# Port backlog — the loop's work list

The standing loop: **search the open-source web for MilkDrop visualisations → rank
by (value × portability) → port one at a time into this repo → validate → commit.**
This file is the ranked work list it draws from, plus the record of what is done and
what is blocked. Discovery is repeatable: the entry points that produced results are
listed at the bottom.

Rules that bind every entry: **equations and constructs only, never a community
`.milk` preset file** (`README.md`, Licensing); the catalog may only be **extended**,
never reordered — `preset` is an index, and saved states restore by it
(`docs/PRESET-CONTRACT.md`); and nothing ships without passing
`python3 tools/check_presets.py`.

## Done

Shipped as presets 13–16, preset-data only, validated:

| Preset | Archetype | Source |
| --- | --- | --- |
| `flow-silk-warp` | multi-frequency sine displacement of the decayed field | t2 Tier A-4 |
| `glowstick-trails` | additive saturated trails over a darkening warp. **Retired before the public release (slot kept).** | t2 Tier B-12 |
| `sector-kaleidoscope` | radial-wedge warp used as a fold, wedge count reseeded. **Retired before the public release (slot kept).** | historian A5 (approximate) |
| `spirolateral` | two counter-rotating custom spirals | t2 Tier B-13 |
| `softmax-halo` | soft-max composite: the `a+b−a·b` screen blend over a rotate/scale self-gather | tranche 2 item 4 (`jamieowen/glsl-blend` `screen.glsl`, MIT) |
| `plasma-veil` | interference-field composite: four incommensurable sine layers driving and veiling the scene | tranche 2 item 1 (`maravexa/hyprsaver` `shaders/plasma.frag`, MIT) |
| `kaleido-fold` | exact kaleidoscope fold: the warp folds the sampling angle into one half-wedge, so the frame becomes N mirror wedges | tranche 2 item 2 (three.js `KaleidoShader.js`, MIT) |
| `roto-streaks` | roto-blur composite: an 8-tap weighted gather along an arc about the screen centre | tranche 2 item 3 (gl-transitions `tangentMotionBlur.glsl`, MIT) |
| `painterly-flow` | painterly multi-blur warp: the warp gathers the frame sharp and through a blurred copy of it | tranche 3 item 5 (engine pass restructure) |
| `reaction-field` | Gray-Scott reaction-diffusion stepping once per frame inside the feedback loop | tranche 3 item 6 (engine kernel, feedback state) |
| `starfield-drift` | CPU particle starfield: 224 stars streaming from a vanish point, rebuilt as meshes per frame | tranche 3 item 7 (engine CPU pool) |
| `mirror-window` | textured-reflect shape as a per-pixel window rather than geometry (lossy, see item 8). **Retired before the public release (slot kept).** | tranche 3 item 8 (platform workaround) |

## Next tranche — requires fragment or engine work

**The preset-only seam is nearly exhausted.** Every remaining ranked archetype needs
something a preset cannot express: a new fragment, or CPU work the equation pools do
not provide. This tranche is a materially riskier class than presets 13–16 — it
touches the engine surface (`frag/` plus the archetype wiring in `main.lua`), so it
wants review, not unattended delegation.

