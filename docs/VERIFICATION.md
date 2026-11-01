# Verification

Status: **Phase 2: core formal verification and lint.** The arch tests (Phase 3), unit tests
(Phase 3) and system tests (Phase 4) are added as each phase completes. Every number below is
copied from a file under `results/`, and that file is named next to it.

## 1. Lint
- **Command:** `make lint` (`scripts/lint.sh`), Verilator 5.050 `-Wall` on `rtl/core/core.f`.
- **Result** (`results/lint.txt`): **clean** in both the normal build and the RVFI build
  (`-DRISCV_FORMAL`), with no waivers (D-011).

## 2. riscv-formal (RVFI)
**Setup**
- **Framework:** `ext/riscv-formal` at `c992aa61` (recorded in `results/env_check.txt` and in
  `results/formal/summary.json`).
- **Solver:** yices 2.7.0 through `smtbmc` (D-002).
- **Configuration:** `formal/checks.cfg`, with `isa rv32iZbb`, `nret 1`, `RISCV_FORMAL_ALIGNED_MEM`.
- **Environment model:** `formal/wrapper.sv`, described in D-010:
  - instruction and data buses unconstrained;
  - any response delay;
  - interrupts unconstrained;
  - bus errors tied to 0.

**Commands**
- `make formal` runs the full depths → `results/formal/summary.json` and
  `results/formal/checks.txt`.
- `make formal-quick` caps every depth at 10 (CI) → `results/formal/summary_quick.json`.

**Result** (`results/formal/summary.json`, 403.9 s wall on 6 jobs): **79 of 79 checks PASS.**

| Check group | Checks | SBY depth | Result |
|---|---|---|---|
| `insn_*`: one per instruction of RV32I + Zbb (`insns/isa_rv32iZbb.txt`) | 55 | 21 | PASS |
| `reg` (register read = last write) | 1 | 15 (D-012) | PASS |
| `pc_fwd`, `pc_bwd` | 2 | 21 | PASS |
| `causal`, `unique` | 2 | 21 | PASS |
| `liveness` (with LP_FAIRNESS, D-010) | 1 | 26 | PASS |
| `ill` (0x00000000 traps) | 1 | 21 | PASS |
| `csrw` for mscratch, mtval, mcycle, minstret | 4 | 21 | PASS |
| `csr_ill` for 10 unimplemented / read-only accesses | 10 | 21 | PASS |
| `csrc_upcnt` for mcycle, minstret | 2 | 16 | PASS |
| `cover` | 1 | 21 | PASS |

**Zbb.** The installed framework supports Zbb (`isa rv32iZbb`), so all 18 Zbb instructions are
among the 55 `insn_*` checks. That includes andn, clz, cpop, ctz, max, maxu, min, minu, orc_b,
orn, rev8, rol, ror, rori, sext_b, sext_h, xnor and zext_h.

**Quick run** (`results/formal/summary_quick.json`, depths capped at 10, SBY depth 11): 79/79 PASS
in 51 s.

**Bugs found:** 1, logged in `docs/DECISIONS.md` under "Bugs found by formal". Its
counterexample is in `results/formal_cex/bug01_exc_ignores_load_use/`.

### Not covered by the formal model (covered later, or a stated limitation)
- **Access faults** (bus errors): `ibus_err`/`dbus_err` are tied to 0 → Phase 3/4 simulation.
- **WARL CSRs** (mstatus, mie, mtvec, mepc, mcause) and misa (D-010) → arch tests `privilege`
  suite, system tests.
- **Trap-handler semantics.** RVFI checks pc continuity (`rvfi_intr`), not that mcause/mepc hold
  the right values → arch tests and system tests.
- **WFI, the Q-Channel handshake and clock gating.** QREQn is held at 1 in formal → Phase 4
  `sleep_demo`.
- **Anything beyond the bound** (15–26 cycles after reset) → arch tests and programs.
