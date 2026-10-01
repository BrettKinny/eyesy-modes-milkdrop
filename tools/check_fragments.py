#!/usr/bin/env python3
"""Fragment-contract validator for the milkdrop engine.

Two questions, both answered from the engine rather than from a copy of it:

1. Does each fragment file honour the host contract? No ``#version`` (the host
   adapts an ES2 body), a precision qualifier, ``varying vec2 uv``, exactly one
   ``main``, no duplicate uniform names, and — for the warp fragments, which are
   the only writers of the feedback target — a ``decay`` term (SCENE-LIBRARY
   design law: the warp pass only decays; light is added by the display comp).

2. Does the uniform traffic agree in both directions? The mode is driven against
   a recording stub of the engine, per preset, and every ``draw_shader`` call is
   observed. A uniform the engine supplies but the fragment never declares is a
   dead parameter (a mistyped ``warp_params`` key, exactly the way ``bass_att1``
   reads as 0); a uniform the fragment declares but the engine never supplies is
   a silent zero. Both directions fail.

    python3 tools/check_fragments.py [--json] [--frag-dir DIR] [--main PATH]
                                     [--expect-fragments N]

Exit codes: 0 every check passed; 1 a fragment or a preset's fragment traffic
broke the contract; 2 the tool could not run (no Lua interpreter, missing mode or
fragment directory, driver crash).

Requires a Lua interpreter on PATH (``luajit``, ``lua``, ``lua5.1``, ``lua5.3``,
``lua5.4``) or ``$CHECK_FRAGMENTS_LUA``. There is deliberately no interpreter-free
mode: the fragment traffic is a property of the running mode, and re-deriving it
in Python would be a second implementation of the mode's logic that can drift.
See docs/FRAGMENT-CONTRACT.md.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

INTERPRETER_PREFERENCES = ("luajit", "lua", "lua5.1", "lua5.3", "lua5.4")
TIMEOUT_SECONDS = 90
FRAMES_PER_PRESET = 2
DEFAULT_MAIN = "milkdrop/main.lua"
DEFAULT_FRAG_DIR = "milkdrop/frag"

# `warp_params.dense` is read by the mode's content_size() to pick the reduced
# content target; it is a flag, not a shader uniform, so it never reaches a
# draw_shader call and must not be counted as a dead parameter.
NON_UNIFORM_WARP_PARAMS = {"dense"}

# Uniforms the host binds on every shader draw regardless of the mode's args
# (engine/src/runtime.cpp:713-719): resolution, time, energy and control, plus
# the audio texture when one is allocated. A fragment may rely on them, so they
# count as supplied when checking what a fragment *declares*.
#
# They are deliberately not added to the opposite direction: the host hands them
# to every fragment, so a fragment that does not declare `u_time` is normal and
# must not be reported as receiving a uniform it never declares.
HOST_UNIFORMS = {"u_resolution", "u_time", "u_energy", "u_control"}
HOST_SAMPLERS = {"u_audio"}

# A warp fragment must bound what it writes back into the feedback target: the
# warp pass is the only writer of that target, so an unbounded one accumulates to
# white. Most fragments bound it by decaying, which is the design law. A fragment
# that instead replaces the field with a bounded computation declares that in its
# header, and the declaration must be accompanied by a clamp. The gate cannot
# prove boundedness, so it requires the claim to be visible to a reviewer rather
# than inferring it from a heuristic — `clamp(` alone is too weak, since a
# fragment may clamp a parameter rather than its output.
WARP_BOUND_DIRECTIVE = "warp-bound:"

# Emitted as tab-separated records rather than JSON: a Lua JSON encoder is more
# code and more failure modes than a short line format.
DRIVER = r"""
-- argv: <main.lua path> <frames per preset>
-- Drives the real mode against a recording stub of the engine so the uniform
-- supply is observed, not parsed. Every draw_shader call is reported with the
-- fragment that received it and the names of the uniforms and samplers passed.
local main_path = arg[1]
local frames = tonumber(arg[2]) or 2
local current = "?"

local function say(...) io.write(table.concat({...}, "\t"), "\n") end

