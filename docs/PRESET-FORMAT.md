# Preset format

A preset is one Lua table in `milkdrop/presets/presets.lua`. The file returns a
list of them, and a preset's position in that list is its slot number: the
value knob 2 selects, and the value a saved scene stores.

This page describes the fields, the variables your equations can read and
write, and the expression language. The source of truth is the code:
`milkdrop/main.lua` for the fields and engine variables, and
`milkdrop/lib/evaluator.lua` for the language. `tools/check_presets.py`
checks a preset against this format ([preset contract](PRESET-CONTRACT.md)).

## The append-only rule

Saved scenes restore a preset by its 1-based slot number. So:

- **Add new presets at the end of the list.** Never insert or reorder.
- **Never delete a preset.** To retire one, replace it with a placeholder that
  keeps the slot (the catalog does this for slots 2, 7, 14, 15 and 24, named
  `retired-NN`).

Moving or removing an entry silently changes what every later saved scene plays.
No check can catch that, so it is a review rule.

## Fields

Every field below is required, even when it is empty, except the last two.

| Field | Type | What it does |
| --- | --- | --- |
| `name` | string | A unique, non-empty name |
| `per_frame_init` | equations | Runs when the preset loads and each time the trigger fires, with a fresh random seed. Use it to seed `q` variables and other per-run choices |
| `per_frame` | equations | Runs once per frame. Its results persist into the next frame. It is the only block that must compile; if it doesn't, the preset is skipped and the previous one keeps running |
| `per_pixel` | equations | Compiled and checked, but not used for rendering: the warp fragments compute their displacement themselves. Leave it `""` |
| `warp_archetype` | string | The warp fragment: `default`, `sphere`, `kaleido`, `blur` or `diffuse` (see below) |
| `comp_archetype` | string | The composite fragment: `default`, `softmax`, `plasma` or `rotoblur` |
| `warp_params` | table | Extra warp uniforms, by name. `dense = true` renders the preset at 480×270 instead of 640×360 |
| `comp_params` | table | The composite's own parameters (see below). Ignored by `default` |
| `wave_mode` | number | The built-in audio wave, drawn every frame: `0` line, `1` circle, `2` spokes, `3` spectrum bars |
| `wave_a` | number | The built-in wave's amplitude, 0–4 |
| `wave_r`, `wave_g`, `wave_b` | numbers | The built-in wave's colour, 0–1 (optional; default white) |
| `waves` | list | Up to 8 custom waves (see below) |
| `shapes` | list | Filled polygons (see below) |
| `decay` | number | The starting value of the `decay` variable |
| `q` | list | Starting values for `q1`, `q2`, ... |
| `param_bridge` | table, optional | Maps a warp uniform to a per-frame variable, for example `{ sectors = "wedges" }`, so a uniform follows a variable with another name |
| `particles` | table, optional | A starfield particle pool: `count` (up to 512), `speed`, `size`, and `tints` (four `{r, g, b}` colours, one per brightness class) |

### Archetypes

| Warp | What it does | Extra variables |
| --- | --- | --- |
| `default` | MilkDrop's standard warp: zoom, rotate, stretch and shift the previous frame, then darken it by `decay` | — |
| `sphere` | Adds a radial pinch toward the centre, for fly-in tunnels | `sphere` |
| `kaleido` | Folds the frame into `sectors` mirror-image wedges | `sectors`, `kaleido_angle` |
| `blur` | Mixes in a blurred copy of the previous frame, so trails smear like paint | `blur_warp`, `blur_spread` |
| `diffuse` | Runs one Gray-Scott reaction-diffusion step per frame instead of a warp. What you draw seeds it: red is reagent A, green is reagent B | `rd_feed`, `rd_kill`, `rd_dt`, `rd_scale` |

| Composite | What it does | `comp_params` |
| --- | --- | --- |
| `default` | Colour finishing only: gamma, brightness, contrast, saturation, hue, echo | — |
| `softmax` | Screen-blends the frame with a rotated, scaled copy of itself, for a halo | `soft_rot` (degrees), `soft_scale`, `soft_mix` |
| `plasma` | Lays an animated interference pattern over the scene | `plasma_scale`, `plasma_speed`, `plasma_lift`, `plasma_glow` |
| `rotoblur` | Smears the frame along arcs around the centre | `blur_rot`, `blur_rad`, `blur_mix` |

