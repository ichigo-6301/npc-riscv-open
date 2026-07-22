`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module cpu_top_ooo_shadow #(
    parameter logic [31:0] RESET_VECTOR = 32'h8000_0000,
    parameter int ALU_LATENCY = 1,
    parameter int ALU1_LATENCY = ALU_LATENCY
) (
    input  logic clk,
    input  logic rst_n,

    input  logic program_valid_i,
    input  logic [31:0] program_pc_i,
    input  logic [31:0] program_instr_i,
    output logic program_ready_o,

    input  logic trace_ready_i,
    input  logic debug_commit_enable_i,
    input  bbus_ooo_arch_reg_t debug_arch_idx_i,
    input  bbus_ooo_phys_reg_t debug_phys_idx_i,
    input  bbus_ooo_phys_reg_t debug_prf_phys_idx_i,
    input  bbus_ooo_rob_idx_t debug_rob_idx_i,

    output logic commit_valid_o,
    output logic [1:0] commit_mask_o,
    output logic commit_slot1_o,
    output logic [31:0] commit_pc_o,
    output logic [31:0] commit_instr_o,
    output logic [31:0] commit_nextpc_o,
    output logic commit_rf_wen_o,
    output bbus_ooo_arch_reg_t commit_rd_o,
    output logic [31:0] commit_wdata_o,
    output logic commit_is_load_o,
    output logic commit_is_store_o,
    output logic commit_is_branch_o,
    output logic commit_is_jal_o,
    output logic commit_is_jalr_o,
    output logic [31:0] commit_mem_addr_o,
    output logic [31:0] commit_mem_wdata_o,
    output logic [3:0] commit_mem_wstrb_o,
    output logic [2:0] commit_mem_len_o,
    output logic commit_unsupported_o,
    output logic commit_exception_valid_o,
    output logic control_pending_o,
    output logic memory_pending_o,
    output logic commit_redirect_valid_o,
    output logic [31:0] commit_redirect_pc_o,

    output logic trace_valid_o,
    output bbus_ooo_commit_trace_packet_t trace_packet_o,

    output bbus_ooo_commit_event_t debug_commit_event_o,
    output logic debug_packet_buffer_valid_o,
    output logic debug_last_packet_accepted_o,
    output logic debug_last_commit_dropped_o,
    output logic debug_shadow_idle_o,
    output logic debug_unsupported_seen_o,
    output logic [31:0] debug_unsupported_pc_o,
    output logic [31:0] debug_unsupported_instr_o,
    output logic [31:0] debug_arch_gpr_o,
    output logic [31:0] debug_arch_pc_o,
    output logic debug_dispatch_candidate_o,
    output logic debug_rename_fire_o,
    output bbus_ooo_renamed_uop_t debug_renamed_uop_o,
    output logic debug_rob_done_o,
    output logic [31:0] debug_rob_result_o,
    output logic [3:0] debug_rob_count_o,
    output logic [3:0] debug_iq_count_o,
    output logic [3:0] debug_iq_ready_count_o,
    output logic [3:0] debug_iq_ready_alu_count_o,
    output logic [3:0] debug_iq_ready_lsu_count_o,
    output logic [3:0] debug_iq_ready_bru_count_o,
    output logic [3:0] debug_iq_ready_csr_sys_count_o,
    output logic [3:0] debug_iq_ready_any_count_o,
    output logic [3:0] debug_issue_candidate_count_o,
    output logic debug_issue_multi_candidate_o,
    output logic debug_rob_full_o,
    output logic debug_iq_full_o,
    output logic debug_wb_buffer_full_o,
    output logic debug_wb_buffer_valid_o,
    output logic debug_alu_busy_o,
    output logic debug_branch_busy_o,
    output logic debug_lsu_busy_o,
    output logic debug_csr_busy_o,
    output logic debug_alu_completion_valid_o,
    output logic debug_branch_completion_valid_o,
    output logic debug_lsu_completion_valid_o,
    output logic debug_csr_completion_valid_o,
    output logic debug_execution_path_clear_o,
    output logic debug_dispatch_valid_o,
    output logic debug_dispatch_ready_o,
    output logic debug_iq_enqueue_o,
    output logic debug_iq_issue_valid_o,
    output logic debug_iq_issue_ready_o,
    output logic debug_issue_fire_o,
    output logic debug_issue_fu_ready_o,
    output logic debug_wb_accept_o,
    output logic debug_wb_stall_o,
    output logic debug_alu_issue_o,
    output logic debug_branch_issue_o,
    output logic debug_lsu_issue_o,
    output logic debug_csr_issue_o,
    output logic debug_wb_conflict_o,
    output logic debug_completion_grant_alu_o,
    output logic debug_completion_grant_bru_o,
    output logic debug_completion_grant_lsu_o,
    output logic debug_completion_grant_csr_o,
    output logic debug_completion_hold_alu_o,
    output logic debug_completion_hold_bru_o,
    output logic debug_completion_hold_lsu_o,
    output logic debug_completion_hold_csr_o,
    output logic debug_completion_oldest_arb_o,
    output logic debug_completion_fixed_arb_o,
    output logic debug_completion_oldest_grant_alu_o,
    output logic debug_completion_oldest_grant_bru_o,
    output logic debug_completion_oldest_grant_lsu_o,
    output logic debug_completion_oldest_grant_csr_o,
    output logic debug_completion_fixed_would_choose_alu_o,
    output logic debug_completion_fixed_would_choose_bru_o,
    output logic debug_completion_fixed_would_choose_lsu_o,
    output logic debug_completion_fixed_would_choose_csr_o,
    output logic debug_completion_oldest_differs_from_fixed_o,
    output logic debug_duplicate_completion_tag_o,
    output logic debug_completion_arb_no_valid_bug_o,
    output logic debug_issue0_fire_o,
    output logic debug_issue1_fire_o,
    output logic debug_issue2_fire_o,
    output logic debug_alu_alu_dual_issue_o,
    output logic debug_alu_lsu_dual_issue_o,
    output logic debug_dual_issue_candidate_o,
    output logic debug_dual_issue_candidate_alu_alu_o,
    output logic debug_dual_issue_candidate_alu_lsu_o,
    output logic debug_dual_issue_candidate_lsu_alu_o,
    output logic debug_dual_issue_fire_alu_alu_o,
    output logic debug_dual_issue_fire_alu_lsu_o,
    output logic debug_dual_issue_fire_lsu_alu_o,
    output logic debug_alu0_issue_o,
    output logic debug_alu1_issue_o,
    output logic debug_alu0_busy_o,
    output logic debug_alu1_busy_o,
    output logic debug_alu0_done_o,
    output logic debug_alu1_done_o,
    output logic debug_alu0_alu1_done_same_cycle_o,
    output logic debug_alu0_alu1_wb_conflict_o,
    output logic debug_completion_grant_alu0_o,
    output logic debug_completion_grant_alu1_o,
    output logic debug_completion_hold_alu0_o,
    output logic debug_completion_hold_alu1_o,
    output logic debug_issue1_suppressed_o,
    output logic debug_issue1_suppressed_by_policy_o,
    output logic debug_issue1_suppressed_by_fu_busy_o,
    output logic debug_issue1_suppressed_by_wb_o,
    output logic debug_dual_issue_blocked_by_prf_o,
    output logic debug_dual_issue_blocked_by_alu_busy_o,
    output logic debug_dual_issue_blocked_by_alu0_busy_o,
    output logic debug_dual_issue_blocked_by_alu1_busy_o,
    output logic debug_dual_issue_blocked_by_lsu_busy_o,
    output logic debug_dual_issue_blocked_by_wb_o,
    output logic debug_dual_issue_blocked_by_completion_clear_o,
    output logic debug_dual_issue_blocked_by_serial_o,
    output logic debug_wb_conflict_alu0_alu1_o,
    output logic debug_wb_conflict_alu_lsu_o,
    output logic debug_wb_conflict_bru_data_o,
    output logic debug_alu1_single_issue_o,
    output logic debug_alu1_single_issue_when_alu0_busy_o,
    output logic debug_alu1_single_issue_when_alu0_idle_o,
    output logic debug_alu_single_issue_redirect_to_alu1_o,
    output logic debug_alu0_single_issue_o,
    output logic debug_alu0_single_issue_when_alu1_idle_o,
    output logic debug_alu_sched_balance_opportunity_o,
    output logic debug_alu_sched_balance_fire_o,
    output logic debug_alu_sched_balance_blocked_both_busy_o,
    output logic debug_alu_sched_balance_blocked_wb_o,
    output logic [1:0] debug_dispatch_width_mode_o,
    output logic debug_dispatch2_candidate_o,
    output logic debug_dispatch2_fire_o,
    output logic debug_dispatch2_slot0_fire_o,
    output logic debug_dispatch2_slot1_fire_o,
    output logic debug_dispatch2_slot1_retained_o,
    output logic debug_dispatch2_blocked_by_rob_o,
    output logic debug_dispatch2_blocked_by_iq_o,
    output logic debug_dispatch2_blocked_by_freelist_o,
    output logic debug_dispatch2_blocked_by_serial_o,
    output logic debug_dispatch2_blocked_by_unsupported_pair_o,
    output logic debug_dispatch2_partial_slot0_only_o,
    output logic debug_dispatch2_slot1_retained_due_to_rob_o,
    output logic debug_dispatch2_slot1_retained_due_to_iq_o,
    output logic debug_dispatch2_slot1_retained_due_to_freelist_o,
    output logic debug_dispatch2_slot1_retained_due_to_serial_o,
    output logic debug_dispatch2_retained_replayed_as_slot0_o,
    output logic debug_dispatch2_retained_duplicate_rename_bug_o,
    output logic debug_dispatch2_retained_duplicate_phys_bug_o,
    output logic debug_dispatch2_retained_duplicate_rob_bug_o,
    output logic debug_dispatch2_retained_flush_clear_o,
    output logic debug_rename2_fire_o,
    output logic debug_rename2_same_cycle_raw_o,
    output logic debug_rename2_same_cycle_waw_o,
    output logic debug_rob_alloc2_o,
    output logic debug_iq_enqueue2_o,
    output logic debug_freelist_alloc2_o,
    output logic debug_freelist_alloc1_due_to_partial_o,
    output logic debug_rob_alloc1_due_to_partial_o,
    output logic debug_iq_enqueue1_due_to_partial_o,
    output logic debug_if2_bundle_valid_o,
    output logic debug_if2_downstream_accept2_o,
    output logic debug_if2_downstream_accept1_o,
    output logic debug_if2_downstream_stall_o,
    output logic debug_if2_slot1_retained_o,
    output logic debug_if2_slot1_replayed_as_slot0_o,
    output logic debug_if2_redirect_flush_o,
    output logic debug_if2_stale_slot_kill_o,
    output logic debug_if2pair_req_o,
    output logic debug_if2pair_resp_o,
    output logic debug_if2pair_resp_drop_o,
    output logic debug_if2pair_stale_resp_kill_o,
    output logic debug_if2pair_valid_mask_11_o,
    output logic debug_if2pair_valid_mask_01_o,
    output logic debug_if2pair_upper_half_single_o,
    output logic debug_if2pair_downstream_accept2_o,
    output logic debug_if2pair_downstream_accept1_o,
    output logic debug_if2pair_downstream_stall_o,
    output logic debug_if2pair_slot1_retained_o,
    output logic debug_if2pair_slot1_replayed_as_slot0_o,
    output logic debug_if2pair_redirect_flush_o,
    output logic debug_if2pair_slot1_only_bug_o,
    output logic debug_if2pair_stale_accept_bug_o,
    output logic debug_if2pair_fetch_endian_bug_o,
    output logic debug_if2pair_duplicate_replay_bug_o,
    output logic debug_duplicate_issue_guard_o,
    output logic [1:0] debug_commit_width_mode_o,
    output logic debug_commit2_candidate_o,
    output logic debug_commit2_fire_o,
    output logic debug_commit2_slot0_only_o,
    output logic debug_commit2_block_slot0_not_ready_o,
    output logic debug_commit2_block_slot1_not_ready_o,
    output logic debug_commit2_block_slot0_complex_o,
    output logic debug_commit2_block_slot1_complex_o,
    output logic debug_commit2_rrat_update2_o,
    output logic debug_commit2_freelist_release2_o,
    output logic debug_commit2_same_rd_waw_o,
    output logic debug_commit2_duplicate_release_bug_o,
    output logic debug_commit2_slot1_without_slot0_bug_o,
    output logic debug_commit2_complex_slot_bug_o,
    output logic debug_commit2_trace_slot1_o,
    output logic debug_commit2_difftest_step2_o
);
    logic reset;
    logic feeder_valid;
    logic [31:0] feeder_pc;
    logic [31:0] feeder_instr;
    logic feeder1_valid;
    logic [31:0] feeder1_pc;
    logic [31:0] feeder1_instr;
    logic decode_supported;
    logic decode_unsupported;
    logic decode_deliverable;
    logic decode1_supported;
    logic decode1_unsupported;
    bbus_ooo_decode_uop_t decode_uop;
    bbus_ooo_decode_uop_t decode1_uop;
    logic dispatch_width2_mode;
    logic decode0_frontend_alu_like;
    logic decode0_backend_valid;
    logic decode1_backend_valid;
    logic feeder_consume;
    logic feeder_consume2;
    logic unsupported_seen_q;
    logic [31:0] unsupported_pc_q;
    logic [31:0] unsupported_instr_q;
    logic frontend_halt_seen_q;
    logic frontend_stop_c;

    logic backend_commit_enable;
    logic backend_commit_space;
    logic backend_commit_width2_mode;
    bbus_ooo_rob_tag_t backend_alloc_tag;
    bbus_ooo_writeback_t backend_alu_writeback;
    logic backend_writeback_accepted;
    bbus_ooo_phys_reg_t backend_rat_phys_debug;
    bbus_ooo_phys_reg_t backend_rrat_phys_debug;
    logic backend_ready_debug;
    logic [6:0] backend_free_count_debug;
    bbus_ooo_phys_reg_t backend_next_free_debug;
    logic [`BBUS_OOO_XLEN-1:0] backend_prf_data_debug;
    logic backend_rob_valid_debug;
    bbus_ooo_rob_idx_t backend_rob_head_debug;
    bbus_ooo_rob_idx_t backend_rob_tail_debug;
    logic [3:0] backend_iq_ready_count_debug;
    logic [3:0] backend_iq_ready_alu_count_debug;
    logic [3:0] backend_iq_ready_lsu_count_debug;
    logic [3:0] backend_iq_ready_bru_count_debug;
    logic [3:0] backend_iq_ready_csr_sys_count_debug;
    logic [3:0] backend_iq_ready_any_count_debug;
    logic [3:0] backend_issue_candidate_count_debug;
    logic backend_issue_multi_candidate_debug;
    logic backend_rob_full_debug;
    logic backend_iq_full_debug;
    logic backend_wb_buffer_full_debug;
    bbus_ooo_phys_reg_t backend_wb_buffer_phys_debug;
    logic [31:0] backend_wb_buffer_result_debug;
    logic backend_alu_busy_debug;
    logic backend_branch_busy_debug;
    logic backend_alu_completion_valid_debug;
    logic backend_lsu_busy_debug;
    logic backend_csr_busy_debug;
    logic backend_branch_completion_valid_debug;
    logic backend_lsu_completion_valid_debug;
    logic backend_csr_completion_valid_debug;
    logic backend_execution_path_clear_debug;
    logic backend_dispatch_valid_debug;
    logic backend_dispatch_ready_debug;
    logic backend_iq_enqueue_debug;
    logic backend_iq_issue_valid_debug;
    logic backend_iq_issue_ready_debug;
    logic backend_issue_fire_debug;
    logic backend_issue_fu_ready_debug;
    logic backend_wb_accept_debug;
    logic backend_wb_stall_debug;
    logic backend_alu_issue_debug;
    logic backend_branch_issue_debug;
    logic backend_lsu_issue_debug;
    logic backend_csr_issue_debug;
    logic backend_wb_conflict_debug;
    logic backend_completion_grant_alu_debug;
    logic backend_completion_grant_bru_debug;
    logic backend_completion_grant_lsu_debug;
    logic backend_completion_grant_csr_debug;
    logic backend_completion_hold_alu_debug;
    logic backend_completion_hold_bru_debug;
    logic backend_completion_hold_lsu_debug;
    logic backend_completion_hold_csr_debug;
    logic backend_completion_oldest_arb_debug;
    logic backend_completion_fixed_arb_debug;
    logic backend_completion_oldest_grant_alu_debug;
    logic backend_completion_oldest_grant_bru_debug;
    logic backend_completion_oldest_grant_lsu_debug;
    logic backend_completion_oldest_grant_csr_debug;
    logic backend_completion_fixed_would_choose_alu_debug;
    logic backend_completion_fixed_would_choose_bru_debug;
    logic backend_completion_fixed_would_choose_lsu_debug;
    logic backend_completion_fixed_would_choose_csr_debug;
    logic backend_completion_oldest_differs_from_fixed_debug;
    logic backend_duplicate_completion_tag_debug;
    logic backend_completion_arb_no_valid_bug_debug;
    logic backend_issue0_fire_debug;
    logic backend_issue1_fire_debug;
    logic backend_issue2_fire_debug;
    logic backend_alu_alu_dual_issue_debug;
    logic backend_alu_lsu_dual_issue_debug;
    logic backend_dual_issue_candidate_debug;
    logic backend_dual_issue_candidate_alu_alu_debug;
    logic backend_dual_issue_candidate_alu_lsu_debug;
    logic backend_dual_issue_candidate_lsu_alu_debug;
    logic backend_dual_issue_fire_alu_alu_debug;
    logic backend_dual_issue_fire_alu_lsu_debug;
    logic backend_dual_issue_fire_lsu_alu_debug;
    logic backend_alu0_issue_debug;
    logic backend_alu1_issue_debug;
    logic backend_alu0_busy_debug;
    logic backend_alu1_busy_debug;
    logic backend_alu0_done_debug;
    logic backend_alu1_done_debug;
    logic backend_alu0_alu1_done_same_cycle_debug;
    logic backend_alu0_alu1_wb_conflict_debug;
    logic backend_completion_grant_alu0_debug;
    logic backend_completion_grant_alu1_debug;
    logic backend_completion_hold_alu0_debug;
    logic backend_completion_hold_alu1_debug;
    logic backend_issue1_suppressed_debug;
    logic backend_issue1_suppressed_by_policy_debug;
    logic backend_issue1_suppressed_by_fu_busy_debug;
    logic backend_issue1_suppressed_by_wb_debug;
    logic backend_dual_issue_blocked_by_prf_debug;
    logic backend_dual_issue_blocked_by_alu_busy_debug;
    logic backend_dual_issue_blocked_by_alu0_busy_debug;
    logic backend_dual_issue_blocked_by_alu1_busy_debug;
    logic backend_dual_issue_blocked_by_lsu_busy_debug;
    logic backend_dual_issue_blocked_by_wb_debug;
    logic backend_dual_issue_blocked_by_completion_clear_debug;
    logic backend_dual_issue_blocked_by_serial_debug;
    logic backend_wb_conflict_alu0_alu1_debug;
    logic backend_wb_conflict_alu_lsu_debug;
    logic backend_wb_conflict_bru_data_debug;
    logic backend_alu1_single_issue_debug;
    logic backend_alu1_single_issue_when_alu0_busy_debug;
    logic backend_alu1_single_issue_when_alu0_idle_debug;
    logic backend_alu_single_issue_redirect_to_alu1_debug;
    logic backend_alu0_single_issue_debug;
    logic backend_alu0_single_issue_when_alu1_idle_debug;
    logic backend_alu_sched_balance_opportunity_debug;
    logic backend_alu_sched_balance_fire_debug;
    logic backend_alu_sched_balance_blocked_both_busy_debug;
    logic backend_alu_sched_balance_blocked_wb_debug;
    logic [1:0] backend_dispatch_width_mode_debug;
    logic backend_rename1_fire_debug;
    logic backend_dispatch2_candidate_debug;
    logic backend_dispatch2_fire_debug;
    logic backend_dispatch2_slot0_fire_debug;
    logic backend_dispatch2_slot1_fire_debug;
    logic backend_dispatch2_slot1_retained_debug;
    logic backend_dispatch2_blocked_by_rob_debug;
    logic backend_dispatch2_blocked_by_iq_debug;
    logic backend_dispatch2_blocked_by_freelist_debug;
    logic backend_dispatch2_blocked_by_serial_debug;
    logic backend_dispatch2_blocked_by_unsupported_pair_debug;
    logic backend_dispatch2_partial_slot0_only_debug;
    logic backend_dispatch2_slot1_retained_due_to_rob_debug;
    logic backend_dispatch2_slot1_retained_due_to_iq_debug;
    logic backend_dispatch2_slot1_retained_due_to_freelist_debug;
    logic backend_dispatch2_slot1_retained_due_to_serial_debug;
    logic backend_dispatch2_retained_replayed_as_slot0_debug;
    logic backend_dispatch2_retained_duplicate_rename_bug_debug;
    logic backend_dispatch2_retained_duplicate_phys_bug_debug;
    logic backend_dispatch2_retained_duplicate_rob_bug_debug;
    logic backend_dispatch2_retained_flush_clear_debug;
    logic backend_rename2_fire_debug;
    logic backend_rename2_same_cycle_raw_debug;
    logic backend_rename2_same_cycle_waw_debug;
    logic backend_rob_alloc2_debug;
    logic backend_iq_enqueue2_debug;
    logic backend_freelist_alloc2_debug;
    logic backend_freelist_alloc1_due_to_partial_debug;
    logic backend_rob_alloc1_due_to_partial_debug;
    logic backend_iq_enqueue1_due_to_partial_debug;
    logic backend_duplicate_issue_guard_debug;
    logic [1:0] backend_commit_width_mode_debug;
    logic backend_commit2_candidate_debug;
    logic backend_commit2_fire_debug;
    logic backend_commit2_slot0_only_debug;
    logic backend_commit2_block_slot0_not_ready_debug;
    logic backend_commit2_block_slot1_not_ready_debug;
    logic backend_commit2_block_slot0_complex_debug;
    logic backend_commit2_block_slot1_complex_debug;
    logic backend_commit2_rrat_update2_debug;
    logic backend_commit2_freelist_release2_debug;
    logic backend_commit2_same_rd_waw_debug;
    logic backend_commit2_duplicate_release_bug_debug;
    logic backend_commit2_slot1_without_slot0_bug_debug;
    logic backend_commit2_complex_slot_bug_debug;
    logic trace_can_accept1;
    logic trace_can_accept2;
    logic trace_commit2_slot1_debug;
    logic if2_frontend_mode;
    logic if2_pair_frontend_mode;
    logic if2_bundle_valid_c;
    logic if2_downstream_accept2_c;
    logic if2_downstream_accept1_c;
    logic if2_downstream_stall_c;
    logic if2_slot1_retained_c;
    logic if2_slot1_replayed_as_slot0_c;
    logic if2_redirect_flush_c;
    logic if2_stale_slot_kill_c;
    logic if2_slot1_replay_pending_q;
    logic [31:0] if2_slot1_replay_pc_q;
    logic [31:0] if2_slot1_replay_instr_q;
    logic if2_slots_visible_q;
    logic trace_accept_normal;
    logic trace_accept_rf_wen;

    function automatic logic frontend_decode_is_alu_like(input bbus_ooo_decode_uop_t uop);
        begin
            frontend_decode_is_alu_like =
                uop.valid &&
                !uop.is_load &&
                !uop.is_store &&
                !uop.is_csr &&
                !uop.is_system &&
                !uop.is_ebreak &&
                !uop.unsupported_class &&
                !uop.exception.valid &&
                ((uop.fu_type == BBUS_OOO_FU_ALU) ||
                 (uop.fu_type == BBUS_OOO_FU_NONE));
        end
    endfunction

    assign reset = !rst_n;
    assign dispatch_width2_mode = (`NPC_OOO_DISPATCH_WIDTH >= 2);
    assign backend_commit_width2_mode = (`NPC_OOO_COMMIT_WIDTH >= 2);
