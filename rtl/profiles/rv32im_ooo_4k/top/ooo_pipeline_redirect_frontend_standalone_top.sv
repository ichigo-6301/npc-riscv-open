`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// S8K standalone composition. This top replaces P8's testbench-owned Decode2
// replay with a raw instruction frontend while leaving P8 itself unchanged.
module ooo_pipeline_redirect_frontend_standalone_top #(
    parameter logic [31:0] RESET_VECTOR = 32'h0000_0000,
    parameter bit PRECISE_STORE_BUFFER_ENABLE = 1'b0,
    parameter bit STORE_LOAD_FORWARDING_ENABLE = 1'b0,
    parameter bit RAW_COMPLETION_WAKEUP_ENABLE = 1'b0,
    parameter bit SAME_CYCLE_DEPENDENCY_FORWARDING_ENABLE = 1'b0,
    parameter bit HEAD_LOAD_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b0,
    parameter bit HEAD_ALU_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b0,
    parameter bit HEAD_BRU_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b0,
    parameter bit LOAD_RESPONSE_COMPLETION_BYPASS_ENABLE = 1'b0,
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
    parameter bit DECODE_DISPATCH_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit FETCH_DECODE_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit FETCH_RESPONSE_CREDIT_TURNOVER_ENABLE = 1'b0,
    parameter bit ORDERED_TARGET_PREFETCH_ORACLE_ENABLE = 1'b0,
    parameter bit DEMAND_FETCH_LATENCY_ORACLE_ENABLE = 1'b0,
    parameter bit CORRECT_BRANCH_DUAL_RETIRE_ENABLE = 1'b0,
    parameter bit YOUNGER_SLOT1_CONTROL_DUAL_RETIRE_ENABLE = 1'b0,
    parameter bit POST_SELECTIVE_REDIRECT_COMMIT_ENABLE = 1'b0,
    parameter bit SELECTIVE_TRANSACTION_REDIRECT_OVERLAP_ENABLE = 1'b0,
    parameter bit STRONG_BRANCH_LINE_DELIVERY_ENABLE = 1'b0,
    parameter bit TARGET_LINE_HIT_ENABLE = 1'b0,
    parameter int unsigned TARGET_LINE_ENTRY_COUNT = 4,
    parameter int unsigned TARGET_LINE_WAY_COUNT = 1,
    parameter int unsigned CONDITIONAL_PRED_ENTRIES = 64,
    parameter bit CORRELATED_PREDICTOR_ENABLE = 1'b0,
    parameter bit CORRELATED_REACHABILITY_ORACLE_ENABLE = 1'b0,
    parameter bit WEAK_BIMODAL_REACHABILITY_ORACLE_ENABLE = 1'b0,
    parameter bit LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE = 1'b0,
    parameter bit MULTIHISTORY_REACHABILITY_ORACLE_ENABLE = 1'b0,
    parameter bit SAME_CYCLE_RAS_UPDATE_FORWARDING_ENABLE = 1'b0,
    parameter bit RAS_SELF_FORWARD_EXCLUSION_ENABLE = 1'b0,
    parameter bit SEQUENTIAL_LINE_HIT_ENABLE = 1'b0,
    parameter bit BRANCH_WINDOW_LINE_DELIVERY_ENABLE = 1'b0,
    parameter bit SPECULATIVE_STORE_DISPATCH_ENABLE = 1'b0,
    parameter bit STRUCTURAL_THROUGHPUT_ORACLE_ENABLE = 1'b0,
    parameter bit SINGLETON_COALESCE_ORACLE_ENABLE = 1'b0,
    parameter bit PARTIAL_PAIR_ORACLE_ENABLE = 1'b0,
    parameter bit CACHED_CROSS_LINE_PAIR_ENABLE = 1'b0,
    parameter bit CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE = 1'b0
) (
    input logic clk,
    input logic reset,
    input logic external_global_recover_i,
    input logic frontend_stop_i,
    input logic [31:0] trap_target_i,
    input logic [31:0] xret_target_i,

    output logic fetch_req_valid_o,
    input  logic fetch_req_ready_i,
    output logic [31:0] fetch_req_addr_o,
    output logic [31:0] fetch_req_pc_o,
    input  logic fetch_rsp_valid_i,
    output logic fetch_rsp_ready_o,
    input  logic [31:0] fetch_rsp_addr_i,
    input  logic [1:0] fetch_rsp_valid_mask_i,
    input  logic [63:0] fetch_rsp_data_i,
    input  logic fetch_rsp_eof_i,
    input  logic fetch_rsp_error_i,
    input  logic fetch_rsp_page_fault_i,

    output logic mem_req_valid_o,
    input logic mem_req_ready_i,
    output logic mem_req_write_o,
    output logic [31:0] mem_req_addr_o,
    output logic [31:0] mem_req_wdata_o,
    output logic [3:0] mem_req_wstrb_o,
    output logic [2:0] mem_req_len_o,
    output logic [1:0] mem_req_access_o,
    output bbus_ooo_mem_token_t mem_req_token_o,
    input logic mem_rsp_valid_i,
    output logic mem_rsp_ready_o,
    input logic [31:0] mem_rsp_rdata_i,
    input logic mem_rsp_error_i,
    input logic mem_rsp_page_fault_i,
    input bbus_ooo_mem_token_t mem_rsp_token_i,

    output logic serial_issue_valid_o,
    input logic serial_issue_ready_i,
    output bbus_ooo_alu_iq_uop_t serial_issue_uop_o,
    output logic [31:0] serial_issue_src1_o,
    output logic [31:0] serial_issue_src2_o,
    output logic [2:0] serial_issue_kind_o,
    input logic serial_completion_valid_i,
    output logic serial_completion_ready_o,
    input bbus_ooo_writeback_t serial_completion_wb_i,
    input logic [2:0] serial_completion_kind_i,

    input logic commit_enable_i,
    output logic redirect_valid_o,
    output bbus_ooo_redirect_t redirect_o,
    output logic recovery_done_o,
    output logic branch_window_active_o,
    output logic branch_window_line_delivery_safe_o,
    output logic branch_recovery_pending_o,
    output logic dispatch_freeze_o,
    output logic serial_dispatch_block_o,
    output logic selective_kill_valid_o,
    output logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_o,

    output bbus_ooo_commit_event_t commit_event_o,
    output logic serial_barrier_o,
    output logic [1:0] rename_fire_mask_o,
    output logic [1:0] backend_accept_mask_o,
    output logic [1:0] final_consume_mask_o,
    output bbus_ooo_writeback_t final_wb0_o,
    output bbus_ooo_writeback_t final_wb1_o,
    output logic [3:0] rob_count_o,
    output logic [3:0] iq_count_o,
    output logic backend_busy_o,
    output logic [1:0] perf_decode_width_o,
    output logic [1:0] perf_dispatch_width_o,
    output logic [1:0] perf_issue_width_o,
    output logic [3:0] perf_dispatch_reason0_o,
    output logic [3:0] perf_dispatch_reason1_o,
    output logic [3:0] perf_issue_reason0_o,
    output logic [3:0] perf_issue_reason1_o,
    output logic [3:0] perf_commit_reason0_o,
    output logic [3:0] perf_commit_reason1_o,
    output logic [63:0] perf_events_o,
    output logic [7:0] perf_mixed_source_o,
    output logic [63:0] perf_structural_oracle_o,
    output logic [63:0] perf_structural_meta_o,
    output logic [63:0] perf_accounting_raw_o,
    output logic [10:0] perf_store_buffer_o,
    output logic [2:0] perf_branch_pair_o,
    output logic [17:0] perf_operand_stage_o,
    output logic [63:0] perf_lifecycle_o,
    output logic [63:0] perf_branch_operand_o,
    output logic [63:0] perf_branch_producer_phase_o,
    output logic [155:0] perf_lsu_causality_o,
    output logic [31:0] perf_store_admission_o,
    output logic [63:0] perf_issue_dependency_o,
    output logic [31:0] perf_retirement_chain_o,
    output logic [63:0] perf_complex_retire_pairing_o,
    output logic [63:0] perf_completion_ownership_o,
    output logic [7:0] perf_serial_attribution_o,
    output logic [8:0] perf_branch_resolution_o,
    output logic [4:0] perf_target_line_o,
    output logic [7:0] perf_frontend_residual_o,
    output logic [1:0] perf_frontend_no_candidate_o,
    output logic [1:0] perf_branch_window_supply_o,
    output logic [3:0] perf_branch_window_post_block_o,
    output logic [23:0] perf_reservation_o,
    output logic [63:0] perf_fetch_response_credit_o,
    output logic [63:0] perf_demand_fetch_identity_o,
    output logic [3:0] perf_branch_window_o,
    output logic [9:0] perf_checkpoint_state_o,
    output logic [1:0] perf_fetch_delivery_width_o,
    output logic [7:0] perf_predictor_o,
    output logic [63:0] perf_predictor_detail_o,
    output logic [15:0] perf_predictor_local_o,
    output logic [20:0] perf_predictor_multihistory_o,
    output logic [31:0] perf_singleton_coalesce_o,
    output logic [31:0] perf_singleton_target_pc_o,
    output logic [31:0] perf_singleton_target_instr_o,
    output logic [31:0] perf_partial_pair_o,
    output logic [31:0] perf_partial_pair_pc_o,
    output logic [31:0] perf_partial_pair_instr_o,
    output logic [15:0] perf_cross_line_pair_o,
    output logic [31:0] perf_cross_line_carry_o,
    output logic [63:0] perf_dispatch_pc_o,
    output logic [63:0] perf_dispatch_instr_o,

    input bbus_ooo_arch_reg_t debug_arch_idx_i,
    input bbus_ooo_phys_reg_t debug_phys_idx_i,
    output bbus_ooo_phys_reg_t debug_rat_phys_o,
    output bbus_ooo_phys_reg_t debug_rrat_phys_o,
    output logic debug_ready_o,
    output logic [6:0] debug_free_count_o,
    output bbus_ooo_phys_reg_t debug_next_free_phys_o,
    output logic [1:0] debug_decode_buffer_valid_mask_o,
    output logic [31:0] debug_decode_buffer_pc0_o,
    output logic [31:0] debug_decode_buffer_pc1_o,
    output bbus_ooo_renamed_uop_t debug_renamed_uop0_o,
    output bbus_ooo_renamed_uop_t debug_renamed_uop1_o,

    output logic [31:0] frontend_fetch_pc_o,
    output logic [1:0] frontend_raw_queue_valid_mask_o,
    output logic [31:0] frontend_raw_queue_pc0_o,
    output logic [31:0] frontend_raw_queue_pc1_o,
    output logic frontend_request_outstanding_o,
    output logic frontend_stale_response_pending_o,
    output logic frontend_fault_o,
    output logic [31:0] frontend_fault_pc_o,
    output logic frontend_eof_o,
    output logic frontend_malformed_response_o,
    output logic frontend_unsupported_seen_o,
    output logic frontend_pending_clear_o,
    output logic frontend_redirect_clear_o,
    output logic frontend_stale_response_drop_o,
    output logic frontend_conservation_error_o,
    output logic branch_protocol_error_o,
    output logic recovery_conservation_error_o,
    output logic conservation_error_o
);
    logic [1:0] frontend_decode_valid;
    logic [1:0] frontend_decode_ready_unused;
    logic [1:0] frontend_decode_accept;
    bbus_ooo_ras_snapshot_t checkpoint_ras_snapshot;
    bbus_ooo_decode_uop_t frontend_decode_uop0;
    bbus_ooo_decode_uop_t frontend_decode_uop1;
    logic frontend_redirect_ready;
    logic p8_redirect_valid;
    bbus_ooo_redirect_t p8_redirect;
    logic p8_recovery_done;
    logic p8_branch_window;
    logic p8_branch_pending;
    logic p8_dispatch_freeze;
    logic p8_serial_dispatch_block;
    logic p8_branch_protocol_error;
    logic p8_recovery_conservation_error;
    logic p8_conservation_error;
    logic [63:0] p8_perf_events;
    logic [63:0] p8_perf_lifecycle;
    logic predictor_update_valid;
    logic [31:0] predictor_update_pc;
    logic [31:0] predictor_update_direct_target;
    bbus_ooo_pred_history_t predictor_update_history;
    logic predictor_update_base_taken;
    logic predictor_update_correlated_candidate;
    logic predictor_update_correlated_taken;
    bbus_ooo_local_history_t predictor_update_local_history;
    logic predictor_update_local_strong;
    logic predictor_update_local_taken;
    bbus_ooo_multihistory_mask_t predictor_update_multihistory_hit;
    bbus_ooo_multihistory_mask_t predictor_update_multihistory_strong;
    bbus_ooo_multihistory_mask_t predictor_update_multihistory_taken;
    bbus_ooo_multihistory_mask_t
        predictor_update_multihistory_chooser_prefer;
    bbus_ooo_multihistory_mask_t
        predictor_update_multihistory_chooser_strong;
    logic predictor_update_current_taken;
    logic predictor_update_taken;
    logic predictor_history_recover_valid;
    bbus_ooo_pred_history_t predictor_history_recover_snapshot;
    logic predictor_history_recover_conditional;
    logic predictor_history_recover_taken;
    logic indirect_update_valid;
    logic [31:0] indirect_update_pc;
    logic [31:0] indirect_update_target;
    logic ras_update_valid;
    bbus_ooo_ras_action_e ras_update_action;
    logic [31:0] ras_update_link;
    logic ras_restore_valid, ras_restore_ready, ras_restore_fire;
    logic ras_restore_payload_valid;
    bbus_ooo_ras_snapshot_t ras_restore_snapshot;
    bbus_ooo_ras_action_e ras_restore_replay_action;
    logic [31:0] ras_restore_replay_link;
    logic ras_restore_collision_error, ras_restore_invalid_error;
    logic target_line_invalidate;
    logic target_line_hit, target_line_sequential_hit;
    logic target_line_branch_window_hit;
    logic target_line_fill, target_line_miss;
    logic [3:0] p8_branch_window_block_reason;

    assign target_line_invalidate =
        (commit_event_o.control_event_valid &&
         (commit_event_o.control_event == BBUS_OOO_CTRL_FENCEI)) ||
        (commit_event_o.normal_commit_mask[0] &&
         commit_event_o.slot0.is_csr && commit_event_o.slot0.csr_write &&
         (commit_event_o.slot0.csr_addr == 12'h180)) ||
        (commit_event_o.normal_commit_mask[0] &&
         commit_event_o.slot0.is_system &&
         ((commit_event_o.slot0.instr & 32'hfe00_7fff) ==
          32'h1200_0073));

    ooo_pipeline_redirect_frontend_2w #(
        .RESET_VECTOR(RESET_VECTOR),
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
        .FETCH_DECODE_FALLTHROUGH_ENABLE(
            FETCH_DECODE_FALLTHROUGH_ENABLE),
        .FETCH_RESPONSE_CREDIT_TURNOVER_ENABLE(
            FETCH_RESPONSE_CREDIT_TURNOVER_ENABLE),
        .ORDERED_TARGET_PREFETCH_ORACLE_ENABLE(
            ORDERED_TARGET_PREFETCH_ORACLE_ENABLE),
        .DEMAND_FETCH_LATENCY_ORACLE_ENABLE(
            DEMAND_FETCH_LATENCY_ORACLE_ENABLE),
        .SINGLETON_COALESCE_ORACLE_ENABLE(
            SINGLETON_COALESCE_ORACLE_ENABLE),
        .PARTIAL_PAIR_ORACLE_ENABLE(PARTIAL_PAIR_ORACLE_ENABLE),
        .CACHED_CROSS_LINE_PAIR_ENABLE(CACHED_CROSS_LINE_PAIR_ENABLE),
        .CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE(
            CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE)
    ) u_frontend (
        .clk(clk),
        .reset(reset),
        .global_recover_i(external_global_recover_i),
        .stop_i(frontend_stop_i),
        .branch_recovery_pending_i(p8_branch_pending),
        .branch_window_active_i(p8_branch_window),
        .branch_window_line_delivery_safe_i(
            branch_window_line_delivery_safe_o),
        .fault_defer_i(
            p8_branch_window || p8_branch_pending || backend_busy_o ||
            (debug_decode_buffer_valid_mask_o != 2'b00)
        ),
        .target_line_invalidate_i(target_line_invalidate),
        .predictor_update_valid_i(predictor_update_valid),
        .predictor_update_pc_i(predictor_update_pc),
        .predictor_update_direct_target_i(predictor_update_direct_target),
        .predictor_update_history_i(predictor_update_history),
        .predictor_update_base_taken_i(predictor_update_base_taken),
        .predictor_update_correlated_candidate_i(
            predictor_update_correlated_candidate),
        .predictor_update_correlated_taken_i(
            predictor_update_correlated_taken),
        .predictor_update_local_history_i(
            predictor_update_local_history),
        .predictor_update_local_strong_i(
            predictor_update_local_strong),
        .predictor_update_local_taken_i(predictor_update_local_taken),
        .predictor_update_multihistory_strong_i(
            predictor_update_multihistory_strong),
        .predictor_update_multihistory_taken_i(
            predictor_update_multihistory_taken),
        .predictor_update_current_taken_i(
            predictor_update_current_taken),
        .predictor_update_taken_i(predictor_update_taken),
        .predictor_history_recover_valid_i(
            predictor_history_recover_valid),
        .predictor_history_recover_snapshot_i(
            predictor_history_recover_snapshot),
        .predictor_history_recover_conditional_i(
            predictor_history_recover_conditional),
        .predictor_history_recover_taken_i(
            predictor_history_recover_taken),
        .indirect_update_valid_i(indirect_update_valid),
        .indirect_update_pc_i(indirect_update_pc),
        .indirect_update_target_i(indirect_update_target),
        .ras_update_valid_i(ras_update_valid),
        .ras_update_action_i(ras_update_action),
        .ras_update_link_i(ras_update_link),
        .ras_restore_valid_i(ras_restore_valid),
        .ras_restore_ready_o(ras_restore_ready),
        .ras_restore_payload_valid_o(ras_restore_payload_valid),
        .ras_restore_snapshot_i(ras_restore_snapshot),
        .ras_restore_replay_action_i(ras_restore_replay_action),
        .ras_restore_replay_link_i(ras_restore_replay_link),
        .ras_restore_fire_o(ras_restore_fire),
        .ras_restore_collision_error_o(ras_restore_collision_error),
        .ras_restore_invalid_error_o(ras_restore_invalid_error),
        .redirect_valid_i(p8_redirect_valid),
        .redirect_i(p8_redirect),
        .redirect_ready_o(frontend_redirect_ready),
        .fetch_req_valid_o(fetch_req_valid_o),
        .fetch_req_ready_i(fetch_req_ready_i),
        .fetch_req_addr_o(fetch_req_addr_o),
        .fetch_req_pc_o(fetch_req_pc_o),
        .fetch_rsp_valid_i(fetch_rsp_valid_i),
        .fetch_rsp_ready_o(fetch_rsp_ready_o),
        .fetch_rsp_addr_i(fetch_rsp_addr_i),
        .fetch_rsp_valid_mask_i(fetch_rsp_valid_mask_i),
        .fetch_rsp_data_i(fetch_rsp_data_i),
        .fetch_rsp_eof_i(fetch_rsp_eof_i),
        .fetch_rsp_error_i(fetch_rsp_error_i),
        .fetch_rsp_page_fault_i(fetch_rsp_page_fault_i),
        .decode_valid_mask_o(frontend_decode_valid),
        .decode_uop0_o(frontend_decode_uop0),
        .decode_uop1_o(frontend_decode_uop1),
        .decode_ready_mask_i(frontend_decode_ready_unused),
        .decode_accept_mask_i(frontend_decode_accept),
        .fetch_pc_o(frontend_fetch_pc_o),
        .raw_queue_valid_mask_o(frontend_raw_queue_valid_mask_o),
        .raw_queue_pc0_o(frontend_raw_queue_pc0_o),
        .raw_queue_pc1_o(frontend_raw_queue_pc1_o),
        .request_outstanding_o(frontend_request_outstanding_o),
        .stale_response_pending_o(frontend_stale_response_pending_o),
        .frontend_fault_o(frontend_fault_o),
        .frontend_fault_pc_o(frontend_fault_pc_o),
        .frontend_eof_o(frontend_eof_o),
        .malformed_response_o(frontend_malformed_response_o),
        .unsupported_seen_o(frontend_unsupported_seen_o),
        .pending_clear_o(frontend_pending_clear_o),
        .redirect_clear_o(frontend_redirect_clear_o),
        .stale_response_drop_o(frontend_stale_response_drop_o),
        .target_line_hit_o(target_line_hit),
        .target_line_sequential_hit_o(target_line_sequential_hit),
        .target_line_branch_window_hit_o(target_line_branch_window_hit),
        .target_line_fill_o(target_line_fill),
        .target_line_miss_o(target_line_miss),
        .perf_fetch_delivery_width_o(perf_fetch_delivery_width_o),
        .perf_frontend_residual_o(perf_frontend_residual_o),
        .perf_frontend_no_candidate_o(perf_frontend_no_candidate_o),
        .perf_branch_window_supply_o(perf_branch_window_supply_o),
        .perf_branch_window_post_block_o(perf_branch_window_post_block_o),
        .perf_reservation_o(perf_reservation_o),
        .perf_fetch_response_credit_o(perf_fetch_response_credit_o),
        .perf_demand_fetch_identity_o(perf_demand_fetch_identity_o),
        .perf_singleton_coalesce_o(perf_singleton_coalesce_o),
        .perf_singleton_target_pc_o(perf_singleton_target_pc_o),
        .perf_singleton_target_instr_o(perf_singleton_target_instr_o),
        .perf_partial_pair_o(perf_partial_pair_o),
        .perf_partial_pair_pc_o(perf_partial_pair_pc_o),
        .perf_partial_pair_instr_o(perf_partial_pair_instr_o),
        .perf_cross_line_pair_o(perf_cross_line_pair_o),
        .perf_cross_line_carry_o(perf_cross_line_carry_o),
        .ras_snapshot_o(checkpoint_ras_snapshot),
        .conservation_error_o(frontend_conservation_error_o)
    );

    ooo_pipeline_branch_recovery_standalone_top #(
        .PRECISE_STORE_BUFFER_ENABLE(PRECISE_STORE_BUFFER_ENABLE),
        .STORE_LOAD_FORWARDING_ENABLE(STORE_LOAD_FORWARDING_ENABLE),
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
        .SPECULATIVE_STORE_DISPATCH_ENABLE(
            SPECULATIVE_STORE_DISPATCH_ENABLE),
        .STRUCTURAL_THROUGHPUT_ORACLE_ENABLE(
            STRUCTURAL_THROUGHPUT_ORACLE_ENABLE),
        .CORRELATED_REACHABILITY_ORACLE_ENABLE(
            CORRELATED_REACHABILITY_ORACLE_ENABLE),
        .WEAK_BIMODAL_REACHABILITY_ORACLE_ENABLE(
            WEAK_BIMODAL_REACHABILITY_ORACLE_ENABLE),
        .LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE(
            LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE),
        .MULTIHISTORY_REACHABILITY_ORACLE_ENABLE(
            MULTIHISTORY_REACHABILITY_ORACLE_ENABLE)
    ) u_p8 (
        .clk(clk),
        .reset(reset),
        .external_global_recover_i(external_global_recover_i),
        .trap_target_i(trap_target_i),
        .xret_target_i(xret_target_i),
        .checkpoint_ras_snapshot_i(checkpoint_ras_snapshot),
        .decode_valid_mask_i(frontend_decode_valid),
        .decode_uop0_i(frontend_decode_uop0),
        .decode_uop1_i(frontend_decode_uop1),
        .decode_ready_mask_o(frontend_decode_ready_unused),
        .decode_accept_mask_o(frontend_decode_accept),
        .mem_req_valid_o(mem_req_valid_o),
        .mem_req_ready_i(mem_req_ready_i),
        .mem_req_write_o(mem_req_write_o),
        .mem_req_addr_o(mem_req_addr_o),
        .mem_req_wdata_o(mem_req_wdata_o),
        .mem_req_wstrb_o(mem_req_wstrb_o),
        .mem_req_len_o(mem_req_len_o),
        .mem_req_access_o(mem_req_access_o),
        .mem_req_token_o(mem_req_token_o),
        .mem_rsp_valid_i(mem_rsp_valid_i),
        .mem_rsp_ready_o(mem_rsp_ready_o),
        .mem_rsp_rdata_i(mem_rsp_rdata_i),
        .mem_rsp_error_i(mem_rsp_error_i),
        .mem_rsp_page_fault_i(mem_rsp_page_fault_i),
        .mem_rsp_token_i(mem_rsp_token_i),
        .serial_issue_valid_o(serial_issue_valid_o),
        .serial_issue_ready_i(serial_issue_ready_i),
        .serial_issue_uop_o(serial_issue_uop_o),
        .serial_issue_src1_o(serial_issue_src1_o),
        .serial_issue_src2_o(serial_issue_src2_o),
        .serial_issue_kind_o(serial_issue_kind_o),
        .serial_completion_valid_i(serial_completion_valid_i),
        .serial_completion_ready_o(serial_completion_ready_o),
        .serial_completion_wb_i(serial_completion_wb_i),
        .serial_completion_kind_i(serial_completion_kind_i),
        .commit_enable_i(commit_enable_i),
        .redirect_ready_i(frontend_redirect_ready),
        .redirect_valid_o(p8_redirect_valid),
        .redirect_o(p8_redirect),
        .recovery_done_o(p8_recovery_done),
        .branch_window_active_o(p8_branch_window),
        .branch_window_line_delivery_safe_o(
            branch_window_line_delivery_safe_o),
        .branch_window_block_reason_o(p8_branch_window_block_reason),
        .perf_checkpoint_state_o(perf_checkpoint_state_o),
        .branch_recovery_pending_o(p8_branch_pending),
        .dispatch_freeze_o(p8_dispatch_freeze),
        .serial_dispatch_block_o(p8_serial_dispatch_block),
        .selective_kill_valid_o(selective_kill_valid_o),
        .selective_killed_rob_mask_o(selective_killed_rob_mask_o),
        .predictor_update_valid_o(predictor_update_valid),
        .predictor_update_pc_o(predictor_update_pc),
        .predictor_update_direct_target_o(predictor_update_direct_target),
        .predictor_update_history_o(predictor_update_history),
        .predictor_update_base_taken_o(predictor_update_base_taken),
        .predictor_update_correlated_candidate_o(
            predictor_update_correlated_candidate),
        .predictor_update_correlated_taken_o(
            predictor_update_correlated_taken),
        .predictor_update_local_history_o(
            predictor_update_local_history),
        .predictor_update_local_strong_o(
            predictor_update_local_strong),
        .predictor_update_local_taken_o(predictor_update_local_taken),
        .predictor_update_multihistory_hit_o(
            predictor_update_multihistory_hit),
        .predictor_update_multihistory_strong_o(
            predictor_update_multihistory_strong),
        .predictor_update_multihistory_taken_o(
            predictor_update_multihistory_taken),
        .predictor_update_multihistory_chooser_prefer_o(
            predictor_update_multihistory_chooser_prefer),
        .predictor_update_multihistory_chooser_strong_o(
            predictor_update_multihistory_chooser_strong),
        .predictor_update_current_taken_o(
            predictor_update_current_taken),
        .predictor_update_taken_o(predictor_update_taken),
        .predictor_history_recover_valid_o(
            predictor_history_recover_valid),
        .predictor_history_recover_snapshot_o(
            predictor_history_recover_snapshot),
        .predictor_history_recover_conditional_o(
            predictor_history_recover_conditional),
        .predictor_history_recover_taken_o(
            predictor_history_recover_taken),
        .indirect_update_valid_o(indirect_update_valid),
        .indirect_update_pc_o(indirect_update_pc),
        .indirect_update_target_o(indirect_update_target),
        .ras_update_valid_o(ras_update_valid),
        .ras_update_action_o(ras_update_action),
        .ras_update_link_o(ras_update_link),
        .ras_restore_valid_o(ras_restore_valid),
        .ras_restore_ready_i(ras_restore_ready),
        .ras_restore_payload_valid_i(ras_restore_payload_valid),
        .ras_restore_snapshot_o(ras_restore_snapshot),
        .ras_restore_replay_action_o(ras_restore_replay_action),
        .ras_restore_replay_link_o(ras_restore_replay_link),
        .commit_event_o(commit_event_o),
        .serial_barrier_o(serial_barrier_o),
        .rename_fire_mask_o(rename_fire_mask_o),
        .backend_accept_mask_o(backend_accept_mask_o),
        .final_consume_mask_o(final_consume_mask_o),
        .final_wb0_o(final_wb0_o),
        .final_wb1_o(final_wb1_o),
        .rob_count_o(rob_count_o),
        .iq_count_o(iq_count_o),
        .backend_busy_o(backend_busy_o),
        .perf_dispatch_width_o(perf_dispatch_width_o),
        .perf_issue_width_o(perf_issue_width_o),
        .perf_dispatch_reason0_o(perf_dispatch_reason0_o),
        .perf_dispatch_reason1_o(perf_dispatch_reason1_o),
        .perf_issue_reason0_o(perf_issue_reason0_o),
        .perf_issue_reason1_o(perf_issue_reason1_o),
        .perf_commit_reason0_o(perf_commit_reason0_o),
        .perf_commit_reason1_o(perf_commit_reason1_o),
        .perf_events_o(p8_perf_events),
        .perf_mixed_source_o(perf_mixed_source_o),
        .perf_structural_oracle_o(perf_structural_oracle_o),
        .perf_structural_meta_o(perf_structural_meta_o),
        .perf_accounting_raw_o(perf_accounting_raw_o),
        .perf_store_buffer_o(perf_store_buffer_o),
        .perf_branch_pair_o(perf_branch_pair_o),
        .perf_operand_stage_o(perf_operand_stage_o),
        .perf_lifecycle_o(p8_perf_lifecycle),
        .perf_branch_operand_o(perf_branch_operand_o),
        .perf_branch_producer_phase_o(perf_branch_producer_phase_o),
        .perf_lsu_causality_o(perf_lsu_causality_o),
        .perf_store_admission_o(perf_store_admission_o),
        .perf_issue_dependency_o(perf_issue_dependency_o),
        .perf_retirement_chain_o(perf_retirement_chain_o),
        .perf_complex_retire_pairing_o(perf_complex_retire_pairing_o),
        .perf_completion_ownership_o(perf_completion_ownership_o),
        .perf_serial_attribution_o(perf_serial_attribution_o),
        .perf_branch_resolution_o(perf_branch_resolution_o),
        .perf_predictor_o(perf_predictor_o),
        .perf_predictor_detail_o(perf_predictor_detail_o),
        .perf_predictor_local_o(perf_predictor_local_o),
        .perf_predictor_multihistory_o(perf_predictor_multihistory_o),
        .debug_arch_idx_i(debug_arch_idx_i),
        .debug_phys_idx_i(debug_phys_idx_i),
        .debug_rat_phys_o(debug_rat_phys_o),
        .debug_rrat_phys_o(debug_rrat_phys_o),
        .debug_ready_o(debug_ready_o),
        .debug_free_count_o(debug_free_count_o),
        .debug_next_free_phys_o(debug_next_free_phys_o),
        .debug_decode_buffer_valid_mask_o(debug_decode_buffer_valid_mask_o),
        .debug_decode_buffer_pc0_o(debug_decode_buffer_pc0_o),
        .debug_decode_buffer_pc1_o(debug_decode_buffer_pc1_o),
        .debug_renamed_uop0_o(debug_renamed_uop0_o),
        .debug_renamed_uop1_o(debug_renamed_uop1_o),
        .branch_protocol_error_o(p8_branch_protocol_error),
        .recovery_conservation_error_o(p8_recovery_conservation_error),
        .conservation_error_o(p8_conservation_error)
    );

    assign redirect_valid_o = p8_redirect_valid;
    assign redirect_o = p8_redirect;
    assign recovery_done_o = p8_recovery_done;
    assign branch_window_active_o = p8_branch_window;
    assign branch_recovery_pending_o = p8_branch_pending;
    assign dispatch_freeze_o = p8_dispatch_freeze;
    assign serial_dispatch_block_o = p8_serial_dispatch_block;
    assign branch_protocol_error_o = p8_branch_protocol_error;
    assign recovery_conservation_error_o = p8_recovery_conservation_error;
    assign perf_decode_width_o = {1'b0, frontend_decode_accept[0]} +
        {1'b0, frontend_decode_accept[1]};
    assign perf_dispatch_pc_o = {
        debug_renamed_uop1_o.pc, debug_renamed_uop0_o.pc
    };
    assign perf_dispatch_instr_o = {
        debug_renamed_uop1_o.instr, debug_renamed_uop0_o.instr
    };
    always_comb begin
        perf_events_o = p8_perf_events;
        perf_events_o[40] = fetch_req_valid_o && fetch_req_ready_i;
        perf_events_o[41] = fetch_rsp_valid_i && fetch_rsp_ready_o;
        perf_events_o[42] = frontend_stale_response_drop_o;
        perf_events_o[43] = frontend_request_outstanding_o;
        perf_events_o[44] = frontend_pending_clear_o;
        perf_events_o[45] = frontend_redirect_clear_o;
        perf_events_o[46] = fetch_rsp_page_fault_i && fetch_rsp_valid_i &&
            fetch_rsp_ready_o;
        perf_events_o[47] = frontend_conservation_error_o;
        perf_lifecycle_o = p8_perf_lifecycle;
        perf_target_line_o = {
            target_line_branch_window_hit,
            target_line_sequential_hit, target_line_miss, target_line_fill,
            target_line_hit
        };
        perf_branch_window_o = 4'd0;
        if (perf_frontend_residual_o[7:4] == 4'd3) begin
            perf_branch_window_o =
                ((p8_branch_window_block_reason >= 4'd1) &&
                 (p8_branch_window_block_reason <= 4'd8)) ?
                p8_branch_window_block_reason :
                (p8_branch_window_block_reason == 4'd0) ? 4'd4 : 4'd9;
        end
    end
    assign conservation_error_o = p8_conservation_error ||
        frontend_conservation_error_o || ras_restore_collision_error ||
        ras_restore_invalid_error;

    /* verilator lint_off UNUSED */
    wire target_line_debug_unused = target_line_hit ^
        target_line_sequential_hit ^ target_line_branch_window_hit ^
        target_line_fill ^ target_line_miss ^
        (^p8_branch_window_block_reason);
    /* verilator lint_on UNUSED */
endmodule
