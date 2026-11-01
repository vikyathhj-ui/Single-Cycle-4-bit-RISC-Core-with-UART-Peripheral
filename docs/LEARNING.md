# Learning notes

Concepts met in this project, explained simply, with pointers into the code. Each phase adds
entries.

## Phase 0
- **Why a testbench must check something.** The legacy testbench "passed" because it never compared
  anything (docs/AUDIT.md F1). The probe in `legacy/tb_probe.v` shows the design actually sent no UART
  frame at all (F3). A testbench without a checker or a reference model only shows that the
  simulation ran.
- **Clock-domain-style handshake bugs inside one clock domain.** The legacy CPU raised `TX_Start` for
  one cycle, but the UART only looked at it once every 5208 cycles (AUDIT F3). Two one-cycle pulses
  with no latch or valid/ready handshake will almost never line up. That is why the new SoC uses
  valid/ready on the bus and FIFOs in the UART.
- **Formal vs compliance vs system tests** (more in Phase 2/3):
  - riscv-formal proves properties of every instruction the core retires, up to a bounded depth.
  - The arch tests compare signatures against a reference model for chosen programs.
  - System tests check that the whole SoC runs real firmware.

## Phase 1
- **Why the SRAM macro shapes the pipeline.** The OpenRAM macro registers its address on the rising
  edge but reads on the falling edge (MICROARCH §3).
  - So the instruction word only exists in the second half of the cycle after the address was sent.
  - In a 3-stage pipeline, decode + ALU + next address must fit in that half cycle.
  - This is also why a load result is not forwarded straight into the ALU, and why the load-use
    stall exists (H3).
- **One forwarding path is enough here.** The register file is written at the end of MEM/WB, and
  the reader is in ID/EX in the same cycle. So only distance-1 dependences need a bypass, and it
  goes from MEM/WB to ID/EX (MICROARCH §4).
- **Precise traps with a 3-stage pipe.** Most traps are found in ID/EX. Bus errors are found in
  MEM/WB, one stage later. When that happens, the younger instruction in ID/EX is cancelled in the
  same cycle (no CSR write, no store, no redirect), so the program sees the trap "between" two
  instructions (MICROARCH §6).
- **WFI is a hint, not a sleep command.** The privileged spec lets WFI be a NOP. It must wake on any
  *individually enabled* pending interrupt, even with `mstatus.MIE`=0 [P §3.3.3]. The real power
  saving comes from the PMU handshake (SPEC §8.2).
- **Generated register maps.** One YAML file produces the doc, the C header and the Python dict, so
  they cannot drift apart. P2's bug (`ON`/`OFF` read as booleans by YAML 1.1) is a good example of
  why the generator checks its input (D-009).

## Phase 2
- **What RVFI is.** RVFI is a set of extra output ports on the core (`rtl/core/lp_rv32_core.sv`,
  under `` `ifdef RISCV_FORMAL ``). Each time an instruction retires, the core reports:
  - the instruction and its pc before and after;
  - which registers it read and the values it saw;
  - what it wrote, and any memory access.

  riscv-formal compares that report against its own model of each instruction
  (`ext/riscv-formal/insns/insn_*.v`). The core's pipeline is never looked at: only what it
  claims each instruction did.
- **What the checks prove, roughly:**
  - `insn_*`: every instruction of that kind computes the right result.
  - `reg`: the value an instruction reads equals the value the last writer wrote. This catches
    forwarding and stall bugs.
  - `pc_fwd` / `pc_bwd`: each instruction starts where the previous one said it would go.
  - `causal`, `unique`: retire order is consistent, and no instruction number is used twice.
  - `liveness`: the core keeps making progress.
  - `csrw`, `csr_ill`, `csrc_upcnt`: CSR read/write semantics, illegal CSR addresses trap, and
    the counters go up.
- **Bounded means "up to N cycles after reset".**
  - A pass at depth 20 means no bug can show up within 20 cycles of reset, for *any* instruction
    stream and any memory/interrupt behaviour.
  - That is strong for pipeline bugs, which need only a few instructions to trigger. It says
    nothing about longer sequences.
- **Formal found a real bug at depth 11 (DECISIONS, Bug 01).** A misaligned store that depended on
  a load right before it was allowed to skip the load-use stall, because it was going to trap
  anyway. But the trap decision itself used the stale register.
  - The simulation tests planned for later would only catch this if someone happened to write
    that exact sequence.
- **Why the core needs no state for a stalled instruction.** The SRAM drops its output after one
  cycle. So when ID/EX stalls, the core simply fetches the same address again, and every
  decision in ID/EX is recomputed from scratch each cycle.
