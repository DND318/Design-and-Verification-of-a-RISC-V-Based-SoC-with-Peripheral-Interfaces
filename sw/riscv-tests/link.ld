/* riscv-tests (env/p) relinked for this SoC: program at address 0
   (tb_cpu_wrapper memory and SoC SRAM), instead of 0x8000_0000. */
OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  . = 0x00000000;
  .text.init : { *(.text.init) }
  . = ALIGN(0x100);
  .tohost : { *(.tohost) }
  . = ALIGN(0x100);
  .text : { *(.text) }
  . = ALIGN(0x100);
  .data : { *(.data) }
  .bss : { *(.bss) }
  _end = .;
}
