# PROGRESS

Single source of truth for status. Update this before every commit.
Spec: `docs/BRIEF.md`. Branch: `rework/lp-rv32`. PRs target `main`.

**Current state (2026-11-02): Phase 5 IN PROGRESS.** Phases 0–4 are merged (PR #1–#3).
- Done so far in Phase 5 (all but the WIP commit 0fb9990 are uncommitted):
  - `flow/config.json`: LibreLane, `LP_GDS` + `PMU_SKY130_CELLS`, die 1100 x 1100 µm, 2 SRAM macros
    (IMEM (500,580) N, DMEM (100,60) FS, halo 15 µm), `PDN_MACRO_CONNECTIONS`.
  - Derived SRAM liberty `flow/lib/...relaxed.lib` from `scripts/sram_lib_relax.py` (D-028).
  - Hold margins 0.2 ns (D-030), Magic DRC with the SRAM maglef abstract (D-031),
    design-repair slew/cap margins 50 % (D-033, still to be written in DECISIONS).
  - `scripts/sta_fmax.py`: per-corner fmax by OpenSTA period sweep. Units bug (slack in seconds)
    fixed after `results/sta/fmax_r03_p110.json` was made, so that file's slack fields are wrong.
  - Gate-level power: `scripts/gls_power.py`, `tb/gls/`, `sw/power_gds/power.S` (D-032, still to be
    written in DECISIONS). First trial on r03.
- Runs:
  - r01 (40 ns): stopped, SRAM max_transition (D-028). r02 (100 ns): evidence in
    `results/flow/r02_evidence.json`.
  - r03 (110 ns, margins 20/10 %): complete. Magic/KLayout/route DRC 0, LVS 0, antenna 0, setup and
    hold met, but 7,809 max-slew violations at max_ss (`flow/runs/r03_p110/final/metrics.json`).
  - r04 (110 ns, margins 50 %, D-033): re-running (the first attempt was cut off by a container restart).
- **Resume:**
  1. If r04 is incomplete, re-run it: `docker exec -w .../flow iic-osic bash -lc 'librelane --manual-pdk --pdk-root $PDK_ROOT --pdk $PDK --scl $STD_CELL_LIBRARY config.json --run-tag r04_p110 --overwrite'`.
  2. Check DRC/LVS/antenna/slew, then `python3 scripts/sta_fmax.py flow/runs/r04_p110`.
  3. `python3 scripts/gls_power.py flow/runs/r04_p110`, then IR drop.
  4. FLOORPLAN.md, DECISIONS D-032/D-033, summary.json, commit, PR.

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
