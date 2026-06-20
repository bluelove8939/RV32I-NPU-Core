`timescale 1ns/1ps

module cpu_top #(
    parameter logic [31:0] RESET_PC      = 32'h0000_0000,
    parameter logic [31:0] HART_ID       = 32'h0000_0000,
    parameter int unsigned ADDR_WIDTH    = 32,
    parameter int unsigned DATA_WIDTH    = 32,
    parameter int unsigned LINE_WORDS    = 16,
    parameter int unsigned LINE_WIDTH    = DATA_WIDTH * LINE_WORDS
) (
    input  logic                  clk,
    input  logic                  reset_n,
    input  logic                  cpu_enable_i,

    input  logic                  software_interrupt_pending_i,
    input  logic                  timer_interrupt_pending_i,
    input  logic                  external_interrupt_pending_i,

    input  logic                  lsu_flush_valid_i,
    output logic                  lsu_flush_ready_o,

    output logic                  i_spm_req_valid_o,
    input  logic                  i_spm_req_ready_i,
    output logic [ADDR_WIDTH-1:0] i_spm_req_line_addr_o,
    input  logic                  i_spm_resp_valid_i,
    output logic                  i_spm_resp_ready_o,
    input  logic [LINE_WIDTH-1:0] i_spm_resp_rdata_i,
    input  logic                  i_spm_resp_error_i,

    output logic                  d_spm_req_valid_o,
    input  logic                  d_spm_req_ready_i,
    output logic                  d_spm_req_write_o,
    output logic [ADDR_WIDTH-1:0] d_spm_req_line_addr_o,
    output logic [LINE_WIDTH-1:0] d_spm_req_wdata_o,
    output logic [LINE_WORDS-1:0] d_spm_req_wstrb_o,
    input  logic                  d_spm_resp_valid_i,
    output logic                  d_spm_resp_ready_o,
    input  logic [LINE_WIDTH-1:0] d_spm_resp_rdata_i,
    input  logic                  d_spm_resp_error_i,

    output logic                  debug_commit_valid_o,
    output logic [31:0]           debug_commit_pc_o,
    output logic [31:0]           debug_commit_instr_o,
    output logic                  debug_commit_exception_o,
    output logic                  debug_commit_interrupt_o,
    output logic                  debug_rf_we_o,
    output logic [4:0]            debug_rf_waddr_o,
    output logic [31:0]           debug_rf_wdata_o,
    output logic [31:0]           debug_fetch_pc_o
);

    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] instr;
        logic [31:0] rs1_value;
        logic [31:0] rs2_value;
        logic [4:0]  rd_addr;
        logic        rd_write;
        logic [31:0] imm;
        logic [3:0]  alu_op;
        logic [1:0]  op_a_sel;
        logic [1:0]  op_b_sel;
        logic        branch;
        logic [2:0]  branch_op;
        logic        jump;
        logic        jump_indirect;
        logic        load;
        logic        store;
        logic [1:0]  mem_size;
        logic        mem_unsigned;
        logic        csr_valid;
        logic [11:0] csr_addr;
        logic [2:0]  csr_op;
        logic        csr_write;
        logic        csr_imm;
        logic        system_ecall;
        logic        system_ebreak;
        logic        system_mret;
        logic [2:0]  wb_sel;
        logic        exception_valid;
        logic [31:0] exception_cause;
        logic [31:0] exception_tval;
    } id_ex_reg_t;

    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] instr;
        logic [31:0] pc_plus4;
        logic [31:0] alu_result;
        logic        load;
        logic        store;
        logic [1:0]  mem_size;
        logic        mem_unsigned;
        logic [31:0] mem_addr;
        logic [31:0] store_data;
        logic        csr_valid;
        logic [11:0] csr_addr;
        logic [2:0]  csr_op;
        logic        csr_write;
        logic [31:0] csr_wdata;
        logic [4:0]  rd_addr;
        logic        rd_write;
        logic [2:0]  wb_sel;
        logic        system_mret;
        logic        exception_valid;
        logic [31:0] exception_cause;
        logic [31:0] exception_tval;
    } mem_wb_reg_t;

    id_ex_reg_t id_ex_q;
    mem_wb_reg_t mem_wb_q;
    logic        mem_lsu_req_sent_q;

    logic                  fetch_snoop_valid;
    logic [ADDR_WIDTH-1:0] fetch_snoop_line_addr;
    logic                  lsu_snoop_stall;
    logic                  fetch_instr_valid;
    logic                  fetch_instr_ready;
    logic [31:0]           fetch_instr_pc;
    logic [31:0]           fetch_instr;
    logic                  fetch_exception_valid;
    logic [31:0]           fetch_exception_cause;
    logic [31:0]           fetch_exception_tval;
    logic                  fetch_stalled;

    logic        dec_valid;
    logic [31:0] dec_pc;
    logic [31:0] dec_instr;
    logic [4:0]  dec_rs1_addr;
    logic [4:0]  dec_rs2_addr;
    logic [4:0]  dec_rd_addr;
    logic        dec_rs1_used;
    logic        dec_rs2_used;
    logic        dec_rd_write;
    logic [31:0] dec_imm;
    logic [3:0]  dec_alu_op;
    logic [1:0]  dec_op_a_sel;
    logic [1:0]  dec_op_b_sel;
    logic        dec_branch;
    logic [2:0]  dec_branch_op;
    logic        dec_jump;
    logic        dec_jump_indirect;
    logic        dec_load;
    logic        dec_store;
    logic [1:0]  dec_mem_size;
    logic        dec_mem_unsigned;
    logic        dec_csr_valid;
    logic [11:0] dec_csr_addr;
    logic [2:0]  dec_csr_op;
    logic        dec_csr_write;
    logic        dec_csr_imm;
    logic        dec_system_ecall;
    logic        dec_system_ebreak;
    logic        dec_system_mret;
    logic [2:0]  dec_wb_sel;
    logic        dec_exception_valid;
    logic [31:0] dec_exception_cause;
    logic [31:0] dec_exception_tval;

    logic [31:0] rf_rs1_value;
    logic [31:0] rf_rs2_value;
    logic        rf_we;
    logic [4:0]  rf_waddr;
    logic [31:0] rf_wdata;
    logic [31:0] wb_data;
    logic [31:0] ex_operand_a_unused;
    logic [31:0] ex_operand_b_unused;
    logic        ex_branch_taken_unused;

    logic        ex_valid;
    logic [31:0] ex_pc;
    logic [31:0] ex_instr;
    logic [31:0] ex_pc_plus4;
    logic [31:0] ex_alu_result;
    logic        ex_redirect_valid;
    logic [31:0] ex_redirect_pc;
    logic        ex_load;
    logic        ex_store;
    logic [1:0]  ex_mem_size;
    logic        ex_mem_unsigned;
    logic [31:0] ex_mem_addr;
    logic [31:0] ex_store_data;
    logic        ex_csr_valid;
    logic [11:0] ex_csr_addr;
    logic [2:0]  ex_csr_op;
    logic        ex_csr_write;
    logic [31:0] ex_csr_wdata;
    logic [4:0]  ex_rd_addr;
    logic        ex_rd_write;
    logic [2:0]  ex_wb_sel;
    logic        ex_system_ecall;
    logic        ex_system_ebreak;
    logic        ex_system_mret;
    logic        ex_exception_valid;
    logic [31:0] ex_exception_cause;
    logic [31:0] ex_exception_tval;

    logic        lsu_req_valid;
    logic        lsu_req_ready;
    logic        lsu_flush_ready;
    logic        lsu_resp_valid;
    logic [31:0] lsu_resp_rdata;
    logic        lsu_resp_exception_valid;
    logic [31:0] lsu_resp_exception_cause;
    logic [31:0] lsu_resp_exception_tval;

    logic        csr_req_valid;
    logic [2:0]  csr_req_op;
    logic [11:0] csr_req_addr;
    logic [31:0] csr_req_wdata;
    logic        csr_raw_req_write;
    logic        commit_csr_req_write_unused;
    logic [31:0] csr_resp_rdata;
    logic        csr_resp_valid;
    logic        csr_resp_illegal;
    logic        csr_trap_valid;
    logic [31:0] csr_trap_mepc;
    logic [31:0] csr_trap_mcause;
    logic [31:0] csr_trap_mtval;
    logic        csr_mret_valid;
    logic        csr_instret_inc;
    logic [31:0] csr_mtvec;
    logic [31:0] csr_mstatus_unused;
    logic [31:0] csr_mie_unused;
    logic [31:0] csr_mscratch_unused;
    logic [31:0] csr_mepc;
    logic [31:0] csr_mcause_unused;
    logic [31:0] csr_mtval_unused;
    logic [31:0] csr_mip_unused;
    logic [63:0] csr_mcycle_unused;
    logic [63:0] csr_minstret_unused;
    logic        csr_interrupt_pending;
    logic [31:0] csr_interrupt_cause;
    logic        commit_redirect_valid;
    logic [31:0] commit_redirect_pc;
    logic        commit_retired;
    logic        commit_exception;
    logic        commit_interrupt;

    logic        mem_access;
    logic        mem_fence;
    logic        mem_complete;
    logic        mem_exception_valid;
    logic [31:0] mem_exception_cause;
    logic [31:0] mem_exception_tval;
    logic        commit_valid;
    logic        ex_to_mem_fire;
    logic        decode_hazard;
    logic        id_ex_can_accept;
    logic        decode_accept;
    logic        redirect_valid;
    logic [31:0] redirect_pc;

    assign mem_access = mem_wb_q.valid &&
                        !mem_wb_q.exception_valid &&
                        (mem_wb_q.load || mem_wb_q.store);
    assign mem_fence = mem_wb_q.valid &&
                       !mem_wb_q.exception_valid &&
                       (mem_wb_q.instr[6:0] == 7'b0001111);
    assign mem_complete = mem_wb_q.valid &&
                          (!mem_access || lsu_resp_valid) &&
                          (!mem_fence || lsu_flush_ready);
    assign mem_exception_valid = mem_wb_q.exception_valid ||
                                 (mem_access &&
                                  lsu_resp_exception_valid);
    assign mem_exception_cause = mem_wb_q.exception_valid ?
        mem_wb_q.exception_cause : lsu_resp_exception_cause;
    assign mem_exception_tval = mem_wb_q.exception_valid ?
        mem_wb_q.exception_tval : lsu_resp_exception_tval;
    assign commit_valid = mem_complete;

    assign redirect_valid = commit_redirect_valid || ex_redirect_valid;
    assign redirect_pc = commit_redirect_valid ? commit_redirect_pc :
                         ex_redirect_pc;

    assign ex_to_mem_fire = id_ex_q.valid && !mem_wb_q.valid &&
                            !commit_redirect_valid;
    assign id_ex_can_accept = !id_ex_q.valid || ex_to_mem_fire;

    assign decode_hazard =
        dec_valid &&
        (((dec_rs1_used && (dec_rs1_addr != 5'd0)) &&
          ((id_ex_q.valid && id_ex_q.rd_write &&
            (id_ex_q.rd_addr == dec_rs1_addr)) ||
           (mem_wb_q.valid && mem_wb_q.rd_write &&
            (mem_wb_q.rd_addr == dec_rs1_addr)))) ||
         ((dec_rs2_used && (dec_rs2_addr != 5'd0)) &&
          ((id_ex_q.valid && id_ex_q.rd_write &&
            (id_ex_q.rd_addr == dec_rs2_addr)) ||
           (mem_wb_q.valid && mem_wb_q.rd_write &&
            (mem_wb_q.rd_addr == dec_rs2_addr)))));

    assign decode_accept = cpu_enable_i &&
                           fetch_instr_valid &&
                           id_ex_can_accept &&
                           !decode_hazard &&
                           !redirect_valid;
    assign fetch_instr_ready = decode_accept;

    assign lsu_req_valid = mem_access &&
                           !mem_lsu_req_sent_q &&
                           !commit_redirect_valid;
    assign csr_raw_req_write = commit_valid &&
                               mem_wb_q.csr_valid &&
                               mem_wb_q.csr_write &&
                               !mem_exception_valid;

    assign debug_commit_valid_o = commit_valid;
    assign debug_commit_pc_o = mem_wb_q.pc;
    assign debug_commit_instr_o = mem_wb_q.instr;
    assign debug_commit_exception_o = commit_exception;
    assign debug_commit_interrupt_o = commit_interrupt;
    assign debug_rf_we_o = rf_we;
    assign debug_rf_waddr_o = rf_waddr;
    assign debug_rf_wdata_o = rf_wdata;

    cpu_i_fetcher #(
        .RESET_PC   (RESET_PC),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .LINE_WORDS (LINE_WORDS),
        .LINE_WIDTH (LINE_WIDTH)
    ) u_i_fetcher (
        .clk                       (clk),
        .reset_n                   (reset_n),
        .fetch_enable_i            (cpu_enable_i),
        .redirect_valid_i          (redirect_valid),
        .redirect_pc_i             (redirect_pc),
        .snoop_query_valid_o       (fetch_snoop_valid),
        .snoop_query_line_addr_o   (fetch_snoop_line_addr),
        .snoop_stall_i             (lsu_snoop_stall),
        .invalidate_valid_i        (fetch_snoop_valid && lsu_snoop_stall),
        .invalidate_line_addr_i    (fetch_snoop_line_addr),
        .instr_valid_o             (fetch_instr_valid),
        .instr_ready_i             (fetch_instr_ready),
        .instr_pc_o                (fetch_instr_pc),
        .instr_o                   (fetch_instr),
        .instr_exception_valid_o   (fetch_exception_valid),
        .instr_exception_cause_o   (fetch_exception_cause),
        .instr_exception_tval_o    (fetch_exception_tval),
        .spm_req_valid_o           (i_spm_req_valid_o),
        .spm_req_ready_i           (i_spm_req_ready_i),
        .spm_req_line_addr_o       (i_spm_req_line_addr_o),
        .spm_resp_valid_i          (i_spm_resp_valid_i),
        .spm_resp_ready_o          (i_spm_resp_ready_o),
        .spm_resp_rdata_i          (i_spm_resp_rdata_i),
        .spm_resp_error_i          (i_spm_resp_error_i),
        .fetch_pc_o                (debug_fetch_pc_o),
        .fetch_stalled_o           (fetch_stalled)
    );

    cpu_i_decoder u_i_decoder (
        .instr_valid_i             (fetch_instr_valid),
        .instr_pc_i                (fetch_instr_pc),
        .instr_i                   (fetch_instr),
        .instr_exception_valid_i   (fetch_exception_valid),
        .instr_exception_cause_i   (fetch_exception_cause),
        .instr_exception_tval_i    (fetch_exception_tval),
        .decode_valid_o            (dec_valid),
        .decode_pc_o               (dec_pc),
        .decode_instr_o            (dec_instr),
        .rs1_addr_o                (dec_rs1_addr),
        .rs2_addr_o                (dec_rs2_addr),
        .rd_addr_o                 (dec_rd_addr),
        .rs1_used_o                (dec_rs1_used),
        .rs2_used_o                (dec_rs2_used),
        .rd_write_o                (dec_rd_write),
        .imm_o                     (dec_imm),
        .alu_op_o                  (dec_alu_op),
        .op_a_sel_o                (dec_op_a_sel),
        .op_b_sel_o                (dec_op_b_sel),
        .branch_o                  (dec_branch),
        .branch_op_o               (dec_branch_op),
        .jump_o                    (dec_jump),
        .jump_indirect_o           (dec_jump_indirect),
        .load_o                    (dec_load),
        .store_o                   (dec_store),
        .mem_size_o                (dec_mem_size),
        .mem_unsigned_o            (dec_mem_unsigned),
        .csr_valid_o               (dec_csr_valid),
        .csr_addr_o                (dec_csr_addr),
        .csr_op_o                  (dec_csr_op),
        .csr_write_o               (dec_csr_write),
        .csr_imm_o                 (dec_csr_imm),
        .system_ecall_o            (dec_system_ecall),
        .system_ebreak_o           (dec_system_ebreak),
        .system_mret_o             (dec_system_mret),
        .wb_sel_o                  (dec_wb_sel),
        .exception_valid_o         (dec_exception_valid),
        .exception_cause_o         (dec_exception_cause),
        .exception_tval_o          (dec_exception_tval)
    );

    cpu_reg_file u_reg_file (
        .clk     (clk),
        .reset_n (reset_n),
        .raddr0_i(dec_rs1_addr),
        .rdata0_o(rf_rs1_value),
        .raddr1_i(dec_rs2_addr),
        .rdata1_o(rf_rs2_value),
        .we_i    (rf_we),
        .waddr_i (rf_waddr),
        .wdata_i (rf_wdata)
    );

    cpu_execute u_execute (
        .execute_valid_i    (id_ex_q.valid),
        .pc_i               (id_ex_q.pc),
        .instr_i            (id_ex_q.instr),
        .rs1_value_i        (id_ex_q.rs1_value),
        .rs2_value_i        (id_ex_q.rs2_value),
        .imm_i              (id_ex_q.imm),
        .alu_op_i           (id_ex_q.alu_op),
        .op_a_sel_i         (id_ex_q.op_a_sel),
        .op_b_sel_i         (id_ex_q.op_b_sel),
        .branch_i           (id_ex_q.branch),
        .branch_op_i        (id_ex_q.branch_op),
        .jump_i             (id_ex_q.jump),
        .jump_indirect_i    (id_ex_q.jump_indirect),
        .load_i             (id_ex_q.load),
        .store_i            (id_ex_q.store),
        .mem_size_i         (id_ex_q.mem_size),
        .mem_unsigned_i     (id_ex_q.mem_unsigned),
        .csr_valid_i        (id_ex_q.csr_valid),
        .csr_addr_i         (id_ex_q.csr_addr),
        .csr_op_i           (id_ex_q.csr_op),
        .csr_write_i        (id_ex_q.csr_write),
        .csr_imm_i          (id_ex_q.csr_imm),
        .rd_addr_i          (id_ex_q.rd_addr),
        .rd_write_i         (id_ex_q.rd_write),
        .wb_sel_i           (id_ex_q.wb_sel),
        .system_ecall_i     (id_ex_q.system_ecall),
        .system_ebreak_i    (id_ex_q.system_ebreak),
        .system_mret_i      (id_ex_q.system_mret),
        .exception_valid_i  (id_ex_q.exception_valid),
        .exception_cause_i  (id_ex_q.exception_cause),
        .exception_tval_i   (id_ex_q.exception_tval),
        .execute_valid_o    (ex_valid),
        .pc_o               (ex_pc),
        .instr_o            (ex_instr),
        .pc_plus4_o         (ex_pc_plus4),
        .operand_a_o        (ex_operand_a_unused),
        .operand_b_o        (ex_operand_b_unused),
        .alu_result_o       (ex_alu_result),
        .branch_taken_o     (ex_branch_taken_unused),
        .redirect_valid_o   (ex_redirect_valid),
        .redirect_pc_o      (ex_redirect_pc),
        .load_o             (ex_load),
        .store_o            (ex_store),
        .mem_size_o         (ex_mem_size),
        .mem_unsigned_o     (ex_mem_unsigned),
        .mem_addr_o         (ex_mem_addr),
        .store_data_o       (ex_store_data),
        .csr_valid_o        (ex_csr_valid),
        .csr_addr_o         (ex_csr_addr),
        .csr_op_o           (ex_csr_op),
        .csr_write_o        (ex_csr_write),
        .csr_wdata_o        (ex_csr_wdata),
        .rd_addr_o          (ex_rd_addr),
        .rd_write_o         (ex_rd_write),
        .wb_sel_o           (ex_wb_sel),
        .system_ecall_o     (ex_system_ecall),
        .system_ebreak_o    (ex_system_ebreak),
        .system_mret_o      (ex_system_mret),
        .exception_valid_o  (ex_exception_valid),
        .exception_cause_o  (ex_exception_cause),
        .exception_tval_o   (ex_exception_tval)
    );

    cpu_lsu #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .LINE_WORDS (LINE_WORDS),
        .LINE_WIDTH (LINE_WIDTH)
    ) u_lsu (
        .clk                    (clk),
        .reset_n                (reset_n),
        .req_valid_i            (lsu_req_valid),
        .req_ready_o            (lsu_req_ready),
        .req_write_i            (mem_wb_q.store),
        .req_addr_i             (mem_wb_q.mem_addr),
        .req_wdata_i            (mem_wb_q.store_data),
        .req_size_i             (mem_wb_q.mem_size),
        .req_unsigned_i         (mem_wb_q.mem_unsigned),
        .resp_valid_o           (lsu_resp_valid),
        .resp_ready_i           (mem_access && lsu_resp_valid),
        .resp_rdata_o           (lsu_resp_rdata),
        .resp_exception_valid_o (lsu_resp_exception_valid),
        .resp_exception_cause_o (lsu_resp_exception_cause),
        .resp_exception_tval_o  (lsu_resp_exception_tval),
        .snoop_valid_i          (fetch_snoop_valid),
        .snoop_line_addr_i      (fetch_snoop_line_addr),
        .snoop_stall_o          (lsu_snoop_stall),
        .flush_valid_i          (lsu_flush_valid_i || mem_fence),
        .flush_ready_o          (lsu_flush_ready),
        .spm_req_valid_o        (d_spm_req_valid_o),
        .spm_req_ready_i        (d_spm_req_ready_i),
        .spm_req_write_o        (d_spm_req_write_o),
        .spm_req_line_addr_o    (d_spm_req_line_addr_o),
        .spm_req_wdata_o        (d_spm_req_wdata_o),
        .spm_req_wstrb_o        (d_spm_req_wstrb_o),
        .spm_resp_valid_i       (d_spm_resp_valid_i),
        .spm_resp_ready_o       (d_spm_resp_ready_o),
        .spm_resp_rdata_i       (d_spm_resp_rdata_i),
        .spm_resp_error_i       (d_spm_resp_error_i)
    );

    cpu_writeback u_writeback (
        .wb_valid_i        (commit_valid),
        .rd_addr_i         (mem_wb_q.rd_addr),
        .rd_write_i        (mem_wb_q.rd_write),
        .wb_sel_i          (mem_wb_q.wb_sel),
        .alu_result_i      (mem_wb_q.alu_result),
        .load_data_i       (lsu_resp_rdata),
        .csr_rdata_i       (csr_resp_rdata),
        .pc_plus4_i        (mem_wb_q.pc_plus4),
        .exception_valid_i (mem_exception_valid || csr_resp_illegal),
        .rf_we_o           (rf_we),
        .rf_waddr_o        (rf_waddr),
        .rf_wdata_o        (rf_wdata),
        .wb_data_o         (wb_data)
    );

    cpu_commit u_commit (
        .commit_valid_i      (commit_valid),
        .commit_pc_i         (mem_wb_q.pc),
        .commit_pc_plus4_i   (mem_wb_q.pc_plus4),
        .commit_instr_i      (mem_wb_q.instr),
        .exception_valid_i   (mem_exception_valid),
        .exception_cause_i   (mem_exception_cause),
        .exception_tval_i    (mem_exception_tval),
        .csr_valid_i         (mem_wb_q.csr_valid),
        .csr_addr_i          (mem_wb_q.csr_addr),
        .csr_op_i            (mem_wb_q.csr_op),
        .csr_write_i         (mem_wb_q.csr_write),
        .csr_wdata_i         (mem_wb_q.csr_wdata),
        .csr_resp_illegal_i  (csr_resp_illegal),
        .system_mret_i       (mem_wb_q.system_mret),
        .interrupt_pending_i (csr_interrupt_pending),
        .interrupt_cause_i   (csr_interrupt_cause),
        .mtvec_i             (csr_mtvec),
        .mepc_i              (csr_mepc),
        .csr_req_valid_o     (csr_req_valid),
        .csr_req_op_o        (csr_req_op),
        .csr_req_addr_o      (csr_req_addr),
        .csr_req_wdata_o     (csr_req_wdata),
        .csr_req_write_o     (commit_csr_req_write_unused),
        .trap_valid_o        (csr_trap_valid),
        .trap_mepc_o         (csr_trap_mepc),
        .trap_mcause_o       (csr_trap_mcause),
        .trap_mtval_o        (csr_trap_mtval),
        .mret_valid_o        (csr_mret_valid),
        .instret_inc_o       (csr_instret_inc),
        .redirect_valid_o    (commit_redirect_valid),
        .redirect_pc_o       (commit_redirect_pc),
        .commit_retired_o    (commit_retired),
        .commit_exception_o  (commit_exception),
        .commit_interrupt_o  (commit_interrupt)
    );

    cpu_csr #(
        .HART_ID(HART_ID)
    ) u_csr (
        .clk                          (clk),
        .reset_n                      (reset_n),
        .csr_req_valid_i              (csr_req_valid),
        .csr_req_op_i                 (csr_req_op),
        .csr_req_addr_i               (csr_req_addr),
        .csr_req_wdata_i              (csr_req_wdata),
        .csr_req_write_i              (csr_raw_req_write),
        .csr_resp_rdata_o             (csr_resp_rdata),
        .csr_resp_valid_o             (csr_resp_valid),
        .csr_resp_illegal_o           (csr_resp_illegal),
        .instret_inc_i                (csr_instret_inc),
        .trap_valid_i                 (csr_trap_valid),
        .trap_mepc_i                  (csr_trap_mepc),
        .trap_mcause_i                (csr_trap_mcause),
        .trap_mtval_i                 (csr_trap_mtval),
        .mret_valid_i                 (csr_mret_valid),
        .software_interrupt_pending_i (software_interrupt_pending_i),
        .timer_interrupt_pending_i    (timer_interrupt_pending_i),
        .external_interrupt_pending_i (external_interrupt_pending_i),
        .mstatus_o                    (csr_mstatus_unused),
        .mie_o                        (csr_mie_unused),
        .mtvec_o                      (csr_mtvec),
        .mscratch_o                   (csr_mscratch_unused),
        .mepc_o                       (csr_mepc),
        .mcause_o                     (csr_mcause_unused),
        .mtval_o                      (csr_mtval_unused),
        .mip_o                        (csr_mip_unused),
        .mcycle_o                     (csr_mcycle_unused),
        .minstret_o                   (csr_minstret_unused),
        .interrupt_pending_o          (csr_interrupt_pending),
        .interrupt_cause_o            (csr_interrupt_cause)
    );

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            id_ex_q <= '0;
        end else begin
            if (commit_redirect_valid) begin
                id_ex_q <= '0;
            end else begin
                if (ex_to_mem_fire) begin
                    id_ex_q.valid <= 1'b0;
                end

                if (decode_accept) begin
                    id_ex_q.valid <= 1'b1;
                    id_ex_q.pc <= dec_pc;
                    id_ex_q.instr <= dec_instr;
                    id_ex_q.rs1_value <= rf_rs1_value;
                    id_ex_q.rs2_value <= rf_rs2_value;
                    id_ex_q.rd_addr <= dec_rd_addr;
                    id_ex_q.rd_write <= dec_rd_write;
                    id_ex_q.imm <= dec_imm;
                    id_ex_q.alu_op <= dec_alu_op;
                    id_ex_q.op_a_sel <= dec_op_a_sel;
                    id_ex_q.op_b_sel <= dec_op_b_sel;
                    id_ex_q.branch <= dec_branch;
                    id_ex_q.branch_op <= dec_branch_op;
                    id_ex_q.jump <= dec_jump;
                    id_ex_q.jump_indirect <= dec_jump_indirect;
                    id_ex_q.load <= dec_load;
                    id_ex_q.store <= dec_store;
                    id_ex_q.mem_size <= dec_mem_size;
                    id_ex_q.mem_unsigned <= dec_mem_unsigned;
                    id_ex_q.csr_valid <= dec_csr_valid;
                    id_ex_q.csr_addr <= dec_csr_addr;
                    id_ex_q.csr_op <= dec_csr_op;
                    id_ex_q.csr_write <= dec_csr_write;
                    id_ex_q.csr_imm <= dec_csr_imm;
                    id_ex_q.system_ecall <= dec_system_ecall;
                    id_ex_q.system_ebreak <= dec_system_ebreak;
                    id_ex_q.system_mret <= dec_system_mret;
                    id_ex_q.wb_sel <= dec_wb_sel;
                    id_ex_q.exception_valid <= dec_exception_valid;
                    id_ex_q.exception_cause <= dec_exception_cause;
                    id_ex_q.exception_tval <= dec_exception_tval;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            mem_wb_q <= '0;
            mem_lsu_req_sent_q <= 1'b0;
        end else begin
            if (commit_valid) begin
                mem_wb_q.valid <= 1'b0;
                mem_lsu_req_sent_q <= 1'b0;
            end

            if (lsu_req_valid && lsu_req_ready) begin
                mem_lsu_req_sent_q <= 1'b1;
            end

            if (commit_redirect_valid) begin
                mem_wb_q.valid <= 1'b0;
                mem_lsu_req_sent_q <= 1'b0;
            end else if (ex_to_mem_fire) begin
                mem_wb_q.valid <= ex_valid;
                mem_wb_q.pc <= ex_pc;
                mem_wb_q.instr <= ex_instr;
                mem_wb_q.pc_plus4 <= ex_pc_plus4;
                mem_wb_q.alu_result <= ex_alu_result;
                mem_wb_q.load <= ex_load;
                mem_wb_q.store <= ex_store;
                mem_wb_q.mem_size <= ex_mem_size;
                mem_wb_q.mem_unsigned <= ex_mem_unsigned;
                mem_wb_q.mem_addr <= ex_mem_addr;
                mem_wb_q.store_data <= ex_store_data;
                mem_wb_q.csr_valid <= ex_csr_valid;
                mem_wb_q.csr_addr <= ex_csr_addr;
                mem_wb_q.csr_op <= ex_csr_op;
                mem_wb_q.csr_write <= ex_csr_write;
                mem_wb_q.csr_wdata <= ex_csr_wdata;
                mem_wb_q.rd_addr <= ex_rd_addr;
                mem_wb_q.rd_write <= ex_rd_write;
                mem_wb_q.wb_sel <= ex_wb_sel;
                mem_wb_q.system_mret <= ex_system_mret;
                mem_wb_q.exception_valid <= ex_exception_valid;
                mem_wb_q.exception_cause <= ex_exception_cause;
                mem_wb_q.exception_tval <= ex_exception_tval;
                mem_lsu_req_sent_q <= 1'b0;
            end
        end
    end

    logic unused_top_signals;
    assign lsu_flush_ready_o = lsu_flush_ready && !mem_fence;
    assign unused_top_signals = fetch_stalled ^
                                csr_resp_valid ^
                                commit_retired ^
                                (^wb_data) ^
                                (^ex_operand_a_unused) ^
                                (^ex_operand_b_unused) ^
                                ex_branch_taken_unused ^
                                ex_system_ecall ^
                                ex_system_ebreak ^
                                commit_csr_req_write_unused ^
                                (^csr_mstatus_unused) ^
                                (^csr_mie_unused) ^
                                (^csr_mscratch_unused) ^
                                (^csr_mcause_unused) ^
                                (^csr_mtval_unused) ^
                                (^csr_mip_unused) ^
                                (^csr_mcycle_unused) ^
                                (^csr_minstret_unused);

endmodule
