`timescale 1ns/1ps

module tb_cpu_execute;

    logic        execute_valid;
    logic [31:0] pc;
    logic [31:0] instr;
    logic [31:0] rs1_value;
    logic [31:0] rs2_value;
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
    logic [4:0]  rd_addr;
    logic        rd_write;
    logic [2:0]  wb_sel;
    logic        system_ecall;
    logic        system_ebreak;
    logic        system_mret;
    logic        exception_valid_in;
    logic [31:0] exception_cause_in;
    logic [31:0] exception_tval_in;

    logic        execute_valid_out;
    logic [31:0] pc_out;
    logic [31:0] instr_out;
    logic [31:0] pc_plus4;
    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic [31:0] alu_result;
    logic        branch_taken;
    logic        redirect_valid;
    logic [31:0] redirect_pc;
    logic        load_out;
    logic        store_out;
    logic [1:0]  mem_size_out;
    logic        mem_unsigned_out;
    logic [31:0] mem_addr;
    logic [31:0] store_data;
    logic        csr_valid_out;
    logic [11:0] csr_addr_out;
    logic [2:0]  csr_op_out;
    logic        csr_write_out;
    logic [31:0] csr_wdata;
    logic [4:0]  rd_addr_out;
    logic        rd_write_out;
    logic [2:0]  wb_sel_out;
    logic        system_ecall_out;
    logic        system_ebreak_out;
    logic        system_mret_out;
    logic        exception_valid;
    logic [31:0] exception_cause;
    logic [31:0] exception_tval;

    localparam logic [3:0] ALU_ADD = 4'd0;
    localparam logic [3:0] ALU_SUB = 4'd1;
    localparam logic [3:0] ALU_COPY_B = 4'd10;

    localparam logic [1:0] OP_A_RS1  = 2'd0;
    localparam logic [1:0] OP_A_PC   = 2'd1;
    localparam logic [1:0] OP_A_ZERO = 2'd2;
    localparam logic [1:0] OP_B_RS2  = 2'd0;
    localparam logic [1:0] OP_B_IMM  = 2'd1;

    localparam logic [2:0] BR_EQ  = 3'd1;
    localparam logic [2:0] BR_NE  = 3'd2;
    localparam logic [2:0] BR_LT  = 3'd3;
    localparam logic [2:0] BR_GEU = 3'd6;

    localparam logic [1:0] MEM_HALF = 2'd1;
    localparam logic [1:0] MEM_WORD = 2'd2;

    localparam logic [2:0] CSR_OP_SET = 3'd2;
    localparam logic [2:0] CSR_OP_CLEAR = 3'd3;

    localparam logic [2:0] WB_ALU = 3'd0;
    localparam logic [2:0] WB_LOAD = 3'd1;
    localparam logic [2:0] WB_CSR = 3'd2;

    localparam logic [31:0] EXC_INSTR_ADDR_MISALIGNED = 32'd0;
    localparam logic [31:0] EXC_ILLEGAL = 32'd2;

    cpu_execute u_execute (
        .execute_valid_i    (execute_valid),
        .pc_i               (pc),
        .instr_i            (instr),
        .rs1_value_i        (rs1_value),
        .rs2_value_i        (rs2_value),
        .imm_i              (imm),
        .alu_op_i           (alu_op),
        .op_a_sel_i         (op_a_sel),
        .op_b_sel_i         (op_b_sel),
        .branch_i           (branch),
        .branch_op_i        (branch_op),
        .jump_i             (jump),
        .jump_indirect_i    (jump_indirect),
        .load_i             (load),
        .store_i            (store),
        .mem_size_i         (mem_size),
        .mem_unsigned_i     (mem_unsigned),
        .csr_valid_i        (csr_valid),
        .csr_addr_i         (csr_addr),
        .csr_op_i           (csr_op),
        .csr_write_i        (csr_write),
        .csr_imm_i          (csr_imm),
        .rd_addr_i          (rd_addr),
        .rd_write_i         (rd_write),
        .wb_sel_i           (wb_sel),
        .system_ecall_i     (system_ecall),
        .system_ebreak_i    (system_ebreak),
        .system_mret_i      (system_mret),
        .exception_valid_i  (exception_valid_in),
        .exception_cause_i  (exception_cause_in),
        .exception_tval_i   (exception_tval_in),
        .execute_valid_o    (execute_valid_out),
        .pc_o               (pc_out),
        .instr_o            (instr_out),
        .pc_plus4_o         (pc_plus4),
        .operand_a_o        (operand_a),
        .operand_b_o        (operand_b),
        .alu_result_o       (alu_result),
        .branch_taken_o     (branch_taken),
        .redirect_valid_o   (redirect_valid),
        .redirect_pc_o      (redirect_pc),
        .load_o             (load_out),
        .store_o            (store_out),
        .mem_size_o         (mem_size_out),
        .mem_unsigned_o     (mem_unsigned_out),
        .mem_addr_o         (mem_addr),
        .store_data_o       (store_data),
        .csr_valid_o        (csr_valid_out),
        .csr_addr_o         (csr_addr_out),
        .csr_op_o           (csr_op_out),
        .csr_write_o        (csr_write_out),
        .csr_wdata_o        (csr_wdata),
        .rd_addr_o          (rd_addr_out),
        .rd_write_o         (rd_write_out),
        .wb_sel_o           (wb_sel_out),
        .system_ecall_o     (system_ecall_out),
        .system_ebreak_o    (system_ebreak_out),
        .system_mret_o      (system_mret_out),
        .exception_valid_o  (exception_valid),
        .exception_cause_o  (exception_cause),
        .exception_tval_o   (exception_tval)
    );

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

    task automatic drive_defaults();
        execute_valid = 1'b1;
        pc = 32'h0000_1000;
        instr = 32'h0000_0013;
        rs1_value = 32'h0000_0100;
        rs2_value = 32'h0000_0004;
        imm = 32'h0000_0020;
        alu_op = ALU_ADD;
        op_a_sel = OP_A_RS1;
        op_b_sel = OP_B_IMM;
        branch = 1'b0;
        branch_op = BR_EQ;
        jump = 1'b0;
        jump_indirect = 1'b0;
        load = 1'b0;
        store = 1'b0;
        mem_size = MEM_WORD;
        mem_unsigned = 1'b0;
        csr_valid = 1'b0;
        csr_addr = 12'h000;
        csr_op = CSR_OP_SET;
        csr_write = 1'b0;
        csr_imm = 1'b0;
        rd_addr = 5'd1;
        rd_write = 1'b1;
        wb_sel = WB_ALU;
        system_ecall = 1'b0;
        system_ebreak = 1'b0;
        system_mret = 1'b0;
        exception_valid_in = 1'b0;
        exception_cause_in = 32'h0000_0000;
        exception_tval_in = 32'h0000_0000;
        #1;
    endtask

    task automatic print_state(input string name);
        $display("[EX] %s pc=0x%08x alu=0x%08x br_taken=%0b redir=%0b redir_pc=0x%08x mem=0x%08x exc=%0b cause=0x%08x",
                 name, pc_out, alu_result, branch_taken, redirect_valid,
                 redirect_pc, mem_addr, exception_valid, exception_cause);
    endtask

    task automatic run_alu_operand_test();
        $display("[TEST] execute ALU operand select");

        drive_defaults();
        print_state("addi-like");
        expect_eq1("valid", execute_valid_out, 1'b1);
        expect_eq32("pc", pc_out, 32'h0000_1000);
        expect_eq32("instr", instr_out, 32'h0000_0013);
        expect_eq32("pc plus4", pc_plus4, 32'h0000_1004);
        expect_eq32("operand a rs1", operand_a, 32'h0000_0100);
        expect_eq32("operand b imm", operand_b, 32'h0000_0020);
        expect_eq32("alu add", alu_result, 32'h0000_0120);
        expect_eq1("rd write", rd_write_out, 1'b1);
        expect_eq5("rd addr", rd_addr_out, 5'd1);
        expect_eq3("wb sel", wb_sel_out, WB_ALU);

        drive_defaults();
        op_a_sel = OP_A_PC;
        op_b_sel = OP_B_IMM;
        imm = 32'h0000_4000;
        #1;
        print_state("auipc-like");
        expect_eq32("op a pc", operand_a, 32'h0000_1000);
        expect_eq32("auipc alu", alu_result, 32'h0000_5000);

        drive_defaults();
        op_a_sel = OP_A_ZERO;
        alu_op = ALU_COPY_B;
        imm = 32'h1234_5000;
        #1;
        print_state("lui-like");
        expect_eq32("op a zero", operand_a, 32'h0000_0000);
        expect_eq32("lui alu", alu_result, 32'h1234_5000);

        drive_defaults();
        op_b_sel = OP_B_RS2;
        alu_op = ALU_SUB;
        rs1_value = 32'h0000_0010;
        rs2_value = 32'h0000_0007;
        #1;
        print_state("sub-like");
        expect_eq32("op b rs2", operand_b, 32'h0000_0007);
        expect_eq32("sub alu", alu_result, 32'h0000_0009);

        $display("[PASS] execute ALU operand select");
    endtask

    task automatic run_branch_jump_test();
        $display("[TEST] execute branch/jump");

        drive_defaults();
        branch = 1'b1;
        branch_op = BR_EQ;
        rs1_value = 32'h0000_aaaa;
        rs2_value = 32'h0000_aaaa;
        imm = 32'h0000_0040;
        #1;
        print_state("beq taken");
        expect_eq1("beq taken", branch_taken, 1'b1);
        expect_eq1("beq redirect", redirect_valid, 1'b1);
        expect_eq32("beq target", redirect_pc, 32'h0000_1040);

        drive_defaults();
        branch = 1'b1;
        branch_op = BR_NE;
        rs1_value = 32'h0000_aaaa;
        rs2_value = 32'h0000_aaaa;
        imm = 32'h0000_0040;
        #1;
        print_state("bne not taken");
        expect_eq1("bne not taken", branch_taken, 1'b0);
        expect_eq1("bne no redirect", redirect_valid, 1'b0);

        drive_defaults();
        branch = 1'b1;
        branch_op = BR_LT;
        rs1_value = 32'hffff_ffff;
        rs2_value = 32'h0000_0001;
        imm = 32'hffff_fffc;
        #1;
        print_state("blt taken");
        expect_eq1("blt taken", branch_taken, 1'b1);
        expect_eq32("blt target", redirect_pc, 32'h0000_0ffc);

        drive_defaults();
        branch = 1'b1;
        branch_op = BR_GEU;
        rs1_value = 32'hffff_ffff;
        rs2_value = 32'h0000_0001;
        imm = 32'h0000_0008;
        #1;
        print_state("bgeu taken");
        expect_eq1("bgeu taken", branch_taken, 1'b1);

        drive_defaults();
        jump = 1'b1;
        jump_indirect = 1'b0;
        imm = 32'h0000_0080;
        #1;
        print_state("jal");
        expect_eq1("jal redirect", redirect_valid, 1'b1);
        expect_eq32("jal target", redirect_pc, 32'h0000_1080);

        drive_defaults();
        jump = 1'b1;
        jump_indirect = 1'b1;
        rs1_value = 32'h0000_2004;
        imm = 32'h0000_0004;
        #1;
        print_state("jalr aligned");
        expect_eq1("jalr redirect", redirect_valid, 1'b1);
        expect_eq32("jalr target", redirect_pc, 32'h0000_2008);

        drive_defaults();
        jump = 1'b1;
        jump_indirect = 1'b1;
        rs1_value = 32'h0000_2001;
        imm = 32'h0000_0003;
        #1;
        print_state("jalr aligned after clear");
        expect_eq1("jalr aligned redirect", redirect_valid, 1'b1);
        expect_eq32("jalr aligned target", redirect_pc, 32'h0000_2004);

        drive_defaults();
        jump = 1'b1;
        jump_indirect = 1'b1;
        rs1_value = 32'h0000_2002;
        imm = 32'h0000_0000;
        #1;
        print_state("jalr misaligned");
        expect_eq1("jalr misaligned redirect suppressed", redirect_valid, 1'b0);
        expect_eq1("jalr misaligned exception", exception_valid, 1'b1);
        expect_eq32("jalr misaligned cause", exception_cause,
                    EXC_INSTR_ADDR_MISALIGNED);
        expect_eq32("jalr misaligned tval", exception_tval, 32'h0000_2002);
        expect_eq1("jalr misaligned rd write suppressed", rd_write_out, 1'b0);

        $display("[PASS] execute branch/jump");
    endtask

    task automatic run_mem_csr_exception_test();
        $display("[TEST] execute memory/CSR/exception pass-through");

        drive_defaults();
        load = 1'b1;
        mem_size = MEM_HALF;
        mem_unsigned = 1'b1;
        wb_sel = WB_LOAD;
        rs1_value = 32'h0000_3000;
        imm = 32'h0000_0012;
        #1;
        print_state("load");
        expect_eq1("load out", load_out, 1'b1);
        expect_eq1("store off", store_out, 1'b0);
        expect_eq2("load size", mem_size_out, MEM_HALF);
        expect_eq1("load unsigned", mem_unsigned_out, 1'b1);
        expect_eq32("load addr", mem_addr, 32'h0000_3012);
        expect_eq3("load wb", wb_sel_out, WB_LOAD);

        drive_defaults();
        store = 1'b1;
        mem_size = MEM_WORD;
        rs1_value = 32'h0000_4000;
        rs2_value = 32'hdead_beef;
        imm = 32'hffff_fffc;
        #1;
        print_state("store");
        expect_eq1("store out", store_out, 1'b1);
        expect_eq32("store addr", mem_addr, 32'h0000_3ffc);
        expect_eq32("store data", store_data, 32'hdead_beef);

        drive_defaults();
        csr_valid = 1'b1;
        csr_addr = 12'h305;
        csr_op = CSR_OP_SET;
        csr_write = 1'b1;
        csr_imm = 1'b0;
        rs1_value = 32'h0000_0088;
        wb_sel = WB_CSR;
        #1;
        print_state("csr reg");
        expect_eq1("csr valid", csr_valid_out, 1'b1);
        expect_eq12("csr addr", csr_addr_out, 12'h305);
        expect_eq3("csr op", csr_op_out, CSR_OP_SET);
        expect_eq1("csr write", csr_write_out, 1'b1);
        expect_eq32("csr wdata reg", csr_wdata, 32'h0000_0088);
        expect_eq3("csr wb", wb_sel_out, WB_CSR);

        drive_defaults();
        csr_valid = 1'b1;
        csr_addr = 12'h342;
        csr_op = CSR_OP_CLEAR;
        csr_write = 1'b1;
        csr_imm = 1'b1;
        imm = 32'h0000_0009;
        #1;
        print_state("csr imm");
        expect_eq32("csr wdata imm", csr_wdata, 32'h0000_0009);

        drive_defaults();
        system_ecall = 1'b1;
        system_ebreak = 1'b1;
        system_mret = 1'b1;
        #1;
        print_state("system");
        expect_eq1("ecall pass", system_ecall_out, 1'b1);
        expect_eq1("ebreak pass", system_ebreak_out, 1'b1);
        expect_eq1("mret pass", system_mret_out, 1'b1);

        drive_defaults();
        exception_valid_in = 1'b1;
        exception_cause_in = EXC_ILLEGAL;
        exception_tval_in = 32'hffff_ffff;
        load = 1'b1;
        store = 1'b1;
        csr_valid = 1'b1;
        csr_write = 1'b1;
        system_mret = 1'b1;
        #1;
        print_state("incoming exception");
        expect_eq1("exception propagated", exception_valid, 1'b1);
        expect_eq32("exception cause propagated", exception_cause, EXC_ILLEGAL);
        expect_eq32("exception tval propagated", exception_tval, 32'hffff_ffff);
        expect_eq1("load suppressed", load_out, 1'b0);
        expect_eq1("store suppressed", store_out, 1'b0);
        expect_eq1("csr suppressed", csr_valid_out, 1'b0);
        expect_eq1("csr write suppressed", csr_write_out, 1'b0);
        expect_eq1("rd write suppressed", rd_write_out, 1'b0);
        expect_eq1("mret suppressed", system_mret_out, 1'b0);

        drive_defaults();
        execute_valid = 1'b0;
        load = 1'b1;
        store = 1'b1;
        csr_valid = 1'b1;
        csr_write = 1'b1;
        rd_write = 1'b1;
        #1;
        print_state("bubble");
        expect_eq1("bubble valid", execute_valid_out, 1'b0);
        expect_eq1("bubble load", load_out, 1'b0);
        expect_eq1("bubble store", store_out, 1'b0);
        expect_eq1("bubble csr", csr_valid_out, 1'b0);
        expect_eq1("bubble rd write", rd_write_out, 1'b0);

        $display("[PASS] execute memory/CSR/exception pass-through");
    endtask

    initial begin
        drive_defaults();
        run_alu_operand_test();
        run_branch_jump_test();
        run_mem_csr_exception_test();
        $display("[PASS] CPU execute tests complete");
        $finish;
    end

endmodule
