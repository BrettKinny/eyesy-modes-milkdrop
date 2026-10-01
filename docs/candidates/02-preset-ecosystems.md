# Candidate census 02 — Preset content ecosystems and the archetype space

Discovery pass over the MilkDrop/AVS preset ecosystems, dated 2026-09-17. Goal: enumerate which
*constructs* exist in the wild, mark what `milkdrop/` (12 presets, 6 fragments) already implements,
and rank the absent archetypes in t2 portability order. Nothing here is a download list; all packs
are third-party artwork — study-only per this repo's licensing rule (README "Licensing"). Engine
code that is freely licensed is flagged as portable; preset files never are.

Evidence levels used below: `[F]` = file name verified in a live listing this pass; `[T]` = theme /
sub-directory verified in a live listing; `[D]` = named in `docs/trackB-plan/_t2-research.txt` or
`docs/research/MilkDropAVSHistorian.md`, not re-verified as a file this pass; `[I]` = inference.

Overlap marking: the last column cites the t2 Part 3 ranking (`t2#1..13`) and the historian's
15-archetype map (`A1..A15`) so nothing already known is re-derived.

---

## Per-ecosystem table

| # | Ecosystem | URL | What it is | Licence / terms verdict | ~Presets & organisation |
|---|---|---|---|---|---|
| 1 | cream-of-the-crop | https://github.com/projectM-visualizer/presets-cream-of-the-crop | ISOSCELES "best of" MilkDrop pack; default projectM pack since 2022 (README) | `LICENSE.md`: presets "not released under any specific license"; authors hold copyright; "safe to assume them to be in the public domain"; takedown contact. Study-only (matches our rule) | 9,795 (README), sorted into 11 top themes: `! Transition`, Dancer (32 subthemes), Drawing (19+), Fractal (~28), Geometric (45+), Hypnotic (7), Particles (8), Reaction (~20), Sparkle (10), Supernova (7), Waveform (10) |
| 2 | official MilkDrop 2.25 bundled pack | https://github.com/projectM-visualizer/presets-milkdrop-original | The preset pack deployed with the last official MilkDrop release (textures excluded; README) | No LICENSE file (API `license: null`). Terms absent → study-only | 552 `.milk` (counted from git tree this pass), flat `Milkdrop-Original/` |
| 3 | classic projectM pack | https://github.com/projectM-visualizer/presets-projectm-classic | projectM's shipped collection until v3.1.12 (README) | No LICENSE file (`license: null`). Terms absent → study-only | ~4,200 (README); flat `bltc201/` folder tree |
| 4 | community pack | https://github.com/projectM-visualizer/presets-community | Community-submission drop (repo has no files at read time) | No LICENSE, no content | 0 shipped |
| 5 | en-d pack | https://github.com/projectM-visualizer/presets-en-d | "En D" author collection, part of default pack set since 2022 (README) | `LICENSE.md` — identical public-domain-assumption text as cream (read raw). Study-only | ~50 (README); per-album subdirs incl. textures/mp3 |
| 6 | MilkDrop texture pack | https://github.com/projectM-visualizer/presets-milkdrop-texture-pack | All textures shipped with MilkDrop + commonly used ones (README) | No LICENSE file (`license: null`). Third-party images → study-only | ~64 JPGs, flat `textures/` |
| 7 | Butterchurn presets | https://github.com/jberg/butterchurn-presets | MilkDrop presets machine-converted to Butterchurn JSON (WebGL2) | Repo `LICENSE` MIT (converter tooling); the JSONs are converted community presets → study-only | ~1,440 JSON (`presets/converted/`, flat; 1,439 elided in listing) |
| 8 | ansorre butterchurn corpus | https://github.com/ansorre/tens-of-thousands-milkdrop-presets-for-butterchurn | Extended Butterchurn-JSON corpus | No licence stated (API null); converted community presets → study-only | 15,056 converted presets (README), one zip |
| 9 | MilkDrop3 engine + bundled set | https://github.com/milkdrop2077/MilkDrop3 (+ https://milkdrop3.com) | MilkDrop 3.x (BSD-3 code — port freely per t2 dossier; `code/LICENSE.txt`). Installer ships "over 500 stunning visuals" (milkdrop3.com); app free for personal use, paid PRO for remunerated (site footer); "a few shaders are not open-source" (README v3.33) | Engine BSD-3 (port); bundled presets community → study-only; closed shaders → don't port | Bundled preset inventory lives inside the installer exe, not the source tree — names not enumerable without downloading (see unreachable); `code/resources/Milkdrop2/` carries engine shaders + Geiss authoring docs |
| 10 | milkdrop.org archive (ex milkdrop.co.uk) | https://milkdrop.org | The historic milkdrop.co.uk preset library, rebuilt as an Astro site powered by Butterchurn (about page) | No explicit licence statement; About/Roadmap: "make the presets themselves freely available". Study-only | 5,527 presets (site), organised by source, 20 quarterly collections (2001-All → 2004-Q4, Newbies/Regulars), 105 author pages with per-preset detail pages |
| 11 | MilkDrop2077 preset generator | https://github.com/milkdrop2077/milkdrop2077 | Flexi's preset generator/masher/randomizer (Pascal) | GPL-3 (LICENSE) → pattern-an-approach only (like flam3) | Embedded `PRESETS.RES`; no pack listing |
| 12 | Poweramp v3 pack | https://github.com/SpasilliumNexus/poweramp-visualizer-presets | Example APK with .milk presets; Poweramp translates EEL→Lua, HLSL→GLSL (README) — a live proof that the preset construct space ports to GLES mobile; extends syntax with `bars_*` spectrum grids | Permissive Poweramp-specific license quoted in README (use for Poweramp-communicating software). Presets → study-only | ~130 `.milk` (57 shown + 73 elided), flat `milk_presets/` + textures |
| 13 | Winamp AVS pack archives | http://archive.visbot.net (canonical https://visbot.net/archive) | "Collection of Winamp AVS packs released throughout the years" — the surviving AVS pack archive | No licence statement on archive; packs are third-party artwork → study-only | 70+ author/pack dirs (`acid`, `avsociety`, `degnic`, `finnishflash`, `grandchild`, `ishan`, `oussy`, `pak-9`, VISBOT compilations …); VISBOT 200 alone = 2,530 presets (winampheritage listing) |
| 14 | Winamp Heritage AVS library | https://winampheritage.com/visualizations/AVS-Presets-11 | Legacy Winamp visualization download directory (unofficial; copyright disclaimer on-site) | Download-only, no preset licence terms; unofficial site | AVSociety "Our Decade" packs, VISBOT compilations, Dynamic Duo EPs, "recapture suite" (101) — dozens of packs |
| 15 | AVS tooling ecosystem | https://github.com/visbot/awesome-avs (CC0 index) → scopes: vis_avs (2.81d), chavs (Happy AVS), vis_avs_dx, webvs (MIT), webvsc, AVS-File-Decoder (MIT), avs-preset-depends (CC0), mscopes (BSD-3), avs4unity, AVS-Forums mirror + forum-archive | Engines/converters, not packs — but they define the AVS construct grammar (superscope, movement, dynamic movement, texer, kaleidoscope…) in runnable form | Tooling MIT/CC0/BSD-3 → constructs studyable; `vis_avs`/`chavs` engine sources have their own Winamp-era terms (no LICENSE in mirror repos) | n/a (packs live at #13/#14) |

