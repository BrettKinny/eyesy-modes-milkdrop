# MilkDrop / AVS Historian — lineage, 15 preset archetypes, eyesy mapping

> Converted from a research-agent JSON artifact to Markdown on 2026-09-17; content unchanged.

## Summary

Research document grounding a 100+ scene library for eyesy in the Winamp-era visualizer lineage (Lissajous/oscilloscope → Cthugha → Winamp AVS → MilkDrop/MilkDrop2 → projectM → Butterchurn), mapping 15 canonical preset archetypes to the eyesy platform with equation essences, feasibility tiers, and knob/trigger mappings. Every finding is grounded in primary docs (Ryan Geiss authoring guide lineage, MilkDrop3 pipeline, Butterchurn WebGL impl) and in-repo reference idioms (modes/phosphor, modes/kali-bloom). The single most load-bearing insight: MilkDrop's warp/composite split — warp bakes into the feedback buffer, composite is display-only — maps directly onto eyesy's render-target ping-pong and resolves the in-repo 'bloom-in-feedback' design trap.

## Files

| path | description |
| --- | --- |
| docs/API.md | eyesy scene API: ctx.audio/midi/knobs/trigger, render targets (8, ping-pong), ES2 fragment shaders, meshes (8192 verts), cosine palettes, u_audio sampler — the hard platform contract every archetype maps to. |
| modes/phosphor/main.lua | Reference idiom for feedback+decay (half-res ping-pong targets), CPU audio-trace polylines (N=384), trigger re-seed of Lissajous ratios. Canonical 'oscilloscope focus' archetype. |
| modes/phosphor/phosphor.frag | Reference feedback-decay shader: rotated/zoomed prev-frame sample × decay + vignette; carries the 'no bloom inside feedback loop' comment. |
| modes/kali-bloom/kali.frag | Reference per-pixel field shader (10-iteration kaliset) + MilkDrop-style feedback with bounded max() composite; carries the 'clamp denominator 1e-9, not 1e-4' trap comment. |
| modes/kali-bloom/main.lua | Half-res target + upscale pattern for a shader-heavy scene (~30ms on device); the perf envelope template for Tier 2 scenes. |
## Architecture

Three-layer pipeline already proven in-repo (half-res ping-pong feedback targets upscaled to 1280x720, immediate prims + line-strip meshes on top, ES2 fragment shaders binding prior targets as samplers) is the shared substrate for all 15 archetypes. Cross-cutting discipline from MilkDrop2: keep a 'warp' pass that writes INTO the decayed feedback buffer and a display-only 'composite' pass that never samples a target it writes — producing MilkDrop's signature persistence while sidestepping the in-repo bloom self-amplify trap. Warp = per-pixel displacement in the fragment shader reading the previous target (Butterchurn's weak-GPU path; no vertex texture fetch exists in GLES2). CPU cost confined to per-frame polyline/particle mesh rebuilds (<=1024 pts) with persistent mesh handles. Full-res only for trivial single-pass scenes; heavy scenes at 640x360 targets upscaled.

## Report
WELTGEIST/ART-FORM LINEAGE (how we got here, so scenes carry the history)

