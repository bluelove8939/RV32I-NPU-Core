`timescale 1ns/1ps

module tb_cpu_i_decoder;

    logic        instr_valid;
    logic [31:0] instr_pc;
    logic [31:0] instr;
    logic        instr_exception_valid;
    logic [31:0] instr_exception_cause;
    logic [31:0] instr_exception_tval;

    logic        decode_valid;
    logic [31:0] decode_pc;
    logic [31:0] decode_instr;
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [4:0]  rd_addr;
    logic        rs1_used;
    logic        rs2_used;
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

    localparam logic [3:0] ALU_ADD  = 4'd0;
    localparam logic [3:0] ALU_SUB  = 4'd1;
    localparam logic [3:0] ALU_SLL  = 4'd2;
    localparam logic [3:0] ALU_SLT  = 4'd3;
    localparam logic [3:0] ALU_SLTU = 4'd4;
    localparam logic [3:0] ALU_XOR  = 4'd5;
    localparam logic [3:0] ALU_SRL  = 4'd6;
    localparam logic [3:0] ALU_SRA  = 4'd7;
    localparam logic [3:0] ALU_OR   = 4'd8;
    localparam logic [3:0] ALU_AND  = 4'd9;
    localparam logic [3:0] ALU_COPY_B = 4'd10;

    localparam logic [1:0] OP_A_RS1  = 2'd0;
    localparam logic [1:0] OP_A_PC   = 2'd1;
    localparam logic [1:0] OP_A_ZERO = 2'd2;
    localparam logic [1:0] OP_B_RS2  = 2'd0;
    localparam logic [1:0] OP_B_IMM  = 2'd1;

    localparam logic [2:0] BR_NONE = 3'd0;
    localparam logic [2:0] BR_EQ   = 3'd1;
    localparam logic [2:0] BR_NE   = 3'd2;
    localparam logic [2:0] BR_LT   = 3'd3;
    localparam logic [2:0] BR_GEU  = 3'd6;

    localparam logic [1:0] MEM_BYTE = 2'd0;
    localparam logic [1:0] MEM_HALF = 2'd1;
    localparam logic [1:0] MEM_WORD = 2'd2;

    localparam logic [2:0] CSR_OP_READ  = 3'd0;
    localparam logic [2:0] CSR_OP_WRITE = 3'd1;
    localparam logic [2:0] CSR_OP_SET   = 3'd2;
    localparam logic [2:0] CSR_OP_CLEAR = 3'd3;

    localparam logic [2:0] WB_ALU  = 3'd0;
    localparam logic [2:0] WB_LOAD = 3'd1;
    localparam logic [2:0] WB_CSR  = 3'd2;
    localparam logic [2:0] WB_PC4  = 3'd3;

    localparam logic [31:0] EXC_FETCH_FAULT = 32'd1;
    localparam logic [31:0] EXC_ILLEGAL = 32'd2;
    localparam logic [31:0] EXC_BREAKPOINT = 32'd3;
    localparam logic [31:0] EXC_ECALL_MMODE = 32'd11;

    cpu_i_decoder u_decoder (
        .instr_valid_i            (instr_valid),
        .instr_pc_i               (instr_pc),
        .instr_i                  (instr),
        .instr_exception_valid_i  (instr_exception_valid),
        .instr_exception_cause_i  (instr_exception_cause),
        .instr_exception_tval_i   (instr_exception_tval),
        .decode_valid_o           (decode_valid),
        .decode_pc_o              (decode_pc),
        .decode_instr_o           (decode_instr),
        .rs1_addr_o               (rs1_addr),
        .rs2_addr_o               (rs2_addr),
        .rd_addr_o                (rd_addr),
        .rs1_used_o               (rs1_used),
        .rs2_used_o               (rs2_used),
        .rd_write_o               (rd_write),
        .imm_o                    (imm),
        .alu_op_o                 (alu_op),
        .op_a_sel_o               (op_a_sel),
        .op_b_sel_o               (op_b_sel),
        .branch_o                 (branch),
        .branch_op_o              (branch_op),
        .jump_o                   (jump),
        .jump_indirect_o          (jump_indirect),
        .load_o                   (load),
        .store_o                  (store),
        .mem_size_o               (mem_size),
        .mem_unsigned_o           (mem_unsigned),
        .csr_valid_o              (csr_valid),
        .csr_addr_o               (csr_addr),
        .csr_op_o                 (csr_op),
        .csr_write_o              (csr_write),
        .csr_imm_o                (csr_imm),
        .system_ecall_o           (system_ecall),
        .system_ebreak_o          (system_ebreak),
        .system_mret_o            (system_mret),
        .wb_sel_o                 (wb_sel),
        .exception_valid_o        (exception_valid),
        .exception_cause_o        (exception_cause),
        .exception_tval_o         (exception_tval)
    );

    function automatic logic [31:0] enc_r(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        return {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_i(
        input logic [11:0] imm12,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm12, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_s(
        input logic [11:0] imm12,
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3
    );
        return {imm12[11:5], rs2, rs1, funct3, imm12[4:0], 7'b0100011};
    endfunction

    function automatic logic [31:0] enc_b(
        input logic [12:0] imm13,
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3
    );
        begin
            if (imm13[0] != 1'b0) begin
                $fatal(1, "[FAIL] branch immediate bit 0 must be zero");
            end
            return {imm13[12], imm13[10:5], rs2, rs1, funct3,
                    imm13[4:1], imm13[11], 7'b1100011};
        end
    endfunction

    function automatic logic [31:0] enc_u(
        input logic [31:12] imm20,
        input logic [4:0]   rd,
        input logic [6:0]   opcode
    );
        return {imm20, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_j(
        input logic [20:0] imm21,
        input logic [4:0]  rd
    );
        begin
            if (imm21[0] != 1'b0) begin
                $fatal(1, "[FAIL] jump immediate bit 0 must be zero");
            end
            return {imm21[20], imm21[10:1], imm21[11],
                    imm21[19:12], rd, 7'b1101111};
        end
    endfunction

    task automatic drive_instr(input logic [31:0] insn);
        instr_valid = 1'b1;
        instr_pc = 32'h0000_1000;
        instr = insn;
        instr_exception_valid = 1'b0;
        instr_exception_cause = 32'h0000_0000;
        instr_exception_tval = 32'h0000_0000;
        #1;
        $display("[DECODE] pc=0x%08x instr=0x%08x rs1=%0d rs2=%0d rd=%0d imm=0x%08x alu=%0d br=%0d j=%0d ld=%0d st=%0d csr=%0d exc=%0d cause=0x%08x",
                 decode_pc, decode_instr, rs1_addr, rs2_addr, rd_addr, imm,
                 alu_op, branch, jump, load, store, csr_valid,
                 exception_valid, exception_cause);
    endtask

    task automatic expect_eq1(
        input string name,
        input logic actual,
        input logic expected
    );
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=%0b expected=%0b",
                   name, actual, expected);
        end
    endtask

    task automatic expect_eq2(
        input string name,
        input logic [1:0] actual,
        input logic [1:0] expected
    );
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=0x%0x expected=0x%0x",
                   name, actual, expected);
        end
    endtask

    task automatic expect_eq3(
        input string name,
        input logic [2:0] actual,
        input logic [2:0] expected
    );
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=0x%0x expected=0x%0x",
                   name, actual, expected);
        end
    endtask

    task automatic expect_eq4(
        input string name,
        input logic [3:0] actual,
        input logic [3:0] expected
    );
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=0x%0x expected=0x%0x",
                   name, actual, expected);
        end
    endtask

    task automatic expect_eq5(
        input string name,
        input logic [4:0] actual,
        input logic [4:0] expected
    );
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=0x%0x expected=0x%0x",
                   name, actual, expected);
        end
    endtask

    task automatic expect_eq12(
        input string name,
        input logic [11:0] actual,
        input logic [11:0] expected
    );
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=0x%03x expected=0x%03x",
                   name, actual, expected);
        end
    endtask

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

    task automatic check_common_no_exception();
        expect_eq1("decode valid", decode_valid, 1'b1);
        expect_eq32("decode pc", decode_pc, 32'h0000_1000);
        expect_eq1("exception valid", exception_valid, 1'b0);
        expect_eq32("exception cause", exception_cause, 32'h0000_0000);
        expect_eq32("exception tval", exception_tval, 32'h0000_0000);
    endtask

    task automatic run_rv32i_decode_test();
        $display("[TEST] RV32I decode");

        drive_instr(enc_r(7'b0000000, 5'd3, 5'd2, 3'b000, 5'd1, 7'b0110011));
        check_common_no_exception();
        expect_eq1("add rs1 used", rs1_used, 1'b1);
        expect_eq1("add rs2 used", rs2_used, 1'b1);
        expect_eq1("add rd write", rd_write, 1'b1);
        expect_eq5("add rs1", rs1_addr, 5'd2);
        expect_eq5("add rs2", rs2_addr, 5'd3);
        expect_eq5("add rd", rd_addr, 5'd1);
        expect_eq4("add alu", alu_op, ALU_ADD);
        expect_eq2("add op a", op_a_sel, OP_A_RS1);
        expect_eq2("add op b", op_b_sel, OP_B_RS2);
        expect_eq3("add wb", wb_sel, WB_ALU);

        drive_instr(enc_r(7'b0100000, 5'd6, 5'd5, 3'b101, 5'd4, 7'b0110011));
        check_common_no_exception();
        expect_eq4("sra alu", alu_op, ALU_SRA);

        drive_instr(enc_i(12'hff8, 5'd8, 3'b000, 5'd7, 7'b0010011));
        check_common_no_exception();
        expect_eq1("addi rs1 used", rs1_used, 1'b1);
        expect_eq1("addi rs2 unused", rs2_used, 1'b0);
        expect_eq32("addi imm", imm, 32'hffff_fff8);
        expect_eq4("addi alu", alu_op, ALU_ADD);
        expect_eq2("addi op b", op_b_sel, OP_B_IMM);

        drive_instr(enc_i({7'b0000000, 5'd4}, 5'd10, 3'b001, 5'd9, 7'b0010011));
        check_common_no_exception();
        expect_eq4("slli alu", alu_op, ALU_SLL);

        drive_instr(enc_i({7'b0100000, 5'd7}, 5'd12, 3'b101, 5'd11, 7'b0010011));
        check_common_no_exception();
        expect_eq4("srai alu", alu_op, ALU_SRA);

        drive_instr(enc_u(20'h12345, 5'd13, 7'b0110111));
        check_common_no_exception();
        expect_eq5("lui rd", rd_addr, 5'd13);
        expect_eq32("lui imm", imm, 32'h1234_5000);
        expect_eq4("lui alu", alu_op, ALU_COPY_B);
        expect_eq2("lui op a", op_a_sel, OP_A_ZERO);

        drive_instr(enc_u(20'h20000, 5'd14, 7'b0010111));
        check_common_no_exception();
        expect_eq4("auipc alu", alu_op, ALU_ADD);
        expect_eq2("auipc op a", op_a_sel, OP_A_PC);

        drive_instr(enc_b(13'h1ffc, 5'd2, 5'd1, 3'b000));
        check_common_no_exception();
        expect_eq1("beq branch", branch, 1'b1);
        expect_eq3("beq op", branch_op, BR_EQ);
        expect_eq32("beq imm", imm, 32'hffff_fffc);

        drive_instr(enc_b(13'h0040, 5'd4, 5'd3, 3'b111));
        check_common_no_exception();
        expect_eq3("bgeu op", branch_op, BR_GEU);

        drive_instr(enc_j(21'h00080, 5'd15));
        check_common_no_exception();
        expect_eq1("jal jump", jump, 1'b1);
        expect_eq1("jal indirect", jump_indirect, 1'b0);
        expect_eq3("jal wb", wb_sel, WB_PC4);
        expect_eq32("jal imm", imm, 32'h0000_0080);

        drive_instr(enc_i(12'h010, 5'd16, 3'b000, 5'd17, 7'b1100111));
        check_common_no_exception();
        expect_eq1("jalr jump", jump, 1'b1);
        expect_eq1("jalr indirect", jump_indirect, 1'b1);
        expect_eq1("jalr rs1 used", rs1_used, 1'b1);

        drive_instr(enc_i(12'h004, 5'd19, 3'b101, 5'd18, 7'b0000011));
        check_common_no_exception();
        expect_eq1("lhu load", load, 1'b1);
        expect_eq2("lhu size", mem_size, MEM_HALF);
        expect_eq1("lhu unsigned", mem_unsigned, 1'b1);
        expect_eq3("lhu wb", wb_sel, WB_LOAD);

        drive_instr(enc_s(12'hffc, 5'd21, 5'd20, 3'b010));
        check_common_no_exception();
        expect_eq1("sw store", store, 1'b1);
        expect_eq1("sw rs2 used", rs2_used, 1'b1);
        expect_eq2("sw size", mem_size, MEM_WORD);
        expect_eq32("sw imm", imm, 32'hffff_fffc);
        expect_eq1("sw rd write", rd_write, 1'b0);

        $display("[PASS] RV32I decode");
    endtask

    task automatic run_csr_system_decode_test();
        $display("[TEST] CSR/system decode");

        drive_instr(enc_i(12'h305, 5'd6, 3'b001, 5'd5, 7'b1110011));
        check_common_no_exception();
        expect_eq1("csrrw valid", csr_valid, 1'b1);
        expect_eq12("csrrw addr", csr_addr, 12'h305);
        expect_eq3("csrrw op", csr_op, CSR_OP_WRITE);
        expect_eq1("csrrw write", csr_write, 1'b1);
        expect_eq1("csrrw imm flag", csr_imm, 1'b0);
        expect_eq1("csrrw rs1 used", rs1_used, 1'b1);
        expect_eq3("csrrw wb", wb_sel, WB_CSR);

        drive_instr(enc_i(12'h300, 5'd0, 3'b010, 5'd7, 7'b1110011));
        check_common_no_exception();
        expect_eq3("csrrs op", csr_op, CSR_OP_SET);
        expect_eq1("csrrs x0 no write", csr_write, 1'b0);

        drive_instr(enc_i(12'h342, 5'd9, 3'b111, 5'd8, 7'b1110011));
        check_common_no_exception();
        expect_eq1("csrrci valid", csr_valid, 1'b1);
        expect_eq3("csrrci op", csr_op, CSR_OP_CLEAR);
        expect_eq1("csrrci write", csr_write, 1'b1);
        expect_eq1("csrrci imm flag", csr_imm, 1'b1);
        expect_eq32("csrrci imm", imm, 32'h0000_0009);

        drive_instr(32'h0000_0073);
        expect_eq1("ecall flag", system_ecall, 1'b1);
        expect_eq1("ecall exception", exception_valid, 1'b1);
        expect_eq32("ecall cause", exception_cause, EXC_ECALL_MMODE);

        drive_instr(32'h0010_0073);
        expect_eq1("ebreak flag", system_ebreak, 1'b1);
        expect_eq1("ebreak exception", exception_valid, 1'b1);
        expect_eq32("ebreak cause", exception_cause, EXC_BREAKPOINT);

        drive_instr(32'h3020_0073);
        check_common_no_exception();
        expect_eq1("mret flag", system_mret, 1'b1);

        $display("[PASS] CSR/system decode");
    endtask

    task automatic run_exception_decode_test();
        $display("[TEST] exception decode");

        drive_instr(32'h0000_0000);
        expect_eq1("illegal exception", exception_valid, 1'b1);
        expect_eq32("illegal cause", exception_cause, EXC_ILLEGAL);
        expect_eq32("illegal tval", exception_tval, 32'h0000_0000);
        expect_eq1("illegal rd write cleared", rd_write, 1'b0);

        drive_instr(enc_i({7'b1111111, 5'd1}, 5'd2, 3'b101, 5'd3, 7'b0010011));
        expect_eq1("bad shift exception", exception_valid, 1'b1);
        expect_eq32("bad shift cause", exception_cause, EXC_ILLEGAL);

        instr_valid = 1'b1;
        instr_pc = 32'h0000_2000;
        instr = enc_i(12'h001, 5'd2, 3'b000, 5'd1, 7'b0010011);
        instr_exception_valid = 1'b1;
        instr_exception_cause = EXC_FETCH_FAULT;
        instr_exception_tval = 32'h0000_2000;
        #1;
        expect_eq1("fetch exception propagated", exception_valid, 1'b1);
        expect_eq32("fetch exception cause", exception_cause, EXC_FETCH_FAULT);
        expect_eq32("fetch exception tval", exception_tval, 32'h0000_2000);
        expect_eq1("fetch exception suppresses rd write", rd_write, 1'b0);

        instr_valid = 1'b0;
        instr_exception_valid = 1'b0;
        #1;
        expect_eq1("invalid decode valid", decode_valid, 1'b0);

        $display("[PASS] exception decode");
    endtask

    initial begin
        instr_valid = 1'b0;
        instr_pc = 32'h0000_0000;
        instr = 32'h0000_0000;
        instr_exception_valid = 1'b0;
        instr_exception_cause = 32'h0000_0000;
        instr_exception_tval = 32'h0000_0000;
        #1;

        run_rv32i_decode_test();
        run_csr_system_decode_test();
        run_exception_decode_test();
        expect_eq3("branch none observed", BR_NONE, 3'd0);
        expect_eq3("branch ne observed", BR_NE, 3'd2);
        expect_eq3("branch lt observed", BR_LT, 3'd3);
        expect_eq2("mem byte observed", MEM_BYTE, 2'd0);
        expect_eq3("csr read observed", CSR_OP_READ, 3'd0);
        expect_eq4("sub observed", ALU_SUB, 4'd1);
        expect_eq4("slt observed", ALU_SLT, 4'd3);
        expect_eq4("sltu observed", ALU_SLTU, 4'd4);
        expect_eq4("xor observed", ALU_XOR, 4'd5);
        expect_eq4("srl observed", ALU_SRL, 4'd6);
        expect_eq4("or observed", ALU_OR, 4'd8);
        expect_eq4("and observed", ALU_AND, 4'd9);
        $display("[PASS] CPU instruction decoder tests complete");
        $finish;
    end

endmodule
