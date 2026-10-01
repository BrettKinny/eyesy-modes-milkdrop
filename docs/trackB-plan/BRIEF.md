# Track B — milkdrop-engine design brief

Status: contract for the batch kickoff (2026-09-16). Sources of truth:
`docs/research/MilkDrop3Portability.md` (architecture + formulas),
`docs/research/MilkDropAVSHistorian.md` (archetype map), `docs/API.md`
(engine Lua API), `docs/SCENE-LIBRARY.md` (knob contract, tiers, design law).
Licensing: MilkDrop3 engine code is BSD-3 (port equations/constructs freely);
community preset packs are third-party artwork — self-authored presets only
for shipped content; pack import stays user-supplied content unless cleared.

## Ownership map (no file conflicts)

| Slice | Owner | Files |
| --- | --- | --- |
| Evaluator + seed presets | agent T1 | `modes/milkdrop/lib/evaluator.lua`, `modes/milkdrop/presets/presets.lua`, `tests/test_milkdrop_evaluator.py` |
| Fragment library | agent T2 | `modes/milkdrop/frag/*.frag` (six files, below) |
| Preset pack (data) | agent T3 | `local/reports/trackB-plan/preset-pack.lua` (staging, merged later) |
| Engine main.lua | agent T4 (wave 2) | `modes/milkdrop/main.lua` |

`runtime.cpp` opens the full Lua stdlib and prepends `modes/milkdrop/?.lua`
to `package.path` — `require("lib/evaluator")` and `require("presets/presets")`
are supported. Preset data lives as Lua tables (no JSON parsing needed).

## Preset schema (Lua table, MilkDrop field names)

```lua
{
  name = "example-preset",
  per_frame_init = "q1 = 0.5; seed = rand(100)",  -- optional, AVS, on load/trigger
  per_frame = "zoom = 1.01 + 0.02*bass; rot = 0.01*sin(0.3*time)",  -- AVS
  per_pixel = "",             -- optional AVS(x,y,rad,ang); presence selects archetype
  warp_archetype = "default", -- "default" | "sphere" | "sector"
  comp_archetype = "default", -- "default" | "glow"
  warp_params = { sectors = 8 },   -- archetype-specific uniforms
  comp_params  = { rot5 = 30, scale5 = 0.9, glow = 0.4 },
  wave_mode = 0,              -- built-in wave 0..3 only in v1 (0=line,1=circle,2=spokes,3=spectrum)
  wave_a = 1.0, wave_r = 1.0, wave_g = 1.0, wave_b = 1.0,
  waves = { { samples = 512, sep = 0, r = 1, g = 1, b = 1, a = 1,
              t1 = "sample = 0.5 + 0.4*sin(sample*6*q1)" } },  -- custom wave, per-point AVS (vars: sample,x,y)
  shapes = { { sides = 4, x = 0.5, y = 0.5, rad = 0.3, ang = 0,
               r = 1, g = 1, b = 1, a = 0.8 } },  -- untextured only (no per-vertex UV in eyesy meshes)
  decay = 0.98,                       -- fallback when per_frame doesn't set it
  q = { 0.5, 0.2 },                   -- initial q1..q32
}
```

Per-frame writable engine vars (v1): `zoom, zoomexp, rot, warp, cx, cy, dx,
dy, sx, sy, decay, gamma, bright, contrast, saturation, hue, echo`.
Per-frame readable: `bass, mid, treb, bass_att, mid_att, treb_att, time, fps,
frame, progress, q1..q32`. Per-point adds `sample, x, y, rad, ang, value1,
value2`. Undefined reads = 0. All results clamped finite (NaN/inf -> 0).

## Evaluator (T1)

`modes/milkdrop/lib/evaluator.lua`, pure Lua 5.1/LuaJIT, zero eyesy deps.
API: `local ev = require("lib/evaluator")`
- `ev.compile(code)` -> `f(env) -> results_table` (compile once at preset
  load; `nil, errmsg` on parse error, never throws).
- `ev.run(env, code)` -> compile+run one-shot (per_frame_init).
Grammar: `;`-separated `name = expr` statements; numbers, identifiers,
`+ - * / %`, unary minus, right-assoc `^`, parens. Functions: `sin cos tan
asin acos atan atan2 abs min max sqr sqrt pow log log10 int sign exp sigmoid
if(c,a,b) above(a,b) below(a,b) equal(a,b) rand(max) bor band bnot`.
`rand` takes a deterministic seeded PRNG handle supplied in env (`env._rand`)
so runs are reproducible. Test harness `tests/test_milkdrop_evaluator.py`
follows existing test conventions (see `tests/test_soak_guard.py`): arithmetic
and precedence, function set, q-pool read/write, NaN/inf clamping, parse-error
returns nil,rand determinism, per-point env (rad/ang from x,y).

