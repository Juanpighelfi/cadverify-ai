# Architecture

CADVerify is a design loop with two halves that do not trust each other. Muse Wonder
(`muse-wonder-1.0`, Meta Model API) reads the request, writes OpenSCAD, looks at renders and
decides what to change. A deterministic harness runs every tool, measures every mesh and owns
the verdict: the model cannot end a session while a gate is red.

```
            host (orchestrator, cadverify.agent)                    Meta Model API
 request.md ──► loop.py ──── Responses API, streamed, chained ────► muse-wonder-1.0
                  │  ▲          (tool calls, images, reasoning)          │
     tool calls   │  │ JSON + images                                     │
                  ▼  │                                                   │
          session sandbox container  ◄─── docker exec cadcheck ... ──────┘
          (no network, /work in memory, the model's code runs here)
                  │
                  │ .scad files only
                  ▼
          verification container, new per source version
          (cadcheck verify: compile, export, measure) ──► gates G1..G8 ──► close accepted or refused
```

## The loop

`cadverify.agent.loop.run_session` drives one session. Each iteration is one model request:

1. The model answers with tool calls. The orchestrator runs them in the session sandbox, syncs
   the workspace mirror on the host, and returns each result as JSON (and the image, when the
   tool makes one).
2. After every source change, the harness verifies the current `.scad` files in a fresh
   container and evaluates the gates.
3. A reply without tool calls is a close. The orchestrator accepts it only when every gate is
   green; otherwise the red gates go back to the model with their details.

Before its first edit, a reply without tool calls is a question for the user. It goes out only
after the model has looked at what it was given (the starting source compiled, every part
exported and seen); the user's answer comes back as the next message.

Limits per session: requests, cost and wall time (`cadverify design --max-requests --max-usd
--max-minutes`). About 10 requests before the end the model is told what a close needs; the
last request asks for it. The ledger checks the spend recorded under the results directory
against a total budget before a session starts.

Long sessions are kept alive by:

- streaming every request (a non-streamed request times out at about 600 s on the server, and a
  64k-token response takes longer);
- chaining with `previous_response_id`, while keeping the whole conversation locally: when the
  server loses a stored response, the loop resends the history without it;
- prompt caching (`prompt_cache_key`, 24 h retention), so a long session pays the cached rate
  for most of its input;
- taking old images out of the context once more than 40 are live: each one is replaced by a
  line saying what it showed and the call that shows it again, while the 10 most recent images
  and the last one of every part and of the assembly stay.

## Tools

Twelve tools, all executed by `cadcheck` inside the sandbox (`cadverify.agent.tools`):

| Tool | What it does |
|---|---|
| `scad_write`, `scad_patch` | the only structured way to edit `.scad` files; a patch must match exactly once |
| `scad_compile` | evaluates the program: echoes, warnings, failed asserts, errors |
| `scad_export` | exports a part (`part` selector) to STL with its mesh report and its spec check; a new mesh brings its sheet attached |
| `mesh_report` | watertightness, bad edges and where they are, volume, bounds, bodies |
| `render_sheet` | an orthographic multi-view sheet from our own OpenGL renderer (moderngl on EGL) |
| `render_view` | a view on demand: free camera, zoom, plane cuts with the profile in mm, several parts, highlights (overhangs, support faces, holes, details) |
| `printability_report` | overhangs above 45° by zone in the print orientation, and bed fit (Bambu Lab A1, 256 mm cube) |
| `interference_check` | the assembly measured exactly as gates G3 and G4 measure it |
| `run_shell`, `run_python` | the model's own code in `/work`, with a timeout, output truncation and every process killed after the call |
| `view_image` | an image the model made itself (a plot, a custom render) |

Rules enforced by the harness, not asked for in the prompt:

- **Numbers before fixes.** After an image, the sources cannot change until a numeric check has
  run. A visual finding is a hypothesis; it is confirmed with a measurement before it is fixed.
  A `.scad` edited by shell while blocked is undone.
- **The model sees what it makes.** An export with a mesh the model has not seen brings its
  sheet attached, and G7 asks for the sheet of the exact mesh it verifies (matched by SHA-256).
