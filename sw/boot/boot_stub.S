/* Phase 3 placeholder boot ROM (docs/SPEC.md §7): jump to IMEM_BASE.
   Replaced in Phase 4 by the real boot loader (warm path, BOOT.SEL strap, UART loader). */
    .section .text
    .globl _start
_start:
    li   t0, 0x10000000      /* IMEM_BASE, docs/MEMORY_MAP.md */
    jr   t0
