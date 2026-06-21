SHELL := /bin/bash

VERILATOR = verilator
VERILATOR_FLAGS = --binary --timing -Wall
LINT_FLAGS = --lint-only --timing -Wall
export CCACHE_DISABLE ?= 1

SRC_DIR = srcs
TB_DIR  = tb
BUILD_DIR = build

INC_FLAGS = -I$(SRC_DIR) -I$(TB_DIR)

TBS = tb_spm_bus tb_cpu_state tb_cpu_i_fetcher tb_cpu_i_decoder tb_cpu_alu tb_cpu_execute tb_cpu_lsu tb_cpu_writeback tb_cpu_commit tb_cpu_top tb_cpu_top_tests
RUN_TBS = $(addprefix run_, $(TBS))
LINT_TBS = $(addprefix lint_, $(TBS))
CPU_TOP_TEST_BINS = \
	$(TB_DIR)/cpu_top_tests/t1_arithmetic_operation.bin \
	$(TB_DIR)/cpu_top_tests/t2_procedures.bin \
	$(TB_DIR)/cpu_top_tests/t3_trap.bin \
	$(TB_DIR)/cpu_top_tests/t4_ecall.bin \
	$(TB_DIR)/cpu_top_tests/t5_fence_and_flush.bin \
	$(TB_DIR)/cpu_top_tests/t6_external_interrupt.bin \
	$(TB_DIR)/cpu_top_tests/t7_ecall_syscall_abi.bin \
	$(TB_DIR)/cpu_top_tests/t8_load_store_widths.bin \
	$(TB_DIR)/cpu_top_tests/t9_misaligned_load_store_trap.bin \
	$(TB_DIR)/cpu_top_tests/t10_csr_ops.bin

TB_SPM_BUS_SRCS = \
	$(SRC_DIR)/spm_bank.sv \
	$(SRC_DIR)/spm_bankgroup.sv \
	$(SRC_DIR)/spm_bus.sv \
	$(TB_DIR)/tb_spm_bus.sv

TB_CPU_STATE_SRCS = \
	$(SRC_DIR)/cpu_reg_file.sv \
	$(SRC_DIR)/cpu_csr.sv \
	$(TB_DIR)/tb_cpu_state.sv

TB_CPU_I_FETCHER_SRCS = \
	$(SRC_DIR)/spm_bank.sv \
	$(SRC_DIR)/spm_bankgroup.sv \
	$(SRC_DIR)/spm_bus.sv \
	$(SRC_DIR)/cpu_i_fetcher.sv \
	$(TB_DIR)/tb_cpu_i_fetcher.sv

TB_CPU_I_DECODER_SRCS = \
	$(SRC_DIR)/cpu_i_decoder.sv \
	$(TB_DIR)/tb_cpu_i_decoder.sv

TB_CPU_ALU_SRCS = \
	$(SRC_DIR)/cpu_alu.sv \
	$(TB_DIR)/tb_cpu_alu.sv

TB_CPU_EXECUTE_SRCS = \
	$(SRC_DIR)/cpu_alu.sv \
	$(SRC_DIR)/cpu_execute.sv \
	$(TB_DIR)/tb_cpu_execute.sv

TB_CPU_LSU_SRCS = \
	$(SRC_DIR)/spm_bank.sv \
	$(SRC_DIR)/spm_bankgroup.sv \
	$(SRC_DIR)/spm_bus.sv \
	$(SRC_DIR)/cpu_lsu.sv \
	$(TB_DIR)/tb_cpu_lsu.sv

TB_CPU_WRITEBACK_SRCS = \
	$(SRC_DIR)/cpu_writeback.sv \
	$(TB_DIR)/tb_cpu_writeback.sv

TB_CPU_COMMIT_SRCS = \
	$(SRC_DIR)/cpu_commit.sv \
	$(TB_DIR)/tb_cpu_commit.sv

TB_CPU_TOP_SRCS = \
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
	$(TB_DIR)/tb_cpu_top.sv

TB_CPU_TOP_TESTS_SRCS = \
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
	$(TB_DIR)/tb_cpu_top_tests.sv

