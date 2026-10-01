-- modes/milkdrop/lib/evaluator.lua
-- AVS-subset expression evaluator for the milkdrop engine (Track B / slice T1).
-- Pure Lua 5.1 / LuaJIT; also runs on 5.2-5.4 (math shims below). No eyesy deps.
--
--   local ev = require("lib.evaluator")
--   local f, err = ev.compile("zoom = 1.004 + 0.02*bass; rot = 0.1*q2*sin(time)")
--   local results = f({ bass = 0.4, q2 = 0.5, time = 2.0 })  --> { zoom=.., rot=.. }
--
-- Grammar: ';'-separated `name = expr` statements (trailing and repeated ';'
-- are fine; empty code compiles to a no-op). Operators: + - * / % , right
-- associative ^, unary minus, parens, literals 1 / 0.5 / .5 / 1e3. Function
-- set: see FUNCS -- sqr is x*x, sqrt is the square root, int truncates toward
-- zero, % is Lua's floor-mod, and band/bor/bnot work on 32-bit two's
-- complement ints (arguments truncated toward zero).
--
-- Reads resolve to the value written earlier in the same block, else env[name]
-- when that is a number, else 0 -- so undefined variables (and q1..q32 before
-- the engine seeds them) read as 0. Writes land in the results table returned
-- by f(env); env is never mutated. The engine merges results into its
-- persistent state table and passes that back as env next frame, which is how
-- q1..q32 and custom variables survive.
--
-- Every number the evaluator produces is finite: NaN and +/-inf collapse to 0.
-- ev.compile returns nil, errmsg on parse errors; ev.run and the compiled
-- function never throw (an internal error comes back as nil, errmsg too).

local floor, ceil = math.floor, math.ceil

-- ------------------------------------------------------------------- shims --

-- 5.1/LuaJIT expose math.atan2/math.log10; 5.3+ use atan(y,x)/log(x,base).
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local log10 = math.log10 or function(x) return math.log(x) / 2.302585092994045684 end

-- ----------------------------------------------------------------- numbers --

-- x - x is 0 for every finite double and NaN for NaN and +/-inf, so a single
-- subtraction is the whole finiteness test. Non-numbers read as 0.
local function num(v)
  if type(v) ~= "number" then return 0 end
  local d = v - v
  if d ~= 0 then return 0 end
  return v
end

-- ----------------------------------------------------------------- bitwise --

local TWO31, TWO32 = 2147483648, 4294967296

local function trunc(v)
  if v < 0 then return ceil(v) end
  return floor(v)
end

-- Unsigned 32-bit view of a float argument (truncated toward zero).
local function u32(v)
  return trunc(v) % TWO32
end

local function signed(n)
  if n >= TWO31 then return n - TWO32 end
  return n
end

local function band_u(a, b)          -- unsigned a & b
  a, b = u32(a), u32(b)
  local r, bit = 0, 1
  for _ = 1, 32 do
    local abit, bbit = a % 2, b % 2
    if abit == 1 and bbit == 1 then r = r + bit end
    a, b, bit = (a - abit) / 2, (b - bbit) / 2, bit + bit
  end
  return r
end

local function band(a, b) return signed(band_u(a, b)) end
-- a | b == a + b - (a & b) exactly, which holds bit for bit in doubles.
local function bor(a, b) return signed(u32(a) + u32(b) - band_u(a, b)) end
local function bnot(a) return signed(TWO32 - 1 - u32(a)) end

-- ------------------------------------------------------- fallback PRNG -----

-- Used only when env._rand is absent, so rand() stays finite and reproducible
-- inside a process with no seeded handle (the engine always supplies _rand).
local fallback_state = 1
local function fallback_rand()
  fallback_state = (fallback_state * 16807) % 2147483647
  return fallback_state / 2147483647
end

-- ------------------------------------------------------------ functions ----

local FUNCS = {
  sin     = { n = 1, f = math.sin },
  cos     = { n = 1, f = math.cos },
  tan     = { n = 1, f = math.tan },
  asin    = { n = 1, f = math.asin },
  acos    = { n = 1, f = math.acos },
  atan    = { n = 1, f = math.atan },
  atan2   = { n = 2, f = atan2 },
  abs     = { n = 1, f = math.abs },
  min     = { n = 2, f = math.min },
  max     = { n = 2, f = math.max },
  sqr     = { n = 1, f = function(x) return x * x end },
  sqrt    = { n = 1, f = math.sqrt },
  pow     = { n = 2, f = function(x, y) return x ^ y end },
  log     = { n = 1, f = math.log },
  log10   = { n = 1, f = log10 },
  int     = { n = 1, f = trunc },
  sign    = { n = 1, f = function(x)
                        if x > 0 then return 1 end
                        if x < 0 then return -1 end
                        return 0
                      end },
  exp     = { n = 1, f = math.exp },
  sigmoid = { n = 1, f = function(x) return 1 / (1 + math.exp(-x)) end },
  above   = { n = 2, f = function(a, b) if a > b then return 1 end return 0 end },
  below   = { n = 2, f = function(a, b) if a < b then return 1 end return 0 end },
  equal   = { n = 2, f = function(a, b) if a == b then return 1 end return 0 end },
  band    = { n = 2, f = band },
  bor     = { n = 2, f = bor },
  bnot    = { n = 1, f = bnot },
}

