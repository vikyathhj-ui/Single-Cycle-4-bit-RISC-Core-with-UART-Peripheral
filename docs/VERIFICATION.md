# Verification

Status: **Phase 4: formal, lint, arch tests, unit tests, system tests.** Every number below is
copied from a file under `results/`, and that file is named next to it.

## 1. Lint
- **Command:** `make lint` (`scripts/lint.sh`), Verilator 5.050 `-Wall` on `rtl/core/core.f`.
- **Result** (`results/lint.txt`): **clean** with no waivers (D-011) for:
  - `lp_rv32_core`, normal build and RVFI build (`-DRISCV_FORMAL`);
  - `lp_rv32_soc` (core + SoC + peripherals + vendored PMU), SIM configuration.

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

## 3. Architectural tests (RISCOF)
**Setup**
- **Framework and suite:** riscof 1.25.3 in `.venv-riscof` (D-004) with riscv-arch-test 3.10.0
  (D-003).
- **Reference model:** Spike 1.1.1-dev (D-013).
- **DUT:** `lp_rv32_core` in `tb/arch/tb_arch.sv` (Verilator). The testbench has the crossbar and
  two 32 KB memories, i.e. the **SIM memory configuration**. For the arch tests IMEM is at
  0x8000_0000 (D-015).
- **Build:** both sides use the same link script and `-mno-relax` (D-016).
- **Command:** `make riscof` → `results/riscof/summary.json`, `results/riscof/tests.txt`.

**Result**

| Suite | PASS | FAIL | NOT RUN (too big for 32 KB) | N/A |
|---|---|---|---|---|
| rv32i_m/I | 32 | 0 | 7 | — |
| rv32i_m/B (the Zbb tests) | 18 | 0 | — | — |
| rv32i_m/privilege | 15 | 0 | — | — |
| rv32i_m/pmp32 (no PMP in this core) | — | — | — | 41 |

- **Not run.** The 7 tests left out for size are `beq-01`, `bge-01`, `bgeu-01`, `blt-01`,
  `bltu-01`, `bne-01` and `jal-01`. Their code overflows the 32 KB IMEM by 192,384 to
  1,723,488 bytes (`tests.txt` has each value). This was the owner's choice (D-015).
  - Branches and JAL are still covered by riscv-formal (`insn_beq` … `insn_jal`, Phase 2).
- **No separate Zicsr suite.** 3.10.0 has none for rv32i_m. CSR behaviour is exercised through the
  privilege tests' trap handlers (mtvec, mepc, mcause, mtval, mstatus).
- **The comparison can fail.** A mutant that decodes SLTU as SLT makes `sltu-01` FAIL with 183 of
  724 words different, while everything else still passes (`results/riscof/mutation_check.txt`,
  D-017).

## 4. Unit tests (cocotb)
**Setup**
- **Tools:** cocotb 2.0.1 on Verilator 5.050. Functional coverage uses cocotb-coverage 2.0.
- **Coverage scope:** only leaf cover points are counted. Each coverage-export test fails if any
  bin is missed.
- **Command:** `make unit` (`scripts/run_unit.py`) → `results/unit/summary.json`,
  `results/coverage/<unit>.json`.

**Result**

| Unit | DUT | Tests | Coverage bins | What is checked |
|---|---|---|---|---|
| uart | `rtl/periph/uart_lite.sv` | 11/11 PASS | 27/27 | see below |
| timer | `rtl/periph/timer_clint.sv` | 6/6 PASS | 8/8 | see below |
| gpio | `rtl/periph/gpio8.sv` | 6/6 PASS | 26/26 | see below |
| xbar | `lp_rv32_xbar` + `apb_bridge` (`tb/unit/xbar_tb.sv`) | 2/2 PASS | 39/39 | see below |
| soc | `lp_rv32_soc` (`tb/unit/soc_tb.sv`, `sw/tests/smoke.S`) | 1/1 PASS | — | see below |

**What each unit test checks**
- **uart:**
  - Baud accuracy: every TX bit is held exactly BAUD_DIV+1 cycles, for DIV 1, 3, 15 and 433.
  - RX at −3 %, 0 % and +3 % bit-period skew.
  - FIFO levels 0/1/15/16; TX and RX overflow; framing error; glitch rejection.
  - Interrupts, flush, reset values, PSLVERR.
- **timer:**
  - mtime rate for PRESCALE 0, 1 and 9.
  - mtip across the LO→HI carry.
  - The safe 3-write mtimecmp update.
  - msip, reset values, PSLVERR.
