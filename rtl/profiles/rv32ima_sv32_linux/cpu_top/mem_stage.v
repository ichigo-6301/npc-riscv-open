`timescale 1ns / 1ps

module mem_stage (
    input clk,
    input rst_n,
    input flush,

    input es_to_ms_valid,
    output ms_allowin,
    input ws_allowin,
    output ms_to_ws_valid,

    input [31:0] es_pc,
    input [31:0] es_instr,
    input [31:0] es_nextpc,
    input [4:0] es_rd,
    input es_reg_wen,
    input [1:0] es_datatoreg,
    input [1:0] es_mem_wr,
    input [2:0] es_mem_op,
    input es_atomic_en,
    input [3:0] es_atomic_op,
    input [31:0] es_aluout,
    input [31:0] es_mem_wdata,
    input es_mem_fwd_dep,
    input es_fast_mul_stat,
    input [31:0] es_csr_read_data,
    input [1:0] es_csr_wen,
    input [11:0] es_csr_waddr1,
    input [11:0] es_csr_waddr2,
    input [31:0] es_csr_wdata1,
    input [31:0] es_csr_wdata2,
    input es_illegal,
    input es_exc_valid,
    input [31:0] es_exc_cause,
    input [31:0] es_exc_tval,
    input es_is_ebreak,
    input [2:0] es_branch,
    input [31:0] es_src1_value,

    output ms_valid,
    output [31:0] ms_pc,
    output [31:0] ms_instr,
    output [31:0] ms_nextpc,
    output [4:0] ms_rd,
    output ms_reg_wen,
    output [1:0] ms_datatoreg,
    output [2:0] ms_mem_op,
    output [31:0] ms_aluout,
    output [31:0] ms_mem_rdata,
    output [31:0] ms_csr_read_data,
    output [1:0] ms_csr_wen,
    output [11:0] ms_csr_waddr1,
    output [11:0] ms_csr_waddr2,
    output [31:0] ms_csr_wdata1,
    output [31:0] ms_csr_wdata2,
    output ms_illegal,
    output ms_exc_valid,
    output [31:0] ms_exc_cause,
    output [31:0] ms_exc_tval,
    output ms_is_ebreak,
    output [2:0] ms_branch,
    output [31:0] ms_src1_value,
    output ms_fast_mul_stat,
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    output ms_stage_block,
    output ms_stage_block_req_phase,
    output ms_stage_block_resp_phase,
    output ms_stage_block_load,
    output ms_stage_block_store,
    output ms_stage_block_req_load,
    output ms_stage_block_req_store,
    output ms_stage_block_resp_load,
    output ms_stage_block_resp_store,
    output fast_req_fire_trace,
    output slow_req_fire_trace,
    output slow_req_fwd_dep_fire_trace,
    output slow_req_nonfwd_fire_trace,
    output ms_stat_load_visible,
    output ms_stat_load_aligned,
    output ms_stat_load_result_ready,
    output ms_stat_load_fault,
    output ms_stat_load_signext_ready,
    output ms_stat_load_req_fire,
    output ms_stat_load_resp_valid,
    output ms_stat_load_resp_fire,
    output ms_stat_load_data_ready,
    output ms_stat_load_signext_data_ready,
    output ms_stat_load_to_wb_valid,
    output ms_stat_load_split_or_misaligned,
    output ms_stat_load_uncached,
    output ms_stat_load_atomic,
    output ms_stat_load_killed,
    output ms_stat_hidden_load,
    output ms_stat_load_store_block,
    output ms_stat_load_lsu_pending,
    output ms_stat_mreq_valid,
    output ms_stat_mreq_is_load,
    output ms_stat_mreq_is_store,
    output ms_stat_mreq_is_atomic,
    output ms_stat_mreq_need_mem,
    output ms_stat_mreq_fire,
    output ms_stat_mreq_misaligned,
    output ms_stat_mreq_split,
    output ms_stat_mreq_fault,
    output ms_stat_mreq_blocked_by_resp,
    output ms_stat_mresp_valid,
    output ms_stat_mresp_is_load,
    output ms_stat_mresp_is_store,
    output ms_stat_mresp_is_atomic,
    output ms_stat_mresp_resp_valid,
    output ms_stat_mresp_resp_fire,
    output ms_stat_mresp_split,
    output ms_stat_mresp_fault,
    output ms_stat_store_visible,
    output ms_stat_store_req_fire,
    output ms_stat_store_resp_valid,
    output ms_stat_store_resp_fire,
    output ms_stat_store_aligned,
    output ms_stat_store_fault,
    output ms_stat_store_split_or_misaligned,
    output ms_stat_store_uncached,
    output ms_stat_store_atomic,
    output ms_stat_store_killed,
    output ms_stat_store_buffer_safe,
    output ms_stat_store_resp_wait,
    output ms_stat_single_outstanding_wait,
    output ms_stat_uncached_wait,
    output ms_stat_writeback_wait,
    output [63:0] stat_exmem_skid_candidate,
    output [63:0] stat_exmem_skid_enqueue,
    output [63:0] stat_exmem_skid_dequeue,
    output [63:0] stat_exmem_skid_full_stall,
    output [63:0] stat_exmem_skid_flush_drop,
    output [63:0] stat_exmem_skid_blocked_not_safe,
    output [63:0] stat_exmem_skid_blocked_branch,
    output [63:0] stat_exmem_skid_blocked_mem,
    output [63:0] stat_exmem_skid_blocked_csr,
    output [63:0] stat_exmem_skid_blocked_exception,
    output [63:0] stat_exmem_skid_blocked_div,
    output [63:0] stat_exmem_skid_blocked_structural,
    output [63:0] stat_exmem_skid_hold_cycles,
    output [63:0] stat_exmem_skid_hold_mem_wait_cycles,
    output [63:0] stat_exmem_skid_dequeue_after_mem_release,
    output [63:0] stat_exmem_skid_dequeue_same_cycle_mem_release,
    output [63:0] stat_exmem_skid_dequeue_causes_wb_valid,
    output stat_exmem_skid_valid,
    output stat_exmem_skid_enqueue_fire,
    output stat_exmem_skid_dequeue_fire,
    output stat_exmem_skid_dequeue_commit_fire,
    output stat_exmem_skid_dequeue_to_mreq_fire,
    output stat_exmem_skid_mem_wait,
    output stat_exmem_skid_mem_release,
`endif
`endif
    output hidden_mreq_valid,
    output hidden_mreq_reg_wen,
    output [4:0] hidden_mreq_rd,
    output [1:0] hidden_mreq_datatoreg,
    output [1:0] hidden_mreq_mem_wr,
    output [31:0] hidden_mreq_aluout,
    output [1:0] hidden_mreq_csr_wen,
    output [11:0] hidden_mreq_csr_waddr1,
    output [11:0] hidden_mreq_csr_waddr2,
    output hidden_mreq_fast_mul_stat,

    output dbus_req_valid,
    input dbus_req_ready,
    output dbus_req_fast_ok,
    output dbus_req_fast_block_atomic,
    output dbus_req_fast_block_misaligned,
    output dbus_req_fast_block_exception,
    output dbus_req_fast_block_phase2,
    output dbus_req_fast_block_other,
    output dbus_req_write,
    output dbus_req_atomic,
    output dbus_req_store_bufferable,
    output [31:0] dbus_req_addr,
    output [31:0] dbus_req_wdata,
    output [3:0] dbus_req_wstrb,
    output [2:0] dbus_req_len,
    input dbus_resp_valid,
    output dbus_resp_ready,
    input [31:0] dbus_resp_data,
    input dbus_resp_exc_valid,
    input [31:0] dbus_resp_exc_cause,
    input [31:0] dbus_resp_exc_tval,

    input atomic_alu_ready,
    output atomic_alu_req_valid,
    output [3:0] atomic_alu_op,
    output [31:0] atomic_alu_old,
    output [31:0] atomic_alu_rs2,
    input atomic_alu_resp_valid,
    input [31:0] atomic_alu_result,

    output dbg_mreq_valid,
    output dbg_mresp_valid,
    output dbg_skid_valid,
    output [31:0] dbg_mreq_instr,
    output [31:0] dbg_mresp_instr,
    output dbg_mreq_need_mem,
    output dbg_mreq_req_valid,
    output dbg_mreq_mem_fire,
    output dbg_mreq_nonmem_fire,
    output dbg_mreq_consumed_eff,
    output dbg_mresp_ready_go,
    output dbg_mresp_commit_fire,
    output dbg_old_mreq_allowin,
    output dbg_mresp_atomic_en,
    output dbg_mresp_split,
    output dbg_mresp_phase1_amo_read
);
    reg mreq_valid_r;
    reg [31:0] mreq_pc_r;
    reg [31:0] mreq_instr_r;
    reg [31:0] mreq_nextpc_r;
    reg [4:0] mreq_rd_r;
    reg mreq_reg_wen_r;
    reg [1:0] mreq_datatoreg_r;
    reg [1:0] mreq_mem_wr_r;
    reg [2:0] mreq_mem_op_r;
    reg mreq_atomic_en_r;
    reg [3:0] mreq_atomic_op_r;
    reg [31:0] mreq_aluout_r;
    reg [31:0] mreq_store_data_r;
    reg [31:0] mreq_csr_read_data_r;
    reg [1:0] mreq_csr_wen_r;
    reg [11:0] mreq_csr_waddr1_r;
    reg [11:0] mreq_csr_waddr2_r;
    reg [31:0] mreq_csr_wdata1_r;
    reg [31:0] mreq_csr_wdata2_r;
    reg mreq_illegal_r;
    reg mreq_exc_valid_r;
    reg [31:0] mreq_exc_cause_r;
    reg [31:0] mreq_exc_tval_r;
    reg mreq_is_ebreak_r;
    reg [2:0] mreq_branch_r;
    reg [31:0] mreq_src1_value_r;
    reg mreq_from_fwd_dep_r;
    reg mreq_fast_mul_stat_r;

    reg mresp_valid_r;
    reg [31:0] mresp_pc_r;
    reg [31:0] mresp_instr_r;
    reg [31:0] mresp_nextpc_r;
    reg [4:0] mresp_rd_r;
    reg mresp_reg_wen_r;
    reg [1:0] mresp_datatoreg_r;
    reg [1:0] mresp_mem_wr_r;
    reg [2:0] mresp_mem_op_r;
    reg mresp_atomic_en_r;
    reg [3:0] mresp_atomic_op_r;
    reg [31:0] mresp_store_data_r;
    reg [31:0] mresp_aluout_r;
    reg [31:0] mresp_csr_read_data_r;
    reg [1:0] mresp_csr_wen_r;
    reg [11:0] mresp_csr_waddr1_r;
    reg [11:0] mresp_csr_waddr2_r;
    reg [31:0] mresp_csr_wdata1_r;
    reg [31:0] mresp_csr_wdata2_r;
    reg mresp_illegal_r;
    reg mresp_exc_valid_r;
    reg [31:0] mresp_exc_cause_r;
    reg [31:0] mresp_exc_tval_r;
    reg mresp_is_ebreak_r;
    reg [2:0] mresp_branch_r;
    reg [31:0] mresp_src1_value_r;
    reg mresp_fast_mul_stat_r;
    reg mresp_atomic_phase2_r;
    reg mresp_atomic_write_sent_r;
    reg [31:0] mresp_atomic_old_r;
    reg [31:0] mresp_atomic_wdata_r;
    reg mresp_atomic_sc_success_r;
    reg mresp_split_r;
    reg mresp_split_first_done_r;
    reg mresp_split_second_sent_r;
    reg [31:0] mresp_split_first_data_r;
    reg [2:0] mresp_split_first_bytes_r;

    reg lrsc_valid_r;
    reg [31:0] lrsc_addr_r;

    reg skid_valid_r;
    reg [31:0] skid_pc_r;
    reg [31:0] skid_instr_r;
    reg [31:0] skid_nextpc_r;
    reg [4:0] skid_rd_r;
    reg skid_reg_wen_r;
    reg [1:0] skid_datatoreg_r;
    reg [1:0] skid_mem_wr_r;
    reg [2:0] skid_mem_op_r;
    reg skid_atomic_en_r;
    reg [3:0] skid_atomic_op_r;
    reg [31:0] skid_aluout_r;
    reg [31:0] skid_store_data_r;
    reg [31:0] skid_csr_read_data_r;
    reg [1:0] skid_csr_wen_r;
    reg [11:0] skid_csr_waddr1_r;
    reg [11:0] skid_csr_waddr2_r;
    reg [31:0] skid_csr_wdata1_r;
    reg [31:0] skid_csr_wdata2_r;
    reg skid_illegal_r;
    reg skid_exc_valid_r;
    reg [31:0] skid_exc_cause_r;
    reg [31:0] skid_exc_tval_r;
    reg skid_is_ebreak_r;
    reg [2:0] skid_branch_r;
    reg [31:0] skid_src1_value_r;
    reg skid_from_fwd_dep_r;
    reg skid_fast_mul_stat_r;

`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    reg [63:0] stat_exmem_skid_candidate_r;
    reg [63:0] stat_exmem_skid_enqueue_r;
    reg [63:0] stat_exmem_skid_dequeue_r;
    reg [63:0] stat_exmem_skid_full_stall_r;
    reg [63:0] stat_exmem_skid_flush_drop_r;
    reg [63:0] stat_exmem_skid_blocked_not_safe_r;
    reg [63:0] stat_exmem_skid_blocked_branch_r;
    reg [63:0] stat_exmem_skid_blocked_mem_r;
    reg [63:0] stat_exmem_skid_blocked_csr_r;
    reg [63:0] stat_exmem_skid_blocked_exception_r;
    reg [63:0] stat_exmem_skid_blocked_div_r;
    reg [63:0] stat_exmem_skid_blocked_structural_r;
    reg [63:0] stat_exmem_skid_hold_cycles_r;
    reg [63:0] stat_exmem_skid_hold_mem_wait_cycles_r;
    reg [63:0] stat_exmem_skid_dequeue_after_mem_release_r;
    reg [63:0] stat_exmem_skid_dequeue_same_cycle_mem_release_r;
    reg [63:0] stat_exmem_skid_dequeue_causes_wb_valid_r;
