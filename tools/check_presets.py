#!/usr/bin/env python3
"""Preset-catalog contract validator for the milkdrop engine.

Runs the engine's own evaluator against the real catalog, so the checks are
authoritative rather than a re-implementation: every equation string must
compile through ``lib/evaluator.lua`` and must evaluate to finite numbers over a
synthetic multi-frame run.

    python3 tools/check_presets.py [--json] [--presets PATH] [--expect-count N]

Exit codes: 0 every check passed; 1 a preset failed the contract; 2 the tool
could not run (no Lua interpreter, unreadable catalog, driver crash).

Requires a Lua interpreter on PATH (``luajit``, ``lua``, ``lua5.1``, ``lua5.3``,
``lua5.4``) or ``$CHECK_PRESETS_LUA``. There is deliberately no interpreter-free
mode: parsing the catalog in Python would mean a second implementation of Lua
table semantics that can drift from the engine's, and a validator that quietly
checks less is worse than one that refuses to run. See docs/PRESET-CONTRACT.md.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

INTERPRETER_PREFERENCES = ("luajit", "lua", "lua5.1", "lua5.3", "lua5.4")
FRAMES = 120
TIMEOUT_SECONDS = 90
DEFAULT_PRESETS = "milkdrop/presets/presets.lua"

# Emitted as tab-separated records rather than JSON: a Lua JSON encoder is more
# code and more failure modes than a four-field line format.
DRIVER = r"""
-- argv: <evaluator.lua> <presets.lua> <frames>
local ev_path, presets_path, frames = arg[1], arg[2], tonumber(arg[3])
local ev = dofile(ev_path)
local P = dofile(presets_path)

local function say(...) io.write(table.concat({...}, "\t"), "\n") end
local function err(preset, field, message)
  say("E", preset, field, tostring(message):gsub("[\t\n]", " "))
end

if type(P) ~= "table" then
  err("catalog", "-", "does not return a table")
  say("SUMMARY", "0", "1")
  return
