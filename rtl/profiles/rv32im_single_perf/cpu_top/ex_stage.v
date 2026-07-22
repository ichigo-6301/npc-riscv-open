`timescale 1ns / 1ps
`include "include/bbus_core_defs.svh"

module ex_stage (
    input clk,
    input rst_n,

    input ds_to_es_valid,
    output es_allowin,
    input ms_allowin,
    output es_to_ms_valid,

    input [31:0] ds_pc,
    input [31:0] ds_instr,
    input [31:0] ds_src1,
    input [31:0] ds_src2,
    input ds_src1_from_prev_ex,
    input ds_src2_from_prev_ex,
    input ds_src1_from_prev_wb,
    input ds_src2_from_prev_wb,
    input ds_pred_taken,
    input [31:0] ds_pred_target,
    input [31:0] ws_rf_wdata,
    input [31:0] ds_imm,
    input [31:0] ds_zimm,
    input [31:0] ds_scsr,
    input [4:0] ds_rd,
    input ds_reg_wen,
    input [2:0] ds_branch,
    input [1:0] ds_datatoreg,
    input [1:0] ds_mem_wr,
    input [2:0] ds_mem_op,
    input [1:0] ds_alu_a_src,
    input [1:0] ds_alu_b_src,
    input [3:0] ds_alu_ctr,
    input [1:0] ds_csr_wen,
    input [11:0] ds_csr_waddr1,
    input [11:0] ds_csr_waddr2,
    input [1:0] ds_csr_wdata_src1,
    input ds_csr_wdata_src2,
    input ds_illegal,
    input ds_is_ebreak,
`ifdef NPC_M_EXTENSION
    input ds_mdu_en,
    input [2:0] ds_mdu_op,
`endif

    output es_valid,
    output es_result_bypassable,
    output [31:0] es_pc,
    output [31:0] es_instr,
    output [31:0] es_nextpc,
    output [4:0] es_rd,
    output es_reg_wen,
    output [1:0] es_datatoreg,
    output [1:0] es_mem_wr,
    output [2:0] es_mem_op,
    output [31:0] es_aluout,
    output [31:0] es_mem_wdata,
    output [31:0] es_csr_read_data,
    output [1:0] es_csr_wen,
    output [11:0] es_csr_waddr1,
    output [11:0] es_csr_waddr2,
    output [31:0] es_csr_wdata1,
    output [31:0] es_csr_wdata2,
    output es_illegal,
    output es_is_ebreak,
    output [2:0] es_branch,
    output [31:0] es_src1_value,
    output es_mem_fwd_dep,
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    output es_stage_block,
    output es_stage_block_mdu_wait,
    output es_stage_block_redirect_wait,
`endif
`endif

    output flush_valid,
    output [31:0] flush_pc,
    output mispredict_flush_valid,
    output [31:0] mispredict_flush_pc,
    output branch_taken_actual
);
    reg es_valid_r;
    reg [31:0] es_pc_r;
    reg [31:0] es_instr_r;
    reg [31:0] es_src1_r;
    reg [31:0] es_src2_r;
    reg [31:0] es_seq_pc_r;
    reg [31:0] es_branch_target_r;
    reg es_pred_taken_r;
    reg [31:0] es_pred_target_r;
    reg es_src1_fwd_dep_r;
    reg es_src2_fwd_dep_r;
    reg [31:0] es_imm_r;
    reg [31:0] es_zimm_r;
    reg [31:0] es_scsr_r;
    reg [4:0] es_rd_r;
    reg es_reg_wen_r;
    reg [2:0] es_branch_r;
    reg es_is_j_r;
    reg es_is_jr_r;
    reg es_is_branch_e_r;
    reg es_is_beq_r;
    reg es_is_bne_r;
    reg es_is_blt_r;
    reg es_is_bge_r;
    reg [1:0] es_datatoreg_r;
    reg [1:0] es_mem_wr_r;
    reg [2:0] es_mem_op_r;
    reg [1:0] es_alu_a_src_r;
    reg [1:0] es_alu_b_src_r;
    reg [3:0] es_alu_ctr_r;
    reg [1:0] es_csr_wen_r;
    reg [11:0] es_csr_waddr1_r;
    reg [11:0] es_csr_waddr2_r;
    reg [1:0] es_csr_wdata_src1_r;
    reg es_csr_wdata_src2_r;
    reg es_illegal_r;
    reg es_is_ebreak_r;
