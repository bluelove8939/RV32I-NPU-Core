`timescale 1ns/1ps

module cpu_alu (
    input  logic [31:0] operand_a_i,
    input  logic [31:0] operand_b_i,
    input  logic [3:0]  alu_op_i,
    output logic [31:0] result_o
);

    localparam logic [3:0] ALU_ADD    = 4'd0;
    localparam logic [3:0] ALU_SUB    = 4'd1;
    localparam logic [3:0] ALU_SLL    = 4'd2;
    localparam logic [3:0] ALU_SLT    = 4'd3;
    localparam logic [3:0] ALU_SLTU   = 4'd4;
    localparam logic [3:0] ALU_XOR    = 4'd5;
    localparam logic [3:0] ALU_SRL    = 4'd6;
    localparam logic [3:0] ALU_SRA    = 4'd7;
    localparam logic [3:0] ALU_OR     = 4'd8;
    localparam logic [3:0] ALU_AND    = 4'd9;
    localparam logic [3:0] ALU_COPY_B = 4'd10;

    always_comb begin
        unique case (alu_op_i)
            ALU_ADD:    result_o = operand_a_i + operand_b_i;
            ALU_SUB:    result_o = operand_a_i - operand_b_i;
            ALU_SLL:    result_o = operand_a_i << operand_b_i[4:0];
            ALU_SLT:    result_o = ($signed(operand_a_i) <
                                    $signed(operand_b_i)) ? 32'd1 : 32'd0;
            ALU_SLTU:   result_o = (operand_a_i < operand_b_i) ? 32'd1 : 32'd0;
            ALU_XOR:    result_o = operand_a_i ^ operand_b_i;
            ALU_SRL:    result_o = operand_a_i >> operand_b_i[4:0];
            ALU_SRA:    result_o = $signed(operand_a_i) >>> operand_b_i[4:0];
            ALU_OR:     result_o = operand_a_i | operand_b_i;
            ALU_AND:    result_o = operand_a_i & operand_b_i;
            ALU_COPY_B: result_o = operand_b_i;
            default:    result_o = 32'h0000_0000;
        endcase
    end

endmodule
