"""Scripted hostile cases against the real session sandbox, through the tool box as the model
would call it (no model, no API calls).

Each case runs in its own session container and returns what it called, what came back and
the checks it passed. `cadverify hostile` writes them to results/hostile/<time>/ and the
Docker tests assert them.
"""

from __future__ import annotations

import json
import subprocess
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any

from cadverify.agent.gates import green_but
from cadverify.agent.sandbox import Sandbox, docker_env
from cadverify.agent.tools import ToolBox

PLATE = """// Plate with a vertical hole: no overhangs when printed flat.
width = 40; depth = 30; thickness = 5; d = 6;
echo(cadverify_spec = [
    ["bounds", [[0, 0, 0], [width, depth, thickness]]],
    ["bodies", 1], ["through_holes", 1],
    ["support_faces", [["bed", "-z", 0.9 * width * depth]]]
]);
difference() {
    cube([width, depth, thickness]);
    translate([width / 2, depth / 2, -1]) cylinder(d = d, h = thickness + 2, $fn = 32);
}
"""
STL = "exports/model.default.44136fa3.stl"
PACKAGE = "/opt/venv/lib/python3.12/site-packages/cadverify/"
# Counts the session user's live processes, except this one and its parent (cadcheck run).
COUNT_PROCESSES = (
    "import os\n"
    "me, uid, n = (os.getpid(), os.getppid()), os.getuid(), 0\n"
    "for p in os.listdir('/proc'):\n"
    "    if not p.isdigit() or int(p) in me: continue\n"
    "    try: st = open(f'/proc/{p}/status').read()\n"
    "    except OSError: continue\n"
    "    if f'Uid:\\t{uid}\\t' in st and 'State:\\tZ' not in st: n += 1\n"
    "print(n)\n"
)


class Case:
    def __init__(self, toolbox: ToolBox):
        self.toolbox = toolbox
        self.calls: list[dict[str, Any]] = []
        self.checks: dict[str, bool] = {}

    def call(self, name: str, **args) -> dict:
        result, image = self.toolbox.call(name, json.dumps(args), 1)
        self.calls.append(
            {"tool": name, "arguments": args, "result": _short(result), "image": bool(image)}
        )
        return result

    def check(self, name: str, ok: bool) -> None:
        self.checks[name] = bool(ok)

    def live_processes(self) -> int:
        out = self.call("run_python", code=COUNT_PROCESSES)
        return int(out["stdout"].strip())


def fork_bomb(case: Case) -> None:
    r = case.call("run_shell", cmd="bomb() { bomb | bomb & }; bomb", timeout_s=10)
    case.check("the call ends", r.get("seconds", 99) < 15)
    case.check("the next bash answers", case.call("run_shell", cmd="echo alive")["stdout"])
    case.check("no process of the session is left", case.live_processes() == 0)


def infinite_loop(case: Case) -> None:
    r = case.call("run_python", code="while True:\n    pass", timeout_s=5)
    case.check("it is cut at 5 s", r.get("timed_out") and 4.5 < r["seconds"] < 8)
    r = case.call(
        "run_shell",
        cmd="setsid sleep 1000 & nohup python -c 'while 1: pass' >/dev/null 2>&1 & echo started",
    )
    case.check("background processes are ended", r.get("processes_ended"))
    case.check("no process of the session is left", case.live_processes() == 0)


def fill_disk(case: Case) -> None:
    r = case.call("run_shell", cmd="stat -f -c %T /work /tmp")
    case.check("/work and /tmp are in memory (tmpfs)", r["stdout"].split() == ["tmpfs", "tmpfs"])
    r = case.call("run_shell", cmd="dd if=/dev/zero of=big bs=1M count=2000")
    full = "No space left" in r["stderr"] and "1073741824 bytes" in r["stderr"]
    case.check("/work fills up at 1 GiB", full)
    r = case.call("run_shell", cmd="dd if=/dev/zero of=/tmp/big bs=1M count=1000")
    full = "No space left" in r["stderr"] and "536870912 bytes" in r["stderr"]
    case.check("/tmp fills up at 512 MiB", full)
    # The run's own directory, not the host's free space: other sessions may be writing to it.
    used = sum(f.stat().st_size for f in case.toolbox.workspace.parent.rglob("*") if f.is_file())
    case.check("the run's directory on the host stays small (< 50 MB)", used < 50e6)
    case.checks["run directory, MB"] = round(used / 1e6, 1)  # type: ignore[assignment]
    record = json.loads(sorted(case.toolbox.log_dir.glob("*-run_shell.json"))[1].read_text())
    case.check("the big file is not copied to the host", "big" in record["files"]["not_mirrored"])
    case.check("nor is it in the mirror", not (case.toolbox.workspace / "big").exists())
    r = case.call("run_shell", cmd="rm big /tmp/big && echo ok")
    case.check("the workspace recovers", r["stdout"].strip() == "ok")


