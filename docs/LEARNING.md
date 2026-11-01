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
