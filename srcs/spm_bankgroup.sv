`timescale 1ns/1ps

module spm_bankgroup #(
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned LINE_WORDS = 16,
    parameter int unsigned DEPTH      = 16,
    parameter int unsigned ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter int unsigned LINE_WIDTH = DATA_WIDTH * LINE_WORDS
) (
    input  logic                         clk,
    input  logic                         reset_n,

    input  logic                         i_req_valid_i,
    output logic                         i_req_ready_o,
    input  logic [ADDR_WIDTH-1:0]        i_req_addr_i,
    output logic                         i_resp_valid_o,
    input  logic                         i_resp_ready_i,
    output logic [LINE_WIDTH-1:0]        i_resp_rdata_o,
    output logic                         i_resp_error_o,

    input  logic                         d_req_valid_i,
    output logic                         d_req_ready_o,
    input  logic                         d_req_write_i,
    input  logic [ADDR_WIDTH-1:0]        d_req_addr_i,
    input  logic [LINE_WIDTH-1:0]        d_req_wdata_i,
    input  logic [LINE_WORDS-1:0]        d_req_wstrb_i,
    output logic                         d_resp_valid_o,
    input  logic                         d_resp_ready_i,
    output logic [LINE_WIDTH-1:0]        d_resp_rdata_o,
    output logic                         d_resp_error_o
);

    typedef enum logic {
        MASTER_I = 1'b0,
        MASTER_D = 1'b1
    } master_e;

    logic                         pending_q;
    master_e                      pending_master_q;
    logic                         select_d;
    logic                         fire_req;
    logic                         fire_resp;
    logic [ADDR_WIDTH-1:0]        selected_addr;
    logic                         selected_write;
    logic [LINE_WIDTH-1:0]        selected_wdata;
    logic [LINE_WORDS-1:0]        selected_wstrb;
    logic [LINE_WORDS-1:0]        bank_req_valid;
    logic [LINE_WORDS-1:0]        bank_req_write;
    logic [LINE_WORDS-1:0][DATA_WIDTH-1:0] bank_wdata;
    logic [LINE_WORDS-1:0][DATA_WIDTH-1:0] bank_rdata;
    logic [LINE_WIDTH-1:0]        line_rdata;

    assign select_d = d_req_valid_i;

    assign i_req_ready_o = !pending_q && !d_req_valid_i;
    assign d_req_ready_o = !pending_q;
    assign fire_req = (d_req_valid_i && d_req_ready_o) ||
                      (i_req_valid_i && i_req_ready_o);

    assign selected_addr  = select_d ? d_req_addr_i  : i_req_addr_i;
    assign selected_write = select_d ? d_req_write_i : 1'b0;
    assign selected_wdata = select_d ? d_req_wdata_i : '0;
    assign selected_wstrb = select_d ? d_req_wstrb_i : '0;

    for (genvar bank_idx = 0; bank_idx < LINE_WORDS; bank_idx++) begin : gen_banks
        assign bank_req_valid[bank_idx] = fire_req;
        assign bank_req_write[bank_idx] = selected_write && selected_wstrb[bank_idx];
        assign bank_wdata[bank_idx] =
            selected_wdata[bank_idx*DATA_WIDTH +: DATA_WIDTH];
        assign line_rdata[bank_idx*DATA_WIDTH +: DATA_WIDTH] = bank_rdata[bank_idx];

        spm_bank #(
            .DATA_WIDTH(DATA_WIDTH),
            .DEPTH     (DEPTH),
            .ADDR_WIDTH(ADDR_WIDTH)
        ) u_bank (
            .clk          (clk),
            .reset_n      (reset_n),
            .req_valid_i  (bank_req_valid[bank_idx]),
            .req_write_i  (bank_req_write[bank_idx]),
            .req_addr_i   (selected_addr),
            .req_wdata_i  (bank_wdata[bank_idx]),
            .resp_rdata_o (bank_rdata[bank_idx])
        );
    end

    assign i_resp_valid_o = pending_q && (pending_master_q == MASTER_I);
    assign d_resp_valid_o = pending_q && (pending_master_q == MASTER_D);
    assign i_resp_rdata_o = line_rdata;
    assign d_resp_rdata_o = line_rdata;
    assign i_resp_error_o = 1'b0;
    assign d_resp_error_o = 1'b0;

    assign fire_resp = (i_resp_valid_o && i_resp_ready_i) ||
                       (d_resp_valid_o && d_resp_ready_i);

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pending_q        <= 1'b0;
            pending_master_q <= MASTER_I;
        end else begin
            if (fire_resp) begin
                pending_q <= 1'b0;
            end

            if (fire_req) begin
                pending_q        <= 1'b1;
                pending_master_q <= select_d ? MASTER_D : MASTER_I;
            end
        end
    end

endmodule
