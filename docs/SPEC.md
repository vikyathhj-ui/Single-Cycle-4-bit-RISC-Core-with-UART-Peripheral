# lp-rv32 functional specification

Status: **confirmed by the owner at the Phase 1 gate (2026-11-01).** Items marked **[decision]** are
listed in `docs/DECISIONS.md` D-007.

**Spec references.** All citations are to the ratified RISC-V ISA Manual, version 20250508
(`riscv/riscv-isa-manual` release `20250508`; copies in git-ignored `ext/specs/`):
- **[U]**: *The RISC-V Instruction Set Manual, Volume I: Unprivileged Architecture*.
- **[P]**: *Volume II: Privileged Architecture* (Machine-Level ISA, version 1.13).

Section numbers are those printed in the 20250508 documents.

Memory map and register details are generated: see `docs/MEMORY_MAP.md` (from `scripts/memmap.yaml`).
Microarchitecture (pipeline, hazards, CSR implementation) is in `docs/MICROARCH.md`.

## 1. Overview

```
                 ┌──────────────────────────── CORE domain (PMU PD0 "CPU") ───────────────────────────┐
  boot ROM ◄─────┤  lp_rv32_core (RV32I+Zicsr+Zbb, M-mode, 3-stage)                                    │
                 │    I-port ──► I-side mux ──► BOOTROM | IMEM port1 (read)                            │
                 │    D-port ──► crossbar ──┬─► BOOTROM | IMEM port0 | DMEM port0                       │
                 │                          └─► bus-to-APB bridge ──► APB (16 × 4 KB slots)            │
                 │    RVFI (formal only)     IRQC (8 sources → mip.MEIP)                               │
                 └──────────────────────────────────────────────┬─────────────────────────────────────┘
  MEM (always powered, clock gated with CORE): IMEM 1rw1r SRAM, DMEM 1rw1r SRAM (GDS: 2 × 1 KB macros)
                                                                │ APB
         ┌──────── PERI domain (PD2) ───────┐   ┌──────────── AON domain (never off) ───────────────────┐
         │ UART core (TX/RX, FIFOs)          │   │ PMU (P2)   TIMER (mtime/mtimecmp/msip)   SYSCTRL      │
         │ GPIO (8 pins, edge IRQs)          │   │ UART-RX start-bit wake detector   reset synchroniser │
         └───────────────────────────────────┘   │ ICG cells (sky130_fd_sc_hd__dlclkp) for CORE and PERI │
                                                 └───────────────────────────────────────────────────────┘
```

| Item | Value |
|---|---|
| ISA | RV32I 2.1 [U §2] + Zicsr 2.0 [U §6] + Zbb 1.0 [U §29.4.2]; machine mode only [P §3] |
| Not implemented | M, A, C, F/D, Zifencei, Zicntr user counters, S/U modes, PMP, debug |
| Hart | one, `mhartid` = 0 [P §3.1.5] |
| Endianness | little [U §1.4] |
| Clocks | one input clock `clk`; CORE and PERI clocks come from it through ICG cells (§8) |
| Reset | `rst_n` pin, asynchronous assert, synchronised release |

## 2. Instruction set

### 2.1 RV32I [U §2]
- Supported: all RV32I instructions, i.e. the integer computational instructions [U §2.4], control
  transfers [U §2.5], loads and stores [U §2.6], FENCE [U §2.7], and ECALL/EBREAK [U §2.8].
- **FENCE** (and FENCE.TSO, PAUSE) execute as no-ops. The core is in-order, has one bus master per
  port and no caches, so memory accesses already complete in program order [U §2.7]. The I/O bits
  need no action, because an APB access completes before the next memory instruction leaves the
  pipeline (MICROARCH §5).
