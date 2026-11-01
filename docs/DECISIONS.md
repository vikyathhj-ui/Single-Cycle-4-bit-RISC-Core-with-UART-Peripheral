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

## D-007 — Spec decisions confirmed at the Phase 1 gate
Each one is marked **[decision]** in `docs/SPEC.md` or `docs/MICROARCH.md`. Format: choice → why →
alternative. **The owner confirmed all of them unchanged on 2026-11-01 ("ok").**

- **S-1, misaligned loads and stores trap** (mcause 4/6) [U §2.6].
  - Why: no misaligned bus or SRAM logic is needed, and riscv-formal supports it
    (`RISCV_FORMAL_ALIGNED_MEM`).
  - Alternative: split the access in hardware.
- **S-2, ALU reuse.** Vendor P1's combinational units (HC adder, shifter, clz, cpop, alu_pkg) and
  wrap them in a new combinational `core_alu`.
  - Why: P1's `alu_top` has latency 2 (registered inputs and outputs, P1 SPEC section 2), which
    breaks single-cycle EX with forwarding.
  - Alternatives: use `alu_top` as is (EX becomes 3 cycles, which defeats the 3-stage pipeline and
    full forwarding); or add a combinational mode to P1 through a P1 PR, which means acting outside
    this repo.
- **S-3, `misa` = `0x4000_0100`.** The B bit stays 0 because B means Zba + Zbb + Zbs
  [P §3.1.1], and this core has Zbb only.
- **S-4, SIM configuration.** Both memories become 32 KB behavioural models with the same 1rw1r
  interface and timing.
  - Why: CoreMark and the arch tests need more than 1 KB, and the RTL stays the same.
  - Alternative: one unified 32 KB memory. That changes the bus structure between the two
    configurations.
- **S-5, `mtval` values.** Illegal instruction gives the instruction bits; EBREAK gives the pc;
  misaligned and access faults give the address; ECALL and interrupts give 0.
  - Why: informative values help debugging, and [P §3.1.16] lets the platform choose. The reference
    model is configured to match in Phase 3.
- **S-6, boot ROM (≤ 256 B) with a UART loader.** It has a warm path (jump to IMEM) and a strap for
  preloaded simulation.
  - Why: the GDS configuration has no flash, so without a loader the chip could never be programmed.
  - Alternative: preload in simulation only, documented as a limitation.
- **S-7, domain mapping.** CORE = P2 PD0 `CPU`, PERI = PD2 `PERI`, PD1 `DSP` tied off,
  `HAS_RET` = 0. MEM (the SRAMs) is always powered, with its clock gated together with CORE.
  - Why: warm boot needs IMEM to keep the program.
- **S-8, IDLE entry.** Firmware writes `MODE_REQ`=IDLE and then executes `WFI`. The core is PD0's
  Q-Channel device: it accepts once `core_idle` is set, and denies if an enabled interrupt is pending.
  - Why: P2's PMU has no hardware idle input. Adding one means changing P2.
  - Alternative: an "auto-IDLE on WFI" input added to P2 through a P2 PR.
- **S-9, the waking UART byte is lost** in DEEP_SLEEP, because PERI is off. The AON detector only
  sees the start bit.
  - Alternative: put the whole UART in AON, which costs AON area and leakage.
- **S-10, SRAM STA corners.** The TT SRAM liberty is used at every corner, and those paths are
  labelled. Each corner's logic-only paths are also reported (D-005).
- **M-1, OpenRAM timing.** The macro reads on the falling edge, so the instruction word and load data
  arrive in the second half of the cycle. 3 stages are kept, and the fmax cost is measured in
  Phase 5.
  - Alternatives: a 4th fetch stage, or SRAMs on the inverted clock.

## D-008 — Spec references pinned to the 20250508 ratified ISA manuals
- **Context:** rule 5 requires section numbers. The `riscv-isa-manual` "latest" releases are dated
  snapshots whose numbering can move.