Every composite also does the `default` colour finishing. The composite only
affects what you see; it never feeds back into the next frame.

### Custom waves

Each entry in `waves` is a line drawn through `samples` points:

```lua
{ samples = 256, r = 0.5, g = 0.9, b = 1.0, a = 0.8,
  t1 = "th = sample*6.2831853; x = 0.5 + 0.3*cos(th); y = 0.5 + 0.3*sin(th);" }
```

`t1` runs once per point. It reads `sample` (0 to 1 along the wave), `value1`
and `value2` (the left and right audio sample at that point), and everything
the per-frame block can read. It sets `x` and `y`: 0 to 1, with (0.5, 0.5) at
the centre of the screen and `y` pointing up. Knob 3 scales the point count
from half to one and a half times `samples`. Each point costs Lua time on the
EYESY, so keep `samples` between 160 and 256 unless the look needs more.

### Shapes

Each entry in `shapes` is a filled regular polygon, fixed for the life of the
preset:

```lua
{ sides = 6, x = 0.5, y = 0.5, rad = 0.2, ang = 0, r = 1, g = 1, b = 1, a = 0.5 }
```

`x`, `y` and `rad` are in the same 0-to-1 units as the waves, and `ang` is in
degrees. Knob 3 scales the number of sides. Shapes are untextured.

## Variables

**Engine variables.** The per-frame block can write these. They start each
preset at their defaults, persist between frames, and are clamped to a safe
range before they reach the shaders:

| Group | Variables |
| --- | --- |
| Motion | `zoom`, `zoomexp`, `rot`, `warp`, `cx`, `cy`, `dx`, `dy`, `sx`, `sy` |
| Feedback | `decay` (1 keeps the trail forever; lower fades it faster) |
| Colour | `gamma`, `bright`, `contrast`, `saturation`, `hue`, `echo` |
| Archetype | `sphere`, `sectors`, `kaleido_angle`, `blur_warp`, `blur_spread`, `rd_feed`, `rd_kill`, `rd_dt`, `rd_scale` |

They mean what they mean in MilkDrop: `zoom` 1.01 zooms in 1% per frame, `rot`
turns the frame, `cx`/`cy` set the centre of zoom and rotation, `dx`/`dy` shift,
`sx`/`sy` stretch, and `warp` adds a wobble. The defaults and ranges are the
`ENGINE_VARS` table at the top of `main.lua`.

**Inputs.** Equations can read:

| Variable | Meaning |
| --- | --- |
| `bass`, `mid`, `treb` | This frame's band levels, about 0–2 |
| `bass_att`, `mid_att`, `treb_att` | The same, smoothed (0.6 s half-life). Usually the better choice for motion |
| `time`, `frame` | Seconds and frames since the preset loaded. Knob 1 scales how fast they advance |
| `progress` | `time` as a 0–1 cycle every 240 s |
| `fps` | The measured frame rate |
| `q1` ... `q32` | Free variables that persist between frames, and the place to keep state |

Any other name you assign is a custom variable. It also persists between
frames. A name that was never assigned reads as 0, so a typo such as
`bass_att1` quietly reads 0; `check_presets.py` warns about these.

## Expression language

The equations are MilkDrop-style statements separated by `;`:

```text
q1 = q1 + 0.01 + 0.05*bass_att;
zoom = 1.004 + 0.02*sin(q1);
```

- Operators: `+ - * / %` (floor modulo), `^` (power, right-associative), unary
  minus and parentheses.
- Functions: `sin cos tan asin acos atan atan2 abs min max sqr sqrt pow log
  log10 int sign exp sigmoid above below equal band bor bnot`, plus `if(c, a, b)`
  (only the chosen branch runs) and `rand(n)`.
- `rand` draws from a seeded generator. The trigger re-runs `per_frame_init`
  with a new seed, so `rand` there is how a preset varies itself on each hit.
- Every result is finite. Division by zero and other NaN or infinite results
  become 0, so a bad equation can't crash the mode.

## Your first preset

Copy an existing entry that uses the archetypes you want, append it to the end
of the list, give it a new `name`, and change its equations. Then run the checks
in the [README](../README.md#checks) and preview it:

```sh
./eyesyctl preview milkdrop --native   # from eyesy-platform; set knob 2 to the new slot
```