local function keys(t)
  local out = {}
  if type(t) == "table" then
    for k in pairs(t) do out[#out + 1] = tostring(k) end
  end
  table.sort(out)
  return table.concat(out, ",")
end

local eyesy = {}
local function noop() end
eyesy.param, eyesy.color = noop, noop
eyesy.begin_target, eyesy.end_target, eyesy.draw_target = noop, noop, noop
eyesy.update_mesh, eyesy.draw_mesh = noop, noop
eyesy.random = function() return 0.5 end
eyesy.target = function(w, h) return { w = w, h = h } end
local mesh_count = 0
eyesy.new_mesh = function() mesh_count = mesh_count + 1; return { id = mesh_count } end
eyesy.shader = function(path) say("SHADER", path); return { path = path } end
eyesy.draw_shader = function(handle, _time, _energy, _control, uniforms, samplers)
  say("DRAW", current, handle.path, keys(uniforms), keys(samplers))
end

_G.eyesy = eyesy

local ok, mod = pcall(dofile, main_path)
if not ok then
  say("ERR", "main.lua", tostring(mod):gsub("[\t\n]", " "))
  say("SUMMARY", "0", "1")
  return
end
if type(mod) ~= "table" or type(mod.setup) ~= "function" or type(mod.draw) ~= "function" then
  say("ERR", "main.lua", "must return a table with setup and draw")
  say("SUMMARY", "0", "1")
  return
end

local setup_ok, setup_err = pcall(mod.setup, { width = 1280, height = 720 })
if not setup_ok then
  say("ERR", "setup", tostring(setup_err):gsub("[\t\n]", " "))
  say("SUMMARY", "0", "1")
  return
end

-- A synthetic but plausible frame: audio bands, 1024-sample L/R waveforms and
-- an fft, so every draw path the presets exercise is actually taken.
local function make_ctx(index, frame_no)
  local left, right, fft = {}, {}, {}
  for k = 1, 1024 do
    left[k] = 0.5 + 0.4 * math.sin(k * 0.31 + frame_no * 0.17)
    right[k] = 0.5 + 0.4 * math.cos(k * 0.23 + frame_no * 0.11)
    fft[k] = 0.5 + 0.4 * math.sin(k * 0.05 + frame_no * 0.07)
  end
  return {
    dt = 1 / 60, time = frame_no / 60, width = 1280, height = 720, trigger = false,
    params = { preset = index, motion = 0.5, detail = 0.5, hue = 0.5, feedback = 0.5 },
    audio = {
      left = left, right = right, fft_left = fft, fft_right = fft,
      bands = { 0.30, 0.25, 0.20 },
    },
  }
end

local catalog_ok, P = pcall(require, "presets/presets")
if not catalog_ok or type(P) ~= "table" then
  say("ERR", "presets/presets", "did not return a table")
  say("SUMMARY", "0", "1")
  return
end

local failures = 0
for i = 1, #P do
  local p = P[i]
  current = tostring(p.name)
  say("PRESET", tostring(i), current, tostring(p.warp_archetype), tostring(p.comp_archetype),
      keys(p.warp_params), keys(p.comp_params), keys(p.param_bridge))
  for f = 1, frames do
    local drew, derr = pcall(mod.draw, make_ctx(i, (i - 1) * frames + f))
    if not drew then
      say("ERR", current, "draw failed: " .. tostring(derr):gsub("[\t\n]", " "))
      failures = failures + 1
      break
    end
  end
end

say("SUMMARY", tostring(#P), tostring(failures))
"""


def resolve_interpreter() -> tuple[str | None, str | None]:
    override = os.environ.get("CHECK_FRAGMENTS_LUA")
    if override:
        found = shutil.which(override) or (override if os.path.exists(override) else None)
        if not found:
            return None, "$CHECK_FRAGMENTS_LUA=%s is not executable" % override
        return found, None
    for candidate in INTERPRETER_PREFERENCES:
        found = shutil.which(candidate)
        if found:
            return found, None
    return None, "no Lua interpreter on PATH (tried %s)" % ", ".join(INTERPRETER_PREFERENCES)


def split_names(value: str) -> list[str]:
    return [name for name in value.split(",") if name]


def strip_comments(text: str) -> str:
    """Drop comments so a mention in prose cannot satisfy a source check.

    Every fragment header documents its uniforms, so an unstripped search for a
    name (``decay``, ``sampler2D``) would pass on the comment alone.
    """
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def declared_uniforms(text: str) -> list[str]:
    return re.findall(r"^\s*uniform\s+\w+\s+(\w+)\s*;", text, re.M)


def check_fragment_source(path: Path, text: str, raw: str) -> list[str]:
    """Host-contract checks that need only the fragment body.

    ``text`` is comment-stripped; ``raw`` is the file as written, needed for the
    header directives that are themselves comments.
    """
    problems = []
    if re.search(r"^\s*#version", text, re.M):
        problems.append("declares #version; the host adapts an ES2 body and supplies its own preamble")
    if not re.search(r"^\s*precision\s+", text, re.M):
        problems.append("no precision qualifier; every fragment must set one")
    if not re.search(r"\bvarying\s+vec2\s+uv\b", text):
        problems.append("does not declare `varying vec2 uv`")
    mains = len(re.findall(r"\bvoid\s+main\s*\(", text))
    if mains != 1:
        problems.append("has %d `void main` definitions, expected exactly 1" % mains)
    uniforms = declared_uniforms(text)
    if not uniforms:
        problems.append("declares no uniforms")
    duplicates = sorted({name for name in uniforms if uniforms.count(name) > 1})
    if duplicates:
        problems.append("declares duplicate uniform(s): %s" % ", ".join(duplicates))
    if path.name.startswith("warp_"):
        body = re.sub(r"^\s*uniform\s+[^;]*;", "", text, flags=re.M)
        declared = WARP_BOUND_DIRECTIVE in raw
        clamped = re.search(r"\bclamp\s*\(", body)
        if not re.search(r"\bdecay\b", body):
            if not declared:
                problems.append(
                    "warp fragment neither decays nor declares how it stays bounded; the warp "
                    "pass is the only writer of the feedback target, so add a `decay` term or a "
                    "`%s` header line stating why the step is bounded" % WARP_BOUND_DIRECTIVE)
            elif not clamped:
                problems.append(
                    "declares `%s` but never calls clamp(); a bounded-warp claim needs a clamp "
                    "in the body to mean anything" % WARP_BOUND_DIRECTIVE)
    return problems


def validate(main: Path, frag_dir: Path) -> dict:
    report: dict = {
        "main_path": str(main),
        "frag_dir": str(frag_dir),
        "errors": [],
        "warnings": [],
        "fragments": {},
        "presets": [],
        "count": None,
        "fragment_count": None,
    }
    interpreter, problem = resolve_interpreter()
    if interpreter is None:
        report["tool_error"] = problem
        return report
    report["interpreter"] = interpreter

    if not main.is_file():
        report["tool_error"] = "mode not found: %s" % main
        return report
    if not frag_dir.is_dir():
        report["tool_error"] = "fragment directory not found: %s" % frag_dir
        return report

    sources: dict[str, str] = {}
    raw_sources: dict[str, str] = {}
    for path in sorted(frag_dir.glob("*.frag")):
        try:
            raw = path.read_text()
        except OSError as error:
            report["errors"].append({"where": path.name, "message": "unreadable: %s" % error})
            continue
        raw_sources[path.name] = raw
        sources[path.name] = strip_comments(raw)
    if not sources:
        report["tool_error"] = "no .frag files under %s" % frag_dir
        return report

    declared: dict[str, set[str]] = {}
    for name, text in sources.items():
        declared[name] = set(declared_uniforms(text))
        for message in check_fragment_source(frag_dir / name, text, raw_sources[name]):
            report["errors"].append({"where": name, "message": message})

    environment = dict(os.environ)
    prefix = "%s/?.lua" % main.parent
    environment["LUA_PATH"] = "%s;;%s" % (prefix, environment.get("LUA_PATH", ""))

    try:
        completed = subprocess.run(
            [interpreter, "-", str(main), str(FRAMES_PER_PRESET)],
            input=DRIVER,
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
            env=environment,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        report["tool_error"] = "driver could not run: %s" % error
        return report

    if completed.returncode != 0 or "SUMMARY" not in completed.stdout:
        detail = completed.stderr.strip() or completed.stdout.strip() or "no output"
        report["tool_error"] = "driver exited %d: %s" % (completed.returncode, detail[-400:])
        return report

    loaded: list[str] = []
    presets: list[dict] = []
    draws: list[dict] = []
    for line in completed.stdout.splitlines():
        parts = line.split("\t")
        kind = parts[0]
        if kind == "SHADER" and len(parts) >= 2:
            loaded.append(Path(parts[1]).name)
        elif kind == "PRESET" and len(parts) >= 8:
            presets.append({
                "index": int(parts[1]),
                "name": parts[2],
                "warp_archetype": parts[3],
                "comp_archetype": parts[4],
                "warp_params": split_names(parts[5]),
                "comp_params": split_names(parts[6]),
                "param_bridge": split_names(parts[7]),
            })
        elif kind == "DRAW" and len(parts) >= 5:
            draws.append({
                "preset": parts[1],
                "fragment": Path(parts[2]).name,
                "uniforms": split_names(parts[3]),
                "samplers": split_names(parts[4]),
            })
        elif kind == "ERR" and len(parts) >= 3:
            report["errors"].append({"where": parts[1], "message": parts[2]})
        elif kind == "SUMMARY" and len(parts) >= 3:
            report["count"] = int(parts[1])
    report["presets"] = presets
    report["fragment_count"] = len(sources)

    # Every fragment the mode loads must exist, and every fragment on disk must be
    # loaded: an unreferenced .frag is dead weight that no deploy would ship.
    for name in loaded:
        if name not in sources:
            report["errors"].append({"where": name, "message": "loaded by the mode but not present in %s" % frag_dir})
    for name in sources:
        if name not in loaded:
            report["errors"].append({"where": name, "message": "present but never loaded by the mode"})

    supplied_any: dict[str, set[str]] = {}
    supplied_by_preset: dict[str, dict[str, set[str]]] = {}
    for draw in draws:
        names = set(draw["uniforms"]) | set(draw["samplers"])
        supplied_any.setdefault(draw["fragment"], set()).update(names)
        supplied_by_preset.setdefault(draw["preset"], {}).setdefault(draw["fragment"], set()).update(names)

    # Direction 1: everything the engine hands a fragment must be declared by it.
    # An undeclared name is a dead parameter — a mistyped warp_params/param_bridge
    # key that compiles, runs, and silently does nothing.
    for fragment, names in sorted(supplied_any.items()):
        if fragment not in declared:
            continue
        dead = sorted(names - declared[fragment])
        if dead:
            owners = sorted({draw["preset"] for draw in draws if draw["fragment"] == fragment})
            report["errors"].append({
                "where": fragment,
                "message": "receives uniform(s) it does not declare: %s (supplied while drawing %s)"
                           % (", ".join(dead), ", ".join(owners)),
            })

    # Direction 2: everything a fragment declares must be supplied by the engine.
    # An unsupplied uniform reads as whatever the host leaves behind — usually 0.
    # The host's own uniforms are available on every draw even though they never
    # appear in args 5 or 6, so they count here.
    for fragment, names in sorted(declared.items()):
        available = supplied_any.get(fragment, set()) | HOST_UNIFORMS | HOST_SAMPLERS
        never = sorted(names - available)
        if never:
            report["errors"].append({
                "where": fragment,
                "message": "declares uniform(s) the engine never supplies: %s" % ", ".join(never),
            })

    # Direction 1, per preset: the preset's own declared parameters must actually
    # reach the fragment its archetype selects.
    for preset in presets:
        reached = supplied_by_preset.get(preset["name"], {})
        warp_fragment = "warp_%s.frag" % preset["warp_archetype"]
        comp_fragment = "comp_%s.frag" % preset["comp_archetype"]
        warp_reached = reached.get(warp_fragment, set())
        comp_reached = reached.get(comp_fragment, set())

        if warp_fragment not in reached:
            report["errors"].append({
                "where": preset["name"],
                "message": "warp_archetype=%s did not draw %s" % (preset["warp_archetype"], warp_fragment),
            })
        if comp_fragment not in reached:
            report["errors"].append({
                "where": preset["name"],
                "message": "comp_archetype=%s did not draw %s" % (preset["comp_archetype"], comp_fragment),
            })

        wanted = {
            "warp_params": [name for name in preset["warp_params"] if name not in NON_UNIFORM_WARP_PARAMS],
            "param_bridge": preset["param_bridge"],
            "comp_params": preset["comp_params"],
        }
        for field, names in wanted.items():
            target = comp_reached if field == "comp_params" else warp_reached
            dead = sorted(set(names) - target)
            if dead:
                report["errors"].append({
                    "where": preset["name"],
                    "message": "%s name(s) never reach a uniform: %s" % (field, ", ".join(dead)),
                })

    # A loaded fragment no preset selects is legal while an archetype is being
    # built, so this is a warning rather than a failure.
    drawn = {draw["fragment"] for draw in draws}
    for name in sorted(sources):
        if name not in drawn:
            report["warnings"].append({
                "where": name,
                "message": "loaded but no preset selects it; an archetype without a preset yet",
            })

    # A fragment that samples nothing is unusual but legitimate (a procedural
    # field), so it is reported for the eye rather than failed.
    for name, text in sorted(sources.items()):
        if not re.search(r"\buniform\s+sampler2D\b", text):
            report["warnings"].append({
                "where": name,
                "message": "declares no sampler: procedural only, no feedback or blur input",
            })
        if name.startswith("warp_"):
            archetype_field, archetype = "warp_archetype", name[len("warp_"):-len(".frag")]
        elif name.startswith("comp_"):
            archetype_field, archetype = "comp_archetype", name[len("comp_"):-len(".frag")]
        else:
            continue  # a helper fragment (blur1) backs no archetype
        if not any(preset[archetype_field] == archetype for preset in presets):
            report["warnings"].append({
                "where": name,
                "message": "no preset in the catalog uses the %s archetype" % archetype,
            })

    report["fragments"] = {
        name: {"declared": sorted(declared[name]), "supplied": sorted(supplied_any.get(name, set()))}
        for name in sorted(sources)
    }
    report["drawn"] = sorted(drawn)
    report["loaded"] = loaded
    return report


def render(report: dict, expected_fragments: int | None) -> tuple[str, int]:
    if "tool_error" in report:
        return "check_fragments: ERROR — %s\n" % report["tool_error"], 2

    lines = [
        "mode:       %s" % report["main_path"],
        "fragments:  %s" % report["frag_dir"],
        "checker:    %s (real mode run against a recording engine stub)" % report["interpreter"],
        "catalog:    %d preset(s)" % (report["count"] or 0),
        "fragments:  %d" % (report["fragment_count"] or 0),
        "",
    ]

    count_problem = None
    if expected_fragments is not None and report["fragment_count"] != expected_fragments:
        count_problem = "expected %d fragment(s), found %d" % (expected_fragments, report["fragment_count"])

    if report["errors"]:
        lines.append("FAIL — %d problem(s)" % len(report["errors"]))
        for item in report["errors"]:
            lines.append("  - %s: %s" % (item["where"], item["message"]))
    if count_problem:
        lines.append("FAIL — %s" % count_problem)
    if report["warnings"]:
        if not report["errors"] and not count_problem:
            lines.append("")
        lines.append("WARN — %d note(s) (not fatal):" % len(report["warnings"]))
        for item in report["warnings"]:
            lines.append("  - %s: %s" % (item["where"], item["message"]))
    if not report["errors"] and not count_problem:
        lines.append("")
        lines.append(
            "PASS — %d fragment(s) over %d preset(s): every fragment honours the host contract "
            "(no #version, precision, `varying vec2 uv`, one main), every uniform the engine "
            "supplies is declared and every declared uniform is supplied, and each preset's "
            "warp_params/comp_params/param_bridge reach the fragment its archetype selects."
            % (report["fragment_count"] or 0, report["count"] or 0)
        )
    return "\n".join(lines) + "\n", 1 if (report["errors"] or count_problem) else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Validate the milkdrop fragment contract.")
    parser.add_argument("--main", default=DEFAULT_MAIN, type=Path)
    parser.add_argument("--frag-dir", default=DEFAULT_FRAG_DIR, type=Path)
    parser.add_argument("--expect-fragments", type=int, default=None,
                        help="assert the library holds exactly N fragments (opt-in)")
    parser.add_argument("--json", action="store_true", help="emit the report as JSON")
    args = parser.parse_args(argv)

    report = validate(args.main, args.frag_dir)
    text, code = render(report, args.expect_fragments)
    if args.json:
        payload = dict(report)
        payload["expected_fragments"] = args.expect_fragments
        payload["exit_code"] = code
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        sys.stdout.write(text)
    return code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))