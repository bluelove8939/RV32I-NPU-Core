SHELL := /bin/bash

CC=riscv32-unknown-elf-gcc
CFLAGS=-march=rv32i_zicsr -mabi=ilp32 -nostdlib -ffreestanding \
  -Wl,-T,../../env/link.ld \
  -Wl,--defsym=__stack_size=0x8000

.PHONY: all clean

all: exe.elf

exe.elf: main.c ../../env/start.S ../../env/link.ld
	$(CC) $(CFLAGS) ../../env/start.S main.c -o $@

clean:
	rm -f exe.elf
