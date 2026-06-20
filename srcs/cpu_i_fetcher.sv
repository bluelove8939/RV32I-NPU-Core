`timescale 1ns/1ps

module cpu_i_fetcher #(
    parameter logic [31:0] RESET_PC   = 32'h0000_0000,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned LINE_WORDS = 16,
    parameter int unsigned LINE_WIDTH = DATA_WIDTH * LINE_WORDS
) (
    input  logic                  clk,
    input  logic                  reset_n,

    input  logic                  fetch_enable_i,

    input  logic                  redirect_valid_i,
    input  logic [31:0]           redirect_pc_i,

    output logic                  snoop_query_valid_o,
    output logic [ADDR_WIDTH-1:0] snoop_query_line_addr_o,
    input  logic                  snoop_stall_i,
    input  logic                  invalidate_valid_i,
    input  logic [ADDR_WIDTH-1:0] invalidate_line_addr_i,

    output logic                  instr_valid_o,
    input  logic                  instr_ready_i,
    output logic [31:0]           instr_pc_o,
    output logic [31:0]           instr_o,
    output logic                  instr_exception_valid_o,
    output logic [31:0]           instr_exception_cause_o,
    output logic [31:0]           instr_exception_tval_o,

    output logic                  spm_req_valid_o,
    input  logic                  spm_req_ready_i,
    output logic [ADDR_WIDTH-1:0] spm_req_line_addr_o,
    input  logic                  spm_resp_valid_i,
    output logic                  spm_resp_ready_o,
    input  logic [LINE_WIDTH-1:0] spm_resp_rdata_i,
    input  logic                  spm_resp_error_i,

    output logic [31:0]           fetch_pc_o,
    output logic                  fetch_stalled_o
);

    localparam int unsigned BYTE_OFFSET_BITS = 2;
    localparam int unsigned WORD_OFFSET_BITS = (LINE_WORDS <= 1) ? 1 :
                                               $clog2(LINE_WORDS);
    localparam int unsigned LINE_OFFSET_BITS = BYTE_OFFSET_BITS +
                                               WORD_OFFSET_BITS;

    localparam logic [31:0] EXC_INSTR_ADDR_MISALIGNED = 32'd0;
    localparam logic [31:0] EXC_INSTR_ACCESS_FAULT    = 32'd1;

    logic [31:0]           pc_q;
    logic [31:0]           pc_d;

    logic                  line_valid_q;
    logic                  line_valid_d;
    logic [ADDR_WIDTH-1:0] line_addr_q;
    logic [ADDR_WIDTH-1:0] line_addr_d;
    logic [LINE_WIDTH-1:0] line_data_q;
    logic [LINE_WIDTH-1:0] line_data_d;

    logic                  fault_valid_q;
    logic                  fault_valid_d;
    logic [ADDR_WIDTH-1:0] fault_line_addr_q;
    logic [ADDR_WIDTH-1:0] fault_line_addr_d;

    logic                  req_pending_q;
    logic                  req_pending_d;
    logic                  req_kill_q;
    logic                  req_kill_d;
    logic [ADDR_WIDTH-1:0] req_line_addr_q;
    logic [ADDR_WIDTH-1:0] req_line_addr_d;

    logic                  out_valid_q;
    logic                  out_valid_d;
    logic [31:0]           out_pc_q;
    logic [31:0]           out_pc_d;
    logic [31:0]           out_instr_q;
    logic [31:0]           out_instr_d;
    logic                  out_exception_valid_q;
    logic                  out_exception_valid_d;
    logic [31:0]           out_exception_cause_q;
    logic [31:0]           out_exception_cause_d;
    logic [31:0]           out_exception_tval_q;
    logic [31:0]           out_exception_tval_d;

    logic [ADDR_WIDTH-1:0] pc_line_addr;
    logic                  pc_misaligned;
    logic                  line_hit;
    logic                  fault_hit;
    logic                  instr_accept;
    logic                  issue_request;
    logic                  invalidate_line_hit;
    logic                  invalidate_fault_hit;
    logic                  invalidate_pending_hit;
    logic                  invalidate_output_hit;

    function automatic logic [ADDR_WIDTH-1:0] pc_to_line_addr(
        input logic [31:0] pc
    );
        logic [ADDR_WIDTH-1:0] line_addr;
        begin
            line_addr = '0;
            for (int unsigned bit_idx = 0;
                 bit_idx < (32 - LINE_OFFSET_BITS);
                 bit_idx++) begin
                if (bit_idx < ADDR_WIDTH) begin
                    line_addr[bit_idx] = pc[bit_idx + LINE_OFFSET_BITS];
                end
            end
            return line_addr;
        end
    endfunction

    function automatic logic [WORD_OFFSET_BITS-1:0] pc_to_word_offset(
        input logic [31:0] pc
    );
        logic [WORD_OFFSET_BITS-1:0] word_offset;
        begin
            word_offset = '0;
            for (int unsigned bit_idx = 0;
                 bit_idx < WORD_OFFSET_BITS;
                 bit_idx++) begin
                word_offset[bit_idx] = pc[BYTE_OFFSET_BITS + bit_idx];
            end
            return word_offset;
        end
    endfunction

    function automatic logic [31:0] select_instr_word(
        input logic [LINE_WIDTH-1:0]       line_data,
        input logic [WORD_OFFSET_BITS-1:0] word_offset
    );
        return line_data[word_offset * DATA_WIDTH +: DATA_WIDTH];
    endfunction

    assign pc_line_addr = pc_to_line_addr(pc_q);
    assign pc_misaligned = (pc_q[1:0] != 2'b00);
    assign line_hit = line_valid_q && (line_addr_q == pc_line_addr);
    assign fault_hit = fault_valid_q && (fault_line_addr_q == pc_line_addr);
    assign instr_accept = out_valid_q && instr_ready_i;
    assign invalidate_line_hit = invalidate_valid_i && line_valid_q &&
                                 (line_addr_q == invalidate_line_addr_i);
    assign invalidate_fault_hit = invalidate_valid_i && fault_valid_q &&
                                  (fault_line_addr_q == invalidate_line_addr_i);
    assign invalidate_pending_hit = invalidate_valid_i && req_pending_q &&
                                    (req_line_addr_q == invalidate_line_addr_i);
    assign invalidate_output_hit = invalidate_valid_i && out_valid_q &&
                                   (pc_to_line_addr(out_pc_q) ==
                                    invalidate_line_addr_i);

    assign snoop_query_valid_o = fetch_enable_i &&
                                 !redirect_valid_i &&
                                 !pc_misaligned;
    assign snoop_query_line_addr_o = pc_line_addr;

    assign issue_request = fetch_enable_i &&
                           !redirect_valid_i &&
                           !snoop_stall_i &&
                           !req_pending_q &&
                           !out_valid_q &&
                           !pc_misaligned &&
                           !line_hit &&
                           !fault_hit;

    assign spm_req_valid_o = issue_request;
    assign spm_req_line_addr_o = pc_line_addr;
    assign spm_resp_ready_o = req_pending_q;

    assign instr_valid_o = out_valid_q;
    assign instr_pc_o = out_pc_q;
    assign instr_o = out_instr_q;
    assign instr_exception_valid_o = out_exception_valid_q;
    assign instr_exception_cause_o = out_exception_cause_q;
    assign instr_exception_tval_o = out_exception_tval_q;

    assign fetch_pc_o = pc_q;
    assign fetch_stalled_o = fetch_enable_i &&
                             !redirect_valid_i &&
                             !out_valid_q &&
                             !pc_misaligned &&
                             (snoop_stall_i ||
                             !line_hit &&
                             !fault_hit);

    always_comb begin
        pc_d = pc_q;
        line_valid_d = line_valid_q;
        line_addr_d = line_addr_q;
        line_data_d = line_data_q;
        fault_valid_d = fault_valid_q;
        fault_line_addr_d = fault_line_addr_q;
        req_pending_d = req_pending_q;
        req_kill_d = req_kill_q;
        req_line_addr_d = req_line_addr_q;
        out_valid_d = out_valid_q;
        out_pc_d = out_pc_q;
        out_instr_d = out_instr_q;
        out_exception_valid_d = out_exception_valid_q;
        out_exception_cause_d = out_exception_cause_q;
        out_exception_tval_d = out_exception_tval_q;

        if (invalidate_line_hit) begin
            line_valid_d = 1'b0;
        end

        if (invalidate_fault_hit) begin
            fault_valid_d = 1'b0;
        end

        if (invalidate_pending_hit) begin
            req_kill_d = 1'b1;
        end

        if (invalidate_output_hit) begin
            out_valid_d = 1'b0;
        end

        if (spm_resp_valid_i && spm_resp_ready_o) begin
            req_pending_d = 1'b0;
            if (req_kill_q) begin
                req_kill_d = 1'b0;
            end else if (spm_resp_error_i) begin
                fault_valid_d = 1'b1;
                fault_line_addr_d = req_line_addr_q;
                if (line_valid_d && (line_addr_d == req_line_addr_q)) begin
                    line_valid_d = 1'b0;
                end
            end else begin
                line_valid_d = 1'b1;
                line_addr_d = req_line_addr_q;
                line_data_d = spm_resp_rdata_i;
                if (fault_valid_d && (fault_line_addr_d == req_line_addr_q)) begin
                    fault_valid_d = 1'b0;
                end
            end
        end

        if (spm_req_valid_o && spm_req_ready_i) begin
            req_pending_d = 1'b1;
            req_line_addr_d = spm_req_line_addr_o;
        end

        if (redirect_valid_i) begin
            pc_d = redirect_pc_i;
            out_valid_d = 1'b0;
        end else begin
            if (instr_accept) begin
                pc_d = pc_q + 32'd4;
                out_valid_d = 1'b0;
            end

            if (fetch_enable_i && !out_valid_d) begin
                if (pc_d[1:0] != 2'b00) begin
                    out_valid_d = 1'b1;
                    out_pc_d = pc_d;
                    out_instr_d = 32'h0000_0000;
                    out_exception_valid_d = 1'b1;
                    out_exception_cause_d = EXC_INSTR_ADDR_MISALIGNED;
                    out_exception_tval_d = pc_d;
                end else if (fault_valid_d &&
                             (fault_line_addr_d == pc_to_line_addr(pc_d))) begin
                    out_valid_d = 1'b1;
                    out_pc_d = pc_d;
                    out_instr_d = 32'h0000_0000;
                    out_exception_valid_d = 1'b1;
                    out_exception_cause_d = EXC_INSTR_ACCESS_FAULT;
                    out_exception_tval_d = pc_d;
                end else if (line_valid_d &&
                             (line_addr_d == pc_to_line_addr(pc_d)) &&
                             !snoop_stall_i) begin
                    out_valid_d = 1'b1;
                    out_pc_d = pc_d;
                    out_instr_d = select_instr_word(
                        line_data_d,
                        pc_to_word_offset(pc_d)
                    );
                    out_exception_valid_d = 1'b0;
                    out_exception_cause_d = 32'h0000_0000;
                    out_exception_tval_d = 32'h0000_0000;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pc_q <= RESET_PC;
            line_valid_q <= 1'b0;
            line_addr_q <= '0;
            line_data_q <= '0;
            fault_valid_q <= 1'b0;
            fault_line_addr_q <= '0;
            req_pending_q <= 1'b0;
            req_kill_q <= 1'b0;
            req_line_addr_q <= '0;
            out_valid_q <= 1'b0;
            out_pc_q <= '0;
            out_instr_q <= '0;
            out_exception_valid_q <= 1'b0;
            out_exception_cause_q <= '0;
            out_exception_tval_q <= '0;
        end else begin
            pc_q <= pc_d;
            line_valid_q <= line_valid_d;
            line_addr_q <= line_addr_d;
            line_data_q <= line_data_d;
            fault_valid_q <= fault_valid_d;
            fault_line_addr_q <= fault_line_addr_d;
            req_pending_q <= req_pending_d;
            req_kill_q <= req_kill_d;
            req_line_addr_q <= req_line_addr_d;
            out_valid_q <= out_valid_d;
            out_pc_q <= out_pc_d;
            out_instr_q <= out_instr_d;
            out_exception_valid_q <= out_exception_valid_d;
            out_exception_cause_q <= out_exception_cause_d;
            out_exception_tval_q <= out_exception_tval_d;
        end
    end

endmodule