- **gpio:**
  - OUT/DIR; IN synchroniser latency (2 cycles).
  - Rising and falling edge interrupts on every pin.
  - An edge in the same cycle as a W1C (set wins, the coincidence is checked by a monitor).
  - PSLVERR.
- **xbar:** 19,999 fetches and 10,276 D-port transactions against a Python memory-map model:
  - every region, both ROM ports, IMEM fetch-after-store coherence;
  - unmapped and past-the-end addresses, narrow APB accesses, absent slots;
  - APB wait states 0–15 and PSLVERR;
  - back-to-back requests;
  - no APB protocol violation.
- **soc:** reset → PMU boot → boot ROM → IMEM → UART. "OK" arrives on `uart_txd` 97 cycles after
  reset release.

**The xbar test can fail.** A bridge mutant that drops a request arriving in the response cycle is
caught after D-019. The first version of the test missed it.

## 5. System tests (firmware on the SoC)
**Setup**
- **Command:** `make system` (`scripts/run_system.py`) → `results/system/summary.json`.
- **Testbench:** `tb/system/soc_sys_tb.sv` (Verilator, cocotb 2.0.1).
- **Memory configuration:** SIM (32 KB + 32 KB).
- **Firmware:** built by `scripts/build_sw.py` with `riscv64-unknown-elf-gcc 16.1.0`,
  `-march=rv32i_zicsr_zbb -mabi=ilp32 -O2` (`results/sw/build_sim.json`).
- **UART:** the testbench decodes and drives the UART at BAUD_DIV+1 = 8 cycles per bit, and 434
  for the boot loader.

**What each test checks** (all PASS)

| Test | Program | What is checked |
|---|---|---|
| hello | `sw/hello` | Boot (BOOT.SEL=1), UART text, misa = 0x40000100, mhartid = 0, SYSCTRL ID, cold reset cause |
| loader | `sw/boot/boot.S` + `sw/loader_payload` | BOOT.SEL=0: '>' prompt, 1,740-byte image over the UART at the reset divisor, echoed checksum 0x0001ebe5, the loaded program runs |
| irq_test | `sw/irq_test` | WARL read-back of mstatus / mie / mtvec / mepc / mcause / misa; ECALL and illegal-instruction mcause and mtval; 3 timer, 1 software and 1 GPIO (IRQC) interrupt; priority MSI before MTI |
| sleep_demo | `sw/sleep_demo` | IDLE + 2 × DEEP_SLEEP; see below |
| zbb_bench | `sw/zbb_bench` | The same kernel with and without Zbb gives the same result (0x848a0121); cycle counts recorded |
| coremark | EEMBC CoreMark (`sw/coremark`) | CRCs match EEMBC's known 2K-performance values; CoreMark/MHz recorded (D-025) |

**sleep_demo: hardware-level checks** (independent of the firmware's output)
- **Clock gating:** the CORE clock had **0** edges during the 2,952-cycle IDLE window in which the
  PMU held `clk_en[CPU]` = 0. The firmware saw `mcycle` advance 160 while `mtime` advanced 3,112.
- **Power-off:** in both DEEP_SLEEP power-off windows (2,704 and 3,312 cycles) there were **0**
  violations: `iso_en[CPU]` stayed 1, and `uart_txd` stayed at its clamp value 1 while PERI was off.
- **Corruption model:** it fired exactly once per DEEP_SLEEP per domain (`corrupt_core` =
  `corrupt_peri` = 2). Both warm boots still ran correctly.
- **Wake reasons and retention:**
  - WAKE_SRC = 0x2 after the UART wake and 0x4 after the timer wake.
  - The DMEM `.noinit` marker survived (MEM stays powered); the stage counter lived in SCRATCH (AON).

**CoreMark** (RTL simulation, SIM configuration; not a valid published score, D-025)
- **Result:** 10 iterations in 8,876,270 cycles → **1.1266 CoreMark/MHz**.
- **Build:** GCC 16.1.0 `-march=rv32i_zicsr_zbb -mabi=ilp32 -O2`, data on the stack in DMEM.

**zbb_bench** (256 words)

| Build | Cycles | Instructions |
|---|---|---|
| without Zbb (`-march=rv32i_zicsr`, libgcc calls) | 25,912 | 22,594 |
| with Zbb (cpop, clz, ctz, rev8, ror, minu, maxu, andn) | 4,897 | 4,636 |

**Problems these tests found**
- Software accessed PERI before it was powered (D-022).
- The loader start-up race (D-023).
- The simulator's missing reset edge (D-024).
