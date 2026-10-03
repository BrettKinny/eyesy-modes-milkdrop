# Render contract

What `tools/check_render.py` — driving `tools/gl_render.c` — proves about the mode's
fragments, and what it deliberately cannot. Run it before any fragment change lands.

```sh
python3 tools/check_render.py             # every case
python3 tools/check_render.py --json      # machine-readable report
python3 tools/check_render.py --self-test # prove the checks fire, then exit
```

Exit codes: `0` every case passed, `1` a case failed, `2` the tool could not run.

## Why this exists

`docs/FRAGMENT-CONTRACT.md` covers the uniform *traffic* between the mode and its
fragments. Traffic is not a picture: a fragment can honour every name the fragment
gate checks and still be rejected by the driver, sample the wrong region of the
frame, or write a flat one. The render gate is the only check in this repo that
compiles and runs the shaders for real.

It is not a nicety. The two defects described in [porting](PORTING.md#two-bugs-found-by-rendering) — the warp
chain sampling half a screen below the intended uv, and the inverted `zoomexp`
exponent — were both invisible to every other check and both found by rendering.
The identity cases here are their regression tests: `warp_default` with `zoom 1 /
zoomexp 1` must return the input frame byte for byte, and with the old code it
returned it shifted 128 rows down on a 256-row frame.

## How it checks

`tools/gl_render.c` opens an EGL context (pbuffer, falling back to surfaceless),
compiles the fragment under the host's own preamble, renders one full-screen quad
into an RGBA8 framebuffer and reads the frame back. It reproduces the engine's
contract from the platform's `engine/src/runtime.cpp`: the fragment body verbatim with no
`#version`, `uv = position.xy / u_resolution` with the origin top-left, and
`u_resolution` / `u_time` filled the way the host fills them.

**The uniform values come from the mode, not from this file.** The gate loads
`main.lua` against a recording stub, draws the catalog, and reads back what the
engine actually hands each fragment — scalars and vectors both, so `blur1` gets
the real `blur_w`/`blur_d` weight rows. A table of values in the gate would be a
second statement of the contract, free to drift from the mode; this cannot drift,
and a fragment the mode never draws is a failure rather than a silent skip.

The input texture is generated in the harness: a ring and eight spokes for angular
structure, over a diagonal ramp with an off-centre blob for asymmetry. The
asymmetry is deliberate — a symmetric pattern makes mirror- and direction-sensitive
checks pass vacuously.

**Checks per case:**

| Check | What it asserts |
| --- | --- |
| `renders` | the driver compiles and links it, `glGetError` is clean, and the frame is not degenerate (not flat, not black) |
| `identity` | with a fragment's neutral parameters, the output equals the input texture byte for byte |
| `differs` | with its archetype's real parameters, the fragment actually changes the frame |
| `periodic` | the kaleidoscope's N-fold angular symmetry, measured on the rendered frame, with a control pair that must differ more |

The `periodic` check is comparative on purpose: the periodic pairs must agree *and*
agree much better than pairs that are not a period apart, so a fragment that
ignores `sectors` cannot pass by rendering something smooth.

Both PPMs — the frame and the dumped input — are written top-down, so a check can
compare them directly without re-deriving the pattern.

**The self-test** builds fragments that are broken in the ways the gate claims to
catch — one that will not compile, one that writes a flat frame — and asserts every
one is rejected. A gate whose failure paths are never exercised is a gate nobody
should trust.

## What it does not check

- **Whether the picture is any good.** It proves a fragment renders and that its
  claimed invariants hold. Whether the look is the look is the human pass over a
  contact sheet.
- **The device driver.** This runs on whatever desktop GLES2 driver is present
  (llvmpipe here, a software rasteriser, but a real driver all the same). VC4 V3D
  2.1 on the Pi is a different implementation with different limits; a fragment
  that links here can still be rejected there. Only a device run settles that.
- **Cost.** Tier is a device measurement (offscreen p50 on VC4, ≤33.3 ms for tier
  C). Nothing here predicts frame time.
- **The whole frame.** It renders one fragment, not the pass chain. Whether the
  mode's warp → waves → composite sequence produces the right final image is the
  device run's business (the platform's `tools/scene_verify.py`).
- **Licensing**, as with every gate here. It cannot tell a self-authored port from
  a copied shader.

## Requirements

A Lua interpreter (the same list the fragment gate accepts, or
`$CHECK_RENDER_LUA`), a C compiler (`cc`, `gcc`, `clang`, or `$CHECK_RENDER_CC`),
and EGL/GLES2 development files. The harness is compiled once into a cache keyed by
a hash of its source, so it rebuilds only when `tools/gl_render.c` changes.

Missing any of those exits `2` rather than skipping the checks, for the same
reason the other gates do: a validator that silently checks less than it claims is
worse than one that refuses to run.