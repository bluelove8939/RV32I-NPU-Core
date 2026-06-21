`timescale 1ns/1ps

module cpu_elf_harness_top #(
    parameter int unsigned ADDR_WIDTH    = 32,
    parameter int unsigned DATA_WIDTH    = 32,
    parameter int unsigned LINE_WORDS    = 16,
    parameter int unsigned LINE_WIDTH    = DATA_WIDTH * LINE_WORDS,
    parameter logic [ADDR_WIDTH-1:0] SPM_BASE_ADDR = 32'h8000_0000,
    parameter int unsigned MEM_BYTES     = 1048576,
    parameter int unsigned N_BANK_GROUPS = 4
) (
    input  logic                  clk,
    input  logic                  reset_n,
    input  logic                  cpu_enable_i,

    input  logic                  software_interrupt_pending_i,
    input  logic                  timer_interrupt_pending_i,
    input  logic                  external_interrupt_pending_i,

    input  logic                  preload_req_valid_i,
    output logic                  preload_req_ready_o,
    input  logic [ADDR_WIDTH-1:0] preload_req_line_addr_i,
    input  logic [LINE_WIDTH-1:0] preload_req_wdata_i,
    output logic                  preload_resp_valid_o,
    input  logic                  preload_resp_ready_i,
    output logic                  preload_resp_error_o,

    output logic                  debug_commit_valid_o,
    output logic [31:0]           debug_commit_pc_o,
    output logic [31:0]           debug_commit_instr_o,
    output logic                  debug_commit_exception_o,
    output logic                  debug_commit_interrupt_o,
    output logic                  debug_rf_we_o,
    output logic [4:0]            debug_rf_waddr_o,
    output logic [31:0]           debug_rf_wdata_o,
    output logic [31:0]           debug_fetch_pc_o,

    input  logic [ADDR_WIDTH-1:0] host_tohost_addr_i,
    output logic                  host_tohost_valid_o,
    output logic [DATA_WIDTH-1:0] host_tohost_value_o,

    input  logic [ADDR_WIDTH-1:0] host_console_addr_i,
    output logic                  host_console_valid_o,
    output logic [7:0]            host_console_char_o
);

    localparam int unsigned DATA_BYTES       = DATA_WIDTH / 8;
    localparam int unsigned CACHELINE_BYTES  = DATA_BYTES * LINE_WORDS;
    localparam int unsigned LINE_OFFSET_BITS = $clog2(CACHELINE_BYTES);
    localparam int unsigned WORD_OFFSET_BITS = $clog2(LINE_WORDS);

    logic                  lsu_flush_ready;

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

    logic                  preload_active;
    logic                  preload_active_q;
    logic                  preload_req_fire;
    logic                  preload_resp_fire;
    logic [ADDR_WIDTH-1:0] host_tohost_line_addr;
    logic [WORD_OFFSET_BITS-1:0] host_tohost_word_idx;
    logic                  host_tohost_write_hit;
    logic [DATA_WIDTH-1:0] host_tohost_write_value;
    logic [ADDR_WIDTH-1:0] host_console_line_addr;
    logic [WORD_OFFSET_BITS-1:0] host_console_word_idx;
    logic                  host_console_write_hit;
    logic [7:0]            host_console_write_char;

    assign preload_active = preload_active_q || preload_req_valid_i;
    assign preload_req_fire = preload_req_valid_i && preload_req_ready_o;
    assign preload_resp_fire = preload_resp_valid_o && preload_resp_ready_i;
    assign host_tohost_line_addr = host_tohost_addr_i >> LINE_OFFSET_BITS;
    assign host_tohost_word_idx =
        host_tohost_addr_i[2 +: WORD_OFFSET_BITS];
    assign host_console_line_addr = host_console_addr_i >> LINE_OFFSET_BITS;
    assign host_console_word_idx =
        host_console_addr_i[2 +: WORD_OFFSET_BITS];

    cpu_top #(
        .RESET_PC   (SPM_BASE_ADDR),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .LINE_WORDS (LINE_WORDS),
        .LINE_WIDTH (LINE_WIDTH)
    ) u_dut (
        .clk                          (clk),
        .reset_n                      (reset_n),
        .cpu_enable_i                 (cpu_enable_i),
        .software_interrupt_pending_i (software_interrupt_pending_i),
        .timer_interrupt_pending_i    (timer_interrupt_pending_i),
        .external_interrupt_pending_i (external_interrupt_pending_i),
        .lsu_flush_valid_i            (1'b0),
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
        .debug_commit_valid_o         (debug_commit_valid_o),
        .debug_commit_pc_o            (debug_commit_pc_o),
        .debug_commit_instr_o         (debug_commit_instr_o),
        .debug_commit_exception_o     (debug_commit_exception_o),
        .debug_commit_interrupt_o     (debug_commit_interrupt_o),
        .debug_rf_we_o                (debug_rf_we_o),
        .debug_rf_waddr_o             (debug_rf_waddr_o),
        .debug_rf_wdata_o             (debug_rf_wdata_o),
        .debug_fetch_pc_o             (debug_fetch_pc_o)
    );

    spm_bus #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .LINE_WORDS    (LINE_WORDS),
        .BASE_ADDR     (SPM_BASE_ADDR),
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

    assign bus_d_req_valid = preload_active ? preload_req_valid_i :
                                              cpu_d_req_valid;
    assign bus_d_req_write = preload_active ? 1'b1 : cpu_d_req_write;
    assign bus_d_req_line_addr = preload_active ? preload_req_line_addr_i :
                                                  cpu_d_req_line_addr;
    assign bus_d_req_wdata = preload_active ? preload_req_wdata_i :
                                              cpu_d_req_wdata;
    assign bus_d_req_wstrb = preload_active ? '1 : cpu_d_req_wstrb;
    assign bus_d_resp_ready = preload_active ? preload_resp_ready_i :
                                               cpu_d_resp_ready;

    assign preload_req_ready_o = preload_active && bus_d_req_ready;
    assign preload_resp_valid_o = preload_active && bus_d_resp_valid;
    assign preload_resp_error_o = preload_active && bus_d_resp_error;

    assign cpu_d_req_ready = !preload_active && bus_d_req_ready;
    assign cpu_d_resp_valid = !preload_active && bus_d_resp_valid;
    assign cpu_d_resp_rdata = bus_d_resp_rdata;
    assign cpu_d_resp_error = bus_d_resp_error;

    always_comb begin
        if (lsu_flush_ready) begin
        end
    end

    always_comb begin
        host_tohost_write_hit = 1'b0;
        host_tohost_write_value = '0;
        host_console_write_hit = 1'b0;
        host_console_write_char = '0;

        if (bus_d_req_valid && bus_d_req_ready && bus_d_req_write &&
            (bus_d_req_line_addr == host_tohost_line_addr)) begin
            for (int unsigned word_idx = 0; word_idx < LINE_WORDS;
                 word_idx++) begin
                if ((host_tohost_word_idx == word_idx[WORD_OFFSET_BITS-1:0]) &&
                    bus_d_req_wstrb[word_idx]) begin
                    host_tohost_write_hit = 1'b1;
                    host_tohost_write_value =
                        bus_d_req_wdata[word_idx * DATA_WIDTH +: DATA_WIDTH];
                end
            end
        end

        if (bus_d_req_valid && bus_d_req_ready && bus_d_req_write &&
            (bus_d_req_line_addr == host_console_line_addr)) begin
            for (int unsigned word_idx = 0; word_idx < LINE_WORDS;
                 word_idx++) begin
                if ((host_console_word_idx ==
                     word_idx[WORD_OFFSET_BITS-1:0]) &&
                    bus_d_req_wstrb[word_idx]) begin
                    host_console_write_hit = 1'b1;
                    host_console_write_char =
                        bus_d_req_wdata[word_idx * DATA_WIDTH +: 8];
                end
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            preload_active_q <= 1'b0;
            host_tohost_valid_o <= 1'b0;
            host_tohost_value_o <= '0;
            host_console_valid_o <= 1'b0;
            host_console_char_o <= '0;
        end else begin
            host_tohost_valid_o <= host_tohost_write_hit;
            if (host_tohost_write_hit) begin
                host_tohost_value_o <= host_tohost_write_value;
            end

            host_console_valid_o <= host_console_write_hit;
            if (host_console_write_hit) begin
                host_console_char_o <= host_console_write_char;
            end

            if (preload_resp_fire) begin
                preload_active_q <= 1'b0;
            end

            if (preload_req_fire) begin
                preload_active_q <= 1'b1;
            end
        end
    end

endmodule
