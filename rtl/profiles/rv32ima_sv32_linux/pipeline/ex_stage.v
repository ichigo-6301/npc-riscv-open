`timescale 1ns / 1ps

module ex_stage (
    input clk,
    input rst_n,
    input flush,

    input ds_to_es_valid,
    output es_allowin,
    input ms_allowin,
    output es_to_ms_valid,

    input [31:0] ds_pc,
    input [31:0] ds_instr,
    input ds_exc_valid,
    input [31:0] ds_exc_cause,
    input [31:0] ds_exc_tval,
    input [4:0] ds_rs1,
    input [4:0] ds_rs2,
    input [31:0] ds_src1,
    input [31:0] ds_src2,
    input ds_src1_from_prev_ex,
    input ds_src2_from_prev_ex,
    input ds_src1_from_prev_wb,
    input ds_src2_from_prev_wb,
    input ds_pred_taken,
    input [31:0] ds_pred_target,
    input ds_pred_btb_hit,
    input ds_pred_btb_is_cond,
    input [1:0] ds_pred_bht_state,
    input [31:0] ds_pred_pht_idx,
    input [31:0] ws_rf_wdata,
    input ms_alu_fwd_valid,
    input [4:0] ms_alu_fwd_rd,
    input [31:0] ms_alu_fwd_data,
    input ms_fast_mul_stat,
    input ms_load_bypass_valid,
    input [4:0] ms_load_bypass_rd,
    input [31:0] ms_load_bypass_data,
    input hidden_alu_fwd_valid,
    input [4:0] hidden_alu_fwd_rd,
    input [31:0] hidden_alu_fwd_data,
    input hidden_alu_fwd_fast_mul_stat,
    input ws_alu_fwd_valid,
    input [4:0] ws_alu_fwd_rd,
    input [31:0] ws_alu_fwd_data,
    input ws_load_fwd_valid,
    input [4:0] ws_load_fwd_rd,
    input [31:0] ws_load_fwd_data,
    input ws_fast_mul_stat,
    input [31:0] ds_imm,
    input [31:0] ds_zimm,
    input [31:0] ds_scsr,
    input [4:0] ds_rd,
    input ds_reg_wen,
    input [2:0] ds_branch,
    input [1:0] ds_datatoreg,
    input [1:0] ds_mem_wr,
    input [2:0] ds_mem_op,
    input ds_atomic_en,
    input [3:0] ds_atomic_op,
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
    output es_atomic_en,
    output [3:0] es_atomic_op,
    output [31:0] es_aluout,
    output [31:0] es_mem_wdata,
    output [31:0] es_csr_read_data,
    output [1:0] es_csr_wen,
    output [11:0] es_csr_waddr1,
    output [11:0] es_csr_waddr2,
    output [31:0] es_csr_wdata1,
    output [31:0] es_csr_wdata2,
    output es_illegal,
    output es_exc_valid,
    output [31:0] es_exc_cause,
    output [31:0] es_exc_tval,
    output es_is_ebreak,
    output [2:0] es_branch,
    output [31:0] es_src1_value,
    output es_mem_fwd_dep,
    output atomic_alu_ready,
    input atomic_alu_req_valid,
    input [3:0] atomic_alu_op,
    input [31:0] atomic_alu_old,
    input [31:0] atomic_alu_rs2,
    output atomic_alu_resp_valid,
    output [31:0] atomic_alu_result,
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    output es_stage_block,
    output es_stage_block_mdu_wait,
    output es_stage_block_redirect_wait,
    output es_stat_is_mdu,
    output es_stat_rs1_mem_alu_fwd,
    output es_stat_rs2_mem_alu_fwd,
    output es_stat_rs1_wb_fwd,
    output es_stat_rs2_wb_fwd,
    output es_stat_rs1_load_fwd,
    output es_stat_rs2_load_fwd,
    output [2:0] es_stat_mdu_op,
    output es_stat_mdu_req_fire,
    output es_stat_mdu_resp_valid,
    output es_stat_mdu_busy,
    output es_stat_mdu_result_ready,
    output es_stat_fast_mul,
    output es_stat_fast_mul_issue,
    output es_stat_fast_mul_resp,
    output es_stat_fast_mul_kill,
    output es_stat_fast_mul_flush_drop,
    output es_stat_fast_mul_forward,
    output es_stat_fast_mul_stall_wait_ready,
    output es_stat_old_div_path,
    output es_stat_old_rem_path,
`endif
`endif

    output flush_valid,
    output [31:0] flush_pc,
    output mispredict_flush_valid,
    output [31:0] mispredict_flush_pc,
    output branch_taken_actual,
    output branch_pred_taken,
    output [31:0] branch_pred_target,
    output branch_pred_btb_hit,
    output branch_pred_btb_is_cond,
    output [1:0] branch_pred_bht_state,
    output [31:0] branch_pred_pht_idx,
    output branch_target_mismatch
);
    reg es_valid_r;
    reg [31:0] es_pc_r;
    reg [31:0] es_instr_r;
    reg es_fetch_exc_valid_r;
    reg [31:0] es_fetch_exc_cause_r;
    reg [31:0] es_fetch_exc_tval_r;
    reg [4:0] es_rs1_r;
    reg [4:0] es_rs2_r;
    reg [31:0] es_src1_r;
    reg [31:0] es_src2_r;
    reg [31:0] es_seq_pc_r;
    reg [31:0] es_branch_target_r;
    reg es_pred_taken_r;
    reg [31:0] es_pred_target_r;
    reg es_pred_btb_hit_r;
    reg es_pred_btb_is_cond_r;
    reg [1:0] es_pred_bht_state_r;
    reg [31:0] es_pred_pht_idx_r;
    reg [31:0] es_src1_hold_r;
    reg [31:0] es_src2_hold_r;
    reg es_src1_hold_valid_r;
    reg es_src2_hold_valid_r;
    reg [31:0] es_imm_r;
    reg [31:0] es_zimm_r;
    reg [31:0] es_scsr_r;
    reg [4:0] es_rd_r;
    reg es_reg_wen_r;
    reg [2:0] es_branch_r;
    reg [1:0] es_datatoreg_r;
    reg [1:0] es_mem_wr_r;
    reg [2:0] es_mem_op_r;
    reg es_atomic_en_r;
    reg [3:0] es_atomic_op_r;
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

    wire es_mdu_op_is_mul = (es_mdu_op_r == 3'd0) || (es_mdu_op_r == 3'd1) ||
        (es_mdu_op_r == 3'd2) || (es_mdu_op_r == 3'd3);
    wire es_mdu_op_is_div = (es_mdu_op_r == 3'd4) || (es_mdu_op_r == 3'd5);
    wire es_mdu_op_is_rem = (es_mdu_op_r == 3'd6) || (es_mdu_op_r == 3'd7);
`ifdef NPC_FAST_MUL
    wire es_fast_mul_op = es_mdu_en_r && es_mdu_op_is_mul;
