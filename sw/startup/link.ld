/* Firmware memory layout: everything in the 16 KB SRAM at 0x0000_0000.
   The image is loaded into SRAM by $readmemh (no boot ROM), so .data needs
   no copy from flash. The stack grows down from the top of SRAM. */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  SRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 16K
}

SECTIONS
{
  .text : {
    KEEP(*(.text.start))
    *(.text .text.*)
  } > SRAM

  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > SRAM

  .data : {
    . = ALIGN(4);
    *(.data .data.* .sdata .sdata.*)
  } > SRAM

  .bss (NOLOAD) : {
    . = ALIGN(4);
    _bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > SRAM

  _stack_top = ORIGIN(SRAM) + LENGTH(SRAM);
  ASSERT(_bss_end <= _stack_top - 1024, "program leaves less than 1 KB of stack")
}
