# Power management (BRIEF A3 "Power integration", A6 power results)

Status: **Phase 4.** The functional power behaviour is implemented and measured in simulation.
Activity-based power numbers (µW/MHz in active and IDLE) come from the Phase 5 layout and VCDs.

## 1. Domains (SPEC §8.1, D-007 S-7, D-021)
```
            +------------------------------- AON (clk, never gated) ----------------------------+
 rst_n ---> | rst_sync   PMU (P2, vendored)   TIMER   SYSCTRL   UART-RX wake   isolation clamps |
            |              |  clk_en/iso_en/rst_n/psw per domain                                 |
            +--------------+----------------------------+-----------------------------------------+
                           | PD0 "CPU"                  | PD2 "PERI"            PD1 "DSP": unused stub
              +------------v-----------+   +------------v-----------+
              | CORE: core, boot ROM,  |   | PERI: UART, GPIO       |
              | crossbar, APB bridge,  |   |                        |
              | IRQC                   |   |                        |
              +------------+-----------+   +------------------------+
                           | clock (gated with CORE)
              +------------v-----------+
              | MEM: IMEM, DMEM (always powered)                     |
              +--------------------------------------------------------+
```
The power intent is described in `upf/lp_rv32.upf` (Phase 5, "not tool-verified"). Power gating
is behavioural: there are no switch cells in the layout (BRIEF A6, out of scope).

## 2. Modes used by firmware
| Mode | CORE | PERI | Entered by | Woken by |
|---|---|---|---|---|
| RUN | ON | ON | reset / wake | — |
| IDLE | CLK_GATED | ON | `MODE_REQ` = IDLE, then WFI (SPEC §8.2) | an enabled interrupt (wake_irq[0] = mip & mie) |
| DEEP_SLEEP | OFF (warm boot) | OFF | `MODE_REQ` = DEEP_SLEEP, then WFI (SPEC §8.3) | UART RX start bit (wake_irq[1]) or mtime ≥ mtimecmp (wake_irq[2]) |

**What the core does:** the core is PD0's Q-Channel device. It accepts the PMU's request only once
WFI is stalled with the pipeline empty, and it denies the request if an enabled interrupt is
already pending (SPEC §8.2).

**What firmware must do** (D-022, D-027):
- wait for PERI ON after every boot;
- empty the UART TX FIFO before DEEP_SLEEP;
- clear SYSCTRL.WAKE_SRC before sleeping.

## 3. Measured behaviour (system test `sleep_demo`, `results/system/summary.json`)
| Check | Result |
|---|---|
| CORE clock edges while `clk_en[CPU]` = 0 in IDLE | 0 over 2,952 cycles |
| `mcycle` vs `mtime` across IDLE (firmware) | 160 vs 3,112 |
| Isolation violations while CORE / PERI off | 0 in both power-off windows (2,704 and 3,312 cycles) |
| Corruption-model events (CORE, PERI) | 2, 2 (one per DEEP_SLEEP) |
| Wake reason after UART / timer wake | WAKE_SRC 0x2 / 0x4 |
| DMEM contents across DEEP_SLEEP | kept (`.noinit` marker 0xcafef00d read back after each warm boot) |

## 4. Why warm boot and not retention
- **Choice:** the CORE domain has no retention flops (`HAS_RET` = 0). After DEEP_SLEEP the core
  restarts from the reset vector, and the boot ROM takes the warm path straight to IMEM.
- **Where state lives:** software keeps what it needs in DMEM (always powered) or SYSCTRL.SCRATCH
  (AON).
- **Why:**
  - It needs no retention cells, which the sky130 flow would not place anyway (P2's finding about
    the `lpflow` cells).
  - Isolation and reset sequencing stay simple.
- **Cost:** the boot path: ROM checks, crt0's `.data`/`.bss` set-up, and the PERI wait.
