#!/usr/bin/env python3
"""Negative suite for tools/check_fragments.py.

A gate that only ever says PASS is worth nothing, so every check the fragment
gate claims is made to fire here: each case mutates a throwaway copy of
``milkdrop/`` and asserts that the gate exits non-zero naming the culprit. The
first case runs the copy unmutated and asserts the gate still passes, so a gate
that fails everything cannot pass this suite either.

    python3 tools/check_fragments_negatives.py            # run every case
    python3 tools/check_fragments_negatives.py --list     # show case names
    python3 tools/check_fragments_negatives.py -v         # show all findings

Exit codes: 0 every case behaved; 1 a case did not; 2 the suite could not run
(no Lua interpreter, or the mode is missing). The gate itself exits 2 in the
same situation, and that is one of the cases below.

The mode is copied per case rather than mutated in place: the gate must be shown
to fail on a *broken* copy, never on the working tree.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GATE = ROOT / "tools" / "check_fragments.py"
MODE_SOURCE = ROOT / "milkdrop"

# (name, mutate, expected exit, substring that must appear in a finding)
CASES: list[tuple[str, str, int, str | None]] = []


def case(name: str, expect_exit: int = 1, expect: str | None = None):
    def register(fn):
        CASES.append((name, fn.__name__, expect_exit, expect))
        setattr(sys.modules[__name__], fn.__name__, fn)
        return fn

    return register


def frag(mode: Path, name: str) -> Path:
    return mode / "frag" / name


def presets(mode: Path) -> Path:
    return mode / "presets" / "presets.lua"


def swap(path: Path, old: str, new: str) -> None:
    """Replace ``old`` once, failing loudly if the anchor has moved."""
    text = path.read_text()
    out = text.replace(old, new, 1)
    if out == text:
        raise AssertionError("anchor not found in %s: %r" % (path.name, old))
    path.write_text(out)


@case("clean", expect_exit=0)
def clean(mode: Path) -> None:
    """Unmutated copy: the gate must pass. Without this the suite proves nothing."""


@case("version-directive", expect="#version")
def version_directive(mode: Path) -> None:
    path = frag(mode, "warp_default.frag")
    path.write_text("#version 100\n" + path.read_text())


@case("missing-varying", expect="varying vec2 uv")
def missing_varying(mode: Path) -> None:
    swap(frag(mode, "comp_default.frag"), "varying vec2 uv;", "")


@case("warp-without-decay", expect="neither decays nor declares")
def warp_without_decay(mode: Path) -> None:
    """The bound check must test *use*, not the declaration.

    The uniform stays declared; only the arithmetic term goes. A gate that
    searches the whole source passes this, which is how the original bug hid.
    """
    swap(frag(mode, "warp_sphere.frag"), ".rgb * decay;", ".rgb;")


@case("warp-bound-without-clamp", expect="never calls clamp()")
def warp_bound_without_clamp(mode: Path) -> None:
    """Claiming the bounded-warp exemption without a clamp is not enough."""
    path = frag(mode, "warp_default.frag")
    swap(path, ".rgb * decay;", ".rgb;")
    path.write_text("// warp-bound: claimed but never enforced\n" + path.read_text())


@case("warp-bound-with-clamp", expect_exit=0)
def warp_bound_with_clamp(mode: Path) -> None:
    """The exemption must actually work, not just fail correctly.

    Same mutation as above plus a real clamp: the gate must accept it, so the
    rule cannot be satisfied only by decaying.
    """
    path = frag(mode, "warp_default.frag")
    swap(path, ".rgb * decay;", ".rgb;")
    swap(path, "gl_FragColor = vec4(col, 1.0);", "gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);")
    path.write_text("// warp-bound: the step is clamped to [0,1]\n" + path.read_text())


@case("missing-precision", expect="precision")
def missing_precision(mode: Path) -> None:
    swap(frag(mode, "warp_default.frag"), "precision highp float;", "")


@case("two-main-functions", expect="expected exactly 1")
def two_main_functions(mode: Path) -> None:
    path = frag(mode, "blur1.frag")
    path.write_text(path.read_text() + "\nvoid main() { gl_FragColor = vec4(0.0); }\n")


@case("duplicate-uniform", expect="duplicate uniform")
def duplicate_uniform(mode: Path) -> None:
    swap(frag(mode, "warp_default.frag"), "uniform float zoom;",
         "uniform float zoom;\nuniform float zoom;")


@case("unsupplied-uniform", expect="never supplies: bogus")
def unsupplied_uniform(mode: Path) -> None:
    swap(frag(mode, "comp_default.frag"), "uniform float echo;",
         "uniform float echo;\nuniform float bogus;")


@case("unsupplied-sampler", expect="never supplies: ghost")
def unsupplied_sampler(mode: Path) -> None:
    swap(frag(mode, "comp_default.frag"), "uniform float echo;",
         "uniform float echo;\nuniform sampler2D ghost;")


@case("missing-fragment-file", expect="not present in")
def missing_fragment_file(mode: Path) -> None:
    frag(mode, "warp_sphere.frag").unlink()


@case("orphan-fragment", expect="never loaded by the mode")
def orphan_fragment(mode: Path) -> None:
    shutil.copy(frag(mode, "warp_default.frag"), frag(mode, "warp_unused.frag"))


@case("preset-param-typo", expect="does not declare: sector")
def preset_param_typo(mode: Path) -> None:
    """warp_params pass straight through as uniforms, so a misspelt `sectors`
    on kaleido-fold reaches warp_kaleido undeclared and dies there."""
    anchor = '    warp_archetype = "kaleido",\n    comp_archetype = "default",\n    warp_params = {},'
    swap(presets(mode), anchor, anchor.replace("warp_params = {}", "warp_params = { sector = 6 }"))


@case("comp-params-on-default-comp", expect="never reach a uniform: soft_mix")
def comp_params_on_default_comp(mode: Path) -> None:
    """comp_params the selected archetype ignores entirely (a softmax knob on
    the first default-comp preset)."""
    anchor = ('    comp_archetype = "default",\n'
              '    warp_params = {},\n'
              '    comp_params = {},')
    swap(presets(mode), anchor, anchor.replace("comp_params = {}", "comp_params = { soft_mix = 0.5 }"))


@case("expect-fragments-mismatch", expect="expected 99 fragment(s)")
def expect_fragments_mismatch(mode: Path) -> None:
    """The opt-in size assertion is checked, not decorative."""
    return  # handled through extra args below


EXTRA_ARGS = {"expect-fragments-mismatch": ["--expect-fragments", "99"]}

# Handled outside the copy loop: the gate must refuse to run without an
# interpreter rather than silently checking less than it claims.
NO_INTERPRETER_CASE = "no-interpreter"


def findings(stdout: str) -> list[str]:
    return [line.strip()[2:] for line in stdout.splitlines() if line.strip().startswith("- ")]


def run_case(name: str, mutator: str, expect_exit: int, expect: str | None,
             tmp: Path, verbose: bool) -> tuple[bool, str]:
    mode = tmp / name / "milkdrop"
    shutil.copytree(MODE_SOURCE, mode)
    getattr(sys.modules[__name__], mutator)(mode)

    proc = subprocess.run(
        [sys.executable, str(GATE),
         "--main", str(mode / "main.lua"), "--frag-dir", str(mode / "frag"),
         *EXTRA_ARGS.get(name, [])],
        capture_output=True, text=True,
    )
    lines = findings(proc.stdout)
    if expect is None:
        ok = proc.returncode == expect_exit and not lines
        detail = "no findings" if ok else "unexpected findings: %s" % lines[:2]
    else:
        # Match against the whole report, not just the "- " finding lines: the
        # --expect-fragments mismatch is reported as a FAIL line of its own.
        matched = [line.strip() for line in proc.stdout.splitlines() if expect in line]
        ok = proc.returncode == expect_exit and bool(matched)
        detail = (matched[0] if matched else
                  "exit %d, findings %s" % (proc.returncode, lines[:2] or "[]"))
    if verbose and not ok:
        detail += "\n" + proc.stdout + proc.stderr
    return ok, detail


def run(tmp: Path, verbose: bool) -> int:
    if not GATE.is_file():
        print("suite: ERROR — %s not found" % GATE)
        return 2
    if not MODE_SOURCE.is_dir():
        print("suite: ERROR — %s not found" % MODE_SOURCE)
        return 2

    results = []
    for name, mutator, expect_exit, expect in CASES:
        results.append((name, run_case(name, mutator, expect_exit, expect, tmp, verbose)))

    # No interpreter: exit 2, and say so, rather than passing vacuously.
    env = dict(os.environ, CHECK_FRAGMENTS_LUA="/nonexistent/luajit")
    proc = subprocess.run(
        [sys.executable, str(GATE), "--main", str(MODE_SOURCE / "main.lua"),
         "--frag-dir", str(MODE_SOURCE / "frag")],
        capture_output=True, text=True, env=env,
    )
    output = proc.stdout + proc.stderr
    refusal_named = "is not executable" in output or "no Lua interpreter" in output
    ok = proc.returncode == 2 and refusal_named
    results.append((NO_INTERPRETER_CASE,
                    (ok, "exit %d, names the interpreter problem" % proc.returncode if ok else
                     "expected exit 2 naming the missing interpreter (got exit %d: %s)"
                     % (proc.returncode, output.strip()[-200:]))))

    width = max(len(name) for name, _ in results)
    for name, (ok, detail) in results:
        print("%-*s %s  %s" % (width, name, "ok  " if ok else "FAIL", detail if not ok or verbose else ""))

    bad = [name for name, (ok, _) in results if not ok]
    print()
    print("%d/%d cases behaved as expected" % (len(results) - len(bad), len(results)))
    if bad:
        print("MISBEHAVED: %s" % ", ".join(bad))
        return 1
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--list", action="store_true", help="list case names and exit")
    parser.add_argument("-v", "--verbose", action="store_true", help="show every result, not just failures")
    args = parser.parse_args(argv)

    if args.list:
        for name, _, expect_exit, expect in CASES:
            print("%-28s exit %d  %s" % (name, expect_exit, expect or "(no finding)"))
        print("%-28s exit 2  the gate refuses without an interpreter" % NO_INTERPRETER_CASE)
        return 0

    tmp = Path(tempfile.mkdtemp(prefix="frag-negatives-"))
    try:
        return run(tmp, args.verbose)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))