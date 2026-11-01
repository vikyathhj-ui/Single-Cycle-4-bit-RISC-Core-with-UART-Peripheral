# lp-rv32 microarchitecture

Status: **Phase 1, confirmed (D-007).** This is the plan the Phase 2 RTL implements. Any change made during
Phase 2 is recorded here and in `docs/DECISIONS.md`. Behaviour is defined in `docs/SPEC.md` (cited
as SPEC §n). This file says how it is built.

## 1. Pipeline overview

Three stages, in order, one instruction per stage (BRIEF A2):

```
          cycle n               cycle n+1                               cycle n+2
  ┌──────────────────┐  ┌───────────────────────────────────────┐  ┌──────────────────────────────┐
  │ IF               │  │ ID/EX                                 │  │ MEM/WB                       │
  │ pc_f ──► I-port  │  │ instr ◄── SRAM dout1 / ROM (registered│  │ load data ◄── SRAM dout0 /   │
  │ address (SRAM    │  │          address, read on negedge)    │  │   ROM / APB rdata            │
  │ port1 or ROM)    │  │ decode, illegal check                 │  │ align + sign/zero-extend     │
  │ next pc = pc_f+4 │  │ regfile read (2R, flops)              │  │ regfile write (1W) at end    │
  │  or redirect     │  │ forward mux ◄── MEM/WB result         │  │ minstret++ (retire)          │
  │                  │  │ core_alu (P1 units), branch compare   │  │ APB: wait for PREADY/PSLVERR │
  │                  │  │ target / next-pc, load/store address  │  │ trap from access fault       │
  │                  │  │ D-port request (SRAM port0 / bridge)  │  │                              │
  │                  │  │ CSR read/modify/write, trap decision  │  │                              │
  └──────────────────┘  └───────────────────────────────────────┘  └──────────────────────────────┘
        IF/ID: pc_d, valid          ID/EX→MEM/WB register: pc, rd, result, load info, valid
```

- **IF** drives the fetch address. The SRAM (or boot-ROM) address register is effectively the IF/ID
  pipeline register, because the macro registers its inputs on the rising edge (§3).
- **ID/EX** decodes and executes. All architectural side effects of non-memory instructions happen
  at the end of this stage: CSR writes, trap entry and the pc redirect. Every one of them is
  suppressed if the MEM/WB instruction traps in the same cycle (§6). Stores to SRAM are also issued
  here.
- **MEM/WB** finishes loads (and APB stores), writes the register file and retires.

## 2. Datapath blocks

