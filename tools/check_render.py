#!/usr/bin/env python3
"""Render-contract validator: every fragment, on a real GLES2 driver.

`tools/check_fragments.py` proves the uniform *traffic* between the mode and its
fragments. It cannot tell you whether a fragment renders: a shader can honour
every name the gate checks and still be rejected by the driver, sample the wrong
region, or write a flat frame. This closes that gap by compiling and running each
fragment for real, offscreen, through `tools/gl_render.c`.

    python3 tools/check_render.py             # every case
    python3 tools/check_render.py --json
    python3 tools/check_render.py --self-test # prove the checks fire

What it checks, per fragment:

* **renders** — the driver compiles and links it, no GL error, and the frame is
  not degenerate (not flat, not black, not blown out).
* **identity** — with parameters set to a fragment's neutral configuration the
  output must be the input texture, byte for byte. This is the regression test
  for the warp coordinate defects: `warp_default` with zoom 1 / zoomexp 1 used to
  return the frame shifted half a screen down.
* **differs** — with its archetype's real parameters the fragment must actually
  change the frame.
* **periodic** — the kaleidoscope's N-fold angular symmetry, measured on the
  rendered frame. The period must move when `sectors` does.

The uniform values are **observed from the running mode**, not restated here: the
driver loads `main.lua` against a recording stub and reports what the engine
actually hands each fragment. A table of values in this file would be a second
statement of the contract, free to drift from the mode.

Requires a Lua interpreter (as the fragment gate does), a C compiler, and
EGL/GLES2 development files. It exits 2 rather than skipping if any is missing,
for the same reason the other gates do: a validator that silently checks less
than it claims is worse than one that refuses to run.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "tools" / "gl_render.c"
MAIN = ROOT / "milkdrop" / "main.lua"
FRAG_DIR = ROOT / "milkdrop" / "frag"

INTERPRETER_PREFERENCES = ("luajit", "lua", "lua5.1", "lua5.3", "lua5.4")
COMPILER_PREFERENCES = ("cc", "gcc", "clang")
TIMEOUT_SECONDS = 120

RENDER_W, RENDER_H = 320, 180     # 16:9, so aspect handling is exercised
IDENTITY_TOLERANCE = 1            # 8-bit rounding across the render round trip
DIFFERS_THRESHOLD = 8             # max channel delta that counts as "it did something"
PERIODIC_MATCH = 2                # max channel delta for a periodic pair
PERIODIC_CONTROL = 5              # min channel delta for the control pair
MIN_STDDEV = 2.0                  # below this the frame is flat, whatever else it is
MIN_RANGE = 8                     # max channel value; a black frame is a broken one

# The engine's own uniform supply, observed from a real run of the mode. Emitted
# as tab-separated records for the same reason the fragment gate's driver is.
DRIVER = r"""
local main_path = arg[1]
local frames = tonumber(arg[2]) or 2
local current = "?"

local function say(...) io.write(table.concat({...}, "\t"), "\n") end

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

