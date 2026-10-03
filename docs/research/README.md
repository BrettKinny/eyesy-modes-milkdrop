# Research notes

Background research behind the preset engine in this repo, written before the
engine was built. They started in the platform repo and moved here with the
code they describe.

| Dossier | What it grounds |
| --- | --- |
| [`MilkDrop3Portability.md`](MilkDrop3Portability.md) | `milkdrop2077/MilkDrop3` (BSD-3-Clause) read in full: the warp/composite shader model, the per-frame/per-vertex/per-point variable pools, Q/T bridging, blur1/2/3 separable passes, noise textures, samplers — plus the licence verdict |
| [`MilkDropAVSHistorian.md`](MilkDropAVSHistorian.md) | The Winamp-era lineage (Lissajous/oscilloscope → Cthugha → AVS → MilkDrop/MilkDrop2 → projectM → Butterchurn) as 15 canonical preset archetypes with equation essences and knob/trigger mappings |
| [`BeatDropForkPorting.md`](BeatDropForkPorting.md) | Assessment of `mvsoft74/BeatDrop` / `OfficialIncubo/BeatDrop-Music-Visualizer`: what is worth porting (FFT + wave shader variables, additional community waveforms, system-time variables), ranked, with licence notes |

The two load-bearing rules the engine is built on come from
`MilkDropAVSHistorian.md` and are restated in [performance](../PERFORMANCE.md): keep a *warp*
pass that writes **into** the decayed feedback buffer, and a display-only
*composite* pass that never samples a target it writes.

Licensing: all equations in `milkdrop/` are self-authored ports of the
archetypes these dossiers document — equations and constructs only. No community
`.milk` preset file is copied. Community preset packs are third-party artwork and
are user-supplied content unless cleared; if one is ever imported, MilkDrop1-era
presets need compat patches and aspect handling (QC checklist in
`BeatDropForkPorting.md`).

Path conventions: `docs/API.md`, `docs/SCENE-LIBRARY.md` and `eyesyctl` refer
to the [eyesy-platform](https://github.com/BrettKinny/eyesy-platform) repo.
`modes/phosphor`, `modes/kali-bloom` and `modes/reaction-diffusion` were earlier
experimental scenes that are not part of any public pack. The plans in these
notes were a starting point; where they differ from the code, the code is right.