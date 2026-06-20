`timescale 1ns/1ps

module spm_bus #(
    parameter int unsigned ADDR_WIDTH    = 32,
    parameter int unsigned DATA_WIDTH    = 32,
    parameter int unsigned LINE_WORDS    = 16,
    parameter int unsigned MEM_BYTES     = 4096,
    parameter int unsigned N_BANK_GROUPS = 4,
    parameter int unsigned LINE_WIDTH    = DATA_WIDTH * LINE_WORDS
) (
    input  logic                  clk,
    input  logic                  reset_n,

    input  logic                  i_req_valid_i,
    output logic                  i_req_ready_o,
    input  logic [ADDR_WIDTH-1:0] i_req_line_addr_i,
    output logic                  i_resp_valid_o,
    input  logic                  i_resp_ready_i,
    output logic [LINE_WIDTH-1:0] i_resp_rdata_o,
    output logic                  i_resp_error_o,

    input  logic                  d_req_valid_i,
    output logic                  d_req_ready_o,
    input  logic                  d_req_write_i,
    input  logic [ADDR_WIDTH-1:0] d_req_line_addr_i,
    input  logic [LINE_WIDTH-1:0] d_req_wdata_i,
    input  logic [LINE_WORDS-1:0] d_req_wstrb_i,
    output logic                  d_resp_valid_o,
    input  logic                  d_resp_ready_i,
    output logic [LINE_WIDTH-1:0] d_resp_rdata_o,
    output logic                  d_resp_error_o
);

    localparam int unsigned CACHELINE_BYTES = (DATA_WIDTH / 8) * LINE_WORDS;
    localparam int unsigned NUM_LINES       = MEM_BYTES / CACHELINE_BYTES;
    localparam int unsigned GROUP_BITS      = (N_BANK_GROUPS <= 1) ? 1 : $clog2(N_BANK_GROUPS);
    localparam int unsigned GROUP_SHIFT     = (N_BANK_GROUPS <= 1) ? 0 : $clog2(N_BANK_GROUPS);
    localparam int unsigned GROUP_DEPTH     = (NUM_LINES + N_BANK_GROUPS - 1) / N_BANK_GROUPS;
    localparam int unsigned ROW_BITS        = (GROUP_DEPTH <= 1) ? 1 : $clog2(GROUP_DEPTH);

    logic [N_BANK_GROUPS-1:0]                  bg_i_req_valid;
    logic [N_BANK_GROUPS-1:0]                  bg_i_req_ready;
    logic [N_BANK_GROUPS-1:0][ROW_BITS-1:0]    bg_i_req_addr;
    logic [N_BANK_GROUPS-1:0]                  bg_i_resp_valid;
    logic [N_BANK_GROUPS-1:0]                  bg_i_resp_ready;
    logic [N_BANK_GROUPS-1:0][LINE_WIDTH-1:0]  bg_i_resp_rdata;
    logic [N_BANK_GROUPS-1:0]                  bg_i_resp_error;

    logic [N_BANK_GROUPS-1:0]                  bg_d_req_valid;
    logic [N_BANK_GROUPS-1:0]                  bg_d_req_ready;
    logic [N_BANK_GROUPS-1:0]                  bg_d_req_write;
    logic [N_BANK_GROUPS-1:0][ROW_BITS-1:0]    bg_d_req_addr;
    logic [N_BANK_GROUPS-1:0][LINE_WIDTH-1:0]  bg_d_req_wdata;
    logic [N_BANK_GROUPS-1:0][LINE_WORDS-1:0]  bg_d_req_wstrb;
    logic [N_BANK_GROUPS-1:0]                  bg_d_resp_valid;
    logic [N_BANK_GROUPS-1:0]                  bg_d_resp_ready;
    logic [N_BANK_GROUPS-1:0][LINE_WIDTH-1:0]  bg_d_resp_rdata;
    logic [N_BANK_GROUPS-1:0]                  bg_d_resp_error;

    logic [GROUP_BITS-1:0] i_group_idx;
    logic [GROUP_BITS-1:0] d_group_idx;
    logic [ROW_BITS-1:0]   i_row_addr;
    logic [ROW_BITS-1:0]   d_row_addr;
    logic                  i_in_range;
    logic                  d_in_range;
    logic                  i_error_pending_q;
    logic                  d_error_pending_q;

    assign i_group_idx = (N_BANK_GROUPS <= 1) ? '0 :
        i_req_line_addr_i[GROUP_BITS-1:0];
    assign d_group_idx = (N_BANK_GROUPS <= 1) ? '0 :
        d_req_line_addr_i[GROUP_BITS-1:0];
    assign i_in_range = (i_req_line_addr_i < NUM_LINES);
    assign d_in_range = (d_req_line_addr_i < NUM_LINES);

    always_comb begin
        i_row_addr = '0;
        d_row_addr = '0;
        for (int unsigned bit_idx = 0; bit_idx < ROW_BITS; bit_idx++) begin
            i_row_addr[bit_idx] = i_req_line_addr_i[bit_idx + GROUP_SHIFT];
            d_row_addr[bit_idx] = d_req_line_addr_i[bit_idx + GROUP_SHIFT];
        end
    end

    always_comb begin
        bg_i_req_valid = '0;
        bg_i_req_addr  = '0;
        bg_d_req_valid = '0;
        bg_d_req_write = '0;
        bg_d_req_addr  = '0;
        bg_d_req_wdata = '0;
        bg_d_req_wstrb = '0;

        if (i_req_valid_i && i_in_range) begin
            bg_i_req_valid[i_group_idx] = 1'b1;
            bg_i_req_addr[i_group_idx]  = i_row_addr;
        end

        if (d_req_valid_i && d_in_range) begin
            bg_d_req_valid[d_group_idx] = 1'b1;
            bg_d_req_write[d_group_idx] = d_req_write_i;
            bg_d_req_addr[d_group_idx]  = d_row_addr;
            bg_d_req_wdata[d_group_idx] = d_req_wdata_i;
            bg_d_req_wstrb[d_group_idx] = d_req_wstrb_i;
        end
    end

    assign i_req_ready_o = i_in_range ? bg_i_req_ready[i_group_idx] :
                                        !i_error_pending_q;
    assign d_req_ready_o = d_in_range ? bg_d_req_ready[d_group_idx] :
                                        !d_error_pending_q;

    always_comb begin
        i_resp_valid_o = i_error_pending_q;
        i_resp_rdata_o = '0;
        i_resp_error_o = i_error_pending_q;
        d_resp_valid_o = d_error_pending_q;
        d_resp_rdata_o = '0;
        d_resp_error_o = d_error_pending_q;

        bg_i_resp_ready = '0;
        bg_d_resp_ready = '0;

        for (int unsigned group_idx = 0; group_idx < N_BANK_GROUPS; group_idx++) begin
            if (bg_i_resp_valid[group_idx]) begin
                i_resp_valid_o = 1'b1;
                i_resp_rdata_o = bg_i_resp_rdata[group_idx];
                i_resp_error_o = bg_i_resp_error[group_idx];
                bg_i_resp_ready[group_idx] = i_resp_ready_i;
            end

            if (bg_d_resp_valid[group_idx]) begin
                d_resp_valid_o = 1'b1;
                d_resp_rdata_o = bg_d_resp_rdata[group_idx];
                d_resp_error_o = bg_d_resp_error[group_idx];
                bg_d_resp_ready[group_idx] = d_resp_ready_i;
            end
        end
    end

    for (genvar group_idx = 0; group_idx < N_BANK_GROUPS; group_idx++) begin : gen_bankgroups
        spm_bankgroup #(
            .DATA_WIDTH(DATA_WIDTH),
            .LINE_WORDS(LINE_WORDS),
            .DEPTH     (GROUP_DEPTH),
            .ADDR_WIDTH(ROW_BITS),
            .LINE_WIDTH(LINE_WIDTH)
        ) u_bankgroup (
            .clk            (clk),
            .reset_n        (reset_n),
            .i_req_valid_i  (bg_i_req_valid[group_idx]),
            .i_req_ready_o  (bg_i_req_ready[group_idx]),
            .i_req_addr_i   (bg_i_req_addr[group_idx]),
            .i_resp_valid_o (bg_i_resp_valid[group_idx]),
            .i_resp_ready_i (bg_i_resp_ready[group_idx]),
            .i_resp_rdata_o (bg_i_resp_rdata[group_idx]),
            .i_resp_error_o (bg_i_resp_error[group_idx]),
            .d_req_valid_i  (bg_d_req_valid[group_idx]),
            .d_req_ready_o  (bg_d_req_ready[group_idx]),
            .d_req_write_i  (bg_d_req_write[group_idx]),
            .d_req_addr_i   (bg_d_req_addr[group_idx]),
            .d_req_wdata_i  (bg_d_req_wdata[group_idx]),
            .d_req_wstrb_i  (bg_d_req_wstrb[group_idx]),
            .d_resp_valid_o (bg_d_resp_valid[group_idx]),
            .d_resp_ready_i (bg_d_resp_ready[group_idx]),
            .d_resp_rdata_o (bg_d_resp_rdata[group_idx]),
            .d_resp_error_o (bg_d_resp_error[group_idx])
        );
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            i_error_pending_q <= 1'b0;
            d_error_pending_q <= 1'b0;
        end else begin
            if (i_error_pending_q && i_resp_ready_i) begin
                i_error_pending_q <= 1'b0;
            end

            if (d_error_pending_q && d_resp_ready_i) begin
                d_error_pending_q <= 1'b0;
            end

            if (i_req_valid_i && i_req_ready_o && !i_in_range) begin
                i_error_pending_q <= 1'b1;
            end

            if (d_req_valid_i && d_req_ready_o && !d_in_range) begin
                d_error_pending_q <= 1'b1;
            end
        end
    end

endmodule
