`timescale 1ns/1ps

module tb_cpu_i_fetcher;

    localparam int unsigned ADDR_WIDTH = 32;
    localparam int unsigned DATA_WIDTH = 32;
    localparam int unsigned LINE_WORDS = 16;
    localparam int unsigned LINE_WIDTH = DATA_WIDTH * LINE_WORDS;
    localparam int unsigned MEM_BYTES = 256;
    localparam int unsigned N_BANK_GROUPS = 4;
    localparam int unsigned CACHELINE_BYTES = (DATA_WIDTH / 8) * LINE_WORDS;
    localparam int unsigned NUM_LINES = MEM_BYTES / CACHELINE_BYTES;

    localparam logic [31:0] EXC_INSTR_ADDR_MISALIGNED = 32'd0;
    localparam logic [31:0] EXC_INSTR_ACCESS_FAULT = 32'd1;

    logic                  clk;
    logic                  reset_n;
    logic                  monitor_enable;

    logic                  fetch_enable;
    logic                  redirect_valid;
    logic [31:0]           redirect_pc;
    logic                  snoop_query_valid;
    logic [ADDR_WIDTH-1:0] snoop_query_line_addr;
    logic                  snoop_stall;
    logic                  invalidate_valid;
    logic [ADDR_WIDTH-1:0] invalidate_line_addr;
    logic                  instr_valid;
    logic                  instr_ready;
    logic [31:0]           instr_pc;
    logic [31:0]           instr;
    logic                  instr_exception_valid;
    logic [31:0]           instr_exception_cause;
    logic [31:0]           instr_exception_tval;
    logic                  fetcher_spm_req_valid;
    logic                  fetcher_spm_req_ready;
    logic [ADDR_WIDTH-1:0] fetcher_spm_req_line_addr;
    logic                  fetcher_spm_resp_valid;
    logic                  fetcher_spm_resp_ready;
    logic [LINE_WIDTH-1:0] fetcher_spm_resp_rdata;
    logic                  fetcher_spm_resp_error;
    logic [31:0]           fetch_pc;
    logic                  fetch_stalled;

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

    cpu_i_fetcher #(
        .RESET_PC   (32'h0000_0000),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .LINE_WORDS (LINE_WORDS),
        .LINE_WIDTH (LINE_WIDTH)
    ) u_i_fetcher (
        .clk                       (clk),
        .reset_n                   (reset_n),
        .fetch_enable_i            (fetch_enable),
        .redirect_valid_i          (redirect_valid),
        .redirect_pc_i             (redirect_pc),
        .snoop_query_valid_o       (snoop_query_valid),
        .snoop_query_line_addr_o   (snoop_query_line_addr),
        .snoop_stall_i             (snoop_stall),
        .invalidate_valid_i        (invalidate_valid),
        .invalidate_line_addr_i    (invalidate_line_addr),
        .instr_valid_o             (instr_valid),
        .instr_ready_i             (instr_ready),
        .instr_pc_o                (instr_pc),
        .instr_o                   (instr),
        .instr_exception_valid_o   (instr_exception_valid),
        .instr_exception_cause_o   (instr_exception_cause),
        .instr_exception_tval_o    (instr_exception_tval),
        .spm_req_valid_o           (fetcher_spm_req_valid),
        .spm_req_ready_i           (fetcher_spm_req_ready),
        .spm_req_line_addr_o       (fetcher_spm_req_line_addr),
        .spm_resp_valid_i          (fetcher_spm_resp_valid),
        .spm_resp_ready_o          (fetcher_spm_resp_ready),
        .spm_resp_rdata_i          (fetcher_spm_resp_rdata),
        .spm_resp_error_i          (fetcher_spm_resp_error),
        .fetch_pc_o                (fetch_pc),
        .fetch_stalled_o           (fetch_stalled)
    );

    spm_bus #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .LINE_WORDS    (LINE_WORDS),
        .MEM_BYTES     (MEM_BYTES),
        .N_BANK_GROUPS (N_BANK_GROUPS),
        .LINE_WIDTH    (LINE_WIDTH)
    ) u_spm_bus (
        .clk                (clk),
        .reset_n            (reset_n),
        .i_req_valid_i      (fetcher_spm_req_valid),
        .i_req_ready_o      (fetcher_spm_req_ready),
        .i_req_line_addr_i  (fetcher_spm_req_line_addr),
        .i_resp_valid_o     (fetcher_spm_resp_valid),
        .i_resp_ready_i     (fetcher_spm_resp_ready),
        .i_resp_rdata_o     (fetcher_spm_resp_rdata),
        .i_resp_error_o     (fetcher_spm_resp_error),
        .d_req_valid_i      (d_req_valid),
        .d_req_ready_o      (d_req_ready),
        .d_req_write_i      (d_req_write),
        .d_req_line_addr_i  (d_req_line_addr),
        .d_req_wdata_i      (d_req_wdata),
        .d_req_wstrb_i      (d_req_wstrb),
        .d_resp_valid_o     (d_resp_valid),
        .d_resp_ready_i     (d_resp_ready),
        .d_resp_rdata_o     (d_resp_rdata),
        .d_resp_error_o     (d_resp_error)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (monitor_enable && fetch_enable) begin
            $display("[cycle %0t] pc=0x%08x snoop_v=%0b snoop_line=0x%08x snoop_stall=%0b inv=%0b inv_line=0x%08x req_v=%0b req_r=%0b req_line=0x%08x resp_v=%0b resp_err=%0b instr_v=%0b instr_r=%0b instr_pc=0x%08x instr=0x%08x exc=%0b cause=0x%08x stall=%0b",
                     $time, fetch_pc,
                     snoop_query_valid, snoop_query_line_addr, snoop_stall,
                     invalidate_valid, invalidate_line_addr,
                     fetcher_spm_req_valid, fetcher_spm_req_ready,
                     fetcher_spm_req_line_addr,
                     fetcher_spm_resp_valid, fetcher_spm_resp_error,
                     instr_valid, instr_ready, instr_pc, instr,
                     instr_exception_valid, instr_exception_cause,
                     fetch_stalled);
        end
    end

    function automatic logic [31:0] make_instr(input int unsigned instr_idx);
        return 32'h1000_0000 + instr_idx[31:0];
    endfunction

    function automatic logic [31:0] make_updated_instr(
        input int unsigned instr_idx
    );
        return 32'h2000_0000 + instr_idx[31:0];
    endfunction

    function automatic logic [LINE_WIDTH-1:0] make_line(
        input int unsigned line_idx
    );
        logic [LINE_WIDTH-1:0] line_data;
        int unsigned instr_idx;
        begin
            line_data = '0;
            for (int unsigned word_idx = 0;
                 word_idx < LINE_WORDS;
                 word_idx++) begin
                instr_idx = (line_idx * LINE_WORDS) + word_idx;
                line_data[word_idx * DATA_WIDTH +: DATA_WIDTH] =
                    make_instr(instr_idx);
            end
            return line_data;
        end
    endfunction

    function automatic logic [LINE_WIDTH-1:0] make_updated_line(
        input int unsigned line_idx
    );
        logic [LINE_WIDTH-1:0] line_data;
        int unsigned instr_idx;
        begin
            line_data = '0;
            for (int unsigned word_idx = 0;
                 word_idx < LINE_WORDS;
                 word_idx++) begin
                instr_idx = (line_idx * LINE_WORDS) + word_idx;
                line_data[word_idx * DATA_WIDTH +: DATA_WIDTH] =
                    make_updated_instr(instr_idx);
            end
            return line_data;
        end
    endfunction

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

    task automatic reset_dut();
        reset_n = 1'b0;
        monitor_enable = 1'b0;
        fetch_enable = 1'b0;
        redirect_valid = 1'b0;
        redirect_pc = 32'h0000_0000;
        snoop_stall = 1'b0;
        invalidate_valid = 1'b0;
        invalidate_line_addr = '0;
        instr_ready = 1'b0;
        d_req_valid = 1'b0;
        d_req_write = 1'b0;
        d_req_line_addr = '0;
        d_req_wdata = '0;
        d_req_wstrb = '0;
        d_resp_ready = 1'b1;

        repeat (4) @(posedge clk);
        reset_n = 1'b1;
        @(posedge clk);
        #1;
        monitor_enable = 1'b1;
    endtask

    task automatic data_write_line(
        input logic [ADDR_WIDTH-1:0] line_addr,
        input logic [LINE_WIDTH-1:0] line_data
    );
        @(negedge clk);
        d_req_valid = 1'b1;
        d_req_write = 1'b1;
        d_req_line_addr = line_addr;
        d_req_wdata = line_data;
        d_req_wstrb = '1;
        while (!d_req_ready) begin
            @(negedge clk);
        end

        @(posedge clk);
        #1;

        @(negedge clk);
        d_req_valid = 1'b0;
        d_req_write = 1'b0;
        d_req_wdata = '0;
        d_req_wstrb = '0;

        #1;
        while (!d_resp_valid) begin
            @(posedge clk);
            #1;
        end

        if (d_resp_error) begin
            $fatal(1, "[FAIL] data init write returned error line=0x%08x",
                   line_addr);
        end
        $display("[INIT] line=0x%08x write response xor=%0b",
                 line_addr, ^d_resp_rdata);

        @(posedge clk);
        #1;
    endtask

    task automatic init_instruction_spm();
        $display("[TEST] init instruction SPM");
        for (int unsigned line_idx = 0; line_idx < NUM_LINES; line_idx++) begin
            data_write_line(line_idx[ADDR_WIDTH-1:0], make_line(line_idx));
        end
    endtask

    task automatic wait_and_accept_instr(
        output logic [31:0] pc,
        output logic [31:0] data,
        output logic        exc_valid,
        output logic [31:0] exc_cause,
        output logic [31:0] exc_tval
    );
        int unsigned wait_cycles;
        begin
            wait_cycles = 0;
            instr_ready = 1'b1;
            while (!instr_valid) begin
                @(posedge clk);
                #1;
                wait_cycles++;
                if (wait_cycles > 40) begin
                    $fatal(1, "[FAIL] instruction fetch timeout");
                end
            end

            pc = instr_pc;
            data = instr;
            exc_valid = instr_exception_valid;
            exc_cause = instr_exception_cause;
            exc_tval = instr_exception_tval;

            @(posedge clk);
            #1;
            instr_ready = 1'b0;
        end
    endtask

    task automatic redirect_to(input logic [31:0] pc);
        @(negedge clk);
        redirect_valid = 1'b1;
        redirect_pc = pc;
        @(posedge clk);
        #1;
        redirect_valid = 1'b0;
        redirect_pc = 32'h0000_0000;
    endtask

    task automatic invalidate_line(input logic [ADDR_WIDTH-1:0] line_addr);
        @(negedge clk);
        invalidate_valid = 1'b1;
        invalidate_line_addr = line_addr;
        @(posedge clk);
        #1;
        invalidate_valid = 1'b0;
        invalidate_line_addr = '0;
    endtask

    task automatic run_sequential_fetch_test();
        logic [31:0] pc;
        logic [31:0] data;
        logic        exc_valid;
        logic [31:0] exc_cause;
        logic [31:0] exc_tval;

        $display("[TEST] sequential fetch across cacheline boundary");
        fetch_enable = 1'b1;

        for (int unsigned instr_idx = 0; instr_idx < 20; instr_idx++) begin
            wait_and_accept_instr(pc, data, exc_valid, exc_cause, exc_tval);
            expect_eq32("sequential pc", pc, instr_idx[31:0] * 32'd4);
            expect_eq32("sequential instr", data, make_instr(instr_idx));
            if (exc_valid) begin
                $fatal(1, "[FAIL] unexpected sequential fetch exception");
            end
            expect_eq32("sequential cause", exc_cause, 32'h0000_0000);
            expect_eq32("sequential tval", exc_tval, 32'h0000_0000);
        end

        $display("[PASS] sequential fetch across cacheline boundary");
    endtask

    task automatic run_backpressure_test();
        logic [31:0] held_pc;
        logic [31:0] held_instr;
        logic [31:0] pc;
        logic [31:0] data;
        logic        exc_valid;
        logic [31:0] exc_cause;
        logic [31:0] exc_tval;

        $display("[TEST] downstream backpressure holds instruction");
        redirect_to(32'h0000_0040);

        instr_ready = 1'b0;
        while (!instr_valid) begin
            @(posedge clk);
            #1;
        end

        held_pc = instr_pc;
        held_instr = instr;
        repeat (3) begin
            @(posedge clk);
            #1;
            expect_eq32("held pc", instr_pc, held_pc);
            expect_eq32("held instr", instr, held_instr);
        end

        wait_and_accept_instr(pc, data, exc_valid, exc_cause, exc_tval);
        expect_eq32("backpressure pc", pc, 32'h0000_0040);
        expect_eq32("backpressure instr", data, make_instr(16));
        if (exc_valid) begin
            $fatal(1, "[FAIL] unexpected backpressure exception");
        end
        expect_eq32("backpressure cause", exc_cause, 32'h0000_0000);
        expect_eq32("backpressure tval", exc_tval, 32'h0000_0000);

        $display("[PASS] downstream backpressure holds instruction");
    endtask

    task automatic run_redirect_test();
        logic [31:0] pc;
        logic [31:0] data;
        logic        exc_valid;
        logic [31:0] exc_cause;
        logic [31:0] exc_tval;

        $display("[TEST] redirect to a different cacheline");
        redirect_to(32'h0000_0080);
        wait_and_accept_instr(pc, data, exc_valid, exc_cause, exc_tval);
        expect_eq32("redirect pc", pc, 32'h0000_0080);
        expect_eq32("redirect instr", data, make_instr(32));
        if (exc_valid) begin
            $fatal(1, "[FAIL] unexpected redirect exception");
        end
        expect_eq32("redirect cause", exc_cause, 32'h0000_0000);
        expect_eq32("redirect tval", exc_tval, 32'h0000_0000);

        $display("[PASS] redirect to a different cacheline");
    endtask

    task automatic run_snoop_stall_test();
        logic [31:0] pc;
        logic [31:0] data;
        logic        exc_valid;
        logic [31:0] exc_cause;
        logic [31:0] exc_tval;

        $display("[TEST] snoop stall blocks fetch request");
        snoop_stall = 1'b1;
        redirect_to(32'h0000_00c0);

        repeat (3) begin
            @(posedge clk);
            #1;
            if (!snoop_query_valid) begin
                $fatal(1, "[FAIL] snoop query was not valid during stall");
            end
            expect_eq32("snoop query line", snoop_query_line_addr, 32'h0000_0003);
            if (fetcher_spm_req_valid) begin
                $fatal(1, "[FAIL] fetch request issued while snoop stalled");
            end
            if (instr_valid) begin
                $fatal(1, "[FAIL] instruction produced while snoop stalled");
            end
        end

        snoop_stall = 1'b0;
        wait_and_accept_instr(pc, data, exc_valid, exc_cause, exc_tval);
        expect_eq32("snoop released pc", pc, 32'h0000_00c0);
        expect_eq32("snoop released instr", data, make_instr(48));
        if (exc_valid) begin
            $fatal(1, "[FAIL] unexpected snoop release exception");
        end
        expect_eq32("snoop released cause", exc_cause, 32'h0000_0000);
        expect_eq32("snoop released tval", exc_tval, 32'h0000_0000);

        $display("[PASS] snoop stall blocks fetch request");
    endtask

    task automatic run_invalidate_stale_line_test();
        logic [31:0] pc;
        logic [31:0] data;
        logic        exc_valid;
        logic [31:0] exc_cause;
        logic [31:0] exc_tval;

        $display("[TEST] invalidate stale prefetched cacheline");
        redirect_to(32'h0000_0080);
        wait_and_accept_instr(pc, data, exc_valid, exc_cause, exc_tval);
        expect_eq32("stale test initial pc", pc, 32'h0000_0080);
        expect_eq32("stale test initial instr", data, make_instr(32));

        data_write_line(32'h0000_0002, make_updated_line(2));
        invalidate_line(32'h0000_0002);
        redirect_to(32'h0000_0080);
        wait_and_accept_instr(pc, data, exc_valid, exc_cause, exc_tval);
        expect_eq32("invalidate refetch pc", pc, 32'h0000_0080);
        expect_eq32("invalidate refetch instr", data, make_updated_instr(32));
        if (exc_valid) begin
            $fatal(1, "[FAIL] unexpected invalidate refetch exception");
        end
        expect_eq32("invalidate refetch cause", exc_cause, 32'h0000_0000);
        expect_eq32("invalidate refetch tval", exc_tval, 32'h0000_0000);

        $display("[PASS] invalidate stale prefetched cacheline");
    endtask

    task automatic run_misaligned_pc_test();
        logic [31:0] pc;
        logic [31:0] data;
        logic        exc_valid;
        logic [31:0] exc_cause;
        logic [31:0] exc_tval;

        $display("[TEST] misaligned PC exception");
        redirect_to(32'h0000_0006);
        wait_and_accept_instr(pc, data, exc_valid, exc_cause, exc_tval);
        expect_eq32("misaligned pc", pc, 32'h0000_0006);
        expect_eq32("misaligned instr", data, 32'h0000_0000);
        if (!exc_valid) begin
            $fatal(1, "[FAIL] misaligned PC did not raise exception");
        end
        expect_eq32("misaligned cause", exc_cause, EXC_INSTR_ADDR_MISALIGNED);
        expect_eq32("misaligned tval", exc_tval, 32'h0000_0006);
    endtask

    task automatic run_fetch_error_test();
        logic [31:0] pc;
        logic [31:0] data;
        logic        exc_valid;
        logic [31:0] exc_cause;
        logic [31:0] exc_tval;

        $display("[TEST] SPM fetch error exception");
        redirect_to(MEM_BYTES[31:0]);
        wait_and_accept_instr(pc, data, exc_valid, exc_cause, exc_tval);
        expect_eq32("fetch error pc", pc, MEM_BYTES[31:0]);
        expect_eq32("fetch error instr", data, 32'h0000_0000);
        if (!exc_valid) begin
            $fatal(1, "[FAIL] fetch error did not raise exception");
        end
        expect_eq32("fetch error cause", exc_cause, EXC_INSTR_ACCESS_FAULT);
        expect_eq32("fetch error tval", exc_tval, MEM_BYTES[31:0]);

        $display("[PASS] SPM fetch error exception");
    endtask

    initial begin
        reset_dut();
        init_instruction_spm();
        run_sequential_fetch_test();
        run_backpressure_test();
        run_redirect_test();
        run_snoop_stall_test();
        run_invalidate_stale_line_test();
        run_misaligned_pc_test();
        run_fetch_error_test();
        $display("[PASS] CPU instruction fetcher tests complete");
        $finish;
    end

endmodule
