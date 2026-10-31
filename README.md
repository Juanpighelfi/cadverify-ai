# CADVerify AI

A design agent on **Muse Wonder** that turns a plain-language request into printable OpenSCAD
parts and assemblies, and cannot say "done" until a deterministic harness has measured that the
geometry is what it claims.

Language models write CAD that looks right in the text and is wrong in the mesh: a hole that
does not go through, a lid that collides with its jar when it turns, an overhang that needs
supports, a wall thinner than the spec. CADVerify makes every claim checkable. The model
declares its intent in the source, the harness measures the exported meshes against it, and the
session closes only when every gate is green and the closing message cites nothing the harness
did not verify.

Built during the [Meta AI Developer Hackathon](https://cerebralvalley.ai/e/meta-ai-developer-hackathon)
(October 27 to November 4, 2026), Indie track.

## Meta models

- `muse-wonder-1.0` through the Meta Model API Responses endpoint, streamed: the designer
  (tool calling, reasoning, and vision on the renders it asks for) and the auditor of its
  closing message (the same model without tools, gate G8).

## How it works

```
request ──► Muse Wonder ──tool calls──► sandbox (OpenSCAD, measurements, renders)
                ▲                              │
                └──── JSON + images ◄──────────┘
                                               │ .scad only
                         close ◄── gates G1..G8 ◄── fresh verification container
```

- **Twelve tools** in a hardened Docker sandbox: write and patch `.scad`, compile, export with a
  mesh report, multi-view sheets and free views with plane cuts from our own renderer,
  printability, an assembly interference and motion check, and the model's own shell and Python.
- **A verifiable spec.** The source echoes what each part must measure (bounds, bodies, through
  holes, support faces, allowed overhangs, details such as a wall thickness or a hole profile)
  and, for an assembly, its press fits, motions and assembly order.
- **Gates** judged on the harness's own verification, never on the model's tool results:
  compiles clean (G1), closed meshes (G2), assembly with no overlaps (G3), motions and assembly
  order without collisions (G4), printable on the bed without unplanned supports (G5), spec held
  and every final part seen (G7), and an honest close (G8).
- **Rules the harness enforces**: a visual finding must be confirmed with a measurement before
  the source can change; every new mesh comes with its sheet so the model sees what it made;
  a spec quietly moved toward what the mesh measures is flagged and must be told to the user.

Details in [docs/architecture.md](docs/architecture.md).

## Demo

Three requests in [requests/](requests/), each a different kind of mechanism, one session each
with `muse-wonder-1.0`. All three closed with every gate green:

| Request | Requests | USD | Minutes | What the harness caught on the way |
|---|---|---|---|---|
| [Bayonet jar](requests/bayonet_jar.md): a jar and a lid with a quarter-turn lock | 27 | 2.60 | 19 | G4: the detent bump collided with the jar during the quarter turn (an overlap 0.022 mm thick); the model replaced it with a drop-in pocket and told the user why. G8 refused a close with 6 unsupported claims, such as "interior Ø70 × 80 mm", which nothing measured. |
| [Headphone stand](requests/headphone_stand.md): three parts that assemble without glue | 17 | 1.31 | 8 | G8 refused a close with 2 unsupported claims (a count of bad edges and an overhang area nobody measured), and one that cited a support face the close check did not know yet (a harness bug, fixed after this session). |
| [Hinge box](requests/hinge_box.md): a box whose hinge prints in place, already assembled | 40 | 3.10 | 18 | G4: the lid's rear lip hit the box partway through its swing; fixed with a notch. Five spec adjustments were flagged and told in the close. G8 refused a close with 6 unsupported claims, such as "the closed lid is retained at the front". |

Each session is recorded under [results/design/](results/design/): every API request
(`raw/`), every tool call (`tools/`), the sources, renders and images the model saw
(`workspace/`), `session.json`, and `replay.html`, a static page of the whole session (open it
from a local copy of the run directory; `uv run cadverify replay <run>` rebuilds it).

## Quick start

Requirements: Python 3.12, [uv](https://docs.astral.sh/uv/), Docker with BuildKit, and a Meta
Model API key.

```sh
uv sync
cp .env.example .env              # set MODEL_API_KEY; .env is git-ignored
docker build -t cadverify-sandbox .
uv run cadverify design requests/bayonet_jar.md --max-usd 5
```

The session prints its run directory. If the model asks questions before it starts designing,
they appear in `<run>/questions/NN.md`; write the answer to another file and rename it to
`<run>/questions/NN.answer.md`.

```sh
uv run cadverify summary results/design/bayonet_jar/<UTC>   # a session as a Markdown table
uv run cadverify spent                                      # USD spent against the budget
uv run cadverify hostile                                    # attacks on the real sandbox, no API
```

Inside the image, `cadcheck` runs every tool from a shell (`docker run --rm -v "$PWD:/work"
cadverify-sandbox cadcheck --help`).

## Limitations

- Motions are swept as rigid bodies, so an elastic feature (a snap bump, a detent that flexes)
  counts as a collision. The bayonet jar shows the consequence: its bump became a pocket.
- G5 checks each part in its own print orientation. A print-in-place product is not checked as
  it prints, all parts together: a bridge that only exists in the assembled pose is not
  measured.
- Strength, stability, feel and fit on a particular printer are not measured. The close must
  list them as not verified, and G8 refuses a close that presents them as verified.
- The renders and the spec checks are deterministic, but the design is not: two sessions on the
  same request differ.

## Tests

```sh
uv run pytest && uv run ruff check . && uv run ruff format --check .
docker run --rm -w /app cadverify-sandbox pytest -q -p no:cacheprovider
```

The host tests are offline: the agent tests use a scripted fake model, and
`tests/test_agent_docker.py` and `tests/test_hostile_docker.py` drive the real sandbox when the
image is built. The tests inside the image cover OpenSCAD, the renderer, the cuts and the
measurements.

## License

[MIT](LICENSE)
