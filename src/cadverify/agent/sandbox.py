"""One hardened cadverify-sandbox container per session, and a fresh one per verification.

The session container is where the model's code runs (run_shell, run_python) and where every
tool runs, as `docker exec <container> cadcheck ...` answering JSON:
- no network; 2 CPUs, 4 GB of memory without swap, 512 processes; no capabilities and no new
  privileges; a read-only root file system;
- the only writable places are /work, a 1 GB tmpfs owned by the session's user, and /tmp, a
  512 MB tmpfs (plus Docker's 64 MB /dev/shm). They live in the container's memory, so filling
  them never touches the host's disk;
- every exec runs as a user id drawn for the session (20001-29999), never used by the host or by
  another session. The process limit per user and `reap` (kill every process of that user)
  cover exactly the session's processes; the container's init and its `sleep` run as nobody;
- /app (the repository's tests), the orchestrator's agent package (prompts, gates, the auditor)
  and the package's file list are hidden under empty read-only tmpfs mounts: the container keeps
  cadcheck, and what the model reads of the harness is what its tools tell it. Nothing private
  is mounted, and the docker CLI runs with an allowlisted environment, without MODEL_API_KEY.

The host keeps a mirror of /work in the run directory. After every tool call the orchestrator
reads the manifest (`cadcheck manifest`, run after `reap`, so no model process is alive) and
copies the files that changed as a tar stream, unpacked with the "data" filter: regular files
only, never outside the mirror. The host never executes or imports anything from the workspace.

The gates are verified in a new container per source version (`verify`): it receives only the
.scad files, from the mirror, exports into its own tmpfs and is removed. The model cannot reach
it, nor the exports it measures.
"""

from __future__ import annotations

import io
import json
import os
import secrets
import subprocess
import tarfile
import uuid
from pathlib import Path
from typing import Any

IMAGE = "cadverify-sandbox"
WORKDIR = "/work"
SITE = "/opt/venv/lib/python3.12/site-packages/cadverify"
# The repository's tests, the orchestrator's agent package and the package's file list: the
# harness's own code, which the model's code has no reason to read.
HIDDEN = ("/app", f"{SITE}/agent", f"{SITE}-0.1.0.dist-info")
CPUS, MEMORY, PIDS = "2", "4g", "512"
WORK_SIZE, TMP_SIZE = "1g", "512m"
# Grace on top of a tool's own timeout before the orchestrator gives up on the exec.
EXEC_GRACE_S = 30
VERIFY_TIMEOUT_S = 900
# The mirror copies a changed file up to this size, and up to this many bytes per session;
# the rest is listed in the result as not copied. .scad files are always copied, up to
# SOURCE_MAX_BYTES in all (the verification needs them).
MIRROR_MAX_FILE = 20_000_000
MIRROR_MAX_TOTAL = 300_000_000
SOURCE_MAX_BYTES = 2_000_000
DOCKER_ENV = ("PATH", "HOME", "LANG", "DOCKER_HOST", "DOCKER_CONFIG", "DOCKER_CONTEXT")


def docker_env() -> dict[str, str]:
    """The docker CLI's environment: an allowlist, so no secret of the orchestrator's
    environment (MODEL_API_KEY) can reach a container through it."""
    return {k: v for k, v in os.environ.items() if k in DOCKER_ENV}


def hardening(uid: int) -> list[str]:
    """`docker run` flags shared by the session and the verification containers."""
    flags = [
        "--init", "--network", "none", "--cpus", CPUS, "--memory", MEMORY, "--memory-swap", MEMORY,
        "--pids-limit", PIDS, "--ulimit", "core=0",
        "--read-only", "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
        "--log-driver", "none",
        "--tmpfs", f"{WORKDIR}:size={WORK_SIZE},uid={uid},gid={uid},mode=0700,exec",
        "--tmpfs", f"/tmp:size={TMP_SIZE},mode=1777",
        "-e", "HOME=/tmp", "-w", WORKDIR,
    ]  # fmt: skip
    for path in HIDDEN:
        flags += ["--tmpfs", f"{path}:ro,size=4k,mode=0555"]
    return flags


