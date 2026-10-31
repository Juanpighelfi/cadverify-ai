"""Spec adjustments toward the measurement: the harness flags them, and the close must tell them.

A spec is the design intent; when a check fails, the fix is the geometry. A spec that moves to
what the mesh already measured, while the mesh stays the same, makes the check pass without
changing the part. One early session did it in a single patch, "I adjust the assembly spec to
what was measured": bounds, bodies and holes moved to the mesh after a measured overlap of
638 mm³. It can be right (a spec badly posed against the request), so the harness does not
refuse it: it says so in the tool result, and G8 asks the close to tell it (agent/closing.py).

An adjustment is a check that failed at the part's previous observation and passes now, when
- the part's mesh is the same (the same STL bytes), whatever changed in the spec; or
- the declared value moved and what the mesh measures there did not (a bounds coordinate, the
  bodies, the through holes, the area of a support face, a detail measured at the same place).
A failing check taken out of the spec with the mesh unchanged is one too. For the assembly: an
overlap the assembly already had, declared now as a permitted interference; a motion that
collided, now with a shorter range that leaves the collision out, or removed. A bounds
coordinate counts when the spec was more than BOUNDS_FLAG_MM off the mesh: less is the rounding
of a spec formula (one early session flagged 61 adjustments, 18 of them of 0.2 to 1 mm).

The harness cannot tell a spec formula fixed from a defect hidden: what it asks is that the close
tells them. Each observation gives the model one short note per part (notes). When the checked
value stayed and something else of the declaration moved (a detail's box, its tolerance), the
note says what moved: the first session that reached G7 was told "plate from 0.9 to 0.9".

Observations come from the model's exports with the default parameters (scad_export, and
interference_check for the assembly) and from the orchestrator's verification of every version.
"""

from __future__ import annotations

from typing import Any

COORD_MM = 0.01  # a measured coordinate, a thickness or a diameter that did not move
BOUNDS_FLAG_MM = 1.0  # the smallest protrusion seen hidden by moving the bounds was 2 mm
MAX_NOTE_ITEMS = 10
AREA_REL = 0.005
FRACTION = 0.002
VOLUME_REL = 0.02
ASSEMBLY = "assembly"
_SIDES = ((0, "min"), (1, "max"))


class SpecHistory:
    def __init__(self) -> None:
        self.parts: dict[str, dict[str, Any]] = {}  # label -> last observation
        self.assembly: dict[str, Any] | None = None
        self.adjustments: list[dict[str, Any]] = []
        self._seen: set[tuple] = set()

    def observe_part(self, label: str, export: dict[str, Any], seq: int | None = None) -> list:
        """An export of a part with the default parameters. Returns the new adjustments."""
        if not export.get("ok") or not export.get("spec") or not export.get("spec_check"):
            return []
        observation = {"items": part_items(export), "sha256": export.get("sha256")}
        previous = self.parts.get(label)
        self.parts[label] = observation
        if previous is None:
            return []
        same = previous["sha256"] is not None and previous["sha256"] == observation["sha256"]
        return self._record(label, _compare(previous["items"], observation["items"], same), seq)

    def observe_assembly(self, report: dict[str, Any], seq: int | None = None) -> list:
        """An assembly report (cadcheck.assembly). Returns the new adjustments."""
        if "problems" not in report or not report.get("instances"):
            return []
        observation = {
            "shas": sorted((i["name"], i.get("sha256")) for i in report["instances"]),
            "items": _assembly_items(report),
            "pairs": {frozenset((p["a"], p["b"])): p for p in report.get("pairs") or []},
            "motions": {m["name"]: m for m in report.get("motions") or []},
        }
        previous = self.assembly
        self.assembly = observation
        if previous is None:
            return []
        same = previous["shas"] == observation["shas"] and None not in dict(observation["shas"])
        found = _compare(previous["items"], observation["items"], same)
        for key, old in previous["pairs"].items():
            new = observation["pairs"].get(key)
            if not (old.get("interference") and new and new.get("permitted") is not None):
                continue
            volume = old["volume_mm3"]
            if abs(new.get("volume_mm3", 0) - volume) <= max(0.01, VOLUME_REL * volume):
                a, b = sorted(key)
                found.append(
                    {
                        "item": f"interference {a} / {b}",
                        "from": "not declared",
                        "to": f"permitted ({new['permitted']})",
                        "measured": f"{volume} mm³, {old.get('thickness_mm')} mm thick",
                        "why": "the overlap was already there and the geometry did not remove it",
                    }
                )
        for name, old in previous["motions"].items():
            hits = (old.get("collisions") or {}).get("from_to")
            if old.get("ok") or not hits:
                continue
            new = observation["motions"].get(name)
            if new is None:
                if same:
                    found.append(
                        {
                            "item": f"motion {name}",
                            "from": old["range"],
                            "to": "removed",
                            "measured": f"collided between {hits[0]:g} and {hits[1]:g}",
                            "why": "a motion that collided left the spec, with the parts unchanged",
                        }
                    )
                continue
            lo, hi = new["range"]
            shorter = lo > old["range"][0] or hi < old["range"][1]
            outside = hits[1] < min(lo, 0.0) or hits[0] > max(hi, 0.0)
            if new.get("ok") and shorter and (same or outside):
                found.append(
                    {
                        "item": f"motion {name}",
                        "from": old["range"],
                        "to": new["range"],
                        "measured": f"collided between {hits[0]:g} and {hits[1]:g}",
                        "why": "the range got shorter and leaves the collision out",
                    }
                )
        return self._record(ASSEMBLY, found, seq)

    def _record(self, label: str, found: list[dict], seq: int | None) -> list[dict]:
        new = []
        for item in found:
            key = (label, item["item"], str(item["from"]), str(item["to"]))
            if key in self._seen:
                continue
            self._seen.add(key)
            adjustment = {"part": label, "seq": seq, **item}
            adjustment["text"] = describe(adjustment)
            self.adjustments.append(adjustment)
            new.append(adjustment)
        return new


