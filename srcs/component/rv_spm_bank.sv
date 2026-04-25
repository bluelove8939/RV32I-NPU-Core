`timescale 1ns/1ps

module rv_spm_bank #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 10
) (
    input  logic                   clk,
    input  logic                   reset_n,
    
    // Memory Interface
    input  logic [ADDR_WIDTH-1:0]  addr_i,
    input  logic                   wr_enable_i,
    input  logic [DATA_WIDTH-1:0]  wr_data_i,
    output logic [DATA_WIDTH-1:0]  rd_data_o
);

    // Memory Array
    logic [DATA_WIDTH-1:0] mem [0:(2**ADDR_WIDTH)-1];

    // Synchronous Read/Write
    always_ff @(posedge clk) begin
        if (wr_enable_i) begin
            mem[addr_i] <= wr_data_i;
        end
        rd_data_o <= mem[addr_i];
    end

endmodule
