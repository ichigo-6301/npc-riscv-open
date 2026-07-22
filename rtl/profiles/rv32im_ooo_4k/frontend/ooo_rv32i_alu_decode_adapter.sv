`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_rv32i_alu_decode_adapter (
    input  logic valid_i,
    input  logic [31:0] pc_i,
    input  logic [31:0] instr_i,

    output logic supported_o,
    output logic unsupported_o,
    output bbus_ooo_decode_uop_t decode_uop_o
);
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    bbus_ooo_alu_op_e alu_op_c;
    bbus_ooo_mdu_op_e mdu_op_c;
    bbus_ooo_atomic_op_e atomic_op_c;
    bbus_ooo_fu_type_e fu_type_c;
    bbus_ooo_branch_op_e branch_op_c;
    bbus_ooo_mem_op_e mem_op_c;
    logic is_op_imm;
    logic is_op;
    logic is_lui;
    logic is_auipc;
    logic is_load;
    logic is_store;
    logic is_branch;
    logic is_jal;
    logic is_jalr;
    logic is_fence_opcode;
    logic is_fence;
    logic is_fencei;
    logic is_system;
    logic is_csr;
    logic is_ebreak;
    logic is_ecall;
    logic is_mret;
    logic is_sret;
    logic is_wfi;
    logic is_sfence_vma;
    logic is_m_extension;
    logic is_atomic_opcode;
    logic is_supported_csr_op;
    logic precise_illegal_c;
    logic op_recognized;
    logic op_enabled;
    logic uses_rs1_c;
    logic uses_rs2_c;
    logic src1_is_pc_c;
    logic src2_is_imm_c;
    logic [31:0] imm_i_c;
    logic [31:0] imm_s_c;
    logic [31:0] imm_u_c;
    logic [31:0] imm_b_c;
    logic [31:0] imm_j_c;
    logic [31:0] imm_c;

    assign opcode = instr_i[6:0];
    assign funct3 = instr_i[14:12];
    assign funct7 = instr_i[31:25];
    assign is_op_imm = (opcode == 7'b0010011);
    assign is_op = (opcode == 7'b0110011);
    assign is_lui = (opcode == 7'b0110111);
    assign is_auipc = (opcode == 7'b0010111);
    assign is_load = (opcode == 7'b0000011);
    assign is_store = (opcode == 7'b0100011);
    assign is_branch = (opcode == 7'b1100011);
    assign is_jal = (opcode == 7'b1101111);
    assign is_jalr = (opcode == 7'b1100111);
    assign is_fence_opcode = (opcode == 7'b0001111);
    assign is_fence = is_fence_opcode && (funct3 == 3'b000) &&
        (instr_i[11:7] == 5'd0) && (instr_i[19:15] == 5'd0);
    assign is_fencei = (instr_i == 32'h0000_100f);
    assign is_system = (opcode == 7'b1110011);
    assign is_csr = is_system && (funct3 != 3'b000);
    assign is_ebreak = (instr_i == 32'h0010_0073);
    assign is_ecall = (instr_i == 32'h0000_0073);
    assign is_mret = (instr_i == 32'h3020_0073);
    assign is_sret = (instr_i == 32'h1020_0073);
    assign is_wfi = (instr_i == 32'h1050_0073);
    assign is_sfence_vma = is_system && (funct3 == 3'b000) &&
        (funct7 == 7'b0001001) && (instr_i[11:7] == 5'd0);
    assign is_m_extension = is_op && (funct7 == 7'b0000001);
    assign is_atomic_opcode = (opcode == 7'b0101111);
    assign is_supported_csr_op =
        is_csr &&
        ((funct3 == 3'b001) || (funct3 == 3'b010) || (funct3 == 3'b011) ||
         (funct3 == 3'b101) || (funct3 == 3'b110) || (funct3 == 3'b111));
    assign imm_i_c = {{20{instr_i[31]}}, instr_i[31:20]};
    assign imm_s_c = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
    assign imm_u_c = {instr_i[31:12], 12'b0};
    assign imm_b_c = {{20{instr_i[31]}}, instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
    assign imm_j_c = {{12{instr_i[31]}}, instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};

    always_comb begin
        alu_op_c = BBUS_OOO_ALU_ADD;
        mdu_op_c = BBUS_OOO_MDU_MUL;
        atomic_op_c = BBUS_OOO_AMO_LR;
        fu_type_c = BBUS_OOO_FU_NONE;
        branch_op_c = BBUS_OOO_BR_BEQ;
        mem_op_c = BBUS_OOO_MEM_NONE;
        op_recognized = 1'b0;
        op_enabled = 1'b0;
        uses_rs1_c = 1'b0;
        uses_rs2_c = 1'b0;
        src1_is_pc_c = 1'b0;
        src2_is_imm_c = 1'b0;
        imm_c = imm_i_c;

        unique case (funct3)
            3'b000: begin branch_op_c = BBUS_OOO_BR_BEQ;  mem_op_c = BBUS_OOO_MEM_B_S; end
            3'b001: begin branch_op_c = BBUS_OOO_BR_BNE;  mem_op_c = BBUS_OOO_MEM_H_S; end
            3'b010: begin branch_op_c = BBUS_OOO_BR_BLT;  mem_op_c = BBUS_OOO_MEM_W; end
            3'b011: begin branch_op_c = BBUS_OOO_BR_BGE;  mem_op_c = BBUS_OOO_MEM_NONE; end
            3'b100: begin branch_op_c = BBUS_OOO_BR_BLT;  mem_op_c = BBUS_OOO_MEM_B_U; end
            3'b101: begin branch_op_c = BBUS_OOO_BR_BGE;  mem_op_c = BBUS_OOO_MEM_H_U; end
            3'b110: begin branch_op_c = BBUS_OOO_BR_BLTU; mem_op_c = BBUS_OOO_MEM_NONE; end
            default: begin branch_op_c = BBUS_OOO_BR_BGEU; mem_op_c = BBUS_OOO_MEM_NONE; end
        endcase

        if (is_lui) begin
            fu_type_c = BBUS_OOO_FU_ALU;
            alu_op_c = BBUS_OOO_ALU_COPY_B;
            src2_is_imm_c = 1'b1;
            imm_c = imm_u_c;
            op_recognized = 1'b1;
            op_enabled = 1'b1;
        end else if (is_auipc) begin
            fu_type_c = BBUS_OOO_FU_ALU;
            alu_op_c = BBUS_OOO_ALU_ADD;
            src1_is_pc_c = 1'b1;
            src2_is_imm_c = 1'b1;
            imm_c = imm_u_c;
            op_recognized = 1'b1;
            op_enabled = 1'b1;
        end else if (is_op) begin
            fu_type_c = is_m_extension ? BBUS_OOO_FU_MDU : BBUS_OOO_FU_ALU;
            uses_rs1_c = 1'b1;
            uses_rs2_c = 1'b1;
            unique case ({funct7, funct3})
                {7'b0000000, 3'b000}: begin alu_op_c = BBUS_OOO_ALU_ADD;  op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b0100000, 3'b000}: begin alu_op_c = BBUS_OOO_ALU_SUB;  op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b0000000, 3'b001}: begin alu_op_c = BBUS_OOO_ALU_SLL;  op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b0000000, 3'b010}: begin alu_op_c = BBUS_OOO_ALU_SLT;  op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b0000000, 3'b011}: begin alu_op_c = BBUS_OOO_ALU_SLTU; op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b0000000, 3'b100}: begin alu_op_c = BBUS_OOO_ALU_XOR;  op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b0000000, 3'b101}: begin alu_op_c = BBUS_OOO_ALU_SRL;  op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b0100000, 3'b101}: begin alu_op_c = BBUS_OOO_ALU_SRA;  op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b0000000, 3'b110}: begin alu_op_c = BBUS_OOO_ALU_OR;   op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b0000000, 3'b111}: begin alu_op_c = BBUS_OOO_ALU_AND;  op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b0000001, 3'b000},
                {7'b0000001, 3'b001},
                {7'b0000001, 3'b010},
                {7'b0000001, 3'b011},
                {7'b0000001, 3'b100},
                {7'b0000001, 3'b101},
                {7'b0000001, 3'b110},
                {7'b0000001, 3'b111}: begin
                    alu_op_c = BBUS_OOO_ALU_ADD;
                    mdu_op_c = bbus_ooo_mdu_op_e'(funct3);
                    op_recognized = 1'b1;
`ifdef NPC_M_EXTENSION
                    op_enabled = 1'b1;
