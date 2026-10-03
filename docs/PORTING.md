# Porting MilkDrop looks

How the presets in this pack were made, where to look for new ideas, and the
licensing rules any new preset or fragment has to follow.

## The rule: port ideas, not files

Every preset here is written from scratch. A port takes the *idea* of a
MilkDrop look — "zoom the previous frame toward a point that drifts with the
bass", say — and writes new equations for it. No community `.milk` preset file
is copied, translated line by line, or shipped.

That is because almost every MilkDrop preset pack is someone else's artwork.
Most packs have no licence at all, and the best-known collection
(`cream-of-the-crop`) assumes public domain while saying the authors keep their
copyright. Study them as much as you like; don't copy them.

Engine code is different. MilkDrop 2's pipeline and default shaders, as
published in [milkdrop2077/MilkDrop3](https://github.com/milkdrop2077/MilkDrop3),
are under BSD-3-Clause, and this pack ports from them openly. New fragments may
port a construct from code under a permissive licence, as long as the licence
is checked at its source and the fragment is listed in
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

Two traps to know about:

- **Shadertoy is study-only.** Its default licence is not permissive, and a
  shader's own licence is hard to verify, so treat every Shadertoy shader as
  reference only.
- **LYGIA is not MIT.** The shader library is under the Prosperity Public
  License 3.0.0, which is non-commercial.

None of the checks in `tools/` can tell a fresh port from a copied file. This
rule is enforced by review.

## Where to look for ideas

These collections are the best map of what MilkDrop looks exist. All are
study-only unless noted.

- [projectM-visualizer/presets-cream-of-the-crop](https://github.com/projectM-visualizer/presets-cream-of-the-crop):
  about 9,800 presets sorted into themes (Dancer, Drawing, Fractal, Geometric,
  Particles, Reaction, Waveform and more). The theme folders are a good
  catalogue of the archetypes.
- [projectM-visualizer/presets-milkdrop-original](https://github.com/projectM-visualizer/presets-milkdrop-original):
  the 552 presets shipped with the last official MilkDrop release.
- [milkdrop.org](https://milkdrop.org): the old milkdrop.co.uk archive, with
  5,500 presets indexed by author and by quarter.
- [jberg/butterchurn-presets](https://github.com/jberg/butterchurn-presets):
  presets converted to JSON for the Butterchurn WebGL player, which is easier to
  read than `.milk`.
- [visbot.net/archive](https://visbot.net/archive) and
  [visbot/awesome-avs](https://github.com/visbot/awesome-avs): the Winamp AVS
  side of the family.
- [milkdrop2077/MilkDrop3](https://github.com/milkdrop2077/MilkDrop3)
  (BSD-3-Clause): the engine, and the preset-authoring guide in
  `code/resources/Milkdrop2/docs/milkdrop_preset_authoring.html`. That guide
  defines what every per-frame variable means.

The [research notes](research/README.md) cover the lineage, the main preset
archetypes and their equation cores, and what the MilkDrop3 and BeatDrop
engines add.

## How a port goes

1. **Pick an archetype and check what it needs.** Most looks need only a new
   preset over the existing fragments. Some need a new warp or composite
   fragment, and a few need mode changes: the painterly flow needed a blurred
   copy of the frame before the warp, and the starfield needed a particle pool
   because the equations have no arrays.
2. **Write the preset** at the end of `milkdrop/presets/presets.lua`
   ([preset format](PRESET-FORMAT.md)). Never insert or reorder.
3. **If it needs a fragment,** add `milkdrop/frag/warp_<name>.frag` or
   `comp_<name>.frag`, load it in `setup()` in `main.lua`, supply its uniforms,
   and add the archetype name to `tools/check_presets.py`. Put the source and
   its licence in the fragment's header and in `THIRD_PARTY_NOTICES.md`.
4. **Run the checks** (see the [README](../README.md#checks)), preview it on the
   desktop, and measure it on the device ([performance](PERFORMANCE.md)).

## What the platform can't do yet

- **Textured shapes.** Meshes have no per-vertex texture coordinates, so
  MilkDrop's textured shapes (often used for reflections) can't be drawn as
  geometry.
- **Per-pixel warp equations.** MilkDrop runs `per_pixel` code on a warp mesh.
  Here, each warp archetype computes its displacement in the fragment, so a
  preset steers the warp only through per-frame variables.
- **FFT in shaders.** Shaders get the waveform as a texture (`u_audio`), but
  not the spectrum. MilkDrop3's `get_fft()` would need a spectrum texture.

## Archetypes not yet ported

From the ideas in the research notes, roughly in order of how easily they would
port:

- Echo-zoom "blobby mirror" (sine-blob displacement plus a mirror fold and the
  soft-max composite)
- Glowstick trails (bright additive trails with a clamped blur glow in the
  composite)
- Tunnel polar warp (`r' = r^p`, `θ' = θ + swirl`)
- Wireframe 3D tracers (CPU rotation and projection into a line mesh)
- Game of Life and other cellular automata (a cheaper relative of the
  reaction-diffusion warp)
- Kali and Mandelbox fractals (per-pixel iteration; likely too slow at full
  size, so a reduced-resolution experiment)

## Two bugs found by rendering

Both of these were invisible to every check that only reads the code, and both
were found by rendering the fragments on a real GLES2 driver. They are fixed,
and `tools/check_render.py` now has regression tests for them.

1. **The warp sampled half a screen too low.** The line that converts
   MilkDrop's y-up coordinates back to texture coordinates added 0.5 to both
   axes, but the y axis already had its 0.5. With neutral settings the output
   was the input shifted down by half its height. The fix is
   `vec2(wuv.x / aspect + 0.5, 0.5 - wuv.y)`.
2. **The `zoomexp` exponent was inverted.** MilkDrop's guide defines
   `zoomexp = 1` as normal, so `zoom = 1, zoomexp = 1` must leave the frame
   alone. The old formula, `zoom * pow(r, 1 - zoomexp) / r`, collapsed it to a
   flat frame. The fix is `zoom * pow(r, zoomexp) / r`.

The render check's identity tests assert that `warp_default` and `warp_sphere`
return the input frame byte for byte at neutral settings.
