OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  SPM (rwx) : ORIGIN = 0x80000000, LENGTH = 1M
}

__spm_origin = ORIGIN(SPM);
__spm_length = LENGTH(SPM);
__spm_end    = ORIGIN(SPM) + LENGTH(SPM);

/* Keep the first software environment small while leaving room for C tests. */
__stack_size = DEFINED(__stack_size) ? __stack_size : 0x4000;

SECTIONS
{
  . = ORIGIN(SPM);

  .text.init : ALIGN(64)
  {
    KEEP(*(.text.init))
  } > SPM

  .text : ALIGN(4)
  {
    *(.text .text.*)
  } > SPM

  .rodata : ALIGN(16)
  {
    *(.srodata .srodata.*)
    *(.rodata .rodata.*)
  } > SPM

  .data : ALIGN(16)
  {
    __data_start = .;
    *(.sdata .sdata.*)
    *(.data .data.*)
    __data_end = .;
  } > SPM

  PROVIDE(__global_pointer$ = __data_start + 0x800);

  .bss (NOLOAD) : ALIGN(16)
  {
    __bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    __bss_end = .;
  } > SPM

  .tohost (NOLOAD) : ALIGN(64)
  {
    tohost = .;
    . += 8;
    fromhost = .;
    . += 8;
    . = ALIGN(64);
    console_putchar = .;
    . += 4;
    . = ALIGN(64);
  } > SPM

  .signature (NOLOAD) : ALIGN(16)
  {
    begin_signature = .;
    *(.signature .signature.*)
    end_signature = .;
  } > SPM

  . = ALIGN(16);
  __heap_start = .;
  PROVIDE(end = __heap_start);
  PROVIDE(_end = __heap_start);
  __heap_end = __spm_end - __stack_size;
  . = __heap_end;

  .stack __heap_end (NOLOAD) : ALIGN(16)
  {
    __stack_bottom = .;
    . += __stack_size;
    __stack_top = .;
  } > SPM

  /DISCARD/ :
  {
    *(.comment)
    *(.riscv.attributes)
    *(.note .note.*)
    *(.eh_frame .eh_frame.*)
  }

  ASSERT(__heap_start <= __heap_end, "SPM image overlaps the reserved stack")
  ASSERT(__stack_top == __spm_end, "stack must end at the top of SPM")
}
