/* CENG 442 Lab 5 test programs.
 *
 * The memory map is the one Lab 6 puts on the FPGA: 8 KB of ROM at zero
 * holding the program, and 8 KB of RAM at C0000000.  The test programs
 * build every value they need with instructions, so there is no
 * initialised data to copy from ROM to RAM and no startup code.  Read
 * only test data lives in .rodata, in ROM, where a load can reach it
 * without anything having run first.
 */

OUTPUT_FORMAT("elf32-littleriscv")
ENTRY(_start)

MEMORY
{
  ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 8K
  RAM (rwx) : ORIGIN = 0xC0000000, LENGTH = 8K
}

SECTIONS
{
  .text : {
    KEEP(*(.text.init))
    *(.text*)
    . = ALIGN(4);
  } > ROM

  .rodata : {
    . = ALIGN(4);
    *(.rodata*)
    . = ALIGN(4);
  } > ROM

  /* Uninitialised only.  Nothing here is copied, so nothing may be
     assumed about its contents: every test writes before it reads. */
  .bss (NOLOAD) : {
    . = ALIGN(4);
    *(.bss*)
    *(.sbss*)
    *(COMMON)
    . = ALIGN(4);
  } > RAM

  __ram_base = ORIGIN(RAM);
  __ram_top  = ORIGIN(RAM) + LENGTH(RAM);

  /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