`else
    wire es_fast_mul_op = 1'b0;
`endif
    wire es_old_mdu_op = es_mdu_en_r && !es_fast_mul_op;
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
    reg mdu_req_sent_r;
`endif

    // When an M instruction is in EX, stall until MDU responds.
`ifdef NPC_M_EXTENSION
    wire mdu_result_available = mdu_result_valid_r || (mdu_resp_valid && mdu_req_sent_r);
    wire [31:0] mdu_result_data = mdu_result_valid_r ? mdu_result_data_r : mdu_resp_data;
    wire es_ready_go_base = es_old_mdu_op ? mdu_result_available : 1'b1;
`else
    wire es_ready_go_base = 1'b1;
`endif
    wire es_stall = es_valid_r && !es_allowin;

    wire rs1_mem_alu_fwd = es_valid_r && (es_rs1_r != 5'b0) &&
        ms_alu_fwd_valid && (ms_alu_fwd_rd == es_rs1_r);
    wire rs2_mem_alu_fwd = es_valid_r && (es_rs2_r != 5'b0) &&
        ms_alu_fwd_valid && (ms_alu_fwd_rd == es_rs2_r);
    wire rs1_hidden_alu_fwd = es_valid_r && !rs1_mem_alu_fwd && (es_rs1_r != 5'b0) &&
        hidden_alu_fwd_valid && (hidden_alu_fwd_rd == es_rs1_r);
    wire rs2_hidden_alu_fwd = es_valid_r && !rs2_mem_alu_fwd && (es_rs2_r != 5'b0) &&
        hidden_alu_fwd_valid && (hidden_alu_fwd_rd == es_rs2_r);
    wire rs1_load_fwd = es_valid_r && !rs1_mem_alu_fwd && !rs1_hidden_alu_fwd &&
        (es_rs1_r != 5'b0) && ms_load_bypass_valid && (ms_load_bypass_rd == es_rs1_r);
    wire rs2_load_fwd = es_valid_r && !rs2_mem_alu_fwd && !rs2_hidden_alu_fwd &&
        (es_rs2_r != 5'b0) && ms_load_bypass_valid && (ms_load_bypass_rd == es_rs2_r);
    wire rs1_wb_alu_fwd = es_valid_r && !rs1_mem_alu_fwd && !rs1_hidden_alu_fwd &&
        !rs1_load_fwd && (es_rs1_r != 5'b0) &&
        ws_alu_fwd_valid && (ws_alu_fwd_rd == es_rs1_r);
    wire rs2_wb_alu_fwd = es_valid_r && !rs2_mem_alu_fwd && !rs2_hidden_alu_fwd &&
        !rs2_load_fwd && (es_rs2_r != 5'b0) &&
        ws_alu_fwd_valid && (ws_alu_fwd_rd == es_rs2_r);
    wire rs1_wb_load_fwd = es_valid_r && !rs1_mem_alu_fwd && !rs1_hidden_alu_fwd &&
        !rs1_load_fwd && !rs1_wb_alu_fwd && (es_rs1_r != 5'b0) &&
        ws_load_fwd_valid && (ws_load_fwd_rd == es_rs1_r);
    wire rs2_wb_load_fwd = es_valid_r && !rs2_mem_alu_fwd && !rs2_hidden_alu_fwd &&
        !rs2_load_fwd && !rs2_wb_alu_fwd && (es_rs2_r != 5'b0) &&
        ws_load_fwd_valid && (ws_load_fwd_rd == es_rs2_r);
    wire rs1_wb_fwd = rs1_wb_alu_fwd || rs1_wb_load_fwd;
    wire rs2_wb_fwd = rs2_wb_alu_fwd || rs2_wb_load_fwd;

    wire [31:0] es_src1_base = es_src1_hold_valid_r ? es_src1_hold_r : es_src1_r;
    wire [31:0] es_src2_base = es_src2_hold_valid_r ? es_src2_hold_r : es_src2_r;
    wire [31:0] es_src1_use =
        rs1_mem_alu_fwd ? ms_alu_fwd_data :
        rs1_hidden_alu_fwd ? hidden_alu_fwd_data :
        rs1_load_fwd ? ms_load_bypass_data :
        rs1_wb_alu_fwd ? ws_alu_fwd_data :
        rs1_wb_load_fwd ? ws_load_fwd_data :
        es_src1_base;
    wire [31:0] es_src2_use =
        rs2_mem_alu_fwd ? ms_alu_fwd_data :
        rs2_hidden_alu_fwd ? hidden_alu_fwd_data :
        rs2_load_fwd ? ms_load_bypass_data :
        rs2_wb_alu_fwd ? ws_alu_fwd_data :
        rs2_wb_load_fwd ? ws_load_fwd_data :
        es_src2_base;

    wire redirect_bypass_wait = 1'b0;

    wire [31:0] redirect_src1_use = es_src1_use;
    wire [31:0] redirect_src2_use = es_src2_use;

    wire es_ready_go = es_ready_go_base && !redirect_bypass_wait;
    wire es_mdu_wait =
`ifdef NPC_M_EXTENSION
        es_valid_r && es_old_mdu_op && !es_ready_go_base;
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
    wire use_atomic_alu = atomic_alu_req_valid && !es_valid_r;
    wire [3:0] atomic_alu_ctr =
        (atomic_alu_op == 4'd4) ? 4'b0000 : // add
        (atomic_alu_op == 4'd5) ? 4'b0100 : // xor
        (atomic_alu_op == 4'd6) ? 4'b0111 : // and
        (atomic_alu_op == 4'd7) ? 4'b0110 : // or
        (atomic_alu_op == 4'd8) ? 4'b0010 : // min (signed less)
        (atomic_alu_op == 4'd9) ? 4'b0010 : // max (signed less)
        (atomic_alu_op == 4'd10) ? 4'b1010 : // minu (unsigned less)
        (atomic_alu_op == 4'd11) ? 4'b1010 : // maxu (unsigned less)
        4'b1011; // swap / fallback: pass A
    wire [31:0] alu_mux_a = use_atomic_alu ? atomic_alu_old : alu_a;
    wire [31:0] alu_mux_b = use_atomic_alu ? atomic_alu_rs2 : alu_b;
    wire [3:0] alu_mux_ctr = use_atomic_alu ? atomic_alu_ctr : es_alu_ctr_r;

    wire [31:0] nextpc;
    wire [31:0] nextpc_raw;
    wire [31:0] jalr_target_raw;
    wire [31:0] jalr_target;
    wire [31:0] aluout;
    wire less;
    wire zero;
    wire es_is_csr_op;
    wire [2:0] es_csr_funct3;
    wire [31:0] es_csr_operand;
    reg [31:0] es_csr_write_value;
    wire redirect_zero;
    wire redirect_less;
    wire [31:0] redirect_sub_result;
    wire redirect_sub_carry;
    wire redirect_sub_overflow;
    wire branch_taken;
    wire redirect_raw;
    wire target_mismatch;
    wire mispredict_raw;
    wire target_misaligned;

    assign es_allowin = !es_valid_r || (es_ready_go && ms_allowin);
    assign es_to_ms_valid = es_valid_r && es_ready_go;

    assign es_valid = es_valid_r;
    assign es_result_bypassable = es_valid_r && es_reg_wen_r && (es_rd_r != 5'b0) &&
        (es_datatoreg_r == 2'b00) &&
        (es_mem_wr_r == 2'b00) && !es_atomic_en_r && (es_csr_wen_r == 2'b00) &&
        !es_fetch_exc_valid_r && !target_misaligned && !es_illegal_r &&
`ifdef NPC_M_EXTENSION
        !es_is_mdu_op;
`else
        1'b1;
`endif
    assign es_pc = es_pc_r;
    assign es_instr = es_instr_r;
    assign es_nextpc = nextpc;
    assign es_rd = es_rd_r;
    assign es_reg_wen = es_reg_wen_r;
    assign es_datatoreg = es_datatoreg_r;
    assign es_mem_wr = es_mem_wr_r;
    assign es_mem_op = es_mem_op_r;
    assign es_atomic_en = es_atomic_en_r;
    assign es_atomic_op = es_atomic_op_r;
`ifdef NPC_M_EXTENSION
    wire signed [63:0] fast_mul_src1_s = {{32{es_src1_use[31]}}, es_src1_use};
    wire signed [63:0] fast_mul_src2_s = {{32{es_src2_use[31]}}, es_src2_use};
    wire signed [63:0] fast_mul_src2_u_s = {32'b0, es_src2_use};
    wire [63:0] fast_mul_src1_u = {32'b0, es_src1_use};
    wire [63:0] fast_mul_src2_u = {32'b0, es_src2_use};
    wire signed [127:0] fast_mul_ss = fast_mul_src1_s * fast_mul_src2_s;
    wire [127:0] fast_mul_uu = fast_mul_src1_u * fast_mul_src2_u;
    wire signed [127:0] fast_mul_su = fast_mul_src1_s * fast_mul_src2_u_s;
    wire [63:0] fast_mul_product =
        (es_mdu_op_r == 3'd1) ? fast_mul_ss[63:0] :
        (es_mdu_op_r == 3'd2) ? fast_mul_su[63:0] :
        (es_mdu_op_r == 3'd3) ? fast_mul_uu[63:0] :
        fast_mul_uu[63:0];
    wire [31:0] fast_mul_result =
        (es_mdu_op_r == 3'd0) ? fast_mul_product[31:0] :
        fast_mul_product[63:32];
`endif
    assign es_aluout =
`ifdef NPC_M_EXTENSION
        es_old_mdu_op ? mdu_result_data :
        es_fast_mul_op ? fast_mul_result :
`endif
        aluout;
    assign es_mem_wdata = es_src2_use;
    // Trace only: memory op depends on forwarded source.
    // load: rs1 affects address; store: rs1(address) or rs2(data).
    assign es_mem_fwd_dep = es_valid_r && (es_mem_wr_r != 2'b00) &&
        (es_src1_hold_valid_r ||
         rs1_mem_alu_fwd || rs1_wb_fwd ||
         rs1_hidden_alu_fwd ||
         ((es_mem_wr_r == 2'b11) &&
          (es_src2_hold_valid_r || rs2_mem_alu_fwd ||
           rs2_hidden_alu_fwd || rs2_wb_fwd)));
    assign atomic_alu_ready = !es_valid_r;
    assign atomic_alu_resp_valid = use_atomic_alu;
    assign atomic_alu_result =
        (atomic_alu_op == 4'd3) ? atomic_alu_rs2 : // swap
        ((atomic_alu_op == 4'd8) || (atomic_alu_op == 4'd10)) ? (less ? atomic_alu_old : atomic_alu_rs2) : // min/minu
        ((atomic_alu_op == 4'd9) || (atomic_alu_op == 4'd11)) ? (less ? atomic_alu_rs2 : atomic_alu_old) : // max/maxu
        aluout;
    assign es_csr_read_data = es_scsr_r;
    assign es_csr_wen = es_csr_wen_r;
    assign es_csr_waddr1 = es_csr_waddr1_r;
    assign es_csr_waddr2 = es_csr_waddr2_r;
    assign es_csr_wdata1 = es_is_csr_op ? es_csr_write_value :
        ((es_csr_wdata_src1_r == 2'b00) ? es_src1_use :
        (es_csr_wdata_src1_r == 2'b01) ? es_zimm_r :
        (es_csr_wdata_src1_r == 2'b10) ? aluout :
        32'd11);
    assign es_csr_wdata2 = es_pc_r;
    assign es_illegal = es_illegal_r;
    assign es_exc_valid = es_valid_r && (es_fetch_exc_valid_r || target_misaligned);
    assign es_exc_cause = es_fetch_exc_valid_r ? es_fetch_exc_cause_r : 32'd0;
    assign es_exc_tval = es_fetch_exc_valid_r ? es_fetch_exc_tval_r : nextpc;
    assign es_is_ebreak = es_is_ebreak_r;
    assign es_branch = es_branch_r;
    assign es_src1_value = es_src1_use;
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    assign es_stage_block = es_valid_r && !es_ready_go;
    assign es_stage_block_mdu_wait = es_mdu_wait;
    assign es_stage_block_redirect_wait = es_valid_r && redirect_bypass_wait;
`ifdef NPC_M_EXTENSION
    assign es_stat_is_mdu = es_valid_r && es_is_mdu_op;
`else
    assign es_stat_is_mdu = 1'b0;
`endif
    assign es_stat_rs1_mem_alu_fwd = rs1_mem_alu_fwd || rs1_hidden_alu_fwd;
    assign es_stat_rs2_mem_alu_fwd = rs2_mem_alu_fwd || rs2_hidden_alu_fwd;
    assign es_stat_rs1_wb_fwd = rs1_wb_fwd;
    assign es_stat_rs2_wb_fwd = rs2_wb_fwd;
    assign es_stat_rs1_load_fwd = rs1_load_fwd || rs1_wb_load_fwd;
    assign es_stat_rs2_load_fwd = rs2_load_fwd || rs2_wb_load_fwd;
`ifdef NPC_M_EXTENSION
    assign es_stat_mdu_op = es_mdu_op_r;
    assign es_stat_mdu_req_fire = mdu_req_fire;
    assign es_stat_mdu_resp_valid = mdu_resp_valid;
    assign es_stat_mdu_busy = mdu_busy;
    assign es_stat_mdu_result_ready = es_fast_mul_op ? es_valid_r : mdu_result_available;
    assign es_stat_fast_mul = es_valid_r && es_fast_mul_op;
    assign es_stat_fast_mul_issue = es_to_ms_valid && es_fast_mul_op;
    assign es_stat_fast_mul_resp = 1'b0;
    assign es_stat_fast_mul_kill = 1'b0;
    assign es_stat_fast_mul_flush_drop = flush && es_valid_r && es_fast_mul_op;
    assign es_stat_fast_mul_forward =
        ((rs1_mem_alu_fwd || rs2_mem_alu_fwd) && ms_fast_mul_stat) ||
        ((rs1_hidden_alu_fwd || rs2_hidden_alu_fwd) && hidden_alu_fwd_fast_mul_stat) ||
        ((rs1_wb_fwd || rs2_wb_fwd) && ws_fast_mul_stat);
    assign es_stat_fast_mul_stall_wait_ready = 1'b0;
    assign es_stat_old_div_path = mdu_req_fire && es_mdu_op_is_div;
    assign es_stat_old_rem_path = mdu_req_fire && es_mdu_op_is_rem;
`else
    assign es_stat_mdu_op = 3'b0;
    assign es_stat_mdu_req_fire = 1'b0;
    assign es_stat_mdu_resp_valid = 1'b0;
    assign es_stat_mdu_busy = 1'b0;
    assign es_stat_mdu_result_ready = 1'b0;
    assign es_stat_fast_mul = 1'b0;
    assign es_stat_fast_mul_issue = 1'b0;
    assign es_stat_fast_mul_resp = 1'b0;
    assign es_stat_fast_mul_kill = 1'b0;
    assign es_stat_fast_mul_flush_drop = 1'b0;
    assign es_stat_fast_mul_forward = 1'b0;
    assign es_stat_fast_mul_stall_wait_ready = 1'b0;
    assign es_stat_old_div_path = 1'b0;
    assign es_stat_old_rem_path = 1'b0;
`endif
`endif
`endif

    assign branch_taken =
        (es_branch_r == 3'b001) ? 1'b1 :
        (es_branch_r == 3'b010) ? 1'b1 :
        (es_branch_r == 3'b011) ? 1'b1 :
        (es_branch_r == 3'b100) ? redirect_zero :
        (es_branch_r == 3'b101) ? !redirect_zero :
        (es_branch_r == 3'b110) ? redirect_less :
        (es_branch_r == 3'b111) ? !redirect_less :
        1'b0;

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

    assign es_is_csr_op = (es_instr_r[6:0] == 7'b1110011) && (es_instr_r[14:12] != 3'b000);
    assign es_csr_funct3 = es_instr_r[14:12];
    assign es_csr_operand = es_csr_funct3[2] ? es_zimm_r : es_src1_use;

    always @(*) begin
        case (es_csr_funct3)
            3'b001, 3'b101: es_csr_write_value = es_csr_operand;              // csrrw/csrrwi
            3'b010, 3'b110: es_csr_write_value = es_scsr_r | es_csr_operand;  // csrrs/csrrsi
            3'b011, 3'b111: es_csr_write_value = es_scsr_r & ~es_csr_operand; // csrrc/csrrci
            default:        es_csr_write_value = aluout;
        endcase
    end

    assign nextpc_raw =
        (es_branch_r == 3'b010) ? jalr_target :
        (es_branch_r == 3'b011) ? es_scsr_r :
        branch_taken ? es_branch_target_r :
        es_seq_pc_r;

    assign nextpc = nextpc_raw;
    assign redirect_raw = branch_taken;
    assign target_misaligned = branch_taken && (nextpc[1:0] != 2'b00);
    assign flush_valid = es_valid_r && es_ready_go && redirect_raw && !target_misaligned;
    assign flush_pc = nextpc;
    assign branch_taken_actual = redirect_raw;
    assign branch_pred_taken = es_pred_taken_r;
    assign branch_pred_target = es_pred_target_r;
    assign branch_pred_btb_hit = es_pred_btb_hit_r;
    assign branch_pred_btb_is_cond = es_pred_btb_is_cond_r;
    assign branch_pred_bht_state = es_pred_bht_state_r;
    assign branch_pred_pht_idx = es_pred_pht_idx_r;
    assign branch_target_mismatch = target_mismatch;
    assign target_mismatch = redirect_raw && es_pred_taken_r && (nextpc != es_pred_target_r);
    assign mispredict_raw = (redirect_raw != es_pred_taken_r) || target_mismatch;
    assign mispredict_flush_valid = es_valid_r && es_ready_go && mispredict_raw && !target_misaligned;
    assign mispredict_flush_pc = nextpc;

    ALU alu(
        .A(alu_mux_a),
        .B(alu_mux_b),
        .ALUctr(alu_mux_ctr),
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
    wire mdu_req_fire;
    assign mdu_req_valid = es_valid_r && es_old_mdu_op && !mdu_result_valid_r && !mdu_req_sent_r;
    assign mdu_req_fire = mdu_req_valid && mdu_req_ready;
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
        es_old_mdu_op ? mdu_result_data :
        es_fast_mul_op ? fast_mul_result :
`endif
        aluout;

    always @(posedge clk) begin
        if (!rst_n) begin
            es_valid_r <= 1'b0;
            es_pc_r <= 32'b0;
            es_instr_r <= 32'b0;
            es_fetch_exc_valid_r <= 1'b0;
            es_fetch_exc_cause_r <= 32'b0;
            es_fetch_exc_tval_r <= 32'b0;
            es_rs1_r <= 5'b0;
            es_rs2_r <= 5'b0;
            es_src1_r <= 32'b0;
            es_src2_r <= 32'b0;
            es_seq_pc_r <= 32'b0;
            es_branch_target_r <= 32'b0;
            es_pred_taken_r <= 1'b0;
            es_pred_target_r <= 32'b0;
            es_pred_btb_hit_r <= 1'b0;
            es_pred_btb_is_cond_r <= 1'b0;
            es_pred_bht_state_r <= 2'b0;
            es_pred_pht_idx_r <= 32'b0;
            es_src1_hold_r <= 32'b0;
            es_src2_hold_r <= 32'b0;
            es_src1_hold_valid_r <= 1'b0;
            es_src2_hold_valid_r <= 1'b0;
            es_imm_r <= 32'b0;
            es_zimm_r <= 32'b0;
            es_scsr_r <= 32'b0;
            es_rd_r <= 5'b0;
            es_reg_wen_r <= 1'b0;
            es_branch_r <= 3'b000;
            es_datatoreg_r <= 2'b00;
            es_mem_wr_r <= 2'b00;
            es_mem_op_r <= 3'b000;
            es_atomic_en_r <= 1'b0;
            es_atomic_op_r <= 4'b0;
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
            mdu_req_sent_r <= 1'b0;
`endif
        end else if (flush) begin
            es_valid_r <= 1'b0;
            es_src1_hold_valid_r <= 1'b0;
            es_src2_hold_valid_r <= 1'b0;
`ifdef NPC_M_EXTENSION
            mdu_result_valid_r <= 1'b0;
            mdu_req_sent_r <= 1'b0;
`endif
        end else begin
            if (es_allowin) begin
            es_valid_r <= ds_to_es_valid;
            es_pc_r <= ds_pc;
            es_instr_r <= ds_instr;
            es_fetch_exc_valid_r <= ds_exc_valid;
            es_fetch_exc_cause_r <= ds_exc_cause;
            es_fetch_exc_tval_r <= ds_exc_tval;
            es_rs1_r <= ds_rs1;
            es_rs2_r <= ds_rs2;
            es_src1_r <= ds_src1;
            es_src2_r <= ds_src2;
            es_seq_pc_r <= ds_pc + 32'd4;
            es_branch_target_r <= ds_pc + ds_imm;
            es_pred_taken_r <= ds_pred_taken;
            es_pred_target_r <= ds_pred_target;
            es_pred_btb_hit_r <= ds_pred_btb_hit;
            es_pred_btb_is_cond_r <= ds_pred_btb_is_cond;
            es_pred_bht_state_r <= ds_pred_bht_state;
            es_pred_pht_idx_r <= ds_pred_pht_idx;
            es_src1_hold_r <= ds_src1_from_prev_ex ? es_result_data :
                              ds_src1_from_prev_wb ? ws_rf_wdata : 32'b0;
            es_src2_hold_r <= ds_src2_from_prev_ex ? es_result_data :
                              ds_src2_from_prev_wb ? ws_rf_wdata : 32'b0;
            es_src1_hold_valid_r <= ds_src1_from_prev_ex | ds_src1_from_prev_wb;
            es_src2_hold_valid_r <= ds_src2_from_prev_ex | ds_src2_from_prev_wb;
            es_imm_r <= ds_imm;
            es_zimm_r <= ds_zimm;
            es_scsr_r <= ds_scsr;
            es_rd_r <= ds_rd;
            es_reg_wen_r <= ds_reg_wen;
            es_branch_r <= ds_branch;
            es_datatoreg_r <= ds_datatoreg;
            es_mem_wr_r <= ds_mem_wr;
            es_mem_op_r <= ds_mem_op;
            es_atomic_en_r <= ds_atomic_en;
            es_atomic_op_r <= ds_atomic_op;
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
            mdu_req_sent_r <= 1'b0;
`endif
            end else if (es_stall) begin
                if (!es_src1_hold_valid_r &&
                    (rs1_mem_alu_fwd || rs1_hidden_alu_fwd || rs1_load_fwd || rs1_wb_fwd)) begin
                    es_src1_hold_valid_r <= 1'b1;
                    es_src1_hold_r <= es_src1_use;
                end
                if (!es_src2_hold_valid_r &&
                    (rs2_mem_alu_fwd || rs2_hidden_alu_fwd || rs2_load_fwd || rs2_wb_fwd)) begin
                    es_src2_hold_valid_r <= 1'b1;
                    es_src2_hold_r <= es_src2_use;
                end
`ifdef NPC_M_EXTENSION
                if (mdu_req_fire) begin
                    mdu_req_sent_r <= 1'b1;
                end
                if (mdu_resp_valid && !mdu_result_valid_r) begin
                    mdu_result_valid_r <= 1'b1;
                    mdu_result_data_r <= mdu_resp_data;
                end
`endif
            end
        end
    end

endmodule
