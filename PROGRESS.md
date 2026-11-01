# PROGRESS

Single source of truth for status. Update this before every commit.
Spec: `docs/BRIEF.md`. Branch: `rework/lp-rv32`. PRs target `main`.

**Current state (2026-11-01): Phase 0 DONE. Next: Phase 1 (spec), which ends at an owner gate.**
- Scope agreed with the owner: Phases 0–2 now. Phase 3+ waits until P2 (`multipower`) is merged (D-006).
- To resume Phase 1, write `docs/SPEC.md` and `docs/MICROARCH.md`, then `scripts/memmap.yaml` → generator →
  `sw/memmap.h`, `tb/memmap.py` and `docs/MEMORY_MAP.md`.
  - Import the PMU registers from P2's merged `scripts/regmap.yaml` (master).
  - Propose an answer for D-005 (SRAM TT-only liberty).
  - Then STOP and ask the owner to confirm the spec. After that, open the Phase 0+1 PR.

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
- [ ] `docs/SPEC.md`, with RISC-V unprivileged/privileged section citations.
- [ ] `docs/MICROARCH.md`: pipeline diagram, hazard table, CSR map.
- [ ] Memory map YAML → C header + Python + Markdown generator (with a `--check` staleness mode).
- [ ] D-005 proposal (SRAM corners). Justify 3 stages vs 2/5 (area and CPI data come in Phase 2).
- [ ] **Gate: owner confirms the spec.** Commit, push, open the Phase 0+1 PR.

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
