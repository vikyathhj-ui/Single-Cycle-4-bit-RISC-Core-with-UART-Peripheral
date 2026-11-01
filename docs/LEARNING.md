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
