# BeatDrop fork porting assessment (OfficialIncubo/BeatDrop-Music-Visualizer)

Researched 2026-09-16 during Track B. Repo identity: the user-facing name
"BeatDropVis" resolves to `OfficialIncubo/BeatDrop-Music-Visualizer` — an
actively developed fork (146★, updated 2026-09-15) of Maxim Volskiy's
`mvsoft74/BeatDrop` (94★), the standalone MilkDrop2 engine that MilkDrop3
(milkdrop2077) is built on. All three engines share the preset spec; the fork
is the most actively maintained member of the family.

License: **BSD-3-Clause** (code porting clean). Bundled 10k+ presets and the
external "MilkDrop Megapack" are third-party artwork — user-supplied content
unless cleared, per the standing licensing note.

## Worth porting (ranked)

1. **FFT + wave shader variables with audio conditioning** — the big one.
   Fork adds `get_fft()/_hz()`, `get_fft_peak()/_hz()`, `get_wave()/
   _left()/_right()` to the shader model (inherited from MilkDrop3's
   get_fft(), with Nitorami's RMS normalization and preset-configurable
   attack/decay). This is what makes modern MilkDrop3-era presets audio-react
   *in the warp/comp shader*, not just via per-frame bass/mid/treb. Eyesy gap:
   `u_audio` is a 1024×2 waveform texture only; ctx.audio FFT bins are
   Lua-side. Port path: Lua maintains a ~64-band log-spaced smoothed spectrum
   (per-band attack/decay, RMS-normalized) each frame → named vec4 uniform
   bank (draw_shader supports vectors) or a 1×64 target texture. `frac()`
   errors on their side; expect similar care. Feeds milkdrop-engine v2 and
   any audio-reactive scene. Real engineering weight (FFT texture plumbing),
   so: post-v1 Track B follow-up.
2. **Nine additional community simple waveforms** — procedural wave_mode
   renders (mesh-drawable, Lua-side, no shader work). Cheap ports that widen
   the variant pool's motion vocabulary. Source: fork's wave render switch in
   the MilkDrop2 state code.
3. **System time/date variables** (`year..totalseconds`, shader
   `sysTime/sysDate` float4s) — trivial: evaluator env entries from `os.date`
   plus optional uniforms. Enables day/night presets. Nearly free.
4. **Screen-dependent aspect + manually patched MilkDrop1 presets** — not
   code to port, but QC knowledge: if community packs are ever imported as
   user-supplied content, MilkDrop1-era presets need compat patches and
   aspect handling to look right. Encode in any future import QC checklist.
5. **Transitions / double-preset blending** (.milk2 crossfades, hard cuts) —
   a real creative feature for variant pools (crossfade between presets),
   but engine-level scope (two live preset states + mix). Park behind Track
   B v1.

## Not applicable to eyesy

Spout sharing, LRC lyrics + LRCLIB, SMTC song info, WASAPI loopback/hi-res
capture, desktop/borderless/window modes, shader precaching (eyesy compiles
transactionally at mode load), projectM-eval (T1's Lua evaluator fills that
role), mouse/keyboard preset control (device has knobs + `ctx.trigger`).

## Provenance

README highlights, `resources/Milkdrop2/docs/ADDED SHADER VARIABLES AND
FUNCTIONS.txt` (read in full), commit history 2026-04..2026-09. Verified via
GitHub API on 2026-09-16.