- **Choice:** cite the ratified release `20250508` (Unprivileged and Privileged; Machine ISA 1.13).
  The PDF and HTML are downloaded into git-ignored `ext/specs/` (`gh release download 20250508 -R
  riscv/riscv-isa-manual`). Section numbers were read from the HTML headings.

## D-009 — PMU register map imported from P2's work branch, provisionally
- **Context:** P2 `master` (`5cca517`) has bare `ON`/`OFF` enum keys in `scripts/regmap.yaml`. YAML
  1.1 parses them as booleans, so P2's generated `docs/REGMAP.md` and `sw/pmu_regs.h` contain
  `True`/`False`. P2's `rework/pmu` fixed this in `dc12040`.
- **Choice:**
  - Copy `scripts/regmap.yaml` from `rework/pmu` `5fe30e0` to `vendor/pmu/regmap.yaml`, recorded
    in `vendor/VENDOR.md`.
  - `scripts/gen_memmap.py` rejects any non-string enum key, so the bug cannot come back silently.
  - Re-pin when P2 merges.
  - No change is made in the P2 repo; the fix is already on its branch.

## D-010 — riscv-formal setup (Phase 2)
All options come from the installed framework (`ext/riscv-formal` at `c992aa6`, its
`docs/source/*.rst` and `cores/nerv/`), as BRIEF rule 5 requires.
- **Reading the RTL.**
  - genchecks reads `[verilog-files]` with Yosys `read -sv`. That frontend rejects the
    in-module `import alu_pkg::*` used by P1's units (`syntax error, unexpected TOK_IMPORT`).
  - So the core is read through the documented `[script-sources]` section, with
    `plugin -i slang` and `read_slang -D RISCV_FORMAL --top lp_rv32_core ...` (P1 D-012 uses the
    same frontend).
  - Only `formal/wrapper.sv` goes through `[verilog-files]`. The file list comes from
    `rtl/core/core.f`.
- **Runner.** genchecks must run two levels below the framework root. `scripts/run_formal.py`
  therefore copies `formal/checks.cfg` and `formal/wrapper.sv` into the git-ignored
  `ext/riscv-formal/cores/lp_rv32/` and runs the framework's own `genchecks.py` and makefile.
- **misa is not exposed over RVFI.**
  - With `RISCV_FORMAL_CSR_MISA`, the framework's Zbb models (e.g. `insns/insn_andn.v`) require
    misa bit 1 to be set, or they expect a trap.
  - The ratified spec defines bit 1 as "B" (Zba + Zbb + Zbs) [P §3.1.1], and this core keeps it 0
    (S-3).
  - misa is a constant (`core_csr.sv`), checked in simulation.
- **csrw is checked only on fully writable CSRs.**
  - `rvfi_csrw_check.sv` asserts that every bit an instruction sets or clears ends up in the
    "effective" written value. A read-only-zero WARL bit can never satisfy that.
  - The CSRs in `[csrs]` are therefore `mscratch`, `mtval`, `mcycle` and `minstret`. The counters
    also get the `upcnt` check.
  - mstatus, mie, mtvec, mepc and mcause are verified by the arch tests (Phase 3) and the system
    tests (Phase 4).
- **`[illegal_csrs]`:** a set of unimplemented M-mode addresses, plus "write to mvendorid".
  `csr_ill` proves that these trap.
- **Environment model** (`formal/wrapper.sv`):
  - The I-port and read data are unconstrained.
  - D-port responses come with any delay, one outstanding request at most.
  - The interrupt lines are unconstrained.
  - Bus errors are tied to 0: access faults are not modelled and are covered in simulation.
  - QREQn = 1.
- **Liveness fairness** (`LP_FAIRNESS`, liveness check only):
  - A bus response arrives within 2 cycles.
  - The instruction stream contains no WFI. WFI may legally wait forever (SPEC §5.5), so without
    this assumption liveness would fail by design.