- **Spec moves are flagged.** When the declared spec moves toward what the mesh already
  measured while the mesh stays the same, the tool result says so (`agent/spec_history.py`),
  and the close must tell the user.

## The verifiable spec

OpenSCAD cannot measure geometry, so the source declares its intent and the harness measures
the mesh against it. The declaration is a structured echo computed from the model's own
parameters (`cadcheck/spec.py`):

```openscad
echo(cadverify_spec = [
    ["bounds", [[0, 0, 0], [shelf_length, wall_height, width]]],
    ["bodies", 1],
    ["through_holes", 3],
    ["support_faces", [["wall", "-x", 0.8 * wall_height * width]]],
    ["overhangs_allowed", [["hole roofs", [[95, -1, 0], [105, 7, 50]]]]],
    ["details", [["wall", "thickness", [x, y, z], [dx, dy, dz], 2.4]]]
]);
```

Details are features measured on the mesh (`cadcheck/details.py`): `material` and `void`
fractions of a box, a `hole` profile along an axis, a `thickness` along a ray, and `view` for a
feature no number describes, which the model must look at up close.

An assembly is one more option of the `part` selector. It places each part through a module
the prompt gives the model, so the list of instances comes from the code:

```openscad
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
```

Its spec declares `allowed_interferences` (press fits, up to 0.3 mm thick), `motions` (a
`rotate` or `slide` swept through its range) and `assembly_order` (each step arrives from far
away along a direction, and may turn, without crossing what is already placed).

## Gates

Judged by the orchestrator on its own verification of the current source, never on the model's
tool results (`agent/gates.py`):

| Gate | Green when |
|---|---|
| G1 | the source compiles and every part exports with no errors, failed asserts or warnings |
| G2 | every part is a closed mesh with the declared number of bodies |
| G3 | the assembly: each instance is its part moved (same volume, area and principal moments), every part present as many times as its `copies`, no overlaps beyond the allowed ones, one connected group, and the units the request chains |
| G4 | every declared motion and the assembly order run without collisions |
| G5 | overhangs only inside the allowed boxes (at most half of a part's surface), and every part fits the bed |
| G7 | the spec holds, details included, and the model saw the final version: the sheet of every part, a view of the whole assembly, a close view of every `view` detail |
| G8 | the close: every `[[name]]` it cites is something the harness verified green, and an auditor (the same model, without tools) finds no claim presented as verified that nothing backs, and no untold spec adjustment |

G6 (fidelity to a reference model) is planned and not part of this build; the numbering keeps
its slot.

## Sandbox

One hardened container per session (`agent/sandbox.py`), from the pinned `cadverify-sandbox`
image (OpenSCAD 2026.10.26 with the Manifold backend, Python 3.12 with trimesh, manifold3d,
numpy, scipy, shapely, matplotlib and Pillow):

- no network; 2 CPUs, 4 GB of memory without swap, 512 processes; no capabilities, no new
  privileges, a read-only root file system;
- `/work` (1 GB) and `/tmp` (512 MB) are tmpfs: filling them never touches the host's disk;
- every exec runs as a user id drawn for the session, so the process limit and the cleanup after
  each call cover exactly the model's processes;
- the orchestrator's prompts, gates and auditor are hidden from the container; the API key never
  enters it;
- the host copies changed files out as a tar stream with the `data` filter, and never executes
  or imports anything from the workspace;
- verification runs in a new container per source version, which receives only the `.scad`
  files; the model cannot reach it.

`cadverify hostile` runs scripted attacks through the same tool box (fork bomb, infinite loop,
disk fill, network, writes outside `/work`, a search for the key, an edit by shell after a
sheet, tampering with the verification, huge output, a memory bomb) and checks that each one is
contained. `tests/test_hostile_docker.py` asserts them.

## Records

Every session writes `results/design/<request>/<UTC>/`:

- `raw/`: every API request and response, with the key never written and images replaced by
  their hash;
- `tools/`: every tool call with its arguments, result, and the files it created, modified or
  deleted;
- `workspace/`: the `.scad` sources, the renders and the images the model saw (STL files are
  regenerated from the sources and not versioned);
- `session.json`: iterations, gates per iteration, tokens, cost and latency, spec adjustments
  and audits.

`cadverify summary <run>` turns a session into a Markdown table, one row per iteration.
