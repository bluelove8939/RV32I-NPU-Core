NMTA_ENV_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))

NMTA_ARCH ?= rv32i_zicsr
NMTA_ABI  ?= ilp32

NMTA_CC ?= riscv32-unknown-elf-gcc
NMTA_AR ?= riscv32-unknown-elf-ar

NMTA_STACK_SIZE ?= 0x8000

NMTA_LINKER_SCRIPT := $(NMTA_ENV_DIR)/link.ld
NMTA_ENV_LIB := $(NMTA_ENV_DIR)/libnmta_env.a

NMTA_CFLAGS := -march=$(NMTA_ARCH) -mabi=$(NMTA_ABI) \
  -ffreestanding \
  -fno-exceptions \
  -fno-unwind-tables \
  -fno-asynchronous-unwind-tables \
  -I$(NMTA_ENV_DIR)

NMTA_LDFLAGS := -nostartfiles \
  -Wl,-T,$(NMTA_LINKER_SCRIPT) \
  -Wl,--defsym=__stack_size=$(NMTA_STACK_SIZE)

NMTA_ENV_LINK := -Wl,--whole-archive $(NMTA_ENV_LIB) -Wl,--no-whole-archive

$(NMTA_ENV_LIB):
	$(MAKE) -C $(NMTA_ENV_DIR) \
	  NMTA_ARCH=$(NMTA_ARCH) \
	  NMTA_ABI=$(NMTA_ABI) \
	  CC=$(NMTA_CC) \
	  AR=$(NMTA_AR)
