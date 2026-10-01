# 03 — Fragment sources: plasma/interference composite + soft-max composite

Status: FINAL. Platform: GLES2 / ES2 fragment bodies (no `#version`), VC4 V3D 2.1, 720p, tier C ≤33.3 ms offscreen p50, `varying vec2 uv` (uv.y top-down), ≤6 samplers, no vertex texture fetch. Composite pass is display-only (never sampled back → no feedback hazard).

Port rule: **construct, never file.** Verdicts below rest only on verified licence text (repo LICENSE file / README statement / spec licence notice). Anything not verifiable by tooling is marked **study-only**.

## Ranking

| Rank | Construct | Best source | Licence (basis) |
|---|---|---|---|
| 1 | Soft-max composite | `jamieowen/glsl-blend` `screen.glsl` | MIT — repo `LICENSE.md` ("The MIT License (MIT) Copyright (c) 2015 Jamie Owen", fetched) + README "License: MIT" |
| 2 | Plasma / interference | `maravexa/hyprsaver` `shaders/plasma.frag` | MIT — repo `LICENSE` (full MIT text, fetched) |

## Construct 1 — plasma / interference field

### 1.1 maravexa/hyprsaver — `shaders/plasma.frag` — **VERIFIED MIT** (best)
- URL: https://github.com/maravexa/hyprsaver/blob/main/shaders/plasma.frag
- Implements: classic plasma — four overlapping sine layers (horizontal, diagonal, two radial around animated centres), `wave(x)=sin(x)*0.5+0.5`, averaged into one field, fine-detail second harmonic, palette-mapped (`palette()`), slow palette rotation, crest brightness modulation. Exactly the `0.5+0.5*sin(Σ harmonic terms)` family; display-only, no feedback.
- Licence: **MIT** — basis: repo `LICENSE` file, fetched verbatim: "MIT License / Copyright (c) 2026 Mara Vexa".
- ES2 risks: `#version 320 es` + `precision highp float` must be stripped/replaced per host convention (VC4 accepts highp in fragments, but the body targets GLSL 3.20-style naming); `gl_FragCoord`/`u_resolution` centring → replace with `varying vec2 uv` (note top-down mismatch: flip uv.y as the host's other frags do); `u_speed_scale`/`u_mouse`/`u_frame` are host-injected → drop; `palette()` is host-injected by hyprsaver → bind to our palette LUT. No loop constructs, no derivatives, 0 texture samplers (cost ≈ 4×sin + 2×length + 1×sin detail per pixel).
- Construct:
  ```glsl
  float wave(float x) { return sin(x)*0.5 + 0.5; }
  // uv centered on screen; t = time*speed
  float v1 = wave(uv.x*6.2 + t*0.7);                       // horizontal ripple
  float v2 = wave(uv.x*3.4 + uv.y*4.6 - t*1.1);            // diagonal
  float v3 = wave(length(uv - c3)*9.4 - t*1.9);            // radial, c3 animated
  float v4 = wave(length(uv - c4)*6.6 + t*1.3);            // radial, c4 animated
  float field = clamp((v1+v2+v3+v4)*0.25 + wave(field*12.57 + t*0.3)*0.15, 0., 1.);
  col = palette(field);  // display-only composite output
  ```
- Port route: new `comp_plasma.frag` in the composite family modeled on `comp_default.frag` (same uniforms/sampler wiring, display-only pass). Procedural field (0 samplers) → optionally one `texture2D` blend into the gather texture; stays well under the 6-sampler cap.
- **PORTED 2026-09-18** — `milkdrop/frag/comp_plasma.frag`, archetype `plasma`, catalog slot 18 (`plasma-veil`). The field drives and veils the scene rather than replacing it, because a composite must composite the warped feedback; hyprsaver's host-injected `palette()` is **not** ported — a self-authored two-stop ramp stands in. The radial layers read aspect-correct Cartesian (screen-height units, as the source does), which needs `u_resolution` — so the fragment gate learned the host-bound uniforms (`u_resolution`, `u_time`, `u_energy`, `u_control`, `u_audio`) instead of treating them as engine-never-supplies. Verified on a real GLES2 driver at three times: matches an independent reference to 0.63/255, and the field moves 17.2% of pixels across a 20/255 luma delta between t=0 and t=1.7.

### 1.2 maravexa/hyprsaver — `shaders/caustics.frag` — **VERIFIED MIT** (interference variant)
- URL: https://github.com/maravexa/hyprsaver/blob/main/shaders/caustics.frag
- Implements: interference-field variant — four planar waves `abs(sin(dot(uv,dir)*freq + t*speed))` at rotated directions multiplied (product spikes where crests coincide), `pow` sharpening, low-frequency heave modulation, palette mapping. Same licence basis as 1.1 (repo `LICENSE`, MIT).
- ES2 risks: as 1.1 (`#version`/precision/uniforms/palette injection), plus `mix`/`smoothstep`/`pow` are ES2-safe; 4×sin per pixel, no samplers.
- Port route: same as 1.1 — sibling `comp_caustics.frag`.

### 1.3 Shadertoy plasma shaders — **STUDY-ONLY as a class**
- Entry point found: e.g. "Plasma Waves V2" https://www.shadertoy.com/view/tftfzj (djalf, 2025).
- Licence: **cannot be established** — shadertoy.com returns HTTP 403 to direct fetch and the archive.org snapshot of the view page 404s, so the per-shader licence field (CC BY-NC-SA / CC BY / CC0 / All Rights Reserved) is not verifiable with available tooling. Judgement would require a browser session; until then every Shadertoy source stays study-only. This is a class negative, not evidence of non-permissive licensing.

Clean negative: no permissive-Shadertoy core found *verified*. Negatives recorded in search log: bgfx (BSD-2, verified) has **no** plasma example in current master; raylib (zlib, verified) glsl330 shader set has **no** plasma shader; google/grafika (Apache-2.0) has **no** Plasma activity in current master; glslViewer `examples/` (MIT) contains only test frags + media; iquilezles.org returns 404 to tooling → licence statement unverifiable → study-only.

## Construct 2 — soft-max composite (`a + b − a·b`)

### 2.1 jamieowen/glsl-blend — `screen.glsl` — **VERIFIED MIT** (best)
- URL: https://github.com/jamieowen/glsl-blend/blob/master/screen.glsl
- Implements: screen blend, per-channel `1 − (1−a)(1−b) ≡ a + b − a·b`, plus `vec3` overload and opacity overload — exactly the requested soft-max (additive look, no clipping to white). Package is the stackgl/glslify blend-mode suite (add, soft-light, overlay, …).
- Licence: **MIT** — basis: repo `LICENSE.md` fetched verbatim ("The MIT License (MIT) Copyright (c) 2015 Jamie Owen"); confirmed by README "## License — MIT. See LICENSE.md".
- ES2 risks: none material — plain GLSL ES functions, scalar and vec3 overloads, no loops/derivatives; `#pragma glslify: export(blendScreen)` lines are preprocessor chatter for a plain-body port and are dropped.
- Construct (verified source, verbatim form):
  ```glsl
  float blendScreen(float base, float blend) { return 1.0 - ((1.0-base) * (1.0-blend)); }
  // vec3 overload applies per channel; == base + blend - base*blend
  // multi-gather: col = blendScreen(blendScreen(g1, g2), g3);
  ```
- Port route: new `comp_softmax.frag` modeled on `comp_default.frag`: two (or three) gather `texture2D` samples → screen blend per channel → clamp → output. Display-only; ≤3 samplers, leaves headroom under the 6-sampler cap.
- **PORTED 2026-09-18** — `milkdrop/frag/comp_softmax.frag`, archetype `softmax`, catalog slot 17 (`softmax-halo`). One `fb` sampler sampled twice through a rotate/scale gather; the source's opacity overload carries `soft_mix`, so `soft_mix = 0` is exact passthrough. Verified on a real GLES2 driver: output matches an independent reference to 0.58/255, and the gather moves 13.9% of pixels across a 20/255 luma delta on structured content (0% on a smooth ramp, which is why the probe content matters).

### 2.2 W3C Compositing and Blending Level 1 — screen formula authority
- URL: https://www.w3.org/TR/compositing-1/
- Licence: **W3C Document License** (use with attribution allowed) — basis: standard W3C TR licence notice on the document header; fetch via W3C API returned the document header/metadata (title, status CRD 2024-03-21, editors). Not a software licence and not GLSL: cited as the authoritative statement that `screen = 1 − (1 − Cb)(1 − Cs)` and that the algebra is a spec-level definition, safe to reimplement.
- ES2 risks: n/a (formula reference only).

### 2.3 jamieowen/glsl-blend — same package, adjacent modes
- `soft-light.glsl`, `add.glsl`, opacity overload in `screen.glsl` (2.1). Same MIT basis. Useful when the composite wants a tuned soft-falloff instead of pure screen. Port route as 2.1.

## Search log (repeatable)
- Repo read (the only one permitted): `ls frag/` → `blur1`, `comp_default`, `comp_glow`, `warp_default`, `warp_sector`, `warp_sphere` (`.frag`).
- GitHub device (`file_read`): `jamieowen/glsl-blend` `LICENSE.md` + `README.md` + `screen.glsl` (MIT, formula); `maravexa/hyprsaver` `LICENSE` + `shaders/plasma.frag` + `shaders/caustics.frag` (MIT, plasma); `bkaradzic/bgfx` `LICENSE` (BSD-2, no plasma example found); `Gargaj/Bonzomatic` `LICENSE` (Unlicense — no in-scope plasma/composite shader pursued).
- GitHub API dir listings: `patriciogonzalezvivo/glslViewer/examples` (no plasma), `raysan5/raylib …/glsl330` (no plasma), `google/grafika …/grafika` (no Plasma activity), `bkaradzic/bgfx/examples` (examples renumbered; no 30-plasma), `gl-transitions/gl-transitions/transitions` (no screen-blend transition), `maravexa/hyprsaver` `src/` + repo root.
- web_search queries: `shadertoy plasma shader CC0 OR "public domain" OR "CC BY" license fragment`; `site:shadertoy.com plasma fragment shader`; `github "plasma" ".frag" OR "plasma shader" fragment GLSL repo MIT license -milkdrop`; `"iquilezles" shader "free to use" OR "public domain" OR license use commercially` — only 1.1/1.2/2.1 yielded verifiable permissive licence text.
- Direct fetch failures (→ study-only, recorded): `shadertoy.com/view/*` (403), `web.archive.org` snapshot of shadertoy view page (404), `iquilezles.org` root/articles (404).

## Undetermined
- Per-shader Shadertoy licences (class-wide; needs a browser session to read the licence field).
- iquilezles.org licence statement (site blocks tooling; famous shader corpus, otherwise a top candidate for both constructs).