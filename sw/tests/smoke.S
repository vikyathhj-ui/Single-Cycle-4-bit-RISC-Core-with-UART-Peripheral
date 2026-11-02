/* Phase 3 SoC smoke test (tb/unit/test_soc.py): print "OK" on the UART, then spin.
   UART register offsets: docs/MEMORY_MAP.md. Loaded into IMEM by the testbench (BOOT.SEL = 1). */
    .section .text
    .globl _start
_start:
    li   t2, 0x40005000      /* PMU: wait for PERI ON and not busy (D-022) */
1:  lw   t1, 0x10(t2)        /* PD_STATE */
    srli t1, t1, 16
    andi t1, t1, 0xF
    bnez t1, 1b
    li   t0, 0x40000000      /* UART_BASE */
    li   t1, 3
    sw   t1, 0x0C(t0)        /* BAUD_DIV = 3: 4 cycles per bit */
    li   t1, 1
    sw   t1, 0x08(t0)        /* CTRL.TX_EN */
    li   t1, 'O'
    sw   t1, 0x00(t0)        /* DATA */
    li   t1, 'K'
    sw   t1, 0x00(t0)
2:  j    2b
