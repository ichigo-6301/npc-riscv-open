`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// S8J standalone composition. This module owns no fetch PC: after a held
// redirect handoff, its testbench supplies the correct-path Decode2 bundle.
module ooo_pipeline_branch_recovery_standalone_top #(
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
    parameter bit CORRECT_BRANCH_DUAL_RETIRE_ENABLE = 1'b0,
    parameter bit YOUNGER_SLOT1_CONTROL_DUAL_RETIRE_ENABLE = 1'b0,
    parameter bit POST_SELECTIVE_REDIRECT_COMMIT_ENABLE = 1'b0,
    parameter bit SELECTIVE_TRANSACTION_REDIRECT_OVERLAP_ENABLE = 1'b0,
    parameter bit STRONG_BRANCH_LINE_DELIVERY_ENABLE = 1'b0,
    parameter bit SPECULATIVE_STORE_DISPATCH_ENABLE = 1'b0,
    parameter bit STRUCTURAL_THROUGHPUT_ORACLE_ENABLE = 1'b0,
    parameter bit CORRELATED_REACHABILITY_ORACLE_ENABLE = 1'b0,
    parameter bit WEAK_BIMODAL_REACHABILITY_ORACLE_ENABLE = 1'b0,
    parameter bit LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE = 1'b0,
    parameter bit MULTIHISTORY_REACHABILITY_ORACLE_ENABLE = 1'b0
) (
    input logic clk,
    input logic reset,
    input logic external_global_recover_i,
    input logic [31:0] trap_target_i,
    input logic [31:0] xret_target_i,
    input bbus_ooo_ras_snapshot_t checkpoint_ras_snapshot_i,

    input logic [1:0] decode_valid_mask_i,
    input bbus_ooo_decode_uop_t decode_uop0_i,
    input bbus_ooo_decode_uop_t decode_uop1_i,
    output logic [1:0] decode_ready_mask_o,
    output logic [1:0] decode_accept_mask_o,

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

    // External serial model is retained for non-BRU sources only.
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
    input logic redirect_ready_i,
    output logic redirect_valid_o,
    output bbus_ooo_redirect_t redirect_o,
    output logic recovery_done_o,
    output logic branch_window_active_o,
    output logic branch_window_line_delivery_safe_o,
    output logic [3:0] branch_window_block_reason_o,
    output logic [9:0] perf_checkpoint_state_o,
    output logic branch_recovery_pending_o,
    output logic dispatch_freeze_o,
    output logic serial_dispatch_block_o,
    output logic selective_kill_valid_o,
    output logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_o,
    output logic predictor_update_valid_o,
    output logic [31:0] predictor_update_pc_o,
    output logic [31:0] predictor_update_direct_target_o,
    output bbus_ooo_pred_history_t predictor_update_history_o,
    output logic predictor_update_base_taken_o,
    output logic predictor_update_correlated_candidate_o,
    output logic predictor_update_correlated_taken_o,
    output bbus_ooo_local_history_t predictor_update_local_history_o,
    output logic predictor_update_local_strong_o,
    output logic predictor_update_local_taken_o,
    output bbus_ooo_multihistory_mask_t
        predictor_update_multihistory_hit_o,
    output bbus_ooo_multihistory_mask_t
        predictor_update_multihistory_strong_o,
    output bbus_ooo_multihistory_mask_t
        predictor_update_multihistory_taken_o,
    output bbus_ooo_multihistory_mask_t
        predictor_update_multihistory_chooser_prefer_o,
    output bbus_ooo_multihistory_mask_t
        predictor_update_multihistory_chooser_strong_o,
    output logic predictor_update_current_taken_o,
    output logic predictor_update_taken_o,
    output logic predictor_history_recover_valid_o,
    output bbus_ooo_pred_history_t predictor_history_recover_snapshot_o,
    output logic predictor_history_recover_conditional_o,
    output logic predictor_history_recover_taken_o,
    output logic indirect_update_valid_o,
    output logic [31:0] indirect_update_pc_o,
    output logic [31:0] indirect_update_target_o,
    output logic ras_update_valid_o,
    output bbus_ooo_ras_action_e ras_update_action_o,
    output logic [31:0] ras_update_link_o,
    output logic ras_restore_valid_o,
    input logic ras_restore_ready_i,
    input logic ras_restore_payload_valid_i,
    output bbus_ooo_ras_snapshot_t ras_restore_snapshot_o,
    output bbus_ooo_ras_action_e ras_restore_replay_action_o,
    output logic [31:0] ras_restore_replay_link_o,

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
    output logic [7:0] perf_predictor_o,
    output logic [63:0] perf_predictor_detail_o,
    output logic [15:0] perf_predictor_local_o,
    output logic [20:0] perf_predictor_multihistory_o,

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
    output logic debug_branch_issue_from_dispatch_o,
    output logic debug_branch_issue_same_cycle_final_o,
    output logic branch_protocol_error_o,
    output logic recovery_conservation_error_o,
    output logic conservation_error_o
);
    localparam logic [2:0] SK_BRU = 3'd0;

    logic p7_global_recover;
    logic p7_recovery_done;
    logic core_serial_issue_valid_i;
    logic core_serial_issue_ready;
    bbus_ooo_alu_iq_uop_t core_serial_issue_uop;
    logic [31:0] core_serial_issue_src1;
    logic [31:0] core_serial_issue_src2;
    logic [2:0] core_serial_issue_kind;
    logic core_serial_issue_from_dispatch;
    logic core_serial_completion_valid;
    logic core_serial_completion_ready;
    bbus_ooo_writeback_t core_serial_completion_wb;
    logic [2:0] core_serial_completion_kind;
    logic predictor_update_correlated_raw_candidate;
    logic predictor_update_correlated_chooser_prefer;
    logic predictor_update_base_counter_valid;
    logic predictor_update_base_counter_taken;
    logic predictor_update_local_chooser_prefer;
    logic predictor_update_local_chooser_strong;

    logic branch_issue_valid;
    logic branch_issue_ready;
    logic branch_issue_accept;
    logic branch_completion_valid;
    logic branch_completion_ready;
    bbus_ooo_writeback_t branch_completion_wb;
    logic branch_occupied;
    logic branch_flush_drop;
    logic branch_selective_unused_drop;
    logic branch_illegal_issue;
    logic registered_branch_fallthrough_eligible_c;
    logic registered_branch_fallthrough_protocol_error;
    logic branch_dispatch_fire;
    bbus_ooo_rob_tag_t branch_dispatch_tag;
    bbus_ooo_rob_tag_t backend_dispatch_tag0;
    bbus_ooo_rob_tag_t backend_dispatch_tag1;
    bbus_ooo_rob_tag_t backend_dispatch_post_tail_tag;
    bbus_ooo_rat_snapshot_t checkpoint_rat_snapshot;
    logic controller_recovery_pulse;
    logic branch_controller_redirect_valid;
    logic branch_controller_redirect_ready;
    bbus_ooo_redirect_t branch_controller_redirect;
    logic branch_controller_dispatch_freeze;
    logic branch_controller_serial_block;
    logic branch_controller_branch_allow;
    logic branch_controller_window;
    logic branch_controller_pending;
    logic control_dispatch_freeze;
    logic control_recovery_pending;
    logic control_branch_cancel;
    logic control_state_recovery_pulse;
    logic control_conservation;
    logic controller_admission_error;
    logic controller_unexpected_final;
    logic controller_conservation;
    logic controller_checkpoint_miss;
    logic branch_pending_select;
    logic checkpoint_release_valid, checkpoint_select_valid;
    bbus_ooo_rob_tag_t checkpoint_release_tag, checkpoint_select_tag;
    logic checkpoint_alloc_ready;
    bbus_ooo_checkpoint_id_t checkpoint_alloc_id;
    logic checkpoint_line_delivery_safe;
    logic checkpoint_blocking_pred_source_valid;
    bbus_ooo_pred_source_e checkpoint_blocking_pred_source;
    bbus_ooo_rob_tag_t checkpoint_blocking_branch_tag;
    logic branch_dispatch_line_delivery_safe;
    logic branch_dispatch_allow_c;
    bbus_ooo_renamed_uop_t branch_dispatch_uop;
    bbus_ooo_ras_action_e branch_dispatch_ras_action;
    logic [31:0] branch_dispatch_ras_link;
    logic checkpoint_lookup_hit;
    bbus_ooo_real_checkpoint_t checkpoint_lookup;
    logic checkpoint_debug_hit;
    bbus_ooo_real_checkpoint_t checkpoint_debug_payload;
    logic [1:0] checkpoint_valid_mask, checkpoint_count;
    logic checkpoint_duplicate_error, checkpoint_invalid_error;
    logic checkpoint_stale_release_error, checkpoint_stale_lookup_error;
    logic checkpoint_stale_purge_error;
    logic checkpoint_purge_ready, checkpoint_purge_fire;
    logic [1:0] checkpoint_purged_mask;
    logic checkpoint_conservation_error;
    bbus_ooo_real_checkpoint_t pending_checkpoint_q;
    logic pending_checkpoint_valid_q;
    logic ras_restore_missed_q;
    logic p7_recovery_mapping_error;
    logic p7_conservation_error;
    logic p7_atomic_recovery_deferred;
    logic external_bru_completion;
    logic serial_collision;
    logic [63:0] p7_perf_events;
    logic [63:0] p7_perf_lifecycle;
    logic [63:0] p7_perf_branch_producer_phase;
    logic p7_perf_ras_self_collision;
    logic [1:0] p7_branch_iq_ready_count;
    logic [1:0] branch_controller_window_count;
    logic branch_mispredict_final_c;
    logic selective_request_valid;
    bbus_ooo_rob_tag_t selective_request_branch_tag;
    logic selective_transaction_valid;
    logic selective_transaction_fire;
    logic backend_selective_recovery_pending;
    logic p7_selective_ready, p7_selective_fire;
    logic [`BBUS_OOO_ROB_ENTRIES-1:0] p7_selective_killed_rob_mask;
    logic [`BBUS_OOO_PHYS_REGS-1:0] p7_selective_killed_phys_mask;
    logic [3:0] p7_selective_killed_count;
    logic p7_selective_identity_error;
    logic control_redirect_valid;
    bbus_ooo_redirect_t control_redirect;
    logic control_redirect_ready;
    logic control_branch_redirect_unused_ready;
    logic speculative_store_dispatch_c;

    // Both branch and synchronous-control recovery pulses are registered
    // commit-age decisions. The public controller arbitrates those decisions
    // before the selected pulse reaches the backend flush boundary.
    assign p7_global_recover = external_global_recover_i ||
        controller_recovery_pulse;
    assign branch_issue_valid = core_serial_issue_valid_i &&
        (core_serial_issue_kind == SK_BRU);
    assign core_serial_issue_ready = branch_issue_valid ? branch_issue_ready :
        serial_issue_ready_i;

    always_comb begin
        serial_issue_valid_o = core_serial_issue_valid_i && !branch_issue_valid;
        serial_issue_uop_o = core_serial_issue_uop;
        serial_issue_src1_o = core_serial_issue_src1;
        serial_issue_src2_o = core_serial_issue_src2;
        serial_issue_kind_o = core_serial_issue_kind;

        external_bru_completion = serial_completion_valid_i &&
            (serial_completion_kind_i == SK_BRU);
        serial_collision = branch_completion_valid && serial_completion_valid_i;
        core_serial_completion_valid = 1'b0;
        core_serial_completion_wb = '0;
        core_serial_completion_kind = serial_completion_kind_i;

        if (branch_completion_valid) begin
            core_serial_completion_valid = 1'b1;
            core_serial_completion_wb = branch_completion_wb;
            core_serial_completion_kind = SK_BRU;
        end else if (!external_bru_completion) begin
            core_serial_completion_valid = serial_completion_valid_i;
            core_serial_completion_wb = serial_completion_wb_i;
            core_serial_completion_kind = serial_completion_kind_i;
        end
    end

    assign branch_completion_ready = branch_completion_valid &&
        core_serial_completion_ready;
    assign serial_completion_ready_o = !branch_completion_valid &&
        !external_bru_completion && core_serial_completion_ready;

    // P21 can retire only a correctly predicted conditional branch in slot1.
    // Keep jumps on the registered executor edge: completing them early
    // shortens the frontend branch window without creating a Commit2 path.
    assign registered_branch_fallthrough_eligible_c =
        !core_serial_issue_from_dispatch &&
        (core_serial_issue_uop.branch_op != BBUS_OOO_BR_JAL) &&
        (core_serial_issue_uop.branch_op != BBUS_OOO_BR_JALR);
    assign registered_branch_fallthrough_protocol_error =
        REGISTERED_BRANCH_ISSUE_FINAL_FALLTHROUGH_ENABLE &&
        SAME_CYCLE_BRANCH_DISPATCH_ISSUE_ENABLE &&
        !registered_branch_fallthrough_eligible_c &&
        branch_issue_accept && branch_completion_valid;
    assign debug_branch_issue_from_dispatch_o = branch_issue_valid &&
        core_serial_issue_from_dispatch;
    assign debug_branch_issue_same_cycle_final_o = branch_issue_accept &&
        branch_completion_valid;
    assign branch_protocol_error_o = external_bru_completion ||
        serial_collision || branch_illegal_issue ||
        registered_branch_fallthrough_protocol_error;
    assign branch_dispatch_fire =
        (backend_accept_mask_o[0] &&
         (debug_renamed_uop0_o.fu_type == BBUS_OOO_FU_BRU)) ||
        (backend_accept_mask_o[1] &&
         (debug_renamed_uop1_o.fu_type == BBUS_OOO_FU_BRU));
    assign branch_dispatch_tag =
        (backend_accept_mask_o[0] &&
         (debug_renamed_uop0_o.fu_type == BBUS_OOO_FU_BRU)) ?
        backend_dispatch_tag0 : backend_dispatch_tag1;
    assign branch_dispatch_uop =
        (backend_accept_mask_o[0] &&
         (debug_renamed_uop0_o.fu_type == BBUS_OOO_FU_BRU)) ?
        debug_renamed_uop0_o : debug_renamed_uop1_o;
    assign branch_dispatch_line_delivery_safe =
        (branch_dispatch_uop.pred_source == BBUS_OOO_PRED_DIRECT_JAL) ||
        branch_dispatch_uop.pred_correlated ||
        (STRONG_BRANCH_LINE_DELIVERY_ENABLE &&
         (branch_dispatch_uop.pred_source == BBUS_OOO_PRED_COND_STRONG));
    assign branch_dispatch_ras_link = branch_dispatch_uop.pc + 32'd4;
    assign ras_update_valid_o = branch_dispatch_fire && !p7_global_recover &&
        (branch_dispatch_ras_action != BBUS_OOO_RAS_NONE);
    assign ras_update_action_o = branch_dispatch_ras_action;
    assign ras_update_link_o = branch_dispatch_ras_link;
    always_comb begin
        logic rd_link, rs1_link;
        rd_link = (branch_dispatch_uop.arch_rd == 5'd1) ||
            (branch_dispatch_uop.arch_rd == 5'd5);
        rs1_link = (branch_dispatch_uop.arch_rs1 == 5'd1) ||
            (branch_dispatch_uop.arch_rs1 == 5'd5);
        branch_dispatch_ras_action = BBUS_OOO_RAS_NONE;
        if (branch_dispatch_uop.branch_op == BBUS_OOO_BR_JAL) begin
            if (rd_link) branch_dispatch_ras_action = BBUS_OOO_RAS_PUSH;
        end else if (branch_dispatch_uop.branch_op == BBUS_OOO_BR_JALR) begin
            if (rd_link && rs1_link) begin
                branch_dispatch_ras_action =
                    (branch_dispatch_uop.arch_rd ==
                     branch_dispatch_uop.arch_rs1) ?
                    BBUS_OOO_RAS_PUSH : BBUS_OOO_RAS_POP_PUSH;
            end else if (rd_link) begin
                branch_dispatch_ras_action = BBUS_OOO_RAS_PUSH;
            end else if (rs1_link) begin
                branch_dispatch_ras_action = BBUS_OOO_RAS_POP;
            end
        end
    end
    assign branch_dispatch_allow_c = branch_controller_branch_allow &&
        checkpoint_alloc_ready;
    assign selective_transaction_valid = selective_request_valid &&
        pending_checkpoint_valid_q &&
        checkpoint_purge_ready && ras_restore_ready_i &&
        ras_restore_payload_valid_i &&
        !external_global_recover_i;
    assign selective_transaction_fire = p7_selective_fire &&
        checkpoint_purge_fire && ras_restore_valid_o && ras_restore_ready_i;
    // Keep the atomic transaction Commit-exclusive. After it fires,
    // REC_REDIRECT owns only the frontend handoff, while dispatch_freeze_o
    // continues to block all new Decode/Rename/Dispatch ownership.
    assign backend_selective_recovery_pending =
        POST_SELECTIVE_REDIRECT_COMMIT_ENABLE ? selective_request_valid :
        branch_controller_pending;
    assign ras_restore_valid_o = p7_selective_fire &&
        pending_checkpoint_valid_q;
    assign ras_restore_snapshot_o = pending_checkpoint_q.ras_snapshot;
    assign ras_restore_replay_action_o =
        pending_checkpoint_q.branch_ras_action;
    assign ras_restore_replay_link_o = pending_checkpoint_q.branch_ras_link;

    always_ff @(posedge clk) begin
        if (reset || p7_global_recover) begin
            pending_checkpoint_q <= '0;
            pending_checkpoint_valid_q <= 1'b0;
            ras_restore_missed_q <= 1'b0;
        end else begin
            if (checkpoint_select_valid && checkpoint_lookup_hit) begin
                pending_checkpoint_q <= checkpoint_lookup;
                pending_checkpoint_valid_q <= 1'b1;
            end
            if (selective_request_valid && pending_checkpoint_valid_q &&
                !ras_restore_payload_valid_i)
                ras_restore_missed_q <= 1'b1;
            if (selective_transaction_fire) begin
                if (!pending_checkpoint_valid_q || !ras_restore_ready_i)
                    ras_restore_missed_q <= 1'b1;
                pending_checkpoint_valid_q <= 1'b0;
            end
        end
    end

    ooo_branch_checkpoint_state_2w u_checkpoint_state (
        .clk(clk), .reset(reset), .clear_all_i(p7_global_recover),
        .alloc_ready_o(checkpoint_alloc_ready),
        .alloc_checkpoint_id_o(checkpoint_alloc_id),
        .alloc_fire_i(branch_dispatch_fire),
        .alloc_branch_rob_tag_i(branch_dispatch_tag),
        .alloc_branch_pc_i(branch_dispatch_uop.pc),
        .alloc_branch_op_i(branch_dispatch_uop.branch_op),
        .alloc_branch_ras_action_i(branch_dispatch_ras_action),
        .alloc_branch_ras_link_i(branch_dispatch_ras_link),
        .alloc_rat_snapshot_i(checkpoint_rat_snapshot),
        .alloc_ras_snapshot_i(checkpoint_ras_snapshot_i),
        .alloc_post_branch_tail_tag_i(backend_dispatch_post_tail_tag),
        .alloc_line_delivery_safe_i(branch_dispatch_line_delivery_safe),
        .alloc_pred_source_i(branch_dispatch_uop.pred_source),
        .release_valid_i(checkpoint_release_valid),
        .release_branch_rob_tag_i(checkpoint_release_tag),
        .selective_purge_valid_i(p7_selective_fire),
        .selective_purge_branch_rob_tag_i(selective_request_branch_tag),
        .selective_purge_killed_rob_mask_i(p7_selective_killed_rob_mask),
        .selective_purge_ready_o(checkpoint_purge_ready),
        .selective_purge_fire_o(checkpoint_purge_fire),
        .selective_purged_mask_o(checkpoint_purged_mask),
        .lookup_valid_i(checkpoint_select_valid),
        .lookup_branch_rob_tag_i(checkpoint_select_tag),
        .lookup_hit_o(checkpoint_lookup_hit),
        .lookup_checkpoint_o(checkpoint_lookup),
        .debug_query_checkpoint_id_i('0),
        .debug_query_hit_o(checkpoint_debug_hit),
        .debug_query_checkpoint_o(checkpoint_debug_payload),
        .valid_mask_o(checkpoint_valid_mask),
        .checkpoint_count_o(checkpoint_count),
        .line_delivery_safe_o(checkpoint_line_delivery_safe),
        .blocking_pred_source_valid_o(
            checkpoint_blocking_pred_source_valid),
        .blocking_pred_source_o(checkpoint_blocking_pred_source),
        .blocking_branch_rob_tag_o(checkpoint_blocking_branch_tag),
        .duplicate_alloc_error_o(checkpoint_duplicate_error),
        .invalid_alloc_error_o(checkpoint_invalid_error),
        .stale_release_error_o(checkpoint_stale_release_error),
        .stale_lookup_error_o(checkpoint_stale_lookup_error),
        .stale_purge_error_o(checkpoint_stale_purge_error),
        .conservation_error_o(checkpoint_conservation_error)
    );

    ooo_branch_pipeline_1w #(
        .ISSUE_COMPLETION_FALLTHROUGH_ENABLE(
            BRANCH_ISSUE_FINAL_FALLTHROUGH_ENABLE &&
            (!SAME_CYCLE_BRANCH_DISPATCH_ISSUE_ENABLE ||
             REGISTERED_BRANCH_ISSUE_FINAL_FALLTHROUGH_ENABLE))
    ) u_branch_pipeline (
        .clk(clk),
        .reset(reset),
        .flush_i(p7_global_recover),
        .selective_kill_valid_i(p7_selective_fire),
        .selective_killed_rob_mask_i(p7_selective_killed_rob_mask),
        .issue_valid_i(branch_issue_valid),
        .issue_completion_fallthrough_i(
            !SAME_CYCLE_BRANCH_DISPATCH_ISSUE_ENABLE ||
            (REGISTERED_BRANCH_ISSUE_FINAL_FALLTHROUGH_ENABLE &&
             registered_branch_fallthrough_eligible_c)),
        .issue_uop_i(core_serial_issue_uop),
        .src1_data_i(core_serial_issue_src1),
        .src2_data_i(core_serial_issue_src2),
        .issue_ready_o(branch_issue_ready),
        .issue_accept_o(branch_issue_accept),
        .completion_wb_o(branch_completion_wb),
        .completion_valid_o(branch_completion_valid),
        .completion_ready_i(branch_completion_ready),
        .predictor_update_valid_o(predictor_update_valid_o),
        .predictor_update_pc_o(predictor_update_pc_o),
        .predictor_update_direct_target_o(predictor_update_direct_target_o),
        .predictor_update_history_o(predictor_update_history_o),
        .predictor_update_base_taken_o(predictor_update_base_taken_o),
        .predictor_update_base_counter_valid_o(
            predictor_update_base_counter_valid),
        .predictor_update_base_counter_taken_o(
            predictor_update_base_counter_taken),
        .predictor_update_correlated_candidate_o(
            predictor_update_correlated_candidate_o),
        .predictor_update_correlated_raw_candidate_o(
            predictor_update_correlated_raw_candidate),
        .predictor_update_correlated_chooser_prefer_o(
            predictor_update_correlated_chooser_prefer),
        .predictor_update_correlated_taken_o(
            predictor_update_correlated_taken_o),
        .predictor_update_local_history_o(
            predictor_update_local_history_o),
        .predictor_update_local_strong_o(
            predictor_update_local_strong_o),
        .predictor_update_local_taken_o(
            predictor_update_local_taken_o),
        .predictor_update_local_chooser_prefer_o(
            predictor_update_local_chooser_prefer),
        .predictor_update_local_chooser_strong_o(
            predictor_update_local_chooser_strong),
        .predictor_update_multihistory_hit_o(
            predictor_update_multihistory_hit_o),
        .predictor_update_multihistory_strong_o(
            predictor_update_multihistory_strong_o),
        .predictor_update_multihistory_taken_o(
            predictor_update_multihistory_taken_o),
        .predictor_update_multihistory_chooser_prefer_o(
            predictor_update_multihistory_chooser_prefer_o),
        .predictor_update_multihistory_chooser_strong_o(
            predictor_update_multihistory_chooser_strong_o),
        .predictor_update_current_taken_o(
            predictor_update_current_taken_o),
        .predictor_update_taken_o(predictor_update_taken_o),
        .predictor_history_recover_valid_o(
            predictor_history_recover_valid_o),
        .predictor_history_recover_snapshot_o(
            predictor_history_recover_snapshot_o),
        .predictor_history_recover_conditional_o(
            predictor_history_recover_conditional_o),
        .predictor_history_recover_taken_o(
            predictor_history_recover_taken_o),
        .indirect_update_valid_o(indirect_update_valid_o),
        .indirect_update_pc_o(indirect_update_pc_o),
        .indirect_update_target_o(indirect_update_target_o),
        .perf_predictor_o(perf_predictor_o),
        .perf_ras_self_collision_o(p7_perf_ras_self_collision),
        .occupied_o(branch_occupied),
        .flush_drop_o(branch_flush_drop),
        .selective_kill_drop_o(branch_selective_unused_drop),
        .illegal_issue_o(branch_illegal_issue)
    );

    ooo_branch_execute_age_recovery_1w #(
        .SELECTIVE_TRANSACTION_REDIRECT_OVERLAP_ENABLE(
            SELECTIVE_TRANSACTION_REDIRECT_OVERLAP_ENABLE)
    ) u_recovery (
        .clk(clk),
        .reset(reset),
        .external_global_recover_i(external_global_recover_i ||
            control_state_recovery_pulse),
        .branch_dispatch_fire_i(branch_dispatch_fire),
        .branch_dispatch_rob_tag_i(branch_dispatch_tag),
        .branch_issue_accept_i(branch_issue_accept),
        .branch_issue_rob_tag_i(core_serial_issue_uop.rob_tag),
        .final_consume_mask_i(final_consume_mask_o),
        .final_wb0_i(final_wb0_o),
        .final_wb1_i(final_wb1_o),
        .checkpoint_lookup_hit_i(checkpoint_lookup_hit),
        .checkpoint_branch_pc_i(checkpoint_lookup.branch_pc),
        .checkpoint_release_valid_o(checkpoint_release_valid),
        .checkpoint_release_tag_o(checkpoint_release_tag),
        .checkpoint_select_valid_o(checkpoint_select_valid),
        .checkpoint_select_tag_o(checkpoint_select_tag),
        .selective_request_valid_o(selective_request_valid),
        .selective_request_branch_tag_o(selective_request_branch_tag),
        .selective_transaction_fire_i(selective_transaction_fire),
        .selective_killed_rob_mask_i(p7_selective_killed_rob_mask),
        .redirect_ready_i(branch_controller_redirect_ready),
        .dispatch_freeze_o(branch_controller_dispatch_freeze),
        .serial_dispatch_block_o(branch_controller_serial_block),
        .branch_dispatch_allow_o(branch_controller_branch_allow),
        .branch_window_active_o(branch_controller_window),
        .branch_window_count_o(branch_controller_window_count),
        .branch_recovery_pending_o(branch_controller_pending),
        .redirect_valid_o(branch_controller_redirect_valid),
        .redirect_o(branch_controller_redirect),
        .admission_error_o(controller_admission_error),
        .unexpected_branch_final_o(controller_unexpected_final),
        .checkpoint_miss_error_o(controller_checkpoint_miss),
        .conservation_error_o(controller_conservation)
    );

    ooo_pipeline_commit_control_recovery_1w u_control_recovery (
        .clk(clk),
        .reset(reset),
        .external_global_recover_i(external_global_recover_i),
        .final_consume_mask_i(final_consume_mask_o),
        .final_wb0_i(final_wb0_o),
        .final_wb1_i(final_wb1_o),
        .commit_event_i(commit_event_o),
        .trap_target_i(trap_target_i),
        .xret_target_i(xret_target_i),
        .branch_recovery_pulse_i(1'b0),
        .branch_redirect_valid_i(1'b0),
        .branch_redirect_i('0),
        .branch_redirect_ready_o(control_branch_redirect_unused_ready),
        .branch_cancel_o(control_branch_cancel),
        .control_state_recovery_pulse_o(control_state_recovery_pulse),
        .redirect_ready_i(control_redirect_ready),
        .dispatch_freeze_o(control_dispatch_freeze),
        .recovery_pending_o(control_recovery_pending),
        .recovery_pulse_o(controller_recovery_pulse),
        .redirect_valid_o(control_redirect_valid),
        .redirect_o(control_redirect),
        .conservation_error_o(control_conservation)
    );

    // Synchronous control/global recovery has priority.  Execute-age branch
    // redirect is a separate no-global channel and is exposed only after the
    // selective transaction has completed atomically.
    assign redirect_valid_o = control_redirect_valid ||
        branch_controller_redirect_valid;
    assign redirect_o = control_redirect_valid ? control_redirect :
        branch_controller_redirect;
    assign control_redirect_ready = redirect_ready_i && control_redirect_valid;
    assign branch_controller_redirect_ready = redirect_ready_i &&
        !control_redirect_valid && branch_controller_redirect_valid;
    assign branch_pending_select = checkpoint_select_valid;

    assign dispatch_freeze_o = branch_controller_dispatch_freeze ||
        control_dispatch_freeze || p7_atomic_recovery_deferred;
    assign serial_dispatch_block_o = branch_controller_serial_block ||
        control_recovery_pending;
    assign speculative_store_dispatch_c =
        SPECULATIVE_STORE_DISPATCH_ENABLE && branch_controller_window &&
        !branch_controller_pending && !control_recovery_pending &&
        !external_global_recover_i;
    assign branch_window_active_o = branch_controller_window ||
        control_recovery_pending;
    assign branch_window_line_delivery_safe_o = branch_controller_window &&
        checkpoint_line_delivery_safe && !control_recovery_pending;
    assign perf_checkpoint_state_o = {
        checkpoint_blocking_branch_tag,
        checkpoint_blocking_pred_source_valid,
        checkpoint_alloc_ready,
        checkpoint_count
    };
    always_comb begin
        branch_window_block_reason_o = 4'd0;
        if (control_recovery_pending) begin
            branch_window_block_reason_o = 4'd8;
        end else if (branch_controller_window &&
                     !checkpoint_line_delivery_safe) begin
            if (!checkpoint_blocking_pred_source_valid) begin
                branch_window_block_reason_o = 4'd9;
            end else begin
                unique case (checkpoint_blocking_pred_source)
                    BBUS_OOO_PRED_COND_MISS:
                        branch_window_block_reason_o = 4'd1;
                    BBUS_OOO_PRED_COND_WEAK:
                        branch_window_block_reason_o = 4'd2;
                    BBUS_OOO_PRED_COND_STRONG:
                        branch_window_block_reason_o = 4'd3;
                    BBUS_OOO_PRED_JALR_RAS:
                        branch_window_block_reason_o = 4'd5;
                    BBUS_OOO_PRED_JALR_BTB:
                        branch_window_block_reason_o = 4'd6;
                    BBUS_OOO_PRED_JALR_MISS:
                        branch_window_block_reason_o = 4'd7;
                    default:
                        branch_window_block_reason_o = 4'd9;
                endcase
            end
        end
    end
    assign branch_recovery_pending_o = branch_controller_pending ||
        control_recovery_pending || p7_atomic_recovery_deferred;
    assign selective_kill_valid_o = p7_selective_fire;
    assign selective_killed_rob_mask_o = p7_selective_killed_rob_mask;

    ooo_pipeline_frontend_backend_standalone_top #(
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
        .STRUCTURAL_THROUGHPUT_ORACLE_ENABLE(
            STRUCTURAL_THROUGHPUT_ORACLE_ENABLE)
    ) u_p7 (
        .clk(clk),
        .reset(reset),
        .global_recover_i(p7_global_recover),
        .branch_nonblocking_i(branch_dispatch_allow_c),
        .dispatch_freeze_i(dispatch_freeze_o),
        .serial_dispatch_block_i(serial_dispatch_block_o),
        .speculative_store_dispatch_i(speculative_store_dispatch_c),
        .selective_recovery_pending_i(backend_selective_recovery_pending),
        .selective_squash_valid_i(selective_transaction_valid),
        .selective_squash_branch_tag_i(selective_request_branch_tag),
        .selective_squash_post_tail_tag_i(
            pending_checkpoint_q.post_branch_tail_tag),
        .selective_restore_rat_snapshot_i(
            pending_checkpoint_q.rat_snapshot),
        .selective_squash_ready_o(p7_selective_ready),
        .selective_squash_fire_o(p7_selective_fire),
        .selective_killed_rob_mask_o(p7_selective_killed_rob_mask),
        .selective_killed_phys_mask_o(p7_selective_killed_phys_mask),
        .selective_killed_count_o(p7_selective_killed_count),
        .selective_recovery_identity_error_o(p7_selective_identity_error),
        .decode_valid_mask_i(decode_valid_mask_i),
        .decode_uop0_i(decode_uop0_i),
        .decode_uop1_i(decode_uop1_i),
        .decode_ready_mask_o(decode_ready_mask_o),
        .decode_accept_mask_o(decode_accept_mask_o),
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
        .serial_issue_valid_o(core_serial_issue_valid_i),
        .serial_issue_ready_i(core_serial_issue_ready),
        .serial_issue_uop_o(core_serial_issue_uop),
        .serial_issue_src1_o(core_serial_issue_src1),
        .serial_issue_src2_o(core_serial_issue_src2),
        .serial_issue_kind_o(core_serial_issue_kind),
        .serial_issue_from_dispatch_o(core_serial_issue_from_dispatch),
        .serial_completion_valid_i(core_serial_completion_valid),
        .serial_completion_ready_o(core_serial_completion_ready),
        .serial_completion_wb_i(core_serial_completion_wb),
        .serial_completion_kind_i(core_serial_completion_kind),
        .commit_enable_i(commit_enable_i),
        .commit_event_o(commit_event_o),
        .recovery_done_o(p7_recovery_done),
        .serial_barrier_o(serial_barrier_o),
        .rename_fire_mask_o(rename_fire_mask_o),
        .backend_accept_mask_o(backend_accept_mask_o),
        .backend_dispatch_tag0_o(backend_dispatch_tag0),
        .backend_dispatch_tag1_o(backend_dispatch_tag1),
        .backend_dispatch_post_tail_tag_o(backend_dispatch_post_tail_tag),
        .checkpoint_rat_snapshot_o(checkpoint_rat_snapshot),
        .final_consume_mask_o(final_consume_mask_o),
        .final_wb0_o(final_wb0_o),
        .final_wb1_o(final_wb1_o),
        .rob_count_o(rob_count_o),
        .iq_count_o(iq_count_o),
        .backend_busy_o(backend_busy_o),
        .atomic_recovery_deferred_o(p7_atomic_recovery_deferred),
        .perf_dispatch_width_o(perf_dispatch_width_o),
        .perf_issue_width_o(perf_issue_width_o),
        .perf_dispatch_reason0_o(perf_dispatch_reason0_o),
        .perf_dispatch_reason1_o(perf_dispatch_reason1_o),
        .perf_issue_reason0_o(perf_issue_reason0_o),
        .perf_issue_reason1_o(perf_issue_reason1_o),
        .perf_commit_reason0_o(perf_commit_reason0_o),
        .perf_commit_reason1_o(perf_commit_reason1_o),
        .perf_branch_iq_ready_count_o(p7_branch_iq_ready_count),
        .perf_backend_events_o(p7_perf_events),
        .perf_mixed_source_o(perf_mixed_source_o),
        .perf_structural_oracle_o(perf_structural_oracle_o),
        .perf_structural_meta_o(perf_structural_meta_o),
        .perf_accounting_raw_o(perf_accounting_raw_o),
        .perf_store_buffer_o(perf_store_buffer_o),
        .perf_branch_pair_o(perf_branch_pair_o),
        .perf_operand_stage_o(perf_operand_stage_o),
        .perf_lifecycle_o(p7_perf_lifecycle),
        .perf_branch_operand_o(perf_branch_operand_o),
        .perf_branch_producer_phase_o(p7_perf_branch_producer_phase),
        .perf_lsu_causality_o(perf_lsu_causality_o),
        .perf_store_admission_o(perf_store_admission_o),
        .perf_issue_dependency_o(perf_issue_dependency_o),
        .perf_retirement_chain_o(perf_retirement_chain_o),
        .perf_complex_retire_pairing_o(perf_complex_retire_pairing_o),
        .perf_completion_ownership_o(perf_completion_ownership_o),
        .perf_serial_attribution_o(perf_serial_attribution_o),
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
        .recovery_mapping_error_o(p7_recovery_mapping_error),
        .conservation_error_o(p7_conservation_error)
    );

    assign recovery_done_o = p7_recovery_done;
    assign perf_branch_resolution_o = {
        branch_controller_window_count,
        checkpoint_select_valid || checkpoint_release_valid,
        branch_completion_valid && branch_completion_ready,
        branch_completion_valid,
        branch_issue_accept,
        branch_issue_valid,
        p7_branch_iq_ready_count
    };
    always_comb begin
        perf_events_o = p7_perf_events;
        perf_events_o[32] = branch_issue_accept;
        perf_events_o[33] = checkpoint_select_valid ||
            checkpoint_release_valid;
        perf_events_o[34] = branch_controller_redirect_valid &&
            branch_controller_redirect_ready;
        perf_events_o[35] = redirect_valid_o && redirect_ready_i;
        perf_events_o[36] = p7_global_recover;
        perf_events_o[37] = branch_recovery_pending_o;
        perf_events_o[38] = branch_occupied;
        perf_events_o[39] = external_global_recover_i;

        branch_mispredict_final_c =
            (final_consume_mask_o[0] && final_wb0_o.valid &&
             final_wb0_o.is_control &&
             (final_wb0_o.is_branch || final_wb0_o.is_jal ||
              final_wb0_o.is_jalr) && final_wb0_o.redirect_valid) ||
            (final_consume_mask_o[1] && final_wb1_o.valid &&
             final_wb1_o.is_control &&
             (final_wb1_o.is_branch || final_wb1_o.is_jal ||
              final_wb1_o.is_jalr) && final_wb1_o.redirect_valid);
        perf_lifecycle_o = p7_perf_lifecycle;
        perf_lifecycle_o[9] = branch_pending_select;
        perf_lifecycle_o[10] = branch_controller_redirect_valid &&
            branch_controller_redirect_ready;
        perf_lifecycle_o[14] = backend_accept_mask_o[0] &&
            debug_renamed_uop0_o.branch_window_line;
        perf_lifecycle_o[15] = backend_accept_mask_o[1] &&
            debug_renamed_uop1_o.branch_window_line;
        perf_lifecycle_o[59] = backend_accept_mask_o[0] &&
            debug_renamed_uop0_o.branch_window_line_word1;
        perf_lifecycle_o[63] = backend_accept_mask_o[1] &&
            debug_renamed_uop1_o.branch_window_line_word1;

        perf_branch_producer_phase_o = p7_perf_branch_producer_phase;
        perf_branch_producer_phase_o[48] =
            branch_completion_valid && branch_completion_ready;
        perf_branch_producer_phase_o[53:49] = {
            branch_completion_wb.rob_tag.gen,
            branch_completion_wb.rob_tag.idx
        };
        perf_branch_producer_phase_o[54] =
            checkpoint_blocking_pred_source_valid;
        perf_branch_producer_phase_o[59:55] = {
            checkpoint_blocking_branch_tag.gen,
            checkpoint_blocking_branch_tag.idx
        };
        perf_branch_producer_phase_o[60] =
            (perf_branch_producer_phase_o[48] &&
             !branch_completion_wb.rob_tag.valid) ||
            (checkpoint_blocking_pred_source_valid &&
             !checkpoint_blocking_branch_tag.valid);

        // Simulation-only identity for every completed control instruction.
        // Keep the existing perf_predictor_o encoding unchanged.
        perf_predictor_detail_o = 64'd0;
        perf_predictor_detail_o[0] = perf_predictor_o[0];
        perf_predictor_detail_o[3:1] = perf_predictor_o[3:1];
        perf_predictor_detail_o[4] = perf_predictor_o[4];
        perf_predictor_detail_o[5] = perf_predictor_o[5];
        perf_predictor_detail_o[6] = perf_predictor_o[6];
        perf_predictor_detail_o[7] = perf_predictor_o[7];
        perf_predictor_detail_o[8] = predictor_update_base_taken_o;
        perf_predictor_detail_o[9] =
            predictor_update_correlated_candidate_o;
        perf_predictor_detail_o[10] = predictor_update_correlated_taken_o;
        perf_predictor_detail_o[18:11] = predictor_update_history_o;
        perf_predictor_detail_o[50:19] = predictor_update_pc_o;
        perf_predictor_detail_o[55:51] = {
            branch_completion_wb.rob_tag.gen,
            branch_completion_wb.rob_tag.idx
        };
        perf_predictor_detail_o[56] = predictor_update_valid_o;
        perf_predictor_detail_o[57] = branch_completion_wb.is_branch;
        perf_predictor_detail_o[58] = branch_completion_wb.is_jal;
        perf_predictor_detail_o[59] = branch_completion_wb.is_jalr;
        perf_predictor_detail_o[60] = branch_completion_wb.redirect_valid;
        perf_predictor_detail_o[61] = p7_perf_ras_self_collision;
        perf_predictor_detail_o[62] =
            predictor_update_valid_o && (
            (CORRELATED_REACHABILITY_ORACLE_ENABLE &&
             predictor_update_correlated_raw_candidate) ||
            (WEAK_BIMODAL_REACHABILITY_ORACLE_ENABLE &&
             predictor_update_base_counter_valid));
        perf_predictor_detail_o[63] =
            predictor_update_valid_o && (
            (CORRELATED_REACHABILITY_ORACLE_ENABLE &&
             predictor_update_correlated_chooser_prefer) ||
            (WEAK_BIMODAL_REACHABILITY_ORACLE_ENABLE &&
             predictor_update_base_counter_taken));

        perf_predictor_local_o = 16'b0;
        if (LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE) begin
            perf_predictor_local_o[14] = 1'b1;
            if (perf_predictor_o[0]) begin
                perf_predictor_local_o[0] = 1'b1;
                perf_predictor_local_o[1] = predictor_update_valid_o;
                perf_predictor_local_o[2] =
                    predictor_update_current_taken_o;
                perf_predictor_local_o[3] = predictor_update_taken_o;
                perf_predictor_local_o[4] =
                    predictor_update_local_strong_o;
                perf_predictor_local_o[5] =
                    predictor_update_local_taken_o;
                perf_predictor_local_o[6] =
                    predictor_update_local_chooser_prefer;
                perf_predictor_local_o[7] =
                    predictor_update_local_chooser_strong;
                perf_predictor_local_o[13:8] =
                    predictor_update_local_history_o;
            end
        end
        perf_predictor_multihistory_o = 21'b0;
        if (MULTIHISTORY_REACHABILITY_ORACLE_ENABLE) begin
            perf_predictor_multihistory_o[19] = 1'b1;
            if (perf_predictor_o[0]) begin
                perf_predictor_multihistory_o[0] = 1'b1;
                perf_predictor_multihistory_o[1] =
                    predictor_update_valid_o;
                perf_predictor_multihistory_o[2] =
                    predictor_update_current_taken_o;
                perf_predictor_multihistory_o[3] =
                    predictor_update_taken_o;
                perf_predictor_multihistory_o[6:4] =
                    predictor_update_multihistory_hit_o;
                perf_predictor_multihistory_o[9:7] =
                    predictor_update_multihistory_strong_o;
                perf_predictor_multihistory_o[12:10] =
                    predictor_update_multihistory_taken_o;
                perf_predictor_multihistory_o[15:13] =
                    predictor_update_multihistory_chooser_prefer_o;
                perf_predictor_multihistory_o[18:16] =
                    predictor_update_multihistory_chooser_strong_o;
                perf_predictor_multihistory_o[20] =
                    (|(predictor_update_multihistory_strong_o &
                       ~predictor_update_multihistory_hit_o)) ||
                    (|(predictor_update_multihistory_chooser_prefer_o &
                       ~predictor_update_multihistory_hit_o)) ||
                    (|(predictor_update_multihistory_chooser_strong_o &
                       ~predictor_update_multihistory_chooser_prefer_o));
            end
        end
    end
    assign recovery_conservation_error_o = p7_recovery_mapping_error ||
        controller_admission_error || controller_unexpected_final ||
        controller_checkpoint_miss || p7_selective_identity_error ||
        checkpoint_conservation_error || checkpoint_stale_purge_error ||
        ras_restore_missed_q;
    assign conservation_error_o = p7_conservation_error || controller_conservation ||
        control_conservation || branch_protocol_error_o ||
        p7_selective_identity_error || checkpoint_conservation_error ||
        checkpoint_stale_purge_error || ras_restore_missed_q;
endmodule
