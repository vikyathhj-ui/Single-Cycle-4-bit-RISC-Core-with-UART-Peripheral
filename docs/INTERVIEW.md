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

## Verification layers (Phase 3)
15. **Q: riscv-formal, arch tests and system tests: what does each find?**
    A:
    - **riscv-formal** proves that every instruction and short sequence is right, for *any* input,
      up to a bound (79/79 checks, `results/formal/summary.json`). It found Bug 01.
    - **Arch tests** run whole programs and compare memory signatures with Spike. 65 PASS
      (`results/riscof/summary.json`). They cover trap handlers and CSRs that formal skipped here.
    - **System tests** (Phase 4) run real firmware on the whole SoC.
    The layers overlap on purpose.
16. **Q: Your arch-test report has "NOT RUN" entries. Why?**
    A: Seven tests (the six branch tests and jal-01) need more than the 32 KB simulation memory. The
    largest overflows by 1,723,488 bytes. The owner chose to run only what fits rather than add a
    larger memory configuration (D-015). Branches and JAL are still proven by riscv-formal.
17. **Q: How do you know a test can fail?**
    A: Mutation checks:
    - SLTU decoded as SLT makes `sltu-01` fail, with 183 of 724 words different.
    - A bridge that drops a back-to-back request made the crossbar test fail only after I added a
      response timeout. Before that it hung silently (D-019).
18. **Q: What did the UART test measure for baud accuracy?**
    A: Every transmitted bit is held for exactly BAUD_DIV+1 clock cycles, checked cycle by cycle on
    `txd`, for divisors 1, 3, 15 and 433. The receiver also accepts frames with a bit period off by
    ±3 % (`results/unit/summary.json`, `tb/unit/test_uart.py`).

## Software, power and benchmarks (Phase 4)
19. **Q: How does WFI interact with the PMU in IDLE?**
    A: Firmware writes `MODE_REQ`=IDLE and executes WFI. The core accepts the PMU's Q-Channel
    request only once WFI is stalled with an empty pipeline. The PMU then drops the ICG enable. In
    `sleep_demo` the core clock had 0 edges over a 2,952-cycle IDLE window. An enabled interrupt
    (`mip & mie`) raises `wake_irq[0]`, the PMU turns the clock back on, WFI retires, and the
    interrupt is taken (`results/system/summary.json`).
20. **Q: Why warm boot instead of retaining the CPU state?**
    A: The CORE domain has no retention flops (`HAS_RET` = 0). DMEM and IMEM stay powered and
    SYSCTRL.SCRATCH is in AON, so software keeps its state there. The boot ROM sees
    RESET_CAUSE.WARM and jumps straight to IMEM. This avoids retention cells and keeps isolation and
    reset simple. The cost is a short re-boot (docs/POWER.md §4).
21. **Q: How do you know DEEP_SLEEP really loses the CPU state in simulation?**
    A: A behavioural corruption model in the testbench overwrites the register file and the UART
    FIFOs when a domain's power switch turns off. It fired 2 times per domain in `sleep_demo`, and
    the warm boots still worked. A monitor also saw 0 isolation violations while the domains were
    off.
22. **Q: What is your CoreMark/MHz and what are the caveats?**
    A: 1.1266, from 10 iterations in 8,876,270 cycles, RTL simulation, 32 KB SIM memories, GCC 16.1.0
    `-O2`. The CRCs match EEMBC's known values. But a 10-iteration simulation is far below
    CoreMark's 10-second rule, so it is not a valid published score (D-025). RV32I has no hardware
    multiply, which pulls the number down.
23. **Q: What did Zbb buy you?**
    A: On a bit-manipulation kernel over 256 words: 25,912 cycles without Zbb (libgcc popcount,
    clz, ctz, bswap) vs 4,897 with Zbb (cpop, clz, ctz, rev8, ror, minu, maxu, andn), with the
    same result.
24. **Q: Why 3 stages? Give numbers.**
    A: CPI on CoreMark:
    - 3-stage measured 1.2408, and the model predicts 1.2397;
    - 2-stage model 1.2861: every load costs a cycle with synchronous SRAM;
    - 5-stage model 1.4486: 2-cycle taken-branch penalty.

    A 5-stage design would need about 17 % higher fmax just to break even. Its area was not
    measured; the 3-stage core synthesises to 81,269.19 µm² (D-026).
25. **Q: Your first hello test printed nothing. What was wrong?**
    A: The PMU powers CPU before PERI, so the first UART write hit an isolated peripheral and got
    a bus error, which is the clamp's intended behaviour. Software now waits for PERI ON (D-022). It
    shows that power sequencing is part of the software contract.
26. **Q: What is the boot flow?**
    A: The ROM runs at 0x0. WARM → jump to IMEM. BOOT.SEL strap → jump to IMEM (preloaded).
    Otherwise it waits for PERI, sends '>', receives a 4-byte length and the image into IMEM,
    echoes the checksum and jumps. In the loader test a 1,740-byte image round-tripped with
    checksum 0x0001ebe5.

<!-- Topics still to cover (Part B rule 7): pipeline hazards and forwarding paths; load-use stall;
     branch penalty and CPI; trap entry/exit, mepc/mcause; WFI with interrupts disabled; warm boot vs
     retention; what RVFI checks and cannot; riscv-formal vs arch tests vs system tests; CoreMark/MHz
     caveats; SRAM halos; PDN over macros and IR drop; clock gating measured vs expected. -->
