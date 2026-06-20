`timescale 1ns/1ps

module cpu_lsu #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned LINE_WORDS = 16,
    parameter int unsigned LINE_WIDTH = DATA_WIDTH * LINE_WORDS
) (
    input  logic                  clk,
    input  logic                  reset_n,

    input  logic                  req_valid_i,
    output logic                  req_ready_o,
    input  logic                  req_write_i,
    input  logic [31:0]           req_addr_i,
    input  logic [31:0]           req_wdata_i,
    input  logic [1:0]            req_size_i,
    input  logic                  req_unsigned_i,

    output logic                  resp_valid_o,
    input  logic                  resp_ready_i,
    output logic [31:0]           resp_rdata_o,
    output logic                  resp_exception_valid_o,
    output logic [31:0]           resp_exception_cause_o,
    output logic [31:0]           resp_exception_tval_o,

    input  logic                  snoop_valid_i,
    input  logic [ADDR_WIDTH-1:0] snoop_line_addr_i,
    output logic                  snoop_stall_o,

    input  logic                  flush_valid_i,
    output logic                  flush_ready_o,

    output logic                  spm_req_valid_o,
    input  logic                  spm_req_ready_i,
    output logic                  spm_req_write_o,
    output logic [ADDR_WIDTH-1:0] spm_req_line_addr_o,
    output logic [LINE_WIDTH-1:0] spm_req_wdata_o,
    output logic [LINE_WORDS-1:0] spm_req_wstrb_o,
    input  logic                  spm_resp_valid_i,
    output logic                  spm_resp_ready_o,
    input  logic [LINE_WIDTH-1:0] spm_resp_rdata_i,
    input  logic                  spm_resp_error_i
);

    localparam logic [1:0] MEM_BYTE = 2'd0;
    localparam logic [1:0] MEM_HALF = 2'd1;
    localparam logic [1:0] MEM_WORD = 2'd2;

    localparam logic [31:0] EXC_LOAD_ADDR_MISALIGNED  = 32'd4;
    localparam logic [31:0] EXC_LOAD_ACCESS_FAULT     = 32'd5;
    localparam logic [31:0] EXC_STORE_ADDR_MISALIGNED = 32'd6;
    localparam logic [31:0] EXC_STORE_ACCESS_FAULT    = 32'd7;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_COMMIT_REQ,
        ST_COMMIT_RESP,
        ST_READ_REQ,
        ST_READ_RESP
    } state_e;

    state_e state_q;

    logic                  buf_valid_q;
    logic                  buf_dirty_q;
    logic [ADDR_WIDTH-1:0] buf_line_addr_q;
    logic [LINE_WIDTH-1:0] buf_line_data_q;

    logic                  pend_valid_q;
    logic                  pend_write_q;
    logic [31:0]           pend_addr_q;
    logic [31:0]           pend_wdata_q;
    logic [1:0]            pend_size_q;
    logic                  pend_unsigned_q;
    logic [ADDR_WIDTH-1:0] pend_line_addr_q;

    logic                  resp_valid_q;
    logic [31:0]           resp_rdata_q;
    logic                  resp_exception_valid_q;
    logic [31:0]           resp_exception_cause_q;
    logic [31:0]           resp_exception_tval_q;

    logic                  commit_for_snoop_q;
    logic                  commit_for_flush_q;

    logic [ADDR_WIDTH-1:0] req_line_addr;
    logic                  req_misaligned;
    logic                  req_buf_hit;
    logic                  snoop_dirty_hit;
    logic                  flush_needs_commit;

    function automatic logic [ADDR_WIDTH-1:0] addr_to_line(input logic [31:0] addr);
        logic [ADDR_WIDTH-1:0] line_addr;
        begin
            line_addr = '0;
            for (int unsigned bit_idx = 0; bit_idx < 26; bit_idx++) begin
                if (bit_idx < ADDR_WIDTH) begin
                    line_addr[bit_idx] = addr[bit_idx + 6];
                end
            end
            return line_addr;
        end
    endfunction

    function automatic logic [$clog2(LINE_WORDS)-1:0] addr_to_word_offset(
        input logic [31:0] addr
    );
        logic [$clog2(LINE_WORDS)-1:0] offset;
        logic unused_addr_upper;
        begin
            offset = '0;
            unused_addr_upper = ^addr[31:6];
            for (int unsigned bit_idx = 0; bit_idx < $clog2(LINE_WORDS); bit_idx++) begin
                offset[bit_idx] = addr[2 + bit_idx];
            end
            if (unused_addr_upper) begin
                offset = offset;
            end
            return offset;
        end
    endfunction

    function automatic logic is_misaligned(
        input logic [31:0] addr,
        input logic [1:0]  size
    );
        logic unused_addr_upper;
        begin
            unused_addr_upper = ^addr[31:2];
            unique case (size)
                MEM_HALF: is_misaligned = addr[0] != 1'b0;
                MEM_WORD: is_misaligned = addr[1:0] != 2'b00;
                default:  is_misaligned = 1'b0;
            endcase
            if (unused_addr_upper) begin
                is_misaligned = is_misaligned;
            end
        end
    endfunction

    function automatic logic [31:0] get_word(
        input logic [LINE_WIDTH-1:0] line_data,
        input logic [$clog2(LINE_WORDS)-1:0] word_offset
    );
        return line_data[word_offset * DATA_WIDTH +: DATA_WIDTH];
    endfunction

    function automatic logic [31:0] merge_store_word(
        input logic [31:0] old_word,
        input logic [31:0] store_data,
        input logic [1:0]  byte_offset,
        input logic [1:0]  size
    );
        logic [31:0] merged;
        begin
            merged = old_word;
            unique case (size)
                MEM_BYTE: begin
                    merged[byte_offset * 8 +: 8] = store_data[7:0];
                end
                MEM_HALF: begin
                    merged[byte_offset[1] * 16 +: 16] = store_data[15:0];
                end
                default: begin
                    merged = store_data;
                end
            endcase
            return merged;
        end
    endfunction

    function automatic logic [LINE_WIDTH-1:0] merge_store_line(
        input logic [LINE_WIDTH-1:0] line_data,
        input logic [31:0]           addr,
        input logic [31:0]           store_data,
        input logic [1:0]            size
    );
        logic [LINE_WIDTH-1:0] merged_line;
        logic [$clog2(LINE_WORDS)-1:0] word_offset;
        logic [31:0] old_word;
        logic [31:0] new_word;
        begin
            merged_line = line_data;
            word_offset = addr_to_word_offset(addr);
            old_word = get_word(line_data, word_offset);
            new_word = merge_store_word(old_word, store_data, addr[1:0], size);
            merged_line[word_offset * DATA_WIDTH +: DATA_WIDTH] = new_word;
            return merged_line;
        end
    endfunction

    function automatic logic [31:0] format_load_data(
        input logic [LINE_WIDTH-1:0] line_data,
        input logic [31:0]           addr,
        input logic [1:0]            size,
        input logic                  is_unsigned
    );
        logic [$clog2(LINE_WORDS)-1:0] word_offset;
        logic [31:0] word_data;
        logic [7:0]  byte_data;
        logic [15:0] half_data;
        begin
            word_offset = addr_to_word_offset(addr);
            word_data = get_word(line_data, word_offset);
            byte_data = word_data[addr[1:0] * 8 +: 8];
            half_data = word_data[addr[1] * 16 +: 16];

            unique case (size)
                MEM_BYTE: return is_unsigned ? {24'b0, byte_data} :
                                         {{24{byte_data[7]}}, byte_data};
                MEM_HALF: return is_unsigned ? {16'b0, half_data} :
                                         {{16{half_data[15]}}, half_data};
                default:  return word_data;
            endcase
        end
    endfunction

    assign req_line_addr = addr_to_line(req_addr_i);
    assign req_misaligned = is_misaligned(req_addr_i, req_size_i);
    assign req_buf_hit = buf_valid_q && (buf_line_addr_q == req_line_addr);
    assign snoop_dirty_hit = snoop_valid_i && buf_valid_q && buf_dirty_q &&
                             (buf_line_addr_q == snoop_line_addr_i);
    assign flush_needs_commit = flush_valid_i && buf_valid_q && buf_dirty_q;

    assign req_ready_o = (state_q == ST_IDLE) && !resp_valid_q &&
                         !snoop_dirty_hit && !flush_needs_commit;
    assign snoop_stall_o = snoop_dirty_hit ||
                           (commit_for_snoop_q && (state_q != ST_IDLE));
    assign flush_ready_o = flush_valid_i && (state_q == ST_IDLE) &&
                           !resp_valid_q && !(buf_valid_q && buf_dirty_q);

    assign resp_valid_o = resp_valid_q;
    assign resp_rdata_o = resp_rdata_q;
    assign resp_exception_valid_o = resp_exception_valid_q;
    assign resp_exception_cause_o = resp_exception_cause_q;
    assign resp_exception_tval_o = resp_exception_tval_q;

    assign spm_req_valid_o = (state_q == ST_COMMIT_REQ) ||
                             (state_q == ST_READ_REQ);
    assign spm_req_write_o = (state_q == ST_COMMIT_REQ);
    assign spm_req_line_addr_o = (state_q == ST_COMMIT_REQ) ? buf_line_addr_q :
                                                                 pend_line_addr_q;
    assign spm_req_wdata_o = buf_line_data_q;
    assign spm_req_wstrb_o = (state_q == ST_COMMIT_REQ) ? '1 : '0;
    assign spm_resp_ready_o = (state_q == ST_COMMIT_RESP) ||
                              (state_q == ST_READ_RESP);

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= ST_IDLE;
            buf_valid_q <= 1'b0;
            buf_dirty_q <= 1'b0;
            buf_line_addr_q <= '0;
            buf_line_data_q <= '0;
            pend_valid_q <= 1'b0;
            pend_write_q <= 1'b0;
            pend_addr_q <= '0;
            pend_wdata_q <= '0;
            pend_size_q <= MEM_WORD;
            pend_unsigned_q <= 1'b0;
            pend_line_addr_q <= '0;
            resp_valid_q <= 1'b0;
            resp_rdata_q <= '0;
            resp_exception_valid_q <= 1'b0;
            resp_exception_cause_q <= '0;
            resp_exception_tval_q <= '0;
            commit_for_snoop_q <= 1'b0;
            commit_for_flush_q <= 1'b0;
        end else begin
            if (resp_valid_q && resp_ready_i) begin
                resp_valid_q <= 1'b0;
                resp_exception_valid_q <= 1'b0;
                resp_exception_cause_q <= '0;
                resp_exception_tval_q <= '0;
            end

            unique case (state_q)
                ST_IDLE: begin
                    commit_for_snoop_q <= 1'b0;
                    commit_for_flush_q <= 1'b0;

                    if (!resp_valid_q && snoop_dirty_hit) begin
                        state_q <= ST_COMMIT_REQ;
                        commit_for_snoop_q <= 1'b1;
                    end else if (!resp_valid_q && flush_needs_commit) begin
                        state_q <= ST_COMMIT_REQ;
                        commit_for_flush_q <= 1'b1;
                    end else if (req_valid_i && req_ready_o) begin
                        if (req_misaligned) begin
                            resp_valid_q <= 1'b1;
                            resp_rdata_q <= '0;
                            resp_exception_valid_q <= 1'b1;
                            resp_exception_cause_q <= req_write_i ?
                                EXC_STORE_ADDR_MISALIGNED :
                                EXC_LOAD_ADDR_MISALIGNED;
                            resp_exception_tval_q <= req_addr_i;
                        end else if (req_buf_hit) begin
                            resp_valid_q <= 1'b1;
                            resp_exception_valid_q <= 1'b0;
                            resp_exception_cause_q <= '0;
                            resp_exception_tval_q <= '0;
                            if (req_write_i) begin
                                buf_line_data_q <= merge_store_line(
                                    buf_line_data_q,
                                    req_addr_i,
                                    req_wdata_i,
                                    req_size_i
                                );
                                buf_dirty_q <= 1'b1;
                                resp_rdata_q <= '0;
                            end else begin
                                resp_rdata_q <= format_load_data(
                                    buf_line_data_q,
                                    req_addr_i,
                                    req_size_i,
                                    req_unsigned_i
                                );
                            end
                        end else begin
                            pend_valid_q <= 1'b1;
                            pend_write_q <= req_write_i;
                            pend_addr_q <= req_addr_i;
                            pend_wdata_q <= req_wdata_i;
                            pend_size_q <= req_size_i;
                            pend_unsigned_q <= req_unsigned_i;
                            pend_line_addr_q <= req_line_addr;
                            if (buf_valid_q && buf_dirty_q) begin
                                state_q <= ST_COMMIT_REQ;
                            end else begin
                                state_q <= ST_READ_REQ;
                            end
                        end
                    end
                end

                ST_COMMIT_REQ: begin
                    if (spm_req_ready_i) begin
                        state_q <= ST_COMMIT_RESP;
                    end
                end

                ST_COMMIT_RESP: begin
                    if (spm_resp_valid_i) begin
                        if (spm_resp_error_i) begin
                            resp_valid_q <= pend_valid_q;
                            resp_rdata_q <= '0;
                            resp_exception_valid_q <= pend_valid_q;
                            resp_exception_cause_q <= pend_write_q ?
                                EXC_STORE_ACCESS_FAULT :
                                EXC_LOAD_ACCESS_FAULT;
                            resp_exception_tval_q <= pend_addr_q;
                            pend_valid_q <= 1'b0;
                            state_q <= ST_IDLE;
                        end else begin
                            buf_dirty_q <= 1'b0;
                            if (commit_for_snoop_q || commit_for_flush_q) begin
                                commit_for_snoop_q <= 1'b0;
                                commit_for_flush_q <= 1'b0;
                                state_q <= ST_IDLE;
                            end else begin
                                state_q <= ST_READ_REQ;
                            end
                        end
                    end
                end

                ST_READ_REQ: begin
                    if (spm_req_ready_i) begin
                        state_q <= ST_READ_RESP;
                    end
                end

                ST_READ_RESP: begin
                    if (spm_resp_valid_i) begin
                        resp_valid_q <= 1'b1;
                        resp_rdata_q <= '0;
                        resp_exception_valid_q <= spm_resp_error_i;
                        resp_exception_cause_q <= spm_resp_error_i ?
                            (pend_write_q ? EXC_STORE_ACCESS_FAULT :
                                            EXC_LOAD_ACCESS_FAULT) :
                            32'h0000_0000;
                        resp_exception_tval_q <= spm_resp_error_i ?
                            pend_addr_q : 32'h0000_0000;

                        if (spm_resp_error_i) begin
                            buf_valid_q <= 1'b0;
                            buf_dirty_q <= 1'b0;
                        end else begin
                            buf_valid_q <= 1'b1;
                            buf_line_addr_q <= pend_line_addr_q;
                            if (pend_write_q) begin
                                buf_line_data_q <= merge_store_line(
                                    spm_resp_rdata_i,
                                    pend_addr_q,
                                    pend_wdata_q,
                                    pend_size_q
                                );
                                buf_dirty_q <= 1'b1;
                            end else begin
                                buf_line_data_q <= spm_resp_rdata_i;
                                buf_dirty_q <= 1'b0;
                                resp_rdata_q <= format_load_data(
                                    spm_resp_rdata_i,
                                    pend_addr_q,
                                    pend_size_q,
                                    pend_unsigned_q
                                );
                            end
                        end
                        pend_valid_q <= 1'b0;
                        state_q <= ST_IDLE;
                    end
                end

                default: begin
                    state_q <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