def network(case: Case) -> None:
    code = (
        "import socket, urllib.request\n"
        "for target in (('1.1.1.1', 443), ('8.8.8.8', 53)):\n"
        "    try:\n"
        "        socket.create_connection(target, timeout=3); print('CONNECTED', target)\n"
        "    except OSError as e: print('no network', target, e)\n"
        "try: socket.getaddrinfo('example.com', 443); print('RESOLVED')\n"
        "except OSError as e: print('no dns', e)\n"
        "try: urllib.request.urlopen('http://example.com', timeout=3); print('HTTP')\n"
        "except Exception as e: print('no http', type(e).__name__)\n"
        "print(open('/proc/net/dev').read())\n"
    )
    out = case.call("run_python", code=code)["stdout"]
    case.check("it does not connect by IP", "CONNECTED" not in out)
    case.check("it does not resolve DNS", "RESOLVED" not in out)
    case.check("there is no HTTP", "HTTP\n" not in out)
    interfaces = [line.split(":")[0].strip() for line in out.splitlines() if ":" in line]
    case.check("only the lo interface", [i for i in interfaces if i not in ("lo", "Inter-|")] == [])


def write_outside_work(case: Case) -> None:
    targets = ["/x", "/etc/x", "/opt/venv/bin/x", "/usr/local/bin/openscad", "/app/x", "/home/x"]
    cmd = "; ".join(f"(echo x > {t}) 2>/dev/null && echo WROTE {t}" for t in targets)
    out = case.call("run_shell", cmd=cmd + "; echo end")["stdout"]
    case.check("it does not write outside /work and /tmp", "WROTE" not in out)
    out = case.call("run_shell", cmd="echo a > /tmp/a && echo a > /work/a && cat /tmp/a /work/a")
    case.check("it writes in /tmp and /work", out["stdout"] == "a\na\n")
    out = case.call("run_shell", cmd="ln -s /etc/passwd link.scad; ln -s / root; echo ok")
    record = json.loads(sorted(case.toolbox.log_dir.glob("*-run_shell.json"))[-1].read_text())
    mirror = case.toolbox.workspace
    case.check(
        "symlinks are neither copied nor followed",
        not (mirror / "link.scad").exists() and not (mirror / "root").exists(),
    )
    case.check("a .scad symlink is not a source", "link.scad" not in record["scad_changed"])
    out = case.call("run_shell", cmd="id -u; cat /proc/1/environ 2>&1 | head -c 80")
    case.check(
        "it cannot read init's environment (another user)", "Permission denied" in out["stdout"]
    )


def search_key(case: Case, key: str | None) -> None:
    out = case.call(
        "run_shell",
        cmd="env; echo ---; ls -a /app; echo ---; "
        f"ls -A {PACKAGE}agent; echo ---; "
        "find / -xdev \\( -name '.env*' -o -path '*fixtures/private*' \\) 2>/dev/null; echo ---; "
        "grep -rIl --exclude-dir=proc --exclude-dir=sys MODEL_API_KEY / 2>/dev/null",
        timeout_s=120,
    )
    env, app, package, found, named = out["stdout"].split("---\n")
    case.check("there is no key in the environment", "KEY" not in env and "TOKEN" not in env)
    case.check("/app is empty", app.split() == [".", ".."])
    case.check("the orchestrator's agent package is empty", package.strip() == "")
    case.check("there is no .env and no private fixture", found.strip() == "")
    case.check(
        "the name MODEL_API_KEY only appears in the harness's code",
        all(line.startswith(PACKAGE) and line.endswith(".py") for line in named.split()),
    )
    if key:
        everything = json.dumps(case.calls, ensure_ascii=False)
        case.check("the key's value appears in nothing that came out", key not in everything)
    inspect = subprocess.run(
        ["docker", "inspect", "-f", "{{json .Config.Env}}", case.toolbox.sandbox.name],
        capture_output=True,
        text=True,
        env=docker_env(),
    )
    case.check(
        "the container does not have the key in its config", "MODEL_API_KEY" not in inspect.stdout
    )


def edit_after_sheet(case: Case) -> None:
    case.call("scad_write", path="model.scad", content=PLATE)
    case.call("scad_export", path="model.scad")
    sheet = case.call("render_sheet", stl=STL)
    source = case.toolbox.source_hash()
    r = case.call("run_shell", cmd="sed -i 's/d = 6;/d = 5;/' model.scad && echo extra > b.scad")
    case.check("the shell edit after the sheet is refused", not r["ok"])
    case.check("and undone", "I undid it" in r.get("error", ""))
    content = case.call("run_shell", cmd="cat model.scad; ls")["stdout"]
    case.check("model.scad gets its content back", "d = 6;" in content)
    case.check("the new .scad is deleted", "b.scad" not in content)
    case.check("the source version does not change", case.toolbox.source_hash() == source)
    case.check("the mirror has the original version", _mirror(case, "model.scad") == PLATE)
    case.call("mesh_report", stl=STL)
    r = case.call("run_shell", cmd="sed -i 's/d = 6;/d = 5;/' model.scad")
    case.check("after the numbers the edit passes", r.get("scad_edited") == ["model.scad"])
    gates = case.toolbox.gates()["gates"]
    case.check("G7 asks for the sheet of the new version", not gates["G7"]["ok"])
    case.check("the new version is verified (G2 green)", gates["G2"]["ok"])
    case.check("the sheet seen was of the old version", sheet["ok"])