def describe(adjustment: dict[str, Any]) -> str:
    """One adjustment in a few words: what moved, from what to what, and what the mesh says."""
    return (
        f"{adjustment['item']} from {adjustment['from']} to {adjustment['to']}, the mesh measures "
        f"{adjustment['measured']} ({adjustment['why']})"
    )


def notes(adjustments: list[dict[str, Any]]) -> list[str]:
    """One note per part for the model: the adjustments and what to do about them."""
    parts: dict[str, list[str]] = {}
    for adjustment in adjustments:
        parts.setdefault(adjustment["part"], []).append(adjustment["text"])
    out = []
    for part, items in parts.items():
        listed = "; ".join(items[:MAX_NOTE_ITEMS])
        if len(items) > MAX_NOTE_ITEMS:
            listed += f"; and {len(items) - MAX_NOTE_ITEMS} more"
        out.append(
            f"{part}: the spec moved toward what the mesh already measured: {listed}. That way "
            "those checks pass without the part changing. If the spec was badly posed against the "
            "request, that is fine: say so in the close, with the reason (once per part is "
            "enough). If not, fix the geometry."
        )
    return out


# ---- what is compared ---------------------------------------------------------------------


def _item(
    spec: Any, measured: Any, ok: bool, kind: str, where: Any = None, decl: dict | None = None
) -> dict[str, Any]:
    """One check: the declared value, the measured one, whether it passes, how to compare them,
    where it is measured and the whole declaration (to tell what moved besides the value)."""
    return {
        "spec": spec,
        "measured": measured,
        "ok": bool(ok),
        "kind": kind,
        "where": where,
        "decl": decl or {},
    }


