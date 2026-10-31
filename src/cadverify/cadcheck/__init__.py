"""cadcheck: deterministic CAD tools with compact JSON output, run inside the sandbox image.

The tools are imported on first use (PEP 562): the light commands the orchestrator runs on
every call (`run`, `reap`, `manifest`) start without loading trimesh.
"""

from importlib import import_module

_EXPORTS = {
    "mesh_report": "cadverify.cadcheck.mesh",
    "Engine": "cadverify.cadcheck.scad",
    "scad_compile": "cadverify.cadcheck.scad",
    "scad_export": "cadverify.cadcheck.scad",
}

__all__ = sorted(_EXPORTS)


def __getattr__(name: str):
    if name in _EXPORTS:
        return getattr(import_module(_EXPORTS[name]), name)
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
