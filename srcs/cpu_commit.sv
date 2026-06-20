`timescale 1ns/1ps

module cpu_commit (
    input  logic        commit_valid_i,
    input  logic [31:0] commit_pc_i,
    input  logic [31:0] commit_pc_plus4_i,
    input  logic [31:0] commit_instr_i,

    input  logic        exception_valid_i,
    input  logic [31:0] exception_cause_i,
    input  logic [31:0] exception_tval_i,

    input  logic        csr_valid_i,
    input  logic [11:0] csr_addr_i,
    input  logic [2:0]  csr_op_i,
    input  logic        csr_write_i,
    input  logic [31:0] csr_wdata_i,
    input  logic        csr_resp_illegal_i,

    input  logic        system_mret_i,

    input  logic        interrupt_pending_i,
    input  logic [31:0] interrupt_cause_i,
    input  logic [31:0] mtvec_i,
    input  logic [31:0] mepc_i,

    output logic        csr_req_valid_o,
    output logic [2:0]  csr_req_op_o,
    output logic [11:0] csr_req_addr_o,
    output logic [31:0] csr_req_wdata_o,
    output logic        csr_req_write_o,

    output logic        trap_valid_o,
    output logic [31:0] trap_mepc_o,
    output logic [31:0] trap_mcause_o,
    output logic [31:0] trap_mtval_o,

    output logic        mret_valid_o,
    output logic        instret_inc_o,

    output logic        redirect_valid_o,
    output logic [31:0] redirect_pc_o,

    output logic        commit_retired_o,
    output logic        commit_exception_o,
    output logic        commit_interrupt_o
);

    localparam logic [31:0] EXC_ILLEGAL_INSTRUCTION = 32'd2;

    logic active;
    logic csr_illegal;
    logic take_exception;
    logic take_interrupt;
    logic take_mret;

    assign active = commit_valid_i;

    assign csr_req_valid_o = active && csr_valid_i && !exception_valid_i;
    assign csr_req_op_o = csr_op_i;
    assign csr_req_addr_o = csr_addr_i;
    assign csr_req_wdata_o = csr_wdata_i;
    assign csr_req_write_o = active && csr_valid_i && csr_write_i &&
                             !exception_valid_i && !csr_resp_illegal_i;

    assign csr_illegal = csr_req_valid_o && csr_resp_illegal_i;
    assign take_exception = active && (exception_valid_i || csr_illegal);
    assign take_mret = active && system_mret_i && !take_exception;
    assign take_interrupt = active &&
                            interrupt_pending_i &&
                            !take_exception &&
                            !take_mret;

    assign trap_valid_o = take_exception || take_interrupt;
    assign trap_mepc_o = take_interrupt ? commit_pc_plus4_i : commit_pc_i;
    assign trap_mcause_o = take_interrupt ? interrupt_cause_i :
                           (csr_illegal ? EXC_ILLEGAL_INSTRUCTION :
                                          exception_cause_i);
    assign trap_mtval_o = take_interrupt ? 32'h0000_0000 :
                          (csr_illegal ? commit_instr_i :
                                         exception_tval_i);

    assign mret_valid_o = take_mret;

    assign instret_inc_o = active && !take_exception;
    assign commit_retired_o = instret_inc_o;
    assign commit_exception_o = take_exception;
    assign commit_interrupt_o = take_interrupt;

    assign redirect_valid_o = trap_valid_o || take_mret;
    assign redirect_pc_o = trap_valid_o ? mtvec_i :
                           (take_mret ? mepc_i : 32'h0000_0000);

endmodule
