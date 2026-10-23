# Performance

What the presets cost on the EYESY, how those numbers were measured, and what
we learned about keeping a MilkDrop-style pipeline fast on its GPU (a VC4 V3D
2.1 in the Compute Module 3+).

The platform's target is **tier C: a median frame time of 33.3 ms or less**,
which is 30 fps. See the platform's [performance
tiers](https://github.com/BrettKinny/eyesy-platform/blob/main/docs/SCENE-LIBRARY.md#performance-tiers).

## Measured costs

Two sets of measurements exist. They were taken in different ways, so compare
numbers within a set, not across them.

**Live HDMI output, October 2026.** The `milkdrop` mode running on a CM3+ EYESY
(release `dev-52ea2cb77c8d`), drawing to HDMI at 1280×720, with the trigger
test tone as the audio input. The frame rate is the engine's own reading.

| Slot | Preset | fps |
| --- | --- | --- |
| 16 | `spirolateral` | 29 |
| 17 | `softmax-halo` | 32 |
| 19 | `kaleido-fold` | 33 |
| 20 | `roto-streaks` | 17.4 |
| 21 | `painterly-flow` | 33 |
| 22 | `reaction-field` | 39.5 |

`roto-streaks` misses tier C by a wide margin. Its composite gathers eight
samples per pixel along an arc, which is the obvious place to start cutting.

**Offscreen median, September 2026.** 600 frames per preset rendered offscreen
on the device GPU (release `dev-e46f786ab44d`), while the live service kept a
light scene running. These are shared-load numbers: the platform explains why
in [measuring on the
device](https://github.com/BrettKinny/eyesy-platform/blob/main/docs/SCENE-LIBRARY.md#measuring-on-the-device).

| Slot | Preset | Median frame time | Equivalent fps |
| --- | --- | --- | --- |
| 1 | `darken-drift` | 29.2 ms | 34.2 |
| 3 | `zoom-drift` | 28.4 ms | 35.2 |
| 4 | `rot-spin` | 27.3 ms | 36.6 |
| 5 | `warp-oscillation` | 27.8 ms | 36.0 |
| 6 | `sphere-rush` | 27.4 ms | 36.5 |
| 8 | `q-bridge` | 28.4 ms | 35.2 |
| 9 | `custom-wave-ring` | 31.8 ms | 31.4 |
| 10 | `custom-wave-petals` | 28.3 ms | 35.3 |
| 11 | `built-in-spectrum` | 27.3 ms | 36.6 |
| 12 | `beat-pulse` | 29.0 ms | 34.5 |

Not yet measured on the device: `flow-silk-warp` (13), `plasma-veil` (18) and
`starfield-drift` (23).

The mode itself never measures anything; `fps` in an equation is just the frame
rate it observes. To measure a preset, run the platform's `tools/benchmark.py`
or `./eyesyctl headless-test` with an input replay that holds knob 2 on the
preset's slot.

**Offscreen median, October 2026 (per-pixel trim).** Same method as above (600
frames offscreen on the device GPU, live service running), measured against the
same session's `starter` floor of 24.5 ms. Each preset was forced by a throwaway
copy of the mode. "Before" is the pack at the previous commit.

| Slot | Preset | Before | After |
| --- | --- | --- | --- |
| 13 | `flow-silk-warp` (the knob-centre default) | 34.7 ms | 33.2 ms |
| 6 | `sphere-rush` | 35.2 ms | 33.9 ms |
| 17 | `softmax-halo` | 36.5 ms | 34.5 ms |
| 18 | `plasma-veil` | 39.8 ms | 37.8 ms |
| 19 | `kaleido-fold` | 37.3 ms | 36.0 ms |
| 20 | `roto-streaks` | 61.7 ms | 39.1 ms |
| 21 | `painterly-flow` | 40.0 ms | 38.7 ms |
| 22 | `reaction-field` | 35.1 ms | 34.0 ms |
| 23 | `starfield-drift` | 35.1 ms | 33.3 ms |

The device was slower in this session than in September for the same code, so
compare the Before and After columns, not these figures against the tables above.
The picture is unchanged: the largest mean difference from the old build in the
desktop verifier's final frames is 0.1 of 255 (rounding in the folded tone matrix).
What changed, all of it per-pixel work moved to once-a-frame Lua:

- The composite's tone chain (gamma, bright, contrast, saturation, hue, echo) is
  one `pow` and a 3x3 affine map; the matrix is built in `tone_uniforms`.
- `warp_default` takes the focus, rotation, squash and translate as three folded
  uniforms and skips `pow` when `zoomexp` is 1; the other warps take `cos(rot)`
  and `sin(rot)` from Lua and skip the same `pow`.
- `comp_rotoblur` computes one `cos`/`sin` pair and rotates by a shared step for
  the other seven taps.

Rendering the composite at 480x270 instead of 640x360 would save about 1 ms more on
every preset, but it softens fine lines (mean difference up to 4.8 of 255 with loud
audio), so it is not enabled.

**Offscreen median, October 2026 (frame budget pass).** Same method and the same
24.5 ms `starter` floor as the previous section; "Before" is the pack at commit
078412a. Every preset in the table is now inside tier C.

| Slot | Preset | Before | After |
| --- | --- | --- | --- |
| 6 | `sphere-rush` | 33.9 ms | 29.5 ms |
| 9 | `custom-wave-ring` | not re-measured | 28.9 ms |
| 13 | `flow-silk-warp` | 33.2 ms | 28.9 ms |
| 16 | `spirolateral` | not re-measured | 29.0 ms |
| 17 | `softmax-halo` | 34.5 ms | 30.1 ms |
| 18 | `plasma-veil` | 37.8 ms | 32.0 ms |
| 19 | `kaleido-fold` | 36.0 ms | 31.6 ms |
| 20 | `roto-streaks` | 39.1 ms | 32.8 ms |
| 21 | `painterly-flow` | 38.7 ms | 31.7 ms |
| 22 | `reaction-field` | 34.0 ms | 29.6 ms |
| 23 | `starfield-drift` | 33.3 ms | 29.0 ms |

Until this pass every preset read 33.2 ms or more, and the readings clustered at
33.2 whatever the preset, which looked like a floor. It was the upscale. Taking
the screen draw out of a forced `roto-streaks` dropped it from 32.4 to 27.0 ms, so
the stretch of the 640x360 composite over 1280x720 was costing 5.4 ms.

- **The upscale is a shader pass.** `e.draw_target(comp_out, 0, 0, w, h)` is now
  `e.draw_shader(blit, ..., { fb = comp_out })` (`frag/blit.frag`, a textured
  copy). Same picture, byte for byte in the desktop verifier on every preset that
  nothing else touched, and 4.2 ms cheaper on the EYESY for every preset. This is
  where most of the table above comes from (e.g. `flow-silk-warp` 33.2 to 28.9).
  The cost was openFrameworks' default shader on the Pi, which every
  `draw_target` went through; eyesy-platform d2f0d67 draws targets with its own
  straight-line shader, after which the old `draw_target` version measures 29.07
  against 28.92 for the blit. The blit stays: it works on older engines and
  skips alpha blending.
- **`comp_plasma`: the centres' trig is in Lua.** The two orbiting centres move
  with sin/cos of the time, which the pixel was computing for all 230k pixels
  (four trig calls). They arrive as `plasma_c`. `plasma-veil` 33.4 to 32.0 ms
  after the upscale change. Desktop A/B: at most 1 of 255 per pixel, mean 0.00.
- **`blur1` runs at half size.** The blurred copy that `warp_blur` reads is a
  smooth, horizontally blurred image sampled back with a linear filter, so the
  `blur` target is 320x180 (a quarter of the pixels, same taps in source texels).
  `painterly-flow` 34.3 to 31.7 ms after the upscale change. Desktop A/B: mean
  0.41 of 255 over its verifier runs (1.27 with loud audio, worst pixel 36).
- **`comp_rotoblur`: 6 taps, no per-pixel `sin`.** The gather lost two of its
  eight taps (about 0.55 ms each); the dither offset comes from interleaved
  gradient noise instead of `fract(sin(..))`; the first tap's cos/sin is built
  from a Lua start angle and a short series for the small per-pixel offset; the
  tap loop works in uv units so it has no division. `roto-streaks` 34.8 to 32.8 ms
  after the upscale change. Desktop A/B: mean 1.6 of 255 (3.2 with loud audio),
  almost all of it the new dither pattern and the thinner smear, not a different
  picture. This is the only preset whose look changed visibly, and it has the
  least headroom: the frame is 32.8 ms, 0.5 ms under the budget.
- `kaleido-fold` needed nothing beyond the upscale (36.0 to 31.6 ms), and its
  desktop A/B is byte-identical.

Things measured and not worth doing: closing and reopening the `back` target
between the warp and the waves costs nothing measurable (merging them changed no
number); custom-wave point counts do not show at this resolution (halving
`roto-streaks`' two 192-point waves moved nothing); the warp's own maths is 0.4 ms
(replacing it with a plain copy saved that much). Each extra cheap, cache-local
fetch in a full-size pass is 0.19 ms, and a dependent gather such as a rotated
roto-blur tap is 0.55 ms, which is the unit to count in.

## What keeps it fast

- **Render at content resolution, then upscale.** The feedback runs at 640×360
  (480×270 for a preset that sets `warp_params.dense`), and the composite is
  drawn at that size too, then stretched to 1280×720. Full-resolution composite
  passes would dominate the frame. Targets filter linearly, so a deliberately
  blocky look needs a nearest-neighbour sample in the shader
  (`floor(uv*RES)+0.5`).
- **Per-pixel maths belongs in Lua.** Anything that is constant across a frame (trig of a
  rotation, a tone matrix, a division by the aspect) costs a few instructions on every
  one of 230k pixels if the fragment computes it. The VC4 runs about 0.08 ms per
  instruction per 640x360 pass.
- **Custom waves cost Lua time.** Every point runs the wave's equations on the
  CPU. Presets that only draw the built-in wave measured 27.3–27.4 ms; presets
  with one 160–384-point custom wave measured 27.8–31.8 ms. Use 160–256 samples
  unless the look needs more.
- **Particles are per-frame Lua too.** The starfield rebuilds every star as one
  triangle each frame: 224 stars is 672 vertices, about the cost of a couple of
  custom waves. A platform mesh holds at most 8192 vertices, so keep particle
  counts in the hundreds. Particle and wave coordinates are content-resolution
  pixels (640×360), not screen pixels.
- **Render targets are limited.** The platform allows eight. The mode uses four
  per content size (two for feedback ping-pong, one for the blur copy, one for
  the composite). Every current preset uses 640×360, so four are in use; a
  `dense` preset would use the other four.

## Rules that keep it correct

- **Never add light inside the feedback loop.** The warp pass only moves and
  darkens the previous frame. Anything brighter belongs in the composite, which
  is display-only. Light added inside the loop builds up to white within
  seconds. `tools/check_fragments.py` fails any warp fragment that does not
  apply `decay` or declare another bound.
- **Keep warp and sphere amounts modest.** Sampling outside the frame repeats
  the edge pixels, so extreme `sphere` or `zoom` values produce flat bands at
  the edges.