`ifdef NPC_OOO_FRONTEND_IF2_PAIR
    assign if2_frontend_mode = 1'b1;
    assign if2_pair_frontend_mode = 1'b1;
`elsif defined(NPC_OOO_FRONTEND_IF2_MIN)
    assign if2_frontend_mode = 1'b1;
    assign if2_pair_frontend_mode = 1'b0;
`else
    assign if2_frontend_mode = 1'b0;
    assign if2_pair_frontend_mode = 1'b0;
`endif
    assign decode0_frontend_alu_like = frontend_decode_is_alu_like(decode_uop);
    assign decode_deliverable = decode_supported || decode_uop.exception.valid;
    assign decode0_backend_valid =
        feeder_valid &&
        decode_deliverable &&
        !unsupported_seen_q &&
        (!dispatch_width2_mode ||
         feeder1_valid ||
         if2_pair_frontend_mode ||
         !decode0_frontend_alu_like);
    assign decode1_backend_valid =
        decode0_backend_valid &&
        feeder1_valid &&
        decode1_supported;
    assign backend_commit_space =
        backend_commit_width2_mode ? trace_can_accept2 : trace_can_accept1;
    assign backend_commit_enable =
        debug_commit_enable_i &&
        backend_commit_space &&
        !unsupported_seen_q &&
        !frontend_halt_seen_q;
    assign frontend_stop_c =
        unsupported_seen_q ||
        frontend_halt_seen_q ||
        control_pending_o ||
        memory_pending_o;
    assign debug_dispatch_candidate_o =
        decode0_backend_valid;
    assign feeder_consume =
        feeder_valid && decode_deliverable && debug_rename_fire_o;
    assign feeder_consume2 =
        feeder_valid &&
        feeder1_valid &&
        decode_deliverable &&
        decode1_supported &&
        debug_rename_fire_o &&
        backend_rename1_fire_debug;
    assign if2_bundle_valid_c = if2_frontend_mode && feeder_valid && feeder1_valid;
    assign if2_downstream_accept2_c = if2_frontend_mode && feeder_consume2;
    assign if2_downstream_accept1_c =
        if2_frontend_mode && feeder_consume && !feeder_consume2;
    assign if2_downstream_stall_c =
        if2_frontend_mode &&
        feeder_valid &&
        !feeder_consume &&
        !commit_redirect_valid_o &&
        !unsupported_seen_q;
    assign if2_slot1_retained_c =
        if2_frontend_mode &&
        feeder_consume &&
        !feeder_consume2 &&
        feeder1_valid;
    assign if2_slot1_replayed_as_slot0_c =
        if2_frontend_mode &&
        if2_slot1_replay_pending_q &&
        feeder_valid &&
        (feeder_pc == if2_slot1_replay_pc_q) &&
        (feeder_instr == if2_slot1_replay_instr_q);
    assign if2_redirect_flush_c = if2_frontend_mode && commit_redirect_valid_o;
    assign if2_stale_slot_kill_c =
        if2_redirect_flush_c &&
        if2_slots_visible_q;

