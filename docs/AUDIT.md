# Audit of the legacy design (`legacy/`)

The original repo held a single-cycle 4-bit core with a UART transmitter, written for an Intel MAX 10
FPGA (`legacy/uuart.qsf`: `10M50DAF484C7G`). It moved to `legacy/` unchanged in the lp-rv32 rework
(`git mv`, history kept). Nothing in it is reused.

Every finding below is backed by `scripts/legacy_probe.sh`, which writes `results/legacy_probe.txt`
(section numbers L1–L5 refer to that file). The probe uses the shipped testbench as is, plus a new
observing testbench, `legacy/tb_probe.v`, that runs with the same 50 MHz clock, 100 ns reset and 1 ms
run length. Reproduce with:

```bash
docker exec -w /foss/projects/Single-Cycle-4-bit-RISC-Core-with-UART-Peripheral iic-osic \
  bash -lc 'scripts/legacy_probe.sh'
```

## What the legacy design is

| Block | File | What it is |
|---|---|---|
| PC | `PC_5Bit.v` | 5-bit counter; +1 or load a jump address |
| ROM | `Inst_ROM.v` | 32 × 8-bit, combinational read, program in an `initial` block |
| Decode | `ControlUnit.v` | opcode = `instr[7:5]`: `000` LOADI, `001` ADD, `010` OUT, `011` JUMP, others NOP |
| Register file | `RegFile_4x4.v` | 4 × 4-bit, 2 async reads, 1 sync write |
| ALU | `ALU_4Bit.v` | ADD/SUB/AND/OR; only ADD is reachable from the decoder |
| UART | `UART_TX.v` | TX only, fixed divider, **4 data bits**, no RX, no FIFO, no interrupts |

## Findings

### F1. The testbench only applies stimulus; it checks nothing (L1)
`legacy/RISC_UART_TOP_tb.v` generates a clock, holds reset for 100 ns, waits 1 ms and calls `$stop`.
It has **0** lines that print, compare or assert anything. When run, the only output is the
simulator's own `$stop called` message. A broken design passes this testbench, and F2–F4 show
the design is in fact broken.

### F2. The ROM program does not match its own comments (L2, L3 P1)
Decoding each ROM word with `ControlUnit`'s table (`opcode = instr[7:5]`):

| Address | Word | Comment says | Actually decodes to |
|---|---|---|---|
| 0 | `0x0D` | LOADI R1, 5 | LOADI R1, 5 ✔ |
| 1 | `0x16` | LOADI R2, 6 | LOADI R2, 6 ✔ |
| 2 | `0x5C` | ADD R1, R2 | **OUT R3** (opcode `010`) |
| 3 | `0x98` | OUT R1 | **NOP** (opcode `100`) |
| 4 | `0xC3` | JUMP 3 | **NOP** (opcode `110`) |

Two problems:
- The ADD never executes. The final register values are R1=5 and R2=6, not R1=0xB (L3 P4).
- There is no working JUMP, so the PC runs past the program.

Only 7 of the 32 ROM entries are initialised. Addresses 7–31 read as `x` in simulation (L3 P2) and
as undefined contents on hardware. The PC wraps every 32 cycles, so the core re-executes this
sequence plus 25 undefined words.

### F3. The UART never transmits (L3 P3–P4)
- `TX_Start` is a combinational decode of the current instruction, so it is high for exactly one
  cycle per OUT.
- The UART's FSM only advances on `clk_enable`, a one-cycle pulse every 5208 cycles
  (`UART_TX.v:55`). It only looks at `TX_Start` in IDLE on that pulse (`UART_TX.v:59`).
- There is no handshake or latch between them, so a start request is seen only if the two
  one-cycle pulses happen to line up.

In the 1 ms run, `TX_Start` was high on **1563** cycles, **0** of them lined up with `clk_enable` in
IDLE, and **0** start bits appeared on `TX_PIN`. Even with the ROM fixed, this "fire and hope"
interface would drop most OUT instructions.

### F4. The UART frame is not a standard format (L4)
- The data path is 4 bits (`TX_Data_In[3:0]`, stop after `bit_count == 3`).
- The frame is start + 4 data + stop, not 8N1, so a standard PC terminal cannot decode it.
- The baud rate is a fixed constant: 5208 cycles per bit, which gives 9600.6 baud at the
  testbench's 50 MHz clock (L4).
- There is no RX path, no FIFO, no status register and no interrupt.

### F5. Not an ISA and not portable to ASIC flows
- The 8-bit custom encoding has no toolchain, so programs are hand-assembled. F2 shows how
  error-prone that is.
- Initialising the ROM in an `initial` block works for FPGA synthesis but not for an ASIC flow.
- The project is a Quartus/MAX 10 project with no constraints, lint or ASIC flow.

## What the rework does differently (pointers to the brief)
| Legacy gap | lp-rv32 answer (docs/BRIEF.md) |
|---|---|
| F1 stimulus-only TB | riscv-formal RVFI proofs, RISCOF arch tests, cocotb unit + system tests with a UART monitor (A5) |
| F2 hand-assembled custom ISA | RV32I + Zicsr + Zbb, compiled with GCC (A2, A4) |
| F3 dropped TX requests | APB UART with 16-byte TX/RX FIFOs and status/interrupts (A3) |
| F4 4-bit frame, fixed baud | 8N1, programmable divisor, baud accuracy tested (A3, A5) |
| F5 FPGA-only | LibreLane on sky130A with OpenRAM SRAM macros, signoff (A6) |

## Environment findings that affect the plan (from `results/env_check.txt`)
These come from the Phase 0 environment check rather than the legacy code. They are recorded here so
they can be traced back, and each has a `docs/DECISIONS.md` entry.

- **SRAM liberty corners.** The installed `sky130_sram_1kbyte_1rw1r_32x256_8` has one liberty file,
  `TT_1p8V_25C`. The brief's "fmax at every corner" (A6) cannot include SS/FF timing for the macro
  itself. To be settled in the Phase 1 spec (D-005).
- **riscv-arch-test moved off RISCOF.** The current `main` uses the ACT4 framework and states that it
  replaces `riscof` (`ext/riscv-arch-test` CHANGELOG, 4.0 entry). The checkout is pinned at tag
  `3.10.0`, the last RISCOF-based release (D-003).