`ifdef NPC_M_EXTENSION
    reg es_mdu_en_r;
    reg [2:0] es_mdu_op_r;

    wire es_is_mdu_op = es_mdu_en_r;

    // MDU interface
    wire mdu_req_valid;
    wire mdu_req_ready;
    wire [2:0] mdu_req_op;
    wire [31:0] mdu_req_src1;
    wire [31:0] mdu_req_src2;
    wire mdu_resp_valid;
    wire mdu_resp_ready;
    wire [31:0] mdu_resp_data;
    wire mdu_busy;
    reg mdu_result_valid_r;
    reg [31:0] mdu_result_data_r;
`endif

    // When an M instruction is in EX, stall until MDU responds.
`ifdef NPC_M_EXTENSION
    wire mdu_result_available = mdu_result_valid_r || mdu_resp_valid;
    wire [31:0] mdu_result_data = mdu_result_valid_r ? mdu_result_data_r : mdu_resp_data;
    wire es_ready_go_base = es_is_mdu_op ? mdu_result_available : 1'b1;
`else
    wire es_ready_go_base = 1'b1;
`endif
    wire es_stall = es_valid_r && !es_allowin;

    wire [31:0] es_src1_use = es_src1_r;
    wire [31:0] es_src2_use = es_src2_r;

    wire redirect_bypass_wait = 1'b0;

    wire [31:0] redirect_src1_use = es_src1_r;
    wire [31:0] redirect_src2_use = es_src2_r;

    wire es_ready_go = es_ready_go_base && !redirect_bypass_wait;
    wire es_mdu_wait =
`ifdef NPC_M_EXTENSION
        es_valid_r && es_is_mdu_op && !es_ready_go_base;
