`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// Standalone-only IF2 owner for the pipeline path. It mirrors the existing
// aligned pair contract without importing DPI or production frontend state.
module ooo_pipeline_redirect_frontend_2w #(
    parameter logic [31:0] RESET_VECTOR = 32'h0000_0000,
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
    parameter bit FETCH_DECODE_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit FETCH_RESPONSE_CREDIT_TURNOVER_ENABLE = 1'b0,
    parameter bit ORDERED_TARGET_PREFETCH_ORACLE_ENABLE = 1'b0,
    parameter bit DEMAND_FETCH_LATENCY_ORACLE_ENABLE = 1'b0,
    parameter bit SINGLETON_COALESCE_ORACLE_ENABLE = 1'b0,
    parameter bit PARTIAL_PAIR_ORACLE_ENABLE = 1'b0,
    parameter bit CACHED_CROSS_LINE_PAIR_ENABLE = 1'b0,
    parameter bit CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE = 1'b0
) (
    input  logic clk,
    input  logic reset,
    input  logic global_recover_i,
    input  logic stop_i,
    input  logic branch_recovery_pending_i,
    input  logic branch_window_active_i,
    input  logic branch_window_line_delivery_safe_i,
    input  logic fault_defer_i,
    input  logic target_line_invalidate_i,
    input  logic predictor_update_valid_i,
    input  logic [31:0] predictor_update_pc_i,
    input  logic [31:0] predictor_update_direct_target_i,
    input  bbus_ooo_pred_history_t predictor_update_history_i,
    input  logic predictor_update_base_taken_i,
    input  logic predictor_update_correlated_candidate_i,
    input  logic predictor_update_correlated_taken_i,
    input  bbus_ooo_local_history_t predictor_update_local_history_i,
    input  logic predictor_update_local_strong_i,
    input  logic predictor_update_local_taken_i,
    input  bbus_ooo_multihistory_mask_t
        predictor_update_multihistory_strong_i,
    input  bbus_ooo_multihistory_mask_t
        predictor_update_multihistory_taken_i,
    input  logic predictor_update_current_taken_i,
    input  logic predictor_update_taken_i,
    input  logic predictor_history_recover_valid_i,
    input  bbus_ooo_pred_history_t predictor_history_recover_snapshot_i,
    input  logic predictor_history_recover_conditional_i,
    input  logic predictor_history_recover_taken_i,
    input  logic indirect_update_valid_i,
    input  logic [31:0] indirect_update_pc_i,
    input  logic [31:0] indirect_update_target_i,
    input  logic ras_update_valid_i,
    input  bbus_ooo_ras_action_e ras_update_action_i,
    input  logic [31:0] ras_update_link_i,
    input logic ras_restore_valid_i,
    output logic ras_restore_ready_o,
    output logic ras_restore_payload_valid_o,
    input bbus_ooo_ras_snapshot_t ras_restore_snapshot_i,
    input bbus_ooo_ras_action_e ras_restore_replay_action_i,
    input logic [31:0] ras_restore_replay_link_i,
    output logic ras_restore_fire_o,
    output logic ras_restore_collision_error_o,
    output logic ras_restore_invalid_error_o,
    input  logic redirect_valid_i,
    input  bbus_ooo_redirect_t redirect_i,
    output logic redirect_ready_o,

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

    output logic [1:0] decode_valid_mask_o,
    output bbus_ooo_decode_uop_t decode_uop0_o,
    output bbus_ooo_decode_uop_t decode_uop1_o,
    input  logic [1:0] decode_ready_mask_i,
    input  logic [1:0] decode_accept_mask_i,

    output logic [31:0] fetch_pc_o,
    output logic [1:0] raw_queue_valid_mask_o,
    output logic [31:0] raw_queue_pc0_o,
    output logic [31:0] raw_queue_pc1_o,
    output logic request_outstanding_o,
    output logic stale_response_pending_o,
    output logic frontend_fault_o,
    output logic [31:0] frontend_fault_pc_o,
    output logic frontend_eof_o,
    output logic malformed_response_o,
    output logic unsupported_seen_o,
    output logic pending_clear_o,
    output logic redirect_clear_o,
    output logic stale_response_drop_o,
    output logic target_line_hit_o,
    output logic target_line_sequential_hit_o,
    output logic target_line_branch_window_hit_o,
    output logic target_line_fill_o,
    output logic target_line_miss_o,
    output logic [1:0] perf_fetch_delivery_width_o,
    output logic [7:0] perf_frontend_residual_o,
    output logic [1:0] perf_frontend_no_candidate_o,
    output logic [1:0] perf_branch_window_supply_o,
    output logic [3:0] perf_branch_window_post_block_o,
    output logic [23:0] perf_reservation_o,
    output logic [63:0] perf_fetch_response_credit_o,
    output logic [63:0] perf_demand_fetch_identity_o,
    output logic [31:0] perf_singleton_coalesce_o,
    output logic [31:0] perf_singleton_target_pc_o,
    output logic [31:0] perf_singleton_target_instr_o,
    output logic [31:0] perf_partial_pair_o,
    output logic [31:0] perf_partial_pair_pc_o,
    output logic [31:0] perf_partial_pair_instr_o,
    output logic [15:0] perf_cross_line_pair_o,
    output logic [31:0] perf_cross_line_carry_o,
    output bbus_ooo_ras_snapshot_t ras_snapshot_o,
    output logic conservation_error_o
);
    localparam logic [3:0] PERF_REQ_FIRED = 4'd1;
    localparam logic [3:0] PERF_REQ_TARGET_LINE = 4'd2;
    localparam logic [3:0] PERF_REQ_RECOVERY_CONTROL = 4'd3;
    localparam logic [3:0] PERF_REQ_TERMINAL_FAULT = 4'd4;
    localparam logic [3:0] PERF_REQ_CURRENT_OWNER_FULL = 4'd5;
    localparam logic [3:0] PERF_REQ_STALE_OWNER_FULL = 4'd6;
    localparam logic [3:0] PERF_REQ_CURRENT_CREDIT_FULL = 4'd7;
    localparam logic [3:0] PERF_REQ_STALE_CREDIT_BLOCK = 4'd8;
    localparam logic [3:0] PERF_REQ_DOWNSTREAM_NOT_READY = 4'd9;
    localparam logic [3:0] PERF_REQ_OTHER = 4'd10;

    localparam logic [3:0] PERF_SEQ_INJECTED = 4'd1;
    localparam logic [3:0] PERF_SEQ_DISABLED = 4'd2;
    localparam logic [3:0] PERF_SEQ_BRANCH_WINDOW = 4'd3;
    localparam logic [3:0] PERF_SEQ_QUEUED_CONTROL = 4'd4;
    localparam logic [3:0] PERF_SEQ_PARTIAL_PAIR = 4'd5;
    localparam logic [3:0] PERF_SEQ_CURRENT_RESERVED = 4'd6;
    localparam logic [3:0] PERF_SEQ_QUEUE_CAPACITY = 4'd7;
    localparam logic [3:0] PERF_SEQ_RECOVERY_TERMINAL = 4'd8;
    localparam logic [3:0] PERF_SEQ_RESPONSE_CONFLICT = 4'd9;
    localparam logic [3:0] PERF_SEQ_OTHER = 4'd10;

    localparam logic [3:0] ORDERED_PREFETCH_REASON_NONE = 4'd0;
    localparam logic [3:0] ORDERED_PREFETCH_REASON_ELIGIBLE = 4'd1;
    localparam logic [3:0] ORDERED_PREFETCH_REASON_DOWNSTREAM = 4'd2;
    localparam logic [3:0] ORDERED_PREFETCH_REASON_RECOVERY = 4'd3;
    localparam logic [3:0] ORDERED_PREFETCH_REASON_BRANCH_WINDOW = 4'd4;
    localparam logic [3:0] ORDERED_PREFETCH_REASON_CONTROL = 4'd5;
    localparam logic [3:0] ORDERED_PREFETCH_REASON_QUEUE_CAPACITY = 4'd6;
    localparam logic [3:0] ORDERED_PREFETCH_REASON_LOOKUP_CONFLICT = 4'd7;
    localparam logic [3:0] ORDERED_PREFETCH_REASON_FUTURE_CACHED = 4'd8;
    localparam logic [3:0] ORDERED_PREFETCH_REASON_FUTURE_DUPLICATE = 4'd9;
    localparam logic [3:0] ORDERED_PREFETCH_REASON_OWNER_CAPACITY = 4'd10;
    localparam logic [3:0] ORDERED_PREFETCH_REASON_OTHER = 4'd11;

    localparam logic [2:0] SINGLETON_ORIGIN_OTHER = 3'd0;
    localparam logic [2:0] SINGLETON_ORIGIN_ALIGNED_SINGLE = 3'd1;
    localparam logic [2:0] SINGLETON_ORIGIN_PAIR_WORD1 = 3'd2;
    localparam logic [2:0] SINGLETON_ORIGIN_DIRECT_RESIDUAL = 3'd3;
    localparam logic [2:0] SINGLETON_ORIGIN_EXCEPTION = 3'd4;
    localparam logic [2:0] SINGLETON_ORIGIN_CROSS_LINE_CARRY = 3'd5;

    logic [31:0] next_pc_q;
    logic [7:0] frontend_epoch_q;
    logic invalidation_active_q;
    logic [31:0] request_pc_q [0:3];
    logic [31:0] request_addr_q [0:3];
    logic [7:0] request_epoch_q [0:3];
    logic [2:0] request_words_q [0:3];
    logic [1:0] request_head_q;
    logic [1:0] request_tail_q;
    logic [2:0] request_count_q;
    logic [2:0] reserved_words_q;

    logic [1:0] queue_head_q;
    logic [2:0] queue_count_q;
    logic [31:0] queue_pc_q [0:3];
    logic [31:0] queue_instr_q [0:3];
    logic queue_exception_q [0:3];
    logic queue_branch_window_line_q [0:3];
    logic queue_branch_window_line_word1_q [0:3];
    logic [2:0] queue_singleton_origin_q [0:3];
    logic [7:0] queue_epoch_q [0:3];
    logic [1:0] queue_second_idx_c;
    logic [1:0] queue_tail_idx_c;
    logic [1:0] queue_valid_c;
    logic [1:0] queue_count_valid_c;
    logic [1:0] queue_epoch_valid_c;
    logic [31:0] queue_pc0_c;
    logic [31:0] queue_pc1_c;
    logic [31:0] queue_instr0_c;
    logic [31:0] queue_instr1_c;
    logic queue_exception0_c;
    logic queue_exception1_c;
    logic queue_branch_window_line0_c;
    logic queue_branch_window_line1_c;
    logic queue_branch_window_line_word10_c;
    logic queue_branch_window_line_word11_c;
    logic [1:0] decode_source_valid_c;
    logic [31:0] decode_source_pc0_c;
    logic [31:0] decode_source_pc1_c;
    logic [31:0] decode_source_instr0_c;
    logic [31:0] decode_source_instr1_c;
    logic decode_source_exception0_c;
    logic decode_source_exception1_c;
    logic decode_source_branch_window_line0_c;
    logic decode_source_branch_window_line1_c;
    logic decode_source_branch_window_line_word10_c;
    logic decode_source_branch_window_line_word11_c;
    logic [1:0] incoming_valid_mask_c;
    logic [31:0] incoming_pc0_c;
    logic [31:0] incoming_pc1_c;
    logic [31:0] incoming_instr0_c;
    logic [31:0] incoming_instr1_c;
    logic incoming_exception0_c;
    logic incoming_branch_window_line_c;
    logic direct_target_line_c;
    logic direct_response_c;
    logic direct_delivery_c;
    logic [1:0] direct_accept_mask_c;
    logic target_line_delivery_common_c;
    logic target_line_candidate_c;
    logic response_delivery_candidate_c;
    bbus_ooo_decode_uop_t decoded_uop0_c;
    bbus_ooo_decode_uop_t decoded_uop1_c;

    logic frontend_fault_q;
    logic [31:0] frontend_fault_pc_q;
    logic frontend_eof_q;
    logic malformed_response_q;
    logic unsupported_seen_q;
    logic illegal_decode_accept_q;
    logic stale_response_drop_q;

    logic decode0_supported;
    logic decode0_unsupported;
    logic decode1_supported;
    logic decode1_unsupported;
    logic oldest_unsupported_c;
    logic younger_unsupported_c;
    logic [1:0] visible_queue_mask_c;
    logic output_enable_c;
    logic legal_decode_accept_c;
    logic [1:0] decode_pop_mask_c;
    logic [1:0] decode_pop_count_c;
    logic [2:0] queue_count_after_pop_c;
    logic [2:0] request_word_count_c;
    logic request_capacity_c;
    logic current_request_capacity_c;
    logic [2:0] current_epoch_owner_count_c;
    logic [2:0] current_epoch_exact_pc_owner_count_c;
    logic [2:0] current_epoch_same_line_owner_count_c;
    logic [2:0] current_epoch_future_line_owner_count_c;
    logic reservation_head_current_c;
    logic reservation_head_exact_pc_c;
    logic reservation_head_same_line_c;
    logic response_from_queue_c;
    logic same_cycle_response_c;
    logic [1:0] expected_rsp_mask_c;
    logic request_fire_c;
    logic fetch_req_valid_base_c;
    logic request_base_fire_c;
    logic response_fire_c;
    logic redirect_fire_c;
    logic response_malformed_c;
    logic response_has_owner_c;
    logic response_stale_c;
    logic invalidation_level_c;
    logic slot0_predict_taken_c;
    logic slot1_predict_taken_c;
    logic slot0_conditional_c;
    logic slot1_conditional_c;
    logic predictor_hit0_c;
    logic predictor_hit1_c;
    logic predictor_strong0_c;
    logic predictor_strong1_c;
    logic predictor_correlated0_c;
    logic predictor_correlated1_c;
    logic predictor_base_taken0_c;
    logic predictor_base_taken1_c;
    logic predictor_base_counter_valid0_c;
    logic predictor_base_counter_valid1_c;
    logic predictor_base_counter_taken0_c;
    logic predictor_base_counter_taken1_c;
    logic predictor_corr_candidate0_c;
    logic predictor_corr_candidate1_c;
    logic predictor_corr_raw_candidate0_c;
    logic predictor_corr_raw_candidate1_c;
    logic predictor_corr_chooser_prefer0_c;
    logic predictor_corr_chooser_prefer1_c;
    logic predictor_corr_taken0_c;
    logic predictor_corr_taken1_c;
    bbus_ooo_local_history_t predictor_local_history0_c;
    bbus_ooo_local_history_t predictor_local_history1_c;
    logic predictor_local_strong0_c;
    logic predictor_local_strong1_c;
    logic predictor_local_taken0_c;
    logic predictor_local_taken1_c;
    logic predictor_local_chooser_prefer0_c;
    logic predictor_local_chooser_prefer1_c;
    logic predictor_local_chooser_strong0_c;
    logic predictor_local_chooser_strong1_c;
    bbus_ooo_multihistory_mask_t predictor_multihistory_hit0_c;
    bbus_ooo_multihistory_mask_t predictor_multihistory_hit1_c;
    bbus_ooo_multihistory_mask_t predictor_multihistory_strong0_c;
    bbus_ooo_multihistory_mask_t predictor_multihistory_strong1_c;
    bbus_ooo_multihistory_mask_t predictor_multihistory_taken0_c;
    bbus_ooo_multihistory_mask_t predictor_multihistory_taken1_c;
    bbus_ooo_multihistory_mask_t
        predictor_multihistory_chooser_prefer0_c;
    bbus_ooo_multihistory_mask_t
        predictor_multihistory_chooser_prefer1_c;
    bbus_ooo_multihistory_mask_t
        predictor_multihistory_chooser_strong0_c;
    bbus_ooo_multihistory_mask_t
        predictor_multihistory_chooser_strong1_c;
    logic predictor_taken0_c;
    logic predictor_taken1_c;
    logic [31:0] predictor_target0_c;
    logic [31:0] predictor_target1_c;
    bbus_ooo_pred_history_t predictor_history_q;
    bbus_ooo_pred_history_t predictor_lookup_history0_c;
    bbus_ooo_pred_history_t predictor_lookup_history1_c;
    bbus_ooo_pred_history_t predictor_history_after_accept_c;
    logic slot0_jalr_c;
    logic slot1_jalr_c;
    logic slot0_return_c;
    logic slot1_return_c;
    logic indirect_taken0_c;
    logic indirect_taken1_c;
    logic [31:0] indirect_target0_c;
    logic [31:0] indirect_target1_c;
    logic indirect_btb_hit0_c, indirect_btb_hit1_c;
    logic indirect_ras_hit0_c, indirect_ras_hit1_c;
    logic [1:0] ras_self_forward_collision_c;
    logic taken_predict_fire_c;
    logic safe_taken_predict_fire_c;
    logic [31:0] taken_predict_target_c;
    logic [31:0] response_pc_c;
    logic [31:0] response_addr_c;
    logic [2:0] fresh_reserved_words_c;
    logic target_line_lookup_hit_c;
    logic target_line_lookup_entry_valid_c;
    logic [63:0] target_line_lookup_data_c;
    logic target_line_lookup_pending_q;
    logic adjacent_line_lookup_hit_c;
    logic adjacent_line_lookup_entry_valid_c;
    logic [63:0] adjacent_line_lookup_data_c;
    logic target_line_eligible_hit_c;
    logic sequential_line_eligible_hit_c;
    logic frontend_control_present_c;
    logic [2:0] target_line_word_count_c;
    logic target_line_capacity_c;
    logic target_line_inject_c;
    logic target_line_branch_window_inject_c;
    logic target_line_fill_c;
    logic sequential_line_candidate_c;
    logic branch_window_line_delivery_c;
    logic [3:0] perf_request_reason_c;
    logic [3:0] perf_sequential_reason_c;
    logic perf_branch_window_full_pair_c;
    logic [3:0] perf_branch_window_post_block_c;
    logic response_credit_head_current_c;
    logic response_credit_normal_c;
    logic response_credit_direct_full_c;
    logic response_credit_direct_consumed_c;
    logic response_credit_direct_partial_c;
    logic response_credit_buffered_c;
    logic response_credit_request_common_c;
    logic response_credit_owner_blocked_c;
    logic response_credit_word_blocked_c;
    logic response_credit_target_c;
    logic response_credit_capacity_after_release_c;
    logic response_credit_structural_eligible_c;
    logic response_credit_ready_eligible_c;
    logic response_credit_state_error_c;
    logic [2:0] response_credit_head_words_c;
    logic ordered_prefetch_target_c;
    logic ordered_prefetch_lookup_c;
    logic [31:0] ordered_prefetch_future_addr_c;
    logic ordered_prefetch_future_hit_c;
    logic ordered_prefetch_protocol_safe_c;
    logic ordered_prefetch_owner_capacity_c;
    logic ordered_prefetch_structural_eligible_c;
    logic ordered_prefetch_ready_eligible_c;
    logic [3:0] ordered_prefetch_reason_c;
    logic ordered_prefetch_recovery_drop_c;
    logic ordered_prefetch_state_error_c;
    logic demand_fetch_state_error_c;
    logic coalesce_target_line_c;
    logic coalesce_response_c;
    logic [1:0] coalesce_incoming_mask_c;
    logic [31:0] coalesce_incoming_pc_c;
    logic [31:0] coalesce_incoming_instr_c;
    logic coalesce_incoming_exception_c;
    logic coalesce_incoming_supported_c;
    logic coalesce_incoming_unsupported_c;
    bbus_ooo_decode_uop_t coalesce_incoming_uop_c;
    logic coalesce_singleton_c;
    logic coalesce_contiguous_c;
    logic coalesce_current_control_c;
    logic coalesce_base_eligible_c;
    logic coalesce_eligible_c;
    logic coalesce_opportunity_c;
    logic coalesce_recovery_terminal_c;
    logic coalesce_admission_block_c;
    logic coalesce_state_error_c;
    logic partial_current_control_c;
    logic partial_younger_control_c;
    logic partial_pair_state_error_c;
    logic [31:0] cross_line_current_pc_c;
    logic [31:0] cross_line_next_pc_c;
    logic cross_line_direct_candidate_c;
    logic cross_line_response_owner_safe_c;
    logic cross_line_owner_safe_c;
    logic cross_line_cached_pair_c;
    logic cross_line_residual_capture_c;
    logic cross_line_queue_capture_c;
    logic cross_line_state_error_c;
    logic cross_line_feature_enable_c;
    logic cross_line_initial_carry_c;
    logic [31:0] cross_line_carry_pc_c;
    logic [31:0] cross_line_carry_instr_c;
    logic cross_line_carry_head_c;
    logic cross_line_roll_candidate_c;
    logic [1:0] cross_line_roll_accept_mask_c;
    logic cross_line_roll_fire_c;
    logic [1:0] cross_line_initial_buffer_count_c;
    logic [1:0] cross_line_roll_buffer_count_c;
    logic [2:0] cross_line_direct_advance_words_c;
    logic cross_line_carry_promote_c;
    logic cross_line_carry_state_error_c;

    function automatic logic [2:0] current_epoch_reserved_words();
        logic [1:0] owner_idx;
        integer owner_offset;
        begin
            current_epoch_reserved_words = 3'd0;
            for (owner_offset = 0; owner_offset < 4;
                 owner_offset = owner_offset + 1) begin
                owner_idx = request_head_q + owner_offset;
                if ((owner_offset < request_count_q) &&
                    (request_epoch_q[owner_idx] == frontend_epoch_q)) begin
                    current_epoch_reserved_words =
                        current_epoch_reserved_words +
                        request_words_q[owner_idx];
                end
            end
        end
    endfunction

    function automatic logic [2:0] current_epoch_owner_count();
        logic [1:0] owner_idx;
        integer owner_offset;
        begin
            current_epoch_owner_count = 3'd0;
            for (owner_offset = 0; owner_offset < 4;
                 owner_offset = owner_offset + 1) begin
                owner_idx = request_head_q + owner_offset;
                if ((owner_offset < request_count_q) &&
                    (request_epoch_q[owner_idx] == frontend_epoch_q)) begin
                    current_epoch_owner_count =
                        current_epoch_owner_count + 3'd1;
                end
            end
        end
    endfunction

    function automatic logic [2:0] current_epoch_exact_pc_owner_count();
        logic [1:0] owner_idx;
        integer owner_offset;
        begin
            current_epoch_exact_pc_owner_count = 3'd0;
            for (owner_offset = 0; owner_offset < 4;
                 owner_offset = owner_offset + 1) begin
                owner_idx = request_head_q + owner_offset;
                if ((owner_offset < request_count_q) &&
                    (request_epoch_q[owner_idx] == frontend_epoch_q) &&
                    (request_pc_q[owner_idx] == next_pc_q)) begin
                    current_epoch_exact_pc_owner_count =
                        current_epoch_exact_pc_owner_count + 3'd1;
                end
            end
        end
    endfunction

    function automatic logic [2:0] current_epoch_same_line_owner_count();
        logic [1:0] owner_idx;
        integer owner_offset;
        begin
            current_epoch_same_line_owner_count = 3'd0;
            for (owner_offset = 0; owner_offset < 4;
                 owner_offset = owner_offset + 1) begin
                owner_idx = request_head_q + owner_offset;
                if ((owner_offset < request_count_q) &&
                    (request_epoch_q[owner_idx] == frontend_epoch_q) &&
                    (request_addr_q[owner_idx] ==
                     {next_pc_q[31:3], 3'b000})) begin
                    current_epoch_same_line_owner_count =
                        current_epoch_same_line_owner_count + 3'd1;
                end
            end
        end
    endfunction

    function automatic logic [2:0] current_epoch_future_line_owner_count();
        logic [1:0] owner_idx;
        integer owner_offset;
        begin
            current_epoch_future_line_owner_count = 3'd0;
            for (owner_offset = 0; owner_offset < 4;
                 owner_offset = owner_offset + 1) begin
                owner_idx = request_head_q + owner_offset;
                if ((owner_offset < request_count_q) &&
                    (request_epoch_q[owner_idx] == frontend_epoch_q) &&
                    (request_addr_q[owner_idx] ==
                     ordered_prefetch_future_addr_c)) begin
                    current_epoch_future_line_owner_count =
                        current_epoch_future_line_owner_count + 3'd1;
                end
            end
        end
    endfunction

    function automatic logic [1:0] prefix_mask(input logic [1:0] mask);
        begin
            unique case (mask)
                2'b00: prefix_mask = 2'b00;
                2'b01: prefix_mask = 2'b01;
                2'b11: prefix_mask = 2'b11;
                default: prefix_mask = 2'b00;
            endcase
        end
    endfunction

    function automatic bbus_ooo_pred_history_t history_push(
        input bbus_ooo_pred_history_t history,
        input logic taken
    );
        history_push = {history[6:0], taken};
    endfunction

    assign queue_second_idx_c = queue_head_q + 2'd1;
    assign queue_tail_idx_c = queue_head_q + queue_count_q[1:0];
    assign queue_count_valid_c = {
        (queue_count_q >= 3'd2),
        (queue_count_q >= 3'd1)
    };
    assign queue_epoch_valid_c = {
        (queue_epoch_q[queue_second_idx_c] == frontend_epoch_q),
        (queue_epoch_q[queue_head_q] == frontend_epoch_q)
    };
    assign queue_valid_c = queue_count_valid_c & queue_epoch_valid_c;
    assign queue_pc0_c = queue_pc_q[queue_head_q];
    assign queue_pc1_c = queue_pc_q[queue_second_idx_c];
    assign queue_instr0_c = queue_instr_q[queue_head_q];
    assign queue_instr1_c = queue_instr_q[queue_second_idx_c];
    assign queue_exception0_c = queue_exception_q[queue_head_q];
    assign queue_exception1_c = queue_exception_q[queue_second_idx_c];
    assign queue_branch_window_line0_c =
        queue_branch_window_line_q[queue_head_q];
    assign queue_branch_window_line1_c =
        queue_branch_window_line_q[queue_second_idx_c];
    assign queue_branch_window_line_word10_c =
        queue_branch_window_line_word1_q[queue_head_q];
    assign queue_branch_window_line_word11_c =
        queue_branch_window_line_word1_q[queue_second_idx_c];

    assign direct_target_line_c = FETCH_DECODE_FALLTHROUGH_ENABLE &&
        (queue_count_q == 3'd0) && target_line_delivery_common_c &&
        (queue_count_q + target_line_word_count_c <= 3'd4);
    assign direct_response_c = FETCH_DECODE_FALLTHROUGH_ENABLE &&
        (queue_count_q == 3'd0) && response_delivery_candidate_c;
    assign direct_delivery_c = direct_target_line_c || direct_response_c;
    assign cross_line_current_pc_c = direct_target_line_c ?
        next_pc_q : response_pc_c;
    assign cross_line_next_pc_c = cross_line_current_pc_c + 32'd4;
    assign cross_line_feature_enable_c = CACHED_CROSS_LINE_PAIR_ENABLE ||
        CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE;
    assign cross_line_direct_candidate_c =
        cross_line_feature_enable_c && direct_delivery_c &&
        cross_line_current_pc_c[2] &&
        (direct_target_line_c ||
         (direct_response_c && !fetch_rsp_page_fault_i &&
          (fetch_rsp_valid_mask_i == 2'b01)));
    assign cross_line_response_owner_safe_c = direct_response_c &&
        ((!response_from_queue_c && same_cycle_response_c) ||
         (response_from_queue_c && (request_count_q == 3'd1) &&
          (next_pc_q == response_pc_c + 32'd4)));
    assign cross_line_owner_safe_c = direct_target_line_c ||
        cross_line_response_owner_safe_c;
    assign cross_line_cached_pair_c = cross_line_direct_candidate_c &&
        adjacent_line_lookup_hit_c && cross_line_owner_safe_c;
    assign cross_line_initial_carry_c =
        CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE && cross_line_cached_pair_c;
    assign cross_line_carry_pc_c = cross_line_current_pc_c + 32'd8;
    assign cross_line_carry_instr_c = adjacent_line_lookup_data_c[63:32];
    assign cross_line_carry_head_c =
        CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE &&
        (queue_count_q == 3'd1) && queue_valid_c[0] &&
        (queue_singleton_origin_q[queue_head_q] ==
         SINGLETON_ORIGIN_CROSS_LINE_CARRY) &&
        !queue_exception0_c && (queue_pc0_c + 32'd4 == next_pc_q) &&
        queue_pc0_c[2] && !next_pc_q[2];

    always_comb begin
        incoming_valid_mask_c = 2'b00;
        incoming_pc0_c = 32'b0;
        incoming_pc1_c = 32'b0;
        incoming_instr0_c = 32'b0;
        incoming_instr1_c = 32'b0;
        incoming_exception0_c = 1'b0;
        incoming_branch_window_line_c = 1'b0;
        if (direct_target_line_c) begin
            incoming_valid_mask_c = next_pc_q[2] ? 2'b01 : 2'b11;
            incoming_pc0_c = next_pc_q;
            incoming_pc1_c = next_pc_q + 32'd4;
            incoming_instr0_c = next_pc_q[2] ?
                target_line_lookup_data_c[63:32] :
                target_line_lookup_data_c[31:0];
            incoming_instr1_c = target_line_lookup_data_c[63:32];
            incoming_branch_window_line_c =
                target_line_branch_window_inject_c;
        end else if (direct_response_c) begin
            incoming_valid_mask_c = fetch_rsp_page_fault_i ?
                2'b01 : fetch_rsp_valid_mask_i;
            incoming_pc0_c = response_pc_c;
            incoming_pc1_c = response_pc_c + 32'd4;
            incoming_instr0_c = response_pc_c[2] ?
                fetch_rsp_data_i[63:32] : fetch_rsp_data_i[31:0];
            incoming_instr1_c = fetch_rsp_data_i[63:32];
            incoming_exception0_c = fetch_rsp_page_fault_i;
        end
        if (cross_line_cached_pair_c) begin
            incoming_valid_mask_c = 2'b11;
            incoming_pc1_c = cross_line_next_pc_c;
            incoming_instr1_c = adjacent_line_lookup_data_c[31:0];
        end
    end

    always_comb begin
        decode_source_valid_c = queue_valid_c;
        decode_source_pc0_c = queue_pc0_c;
        decode_source_pc1_c = queue_pc1_c;
        decode_source_instr0_c = queue_instr0_c;
        decode_source_instr1_c = queue_instr1_c;
        decode_source_exception0_c = queue_exception0_c;
        decode_source_exception1_c = queue_exception1_c;
        decode_source_branch_window_line0_c = queue_branch_window_line0_c;
        decode_source_branch_window_line1_c = queue_branch_window_line1_c;
        decode_source_branch_window_line_word10_c =
            queue_branch_window_line_word10_c;
        decode_source_branch_window_line_word11_c =
            queue_branch_window_line_word11_c;
        if (direct_delivery_c) begin
            decode_source_valid_c = incoming_valid_mask_c;
            decode_source_pc0_c = incoming_pc0_c;
            decode_source_pc1_c = incoming_pc1_c;
            decode_source_instr0_c = incoming_instr0_c;
            decode_source_instr1_c = incoming_instr1_c;
            decode_source_exception0_c = incoming_exception0_c;
            decode_source_exception1_c = 1'b0;
            decode_source_branch_window_line0_c =
                incoming_branch_window_line_c;
            decode_source_branch_window_line1_c =
                incoming_branch_window_line_c;
            decode_source_branch_window_line_word10_c = 1'b0;
            decode_source_branch_window_line_word11_c =
                incoming_branch_window_line_c;
        end else if (cross_line_roll_candidate_c) begin
            decode_source_valid_c = 2'b11;
            decode_source_pc0_c = queue_pc0_c;
            decode_source_pc1_c = next_pc_q;
            decode_source_instr0_c = queue_instr0_c;
            decode_source_instr1_c = target_line_lookup_data_c[31:0];
            decode_source_exception0_c = 1'b0;
            decode_source_exception1_c = 1'b0;
            decode_source_branch_window_line0_c =
                queue_branch_window_line0_c;
            decode_source_branch_window_line1_c =
                target_line_branch_window_inject_c;
            decode_source_branch_window_line_word10_c =
                queue_branch_window_line_word10_c;
            decode_source_branch_window_line_word11_c = 1'b0;
        end
    end

    ooo_rv32i_alu_decode_adapter u_decode0 (
        .valid_i(decode_source_valid_c[0]),
        .pc_i(decode_source_pc0_c),
        .instr_i(decode_source_instr0_c),
        .supported_o(decode0_supported),
        .unsupported_o(decode0_unsupported),
        .decode_uop_o(decoded_uop0_c)
    );

    ooo_rv32i_alu_decode_adapter u_decode1 (
        .valid_i(decode_source_valid_c[1]),
        .pc_i(decode_source_pc1_c),
        .instr_i(decode_source_instr1_c),
        .supported_o(decode1_supported),
        .unsupported_o(decode1_unsupported),
        .decode_uop_o(decoded_uop1_c)
    );

    ooo_rv32i_alu_decode_adapter u_coalesce_incoming_decode (
        .valid_i(coalesce_incoming_mask_c[0] &&
                 !coalesce_incoming_exception_c),
        .pc_i(coalesce_incoming_pc_c),
        .instr_i(coalesce_incoming_instr_c),
        .supported_o(coalesce_incoming_supported_c),
        .unsupported_o(coalesce_incoming_unsupported_c),
        .decode_uop_o(coalesce_incoming_uop_c)
    );

    assign slot0_conditional_c = decode_source_valid_c[0] &&
        !decode_source_exception0_c && decode0_supported &&
        (decoded_uop0_c.fu_type == BBUS_OOO_FU_BRU) &&
        (decoded_uop0_c.branch_op != BBUS_OOO_BR_JAL) &&
        (decoded_uop0_c.branch_op != BBUS_OOO_BR_JALR);
    assign slot1_conditional_c = decode_source_valid_c[1] &&
        !decode_source_exception1_c && decode1_supported &&
        (decoded_uop1_c.fu_type == BBUS_OOO_FU_BRU) &&
        (decoded_uop1_c.branch_op != BBUS_OOO_BR_JAL) &&
        (decoded_uop1_c.branch_op != BBUS_OOO_BR_JALR);

    assign predictor_lookup_history0_c = CORRELATED_PREDICTOR_ENABLE ?
        predictor_history_q : '0;
    assign predictor_lookup_history1_c = !CORRELATED_PREDICTOR_ENABLE ? '0 :
        slot0_conditional_c ?
        history_push(predictor_history_q, predictor_taken0_c) :
        predictor_history_q;

    ooo_tagged_btb_bht_2w #(
        .ENTRIES(CONDITIONAL_PRED_ENTRIES),
        .CORRELATED_ENABLE(CORRELATED_PREDICTOR_ENABLE),
        .LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE(
            LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE),
        .MULTIHISTORY_REACHABILITY_ORACLE_ENABLE(
            MULTIHISTORY_REACHABILITY_ORACLE_ENABLE)
    ) u_predictor (
        .clk(clk),
        .reset(reset),
        .lookup_valid_i({slot1_conditional_c, slot0_conditional_c}),
        .lookup_pc0_i(decoded_uop0_c.pc),
        .lookup_pc1_i(decoded_uop1_c.pc),
        .fallback_taken0_i(decoded_uop0_c.imm[31]),
        .fallback_taken1_i(decoded_uop1_c.imm[31]),
        .direct_target0_i(decoded_uop0_c.pc + decoded_uop0_c.imm),
        .direct_target1_i(decoded_uop1_c.pc + decoded_uop1_c.imm),
        .lookup_history0_i(predictor_lookup_history0_c),
        .lookup_history1_i(predictor_lookup_history1_c),
        .hit0_o(predictor_hit0_c),
        .hit1_o(predictor_hit1_c),
        .strong0_o(predictor_strong0_c),
        .strong1_o(predictor_strong1_c),
        .correlated0_o(predictor_correlated0_c),
        .correlated1_o(predictor_correlated1_c),
        .base_taken0_o(predictor_base_taken0_c),
        .base_taken1_o(predictor_base_taken1_c),
        .base_counter_valid0_o(predictor_base_counter_valid0_c),
        .base_counter_valid1_o(predictor_base_counter_valid1_c),
        .base_counter_taken0_o(predictor_base_counter_taken0_c),
        .base_counter_taken1_o(predictor_base_counter_taken1_c),
        .correlated_candidate0_o(predictor_corr_candidate0_c),
        .correlated_candidate1_o(predictor_corr_candidate1_c),
        .correlated_raw_candidate0_o(predictor_corr_raw_candidate0_c),
        .correlated_raw_candidate1_o(predictor_corr_raw_candidate1_c),
        .correlated_chooser_prefer0_o(predictor_corr_chooser_prefer0_c),
        .correlated_chooser_prefer1_o(predictor_corr_chooser_prefer1_c),
        .correlated_taken0_o(predictor_corr_taken0_c),
        .correlated_taken1_o(predictor_corr_taken1_c),
        .local_history0_o(predictor_local_history0_c),
        .local_history1_o(predictor_local_history1_c),
        .local_strong0_o(predictor_local_strong0_c),
        .local_strong1_o(predictor_local_strong1_c),
        .local_taken0_o(predictor_local_taken0_c),
        .local_taken1_o(predictor_local_taken1_c),
        .local_chooser_prefer0_o(predictor_local_chooser_prefer0_c),
        .local_chooser_prefer1_o(predictor_local_chooser_prefer1_c),
        .local_chooser_strong0_o(predictor_local_chooser_strong0_c),
        .local_chooser_strong1_o(predictor_local_chooser_strong1_c),
        .multihistory_hit0_o(predictor_multihistory_hit0_c),
        .multihistory_hit1_o(predictor_multihistory_hit1_c),
        .multihistory_strong0_o(predictor_multihistory_strong0_c),
        .multihistory_strong1_o(predictor_multihistory_strong1_c),
        .multihistory_taken0_o(predictor_multihistory_taken0_c),
        .multihistory_taken1_o(predictor_multihistory_taken1_c),
        .multihistory_chooser_prefer0_o(
            predictor_multihistory_chooser_prefer0_c),
        .multihistory_chooser_prefer1_o(
            predictor_multihistory_chooser_prefer1_c),
        .multihistory_chooser_strong0_o(
            predictor_multihistory_chooser_strong0_c),
        .multihistory_chooser_strong1_o(
            predictor_multihistory_chooser_strong1_c),
        .pred_taken0_o(predictor_taken0_c),
        .pred_taken1_o(predictor_taken1_c),
        .pred_target0_o(predictor_target0_c),
        .pred_target1_o(predictor_target1_c),
        .update_valid_i(predictor_update_valid_i),
        .update_pc_i(predictor_update_pc_i),
        .update_direct_target_i(predictor_update_direct_target_i),
        .update_history_i(predictor_update_history_i),
        .update_base_taken_i(predictor_update_base_taken_i),
        .update_correlated_candidate_i(
            predictor_update_correlated_candidate_i),
        .update_correlated_taken_i(predictor_update_correlated_taken_i),
        .update_local_history_i(predictor_update_local_history_i),
        .update_local_strong_i(predictor_update_local_strong_i),
        .update_local_taken_i(predictor_update_local_taken_i),
        .update_multihistory_strong_i(
            predictor_update_multihistory_strong_i),
        .update_multihistory_taken_i(
            predictor_update_multihistory_taken_i),
        .update_current_taken_i(predictor_update_current_taken_i),
        .update_taken_i(predictor_update_taken_i)
    );

    assign slot0_jalr_c = decode_source_valid_c[0] &&
        !decode_source_exception0_c &&
        decode0_supported && (decoded_uop0_c.branch_op == BBUS_OOO_BR_JALR);
    assign slot1_jalr_c = decode_source_valid_c[1] &&
        !decode_source_exception1_c &&
        decode1_supported && (decoded_uop1_c.branch_op == BBUS_OOO_BR_JALR);
    assign slot0_return_c = slot0_jalr_c &&
        ((decoded_uop0_c.arch_rs1 == bbus_ooo_arch_reg_t'(5'd1)) ||
         (decoded_uop0_c.arch_rs1 == bbus_ooo_arch_reg_t'(5'd5))) &&
        (decoded_uop0_c.arch_rd != bbus_ooo_arch_reg_t'(5'd1)) &&
        (decoded_uop0_c.arch_rd != bbus_ooo_arch_reg_t'(5'd5));
    assign slot1_return_c = slot1_jalr_c &&
        ((decoded_uop1_c.arch_rs1 == bbus_ooo_arch_reg_t'(5'd1)) ||
         (decoded_uop1_c.arch_rs1 == bbus_ooo_arch_reg_t'(5'd5))) &&
        (decoded_uop1_c.arch_rd != bbus_ooo_arch_reg_t'(5'd1)) &&
        (decoded_uop1_c.arch_rd != bbus_ooo_arch_reg_t'(5'd5));

    ooo_jalr_btb_ras_2w #(
        .SAME_CYCLE_UPDATE_FORWARDING_ENABLE(
            SAME_CYCLE_RAS_UPDATE_FORWARDING_ENABLE),
        .RAS_SELF_FORWARD_EXCLUSION_ENABLE(
            RAS_SELF_FORWARD_EXCLUSION_ENABLE)
    ) u_indirect_predictor (
        .clk(clk),
        .reset(reset),
        .clear_ras_i(global_recover_i),
        .lookup_valid_i({slot1_jalr_c, slot0_jalr_c}),
        .lookup_pc0_i(decoded_uop0_c.pc),
        .lookup_pc1_i(decoded_uop1_c.pc),
        .lookup_return0_i(slot0_return_c),
        .lookup_return1_i(slot1_return_c),
        .pred_taken0_o(indirect_taken0_c),
        .pred_taken1_o(indirect_taken1_c),
        .pred_target0_o(indirect_target0_c),
        .pred_target1_o(indirect_target1_c),
        .btb_hit0_o(indirect_btb_hit0_c),
        .btb_hit1_o(indirect_btb_hit1_c),
        .ras_hit0_o(indirect_ras_hit0_c),
        .ras_hit1_o(indirect_ras_hit1_c),
        .self_forward_collision_o(ras_self_forward_collision_c),
        .btb_update_valid_i(indirect_update_valid_i),
        .btb_update_pc_i(indirect_update_pc_i),
        .btb_update_target_i(indirect_update_target_i),
        .ras_update_valid_i(ras_update_valid_i),
        .ras_update_action_i(ras_update_action_i),
        .ras_update_link_i(ras_update_link_i),
        .ras_restore_valid_i(ras_restore_valid_i),
        .ras_restore_ready_o(ras_restore_ready_o),
        .ras_restore_snapshot_i(ras_restore_snapshot_i),
        .ras_restore_payload_valid_o(ras_restore_payload_valid_o),
        .ras_restore_replay_action_i(ras_restore_replay_action_i),
        .ras_restore_replay_link_i(ras_restore_replay_link_i),
        .ras_restore_fire_o(ras_restore_fire_o),
        .ras_restore_collision_error_o(ras_restore_collision_error_o),
        .ras_restore_invalid_error_o(ras_restore_invalid_error_o),
        .ras_snapshot_o(ras_snapshot_o)
    );

    assign oldest_unsupported_c = decode_source_valid_c[0] &&
        !decode_source_exception0_c && decode0_unsupported;
    assign younger_unsupported_c =
        (decode_source_valid_c == 2'b11) && decode0_supported &&
        !decode_source_exception1_c && decode1_unsupported;
    assign slot0_predict_taken_c = decode_source_valid_c[0] &&
        !decode_source_exception0_c && decode0_supported &&
        (decoded_uop0_c.fu_type == BBUS_OOO_FU_BRU) &&
        ((decoded_uop0_c.branch_op == BBUS_OOO_BR_JAL) ||
         (slot0_conditional_c && predictor_taken0_c) ||
         (slot0_jalr_c && indirect_taken0_c));
    assign slot1_predict_taken_c = decode_source_valid_c[1] &&
        !decode_source_exception1_c && decode1_supported &&
        (decoded_uop1_c.fu_type == BBUS_OOO_FU_BRU) &&
        ((decoded_uop1_c.branch_op == BBUS_OOO_BR_JAL) ||
         (slot1_conditional_c && predictor_taken1_c) ||
         (slot1_jalr_c && indirect_taken1_c));
    assign visible_queue_mask_c =
        (oldest_unsupported_c || younger_unsupported_c ||
         slot0_predict_taken_c || slot0_jalr_c) ?
        2'b01 : decode_source_valid_c;
    assign output_enable_c = !reset && !global_recover_i && !stop_i &&
        !branch_recovery_pending_i && !redirect_valid_i && !frontend_fault_q;
    assign decode_valid_mask_o =
        output_enable_c ? visible_queue_mask_c : 2'b00;

    assign legal_decode_accept_c =
        (decode_accept_mask_i == prefix_mask(decode_accept_mask_i)) &&
        ((decode_accept_mask_i & ~decode_valid_mask_o) == 2'b00);
    assign decode_pop_mask_c =
        legal_decode_accept_c ? decode_accept_mask_i : 2'b00;
    assign direct_accept_mask_c = direct_delivery_c ?
        decode_pop_mask_c : 2'b00;
    assign cross_line_roll_accept_mask_c = cross_line_roll_candidate_c ?
        decode_pop_mask_c : 2'b00;
    assign cross_line_roll_fire_c = cross_line_roll_candidate_c &&
        cross_line_roll_accept_mask_c[0];
    always_comb begin
        cross_line_initial_buffer_count_c = 2'd0;
        if (cross_line_initial_carry_c) begin
            unique case (direct_accept_mask_c)
                2'b00: cross_line_initial_buffer_count_c = 2'd3;
                2'b01: cross_line_initial_buffer_count_c = 2'd2;
                2'b11: cross_line_initial_buffer_count_c = 2'd1;
                default: cross_line_initial_buffer_count_c = 2'd0;
            endcase
        end
    end
    always_comb begin
        cross_line_roll_buffer_count_c = 2'd0;
        if (cross_line_roll_fire_c) begin
            cross_line_roll_buffer_count_c =
                (cross_line_roll_accept_mask_c == 2'b11) ? 2'd1 : 2'd2;
        end
    end
    assign cross_line_direct_advance_words_c =
        cross_line_initial_carry_c ? 3'd3 :
        cross_line_cached_pair_c ? 3'd2 : request_word_count_c;
    assign decode_pop_count_c = direct_delivery_c ? 2'd0 :
        cross_line_roll_candidate_c ?
        {1'b0, cross_line_roll_accept_mask_c[0]} :
        ({1'b0, decode_pop_mask_c[0]} +
         {1'b0, decode_pop_mask_c[1]});
    assign cross_line_carry_promote_c =
        CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE &&
        !direct_delivery_c && !taken_predict_fire_c &&
        (queue_count_after_pop_c == 3'd1) &&
        (queue_count_q > decode_pop_count_c) &&
        (queue_singleton_origin_q[
            queue_head_q + decode_pop_count_c[1:0]] ==
         SINGLETON_ORIGIN_CROSS_LINE_CARRY) &&
        (decode_pop_count_c != 2'd0);
    always_comb begin
        predictor_history_after_accept_c = predictor_history_q;
        if (CORRELATED_PREDICTOR_ENABLE && decode_pop_mask_c[0] &&
            slot0_conditional_c) begin
            predictor_history_after_accept_c = history_push(
                predictor_history_after_accept_c,
                predictor_taken0_c
            );
        end
        if (CORRELATED_PREDICTOR_ENABLE && decode_pop_mask_c[1] &&
            slot1_conditional_c) begin
            predictor_history_after_accept_c = history_push(
                predictor_history_after_accept_c,
                predictor_taken1_c
            );
        end
    end
    assign queue_count_after_pop_c = queue_count_q - decode_pop_count_c;
    assign fresh_reserved_words_c = current_epoch_reserved_words();
    assign current_epoch_owner_count_c = current_epoch_owner_count();
    assign current_epoch_exact_pc_owner_count_c =
        current_epoch_exact_pc_owner_count();
    assign current_epoch_same_line_owner_count_c =
        current_epoch_same_line_owner_count();
    assign current_epoch_future_line_owner_count_c =
        current_epoch_future_line_owner_count();
    assign reservation_head_current_c = response_from_queue_c &&
        (request_epoch_q[request_head_q] == frontend_epoch_q);
    assign reservation_head_exact_pc_c = reservation_head_current_c &&
        (request_pc_q[request_head_q] == next_pc_q);
    assign reservation_head_same_line_c = reservation_head_current_c &&
        (request_addr_q[request_head_q] == {next_pc_q[31:3], 3'b000});
    assign redirect_ready_o = !reset && !global_recover_i;
    assign redirect_fire_c = redirect_valid_i && redirect_ready_o;
    assign response_from_queue_c = (request_count_q != 3'd0);
    assign same_cycle_response_c = !response_from_queue_c &&
        request_base_fire_c && response_fire_c;
    assign request_word_count_c = next_pc_q[2] ? 3'd1 : 3'd2;
    assign request_capacity_c =
        (queue_count_after_pop_c + reserved_words_q +
         request_word_count_c <= 3'd4);
    assign current_request_capacity_c =
        (queue_count_after_pop_c + fresh_reserved_words_c +
         request_word_count_c <= 3'd4);
    assign target_line_word_count_c = next_pc_q[2] ? 3'd1 : 3'd2;
    assign target_line_capacity_c =
        (queue_count_after_pop_c + target_line_word_count_c <= 3'd4);
    assign frontend_control_present_c =
        (queue_valid_c[0] && !queue_exception0_c && decode0_supported &&
         (decoded_uop0_c.fu_type == BBUS_OOO_FU_BRU)) ||
        (queue_valid_c[1] && !queue_exception1_c && decode1_supported &&
         (decoded_uop1_c.fu_type == BBUS_OOO_FU_BRU));
    assign branch_window_line_delivery_c =
        BRANCH_WINDOW_LINE_DELIVERY_ENABLE &&
        branch_window_line_delivery_safe_i;
    assign sequential_line_eligible_hit_c = SEQUENTIAL_LINE_HIT_ENABLE &&
        (!branch_window_active_i || branch_window_line_delivery_c) &&
        !frontend_control_present_c &&
        (target_line_word_count_c == 3'd2) &&
        target_line_lookup_hit_c;
    assign target_line_eligible_hit_c = target_line_lookup_hit_c &&
        (target_line_lookup_pending_q || sequential_line_eligible_hit_c);
    assign sequential_line_candidate_c = target_line_lookup_hit_c &&
        !target_line_lookup_pending_q;
    assign target_line_delivery_common_c = target_line_eligible_hit_c &&
        (fresh_reserved_words_c == 3'd0) &&
        !reset && !global_recover_i && !stop_i &&
        !branch_recovery_pending_i && !redirect_valid_i &&
        !frontend_fault_q && !frontend_eof_q &&
        !response_fire_c;
    assign cross_line_roll_candidate_c = cross_line_carry_head_c &&
        target_line_delivery_common_c &&
        (target_line_word_count_c == 3'd2);
    assign target_line_candidate_c = target_line_delivery_common_c &&
        !cross_line_carry_promote_c &&
        (target_line_capacity_c || direct_target_line_c);
    assign target_line_inject_c = cross_line_roll_fire_c ||
        (target_line_candidate_c && !cross_line_roll_candidate_c &&
         (!taken_predict_fire_c || direct_target_line_c));
    assign target_line_branch_window_inject_c = target_line_inject_c &&
        !target_line_lookup_pending_q && branch_window_active_i;
    assign fetch_req_valid_base_c = !reset && !global_recover_i && !stop_i &&
        !branch_recovery_pending_i && !redirect_valid_i &&
        !taken_predict_fire_c && !frontend_fault_q && !frontend_eof_q &&
        !(cross_line_cached_pair_c && response_from_queue_c) &&
        !target_line_eligible_hit_c &&
        (request_count_q < 3'd4) && request_capacity_c;
    assign fetch_req_valid_o = fetch_req_valid_base_c ||
        (FETCH_RESPONSE_CREDIT_TURNOVER_ENABLE &&
         response_credit_structural_eligible_c &&
         !branch_window_active_i);
    assign fetch_req_addr_o = {next_pc_q[31:3], 3'b000};
    assign fetch_req_pc_o = next_pc_q;
    assign request_base_fire_c = fetch_req_valid_base_c && fetch_req_ready_i;
    assign request_fire_c = fetch_req_valid_o && fetch_req_ready_i;
    assign response_has_owner_c = response_from_queue_c ||
        request_base_fire_c;
    assign response_stale_c = response_from_queue_c &&
        (request_epoch_q[request_head_q] != frontend_epoch_q);
    assign invalidation_level_c = global_recover_i || stop_i ||
        branch_recovery_pending_i;
    assign response_pc_c = response_from_queue_c ?
        request_pc_q[request_head_q] : next_pc_q;
    assign response_addr_c = response_from_queue_c ?
        request_addr_q[request_head_q] :
        {next_pc_q[31:3], 3'b000};
    assign expected_rsp_mask_c = response_pc_c[2] ? 2'b01 : 2'b11;
    assign response_malformed_c = !(fetch_rsp_page_fault_i === 1'b1) && (
        (fetch_rsp_addr_i != response_addr_c) ||
        (fetch_rsp_eof_i && (fetch_rsp_valid_mask_i != 2'b00)) ||
         (!fetch_rsp_eof_i && (fetch_rsp_valid_mask_i != expected_rsp_mask_c)));
    assign response_delivery_candidate_c = response_fire_c &&
        response_has_owner_c && !response_stale_c && !redirect_fire_c &&
        !invalidation_level_c && !frontend_fault_q && !frontend_eof_q &&
        ((fetch_rsp_page_fault_i === 1'b1) ||
         (!fetch_rsp_error_i && !fetch_rsp_eof_i &&
          !response_malformed_c));
    assign target_line_fill_c = response_fire_c && response_has_owner_c &&
        !response_stale_c && !redirect_fire_c &&
        (!taken_predict_fire_c || direct_response_c) &&
        !invalidation_level_c && !fetch_rsp_page_fault_i &&
        !fetch_rsp_error_i && !fetch_rsp_eof_i && !response_malformed_c;
    assign taken_predict_fire_c =
        (decode_pop_mask_c[0] && slot0_predict_taken_c) ||
        (decode_pop_mask_c[1] && slot1_predict_taken_c);
    assign safe_taken_predict_fire_c =
        (decode_pop_mask_c[0] && slot0_predict_taken_c &&
         (decoded_uop0_c.branch_op == BBUS_OOO_BR_JAL)) ||
        (decode_pop_mask_c[1] && slot1_predict_taken_c &&
         (decoded_uop1_c.branch_op == BBUS_OOO_BR_JAL));
    assign taken_predict_target_c =
        (decode_pop_mask_c[1] && slot1_predict_taken_c) ?
        ((decoded_uop1_c.branch_op == BBUS_OOO_BR_JAL) ?
         (decoded_uop1_c.pc + decoded_uop1_c.imm) :
         (decoded_uop1_c.branch_op == BBUS_OOO_BR_JALR) ?
         indirect_target1_c : predictor_target1_c) :
        ((decoded_uop0_c.branch_op == BBUS_OOO_BR_JAL) ?
         (decoded_uop0_c.pc + decoded_uop0_c.imm) :
         (decoded_uop0_c.branch_op == BBUS_OOO_BR_JALR) ?
         indirect_target0_c : predictor_target0_c);

    always_comb begin
        perf_request_reason_c = 4'd0;
        if (!reset) begin
            if (request_fire_c) begin
                perf_request_reason_c = PERF_REQ_FIRED;
            end else if (global_recover_i || branch_recovery_pending_i ||
                         redirect_valid_i || taken_predict_fire_c) begin
                perf_request_reason_c = PERF_REQ_RECOVERY_CONTROL;
            end else if (stop_i || frontend_fault_q || frontend_eof_q) begin
                perf_request_reason_c = PERF_REQ_TERMINAL_FAULT;
            end else if (target_line_eligible_hit_c ||
                         (cross_line_cached_pair_c &&
                          response_from_queue_c)) begin
                perf_request_reason_c = PERF_REQ_TARGET_LINE;
            end else if (request_count_q == 3'd4) begin
                perf_request_reason_c =
                    (current_epoch_owner_count_c == 3'd4) ?
                    PERF_REQ_CURRENT_OWNER_FULL : PERF_REQ_STALE_OWNER_FULL;
            end else if (!request_capacity_c) begin
                perf_request_reason_c = current_request_capacity_c ?
                    PERF_REQ_STALE_CREDIT_BLOCK :
                    PERF_REQ_CURRENT_CREDIT_FULL;
            end else if (fetch_req_valid_o && !fetch_req_ready_i) begin
                perf_request_reason_c = PERF_REQ_DOWNSTREAM_NOT_READY;
            end else begin
                perf_request_reason_c = PERF_REQ_OTHER;
            end
        end
    end

    always_comb begin
        perf_sequential_reason_c = 4'd0;
        if (!reset && sequential_line_candidate_c) begin
            if (target_line_inject_c && !target_line_lookup_pending_q) begin
                perf_sequential_reason_c = PERF_SEQ_INJECTED;
            end else if (!SEQUENTIAL_LINE_HIT_ENABLE) begin
                perf_sequential_reason_c = PERF_SEQ_DISABLED;
            end else if (global_recover_i || stop_i ||
                         branch_recovery_pending_i || redirect_valid_i ||
                         taken_predict_fire_c || frontend_fault_q ||
                         frontend_eof_q) begin
                perf_sequential_reason_c = PERF_SEQ_RECOVERY_TERMINAL;
            end else if (branch_window_active_i &&
                         !branch_window_line_delivery_c) begin
                perf_sequential_reason_c = PERF_SEQ_BRANCH_WINDOW;
            end else if (frontend_control_present_c) begin
                perf_sequential_reason_c = PERF_SEQ_QUEUED_CONTROL;
            end else if (target_line_word_count_c != 3'd2) begin
                perf_sequential_reason_c = PERF_SEQ_PARTIAL_PAIR;
            end else if (cross_line_roll_candidate_c) begin
                perf_sequential_reason_c = PERF_SEQ_CURRENT_RESERVED;
            end else if (cross_line_carry_promote_c) begin
                perf_sequential_reason_c = PERF_SEQ_CURRENT_RESERVED;
            end else if (fresh_reserved_words_c != 3'd0) begin
                perf_sequential_reason_c = PERF_SEQ_CURRENT_RESERVED;
            end else if (!target_line_capacity_c) begin
                perf_sequential_reason_c = PERF_SEQ_QUEUE_CAPACITY;
            end else if (response_fire_c) begin
                perf_sequential_reason_c = PERF_SEQ_RESPONSE_CONFLICT;
            end else begin
                perf_sequential_reason_c = PERF_SEQ_OTHER;
            end
        end
    end

    always_comb begin
        decode_uop0_o = decoded_uop0_c;
        decode_uop1_o = decoded_uop1_c;
        if ((decoded_uop0_c.fu_type == BBUS_OOO_FU_BRU) &&
            (decoded_uop0_c.branch_op == BBUS_OOO_BR_JAL)) begin
            decode_uop0_o.pred_taken = 1'b1;
            decode_uop0_o.pred_target = decoded_uop0_c.pc + decoded_uop0_c.imm;
            decode_uop0_o.pred_source = BBUS_OOO_PRED_DIRECT_JAL;
            decode_uop0_o.pred_history = predictor_lookup_history0_c;
        end else if (slot0_conditional_c) begin
            decode_uop0_o.pred_taken = predictor_taken0_c;
            decode_uop0_o.pred_target = predictor_taken0_c ?
                predictor_target0_c : decoded_uop0_c.pc + 32'd4;
            decode_uop0_o.pred_source = !predictor_hit0_c ?
                BBUS_OOO_PRED_COND_MISS : predictor_strong0_c ?
                BBUS_OOO_PRED_COND_STRONG : BBUS_OOO_PRED_COND_WEAK;
            decode_uop0_o.pred_correlated = predictor_correlated0_c;
            decode_uop0_o.pred_base_taken = predictor_base_taken0_c;
            decode_uop0_o.pred_base_counter_valid =
                WEAK_BIMODAL_REACHABILITY_ORACLE_ENABLE &&
                predictor_base_counter_valid0_c;
            decode_uop0_o.pred_base_counter_taken =
                WEAK_BIMODAL_REACHABILITY_ORACLE_ENABLE &&
                predictor_base_counter_taken0_c;
            decode_uop0_o.pred_corr_candidate = predictor_corr_candidate0_c;
            decode_uop0_o.pred_corr_raw_candidate =
                CORRELATED_REACHABILITY_ORACLE_ENABLE &&
                predictor_corr_raw_candidate0_c;
            decode_uop0_o.pred_corr_chooser_prefer =
                CORRELATED_REACHABILITY_ORACLE_ENABLE &&
                predictor_corr_chooser_prefer0_c;
            decode_uop0_o.pred_corr_taken = predictor_corr_taken0_c;
            decode_uop0_o.pred_history = predictor_lookup_history0_c;
            decode_uop0_o.pred_local_history =
                predictor_local_history0_c;
            decode_uop0_o.pred_local_strong =
                LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE &&
                predictor_local_strong0_c;
            decode_uop0_o.pred_local_taken =
                LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE &&
                predictor_local_taken0_c;
            decode_uop0_o.pred_local_chooser_prefer =
                LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE &&
                predictor_local_chooser_prefer0_c;
            decode_uop0_o.pred_local_chooser_strong =
                LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE &&
                predictor_local_chooser_strong0_c;
            decode_uop0_o.pred_multihistory_hit =
                MULTIHISTORY_REACHABILITY_ORACLE_ENABLE ?
                predictor_multihistory_hit0_c : '0;
            decode_uop0_o.pred_multihistory_strong =
                MULTIHISTORY_REACHABILITY_ORACLE_ENABLE ?
                predictor_multihistory_strong0_c : '0;
            decode_uop0_o.pred_multihistory_taken =
                MULTIHISTORY_REACHABILITY_ORACLE_ENABLE ?
                predictor_multihistory_taken0_c : '0;
            decode_uop0_o.pred_multihistory_chooser_prefer =
                MULTIHISTORY_REACHABILITY_ORACLE_ENABLE ?
                predictor_multihistory_chooser_prefer0_c : '0;
            decode_uop0_o.pred_multihistory_chooser_strong =
                MULTIHISTORY_REACHABILITY_ORACLE_ENABLE ?
                predictor_multihistory_chooser_strong0_c : '0;
        end else if (slot0_jalr_c) begin
            decode_uop0_o.pred_taken = indirect_taken0_c;
            decode_uop0_o.pred_target = indirect_target0_c;
            decode_uop0_o.pred_source = indirect_ras_hit0_c ?
                BBUS_OOO_PRED_JALR_RAS : indirect_btb_hit0_c ?
                BBUS_OOO_PRED_JALR_BTB : BBUS_OOO_PRED_JALR_MISS;
            decode_uop0_o.pred_history = predictor_lookup_history0_c;
            decode_uop0_o.pred_ras_self_collision =
                ras_self_forward_collision_c[0];
        end
        if ((decoded_uop1_c.fu_type == BBUS_OOO_FU_BRU) &&
            (decoded_uop1_c.branch_op == BBUS_OOO_BR_JAL)) begin
            decode_uop1_o.pred_taken = 1'b1;
            decode_uop1_o.pred_target = decoded_uop1_c.pc + decoded_uop1_c.imm;
            decode_uop1_o.pred_source = BBUS_OOO_PRED_DIRECT_JAL;
            decode_uop1_o.pred_history = predictor_lookup_history1_c;
        end else if (slot1_conditional_c) begin
            decode_uop1_o.pred_taken = predictor_taken1_c;
            decode_uop1_o.pred_target = predictor_taken1_c ?
                predictor_target1_c : decoded_uop1_c.pc + 32'd4;
            decode_uop1_o.pred_source = !predictor_hit1_c ?
                BBUS_OOO_PRED_COND_MISS : predictor_strong1_c ?
                BBUS_OOO_PRED_COND_STRONG : BBUS_OOO_PRED_COND_WEAK;
            decode_uop1_o.pred_correlated = predictor_correlated1_c;
            decode_uop1_o.pred_base_taken = predictor_base_taken1_c;
            decode_uop1_o.pred_base_counter_valid =
                WEAK_BIMODAL_REACHABILITY_ORACLE_ENABLE &&
                predictor_base_counter_valid1_c;
            decode_uop1_o.pred_base_counter_taken =
                WEAK_BIMODAL_REACHABILITY_ORACLE_ENABLE &&
                predictor_base_counter_taken1_c;
            decode_uop1_o.pred_corr_candidate = predictor_corr_candidate1_c;
            decode_uop1_o.pred_corr_raw_candidate =
                CORRELATED_REACHABILITY_ORACLE_ENABLE &&
                predictor_corr_raw_candidate1_c;
            decode_uop1_o.pred_corr_chooser_prefer =
                CORRELATED_REACHABILITY_ORACLE_ENABLE &&
                predictor_corr_chooser_prefer1_c;
            decode_uop1_o.pred_corr_taken = predictor_corr_taken1_c;
            decode_uop1_o.pred_history = predictor_lookup_history1_c;
            decode_uop1_o.pred_local_history =
                predictor_local_history1_c;
            decode_uop1_o.pred_local_strong =
                LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE &&
                predictor_local_strong1_c;
            decode_uop1_o.pred_local_taken =
                LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE &&
                predictor_local_taken1_c;
            decode_uop1_o.pred_local_chooser_prefer =
                LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE &&
                predictor_local_chooser_prefer1_c;
            decode_uop1_o.pred_local_chooser_strong =
                LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE &&
                predictor_local_chooser_strong1_c;
            decode_uop1_o.pred_multihistory_hit =
                MULTIHISTORY_REACHABILITY_ORACLE_ENABLE ?
                predictor_multihistory_hit1_c : '0;
            decode_uop1_o.pred_multihistory_strong =
                MULTIHISTORY_REACHABILITY_ORACLE_ENABLE ?
                predictor_multihistory_strong1_c : '0;
            decode_uop1_o.pred_multihistory_taken =
                MULTIHISTORY_REACHABILITY_ORACLE_ENABLE ?
                predictor_multihistory_taken1_c : '0;
            decode_uop1_o.pred_multihistory_chooser_prefer =
                MULTIHISTORY_REACHABILITY_ORACLE_ENABLE ?
                predictor_multihistory_chooser_prefer1_c : '0;
            decode_uop1_o.pred_multihistory_chooser_strong =
                MULTIHISTORY_REACHABILITY_ORACLE_ENABLE ?
                predictor_multihistory_chooser_strong1_c : '0;
        end else if (slot1_jalr_c) begin
            decode_uop1_o.pred_taken = indirect_taken1_c;
            decode_uop1_o.pred_target = indirect_target1_c;
            decode_uop1_o.pred_source = indirect_ras_hit1_c ?
                BBUS_OOO_PRED_JALR_RAS : indirect_btb_hit1_c ?
                BBUS_OOO_PRED_JALR_BTB : BBUS_OOO_PRED_JALR_MISS;
            decode_uop1_o.pred_history = predictor_lookup_history1_c;
            decode_uop1_o.pred_ras_self_collision =
                ras_self_forward_collision_c[1];
        end
        if (decode_source_exception0_c) begin
            decode_uop0_o = '0;
            decode_uop0_o.valid = decode_source_valid_c[0];
            decode_uop0_o.pc = decode_source_pc0_c;
            decode_uop0_o.fu_type = BBUS_OOO_FU_SYS;
            decode_uop0_o.is_system = 1'b1;
            decode_uop0_o.exception.valid = 1'b1;
            decode_uop0_o.exception.cause = 32'd12;
            decode_uop0_o.exception.tval = decode_source_pc0_c;
        end
        if (decode_source_exception1_c) begin
            decode_uop1_o = '0;
            decode_uop1_o.valid = decode_source_valid_c[1];
            decode_uop1_o.pc = decode_source_pc1_c;
            decode_uop1_o.fu_type = BBUS_OOO_FU_SYS;
            decode_uop1_o.is_system = 1'b1;
            decode_uop1_o.exception.valid = 1'b1;
            decode_uop1_o.exception.cause = 32'd12;
            decode_uop1_o.exception.tval = decode_source_pc1_c;
        end
        decode_uop0_o.branch_window_line = decode_source_valid_c[0] &&
            decode_source_branch_window_line0_c;
        decode_uop1_o.branch_window_line = decode_source_valid_c[1] &&
            decode_source_branch_window_line1_c;
        decode_uop0_o.branch_window_line_word1 =
            decode_uop0_o.branch_window_line &&
            decode_source_branch_window_line_word10_c;
        decode_uop1_o.branch_window_line_word1 =
            decode_uop1_o.branch_window_line &&
            decode_source_branch_window_line_word11_c;
    end

    // A response is always consumed once it arrives. It is either queued,
    // terminally faulted, or absorbed as stale ownership.
    assign fetch_rsp_ready_o = !reset;
    assign response_fire_c = fetch_rsp_valid_i && fetch_rsp_ready_o;

    assign fetch_pc_o = response_from_queue_c ?
        request_pc_q[request_head_q] : next_pc_q;
    assign raw_queue_valid_mask_o = queue_valid_c;
    assign raw_queue_pc0_o = queue_valid_c[0] ? queue_pc0_c : '0;
    assign raw_queue_pc1_o = queue_valid_c[1] ? queue_pc1_c : '0;
    assign request_outstanding_o = (request_count_q != 3'd0);
    assign stale_response_pending_o = response_stale_c;
    assign frontend_fault_o = frontend_fault_q;
    assign frontend_fault_pc_o = frontend_fault_pc_q;
    assign frontend_eof_o = frontend_eof_q;
    assign malformed_response_o = malformed_response_q;
    assign unsupported_seen_o = unsupported_seen_q;
    assign pending_clear_o = branch_recovery_pending_i;
    assign redirect_clear_o = redirect_fire_c;
    assign stale_response_drop_o = stale_response_drop_q;
    assign target_line_hit_o = target_line_inject_c;
    assign target_line_sequential_hit_o = target_line_inject_c &&
        !target_line_lookup_pending_q;
    assign target_line_branch_window_hit_o =
        target_line_branch_window_inject_c;
    assign target_line_fill_o = TARGET_LINE_HIT_ENABLE && target_line_fill_c;
    assign target_line_miss_o = TARGET_LINE_HIT_ENABLE &&
        target_line_lookup_pending_q && request_fire_c;
    always_comb begin
        perf_fetch_delivery_width_o = 2'd0;
        if (target_line_inject_c) begin
            perf_fetch_delivery_width_o = cross_line_cached_pair_c ?
                2'd2 : target_line_word_count_c[1:0];
        end else if (response_delivery_candidate_c &&
                     (!taken_predict_fire_c || direct_response_c)) begin
            if (fetch_rsp_page_fault_i === 1'b1) begin
                perf_fetch_delivery_width_o = 2'd1;
            end else if (!fetch_rsp_error_i && !fetch_rsp_eof_i &&
                         !response_malformed_c) begin
                perf_fetch_delivery_width_o = cross_line_cached_pair_c ?
                    2'd2 : ({1'b0, fetch_rsp_valid_mask_i[0]} +
                            {1'b0, fetch_rsp_valid_mask_i[1]});
            end
        end
    end
    assign perf_frontend_residual_o = {
        perf_sequential_reason_c, perf_request_reason_c
    };
    assign perf_branch_window_full_pair_c =
        (perf_sequential_reason_c == PERF_SEQ_BRANCH_WINDOW) &&
        (target_line_word_count_c == 3'd2);
    assign perf_branch_window_supply_o[0] =
        perf_branch_window_full_pair_c;
    assign perf_branch_window_post_block_c = {
        perf_branch_window_full_pair_c && response_fire_c,
        perf_branch_window_full_pair_c && !target_line_capacity_c,
        perf_branch_window_full_pair_c && (fresh_reserved_words_c != 3'd0),
        perf_branch_window_full_pair_c && frontend_control_present_c
    };
    assign perf_branch_window_post_block_o =
        perf_branch_window_post_block_c;
    assign perf_branch_window_supply_o[1] =
        perf_branch_window_full_pair_c &&
        (perf_branch_window_post_block_c == 4'b0000);
    assign perf_reservation_o = {
        current_request_capacity_c,
        (fresh_reserved_words_c != 3'd0),
        request_fire_c,
        (response_fire_c && response_from_queue_c && response_stale_c),
        (response_fire_c && response_has_owner_c && !response_stale_c),
        response_fire_c,
        response_from_queue_c ? request_words_q[request_head_q] : 3'd0,
        request_head_q,
        reservation_head_same_line_c,
        reservation_head_exact_pc_c,
        reservation_head_current_c,
        response_from_queue_c,
        current_epoch_same_line_owner_count_c,
        current_epoch_exact_pc_owner_count_c,
        current_epoch_owner_count_c
    };
    assign response_credit_head_current_c = response_fire_c &&
        response_from_queue_c && reservation_head_current_c;
    assign response_credit_normal_c = response_credit_head_current_c &&
        !fetch_rsp_page_fault_i && !fetch_rsp_error_i && !fetch_rsp_eof_i &&
        !response_malformed_c;
    assign response_credit_direct_full_c = response_credit_normal_c &&
        direct_response_c && (direct_accept_mask_c != 2'b00) &&
        (direct_accept_mask_c == incoming_valid_mask_c) &&
        !cross_line_cached_pair_c;
    assign response_credit_direct_consumed_c = direct_response_c &&
        (direct_accept_mask_c != 2'b00) &&
        ((!fetch_rsp_page_fault_i && !fetch_rsp_error_i &&
          !fetch_rsp_eof_i && !response_malformed_c &&
          (direct_accept_mask_c == incoming_valid_mask_c) &&
          !cross_line_cached_pair_c) ||
         (fetch_rsp_page_fault_i && (direct_accept_mask_c == 2'b01)));
    assign response_credit_direct_partial_c = response_credit_normal_c &&
        direct_response_c && (direct_accept_mask_c != 2'b00) &&
        (direct_accept_mask_c != incoming_valid_mask_c);
    assign response_credit_buffered_c = response_credit_head_current_c &&
        (!fetch_rsp_error_i && !fetch_rsp_eof_i &&
         !response_malformed_c) && !response_credit_direct_consumed_c;
    assign response_credit_request_common_c = !reset &&
        !global_recover_i && !stop_i && !branch_recovery_pending_i &&
        !redirect_valid_i && !taken_predict_fire_c && !frontend_fault_q &&
        !frontend_eof_q && !target_line_eligible_hit_c &&
        !(cross_line_cached_pair_c && response_from_queue_c);
    assign response_credit_owner_blocked_c = request_count_q == 3'd4;
    assign response_credit_word_blocked_c = !request_capacity_c;
    assign response_credit_target_c = response_credit_normal_c &&
        response_credit_request_common_c &&
        (response_credit_owner_blocked_c ||
         response_credit_word_blocked_c);
    assign response_credit_head_words_c = response_from_queue_c ?
        request_words_q[request_head_q] : 3'd0;
    assign response_credit_capacity_after_release_c =
        (request_count_q != 3'd0) &&
        (reserved_words_q >= response_credit_head_words_c) &&
        ({1'b0, queue_count_after_pop_c} + {1'b0, reserved_words_q} -
         {1'b0, response_credit_head_words_c} +
         {1'b0, request_word_count_c} <= 4'd4);
    assign response_credit_structural_eligible_c =
        response_credit_target_c && response_credit_direct_full_c &&
        response_credit_capacity_after_release_c;
    assign response_credit_ready_eligible_c =
        response_credit_structural_eligible_c && fetch_req_ready_i;
    assign response_credit_state_error_c =
        (response_credit_target_c &&
         (!response_from_queue_c || !reservation_head_current_c)) ||
        (response_credit_direct_full_c &&
         (!response_credit_normal_c || cross_line_cached_pair_c)) ||
        (response_credit_structural_eligible_c &&
         (!response_credit_target_c ||
          !response_credit_capacity_after_release_c)) ||
        (response_credit_head_current_c &&
         (response_credit_head_words_c == 3'd0)) ||
        (response_credit_head_words_c > reserved_words_q);
    assign ordered_prefetch_future_addr_c =
        {next_pc_q[31:3], 3'b000} + 32'd8;
    assign ordered_prefetch_target_c =
        ORDERED_TARGET_PREFETCH_ORACLE_ENABLE &&
        sequential_line_candidate_c && !next_pc_q[2] &&
        (fresh_reserved_words_c != 3'd0);
    assign ordered_prefetch_lookup_c = ordered_prefetch_target_c &&
        !cross_line_direct_candidate_c;
    assign ordered_prefetch_future_hit_c = ordered_prefetch_lookup_c &&
        adjacent_line_lookup_hit_c;
    assign ordered_prefetch_recovery_drop_c = global_recover_i ||
        branch_recovery_pending_i || redirect_valid_i ||
        target_line_invalidate_i;
    assign ordered_prefetch_protocol_safe_c = ordered_prefetch_target_c &&
        !reset && !global_recover_i && !stop_i &&
        !branch_recovery_pending_i && !redirect_valid_i &&
        !target_line_invalidate_i && !taken_predict_fire_c &&
        !frontend_fault_q && !frontend_eof_q &&
        !branch_window_active_i && !frontend_control_present_c &&
        target_line_capacity_c && !cross_line_direct_candidate_c;
    assign ordered_prefetch_owner_capacity_c = request_count_q < 3'd4;
    assign ordered_prefetch_structural_eligible_c =
        ordered_prefetch_protocol_safe_c &&
        !ordered_prefetch_future_hit_c &&
        (current_epoch_future_line_owner_count_c == 3'd0) &&
        ordered_prefetch_owner_capacity_c;
    assign ordered_prefetch_ready_eligible_c =
        ordered_prefetch_structural_eligible_c && fetch_req_ready_i;
    always_comb begin
        ordered_prefetch_reason_c = ORDERED_PREFETCH_REASON_NONE;
        if (ordered_prefetch_target_c) begin
            if (reset || global_recover_i || stop_i ||
                branch_recovery_pending_i || redirect_valid_i ||
                target_line_invalidate_i || taken_predict_fire_c ||
                frontend_fault_q || frontend_eof_q) begin
                ordered_prefetch_reason_c =
                    ORDERED_PREFETCH_REASON_RECOVERY;
            end else if (branch_window_active_i) begin
                ordered_prefetch_reason_c =
                    ORDERED_PREFETCH_REASON_BRANCH_WINDOW;
            end else if (frontend_control_present_c) begin
                ordered_prefetch_reason_c =
                    ORDERED_PREFETCH_REASON_CONTROL;
            end else if (!target_line_capacity_c) begin
                ordered_prefetch_reason_c =
                    ORDERED_PREFETCH_REASON_QUEUE_CAPACITY;
            end else if (cross_line_direct_candidate_c) begin
                ordered_prefetch_reason_c =
                    ORDERED_PREFETCH_REASON_LOOKUP_CONFLICT;
            end else if (ordered_prefetch_future_hit_c) begin
                ordered_prefetch_reason_c =
                    ORDERED_PREFETCH_REASON_FUTURE_CACHED;
            end else if (current_epoch_future_line_owner_count_c != 3'd0) begin
                ordered_prefetch_reason_c =
                    ORDERED_PREFETCH_REASON_FUTURE_DUPLICATE;
            end else if (!ordered_prefetch_owner_capacity_c) begin
                ordered_prefetch_reason_c =
                    ORDERED_PREFETCH_REASON_OWNER_CAPACITY;
            end else if (!fetch_req_ready_i) begin
                ordered_prefetch_reason_c =
                    ORDERED_PREFETCH_REASON_DOWNSTREAM;
            end else if (ordered_prefetch_ready_eligible_c) begin
                ordered_prefetch_reason_c =
                    ORDERED_PREFETCH_REASON_ELIGIBLE;
            end else begin
                ordered_prefetch_reason_c = ORDERED_PREFETCH_REASON_OTHER;
            end
        end
    end
    assign ordered_prefetch_state_error_c =
        ORDERED_TARGET_PREFETCH_ORACLE_ENABLE && (
        (ordered_prefetch_target_c &&
         (next_pc_q[2] || !target_line_lookup_hit_c ||
          target_line_lookup_pending_q ||
          (fresh_reserved_words_c == 3'd0))) ||
        (ordered_prefetch_structural_eligible_c &&
         ((ordered_prefetch_reason_c !=
           ORDERED_PREFETCH_REASON_ELIGIBLE) &&
          (ordered_prefetch_reason_c !=
           ORDERED_PREFETCH_REASON_DOWNSTREAM))) ||
        (ordered_prefetch_ready_eligible_c !=
         (ordered_prefetch_reason_c ==
          ORDERED_PREFETCH_REASON_ELIGIBLE)) ||
        (ordered_prefetch_lookup_c && cross_line_direct_candidate_c) ||
        (current_epoch_future_line_owner_count_c > request_count_q));
    assign demand_fetch_state_error_c =
        DEMAND_FETCH_LATENCY_ORACLE_ENABLE && (
        ORDERED_TARGET_PREFETCH_ORACLE_ENABLE ||
        (request_count_q > 3'd4) ||
        (response_credit_head_current_c && response_stale_c) ||
        (response_delivery_candidate_c &&
         (!response_fire_c || !response_has_owner_c || response_stale_c)));
    always_comb begin
        perf_fetch_response_credit_o = 64'b0;
        perf_fetch_response_credit_o[0] = 1'b1;
        perf_fetch_response_credit_o[1] = response_fire_c;
        perf_fetch_response_credit_o[2] = response_from_queue_c;
        perf_fetch_response_credit_o[3] = response_credit_head_current_c;
        perf_fetch_response_credit_o[4] = response_fire_c &&
            response_from_queue_c && response_stale_c;
        perf_fetch_response_credit_o[5] = response_fire_c &&
            response_has_owner_c;
        perf_fetch_response_credit_o[6] = response_credit_normal_c;
        perf_fetch_response_credit_o[7] = response_fire_c &&
            fetch_rsp_page_fault_i;
        perf_fetch_response_credit_o[8] = response_fire_c &&
            fetch_rsp_error_i;
        perf_fetch_response_credit_o[9] = response_fire_c && fetch_rsp_eof_i;
        perf_fetch_response_credit_o[10] = response_fire_c &&
            response_malformed_c;
        perf_fetch_response_credit_o[11] = direct_response_c;
        perf_fetch_response_credit_o[13:12] = direct_accept_mask_c;
        perf_fetch_response_credit_o[15:14] = incoming_valid_mask_c;
        perf_fetch_response_credit_o[16] = response_credit_direct_full_c;
        perf_fetch_response_credit_o[17] = response_credit_direct_partial_c;
        perf_fetch_response_credit_o[18] = response_credit_buffered_c;
        perf_fetch_response_credit_o[19] = cross_line_cached_pair_c;
        perf_fetch_response_credit_o[20] = taken_predict_fire_c;
        perf_fetch_response_credit_o[21] =
            response_credit_request_common_c;
        perf_fetch_response_credit_o[22] =
            response_credit_owner_blocked_c;
        perf_fetch_response_credit_o[23] =
            response_credit_word_blocked_c;
        perf_fetch_response_credit_o[24] =
            response_credit_capacity_after_release_c;
        perf_fetch_response_credit_o[25] =
            response_credit_structural_eligible_c;
        perf_fetch_response_credit_o[26] = fetch_req_ready_i;
        perf_fetch_response_credit_o[27] =
            response_credit_ready_eligible_c;
        perf_fetch_response_credit_o[28] = request_fire_c;
        perf_fetch_response_credit_o[31:29] =
            response_credit_head_words_c;
        perf_fetch_response_credit_o[34:32] = reserved_words_q;
        perf_fetch_response_credit_o[37:35] = queue_count_after_pop_c;
        perf_fetch_response_credit_o[40:38] = request_word_count_c;
        perf_fetch_response_credit_o[43:41] = request_count_q;
        perf_fetch_response_credit_o[44] = response_credit_target_c;
        perf_fetch_response_credit_o[45] = response_credit_state_error_c;
        perf_fetch_response_credit_o[46] = response_credit_normal_c &&
            direct_response_c && (direct_accept_mask_c == 2'b00);
        perf_fetch_response_credit_o[47] = response_fire_c &&
            (!response_has_owner_c || response_stale_c ||
             fetch_rsp_error_i || fetch_rsp_eof_i ||
             response_malformed_c);
        perf_fetch_response_credit_o[48] = branch_window_active_i;
        perf_fetch_response_credit_o[49] =
            branch_window_line_delivery_safe_i;
        if (ORDERED_TARGET_PREFETCH_ORACLE_ENABLE) begin
            perf_fetch_response_credit_o[50] = 1'b1;
            perf_fetch_response_credit_o[51] =
                ordered_prefetch_target_c;
            perf_fetch_response_credit_o[52] =
                ordered_prefetch_structural_eligible_c;
            perf_fetch_response_credit_o[53] =
                ordered_prefetch_ready_eligible_c;
            perf_fetch_response_credit_o[57:54] =
                ordered_prefetch_reason_c;
            perf_fetch_response_credit_o[58] = target_line_inject_c;
            perf_fetch_response_credit_o[59] =
                ordered_prefetch_recovery_drop_c;
            perf_fetch_response_credit_o[62:60] = request_count_q;
            perf_fetch_response_credit_o[63] =
                ordered_prefetch_state_error_c;
        end else if (DEMAND_FETCH_LATENCY_ORACLE_ENABLE) begin
            perf_fetch_response_credit_o[50] = 1'b1;
            perf_fetch_response_credit_o[51] =
                target_line_lookup_pending_q;
            perf_fetch_response_credit_o[52] = target_line_lookup_hit_c;
            perf_fetch_response_credit_o[53] = target_line_inject_c;
            perf_fetch_response_credit_o[54] = global_recover_i ||
                branch_recovery_pending_i || redirect_valid_i ||
                taken_predict_fire_c;
            perf_fetch_response_credit_o[55] = stop_i ||
                frontend_fault_q || frontend_eof_q;
            perf_fetch_response_credit_o[56] =
                response_delivery_candidate_c;
            perf_fetch_response_credit_o[57] = frontend_control_present_c;
            perf_fetch_response_credit_o[58] = target_line_eligible_hit_c;
            perf_fetch_response_credit_o[59] = same_cycle_response_c;
            perf_fetch_response_credit_o[60] = request_capacity_c;
            perf_fetch_response_credit_o[61] =
                current_request_capacity_c;
            perf_fetch_response_credit_o[62] = demand_fetch_state_error_c;
            perf_fetch_response_credit_o[63] =
                target_line_lookup_entry_valid_c;
        end
    end
    assign perf_demand_fetch_identity_o =
        DEMAND_FETCH_LATENCY_ORACLE_ENABLE ?
        {response_pc_c, next_pc_q} : 64'b0;
    assign coalesce_singleton_c = SINGLETON_COALESCE_ORACLE_ENABLE &&
        (queue_count_q == 3'd1) && queue_valid_c[0];
    assign coalesce_target_line_c = coalesce_singleton_c &&
        target_line_inject_c;
    assign coalesce_response_c = coalesce_singleton_c &&
        response_delivery_candidate_c && !taken_predict_fire_c;
    always_comb begin
        coalesce_incoming_mask_c = 2'b00;
        coalesce_incoming_pc_c = 32'b0;
        coalesce_incoming_instr_c = 32'b0;
        coalesce_incoming_exception_c = 1'b0;
        if (coalesce_target_line_c) begin
            coalesce_incoming_mask_c = next_pc_q[2] ? 2'b01 : 2'b11;
            coalesce_incoming_pc_c = next_pc_q;
            coalesce_incoming_instr_c = next_pc_q[2] ?
                target_line_lookup_data_c[63:32] :
                target_line_lookup_data_c[31:0];
        end else if (coalesce_response_c) begin
            coalesce_incoming_mask_c = fetch_rsp_page_fault_i ?
                2'b01 : fetch_rsp_valid_mask_i;
            coalesce_incoming_pc_c = response_pc_c;
            coalesce_incoming_instr_c = response_pc_c[2] ?
                fetch_rsp_data_i[63:32] : fetch_rsp_data_i[31:0];
            coalesce_incoming_exception_c = fetch_rsp_page_fault_i;
        end
    end
    assign coalesce_contiguous_c =
        (coalesce_incoming_mask_c != 2'b00) &&
        (queue_pc0_c + 32'd4 == coalesce_incoming_pc_c);
    assign coalesce_current_control_c = queue_valid_c[0] &&
        !queue_exception0_c && decode0_supported &&
        (decoded_uop0_c.fu_type == BBUS_OOO_FU_BRU);
    assign coalesce_recovery_terminal_c = reset || global_recover_i || stop_i ||
        branch_recovery_pending_i || redirect_valid_i || frontend_fault_q ||
        frontend_eof_q;
    assign coalesce_admission_block_c =
        (fresh_reserved_words_c != 3'd0) ||
        (!target_line_capacity_c && target_line_lookup_hit_c);
    assign coalesce_base_eligible_c = coalesce_singleton_c &&
        (coalesce_target_line_c || coalesce_response_c) &&
        coalesce_contiguous_c && output_enable_c &&
        !cross_line_roll_candidate_c &&
        !coalesce_current_control_c && !queue_exception0_c &&
        !oldest_unsupported_c && !coalesce_incoming_exception_c &&
        coalesce_incoming_supported_c &&
        !coalesce_incoming_unsupported_c;
    assign coalesce_eligible_c = coalesce_base_eligible_c &&
        (decode_ready_mask_i == 2'b11);
    assign coalesce_opportunity_c = coalesce_eligible_c &&
        decode_pop_mask_c[0];
    assign coalesce_state_error_c = SINGLETON_COALESCE_ORACLE_ENABLE && (
        (coalesce_target_line_c && coalesce_response_c) ||
        ((coalesce_incoming_mask_c != 2'b00) &&
         (coalesce_incoming_mask_c != 2'b01) &&
         (coalesce_incoming_mask_c != 2'b11)) ||
        (coalesce_opportunity_c &&
         (!coalesce_eligible_c || !decode_pop_mask_c[0])) ||
        (coalesce_eligible_c &&
         (!coalesce_base_eligible_c ||
          (decode_ready_mask_i != 2'b11))));
    // Bit 26 is the deduplicated incremental-slot opportunity consumed by
    // the P30 accounting sampler. The remaining bits retain the blockers that
    // were evaluated before that decision.
    always_comb begin
        perf_singleton_coalesce_o = 32'b0;
        if (SINGLETON_COALESCE_ORACLE_ENABLE) begin
            perf_singleton_coalesce_o[0] = 1'b1;
            perf_singleton_coalesce_o[1] = coalesce_singleton_c;
            perf_singleton_coalesce_o[4:2] =
                queue_singleton_origin_q[queue_head_q];
            perf_singleton_coalesce_o[5] = coalesce_target_line_c;
            perf_singleton_coalesce_o[6] = coalesce_response_c;
            perf_singleton_coalesce_o[8:7] = coalesce_incoming_mask_c;
            perf_singleton_coalesce_o[9] = coalesce_contiguous_c;
            perf_singleton_coalesce_o[10] = coalesce_current_control_c;
            perf_singleton_coalesce_o[11] = queue_exception0_c;
            perf_singleton_coalesce_o[12] = oldest_unsupported_c;
            perf_singleton_coalesce_o[13] =
                coalesce_incoming_exception_c;
            perf_singleton_coalesce_o[14] =
                coalesce_incoming_unsupported_c;
            perf_singleton_coalesce_o[16:15] = decode_ready_mask_i;
            perf_singleton_coalesce_o[18:17] = decode_accept_mask_i;
            perf_singleton_coalesce_o[19] = output_enable_c;
            perf_singleton_coalesce_o[20] =
                coalesce_recovery_terminal_c;
            perf_singleton_coalesce_o[21] = coalesce_admission_block_c;
            perf_singleton_coalesce_o[22] = response_fire_c;
            perf_singleton_coalesce_o[23] =
                coalesce_incoming_mask_c != 2'b00;
            perf_singleton_coalesce_o[24] = coalesce_base_eligible_c;
            perf_singleton_coalesce_o[25] = coalesce_eligible_c;
            perf_singleton_coalesce_o[26] = coalesce_opportunity_c;
            perf_singleton_coalesce_o[27] =
                queue_singleton_origin_q[queue_head_q] !=
                SINGLETON_ORIGIN_OTHER;
            perf_singleton_coalesce_o[28] = decode_valid_mask_o[0];
            perf_singleton_coalesce_o[31] = coalesce_state_error_c;
        end
    end
    assign perf_singleton_target_pc_o = coalesce_opportunity_c ?
        coalesce_incoming_pc_c : 32'b0;
    assign perf_singleton_target_instr_o = coalesce_opportunity_c ?
        coalesce_incoming_instr_c : 32'b0;
    assign partial_current_control_c = decode_source_valid_c[0] &&
        !decode_source_exception0_c && decode0_supported &&
        (decoded_uop0_c.fu_type == BBUS_OOO_FU_BRU);
    assign partial_younger_control_c = decode_source_valid_c[1] &&
        !decode_source_exception1_c && decode1_supported &&
        (decoded_uop1_c.fu_type == BBUS_OOO_FU_BRU);
    assign partial_pair_state_error_c = PARTIAL_PAIR_ORACLE_ENABLE && (
        (direct_target_line_c && direct_response_c) ||
        (direct_delivery_c && (queue_count_q != 3'd0)) ||
        (decode_source_valid_c != prefix_mask(decode_source_valid_c)) ||
        (decode_valid_mask_o != prefix_mask(decode_valid_mask_o)) ||
        (decode_ready_mask_i != prefix_mask(decode_ready_mask_i)) ||
        (decode_accept_mask_i != prefix_mask(decode_accept_mask_i)) ||
        ((decode_accept_mask_i & ~decode_valid_mask_o) != 2'b00));
    // P10 owns the authoritative partial_pair slot decision. This P31 bus
    // only exports the frontend state needed to explain those slots.
    always_comb begin
        perf_partial_pair_o = 32'b0;
        if (PARTIAL_PAIR_ORACLE_ENABLE) begin
            perf_partial_pair_o[0] = 1'b1;
            perf_partial_pair_o[1] = direct_delivery_c;
            perf_partial_pair_o[4:2] = queue_count_q;
            perf_partial_pair_o[6:5] = queue_valid_c;
            perf_partial_pair_o[8:7] = decode_source_valid_c;
            perf_partial_pair_o[10:9] = decode_valid_mask_o;
            perf_partial_pair_o[12:11] = decode_ready_mask_i;
            perf_partial_pair_o[14:13] = decode_accept_mask_i;
            perf_partial_pair_o[15] = partial_current_control_c;
            perf_partial_pair_o[16] = decode_source_exception0_c;
            perf_partial_pair_o[17] = oldest_unsupported_c;
            perf_partial_pair_o[18] = partial_younger_control_c;
            perf_partial_pair_o[19] = decode_source_exception1_c;
            perf_partial_pair_o[20] = younger_unsupported_c;
            perf_partial_pair_o[21] = output_enable_c;
            perf_partial_pair_o[22] = direct_target_line_c;
            perf_partial_pair_o[23] = direct_response_c;
            perf_partial_pair_o[24] = decode_source_pc0_c[2];
            perf_partial_pair_o[25] = decode_pop_mask_c[0];
            perf_partial_pair_o[26] = decode_pop_mask_c[1];
            perf_partial_pair_o[27] = target_line_inject_c;
            perf_partial_pair_o[28] = response_delivery_candidate_c;
            perf_partial_pair_o[29] = fresh_reserved_words_c != 3'd0;
            perf_partial_pair_o[30] = frontend_control_present_c;
            perf_partial_pair_o[31] = partial_pair_state_error_c;
        end
    end
    assign perf_partial_pair_pc_o =
        (PARTIAL_PAIR_ORACLE_ENABLE && decode_source_valid_c[0]) ?
        decode_source_pc0_c : 32'b0;
    assign perf_partial_pair_instr_o =
        (PARTIAL_PAIR_ORACLE_ENABLE && decode_source_valid_c[0]) ?
        decode_source_instr0_c : 32'b0;
    assign cross_line_residual_capture_c = cross_line_cached_pair_c &&
        (direct_accept_mask_c == 2'b01) && !taken_predict_fire_c;
    assign cross_line_queue_capture_c = cross_line_cached_pair_c &&
        (direct_accept_mask_c == 2'b00) && !taken_predict_fire_c;
    assign cross_line_state_error_c = CACHED_CROSS_LINE_PAIR_ENABLE && (
        (cross_line_cached_pair_c &&
         (!cross_line_direct_candidate_c || !adjacent_line_lookup_hit_c ||
          !cross_line_owner_safe_c || (incoming_valid_mask_c != 2'b11))) ||
        (cross_line_residual_capture_c && !cross_line_cached_pair_c) ||
        (cross_line_queue_capture_c && !cross_line_cached_pair_c) ||
        (cross_line_direct_candidate_c && !cross_line_current_pc_c[2]));
    always_comb begin
        perf_cross_line_pair_o = 16'b0;
        if (CACHED_CROSS_LINE_PAIR_ENABLE) begin
            perf_cross_line_pair_o[0] = 1'b1;
            perf_cross_line_pair_o[1] = cross_line_direct_candidate_c;
            perf_cross_line_pair_o[2] = adjacent_line_lookup_hit_c;
            perf_cross_line_pair_o[3] = cross_line_owner_safe_c;
            perf_cross_line_pair_o[4] = cross_line_cached_pair_c;
            perf_cross_line_pair_o[5] = direct_target_line_c;
            perf_cross_line_pair_o[6] = direct_response_c;
            perf_cross_line_pair_o[8:7] = direct_accept_mask_c;
            perf_cross_line_pair_o[9] = cross_line_residual_capture_c;
            perf_cross_line_pair_o[10] = cross_line_cached_pair_c &&
                (direct_accept_mask_c == 2'b11);
            perf_cross_line_pair_o[11] = cross_line_queue_capture_c;
            perf_cross_line_pair_o[12] =
                adjacent_line_lookup_entry_valid_c;
            perf_cross_line_pair_o[13] =
                cross_line_direct_candidate_c && !cross_line_owner_safe_c;
            perf_cross_line_pair_o[14] = cross_line_cached_pair_c &&
                (direct_accept_mask_c == 2'b01) && taken_predict_fire_c;
            perf_cross_line_pair_o[15] = cross_line_state_error_c;
        end
    end
    assign cross_line_carry_state_error_c =
        CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE && (
        CACHED_CROSS_LINE_PAIR_ENABLE ||
        (cross_line_initial_carry_c &&
         (!cross_line_cached_pair_c || (incoming_valid_mask_c != 2'b11))) ||
        (cross_line_roll_candidate_c &&
         (!cross_line_carry_head_c || !target_line_lookup_hit_c ||
          next_pc_q[2])) ||
        (cross_line_roll_fire_c &&
         ((cross_line_roll_accept_mask_c != 2'b01) &&
          (cross_line_roll_accept_mask_c != 2'b11))) ||
        (cross_line_roll_fire_c && !target_line_inject_c) ||
        (cross_line_initial_carry_c && cross_line_roll_candidate_c));
    always_comb begin
        perf_cross_line_carry_o = 32'b0;
        if (CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE) begin
            perf_cross_line_carry_o[0] = 1'b1;
            perf_cross_line_carry_o[1] = cross_line_direct_candidate_c;
            perf_cross_line_carry_o[2] = adjacent_line_lookup_hit_c;
            perf_cross_line_carry_o[3] = cross_line_owner_safe_c;
            perf_cross_line_carry_o[4] = cross_line_initial_carry_c;
            perf_cross_line_carry_o[6:5] = direct_accept_mask_c;
            perf_cross_line_carry_o[8:7] =
                cross_line_initial_buffer_count_c;
            perf_cross_line_carry_o[9] = cross_line_carry_head_c;
            perf_cross_line_carry_o[10] = cross_line_roll_candidate_c;
            perf_cross_line_carry_o[12:11] =
                cross_line_roll_accept_mask_c;
            perf_cross_line_carry_o[13] = cross_line_roll_fire_c;
            perf_cross_line_carry_o[15:14] =
                cross_line_roll_buffer_count_c;
            perf_cross_line_carry_o[18:16] = queue_count_q;
            perf_cross_line_carry_o[19] = target_line_lookup_hit_c;
            perf_cross_line_carry_o[20] = target_line_inject_c;
            perf_cross_line_carry_o[21] = taken_predict_fire_c;
            perf_cross_line_carry_o[22] = direct_target_line_c;
            perf_cross_line_carry_o[23] = direct_response_c;
            perf_cross_line_carry_o[24] =
                adjacent_line_lookup_entry_valid_c;
            perf_cross_line_carry_o[25] = cross_line_carry_head_c &&
                !cross_line_roll_candidate_c;
            perf_cross_line_carry_o[26] = cross_line_roll_fire_c &&
                (cross_line_roll_accept_mask_c == 2'b01);
            perf_cross_line_carry_o[27] = cross_line_roll_fire_c &&
                (cross_line_roll_accept_mask_c == 2'b11);
            perf_cross_line_carry_o[28] = cross_line_initial_carry_c &&
                !taken_predict_fire_c;
            perf_cross_line_carry_o[29] = cross_line_roll_fire_c &&
                !taken_predict_fire_c;
            perf_cross_line_carry_o[30] =
                CACHED_CROSS_LINE_PAIR_ENABLE;
            perf_cross_line_carry_o[31] = cross_line_carry_state_error_c;
        end
    end
    always_comb begin
        perf_frontend_no_candidate_o = 2'd0;
        if (!target_line_lookup_hit_c) begin
            if (!TARGET_LINE_HIT_ENABLE) begin
                perf_frontend_no_candidate_o = 2'd3;
            end else if (target_line_lookup_entry_valid_c) begin
                perf_frontend_no_candidate_o = 2'd2;
            end else begin
                perf_frontend_no_candidate_o = 2'd1;
            end
        end
    end
    assign conservation_error_o = illegal_decode_accept_q ||
        cross_line_state_error_c ||
        cross_line_carry_state_error_c ||
        (queue_count_q > 3'd4) ||
        (request_count_q > 3'd4) ||
        (reserved_words_q > 3'd4) ||
        (queue_count_q + fresh_reserved_words_c > 3'd4) ||
        ((queue_count_q >= 3'd1) && !queue_epoch_valid_c[0]) ||
        ((queue_count_q >= 3'd2) && !queue_epoch_valid_c[1]) ||
        ((request_count_q != 3'd0) &&
         (request_addr_q[request_head_q][2:0] != 3'b000)) ||
        (direct_target_line_c && direct_response_c) ||
        (direct_delivery_c && (queue_count_q != 3'd0)) ||
        (direct_delivery_c &&
         (incoming_valid_mask_c != 2'b01) &&
         (incoming_valid_mask_c != 2'b11)) ||
        ((direct_accept_mask_c & ~incoming_valid_mask_c) != 2'b00) ||
        (!direct_delivery_c && (direct_accept_mask_c != 2'b00));

    ooo_ifetch_target_line_4entry #(
        .ENABLE(TARGET_LINE_HIT_ENABLE),
        .SECOND_LOOKUP_ENABLE(
            CACHED_CROSS_LINE_PAIR_ENABLE ||
            CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE ||
            ORDERED_TARGET_PREFETCH_ORACLE_ENABLE),
        .ENTRY_COUNT(TARGET_LINE_ENTRY_COUNT),
        .WAY_COUNT(TARGET_LINE_WAY_COUNT)
    ) u_target_line (
        .clk(clk),
        .reset(reset),
        .invalidate_i(target_line_invalidate_i),
        .lookup_valid_i(!reset && !frontend_fault_q && !frontend_eof_q),
        .lookup_addr_i({next_pc_q[31:3], 3'b000}),
        .lookup_hit_o(target_line_lookup_hit_c),
        .lookup_entry_valid_o(target_line_lookup_entry_valid_c),
        .lookup_data_o(target_line_lookup_data_c),
        .lookup1_valid_i(
            cross_line_direct_candidate_c || ordered_prefetch_lookup_c),
        .lookup1_addr_i(cross_line_direct_candidate_c ?
            {cross_line_next_pc_c[31:3], 3'b000} :
            ordered_prefetch_future_addr_c),
        .lookup1_hit_o(adjacent_line_lookup_hit_c),
        .lookup1_entry_valid_o(adjacent_line_lookup_entry_valid_c),
        .lookup1_data_o(adjacent_line_lookup_data_c),
        .fill_valid_i(target_line_fill_c),
        .fill_addr_i(response_addr_c),
        .fill_data_i(fetch_rsp_data_i)
    );

    integer queue_i;
    always_ff @(posedge clk) begin
        if (reset) begin
            next_pc_q <= RESET_VECTOR;
            frontend_epoch_q <= '0;
            predictor_history_q <= '0;
            invalidation_active_q <= 1'b0;
            target_line_lookup_pending_q <= 1'b0;
            request_head_q <= '0;
            request_tail_q <= '0;
            request_count_q <= '0;
            reserved_words_q <= '0;
            queue_head_q <= '0;
            queue_count_q <= '0;
            for (queue_i = 0; queue_i < 4; queue_i = queue_i + 1) begin
                queue_pc_q[queue_i] <= '0;
                queue_instr_q[queue_i] <= '0;
                queue_exception_q[queue_i] <= 1'b0;
                queue_branch_window_line_q[queue_i] <= 1'b0;
                queue_branch_window_line_word1_q[queue_i] <= 1'b0;
                queue_singleton_origin_q[queue_i] <=
                    SINGLETON_ORIGIN_OTHER;
                queue_epoch_q[queue_i] <= '0;
                request_pc_q[queue_i] <= '0;
                request_addr_q[queue_i] <= '0;
                request_epoch_q[queue_i] <= '0;
                request_words_q[queue_i] <= '0;
            end
            frontend_fault_q <= 1'b0;
            frontend_fault_pc_q <= '0;
            frontend_eof_q <= 1'b0;
            malformed_response_q <= 1'b0;
            unsupported_seen_q <= 1'b0;
            illegal_decode_accept_q <= 1'b0;
            stale_response_drop_q <= 1'b0;
        end else begin
            if (!CORRELATED_PREDICTOR_ENABLE || global_recover_i) begin
                predictor_history_q <= '0;
            end else if (predictor_history_recover_valid_i) begin
                predictor_history_q <= predictor_history_recover_conditional_i ?
                    history_push(
                        predictor_history_recover_snapshot_i,
                        predictor_history_recover_taken_i
                    ) : predictor_history_recover_snapshot_i;
            end else if (redirect_fire_c &&
                         (redirect_i.reason == BBUS_OOO_REDIRECT_EXCEPTION)) begin
                predictor_history_q <= '0;
            end else begin
                predictor_history_q <= predictor_history_after_accept_c;
            end
            stale_response_drop_q <= 1'b0;
            invalidation_active_q <= invalidation_level_c;
            if (global_recover_i || stop_i) begin
                target_line_lookup_pending_q <= 1'b0;
            end else if (redirect_fire_c || safe_taken_predict_fire_c) begin
                target_line_lookup_pending_q <= 1'b1;
            end else if (target_line_inject_c || request_fire_c) begin
                target_line_lookup_pending_q <= 1'b0;
            end
            if (!legal_decode_accept_c) begin
                illegal_decode_accept_q <= 1'b1;
            end

            if (global_recover_i || stop_i || redirect_fire_c ||
                branch_recovery_pending_i || taken_predict_fire_c) begin
                if (redirect_fire_c || taken_predict_fire_c ||
                    !invalidation_active_q) begin
                    frontend_epoch_q <= frontend_epoch_q + 8'd1;
                end
                queue_head_q <= '0;
                queue_count_q <= '0;
                if (global_recover_i) begin
                    next_pc_q <= RESET_VECTOR;
                    frontend_fault_q <= 1'b0;
                    frontend_fault_pc_q <= '0;
                    malformed_response_q <= 1'b0;
                    unsupported_seen_q <= 1'b0;
                end else if (redirect_fire_c) begin
                    next_pc_q <= redirect_i.target;
                end else if (taken_predict_fire_c) begin
                    next_pc_q <= taken_predict_target_c;
                end else if (branch_recovery_pending_i &&
                             response_from_queue_c) begin
                    next_pc_q <= request_pc_q[request_head_q];
                end
                if (global_recover_i || redirect_fire_c || taken_predict_fire_c ||
                    branch_recovery_pending_i) begin
                    frontend_eof_q <= 1'b0;
                end
                if (response_from_queue_c && response_fire_c) begin
                    request_head_q <= request_head_q + 2'd1;
                    request_count_q <= request_count_q - 3'd1;
                    reserved_words_q <= reserved_words_q -
                        request_words_q[request_head_q];
                    stale_response_drop_q <= 1'b1;
                end
            end else begin
                if (decode_pop_count_c != 2'd0) begin
                    queue_head_q <= queue_head_q + decode_pop_count_c;
                    queue_count_q <= queue_count_after_pop_c;
                end

                if (target_line_inject_c) begin
                    if (cross_line_roll_fire_c) begin
                        if (cross_line_roll_accept_mask_c == 2'b01) begin
                            queue_pc_q[queue_tail_idx_c] <= next_pc_q;
                            queue_instr_q[queue_tail_idx_c] <=
                                target_line_lookup_data_c[31:0];
                            queue_exception_q[queue_tail_idx_c] <= 1'b0;
                            queue_branch_window_line_q[queue_tail_idx_c] <=
                                target_line_branch_window_inject_c;
                            queue_branch_window_line_word1_q[
                                queue_tail_idx_c] <= 1'b0;
                            queue_epoch_q[queue_tail_idx_c] <=
                                frontend_epoch_q;
                            queue_singleton_origin_q[queue_tail_idx_c] <=
                                SINGLETON_ORIGIN_OTHER;
                            queue_pc_q[queue_tail_idx_c + 2'd1] <=
                                next_pc_q + 32'd4;
                            queue_instr_q[queue_tail_idx_c + 2'd1] <=
                                target_line_lookup_data_c[63:32];
                            queue_exception_q[
                                queue_tail_idx_c + 2'd1] <= 1'b0;
                            queue_branch_window_line_q[
                                queue_tail_idx_c + 2'd1] <=
                                target_line_branch_window_inject_c;
                            queue_branch_window_line_word1_q[
                                queue_tail_idx_c + 2'd1] <=
                                target_line_branch_window_inject_c;
                            queue_epoch_q[queue_tail_idx_c + 2'd1] <=
                                frontend_epoch_q;
                            queue_singleton_origin_q[
                                queue_tail_idx_c + 2'd1] <=
                                SINGLETON_ORIGIN_CROSS_LINE_CARRY;
                            queue_count_q <= queue_count_after_pop_c + 3'd2;
                        end else begin
                            queue_pc_q[queue_tail_idx_c] <=
                                next_pc_q + 32'd4;
                            queue_instr_q[queue_tail_idx_c] <=
                                target_line_lookup_data_c[63:32];
                            queue_exception_q[queue_tail_idx_c] <= 1'b0;
                            queue_branch_window_line_q[queue_tail_idx_c] <=
                                target_line_branch_window_inject_c;
                            queue_branch_window_line_word1_q[
                                queue_tail_idx_c] <=
                                target_line_branch_window_inject_c;
                            queue_epoch_q[queue_tail_idx_c] <=
                                frontend_epoch_q;
                            queue_singleton_origin_q[queue_tail_idx_c] <=
                                SINGLETON_ORIGIN_CROSS_LINE_CARRY;
                            queue_count_q <= queue_count_after_pop_c + 3'd1;
                        end
                    end else if (direct_target_line_c &&
                        (direct_accept_mask_c != 2'b00)) begin
                        if (cross_line_initial_carry_c) begin
                            if (direct_accept_mask_c == 2'b01) begin
                                queue_pc_q[queue_tail_idx_c] <= incoming_pc1_c;
                                queue_instr_q[queue_tail_idx_c] <=
                                    incoming_instr1_c;
                                queue_exception_q[queue_tail_idx_c] <= 1'b0;
                                queue_branch_window_line_q[
                                    queue_tail_idx_c] <=
                                    incoming_branch_window_line_c;
                                queue_branch_window_line_word1_q[
                                    queue_tail_idx_c] <=
                                    incoming_branch_window_line_c;
                                queue_epoch_q[queue_tail_idx_c] <=
                                    frontend_epoch_q;
                                queue_singleton_origin_q[
                                    queue_tail_idx_c] <=
                                    SINGLETON_ORIGIN_DIRECT_RESIDUAL;
                                queue_pc_q[queue_tail_idx_c + 2'd1] <=
                                    cross_line_carry_pc_c;
                                queue_instr_q[queue_tail_idx_c + 2'd1] <=
                                    cross_line_carry_instr_c;
                                queue_exception_q[
                                    queue_tail_idx_c + 2'd1] <= 1'b0;
                                queue_branch_window_line_q[
                                    queue_tail_idx_c + 2'd1] <=
                                    incoming_branch_window_line_c;
                                queue_branch_window_line_word1_q[
                                    queue_tail_idx_c + 2'd1] <=
                                    incoming_branch_window_line_c;
                                queue_epoch_q[queue_tail_idx_c + 2'd1] <=
                                    frontend_epoch_q;
                                queue_singleton_origin_q[
                                    queue_tail_idx_c + 2'd1] <=
                                    SINGLETON_ORIGIN_CROSS_LINE_CARRY;
                                queue_count_q <=
                                    queue_count_after_pop_c + 3'd2;
                            end else begin
                                queue_pc_q[queue_tail_idx_c] <=
                                    cross_line_carry_pc_c;
                                queue_instr_q[queue_tail_idx_c] <=
                                    cross_line_carry_instr_c;
                                queue_exception_q[queue_tail_idx_c] <= 1'b0;
                                queue_branch_window_line_q[
                                    queue_tail_idx_c] <=
                                    incoming_branch_window_line_c;
                                queue_branch_window_line_word1_q[
                                    queue_tail_idx_c] <=
                                    incoming_branch_window_line_c;
                                queue_epoch_q[queue_tail_idx_c] <=
                                    frontend_epoch_q;
                                queue_singleton_origin_q[
                                    queue_tail_idx_c] <=
                                    SINGLETON_ORIGIN_CROSS_LINE_CARRY;
                                queue_count_q <=
                                    queue_count_after_pop_c + 3'd1;
                            end
                        end else if ((incoming_valid_mask_c == 2'b11) &&
                            (direct_accept_mask_c == 2'b01)) begin
                            queue_pc_q[queue_tail_idx_c] <= incoming_pc1_c;
                            queue_instr_q[queue_tail_idx_c] <=
                                incoming_instr1_c;
                            queue_exception_q[queue_tail_idx_c] <= 1'b0;
                            queue_branch_window_line_q[queue_tail_idx_c] <=
                                incoming_branch_window_line_c;
                            queue_branch_window_line_word1_q[
                                queue_tail_idx_c] <=
                                incoming_branch_window_line_c;
                            queue_epoch_q[queue_tail_idx_c] <=
                                frontend_epoch_q;
                            queue_singleton_origin_q[queue_tail_idx_c] <=
                                SINGLETON_ORIGIN_DIRECT_RESIDUAL;
                            queue_count_q <= queue_count_after_pop_c + 3'd1;
                        end else begin
                            queue_count_q <= queue_count_after_pop_c;
                        end
                    end else begin
                        queue_pc_q[queue_tail_idx_c] <= next_pc_q;
                        queue_instr_q[queue_tail_idx_c] <= next_pc_q[2] ?
                            target_line_lookup_data_c[63:32] :
                            target_line_lookup_data_c[31:0];
                        queue_exception_q[queue_tail_idx_c] <= 1'b0;
                        queue_branch_window_line_q[queue_tail_idx_c] <=
                            target_line_branch_window_inject_c;
                        queue_branch_window_line_word1_q[queue_tail_idx_c] <=
                            1'b0;
                        queue_epoch_q[queue_tail_idx_c] <= frontend_epoch_q;
                        queue_singleton_origin_q[queue_tail_idx_c] <=
                            next_pc_q[2] ? SINGLETON_ORIGIN_ALIGNED_SINGLE :
                            SINGLETON_ORIGIN_OTHER;
                        if (cross_line_initial_carry_c) begin
                            queue_pc_q[queue_tail_idx_c + 2'd1] <=
                                cross_line_next_pc_c;
                            queue_instr_q[queue_tail_idx_c + 2'd1] <=
                                adjacent_line_lookup_data_c[31:0];
                            queue_exception_q[
                                queue_tail_idx_c + 2'd1] <= 1'b0;
                            queue_branch_window_line_q[
                                queue_tail_idx_c + 2'd1] <=
                                target_line_branch_window_inject_c;
                            queue_branch_window_line_word1_q[
                                queue_tail_idx_c + 2'd1] <=
                                target_line_branch_window_inject_c;
                            queue_epoch_q[queue_tail_idx_c + 2'd1] <=
                                frontend_epoch_q;
                            queue_singleton_origin_q[
                                queue_tail_idx_c + 2'd1] <=
                                SINGLETON_ORIGIN_PAIR_WORD1;
                            queue_pc_q[queue_tail_idx_c + 2'd2] <=
                                cross_line_carry_pc_c;
                            queue_instr_q[queue_tail_idx_c + 2'd2] <=
                                cross_line_carry_instr_c;
                            queue_exception_q[
                                queue_tail_idx_c + 2'd2] <= 1'b0;
                            queue_branch_window_line_q[
                                queue_tail_idx_c + 2'd2] <=
                                target_line_branch_window_inject_c;
                            queue_branch_window_line_word1_q[
                                queue_tail_idx_c + 2'd2] <=
                                target_line_branch_window_inject_c;
                            queue_epoch_q[queue_tail_idx_c + 2'd2] <=
                                frontend_epoch_q;
                            queue_singleton_origin_q[
                                queue_tail_idx_c + 2'd2] <=
                                SINGLETON_ORIGIN_CROSS_LINE_CARRY;
                            queue_count_q <= queue_count_after_pop_c + 3'd3;
                        end else if (cross_line_cached_pair_c) begin
                            queue_pc_q[queue_tail_idx_c + 2'd1] <=
                                cross_line_next_pc_c;
                            queue_instr_q[queue_tail_idx_c + 2'd1] <=
                                adjacent_line_lookup_data_c[31:0];
                            queue_exception_q[
                                queue_tail_idx_c + 2'd1] <= 1'b0;
                            queue_branch_window_line_q[
                                queue_tail_idx_c + 2'd1] <=
                                target_line_branch_window_inject_c;
                            queue_branch_window_line_word1_q[
                                queue_tail_idx_c + 2'd1] <=
                                target_line_branch_window_inject_c;
                            queue_epoch_q[queue_tail_idx_c + 2'd1] <=
                                frontend_epoch_q;
                            queue_singleton_origin_q[
                                queue_tail_idx_c + 2'd1] <=
                                SINGLETON_ORIGIN_PAIR_WORD1;
                            queue_count_q <= queue_count_after_pop_c + 3'd2;
                        end else if (next_pc_q[2]) begin
                            queue_count_q <= queue_count_after_pop_c + 3'd1;
                        end else begin
                            queue_pc_q[queue_tail_idx_c + 2'd1] <=
                                next_pc_q + 32'd4;
                            queue_instr_q[queue_tail_idx_c + 2'd1] <=
                                target_line_lookup_data_c[63:32];
                            queue_exception_q[
                                queue_tail_idx_c + 2'd1] <= 1'b0;
                            queue_branch_window_line_q[
                                queue_tail_idx_c + 2'd1] <=
                                target_line_branch_window_inject_c;
                            queue_branch_window_line_word1_q[
                                queue_tail_idx_c + 2'd1] <=
                                target_line_branch_window_inject_c;
                            queue_epoch_q[queue_tail_idx_c + 2'd1] <=
                                frontend_epoch_q;
                            queue_singleton_origin_q[
                                queue_tail_idx_c + 2'd1] <=
                                SINGLETON_ORIGIN_PAIR_WORD1;
                            queue_count_q <= queue_count_after_pop_c + 3'd2;
                        end
                    end
                    next_pc_q <= next_pc_q +
                        ((cross_line_roll_fire_c ? 3'd2 :
                          cross_line_initial_carry_c ? 3'd3 :
                          cross_line_cached_pair_c ? 3'd2 :
                          target_line_word_count_c) << 2);
                end else if (response_fire_c) begin
                    if (!response_has_owner_c) begin
                        frontend_fault_q <= 1'b1;
                        frontend_fault_pc_q <= response_pc_c;
                        malformed_response_q <= 1'b1;
                    end else begin
                        if (response_stale_c) begin
                            stale_response_drop_q <= 1'b1;
                        end else if (fetch_rsp_page_fault_i === 1'b1) begin
                            if (direct_response_c &&
                                (direct_accept_mask_c == 2'b01)) begin
                                queue_count_q <= queue_count_after_pop_c;
                            end else begin
                                queue_pc_q[queue_tail_idx_c] <= response_pc_c;
                                queue_instr_q[queue_tail_idx_c] <= '0;
                                queue_exception_q[queue_tail_idx_c] <= 1'b1;
                                queue_branch_window_line_q[
                                    queue_tail_idx_c] <= 1'b0;
                                queue_branch_window_line_word1_q[
                                    queue_tail_idx_c] <= 1'b0;
                                queue_epoch_q[queue_tail_idx_c] <=
                                    frontend_epoch_q;
                                queue_singleton_origin_q[queue_tail_idx_c] <=
                                    SINGLETON_ORIGIN_EXCEPTION;
                                queue_count_q <=
                                    queue_count_after_pop_c + 3'd1;
                            end
                            next_pc_q <= response_pc_c + 32'd4;
                        end else if (fetch_rsp_error_i || response_malformed_c) begin
                            queue_head_q <= '0;
                            queue_count_q <= '0;
                            frontend_fault_q <= 1'b1;
                            frontend_fault_pc_q <= response_pc_c;
                            malformed_response_q <= response_malformed_c;
                        end else if (fetch_rsp_eof_i) begin
                            frontend_eof_q <= 1'b1;
                        end else begin
                            if (direct_response_c &&
                                (direct_accept_mask_c != 2'b00)) begin
                                if (cross_line_initial_carry_c) begin
                                    if (direct_accept_mask_c == 2'b01) begin
                                        queue_pc_q[queue_tail_idx_c] <=
                                            incoming_pc1_c;
                                        queue_instr_q[queue_tail_idx_c] <=
                                            incoming_instr1_c;
                                        queue_exception_q[
                                            queue_tail_idx_c] <= 1'b0;
                                        queue_branch_window_line_q[
                                            queue_tail_idx_c] <= 1'b0;
                                        queue_branch_window_line_word1_q[
                                            queue_tail_idx_c] <= 1'b0;
                                        queue_epoch_q[queue_tail_idx_c] <=
                                            frontend_epoch_q;
                                        queue_singleton_origin_q[
                                            queue_tail_idx_c] <=
                                            SINGLETON_ORIGIN_DIRECT_RESIDUAL;
                                        queue_pc_q[
                                            queue_tail_idx_c + 2'd1] <=
                                            cross_line_carry_pc_c;
                                        queue_instr_q[
                                            queue_tail_idx_c + 2'd1] <=
                                            cross_line_carry_instr_c;
                                        queue_exception_q[
                                            queue_tail_idx_c + 2'd1] <= 1'b0;
                                        queue_branch_window_line_q[
                                            queue_tail_idx_c + 2'd1] <= 1'b0;
                                        queue_branch_window_line_word1_q[
                                            queue_tail_idx_c + 2'd1] <= 1'b0;
                                        queue_epoch_q[
                                            queue_tail_idx_c + 2'd1] <=
                                            frontend_epoch_q;
                                        queue_singleton_origin_q[
                                            queue_tail_idx_c + 2'd1] <=
                                            SINGLETON_ORIGIN_CROSS_LINE_CARRY;
                                        queue_count_q <=
                                            queue_count_after_pop_c + 3'd2;
                                    end else begin
                                        queue_pc_q[queue_tail_idx_c] <=
                                            cross_line_carry_pc_c;
                                        queue_instr_q[queue_tail_idx_c] <=
                                            cross_line_carry_instr_c;
                                        queue_exception_q[
                                            queue_tail_idx_c] <= 1'b0;
                                        queue_branch_window_line_q[
                                            queue_tail_idx_c] <= 1'b0;
                                        queue_branch_window_line_word1_q[
                                            queue_tail_idx_c] <= 1'b0;
                                        queue_epoch_q[queue_tail_idx_c] <=
                                            frontend_epoch_q;
                                        queue_singleton_origin_q[
                                            queue_tail_idx_c] <=
                                            SINGLETON_ORIGIN_CROSS_LINE_CARRY;
                                        queue_count_q <=
                                            queue_count_after_pop_c + 3'd1;
                                    end
                                end else if ((incoming_valid_mask_c == 2'b11) &&
                                    (direct_accept_mask_c == 2'b01)) begin
                                    queue_pc_q[queue_tail_idx_c] <=
                                        incoming_pc1_c;
                                    queue_instr_q[queue_tail_idx_c] <=
                                        incoming_instr1_c;
                                    queue_exception_q[queue_tail_idx_c] <=
                                        1'b0;
                                    queue_branch_window_line_q[
                                        queue_tail_idx_c] <= 1'b0;
                                    queue_branch_window_line_word1_q[
                                        queue_tail_idx_c] <= 1'b0;
                                    queue_epoch_q[queue_tail_idx_c] <=
                                        frontend_epoch_q;
                                    queue_singleton_origin_q[
                                        queue_tail_idx_c] <=
                                        SINGLETON_ORIGIN_DIRECT_RESIDUAL;
                                    queue_count_q <=
                                        queue_count_after_pop_c + 3'd1;
                                end else begin
                                    queue_count_q <= queue_count_after_pop_c;
                                end
                            end else begin
                                queue_pc_q[queue_tail_idx_c] <= response_pc_c;
                                queue_instr_q[queue_tail_idx_c] <=
                                    response_pc_c[2] ?
                                    fetch_rsp_data_i[63:32] :
                                    fetch_rsp_data_i[31:0];
                                queue_exception_q[queue_tail_idx_c] <= 1'b0;
                                queue_branch_window_line_q[
                                    queue_tail_idx_c] <= 1'b0;
                                queue_branch_window_line_word1_q[
                                    queue_tail_idx_c] <= 1'b0;
                                queue_epoch_q[queue_tail_idx_c] <=
                                    frontend_epoch_q;
                                queue_singleton_origin_q[queue_tail_idx_c] <=
                                    response_pc_c[2] ?
                                    SINGLETON_ORIGIN_ALIGNED_SINGLE :
                                    SINGLETON_ORIGIN_OTHER;
                                if (cross_line_initial_carry_c) begin
                                    queue_pc_q[
                                        queue_tail_idx_c + 2'd1] <=
                                        cross_line_next_pc_c;
                                    queue_instr_q[
                                        queue_tail_idx_c + 2'd1] <=
                                        adjacent_line_lookup_data_c[31:0];
                                    queue_exception_q[
                                        queue_tail_idx_c + 2'd1] <= 1'b0;
                                    queue_branch_window_line_q[
                                        queue_tail_idx_c + 2'd1] <= 1'b0;
                                    queue_branch_window_line_word1_q[
                                        queue_tail_idx_c + 2'd1] <= 1'b0;
                                    queue_epoch_q[
                                        queue_tail_idx_c + 2'd1] <=
                                        frontend_epoch_q;
                                    queue_singleton_origin_q[
                                        queue_tail_idx_c + 2'd1] <=
                                        SINGLETON_ORIGIN_PAIR_WORD1;
                                    queue_pc_q[
                                        queue_tail_idx_c + 2'd2] <=
                                        cross_line_carry_pc_c;
                                    queue_instr_q[
                                        queue_tail_idx_c + 2'd2] <=
                                        cross_line_carry_instr_c;
                                    queue_exception_q[
                                        queue_tail_idx_c + 2'd2] <= 1'b0;
                                    queue_branch_window_line_q[
                                        queue_tail_idx_c + 2'd2] <= 1'b0;
                                    queue_branch_window_line_word1_q[
                                        queue_tail_idx_c + 2'd2] <= 1'b0;
                                    queue_epoch_q[
                                        queue_tail_idx_c + 2'd2] <=
                                        frontend_epoch_q;
                                    queue_singleton_origin_q[
                                        queue_tail_idx_c + 2'd2] <=
                                        SINGLETON_ORIGIN_CROSS_LINE_CARRY;
                                    queue_count_q <=
                                        queue_count_after_pop_c + 3'd3;
                                end else if (cross_line_cached_pair_c) begin
                                    queue_pc_q[
                                        queue_tail_idx_c + 2'd1] <=
                                        cross_line_next_pc_c;
                                    queue_instr_q[
                                        queue_tail_idx_c + 2'd1] <=
                                        adjacent_line_lookup_data_c[31:0];
                                    queue_exception_q[
                                        queue_tail_idx_c + 2'd1] <= 1'b0;
                                    queue_branch_window_line_q[
                                        queue_tail_idx_c + 2'd1] <= 1'b0;
                                    queue_branch_window_line_word1_q[
                                        queue_tail_idx_c + 2'd1] <= 1'b0;
                                    queue_epoch_q[
                                        queue_tail_idx_c + 2'd1] <=
                                        frontend_epoch_q;
                                    queue_singleton_origin_q[
                                        queue_tail_idx_c + 2'd1] <=
                                        SINGLETON_ORIGIN_PAIR_WORD1;
                                    queue_count_q <=
                                        queue_count_after_pop_c + 3'd2;
                                end else if (response_pc_c[2]) begin
                                    queue_count_q <=
                                        queue_count_after_pop_c + 3'd1;
                                end else begin
                                    queue_pc_q[queue_tail_idx_c + 2'd1] <=
                                        response_pc_c + 32'd4;
                                    queue_instr_q[
                                        queue_tail_idx_c + 2'd1] <=
                                        fetch_rsp_data_i[63:32];
                                    queue_exception_q[
                                        queue_tail_idx_c + 2'd1] <= 1'b0;
                                    queue_branch_window_line_q[
                                        queue_tail_idx_c + 2'd1] <= 1'b0;
                                    queue_branch_window_line_word1_q[
                                        queue_tail_idx_c + 2'd1] <= 1'b0;
                                    queue_epoch_q[
                                        queue_tail_idx_c + 2'd1] <=
                                        frontend_epoch_q;
                                    queue_singleton_origin_q[
                                        queue_tail_idx_c + 2'd1] <=
                                        SINGLETON_ORIGIN_PAIR_WORD1;
                                    queue_count_q <=
                                        queue_count_after_pop_c + 3'd2;
                                end
                            end
                            if (cross_line_cached_pair_c &&
                                response_from_queue_c)
                                next_pc_q <= response_pc_c +
                                    (cross_line_initial_carry_c ?
                                     32'd12 : 32'd8);
                        end
                    end
                end

                if (request_fire_c && !same_cycle_response_c) begin
                    request_pc_q[request_tail_q] <= next_pc_q;
                    request_addr_q[request_tail_q] <=
                        {next_pc_q[31:3], 3'b000};
                    request_epoch_q[request_tail_q] <= frontend_epoch_q;
                    request_words_q[request_tail_q] <= request_word_count_c;
                    request_tail_q <= request_tail_q + 2'd1;
                end
                if (request_fire_c) begin
                    next_pc_q <= next_pc_q +
                        (((cross_line_cached_pair_c && direct_response_c) ?
                          cross_line_direct_advance_words_c :
                          request_word_count_c) << 2);
                end

                unique case ({request_fire_c && !same_cycle_response_c,
                              response_fire_c && response_from_queue_c})
                    2'b10: begin
                        request_count_q <= request_count_q + 3'd1;
                        reserved_words_q <=
                            reserved_words_q + request_word_count_c;
                    end
                    2'b01: begin
                        request_head_q <= request_head_q + 2'd1;
                        request_count_q <= request_count_q - 3'd1;
                        reserved_words_q <= reserved_words_q -
                            request_words_q[request_head_q];
                    end
                    2'b11: begin
                        request_head_q <= request_head_q + 2'd1;
                        reserved_words_q <= reserved_words_q -
                            request_words_q[request_head_q] +
                            request_word_count_c;
                    end
                    default: begin
                        request_count_q <= request_count_q;
                        reserved_words_q <= reserved_words_q;
                    end
                endcase
            end
        end
    end
endmodule