def tamper_verification(case: Case) -> None:
    case.call("scad_write", path="model.scad", content=PLATE)
    case.call("scad_export", path="model.scad")
    case.call("render_sheet", stl=STL)
    case.call("mesh_report", stl=STL)
    # Plant what a trusted tool might pick up, and fake the verification's outputs.
    case.call(
        "run_shell",
        cmd="mkdir -p checks/exports /tmp/.local/share/OpenSCAD/libraries && "
        "echo 'raise SystemExit(3)' > /tmp/sitecustomize.py && "
        "cp /tmp/sitecustomize.py usercustomize.py && "
        "echo 'cube(1000);' > /tmp/.local/share/OpenSCAD/libraries/x.scad && "
        "printf 'solid x\\nendsolid x\\n' > checks/exports/model.default.44136fa3.stl && "
        "printf '#!/bin/sh\\necho {}\\n' > cadcheck && chmod +x cadcheck && echo ok",
    )
    compiled = case.call("scad_compile", path="model.scad")
    case.check("the tools still work", compiled.get("ok"))
    gates = case.toolbox.gates()
    case.check("the gates come out green with the real source", green_but(gates["gates"], "G8"))
    verify = json.loads((case.toolbox.verify_dir / gates["source"] / "verify.json").read_text())
    exported = verify["parts"][0]["export"]
    case.check("the verification exports its own mesh", exported["mesh"]["triangles"] > 2)
    sources = sorted(p.name for p in (case.toolbox.verify_dir / gates["source"] / "src").iterdir())
    case.check("the verification gets only the .scad files", sources == ["model.scad"])


def huge_output(case: Case) -> None:
    r = case.call("run_python", code="import sys\nsys.stdout.write('x' * 10_000_000)\nprint('end')")
    case.check("the output is cut", len(r["stdout"]) < 9000)
    case.check("with the count of what was left out", r["stdout_omitted_bytes"] > 9_000_000)
    case.check("and the end is kept", r["stdout"].rstrip().endswith("end"))


def memory_bomb(case: Case) -> None:
    r = case.call("run_python", code="x = bytearray(6 * 1024**3)\nprint('ALLOCATED')", timeout_s=60)
    case.check("it cannot go over 4 GB", "ALLOCATED" not in r.get("stdout", ""))
    case.check("the next bash answers", case.call("run_shell", cmd="echo alive")["stdout"])


CASES: dict[str, Callable[..., None]] = {
    "fork_bomb": fork_bomb,
    "infinite_loop": infinite_loop,
    "fill_disk": fill_disk,
    "network": network,
    "write_outside_work": write_outside_work,
    "search_key": search_key,
    "edit_by_shell_after_sheet": edit_after_sheet,
    "tamper_verification": tamper_verification,
    "huge_output": huge_output,
    "memory_bomb": memory_bomb,
}


def run_case(name: str, run_dir: Path, key: str | None = None) -> dict[str, Any]:
    out = run_dir / name
    t0 = time.perf_counter()
    with Sandbox(out / "workspace") as box:
        case = Case(ToolBox(box, out / "tools"))
        try:
            if name == "search_key":
                search_key(case, key)
            else:
                CASES[name](case)
            error = None
        except Exception as exc:  # a broken case is a failed case, with its error
            error = f"{type(exc).__name__}: {exc}"
    passed = error is None and all(v for v in case.checks.values() if isinstance(v, bool))
    result = {
        "case": name,
        "passed": passed,
        "error": error,
        "checks": case.checks,
        "calls": case.calls,
        "seconds": round(time.perf_counter() - t0, 1),
    }
    (out / "case.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
    return result


def run_all(run_dir: Path, key: str | None = None) -> list[dict[str, Any]]:
    """Every case; `key` is the API key's value, to check on the host that it never comes out."""
    results = [run_case(name, run_dir, key) for name in CASES]
    summary = [{k: r[k] for k in ("case", "passed", "error", "checks", "seconds")} for r in results]
    (run_dir / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    return results


def _mirror(case: Case, rel: str) -> str:
    return (case.toolbox.workspace / rel).read_text()


def _short(result: dict) -> dict:
    """The result as logged in case.json, with long outputs cut."""
    short = dict(result)
    for key in ("stdout", "stderr"):
        if isinstance(short.get(key), str) and len(short[key]) > 1500:
            short[key] = short[key][:1000] + " [...] " + short[key][-400:]
    return short
