# Track B variant pass

Spec for the variant pass: the scaling step that turns this engine's preset
catalog into a growing library of scene variants. It is the contract the pass
runs against and the acceptance gate every shipped batch must clear. The engine
was built against [`docs/trackB-plan/BRIEF.md`](trackB-plan/BRIEF.md); its
measured costs are in the [README](../README.md).

## What Track B is

One Lua engine (`milkdrop/`) loads a catalog of presets defined in
`milkdrop/presets/presets.lua`: per-frame equations drive the feedback loop,
per-point equations drive custom waves, and a warp -> composite fragment chain
(`milkdrop/frag/`) renders the frame.

The variant pass is the authoring workload on top of that engine: instead of
one-off scenes, presets are written as parameterized families so a family can
be cheaply re-instantiated across its variant axes. The payoff is scale — from
the 12 presets that shipped with the engine toward a library of 100+
self-authored variants (see Target) — at the per-preset cost of a parameter
pass rather than a new scene.

## Presets as scene variants

A preset is a scene variant in the sense of `eyesy-platform`'s
`docs/SCENE-LIBRARY.md`: a saved scene JSON is parameters + state, never new
code, and must be recognizable as its family while carrying its own name,
default palette, and trigger behavior. The preset catalog encodes the same
contract in Lua — each entry is `name` + `per_frame_init` / `per_frame` /
`per_pixel` / `waves` equation blocks plus archetype and parameter tables
(`warp_archetype`, `comp_archetype`, `comp_params`, `wave_mode`, `decay`, `q`
pool). Switching between presets is the mode-level equivalent of scene recall;
the trigger button re-runs `per_frame_init` with a fresh seed ("in-family beat":
re-seed morphology and palette, never switch preset — the k2/`preset` knob and
saved-scene variants own switching, per the Track B brief).

A variant is therefore a full preset entry whose family (warp archetype, comp
archetype, wave structure) is held constant while the three axes below are
swept.

## Per-family variant axes

| Axis | What varies | Where it lives in a preset |
| --- | --- | --- |
| **palette** | colour identity: base hue and drift, gamma, contrast, echo, per-family palette name | `hue`/`gamma`/`contrast` writes in `per_frame`, `comp_params` colour uniforms, the `palette` field of a variant JSON (Track B brief layout); trigger re-seeds it (MilkDrop `c` randomize-colors equivalent) |
| **regime** | feedback character: which warp and composite do the loop, how hard the decay, which built-in wave rides along | `warp_archetype`, `comp_archetype`, `decay`/`gamma`/`contrast`/`echo` envelope, `wave_mode` 0..3, `q`-pool integration rates |
| **motion** | geometry and audio coupling: zoom/rot drift, wave shape and radius, how hard bass/mid/treb push | per-frame `zoom`/`rot`/`cx`/`cy`/`dx`/`dy`/`warp` writes, per-point wave equations (`th`, `rr`, `x`, `y`), `bass_att`/`mid_att`/`treb_att` coefficients, knob-1/knob-5 bridge |

A family is a fixed (warp_archetype, comp_archetype, wave structure); variants
of that family differ along at least one axis above and keep the family's
recognizable look. Example: the composite presets `softmax-halo` and
`plasma-veil` are single points of their families today — the pass sweeps
palette and motion variants of each at a fixed comp regime.

## Target

From the 12 presets the engine first shipped with toward 100+ self-authored
variants. The catalog now has 24 slots, five of them retired placeholders (see
`docs/PRESET-CONTRACT.md` for why slots are never removed or reordered). The
100+ goal is met by sweeping the three axes per family, not by adding one-off
presets; each tranche ships as a batch (see QC gate).

## QC gate

Every batch of new or re-tuned variants must pass, in order:

1. **Pack gates**: `tools/check_presets.py` (preset schema, archetypes, every
   equation compiles), `tools/check_fragments.py` (fragment host contract and
   uniform traffic, plus the negative demonstrations), and the evaluator suite
   `python3 -m unittest tests.test_milkdrop_evaluator`.
2. **Per-scene tier assertion**: every preset holds tier C (`<= 33.3 ms` p50,
   the performance tiers in `eyesy-platform`'s `docs/SCENE-LIBRARY.md`) on the
   device, 600 frames offscreen with a tier-A neighbour, per preset.
3. **Contact sheet per batch**: a `contact-sheet.png` from
   `eyesy-platform`'s `tools/scene_verify.py`, plus per-preset `summary.json`
   from its deterministic A/B contract verdict, and a human visual pass over
   the sheet — aesthetics and family resemblance are a human call, never
   asserted mechanically. The run output is not committed.
4. **Batch docs + commit**: the batch lands with its variant list, per-preset
   tier numbers, and any family notes.

## Licensing rule

- Self-authored parameter variants are unencumbered. The engine's equations
  are self-authored ports of documented archetypes (BSD-3-Clause upstream
  `milkdrop2077/MilkDrop3`); no community `.milk` preset file is copied, and
  this pass keeps it that way — variants are parameter sweeps of
  self-authored presets, not re-encoded packs.
- Community preset packs (projectM cream-of-the-crop, butterchurn-presets)
  are separate artwork with separate terms: importing them into a distributed
  product is a rights question, not a code-port question. Treat community
  pack import as user-supplied content unless cleared — the import QC
  checklist (MilkDrop1-era compat patches, aspect handling) is in
  `docs/research/BeatDropForkPorting.md`.

## Where the work happens

Preset authoring, the pack gates and the evaluator tests live here
(`milkdrop/main.lua`, `milkdrop/lib/evaluator.lua`,
`milkdrop/presets/presets.lua`, `milkdrop/frag/`, `tools/`, `tests/`).
`eyesy-platform` consumes the mode via `./eyesyctl modes sync` and owns the
engine-side contracts (`docs/SCENE-LIBRARY.md`, `docs/API.md`) and the device
tier runs. Never edit the platform's `modes/` directly: it is the gitignored
assembly dir.

## Resolved follow-ups

The evaluator suite once flagged two preset defects, both since fixed in the
catalog with the assertions unchanged:

- `spirolateral`'s first custom wave let its radius reach 0.54 at full
  `bass_att`, putting the spiral tip past `x = 1.0`. The engine only clamps
  custom-wave points to `-1.0..2.0` (a non-finite guard, not an on-screen
  clamp), so the tip drew off the right edge.
  `test_wave_points_stay_on_screen` guards the "x/y are normalised 0..1 about
  (0.5, 0.5)" contract.
- `reaction-field`'s `per_frame` never wrote `zoom`, leaving the warp pass
  without its feedback driver. `test_preset_frames_run_finite` asserts every
  preset writes it.