Author collections (task list: Geiss, Flexi, Rovastar, Flexi+Cope, Eo.S, LuxXx, Aderrasi, shifter,
Jc, drozdzilla, martin, null1024, ORB, suksma): no standalone sites were found this pass; every one
of these authors is indexed live per-author:
`https://milkdrop.org/presets/authors/<slug>/` — Rovastar (842), Zylot (496), Eo.S. (428),
Unchained (424), Aderrasi (388), Geiss (356), Phat (349), Krash (254), Telek (214), Idiot (203),
Fvese (191), Shifter (104), fiShbRaiN (114), plus 90 more. Flexi (MilkDrop2077) is post-2004 and
sits in cream-of-the-crop / milkdrop-original / butterchurn (e.g. `Flexi - Milkcore`, `Flexi + Geiss
- pogo-cubes on tokamak matter`). drozdzilla ("Spiromachia") and null1024 ("Plasma") are t2-named
titles inside the cream pack [D]; not independently file-verified this pass.

## Construct census — families evidenced vs repo status

Repo status key: **done** = mechanic present in `milkdrop/`; **partial** = adjacent mechanic exists;
**absent** = not implemented. Family list built from the theme directories above (the theme taxonomy
*is* the archetype-space enumeration), milkdrop.org author pages, and the pack file listings.

