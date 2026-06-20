`timescale 1ns/1ps

module cpu_csr #(
    parameter logic [31:0] HART_ID = 32'h0000_0000,
    parameter logic [31:0] MISA_VALUE = 32'h4000_0100
) (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        csr_req_valid_i,
    input  logic [2:0]  csr_req_op_i,
    input  logic [11:0] csr_req_addr_i,
    input  logic [31:0] csr_req_wdata_i,
    input  logic        csr_req_write_i,
    output logic [31:0] csr_resp_rdata_o,
    output logic        csr_resp_valid_o,
    output logic        csr_resp_illegal_o,

    input  logic        instret_inc_i,

    input  logic        trap_valid_i,
    input  logic [31:0] trap_mepc_i,
    input  logic [31:0] trap_mcause_i,
    input  logic [31:0] trap_mtval_i,

    input  logic        mret_valid_i,

    input  logic        software_interrupt_pending_i,
    input  logic        timer_interrupt_pending_i,
    input  logic        external_interrupt_pending_i,

    output logic [31:0] mstatus_o,
    output logic [31:0] mie_o,
    output logic [31:0] mtvec_o,
    output logic [31:0] mscratch_o,
    output logic [31:0] mepc_o,
    output logic [31:0] mcause_o,
    output logic [31:0] mtval_o,
    output logic [31:0] mip_o,
    output logic [63:0] mcycle_o,
    output logic [63:0] minstret_o,
    output logic        interrupt_pending_o,
    output logic [31:0] interrupt_cause_o
);

    localparam logic [2:0] CSR_OP_READ  = 3'd0;
    localparam logic [2:0] CSR_OP_WRITE = 3'd1;
    localparam logic [2:0] CSR_OP_SET   = 3'd2;
    localparam logic [2:0] CSR_OP_CLEAR = 3'd3;

    localparam logic [11:0] CSR_MSTATUS  = 12'h300;
    localparam logic [11:0] CSR_MISA     = 12'h301;
    localparam logic [11:0] CSR_MIE      = 12'h304;
    localparam logic [11:0] CSR_MTVEC    = 12'h305;
    localparam logic [11:0] CSR_MSCRATCH = 12'h340;
    localparam logic [11:0] CSR_MEPC     = 12'h341;
    localparam logic [11:0] CSR_MCAUSE   = 12'h342;
    localparam logic [11:0] CSR_MTVAL    = 12'h343;
    localparam logic [11:0] CSR_MIP      = 12'h344;
    localparam logic [11:0] CSR_MCYCLE   = 12'hB00;
    localparam logic [11:0] CSR_MINSTRET = 12'hB02;
    localparam logic [11:0] CSR_MCYCLEH  = 12'hB80;
    localparam logic [11:0] CSR_MINSTRETH = 12'hB82;
    localparam logic [11:0] CSR_MHARTID  = 12'hF14;

    localparam logic [31:0] MSTATUS_MIE_MASK  = 32'h0000_0008;
    localparam logic [31:0] MSTATUS_MPIE_MASK = 32'h0000_0080;
    localparam logic [31:0] MSTATUS_MPP_MASK  = 32'h0000_1800;
    localparam logic [31:0] MSTATUS_WR_MASK   = MSTATUS_MIE_MASK |
                                                MSTATUS_MPIE_MASK |
                                                MSTATUS_MPP_MASK;
    localparam logic [31:0] MACHINE_IRQ_MASK  = 32'h0000_0888;

    logic [31:0] mstatus_q;
    logic [31:0] mie_q;
    logic [31:0] mtvec_q;
    logic [31:0] mscratch_q;
    logic [31:0] mepc_q;
    logic [31:0] mcause_q;
    logic [31:0] mtval_q;
    logic [63:0] mcycle_q;
    logic [63:0] minstret_q;

    logic        csr_known;
    logic        csr_read_only;
    logic        csr_op_known;
    logic [31:0] csr_write_data;
    logic [31:0] mip_value;
    logic [31:0] enabled_interrupts;

    assign csr_resp_valid_o = csr_req_valid_i;
    assign csr_op_known = (csr_req_op_i == CSR_OP_READ)  ||
                          (csr_req_op_i == CSR_OP_WRITE) ||
                          (csr_req_op_i == CSR_OP_SET)   ||
                          (csr_req_op_i == CSR_OP_CLEAR);
    assign csr_resp_illegal_o = csr_req_valid_i &&
                                (!csr_known ||
                                 !csr_op_known ||
                                 (csr_req_write_i && csr_read_only));

    assign mip_value = {20'b0,
                        external_interrupt_pending_i,
                        3'b000,
                        timer_interrupt_pending_i,
                        3'b000,
                        software_interrupt_pending_i,
                        3'b000};
    assign enabled_interrupts = mie_q & mip_value & MACHINE_IRQ_MASK;

    assign mstatus_o = mstatus_q;
    assign mie_o = mie_q;
    assign mtvec_o = mtvec_q;
    assign mscratch_o = mscratch_q;
    assign mepc_o = mepc_q;
    assign mcause_o = mcause_q;
    assign mtval_o = mtval_q;
    assign mip_o = mip_value;
    assign mcycle_o = mcycle_q;
    assign minstret_o = minstret_q;
    assign interrupt_pending_o = mstatus_q[3] && (enabled_interrupts != '0);

    always_comb begin
        csr_known = 1'b1;
        csr_read_only = 1'b0;
        csr_resp_rdata_o = '0;

        unique case (csr_req_addr_i)
            CSR_MSTATUS:  csr_resp_rdata_o = mstatus_q;
            CSR_MISA: begin
                csr_resp_rdata_o = MISA_VALUE;
                csr_read_only = 1'b1;
            end
            CSR_MIE:      csr_resp_rdata_o = mie_q;
            CSR_MTVEC:    csr_resp_rdata_o = mtvec_q;
            CSR_MSCRATCH: csr_resp_rdata_o = mscratch_q;
            CSR_MEPC:     csr_resp_rdata_o = mepc_q;
            CSR_MCAUSE:   csr_resp_rdata_o = mcause_q;
            CSR_MTVAL:    csr_resp_rdata_o = mtval_q;
            CSR_MIP: begin
                csr_resp_rdata_o = mip_value;
                csr_read_only = 1'b1;
            end
            CSR_MCYCLE:   csr_resp_rdata_o = mcycle_q[31:0];
            CSR_MINSTRET: csr_resp_rdata_o = minstret_q[31:0];
            CSR_MCYCLEH:  csr_resp_rdata_o = mcycle_q[63:32];
            CSR_MINSTRETH: csr_resp_rdata_o = minstret_q[63:32];
            CSR_MHARTID: begin
                csr_resp_rdata_o = HART_ID;
                csr_read_only = 1'b1;
            end
            default: begin
                csr_known = 1'b0;
                csr_resp_rdata_o = '0;
            end
        endcase
    end

    always_comb begin
        unique case (csr_req_op_i)
            CSR_OP_WRITE: csr_write_data = csr_req_wdata_i;
            CSR_OP_SET:   csr_write_data = csr_resp_rdata_o | csr_req_wdata_i;
            CSR_OP_CLEAR: csr_write_data = csr_resp_rdata_o & ~csr_req_wdata_i;
            default:      csr_write_data = csr_resp_rdata_o;
        endcase
    end

    always_comb begin
        interrupt_cause_o = 32'h0000_0000;
        if (enabled_interrupts[11]) begin
            interrupt_cause_o = 32'h8000_000B;
        end else if (enabled_interrupts[7]) begin
            interrupt_cause_o = 32'h8000_0007;
        end else if (enabled_interrupts[3]) begin
            interrupt_cause_o = 32'h8000_0003;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            mstatus_q  <= '0;
            mie_q      <= '0;
            mtvec_q    <= '0;
            mscratch_q <= '0;
            mepc_q     <= '0;
            mcause_q   <= '0;
            mtval_q    <= '0;
            mcycle_q   <= '0;
            minstret_q <= '0;
        end else begin
            mcycle_q <= mcycle_q + 64'd1;
            if (instret_inc_i) begin
                minstret_q <= minstret_q + 64'd1;
            end

            if (csr_req_valid_i && csr_req_write_i && !csr_resp_illegal_o) begin
                unique case (csr_req_addr_i)
                    CSR_MSTATUS: begin
                        mstatus_q <= (mstatus_q & ~MSTATUS_WR_MASK) |
                                     (csr_write_data & MSTATUS_WR_MASK);
                    end
                    CSR_MIE: begin
                        mie_q <= csr_write_data & MACHINE_IRQ_MASK;
                    end
                    CSR_MTVEC: begin
                        mtvec_q <= {csr_write_data[31:2], 2'b00};
                    end
                    CSR_MSCRATCH: begin
                        mscratch_q <= csr_write_data;
                    end
                    CSR_MEPC: begin
                        mepc_q <= csr_write_data & 32'hFFFF_FFFC;
                    end
                    CSR_MCAUSE: begin
                        mcause_q <= csr_write_data;
                    end
                    CSR_MTVAL: begin
                        mtval_q <= csr_write_data;
                    end
                    CSR_MCYCLE: begin
                        mcycle_q[31:0] <= csr_write_data;
                    end
                    CSR_MINSTRET: begin
                        minstret_q[31:0] <= csr_write_data;
                    end
                    CSR_MCYCLEH: begin
                        mcycle_q[63:32] <= csr_write_data;
                    end
                    CSR_MINSTRETH: begin
                        minstret_q[63:32] <= csr_write_data;
                    end
                    default: begin
                    end
                endcase
            end

            if (trap_valid_i) begin
                mepc_q <= trap_mepc_i & 32'hFFFF_FFFC;
                mcause_q <= trap_mcause_i;
                mtval_q <= trap_mtval_i;
                mstatus_q[7] <= mstatus_q[3];
                mstatus_q[3] <= 1'b0;
                mstatus_q[12:11] <= 2'b11;
            end else if (mret_valid_i) begin
                mstatus_q[3] <= mstatus_q[7];
                mstatus_q[7] <= 1'b1;
                mstatus_q[12:11] <= 2'b11;
            end
        end
    end

endmodule
