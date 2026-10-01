# 04 — Fragment sources: roto-blur / motion-trail composite, kaleidoscope fold warp

Scope: permissive GLSL sources for two display-only constructs on ES2/VC4 (720p, tier C). Port **constructs, never files**. Platform: no `#version`, `varying vec2 uv` with uv.y top-down, ≤6 samplers, composite pass never sampled back (no feedback hazard inside the pass).

Existing fragments (port targets, from `milkdrop/frag/`): `blur1.frag`, `comp_default.frag`, `comp_glow.frag`, `warp_default.frag`, `warp_sector.frag`, `warp_sphere.frag`.

## Construct A — roto-blur / motion-trail composite (display-only blend)

### Candidates

| # | Source (URL) | Implements | Licence + basis | ES2 risks | Route |
|---|---|---|---|---|---|
| A1 | three.js `AfterimageShader.js` — https://github.com/mrdoob/three.js/blob/dev/examples/jsm/shaders/AfterimageShader.js | Motion-trail composite: decay old gather by `damp`, blend with new via `max()` (non-clipping additive look) | **MIT** — repo-root `LICENSE` of mrdoob/three.js ("The MIT License, Copyright © 2010-2026 three.js authors"); file ships in the MIT-scoped examples tree | None: ES2-native (`texture2D`, `gl_FragColor`, `sign`/`max`); 2 samplers; no derivatives, no loops. Rename `vUv`→`uv` | Extends `comp_default.frag` (2-gather display composite). **Needs a cross-frame hold texture for tOld** — the "old" gather must persist between frames; platform question if the harness cannot retain one `[INFERENCE]` |
| A2 | gl-transitions `tangentMotionBlur.glsl` — https://github.com/gl-transitions/gl-transitions/blob/master/transitions/tangentMotionBlur.glsl | Directional motion-blur gather: ~20 weighted taps along a velocity vector with jittered start; includes `rotateUv()` (mat2 rotation about an anchor) | **MIT** — per-file header `// License: MIT` (author chenkai); repo `LICENSE` ("MIT License … Individual transitions … may have their own license specified in their file header comments", per-file beats repo) | Mostly clean: float loop `t <= 20.0` (constant bound, ES2-legal; ~20 iter OK for VC4), `mat2` ctor, `fract`, sin-based `rand`. Aspect: uses `1./ratio` — drop or pass `ratio` uniform (720p is 16:9, arc sampling needs aspect-corrected center-to-uv mapping) | Extends `blur1.frag`: swap the linear `speed*percent` offset for arc `rotateUv(uv, a0+(a1-a0)*t, center)` → true roto-blur gather; blend = weighted mean (A1's decay/max can layer on top if a hold buffer exists) |

**Negative, stated plainly:** no dedicated permissively-licensed shader computing rotational (arc) blur was found. Web search for `"rotational blur" OR "roto blur" OR "spin blur" GLSL MIT license` returned no usable permissive source (hits: generic GitHub, a ComfyUI node page pointing at Deforum, MIT — but not a shader artifact). The construct is fully reproducible from A2's gather + rotation helper. Shadertoy roto-blur shaders were **excluded class-wide**: Shadertoy's default licence is proprietary "Standard" (all rights reserved), and per-shader Creative Commons status could not be verified within budget → study-only, none recorded.

### Construct (A1 + A2, 5 lines each)
```
// A2 gather — arc taps, parabolic weight, jittered start
for (float t = 0.0; t <= 1.0; t += 1.0/18.0) {
    float w = 4.0 * (t - t*t);                                 // peak at midpoint
    col += texture2D(src, rotateUv(uv, a0 + (a1-a0)*t, center)).rgb * w;
}
col /= total;
// A1 blend — decayed old vs new, additive look without clipping
old *= damp * max(sign(old - 0.1), 0.0);   // kill near-black residue
gl_FragColor = max(newSample, old);
```

