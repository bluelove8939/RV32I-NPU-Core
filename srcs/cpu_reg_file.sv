`timescale 1ns/1ps

module cpu_reg_file #(
    parameter int unsigned XLEN = 32,
    parameter int unsigned N_REGS = 32,
    parameter int unsigned REG_ADDR_WIDTH = 5
) (
    input  logic                         clk,
    input  logic                         reset_n,

    input  logic [REG_ADDR_WIDTH-1:0]    raddr0_i,
    output logic [XLEN-1:0]              rdata0_o,
    input  logic [REG_ADDR_WIDTH-1:0]    raddr1_i,
    output logic [XLEN-1:0]              rdata1_o,

    input  logic                         we_i,
    input  logic [REG_ADDR_WIDTH-1:0]    waddr_i,
    input  logic [XLEN-1:0]              wdata_i
);

    logic [XLEN-1:0] regs_q [1:N_REGS-1];

    assign rdata0_o = (raddr0_i == '0) ? '0 : regs_q[raddr0_i];
    assign rdata1_o = (raddr1_i == '0) ? '0 : regs_q[raddr1_i];

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (int unsigned reg_idx = 1; reg_idx < N_REGS; reg_idx++) begin
                regs_q[reg_idx] <= '0;
            end
        end else if (we_i && (waddr_i != '0)) begin
            regs_q[waddr_i] <= wdata_i;
        end
    end

endmodule
