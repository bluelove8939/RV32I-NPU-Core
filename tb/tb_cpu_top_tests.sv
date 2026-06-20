`timescale 1ns/1ps

module tb_cpu_top_tests;

    localparam int unsigned ADDR_WIDTH = 32;
    localparam int unsigned DATA_WIDTH = 32;
    localparam int unsigned LINE_WORDS = 16;
    localparam int unsigned LINE_WIDTH = DATA_WIDTH * LINE_WORDS;
    localparam int unsigned MEM_BYTES = 4096;
    localparam int unsigned N_BANK_GROUPS = 4;
    localparam int unsigned MAX_PROGRAM_WORDS = 1024;
    localparam int unsigned MAX_CYCLES = 5000;

    localparam logic [31:0] HALT_INSTR = 32'h0000_006f;

    logic clk;
    logic reset_n;
    logic cpu_enable;
    logic lsu_flush_valid;
    logic lsu_flush_ready;

    logic                  cpu_i_req_valid;
    logic                  cpu_i_req_ready;
    logic [ADDR_WIDTH-1:0] cpu_i_req_line_addr;
    logic                  cpu_i_resp_valid;
    logic                  cpu_i_resp_ready;
    logic [LINE_WIDTH-1:0] cpu_i_resp_rdata;
    logic                  cpu_i_resp_error;

    logic                  cpu_d_req_valid;
    logic                  cpu_d_req_ready;
    logic                  cpu_d_req_write;
    logic [ADDR_WIDTH-1:0] cpu_d_req_line_addr;
    logic [LINE_WIDTH-1:0] cpu_d_req_wdata;
    logic [LINE_WORDS-1:0] cpu_d_req_wstrb;
    logic                  cpu_d_resp_valid;
    logic                  cpu_d_resp_ready;
    logic [LINE_WIDTH-1:0] cpu_d_resp_rdata;
    logic                  cpu_d_resp_error;

    logic                  preload_active;
    logic                  preload_d_req_valid;
    logic                  preload_d_req_ready;
    logic                  preload_d_req_write;
    logic [ADDR_WIDTH-1:0] preload_d_req_line_addr;
    logic [LINE_WIDTH-1:0] preload_d_req_wdata;
    logic [LINE_WORDS-1:0] preload_d_req_wstrb;
    logic                  preload_d_resp_valid;
    logic                  preload_d_resp_ready;
    logic [LINE_WIDTH-1:0] preload_d_resp_rdata;
    logic                  preload_d_resp_error;

    logic                  bus_d_req_valid;
    logic                  bus_d_req_ready;
    logic                  bus_d_req_write;
    logic [ADDR_WIDTH-1:0] bus_d_req_line_addr;
    logic [LINE_WIDTH-1:0] bus_d_req_wdata;
    logic [LINE_WORDS-1:0] bus_d_req_wstrb;
    logic                  bus_d_resp_valid;
    logic                  bus_d_resp_ready;
    logic [LINE_WIDTH-1:0] bus_d_resp_rdata;
    logic                  bus_d_resp_error;

    logic                  dbg_commit_valid;
    logic [31:0]           dbg_commit_pc;
    logic [31:0]           dbg_commit_instr;
    logic                  dbg_commit_exception;
    logic                  dbg_commit_interrupt;
    logic                  dbg_rf_we;
    logic [4:0]            dbg_rf_waddr;
    logic [31:0]           dbg_rf_wdata;
    logic [31:0]           dbg_fetch_pc;

    logic [31:0] program_words [0:MAX_PROGRAM_WORDS-1];
    int unsigned program_word_count;
    string bin_path;

    cpu_top #(
        .RESET_PC   (32'h0000_0000),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .LINE_WORDS (LINE_WORDS),
        .LINE_WIDTH (LINE_WIDTH)
    ) u_dut (
        .clk                          (clk),
        .reset_n                      (reset_n),
        .cpu_enable_i                 (cpu_enable),
        .software_interrupt_pending_i (1'b0),
        .timer_interrupt_pending_i    (1'b0),
        .external_interrupt_pending_i (1'b0),
        .lsu_flush_valid_i            (lsu_flush_valid),
        .lsu_flush_ready_o            (lsu_flush_ready),
        .i_spm_req_valid_o            (cpu_i_req_valid),
        .i_spm_req_ready_i            (cpu_i_req_ready),
        .i_spm_req_line_addr_o        (cpu_i_req_line_addr),
        .i_spm_resp_valid_i           (cpu_i_resp_valid),
        .i_spm_resp_ready_o           (cpu_i_resp_ready),
        .i_spm_resp_rdata_i           (cpu_i_resp_rdata),
        .i_spm_resp_error_i           (cpu_i_resp_error),
        .d_spm_req_valid_o            (cpu_d_req_valid),
        .d_spm_req_ready_i            (cpu_d_req_ready),
        .d_spm_req_write_o            (cpu_d_req_write),
        .d_spm_req_line_addr_o        (cpu_d_req_line_addr),
        .d_spm_req_wdata_o            (cpu_d_req_wdata),
        .d_spm_req_wstrb_o            (cpu_d_req_wstrb),
        .d_spm_resp_valid_i           (cpu_d_resp_valid),
        .d_spm_resp_ready_o           (cpu_d_resp_ready),
        .d_spm_resp_rdata_i           (cpu_d_resp_rdata),
        .d_spm_resp_error_i           (cpu_d_resp_error),
        .debug_commit_valid_o         (dbg_commit_valid),
        .debug_commit_pc_o            (dbg_commit_pc),
        .debug_commit_instr_o         (dbg_commit_instr),
        .debug_commit_exception_o     (dbg_commit_exception),
        .debug_commit_interrupt_o     (dbg_commit_interrupt),
        .debug_rf_we_o                (dbg_rf_we),
        .debug_rf_waddr_o             (dbg_rf_waddr),
        .debug_rf_wdata_o             (dbg_rf_wdata),
        .debug_fetch_pc_o             (dbg_fetch_pc)
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
        .i_req_valid_i     (cpu_i_req_valid),
        .i_req_ready_o     (cpu_i_req_ready),
        .i_req_line_addr_i (cpu_i_req_line_addr),
        .i_resp_valid_o    (cpu_i_resp_valid),
        .i_resp_ready_i    (cpu_i_resp_ready),
        .i_resp_rdata_o    (cpu_i_resp_rdata),
        .i_resp_error_o    (cpu_i_resp_error),
        .d_req_valid_i     (bus_d_req_valid),
        .d_req_ready_o     (bus_d_req_ready),
        .d_req_write_i     (bus_d_req_write),
        .d_req_line_addr_i (bus_d_req_line_addr),
        .d_req_wdata_i     (bus_d_req_wdata),
        .d_req_wstrb_i     (bus_d_req_wstrb),
        .d_resp_valid_o    (bus_d_resp_valid),
        .d_resp_ready_i    (bus_d_resp_ready),
        .d_resp_rdata_o    (bus_d_resp_rdata),
        .d_resp_error_o    (bus_d_resp_error)
    );

    assign bus_d_req_valid = preload_active ? preload_d_req_valid :
                                              cpu_d_req_valid;
    assign bus_d_req_write = preload_active ? preload_d_req_write :
                                              cpu_d_req_write;
    assign bus_d_req_line_addr = preload_active ? preload_d_req_line_addr :
                                                  cpu_d_req_line_addr;
    assign bus_d_req_wdata = preload_active ? preload_d_req_wdata :
                                              cpu_d_req_wdata;
    assign bus_d_req_wstrb = preload_active ? preload_d_req_wstrb :
                                              cpu_d_req_wstrb;
    assign bus_d_resp_ready = preload_active ? preload_d_resp_ready :
                                               cpu_d_resp_ready;

    assign preload_d_req_ready = preload_active && bus_d_req_ready;
    assign preload_d_resp_valid = preload_active && bus_d_resp_valid;
    assign preload_d_resp_rdata = bus_d_resp_rdata;
    assign preload_d_resp_error = bus_d_resp_error;

    assign cpu_d_req_ready = !preload_active && bus_d_req_ready;
    assign cpu_d_resp_valid = !preload_active && bus_d_resp_valid;
    assign cpu_d_resp_rdata = bus_d_resp_rdata;
    assign cpu_d_resp_error = bus_d_resp_error;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic logic [31:0] get_reg(input int unsigned reg_idx);
        if (reg_idx == 0) begin
            return 32'h0000_0000;
        end
        return u_dut.u_reg_file.regs_q[reg_idx];
    endfunction

    task automatic reset_dut();
        begin
            reset_n = 1'b0;
            cpu_enable = 1'b0;
            lsu_flush_valid = 1'b0;
            preload_active = 1'b0;
            preload_d_req_valid = 1'b0;
            preload_d_req_write = 1'b0;
            preload_d_req_line_addr = '0;
            preload_d_req_wdata = '0;
            preload_d_req_wstrb = '0;
            preload_d_resp_ready = 1'b1;
            repeat (5) @(posedge clk);
            reset_n = 1'b1;
            repeat (2) @(posedge clk);
            #1;
        end
    endtask

    task automatic preload_access_line(
        input  logic                  is_write,
        input  logic [ADDR_WIDTH-1:0] line_addr,
        input  logic [LINE_WIDTH-1:0] wdata,
        output logic [LINE_WIDTH-1:0] rdata
    );
        int unsigned cycles;
        begin
            @(negedge clk);
            preload_active = 1'b1;
            preload_d_req_valid = 1'b1;
            preload_d_req_write = is_write;
            preload_d_req_line_addr = line_addr;
            preload_d_req_wdata = wdata;
            preload_d_req_wstrb = is_write ? '1 : '0;

            cycles = 0;
            while (!preload_d_req_ready) begin
                @(negedge clk);
                cycles++;
                if (cycles > 80) begin
                    $fatal(1, "[FAIL] preload request timeout line=%0d", line_addr);
                end
            end

            @(posedge clk);
            #1;
            preload_d_req_valid = 1'b0;

            cycles = 0;
            while (!preload_d_resp_valid) begin
                @(posedge clk);
                #1;
                cycles++;
                if (cycles > 80) begin
                    $fatal(1, "[FAIL] preload response timeout line=%0d", line_addr);
                end
            end

            if (preload_d_resp_error) begin
                $fatal(1, "[FAIL] preload response error line=%0d", line_addr);
            end

            rdata = preload_d_resp_rdata;
            @(posedge clk);
            #1;
            @(negedge clk);
            preload_active = 1'b0;
        end
    endtask

    task automatic preload_write_line(
        input logic [ADDR_WIDTH-1:0] line_addr,
        input logic [LINE_WIDTH-1:0] line_data
    );
        logic [LINE_WIDTH-1:0] unused_rdata;
        begin
            preload_access_line(1'b1, line_addr, line_data, unused_rdata);
        end
    endtask

    task automatic preload_read_line(
        input  logic [ADDR_WIDTH-1:0] line_addr,
        output logic [LINE_WIDTH-1:0] line_data
    );
        begin
            preload_access_line(1'b0, line_addr, '0, line_data);
        end
    endtask

    task automatic load_program_file(input string path);
        int fd;
        int scan_result;
        logic [31:0] word;
        begin
            for (int unsigned idx = 0; idx < MAX_PROGRAM_WORDS; idx++) begin
                program_words[idx] = 32'h0000_006f;
            end

            program_word_count = 0;
            fd = $fopen(path, "r");
            if (fd == 0) begin
                $fatal(1, "[FAIL] cannot open BIN file: %s", path);
            end

            while (!$feof(fd)) begin
                scan_result = $fscanf(fd, "%h\n", word);
                if (scan_result == 1) begin
                    if (program_word_count >= MAX_PROGRAM_WORDS) begin
                        $fatal(1, "[FAIL] program too large: %s", path);
                    end
                    program_words[program_word_count] = word;
                    program_word_count++;
                end
            end
            $fclose(fd);

            if (program_word_count == 0) begin
                $fatal(1, "[FAIL] empty BIN file: %s", path);
            end
            $display("[LOAD] %s words=%0d", path, program_word_count);
        end
    endtask

    task automatic preload_program();
        int unsigned n_lines;
        logic [LINE_WIDTH-1:0] line_data;
        begin
            n_lines = (program_word_count + LINE_WORDS - 1) / LINE_WORDS;
            for (int unsigned line_idx = 0; line_idx < n_lines; line_idx++) begin
                line_data = '0;
                for (int unsigned word_idx = 0; word_idx < LINE_WORDS; word_idx++) begin
                    line_data[word_idx * DATA_WIDTH +: DATA_WIDTH] =
                        program_words[line_idx * LINE_WORDS + word_idx];
                end
                preload_write_line(line_idx[ADDR_WIDTH-1:0], line_data);
            end
        end
    endtask

    task automatic run_until_halt();
        int unsigned cycles;
        int unsigned halt_count;
        logic [31:0] halt_pc;
        begin
            @(negedge clk);
            cpu_enable = 1'b1;
            cycles = 0;
            halt_count = 0;
            halt_pc = '0;

            while (cycles < MAX_CYCLES) begin
                @(posedge clk);
                #1;
                if (dbg_commit_valid) begin
                    $display("[COMMIT] pc=0x%08x instr=0x%08x rf_we=%0b rd=%0d wdata=0x%08x exc=%0b irq=%0b fetch_pc=0x%08x",
                             dbg_commit_pc,
                             dbg_commit_instr,
                             dbg_rf_we,
                             dbg_rf_waddr,
                             dbg_rf_wdata,
                             dbg_commit_exception,
                             dbg_commit_interrupt,
                             dbg_fetch_pc);

                    if (dbg_commit_instr == HALT_INSTR) begin
                        if ((halt_count != 0) && (halt_pc == dbg_commit_pc)) begin
                            halt_count++;
                        end else begin
                            halt_pc = dbg_commit_pc;
                            halt_count = 1;
                        end
                    end else begin
                        halt_count = 0;
                    end

                    if (halt_count >= 3) begin
                        @(negedge clk);
                        cpu_enable = 1'b0;
                        $display("[HALT] self-loop pc=0x%08x cycles=%0d", halt_pc, cycles);
                        return;
                    end
                end
                cycles++;
            end

            $fatal(1, "[FAIL] timeout waiting for halt after %0d cycles", MAX_CYCLES);
        end
    endtask

    task automatic dump_registers();
        begin
            $display("[REGFILE]");
            for (int unsigned idx = 0; idx < 32; idx++) begin
                $display("x%0d = 0x%08x", idx, get_reg(idx));
            end
        end
    endtask

    task automatic check_signature();
        logic [31:0] data_line;
        logic [31:0] test_id;
        logic [31:0] pass_flag;
        logic [LINE_WIDTH-1:0] line_data;
        logic unused_line_upper;
        begin
            unused_line_upper = 1'b0;
            test_id = get_reg(30);
            pass_flag = get_reg(31);
            if (pass_flag !== 32'h0000_0001) begin
                $fatal(1, "[FAIL] pass signature x31=0x%08x", pass_flag);
            end

            unique case (test_id)
                32'd1: begin
                    if (get_reg(10) !== 32'd34) begin
                        $fatal(1, "[FAIL] t1 expected x10=34 actual=0x%08x", get_reg(10));
                    end
                end
                32'd2: begin
                    if ((get_reg(10) !== 32'd42) || (get_reg(11) !== 32'd43)) begin
                        $fatal(1, "[FAIL] t2 expected x10=42 x11=43 actual x10=0x%08x x11=0x%08x",
                               get_reg(10), get_reg(11));
                    end
                end
                32'd3: begin
                    if ((get_reg(10) !== 32'd3) || (get_reg(11) !== 32'd2)) begin
                        $fatal(1, "[FAIL] t3 expected x10=3 x11=2 actual x10=0x%08x x11=0x%08x",
                               get_reg(10), get_reg(11));
                    end
                end
                32'd4: begin
                    if ((get_reg(10) !== 32'd4) || (get_reg(11) !== 32'd11)) begin
                        $fatal(1, "[FAIL] t4 expected x10=4 x11=11 actual x10=0x%08x x11=0x%08x",
                               get_reg(10), get_reg(11));
                    end
                end
                32'd5: begin
                    preload_read_line(32'd9, line_data);
                    data_line = line_data[0 +: 32];
                    unused_line_upper = ^line_data[LINE_WIDTH-1:32];
                    if ((get_reg(10) !== 32'd123) || (data_line !== 32'd123)) begin
                        $fatal(1, "[FAIL] t5 expected x10=123 mem[0x240]=123 actual x10=0x%08x mem=0x%08x",
                               get_reg(10), data_line);
                    end
                end
                default: begin
                    $fatal(1, "[FAIL] unknown test id x30=0x%08x", test_id);
                end
            endcase

            $display("[PASS] test_id=%0d signature OK", test_id);
            if (unused_line_upper || lsu_flush_ready) begin
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("BIN=%s", bin_path)) begin
            $fatal(1, "[FAIL] missing +BIN=<hex_text_file> argument");
        end

        reset_dut();
        load_program_file(bin_path);
        preload_program();
        run_until_halt();
        dump_registers();
        check_signature();
        $display("[PASS] CPU top program test complete: %s", bin_path);
        $finish;
    end

endmodule