def session_uid() -> int:
    return 20001 + secrets.randbelow(9999)


def tar_bytes(files: dict[str, bytes]) -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as tar:
        for rel, data in sorted(files.items()):
            info = tarfile.TarInfo(rel)
            info.size = len(data)
            info.mode = 0o644
            tar.addfile(info, io.BytesIO(data))
    return buffer.getvalue()


class Sandbox:
    def __init__(self, workspace: Path, image: str = IMAGE):
        self.workspace = workspace.resolve()  # the host mirror of /work
        self.image = image
        self.name = f"cadverify-{uuid.uuid4().hex[:10]}"
        self.uid = session_uid()
        self.started = False
        self.files: dict[str, list] = {}  # last manifest: path -> [size, mtime_ns, sha256]
        self.mirrored_bytes = 0

    def __enter__(self) -> Sandbox:
        self.start()
        return self

    def __exit__(self, *exc: object) -> None:
        self.stop()

    def start(self) -> None:
        self.workspace.mkdir(parents=True, exist_ok=True)
        # The container's own processes (init, sleep) run as nobody: reap cannot kill them.
        cmd = ["docker", "run", "-d", "--name", self.name, *hardening(self.uid)]
        cmd += ["--user", "65534:65534", self.image, "sleep", "infinity"]
        subprocess.run(
            cmd, check=True, capture_output=True, text=True, timeout=120, env=docker_env()
        )
        self.started = True

    def stop(self) -> None:
        if self.started:
            cmd = ["docker", "rm", "-f", self.name]
            subprocess.run(cmd, capture_output=True, timeout=120, env=docker_env())
            self.started = False

    # ---- execs ----------------------------------------------------------------------------

    def exec(
        self, argv: list[str], stdin: bytes = b"", timeout_s: float = 120
    ) -> subprocess.CompletedProcess | None:
        """Run argv in the container as the session's user; None when the exec timed out (what
        it left running is killed with reap)."""
        cmd = ["docker", "exec", "-i", "--user", f"{self.uid}:{self.uid}", "-w", WORKDIR]
        try:
            return subprocess.run(
                [*cmd, self.name, *argv],
                input=stdin,
                capture_output=True,
                timeout=timeout_s,
                env=docker_env(),
            )
        except subprocess.TimeoutExpired:
            self.reap()
            return None

    def cadcheck(self, args: list[str], stdin: str | None = None, timeout_s: float = 300) -> dict:
        """Run `cadcheck <args>` in the container and return its JSON result."""
        proc = self.exec(["cadcheck", *args], (stdin or "").encode(), timeout_s)
        if proc is None:
            return {"ok": False, "error": f"The tool ran over {timeout_s:.0f} s and was stopped"}
        try:
            result: dict[str, Any] = json.loads(proc.stdout)
        except json.JSONDecodeError:
            return {
                "ok": False,
                "error": "The tool failed without returning JSON",
                "stderr": proc.stderr.decode(errors="replace")[-2000:],
            }
        return result

    def reap(self) -> dict:
        """Kill every process of the session's user (what the model's code left running)."""
        cmd = ["docker", "exec", "--user", f"{self.uid}:{self.uid}", self.name, "cadcheck", "reap"]
        proc = subprocess.run(cmd, capture_output=True, timeout=60, env=docker_env())
        try:
            return json.loads(proc.stdout)
        except json.JSONDecodeError:
            return {"ok": False, "error": proc.stderr.decode(errors="replace")[-500:]}

    # ---- the mirror -----------------------------------------------------------------------

    def sync(self) -> dict[str, Any]:
        """Read the manifest and bring the mirror up to date. Returns what changed since the
        last sync, and the SHA-256 of every .scad file."""
        manifest = self.cadcheck(["manifest"], timeout_s=120)
        if "files" not in manifest:
            return {"ok": False, "error": manifest.get("error", "manifest failed")}
        files: dict[str, list] = manifest["files"]
        old = self.files
        new = sorted(p for p in files if p not in old)
        modified = sorted(p for p in files if p in old and files[p] != old[p])
        deleted = sorted(p for p in old if p not in files)
        scad_bytes = sum(v[0] for v in files.values() if v[2] is not None)
        pull, skipped = [], []
        for path in new + modified:
            size, _, sha = files[path]
            if sha is not None and scad_bytes <= SOURCE_MAX_BYTES:
                pull.append(path)
            elif size <= MIRROR_MAX_FILE and self.mirrored_bytes + size <= MIRROR_MAX_TOTAL:
                pull.append(path)
                self.mirrored_bytes += size
            else:
                skipped.append(path)
        self._remove_local(deleted + skipped)
        pulled = self.pull(pull)
        self.files = files
        return {
            "ok": True,
            "new": new,
            "modified": modified,
            "deleted": deleted,
            "not_mirrored": skipped + [p for p in pull if p not in pulled],
            "truncated": manifest.get("truncated", False),
            "other": manifest.get("other", []),
            "scad": {p: v[2] for p, v in files.items() if v[2] is not None},
            "scad_bytes": scad_bytes,
        }

    def pull(self, paths: list[str]) -> set[str]:
        """Copy these files of /work into the mirror; returns the ones copied."""
        if not paths:
            return set()
        listing = b"\0".join(p.encode() for p in paths) + b"\0"
        proc = self.exec(["tar", "-C", WORKDIR, "--null", "-T", "-", "-cf", "-"], listing, 300)
        if proc is None or not proc.stdout:
            return set()
        wanted, copied = set(paths), set()
        with tarfile.open(fileobj=io.BytesIO(proc.stdout), mode="r:") as tar:
            for member in tar:
                if not member.isreg() or member.name not in wanted:
                    continue
                self._remove_local([member.name])
                try:
                    tar.extract(member, self.workspace, filter="data")
                except (tarfile.FilterError, OSError):
                    continue
                copied.add(member.name)
        return copied

    def restore(self, files: dict[str, bytes | None]) -> None:
        """Write these files back into /work (None deletes one), then sync the mirror."""
        write = {p: d for p, d in files.items() if d is not None}
        if write:
            self.exec(["tar", "-C", WORKDIR, "-xf", "-"], tar_bytes(write), 120)
        delete = [p for p, d in files.items() if d is None]
        if delete:
            self.exec(["rm", "-f", "--", *delete], b"", 60)
        self.sync()

    def _remove_local(self, paths: list[str]) -> None:
        for rel in paths:
            path = (self.workspace / rel).resolve()
            if path.is_relative_to(self.workspace) and path.is_file() and not path.is_symlink():
                path.unlink()

    # ---- verification ---------------------------------------------------------------------

    def verify(
        self,
        sources: dict[str, bytes],
        main: str,
        assembly: bool = False,
        requirements: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """`cadcheck verify` of `main` in a new container that holds only these sources; with
        `assembly`, the assembly too (cadcheck.assembly), with the request's `requirements`."""
        uid = session_uid()
        name = f"cadverify-verify-{uuid.uuid4().hex[:10]}"
        script = 'tar -x -C /work -f - && exec cadcheck verify "$0" --out-dir /work/checks/exports'
        extra = [json.dumps(requirements or {})] if assembly else []
        if assembly:
            script += ' --assembly --requirements "$1"'
        cmd = ["docker", "run", "--rm", "-i", "--name", name, *hardening(uid)]
        cmd += ["--user", f"{uid}:{uid}", self.image, "sh", "-c", script, main, *extra]
        try:
            proc = subprocess.run(
                cmd,
                input=tar_bytes(sources),
                capture_output=True,
                timeout=VERIFY_TIMEOUT_S,
                env=docker_env(),
            )
        except subprocess.TimeoutExpired:
            subprocess.run(["docker", "rm", "-f", name], capture_output=True, env=docker_env())
            return {"ok": False, "error": f"verify ran over {VERIFY_TIMEOUT_S} s"}
        try:
            return json.loads(proc.stdout)
        except json.JSONDecodeError:
            return {
                "ok": False,
                "error": "verify failed without returning JSON",
                "stderr": proc.stderr.decode(errors="replace")[-2000:],
            }