`ifdef NPC_OOO_FRONTEND_IF2_PAIR
    ooo_pmem_ifetch_pair #(
        .RESET_VECTOR(RESET_VECTOR),
        .DPI_CHANNEL(0)
    ) u_if2_pair_fetcher (
        .clk(clk),
        .reset(reset),
        .fetch_valid_o(feeder_valid),
        .fetch_pc_o(feeder_pc),
        .fetch_instr_o(feeder_instr),
        .fetch1_valid_o(feeder1_valid),
        .fetch1_pc_o(feeder1_pc),
        .fetch1_instr_o(feeder1_instr),
        .consume_i(feeder_consume),
        .consume2_i(feeder_consume2),
        .stop_i(frontend_stop_c),
        .redirect_valid_i(commit_redirect_valid_o),
        .redirect_pc_i(commit_redirect_pc_o),
        .debug_req_valid_o(debug_if2pair_req_o),
        .debug_resp_valid_o(debug_if2pair_resp_o),
        .debug_resp_drop_o(debug_if2pair_resp_drop_o),
        .debug_stale_resp_kill_o(debug_if2pair_stale_resp_kill_o),
        .debug_valid_mask_11_o(debug_if2pair_valid_mask_11_o),
        .debug_valid_mask_01_o(debug_if2pair_valid_mask_01_o),
        .debug_upper_half_single_o(debug_if2pair_upper_half_single_o),
        .debug_slot1_only_bug_o(debug_if2pair_slot1_only_bug_o),
        .debug_stale_accept_bug_o(debug_if2pair_stale_accept_bug_o),
        .debug_fetch_endian_bug_o(debug_if2pair_fetch_endian_bug_o)
    );
    assign program_ready_o = 1'b0;
`else
    ooo_tiny_instr_feeder u_feeder (
        .clk(clk),
        .reset(reset),
        .program_valid_i(program_valid_i),
        .program_pc_i(program_pc_i),
        .program_instr_i(program_instr_i),
        .program_ready_o(program_ready_o),
        .consume_i(feeder_consume),
        .consume2_i(feeder_consume2),
        .stop_i(frontend_stop_c),
        .flush_i(commit_redirect_valid_o),
        .fetch_valid_o(feeder_valid),
        .fetch_pc_o(feeder_pc),
        .fetch_instr_o(feeder_instr),
        .fetch1_valid_o(feeder1_valid),
        .fetch1_pc_o(feeder1_pc),
        .fetch1_instr_o(feeder1_instr)
    );
    assign debug_if2pair_req_o = 1'b0;
    assign debug_if2pair_resp_o = 1'b0;
    assign debug_if2pair_resp_drop_o = 1'b0;
    assign debug_if2pair_stale_resp_kill_o = 1'b0;
    assign debug_if2pair_valid_mask_11_o = 1'b0;
    assign debug_if2pair_valid_mask_01_o = 1'b0;
    assign debug_if2pair_upper_half_single_o = 1'b0;
    assign debug_if2pair_slot1_only_bug_o = 1'b0;
    assign debug_if2pair_stale_accept_bug_o = 1'b0;
    assign debug_if2pair_fetch_endian_bug_o = 1'b0;
