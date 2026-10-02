# Preset contract

What `tools/check_presets.py` enforces on `milkdrop/presets/presets.lua`, and what
it deliberately does not. Run it before any preset leaves a branch. The other half
of the engine — the fragments, and the uniforms the mode hands them — is
`tools/check_fragments.py` (`docs/FRAGMENT-CONTRACT.md`).

```sh
python3 tools/check_presets.py                        # the catalog in place
python3 tools/check_presets.py --expect-count 24      # also assert the size
python3 tools/check_presets.py --json                 # machine-readable report
```

Exit codes: `0` pass, `1` a preset broke the contract, `2` the tool could not run.

## Why this exists

The repository had no gate of its own. Its only verification was the evaluator
test suite, which then lived in the engine repository (it is now
`tests/test_milkdrop_evaluator.py` here), so a standing port loop had nothing to
run on the repo it was changing. A port that "looks right" but fails to
compile is caught here instead of on the device.

## How it checks

The validator drives **the engine's own evaluator** — it does not re-implement it.
A Python driver runs `lib/evaluator.lua` against the real catalog and reports
tab-separated records. Checks are therefore authoritative rather than a second
opinion that can drift from the engine.

**Fails on:**

| Check | Detail |
| --- | --- |
| Catalog shape | `presets.lua` returns a table; each entry is a table |
| Required keys | `name`, `per_frame_init`, `per_frame`, `per_pixel`, `warp_archetype`, `comp_archetype`, `warp_params`, `comp_params`, `wave_mode`, `wave_a`, `waves`, `shapes`, `decay`, `q` |
| Key types | equation fields are strings; `q` is a table; `decay` is a finite number; `param_bridge`, if present, maps strings to strings; `particles`, if present, is a table whose `count`/`speed`/`size` are finite numbers and whose `tints` is a table |
| Archetypes | `warp_archetype` ∈ {`default`, `sphere`, `kaleido`, `blur`, `diffuse`}; `comp_archetype` ∈ {`default`, `softmax`, `plasma`, `rotoblur`}. Each names a fragment by convention (`warp_<arch>.frag` / `comp_<arch>.frag`), and `docs/FRAGMENT-CONTRACT.md` covers what that fragment must then satisfy |
| Names | non-empty and unique across the catalog |
| Compilation | every equation string — `per_frame_init`, `per_frame`, `per_pixel`, and each `waves[i].t1` — compiles through `lib/evaluator.lua` |
| Finite results | a 120-frame smoke run over a documented synthetic env produces only finite numbers |

**Warns (never fails) on:** identifiers that are never assigned in the preset and
are not readable engine inputs. This matters because the evaluator resolves an
unknown name to **0** rather than erroring (`lib/evaluator.lua:23` — "NaN and +/-inf
collapse to 0"), so a mistyped input like `bass_att1` silently reads as zero and the
preset still compiles and still runs. It is a warning rather than a failure because a
legitimate custom variable may be assigned in another block of the same preset, and
the loop must not be blocked by a heuristic.

**`--expect-count N` is opt-in.** The catalog grows as the loop ports archetypes, so
asserting a size by default would fail on every successful port.

## What it does not check

- **Licensing.** It cannot tell a self-authored port from a copied preset file. The
  rule in `README.md` — equations and constructs only, never a community `.milk`
  preset — is a **human review obligation** on every port. The validator's pass says
  nothing about it.
- **Whether the look matches the archetype.** A preset can satisfy every structural
  check and still not be the visual it claims to be. That is the human pass over a
  contact sheet.
- **Cost.** Tier is a device measurement (offscreen p50 on VC4, ≤33.3 ms for tier C).
  Nothing here predicts frame time.
- **Preset order.** It does not police index order, and this matters more than it
  looks: `preset` is a 1-based index into the catalog (the `e.param("preset", …)`
  call in `main.lua`), and a saved state restores by that index (the
  `clamp_num(saved.preset, 1, 1, #PRESETS)` line in `main.lua`), so reordering
  silently changes what an existing saved scene plays. Extend the catalog; never
  reorder it. That is a reviewer rule, not a mechanical one.

## Interpreter requirement

A Lua interpreter must be on `PATH` (`luajit`, `lua`, `lua5.1`, `lua5.3`, `lua5.4`),
or named in `$CHECK_PRESETS_LUA`. There is deliberately **no interpreter-free mode**:
parsing the catalog in Python would mean a second implementation of Lua table
semantics that can drift from the engine's, and a validator that silently checks less
is worse than one that refuses to run. On a host without Lua the tool exits `2` with
that reason, and the honest conclusion is that this repository cannot be validated
there — which is exactly what blocks routing this repo through a Lua-less pipeline
host.

## Contract sources

`milkdrop/main.lua` (the header comment documents the per-frame writable vars and the
knob map), `milkdrop/lib/evaluator.lua` (the function set and the finite-result
guarantee), and `docs/trackB-plan/BRIEF.md` (the preset schema).