Seed presets in `presets/presets.lua` (module returns `{ preset1, ... }`):
1. `darken-drift` — default archetype, per_frame zoom/warp driven by bass, comp default. Baseline.
2. `sector-shards` — sector warp archetype + glow comp (retired before the public release)
   (from the research doc's fully-read preset; ported, not copied verbatim).

## Fragment library (T2)

Six ES2 fragments, no `#version`, `varying vec2 uv`, uniforms as named
floats/vec2/sampler from draw_shader args 5/6. CRITICAL engine fact:
`uv.y` is TOP-DOWN — all MilkDrop math is y-up Cartesian, so convert once:
`vec2 p = vec2((uv.x-0.5)*aspect, 0.5-uv.y)` (aspect = width/height uniform).
Formula ground truth: read `docs/research/MilkDrop3Portability.md` IN FULL
(the mapped per-pixel formula is in the report body) — do not invent.

- `warp_default.frag` — canonical per-pixel warp: sample `prev` at warped uv,
  multiply by `decay`. Uniforms: prev, zoom, zoomexp, rot, warp, cx, cy, dx,
  dy, sx, sy, decay, aspect, texel(vec2).
- `warp_sphere.frag` — radial sphere pinch on top of default. Uniforms:
  default + `sphere`.
- `warp_sector.frag` (retired before the public release) — radial-wedge: per-sector rot + zoom
  pulse. Uniforms: default + `sectors`, `sector_rot`, `sector_zoom`.
- `comp_default.frag` — display pass over feedback: gamma, bright, contrast,
  saturation, hue shift, echo. Uniforms: fb, gamma, bright, contrast,
  saturation, hue, echo.
- `comp_glow.frag` — max() composite of 5 rotated/scaled fb gathers + blur1
  (retired before the public release). Uniforms: fb, blur1, rot5, scale5, glow, gamma,
  bright, saturation, hue.
- `blur1.frag` — single-pass 8-tap Gaussian gather (blur1_ps.fx offsets
  d1..d4/weights w1..w4, texel-unit). Uniforms: src, texel.

Rules (SCENE-LIBRARY design law): never add light into the target you next
sample for decay — warp pass only decays; glow lives in the display comp.

## Engine main.lua (T4, wave 2)

Params: `preset` (k2, index into presets.lua), `motion` (k1 -> speed/decay
axis), `detail` (k3 -> wave samples/shape detail), `hue` (k4), `feedback`
(k5 -> warp/zoom axis). Trigger = in-family beat: re-run per_frame_init with
fresh seed (q-pool randomization), never switch presets (preset switching is
k2 / saved-scene variants). Pipeline per frame: per_frame eval -> warp pass
into back (640x360; 480x270 when warp_params.dense) -> waves/shapes meshes
into back (8192-vertex cap; 2048 max samples) -> blur pass (only glow comp)
-> composite draw to screen -> swap. Targets used: 3 of 8. save/restore:
preset index + q pool + decayed beat state. Tier: C (<= 33.3 ms p50) per
preset on device; per-preset tier assertion in headless runs.

## QC protocol (batch standard)

Desktop preview per archetype + eyeball, `./eyesyctl test`, package,
headless device run per preset (tier assert + zero errors + RSS flat),
visual review of grabs, transactional deploy, docs + roadmap + commit.

## T1 integration notes (verified 2026-09-16, 36/36 green)

- `compile(nil)` = empty code (per_frame_init/per_frame/per_pixel are
  optional); `f(env)` never throws (nil,errmsg on internal error). env is
  never mutated — the engine merges results into its persistent state table
  to persist q1..q32 across frames.
- `env._rand` (seeded PRNG, returns [0,1)) is supplied by the engine; the
  module falls back to a deterministic Park-Miller LCG if absent.
- Pinned semantics: `sqr(x)=x*x`; `%` is floor-mod (sign of divisor);
  `-2^2 == -4`; `if(c,a,b)` is lazy (untaken branch unevaluated — observable
  through the rand stream).
- Coordinates: per-point x/y normalized 0..1 with visual origin (0.5,0.5);
  engine derives rad/ang from (x-0.5, y-0.5). Preset headers document this.
- sector-shards keeps the ported per-point sector math in per_pixel
  (seg/rise/dx/dy) while the v1 warp_sector fragment computes the wedge
  analytically — T4 must not consume those outputs.
- Perf headroom (LuaJIT): 2048-point wave pass 0.71 ms/frame, per_frame
  1.3 M evals/s — the evaluator is not the tier-C risk.

## T3 integration decisions (verified 2026-09-16, 10/10 presets)

- Merge: `presets/presets.lua` becomes 12 presets (2 seeds + the 10 from
  `local/reports/trackB-plan/preset-pack.lua`). The staging file is read-only
  input to the merge.
- `sphere` is a per-frame writable engine var (was missing from the brief's
  list); T4 forwards it to warp_sphere.frag's `sphere` uniform or
  sphere-rush degrades to the default warp.
- Optional preset field `param_bridge` (map of warp_params key -> per-frame
  var name, e.g. `{sectors = "wedges"}`): T4 evaluates it each frame after
  the per-frame merge so reseeded variant axes stay in sync with the
  analytic fragments. Without it, sector-shards-16's wedge reseed is
  decorative.
- `wave_a` = amplitude multiplier on the wave draw (0.7..1.2 typical).
- All 12 presets expect Tier C; sector-shards-16 is the top end (sector
  warp + glow 5-gather + blur1). Per-preset visual/tier notes trail
  preset-pack.lua.
