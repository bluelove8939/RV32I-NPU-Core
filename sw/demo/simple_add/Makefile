SHELL := /bin/bash


ifneq ($(strip $(NMTA_ENV_MK)),)
NMTA_ENV_MK:=../../env/nmta_env.mk
endif

include $(NMTA_ENV_MK)

.DEFAULT_GOAL := all

.PHONY: all clean

all: exe.elf

exe.elf: main.c $(NMTA_ENV_LIB) $(NMTA_LINKER_SCRIPT)
	$(NMTA_CC) $(NMTA_CFLAGS) $(NMTA_LDFLAGS) main.c $(NMTA_ENV_LINK) -o $@

clean:
	rm -f exe.elf
