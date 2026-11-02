# PROGRESS

Single source of truth for status. Update this before every commit.
Spec: `docs/BRIEF.md`. Branch: `rework/lp-rv32`. PRs target `main`.

**Current state (2026-11-02): Phase 3 DONE (gate met). Next: Phase 4 (software + system tests).**
- Phases 0–2 merged (PR #1, #2). Phase 3 committed on `rework/lp-rv32`. Per the brief, the next PR
  opens after Phase 4.
- Phase 4 resume point:
  1. `sw/`: linker scripts (GDS, SIM), crt0, HAL (UART, timer, GPIO, PMU), the real boot loader
     (`sw/boot/`, replaces the stub, D-020), and the programs hello, irq_test, sleep_demo,
     zbb_bench, coremark.
  2. cocotb system tests with a UART monitor/driver and power-aware checks (see P2's
     `tb/domain_shell.sv` for the corruption model).
  3. CoreMark in the SIM config.
  4. Stage-count CPI data (MICROARCH §9).

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

## Phase 3 — Compliance and SoC
- [x] PMU vendored from `soc-pmu-sequencer` master `a87ba58` (14 files byte-identical; regmap unchanged, D-014).
- [x] RISCOF (`make riscof`): **65 PASS / 0 FAIL**, 7 NOT RUN (too big for 32 KB, D-015), 41 N/A (PMP).
      Spike reference (D-013), `-mno-relax` (D-016), mutation check (D-017).
- [x] SoC RTL:
  - `rtl/soc/`: xbar, APB bridge, boot ROM (stub, D-020), SIM memory, Q-Channel stub, switch
    model, `lp_rv32_soc`;
  - `rtl/periph/`: UART, GPIO, TIMER, IRQC, SYSCTRL, UART wake.
  - Lint clean (`make lint`), D-018, D-021.
- [x] cocotb unit tests (`make unit`): **26/26 PASS**, coverage 100 % of 100 bins (uart 27, timer 8,
      gpio 26, xbar 39) plus the SoC smoke test. Xbar mutation check (D-019).
- [x] CI: unit tests added.
- [x] **Gate:** arch tests pass and unit tests pass. Committed.

## Phase 4 — Software and system tests
## Phase 5 — Physical
## Phase 6 — Docs and close
