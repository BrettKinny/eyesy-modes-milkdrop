-- modes/milkdrop/presets/presets.lua
-- Presets for the milkdrop engine. Format: docs/PRESET-FORMAT.md; every
-- equation string is AVS-subset code evaluated by lib/evaluator.lua.
--
-- Coordinates: per-point x/y are normalised 0..1 with the visual origin at
-- (0.5, 0.5); the engine derives rad/ang from (x - 0.5, y - 0.5) before it
-- hands a point env to per_pixel / wave code. Per-frame code writes the engine
-- uniforms (zoom, warp, rot, cx, cy, dx, dy, decay, gamma, ...); q1..q32 and
-- custom names persist across frames because the engine merges evaluator
-- results into its state table and passes that back as env.
--
-- Append only: a preset's position is its slot, and saved scenes restore by
-- slot. Never insert, reorder or delete. Retired slots (2, 7, 14, 15 and 24)
-- hold `retired-NN` placeholders so every other preset keeps its index.
--
-- Slots 1-16 run on the default composite and the default or sphere
-- warps. Slots 17-23 each introduced an archetype that needed a new fragment
-- or mode feature: the soft-max, interference-field and roto-blur composites,
-- the kaleidoscope fold, the painterly blur warp, reaction-diffusion and the
-- particle starfield. "Historian A<n>" below refers to the archetype map in
-- docs/research/MilkDropAVSHistorian.md.
--
-- Licensing: all equations are self-authored ports of the archetypes
-- documented in docs/research/MilkDrop3Portability.md and
-- docs/research/MilkDropAVSHistorian.md (equations and constructs only; no
-- community preset files are copied).

