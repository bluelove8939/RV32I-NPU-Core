`timescale 1ns/1ps

module tb_cpu_state;

    logic        clk;
    logic        reset_n;

    logic [4:0]  raddr0;
    logic [31:0] rdata0;
    logic [4:0]  raddr1;
    logic [31:0] rdata1;
    logic        rf_we;
    logic [4:0]  rf_waddr;
    logic [31:0] rf_wdata;

    logic        csr_req_valid;
    logic [2:0]  csr_req_op;
    logic [11:0] csr_req_addr;
    logic [31:0] csr_req_wdata;
    logic        csr_req_write;
    logic [31:0] csr_resp_rdata;
    logic        csr_resp_valid;
    logic        csr_resp_illegal;
    logic        instret_inc;
    logic        trap_valid;
    logic [31:0] trap_mepc;
    logic [31:0] trap_mcause;
    logic [31:0] trap_mtval;
    logic        mret_valid;
    logic        software_interrupt_pending;
    logic        timer_interrupt_pending;
    logic        external_interrupt_pending;
    logic [31:0] mstatus;
    logic [31:0] mie;
    logic [31:0] mtvec;
    logic [31:0] mscratch;
    logic [31:0] mepc;
    logic [31:0] mcause;
    logic [31:0] mtval;
    logic [31:0] mip;
    logic [63:0] mcycle;
    logic [63:0] minstret;
    logic        interrupt_pending;
    logic [31:0] interrupt_cause;

    localparam logic [2:0] CSR_OP_READ  = 3'd0;
    localparam logic [2:0] CSR_OP_WRITE = 3'd1;
    localparam logic [2:0] CSR_OP_SET   = 3'd2;
    localparam logic [2:0] CSR_OP_CLEAR = 3'd3;

    localparam logic [11:0] CSR_MSTATUS  = 12'h300;
    localparam logic [11:0] CSR_MISA     = 12'h301;
    localparam logic [11:0] CSR_MIE      = 12'h304;
    localparam logic [11:0] CSR_MTVEC    = 12'h305;
    localparam logic [11:0] CSR_MSCRATCH = 12'h340;
    localparam logic [11:0] CSR_MCYCLE   = 12'hB00;

    cpu_reg_file u_reg_file (
        .clk       (clk),
        .reset_n   (reset_n),
        .raddr0_i  (raddr0),
        .rdata0_o  (rdata0),
        .raddr1_i  (raddr1),
        .rdata1_o  (rdata1),
        .we_i      (rf_we),
        .waddr_i   (rf_waddr),
        .wdata_i   (rf_wdata)
    );

    cpu_csr u_csr (
        .clk                          (clk),
        .reset_n                      (reset_n),
        .csr_req_valid_i              (csr_req_valid),
        .csr_req_op_i                 (csr_req_op),
        .csr_req_addr_i               (csr_req_addr),
        .csr_req_wdata_i              (csr_req_wdata),
        .csr_req_write_i              (csr_req_write),
        .csr_resp_rdata_o             (csr_resp_rdata),
        .csr_resp_valid_o             (csr_resp_valid),
        .csr_resp_illegal_o           (csr_resp_illegal),
        .instret_inc_i                (instret_inc),
        .trap_valid_i                 (trap_valid),
        .trap_mepc_i                  (trap_mepc),
        .trap_mcause_i                (trap_mcause),
        .trap_mtval_i                 (trap_mtval),
        .mret_valid_i                 (mret_valid),
        .software_interrupt_pending_i (software_interrupt_pending),
        .timer_interrupt_pending_i    (timer_interrupt_pending),
        .external_interrupt_pending_i (external_interrupt_pending),
        .mstatus_o                    (mstatus),
        .mie_o                        (mie),
        .mtvec_o                      (mtvec),
        .mscratch_o                   (mscratch),
        .mepc_o                       (mepc),
        .mcause_o                     (mcause),
        .mtval_o                      (mtval),
        .mip_o                        (mip),
        .mcycle_o                     (mcycle),
        .minstret_o                   (minstret),
        .interrupt_pending_o          (interrupt_pending),
        .interrupt_cause_o            (interrupt_cause)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

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

    task automatic expect_eq64(
        input string name,
        input logic [63:0] actual,
        input logic [63:0] expected
    );
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=0x%016x expected=0x%016x",
                   name, actual, expected);
        end
    endtask

    task automatic reset_dut();
        reset_n = 1'b0;
        raddr0 = '0;
        raddr1 = '0;
        rf_we = 1'b0;
        rf_waddr = '0;
        rf_wdata = '0;
        csr_req_valid = 1'b0;
        csr_req_op = CSR_OP_READ;
        csr_req_addr = '0;
        csr_req_wdata = '0;
        csr_req_write = 1'b0;
        instret_inc = 1'b0;
        trap_valid = 1'b0;
        trap_mepc = '0;
        trap_mcause = '0;
        trap_mtval = '0;
        mret_valid = 1'b0;
        software_interrupt_pending = 1'b0;
        timer_interrupt_pending = 1'b0;
        external_interrupt_pending = 1'b0;

        repeat (3) @(posedge clk);
        reset_n = 1'b1;
        @(posedge clk);
        #1;
    endtask

    task automatic rf_write(input logic [4:0] addr, input logic [31:0] data);
        @(negedge clk);
        rf_we = 1'b1;
        rf_waddr = addr;
        rf_wdata = data;
        @(posedge clk);
        #1;
        rf_we = 1'b0;
    endtask

    task automatic csr_access(
        input  logic [11:0] addr,
        input  logic [2:0]  op,
        input  logic        do_write,
        input  logic [31:0] wdata,
        output logic [31:0] rdata,
        output logic        illegal
    );
        @(negedge clk);
        csr_req_valid = 1'b1;
        csr_req_op = op;
        csr_req_addr = addr;
        csr_req_wdata = wdata;
        csr_req_write = do_write;
        #1;
        if (!csr_resp_valid) begin
            $fatal(1, "[FAIL] CSR response was not valid");
        end
        rdata = csr_resp_rdata;
        illegal = csr_resp_illegal;
        @(posedge clk);
        #1;
        csr_req_valid = 1'b0;
        csr_req_write = 1'b0;
        csr_req_wdata = '0;
    endtask

    task automatic run_reg_file_test();
        $display("[TEST] register file");

        rf_write(5'd1, 32'hDEAD_BEEF);
        rf_write(5'd31, 32'hCAFE_0123);
        rf_write(5'd0, 32'hFFFF_FFFF);

        raddr0 = 5'd1;
        raddr1 = 5'd31;
        #1;
        expect_eq32("x1 read", rdata0, 32'hDEAD_BEEF);
        expect_eq32("x31 read", rdata1, 32'hCAFE_0123);

        raddr0 = 5'd0;
        #1;
        expect_eq32("x0 constant zero", rdata0, 32'h0000_0000);

        $display("[PASS] register file");
    endtask

    task automatic run_csr_test();
        logic [31:0] rdata;
        logic        illegal;
        logic [63:0] minstret_before;

        $display("[TEST] CSR file");

        csr_access(CSR_MTVEC, CSR_OP_WRITE, 1'b1, 32'h0000_0105, rdata, illegal);
        if (illegal) begin
            $fatal(1, "[FAIL] mtvec write reported illegal");
        end
        expect_eq32("mtvec alignment", mtvec, 32'h0000_0104);

        csr_access(CSR_MSCRATCH, CSR_OP_WRITE, 1'b1, 32'h1234_5678, rdata, illegal);
        expect_eq32("mscratch output", mscratch, 32'h1234_5678);
        csr_access(CSR_MSCRATCH, CSR_OP_READ, 1'b0, 32'h0000_0000, rdata, illegal);
        expect_eq32("mscratch readback", rdata, 32'h1234_5678);

        csr_access(CSR_MIE, CSR_OP_SET, 1'b1, 32'hFFFF_FFFF, rdata, illegal);
        expect_eq32("mie write mask", mie, 32'h0000_0888);
        csr_access(CSR_MIE, CSR_OP_CLEAR, 1'b1, 32'h0000_0080, rdata, illegal);
        expect_eq32("mie clear", mie, 32'h0000_0808);

        csr_access(CSR_MISA, CSR_OP_WRITE, 1'b1, 32'h0000_0000, rdata, illegal);
        if (!illegal) begin
            $fatal(1, "[FAIL] misa write did not report illegal");
        end

        csr_access(CSR_MCYCLE, CSR_OP_WRITE, 1'b1, 32'h0000_0010, rdata, illegal);
        csr_access(CSR_MCYCLE, CSR_OP_READ, 1'b0, 32'h0000_0000, rdata, illegal);
        if (rdata < 32'h0000_0010) begin
            $fatal(1, "[FAIL] mcycle did not advance from written value");
        end
        if (mcycle[31:0] < 32'h0000_0010) begin
            $fatal(1, "[FAIL] mcycle output did not advance from written value");
        end
        expect_eq32("mcycle high output", mcycle[63:32], 32'h0000_0000);

        minstret_before = minstret;
        @(negedge clk);
        instret_inc = 1'b1;
        @(posedge clk);
        #1;
        instret_inc = 1'b0;
        expect_eq64("minstret increment", minstret, minstret_before + 64'd1);

        csr_access(CSR_MSTATUS, CSR_OP_WRITE, 1'b1, 32'h0000_0008, rdata, illegal);
        @(negedge clk);
        trap_valid = 1'b1;
        trap_mepc = 32'h0000_0202;
        trap_mcause = 32'h0000_000B;
        trap_mtval = 32'h1111_2222;
        @(posedge clk);
        #1;
        trap_valid = 1'b0;
        expect_eq32("trap mepc alignment", mepc, 32'h0000_0200);
        expect_eq32("trap mcause", mcause, 32'h0000_000B);
        expect_eq32("trap mtval", mtval, 32'h1111_2222);
        expect_eq32("trap mstatus", mstatus & 32'h0000_1888, 32'h0000_1880);

        @(negedge clk);
        mret_valid = 1'b1;
        @(posedge clk);
        #1;
        mret_valid = 1'b0;
        expect_eq32("mret mstatus", mstatus & 32'h0000_1888, 32'h0000_1888);

        csr_access(CSR_MIE, CSR_OP_WRITE, 1'b1, 32'h0000_0888, rdata, illegal);
        csr_access(CSR_MSTATUS, CSR_OP_WRITE, 1'b1, 32'h0000_0008, rdata, illegal);
        external_interrupt_pending = 1'b1;
        #1;
        expect_eq32("mip external bit", mip, 32'h0000_0800);
        if (!interrupt_pending) begin
            $fatal(1, "[FAIL] external interrupt was not pending");
        end
        expect_eq32("external interrupt cause", interrupt_cause, 32'h8000_000B);

        $display("[PASS] CSR file");
    endtask

    initial begin
        reset_dut();
        run_reg_file_test();
        run_csr_test();
        $display("[PASS] CPU architectural state tests complete");
        $finish;
    end

endmodule
