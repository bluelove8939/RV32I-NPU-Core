`timescale 1ns/1ps

module cpu_execute (
    input  logic        execute_valid_i,
    input  logic [31:0] pc_i,
    input  logic [31:0] instr_i,

    input  logic [31:0] rs1_value_i,
    input  logic [31:0] rs2_value_i,
    input  logic [31:0] imm_i,

    input  logic [3:0]  alu_op_i,
    input  logic [1:0]  op_a_sel_i,
    input  logic [1:0]  op_b_sel_i,

    input  logic        branch_i,
    input  logic [2:0]  branch_op_i,
    input  logic        jump_i,
    input  logic        jump_indirect_i,

    input  logic        load_i,
    input  logic        store_i,
    input  logic [1:0]  mem_size_i,
    input  logic        mem_unsigned_i,

    input  logic        csr_valid_i,
    input  logic [11:0] csr_addr_i,
    input  logic [2:0]  csr_op_i,
    input  logic        csr_write_i,
    input  logic        csr_imm_i,

    input  logic [4:0]  rd_addr_i,
    input  logic        rd_write_i,
    input  logic [2:0]  wb_sel_i,

    input  logic        system_ecall_i,
    input  logic        system_ebreak_i,
    input  logic        system_mret_i,

    input  logic        exception_valid_i,
    input  logic [31:0] exception_cause_i,
    input  logic [31:0] exception_tval_i,

    output logic        execute_valid_o,
    output logic [31:0] pc_o,
    output logic [31:0] instr_o,
    output logic [31:0] pc_plus4_o,

    output logic [31:0] operand_a_o,
    output logic [31:0] operand_b_o,
    output logic [31:0] alu_result_o,

    output logic        branch_taken_o,
    output logic        redirect_valid_o,
    output logic [31:0] redirect_pc_o,

    output logic        load_o,
    output logic        store_o,
    output logic [1:0]  mem_size_o,
    output logic        mem_unsigned_o,
    output logic [31:0] mem_addr_o,
    output logic [31:0] store_data_o,

    output logic        csr_valid_o,
    output logic [11:0] csr_addr_o,
    output logic [2:0]  csr_op_o,
    output logic        csr_write_o,
    output logic [31:0] csr_wdata_o,

    output logic [4:0]  rd_addr_o,
    output logic        rd_write_o,
    output logic [2:0]  wb_sel_o,

    output logic        system_ecall_o,
    output logic        system_ebreak_o,
    output logic        system_mret_o,

    output logic        exception_valid_o,
    output logic [31:0] exception_cause_o,
    output logic [31:0] exception_tval_o
);

    localparam logic [1:0] OP_A_RS1  = 2'd0;
    localparam logic [1:0] OP_A_PC   = 2'd1;
    localparam logic [1:0] OP_A_ZERO = 2'd2;

    localparam logic [1:0] OP_B_RS2 = 2'd0;
    localparam logic [1:0] OP_B_IMM = 2'd1;

    localparam logic [2:0] BR_EQ   = 3'd1;
    localparam logic [2:0] BR_NE   = 3'd2;
    localparam logic [2:0] BR_LT   = 3'd3;
    localparam logic [2:0] BR_GE   = 3'd4;
    localparam logic [2:0] BR_LTU  = 3'd5;
    localparam logic [2:0] BR_GEU  = 3'd6;

    localparam logic [31:0] EXC_INSTR_ADDR_MISALIGNED = 32'd0;

    logic [31:0] alu_operand_a;
    logic [31:0] alu_operand_b;
    logic [31:0] alu_result;
    logic        branch_condition;
    logic [31:0] branch_target;
    logic [31:0] jump_target_raw;
    logic [31:0] jump_target;
    logic [31:0] selected_target;
    logic        target_misaligned;

    always_comb begin
        unique case (op_a_sel_i)
            OP_A_RS1:  alu_operand_a = rs1_value_i;
            OP_A_PC:   alu_operand_a = pc_i;
            OP_A_ZERO: alu_operand_a = 32'h0000_0000;
            default:   alu_operand_a = 32'h0000_0000;
        endcase
    end

    always_comb begin
        unique case (op_b_sel_i)
            OP_B_RS2: alu_operand_b = rs2_value_i;
            OP_B_IMM: alu_operand_b = imm_i;
            default:  alu_operand_b = 32'h0000_0000;
        endcase
    end

    cpu_alu u_alu (
        .operand_a_i (alu_operand_a),
        .operand_b_i (alu_operand_b),
        .alu_op_i    (alu_op_i),
        .result_o    (alu_result)
    );

    always_comb begin
        unique case (branch_op_i)
            BR_EQ:   branch_condition = (rs1_value_i == rs2_value_i);
            BR_NE:   branch_condition = (rs1_value_i != rs2_value_i);
            BR_LT:   branch_condition = ($signed(rs1_value_i) <
                                         $signed(rs2_value_i));
            BR_GE:   branch_condition = ($signed(rs1_value_i) >=
                                         $signed(rs2_value_i));
            BR_LTU:  branch_condition = (rs1_value_i < rs2_value_i);
            BR_GEU:  branch_condition = (rs1_value_i >= rs2_value_i);
            default: branch_condition = 1'b0;
        endcase
    end

    assign branch_target = pc_i + imm_i;
    assign jump_target_raw = jump_indirect_i ? (rs1_value_i + imm_i) :
                                               (pc_i + imm_i);
    assign jump_target = jump_indirect_i ? {jump_target_raw[31:1], 1'b0} :
                                           jump_target_raw;
    assign branch_taken_o = execute_valid_i && branch_i && branch_condition;
    assign selected_target = jump_i ? jump_target : branch_target;
    assign target_misaligned = execute_valid_i &&
                               !exception_valid_i &&
                               (jump_i || branch_taken_o) &&
                               (selected_target[1:0] != 2'b00);

    assign execute_valid_o = execute_valid_i;
    assign pc_o = pc_i;
    assign instr_o = instr_i;
    assign pc_plus4_o = pc_i + 32'd4;
    assign operand_a_o = alu_operand_a;
    assign operand_b_o = alu_operand_b;
    assign alu_result_o = alu_result;

    assign redirect_valid_o = execute_valid_i &&
                              !exception_valid_i &&
                              !target_misaligned &&
                              (jump_i || branch_taken_o);
    assign redirect_pc_o = selected_target;

    assign load_o = execute_valid_i && !exception_valid_o && load_i;
    assign store_o = execute_valid_i && !exception_valid_o && store_i;
    assign mem_size_o = mem_size_i;
    assign mem_unsigned_o = mem_unsigned_i;
    assign mem_addr_o = alu_result;
    assign store_data_o = rs2_value_i;

    assign csr_valid_o = execute_valid_i && !exception_valid_o && csr_valid_i;
    assign csr_addr_o = csr_addr_i;
    assign csr_op_o = csr_op_i;
    assign csr_write_o = execute_valid_i && !exception_valid_o && csr_write_i;
    assign csr_wdata_o = csr_imm_i ? imm_i : rs1_value_i;

    assign rd_addr_o = rd_addr_i;
    assign rd_write_o = execute_valid_i && !exception_valid_o && rd_write_i;
    assign wb_sel_o = wb_sel_i;

    assign system_ecall_o = execute_valid_i && system_ecall_i;
    assign system_ebreak_o = execute_valid_i && system_ebreak_i;
    assign system_mret_o = execute_valid_i && !exception_valid_o &&
                           system_mret_i;

    always_comb begin
        exception_valid_o = exception_valid_i;
        exception_cause_o = exception_cause_i;
        exception_tval_o = exception_tval_i;

        if (target_misaligned) begin
            exception_valid_o = 1'b1;
            exception_cause_o = EXC_INSTR_ADDR_MISALIGNED;
            exception_tval_o = selected_target;
        end
    end

endmodule
