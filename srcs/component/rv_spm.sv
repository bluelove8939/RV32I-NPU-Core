`timescale 1ns/1ps

module rv_spm #(
    parameter int N_AGENTS        = 4,
    parameter int BANK_DATA_WIDTH = 8,
    parameter int BANK_ADDR_WIDTH = 13,
    parameter int N_BANKS         = 128,
    parameter int ADDR_WIDTH      = BANK_ADDR_WIDTH + $clog2(N_BANKS)
) (
    input  logic clk,
    input  logic reset_n,

    // Agent Interfaces
    input  logic [N_AGENTS-1:0]                              agent_req_i,
    input  logic [N_AGENTS-1:0][ADDR_WIDTH-1:0]              agent_addr_i,
    input  logic [N_AGENTS-1:0]                              agent_wr_enable_i,
    input  logic [N_AGENTS-1:0][N_BANKS*BANK_DATA_WIDTH-1:0] agent_wr_data_i,
    output logic [N_AGENTS-1:0]                              agent_ready_o, // High if request is granted this cycle

    output logic [N_AGENTS-1:0]                              agent_rd_data_vld_o,
    output logic [N_AGENTS-1:0][N_BANKS*BANK_DATA_WIDTH-1:0] agent_rd_data_o
);

    localparam int BLOCK_DATA_WIDTH = N_BANKS * BANK_DATA_WIDTH;

    // 1. Round-Robin Arbiter (Combinational)
    logic [N_AGENTS-1:0]         gnt_vec;
    logic [$clog2(N_AGENTS)-1:0] last_gnt_agent;
    int                          arb_idx; // Declared outside to avoid IMPLICITSTATIC

    // Maintain fairness by tracking the last granted agent
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            last_gnt_agent <= '0;
        end else if (|gnt_vec) begin
            for (int i = 0; i < N_AGENTS; i++) begin
                if (gnt_vec[i]) last_gnt_agent <= i[$clog2(N_AGENTS)-1:0];
            end
        end
    end

    // Combinational Grant Logic
    always_comb begin
        gnt_vec = '0;
        arb_idx = 0;
        for (int j = 1; j <= N_AGENTS; j++) begin
            arb_idx = (int'(last_gnt_agent) + j) % N_AGENTS;
            if (agent_req_i[arb_idx]) begin
                gnt_vec[arb_idx] = 1'b1;
                break; // Grant only one agent per cycle
            end
        end
    end

    assign agent_ready_o = gnt_vec;

    // 2. Mux for Bank Inputs
    logic [ADDR_WIDTH-1:0]       sel_addr;
    logic                        sel_wr_enable;
    logic [BLOCK_DATA_WIDTH-1:0] sel_wr_data;

    always_comb begin
        sel_addr      = '0;
        sel_wr_enable = 1'b0;
        sel_wr_data   = '0;
        for (int i = 0; i < N_AGENTS; i++) begin
            if (gnt_vec[i]) begin
                sel_addr      = agent_addr_i[i];
                sel_wr_enable = agent_wr_enable_i[i];
                sel_wr_data   = agent_wr_data_i[i];
            end
        end
    end

    // 3. Bank Instantiation
    logic [N_BANKS-1:0][BANK_DATA_WIDTH-1:0] bank_rd_data;

    generate
        for (genvar b = 0; b < N_BANKS; b++) begin : gen_banks
            rv_spm_bank #(
                .DATA_WIDTH(BANK_DATA_WIDTH),
                .ADDR_WIDTH(BANK_ADDR_WIDTH)
            ) u_bank (
                .clk(clk),
                .reset_n(reset_n),
                // Explicit slicing to avoid UNUSEDSIGNAL warnings for lower bits
                .addr_i(sel_addr[ADDR_WIDTH-1 : $clog2(N_BANKS)]),
                .wr_enable_i(sel_wr_enable && |gnt_vec),
                .wr_data_i(sel_wr_data[b*BANK_DATA_WIDTH +: BANK_DATA_WIDTH]),
                .rd_data_o(bank_rd_data[b])
            );
        end
    endgenerate

    // 4. Response Handling (Read latency: 1 cycle)
    logic [N_AGENTS-1:0] rd_vld_pipe;
    
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rd_vld_pipe <= '0;
        end else begin
            // Valid for an agent if it was granted a READ request
            rd_vld_pipe <= gnt_vec & ~agent_wr_enable_i;
        end
    end

    assign agent_rd_data_vld_o = rd_vld_pipe;
    assign agent_rd_data_o     = {N_AGENTS{bank_rd_data}}; // Broadcast read data

endmodule
