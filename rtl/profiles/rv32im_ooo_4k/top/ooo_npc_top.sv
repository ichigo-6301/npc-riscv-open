`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_npc_top #(
    parameter logic [31:0] RESET_VECTOR = 32'h8000_0000,
    parameter bit USE_PMEM_IFETCH = 1'b1,
    parameter int ALU_LATENCY = 1,
    parameter int ALU1_LATENCY = ALU_LATENCY,
    parameter bit RAW_COMPLETION_WAKEUP_ENABLE = 1'b1,
    parameter bit SAME_CYCLE_DEPENDENCY_FORWARDING_ENABLE = 1'b1,
    parameter bit HEAD_LOAD_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b1,
    parameter bit HEAD_ALU_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b0,
    parameter bit HEAD_BRU_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b0,
    parameter bit LOAD_RESPONSE_COMPLETION_BYPASS_ENABLE = 1'b1,
    parameter bit LSU_REQUEST_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit PAIR_RAW_TO_FINAL_BYPASS_ENABLE = 1'b0,
    parameter bit SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE = 1'b0,
    parameter bit SAME_CYCLE_DISPATCH_ISSUE_ENABLE = 1'b0,
    parameter bit SAME_CYCLE_BRANCH_DISPATCH_ISSUE_ENABLE = 1'b0,
    parameter bit BRANCH_ORDINARY_CONCURRENT_ISSUE_ENABLE = 1'b0,
    parameter bit BRANCH_YOUNGER_ORDINARY_CONCURRENT_ISSUE_ENABLE = 1'b0,
    parameter bit REGISTERED_BRU_DISPATCH_ORDINARY_ISSUE2_ENABLE = 1'b0,
    parameter bit ISSUE_OPERAND_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit SLOT1_FINAL_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b0,
    parameter bit BRANCH_ISSUE_FINAL_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit REGISTERED_BRANCH_ISSUE_FINAL_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit STORE_ISSUE_FINAL_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit MDU_MUL_COMPLETION_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE = 1'b0,
    parameter bit POSTED_STORE_RESPONSE_PIPELINE_ENABLE = 1'b0,
    parameter bit DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE = 1'b0,
    parameter bit PRE_ARBITER_LOAD_HIT_ORACLE_ENABLE = 1'b0,
    parameter bit LOAD_TRANSACTION_DEPTH3_ENABLE = 1'b0,
    parameter bit IFETCH_SAME_EDGE_RESPONSE_CAPTURE_ENABLE = 1'b0,
    parameter bit DECODE_DISPATCH_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit FETCH_DECODE_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit FETCH_RESPONSE_CREDIT_TURNOVER_ENABLE = 1'b0,
    parameter bit ORDERED_TARGET_PREFETCH_ORACLE_ENABLE = 1'b0,
    parameter bit DEMAND_FETCH_LATENCY_ORACLE_ENABLE = 1'b0,
    parameter bit FETCH_RESPONSE_SERVICE_ORACLE_ENABLE = 1'b0,
    parameter bit CORRECT_BRANCH_DUAL_RETIRE_ENABLE = 1'b0,
    parameter bit YOUNGER_SLOT1_CONTROL_DUAL_RETIRE_ENABLE = 1'b0,
    parameter bit POST_SELECTIVE_REDIRECT_COMMIT_ENABLE = 1'b0,
    parameter bit SELECTIVE_TRANSACTION_REDIRECT_OVERLAP_ENABLE = 1'b0,
    parameter bit STRONG_BRANCH_LINE_DELIVERY_ENABLE = 1'b0,
    parameter bit DUAL_TRACE_SINK_ENABLE = 1'b0,
    parameter bit TARGET_LINE_HIT_ENABLE = 1'b1,
    parameter int unsigned TARGET_LINE_ENTRY_COUNT = 128,
    parameter int unsigned TARGET_LINE_WAY_COUNT = 1,
    parameter int unsigned CONDITIONAL_PRED_ENTRIES = 256,
    parameter bit CORRELATED_PREDICTOR_ENABLE = 1'b1,
    parameter bit CORRELATED_REACHABILITY_ORACLE_ENABLE = 1'b0,
    parameter bit WEAK_BIMODAL_REACHABILITY_ORACLE_ENABLE = 1'b0,
    parameter bit LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE = 1'b0,
    parameter bit MULTIHISTORY_REACHABILITY_ORACLE_ENABLE = 1'b0,
    parameter bit SAME_CYCLE_RAS_UPDATE_FORWARDING_ENABLE = 1'b1,
    parameter bit RAS_SELF_FORWARD_EXCLUSION_ENABLE = 1'b0,
    parameter bit SEQUENTIAL_LINE_HIT_ENABLE = 1'b1,
    parameter bit BRANCH_WINDOW_LINE_DELIVERY_ENABLE = 1'b1,
    parameter bit SPECULATIVE_STORE_DISPATCH_ENABLE = 1'b1,
    parameter bit DATA_LINE_HIT_ENABLE = 1'b1,
    parameter bit DATA_LINE_SAME_WORD_MISS_COALESCING_ENABLE = 1'b0,
    parameter bit DATA_LINE_STORE_RESPONSE_UPDATE_ENABLE = 1'b0,
    parameter int unsigned DATA_LINE_COUNT = 64,
    parameter int unsigned DATA_LINE_WAY_COUNT = 1,
    parameter bit PIPE_PERF_ACCOUNTING_ENABLE = 1'b0,
    parameter bit PIPE_PERF_OBSERVABILITY_ENABLE = 1'b0,
    parameter bit STRUCTURAL_THROUGHPUT_ORACLE_ENABLE = 1'b0,
    parameter bit SINGLETON_COALESCE_ORACLE_ENABLE = 1'b0,
    parameter bit PARTIAL_PAIR_ORACLE_ENABLE = 1'b0,
    parameter bit CACHED_CROSS_LINE_PAIR_ENABLE = 1'b0,
    parameter bit CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE = 1'b0
) (
    input  logic clk,
    input  logic rst_n,

    input  logic program_valid_i,
    input  logic [31:0] program_pc_i,
    input  logic [31:0] program_instr_i,
    output logic program_ready_o,

    input  logic commit_ready_i,

    output logic commit_valid_o,
    output logic [1:0] commit_mask_o,
    output logic commit_slot1_o,
    output logic [31:0] commit_pc_o,
    output logic [31:0] commit_instr_o,
    output logic [31:0] commit_nextpc_o,
    output logic commit_rf_wen_o,
    output logic [4:0] commit_rd_o,
    output logic [31:0] commit_wdata_o,
    output logic commit_is_load_o,
    output logic commit_is_store_o,
    output logic commit_is_branch_o,
    output logic commit_is_jal_o,
    output logic commit_is_jalr_o,
    output logic commit_unsupported_o,
    output logic commit_exception_valid_o,
    output logic [31:0] commit_mem_addr_o,
    output logic [31:0] commit_mem_wdata_o,
    output logic [3:0] commit_mem_wstrb_o,
    output logic [2:0] commit_mem_len_o,
    output logic commit1_valid_o,
    output logic [1:0] commit1_mask_o,
    output logic commit1_slot1_o,
    output logic [31:0] commit1_pc_o,
    output logic [31:0] commit1_instr_o,
    output logic [31:0] commit1_nextpc_o,
    output logic commit1_rf_wen_o,
    output logic [4:0] commit1_rd_o,
    output logic [31:0] commit1_wdata_o,
    output logic commit1_is_load_o,
    output logic commit1_is_store_o,
    output logic commit1_is_branch_o,
    output logic commit1_is_jal_o,
    output logic commit1_is_jalr_o,
    output logic commit1_unsupported_o,
    output logic commit1_exception_valid_o,
    output logic [31:0] commit1_mem_addr_o,
    output logic [31:0] commit1_mem_wdata_o,
    output logic [3:0] commit1_mem_wstrb_o,
    output logic [2:0] commit1_mem_len_o,

    output logic unsupported_seen_o,
    output logic [31:0] unsupported_pc_o,
    output logic [31:0] unsupported_instr_o,
    output logic shadow_idle_o,
    output logic halt_valid_o,
    output logic [31:0] halt_pc_o,
    output logic [31:0] halt_instr_o,
    output logic [3:0] halt_reason_o,

    input  logic [4:0] debug_arch_idx_i,
    output logic [31:0] debug_arch_gpr_o,
    output logic [31:0] debug_arch_pc_o,
    output logic [3:0] dbg_inflight_rob_occ_o,
    output logic [3:0] dbg_inflight_iq_occ_o,
    output logic [3:0] dbg_inflight_iq_ready_occ_o,
    output logic [3:0] dbg_inflight_iq_ready_alu_count_o,
    output logic [3:0] dbg_inflight_iq_ready_lsu_count_o,
    output logic [3:0] dbg_inflight_iq_ready_bru_count_o,
    output logic [3:0] dbg_inflight_iq_ready_csr_sys_count_o,
    output logic [3:0] dbg_inflight_iq_ready_any_count_o,
    output logic [3:0] dbg_inflight_issue_candidate_count_o,
    output logic dbg_inflight_issue_multi_candidate_o,
    output logic dbg_inflight_dispatch_candidate_o,
    output logic dbg_inflight_dispatch_fire_o,
    output logic dbg_inflight_iq_enqueue_o,
    output logic dbg_inflight_issue_valid_o,
    output logic dbg_inflight_issue_ready_o,
    output logic dbg_inflight_issue_fire_o,
    output logic dbg_inflight_issue_fu_ready_o,
    output logic dbg_inflight_execution_path_clear_o,
    output logic dbg_inflight_rob_full_o,
    output logic dbg_inflight_iq_full_o,
    output logic dbg_inflight_wb_buffer_valid_o,
    output logic dbg_inflight_wb_buffer_full_o,
    output logic dbg_inflight_wb_accept_o,
    output logic dbg_inflight_wb_stall_o,
    output logic dbg_inflight_alu_busy_o,
    output logic dbg_inflight_bru_busy_o,
    output logic dbg_inflight_lsu_busy_o,
    output logic dbg_inflight_csr_busy_o,
    output logic dbg_inflight_control_pending_o,
    output logic dbg_inflight_memory_pending_o,
    output logic dbg_inflight_commit_fire_o,
    output logic dbg_inflight_alu_issue_o,
    output logic dbg_inflight_bru_issue_o,
    output logic dbg_inflight_lsu_issue_o,
    output logic dbg_inflight_csr_issue_o,
    output logic dbg_inflight_alu_done_o,
    output logic dbg_inflight_bru_done_o,
    output logic dbg_inflight_lsu_done_o,
    output logic dbg_inflight_csr_done_o,
    output logic dbg_inflight_wb_conflict_o,
    output logic dbg_inflight_completion_grant_alu_o,
    output logic dbg_inflight_completion_grant_bru_o,
    output logic dbg_inflight_completion_grant_lsu_o,
    output logic dbg_inflight_completion_grant_csr_o,
    output logic dbg_inflight_completion_hold_alu_o,
    output logic dbg_inflight_completion_hold_bru_o,
    output logic dbg_inflight_completion_hold_lsu_o,
    output logic dbg_inflight_completion_hold_csr_o,
    output logic dbg_inflight_completion_oldest_arb_o,
    output logic dbg_inflight_completion_fixed_arb_o,
    output logic dbg_inflight_completion_oldest_grant_alu_o,
    output logic dbg_inflight_completion_oldest_grant_bru_o,
    output logic dbg_inflight_completion_oldest_grant_lsu_o,
    output logic dbg_inflight_completion_oldest_grant_csr_o,
    output logic dbg_inflight_completion_fixed_would_choose_alu_o,
    output logic dbg_inflight_completion_fixed_would_choose_bru_o,
    output logic dbg_inflight_completion_fixed_would_choose_lsu_o,
    output logic dbg_inflight_completion_fixed_would_choose_csr_o,
    output logic dbg_inflight_completion_oldest_differs_from_fixed_o,
    output logic dbg_inflight_duplicate_completion_tag_o,
    output logic dbg_inflight_completion_arb_no_valid_bug_o,
    output logic dbg_inflight_issue0_fire_o,
    output logic dbg_inflight_issue1_fire_o,
    output logic dbg_inflight_issue2_fire_o,
    output logic dbg_inflight_alu_alu_dual_issue_o,
    output logic dbg_inflight_alu_lsu_dual_issue_o,
    output logic dbg_inflight_dual_issue_candidate_o,
    output logic dbg_inflight_dual_issue_candidate_alu_alu_o,
    output logic dbg_inflight_dual_issue_candidate_alu_lsu_o,
    output logic dbg_inflight_dual_issue_candidate_lsu_alu_o,
    output logic dbg_inflight_dual_issue_fire_alu_alu_o,
    output logic dbg_inflight_dual_issue_fire_alu_lsu_o,
    output logic dbg_inflight_dual_issue_fire_lsu_alu_o,
    output logic dbg_inflight_alu0_issue_o,
    output logic dbg_inflight_alu1_issue_o,
    output logic dbg_inflight_alu0_busy_o,
    output logic dbg_inflight_alu1_busy_o,
    output logic dbg_inflight_alu0_done_o,
    output logic dbg_inflight_alu1_done_o,
    output logic dbg_inflight_alu0_alu1_done_same_cycle_o,
    output logic dbg_inflight_alu0_alu1_wb_conflict_o,
    output logic dbg_inflight_completion_grant_alu0_o,
    output logic dbg_inflight_completion_grant_alu1_o,
    output logic dbg_inflight_completion_hold_alu0_o,
    output logic dbg_inflight_completion_hold_alu1_o,
    output logic dbg_inflight_issue1_suppressed_o,
    output logic dbg_inflight_issue1_suppressed_by_policy_o,
    output logic dbg_inflight_issue1_suppressed_by_fu_busy_o,
    output logic dbg_inflight_issue1_suppressed_by_wb_o,
    output logic dbg_inflight_dual_issue_blocked_by_prf_o,
    output logic dbg_inflight_dual_issue_blocked_by_alu_busy_o,
    output logic dbg_inflight_dual_issue_blocked_by_alu0_busy_o,
    output logic dbg_inflight_dual_issue_blocked_by_alu1_busy_o,
    output logic dbg_inflight_dual_issue_blocked_by_lsu_busy_o,
    output logic dbg_inflight_dual_issue_blocked_by_wb_o,
    output logic dbg_inflight_dual_issue_blocked_by_completion_clear_o,
    output logic dbg_inflight_dual_issue_blocked_by_serial_o,
    output logic dbg_inflight_wb_conflict_alu0_alu1_o,
    output logic dbg_inflight_wb_conflict_alu_lsu_o,
    output logic dbg_inflight_wb_conflict_bru_data_o,
    output logic dbg_inflight_alu1_single_issue_o,
    output logic dbg_inflight_alu1_single_issue_when_alu0_busy_o,
    output logic dbg_inflight_alu1_single_issue_when_alu0_idle_o,
    output logic dbg_inflight_alu_single_issue_redirect_to_alu1_o,
    output logic dbg_inflight_alu0_single_issue_o,
    output logic dbg_inflight_alu0_single_issue_when_alu1_idle_o,
    output logic dbg_inflight_alu_sched_balance_opportunity_o,
    output logic dbg_inflight_alu_sched_balance_fire_o,
    output logic dbg_inflight_alu_sched_balance_blocked_both_busy_o,
    output logic dbg_inflight_alu_sched_balance_blocked_wb_o,
    output logic [1:0] dbg_inflight_dispatch_width_mode_o,
    output logic dbg_inflight_dispatch2_candidate_o,
    output logic dbg_inflight_dispatch2_fire_o,
    output logic dbg_inflight_dispatch2_slot0_fire_o,
    output logic dbg_inflight_dispatch2_slot1_fire_o,
    output logic dbg_inflight_dispatch2_slot1_retained_o,
    output logic dbg_inflight_dispatch2_blocked_by_rob_o,
    output logic dbg_inflight_dispatch2_blocked_by_iq_o,
    output logic dbg_inflight_dispatch2_blocked_by_freelist_o,
    output logic dbg_inflight_dispatch2_blocked_by_serial_o,
    output logic dbg_inflight_dispatch2_blocked_by_unsupported_pair_o,
    output logic dbg_inflight_dispatch2_partial_slot0_only_o,
    output logic dbg_inflight_dispatch2_slot1_retained_due_to_rob_o,
    output logic dbg_inflight_dispatch2_slot1_retained_due_to_iq_o,
    output logic dbg_inflight_dispatch2_slot1_retained_due_to_freelist_o,
    output logic dbg_inflight_dispatch2_slot1_retained_due_to_serial_o,
    output logic dbg_inflight_dispatch2_retained_replayed_as_slot0_o,
    output logic dbg_inflight_dispatch2_retained_duplicate_rename_bug_o,
    output logic dbg_inflight_dispatch2_retained_duplicate_phys_bug_o,
    output logic dbg_inflight_dispatch2_retained_duplicate_rob_bug_o,
    output logic dbg_inflight_dispatch2_retained_flush_clear_o,
    output logic dbg_inflight_rename2_fire_o,
    output logic dbg_inflight_rename2_same_cycle_raw_o,
    output logic dbg_inflight_rename2_same_cycle_waw_o,
    output logic dbg_inflight_rob_alloc2_o,
    output logic dbg_inflight_iq_enqueue2_o,
    output logic dbg_inflight_freelist_alloc2_o,
    output logic dbg_inflight_freelist_alloc1_due_to_partial_o,
    output logic dbg_inflight_rob_alloc1_due_to_partial_o,
    output logic dbg_inflight_iq_enqueue1_due_to_partial_o,
    output logic dbg_inflight_if2_bundle_valid_o,
    output logic dbg_inflight_if2_downstream_accept2_o,
    output logic dbg_inflight_if2_downstream_accept1_o,
    output logic dbg_inflight_if2_downstream_stall_o,
    output logic dbg_inflight_if2_slot1_retained_o,
    output logic dbg_inflight_if2_slot1_replayed_as_slot0_o,
    output logic dbg_inflight_if2_redirect_flush_o,
    output logic dbg_inflight_if2_stale_slot_kill_o,
    output logic dbg_inflight_if2pair_req_o,
    output logic dbg_inflight_if2pair_resp_o,
    output logic dbg_inflight_if2pair_resp_drop_o,
    output logic dbg_inflight_if2pair_stale_resp_kill_o,
    output logic dbg_inflight_if2pair_valid_mask_11_o,
    output logic dbg_inflight_if2pair_valid_mask_01_o,
    output logic dbg_inflight_if2pair_upper_half_single_o,
    output logic dbg_inflight_if2pair_downstream_accept2_o,
    output logic dbg_inflight_if2pair_downstream_accept1_o,
    output logic dbg_inflight_if2pair_downstream_stall_o,
    output logic dbg_inflight_if2pair_slot1_retained_o,
    output logic dbg_inflight_if2pair_slot1_replayed_as_slot0_o,
    output logic dbg_inflight_if2pair_redirect_flush_o,
    output logic dbg_inflight_if2pair_slot1_only_bug_o,
    output logic dbg_inflight_if2pair_stale_accept_bug_o,
    output logic dbg_inflight_if2pair_fetch_endian_bug_o,
    output logic dbg_inflight_if2pair_duplicate_replay_bug_o,
    output logic dbg_inflight_duplicate_issue_guard_o,
    output logic [1:0] dbg_inflight_commit_width_mode_o,
    output logic dbg_inflight_commit2_candidate_o,
    output logic dbg_inflight_commit2_fire_o,
    output logic dbg_inflight_commit2_slot0_only_o,
    output logic dbg_inflight_commit2_block_slot0_not_ready_o,
    output logic dbg_inflight_commit2_block_slot1_not_ready_o,
    output logic dbg_inflight_commit2_block_slot0_complex_o,
    output logic dbg_inflight_commit2_block_slot1_complex_o,
    output logic dbg_inflight_commit2_rrat_update2_o,
    output logic dbg_inflight_commit2_freelist_release2_o,
    output logic dbg_inflight_commit2_same_rd_waw_o,
    output logic dbg_inflight_commit2_duplicate_release_bug_o,
    output logic dbg_inflight_commit2_slot1_without_slot0_bug_o,
    output logic dbg_inflight_commit2_complex_slot_bug_o,
    output logic dbg_inflight_commit2_trace_slot1_o,
    output logic dbg_inflight_commit2_difftest_step2_o,
    output logic [9:0] dbg_pipe_perf_stage_widths_o,
    output logic [23:0] dbg_pipe_perf_lost_reasons_o,
    output logic [31:0] dbg_pipe_perf_occupancy_o,
    output logic [63:0] dbg_pipe_perf_events_o,
    output logic [7:0] dbg_pipe_perf_mixed_source_o,
    output logic [63:0] dbg_pipe_perf_structural_oracle_o,
    output logic [63:0] dbg_pipe_perf_structural_meta_o,
    output logic [63:0] dbg_pipe_accounting_raw_o,
    output logic dbg_pipe_accounting_selective_transaction_fire_o,
    output logic [2:0] dbg_pipe_perf_branch_pair_o,
    output logic [17:0] dbg_pipe_perf_operand_stage_o,
    output logic [1:0] dbg_pipe_accounting_fetch_width_o,
    output logic [8:0] dbg_pipe_perf_trace_width_oracle_o,
    output logic [63:0] dbg_pipe_perf_lifecycle_o,
    output logic [63:0] dbg_pipe_perf_branch_operand_o,
    output logic [63:0] dbg_pipe_perf_branch_producer_phase_o,
    output logic [63:0] dbg_pipe_perf_lsu_causality_o,
    output logic [63:0] dbg_pipe_perf_composite_load_turnover_o,
    output logic [31:0] dbg_pipe_perf_store_admission_o,
    output logic [63:0] dbg_pipe_perf_issue_dependency_o,
    output logic [31:0] dbg_pipe_perf_retirement_chain_o,
    output logic [63:0] dbg_pipe_perf_complex_retire_pairing_o,
    output logic [63:0] dbg_pipe_perf_completion_ownership_o,
    output logic [7:0] dbg_pipe_perf_serial_attribution_o,
    output logic [8:0] dbg_pipe_perf_branch_resolution_o,
    output logic [4:0] dbg_pipe_perf_target_line_o,
    output logic [7:0] dbg_pipe_perf_frontend_residual_o,
    output logic [1:0] dbg_pipe_perf_frontend_no_candidate_o,
    output logic [1:0] dbg_pipe_perf_branch_window_supply_o,
    output logic [3:0] dbg_pipe_perf_branch_window_post_block_o,
    output logic [23:0] dbg_pipe_perf_reservation_o,
    output logic [63:0] dbg_pipe_perf_fetch_response_credit_o,
    output logic [63:0] dbg_pipe_perf_demand_fetch_identity_o,
    output logic [63:0] dbg_pipe_perf_fetch_response_service_o,
    output logic [3:0] dbg_pipe_perf_branch_window_o,
    output logic [9:0] dbg_pipe_perf_checkpoint_state_o,
    output logic [3:0] dbg_pipe_perf_data_line_o,
    output logic [15:0] dbg_pipe_perf_data_line_causality_o,
    output logic [15:0] dbg_pipe_perf_data_line_coalescing_o,
    output logic [63:0] dbg_pipe_perf_data_line_store_origin_o,
    output logic [63:0] dbg_pipe_perf_store_transaction_o,
    output logic [7:0] dbg_pipe_perf_predictor_o,
    output logic [63:0] dbg_pipe_perf_predictor_detail_o,
    output logic [15:0] dbg_pipe_perf_predictor_local_o,
    output logic [20:0] dbg_pipe_perf_predictor_multihistory_o,
    output logic [31:0] dbg_pipe_perf_singleton_coalesce_o,
    output logic [31:0] dbg_pipe_perf_singleton_target_pc_o,
    output logic [31:0] dbg_pipe_perf_singleton_target_instr_o,
    output logic [31:0] dbg_pipe_perf_partial_pair_o,
    output logic [31:0] dbg_pipe_perf_partial_pair_pc_o,
    output logic [31:0] dbg_pipe_perf_partial_pair_instr_o,
    output logic [15:0] dbg_pipe_perf_cross_line_pair_o,
    output logic [31:0] dbg_pipe_perf_cross_line_carry_o,
    output logic [63:0] dbg_pipe_perf_dispatch_pc_o,
    output logic [63:0] dbg_pipe_perf_dispatch_instr_o
);
    localparam logic [31:0] EBREAK_INSTR = 32'h0010_0073;
    localparam logic [3:0] HALT_REASON_EBREAK = 4'd1;

    bbus_ooo_arch_reg_t commit_rd;
    bbus_ooo_commit_trace_packet_t trace_packet;
    bbus_ooo_commit_event_t commit_event;
    bbus_ooo_renamed_uop_t renamed_uop;

    logic reset;
    logic shadow_program_valid;
    logic [31:0] shadow_program_pc;
    logic [31:0] shadow_program_instr;
    logic shadow_program_ready;
    logic pmem_fetch_valid;
    logic [31:0] pmem_fetch_pc;
    logic [31:0] pmem_fetch_instr;
    logic pmem_fetch_ready;
    logic pmem_fetch_stop;
    logic pmem_req_valid;
    logic pmem_resp_valid;
    logic [31:0] pmem_debug_fetch_pc;
    logic ebreak_seen_q;
    logic [31:0] ebreak_pc_q;
    logic [31:0] ebreak_instr_q;
    logic shadow_idle;
    logic shadow_control_pending;
    logic shadow_memory_pending;
    logic shadow_commit_redirect_valid;
    logic [31:0] shadow_commit_redirect_pc;
    logic trace_valid;
    logic packet_buffer_valid;
    logic last_packet_accepted;
    logic last_commit_dropped;
    logic rename_fire;
    logic rob_done;
    logic [31:0] rob_result;
    logic [3:0] rob_count;
    logic [3:0] iq_count;
    logic [3:0] iq_ready_count;
    logic [3:0] iq_ready_alu_count;
    logic [3:0] iq_ready_lsu_count;
    logic [3:0] iq_ready_bru_count;
    logic [3:0] iq_ready_csr_sys_count;
    logic [3:0] iq_ready_any_count;
    logic [3:0] issue_candidate_count;
    logic issue_multi_candidate;
    logic rob_full;
    logic iq_full;
    logic wb_buffer_valid;
    logic wb_buffer_full;
    logic dispatch_candidate;
    logic dispatch_valid;
    logic dispatch_ready;
    logic iq_enqueue;
    logic iq_issue_valid;
    logic iq_issue_ready;
    logic issue_fire;
    logic issue_fu_ready;
    logic execution_path_clear;
    logic wb_accept;
    logic wb_stall;
    logic alu_busy;
    logic bru_busy;
    logic lsu_busy;
    logic csr_busy;
    logic alu_issue;
    logic bru_issue;
    logic lsu_issue;
    logic csr_issue;
    logic alu_done;
    logic bru_done;
    logic lsu_done;
    logic csr_done;
    logic wb_conflict;
    logic completion_grant_alu;
    logic completion_grant_bru;
    logic completion_grant_lsu;
    logic completion_grant_csr;
    logic completion_hold_alu;
    logic completion_hold_bru;
    logic completion_hold_lsu;
    logic completion_hold_csr;
    logic completion_oldest_arb;
    logic completion_fixed_arb;
    logic completion_oldest_grant_alu;
    logic completion_oldest_grant_bru;
    logic completion_oldest_grant_lsu;
    logic completion_oldest_grant_csr;
    logic completion_fixed_would_choose_alu;
    logic completion_fixed_would_choose_bru;
    logic completion_fixed_would_choose_lsu;
    logic completion_fixed_would_choose_csr;
    logic completion_oldest_differs_from_fixed;
    logic duplicate_completion_tag;
    logic completion_arb_no_valid_bug;
    logic issue0_fire;
    logic issue1_fire;
    logic issue2_fire;
    logic alu_alu_dual_issue;
    logic alu_lsu_dual_issue;
    logic dual_issue_candidate;
    logic dual_issue_candidate_alu_alu;
    logic dual_issue_candidate_alu_lsu;
    logic dual_issue_candidate_lsu_alu;
    logic dual_issue_fire_alu_alu;
    logic dual_issue_fire_alu_lsu;
    logic dual_issue_fire_lsu_alu;
    logic alu0_issue;
    logic alu1_issue;
    logic alu0_busy;
    logic alu1_busy;
    logic alu0_done;
    logic alu1_done;
    logic alu0_alu1_done_same_cycle;
    logic alu0_alu1_wb_conflict;
    logic completion_grant_alu0;
    logic completion_grant_alu1;
    logic completion_hold_alu0;
    logic completion_hold_alu1;
    logic issue1_suppressed;
    logic issue1_suppressed_by_policy;
    logic issue1_suppressed_by_fu_busy;
    logic issue1_suppressed_by_wb;
    logic dual_issue_blocked_by_prf;
    logic dual_issue_blocked_by_alu_busy;
    logic dual_issue_blocked_by_alu0_busy;
    logic dual_issue_blocked_by_alu1_busy;
    logic dual_issue_blocked_by_lsu_busy;
    logic dual_issue_blocked_by_wb;
    logic dual_issue_blocked_by_completion_clear;
    logic dual_issue_blocked_by_serial;
    logic wb_conflict_alu0_alu1;
    logic wb_conflict_alu_lsu;
    logic wb_conflict_bru_data;
    logic alu1_single_issue;
    logic alu1_single_issue_when_alu0_busy;
    logic alu1_single_issue_when_alu0_idle;
    logic alu_single_issue_redirect_to_alu1;
    logic alu0_single_issue;
    logic alu0_single_issue_when_alu1_idle;
    logic alu_sched_balance_opportunity;
    logic alu_sched_balance_fire;
    logic alu_sched_balance_blocked_both_busy;
    logic alu_sched_balance_blocked_wb;
    logic [1:0] dispatch_width_mode;
    logic dispatch2_candidate;
    logic dispatch2_fire;
    logic dispatch2_slot0_fire;
    logic dispatch2_slot1_fire;
    logic dispatch2_slot1_retained;
    logic dispatch2_blocked_by_rob;
    logic dispatch2_blocked_by_iq;
    logic dispatch2_blocked_by_freelist;
    logic dispatch2_blocked_by_serial;
    logic dispatch2_blocked_by_unsupported_pair;
    logic dispatch2_partial_slot0_only;
    logic dispatch2_slot1_retained_due_to_rob;
    logic dispatch2_slot1_retained_due_to_iq;
    logic dispatch2_slot1_retained_due_to_freelist;
    logic dispatch2_slot1_retained_due_to_serial;
    logic dispatch2_retained_replayed_as_slot0;
    logic dispatch2_retained_duplicate_rename_bug;
    logic dispatch2_retained_duplicate_phys_bug;
    logic dispatch2_retained_duplicate_rob_bug;
    logic dispatch2_retained_flush_clear;
    logic rename2_fire;
    logic rename2_same_cycle_raw;
    logic rename2_same_cycle_waw;
    logic rob_alloc2;
    logic iq_enqueue2;
    logic freelist_alloc2;
    logic freelist_alloc1_due_to_partial;
    logic rob_alloc1_due_to_partial;
    logic iq_enqueue1_due_to_partial;
    logic if2_bundle_valid;
    logic if2_downstream_accept2;
    logic if2_downstream_accept1;
    logic if2_downstream_stall;
    logic if2_slot1_retained;
    logic if2_slot1_replayed_as_slot0;
    logic if2_redirect_flush;
    logic if2_stale_slot_kill;
    logic if2pair_req;
    logic if2pair_resp;
    logic if2pair_resp_drop;
    logic if2pair_stale_resp_kill;
    logic if2pair_valid_mask_11;
    logic if2pair_valid_mask_01;
    logic if2pair_upper_half_single;
    logic if2pair_downstream_accept2;
    logic if2pair_downstream_accept1;
    logic if2pair_downstream_stall;
    logic if2pair_slot1_retained;
    logic if2pair_slot1_replayed_as_slot0;
    logic if2pair_redirect_flush;
    logic if2pair_slot1_only_bug;
    logic if2pair_stale_accept_bug;
    logic if2pair_fetch_endian_bug;
    logic if2pair_duplicate_replay_bug;
    logic duplicate_issue_guard;
    logic [1:0] commit_width_mode;
    logic commit2_candidate;
    logic commit2_fire;
    logic commit2_slot0_only;
    logic commit2_block_slot0_not_ready;
    logic commit2_block_slot1_not_ready;
    logic commit2_block_slot0_complex;
    logic commit2_block_slot1_complex;
    logic commit2_rrat_update2;
    logic commit2_freelist_release2;
    logic commit2_same_rd_waw;
    logic commit2_duplicate_release_bug;
    logic commit2_slot1_without_slot0_bug;
    logic commit2_complex_slot_bug;
    logic commit2_trace_slot1;
    logic commit2_difftest_step2;
    logic shadow_ebreak_commit;

    assign reset = !rst_n;

`ifdef NPC_OOO_BACKEND_PIPELINE
    logic pipe_commit_valid;
    bbus_ooo_commit_trace_packet_t pipe_commit_packet;
    logic pipe_commit1_valid;
    bbus_ooo_commit_trace_packet_t pipe_commit_packet1;
    bbus_ooo_commit_event_t pipe_commit_event;
    logic pipe_idle, pipe_halt_valid;
    logic [31:0] pipe_halt_pc, pipe_halt_instr;
    logic [3:0] pipe_halt_reason;
    logic [31:0] pipe_arch_gpr, pipe_arch_pc;
    logic [3:0] pipe_rob_count, pipe_iq_count;
    logic pipe_control_pending, pipe_memory_pending, pipe_frontend_busy;
    logic pipe_commit_fire, pipe_commit2_fire, pipe_trace_buffer_valid;
    logic pipe_conservation_error, pipe_unsupported_seen;
    logic [9:0] pipe_perf_stage_widths;
    logic [23:0] pipe_perf_lost_reasons;
    logic [31:0] pipe_perf_occupancy;
    logic [63:0] pipe_perf_events;
    logic [7:0] pipe_perf_mixed_source;
    logic [63:0] pipe_perf_structural_oracle;
    logic [63:0] pipe_perf_structural_meta;
    logic [63:0] pipe_accounting_raw;
    logic pipe_accounting_selective_transaction_fire;
    logic [2:0] pipe_perf_branch_pair;
    logic [17:0] pipe_perf_operand_stage;
    logic [1:0] pipe_accounting_fetch_width;
    logic [8:0] pipe_perf_trace_width_oracle;
    logic [63:0] pipe_perf_lifecycle;
    logic [63:0] pipe_perf_branch_operand;
    logic [63:0] pipe_perf_branch_producer_phase;
    logic [63:0] pipe_perf_lsu_causality;
    logic [63:0] pipe_perf_composite_load_turnover;
    logic [31:0] pipe_perf_store_admission;
    logic [63:0] pipe_perf_issue_dependency;
    logic [31:0] pipe_perf_retirement_chain;
    logic [63:0] pipe_perf_complex_retire_pairing;
    logic [63:0] pipe_perf_completion_ownership;
    logic [7:0] pipe_perf_serial_attribution;
    logic [8:0] pipe_perf_branch_resolution;
    logic [4:0] pipe_perf_target_line;
    logic [7:0] pipe_perf_frontend_residual;
    logic [1:0] pipe_perf_frontend_no_candidate;
    logic [1:0] pipe_perf_branch_window_supply;
    logic [3:0] pipe_perf_branch_window_post_block;
    logic [23:0] pipe_perf_reservation;
    logic [63:0] pipe_perf_fetch_response_credit;
    logic [63:0] pipe_perf_demand_fetch_identity;
    logic [63:0] pipe_perf_fetch_response_service;
    logic [3:0] pipe_perf_branch_window;
    logic [9:0] pipe_perf_checkpoint_state;
    logic [3:0] pipe_perf_data_line;
    logic [15:0] pipe_perf_data_line_causality;
    logic [15:0] pipe_perf_data_line_coalescing;
    logic [63:0] pipe_perf_data_line_store_origin;
    logic [63:0] pipe_perf_store_transaction;
    logic [7:0] pipe_perf_predictor;
    logic [63:0] pipe_perf_predictor_detail;
    logic [15:0] pipe_perf_predictor_local;
    logic [20:0] pipe_perf_predictor_multihistory;
    logic [31:0] pipe_perf_singleton_coalesce;
    logic [31:0] pipe_perf_singleton_target_pc;
    logic [31:0] pipe_perf_singleton_target_instr;
    logic [31:0] pipe_perf_partial_pair;
    logic [31:0] pipe_perf_partial_pair_pc;
    logic [31:0] pipe_perf_partial_pair_instr;
    logic [15:0] pipe_perf_cross_line_pair;
    logic [31:0] pipe_perf_cross_line_carry;
    logic [63:0] pipe_perf_dispatch_pc;
    logic [63:0] pipe_perf_dispatch_instr;
    logic [31:0] pipe_unsupported_pc, pipe_unsupported_instr;

    ooo_pipeline_npc_core_top #(
        .RESET_VECTOR(RESET_VECTOR),
        .RAW_COMPLETION_WAKEUP_ENABLE(RAW_COMPLETION_WAKEUP_ENABLE),
        .SAME_CYCLE_DEPENDENCY_FORWARDING_ENABLE(
            SAME_CYCLE_DEPENDENCY_FORWARDING_ENABLE),
        .HEAD_LOAD_WRITEBACK_COMMIT_BYPASS_ENABLE(
            HEAD_LOAD_WRITEBACK_COMMIT_BYPASS_ENABLE),
        .HEAD_ALU_WRITEBACK_COMMIT_BYPASS_ENABLE(
            HEAD_ALU_WRITEBACK_COMMIT_BYPASS_ENABLE),
        .HEAD_BRU_WRITEBACK_COMMIT_BYPASS_ENABLE(
            HEAD_BRU_WRITEBACK_COMMIT_BYPASS_ENABLE),
        .LOAD_RESPONSE_COMPLETION_BYPASS_ENABLE(
            LOAD_RESPONSE_COMPLETION_BYPASS_ENABLE),
        .LSU_REQUEST_FALLTHROUGH_ENABLE(
            LSU_REQUEST_FALLTHROUGH_ENABLE),
        .PAIR_RAW_TO_FINAL_BYPASS_ENABLE(
            PAIR_RAW_TO_FINAL_BYPASS_ENABLE),
        .SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE(
            SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE),
        .SAME_CYCLE_DISPATCH_ISSUE_ENABLE(
            SAME_CYCLE_DISPATCH_ISSUE_ENABLE),
        .SAME_CYCLE_BRANCH_DISPATCH_ISSUE_ENABLE(
            SAME_CYCLE_BRANCH_DISPATCH_ISSUE_ENABLE),
        .BRANCH_ORDINARY_CONCURRENT_ISSUE_ENABLE(
            BRANCH_ORDINARY_CONCURRENT_ISSUE_ENABLE),
        .BRANCH_YOUNGER_ORDINARY_CONCURRENT_ISSUE_ENABLE(
            BRANCH_YOUNGER_ORDINARY_CONCURRENT_ISSUE_ENABLE),
        .REGISTERED_BRU_DISPATCH_ORDINARY_ISSUE2_ENABLE(
            REGISTERED_BRU_DISPATCH_ORDINARY_ISSUE2_ENABLE),
        .ISSUE_OPERAND_FALLTHROUGH_ENABLE(
            ISSUE_OPERAND_FALLTHROUGH_ENABLE),
        .SLOT1_FINAL_WRITEBACK_COMMIT_BYPASS_ENABLE(
            SLOT1_FINAL_WRITEBACK_COMMIT_BYPASS_ENABLE),
        .BRANCH_ISSUE_FINAL_FALLTHROUGH_ENABLE(
            BRANCH_ISSUE_FINAL_FALLTHROUGH_ENABLE),
        .REGISTERED_BRANCH_ISSUE_FINAL_FALLTHROUGH_ENABLE(
            REGISTERED_BRANCH_ISSUE_FINAL_FALLTHROUGH_ENABLE),
        .STORE_ISSUE_FINAL_FALLTHROUGH_ENABLE(
            STORE_ISSUE_FINAL_FALLTHROUGH_ENABLE),
        .MDU_MUL_COMPLETION_FALLTHROUGH_ENABLE(
            MDU_MUL_COMPLETION_FALLTHROUGH_ENABLE),
        .POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE(
            POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE),
        .POSTED_STORE_RESPONSE_PIPELINE_ENABLE(
            POSTED_STORE_RESPONSE_PIPELINE_ENABLE),
        .DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE(
            DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE),
        .PRE_ARBITER_LOAD_HIT_ORACLE_ENABLE(
            PRE_ARBITER_LOAD_HIT_ORACLE_ENABLE),
        .LOAD_TRANSACTION_DEPTH3_ENABLE(LOAD_TRANSACTION_DEPTH3_ENABLE),
        .IFETCH_SAME_EDGE_RESPONSE_CAPTURE_ENABLE(
            IFETCH_SAME_EDGE_RESPONSE_CAPTURE_ENABLE),
        .FETCH_DECODE_FALLTHROUGH_ENABLE(
            FETCH_DECODE_FALLTHROUGH_ENABLE),
        .FETCH_RESPONSE_CREDIT_TURNOVER_ENABLE(
            FETCH_RESPONSE_CREDIT_TURNOVER_ENABLE),
        .ORDERED_TARGET_PREFETCH_ORACLE_ENABLE(
            ORDERED_TARGET_PREFETCH_ORACLE_ENABLE),
        .DEMAND_FETCH_LATENCY_ORACLE_ENABLE(
            DEMAND_FETCH_LATENCY_ORACLE_ENABLE),
        .FETCH_RESPONSE_SERVICE_ORACLE_ENABLE(
            FETCH_RESPONSE_SERVICE_ORACLE_ENABLE),
        .DECODE_DISPATCH_FALLTHROUGH_ENABLE(
            DECODE_DISPATCH_FALLTHROUGH_ENABLE),
        .CORRECT_BRANCH_DUAL_RETIRE_ENABLE(
            CORRECT_BRANCH_DUAL_RETIRE_ENABLE),
        .YOUNGER_SLOT1_CONTROL_DUAL_RETIRE_ENABLE(
            YOUNGER_SLOT1_CONTROL_DUAL_RETIRE_ENABLE),
        .POST_SELECTIVE_REDIRECT_COMMIT_ENABLE(
            POST_SELECTIVE_REDIRECT_COMMIT_ENABLE),
        .SELECTIVE_TRANSACTION_REDIRECT_OVERLAP_ENABLE(
            SELECTIVE_TRANSACTION_REDIRECT_OVERLAP_ENABLE),
        .STRONG_BRANCH_LINE_DELIVERY_ENABLE(
            STRONG_BRANCH_LINE_DELIVERY_ENABLE),
        .DUAL_TRACE_SINK_ENABLE(DUAL_TRACE_SINK_ENABLE),
        .TARGET_LINE_HIT_ENABLE(TARGET_LINE_HIT_ENABLE),
        .TARGET_LINE_ENTRY_COUNT(TARGET_LINE_ENTRY_COUNT),
        .TARGET_LINE_WAY_COUNT(TARGET_LINE_WAY_COUNT),
        .CONDITIONAL_PRED_ENTRIES(CONDITIONAL_PRED_ENTRIES),
        .CORRELATED_PREDICTOR_ENABLE(CORRELATED_PREDICTOR_ENABLE),
        .CORRELATED_REACHABILITY_ORACLE_ENABLE(
            CORRELATED_REACHABILITY_ORACLE_ENABLE),
        .WEAK_BIMODAL_REACHABILITY_ORACLE_ENABLE(
            WEAK_BIMODAL_REACHABILITY_ORACLE_ENABLE),
        .LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE(
            LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE),
        .MULTIHISTORY_REACHABILITY_ORACLE_ENABLE(
            MULTIHISTORY_REACHABILITY_ORACLE_ENABLE),
        .SAME_CYCLE_RAS_UPDATE_FORWARDING_ENABLE(
            SAME_CYCLE_RAS_UPDATE_FORWARDING_ENABLE),
        .RAS_SELF_FORWARD_EXCLUSION_ENABLE(
            RAS_SELF_FORWARD_EXCLUSION_ENABLE),
        .SEQUENTIAL_LINE_HIT_ENABLE(SEQUENTIAL_LINE_HIT_ENABLE),
        .BRANCH_WINDOW_LINE_DELIVERY_ENABLE(
            BRANCH_WINDOW_LINE_DELIVERY_ENABLE),
        .SPECULATIVE_STORE_DISPATCH_ENABLE(
            SPECULATIVE_STORE_DISPATCH_ENABLE),
        .DATA_LINE_HIT_ENABLE(DATA_LINE_HIT_ENABLE),
        .DATA_LINE_SAME_WORD_MISS_COALESCING_ENABLE(
            DATA_LINE_SAME_WORD_MISS_COALESCING_ENABLE),
        .DATA_LINE_STORE_RESPONSE_UPDATE_ENABLE(
            DATA_LINE_STORE_RESPONSE_UPDATE_ENABLE),
        .DATA_LINE_COUNT(DATA_LINE_COUNT),
        .DATA_LINE_WAY_COUNT(DATA_LINE_WAY_COUNT),
        .STRUCTURAL_THROUGHPUT_ORACLE_ENABLE(
            STRUCTURAL_THROUGHPUT_ORACLE_ENABLE),
        .SINGLETON_COALESCE_ORACLE_ENABLE(
            SINGLETON_COALESCE_ORACLE_ENABLE),
        .PARTIAL_PAIR_ORACLE_ENABLE(PARTIAL_PAIR_ORACLE_ENABLE),
        .CACHED_CROSS_LINE_PAIR_ENABLE(CACHED_CROSS_LINE_PAIR_ENABLE),
        .CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE(
            CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE)
    ) u_pipeline_core (
        .clk(clk), .reset(reset), .commit_ready_i(commit_ready_i),
        .debug_arch_idx_i(bbus_ooo_arch_reg_t'(debug_arch_idx_i)),
        .ext_if_req_valid_o(), .ext_if_req_ready_i(1'b0),
        .ext_if_req_addr_o(), .ext_if_req_pc_o(),
        .ext_if_rsp_valid_i(1'b0), .ext_if_rsp_ready_o(),
        .ext_if_rsp_addr_i(32'b0), .ext_if_rsp_valid_mask_i(2'b0),
        .ext_if_rsp_data_i(64'b0), .ext_if_rsp_eof_i(1'b0),
        .ext_if_rsp_error_i(1'b0),
        .ext_fetch_pte_req_valid_o(), .ext_fetch_pte_req_ready_i(1'b0),
        .ext_fetch_pte_req_addr_o(), .ext_fetch_pte_rsp_valid_i(1'b0),
        .ext_fetch_pte_rsp_ready_o(), .ext_fetch_pte_rsp_data_i(32'b0),
        .ext_fetch_pte_rsp_error_i(1'b0),
        .ext_mem_req_valid_o(), .ext_mem_req_ready_i(1'b0),
        .ext_mem_req_write_o(), .ext_mem_req_addr_o(),
        .ext_mem_req_wdata_o(), .ext_mem_req_wstrb_o(), .ext_mem_req_len_o(),
        .ext_mem_req_token_o(),
        .ext_mem_rsp_valid_i(1'b0), .ext_mem_rsp_ready_o(),
        .ext_mem_rsp_rdata_i(32'b0), .ext_mem_rsp_error_i(1'b0),
        .ext_mem_rsp_token_i('0),
        .commit_valid_o(pipe_commit_valid), .commit_packet_o(pipe_commit_packet),
        .commit1_valid_o(pipe_commit1_valid),
        .commit_packet1_o(pipe_commit_packet1),
        .commit_event_o(pipe_commit_event),
        .unsupported_seen_o(pipe_unsupported_seen),
        .unsupported_pc_o(pipe_unsupported_pc),
        .unsupported_instr_o(pipe_unsupported_instr),
        .idle_o(pipe_idle), .halt_valid_o(pipe_halt_valid),
        .halt_pc_o(pipe_halt_pc), .halt_instr_o(pipe_halt_instr),
        .halt_reason_o(pipe_halt_reason), .debug_arch_gpr_o(pipe_arch_gpr),
        .debug_arch_pc_o(pipe_arch_pc), .debug_rob_count_o(pipe_rob_count),
        .debug_iq_count_o(pipe_iq_count),
        .debug_control_pending_o(pipe_control_pending),
        .debug_memory_pending_o(pipe_memory_pending),
        .debug_frontend_busy_o(pipe_frontend_busy),
        .debug_commit_fire_o(pipe_commit_fire),
        .debug_commit2_fire_o(pipe_commit2_fire),
        .debug_trace_buffer_valid_o(pipe_trace_buffer_valid),
        .debug_conservation_error_o(pipe_conservation_error),
        .perf_stage_widths_o(pipe_perf_stage_widths),
        .perf_lost_reasons_o(pipe_perf_lost_reasons),
        .perf_occupancy_o(pipe_perf_occupancy),
        .perf_events_o(pipe_perf_events),
        .perf_mixed_source_o(pipe_perf_mixed_source),
        .perf_structural_oracle_o(pipe_perf_structural_oracle),
        .perf_structural_meta_o(pipe_perf_structural_meta),
        .perf_accounting_raw_o(pipe_accounting_raw),
        .perf_selective_transaction_fire_o(
            pipe_accounting_selective_transaction_fire),
        .perf_branch_pair_o(pipe_perf_branch_pair),
        .perf_operand_stage_o(pipe_perf_operand_stage),
        .perf_fetch_delivery_width_o(pipe_accounting_fetch_width),
        .perf_trace_width_oracle_o(pipe_perf_trace_width_oracle),
        .perf_lifecycle_o(pipe_perf_lifecycle),
        .perf_branch_operand_o(pipe_perf_branch_operand),
        .perf_branch_producer_phase_o(pipe_perf_branch_producer_phase),
        .perf_lsu_causality_o(pipe_perf_lsu_causality),
        .perf_composite_load_turnover_o(
            pipe_perf_composite_load_turnover),
        .perf_store_admission_o(pipe_perf_store_admission),
        .perf_issue_dependency_o(pipe_perf_issue_dependency),
        .perf_retirement_chain_o(pipe_perf_retirement_chain),
        .perf_complex_retire_pairing_o(pipe_perf_complex_retire_pairing),
        .perf_completion_ownership_o(pipe_perf_completion_ownership),
        .perf_serial_attribution_o(pipe_perf_serial_attribution),
        .perf_branch_resolution_o(pipe_perf_branch_resolution),
        .perf_target_line_o(pipe_perf_target_line),
        .perf_frontend_residual_o(pipe_perf_frontend_residual),
        .perf_frontend_no_candidate_o(pipe_perf_frontend_no_candidate),
        .perf_branch_window_supply_o(pipe_perf_branch_window_supply),
        .perf_branch_window_post_block_o(pipe_perf_branch_window_post_block),
        .perf_reservation_o(pipe_perf_reservation),
        .perf_fetch_response_credit_o(pipe_perf_fetch_response_credit),
        .perf_demand_fetch_identity_o(pipe_perf_demand_fetch_identity),
        .perf_fetch_response_service_o(pipe_perf_fetch_response_service),
        .perf_branch_window_o(pipe_perf_branch_window),
        .perf_checkpoint_state_o(pipe_perf_checkpoint_state),
        .perf_data_line_o(pipe_perf_data_line),
        .perf_data_line_causality_o(pipe_perf_data_line_causality),
        .perf_data_line_coalescing_o(pipe_perf_data_line_coalescing),
        .perf_data_line_store_origin_o(pipe_perf_data_line_store_origin),
        .perf_store_transaction_o(pipe_perf_store_transaction),
        .perf_predictor_o(pipe_perf_predictor),
        .perf_predictor_detail_o(pipe_perf_predictor_detail),
        .perf_predictor_local_o(pipe_perf_predictor_local),
        .perf_predictor_multihistory_o(
            pipe_perf_predictor_multihistory),
        .perf_singleton_coalesce_o(pipe_perf_singleton_coalesce),
        .perf_singleton_target_pc_o(pipe_perf_singleton_target_pc),
        .perf_singleton_target_instr_o(pipe_perf_singleton_target_instr),
        .perf_partial_pair_o(pipe_perf_partial_pair),
        .perf_partial_pair_pc_o(pipe_perf_partial_pair_pc),
        .perf_partial_pair_instr_o(pipe_perf_partial_pair_instr),
        .perf_cross_line_pair_o(pipe_perf_cross_line_pair),
        .perf_cross_line_carry_o(pipe_perf_cross_line_carry),
        .perf_dispatch_pc_o(pipe_perf_dispatch_pc),
        .perf_dispatch_instr_o(pipe_perf_dispatch_instr)
    );

    always_comb begin
        program_ready_o = '0;
        commit_valid_o = '0;
        commit_mask_o = '0;
        commit_slot1_o = '0;
        commit_pc_o = '0;
        commit_instr_o = '0;
        commit_nextpc_o = '0;
        commit_rf_wen_o = '0;
        commit_rd_o = '0;
        commit_wdata_o = '0;
        commit_is_load_o = '0;
        commit_is_store_o = '0;
        commit_is_branch_o = '0;
        commit_is_jal_o = '0;
        commit_is_jalr_o = '0;
        commit_unsupported_o = '0;
        commit_exception_valid_o = '0;
        commit_mem_addr_o = '0;
        commit_mem_wdata_o = '0;
        commit_mem_wstrb_o = '0;
        commit_mem_len_o = '0;
        commit1_valid_o = '0;
        commit1_mask_o = '0;
        commit1_slot1_o = '0;
        commit1_pc_o = '0;
        commit1_instr_o = '0;
        commit1_nextpc_o = '0;
        commit1_rf_wen_o = '0;
        commit1_rd_o = '0;
        commit1_wdata_o = '0;
        commit1_is_load_o = '0;
        commit1_is_store_o = '0;
        commit1_is_branch_o = '0;
        commit1_is_jal_o = '0;
        commit1_is_jalr_o = '0;
        commit1_unsupported_o = '0;
        commit1_exception_valid_o = '0;
        commit1_mem_addr_o = '0;
        commit1_mem_wdata_o = '0;
        commit1_mem_wstrb_o = '0;
        commit1_mem_len_o = '0;
        unsupported_seen_o = '0;
        unsupported_pc_o = '0;
        unsupported_instr_o = '0;
        shadow_idle_o = '0;
        halt_valid_o = '0;
        halt_pc_o = '0;
        halt_instr_o = '0;
        halt_reason_o = '0;
        debug_arch_gpr_o = '0;
        debug_arch_pc_o = '0;
        dbg_inflight_rob_occ_o = '0;
        dbg_inflight_iq_occ_o = '0;
        dbg_inflight_iq_ready_occ_o = '0;
        dbg_inflight_iq_ready_alu_count_o = '0;
        dbg_inflight_iq_ready_lsu_count_o = '0;
        dbg_inflight_iq_ready_bru_count_o = '0;
        dbg_inflight_iq_ready_csr_sys_count_o = '0;
        dbg_inflight_iq_ready_any_count_o = '0;
        dbg_inflight_issue_candidate_count_o = '0;
        dbg_inflight_issue_multi_candidate_o = '0;
        dbg_inflight_dispatch_candidate_o = '0;
        dbg_inflight_dispatch_fire_o = '0;
        dbg_inflight_iq_enqueue_o = '0;
        dbg_inflight_issue_valid_o = '0;
        dbg_inflight_issue_ready_o = '0;
        dbg_inflight_issue_fire_o = '0;
        dbg_inflight_issue_fu_ready_o = '0;
        dbg_inflight_execution_path_clear_o = '0;
        dbg_inflight_rob_full_o = '0;
        dbg_inflight_iq_full_o = '0;
        dbg_inflight_wb_buffer_valid_o = '0;
        dbg_inflight_wb_buffer_full_o = '0;
        dbg_inflight_wb_accept_o = '0;
        dbg_inflight_wb_stall_o = '0;
        dbg_inflight_alu_busy_o = '0;
        dbg_inflight_bru_busy_o = '0;
        dbg_inflight_lsu_busy_o = '0;
        dbg_inflight_csr_busy_o = '0;
        dbg_inflight_control_pending_o = '0;
        dbg_inflight_memory_pending_o = '0;
        dbg_inflight_commit_fire_o = '0;
        dbg_inflight_alu_issue_o = '0;
        dbg_inflight_bru_issue_o = '0;
        dbg_inflight_lsu_issue_o = '0;
        dbg_inflight_csr_issue_o = '0;
        dbg_inflight_alu_done_o = '0;
        dbg_inflight_bru_done_o = '0;
        dbg_inflight_lsu_done_o = '0;
        dbg_inflight_csr_done_o = '0;
        dbg_inflight_wb_conflict_o = '0;
        dbg_inflight_completion_grant_alu_o = '0;
        dbg_inflight_completion_grant_bru_o = '0;
        dbg_inflight_completion_grant_lsu_o = '0;
        dbg_inflight_completion_grant_csr_o = '0;
        dbg_inflight_completion_hold_alu_o = '0;
        dbg_inflight_completion_hold_bru_o = '0;
        dbg_inflight_completion_hold_lsu_o = '0;
        dbg_inflight_completion_hold_csr_o = '0;
        dbg_inflight_completion_oldest_arb_o = '0;
        dbg_inflight_completion_fixed_arb_o = '0;
        dbg_inflight_completion_oldest_grant_alu_o = '0;
        dbg_inflight_completion_oldest_grant_bru_o = '0;
        dbg_inflight_completion_oldest_grant_lsu_o = '0;
        dbg_inflight_completion_oldest_grant_csr_o = '0;
        dbg_inflight_completion_fixed_would_choose_alu_o = '0;
        dbg_inflight_completion_fixed_would_choose_bru_o = '0;
        dbg_inflight_completion_fixed_would_choose_lsu_o = '0;
        dbg_inflight_completion_fixed_would_choose_csr_o = '0;
        dbg_inflight_completion_oldest_differs_from_fixed_o = '0;
        dbg_inflight_duplicate_completion_tag_o = '0;
        dbg_inflight_completion_arb_no_valid_bug_o = '0;
        dbg_inflight_issue0_fire_o = '0;
        dbg_inflight_issue1_fire_o = '0;
        dbg_inflight_issue2_fire_o = '0;
        dbg_inflight_alu_alu_dual_issue_o = '0;
        dbg_inflight_alu_lsu_dual_issue_o = '0;
        dbg_inflight_dual_issue_candidate_o = '0;
        dbg_inflight_dual_issue_candidate_alu_alu_o = '0;
        dbg_inflight_dual_issue_candidate_alu_lsu_o = '0;
        dbg_inflight_dual_issue_candidate_lsu_alu_o = '0;
        dbg_inflight_dual_issue_fire_alu_alu_o = '0;
        dbg_inflight_dual_issue_fire_alu_lsu_o = '0;
        dbg_inflight_dual_issue_fire_lsu_alu_o = '0;
        dbg_inflight_alu0_issue_o = '0;
        dbg_inflight_alu1_issue_o = '0;
        dbg_inflight_alu0_busy_o = '0;
        dbg_inflight_alu1_busy_o = '0;
        dbg_inflight_alu0_done_o = '0;
        dbg_inflight_alu1_done_o = '0;
        dbg_inflight_alu0_alu1_done_same_cycle_o = '0;
        dbg_inflight_alu0_alu1_wb_conflict_o = '0;
        dbg_inflight_completion_grant_alu0_o = '0;
        dbg_inflight_completion_grant_alu1_o = '0;
        dbg_inflight_completion_hold_alu0_o = '0;
        dbg_inflight_completion_hold_alu1_o = '0;
        dbg_inflight_issue1_suppressed_o = '0;
        dbg_inflight_issue1_suppressed_by_policy_o = '0;
        dbg_inflight_issue1_suppressed_by_fu_busy_o = '0;
        dbg_inflight_issue1_suppressed_by_wb_o = '0;
        dbg_inflight_dual_issue_blocked_by_prf_o = '0;
        dbg_inflight_dual_issue_blocked_by_alu_busy_o = '0;
        dbg_inflight_dual_issue_blocked_by_alu0_busy_o = '0;
        dbg_inflight_dual_issue_blocked_by_alu1_busy_o = '0;
        dbg_inflight_dual_issue_blocked_by_lsu_busy_o = '0;
        dbg_inflight_dual_issue_blocked_by_wb_o = '0;
        dbg_inflight_dual_issue_blocked_by_completion_clear_o = '0;
        dbg_inflight_dual_issue_blocked_by_serial_o = '0;
        dbg_inflight_wb_conflict_alu0_alu1_o = '0;
        dbg_inflight_wb_conflict_alu_lsu_o = '0;
        dbg_inflight_wb_conflict_bru_data_o = '0;
        dbg_inflight_alu1_single_issue_o = '0;
        dbg_inflight_alu1_single_issue_when_alu0_busy_o = '0;
        dbg_inflight_alu1_single_issue_when_alu0_idle_o = '0;
        dbg_inflight_alu_single_issue_redirect_to_alu1_o = '0;
        dbg_inflight_alu0_single_issue_o = '0;
        dbg_inflight_alu0_single_issue_when_alu1_idle_o = '0;
        dbg_inflight_alu_sched_balance_opportunity_o = '0;
        dbg_inflight_alu_sched_balance_fire_o = '0;
        dbg_inflight_alu_sched_balance_blocked_both_busy_o = '0;
        dbg_inflight_alu_sched_balance_blocked_wb_o = '0;
        dbg_inflight_dispatch_width_mode_o = '0;
        dbg_inflight_dispatch2_candidate_o = '0;
        dbg_inflight_dispatch2_fire_o = '0;
        dbg_inflight_dispatch2_slot0_fire_o = '0;
        dbg_inflight_dispatch2_slot1_fire_o = '0;
        dbg_inflight_dispatch2_slot1_retained_o = '0;
        dbg_inflight_dispatch2_blocked_by_rob_o = '0;
        dbg_inflight_dispatch2_blocked_by_iq_o = '0;
        dbg_inflight_dispatch2_blocked_by_freelist_o = '0;
        dbg_inflight_dispatch2_blocked_by_serial_o = '0;
        dbg_inflight_dispatch2_blocked_by_unsupported_pair_o = '0;
        dbg_inflight_dispatch2_partial_slot0_only_o = '0;
        dbg_inflight_dispatch2_slot1_retained_due_to_rob_o = '0;
        dbg_inflight_dispatch2_slot1_retained_due_to_iq_o = '0;
        dbg_inflight_dispatch2_slot1_retained_due_to_freelist_o = '0;
        dbg_inflight_dispatch2_slot1_retained_due_to_serial_o = '0;
        dbg_inflight_dispatch2_retained_replayed_as_slot0_o = '0;
        dbg_inflight_dispatch2_retained_duplicate_rename_bug_o = '0;
        dbg_inflight_dispatch2_retained_duplicate_phys_bug_o = '0;
        dbg_inflight_dispatch2_retained_duplicate_rob_bug_o = '0;
        dbg_inflight_dispatch2_retained_flush_clear_o = '0;
        dbg_inflight_rename2_fire_o = '0;
        dbg_inflight_rename2_same_cycle_raw_o = '0;
        dbg_inflight_rename2_same_cycle_waw_o = '0;
        dbg_inflight_rob_alloc2_o = '0;
        dbg_inflight_iq_enqueue2_o = '0;
        dbg_inflight_freelist_alloc2_o = '0;
        dbg_inflight_freelist_alloc1_due_to_partial_o = '0;
        dbg_inflight_rob_alloc1_due_to_partial_o = '0;
        dbg_inflight_iq_enqueue1_due_to_partial_o = '0;
        dbg_inflight_if2_bundle_valid_o = '0;
        dbg_inflight_if2_downstream_accept2_o = '0;
        dbg_inflight_if2_downstream_accept1_o = '0;
        dbg_inflight_if2_downstream_stall_o = '0;
        dbg_inflight_if2_slot1_retained_o = '0;
        dbg_inflight_if2_slot1_replayed_as_slot0_o = '0;
        dbg_inflight_if2_redirect_flush_o = '0;
        dbg_inflight_if2_stale_slot_kill_o = '0;
        dbg_inflight_if2pair_req_o = '0;
        dbg_inflight_if2pair_resp_o = '0;
        dbg_inflight_if2pair_resp_drop_o = '0;
        dbg_inflight_if2pair_stale_resp_kill_o = '0;
        dbg_inflight_if2pair_valid_mask_11_o = '0;
        dbg_inflight_if2pair_valid_mask_01_o = '0;
        dbg_inflight_if2pair_upper_half_single_o = '0;
        dbg_inflight_if2pair_downstream_accept2_o = '0;
        dbg_inflight_if2pair_downstream_accept1_o = '0;
        dbg_inflight_if2pair_downstream_stall_o = '0;
        dbg_inflight_if2pair_slot1_retained_o = '0;
        dbg_inflight_if2pair_slot1_replayed_as_slot0_o = '0;
        dbg_inflight_if2pair_redirect_flush_o = '0;
        dbg_inflight_if2pair_slot1_only_bug_o = '0;
        dbg_inflight_if2pair_stale_accept_bug_o = '0;
        dbg_inflight_if2pair_fetch_endian_bug_o = '0;
        dbg_inflight_if2pair_duplicate_replay_bug_o = '0;
        dbg_inflight_duplicate_issue_guard_o = '0;
        dbg_inflight_commit_width_mode_o = '0;
        dbg_inflight_commit2_candidate_o = '0;
        dbg_inflight_commit2_fire_o = '0;
        dbg_inflight_commit2_slot0_only_o = '0;
        dbg_inflight_commit2_block_slot0_not_ready_o = '0;
        dbg_inflight_commit2_block_slot1_not_ready_o = '0;
        dbg_inflight_commit2_block_slot0_complex_o = '0;
        dbg_inflight_commit2_block_slot1_complex_o = '0;
        dbg_inflight_commit2_rrat_update2_o = '0;
        dbg_inflight_commit2_freelist_release2_o = '0;
        dbg_inflight_commit2_same_rd_waw_o = '0;
        dbg_inflight_commit2_duplicate_release_bug_o = '0;
        dbg_inflight_commit2_slot1_without_slot0_bug_o = '0;
        dbg_inflight_commit2_complex_slot_bug_o = '0;
        dbg_inflight_commit2_trace_slot1_o = '0;
        dbg_inflight_commit2_difftest_step2_o = '0;
        commit_valid_o = pipe_commit_valid;
        commit_mask_o = pipe_commit_packet.commit_mask;
        commit_slot1_o = pipe_commit_packet.commit_slot1;
        commit_pc_o = pipe_commit_packet.pc;
        commit_instr_o = pipe_commit_packet.instr;
        commit_nextpc_o = pipe_commit_packet.commit_nextpc;
        commit_rf_wen_o = pipe_commit_packet.rf_wen;
        commit_rd_o = pipe_commit_packet.arch_rd;
        commit_wdata_o = pipe_commit_packet.wdata;
        commit_is_load_o = pipe_commit_packet.is_load;
        commit_is_store_o = pipe_commit_packet.is_store;
        commit_is_branch_o = pipe_commit_packet.is_branch;
        commit_is_jal_o = pipe_commit_packet.is_jal;
        commit_is_jalr_o = pipe_commit_packet.is_jalr;
        commit_unsupported_o = pipe_commit_packet.unsupported;
        commit_exception_valid_o = pipe_commit_packet.exception_valid;
        commit_mem_addr_o = pipe_commit_packet.mem_addr;
        commit_mem_wdata_o = pipe_commit_packet.mem_wdata;
        commit_mem_wstrb_o = pipe_commit_packet.mem_wstrb;
        commit_mem_len_o = pipe_commit_packet.mem_len;
        commit1_valid_o = pipe_commit1_valid;
        commit1_mask_o = pipe_commit_packet1.commit_mask;
        commit1_slot1_o = pipe_commit_packet1.commit_slot1;
        commit1_pc_o = pipe_commit_packet1.pc;
        commit1_instr_o = pipe_commit_packet1.instr;
        commit1_nextpc_o = pipe_commit_packet1.commit_nextpc;
        commit1_rf_wen_o = pipe_commit_packet1.rf_wen;
        commit1_rd_o = pipe_commit_packet1.arch_rd;
        commit1_wdata_o = pipe_commit_packet1.wdata;
        commit1_is_load_o = pipe_commit_packet1.is_load;
        commit1_is_store_o = pipe_commit_packet1.is_store;
        commit1_is_branch_o = pipe_commit_packet1.is_branch;
        commit1_is_jal_o = pipe_commit_packet1.is_jal;
        commit1_is_jalr_o = pipe_commit_packet1.is_jalr;
        commit1_unsupported_o = pipe_commit_packet1.unsupported;
        commit1_exception_valid_o = pipe_commit_packet1.exception_valid;
        commit1_mem_addr_o = pipe_commit_packet1.mem_addr;
        commit1_mem_wdata_o = pipe_commit_packet1.mem_wdata;
        commit1_mem_wstrb_o = pipe_commit_packet1.mem_wstrb;
        commit1_mem_len_o = pipe_commit_packet1.mem_len;
        unsupported_seen_o = pipe_unsupported_seen;
        unsupported_pc_o = pipe_unsupported_pc;
        unsupported_instr_o = pipe_unsupported_instr;
        shadow_idle_o = pipe_idle;
        halt_valid_o = pipe_halt_valid;
        halt_pc_o = pipe_halt_pc;
        halt_instr_o = pipe_halt_instr;
        halt_reason_o = pipe_halt_reason;
        debug_arch_gpr_o = pipe_arch_gpr;
        debug_arch_pc_o = pipe_arch_pc;
        dbg_inflight_rob_occ_o = pipe_rob_count;
        dbg_inflight_iq_occ_o = pipe_iq_count;
        dbg_inflight_control_pending_o = pipe_control_pending;
        dbg_inflight_memory_pending_o = pipe_memory_pending;
        dbg_inflight_commit_fire_o = pipe_commit_fire;
        dbg_inflight_commit_width_mode_o = 2'd2;
        dbg_inflight_commit2_fire_o = pipe_commit2_fire;
        dbg_inflight_commit2_trace_slot1_o = pipe_commit_fire &&
            pipe_commit_packet.commit_slot1;
        dbg_inflight_commit2_difftest_step2_o = pipe_commit_fire &&
            pipe_commit_packet.commit_slot1;
        dbg_inflight_wb_buffer_valid_o = pipe_trace_buffer_valid;
        dbg_inflight_completion_arb_no_valid_bug_o = 1'b0;
        dbg_inflight_if2pair_req_o = 1'b0;
        dbg_pipe_perf_stage_widths_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_stage_widths : '0;
        dbg_pipe_perf_lost_reasons_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_lost_reasons : '0;
        dbg_pipe_perf_occupancy_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_occupancy : '0;
        dbg_pipe_perf_events_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_events : '0;
        dbg_pipe_perf_mixed_source_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_mixed_source : '0;
        dbg_pipe_perf_structural_oracle_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_structural_oracle : '0;
        dbg_pipe_perf_structural_meta_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_structural_meta : '0;
        dbg_pipe_accounting_raw_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_accounting_raw : '0;
        dbg_pipe_accounting_selective_transaction_fire_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_accounting_selective_transaction_fire : 1'b0;
        dbg_pipe_perf_branch_pair_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_branch_pair : '0;
        dbg_pipe_perf_operand_stage_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_operand_stage : '0;
        dbg_pipe_accounting_fetch_width_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_accounting_fetch_width : '0;
        dbg_pipe_perf_trace_width_oracle_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_trace_width_oracle : '0;
        dbg_pipe_perf_lifecycle_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_lifecycle : '0;
        dbg_pipe_perf_branch_operand_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_branch_operand : '0;
        dbg_pipe_perf_branch_producer_phase_o =
            PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_branch_producer_phase : '0;
        dbg_pipe_perf_lsu_causality_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_lsu_causality : '0;
        dbg_pipe_perf_composite_load_turnover_o =
            PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_composite_load_turnover : '0;
        dbg_pipe_perf_store_admission_o =
            PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_store_admission : '0;
        dbg_pipe_perf_issue_dependency_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_issue_dependency : '0;
        dbg_pipe_perf_retirement_chain_o = '0;
        if (PIPE_PERF_OBSERVABILITY_ENABLE)
            dbg_pipe_perf_retirement_chain_o[12:0] =
                pipe_perf_retirement_chain[12:0];
        if (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE)
            dbg_pipe_perf_retirement_chain_o[31:13] =
                pipe_perf_retirement_chain[31:13];
        dbg_pipe_perf_complex_retire_pairing_o =
            PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_complex_retire_pairing : '0;
        dbg_pipe_perf_completion_ownership_o =
            PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_completion_ownership : '0;
        dbg_pipe_perf_serial_attribution_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_serial_attribution : '0;
        dbg_pipe_perf_branch_resolution_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_branch_resolution : '0;
        dbg_pipe_perf_target_line_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_target_line : '0;
        dbg_pipe_perf_frontend_residual_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_frontend_residual : '0;
        dbg_pipe_perf_frontend_no_candidate_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_frontend_no_candidate : '0;
        dbg_pipe_perf_branch_window_supply_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_branch_window_supply : '0;
        dbg_pipe_perf_branch_window_post_block_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_branch_window_post_block : '0;
        dbg_pipe_perf_reservation_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_reservation : '0;
        dbg_pipe_perf_fetch_response_credit_o =
            PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_fetch_response_credit : '0;
        dbg_pipe_perf_demand_fetch_identity_o =
            PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_demand_fetch_identity : '0;
        dbg_pipe_perf_fetch_response_service_o =
            PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_fetch_response_service : '0;
        dbg_pipe_perf_branch_window_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_branch_window : '0;
        dbg_pipe_perf_checkpoint_state_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_checkpoint_state : '0;
        dbg_pipe_perf_data_line_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_data_line : '0;
        dbg_pipe_perf_data_line_causality_o =
            PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_data_line_causality : '0;
        dbg_pipe_perf_data_line_coalescing_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_data_line_coalescing : '0;
        dbg_pipe_perf_data_line_store_origin_o =
            PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_data_line_store_origin : '0;
        dbg_pipe_perf_store_transaction_o =
            PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_store_transaction : '0;
        dbg_pipe_perf_predictor_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_predictor : '0;
        dbg_pipe_perf_predictor_detail_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_predictor_detail : '0;
        dbg_pipe_perf_predictor_local_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_predictor_local : '0;
        dbg_pipe_perf_predictor_multihistory_o =
            PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_predictor_multihistory : '0;
        dbg_pipe_perf_singleton_coalesce_o =
            PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_singleton_coalesce : '0;
        dbg_pipe_perf_singleton_target_pc_o =
            PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_singleton_target_pc : '0;
        dbg_pipe_perf_singleton_target_instr_o =
            PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_singleton_target_instr : '0;
        dbg_pipe_perf_partial_pair_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_partial_pair : '0;
        dbg_pipe_perf_partial_pair_pc_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_partial_pair_pc : '0;
        dbg_pipe_perf_partial_pair_instr_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_partial_pair_instr : '0;
        dbg_pipe_perf_cross_line_pair_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_cross_line_pair : '0;
        dbg_pipe_perf_cross_line_carry_o =
            (PIPE_PERF_ACCOUNTING_ENABLE || PIPE_PERF_OBSERVABILITY_ENABLE) ?
            pipe_perf_cross_line_carry : '0;
        dbg_pipe_perf_dispatch_pc_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_dispatch_pc : '0;
        dbg_pipe_perf_dispatch_instr_o = PIPE_PERF_OBSERVABILITY_ENABLE ?
            pipe_perf_dispatch_instr : '0;
    end

    /* verilator lint_off UNUSED */
    wire pipe_commit_event_unused = ^pipe_commit_event;
    /* verilator lint_on UNUSED */
`else
    assign commit_rd_o = commit_rd;
    assign shadow_idle_o = shadow_idle;
    assign dbg_inflight_rob_occ_o = rob_count;
    assign dbg_inflight_iq_occ_o = iq_count;
    assign dbg_inflight_iq_ready_occ_o = iq_ready_count;
    assign dbg_inflight_iq_ready_alu_count_o = iq_ready_alu_count;
    assign dbg_inflight_iq_ready_lsu_count_o = iq_ready_lsu_count;
    assign dbg_inflight_iq_ready_bru_count_o = iq_ready_bru_count;
    assign dbg_inflight_iq_ready_csr_sys_count_o = iq_ready_csr_sys_count;
    assign dbg_inflight_iq_ready_any_count_o = iq_ready_any_count;
    assign dbg_inflight_issue_candidate_count_o = issue_candidate_count;
    assign dbg_inflight_issue_multi_candidate_o = issue_multi_candidate;
    assign dbg_inflight_dispatch_candidate_o = dispatch_candidate;
    assign dbg_inflight_dispatch_fire_o = rename_fire;
    assign dbg_inflight_iq_enqueue_o = iq_enqueue;
    assign dbg_inflight_issue_valid_o = iq_issue_valid;
    assign dbg_inflight_issue_ready_o = iq_issue_ready;
    assign dbg_inflight_issue_fire_o = issue_fire;
    assign dbg_inflight_issue_fu_ready_o = issue_fu_ready;
    assign dbg_inflight_execution_path_clear_o = execution_path_clear;
    assign dbg_inflight_rob_full_o = rob_full;
    assign dbg_inflight_iq_full_o = iq_full;
    assign dbg_inflight_wb_buffer_valid_o = wb_buffer_valid;
    assign dbg_inflight_wb_buffer_full_o = wb_buffer_full;
    assign dbg_inflight_wb_accept_o = wb_accept;
    assign dbg_inflight_wb_stall_o = wb_stall;
    assign dbg_inflight_alu_busy_o = alu_busy;
    assign dbg_inflight_bru_busy_o = bru_busy;
    assign dbg_inflight_lsu_busy_o = lsu_busy;
    assign dbg_inflight_csr_busy_o = csr_busy;
    assign dbg_inflight_control_pending_o = shadow_control_pending;
    assign dbg_inflight_memory_pending_o = shadow_memory_pending;
    assign dbg_inflight_commit_fire_o = commit_valid_o;
    assign dbg_inflight_commit_width_mode_o = commit_width_mode;
    assign dbg_inflight_commit2_candidate_o = commit2_candidate;
    assign dbg_inflight_commit2_fire_o = commit2_fire;
    assign dbg_inflight_commit2_slot0_only_o = commit2_slot0_only;
    assign dbg_inflight_commit2_block_slot0_not_ready_o =
        commit2_block_slot0_not_ready;
    assign dbg_inflight_commit2_block_slot1_not_ready_o =
        commit2_block_slot1_not_ready;
    assign dbg_inflight_commit2_block_slot0_complex_o =
        commit2_block_slot0_complex;
    assign dbg_inflight_commit2_block_slot1_complex_o =
        commit2_block_slot1_complex;
    assign dbg_inflight_commit2_rrat_update2_o = commit2_rrat_update2;
    assign dbg_inflight_commit2_freelist_release2_o = commit2_freelist_release2;
    assign dbg_inflight_commit2_same_rd_waw_o = commit2_same_rd_waw;
    assign dbg_inflight_commit2_duplicate_release_bug_o =
        commit2_duplicate_release_bug;
    assign dbg_inflight_commit2_slot1_without_slot0_bug_o =
        commit2_slot1_without_slot0_bug;
    assign dbg_inflight_commit2_complex_slot_bug_o = commit2_complex_slot_bug;
    assign dbg_inflight_commit2_trace_slot1_o = commit2_trace_slot1;
    assign dbg_inflight_commit2_difftest_step2_o = commit2_difftest_step2;
    assign dbg_pipe_perf_stage_widths_o = '0;
    assign dbg_pipe_perf_lost_reasons_o = '0;
    assign dbg_pipe_perf_occupancy_o = '0;
    assign dbg_pipe_perf_events_o = '0;
    assign dbg_pipe_perf_mixed_source_o = '0;
    assign dbg_pipe_perf_structural_oracle_o = '0;
    assign dbg_pipe_perf_structural_meta_o = '0;
    assign dbg_pipe_accounting_raw_o = '0;
    assign dbg_pipe_accounting_selective_transaction_fire_o = 1'b0;
    assign dbg_pipe_perf_branch_pair_o = '0;
    assign dbg_pipe_perf_operand_stage_o = '0;
    assign dbg_pipe_accounting_fetch_width_o = '0;
    assign dbg_pipe_perf_trace_width_oracle_o = '0;
    assign dbg_pipe_perf_lifecycle_o = '0;
    assign dbg_pipe_perf_branch_operand_o = '0;
    assign dbg_pipe_perf_branch_producer_phase_o = '0;
    assign dbg_pipe_perf_lsu_causality_o = '0;
    assign dbg_pipe_perf_composite_load_turnover_o = '0;
    assign dbg_pipe_perf_store_admission_o = '0;
    assign dbg_pipe_perf_issue_dependency_o = '0;
    assign dbg_pipe_perf_retirement_chain_o = '0;
    assign dbg_pipe_perf_complex_retire_pairing_o = '0;
    assign dbg_pipe_perf_completion_ownership_o = '0;
    assign dbg_pipe_perf_serial_attribution_o = '0;
    assign dbg_pipe_perf_branch_resolution_o = '0;
    assign dbg_pipe_perf_target_line_o = '0;
    assign dbg_pipe_perf_frontend_residual_o = '0;
    assign dbg_pipe_perf_frontend_no_candidate_o = '0;
    assign dbg_pipe_perf_branch_window_supply_o = '0;
    assign dbg_pipe_perf_branch_window_post_block_o = '0;
    assign dbg_pipe_perf_reservation_o = '0;
    assign dbg_pipe_perf_fetch_response_credit_o = '0;
    assign dbg_pipe_perf_demand_fetch_identity_o = '0;
    assign dbg_pipe_perf_fetch_response_service_o = '0;
    assign dbg_pipe_perf_branch_window_o = '0;
    assign dbg_pipe_perf_checkpoint_state_o = '0;
    assign dbg_pipe_perf_data_line_o = '0;
    assign dbg_pipe_perf_data_line_causality_o = '0;
    assign dbg_pipe_perf_data_line_coalescing_o = '0;
    assign dbg_pipe_perf_data_line_store_origin_o = '0;
    assign dbg_pipe_perf_store_transaction_o = '0;
    assign dbg_pipe_perf_predictor_o = '0;
    assign dbg_pipe_perf_predictor_detail_o = '0;
    assign dbg_pipe_perf_predictor_local_o = '0;
    assign dbg_pipe_perf_predictor_multihistory_o = '0;
    assign dbg_pipe_perf_singleton_coalesce_o = '0;
    assign dbg_pipe_perf_singleton_target_pc_o = '0;
    assign dbg_pipe_perf_singleton_target_instr_o = '0;
    assign dbg_pipe_perf_partial_pair_o = '0;
    assign dbg_pipe_perf_partial_pair_pc_o = '0;
    assign dbg_pipe_perf_partial_pair_instr_o = '0;
    assign dbg_pipe_perf_cross_line_pair_o = '0;
    assign dbg_pipe_perf_cross_line_carry_o = '0;
    assign dbg_pipe_perf_dispatch_pc_o = '0;
    assign dbg_pipe_perf_dispatch_instr_o = '0;
    assign dbg_inflight_alu_issue_o = alu_issue;
    assign dbg_inflight_bru_issue_o = bru_issue;
    assign dbg_inflight_lsu_issue_o = lsu_issue;
    assign dbg_inflight_csr_issue_o = csr_issue;
    assign dbg_inflight_alu_done_o = alu_done;
    assign dbg_inflight_bru_done_o = bru_done;
    assign dbg_inflight_lsu_done_o = lsu_done;
    assign dbg_inflight_csr_done_o = csr_done;
    assign dbg_inflight_wb_conflict_o = wb_conflict;
    assign dbg_inflight_completion_grant_alu_o = completion_grant_alu;
    assign dbg_inflight_completion_grant_bru_o = completion_grant_bru;
    assign dbg_inflight_completion_grant_lsu_o = completion_grant_lsu;
    assign dbg_inflight_completion_grant_csr_o = completion_grant_csr;
    assign dbg_inflight_completion_hold_alu_o = completion_hold_alu;
    assign dbg_inflight_completion_hold_bru_o = completion_hold_bru;
    assign dbg_inflight_completion_hold_lsu_o = completion_hold_lsu;
    assign dbg_inflight_completion_hold_csr_o = completion_hold_csr;
    assign dbg_inflight_completion_oldest_arb_o = completion_oldest_arb;
    assign dbg_inflight_completion_fixed_arb_o = completion_fixed_arb;
    assign dbg_inflight_completion_oldest_grant_alu_o = completion_oldest_grant_alu;
    assign dbg_inflight_completion_oldest_grant_bru_o = completion_oldest_grant_bru;
    assign dbg_inflight_completion_oldest_grant_lsu_o = completion_oldest_grant_lsu;
    assign dbg_inflight_completion_oldest_grant_csr_o = completion_oldest_grant_csr;
    assign dbg_inflight_completion_fixed_would_choose_alu_o = completion_fixed_would_choose_alu;
    assign dbg_inflight_completion_fixed_would_choose_bru_o = completion_fixed_would_choose_bru;
    assign dbg_inflight_completion_fixed_would_choose_lsu_o = completion_fixed_would_choose_lsu;
    assign dbg_inflight_completion_fixed_would_choose_csr_o = completion_fixed_would_choose_csr;
    assign dbg_inflight_completion_oldest_differs_from_fixed_o =
        completion_oldest_differs_from_fixed;
    assign dbg_inflight_duplicate_completion_tag_o = duplicate_completion_tag;
    assign dbg_inflight_completion_arb_no_valid_bug_o = completion_arb_no_valid_bug;
    assign dbg_inflight_issue0_fire_o = issue0_fire;
    assign dbg_inflight_issue1_fire_o = issue1_fire;
    assign dbg_inflight_issue2_fire_o = issue2_fire;
    assign dbg_inflight_alu_alu_dual_issue_o = alu_alu_dual_issue;
    assign dbg_inflight_alu_lsu_dual_issue_o = alu_lsu_dual_issue;
    assign dbg_inflight_dual_issue_candidate_o = dual_issue_candidate;
    assign dbg_inflight_dual_issue_candidate_alu_alu_o = dual_issue_candidate_alu_alu;
    assign dbg_inflight_dual_issue_candidate_alu_lsu_o = dual_issue_candidate_alu_lsu;
    assign dbg_inflight_dual_issue_candidate_lsu_alu_o = dual_issue_candidate_lsu_alu;
    assign dbg_inflight_dual_issue_fire_alu_alu_o = dual_issue_fire_alu_alu;
    assign dbg_inflight_dual_issue_fire_alu_lsu_o = dual_issue_fire_alu_lsu;
    assign dbg_inflight_dual_issue_fire_lsu_alu_o = dual_issue_fire_lsu_alu;
    assign dbg_inflight_alu0_issue_o = alu0_issue;
    assign dbg_inflight_alu1_issue_o = alu1_issue;
    assign dbg_inflight_alu0_busy_o = alu0_busy;
    assign dbg_inflight_alu1_busy_o = alu1_busy;
    assign dbg_inflight_alu0_done_o = alu0_done;
    assign dbg_inflight_alu1_done_o = alu1_done;
    assign dbg_inflight_alu0_alu1_done_same_cycle_o = alu0_alu1_done_same_cycle;
    assign dbg_inflight_alu0_alu1_wb_conflict_o = alu0_alu1_wb_conflict;
    assign dbg_inflight_completion_grant_alu0_o = completion_grant_alu0;
    assign dbg_inflight_completion_grant_alu1_o = completion_grant_alu1;
    assign dbg_inflight_completion_hold_alu0_o = completion_hold_alu0;
    assign dbg_inflight_completion_hold_alu1_o = completion_hold_alu1;
    assign dbg_inflight_issue1_suppressed_o = issue1_suppressed;
    assign dbg_inflight_issue1_suppressed_by_policy_o = issue1_suppressed_by_policy;
    assign dbg_inflight_issue1_suppressed_by_fu_busy_o = issue1_suppressed_by_fu_busy;
    assign dbg_inflight_issue1_suppressed_by_wb_o = issue1_suppressed_by_wb;
    assign dbg_inflight_dual_issue_blocked_by_prf_o = dual_issue_blocked_by_prf;
    assign dbg_inflight_dual_issue_blocked_by_alu_busy_o = dual_issue_blocked_by_alu_busy;
    assign dbg_inflight_dual_issue_blocked_by_alu0_busy_o = dual_issue_blocked_by_alu0_busy;
    assign dbg_inflight_dual_issue_blocked_by_alu1_busy_o = dual_issue_blocked_by_alu1_busy;
    assign dbg_inflight_dual_issue_blocked_by_lsu_busy_o = dual_issue_blocked_by_lsu_busy;
    assign dbg_inflight_dual_issue_blocked_by_wb_o = dual_issue_blocked_by_wb;
    assign dbg_inflight_dual_issue_blocked_by_completion_clear_o =
        dual_issue_blocked_by_completion_clear;
    assign dbg_inflight_dual_issue_blocked_by_serial_o = dual_issue_blocked_by_serial;
    assign dbg_inflight_wb_conflict_alu0_alu1_o = wb_conflict_alu0_alu1;
    assign dbg_inflight_wb_conflict_alu_lsu_o = wb_conflict_alu_lsu;
    assign dbg_inflight_wb_conflict_bru_data_o = wb_conflict_bru_data;
    assign dbg_inflight_alu1_single_issue_o = alu1_single_issue;
    assign dbg_inflight_alu1_single_issue_when_alu0_busy_o =
        alu1_single_issue_when_alu0_busy;
    assign dbg_inflight_alu1_single_issue_when_alu0_idle_o =
        alu1_single_issue_when_alu0_idle;
    assign dbg_inflight_alu_single_issue_redirect_to_alu1_o =
        alu_single_issue_redirect_to_alu1;
    assign dbg_inflight_alu0_single_issue_o = alu0_single_issue;
    assign dbg_inflight_alu0_single_issue_when_alu1_idle_o =
        alu0_single_issue_when_alu1_idle;
    assign dbg_inflight_alu_sched_balance_opportunity_o =
        alu_sched_balance_opportunity;
    assign dbg_inflight_alu_sched_balance_fire_o = alu_sched_balance_fire;
    assign dbg_inflight_alu_sched_balance_blocked_both_busy_o =
        alu_sched_balance_blocked_both_busy;
    assign dbg_inflight_alu_sched_balance_blocked_wb_o =
        alu_sched_balance_blocked_wb;
    assign dbg_inflight_dispatch_width_mode_o = dispatch_width_mode;
    assign dbg_inflight_dispatch2_candidate_o = dispatch2_candidate;
    assign dbg_inflight_dispatch2_fire_o = dispatch2_fire;
    assign dbg_inflight_dispatch2_slot0_fire_o = dispatch2_slot0_fire;
    assign dbg_inflight_dispatch2_slot1_fire_o = dispatch2_slot1_fire;
    assign dbg_inflight_dispatch2_slot1_retained_o = dispatch2_slot1_retained;
    assign dbg_inflight_dispatch2_blocked_by_rob_o = dispatch2_blocked_by_rob;
    assign dbg_inflight_dispatch2_blocked_by_iq_o = dispatch2_blocked_by_iq;
    assign dbg_inflight_dispatch2_blocked_by_freelist_o = dispatch2_blocked_by_freelist;
    assign dbg_inflight_dispatch2_blocked_by_serial_o = dispatch2_blocked_by_serial;
    assign dbg_inflight_dispatch2_blocked_by_unsupported_pair_o =
        dispatch2_blocked_by_unsupported_pair;
    assign dbg_inflight_dispatch2_partial_slot0_only_o =
        dispatch2_partial_slot0_only;
    assign dbg_inflight_dispatch2_slot1_retained_due_to_rob_o =
        dispatch2_slot1_retained_due_to_rob;
    assign dbg_inflight_dispatch2_slot1_retained_due_to_iq_o =
        dispatch2_slot1_retained_due_to_iq;
    assign dbg_inflight_dispatch2_slot1_retained_due_to_freelist_o =
        dispatch2_slot1_retained_due_to_freelist;
    assign dbg_inflight_dispatch2_slot1_retained_due_to_serial_o =
        dispatch2_slot1_retained_due_to_serial;
    assign dbg_inflight_dispatch2_retained_replayed_as_slot0_o =
        dispatch2_retained_replayed_as_slot0;
    assign dbg_inflight_dispatch2_retained_duplicate_rename_bug_o =
        dispatch2_retained_duplicate_rename_bug;
    assign dbg_inflight_dispatch2_retained_duplicate_phys_bug_o =
        dispatch2_retained_duplicate_phys_bug;
    assign dbg_inflight_dispatch2_retained_duplicate_rob_bug_o =
        dispatch2_retained_duplicate_rob_bug;
    assign dbg_inflight_dispatch2_retained_flush_clear_o =
        dispatch2_retained_flush_clear;
    assign dbg_inflight_rename2_fire_o = rename2_fire;
    assign dbg_inflight_rename2_same_cycle_raw_o = rename2_same_cycle_raw;
    assign dbg_inflight_rename2_same_cycle_waw_o = rename2_same_cycle_waw;
    assign dbg_inflight_rob_alloc2_o = rob_alloc2;
    assign dbg_inflight_iq_enqueue2_o = iq_enqueue2;
    assign dbg_inflight_freelist_alloc2_o = freelist_alloc2;
    assign dbg_inflight_freelist_alloc1_due_to_partial_o =
        freelist_alloc1_due_to_partial;
    assign dbg_inflight_rob_alloc1_due_to_partial_o =
        rob_alloc1_due_to_partial;
    assign dbg_inflight_iq_enqueue1_due_to_partial_o =
        iq_enqueue1_due_to_partial;
    assign dbg_inflight_if2_bundle_valid_o = if2_bundle_valid;
    assign dbg_inflight_if2_downstream_accept2_o = if2_downstream_accept2;
    assign dbg_inflight_if2_downstream_accept1_o = if2_downstream_accept1;
    assign dbg_inflight_if2_downstream_stall_o = if2_downstream_stall;
    assign dbg_inflight_if2_slot1_retained_o = if2_slot1_retained;
    assign dbg_inflight_if2_slot1_replayed_as_slot0_o = if2_slot1_replayed_as_slot0;
    assign dbg_inflight_if2_redirect_flush_o = if2_redirect_flush;
    assign dbg_inflight_if2_stale_slot_kill_o = if2_stale_slot_kill;
    assign dbg_inflight_if2pair_req_o = if2pair_req;
    assign dbg_inflight_if2pair_resp_o = if2pair_resp;
    assign dbg_inflight_if2pair_resp_drop_o = if2pair_resp_drop;
    assign dbg_inflight_if2pair_stale_resp_kill_o = if2pair_stale_resp_kill;
    assign dbg_inflight_if2pair_valid_mask_11_o = if2pair_valid_mask_11;
    assign dbg_inflight_if2pair_valid_mask_01_o = if2pair_valid_mask_01;
    assign dbg_inflight_if2pair_upper_half_single_o = if2pair_upper_half_single;
    assign dbg_inflight_if2pair_downstream_accept2_o = if2pair_downstream_accept2;
    assign dbg_inflight_if2pair_downstream_accept1_o = if2pair_downstream_accept1;
    assign dbg_inflight_if2pair_downstream_stall_o = if2pair_downstream_stall;
    assign dbg_inflight_if2pair_slot1_retained_o = if2pair_slot1_retained;
    assign dbg_inflight_if2pair_slot1_replayed_as_slot0_o = if2pair_slot1_replayed_as_slot0;
    assign dbg_inflight_if2pair_redirect_flush_o = if2pair_redirect_flush;
    assign dbg_inflight_if2pair_slot1_only_bug_o = if2pair_slot1_only_bug;
    assign dbg_inflight_if2pair_stale_accept_bug_o = if2pair_stale_accept_bug;
    assign dbg_inflight_if2pair_fetch_endian_bug_o = if2pair_fetch_endian_bug;
    assign dbg_inflight_if2pair_duplicate_replay_bug_o = if2pair_duplicate_replay_bug;
    assign dbg_inflight_duplicate_issue_guard_o = duplicate_issue_guard;

`ifdef NPC_OOO_FRONTEND_IF2_PAIR
    localparam bit USE_EXTERNAL_PMEM_IFETCH = 1'b0;
`else
    localparam bit USE_EXTERNAL_PMEM_IFETCH = USE_PMEM_IFETCH;
`endif
    assign pmem_fetch_ready = USE_EXTERNAL_PMEM_IFETCH ? shadow_program_ready : 1'b0;
    assign pmem_fetch_stop =
        ebreak_seen_q || unsupported_seen_o || halt_valid_o || shadow_control_pending || shadow_memory_pending;

    assign shadow_program_valid =
        USE_EXTERNAL_PMEM_IFETCH ?
            pmem_fetch_valid :
            program_valid_i;
    assign shadow_program_pc = USE_EXTERNAL_PMEM_IFETCH ? pmem_fetch_pc : program_pc_i;
    assign shadow_program_instr = USE_EXTERNAL_PMEM_IFETCH ? pmem_fetch_instr : program_instr_i;
    assign program_ready_o = USE_EXTERNAL_PMEM_IFETCH ? 1'b0 : shadow_program_ready;
    assign halt_valid_o = ebreak_seen_q && shadow_idle;
    assign halt_pc_o = ebreak_pc_q;
    assign halt_instr_o = ebreak_instr_q;
    assign halt_reason_o = halt_valid_o ? HALT_REASON_EBREAK : 4'd0;
    assign shadow_ebreak_commit =
        commit_event.control_event_valid &&
        (commit_event.control_event == BBUS_OOO_CTRL_EBREAK);

    ooo_pmem_ifetch #(
        .RESET_VECTOR(RESET_VECTOR),
        .DPI_CHANNEL(0)
    ) u_pmem_ifetch (
        .clk(clk),
        .reset(reset),
        .fetch_valid_o(pmem_fetch_valid),
        .fetch_pc_o(pmem_fetch_pc),
        .fetch_instr_o(pmem_fetch_instr),
        .fetch_ready_i(pmem_fetch_ready),
        .stop_i(pmem_fetch_stop),
        .redirect_valid_i(shadow_commit_redirect_valid),
        .redirect_pc_i(shadow_commit_redirect_pc),
        .debug_req_valid_o(pmem_req_valid),
        .debug_resp_valid_o(pmem_resp_valid),
        .debug_fetch_pc_o(pmem_debug_fetch_pc)
    );

    cpu_top_ooo_shadow #(
        .RESET_VECTOR(RESET_VECTOR),
        .ALU_LATENCY(ALU_LATENCY),
        .ALU1_LATENCY(ALU1_LATENCY)
    ) u_shadow (
        .clk(clk),
        .rst_n(rst_n),
        .program_valid_i(shadow_program_valid),
        .program_pc_i(shadow_program_pc),
        .program_instr_i(shadow_program_instr),
        .program_ready_o(shadow_program_ready),
        .trace_ready_i(commit_ready_i),
        .debug_commit_enable_i(1'b1),
        .debug_arch_idx_i(bbus_ooo_arch_reg_t'(debug_arch_idx_i)),
        .debug_phys_idx_i(`BBUS_OOO_PHYS_ZERO),
        .debug_prf_phys_idx_i(`BBUS_OOO_PHYS_ZERO),
        .debug_rob_idx_i('0),
        .commit_valid_o(commit_valid_o),
        .commit_mask_o(commit_mask_o),
        .commit_slot1_o(commit_slot1_o),
        .commit_pc_o(commit_pc_o),
        .commit_instr_o(commit_instr_o),
        .commit_nextpc_o(commit_nextpc_o),
        .commit_rf_wen_o(commit_rf_wen_o),
        .commit_rd_o(commit_rd),
        .commit_wdata_o(commit_wdata_o),
        .commit_is_load_o(commit_is_load_o),
        .commit_is_store_o(commit_is_store_o),
        .commit_is_branch_o(commit_is_branch_o),
        .commit_is_jal_o(commit_is_jal_o),
        .commit_is_jalr_o(commit_is_jalr_o),
        .commit_mem_addr_o(commit_mem_addr_o),
        .commit_mem_wdata_o(commit_mem_wdata_o),
        .commit_mem_wstrb_o(commit_mem_wstrb_o),
        .commit_mem_len_o(commit_mem_len_o),
        .commit_unsupported_o(commit_unsupported_o),
        .commit_exception_valid_o(commit_exception_valid_o),
        .control_pending_o(shadow_control_pending),
        .memory_pending_o(shadow_memory_pending),
        .commit_redirect_valid_o(shadow_commit_redirect_valid),
        .commit_redirect_pc_o(shadow_commit_redirect_pc),
        .trace_valid_o(trace_valid),
        .trace_packet_o(trace_packet),
        .debug_commit_event_o(commit_event),
        .debug_packet_buffer_valid_o(packet_buffer_valid),
        .debug_last_packet_accepted_o(last_packet_accepted),
        .debug_last_commit_dropped_o(last_commit_dropped),
        .debug_shadow_idle_o(shadow_idle),
        .debug_unsupported_seen_o(unsupported_seen_o),
        .debug_unsupported_pc_o(unsupported_pc_o),
        .debug_unsupported_instr_o(unsupported_instr_o),
        .debug_arch_gpr_o(debug_arch_gpr_o),
        .debug_arch_pc_o(debug_arch_pc_o),
        .debug_dispatch_candidate_o(dispatch_candidate),
        .debug_rename_fire_o(rename_fire),
        .debug_renamed_uop_o(renamed_uop),
        .debug_rob_done_o(rob_done),
        .debug_rob_result_o(rob_result),
        .debug_rob_count_o(rob_count),
        .debug_iq_count_o(iq_count),
        .debug_iq_ready_count_o(iq_ready_count),
        .debug_iq_ready_alu_count_o(iq_ready_alu_count),
        .debug_iq_ready_lsu_count_o(iq_ready_lsu_count),
        .debug_iq_ready_bru_count_o(iq_ready_bru_count),
        .debug_iq_ready_csr_sys_count_o(iq_ready_csr_sys_count),
        .debug_iq_ready_any_count_o(iq_ready_any_count),
        .debug_issue_candidate_count_o(issue_candidate_count),
        .debug_issue_multi_candidate_o(issue_multi_candidate),
        .debug_rob_full_o(rob_full),
        .debug_iq_full_o(iq_full),
        .debug_wb_buffer_full_o(wb_buffer_full),
        .debug_wb_buffer_valid_o(wb_buffer_valid),
        .debug_alu_busy_o(alu_busy),
        .debug_branch_busy_o(bru_busy),
        .debug_lsu_busy_o(lsu_busy),
        .debug_csr_busy_o(csr_busy),
        .debug_alu_completion_valid_o(alu_done),
        .debug_branch_completion_valid_o(bru_done),
        .debug_lsu_completion_valid_o(lsu_done),
        .debug_csr_completion_valid_o(csr_done),
        .debug_execution_path_clear_o(execution_path_clear),
        .debug_dispatch_valid_o(dispatch_valid),
        .debug_dispatch_ready_o(dispatch_ready),
        .debug_iq_enqueue_o(iq_enqueue),
        .debug_iq_issue_valid_o(iq_issue_valid),
        .debug_iq_issue_ready_o(iq_issue_ready),
        .debug_issue_fire_o(issue_fire),
        .debug_issue_fu_ready_o(issue_fu_ready),
        .debug_wb_accept_o(wb_accept),
        .debug_wb_stall_o(wb_stall),
        .debug_alu_issue_o(alu_issue),
        .debug_branch_issue_o(bru_issue),
        .debug_lsu_issue_o(lsu_issue),
        .debug_csr_issue_o(csr_issue),
        .debug_wb_conflict_o(wb_conflict),
        .debug_completion_grant_alu_o(completion_grant_alu),
        .debug_completion_grant_bru_o(completion_grant_bru),
        .debug_completion_grant_lsu_o(completion_grant_lsu),
        .debug_completion_grant_csr_o(completion_grant_csr),
        .debug_completion_hold_alu_o(completion_hold_alu),
        .debug_completion_hold_bru_o(completion_hold_bru),
        .debug_completion_hold_lsu_o(completion_hold_lsu),
        .debug_completion_hold_csr_o(completion_hold_csr),
        .debug_completion_oldest_arb_o(completion_oldest_arb),
        .debug_completion_fixed_arb_o(completion_fixed_arb),
        .debug_completion_oldest_grant_alu_o(completion_oldest_grant_alu),
        .debug_completion_oldest_grant_bru_o(completion_oldest_grant_bru),
        .debug_completion_oldest_grant_lsu_o(completion_oldest_grant_lsu),
        .debug_completion_oldest_grant_csr_o(completion_oldest_grant_csr),
        .debug_completion_fixed_would_choose_alu_o(completion_fixed_would_choose_alu),
        .debug_completion_fixed_would_choose_bru_o(completion_fixed_would_choose_bru),
        .debug_completion_fixed_would_choose_lsu_o(completion_fixed_would_choose_lsu),
        .debug_completion_fixed_would_choose_csr_o(completion_fixed_would_choose_csr),
        .debug_completion_oldest_differs_from_fixed_o(completion_oldest_differs_from_fixed),
        .debug_duplicate_completion_tag_o(duplicate_completion_tag),
        .debug_completion_arb_no_valid_bug_o(completion_arb_no_valid_bug),
        .debug_issue0_fire_o(issue0_fire),
        .debug_issue1_fire_o(issue1_fire),
        .debug_issue2_fire_o(issue2_fire),
        .debug_alu_alu_dual_issue_o(alu_alu_dual_issue),
        .debug_alu_lsu_dual_issue_o(alu_lsu_dual_issue),
        .debug_dual_issue_candidate_o(dual_issue_candidate),
        .debug_dual_issue_candidate_alu_alu_o(dual_issue_candidate_alu_alu),
        .debug_dual_issue_candidate_alu_lsu_o(dual_issue_candidate_alu_lsu),
        .debug_dual_issue_candidate_lsu_alu_o(dual_issue_candidate_lsu_alu),
        .debug_dual_issue_fire_alu_alu_o(dual_issue_fire_alu_alu),
        .debug_dual_issue_fire_alu_lsu_o(dual_issue_fire_alu_lsu),
        .debug_dual_issue_fire_lsu_alu_o(dual_issue_fire_lsu_alu),
        .debug_alu0_issue_o(alu0_issue),
        .debug_alu1_issue_o(alu1_issue),
        .debug_alu0_busy_o(alu0_busy),
        .debug_alu1_busy_o(alu1_busy),
        .debug_alu0_done_o(alu0_done),
        .debug_alu1_done_o(alu1_done),
        .debug_alu0_alu1_done_same_cycle_o(alu0_alu1_done_same_cycle),
        .debug_alu0_alu1_wb_conflict_o(alu0_alu1_wb_conflict),
        .debug_completion_grant_alu0_o(completion_grant_alu0),
        .debug_completion_grant_alu1_o(completion_grant_alu1),
        .debug_completion_hold_alu0_o(completion_hold_alu0),
        .debug_completion_hold_alu1_o(completion_hold_alu1),
        .debug_issue1_suppressed_o(issue1_suppressed),
        .debug_issue1_suppressed_by_policy_o(issue1_suppressed_by_policy),
        .debug_issue1_suppressed_by_fu_busy_o(issue1_suppressed_by_fu_busy),
        .debug_issue1_suppressed_by_wb_o(issue1_suppressed_by_wb),
        .debug_dual_issue_blocked_by_prf_o(dual_issue_blocked_by_prf),
        .debug_dual_issue_blocked_by_alu_busy_o(dual_issue_blocked_by_alu_busy),
        .debug_dual_issue_blocked_by_alu0_busy_o(dual_issue_blocked_by_alu0_busy),
        .debug_dual_issue_blocked_by_alu1_busy_o(dual_issue_blocked_by_alu1_busy),
        .debug_dual_issue_blocked_by_lsu_busy_o(dual_issue_blocked_by_lsu_busy),
        .debug_dual_issue_blocked_by_wb_o(dual_issue_blocked_by_wb),
        .debug_dual_issue_blocked_by_completion_clear_o(dual_issue_blocked_by_completion_clear),
        .debug_dual_issue_blocked_by_serial_o(dual_issue_blocked_by_serial),
        .debug_wb_conflict_alu0_alu1_o(wb_conflict_alu0_alu1),
        .debug_wb_conflict_alu_lsu_o(wb_conflict_alu_lsu),
        .debug_wb_conflict_bru_data_o(wb_conflict_bru_data),
        .debug_alu1_single_issue_o(alu1_single_issue),
        .debug_alu1_single_issue_when_alu0_busy_o(alu1_single_issue_when_alu0_busy),
        .debug_alu1_single_issue_when_alu0_idle_o(alu1_single_issue_when_alu0_idle),
        .debug_alu_single_issue_redirect_to_alu1_o(alu_single_issue_redirect_to_alu1),
        .debug_alu0_single_issue_o(alu0_single_issue),
        .debug_alu0_single_issue_when_alu1_idle_o(alu0_single_issue_when_alu1_idle),
        .debug_alu_sched_balance_opportunity_o(alu_sched_balance_opportunity),
        .debug_alu_sched_balance_fire_o(alu_sched_balance_fire),
        .debug_alu_sched_balance_blocked_both_busy_o(alu_sched_balance_blocked_both_busy),
        .debug_alu_sched_balance_blocked_wb_o(alu_sched_balance_blocked_wb),
        .debug_dispatch_width_mode_o(dispatch_width_mode),
        .debug_dispatch2_candidate_o(dispatch2_candidate),
        .debug_dispatch2_fire_o(dispatch2_fire),
        .debug_dispatch2_slot0_fire_o(dispatch2_slot0_fire),
        .debug_dispatch2_slot1_fire_o(dispatch2_slot1_fire),
        .debug_dispatch2_slot1_retained_o(dispatch2_slot1_retained),
        .debug_dispatch2_blocked_by_rob_o(dispatch2_blocked_by_rob),
        .debug_dispatch2_blocked_by_iq_o(dispatch2_blocked_by_iq),
        .debug_dispatch2_blocked_by_freelist_o(dispatch2_blocked_by_freelist),
        .debug_dispatch2_blocked_by_serial_o(dispatch2_blocked_by_serial),
        .debug_dispatch2_blocked_by_unsupported_pair_o(dispatch2_blocked_by_unsupported_pair),
        .debug_dispatch2_partial_slot0_only_o(dispatch2_partial_slot0_only),
        .debug_dispatch2_slot1_retained_due_to_rob_o(dispatch2_slot1_retained_due_to_rob),
        .debug_dispatch2_slot1_retained_due_to_iq_o(dispatch2_slot1_retained_due_to_iq),
        .debug_dispatch2_slot1_retained_due_to_freelist_o(dispatch2_slot1_retained_due_to_freelist),
        .debug_dispatch2_slot1_retained_due_to_serial_o(dispatch2_slot1_retained_due_to_serial),
        .debug_dispatch2_retained_replayed_as_slot0_o(dispatch2_retained_replayed_as_slot0),
        .debug_dispatch2_retained_duplicate_rename_bug_o(dispatch2_retained_duplicate_rename_bug),
        .debug_dispatch2_retained_duplicate_phys_bug_o(dispatch2_retained_duplicate_phys_bug),
        .debug_dispatch2_retained_duplicate_rob_bug_o(dispatch2_retained_duplicate_rob_bug),
        .debug_dispatch2_retained_flush_clear_o(dispatch2_retained_flush_clear),
        .debug_rename2_fire_o(rename2_fire),
        .debug_rename2_same_cycle_raw_o(rename2_same_cycle_raw),
        .debug_rename2_same_cycle_waw_o(rename2_same_cycle_waw),
        .debug_rob_alloc2_o(rob_alloc2),
        .debug_iq_enqueue2_o(iq_enqueue2),
        .debug_freelist_alloc2_o(freelist_alloc2),
        .debug_freelist_alloc1_due_to_partial_o(freelist_alloc1_due_to_partial),
        .debug_rob_alloc1_due_to_partial_o(rob_alloc1_due_to_partial),
        .debug_iq_enqueue1_due_to_partial_o(iq_enqueue1_due_to_partial),
        .debug_if2_bundle_valid_o(if2_bundle_valid),
        .debug_if2_downstream_accept2_o(if2_downstream_accept2),
        .debug_if2_downstream_accept1_o(if2_downstream_accept1),
        .debug_if2_downstream_stall_o(if2_downstream_stall),
        .debug_if2_slot1_retained_o(if2_slot1_retained),
        .debug_if2_slot1_replayed_as_slot0_o(if2_slot1_replayed_as_slot0),
        .debug_if2_redirect_flush_o(if2_redirect_flush),
        .debug_if2_stale_slot_kill_o(if2_stale_slot_kill),
        .debug_if2pair_req_o(if2pair_req),
        .debug_if2pair_resp_o(if2pair_resp),
        .debug_if2pair_resp_drop_o(if2pair_resp_drop),
        .debug_if2pair_stale_resp_kill_o(if2pair_stale_resp_kill),
        .debug_if2pair_valid_mask_11_o(if2pair_valid_mask_11),
        .debug_if2pair_valid_mask_01_o(if2pair_valid_mask_01),
        .debug_if2pair_upper_half_single_o(if2pair_upper_half_single),
        .debug_if2pair_downstream_accept2_o(if2pair_downstream_accept2),
        .debug_if2pair_downstream_accept1_o(if2pair_downstream_accept1),
        .debug_if2pair_downstream_stall_o(if2pair_downstream_stall),
        .debug_if2pair_slot1_retained_o(if2pair_slot1_retained),
        .debug_if2pair_slot1_replayed_as_slot0_o(if2pair_slot1_replayed_as_slot0),
        .debug_if2pair_redirect_flush_o(if2pair_redirect_flush),
        .debug_if2pair_slot1_only_bug_o(if2pair_slot1_only_bug),
        .debug_if2pair_stale_accept_bug_o(if2pair_stale_accept_bug),
        .debug_if2pair_fetch_endian_bug_o(if2pair_fetch_endian_bug),
        .debug_if2pair_duplicate_replay_bug_o(if2pair_duplicate_replay_bug),
        .debug_duplicate_issue_guard_o(duplicate_issue_guard),
        .debug_commit_width_mode_o(commit_width_mode),
        .debug_commit2_candidate_o(commit2_candidate),
        .debug_commit2_fire_o(commit2_fire),
        .debug_commit2_slot0_only_o(commit2_slot0_only),
        .debug_commit2_block_slot0_not_ready_o(commit2_block_slot0_not_ready),
        .debug_commit2_block_slot1_not_ready_o(commit2_block_slot1_not_ready),
        .debug_commit2_block_slot0_complex_o(commit2_block_slot0_complex),
        .debug_commit2_block_slot1_complex_o(commit2_block_slot1_complex),
        .debug_commit2_rrat_update2_o(commit2_rrat_update2),
        .debug_commit2_freelist_release2_o(commit2_freelist_release2),
        .debug_commit2_same_rd_waw_o(commit2_same_rd_waw),
        .debug_commit2_duplicate_release_bug_o(commit2_duplicate_release_bug),
        .debug_commit2_slot1_without_slot0_bug_o(commit2_slot1_without_slot0_bug),
        .debug_commit2_complex_slot_bug_o(commit2_complex_slot_bug),
        .debug_commit2_trace_slot1_o(commit2_trace_slot1),
        .debug_commit2_difftest_step2_o(commit2_difftest_step2)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            ebreak_seen_q <= 1'b0;
            ebreak_pc_q <= RESET_VECTOR;
            ebreak_instr_q <= EBREAK_INSTR;
        end else if (shadow_ebreak_commit) begin
            ebreak_seen_q <= 1'b1;
            ebreak_pc_q <= commit_event.slot0.pc;
            ebreak_instr_q <= commit_event.slot0.instr;
        end
    end

    /* verilator lint_off UNUSED */
    wire trace_valid_unused = trace_valid;
    wire trace_packet_unused = ^trace_packet;
    wire commit_event_unused = ^commit_event;
    wire packet_buffer_valid_unused = packet_buffer_valid;
    wire last_packet_accepted_unused = last_packet_accepted;
    wire last_commit_dropped_unused = last_commit_dropped;
    wire rename_fire_unused = rename_fire;
    wire renamed_uop_unused = ^renamed_uop;
    wire rob_done_unused = rob_done;
    wire rob_result_unused = ^rob_result;
    wire rob_count_unused = ^rob_count;
    wire iq_count_unused = ^iq_count;
    wire wb_buffer_valid_unused = wb_buffer_valid;
    wire shadow_control_pending_unused = shadow_control_pending;
    wire shadow_memory_pending_unused = shadow_memory_pending;
    wire shadow_commit_redirect_unused = shadow_commit_redirect_valid ^ ^shadow_commit_redirect_pc;
    wire ebreak_commit_unused = shadow_ebreak_commit;
    wire pmem_req_valid_unused = pmem_req_valid;
    wire pmem_resp_valid_unused = pmem_resp_valid;
    wire pmem_debug_fetch_pc_unused = ^pmem_debug_fetch_pc;
    /* verilator lint_on UNUSED */
`endif
endmodule