- **HINTs** [U §2.9] execute as their base instruction (most of them write `x0`, so they do nothing).
- **Misaligned loads and stores** raise *load address misaligned* (mcause 4) or *store/AMO address
  misaligned* (6). The access is not performed. [U §2.6] allows either handling or trapping, and
  [P §3.1.15] Table 14 gives the codes. **[decision S-1]**
  - *Why:* no misaligned support in the bus or SRAM is needed.
  - riscv-formal expects this behaviour when `RISCV_FORMAL_ALIGNED_MEM` is defined (`ext/riscv-formal/docs/source/rvfi.rst`).
- **Misaligned jump and branch targets.** A taken branch, JAL or JALR whose target is not 4-byte
  aligned raises *instruction address misaligned* (0) on the jump instruction itself
  [U §2.5.1, §2.5.2]. IALIGN = 32 because C is not implemented.
- **Encodings with no defined instruction** raise *illegal instruction* (2). This includes the
  reserved encodings of the base ISA, FENCE.I (Zifencei is not implemented), and any SYSTEM
  encoding other than ECALL, EBREAK, MRET, WFI and the CSR instructions.

### 2.2 Zicsr [U §6]
- CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI [U §6.1].
- **Read and write side effects follow [U §6.1]:**
  - CSRRW/CSRRWI with `rd = x0` do not read the CSR.
  - CSRRS/CSRRC with `rs1 = x0`, and CSRRSI/CSRRCI with `uimm = 0`, do not write it.
- **Illegal CSR accesses raise illegal instruction:**
  - an access to an unimplemented CSR address;
  - a write to a read-only CSR, i.e. address bits [11:10] = `11` [P §2.1].
- A CSR write takes effect for the next instruction [U §6.1.1]. For writes that change interrupt
  enables, see §5.4.

### 2.3 Zbb [U §29.4.2]
- ANDN, ORN, XNOR [U §29.4.2.1];
- CLZ, CTZ [U §29.4.2.2];
- CPOP [U §29.4.2.3];
- MIN, MINU, MAX, MAXU [U §29.4.2.4];
- SEXT.B, SEXT.H, ZEXT.H [U §29.4.2.5];
- ROL, ROR, RORI [U §29.4.2.6];
- ORC.B [U §29.4.2.7];
- REV8 [U §29.4.2.8].

The RV64-only "W" forms [U §29.2] are illegal on RV32. The datapath for these comes from the P1 ALU
(§10, **[decision S-2]**).

### 2.4 Privileged instructions [P §3.3]
- **ECALL** → *environment call from M-mode* (11). **EBREAK** → *breakpoint* (3) [P §3.3.1].
- **MRET** [P §3.3.2]: `pc ← mepc`, `MIE ← MPIE`, `MPIE ← 1`, `MPP ← M` (the least-privileged
  supported mode is M, because U-mode is absent) [P §3.1.6.1].
- **WFI** [P §3.3.3]: see §5.5.
- SRET and other privileged encodings raise illegal instruction.

## 3. Control and status registers [P §2, §3.1]

All CSRs are machine-level. Addresses come from the CSR listing [P §2.2]. "RO-0" means read-only
zero.

