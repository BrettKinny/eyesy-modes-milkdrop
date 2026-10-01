-- modes/milkdrop/main.lua
-- MilkDrop-style preset engine (Track B / slice T4).
--
-- Contract: local/reports/trackB-plan/BRIEF.md (pipeline, preset schema, T1
-- integration notes, T3 integration decisions). Preset data lives in
-- presets/presets.lua; every equation string is AVS-subset code evaluated by
-- lib/evaluator.lua.
--
-- Per frame:
--   1. env: bass/mid/treb + bass_att/mid_att/treb_att (dt-based EMA, 0.6 s
--      half-life), time/frame/progress/fps, the q pool
--   2. per_frame (per_frame_init runs on preset load and on ctx.trigger);
--      results merge into the persistent state table, which is also the env
--   3. clamp engine vars
--   4. warp pass: warp_<archetype> fragment into `back`, sampling `front`
--   5. waves (custom per-point eval + built-in wave_mode 0..3) and shapes draw
--      into `back`
--   6. composite (comp_<archetype>) at content resolution, upscaled to the
--      screen, no feedback write
--   7. swap front/back
--
-- The blur warp archetype runs blur1 into the third target before step 4.
--
-- Knobs (docs/SCENE-LIBRARY.md): 1 motion (scales the per-frame time
-- accumulation), 2 preset (1..#presets), 3 detail (wave samples, shape sides),
-- 4 hue (composite hue offset), 5 feedback (zoom/warp axis multiplier).
-- ctx.trigger re-runs per_frame_init with a fresh seed: an in-family beat, it
-- never switches presets.
--
-- Per-frame writable engine vars (clamped, then fed to the fragments): zoom
-- zoomexp rot warp sphere cx cy dx dy sx sy decay gamma bright contrast
-- saturation hue echo sectors. A preset can bridge
-- extra warp uniforms from per-frame variables with
-- `param_bridge = { <uniform> = "<per-frame var>" }` (T3 integration note), so
-- a reseeded axis (e.g. kaleido-fold's mirror count) stays in sync with the
-- analytic fragment.
--
-- Error discipline: a preset whose equations fail to compile is rejected and
-- the previous preset keeps running; a per-frame runtime error keeps the
-- previous engine vars. Both are logged once. Nothing here throws.

local e = eyesy
local ev = require("lib.evaluator")
local PRESETS = require("presets/presets")

-- ---------------------------------------------------------------- constants

local PI = 3.14159265358979
local TWO_PI = 6.28318530717959
local LN2 = 0.693147180559945

local CONTENT_STD = { 640, 360 }    -- default feedback content size
local CONTENT_DENSE = { 480, 270 }  -- preset warp_params.dense variant
local MAX_WAVE_SAMPLES = 2048       -- brief: <= 2048 samples per custom wave
local MAX_WAVES = 8                 -- custom-wave mesh slots
local BUILTIN_POINTS = 96           -- built-in wave resolution at detail 0.5
local SHAPE_MAX_SIDES = 64
local PARTICLE_MAX = 512        -- pool ceiling: 3 vertices and 3 indices per particle
local PARTICLE_CLASSES = 4      -- one mesh per class; the mesh API colours per mesh, not per vertex
local DETAIL_LO = 0.5               -- detail knob scales 0.5..1.5
local ENV_HALF_LIFE = 0.6           -- s, *_att EMA half-life
local BAND_GAIN = 2.5               -- bands are root-sum-square amplitudes
local BAND_MAX = 2.0                -- ... normalised into ~0..2
local HUE_SPAN = PI                 -- k4 sweeps the comp hue over +-90 degrees
local MOTION_LO, MOTION_SPAN = 0.25, 1.5 -- k1 -> 0.25..1.75x time rate
local BEAT_RATE = 2.5               -- trigger-envelope decay per second
local SPECTRUM_GAIN = 2.0           -- FFT bins are sinusoid-normalised
local WAVE_MIN, WAVE_MAX = -1.0, 2.0 -- per-point x/y sanity bounds
local PROGRESS_WRAP = 240.0         -- s, env `progress` cycle

-- Per-frame writable engine vars: name, default, min, max. Defaults are the
-- fragment header defaults; the ranges keep a runaway equation finite and in
-- a range the fragments can render (a warp of 2.0 is already a black hole).
local ENGINE_VARS = {
  { "zoom", 1.004, 0.5, 2.0 },
  { "zoomexp", 1.0, 0.1, 4.0 },
  { "rot", 0.0, -1.0, 1.0 },
  { "warp", 0.011, -2.0, 2.0 },
  { "cx", 0.5, 0.0, 1.0 },
  { "cy", 0.5, 0.0, 1.0 },
  { "dx", 0.0, -0.5, 0.5 },
  { "dy", 0.0, -0.5, 0.5 },
  { "sx", 1.0, 0.25, 4.0 },
  { "sy", 1.0, 0.25, 4.0 },
  { "decay", 0.98, 0.0, 1.0 },
  { "gamma", 1.0, 0.1, 5.0 },
  { "bright", 1.0, 0.0, 4.0 },
  { "contrast", 1.0, 0.0, 4.0 },
  { "saturation", 1.0, 0.0, 4.0 },
  { "hue", 0.0, -TWO_PI, TWO_PI },
  { "echo", 0.0, 0.0, 2.0 },
  { "sphere", 0.2, -2.0, 2.0 },
  { "sectors", 8.0, 2.0, 64.0 },
  { "kaleido_angle", 0.0, -TWO_PI, TWO_PI },
  { "blur_warp", 0.55, 0.0, 1.0 },
  { "blur_spread", 0.012, 0.0, 0.08 },
  { "rd_feed", 0.035, 0.0, 0.2 },
  { "rd_kill", 0.060, 0.0, 0.2 },
  { "rd_dt", 1.0, 0.0, 2.0 },
  { "rd_scale", 1.0, 0.25, 8.0 },
}

local ENGINE_DEFAULTS, ENGINE_MAP = {}, {}
for i = 1, #ENGINE_VARS do
  local v = ENGINE_VARS[i]
  ENGINE_DEFAULTS[v[1]] = v[2]
  ENGINE_MAP[v[1]] = v
end

-- ------------------------------------------------------------- module state

local state = {}          -- persistent evaluator state == per-frame env
local point_env = {}      -- scratch env for per-point wave code
local preset_index = 1
local preset = PRESETS[1]
local current = nil       -- compiled code of the running preset
local compiled = {}       -- [preset index] = compiled code
local wave_pts = {}       -- [slot] = reusable vertex pool
local wave_meshes = {}    -- [slot] = mesh handle
local builtin_pts, builtin_mesh
local shape_pts, shape_idx, shape_mesh
-- CPU particle pool (the starfield archetype). The equation pools cannot hold
-- arrays, so the pool lives here and a preset only declares its shape.
local pstate = { ang = {}, rad = {}, spd = {}, cls = {} }
local pcount, pspec, prand = 0, nil, nil
local particle_pts, particle_idx, particle_meshes = {}, {}, {}
local targets = {}        -- ["<w>x<h>"] = { front, back, blur }
local front, back, blur, comp_out
local content_w, content_h
local shader = {}         -- warp_<archetype>, comp_<archetype>, blur1
local att = { bass = 0, mid = 0, treb = 0 }
local clock = { time = 0, frame = 0 } -- k1-scaled accumulation handed to presets
local real_frame = 0
local beat = 0
local fps_est = 60
local seed_base, seed_count = 1, 0
local logged = {}

-- ---------------------------------------------------------------- utilities

local function clamp(v, lo, hi)
  if v ~= v then return lo end
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function clamp01(v)
  return clamp(v, 0, 1)
end

local function clamp_num(v, fallback, lo, hi)
  if type(v) ~= "number" or v ~= v then return fallback end
  return clamp(v, lo, hi)
end

local function log_once(key, message)
  if logged[key] then return end
  logged[key] = true
  print("milkdrop: " .. key .. ": " .. tostring(message))
end

-- Seed the evaluator's PRNG handle (env._rand): the Park-Miller LCG the
-- evaluator test harness uses, so preset runs stay reproducible.
local function make_rand(seed)
  local s = seed % 2147483647
  if s <= 0 then s = 1 end
  return function()
    s = (s * 16807) % 2147483647
    return s / 2147483647
  end
end

local function next_seed()
  seed_count = seed_count + 1
  return (seed_base + seed_count * 2654435761) % 2147483647
end

local function merge(dst, src)
  for k, v in pairs(src) do dst[k] = v end
end

-- ctx.audio.<band> -> ~0..2 (root-sum-square amplitudes, per docs/API.md)
local function band_value(v)
  if type(v) ~= "number" or v ~= v then return 0 end
  return clamp(v * BAND_GAIN, 0, BAND_MAX)
end

local function sample_at(array, u)
  if type(array) ~= "table" then return 0 end
  local v = array[math.floor(u * 1023) + 1]
  if type(v) ~= "number" or v ~= v then return 0 end
  return v
end

local function setpt(pts, i, x, y)
  local v = pts[i]
  if v == nil then
    v = { 0, 0, 0 }
    pts[i] = v
  end
  v[1], v[2] = x, y
  return i + 1
end

-- Drop every entry from index k on. update_mesh reads 1..#pts, so a stale
-- tail would be drawn as holes; the walk stops at the first nil, which keeps
-- the pool a contiguous run after every trim.
local function trim_from(list, k)
  local j = k
  while list[j] ~= nil do
    list[j] = nil
    j = j + 1
  end
end

-- ------------------------------------------------------------ preset state

local function content_size(p)
  local wp = p.warp_params
  if type(wp) == "table" and wp.dense then return CONTENT_DENSE[1], CONTENT_DENSE[2] end
  return CONTENT_STD[1], CONTENT_STD[2]
end

-- Compile every equation string of a preset. Returns nil when per_frame (the
-- only mandatory block) does not parse, leaving the running preset in place.
local function build_compiled(p)
  local frame, ferr = ev.compile(p.per_frame)
  if not frame then
    log_once("per_frame:" .. tostring(p.name), ferr)
    return nil
  end
  local init, ierr = ev.compile(p.per_frame_init)
  if not init then
    log_once("per_frame_init:" .. tostring(p.name), ierr)
  end
  local pixel, perr = ev.compile(p.per_pixel)
  if not pixel then
    log_once("per_pixel:" .. tostring(p.name), perr)
  end
  local waves = {}
  for i, w in ipairs(p.waves or {}) do
    local f, werr = ev.compile(w.t1)
    if not f then
      log_once("wave:" .. tostring(p.name) .. "[" .. i .. "]", werr)
    end
    waves[i] = f
  end
  return {
    init = init,
    frame = frame,
    -- per_pixel is compiled for author feedback only: the warp fragments
    -- evaluate their displacement analytically, so its outputs must not be
    -- consumed (T1 integration notes).
    pixel = pixel,
    waves = waves,
  }
end

-- --------------------------------------------------------------- particles

-- Starfield pool. A preset declares only its shape; the per-particle state lives
-- here because the formula pools have no arrays. Each particle is one triangle
-- (3 vertices, 3 indices), rebuilt every frame — 512 particles is 1536 vertices,
-- inside the API's 8192-vertex budget, but this is real per-frame Lua work, so
-- the counts in the catalog stay in the low hundreds.
local PARTICLE_TINTS = {
  { 1.0, 1.0, 1.0 }, { 0.55, 0.75, 1.0 }, { 1.0, 0.85, 0.55 }, { 0.85, 0.55, 1.0 },
}

local function particle_spec_value(key, fallback, lo, hi)
  local spec = pspec
  local v = type(spec) == "table" and spec[key] or nil
  return clamp_num(v, fallback, lo, hi)
end

-- Fresh pool: angles, radii, per-star speed and class. Uses its own RNG stream
-- derived from the preset seed, so the pool is reproducible on a replay without
-- consuming the equations' rand() sequence.
local function init_particles(seed)
  pspec = type(preset.particles) == "table" and preset.particles or nil
  pcount = 0
  if not pspec then return end
  pcount = math.floor(particle_spec_value("count", 256, 0, PARTICLE_MAX) + 0.5)
  prand = make_rand(seed * 7 + 13)
  for i = 1, pcount do
    pstate.ang[i] = prand() * TWO_PI
    pstate.rad[i] = 0.02 + 0.98 * prand()
    pstate.spd[i] = 0.6 + 0.8 * prand()
    pstate.cls[i] = 1 + math.floor(prand() * PARTICLE_CLASSES)
  end
end

-- Integrate the pool and rebuild the meshes. The stars stream outward from the
-- centre and are reseeded near it once they leave the frame, which is the
-- classic starfield read: motion is radial, so the scene has a vanish point.
local function draw_particles(w, h, sdt)
  if pcount == 0 or not pspec then return end
  local base = particle_spec_value("speed", 0.075, 0.0, 2.0)
  local size = particle_spec_value("size", 0.006, 0.0005, 0.05) * h
  local boost = 1 + 1.5 * state.bass_att
  -- elliptical reach: r = 1.05 lands on the frame edge in both axes, so the
  -- whole life cycle is visible instead of the outer frame staying empty
  local rx, ry = 0.48 * w, 0.48 * h
  local cx, cy = 0.5 * w, 0.5 * h

  local counts = { 0, 0, 0, 0 }
  for i = 1, pcount do
    local r = pstate.rad[i] + base * boost * sdt * pstate.spd[i] * (0.3 + pstate.rad[i])
    if r > 1.05 then
      r = 0.035
      pstate.ang[i] = prand() * TWO_PI
      pstate.spd[i] = 0.6 + 0.8 * prand()
    end
    pstate.rad[i] = r
    local cls = pstate.cls[i]
    -- one triangle per star, smaller near the centre so the field recedes
    local s = size * (0.35 + 0.65 * r)
    local x = cx + rx * r * math.cos(pstate.ang[i])
    local y = cy + ry * r * math.sin(pstate.ang[i])
    local k = counts[cls] + 1
    local pts, idx = particle_pts[cls], particle_idx[cls]
    setpt(pts, k, x, y - s)
    setpt(pts, k + 1, x - 0.87 * s, y + 0.5 * s)
    setpt(pts, k + 2, x + 0.87 * s, y + 0.5 * s)
    idx[k], idx[k + 1], idx[k + 2] = k, k + 1, k + 2
    counts[cls] = k + 2
  end

  for c = 1, PARTICLE_CLASSES do
    local pts, idx, n = particle_pts[c], particle_idx[c], counts[c]
    trim_from(pts, n + 1)
    trim_from(idx, n + 1)
    if n > 0 then
      local tint = type(pspec.tints) == "table" and pspec.tints[c] or nil
      local t = type(tint) == "table" and tint or PARTICLE_TINTS[c]
      e.color(clamp01(t[1] or 1), clamp01(t[2] or 1), clamp01(t[3] or 1), 1)
      e.update_mesh(particle_meshes[c], pts, idx)
      e.draw_mesh(particle_meshes[c])
    end
  end
end

local function run_init(seed)
  state._rand = make_rand(seed)
  local f = current and current.init
  if not f then return end
  local results, err = f(state)
  if not results then
    log_once("run:init:" .. tostring(preset.name), err)
    return
  end
  merge(state, results)
end

-- Full preset load: fresh state, declared q pool, per_frame_init with a fresh
-- seed, fresh point pools and content targets.
local function target_set(w, h)
  local key = w .. "x" .. h
  local set = targets[key]
  if set == nil then
    set = { front = e.target(w, h), back = e.target(w, h), blur = e.target(w, h),
            comp = e.target(w, h) }
    targets[key] = set
  end
  return set
end

local function load_preset(index, seed)
  local p = PRESETS[index]
  if type(p) ~= "table" then return false end
  local c = compiled[index] or build_compiled(p)
  if not c then return false end
  compiled[index] = c

  preset_index, preset, current = index, p, c

  state = {}
  for name, value in pairs(ENGINE_DEFAULTS) do state[name] = value end
  if type(p.decay) == "number" then state.decay = clamp(p.decay, 0, 1) end
  for j = 1, 32 do state["q" .. j] = 0 end
  local q0 = p.q
  if type(q0) == "table" then
    for j = 1, #q0 do
      local v = q0[j]
      if type(v) == "number" and v == v then state["q" .. j] = v end
    end
  end

  wave_pts = {}
  point_env = {}
  clock.time, clock.frame = 0, 0
  beat = 0

  local w, h = content_size(p)
  local set = target_set(w, h)
  content_w, content_h = w, h
  front, back, blur, comp_out = set.front, set.back, set.blur, set.comp

  run_init(seed)
  init_particles(seed)
  return true
end

-- ------------------------------------------------------------------ stages

local function clamp_engine()
  for i = 1, #ENGINE_VARS do
    local v = ENGINE_VARS[i] -- name, default, min, max
    state[v[1]] = clamp(state[v[1]], v[3], v[4])
  end
end

-- The per-point evaluator env is this frame's state plus the point variables
-- (sample/x/y/rad/ang/value1/value2) the wave loop overwrites. Synced once per
-- frame after the per-frame merge, so wave code reads this frame's q pool,
-- envelopes and time; results are per point and are not merged back.
local function sync_point_env()
  for k, v in pairs(state) do point_env[k] = v end
end

local function warp_uniforms(w, h, feedback)
  local u = {}
  -- 1) archetype uniforms declared by the preset (e.g. sectors = 8)
  local wp = preset.warp_params
  if type(wp) == "table" then
    for k, v in pairs(wp) do
      if type(v) == "number" and v == v then u[k] = v end
    end
  end
  -- 2) the reaction-diffusion archetype reads its state off the pixel grid, so it
  -- never warps the field: it takes the model's parameters and the texel size and
  -- none of the geometric uniforms. Supplying the geometric set anyway would make
  -- the fragment declare fourteen uniforms it must not use, and the fragment gate
  -- insists that everything supplied is declared.
  local arch = preset.warp_archetype
  if arch == "diffuse" then
    u.rd_feed = state.rd_feed
    u.rd_kill = state.rd_kill
    u.rd_dt = state.rd_dt
    u.rd_scale = state.rd_scale
    u.texel = { 1 / w, 1 / h }
    return u
  end

  -- 3) engine vars (authoritative for the shared names)
  local fb = 0.5 + feedback
  u.zoom = 1 + (state.zoom - 1) * fb
  u.zoomexp = state.zoomexp
  u.rot = state.rot
  u.warp = state.warp * fb
  u.cx, u.cy = state.cx, state.cy
  u.dx, u.dy = state.dx, state.dy
  u.sx, u.sy = state.sx, state.sy
  u.decay = state.decay
  u.aspect = w / h
  u.texel = { 1 / w, 1 / h }
  if arch == "sphere" then
    u.sphere = state.sphere
  elseif arch == "kaleido" then
    u.sectors = state.sectors
    u.kaleido_angle = state.kaleido_angle
  elseif arch == "blur" then
    u.blur_warp = state.blur_warp
    u.blur_spread = state.blur_spread
  end
  -- 3) param_bridge: seed variant axes from per-frame variables (T3 note)
  local bridge = preset.param_bridge
  if type(bridge) == "table" then
    for uniform, var in pairs(bridge) do
      if type(var) == "string" then
        local v = state[var]
        if type(v) == "number" and v == v then
          local range = ENGINE_MAP[uniform]
          if range then v = clamp(v, range[3], range[4]) end
          u[uniform] = v
        end
      end
    end
  end
  return u