`endif
`endif

    wire mreq_is_atomic_lr = mreq_atomic_en_r && (mreq_atomic_op_r == 4'd1);
    wire mreq_is_atomic_sc = mreq_atomic_en_r && (mreq_atomic_op_r == 4'd2);
    wire mreq_is_atomic_amo = mreq_atomic_en_r &&
        (mreq_atomic_op_r >= 4'd3) && (mreq_atomic_op_r <= 4'd11);
    // LR/SC 时序要点：
    // - LR 的reservation在“收到LR读响应”这一拍才真正建立；
    // - 若下一条SC已提前进入mreq队列，且恰好在同一拍尝试判定成功与否，
    //   不能只看旧的lrsc_valid_r（否则会把本应成功的SC误判为失败）。
    // 这里引入“可见reservation”视图，把“本拍LR响应建立reservation”也纳入判定。
    wire lr_resp_set_resv = mem_resp_fire && mresp_atomic_en_r && mresp_is_atomic_lr;
    wire [31:0] lrsc_addr_visible = lr_resp_set_resv ? {mresp_aluout_r[31:2], 2'b00} : lrsc_addr_r;
    wire lrsc_valid_visible = lrsc_valid_r || lr_resp_set_resv;
    wire [31:0] mreq_addr_aligned = {mreq_aluout_r[31:2], 2'b00};
    wire lr_pending_same_addr = mresp_valid_r && mresp_atomic_en_r &&
        (mresp_atomic_op_r == 4'd1) && ({mresp_aluout_r[31:2], 2'b00} == mreq_addr_aligned);
    wire mreq_sc_success = mreq_is_atomic_sc &&
        (((lrsc_valid_visible) && (mreq_addr_aligned == lrsc_addr_visible)) || lr_pending_same_addr);

    wire mreq_is_load = (mreq_mem_wr_r == 2'b01) && !mreq_atomic_en_r;
    wire mreq_is_store = (mreq_mem_wr_r == 2'b11);
    wire mreq_need_mem_raw = mreq_valid_r &&
        ((mreq_mem_wr_r != 2'b00) || mreq_atomic_en_r);
    wire mreq_is_half = (mreq_mem_op_r == 3'b001) || (mreq_mem_op_r == 3'b101);
    wire mreq_is_word = (mreq_mem_op_r == 3'b010) || mreq_atomic_en_r;
    wire mreq_addr_misaligned =
        ((mreq_is_word) && (mreq_aluout_r[1:0] != 2'b00)) ||
        ((mreq_is_half) && (mreq_aluout_r[0] != 1'b0));
`ifndef NPC_MISALIGNED_DATA
    localparam NPC_MISALIGNED_DATA_EN = 1;
`else
    localparam NPC_MISALIGNED_DATA_EN = `NPC_MISALIGNED_DATA;
`endif
    wire mreq_misaligned_can_complete = (NPC_MISALIGNED_DATA_EN != 0) && !mreq_atomic_en_r;
    wire mreq_misaligned_trap = mreq_addr_misaligned && !mreq_misaligned_can_complete;
    wire mreq_mem_exc_valid = mreq_need_mem_raw && !mreq_exc_valid_r && mreq_misaligned_trap;
    wire [31:0] mreq_mem_exc_cause = mreq_is_load ? 32'd4 : 32'd6;
    wire mreq_exc_valid_eff = mreq_exc_valid_r || mreq_mem_exc_valid;
    wire [31:0] mreq_exc_cause_eff = mreq_exc_valid_r ? mreq_exc_cause_r : mreq_mem_exc_cause;
    wire [31:0] mreq_exc_tval_eff = mreq_exc_valid_r ? mreq_exc_tval_r : mreq_aluout_r;

    wire mreq_need_mem = mreq_need_mem_raw && !mreq_exc_valid_eff;
    wire mresp_need_mem = mresp_valid_r && (mresp_mem_wr_r != 2'b00);
    wire mresp_resp_exc = dbus_resp_valid && dbus_resp_exc_valid;

    wire [4:0] mreq_mem_shift = {mreq_aluout_r[1:0], 3'b000};
    wire [4:0] mresp_mem_shift = {mresp_aluout_r[1:0], 3'b000};
    wire [1:0] mreq_offset = mreq_aluout_r[1:0];
    wire [2:0] mreq_access_bytes =
        mreq_is_word ? 3'd4 :
        mreq_is_half ? 3'd2 :
        3'd1;
    wire [2:0] mreq_first_bytes = 3'd4 - {1'b0, mreq_offset};
    wire mreq_split_access = mreq_need_mem && mreq_misaligned_can_complete &&
        (({1'b0, mreq_offset} + mreq_access_bytes) > 3'd4);
    wire [3:0] mreq_raw_wstrb =
        (mreq_mem_op_r == 3'b010) ? 4'b1111 :
        ((mreq_mem_op_r == 3'b001) || (mreq_mem_op_r == 3'b101)) ? 4'b0011 :
        4'b0001;
    wire [31:0] mresp_load_data_aligned = dbus_resp_data >> mresp_mem_shift;
    wire [31:0] mresp_split_load_data =
        mresp_split_first_data_r | (dbus_resp_data << {mresp_split_first_bytes_r[1:0], 3'b000});

    wire mem_resp_fire = mresp_valid_r && dbus_resp_valid && dbus_resp_ready;
    // 为避免在请求/响应同拍交错时重复发射同一条访存，先收敛为“单未决访存”：
    // 只有当mresp槽为空时才允许发起新的mreq。
    // 这会牺牲一点吞吐，但能保证LR/SC/AMO语义和提交顺序稳定。
    wire mresp_can_accept = !mresp_valid_r;
    wire mreq_req_valid = mreq_need_mem && !(mreq_is_atomic_sc && !mreq_sc_success);
    wire mreq_req_write = mreq_atomic_en_r ?
        (mreq_is_atomic_sc ? mreq_sc_success : 1'b0) :
        mreq_is_store;
    // 原子访存中：
    // - LR/AMO 第1阶段是读，不使用写数据；
    // - SC 成功时需要把 rs2(即 mreq_store_data_r)真正写回内存。
    wire [31:0] mreq_req_wdata = mreq_atomic_en_r ?
        (mreq_is_atomic_sc ? (mreq_store_data_r << mreq_mem_shift) : 32'b0) :
        (mreq_store_data_r << mreq_mem_shift);
    wire [3:0] mreq_req_wstrb = mreq_atomic_en_r ?
        (mreq_req_write ? 4'b1111 : 4'b0000) :
        (mreq_raw_wstrb << mreq_aluout_r[1:0]);
    wire [2:0] mreq_req_len_full = mreq_atomic_en_r ? 3'd4 :
        ((mreq_mem_op_r == 3'b010) ? 3'd4 :
         (((mreq_mem_op_r == 3'b001) || (mreq_mem_op_r == 3'b101)) ? 3'd2 : 3'd1));
    wire [2:0] mreq_req_len = mreq_split_access ? mreq_first_bytes : mreq_req_len_full;

    wire atomic_phase2_req_valid = mresp_valid_r && mresp_atomic_en_r &&
        mresp_atomic_phase2_r && !mresp_atomic_write_sent_r;
    wire split_second_req_valid = mresp_valid_r && mresp_split_r &&
        mresp_split_first_done_r && !mresp_split_second_sent_r;
    wire atomic_phase2_req_fire = atomic_phase2_req_valid && dbus_req_ready;
    wire split_second_req_fire = split_second_req_valid && dbus_req_ready;
    wire mreq_mem_fire = mreq_req_valid && mresp_can_accept && dbus_req_ready;
    wire mreq_nonmem_fire = mreq_valid_r && (!mreq_need_mem || mreq_exc_valid_eff) && !mresp_valid_r && ws_allowin;
    wire mreq_sc_fail_fire = mreq_valid_r && mreq_is_atomic_sc && !mreq_sc_success &&
        !mresp_valid_r && ws_allowin;
    wire mreq_consumed = mreq_mem_fire || mreq_nonmem_fire;
    wire mreq_consumed_eff = mreq_mem_fire || mreq_nonmem_fire || mreq_sc_fail_fire;

    wire old_mreq_allowin = (!mreq_valid_r || mreq_consumed_eff) &&
        !(mresp_valid_r && mresp_atomic_en_r);
`ifdef NPC_EX_MEM_SKID
    localparam EX_MEM_SKID_ENABLE = 1'b1;
`else
    localparam EX_MEM_SKID_ENABLE = 1'b0;
`endif
    wire es_is_fence_like = (es_instr[6:0] == 7'b0001111);
    wire es_is_system_like = (es_instr[6:0] == 7'b1110011);
    wire es_is_m_extension = (es_instr[6:0] == 7'b0110011) &&
        (es_instr[31:25] == 7'b0000001);
    wire es_is_div_or_unstable_mdu = es_is_m_extension && !es_fast_mul_stat;
    wire es_skid_block_mem = (es_datatoreg != 2'b00) ||
        (es_mem_wr != 2'b00) || es_atomic_en;
    wire es_skid_block_branch = (es_branch != 3'b000);
    wire es_skid_block_csr = (es_csr_wen != 2'b00) ||
        es_is_fence_like || es_is_system_like;
    wire es_skid_block_exception = es_exc_valid || es_illegal || es_is_ebreak;
    wire es_safe_skid_packet = es_to_ms_valid && !es_skid_block_mem &&
        !es_skid_block_branch && !es_skid_block_csr &&
        !es_skid_block_exception && !es_is_div_or_unstable_mdu;
    wire skid_candidate_pulse = EX_MEM_SKID_ENABLE && es_to_ms_valid &&
        !old_mreq_allowin;
    wire skid_can_enqueue = skid_candidate_pulse && !skid_valid_r &&
        !mresp_valid_r && es_safe_skid_packet;
    wire skid_commit_fire = EX_MEM_SKID_ENABLE && skid_valid_r &&
        !mreq_valid_r && !mresp_valid_r && ws_allowin;
    wire skid_dequeue_to_mreq = EX_MEM_SKID_ENABLE && skid_valid_r &&
        old_mreq_allowin && !skid_commit_fire;
    wire skid_dequeue_fire = skid_dequeue_to_mreq || skid_commit_fire;
    wire skid_mem_wait = skid_valid_r && (mreq_valid_r || mresp_valid_r ||
        dbus_req_valid || (dbus_resp_ready && !dbus_resp_valid));
    wire skid_mem_release = skid_valid_r && old_mreq_allowin;

    assign ms_allowin = (old_mreq_allowin && (!skid_valid_r || skid_commit_fire)) ||
        skid_can_enqueue;

    wire [2:0] mresp_split_first_bytes = 3'd4 - {1'b0, mresp_aluout_r[1:0]};
    wire [31:0] split_second_store_data = mresp_store_data_r >> ({mresp_split_first_bytes[1:0], 3'b000});
    wire [3:0] split_second_wstrb =
        (mresp_mem_op_r == 3'b010) ?
            ((mresp_aluout_r[1:0] == 2'd1) ? 4'b0001 :
             (mresp_aluout_r[1:0] == 2'd2) ? 4'b0011 :
                                               4'b0111) :
            4'b0001;
    wire [2:0] split_second_len =
        (mresp_mem_op_r == 3'b010) ?
            ((mresp_aluout_r[1:0] == 2'd1) ? 3'd1 :
             (mresp_aluout_r[1:0] == 2'd2) ? 3'd2 :
                                               3'd3) :
            3'd1;
    assign dbus_req_valid = atomic_phase2_req_valid || split_second_req_valid ||
        (mreq_req_valid && mresp_can_accept);
    assign dbus_req_fast_ok = !atomic_phase2_req_valid && !split_second_req_valid &&
        mreq_req_valid && mresp_can_accept && !mreq_atomic_en_r &&
        !mreq_split_access && !mreq_addr_misaligned && !mreq_exc_valid_r;
    assign dbus_req_fast_block_atomic = dbus_req_valid && !dbus_req_fast_ok && mreq_atomic_en_r;
    assign dbus_req_fast_block_misaligned = dbus_req_valid && !dbus_req_fast_ok &&
        (mreq_split_access || mreq_addr_misaligned);
    assign dbus_req_fast_block_exception = dbus_req_valid && !dbus_req_fast_ok && mreq_exc_valid_r;
    assign dbus_req_fast_block_phase2 = dbus_req_valid && !dbus_req_fast_ok &&
        (atomic_phase2_req_valid || split_second_req_valid);
    assign dbus_req_fast_block_other = dbus_req_valid && !dbus_req_fast_ok &&
        !dbus_req_fast_block_atomic && !dbus_req_fast_block_misaligned &&
        !dbus_req_fast_block_exception && !dbus_req_fast_block_phase2;
    assign dbus_req_write = atomic_phase2_req_valid ? 1'b1 :
        (split_second_req_valid ? mresp_is_store : mreq_req_write);
    assign dbus_req_atomic = atomic_phase2_req_valid ||
        (mreq_req_valid && mresp_can_accept && mreq_atomic_en_r);
    assign dbus_req_store_bufferable = mreq_req_valid && mresp_can_accept &&
        mreq_is_store && !mreq_atomic_en_r && !mreq_split_access &&
        !mreq_addr_misaligned && !mreq_exc_valid_eff;
    assign dbus_req_addr = atomic_phase2_req_valid ? mresp_aluout_r :
        (split_second_req_valid ? {mresp_aluout_r[31:2], 2'b00} + 32'd4 : mreq_aluout_r);
    assign dbus_req_wdata = atomic_phase2_req_valid ? mresp_atomic_wdata_r :
        (split_second_req_valid ? split_second_store_data : mreq_req_wdata);
    assign dbus_req_wstrb = atomic_phase2_req_valid ? 4'b1111 :
        (split_second_req_valid ? (mresp_is_store ? split_second_wstrb : 4'b0000) : mreq_req_wstrb);
    assign dbus_req_len = atomic_phase2_req_valid ? 3'd4 :
        (split_second_req_valid ? split_second_len : mreq_req_len);
    assign dbus_resp_ready = mresp_valid_r &&
        (mresp_resp_exc ? ws_allowin :
            (mresp_split_r ? (!mresp_split_first_done_r || (mresp_split_second_sent_r && ws_allowin)) : ws_allowin));

    wire mresp_selected = mresp_valid_r;
    wire skid_selected = !mresp_valid_r && !mreq_valid_r && skid_valid_r;
    wire mresp_is_load = (mresp_mem_wr_r == 2'b01) && !mresp_atomic_en_r;
    wire mresp_is_store = (mresp_mem_wr_r == 2'b11);
    wire mresp_is_atomic_lr = mresp_atomic_en_r && (mresp_atomic_op_r == 4'd1);
    wire mresp_is_atomic_sc = mresp_atomic_en_r && (mresp_atomic_op_r == 4'd2);
    wire mresp_is_atomic_amo = mresp_atomic_en_r &&
        (mresp_atomic_op_r >= 4'd3) && (mresp_atomic_op_r <= 4'd11);
    wire mresp_phase1_amo_read = mresp_is_atomic_amo && !mresp_atomic_phase2_r;
    wire mresp_ready_go = mresp_valid_r && dbus_resp_valid &&
        (mresp_resp_exc || (mresp_split_r ? mresp_split_second_sent_r : !mresp_phase1_amo_read));
    wire mresp_commit_fire = mresp_ready_go && ws_allowin;
    wire mreq_ready_go = (mreq_valid_r && !mreq_need_mem && !mresp_valid_r) || mreq_sc_fail_fire;

    assign dbg_mreq_valid = mreq_valid_r;
    assign dbg_mresp_valid = mresp_valid_r;
    assign dbg_skid_valid = skid_valid_r;
    assign dbg_mreq_instr = mreq_instr_r;
    assign dbg_mresp_instr = mresp_instr_r;
    assign dbg_mreq_need_mem = mreq_need_mem;
    assign dbg_mreq_req_valid = mreq_req_valid;
    assign dbg_mreq_mem_fire = mreq_mem_fire;
    assign dbg_mreq_nonmem_fire = mreq_nonmem_fire;
    assign dbg_mreq_consumed_eff = mreq_consumed_eff;
    assign dbg_mresp_ready_go = mresp_ready_go;
    assign dbg_mresp_commit_fire = mresp_commit_fire;
    assign dbg_old_mreq_allowin = old_mreq_allowin;
    assign dbg_mresp_atomic_en = mresp_atomic_en_r;
    assign dbg_mresp_split = mresp_split_r;
    assign dbg_mresp_phase1_amo_read = mresp_phase1_amo_read;

    wire mresp_exc_valid_eff = mresp_resp_exc || mresp_exc_valid_r;
    wire [31:0] mresp_exc_cause_eff = mresp_resp_exc ? dbus_resp_exc_cause : mresp_exc_cause_r;
    wire [31:0] mresp_exc_tval_eff = mresp_resp_exc ? dbus_resp_exc_tval : mresp_exc_tval_r;

    assign ms_to_ws_valid = (((mresp_ready_go || mreq_ready_go) && ws_allowin) ||
        skid_commit_fire);
    assign ms_valid = mresp_valid_r || mreq_valid_r || skid_valid_r;
    assign ms_pc = mresp_selected ? mresp_pc_r : (skid_selected ? skid_pc_r : mreq_pc_r);
    assign ms_instr = mresp_selected ? mresp_instr_r : (skid_selected ? skid_instr_r : mreq_instr_r);
    assign ms_nextpc = mresp_selected ? mresp_nextpc_r : (skid_selected ? skid_nextpc_r : mreq_nextpc_r);
    assign ms_rd = mresp_selected ? mresp_rd_r : (skid_selected ? skid_rd_r : mreq_rd_r);
    assign ms_reg_wen = mresp_selected ? mresp_reg_wen_r : (skid_selected ? skid_reg_wen_r : mreq_reg_wen_r);
    assign ms_datatoreg = mresp_selected ? mresp_datatoreg_r : (skid_selected ? skid_datatoreg_r : mreq_datatoreg_r);
    assign ms_mem_op = mresp_selected ? mresp_mem_op_r : (skid_selected ? skid_mem_op_r : mreq_mem_op_r);
    assign ms_aluout = mresp_selected ? mresp_aluout_r : (skid_selected ? skid_aluout_r : mreq_aluout_r);
    assign ms_mem_rdata = mresp_selected ?
            (mresp_atomic_en_r ?
            (mresp_is_atomic_sc ? (mresp_atomic_sc_success_r ? 32'd0 : 32'd1) :
                (mresp_is_atomic_amo ? mresp_atomic_old_r : mresp_load_data_aligned)) :
            (mresp_split_r ? mresp_split_load_data : mresp_load_data_aligned)) :
        (mreq_sc_fail_fire ? 32'd1 : 32'b0);
    assign ms_csr_read_data = mresp_selected ? mresp_csr_read_data_r : (skid_selected ? skid_csr_read_data_r : mreq_csr_read_data_r);
    assign ms_csr_wen = mresp_selected ? mresp_csr_wen_r : (skid_selected ? skid_csr_wen_r : mreq_csr_wen_r);
    assign ms_csr_waddr1 = mresp_selected ? mresp_csr_waddr1_r : (skid_selected ? skid_csr_waddr1_r : mreq_csr_waddr1_r);
    assign ms_csr_waddr2 = mresp_selected ? mresp_csr_waddr2_r : (skid_selected ? skid_csr_waddr2_r : mreq_csr_waddr2_r);
    assign ms_csr_wdata1 = mresp_selected ? mresp_csr_wdata1_r : (skid_selected ? skid_csr_wdata1_r : mreq_csr_wdata1_r);
    assign ms_csr_wdata2 = mresp_selected ? mresp_csr_wdata2_r : (skid_selected ? skid_csr_wdata2_r : mreq_csr_wdata2_r);
    assign ms_illegal = mresp_selected ? mresp_illegal_r : (skid_selected ? skid_illegal_r : mreq_illegal_r);
    assign ms_exc_valid = mresp_selected ? mresp_exc_valid_eff : (skid_selected ? skid_exc_valid_r : mreq_exc_valid_eff);
    assign ms_exc_cause = mresp_selected ? mresp_exc_cause_eff : (skid_selected ? skid_exc_cause_r : mreq_exc_cause_eff);
    assign ms_exc_tval = mresp_selected ? mresp_exc_tval_eff : (skid_selected ? skid_exc_tval_r : mreq_exc_tval_eff);
    assign ms_is_ebreak = mresp_selected ? mresp_is_ebreak_r : (skid_selected ? skid_is_ebreak_r : mreq_is_ebreak_r);
    assign ms_branch = mresp_selected ? mresp_branch_r : (skid_selected ? skid_branch_r : mreq_branch_r);
    assign ms_src1_value = mresp_selected ? mresp_src1_value_r : (skid_selected ? skid_src1_value_r : mreq_src1_value_r);
    assign ms_fast_mul_stat = mresp_selected ? mresp_fast_mul_stat_r : (skid_selected ? skid_fast_mul_stat_r : mreq_fast_mul_stat_r);
    // AMO 的算术/逻辑运算在 MEM 阶段本地完成：
    // 这样可以避免 EX<->MEM 因握手互相等待导致的死锁。
    // 因此这里将 EX 侧共享 atomic ALU 接口保持静默。
    assign atomic_alu_req_valid = 1'b0;
    assign atomic_alu_op = 4'b0;
    assign atomic_alu_old = 32'b0;
    assign atomic_alu_rs2 = 32'b0;

    wire amo_slt_signed = ($signed(mresp_load_data_aligned) < $signed(mresp_store_data_r));
    wire amo_slt_unsigned = (mresp_load_data_aligned < mresp_store_data_r);
    // AMO phase1 读回旧值后，按照 funct5(op)在 MEM 阶段直接计算写回值
    // （对应 amo{swap,add,xor,and,or,min,max,minu,maxu}.w）
    wire [31:0] amo_wdata_calc =
        (mresp_atomic_op_r == 4'd3)  ? mresp_store_data_r :                           // swap
        (mresp_atomic_op_r == 4'd4)  ? (mresp_load_data_aligned + mresp_store_data_r) : // add
        (mresp_atomic_op_r == 4'd5)  ? (mresp_load_data_aligned ^ mresp_store_data_r) : // xor
        (mresp_atomic_op_r == 4'd6)  ? (mresp_load_data_aligned & mresp_store_data_r) : // and
        (mresp_atomic_op_r == 4'd7)  ? (mresp_load_data_aligned | mresp_store_data_r) : // or
        (mresp_atomic_op_r == 4'd8)  ? (amo_slt_signed ? mresp_load_data_aligned : mresp_store_data_r) : // min
        (mresp_atomic_op_r == 4'd9)  ? (amo_slt_signed ? mresp_store_data_r : mresp_load_data_aligned) : // max
        (mresp_atomic_op_r == 4'd10) ? (amo_slt_unsigned ? mresp_load_data_aligned : mresp_store_data_r) : // minu
        (mresp_atomic_op_r == 4'd11) ? (amo_slt_unsigned ? mresp_store_data_r : mresp_load_data_aligned) : // maxu
                                        mresp_store_data_r;

`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    assign ms_stage_block = (mreq_valid_r && !mreq_consumed_eff) ||
                            (mresp_valid_r && !dbus_resp_valid);
    assign ms_stage_block_req_phase = (mreq_req_valid && !mreq_mem_fire) || atomic_phase2_req_valid;
    assign ms_stage_block_resp_phase = mresp_valid_r && !dbus_resp_valid;
    assign ms_stage_block_load =
        (mreq_valid_r && !mreq_consumed_eff && mreq_is_load) ||
        (mresp_valid_r && !dbus_resp_valid && mresp_is_load);
    assign ms_stage_block_store =
        (mreq_valid_r && !mreq_consumed_eff && mreq_is_store) ||
        (mresp_valid_r && !dbus_resp_valid && mresp_is_store);
    assign ms_stage_block_req_load = (mreq_req_valid && !mreq_mem_fire && mreq_is_load);
    assign ms_stage_block_req_store =
        (mreq_req_valid && !mreq_mem_fire && mreq_is_store) || atomic_phase2_req_valid;
    assign ms_stage_block_resp_load = mresp_valid_r && !dbus_resp_valid && mresp_is_load;
    assign ms_stage_block_resp_store = mresp_valid_r && !dbus_resp_valid && mresp_is_store;
    // Two-level LSU has no fast request path; all issued memory requests are
    // classified as "slow" for compatibility with existing PipeStat outputs.
    assign fast_req_fire_trace = 1'b0;
    assign slow_req_fire_trace = mreq_mem_fire;
    assign slow_req_fwd_dep_fire_trace = mreq_mem_fire && mreq_from_fwd_dep_r;
    assign slow_req_nonfwd_fire_trace = mreq_mem_fire && !mreq_from_fwd_dep_r;
    assign ms_stat_load_visible = (mresp_valid_r && mresp_is_load) ||
                                  (mreq_valid_r && mreq_is_load);
    assign ms_stat_load_aligned =
        mresp_valid_r ? (mresp_is_load && !mresp_split_r) :
        (mreq_valid_r && mreq_is_load && !mreq_split_access && !mreq_addr_misaligned);
    assign ms_stat_load_result_ready = mem_resp_fire && mresp_is_load && !mresp_resp_exc;
    assign ms_stat_load_fault = (mresp_valid_r && mresp_is_load && mresp_resp_exc) ||
                                (mreq_valid_r && mreq_is_load && mreq_mem_exc_valid);
    assign ms_stat_load_signext_ready = ms_stat_load_result_ready;
    assign ms_stat_load_req_fire = mreq_mem_fire && mreq_is_load;
    assign ms_stat_load_resp_valid = mresp_valid_r && mresp_is_load && dbus_resp_valid;
    assign ms_stat_load_resp_fire = mem_resp_fire && mresp_is_load;
    assign ms_stat_load_data_ready = mresp_ready_go && mresp_is_load && !mresp_resp_exc;
    assign ms_stat_load_signext_data_ready = ms_stat_load_data_ready;
    assign ms_stat_load_to_wb_valid = ms_to_ws_valid && mresp_selected &&
                                      mresp_is_load && !mresp_exc_valid_eff;
    assign ms_stat_load_split_or_misaligned =
        (mresp_valid_r && mresp_is_load && mresp_split_r) ||
        (mreq_valid_r && mreq_is_load && (mreq_split_access || mreq_addr_misaligned));
    assign ms_stat_load_uncached = 1'b0;
    assign ms_stat_load_atomic =
        (mresp_valid_r && mresp_atomic_en_r) ||
        (mreq_valid_r && mreq_atomic_en_r);
    assign ms_stat_load_killed = flush && ms_stat_load_visible;
    assign ms_stat_hidden_load = mresp_valid_r && mreq_valid_r && mreq_is_load;
    assign ms_stat_load_store_block =
        ms_stage_block_store || ms_stage_block_req_store || ms_stage_block_resp_store;
    assign ms_stat_load_lsu_pending =
        (mresp_valid_r && mresp_is_load && !dbus_resp_valid) ||
        (mreq_valid_r && mreq_is_load && !mreq_consumed_eff) ||
        (mreq_req_valid && !mresp_can_accept);
    assign ms_stat_mreq_valid = mreq_valid_r;
    assign ms_stat_mreq_is_load = mreq_is_load;
    assign ms_stat_mreq_is_store = mreq_is_store;
    assign ms_stat_mreq_is_atomic = mreq_atomic_en_r;
    assign ms_stat_mreq_need_mem = mreq_need_mem;
    assign ms_stat_mreq_fire = mreq_mem_fire;
    assign ms_stat_mreq_misaligned = mreq_addr_misaligned;
    assign ms_stat_mreq_split = mreq_split_access;
    assign ms_stat_mreq_fault = mreq_exc_valid_eff;
    assign ms_stat_mreq_blocked_by_resp = mreq_req_valid && !mresp_can_accept;
    assign ms_stat_mresp_valid = mresp_valid_r;
    assign ms_stat_mresp_is_load = mresp_is_load;
    assign ms_stat_mresp_is_store = mresp_is_store;
    assign ms_stat_mresp_is_atomic = mresp_atomic_en_r;
    assign ms_stat_mresp_resp_valid = mresp_valid_r && dbus_resp_valid;
    assign ms_stat_mresp_resp_fire = mem_resp_fire;
    assign ms_stat_mresp_split = mresp_split_r;
    assign ms_stat_mresp_fault = mresp_valid_r && mresp_exc_valid_eff;
    assign ms_stat_store_visible = (mresp_valid_r && mresp_is_store) ||
                                   (mreq_valid_r && mreq_is_store);
    assign ms_stat_store_req_fire = mreq_mem_fire && mreq_is_store;
    assign ms_stat_store_resp_valid = mresp_valid_r && mresp_is_store && dbus_resp_valid;
    assign ms_stat_store_resp_fire = mem_resp_fire && mresp_is_store;
    assign ms_stat_store_aligned =
        (mresp_valid_r && mresp_is_store) ? !mresp_split_r :
        (mreq_valid_r && mreq_is_store && !mreq_split_access && !mreq_addr_misaligned);
    assign ms_stat_store_fault = (mresp_valid_r && mresp_is_store && mresp_resp_exc) ||
                                 (mreq_valid_r && mreq_is_store && mreq_mem_exc_valid);
    assign ms_stat_store_split_or_misaligned =
        (mresp_valid_r && mresp_is_store && mresp_split_r) ||
        (mreq_valid_r && mreq_is_store && (mreq_split_access || mreq_addr_misaligned));
    assign ms_stat_store_uncached = 1'b0;
    assign ms_stat_store_atomic =
        (mresp_valid_r && mresp_atomic_en_r) ||
        (mreq_valid_r && mreq_atomic_en_r);
    assign ms_stat_store_killed = flush && ms_stat_store_visible;
    assign ms_stat_store_buffer_safe =
        ms_stat_store_visible && ms_stat_store_aligned &&
        !ms_stat_store_fault && !ms_stat_store_uncached &&
        !ms_stat_store_atomic && !ms_stat_store_killed &&
        !ms_stat_store_split_or_misaligned;
    assign ms_stat_store_resp_wait = mresp_valid_r && mresp_is_store && !dbus_resp_valid;
    assign ms_stat_single_outstanding_wait = mreq_req_valid && !mresp_can_accept;
    assign ms_stat_uncached_wait = 1'b0;
    assign ms_stat_writeback_wait = 1'b0;
`endif
`endif
    // When an older memory request is in mresp, the mreq slot is hidden behind
    // it on the normal ms_* outputs. Keep that younger destination visible to
    // ID hazard detection, but do not create another bypass data path.
    wire hidden_select_skid = skid_valid_r && !skid_selected &&
        !(mresp_valid_r && mreq_valid_r);
    assign hidden_mreq_valid = (mresp_valid_r && mreq_valid_r) ||
        (skid_valid_r && !skid_selected);
    assign hidden_mreq_reg_wen = hidden_select_skid ? skid_reg_wen_r : mreq_reg_wen_r;
    assign hidden_mreq_rd = hidden_select_skid ? skid_rd_r : mreq_rd_r;
    assign hidden_mreq_datatoreg = hidden_select_skid ? skid_datatoreg_r : mreq_datatoreg_r;
    assign hidden_mreq_mem_wr = hidden_select_skid ? skid_mem_wr_r : mreq_mem_wr_r;
    assign hidden_mreq_aluout = hidden_select_skid ? skid_aluout_r : mreq_aluout_r;
    assign hidden_mreq_csr_wen = hidden_select_skid ? skid_csr_wen_r : mreq_csr_wen_r;
    assign hidden_mreq_csr_waddr1 = hidden_select_skid ? skid_csr_waddr1_r : mreq_csr_waddr1_r;
    assign hidden_mreq_csr_waddr2 = hidden_select_skid ? skid_csr_waddr2_r : mreq_csr_waddr2_r;
    assign hidden_mreq_fast_mul_stat = hidden_select_skid ? skid_fast_mul_stat_r : mreq_fast_mul_stat_r;

`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    assign stat_exmem_skid_candidate = stat_exmem_skid_candidate_r;
    assign stat_exmem_skid_enqueue = stat_exmem_skid_enqueue_r;
    assign stat_exmem_skid_dequeue = stat_exmem_skid_dequeue_r;
    assign stat_exmem_skid_full_stall = stat_exmem_skid_full_stall_r;
    assign stat_exmem_skid_flush_drop = stat_exmem_skid_flush_drop_r;
    assign stat_exmem_skid_blocked_not_safe = stat_exmem_skid_blocked_not_safe_r;
    assign stat_exmem_skid_blocked_branch = stat_exmem_skid_blocked_branch_r;
    assign stat_exmem_skid_blocked_mem = stat_exmem_skid_blocked_mem_r;
    assign stat_exmem_skid_blocked_csr = stat_exmem_skid_blocked_csr_r;
    assign stat_exmem_skid_blocked_exception = stat_exmem_skid_blocked_exception_r;
    assign stat_exmem_skid_blocked_div = stat_exmem_skid_blocked_div_r;
    assign stat_exmem_skid_blocked_structural = stat_exmem_skid_blocked_structural_r;
    assign stat_exmem_skid_hold_cycles = stat_exmem_skid_hold_cycles_r;
    assign stat_exmem_skid_hold_mem_wait_cycles = stat_exmem_skid_hold_mem_wait_cycles_r;
    assign stat_exmem_skid_dequeue_after_mem_release = stat_exmem_skid_dequeue_after_mem_release_r;
    assign stat_exmem_skid_dequeue_same_cycle_mem_release = stat_exmem_skid_dequeue_same_cycle_mem_release_r;
    assign stat_exmem_skid_dequeue_causes_wb_valid = stat_exmem_skid_dequeue_causes_wb_valid_r;
    assign stat_exmem_skid_valid = skid_valid_r;
    assign stat_exmem_skid_enqueue_fire = skid_can_enqueue;
    assign stat_exmem_skid_dequeue_fire = skid_dequeue_fire;
    assign stat_exmem_skid_dequeue_commit_fire = skid_commit_fire;
    assign stat_exmem_skid_dequeue_to_mreq_fire = skid_dequeue_to_mreq;
    assign stat_exmem_skid_mem_wait = skid_mem_wait;
    assign stat_exmem_skid_mem_release = skid_mem_release;
`endif
`endif

    always @(posedge clk) begin
        if (!rst_n) begin
            mreq_valid_r <= 1'b0;
            mreq_pc_r <= 32'b0;
            mreq_instr_r <= 32'b0;
            mreq_nextpc_r <= 32'b0;
            mreq_rd_r <= 5'b0;
            mreq_reg_wen_r <= 1'b0;
            mreq_datatoreg_r <= 2'b00;
            mreq_mem_wr_r <= 2'b00;
            mreq_mem_op_r <= 3'b000;
            mreq_atomic_en_r <= 1'b0;
            mreq_atomic_op_r <= 4'b0;
            mreq_aluout_r <= 32'b0;
            mreq_store_data_r <= 32'b0;
            mreq_csr_read_data_r <= 32'b0;
            mreq_csr_wen_r <= 2'b00;
            mreq_csr_waddr1_r <= 12'b0;
            mreq_csr_waddr2_r <= 12'b0;
            mreq_csr_wdata1_r <= 32'b0;
            mreq_csr_wdata2_r <= 32'b0;
            mreq_illegal_r <= 1'b0;
            mreq_exc_valid_r <= 1'b0;
            mreq_exc_cause_r <= 32'b0;
            mreq_exc_tval_r <= 32'b0;
            mreq_is_ebreak_r <= 1'b0;
            mreq_branch_r <= 3'b000;
            mreq_src1_value_r <= 32'b0;
            mreq_from_fwd_dep_r <= 1'b0;
            mreq_fast_mul_stat_r <= 1'b0;

            mresp_valid_r <= 1'b0;
            mresp_pc_r <= 32'b0;
            mresp_instr_r <= 32'b0;
            mresp_nextpc_r <= 32'b0;
            mresp_rd_r <= 5'b0;
            mresp_reg_wen_r <= 1'b0;
            mresp_datatoreg_r <= 2'b00;
            mresp_mem_wr_r <= 2'b00;
            mresp_mem_op_r <= 3'b000;
            mresp_atomic_en_r <= 1'b0;
            mresp_atomic_op_r <= 4'b0;
            mresp_store_data_r <= 32'b0;
            mresp_aluout_r <= 32'b0;
            mresp_csr_read_data_r <= 32'b0;
            mresp_csr_wen_r <= 2'b00;
            mresp_csr_waddr1_r <= 12'b0;
            mresp_csr_waddr2_r <= 12'b0;
            mresp_csr_wdata1_r <= 32'b0;
            mresp_csr_wdata2_r <= 32'b0;
            mresp_illegal_r <= 1'b0;
            mresp_exc_valid_r <= 1'b0;
            mresp_exc_cause_r <= 32'b0;
            mresp_exc_tval_r <= 32'b0;
            mresp_is_ebreak_r <= 1'b0;
            mresp_branch_r <= 3'b000;
            mresp_src1_value_r <= 32'b0;
            mresp_fast_mul_stat_r <= 1'b0;
            mresp_atomic_phase2_r <= 1'b0;
            mresp_atomic_write_sent_r <= 1'b0;
            mresp_atomic_old_r <= 32'b0;
            mresp_atomic_wdata_r <= 32'b0;
            mresp_atomic_sc_success_r <= 1'b0;
            mresp_split_r <= 1'b0;
            mresp_split_first_done_r <= 1'b0;
            mresp_split_second_sent_r <= 1'b0;
            mresp_split_first_data_r <= 32'b0;
            mresp_split_first_bytes_r <= 3'b0;

            lrsc_valid_r <= 1'b0;
            lrsc_addr_r <= 32'b0;

            skid_valid_r <= 1'b0;
            skid_pc_r <= 32'b0;
            skid_instr_r <= 32'b0;
            skid_nextpc_r <= 32'b0;
            skid_rd_r <= 5'b0;
            skid_reg_wen_r <= 1'b0;
            skid_datatoreg_r <= 2'b00;
            skid_mem_wr_r <= 2'b00;
            skid_mem_op_r <= 3'b000;
            skid_atomic_en_r <= 1'b0;
            skid_atomic_op_r <= 4'b0;
            skid_aluout_r <= 32'b0;
            skid_store_data_r <= 32'b0;
            skid_csr_read_data_r <= 32'b0;
            skid_csr_wen_r <= 2'b00;
            skid_csr_waddr1_r <= 12'b0;
            skid_csr_waddr2_r <= 12'b0;
            skid_csr_wdata1_r <= 32'b0;
            skid_csr_wdata2_r <= 32'b0;
            skid_illegal_r <= 1'b0;
            skid_exc_valid_r <= 1'b0;
            skid_exc_cause_r <= 32'b0;
            skid_exc_tval_r <= 32'b0;
            skid_is_ebreak_r <= 1'b0;
            skid_branch_r <= 3'b000;
            skid_src1_value_r <= 32'b0;
            skid_from_fwd_dep_r <= 1'b0;
            skid_fast_mul_stat_r <= 1'b0;
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
            stat_exmem_skid_candidate_r <= 64'd0;
            stat_exmem_skid_enqueue_r <= 64'd0;
            stat_exmem_skid_dequeue_r <= 64'd0;
            stat_exmem_skid_full_stall_r <= 64'd0;
            stat_exmem_skid_flush_drop_r <= 64'd0;
            stat_exmem_skid_blocked_not_safe_r <= 64'd0;
            stat_exmem_skid_blocked_branch_r <= 64'd0;
            stat_exmem_skid_blocked_mem_r <= 64'd0;
            stat_exmem_skid_blocked_csr_r <= 64'd0;
            stat_exmem_skid_blocked_exception_r <= 64'd0;
            stat_exmem_skid_blocked_div_r <= 64'd0;
            stat_exmem_skid_blocked_structural_r <= 64'd0;
            stat_exmem_skid_hold_cycles_r <= 64'd0;
            stat_exmem_skid_hold_mem_wait_cycles_r <= 64'd0;
            stat_exmem_skid_dequeue_after_mem_release_r <= 64'd0;
            stat_exmem_skid_dequeue_same_cycle_mem_release_r <= 64'd0;
            stat_exmem_skid_dequeue_causes_wb_valid_r <= 64'd0;
`endif
`endif
        end else if (flush) begin
            mreq_valid_r <= 1'b0;
            mresp_valid_r <= 1'b0;
            mresp_atomic_phase2_r <= 1'b0;
            mresp_atomic_write_sent_r <= 1'b0;
            mresp_atomic_old_r <= 32'b0;
            mresp_atomic_wdata_r <= 32'b0;
            mresp_split_r <= 1'b0;
            mresp_split_first_done_r <= 1'b0;
            mresp_split_second_sent_r <= 1'b0;
            mresp_split_first_data_r <= 32'b0;
            mresp_split_first_bytes_r <= 3'b0;
            lrsc_valid_r <= 1'b0;
            skid_valid_r <= 1'b0;
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
            if (skid_valid_r) begin
                stat_exmem_skid_flush_drop_r <= stat_exmem_skid_flush_drop_r + 64'd1;
            end
`endif
`endif
        end else begin
            // 一旦该mresp已经被提交到WB（ms_to_ws_valid握手成功），就应当释放mresp槽位。
            // 仅依赖mem_resp_fire来清槽会在某些握手边界下造成“同一条响应重复提交”。
            if (mresp_commit_fire && !mreq_mem_fire) begin
                mresp_valid_r <= 1'b0;
            end

            if (atomic_phase2_req_fire) begin
                mresp_atomic_write_sent_r <= 1'b1;
            end
            if (split_second_req_fire) begin
                mresp_split_second_sent_r <= 1'b1;
            end

            if (mem_resp_fire && mresp_split_r && !mresp_split_first_done_r) begin
                mresp_split_first_done_r <= 1'b1;
                mresp_split_first_data_r <= mresp_is_load ? mresp_load_data_aligned : 32'b0;
            end

            // AMO 第1阶段：收到读响应
            // 1) 锁存 old（用于 rd 返回）
            // 2) 锁存 new（phase2 写回值）
            // 3) 进入 phase2（发写请求）
            if (mem_resp_fire && mresp_phase1_amo_read) begin
                mresp_atomic_old_r <= mresp_load_data_aligned;
                mresp_atomic_wdata_r <= amo_wdata_calc;
                mresp_atomic_phase2_r <= 1'b1;
                mresp_atomic_write_sent_r <= 1'b0;
            end

            if (mreq_mem_fire) begin
                mresp_valid_r <= 1'b1;
                mresp_pc_r <= mreq_pc_r;
                mresp_instr_r <= mreq_instr_r;
                mresp_nextpc_r <= mreq_nextpc_r;
                mresp_rd_r <= mreq_rd_r;
                mresp_reg_wen_r <= mreq_reg_wen_r;
                mresp_datatoreg_r <= mreq_datatoreg_r;
                mresp_mem_wr_r <= mreq_mem_wr_r;
                mresp_mem_op_r <= mreq_mem_op_r;
                mresp_atomic_en_r <= mreq_atomic_en_r;
                mresp_atomic_op_r <= mreq_atomic_op_r;
                mresp_store_data_r <= mreq_store_data_r;
                mresp_aluout_r <= mreq_aluout_r;
                mresp_csr_read_data_r <= mreq_csr_read_data_r;
                mresp_csr_wen_r <= mreq_csr_wen_r;
                mresp_csr_waddr1_r <= mreq_csr_waddr1_r;
                mresp_csr_waddr2_r <= mreq_csr_waddr2_r;
                mresp_csr_wdata1_r <= mreq_csr_wdata1_r;
                mresp_csr_wdata2_r <= mreq_csr_wdata2_r;
                mresp_illegal_r <= mreq_illegal_r;
                mresp_exc_valid_r <= mreq_exc_valid_eff;
                mresp_exc_cause_r <= mreq_exc_cause_eff;
                mresp_exc_tval_r <= mreq_exc_tval_eff;
                mresp_is_ebreak_r <= mreq_is_ebreak_r;
                mresp_branch_r <= mreq_branch_r;
                mresp_src1_value_r <= mreq_src1_value_r;
                mresp_fast_mul_stat_r <= mreq_fast_mul_stat_r;
                mresp_atomic_phase2_r <= 1'b0;
                mresp_atomic_write_sent_r <= 1'b0;
                mresp_atomic_old_r <= 32'b0;
                mresp_atomic_wdata_r <= 32'b0;
                mresp_atomic_sc_success_r <= mreq_sc_success;
                mresp_split_r <= mreq_split_access;
                mresp_split_first_done_r <= 1'b0;
                mresp_split_second_sent_r <= 1'b0;
                mresp_split_first_data_r <= 32'b0;
                mresp_split_first_bytes_r <= mreq_first_bytes;
                // 提前建立LR reservation（请求发出即记录），避免在某些握手边界下
                // LR响应尚未回写状态而紧随其后的SC被误判失败。
                if (mreq_is_atomic_lr) begin
                    lrsc_valid_r <= 1'b1;
                    lrsc_addr_r <= {mreq_aluout_r[31:2], 2'b00};
                end
            end

            if (mem_resp_fire && mresp_atomic_en_r) begin
                if (mresp_is_atomic_lr) begin
                    lrsc_valid_r <= 1'b1;
                    lrsc_addr_r <= {mresp_aluout_r[31:2], 2'b00};
                end else if (mresp_is_atomic_sc) begin
                    lrsc_valid_r <= 1'b0;
                end else if (mresp_is_atomic_amo && mresp_atomic_phase2_r) begin
                    // AMO 第2阶段完成：写响应返回后，清除 phase2 状态
                    lrsc_valid_r <= 1'b0;
                    mresp_atomic_phase2_r <= 1'b0;
                    mresp_atomic_write_sent_r <= 1'b0;
                end
            end

            if (mem_resp_fire && mresp_resp_exc) begin
                mresp_exc_valid_r <= 1'b1;
                mresp_exc_cause_r <= dbus_resp_exc_cause;
                mresp_exc_tval_r <= dbus_resp_exc_tval;
                if (mresp_atomic_en_r) begin
                    lrsc_valid_r <= 1'b0;
                end
            end

            // Any successful non-atomic store also clears LR reservation.
            if (mreq_mem_fire && mreq_req_write && !mreq_atomic_en_r) begin
                lrsc_valid_r <= 1'b0;
            end
            if (mreq_sc_fail_fire) begin
                lrsc_valid_r <= 1'b0;
            end

`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
            if (skid_candidate_pulse) begin
                stat_exmem_skid_candidate_r <= stat_exmem_skid_candidate_r + 64'd1;
                if (skid_valid_r) begin
                    stat_exmem_skid_full_stall_r <= stat_exmem_skid_full_stall_r + 64'd1;
                end else if (es_skid_block_mem) begin
                    stat_exmem_skid_blocked_mem_r <= stat_exmem_skid_blocked_mem_r + 64'd1;
                end else if (es_skid_block_branch) begin
                    stat_exmem_skid_blocked_branch_r <= stat_exmem_skid_blocked_branch_r + 64'd1;
                end else if (es_skid_block_csr) begin
                    stat_exmem_skid_blocked_csr_r <= stat_exmem_skid_blocked_csr_r + 64'd1;
                end else if (es_skid_block_exception) begin
                    stat_exmem_skid_blocked_exception_r <= stat_exmem_skid_blocked_exception_r + 64'd1;
                end else if (es_is_div_or_unstable_mdu) begin
                    stat_exmem_skid_blocked_div_r <= stat_exmem_skid_blocked_div_r + 64'd1;
                end else if (mresp_valid_r) begin
                    stat_exmem_skid_blocked_structural_r <= stat_exmem_skid_blocked_structural_r + 64'd1;
                end else if (skid_can_enqueue) begin
                    stat_exmem_skid_enqueue_r <= stat_exmem_skid_enqueue_r + 64'd1;
                end else begin
                    stat_exmem_skid_blocked_not_safe_r <= stat_exmem_skid_blocked_not_safe_r + 64'd1;
                end
            end
            if (skid_dequeue_to_mreq || skid_commit_fire) begin
                stat_exmem_skid_dequeue_r <= stat_exmem_skid_dequeue_r + 64'd1;
            end
            if (skid_valid_r) begin
                stat_exmem_skid_hold_cycles_r <= stat_exmem_skid_hold_cycles_r + 64'd1;
            end
            if (skid_mem_wait) begin
                stat_exmem_skid_hold_mem_wait_cycles_r <=
                    stat_exmem_skid_hold_mem_wait_cycles_r + 64'd1;
            end
            if (skid_dequeue_fire) begin
                if (skid_mem_release) begin
                    stat_exmem_skid_dequeue_same_cycle_mem_release_r <=
                        stat_exmem_skid_dequeue_same_cycle_mem_release_r + 64'd1;
                end else begin
                    stat_exmem_skid_dequeue_after_mem_release_r <=
                        stat_exmem_skid_dequeue_after_mem_release_r + 64'd1;
                end
                if (skid_commit_fire) begin
                    stat_exmem_skid_dequeue_causes_wb_valid_r <=
                        stat_exmem_skid_dequeue_causes_wb_valid_r + 64'd1;
                end
            end
`endif
`endif

            if (skid_can_enqueue) begin
                skid_valid_r <= 1'b1;
                skid_pc_r <= es_pc;
                skid_instr_r <= es_instr;
                skid_nextpc_r <= es_nextpc;
                skid_rd_r <= es_rd;
                skid_reg_wen_r <= es_reg_wen;
                skid_datatoreg_r <= es_datatoreg;
                skid_mem_wr_r <= es_mem_wr;
                skid_mem_op_r <= es_mem_op;
                skid_atomic_en_r <= es_atomic_en;
                skid_atomic_op_r <= es_atomic_op;
                skid_aluout_r <= es_aluout;
                skid_store_data_r <= es_mem_wdata;
                skid_csr_read_data_r <= es_csr_read_data;
                skid_csr_wen_r <= es_csr_wen;
                skid_csr_waddr1_r <= es_csr_waddr1;
                skid_csr_waddr2_r <= es_csr_waddr2;
                skid_csr_wdata1_r <= es_csr_wdata1;
                skid_csr_wdata2_r <= es_csr_wdata2;
                skid_illegal_r <= es_illegal;
                skid_exc_valid_r <= es_exc_valid;
                skid_exc_cause_r <= es_exc_cause;
                skid_exc_tval_r <= es_exc_tval;
                skid_is_ebreak_r <= es_is_ebreak;
                skid_branch_r <= es_branch;
                skid_src1_value_r <= es_src1_value;
                skid_from_fwd_dep_r <= es_mem_fwd_dep;
                skid_fast_mul_stat_r <= es_fast_mul_stat;
            end

            if (skid_dequeue_to_mreq) begin
                mreq_valid_r <= 1'b1;
                mreq_pc_r <= skid_pc_r;
                mreq_instr_r <= skid_instr_r;
                mreq_nextpc_r <= skid_nextpc_r;
                mreq_rd_r <= skid_rd_r;
                mreq_reg_wen_r <= skid_reg_wen_r;
                mreq_datatoreg_r <= skid_datatoreg_r;
                mreq_mem_wr_r <= skid_mem_wr_r;
                mreq_mem_op_r <= skid_mem_op_r;
                mreq_atomic_en_r <= skid_atomic_en_r;
                mreq_atomic_op_r <= skid_atomic_op_r;
                mreq_aluout_r <= skid_aluout_r;
                mreq_store_data_r <= skid_store_data_r;
                mreq_csr_read_data_r <= skid_csr_read_data_r;
                mreq_csr_wen_r <= skid_csr_wen_r;
                mreq_csr_waddr1_r <= skid_csr_waddr1_r;
                mreq_csr_waddr2_r <= skid_csr_waddr2_r;
                mreq_csr_wdata1_r <= skid_csr_wdata1_r;
                mreq_csr_wdata2_r <= skid_csr_wdata2_r;
                mreq_illegal_r <= skid_illegal_r;
                mreq_exc_valid_r <= skid_exc_valid_r;
                mreq_exc_cause_r <= skid_exc_cause_r;
                mreq_exc_tval_r <= skid_exc_tval_r;
                mreq_is_ebreak_r <= skid_is_ebreak_r;
                mreq_branch_r <= skid_branch_r;
                mreq_src1_value_r <= skid_src1_value_r;
                mreq_from_fwd_dep_r <= skid_from_fwd_dep_r;
                mreq_fast_mul_stat_r <= skid_fast_mul_stat_r;
                skid_valid_r <= 1'b0;
            end else if (old_mreq_allowin && (!skid_valid_r || skid_commit_fire)) begin
                mreq_valid_r <= es_to_ms_valid;
                if (skid_commit_fire) begin
                    skid_valid_r <= 1'b0;
                end
                if (es_to_ms_valid) begin
                    mreq_pc_r <= es_pc;
                    mreq_instr_r <= es_instr;
                    mreq_nextpc_r <= es_nextpc;
                    mreq_rd_r <= es_rd;
                    mreq_reg_wen_r <= es_reg_wen;
                    mreq_datatoreg_r <= es_datatoreg;
                    mreq_mem_wr_r <= es_mem_wr;
                    mreq_mem_op_r <= es_mem_op;
                    mreq_atomic_en_r <= es_atomic_en;
                    mreq_atomic_op_r <= es_atomic_op;
                    mreq_aluout_r <= es_aluout;
                    mreq_store_data_r <= es_mem_wdata;
                    mreq_csr_read_data_r <= es_csr_read_data;
                    mreq_csr_wen_r <= es_csr_wen;
                    mreq_csr_waddr1_r <= es_csr_waddr1;
                    mreq_csr_waddr2_r <= es_csr_waddr2;
                    mreq_csr_wdata1_r <= es_csr_wdata1;
                    mreq_csr_wdata2_r <= es_csr_wdata2;
                    mreq_illegal_r <= es_illegal;
                    mreq_exc_valid_r <= es_exc_valid;
                    mreq_exc_cause_r <= es_exc_cause;
                    mreq_exc_tval_r <= es_exc_tval;
                    mreq_is_ebreak_r <= es_is_ebreak;
                    mreq_branch_r <= es_branch;
                    mreq_src1_value_r <= es_src1_value;
                    mreq_from_fwd_dep_r <= es_mem_fwd_dep;
                    mreq_fast_mul_stat_r <= es_fast_mul_stat;
                end
            end
        end
    end
endmodule