- **Re-fetch on stall.**
  - In the model, a stalled ID/EX instruction is re-fetched, and the free I-port may return a
    different word. The core evaluates ID/EX purely combinationally each cycle, so this is just
    "a different instruction was fetched".
  - On silicon the SRAM returns the same word (MICROARCH §3).

## D-011 — Lint without waivers
- **Tool and builds:** `scripts/lint.sh` runs Verilator `-Wall` on `rtl/core/core.f` in the normal
  build and the RVFI build. Both are clean, with no `lint_off` pragmas.
- **Signals only RVFI uses:** in the normal build they are XOR-reduced into a signal named
  `unused_*`, which Verilator's default `--unused-regexp` accepts.
- **Unused package parameter:** the vendored `alu_pkg.OP_ILLEGAL_MIN` would otherwise be unused. It
  is used in an elaboration check in `core_alu.sv`, which fails the build if a re-vendored package
  changes the opcode encoding.

## D-012 — riscv-formal `reg` check at depth 14, the others at 20 (Phase 2)
- **Context:** with `reg 5 20` (SBY depth 21), the first full run finished the other 78 checks in
  about 5 minutes, all PASS. `reg_ch0` was still in yices on its single final step after more than
  2 hours (`ps` showed the solver at 1:59:17). It was stopped. No status was produced, so it is
  not reported as a pass.
- **Probe:** `scripts/run_formal.py --only '^reg_ch0$' --set reg=5,N --work lp_rv32_regN`, run
  in parallel with a 30-minute limit each (`results/formal/probe_reg*.log`,
  `results/formal/probe_reg_done.txt`, `results/formal/probe_lp_rv32_reg*.json`):

  | `reg` depth in cfg | SBY depth | Result | Solver time |
  |---|---|---|---|
  | 12 | 13 | PASS | 30 s |
  | 14 | 15 | PASS | 312 s |
  | 16 | 17 | no result within 1800 s (timeout) | — |
  | 18 | 19 | no result within 1800 s (timeout) | — |

- **Choice:** `reg 5 14`, the deepest depth that completed. Every other check keeps its configured
  depth.
- **What this means:** `reg` proves register read-after-write consistency for traces of up to 15
  cycles after reset.
  - In this pipeline a value is forwarded at distance 1 and read from the register file at
    distance ≥ 2 (MICROARCH §4). Bug 01 appeared at depth 11.
  - Longer sequences are covered by the arch tests and system tests (Phases 3–4).
- **Possible later improvement (not done):** run `reg` with a different engine, or let it run for
  hours. That is optional and would be recorded here.

## Bugs found by formal
Every counterexample is kept under `results/formal_cex/`. `scripts/cex_dump.py <vcd>` prints it as
a per-cycle table.

### Bug 01 — Exceptions skipped the load-use stall (`reg_ch0`, quick depth 11)
- **Evidence:** `results/formal_cex/bug01_exc_ignores_load_use/` (VCD and `trace.txt`).
- **Symptom:** at cycle 11, a store at pc 0x10 retired with `rvfi_rs2_rdata = c0100108`. But x23
  had been written with `c0100118` by the load at pc 0xc, which retired in cycle 10.
- **Cause:** `adv_ex` let an instruction with a synchronous exception leave ID/EX even during a
  load-use stall (`take_irq || exc || (!load_use && !wfi_wait)`).
  - The store here was misaligned, so it trapped, and it read a stale register.
  - This is a real bug: a misaligned-address or jump-target exception decision can depend on
    `rs1`, and that would be computed from the stale value.
- **Fix:** only interrupts bypass the stall, since they use no operands:
  `take_irq || (!load_use && (exc || !wfi_wait))` in `rtl/core/lp_rv32_core.sv`.
- **Verification:** all 79 checks pass at quick depth afterwards (`results/formal/summary_quick.json`).
