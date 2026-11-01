# P6 — `lp-rv32-mcu`

**Title:** LP-RV32, a power-managed RISC-V microcontroller (RV32I + Zicsr + Zbb, UART, timer, GPIO, PMU) taken RTL to GDS on SKY130.

Reworks `Single-Cycle-4-bit-RISC-Core-with-UART-Peripheral` and absorbs `UART-FLOOR-PLAN`. It reuses P1's ALU and P2's PMU, so it is the **capstone that ties your digital projects together**. Target roles are SoC/digital design, CPU design and physical design (TI, NXP).

**Run this after P1 and P2 are merged.**

## Part A — Design specification (read this yourself)

### A1. Why this stands out
5-stage RISC-V cores are among the most common student projects in India. This one is different in four ways:
1. **Industry-grade verification:** RISC-V Formal (RVFI) proofs and the official RISC-V architectural test suite run through RISCOF against a reference model, plus real C firmware.
2. **System-level low power:** `WFI` triggers clock gating via your own PMU. Deep sleep with warm boot wakes on a UART byte or a timer.
3. **Reuse of your own verified IP**, the P1 ALU and the P2 PMU, the way real SoC teams work.
4. **A real floorplan** with SRAM macros, a PDN over them and an IR-drop analysis. This replaces the weak `UART-FLOOR-PLAN` repo.

The headline metrics are CoreMark/MHz (RTL simulation, labelled) and µW/MHz from activity-based power.

### A2. Core
- **ISA:** RV32I + Zicsr + Zbb, machine mode only. `WFI` is implemented; unsupported instructions trap as illegal.
- **Pipeline:** 3-stage in-order (IF, ID/EX, MEM/WB), with:
  - full forwarding;
  - a load-use stall;
  - branches resolved in EX with static not-taken prediction (penalty documented).

  Justify 3 stages vs 2 or 5 in `docs/DECISIONS.md`, with area and CPI data.
- **ALU:** vendored from `rv32-alu-ppa-explorer` at a pinned commit (`vendor/VENDOR.md` records the hash), using that project's recommended adder config.
- **CSRs:** mstatus, misa, mie, mip, mtvec (direct mode), mepc, mcause, mtval, mscratch, mcycle(h), minstret(h), mhartid.
- **Interrupts:** machine timer, machine external (via a simple 8-source interrupt controller), and software. Traps follow the privileged spec; cite the section numbers in `docs/SPEC.md`.
- **RVFI port** for RISC-V Formal.

### A3. SoC
- **Memories:**
  - **GDS configuration:** 2 × `sky130_sram_1kbyte_1rw1r_32x256_8` OpenRAM macros (1 KB instruction, 1 KB data). Check that the macro exists in the installed PDK's `sky130_sram_macros`, and how LibreLane takes macros (variable names changed after OpenLane 1).
  - **Simulation configuration:** a parameterised 32 KB behavioural memory for CoreMark and the compliance tests. **Every reported number states which configuration it came from.**
- **Interconnect:** the core's I/D ports go to a simple valid/ready crossbar, which connects to the SRAMs and an AHB-lite-to-APB or simple-bus-to-APB bridge.
- **APB peripherals:**
  - **UART** (16550-lite): programmable baud divisor, 8N1, 16-byte TX/RX FIFOs, RX/TX/error interrupts. This replaces the old UART.
  - **Machine timer:** memory-mapped mtime/mtimecmp (CLINT-style).
  - **GPIO:** 8-bit, direction register, per-pin edge interrupt.
  - **PMU:** vendored from `soc-pmu-sequencer` at a pinned commit, with the register map imported from its YAML.
  - **SYSCTRL:** a boot/wake-reason register and a scratch register in the AON domain.
- **Power integration:**
  - **IDLE:** `WFI` asserts a core-idle signal; the PMU gates the core clock through the sky130 ICG cell. Any enabled interrupt wakes it.
  - **DEEP_SLEEP:** firmware writes the PMU mode, executes `WFI`, and the core domain is powered off (behavioural power-aware model, as in P2). A UART RX start bit or timer compare wakes it; the core **warm-boots** from the reset vector and reads SYSCTRL to tell a warm wake from a cold boot.
  - The PMU, timer, UART-RX wake detector and SYSCTRL sit in the AON domain. Document this in a domain diagram and in `upf/lp_rv32.upf`, with the same "not tool-verified" header as P2.

