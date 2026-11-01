# PROGRESS

Single source of truth for status. Update this before every commit.
Spec: `docs/BRIEF.md`. Branch: `rework/lp-rv32`. PRs target `main`.

**Current state (2026-11-01): Phase 2 DONE (gate met). STOP: Phase 3 needs P2 merged (D-006).**
- Phase 0+1 PR #1 and the Phase 2 PR are open for the owner to merge.
- Phase 3 resume point (only after P2 `multipower` is merged):
  1. Vendor the PMU from P2's default branch and re-pin `vendor/pmu/regmap.yaml`.
  2. Decide the RISCOF reference model with the owner (D-003).
  3. Build the SoC blocks per SPEC §9 and their unit tests.
- Open items:
  - The CPI/area data for 3 vs 2 vs 5 stages needs program traces (MICROARCH §9, Phase 4).
  - INTERVIEW has 14 of the 40+ questions.

## Phase 0 — Setup
- [x] Environment check: `scripts/env_check.sh` → `results/env_check.txt`. All found (RESULT line).
      Installs made inside the repo only (no sudo):
      - `.venv` with cocotb-coverage;
      - `.venv-riscof` with riscof (D-004);
      - `ext/riscv-formal`;
      - `ext/riscv-arch-test` @3.10.0 (D-003);
      - `ext/sail` 0.16.

      The solver is yices (D-002).
- [x] `docs/BRIEF.md` (verbatim), `CLAUDE.md`, `PROGRESS.md`, `.gitattributes`, `.gitignore`,
      `LICENSE` (Apache-2.0), `NOTICE`.
- [x] Old code moved to `legacy/` with `git mv`. `docs/AUDIT.md` is backed by `scripts/legacy_probe.sh`
      → `results/legacy_probe.txt` (new probe TB `legacy/tb_probe.v`).
- [x] Layout created.
- [x] Commit + push `rework/lp-rv32`. The PR opens together with Phase 1, after the owner's spec review.

## Phase 1 — Spec
- [x] `docs/SPEC.md`: RV32I/Zicsr/Zbb, CSRs, traps, WFI, boot, power, peripherals. Citations are to
      the ratified 20250508 manuals in `ext/specs/` (D-008).
- [x] `docs/MICROARCH.md`: pipeline, OpenRAM half-cycle timing (M-1), hazard table H1–H11, precise
      traps, CSR map, stage-count data plan, formal plan.
- [x] `scripts/memmap.yaml` → `scripts/gen_memmap.py` (`make memmap`, `make memmap-check`) →
      `docs/MEMORY_MAP.md`, `sw/include/lp_rv32.h` (compiles for GDS and SIM), `tb/memmap.py`.
      PMU registers come from `vendor/pmu/regmap.yaml` (P2 `5fe30e0`, provisional, D-009).
- [x] **Gate: owner confirmed the spec** (D-007, all items unchanged). Committed, pushed, Phase 0+1 PR opened.

## Phase 2 — Core and RVFI
- [x] P1 ALU vendored: `prefix-adder-alu-sky130` `d59a42e` → `vendor/alu/` (19 files, byte-identical; `vendor/VENDOR.md`).
- [x] Core RTL `rtl/core/` (`core.f`): 3-stage pipeline, MEM/WB→ID/EX forwarding, load-use stall,
      branch in EX (registered redirect), CSRs, precise traps, WFI, Q-Channel device, RVFI port.
- [x] `make lint`: clean, normal + RVFI build, no waivers (`results/lint.txt`).
- [x] riscv-formal (`formal/checks.cfg`, `formal/wrapper.sv`, `scripts/run_formal.py`):
  - 79/79 PASS at full depth (`results/formal/summary.json`);
  - `reg` at SBY depth 15 (D-012);
  - Bug 01 found and fixed (DECISIONS);
  - `scripts/cex_dump.py` prints counterexamples.
- [x] CI workflow (`.github/workflows/ci.yml`): memmap-check, lint, formal-quick.
- [x] **Gate:** all checks pass at the stated depths. Committed, pushed, PR opened.

## Phase 3 — Compliance and SoC (blocked on P2)
## Phase 4 — Software and system tests
## Phase 5 — Physical
## Phase 6 — Docs and close