local OPS = {
  ["+"] = function(a, b) return a + b end,
  ["-"] = function(a, b) return a - b end,
  ["*"] = function(a, b) return a * b end,
  ["/"] = function(a, b) return a / b end,
  ["%"] = function(a, b) return a % b end,
  ["^"] = function(a, b) return a ^ b end,
}

-- --------------------------------------------------------------- nodes -----

-- Node signature: node(env, loc) -> finite number. `loc` holds the values
-- written by earlier statements in the current run and doubles as the results
-- table handed back to the caller.

local function bin(op, fa, fb)
  return function(env, loc) return num(op(fa(env, loc), fb(env, loc))) end
end

local function neg(fa)
  return function(env, loc) return num(-fa(env, loc)) end
end

local function read(name)
  return function(env, loc)
    local v = loc[name]
    if v == nil then v = env[name] end
    return num(v)
  end
end

local function call1(f, fa)
  return function(env, loc) return num(f(fa(env, loc))) end
end

local function call2(f, fa, fb)
  return function(env, loc) return num(f(fa(env, loc), fb(env, loc))) end
end

-- rand() draws from the deterministic PRNG handle the engine seeds per run.
local function call_rand(fa)
  return function(env, loc)
    local r = env._rand
    local draw
    if type(r) == "function" then draw = r() else draw = fallback_rand() end
    return num(num(draw) * fa(env, loc))
  end
end

-- if(c,a,b) only evaluates the branch it selects.
local function call_if(fc, fa, fb)
  return function(env, loc)
    if fc(env, loc) ~= 0 then return fa(env, loc) end
    return fb(env, loc)
  end
end

-- Fold an operator whose operands are both compile-time constants.
local function fold(op, fa, ka, fb, kb)
  if ka ~= nil and kb ~= nil then
    local v = num(op(ka, kb))
    return function() return v end, v
  end
  return bin(op, fa, fb), nil
end

-- ------------------------------------------------------------- tokenizer ---

