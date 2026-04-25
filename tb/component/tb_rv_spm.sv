`timescale 1ns/1ps

module tb_rv_spm;

    // Parameters
    localparam int N_AGENTS        = 2;
    localparam int BANK_DATA_WIDTH = 8;
    localparam int BANK_ADDR_WIDTH = 13;
    localparam int N_BANKS         = 128;
    localparam int ADDR_WIDTH      = 20;
    localparam int BLOCK_DATA_WIDTH = N_BANKS * BANK_DATA_WIDTH;

    // Signals
    logic clk;
    logic reset_n;
    logic [N_AGENTS-1:0]                             agent_req;
    logic [N_AGENTS-1:0][ADDR_WIDTH-1:0]             agent_addr;
    logic [N_AGENTS-1:0]                             agent_wr_enable;
    logic [N_AGENTS-1:0][BLOCK_DATA_WIDTH-1:0]       agent_wr_data;
    logic [N_AGENTS-1:0]                             agent_ready;
    logic [N_AGENTS-1:0]                             agent_rd_data_vld;
    logic [N_AGENTS-1:0][BLOCK_DATA_WIDTH-1:0]       agent_rd_data;

    // DUT Instance
    rv_spm #(
        .N_AGENTS(N_AGENTS),
        .BANK_DATA_WIDTH(BANK_DATA_WIDTH),
        .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH),
        .N_BANKS(N_BANKS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .agent_req_i(agent_req),
        .agent_addr_i(agent_addr),
        .agent_wr_enable_i(agent_wr_enable),
        .agent_wr_data_i(agent_wr_data),
        .agent_ready_o(agent_ready),
        .agent_rd_data_vld_o(agent_rd_data_vld),
        .agent_rd_data_o(agent_rd_data)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test Procedure
    initial begin
        // Initialize
        reset_n = 0;
        agent_req = '0;
        agent_addr = '0;
        agent_wr_enable = '0;
        agent_wr_data = '0;

        $display("--- Starting SPM Testbench ---");
        repeat (2) @(posedge clk);
        reset_n = 1;
        repeat (2) @(posedge clk);

        // Scenario 1: Agent 0 Write
        $display("[T1] Agent 0: Writing data 0xAA to Addr 0x01234");
        agent_req[0] = 1;
        agent_addr[0] = 20'h01234;
        agent_wr_enable[0] = 1;
        agent_wr_data[0] = {N_BANKS{8'hAA}};
        @(posedge clk);
        while (!agent_ready[0]) @(posedge clk);
        agent_req[0] = 0;
        agent_wr_enable[0] = 0;
        
        // Scenario 2: Agent 1 Write
        $display("[T2] Agent 1: Writing data 0xBB to Addr 0x05678");
        agent_req[1] = 1;
        agent_addr[1] = 20'h05678;
        agent_wr_enable[1] = 1;
        agent_wr_data[1] = {N_BANKS{8'hBB}};
        @(posedge clk);
        while (!agent_ready[1]) @(posedge clk);
        agent_req[1] = 0;
        agent_wr_enable[1] = 0;

        repeat (2) @(posedge clk);

        // Scenario 3: Simultaneous Read (Arbitration Check)
        $display("[T3] Simultaneous Read: Both Agents requesting at the same time");
        agent_req = 2'b11;
        agent_wr_enable = 2'b00;
        agent_addr[0] = 20'h01234;
        agent_addr[1] = 20'h05678;

        // Cycle 1: Arbiter decides
        @(posedge clk);
        $display("Cycle 1: agent_ready(Gnt) = %b, agent_rd_data_vld = %b", agent_ready, agent_rd_data_vld);
        
        // Cycle 2: Previous read data should be valid, and next agent granted
        @(posedge clk);
        $display("Cycle 2: agent_ready(Gnt) = %b, agent_rd_data_vld = %b", agent_ready, agent_rd_data_vld);
        if (agent_rd_data_vld[0]) $display(">> Agent 0 Read Data [0]: %h (Expected AA)", agent_rd_data[0][7:0]);
        if (agent_rd_data_vld[1]) $display(">> Agent 1 Read Data [0]: %h (Expected BB)", agent_rd_data[1][7:0]);

        // Cycle 3: Last read data valid
        @(posedge clk);
        agent_req = 2'b00; // Stop requests
        $display("Cycle 3: agent_ready(Gnt) = %b, agent_rd_data_vld = %b", agent_ready, agent_rd_data_vld);
        if (agent_rd_data_vld[0]) $display(">> Agent 0 Read Data [0]: %h (Expected AA)", agent_rd_data[0][7:0]);
        if (agent_rd_data_vld[1]) $display(">> Agent 1 Read Data [0]: %h (Expected BB)", agent_rd_data[1][7:0]);

        repeat (5) @(posedge clk);
        
        $display("--- SPM Testbench Finished ---");
        $finish;
    end

endmodule
