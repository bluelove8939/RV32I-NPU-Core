`timescale 1ns/1ps

module tb_cpu_writeback;

    logic        wb_valid;
    logic [4:0]  rd_addr;
    logic        rd_write;
    logic [2:0]  wb_sel;
    logic [31:0] alu_result;
    logic [31:0] load_data;
    logic [31:0] csr_rdata;
    logic [31:0] pc_plus4;
    logic        exception_valid;
    logic        rf_we;
    logic [4:0]  rf_waddr;
    logic [31:0] rf_wdata;
    logic [31:0] wb_data;

    localparam logic [2:0] WB_ALU  = 3'd0;
    localparam logic [2:0] WB_LOAD = 3'd1;
    localparam logic [2:0] WB_CSR  = 3'd2;
    localparam logic [2:0] WB_PC4  = 3'd3;

    cpu_writeback u_writeback (
        .wb_valid_i         (wb_valid),
        .rd_addr_i          (rd_addr),
        .rd_write_i         (rd_write),
        .wb_sel_i           (wb_sel),
        .alu_result_i       (alu_result),
        .load_data_i        (load_data),
        .csr_rdata_i        (csr_rdata),
        .pc_plus4_i         (pc_plus4),
        .exception_valid_i  (exception_valid),
        .rf_we_o            (rf_we),
        .rf_waddr_o         (rf_waddr),
        .rf_wdata_o         (rf_wdata),
        .wb_data_o          (wb_data)
    );

    task automatic expect_eq1(input string name, input logic actual, input logic expected);
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=%0b expected=%0b", name, actual, expected);
        end
    endtask

    task automatic expect_eq5(input string name, input logic [4:0] actual, input logic [4:0] expected);
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=0x%0x expected=0x%0x", name, actual, expected);
        end
    endtask

    task automatic expect_eq32(input string name, input logic [31:0] actual, input logic [31:0] expected);
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=0x%08x expected=0x%08x", name, actual, expected);
        end
    endtask

    task automatic drive_defaults();
        wb_valid = 1'b1;
        rd_addr = 5'd5;
        rd_write = 1'b1;
        wb_sel = WB_ALU;
        alu_result = 32'haaaa_0001;
        load_data = 32'hbbbb_0002;
        csr_rdata = 32'hcccc_0003;
        pc_plus4 = 32'hdddd_0004;
        exception_valid = 1'b0;
        #1;
    endtask

    task automatic check_source(input string name, input logic [2:0] sel, input logic [31:0] expected);
        drive_defaults();
        wb_sel = sel;
        #1;
        $display("[WB] %s sel=%0d data=0x%08x rf_we=%0b", name, sel, wb_data, rf_we);
        expect_eq32(name, wb_data, expected);
        expect_eq32({name, " rf_wdata"}, rf_wdata, expected);
        expect_eq1({name, " rf_we"}, rf_we, 1'b1);
        expect_eq5({name, " rf_waddr"}, rf_waddr, 5'd5);
    endtask

    initial begin
        check_source("alu", WB_ALU, 32'haaaa_0001);
        check_source("load", WB_LOAD, 32'hbbbb_0002);
        check_source("csr", WB_CSR, 32'hcccc_0003);
        check_source("pc4", WB_PC4, 32'hdddd_0004);
        check_source("default", 3'd7, 32'haaaa_0001);

        drive_defaults();
        rd_addr = 5'd0;
        #1;
        expect_eq1("x0 write suppressed", rf_we, 1'b0);
        expect_eq32("x0 data still selected", wb_data, 32'haaaa_0001);

        drive_defaults();
        rd_write = 1'b0;
        #1;
        expect_eq1("rd_write false suppressed", rf_we, 1'b0);

        drive_defaults();
        wb_valid = 1'b0;
        #1;
        expect_eq1("invalid suppressed", rf_we, 1'b0);

        drive_defaults();
        exception_valid = 1'b1;
        #1;
        expect_eq1("exception suppressed", rf_we, 1'b0);

        $display("[PASS] CPU writeback tests complete");
        $finish;
    end

endmodule