-include harness/Makefile

.PHONY: all clean lint run_cpu_top_test_bins $(TBS) $(RUN_TBS) $(LINT_TBS)

all: $(TBS)

lint: $(LINT_TBS)

tb_spm_bus: $(BUILD_DIR)/tb_spm_bus

tb_cpu_state: $(BUILD_DIR)/tb_cpu_state

tb_cpu_i_fetcher: $(BUILD_DIR)/tb_cpu_i_fetcher

tb_cpu_i_decoder: $(BUILD_DIR)/tb_cpu_i_decoder

tb_cpu_alu: $(BUILD_DIR)/tb_cpu_alu

tb_cpu_execute: $(BUILD_DIR)/tb_cpu_execute

tb_cpu_lsu: $(BUILD_DIR)/tb_cpu_lsu

tb_cpu_writeback: $(BUILD_DIR)/tb_cpu_writeback

tb_cpu_commit: $(BUILD_DIR)/tb_cpu_commit

tb_cpu_top: $(BUILD_DIR)/tb_cpu_top

tb_cpu_top_tests: $(BUILD_DIR)/tb_cpu_top_tests

$(BUILD_DIR)/tb_spm_bus: $(TB_SPM_BUS_SRCS) | $(BUILD_DIR)
	source env.sh && $(VERILATOR) $(VERILATOR_FLAGS) $(INC_FLAGS) \
		--top-module tb_spm_bus \
		$(TB_SPM_BUS_SRCS) \
		--Mdir $(BUILD_DIR)/obj_tb_spm_bus \
		-o ../tb_spm_bus

lint_tb_spm_bus:
	source env.sh && $(VERILATOR) $(LINT_FLAGS) $(INC_FLAGS) \
		--top-module tb_spm_bus \
		$(TB_SPM_BUS_SRCS)

