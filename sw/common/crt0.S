/* crt0: reset entry for programs in IMEM (docs/SPEC.md §7). The boot ROM jumps here (IMEM_BASE).
   Sets sp and mtvec (direct mode, [P §3.1.7]), copies .data from its load address in IMEM to DMEM,
   clears .bss, calls main(), then spins. trap_entry saves the caller-saved registers, calls
   trap_handler(mcause, mepc, mtval) and returns with mret to the mepc it returns [P §3.3.2]. */
    .section .text.init
    .globl _start
_start:
    la   sp, _stack_top
    la   t0, trap_entry
    csrw mtvec, t0
    la   t0, _data_lma
    la   t1, _data_start
    la   t2, _data_end
1:  bgeu t1, t2, 2f
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j    1b
2:  la   t1, _bss_start
    la   t2, _bss_end
3:  bgeu t1, t2, 4f
    sw   zero, 0(t1)
    addi t1, t1, 4
    j    3b
4:  call hal_wait_peri               /* PERI may still be powering up (D-022) */
    call main
5:  j    5b

    .align 2
    .globl trap_entry
trap_entry:
    addi sp, sp, -64
    sw   ra,  0(sp)
    sw   t0,  4(sp)
    sw   t1,  8(sp)
    sw   t2, 12(sp)
    sw   a0, 16(sp)
    sw   a1, 20(sp)
    sw   a2, 24(sp)
    sw   a3, 28(sp)
    sw   a4, 32(sp)
    sw   a5, 36(sp)
    sw   a6, 40(sp)
    sw   a7, 44(sp)
    sw   t3, 48(sp)
    sw   t4, 52(sp)
    sw   t5, 56(sp)
    sw   t6, 60(sp)
    csrr a0, mcause
    csrr a1, mepc
    csrr a2, mtval
    call trap_handler
    csrw mepc, a0
    lw   ra,  0(sp)
    lw   t0,  4(sp)
    lw   t1,  8(sp)
    lw   t2, 12(sp)
    lw   a0, 16(sp)
    lw   a1, 20(sp)
    lw   a2, 24(sp)
    lw   a3, 28(sp)
    lw   a4, 32(sp)
    lw   a5, 36(sp)
    lw   a6, 40(sp)
    lw   a7, 44(sp)
    lw   t3, 48(sp)
    lw   t4, 52(sp)
    lw   t5, 56(sp)
    lw   t6, 60(sp)
    addi sp, sp, 64
    mret
