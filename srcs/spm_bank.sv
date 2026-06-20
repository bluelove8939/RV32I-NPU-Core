`timescale 1ns/1ps

module spm_bank #(
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned DEPTH      = 16,
    parameter int unsigned ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic                  clk,
    input  logic                  reset_n,

    input  logic                  req_valid_i,
    input  logic                  req_write_i,
    input  logic [ADDR_WIDTH-1:0] req_addr_i,
    input  logic [DATA_WIDTH-1:0] req_wdata_i,

    output logic [DATA_WIDTH-1:0] resp_rdata_o
);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            resp_rdata_o <= '0;
        end else if (req_valid_i) begin
            resp_rdata_o <= mem[req_addr_i];

            if (req_write_i) begin
                mem[req_addr_i] <= req_wdata_i;
            end
        end
    end

endmodule