### A4. Software
- **Toolchain:** `riscv32-unknown-elf-gcc` or `riscv64-unknown-elf-gcc` with `-march=rv32i_zicsr_zbb -mabi=ilp32`. Record the exact version.
- `sw/`: a linker script per memory config, crt0, a minimal HAL (UART, timer, GPIO, PMU), and these programs:
  - `hello` (UART print);
  - `irq_test` (timer + GPIO interrupts);
  - `sleep_demo` (IDLE + DEEP_SLEEP + wake by UART/timer, printing the wake reason);
  - `zbb_bench` (the same algorithm with and without Zbb, comparing cycle counts);
  - `coremark` (EEMBC CoreMark, 32 KB config only; follow its run and reporting rules and **label the result "RTL simulation"**).

### A5. Verification
- **RISC-V Formal:** connect RVFI and run the standard checks configured for this core: instruction checks for RV32I (+ Zbb if supported by the framework version; otherwise say so), PC forward/backward, register file, causal and liveness checks with bounded depth. Report pass/fail per check.
- **Architectural tests:** RISCOF with the `riscv-arch-test` suites for RV32I, Zicsr where available, and Zbb, against the Sail reference model (or Spike if Sail is impractical; say which). Report pass/fail per test.
- **Unit tests:** cocotb for the UART (baud accuracy, FIFO full/empty, framing error), timer, GPIO, crossbar and APB bridge.
- **System tests:** cocotb with a UART monitor and driver in the testbench: `hello`, `irq_test`, `sleep_demo` (check the clock is actually gated during IDLE, the power-aware corruption works in DEEP_SLEEP, and the wake reason is correct) and `coremark`.
- **Lint:** Verilator `-Wall` clean.

### A6. Physical design (LibreLane, sky130A)
- **Floorplan** (`docs/FLOORPLAN.md`, the successor to UART-FLOOR-PLAN): SRAM macro placement and halos, pin plan, core utilisation target, PDN (straps, rings, connecting macro power pins) and its design reasoning, with an IR-drop analysis from OpenROAD.
- **Results:**
  - area;
  - fmax at every corner;
  - setup/hold;
  - DRC (Magic + KLayout), LVS and antenna clean;
  - power from a VCD of the `hello` + `sleep_demo` workload, giving µW/MHz in active and IDLE states. This shows the measured saving from clock gating.
- **Out of scope:** a physically power-gated layout (switch cells, multi-voltage implementation), as in P2.

### A7. Deliverables
- `docs/SPEC.md`, `docs/MICROARCH.md` (pipeline diagram, hazard table, CSR map), `docs/MEMORY_MAP.md` (generated), `docs/POWER.md`, `docs/VERIFICATION.md`, `docs/FLOORPLAN.md`, `docs/RESULTS.md`.
- `docs/DECISIONS.md`, `docs/LEARNING.md`, `docs/INTERVIEW.md`.
- `results/summary.json`; `make all` (sw → lint → unit → riscv-formal → riscof → system → flow); CI covering lint, unit tests, a reduced riscv-formal depth and `hello`.

### A8. Done when
- All RVFI checks pass at the stated depth, with arch tests 100% pass (or failures listed and explained).
- All system tests pass.
- CoreMark/MHz is reported with its configuration.
- The GDS is signoff-clean.
- Measured IDLE vs active power is reported.
- You can draw the pipeline and explain every hazard and the trap sequence on a whiteboard.

---

## Part B — Prompt for Claude Code

**How to use this:** paste this **entire file** into Claude Code as one message, inside a clone of `Single-Cycle-4-bit-RISC-Core-with-UART-Peripheral`. P1 and P2 must be merged first.

---

You are working in my GitHub repo `Single-Cycle-4-bit-RISC-Core-with-UART-Peripheral` (owner `vikyathhj-ui`). Turn it into `lp-rv32-mcu`: a power-managed RV32I+Zicsr+Zbb microcontroller with UART, timer, GPIO and my own PMU, verified with RISC-V Formal and RISCOF, and taken through LibreLane on SKY130 with OpenRAM SRAM macros. It reuses my ALU from `vikyathhj-ui/rv32-alu-ppa-explorer` (or its old name `32bit-RTL-To-GDS`) and my PMU from `vikyathhj-ui/soc-pmu-sequencer` (or `multipower`). Part A of this message is the binding specification. I am a final-year ECE student applying for digital/SoC design roles; correctness and honesty matter more than speed.

### Non-negotiable rules
1. **Never fabricate or hand-type a result.** Every number comes from a script parsing a tool output, stored in `results/summary.json` with its source path and the memory configuration used.
2. **Git:**
   - Branch `rework/lp-rv32`. Move the old 4-bit core and UART to `legacy/`; do not delete them.
   - Conventional Commits after each gate, with what/why/verification in the body. Keep the default `Co-Authored-By: Claude` trailer.
   - Push after each commit; open a PR per phase. **Never merge**, never force-push, never rewrite history.