def part_items(export: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Every check of a part's spec: what it declares, what the mesh measures, whether it
    passes."""
    spec, check, mesh = export["spec"], export["spec_check"], export.get("mesh") or {}
    items: dict[str, dict[str, Any]] = {}
    if spec.get("bounds") is not None and mesh.get("bounds"):
        items.update(_bounds_items(spec["bounds"], mesh["bounds"], check.get("bounds") or {}))
    for key in ("bodies", "through_holes"):
        if key in check:
            items[key] = _item(check[key]["expected"], check[key]["actual"], check[key]["ok"], "n")
    for face in check.get("support_faces") or []:
        items[f"support face {face['name']}"] = _item(
            face["min_area_mm2"],
            face["area_on_extreme_plane_mm2"],
            face["ok"],
            "area",
            face["direction"],
        )
    declared = {d["name"]: d for d in spec.get("details") or []}
    for result in check.get("details") or []:
        detail = declared.get(result["name"])
        if detail is None:
            continue
        items[f"detail {result['name']}"] = {
            **_detail_item(detail, result),
            "decl": {k: v for k, v in detail.items() if k != "name"},
        }
    return items


def _bounds_items(spec_bounds, measured, check) -> dict[str, dict[str, Any]]:
    failing = " ".join(check.get("deviations") or [])
    items = {}
    for side, label in _SIDES:
        for axis in range(3):
            name = f"{label} {'xyz'[axis]}"
            items[f"bounds {name}"] = _item(
                spec_bounds[side][axis],
                measured[side][axis],
                f"{name}:" not in failing,
                "coord",
            )
    return items


def _detail_item(detail: dict[str, Any], result: dict[str, Any]) -> dict[str, Any]:
    kind = detail["kind"]
    if kind in ("material", "void", "view"):
        return _item(
            detail.get("fraction"),
            result.get("material_fraction"),
            result["ok"],
            "fraction",
            detail["box"],
        )
    where = [detail["point"], detail["direction"]]
    if kind == "thickness":
        return _item(detail["mm"], result.get("measured_mm"), result["ok"], "coord", where)
    measured = [c["measured_mm"] for c in result.get("diameters") or []]
    depths = [d for d, _ in detail["diameters"]]
    wanted = [w for _, w in detail["diameters"]]
    return _item(wanted, measured or None, result["ok"], "coord", [*where, depths])


def _assembly_items(report: dict[str, Any]) -> dict[str, dict[str, Any]]:
    check = report.get("spec_check") or {}
    spec = report.get("spec") or {}
    items: dict[str, dict[str, Any]] = {}
    if spec.get("bounds") is not None and check.get("measured_bounds"):
        items.update(_bounds_items(spec["bounds"], check["measured_bounds"], check["bounds"]))
    for face in check.get("support_faces") or []:
        items[f"support face {face['name']}"] = _item(
            face["min_area_mm2"],
            face["area_on_extreme_plane_mm2"],
            face["ok"],
            "area",
            face["direction"],
        )
    return items


def _compare(previous: dict, current: dict, same_mesh: bool) -> list[dict[str, Any]]:
    found = []
    for key, old in previous.items():
        if old["ok"]:
            continue
        new = current.get(key)
        if new is None:
            if same_mesh:
                found.append(
                    {
                        "item": key,
                        "from": old["spec"],
                        "to": "removed",
                        "measured": old["measured"],
                        "why": "a failing check left the spec, with the mesh unchanged",
                    }
                )
            continue
        if not new["ok"]:
            continue
        if key.startswith("bounds") and abs(old["spec"] - old["measured"]) <= BOUNDS_FLAG_MM:
            continue
        if same_mesh:
            why = "the mesh is the same"
        elif new["where"] == old["where"] and _same(old["measured"], new["measured"], old["kind"]):
            why = "what was measured did not change"
        else:
            continue
        before, after = old["spec"], new["spec"]
        if before == after and (moved := _moved(old["decl"], new["decl"])):
            before = "; ".join(f"{field} {a}" for field, (a, _) in moved.items())
            after = "; ".join(f"{field} {b}" for field, (_, b) in moved.items())
        found.append(
            {
                "item": key,
                "from": before,
                "to": after,
                "measured": new["measured"],
                "why": why,
            }
        )
    return found


def _moved(old: dict[str, Any], new: dict[str, Any]) -> dict[str, tuple[Any, Any]]:
    """The fields of a declaration that changed: {field: (before, after)}."""
    return {
        k: (old.get(k), new.get(k)) for k in sorted(set(old) | set(new)) if old.get(k) != new.get(k)
    }


def _same(a: Any, b: Any, kind: str) -> bool:
    if isinstance(a, list) or isinstance(b, list):
        return (
            isinstance(a, list)
            and isinstance(b, list)
            and len(a) == len(b)
            and all(_same(x, y, kind) for x, y in zip(a, b, strict=True))
        )
    if a is None or b is None:
        return a is b
    if kind == "n":
        return a == b
    if kind == "area":
        return abs(a - b) <= AREA_REL * max(abs(a), abs(b), 1e-9)
    if kind == "fraction":
        return abs(a - b) <= FRACTION
    return abs(a - b) <= COORD_MM
