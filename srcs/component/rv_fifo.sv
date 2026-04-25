`timescale 1ns/1ps

module rv_fifo #(
    parameter int DATA_WIDTH = 32,
    parameter int N_ENTRIES  = 8
) (
    input  logic                   clk,
    input  logic                   reset_n,

    // Write Interface
    input  logic                   wr_enable_i,
    input  logic [DATA_WIDTH-1:0]  wr_data_i,
    output logic                   full_o,

    // Read Interface
    input  logic                   rd_enable_i,
    output logic [DATA_WIDTH-1:0]  rd_data_o,
    output logic                   empty_o,

    // Status
    output logic [$clog2(N_ENTRIES):0] count_o
);

    logic [DATA_WIDTH-1:0] mem [0:N_ENTRIES-1];
    logic [$clog2(N_ENTRIES)-1:0] wr_ptr, rd_ptr;
    logic [$clog2(N_ENTRIES):0]   count;

    assign full_o  = (count == N_ENTRIES);
    assign empty_o = (count == 0);
    assign count_o = count;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wr_ptr  <= '0;
            rd_ptr  <= '0;
            count   <= '0;
            rd_data_o <= '0;
        end else begin
            // Write Logic
            if (wr_enable_i && !full_o) begin
                mem[wr_ptr] <= wr_data_i;
                wr_ptr      <= wr_ptr + 1'b1;
            end

            // Read Logic
            if (rd_enable_i && !empty_o) begin
                rd_data_o <= mem[rd_ptr];
                rd_ptr    <= rd_ptr + 1'b1;
            end

            // Count Update
            case ({wr_enable_i && !full_o, rd_enable_i && !empty_o})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