`endif

    ooo_rv32i_alu_decode_adapter u_decode_adapter (
        .valid_i(feeder_valid),
        .pc_i(feeder_pc),
        .instr_i(feeder_instr),
        .supported_o(decode_supported),
        .unsupported_o(decode_unsupported),
        .decode_uop_o(decode_uop)
    );

    ooo_rv32i_alu_decode_adapter u_decode1_adapter (
        .valid_i(feeder1_valid),
        .pc_i(feeder1_pc),
        .instr_i(feeder1_instr),
        .supported_o(decode1_supported),
        .unsupported_o(decode1_unsupported),
        .decode_uop_o(decode1_uop)
    );

    ooo_s2_alu1_standalone_top #(
        .ALU_LATENCY(ALU_LATENCY),
        .ALU1_LATENCY(ALU1_LATENCY)
    ) u_backend (
        .clk(clk),
        .reset(reset),
        .decode_valid_i(decode0_backend_valid),
        .decode_uop_i(decode_uop),
        .decode1_valid_i(decode1_backend_valid),
        .decode1_uop_i(decode1_uop),
        .commit_enable_i(backend_commit_enable),
        .debug_alu_issue_enable_i(1'b1),
        .debug_wakeup_enable_i(1'b1),
        .debug_wb_accept_enable_i(1'b1),
        .debug_arch_idx_i(debug_arch_idx_i),
        .debug_phys_idx_i(debug_phys_idx_i),
        .debug_prf_phys_idx_i(debug_prf_phys_idx_i),
        .debug_rob_idx_i(debug_rob_idx_i),
        .rename_fire_o(debug_rename_fire_o),
        .rename1_fire_o(backend_rename1_fire_debug),
        .renamed_uop_o(debug_renamed_uop_o),
        .alloc_tag_o(backend_alloc_tag),
        .alu_writeback_o(backend_alu_writeback),
        .writeback_accepted_o(backend_writeback_accepted),
        .commit_event_o(debug_commit_event_o),
        .control_pending_o(control_pending_o),
        .memory_pending_o(memory_pending_o),
        .commit_redirect_valid_o(commit_redirect_valid_o),
        .commit_redirect_pc_o(commit_redirect_pc_o),
        .debug_rat_phys_o(backend_rat_phys_debug),
        .debug_rrat_phys_o(backend_rrat_phys_debug),
        .debug_ready_o(backend_ready_debug),
        .debug_free_count_o(backend_free_count_debug),
        .debug_next_free_phys_o(backend_next_free_debug),
        .debug_prf_data_o(backend_prf_data_debug),
        .debug_rob_valid_o(backend_rob_valid_debug),
        .debug_rob_done_o(debug_rob_done_o),
        .debug_rob_result_o(debug_rob_result_o),
        .debug_rob_count_o(debug_rob_count_o),
        .debug_rob_head_o(backend_rob_head_debug),
        .debug_rob_tail_o(backend_rob_tail_debug),
        .debug_iq_count_o(debug_iq_count_o),
        .debug_iq_ready_count_o(backend_iq_ready_count_debug),
        .debug_iq_ready_alu_count_o(backend_iq_ready_alu_count_debug),
        .debug_iq_ready_lsu_count_o(backend_iq_ready_lsu_count_debug),
        .debug_iq_ready_bru_count_o(backend_iq_ready_bru_count_debug),
        .debug_iq_ready_csr_sys_count_o(backend_iq_ready_csr_sys_count_debug),
        .debug_iq_ready_any_count_o(backend_iq_ready_any_count_debug),
        .debug_issue_candidate_count_o(backend_issue_candidate_count_debug),
        .debug_issue_multi_candidate_o(backend_issue_multi_candidate_debug),
        .debug_rob_full_o(backend_rob_full_debug),
        .debug_iq_full_o(backend_iq_full_debug),
        .debug_wb_buffer_full_o(backend_wb_buffer_full_debug),
        .debug_wb_buffer_valid_o(debug_wb_buffer_valid_o),
        .debug_wb_buffer_phys_o(backend_wb_buffer_phys_debug),
        .debug_wb_buffer_result_o(backend_wb_buffer_result_debug),
        .debug_alu_busy_o(backend_alu_busy_debug),
        .debug_alu_completion_valid_o(backend_alu_completion_valid_debug),
        .debug_lsu_busy_o(backend_lsu_busy_debug),
        .debug_lsu_completion_valid_o(backend_lsu_completion_valid_debug),
        .debug_branch_busy_o(backend_branch_busy_debug),
        .debug_branch_completion_valid_o(backend_branch_completion_valid_debug),
        .debug_csr_busy_o(backend_csr_busy_debug),
        .debug_csr_completion_valid_o(backend_csr_completion_valid_debug),
        .debug_execution_path_clear_o(backend_execution_path_clear_debug),
        .debug_dispatch_valid_o(backend_dispatch_valid_debug),
        .debug_dispatch_ready_o(backend_dispatch_ready_debug),
        .debug_dispatch_fire_o(),
        .debug_iq_enqueue_o(backend_iq_enqueue_debug),
        .debug_iq_issue_valid_o(backend_iq_issue_valid_debug),
        .debug_iq_issue_ready_o(backend_iq_issue_ready_debug),
        .debug_issue_fire_o(backend_issue_fire_debug),
        .debug_issue_fu_ready_o(backend_issue_fu_ready_debug),
        .debug_wb_accept_o(backend_wb_accept_debug),
        .debug_wb_stall_o(backend_wb_stall_debug),
        .debug_alu_issue_o(backend_alu_issue_debug),
        .debug_branch_issue_o(backend_branch_issue_debug),
        .debug_lsu_issue_o(backend_lsu_issue_debug),
        .debug_csr_issue_o(backend_csr_issue_debug),
        .debug_wb_conflict_o(backend_wb_conflict_debug),
        .debug_completion_grant_alu_o(backend_completion_grant_alu_debug),
        .debug_completion_grant_bru_o(backend_completion_grant_bru_debug),
        .debug_completion_grant_lsu_o(backend_completion_grant_lsu_debug),
        .debug_completion_grant_csr_o(backend_completion_grant_csr_debug),
        .debug_completion_hold_alu_o(backend_completion_hold_alu_debug),
        .debug_completion_hold_bru_o(backend_completion_hold_bru_debug),
        .debug_completion_hold_lsu_o(backend_completion_hold_lsu_debug),
        .debug_completion_hold_csr_o(backend_completion_hold_csr_debug),
        .debug_completion_oldest_arb_o(backend_completion_oldest_arb_debug),
        .debug_completion_fixed_arb_o(backend_completion_fixed_arb_debug),
        .debug_completion_oldest_grant_alu_o(backend_completion_oldest_grant_alu_debug),
        .debug_completion_oldest_grant_bru_o(backend_completion_oldest_grant_bru_debug),
        .debug_completion_oldest_grant_lsu_o(backend_completion_oldest_grant_lsu_debug),
        .debug_completion_oldest_grant_csr_o(backend_completion_oldest_grant_csr_debug),
        .debug_completion_fixed_would_choose_alu_o(backend_completion_fixed_would_choose_alu_debug),
        .debug_completion_fixed_would_choose_bru_o(backend_completion_fixed_would_choose_bru_debug),
        .debug_completion_fixed_would_choose_lsu_o(backend_completion_fixed_would_choose_lsu_debug),
        .debug_completion_fixed_would_choose_csr_o(backend_completion_fixed_would_choose_csr_debug),
        .debug_completion_oldest_differs_from_fixed_o(backend_completion_oldest_differs_from_fixed_debug),
        .debug_duplicate_completion_tag_o(backend_duplicate_completion_tag_debug),
        .debug_completion_arb_no_valid_bug_o(backend_completion_arb_no_valid_bug_debug),
        .debug_issue0_fire_o(backend_issue0_fire_debug),
        .debug_issue1_fire_o(backend_issue1_fire_debug),
        .debug_issue2_fire_o(backend_issue2_fire_debug),
        .debug_alu_alu_dual_issue_o(backend_alu_alu_dual_issue_debug),
        .debug_alu_lsu_dual_issue_o(backend_alu_lsu_dual_issue_debug),
        .debug_dual_issue_candidate_o(backend_dual_issue_candidate_debug),
        .debug_dual_issue_candidate_alu_alu_o(backend_dual_issue_candidate_alu_alu_debug),
        .debug_dual_issue_candidate_alu_lsu_o(backend_dual_issue_candidate_alu_lsu_debug),
        .debug_dual_issue_candidate_lsu_alu_o(backend_dual_issue_candidate_lsu_alu_debug),
        .debug_dual_issue_fire_alu_alu_o(backend_dual_issue_fire_alu_alu_debug),
        .debug_dual_issue_fire_alu_lsu_o(backend_dual_issue_fire_alu_lsu_debug),
        .debug_dual_issue_fire_lsu_alu_o(backend_dual_issue_fire_lsu_alu_debug),
        .debug_alu0_issue_o(backend_alu0_issue_debug),
        .debug_alu1_issue_o(backend_alu1_issue_debug),
        .debug_alu0_busy_o(backend_alu0_busy_debug),
        .debug_alu1_busy_o(backend_alu1_busy_debug),
        .debug_alu0_done_o(backend_alu0_done_debug),
        .debug_alu1_done_o(backend_alu1_done_debug),
        .debug_alu0_alu1_done_same_cycle_o(backend_alu0_alu1_done_same_cycle_debug),
        .debug_alu0_alu1_wb_conflict_o(backend_alu0_alu1_wb_conflict_debug),
        .debug_completion_grant_alu0_o(backend_completion_grant_alu0_debug),
        .debug_completion_grant_alu1_o(backend_completion_grant_alu1_debug),
        .debug_completion_hold_alu0_o(backend_completion_hold_alu0_debug),
        .debug_completion_hold_alu1_o(backend_completion_hold_alu1_debug),
        .debug_issue1_suppressed_o(backend_issue1_suppressed_debug),
        .debug_issue1_suppressed_by_policy_o(backend_issue1_suppressed_by_policy_debug),
        .debug_issue1_suppressed_by_fu_busy_o(backend_issue1_suppressed_by_fu_busy_debug),
        .debug_issue1_suppressed_by_wb_o(backend_issue1_suppressed_by_wb_debug),
        .debug_dual_issue_blocked_by_prf_o(backend_dual_issue_blocked_by_prf_debug),
        .debug_dual_issue_blocked_by_alu_busy_o(backend_dual_issue_blocked_by_alu_busy_debug),
        .debug_dual_issue_blocked_by_alu0_busy_o(backend_dual_issue_blocked_by_alu0_busy_debug),
        .debug_dual_issue_blocked_by_alu1_busy_o(backend_dual_issue_blocked_by_alu1_busy_debug),
        .debug_dual_issue_blocked_by_lsu_busy_o(backend_dual_issue_blocked_by_lsu_busy_debug),
        .debug_dual_issue_blocked_by_wb_o(backend_dual_issue_blocked_by_wb_debug),
        .debug_dual_issue_blocked_by_completion_clear_o(backend_dual_issue_blocked_by_completion_clear_debug),
        .debug_dual_issue_blocked_by_serial_o(backend_dual_issue_blocked_by_serial_debug),
        .debug_wb_conflict_alu0_alu1_o(backend_wb_conflict_alu0_alu1_debug),
        .debug_wb_conflict_alu_lsu_o(backend_wb_conflict_alu_lsu_debug),
        .debug_wb_conflict_bru_data_o(backend_wb_conflict_bru_data_debug),
        .debug_alu1_single_issue_o(backend_alu1_single_issue_debug),
        .debug_alu1_single_issue_when_alu0_busy_o(backend_alu1_single_issue_when_alu0_busy_debug),
        .debug_alu1_single_issue_when_alu0_idle_o(backend_alu1_single_issue_when_alu0_idle_debug),
        .debug_alu_single_issue_redirect_to_alu1_o(backend_alu_single_issue_redirect_to_alu1_debug),
        .debug_alu0_single_issue_o(backend_alu0_single_issue_debug),
        .debug_alu0_single_issue_when_alu1_idle_o(backend_alu0_single_issue_when_alu1_idle_debug),
        .debug_alu_sched_balance_opportunity_o(backend_alu_sched_balance_opportunity_debug),
        .debug_alu_sched_balance_fire_o(backend_alu_sched_balance_fire_debug),
        .debug_alu_sched_balance_blocked_both_busy_o(backend_alu_sched_balance_blocked_both_busy_debug),
        .debug_alu_sched_balance_blocked_wb_o(backend_alu_sched_balance_blocked_wb_debug),
        .debug_dispatch_width_mode_o(backend_dispatch_width_mode_debug),
        .debug_dispatch2_candidate_o(backend_dispatch2_candidate_debug),
        .debug_dispatch2_fire_o(backend_dispatch2_fire_debug),
        .debug_dispatch2_slot0_fire_o(backend_dispatch2_slot0_fire_debug),
        .debug_dispatch2_slot1_fire_o(backend_dispatch2_slot1_fire_debug),
        .debug_dispatch2_slot1_retained_o(backend_dispatch2_slot1_retained_debug),
        .debug_dispatch2_blocked_by_rob_o(backend_dispatch2_blocked_by_rob_debug),
        .debug_dispatch2_blocked_by_iq_o(backend_dispatch2_blocked_by_iq_debug),
        .debug_dispatch2_blocked_by_freelist_o(backend_dispatch2_blocked_by_freelist_debug),
        .debug_dispatch2_blocked_by_serial_o(backend_dispatch2_blocked_by_serial_debug),
        .debug_dispatch2_blocked_by_unsupported_pair_o(backend_dispatch2_blocked_by_unsupported_pair_debug),
        .debug_dispatch2_partial_slot0_only_o(backend_dispatch2_partial_slot0_only_debug),
        .debug_dispatch2_slot1_retained_due_to_rob_o(backend_dispatch2_slot1_retained_due_to_rob_debug),
        .debug_dispatch2_slot1_retained_due_to_iq_o(backend_dispatch2_slot1_retained_due_to_iq_debug),
        .debug_dispatch2_slot1_retained_due_to_freelist_o(backend_dispatch2_slot1_retained_due_to_freelist_debug),
        .debug_dispatch2_slot1_retained_due_to_serial_o(backend_dispatch2_slot1_retained_due_to_serial_debug),
        .debug_dispatch2_retained_replayed_as_slot0_o(backend_dispatch2_retained_replayed_as_slot0_debug),
        .debug_dispatch2_retained_duplicate_rename_bug_o(backend_dispatch2_retained_duplicate_rename_bug_debug),
        .debug_dispatch2_retained_duplicate_phys_bug_o(backend_dispatch2_retained_duplicate_phys_bug_debug),
        .debug_dispatch2_retained_duplicate_rob_bug_o(backend_dispatch2_retained_duplicate_rob_bug_debug),
        .debug_dispatch2_retained_flush_clear_o(backend_dispatch2_retained_flush_clear_debug),
        .debug_rename2_fire_o(backend_rename2_fire_debug),
        .debug_rename2_same_cycle_raw_o(backend_rename2_same_cycle_raw_debug),
        .debug_rename2_same_cycle_waw_o(backend_rename2_same_cycle_waw_debug),
        .debug_rob_alloc2_o(backend_rob_alloc2_debug),
        .debug_iq_enqueue2_o(backend_iq_enqueue2_debug),
        .debug_freelist_alloc2_o(backend_freelist_alloc2_debug),
        .debug_freelist_alloc1_due_to_partial_o(backend_freelist_alloc1_due_to_partial_debug),
        .debug_rob_alloc1_due_to_partial_o(backend_rob_alloc1_due_to_partial_debug),
        .debug_iq_enqueue1_due_to_partial_o(backend_iq_enqueue1_due_to_partial_debug),
        .debug_duplicate_issue_guard_o(backend_duplicate_issue_guard_debug),
        .debug_commit_width_mode_o(backend_commit_width_mode_debug),
        .debug_commit2_candidate_o(backend_commit2_candidate_debug),
        .debug_commit2_fire_o(backend_commit2_fire_debug),
        .debug_commit2_slot0_only_o(backend_commit2_slot0_only_debug),
        .debug_commit2_block_slot0_not_ready_o(backend_commit2_block_slot0_not_ready_debug),
        .debug_commit2_block_slot1_not_ready_o(backend_commit2_block_slot1_not_ready_debug),
        .debug_commit2_block_slot0_complex_o(backend_commit2_block_slot0_complex_debug),
        .debug_commit2_block_slot1_complex_o(backend_commit2_block_slot1_complex_debug),
        .debug_commit2_rrat_update2_o(backend_commit2_rrat_update2_debug),
        .debug_commit2_freelist_release2_o(backend_commit2_freelist_release2_debug),
        .debug_commit2_same_rd_waw_o(backend_commit2_same_rd_waw_debug),
        .debug_commit2_duplicate_release_bug_o(backend_commit2_duplicate_release_bug_debug),
        .debug_commit2_slot1_without_slot0_bug_o(backend_commit2_slot1_without_slot0_bug_debug),
        .debug_commit2_complex_slot_bug_o(backend_commit2_complex_slot_bug_debug),
        .debug_dual_wb_enabled_o(),
        .debug_dual_wb_raw_fire_o(),
        .debug_dual_wb_final_fire_o(),
        .debug_dual_wb_lane1_hold_o(),
        .debug_dual_wb_lane1_replay_o(),
        .debug_dual_wb_duplicate_phys_hold_o(),
        .debug_dual_wb_duplicate_rob_tag_hold_o(),
        .debug_dual_wb_atomicity_guard_o()
    );

    ooo_commit_trace_adapter u_commit_trace_adapter (
        .clk(clk),
        .reset(reset),
        .commit_event_i(debug_commit_event_o),
        .exception_nextpc_valid_i(commit_redirect_valid_o),
        .exception_nextpc_i(commit_redirect_pc_o),
        .trace_can_accept1_o(trace_can_accept1),
        .trace_can_accept2_o(trace_can_accept2),
        .trace_valid_o(trace_valid_o),
        .trace_ready_i(trace_ready_i),
        .trace_packet_o(trace_packet_o),
        .debug_packet_buffer_valid_o(debug_packet_buffer_valid_o),
        .debug_last_packet_accepted_o(debug_last_packet_accepted_o),
        .debug_last_commit_dropped_o(debug_last_commit_dropped_o),
        .debug_commit2_trace_slot1_o(trace_commit2_slot1_debug)
    );

    ooo_npc_commit_trace_bridge u_trace_bridge (
        .clk(clk),
        .reset(reset),
        .trace_valid_i(trace_valid_o),
        .trace_ready_i(trace_ready_i),
        .trace_packet_i(trace_packet_o),
        .commit_valid_o(commit_valid_o),
        .commit_mask_o(commit_mask_o),
        .commit_slot1_o(commit_slot1_o),
        .commit_pc_o(commit_pc_o),
        .commit_instr_o(commit_instr_o),
        .commit_nextpc_o(commit_nextpc_o),
        .commit_rf_wen_o(commit_rf_wen_o),
        .commit_rd_o(commit_rd_o),
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
        .commit_exception_valid_o(commit_exception_valid_o)
    );

    assign trace_accept_normal =
        trace_valid_o &&
        trace_ready_i &&
        trace_packet_o.valid &&
        !trace_packet_o.unsupported;
    assign trace_accept_rf_wen =
        trace_accept_normal &&
        !trace_packet_o.exception_valid &&
        trace_packet_o.rf_wen &&
        (trace_packet_o.arch_rd != bbus_ooo_arch_reg_t'(5'd0));

    ooo_shadow_arch_state #(
        .RESET_VECTOR(RESET_VECTOR)
    ) u_shadow_arch_state (
        .clk(clk),
        .reset(reset),
        .commit_valid_i(trace_accept_normal),
        .commit_nextpc_i(trace_packet_o.commit_nextpc),
        .commit_rf_wen_i(trace_accept_rf_wen),
        .commit_rd_i(trace_packet_o.arch_rd),
        .commit_wdata_i(trace_packet_o.wdata),
        .debug_arch_idx_i(debug_arch_idx_i),
        .debug_arch_gpr_o(debug_arch_gpr_o),
        .debug_arch_pc_o(debug_arch_pc_o)
    );

    assign debug_shadow_idle_o =
        !feeder_valid &&
        (debug_rob_count_o == 4'd0) &&
        (debug_iq_count_o == 4'd0) &&
        !debug_wb_buffer_valid_o &&
        !trace_valid_o &&
        !debug_packet_buffer_valid_o &&
        !debug_last_packet_accepted_o &&
        !debug_last_commit_dropped_o &&
        !control_pending_o &&
        !memory_pending_o &&
        !unsupported_seen_q;
    assign debug_iq_ready_count_o = backend_iq_ready_count_debug;
    assign debug_iq_ready_alu_count_o = backend_iq_ready_alu_count_debug;
    assign debug_iq_ready_lsu_count_o = backend_iq_ready_lsu_count_debug;
    assign debug_iq_ready_bru_count_o = backend_iq_ready_bru_count_debug;
    assign debug_iq_ready_csr_sys_count_o = backend_iq_ready_csr_sys_count_debug;
    assign debug_iq_ready_any_count_o = backend_iq_ready_any_count_debug;
    assign debug_issue_candidate_count_o = backend_issue_candidate_count_debug;
    assign debug_issue_multi_candidate_o = backend_issue_multi_candidate_debug;
    assign debug_rob_full_o = backend_rob_full_debug;
    assign debug_iq_full_o = backend_iq_full_debug;
    assign debug_wb_buffer_full_o = backend_wb_buffer_full_debug;
    assign debug_alu_busy_o = backend_alu_busy_debug;
    assign debug_branch_busy_o = backend_branch_busy_debug;
    assign debug_lsu_busy_o = backend_lsu_busy_debug;
    assign debug_csr_busy_o = backend_csr_busy_debug;
    assign debug_alu_completion_valid_o = backend_alu_completion_valid_debug;
    assign debug_branch_completion_valid_o = backend_branch_completion_valid_debug;
    assign debug_lsu_completion_valid_o = backend_lsu_completion_valid_debug;
    assign debug_csr_completion_valid_o = backend_csr_completion_valid_debug;
    assign debug_execution_path_clear_o = backend_execution_path_clear_debug;
    assign debug_dispatch_valid_o = backend_dispatch_valid_debug;
    assign debug_dispatch_ready_o = backend_dispatch_ready_debug;
    assign debug_iq_enqueue_o = backend_iq_enqueue_debug;
    assign debug_iq_issue_valid_o = backend_iq_issue_valid_debug;
    assign debug_iq_issue_ready_o = backend_iq_issue_ready_debug;
    assign debug_issue_fire_o = backend_issue_fire_debug;
    assign debug_issue_fu_ready_o = backend_issue_fu_ready_debug;
    assign debug_wb_accept_o = backend_wb_accept_debug;
    assign debug_wb_stall_o = backend_wb_stall_debug;
    assign debug_alu_issue_o = backend_alu_issue_debug;
    assign debug_branch_issue_o = backend_branch_issue_debug;
    assign debug_lsu_issue_o = backend_lsu_issue_debug;
    assign debug_csr_issue_o = backend_csr_issue_debug;
    assign debug_wb_conflict_o = backend_wb_conflict_debug;
    assign debug_completion_grant_alu_o = backend_completion_grant_alu_debug;
    assign debug_completion_grant_bru_o = backend_completion_grant_bru_debug;
    assign debug_completion_grant_lsu_o = backend_completion_grant_lsu_debug;
    assign debug_completion_grant_csr_o = backend_completion_grant_csr_debug;
    assign debug_completion_hold_alu_o = backend_completion_hold_alu_debug;
    assign debug_completion_hold_bru_o = backend_completion_hold_bru_debug;
    assign debug_completion_hold_lsu_o = backend_completion_hold_lsu_debug;
    assign debug_completion_hold_csr_o = backend_completion_hold_csr_debug;
    assign debug_completion_oldest_arb_o = backend_completion_oldest_arb_debug;
    assign debug_completion_fixed_arb_o = backend_completion_fixed_arb_debug;
    assign debug_completion_oldest_grant_alu_o = backend_completion_oldest_grant_alu_debug;
    assign debug_completion_oldest_grant_bru_o = backend_completion_oldest_grant_bru_debug;
    assign debug_completion_oldest_grant_lsu_o = backend_completion_oldest_grant_lsu_debug;
    assign debug_completion_oldest_grant_csr_o = backend_completion_oldest_grant_csr_debug;
    assign debug_completion_fixed_would_choose_alu_o = backend_completion_fixed_would_choose_alu_debug;
    assign debug_completion_fixed_would_choose_bru_o = backend_completion_fixed_would_choose_bru_debug;
    assign debug_completion_fixed_would_choose_lsu_o = backend_completion_fixed_would_choose_lsu_debug;
    assign debug_completion_fixed_would_choose_csr_o = backend_completion_fixed_would_choose_csr_debug;
    assign debug_completion_oldest_differs_from_fixed_o =
        backend_completion_oldest_differs_from_fixed_debug;
    assign debug_duplicate_completion_tag_o = backend_duplicate_completion_tag_debug;
    assign debug_completion_arb_no_valid_bug_o = backend_completion_arb_no_valid_bug_debug;
    assign debug_issue0_fire_o = backend_issue0_fire_debug;
    assign debug_issue1_fire_o = backend_issue1_fire_debug;
    assign debug_issue2_fire_o = backend_issue2_fire_debug;
    assign debug_alu_alu_dual_issue_o = backend_alu_alu_dual_issue_debug;
    assign debug_alu_lsu_dual_issue_o = backend_alu_lsu_dual_issue_debug;
    assign debug_dual_issue_candidate_o = backend_dual_issue_candidate_debug;
    assign debug_dual_issue_candidate_alu_alu_o = backend_dual_issue_candidate_alu_alu_debug;
    assign debug_dual_issue_candidate_alu_lsu_o = backend_dual_issue_candidate_alu_lsu_debug;
    assign debug_dual_issue_candidate_lsu_alu_o = backend_dual_issue_candidate_lsu_alu_debug;
    assign debug_dual_issue_fire_alu_alu_o = backend_dual_issue_fire_alu_alu_debug;
    assign debug_dual_issue_fire_alu_lsu_o = backend_dual_issue_fire_alu_lsu_debug;
    assign debug_dual_issue_fire_lsu_alu_o = backend_dual_issue_fire_lsu_alu_debug;
    assign debug_alu0_issue_o = backend_alu0_issue_debug;
    assign debug_alu1_issue_o = backend_alu1_issue_debug;
    assign debug_alu0_busy_o = backend_alu0_busy_debug;
    assign debug_alu1_busy_o = backend_alu1_busy_debug;
    assign debug_alu0_done_o = backend_alu0_done_debug;
    assign debug_alu1_done_o = backend_alu1_done_debug;
    assign debug_alu0_alu1_done_same_cycle_o = backend_alu0_alu1_done_same_cycle_debug;
    assign debug_alu0_alu1_wb_conflict_o = backend_alu0_alu1_wb_conflict_debug;
    assign debug_completion_grant_alu0_o = backend_completion_grant_alu0_debug;
    assign debug_completion_grant_alu1_o = backend_completion_grant_alu1_debug;
    assign debug_completion_hold_alu0_o = backend_completion_hold_alu0_debug;
    assign debug_completion_hold_alu1_o = backend_completion_hold_alu1_debug;
    assign debug_issue1_suppressed_o = backend_issue1_suppressed_debug;
    assign debug_issue1_suppressed_by_policy_o = backend_issue1_suppressed_by_policy_debug;
    assign debug_issue1_suppressed_by_fu_busy_o = backend_issue1_suppressed_by_fu_busy_debug;
    assign debug_issue1_suppressed_by_wb_o = backend_issue1_suppressed_by_wb_debug;
    assign debug_dual_issue_blocked_by_prf_o = backend_dual_issue_blocked_by_prf_debug;
    assign debug_dual_issue_blocked_by_alu_busy_o = backend_dual_issue_blocked_by_alu_busy_debug;
    assign debug_dual_issue_blocked_by_alu0_busy_o = backend_dual_issue_blocked_by_alu0_busy_debug;
    assign debug_dual_issue_blocked_by_alu1_busy_o = backend_dual_issue_blocked_by_alu1_busy_debug;
    assign debug_dual_issue_blocked_by_lsu_busy_o = backend_dual_issue_blocked_by_lsu_busy_debug;
    assign debug_dual_issue_blocked_by_wb_o = backend_dual_issue_blocked_by_wb_debug;
    assign debug_dual_issue_blocked_by_completion_clear_o =
        backend_dual_issue_blocked_by_completion_clear_debug;
    assign debug_dual_issue_blocked_by_serial_o = backend_dual_issue_blocked_by_serial_debug;
    assign debug_wb_conflict_alu0_alu1_o = backend_wb_conflict_alu0_alu1_debug;
    assign debug_wb_conflict_alu_lsu_o = backend_wb_conflict_alu_lsu_debug;
    assign debug_wb_conflict_bru_data_o = backend_wb_conflict_bru_data_debug;
    assign debug_alu1_single_issue_o = backend_alu1_single_issue_debug;
    assign debug_alu1_single_issue_when_alu0_busy_o =
        backend_alu1_single_issue_when_alu0_busy_debug;
    assign debug_alu1_single_issue_when_alu0_idle_o =
        backend_alu1_single_issue_when_alu0_idle_debug;
    assign debug_alu_single_issue_redirect_to_alu1_o =
        backend_alu_single_issue_redirect_to_alu1_debug;
    assign debug_alu0_single_issue_o = backend_alu0_single_issue_debug;
    assign debug_alu0_single_issue_when_alu1_idle_o =
        backend_alu0_single_issue_when_alu1_idle_debug;
    assign debug_alu_sched_balance_opportunity_o =
        backend_alu_sched_balance_opportunity_debug;
    assign debug_alu_sched_balance_fire_o = backend_alu_sched_balance_fire_debug;
    assign debug_alu_sched_balance_blocked_both_busy_o =
        backend_alu_sched_balance_blocked_both_busy_debug;
    assign debug_alu_sched_balance_blocked_wb_o =
        backend_alu_sched_balance_blocked_wb_debug;
    assign debug_dispatch_width_mode_o = backend_dispatch_width_mode_debug;
    assign debug_dispatch2_candidate_o = backend_dispatch2_candidate_debug;
    assign debug_dispatch2_fire_o = backend_dispatch2_fire_debug;
    assign debug_dispatch2_slot0_fire_o = backend_dispatch2_slot0_fire_debug;
    assign debug_dispatch2_slot1_fire_o = backend_dispatch2_slot1_fire_debug;
    assign debug_dispatch2_slot1_retained_o = backend_dispatch2_slot1_retained_debug;
    assign debug_dispatch2_blocked_by_rob_o = backend_dispatch2_blocked_by_rob_debug;
    assign debug_dispatch2_blocked_by_iq_o = backend_dispatch2_blocked_by_iq_debug;
    assign debug_dispatch2_blocked_by_freelist_o =
        backend_dispatch2_blocked_by_freelist_debug;
    assign debug_dispatch2_blocked_by_serial_o = backend_dispatch2_blocked_by_serial_debug;
    assign debug_dispatch2_blocked_by_unsupported_pair_o =
        backend_dispatch2_blocked_by_unsupported_pair_debug;
    assign debug_dispatch2_partial_slot0_only_o =
        backend_dispatch2_partial_slot0_only_debug;
    assign debug_dispatch2_slot1_retained_due_to_rob_o =
        backend_dispatch2_slot1_retained_due_to_rob_debug;
    assign debug_dispatch2_slot1_retained_due_to_iq_o =
        backend_dispatch2_slot1_retained_due_to_iq_debug;
    assign debug_dispatch2_slot1_retained_due_to_freelist_o =
        backend_dispatch2_slot1_retained_due_to_freelist_debug;
    assign debug_dispatch2_slot1_retained_due_to_serial_o =
        backend_dispatch2_slot1_retained_due_to_serial_debug;
    assign debug_dispatch2_retained_replayed_as_slot0_o =
        backend_dispatch2_retained_replayed_as_slot0_debug;
    assign debug_dispatch2_retained_duplicate_rename_bug_o =
        backend_dispatch2_retained_duplicate_rename_bug_debug;
    assign debug_dispatch2_retained_duplicate_phys_bug_o =
        backend_dispatch2_retained_duplicate_phys_bug_debug;
    assign debug_dispatch2_retained_duplicate_rob_bug_o =
        backend_dispatch2_retained_duplicate_rob_bug_debug;
    assign debug_dispatch2_retained_flush_clear_o =
        backend_dispatch2_retained_flush_clear_debug;
    assign debug_rename2_fire_o = backend_rename2_fire_debug;
    assign debug_rename2_same_cycle_raw_o = backend_rename2_same_cycle_raw_debug;
    assign debug_rename2_same_cycle_waw_o = backend_rename2_same_cycle_waw_debug;
    assign debug_rob_alloc2_o = backend_rob_alloc2_debug;
    assign debug_iq_enqueue2_o = backend_iq_enqueue2_debug;
    assign debug_freelist_alloc2_o = backend_freelist_alloc2_debug;
    assign debug_freelist_alloc1_due_to_partial_o =
        backend_freelist_alloc1_due_to_partial_debug;
    assign debug_rob_alloc1_due_to_partial_o =
        backend_rob_alloc1_due_to_partial_debug;
    assign debug_iq_enqueue1_due_to_partial_o =
        backend_iq_enqueue1_due_to_partial_debug;
    assign debug_if2_bundle_valid_o = if2_bundle_valid_c;
    assign debug_if2_downstream_accept2_o = if2_downstream_accept2_c;
    assign debug_if2_downstream_accept1_o = if2_downstream_accept1_c;
    assign debug_if2_downstream_stall_o = if2_downstream_stall_c;
    assign debug_if2_slot1_retained_o = if2_slot1_retained_c;
    assign debug_if2_slot1_replayed_as_slot0_o = if2_slot1_replayed_as_slot0_c;
    assign debug_if2_redirect_flush_o = if2_redirect_flush_c;
    assign debug_if2_stale_slot_kill_o = if2_stale_slot_kill_c;
    assign debug_if2pair_downstream_accept2_o =
        if2_pair_frontend_mode && if2_downstream_accept2_c;
    assign debug_if2pair_downstream_accept1_o =
        if2_pair_frontend_mode && if2_downstream_accept1_c;
    assign debug_if2pair_downstream_stall_o =
        if2_pair_frontend_mode && if2_downstream_stall_c;
    assign debug_if2pair_slot1_retained_o =
        if2_pair_frontend_mode && if2_slot1_retained_c;
    assign debug_if2pair_slot1_replayed_as_slot0_o =
        if2_pair_frontend_mode && if2_slot1_replayed_as_slot0_c;
    assign debug_if2pair_redirect_flush_o =
        if2_pair_frontend_mode && if2_redirect_flush_c;
    assign debug_if2pair_duplicate_replay_bug_o =
        if2_pair_frontend_mode &&
        debug_dispatch2_retained_duplicate_rename_bug_o;
    assign debug_duplicate_issue_guard_o = backend_duplicate_issue_guard_debug;
    assign debug_commit_width_mode_o = backend_commit_width_mode_debug;
    assign debug_commit2_candidate_o = backend_commit2_candidate_debug;
    assign debug_commit2_fire_o = backend_commit2_fire_debug;
    assign debug_commit2_slot0_only_o = backend_commit2_slot0_only_debug;
    assign debug_commit2_block_slot0_not_ready_o =
        backend_commit2_block_slot0_not_ready_debug;
    assign debug_commit2_block_slot1_not_ready_o =
        backend_commit2_block_slot1_not_ready_debug;
    assign debug_commit2_block_slot0_complex_o =
        backend_commit2_block_slot0_complex_debug;
    assign debug_commit2_block_slot1_complex_o =
        backend_commit2_block_slot1_complex_debug;
    assign debug_commit2_rrat_update2_o = backend_commit2_rrat_update2_debug;
    assign debug_commit2_freelist_release2_o =
        backend_commit2_freelist_release2_debug;
    assign debug_commit2_same_rd_waw_o = backend_commit2_same_rd_waw_debug;
    assign debug_commit2_duplicate_release_bug_o =
        backend_commit2_duplicate_release_bug_debug;
    assign debug_commit2_slot1_without_slot0_bug_o =
        backend_commit2_slot1_without_slot0_bug_debug;
    assign debug_commit2_complex_slot_bug_o =
        backend_commit2_complex_slot_bug_debug;
    assign debug_commit2_trace_slot1_o = trace_commit2_slot1_debug;
    assign debug_commit2_difftest_step2_o =
        commit_valid_o && commit_mask_o[1] && commit_slot1_o;
    assign debug_unsupported_seen_o = unsupported_seen_q;
    assign debug_unsupported_pc_o = unsupported_pc_q;
    assign debug_unsupported_instr_o = unsupported_instr_q;

    always_ff @(posedge clk) begin
        if (reset || commit_redirect_valid_o) begin
            if2_slot1_replay_pending_q <= 1'b0;
            if2_slot1_replay_pc_q <= 32'b0;
            if2_slot1_replay_instr_q <= 32'b0;
        end else if (if2_slot1_retained_c) begin
            if2_slot1_replay_pending_q <= 1'b1;
            if2_slot1_replay_pc_q <= feeder1_pc;
            if2_slot1_replay_instr_q <= feeder1_instr;
        end else if (if2_slot1_replayed_as_slot0_c) begin
            if2_slot1_replay_pending_q <= 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            if2_slots_visible_q <= 1'b0;
        end else begin
            if2_slots_visible_q <=
                if2_frontend_mode &&
                (feeder_valid || feeder1_valid || if2_slot1_replay_pending_q);
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            frontend_halt_seen_q <= 1'b0;
        end else if (debug_commit_event_o.control_event_valid &&
                     (debug_commit_event_o.control_event == BBUS_OOO_CTRL_EBREAK)) begin
            frontend_halt_seen_q <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            unsupported_seen_q <= 1'b0;
            unsupported_pc_q <= RESET_VECTOR;
            unsupported_instr_q <= 32'b0;
        end
    end

    /* verilator lint_off UNUSED */
    wire backend_alloc_tag_unused = ^backend_alloc_tag;
    wire backend_alu_writeback_unused = ^backend_alu_writeback;
    wire backend_writeback_accepted_unused = backend_writeback_accepted;
    wire backend_rat_phys_debug_unused = ^backend_rat_phys_debug;
    wire backend_rrat_phys_debug_unused = ^backend_rrat_phys_debug;
    wire backend_ready_debug_unused = backend_ready_debug;
    wire backend_free_count_debug_unused = ^backend_free_count_debug;
    wire backend_next_free_debug_unused = ^backend_next_free_debug;
    wire backend_prf_data_debug_unused = ^backend_prf_data_debug;
    wire backend_rob_valid_debug_unused = backend_rob_valid_debug;
    wire backend_rob_head_debug_unused = ^backend_rob_head_debug;
    wire backend_rob_tail_debug_unused = ^backend_rob_tail_debug;
    wire backend_iq_ready_count_debug_unused = ^backend_iq_ready_count_debug;
    wire backend_wb_buffer_full_debug_unused = backend_wb_buffer_full_debug;
    wire backend_wb_buffer_phys_debug_unused = ^backend_wb_buffer_phys_debug;
    wire backend_wb_buffer_result_debug_unused = ^backend_wb_buffer_result_debug;
    wire backend_alu_busy_debug_unused = backend_alu_busy_debug;
    wire backend_alu_completion_valid_debug_unused = backend_alu_completion_valid_debug;
    wire backend_lsu_debug_unused = backend_lsu_busy_debug ^ backend_lsu_completion_valid_debug;
    wire commit_unsupported_unused = commit_unsupported_o;
    wire commit_exception_valid_unused = commit_exception_valid_o;
    /* verilator lint_on UNUSED */
endmodule
