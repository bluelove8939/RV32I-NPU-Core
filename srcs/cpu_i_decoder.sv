`timescale 1ns/1ps

module cpu_i_decoder (
    input  logic        instr_valid_i,
    input  logic [31:0] instr_pc_i,
    input  logic [31:0] instr_i,
    input  logic        instr_exception_valid_i,
    input  logic [31:0] instr_exception_cause_i,
    input  logic [31:0] instr_exception_tval_i,

    output logic        decode_valid_o,
    output logic [31:0] decode_pc_o,
    output logic [31:0] decode_instr_o,

    output logic [4:0]  rs1_addr_o,
    output logic [4:0]  rs2_addr_o,
    output logic [4:0]  rd_addr_o,
    output logic        rs1_used_o,
    output logic        rs2_used_o,
    output logic        rd_write_o,
    output logic [31:0] imm_o,

    output logic [3:0]  alu_op_o,
    output logic [1:0]  op_a_sel_o,
    output logic [1:0]  op_b_sel_o,

    output logic        branch_o,
    output logic [2:0]  branch_op_o,
    output logic        jump_o,
    output logic        jump_indirect_o,

    output logic        load_o,
    output logic        store_o,
    output logic [1:0]  mem_size_o,
    output logic        mem_unsigned_o,

    output logic        csr_valid_o,
    output logic [11:0] csr_addr_o,
    output logic [2:0]  csr_op_o,
    output logic        csr_write_o,
    output logic        csr_imm_o,

    output logic        system_ecall_o,
    output logic        system_ebreak_o,
    output logic        system_mret_o,

    output logic [2:0]  wb_sel_o,

    output logic        exception_valid_o,
    output logic [31:0] exception_cause_o,
    output logic [31:0] exception_tval_o
);

    localparam logic [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam logic [6:0] OPCODE_MISC_MEM = 7'b0001111;
    localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;
    localparam logic [6:0] OPCODE_AUIPC  = 7'b0010111;
    localparam logic [6:0] OPCODE_STORE  = 7'b0100011;
    localparam logic [6:0] OPCODE_OP     = 7'b0110011;
    localparam logic [6:0] OPCODE_LUI    = 7'b0110111;
    localparam logic [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam logic [6:0] OPCODE_JALR   = 7'b1100111;
    localparam logic [6:0] OPCODE_JAL    = 7'b1101111;
    localparam logic [6:0] OPCODE_SYSTEM = 7'b1110011;

    localparam logic [3:0] ALU_ADD  = 4'd0;
    localparam logic [3:0] ALU_SUB  = 4'd1;
    localparam logic [3:0] ALU_SLL  = 4'd2;
    localparam logic [3:0] ALU_SLT  = 4'd3;
    localparam logic [3:0] ALU_SLTU = 4'd4;
    localparam logic [3:0] ALU_XOR  = 4'd5;
    localparam logic [3:0] ALU_SRL  = 4'd6;
    localparam logic [3:0] ALU_SRA  = 4'd7;
    localparam logic [3:0] ALU_OR   = 4'd8;
    localparam logic [3:0] ALU_AND  = 4'd9;
    localparam logic [3:0] ALU_COPY_B = 4'd10;

    localparam logic [1:0] OP_A_RS1  = 2'd0;
    localparam logic [1:0] OP_A_PC   = 2'd1;
    localparam logic [1:0] OP_A_ZERO = 2'd2;

    localparam logic [1:0] OP_B_RS2 = 2'd0;
    localparam logic [1:0] OP_B_IMM = 2'd1;

    localparam logic [2:0] BR_NONE = 3'd0;
    localparam logic [2:0] BR_EQ   = 3'd1;
    localparam logic [2:0] BR_NE   = 3'd2;
    localparam logic [2:0] BR_LT   = 3'd3;
    localparam logic [2:0] BR_GE   = 3'd4;
    localparam logic [2:0] BR_LTU  = 3'd5;
    localparam logic [2:0] BR_GEU  = 3'd6;

    localparam logic [1:0] MEM_BYTE = 2'd0;
    localparam logic [1:0] MEM_HALF = 2'd1;
    localparam logic [1:0] MEM_WORD = 2'd2;

    localparam logic [2:0] CSR_OP_READ  = 3'd0;
    localparam logic [2:0] CSR_OP_WRITE = 3'd1;
    localparam logic [2:0] CSR_OP_SET   = 3'd2;
    localparam logic [2:0] CSR_OP_CLEAR = 3'd3;

    localparam logic [2:0] WB_ALU  = 3'd0;
    localparam logic [2:0] WB_LOAD = 3'd1;
    localparam logic [2:0] WB_CSR  = 3'd2;
    localparam logic [2:0] WB_PC4  = 3'd3;

    localparam logic [31:0] EXC_ILLEGAL_INSTRUCTION = 32'd2;
    localparam logic [31:0] EXC_BREAKPOINT          = 32'd3;
    localparam logic [31:0] EXC_ECALL_MMODE         = 32'd11;

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [4:0] rs1;
    logic [4:0] rs2;
    logic [4:0] rd;
    logic       illegal;

    logic [31:0] imm_i_type;
    logic [31:0] imm_s_type;
    logic [31:0] imm_b_type;
    logic [31:0] imm_u_type;
    logic [31:0] imm_j_type;
    logic [31:0] csr_uimm;

    assign opcode = instr_i[6:0];
    assign rd     = instr_i[11:7];
    assign funct3 = instr_i[14:12];
    assign rs1    = instr_i[19:15];
    assign rs2    = instr_i[24:20];
    assign funct7 = instr_i[31:25];

    assign imm_i_type = {{20{instr_i[31]}}, instr_i[31:20]};
    assign imm_s_type = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
    assign imm_b_type = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                         instr_i[30:25], instr_i[11:8], 1'b0};
    assign imm_u_type = {instr_i[31:12], 12'b0};
    assign imm_j_type = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12],
                         instr_i[20], instr_i[30:21], 1'b0};
    assign csr_uimm = {27'b0, rs1};

    always_comb begin
        decode_valid_o = instr_valid_i;
        decode_pc_o = instr_pc_i;
        decode_instr_o = instr_i;

        rs1_addr_o = rs1;
        rs2_addr_o = rs2;
        rd_addr_o = rd;
        rs1_used_o = 1'b0;
        rs2_used_o = 1'b0;
        rd_write_o = 1'b0;
        imm_o = 32'h0000_0000;

        alu_op_o = ALU_ADD;
        op_a_sel_o = OP_A_RS1;
        op_b_sel_o = OP_B_RS2;

        branch_o = 1'b0;
        branch_op_o = BR_NONE;
        jump_o = 1'b0;
        jump_indirect_o = 1'b0;

        load_o = 1'b0;
        store_o = 1'b0;
        mem_size_o = MEM_WORD;
        mem_unsigned_o = 1'b0;

        csr_valid_o = 1'b0;
        csr_addr_o = instr_i[31:20];
        csr_op_o = CSR_OP_READ;
        csr_write_o = 1'b0;
        csr_imm_o = 1'b0;

        system_ecall_o = 1'b0;
        system_ebreak_o = 1'b0;
        system_mret_o = 1'b0;

        wb_sel_o = WB_ALU;
        exception_valid_o = instr_exception_valid_i;
        exception_cause_o = instr_exception_cause_i;
        exception_tval_o = instr_exception_tval_i;
        illegal = 1'b0;

        if (instr_valid_i && !instr_exception_valid_i) begin
            unique case (opcode)
                OPCODE_LUI: begin
                    rd_write_o = 1'b1;
                    imm_o = imm_u_type;
                    alu_op_o = ALU_COPY_B;
                    op_a_sel_o = OP_A_ZERO;
                    op_b_sel_o = OP_B_IMM;
                    wb_sel_o = WB_ALU;
                end

                OPCODE_AUIPC: begin
                    rd_write_o = 1'b1;
                    imm_o = imm_u_type;
                    alu_op_o = ALU_ADD;
                    op_a_sel_o = OP_A_PC;
                    op_b_sel_o = OP_B_IMM;
                    wb_sel_o = WB_ALU;
                end

                OPCODE_JAL: begin
                    rd_write_o = 1'b1;
                    imm_o = imm_j_type;
                    jump_o = 1'b1;
                    wb_sel_o = WB_PC4;
                end

                OPCODE_JALR: begin
                    if (funct3 == 3'b000) begin
                        rs1_used_o = 1'b1;
                        rd_write_o = 1'b1;
                        imm_o = imm_i_type;
                        jump_o = 1'b1;
                        jump_indirect_o = 1'b1;
                        wb_sel_o = WB_PC4;
                    end else begin
                        illegal = 1'b1;
                    end
                end

                OPCODE_BRANCH: begin
                    rs1_used_o = 1'b1;
                    rs2_used_o = 1'b1;
                    imm_o = imm_b_type;
                    branch_o = 1'b1;
                    unique case (funct3)
                        3'b000: branch_op_o = BR_EQ;
                        3'b001: branch_op_o = BR_NE;
                        3'b100: branch_op_o = BR_LT;
                        3'b101: branch_op_o = BR_GE;
                        3'b110: branch_op_o = BR_LTU;
                        3'b111: branch_op_o = BR_GEU;
                        default: illegal = 1'b1;
                    endcase
                end

                OPCODE_LOAD: begin
                    rs1_used_o = 1'b1;
                    rd_write_o = 1'b1;
                    imm_o = imm_i_type;
                    alu_op_o = ALU_ADD;
                    op_a_sel_o = OP_A_RS1;
                    op_b_sel_o = OP_B_IMM;
                    load_o = 1'b1;
                    wb_sel_o = WB_LOAD;
                    unique case (funct3)
                        3'b000: begin
                            mem_size_o = MEM_BYTE;
                            mem_unsigned_o = 1'b0;
                        end
                        3'b001: begin
                            mem_size_o = MEM_HALF;
                            mem_unsigned_o = 1'b0;
                        end
                        3'b010: begin
                            mem_size_o = MEM_WORD;
                            mem_unsigned_o = 1'b0;
                        end
                        3'b100: begin
                            mem_size_o = MEM_BYTE;
                            mem_unsigned_o = 1'b1;
                        end
                        3'b101: begin
                            mem_size_o = MEM_HALF;
                            mem_unsigned_o = 1'b1;
                        end
                        default: illegal = 1'b1;
                    endcase
                end

                OPCODE_MISC_MEM: begin
                    unique case (funct3)
                        3'b000: begin
                        end
                        3'b001: begin
                        end
                        default: illegal = 1'b1;
                    endcase
                end

                OPCODE_STORE: begin
                    rs1_used_o = 1'b1;
                    rs2_used_o = 1'b1;
                    imm_o = imm_s_type;
                    alu_op_o = ALU_ADD;
                    op_a_sel_o = OP_A_RS1;
                    op_b_sel_o = OP_B_IMM;
                    store_o = 1'b1;
                    unique case (funct3)
                        3'b000: mem_size_o = MEM_BYTE;
                        3'b001: mem_size_o = MEM_HALF;
                        3'b010: mem_size_o = MEM_WORD;
                        default: illegal = 1'b1;
                    endcase
                end

                OPCODE_OP_IMM: begin
                    rs1_used_o = 1'b1;
                    rd_write_o = 1'b1;
                    imm_o = imm_i_type;
                    op_a_sel_o = OP_A_RS1;
                    op_b_sel_o = OP_B_IMM;
                    wb_sel_o = WB_ALU;
                    unique case (funct3)
                        3'b000: alu_op_o = ALU_ADD;
                        3'b010: alu_op_o = ALU_SLT;
                        3'b011: alu_op_o = ALU_SLTU;
                        3'b100: alu_op_o = ALU_XOR;
                        3'b110: alu_op_o = ALU_OR;
                        3'b111: alu_op_o = ALU_AND;
                        3'b001: begin
                            if (funct7 == 7'b0000000) begin
                                alu_op_o = ALU_SLL;
                            end else begin
                                illegal = 1'b1;
                            end
                        end
                        3'b101: begin
                            if (funct7 == 7'b0000000) begin
                                alu_op_o = ALU_SRL;
                            end else if (funct7 == 7'b0100000) begin
                                alu_op_o = ALU_SRA;
                            end else begin
                                illegal = 1'b1;
                            end
                        end
                        default: illegal = 1'b1;
                    endcase
                end

                OPCODE_OP: begin
                    rs1_used_o = 1'b1;
                    rs2_used_o = 1'b1;
                    rd_write_o = 1'b1;
                    op_a_sel_o = OP_A_RS1;
                    op_b_sel_o = OP_B_RS2;
                    wb_sel_o = WB_ALU;
                    unique case ({funct7, funct3})
                        {7'b0000000, 3'b000}: alu_op_o = ALU_ADD;
                        {7'b0100000, 3'b000}: alu_op_o = ALU_SUB;
                        {7'b0000000, 3'b001}: alu_op_o = ALU_SLL;
                        {7'b0000000, 3'b010}: alu_op_o = ALU_SLT;
                        {7'b0000000, 3'b011}: alu_op_o = ALU_SLTU;
                        {7'b0000000, 3'b100}: alu_op_o = ALU_XOR;
                        {7'b0000000, 3'b101}: alu_op_o = ALU_SRL;
                        {7'b0100000, 3'b101}: alu_op_o = ALU_SRA;
                        {7'b0000000, 3'b110}: alu_op_o = ALU_OR;
                        {7'b0000000, 3'b111}: alu_op_o = ALU_AND;
                        default: illegal = 1'b1;
                    endcase
                end

                OPCODE_SYSTEM: begin
                    if (funct3 == 3'b000) begin
                        unique case (instr_i)
                            32'h0000_0073: begin
                                system_ecall_o = 1'b1;
                                exception_valid_o = 1'b1;
                                exception_cause_o = EXC_ECALL_MMODE;
                                exception_tval_o = 32'h0000_0000;
                            end
                            32'h0010_0073: begin
                                system_ebreak_o = 1'b1;
                                exception_valid_o = 1'b1;
                                exception_cause_o = EXC_BREAKPOINT;
                                exception_tval_o = 32'h0000_0000;
                            end
                            32'h3020_0073: begin
                                system_mret_o = 1'b1;
                            end
                            default: illegal = 1'b1;
                        endcase
                    end else begin
                        csr_valid_o = 1'b1;
                        csr_addr_o = instr_i[31:20];
                        rd_write_o = 1'b1;
                        wb_sel_o = WB_CSR;
                        unique case (funct3)
                            3'b001: begin
                                rs1_used_o = 1'b1;
                                csr_op_o = CSR_OP_WRITE;
                                csr_write_o = 1'b1;
                            end
                            3'b010: begin
                                rs1_used_o = 1'b1;
                                csr_op_o = CSR_OP_SET;
                                csr_write_o = (rs1 != 5'd0);
                            end
                            3'b011: begin
                                rs1_used_o = 1'b1;
                                csr_op_o = CSR_OP_CLEAR;
                                csr_write_o = (rs1 != 5'd0);
                            end
                            3'b101: begin
                                csr_imm_o = 1'b1;
                                imm_o = csr_uimm;
                                csr_op_o = CSR_OP_WRITE;
                                csr_write_o = 1'b1;
                            end
                            3'b110: begin
                                csr_imm_o = 1'b1;
                                imm_o = csr_uimm;
                                csr_op_o = CSR_OP_SET;
                                csr_write_o = (rs1 != 5'd0);
                            end
                            3'b111: begin
                                csr_imm_o = 1'b1;
                                imm_o = csr_uimm;
                                csr_op_o = CSR_OP_CLEAR;
                                csr_write_o = (rs1 != 5'd0);
                            end
                            default: illegal = 1'b1;
                        endcase
                    end
                end

                default: begin
                    illegal = 1'b1;
                end
            endcase

            if (illegal) begin
                exception_valid_o = 1'b1;
                exception_cause_o = EXC_ILLEGAL_INSTRUCTION;
                exception_tval_o = instr_i;
                rd_write_o = 1'b0;
                load_o = 1'b0;
                store_o = 1'b0;
                branch_o = 1'b0;
                jump_o = 1'b0;
                csr_valid_o = 1'b0;
                csr_write_o = 1'b0;
                system_ecall_o = 1'b0;
                system_ebreak_o = 1'b0;
                system_mret_o = 1'b0;
            end
        end
    end

endmodule