| CSR | Addr | Implementation | Ref |
|---|---|---|---|
| mvendorid | 0xF11 | RO-0 (non-commercial) | [P §3.1.2] |
| marchid | 0xF12 | RO-0 | [P §3.1.3] |
| mimpid | 0xF13 | RO-0 | [P §3.1.4] |
| mhartid | 0xF14 | RO-0 | [P §3.1.5] |
| mconfigptr | 0xF15 | RO-0 (no configuration structure) | [P §3.1.17] |
| mstatus | 0x300 | MIE (bit 3), MPIE (bit 7) writable; MPP (bits 12:11) reads `11` (M only, WARL); all other bits RO-0 (no S/U, MPRV, FS, VS, XS, SD, TW…) | [P §3.1.6] |
| misa | 0x301 | RO (writes ignored; WARL allows this [P §3.1.1]): MXL=1 (32-bit), extension bit I only — see S-3 below | [P §3.1.1] |
| mie | 0x304 | MSIE (3), MTIE (7), MEIE (11) writable; others RO-0 | [P §3.1.9] |
| mtvec | 0x305 | BASE writable (bits 31:2), MODE RO-0 (direct only) | [P §3.1.7] |
| mstatush | 0x310 | RO-0 (MBE=0: little-endian; no MPV/GVA/MDT) | [P §3.1.6] |
| mscratch | 0x340 | RW, 32 bits | [P §3.1.13] |
| mepc | 0x341 | RW; bits 1:0 RO-0 (IALIGN=32) | [P §3.1.14] |
| mcause | 0x342 | RW; Interrupt bit 31 and Exception Code bits 3:0 (WLRL) | [P §3.1.15] |
| mtval | 0x343 | RW, 32 bits; written on traps as in §5.3 | [P §3.1.16] |
| mip | 0x344 | MSIP (3), MTIP (7), MEIP (11): read-only views of the TIMER and IRQC lines | [P §3.1.9] |
| mcycle / mcycleh | 0xB00 / 0xB80 | 64-bit cycle counter, writable | [P §3.1.10] |
| minstret / minstreth | 0xB02 / 0xB82 | 64-bit retired-instruction counter, writable | [P §3.1.10] |
| mhpmcounter3–31(h) | 0xB03–0xB1F, 0xB83–0xB9F | RO-0 (allowed by [P §3.1.10]) | [P §3.1.10] |
| mhpmevent3–31 | 0x323–0x33F | RO-0 | [P §3.1.10] |

- **Not implemented** (accesses raise illegal instruction):
  - medeleg and mideleg, which should not exist with only M-mode [P §3.1.8];
  - mcounteren and menvcfg, which only exist with U-mode [P §3.1.11, §3.1.18];
  - mcountinhibit, which is optional: "behaves as though the register were set to zero" [P §3.1.12];
  - mseccfg, PMP CSRs, and all S/U-mode and debug CSRs.
- **misa extensions [decision S-3].**
  - Bit 8 ("I") is set.
  - Bit 1 ("B") stays 0. [P §3.1.1] says: "When the "B" bit is 1, the implementation supports the
    instructions provided by the Zba, Zbb, and Zbs extensions. When the "B" bit is 0, it indicates
    that the implementation might not support one or more of [them]". This core implements Zbb only.
  - So misa = `0x4000_0100` (MXL=1, I). Software learns about Zbb from the platform description, not
    from misa.
- **mcycle and minstret** count every cycle and every retired instruction. That includes cycles
  stalled in WFI while the clock runs, but not cycles while the CORE clock is gated (the counter's
  clock is stopped). A CSR write to mcycle or minstret by an instruction overrides that
  instruction's own increment [P §3.1.10: "Any CSR write takes effect after the writing instruction
  has otherwise completed"].
- **Reset values** follow [P §3.4]: `mstatus.MIE`=0, `mcause`=0 (this design does not tell reset
  causes apart in mcause; SYSCTRL does that, §7). Every other CSR also resets to 0. That is a
  stronger guarantee than [P §3.4] requires ("all other hart state is UNSPECIFIED"); it is chosen so
  that power-aware simulation is deterministic.

## 4. Memory map and bus behaviour
- **Address map:** see `docs/MEMORY_MAP.md`. Summary:
  - BOOTROM at `0x0000_0000` (reset vector);
  - IMEM at `0x1000_0000`;
  - DMEM at `0x2000_0000`;
  - APB peripherals at `0x4000_0000`, 4 KB per slot.
- **Two memory configurations.** Every reported number names the configuration it came from
  (BRIEF A3).
  - **GDS:** IMEM and DMEM are each one `sky130_sram_1kbyte_1rw1r_32x256_8` (1 KB).
  - **SIM:** behavioural models of the same 1rw1r interface, 32 KB each. **[decision S-4]**
- **Fetch** may use BOOTROM and IMEM only. Fetching from DMEM, APB or unmapped space raises
  *instruction access fault* (1). mtval = the faulting address.
