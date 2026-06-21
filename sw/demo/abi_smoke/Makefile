SHELL := /bin/bash

CC=riscv32-unknown-elf-gcc
CFLAGS=-march=rv32i_zicsr -mabi=ilp32 -nostdlib -ffreestanding \
  -I../../env \
  -Wl,-T,../../env/link.ld \
  -Wl,--defsym=__stack_size=0x8000

.PHONY: all clean

all: abi_smoke.elf

abi_smoke.elf: main.c ../../env/start.S ../../env/syscalls.c ../../env/link.ld
	$(CC) $(CFLAGS) ../../env/start.S ../../env/syscalls.c main.c -o $@

clean:
	rm -f abi_smoke.elf
