`timescale 1ns/1ps

module tb_cpu_alu;

    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic [3:0]  alu_op;
    logic [31:0] result;

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

    cpu_alu u_alu (
        .operand_a_i (operand_a),
        .operand_b_i (operand_b),
        .alu_op_i    (alu_op),
        .result_o    (result)
    );

    task automatic expect_eq32(
        input string name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=0x%08x expected=0x%08x",
                   name, actual, expected);
        end
    endtask

    task automatic check_alu(
        input string name,
        input logic [3:0] op,
        input logic [31:0] a,
        input logic [31:0] b,
        input logic [31:0] expected
    );
        operand_a = a;
        operand_b = b;
        alu_op = op;
        #1;
        $display("[ALU] %s a=0x%08x b=0x%08x result=0x%08x",
                 name, a, b, result);
        expect_eq32(name, result, expected);
    endtask

    initial begin
        check_alu("add", ALU_ADD, 32'h0000_0007, 32'h0000_0005,
                  32'h0000_000c);
        check_alu("sub", ALU_SUB, 32'h0000_0007, 32'h0000_0005,
                  32'h0000_0002);
        check_alu("sll", ALU_SLL, 32'h0000_0001, 32'h0000_0004,
                  32'h0000_0010);
        check_alu("slt true", ALU_SLT, 32'hffff_ffff, 32'h0000_0001,
                  32'h0000_0001);
        check_alu("slt false", ALU_SLT, 32'h0000_0001, 32'hffff_ffff,
                  32'h0000_0000);
        check_alu("sltu true", ALU_SLTU, 32'h0000_0001, 32'hffff_ffff,
                  32'h0000_0001);
        check_alu("xor", ALU_XOR, 32'hff00_ff00, 32'h0f0f_0f0f,
                  32'hf00f_f00f);
        check_alu("srl", ALU_SRL, 32'h8000_0000, 32'h0000_0004,
                  32'h0800_0000);
        check_alu("sra", ALU_SRA, 32'h8000_0000, 32'h0000_0004,
                  32'hf800_0000);
        check_alu("or", ALU_OR, 32'hff00_0000, 32'h0000_00ff,
                  32'hff00_00ff);
        check_alu("and", ALU_AND, 32'hff00_00ff, 32'h0f0f_0f0f,
                  32'h0f00_000f);
        check_alu("copy b", ALU_COPY_B, 32'h1234_5678, 32'hdead_beef,
                  32'hdead_beef);
        check_alu("default", 4'hf, 32'h1234_5678, 32'hdead_beef,
                  32'h0000_0000);

        $display("[PASS] CPU ALU tests complete");
        $finish;
    end

endmodule
