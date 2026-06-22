SHELL := /bin/bash

NMTA_ARCH ?= rv32i_zicsr
NMTA_ABI  ?= ilp32

CC ?= riscv32-unknown-elf-gcc
AR ?= riscv32-unknown-elf-ar

BUILD_DIR := build
LIB := libnmta_env.a

CFLAGS := -march=$(NMTA_ARCH) -mabi=$(NMTA_ABI) \
  -ffreestanding \
  -fno-exceptions \
  -fno-unwind-tables \
  -fno-asynchronous-unwind-tables \
  -I.

OBJS := \
  $(BUILD_DIR)/start.o \
  $(BUILD_DIR)/syscalls.o

.PHONY: all clean

all: $(LIB)

$(LIB): $(OBJS)
	$(AR) rcs $@ $^

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/start.o: start.S link.ld | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/syscalls.o: syscalls.c nmta_syscall.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf $(BUILD_DIR) $(LIB)
