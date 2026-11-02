/* Boot ROM (docs/SPEC.md §7, D-020). Runs from the reset vector 0x0000_0000. Must fit 256 B.
   Register offsets: docs/MEMORY_MAP.md (UART 0x4000_0000, SYSCTRL 0x4000_4000, PMU 0x4000_5000).
   1. Warm path: SYSCTRL.RESET_CAUSE.WARM = 1 -> IMEM still holds the program -> jump to IMEM_BASE.
   2. Simulation path: SYSCTRL.BOOT.SEL = 1 (strap) -> memory preloaded -> jump to IMEM_BASE.
   3. Loader path:
      - wait until the PMU reports PERI ON and not busy (D-022);
      - enable the UART at its reset divisor (BAUD_DIV = 433) and send the prompt '>';
        the host waits for it before sending (otherwise the first byte can arrive before the
        receiver is enabled, D-023);
      - receive a 4-byte little-endian length, then that many bytes, stored to IMEM in order;
      - send back the 32-bit sum of the bytes (little-endian) and wait until it has been sent;
      - jump to IMEM_BASE.
   Uses only registers, no stack (DMEM is not needed). */
    .section .text
    .globl _start
_start:
    li   s0, 0x40004000          /* SYSCTRL */
    lw   t0, 0x04(s0)            /* RESET_CAUSE */
    andi t0, t0, 2               /* WARM */
    bnez t0, run
    lw   t0, 0x10(s0)            /* BOOT */
    andi t0, t0, 1               /* SEL */
    bnez t0, run

    li   s1, 0x40005000          /* PMU */
1:  lw   t0, 0x10(s1)            /* PD_STATE */
    srli t0, t0, 16              /* PERI_STATE [18:16], PERI_BUSY [19] */
    andi t0, t0, 0xF
    bnez t0, 1b                  /* 0 = ON and not busy */

    li   s2, 0x40000000          /* UART */
    li   t0, 3
    sw   t0, 0x08(s2)            /* CTRL: TX_EN | RX_EN */
    li   t0, 0x3E
    sw   t0, 0x00(s2)            /* prompt '>': the receiver is ready, the host may send */

    li   s3, 0                   /* length */
    li   s4, 0                   /* shift */
    li   s5, 32
2:  jal  ra, getc
    sll  a0, a0, s4
    or   s3, s3, a0
    addi s4, s4, 8
    bne  s4, s5, 2b

    li   s6, 0x10000000          /* IMEM_BASE: destination */
    li   s7, 0                   /* checksum */
3:  beqz s3, 4f
    jal  ra, getc
    sb   a0, 0(s6)
    add  s7, s7, a0
    addi s6, s6, 1
    addi s3, s3, -1
    j    3b

4:  li   s4, 4
5:  andi t0, s7, 0xFF
6:  lw   t1, 0x04(s2)            /* STATUS */
    andi t1, t1, 2               /* TX_FULL */
    bnez t1, 6b
    sw   t0, 0x00(s2)            /* DATA */
    srli s7, s7, 8
    addi s4, s4, -1
    bnez s4, 5b
7:  lw   t1, 0x04(s2)
    andi t1, t1, 1               /* TX_EMPTY (FIFO and shifter) */
    beqz t1, 7b

run:
    li   t0, 0x10000000          /* IMEM_BASE */
    jr   t0

getc:                            /* a0 = next RX byte (blocking) */
    lw   t1, 0x04(s2)            /* STATUS */
    andi t1, t1, 4               /* RX_EMPTY */
    bnez t1, getc
    lw   a0, 0x00(s2)
    andi a0, a0, 0xFF
    ret
