`timescale 1ns/1ps

module tb_cpu_commit;

    logic        commit_valid;
    logic [31:0] commit_pc;
    logic [31:0] commit_pc_plus4;
    logic [31:0] commit_instr;
    logic        exception_valid;
    logic [31:0] exception_cause;
    logic [31:0] exception_tval;
    logic        csr_valid;
    logic [11:0] csr_addr;
    logic [2:0]  csr_op;
    logic        csr_write;
    logic [31:0] csr_wdata;
    logic        csr_resp_illegal;
    logic        system_mret;
    logic        interrupt_pending;
    logic [31:0] interrupt_cause;
    logic [31:0] mtvec;
    logic [31:0] mepc;

    logic        csr_req_valid;
    logic [2:0]  csr_req_op;
    logic [11:0] csr_req_addr;
    logic [31:0] csr_req_wdata;
    logic        csr_req_write;
    logic        trap_valid;
    logic [31:0] trap_mepc;
    logic [31:0] trap_mcause;
    logic [31:0] trap_mtval;
    logic        mret_valid;
    logic        instret_inc;
    logic        redirect_valid;
    logic [31:0] redirect_pc;
    logic        commit_retired;
    logic        commit_exception;
    logic        commit_interrupt;

    localparam logic [2:0] CSR_OP_WRITE = 3'd1;
    localparam logic [2:0] CSR_OP_SET   = 3'd2;
    localparam logic [31:0] EXC_ILLEGAL = 32'd2;
    localparam logic [31:0] EXC_ECALL_MMODE = 32'd11;

    cpu_commit u_commit (
        .commit_valid_i       (commit_valid),
        .commit_pc_i          (commit_pc),
        .commit_pc_plus4_i    (commit_pc_plus4),
        .commit_instr_i       (commit_instr),
        .exception_valid_i    (exception_valid),
        .exception_cause_i    (exception_cause),
        .exception_tval_i     (exception_tval),
        .csr_valid_i          (csr_valid),
        .csr_addr_i           (csr_addr),
        .csr_op_i             (csr_op),
        .csr_write_i          (csr_write),
        .csr_wdata_i          (csr_wdata),
        .csr_resp_illegal_i   (csr_resp_illegal),
        .system_mret_i        (system_mret),
        .interrupt_pending_i  (interrupt_pending),
        .interrupt_cause_i    (interrupt_cause),
        .mtvec_i              (mtvec),
        .mepc_i               (mepc),
        .csr_req_valid_o      (csr_req_valid),
        .csr_req_op_o         (csr_req_op),
        .csr_req_addr_o       (csr_req_addr),
        .csr_req_wdata_o      (csr_req_wdata),
        .csr_req_write_o      (csr_req_write),
        .trap_valid_o         (trap_valid),
        .trap_mepc_o          (trap_mepc),
        .trap_mcause_o        (trap_mcause),
        .trap_mtval_o         (trap_mtval),
        .mret_valid_o         (mret_valid),
        .instret_inc_o        (instret_inc),
        .redirect_valid_o     (redirect_valid),
        .redirect_pc_o        (redirect_pc),
        .commit_retired_o     (commit_retired),
        .commit_exception_o   (commit_exception),
        .commit_interrupt_o   (commit_interrupt)
    );

    task automatic expect_eq1(input string name, input logic actual, input logic expected);
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=%0b expected=%0b", name, actual, expected);
        end
    endtask

    task automatic expect_eq3(input string name, input logic [2:0] actual, input logic [2:0] expected);
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=0x%0x expected=0x%0x", name, actual, expected);
        end
    endtask

    task automatic expect_eq12(input string name, input logic [11:0] actual, input logic [11:0] expected);
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=0x%03x expected=0x%03x", name, actual, expected);
        end
    endtask

    task automatic expect_eq32(input string name, input logic [31:0] actual, input logic [31:0] expected);
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=0x%08x expected=0x%08x", name, actual, expected);
        end
    endtask

    task automatic drive_defaults();
        commit_valid = 1'b1;
        commit_pc = 32'h0000_1000;
        commit_pc_plus4 = 32'h0000_1004;
        commit_instr = 32'h0000_0013;
        exception_valid = 1'b0;
        exception_cause = 32'h0000_0000;
        exception_tval = 32'h0000_0000;
        csr_valid = 1'b0;
        csr_addr = 12'h000;
        csr_op = CSR_OP_WRITE;
        csr_write = 1'b0;
        csr_wdata = 32'h0000_0000;
        csr_resp_illegal = 1'b0;
        system_mret = 1'b0;
        interrupt_pending = 1'b0;
        interrupt_cause = 32'h8000_000b;
        mtvec = 32'h0000_0100;
        mepc = 32'h0000_0200;
        #1;
    endtask

    task automatic print_state(input string name);
        $display("[COMMIT] %s trap=%0b mret=%0b instret=%0b redir=%0b redir_pc=0x%08x csr_v=%0b csr_w=%0b cause=0x%08x",
                 name, trap_valid, mret_valid, instret_inc,
                 redirect_valid, redirect_pc, csr_req_valid,
                 csr_req_write, trap_mcause);
    endtask

    initial begin
        drive_defaults();
        print_state("normal");
        expect_eq1("normal instret", instret_inc, 1'b1);
        expect_eq1("normal retired", commit_retired, 1'b1);
        expect_eq1("normal trap", trap_valid, 1'b0);
        expect_eq1("normal redirect", redirect_valid, 1'b0);

        drive_defaults();
        csr_valid = 1'b1;
        csr_addr = 12'h305;
        csr_op = CSR_OP_SET;
        csr_write = 1'b1;
        csr_wdata = 32'h0000_0088;
        #1;
        print_state("csr normal");
        expect_eq1("csr req valid", csr_req_valid, 1'b1);
        expect_eq3("csr req op", csr_req_op, CSR_OP_SET);
        expect_eq12("csr req addr", csr_req_addr, 12'h305);
        expect_eq32("csr req wdata", csr_req_wdata, 32'h0000_0088);
        expect_eq1("csr req write", csr_req_write, 1'b1);
        expect_eq1("csr instret", instret_inc, 1'b1);

        drive_defaults();
        exception_valid = 1'b1;
        exception_cause = EXC_ECALL_MMODE;
        exception_tval = 32'h0000_0000;
        csr_valid = 1'b1;
        csr_write = 1'b1;
        #1;
        print_state("exception");
        expect_eq1("exception trap", trap_valid, 1'b1);
        expect_eq32("exception mepc", trap_mepc, 32'h0000_1000);
        expect_eq32("exception cause", trap_mcause, EXC_ECALL_MMODE);
        expect_eq32("exception tval", trap_mtval, 32'h0000_0000);
        expect_eq1("exception redirect", redirect_valid, 1'b1);
        expect_eq32("exception redirect pc", redirect_pc, 32'h0000_0100);
        expect_eq1("exception instret suppressed", instret_inc, 1'b0);
        expect_eq1("exception csr suppressed", csr_req_valid, 1'b0);
        expect_eq1("commit exception flag", commit_exception, 1'b1);

        drive_defaults();
        commit_instr = 32'h3053_10f3;
        csr_valid = 1'b1;
        csr_addr = 12'h305;
        csr_op = CSR_OP_WRITE;
        csr_write = 1'b1;
        csr_wdata = 32'h1111_2222;
        csr_resp_illegal = 1'b1;
        #1;
        print_state("csr illegal");
        expect_eq1("csr illegal req valid", csr_req_valid, 1'b1);
        expect_eq1("csr illegal write suppressed", csr_req_write, 1'b0);
        expect_eq1("csr illegal trap", trap_valid, 1'b1);
        expect_eq32("csr illegal cause", trap_mcause, EXC_ILLEGAL);
        expect_eq32("csr illegal tval", trap_mtval, 32'h3053_10f3);
        expect_eq1("csr illegal instret", instret_inc, 1'b0);

        drive_defaults();
        system_mret = 1'b1;
        #1;
        print_state("mret");
        expect_eq1("mret valid", mret_valid, 1'b1);
        expect_eq1("mret redirect", redirect_valid, 1'b1);
        expect_eq32("mret redirect pc", redirect_pc, 32'h0000_0200);
        expect_eq1("mret instret", instret_inc, 1'b1);
        expect_eq1("mret trap", trap_valid, 1'b0);

        drive_defaults();
        interrupt_pending = 1'b1;
        interrupt_cause = 32'h8000_0007;
        #1;
        print_state("interrupt");
        expect_eq1("interrupt trap", trap_valid, 1'b1);
        expect_eq1("interrupt flag", commit_interrupt, 1'b1);
        expect_eq32("interrupt mepc", trap_mepc, 32'h0000_1004);
        expect_eq32("interrupt cause", trap_mcause, 32'h8000_0007);
        expect_eq32("interrupt tval", trap_mtval, 32'h0000_0000);
        expect_eq1("interrupt current inst retired", instret_inc, 1'b1);
        expect_eq32("interrupt redirect pc", redirect_pc, 32'h0000_0100);

        drive_defaults();
        commit_valid = 1'b0;
        csr_valid = 1'b1;
        csr_write = 1'b1;
        interrupt_pending = 1'b1;
        #1;
        print_state("bubble");
        expect_eq1("bubble csr", csr_req_valid, 1'b0);
        expect_eq1("bubble trap", trap_valid, 1'b0);
        expect_eq1("bubble instret", instret_inc, 1'b0);
        expect_eq1("bubble redirect", redirect_valid, 1'b0);

        $display("[PASS] CPU commit tests complete");
        $finish;
    end

endmodule
