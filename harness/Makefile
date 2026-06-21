HARNESS_DIR := harness

HARNESS_TOP := cpu_elf_harness_top
HARNESS_BIN := $(BUILD_DIR)/cpu_elf_harness
HARNESS_OBJ_DIR := $(BUILD_DIR)/obj_cpu_elf_harness

HARNESS_SV_SRCS = \
	$(SRC_DIR)/spm_bank.sv \
	$(SRC_DIR)/spm_bankgroup.sv \
	$(SRC_DIR)/spm_bus.sv \
	$(SRC_DIR)/cpu_alu.sv \
	$(SRC_DIR)/cpu_execute.sv \
	$(SRC_DIR)/cpu_i_decoder.sv \
	$(SRC_DIR)/cpu_i_fetcher.sv \
	$(SRC_DIR)/cpu_lsu.sv \
	$(SRC_DIR)/cpu_writeback.sv \
	$(SRC_DIR)/cpu_commit.sv \
	$(SRC_DIR)/cpu_csr.sv \
	$(SRC_DIR)/cpu_reg_file.sv \
	$(SRC_DIR)/cpu_top.sv \
	$(HARNESS_DIR)/cpu_elf_harness_top.sv

HARNESS_CPP_SRCS = \
	$(HARNESS_DIR)/cpu_elf_harness.cpp \
	$(HARNESS_DIR)/elf_loader.cpp

.PHONY: harness lint_harness run_harness_elf debug_harness_elf

harness: $(HARNESS_BIN)

$(HARNESS_BIN): $(HARNESS_SV_SRCS) $(HARNESS_CPP_SRCS) | $(BUILD_DIR)
	source env.sh && $(VERILATOR) --cc --timing -Wall $(INC_FLAGS) -I$(HARNESS_DIR) \
		--top-module $(HARNESS_TOP) \
		$(HARNESS_SV_SRCS) \
		--exe $(HARNESS_CPP_SRCS) \
		--Mdir $(HARNESS_OBJ_DIR) \
		-o ../cpu_elf_harness
	$(MAKE) -C $(HARNESS_OBJ_DIR) -f V$(HARNESS_TOP).mk

lint_harness:
	source env.sh && $(VERILATOR) $(LINT_FLAGS) $(INC_FLAGS) -I$(HARNESS_DIR) \
		--top-module $(HARNESS_TOP) \
		$(HARNESS_SV_SRCS)

run_harness_elf: $(HARNESS_BIN)
	@test -n "$(ELF)" || (echo "usage: make run_harness_elf ELF=<program.elf> [MAX_CYCLES=N] [HARNESS_ARGS='...']" && exit 1)
	@$(HARNESS_BIN) $(ELF) --run --max-cycles=$(or $(MAX_CYCLES),10000) $(HARNESS_ARGS)

debug_harness_elf: $(HARNESS_BIN)
	@test -n "$(ELF)" || (echo "usage: make debug_harness_elf ELF=<program.elf> [MAX_CYCLES=N] [HARNESS_ARGS='...']" && exit 1)
	@$(HARNESS_BIN) $(ELF) --debug --max-cycles=$(or $(MAX_CYCLES),10000) $(HARNESS_ARGS)