end

local function warp_shader()
  -- archetype -> fragment follows the naming convention the fragment gate
  -- enforces (warp_<archetype>.frag), so this is a lookup rather than a chain
  -- that has to be extended for every archetype.
  return shader["warp_" .. tostring(preset.warp_archetype)] or shader.warp_default
end

-- blur1.frag's default weight row for the blur warp; texel is 1/pixel at the
-- current content size.
local function blur1_uniforms(w, h)
  return {
    texel = { 1 / w, 1 / h },
    blur_w = { 7.8, 6.4, 3.1, 1.0 },
    blur_d = { 0.487, 3.344, 6.387, 10.0 },
    blur_scale = 1.0, blur_bias = 0.0,
  }
end

-- Comp archetype selection and its uniforms. Returns (shader, u).
local function comp_shader_and_uniforms(hue_knob)
  local arch = preset.comp_archetype
  local u = {}
  if arch == "softmax" then
    local cp = preset.comp_params or {}
    u.soft_rot = clamp_num(cp.soft_rot, 6.0, -180.0, 180.0)
    u.soft_scale = clamp_num(cp.soft_scale, 1.03, 0.25, 2.0)
    u.soft_mix = clamp_num(cp.soft_mix, 0.55, 0.0, 1.0)
  elseif arch == "plasma" then
    local cp = preset.comp_params or {}
    u.plasma_scale = clamp_num(cp.plasma_scale, 1.0, 0.25, 4.0)
    u.plasma_speed = clamp_num(cp.plasma_speed, 1.0, -4.0, 4.0)
    u.plasma_lift = clamp_num(cp.plasma_lift, 0.6, 0.0, 2.0)
    u.plasma_glow = clamp_num(cp.plasma_glow, 0.25, 0.0, 2.0)
  elseif arch == "rotoblur" then
    local cp = preset.comp_params or {}
    u.blur_rot = clamp_num(cp.blur_rot, 0.18, -PI, PI)
    u.blur_rad = clamp_num(cp.blur_rad, 0.02, -0.5, 0.5)
    u.blur_mix = clamp_num(cp.blur_mix, 0.75, 0.0, 1.0)
  end
  u.gamma = state.gamma
  u.bright = state.bright
  u.saturation = state.saturation
  u.hue = clamp(state.hue + (hue_knob - 0.5) * HUE_SPAN, -TWO_PI, TWO_PI)
  u.contrast = state.contrast
  u.echo = state.echo
  -- archetype -> fragment follows the naming convention the fragment gate
  -- enforces (comp_<archetype>.frag), so this is a lookup rather than a chain
  -- that has to be extended for every archetype.
  local sh = shader["comp_" .. tostring(arch)] or shader.comp_default
  return sh, u