return {
  {
    -- Tier A baseline: default darken warp (warp_ps.fx: sample prev at warped
    -- uv, multiply by decay) with bass-driven zoom/warp and a slow harmonic
    -- drift on the translate terms, so the feedback keeps moving in silence.
    -- per_frame_init seeds the drift rates per trigger; q3 integrates the
    -- motion phase and is the carry-across-frames variable.
    name = "darken-drift",
    per_frame_init = "q1 = 0.4 + 0.4*rand(1); q2 = 0.35 + 0.3*rand(1); q3 = 0;",
    per_frame =
        "q3 = q3 + 0.01 + 0.06*q2*bass_att;"
      .. "zoom = 1.004 + 0.02*q1*bass_att;"
      .. "warp = 0.3*q2*bass_att;"
      .. "rot = 0.12*q2*sin(q3*1.7);"
      .. "cx = 0.5 + 0.05*sin(q3*0.9);"
      .. "cy = 0.5 + 0.05*cos(q3*0.7);"
      .. "dx = 0.003*sin(q3*1.3);"
      .. "dy = 0.003*cos(q3*1.1);"
      .. "decay = 0.975 + 0.02*bass_att;"
      .. "gamma = 1.0 + 0.3*treb_att;",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 0,
    wave_a = 0.9, wave_r = 0.7, wave_g = 0.9, wave_b = 1.0,
    waves = {
      {
        samples = 256, sep = 0, r = 0.7, g = 0.9, b = 1.0, a = 0.6,
        -- single line wave: lookup position is pushed by the drift phase, the
        -- point position follows it, so the trace breathes with the feedback.
        t1 = "sample = 0.5 + 0.45*sin(sample*3.14159 + q3);"
          .. "x = sample;"
          .. "y = 0.5 + 0.22*sin(sample*6.28318 + q3*1.4);",
      },
    },
    shapes = {},
    decay = 0.98,
    q = { 0.5, 0.2 },
  },

  -- Slot 2 is retired. The preset that lived here was removed before the
  -- public release, and this placeholder holds the slot so every later preset
  -- keeps its index (saved scenes restore by index: docs/PRESET-CONTRACT.md).
  -- A plain built-in-wave drift on the default passes. Self-authored.
  {
    name = "retired-02",
    per_frame_init = "",
    per_frame =
        "zoom = 1.004 + 0.01*bass_att;"
      .. "rot = 0.01*sin(time*0.3);"
      .. "decay = 0.97;",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 0,
    wave_a = 0.6, wave_r = 0.8, wave_g = 0.8, wave_b = 0.8,
    waves = {},
    shapes = {},
    decay = 0.97,
    q = {},
  },

  ------------------------------------------------------------------ slot 3
  -- Archetype: zoom-drift. Historian A1 (oscilloscope focus) / A7 (feedback
  -- drift) family: the classic darken-drift machine — slow zoom/rot/pan of
  -- the decayed feedback with a line wave riding on top. Self-authored:
  -- the drift is a time-integrated phase (q1) advanced by time + bass, so
  -- motion persists in silence and swells on hits.
  {
    name = "zoom-drift",
    per_frame_init =
        "q1 = 0; q2 = 0.5 + 0.4*rand(1); q3 = 0.5 + 0.4*rand(1);",
    per_frame =
        "q1 = q1 + 0.008 + 0.05*bass_att;"
      .. "zoom = 1.006 + 0.03*q2*bass_att;"
      .. "zoomexp = 1.0 - 0.25*bass_att;"
      .. "rot = 0.05*q3*sin(q1*0.9);"
      .. "warp = 0.2 + 0.25*bass_att;"
      .. "cx = 0.5 + 0.07*sin(q1*0.6);"
      .. "cy = 0.5 + 0.06*cos(q1*0.45);"
      .. "dx = 0.004*sin(q1*1.3);"
      .. "dy = 0.004*cos(q1*1.1);"
      .. "decay = 0.972 + 0.02*bass_att;"
      .. "gamma = 1.0 + 0.35*treb_att;",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 0,
    wave_a = 0.85, wave_r = 0.75, wave_g = 0.95, wave_b = 1.0,
    waves = {
      {
        samples = 256, sep = 0, r = 0.75, g = 0.9, b = 1.0, a = 0.7,
        -- line wave: the trace sits on a slow sine rail (q1) with a
        -- second harmonic that opens on mid; x stays linear in sample.
        t1 = "x = sample;"
          .. "y = 0.5 + 0.2*sin(sample*4.0 + q1*2.0)"
          .. " + 0.12*mid_att*sin(sample*9.0 - q1*3.0);",
      },
    },
    shapes = {},
    decay = 0.98,
    q = { 0.5, 0.7, 0.6 },
  },

  ------------------------------------------------------------------ slot 4
  -- Archetype: rot-spin. Historian A7 (bloom spiral / spinner) family:
  -- the feedback buffer rotates and breathes with a sinusoidal zoom,
  -- reseeded per trigger. Self-authored: spin rate is a reseeded constant
  -- (q2) modulated by a slow sin(time) sway, zoom is a standing wave on
  -- q1, and a single spectrum-style radial wave marks the rotation.
  {
    name = "rot-spin",
    per_frame_init =
        "q1 = 0; q2 = 0.5 + 0.5*rand(1); q3 = 0.5 + 0.4*rand(1);",
    per_frame =
        "q1 = q1 + 0.02 + 0.06*treb_att;"
      .. "rot = 0.05*q2*(1.0 + 0.6*sin(0.25*time)) + 0.04*bass_att;"
      .. "zoom = 1.012 + 0.035*sin(q1*1.7);"
      .. "zoomexp = 1.0;"
      .. "warp = 0.15;"
      .. "cx = 0.5 + 0.02*sin(q1*0.8);"
      .. "cy = 0.5 + 0.02*cos(q1*0.8);"
      .. "dx = 0; dy = 0;"
      .. "decay = 0.968 + 0.02*bass_att;"
      .. "gamma = 1.05 + 0.3*treb_att;"
      .. "hue = 0.02*q3*mid_att;",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 2,
    wave_a = 1.0, wave_r = 1.0, wave_g = 0.75, wave_b = 0.4,
    waves = {},
    shapes = {},
    decay = 0.975,
    q = { 0, 0.8, 0.7 },
  },

  ------------------------------------------------------------------ slot 5
  -- Archetype: warp-oscillation. Historian A9 (liquid metal / blobby)
  -- family: the default warp's spherical pinch (1/(r+eps) falloff around
  -- the focus) is driven by a two-frequency oscillation plus a bass kick,
  -- so the buffer ripples like liquid. Self-authored: pinch =
  -- 0.25*(0.5 + 0.5*sin(q1*2.3)) + 0.15*sin(q1*1.1 + 1.5) + 0.5*bass_att,
  -- with q1 advanced by time and treb.
  {
    name = "warp-oscillation",
    per_frame_init =
        "q1 = 0; q2 = 0.5 + 0.4*rand(1); q3 = 0.5 + 0.4*rand(1);",
    per_frame =
        "q1 = q1 + 0.02 + 0.05*treb_att;"
      .. "warp = 0.25*(0.5 + 0.5*sin(q1*2.3))"
      .. " + 0.15*sin(q1*1.1 + 1.5)"
      .. " + 0.5*bass_att;"
      .. "zoom = 1.008 + 0.02*bass_att;"
      .. "zoomexp = 1.0 - 0.3*treb_att;"
      .. "rot = 0.03*sin(q1*0.7);"
      .. "cx = 0.5 + 0.04*sin(q1*0.5);"
      .. "cy = 0.5 + 0.04*cos(q1*0.63);"
      .. "dx = 0.002*sin(q1*1.9);"
      .. "dy = 0.002*cos(q1*1.7);"
      .. "sx = 1.0 + 0.05*sin(q1*1.3);"
      .. "sy = 1.0 - 0.05*sin(q1*1.3);"
      .. "decay = 0.97 + 0.02*mid_att;"
      .. "gamma = 1.0 + 0.4*treb_att;",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 0,
    wave_a = 0.7, wave_r = 0.4, wave_g = 0.9, wave_b = 1.0,
    waves = {
      {
        samples = 384, sep = 0, r = 0.4, g = 0.9, b = 1.0, a = 0.55,
        -- flat line that the liquid warp bends: y fixed at center.
        t1 = "x = sample; y = 0.5;",
      },
    },
    shapes = {},
    decay = 0.975,
    q = { 0, 0.7, 0.6 },
  },

  ------------------------------------------------------------------ slot 6
  -- Archetype: sphere-rush. Historian A8 (tunnel warp) family: the sphere
  -- archetype's radial pinch (q += sphere*q/(r+0.05), see
  -- frag/warp_sphere.frag) is driven positive and hard so the feedback is
  -- pulled toward the focus — the classic fly-in — while a radial wave
  -- (wave_mode 1) marks the wall. Self-authored: sphere = 0.1 +
  -- 0.55*bass_att^1.5-ish via pow, with a slow breathing on q1; the pinch
  -- flips briefly negative on triggers through a decaying kick (q2) that
  -- per_frame_init re-arms, so each beat bulges the sphere before the
  -- pull resumes.
  {
    name = "sphere-rush",
    per_frame_init =
        "q1 = 0; q2 = 1.0; q3 = 0.5 + 0.4*rand(1);",
    per_frame =
        "q1 = q1 + 0.03 + 0.08*bass_att;"
      .. "q2 = q2*0.9;"
      .. "sphere = 0.08 + 0.28*pow(bass_att, 1.5) + 0.05*sin(q1*2.0)"
      .. " - 0.3*q2;"
      .. "zoom = 1.004 + 0.03*bass_att;"
      .. "zoomexp = 1.0;"
      .. "rot = 0.02*sin(q1*0.6);"
      .. "warp = 0.05;"
      .. "cx = 0.5; cy = 0.5; dx = 0; dy = 0;"
      .. "decay = 0.975 + 0.02*bass_att;"
      .. "gamma = 1.1 + 0.3*treb_att;"
      .. "hue = 0.03*q3*sin(q1*0.4);",
    per_pixel = "",
    warp_archetype = "sphere",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 1,
    wave_a = 1.0, wave_r = 1.0, wave_g = 0.8, wave_b = 0.5,
    waves = {},
    shapes = {},
    decay = 0.96,
    q = { 0, 1, 0.7 },
  },
  ------------------------------------------------------------------ slot 7
  -- Slot 7 is retired. The preset that lived here was removed before the
  -- public release, and this placeholder holds the slot so every later preset
  -- keeps its index (saved scenes restore by index: docs/PRESET-CONTRACT.md).
  -- A plain built-in-wave drift on the default passes. Self-authored.
  {
    name = "retired-07",
    per_frame_init = "",
    per_frame =
        "zoom = 1.004 + 0.01*bass_att;"
      .. "rot = 0.01*sin(time*0.3);"
      .. "decay = 0.97;",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 0,
    wave_a = 0.6, wave_r = 0.8, wave_g = 0.8, wave_b = 0.8,
    waves = {},
    shapes = {},
    decay = 0.97,
    q = {},
  },

  ------------------------------------------------------------------ slot 8
  -- Archetype: per-frame q-bridge demo. A didactic preset: every q-pool
  -- slot is seeded from rand in per_frame_init (q1..q32 = 0.1 + 0.8*rand)
  -- and per_frame integrates them in a chain — each q advances by a
  -- fixed step scaled by the PREVIOUS slot, so the trigger's reseeded
  -- random state propagates visibly through the whole pool as drifting
  -- color/zoom/rot. Demonstrates the state-merge contract: q values
  -- persist across frames and rand() re-rolls per trigger (lazy if()
  -- keeps the rand stream deterministic).
  {
    name = "q-bridge",
    per_frame_init =
        "q1 = 0.1 + 0.8*rand(1); q2 = 0.1 + 0.8*rand(1);"
      .. "q3 = 0.1 + 0.8*rand(1); q4 = 0.1 + 0.8*rand(1);"
      .. "q5 = 0.1 + 0.8*rand(1); q6 = 0.1 + 0.8*rand(1);"
      .. "q7 = 0.1 + 0.8*rand(1); q8 = 0.1 + 0.8*rand(1);"
      .. "q9 = 0.1 + 0.8*rand(1); q10 = 0.1 + 0.8*rand(1);"
      .. "q11 = 0.1 + 0.8*rand(1); q12 = 0.1 + 0.8*rand(1);"
      .. "q13 = 0.1 + 0.8*rand(1); q14 = 0.1 + 0.8*rand(1);"
      .. "q15 = 0.1 + 0.8*rand(1); q16 = 0.1 + 0.8*rand(1);"
      .. "q17 = 0.1 + 0.8*rand(1); q18 = 0.1 + 0.8*rand(1);"
      .. "q19 = 0.1 + 0.8*rand(1); q20 = 0.1 + 0.8*rand(1);"
      .. "q21 = 0.1 + 0.8*rand(1); q22 = 0.1 + 0.8*rand(1);"
      .. "q23 = 0.1 + 0.8*rand(1); q24 = 0.1 + 0.8*rand(1);"
      .. "q25 = 0.1 + 0.8*rand(1); q26 = 0.1 + 0.8*rand(1);"
      .. "q27 = 0.1 + 0.8*rand(1); q28 = 0.1 + 0.8*rand(1);"
      .. "q29 = 0.1 + 0.8*rand(1); q30 = 0.1 + 0.8*rand(1);"
      .. "q31 = 0.1 + 0.8*rand(1); q32 = 0.1 + 0.8*rand(1);",
    per_frame =
        -- chain: each slot advances by its own rate scaled by the previous
        -- slot's value; the last wraps back to q1 so the pool is a loop.
        "q1 = q1 + 0.01*q32;"
      .. "q2 = q2 + 0.01*q1;"
      .. "q3 = q3 + 0.01*q2;"
      .. "q4 = q4 + 0.01*q3;"
      .. "q5 = q5 + 0.01*q4;"
      .. "q6 = q6 + 0.01*q5;"
      .. "q7 = q7 + 0.01*q6;"
      .. "q8 = q8 + 0.01*q7;"
      .. "q9 = q9 + 0.01*q8;"
      .. "q10 = q10 + 0.01*q9;"
      .. "q11 = q11 + 0.01*q10;"
      .. "q12 = q12 + 0.01*q11;"
      .. "q13 = q13 + 0.01*q12;"
      .. "q14 = q14 + 0.01*q13;"
      .. "q15 = q15 + 0.01*q14;"
      .. "q16 = q16 + 0.01*q15;"
      .. "q17 = q17 + 0.01*q16;"
      .. "q18 = q18 + 0.01*q17;"
      .. "q19 = q19 + 0.01*q18;"
      .. "q20 = q20 + 0.01*q19;"
      .. "q21 = q21 + 0.01*q20;"
      .. "q22 = q22 + 0.01*q21;"
      .. "q23 = q23 + 0.01*q22;"
      .. "q24 = q24 + 0.01*q23;"
      .. "q25 = q25 + 0.01*q24;"
      .. "q26 = q26 + 0.01*q25;"
      .. "q27 = q27 + 0.01*q26;"
      .. "q28 = q28 + 0.01*q27;"
      .. "q29 = q29 + 0.01*q28;"
      .. "q30 = q30 + 0.01*q29;"
      .. "q31 = q31 + 0.01*q30;"
      .. "q32 = q32 + 0.01*q31;"
      .. "zoom = 1.004 + 0.02*q1;"
      .. "rot = 0.03*sin(q2*6.2831853);"
      .. "warp = 0.2*q3;"
      .. "cx = 0.5 + 0.05*sin(q4*6.2831853);"
      .. "cy = 0.5 + 0.05*cos(q5*6.2831853);"
      .. "dx = 0.003*sin(q6*6.2831853);"
      .. "dy = 0.003*cos(q7*6.2831853);"
      .. "decay = 0.97;"
      .. "gamma = 1.0 + 0.4*mid_att;"
      .. "hue = 0.1*q8*mid_att;",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 0,
    wave_a = 0.9, wave_r = 0.9, wave_g = 0.9, wave_b = 0.9,
    waves = {
      {
        -- the wave reads the pool too: amplitude from q10, rail from q11.
        samples = 256, sep = 0, r = 0.9, g = 0.9, b = 0.9, a = 0.6,
        t1 = "x = sample;"
          .. "y = 0.5 + 0.2*q10*sin(sample*6.2831853 + q11*6.2831853);",
      },
    },
    shapes = {},
    decay = 0.97,
    q = {},
  },

  ------------------------------------------------------------------ slot 9
  -- Archetype: custom-wave ring. One custom wave whose points sit on a
  -- circle (x = 0.5 + r*cos(2*pi*sample), y = 0.5 + r*sin(2*pi*sample))
  -- with the radius modulated by a per-point angular harmonic whose order
  -- and phase are reseeded per trigger — a "ring" that wobbles organically.
  -- Self-authored; no feedback interaction beyond the default warp.
  {
    name = "custom-wave-ring",
    per_frame_init =
        "q1 = 0; q2 = 2 + int(4*rand(1)); q3 = 0.5 + 0.5*rand(1);"
      .. "q4 = 0.5 + 0.4*rand(1);",
    per_frame =
        "q1 = q1 + 0.02 + 0.06*treb_att;"
      .. "zoom = 1.005;"
      .. "zoomexp = 1.0;"
      .. "rot = 0.02*sin(q1*0.8);"
      .. "warp = 0.1;"
      .. "cx = 0.5; cy = 0.5; dx = 0; dy = 0;"
      .. "decay = 0.965 + 0.02*bass_att;"
      .. "gamma = 1.05;"
      .. "hue = 0.02*q4*mid_att;",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 0,
    wave_a = 1.0, wave_r = 0.5, wave_g = 1.0, wave_b = 1.0,
    waves = {
      {
        samples = 256, sep = 0, r = 0.5, g = 1.0, b = 1.0, a = 0.9,
        -- ring: base radius 0.28, wobble = q4 * sin(q2*theta + q1) with a
        -- bass swell on the base radius; theta = 2*pi*sample.
        t1 = "th = sample*6.2831853;"
          .. "rr = 0.28 + 0.08*bass_att + 0.04*q4*sin(q2*th + q1);"
          .. "x = 0.5 + rr*cos(th);"
          .. "y = 0.5 + rr*sin(th);",
      },
    },
    shapes = {},
    decay = 0.97,
    q = { 0, 3, 0.7, 0.6 },
  },

  ------------------------------------------------------------------ slot 10
  -- Archetype: custom-wave harmonic petals. The superscope/A15 family,
  -- self-authored: the point position is a sum of two radial harmonics of
  -- theta (radius = 0.15*sin(3*theta + q1) + 0.1*sin(7*theta - q2)), so
  -- the closed curve has 3-fold and 7-fold lobes that rotate against each
  -- other as the phases advance at different rates — the classic petal
  -- bloom, built from radial harmonics rather than a switched blend.
  {
    name = "custom-wave-petals",
    per_frame_init =
        "q1 = 0; q2 = 0; q3 = 0.5 + 0.4*rand(1);"
      .. "q4 = 3 + int(2*rand(1));",
    per_frame =
        "q1 = q1 + 0.015 + 0.05*treb_att;"
      .. "q2 = q2 + 0.025 + 0.05*mid_att;"
      .. "zoom = 1.004;"
      .. "zoomexp = 1.0;"
      .. "rot = 0.015*sin(q1*0.9);"
      .. "warp = 0.12*bass_att;"
      .. "cx = 0.5; cy = 0.5; dx = 0; dy = 0;"
      .. "decay = 0.968 + 0.02*bass_att;"
      .. "gamma = 1.0 + 0.3*treb_att;"
      .. "hue = 0.03*q3*mid_att;",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 0,
    wave_a = 1.0, wave_r = 1.0, wave_g = 0.4, wave_b = 0.9,
    waves = {
      {
        -- petals: radius is a sum of two counter-rotating harmonics; the
        -- lobe order q4 (3 or 5) is reseeded per trigger.
        samples = 160, sep = 0, r = 1.0, g = 0.4, b = 0.9, a = 0.85,
        t1 = "th = sample*6.2831853;"
          .. "rr = 0.15*sin(q4*th + q1) + 0.1*sin(7*th - q2)"
          .. " + 0.05*bass_att*sin(2*th + q1);"
          .. "x = 0.5 + rr*cos(th);"
          .. "y = 0.5 + rr*sin(th);",
      },
    },
    shapes = {},
    decay = 0.97,
    q = { 0, 0, 0.7, 3 },
  },

  ------------------------------------------------------------------ slot 11
  -- Archetype: built-in wave_mode spectrum. The only preset in the pack
  -- that leans on the engine's built-in wave rendering (wave_mode = 3,
  -- spectrum) rather than custom per-point wave code: no waves table, the
  -- feedback simply orbits and the spectrum bars carry the audio story.
  -- Self-authored per_frame motion: a slow Lissajous pan (cx/cy on a
  -- 3:2 harmonic pair of q1) with a bass-gated zoom pulse.
  {
    name = "built-in-spectrum",
    per_frame_init =
        "q1 = 0; q2 = 0.5 + 0.4*rand(1);",
    per_frame =
        "q1 = q1 + 0.02 + 0.05*mid_att;"
      .. "cx = 0.5 + 0.08*sin(q1*1.5);"
      .. "cy = 0.5 + 0.07*sin(q1*2.0);"
      .. "zoom = 1.01 + 0.03*bass_att;"
      .. "zoomexp = 1.0;"
      .. "rot = 0.02*sin(q1*0.7);"
      .. "warp = 0.15*bass_att;"
      .. "dx = 0.003*cos(q1*2.5);"
      .. "dy = 0.003*sin(q1*2.5);"
      .. "decay = 0.97 + 0.02*bass_att;"
      .. "gamma = 1.05 + 0.3*treb_att;"
      .. "hue = 0.02*q2*mid_att;",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 3,
    wave_a = 1.2, wave_r = 1.0, wave_g = 0.85, wave_b = 0.5,
    waves = {},
    shapes = {},
    decay = 0.975,
    q = { 0, 0.7 },
  },

  ------------------------------------------------------------------ slot 12
  -- Archetype: beat-pulse decay. Historian A4 (beat pulse / shockwave)
  -- family, feedback-native: every frame the decay constant is pulled down
  -- by the bass attack (bass_att), so hard hits bleed the buffer faster
  -- and the trails stay tight in loud passages, while a decaying kick (q1,
  -- re-armed to 1.0 on each trigger by per_frame_init) adds a one-shot
  -- brightness/gamma flash and a zoom pop. Self-authored: decay = 0.975
  -- - 0.05*max(0, bass_att - 0.3) - 0.08*q1; bright = 1.0 + 0.6*q1;
  -- zoom pop = 1.004 + 0.06*q1.
  {
    name = "beat-pulse",
    per_frame_init =
        "q1 = 1.0; q2 = 0.5 + 0.4*rand(1);",
    per_frame =
        "q1 = q1*0.88;"
      .. "decay = 0.975 - 0.05*above(bass_att, 0.3)*(bass_att - 0.3)"
      .. " - 0.08*q1;"
      .. "zoom = 1.004 + 0.06*q1;"
      .. "zoomexp = 1.0 - 0.3*q1;"
      .. "rot = 0.02*sin(0.5*time);"
      .. "warp = 0.15 + 0.2*bass_att;"
      .. "cx = 0.5; cy = 0.5; dx = 0; dy = 0;"
      .. "bright = 1.0 + 0.6*q1;"
      .. "gamma = 1.0 + 0.3*q1;"
      .. "hue = 0.02*q2*mid_att;",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 0,
    wave_a = 0.9, wave_r = 1.0, wave_g = 0.95, wave_b = 0.8,
    waves = {
      {
        -- the trace itself pulses: amplitude from the same bass gate +
        -- kick, so the wave and the buffer flash on the same beat.
        samples = 256, sep = 0, r = 1.0, g = 0.95, b = 0.8, a = 0.8,
        t1 = "amp = 0.12 + 0.25*above(bass_att, 0.3)*(bass_att - 0.3)"
          .. " + 0.15*q1;"
          .. "x = sample;"
          .. "y = 0.5 + amp*sin(sample*12.5663706 + 0.5*time);",
      },
    },
    shapes = {},
    decay = 0.975,
    q = { 1, 0.7 },
  },

  ------------------------------------------------------------------ slot 13
  -- Archetype: flow-silk warp, after Flexi's "Buttermilk" silk look:
  -- multi-frequency sine displacement of the decayed field. Our warp fragment
  -- is not per-pixel scriptable, so the port expresses the silk through per-frame
  -- translate/zoom/rot/warp terms: three time-integrated phases (q1..q3,
  -- each advanced by its own att band) modulate every warp axis with a distinct
  -- sine sum, so the buffer flows like layered silk. Self-authored equations;
  -- motion persists in silence and swells on hits.

  {
    name = "flow-silk-warp",
    per_frame_init =
        "q1 =0; q2 =0; q3 =0;"
      .. "q4 =0.5 +0.5*rand(1);",
    per_frame =
        "q1 = q1 + 0.02 + 0.06*bass_att;"
      .. "q2 = q2 + 0.014 + 0.05*mid_att;"
      .. "q3 = q3 + 0.017 + 0.05*treb_att;"
      .. "zoom = 1.004 + 0.015*bass_att + 0.01*sin(q1*2.1) + 0.008*sin(q2*3.3 + 1.7);"
      .. "rot = 0.04*sin(q1*1.3) + 0.03*sin(q2*2.7 + 0.9);"
      .. "warp = 0.1 + 0.12*bass_att + 0.06*sin(q2*2.3) + 0.04*sin(q3*4.1 + 2.1);"
      .. "cx = 0.5 + 0.03*sin(q1*0.8) + 0.02*sin(q2*1.9);"
      .. "cy = 0.5 + 0.03*cos(q1*0.7) + 0.02*cos(q3*1.6);"
      .. "dx = 0.002*sin(q1*2.0) + 0.0015*sin(q3*3.1 + 1.2);"
      .. "dy = 0.002*cos(q1*1.9) + 0.0015*cos(q3*2.9 + 0.8);"
      .. "decay = 0.974 + 0.02*bass_att;"
      .. "gamma = 1.0 + 0.3*treb_att;"
      .. "hue = 0.02*q4*mid_att;",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 0,
    wave_a = 0.8, wave_r = 0.7, wave_g = 0.95, wave_b = 1.0,
    waves = {},
    shapes = {},
    decay = 0.98,
    q = { 0, 0, 0, 0.7 },
  },

  ------------------------------------------------------------------ slot 14
  -- Slot 14 is retired. The preset that lived here was removed before the
  -- public release, and this placeholder holds the slot so every later preset
  -- keeps its index (saved scenes restore by index: docs/PRESET-CONTRACT.md).
  -- A plain built-in-wave drift on the default passes. Self-authored.
  {
    name = "retired-14",
    per_frame_init = "",
    per_frame =
        "zoom = 1.004 + 0.01*bass_att;"
      .. "rot = 0.01*sin(time*0.3);"
      .. "decay = 0.97;",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 0,
    wave_a = 0.6, wave_r = 0.8, wave_g = 0.8, wave_b = 0.8,
    waves = {},
    shapes = {},
    decay = 0.97,
    q = {},
  },

  ------------------------------------------------------------------ slot 15
  -- Slot 15 is retired. The preset that lived here was removed before the
  -- public release, and this placeholder holds the slot so every later preset
  -- keeps its index (saved scenes restore by index: docs/PRESET-CONTRACT.md).
  -- A plain built-in-wave drift on the default passes. Self-authored.
  {
    name = "retired-15",
    per_frame_init = "",
    per_frame =
        "zoom = 1.004 + 0.01*bass_att;"
      .. "rot = 0.01*sin(time*0.3);"
      .. "decay = 0.97;",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 0,
    wave_a = 0.6, wave_r = 0.8, wave_g = 0.8, wave_b = 0.8,
    waves = {},
    shapes = {},
    decay = 0.97,
    q = {},
  },

  ------------------------------------------------------------------ slot 16
  -- Archetype: spirolateral point cloud, after drozdzilla's "Spiromachia"
  -- look: per-vertex line spirals modulated by bass. Two custom
  -- waves trace counter-rotating spirals(radius grows along the strip and bulges
  -- toward the tip with bass_att), spins are reseeded per trigger, the spirals'
  -- phases advance at different att rates and share a slow common rot. The
  -- radius is capped at 0.48 so a bass bulge never pushes the tip off screen.
  -- Self-authored equations; the decayed default warp leaves short point trails.
  {
    name = "spirolateral",
    per_frame_init =
        "q1 =0; q2 =0; q3 =0;"
      .. "spins =2 + int(2*rand(1));"
      .. "q4 =0.5 +0.4*rand(1);",
    per_frame =
        "q1 = q1 + 0.02 + 0.08*bass_att;"
      .. "q2 = q2 + 0.02 + 0.08*treb_att;"
      .. "q3 = q3 + 0.01 +  0.05*mid_att;"
      .. "zoom = 1.005 + 0.02*bass_att;"
      .. "rot =  0.02*sin(q3*0.8);"
      .. "warp = 0.12*bass_att;"
      .. "cx =0.5; cy =0.5; dx =0; dy =0;"
      .. "decay =0.975 +0.015*bass_att;"
      .. "gamma =1.0 +0.3*treb_att;"
      .. "hue =0.02*q4*mid_att;",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 0,
    wave_a =  0.9, wave_r =  0.3, wave_g = 1.0, wave_b =  0.9,
    waves ={
      {
        -- cyan spiral, phase advances with bass; radius bulges toward the tip.on
        -- bass hits and the common rot q3 turns the whole pair.               
        samples =256, sep =0, r =0.3, g =1.0, b =0.9, a =0.85,
        t1 = "th = sample*6.2831853*spins + q1 + q3;"
          .. "rr = min(0.48, 0.05 + 0.38*sample + (0.08 + 0.14*sample)*bass_att);"
          .. "x =  0.5 + rr*cos(th);"
          .. "y =  0.5 + rr*sin(th);",
      },
      {
        -- orange counter-spiral, phase retreats with treb.

        samples =256, sep =0, r =1.0, g =0.5, b =0.25, a =0.85,
        t1 = "th = sample*6.2831853*spins - q2 + q3;"
          .. "rr = min(0.48, 0.05 + 0.38*sample + (0.08 + 0.14*sample)*bass_att);"
          .. "x =  0.5 + rr*cos(th);"
          .. "y =  0.5 + rr*sin(th);",
      },
    },
    shapes = {},
    decay =  0.978,
    q = { 0, 0, 0,0.7 },
  },

  -- Archetype: the soft-max composite. The frame is screen
  -- blended with a rotated, magnified gather of itself (comp_softmax.frag; the
  -- a+b-a*b construct from jamieowen/glsl-blend screen.glsl, MIT), so lit
  -- structure doubles into a halo with no blur pass and no gain added inside
  -- the feedback loop. One precessing ring wave plus the built-in wave, long
  -- trails, and a comp rotation off the trail axis so the doubling reads.
  -- Self-authored equations.
  {
    name = "softmax-halo",
    per_frame_init =
        "q1 =0;"
      .. "q2 =0.2 + 0.3*rand(1);"
      .. "q3 =0.4 + 0.4*rand(1);",
    per_frame =
        "q1 = q1 + 0.012 + 0.03*bass_att;"
      .. "zoom = 1.005 + 0.025*bass_att;"
      .. "rot  = 0.04*sin(q1*0.9);"
      .. "warp = 0.10 + 0.18*bass_att;"
      .. "cx =0.5; cy =0.5; dx =0; dy =0;"
      .. "decay =0.974 +0.018*bass_att;"
      .. "gamma =1.0 +0.25*treb_att;"
      .. "contrast =1.0 + 0.2*mid_att;"
      .. "hue  =0.45*sin(q1*0.25 + q2*6.0);",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "softmax",
    warp_params = {},
    comp_params = { soft_rot = 7.0, soft_scale = 1.04, soft_mix = 0.6 },
    wave_mode = 0,
    wave_a =  0.9, wave_r =  1.0, wave_g =  0.7, wave_b =  0.4,
    waves = {
      {
        -- A precessing ring whose radius breathes with bass and carries a
        -- three-lobe ripple; screened against its own rotated copy, the two
        -- rings interleave into a slow rosette.
        samples =256, sep =0, r =0.4, g =0.9, b =1.0, a =0.8,
        t1 = "th = sample*6.2831853 + q1 + q3;"
          .. "rr = 0.22 + 0.06*bass_att + 0.05*sin(th*3 + q1*1.7);"
          .. "x = 0.5 + rr*cos(th);"
          .. "y = 0.5 + rr*sin(th);",
      },
    },
    shapes = {},
    decay =  0.975,
    q = { 0, 0, 0,0.6 },
  },

  -- Archetype: the interference-field composite. Four
  -- incommensurable sine layers, two of them radial around orbiting centres,
  -- sum into one field that drives the scene and veils it in light
  -- (comp_plasma.frag; the plasma construct from maravexa/hyprsaver
  -- shaders/plasma.frag, MIT). The scene underneath stays deliberately sparse —
  -- one breathing ring — so the field is what moves. Self-authored equations.
  {
    name = "plasma-veil",
    per_frame_init =
        "q1 =0;"
      .. "q2 =0.3 + 0.4*rand(1);",
    per_frame =
        "q1 = q1 + 0.010 + 0.025*bass_att;"
      .. "zoom = 1.008 + 0.02*bass_att;"
      .. "rot  = 0.03*sin(q1*0.6);"
      .. "warp = 0.08 + 0.12*bass_att;"
      .. "cx =0.5; cy =0.5; dx =0; dy =0;"
      .. "decay =0.981 +0.012*bass_att;"
      .. "gamma =1.0 +0.2*treb_att;"
      .. "contrast =1.05 + 0.15*mid_att;"
      .. "hue  =0.4*sin(q1*0.2 + q2*5.0);",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "plasma",
    warp_params = {},
    comp_params = { plasma_scale = 1.0, plasma_speed = 0.5,
                    plasma_lift = 0.85, plasma_glow = 0.30 },
    wave_mode = 0,
    wave_a =  0.85, wave_r =  0.4, wave_g =  0.8, wave_b =  1.0,
    waves = {
      {
        -- A slow breathing ring; the plasma field carries the rest.
        samples =256, sep =0, r =1.0, g =1.0, b =1.0, a =0.7,
        t1 = "th = sample*6.2831853 + q1*0.5;"
          .. "rr = 0.18 + 0.04*bass_att + 0.02*sin(q1*1.3);"
          .. "x = 0.5 + rr*cos(th);"
          .. "y = 0.5 + rr*sin(th);",
      },
    },
    shapes = {},
    decay =  0.985,
    q = { 0, 0, 0,0.5 },
  },

  -- Archetype: the exact kaleidoscope fold. The warp samples
  -- the feedback through an angle folded into one half-wedge
  -- (warp_kaleido.frag; the radial-reflection construct from three.js
  -- KaleidoShader, MIT), so the frame reconstructs as N mirror-symmetric
  -- wedges: a true reflection, not a rotated copy. Radius is untouched, so the
  -- trails keep their radial structure while the angle mirrors, and the fold
  -- rotation plus the wedge count both answer to the audio.
  -- Self-authored equations.
  {
    name = "kaleido-fold",
    per_frame_init =
        "q1 =0;"
      .. "q2 =0.5 + 0.5*rand(1);",
    per_frame =
        "q1 = q1 + 0.005 + 0.018*bass_att;"
      .. "kaleido_angle = 0.40*sin(q1*0.45) + 0.15*q2;"
      .. "sectors = 6 + 2*above(bass_att, 0.6);"
      .. "zoom = 1.004 + 0.012*bass_att;"
      .. "rot  = 0.02*sin(q1*1.1);"
      .. "warp = 0.05 + 0.10*bass_att;"
      .. "cx =0.5; cy =0.5; dx =0; dy =0;"
      .. "decay =0.984 +0.010*bass_att;"
      .. "gamma =1.0 +0.2*treb_att;"
      .. "hue  =0.35*sin(q1*0.22);",
    per_pixel = "",
    warp_archetype = "kaleido",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 0,
    wave_a =  0.85, wave_r =  1.0, wave_g =  0.6, wave_b =  0.3,
    waves = {
      {
        -- An offset ring: radially asymmetric, so the fold has something to
        -- mirror. Its centre precesses, which walks the arcs around the wedges.
        samples =256, sep =0, r =0.5, g =0.9, b =1.0, a =0.8,
        t1 = "th = sample*6.2831853 + q1*0.3;"
          .. "rr = 0.30 + 0.05*bass_att;"
          .. "x = 0.5 + rr*cos(th) + 0.12*sin(q1*0.7);"
          .. "y = 0.5 + rr*sin(th);",
      },
    },
    shapes = {},
    decay =  0.986,
    q = { 0, 0, 0,0.5 },
  },

  -- Archetype: the roto-blur composite. The frame is smeared
  -- along an arc about the screen centre (comp_rotoblur.frag; the weighted
  -- multi-tap gather from gl-transitions tangentMotionBlur.glsl, MIT), so lit
  -- structure drags into circular streaks — display-only, so the feedback loop
  -- never sees it. Two counter-rotating arcs give the gather something to
  -- smear. Self-authored equations.
  {
    name = "roto-streaks",
    per_frame_init =
        "q1 =0;"
      .. "q2 =0.4 + 0.4*rand(1);",
    per_frame =
        "q1 = q1 + 0.008 + 0.020*bass_att;"
      .. "zoom = 1.006 + 0.02*bass_att;"
      .. "rot  = 0.05*sin(q1*0.7);"
      .. "warp = 0.07 + 0.12*bass_att;"
      .. "cx =0.5; cy =0.5; dx =0; dy =0;"
      .. "decay =0.978 +0.015*bass_att;"
      .. "gamma =1.0 +0.2*treb_att;"
      .. "contrast =1.0 + 0.15*mid_att;"
      .. "hue  =0.35*sin(q1*0.18 + q2*4.0);",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "rotoblur",
    warp_params = {},
    comp_params = { blur_rot = 0.22, blur_rad = 0.03, blur_mix = 0.72 },
    wave_mode = 0,
    wave_a =  0.9, wave_r =  0.5, wave_g = 1.0, wave_b =  0.7,
    waves = {
      {
        -- Outer arc, sweeping one way; the gather drags its ends into streaks.
        samples =192, sep =0, r =0.6, g =1.0, b =0.9, a =0.75,
        t1 = "th = 0.6*3.14159265 + sample*3.14159265 + q1*0.55;"
          .. "rr = 0.26 + 0.04*bass_att;"
          .. "x = 0.5 + rr*cos(th);"
          .. "y = 0.5 + rr*sin(th);",
      },
      {
        -- Inner counter-arc, so the blur reads as rotation, not a shift.
        samples =192, sep =0, r =1.0, g =0.5, b =0.4, a =0.75,
        t1 = "th = 0.4*3.14159265 - sample*3.14159265 - q1*0.75;"
          .. "rr =  0.13 + 0.03*treb_att;"
          .. "x = 0.5 + rr*cos(th);"
          .. "y = 0.5 + rr*sin(th);",
      },
    },
    shapes = {},
    decay =  0.982,
    q = { 0, 0, 0,0.5 },
  },

  -- Archetype: the painterly multi-blur flow. The warp gathers the
  -- previous frame sharp and through the engine's blur1 copy at three vertical
  -- offsets (warp_blur.frag), so each frame feeds a softened version of the last
  -- one forward — the blur lives inside the feedback loop, which is what turns
  -- the trails into dragged paint rather than clipped streaks. The blur share
  -- rises with the bass, so hits thicken the flow.
  -- Self-authored equations.
  {
    name = "painterly-flow",
    per_frame_init =
        "q1 =0;"
      .. "q2 =0.4 + 0.4*rand(1);",
    per_frame =
        "q1 = q1 + 0.007 + 0.018*bass_att;"
      .. "zoom = 1.007 + 0.02*bass_att;"
      .. "rot  = 0.045*sin(q1*0.6);"
      .. "warp = 0.06 + 0.12*bass_att;"
      .. "cx =0.5; cy =0.5; dx =0; dy =0;"
      .. "decay =0.986 +0.010*bass_att;"
      .. "blur_warp = 0.45 + 0.35*bass_att;"
      .. "blur_spread = 0.008 + 0.012*mid_att;"
      .. "gamma =1.0 +0.2*treb_att;"
      .. "saturation =1.0 + 0.3*mid_att;"
      .. "hue  =0.4*sin(q1*0.2 + q2*5.0);",
    per_pixel = "",
    warp_archetype = "blur",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 1,
    wave_a =  0.9, wave_r =  0.9, wave_g =  0.8, wave_b =  0.5,
    waves = {
      {
        -- one soft petal sweep; the blur does the rest of the painting
        samples =224, sep =0, r =1.0, g =0.7, b =0.4, a =0.8,
        t1 = "th = sample*6.2831853*1.5 + q1*0.4;"
          .. "rr = 0.30 + 0.07*bass_att + 0.04*sin(th*2.0 + q1);"
          .. "x = 0.5 + rr*cos(th);"
          .. "y = 0.5 + rr*sin(th);",
      },
    },
    shapes = {},
    decay =  0.988,
    q = { 0, 0, 0,0.5 },
  },

  -- Archetype: Gray-Scott reaction-diffusion, one step per frame
  -- inside the feedback loop (warp_diffuse.frag). The feedback target carries the
  -- two reagents — A in red, B in green and blue — and the waves this preset
  -- draws *after* the warp are the faucet: they inject B, so the pattern grows
  -- out of what you see drawn. Feed and kill are engine vars, so the equations
  -- walk the model between its regimes while it runs.
  -- Self-authored equations.
  {
    name = "reaction-field",
    per_frame_init =
        "q1 =0;"
      .. "q2 =0.3 + 0.4*rand(1);",
    per_frame =
        "q1 = q1 + 0.004 + 0.010*bass_att;"
      -- warp_diffuse ignores zoom, and the field must never fade: both are
      -- pinned at identity (decay matches the preset's static 1.0) so the
      -- reagents are neither advected nor drained
      .. "zoom = 1.0; decay = 1.0;"
      .. "rd_feed = 0.030 + 0.008*sin(q1*0.7);"
      .. "rd_kill = 0.056 + 0.006*cos(q1*0.5 + q2);"
      .. "rd_dt   = 1.0;"
      .. "hue  =0.3*sin(q1*0.2);"
      .. "saturation = 0.7 + 0.3*mid_att;"
      .. "contrast = 1.1 + 0.2*treb_att;"
      .. "gamma = 1.0 + 0.15*bass_att;",
    per_pixel = "",
    warp_archetype = "diffuse",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 0,
    wave_a =  0.55, wave_r =  0.0, wave_g =  0.55, wave_b =  0.0,
    waves = {
      {
        -- The faucet: a drifting spot that injects B into the field. r is left
        -- at zero because red is A, the reagent that must not be topped up.
        samples =64, sep =0, r =0.0, g =0.7, b =0.0, a =0.8,
        t1 = "th = sample*6.2831853 + q1*0.9;"
          .. "rr = 0.022 + 0.010*bass_att;"
          .. "x = 0.5 + 0.22*cos(q1*0.55) + rr*cos(th);"
          .. "y = 0.5 + 0.22*sin(q1*0.61) + rr*sin(th);",
      },
    },
    shapes = {},
    decay =  1.0,
    q = { 0, 0, 0,0.5 },
  },

  -- Archetype: the particle starfield. The formula pools have no
  -- arrays, so the pool lives in the mode and the preset only declares its shape
  -- (`particles`; see main.lua's particle section). 224 stars stream outward from
  -- a vanish point and are reseeded near it as they leave the frame; each is one
  -- triangle rebuilt per frame, and the short decay drags them into streaks.
  -- Bass accelerates the stream and the spectrum bar across the bottom anchors it.
  -- Self-authored equations.
  {
    name = "starfield-drift",
    per_frame_init =
        "q1 =0;"
      .. "q2 =0.5 + 0.5*rand(1);",
    per_frame =
        "q1 = q1 + 0.006 + 0.020*bass_att;"
      .. "zoom = 1.010 + 0.02*bass_att;"
      .. "rot  = 0.03*sin(q1*0.5);"
      .. "warp = 0.05 + 0.10*bass_att;"
      .. "cx =0.5; cy =0.5; dx =0; dy =0;"
      .. "decay =0.955 +0.020*bass_att;"
      .. "gamma =1.0 +0.2*treb_att;"
      .. "saturation =0.9 + 0.3*mid_att;"
      .. "hue  =0.3*sin(q1*0.15 + q2*4.0);",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    particles = {
      count = 224, speed = 0.085, size = 0.0065,
      -- one entry per brightness class; the mesh API colours per mesh, so the
      -- pool is split into four classes rather than shaded per star
      tints = { { 0.95, 0.97, 1.00 }, { 0.55, 0.80, 1.00 },
                { 1.00, 0.85, 0.55 }, { 0.80, 0.60, 1.00 } },
    },
    wave_mode = 3,
    wave_a =  0.25, wave_r =  0.4, wave_g =  0.6, wave_b =  1.0,
    waves = {},
    shapes = {},
    decay =  0.96,
    q = { 0, 0, 0,0.5 },
  },

  -- Slot 24 is retired. The preset that lived here was removed before the
  -- public release, and this placeholder holds the slot so every later preset
  -- keeps its index (saved scenes restore by index: docs/PRESET-CONTRACT.md).
  -- A plain built-in-wave drift on the default passes. Self-authored.
  {
    name = "retired-24",
    per_frame_init = "",
    per_frame =
        "zoom = 1.004 + 0.01*bass_att;"
      .. "rot = 0.01*sin(time*0.3);"
      .. "decay = 0.97;",
    per_pixel = "",
    warp_archetype = "default",
    comp_archetype = "default",
    warp_params = {},
    comp_params = {},
    wave_mode = 0,
    wave_a = 0.6, wave_r = 0.8, wave_g = 0.8, wave_b = 0.8,
    waves = {},
    shapes = {},
    decay = 0.97,
    q = {},
  },
}
