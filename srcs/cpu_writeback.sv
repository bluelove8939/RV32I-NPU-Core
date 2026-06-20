`timescale 1ns/1ps

module cpu_writeback (
    input  logic        wb_valid_i,
    input  logic [4:0]  rd_addr_i,
    input  logic        rd_write_i,
    input  logic [2:0]  wb_sel_i,
    input  logic [31:0] alu_result_i,
    input  logic [31:0] load_data_i,
    input  logic [31:0] csr_rdata_i,
    input  logic [31:0] pc_plus4_i,
    input  logic        exception_valid_i,

    output logic        rf_we_o,
    output logic [4:0]  rf_waddr_o,
    output logic [31:0] rf_wdata_o,
    output logic [31:0] wb_data_o
);

    localparam logic [2:0] WB_ALU  = 3'd0;
    localparam logic [2:0] WB_LOAD = 3'd1;
    localparam logic [2:0] WB_CSR  = 3'd2;
    localparam logic [2:0] WB_PC4  = 3'd3;

    always_comb begin
        unique case (wb_sel_i)
            WB_ALU:  wb_data_o = alu_result_i;
            WB_LOAD: wb_data_o = load_data_i;
            WB_CSR:  wb_data_o = csr_rdata_i;
            WB_PC4:  wb_data_o = pc_plus4_i;
            default: wb_data_o = alu_result_i;
        endcase
    end

    assign rf_we_o = wb_valid_i &&
                     rd_write_i &&
                     (rd_addr_i != 5'd0) &&
                     !exception_valid_i;
    assign rf_waddr_o = rd_addr_i;
    assign rf_wdata_o = wb_data_o;

endmodule