end

-- Built-in wave (wave_mode 0..3) drawn every frame from ctx.audio, scaled by
-- the preset's wave_a/r/g/b — MilkDrop draws it alongside any custom waves.
local function draw_builtin_wave(w, h, detail, left, right, fft)
  local mode = math.floor(clamp_num(preset.wave_mode, 0, -1, 7) + 0.5)
  if mode < 0 or mode > 3 then mode = 0 end
  local n = math.floor(BUILTIN_POINTS * (DETAIL_LO + detail))
  n = clamp(n, 8, MAX_WAVE_SAMPLES)
  local amp = clamp_num(preset.wave_a, 1.0, 0.0, 4.0)
  local inv = 1 / (n - 1)
  local pts = builtin_pts
  local k = 1

  if mode == 0 then -- line
    for j = 1, n do
      local u = (j - 1) * inv
      local yn = 0.5 + 0.35 * amp * sample_at(left, u)
      k = setpt(pts, k, u * w, (1 - yn) * h)
    end
  elseif mode == 1 then -- circle
    for j = 1, n do
      local u = (j - 1) * inv
      local th = u * TWO_PI
      local rn = 0.25 + 0.25 * amp * sample_at(left, u)
      local yn = 0.5 + rn * math.sin(th)
      k = setpt(pts, k, (0.5 + rn * math.cos(th)) * w, (1 - yn) * h)
    end
  elseif mode == 2 then -- spokes: [centre, tip] per angle slot
    local cx, cy = 0.5 * w, 0.5 * h
    for j = 1, n do
      local u = (j - 1) * inv
      local th = u * TWO_PI
      local s = sample_at(left, u)
      if s < 0 then s = -s end
      local rn = 0.08 + 0.45 * amp * s
      k = setpt(pts, k, cx, cy)
      local yn = 0.5 + rn * math.sin(th)
      k = setpt(pts, k, (0.5 + rn * math.cos(th)) * w, (1 - yn) * h)
    end
  else -- spectrum bars: [base, top] per bin, no chords between bars
    local base = 0.14
    local span = 0.6 * amp
    for j = 1, n do
      local u = (j - 1) * inv
      local v = 0.0
      if type(fft) == "table" then
        local raw = fft[1 + math.floor(u * 255)]
        if type(raw) == "number" and raw == raw then v = clamp01(raw * SPECTRUM_GAIN) end
      end
      k = setpt(pts, k, u * w, (1 - base) * h)
      k = setpt(pts, k, u * w, (1 - (base + span * v)) * h)
    end
  end

  trim_from(pts, k)
  e.color(clamp01(preset.wave_r or 1), clamp01(preset.wave_g or 1),
          clamp01(preset.wave_b or 1), 1)
  e.update_mesh(builtin_mesh, pts)
  e.draw_mesh(builtin_mesh)
