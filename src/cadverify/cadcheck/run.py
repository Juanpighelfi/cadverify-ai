"""The model's own code in the sandbox: run_shell / run_python, and what the harness needs
around them. Runs inside the session container, as the session's user.

- `run`: one shell command or Python program in /work, in its own process group, with a
  timeout that kills the whole group, a process limit and the output truncated to its head and
  tail with the count of what was left out. The program's background children may outlive it:
  the orchestrator runs `reap` after every call.
- `reap`: SIGKILL to every process of this user except itself (kill(-1)); the container's init
  and its `sleep` run as another user and survive.
- `manifest`: the regular files under /work with size and mtime, and the SHA-256 of every .scad
  file: the sources the gates verify, wherever they are. Edits are detected by content, not by
  date.
- `normalize_image`: a PNG or JPEG the model made, decoded with a pixel cap and saved as a PNG
  no larger than the given side and pixel count, for view_image.

Only the standard library at import time: these commands run on every tool call.
"""

from __future__ import annotations

import contextlib
import hashlib
import os
import resource
import selectors
import signal
import subprocess
import time
from pathlib import Path
from typing import Any

WORKDIR = "/work"
MAX_CODE_BYTES = 100_000  # one argv string can be up to 128 KiB on Linux
DEFAULT_NPROC = 256  # leaves room under the container's 512 pids for the harness's own execs
DRAIN_AFTER_EXIT_S = 0.5  # background children may keep the pipes open
MAX_MANIFEST_FILES = 20_000

ENV = {
    "PATH": "/opt/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    "HOME": "/tmp",
    "MPLCONFIGDIR": "/tmp/matplotlib",
    "MPLBACKEND": "Agg",
    "LANG": "C.UTF-8",
    "PYTHONUNBUFFERED": "1",
    "OPENSCAD_BIN": "/usr/local/bin/openscad",
    "CADVERIFY_SANDBOX": "1",
}


class _Capture:
    """Keeps the first `head` and the last `tail` bytes of a stream and counts the rest."""

    def __init__(self, limit: int):
        self.head_limit = limit * 3 // 4
        self.tail_limit = limit - self.head_limit
        self.head = bytearray()
        self.tail = bytearray()
        self.total = 0

    def add(self, data: bytes) -> None:
        self.total += len(data)
        room = self.head_limit - len(self.head)
        if room > 0:
            self.head += data[:room]
            data = data[room:]
        if data:
            self.tail += data
            del self.tail[: max(len(self.tail) - self.tail_limit, 0)]

    def text(self) -> str:
        omitted = self.total - len(self.head) - len(self.tail)
        head = self.head.decode("utf-8", errors="replace")
        tail = self.tail.decode("utf-8", errors="replace")
        if omitted > 0:
            return f"{head}\n[... {omitted} bytes left out ...]\n{tail}"
        return head + tail

    @property
    def omitted(self) -> int:
        return max(self.total - len(self.head) - len(self.tail), 0)


def run(
    kind: str,
    code: str,
    timeout_s: float = 60,
    max_stdout: int = 8000,
    max_stderr: int = 4000,
    nproc: int = DEFAULT_NPROC,
    cwd: str = WORKDIR,
) -> dict[str, Any]:
    if kind not in ("shell", "python"):
        return {"ok": False, "error": f"unknown kind {kind!r}"}
    if len(code.encode("utf-8")) > MAX_CODE_BYTES:
        return {
            "ok": False,
            "error": f"The code is over {MAX_CODE_BYTES} bytes: write it in parts",
        }
    argv = ["bash", "-c", code] if kind == "shell" else ["python", "-c", code]

    def limits() -> None:
        resource.setrlimit(resource.RLIMIT_NPROC, (nproc, nproc))
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

    t0 = time.monotonic()
    proc = subprocess.Popen(
        argv,
        cwd=cwd,
        env=ENV,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
        preexec_fn=limits,
    )
    out, err = _Capture(max_stdout), _Capture(max_stderr)
    selector = selectors.DefaultSelector()
    selector.register(proc.stdout, selectors.EVENT_READ, out)
    selector.register(proc.stderr, selectors.EVENT_READ, err)
    deadline = t0 + timeout_s
    timed_out = False
    exited_at = None
    while selector.get_map():
        now = time.monotonic()
        if proc.poll() is not None and exited_at is None:
            exited_at = now
        if exited_at is not None and now - exited_at > DRAIN_AFTER_EXIT_S:
            break  # only background children hold the pipes now; reap kills them
        if now >= deadline and not timed_out:
            timed_out = True
            _kill_group(proc.pid)
            deadline = now + 2  # read what is left, then stop
        elif timed_out and now >= deadline:
            break
        for key, _ in selector.select(timeout=0.1):
            data = os.read(key.fd, 65536)
            if data:
                key.data.add(data)
            else:
                selector.unregister(key.fileobj)
    selector.close()
    try:
        returncode = proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        _kill_group(proc.pid)
        returncode = proc.wait()
    for stream in (proc.stdout, proc.stderr):
        stream.close()
    return {
        "ok": returncode == 0 and not timed_out,
        "exit_code": returncode,
        "timed_out": timed_out,
        "seconds": round(time.monotonic() - t0, 3),
        "stdout": out.text(),
        "stderr": err.text(),
        "stdout_bytes": out.total,
        "stderr_bytes": err.total,
        "stdout_omitted_bytes": out.omitted,
        "stderr_omitted_bytes": err.omitted,
    }


