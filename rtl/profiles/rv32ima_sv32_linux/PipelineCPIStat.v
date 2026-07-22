`timescale 1ns / 1ps

`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
module PipelineCPIStat (
    input clk,
    input rst_n,

    input fs_to_ds_valid,
    input if_stall,
    input ds_allowin,
    input ds_to_es_valid,
    input es_allowin,
    input es_to_ms_valid,
    input ms_allowin,
    input ms_to_ws_valid,
    input ws_allowin,
    input es_valid,
    input ms_valid,
    input ws_valid,

    input id_stage_block,
    input id_stage_block_reg_hazard,
    input id_stage_block_csr_hazard,
    input id_stage_block_load_use,
    input id_stage_block_ex_raw,
    input id_stage_block_ms_raw,
    input id_stage_block_hidden_raw,
    input ds_stat_uses_rs1,
    input ds_stat_uses_rs2,
    input ds_stat_rs1_match_es,
    input ds_stat_rs1_match_ms,
    input ds_stat_rs1_match_hidden,
    input ds_stat_rs1_match_ws,
    input ds_stat_rs2_match_es,
    input ds_stat_rs2_match_ms,
    input ds_stat_rs2_match_hidden,
    input ds_stat_rs2_match_ws,
    input ds_stat_csr_counter_hazard,
    input ds_stat_rs1_ex_alu_fwd,
    input ds_stat_rs2_ex_alu_fwd,
    input ds_stat_fwd_load_block,
    input ds_stat_fwd_csr_block,
    input ds_stat_fwd_kill_block,
    input ex_stage_block,
    input ex_stage_block_mdu_wait,
    input ex_stage_block_redirect_wait,
    input es_result_bypassable,
    input [1:0] es_datatoreg,
    input [1:0] es_mem_wr,
    input es_atomic_en,
    input [1:0] es_csr_wen,
    input es_stat_is_mdu,
    input es_stat_rs1_mem_alu_fwd,
    input es_stat_rs2_mem_alu_fwd,
    input es_stat_rs1_wb_fwd,
    input es_stat_rs2_wb_fwd,
    input es_stat_rs1_load_fwd,
    input es_stat_rs2_load_fwd,
    input [2:0] es_stat_mdu_op,
    input es_stat_mdu_req_fire,
    input es_stat_mdu_resp_valid,
    input es_stat_mdu_busy,
    input es_stat_mdu_result_ready,
    input es_stat_fast_mul,
    input es_stat_fast_mul_issue,
    input es_stat_fast_mul_resp,
    input es_stat_fast_mul_kill,
    input es_stat_fast_mul_flush_drop,
    input es_stat_fast_mul_forward,
    input es_stat_fast_mul_stall_wait_ready,
    input es_stat_old_div_path,
    input es_stat_old_rem_path,
    input ms_stage_block,
    input ms_stage_block_req_phase,
    input ms_stage_block_resp_phase,
    input ms_stage_block_load,
    input ms_stage_block_store,
    input ms_stage_block_req_load,
    input ms_stage_block_req_store,
    input ms_stage_block_resp_load,
    input ms_stage_block_resp_store,
    input [1:0] ms_datatoreg,
    input [1:0] ms_csr_wen,
    input ms_fwd_valid,
    input ms_stat_load_visible,
    input ms_stat_load_aligned,
    input ms_stat_load_result_ready,
    input ms_stat_load_fault,
    input ms_stat_load_signext_ready,
    input ms_stat_load_req_fire,
    input ms_stat_load_resp_valid,
    input ms_stat_load_resp_fire,
    input ms_stat_load_data_ready,
    input ms_stat_load_signext_data_ready,
    input ms_stat_load_to_wb_valid,
    input ms_stat_load_split_or_misaligned,
    input ms_stat_load_uncached,
    input ms_stat_load_atomic,
    input ms_stat_load_killed,
    input ms_stat_hidden_load,
    input ms_stat_load_store_block,
    input ms_stat_load_lsu_pending,
    input ms_stat_mreq_valid,
    input ms_stat_mreq_is_load,
    input ms_stat_mreq_is_store,
    input ms_stat_mreq_is_atomic,
    input ms_stat_mreq_need_mem,
    input ms_stat_mreq_fire,
    input ms_stat_mreq_misaligned,
    input ms_stat_mreq_split,
    input ms_stat_mreq_fault,
    input ms_stat_mreq_blocked_by_resp,
    input ms_stat_mresp_valid,
    input ms_stat_mresp_is_load,
    input ms_stat_mresp_is_store,
    input ms_stat_mresp_is_atomic,
    input ms_stat_mresp_resp_valid,
    input ms_stat_mresp_resp_fire,
    input ms_stat_mresp_split,
    input ms_stat_mresp_fault,
    input ms_stat_store_visible,
    input ms_stat_store_req_fire,
    input ms_stat_store_resp_valid,
    input ms_stat_store_resp_fire,
    input ms_stat_store_aligned,
    input ms_stat_store_fault,
    input ms_stat_store_split_or_misaligned,
    input ms_stat_store_uncached,
    input ms_stat_store_atomic,
    input ms_stat_store_killed,
    input ms_stat_store_buffer_safe,
    input ms_stat_store_resp_wait,
    input ms_stat_single_outstanding_wait,
    input ms_stat_uncached_wait,
    input ms_stat_writeback_wait,
    input [63:0] stat_exmem_skid_candidate,
    input [63:0] stat_exmem_skid_enqueue,
    input [63:0] stat_exmem_skid_dequeue,
    input [63:0] stat_exmem_skid_full_stall,
    input [63:0] stat_exmem_skid_flush_drop,
    input [63:0] stat_exmem_skid_blocked_not_safe,
    input [63:0] stat_exmem_skid_blocked_branch,
    input [63:0] stat_exmem_skid_blocked_mem,
    input [63:0] stat_exmem_skid_blocked_csr,
    input [63:0] stat_exmem_skid_blocked_exception,
    input [63:0] stat_exmem_skid_blocked_div,
    input [63:0] stat_exmem_skid_blocked_structural,
    input [63:0] stat_exmem_skid_hold_cycles,
    input [63:0] stat_exmem_skid_hold_mem_wait_cycles,
    input [63:0] stat_exmem_skid_dequeue_after_mem_release,
    input [63:0] stat_exmem_skid_dequeue_same_cycle_mem_release,
    input [63:0] stat_exmem_skid_dequeue_causes_wb_valid,
    input stat_exmem_skid_valid,
    input stat_exmem_skid_enqueue_fire,
    input stat_exmem_skid_dequeue_fire,
    input stat_exmem_skid_dequeue_commit_fire,
    input stat_exmem_skid_dequeue_to_mreq_fire,
    input stat_exmem_skid_mem_wait,
    input stat_exmem_skid_mem_release,
    input [63:0] store_buffer_enqueue_count,
    input [63:0] store_buffer_dequeue_count,
    input [63:0] store_buffer_full_stall_count,
    input [63:0] store_buffer_drain_req_count,
    input [63:0] store_buffer_drain_resp_count,
    input [63:0] store_buffer_drain_wait_count,
    input [63:0] store_buffer_load_forward_count,
    input [63:0] store_buffer_load_stall_conflict_count,
    input [63:0] store_buffer_load_stall_buffer_nonempty_count,
    input [63:0] store_buffer_fence_drain_wait_count,
    input [63:0] store_buffer_uncached_drain_wait_count,
    input [63:0] store_buffer_killed_store_block_count,
    input [63:0] store_buffer_occupancy0_count,
    input [63:0] store_buffer_occupancy1_count,
    input [63:0] store_buffer_occupancy2_count,
    input [63:0] store_buffer_max_occupancy_count,
    input [63:0] store_buffer_enqueue_occ0_count,
    input [63:0] store_buffer_enqueue_occ1_count,
    input [63:0] store_buffer_enqueue_full_count,
    input [63:0] dhitopt_candidate_count,
    input [63:0] dhitopt_success_count,
    input [63:0] dhitopt_fallback_count,
    input [63:0] dhitopt_block_store_buffer_count,
    input [63:0] dhitopt_block_uncached_count,
    input [63:0] dhitopt_block_fault_count,
    input [63:0] dhitopt_block_miss_count,
    input [63:0] dhitopt_block_alignment_count,
    input [63:0] dhitopt_unknown_count,
    input [1:0] hidden_mreq_datatoreg,
    input [1:0] hidden_mreq_mem_wr,
    input [1:0] hidden_mreq_csr_wen,
    input [1:0] ws_stat_datatoreg,
    input [2:0] ws_stat_mem_op,
    input [1:0] ws_csr_wen,

    input redirect_flush_valid,
    input redirect_clear_valid,
    input stop_clear_valid,
    input trap_redirect_valid,
    input fencei_start,
    input vm_flush_start,
    input fencei_maint_active,

    input ibus_req_valid,
    input ibus_req_ready,
    input ibus_resp_valid,
    input ibus_resp_ready,
    input dbus_req_valid,
    input dbus_req_ready,
    input dbus_resp_valid,
    input dbus_resp_ready,

    input [63:0] branch_redirect_wait_cycle,
    input [63:0] icache_req_wait_cycle,
    input [63:0] icache_hit_resp_wait_cycle,
    input [63:0] icache_miss_wait_cycle,
    input [63:0] dcache_req_wait_cycle,
    input [63:0] dcache_hit_resp_wait_cycle,
    input [63:0] dcache_miss_wait_cycle,
    input [63:0] dcache_uncached_access,
    input [63:0] dcache_writeback_cycle,
    input [63:0] if_pipe_epoch_drop_count,
    input [63:0] if_pipe_stall_cycle,
    input [63:0] if_pipe_icache_miss_count,

    input if_stat_fs_valid,
    input [1:0] if_stat_queue_count,
    input if_stat_fetch_room,
    input if_stat_req_fire,
    input if_stat_resp_fire,
    input if_stat_resp_accept,
    input if_stat_resp_drop,
    input if_stat_bypass_direct,
    input if_stat_waiting_resp,
    input if_stat_drop_resp,
    input if_stat_fs_pop,
    input if_stat_resp_enq,
    input if_stat_queue_full,
    input if_stat_resp_block,
    input if_pipe_stat_outstanding,
    input if_pipe_stat_replay_valid,
    input if_pipe_stat_ptw_busy,
    input if_pipe_stat_req_valid,
    input if_pipe_stat_req_ready,
    input if_pipe_stat_resp_current,
    input if_pipe_stat_resp_stale,
    input if_pipe_stat_lower_req_valid,
    input if_pipe_stat_lower_req_ready,
    input if_pipe_stat_lower_resp_valid,
    input if_pipe_stat_lower_resp_ready,
    input icache_pipe_resp_valid,
    input icache_pipe_resp_ready,
    input [63:0] icache_pipe_resp_fifo_full_cycle,

    input commit_valid,
    input commit_is_ebreak,
    input commit_illegal
);
    reg [63:0] cycle_count;
    reg [63:0] commit_count;
    reg [63:0] bubble_count;

    reg [63:0] bucket_trap_flush;
    reg [63:0] bucket_wb_block;
    reg [63:0] bucket_mem_lsu_wait;
    reg [63:0] bucket_dcache_wait;
    reg [63:0] bucket_store_wait;
    reg [63:0] bucket_load_use;
    reg [63:0] bucket_raw_hazard;
    reg [63:0] bucket_csr_special;
    reg [63:0] bucket_id_stall;
    reg [63:0] bucket_ex_stall;
    reg [63:0] bucket_if_id_empty;
    reg [63:0] bucket_frontend_wait;
    reg [63:0] bucket_icache_fetch_wait;
    reg [63:0] bucket_branch_recovery;
    reg [63:0] bucket_resp_block;
    reg [63:0] bucket_stage_latency;
    reg [63:0] bucket_unknown;

    reg [63:0] occ_if;
    reg [63:0] occ_ifid;
    reg [63:0] occ_id;
    reg [63:0] occ_ex;
    reg [63:0] occ_mem;
    reg [63:0] occ_wb;
    reg [63:0] occ_commit;

    reg [63:0] stall_if_by_ifid_full;
    reg [63:0] stall_ifid_by_id_not_ready;
    reg [63:0] stall_id_by_ex_not_ready;
    reg [63:0] stall_ex_by_mem_not_ready;
    reg [63:0] stall_mem_by_wb_not_ready;
    reg [63:0] stall_mem_by_dbus;
    reg [63:0] stall_wb;

    reg [63:0] frontend_if_pipe_no_resp;
    reg [63:0] frontend_backpressure;
    reg [63:0] frontend_epoch_drop_recovery;
    reg [63:0] frontend_icache_miss_wait_seen;
    reg [63:0] frontend_icache_refill_wait_seen;
    reg [63:0] frontend_itlb_miss_wait_seen;
    reg [63:0] frontend_self_wait;
    reg [63:0] frontend_backpressure_wait;
    reg [63:0] frontend_ifid_queue_full_wait;
    reg [63:0] frontend_id_not_ready_backpressure;
    reg [63:0] frontend_ex_not_ready_backpressure;
    reg [63:0] frontend_if_pipe_no_resp_wait;
    reg [63:0] frontend_if_pipe_req_not_ready_wait;
    reg [63:0] frontend_icache_miss_refill_wait;
    reg [63:0] frontend_icache_req_wait;
    reg [63:0] frontend_epoch_drop_recovery_wait;
    reg [63:0] frontend_ptw_wait;
    reg [63:0] frontend_unknown;

    reg [63:0] mem_load_resp_wait;
    reg [63:0] mem_store_resp_wait;
    reg [63:0] mem_load_req_wait;
    reg [63:0] mem_store_req_wait;
    reg [63:0] mem_store_wait;
    reg [63:0] mem_load_wait;
    reg [63:0] mem_single_outstanding_wait;
    reg [63:0] prev_icache_req_wait_cycle;
    reg [63:0] prev_icache_miss_wait_cycle;
    reg [63:0] prev_dcache_miss_wait_cycle;
    reg [63:0] prev_dcache_uncached_access;
    reg [63:0] prev_dcache_writeback_cycle;
    reg [63:0] prev_store_buffer_drain_wait_count;
    reg [63:0] prev_store_buffer_load_stall_conflict_count;
    reg [63:0] prev_icache_pipe_resp_fifo_full_cycle;
    reg [63:0] prev_if_pipe_epoch_drop_count;
    reg [63:0] prev_if_pipe_icache_miss_count;
    reg [63:0] ready_if;
    reg [63:0] ready_ifid;
    reg [63:0] ready_id;
    reg [63:0] ready_ex;
    reg [63:0] ready_mem;
    reg [63:0] ready_wb;
    reg [63:0] resp_block_total;
    reg [63:0] resp_block_if_queue_full;
    reg [63:0] resp_block_id_not_ready;
    reg [63:0] resp_block_epoch_drop;
    reg [63:0] resp_block_fifo_full;
    reg [63:0] resp_block_wait_commit;
    reg [63:0] resp_block_if_stage_not_accepting;
    reg [63:0] resp_block_unknown;
    reg [63:0] stage_latency_ifid_valid;
    reg [63:0] stage_latency_id_valid;
    reg [63:0] stage_latency_ex_valid;
    reg [63:0] stage_latency_mem_valid;
    reg [63:0] stage_latency_frontend_empty;
    reg [63:0] ifq_depth0_cycles;
    reg [63:0] ifq_depth1_cycles;
    reg [63:0] ifq_depth2_cycles;
    reg [63:0] ifq_full_cycles;
    reg [63:0] ifq_empty_cycles;
    reg [63:0] ifq_push_attempt;
    reg [63:0] ifq_push_fire;
    reg [63:0] ifq_push_block;
    reg [63:0] ifq_pop_attempt;
    reg [63:0] ifq_pop_fire;
    reg [63:0] ifq_pop_block;
    reg [63:0] ifq_entry0_valid_cycles;
    reg [63:0] ifq_entry1_valid_cycles;
    reg [63:0] ifq_both_valid_cycles;
    reg [63:0] ifq_single_valid_cycles;
    reg [63:0] ifq_block_full_no_pop;
    reg [63:0] ifq_block_full_with_pop_same_cycle;
    reg [63:0] ifq_block_full_id_ready;
    reg [63:0] ifq_block_full_id_not_ready;
    reg [63:0] ifq_block_backend_stall;
    reg [63:0] ifq_block_redirect;
    reg [63:0] ifq_block_epoch_drop;
    reg [63:0] ifq_block_load_use;
    reg [63:0] ifq_block_raw_hazard;
    reg [63:0] ifq_block_mem_lsu;
    reg [63:0] ifq_block_csr_special;
    reg [63:0] ifq_block_unknown;
    reg [63:0] hazard_load_use_total;
    reg [63:0] hazard_raw_total;
    reg [63:0] hazard_csr_total;
    reg [63:0] hazard_mem_lsu_total;
    reg [63:0] hazard_rs1;
    reg [63:0] hazard_rs2;
    reg [63:0] hazard_both;
    reg [63:0] hazard_operand_unknown;
    reg [63:0] hazard_ex_alu;
    reg [63:0] hazard_mem_alu;
    reg [63:0] hazard_wb;
    reg [63:0] hazard_load_hit;
    reg [63:0] hazard_load_miss;
    reg [63:0] hazard_lsu_pending;
    reg [63:0] hazard_csr;
    reg [63:0] hazard_muldiv;
    reg [63:0] hazard_store;
    reg [63:0] hazard_branch;
    reg [63:0] hazard_system;
    reg [63:0] hazard_unknown;
    reg [63:0] fwd_ex_alu_to_ex;
    reg [63:0] fwd_mem_alu_to_ex;
    reg [63:0] fwd_wb_to_ex;
    reg [63:0] fwd_load_hit_to_ex;
    reg [63:0] fwd_load_miss_not_bypassable;
    reg [63:0] fwd_csr_not_bypassable;
    reg [63:0] fwd_muldiv_not_bypassable;
    reg [63:0] fwd_memory_order_not_bypassable;
    reg [63:0] fwd_unknown;
    reg [63:0] fwd_stat_rs1_ex_alu;
    reg [63:0] fwd_stat_rs2_ex_alu;
    reg [63:0] fwd_stat_rs1_mem_alu;
    reg [63:0] fwd_stat_rs2_mem_alu;
    reg [63:0] fwd_stat_rs1_wb;
    reg [63:0] fwd_stat_rs2_wb;
    reg [63:0] fwd_stat_x0_block;
    reg [63:0] fwd_stat_load_block;
    reg [63:0] fwd_stat_csr_block;
    reg [63:0] fwd_stat_kill_block;
    reg [63:0] load_pending_true_dcache_load_miss_wait;
    reg [63:0] load_pending_load_hit_no_forward_wait;
    reg [63:0] load_pending_load_wait_mem_resp;
    reg [63:0] load_pending_load_wait_wb;
    reg [63:0] load_pending_blocked_by_store_miss;
    reg [63:0] load_pending_blocked_by_uncached;
    reg [63:0] load_pending_lsu_single_outstanding_wait;
    reg [63:0] load_pending_other;
    reg [63:0] loadhit_total;
    reg [63:0] loadhit_aligned_hit;
    reg [63:0] loadhit_unaligned;
    reg [63:0] loadhit_dtlb_hit;
    reg [63:0] loadhit_dcache_hit;
    reg [63:0] loadhit_uncached;
    reg [63:0] loadhit_fault;
    reg [63:0] loadhit_signext_ready;
    reg [63:0] loadhit_consumer_rs1;
    reg [63:0] loadhit_consumer_rs2;
    reg [63:0] loadhit_producer_killed;
    reg [63:0] loadhit_same_cycle_possible;
    reg [63:0] loadhit_mem_to_ex_possible;
    reg [63:0] loadhit_wb_only;
    reg [63:0] loadhit_not_safe;
    reg [63:0] loadhit_unknown;
    reg [63:0] loadhit_timing_total;
    reg [63:0] loadhit_timing_data_valid_cycle;
    reg [63:0] loadhit_timing_signext_ready_cycle;
    reg [63:0] loadhit_timing_wb_ready_cycle;
    reg [63:0] loadhit_timing_consumer_wait_ex;
    reg [63:0] loadhit_timing_consumer_wait_mem;
    reg [63:0] loadhit_timing_consumer_wait_wb;
    reg [63:0] load_forward_safe_mem_to_ex;
    reg [63:0] load_forward_safe_memwb_to_ex;
    reg [63:0] load_forward_safe_wb_to_ex;
    reg [63:0] load_forward_blocked_uncached;
    reg [63:0] load_forward_blocked_fault;
    reg [63:0] load_forward_blocked_misaligned;
    reg [63:0] load_forward_blocked_kill;
    reg [63:0] load_forward_blocked_not_signext;
    reg [63:0] load_forward_blocked_lsu_pending;
    reg [63:0] load_forward_unknown;
    reg [63:0] load_use_load_hit;
    reg [63:0] load_use_load_miss;
    reg [63:0] load_use_lsu_busy;
    reg [63:0] load_use_wait_mem;
    reg [63:0] load_use_wait_wb;
    reg [63:0] load_use_same_cycle_resp_possible;
    reg [63:0] load_use_unknown;
    reg [63:0] raw_alu_ex;
    reg [63:0] raw_alu_mem;
    reg [63:0] raw_alu_wb;
    reg [63:0] raw_load_mem;
    reg [63:0] raw_load_wb;
    reg [63:0] raw_csr;
    reg [63:0] raw_muldiv;
    reg [63:0] raw_hidden;
    reg [63:0] raw_unknown;
    reg [63:0] mdu_mul_total;
    reg [63:0] mdu_mul_wait_cycles;
    reg [63:0] mdu_mul_consumer_stall;
    reg [63:0] mdu_mul_latency_sum;
    reg [63:0] mdu_mul_max_latency;
    reg [63:0] mdu_mulh_total;
    reg [63:0] mdu_mulh_wait_cycles;
    reg [63:0] mdu_div_total;
    reg [63:0] mdu_div_wait_cycles;
    reg [63:0] mdu_div_latency_sum;
    reg [63:0] mdu_div_max_latency;
    reg [63:0] mdu_rem_total;
    reg [63:0] mdu_rem_wait_cycles;
    reg [63:0] mdu_busy_cycles;
    reg [63:0] mdu_result_ready_cycles;
    reg [63:0] mdu_consumer_wait_cycles;
    reg [63:0] mdu_unknown;
    reg [63:0] mdu_current_latency;
    reg [2:0] mdu_current_op;
    reg mdu_current_valid;
    reg [63:0] fast_mul_issue;
    reg [63:0] fast_mul_resp;
    reg [63:0] fast_mul_kill;
    reg [63:0] fast_mul_flush_drop;
    reg [63:0] fast_mul_forward;
    reg [63:0] fast_mul_stall_wait_ready;
    reg [63:0] fast_mul_old_div_path;
    reg [63:0] fast_mul_old_rem_path;
    reg [63:0] fast_mul_total;
    reg [63:0] old_mul_total;
    reg [63:0] mem_backend_load_response_wait;
    reg [63:0] mem_backend_store_response_wait;
    reg [63:0] mem_backend_store_miss_wait;
    reg [63:0] mem_backend_store_write_resp_wait;
    reg [63:0] mem_backend_dcache_miss_wait;
    reg [63:0] mem_backend_dcache_req_wait;
    reg [63:0] mem_backend_single_outstanding_wait;
    reg [63:0] mem_backend_uncached_wait;
    reg [63:0] mem_backend_writeback_wait;
    reg [63:0] mem_backend_other;
    reg [63:0] mem_v2_load_req_total;
    reg [63:0] mem_v2_load_req_fire;
    reg [63:0] mem_v2_load_resp_wait;
    reg [63:0] mem_v2_load_resp_wait_dcache_hit;
    reg [63:0] mem_v2_load_resp_wait_dcache_miss;
    reg [63:0] mem_v2_load_resp_wait_blocked_by_store;
    reg [63:0] mem_v2_load_resp_wait_blocked_by_single;
    reg [63:0] mem_v2_load_resp_wait_uncached;
    reg [63:0] mem_v2_load_resp_wait_other;
    reg [63:0] mem_v2_store_req_total;
    reg [63:0] mem_v2_store_req_fire;
    reg [63:0] mem_v2_store_hit_total;
    reg [63:0] mem_v2_store_miss_total;
    reg [63:0] mem_v2_store_resp_wait;
    reg [63:0] mem_v2_store_hit_resp_wait;
    reg [63:0] mem_v2_store_miss_resp_wait;
    reg [63:0] mem_v2_store_write_resp_wait;
    reg [63:0] mem_v2_store_refill_wait;
    reg [63:0] mem_v2_store_uncached_wait;
    reg [63:0] mem_v2_store_other;
    reg [63:0] mem_v2_single_outstanding_wait;
    reg [63:0] mem_v2_single_load_blocked_by_load;
    reg [63:0] mem_v2_single_load_blocked_by_store;
    reg [63:0] mem_v2_single_store_blocked_by_load;
    reg [63:0] mem_v2_single_store_blocked_by_store;
    reg [63:0] mem_v2_single_uncached;
    reg [63:0] mem_v2_single_other;
    reg [63:0] storebuf_store_total;
    reg [63:0] storebuf_aligned_cached_hit;
    reg [63:0] storebuf_aligned_cached_miss;
    reg [63:0] storebuf_uncached_or_mmio;
    reg [63:0] storebuf_fault_or_page_fault;
    reg [63:0] storebuf_misaligned_or_cross_page;
    reg [63:0] storebuf_atomic_or_lrsc;
    reg [63:0] storebuf_before_fence;
    reg [63:0] storebuf_killed_or_exception;
    reg [63:0] storebuf_safe_candidate;
    reg [63:0] storebuf_not_safe;
    reg [63:0] storebuf_unknown;
    reg [63:0] dcache_proto_load_hit_latency_sum;
    reg [63:0] dcache_proto_load_hit_latency_count;
    reg [63:0] dcache_proto_load_hit_latency_max;
    reg [63:0] dcache_proto_store_hit_latency_sum;
    reg [63:0] dcache_proto_store_hit_latency_count;
    reg [63:0] dcache_proto_store_hit_latency_max;
    reg [63:0] dcache_proto_load_resp_valid_wait_ready;
    reg [63:0] dcache_proto_store_resp_valid_wait_ready;
    reg [63:0] dcache_proto_mem_stage_wait_resp_ready;
    reg [63:0] dcache_proto_wb_stage_backpressure;
    reg [63:0] dcache_proto_resp_protocol_overhead;
    reg [63:0] dcache_proto_current_latency;
    reg dcache_proto_track_valid;
    reg dcache_proto_track_store;
    reg dcache_proto_track_hit;
    reg [63:0] sbuf_drain_overlap_with_useful_pipeline;
    reg [63:0] sbuf_drain_blocks_load;
    reg [63:0] sbuf_drain_blocks_store_enqueue;
    reg [63:0] sbuf_drain_blocks_pipeline_mem;
    reg [63:0] sbuf_drain_blocks_icache_or_ptw;
    reg [63:0] sbuf_drain_background_only;
    reg [63:0] sbuf_drain_unknown;
    reg [63:0] lrp_load_req_total;
    reg [63:0] lrp_load_req_fire;
    reg [63:0] lrp_load_resp_total;
    reg [63:0] lrp_load_resp_fire;
    reg [63:0] lrp_wait_total;
    reg [63:0] lrp_wait_dcache_hit;
    reg [63:0] lrp_wait_dcache_miss;
    reg [63:0] lrp_wait_uncached;
    reg [63:0] lrp_wait_sbuf_drain;
    reg [63:0] lrp_wait_sbuf_conflict;
    reg [63:0] lrp_wait_lsu_busy;
    reg [63:0] lrp_wait_mem_stage_block;
    reg [63:0] lrp_wait_wb_block;
    reg [63:0] lrp_wait_other;
    reg [63:0] dclh_total;
    reg [63:0] dclh_latency_1;
    reg [63:0] dclh_latency_2;
    reg [63:0] dclh_latency_3;
    reg [63:0] dclh_latency_gt3;
    reg [63:0] dclh_latency_sum;
    reg [63:0] dclh_latency_max;
    reg [63:0] dclh_tag_lookup_wait;
    reg [63:0] dclh_data_array_wait;
    reg [63:0] dclh_data_align_wait;
    reg [63:0] dclh_signext_wait;
    reg [63:0] dclh_response_reg_wait;
    reg [63:0] dclh_cpu_resp_wait;
    reg [63:0] dclh_other;
    reg [63:0] loaduse_path_wait_dcache_hit;
    reg [63:0] loaduse_path_wait_dcache_miss;
    reg [63:0] loaduse_path_wait_signext;
    reg [63:0] loaduse_path_wait_memwb;
    reg [63:0] loaduse_path_wait_wb;
    reg [63:0] loaduse_path_wait_lsu_pending;
    reg [63:0] loaduse_path_wait_store_buffer;
    reg [63:0] loaduse_path_wait_other;
    reg [63:0] lbp2_candidate_total;
    reg [63:0] lbp2_safe_dcache_resp_to_ex;
    reg [63:0] lbp2_safe_mem_stage_to_ex;
    reg [63:0] lbp2_safe_memwb_to_ex;
    reg [63:0] lbp2_safe_wb_to_ex;
    reg [63:0] lbp2_blocked_signext_not_ready;
    reg [63:0] lbp2_blocked_resp_not_ready;
    reg [63:0] lbp2_blocked_exception_or_fault;
    reg [63:0] lbp2_blocked_uncached;
    reg [63:0] lbp2_blocked_kill_or_flush;
    reg [63:0] lbp2_blocked_store_buffer_conflict;
    reg [63:0] lbp2_blocked_timing_unknown;
    reg [63:0] lbp2_unknown;
    reg [63:0] lsu_so2_total;
    reg [63:0] lsu_so2_load_blocked_by_load;
    reg [63:0] lsu_so2_load_blocked_by_store;
    reg [63:0] lsu_so2_store_blocked_by_load;
    reg [63:0] lsu_so2_store_blocked_by_store;
    reg [63:0] lsu_so2_load_blocked_by_sbuf_drain;
    reg [63:0] lsu_so2_load_blocked_by_dcache_refill;
    reg [63:0] lsu_so2_load_blocked_by_uncached;
    reg [63:0] lsu_so2_other;
    reg [63:0] lsu_pipe_bridge_load_via;
    reg [63:0] lsu_pipe_bridge_store_via;
    reg [63:0] lsu_pipe_bridge_atomic_via;
    reg [63:0] lsu_load_bypass_candidate;
    reg [63:0] lsu_load_bypass_release_id_stall;
    reg [63:0] lsu_load_bypass_forward_rs1;
    reg [63:0] lsu_load_bypass_forward_rs2;
    reg [63:0] lsu_load_bypass_forward_both;
    reg [63:0] lsu_load_bypass_blocked_not_load;
    reg [63:0] lsu_load_bypass_blocked_rd_x0;
    reg [63:0] lsu_load_bypass_blocked_resp_not_ready;
    reg [63:0] lsu_load_bypass_blocked_signext_not_ready;
    reg [63:0] lsu_load_bypass_blocked_fault;
    reg [63:0] lsu_load_bypass_blocked_kill;
    reg [63:0] lsu_load_bypass_blocked_uncached;
    reg [63:0] lsu_load_bypass_blocked_miss;
    reg [63:0] lsu_load_bypass_blocked_misaligned;
    reg [63:0] lsu_load_bypass_blocked_atomic;
    reg [63:0] lsu_load_bypass_blocked_store_buffer;
    reg [63:0] late_bypass_total_load_dep;
    reg [63:0] late_bypass_distance1;
    reg [63:0] late_bypass_distance2;
    reg [63:0] late_bypass_distance3plus;
    reg [63:0] late_bypass_resp_ready_before_ex;
    reg [63:0] late_bypass_resp_ready_same_cycle_ex;
    reg [63:0] late_bypass_signext_ready_before_ex;
    reg [63:0] late_bypass_safe;
    reg [63:0] late_bypass_actual;
    reg [63:0] late_bypass_unknown;
    reg [63:0] exmem_skid_eff_enqueue_when_ex_would_stall;
    reg [63:0] exmem_skid_eff_enqueue_and_ex_allowin;
    reg [63:0] exmem_skid_eff_enqueue_and_id_allowin;
    reg [63:0] exmem_skid_eff_enqueue_and_if_pop_next;
    reg [63:0] exmem_skid_eff_enqueue_but_upstream_still_stall;
    reg [63:0] exmem_skid_eff_no_gain_skid_full;
    reg [63:0] exmem_skid_eff_no_gain_next_inst_blocked;
    reg [63:0] exmem_skid_eff_no_gain_mem_response_wait;
    reg [63:0] exmem_skid_eff_no_gain_dequeue_same_as_old_path;
    reg [63:0] exmem_skid_eff_unknown;
    reg prev_exmem_skid_enqueue;

    reg printed;

    wire real_commit = commit_valid && !commit_is_ebreak && !commit_illegal;
    wire terminal_commit = commit_valid && (commit_is_ebreak || commit_illegal);
    wire trap_flush_now = trap_redirect_valid || fencei_start || vm_flush_start ||
        redirect_clear_valid || stop_clear_valid || fencei_maint_active;
    wire wb_block_now = ms_to_ws_valid && !ws_allowin;
    wire dbus_req_wait_now = dbus_req_valid && !dbus_req_ready;
    wire dbus_resp_wait_now = dbus_resp_ready && !dbus_resp_valid;
    wire mem_lsu_wait_now = ms_stage_block || (es_to_ms_valid && !ms_allowin) ||
        dbus_req_wait_now || dbus_resp_wait_now;
    wire store_wait_now = ms_stage_block_store || ms_stage_block_req_store ||
        ms_stage_block_resp_store;
    wire dcache_wait_now = dbus_req_wait_now || dbus_resp_wait_now;
    wire load_use_now = id_stage_block_load_use;
    wire raw_hazard_now = id_stage_block_reg_hazard &&
        !id_stage_block_load_use &&
        (id_stage_block_ex_raw || id_stage_block_ms_raw || id_stage_block_hidden_raw);
    wire csr_special_now = id_stage_block_csr_hazard || ex_stage_block_mdu_wait;
    wire id_stall_now = id_stage_block || (ds_to_es_valid && !es_allowin);
    wire ex_stall_now = ex_stage_block || (es_to_ms_valid && !ms_allowin);
    wire frontend_wait_now = if_stall || (ibus_req_valid && !ibus_req_ready) ||
        (ibus_resp_ready && !ibus_resp_valid);
    wire icache_fetch_wait_now = ibus_req_valid && !ibus_req_ready;
    wire if_id_empty_now = !fs_to_ds_valid && !ds_to_es_valid && !es_valid &&
        !ms_valid && !ws_valid;
    wire branch_recovery_now = redirect_flush_valid || ex_stage_block_redirect_wait;
    wire icache_pipe_resp_block_now = icache_pipe_resp_valid && !icache_pipe_resp_ready;
    wire stage_latency_now = !ws_valid &&
        (fs_to_ds_valid || ds_to_es_valid || es_valid || es_to_ms_valid ||
         ms_valid || ms_to_ws_valid || if_stat_fs_valid);
    wire hazard_event_now = load_use_now || raw_hazard_now || csr_special_now || mem_lsu_wait_now;
    wire hazard_rs1_now =
        ds_stat_rs1_match_es || ds_stat_rs1_match_ms ||
        ds_stat_rs1_match_hidden || ds_stat_rs1_match_ws;
    wire hazard_rs2_now =
        ds_stat_rs2_match_es || ds_stat_rs2_match_ms ||
        ds_stat_rs2_match_hidden || ds_stat_rs2_match_ws;
    wire hazard_both_now = hazard_rs1_now && hazard_rs2_now;
    wire hazard_only_rs1_now = hazard_rs1_now && !hazard_rs2_now;
    wire hazard_only_rs2_now = !hazard_rs1_now && hazard_rs2_now;
    wire match_ex_now = ds_stat_rs1_match_es || ds_stat_rs2_match_es;
    wire match_ms_now = !match_ex_now && (ds_stat_rs1_match_ms || ds_stat_rs2_match_ms);
    wire match_hidden_now = !match_ex_now && !match_ms_now &&
        (ds_stat_rs1_match_hidden || ds_stat_rs2_match_hidden);
    wire match_wb_now = !match_ex_now && !match_ms_now && !match_hidden_now &&
        (ds_stat_rs1_match_ws || ds_stat_rs2_match_ws);
    wire ex_is_load_now = (es_datatoreg == 2'b01);
    wire ex_is_csr_now = (es_datatoreg == 2'b10) || (es_csr_wen != 2'b00);
    wire ex_is_store_or_mem_order_now = (es_mem_wr != 2'b00) || es_atomic_en;
    wire ex_is_alu_now = es_result_bypassable && !ex_is_load_now &&
        !ex_is_csr_now && !ex_is_store_or_mem_order_now && !es_stat_is_mdu;
    wire ms_is_load_now = (ms_datatoreg == 2'b01);
    wire ms_is_csr_now = (ms_datatoreg == 2'b10) || (ms_csr_wen != 2'b00);
    wire ms_is_alu_now = (ms_datatoreg == 2'b00) && (ms_csr_wen == 2'b00);
    wire hidden_is_load_now = (hidden_mreq_datatoreg == 2'b01);
    wire hidden_is_csr_now = (hidden_mreq_datatoreg == 2'b10) || (hidden_mreq_csr_wen != 2'b00);
    wire hidden_is_mem_order_now = (hidden_mreq_mem_wr != 2'b00);
    wire ws_is_load_now = (ws_stat_datatoreg == 2'b01);
    wire ws_is_csr_now = (ws_stat_datatoreg == 2'b10) || (ws_csr_wen != 2'b00);
    wire ws_is_alu_now = (ws_stat_datatoreg == 2'b00) && (ws_csr_wen == 2'b00);
    wire ms_load_ready_now = ms_is_load_now && ms_fwd_valid && !ms_stage_block;
    wire load_bypass_dep_now = (ds_stat_rs1_match_ms || ds_stat_rs2_match_ms);
    wire load_bypass_release_now = load_bypass_dep_now && ms_stat_load_visible &&
        ms_stat_load_aligned && ms_stat_load_data_ready &&
        ms_stat_load_signext_data_ready && !ms_stat_load_fault &&
        !ms_stat_load_uncached && !ms_stat_load_split_or_misaligned &&
        !ms_stat_load_atomic && !ms_stat_load_killed &&
        !ms_stat_load_store_block && !ms_stat_load_lsu_pending;
    wire load_bypass_forward_rs1_now = es_stat_rs1_load_fwd;
    wire load_bypass_forward_rs2_now = es_stat_rs2_load_fwd;
    wire load_bypass_forward_any_now = load_bypass_forward_rs1_now || load_bypass_forward_rs2_now;
    wire ms_load_miss_now = ms_is_load_now &&
        (ms_stage_block_resp_load || ms_stage_block_req_load || ms_stage_block_load);
    wire ms_lsu_busy_now = ms_stage_block_load || ms_stage_block_req_load ||
        ms_stage_block_resp_load || dbus_req_wait_now || dbus_resp_wait_now;
    wire mdu_op_mul = (es_stat_mdu_op == 3'd0);
    wire mdu_op_mulh = (es_stat_mdu_op == 3'd1) ||
        (es_stat_mdu_op == 3'd2) || (es_stat_mdu_op == 3'd3);
    wire mdu_op_div = (es_stat_mdu_op == 3'd4) ||
        (es_stat_mdu_op == 3'd5);
    wire mdu_op_rem = (es_stat_mdu_op == 3'd6) ||
        (es_stat_mdu_op == 3'd7);
    wire loadhit_mem_to_ex_now = ms_stat_load_visible &&
        ms_stat_load_aligned && ms_stat_load_result_ready &&
        ms_stat_load_signext_ready && !ms_stat_load_fault &&
        !ms_stat_uncached_wait;
    wire loadhit_wb_only_now = match_hidden_now || match_wb_now ||
        (ms_stat_load_visible && !ms_stat_load_result_ready);
    wire loadhit_not_safe_now = ms_stat_load_fault || ms_stat_uncached_wait ||
        (ms_stat_load_visible && !ms_stat_load_aligned);
    wire loadhit_consumer_rs1_now = ds_stat_rs1_match_es ||
        ds_stat_rs1_match_ms || ds_stat_rs1_match_hidden ||
        ds_stat_rs1_match_ws;
    wire loadhit_consumer_rs2_now = ds_stat_rs2_match_es ||
        ds_stat_rs2_match_ms || ds_stat_rs2_match_hidden ||
        ds_stat_rs2_match_ws;
    wire loadhit_safe_mem_to_ex_now = ms_stat_load_visible &&
        ms_stat_load_aligned && ms_stat_load_data_ready &&
        ms_stat_load_signext_data_ready && !ms_stat_load_fault &&
        !ms_stat_load_uncached && !ms_stat_load_split_or_misaligned &&
        !ms_stat_load_atomic && !ms_stat_load_killed &&
        !ms_stat_load_lsu_pending;
    wire loadhit_safe_memwb_to_ex_now = ms_stat_load_visible &&
        !loadhit_safe_mem_to_ex_now && ms_stat_load_result_ready &&
        ms_stat_load_signext_ready && !ms_stat_load_fault &&
        !ms_stat_load_uncached && !ms_stat_load_split_or_misaligned &&
        !ms_stat_load_atomic && !ms_stat_load_killed;
    wire loadhit_safe_wb_to_ex_now = ms_stat_load_visible &&
        !loadhit_safe_mem_to_ex_now && !loadhit_safe_memwb_to_ex_now &&
        (ms_stat_load_to_wb_valid || match_wb_now) &&
        !ms_stat_load_fault && !ms_stat_load_uncached &&
        !ms_stat_load_split_or_misaligned && !ms_stat_load_atomic &&
        !ms_stat_load_killed;
    wire loadhit_blocked_not_signext_now = ms_stat_load_visible &&
        !ms_stat_load_signext_data_ready && !ms_stat_load_fault &&
        !ms_stat_load_uncached && !ms_stat_load_split_or_misaligned &&
        !ms_stat_load_killed;
    wire loadhit_blocked_lsu_pending_now = ms_stat_load_lsu_pending ||
        ms_stat_load_store_block || ms_stat_store_resp_wait ||
        ms_stat_single_outstanding_wait || ms_stage_block_resp_load ||
        ms_stage_block_req_load;
    wire mem_backend_wait_now = mem_lsu_wait_now || dcache_wait_now ||
        store_wait_now || ms_stat_single_outstanding_wait ||
        ms_stat_uncached_wait || ms_stat_writeback_wait;
    wire mem_v2_single_now = ms_stat_mreq_blocked_by_resp ||
        ms_stat_single_outstanding_wait;
    wire mem_v2_store_blocking_load_now =
        ms_stat_mreq_is_load &&
        (ms_stat_mresp_is_store || ms_stage_block_store ||
         ms_stage_block_req_store || ms_stage_block_resp_store);
    wire mem_v2_load_resp_wait_now =
        ms_stage_block_resp_load || (dbus_resp_wait_now && ms_stat_mresp_is_load);
    wire mem_v2_store_resp_wait_now =
        ms_stage_block_resp_store || (dbus_resp_wait_now && ms_stat_mresp_is_store);
    wire mem_v2_store_miss_like_now =
        ms_stage_block_req_store || ms_stage_block_resp_store ||
        dcache_miss_delta || dcache_writeback_delta;
    wire mem_v2_store_hit_like_now =
        ms_stat_store_visible && !mem_v2_store_miss_like_now &&
        !ms_stat_store_uncached && !ms_stat_store_split_or_misaligned &&
        !ms_stat_store_fault;
    wire mem_v2_store_event_now = ms_stat_store_visible ||
        ms_stat_store_req_fire || ms_stat_store_resp_fire;
    wire storebuf_not_safe_now = ms_stat_store_uncached ||
        ms_stat_store_fault || ms_stat_store_split_or_misaligned ||
        ms_stat_store_atomic || ms_stat_store_killed ||
        fencei_start || vm_flush_start || fencei_maint_active;
    wire storebuf_safe_now = ms_stat_store_buffer_safe &&
        !fencei_start && !vm_flush_start && !fencei_maint_active;
    wire dcache_proto_resp_valid_wait_ready_now =
        ms_stat_mresp_resp_valid && !ws_allowin;
    wire dcache_proto_overhead_now =
        ms_stat_mresp_resp_valid && ms_stat_mresp_valid && !ms_stat_mresp_resp_fire;
    wire dcache_proto_hit_still_now = dcache_proto_track_hit &&
        !dcache_miss_delta && !dcache_writeback_delta && !dcache_uncached_delta;
    wire load_resp_wait_path_now =
        ms_stage_block_resp_load || (dbus_resp_wait_now && ms_stat_mresp_is_load);
    wire load_sbuf_drain_now = store_buffer_drain_wait_delta &&
        (ms_stage_block_load || ms_stage_block_req_load ||
         ms_stage_block_resp_load || ms_stat_mreq_is_load);
    wire load_sbuf_conflict_now =
        (store_buffer_load_stall_conflict_count !=
         prev_store_buffer_load_stall_conflict_count);
    wire load_dcache_miss_like_now = dcache_miss_delta || ms_stage_block_req_load;
    wire load_dcache_hit_like_now =
        ms_stat_load_resp_valid || ms_stat_load_data_ready ||
        (ms_stage_block_resp_load && !load_dcache_miss_like_now &&
         !dcache_uncached_delta);
    wire load_resp_uncached_now = ms_stat_load_uncached ||
        ms_stat_uncached_wait || dcache_uncached_delta;
    wire load_resp_lsu_busy_now = ms_stat_single_outstanding_wait ||
        ms_stat_mreq_blocked_by_resp || ms_stat_load_lsu_pending;
    wire load_resp_mem_stage_block_now =
        ms_stage_block_load || ms_stage_block_resp_load || ms_stage_block_req_load;
    wire load_resp_wb_block_now = wb_block_now ||
        (ms_to_ws_valid && !ws_allowin);
    wire load_use_path_event_now = load_use_now;
    wire load_candidate_matches_load_now =
        ((match_ex_now && ex_is_load_now) ||
         (match_ms_now && ms_is_load_now) ||
         (match_hidden_now && hidden_is_load_now) ||
         (match_wb_now && ws_is_load_now));
    wire lbp2_safe_dcache_now =
        ms_stat_load_resp_valid && ms_stat_load_data_ready &&
        ms_stat_load_signext_data_ready && ms_stat_load_aligned &&
        !ms_stat_load_fault && !ms_stat_load_uncached &&
        !ms_stat_load_split_or_misaligned && !ms_stat_load_atomic &&
        !ms_stat_load_killed && !trap_flush_now && !redirect_flush_valid;
    wire lbp2_safe_mem_stage_now =
        !lbp2_safe_dcache_now && ms_stat_load_visible &&
        ms_stat_load_result_ready && ms_stat_load_signext_ready &&
        ms_stat_load_aligned && !ms_stat_load_fault &&
        !ms_stat_load_uncached && !ms_stat_load_split_or_misaligned &&
        !ms_stat_load_atomic && !ms_stat_load_killed &&
        !trap_flush_now && !redirect_flush_valid;
    wire lbp2_safe_memwb_now =
        !lbp2_safe_dcache_now && !lbp2_safe_mem_stage_now &&
        ms_stat_load_to_wb_valid && !ms_stat_load_fault &&
        !ms_stat_load_uncached && !ms_stat_load_split_or_misaligned &&
        !ms_stat_load_atomic && !ms_stat_load_killed;
    wire lbp2_safe_wb_now =
        !lbp2_safe_dcache_now && !lbp2_safe_mem_stage_now &&
        !lbp2_safe_memwb_now && match_wb_now && ws_is_load_now;

    wire ifid_full_wait = fs_to_ds_valid && !ds_allowin;
    wire ifid_backpressure = fs_to_ds_valid && !ds_allowin;
    wire id_backpressure = ds_to_es_valid && !es_allowin;
    wire ex_backpressure = es_to_ms_valid && !ms_allowin;
    wire mem_backpressure = ms_to_ws_valid && !ws_allowin;
    wire icache_miss_delta = (icache_miss_wait_cycle != prev_icache_miss_wait_cycle) ||
        (if_pipe_icache_miss_count != prev_if_pipe_icache_miss_count);
    wire icache_req_delta = (icache_req_wait_cycle != prev_icache_req_wait_cycle);
    wire dcache_miss_delta = (dcache_miss_wait_cycle != prev_dcache_miss_wait_cycle);
    wire dcache_uncached_delta = (dcache_uncached_access != prev_dcache_uncached_access);
    wire dcache_writeback_delta = (dcache_writeback_cycle != prev_dcache_writeback_cycle);
    wire store_buffer_drain_wait_delta =
        (store_buffer_drain_wait_count != prev_store_buffer_drain_wait_count);
    wire epoch_recovery_now = redirect_clear_valid || stop_clear_valid ||
        if_stat_resp_drop || if_pipe_stat_resp_stale ||
        (if_pipe_epoch_drop_count != prev_if_pipe_epoch_drop_count);
    wire ptw_wait_now = if_pipe_stat_ptw_busy ||
        (if_pipe_stat_lower_req_valid && !if_pipe_stat_lower_req_ready) ||
        (if_pipe_stat_lower_resp_ready && !if_pipe_stat_lower_resp_valid);
    wire resp_fifo_full_delta =
        (icache_pipe_resp_fifo_full_cycle != prev_icache_pipe_resp_fifo_full_cycle);
    wire ifid_queue_full_now = !if_stat_fetch_room || (if_stat_queue_count == 2'd2);
    wire id_not_ready_now = fs_to_ds_valid && !ds_allowin;
    wire ex_not_ready_now = (ds_to_es_valid && !es_allowin) ||
        (es_to_ms_valid && !ms_allowin) ||
        (ms_to_ws_valid && !ws_allowin);
    wire if_pipe_req_not_ready_now = if_pipe_stat_req_valid && !if_pipe_stat_req_ready;
    wire if_pipe_no_resp_now =
        (if_pipe_stat_outstanding && !if_pipe_stat_resp_current) ||
        (if_stat_waiting_resp && !if_stat_resp_fire) ||
        (ibus_resp_ready && !ibus_resp_valid);
    wire frontend_self_wait_now =
        !fs_to_ds_valid && !if_stat_fs_valid && !if_stat_resp_accept &&
        !if_pipe_stat_resp_current && !id_not_ready_now && !ex_not_ready_now;
    wire frontend_backpressure_like_now =
        if_stat_resp_accept || if_stat_bypass_direct || if_stat_fs_valid ||
        !ds_allowin || !es_allowin || !ms_allowin || !ws_allowin ||
        if_stat_req_fire || if_stat_resp_fire || if_stall;
    wire resp_wait_commit_now = fencei_start || vm_flush_start || fencei_maint_active;
    wire if_stage_not_accepting_resp_now =
        if_pipe_stat_resp_current && !ibus_resp_ready;
    wire ifq_push_block_now =
        icache_pipe_resp_valid && !icache_pipe_resp_ready && if_stat_queue_full;
    wire ifq_push_attempt_now = if_stat_resp_enq || ifq_push_block_now;
    wire backend_stall_now = ex_not_ready_now || wb_block_now;
    wire redirect_or_flush_now = redirect_flush_valid || redirect_clear_valid ||
        trap_redirect_valid || stop_clear_valid;

    task print_cpi_line;
        input [255:0] prefix;
        input [255:0] name;
        input [63:0] cycles;
        reg [63:0] x100;
        begin
            if (commit_count == 64'd0) begin
                $display("[%0s] %0s=N/A", prefix, name);
            end else begin
                x100 = (cycles * 64'd100) / commit_count;
                $display("[%0s] %0s=%0d.%02d (%0d/%0d)",
                    prefix, name, x100 / 64'd100, x100 % 64'd100,
                    cycles, commit_count);
            end
        end
    endtask

    task count_loadhit_timing_safety;
        begin
            loadhit_timing_total <= loadhit_timing_total + 64'd1;
            if (ms_stat_load_data_ready) begin
                loadhit_timing_data_valid_cycle <=
                    loadhit_timing_data_valid_cycle + 64'd1;
            end
            if (ms_stat_load_signext_data_ready) begin
                loadhit_timing_signext_ready_cycle <=
                    loadhit_timing_signext_ready_cycle + 64'd1;
            end
            if (ms_stat_load_to_wb_valid || match_wb_now) begin
                loadhit_timing_wb_ready_cycle <=
                    loadhit_timing_wb_ready_cycle + 64'd1;
            end
            if (match_ex_now) begin
                loadhit_timing_consumer_wait_ex <=
                    loadhit_timing_consumer_wait_ex + 64'd1;
            end else if (match_ms_now || match_hidden_now) begin
                loadhit_timing_consumer_wait_mem <=
                    loadhit_timing_consumer_wait_mem + 64'd1;
            end else if (match_wb_now) begin
                loadhit_timing_consumer_wait_wb <=
                    loadhit_timing_consumer_wait_wb + 64'd1;
            end

            if (loadhit_safe_mem_to_ex_now) begin
                load_forward_safe_mem_to_ex <=
                    load_forward_safe_mem_to_ex + 64'd1;
            end else if (loadhit_safe_memwb_to_ex_now) begin
                load_forward_safe_memwb_to_ex <=
                    load_forward_safe_memwb_to_ex + 64'd1;
            end else if (loadhit_safe_wb_to_ex_now) begin
                load_forward_safe_wb_to_ex <=
                    load_forward_safe_wb_to_ex + 64'd1;
            end else if (ms_stat_load_uncached || ms_stat_uncached_wait) begin
                load_forward_blocked_uncached <=
                    load_forward_blocked_uncached + 64'd1;
            end else if (ms_stat_load_fault) begin
                load_forward_blocked_fault <=
                    load_forward_blocked_fault + 64'd1;
            end else if (ms_stat_load_split_or_misaligned) begin
                load_forward_blocked_misaligned <=
                    load_forward_blocked_misaligned + 64'd1;
            end else if (ms_stat_load_killed || trap_flush_now ||
                    redirect_flush_valid) begin
                load_forward_blocked_kill <=
                    load_forward_blocked_kill + 64'd1;
            end else if (loadhit_blocked_not_signext_now) begin
                load_forward_blocked_not_signext <=
                    load_forward_blocked_not_signext + 64'd1;
            end else if (loadhit_blocked_lsu_pending_now ||
                    !ms_stat_load_visible || ms_stat_hidden_load) begin
                load_forward_blocked_lsu_pending <=
                    load_forward_blocked_lsu_pending + 64'd1;
            end else begin
                load_forward_unknown <= load_forward_unknown + 64'd1;
            end
        end
    endtask

    task count_load_pending_not_bypassable;
        begin
            fwd_load_miss_not_bypassable <= fwd_load_miss_not_bypassable + 64'd1;
            if (dcache_miss_delta && (ms_stage_block_load ||
                    ms_stage_block_req_load || ms_stage_block_resp_load)) begin
                load_pending_true_dcache_load_miss_wait <=
                    load_pending_true_dcache_load_miss_wait + 64'd1;
            end else if (dcache_uncached_delta) begin
                load_pending_blocked_by_uncached <=
                    load_pending_blocked_by_uncached + 64'd1;
            end else if (ms_stage_block_store || ms_stage_block_req_store ||
                    ms_stage_block_resp_store) begin
                load_pending_blocked_by_store_miss <=
                    load_pending_blocked_by_store_miss + 64'd1;
            end else if (ms_stage_block_resp_load || dbus_resp_wait_now) begin
                load_pending_load_wait_mem_resp <=
                    load_pending_load_wait_mem_resp + 64'd1;
            end else if (ms_stage_block_resp_phase || ms_stage_block_req_phase ||
                    ms_stage_block) begin
                load_pending_lsu_single_outstanding_wait <=
                    load_pending_lsu_single_outstanding_wait + 64'd1;
            end else if ((match_ex_now && ex_is_load_now) ||
                    (match_ms_now && ms_is_load_now)) begin
                load_pending_load_hit_no_forward_wait <=
                    load_pending_load_hit_no_forward_wait + 64'd1;
                loadhit_total <= loadhit_total + 64'd1;
                count_loadhit_timing_safety();
                if (ms_stat_load_visible && ms_stat_load_aligned) begin
                    loadhit_aligned_hit <= loadhit_aligned_hit + 64'd1;
                end else if (ms_stat_load_visible && !ms_stat_load_aligned) begin
                    loadhit_unaligned <= loadhit_unaligned + 64'd1;
                end
                if (ms_stat_load_visible) loadhit_dtlb_hit <= loadhit_dtlb_hit + 64'd1;
                if (ms_stat_load_result_ready) loadhit_dcache_hit <= loadhit_dcache_hit + 64'd1;
                if (ms_stat_uncached_wait) loadhit_uncached <= loadhit_uncached + 64'd1;
                if (ms_stat_load_fault) loadhit_fault <= loadhit_fault + 64'd1;
                if (ms_stat_load_signext_ready) loadhit_signext_ready <= loadhit_signext_ready + 64'd1;
                if (loadhit_consumer_rs1_now) loadhit_consumer_rs1 <= loadhit_consumer_rs1 + 64'd1;
                if (loadhit_consumer_rs2_now) loadhit_consumer_rs2 <= loadhit_consumer_rs2 + 64'd1;
                if (trap_flush_now || redirect_flush_valid) begin
                    loadhit_producer_killed <= loadhit_producer_killed + 64'd1;
                end
                if (ms_stat_load_result_ready) loadhit_same_cycle_possible <= loadhit_same_cycle_possible + 64'd1;
                if (loadhit_mem_to_ex_now) begin
                    loadhit_mem_to_ex_possible <= loadhit_mem_to_ex_possible + 64'd1;
                end else if (loadhit_wb_only_now) begin
                    loadhit_wb_only <= loadhit_wb_only + 64'd1;
                end else if (loadhit_not_safe_now || !ms_stat_load_visible) begin
                    loadhit_not_safe <= loadhit_not_safe + 64'd1;
                end else begin
                    loadhit_unknown <= loadhit_unknown + 64'd1;
                end
            end else if ((match_hidden_now && hidden_is_load_now) ||
                    (match_wb_now && ws_is_load_now)) begin
                load_pending_load_wait_wb <=
                    load_pending_load_wait_wb + 64'd1;
            end else begin
                load_pending_other <= load_pending_other + 64'd1;
            end
        end
    endtask

    task print_stats;
        reg [63:0] bubble_sum;
        reg [63:0] frontend_sum;
        reg [63:0] frontend_mismatch;
        reg [63:0] bubble_expected;
        reg [63:0] mismatch;
        reg [63:0] branch_perfect_cycles;
        reg [63:0] ifq_block_sum;
        reg [63:0] ifq_block_mismatch;
        reg [63:0] hazard_total_sum;
        reg [63:0] hazard_total_expected;
        reg [63:0] hazard_total_mismatch;
        reg [63:0] hazard_operand_sum;
        reg [63:0] hazard_operand_mismatch;
        reg [63:0] load_use_sum;
        reg [63:0] load_use_mismatch;
        reg [63:0] raw_sum;
        reg [63:0] raw_mismatch;
        reg [63:0] load_pending_sum;
        reg [63:0] load_pending_mismatch;
        reg [63:0] loadhit_exclusive_sum;
        reg [63:0] loadhit_mismatch;
        reg [63:0] load_forward_sum;
        reg [63:0] load_forward_mismatch;
        reg [63:0] mem_backend_sum;
        reg [63:0] mem_backend_mismatch;
        reg [63:0] mem_backend_total;
        reg [63:0] mdu_accounted;
        reg [63:0] mdu_mismatch;
        reg [63:0] mul_avg_latency;
        reg [63:0] div_avg_latency;
        reg [63:0] fast_mul_kill_display;
        reg [63:0] fast_mul_mismatch;
        reg [63:0] mem_v2_load_resp_sum;
        reg [63:0] mem_v2_load_resp_mismatch;
        reg [63:0] mem_v2_store_resp_sum;
        reg [63:0] mem_v2_store_resp_mismatch;
        reg [63:0] mem_v2_single_sum;
        reg [63:0] mem_v2_single_mismatch;
        reg [63:0] storebuf_sum;
        reg [63:0] storebuf_mismatch;
        reg [63:0] lsu_load_bypass_sum;
        reg [63:0] lsu_load_bypass_mismatch;
        reg [63:0] late_bypass_sum;
        reg [63:0] late_bypass_mismatch;
        reg [63:0] dcache_proto_load_avg;
        reg [63:0] dcache_proto_store_avg;
        reg [63:0] lrp_wait_sum;
        reg [63:0] lrp_wait_mismatch;
        reg [63:0] dclh_avg;
        reg [63:0] dclh_latency_bucket_sum;
        reg [63:0] dclh_latency_bucket_mismatch;
        reg [63:0] dclh_wait_sum;
        reg [63:0] dclh_wait_expected;
        reg [63:0] dclh_wait_mismatch;
        reg [63:0] dhitopt_sum;
        reg [63:0] dhitopt_mismatch;
        reg [63:0] loaduse_path_sum;
        reg [63:0] loaduse_path_mismatch;
        reg [63:0] lbp2_sum;
        reg [63:0] lbp2_mismatch;
        reg [63:0] lsu_so2_sum;
        reg [63:0] lsu_so2_mismatch;
        reg [63:0] sbuf_store_resp_cpu_visible;
        reg [63:0] sbuf_store_resp_uncached;
        reg [63:0] sbuf_store_resp_fence;
        reg [63:0] sbuf_store_resp_full;
        reg [63:0] sbuf_store_resp_other;
        reg [63:0] sbuf_store_resp_sum;
        reg [63:0] sbuf_store_resp_mismatch;
        reg [63:0] sbuf_drain_impact_sum;
        reg [63:0] sbuf_drain_impact_mismatch;
        reg [63:0] exmem_skid_sum;
        reg [63:0] exmem_skid_mismatch;
        reg [63:0] mem_issue_after_skid_remaining;
        reg [63:0] mem_issue_after_skid_mismatch;
        reg [63:0] exmem_skid_eff_enqueue_sum;
        reg [63:0] exmem_skid_eff_no_gain_sum;
        reg [63:0] exmem_skid_eff_mismatch_enqueue;
        reg [63:0] exmem_skid_eff_mismatch_nogain;
        reg [63:0] exmem_skid_eff_mismatch;
        begin
            bubble_sum =
                bucket_trap_flush + bucket_wb_block + bucket_mem_lsu_wait +
                bucket_dcache_wait + bucket_store_wait + bucket_load_use +
                bucket_raw_hazard + bucket_csr_special + bucket_id_stall +
                bucket_ex_stall + bucket_if_id_empty + bucket_frontend_wait +
                bucket_icache_fetch_wait + bucket_branch_recovery +
                bucket_resp_block + bucket_stage_latency + bucket_unknown;
            bubble_expected = cycle_count - commit_count;
            mismatch = (bubble_sum >= bubble_expected) ?
                (bubble_sum - bubble_expected) : (bubble_expected - bubble_sum);
            frontend_sum =
                frontend_self_wait + frontend_backpressure_wait +
                frontend_ifid_queue_full_wait + frontend_id_not_ready_backpressure +
                frontend_ex_not_ready_backpressure + frontend_if_pipe_no_resp_wait +
                frontend_if_pipe_req_not_ready_wait + frontend_icache_miss_refill_wait +
                frontend_icache_req_wait + frontend_epoch_drop_recovery_wait +
                frontend_ptw_wait + frontend_unknown;
            frontend_mismatch = (frontend_sum >= bucket_frontend_wait) ?
                (frontend_sum - bucket_frontend_wait) : (bucket_frontend_wait - frontend_sum);
            ifq_block_sum =
                ifq_block_full_no_pop + ifq_block_full_with_pop_same_cycle +
                ifq_block_full_id_ready + ifq_block_full_id_not_ready +
                ifq_block_backend_stall + ifq_block_redirect +
                ifq_block_epoch_drop + ifq_block_load_use +
                ifq_block_raw_hazard + ifq_block_mem_lsu +
                ifq_block_csr_special + ifq_block_unknown;
            ifq_block_mismatch = (ifq_block_sum >= ifq_push_block) ?
                (ifq_block_sum - ifq_push_block) : (ifq_push_block - ifq_block_sum);
            hazard_total_sum = hazard_load_use_total + hazard_raw_total +
                hazard_csr_total + hazard_mem_lsu_total;
            hazard_total_expected = hazard_total_sum;
            hazard_total_mismatch = 64'd0;
            hazard_operand_sum = hazard_rs1 + hazard_rs2 + hazard_both +
                hazard_operand_unknown;
            hazard_operand_mismatch = (hazard_operand_sum >= (hazard_load_use_total + hazard_raw_total)) ?
                (hazard_operand_sum - (hazard_load_use_total + hazard_raw_total)) :
                ((hazard_load_use_total + hazard_raw_total) - hazard_operand_sum);
            load_use_sum = load_use_load_hit + load_use_load_miss +
                load_use_lsu_busy + load_use_wait_mem + load_use_wait_wb +
                load_use_unknown;
            load_use_mismatch = (load_use_sum >= hazard_load_use_total) ?
                (load_use_sum - hazard_load_use_total) : (hazard_load_use_total - load_use_sum);
            raw_sum = raw_alu_ex + raw_alu_mem + raw_alu_wb + raw_load_mem +
                raw_load_wb + raw_csr + raw_muldiv + raw_hidden + raw_unknown;
            raw_mismatch = (raw_sum >= hazard_raw_total) ?
                (raw_sum - hazard_raw_total) : (hazard_raw_total - raw_sum);
            load_pending_sum = load_pending_true_dcache_load_miss_wait +
                load_pending_load_hit_no_forward_wait +
                load_pending_load_wait_mem_resp + load_pending_load_wait_wb +
                load_pending_blocked_by_store_miss +
                load_pending_blocked_by_uncached +
                load_pending_lsu_single_outstanding_wait + load_pending_other;
            load_pending_mismatch = (load_pending_sum >= fwd_load_miss_not_bypassable) ?
                (load_pending_sum - fwd_load_miss_not_bypassable) :
                (fwd_load_miss_not_bypassable - load_pending_sum);
            loadhit_exclusive_sum = loadhit_mem_to_ex_possible + loadhit_wb_only +
                loadhit_not_safe + loadhit_unknown;
            loadhit_mismatch = (loadhit_exclusive_sum >= loadhit_total) ?
                (loadhit_exclusive_sum - loadhit_total) :
                (loadhit_total - loadhit_exclusive_sum);
            load_forward_sum =
                load_forward_safe_mem_to_ex + load_forward_safe_memwb_to_ex +
                load_forward_safe_wb_to_ex + load_forward_blocked_uncached +
                load_forward_blocked_fault + load_forward_blocked_misaligned +
                load_forward_blocked_kill + load_forward_blocked_not_signext +
                load_forward_blocked_lsu_pending + load_forward_unknown;
            load_forward_mismatch = (load_forward_sum >= loadhit_timing_total) ?
                (load_forward_sum - loadhit_timing_total) :
                (loadhit_timing_total - load_forward_sum);
            mem_backend_sum =
                mem_backend_load_response_wait + mem_backend_store_response_wait +
                mem_backend_store_miss_wait + mem_backend_store_write_resp_wait +
                mem_backend_dcache_miss_wait + mem_backend_dcache_req_wait +
                mem_backend_single_outstanding_wait + mem_backend_uncached_wait +
                mem_backend_writeback_wait + mem_backend_other;
            mem_backend_total = mem_backend_sum;
            mem_backend_mismatch = 64'd0;
            mdu_accounted = mdu_mul_wait_cycles + mdu_mulh_wait_cycles +
                mdu_div_wait_cycles + mdu_rem_wait_cycles + mdu_unknown;
            mdu_mismatch = (mdu_accounted >= mdu_busy_cycles) ?
                (mdu_accounted - mdu_busy_cycles) :
                (mdu_busy_cycles - mdu_accounted);
            mul_avg_latency = (mdu_mul_total == 64'd0) ? 64'd0 :
                (mdu_mul_latency_sum / mdu_mul_total);
            div_avg_latency = (mdu_div_total == 64'd0) ? 64'd0 :
                (mdu_div_latency_sum / mdu_div_total);
            fast_mul_kill_display =
                (fast_mul_issue >= (fast_mul_resp + fast_mul_flush_drop)) ?
                (fast_mul_issue - fast_mul_resp - fast_mul_flush_drop) :
                fast_mul_kill;
            fast_mul_mismatch =
                (fast_mul_issue >= (fast_mul_resp + fast_mul_kill_display + fast_mul_flush_drop)) ?
                (fast_mul_issue - fast_mul_resp - fast_mul_kill_display - fast_mul_flush_drop) :
                (fast_mul_resp + fast_mul_kill_display + fast_mul_flush_drop - fast_mul_issue);
            mem_v2_load_resp_sum =
                mem_v2_load_resp_wait_dcache_hit +
                mem_v2_load_resp_wait_dcache_miss +
                mem_v2_load_resp_wait_blocked_by_store +
                mem_v2_load_resp_wait_blocked_by_single +
                mem_v2_load_resp_wait_uncached +
                mem_v2_load_resp_wait_other;
            mem_v2_load_resp_mismatch = (mem_v2_load_resp_sum >= mem_v2_load_resp_wait) ?
                (mem_v2_load_resp_sum - mem_v2_load_resp_wait) :
                (mem_v2_load_resp_wait - mem_v2_load_resp_sum);
            mem_v2_store_resp_sum =
                mem_v2_store_hit_resp_wait + mem_v2_store_miss_resp_wait +
                mem_v2_store_write_resp_wait + mem_v2_store_refill_wait +
                mem_v2_store_uncached_wait + mem_v2_store_other;
            mem_v2_store_resp_mismatch = (mem_v2_store_resp_sum >= mem_v2_store_resp_wait) ?
                (mem_v2_store_resp_sum - mem_v2_store_resp_wait) :
                (mem_v2_store_resp_wait - mem_v2_store_resp_sum);
            mem_v2_single_sum =
                mem_v2_single_load_blocked_by_load +
                mem_v2_single_load_blocked_by_store +
                mem_v2_single_store_blocked_by_load +
                mem_v2_single_store_blocked_by_store +
                mem_v2_single_uncached + mem_v2_single_other;
            mem_v2_single_mismatch = (mem_v2_single_sum >= mem_v2_single_outstanding_wait) ?
                (mem_v2_single_sum - mem_v2_single_outstanding_wait) :
                (mem_v2_single_outstanding_wait - mem_v2_single_sum);
            storebuf_sum = storebuf_safe_candidate + storebuf_not_safe;
            storebuf_mismatch = (storebuf_sum >= storebuf_store_total) ?
                (storebuf_sum - storebuf_store_total) :
                (storebuf_store_total - storebuf_sum);
            lsu_load_bypass_sum = lsu_load_bypass_release_id_stall +
                lsu_load_bypass_blocked_not_load +
                lsu_load_bypass_blocked_rd_x0 +
                lsu_load_bypass_blocked_resp_not_ready +
                lsu_load_bypass_blocked_signext_not_ready +
                lsu_load_bypass_blocked_fault +
                lsu_load_bypass_blocked_kill +
                lsu_load_bypass_blocked_uncached +
                lsu_load_bypass_blocked_miss +
                lsu_load_bypass_blocked_misaligned +
                lsu_load_bypass_blocked_atomic +
                lsu_load_bypass_blocked_store_buffer;
            lsu_load_bypass_mismatch = (lsu_load_bypass_sum >= lsu_load_bypass_candidate) ?
                (lsu_load_bypass_sum - lsu_load_bypass_candidate) :
                (lsu_load_bypass_candidate - lsu_load_bypass_sum);
            late_bypass_sum = late_bypass_safe + late_bypass_unknown;
            late_bypass_mismatch = (late_bypass_sum >= late_bypass_total_load_dep) ?
                (late_bypass_sum - late_bypass_total_load_dep) :
                (late_bypass_total_load_dep - late_bypass_sum);
            dcache_proto_load_avg = (dcache_proto_load_hit_latency_count == 64'd0) ? 64'd0 :
                (dcache_proto_load_hit_latency_sum / dcache_proto_load_hit_latency_count);
            dcache_proto_store_avg = (dcache_proto_store_hit_latency_count == 64'd0) ? 64'd0 :
                (dcache_proto_store_hit_latency_sum / dcache_proto_store_hit_latency_count);
            lrp_wait_sum =
                lrp_wait_dcache_hit + lrp_wait_dcache_miss +
                lrp_wait_uncached + lrp_wait_sbuf_drain +
                lrp_wait_sbuf_conflict + lrp_wait_lsu_busy +
                lrp_wait_mem_stage_block + lrp_wait_wb_block +
                lrp_wait_other;
            lrp_wait_mismatch = (lrp_wait_sum >= lrp_wait_total) ?
                (lrp_wait_sum - lrp_wait_total) :
                (lrp_wait_total - lrp_wait_sum);
            dclh_avg = (dclh_total == 64'd0) ? 64'd0 :
                (dclh_latency_sum / dclh_total);
            dclh_latency_bucket_sum =
                dclh_latency_1 + dclh_latency_2 +
                dclh_latency_3 + dclh_latency_gt3;
            dclh_latency_bucket_mismatch =
                (dclh_latency_bucket_sum >= dclh_total) ?
                (dclh_latency_bucket_sum - dclh_total) :
                (dclh_total - dclh_latency_bucket_sum);
            dclh_wait_expected =
                (dclh_latency_sum >= dclh_total) ?
                (dclh_latency_sum - dclh_total) : 64'd0;
            dclh_wait_sum =
                dclh_tag_lookup_wait + dclh_data_array_wait +
                dclh_data_align_wait + dclh_signext_wait +
                dclh_response_reg_wait + dclh_cpu_resp_wait +
                dclh_other;
            dclh_wait_mismatch =
                ((dclh_latency_bucket_mismatch == 64'd0) &&
                 (dclh_wait_sum == dclh_wait_expected)) ? 64'd0 :
                ((dclh_wait_sum >= dclh_wait_expected) ?
                 (dclh_wait_sum - dclh_wait_expected) :
                 (dclh_wait_expected - dclh_wait_sum));
            dhitopt_sum =
                dhitopt_success_count + dhitopt_fallback_count +
                dhitopt_block_store_buffer_count +
                dhitopt_block_uncached_count + dhitopt_block_fault_count +
                dhitopt_block_miss_count +
                dhitopt_block_alignment_count + dhitopt_unknown_count;
            dhitopt_mismatch = (dhitopt_sum >= dhitopt_candidate_count) ?
                (dhitopt_sum - dhitopt_candidate_count) :
                (dhitopt_candidate_count - dhitopt_sum);
            loaduse_path_sum =
                loaduse_path_wait_dcache_hit +
                loaduse_path_wait_dcache_miss +
                loaduse_path_wait_signext +
                loaduse_path_wait_memwb +
                loaduse_path_wait_wb +
                loaduse_path_wait_lsu_pending +
                loaduse_path_wait_store_buffer +
                loaduse_path_wait_other;
            loaduse_path_mismatch =
                (loaduse_path_sum >= hazard_load_use_total) ?
                (loaduse_path_sum - hazard_load_use_total) :
                (hazard_load_use_total - loaduse_path_sum);
            lbp2_sum =
                lbp2_safe_dcache_resp_to_ex +
                lbp2_safe_mem_stage_to_ex +
                lbp2_safe_memwb_to_ex +
                lbp2_safe_wb_to_ex +
                lbp2_blocked_signext_not_ready +
                lbp2_blocked_resp_not_ready +
                lbp2_blocked_exception_or_fault +
                lbp2_blocked_uncached +
                lbp2_blocked_kill_or_flush +
                lbp2_blocked_store_buffer_conflict +
                lbp2_blocked_timing_unknown +
                lbp2_unknown;
            lbp2_mismatch =
                (lbp2_sum >= lbp2_candidate_total) ?
                (lbp2_sum - lbp2_candidate_total) :
                (lbp2_candidate_total - lbp2_sum);
            lsu_so2_sum =
                lsu_so2_load_blocked_by_load +
                lsu_so2_load_blocked_by_store +
                lsu_so2_store_blocked_by_load +
                lsu_so2_store_blocked_by_store +
                lsu_so2_load_blocked_by_sbuf_drain +
                lsu_so2_load_blocked_by_dcache_refill +
                lsu_so2_load_blocked_by_uncached +
                lsu_so2_other;
            lsu_so2_mismatch =
                (lsu_so2_sum >= lsu_so2_total) ?
                (lsu_so2_sum - lsu_so2_total) :
                (lsu_so2_total - lsu_so2_sum);
            sbuf_store_resp_uncached =
                (store_buffer_uncached_drain_wait_count > mem_v2_store_resp_wait) ?
                mem_v2_store_resp_wait : store_buffer_uncached_drain_wait_count;
            sbuf_store_resp_fence = 64'd0;
            sbuf_store_resp_full =
                (store_buffer_full_stall_count > (mem_v2_store_resp_wait - sbuf_store_resp_uncached)) ?
                (mem_v2_store_resp_wait - sbuf_store_resp_uncached) :
                store_buffer_full_stall_count;
            sbuf_store_resp_other =
                mem_v2_store_resp_wait - sbuf_store_resp_uncached -
                sbuf_store_resp_fence - sbuf_store_resp_full;
            sbuf_store_resp_cpu_visible =
                sbuf_store_resp_uncached + sbuf_store_resp_fence +
                sbuf_store_resp_full + sbuf_store_resp_other;
            sbuf_store_resp_sum = sbuf_store_resp_cpu_visible;
            sbuf_store_resp_mismatch =
                (sbuf_store_resp_sum >= mem_v2_store_resp_wait) ?
                (sbuf_store_resp_sum - mem_v2_store_resp_wait) :
                (mem_v2_store_resp_wait - sbuf_store_resp_sum);
            sbuf_drain_impact_sum =
                sbuf_drain_overlap_with_useful_pipeline +
                sbuf_drain_blocks_load +
                sbuf_drain_blocks_store_enqueue +
                sbuf_drain_blocks_pipeline_mem +
                sbuf_drain_blocks_icache_or_ptw +
                sbuf_drain_background_only +
                sbuf_drain_unknown;
            sbuf_drain_impact_mismatch =
                (sbuf_drain_impact_sum >= store_buffer_drain_wait_count) ?
                (sbuf_drain_impact_sum - store_buffer_drain_wait_count) :
                (store_buffer_drain_wait_count - sbuf_drain_impact_sum);
            exmem_skid_sum =
                stat_exmem_skid_enqueue +
                stat_exmem_skid_full_stall +
                stat_exmem_skid_blocked_not_safe +
                stat_exmem_skid_blocked_branch +
                stat_exmem_skid_blocked_mem +
                stat_exmem_skid_blocked_csr +
                stat_exmem_skid_blocked_exception +
                stat_exmem_skid_blocked_div +
                stat_exmem_skid_blocked_structural;
            exmem_skid_mismatch =
                (exmem_skid_sum >= stat_exmem_skid_candidate) ?
                (exmem_skid_sum - stat_exmem_skid_candidate) :
                (stat_exmem_skid_candidate - exmem_skid_sum);
            mem_issue_after_skid_remaining =
                (stat_exmem_skid_candidate >= stat_exmem_skid_enqueue) ?
                (stat_exmem_skid_candidate - stat_exmem_skid_enqueue) : 64'd0;
            mem_issue_after_skid_mismatch = exmem_skid_mismatch;
            exmem_skid_eff_enqueue_sum =
                exmem_skid_eff_enqueue_and_ex_allowin +
                exmem_skid_eff_enqueue_but_upstream_still_stall;
            exmem_skid_eff_mismatch_enqueue =
                (exmem_skid_eff_enqueue_sum >= stat_exmem_skid_enqueue) ?
                (exmem_skid_eff_enqueue_sum - stat_exmem_skid_enqueue) :
                (stat_exmem_skid_enqueue - exmem_skid_eff_enqueue_sum);
            exmem_skid_eff_no_gain_sum =
                exmem_skid_eff_no_gain_skid_full +
                exmem_skid_eff_no_gain_next_inst_blocked +
                exmem_skid_eff_no_gain_mem_response_wait +
                exmem_skid_eff_no_gain_dequeue_same_as_old_path +
                exmem_skid_eff_unknown;
            exmem_skid_eff_mismatch_nogain =
                (exmem_skid_eff_no_gain_sum >=
                 exmem_skid_eff_enqueue_but_upstream_still_stall) ?
                (exmem_skid_eff_no_gain_sum -
                 exmem_skid_eff_enqueue_but_upstream_still_stall) :
                (exmem_skid_eff_enqueue_but_upstream_still_stall -
                 exmem_skid_eff_no_gain_sum);
            exmem_skid_eff_mismatch =
                exmem_skid_eff_mismatch_enqueue +
                exmem_skid_eff_mismatch_nogain;

            $display("[CPIAttribution] cycles=%0d commit=%0d bubble=%0d CPI_ideal_commit=1.00",
                cycle_count, commit_count, bubble_expected);
            print_cpi_line("CPIAttribution", "CPI_total", cycle_count);
            $display("[CPIAttribution] exclusive_bubbles trap_flush=%0d wb_block=%0d mem_lsu_wait=%0d dcache_wait=%0d store_wait=%0d load_use=%0d raw_hazard=%0d csr_or_special=%0d id_stage_stall=%0d ex_stage_stall=%0d if_id_empty=%0d frontend_wait=%0d icache_fetch_wait=%0d branch_recovery=%0d resp_block=%0d stage_latency=%0d unknown=%0d sum=%0d mismatch=%0d",
                bucket_trap_flush, bucket_wb_block, bucket_mem_lsu_wait,
                bucket_dcache_wait, bucket_store_wait, bucket_load_use,
                bucket_raw_hazard, bucket_csr_special, bucket_id_stall,
                bucket_ex_stall, bucket_if_id_empty, bucket_frontend_wait,
                bucket_icache_fetch_wait, bucket_branch_recovery,
                bucket_resp_block, bucket_stage_latency, bucket_unknown,
                bubble_sum, mismatch);
            print_cpi_line("CPIAttribution", "redirect_contrib", bucket_trap_flush + bucket_branch_recovery);
            print_cpi_line("CPIAttribution", "frontend_wait_contrib", bucket_frontend_wait + bucket_icache_fetch_wait);
            print_cpi_line("CPIAttribution", "mem_lsu_wait_contrib", bucket_mem_lsu_wait + bucket_dcache_wait + bucket_store_wait);
            print_cpi_line("CPIAttribution", "hazard_contrib", bucket_load_use + bucket_raw_hazard + bucket_csr_special);
            print_cpi_line("CPIAttribution", "resp_block_contrib", bucket_resp_block);
            print_cpi_line("CPIAttribution", "stage_latency_contrib", bucket_stage_latency);
            print_cpi_line("CPIAttribution", "unknown_contrib", bucket_unknown);
            $display("[PipeOcc] IF=%0d IFID=%0d ID=%0d EX=%0d MEM=%0d WB=%0d COMMIT=%0d",
                occ_if, occ_ifid, occ_id, occ_ex, occ_mem, occ_wb, occ_commit);
            $display("[PipeReady] if_ready=%0d ifid_ready=%0d id_ready=%0d ex_ready=%0d mem_ready=%0d wb_ready=%0d",
                ready_if, ready_ifid, ready_id, ready_ex, ready_mem, ready_wb);
            $display("[PipeStall] if_stall_by_ifid_full=%0d ifid_by_id_not_ready=%0d id_by_ex_not_ready=%0d ex_by_mem_not_ready=%0d mem_by_wb_not_ready=%0d mem_by_dbus=%0d wb_stall=%0d",
                stall_if_by_ifid_full, stall_ifid_by_id_not_ready,
                stall_id_by_ex_not_ready, stall_ex_by_mem_not_ready,
                stall_mem_by_wb_not_ready, stall_mem_by_dbus, stall_wb);
            $display("[FrontendBreakdown] frontend_wait=%0d self_wait=%0d backpressure_wait=%0d ifid_full=%0d id_not_ready=%0d ex_mem_wb_backpressure=%0d no_resp=%0d req_not_ready=%0d icache_miss=%0d icache_req_wait=%0d epoch_recovery=%0d ptw=%0d unknown=%0d sum=%0d mismatch=%0d",
                bucket_frontend_wait, frontend_self_wait, frontend_backpressure_wait,
                frontend_ifid_queue_full_wait, frontend_id_not_ready_backpressure,
                frontend_ex_not_ready_backpressure, frontend_if_pipe_no_resp_wait,
                frontend_if_pipe_req_not_ready_wait, frontend_icache_miss_refill_wait,
                frontend_icache_req_wait, frontend_epoch_drop_recovery_wait,
                frontend_ptw_wait, frontend_unknown, frontend_sum, frontend_mismatch);
            $display("[RespBlockBreakdown] resp_block=%0d if_queue_full=%0d id_not_ready=%0d epoch_drop=%0d fifo_full=%0d resp_wait_commit=%0d if_stage_not_accepting=%0d unknown=%0d sum=%0d mismatch=%0d",
                resp_block_total, resp_block_if_queue_full,
                resp_block_id_not_ready, resp_block_epoch_drop,
                resp_block_fifo_full, resp_block_wait_commit,
                resp_block_if_stage_not_accepting, resp_block_unknown,
                resp_block_if_queue_full + resp_block_id_not_ready +
                resp_block_epoch_drop + resp_block_fifo_full +
                resp_block_wait_commit + resp_block_if_stage_not_accepting +
                resp_block_unknown,
                (resp_block_total >=
                    (resp_block_if_queue_full + resp_block_id_not_ready +
                     resp_block_epoch_drop + resp_block_fifo_full +
                     resp_block_wait_commit + resp_block_if_stage_not_accepting +
                     resp_block_unknown)) ?
                    (resp_block_total -
                     (resp_block_if_queue_full + resp_block_id_not_ready +
                      resp_block_epoch_drop + resp_block_fifo_full +
                      resp_block_wait_commit + resp_block_if_stage_not_accepting +
                      resp_block_unknown)) :
                    ((resp_block_if_queue_full + resp_block_id_not_ready +
                      resp_block_epoch_drop + resp_block_fifo_full +
                      resp_block_wait_commit + resp_block_if_stage_not_accepting +
                      resp_block_unknown) - resp_block_total));
            $display("[StageLatencyBreakdown] stage_latency=%0d ifid_valid=%0d id_valid=%0d ex_valid=%0d mem_valid=%0d frontend_empty=%0d",
                bucket_stage_latency, stage_latency_ifid_valid,
                stage_latency_id_valid, stage_latency_ex_valid,
                stage_latency_mem_valid, stage_latency_frontend_empty);
            $display("[IFQueueStat] depth0=%0d depth1=%0d depth2=%0d full=%0d empty=%0d push_attempt=%0d push_fire=%0d push_block=%0d pop_attempt=%0d pop_fire=%0d pop_block=%0d entry0_valid=%0d entry1_valid=%0d both_valid=%0d single_valid=%0d",
                ifq_depth0_cycles, ifq_depth1_cycles, ifq_depth2_cycles,
                ifq_full_cycles, ifq_empty_cycles, ifq_push_attempt,
                ifq_push_fire, ifq_push_block, ifq_pop_attempt, ifq_pop_fire,
                ifq_pop_block, ifq_entry0_valid_cycles, ifq_entry1_valid_cycles,
                ifq_both_valid_cycles, ifq_single_valid_cycles);
            $display("[IFQueueBlockBreakdown] push_block=%0d full_no_pop=%0d full_with_pop_same_cycle=%0d full_id_ready=%0d full_id_not_ready=%0d backend_stall=%0d redirect=%0d epoch_drop=%0d load_use=%0d raw_hazard=%0d mem_lsu=%0d csr_special=%0d unknown=%0d sum=%0d mismatch=%0d",
                ifq_push_block, ifq_block_full_no_pop,
                ifq_block_full_with_pop_same_cycle, ifq_block_full_id_ready,
                ifq_block_full_id_not_ready, ifq_block_backend_stall,
                ifq_block_redirect, ifq_block_epoch_drop, ifq_block_load_use,
                ifq_block_raw_hazard, ifq_block_mem_lsu, ifq_block_csr_special,
                ifq_block_unknown, ifq_block_sum, ifq_block_mismatch);
            $display("[HazardBreakdown] load_use=%0d raw_hazard=%0d csr_special=%0d mem_lsu=%0d total=%0d sum=%0d mismatch=%0d",
                hazard_load_use_total, hazard_raw_total, hazard_csr_total,
                hazard_mem_lsu_total, hazard_total_expected, hazard_total_sum,
                hazard_total_mismatch);
            $display("[HazardProducer] ex_alu=%0d mem_alu=%0d wb=%0d load_hit=%0d load_miss=%0d lsu_pending=%0d csr=%0d muldiv=%0d store=%0d branch=%0d system=%0d unknown=%0d",
                hazard_ex_alu, hazard_mem_alu, hazard_wb, hazard_load_hit,
                hazard_load_miss, hazard_lsu_pending, hazard_csr,
                hazard_muldiv, hazard_store, hazard_branch, hazard_system,
                hazard_unknown);
            $display("[HazardOperand] rs1=%0d rs2=%0d both=%0d unknown=%0d mismatch=%0d",
                hazard_rs1, hazard_rs2, hazard_both, hazard_operand_unknown,
                hazard_operand_mismatch);
            $display("[ForwardingOpportunity] ex_alu_to_ex=%0d mem_alu_to_ex=%0d wb_to_ex=%0d load_hit_to_ex=%0d load_miss_not_bypassable=%0d csr_not_bypassable=%0d muldiv_not_bypassable=%0d memory_order_not_bypassable=%0d unknown=%0d",
                fwd_ex_alu_to_ex, fwd_mem_alu_to_ex, fwd_wb_to_ex,
                fwd_load_hit_to_ex, fwd_load_miss_not_bypassable,
                fwd_csr_not_bypassable, fwd_muldiv_not_bypassable,
                fwd_memory_order_not_bypassable, fwd_unknown);
            $display("[ForwardingStat] rs1_ex_alu_fwd=%0d rs2_ex_alu_fwd=%0d rs1_mem_alu_fwd=%0d rs2_mem_alu_fwd=%0d rs1_wb_fwd=%0d rs2_wb_fwd=%0d fwd_x0_block=%0d fwd_load_block=%0d fwd_csr_block=%0d fwd_kill_block=%0d",
                fwd_stat_rs1_ex_alu, fwd_stat_rs2_ex_alu,
                fwd_stat_rs1_mem_alu, fwd_stat_rs2_mem_alu,
                fwd_stat_rs1_wb, fwd_stat_rs2_wb,
                fwd_stat_x0_block, fwd_stat_load_block,
                fwd_stat_csr_block, fwd_stat_kill_block);
            $display("[LoadUseBreakdown] load_hit=%0d load_miss=%0d lsu_busy=%0d wait_mem=%0d wait_wb=%0d same_cycle_resp_possible=%0d unknown=%0d sum=%0d mismatch=%0d",
                load_use_load_hit, load_use_load_miss, load_use_lsu_busy,
                load_use_wait_mem, load_use_wait_wb,
                load_use_same_cycle_resp_possible, load_use_unknown,
                load_use_sum, load_use_mismatch);
            $display("[LoadPendingBreakdown] load_lsu_pending_cycles=%0d true_dcache_load_miss_wait=%0d load_hit_no_forward_wait=%0d load_wait_mem_resp=%0d load_wait_wb=%0d load_blocked_by_store_miss=%0d load_blocked_by_uncached=%0d lsu_single_outstanding_wait=%0d other=%0d sum=%0d mismatch=%0d",
                fwd_load_miss_not_bypassable,
                load_pending_true_dcache_load_miss_wait,
                load_pending_load_hit_no_forward_wait,
                load_pending_load_wait_mem_resp, load_pending_load_wait_wb,
                load_pending_blocked_by_store_miss,
                load_pending_blocked_by_uncached,
                load_pending_lsu_single_outstanding_wait,
                load_pending_other, load_pending_sum, load_pending_mismatch);
            $display("[RawHazardBreakdown] raw_alu_ex=%0d raw_alu_mem=%0d raw_alu_wb=%0d raw_load_mem=%0d raw_load_wb=%0d raw_csr=%0d raw_muldiv=%0d raw_hidden=%0d raw_unknown=%0d sum=%0d mismatch=%0d",
                raw_alu_ex, raw_alu_mem, raw_alu_wb, raw_load_mem,
                raw_load_wb, raw_csr, raw_muldiv, raw_hidden, raw_unknown,
                raw_sum, raw_mismatch);
            $display("[HazardAfterForwarding] raw_alu_ex=%0d raw_alu_mem=%0d raw_load_mem=%0d raw_load_wb=%0d raw_muldiv=%0d load_lsu_pending_cycles=%0d load_hit_no_forward_wait=%0d",
                raw_alu_ex, raw_alu_mem, raw_load_mem, raw_load_wb,
                raw_muldiv, fwd_load_miss_not_bypassable,
                load_pending_load_hit_no_forward_wait);
            $display("[MDUBreakdown] fast_mul_enable=%0d fast_mul_latency=%0d effective_fast_mul_latency=%0d mul_total=%0d mul_fast_count=%0d mul_old_count=%0d mul_wait_cycles=%0d mul_consumer_stall=%0d mul_avg_latency=%0d mul_max_latency=%0d mulh_total=%0d mulh_wait_cycles=%0d div_total=%0d div_wait_cycles=%0d div_avg_latency=%0d div_max_latency=%0d rem_total=%0d rem_wait_cycles=%0d mdu_busy_cycles=%0d mdu_result_ready_cycles=%0d mdu_consumer_wait_cycles=%0d raw_muldiv=%0d mdu_unknown=%0d mdu_mismatch=%0d",
`ifdef NPC_FAST_MUL
                1,
`else
                0,
`endif
`ifdef NPC_FAST_MUL_LATENCY
                `NPC_FAST_MUL_LATENCY,
`else
                2,
`endif
                2,
                mdu_mul_total + fast_mul_total,
                fast_mul_total, old_mul_total,
                mdu_mul_wait_cycles, mdu_mul_consumer_stall,
                mul_avg_latency, mdu_mul_max_latency,
                mdu_mulh_total, mdu_mulh_wait_cycles,
                mdu_div_total, mdu_div_wait_cycles, div_avg_latency,
                mdu_div_max_latency, mdu_rem_total, mdu_rem_wait_cycles,
                mdu_busy_cycles, mdu_result_ready_cycles,
                mdu_consumer_wait_cycles, raw_muldiv, mdu_unknown, mdu_mismatch);
            $display("[FastMulStat] issue=%0d resp=%0d kill=%0d flush_drop=%0d forward=%0d stall_wait_ready=%0d old_div_path=%0d old_rem_path=%0d mismatch=%0d",
                fast_mul_issue, fast_mul_resp, fast_mul_kill_display,
                fast_mul_flush_drop, fast_mul_forward,
                fast_mul_stall_wait_ready, fast_mul_old_div_path,
                fast_mul_old_rem_path, fast_mul_mismatch);
            $display("[LoadHitForwardingOpportunity] total=%0d aligned_hit=%0d unaligned=%0d dtlb_hit=%0d dcache_hit=%0d uncached=%0d page_fault_or_access_fault=%0d signext_ready=%0d consumer_rs1=%0d consumer_rs2=%0d producer_killed=%0d same_cycle_possible=%0d mem_to_ex_possible=%0d wb_only=%0d not_safe=%0d unknown=%0d mismatch=%0d",
                loadhit_total, loadhit_aligned_hit, loadhit_unaligned,
                loadhit_dtlb_hit, loadhit_dcache_hit, loadhit_uncached,
                loadhit_fault, loadhit_signext_ready, loadhit_consumer_rs1,
                loadhit_consumer_rs2, loadhit_producer_killed,
                loadhit_same_cycle_possible, loadhit_mem_to_ex_possible,
                loadhit_wb_only, loadhit_not_safe, loadhit_unknown,
                loadhit_mismatch);
            $display("[LoadHitTiming] load_hit_total=%0d load_hit_data_valid_cycle=%0d signext_ready_cycle=%0d wb_ready_cycle=%0d consumer_wait_ex=%0d consumer_wait_mem=%0d consumer_wait_wb=%0d",
                loadhit_timing_total, loadhit_timing_data_valid_cycle,
                loadhit_timing_signext_ready_cycle,
                loadhit_timing_wb_ready_cycle,
                loadhit_timing_consumer_wait_ex,
                loadhit_timing_consumer_wait_mem,
                loadhit_timing_consumer_wait_wb);
            $display("[LoadForwardingSafety] total=%0d safe_mem_to_ex=%0d safe_memwb_to_ex=%0d safe_wb_to_ex=%0d blocked_by_uncached=%0d blocked_by_fault=%0d blocked_by_misaligned=%0d blocked_by_kill=%0d blocked_by_not_signext_ready=%0d blocked_by_lsu_pending=%0d unknown=%0d sum=%0d mismatch=%0d",
                loadhit_timing_total, load_forward_safe_mem_to_ex,
                load_forward_safe_memwb_to_ex, load_forward_safe_wb_to_ex,
                load_forward_blocked_uncached, load_forward_blocked_fault,
                load_forward_blocked_misaligned, load_forward_blocked_kill,
                load_forward_blocked_not_signext,
                load_forward_blocked_lsu_pending, load_forward_unknown,
                load_forward_sum, load_forward_mismatch);
            $display("[LoadRAWBreakdown] raw_load_mem=%0d raw_load_wb=%0d load_hit_no_forward_wait=%0d load_wait_mem_resp=%0d load_blocked_by_store_miss=%0d lsu_single_outstanding=%0d",
                raw_load_mem, raw_load_wb,
                load_pending_load_hit_no_forward_wait,
                load_pending_load_wait_mem_resp,
                load_pending_blocked_by_store_miss,
                load_pending_lsu_single_outstanding_wait);
            $display("[FrontendCPI] if_pipe_no_resp=%0d epoch_drop_recovery=%0d icache_miss_wait=%0d icache_refill_wait=%0d itlb_miss_wait=%0d frontend_backpressure=%0d if_pipe_stall_total=%0d if_pipe_epoch_drop_total=%0d if_pipe_icache_miss_total=%0d",
                frontend_if_pipe_no_resp, frontend_epoch_drop_recovery,
                frontend_icache_miss_wait_seen, frontend_icache_refill_wait_seen,
                frontend_itlb_miss_wait_seen, frontend_backpressure,
                if_pipe_stall_cycle, if_pipe_epoch_drop_count,
                if_pipe_icache_miss_count);
            $display("[MemCPI] dcache_load_miss_wait=%0d dcache_store_miss_wait=%0d uncached_wait=%0d store_response_wait=%0d load_response_wait=%0d slow_fallback_wait=%0d mem_single_outstanding_wait=%0d req_load_wait=%0d req_store_wait=%0d cache_req_wait_total=%0d cache_hit_resp_wait_total=%0d cache_miss_wait_total=%0d writeback_wait_total=%0d",
                64'd0, 64'd0, 64'd0, mem_store_resp_wait, mem_load_resp_wait,
                bucket_mem_lsu_wait, mem_single_outstanding_wait,
                mem_load_req_wait, mem_store_req_wait,
                dcache_req_wait_cycle, dcache_hit_resp_wait_cycle,
                dcache_miss_wait_cycle, dcache_writeback_cycle);
            $display("[MemBackendBreakdown] load_response_wait=%0d store_response_wait=%0d store_miss_wait=%0d store_write_resp_wait=%0d dcache_miss_wait=%0d dcache_req_wait=%0d single_outstanding_wait=%0d uncached_wait=%0d writeback_wait=%0d other=%0d total=%0d mismatch=%0d",
                mem_backend_load_response_wait, mem_backend_store_response_wait,
                mem_backend_store_miss_wait, mem_backend_store_write_resp_wait,
                mem_backend_dcache_miss_wait, mem_backend_dcache_req_wait,
                mem_backend_single_outstanding_wait, mem_backend_uncached_wait,
                mem_backend_writeback_wait, mem_backend_other,
                mem_backend_total, mem_backend_mismatch);
            $display("[MemBackendV2] load_req_total=%0d load_req_fire=%0d load_resp_wait=%0d load_resp_wait_dcache_hit=%0d load_resp_wait_dcache_miss=%0d load_resp_wait_blocked_by_store=%0d load_resp_wait_blocked_by_single_outstanding=%0d load_resp_wait_uncached=%0d load_resp_wait_other=%0d load_resp_sum=%0d load_resp_mismatch=%0d",
                mem_v2_load_req_total, mem_v2_load_req_fire,
                mem_v2_load_resp_wait, mem_v2_load_resp_wait_dcache_hit,
                mem_v2_load_resp_wait_dcache_miss,
                mem_v2_load_resp_wait_blocked_by_store,
                mem_v2_load_resp_wait_blocked_by_single,
                mem_v2_load_resp_wait_uncached,
                mem_v2_load_resp_wait_other, mem_v2_load_resp_sum,
                mem_v2_load_resp_mismatch);
            $display("[MemBackendV2] store_req_total=%0d store_req_fire=%0d store_hit_total=%0d store_miss_total=%0d store_resp_wait=%0d store_hit_resp_wait=%0d store_miss_resp_wait=%0d store_write_resp_wait=%0d store_refill_wait=%0d store_uncached_wait=%0d store_other=%0d store_resp_sum=%0d store_resp_mismatch=%0d",
                mem_v2_store_req_total, mem_v2_store_req_fire,
                mem_v2_store_hit_total, mem_v2_store_miss_total,
                mem_v2_store_resp_wait, mem_v2_store_hit_resp_wait,
                mem_v2_store_miss_resp_wait,
                mem_v2_store_write_resp_wait, mem_v2_store_refill_wait,
                mem_v2_store_uncached_wait, mem_v2_store_other,
                mem_v2_store_resp_sum, mem_v2_store_resp_mismatch);
            $display("[MemBackendV2] single_outstanding_wait=%0d single_outstanding_load_blocked_by_load=%0d single_outstanding_load_blocked_by_store=%0d single_outstanding_store_blocked_by_load=%0d single_outstanding_store_blocked_by_store=%0d single_outstanding_uncached=%0d single_outstanding_other=%0d single_sum=%0d single_mismatch=%0d",
                mem_v2_single_outstanding_wait,
                mem_v2_single_load_blocked_by_load,
                mem_v2_single_load_blocked_by_store,
                mem_v2_single_store_blocked_by_load,
                mem_v2_single_store_blocked_by_store,
                mem_v2_single_uncached, mem_v2_single_other,
                mem_v2_single_sum, mem_v2_single_mismatch);
            $display("[StoreBufferOpportunity] store_total=%0d store_aligned_cached_hit=%0d store_aligned_cached_miss=%0d store_uncached_or_mmio=%0d store_fault_or_page_fault=%0d store_misaligned_or_cross_page=%0d store_atomic_or_lrsc=%0d store_before_fence=%0d store_killed_or_exception=%0d store_buffer_safe_candidate=%0d store_buffer_not_safe=%0d unknown=%0d sum=%0d mismatch=%0d",
                storebuf_store_total, storebuf_aligned_cached_hit,
                storebuf_aligned_cached_miss, storebuf_uncached_or_mmio,
                storebuf_fault_or_page_fault,
                storebuf_misaligned_or_cross_page,
                storebuf_atomic_or_lrsc, storebuf_before_fence,
                storebuf_killed_or_exception, storebuf_safe_candidate,
                storebuf_not_safe, storebuf_unknown, storebuf_sum,
                storebuf_mismatch);
            $display("[DCacheRespProtocol] load_hit_latency_avg=%0d load_hit_latency_max=%0d store_hit_latency_avg=%0d store_hit_latency_max=%0d load_resp_valid_wait_ready=%0d store_resp_valid_wait_ready=%0d mem_stage_wait_resp_ready=%0d wb_stage_backpressure=%0d resp_protocol_overhead=%0d",
                dcache_proto_load_avg, dcache_proto_load_hit_latency_max,
                dcache_proto_store_avg, dcache_proto_store_hit_latency_max,
                dcache_proto_load_resp_valid_wait_ready,
                dcache_proto_store_resp_valid_wait_ready,
                dcache_proto_mem_stage_wait_resp_ready,
                dcache_proto_wb_stage_backpressure,
                dcache_proto_resp_protocol_overhead);
            $display("[LoadResponsePath] load_req_total=%0d load_req_fire=%0d load_resp_total=%0d load_resp_fire=%0d load_resp_wait_total=%0d load_resp_wait_dcache_hit=%0d load_resp_wait_dcache_miss=%0d load_resp_wait_uncached=%0d load_resp_wait_store_buffer_drain=%0d load_resp_wait_store_buffer_conflict=%0d load_resp_wait_lsu_busy=%0d load_resp_wait_mem_stage_block=%0d load_resp_wait_wb_block=%0d load_resp_wait_other=%0d sum=%0d mismatch=%0d",
                lrp_load_req_total, lrp_load_req_fire,
                lrp_load_resp_total, lrp_load_resp_fire,
                lrp_wait_total, lrp_wait_dcache_hit,
                lrp_wait_dcache_miss, lrp_wait_uncached,
                lrp_wait_sbuf_drain, lrp_wait_sbuf_conflict,
                lrp_wait_lsu_busy, lrp_wait_mem_stage_block,
                lrp_wait_wb_block, lrp_wait_other,
                lrp_wait_sum, lrp_wait_mismatch);
            $display("[DCacheLoadHitPath] load_hit_total=%0d load_hit_latency_1=%0d load_hit_latency_2=%0d load_hit_latency_3=%0d load_hit_latency_gt3=%0d load_hit_latency_avg=%0d load_hit_latency_max=%0d tag_lookup_wait=%0d data_array_wait=%0d data_align_wait=%0d signext_wait=%0d response_reg_wait=%0d cpu_resp_wait=%0d other=%0d wait_sum=%0d wait_expected=%0d mismatch=%0d",
                dclh_total, dclh_latency_1, dclh_latency_2,
                dclh_latency_3, dclh_latency_gt3, dclh_avg,
                dclh_latency_max, dclh_tag_lookup_wait,
                dclh_data_array_wait, dclh_data_align_wait,
                dclh_signext_wait, dclh_response_reg_wait,
                dclh_cpu_resp_wait, dclh_other, dclh_wait_sum,
                dclh_wait_expected, dclh_wait_mismatch);
            $display("[DCacheHitOptStat] enable=%0d fast_hit_candidate=%0d fast_hit_success=%0d fast_hit_fallback=%0d fast_hit_blocked_by_store_buffer=%0d fast_hit_blocked_by_uncached=%0d fast_hit_blocked_by_fault=%0d fast_hit_blocked_by_miss=%0d fast_hit_blocked_by_alignment=%0d unknown=%0d sum=%0d mismatch=%0d",
`ifdef NPC_DCACHE_HIT_OPT
                1,
`else
                0,
`endif
                dhitopt_candidate_count, dhitopt_success_count,
                dhitopt_fallback_count, dhitopt_block_store_buffer_count,
                dhitopt_block_uncached_count, dhitopt_block_fault_count,
                dhitopt_block_miss_count, dhitopt_block_alignment_count,
                dhitopt_unknown_count, dhitopt_sum, dhitopt_mismatch);
            $display("[LoadUsePath] load_use_total=%0d load_use_wait_dcache_hit=%0d load_use_wait_dcache_miss=%0d load_use_wait_signext=%0d load_use_wait_memwb=%0d load_use_wait_wb=%0d load_use_wait_lsu_pending=%0d load_use_wait_store_buffer=%0d load_use_wait_other=%0d sum=%0d mismatch=%0d",
                hazard_load_use_total, loaduse_path_wait_dcache_hit,
                loaduse_path_wait_dcache_miss,
                loaduse_path_wait_signext, loaduse_path_wait_memwb,
                loaduse_path_wait_wb, loaduse_path_wait_lsu_pending,
                loaduse_path_wait_store_buffer, loaduse_path_wait_other,
                loaduse_path_sum, loaduse_path_mismatch);
            $display("[LoadBypassOpportunityV2] candidate_total=%0d safe_dcache_resp_to_ex=%0d safe_mem_stage_to_ex=%0d safe_memwb_to_ex=%0d safe_wb_to_ex=%0d blocked_by_signext_not_ready=%0d blocked_by_resp_not_ready=%0d blocked_by_exception_or_fault=%0d blocked_by_uncached=%0d blocked_by_kill_or_flush=%0d blocked_by_store_buffer_conflict=%0d blocked_by_timing_unknown=%0d unknown=%0d sum=%0d mismatch=%0d",
                lbp2_candidate_total, lbp2_safe_dcache_resp_to_ex,
                lbp2_safe_mem_stage_to_ex, lbp2_safe_memwb_to_ex,
                lbp2_safe_wb_to_ex, lbp2_blocked_signext_not_ready,
                lbp2_blocked_resp_not_ready,
                lbp2_blocked_exception_or_fault, lbp2_blocked_uncached,
                lbp2_blocked_kill_or_flush,
                lbp2_blocked_store_buffer_conflict,
                lbp2_blocked_timing_unknown, lbp2_unknown,
                lbp2_sum, lbp2_mismatch);
            $display("[LSUSingleOutstandingV2] single_outstanding_wait_total=%0d load_blocked_by_load=%0d load_blocked_by_store=%0d store_blocked_by_load=%0d store_blocked_by_store=%0d load_blocked_by_store_buffer_drain=%0d load_blocked_by_dcache_refill=%0d load_blocked_by_uncached=%0d other=%0d sum=%0d mismatch=%0d",
                lsu_so2_total, lsu_so2_load_blocked_by_load,
                lsu_so2_load_blocked_by_store,
                lsu_so2_store_blocked_by_load,
                lsu_so2_store_blocked_by_store,
                lsu_so2_load_blocked_by_sbuf_drain,
                lsu_so2_load_blocked_by_dcache_refill,
                lsu_so2_load_blocked_by_uncached,
                lsu_so2_other, lsu_so2_sum, lsu_so2_mismatch);
            $display("[LSUPipeBridgeIntegration] enable=%0d load_via_bridge=%0d store_via_bridge=%0d atomic_via_bridge=%0d pipe_direct_dcache_req=%0d pipe_store_direct=%0d pipe_load_direct=%0d mismatch=%0d",
`ifdef NPC_LSU_HIT_PIPELINE
                1,
`else
                0,
`endif
                lsu_pipe_bridge_load_via, lsu_pipe_bridge_store_via,
                lsu_pipe_bridge_atomic_via, 0, 0, 0, 0);
            $display("[LSULoadBypassStat] enable=%0d candidate=%0d release_id_stall=%0d forward_rs1=%0d forward_rs2=%0d forward_both=%0d blocked_not_load=%0d blocked_rd_x0=%0d blocked_resp_not_ready=%0d blocked_signext_not_ready=%0d blocked_fault=%0d blocked_kill=%0d blocked_uncached=%0d blocked_miss=%0d blocked_misaligned=%0d blocked_atomic=%0d blocked_store_buffer=%0d mismatch=%0d",
`ifdef NPC_LSU_LOAD_BYPASS
                1,
`else
                0,
`endif
                lsu_load_bypass_candidate,
                lsu_load_bypass_release_id_stall,
                lsu_load_bypass_forward_rs1,
                lsu_load_bypass_forward_rs2,
                lsu_load_bypass_forward_both,
                lsu_load_bypass_blocked_not_load,
                lsu_load_bypass_blocked_rd_x0,
                lsu_load_bypass_blocked_resp_not_ready,
                lsu_load_bypass_blocked_signext_not_ready,
                lsu_load_bypass_blocked_fault,
                lsu_load_bypass_blocked_kill,
                lsu_load_bypass_blocked_uncached,
                lsu_load_bypass_blocked_miss,
                lsu_load_bypass_blocked_misaligned,
                lsu_load_bypass_blocked_atomic,
                lsu_load_bypass_blocked_store_buffer,
                lsu_load_bypass_mismatch);
            $display("[LoadLateBypassWindow] total_load_dep=%0d distance1=%0d distance2=%0d distance3plus=%0d resp_ready_before_consumer_ex=%0d resp_ready_same_cycle_consumer_ex=%0d signext_ready_before_consumer_ex=%0d safe_late_bypass=%0d actual_late_bypass=%0d unknown=%0d mismatch=%0d",
                late_bypass_total_load_dep, late_bypass_distance1,
                late_bypass_distance2, late_bypass_distance3plus,
                late_bypass_resp_ready_before_ex,
                late_bypass_resp_ready_same_cycle_ex,
                late_bypass_signext_ready_before_ex,
                late_bypass_safe, late_bypass_actual,
                late_bypass_unknown, late_bypass_mismatch);
            $display("[ExMemSkidStat] enable=%0d candidate=%0d enqueue=%0d dequeue=%0d full_stall=%0d flush_drop=%0d blocked_not_safe=%0d blocked_branch=%0d blocked_mem=%0d blocked_csr=%0d blocked_exception=%0d blocked_div=%0d blocked_structural=%0d saved_cycles_est=%0d mismatch=%0d",
`ifdef NPC_EX_MEM_SKID
                1,
`else
                0,
`endif
                stat_exmem_skid_candidate, stat_exmem_skid_enqueue,
                stat_exmem_skid_dequeue, stat_exmem_skid_full_stall,
                stat_exmem_skid_flush_drop, stat_exmem_skid_blocked_not_safe,
                stat_exmem_skid_blocked_branch, stat_exmem_skid_blocked_mem,
                stat_exmem_skid_blocked_csr,
                stat_exmem_skid_blocked_exception,
                stat_exmem_skid_blocked_div,
                stat_exmem_skid_blocked_structural,
                stat_exmem_skid_enqueue, exmem_skid_mismatch);
            $display("[MemIssueWindowAfterSkid] mem_wait_total=%0d can_skid_ex_to_mem=%0d actual_skid_enqueue=%0d remaining_structural_or_not_safe=%0d would_need_response_queue_remaining=%0d mismatch=%0d",
                bucket_mem_lsu_wait + bucket_dcache_wait + bucket_store_wait,
                stat_exmem_skid_candidate, stat_exmem_skid_enqueue,
                mem_issue_after_skid_remaining,
                stat_exmem_skid_blocked_structural,
                mem_issue_after_skid_mismatch);
            $display("[ExMemSkidEffectiveness] enqueue=%0d dequeue=%0d enqueue_when_ex_would_stall=%0d enqueue_and_ex_allowin=%0d enqueue_and_id_allowin=%0d enqueue_and_if_pop_next=%0d enqueue_but_upstream_still_stall=%0d skid_full_cycles=%0d skid_holds_during_mem_wait=%0d skid_dequeue_after_mem_release=%0d skid_dequeue_same_cycle_mem_release=%0d skid_dequeue_causes_wb_valid=%0d saved_ex_stall_est=%0d saved_id_stall_est=%0d saved_if_stall_est=%0d no_gain_due_to_skid_full=%0d no_gain_due_to_next_inst_blocked=%0d no_gain_due_to_mem_response_wait=%0d no_gain_due_to_dequeue_same_as_old_path=%0d unknown=%0d mismatch=%0d",
                stat_exmem_skid_enqueue, stat_exmem_skid_dequeue,
                exmem_skid_eff_enqueue_when_ex_would_stall,
                exmem_skid_eff_enqueue_and_ex_allowin,
                exmem_skid_eff_enqueue_and_id_allowin,
                exmem_skid_eff_enqueue_and_if_pop_next,
                exmem_skid_eff_enqueue_but_upstream_still_stall,
                stat_exmem_skid_hold_cycles,
                stat_exmem_skid_hold_mem_wait_cycles,
                stat_exmem_skid_dequeue_after_mem_release,
                stat_exmem_skid_dequeue_same_cycle_mem_release,
                stat_exmem_skid_dequeue_causes_wb_valid,
                exmem_skid_eff_enqueue_and_ex_allowin,
                exmem_skid_eff_enqueue_and_id_allowin,
                exmem_skid_eff_enqueue_and_if_pop_next,
                exmem_skid_eff_no_gain_skid_full,
                exmem_skid_eff_no_gain_next_inst_blocked,
                exmem_skid_eff_no_gain_mem_response_wait,
                exmem_skid_eff_no_gain_dequeue_same_as_old_path,
                exmem_skid_eff_unknown,
                exmem_skid_eff_mismatch);
            $display("[StoreBufferStat] enable=%0d entries=%0d enqueue=%0d dequeue=%0d full_stall=%0d drain_req=%0d drain_resp=%0d drain_wait=%0d load_forward=%0d load_stall_conflict=%0d load_stall_buffer_nonempty=%0d fence_drain_wait=%0d uncached_drain_wait=%0d killed_store_block=%0d",
`ifdef NPC_STORE_BUFFER_ENABLE
                1,
`else
                0,
`endif
`ifdef NPC_STORE_BUFFER_ENTRIES
                `NPC_STORE_BUFFER_ENTRIES,
`else
                2,
`endif
                store_buffer_enqueue_count, store_buffer_dequeue_count,
                store_buffer_full_stall_count, store_buffer_drain_req_count,
                store_buffer_drain_resp_count, store_buffer_drain_wait_count,
                store_buffer_load_forward_count,
                store_buffer_load_stall_conflict_count,
                store_buffer_load_stall_buffer_nonempty_count,
                store_buffer_fence_drain_wait_count,
                store_buffer_uncached_drain_wait_count,
                store_buffer_killed_store_block_count);
            $display("[StoreBufferBreakdown] store_resp_wait_total=%0d store_resp_wait_cpu_visible=%0d store_resp_wait_background_drain=%0d store_resp_wait_uncached=%0d store_resp_wait_fence_drain=%0d store_resp_wait_full_stall=%0d store_resp_wait_other=%0d mismatch=%0d",
                mem_v2_store_resp_wait,
                sbuf_store_resp_cpu_visible,
                store_buffer_drain_wait_count,
                sbuf_store_resp_uncached,
                sbuf_store_resp_fence,
                sbuf_store_resp_full,
                sbuf_store_resp_other,
                sbuf_store_resp_mismatch);
            $display("[StoreBufferDrainImpact] drain_wait_total=%0d drain_overlap_with_useful_pipeline=%0d drain_blocks_load=%0d drain_blocks_store_enqueue=%0d drain_blocks_pipeline_mem=%0d drain_blocks_icache_or_ptw=%0d drain_background_only=%0d unknown=%0d sum=%0d mismatch=%0d",
                store_buffer_drain_wait_count,
                sbuf_drain_overlap_with_useful_pipeline,
                sbuf_drain_blocks_load,
                sbuf_drain_blocks_store_enqueue,
                sbuf_drain_blocks_pipeline_mem,
                sbuf_drain_blocks_icache_or_ptw,
                sbuf_drain_background_only,
                sbuf_drain_unknown,
                sbuf_drain_impact_sum,
                sbuf_drain_impact_mismatch);
            $display("[PostStoreCPI] mem_lsu_wait=%0d dcache_wait=%0d store_wait=%0d load_use=%0d raw_hazard=%0d frontend_wait=%0d stage_latency=%0d unknown=%0d",
                bucket_mem_lsu_wait, bucket_dcache_wait, bucket_store_wait,
                bucket_load_use, bucket_raw_hazard, bucket_frontend_wait,
                bucket_stage_latency, bucket_unknown);
            print_cpi_line("PostFastMulCPI", "CPI_total", cycle_count);
            $display("[PostFastMulCPI] mem_lsu_wait=%0d dcache_wait=%0d store_wait=%0d load_use=%0d raw_hazard=%0d frontend_wait=%0d stage_latency=%0d unknown=%0d mismatch=%0d",
                bucket_mem_lsu_wait, bucket_dcache_wait, bucket_store_wait,
                bucket_load_use, bucket_raw_hazard, bucket_frontend_wait,
                bucket_stage_latency, bucket_unknown, mismatch);
            $display("[StoreBufferCapacity] entries=%0d effective_entries=%0d max_occupancy=%0d occupancy0_cycles=%0d occupancy1_cycles=%0d occupancy2_cycles=%0d full_stall=%0d enqueue_when_occupancy0=%0d enqueue_when_occupancy1=%0d enqueue_when_full=%0d",
`ifdef NPC_STORE_BUFFER_ENTRIES
                `NPC_STORE_BUFFER_ENTRIES,
                (`NPC_STORE_BUFFER_ENTRIES > 2) ? 2 : `NPC_STORE_BUFFER_ENTRIES,
`else
                2, 2,
`endif
                store_buffer_max_occupancy_count,
                store_buffer_occupancy0_count,
                store_buffer_occupancy1_count,
                store_buffer_occupancy2_count,
                store_buffer_full_stall_count,
                store_buffer_enqueue_occ0_count,
                store_buffer_enqueue_occ1_count,
                store_buffer_enqueue_full_count);
            $display("[FrontendCPI] cache_req_wait_total=%0d cache_hit_resp_wait_total=%0d cache_miss_wait_total=%0d",
                icache_req_wait_cycle, icache_hit_resp_wait_cycle,
                icache_miss_wait_cycle);
            if (cycle_count > branch_redirect_wait_cycle) begin
                branch_perfect_cycles = cycle_count - branch_redirect_wait_cycle;
            end else begin
                branch_perfect_cycles = 64'd0;
            end
            print_cpi_line("UpperBound", "branch_perfect_cpi", branch_perfect_cycles);
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 64'd0;
            commit_count <= 64'd0;
            bubble_count <= 64'd0;
            bucket_trap_flush <= 64'd0;
            bucket_wb_block <= 64'd0;
            bucket_mem_lsu_wait <= 64'd0;
            bucket_dcache_wait <= 64'd0;
            bucket_store_wait <= 64'd0;
            bucket_load_use <= 64'd0;
            bucket_raw_hazard <= 64'd0;
            bucket_csr_special <= 64'd0;
            bucket_id_stall <= 64'd0;
            bucket_ex_stall <= 64'd0;
            bucket_if_id_empty <= 64'd0;
            bucket_frontend_wait <= 64'd0;
            bucket_icache_fetch_wait <= 64'd0;
            bucket_branch_recovery <= 64'd0;
            bucket_resp_block <= 64'd0;
            bucket_stage_latency <= 64'd0;
            bucket_unknown <= 64'd0;
            occ_if <= 64'd0;
            occ_ifid <= 64'd0;
            occ_id <= 64'd0;
            occ_ex <= 64'd0;
            occ_mem <= 64'd0;
            occ_wb <= 64'd0;
            occ_commit <= 64'd0;
            stall_if_by_ifid_full <= 64'd0;
            stall_ifid_by_id_not_ready <= 64'd0;
            stall_id_by_ex_not_ready <= 64'd0;
            stall_ex_by_mem_not_ready <= 64'd0;
            stall_mem_by_wb_not_ready <= 64'd0;
            stall_mem_by_dbus <= 64'd0;
            stall_wb <= 64'd0;
            frontend_if_pipe_no_resp <= 64'd0;
            frontend_backpressure <= 64'd0;
            frontend_epoch_drop_recovery <= 64'd0;
            frontend_icache_miss_wait_seen <= 64'd0;
            frontend_icache_refill_wait_seen <= 64'd0;
            frontend_itlb_miss_wait_seen <= 64'd0;
            frontend_self_wait <= 64'd0;
            frontend_backpressure_wait <= 64'd0;
            frontend_ifid_queue_full_wait <= 64'd0;
            frontend_id_not_ready_backpressure <= 64'd0;
            frontend_ex_not_ready_backpressure <= 64'd0;
            frontend_if_pipe_no_resp_wait <= 64'd0;
            frontend_if_pipe_req_not_ready_wait <= 64'd0;
            frontend_icache_miss_refill_wait <= 64'd0;
            frontend_icache_req_wait <= 64'd0;
            frontend_epoch_drop_recovery_wait <= 64'd0;
            frontend_ptw_wait <= 64'd0;
            frontend_unknown <= 64'd0;
            mem_load_resp_wait <= 64'd0;
            mem_store_resp_wait <= 64'd0;
            mem_load_req_wait <= 64'd0;
            mem_store_req_wait <= 64'd0;
            mem_store_wait <= 64'd0;
            mem_load_wait <= 64'd0;
            mem_single_outstanding_wait <= 64'd0;
            prev_icache_req_wait_cycle <= 64'd0;
            prev_icache_miss_wait_cycle <= 64'd0;
            prev_dcache_miss_wait_cycle <= 64'd0;
            prev_dcache_uncached_access <= 64'd0;
            prev_dcache_writeback_cycle <= 64'd0;
            prev_store_buffer_drain_wait_count <= 64'd0;
            prev_store_buffer_load_stall_conflict_count <= 64'd0;
            prev_icache_pipe_resp_fifo_full_cycle <= 64'd0;
            prev_if_pipe_epoch_drop_count <= 64'd0;
            prev_if_pipe_icache_miss_count <= 64'd0;
            ready_if <= 64'd0;
            ready_ifid <= 64'd0;
            ready_id <= 64'd0;
            ready_ex <= 64'd0;
            ready_mem <= 64'd0;
            ready_wb <= 64'd0;
            resp_block_total <= 64'd0;
            resp_block_if_queue_full <= 64'd0;
            resp_block_id_not_ready <= 64'd0;
            resp_block_epoch_drop <= 64'd0;
            resp_block_fifo_full <= 64'd0;
            resp_block_wait_commit <= 64'd0;
            resp_block_if_stage_not_accepting <= 64'd0;
            resp_block_unknown <= 64'd0;
            stage_latency_ifid_valid <= 64'd0;
            stage_latency_id_valid <= 64'd0;
            stage_latency_ex_valid <= 64'd0;
            stage_latency_mem_valid <= 64'd0;
            stage_latency_frontend_empty <= 64'd0;
            ifq_depth0_cycles <= 64'd0;
            ifq_depth1_cycles <= 64'd0;
            ifq_depth2_cycles <= 64'd0;
            ifq_full_cycles <= 64'd0;
            ifq_empty_cycles <= 64'd0;
            ifq_push_attempt <= 64'd0;
            ifq_push_fire <= 64'd0;
            ifq_push_block <= 64'd0;
            ifq_pop_attempt <= 64'd0;
            ifq_pop_fire <= 64'd0;
            ifq_pop_block <= 64'd0;
            ifq_entry0_valid_cycles <= 64'd0;
            ifq_entry1_valid_cycles <= 64'd0;
            ifq_both_valid_cycles <= 64'd0;
            ifq_single_valid_cycles <= 64'd0;
            ifq_block_full_no_pop <= 64'd0;
            ifq_block_full_with_pop_same_cycle <= 64'd0;
            ifq_block_full_id_ready <= 64'd0;
            ifq_block_full_id_not_ready <= 64'd0;
            ifq_block_backend_stall <= 64'd0;
            ifq_block_redirect <= 64'd0;
            ifq_block_epoch_drop <= 64'd0;
            ifq_block_load_use <= 64'd0;
            ifq_block_raw_hazard <= 64'd0;
            ifq_block_mem_lsu <= 64'd0;
            ifq_block_csr_special <= 64'd0;
            ifq_block_unknown <= 64'd0;
            hazard_load_use_total <= 64'd0;
            hazard_raw_total <= 64'd0;
            hazard_csr_total <= 64'd0;
            hazard_mem_lsu_total <= 64'd0;
            hazard_rs1 <= 64'd0;
            hazard_rs2 <= 64'd0;
            hazard_both <= 64'd0;
            hazard_operand_unknown <= 64'd0;
            hazard_ex_alu <= 64'd0;
            hazard_mem_alu <= 64'd0;
            hazard_wb <= 64'd0;
            hazard_load_hit <= 64'd0;
            hazard_load_miss <= 64'd0;
            hazard_lsu_pending <= 64'd0;
            hazard_csr <= 64'd0;
            hazard_muldiv <= 64'd0;
            hazard_store <= 64'd0;
            hazard_branch <= 64'd0;
            hazard_system <= 64'd0;
            hazard_unknown <= 64'd0;
            fwd_ex_alu_to_ex <= 64'd0;
            fwd_mem_alu_to_ex <= 64'd0;
            fwd_wb_to_ex <= 64'd0;
            fwd_load_hit_to_ex <= 64'd0;
            fwd_load_miss_not_bypassable <= 64'd0;
            fwd_csr_not_bypassable <= 64'd0;
            fwd_muldiv_not_bypassable <= 64'd0;
            fwd_memory_order_not_bypassable <= 64'd0;
            fwd_unknown <= 64'd0;
            fwd_stat_rs1_ex_alu <= 64'd0;
            fwd_stat_rs2_ex_alu <= 64'd0;
            fwd_stat_rs1_mem_alu <= 64'd0;
            fwd_stat_rs2_mem_alu <= 64'd0;
            fwd_stat_rs1_wb <= 64'd0;
            fwd_stat_rs2_wb <= 64'd0;
            fwd_stat_x0_block <= 64'd0;
            fwd_stat_load_block <= 64'd0;
            fwd_stat_csr_block <= 64'd0;
            fwd_stat_kill_block <= 64'd0;
            load_pending_true_dcache_load_miss_wait <= 64'd0;
            load_pending_load_hit_no_forward_wait <= 64'd0;
            load_pending_load_wait_mem_resp <= 64'd0;
            load_pending_load_wait_wb <= 64'd0;
            load_pending_blocked_by_store_miss <= 64'd0;
            load_pending_blocked_by_uncached <= 64'd0;
            load_pending_lsu_single_outstanding_wait <= 64'd0;
            load_pending_other <= 64'd0;
            loadhit_total <= 64'd0;
            loadhit_aligned_hit <= 64'd0;
            loadhit_unaligned <= 64'd0;
            loadhit_dtlb_hit <= 64'd0;
            loadhit_dcache_hit <= 64'd0;
            loadhit_uncached <= 64'd0;
            loadhit_fault <= 64'd0;
            loadhit_signext_ready <= 64'd0;
            loadhit_consumer_rs1 <= 64'd0;
            loadhit_consumer_rs2 <= 64'd0;
            loadhit_producer_killed <= 64'd0;
            loadhit_same_cycle_possible <= 64'd0;
            loadhit_mem_to_ex_possible <= 64'd0;
            loadhit_wb_only <= 64'd0;
            loadhit_not_safe <= 64'd0;
            loadhit_unknown <= 64'd0;
            loadhit_timing_total <= 64'd0;
            loadhit_timing_data_valid_cycle <= 64'd0;
            loadhit_timing_signext_ready_cycle <= 64'd0;
            loadhit_timing_wb_ready_cycle <= 64'd0;
            loadhit_timing_consumer_wait_ex <= 64'd0;
            loadhit_timing_consumer_wait_mem <= 64'd0;
            loadhit_timing_consumer_wait_wb <= 64'd0;
            load_forward_safe_mem_to_ex <= 64'd0;
            load_forward_safe_memwb_to_ex <= 64'd0;
            load_forward_safe_wb_to_ex <= 64'd0;
            load_forward_blocked_uncached <= 64'd0;
            load_forward_blocked_fault <= 64'd0;
            load_forward_blocked_misaligned <= 64'd0;
            load_forward_blocked_kill <= 64'd0;
            load_forward_blocked_not_signext <= 64'd0;
            load_forward_blocked_lsu_pending <= 64'd0;
            load_forward_unknown <= 64'd0;
            load_use_load_hit <= 64'd0;
            load_use_load_miss <= 64'd0;
            load_use_lsu_busy <= 64'd0;
            load_use_wait_mem <= 64'd0;
            load_use_wait_wb <= 64'd0;
            load_use_same_cycle_resp_possible <= 64'd0;
            load_use_unknown <= 64'd0;
            raw_alu_ex <= 64'd0;
            raw_alu_mem <= 64'd0;
            raw_alu_wb <= 64'd0;
            raw_load_mem <= 64'd0;
            raw_load_wb <= 64'd0;
            raw_csr <= 64'd0;
            raw_muldiv <= 64'd0;
            raw_hidden <= 64'd0;
            raw_unknown <= 64'd0;
            mdu_mul_total <= 64'd0;
            mdu_mul_wait_cycles <= 64'd0;
            mdu_mul_consumer_stall <= 64'd0;
            mdu_mul_latency_sum <= 64'd0;
            mdu_mul_max_latency <= 64'd0;
            mdu_mulh_total <= 64'd0;
            mdu_mulh_wait_cycles <= 64'd0;
            mdu_div_total <= 64'd0;
            mdu_div_wait_cycles <= 64'd0;
            mdu_div_latency_sum <= 64'd0;
            mdu_div_max_latency <= 64'd0;
            mdu_rem_total <= 64'd0;
            mdu_rem_wait_cycles <= 64'd0;
            mdu_busy_cycles <= 64'd0;
            mdu_result_ready_cycles <= 64'd0;
            mdu_consumer_wait_cycles <= 64'd0;
            mdu_unknown <= 64'd0;
            mdu_current_latency <= 64'd0;
            mdu_current_op <= 3'b0;
            mdu_current_valid <= 1'b0;
            fast_mul_issue <= 64'd0;
            fast_mul_resp <= 64'd0;
            fast_mul_kill <= 64'd0;
            fast_mul_flush_drop <= 64'd0;
            fast_mul_forward <= 64'd0;
            fast_mul_stall_wait_ready <= 64'd0;
            fast_mul_old_div_path <= 64'd0;
            fast_mul_old_rem_path <= 64'd0;
            fast_mul_total <= 64'd0;
            old_mul_total <= 64'd0;
            mem_backend_load_response_wait <= 64'd0;
            mem_backend_store_response_wait <= 64'd0;
            mem_backend_store_miss_wait <= 64'd0;
            mem_backend_store_write_resp_wait <= 64'd0;
            mem_backend_dcache_miss_wait <= 64'd0;
            mem_backend_dcache_req_wait <= 64'd0;
            mem_backend_single_outstanding_wait <= 64'd0;
            mem_backend_uncached_wait <= 64'd0;
            mem_backend_writeback_wait <= 64'd0;
            mem_backend_other <= 64'd0;
            mem_v2_load_req_total <= 64'd0;
            mem_v2_load_req_fire <= 64'd0;
            mem_v2_load_resp_wait <= 64'd0;
            mem_v2_load_resp_wait_dcache_hit <= 64'd0;
            mem_v2_load_resp_wait_dcache_miss <= 64'd0;
            mem_v2_load_resp_wait_blocked_by_store <= 64'd0;
            mem_v2_load_resp_wait_blocked_by_single <= 64'd0;
            mem_v2_load_resp_wait_uncached <= 64'd0;
            mem_v2_load_resp_wait_other <= 64'd0;
            mem_v2_store_req_total <= 64'd0;
            mem_v2_store_req_fire <= 64'd0;
            mem_v2_store_hit_total <= 64'd0;
            mem_v2_store_miss_total <= 64'd0;
            mem_v2_store_resp_wait <= 64'd0;
            mem_v2_store_hit_resp_wait <= 64'd0;
            mem_v2_store_miss_resp_wait <= 64'd0;
            mem_v2_store_write_resp_wait <= 64'd0;
            mem_v2_store_refill_wait <= 64'd0;
            mem_v2_store_uncached_wait <= 64'd0;
            mem_v2_store_other <= 64'd0;
            mem_v2_single_outstanding_wait <= 64'd0;
            mem_v2_single_load_blocked_by_load <= 64'd0;
            mem_v2_single_load_blocked_by_store <= 64'd0;
            mem_v2_single_store_blocked_by_load <= 64'd0;
            mem_v2_single_store_blocked_by_store <= 64'd0;
            mem_v2_single_uncached <= 64'd0;
            mem_v2_single_other <= 64'd0;
            storebuf_store_total <= 64'd0;
            storebuf_aligned_cached_hit <= 64'd0;
            storebuf_aligned_cached_miss <= 64'd0;
            storebuf_uncached_or_mmio <= 64'd0;
            storebuf_fault_or_page_fault <= 64'd0;
            storebuf_misaligned_or_cross_page <= 64'd0;
            storebuf_atomic_or_lrsc <= 64'd0;
            storebuf_before_fence <= 64'd0;
            storebuf_killed_or_exception <= 64'd0;
            storebuf_safe_candidate <= 64'd0;
            storebuf_not_safe <= 64'd0;
            storebuf_unknown <= 64'd0;
            dcache_proto_load_hit_latency_sum <= 64'd0;
            dcache_proto_load_hit_latency_count <= 64'd0;
            dcache_proto_load_hit_latency_max <= 64'd0;
            dcache_proto_store_hit_latency_sum <= 64'd0;
            dcache_proto_store_hit_latency_count <= 64'd0;
            dcache_proto_store_hit_latency_max <= 64'd0;
            dcache_proto_load_resp_valid_wait_ready <= 64'd0;
            dcache_proto_store_resp_valid_wait_ready <= 64'd0;
            dcache_proto_mem_stage_wait_resp_ready <= 64'd0;
            dcache_proto_wb_stage_backpressure <= 64'd0;
            dcache_proto_resp_protocol_overhead <= 64'd0;
            dcache_proto_current_latency <= 64'd0;
            dcache_proto_track_valid <= 1'b0;
            dcache_proto_track_store <= 1'b0;
            dcache_proto_track_hit <= 1'b0;
            sbuf_drain_overlap_with_useful_pipeline <= 64'd0;
            sbuf_drain_blocks_load <= 64'd0;
            sbuf_drain_blocks_store_enqueue <= 64'd0;
            sbuf_drain_blocks_pipeline_mem <= 64'd0;
            sbuf_drain_blocks_icache_or_ptw <= 64'd0;
            sbuf_drain_background_only <= 64'd0;
            sbuf_drain_unknown <= 64'd0;
            lrp_load_req_total <= 64'd0;
            lrp_load_req_fire <= 64'd0;
            lrp_load_resp_total <= 64'd0;
            lrp_load_resp_fire <= 64'd0;
            lrp_wait_total <= 64'd0;
            lrp_wait_dcache_hit <= 64'd0;
            lrp_wait_dcache_miss <= 64'd0;
            lrp_wait_uncached <= 64'd0;
            lrp_wait_sbuf_drain <= 64'd0;
            lrp_wait_sbuf_conflict <= 64'd0;
            lrp_wait_lsu_busy <= 64'd0;
            lrp_wait_mem_stage_block <= 64'd0;
            lrp_wait_wb_block <= 64'd0;
            lrp_wait_other <= 64'd0;
            dclh_total <= 64'd0;
            dclh_latency_1 <= 64'd0;
            dclh_latency_2 <= 64'd0;
            dclh_latency_3 <= 64'd0;
            dclh_latency_gt3 <= 64'd0;
            dclh_latency_sum <= 64'd0;
            dclh_latency_max <= 64'd0;
            dclh_tag_lookup_wait <= 64'd0;
            dclh_data_array_wait <= 64'd0;
            dclh_data_align_wait <= 64'd0;
            dclh_signext_wait <= 64'd0;
            dclh_response_reg_wait <= 64'd0;
            dclh_cpu_resp_wait <= 64'd0;
            dclh_other <= 64'd0;
            loaduse_path_wait_dcache_hit <= 64'd0;
            loaduse_path_wait_dcache_miss <= 64'd0;
            loaduse_path_wait_signext <= 64'd0;
            loaduse_path_wait_memwb <= 64'd0;
            loaduse_path_wait_wb <= 64'd0;
            loaduse_path_wait_lsu_pending <= 64'd0;
            loaduse_path_wait_store_buffer <= 64'd0;
            loaduse_path_wait_other <= 64'd0;
            lbp2_candidate_total <= 64'd0;
            lbp2_safe_dcache_resp_to_ex <= 64'd0;
            lbp2_safe_mem_stage_to_ex <= 64'd0;
            lbp2_safe_memwb_to_ex <= 64'd0;
            lbp2_safe_wb_to_ex <= 64'd0;
            lbp2_blocked_signext_not_ready <= 64'd0;
            lbp2_blocked_resp_not_ready <= 64'd0;
            lbp2_blocked_exception_or_fault <= 64'd0;
            lbp2_blocked_uncached <= 64'd0;
            lbp2_blocked_kill_or_flush <= 64'd0;
            lbp2_blocked_store_buffer_conflict <= 64'd0;
            lbp2_blocked_timing_unknown <= 64'd0;
            lbp2_unknown <= 64'd0;
            lsu_so2_total <= 64'd0;
            lsu_so2_load_blocked_by_load <= 64'd0;
            lsu_so2_load_blocked_by_store <= 64'd0;
            lsu_so2_store_blocked_by_load <= 64'd0;
            lsu_so2_store_blocked_by_store <= 64'd0;
            lsu_so2_load_blocked_by_sbuf_drain <= 64'd0;
            lsu_so2_load_blocked_by_dcache_refill <= 64'd0;
            lsu_so2_load_blocked_by_uncached <= 64'd0;
            lsu_so2_other <= 64'd0;
            lsu_pipe_bridge_load_via <= 64'd0;
            lsu_pipe_bridge_store_via <= 64'd0;
            lsu_pipe_bridge_atomic_via <= 64'd0;
            lsu_load_bypass_candidate <= 64'd0;
            lsu_load_bypass_release_id_stall <= 64'd0;
            lsu_load_bypass_forward_rs1 <= 64'd0;
            lsu_load_bypass_forward_rs2 <= 64'd0;
            lsu_load_bypass_forward_both <= 64'd0;
            lsu_load_bypass_blocked_not_load <= 64'd0;
            lsu_load_bypass_blocked_rd_x0 <= 64'd0;
            lsu_load_bypass_blocked_resp_not_ready <= 64'd0;
            lsu_load_bypass_blocked_signext_not_ready <= 64'd0;
            lsu_load_bypass_blocked_fault <= 64'd0;
            lsu_load_bypass_blocked_kill <= 64'd0;
            lsu_load_bypass_blocked_uncached <= 64'd0;
            lsu_load_bypass_blocked_miss <= 64'd0;
            lsu_load_bypass_blocked_misaligned <= 64'd0;
            lsu_load_bypass_blocked_atomic <= 64'd0;
            lsu_load_bypass_blocked_store_buffer <= 64'd0;
            late_bypass_total_load_dep <= 64'd0;
            late_bypass_distance1 <= 64'd0;
            late_bypass_distance2 <= 64'd0;
            late_bypass_distance3plus <= 64'd0;
            late_bypass_resp_ready_before_ex <= 64'd0;
            late_bypass_resp_ready_same_cycle_ex <= 64'd0;
            late_bypass_signext_ready_before_ex <= 64'd0;
            late_bypass_safe <= 64'd0;
            late_bypass_actual <= 64'd0;
            late_bypass_unknown <= 64'd0;
            exmem_skid_eff_enqueue_when_ex_would_stall <= 64'd0;
            exmem_skid_eff_enqueue_and_ex_allowin <= 64'd0;
            exmem_skid_eff_enqueue_and_id_allowin <= 64'd0;
            exmem_skid_eff_enqueue_and_if_pop_next <= 64'd0;
            exmem_skid_eff_enqueue_but_upstream_still_stall <= 64'd0;
            exmem_skid_eff_no_gain_skid_full <= 64'd0;
            exmem_skid_eff_no_gain_next_inst_blocked <= 64'd0;
            exmem_skid_eff_no_gain_mem_response_wait <= 64'd0;
            exmem_skid_eff_no_gain_dequeue_same_as_old_path <= 64'd0;
            exmem_skid_eff_unknown <= 64'd0;
            prev_exmem_skid_enqueue <= 1'b0;
            printed <= 1'b0;
        end else if (!printed && terminal_commit) begin
            print_stats();
            printed <= 1'b1;
        end else if (!printed) begin
            cycle_count <= cycle_count + 64'd1;
            prev_exmem_skid_enqueue <= stat_exmem_skid_enqueue_fire;
            prev_icache_req_wait_cycle <= icache_req_wait_cycle;
            prev_icache_miss_wait_cycle <= icache_miss_wait_cycle;
            prev_dcache_miss_wait_cycle <= dcache_miss_wait_cycle;
            prev_dcache_uncached_access <= dcache_uncached_access;
            prev_dcache_writeback_cycle <= dcache_writeback_cycle;
            prev_store_buffer_drain_wait_count <= store_buffer_drain_wait_count;
            prev_store_buffer_load_stall_conflict_count <=
                store_buffer_load_stall_conflict_count;
            prev_icache_pipe_resp_fifo_full_cycle <= icache_pipe_resp_fifo_full_cycle;
            prev_if_pipe_epoch_drop_count <= if_pipe_epoch_drop_count;
            prev_if_pipe_icache_miss_count <= if_pipe_icache_miss_count;

            if (fs_to_ds_valid || if_stall || ibus_req_valid || ibus_resp_ready) occ_if <= occ_if + 64'd1;
            if (fs_to_ds_valid) occ_ifid <= occ_ifid + 64'd1;
            if (ds_to_es_valid || id_stage_block) occ_id <= occ_id + 64'd1;
            if (es_valid || es_to_ms_valid || ex_stage_block) occ_ex <= occ_ex + 64'd1;
            if (ms_valid || ms_to_ws_valid || ms_stage_block) occ_mem <= occ_mem + 64'd1;
            if (ws_valid) occ_wb <= occ_wb + 64'd1;

            if (ds_stat_rs1_ex_alu_fwd) fwd_stat_rs1_ex_alu <= fwd_stat_rs1_ex_alu + 64'd1;
            if (ds_stat_rs2_ex_alu_fwd) fwd_stat_rs2_ex_alu <= fwd_stat_rs2_ex_alu + 64'd1;
            if (es_stat_rs1_mem_alu_fwd) fwd_stat_rs1_mem_alu <= fwd_stat_rs1_mem_alu + 64'd1;
            if (es_stat_rs2_mem_alu_fwd) fwd_stat_rs2_mem_alu <= fwd_stat_rs2_mem_alu + 64'd1;
            if (es_stat_rs1_wb_fwd) fwd_stat_rs1_wb <= fwd_stat_rs1_wb + 64'd1;
            if (es_stat_rs2_wb_fwd) fwd_stat_rs2_wb <= fwd_stat_rs2_wb + 64'd1;
            if (load_bypass_forward_rs1_now) lsu_load_bypass_forward_rs1 <= lsu_load_bypass_forward_rs1 + 64'd1;
            if (load_bypass_forward_rs2_now) lsu_load_bypass_forward_rs2 <= lsu_load_bypass_forward_rs2 + 64'd1;
            if (load_bypass_forward_rs1_now && load_bypass_forward_rs2_now) begin
                lsu_load_bypass_forward_both <= lsu_load_bypass_forward_both + 64'd1;
            end
            if (load_bypass_forward_any_now) late_bypass_actual <= late_bypass_actual + 64'd1;
            if (ds_stat_fwd_load_block) fwd_stat_load_block <= fwd_stat_load_block + 64'd1;
            if (ds_stat_fwd_csr_block) fwd_stat_csr_block <= fwd_stat_csr_block + 64'd1;
            if (ds_stat_fwd_kill_block) fwd_stat_kill_block <= fwd_stat_kill_block + 64'd1;
            if (es_stat_fast_mul_issue) begin
                fast_mul_issue <= fast_mul_issue + 64'd1;
                fast_mul_total <= fast_mul_total + 64'd1;
            end
            if (es_stat_fast_mul_resp) fast_mul_resp <= fast_mul_resp + 64'd1;
            if (es_stat_fast_mul_kill) fast_mul_kill <= fast_mul_kill + 64'd1;
            if (es_stat_fast_mul_flush_drop) fast_mul_flush_drop <= fast_mul_flush_drop + 64'd1;
            if (es_stat_fast_mul_forward) fast_mul_forward <= fast_mul_forward + 64'd1;
            if (es_stat_fast_mul_stall_wait_ready) begin
                fast_mul_stall_wait_ready <= fast_mul_stall_wait_ready + 64'd1;
            end
            if (es_stat_old_div_path) fast_mul_old_div_path <= fast_mul_old_div_path + 64'd1;
            if (es_stat_old_rem_path) fast_mul_old_rem_path <= fast_mul_old_rem_path + 64'd1;

            if (es_stat_mdu_busy) begin
                mdu_busy_cycles <= mdu_busy_cycles + 64'd1;
                if (mdu_current_valid) begin
                    mdu_current_latency <= mdu_current_latency + 64'd1;
                end
                if (mdu_op_mul) begin
                    mdu_mul_wait_cycles <= mdu_mul_wait_cycles + 64'd1;
                end else if (mdu_op_mulh) begin
                    mdu_mulh_wait_cycles <= mdu_mulh_wait_cycles + 64'd1;
                end else if (mdu_op_div) begin
                    mdu_div_wait_cycles <= mdu_div_wait_cycles + 64'd1;
                end else if (mdu_op_rem) begin
                    mdu_rem_wait_cycles <= mdu_rem_wait_cycles + 64'd1;
                end else begin
                    mdu_unknown <= mdu_unknown + 64'd1;
                end
            end
            if (es_stat_mdu_result_ready) begin
                mdu_result_ready_cycles <= mdu_result_ready_cycles + 64'd1;
            end
            if (es_stat_mdu_req_fire) begin
                mdu_current_valid <= 1'b1;
                mdu_current_op <= es_stat_mdu_op;
                mdu_current_latency <= 64'd1;
                if (mdu_op_mul || mdu_op_mulh) begin
                    old_mul_total <= old_mul_total + 64'd1;
                end
            end
            if (mdu_current_valid && es_stat_mdu_result_ready) begin
                if (mdu_current_op == 3'd0) begin
                    mdu_mul_total <= mdu_mul_total + 64'd1;
                    mdu_mul_latency_sum <= mdu_mul_latency_sum + mdu_current_latency;
                    if (mdu_current_latency > mdu_mul_max_latency) begin
                        mdu_mul_max_latency <= mdu_current_latency;
                    end
                end else if ((mdu_current_op == 3'd1) || (mdu_current_op == 3'd2) ||
                        (mdu_current_op == 3'd3)) begin
                    mdu_mulh_total <= mdu_mulh_total + 64'd1;
                end else if ((mdu_current_op == 3'd4) || (mdu_current_op == 3'd5)) begin
                    mdu_div_total <= mdu_div_total + 64'd1;
                    mdu_div_latency_sum <= mdu_div_latency_sum + mdu_current_latency;
                    if (mdu_current_latency > mdu_div_max_latency) begin
                        mdu_div_max_latency <= mdu_current_latency;
                    end
                end else if ((mdu_current_op == 3'd6) || (mdu_current_op == 3'd7)) begin
                    mdu_rem_total <= mdu_rem_total + 64'd1;
                end
                mdu_current_valid <= 1'b0;
                mdu_current_latency <= 64'd0;
            end

            if (ifid_full_wait) stall_if_by_ifid_full <= stall_if_by_ifid_full + 64'd1;
            if (ifid_backpressure) stall_ifid_by_id_not_ready <= stall_ifid_by_id_not_ready + 64'd1;
            if (id_backpressure) stall_id_by_ex_not_ready <= stall_id_by_ex_not_ready + 64'd1;
            if (ex_backpressure) stall_ex_by_mem_not_ready <= stall_ex_by_mem_not_ready + 64'd1;
            if (mem_backpressure) stall_mem_by_wb_not_ready <= stall_mem_by_wb_not_ready + 64'd1;
            if (dbus_req_wait_now || dbus_resp_wait_now) stall_mem_by_dbus <= stall_mem_by_dbus + 64'd1;
            if (wb_block_now) stall_wb <= stall_wb + 64'd1;
            if (if_stat_fetch_room && ibus_req_ready) ready_if <= ready_if + 64'd1;
            if (ds_allowin) ready_ifid <= ready_ifid + 64'd1;
            if (es_allowin) ready_id <= ready_id + 64'd1;
            if (ms_allowin) ready_ex <= ready_ex + 64'd1;
            if (ws_allowin) ready_mem <= ready_mem + 64'd1;
            ready_wb <= ready_wb + 64'd1;

            if (if_stat_queue_count == 2'd0) ifq_depth0_cycles <= ifq_depth0_cycles + 64'd1;
            if (if_stat_queue_count == 2'd1) ifq_depth1_cycles <= ifq_depth1_cycles + 64'd1;
            if (if_stat_queue_count == 2'd2) ifq_depth2_cycles <= ifq_depth2_cycles + 64'd1;
            if (if_stat_queue_full) ifq_full_cycles <= ifq_full_cycles + 64'd1;
            if (if_stat_queue_count == 2'd0) ifq_empty_cycles <= ifq_empty_cycles + 64'd1;
            if (ifq_push_attempt_now) ifq_push_attempt <= ifq_push_attempt + 64'd1;
            if (if_stat_resp_enq) ifq_push_fire <= ifq_push_fire + 64'd1;
            if (ifq_push_block_now) ifq_push_block <= ifq_push_block + 64'd1;
            if (if_stat_fs_valid) ifq_pop_attempt <= ifq_pop_attempt + 64'd1;
            if (if_stat_fs_pop) ifq_pop_fire <= ifq_pop_fire + 64'd1;
            if (if_stat_fs_valid && !ds_allowin) ifq_pop_block <= ifq_pop_block + 64'd1;
            if (if_stat_queue_count != 2'd0) ifq_entry0_valid_cycles <= ifq_entry0_valid_cycles + 64'd1;
            if (if_stat_queue_count == 2'd2) ifq_entry1_valid_cycles <= ifq_entry1_valid_cycles + 64'd1;
            if (if_stat_queue_count == 2'd2) ifq_both_valid_cycles <= ifq_both_valid_cycles + 64'd1;
            if (if_stat_queue_count == 2'd1) ifq_single_valid_cycles <= ifq_single_valid_cycles + 64'd1;

            if (stat_exmem_skid_enqueue_fire) begin
                if (es_to_ms_valid) begin
                    exmem_skid_eff_enqueue_when_ex_would_stall <=
                        exmem_skid_eff_enqueue_when_ex_would_stall + 64'd1;
                end
                if (es_allowin) begin
                    exmem_skid_eff_enqueue_and_ex_allowin <=
                        exmem_skid_eff_enqueue_and_ex_allowin + 64'd1;
                end else begin
                    exmem_skid_eff_enqueue_but_upstream_still_stall <=
                        exmem_skid_eff_enqueue_but_upstream_still_stall + 64'd1;
                    if (stat_exmem_skid_full_stall != 64'd0 &&
                            stat_exmem_skid_valid) begin
                        exmem_skid_eff_no_gain_skid_full <=
                            exmem_skid_eff_no_gain_skid_full + 64'd1;
                    end else if (stat_exmem_skid_mem_wait || dbus_resp_wait_now ||
                            ms_stage_block_resp_phase || ms_stage_block_resp_load ||
                            ms_stage_block_resp_store) begin
                        exmem_skid_eff_no_gain_mem_response_wait <=
                            exmem_skid_eff_no_gain_mem_response_wait + 64'd1;
                    end else if (!ds_allowin || !if_stat_fs_pop ||
                            load_use_now || raw_hazard_now || csr_special_now) begin
                        exmem_skid_eff_no_gain_next_inst_blocked <=
                            exmem_skid_eff_no_gain_next_inst_blocked + 64'd1;
                    end else if (stat_exmem_skid_dequeue_to_mreq_fire) begin
                        exmem_skid_eff_no_gain_dequeue_same_as_old_path <=
                            exmem_skid_eff_no_gain_dequeue_same_as_old_path + 64'd1;
                    end else begin
                        exmem_skid_eff_unknown <= exmem_skid_eff_unknown + 64'd1;
                    end
                end
                if (ds_allowin) begin
                    exmem_skid_eff_enqueue_and_id_allowin <=
                        exmem_skid_eff_enqueue_and_id_allowin + 64'd1;
                end
            end
            if (prev_exmem_skid_enqueue && if_stat_fs_pop) begin
                exmem_skid_eff_enqueue_and_if_pop_next <=
                    exmem_skid_eff_enqueue_and_if_pop_next + 64'd1;
            end

            if (ifq_push_block_now) begin
                if (redirect_or_flush_now) begin
                    ifq_block_redirect <= ifq_block_redirect + 64'd1;
                end else if (epoch_recovery_now || if_pipe_stat_resp_stale ||
                        if_stat_resp_drop || if_stat_drop_resp) begin
                    ifq_block_epoch_drop <= ifq_block_epoch_drop + 64'd1;
                end else if (if_stat_fs_pop) begin
                    ifq_block_full_with_pop_same_cycle <= ifq_block_full_with_pop_same_cycle + 64'd1;
                end else if (load_use_now) begin
                    ifq_block_load_use <= ifq_block_load_use + 64'd1;
                end else if (raw_hazard_now) begin
                    ifq_block_raw_hazard <= ifq_block_raw_hazard + 64'd1;
                end else if (csr_special_now) begin
                    ifq_block_csr_special <= ifq_block_csr_special + 64'd1;
                end else if (mem_lsu_wait_now) begin
                    ifq_block_mem_lsu <= ifq_block_mem_lsu + 64'd1;
                end else if (backend_stall_now) begin
                    ifq_block_backend_stall <= ifq_block_backend_stall + 64'd1;
                end else if (!ds_allowin) begin
                    ifq_block_full_id_not_ready <= ifq_block_full_id_not_ready + 64'd1;
                end else if (ds_allowin) begin
                    ifq_block_full_id_ready <= ifq_block_full_id_ready + 64'd1;
                end else if (!if_stat_fs_pop) begin
                    ifq_block_full_no_pop <= ifq_block_full_no_pop + 64'd1;
                end else begin
                    ifq_block_unknown <= ifq_block_unknown + 64'd1;
                end
            end

            if (ibus_resp_ready && !ibus_resp_valid) frontend_if_pipe_no_resp <= frontend_if_pipe_no_resp + 64'd1;
            if (ibus_req_valid && !ibus_req_ready) frontend_backpressure <= frontend_backpressure + 64'd1;
            if ((if_pipe_epoch_drop_count != prev_if_pipe_epoch_drop_count) ||
                    redirect_clear_valid || stop_clear_valid) begin
                frontend_epoch_drop_recovery <= frontend_epoch_drop_recovery + 64'd1;
            end
            if (icache_miss_wait_cycle != prev_icache_miss_wait_cycle) begin
                frontend_icache_miss_wait_seen <= frontend_icache_miss_wait_seen + 64'd1;
            end
            if (icache_req_wait_cycle != prev_icache_req_wait_cycle) begin
                frontend_icache_refill_wait_seen <= frontend_icache_refill_wait_seen + 64'd1;
            end

            if (ms_stage_block_req_load) mem_load_req_wait <= mem_load_req_wait + 64'd1;
            if (ms_stage_block_req_store) mem_store_req_wait <= mem_store_req_wait + 64'd1;
            if (ms_stage_block_resp_load) mem_load_resp_wait <= mem_load_resp_wait + 64'd1;
            if (ms_stage_block_resp_store) mem_store_resp_wait <= mem_store_resp_wait + 64'd1;
            if (ms_stage_block_load) mem_load_wait <= mem_load_wait + 64'd1;
            if (ms_stage_block_store) mem_store_wait <= mem_store_wait + 64'd1;
            if (ms_stage_block_resp_phase) mem_single_outstanding_wait <= mem_single_outstanding_wait + 64'd1;
            if (ms_stat_mreq_valid && ms_stat_mreq_is_load && ms_stat_mreq_need_mem) begin
                lrp_load_req_total <= lrp_load_req_total + 64'd1;
            end
            if (ms_stat_load_req_fire) begin
                lrp_load_req_fire <= lrp_load_req_fire + 64'd1;
            end
            if (ms_stat_mresp_valid && ms_stat_mresp_is_load) begin
                lrp_load_resp_total <= lrp_load_resp_total + 64'd1;
            end
            if (ms_stat_load_resp_fire) begin
                lrp_load_resp_fire <= lrp_load_resp_fire + 64'd1;
            end
            if (load_resp_wait_path_now) begin
                lrp_wait_total <= lrp_wait_total + 64'd1;
                if (load_resp_uncached_now) begin
                    lrp_wait_uncached <= lrp_wait_uncached + 64'd1;
                end else if (load_sbuf_conflict_now) begin
                    lrp_wait_sbuf_conflict <= lrp_wait_sbuf_conflict + 64'd1;
                end else if (load_sbuf_drain_now) begin
                    lrp_wait_sbuf_drain <= lrp_wait_sbuf_drain + 64'd1;
                end else if (load_dcache_miss_like_now) begin
                    lrp_wait_dcache_miss <= lrp_wait_dcache_miss + 64'd1;
                end else if (load_dcache_hit_like_now) begin
                    lrp_wait_dcache_hit <= lrp_wait_dcache_hit + 64'd1;
                end else if (load_resp_lsu_busy_now) begin
                    lrp_wait_lsu_busy <= lrp_wait_lsu_busy + 64'd1;
                end else if (load_resp_mem_stage_block_now) begin
                    lrp_wait_mem_stage_block <= lrp_wait_mem_stage_block + 64'd1;
                end else if (load_resp_wb_block_now) begin
                    lrp_wait_wb_block <= lrp_wait_wb_block + 64'd1;
                end else begin
                    lrp_wait_other <= lrp_wait_other + 64'd1;
                end
            end
            if (ms_stat_mreq_valid && ms_stat_mreq_is_load && ms_stat_mreq_need_mem) begin
                mem_v2_load_req_total <= mem_v2_load_req_total + 64'd1;
            end
            if (ms_stat_load_req_fire) mem_v2_load_req_fire <= mem_v2_load_req_fire + 64'd1;
            if (ms_stat_load_req_fire) lsu_pipe_bridge_load_via <= lsu_pipe_bridge_load_via + 64'd1;
            if (load_bypass_dep_now) begin
                lsu_load_bypass_candidate <= lsu_load_bypass_candidate + 64'd1;
                late_bypass_total_load_dep <= late_bypass_total_load_dep + 64'd1;
                late_bypass_distance1 <= late_bypass_distance1 + 64'd1;
                if (load_bypass_release_now) begin
                    lsu_load_bypass_release_id_stall <= lsu_load_bypass_release_id_stall + 64'd1;
                    late_bypass_safe <= late_bypass_safe + 64'd1;
                    late_bypass_resp_ready_before_ex <= late_bypass_resp_ready_before_ex + 64'd1;
                    late_bypass_resp_ready_same_cycle_ex <= late_bypass_resp_ready_same_cycle_ex + 64'd1;
                    late_bypass_signext_ready_before_ex <= late_bypass_signext_ready_before_ex + 64'd1;
                end else begin
                    late_bypass_unknown <= late_bypass_unknown + 64'd1;
                    if (!ms_stat_load_visible) begin
                        lsu_load_bypass_blocked_not_load <= lsu_load_bypass_blocked_not_load + 64'd1;
                    end else if (ms_stat_load_fault) begin
                        lsu_load_bypass_blocked_fault <= lsu_load_bypass_blocked_fault + 64'd1;
                    end else if (ms_stat_load_killed) begin
                        lsu_load_bypass_blocked_kill <= lsu_load_bypass_blocked_kill + 64'd1;
                    end else if (ms_stat_load_uncached) begin
                        lsu_load_bypass_blocked_uncached <= lsu_load_bypass_blocked_uncached + 64'd1;
                    end else if (ms_stat_load_split_or_misaligned || !ms_stat_load_aligned) begin
                        lsu_load_bypass_blocked_misaligned <= lsu_load_bypass_blocked_misaligned + 64'd1;
                    end else if (ms_stat_load_atomic) begin
                        lsu_load_bypass_blocked_atomic <= lsu_load_bypass_blocked_atomic + 64'd1;
                    end else if (ms_stat_load_store_block) begin
                        lsu_load_bypass_blocked_store_buffer <= lsu_load_bypass_blocked_store_buffer + 64'd1;
                    end else if (!ms_stat_load_data_ready) begin
                        lsu_load_bypass_blocked_resp_not_ready <= lsu_load_bypass_blocked_resp_not_ready + 64'd1;
                    end else if (!ms_stat_load_signext_data_ready) begin
                        lsu_load_bypass_blocked_signext_not_ready <= lsu_load_bypass_blocked_signext_not_ready + 64'd1;
                    end else begin
                        lsu_load_bypass_blocked_resp_not_ready <= lsu_load_bypass_blocked_resp_not_ready + 64'd1;
                    end
                end
            end
            if (mem_v2_load_resp_wait_now) begin
                mem_v2_load_resp_wait <= mem_v2_load_resp_wait + 64'd1;
                if (ms_stat_load_uncached || dcache_uncached_delta) begin
                    mem_v2_load_resp_wait_uncached <= mem_v2_load_resp_wait_uncached + 64'd1;
                end else if (mem_v2_store_blocking_load_now) begin
                    mem_v2_load_resp_wait_blocked_by_store <=
                        mem_v2_load_resp_wait_blocked_by_store + 64'd1;
                end else if (mem_v2_single_now) begin
                    mem_v2_load_resp_wait_blocked_by_single <=
                        mem_v2_load_resp_wait_blocked_by_single + 64'd1;
                end else if (dcache_miss_delta || ms_stage_block_req_load) begin
                    mem_v2_load_resp_wait_dcache_miss <=
                        mem_v2_load_resp_wait_dcache_miss + 64'd1;
                end else if (ms_stat_load_resp_valid || ms_stat_load_data_ready ||
                        (ms_stage_block_resp_load && !dcache_miss_delta)) begin
                    mem_v2_load_resp_wait_dcache_hit <=
                        mem_v2_load_resp_wait_dcache_hit + 64'd1;
                end else begin
                    mem_v2_load_resp_wait_other <= mem_v2_load_resp_wait_other + 64'd1;
                end
            end
            if (ms_stat_mreq_valid && ms_stat_mreq_is_store && ms_stat_mreq_need_mem) begin
                mem_v2_store_req_total <= mem_v2_store_req_total + 64'd1;
            end
            if (ms_stat_store_req_fire) mem_v2_store_req_fire <= mem_v2_store_req_fire + 64'd1;
            if (ms_stat_store_req_fire) lsu_pipe_bridge_store_via <= lsu_pipe_bridge_store_via + 64'd1;
            if (ms_stat_mreq_fire && ms_stat_mreq_is_atomic) begin
                lsu_pipe_bridge_atomic_via <= lsu_pipe_bridge_atomic_via + 64'd1;
            end
            if (ms_stat_store_req_fire) begin
                if (mem_v2_store_miss_like_now) mem_v2_store_miss_total <= mem_v2_store_miss_total + 64'd1;
                else mem_v2_store_hit_total <= mem_v2_store_hit_total + 64'd1;
            end
            if (mem_v2_store_resp_wait_now) begin
                mem_v2_store_resp_wait <= mem_v2_store_resp_wait + 64'd1;
                if (ms_stat_store_uncached || dcache_uncached_delta) begin
                    mem_v2_store_uncached_wait <= mem_v2_store_uncached_wait + 64'd1;
                end else if (dcache_writeback_delta || ms_stat_store_resp_wait) begin
                    mem_v2_store_write_resp_wait <= mem_v2_store_write_resp_wait + 64'd1;
                end else if (dcache_miss_delta || ms_stage_block_req_store) begin
                    mem_v2_store_miss_resp_wait <= mem_v2_store_miss_resp_wait + 64'd1;
                end else if (ms_stat_store_resp_valid) begin
                    mem_v2_store_hit_resp_wait <= mem_v2_store_hit_resp_wait + 64'd1;
                end else if (ms_stage_block_resp_store) begin
                    mem_v2_store_refill_wait <= mem_v2_store_refill_wait + 64'd1;
                end else begin
                    mem_v2_store_other <= mem_v2_store_other + 64'd1;
                end
            end
            if (mem_v2_single_now) begin
                mem_v2_single_outstanding_wait <= mem_v2_single_outstanding_wait + 64'd1;
                if (ms_stat_uncached_wait || dcache_uncached_delta) begin
                    mem_v2_single_uncached <= mem_v2_single_uncached + 64'd1;
                end else if (ms_stat_mreq_is_load && ms_stat_mresp_is_load) begin
                    mem_v2_single_load_blocked_by_load <=
                        mem_v2_single_load_blocked_by_load + 64'd1;
                end else if (ms_stat_mreq_is_load && ms_stat_mresp_is_store) begin
                    mem_v2_single_load_blocked_by_store <=
                        mem_v2_single_load_blocked_by_store + 64'd1;
                end else if (ms_stat_mreq_is_store && ms_stat_mresp_is_load) begin
                    mem_v2_single_store_blocked_by_load <=
                        mem_v2_single_store_blocked_by_load + 64'd1;
                end else if (ms_stat_mreq_is_store && ms_stat_mresp_is_store) begin
                    mem_v2_single_store_blocked_by_store <=
                        mem_v2_single_store_blocked_by_store + 64'd1;
                end else begin
                    mem_v2_single_other <= mem_v2_single_other + 64'd1;
                end
            end
            if (mem_v2_single_now) begin
                lsu_so2_total <= lsu_so2_total + 64'd1;
                if (ms_stat_uncached_wait || dcache_uncached_delta) begin
                    lsu_so2_load_blocked_by_uncached <=
                        lsu_so2_load_blocked_by_uncached + 64'd1;
                end else if (load_sbuf_drain_now && ms_stat_mreq_is_load) begin
                    lsu_so2_load_blocked_by_sbuf_drain <=
                        lsu_so2_load_blocked_by_sbuf_drain + 64'd1;
                end else if (dcache_miss_delta && ms_stat_mreq_is_load) begin
                    lsu_so2_load_blocked_by_dcache_refill <=
                        lsu_so2_load_blocked_by_dcache_refill + 64'd1;
                end else if (ms_stat_mreq_is_load && ms_stat_mresp_is_load) begin
                    lsu_so2_load_blocked_by_load <=
                        lsu_so2_load_blocked_by_load + 64'd1;
                end else if (ms_stat_mreq_is_load && ms_stat_mresp_is_store) begin
                    lsu_so2_load_blocked_by_store <=
                        lsu_so2_load_blocked_by_store + 64'd1;
                end else if (ms_stat_mreq_is_store && ms_stat_mresp_is_load) begin
                    lsu_so2_store_blocked_by_load <=
                        lsu_so2_store_blocked_by_load + 64'd1;
                end else if (ms_stat_mreq_is_store && ms_stat_mresp_is_store) begin
                    lsu_so2_store_blocked_by_store <=
                        lsu_so2_store_blocked_by_store + 64'd1;
                end else begin
                    lsu_so2_other <= lsu_so2_other + 64'd1;
                end
            end
            if (mem_v2_store_event_now) begin
                storebuf_store_total <= storebuf_store_total + 64'd1;
                if (storebuf_safe_now) begin
                    storebuf_safe_candidate <= storebuf_safe_candidate + 64'd1;
                    if (mem_v2_store_miss_like_now) begin
                        storebuf_aligned_cached_miss <= storebuf_aligned_cached_miss + 64'd1;
                    end else begin
                        storebuf_aligned_cached_hit <= storebuf_aligned_cached_hit + 64'd1;
                    end
                end else begin
                    storebuf_not_safe <= storebuf_not_safe + 64'd1;
                    if (ms_stat_store_uncached || dcache_uncached_delta) storebuf_uncached_or_mmio <= storebuf_uncached_or_mmio + 64'd1;
                    else if (ms_stat_store_fault) storebuf_fault_or_page_fault <= storebuf_fault_or_page_fault + 64'd1;
                    else if (ms_stat_store_split_or_misaligned) storebuf_misaligned_or_cross_page <= storebuf_misaligned_or_cross_page + 64'd1;
                    else if (ms_stat_store_atomic) storebuf_atomic_or_lrsc <= storebuf_atomic_or_lrsc + 64'd1;
                    else if (fencei_start || vm_flush_start || fencei_maint_active) storebuf_before_fence <= storebuf_before_fence + 64'd1;
                    else if (ms_stat_store_killed || trap_flush_now) storebuf_killed_or_exception <= storebuf_killed_or_exception + 64'd1;
                    else storebuf_unknown <= storebuf_unknown + 64'd1;
                end
            end
            if (dcache_proto_resp_valid_wait_ready_now) begin
                dcache_proto_mem_stage_wait_resp_ready <=
                    dcache_proto_mem_stage_wait_resp_ready + 64'd1;
                if (ms_stat_mresp_is_load) begin
                    dcache_proto_load_resp_valid_wait_ready <=
                        dcache_proto_load_resp_valid_wait_ready + 64'd1;
                end else if (ms_stat_mresp_is_store) begin
                    dcache_proto_store_resp_valid_wait_ready <=
                        dcache_proto_store_resp_valid_wait_ready + 64'd1;
                end
            end
            if (wb_block_now) dcache_proto_wb_stage_backpressure <= dcache_proto_wb_stage_backpressure + 64'd1;
            if (dcache_proto_overhead_now) begin
                dcache_proto_resp_protocol_overhead <=
                    dcache_proto_resp_protocol_overhead + 64'd1;
            end
            if (store_buffer_drain_wait_delta) begin
                if (ms_stage_block_load || ms_stage_block_req_load ||
                        ms_stage_block_resp_load ||
                        (ms_stat_mreq_is_load && ms_stat_mreq_blocked_by_resp)) begin
                    sbuf_drain_blocks_load <= sbuf_drain_blocks_load + 64'd1;
                end else if (ms_stage_block_req_store || ms_stat_store_buffer_safe ||
                        ms_stat_store_visible) begin
                    sbuf_drain_blocks_store_enqueue <=
                        sbuf_drain_blocks_store_enqueue + 64'd1;
                end else if (ms_stage_block || !ms_allowin || ms_to_ws_valid) begin
                    sbuf_drain_blocks_pipeline_mem <=
                        sbuf_drain_blocks_pipeline_mem + 64'd1;
                end else if (ptw_wait_now || if_pipe_req_not_ready_now ||
                        if_pipe_no_resp_now || if_stall) begin
                    sbuf_drain_blocks_icache_or_ptw <=
                        sbuf_drain_blocks_icache_or_ptw + 64'd1;
                end else if (fs_to_ds_valid || ds_to_es_valid || es_to_ms_valid ||
                        es_valid || ms_valid || ws_valid) begin
                    sbuf_drain_overlap_with_useful_pipeline <=
                        sbuf_drain_overlap_with_useful_pipeline + 64'd1;
                end else begin
                    sbuf_drain_background_only <=
                        sbuf_drain_background_only + 64'd1;
                end
            end
            if (!dcache_proto_track_valid && ms_stat_mreq_fire &&
                    !ms_stat_mreq_fault && !ms_stat_mreq_misaligned &&
                    !ms_stat_mreq_split && !ms_stat_mreq_is_atomic) begin
                dcache_proto_track_valid <= 1'b1;
                dcache_proto_track_store <= ms_stat_mreq_is_store;
                dcache_proto_track_hit <= !dcache_miss_delta;
                dcache_proto_current_latency <= 64'd1;
            end else if (dcache_proto_track_valid) begin
                dcache_proto_current_latency <= dcache_proto_current_latency + 64'd1;
                dcache_proto_track_hit <= dcache_proto_hit_still_now;
                if (ms_stat_mresp_resp_fire) begin
                    if (dcache_proto_track_store && dcache_proto_hit_still_now) begin
                        dcache_proto_store_hit_latency_count <=
                            dcache_proto_store_hit_latency_count + 64'd1;
                        dcache_proto_store_hit_latency_sum <=
                            dcache_proto_store_hit_latency_sum + dcache_proto_current_latency;
                        if (dcache_proto_current_latency > dcache_proto_store_hit_latency_max) begin
                            dcache_proto_store_hit_latency_max <= dcache_proto_current_latency;
                        end
                    end else if (!dcache_proto_track_store && dcache_proto_hit_still_now) begin
                        dcache_proto_load_hit_latency_count <=
                            dcache_proto_load_hit_latency_count + 64'd1;
                        dcache_proto_load_hit_latency_sum <=
                            dcache_proto_load_hit_latency_sum + dcache_proto_current_latency;
                        if (dcache_proto_current_latency > dcache_proto_load_hit_latency_max) begin
                            dcache_proto_load_hit_latency_max <= dcache_proto_current_latency;
                        end
                        dclh_total <= dclh_total + 64'd1;
                        dclh_latency_sum <=
                            dclh_latency_sum + dcache_proto_current_latency;
                        if (dcache_proto_current_latency > dclh_latency_max) begin
                            dclh_latency_max <= dcache_proto_current_latency;
                        end
                        if (dcache_proto_current_latency <= 64'd1) begin
                            dclh_latency_1 <= dclh_latency_1 + 64'd1;
                        end else if (dcache_proto_current_latency == 64'd2) begin
                            dclh_latency_2 <= dclh_latency_2 + 64'd1;
                            dclh_tag_lookup_wait <= dclh_tag_lookup_wait + 64'd1;
                        end else if (dcache_proto_current_latency == 64'd3) begin
                            dclh_latency_3 <= dclh_latency_3 + 64'd1;
                            dclh_tag_lookup_wait <= dclh_tag_lookup_wait + 64'd1;
                            dclh_data_array_wait <= dclh_data_array_wait + 64'd1;
                        end else begin
                            dclh_latency_gt3 <= dclh_latency_gt3 + 64'd1;
                            dclh_tag_lookup_wait <= dclh_tag_lookup_wait + 64'd1;
                            dclh_data_array_wait <= dclh_data_array_wait + 64'd1;
                            dclh_response_reg_wait <=
                                dclh_response_reg_wait +
                                (dcache_proto_current_latency - 64'd3);
                        end
                    end
                    dcache_proto_track_valid <= 1'b0;
                    dcache_proto_current_latency <= 64'd0;
                end
            end
            if (mem_backend_wait_now) begin
                if (ms_stat_uncached_wait || dcache_uncached_delta) begin
                    mem_backend_uncached_wait <= mem_backend_uncached_wait + 64'd1;
                end else if (ms_stat_writeback_wait || dcache_writeback_delta) begin
                    mem_backend_writeback_wait <= mem_backend_writeback_wait + 64'd1;
                end else if (ms_stat_store_resp_wait) begin
                    mem_backend_store_write_resp_wait <=
                        mem_backend_store_write_resp_wait + 64'd1;
                end else if (ms_stage_block_store || ms_stage_block_req_store ||
                        ms_stage_block_resp_store) begin
                    mem_backend_store_miss_wait <= mem_backend_store_miss_wait + 64'd1;
                end else if (ms_stage_block_resp_load || dbus_resp_wait_now) begin
                    mem_backend_load_response_wait <=
                        mem_backend_load_response_wait + 64'd1;
                end else if (ms_stage_block_resp_store) begin
                    mem_backend_store_response_wait <=
                        mem_backend_store_response_wait + 64'd1;
                end else if (dbus_req_wait_now || ms_stage_block_req_phase) begin
                    mem_backend_dcache_req_wait <= mem_backend_dcache_req_wait + 64'd1;
                end else if (ms_stat_single_outstanding_wait || ms_stage_block_resp_phase) begin
                    mem_backend_single_outstanding_wait <=
                        mem_backend_single_outstanding_wait + 64'd1;
                end else if (dcache_miss_delta) begin
                    mem_backend_dcache_miss_wait <= mem_backend_dcache_miss_wait + 64'd1;
                end else begin
                    mem_backend_other <= mem_backend_other + 64'd1;
                end
            end
            if (hazard_event_now) begin
                hazard_load_use_total <= hazard_load_use_total + (load_use_now ? 64'd1 : 64'd0);
                hazard_raw_total <= hazard_raw_total + (raw_hazard_now ? 64'd1 : 64'd0);
                hazard_csr_total <= hazard_csr_total + (csr_special_now ? 64'd1 : 64'd0);
                hazard_mem_lsu_total <= hazard_mem_lsu_total + (mem_lsu_wait_now ? 64'd1 : 64'd0);
                if (load_use_now || raw_hazard_now) begin
                    if (hazard_only_rs1_now) hazard_rs1 <= hazard_rs1 + 64'd1;
                    if (hazard_only_rs2_now) hazard_rs2 <= hazard_rs2 + 64'd1;
                    if (hazard_both_now) hazard_both <= hazard_both + 64'd1;
                    if (!hazard_rs1_now && !hazard_rs2_now) begin
                        hazard_operand_unknown <= hazard_operand_unknown + 64'd1;
                    end
                end

                if (load_use_path_event_now) begin
                    if (load_sbuf_conflict_now || load_sbuf_drain_now) begin
                        loaduse_path_wait_store_buffer <=
                            loaduse_path_wait_store_buffer + 64'd1;
                    end else if (load_dcache_miss_like_now || dcache_miss_delta) begin
                        loaduse_path_wait_dcache_miss <=
                            loaduse_path_wait_dcache_miss + 64'd1;
                    end else if (ms_stat_load_visible &&
                            !ms_stat_load_signext_data_ready &&
                            !ms_stat_load_fault && !ms_stat_load_uncached) begin
                        loaduse_path_wait_signext <=
                            loaduse_path_wait_signext + 64'd1;
                    end else if (ms_stat_load_to_wb_valid) begin
                        loaduse_path_wait_memwb <=
                            loaduse_path_wait_memwb + 64'd1;
                    end else if (match_wb_now && ws_is_load_now) begin
                        loaduse_path_wait_wb <=
                            loaduse_path_wait_wb + 64'd1;
                    end else if (load_resp_lsu_busy_now ||
                            ms_stage_block_load || ms_stage_block_resp_load ||
                            ms_stage_block_req_load) begin
                        loaduse_path_wait_lsu_pending <=
                            loaduse_path_wait_lsu_pending + 64'd1;
                    end else if (load_dcache_hit_like_now ||
                            ms_stat_load_resp_valid ||
                            ms_stat_load_data_ready) begin
                        loaduse_path_wait_dcache_hit <=
                            loaduse_path_wait_dcache_hit + 64'd1;
                    end else begin
                        loaduse_path_wait_other <=
                            loaduse_path_wait_other + 64'd1;
                    end
                end

                if ((load_use_now || raw_hazard_now) &&
                        load_candidate_matches_load_now) begin
                    lbp2_candidate_total <= lbp2_candidate_total + 64'd1;
                    if (lbp2_safe_dcache_now) begin
                        lbp2_safe_dcache_resp_to_ex <=
                            lbp2_safe_dcache_resp_to_ex + 64'd1;
                    end else if (lbp2_safe_mem_stage_now) begin
                        lbp2_safe_mem_stage_to_ex <=
                            lbp2_safe_mem_stage_to_ex + 64'd1;
                    end else if (lbp2_safe_memwb_now) begin
                        lbp2_safe_memwb_to_ex <=
                            lbp2_safe_memwb_to_ex + 64'd1;
                    end else if (lbp2_safe_wb_now) begin
                        lbp2_safe_wb_to_ex <= lbp2_safe_wb_to_ex + 64'd1;
                    end else if (ms_stat_load_fault || ms_stat_mreq_fault ||
                            ms_stat_mresp_fault) begin
                        lbp2_blocked_exception_or_fault <=
                            lbp2_blocked_exception_or_fault + 64'd1;
                    end else if (ms_stat_load_uncached || ms_stat_uncached_wait ||
                            dcache_uncached_delta) begin
                        lbp2_blocked_uncached <=
                            lbp2_blocked_uncached + 64'd1;
                    end else if (ms_stat_load_killed || trap_flush_now ||
                            redirect_flush_valid) begin
                        lbp2_blocked_kill_or_flush <=
                            lbp2_blocked_kill_or_flush + 64'd1;
                    end else if (load_sbuf_conflict_now || load_sbuf_drain_now) begin
                        lbp2_blocked_store_buffer_conflict <=
                            lbp2_blocked_store_buffer_conflict + 64'd1;
                    end else if (ms_stat_load_visible &&
                            !ms_stat_load_signext_data_ready) begin
                        lbp2_blocked_signext_not_ready <=
                            lbp2_blocked_signext_not_ready + 64'd1;
                    end else if (ms_stat_load_lsu_pending ||
                            !ms_stat_load_resp_valid ||
                            !ms_stat_load_data_ready) begin
                        lbp2_blocked_resp_not_ready <=
                            lbp2_blocked_resp_not_ready + 64'd1;
                    end else if (!ms_stat_load_visible && !match_wb_now) begin
                        lbp2_blocked_timing_unknown <=
                            lbp2_blocked_timing_unknown + 64'd1;
                    end else begin
                        lbp2_unknown <= lbp2_unknown + 64'd1;
                    end
                end

                if (load_use_now) begin
                    if (match_ex_now) begin
                        load_use_wait_mem <= load_use_wait_mem + 64'd1;
                        if (ex_is_load_now) begin
                            count_load_pending_not_bypassable();
                            hazard_load_miss <= hazard_load_miss + 64'd1;
                            hazard_lsu_pending <= hazard_lsu_pending + 64'd1;
                        end else if (es_stat_is_mdu) begin
                            fwd_muldiv_not_bypassable <= fwd_muldiv_not_bypassable + 64'd1;
                            hazard_muldiv <= hazard_muldiv + 64'd1;
                            mdu_consumer_wait_cycles <= mdu_consumer_wait_cycles + 64'd1;
                            if (es_stat_fast_mul) begin
                                fast_mul_stall_wait_ready <= fast_mul_stall_wait_ready + 64'd1;
                            end
                            if (mdu_op_mul) begin
                                mdu_mul_consumer_stall <= mdu_mul_consumer_stall + 64'd1;
                            end
                        end else if (ex_is_alu_now) begin
                            fwd_ex_alu_to_ex <= fwd_ex_alu_to_ex + 64'd1;
                            hazard_ex_alu <= hazard_ex_alu + 64'd1;
                        end else if (ex_is_csr_now) begin
                            fwd_csr_not_bypassable <= fwd_csr_not_bypassable + 64'd1;
                            hazard_csr <= hazard_csr + 64'd1;
                        end else if (ex_is_store_or_mem_order_now) begin
                            fwd_memory_order_not_bypassable <= fwd_memory_order_not_bypassable + 64'd1;
                            hazard_store <= hazard_store + 64'd1;
                        end else begin
                            fwd_unknown <= fwd_unknown + 64'd1;
                            hazard_unknown <= hazard_unknown + 64'd1;
                        end
                    end else if (ms_is_load_now && ms_load_ready_now) begin
                        load_use_load_hit <= load_use_load_hit + 64'd1;
                        load_use_same_cycle_resp_possible <= load_use_same_cycle_resp_possible + 64'd1;
                        fwd_load_hit_to_ex <= fwd_load_hit_to_ex + 64'd1;
                        hazard_load_hit <= hazard_load_hit + 64'd1;
                    end else if (ms_is_load_now && ms_load_miss_now) begin
                        load_use_load_miss <= load_use_load_miss + 64'd1;
                        count_load_pending_not_bypassable();
                        hazard_load_miss <= hazard_load_miss + 64'd1;
                        hazard_lsu_pending <= hazard_lsu_pending + 64'd1;
                    end else if (match_ms_now && ms_is_load_now) begin
                        load_use_wait_mem <= load_use_wait_mem + 64'd1;
                        count_load_pending_not_bypassable();
                        hazard_load_miss <= hazard_load_miss + 64'd1;
                        hazard_lsu_pending <= hazard_lsu_pending + 64'd1;
                    end else if (match_ms_now && ms_is_alu_now) begin
                        load_use_wait_mem <= load_use_wait_mem + 64'd1;
                        fwd_mem_alu_to_ex <= fwd_mem_alu_to_ex + 64'd1;
                        hazard_mem_alu <= hazard_mem_alu + 64'd1;
                    end else if (match_ms_now && ms_is_csr_now) begin
                        load_use_wait_mem <= load_use_wait_mem + 64'd1;
                        fwd_csr_not_bypassable <= fwd_csr_not_bypassable + 64'd1;
                        hazard_csr <= hazard_csr + 64'd1;
                    end else if (ms_stage_block_resp_phase || ms_stage_block_req_phase ||
                            ms_stage_block_load) begin
                        load_use_lsu_busy <= load_use_lsu_busy + 64'd1;
                        count_load_pending_not_bypassable();
                        hazard_load_miss <= hazard_load_miss + 64'd1;
                        hazard_lsu_pending <= hazard_lsu_pending + 64'd1;
                    end else if (match_hidden_now) begin
                        load_use_wait_wb <= load_use_wait_wb + 64'd1;
                        if (hidden_is_load_now) begin
                            count_load_pending_not_bypassable();
                            hazard_load_miss <= hazard_load_miss + 64'd1;
                        end else if (hidden_is_csr_now) begin
                            fwd_csr_not_bypassable <= fwd_csr_not_bypassable + 64'd1;
                            hazard_csr <= hazard_csr + 64'd1;
                        end else if (hidden_is_mem_order_now) begin
                            fwd_memory_order_not_bypassable <= fwd_memory_order_not_bypassable + 64'd1;
                            hazard_store <= hazard_store + 64'd1;
                        end else begin
                            hazard_lsu_pending <= hazard_lsu_pending + 64'd1;
                        end
                    end else if (ws_stat_mem_op != 3'b000 || ws_is_load_now) begin
                        load_use_wait_wb <= load_use_wait_wb + 64'd1;
                        hazard_load_hit <= hazard_load_hit + 64'd1;
                    end else if (match_wb_now && ws_is_alu_now) begin
                        load_use_wait_wb <= load_use_wait_wb + 64'd1;
                        fwd_wb_to_ex <= fwd_wb_to_ex + 64'd1;
                        hazard_wb <= hazard_wb + 64'd1;
                    end else if (match_wb_now && ws_is_csr_now) begin
                        load_use_wait_wb <= load_use_wait_wb + 64'd1;
                        fwd_csr_not_bypassable <= fwd_csr_not_bypassable + 64'd1;
                        hazard_csr <= hazard_csr + 64'd1;
                    end else begin
                        load_use_unknown <= load_use_unknown + 64'd1;
                    end
                end

                if (raw_hazard_now) begin
                    if (match_ex_now) begin
                        if (es_stat_is_mdu) begin
                            raw_muldiv <= raw_muldiv + 64'd1;
                            fwd_muldiv_not_bypassable <= fwd_muldiv_not_bypassable + 64'd1;
                            hazard_muldiv <= hazard_muldiv + 64'd1;
                            mdu_consumer_wait_cycles <= mdu_consumer_wait_cycles + 64'd1;
                            if (es_stat_fast_mul) begin
                                fast_mul_stall_wait_ready <= fast_mul_stall_wait_ready + 64'd1;
                            end
                            if (mdu_op_mul) begin
                                mdu_mul_consumer_stall <= mdu_mul_consumer_stall + 64'd1;
                            end
                        end else if (ex_is_alu_now) begin
                            raw_alu_ex <= raw_alu_ex + 64'd1;
                            fwd_ex_alu_to_ex <= fwd_ex_alu_to_ex + 64'd1;
                            hazard_ex_alu <= hazard_ex_alu + 64'd1;
                        end else if (ex_is_load_now) begin
                            raw_load_mem <= raw_load_mem + 64'd1;
                            count_load_pending_not_bypassable();
                            hazard_load_miss <= hazard_load_miss + 64'd1;
                        end else if (ex_is_csr_now) begin
                            raw_csr <= raw_csr + 64'd1;
                            fwd_csr_not_bypassable <= fwd_csr_not_bypassable + 64'd1;
                            hazard_csr <= hazard_csr + 64'd1;
                        end else if (ex_is_store_or_mem_order_now) begin
                            raw_hidden <= raw_hidden + 64'd1;
                            fwd_memory_order_not_bypassable <= fwd_memory_order_not_bypassable + 64'd1;
                            hazard_store <= hazard_store + 64'd1;
                        end else begin
                            raw_unknown <= raw_unknown + 64'd1;
                        end
                    end else if (match_ms_now) begin
                        if (ms_is_alu_now) begin
                            raw_alu_mem <= raw_alu_mem + 64'd1;
                            fwd_mem_alu_to_ex <= fwd_mem_alu_to_ex + 64'd1;
                            hazard_mem_alu <= hazard_mem_alu + 64'd1;
                        end else if (ms_is_load_now) begin
                            raw_load_mem <= raw_load_mem + 64'd1;
                            count_load_pending_not_bypassable();
                            hazard_load_miss <= hazard_load_miss + 64'd1;
                        end else if (ms_is_csr_now) begin
                            raw_csr <= raw_csr + 64'd1;
                            fwd_csr_not_bypassable <= fwd_csr_not_bypassable + 64'd1;
                            hazard_csr <= hazard_csr + 64'd1;
                        end else begin
                            raw_unknown <= raw_unknown + 64'd1;
                        end
                    end else if (match_hidden_now) begin
                        if (hidden_is_load_now) begin
                            raw_load_wb <= raw_load_wb + 64'd1;
                            count_load_pending_not_bypassable();
                            hazard_load_miss <= hazard_load_miss + 64'd1;
                        end else if (hidden_is_csr_now) begin
                            raw_csr <= raw_csr + 64'd1;
                            fwd_csr_not_bypassable <= fwd_csr_not_bypassable + 64'd1;
                            hazard_csr <= hazard_csr + 64'd1;
                        end else if (hidden_is_mem_order_now) begin
                            raw_hidden <= raw_hidden + 64'd1;
                            fwd_memory_order_not_bypassable <= fwd_memory_order_not_bypassable + 64'd1;
                            hazard_store <= hazard_store + 64'd1;
                        end else begin
                            raw_hidden <= raw_hidden + 64'd1;
                            hazard_lsu_pending <= hazard_lsu_pending + 64'd1;
                        end
                    end else if (match_wb_now) begin
                        if (ws_is_alu_now) begin
                            raw_alu_wb <= raw_alu_wb + 64'd1;
                            fwd_wb_to_ex <= fwd_wb_to_ex + 64'd1;
                            hazard_wb <= hazard_wb + 64'd1;
                        end else if (ws_is_load_now) begin
                            raw_load_wb <= raw_load_wb + 64'd1;
                            count_load_pending_not_bypassable();
                            hazard_load_miss <= hazard_load_miss + 64'd1;
                        end else if (ws_is_csr_now) begin
                            raw_csr <= raw_csr + 64'd1;
                            fwd_csr_not_bypassable <= fwd_csr_not_bypassable + 64'd1;
                            hazard_csr <= hazard_csr + 64'd1;
                        end else begin
                            raw_unknown <= raw_unknown + 64'd1;
                        end
                    end else begin
                        hazard_unknown <= hazard_unknown + 64'd1;
                        fwd_unknown <= fwd_unknown + 64'd1;
                    end
                end
            end

            if (icache_pipe_resp_block_now) begin
                resp_block_total <= resp_block_total + 64'd1;
                if (epoch_recovery_now || if_pipe_stat_resp_stale) begin
                    resp_block_epoch_drop <= resp_block_epoch_drop + 64'd1;
                end else if (ifid_queue_full_now) begin
                    resp_block_if_queue_full <= resp_block_if_queue_full + 64'd1;
                end else if (id_not_ready_now) begin
                    resp_block_id_not_ready <= resp_block_id_not_ready + 64'd1;
                end else if (resp_fifo_full_delta) begin
                    resp_block_fifo_full <= resp_block_fifo_full + 64'd1;
                end else if (resp_wait_commit_now) begin
                    resp_block_wait_commit <= resp_block_wait_commit + 64'd1;
                end else if (if_stage_not_accepting_resp_now) begin
                    resp_block_if_stage_not_accepting <= resp_block_if_stage_not_accepting + 64'd1;
                end else begin
                    resp_block_unknown <= resp_block_unknown + 64'd1;
                end
            end

            if (real_commit) begin
                commit_count <= commit_count + 64'd1;
                occ_commit <= occ_commit + 64'd1;
            end else begin
                bubble_count <= bubble_count + 64'd1;
                if (trap_flush_now) begin
                    bucket_trap_flush <= bucket_trap_flush + 64'd1;
                end else if (wb_block_now) begin
                    bucket_wb_block <= bucket_wb_block + 64'd1;
                end else if (store_wait_now) begin
                    bucket_store_wait <= bucket_store_wait + 64'd1;
                end else if (dcache_wait_now) begin
                    bucket_dcache_wait <= bucket_dcache_wait + 64'd1;
                end else if (mem_lsu_wait_now) begin
                    bucket_mem_lsu_wait <= bucket_mem_lsu_wait + 64'd1;
                end else if (load_use_now) begin
                    bucket_load_use <= bucket_load_use + 64'd1;
                end else if (raw_hazard_now) begin
                    bucket_raw_hazard <= bucket_raw_hazard + 64'd1;
                end else if (csr_special_now) begin
                    bucket_csr_special <= bucket_csr_special + 64'd1;
                end else if (id_stall_now) begin
                    bucket_id_stall <= bucket_id_stall + 64'd1;
                end else if (ex_stall_now) begin
                    bucket_ex_stall <= bucket_ex_stall + 64'd1;
                end else if (if_id_empty_now) begin
                    bucket_if_id_empty <= bucket_if_id_empty + 64'd1;
                end else if (frontend_wait_now) begin
                    bucket_frontend_wait <= bucket_frontend_wait + 64'd1;
                    if (epoch_recovery_now) begin
                        frontend_epoch_drop_recovery_wait <= frontend_epoch_drop_recovery_wait + 64'd1;
                    end else if (ptw_wait_now) begin
                        frontend_ptw_wait <= frontend_ptw_wait + 64'd1;
                    end else if (icache_miss_delta) begin
                        frontend_icache_miss_refill_wait <= frontend_icache_miss_refill_wait + 64'd1;
                    end else if (icache_req_delta || (ibus_req_valid && !ibus_req_ready)) begin
                        frontend_icache_req_wait <= frontend_icache_req_wait + 64'd1;
                    end else if (ifid_queue_full_now) begin
                        frontend_ifid_queue_full_wait <= frontend_ifid_queue_full_wait + 64'd1;
                    end else if (id_not_ready_now) begin
                        frontend_id_not_ready_backpressure <= frontend_id_not_ready_backpressure + 64'd1;
                    end else if (ex_not_ready_now) begin
                        frontend_ex_not_ready_backpressure <= frontend_ex_not_ready_backpressure + 64'd1;
                    end else if (if_pipe_req_not_ready_now) begin
                        frontend_if_pipe_req_not_ready_wait <= frontend_if_pipe_req_not_ready_wait + 64'd1;
                    end else if (if_pipe_no_resp_now) begin
                        frontend_if_pipe_no_resp_wait <= frontend_if_pipe_no_resp_wait + 64'd1;
                    end else if (frontend_self_wait_now) begin
                        frontend_self_wait <= frontend_self_wait + 64'd1;
                    end else if (frontend_backpressure_like_now) begin
                        frontend_backpressure_wait <= frontend_backpressure_wait + 64'd1;
                    end else begin
                        frontend_unknown <= frontend_unknown + 64'd1;
                    end
                end else if (icache_fetch_wait_now) begin
                    bucket_icache_fetch_wait <= bucket_icache_fetch_wait + 64'd1;
                end else if (branch_recovery_now) begin
                    bucket_branch_recovery <= bucket_branch_recovery + 64'd1;
                end else if (icache_pipe_resp_block_now) begin
                    bucket_resp_block <= bucket_resp_block + 64'd1;
                end else if (stage_latency_now) begin
                    bucket_stage_latency <= bucket_stage_latency + 64'd1;
                    if (ms_valid || ms_to_ws_valid) begin
                        stage_latency_mem_valid <= stage_latency_mem_valid + 64'd1;
                    end else if (es_valid || es_to_ms_valid) begin
                        stage_latency_ex_valid <= stage_latency_ex_valid + 64'd1;
                    end else if (ds_to_es_valid) begin
                        stage_latency_id_valid <= stage_latency_id_valid + 64'd1;
                    end else if (fs_to_ds_valid || if_stat_fs_valid) begin
                        stage_latency_ifid_valid <= stage_latency_ifid_valid + 64'd1;
                    end else begin
                        stage_latency_frontend_empty <= stage_latency_frontend_empty + 64'd1;
                    end
                end else begin
                    bucket_unknown <= bucket_unknown + 64'd1;
                end
            end

        end
    end
endmodule
`endif
`endif
