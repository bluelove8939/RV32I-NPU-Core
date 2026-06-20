`timescale 1ns/1ps

module tb_cpu_top;

    localparam int unsigned ADDR_WIDTH = 32;
    localparam int unsigned DATA_WIDTH = 32;
    localparam int unsigned LINE_WORDS = 16;
    localparam int unsigned LINE_WIDTH = DATA_WIDTH * LINE_WORDS;
    localparam int unsigned MEM_BYTES = 4096;
    localparam int unsigned N_BANK_GROUPS = 4;

    localparam logic [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;
    localparam logic [6:0] OPCODE_STORE  = 7'b0100011;
    localparam logic [6:0] OPCODE_OP     = 7'b0110011;
    localparam logic [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam logic [6:0] OPCODE_JAL    = 7'b1101111;
    localparam logic [6:0] OPCODE_SYSTEM = 7'b1110011;

    logic clk;
    logic reset_n;
    logic cpu_enable;
    logic lsu_flush_valid;
    logic lsu_flush_ready;

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

    logic                  preload_active;
    logic                  preload_d_req_valid;
    logic                  preload_d_req_ready;
    logic                  preload_d_req_write;
    logic [ADDR_WIDTH-1:0] preload_d_req_line_addr;
    logic [LINE_WIDTH-1:0] preload_d_req_wdata;
    logic [LINE_WORDS-1:0] preload_d_req_wstrb;
    logic                  preload_d_resp_valid;
    logic                  preload_d_resp_ready;
    logic [LINE_WIDTH-1:0] preload_d_resp_rdata;
    logic                  preload_d_resp_error;

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

    logic                  dbg_commit_valid;
    logic [31:0]           dbg_commit_pc;
    logic [31:0]           dbg_commit_instr;
    logic                  dbg_commit_exception;
    logic                  dbg_commit_interrupt;
    logic                  dbg_rf_we;
    logic [4:0]            dbg_rf_waddr;
    logic [31:0]           dbg_rf_wdata;
    logic [31:0]           dbg_fetch_pc;

    cpu_top #(
        .RESET_PC   (32'h0000_0000),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .LINE_WORDS (LINE_WORDS),
        .LINE_WIDTH (LINE_WIDTH)
    ) u_dut (
        .clk                          (clk),
        .reset_n                      (reset_n),
        .cpu_enable_i                 (cpu_enable),
        .software_interrupt_pending_i (1'b0),
        .timer_interrupt_pending_i    (1'b0),
        .external_interrupt_pending_i (1'b0),
        .lsu_flush_valid_i            (lsu_flush_valid),
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
        .debug_commit_valid_o         (dbg_commit_valid),
        .debug_commit_pc_o            (dbg_commit_pc),
        .debug_commit_instr_o         (dbg_commit_instr),
        .debug_commit_exception_o     (dbg_commit_exception),
        .debug_commit_interrupt_o     (dbg_commit_interrupt),
        .debug_rf_we_o                (dbg_rf_we),
        .debug_rf_waddr_o             (dbg_rf_waddr),
        .debug_rf_wdata_o             (dbg_rf_wdata),
        .debug_fetch_pc_o             (dbg_fetch_pc)
    );

    spm_bus #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .LINE_WORDS    (LINE_WORDS),
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

    assign bus_d_req_valid = preload_active ? preload_d_req_valid :
                                              cpu_d_req_valid;
    assign bus_d_req_write = preload_active ? preload_d_req_write :
                                              cpu_d_req_write;
    assign bus_d_req_line_addr = preload_active ? preload_d_req_line_addr :
                                                  cpu_d_req_line_addr;
    assign bus_d_req_wdata = preload_active ? preload_d_req_wdata :
                                              cpu_d_req_wdata;
    assign bus_d_req_wstrb = preload_active ? preload_d_req_wstrb :
                                              cpu_d_req_wstrb;
    assign bus_d_resp_ready = preload_active ? preload_d_resp_ready :
                                               cpu_d_resp_ready;

    assign preload_d_req_ready = preload_active && bus_d_req_ready;
    assign preload_d_resp_valid = preload_active && bus_d_resp_valid;
    assign preload_d_resp_rdata = bus_d_resp_rdata;
    assign preload_d_resp_error = bus_d_resp_error;

    assign cpu_d_req_ready = !preload_active && bus_d_req_ready;
    assign cpu_d_resp_valid = !preload_active && bus_d_resp_valid;
    assign cpu_d_resp_rdata = bus_d_resp_rdata;
    assign cpu_d_resp_error = bus_d_resp_error;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function automatic logic [31:0] r_type(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        return {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] i_type(
        input logic [11:0] imm,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] s_type(
        input logic [11:0] imm,
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3
    );
        return {imm[11:5], rs2, rs1, funct3, imm[4:0], OPCODE_STORE};
    endfunction

    function automatic logic [31:0] b_type(
        input logic [12:0] imm,
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3
    );
        logic unused_imm0;
        begin
            unused_imm0 = imm[0];
            return {imm[12], imm[10:5], rs2, rs1, funct3,
                    imm[4:1], imm[11], OPCODE_BRANCH} ^
                   {31'b0, unused_imm0 & 1'b0};
        end
    endfunction

    function automatic logic [31:0] j_type(
        input logic [20:0] imm,
        input logic [4:0]  rd
    );
        logic unused_imm0;
        begin
            unused_imm0 = imm[0];
            return {imm[20], imm[10:1], imm[11], imm[19:12],
                    rd, OPCODE_JAL} ^
                   {31'b0, unused_imm0 & 1'b0};
        end
    endfunction

    function automatic logic [31:0] addi(input logic [4:0] rd,
                                         input logic [4:0] rs1,
                                         input logic [11:0] imm);
        return i_type(imm, rs1, 3'b000, rd, OPCODE_OP_IMM);
    endfunction

    function automatic logic [31:0] lw(input logic [4:0] rd,
                                       input logic [4:0] rs1,
                                       input logic [11:0] imm);
        return i_type(imm, rs1, 3'b010, rd, OPCODE_LOAD);
    endfunction

    function automatic logic [31:0] sw(input logic [4:0] rs2,
                                       input logic [4:0] rs1,
                                       input logic [11:0] imm);
        return s_type(imm, rs2, rs1, 3'b010);
    endfunction

    function automatic logic [31:0] add(input logic [4:0] rd,
                                        input logic [4:0] rs1,
                                        input logic [4:0] rs2);
        return r_type(7'b0000000, rs2, rs1, 3'b000, rd, OPCODE_OP);
    endfunction

    function automatic logic [31:0] beq(input logic [4:0] rs1,
                                        input logic [4:0] rs2,
                                        input logic [12:0] imm);
        return b_type(imm, rs2, rs1, 3'b000);
    endfunction

    function automatic logic [31:0] jal(input logic [4:0] rd,
                                        input logic [20:0] imm);
        return j_type(imm, rd);
    endfunction

    function automatic logic [31:0] csrrw(input logic [4:0] rd,
                                          input logic [11:0] csr,
                                          input logic [4:0] rs1);
        return {csr, rs1, 3'b001, rd, OPCODE_SYSTEM};
    endfunction

    function automatic logic [31:0] csrrs(input logic [4:0] rd,
                                          input logic [11:0] csr,
                                          input logic [4:0] rs1);
        return {csr, rs1, 3'b010, rd, OPCODE_SYSTEM};
    endfunction

    function automatic logic [LINE_WIDTH-1:0] empty_line();
        return '0;
    endfunction

    task automatic reset_dut();
        begin
            reset_n = 1'b0;
            cpu_enable = 1'b0;
            lsu_flush_valid = 1'b0;
            preload_active = 1'b0;
            preload_d_req_valid = 1'b0;
            preload_d_req_write = 1'b0;
            preload_d_req_line_addr = '0;
            preload_d_req_wdata = '0;
            preload_d_req_wstrb = '0;
            preload_d_resp_ready = 1'b1;
            repeat (5) @(posedge clk);
            reset_n = 1'b1;
            repeat (2) @(posedge clk);
            #1;
        end
    endtask

    task automatic preload_write_line(
        input logic [ADDR_WIDTH-1:0] line_addr,
        input logic [LINE_WIDTH-1:0] line_data
    );
        int unsigned cycles;
        begin
            @(negedge clk);
            preload_active = 1'b1;
            preload_d_req_valid = 1'b1;
            preload_d_req_write = 1'b1;
            preload_d_req_line_addr = line_addr;
            preload_d_req_wdata = line_data;
            preload_d_req_wstrb = '1;

            cycles = 0;
            while (!preload_d_req_ready) begin
                @(negedge clk);
                cycles++;
                if (cycles > 40) begin
                    $fatal(1, "[FAIL] preload request timeout line=%0d", line_addr);
                end
            end

            @(posedge clk);
            #1;
            preload_d_req_valid = 1'b0;

            cycles = 0;
            while (!preload_d_resp_valid) begin
                @(posedge clk);
                #1;
                cycles++;
                if (cycles > 40) begin
                    $fatal(1, "[FAIL] preload response timeout line=%0d", line_addr);
                end
            end

            if (preload_d_resp_error) begin
                $fatal(1, "[FAIL] preload response error line=%0d", line_addr);
            end

            @(posedge clk);
            #1;
            @(negedge clk);
            preload_active = 1'b0;
        end
    endtask

    task automatic start_cpu();
        begin
            @(negedge clk);
            cpu_enable = 1'b1;
        end
    endtask

    task automatic wait_for_reg_write(
        input logic [4:0] expected_rd,
        input logic [31:0] expected_data,
        input int unsigned max_cycles
    );
        int unsigned cycles;
        begin
            cycles = 0;
            while (cycles < max_cycles) begin
                @(posedge clk);
                #1;
                if (dbg_commit_valid && dbg_rf_we &&
                    (dbg_rf_waddr == 5'd5)) begin
                    $fatal(1, "[FAIL] unexpected x5 write pc=0x%08x data=0x%08x",
                           dbg_commit_pc, dbg_rf_wdata);
                end
                if (dbg_commit_valid && dbg_rf_we &&
                    (dbg_rf_waddr == expected_rd)) begin
                    if (dbg_rf_wdata !== expected_data) begin
                        $fatal(1, "[FAIL] x%0d write data actual=0x%08x expected=0x%08x",
                               expected_rd, dbg_rf_wdata, expected_data);
                    end
                    return;
                end
                if (dbg_commit_exception) begin
                    $fatal(1, "[FAIL] unexpected exception pc=0x%08x instr=0x%08x",
                           dbg_commit_pc, dbg_commit_instr);
                end
                cycles++;
            end
            $fatal(1, "[FAIL] timeout waiting for x%0d=0x%08x",
                   expected_rd, expected_data);
        end
    endtask

    task automatic run_alu_lsu_branch_test();
        logic [LINE_WIDTH-1:0] line0;
        logic [LINE_WIDTH-1:0] data_line;
        begin
            $display("[TEST] cpu_top ALU/LSU/branch integration");
            reset_dut();

            line0 = empty_line();
            line0[0 * 32 +: 32] = addi(5'd1, 5'd0, 12'd5);
            line0[1 * 32 +: 32] = addi(5'd2, 5'd0, 12'd7);
            line0[2 * 32 +: 32] = add(5'd3, 5'd1, 5'd2);
            line0[3 * 32 +: 32] = sw(5'd3, 5'd0, 12'h100);
            line0[4 * 32 +: 32] = lw(5'd4, 5'd0, 12'h100);
            line0[5 * 32 +: 32] = beq(5'd4, 5'd3, 13'd8);
            line0[6 * 32 +: 32] = addi(5'd5, 5'd0, 12'd1);
            line0[7 * 32 +: 32] = jal(5'd0, 21'd0);
            data_line = empty_line();

            preload_write_line(0, line0);
            preload_write_line(4, data_line);
            start_cpu();
            wait_for_reg_write(5'd4, 32'd12, 250);
            $display("[PASS] cpu_top ALU/LSU/branch integration");
        end
    endtask

    task automatic run_csr_test();
        logic [LINE_WIDTH-1:0] line0;
        begin
            $display("[TEST] cpu_top CSR integration");
            reset_dut();

            line0 = empty_line();
            line0[0 * 32 +: 32] = addi(5'd1, 5'd0, 12'h055);
            line0[1 * 32 +: 32] = csrrw(5'd6, 12'h340, 5'd1);
            line0[2 * 32 +: 32] = csrrs(5'd7, 12'h340, 5'd0);
            line0[3 * 32 +: 32] = jal(5'd0, 21'd0);

            preload_write_line(0, line0);
            start_cpu();
            wait_for_reg_write(5'd6, 32'h0000_0000, 200);
            wait_for_reg_write(5'd7, 32'h0000_0055, 200);
            $display("[PASS] cpu_top CSR integration");
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (dbg_commit_valid) begin
            $display("[COMMIT] pc=0x%08x instr=0x%08x rf_we=%0b rd=%0d wdata=0x%08x exc=%0b irq=%0b fetch_pc=0x%08x",
                     dbg_commit_pc,
                     dbg_commit_instr,
                     dbg_rf_we,
                     dbg_rf_waddr,
                     dbg_rf_wdata,
                     dbg_commit_exception,
                     dbg_commit_interrupt,
                     dbg_fetch_pc);
        end
    end

    logic unused_tb_signals;
    assign unused_tb_signals = lsu_flush_ready ^ (^preload_d_resp_rdata);

    initial begin
        run_alu_lsu_branch_test();
        run_csr_test();
        $display("[PASS] CPU top tests complete");
        $finish;
    end

endmodule