end

local function draw_custom_waves(w, h, detail, left, right)
  local list = preset.waves
  if type(list) ~= "table" then return end
  local scale = DETAIL_LO + detail
  for i = 1, #list do
    local spec = list[i]
    local f = current.waves and current.waves[i]
    if f then
      local n = math.floor(clamp_num(spec.samples, 512, 0, MAX_WAVE_SAMPLES) * scale)
      n = clamp(n, 2, MAX_WAVE_SAMPLES)
      local inv = 1 / (n - 1)
      local pool = wave_pts[i]
      if pool == nil then
        pool = {}
        wave_pts[i] = pool
      end
      local pt = point_env
      for j = 1, n do
        local u = (j - 1) * inv
        -- per-point env (T1 notes): x/y are normalised 0..1 about (0.5, 0.5)
        -- and rad/ang are derived from them; value1/value2 carry the audio
        -- samples at this point.
        pt.sample = u
        pt.x = u
        pt.y = 0.5
        local dxu = u - 0.5
        if dxu < 0 then
          pt.rad, pt.ang = -dxu, PI
        else
          pt.rad, pt.ang = dxu, 0
        end
        pt.value1 = sample_at(left, u)
        pt.value2 = sample_at(right, u)
        local out = f(pt)
        local vx, vy = u, 0.5
        if out then
          local ox = out.x
          if type(ox) == "number" then vx = ox end
          local oy = out.y
          if type(oy) == "number" then vy = oy end
        end
        vx = clamp(vx, WAVE_MIN, WAVE_MAX)
        vy = clamp(vy, WAVE_MIN, WAVE_MAX)
        local v = pool[j]
        if v == nil then
          v = { 0, 0, 0 }
          pool[j] = v
        end
        v[1] = vx * w
        v[2] = (1 - vy) * h
      end
      trim_from(pool, n + 1)
      e.color(clamp01(spec.r or 1), clamp01(spec.g or 1), clamp01(spec.b or 1),
              clamp01(spec.a or 1))
      e.update_mesh(wave_meshes[i], pool)
      e.draw_mesh(wave_meshes[i])
    end
  end