- **Loads and stores** may use all four regions.
  - The APB window accepts 32-bit aligned accesses only. A byte or halfword access there raises
    *load/store access fault* (5/7) without reaching the bus.
  - So do unmapped addresses and APB slots with no peripheral.
  - An APB `PSLVERR` response also gives an access fault. For example, P2's PMU answers writes to
    RO registers and unknown addresses with `PSLVERR`.
  - Stores to BOOTROM raise a store access fault.
- **Self-modifying code.** There is no instruction cache and Zifencei is not implemented. A store to
  IMEM is visible to fetches of instructions that enter the pipeline after the store has completed.
  The boot loader relies on this (§7); it never fetches from a word it has just written within the
  same 2 instructions (MICROARCH §5).

## 5. Traps and interrupts [P §3.1.6.1, §3.1.7, §3.1.9, §3.1.14–3.1.16]

### 5.1 Trap causes implemented ([P §3.1.15] Table 14)
| mcause | Cause | mtval |
|---|---|---|
| 0x8000_0003 | Machine software interrupt (MSIP) | 0 |
| 0x8000_0007 | Machine timer interrupt (MTIP) | 0 |
| 0x8000_000B | Machine external interrupt (MEIP, from IRQC) | 0 |
| 0 | Instruction address misaligned | target address |
| 1 | Instruction access fault | fetch address |
| 2 | Illegal instruction | the instruction bits **[decision S-5]** |
| 3 | Breakpoint (EBREAK) | pc of the EBREAK **[decision S-5]** |
| 4 / 6 | Load / store address misaligned | effective address |
| 5 / 7 | Load / store access fault | effective address |
| 11 | Environment call from M-mode | 0 |

### 5.2 Priorities
- **Interrupts, if several are pending and enabled:** MEI > MSI > MTI [P §3.1.9].
- **Synchronous exceptions** follow [P §3.1.15] Table 15. For this core:
  1. instruction access fault;
  2. illegal instruction, instruction address misaligned, ECALL and EBREAK (one instruction can only
     raise one of these);
  3. load/store address misaligned;
  4. load/store access fault.
- **Interrupts vs exceptions:** an interrupt is taken *before* the instruction it is attached to, so
  that instruction does not execute and cannot raise an exception (MICROARCH §6).

### 5.3 Trap entry (into M-mode; this is the only mode)
In one step [P §3.1.6.1, §3.1.7, §3.1.14–3.1.16]:
1. `mepc` ← the pc of the trapping instruction. For an interrupt, it is the pc of the first
   instruction that did not execute.
2. `mcause` ← cause (§5.1). `mtval` ← the value in §5.1.
3. `mstatus.MPIE` ← `mstatus.MIE`; `mstatus.MIE` ← 0; `mstatus.MPP` ← M.
4. `pc` ← `mtvec.BASE` (direct mode: all traps go to BASE) [P §3.1.7, Table 13].

Rules:
- The trapping instruction does not retire.
- It does not write `rd`, memory or any CSR, and does not increment `minstret`.
- All older instructions complete; no younger instruction has any effect (precise traps,
  MICROARCH §6).

### 5.4 Interrupt taking [P §3.1.9]
- **Condition:** interrupt *i* is taken when `mstatus.MIE`=1 and bit *i* is set in both `mip` and
  `mie`. Because the core is always in M-mode, nothing else is needed.
- **Re-evaluation:** the condition is checked again after MRET and after a CSR write to `mstatus`
  or `mie`, as [P §3.1.9] requires. The instruction after such a write sees the new enables.
- **Sources** are levels:
  - MTIP = (mtime ≥ mtimecmp), unsigned 64-bit [P §3.2.1];
  - MSIP = TIMER.MSIP;
  - MEIP = |(IRQC.PENDING & IRQC.ENABLE).

  Software clears each one at its source, never in `mip`, which is read-only [P §3.1.9].

### 5.5 WFI [P §3.3.3]
- **When WFI reaches execute:**
  - If `(mip & mie) ≠ 0`, it completes like a NOP.
  - Otherwise the core **stalls**: WFI stays in the execute stage, and older instructions drain.
