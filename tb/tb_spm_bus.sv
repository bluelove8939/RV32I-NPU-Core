`timescale 1ns/1ps

module tb_spm_bus;

    localparam int unsigned ADDR_WIDTH    = 32;
    localparam int unsigned DATA_WIDTH    = 32;
    localparam int unsigned LINE_WORDS    = 16;
    localparam int unsigned LINE_WIDTH    = DATA_WIDTH * LINE_WORDS;
    localparam int unsigned MEM_BYTES     = 512;
    localparam int unsigned N_BANK_GROUPS = 4;
    localparam int unsigned CACHELINE_BYTES = (DATA_WIDTH / 8) * LINE_WORDS;
    localparam int unsigned NUM_LINES       = MEM_BYTES / CACHELINE_BYTES;

    logic clk;
    logic reset_n;

    logic                  i_req_valid;
    logic                  i_req_ready;
    logic [ADDR_WIDTH-1:0] i_req_line_addr;
    logic                  i_resp_valid;
    logic                  i_resp_ready;
    logic [LINE_WIDTH-1:0] i_resp_rdata;
    logic                  i_resp_error;

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

    int unsigned cycle_count;
    logic monitor_enable;

    spm_bus #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .LINE_WORDS   (LINE_WORDS),
        .MEM_BYTES    (MEM_BYTES),
        .N_BANK_GROUPS(N_BANK_GROUPS),
        .LINE_WIDTH   (LINE_WIDTH)
    ) u_spm_bus (
        .clk                (clk),
        .reset_n            (reset_n),
        .i_req_valid_i      (i_req_valid),
        .i_req_ready_o      (i_req_ready),
        .i_req_line_addr_i  (i_req_line_addr),
        .i_resp_valid_o     (i_resp_valid),
        .i_resp_ready_i     (i_resp_ready),
        .i_resp_rdata_o     (i_resp_rdata),
        .i_resp_error_o     (i_resp_error),
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

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cycle_count   <= 0;
            monitor_enable <= 1'b0;
        end else begin
            cycle_count   <= cycle_count + 1;
            monitor_enable <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (monitor_enable) begin
            $strobe(
                "[cycle %4d] I_REQ v=%0b r=%0b line=0x%08h | D_REQ v=%0b r=%0b wr=%0b line=0x%08h | I_RESP v=%0b first=0x%08h err=%0b | D_RESP v=%0b first=0x%08h err=%0b",
                cycle_count,
                i_req_valid, i_req_ready, i_req_line_addr,
                d_req_valid, d_req_ready, d_req_write, d_req_line_addr,
                i_resp_valid, i_resp_rdata[31:0], i_resp_error,
                d_resp_valid, d_resp_rdata[31:0], d_resp_error
            );
        end
    end

    function automatic logic [LINE_WIDTH-1:0] make_addr_pattern_line(
        input int unsigned line_addr
    );
        logic [LINE_WIDTH-1:0] line;
        int unsigned byte_addr;
        begin
            line = '0;
            for (int unsigned word_idx = 0; word_idx < LINE_WORDS; word_idx++) begin
                byte_addr = (line_addr * CACHELINE_BYTES) + (word_idx * 4);
                line[word_idx*DATA_WIDTH +: DATA_WIDTH] = {
                    8'(byte_addr + 3),
                    8'(byte_addr + 2),
                    8'(byte_addr + 1),
                    8'(byte_addr + 0)
                };
            end
            return line;
        end
    endfunction

    task automatic reset_dut;
        begin
            reset_n         = 1'b0;
            i_req_valid     = 1'b0;
            i_req_line_addr = '0;
            i_resp_ready    = 1'b1;
            d_req_valid     = 1'b0;
            d_req_write     = 1'b0;
            d_req_line_addr = '0;
            d_req_wdata     = '0;
            d_req_wstrb     = '0;
            d_resp_ready    = 1'b1;

            repeat (4) @(posedge clk);
            reset_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic data_line_access(
        input  logic [ADDR_WIDTH-1:0] line_addr,
        input  logic                  write,
        input  logic [LINE_WIDTH-1:0] wdata,
        input  logic [LINE_WORDS-1:0] wstrb,
        output logic [LINE_WIDTH-1:0] rdata,
        output logic                  error
    );
        int unsigned timeout_count;
        begin
            timeout_count = 0;

            @(negedge clk);
            d_req_valid     = 1'b1;
            d_req_write     = write;
            d_req_line_addr = line_addr;
            d_req_wdata     = wdata;
            d_req_wstrb     = wstrb;

            do begin
                @(posedge clk);
                #1;
                timeout_count++;
                if (timeout_count > 20) begin
                    $fatal(1, "[test] data response timeout at line=0x%08h", line_addr);
                end
            end while (!d_resp_valid);

            rdata = d_resp_rdata;
            error = d_resp_error;

            @(negedge clk);
            d_req_valid = 1'b0;
            d_req_write = 1'b0;
            d_req_wdata = '0;
            d_req_wstrb = '0;
        end
    endtask

    task automatic init_spm_addr_pattern;
        logic [LINE_WIDTH-1:0] rdata;
        logic error;
        begin
            $display("[init] initializing SPM with cacheline writes");

            for (int unsigned line_addr = 0; line_addr < NUM_LINES; line_addr++) begin
                data_line_access(
                    line_addr[ADDR_WIDTH-1:0],
                    1'b1,
                    make_addr_pattern_line(line_addr),
                    {LINE_WORDS{1'b1}},
                    rdata,
                    error
                );

                if (error) begin
                    $fatal(1, "[init] write error at line=0x%08h", line_addr);
                end

                if (rdata === {LINE_WIDTH{1'bx}}) begin
                    $fatal(1, "[init] unknown write response at line=0x%08h", line_addr);
                end
            end

            $display("[init] SPM initialized from byte address 0x0000 to 0x%04h", MEM_BYTES - 1);
        end
    endtask

    task automatic run_concurrent_fetch_test;
        localparam int unsigned TOTAL_REQS = 4;
        logic [LINE_WIDTH-1:0] expected_i [0:TOTAL_REQS-1];
        logic [LINE_WIDTH-1:0] expected_d [0:TOTAL_REQS-1];
        int unsigned i_issue_count;
        int unsigned d_issue_count;
        int unsigned i_resp_count;
        int unsigned d_resp_count;
        int unsigned timeout_count;
        begin
            $display("[test] concurrent cacheline fetch start");
            $display("[test] instruction line range: 0 to 3");
            $display("[test] data line range       : 1 to 4");

            for (int unsigned idx = 0; idx < TOTAL_REQS; idx++) begin
                expected_i[idx] = make_addr_pattern_line(idx);
                expected_d[idx] = make_addr_pattern_line(idx + 1);
            end

            i_issue_count = 0;
            d_issue_count = 0;
            i_resp_count  = 0;
            d_resp_count  = 0;
            timeout_count = 0;

            @(negedge clk);
            i_req_valid     = 1'b1;
            i_req_line_addr = 0;
            d_req_valid     = 1'b1;
            d_req_write     = 1'b0;
            d_req_line_addr = 1;
            d_req_wdata     = '0;
            d_req_wstrb     = '0;

            while ((i_resp_count < TOTAL_REQS) || (d_resp_count < TOTAL_REQS)) begin
                @(posedge clk);
                #1;
                timeout_count++;

                if (i_resp_valid && i_resp_ready) begin
                    if (i_resp_error || (i_resp_rdata != expected_i[i_resp_count])) begin
                        $fatal(1, "[test] instruction line mismatch idx=%0d err=%0b",
                               i_resp_count, i_resp_error);
                    end
                    i_resp_count++;
                end

                if (d_resp_valid && d_resp_ready) begin
                    if (d_resp_error || (d_resp_rdata != expected_d[d_resp_count])) begin
                        $fatal(1, "[test] data line mismatch idx=%0d err=%0b",
                               d_resp_count, d_resp_error);
                    end
                    d_resp_count++;
                end

                @(negedge clk);

                if (i_req_valid && i_req_ready) begin
                    i_issue_count++;
                    if (i_issue_count < TOTAL_REQS) begin
                        i_req_line_addr = i_issue_count;
                    end else begin
                        i_req_valid = 1'b0;
                    end
                end

                if (d_req_valid && d_req_ready) begin
                    d_issue_count++;
                    if (d_issue_count < TOTAL_REQS) begin
                        d_req_line_addr = d_issue_count + 1;
                    end else begin
                        d_req_valid = 1'b0;
                    end
                end

                if (timeout_count > 100) begin
                    $fatal(1, "[test] concurrent fetch timeout: i=%0d/%0d d=%0d/%0d",
                           i_resp_count, TOTAL_REQS, d_resp_count, TOTAL_REQS);
                end
            end

            @(negedge clk);
            i_req_valid = 1'b0;
            d_req_valid = 1'b0;
            d_req_write = 1'b0;
            d_req_wdata = '0;
            d_req_wstrb = '0;

            repeat (2) @(posedge clk);
            $display("[test] concurrent cacheline fetch complete: instruction=%0d data=%0d",
                     i_resp_count, d_resp_count);
        end
    endtask

    task automatic run_same_bankgroup_priority_test;
        logic [LINE_WIDTH-1:0] expected_i;
        logic [LINE_WIDTH-1:0] expected_d;
        begin
            $display("[test] same-bankgroup fixed-priority arbitration start");
            expected_i = make_addr_pattern_line(0);
            expected_d = make_addr_pattern_line(4);

            @(negedge clk);
            i_req_valid     = 1'b1;
            i_req_line_addr = 0;
            d_req_valid     = 1'b1;
            d_req_write     = 1'b0;
            d_req_line_addr = 4;
            d_req_wdata     = '0;
            d_req_wstrb     = '0;

            @(posedge clk);
            #1;

            if (!d_resp_valid || i_resp_valid) begin
                $fatal(1, "[test] expected D response first and I stall for same bank group");
            end

            if (d_resp_error || (d_resp_rdata != expected_d)) begin
                $fatal(1, "[test] same-bankgroup D response mismatch");
            end

            @(negedge clk);
            d_req_valid = 1'b0;

            @(posedge clk);
            #1;

            if (!i_resp_valid) begin
                @(posedge clk);
                #1;
            end

            if (!i_resp_valid) begin
                $fatal(1, "[test] expected I response after D request is removed");
            end

            if (i_resp_error || (i_resp_rdata != expected_i)) begin
                $fatal(1, "[test] same-bankgroup I response mismatch");
            end

            @(negedge clk);
            i_req_valid = 1'b0;

            repeat (2) @(posedge clk);
            $display("[test] same-bankgroup fixed-priority arbitration complete");
        end
    endtask

    task automatic run_spm_zero_write_readback_test;
        logic [LINE_WIDTH-1:0] rdata;
        logic error;
        begin
            $display("[test] SPM zero cacheline write/readback start");

            for (int unsigned line_addr = 0; line_addr < 4; line_addr++) begin
                data_line_access(
                    line_addr[ADDR_WIDTH-1:0],
                    1'b1,
                    '0,
                    {LINE_WORDS{1'b1}},
                    rdata,
                    error
                );

                if (error) begin
                    $fatal(1, "[test] zero write error at line=0x%08h", line_addr);
                end
                $display("[write] line=0x%08h data=ZERO", line_addr);
            end

            for (int unsigned line_addr = 0; line_addr < 4; line_addr++) begin
                data_line_access(
                    line_addr[ADDR_WIDTH-1:0],
                    1'b0,
                    '0,
                    '0,
                    rdata,
                    error
                );

                $display("[read ] line=0x%08h first_word=0x%08h err=%0b",
                         line_addr, rdata[31:0], error);

                if (error || (rdata != '0)) begin
                    $fatal(1, "[test] zero readback mismatch at line=0x%08h", line_addr);
                end
            end

            $display("[test] SPM zero cacheline write/readback complete");
        end
    endtask

    task automatic run_bankgroup_parallel_test;
        logic [LINE_WIDTH-1:0] expected_i;
        logic [LINE_WIDTH-1:0] expected_d;
        begin
            $display("[test] different-bankgroup parallel request start");
            expected_i = make_addr_pattern_line(4);
            expected_d = make_addr_pattern_line(5);

            @(negedge clk);
            i_req_valid     = 1'b1;
            i_req_line_addr = 4;
            d_req_valid     = 1'b1;
            d_req_write     = 1'b0;
            d_req_line_addr = 5;
            d_req_wdata     = '0;
            d_req_wstrb     = '0;

            @(posedge clk);
            #1;

            if (!i_resp_valid || !d_resp_valid) begin
                $fatal(1, "[test] expected simultaneous I/D responses from different bank groups");
            end

            if (i_resp_error || (i_resp_rdata != expected_i)) begin
                $fatal(1, "[test] parallel instruction response mismatch");
            end

            if (d_resp_error || (d_resp_rdata != expected_d)) begin
                $fatal(1, "[test] parallel data response mismatch");
            end

            @(negedge clk);
            i_req_valid = 1'b0;
            d_req_valid = 1'b0;

            repeat (2) @(posedge clk);
            $display("[test] different-bankgroup parallel request complete");
        end
    endtask

    initial begin
        reset_dut();
        init_spm_addr_pattern();
        run_concurrent_fetch_test();
        run_same_bankgroup_priority_test();
        run_spm_zero_write_readback_test();
        run_bankgroup_parallel_test();
        $finish;
    end

endmodule
