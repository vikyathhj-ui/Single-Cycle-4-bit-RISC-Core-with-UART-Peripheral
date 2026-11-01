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

## Pipeline and hazards (Phases 1–2)
3. **Q: Draw your pipeline. Why 3 stages?**
   A: IF | ID/EX | MEM/WB (docs/MICROARCH.md §1).
   - IF sends the pc to the SRAM.
   - ID/EX decodes, reads registers, forwards, runs the ALU, resolves branches and issues the
     load/store.
   - MEM/WB finishes the load and writes the register file.
   The brief fixes 3 stages. The trade-off against 2 and 5 stages is measured from real program
   traces in Phase 4 (MICROARCH §9), so I won't quote a CPI before then.
4. **Q: What forwarding paths do you have?**
   A: One: MEM/WB → ID/EX (hazard H1). The register file is written at the end of MEM/WB, so
   anything two or more instructions older is read straight from the register file (H2). Load
   results are not forwarded (see Q5).
5. **Q: Why do you have a load-use stall if you could forward the load data?**
   A: The OpenRAM macro reads on the *falling* edge (`always @(negedge clk0)` in its Verilog model;
   `dout` is `timing_type : falling_edge` in its liberty file). Load data only arrives in the
   second half of the MEM/WB cycle. Forwarding it into the ALU would add a second half-cycle
   critical path, so a dependent instruction waits one cycle instead (H3).
6. **Q: What is your branch penalty?**
   A: Branches resolve in ID/EX with static not-taken prediction. The redirect is registered (that
   keeps the SRAM-output → decode → compare → SRAM-address path out of one cycle). So a taken
   branch or jump costs one bubble, and a not-taken branch costs nothing (H4). How often that
   happens is measured in Phase 4.
7. **Q: How do you handle a stall when the SRAM drops its output after one cycle?**
   A: I fetch the same address again. Every decision in ID/EX is recomputed from scratch each
   cycle, so no instruction register is needed (MICROARCH §3, D-010).

## Traps and WFI
8. **Q: Walk me through trap entry.**
   A: In one cycle (SPEC §5.3, [P §3.1.6.1]):
   - mepc ← pc of the trapping instruction;
   - mcause and mtval ← cause and value;
   - MPIE ← MIE, then MIE ← 0, and MPP ← M;
   - the pc is redirected to mtvec.BASE (direct mode).
   The trapping instruction writes nothing. Interrupts attach to the instruction in ID/EX, which
   does not execute, so mepc = its pc. MRET does MIE ← MPIE, MPIE ← 1, pc ← mepc.
9. **Q: An access fault comes back from the bus while a younger instruction is in ID/EX. What
   happens?**
   A: The younger instruction is squashed in the same cycle: its CSR write, store and redirect are
   all blocked. The trap uses the MEM/WB pc (MICROARCH §6). That is what keeps traps precise.
10. **Q: How does WFI behave with interrupts disabled?**
    A: It waits until `mip & mie ≠ 0`, ignoring `mstatus.MIE`, as [P §3.3.3] requires. If MIE=0,
    execution simply continues at pc+4, and software reads mip. If MIE=1, the *next* instruction
    takes the trap, so mepc = pc(WFI)+4. WFI itself is never interrupted.
11. **Q: How does the core get its clock gated?**
    A: The core is the PMU's Q-Channel device for PD0.
    - Firmware writes `MODE_REQ`=IDLE, then executes WFI.
    - The core accepts the quiescence request only when WFI is stalled with the pipeline empty,
      and denies it if an enabled interrupt is already pending.
    - The PMU then drops `clk_en` into the sky130 ICG (SPEC §8.2).

## Formal verification
12. **Q: What does RVFI check, and what can it not check?**
    A: RVFI reports each retired instruction (pc, registers read and written, memory access). It
    checks that the reports match the ISA (`insn_*`), stay consistent with each other (`reg`,
    `pc_fwd/bwd`, `causal`, `unique`) and keep progressing (`liveness`). In my setup it does not
    check:
    - bus faults (tied to 0);
    - the WARL CSRs mstatus/mie/mtvec/mepc/mcause (the `csrw` check assumes every bit is
      writable);
    - misa (D-010);
    - anything deeper than the bound;
    - the SoC around the core.
13. **Q: Give an example of a bug formal found.**
    A: Bug 01 (DECISIONS), found by `reg_ch0` at depth 11. A misaligned store right after a load
    it depended on skipped the load-use stall, because it was going to trap anyway, so it read a
    stale register. The fix was to let only interrupts bypass the stall.
14. **Q: What does "passes at depth N" mean? Why is your `reg` depth lower?**
    A: No counterexample exists within N cycles after reset, for any instruction stream. Solver
    time for `reg` grew about 10× per 2 extra steps: 30 s at SBY depth 13, 312 s at 15, and no
    result within 30 min at 17 or 19 (D-012). So `reg` runs at 15 and the rest at their configured
    depths. Longer sequences are covered by the arch and system tests.

<!-- Topics still to cover (Part B rule 7): pipeline hazards and forwarding paths; load-use stall;
     branch penalty and CPI; trap entry/exit, mepc/mcause; WFI with interrupts disabled; warm boot vs
     retention; what RVFI checks and cannot; riscv-formal vs arch tests vs system tests; CoreMark/MHz
     caveats; SRAM halos; PDN over macros and IR drop; clock gating measured vs expected. -->