- **The stall ends when `(mip & mie) ≠ 0`, whatever `mstatus.MIE` is.**
  - WFI must be "unaffected by the global interrupt bits ... but should honor the individual
    interrupt enables" [P §3.3.3].
  - WFI then retires.
  - If `mstatus.MIE`=1, the interrupt is taken on the *next* instruction, so `mepc` = pc(WFI)+4,
    as [P §3.3.3] states.
  - If `MIE`=0, execution simply continues at pc+4. Software then reads `mip` to see what woke it
    ("WFI with interrupts disabled", INTERVIEW).
- **While stalled, the core reports `core_idle`=1.** This is the core's half of the IDLE handshake
  with the PMU (§8.2). Without a PMU request, the core just waits with its clock running.
- WFI is never illegal, because there is no TW bit and no U-mode.

## 6. Reset and boot [P §3.4]
- **Reset.** On reset the core is in M-mode with `mstatus.MIE`=0 and `pc` = `0x0000_0000` (the
  BOOTROM base, the implementation-defined reset vector [P §3.4]). CSRs are reset as in §3.
- **Core domain resets.** The core domain has two reset sources, combined with AND:
  - the synchronised `rst_n` pin (cold reset);
  - the PMU's `rst_n[CPU]` output (warm reset at the end of a DEEP_SLEEP power-up).

  SYSCTRL records which one it was (§7).

## 7. Boot ROM and warm boot **[decision S-6]**

**Why a boot ROM is needed.** The GDS configuration has SRAM only, with no flash, so something must
put the program into IMEM.

**Boot ROM.** A small boot ROM (≤ 256 B, synthesised from `sw/boot/`; the size comes from the build)
runs from the reset vector:
1. **Warm path.** If `SYSCTRL.RESET_CAUSE.WARM`=1, IMEM still holds the program (MEM is always
   powered, §8), so it jumps straight to `IMEM_BASE`.
2. **Simulation path.** If `SYSCTRL.BOOT.SEL`=1 (strap pin), the memory was preloaded by the
   testbench, so it jumps to `IMEM_BASE`.
3. **Loader path.** Otherwise it runs a UART loader:
   - It waits until the PMU reports PERI ON (D-022), then enables the UART at the reset baud
     divisor.
   - It sends the prompt `>`. The host must wait for it before sending (D-023).
   - Format: a 4-byte little-endian length, then the bytes, which it stores to IMEM through the
     D-port.
   - It echoes the 32-bit sum of the bytes (little-endian), waits until it has been sent, then
     jumps to `IMEM_BASE`.
   - Implementation: `sw/boot/boot.S`. The ROM image is generated by `scripts/gen_bootrom.py`
     (216 of 256 bytes).

**After the jump.** `crt0` reads `SYSCTRL.RESET_CAUSE` and `SYSCTRL.WAKE_SRC` to tell a cold boot
from a warm wake, and why it woke (BRIEF A3). **Warm boot is used instead of CPU retention:** the
CORE domain has no retention flops, and all state that must survive sits in AON (SYSCTRL.SCRATCH)
or MEM.

## 8. Power management

### 8.1 Domains
| Domain | Contents | PMU domain | IDLE | DEEP_SLEEP |
|---|---|---|---|---|
| AON | PMU, TIMER, SYSCTRL, UART-RX wake detector, reset synchroniser, ICG cells, isolation clamps | — (always on) | on | on |
| CORE | core, boot ROM, crossbar, APB bridge, IRQC | PD0 `CPU`, `HAS_RET`=0 | CLK_GATED | OFF |
| PERI | UART (TX/RX, FIFOs, registers), GPIO | PD2 `PERI`, `HAS_RET`=0 | ON | OFF |
| MEM | IMEM, DMEM SRAMs | — (always powered; clock = CORE clock) | clock stopped | powered, clock stopped |
| — | (P2's PD1 `DSP` is not used: tied to an always-accepting Q-Channel stub and a switch model) | PD1 | CLK_GATED | OFF |

The **[decision S-7]** points behind this table:
- **PMU domain mapping.** P2's PMU has three domains (`CPU`, `DSP`, `PERI`; P2 SPEC §3.2).
  - CORE maps to `CPU` and PERI maps to `PERI`.
  - `DSP` has no logic in this SoC and is tied off.
  - `HAS_RET` = `3'b000`, so P2's "RET" targets are satisfied by OFF (P2 SPEC §3.2, target
    satisfaction rule). This gives the warm-boot behaviour the brief asks for.