local OPCHAR = {
  ["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true, ["%"] = true,
  ["^"] = true, ["("] = true, [")"] = true, [","] = true, ["="] = true,
  [";"] = true,
}

local function is_digit(c) return c >= "0" and c <= "9" end
local function is_alpha(c)
  return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"
end

local function tokenize(src)
  local toks, n, i = {}, #src, 1
  while i <= n do
    local c = src:sub(i, i)
    if c == " " or c == "\t" or c == "\n" or c == "\r" then
      i = i + 1
    elseif is_digit(c) or (c == "." and is_digit(src:sub(i + 1, i + 1))) then
      local start = i
      while i <= n and is_digit(src:sub(i, i)) do i = i + 1 end
      if src:sub(i, i) == "." then
        i = i + 1
        while i <= n and is_digit(src:sub(i, i)) do i = i + 1 end
      end
      local e = src:sub(i, i)
      if e == "e" or e == "E" then
        local j = i + 1
        local sign = src:sub(j, j)
        if sign == "+" or sign == "-" then j = j + 1 end
        if is_digit(src:sub(j, j)) then
          i = j
          while i <= n and is_digit(src:sub(i, i)) do i = i + 1 end
        end
      end
      toks[#toks + 1] = { t = "num", v = tonumber(src:sub(start, i - 1)), p = start }
    elseif is_alpha(c) then
      local start = i
      while i <= n and (is_alpha(src:sub(i, i)) or is_digit(src:sub(i, i))) do i = i + 1 end
      toks[#toks + 1] = { t = "name", v = src:sub(start, i - 1), p = start }
    elseif OPCHAR[c] then
      toks[#toks + 1] = { t = c, p = i }
      i = i + 1
    else
      return nil, "unexpected character '" .. c .. "' at " .. i
    end
  end
  toks[#toks + 1] = { t = "eof", p = n + 1 }
  return toks
end

local function token_text(tk)
  if tk.t == "num" then return "number " .. tostring(tk.v) end
  if tk.t == "name" then return "name '" .. tk.v .. "'" end
  return "'" .. tk.t .. "'"
end

-- ---------------------------------------------------------------- parser ---

local parse_add, parse_mul, parse_unary, parse_power, parse_primary, parse_call

-- Every parse_* returns node, const_value, next_index on success and
-- nil, errmsg on failure (a node is always a function, so the two are
-- unambiguous).

parse_primary = function(toks, i)
  local tk = toks[i]
  if tk.t == "num" then
    local v = tk.v
    return function() return v end, v, i + 1
  elseif tk.t == "name" then
    if toks[i + 1].t == "(" then return parse_call(toks, i) end
    return read(tk.v), nil, i + 1
  elseif tk.t == "(" then
    local f, k, j = parse_add(toks, i + 1)
    if not f then return nil, k end
    if toks[j].t ~= ")" then
      return nil, "expected ')' at " .. toks[j].p
    end
    return f, k, j + 1
  end
  return nil, "unexpected " .. token_text(tk) .. " at " .. tk.p
end

parse_power = function(toks, i)
  local f, k, j = parse_primary(toks, i)
  if not f then return nil, k end
  if toks[j].t == "^" then
    local g, gk, m = parse_unary(toks, j + 1)
    if not g then return nil, gk end
    local node, nk = fold(OPS["^"], f, k, g, gk)
    return node, nk, m
  end
  return f, k, j
end

parse_unary = function(toks, i)
  if toks[i].t == "-" then
    local f, k, j = parse_unary(toks, i + 1)
    if not f then return nil, k end
    if k ~= nil then
      local v = num(-k)
      return function() return v end, v, j
    end
    return neg(f), nil, j
  end
  return parse_power(toks, i)
end

parse_mul = function(toks, i)
  local f, k, j = parse_unary(toks, i)
  if not f then return nil, k end
  while true do
    local t = toks[j].t
    if t == "*" or t == "/" or t == "%" then
      local g, gk, m = parse_unary(toks, j + 1)
      if not g then return nil, gk end
      local node, nk = fold(OPS[t], f, k, g, gk)
      f, k, j = node, nk, m
    else
      return f, k, j
    end
  end
end

parse_add = function(toks, i)
  local f, k, j = parse_mul(toks, i)
  if not f then return nil, k end
  while true do
    local t = toks[j].t
    if t == "+" or t == "-" then
      local g, gk, m = parse_mul(toks, j + 1)
      if not g then return nil, gk end
      local node, nk = fold(OPS[t], f, k, g, gk)
      f, k, j = node, nk, m
    else
      return f, k, j
    end
  end
end

parse_call = function(toks, i)
  local name = toks[i].v
  local is_if = name == "if"
  local is_rand = name == "rand"
  local entry = FUNCS[name]
  if not entry and not is_if and not is_rand then
    return nil, "unknown function '" .. name .. "' at " .. toks[i].p
  end
  local want = entry and entry.n or (is_rand and 1 or 3)

  local args, count, j = {}, 0, i + 2
  if toks[j].t ~= ")" then
    while true do
      local f, k, m = parse_add(toks, j)
      if not f then return nil, k end
      count = count + 1
      args[count] = f
      j = m
      if toks[j].t == "," then
        j = j + 1
      elseif toks[j].t ~= ")" then
        return nil, "expected ',' or ')' at " .. toks[j].p
      else
        break
      end
    end
  end
  if count ~= want then
    return nil, "function '" .. name .. "' takes " .. want .. " argument(s), got "
      .. count .. " at " .. toks[i].p
  end

  local node
  if is_rand then
    node = call_rand(args[1])
  elseif is_if then
    node = call_if(args[1], args[2], args[3])
  elseif want == 1 then
    node = call1(entry.f, args[1])
  else
    node = call2(entry.f, args[1], args[2])
  end
  return node, nil, j + 1
end

local function parse_program(src)
  local toks, terr = tokenize(src)
  if not toks then return nil, terr end
  local stmts, count, i = {}, 0, 1
  while toks[i].t ~= "eof" do
    if toks[i].t == ";" then
      i = i + 1
    else
      local tk = toks[i]
      if tk.t ~= "name" then
        return nil, "expected a variable name at " .. tk.p
      end
      if toks[i + 1].t ~= "=" then
        return nil, "expected '=' after '" .. tk.v .. "' at " .. toks[i + 1].p
      end
      local f, k, j = parse_add(toks, i + 2)
      if not f then return nil, k end
      count = count + 1
      stmts[count] = { name = tk.v, node = f }
      i = j
      local t = toks[i].t
      if t ~= ";" and t ~= "eof" then
        return nil, "unexpected " .. token_text(toks[i]) .. " at " .. toks[i].p
      end
    end
  end
  return stmts
end

-- --------------------------------------------------------------- surface ---

local EMPTY = {}

local function program(stmts)
  local count = #stmts
  return function(env, loc)
    for s = 1, count do
      local st = stmts[s]
      loc[st.name] = st.node(env, loc)
    end
    return loc
  end
end

-- ev.compile(code) -> f(env) -> results, or nil, errmsg on a parse error.
local function compile(code)
  if code == nil then code = "" end
  if type(code) ~= "string" then return nil, "code must be a string" end
  local ok, stmts, err = pcall(parse_program, code)
  if not ok then return nil, "parse error: " .. tostring(stmts) end
  if not stmts then return nil, err end
  local body = program(stmts)
  return function(env)
    if type(env) ~= "table" then env = EMPTY end
    local loc = {}
    local ran, res = pcall(body, env, loc)
    if not ran then return nil, "runtime error: " .. tostring(res) end
    return res
  end
end

-- ev.run(env, code) -> results for a one-shot block (per_frame_init).
local function run(env, code)
  local f, err = compile(code)
  if not f then return nil, err end
  return f(env)
end

return {
  compile = compile,
  run = run,
}
