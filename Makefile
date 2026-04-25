# Verilator Makefile for RV32I-NPU-Core

VERILATOR = verilator
# --binary: Use SystemVerilog testbench as top-level and generate executable
# -Wall: Enable all warnings
# --trace: Enable waveform tracing (VCD)
# -j: Use all available cores for parallel build
VERILATOR_FLAGS = --binary -Wall -Wno-UNUSEDSIGNAL --trace -j 0 --Mdir $(BUILD_DIR)/obj_dir

# Directory paths
SRC_DIR = srcs
TB_DIR  = tb
BUILD_DIR = build

# Include paths
INC_FLAGS = -I$(SRC_DIR)/component \
            -I$(SRC_DIR)/core \
            -I$(TB_DIR)/component

# List of testbenches
TBS = tb_rv_spm
# Create run targets (e.g., run_tb_rv_spm)
RUN_TBS = $(addprefix run_, $(TBS))

.PHONY: all clean $(TBS) $(RUN_TBS)

all: $(TBS)

# Run rules: Build then execute
$(RUN_TBS): run_%: %
	@echo "------------------------------------------------------------"
	@echo "Running simulation: $(BUILD_DIR)/$*"
	@echo "------------------------------------------------------------"
	./$(BUILD_DIR)/$*

# Rule for tb_rv_spm
tb_rv_spm: $(BUILD_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) $(INC_FLAGS) \
		$(SRC_DIR)/component/rv_spm_bank.sv \
		$(SRC_DIR)/component/rv_spm.sv \
		$(TB_DIR)/component/tb_rv_spm.sv \
		-o ../$@

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR)
	@echo "Cleanup complete."
