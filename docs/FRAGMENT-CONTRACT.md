# Fragment contract

What `tools/check_fragments.py` enforces on `milkdrop/frag/*.frag` and on the
uniform traffic between the mode and those fragments. Run it before any fragment
or archetype wiring leaves a branch.

```sh
python3 tools/check_fragments.py                     # the library in place
python3 tools/check_fragments.py --expect-fragments 13 # also assert the size
python3 tools/check_fragments.py --json              # machine-readable report
```

Exit codes: `0` pass, `1` a fragment or a preset's fragment traffic broke the
contract, `2` the tool could not run.

## Why this exists

`docs/PRESET-CONTRACT.md` covers the catalog. The other half of the engine — the
fragments and the uniforms the mode hands them — had no gate at all, and it hides
the same class of bug the preset gate was built for: a name that is wrong, compiles,
and silently does nothing. A preset that says `warp_params = { sector = 8 }` where
the fragment declares `sectors` still renders; it just ignores the parameter. A
fragment that declares a uniform the mode never passes reads whatever the host
leaves behind, usually `0`.

## How it checks

It does not parse `main.lua`. It **runs** it — the mode is `dofile`d against a
recording stub of the `eyesy` handle, `setup()` runs, and then every preset is
drawn for two synthetic frames while each `draw_shader` call is recorded with the
fragment it went to and the names of the uniforms and samplers passed. The uniform
supply is therefore *observed*, not inferred, which is the same principle as the
preset gate driving the engine's own evaluator.

**Fails on:**

| Check | Detail |
| --- | --- |
| Host contract | no `#version` directive (the host adapts an ES2 body), a precision qualifier present, `varying vec2 uv` declared, exactly one `void main` |
| Uniforms | at least one declared; no duplicate names |
| Warp bound | every `warp_*.frag` must bound what it writes back: either it *uses* `decay`, or it carries a `warp-bound:` header line and calls `clamp()`. The warp pass is the only writer of the feedback target, so an unbounded one accumulates to white |
| Supply → declaration | every uniform name the engine hands a fragment must be declared by it; an undeclared name is a dead parameter |
| Declaration → supply | every uniform a fragment declares must be supplied by the engine; an unsupplied uniform is a silent zero |
| Per-preset reach | a preset's `warp_params` (minus the `dense` content-size flag), `param_bridge` and `comp_params` names must reach a real uniform |
| Archetype wiring | a preset's `warp_archetype`/`comp_archetype` must actually draw `warp_<arch>.frag`/`comp_<arch>.frag` |
| Reachability | every fragment the mode loads must exist on disk, and every `.frag` on disk must be loaded by `setup()` — an unreferenced fragment ships nothing |

**Warns (never fails) on:** a fragment with no sampler (a purely procedural field is
legitimate, and the gate must not force an archetype to read the feedback target just
to satisfy it), a loaded fragment no preset selects (building an archetype before the
presets that use it), and an archetype no preset uses.

**The `warp-bound:` exception is declared, not inferred.** `warp_diffuse` runs a
Gray-Scott step that replaces the field with a bounded function of the previous
state rather than decaying it, and a reaction-diffusion field has no decay to
express. The gate cannot prove boundedness, so it requires the claim to be visible
to a reviewer: a `warp-bound:` header line naming why the step is bounded, *and* a
`clamp()` in the body. `clamp()` alone is too weak — a fragment may clamp a
parameter rather than its output.

**Host-bound uniforms count as supplied.** The host binds `u_resolution`, `u_time`,
`u_energy` and `u_control` on every shader draw, plus `u_audio` when an audio
texture is allocated (`engine/src/runtime.cpp:713-719`), independently of the
mode's own args. They satisfy a fragment's declaration. They are deliberately not
treated as *received* uniforms, because the host hands them to every fragment — a
fragment that does not declare `u_time` is normal, not a dead parameter.

Comments are stripped before every source check. That is not cosmetic: each fragment
header documents its own uniforms, so an unstripped search for `decay` or
`sampler2D` would be satisfied by the prose alone.

`--expect-fragments N` is opt-in, for the same reason the preset gate's size
assertion is: the library grows as archetypes are ported.

## Proving the gate fires

A gate that only ever says PASS is worth nothing, so
`tools/check_fragments_negatives.py` mutates a throwaway copy of `milkdrop/` once
per check and asserts the gate fails, naming the culprit:

```sh
python3 tools/check_fragments_negatives.py            # 15 cases
python3 tools/check_fragments_negatives.py --list     # case names and expectations
```

The first case is the unmutated copy, so a gate that fails everything cannot pass
the suite either. The last asserts the gate exits `2` without an interpreter
rather than checking less than it claims. Two cases are there because the first
version of this gate got them wrong: a warp fragment whose `decay` *uniform* is
declared but whose arithmetic never uses it (the check read the declaration), and
`comp_params` on a default composite the mode ignores outright, which no
fragment-side check can see.

## What it does not check

- **Licensing.** As with presets, it cannot tell a self-authored port from a copied
  shader. Port **constructs, never files**; that rule is a human obligation.
- **Whether the fragment renders correctly.** It proves the traffic, not the image.
  That is `tools/check_render.py`'s job (`docs/RENDER-CONTRACT.md`): it compiles and
  renders each fragment on a real GLES2 driver and asserts the neutral identities.
  Neither replaces a device run for the look or the cost.
- **Cost.** Tier is a device measurement (offscreen p50 on VC4, ≤33.3 ms for tier C).
- **Shader compilation on the device.** The host adapts and compiles the body; a
  fragment that is structurally valid can still be rejected by the driver. Only a
  device run settles that.

## The contract, as it actually binds

`main.lua` supplies each fragment from a fixed base plus per-archetype extras:

| Fragment | Samplers | Supplied uniforms |
| --- | --- | --- |
| `warp_default` | `prev` | zoom, zoomexp, rot, warp, cx, cy, dx, dy, sx, sy, decay, aspect, texel |
| `warp_sphere` | `prev` | the above + `sphere` |
| `comp_default` | `fb` | gamma, bright, contrast, saturation, hue, echo |
| `comp_softmax` | `fb` | soft_rot, soft_scale, soft_mix + the `comp_default` set |
| `comp_plasma` | `fb` | plasma_scale, plasma_speed, plasma_lift, plasma_glow + the `comp_default` set, and the host's u_resolution and u_time |
| `comp_rotoblur` | `fb` | blur_rot, blur_rad, blur_mix + the `comp_default` set, and the host's u_resolution |
| `blur1` | `src` | texel, blur_w, blur_d, blur_scale, blur_bias |
| `warp_kaleido` | `prev` | the `warp_default` set + `sectors`, `kaleido_angle` |
| `warp_blur` | `prev`, `prev_blur` | the `warp_default` set + `blur_warp`, `blur_spread` |
| `warp_diffuse` | `prev` | rd_feed, rd_kill, rd_dt, rd_scale, texel (no geometric uniforms — it never warps) |

That table is a description of what the gate observes, not the source of truth — the
source of truth is `main.lua`, which is why the gate runs it. `warp_params.dense` is
the one preset parameter that is not a uniform: it selects the reduced content target.

`warp_blur` needs a second texture, so the mode runs a `blur1` pass over the feedback
target *before* the warp whenever `warp_archetype = blur`, into the same `blur` target
the glow composite later fills from `back`. The two never need it at the same moment,
which is why no extra target was needed — the budget is already full.