- **What happens in P2's other modes.** SLEEP puts CORE in RET, which is satisfied by OFF, and PERI
  in CLK_GATED. SHUTDOWN turns everything off. Both modes are available, but firmware uses only RUN,
  IDLE and DEEP_SLEEP.
- **MEM stays powered in every mode.** That is what makes warm boot possible without reloading the
  program. Its clock is the CORE clock, so it stops in IDLE and DEEP_SLEEP.

**Power-up order.** After reset, and after every DEEP_SLEEP wake, the PMU powers CORE up before
PERI (P2's inrush arbiter, one domain at a time). The core therefore starts while PERI is still
isolated, and an access to the UART or GPIO then gets an error response (D-021). Software must wait
until `PMU.PD_STATE` shows PERI ON and not busy (`crt0` → `hal_wait_peri()`, the boot loader;
D-022).

**Power gating is behavioural only.** As in P2 (BRIEF A6, "out of scope"), it is a behavioural
power-aware model:
- When a domain is OFF, simulation corrupts its state (flops to X, or random under a plusarg), and
  isolation clamps its outputs to 0.
- No switch cells are placed in the layout. `upf/lp_rv32.upf` describes the intent and carries the
  "not tool-verified" header.

### 8.2 IDLE (clock gating) **[decision S-8]**
P2's PMU has no "core idle" input. Modes are requested by writing `MODE_REQ`. Each domain is
controlled through an ARM Q-Channel (P2 SPEC §2.2), and **the core is the Q-Channel device for PD0**.

**Firmware sequence:**
1. Set `PMU.WAKE_MODE`=RUN and `PMU.WAKE_MASK` (bit 0 = core interrupt).
2. Write `PMU.MODE_REQ`=IDLE.
3. Execute `WFI`.

**Core's Q-Channel device behaviour (P2 SPEC §2.2 rules):**
- **While `QREQn`=0:**
  - **Accept** (`QACCEPTn`←0) only once `core_idle`=1, i.e. WFI is stalled with the pipeline
    drained and no bus transaction outstanding (§5.5).
  - **Deny** (`QDENY`←1) if `(mip & mie) ≠ 0` before it accepts. The PMU then leaves PD0 ON and
    sets `IRQ_STATUS.DENY`, and the WFI completes normally.
- **Back in Q_RUN:** after `QREQn`=1 the core sets `QACCEPTn`←1.

**Where the timing comes from.** The PMU waits up to `TMO_QCH` cycles for an answer; a timeout is a
PMU FAULT. Firmware executes `WFI` immediately after the `MODE_REQ` write (the HAL does it in
straight-line code). The cycle count from write to accept is measured in Phase 4, not assumed.

**Gating.**
- The PMU then drops `clk_en[CPU]`, and the ICG `sky130_fd_sc_hd__dlclkp` stops the CORE and MEM
  clocks.
- PERI stays ON, so the UART keeps receiving and GPIO keeps detecting edges.

**Wake.**
- `wake_irq[0]` = `|(mip & mie)` is computed from the always-valid interrupt lines and the core's
  `mie` flops. Those flops hold their value while gated, and the AND has no clock.
- When it rises, the PMU sets `MODE_REQ` ← `WAKE_MODE` = RUN and runs CG-up: the clock comes back
  and Q_EXIT follows.
- The stalled WFI sees `(mip & mie) ≠ 0`, retires, and the interrupt is taken if `MIE`=1 (§5.5).
- SYSCTRL.WAKE_SRC.CORE_IRQ is set.

**Brief wording vs this design.** The brief says "WFI asserts a core-idle signal; the PMU gates the
core clock". Here `core_idle` gates the Q-Channel accept, and the request comes from the `MODE_REQ`
write. Plain `WFI` without the write stalls with the clock running. The alternative, a hardware
"auto-IDLE on WFI" input, would need a change to P2's PMU (outside this repo).

### 8.3 DEEP_SLEEP and warm boot
**Firmware sequence:**
1. Set `WAKE_MODE`=RUN.
2. Set `WAKE_MASK` to enable bit 1 (UART RX) and/or bit 2 (timer).
3. Set `SYSCTRL.UART_WAKE_EN` and/or program `mtimecmp`.
4. Write `MODE_REQ`=DEEP_SLEEP, then execute `WFI`.

**What follows:**
1. The core accepts the Q-Channel request as in §8.2.
2. The PMU runs the P2 power-down sequence for PD0 (P2 SPEC §4.1: clock off, isolate, reset, switches
   off) and also powers PERI down.
3. **Wake sources** (AON): `wake_irq[1]` = UART-RX start-bit detector (§8.4), `wake_irq[2]` =
   (mtime ≥ mtimecmp).
4. On a wake, the PMU powers PERI and CORE back up (P2 SPEC §4.3) and releases `rst_n[CPU]`.
5. The core starts at the reset vector.
6. SYSCTRL sets `RESET_CAUSE.WARM` and the `WAKE_SRC` bit(s), and the boot ROM takes the warm path
   (§7).

**Lost state.** All CORE and PERI state is lost: registers, CSRs, UART FIFOs and settings, GPIO
settings. Firmware must keep anything it needs in DMEM/IMEM or `SYSCTRL.SCRATCH`.

### 8.4 UART-RX wake detector (AON)
- **Function:** a 2-flop synchroniser on the RX pin plus a falling-edge detector, enabled by
  `SYSCTRL.UART_WAKE_EN`.
- **The waking byte is lost.** The UART receiver is in PERI, which is OFF until the wake completes.
  The wake only says that a byte started. Firmware tells the sender to retry, e.g. by printing a
  prompt. **[decision S-9]**

## 9. Peripherals
All registers are in `docs/MEMORY_MAP.md`. Behaviour beyond the register descriptions:

**UART (16550-lite)**
- Supports 8N1 only. The TX FIFO and RX FIFO are 16 bytes each.
- The bit period is `BAUD_DIV+1` cycles of the PERI clock.
- **RX timing:**
  - A start bit is accepted if RX is still 0 at its middle, i.e. `(BAUD_DIV+1)/2` cycles after the
    falling edge.
  - Data bits are sampled every `BAUD_DIV+1` cycles after that, at their middle.
  - The stop bit is sampled the same way; a 0 there is a framing error.
- The unit tests measure baud accuracy as the bit period on the TX pin in cycles (BRIEF A5).

**TIMER**
- mtime counts the AON clock divided by `PRESCALE+1`.
- A write to MTIME_LO/HI or MTIMECMP_LO/HI takes effect on the next cycle.
- Firmware writes the 64-bit compare with the usual sequence: write the high word with all ones,
  then the low word, then the real high word. This avoids a false MTIP [P §3.2.1].

**GPIO**
- Each pin has a 2-flop synchroniser.
- Edges are detected on the synchronised value.
- An output pin also sees its own edges.

**IRQC**
- Sources: 0 UART, 1 GPIO, 2 PMU (`irq` output, P2 REGMAP `IRQ_STATUS`/`IRQ_EN`); 3–7 tied to 0.

**SYSCTRL**
- Lives in AON. Its registers are reset only by the cold reset.
- `RESET_CAUSE.WARM` is set when the CPU domain powers up again after the first power-up following
  a cold reset (D-018).
- `WAKE_SRC` records a rising edge on every wake input, including inputs the PMU masks.
  Firmware clears it before sleeping (D-027).

**Bus-to-APB bridge**
- The core-side request is a valid/ready handshake. The APB side follows APB3 (ARM IHI 0024E; the
  same subset as P2 SPEC §2.1): SETUP, ACCESS, wait states via `PREADY`, and `PSLVERR`.

## 10. Reused IP
- **ALU (P1, `vikyathhj-ui/prefix-adder-alu-sky130`, formerly `32bit-RTL-To-GDS`)
  [decision S-2].**
  - P1's `alu_top` registers its inputs and outputs (latency 2 with PIPE=0, P1 SPEC section 2). That
    cannot sit inside a single-cycle execute stage with forwarding.
  - So P6 vendors P1's combinational units unchanged from `main` at a pinned commit:
    - `adder` with the `adder_hc` Han-Carlson architecture, P1's signed-off recommendation
      (P1 `docs/PPA_REPORT.md` §6, D-031);
    - `shifter`;
    - `clz` and `clz_tree`;
    - `cpop`;
    - `pg_black` and `pg_gray`;
    - `alu_pkg`.
  - A new combinational wrapper `rtl/core/core_alu.sv` composes these units the way `alu_top`'s S1/S2
    logic does, without its registers.
  - The ALU opcode encoding is P1's (`alu_pkg`, opcodes 0–26).
  - `vendor/VENDOR.md` records the repo, hash, date and P1's MIT licence.
- **PMU (P2, `vikyathhj-ui/multipower`, to be renamed `soc-pmu-sequencer`).**
  - Vendored in Phase 3, once P2 is merged (D-006).
  - The register map used here is a provisional copy of P2's `scripts/regmap.yaml` from the P2 work
    branch (commit `5fe30e0`), recorded in `vendor/VENDOR.md`.
  - **It is not P2's `master` copy, for a reason:**
    - On `master`, the `pd_state` enum keys `ON`/`OFF` are bare YAML. YAML 1.1 reads them as
      booleans, so the generated `docs/REGMAP.md` and `sw/pmu_regs.h` show `True`/`False`.
    - P2's work branch has already fixed this (commit `dc12040`), but the fix isn't merged yet.
  - It is re-pinned to P2's merged commit when the PMU is vendored.

## 11. Verification hooks
- **RVFI port** (riscv-formal `docs/source/rvfi.rst`):
  - one retire channel (`NRET`=1);
  - `rvfi_trap` set as that document requires (illegal, misaligned memory, misaligned jump target);
  - `rvfi_intr` on the first instruction of a handler;
  - CSR ports for the CSRs listed in `formal/checks.cfg`.

  The port is compiled only with `` `define RISCV_FORMAL ``.
- **Defines** set in the riscv-formal configuration: `RISCV_FORMAL_ALIGNED_MEM` (S-1).
- **riscv-formal options:**
  - `isa rv32iZbb`, which is supported by the installed riscv-formal (`insns/isa_rv32iZbb.txt`);
  - `solver yices` (D-002).
- **Arch tests:**
  - riscv-arch-test 3.10.0 suites `rv32i_m/I`, `rv32i_m/B` (Zbb tests only), and `rv32i_m/privilege`
    where they apply to an M-only core with Zicsr.
  - The reference model (Sail or Spike) is settled in Phase 3 (D-003).
  - The reference model is configured to match S-1 and S-5.

## 12. Open items carried to later phases
- **Phase 3:** the RISCOF reference model (D-003); PMU vendoring and its exact port list (P2 MICROARCH).
- **Phase 5:** STA corners for the SRAM macro, which has only a TT liberty file (D-005, **[decision S-10]**).
  - Proposal: run the multi-corner STA (all std-cell corners) using the TT SRAM liberty for the macro
    in every corner, and label macro paths "SRAM timing: TT model only".
  - In addition, report each corner's worst register-to-register path that does not touch the macro,
    so the logic's corner behaviour is shown on its own.