end
say("COUNT", tostring(#P))

local REQUIRED = {
  "name", "per_frame_init", "per_frame", "per_pixel",
  "warp_archetype", "comp_archetype", "warp_params", "comp_params",
  "wave_mode", "wave_a", "waves", "shapes", "decay", "q",
}
local WARP = { default = true, sphere = true, kaleido = true, blur = true, diffuse = true }
local COMP = { default = true, softmax = true, plasma = true, rotoblur = true }
local EQUATION_FIELDS = { "per_frame_init", "per_frame", "per_pixel" }

-- Readable engine inputs (docs/API.md contract + the per-point pool). Anything
-- else an equation reads must be assigned somewhere in the same preset: the
-- evaluator resolves an unknown name to 0, so a typo is silent.
local READABLE = {
  bass = true, mid = true, treb = true,
  bass_att = true, mid_att = true, treb_att = true,
  time = true, fps = true, frame = true, progress = true,
  sample = true, x = true, y = true, rad = true, ang = true,
  value1 = true, value2 = true,
}
for i = 1, 32 do READABLE["q" .. i] = true end

local FUNCTIONS = {}
for _, name in ipairs({
  "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "abs", "min", "max",
  "sqr", "sqrt", "pow", "log", "log10", "int", "sign", "exp", "sigmoid",
  "if", "above", "below", "equal", "rand", "bor", "band", "bnot",
}) do FUNCTIONS[name] = true end

local names, failures = {}, 0
local function fail(preset, field, message) failures = failures + 1; err(preset, field, message) end

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

for index = 1, #P do
  local p = P[index]
  local label = (type(p) == "table" and type(p.name) == "string" and p.name ~= "")
      and p.name or ("#" .. index)

  if type(p) ~= "table" then
    fail(label, "-", "preset is not a table")
  else
    -- schema
    for _, key in ipairs(REQUIRED) do
      if p[key] == nil then fail(label, key, "missing required key") end
    end
    if type(p.name) ~= "string" or p.name == "" then
      fail(label, "name", "must be a non-empty string")
    elseif names[p.name] then
      fail(label, "name", "duplicate name")
    else
      names[p.name] = true
    end
    if p.warp_archetype ~= nil and not WARP[p.warp_archetype] then
      fail(label, "warp_archetype", "unknown archetype: " .. tostring(p.warp_archetype))
    end
    if p.comp_archetype ~= nil and not COMP[p.comp_archetype] then
      fail(label, "comp_archetype", "unknown archetype: " .. tostring(p.comp_archetype))
    end
    if p.decay ~= nil and not finite(p.decay) then
      fail(label, "decay", "must be a finite number")
    end
    if p.q ~= nil and type(p.q) ~= "table" then
      fail(label, "q", "must be a table")
    end
    -- `particles` is optional: it selects the mode's CPU starfield pool, which
    -- only the starfield archetype uses. Validated when present, never required.
    if p.particles ~= nil then
      if type(p.particles) ~= "table" then
        fail(label, "particles", "must be a table")
      else
        for _, key in ipairs({ "count", "speed", "size" }) do
          local v = p.particles[key]
          if v ~= nil and not finite(v) then
            fail(label, "particles." .. key, "must be a finite number")
          end
        end
        if p.particles.tints ~= nil and type(p.particles.tints) ~= "table" then
          fail(label, "particles.tints", "must be a table of {r,g,b} triples")
        end
      end
    end
    if p.param_bridge ~= nil then
      if type(p.param_bridge) ~= "table" then
        fail(label, "param_bridge", "must be a table")
      else
        for k, v in pairs(p.param_bridge) do
          if type(k) ~= "string" or type(v) ~= "string" then
            fail(label, "param_bridge", "keys and values must be strings")
          end
        end
      end
    end

    -- equation strings: collect then compile
    local equations = {}
    for _, field in ipairs(EQUATION_FIELDS) do
      if p[field] ~= nil then
        if type(p[field]) ~= "string" then
          fail(label, field, "must be a string")
        else
          equations[#equations + 1] = { field, p[field] }
        end
      end
    end
    if type(p.waves) == "table" then
      for i, w in ipairs(p.waves) do
        if type(w) == "table" and w.t1 ~= nil then
          if type(w.t1) ~= "string" then
            fail(label, "wave[" .. i .. "].t1", "must be a string")
          else
            equations[#equations + 1] = { "wave[" .. i .. "].t1", w.t1 }
          end
        end
      end
    end

    local compiled = {}
    for _, entry in ipairs(equations) do
      local field, code = entry[1], entry[2]
      local f, compile_error = ev.compile(code)
      if not f then
        fail(label, field, compile_error or "compile failed")
      else
        compiled[#compiled + 1] = { field, f }
      end
    end

    -- Identifier audit. Reported as warnings, never failures: the evaluator
    -- resolves an undefined name to 0, so a mistyped input is silent, but a
    -- legitimate custom variable assigned in another block must not be punished.
    -- Tokenised properly rather than pattern-scanned, because stripping numeric
    -- literals from the raw text would also strip the digits from `q1`/`t1`.
    local function tokens(code)
      local i, n, out = 1, #code, {}
      while i <= n do
        local c = code:sub(i, i)
        if c:match("%s") then
          i = i + 1
        elseif c:match("[%a_]") then
          local _, e = code:find("^[%a_][%w_]*", i)
          out[#out + 1] = { "name", code:sub(i, e) }
          i = e + 1
        elseif c:match("%d") or (c == "." and code:sub(i + 1, i + 1):match("%d")) then
          local _, e = code:find("^%d*%.?%d*[eE]?[%+%-]?%d*", i)
          if not e or e < i then e = i end
          out[#out + 1] = { "number", code:sub(i, e) }
          i = e + 1
        elseif c == '"' or c == "'" then
          local pattern = c == '"' and '^"[^"]*"' or "^'[^']*'"
          local _, e = code:find(pattern, i)
          out[#out + 1] = { "string", code:sub(i, e or n) }
          i = (e or n) + 1
        else
          out[#out + 1] = { "op", c }
          i = i + 1
        end
      end
      return out
    end

    local assigned = {}
    -- assignment targets: a name token immediately followed by `=` (not `==`)
    for _, entry in ipairs(equations) do
      local list = tokens(entry[2])
      for index, token in ipairs(list) do
        if token[1] == "name" then
          local nxt = list[index + 1]
          if nxt and nxt[1] == "op" and nxt[2] == "=" then assigned[token[2]] = true end
        end
      end
    end

    local warned = {}
    for _, entry in ipairs(equations) do
      local field = entry[1]
      local list = tokens(entry[2])
      for index, token in ipairs(list) do
        if token[1] == "name" then
          local name = token[2]
          local nxt = list[index + 1]
          local is_call = nxt ~= nil and nxt[1] == "op" and nxt[2] == "("
          if is_call and not FUNCTIONS[name] and not warned[name] then
            warned[name] = true
            say("W", label, field, "call to unknown function: " .. name)
          elseif not is_call and not assigned[name] and not READABLE[name] and not FUNCTIONS[name]
              and not warned[name] then
            warned[name] = true
            say("W", label, field, "reads as 0: never assigned in this preset and not a readable input: " .. name)
          end
        end
      end
    end

    -- smoke run: finite results only
    local env = {
      bass = 0.3, mid = 0.2, treb = 0.1,
      bass_att = 0.25, mid_att = 0.18, treb_att = 0.09,
      time = 0, frame = 0, fps = 60, progress = 0,
      sample = 0, x = 0.5, y = 0.5, rad = 0, ang = 0,
      value1 = 0, value2 = 0,
      _rand = function() return 0.5 end,
    }
    for i = 1, 32 do env["q" .. i] = 0 end

    local non_finite = 0
    for frame = 1, frames do
      env.frame, env.time, env.progress = frame, frame / 60, frame / 14400
      for _, entry in ipairs(compiled) do
        local field, f = entry[1], entry[2]
        local ok, results = pcall(f, env)
        if not ok then
          fail(label, field, "runtime error: " .. tostring(results))
        elseif type(results) == "table" then
          for key, value in pairs(results) do
            if type(value) == "number" and not finite(value) then non_finite = non_finite + 1 end
            env[key] = value
          end
        end
      end
    end
    if non_finite > 0 then
      fail(label, "smoke", non_finite .. " non-finite result(s) over " .. frames .. " frames")
    end
  end
  say("OK", label)
end

say("SUMMARY", tostring(#P - failures), tostring(failures))
"""


def resolve_interpreter() -> tuple[str | None, str | None]:
    override = os.environ.get("CHECK_PRESETS_LUA")
    if override:
        found = shutil.which(override) or (override if os.path.exists(override) else None)
        if not found:
            return None, "$CHECK_PRESETS_LUA=%s is not executable" % override
        return found, None
    for candidate in INTERPRETER_PREFERENCES:
        found = shutil.which(candidate)
        if found:
            return found, None
    return None, "no Lua interpreter on PATH (tried %s)" % ", ".join(INTERPRETER_PREFERENCES)


def evaluator_path_for(presets: Path) -> Path:
    return (presets.parent / ".." / "lib" / "evaluator.lua").resolve()


def validate(presets: Path, frames: int) -> dict:
    """Run the driver; return a report dict. Never raises for preset failures."""
    report: dict = {"presets_path": str(presets), "frames": frames, "errors": [], "warnings": [], "ok": [], "count": None}
    interpreter, problem = resolve_interpreter()
    if interpreter is None:
        report["tool_error"] = problem
        return report
    report["interpreter"] = interpreter

    if not presets.is_file():
        report["tool_error"] = "catalog not found: %s" % presets
        return report
    evaluator = evaluator_path_for(presets)
    if not evaluator.is_file():
        report["tool_error"] = "evaluator not found: %s" % evaluator
        return report
    report["evaluator_path"] = str(evaluator)

    try:
        completed = subprocess.run(
            [interpreter, "-", str(evaluator), str(presets), str(frames)],
            input=DRIVER,
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        report["tool_error"] = "driver could not run: %s" % error
        return report

    if completed.returncode != 0 or "SUMMARY" not in completed.stdout:
        detail = completed.stderr.strip() or completed.stdout.strip() or "no output"
        report["tool_error"] = "driver exited %d: %s" % (completed.returncode, detail[-400:])
        return report

    for line in completed.stdout.splitlines():
        parts = line.split("\t")
        kind = parts[0]
        if kind == "COUNT" and len(parts) >= 2:
            report["count"] = int(parts[1])
        elif kind == "E" and len(parts) >= 4:
            report["errors"].append({"preset": parts[1], "field": parts[2], "message": parts[3]})
        elif kind == "W" and len(parts) >= 4:
            report["warnings"].append({"preset": parts[1], "field": parts[2], "message": parts[3]})
        elif kind == "OK" and len(parts) >= 2:
            report["ok"].append(parts[1])
        elif kind == "SUMMARY" and len(parts) >= 3:
            report["passed"] = int(parts[1])
            report["failed"] = int(parts[2])
    return report


def render(report: dict, expected_count: int | None) -> tuple[str, int]:
    lines = []
    if "tool_error" in report:
        lines.append("check_presets: ERROR — %s" % report["tool_error"])
        return "\n".join(lines) + "\n", 2

    lines.append("catalog:   %s" % report["presets_path"])
    lines.append("evaluator: %s" % report["evaluator_path"])
    lines.append("checker:   %s (real compile + %d-frame smoke run)"
                 % (report["interpreter"], report["frames"]))
    lines.append("presets:   %d" % (report["count"] or 0))
    lines.append("")

    count_problem = None
    if expected_count is not None and report["count"] != expected_count:
        count_problem = "expected %d preset(s), found %d" % (expected_count, report["count"])

    if report["errors"]:
        lines.append("FAIL — %d problem(s)" % len(report["errors"]))
        for item in report["errors"]:
            lines.append("  - %s: %s: %s" % (item["preset"], item["field"], item["message"]))
    if count_problem:
        lines.append("FAIL — %s" % count_problem)
    if report["warnings"]:
        lines.append("")
        lines.append("WARN — %d name(s) read as 0 (not fatal; the evaluator resolves "
                     "unknown names to 0, so check these by eye):" % len(report["warnings"]))
        for item in report["warnings"]:
            lines.append("  - %s: %s: %s" % (item["preset"], item["field"], item["message"]))
    if not report["errors"] and not count_problem:
        lines.append("")
        lines.append("PASS — %d preset(s): every equation compiles through the engine's own "
                     "evaluator, the schema and archetype names are valid, names are unique, "
                     "and the finite-result contract holds over %d frames."
                     % (report["count"] or 0, report["frames"]))
    return "\n".join(lines) + "\n", 1 if (report["errors"] or count_problem) else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Validate the milkdrop preset catalog.")
    parser.add_argument("--presets", default=DEFAULT_PRESETS, type=Path)
    parser.add_argument("--expect-count", type=int, default=None,
                        help="assert the catalog holds exactly N presets (opt-in)")
    parser.add_argument("--frames", type=int, default=FRAMES, help="smoke-run length")
    parser.add_argument("--json", action="store_true", help="emit the report as JSON")
    args = parser.parse_args(argv)

    report = validate(args.presets, args.frames)
    text, code = render(report, args.expect_count)
    if args.json:
        payload = dict(report)
        payload["expected_count"] = args.expect_count
        payload["exit_code"] = code
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        sys.stdout.write(text)
    return code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))