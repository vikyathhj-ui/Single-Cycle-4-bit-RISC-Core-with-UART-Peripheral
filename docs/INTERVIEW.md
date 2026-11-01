# Interview questions

40+ questions with answers that use this project's own numbers (docs/BRIEF.md Part B rule 7).
Answers are filled in as each phase produces evidence. Numbers are copied only from `results/`.

## Legacy and verification mindset (Phase 0)
1. **Q: Your old project had a testbench. Why did you call it insufficient?**
   A: It applied reset, waited 1 ms and stopped, with 0 checking statements (`results/legacy_probe.txt` L1).
   When I added an observing probe, the UART had sent 0 start bits in that 1 ms (L3 P4). The ROM program
   also did not match its comments: the "ADD" word decodes as OUT, and the "OUT" and "JUMP" words
   decode as NOPs (L2/L3 P1). A testbench that never compares outputs to a reference can't catch any
   of this.
2. **Q: Why did the legacy UART never transmit?**
   A: The CPU's `TX_Start` was a one-cycle combinational pulse. The UART FSM only sampled it on a
   one-cycle baud tick every 5208 cycles. In the probe, `TX_Start` was high on 1563 cycles and none of
   them lined up with the tick (L3 P3). The fix is a handshake or a FIFO. The new UART has 16-byte FIFOs
   behind an APB register interface.

<!-- Topics still to cover (Part B rule 7): pipeline hazards and forwarding paths; load-use stall;
     branch penalty and CPI; trap entry/exit, mepc/mcause; WFI with interrupts disabled; warm boot vs
     retention; what RVFI checks and cannot; riscv-formal vs arch tests vs system tests; CoreMark/MHz
     caveats; SRAM halos; PDN over macros and IR drop; clock gating measured vs expected. -->