end

local function draw_shapes(w, h, detail)
  local list = preset.shapes
  if type(list) ~= "table" then return end
  local scale = DETAIL_LO + detail
  for i = 1, #list do
    local spec = list[i]
    local sides = math.floor(clamp_num(spec.sides, 4, 0, SHAPE_MAX_SIDES) * scale + 0.5)
    sides = clamp(sides, 3, SHAPE_MAX_SIDES)
    local cx = clamp_num(spec.x, 0.5, -1, 2) * w
    local cy = (1 - clamp_num(spec.y, 0.5, -1, 2)) * h
    local rad = clamp_num(spec.rad, 0.25, 0, 4) * h
    local ang = math.rad(clamp_num(spec.ang, 0, -3600, 3600))
    local step = TWO_PI / sides
    setpt(shape_pts, 1, cx, cy)
    for j = 1, sides do
      local a = ang + (j - 1) * step
      setpt(shape_pts, j + 1, cx + rad * math.cos(a), cy - rad * math.sin(a))
    end
    trim_from(shape_pts, sides + 2)
    -- triangle fan as explicit 1-based triples (API: indices are triples)
    local k = 0
    for j = 1, sides do
      local nxt = j % sides + 1
      shape_idx[k + 1], shape_idx[k + 2], shape_idx[k + 3] = 1, 1 + j, 1 + nxt
      k = k + 3
    end
    trim_from(shape_idx, k + 1)
    e.color(clamp01(spec.r or 1), clamp01(spec.g or 1), clamp01(spec.b or 1),
            clamp01(spec.a or 1))
    e.update_mesh(shape_mesh, shape_pts, shape_idx)
    e.draw_mesh(shape_mesh)
  end
