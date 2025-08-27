ENTRY(_start)
OUTPUT_FORMAT("elf64-x86-64")
SECTIONS
{
  . = 0x7C00;                 /* where BIOS jumps */
  .boot 0x7C00 : AT(0) {
    KEEP(*(.text*))
    KEEP(*(.rodata*))
    KEEP(*(.data*))
    KEEP(*(.bss*))
  }
  /DISCARD/ : { *(*); }
}