| Archetype family | Evidence (representative `Name - Author`) | Repo status |
|---|---|---|
| Plain-glass darken / zoom-rot-translate feedback | theme Reaction/Feedback [T]; `martin - another kind of groove` [F] | **done** — `warp_default` + darken-drift/zoom-drift/rot-spin |
| Spherical pinch fly-in | theme Waveform/Wire Tunnel [T], `sphere-rush` family | **done** — `warp_sphere` + sphere-rush |
| Radial-wedge sector warp | unlicensed community preset [F] | **retired** — the port was removed before the public release: study-only source |
| Harmonic-petal / phase-coupled waves | unlicensed community presets [F] | **done** — custom-wave-petals (self-authored radial harmonics); the direct port was retired |
| 5-gather max() glow comp + solarize | unlicensed community preset [F] | **retired** — `comp_glow` was removed before the public release: study-only source |
| Spectrum/waveform bars | built-in wave_mode 3; Poweramp `bars_*` extension spec [F-doc] | **partial** — one preset; bars variety absent |
| Custom wave rings / superscope petals | `custom-wave-ring`, `custom-wave-petals`; theme Waveform/Wire Flower [T] | **done** (2D polar); 3D superscope absent |
| Beat-pulse decay | `beat-pulse` | **done** (decay-domain); expanding-ring shockwave absent |
| Liquid metal / blobby displacement | theme Dancer/Blobby, Reaction/Liquid* [T]; `warp-oscillation` | **partial** — single-pinch ripple; no blob field |
| Blobby MIRROR (reflection + echo-zoom + soft-max) | theme Dancer/Blobby Mirror (32+ files) [T]; `LuxXx - Benefiscient Prescience` [F], `ORB - Radiation` [F], `LuxXx - Done For the Night` [F], `suksma - ancientient visitarz` [F] | **absent** |
| Textured-reflect shape | textured=1 square in an unlicensed community preset [F-implied]; theme Geometric/Squares Glass [T] | **partial** — shapes untextured (no per-vertex UV); masked-fragment route identified (t2 Part 4) |
| Flow-silk multi-frequency sine warp | `Flexi - Milkcore` [F], `Flexi - cell tissue` [F], `Flexi + Martin - astral projection` [F], `EVET + Flexi - Rainbox Splash Poolz` [F] | **absent** |
| Kaleidoscope fold | `Eo.S. - repeater 15 - kaleidoscope b` [F] (milkdrop-original + projectm-classic), `Rovastar + Geiss - Hyperkaleidoscope Glow 2` [F] (poweramp); hyphenated mirror themes [T] | **absent** |
| Plasma / wave-interference | theme Fractal/Wave Interference [T]; `null1024 - Plasma` [D] | **absent** |
| Reaction–diffusion (Gray–Scott) | theme Reaction/Contagion, Growth [T]; `DemonLD - Toxic water diffusion` [F], `Flexi + Geiss - Bipolar vs. Reaction Diffusion mix` [F], `AdamFx 2 Geiss/Zylot/Flexi - Reaction Diffusion 3` [F] | **absent** |
| Conway Game-of-Life cellular automaton | `Geiss - Game of Life 3` [F] (poweramp) | **absent** |
| Kali / orbit-trap fractal | `shifter - urchin kali` [F] + suksma tail family [F]; in-repo precedent `modes/kali-bloom` (sibling pack) | **absent here** |
| Mandelbox / Sierpinski / nested-base fractals | theme Fractal/Mandelbox, Nested *, Sierpinski, Womb [T] | **absent** (per-pixel iteration; cost risk) |
| Particle fields & starfields | theme Particles/{Points,Points Fast,Points Trails,Spaz,Swarm,Orbit,Grid} [T], Supernova/Stars [T]; `Eo.S. and PieturP - Starfield` [F] | **absent** |
| Dot fountain (AVS moving particles) | AVS classic; theme Particles/Points [T] | **absent** |
| Wireframe 3D tracers | `Eo.S. + Phat - cubetrace - v2` [F], `Flexi + Geiss - pogo-cubes on tokamak matter` [F], `Geiss - Smoke Rings` [F]; theme Geometric/Wire Cube Trace, Wire Torus, Wire Sphere [T] | **absent** |
| Spirolateral point clouds | `drozdzilla - Spiromachia` [D] (t2 Tier B #13) | **absent** |
| Tunnel polar warp | `Flexi + Martin - tunnel of supraschismatika` [F]; theme Geometric/Tunnel *, Sparkle/Glimmer Tunnel [T] | **partial** — sphere pinch family only |
| Roto-blur / motion-trail comp | `Geiss - Motion Blur 2 (Reverse Jelly V3)` [F]; theme Dancer/Whirl, Drawing/Trails [T] | **absent** |
| Glowstick additive trails (`blur1_min` trick) | `Eo.S. + Geiss - glowsticks v2 02 (Relief Mix)` [F], `Eo.S. - glowsticks v2 03 music` [F]; theme Dancer/Glowsticks + Mirror + Fast [T] | **partial** — glow comp exists; add+bias trick absent |
| Soft-max blobby comp (`a+b-a*b`) | theme Dancer/Blobby Mirror [T]; t2 Tier B #11 | **absent** (comp variant) |
| Neon sweep / additive shape sweeps | `Flexi - Electro Deps` [D] (t2 Tier B #9) | **absent** |
| Painterly multi-blur flow | `Aderrasi + Geiss - Airhandler (Kali Mix)` [F], `Aderrasi - Airhandler (Principle of Sharing)` [F] (t2 Tier B #10) | **absent** |
| Transition wipes / preset blending | `! Transition` theme [T]; MilkDrop3 `.milk2` double-preset [F-doc] | **absent** (engine-level preset switching; out of preset scope) |
| Game/novelty generators, mash-ups, collage naming | `$$$ Royal - Mashup (*)` families [F]; `Rovastar` mash-ups [F] | n/a (combinatorics of the above) |

## Ranked unported-archetype list (portability order) + top-8 recommendation

Ranking reuses t2 Part 3 Tier A (direct, low rework) / Tier B (good beauty, moderate work). All of
these are evidenced in the wild (census above) and absent from `milkdrop/` today. Overlap markers:
`t2#n` = t2-research Part 3 item; `An` = historian archetype. **New to both existing documents**:
kaleidoscope fold, roto-blur comp, Conway Game-of-Life, and the concrete file-level evidence for
particles/wireframe/tunnel.

**Tier A — direct, low rework (new fragment or small preset-variant, no new engine capability):**

1. **Plasma / interference field** — rep `null1024 - Plasma` [D] / theme Fractal/Wave Interference [T].
   *Essence:* per-pixel `col = 0.5+0.5*sin(Σ harmonic waves of uv)` (e.g. sin(x·a+t)+sin(y·b−t)+sin((x+y)·c)),
   phase from time/audio, palette-mapped; zero feedback dependence. *Port route:* new `comp_plasma`
   fragment — pure math, 3-4 sin taps, full-res viable; historian A3 / t2 Tier A #7.
2. **Kaleidoscope fold** — rep `Eo.S. - repeater 15 - kaleidoscope b` [F]; `Rovastar + Geiss -
   Hyperkaleidoscope Glow 2` [F]. *Essence:* analytic uv fold — `theta' = |theta mod 2π/N|` reflected
   into one sector, mirror on alternate spokes; sample prev at folded uv with decay, optionally
   combined with zoom/rot drift; N reseeded per trigger. *Port route:* new `warp_kaleido` fragment
   (one texture tap, analytic trig); Tier A. **New vs t2** (historian A5).
3. **Flow-silk displacement warp** — rep `Flexi - Milkcore` [F], `Flexi - cell tissue` [F]. *Essence:*
   multi-frequency sine displacement `uv_w = uv + Σ a_k·sin(f_k·uv·2π + φ_k)` with per-frame, audio-
   modulated phases — Flexi's flowing-deformation signature. *Port route:* new `warp_flow` fragment,
   coefficients as uniforms from per_frame; direct. t2 Tier A #4.
4. **Glowstick additive trails** — rep `Eo.S. + Geiss - glowsticks v2 02 (Relief Mix)` [F]; theme
   Dancer/Glowsticks [T]. *Essence:* bright additive wave/spinner trails injected into a darkening
   warp; comp glow uses the blur1-min trick `ret += (GetBlur1 − blur1_min)·2` (clamp+bias of the
   blur gather) so trails bloom without feedback self-amplification. *Port route:* preset on
   `warp_default` + additive wave pass, `comp_glow` gains a clamp-bias uniform; small fragment delta.
   t2 Tier B #12 / historian A4/A7.
5. **Echo-zoom blobby mirror** — rep `LuxXx - Benefiscient Prescience` [F], `ORB - Radiation` [F];
   theme Dancer/Blobby Mirror [T]. *Essence:* a few drifting sine-blob displacement terms
   (`u = Σ A_k sin(k·x+ω·t+φ)`) plus reflection symmetry and echo-zoom sampling of prev; finishing via
   soft-max composite `a+b−a·b`. *Port route:* `warp_flow` variant with mirror fold + `comp_softmax`
   fragment (2-3 gathers). t2 Tier B #11 / historian A9.
6. **Roto-blur / motion-trail composite** — rep `Geiss - Motion Blur 2 (Reverse Jelly V3)` [F]. *Essence:*
   display-only angular/radial blur — sample prev at theta-offsets or radial offsets (≤8 taps),
   blended 0..1; never fed back into the sampled target (bloom trap discipline). *Port route:* new
   `comp_rotoblur` fragment, mirror of `blur1`'s 8-tap gather pattern. **New vs t2** (historian A10).

**Tier B — good beauty, moderate work:**

7. **Dot fountain / particle starfield** — rep `Eo.S. and PieturP - Starfield` [F]; theme
   Particles/{Points,Spaz,Swarm} [T]. *Essence:* CPU particle pool (a few hundred), per-frame
   integrate (gravity/wrap/reflect/swirl + audio kick), draw points/lines into the feedback target
   for trails. *Port route:* Lua particle table + point/line mesh rebuilt per frame (custom-wave
   pattern proven in-pack; watch the 8192-vertex budget, 160-256 pts/fountain). historian A11/A12.
8. **Reaction–diffusion (Gray–Scott)** — rep `DemonLD - Toxic water diffusion` [F]; `Flexi + Geiss -
   Bipolar vs. Reaction Diffusion mix` [F]; theme Reaction [T]. *Essence:* A,B encoded in RG of ONE
   feedback target; 5-tap Laplacian; `A' = A + (DA·∇²A − A·B² + f(1−A))`, `B' = B + (DB·∇²B + A·B² −
   (k+f)B)` iterated across frames; clamp feed/kill ~1e-9 discipline. *Port route:* rD fragment over
   the half-res feedback target (1-2 iterations/frame). Heaviest of the set — validate on device
   before committing (historian flags >40 ms risk); **fallback in the same slot:** Conway game-of-life
   CA (`Geiss - Game of Life 3` [F]) — a cheaper 9-tap neighbourhood automaton on one RG target.
   t2 Tier A #8 / historian A14.

**Top 8 recommendation (ranked):** 1 Plasma · 2 Kaleidoscope fold · 3 Flow-silk warp · 4 Glowstick
trails · 5 Echo-zoom blobby mirror · 6 Roto-blur comp · 7 Dot fountain/starfield · 8 Reaction–diffusion
(with Game-of-Life as the cheap fallback). Spread: 3 pure-comp fragments (plasma, roto-blur,
soft-max inside #5), 2 warp fragments (kaleido, flow-silk; echo-mirror rides on flow-silk), 2 preset/
comp-delta variants (glowstick on comp_glow, blobby soft-max), 1 CPU-mesh archetype (fountain), 1
feedback-iterate archetype (rD). All fit the existing half-res warp→composite pipeline; none needs
a platform capability we lack (per-vertex UV and vertex texture fetch are deliberately avoided).

**Honourable mentions (ranked below top 8):** wireframe/3D tracer (historian A6; t2 nominated
pogo-cubes — evidence `Eo.S. + Phat - cubetrace - v2` [F], `pogo-cubes on tokamak matter` [F], theme
Geometric/Wire Cube Trace [T]; route: CPU 3D→2D rotation/projection + line mesh — fine, moderate
work); tunnel polar warp (historian A8 — `Flexi + Martin - tunnel of supraschismatika` [F]; pure
polar remap `r'=r^p, theta'=theta+swirl` — direct fragment, ranked below since sphere-rush already
covers the family's fly-in feel); textured-reflect shape (t2#2 — needs the masked-fragment route,
no per-vertex UV); neon sweep (t2#9 — `Flexi - Electro Deps` [D]); Spiromachia point cloud (t2#13);
painterly multi-blur (`Aderrasi - Airhandler` family [F], t2#10 — needs blur-gather-in-warp, use
existing blur1); Kali orbit-trap (`shifter - urchin kali` [F], t2#6 — precedent lives in sibling
`modes/kali-bloom`, port is a preset + comp reuse). Mandelbox family [T] — attractive but per-pixel
iteration at 720p is a tier risk; treat as a kali-style half-res experiment only.

## Unreachable / needs-verify (honest status)

| Source | Attempt | Result |
|---|---|---|
| milkdrop.co.uk domain | Direct DNS + web search (re-run this pass) | Domain is squatter-held (stated on milkdrop.org/about). Web search still returns non-sequitur results (AINS/NILAM pages) — the dossier's "failed search attempt" reproduces. **Resolution:** the archive itself is live at milkdrop.org (5,527 presets), and the original Rovastar/Krash "Beginners Guide" is mirrored on Wayback (web.archive.org/web/20060719012900/http://www.milkdrop.co.uk/guide.htm, cited from milkdrop.org/about) |
| NestDrop full package (previews + installer) | https://www.patreon.com/posts/pack-nestdrop-91682111 | HTTP 403 — Patreon blocks bots. Backstory link in cream README is live via archive: web.archive.org/web/20240609162724/https://thefulldomeblog.com/2020/02/21/nestdrop-presets-collection-cream-of-the-crop/ |
| MilkDrop3 bundled preset inventory | milkdrop2077/MilkDrop3 source tree | Not in the repo — carried inside the installer (`MilkDrop3.exe`); count claimed "over 500 stunning visuals" on milkdrop3.com. Name-level enumeration requires downloading the Windows installer (not done this pass) |
| Webamp AVS page | https://webamp.org/avs | 404. Webamp's AVS integration routes through visbot's webvs demo (azeemarshad.in/webvs/examples — referenced in visbot/webvs README, not re-opened this pass) |
| Official AVS forum | forums.winamp.com forumdisplay f=85 (from awesome-avs) | Not opened this pass (JS-gated legacy forum); static mirror verified: https://visbot.github.io/AVS-Forums/ and binary archive visbot/forum-archive |
| Standalone author sites (Geiss, Flexi, Rovastar, Eo.S, LuxXx, Aderrasi, shifter, Jc, drozdzilla, martin, null1024, ORB, suksma) | Web search | No live standalone sites found; all are covered by the per-author indexes at milkdrop.org/presets/authors/ and the packs above. `drozdzilla - Spiromachia` and `null1024 - Plasma` remain t2-named [D], not file-verified this pass |
| Cream Sparkle/Supernova subtheme tail | API listing | Enumerated (Sparkle 9, Supernova 7 subthemes); sub-dir file listings not expanded this pass |

## Repeatable entry points and queries

GitHub API (used this pass, all live):
- Theme census: `https://api.github.com/repos/projectM-visualizer/presets-cream-of-the-crop/contents/<dir>` (dir = `! Transition`, `Dancer[/<sub>]`, `Drawing`, `Fractal`, `Geometric`, `Hypnotic`, `Particles`, `Reaction`, `Sparkle`, `Supernova`, `Waveform`). Extend by recursing one level for every subtheme.
- Pack family: `https://api.github.com/orgs/projectM-visualizer/repos` — the six preset repos + texture pack; re-run to catch new packs.
- Search pattern A: `https://api.github.com/search/repositories?q=milkdrop+presets` → 67 repos (packs, converters, players).
- Search pattern B: `https://api.github.com/search/repositories?q=winamp+avs+preset` → 9 repos, all tooling — the AVS *corpus* lives outside GitHub (next two rows).
- File counts: `https://api.github.com/repos/<owner>/<repo>/git/trees/<branch>?recursive=1` (used to count milkdrop-original = 552 .milk).

Historic archive (milkdrop.org, live):
- Library index + collection buckets: `/presets`, `/presets/collections/<year>-<q>-<newbies|regulars>`; author buckets: `/presets/authors/<slug>` (105 authors); per-preset detail: `/presets/detail/<slug>`. Machine-readable: `/sitemap-index.xml`, `/rss.xml`.

AVS archives (live):
- Pack archive: `https://visbot.net/archive/<pack>` (70+ pack dirs; page lists all).
- Legacy download library: `https://winampheritage.com/visualizations/AVS-Presets-11` + per-pack `/visualization/<slug>/<id>`.
- Curated index (CC0): `https://github.com/visbot/awesome-avs` — teams, forums, mirrors, docs; its "Resources" section is the AVS rabbit-hole map. Forum mirror: `https://visbot.github.io/AVS-Forums/`; raw archive: `visbot/forum-archive`; decoder/converter: `grandchild/AVS-File-Decoder` (MIT), `visbot/webvs` (MIT).

Pack-linked (verify-and-extend): cream README → Patreon NestDrop post (bot-blocked; use Wayback) and fulldomeblog archive link; milkdrop3.com → YouTube/Patreon/BuyMeACoffee (Flexi's distribution); r/milkdrop (linked from milkdrop3.com, community hub); geisswerks.com/milkdrop (official authoring guide + MilkDrop1 lineage; HTTP 406 to some readers per historian — corroborate via the milkdrop.org mirror `/resources/preset-authoring`).

Extension queries that produced nothing this pass (recorded so the loop doesn't retry blindly):
- `web_search "milkdrop.co.uk"` → only non-sequiturs (use direct URL instead).
- GitHub `q=winamp+avs+preset` → no pack repos (packs are on visbot.net/archive + winampheritage).