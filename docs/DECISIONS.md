# Design decisions

Format: context → options → choice → evidence. Numbers are quoted from files under `results/`
and are never typed by hand.

## D-001 — Clone location and branch (Phase 0)
- **Context:** the brief assumes we work inside a clone of this repo. The other projects live in
  `~/projects` (container: `/foss/projects`).
- **Choice:**
  - The clone is at `~/projects/Single-Cycle-4-bit-RISC-Core-with-UART-Peripheral` and the work
    branch is `rework/lp-rv32`. PRs target `main`, the repo's default branch.
  - If the repo is renamed in Phase 6, the local folder name stays the same, so the absolute paths
    stored in LibreLane `runs/` keep working (same reason as P1).

## D-002 — riscv-formal solver: yices (Phase 0)
- **Context:**
  - The brief says riscv-formal "typically needs boolector or bitwuzla; check its docs".
  - The container has only `yices-smt2` (`results/env_check.txt`). boolector, bitwuzla and z3 are
    absent.
- **Evidence:**
  - `ext/riscv-formal/docs/source/procedure.rst` lists a `solver` option in `checks.cfg` ("Name of
    solver, defaults to `boolector`").
  - `ext/riscv-formal/checks/genchecks.py` turns it into the SBY engine line
    `smtbmc <solver>` (around line 294). It also has special cases for `bmc3` (ABC) and
    `btormc`.
  - `smtbmc yices` is a standard SBY engine.
- **Choice:** set `solver yices` in `formal/checks.cfg`. Nothing is installed.
- **Risk:** if a check is impractically slow with yices, `bmc3` (yosys-abc, also installed) is
  the documented fallback. Any switch is recorded here.

## D-003 — riscv-arch-test pinned at 3.10.0 for RISCOF (Phase 0)
- **Context:**
  - The brief requires RISCOF with `riscv-arch-test`.
  - The current `main` of riscv-arch-test (cloned 2026-11-01, `cbbb9f0e`) is "ACT 4.0". Its
    CHANGELOG says "The old `riscof`/`riscv-ctg`/`riscv-isac`/`riscv-config` flow has been replaced".
    Its README calls riscof "deprecated".
- **Options:**
  - (a) Pin to the last RISCOF release, `3.10.0`. This matches the brief.
  - (b) Use ACT4 on `main`. This needs `mise`, Ruby and the riscv-unified-db gem, and departs from the
    brief.
- **Choice:** (a). `ext/riscv-arch-test` is checked out at `3.10.0`
  (`fc32e41d49480fd99ba0a192dfff9c3319b44873`, 2024-11-05). `results/env_check.txt` records it.
  - Suites present at this tag: `riscv-test-suite/rv32i_m/{I, B, privilege, Zifencei, ...}`.
- **Open for Phase 3 (decide with the owner):**
  - The 3.10.0 Sail plugin (`riscof-plugins/rv32/sail_cSim/riscof_sail_cSim.py`) runs the old
    `riscv_sim_RV32` binary.
  - The installed Sail release (0.16) provides `sail_riscv_sim`, which has a different CLI and
    config scheme.
  - Options:
    - adapt the plugin to `sail_riscv_sim`;
    - use an older Sail build;
    - use Spike, which the brief allows ("say which").

## D-004 — riscof in its own isolated venv (Phase 0)
- **Context:**
  - `pip install riscof` fails in the main venv: riscv-config 3.18.3 pins `pyyaml==5.2`, which
    has no wheel for Python 3.12. Building it from source fails with Cython 3
    (`'build_ext' object has no attribute 'cython_sources'`).
  - The container's `PYTHONPATH` also puts `/usr/local/lib/python3.12/dist-packages` ahead of
    any venv's own packages.
- **Choice:**
  - Create a separate venv, `.venv-riscof`, without system site-packages and with `PYTHONPATH`
    cleared.
  - In it, install `cython<3`, `setuptools<70` and `wheel`, then `pyyaml==5.2` with
    `--no-build-isolation`, then `riscof` (1.25.3).
  - The cocotb venv `.venv` stays on PyYAML 6.
  - Always run riscof as `PYTHONPATH= .venv-riscof/bin/riscof ...`.

## D-005 — SRAM macro has a TT liberty only (Phase 0, open → Phase 1 spec)
- **Context:**
  - The brief asks for "fmax at every corner" (A6).
  - `results/env_check.txt` shows one liberty file for `sky130_sram_1kbyte_1rw1r_32x256_8`:
    `TT_1p8V_25C`.
- **Status:** a proposal goes into `docs/SPEC.md` for the owner to confirm at the Phase 1 gate.

## D-006 — Phases 3+ wait for P2 (Phase 0)
- **Context:**
  - P2 (`vikyathhj-ui/multipower`, default branch `master`) has only its Phase 0+1 PR merged.
  - Its PMU RTL is still on `rework/pmu` in Phase 3 verification, and the repo is not yet renamed to
    `soc-pmu-sequencer`.
- **Choice (owner, 2026-11-01):**
  - Do P6 Phases 0–2 now. They need only the P1 ALU, plus P2's merged register-map YAML for the
    spec.
  - Vendoring the PMU (Phase 3) waits until P2 is merged.
  - `vendor/VENDOR.md` will record the repo name and branch as they actually are.
