/* Linker script, SIM memory configuration (docs/MEMORY_MAP.md, D-007 S-4):
   IMEM 32K at 0x1000_0000 holds code, read-only data and the initial values of .data;
   DMEM 32K at 0x2000_0000 holds .data (copied by crt0), .bss and the stack (top of DMEM).
   One IMEM image is the whole program, so the same image works when the testbench preloads IMEM
   (BOOT.SEL = 1) and when the boot ROM loads it over the UART (SPEC §7). */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  IMEM (rx) : ORIGIN = 0x10000000, LENGTH = 32K
  DMEM (rw) : ORIGIN = 0x20000000, LENGTH = 32K
}

SECTIONS
{
  .text : {
    KEEP(*(.text.init))
    *(.text .text.*)
  } > IMEM
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > IMEM
  .data : {
    _data_start = .;
    *(.data .data.* .sdata .sdata.*)
    . = ALIGN(4);
    _data_end = .;
  } > DMEM AT> IMEM
  _data_lma = LOADADDR(.data);
  .bss (NOLOAD) : {
    _bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > DMEM
  /* .noinit: in DMEM but neither loaded nor cleared by crt0, so it keeps its value across a
     DEEP_SLEEP warm boot (MEM stays powered, SPEC §8.1). Its value after a cold boot is undefined. */
  .noinit (NOLOAD) : { *(.noinit .noinit.*) } > DMEM
  _image_end = _data_lma + (_data_end - _data_start);
  _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
  ASSERT(ADDR(.noinit) + SIZEOF(.noinit) + 512 <= _stack_top, "DMEM: less than 512 B left for the stack")
}