| # | Archetype | What it needs | Representative |
| --- | --- | --- | --- |
| 1 | Plasma / interference field | **landed, slot 18** — `comp_plasma` sums four incommensurable sine layers (two radial around orbiting centres) into one field that lifts and veils the scene | `null1024 - Plasma` |
| 2 | Exact kaleidoscope fold | **landed, slot 19** — `warp_kaleido` folds the sampling angle (`mod` then `abs`) into one half-wedge; radius is preserved, so it is a reflection, not a shear | `Eo.S. - repeater 15 - kaleidoscope b` |
| 3 | Roto-blur / motion-trail | **landed, slot 20** — `comp_rotoblur`: 8-tap weighted gather along an arc (plus an optional radial sweep), display-only | `Geiss - Motion Blur 2` |
| 4 | Blobby mirrored feedback | **landed, slot 17** — `comp_softmax` does the `a+b−a·b` composite over a rotate/scale self-gather; the mirror fold is not part of it and stays with item 2 | `LuxXx - Benefiscient Prescience` |
| 5 | Painterly multi-blur flow | **landed, slot 21** — `warp_blur` gathers `prev` sharp and through `prev_blur` at three vertical offsets; the mode runs a conditional `blur1` pass over the feedback before the warp | `Aderrasi - Airhandler` |
| 6 | Gray-Scott reaction-diffusion | **landed, slot 22** — `warp_diffuse` steps the model once per frame with the feedback target as its state (A in red, B in green/blue); the drawn waves are the faucet. The one warp archetype that does not decay, so the gate's rule became "bound it" with a declared `warp-bound:` exception | `DemonLD - Toxic water diffusion` |
| 7 | Particle fountain / starfield | **landed, slot 23** — the pool lives in the mode (the formula pools have no arrays) and a preset declares only its shape via `particles`: 224 stars streaming outward, one triangle each, meshes rebuilt per frame | `Eo.S. and PieturP - Starfield` |
| 8 | Textured-reflect shape | **retired before the public release** (slot 24 kept as a placeholder, `comp_reflect` removed). It was a workaround — `comp_reflect` masks a rotated, zoomed, mirrored copy of the frame into a square window. **Not a port:** the engine has no per-vertex UV, so the shape is a per-pixel mask, the window cannot be an arbitrary polygon, and `tex_zoom = 1/rad` (a polar mapping needing the shape's own vertex radius) is approximated by a flat zoom. The read survives; the geometry does not | an unlicensed community preset |

**All eight items are done**, one archetype per commit, each with both gates plus
a real-driver render probe: slot 17 soft-max, 18 plasma, 19 kaleidoscope fold, 20
roto-blur, 21 painterly multi-blur, 22 reaction-diffusion, 23 starfield, 24
windowed reflection. Items 5–8 changed the engine rather than just adding a
fragment — 5 needed a blur of the feedback produced before the warp, 6 needed the
gate's decay rule restated as a bound so a bounded non-decaying step could exist at
all, 7 needed a CPU pool because the formula pools cannot hold an array, and 8 is a
workaround rather than a port, because the platform has no per-vertex UV. Only 8 is
lossy, and the loss is recorded in its row above.

Items 1–4 have licence-verified sources already researched. All four licences were
re-fetched live at their URLs on 2026-09-18 before porting — never trusted from this
list — and each verdict below records the licence text it rests on:

| Item | Source | Licence |
| --- | --- | --- |
| 1 plasma | `maravexa/hyprsaver` `shaders/plasma.frag` (+ `caustics.frag`) | MIT — re-verified 2026-09-18 from `LICENSE`: "MIT License / Copyright (c) 2026 Mara Vexa" |
| 2 kaleidoscope fold | three.js `examples/jsm/shaders/KaleidoShader.js` | MIT — re-verified 2026-09-18 from `LICENSE`: "The MIT License / Copyright © 2010-2026 three.js authors". That file credits pixelshaders.com / Toby Schachman as its own upstream |
| 3 roto-blur | three.js `AfterimageShader.js` + gl-transitions `tangentMotionBlur.glsl` | MIT — re-verified 2026-09-18: three.js `LICENSE` ("Copyright © 2010-2026 three.js authors"); gl-transitions `LICENSE` ("Copyright (c) 2017-present gl-transitions contributors") and `tangentMotionBlur.glsl`'s own header (`// License: MIT`, Author: chenkai) |
| 4 soft-max | `jamieowen/glsl-blend` `screen.glsl` (`a+b−a·b`) | MIT — re-verified 2026-09-18 from `LICENSE.md`: "The MIT License (MIT) Copyright (c) 2015 Jamie Owen" |

Constructs and ES2 port notes: `docs/candidates/03-fragment-sources-comp.md` (items 1,
4) and `docs/candidates/04-fragment-sources-warp.md` (items 2, 3). Two traps those
passes found: **Shadertoy is study-only as a class** (its default licence is
proprietary and the per-shader field is not fetchable without a browser), and
**LYGIA is not MIT** — it is the Prosperity Public License 3.0.0, non-commercial.

New fragments land under three gates. `tools/check_fragments.py`
(`docs/FRAGMENT-CONTRACT.md`) runs the mode and watches every `draw_shader` call: a
fragment declaring a uniform the engine never supplies fails, and so does a preset
parameter that reaches no uniform. `tools/check_render.py`
(`docs/RENDER-CONTRACT.md`) compiles and renders each fragment on a real GLES2
driver and asserts its neutral identities. Add the fragment, wire the archetype,
then run `python3 tools/check_fragments.py`, `python3 tools/check_presets.py` and
`python3 tools/check_render.py`.

## Defects found while porting

Both were found by rendering the fragments on a real GLES2 driver rather than by
reading them. Both are fixed, and each fix was checked against the canonical
MilkDrop preset-authoring spec (linked from
`docs/research/MilkDrop3Portability.md`) rather than against intuition.

### 1. The warp coordinate chain sampled half a screen below the intended uv — FIXED

All four `warp_*.frag` ended with:

```glsl
wuv = vec2(wuv.x / aspect, 0.5 - wuv.y) + 0.5;
```

The `+ 0.5` is a vec2 add, but the y component already carries its own half: the
`0.5 - wuv.y` *is* the y-up to y-down conversion. So the sampled uv was
`uv.y + 0.5`. Rendered with identity parameters, the output was **exactly** the
input shifted 128 rows on a 256-row frame — `out[r] == in[r + 128]` for every row,
maximum difference 0.0/255 — and the same harness reproduces the input
byte-exactly through a composite fragment, so the offset lived in that line rather
than in the harness. Corroboration: `comp_glow.frag`'s analogous line was already
right (`vec2(0.5 + uv2.x, 0.5 - uv2.y)`), which is the shape the warp line was
reaching for.

Fixed to `vec2(wuv.x / aspect + 0.5, 0.5 - wuv.y)` in all four. After the fix,
identity parameters give `warp_default` and `warp_sphere` byte-exact passthrough
(0.00/255) and the `r + 128` signature is gone: 0.00/255 at shift 0, 224/255 at
±128.

### 2. The zoomexp exponent was inverted — FIXED

The warp computed `zoom * pow(r, 1 - zoomexp) / r`. The spec defines `zoomexp` as
"controls the curvature of the zoom; **1 = normal**" and `zoom` as "0.9 = zoom out
10% per frame, 1.0 = no zoom, 1.1 = zoom in 10%", so the two documented neutral
values must produce the identity. They did not: at `zoom = 1, zoomexp = 1` the
multiplier collapses to `1/r`, mapping every pixel to radius `zoom` — a flat frame
sampling only the border. All nine presets that set `zoomexp` pin it at `1.0`, the
spec's own normal value, so every scene was running with a collapsed warp.

Fixed to `zoom * pow(r, zoomexp) / r`, i.e. `zoom * r^(zoomexp - 1)`: at
`zoomexp = 1` that is exactly `zoom`, a uniform proportional scale. After the fix,
`zoom = 1, zoomexp = 1` is byte-exact identity (0.00/255) in `warp_default` and
`warp_sphere`; `zoom = 1.004` now leaves the frame's luma stddev untouched
(0.0876, i.e. structure survives) where it previously collapsed to 0.033; and
`zoom = 0.98` zooms out symmetrically.

The README's engine note needed no change: "warp sampling beyond [0,1] clamps to
edge columns" is correct advice once the chain is right.

Both fixes are covered by regression tests now: `tools/check_render.py`'s identity
cases assert that `warp_default` and `warp_sphere` with `zoom 1 / zoomexp 1` return
the input frame byte for byte, which the old code failed. Putting the half-screen
offset back makes the gate fail with a 150/255 delta; nothing else in the repo
would notice.

## Discovery entry points that produced results

Repeatable, in the order they paid off:

- `projectM-visualizer/presets-cream-of-the-crop` (~9,795, theme-sorted) — the
  canonical curated pack; theme directories enumerate the archetype space.
- `projectM-visualizer/presets-milkdrop-original` (552 — the last official bundled
  pack) and `presets-projectm-classic` (~4,200).
- `milkdrop.org` archive (ex-`milkdrop.co.uk`; the old domain is squatted) — 5,527
  presets, quarterly collections, 105 author indexes.
- `jberg/butterchurn-presets` (~1,440 JSON) and
  `ansorre/tens-of-thousands-milkdrop-presets-for-butterchurn` (15,056).
- `visbot.net/archive` (70+ AVS author packs, e.g. VISBOT 200 = 2,530) and the
  `winampheritage.com` AVS library — the Winamp-AVS lineage.
- `SpasilliumNexus/poweramp-visualizer-presets` — permissive, and evidence that
  EEL→Lua / HLSL→GLSL translation works on mobile GLES.
- `milkdrop2077/MilkDrop3` (BSD-3 engine code, portable) for pipeline mechanics.

Licence status, so a future pass does not re-derive it: nearly every preset pack is
**study-only** — most carry no licence file at all, and `cream-of-the-crop` states a
public-domain *assumption* while authors retain copyright. Study them for archetypes
and constructs; never copy a file.

## Routing this through the pipeline

The intended mechanism is Pi Agent's Development Pipeline (managed clone already
provisioned at `nightshift-repositories/BrettKinny/eyesy-modes-milkdrop`). It cannot
take this repo today: `pi-agent/src/development/pipeline.ts:362` hardcodes
`allowedScope: ["src", "test", "tests", "features"]`, enforced in
`src/coding/packet-runner.ts`, and nothing in this repo lives there. Until that
becomes repository-derived, this work runs as direct delegation.

Two lessons from the first overnight run, worth keeping:

- **Scope subagent tasks to ~10 minutes of work.** A 30-minute runtime ceiling is
  enforced (`task.maxRuntimeMs=1800000`); two discovery passes hit it having produced
  nothing, one of them after burning its whole budget re-reading the repo.
- **Narrow beats broad.** The two tasks that finished in 6–9 minutes were the two with
  a bounded output.
