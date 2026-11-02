# PROGRESS

Single source of truth for status. Update this before every commit.
Spec: `docs/BRIEF.md`. Branch: `rework/lp-rv32`. PRs target `main`.

**Current state (2026-11-02): Phase 4 DONE (gate met). Phase 3+4 PR opened. Next: Phase 5 (physical).**
- Phase 5 resume point (LibreLane, sky130A, GDS memory configuration `LP_GDS`):
  1. Flow config with the 2 SRAM macros: check LibreLane's macro variables in the installed
     version, placement, halos, PDN over the macros.
  2. Isolation and ICG cells (D-021 note).
  3. Multi-corner STA with the TT-only SRAM liberty (S-10).
  4. IR drop; activity power for active vs IDLE from VCDs of hello + sleep_demo; signoff.
  5. `docs/FLOORPLAN.md`, `upf/lp_rv32.upf`.
- INTERVIEW has 26 of the 40+ questions.

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
- [x] `sw/common`: crt0 (waits for PERI, D-022), linker scripts (SIM/GDS, `.noinit`), HAL;
      `scripts/build_sw.py`.
- [x] Boot ROM loader `sw/boot/boot.S` (prompt, D-023), 216 B.
- [x] Programs: hello, loader_payload, irq_test, sleep_demo, zbb_bench, CoreMark (port in
      `sw/coremark`, D-025).
- [x] System tests (`make system`): **6/6 PASS**, including the power checks in sleep_demo.
      `--x-initial-edge` (D-024).
- [x] CoreMark **1.1266 CoreMark/MHz** (RTL simulation, SIM config, not a valid published score).
- [x] zbb_bench: 25,912 vs 4,897 cycles.
- [x] Stage-count CPI data (D-026) and core synthesis area. `results/summary.json` (`make summary`).
- [x] CI: hello system test added. Docs: POWER.md, VERIFICATION §5, SPEC/MICROARCH updates.
- [x] **Gate:** all pass, CoreMark/MHz recorded. Committed, PR opened.

## Phase 5 — Physical
## Phase 6 — Docs and close
