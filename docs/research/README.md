# Research corpus — MilkDrop engine

The dossiers behind the preset engine in this repo. They were tracked in the
`eyesy` engine repo until the mode collections were split out, and moved here
with the code they describe.

| Dossier | What it grounds |
| --- | --- |
| `MilkDrop3Portability.md` | `milkdrop2077/MilkDrop3` (BSD-3-Clause) read in full: the warp/composite shader model, the per-frame/per-vertex/per-point variable pools, Q/T bridging, blur1/2/3 separable passes, noise textures, samplers — plus the licence verdict |
| `MilkDropAVSHistorian.md` | The Winamp-era lineage (Lissajous/oscilloscope → Cthugha → AVS → MilkDrop/MilkDrop2 → projectM → Butterchurn) as 15 canonical preset archetypes with equation essences and knob/trigger mappings |
| `BeatDropForkPorting.md` | Assessment of `mvsoft74/BeatDrop` / `OfficialIncubo/BeatDrop-Music-Visualizer`: what is worth porting (FFT + wave shader variables, additional community waveforms, system-time variables), ranked, with licence notes |

The two load-bearing rules the engine is built on come from
`MilkDropAVSHistorian.md` and are restated in this repo's README: keep a *warp*
pass that writes **into** the decayed feedback buffer, and a display-only
*composite* pass that never samples a target it writes.

Licensing: all equations in `milkdrop/` are self-authored ports of the
archetypes these dossiers document — equations and constructs only. No community
`.milk` preset file is copied. Community preset packs are third-party artwork and
are user-supplied content unless cleared; if one is ever imported, MilkDrop1-era
presets need compat patches and aspect handling (QC checklist in
`BeatDropForkPorting.md`).

Path conventions: `modes/<name>/...` resolves under this repo's mode folders
once `./eyesyctl modes sync` has assembled them; `docs/API.md`,
`docs/SCENE-LIBRARY.md` and `eyesyctl` refer to the `eyesy` engine repo.