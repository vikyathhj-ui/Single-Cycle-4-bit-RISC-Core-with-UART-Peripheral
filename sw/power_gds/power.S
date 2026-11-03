/* power_gds: activity-power workload for the GDS memory configuration (1 KB IMEM + 1 KB DMEM).
   hello and sleep_demo do not fit 1 KB of IMEM, so this program has the same phases in a compact
   form (D-032). Phases are marked on GPIO outputs so the gate-level testbench (tb/gls) can dump
   exactly one phase into a VCD:
     gpio_o[0] = 1 : ACTIVE  - UART prints "PWR\n", then a compute loop (ALU, shifts, loads, stores
                               to DMEM, a branch per iteration) for LOOPS iterations
     gpio_o[1] = 1 : IDLE    - MODE_REQ = IDLE + WFI (SPEC §8.2); woken by the machine timer
                               interrupt after IDLE_TICKS mtime ticks
   Then it prints "DONE\n" and spins. Register offsets: docs/MEMORY_MAP.md. */
    .equ UART,    0x40000000
    .equ GPIO,    0x40001000
    .equ TIMER,   0x40002000
    .equ PMU,     0x40005000
    .equ DMEM,    0x20000000
    .equ LOOPS,   2000
    .equ IDLE_TICKS, 20000

    .section .text.init
    .globl _start
_start:
    la   t0, trap
    csrw mtvec, t0
    li   s1, PMU
1:  lw   t0, 0x10(s1)            /* PD_STATE: wait for PERI ON and not busy (D-022) */
    srli t0, t0, 16
    andi t0, t0, 0xF
    bnez t0, 1b
    li   s0, UART
    li   t0, 7
    sw   t0, 0x0C(s0)            /* BAUD_DIV = 7 */
    li   t0, 1
    sw   t0, 0x08(s0)            /* CTRL.TX_EN */
    li   s2, GPIO
    li   t0, 3
    sw   t0, 0x08(s2)            /* DIR: pins 0, 1 outputs */

    /* ---------------- ACTIVE */
    li   t0, 1
    sw   t0, 0x04(s2)            /* OUT = 01 */
    la   a0, msg_pwr
    jal  ra, puts
    li   t1, LOOPS
    li   t2, 0x12345678          /* xorshift state */
    li   t3, DMEM
    li   t4, 0
2:  slli t5, t2, 13
    xor  t2, t2, t5
    srli t5, t2, 17
    xor  t2, t2, t5
    slli t5, t2, 5
    xor  t2, t2, t5
    andi t5, t2, 0x3FC           /* word offset in the first 1 KB of DMEM */
    add  t5, t5, t3
    lw   t6, 0(t5)
    add  t6, t6, t2
    sw   t6, 0(t5)
    add  t4, t4, t6
    addi t1, t1, -1
    bnez t1, 2b
3:  lw   t0, 0x04(s0)            /* wait until the UART is idle before leaving ACTIVE */
    andi t0, t0, 1
    beqz t0, 3b

    /* ---------------- IDLE */
    li   t0, 2
    sw   t0, 0x04(s2)            /* OUT = 10 */
    li   s3, TIMER
    lw   t0, 0x10(s3)            /* MTIME_LO */
    li   t1, IDLE_TICKS
    add  t0, t0, t1
    li   t1, -1
    sw   t1, 0x0C(s3)            /* MTIMECMP_HI = all ones (safe update) */
    sw   t0, 0x08(s3)            /* MTIMECMP_LO */
    lw   t1, 0x14(s3)
    sw   t1, 0x0C(s3)            /* MTIMECMP_HI = MTIME_HI */
    li   t0, 0x80
    csrw mie, t0                 /* MTIE */
    csrsi mstatus, 8             /* MIE */
    sw   zero, 0x14(s1)          /* WAKE_MODE = RUN */
    li   t0, 0xFE
    sw   t0, 0x18(s1)            /* WAKE_MASK: only wake_irq[0] (core interrupt) */
    li   t0, 1
    sw   t0, 0x08(s1)            /* MODE_REQ = IDLE */
    wfi
    sw   zero, 0x08(s1)          /* MODE_REQ = RUN (in case the request was denied) */

    /* ---------------- end */
    sw   zero, 0x04(s2)          /* OUT = 00 */
    la   a0, msg_done
    jal  ra, puts
4:  j    4b

puts:                            /* a0 = string, uses t0/t1 */
    lbu  t1, 0(a0)
    beqz t1, 6f
5:  lw   t0, 0x04(s0)
    andi t0, t0, 2               /* TX_FULL */
    bnez t0, 5b
    sw   t1, 0x00(s0)
    addi a0, a0, 1
    j    puts
6:  ret

    .align 2
trap:                            /* machine timer interrupt: push mtimecmp away, return */
    li   t0, -1
    li   t1, TIMER
    sw   t0, 0x0C(t1)
    sw   t0, 0x08(t1)
    mret

msg_pwr:  .asciz "PWR\n"
msg_done: .asciz "DONE\n"
