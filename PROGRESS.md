# PROGRESS

Single source of truth for status. Update this before every commit.
Spec: `docs/BRIEF.md`. Branch: `rework/lp-rv32`. PRs target `main`.

**Current state (2026-11-01): Phase 1 DONE (spec confirmed, D-007). Next: Phase 2.**
- Scope agreed with the owner: Phases 0–2 now. Phase 3+ waits until P2 (`multipower`) is merged (D-006).
- Phase 2 resume point:
  1. Vendor P1's combinational units into `vendor/alu/` (pinned hash in `vendor/VENDOR.md`).
  2. Write `rtl/core/*` per docs/MICROARCH.md, then the RVFI port.
  3. Write `formal/checks.cfg` and `formal/wrapper.sv`, then run riscv-formal.

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
- [ ] Vendor P1 ALU (`prefix-adder-alu-sky130` main, pinned hash, recommended adder) → `vendor/VENDOR.md`.
- [ ] Core RTL: 3-stage pipeline, forwarding, load-use stall, branch in EX, CSRs, traps, WFI.
- [ ] RVFI port + `formal/checks.cfg` (`isa rv32iZbb`, `solver yices`); counterexamples → `results/formal_cex/`.
- [ ] Verilator `-Wall` clean.
- [ ] **Gate:** all checks pass at the stated depth. Commit, push, open a PR. Stop: Phase 3 needs P2.

## Phase 3 — Compliance and SoC (blocked on P2)
## Phase 4 — Software and system tests
## Phase 5 — Physical
## Phase 6 — Docs and close