1. ANALOG OSCILLOSCOPE / LISSAJOUS (pre-digital visual music): driving a scope's X and Y inputs with the left/right channels yields 2D Lissajous figures (integer frequency-ratio patterns like 5:7). Origin of both the 'oscilloscope focus' and 'superscope' archetypes. The scope also gave us persistence trails (phosphor) — real CRTs literally decayed the trace.
2. CTHUGHA (Kevin 'Zaph' Burfitt, 1994, MS-DOS): the founding feedback machine — a 256-color pixel grid where each frame (a) injects audio-reactive waves/particles, (b) runs a cellular-automaton decay pass (each pixel's value from neighbor averages), (c) applies a translation/warp step (zoom/rotate/scroll), then renders through a cycling color palette. Established the feedback→decay→warp→palette recipe that defines audio-viz to this day; ported to Winamp.
3. WINAMP AVS (Justin Frankel / Nullsoft, 2000): the modular revolution. Presets are render-LISTS — stacked effect components (sources + transforms) evaluated in order — edited visually, with a scripting engine (expression language, the ancestor of MilkDrop's EEL) letting users write math directly (e.g. r = r + sin(d*4)). Its look still defines audio-viz because it made the art form a user-authorable combinator of a small set of primitives.
4. MILKDROP (Ryan Geiss, 2001): pushed the recipe onto the GPU. Same machine as Cthugha (feedback buffer + decay + warp + waveform overlay) but the warp became parametric/scriptable: per-frame and per-vertex EEL equations drive a handful of motion params (zoom, rotation, stretch, ripple, pan) over a coarse screen-space WARP MESH (32x24 to 48x36), the GPU interpolating across all pixels. Preset switching itself is an event: randomized per-vertex wipe patterns (directional sweeps, radial reveals) blend old/new warp fields.
5. MILKDROP 2 (Geiss, 2007): true per-pixel programmability via pixel shaders — a WARP SHADER (its output baked into the feedback texture, persisting) and a COMPOSITE SHADER (display-only finishing: gamma, echo, hue). This warp/composite split is the load-bearing concept to steal. Self-normalizing audio measures (bass/mid/treble scaled so 1.0 = 'average loudness for this song') let thousands of community presets react to any track.
6. OPEN SOURCE: projectM (MilkDrop-compatible, cross-platform) ships ~10k curated presets; Butterchurn (jberg, MIT) is a faithful WebGL 2 port — the best weak-GPU per-pixel warp reference.

WHY AVS'S LOOK STILL DEFINES AUDIO-VIZ: it reduced the infinite space of visuals to a small combinatorial grammar (sources + transforms + feedback + palette) that runs on any hardware; every later engine (MilkDrop, projectM, Butterchurn, eyesy's own feedback scenes) is a refinement of that grammar, not a departure.

CANONICAL AVS EFFECTS (render-list components) — their algorithmic cores:
- Superscope: parametric polyline x(u),y(u),z(u) per point, per-point audio equations, optional mirror/fold ('scope' on). -> CPU polyline.
- Movement (MVP): 2D warp grid with custom x/y displacement equations per vertex — the direct ancestor of MilkDrop's warp mesh.
- Moving Particle / Dot Fountain: gravity-driven particle emitter, wrap/reflect at edges.
- 2D/3D Shape: polygon/3D-object projection component.
- Dynamic Movement: per-pixel displacement driven by two lookup-table images.
- Kaleidoscope: mirror the frame into N radial slices.
- Water: pseudo-3D ripple. Bump: bumpmap lighting over a texture. Blur/Brightness/Color-reduction/Invert: image ops. Buffer Save/Restore: explicit feedback. Milky Way: additive twinkle/grain. Radiosity: glow bleed.

MILKDROP PRESET MODEL (per Geiss authoring guide + MilkDrop3 pipeline doc):
- Per-frame equations: update motion parameters (zoom, rot, warps, pan, ripple) + colors every frame.
- Per-vertex equations: displace each warp-mesh vertex (base/zoom/rot/warp/ripple).
- Warp mesh: coarse grid textured with previous frame; the warp shader reads the PREVIOUS framebuffer texture and displaces samples per mesh/vertex, interpolated across pixels.
- Feedback decay: each frame the buffer is multiplied by < 1 (typically 0.9-0.98), plus an 'echo zoom' on the sampled texture.
- Wave modes: ~8 waveform styles (spectrum bars, line, off, etc.) drawn over/under the image.
- Custom shapes: user-defined polyline shapes as components.
- Composite shader: display-only finishing pass.
- Motion vectors / self-normalized audio: bass/mid/treble smoothed and normalized.
- Transitions: per-vertex wipe blend between presets.

BUTTERCHURN (WebGL2 MilkDrop2) — the reference for OUR weak GPU: it reproduces the per-pixel warp by sampling the previous-frame render target in a pixel shader, which is EXACTLY eyesy's draw_shader-with-target-sampler mechanism. GLES2 has no vertex-texture-fetch, so the fragment-warp path (not the classic CPU-mesh+GPU-interpolate) is the right one for VC4 V3D2; a reduced CPU warp grid (updated per-frame, drawn as indexed tris) remains a cheaper-but-affine alternative. Project: jberg/butterchurn (MIT); presets: jberg/butterchurn-presets, and projectM-visualizer/presets-cream-of-the-crop (~9,795 presets, curated 'cream of the crop' by ISOSCELES, default projectM pack). MilkDrop preset-archive lineage also via r/milkdrop and the NestDrop pack.

PLATFORM MAPPING PRIMITIVES (eyesy):
- feedback = 2 render targets ping-pong (target() x2, begin/end_target, swap) + decay multiply in a shader sampling the OTHER target — proven in phosphor/kali. max() composite (kali) keeps channels bounded; NEVER add light into the target you next-sample for decay (phosphor/kali comment trap).
- warp = per-pixel displacement in fragment shader: sample prev target at uv + disp(uv, audio, time) — Butterchurn-proven weak-GPU path; no vertex texture fetch needed/possible.
- oscilloscope/wave/superscope = CPU line-strip mesh rebuilt per frame from ctx.audio.left/right/fft (phosphor pattern: N up to 1024), drawn over feedback.
- composite (display-only finishing: echo, hue, vignette) = a separate draw_shader pass that does NOT feed the sampled target.
- palettes = eyesy cosine/custom 2-16 stop palettes for all color; deterministic eyesy.random for reseed.
- full-res ~16.6ms for cheap passes; heavy scenes at half-res 640x360 targets upscaled (24-30ms fleet envelope) — use kali-bloom/phosphor as the template.

*** THE 15 ARCHETYPES (scene candidates) ***

TIER 1 — cheap/full-res, proven idioms:

A1 OSCILLOSCOPE FOCUS (Lissajous + trails). Origin: analog scope; MilkDrop Spikeball; AVS superscope. Essence: CPU polyline X=L[i],Y=R[i] over decayed feedback; optional mirrored/reflected copies; phosphor 'trail'. Implement: phosphor audio_trace pattern, N<=1024, persistent mesh handle. Perf trick: CPU mesh once/frame, zero shader cost, full-res. Knobs: k1 decay, k2 gain, k3 hue, k4 morph(scope->wave), k5 symmetry. Trigger: re-seed Lissajous ratios (ratio_a/ratio_b) + flash.

A2 WAVEFORM / SPECTRUM ANALYZER. Origin: hardware analyzer, MilkDrop wave modes. Essence: bars/curve from fft bins or 3 bands. Implement: decimate fft 513 -> 32-64 bars on CPU; rect batch or line strip; bass->k1 amplitude. Perf trick: decimation on CPU, batch rects, full-res. Knobs: k1 gain, k2 falloff speed, k3 hue, k4 bar-thickness, k5 mirror. Trigger: freeze/decay reset.

A3 PLASMA / INTERFERENCE FIELD. Origin: demoscene 256-color plasma; Cthugha palette cycling; MilkDrop color morph. Essence: col = sin(x*a+t)+sin(y*b-t)+sin((x+y)*c) combined; phase from time/audio; palette-cycle. Implement: full-res fragment shader, 3-4 sin taps. Perf trick: palette via eyesy.palette(phase), cheap at full-res. Knobs: k1 turbulence, k2 hue drift, k3 saturation, k4 pattern select, k5 speed. Trigger: randomize frequencies + palette.

A4 BEAT PULSE / SHOCKWAVE. Origin: beat-reactive visualizers; 'glowsticks' beat code. Essence: on trigger/bass emit expanding ring r(t)=c*(t-t0) with amplitude envelope, multiplied into frame. Implement: cheap ring in shader or line-mesh; reset on ctx.trigger or bass-band crossing. Perf trick: single pass, full-res. Knobs: k1 ring thickness, k2 expansion speed, k3 hue, k4 bass sensitivity, k5 number of rings. Trigger: spawn ring burst.

A5 KALEIDOSCOPE FEEDBACK. Origin: AVS Kaleidoscope; mandala presets. Essence: fold uv across N spokes: theta' = |theta mod (2*pi/N)| reflected into one sector, mirroring; combine with decayed feedback for multi-scale mandala. Implement: pure uv transform (analytic fold) in shader, full-res. Perf trick: no texture taps beyond prev, analytic fold, full-res OK. Knobs: k1 fold count (integer 3-12), k2 rotation, k3 hue, k4 zoom, k5 mirror symmetry. Trigger: change fold count + reseed.

A6 WIREFRAME 3D TRACER (cube/torus). Origin: demoscene 3D wireframe; MilkDrop 'cubetrace', 'pogo-cubes', AVS 3D Shape. Essence: rotate N-vertex 3D mesh by Euler angles from audio, perspective-project, draw edges into feedback; edges glow/trail. Implement: tiny CPU rotation+project (cube=8 verts/24 edges), line-strip mesh, feedback decay for trails. Perf trick: precompute vertex list, CPU transform trivial, mesh API. Knobs: k1 spin speed, k2 bass wobble, k3 hue, k4 edge glow, k5 mesh complexity (cube->torus). Trigger: swap mesh type / reseed.

TIER 2 — half-res targets + upscale (24-30ms fleet envelope, kali/phosphor template):

A7 BLOOM SPIRAL / SPINNER. Origin: MilkDrop 'spinners'/'glowsticks' bass-blooming mandalas. Essence: per-pixel rotation+zoom of decayed feedback plus bass-triggered additive spiral light, swirl theta' = theta + k*r. Implement: half-res fragment shader warp+decay; inject bloom ONLY in a display-only composite pass (the in-repo trap). Perf trick: bounded max() composite, feedback accumulates the spiral rather than generating it per-pixel. Knobs: k1 decay, k2 swirl, k3 hue, k4 bass bloom, k5 spiral density. Trigger: reseed + bloom flash.

A8 TUNNEL WARP. Origin: MilkDrop 'tunnel of supraschismatika'; demoscene fly-through. Essence: polar remap — uv->(r,theta), sample prev at r' = r^p, theta' = theta + swirl(t) + bass; fly-in illusion. Implement: half-res fragment warp, single texture2D/pixel. Perf trick: reuse feedback as the tunnel wall (no new geometry). Knobs: k1 depth/zoom, k2 swirl, k3 hue, k4 distortion, k5 tunnel count (multi-layer). Trigger: invert/restart tunnel.

A9 LIQUID METAL / BLOBBY MIRROR. Origin: MilkDrop 'Blobby Mirror' family; fluid melt warps. Essence: displacement field u = sum of A*sin(k*x + w*t + phi) over a few drifting blobs; sample prev at uv + u; add reflection symmetry. Implement: half-res fragment warp, 3-4 sine taps. Perf trick: few sine blobs, decayed prev as liquid source. Knobs: k1 blob count, k2 melt speed, k3 hue, k4 viscosity (displacement scale), k5 mirror. Trigger: new blob seed.

A10 ROTO-BLUR / MOTION-TRAIL COMPOSITE. Origin: MilkDrop composite-shader finishing (angular/radial blur, 'echidna'). Essence: angular blur samples prev at theta offsets; radial blur at r offsets; applied display-ONLY, never fed back into the sampled target (bloom trap). Implement: half-res composite pass, <=8 taps. Perf trick: keep as non-feedback pass to avoid self-amplify; low tap count. Knobs: k1 blur radius, k2 blur type (angular/radial), k3 hue echo, k4 intensity, k5 mix. Trigger: burst echo.

A11 GALAXY / 3D PARTICLE STARFIELD. Origin: demoscene starfield; MilkDrop 'magnetosphere'/'Rainbow Splash Poolz'; AVS Moving Particles. Essence: N particles with 3D pos, perspective project p=pos/(z+d); pos += vel + audio kick; draw points/lines; feedback trails. Implement: CPU particle sim (<=512), draw into half-res target, feedback gives trails. Perf trick: fixed pool, reuse mesh handle, half-res. Knobs: k1 particle rate, k2 velocity/flow, k3 hue, k4 audio sensitivity, k5 depth/field shape. Trigger: particle burst / field inversion.

A12 DOT FOUNTAIN (AVS moving particles). Origin: AVS Dot Fountain classic. Essence: emitter spawns dots, gravity pulls down, wrap/reflect at edges, velocity ~ audio. Implement: CPU particle pool (a few hundred), point/line draw, half-res + feedback trails. Perf trick: fixed-count pool, CPU update only, no shader cost. Knobs: k1 flow rate, k2 gravity, k3 hue, k4 turbulence, k5 wrap/reflect mode. Trigger: burst fountain.

A13 KALI / ORBIT-TRAP FRACTAL. Origin: KaliSet fractal; MilkDrop 'urchin kali'. Essence (in-repo): v = abs(v)/max(dot(v,v),1e-9) - c; acc += exp(-length(v)); iterate ~10. Implement: port/extend kali-bloom. Perf trick: clamp denominator at 1e-9 (NOT 1e-4 -> flat orbits); <=10 iterations at half-res. Knobs: k1 zoom, k2 morph, k3 hue, k4 spin, k5 decay/feedback. Trigger: reseed orbit center + palette.

A14 REACTION–DIFFUSION (Gray–Scott). Origin: classic Gray-Scott CA; MilkDrop 'Reaction Diffusion'/'Toxic water diffusion'; ShoggothOx lineage. Essence: A' = A + (DA*laplacian(A) - A*B^2 + f*(1-A)); B' = B + (DB*laplacian(B) + A*B^2 - (k+f)*B). Implement: encode A,B in RG of ONE target, 5-tap Laplacian in a single fragment pass, iterate across FRAMES via feedback (not per-frame). Half-res, 1-2 iterations/frame. Perf trick: single target RG, accumulate over frames, clamp feed/kill. Knobs: k1 feed f, k2 kill k, k3 diffusion, k4 hue, k5 flow seed. Trigger: reseed field / swap pattern. NOTE: heaviest of Tier 2 — validate timings on device first; fallback Tier 3 if >40ms.

A15 SUPERSCOPE (AVS parametric curve, 3D). Origin: AVS Superscope. Essence: for i in 0..N: u=i/N; point=(x(u),y(u),z(u)) where x/y/z are audio-parametric (e.g. y = sum of sine harmonics driven by fft bins); draw polyline, optional 'scope' fold. Implement: CPU polyline (phosphor N=384 pattern), full-res, often over a feedback warp. Perf trick: N=256-512, reuse mesh; combine curves with hue offsets. Knobs: k1 harmonic mix, k2 gain, k3 hue, k4 morph(2D->3D), k5 decay. Trigger: reseed harmonic ratios.

KNOB/TRIGGER CONVENTION (recommended for fleet consistency): k1=feedback decay, k2=warp/zoom intensity, k3=hue/palette phase, k4=gain/intensity, k5=morph/symmetry; trigger=reseeding event (palette + internal seed + optional transition wipe) rather than a one-shot geometric gimmick — mirrors MilkDrop's randomized per-vertex preset-transition as a cross-scene brand element (implement as a shader mask blend between two targets on trigger).

CROSS-CUTTING DESIGN RULES FOR THE FLEET (from MilkDrop2 + in-repo comments):
1. Warp/composite split: the warp pass writes the decayed feedback buffer; the composite pass (echo/hue/bloom/vignette) is display-only and never samples a target it writes — this is both MilkDrop's signature persistence AND the resolution of the in-repo 'bloom inside feedback self-amplifies to white' trap.
2. All shader feedback at half-res (640x360) upscaled; only trivial single-pass scenes at full-res.
3. Fragment warp (sample prev target at displaced uv), never vertex texture fetch (no GLES2).
4. CPU work confined to per-frame polyline/particle mesh rebuilds <=1024 points with persistent mesh handles.
5. Preserve both in-repo traps as shader comments (bloom-in-loop; kaliset clamp 1e-9).

SOURCES (real, not fabricated):
- In-repo: docs/API.md; modes/phosphor/{main.lua,phosphor.frag}; modes/kali-bloom/{main.lua,kali.frag}.
- shoggothox.com/blog/history-of-visualizers.html — lineage Lissajous->Cthugha->AVS->MilkDrop->Butterchurn; MilkDrop warp-mesh 32x24-48x36, EEL, MilkDrop2 warp/composite shaders, randomized preset wipes, self-normalizing audio.
- geisswerks.com/milkdrop/milkdrop_preset_authoring.html — Geiss primary authoring guide (per-frame/per-vertex equations, warp mesh, waves, shapes, motion vectors) [HTTP 406 to reader; content corroborated via MilkDrop3 pipeline doc + authoring lineage].
- deepwiki.com/milkdrop2077/MilkDrop3/3.4-rendering-pipeline — warp shader reads previous framebuffer and displaces samples per-vertex; per-pixel logic in warp HLSL.
- github.com/jberg/butterchurn — WebGL2 MilkDrop2 port (MIT); warp via pixel-shader sampling of prev render target = the weak-GPU reference. Presets: jberg/butterchurn-presets; full tree at github.com/jberg/butterchurn/tree/master/packages/butterchurn/src.
- github.com/projectM-visualizer/presets-cream-of-the-crop — ~9,795 curated MilkDrop presets by ISOSCELES, default projectM pack; archetype names (Dancer/Aurora, Blobby Mirror, 'urchin kali', cubetrace, tokamak, tunnel of supraschismatika, Reaction Diffusion, glowsticks) evidence the archetype taxonomy above.
- github.com/timredfern/ofxAVS + deepwiki grandchild/vis_avs + pfahlr/AVS2K25 — AVS render-list/modular architecture, Justin Frankel origin.
- en.wikipedia.org/wiki/Cthugha, Advanced_Visualization_Studio, MilkDrop; projectM (projectM-visualizer/projectm).