`else
                    op_enabled = 1'b0;
`endif
                end
                default: begin alu_op_c = BBUS_OOO_ALU_ADD; op_recognized = 1'b0; op_enabled = 1'b0; end
            endcase
        end else if (is_op_imm) begin
            fu_type_c = BBUS_OOO_FU_ALU;
            uses_rs1_c = 1'b1;
            src2_is_imm_c = 1'b1;
            unique casez ({funct7, funct3})
                {7'b???????, 3'b000}: begin alu_op_c = BBUS_OOO_ALU_ADD;  op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b???????, 3'b010}: begin alu_op_c = BBUS_OOO_ALU_SLT;  op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b???????, 3'b011}: begin alu_op_c = BBUS_OOO_ALU_SLTU; op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b???????, 3'b100}: begin alu_op_c = BBUS_OOO_ALU_XOR;  op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b???????, 3'b110}: begin alu_op_c = BBUS_OOO_ALU_OR;   op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b???????, 3'b111}: begin alu_op_c = BBUS_OOO_ALU_AND;  op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b0000000, 3'b001}: begin alu_op_c = BBUS_OOO_ALU_SLL;  op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b0000000, 3'b101}: begin alu_op_c = BBUS_OOO_ALU_SRL;  op_recognized = 1'b1; op_enabled = 1'b1; end
                {7'b0100000, 3'b101}: begin alu_op_c = BBUS_OOO_ALU_SRA;  op_recognized = 1'b1; op_enabled = 1'b1; end
                default: begin alu_op_c = BBUS_OOO_ALU_ADD; op_recognized = 1'b0; op_enabled = 1'b0; end
            endcase
        end else if (is_jal) begin
            fu_type_c = BBUS_OOO_FU_BRU;
            branch_op_c = BBUS_OOO_BR_JAL;
            imm_c = imm_j_c;
            op_recognized = 1'b1;
            op_enabled = 1'b1;
        end else if (is_jalr) begin
            fu_type_c = BBUS_OOO_FU_BRU;
            branch_op_c = BBUS_OOO_BR_JALR;
            uses_rs1_c = 1'b1;
            op_recognized = (funct3 == 3'b000);
            op_enabled = op_recognized;
        end else if (is_branch) begin
            fu_type_c = BBUS_OOO_FU_BRU;
            uses_rs1_c = 1'b1;
            uses_rs2_c = 1'b1;
            imm_c = imm_b_c;
            op_recognized =
                (funct3 == 3'b000) || (funct3 == 3'b001) ||
                (funct3 == 3'b100) || (funct3 == 3'b101) ||
                (funct3 == 3'b110) || (funct3 == 3'b111);
            op_enabled = op_recognized;
        end else if (is_atomic_opcode) begin
            fu_type_c = BBUS_OOO_FU_AMO;
            mem_op_c = BBUS_OOO_MEM_W;
            uses_rs1_c = 1'b1;
            uses_rs2_c = 1'b1;
            op_recognized = (funct3 == 3'b010);
            unique case (instr_i[31:27])
                5'b00010: begin
                    atomic_op_c = BBUS_OOO_AMO_LR;
                    uses_rs2_c = 1'b0;
                    op_recognized = op_recognized && (instr_i[24:20] == 5'd0);
                end
                5'b00011: atomic_op_c = BBUS_OOO_AMO_SC;
                5'b00001: atomic_op_c = BBUS_OOO_AMO_SWAP;
                5'b00000: atomic_op_c = BBUS_OOO_AMO_ADD;
                5'b00100: atomic_op_c = BBUS_OOO_AMO_XOR;
                5'b01100: atomic_op_c = BBUS_OOO_AMO_AND;
                5'b01000: atomic_op_c = BBUS_OOO_AMO_OR;
                5'b10000: atomic_op_c = BBUS_OOO_AMO_MIN;
                5'b10100: atomic_op_c = BBUS_OOO_AMO_MAX;
                5'b11000: atomic_op_c = BBUS_OOO_AMO_MINU;
                5'b11100: atomic_op_c = BBUS_OOO_AMO_MAXU;
                default: op_recognized = 1'b0;
            endcase
`ifdef NPC_A_EXTENSION
            op_enabled = op_recognized;
`else
            op_enabled = 1'b0;
`endif
        end else if (is_load) begin
            fu_type_c = BBUS_OOO_FU_LSU;
            uses_rs1_c = 1'b1;
            src2_is_imm_c = 1'b1;
            imm_c = imm_i_c;
            op_recognized =
                (funct3 == 3'b000) || (funct3 == 3'b001) ||
                (funct3 == 3'b010) || (funct3 == 3'b100) ||
                (funct3 == 3'b101);
            op_enabled = op_recognized;
        end else if (is_store) begin
            fu_type_c = BBUS_OOO_FU_LSU;
            uses_rs1_c = 1'b1;
            uses_rs2_c = 1'b1;
            imm_c = imm_s_c;
            op_recognized =
                (funct3 == 3'b000) || (funct3 == 3'b001) ||
                (funct3 == 3'b010);
            op_enabled = op_recognized;
        end else if (is_fence_opcode) begin
            fu_type_c = BBUS_OOO_FU_SYS;
            op_recognized = is_fence || is_fencei;
            op_enabled = op_recognized;
        end else if (is_system) begin
            fu_type_c = is_csr ? BBUS_OOO_FU_CSR : BBUS_OOO_FU_SYS;
            uses_rs1_c =
                (is_csr &&
                 !funct3[2] &&
                 !(((funct3 == 3'b010) || (funct3 == 3'b011)) && (instr_i[19:15] == 5'd0))) ||
                is_sfence_vma;
            uses_rs2_c = is_sfence_vma;
            op_recognized =
                is_ebreak ||
                is_ecall ||
                is_mret ||
                is_sret ||
                is_wfi ||
                is_sfence_vma ||
                is_csr;
            op_enabled = is_ebreak || is_ecall || is_mret || is_supported_csr_op;
`ifdef NPC_S_EXTENSION
            op_enabled = op_enabled || is_sret || is_wfi || is_sfence_vma;
`endif
        end

        precise_illegal_c = valid_i && !op_enabled;

        decode_uop_o = '0;
        decode_uop_o.valid = valid_i;
        decode_uop_o.pc = pc_i;
        decode_uop_o.instr = instr_i;
        decode_uop_o.arch_rs1 = instr_i[19:15];
        decode_uop_o.arch_rs2 = uses_rs2_c ? instr_i[24:20] : 5'd0;
        decode_uop_o.arch_rd = (is_branch || is_store) ? 5'd0 : instr_i[11:7];
        decode_uop_o.uses_rs1 = valid_i && op_enabled && uses_rs1_c;
        decode_uop_o.uses_rs2 = valid_i && op_enabled && uses_rs2_c;
        decode_uop_o.rf_wen =
            valid_i && op_enabled &&
            !is_branch &&
            !is_store &&
            !((is_system || is_fence_opcode) && !is_csr) &&
            (instr_i[11:7] != 5'd0);
        decode_uop_o.fu_type = precise_illegal_c ? BBUS_OOO_FU_SYS : fu_type_c;
        decode_uop_o.branch_op = branch_op_c;
        decode_uop_o.pred_taken = 1'b0;
        decode_uop_o.pred_target = pc_i + 32'd4;
        decode_uop_o.alu_op = alu_op_c;
        decode_uop_o.mdu_op = mdu_op_c;
        decode_uop_o.atomic_op = atomic_op_c;
        decode_uop_o.aq = valid_i && op_enabled && is_atomic_opcode && instr_i[26];
        decode_uop_o.rl = valid_i && op_enabled && is_atomic_opcode && instr_i[25];
        decode_uop_o.src1_is_pc = valid_i && op_enabled && src1_is_pc_c;
        decode_uop_o.src2_is_imm = valid_i && op_enabled && src2_is_imm_c;
        decode_uop_o.imm = imm_c;
        decode_uop_o.is_load = is_load;
        decode_uop_o.is_store = is_store;
        decode_uop_o.mem_op = mem_op_c;
        decode_uop_o.is_csr = is_csr;
        decode_uop_o.is_system = precise_illegal_c || is_system || is_fence_opcode;
        decode_uop_o.is_ebreak = is_ebreak;
        decode_uop_o.csr_addr = instr_i[31:20];
        decode_uop_o.unsupported_class = 1'b0;
        decode_uop_o.exception = '0;
        decode_uop_o.exception.valid = precise_illegal_c;
        decode_uop_o.exception.cause = precise_illegal_c ? 32'd2 : 32'b0;
        decode_uop_o.exception.tval = precise_illegal_c ? instr_i : 32'b0;
    end

    assign supported_o = valid_i && op_enabled;
    assign unsupported_o = valid_i && !op_enabled;
endmodule
