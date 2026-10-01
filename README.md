# eyesy-modes-milkdrop

The MilkDrop preset engine for EYESY, and the presets it plays. Sibling repos:
[`eyesy-platform`](https://github.com/BrettKinny/eyesy-platform) (engine/OS),
[`eyesy-modes-factory`](https://github.com/BrettKinny/eyesy-modes-factory)
(stock-library ports), and `eyesy-modes-bespoke` (original scenes, kept private).

This pack is one mode folder — `milkdrop/` — which is a **preset engine**, not a
single scene: one Lua runtime plus thirteen canonical ES2 fragment passes, playing a
catalog of presets defined in Lua. That is why it is its own repo: it has a
double-pass warp/composite FBO pipeline and a preset variable pool (`q1..q32`,
per-frame/per-vertex/per-point equations) that no other mode shares.

## Consuming this repo

From the engine repo:

```sh
./eyesyctl modes sync      # assembles this pack's modes into modes/
./eyesyctl preview milkdrop --headless --frames 120
```

`sync` is required before `./eyesyctl package`; `preview`/`test` resolve across
the packs directly. The engine's per-mode evaluator tests
(`tests/test_milkdrop_evaluator.py` in the engine repo) drive
`milkdrop/lib/evaluator.lua` from this pack and skip when it is absent.

## Layout

| Path | What it is |
| --- | --- |
| `main.lua` | The engine: preset loading, the warp→composite pass chain, audio/Q-variable globals, knob mapping |
| `lib/evaluator.lua` | The preset equation evaluator (per-frame, per-vertex, per-point pools) |
| `presets/presets.lua` | The preset catalog — the file you edit to add or tune a preset |
| `frag/warp_default.frag` | Canonical MilkDrop warp pass (MilkDrop2 `warp_ps.fx` default) — samples the previous feedback frame at the analytically-warped uv and applies decay |
| `frag/warp_sphere.frag` | Sphere/fly-in warp |
| `frag/comp_default.frag` | Display-only passthrough composite |
| `frag/blur1.frag` | 8-tap separable Gaussian gather (`blur1_ps.fx` port) |

## Presets and measured cost

Per preset, 600 frames offscreen on VC4 V3D 2.1 with a tier-A neighbour
(release `dev-e46f786ab44d`, 60.3 fps on the KMS path):

| Preset | p50 | Tier |
| --- | --- | --- |
| `rot-spin` | 27.3 ms | C |
| `built-in-spectrum` | 27.3 ms | C |
| `sphere-rush` | 27.4 ms | C |
| `warp-oscillation` | 27.8 ms | C |
| `q-bridge` | 28.4 ms | C |
| `custom-wave-petals` | 28.3 ms | C |
| `zoom-drift` | 28.4 ms | C |
| `darken-drift` | 29.2 ms | C |
| `beat-pulse` | 29.0 ms | C |
| `custom-wave-ring` | 31.8 ms | C |

Slots 2 and 7 (the two glow-composite presets measured here before) are retired;
see the presets file.

## Engine facts worth keeping

- **Composite through a content-resolution target, then upscale.** Full-res
  composite passes dominate the frame budget; `draw_target` upscale is now
  standard for any shader-display engine. Note `ofFbo` targets are `GL_LINEAR`,
  so a chunky look needs a nearest resample (`floor(uv*RES)+0.5`).
- **CPU particle pools are per-frame Lua too.** The starfield pool rebuilds every particle as one triangle each frame (224 stars is 672 vertices and 672 indices), which is comparable to a couple of custom waves. The mesh API caps a mesh at 8192 vertices and 49152 indices and requires xyz vertices, so counts stay in the low hundreds. Note mesh coordinates are **content-resolution** pixels, not screen pixels — 640x360 for a standard preset, while the composite upscales.
- **Custom waves are expensive on ARM.** Per-point Lua evaluation costs real
  milliseconds: built-in-wave presets run ~7 ms/frame cheaper than custom-wave
  presets at equal pipeline. Author 160–256 samples, not 512+, unless the look
  demands it.
- **The catalog saturates the 8-target budget** (4 targets × 2 content sizes).
  No further in-mode targets are available without dropping dense.
- **Keep warp/sphere magnitudes bounded.** Warp sampling beyond [0, 1] clamps to
  edge columns, so extreme sphere/zoom values produce flat edge panels.
- **Feedback discipline.** The warp pass writes *into* the decayed feedback
  target and never adds light to it; the composite pass is display-only. Adding
  light inside a feedback loop self-amplifies to white.

## Docs

| Path | What it is |
| --- | --- |
| `docs/research/` | the MilkDrop3 / Winamp-AVS / BeatDrop dossiers — see its README |
| `docs/trackB-plan/` | the Track B brief the engine was built against, and its research notes |
| `docs/PRESET-CONTRACT.md` | what the preset gate enforces, and the checks it deliberately cannot make |
| `docs/FRAGMENT-CONTRACT.md` | what the fragment gate enforces: the host contract and the uniform traffic in both directions |
| `docs/RENDER-CONTRACT.md` | what the render gate proves on a real driver, and what it cannot (the look, the device, cost) |
| `docs/PORT-BACKLOG.md` | the porting loop's ranked work list, the licence-verified fragment sources, and the discovery entry points |
| `tools/` | the verification gates (`check_presets.py`, `check_fragments.py`, `check_render.py`) and the negative suite that proves the fragment gate fires (`check_fragments_negatives.py`) |

The per-preset p50 numbers above came from per-preset device tier gates. Those
runs were regenerable output, kept out of git and deleted on 2026-09-17, so this
table is now the only record of them — including the fact that the preset each
`p<NN>` gate covered was only recoverable for two of the twelve.

## Verification

Three gates, all driving the engine rather than re-implementing it, so their checks
are authoritative. The first two need a Lua interpreter on `PATH`; the third also
needs a C compiler and EGL/GLES2 headers. All exit `2` without what they need —
deliberately, because a validator that silently checks less than it claims is worse
than one that refuses to run.

```sh
python3 tools/check_presets.py     # catalog: schema, archetypes, every equation compiles
python3 tools/check_fragments.py   # fragments: host contract + uniform traffic, both ways
python3 tools/check_render.py      # fragments: compile + render on a real GLES2 driver
```

`check_fragments.py` runs the real mode against a recording stub of the engine and
watches every `draw_shader` call, so a preset parameter that reaches no uniform and
a fragment uniform the engine never supplies are both caught.
`tools/check_fragments_negatives.py` then mutates a throwaway copy of the mode once
per check and asserts the gate fails, naming the culprit, and
`tools/check_render.py --self-test` does the same for the render checks, so the
gates' failure paths are demonstrated rather than assumed. What each gate cannot
check — licensing above all, and for the render gate the look, the device and cost
— is stated in its contract doc.

## Licensing

This pack is under the BSD 3-Clause License ([LICENSE](LICENSE)). Fragments that
port third-party shader code or constructs, and the licences those sources carry,
are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The engine's pipeline mechanics follow MilkDrop's, studied from
BSD-3-Clause upstream (`milkdrop2077/MilkDrop3`, itself built on Maxim Volskiy's
BeatDrop). Every equation here is a **self-authored port** of the archetypes
documented in the engine repo's `docs/research/MilkDrop3Portability.md` and
`docs/research/MilkDropAVSHistorian.md` — equations and constructs only. No
community `.milk` preset file is copied. If community packs are ever imported as
user content, MilkDrop1-era presets need compat patches and aspect handling; that
QC checklist is in `docs/research/BeatDropForkPorting.md` in this repo.