$(BUILD_DIR)/tb_cpu_state: $(TB_CPU_STATE_SRCS) | $(BUILD_DIR)
	source env.sh && $(VERILATOR) $(VERILATOR_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_state \
		$(TB_CPU_STATE_SRCS) \
		--Mdir $(BUILD_DIR)/obj_tb_cpu_state \
		-o ../tb_cpu_state

lint_tb_cpu_state:
	source env.sh && $(VERILATOR) $(LINT_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_state \
		$(TB_CPU_STATE_SRCS)

$(BUILD_DIR)/tb_cpu_i_fetcher: $(TB_CPU_I_FETCHER_SRCS) | $(BUILD_DIR)
	source env.sh && $(VERILATOR) $(VERILATOR_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_i_fetcher \
		$(TB_CPU_I_FETCHER_SRCS) \
		--Mdir $(BUILD_DIR)/obj_tb_cpu_i_fetcher \
		-o ../tb_cpu_i_fetcher

lint_tb_cpu_i_fetcher:
	source env.sh && $(VERILATOR) $(LINT_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_i_fetcher \
		$(TB_CPU_I_FETCHER_SRCS)

$(BUILD_DIR)/tb_cpu_i_decoder: $(TB_CPU_I_DECODER_SRCS) | $(BUILD_DIR)
	source env.sh && $(VERILATOR) $(VERILATOR_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_i_decoder \
		$(TB_CPU_I_DECODER_SRCS) \
		--Mdir $(BUILD_DIR)/obj_tb_cpu_i_decoder \
		-o ../tb_cpu_i_decoder

lint_tb_cpu_i_decoder:
	source env.sh && $(VERILATOR) $(LINT_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_i_decoder \
		$(TB_CPU_I_DECODER_SRCS)

$(BUILD_DIR)/tb_cpu_alu: $(TB_CPU_ALU_SRCS) | $(BUILD_DIR)
	source env.sh && $(VERILATOR) $(VERILATOR_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_alu \
		$(TB_CPU_ALU_SRCS) \
		--Mdir $(BUILD_DIR)/obj_tb_cpu_alu \
		-o ../tb_cpu_alu

lint_tb_cpu_alu:
	source env.sh && $(VERILATOR) $(LINT_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_alu \
		$(TB_CPU_ALU_SRCS)

$(BUILD_DIR)/tb_cpu_execute: $(TB_CPU_EXECUTE_SRCS) | $(BUILD_DIR)
	source env.sh && $(VERILATOR) $(VERILATOR_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_execute \
		$(TB_CPU_EXECUTE_SRCS) \
		--Mdir $(BUILD_DIR)/obj_tb_cpu_execute \
		-o ../tb_cpu_execute

lint_tb_cpu_execute:
	source env.sh && $(VERILATOR) $(LINT_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_execute \
		$(TB_CPU_EXECUTE_SRCS)

$(BUILD_DIR)/tb_cpu_lsu: $(TB_CPU_LSU_SRCS) | $(BUILD_DIR)
	source env.sh && $(VERILATOR) $(VERILATOR_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_lsu \
		$(TB_CPU_LSU_SRCS) \
		--Mdir $(BUILD_DIR)/obj_tb_cpu_lsu \
		-o ../tb_cpu_lsu

lint_tb_cpu_lsu:
	source env.sh && $(VERILATOR) $(LINT_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_lsu \
		$(TB_CPU_LSU_SRCS)

$(BUILD_DIR)/tb_cpu_writeback: $(TB_CPU_WRITEBACK_SRCS) | $(BUILD_DIR)
	source env.sh && $(VERILATOR) $(VERILATOR_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_writeback \
		$(TB_CPU_WRITEBACK_SRCS) \
		--Mdir $(BUILD_DIR)/obj_tb_cpu_writeback \
		-o ../tb_cpu_writeback

lint_tb_cpu_writeback:
	source env.sh && $(VERILATOR) $(LINT_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_writeback \
		$(TB_CPU_WRITEBACK_SRCS)

$(BUILD_DIR)/tb_cpu_commit: $(TB_CPU_COMMIT_SRCS) | $(BUILD_DIR)
	source env.sh && $(VERILATOR) $(VERILATOR_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_commit \
		$(TB_CPU_COMMIT_SRCS) \
		--Mdir $(BUILD_DIR)/obj_tb_cpu_commit \
		-o ../tb_cpu_commit

lint_tb_cpu_commit:
	source env.sh && $(VERILATOR) $(LINT_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_commit \
		$(TB_CPU_COMMIT_SRCS)

$(BUILD_DIR)/tb_cpu_top: $(TB_CPU_TOP_SRCS) | $(BUILD_DIR)
	source env.sh && $(VERILATOR) $(VERILATOR_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_top \
		$(TB_CPU_TOP_SRCS) \
		--Mdir $(BUILD_DIR)/obj_tb_cpu_top \
		-o ../tb_cpu_top

lint_tb_cpu_top:
	source env.sh && $(VERILATOR) $(LINT_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_top \
		$(TB_CPU_TOP_SRCS)

$(BUILD_DIR)/tb_cpu_top_tests: $(TB_CPU_TOP_TESTS_SRCS) | $(BUILD_DIR)
	source env.sh && $(VERILATOR) $(VERILATOR_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_top_tests \
		$(TB_CPU_TOP_TESTS_SRCS) \
		--Mdir $(BUILD_DIR)/obj_tb_cpu_top_tests \
		-o ../tb_cpu_top_tests

lint_tb_cpu_top_tests:
	source env.sh && $(VERILATOR) $(LINT_FLAGS) $(INC_FLAGS) \
		--top-module tb_cpu_top_tests \
		$(TB_CPU_TOP_TESTS_SRCS)

run_cpu_top_test_bins: $(BUILD_DIR)/tb_cpu_top_tests
	@set -e; \
	for bin in $(CPU_TOP_TEST_BINS); do \
		echo "------------------------------------------------------------"; \
		echo "Running CPU top program test: $$bin"; \
		echo "------------------------------------------------------------"; \
		$(BUILD_DIR)/tb_cpu_top_tests +BIN=$$bin; \
	done

$(RUN_TBS): run_%: $(BUILD_DIR)/%
	@echo "------------------------------------------------------------"
	@echo "Running simulation: $<"
	@echo "------------------------------------------------------------"
	$<

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR)
	@echo "Cleanup complete."
