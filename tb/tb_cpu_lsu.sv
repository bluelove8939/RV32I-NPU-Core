`timescale 1ns/1ps

module tb_cpu_lsu;

    localparam int unsigned ADDR_WIDTH = 32;
    localparam int unsigned DATA_WIDTH = 32;
    localparam int unsigned LINE_WORDS = 16;
    localparam int unsigned LINE_WIDTH = DATA_WIDTH * LINE_WORDS;
    localparam int unsigned MEM_BYTES = 256;
    localparam int unsigned N_BANK_GROUPS = 4;

    localparam logic [1:0] MEM_BYTE = 2'd0;
    localparam logic [1:0] MEM_HALF = 2'd1;
    localparam logic [1:0] MEM_WORD = 2'd2;

    localparam logic [31:0] EXC_LOAD_ADDR_MISALIGNED  = 32'd4;
    localparam logic [31:0] EXC_STORE_ADDR_MISALIGNED = 32'd6;

    logic clk;
    logic reset_n;

    logic                  req_valid;
    logic                  req_ready;
    logic                  req_write;
    logic [31:0]           req_addr;
    logic [31:0]           req_wdata;
    logic [1:0]            req_size;
    logic                  req_unsigned;
    logic                  resp_valid;
    logic                  resp_ready;
    logic [31:0]           resp_rdata;
    logic                  resp_exception_valid;
    logic [31:0]           resp_exception_cause;
    logic [31:0]           resp_exception_tval;
    logic                  snoop_valid;
    logic [ADDR_WIDTH-1:0] snoop_line_addr;
    logic                  snoop_stall;
    logic                  flush_valid;
    logic                  flush_ready;

    logic                  d_req_valid;
    logic                  d_req_ready;
    logic                  d_req_write;
    logic [ADDR_WIDTH-1:0] d_req_line_addr;
    logic [LINE_WIDTH-1:0] d_req_wdata;
    logic [LINE_WORDS-1:0] d_req_wstrb;
    logic                  d_resp_valid;
    logic                  d_resp_ready;
    logic [LINE_WIDTH-1:0] d_resp_rdata;
    logic                  d_resp_error;

    logic                  i_req_valid;
    logic                  i_req_ready;
    logic [ADDR_WIDTH-1:0] i_req_line_addr;
    logic                  i_resp_valid;
    logic                  i_resp_ready;
    logic [LINE_WIDTH-1:0] i_resp_rdata;
    logic                  i_resp_error;

    cpu_lsu #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .LINE_WORDS (LINE_WORDS),
        .LINE_WIDTH (LINE_WIDTH)
    ) u_lsu (
        .clk                    (clk),
        .reset_n                (reset_n),
        .req_valid_i            (req_valid),
        .req_ready_o            (req_ready),
        .req_write_i            (req_write),
        .req_addr_i             (req_addr),
        .req_wdata_i            (req_wdata),
        .req_size_i             (req_size),
        .req_unsigned_i         (req_unsigned),
        .resp_valid_o           (resp_valid),
        .resp_ready_i           (resp_ready),
        .resp_rdata_o           (resp_rdata),
        .resp_exception_valid_o (resp_exception_valid),
        .resp_exception_cause_o (resp_exception_cause),
        .resp_exception_tval_o  (resp_exception_tval),
        .snoop_valid_i          (snoop_valid),
        .snoop_line_addr_i      (snoop_line_addr),
        .snoop_stall_o          (snoop_stall),
        .flush_valid_i          (flush_valid),
        .flush_ready_o          (flush_ready),
        .spm_req_valid_o        (d_req_valid),
        .spm_req_ready_i        (d_req_ready),
        .spm_req_write_o        (d_req_write),
        .spm_req_line_addr_o    (d_req_line_addr),
        .spm_req_wdata_o        (d_req_wdata),
        .spm_req_wstrb_o        (d_req_wstrb),
        .spm_resp_valid_i       (d_resp_valid),
        .spm_resp_ready_o       (d_resp_ready),
        .spm_resp_rdata_i       (d_resp_rdata),
        .spm_resp_error_i       (d_resp_error)
    );

    spm_bus #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .LINE_WORDS    (LINE_WORDS),
        .MEM_BYTES     (MEM_BYTES),
        .N_BANK_GROUPS (N_BANK_GROUPS),
        .LINE_WIDTH    (LINE_WIDTH)
    ) u_spm_bus (
        .clk               (clk),
        .reset_n           (reset_n),
        .i_req_valid_i     (i_req_valid),
        .i_req_ready_o     (i_req_ready),
        .i_req_line_addr_i (i_req_line_addr),
        .i_resp_valid_o    (i_resp_valid),
        .i_resp_ready_i    (i_resp_ready),
        .i_resp_rdata_o    (i_resp_rdata),
        .i_resp_error_o    (i_resp_error),
        .d_req_valid_i     (d_req_valid),
        .d_req_ready_o     (d_req_ready),
        .d_req_write_i     (d_req_write),
        .d_req_line_addr_i (d_req_line_addr),
        .d_req_wdata_i     (d_req_wdata),
        .d_req_wstrb_i     (d_req_wstrb),
        .d_resp_valid_o    (d_resp_valid),
        .d_resp_ready_i    (d_resp_ready),
        .d_resp_rdata_o    (d_resp_rdata),
        .d_resp_error_o    (d_resp_error)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic logic [31:0] word_pattern(
        input int unsigned line_idx,
        input int unsigned word_idx
    );
        return 32'h1000_0000 + (line_idx[31:0] << 8) + word_idx[31:0];
    endfunction

    task automatic expect_eq1(input string name, input logic actual, input logic expected);
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=%0b expected=%0b", name, actual, expected);
        end
    endtask

    task automatic expect_eq32(input string name, input logic [31:0] actual, input logic [31:0] expected);
        if (actual !== expected) begin
            $fatal(1, "[FAIL] %s actual=0x%08x expected=0x%08x", name, actual, expected);
        end
    endtask

    task automatic reset_dut();
        reset_n = 1'b0;
        req_valid = 1'b0;
        req_write = 1'b0;
        req_addr = '0;
        req_wdata = '0;
        req_size = MEM_WORD;
        req_unsigned = 1'b0;
        resp_ready = 1'b1;
        snoop_valid = 1'b0;
        snoop_line_addr = '0;
        flush_valid = 1'b0;
        i_req_valid = 1'b0;
        i_req_line_addr = '0;
        i_resp_ready = 1'b1;
        repeat (4) @(posedge clk);
        reset_n = 1'b1;
        @(posedge clk);
        #1;
    endtask

    task automatic lsu_access(
        input  logic        is_write,
        input  logic [31:0] addr,
        input  logic [31:0] wdata,
        input  logic [1:0]  size,
        input  logic        is_unsigned,
        output logic [31:0] rdata,
        output logic        exc_valid,
        output logic [31:0] exc_cause,
        output logic [31:0] exc_tval
    );
        int unsigned cycles;
        begin
            @(negedge clk);
            req_valid = 1'b1;
            req_write = is_write;
            req_addr = addr;
            req_wdata = wdata;
            req_size = size;
            req_unsigned = is_unsigned;
            while (!req_ready) begin
                @(negedge clk);
            end
            @(posedge clk);
            #1;
            req_valid = 1'b0;

            cycles = 0;
            while (!resp_valid) begin
                @(posedge clk);
                #1;
                cycles++;
                if (cycles > 80) begin
                    $fatal(1, "[FAIL] LSU response timeout addr=0x%08x", addr);
                end
            end
            rdata = resp_rdata;
            exc_valid = resp_exception_valid;
            exc_cause = resp_exception_cause;
            exc_tval = resp_exception_tval;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic lsu_store_word(input logic [31:0] addr, input logic [31:0] data);
        logic [31:0] rdata;
        logic exc_valid;
        logic [31:0] exc_cause;
        logic [31:0] exc_tval;
        begin
            lsu_access(1'b1, addr, data, MEM_WORD, 1'b0,
                       rdata, exc_valid, exc_cause, exc_tval);
            expect_eq1("store exception", exc_valid, 1'b0);
            expect_eq32("store rdata", rdata, 32'h0000_0000);
            expect_eq32("store cause", exc_cause, 32'h0000_0000);
            expect_eq32("store tval", exc_tval, 32'h0000_0000);
        end
    endtask

    task automatic lsu_flush();
        int unsigned cycles;
        begin
            @(negedge clk);
            flush_valid = 1'b1;
            cycles = 0;
            while (!flush_ready) begin
                @(posedge clk);
                #1;
                cycles++;
                if (cycles > 80) begin
                    $fatal(1, "[FAIL] LSU flush timeout");
                end
            end
            @(negedge clk);
            flush_valid = 1'b0;
        end
    endtask

    task automatic snoop_flush(input logic [ADDR_WIDTH-1:0] line_addr);
        int unsigned cycles;
        begin
            @(negedge clk);
            snoop_valid = 1'b1;
            snoop_line_addr = line_addr;
            cycles = 0;
            do begin
                @(posedge clk);
                #1;
                cycles++;
                if (cycles > 80) begin
                    $fatal(1, "[FAIL] snoop flush timeout line=0x%08x", line_addr);
                end
            end while (snoop_stall);
            @(negedge clk);
            snoop_valid = 1'b0;
        end
    endtask

    task automatic i_read_line(
        input  logic [ADDR_WIDTH-1:0] line_addr,
        output logic [LINE_WIDTH-1:0] line_data
    );
        int unsigned cycles;
        begin
            @(negedge clk);
            i_req_valid = 1'b1;
            i_req_line_addr = line_addr;
            while (!i_req_ready) begin
                @(negedge clk);
            end
            @(posedge clk);
            #1;
            i_req_valid = 1'b0;

            cycles = 0;
            while (!i_resp_valid) begin
                @(posedge clk);
                #1;
                cycles++;
                if (cycles > 80) begin
                    $fatal(1, "[FAIL] instruction port read timeout");
                end
            end
            if (i_resp_error) begin
                $fatal(1, "[FAIL] instruction port read error");
            end
            line_data = i_resp_rdata;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic init_line(input int unsigned line_idx);
        for (int unsigned word_idx = 0; word_idx < LINE_WORDS; word_idx++) begin
            lsu_store_word((line_idx * 64 + word_idx * 4), word_pattern(line_idx, word_idx));
        end
        lsu_flush();
    endtask

    task automatic run_load_store_test();
        logic [31:0] rdata;
        logic exc_valid;
        logic [31:0] exc_cause;
        logic [31:0] exc_tval;
        begin
            $display("[TEST] LSU load/store and store buffer hit");
            init_line(0);

            lsu_access(1'b0, 32'h0000_0008, '0, MEM_WORD, 1'b0,
                       rdata, exc_valid, exc_cause, exc_tval);
            expect_eq1("lw exception", exc_valid, 1'b0);
            expect_eq32("lw cause", exc_cause, 32'h0000_0000);
            expect_eq32("lw tval", exc_tval, 32'h0000_0000);
            expect_eq32("lw data", rdata, word_pattern(0, 2));

            lsu_access(1'b1, 32'h0000_0009, 32'h0000_00aa, MEM_BYTE, 1'b0,
                       rdata, exc_valid, exc_cause, exc_tval);
            expect_eq1("sb exception", exc_valid, 1'b0);
            expect_eq32("sb cause", exc_cause, 32'h0000_0000);
            expect_eq32("sb tval", exc_tval, 32'h0000_0000);

            lsu_access(1'b0, 32'h0000_0008, '0, MEM_WORD, 1'b0,
                       rdata, exc_valid, exc_cause, exc_tval);
            expect_eq32("store buffer word merge", rdata, 32'h1000_aa02);

            lsu_access(1'b0, 32'h0000_0009, '0, MEM_BYTE, 1'b1,
                       rdata, exc_valid, exc_cause, exc_tval);
            expect_eq32("lbu merged byte", rdata, 32'h0000_00aa);

            lsu_access(1'b1, 32'h0000_000a, 32'h0000_8081, MEM_HALF, 1'b0,
                       rdata, exc_valid, exc_cause, exc_tval);
            expect_eq1("sh exception", exc_valid, 1'b0);
            expect_eq32("sh cause", exc_cause, 32'h0000_0000);
            expect_eq32("sh tval", exc_tval, 32'h0000_0000);
            lsu_access(1'b0, 32'h0000_000a, '0, MEM_HALF, 1'b0,
                       rdata, exc_valid, exc_cause, exc_tval);
            expect_eq32("lh sign extend", rdata, 32'hffff_8081);

            $display("[PASS] LSU load/store and store buffer hit");
        end
    endtask

    task automatic run_snoop_and_flush_test();
        logic [LINE_WIDTH-1:0] line_data;
        logic [31:0] rdata;
        logic exc_valid;
        logic [31:0] exc_cause;
        logic [31:0] exc_tval;
        begin
            $display("[TEST] LSU snoop and explicit flush");

            i_read_line(0, line_data);
            $display("[LINE] line0 before snoop xor=%0b", ^line_data);
            expect_eq32("SPM old word before snoop",
                        line_data[2 * 32 +: 32], word_pattern(0, 2));

            snoop_flush(0);
            i_read_line(0, line_data);
            $display("[LINE] line0 after snoop xor=%0b", ^line_data);
            expect_eq32("SPM committed word after snoop",
                        line_data[2 * 32 +: 32], 32'h8081_aa02);

            init_line(1);
            lsu_access(1'b1, 32'h0000_0040, 32'hfeed_cafe, MEM_WORD, 1'b0,
                       rdata, exc_valid, exc_cause, exc_tval);
            expect_eq1("line1 store exception", exc_valid, 1'b0);
            expect_eq32("line1 store rdata", rdata, 32'h0000_0000);
            expect_eq32("line1 store cause", exc_cause, 32'h0000_0000);
            expect_eq32("line1 store tval", exc_tval, 32'h0000_0000);
            lsu_flush();
            i_read_line(1, line_data);
            $display("[LINE] line1 after flush xor=%0b", ^line_data);
            expect_eq32("explicit flush committed line1",
                        line_data[0 +: 32], 32'hfeed_cafe);

            $display("[PASS] LSU snoop and explicit flush");
        end
    endtask

    task automatic run_misaligned_test();
        logic [31:0] rdata;
        logic exc_valid;
        logic [31:0] exc_cause;
        logic [31:0] exc_tval;
        begin
            $display("[TEST] LSU misaligned exceptions");
            lsu_access(1'b0, 32'h0000_0001, '0, MEM_HALF, 1'b0,
                       rdata, exc_valid, exc_cause, exc_tval);
            expect_eq1("lh misaligned exception", exc_valid, 1'b1);
            expect_eq32("lh misaligned rdata", rdata, 32'h0000_0000);
            expect_eq32("lh misaligned cause", exc_cause, EXC_LOAD_ADDR_MISALIGNED);
            expect_eq32("lh misaligned tval", exc_tval, 32'h0000_0001);

            lsu_access(1'b1, 32'h0000_0002, 32'h1234_5678, MEM_WORD, 1'b0,
                       rdata, exc_valid, exc_cause, exc_tval);
            expect_eq1("sw misaligned exception", exc_valid, 1'b1);
            expect_eq32("sw misaligned rdata", rdata, 32'h0000_0000);
            expect_eq32("sw misaligned cause", exc_cause, EXC_STORE_ADDR_MISALIGNED);
            expect_eq32("sw misaligned tval", exc_tval, 32'h0000_0002);
            $display("[PASS] LSU misaligned exceptions");
        end
    endtask

    initial begin
        reset_dut();
        run_load_store_test();
        run_snoop_and_flush_test();
        run_misaligned_test();
        $display("[PASS] CPU LSU tests complete");
        $finish;
    end

endmodule