**PORTED 2026-09-18** — `milkdrop/frag/comp_rotoblur.frag`, archetype `rotoblur`, catalog
slot 20 (`roto-streaks`). The A2 gather is what landed: 8 taps (the ceiling the
backlog sets) with the triangular weight `4*(f - f^2)` and a per-pixel jitter, traced
along an **arc about the screen centre** rather than a linear direction, plus an
optional radial sweep. A1's damped-old-frame blend is deliberately **not** ported: this
engine already decays the previous frame in the warp pass, so a second cross-frame hold
would duplicate the feedback rather than add a blur. Verified on a real GLES2 driver:
with no sweep or with `blur_mix = 0` the output is byte-exact passthrough (0.00/255),
sweeping 0.35 rad drops angular energy at radius 0.28 to 0.57x while preserving mean
luma at that radius to 0.01, and `blur_rot` drives angular energy 9.20 -> 4.67
monotonically where `blur_rad` instead moves luma 0.60 -> 0.25. So the two axes are
independent and the smear is genuinely tangential.

## Construct B — analytic kaleidoscope fold warp

### Candidates

| # | Source (URL) | Implements | Licence + basis | ES2 risks | Route |
|---|---|---|---|---|---|
| B1 | three.js `KaleidoShader.js` — https://github.com/mrdoob/three.js/blob/dev/examples/jsm/shaders/KaleidoShader.js | Polar sector fold: `mod()`+`abs()` fold of atan2 angle into one of `sides` sectors, re-projected by radius (ported from pixelshaders.com / Toby Schachman into three.js examples) | **MIT** — repo-root `LICENSE` (as A1); file header records provenance only, no separate licence, repo MIT governs | None: pure math, 1 sampler, no loops/derivatives, ES2-native. With uv.y top-down the fold mirrors sense — cosmetic. `vUv`→`uv` rename | Extends/replaces `warp_sector.frag`: fold warp maps uv→uv' before main warp math |
| B2 | gl-transitions `kaleidoscope.glsl` — https://github.com/gl-transitions/gl-transitions/blob/master/transitions/kaleidoscope.glsl | Mirror-tile kaleidoscope: iterated rotation (7 steps) + ping-pong `abs(mod(p,2)-1)` tiling | **MIT** — per-file header `// License: MIT` (author nwoeanhinnogaehr) + repo `LICENSE` per-file clause | Clean: int loop (7), `mod`/`abs`/`sin`/`cos`; ES2-legal. Tiles cross the seam at sector boundaries (tile variety, not smooth-fold variety) | Alternative to B1 in `warp_sector.frag` if a tiled look is wanted |
| B3 | gl-transitions `powerKaleido.glsl` — https://github.com/gl-transitions/gl-transitions/blob/master/transitions/powerKaleido.glsl | Reflexion kaleidoscope: 10-iteration loop reflecting uv across rotating sector normals (`refl`, `rot` helpers) | **MIT** — per-file header `// License: MIT` (author Boundless) + repo clause | **Heavy**: nested float loops (10 × ~6), `tan`/`asin`/`sign` per reflection — high VC4 ALU cost at 720p; keep as reference only or trim iterations | Study / optional variant |
| B4 | LYGIA `space/kaleidoscope.glsl` — https://github.com/patriciogonzalezvivo/lygia/blob/main/space/kaleidoscope.glsl | Polar fold (`floor`-based sector clamp + `min(angle, seg-angle)` + mirror `max(min(kuv,2-kuv),-kuv)`), per Daniel Ilett's kaleidoscope tutorial | **NOT permissive → study-only.** Repo `LICENSE.md` is **The Prosperity Public License 3.0.0** (source-available, non-commercial; 30-day commercial trial), NOT MIT as sometimes assumed | Clean ES2 math, no loops — a good *recipe* reference | None (licence blocks); construct reimplemented from the recipe if wanted |

**Shadertoy class caveat** applies to B as well (proprietary default licence, unverifiable per-shader CC within budget → excluded).