-- Scalars and vectors are reported; the host fills u_resolution and texel
-- itself, and the harness sets those from the render size. Vectors arrive as
-- comma-separated lists, the way the mode passes blur_w = {7.8, 6.4, 3.1, 1.0}.
local function scalars(t)
  local out = {}
  if type(t) == "table" then
    for k, v in pairs(t) do
      if type(v) == "number" and v == v then
        out[#out + 1] = k .. "=" .. tostring(v)
      elseif type(v) == "table" then
        local parts = {}
        for i = 1, #v do
          if type(v[i]) == "number" and v[i] == v[i] then parts[#parts + 1] = tostring(v[i]) end
        end
        if #parts > 0 then out[#out + 1] = k .. "=" .. table.concat(parts, ",") end
      end
    end
  end
  table.sort(out)
  return table.concat(out, ",")
end
local function names(t)
  local out = {}
  if type(t) == "table" then
    for k in pairs(t) do out[#out + 1] = tostring(k) end
  end
  table.sort(out)
  return table.concat(out, ",")
end

eyesy.draw_shader = function(handle, _t, _e, _c, uniforms, samplers)
  say("DRAW", current, handle.path, scalars(uniforms), names(samplers))
end
_G.eyesy = eyesy

local ok, mod = pcall(dofile, main_path)
if not ok then say("ERR", "main.lua", tostring(mod):gsub("[\t\n]", " ")); say("SUMMARY", "0"); return end
local setup_ok, setup_err = pcall(mod.setup, { width = 1280, height = 720 })
if not setup_ok then say("ERR", "setup", tostring(setup_err):gsub("[\t\n]", " ")); say("SUMMARY", "0"); return end

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
    audio = { left = left, right = right, fft_left = fft, fft_right = fft,
              bands = { 0.30, 0.25, 0.20 } },
  }
end

local catalog_ok, P = pcall(require, "presets/presets")
if not catalog_ok or type(P) ~= "table" then say("ERR", "presets/presets", "not a table"); say("SUMMARY", "0"); return end

for i = 1, #P do
  current = tostring(P[i].name)
  for f = 1, frames do
    local drew, derr = pcall(mod.draw, make_ctx(i, (i - 1) * frames + f))
    if not drew then say("ERR", current, tostring(derr):gsub("[\t\n]", " ")); break end
  end
end
say("SUMMARY", tostring(#P))
"""


# Each case: fragment, uniform overrides, and the invariants to assert. Base
# values come from the engine; overrides are what makes a configuration neutral
# or makes one axis unambiguous.
CASES: list[dict] = [
    # the warp chain: identity is the regression test for the coordinate defects
    {"frag": "warp_default", "checks": ["renders"]},
    {"frag": "warp_default", "label": "identity", "checks": ["identity"],
     "over": {"zoom": 1.0, "zoomexp": 1.0, "rot": 0.0, "warp": 0.0,
              "dx": 0.0, "dy": 0.0, "sx": 1.0, "sy": 1.0, "decay": 1.0}},
    {"frag": "warp_sphere", "checks": ["renders"]},
    {"frag": "warp_sphere", "label": "identity", "checks": ["identity"],
     "over": {"zoom": 1.0, "zoomexp": 1.0, "rot": 0.0, "warp": 0.0, "sphere": 0.0,
              "dx": 0.0, "dy": 0.0, "sx": 1.0, "sy": 1.0, "decay": 1.0}},
    {"frag": "warp_kaleido", "checks": ["renders", "differs"]},
    {"frag": "warp_kaleido", "label": "6-fold period", "checks": ["periodic"],
     "over": {"sectors": 6, "kaleido_angle": 0.0, "rot": 0.0, "dx": 0.0, "dy": 0.0}, "period": 6},
    {"frag": "warp_blur", "checks": ["renders", "differs"]},
    {"frag": "warp_blur", "label": "sharp only", "checks": ["identity"],
     "over": {"zoom": 1.0, "zoomexp": 1.0, "rot": 0.0, "warp": 0.0, "blur_warp": 0.0,
              "dx": 0.0, "dy": 0.0, "sx": 1.0, "sy": 1.0, "decay": 1.0}},
    {"frag": "warp_diffuse", "checks": ["renders", "differs"]},

    # the composites
    {"frag": "comp_default", "checks": ["renders"]},
    {"frag": "comp_default", "label": "neutral tone chain", "checks": ["identity"],
     "over": {"gamma": 1.0, "bright": 1.0, "contrast": 1.0, "saturation": 1.0,
              "hue": 0.0, "echo": 0.0}},
    {"frag": "comp_softmax", "checks": ["renders", "differs"]},
    {"frag": "comp_softmax", "label": "mix 0", "checks": ["identity"],
     "over": {"soft_mix": 0.0, "gamma": 1.0, "bright": 1.0, "contrast": 1.0,
              "saturation": 1.0, "hue": 0.0, "echo": 0.0}},
    {"frag": "comp_plasma", "checks": ["renders", "differs"]},
    {"frag": "comp_rotoblur", "checks": ["renders", "differs"]},
    {"frag": "comp_rotoblur", "label": "no sweep", "checks": ["identity"],
     "over": {"blur_rot": 0.0, "blur_rad": 0.0, "blur_mix": 1.0, "gamma": 1.0,
              "bright": 1.0, "contrast": 1.0, "saturation": 1.0, "hue": 0.0, "echo": 0.0}},
    {"frag": "blur1", "checks": ["renders", "differs"], "over": {"blur_scale": 1.0, "blur_bias": 0.0}},
]

# Cases that only exist to prove the gate's own checks fire.
SELF_TEST = {
    "degenerate": (
        "precision highp float;\n"
        "varying vec2 uv;\n"
        "uniform sampler2D prev;\n"
        "void main() { gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0); }\n"
    ),
    "flat-out": (
        "precision highp float;\n"
        "varying vec2 uv;\n"
        "uniform sampler2D prev;\n"
        "void main() { gl_FragColor = vec4(0.5, 0.5, 0.5, 1.0); }\n"
    ),
    "won't-compile": (
        "precision highp float;\n"
        "varying vec2 uv;\n"
        "void main() { this is not glsl }\n"
    ),
}


# ------------------------------------------------------------------ toolchain

def resolve_interpreter() -> tuple[str | None, str | None]:
    override = os.environ.get("CHECK_RENDER_LUA")
    if override:
        found = shutil.which(override) or (override if os.path.exists(override) else None)
        if not found:
            return None, "$CHECK_RENDER_LUA=%s is not executable" % override
        return found, None
    for candidate in INTERPRETER_PREFERENCES:
        found = shutil.which(candidate)
        if found:
            return found, None
    return None, "no Lua interpreter on PATH (tried %s)" % ", ".join(INTERPRETER_PREFERENCES)


def resolve_compiler() -> tuple[str | None, str | None]:
    override = os.environ.get("CHECK_RENDER_CC")
    if override:
        found = shutil.which(override) or (override if os.path.exists(override) else None)
        if not found:
            return None, "$CHECK_RENDER_CC=%s is not executable" % override
    else:
        found = None
        for candidate in COMPILER_PREFERENCES:
            found = shutil.which(candidate)
            if found:
                break
        if not found:
            return None, "no C compiler on PATH (tried %s)" % ", ".join(COMPILER_PREFERENCES)
    for header in ("EGL/egl.h", "GLES2/gl2.h"):
        if not any((Path(p) / header).exists() for p in ("/usr/include", "/usr/local/include")):
            return None, "missing %s (need EGL and GLES2 development files)" % header
    return found, None


def build(compiler: str) -> tuple[Path | None, str | None]:
    """Compile the harness into a cache keyed by the source, so it rebuilds only
    when the source changes."""
    source = HARNESS.read_bytes()
    digest = hashlib.sha256(source).hexdigest()[:16]
    cache = Path(tempfile.gettempdir()) / "omp-milkdrop-render" / digest
    binary = cache / "gl_render"
    if binary.exists():
        return binary, None
    cache.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        [compiler, "-O1", "-std=c99", "-o", str(binary), str(HARNESS), "-lEGL", "-lGLESv2", "-lm"],
        capture_output=True, text=True,
    )
    if proc.returncode != 0 or not binary.exists():
        return None, "harness did not build: %s" % (proc.stderr.strip()[-400:] or "no output")
    return binary, None


# ------------------------------------------------------------------- rendering

def read_ppm(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    if not data.startswith(b"P6"):
        raise ValueError("%s is not a P6 PPM" % path)
    parts = data.split(b"\n", 3)
    width, height = (int(x) for x in parts[1].split())
    return width, height, parts[3]


def channel_delta(a: bytes, b: bytes) -> tuple[int, float]:
    """Max and mean absolute channel difference between two frames."""
    if len(a) != len(b):
        raise ValueError("frame sizes differ: %d vs %d" % (len(a), len(b)))
    worst = 0
    total = 0
    for i in range(0, len(a), 3):
        for c in range(3):
            d = a[i + c] - b[i + c]
            if d < 0:
                d = -d
            if d > worst:
                worst = d
            total += d
    return worst, total / (len(a) / 3 * 3)


def render(binary: Path, frag: Path, uniforms: dict[str, float], work: Path,
           tag: str) -> dict:
    out = work / ("out-%s.ppm" % tag)
    inp = work / ("in-%s.ppm" % tag)
    env = dict(os.environ)
    env["GL_RENDER_DUMP_INPUT"] = str(inp)
    args = [str(binary), str(frag), str(out)] + ["%s=%s" % (k, v) for k, v in sorted(uniforms.items())]
    proc = subprocess.run(args, capture_output=True, text=True, env=env, timeout=TIMEOUT_SECONDS)

    result: dict = {"exit": proc.returncode, "stdout": proc.stdout, "stderr": proc.stderr}
    if proc.returncode != 0:
        result["error"] = (proc.stderr.strip() or "exited %d" % proc.returncode)[-400:]
        return result
    for line in proc.stdout.splitlines():
        parts = line.split("\t")
        if parts[0] in ("GL_VERSION", "GL_RENDERER") and len(parts) >= 2:
            result[parts[0]] = parts[1]
        elif parts[0] in ("UNIFORMS_SET", "SAMPLERS_SET", "UNIFORMS_MISSING", "GL_ERROR") and len(parts) >= 2:
            result[parts[0]] = int(parts[1])
        elif parts[0] == "STATS" and len(parts) >= 5:
            result["stats"] = {p.split("=")[0]: float(p.split("=")[1]) for p in parts[1:]}
        elif parts[0] == "INPUT_STATS" and len(parts) >= 5:
            result["input_stats"] = {p.split("=")[0]: float(p.split("=")[1]) for p in parts[1:]}
    try:
        result["frame"] = read_ppm(out)[2]
        result["input"] = read_ppm(inp)[2]
    except (OSError, ValueError) as error:
        result["error"] = str(error)
    return result


def periodic_deltas(frame: bytes, width: int, height: int, n: int) -> tuple[float, float]:
    """Angular periodicity of the rendered frame: (period mean, control mean).

    The kaleidoscope folds the sampling angle into one sector, so the frame
    repeats every 2*pi/n about the screen centre. Measured straight off the
    frame, with no model of the fragment. Means rather than maxima: the built-in
    input has sharp edges, and nearest-pixel sampling at two different angles
    lands on different pixels at those edges, so a maximum would measure the edge
    rather than the symmetry.
    """
    cx, cy = width / 2.0, height / 2.0

    def at(degrees: float, radius: float) -> tuple[int, int, int]:
        rad = math.radians(degrees)
        px = radius * height * math.cos(rad)          # p space is height units
        py = radius * height * math.sin(rad)
        x = min(max(int(round(cx + px)), 0), width - 1)
        y = min(max(int(round(cy - py)), 0), height - 1)
        i = (y * width + x) * 3
        return frame[i], frame[i + 1], frame[i + 2]

    def delta(a: float, b: float, r: float) -> float:
        pa, pb = at(a, r), at(b, r)
        return max(abs(pa[c] - pb[c]) for c in range(3))

    radii = (0.12, 0.20, 0.28)
    period = sum(delta(a, a + 360.0 / n, r) for r in radii for a in range(0, 360, 2))
    control = sum(delta(a, a + 17.0, r) for r in radii for a in range(0, 360, 2))
    pairs = len(radii) * len(range(0, 360, 2))
    return period / pairs, control / pairs


# ------------------------------------------------------------------ the cases

def parse_uniforms(record: str) -> dict[str, str]:
    """`a=1,b=2,c=3.5,d=4` -> values. A part carrying `=` starts a key; parts
    without one extend the previous value, which is how a vector (blur_w =
    7.8,6.4,3.1,1.0) survives the flat record format."""
    out: dict[str, str] = {}
    key = None
    for part in record.split(","):
        if not part:
            continue
        if "=" in part:
            key, value = part.split("=", 1)
            out[key] = value
        elif key is not None:
            out[key] += "," + part
    return out


def engine_uniforms(interpreter: str) -> tuple[dict[str, dict], str | None]:
    """What the engine actually hands each fragment, from a real run."""
    env = dict(os.environ)
    env["LUA_PATH"] = "%s/?.lua;;%s" % (MAIN.parent, env.get("LUA_PATH", ""))
    try:
        proc = subprocess.run([interpreter, "-", str(MAIN), "2"], input=DRIVER,
                              capture_output=True, text=True, env=env, timeout=TIMEOUT_SECONDS)
    except (OSError, subprocess.TimeoutExpired) as error:
        return {}, "driver could not run: %s" % error
    if proc.returncode != 0 or "SUMMARY" not in proc.stdout:
        return {}, "driver exited %d: %s" % (proc.returncode, (proc.stderr or proc.stdout).strip()[-400:])

    observed: dict[str, dict] = {}
    for line in proc.stdout.splitlines():
        parts = line.split("\t")
        if parts[0] != "DRAW" or len(parts) < 5:
            continue
        name = Path(parts[2]).name
        if name in observed:
            continue                      # first preset that uses it: deterministic
        observed[name] = {"uniforms": parse_uniforms(parts[3]),
                          "samplers": [s for s in parts[4].split(",") if s]}
    return observed, None


def run_case(binary: Path, case: dict, observed: dict, work: Path) -> dict:
    frag_name = case["frag"] + ".frag"
    label = case.get("label", "")
    tag = (case["frag"] + ("-" + label.replace(" ", "-") if label else ""))
    frag = FRAG_DIR / frag_name
    if not frag.is_file():
        return {"where": tag, "ok": False, "detail": "fragment not found"}
    if frag_name not in observed:
        return {"where": tag, "ok": False, "detail": "the mode never draws this fragment"}

    uniforms = dict(observed[frag_name]["uniforms"])
    uniforms.update(case.get("over", {}))
    want = list(case["checks"])

    first = render(binary, frag, uniforms, work, tag)
    if first.get("error"):
        return {"where": tag, "ok": False, "detail": first["error"]}

    problems = []
    if first.get("GL_ERROR"):
        problems.append("GL error 0x%x" % first["GL_ERROR"])
    if first.get("UNIFORMS_MISSING"):
        problems.append("%d uniform(s) left at zero" % first["UNIFORMS_MISSING"])

    if "renders" in want or "differs" in want or "identity" in want:
        stats = first.get("stats", {})
        if stats.get("stddev", 0.0) < MIN_STDDEV:
            problems.append("frame is flat (stddev %.2f)" % stats.get("stddev", 0.0))
        if stats.get("max", 0.0) < MIN_RANGE:
            problems.append("frame is black (max %.0f)" % stats.get("max", 0.0))

    if "differs" in want:
        worst, _ = channel_delta(first["frame"], first["input"])
        if worst < DIFFERS_THRESHOLD:
            problems.append("does not change the frame (max delta %d)" % worst)

    if "identity" in want:
        worst, _ = channel_delta(first["frame"], first["input"])
        if worst > IDENTITY_TOLERANCE:
            problems.append("not an identity: max delta %d/255" % worst)

    if "periodic" in want:
        n = int(case.get("period", 0))
        period, control = periodic_deltas(first["frame"], RENDER_W, RENDER_H, n)
        # the periodic pairs must agree, and must agree *much better* than pairs
        # that are not a period apart — otherwise the check proves nothing
        if period > max(PERIODIC_MATCH, control / 3.0):
            problems.append("not %d-fold periodic: mean delta %.1f/255 vs control %.1f"
                            % (n, period, control))
        if control < PERIODIC_CONTROL:
            problems.append("control pairs differ by only %.1f/255: the test is vacuous" % control)

    detail = "ok"
    if problems:
        detail = "; ".join(problems)
    return {"where": tag, "ok": not problems, "detail": detail,
            "stats": first.get("stats", {}), "gl": first.get("GL_RENDERER", "?")}


def self_test(binary: Path, work: Path) -> int:
    """Prove the checks fire: every case here must be rejected."""
    print("self-test: each of these must FAIL")
    failures = 0
    for name, source in SELF_TEST.items():
        frag = work / ("selftest-%s.frag" % name)
        frag.write_text(source)
        case = {"frag": name, "checks": ["renders"]}
        first = render(binary, frag, {"prev": 0.0}, work, "selftest-" + name)
        rejected = bool(first.get("error")) or first.get("stats", {}).get("stddev", 0.0) < MIN_STDDEV
        if rejected:
            why = "compile/link rejected" if first.get("error") else "flat frame"
        else:
            why = "ACCEPTED, which is the bug"
            failures += 1
        print("  %-16s %s" % (name, why))
    print("")
    print("%d/%d self-test cases rejected as expected" % (len(SELF_TEST) - failures, len(SELF_TEST)))
    return 1 if failures else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--json", action="store_true", help="emit the report as JSON")
    parser.add_argument("--self-test", action="store_true",
                        help="prove the gate's checks fire, then exit")
    args = parser.parse_args(argv)

    interpreter, problem = resolve_interpreter()
    if not interpreter:
        print("check_render: ERROR — %s" % problem)
        return 2
    compiler, problem = resolve_compiler()
    if not compiler:
        print("check_render: ERROR — %s" % problem)
        return 2
    binary, problem = build(compiler)
    if not binary:
        print("check_render: ERROR — %s" % problem)
        return 2

    work = Path(tempfile.mkdtemp(prefix="render-check-"))
    try:
        if args.self_test:
            return self_test(binary, work)

        observed, problem = engine_uniforms(interpreter)
        if problem:
            print("check_render: ERROR — %s" % problem)
            return 2

        results = [run_case(binary, case, observed, work) for case in CASES]
        observed_fragments = sorted(observed)
        declared = sorted(p.name for p in FRAG_DIR.glob("*.frag"))
        unrendered = [name for name in declared if name not in observed_fragments]

        report = {
            "interpreter": interpreter,
            "compiler": compiler,
            "harness": str(binary),
            "fragments": len(declared),
            "observed": len(observed_fragments),
            "cases": len(results),
            "results": results,
            "unrendered": unrendered,
            "errors": [r for r in results if not r["ok"]],
        }
        if args.json:
            print(json.dumps(report, indent=2))
            return 1 if report["errors"] else 0

        lines = [
            "harness:   %s" % binary,
            "checker:   %s + %s (real EGL/GLES2 render, %dx%d)"
            % (interpreter, Path(binary).name, RENDER_W, RENDER_H),
            "fragments: %d declared, %d drawn by the mode" % (len(declared), len(observed_fragments)),
            ""
        ]
        for result in results:
            note = ("stddev %.1f" % result.get("stats", {}).get("stddev", 0.0)) if result["ok"] else result["detail"]
            lines.append("  %-32s %s" % (result["where"], note))
        if unrendered:
            lines.append("")
            lines.append("FAIL — never drawn by the mode: %s" % ", ".join(unrendered))
        if report["errors"]:
            lines.append("")
            lines.append("FAIL — %d case(s)" % len(report["errors"]))
        else:
            lines.append("")
            lines.append(
                "PASS — %d case(s) over %d fragment(s) on %s: every fragment compiles, links and "
                "renders non-degenerately, every neutral configuration is a byte-exact identity, "
                "every archetype changes the frame, and the kaleidoscope's period tracks `sectors`."
                % (len(results), len(observed_fragments), results[0].get("gl", "the driver")))
        print("\n".join(lines) + "\n")
        return 1 if (report["errors"] or unrendered) else 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))