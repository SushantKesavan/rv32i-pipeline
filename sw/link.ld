/* Harvard layout used by the testbench: code lives in imem (address 0),
   zero-initialised globals in dmem (.bss at 0x4000, inside the 4 KB dmem window).
   dmem is not preloaded, so initialised data is not supported (checked by the ASSERT). */
ENTRY(_start)
SECTIONS
{
  . = 0;
  .text : { *(.text.init) *(.text .text.*) }
  . = 0x4000;
  .bss (NOLOAD) : { *(.bss .bss.* .sbss .sbss.* COMMON) }
  .data : { *(.data .data.* .sdata .sdata.* .rodata .rodata.* .srodata .srodata.*) }
  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame*) *(.note*) }
}
ASSERT(SIZEOF(.data) == 0, "initialised data / .rodata is not supported (dmem is not preloaded)")
ASSERT(SIZEOF(.text) <= 4096, "program does not fit in 1024-word imem")