### Construct (B1, 5 lines)
```
vec2 p = uv - 0.5;  float r = length(p);
float a = atan(p.y, p.x) + angle;                 // angle uniform animates
a = mod(a, TAU / sides);
a = abs(a - TAU / (2.0 * sides));                 // mirror-fold into one sector
vec2 warp_uv = r * vec2(cos(a), sin(a)) + 0.5;    // sample here
```

**PORTED 2026-09-18** — `milkdrop/frag/warp_kaleido.frag`, archetype `kaleido`, catalog
slot 19 (`kaleido-fold`). Self-authored implementation of the fold, wired into the
MilkDrop warp chain: the wedge count comes from the engine's existing `sectors`, the
fold rotation from a new per-frame `kaleido_angle` engine var, and it decays like every
warp fragment must. Radius is preserved by the fold, so the radial warp terms keep their
magnitude and only the direction mirrors; being a projection, it converges in one frame
rather than compounding in the feedback. Verified on a real GLES2 driver: matches an
independent reference to 0.50/255, and the rendered frame is exactly N-fold
angular-periodic — `a vs a+60°` differs by 0.12-1.57/255 where the `a+17°` control
differs by 12.4-17.9 — with the within-wedge mirror `a vs 60°-a` also matching (0.18-2.27)
and the period moving to 120° when `sectors` is 3 (1.66-2.20). Re-measured after the warp
coordinate fixes recorded in `docs/PORT-BACKLOG.md`; the fragment itself was unchanged.

## Ranking (clarity × licence clarity)
1. **B — three.js `KaleidoShader.js` (MIT)**: smallest, pure-analytic ES2 body, licence verified at repo root; drop-in warp fold.
2. **A — three.js `AfterimageShader.js` (MIT)**: crisply the composite blend, licence verified; needs cross-frame hold for the "old" gather.
3. A — gl-transitions `tangentMotionBlur.glsl` (MIT per-file): supplies the rotation + multi-tap gather that makes roto-blur possible; more moving parts (ratio, 20-tap loop).

**Best source per construct:** A → three.js `AfterimageShader.js` (MIT) as the composite; pair with gl-transitions `tangentMotionBlur.glsl` (MIT) for the rotational gather. B → three.js `KaleidoShader.js` (MIT).

## Search log (repeatable)
- Entry points: three.js `examples/jsm/shaders/` (targeted file reads; MIT known at repo root, re-verified live); gl-transitions transition library (shallow clone → `ls transitions/ | grep -iE 'kaleido|blur|wind|trail|spin|roto'` → 125 transitions, 4 relevant); LYGIA shader library (clone → `grep -ri kaleido` + `find -iname '*kaleido*'` → licence check on `LICENSE.md`).
- Queries: GitHub file reads `mrdoob/three.js` (`LICENSE`, `examples/jsm/shaders/KaleidoShader.js`, `AfterimageShader.js`); `gl-transitions/gl-transitions` (`LICENSE`, `transitions/kaleidoscope.glsl`, `powerKaleido.glsl`, `tangentMotionBlur.glsl`); `patriciogonzalezvivo/lygia` (`LICENSE.md`, `space/kaleidoscope.glsl`). Web search: `github shader "rotational blur" OR "roto blur" OR "spin blur" GLSL MIT license fragment` → negative for a dedicated permissive roto-blur.
- Verification method: every licence statement above is from a file read live at the record's URL (repo `LICENSE`/`LICENSE.md` or per-file header), not from memory or repo metadata.

## Verdict summary
- Both constructs have permissive sources: A → MIT (A1 + A2); B → MIT (B1–B3). No clean negative needed.
- Undetermined: whether the harness can retain a cross-frame hold texture for the afterimage "old" gather — A1's trail mode depends on it (roto-blur itself does not); aspect/`ratio` treatment for A2 on 16:9 720p; `KaleidoShader`'s top-down uv mirror sense is cosmetic, confirm visually.
- Study-only records: B4 (LYGIA, Prosperity 3.0.0 — non-commercial, not usable) and Shadertoy class-wide (unverifiable default licence).