end

-- ------------------------------------------------------------------ module

return {
  api_version = 1,

  setup = function(ctx)
    e.param("motion", 0.5, 0, 1, 1)
    e.param("preset", 1, 1, #PRESETS, 2)
    e.param("detail", 0.5, 0, 1, 3)
    e.param("hue", 0.5, 0, 1, 4)
    e.param("feedback", 0.5, 0, 1, 5)

    shader.warp_default = e.shader("frag/warp_default.frag")
    shader.warp_sphere = e.shader("frag/warp_sphere.frag")
    shader.warp_kaleido = e.shader("frag/warp_kaleido.frag")
    shader.warp_blur = e.shader("frag/warp_blur.frag")
    shader.warp_diffuse = e.shader("frag/warp_diffuse.frag")
    shader.comp_default = e.shader("frag/comp_default.frag")
    shader.comp_softmax = e.shader("frag/comp_softmax.frag")
    shader.comp_plasma = e.shader("frag/comp_plasma.frag")
    shader.comp_rotoblur = e.shader("frag/comp_rotoblur.frag")
    shader.blur1 = e.shader("frag/blur1.frag")

    -- Compile the whole catalog up front: preset switching is then allocation
    -- free apart from the state table.
    for i = 1, #PRESETS do compiled[i] = build_compiled(PRESETS[i]) end

    -- Content targets for every size the catalog asks for (three targets:
    -- front/back/blur, i.e. 3 of the 8 allowed).
    for i = 1, #PRESETS do
      local w, h = content_size(PRESETS[i])
      target_set(w, h)
    end

    for i = 1, MAX_WAVES do wave_meshes[i] = e.new_mesh() end
    builtin_mesh = e.new_mesh()
    shape_mesh = e.new_mesh()
    builtin_pts, shape_pts, shape_idx = {}, {}, {}
    for i = 1, 3 * SHAPE_MAX_SIDES do shape_idx[i] = 1 end
    for c = 1, PARTICLE_CLASSES do
      particle_meshes[c] = e.new_mesh()
      particle_pts[c], particle_idx[c] = {}, {}
    end

    seed_base = 1 + math.floor(e.random() * 2147482000)
    load_preset(1, next_seed())
  end,

  draw = function(ctx)
    local dt = ctx.dt
    if type(dt) ~= "number" or dt ~= dt or dt <= 0 then
      dt = 1 / 60
    elseif dt > 0.25 then
      dt = 0.25
    end

    local params = ctx.params or {}
    local motion = clamp_num(params.motion, 0.5, 0, 1)
    local detail = clamp_num(params.detail, 0.5, 0, 1)
    local hue_knob = clamp_num(params.hue, 0.5, 0, 1)
    local feedback = clamp_num(params.feedback, 0.5, 0, 1)

    -- k2: a full reload (fresh state + per_frame_init) on every slot change.
    -- A preset that does not compile leaves the running one in place.
    local want = math.floor(clamp_num(params.preset, preset_index, 1, #PRESETS) + 0.5)
    want = clamp(want, 1, #PRESETS)
    if want ~= preset_index then load_preset(want, next_seed()) end

    -- (1) env: audio envelopes + clocks
    local audio = ctx.audio or {}
    local bands = audio.bands
    local bass, mid, treb = 0, 0, 0
    if type(bands) == "table" then
      bass, mid, treb = band_value(bands[1]), band_value(bands[2]), band_value(bands[3])
    end
    local alpha = 1 - math.exp(-dt * LN2 / ENV_HALF_LIFE)
    att.bass = clamp(att.bass + (bass - att.bass) * alpha, 0, BAND_MAX)
    att.mid = clamp(att.mid + (mid - att.mid) * alpha, 0, BAND_MAX)
    att.treb = clamp(att.treb + (treb - att.treb) * alpha, 0, BAND_MAX)

    real_frame = real_frame + 1
    fps_est = fps_est + (1 / dt - fps_est) * 0.05
    local speed = MOTION_LO + MOTION_SPAN * motion
    clock.time = clock.time + dt * speed
    clock.frame = clock.frame + speed

    state.bass, state.mid, state.treb = bass, mid, treb
    state.bass_att, state.mid_att, state.treb_att = att.bass, att.mid, att.treb
    state.time = clock.time
    state.frame = clock.frame
    state.progress = (clock.time % PROGRESS_WRAP) / PROGRESS_WRAP
    state.fps = fps_est

    -- In-family beat: re-run per_frame_init with a fresh seed, never switch.
    if ctx.trigger then
      beat = 1
      run_init(next_seed())
    else
      beat = beat - dt * BEAT_RATE
      if beat < 0 then beat = 0 end
    end

    -- (2) per_frame -> persistent state
    local results, err = current.frame(state)
    if results then
      merge(state, results)
    else
      log_once("run:frame:" .. tostring(preset.name), err) -- keep previous vars
    end

    -- (3) clamp engine vars
    clamp_engine()
    sync_point_env()

    local w, h = content_w, content_h
    local left, right = audio.left, audio.right
    if type(left) ~= "table" then left = nil end
    if type(right) ~= "table" then right = nil end
    local energy = clamp(bass + 0.5 * beat, 0, 4)

    -- (3b) blurred copy of the feedback, for warp archetypes that gather through
    -- it (warp_blur). Runs before the warp because it reads `front`.
    local warp_samplers = { prev = front }
    if preset.warp_archetype == "blur" then
      e.begin_target(blur)
      e.color(1, 1, 1)
      e.draw_shader(shader.blur1, ctx.time, energy, motion, blur1_uniforms(w, h),
                    { src = front })
      e.end_target()
      warp_samplers.prev_blur = blur
    end

    -- (4) warp pass: `back` samples `front` (feedback only, never adds light)
    e.begin_target(back)
    e.color(1, 1, 1)
    e.draw_shader(warp_shader(), ctx.time, energy, motion,
                  warp_uniforms(w, h, feedback), warp_samplers)
    e.end_target()

    -- (5) waves + shapes on top of the warped feedback
    e.begin_target(back)
    e.color(1, 1, 1)
    draw_custom_waves(w, h, detail, left, right)
    draw_builtin_wave(w, h, detail, left, right, audio.fft_left)
    draw_shapes(w, h, detail)
    draw_particles(w, h, dt * speed)
    e.end_target()

    -- (6) composite at content resolution, then upscale to the screen:
    -- the tone/gather math dominates the frame budget at 1280x720, and the
    -- whole scene library already upscales content passes (SCENE-LIBRARY).
    local comp_sh, comp_u = comp_shader_and_uniforms(hue_knob)
    e.begin_target(comp_out)
    e.color(1, 1, 1)
    e.draw_shader(comp_sh, ctx.time, energy, motion, comp_u, { fb = back })
    e.end_target()
    e.color(1, 1, 1)
    e.draw_target(comp_out, 0, 0, ctx.width, ctx.height)

    -- (7) ping-pong
    front, back = back, front
  end,

  save = function()
    local pool = {}
    for j = 1, 32 do pool[tostring(j)] = state["q" .. j] or 0 end
    return {
      preset = preset_index,
      clock_time = clock.time,
      clock_frame = clock.frame,
      real_frame = real_frame,
      beat = beat,
      att = { bass = att.bass, mid = att.mid, treb = att.treb },
      q = pool,
    }
  end,

  restore = function(saved)
    if type(saved) ~= "table" then return end
    local index = math.floor(clamp_num(saved.preset, 1, 1, #PRESETS))
    if index ~= preset_index then load_preset(index, next_seed()) end
    local pool = saved.q
    if type(pool) == "table" then
      for j = 1, 32 do
        local v = pool[tostring(j)]
        if type(v) == "number" and v == v then state["q" .. j] = v end
      end
    end
    local a = saved.att
    if type(a) == "table" then
      att.bass = clamp_num(a.bass, att.bass, 0, BAND_MAX)
      att.mid = clamp_num(a.mid, att.mid, 0, BAND_MAX)
      att.treb = clamp_num(a.treb, att.treb, 0, BAND_MAX)
    end
    beat = clamp_num(saved.beat, beat, 0, 1)
    clock.time = clamp_num(saved.clock_time, clock.time, 0, 1e9)
    clock.frame = clamp_num(saved.clock_frame, clock.frame, 0, 1e9)
    real_frame = clamp_num(saved.real_frame, real_frame, 0, 1e9)
  end,
}
