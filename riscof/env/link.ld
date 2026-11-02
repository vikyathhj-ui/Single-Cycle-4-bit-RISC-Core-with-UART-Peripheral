/* Link script for the RISCOF arch tests, shared by the DUT (lp_rv32) and the reference (Spike) so
   that address-dependent signature values are identical. SIM memory configuration (D-007 S-4):
   code in IMEM (32 KB at 0x8000_0000), data / signature / tohost in DMEM (32 KB at 0x2000_0000).
   IMEM is at 0x8000_0000, not the SoC's 0x1000_0000, because Spike has a UART at 0x1000_0000 (D-015).
   Based on riscv-arch-test 3.10.0 riscof-plugins/rv32/spike_simple/env/link.ld. */
OUTPUT_ARCH( "riscv" )
ENTRY(rvtest_entry_point)

MEMORY
{
  IMEM (rx) : ORIGIN = 0x80000000, LENGTH = 32K
  DMEM (rw) : ORIGIN = 0x20000000, LENGTH = 32K
}

SECTIONS
{
  .text.init : { *(.text.init) } > IMEM
  .text : { *(.text) } > IMEM
  .tohost : { *(.tohost) } > DMEM
  .data : { *(.data) } > DMEM
  .data.string : { *(.data.string) } > DMEM
  .bss : { *(.bss) } > DMEM
  _end = .;
}