| Block | File (Phase 2) | Notes |
|---|---|---|
| Fetch / next-pc | `rtl/core/core_fetch.sv` | pc_f register. next = redirect target if a trap, MRET or taken branch/jump is in ID/EX; else pc_f+4; else hold (stall) |
| Decoder | `rtl/core/core_decode.sv` | RV32I + Zicsr + Zbb + MRET/WFI/ECALL/EBREAK/FENCE; produces the P1 ALU opcode (alu_pkg 0–26) |
| Register file | `rtl/core/core_regfile.sv` | 31 × 32 flops, x0 hard-wired 0, 2 async reads, 1 write at the end of MEM/WB |
| ALU | `rtl/core/core_alu.sv` | combinational wrapper over vendored P1 units: `adder` (ARCH = HC), `shifter`, `clz`, `cpop` (SPEC §10) |
| Branch unit | in `core_ex.sv` | compare uses the ALU's SLT/SLTU/SUB result paths. Target = pc + imm (separate 32-bit adder; JALR: rs1 + imm, bit 0 cleared [U §2.5.1]) |
| LSU | `rtl/core/core_lsu.sv` | address = rs1 + imm (the ALU adder); misalignment check; byte strobes; store data replication; load align/extend in MEM/WB |
| CSR file + trap unit | `rtl/core/core_csr.sv` | SPEC §3; trap entry/MRET (SPEC §5.3); interrupt select (MEI > MSI > MTI) |
| RVFI | `rtl/core/core_rvfi.sv` | under `` `ifdef RISCV_FORMAL ``; one retire channel from MEM/WB |
| Q-Channel device | `rtl/core/core_qch.sv` | SPEC §8.2: accept when `core_idle`, deny when `(mip & mie) ≠ 0` |

## 3. Memory timing (OpenRAM macro) and its consequence **[decision M-1]**
`sky130_sram_1kbyte_1rw1r_32x256_8` behaviour, taken from its Verilog model
(`$PDK_ROOT/sky130A/libs.ref/sky130_sram_macros/verilog/…32x256_8.v`) and liberty file:
- **Inputs:** `csb`, `web`, `wmask`, `addr` and `din` are registered on the **rising** edge of
  `clk0`/`clk1`.
- **Reads and writes** happen on the **falling** edge (`always @(negedge clk0)`). `dout` updates
  after the falling edge plus the read delay. The liberty models `dout` as `timing_type :
  falling_edge`.
- **`dout` is not held:** the model drives it to X `T_HOLD` after the next rising edge. Read data
  must therefore be used, or captured, by the end of the cycle after the address edge.

**Consequence for a 3-stage pipeline:**
- The instruction word is available only in the *second half* of the ID/EX cycle. The critical path
  is therefore about: clk↓ → dout1 → decode → regfile/forward → ALU → (branch redirect to the SRAM
  address, or load/store address to SRAM port0) → setup before clk↑.
- The same applies to load data in MEM/WB (dout0 → align → regfile write).

**Options considered:**
- (a) Accept the half-cycle budget and keep 3 stages. The brief asks for exactly 3.
- (b) Add a fetch-register stage, which makes 4 stages.
- (c) Clock the SRAMs on the inverted clock.

**Choice:** (a). The cost will show up as a lower fmax. It is measured in Phase 5 and explained
there, not estimated here. The SIM behavioural memories follow the same timing contract (registered
inputs, data valid in the next cycle) so the RTL behaves identically in both configurations.

**Boot ROM:** same contract. Its address is registered on the rising edge, and its output is
combinational from the registered address.

## 4. Hazards

**Distances.** Distance *d* means the consumer is *d* instructions after the producer.
- **Register file write timing:** the register file is written at the end of MEM/WB. A consumer at
  distance ≥ 2 therefore reads the new value from the register file.
- **Forwarding path:** distance 1 needs the single forwarding path MEM/WB → ID/EX.

| # | Hazard | Example | Detection | Resolution | Penalty |
|---|---|---|---|---|---|
| H1 | RAW, ALU/CSR/JAL result → next instr | `add x1,..` ; `sub x2,x1,..` | MEM/WB.rd = ID/EX.rs*, rd ≠ 0, MEM/WB not a load | forward the MEM/WB result into the ID/EX operand mux | 0 |
| H2 | RAW at distance 2 | `add x1` ; `nop` ; `sub ..,x1` | — | register file already written at the end of the producer's MEM/WB | 0 |
| H3 | **Load-use** | `lw x1,0(x2)` ; `add x3,x1,x4` | MEM/WB is a load, MEM/WB.rd = ID/EX.rs*, rd ≠ 0 | **stall ID/EX and IF one cycle** (a bubble goes into MEM/WB). Load data is only valid after the falling edge (§3), so forwarding it into the ALU would add a second half-cycle path | 1 cycle |
| H4 | Taken branch / JAL / JALR | `beq` taken | resolved in ID/EX | predicted not-taken. On a taken branch, flush the instruction fetched behind it (it arrives as a bubble) and redirect IF | 1 cycle (taken), 0 (not taken) |
| H5 | Trap / MRET redirect | `ecall`, interrupt, `mret` | ID/EX (or MEM/WB for access faults, §6) | flush younger instructions, redirect to mtvec / mepc | 1 cycle (2 if the trap comes from MEM/WB) |
| H6 | APB access in MEM/WB | `lw` from UART | bridge not done | stall all stages until `PREADY` | APB wait states + bridge cycles (measured) |
| H7 | CSR → CSR | `csrw mie` ; `csrr t0, mie` | — | CSR written at the end of ID/EX; the next instruction reads the new value | 0 |
| H8 | minstret read with an older instruction retiring | `addi` ; `csrr t0, minstret` | MEM/WB valid and not trapping in the same cycle | read value + 1 (that instruction retires this cycle, before the reader) | 0 |
| H9 | Interrupt-enable write → interrupt | `csrsi mstatus, 8` with MTIP pending | — | re-evaluated for the next instruction in ID/EX (SPEC §5.4) | 0 |
| H10 | WFI | `wfi` with no enabled interrupt pending | ID/EX holds WFI, `(mip & mie) = 0` | stall in ID/EX; the pipeline drains; `core_idle` = 1 once MEM/WB is empty | until wake |
| H11 | Store to IMEM, then fetch of that word | loader | none in hardware | SPEC §4 software rule: no fetch of a just-written word within 2 instructions | — |

**Branch penalty and CPI.** The CPI contribution is 1 cycle per taken control transfer plus 1 per
load-use pair, plus APB wait states. Phase 2/4 measure the hazard counts with simulation counters
(taken branches, load-use stalls) on real programs. The CPI is computed from those counts, never
assumed.

## 5. Memory ports and the crossbar
- **I-port:**
  - The request is the IF address, every cycle, unless stalled.
  - BOOTROM and IMEM port1 are reachable. Other addresses give an instruction access fault, which the
    fetch unit flags on the instruction (no bus request).
- **D-port:** a valid/ready request from ID/EX (addr, wdata, wstrb, we). Read data and the error
  response arrive in MEM/WB.
  - **SRAM targets** (IMEM port0, DMEM port0) are always ready. Data is available in the next cycle.
  - **The APB bridge** registers the request at the end of ID/EX. The SETUP phase then follows, and
    ACCESS repeats until `PREADY`. MEM/WB stalls meanwhile.
  - Because a memory instruction only leaves MEM/WB once its APB transfer is complete, accesses
    complete in program order. That is why FENCE can be a no-op (SPEC §2.1).
- **Crossbar arbitration:** the I-port and D-port never compete. The SRAMs have separate ports for
  them, and the boot ROM has two read ports. So the "crossbar" is an address decoder plus response
  muxes per port, with no arbiter.

## 6. Precise traps
- **Where traps are detected:**
  - **In ID/EX:** illegal instruction, ECALL, EBREAK, misaligned jump target, misaligned load/store
    address, instruction access fault (flagged by fetch), and interrupts.
  - **In MEM/WB:** load/store access fault (decode error or `PSLVERR`).
- **When a MEM/WB trap occurs** in a cycle, the ID/EX instruction is squashed in that cycle. Its CSR
  write, store request and redirect are all suppressed. Trap entry uses the MEM/WB pc.
  - SRAM stores are issued from ID/EX at the clock edge. Their chip-select and write-enable are
    gated by the "no MEM/WB trap this cycle" signal.
  - An access fault can only come from a bus response. For SRAM accesses that are decoded as
    unmapped, the fault is raised in ID/EX instead, before any request is sent.
- **Interrupts** attach to the instruction in ID/EX, if it is valid, there is no MEM/WB trap, and the
  pipeline is not stalled on H3/H6. That instruction is not executed, and `mepc` = its pc. If ID/EX
  holds a bubble, the interrupt waits one cycle.
- **trap_entry and mret** take one cycle in ID/EX. The CSR updates follow SPEC §5.3, and IF is
  redirected.

## 7. Clocks, resets and the core's power interface
- **CORE clock:** `clk` → ICG `sky130_fd_sc_hd__dlclkp` (enable = PMU `clk_en[CPU]`) → `clk_core`.
  `clk_core` also clocks the IMEM/DMEM macros.
- **PERI clock:** `clk` → ICG (enable = `clk_en[PERI]`) → `clk_peri`.
- **AON:** runs on `clk` directly.
- **Core reset:** `rst_core_n` = synchronised `rst_n` AND PMU `rst_n[CPU]`.
- **Isolation:** `iso_en[CPU]`, `iso_en[PERI]` clamp the domain outputs to 0 in AON, before they
  reach AON logic. Inputs to a powered-down domain are not isolated, because the domain ignores them.
- **Signals the core exposes:**
  - `core_idle` (SPEC §5.5);
  - `irq_wake` = `|(mip & mie)` (combinational, SPEC §8.2);
  - its Q-Channel device pins (`QREQn` in, `QACCEPTn`/`QDENY`/`QACTIVE` out). `QACTIVE` = 1 whenever
    the pipeline holds a valid instruction other than a stalled WFI.

## 8. CSR map (implementation)
Semantics are in SPEC §3. Read-only zeros are decoded so that reads succeed and writes trap.

| Addr | CSR | Storage (flops) | Write mask |
|---|---|---|---|
| 0x300 | mstatus | MIE, MPIE (2) | `0x0000_0088` (MPP reads `11`) |
| 0x301 | misa | — (constant `0x4000_0100`) | none (writes ignored, WARL) |
| 0x304 | mie | 3 | `0x0000_0888` |
| 0x305 | mtvec | 30 | `0xFFFF_FFFC` |
| 0x310 | mstatush | — | none (RO-0) |
| 0x340 | mscratch | 32 | all |
| 0x341 | mepc | 30 | `0xFFFF_FFFC` |
| 0x342 | mcause | Interrupt + 4-bit code (5) | bit 31, bits 3:0 (WLRL) |
| 0x343 | mtval | 32 | all |
| 0x344 | mip | — (wires MSIP, MTIP, MEIP) | none (writes ignored: all bits are read-only in this core) |
| 0xB00 / 0xB80 | mcycle / mcycleh | 64 | all |
| 0xB02 / 0xB82 | minstret / minstreth | 64 | all |
| 0xB03–0xB1F, 0xB83–0xB9F | mhpmcounter3–31(h) | — | none (RO-0, writable address: writes ignored) |
| 0x323–0x33F | mhpmevent3–31 | — | none (RO-0, writes ignored) |
| 0xF11–0xF15 | mvendorid, marchid, mimpid, mhartid, mconfigptr | — | read-only address: writes trap |

## 9. Stage-count justification (data comes in Phase 2)
The brief asks for 3 stages to be justified against 2 and 5, with area and CPI data. Plan:
- **CPI:**
  - Run the Phase 2/4 programs (zbb_bench, hello, the arch-test ELFs) and log, per retired
    instruction, the hazard events that each pipeline depth would see: taken branches, load-use
    distance-1 pairs, and distance-2 pairs.
  - A script (`scripts/cpi_model.py`) computes the CPI that a 2-stage, 3-stage and 5-stage in-order
    pipeline would have *for these traces* under stated penalty rules.
  - The 3-stage figure is cross-checked against the real RTL cycle count.
  - The 2- and 5-stage figures are labelled "trace-driven model", not measurements.
- **Area:** Yosys `stat` of the 3-stage core gives the cells and flops of each pipeline register.
  The extra register bits a 5-stage design needs are counted from the field widths, labelled as a
  count, not a layout area.
- The DECISIONS entry quotes only these script outputs.

## 10. Formal plan (Phase 2)
- **riscv-formal setup:**
  - `formal/checks.cfg` is written from the installed `ext/riscv-formal` documentation and the
    `cores/nerv/checks.cfg` example.
  - Options: `isa rv32iZbb`, `solver yices`, `nret 1`.
  - Checks: `insn`, `reg`, `pc_fwd`, `pc_bwd`, `unique`, `causal`, `liveness`, `cover`, `ill`, `csrw`,
    `csr_ill`, and the `csrc_*` counter checks for mcycle/minstret.
  - Defines: `RISCV_FORMAL_ALIGNED_MEM`.
- **Depths** are set from measured run times. Every check's depth and result is reported in
  `results/formal/summary.json`, and counterexamples go to `results/formal_cex/`.
- **Wrapper:** `formal/wrapper.sv` connects the core's I/D ports to unconstrained memories, as the
  riscv-formal examples do, and holds the Q-Channel inactive (`QREQn`=1).