3. **Vendored IP:** copy the ALU and PMU into `vendor/` at the latest `main` commit, recording repo, commit hash and date in `vendor/VENDOR.md`. If you find a bug in vendored IP, fix it **in the source repo** through a separate branch and PR (ask me first), then re-vendor.
4. **Ask me before:** renaming repos, changing visibility, installing system packages, or acting outside this repo.
5. Cite the RISC-V unprivileged and privileged spec sections for every ISA or trap behaviour. Never invent framework options for riscv-formal or RISCOF: read their docs or examples in the installed versions.
6. Keep `PROGRESS.md` current so a new session can continue from "Read CLAUDE.md and PROGRESS.md and continue".
7. Keep `docs/DECISIONS.md`, `docs/LEARNING.md` and `docs/INTERVIEW.md` (40+ questions with answers using this project's numbers). The questions must cover:
   - pipeline hazards and forwarding paths;
   - the load-use stall;
   - branch penalty and CPI;
   - the trap entry/exit sequence and the mepc/mcause semantics;
   - how WFI works with interrupts disabled;
   - why warm boot instead of CPU retention;
   - what RVFI checks and what it cannot;
   - riscv-formal vs arch tests vs system tests;
   - CoreMark/MHz caveats;
   - why SRAM macros need halos;
   - PDN over macros and IR drop;
   - clock gating savings measured vs expected.

### Phase 0 — Setup (one commit)
- **Environment check:** `verilator`, `iverilog`, `yosys`, `sby` + solvers (riscv-formal typically needs boolector or bitwuzla; check its docs), a RISC-V GCC toolchain, `riscof` + a reference model (`sail-riscv` or `spike`), a `riscv-arch-test` checkout, a `riscv-formal` checkout, `python3` + `cocotb` + `cocotb-coverage`, `librelane`, `openroad`, `sta`, `magic`, `netgen`, `klayout`, the sky130A PDK, and `sky130_sram_macros` (check the 1 KB macro's LEF/GDS/LIB paths).
  - Print a found/missing table. If anything is missing, stop and give me install commands; no sudo.
- **Save the brief and set up the repo:** save this message verbatim as `docs/BRIEF.md`. Create `CLAUDE.md`, `PROGRESS.md`, `.gitattributes` (`* text=auto eol=lf`), `.gitignore` and `LICENSE` (Apache-2.0).
- **Legacy and audit:** move the old code to `legacy/` and write `docs/AUDIT.md`, noting the old testbench only applied stimulus.
- **Layout:**
  ```
  rtl/core/  rtl/soc/  rtl/periph/  vendor/  sw/  tb/  formal/  riscof/  upf/  flow/  scripts/  results/  docs/
  ```

### Phase 1 — Spec
- `docs/SPEC.md`, `docs/MICROARCH.md` and the memory map (generated from YAML into C header + Python + Markdown) from Part A.

Gate: **stop and ask me to confirm the spec.**

### Phase 2 — Core and RVFI
- Core RTL with the vendored ALU; RVFI; RISC-V Formal checks.
- Every counterexample is saved under `results/formal_cex/` and logged in DECISIONS under "Bugs found by formal".

Gate: all checks pass at the stated depth. Commit, then open a PR.

### Phase 3 — Compliance and SoC
- RISCOF setup and runs (report per test).
- SoC: crossbar, APB bridge, UART, timer, GPIO, interrupt controller, SYSCTRL, vendored PMU.
- Unit tests and coverage.

Gate: arch tests pass and unit tests pass. Commit.

### Phase 4 — Software and system tests
- `sw/` HAL and programs; cocotb system tests including `sleep_demo` with power-aware checks; CoreMark in the 32 KB config.
- `zbb_bench` comparison.

Gate: all pass, and CoreMark/MHz is recorded. Commit, then open a PR.

### Phase 5 — Physical
- LibreLane with the 2 SRAM macros; floorplan and PDN documented in `docs/FLOORPLAN.md`; IR drop; multi-corner STA.
- Activity-based power for active vs IDLE.
- Signoff clean.

Gate: done. Commit.

### Phase 6 — Docs and close
- **README:**
  - pitch;
  - SoC block diagram;
  - domain diagram;
  - results table auto-generated from `summary.json`;
  - GDS render;
  - "Reproduce";
  - "Limitations": no silicon; behavioural power gating; CoreMark from RTL simulation with 32 KB memory;
  - "AI assistance": "Developed with Claude Code; all results reproduced by Vikyath J with `make all`."
- `results/resume_bullets.md`: 3 bullets using only `summary.json` numbers.
- Open the final PR. Then ask me whether to rename the repo to `lp-rv32-mcu`, and whether to make `UART-FLOOR-PLAN` private with a pointer to `docs/FLOORPLAN.md`.

Start with Phase 0, in plan mode, and show me the plan before editing files.