`else
        1'b0;
`endif

    wire [31:0] alu_a =
        (es_alu_a_src_r == 2'b00) ? es_src1_use :
        (es_alu_a_src_r == 2'b01) ? es_pc_r :
        es_zimm_r;

    wire [31:0] alu_b =
        (es_alu_b_src_r == 2'b00) ? es_src2_use :
        (es_alu_b_src_r == 2'b01) ? es_imm_r :
        (es_alu_b_src_r == 2'b10) ? 32'd4 :
        es_scsr_r;

    wire [31:0] nextpc;
    wire [31:0] nextpc_raw;
    wire [31:0] jalr_target_raw;
    wire [31:0] jalr_target;
    wire [31:0] aluout;
    wire less;
    wire zero;
    wire redirect_zero;
    wire redirect_less;
    wire [31:0] redirect_sub_result;
    wire redirect_sub_carry;
    wire redirect_sub_overflow;
    wire normal_redirect_taken;
    wire slowpath_redirect_taken;
    wire redirect_class_valid;
    wire target_mismatch;
    wire normal_redirect_mispredict;
    wire instr_addr_misaligned_trap;
    wire es_is_cond_branch = es_is_beq_r || es_is_bne_r || es_is_blt_r || es_is_bge_r;
    bbus_fu_e es_fu_class;
    bbus_uop_t es_uop_view;

    assign es_allowin = !es_valid_r || (es_ready_go && ms_allowin);
    assign es_to_ms_valid = es_valid_r && es_ready_go;

    assign es_valid = es_valid_r;
    assign es_result_bypassable = es_valid_r && es_reg_wen_r && !instr_addr_misaligned_trap &&
        (es_rd_r != 5'b0) &&
        (es_datatoreg_r == 2'b00) &&
`ifdef NPC_M_EXTENSION
        (!es_is_mdu_op || mdu_result_available);
`else
        1'b1;
`endif
    assign es_pc = es_pc_r;
    assign es_instr = es_instr_r;
    assign es_nextpc = nextpc;
    assign es_rd = es_rd_r;
    assign es_reg_wen = instr_addr_misaligned_trap ? 1'b0 : es_reg_wen_r;
    assign es_datatoreg = es_datatoreg_r;
    assign es_mem_wr = es_mem_wr_r;
    assign es_mem_op = es_mem_op_r;
    assign es_aluout =
`ifdef NPC_M_EXTENSION
        es_is_mdu_op ? mdu_result_data :
`endif
        aluout;
    assign es_mem_wdata = es_src2_use;
    // Trace only: memory op depends on forwarded source.
    // load: rs1 affects address; store: rs1(address) or rs2(data).
    assign es_mem_fwd_dep = es_valid_r && (es_mem_wr_r != 2'b00) &&
        (es_src1_fwd_dep_r ||
         ((es_mem_wr_r == 2'b11) && es_src2_fwd_dep_r));
    assign es_csr_read_data = es_scsr_r;
    assign es_csr_wen = instr_addr_misaligned_trap ? 2'b11 : es_csr_wen_r;
    assign es_csr_waddr1 = instr_addr_misaligned_trap ? 12'h342 : es_csr_waddr1_r;
    assign es_csr_waddr2 = instr_addr_misaligned_trap ? 12'h341 : es_csr_waddr2_r;
    assign es_csr_wdata1 =
        instr_addr_misaligned_trap ? 32'd0 :
        (es_csr_wdata_src1_r == 2'b00) ? es_src1_use :
        (es_csr_wdata_src1_r == 2'b01) ? es_zimm_r :
        (es_csr_wdata_src1_r == 2'b10) ? aluout :
        (es_instr_r == 32'h00000073) ? 32'd11 :
        (es_instr_r == 32'h00100073) ? 32'd3 :
        ((es_instr_r == 32'h30200073) && (es_csr_waddr1_r == 12'h300)) ? 32'h00000080 :
        ((es_instr_r == 32'h10200073) && (es_csr_waddr1_r == 12'h300)) ? 32'h00000020 :
        32'd2;
    assign es_csr_wdata2 = es_pc_r;
    assign es_illegal = es_illegal_r;
    assign es_is_ebreak = es_is_ebreak_r;
    assign es_branch = instr_addr_misaligned_trap ? `BBUS_BR_E : es_branch_r;
    assign es_src1_value = es_src1_use;
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    assign es_stage_block = es_valid_r && !es_ready_go;
    assign es_stage_block_mdu_wait = es_mdu_wait;
    assign es_stage_block_redirect_wait = es_valid_r && redirect_bypass_wait;
`endif
`endif

    assign jalr_target = jalr_target_raw & 32'hfffffffe;
    assign redirect_zero = (redirect_src1_use == redirect_src2_use);
    assign redirect_sub_result = redirect_src1_use + ~redirect_src2_use + 32'd1;
    assign redirect_sub_carry =
        (redirect_src1_use[31] & ~redirect_src2_use[31]) |
        ((redirect_src1_use[31] | ~redirect_src2_use[31]) & ~redirect_sub_result[31]);
    assign redirect_sub_overflow =
        (redirect_src1_use[31] & ~redirect_src2_use[31] & ~redirect_sub_result[31]) |
        (~redirect_src1_use[31] & redirect_src2_use[31] & redirect_sub_result[31]);
    assign redirect_less = es_alu_ctr_r[3] ?
        ~redirect_sub_carry :
        (redirect_sub_overflow ^ redirect_sub_result[31]);
    // normal_redirect_taken covers J/JR and conditional branch redirects that
    // may generate a same-cycle EX->IF fast redirect.
    assign normal_redirect_taken =
        es_is_j_r ||
        es_is_jr_r ||
        (es_is_beq_r && redirect_zero) ||
        (es_is_bne_r && !redirect_zero) ||
        (es_is_blt_r && redirect_less) ||
        (es_is_bge_r && !redirect_less);
    // slowpath_redirect_taken covers BR_E/trap-like prepare events. It may
    // request younger-instruction killing, but must not be part of the normal
    // fast mispredict cone.
    assign slowpath_redirect_taken = es_is_branch_e_r;

`ifdef NPC_RVTEST_TRAP_STUB
    assign instr_addr_misaligned_trap =
        (es_is_j_r && es_branch_target_r[1]) ||
        (es_is_jr_r && jalr_target[1]) ||
        (es_is_cond_branch && normal_redirect_taken && es_branch_target_r[1]);
`else
    assign instr_addr_misaligned_trap = 1'b0;
`endif

    assign es_fu_class =
`ifdef NPC_M_EXTENSION
        es_is_mdu_op ? BBUS_FU_MDU :
`endif
        (es_illegal_r || es_is_ebreak_r || es_is_branch_e_r ||
         instr_addr_misaligned_trap) ? BBUS_FU_SYS :
        (es_mem_wr_r != 2'b00) ? BBUS_FU_LSU :
        (es_csr_wen_r != 2'b00) ? BBUS_FU_CSR :
        (es_branch_r != `BBUS_BR_NONE) ? BBUS_FU_BRU :
        BBUS_FU_ALU;

    assign nextpc_raw =
        instr_addr_misaligned_trap ? es_scsr_r :
        es_is_jr_r ? jalr_target :
        es_is_branch_e_r ? es_scsr_r :
        normal_redirect_taken ? es_branch_target_r :
        es_seq_pc_r;

    assign nextpc = nextpc_raw;
    assign es_uop_view.valid = es_valid_r;
    assign es_uop_view.pc = es_pc_r;
    assign es_uop_view.instr = es_instr_r;
    assign es_uop_view.nextpc = nextpc;
    assign es_uop_view.rs1 = 5'b0;
    assign es_uop_view.rs2 = 5'b0;
    assign es_uop_view.rd = es_rd_r;
    assign es_uop_view.uses_rs1 = 1'b0;
    assign es_uop_view.uses_rs2 = 1'b0;
    assign es_uop_view.rf_wen = instr_addr_misaligned_trap ? 1'b0 : es_reg_wen_r;
    assign es_uop_view.fu = es_fu_class;
    assign es_uop_view.branch =
        bbus_branch_e'(instr_addr_misaligned_trap ? `BBUS_BR_E : es_branch_r);
    assign es_uop_view.imm = es_imm_r;
    assign es_uop_view.src1_value = es_src1_use;
    assign es_uop_view.src2_value = es_src2_use;
    assign es_uop_view.mem_wr = es_mem_wr_r;
    assign es_uop_view.mem_op = es_mem_op_r;
    assign es_uop_view.datatoreg = es_datatoreg_r;
    assign es_uop_view.csr_wen = instr_addr_misaligned_trap ? 2'b11 : es_csr_wen_r;
    assign es_uop_view.csr_waddr1 = instr_addr_misaligned_trap ? 12'h342 : es_csr_waddr1_r;
    assign es_uop_view.csr_waddr2 = instr_addr_misaligned_trap ? 12'h341 : es_csr_waddr2_r;
    assign es_uop_view.pred_taken = es_pred_taken_r;
    assign es_uop_view.pred_target = es_pred_target_r;
    assign es_uop_view.illegal = es_illegal_r;
    assign es_uop_view.is_ebreak = es_is_ebreak_r;
    assign es_uop_view.exc.valid = 1'b0;
    assign es_uop_view.exc.cause = 32'b0;
    assign es_uop_view.exc.tval = 32'b0;
    assign es_uop_view.exc.epc = 32'b0;
    /* verilator lint_off UNUSED */
    wire es_uop_view_unused = ^es_uop_view;
    /* verilator lint_on UNUSED */

    assign redirect_class_valid = normal_redirect_taken || slowpath_redirect_taken;
    assign flush_valid = es_valid_r && es_ready_go && redirect_class_valid;
    assign flush_pc = nextpc;
    assign branch_taken_actual = redirect_class_valid;
    assign target_mismatch =
        normal_redirect_taken && es_pred_taken_r && (nextpc != es_pred_target_r);
    assign normal_redirect_mispredict =
        (normal_redirect_taken != es_pred_taken_r) || target_mismatch;
    assign mispredict_flush_valid = es_valid_r && es_ready_go && normal_redirect_mispredict;
    assign mispredict_flush_pc = nextpc;

    ALU alu(
        .A(alu_a),
        .B(alu_b),
        .ALUctr(es_alu_ctr_r),
        .ALUout(aluout),
        .Less(less),
        .Zero(zero)
    );

    PCAdder jalr_pc_adder(
        .PCA(es_imm_r),
        .PCB(redirect_src1_use),
        // .Branch(3'b010): rs1 + imm, then clear low bits
        .NextPC(jalr_target_raw)
    );

`ifdef NPC_M_EXTENSION
    // MDU is decoupled from MEM back-pressure. EX latches the result locally
    // when MEM cannot accept it, avoiding a long ms_allowin -> MDU CE path.
    assign mdu_req_valid = es_valid_r && es_mdu_en_r && !mdu_result_valid_r && mdu_req_ready;
    assign mdu_req_op = es_mdu_op_r;
    assign mdu_req_src1 = es_src1_use;
    assign mdu_req_src2 = es_src2_use;
    assign mdu_resp_ready = 1'b1;

    Mdu mdu(
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(mdu_req_valid),
        .req_ready(mdu_req_ready),
        .req_op(mdu_req_op),
        .req_src1(mdu_req_src1),
        .req_src2(mdu_req_src2),
        .resp_valid(mdu_resp_valid),
        .resp_ready(mdu_resp_ready),
        .resp_data(mdu_resp_data),
        .busy(mdu_busy)
    );
`endif

    wire [31:0] es_result_data =
`ifdef NPC_M_EXTENSION
        es_is_mdu_op ? mdu_result_data :
`endif
        aluout;
    wire [31:0] ds_src1_final =
        ds_src1_from_prev_ex ? es_result_data :
        ds_src1_from_prev_wb ? ws_rf_wdata :
        ds_src1;
    wire [31:0] ds_src2_final =
        ds_src2_from_prev_ex ? es_result_data :
        ds_src2_from_prev_wb ? ws_rf_wdata :
        ds_src2;

    always @(posedge clk) begin
        if (!rst_n) begin
            es_valid_r <= 1'b0;
            es_pc_r <= 32'b0;
            es_instr_r <= 32'b0;
            es_src1_r <= 32'b0;
            es_src2_r <= 32'b0;
            es_seq_pc_r <= 32'b0;
            es_branch_target_r <= 32'b0;
            es_pred_taken_r <= 1'b0;
            es_pred_target_r <= 32'b0;
            es_src1_fwd_dep_r <= 1'b0;
            es_src2_fwd_dep_r <= 1'b0;
            es_imm_r <= 32'b0;
            es_zimm_r <= 32'b0;
            es_scsr_r <= 32'b0;
            es_rd_r <= 5'b0;
            es_reg_wen_r <= 1'b0;
            es_branch_r <= `BBUS_BR_NONE;
            es_is_j_r <= 1'b0;
            es_is_jr_r <= 1'b0;
            es_is_branch_e_r <= 1'b0;
            es_is_beq_r <= 1'b0;
            es_is_bne_r <= 1'b0;
            es_is_blt_r <= 1'b0;
            es_is_bge_r <= 1'b0;
            es_datatoreg_r <= 2'b00;
            es_mem_wr_r <= 2'b00;
            es_mem_op_r <= 3'b000;
            es_alu_a_src_r <= 2'b00;
            es_alu_b_src_r <= 2'b00;
            es_alu_ctr_r <= 4'b0000;
            es_csr_wen_r <= 2'b00;
            es_csr_waddr1_r <= 12'b0;
            es_csr_waddr2_r <= 12'b0;
            es_csr_wdata_src1_r <= 2'b00;
            es_csr_wdata_src2_r <= 1'b0;
            es_illegal_r <= 1'b0;
            es_is_ebreak_r <= 1'b0;
`ifdef NPC_M_EXTENSION
            es_mdu_en_r <= 1'b0;
            es_mdu_op_r <= 3'b0;
            mdu_result_valid_r <= 1'b0;
            mdu_result_data_r <= 32'b0;
`endif
        end else begin
            if (es_allowin) begin
            es_valid_r <= ds_to_es_valid;
            es_pc_r <= ds_pc;
            es_instr_r <= ds_instr;
            es_src1_r <= ds_src1_final;
            es_src2_r <= ds_src2_final;
            es_seq_pc_r <= ds_pc + 32'd4;
            es_branch_target_r <= ds_pc + ds_imm;
            es_pred_taken_r <= ds_pred_taken;
            es_pred_target_r <= ds_pred_target;
            es_src1_fwd_dep_r <= ds_src1_from_prev_ex | ds_src1_from_prev_wb;
            es_src2_fwd_dep_r <= ds_src2_from_prev_ex | ds_src2_from_prev_wb;
            es_imm_r <= ds_imm;
            es_zimm_r <= ds_zimm;
            es_scsr_r <= ds_scsr;
            es_rd_r <= ds_rd;
            es_reg_wen_r <= ds_reg_wen;
            es_branch_r <= ds_branch;
            es_is_j_r <= (ds_branch == `BBUS_BR_J);
            es_is_jr_r <= (ds_branch == `BBUS_BR_JR);
            es_is_branch_e_r <= (ds_branch == `BBUS_BR_E);
            es_is_beq_r <= (ds_branch == `BBUS_BR_BEQ);
            es_is_bne_r <= (ds_branch == `BBUS_BR_BNE);
            es_is_blt_r <= (ds_branch == `BBUS_BR_BLT);
            es_is_bge_r <= (ds_branch == `BBUS_BR_BGE);
            es_datatoreg_r <= ds_datatoreg;
            es_mem_wr_r <= ds_mem_wr;
            es_mem_op_r <= ds_mem_op;
            es_alu_a_src_r <= ds_alu_a_src;
            es_alu_b_src_r <= ds_alu_b_src;
            es_alu_ctr_r <= ds_alu_ctr;
            es_csr_wen_r <= ds_csr_wen;
            es_csr_waddr1_r <= ds_csr_waddr1;
            es_csr_waddr2_r <= ds_csr_waddr2;
            es_csr_wdata_src1_r <= ds_csr_wdata_src1;
            es_csr_wdata_src2_r <= ds_csr_wdata_src2;
            es_illegal_r <= ds_illegal;
            es_is_ebreak_r <= ds_is_ebreak;
`ifdef NPC_M_EXTENSION
            es_mdu_en_r <= ds_mdu_en;
            es_mdu_op_r <= ds_mdu_op;
            mdu_result_valid_r <= 1'b0;
            mdu_result_data_r <= 32'b0;
`endif
            end else if (es_stall) begin
`ifdef NPC_M_EXTENSION
                if (mdu_resp_valid && !mdu_result_valid_r) begin
                    mdu_result_valid_r <= 1'b1;
                    mdu_result_data_r <= mdu_resp_data;
                end
`endif
            end
        end
    end

endmodule
