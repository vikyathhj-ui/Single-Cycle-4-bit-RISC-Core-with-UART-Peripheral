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

## D-013 — RISCOF reference model: Spike (Phase 3, owner decision 2026-11-02)
- **Context:**
  - riscv-arch-test 3.10.0 (D-003) ships a Sail RISCOF plugin that runs the old `riscv_sim_RV32`
    binary.
  - The installed Sail 0.16 provides `sail_riscv_sim`, which has a different command line and a
    JSON configuration.
  - Spike 1.1.1-dev is installed in the container. BRIEF A5 allows Spike "if Sail is impractical;
    say which".
- **Options:** adapt the Sail plugin to 0.16, or use Spike.
- **Choice (owner):** Spike. Every arch-test result names Spike as the reference model.
- **Consequence:** Spike must be configured to match this core's choices (misaligned accesses trap,
  S-1; mtval values, S-5). The plugin settings are recorded in `riscof/`.

## D-014 — PMU vendored from P2 `master` a87ba58 (Phase 3)
- **Context:**
  - P2 was renamed `vikyathhj-ui/soc-pmu-sequencer`. Its default branch is `master`, and its RTL
    is merged (P2 PRs #2 and #3).
  - P2 PR #4 (README, resume bullets) was still open on 2026-11-02. `git diff a87ba58
    origin/rework/pmu -- rtl scripts/regmap.yaml` is empty.
- **Choice (owner: "start Phase 3 now"):** vendor from `master` `a87ba58`. If PR #4 changes
  anything that is vendored, re-vendor.
- **Register map:** `vendor/pmu/regmap.yaml` is identical to the provisional copy (D-009), so
  `docs/MEMORY_MAP.md` is unchanged.

## D-015 — Arch tests: SIM memory size, exclusions, and test addresses (Phase 3, owner decisions 2026-11-02)
- **Size.** The riscv-arch-test 3.10.0 tests are far larger than the brief's 32 KB SIM memory. The
  largest code is `rv32i_m/I/src/jal-01.S` at 1,756,272 bytes; the largest data is 7,532 bytes
  (`bgeu-01`).
  - Options: add a 2 MB "ARCH" configuration, or run only the tests that fit 32 KB.
  - **Choice (owner):** only tests that fit the SIM configuration (IMEM 32 KB + DMEM 32 KB).
  - `scripts/run_riscof.py` links each test with the real 32 KB script. Those that overflow are
    listed as "NOT RUN (too big)", with the linker's overflow size, in
    `results/riscof/summary.json`.
- **PMP.** The 41 `rv32i_m/pmp32` tests are excluded as N/A (owner): the core has no PMP (SPEC §1).
- **Zicsr.** riscv-arch-test 3.10.0 has no separate Zicsr suite for rv32i_m. CSR behaviour is
  exercised through the `privilege` tests' trap handler (mtvec, mepc, mcause, mtval, mstatus).
- **Addresses.** Spike has a built-in UART at 0x1000_0000, which overlaps the SoC's IMEM base. The
  DUT and Spike must link identically, so for the arch tests only IMEM is at 0x8000_0000
  (`riscof/env/link.ld`). `lp_rv32_xbar` takes `IMEM_BASE`/`DMEM_BASE` parameters (defaults = the
  SoC memory map), and `tb/arch/tb_arch.sv` overrides IMEM_BASE. The core RTL is the same.

## D-016 — Arch tests compiled with `-mno-relax` (Phase 3)
- **Symptom:** `add-01` timed out on the DUT. The trace (`scripts/arch_one.py --trace`) showed an
  illegal-instruction trap at pc 0x800002c8 on the word 0x00130001. The disassembly shows a 2-byte
  `.insn 2, 0x0001` (c.nop) after a `la`, with the following 4-byte nops at 2-byte-aligned
  addresses.
- **Cause:** `arch_test.h` wraps `.align UNROLLSZ` in `.option rvc` (LA macro, RVTEST_CODE_BEGIN).
  With linker relaxation, the linker trims the alignment padding and can leave a c.nop in it. A
  core without C cannot execute that.
- **Fix:** both plugins and the size check compile with `-mno-relax`, so the padding is exact.
  The DUT and the reference get identical code. No c.nop remains (`objdump` count 0 for add-01).

## D-017 — RISCOF flow checked with a mutant (Phase 3)
- **Purpose:** to show that a PASS really means matching signatures.
- **Method:** a copy of `core_decode.sv` that decodes SLTU as SLT was built into the testbench and
  the full flow re-run.
- **Result** (`results/riscof/mutation_check.txt`): `rv32i_m/I/src/sltu-01.S` FAIL, "183 of 724
  words differ, first at word 1". Every other test still passes. The real RTL was never edited, and
  the testbench was rebuilt from it afterwards.

## D-018 — SYSCTRL detects a warm boot from the PMU main-switch acknowledge (Phase 3)
- **Context:**
  - The first version sampled the core-domain reset (PMU `rst_n[CPU]`) as data to see it rise.
  - That same net is the core's asynchronous reset. Verilator reported `SYNCASYNCNET` on it.
- **Choice:** set `RESET_CAUSE.WARM` when the CPU domain powers up again, i.e. when PMU
  `psw_main_ack[0]` rises for any time after the first one following a cold reset.
  - This signal is AON-side and is not a reset.
  - The main switch comes on before the PMU releases the core reset (P2 SPEC §4.3), so WARM is
    already set when the core starts.
  - The lint stays clean without a waiver (D-011).

## D-019 — Crossbar/bridge test: missing response timeout found by a mutant (Phase 3)
- **What happened:** a mutant of `apb_bridge.sv` was tried. It accepts a request only in IDLE, so it
  drops one that arrives in the response cycle, which is the bug fixed while the bridge was being
  written.
  - The first version of `tb/unit/test_xbar.py` still reported `test_random_traffic` as PASS: the
    dropped request just never got a response, and the test kept waiting.
  - Only the coverage check failed.
- **Fix to the test:** every D-port request must be answered within 40 cycles (the slave model
  inserts at most 15 wait states).
- **Result:** with the mutant, `test_random_traffic` FAILs with "D write APB: no response after 40
  cycles". With the real RTL it passes (`results/unit/mutation_xbar.txt`).

## D-020 — Boot ROM: Phase 3 stub, loader in Phase 4 (Phase 3)
- **Now:** `rtl/soc/bootrom_image.svh` is generated by `scripts/gen_bootrom.py` from
  `sw/boot/boot_stub.S`. The stub just jumps to IMEM_BASE (2 words).
- **Phase 4:** the real loader (SPEC §7: warm path, BOOT.SEL strap, UART loader) replaces it from
  `sw/boot/`. The ROM is always generated from source, never hand-typed.

## D-021 — SoC power-domain wiring choices (Phase 3)
- **PERI and DSP Q-Channels:** an always-accepting stub device (`rtl/soc/qch_stub_dev.sv`) per S-7.
  Firmware empties the UART TX FIFO before DEEP_SLEEP (SPEC §8.3).
- **Isolation, CORE → anything else:** every signal leaving CORE is clamped to 0 by `iso_en[0]`.
  That covers the APB request signals to AON/PERI slaves and the core's wake request. The
  Q-Channel outputs are already isolated inside the PMU.
- **Isolation, PERI → anything else:** every signal leaving PERI is clamped by `iso_en[2]`:
  - the APB response clamps to an error (PREADY=1, PSLVERR=1, PRDATA=0), so an access to a
    powered-off peripheral cannot hang the bridge;
  - `uart_txd` clamps to 1, the idle line level;
  - interrupts, GPIO outputs and output enables clamp to 0.
- **Clocks:** all clocks come from the one `clk` through the PMU's ICGs, so the domains are
  synchronous to each other.
- **Physical design note for Phase 5:** P2's `iso_wrap`/`icg_wrap` select the sky130 cells with
  `PMU_SKY130_CELLS`. P2 found that LibreLane excludes the `lpflow_*` isolation cells, so the
  Phase 5 configuration must handle the isolation cells.

## D-022 — Software waits for PERI before touching the UART or GPIO (Phase 4)
- **Found by:** the first `hello` system test printed nothing. The trace showed a store access
  fault at cycle 79 on the first UART write (`sw a0,12(a5)` to 0x4000_000C).
- **Cause:** the PMU powers the domains up one at a time, CPU before PERI (P2 inrush arbiter), so
  the core runs before PERI is on. While PERI is isolated, its clamps answer every APB access with an
  error, which is the intended behaviour (D-021). The Phase 3 smoke test only passed because of its
  timing.
- **Fix:** software rule, recorded in SPEC §7 and §8.1:
  - `crt0` calls `hal_wait_peri()` before `main()`. It polls PMU `PD_STATE` until PERI is ON and
    not busy.
  - The boot ROM loader and `sw/tests/smoke.S` do the same before using the UART.
- **Alternative (not taken):** a hardware stall of the core until all domains are up. This would
  change the PMU's sequencing, which is P2's design.

## D-023 — UART loader sends a '>' prompt before it accepts data (Phase 4)
- **Found by:** the loader test. Its host sent the first length byte while PERI was still powering
  up. The receiver was not enabled yet, so the length was decoded wrongly.
- **Fix:** once the UART is enabled, the boot ROM writes '>'. The host waits for it before sending.
  It costs 2 instructions; the ROM is 216 of 256 bytes.
- **Result:** the prompt arrives 4,232 cycles after reset release (`results/system/summary.json`,
  loader). That is the PERI power-up plus one frame at the reset divisor.

## D-024 — Verilator `--x-initial-edge` for every simulation build (Phase 4)
- **Symptom:** in the SoC, the first instruction retired at pc 0x4, not the reset vector.
  - That made the boot ROM's `lw t0, 4(s0)` read through a stale `s0`, so the loader took the warm
    path on a cold boot.
  - A probe showed `id_pc` = 0 instead of `RESET_VEC − 4` after reset.
- **Cause:** a simulation semantics issue, not an RTL bug.
  - The core's flops are `always_ff @(posedge clk or negedge rst_n)`. In the SoC, `rst_n[CPU]` is
    low from time 0, and the CORE clock is gated off during reset.
  - Verilator's 2-state initial value (0) produces no `negedge` at time 0, so the reset branch never
    ran.
  - On silicon an asynchronous reset is level-sensitive. The arch testbench did not show this,
    because its clock runs during reset.
- **Fix:** `--x-initial-edge` ("Enable initial X->0 and X->1 edge triggers", `verilator --help`) in
  `make tb-arch`, `scripts/run_unit.py` and `scripts/run_system.py`.
  - After the fix the first retirement is pc 0x0 (`lui s0, 0x40004`).
  - RISCOF was re-run with the rebuilt testbench.

## D-025 — CoreMark: port, run length and labelling (Phase 4)
- **Source:** EEMBC CoreMark, `eembc/coremark` at `1f483d5b` (2025-05-01), cloned into git-ignored
  `ext/coremark`.
  - The core files (`core_list_join.c`, `core_main.c`, `core_matrix.c`, `core_state.c`,
    `core_util.c`, `coremark.h`) are compiled unmodified.
  - The port in `sw/coremark/` is EEMBC's `barebones` porting files, changed only where marked
    "lp_rv32 port": the timer is `mcycle`, the UART uses the HAL, there are no float or time.h, and
    `DONE` is printed at the end. This follows the CoreMark rule that only porting files may change.
- **Time base:** `EE_TICKS_PER_SEC` = 1,000,000 cycles, so CoreMark's printed Iterations/Sec equals
  CoreMark/MHz.
  - The reported figure is computed by the test from the printed "Iterations" and "Total ticks":
    10 × 10^6 / 8,876,270 = **1.1266 CoreMark/MHz** (`results/system/summary.json`).
- **Validation:** CoreMark compares its CRCs with EEMBC's known values for the 2K performance run.
  No CRC error was printed, and seedcrc = 0xe9f5.
  - CoreMark also counts "Must execute for at least 10 secs" as an error and therefore prints
    "Errors detected".
  - 10 iterations in RTL simulation take 8.9 M cycles. A real 10-second run is out of reach in
    simulation, and running "longer" on a simulated clock would only satisfy the text of the rule.
- **Label:** every CoreMark number is reported as "RTL simulation, SIM configuration, not a valid
  published CoreMark score".
- **Why the figure is low:** RV32I has no M extension, so multiplications are libgcc calls
  (`__mulsi3`).

## D-026 — Stage count: CPI data (Phase 4)
- **CPI data** (`scripts/cpi_model.py` → `results/cpi/cpi_model.json`): hazard counts measured on the
  real 3-stage RTL from the RVFI retire stream (CoreMark, 7,209,775 instructions), with the
  penalty rules stated in the script:

  | Pipeline | CPI on CoreMark |
  |---|---|
  | 2-stage (model) | 1.2861 |
  | 3-stage (model) | 1.2397 |
  | 3-stage (measured) | 1.2408 |
  | 5-stage (model) | 1.4486 |

  - The 3-stage model is within 7,885 cycles of the measured 8,945,622, which validates the
    counting.
- **Area data:** only the 3-stage core exists. Yosys synthesis on sky130 tt gives 81,269.19 µm²,
  8,040 cells and 1,430 flops (`results/area/core_yosys.json`; pre-layout). The 2- and 5-stage
  designs are not built, so their area is **not measured**.
- **Reasoning:**
  - 2 stages: a synchronous SRAM read cannot finish in the same stage as the address. Every load
    then costs a cycle (+0.0464 CPI here).
  - 5 stages: 2-cycle branch penalties (+0.2089 CPI). They pay off only if the shorter stages raise
    fmax by more than that ratio.
  - The 3-stage clock period is measured in Phase 5. The comparison with a 5-stage fmax stays
    qualitative because no 5-stage design exists.

## D-027 — SYSCTRL.WAKE_SRC records every wake input edge, masked or not (Phase 4)
- **What happens:** in `sleep_demo`'s IDLE phase, WAKE_SRC reads 0x5 (core interrupt + timer),
  although the PMU only had bit 0 unmasked. MTIP also rose and is wired to `wake_irq[2]`.
- **Status:** this matches the register description ("which wake source(s) fired since last
  cleared"). The PMU mask decides what wakes the chip; SYSCTRL only records edges.
- **Firmware practice:** clear WAKE_SRC before sleeping (`sleep_demo` does). After DEEP_SLEEP the
  recorded value was exactly the one enabled source each time: 0x2 for UART, 0x4 for the timer.

## D-028 — SRAM liberty max_transition 0.04 ns: post-GRT design repair disabled (Phase 5)
- **Symptom:** run r01 (40 ns) stopped in `OpenROAD.RepairDesignPostGRT` with `[RSZ-0090] Max
  transition time from SDC is 0.040ns. Best achievable transition time is 0.068ns with a load of
  0.01pF`.
- **Cause:** `sky130_sram_1kbyte_1rw1r_32x256_8_TT_1p8V_25C.lib` sets `max_transition : 0.04` on
  the buses `addr0`, `wmask0` and `addr1` (lib lines 188, 225, 427). The same file's
  `default_max_transition` is 0.5. No sky130_fd_sc_hd driver can produce a 0.04 ns transition
  into that pin load (the resizer's best is 0.068 ns).
- **Options:**
  - edit a copy of the PDK liberty, which would change a vendor view;
  - lower the global MAX_TRANSITION, which does not help: the pin limit is tighter;
  - disable only the post-global-route repair step that treats it as a hard error.
- **First choice (run r02), reversed:** `RUN_POST_GRT_DESIGN_REPAIR` = false.
  - That left the whole design without post-route slew repair: 7,859 max-slew violations at
    max_ss, with fanout nets at 2.39 ns against the 0.75 ns limit, while the pre-route repair alone
    was not enough (`results/flow/r02_evidence.json`).
  - Too blunt.
- **Final choice:** keep post-route repair, and give the flow a derived SRAM liberty
  (`scripts/sram_lib_relax.py` → `flow/lib/…TT_1p8V_25C.relaxed.lib`).
  - It is a copy of the PDK file in which only the three `max_transition : 0.04` lines of the buses
    `addr0`, `wmask0` and `addr1` are set to the file's own `default_max_transition` (0.5). The diff
    is in `results/flow/sram_lib_relax.diff`.
  - Timing arcs, pins and area are unchanged, and the PDK file is not modified.
  - The transitions actually reached at those SRAM pins are reported in signoff against the
    original 0.04 ns value, so the deviation stays visible.

## D-029 — fmax per corner by an STA period sweep, implementation at 100 ns (Phase 5)
- **Context:** at 40 ns (run r01, mid-PnR) the setup worst slack was TT +0.77 ns, SS −48.6 ns,
  FF −0.48 ns.
  - The critical path starts at `u_imem` on the **falling** clock edge (dout1) and ends at a
    rising-edge flop after decode and execute. This is the half-cycle path accepted at the spec
    gate (M-1).
  - For such a path slack = T/2 − delay, so fmax ≠ 1/(T − slack).
- **Choice:**
  - Implement at CLOCK_PERIOD = 100 ns, so that every corner can close and the resizer is not
    driven by impossible violations.
  - Measure fmax per corner with `scripts/sta_fmax.py`: OpenSTA on the final netlist + SPEF,
    LibreLane's own `base.sdc` re-applied at each trial period, and a binary search to 0.05 ns for
    the smallest period with setup slack ≥ 0, for all 9 corners.
  - The SRAM uses its TT liberty at every corner (S-10), and every fmax is labelled that way.
- **Limitation:** a design implemented for 100 ns is not optimised by the resizer for shorter
  periods. The reported fmax is that of this implementation, not the best a tighter target could
  reach.

## D-030 — Hold margins 0.2 ns (Phase 5)
- **Context:** in run r02, after the resizer's hold repair, there were still hold violations at
  max_ff (29 paths, worst −0.164 ns), nom_ff (19), min_ff (13) and max_tt (4)
  (`flow/runs/r02_p100/56-openroad-stapostpnr/*/min.rpt`).
  - The worst path is register-to-register between flops on the ungated `clk_regs` tree and the
    PMU-gated tree. The gated tree's ICG plus delay buffers give the skew.
  - The resizer already works on every STA corner (`RSZ_CORNERS` unset → `STA_CORNERS`).
- **Choice:** `PL_RESIZER_HOLD_SLACK_MARGIN` 0.1 → 0.2 and `GRT_RESIZER_HOLD_SLACK_MARGIN`
  0.05 → 0.2, so the repair aims beyond 0.
- **Cost:** more hold buffers, i.e. area and some power. Measured in the run that uses it.

## D-031 — Magic DRC with the OpenRAM macros as abstract views (Phase 5)
- **Evidence (run r02):** Magic DRC on the full GDS reported 5,189,248 markers.
  - **All** of them are inside the two SRAM footprints: 2,832,125 in u_imem and 2,357,123 in
    u_dmem. **0** are outside (`results/flow/r02_evidence.json`).
  - Magic also warned that cells inside the macro GDS are placed on top of themselves.
  - KLayout DRC on the same GDS: 0. LVS: 0 errors. Routing DRC: 0. Antenna: 0.
- **Interpretation:** the OpenRAM bitcell array is built with SRAM-specific rule exceptions that
  Magic's full sky130 deck flags. The design's own placement and routing has no Magic markers.
- **Choice:** `MAGIC_DRC_MAGLEFS` = the PDK's `maglef/sky130_sram_1kbyte_1rw1r_32x256_8.mag`.
  LibreLane: "abstract LEF views ... act as blackboxes during DRC". Magic then checks everything
  except the macro internals.
- **Reporting:** both numbers are reported, the full-GDS count with its location analysis and the
  abstract-view count. The macros are not claimed to be Magic-clean internally.

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