def _kill_group(pid: int) -> None:
    with contextlib.suppress(ProcessLookupError):
        os.killpg(pid, signal.SIGKILL)


def reap(rounds: int = 5) -> dict[str, Any]:
    """Kill every other process of this user; repeat until none is left."""
    uid = os.getuid()
    me = os.getpid()
    killed = 0
    remaining: list[int] = []
    for _ in range(rounds):
        remaining = [p for p in _processes_of(uid) if p != me]
        if not remaining:
            break
        killed += len(remaining)
        with contextlib.suppress(ProcessLookupError):
            os.kill(-1, signal.SIGKILL)  # every process we may signal, except ourselves
        time.sleep(0.05)
        remaining = [p for p in _processes_of(uid) if p != me]
    return {"ok": not remaining, "killed": killed, "remaining": len(remaining)}


def _processes_of(uid: int) -> list[int]:
    pids = []
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        try:
            status = Path(entry.path, "status").read_text()
        except OSError:
            continue
        for line in status.splitlines():
            if line.startswith("Uid:"):
                if int(line.split()[1]) == uid:
                    pids.append(int(entry.name))
                break
            if line.startswith("State:") and "Z" in line.split()[1]:
                break  # a zombie is already dead; its parent (init) reaps it
    return pids


def manifest(root: str = WORKDIR) -> dict[str, Any]:
    """Every regular file under root: {path: [size, mtime_ns, sha256 or None]}.

    The SHA-256 is computed for every .scad file (the sources the gates verify); other files are
    tracked by size and modification time. Symlinks and other non-regular files are listed apart
    and never followed.
    """
    files: dict[str, list] = {}
    other: list[str] = []
    truncated = False
    base = Path(root)
    for directory, dirnames, filenames in os.walk(root, followlinks=False):
        rel_dir = Path(directory).relative_to(base)
        for name in sorted(dirnames):
            if (Path(directory) / name).is_symlink():
                other.append(str(rel_dir / name))
        for name in filenames:
            path = Path(directory) / name
            rel = str(rel_dir / name) if str(rel_dir) != "." else name
            try:
                st = path.lstat()
            except OSError:
                continue
            if not _is_regular(st.st_mode):
                other.append(rel)
                continue
            if len(files) >= MAX_MANIFEST_FILES:
                truncated = True
                continue
            digest = None
            if name.endswith(".scad"):
                with path.open("rb") as f:
                    digest = hashlib.file_digest(f, "sha256").hexdigest()
            files[rel] = [st.st_size, st.st_mtime_ns, digest]
    return {"ok": True, "files": files, "other": sorted(other)[:100], "truncated": truncated}


def _is_regular(mode: int) -> bool:
    import stat

    return stat.S_ISREG(mode)


def normalize_image(
    source: str, out: str, max_side: int, max_pixels: int, root: str = WORKDIR
) -> dict[str, Any]:
    """Decode a PNG or JPEG with a pixel cap and save it as RGB PNG within the limits."""
    from PIL import Image

    base = Path(root).resolve()
    path = (base / source).resolve()
    if not path.is_relative_to(base) or not path.is_file():
        return {"ok": False, "error": f"{source} is not a file of the workspace"}
    Image.MAX_IMAGE_PIXELS = 50_000_000  # a larger image is refused, not decoded
    try:
        with Image.open(path) as image:
            if image.format not in ("PNG", "JPEG"):
                return {"ok": False, "error": f"Only PNG or JPEG; {source} is {image.format}"}
            source_size = list(image.size)
            image.load()
            rgb = image.convert("RGBA")
    except (OSError, Image.DecompressionBombError, ValueError) as exc:
        return {"ok": False, "error": f"Could not read the image: {exc}"}
    flat = Image.new("RGB", rgb.size, "white")
    flat.paste(rgb, mask=rgb.getchannel("A"))
    w, h = flat.size
    scale = min(1.0, max_side / max(w, h), (max_pixels / (w * h)) ** 0.5)
    if scale < 1.0:
        flat = flat.resize(
            (max(1, int(w * scale)), max(1, int(h * scale))), Image.Resampling.LANCZOS
        )
    target = base / out
    target.parent.mkdir(parents=True, exist_ok=True)
    flat.save(target, format="PNG")
    return {"ok": True, "path": out, "source_size": source_size, "size": list(flat.size)}
