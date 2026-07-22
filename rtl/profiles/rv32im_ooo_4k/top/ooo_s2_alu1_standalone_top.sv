`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

`ifndef NPC_OOO_DUAL_WB
`define NPC_OOO_DUAL_WB 0
`endif

module ooo_s2_alu1_standalone_top #(
    parameter int ALU_LATENCY = 1,
    parameter int ALU1_LATENCY = ALU_LATENCY
) (
    input  logic clk,
    input  logic reset,

    input  logic decode_valid_i,
    input  bbus_ooo_decode_uop_t decode_uop_i,
    input  logic decode1_valid_i,
    input  bbus_ooo_decode_uop_t decode1_uop_i,
    input  logic commit_enable_i,
    input  logic debug_alu_issue_enable_i,
    input  logic debug_wakeup_enable_i,
    input  logic debug_wb_accept_enable_i,

    input  bbus_ooo_arch_reg_t debug_arch_idx_i,
    input  bbus_ooo_phys_reg_t debug_phys_idx_i,
    input  bbus_ooo_phys_reg_t debug_prf_phys_idx_i,
    input  bbus_ooo_rob_idx_t debug_rob_idx_i,

    output logic rename_fire_o,
    output logic rename1_fire_o,
    output bbus_ooo_renamed_uop_t renamed_uop_o,
    output bbus_ooo_rob_tag_t alloc_tag_o,
    output bbus_ooo_writeback_t alu_writeback_o,
    output logic writeback_accepted_o,
    output bbus_ooo_commit_event_t commit_event_o,
    output logic control_pending_o,
    output logic memory_pending_o,
    output logic commit_redirect_valid_o,
    output logic [31:0] commit_redirect_pc_o,

    output bbus_ooo_phys_reg_t debug_rat_phys_o,
    output bbus_ooo_phys_reg_t debug_rrat_phys_o,
    output logic debug_ready_o,
    output logic [6:0] debug_free_count_o,
    output bbus_ooo_phys_reg_t debug_next_free_phys_o,
    output logic [`BBUS_OOO_XLEN-1:0] debug_prf_data_o,
    output logic debug_rob_valid_o,
    output logic debug_rob_done_o,
    output logic [31:0] debug_rob_result_o,
    output logic [3:0] debug_rob_count_o,
    output bbus_ooo_rob_idx_t debug_rob_head_o,
    output bbus_ooo_rob_idx_t debug_rob_tail_o,
    output logic [3:0] debug_iq_count_o,
    output logic [3:0] debug_iq_ready_count_o,
    output logic [3:0] debug_iq_ready_alu_count_o,
    output logic [3:0] debug_iq_ready_lsu_count_o,
    output logic [3:0] debug_iq_ready_bru_count_o,
    output logic [3:0] debug_iq_ready_csr_sys_count_o,
    output logic [3:0] debug_iq_ready_any_count_o,
    output logic [3:0] debug_issue_candidate_count_o,
    output logic debug_issue_multi_candidate_o,
    output logic debug_wb_buffer_full_o,
    output logic debug_wb_buffer_valid_o,
    output bbus_ooo_phys_reg_t debug_wb_buffer_phys_o,
    output logic [31:0] debug_wb_buffer_result_o,
    output logic debug_alu_busy_o,
    output logic debug_alu_completion_valid_o,
    output logic debug_lsu_busy_o,
    output logic debug_lsu_completion_valid_o,
    output logic debug_branch_busy_o,
    output logic debug_branch_completion_valid_o,
    output logic debug_csr_busy_o,
    output logic debug_csr_completion_valid_o,
    output logic debug_execution_path_clear_o,
    output logic debug_dispatch_valid_o,
    output logic debug_dispatch_ready_o,
    output logic debug_dispatch_fire_o,
    output logic debug_iq_enqueue_o,
    output logic debug_iq_issue_valid_o,
    output logic debug_iq_issue_ready_o,
    output logic debug_issue_fire_o,
    output logic debug_issue_fu_ready_o,
    output logic debug_rob_full_o,
    output logic debug_iq_full_o,
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
    output logic debug_dual_wb_enabled_o,
    output logic debug_dual_wb_raw_fire_o,
    output logic debug_dual_wb_final_fire_o,
    output logic debug_dual_wb_lane1_hold_o,
    output logic debug_dual_wb_lane1_replay_o,
    output logic debug_dual_wb_duplicate_phys_hold_o,
    output logic debug_dual_wb_duplicate_rob_tag_hold_o,
    output logic debug_dual_wb_atomicity_guard_o
);
`ifdef NPC_OOO_EBREAK_TRAP
    localparam bit EBREAK_TRAP_ENABLE = 1'b1;
`else
    localparam bit EBREAK_TRAP_ENABLE = 1'b0;
`endif
    bbus_ooo_decode_uop_t decode_uop1_zero;
    logic [1:0] decode_valid_mask;
    logic [1:0] rename_fire_mask;
    logic [1:0] dispatch_slots_available;
    bbus_ooo_renamed_uop_t renamed_uop0;
    bbus_ooo_renamed_uop_t renamed_uop1;

    logic [1:0] rob_available_slots;
    logic selective_unused_ready, selective_unused_fire,
        selective_unused_identity_error;
    logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_unused_killed_rob_mask;
    logic [`BBUS_OOO_PHYS_REGS-1:0] selective_unused_killed_phys_mask;
    logic [3:0] selective_unused_killed_count;
    bbus_ooo_rob_idx_t rob_head_idx;
    bbus_ooo_rob_tag_t rob_head_tag;
    logic [1:0] rob_alloc_fire_mask;
    bbus_ooo_rob_tag_t alloc_tag0;
    bbus_ooo_rob_tag_t alloc_tag1;
    bbus_ooo_rob_alloc_t rob_alloc0;
    bbus_ooo_rob_alloc_t rob_alloc1;
    logic [1:0] rob_commit_width_mode_debug;
    logic rob_commit2_candidate_debug;
    logic rob_commit2_fire_debug;
    logic rob_commit2_slot0_only_debug;
    logic rob_commit2_block_slot0_not_ready_debug;
    logic rob_commit2_block_slot1_not_ready_debug;
    logic rob_commit2_block_slot0_complex_debug;
    logic rob_commit2_block_slot1_complex_debug;
    logic rob_commit2_slot1_without_slot0_bug_debug;
    logic rob_commit2_complex_slot_bug_debug;
    logic rename_commit2_rrat_update2_debug;
    logic rename_commit2_freelist_release2_debug;
    logic rename_commit2_same_rd_waw_debug;
    logic rename_commit2_duplicate_release_bug_debug;

    bbus_ooo_alu_iq_uop_t iq_dispatch_uop;
    bbus_ooo_alu_iq_uop_t iq_dispatch1_uop;
    logic iq_dispatch_valid;
    logic iq_dispatch1_valid;
    logic iq_dispatch_ready;
    logic iq_dispatch1_ready;
    logic [1:0] iq_dispatch_ready_count;
    logic [1:0] iq_dispatch_fire_mask;
    logic iq_issue_valid;
    bbus_ooo_alu_iq_uop_t iq_issue_uop;
    logic iq_issue1_valid;
    bbus_ooo_alu_iq_uop_t iq_issue1_uop;
    logic iq_issue2_pair_valid;
    logic iq_issue2_pair_is_alu_lsu;
    logic iq_issue2_pair_is_alu_alu;
    logic iq_issue2_pair_legal;
    logic iq_duplicate_issue_guard;

    logic [`BBUS_OOO_XLEN-1:0] prf_rs1_data;
    logic [`BBUS_OOO_XLEN-1:0] prf_rs2_data;
    logic [`BBUS_OOO_XLEN-1:0] prf1_rs1_data;
    logic [`BBUS_OOO_XLEN-1:0] prf1_rs2_data;
    bbus_ooo_writeback_t alu0_completion_wb;
    bbus_ooo_writeback_t alu1_completion_wb;
    logic alu0_completion_valid;
    logic alu1_completion_valid;
    logic alu0_completion_ready;
    logic alu1_completion_ready;
    logic alu0_busy;
    logic alu1_busy;
    bbus_ooo_branch_uop_t branch_issue_uop;
    logic branch_issue_valid;
    logic branch_issue_ready_raw;
    logic branch_completion_valid;
    logic branch_completion_ready;
    bbus_ooo_branch_completion_t branch_completion;
    bbus_ooo_redirect_t branch_redirect;
    logic branch_redirect_valid;
    logic branch_busy;
    logic branch_debug_completion_valid;
    bbus_ooo_writeback_t branch_completion_wb;
    logic branch_target_misaligned_c;
    bbus_ooo_lsu_uop_t lsu_issue_uop;
    logic lsu_issue_valid;
    logic lsu_issue_ready_raw;
    logic lsu_completion_valid;
    logic lsu_completion_ready;
    bbus_ooo_writeback_t lsu_completion_wb;
    logic csr_completion_valid;
    logic csr_completion_ready;
    logic csr_local_completion_valid;
    logic csr_local_completion_ready;
    bbus_ooo_writeback_t csr_completion_wb;
    bbus_ooo_writeback_t csr_completion_wb_q;
    bbus_ooo_writeback_t csr_completion_next_c;
    logic csr_busy_q;
    logic csr_issue_valid;
    logic mdu_issue_valid;
    logic mdu_issue_ready_raw;
    logic mdu_completion_valid;
    logic mdu_completion_ready;
    bbus_ooo_writeback_t mdu_completion_wb;
    logic mdu_busy;
    logic mdu_flush_drop;
    logic mdu_illegal_issue;
    logic atomic_issue_valid;
    logic atomic_issue_ready_raw;
    logic atomic_completion_valid;
    logic atomic_completion_ready;
    bbus_ooo_writeback_t atomic_completion_wb;
    logic atomic_busy;
    logic atomic_memory_lock;
    logic atomic_write_request_fire;
    logic atomic_recovery_block;
    logic atomic_killed_read_drain;
    logic atomic_illegal_issue;
    logic atomic_flush_drop;
    logic atomic_reservation_valid;
    logic [31:0] atomic_reservation_addr;
    logic atomic_sc_success;
    logic atomic_sc_failure;
    logic atomic_irreversible_flush_error;
    logic atomic_conservation_error;
    logic atomic_commit_valid;
    bbus_ooo_rob_tag_t atomic_commit_tag;
    logic atomic_mem_req_valid;
    logic atomic_mem_req_ready;
    logic atomic_mem_req_write;
    logic [31:0] atomic_mem_req_addr;
    logic [31:0] atomic_mem_req_wdata;
    logic [3:0] atomic_mem_req_wstrb;
    logic [2:0] atomic_mem_req_len;
    logic atomic_mem_rsp_valid;
    logic atomic_mem_rsp_ready;
    logic [31:0] atomic_mem_rsp_rdata;
    logic atomic_mem_rsp_error;
    logic atomic_bridge_busy;
    logic atomic_bridge_req_fire;
    logic atomic_bridge_rsp_capture;
    logic atomic_bridge_rsp_fire;
    logic atomic_bridge_protocol_error;
    logic atomic_lsu_collision_error_q;
    logic [31:0] csr_read_data_c;
    logic [31:0] csr_operand_c;
    logic [31:0] csr_wdata_c;
    logic csr_write_c;
    logic csr_access_illegal_c;
    logic mret_illegal_c;
    logic sret_illegal_c;
    logic wfi_illegal_c;
    logic sfence_illegal_c;
    logic csr_is_ecall_c;
    logic csr_is_mret_c;
    logic csr_is_sret_c;
    logic csr_is_wfi_c;
    logic csr_is_sfence_vma_c;
    logic csr_is_fencei_c;
    logic csr_is_ebreak_c;
    logic [31:0] csr_mstatus_q;
    logic [31:0] csr_mtvec_q;
    logic [31:0] csr_mepc_q;
    logic [31:0] csr_mcause_q;
    logic [31:0] csr_mscratch_q;
    logic [31:0] csr_mie_q;
    logic [31:0] csr_mip_q;
    logic [31:0] csr_mtval_q;
    logic [31:0] csr_mcounteren_q;
    logic [31:0] csr_medeleg_q;
    logic [31:0] csr_mideleg_q;
    logic [31:0] csr_stvec_q;
    logic [31:0] csr_sscratch_q;
    logic [31:0] csr_sepc_q;
    logic [31:0] csr_scause_q;
    logic [31:0] csr_stval_q;
    logic [31:0] csr_scounteren_q;
    logic [1:0] priv_mode_q;
    logic commit_trap_delegated_c;
    logic [31:0] commit_trap_cause_c;
    logic [31:0] commit_trap_target_c;
    logic lsu_commit_store_valid;
    logic lsu_commit_store_valid_to_unit;
    logic lsu_commit_store_ready;
    logic lsu_commit_store_ready_raw;
    logic lsu_commit_store_done;
    logic [31:0] lsu_commit_store_addr;
    logic [31:0] lsu_commit_store_wdata;
    logic [3:0] lsu_commit_store_wstrb;
    logic [2:0] lsu_commit_store_len;
    logic lsu_debug_mem_req_valid;
    logic lsu_debug_mem_resp_valid;
    logic lsu_issue_valid_to_unit;
    bbus_ooo_writeback_t wb_buffer_in;
    logic wb_buffer_in_valid;
    logic wb_buffer_in_ready;
    bbus_ooo_writeback_t wb_buffer_out;
    logic wb_buffer_out_valid;
    logic wb_buffer_out_accepted;
    logic wb_buffer_out_drop;
    logic completion_any_valid;
    logic completion_oldest_mode;
    logic completion_fixed_mode;
    logic alu_sched_balance_mode;
    logic fixed_completion_grant_alu0;
    logic fixed_completion_grant_alu1;
    logic fixed_completion_grant_bru;
    logic fixed_completion_grant_lsu;
    logic fixed_completion_grant_csr;
    logic fixed_completion_grant_atomic;
    logic oldest_completion_grant_alu0;
    logic oldest_completion_grant_alu1;
    logic oldest_completion_grant_bru;
    logic oldest_completion_grant_lsu;
    logic oldest_completion_grant_csr;
    logic oldest_completion_grant_atomic;
    logic selected_completion_grant_alu0;
    logic selected_completion_grant_alu1;
    logic selected_completion_grant_bru;
    logic selected_completion_grant_lsu;
    logic selected_completion_grant_csr;
    logic selected_completion_grant_atomic;
    logic completion_selected_valid;
    logic completion_oldest_differs_from_fixed;
    logic duplicate_completion_tag;
    logic completion_arb_no_valid_bug;
    bbus_ooo_writeback_t rob_writeback;
    bbus_ooo_writeback_t rob_writeback1;
    logic rob_wb_accepted_raw;
    logic rob_wb1_accepted_raw;
    logic rob_probe0_match;
    logic rob_probe1_match;
    logic wb_prf_write_valid;
    logic wb_prf_write1_valid;
    logic wb_readytable_wakeup_valid;
    logic wb_readytable_wakeup1_valid;
    bbus_ooo_phys_reg_t wb_readytable_wakeup_phys;
    bbus_ooo_phys_reg_t wb_readytable_wakeup1_phys;
    bbus_ooo_phys_reg_t wb_prf_write_phys;
    bbus_ooo_phys_reg_t wb_prf_write1_phys;
    logic [`BBUS_OOO_XLEN-1:0] wb_prf_write_data;
    logic [`BBUS_OOO_XLEN-1:0] wb_prf_write1_data;
    logic dual_wb_enabled;
    logic dual_wb_non_alu_completion_valid;
    logic dual_wb_raw_eligible;
    logic dual_wb_active_cycle;
    logic [1:0] dual_wb_source_accept_mask;
    logic [1:0] dual_wb_source_drop_mask;
    logic [1:0] dual_wb_source_clear_mask;
    logic [1:0] dual_wb_raw_accept_mask;
    logic [1:0] dual_wb_final_accept_mask;
    logic [1:0] dual_wb_hold_mask;
    logic [1:0] dual_wb_offer_mask;
    logic [1:0] dual_wb_consume_mask;
    logic [1:0] dual_wb_final_drop_mask;
    logic legacy_wb_offer_valid;
    logic [1:0] dual_wb_ordinary_wakeup_valid;
    bbus_ooo_writeback_t dual_wb0_final;
    bbus_ooo_writeback_t dual_wb1_final;
    bbus_ooo_phys_reg_t dual_wb_wakeup_phys0;
    bbus_ooo_phys_reg_t dual_wb_wakeup_phys1;
    bbus_ooo_writeback_t dual_wb0_input;
    bbus_ooo_writeback_t dual_wb1_input;
    bbus_ooo_writeback_t dual_wb_held_wb;
    logic dual_wb_held_valid;
    logic [1:0] dual_wb_pending_count;
    logic dual_wb_buffer_full;
    logic dual_wb_buffer_empty;
    logic [1:0] dual_wb_enqueue_mask;
    logic [1:0] dual_wb_dequeue_mask;
    logic dual_wb_raw_fire;
    logic dual_wb_final_fire;
    logic dual_wb_lane1_hold;
    logic dual_wb_lane1_replay;
    logic dual_wb_duplicate_phys_hold;
    logic dual_wb_duplicate_rob_tag_hold;
    logic dual_wb_lane0_block_hold;
    logic dual_wb_lane1_consumer_block_hold;
    logic dual_wb_lane1_buffer_full_hold;
    logic dual_wb_lane1_ordering_block_hold;
    logic dual_wb_held_blocked;
    logic dual_wb_buffer_full_hold;
    logic dual_wb_conservation_error;
    logic dual_wb_stale_drop0;
    logic dual_wb_stale_drop1;
    logic dual_wb_killed_drop0;
    logic dual_wb_killed_drop1;
    logic dual_wb_exception_no_wakeup0;
    logic dual_wb_exception_no_wakeup1;
    logic dual_wb_p0_wakeup_suppressed0;
    logic dual_wb_p0_wakeup_suppressed1;
    logic dual_wb_atomicity_mask_valid;
    logic [`BBUS_OOO_XLEN-1:0] alu_src1_data;
    logic [`BBUS_OOO_XLEN-1:0] alu_src2_data;
    logic [`BBUS_OOO_XLEN-1:0] alu1_src1_data;
    logic [`BBUS_OOO_XLEN-1:0] alu1_src2_data;
    logic [`BBUS_OOO_XLEN-1:0] branch_src1_data;
    logic [`BBUS_OOO_XLEN-1:0] branch_src2_data;
    logic [`BBUS_OOO_XLEN-1:0] lsu_base_data;
    logic [`BBUS_OOO_XLEN-1:0] lsu_store_data;
    bbus_ooo_alu_iq_uop_t alu0_selected_uop;
    bbus_ooo_alu_iq_uop_t alu1_selected_uop;
    bbus_ooo_alu_iq_uop_t lsu_selected_uop;
    logic alu_issue_ready_raw;
    logic alu1_issue_ready_raw;
    logic iq_issue_ready_to_iq;
    logic iq_issue1_ready_to_iq;
    logic alu0_issue_valid;
    logic alu1_issue_valid;
    logic issue_is_alu;
    logic issue_is_bru;
    logic issue_is_lsu;
    logic issue_is_lsu_load;
    logic issue_is_csr_sys;
    logic issue_is_mdu;
    logic issue_is_atomic;
    logic issue1_is_alu;
    logic issue1_is_lsu_load;
    logic issue0_serializing_for_pair;
    logic execution_path_clear;
    logic completion_path_clear;
    logic issue_selected_fu_ready;
    logic alu_issue_allowed;
    logic alu1_single_issue_candidate;
    logic alu1_single_issue_allowed;
    logic alu1_single_issue_fire;
    logic alu0_single_issue_fire;
    logic alu_sched_balance_blocked_both_busy;
    logic alu_sched_balance_blocked_wb;
    logic branch_issue_allowed;
    logic lsu_issue_allowed;
    logic csr_issue_allowed;
    logic mdu_issue_allowed;
    logic atomic_issue_allowed;
    logic dual_issue_candidate;
    logic dual_alu_lsu_candidate;
    logic dual_alu_alu_candidate;
    logic dual_issue_candidate_alu_alu;
    logic dual_issue_candidate_alu_lsu;
    logic dual_issue_candidate_lsu_alu;
    logic dual_alu_lsu_allowed;
    logic dual_alu_alu_allowed;
    logic dual_issue_allowed;
    logic dual_issue_fire;
    logic issue0_fire;
    logic issue1_fire;
    logic issue1_suppressed_c;
    logic issue1_suppressed_by_fu_busy_c;
    logic issue1_suppressed_by_wb_c;
    logic alu_from_issue1;
    logic alu1_from_issue0;
    logic lsu_from_issue1;
    logic wb_conflict_alu0_alu1;
    logic wb_conflict_alu_lsu;
    logic wb_conflict_bru_data;
    logic decode_needs_iq;
    logic control_pending_q;
    logic memory_pending_q;
    logic store_serializing_pending;
    logic dispatch_width2_mode;
    logic decode1_pair_safe;
    logic decode1_valid_for_rename;
    logic [1:0] dispatch_slots_single;
    logic [1:0] dispatch_slots_dual;
    logic [1:0] iq_available_slots;
    logic [1:0] rob_dispatch_available_slots;
    logic [1:0] iq_dispatch_available_slots;
    logic [6:0] freelist_dispatch_available_slots;
    logic [1:0] dispatch2_phys_needed;
    logic dispatch2_candidate_c;
    logic dispatch2_safe_pair_candidate;
    logic dispatch2_resource_candidate;
    logic dispatch2_partial_slot0_only_c;
    logic dispatch2_slot1_retained_due_to_rob_c;
    logic dispatch2_slot1_retained_due_to_iq_c;
    logic dispatch2_slot1_retained_due_to_freelist_c;
    logic dispatch2_slot1_retained_due_to_serial_c;
    logic dispatch2_retained_pending_q;
    logic [31:0] dispatch2_retained_pc_q;
    logic [31:0] dispatch2_retained_instr_q;
    logic dispatch2_retained_replayed_as_slot0_c;
    logic dispatch2_retained_duplicate_decode_c;
    logic dispatch2_retained_flush_clear_c;
    logic completion_recovery_event_c;
    logic completion_flush_c;
    logic completion_flush_q;

    function automatic logic iq_is_alu_like(input bbus_ooo_alu_iq_uop_t uop);
        begin
            iq_is_alu_like =
                uop.valid &&
                !uop.is_load &&
                !uop.is_store &&
                !uop.is_csr &&
                !uop.is_system &&
                ((uop.fu_type == BBUS_OOO_FU_ALU) ||
                 (uop.fu_type == BBUS_OOO_FU_NONE));
        end
    endfunction

    function automatic logic iq_is_lsu_load(input bbus_ooo_alu_iq_uop_t uop);
        begin
            iq_is_lsu_load =
                uop.valid &&
                (uop.fu_type == BBUS_OOO_FU_LSU) &&
                uop.is_load &&
                !uop.is_store;
        end
    endfunction

    function automatic logic iq_is_lsu_store(input bbus_ooo_alu_iq_uop_t uop);
        begin
            iq_is_lsu_store =
                uop.valid &&
                (uop.fu_type == BBUS_OOO_FU_LSU) &&
                uop.is_store;
        end
    endfunction

    function automatic logic iq_is_bru(input bbus_ooo_alu_iq_uop_t uop);
        begin
            iq_is_bru = uop.valid && (uop.fu_type == BBUS_OOO_FU_BRU);
        end
    endfunction

    function automatic logic iq_is_csr_sys(input bbus_ooo_alu_iq_uop_t uop);
        begin
            iq_is_csr_sys =
                uop.valid &&
                ((uop.fu_type == BBUS_OOO_FU_CSR) ||
                 (uop.fu_type == BBUS_OOO_FU_SYS) ||
                 uop.is_csr ||
                 uop.is_system);
        end
    endfunction

    function automatic logic iq_is_mdu(input bbus_ooo_alu_iq_uop_t uop);
        begin
            iq_is_mdu = uop.valid && (uop.fu_type == BBUS_OOO_FU_MDU);
        end
    endfunction

    function automatic logic iq_is_atomic(input bbus_ooo_alu_iq_uop_t uop);
        begin
            iq_is_atomic = uop.valid && (uop.fu_type == BBUS_OOO_FU_AMO);
        end
    endfunction

    function automatic logic iq_is_serializing(input bbus_ooo_alu_iq_uop_t uop);
        begin
            iq_is_serializing =
                iq_is_bru(uop) ||
                iq_is_lsu_store(uop) ||
                iq_is_csr_sys(uop) ||
                iq_is_mdu(uop) ||
                iq_is_atomic(uop);
        end
    endfunction

    function automatic logic decode_needs_phys(input bbus_ooo_decode_uop_t uop);
        begin
            decode_needs_phys =
                uop.valid &&
                uop.rf_wen &&
                (uop.arch_rd != 5'd0) &&
                !uop.exception.valid;
        end
    endfunction

    function automatic logic decode_is_alu_like(input bbus_ooo_decode_uop_t uop);
        begin
            decode_is_alu_like =
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

    function automatic logic decode_is_serializing(input bbus_ooo_decode_uop_t uop);
        begin
            decode_is_serializing =
                uop.valid &&
                (uop.is_load ||
                 uop.is_store ||
                 uop.is_csr ||
                 uop.is_system ||
                 uop.is_ebreak ||
                 uop.unsupported_class ||
                 uop.exception.valid ||
                 (uop.fu_type == BBUS_OOO_FU_BRU) ||
                 (uop.fu_type == BBUS_OOO_FU_CSR) ||
                 (uop.fu_type == BBUS_OOO_FU_SYS) ||
                 (uop.fu_type == BBUS_OOO_FU_LSU) ||
                 (uop.fu_type == BBUS_OOO_FU_MDU) ||
                 (uop.fu_type == BBUS_OOO_FU_AMO));
        end
    endfunction

    function automatic logic legal_alu_lsu_pair(
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        begin
            legal_alu_lsu_pair =
                a.valid &&
                b.valid &&
                ((iq_is_alu_like(a) && iq_is_lsu_load(b)) ||
                 (iq_is_lsu_load(a) && iq_is_alu_like(b)));
        end
    endfunction

    function automatic logic legal_alu_alu_pair(
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        begin
            legal_alu_alu_pair =
                a.valid &&
                b.valid &&
                iq_is_alu_like(a) &&
                iq_is_alu_like(b);
        end
    endfunction

    function automatic logic legal_issue2_pair(
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        begin
            legal_issue2_pair =
                legal_alu_lsu_pair(a, b) ||
                legal_alu_alu_pair(a, b);
        end
    endfunction

    function automatic int unsigned rob_age_distance(
        input bbus_ooo_rob_tag_t tag,
        input bbus_ooo_rob_idx_t head_idx
    );
        int unsigned tag_idx_u;
        int unsigned head_idx_u;
        begin
            tag_idx_u = int'(tag.idx);
            head_idx_u = int'(head_idx);
            if (tag_idx_u >= head_idx_u) begin
                rob_age_distance = tag_idx_u - head_idx_u;
            end else begin
                rob_age_distance = (`BBUS_OOO_ROB_ENTRIES + tag_idx_u) - head_idx_u;
            end
        end
    endfunction

    function automatic logic same_valid_rob_tag(
        input logic a_valid,
        input bbus_ooo_rob_tag_t a_tag,
        input logic b_valid,
        input bbus_ooo_rob_tag_t b_tag
    );
        begin
            same_valid_rob_tag = a_valid && b_valid && (a_tag == b_tag);
        end
    endfunction

    function automatic logic [31:0] csr_read_value(input logic [11:0] addr);
        begin
            unique case (addr)
`ifdef NPC_S_EXTENSION
                12'h100: csr_read_value = csr_mstatus_q & 32'h000c_0122;
                12'h104: csr_read_value = csr_mie_q & csr_mideleg_q & 32'h0000_0222;
                12'h105: csr_read_value = csr_stvec_q;
                12'h106: csr_read_value = csr_scounteren_q;
                12'h140: csr_read_value = csr_sscratch_q;
                12'h141: csr_read_value = csr_sepc_q;
                12'h142: csr_read_value = csr_scause_q;
                12'h143: csr_read_value = csr_stval_q;
                12'h144: csr_read_value = csr_mip_q & csr_mideleg_q & 32'h0000_0222;
                12'h180: csr_read_value = 32'b0;
`endif
                12'h300: csr_read_value = csr_mstatus_q;
                12'h301: begin
                    csr_read_value = 32'h4010_0100;
`ifdef NPC_M_EXTENSION
                    csr_read_value = csr_read_value | 32'h0000_1000;
`endif
`ifdef NPC_A_EXTENSION
                    csr_read_value = csr_read_value | 32'h0000_0001;
`endif
`ifdef NPC_S_EXTENSION
                    csr_read_value = csr_read_value | 32'h0004_0000;
`endif
                end
                12'h302: csr_read_value = csr_medeleg_q;
                12'h303: csr_read_value = csr_mideleg_q;
                12'h304: csr_read_value = csr_mie_q;
                12'h305: csr_read_value = csr_mtvec_q;
                12'h306: csr_read_value = csr_mcounteren_q;
                12'h340: csr_read_value = csr_mscratch_q;
                12'h341: csr_read_value = csr_mepc_q;
                12'h342: csr_read_value = csr_mcause_q;
                12'h343: csr_read_value = csr_mtval_q;
                12'h344: csr_read_value = csr_mip_q;
                12'hb00,
                12'hb02,
                12'hb80,
                12'hb82,
                12'hc00,
                12'hc02,
                12'hc80,
                12'hc82: begin
                    // TODO(S9_COUNTERS): add architectural mcycle/minstret
                    // state and a directed DUT/NEMU counter test.
                    csr_read_value = 32'b0;
                end
                12'hf11: csr_read_value = 32'b0;
                12'hf12: csr_read_value = 32'h0000_0005;
                12'hf13: csr_read_value = 32'b0;
                12'hf14: csr_read_value = 32'b0;
                default: csr_read_value = 32'b0;
            endcase
        end
    endfunction

    function automatic logic csr_implemented(input logic [11:0] addr);
        begin
            unique case (addr)
`ifdef NPC_S_EXTENSION
                12'h100, 12'h104, 12'h105, 12'h106,
                12'h140, 12'h141, 12'h142, 12'h143, 12'h144, 12'h180,
`endif
                12'h300, 12'h301, 12'h302, 12'h303, 12'h304, 12'h305,
                12'h306, 12'h340, 12'h341, 12'h342, 12'h343, 12'h344,
                12'h3a0, 12'h3b0,
                12'h7a0, 12'h7a1, 12'h7a2, 12'h7a3, 12'h7a4,
                12'hb00, 12'hb02, 12'hb80, 12'hb82,
                12'hc00, 12'hc02, 12'hc80, 12'hc82,
                12'hf11, 12'hf12, 12'hf13, 12'hf14:
                    csr_implemented = 1'b1;
                default: csr_implemented = 1'b0;
            endcase
        end
    endfunction

    function automatic logic csr_counter_access_ok(
        input logic [11:0] addr,
        input logic [1:0] priv,
        input logic [31:0] mcounteren,
        input logic [31:0] scounteren
    );
        logic enabled;
        begin
            enabled = 1'b1;
            if (priv != 2'b11) begin
                unique case (addr)
                    12'hc00, 12'hc80: enabled = mcounteren[0];
                    12'hc02, 12'hc82: enabled = mcounteren[2];
                    default: enabled = 1'b1;
                endcase
                if ((priv == 2'b00) && enabled) begin
                    unique case (addr)
                        12'hc00, 12'hc80: enabled = scounteren[0];
                        12'hc02, 12'hc82: enabled = scounteren[2];
                        default: enabled = 1'b1;
                    endcase
                end
            end
            csr_counter_access_ok = enabled;
        end
    endfunction

    function automatic logic [31:0] mstatus_warl(input logic [31:0] value);
        logic [31:0] result;
        begin
`ifdef NPC_S_EXTENSION
            result = value & 32'h007e_19aa;
            if (value[12:11] == 2'b10) begin
                result[12:11] = 2'b00;
            end
`else
            result = value & 32'h0002_1888;
            if ((value[12:11] == 2'b01) || (value[12:11] == 2'b10)) begin
                result[12:11] = 2'b00;
            end
`endif
            mstatus_warl = result;
        end
    endfunction

    function automatic logic [31:0] csr_mask_for_write(input logic [11:0] addr);
        begin
            unique case (addr)
                12'h100: csr_mask_for_write = 32'h000c_0122;
                12'h104, 12'h144: csr_mask_for_write = csr_mideleg_q & 32'h0000_0222;
`ifdef NPC_S_EXTENSION
                12'h300: csr_mask_for_write = 32'h007e_19aa;
`else
                12'h300: csr_mask_for_write = 32'h0002_1888;
`endif
                12'h302: csr_mask_for_write = 32'h0000_b3ff;
                12'h303: csr_mask_for_write = 32'h0000_0222;
                default: csr_mask_for_write = 32'hffff_ffff;
            endcase
        end
    endfunction

    function automatic logic [31:0] csr_apply_write(
        input logic [11:0] addr,
        input logic [31:0] old_value,
        input logic [31:0] wdata
    );
        logic [31:0] mask;
        begin
            mask = csr_mask_for_write(addr);
            csr_apply_write = (old_value & ~mask) | (wdata & mask);
        end
    endfunction

    function automatic logic [31:0] csr_trap_mstatus(
        input logic [31:0] old_mstatus,
        input logic [1:0] old_priv
    );
        begin
            csr_trap_mstatus =
                (old_mstatus & ~32'h0000_1888) |
                ({30'b0, old_priv} << 11) |
                ({31'b0, old_mstatus[3]} << 7);
        end
    endfunction

    function automatic logic [31:0] ecall_cause(input logic [1:0] priv);
        begin
            unique case (priv)
                2'b00: ecall_cause = 32'd8;
                2'b01: ecall_cause = 32'd9;
                default: ecall_cause = 32'd11;
            endcase
        end
    endfunction

    function automatic logic [31:0] csr_mret_mstatus(input logic [31:0] old_mstatus);
        logic [31:0] next_status;
        logic [1:0] return_priv;
        begin
            return_priv = old_mstatus[12:11];
            next_status = (old_mstatus & ~32'h0000_0008) |
                ({31'b0, old_mstatus[7]} << 3);
            next_status = next_status | 32'h0000_0080;
            next_status = next_status & ~32'h0000_1800;
            if (return_priv != 2'b11) begin
                next_status = next_status & ~32'h0002_0000;
            end
            csr_mret_mstatus = next_status;
        end
    endfunction

    function automatic logic [31:0] csr_sret_mstatus(input logic [31:0] old_mstatus);
        logic [31:0] next_status;
        begin
            next_status = (old_mstatus & ~32'h0000_0002) |
                ({31'b0, old_mstatus[5]} << 1);
            next_status = next_status | 32'h0000_0020;
            next_status = next_status & ~32'h0002_0100;
            csr_sret_mstatus = next_status;
        end
    endfunction

    function automatic logic [31:0] csr_trap_sstatus(
        input logic [31:0] old_mstatus,
        input logic [1:0] old_priv
    );
        logic [31:0] next_status;
        begin
            next_status = (old_mstatus & ~32'h0000_0122) |
                ({31'b0, old_mstatus[1]} << 5);
            if (old_priv == 2'b01) next_status = next_status | 32'h0000_0100;
            csr_trap_sstatus = next_status;
        end
    endfunction

    assign decode_uop1_zero = '0;
    assign dispatch_width2_mode = (`NPC_OOO_DISPATCH_WIDTH >= 2);
    assign decode1_pair_safe =
        dispatch_width2_mode &&
        decode_valid_i &&
        decode1_valid_i &&
        decode_is_alu_like(decode_uop_i) &&
        decode_is_alu_like(decode1_uop_i);
    assign decode1_valid_for_rename = decode1_pair_safe;
    assign decode_valid_mask = {decode1_valid_for_rename, decode_valid_i};
    assign decode_needs_iq =
        decode_valid_i &&
        !decode_uop_i.exception.valid &&
        !decode_uop_i.is_ebreak;
    assign store_serializing_pending = memory_pending_q;
    assign iq_available_slots = iq_dispatch_ready_count;
    assign rob_dispatch_available_slots =
        (`NPC_OOO_DISPATCH2_TEST_LIMIT_ROB_FREE != 0) ?
        ((rob_available_slots != 2'd0) ? 2'd1 : 2'd0) :
        rob_available_slots;
    assign iq_dispatch_available_slots =
        (`NPC_OOO_DISPATCH2_TEST_LIMIT_IQ_FREE != 0) ?
        ((iq_available_slots != 2'd0) ? 2'd1 : 2'd0) :
        iq_available_slots;
    assign freelist_dispatch_available_slots =
        (`NPC_OOO_DISPATCH2_TEST_LIMIT_FREELIST_FREE != 0) ?
        ((debug_free_count_o != 7'd0) ? 7'd1 : 7'd0) :
        debug_free_count_o;
    assign dispatch2_phys_needed =
        {1'b0, decode_needs_phys(decode_uop_i)} +
        {1'b0, decode_needs_phys(decode1_uop_i)};
    assign dispatch_slots_single =
        ((rob_dispatch_available_slots >= 2'd1) &&
         (!decode_needs_iq || iq_dispatch_ready) &&
         !store_serializing_pending &&
         !control_pending_q &&
         !completion_flush_c) ? 2'd1 : 2'd0;
    assign dispatch_slots_dual =
        (decode1_pair_safe &&
         (rob_dispatch_available_slots >= 2'd2) &&
         (iq_dispatch_available_slots >= 2'd2) &&
         (freelist_dispatch_available_slots >= {5'b0, dispatch2_phys_needed}) &&
         !store_serializing_pending &&
         !control_pending_q &&
         !completion_flush_c) ? 2'd2 : dispatch_slots_single;
    assign dispatch_slots_available = dispatch_width2_mode ? dispatch_slots_dual : dispatch_slots_single;
    assign dispatch2_candidate_c =
        dispatch_width2_mode &&
        decode_valid_i &&
        decode1_valid_i;
    assign dispatch2_safe_pair_candidate = dispatch2_candidate_c && decode1_pair_safe;
    assign dispatch2_resource_candidate = dispatch2_safe_pair_candidate && (dispatch_slots_available >= 2'd2);
    assign dispatch2_partial_slot0_only_c =
        dispatch_width2_mode &&
        decode1_valid_i &&
        rename_fire_mask[0] &&
        !rename_fire_mask[1];
    assign dispatch2_slot1_retained_due_to_rob_c =
        dispatch2_safe_pair_candidate &&
        (rob_dispatch_available_slots < 2'd2) &&
        rename_fire_mask[0] &&
        !rename_fire_mask[1];
    assign dispatch2_slot1_retained_due_to_iq_c =
        dispatch2_safe_pair_candidate &&
        (rob_dispatch_available_slots >= 2'd2) &&
        (iq_dispatch_available_slots < 2'd2) &&
        rename_fire_mask[0] &&
        !rename_fire_mask[1];
    assign dispatch2_slot1_retained_due_to_freelist_c =
        dispatch2_safe_pair_candidate &&
        (rob_dispatch_available_slots >= 2'd2) &&
        (iq_dispatch_available_slots >= 2'd2) &&
        (freelist_dispatch_available_slots < {5'b0, dispatch2_phys_needed}) &&
        rename_fire_mask[0] &&
        !rename_fire_mask[1];
    assign dispatch2_slot1_retained_due_to_serial_c =
        dispatch2_candidate_c &&
        (decode_is_serializing(decode_uop_i) || decode_is_serializing(decode1_uop_i)) &&
        rename_fire_mask[0] &&
        !rename_fire_mask[1];
    assign dispatch2_retained_replayed_as_slot0_c =
        dispatch2_retained_pending_q &&
        decode_valid_i &&
        rename_fire_mask[0] &&
        (decode_uop_i.pc == dispatch2_retained_pc_q) &&
        (decode_uop_i.instr == dispatch2_retained_instr_q);
    assign dispatch2_retained_duplicate_decode_c =
        dispatch2_retained_pending_q &&
        decode_valid_i &&
        decode1_valid_i &&
        rename_fire_mask[1] &&
        (decode1_uop_i.pc == dispatch2_retained_pc_q) &&
        (decode1_uop_i.instr == dispatch2_retained_instr_q);
    assign dispatch2_retained_flush_clear_c =
        dispatch2_retained_pending_q &&
        (commit_redirect_valid_o || control_pending_q);

    always_ff @(posedge clk) begin
        if (reset) begin
            dispatch2_retained_pending_q <= 1'b0;
            dispatch2_retained_pc_q <= 32'b0;
            dispatch2_retained_instr_q <= 32'b0;
        end else if (dispatch2_retained_flush_clear_c ||
                     dispatch2_retained_replayed_as_slot0_c) begin
            dispatch2_retained_pending_q <= 1'b0;
        end else if (dispatch2_partial_slot0_only_c && decode1_valid_i) begin
            dispatch2_retained_pending_q <= 1'b1;
            dispatch2_retained_pc_q <= decode1_uop_i.pc;
            dispatch2_retained_instr_q <= decode1_uop_i.instr;
        end
    end

    assign rename_fire_o = rename_fire_mask[0];
    assign rename1_fire_o = rename_fire_mask[1];
    assign renamed_uop_o = renamed_uop0;
    assign alloc_tag_o = alloc_tag0;
    // Preserve the legacy observation contract: a held final or legacy buffer
    // packet remains visible even while the consumer-side ready gate is low.
    assign alu_writeback_o =
        dual_wb_final_accept_mask[0] ? dual_wb0_final :
        (dual_wb_final_accept_mask[1] ? dual_wb1_final : wb_buffer_out);
    assign writeback_accepted_o = wb_buffer_out_accepted || (dual_wb_consume_mask != 2'b00);
    assign control_pending_o = control_pending_q;
    assign memory_pending_o = memory_pending_q;
    assign commit_redirect_valid_o =
        (commit_event_o.normal_commit_mask[0] &&
         commit_event_o.slot0.is_control &&
         commit_event_o.slot0.redirect_valid) ||
        (commit_event_o.control_event_valid &&
         (commit_event_o.control_event == BBUS_OOO_CTRL_EXCEPTION));
    always_comb begin
        commit_trap_cause_c = commit_event_o.slot0.exception.valid ?
            commit_event_o.slot0.exception.cause : ecall_cause(priv_mode_q);
        commit_trap_delegated_c = 1'b0;
`ifdef NPC_S_EXTENSION
        commit_trap_delegated_c = (priv_mode_q != 2'b11) &&
            csr_medeleg_q[commit_trap_cause_c[4:0]];
`endif
        commit_trap_target_c = commit_trap_delegated_c ?
            {csr_stvec_q[31:2], 2'b00} : {csr_mtvec_q[31:2], 2'b00};
    end
    assign commit_redirect_pc_o =
        (commit_event_o.control_event_valid &&
         (commit_event_o.control_event == BBUS_OOO_CTRL_EXCEPTION)) ?
        commit_trap_target_c :
        (commit_event_o.slot0.instr == 32'h0000_0073) ? commit_trap_target_c :
        (commit_event_o.slot0.instr == 32'h1020_0073) ? csr_sepc_q :
        commit_event_o.slot0.commit_nextpc;
    // Keep transport reset registered to stay out of the ROB/writeback cone.
    // The supported control/exception path serializes dispatch before this
    // boundary, so the following-cycle pulse kills transport state without
    // claiming general younger-entry recovery.
    assign completion_recovery_event_c =
        commit_redirect_valid_o ||
        commit_event_o.control_event_valid ||
        (commit_event_o.normal_commit_mask[0] &&
         (commit_event_o.slot0.is_csr || commit_event_o.slot0.is_system));
    assign completion_flush_c = completion_flush_q;
    assign debug_rob_head_o = rob_head_idx;
    assign debug_wb_buffer_valid_o = wb_buffer_out_valid;
    assign debug_wb_buffer_phys_o = wb_buffer_out.phys_rd;
    assign debug_wb_buffer_result_o = wb_buffer_out.result;
    assign debug_branch_busy_o = branch_busy;
    assign debug_branch_completion_valid_o = branch_completion_valid;
    assign debug_csr_busy_o = csr_busy_q;
    assign debug_csr_completion_valid_o = csr_completion_valid;
    assign debug_dispatch_valid_o = iq_dispatch_valid || iq_dispatch1_valid;
    assign debug_dispatch_ready_o =
        (iq_dispatch_valid && iq_dispatch_ready) ||
        (iq_dispatch1_valid && iq_dispatch1_ready);
    assign debug_dispatch_fire_o = rename_fire_mask[0];
    assign debug_iq_enqueue_o = |iq_dispatch_fire_mask;
    assign debug_iq_issue_valid_o = iq_issue_valid;
    assign debug_iq_issue_ready_o = iq_issue_ready_to_iq;
    assign debug_issue_fire_o = issue0_fire || issue1_fire;
    assign debug_lsu_completion_valid_o = lsu_completion_valid;
    assign debug_issue0_fire_o = issue0_fire;
    assign debug_issue1_fire_o = issue1_fire;
    assign debug_issue2_fire_o = dual_issue_fire;
    assign debug_alu_alu_dual_issue_o = dual_issue_fire && dual_alu_alu_candidate;
    assign debug_alu_lsu_dual_issue_o = dual_issue_fire && dual_alu_lsu_candidate;
    assign debug_dual_issue_candidate_o = dual_issue_candidate;
    assign debug_dual_issue_candidate_alu_alu_o = dual_issue_candidate_alu_alu;
    assign debug_dual_issue_candidate_alu_lsu_o = dual_issue_candidate_alu_lsu;
    assign debug_dual_issue_candidate_lsu_alu_o = dual_issue_candidate_lsu_alu;
    assign debug_dual_issue_fire_alu_alu_o = dual_issue_fire && dual_issue_candidate_alu_alu;
    assign debug_dual_issue_fire_alu_lsu_o = dual_issue_fire && dual_issue_candidate_alu_lsu;
    assign debug_dual_issue_fire_lsu_alu_o = dual_issue_fire && dual_issue_candidate_lsu_alu;
    assign issue1_suppressed_c = iq_issue1_valid && issue0_fire && !issue1_fire;
    assign debug_issue1_suppressed_o = issue1_suppressed_c;
    assign debug_dual_issue_blocked_by_prf_o = 1'b0;
    assign debug_dual_issue_blocked_by_alu0_busy_o =
        dual_issue_candidate && (!alu_issue_ready_raw || alu0_busy);
    assign debug_dual_issue_blocked_by_alu_busy_o =
        debug_dual_issue_blocked_by_alu0_busy_o;
    assign debug_dual_issue_blocked_by_alu1_busy_o =
        dual_alu_alu_candidate && (!alu1_issue_ready_raw || alu1_busy);
    assign debug_dual_issue_blocked_by_lsu_busy_o =
        dual_alu_lsu_candidate && (!lsu_issue_ready_raw || debug_lsu_busy_o);
    assign debug_dual_issue_blocked_by_wb_o =
        dual_issue_candidate && !wb_buffer_in_ready;
    assign debug_dual_issue_blocked_by_completion_clear_o =
        dual_issue_candidate && completion_any_valid;
    assign debug_dual_issue_blocked_by_serial_o =
        iq_issue_valid && !iq_issue1_valid &&
        (debug_issue_candidate_count_o >= 4'd2) &&
        issue0_serializing_for_pair;
    assign issue1_suppressed_by_fu_busy_c =
        issue1_suppressed_c &&
        (debug_dual_issue_blocked_by_alu0_busy_o ||
         debug_dual_issue_blocked_by_alu1_busy_o ||
         debug_dual_issue_blocked_by_lsu_busy_o);
    assign issue1_suppressed_by_wb_c =
        issue1_suppressed_c &&
        (debug_dual_issue_blocked_by_wb_o ||
         debug_dual_issue_blocked_by_completion_clear_o);
    assign debug_issue1_suppressed_by_policy_o =
        issue1_suppressed_c &&
        !issue1_suppressed_by_fu_busy_c &&
        !issue1_suppressed_by_wb_c;
    assign debug_issue1_suppressed_by_fu_busy_o = issue1_suppressed_by_fu_busy_c;
    assign debug_issue1_suppressed_by_wb_o = issue1_suppressed_by_wb_c;
    assign debug_duplicate_issue_guard_o =
        iq_duplicate_issue_guard ||
        (iq_issue2_pair_valid && (iq_issue_uop.rob_tag == iq_issue1_uop.rob_tag));
    assign debug_dispatch_width_mode_o = dispatch_width2_mode ? 2'd2 : 2'd1;
    assign debug_dispatch2_candidate_o = dispatch2_candidate_c;
    assign debug_dispatch2_fire_o = dispatch_width2_mode && (rename_fire_mask == 2'b11);
    assign debug_dispatch2_slot0_fire_o = dispatch_width2_mode && rename_fire_mask[0];
    assign debug_dispatch2_slot1_fire_o = dispatch_width2_mode && rename_fire_mask[1];
    assign debug_dispatch2_slot1_retained_o =
        dispatch_width2_mode &&
        decode1_valid_i &&
        rename_fire_mask[0] &&
        !rename_fire_mask[1];
    assign debug_dispatch2_blocked_by_rob_o =
        dispatch2_safe_pair_candidate && (rob_dispatch_available_slots < 2'd2);
    assign debug_dispatch2_blocked_by_iq_o =
        dispatch2_safe_pair_candidate && (iq_dispatch_available_slots < 2'd2);
    assign debug_dispatch2_blocked_by_freelist_o =
        dispatch2_safe_pair_candidate &&
        (freelist_dispatch_available_slots < {5'b0, dispatch2_phys_needed});
    assign debug_dispatch2_blocked_by_serial_o =
        dispatch2_candidate_c &&
        (decode_is_serializing(decode_uop_i) || decode_is_serializing(decode1_uop_i));
    assign debug_dispatch2_blocked_by_unsupported_pair_o =
        dispatch2_candidate_c && !decode1_pair_safe && !debug_dispatch2_blocked_by_serial_o;
    assign debug_dispatch2_partial_slot0_only_o = dispatch2_partial_slot0_only_c;
    assign debug_dispatch2_slot1_retained_due_to_rob_o =
        dispatch2_slot1_retained_due_to_rob_c;
    assign debug_dispatch2_slot1_retained_due_to_iq_o =
        dispatch2_slot1_retained_due_to_iq_c;
    assign debug_dispatch2_slot1_retained_due_to_freelist_o =
        dispatch2_slot1_retained_due_to_freelist_c;
    assign debug_dispatch2_slot1_retained_due_to_serial_o =
        dispatch2_slot1_retained_due_to_serial_c;
    assign debug_dispatch2_retained_replayed_as_slot0_o =
        dispatch2_retained_replayed_as_slot0_c;
    assign debug_dispatch2_retained_duplicate_rename_bug_o =
        dispatch2_retained_duplicate_decode_c;
    assign debug_dispatch2_retained_duplicate_phys_bug_o =
        dispatch2_retained_duplicate_decode_c && decode_needs_phys(decode1_uop_i);
    assign debug_dispatch2_retained_duplicate_rob_bug_o =
        dispatch2_retained_duplicate_decode_c;
    assign debug_dispatch2_retained_flush_clear_o =
        dispatch2_retained_flush_clear_c;
    assign debug_rename2_fire_o = dispatch_width2_mode && (rename_fire_mask == 2'b11);
    assign debug_rename2_same_cycle_raw_o =
        dispatch_width2_mode &&
        (rename_fire_mask == 2'b11) &&
        decode_needs_phys(decode_uop_i) &&
        (decode_uop_i.arch_rd != 5'd0) &&
        ((decode1_uop_i.uses_rs1 && (decode1_uop_i.arch_rs1 == decode_uop_i.arch_rd)) ||
         (decode1_uop_i.uses_rs2 && (decode1_uop_i.arch_rs2 == decode_uop_i.arch_rd)));
    assign debug_rename2_same_cycle_waw_o =
        dispatch_width2_mode &&
        (rename_fire_mask == 2'b11) &&
        decode_needs_phys(decode_uop_i) &&
        decode_needs_phys(decode1_uop_i) &&
        (decode_uop_i.arch_rd == decode1_uop_i.arch_rd) &&
        (decode_uop_i.arch_rd != 5'd0);
    assign debug_rob_alloc2_o = dispatch_width2_mode && (rob_alloc_fire_mask == 2'b11);
    assign debug_iq_enqueue2_o = dispatch_width2_mode && (iq_dispatch_fire_mask == 2'b11);
    assign debug_freelist_alloc2_o =
        dispatch_width2_mode &&
        (rename_fire_mask == 2'b11) &&
        decode_needs_phys(decode_uop_i) &&
        decode_needs_phys(decode1_uop_i);
    assign debug_freelist_alloc1_due_to_partial_o =
        dispatch2_partial_slot0_only_c &&
        decode_needs_phys(decode_uop_i);
    assign debug_rob_alloc1_due_to_partial_o =
        dispatch2_partial_slot0_only_c &&
        rob_alloc_fire_mask[0] &&
        !rob_alloc_fire_mask[1];
    assign debug_iq_enqueue1_due_to_partial_o =
        dispatch2_partial_slot0_only_c &&
        iq_dispatch_fire_mask[0] &&
        !iq_dispatch_fire_mask[1];
    assign debug_commit_width_mode_o = rob_commit_width_mode_debug;
    assign debug_commit2_candidate_o = rob_commit2_candidate_debug;
    assign debug_commit2_fire_o = rob_commit2_fire_debug;
    assign debug_commit2_slot0_only_o = rob_commit2_slot0_only_debug;
    assign debug_commit2_block_slot0_not_ready_o =
        rob_commit2_block_slot0_not_ready_debug;
    assign debug_commit2_block_slot1_not_ready_o =
        rob_commit2_block_slot1_not_ready_debug;
    assign debug_commit2_block_slot0_complex_o =
        rob_commit2_block_slot0_complex_debug;
    assign debug_commit2_block_slot1_complex_o =
        rob_commit2_block_slot1_complex_debug;
    assign debug_commit2_rrat_update2_o = rename_commit2_rrat_update2_debug;
    assign debug_commit2_freelist_release2_o =
        rename_commit2_freelist_release2_debug;
    assign debug_commit2_same_rd_waw_o = rename_commit2_same_rd_waw_debug;
    assign debug_commit2_duplicate_release_bug_o =
        rename_commit2_duplicate_release_bug_debug;
    assign debug_commit2_slot1_without_slot0_bug_o =
        rob_commit2_slot1_without_slot0_bug_debug;
    assign debug_commit2_complex_slot_bug_o =
        rob_commit2_complex_slot_bug_debug;
    assign debug_dual_wb_enabled_o = dual_wb_enabled;
    assign debug_dual_wb_raw_fire_o = dual_wb_raw_fire;
    assign debug_dual_wb_final_fire_o = dual_wb_final_fire;
    assign debug_dual_wb_lane1_hold_o = dual_wb_lane1_hold;
    assign debug_dual_wb_lane1_replay_o = dual_wb_lane1_replay;
    assign debug_dual_wb_duplicate_phys_hold_o = dual_wb_duplicate_phys_hold;
    assign debug_dual_wb_duplicate_rob_tag_hold_o = dual_wb_duplicate_rob_tag_hold;
    assign debug_dual_wb_atomicity_guard_o = dual_wb_atomicity_mask_valid;

`ifdef NPC_OOO_COMPLETION_ARB_OLDEST
    assign completion_oldest_mode = 1'b1;
`else
    assign completion_oldest_mode = 1'b0;
`endif
    assign completion_fixed_mode = !completion_oldest_mode;

`ifdef NPC_OOO_ALU_SCHED_BALANCE
    assign alu_sched_balance_mode = 1'b1;
`else
    assign alu_sched_balance_mode = 1'b0;
`endif

    always_comb begin
        rob_alloc0 = '0;
        rob_alloc0.valid = rename_fire_mask[0];
        rob_alloc0.pc = renamed_uop0.pc;
        rob_alloc0.instr = renamed_uop0.instr;
        rob_alloc0.arch_rd = renamed_uop0.arch_rd;
        rob_alloc0.phys_rd_new = renamed_uop0.phys_rd_new;
        rob_alloc0.phys_rd_old = renamed_uop0.phys_rd_old;
        rob_alloc0.rf_wen = renamed_uop0.rf_wen;
        rob_alloc0.fu_type = renamed_uop0.fu_type;
        rob_alloc0.branch_op = renamed_uop0.branch_op;
        rob_alloc0.is_load = renamed_uop0.is_load;
        rob_alloc0.is_store = renamed_uop0.is_store;
        rob_alloc0.is_ebreak = renamed_uop0.is_ebreak && !EBREAK_TRAP_ENABLE;
        rob_alloc0.is_csr = renamed_uop0.is_csr;
        rob_alloc0.is_system = renamed_uop0.is_system;
        rob_alloc0.csr_addr = renamed_uop0.csr_addr;
        rob_alloc0.mem_op = renamed_uop0.mem_op;
        rob_alloc0.exception = renamed_uop0.exception;

        rob_alloc1 = '0;
        rob_alloc1.valid = rename_fire_mask[1];
        rob_alloc1.pc = renamed_uop1.pc;
        rob_alloc1.instr = renamed_uop1.instr;
        rob_alloc1.arch_rd = renamed_uop1.arch_rd;
        rob_alloc1.phys_rd_new = renamed_uop1.phys_rd_new;
        rob_alloc1.phys_rd_old = renamed_uop1.phys_rd_old;
        rob_alloc1.rf_wen = renamed_uop1.rf_wen;
        rob_alloc1.fu_type = renamed_uop1.fu_type;
        rob_alloc1.branch_op = renamed_uop1.branch_op;
        rob_alloc1.is_load = renamed_uop1.is_load;
        rob_alloc1.is_store = renamed_uop1.is_store;
        rob_alloc1.is_ebreak = renamed_uop1.is_ebreak && !EBREAK_TRAP_ENABLE;
        rob_alloc1.is_csr = renamed_uop1.is_csr;
        rob_alloc1.is_system = renamed_uop1.is_system;
        rob_alloc1.csr_addr = renamed_uop1.csr_addr;
        rob_alloc1.mem_op = renamed_uop1.mem_op;
        rob_alloc1.exception = renamed_uop1.exception;

        iq_dispatch_uop = '0;
        iq_dispatch_uop.valid =
            rob_alloc_fire_mask[0] &&
            !renamed_uop0.exception.valid &&
            (!renamed_uop0.is_ebreak || EBREAK_TRAP_ENABLE);
        iq_dispatch_uop.rob_tag = alloc_tag0;
        iq_dispatch_uop.pc = renamed_uop0.pc;
        iq_dispatch_uop.instr = renamed_uop0.instr;
        iq_dispatch_uop.arch_rd = renamed_uop0.arch_rd;
        iq_dispatch_uop.phys_rs1 = renamed_uop0.phys_rs1;
        iq_dispatch_uop.phys_rs2 = renamed_uop0.phys_rs2;
        iq_dispatch_uop.phys_rd_new = renamed_uop0.phys_rd_new;
        iq_dispatch_uop.rf_wen = renamed_uop0.rf_wen;
        iq_dispatch_uop.fu_type = renamed_uop0.fu_type;
        iq_dispatch_uop.branch_op = renamed_uop0.branch_op;
        iq_dispatch_uop.pred_taken = renamed_uop0.pred_taken;
        iq_dispatch_uop.pred_target = renamed_uop0.pred_target;
        iq_dispatch_uop.pred_source = renamed_uop0.pred_source;
        iq_dispatch_uop.pred_correlated = renamed_uop0.pred_correlated;
        iq_dispatch_uop.pred_base_taken = renamed_uop0.pred_base_taken;
        iq_dispatch_uop.pred_base_counter_valid =
            renamed_uop0.pred_base_counter_valid;
        iq_dispatch_uop.pred_base_counter_taken =
            renamed_uop0.pred_base_counter_taken;
        iq_dispatch_uop.pred_corr_candidate = renamed_uop0.pred_corr_candidate;
        iq_dispatch_uop.pred_corr_raw_candidate =
            renamed_uop0.pred_corr_raw_candidate;
        iq_dispatch_uop.pred_corr_chooser_prefer =
            renamed_uop0.pred_corr_chooser_prefer;
        iq_dispatch_uop.pred_corr_taken = renamed_uop0.pred_corr_taken;
        iq_dispatch_uop.pred_history = renamed_uop0.pred_history;
        iq_dispatch_uop.pred_local_history = renamed_uop0.pred_local_history;
        iq_dispatch_uop.pred_local_strong = renamed_uop0.pred_local_strong;
        iq_dispatch_uop.pred_local_taken = renamed_uop0.pred_local_taken;
        iq_dispatch_uop.pred_local_chooser_prefer =
            renamed_uop0.pred_local_chooser_prefer;
        iq_dispatch_uop.pred_local_chooser_strong =
            renamed_uop0.pred_local_chooser_strong;
        iq_dispatch_uop.pred_multihistory_hit =
            renamed_uop0.pred_multihistory_hit;
        iq_dispatch_uop.pred_multihistory_strong =
            renamed_uop0.pred_multihistory_strong;
        iq_dispatch_uop.pred_multihistory_taken =
            renamed_uop0.pred_multihistory_taken;
        iq_dispatch_uop.pred_multihistory_chooser_prefer =
            renamed_uop0.pred_multihistory_chooser_prefer;
        iq_dispatch_uop.pred_multihistory_chooser_strong =
            renamed_uop0.pred_multihistory_chooser_strong;
        iq_dispatch_uop.pred_ras_self_collision =
            renamed_uop0.pred_ras_self_collision;
        iq_dispatch_uop.alu_op = renamed_uop0.alu_op;
        iq_dispatch_uop.mdu_op = renamed_uop0.mdu_op;
        iq_dispatch_uop.atomic_op = renamed_uop0.atomic_op;
        iq_dispatch_uop.aq = renamed_uop0.aq;
        iq_dispatch_uop.rl = renamed_uop0.rl;
        iq_dispatch_uop.is_load = renamed_uop0.is_load;
        iq_dispatch_uop.is_store = renamed_uop0.is_store;
        iq_dispatch_uop.mem_op = renamed_uop0.mem_op;
        iq_dispatch_uop.src1_is_pc = renamed_uop0.src1_is_pc;
        iq_dispatch_uop.src2_is_imm = renamed_uop0.src2_is_imm;
        iq_dispatch_uop.imm = renamed_uop0.imm;
        iq_dispatch_uop.is_csr = renamed_uop0.is_csr;
        iq_dispatch_uop.is_system = renamed_uop0.is_system;
        iq_dispatch_uop.csr_addr = renamed_uop0.csr_addr;
        iq_dispatch_uop.src1_ready = renamed_uop0.src1_ready;
        iq_dispatch_uop.src2_ready = renamed_uop0.src2_ready;

        iq_dispatch1_uop = '0;
        iq_dispatch1_uop.valid =
            rob_alloc_fire_mask[1] &&
            !renamed_uop1.exception.valid &&
            !renamed_uop1.is_ebreak;
        iq_dispatch1_uop.rob_tag = alloc_tag1;
        iq_dispatch1_uop.pc = renamed_uop1.pc;
        iq_dispatch1_uop.instr = renamed_uop1.instr;
        iq_dispatch1_uop.arch_rd = renamed_uop1.arch_rd;
        iq_dispatch1_uop.phys_rs1 = renamed_uop1.phys_rs1;
        iq_dispatch1_uop.phys_rs2 = renamed_uop1.phys_rs2;
        iq_dispatch1_uop.phys_rd_new = renamed_uop1.phys_rd_new;
        iq_dispatch1_uop.rf_wen = renamed_uop1.rf_wen;
        iq_dispatch1_uop.fu_type = renamed_uop1.fu_type;
        iq_dispatch1_uop.branch_op = renamed_uop1.branch_op;
        iq_dispatch1_uop.pred_taken = renamed_uop1.pred_taken;
        iq_dispatch1_uop.pred_target = renamed_uop1.pred_target;
        iq_dispatch1_uop.pred_source = renamed_uop1.pred_source;
        iq_dispatch1_uop.pred_correlated = renamed_uop1.pred_correlated;
        iq_dispatch1_uop.pred_base_taken = renamed_uop1.pred_base_taken;
        iq_dispatch1_uop.pred_base_counter_valid =
            renamed_uop1.pred_base_counter_valid;
        iq_dispatch1_uop.pred_base_counter_taken =
            renamed_uop1.pred_base_counter_taken;
        iq_dispatch1_uop.pred_corr_candidate = renamed_uop1.pred_corr_candidate;
        iq_dispatch1_uop.pred_corr_raw_candidate =
            renamed_uop1.pred_corr_raw_candidate;
        iq_dispatch1_uop.pred_corr_chooser_prefer =
            renamed_uop1.pred_corr_chooser_prefer;
        iq_dispatch1_uop.pred_corr_taken = renamed_uop1.pred_corr_taken;
        iq_dispatch1_uop.pred_history = renamed_uop1.pred_history;
        iq_dispatch1_uop.pred_local_history = renamed_uop1.pred_local_history;
        iq_dispatch1_uop.pred_local_strong = renamed_uop1.pred_local_strong;
        iq_dispatch1_uop.pred_local_taken = renamed_uop1.pred_local_taken;
        iq_dispatch1_uop.pred_local_chooser_prefer =
            renamed_uop1.pred_local_chooser_prefer;
        iq_dispatch1_uop.pred_local_chooser_strong =
            renamed_uop1.pred_local_chooser_strong;
        iq_dispatch1_uop.pred_multihistory_hit =
            renamed_uop1.pred_multihistory_hit;
        iq_dispatch1_uop.pred_multihistory_strong =
            renamed_uop1.pred_multihistory_strong;
        iq_dispatch1_uop.pred_multihistory_taken =
            renamed_uop1.pred_multihistory_taken;
        iq_dispatch1_uop.pred_multihistory_chooser_prefer =
            renamed_uop1.pred_multihistory_chooser_prefer;
        iq_dispatch1_uop.pred_multihistory_chooser_strong =
            renamed_uop1.pred_multihistory_chooser_strong;
        iq_dispatch1_uop.pred_ras_self_collision =
            renamed_uop1.pred_ras_self_collision;
        iq_dispatch1_uop.alu_op = renamed_uop1.alu_op;
        iq_dispatch1_uop.mdu_op = renamed_uop1.mdu_op;
        iq_dispatch1_uop.atomic_op = renamed_uop1.atomic_op;
        iq_dispatch1_uop.aq = renamed_uop1.aq;
        iq_dispatch1_uop.rl = renamed_uop1.rl;
        iq_dispatch1_uop.is_load = renamed_uop1.is_load;
        iq_dispatch1_uop.is_store = renamed_uop1.is_store;
        iq_dispatch1_uop.mem_op = renamed_uop1.mem_op;
        iq_dispatch1_uop.src1_is_pc = renamed_uop1.src1_is_pc;
        iq_dispatch1_uop.src2_is_imm = renamed_uop1.src2_is_imm;
        iq_dispatch1_uop.imm = renamed_uop1.imm;
        iq_dispatch1_uop.is_csr = renamed_uop1.is_csr;
        iq_dispatch1_uop.is_system = renamed_uop1.is_system;
        iq_dispatch1_uop.csr_addr = renamed_uop1.csr_addr;
        iq_dispatch1_uop.src1_ready = renamed_uop1.src1_ready;
        iq_dispatch1_uop.src2_ready = renamed_uop1.src2_ready;
    end

    assign iq_dispatch_valid = iq_dispatch_uop.valid;
    assign iq_dispatch1_valid = iq_dispatch1_uop.valid;

    assign dual_wb_enabled = (`NPC_OOO_DUAL_WB != 0);
    assign dual_wb_non_alu_completion_valid =
        branch_completion_valid || lsu_completion_valid ||
        atomic_completion_valid || csr_completion_valid;
    assign dual_wb_raw_eligible =
        dual_wb_enabled &&
        !dual_wb_held_valid &&
        !wb_buffer_out_valid &&
        !dual_wb_non_alu_completion_valid &&
        (alu0_completion_valid || alu1_completion_valid);
    assign dual_wb_active_cycle =
        dual_wb_enabled &&
        (completion_flush_c || dual_wb_held_valid ||
         (!wb_buffer_out_valid && dual_wb_raw_eligible));
    assign dual_wb0_input = dual_wb_raw_eligible ? alu0_completion_wb : '0;
    assign dual_wb1_input = dual_wb_raw_eligible ? alu1_completion_wb : '0;
    // The wrapper owns transport retention. An offered final lane becomes a
    // consumer lane only after the real ROB accepts its packet.
    // The final offer is a registered transport state. Keep recovery detection
    // out of this combinational accept path: commit_event depends on ROB
    // writeback acceptance, so feeding it back here creates a zero-delay loop.
    // A recovery observed this cycle becomes completion_flush_q for the next
    // cycle, where every transport stage is killed together.
    assign dual_wb_offer_mask =
        (dual_wb_enabled && debug_wb_accept_enable_i && !completion_flush_c) ?
        dual_wb_final_accept_mask : 2'b00;
    assign dual_wb_consume_mask = {
        dual_wb_offer_mask[1] && rob_wb1_accepted_raw,
        dual_wb_offer_mask[0] && rob_wb_accepted_raw
    };
    // The ROB has no transient ready state. Once an offered final lane is not
    // accepted, the packet is stale, duplicate, or otherwise terminally
    // invalid. Tell the wrapper to retire it without exposing it to PRF,
    // ReadyTable, IQ wakeup, or ROB.done consumers.
    assign dual_wb_final_drop_mask = {
        dual_wb_offer_mask[1] && !rob_wb1_accepted_raw,
        dual_wb_offer_mask[0] && !rob_wb_accepted_raw
    };
    // A legacy packet must use the same offer condition for ROB, PRF and
    // wakeup. This prevents a recovery-cycle ROB-only completion update.
    assign legacy_wb_offer_valid =
        !completion_flush_c &&
        debug_wb_accept_enable_i &&
        (dual_wb_final_accept_mask == 2'b00) &&
        wb_buffer_out_valid;
    assign rob_writeback =
        dual_wb_offer_mask[0] ? dual_wb0_final :
        (legacy_wb_offer_valid ? wb_buffer_out : '0);
    assign rob_writeback1 = dual_wb_offer_mask[1] ? dual_wb1_final : '0;
    assign wb_buffer_out_accepted = legacy_wb_offer_valid && rob_wb_accepted_raw;
    // The legacy 1W buffer has the same terminal-rejection requirement as the
    // dual-WB final wrapper. A packet the ROB cannot accept is stale, already
    // done, or malformed, never a transient backpressure condition. Clear it
    // without reporting a consumer acceptance or updating PRF/Ready/IQ.
    assign wb_buffer_out_drop = legacy_wb_offer_valid && !rob_wb_accepted_raw;
    assign wb_prf_write_phys =
        dual_wb_offer_mask[0] ? dual_wb0_final.phys_rd : wb_buffer_out.phys_rd;
    assign wb_prf_write_data =
        dual_wb_offer_mask[0] ? dual_wb0_final.result : wb_buffer_out.result;
    assign wb_prf_write_valid =
        dual_wb_offer_mask[0] ?
            (dual_wb_consume_mask[0] &&
             dual_wb0_final.rf_wen && !dual_wb0_final.exception.valid) :
            (legacy_wb_offer_valid && wb_buffer_out_accepted &&
             wb_buffer_out.rf_wen && !wb_buffer_out.exception.valid);
    assign wb_prf_write1_phys = dual_wb1_final.phys_rd;
    assign wb_prf_write1_data = dual_wb1_final.result;
    assign wb_prf_write1_valid =
        dual_wb_consume_mask[1] &&
        dual_wb1_final.rf_wen &&
        !dual_wb1_final.exception.valid;
    assign wb_readytable_wakeup_phys =
        dual_wb_offer_mask[0] ? dual_wb_wakeup_phys0 : wb_buffer_out.phys_rd;
    assign wb_readytable_wakeup1_phys = dual_wb_wakeup_phys1;
    assign wb_readytable_wakeup_valid =
        (dual_wb_offer_mask[0] ?
            (dual_wb_consume_mask[0] && dual_wb_ordinary_wakeup_valid[0]) :
            wb_prf_write_valid) &&
        debug_wakeup_enable_i;
    assign wb_readytable_wakeup1_valid =
        dual_wb_consume_mask[1] &&
        dual_wb_ordinary_wakeup_valid[1] &&
        debug_wakeup_enable_i;
    assign issue_is_alu = iq_is_alu_like(iq_issue_uop);
    assign issue_is_bru = iq_is_bru(iq_issue_uop);
    assign issue_is_lsu = iq_issue_valid && (iq_issue_uop.fu_type == BBUS_OOO_FU_LSU);
    assign issue_is_lsu_load = iq_is_lsu_load(iq_issue_uop);
    assign issue_is_csr_sys = iq_is_csr_sys(iq_issue_uop);
    assign issue_is_mdu = iq_is_mdu(iq_issue_uop);
    assign issue_is_atomic = iq_is_atomic(iq_issue_uop);
    assign issue1_is_alu = iq_is_alu_like(iq_issue1_uop);
    assign issue1_is_lsu_load = iq_is_lsu_load(iq_issue1_uop);
    assign issue0_serializing_for_pair = iq_is_serializing(iq_issue_uop);
    assign execution_path_clear =
        !alu0_busy &&
        !alu1_busy &&
        !branch_busy &&
        !debug_lsu_busy_o &&
        !csr_busy_q &&
        !mdu_busy &&
        !atomic_busy &&
        !atomic_bridge_busy &&
        !alu0_completion_valid &&
        !alu1_completion_valid &&
        !branch_completion_valid &&
        !lsu_completion_valid &&
        !csr_completion_valid &&
        !atomic_completion_valid &&
        !completion_flush_c;
    assign completion_path_clear =
        !alu0_completion_valid &&
        !alu1_completion_valid &&
        !branch_completion_valid &&
        !lsu_completion_valid &&
        !csr_completion_valid &&
        !atomic_completion_valid &&
        wb_buffer_in_ready &&
        !completion_flush_c;
    assign debug_execution_path_clear_o = execution_path_clear;
    assign dual_issue_candidate =
        iq_issue_valid &&
        iq_issue1_valid &&
        iq_issue2_pair_valid &&
        iq_issue2_pair_legal &&
        legal_issue2_pair(iq_issue_uop, iq_issue1_uop) &&
        (iq_issue_uop.rob_tag != iq_issue1_uop.rob_tag);
    assign dual_alu_lsu_candidate =
        dual_issue_candidate &&
        iq_issue2_pair_is_alu_lsu &&
        legal_alu_lsu_pair(iq_issue_uop, iq_issue1_uop);
    assign dual_alu_alu_candidate =
        dual_issue_candidate &&
        iq_issue2_pair_is_alu_alu &&
        legal_alu_alu_pair(iq_issue_uop, iq_issue1_uop);
    assign dual_issue_candidate_alu_alu = dual_alu_alu_candidate;
    assign dual_issue_candidate_alu_lsu =
        dual_alu_lsu_candidate && issue_is_alu && issue1_is_lsu_load;
    assign dual_issue_candidate_lsu_alu =
        dual_alu_lsu_candidate && issue_is_lsu_load && issue1_is_alu;
    assign alu_issue_allowed =
        issue_is_alu &&
        alu_issue_ready_raw &&
        !alu0_busy &&
        !branch_busy &&
        !csr_busy_q &&
        !mdu_busy &&
        !atomic_busy &&
        completion_path_clear;
    assign alu1_single_issue_candidate =
        issue_is_alu &&
        !dual_issue_candidate &&
        alu0_busy &&
        !alu1_busy &&
        !branch_busy &&
        !csr_busy_q &&
        !mdu_busy &&
        !atomic_busy &&
        alu1_issue_ready_raw;
    assign alu1_single_issue_allowed =
        alu1_single_issue_candidate &&
        completion_path_clear;
    assign alu_sched_balance_blocked_both_busy =
        alu_sched_balance_mode &&
        issue_is_alu &&
        !dual_issue_candidate &&
        alu0_busy &&
        alu1_busy &&
        !branch_busy &&
        !csr_busy_q &&
        !mdu_busy &&
        !atomic_busy;
    assign alu_sched_balance_blocked_wb =
        alu1_single_issue_candidate &&
        !completion_path_clear;
    assign branch_issue_allowed =
        issue_is_bru &&
        branch_issue_ready_raw &&
        execution_path_clear &&
        wb_buffer_in_ready;
    assign lsu_issue_allowed =
        issue_is_lsu &&
        lsu_issue_ready_raw &&
        execution_path_clear &&
        wb_buffer_in_ready;
    assign csr_issue_allowed =
        issue_is_csr_sys &&
        execution_path_clear &&
        wb_buffer_in_ready;
    assign mdu_issue_allowed =
        issue_is_mdu &&
        mdu_issue_ready_raw &&
        execution_path_clear &&
        wb_buffer_in_ready;
    assign atomic_issue_allowed =
        issue_is_atomic &&
        atomic_issue_ready_raw &&
        execution_path_clear &&
        !lsu_commit_store_valid &&
        wb_buffer_in_ready;
    assign dual_alu_lsu_allowed =
        dual_alu_lsu_candidate &&
        alu_issue_ready_raw &&
        lsu_issue_ready_raw &&
        !alu0_busy &&
        !debug_lsu_busy_o &&
        !branch_busy &&
        !csr_busy_q &&
        !mdu_busy &&
        !atomic_busy &&
        completion_path_clear;
    assign dual_alu_alu_allowed =
        dual_alu_alu_candidate &&
        alu_issue_ready_raw &&
        alu1_issue_ready_raw &&
        !alu0_busy &&
        !alu1_busy &&
        !branch_busy &&
        !csr_busy_q &&
        !mdu_busy &&
        !atomic_busy &&
        completion_path_clear;
    assign dual_issue_allowed =
        dual_alu_lsu_allowed ||
        dual_alu_alu_allowed;
    assign dual_issue_fire = debug_alu_issue_enable_i && dual_issue_allowed;
    assign issue0_fire =
        iq_issue_valid &&
        iq_issue_ready_to_iq;
    assign issue1_fire =
        iq_issue1_valid &&
        iq_issue_ready_to_iq &&
        iq_issue1_ready_to_iq;
    assign issue_selected_fu_ready =
        dual_issue_allowed ||
        alu_issue_allowed ||
        alu1_single_issue_allowed ||
        branch_issue_allowed ||
        lsu_issue_allowed ||
        csr_issue_allowed ||
        mdu_issue_allowed ||
        atomic_issue_allowed;
    assign iq_issue_ready_to_iq =
        debug_alu_issue_enable_i &&
        issue_selected_fu_ready &&
        (!iq_issue1_valid || dual_issue_fire);
    assign iq_issue1_ready_to_iq = dual_issue_fire;
    assign debug_issue_fu_ready_o =
        dual_issue_allowed ||
        (issue_is_alu && alu_issue_ready_raw) ||
        (issue_is_alu && alu_sched_balance_mode && alu1_issue_ready_raw) ||
        (issue_is_bru && branch_issue_ready_raw) ||
        (issue_is_lsu && lsu_issue_ready_raw) ||
        issue_is_csr_sys ||
        (issue_is_mdu && mdu_issue_ready_raw) ||
        (issue_is_atomic && atomic_issue_ready_raw &&
         !debug_lsu_busy_o && !lsu_commit_store_valid && !atomic_bridge_busy);
    assign alu_from_issue1 = dual_issue_fire && dual_alu_lsu_candidate && issue1_is_alu;
    assign alu1_single_issue_fire =
        debug_alu_issue_enable_i && !dual_issue_fire && alu1_single_issue_allowed;
    assign alu0_single_issue_fire =
        debug_alu_issue_enable_i && !dual_issue_fire && alu_issue_allowed;
    assign alu1_from_issue0 = alu1_single_issue_fire;
    assign lsu_from_issue1 = dual_issue_fire && dual_alu_lsu_candidate && issue1_is_lsu_load;
    assign alu0_issue_valid =
        (dual_issue_fire && (issue_is_alu || issue1_is_alu)) ||
        alu0_single_issue_fire;
    assign alu1_issue_valid =
        (dual_issue_fire && dual_alu_alu_candidate) ||
        alu1_single_issue_fire;
    assign branch_issue_valid =
        debug_alu_issue_enable_i && !dual_issue_fire && branch_issue_allowed;
    assign lsu_issue_valid =
        (dual_issue_fire && (issue_is_lsu_load || issue1_is_lsu_load)) ||
        (debug_alu_issue_enable_i && !dual_issue_fire && lsu_issue_allowed);
    assign csr_issue_valid =
        debug_alu_issue_enable_i && !dual_issue_fire && csr_issue_allowed;
    assign mdu_issue_valid =
        debug_alu_issue_enable_i && !dual_issue_fire && mdu_issue_allowed;
    assign atomic_issue_valid =
        debug_alu_issue_enable_i && !dual_issue_fire && atomic_issue_allowed;
    assign debug_rob_full_o = (rob_available_slots == 2'd0);
    assign debug_iq_full_o = !iq_dispatch_ready;
    assign debug_wb_accept_o = wb_buffer_out_accepted || (dual_wb_consume_mask != 2'b00);
    assign debug_wb_stall_o = (wb_buffer_in_valid && !wb_buffer_in_ready) || dual_wb_held_valid;
    assign debug_alu_issue_o = alu0_issue_valid || alu1_issue_valid;
    assign debug_branch_issue_o = branch_issue_valid;
    assign debug_lsu_issue_o = lsu_issue_valid;
    assign debug_csr_issue_o = csr_issue_valid;
    assign wb_conflict_alu0_alu1 = alu0_completion_valid && alu1_completion_valid;
    assign wb_conflict_alu_lsu =
        lsu_completion_valid && (alu0_completion_valid || alu1_completion_valid);
    assign wb_conflict_bru_data =
        branch_completion_valid &&
        (alu0_completion_valid || alu1_completion_valid ||
         lsu_completion_valid || atomic_completion_valid ||
         csr_completion_valid);
    assign debug_wb_conflict_alu0_alu1_o = wb_conflict_alu0_alu1;
    assign debug_wb_conflict_alu_lsu_o = wb_conflict_alu_lsu;
    assign debug_wb_conflict_bru_data_o = wb_conflict_bru_data;
    assign debug_alu1_single_issue_o = alu1_single_issue_fire;
    assign debug_alu1_single_issue_when_alu0_busy_o =
        alu1_single_issue_fire && alu0_busy;
    assign debug_alu1_single_issue_when_alu0_idle_o =
        alu1_single_issue_fire && !alu0_busy;
    assign debug_alu_single_issue_redirect_to_alu1_o = alu1_single_issue_fire;
    assign debug_alu0_single_issue_o = alu0_single_issue_fire;
    assign debug_alu0_single_issue_when_alu1_idle_o =
        alu0_single_issue_fire && !alu1_busy;
    assign debug_alu_sched_balance_opportunity_o = alu1_single_issue_candidate;
    assign debug_alu_sched_balance_fire_o = alu1_single_issue_fire;
    assign debug_alu_sched_balance_blocked_both_busy_o =
        alu_sched_balance_blocked_both_busy;
    assign debug_alu_sched_balance_blocked_wb_o =
        alu_sched_balance_blocked_wb;
    assign debug_wb_conflict_o =
        wb_conflict_alu0_alu1 ||
        (alu0_completion_valid && branch_completion_valid) ||
        wb_conflict_alu_lsu ||
        (alu0_completion_valid && csr_completion_valid) ||
        (alu1_completion_valid && branch_completion_valid) ||
        (alu1_completion_valid && csr_completion_valid) ||
        (alu0_completion_valid && atomic_completion_valid) ||
        (alu1_completion_valid && atomic_completion_valid) ||
        (branch_completion_valid && lsu_completion_valid) ||
        (branch_completion_valid && csr_completion_valid) ||
        (branch_completion_valid && atomic_completion_valid) ||
        (lsu_completion_valid && csr_completion_valid) ||
        (lsu_completion_valid && atomic_completion_valid) ||
        (csr_completion_valid && atomic_completion_valid);
    assign completion_any_valid =
        branch_completion_valid || lsu_completion_valid ||
        atomic_completion_valid || csr_completion_valid ||
        alu0_completion_valid || alu1_completion_valid;
    assign fixed_completion_grant_bru = branch_completion_valid;
    assign fixed_completion_grant_lsu = !branch_completion_valid && lsu_completion_valid;
    assign fixed_completion_grant_atomic =
        !branch_completion_valid && !lsu_completion_valid &&
        atomic_completion_valid;
    assign fixed_completion_grant_csr =
        !branch_completion_valid && !lsu_completion_valid &&
        !atomic_completion_valid && csr_completion_valid;
    assign fixed_completion_grant_alu0 =
        !branch_completion_valid && !lsu_completion_valid &&
        !atomic_completion_valid && !csr_completion_valid &&
        alu0_completion_valid;
    assign fixed_completion_grant_alu1 =
        !branch_completion_valid && !lsu_completion_valid &&
        !atomic_completion_valid && !csr_completion_valid &&
        !alu0_completion_valid && alu1_completion_valid;
    assign completion_selected_valid =
        selected_completion_grant_bru || selected_completion_grant_lsu ||
        selected_completion_grant_atomic || selected_completion_grant_csr ||
        selected_completion_grant_alu0 || selected_completion_grant_alu1;
    assign completion_oldest_differs_from_fixed =
        completion_any_valid &&
        ({oldest_completion_grant_bru, oldest_completion_grant_lsu,
          oldest_completion_grant_atomic,
          oldest_completion_grant_csr, oldest_completion_grant_alu0,
          oldest_completion_grant_alu1} !=
         {fixed_completion_grant_bru, fixed_completion_grant_lsu,
          fixed_completion_grant_atomic,
          fixed_completion_grant_csr, fixed_completion_grant_alu0,
          fixed_completion_grant_alu1});
    assign duplicate_completion_tag =
        same_valid_rob_tag(alu0_completion_valid, alu0_completion_wb.rob_tag,
                           alu1_completion_valid, alu1_completion_wb.rob_tag) ||
        same_valid_rob_tag(alu0_completion_valid, alu0_completion_wb.rob_tag,
                           branch_completion_valid, branch_completion_wb.rob_tag) ||
        same_valid_rob_tag(alu0_completion_valid, alu0_completion_wb.rob_tag,
                           lsu_completion_valid, lsu_completion_wb.rob_tag) ||
        same_valid_rob_tag(alu0_completion_valid, alu0_completion_wb.rob_tag,
                           csr_completion_valid, csr_completion_wb.rob_tag) ||
        same_valid_rob_tag(alu1_completion_valid, alu1_completion_wb.rob_tag,
                           branch_completion_valid, branch_completion_wb.rob_tag) ||
        same_valid_rob_tag(alu1_completion_valid, alu1_completion_wb.rob_tag,
                           lsu_completion_valid, lsu_completion_wb.rob_tag) ||
        same_valid_rob_tag(alu1_completion_valid, alu1_completion_wb.rob_tag,
                           csr_completion_valid, csr_completion_wb.rob_tag) ||
        same_valid_rob_tag(branch_completion_valid, branch_completion_wb.rob_tag,
                           lsu_completion_valid, lsu_completion_wb.rob_tag) ||
        same_valid_rob_tag(branch_completion_valid, branch_completion_wb.rob_tag,
                           csr_completion_valid, csr_completion_wb.rob_tag) ||
        same_valid_rob_tag(lsu_completion_valid, lsu_completion_wb.rob_tag,
                           csr_completion_valid, csr_completion_wb.rob_tag) ||
        same_valid_rob_tag(alu0_completion_valid, alu0_completion_wb.rob_tag,
                           atomic_completion_valid, atomic_completion_wb.rob_tag) ||
        same_valid_rob_tag(alu1_completion_valid, alu1_completion_wb.rob_tag,
                           atomic_completion_valid, atomic_completion_wb.rob_tag) ||
        same_valid_rob_tag(branch_completion_valid, branch_completion_wb.rob_tag,
                           atomic_completion_valid, atomic_completion_wb.rob_tag) ||
        same_valid_rob_tag(lsu_completion_valid, lsu_completion_wb.rob_tag,
                           atomic_completion_valid, atomic_completion_wb.rob_tag) ||
        same_valid_rob_tag(csr_completion_valid, csr_completion_wb.rob_tag,
                           atomic_completion_valid, atomic_completion_wb.rob_tag);
    assign completion_arb_no_valid_bug =
        (completion_selected_valid && !completion_any_valid) ||
        (completion_any_valid && !completion_selected_valid);

    always_comb begin
        int unsigned best_age;
        int unsigned candidate_age;
        logic [2:0] best_priority;
        logic best_valid;

        oldest_completion_grant_alu0 = 1'b0;
        oldest_completion_grant_alu1 = 1'b0;
        oldest_completion_grant_bru = 1'b0;
        oldest_completion_grant_lsu = 1'b0;
        oldest_completion_grant_csr = 1'b0;
        oldest_completion_grant_atomic = 1'b0;
        best_age = 0;
        candidate_age = 0;
        best_priority = 3'd0;
        best_valid = 1'b0;

        if (alu1_completion_valid) begin
            oldest_completion_grant_alu1 = 1'b1;
            best_age = rob_age_distance(alu1_completion_wb.rob_tag, rob_head_idx);
            best_priority = 3'd0;
            best_valid = 1'b1;
        end
        if (alu0_completion_valid) begin
            candidate_age = rob_age_distance(alu0_completion_wb.rob_tag, rob_head_idx);
            if (!best_valid || (candidate_age < best_age) ||
                ((candidate_age == best_age) && (3'd1 > best_priority))) begin
                oldest_completion_grant_alu0 = 1'b1;
                oldest_completion_grant_alu1 = 1'b0;
                oldest_completion_grant_bru = 1'b0;
                oldest_completion_grant_lsu = 1'b0;
                oldest_completion_grant_csr = 1'b0;
                oldest_completion_grant_atomic = 1'b0;
                best_age = candidate_age;
                best_priority = 3'd1;
                best_valid = 1'b1;
            end
        end
        if (csr_completion_valid) begin
            candidate_age = rob_age_distance(csr_completion_wb.rob_tag, rob_head_idx);
            if (!best_valid || (candidate_age < best_age) ||
                ((candidate_age == best_age) && (3'd2 > best_priority))) begin
                oldest_completion_grant_alu0 = 1'b0;
                oldest_completion_grant_alu1 = 1'b0;
                oldest_completion_grant_bru = 1'b0;
                oldest_completion_grant_lsu = 1'b0;
                oldest_completion_grant_csr = 1'b1;
                oldest_completion_grant_atomic = 1'b0;
                best_age = candidate_age;
                best_priority = 3'd2;
                best_valid = 1'b1;
            end
        end
        if (atomic_completion_valid) begin
            candidate_age = rob_age_distance(
                atomic_completion_wb.rob_tag, rob_head_idx);
            if (!best_valid || (candidate_age < best_age) ||
                ((candidate_age == best_age) && (3'd3 > best_priority))) begin
                oldest_completion_grant_alu0 = 1'b0;
                oldest_completion_grant_alu1 = 1'b0;
                oldest_completion_grant_bru = 1'b0;
                oldest_completion_grant_lsu = 1'b0;
                oldest_completion_grant_csr = 1'b0;
                oldest_completion_grant_atomic = 1'b1;
                best_age = candidate_age;
                best_priority = 3'd3;
                best_valid = 1'b1;
            end
        end
        if (lsu_completion_valid) begin
            candidate_age = rob_age_distance(lsu_completion_wb.rob_tag, rob_head_idx);
            if (!best_valid || (candidate_age < best_age) ||
                ((candidate_age == best_age) && (3'd4 > best_priority))) begin
                oldest_completion_grant_alu0 = 1'b0;
                oldest_completion_grant_alu1 = 1'b0;
                oldest_completion_grant_bru = 1'b0;
                oldest_completion_grant_lsu = 1'b1;
                oldest_completion_grant_csr = 1'b0;
                oldest_completion_grant_atomic = 1'b0;
                best_age = candidate_age;
                best_priority = 3'd4;
                best_valid = 1'b1;
            end
        end
        if (branch_completion_valid) begin
            candidate_age = rob_age_distance(branch_completion_wb.rob_tag, rob_head_idx);
            if (!best_valid || (candidate_age < best_age) ||
                ((candidate_age == best_age) && (3'd5 > best_priority))) begin
                oldest_completion_grant_alu0 = 1'b0;
                oldest_completion_grant_alu1 = 1'b0;
                oldest_completion_grant_bru = 1'b1;
                oldest_completion_grant_lsu = 1'b0;
                oldest_completion_grant_csr = 1'b0;
                oldest_completion_grant_atomic = 1'b0;
            end
        end
    end

    always_comb begin
        if (completion_oldest_mode) begin
            selected_completion_grant_alu0 = oldest_completion_grant_alu0;
            selected_completion_grant_alu1 = oldest_completion_grant_alu1;
            selected_completion_grant_bru = oldest_completion_grant_bru;
            selected_completion_grant_lsu = oldest_completion_grant_lsu;
            selected_completion_grant_csr = oldest_completion_grant_csr;
            selected_completion_grant_atomic = oldest_completion_grant_atomic;
        end else begin
            selected_completion_grant_alu0 = fixed_completion_grant_alu0;
            selected_completion_grant_alu1 = fixed_completion_grant_alu1;
            selected_completion_grant_bru = fixed_completion_grant_bru;
            selected_completion_grant_lsu = fixed_completion_grant_lsu;
            selected_completion_grant_csr = fixed_completion_grant_csr;
            selected_completion_grant_atomic = fixed_completion_grant_atomic;
        end
    end

    assign alu0_selected_uop = alu_from_issue1 ? iq_issue1_uop : iq_issue_uop;
    assign alu1_selected_uop = alu1_from_issue0 ? iq_issue_uop : iq_issue1_uop;
    assign lsu_selected_uop = lsu_from_issue1 ? iq_issue1_uop : iq_issue_uop;
    assign alu_src1_data =
        alu0_selected_uop.src1_is_pc ? alu0_selected_uop.pc :
        (alu_from_issue1 ? prf1_rs1_data : prf_rs1_data);
    assign alu_src2_data =
        alu0_selected_uop.src2_is_imm ? alu0_selected_uop.imm :
        (alu_from_issue1 ? prf1_rs2_data : prf_rs2_data);
    assign alu1_src1_data =
        alu1_selected_uop.src1_is_pc ? alu1_selected_uop.pc :
        (alu1_from_issue0 ? prf_rs1_data : prf1_rs1_data);
    assign alu1_src2_data =
        alu1_selected_uop.src2_is_imm ? alu1_selected_uop.imm :
        (alu1_from_issue0 ? prf_rs2_data : prf1_rs2_data);
    assign branch_src1_data = prf_rs1_data;
    assign branch_src2_data = prf_rs2_data;
    assign lsu_base_data = lsu_from_issue1 ? prf1_rs1_data : prf_rs1_data;
    assign lsu_store_data = lsu_from_issue1 ? prf1_rs2_data : prf_rs2_data;
    assign csr_local_completion_valid = csr_busy_q;
    assign csr_completion_valid = mdu_completion_valid || csr_local_completion_valid;
    assign csr_completion_wb = mdu_completion_valid ?
        mdu_completion_wb : csr_completion_wb_q;
    assign csr_is_ecall_c = (iq_issue_uop.instr == 32'h0000_0073);
    assign csr_is_mret_c = (iq_issue_uop.instr == 32'h3020_0073);
    assign csr_is_sret_c = (iq_issue_uop.instr == 32'h1020_0073);
    assign csr_is_wfi_c = (iq_issue_uop.instr == 32'h1050_0073);
    assign csr_is_sfence_vma_c =
        (iq_issue_uop.instr[31:25] == 7'b0001001) &&
        (iq_issue_uop.instr[14:7] == 8'b0);
    assign csr_is_fencei_c = (iq_issue_uop.instr == 32'h0000_100f);
    assign csr_is_ebreak_c = (iq_issue_uop.instr == 32'h0010_0073);
    assign csr_read_data_c = csr_read_value(iq_issue_uop.csr_addr);
    assign csr_operand_c = iq_issue_uop.instr[14] ?
        {27'b0, iq_issue_uop.instr[19:15]} :
        prf_rs1_data;

    always_comb begin
        csr_write_c = 1'b0;
        csr_wdata_c = csr_read_data_c;
        unique case (iq_issue_uop.instr[14:12])
            3'b001: begin
                csr_write_c = iq_issue_uop.is_csr;
                csr_wdata_c = csr_operand_c;
            end
            3'b010: begin
                csr_write_c = iq_issue_uop.is_csr && (iq_issue_uop.instr[19:15] != 5'd0);
                csr_wdata_c = csr_read_data_c | csr_operand_c;
            end
            3'b011: begin
                csr_write_c = iq_issue_uop.is_csr && (iq_issue_uop.instr[19:15] != 5'd0);
                csr_wdata_c = csr_read_data_c & ~csr_operand_c;
            end
            3'b101: begin
                csr_write_c = iq_issue_uop.is_csr;
                csr_wdata_c = csr_operand_c;
            end
            3'b110: begin
                csr_write_c = iq_issue_uop.is_csr && (iq_issue_uop.instr[19:15] != 5'd0);
                csr_wdata_c = csr_read_data_c | csr_operand_c;
            end
            3'b111: begin
                csr_write_c = iq_issue_uop.is_csr && (iq_issue_uop.instr[19:15] != 5'd0);
                csr_wdata_c = csr_read_data_c & ~csr_operand_c;
            end
            default: begin
                csr_write_c = 1'b0;
                csr_wdata_c = csr_read_data_c;
            end
        endcase

        csr_access_illegal_c = iq_issue_uop.is_csr &&
            (!csr_implemented(iq_issue_uop.csr_addr) ||
             (priv_mode_q < iq_issue_uop.csr_addr[9:8]) ||
             (csr_write_c && (iq_issue_uop.csr_addr[11:10] == 2'b11)) ||
             ((iq_issue_uop.csr_addr == 12'h180) && (priv_mode_q == 2'b01) &&
              csr_mstatus_q[20]) ||
             !csr_counter_access_ok(
                 iq_issue_uop.csr_addr,
                 priv_mode_q,
                 csr_mcounteren_q,
                 csr_scounteren_q
             ));
        mret_illegal_c = csr_is_mret_c && (priv_mode_q != 2'b11);
`ifdef NPC_S_EXTENSION
        sret_illegal_c = csr_is_sret_c &&
            ((priv_mode_q == 2'b00) || ((priv_mode_q == 2'b01) && csr_mstatus_q[22]));
        wfi_illegal_c = csr_is_wfi_c &&
            ((priv_mode_q == 2'b00) || ((priv_mode_q == 2'b01) && csr_mstatus_q[21]));
        sfence_illegal_c = csr_is_sfence_vma_c &&
            ((priv_mode_q == 2'b00) || ((priv_mode_q == 2'b01) && csr_mstatus_q[20]));
`else
        sret_illegal_c = csr_is_sret_c;
        wfi_illegal_c = csr_is_wfi_c;
        sfence_illegal_c = csr_is_sfence_vma_c;
`endif

        csr_completion_next_c = '0;
        csr_completion_next_c.valid = csr_issue_valid;
        csr_completion_next_c.rob_tag = iq_issue_uop.rob_tag;
        csr_completion_next_c.phys_rd = iq_issue_uop.phys_rd_new;
        csr_completion_next_c.rf_wen = iq_issue_uop.rf_wen &&
            iq_issue_uop.is_csr && !csr_access_illegal_c;
        csr_completion_next_c.result = csr_read_data_c;
        csr_completion_next_c.done = csr_issue_valid;
        csr_completion_next_c.is_control = csr_issue_valid &&
            !(mret_illegal_c || sret_illegal_c) &&
            (csr_is_ecall_c || csr_is_mret_c || csr_is_sret_c || csr_is_fencei_c);
        csr_completion_next_c.actual_taken = csr_issue_valid &&
            (csr_is_ecall_c || csr_is_mret_c || csr_is_sret_c || csr_is_fencei_c);
        csr_completion_next_c.actual_nextpc =
            csr_is_ecall_c ?
`ifdef NPC_S_EXTENSION
                (((priv_mode_q != 2'b11) && csr_medeleg_q[ecall_cause(priv_mode_q)]) ?
                    {csr_stvec_q[31:2], 2'b00} : {csr_mtvec_q[31:2], 2'b00}) :
`else
                {csr_mtvec_q[31:2], 2'b00} :
`endif
            csr_is_mret_c ? csr_mepc_q :
            csr_is_sret_c ? csr_sepc_q :
            (iq_issue_uop.pc + 32'd4);
        csr_completion_next_c.redirect_valid = csr_issue_valid &&
            !(mret_illegal_c || sret_illegal_c) &&
            (csr_is_ecall_c || csr_is_mret_c || csr_is_sret_c || csr_is_fencei_c);
        csr_completion_next_c.is_csr = iq_issue_uop.is_csr && !csr_access_illegal_c;
        csr_completion_next_c.is_system = iq_issue_uop.is_system &&
            !(mret_illegal_c || sret_illegal_c || wfi_illegal_c ||
              sfence_illegal_c || (csr_is_ebreak_c && EBREAK_TRAP_ENABLE));
        csr_completion_next_c.csr_addr = iq_issue_uop.csr_addr;
        csr_completion_next_c.csr_write = csr_write_c && !csr_access_illegal_c;
        csr_completion_next_c.csr_wdata = csr_wdata_c;
        csr_completion_next_c.exception = '0;
        if (csr_access_illegal_c || mret_illegal_c || sret_illegal_c ||
            wfi_illegal_c || sfence_illegal_c) begin
            csr_completion_next_c.rf_wen = 1'b0;
            csr_completion_next_c.is_control = 1'b0;
            csr_completion_next_c.redirect_valid = 1'b0;
            csr_completion_next_c.exception.valid = 1'b1;
            csr_completion_next_c.exception.cause = 32'd2;
            csr_completion_next_c.exception.tval = iq_issue_uop.instr;
        end else if (csr_is_ebreak_c && EBREAK_TRAP_ENABLE) begin
            csr_completion_next_c.rf_wen = 1'b0;
            csr_completion_next_c.exception.valid = 1'b1;
            csr_completion_next_c.exception.cause = 32'd3;
            csr_completion_next_c.exception.tval = 32'b0;
        end
    end

    always_comb begin
        branch_issue_uop = '0;
        branch_issue_uop.valid = branch_issue_valid;
        branch_issue_uop.rob_tag = iq_issue_uop.rob_tag;
        branch_issue_uop.pc = iq_issue_uop.pc;
        branch_issue_uop.instr = iq_issue_uop.instr;
        branch_issue_uop.br_op = iq_issue_uop.branch_op;
        branch_issue_uop.imm = iq_issue_uop.imm;
        branch_issue_uop.pred_taken = iq_issue_uop.pred_taken;
        branch_issue_uop.pred_target = iq_issue_uop.pred_target;
        branch_issue_uop.pred_source = iq_issue_uop.pred_source;
        branch_issue_uop.pred_correlated = iq_issue_uop.pred_correlated;
        branch_issue_uop.pred_base_taken = iq_issue_uop.pred_base_taken;
        branch_issue_uop.pred_base_counter_valid =
            iq_issue_uop.pred_base_counter_valid;
        branch_issue_uop.pred_base_counter_taken =
            iq_issue_uop.pred_base_counter_taken;
        branch_issue_uop.pred_corr_candidate = iq_issue_uop.pred_corr_candidate;
        branch_issue_uop.pred_corr_raw_candidate =
            iq_issue_uop.pred_corr_raw_candidate;
        branch_issue_uop.pred_corr_chooser_prefer =
            iq_issue_uop.pred_corr_chooser_prefer;
        branch_issue_uop.pred_corr_taken = iq_issue_uop.pred_corr_taken;
        branch_issue_uop.pred_history = iq_issue_uop.pred_history;
        branch_issue_uop.pred_local_history = iq_issue_uop.pred_local_history;
        branch_issue_uop.pred_local_strong = iq_issue_uop.pred_local_strong;
        branch_issue_uop.pred_local_taken = iq_issue_uop.pred_local_taken;
        branch_issue_uop.pred_local_chooser_prefer =
            iq_issue_uop.pred_local_chooser_prefer;
        branch_issue_uop.pred_local_chooser_strong =
            iq_issue_uop.pred_local_chooser_strong;
        branch_issue_uop.pred_multihistory_hit =
            iq_issue_uop.pred_multihistory_hit;
        branch_issue_uop.pred_multihistory_strong =
            iq_issue_uop.pred_multihistory_strong;
        branch_issue_uop.pred_multihistory_taken =
            iq_issue_uop.pred_multihistory_taken;
        branch_issue_uop.pred_multihistory_chooser_prefer =
            iq_issue_uop.pred_multihistory_chooser_prefer;
        branch_issue_uop.pred_multihistory_chooser_strong =
            iq_issue_uop.pred_multihistory_chooser_strong;
        branch_issue_uop.pred_ras_self_collision =
            iq_issue_uop.pred_ras_self_collision;
        branch_issue_uop.arch_rd = iq_issue_uop.arch_rd;
        branch_issue_uop.phys_rd = iq_issue_uop.phys_rd_new;
        branch_issue_uop.rf_wen = iq_issue_uop.rf_wen;

        branch_target_misaligned_c = branch_completion.valid &&
            branch_completion.actual_taken && branch_completion.actual_target[1];

        branch_completion_wb = '0;
        branch_completion_wb.valid = branch_completion.valid;
        branch_completion_wb.rob_tag = branch_completion.rob_tag;
        branch_completion_wb.phys_rd = branch_completion.phys_rd;
        branch_completion_wb.rf_wen = branch_completion.rf_wen &&
            !branch_target_misaligned_c;
        branch_completion_wb.result =
            ((branch_completion.br_op == BBUS_OOO_BR_JAL) ||
             (branch_completion.br_op == BBUS_OOO_BR_JALR)) ?
            branch_completion.link_wdata : 32'b0;
        branch_completion_wb.done = branch_completion.valid;
        branch_completion_wb.is_control = branch_completion.valid &&
            !branch_target_misaligned_c;
        branch_completion_wb.is_branch =
            branch_completion.valid && !branch_target_misaligned_c &&
            (branch_completion.br_op != BBUS_OOO_BR_JAL) &&
            (branch_completion.br_op != BBUS_OOO_BR_JALR);
        branch_completion_wb.is_jal =
            branch_completion.valid && !branch_target_misaligned_c &&
            (branch_completion.br_op == BBUS_OOO_BR_JAL);
        branch_completion_wb.is_jalr =
            branch_completion.valid && !branch_target_misaligned_c &&
            (branch_completion.br_op == BBUS_OOO_BR_JALR);
        branch_completion_wb.actual_taken = branch_completion.actual_taken;
        branch_completion_wb.actual_nextpc = branch_completion.actual_target;
        branch_completion_wb.redirect_valid = branch_completion.valid &&
            !branch_target_misaligned_c;
        branch_completion_wb.exception = '0;
        branch_completion_wb.exception.valid = branch_target_misaligned_c;
        branch_completion_wb.exception.cause = branch_target_misaligned_c ?
            32'd0 : 32'b0;
        branch_completion_wb.exception.tval = branch_target_misaligned_c ?
            branch_completion.actual_target : 32'b0;

        lsu_issue_uop = '0;
        lsu_issue_uop.valid = lsu_issue_valid;
        lsu_issue_uop.rob_tag = lsu_selected_uop.rob_tag;
        lsu_issue_uop.pc = lsu_selected_uop.pc;
        lsu_issue_uop.instr = lsu_selected_uop.instr;
        lsu_issue_uop.arch_rd = lsu_selected_uop.arch_rd;
        lsu_issue_uop.phys_rd = lsu_selected_uop.phys_rd_new;
        lsu_issue_uop.rf_wen = lsu_selected_uop.rf_wen;
        lsu_issue_uop.is_load = lsu_selected_uop.is_load;
        lsu_issue_uop.is_store = lsu_selected_uop.is_store;
        lsu_issue_uop.mem_op = lsu_selected_uop.mem_op;
        lsu_issue_uop.imm = lsu_selected_uop.imm;
    end

    always_comb begin
        if (selected_completion_grant_bru) begin
            wb_buffer_in = branch_completion_wb;
        end else if (selected_completion_grant_lsu) begin
            wb_buffer_in = lsu_completion_wb;
        end else if (selected_completion_grant_atomic) begin
            wb_buffer_in = atomic_completion_wb;
        end else if (selected_completion_grant_csr) begin
            wb_buffer_in = csr_completion_wb;
        end else if (selected_completion_grant_alu0) begin
            wb_buffer_in = alu0_completion_wb;
        end else if (selected_completion_grant_alu1) begin
            wb_buffer_in = alu1_completion_wb;
        end else begin
            wb_buffer_in = '0;
        end
        wb_buffer_in_valid = completion_selected_valid && !dual_wb_active_cycle;
    end

    generate
        if (`NPC_OOO_DUAL_WB != 0) begin : gen_dual_wb_wrapper
            ooo_dual_wb_buffered_wrapper_2w u_dual_wb_wrapper (
                .clk(clk),
                .reset(reset),
                .wb0_i(dual_wb0_input),
                .wb1_i(dual_wb1_input),
                .wb0_rob_match_i(rob_probe0_match),
                .wb1_rob_match_i(rob_probe1_match),
                .wb0_killed_i(completion_flush_c),
                .wb1_killed_i(completion_flush_c),
                .lane0_consumer_block_i(1'b0),
                .lane1_consumer_block_i(1'b0),
                .lane1_buffer_full_i(1'b0),
                .lane1_ordering_block_i(1'b0),
                .final_consumer_ready_i(debug_wb_accept_enable_i && !completion_flush_c),
                .final_consumer_accept_mask_i(dual_wb_consume_mask),
                .final_consumer_drop_mask_i(dual_wb_final_drop_mask),
                .flush_i(completion_flush_c),
                .raw_accept_mask_o(dual_wb_raw_accept_mask),
                .source_accept_mask_o(dual_wb_source_accept_mask),
                .source_drop_mask_o(dual_wb_source_drop_mask),
                .source_clear_mask_o(dual_wb_source_clear_mask),
                .final_accept_mask_o(dual_wb_final_accept_mask),
                .final_drop_mask_o(),
                .hold_mask_o(dual_wb_hold_mask),
                .wb0_final_o(dual_wb0_final),
                .wb1_final_o(dual_wb1_final),
                .ordinary_wakeup_valid_final_o(dual_wb_ordinary_wakeup_valid),
                .wakeup_phys0_final_o(dual_wb_wakeup_phys0),
                .wakeup_phys1_final_o(dual_wb_wakeup_phys1),
                .pending_count_o(dual_wb_pending_count),
                .buffer_full_o(dual_wb_buffer_full),
                .buffer_empty_o(dual_wb_buffer_empty),
                .enqueue_mask_o(dual_wb_enqueue_mask),
                .dequeue_mask_o(dual_wb_dequeue_mask),
                .dual_wb_raw_fire_o(dual_wb_raw_fire),
                .dual_wb_final_fire_o(dual_wb_final_fire),
                .lane1_hold_o(dual_wb_lane1_hold),
                .lane1_replay_o(dual_wb_lane1_replay),
                .duplicate_phys_hold_o(dual_wb_duplicate_phys_hold),
                .duplicate_rob_tag_hold_o(dual_wb_duplicate_rob_tag_hold),
                .lane0_block_hold_o(dual_wb_lane0_block_hold),
                .lane1_consumer_block_hold_o(dual_wb_lane1_consumer_block_hold),
                .lane1_buffer_full_hold_o(dual_wb_lane1_buffer_full_hold),
                .lane1_ordering_block_hold_o(dual_wb_lane1_ordering_block_hold),
                .buffer_full_hold_o(dual_wb_buffer_full_hold),
                .stale_drop0_o(dual_wb_stale_drop0),
                .stale_drop1_o(dual_wb_stale_drop1),
                .killed_drop0_o(dual_wb_killed_drop0),
                .killed_drop1_o(dual_wb_killed_drop1),
                .exception_no_wakeup0_o(dual_wb_exception_no_wakeup0),
                .exception_no_wakeup1_o(dual_wb_exception_no_wakeup1),
                .p0_wakeup_suppressed0_o(dual_wb_p0_wakeup_suppressed0),
                .p0_wakeup_suppressed1_o(dual_wb_p0_wakeup_suppressed1),
                .atomicity_mask_valid_o(dual_wb_atomicity_mask_valid),
                .conservation_error_o(dual_wb_conservation_error)
            );
            assign dual_wb_held_valid =
                !dual_wb_buffer_empty || (dual_wb_final_accept_mask != 2'b00);
            assign dual_wb_held_wb = '0;
            assign dual_wb_held_blocked = dual_wb_buffer_full_hold;
        end else begin : gen_no_dual_wb_wrapper
            assign dual_wb_source_accept_mask = 2'b00;
            assign dual_wb_source_drop_mask = 2'b00;
            assign dual_wb_source_clear_mask = 2'b00;
            assign dual_wb_raw_accept_mask = 2'b00;
            assign dual_wb_final_accept_mask = 2'b00;
            assign dual_wb_hold_mask = 2'b00;
            assign dual_wb0_final = '0;
            assign dual_wb1_final = '0;
            assign dual_wb_ordinary_wakeup_valid = 2'b00;
            assign dual_wb_wakeup_phys0 = '0;
            assign dual_wb_wakeup_phys1 = '0;
            assign dual_wb_held_valid = 1'b0;
            assign dual_wb_held_wb = '0;
            assign dual_wb_pending_count = 2'b00;
            assign dual_wb_buffer_full = 1'b0;
            assign dual_wb_buffer_empty = 1'b1;
            assign dual_wb_enqueue_mask = 2'b00;
            assign dual_wb_dequeue_mask = 2'b00;
            assign dual_wb_raw_fire = 1'b0;
            assign dual_wb_final_fire = 1'b0;
            assign dual_wb_lane1_hold = 1'b0;
            assign dual_wb_lane1_replay = 1'b0;
            assign dual_wb_duplicate_phys_hold = 1'b0;
            assign dual_wb_duplicate_rob_tag_hold = 1'b0;
            assign dual_wb_lane0_block_hold = 1'b0;
            assign dual_wb_lane1_consumer_block_hold = 1'b0;
            assign dual_wb_lane1_buffer_full_hold = 1'b0;
            assign dual_wb_lane1_ordering_block_hold = 1'b0;
            assign dual_wb_held_blocked = 1'b0;
            assign dual_wb_buffer_full_hold = 1'b0;
            assign dual_wb_conservation_error = 1'b0;
            assign dual_wb_stale_drop0 = 1'b0;
            assign dual_wb_stale_drop1 = 1'b0;
            assign dual_wb_killed_drop0 = 1'b0;
            assign dual_wb_killed_drop1 = 1'b0;
            assign dual_wb_exception_no_wakeup0 = 1'b0;
            assign dual_wb_exception_no_wakeup1 = 1'b0;
            assign dual_wb_p0_wakeup_suppressed0 = 1'b0;
            assign dual_wb_p0_wakeup_suppressed1 = 1'b0;
            assign dual_wb_atomicity_mask_valid = 1'b0;
        end
    endgenerate

    rename_prf_core u_rename (
        .clk(clk),
        .reset(reset),
        .decode_valid_mask_i(decode_valid_mask),
        .decode_uop0_i(decode_uop_i),
        .decode_uop1_i(dispatch_width2_mode ? decode1_uop_i : decode_uop1_zero),
        .dispatch_slots_available_i(dispatch_slots_available),
        .rename_fire_mask_o(rename_fire_mask),
        .renamed_uop0_o(renamed_uop0),
        .renamed_uop1_o(renamed_uop1),
        .commit_event_i(commit_event_o),
        .wb_ready_valid_i(wb_readytable_wakeup_valid),
        .wb_ready_phys_i(wb_readytable_wakeup_phys),
        .wb_ready1_valid_i(wb_readytable_wakeup1_valid),
        .wb_ready1_phys_i(wb_readytable_wakeup1_phys),
        .debug_arch_idx_i(debug_arch_idx_i),
        .debug_phys_idx_i(debug_phys_idx_i),
        .debug_rat_phys_o(debug_rat_phys_o),
        .debug_rrat_phys_o(debug_rrat_phys_o),
        .debug_ready_o(debug_ready_o),
        .debug_free_count_o(debug_free_count_o),
        .debug_next_free_phys_o(debug_next_free_phys_o),
        .debug_commit2_rrat_update2_o(rename_commit2_rrat_update2_debug),
        .debug_commit2_freelist_release2_o(rename_commit2_freelist_release2_debug),
        .debug_commit2_same_rd_waw_o(rename_commit2_same_rd_waw_debug),
        .debug_commit2_duplicate_release_bug_o(rename_commit2_duplicate_release_bug_debug)
    );

    small_rob #(
        .COMMIT2_ENABLE(`NPC_OOO_COMMIT_WIDTH >= 2)
    ) u_rob (
        .clk(clk),
        .reset(reset),
        .flush_i(1'b0),
        .alloc_valid_mask_i(rename_fire_mask),
        .alloc_slot0_i(rob_alloc0),
        .alloc_slot1_i(rob_alloc1),
        .alloc_fire_mask_o(rob_alloc_fire_mask),
        .alloc_tag0_o(alloc_tag0),
        .alloc_tag1_o(alloc_tag1),
        .selective_squash_valid_i(1'b0),
        .selective_squash_branch_tag_i('0),
        .selective_squash_post_tail_tag_i('0),
        .selective_squash_ready_o(selective_unused_ready),
        .selective_squash_fire_o(selective_unused_fire),
        .selective_killed_rob_mask_o(selective_unused_killed_rob_mask),
        .selective_killed_phys_mask_o(selective_unused_killed_phys_mask),
        .selective_killed_count_o(selective_unused_killed_count),
        .selective_squash_identity_error_o(selective_unused_identity_error),
        .available_slots_o(rob_available_slots),
        .writeback_i(rob_writeback),
        .writeback_accepted_o(rob_wb_accepted_raw),
        .writeback1_i(rob_writeback1),
        .writeback1_accepted_o(rob_wb1_accepted_raw),
        .writeback_probe0_i(alu0_completion_wb),
        .writeback_probe1_i(alu1_completion_wb),
        .writeback_probe0_match_o(rob_probe0_match),
        .writeback_probe1_match_o(rob_probe1_match),
        .raw_probe_valid_mask_i('0),
        .raw_probe_wb_i('{default:'0}),
        .raw_probe_fresh_mask_o(),
        .commit_enable_i(commit_enable_i),
        .commit_store_valid_o(lsu_commit_store_valid),
        .commit_store_ready_i(lsu_commit_store_ready),
        .commit_store_accept_is_done_i(1'b0),
        .commit_store_done_i(lsu_commit_store_done),
        .commit_store_rob_tag_o(),
        .commit_store_done_rob_tag_i('0),
        .commit_store_done_match_o(),
        .commit_store_done_drop_o(),
        .commit_store_done_clear_o(),
        .commit_store_addr_o(lsu_commit_store_addr),
        .commit_store_wdata_o(lsu_commit_store_wdata),
        .commit_store_wstrb_o(lsu_commit_store_wstrb),
        .commit_store_len_o(lsu_commit_store_len),
        .commit_event_o(commit_event_o),
        .debug_commit_width_mode_o(rob_commit_width_mode_debug),
        .debug_commit2_candidate_o(rob_commit2_candidate_debug),
        .debug_commit2_fire_o(rob_commit2_fire_debug),
        .debug_commit2_slot0_only_o(rob_commit2_slot0_only_debug),
        .debug_commit2_block_slot0_not_ready_o(rob_commit2_block_slot0_not_ready_debug),
        .debug_commit2_block_slot1_not_ready_o(rob_commit2_block_slot1_not_ready_debug),
        .debug_commit2_block_slot0_complex_o(rob_commit2_block_slot0_complex_debug),
        .debug_commit2_block_slot1_complex_o(rob_commit2_block_slot1_complex_debug),
        .debug_commit2_slot1_without_slot0_bug_o(rob_commit2_slot1_without_slot0_bug_debug),
        .debug_commit2_complex_slot_bug_o(rob_commit2_complex_slot_bug_debug),
        .debug_rob_idx_i(debug_rob_idx_i),
        .debug_rob_valid_o(debug_rob_valid_o),
        .debug_rob_done_o(debug_rob_done_o),
        .debug_rob_result_o(debug_rob_result_o),
        .debug_rob_count_o(debug_rob_count_o),
        .debug_rob_head_o(rob_head_idx),
        .debug_rob_tail_o(debug_rob_tail_o),
        .rob_head_tag_o(rob_head_tag)
    );

    alu_issue_queue_1w u_iq (
        .clk(clk),
        .reset(reset),
        .flush_i(completion_flush_c),
        .selective_kill_valid_i(1'b0), .selective_killed_rob_mask_i('0),
        .selective_killed_count_o(),
        .rob_head_i(rob_head_idx),
        .rob_head_tag_i(rob_head_tag),
        .alu0_available_i(
            alu_issue_ready_raw && !alu0_busy && !branch_busy &&
            !csr_busy_q && !mdu_busy && completion_path_clear),
        .alu1_available_i(
            alu1_issue_ready_raw && !alu1_busy && !branch_busy &&
            !csr_busy_q && !mdu_busy && completion_path_clear),
        .lsu_available_i(
            lsu_issue_ready_raw && execution_path_clear && wb_buffer_in_ready),
        .bru_available_i(
            branch_issue_ready_raw && execution_path_clear && wb_buffer_in_ready),
        .csr_sys_available_i(execution_path_clear && wb_buffer_in_ready),
        .atomic_available_i(
            atomic_issue_ready_raw && execution_path_clear &&
            !lsu_commit_store_valid && wb_buffer_in_ready),
        .dispatch_valid_i(iq_dispatch_valid),
        .dispatch_uop_i(iq_dispatch_uop),
        .dispatch1_valid_i(iq_dispatch1_valid),
        .dispatch1_uop_i(iq_dispatch1_uop),
        .dispatch_ready_o(iq_dispatch_ready),
        .dispatch1_ready_o(iq_dispatch1_ready),
        .dispatch_ready_count_o(iq_dispatch_ready_count),
        .dispatch_fire_mask_o(iq_dispatch_fire_mask),
        .wakeup_valid_i(wb_readytable_wakeup_valid),
        .wakeup_phys_i(wb_readytable_wakeup_phys),
        .wakeup1_valid_i(wb_readytable_wakeup1_valid),
        .wakeup1_phys_i(wb_readytable_wakeup1_phys),
        .issue_valid_o(iq_issue_valid),
        .issue_uop_o(iq_issue_uop),
        .issue_ready_i(iq_issue_ready_to_iq),
        .issue1_valid_o(iq_issue1_valid),
        .issue1_uop_o(iq_issue1_uop),
        .issue1_ready_i(iq_issue1_ready_to_iq),
        .issue2_pair_valid_o(iq_issue2_pair_valid),
        .issue2_pair_is_alu_lsu_o(iq_issue2_pair_is_alu_lsu),
        .issue2_pair_is_alu_alu_o(iq_issue2_pair_is_alu_alu),
        .issue2_pair_legal_o(iq_issue2_pair_legal),
        .debug_count_o(debug_iq_count_o),
        .debug_ready_count_o(debug_iq_ready_count_o),
        .debug_ready_alu_count_o(debug_iq_ready_alu_count_o),
        .debug_ready_lsu_count_o(debug_iq_ready_lsu_count_o),
        .debug_ready_bru_count_o(debug_iq_ready_bru_count_o),
        .debug_ready_csr_sys_count_o(debug_iq_ready_csr_sys_count_o),
        .debug_ready_any_count_o(debug_iq_ready_any_count_o),
        .debug_issue_candidate_count_o(debug_issue_candidate_count_o),
        .debug_issue_multi_candidate_o(debug_issue_multi_candidate_o),
        .debug_issue0_fire_o(),
        .debug_issue1_fire_o(),
        .debug_issue2_fire_o(),
        .debug_duplicate_issue_guard_o(iq_duplicate_issue_guard)
    );

    ooo_prf u_prf (
        .clk(clk),
        .reset(reset),
        .read_rs1_phys_i(iq_issue_uop.phys_rs1),
        .read_rs2_phys_i(iq_issue_uop.phys_rs2),
        .read_rs1_data_o(prf_rs1_data),
        .read_rs2_data_o(prf_rs2_data),
        .read1_rs1_phys_i(iq_issue1_uop.phys_rs1),
        .read1_rs2_phys_i(iq_issue1_uop.phys_rs2),
        .read1_rs1_data_o(prf1_rs1_data),
        .read1_rs2_data_o(prf1_rs2_data),
        .write_valid_i(wb_prf_write_valid),
        .write_phys_i(wb_prf_write_phys),
        .write_data_i(wb_prf_write_data),
        .write1_valid_i(wb_prf_write1_valid),
        .write1_phys_i(wb_prf_write1_phys),
        .write1_data_i(wb_prf_write1_data),
        .debug_phys_idx_i(debug_prf_phys_idx_i),
        .debug_data_o(debug_prf_data_o)
    );

    ooo_alu #(
        .LATENCY(ALU_LATENCY),
        .PIPELINED(1'b0)
    ) u_alu0 (
        .clk(clk),
        .reset(reset),
        .issue_valid_i(alu0_issue_valid),
        .issue_uop_i(alu0_selected_uop),
        .src1_data_i(alu_src1_data),
        .src2_data_i(alu_src2_data),
        .issue_ready_o(alu_issue_ready_raw),
        .completion_wb_o(alu0_completion_wb),
        .completion_valid_o(alu0_completion_valid),
        .completion_ready_i(alu0_completion_ready),
        .debug_busy_o(alu0_busy),
        .debug_completion_valid_o(debug_alu0_done_o)
    );

    ooo_alu #(
        .LATENCY(ALU1_LATENCY),
        .PIPELINED(1'b0)
    ) u_alu1 (
        .clk(clk),
        .reset(reset),
        .issue_valid_i(alu1_issue_valid),
        .issue_uop_i(alu1_selected_uop),
        .src1_data_i(alu1_src1_data),
        .src2_data_i(alu1_src2_data),
        .issue_ready_o(alu1_issue_ready_raw),
        .completion_wb_o(alu1_completion_wb),
        .completion_valid_o(alu1_completion_valid),
        .completion_ready_i(alu1_completion_ready),
        .debug_busy_o(alu1_busy),
        .debug_completion_valid_o(debug_alu1_done_o)
    );

    ooo_branch_execute u_branch_execute (
        .clk(clk),
        .reset(reset),
        .issue_valid_i(branch_issue_valid),
        .issue_completion_fallthrough_i(1'b1),
        .issue_ready_o(branch_issue_ready_raw),
        .issue_uop_i(branch_issue_uop),
        .src1_data_i(branch_src1_data),
        .src2_data_i(branch_src2_data),
        .completion_valid_o(branch_completion_valid),
        .completion_ready_i(branch_completion_ready),
        .completion_o(branch_completion),
        .redirect_valid_o(branch_redirect_valid),
        .redirect_o(branch_redirect),
        .debug_busy_o(branch_busy),
        .debug_completion_valid_o(branch_debug_completion_valid)
    );

    ooo_lsu #(
        .DPI_CHANNEL(1)
    ) u_lsu (
        .clk(clk),
        .reset(reset),
        .issue_valid_i(lsu_issue_valid_to_unit),
        .issue_ready_o(lsu_issue_ready_raw),
        .issue_uop_i(lsu_issue_uop),
        .base_data_i(lsu_base_data),
        .store_data_i(lsu_store_data),
        .completion_valid_o(lsu_completion_valid),
        .completion_ready_i(lsu_completion_ready),
        .completion_wb_o(lsu_completion_wb),
        .commit_store_valid_i(lsu_commit_store_valid_to_unit),
        .commit_store_ready_o(lsu_commit_store_ready_raw),
        .commit_store_addr_i(lsu_commit_store_addr),
        .commit_store_wdata_i(lsu_commit_store_wdata),
        .commit_store_len_i(lsu_commit_store_len),
        .commit_store_done_o(lsu_commit_store_done),
        .debug_busy_o(debug_lsu_busy_o),
        .debug_mem_req_valid_o(lsu_debug_mem_req_valid),
        .debug_mem_resp_valid_o(lsu_debug_mem_resp_valid)
    );

    assign lsu_issue_valid_to_unit =
        lsu_issue_valid && !atomic_memory_lock && !atomic_bridge_busy;
    assign lsu_commit_store_valid_to_unit =
        lsu_commit_store_valid && !atomic_memory_lock && !atomic_bridge_busy;
    assign lsu_commit_store_ready =
        lsu_commit_store_ready_raw && !atomic_memory_lock &&
        !atomic_bridge_busy;

`ifdef NPC_A_EXTENSION
    assign atomic_commit_valid =
        commit_event_o.normal_commit_mask[0] &&
        (commit_event_o.slot0.fu_type == BBUS_OOO_FU_AMO);
    assign atomic_commit_tag = commit_event_o.slot0.rob_tag;

    ooo_atomic_pipeline_1w u_atomic (
        .clk(clk),
        .reset(reset),
        .flush_i(completion_flush_c),
        .issue_valid_i(atomic_issue_valid),
        .issue_uop_i(iq_issue_uop),
        .address_i(prf_rs1_data),
        .operand_i(prf_rs2_data),
        .issue_ready_o(atomic_issue_ready_raw),
        .issue_accept_o(),
        .mem_req_valid_o(atomic_mem_req_valid),
        .mem_req_ready_i(atomic_mem_req_ready),
        .mem_req_write_o(atomic_mem_req_write),
        .mem_req_addr_o(atomic_mem_req_addr),
        .mem_req_wdata_o(atomic_mem_req_wdata),
        .mem_req_wstrb_o(atomic_mem_req_wstrb),
        .mem_req_len_o(atomic_mem_req_len),
        .mem_rsp_valid_i(atomic_mem_rsp_valid),
        .mem_rsp_ready_o(atomic_mem_rsp_ready),
        .mem_rsp_rdata_i(atomic_mem_rsp_rdata),
        .mem_rsp_error_i(atomic_mem_rsp_error),
        .completion_valid_o(atomic_completion_valid),
        .completion_ready_i(atomic_completion_ready),
        .completion_wb_o(atomic_completion_wb),
        .commit_valid_i(atomic_commit_valid),
        .commit_rob_tag_i(atomic_commit_tag),
        .reservation_invalidate_i(lsu_commit_store_done),
        .occupied_o(atomic_busy),
        .memory_lock_o(atomic_memory_lock),
        .write_request_fire_o(atomic_write_request_fire),
        .recovery_block_o(atomic_recovery_block),
        .killed_read_drain_o(atomic_killed_read_drain),
        .illegal_issue_o(atomic_illegal_issue),
        .flush_drop_o(atomic_flush_drop),
        .reservation_valid_o(atomic_reservation_valid),
        .reservation_addr_o(atomic_reservation_addr),
        .sc_success_o(atomic_sc_success),
        .sc_failure_o(atomic_sc_failure),
        .irreversible_flush_error_o(atomic_irreversible_flush_error),
        .conservation_error_o(atomic_conservation_error)
    );

    ooo_pipeline_dpi_mem_bridge_1w #(
        .DPI_CHANNEL(1)
    ) u_atomic_mem_bridge (
        .clk(clk),
        .reset(reset),
        .req_valid_i(atomic_mem_req_valid),
        .req_ready_o(atomic_mem_req_ready),
        .req_write_i(atomic_mem_req_write),
        .req_addr_i(atomic_mem_req_addr),
        .req_wdata_i(atomic_mem_req_wdata),
        .req_wstrb_i(atomic_mem_req_wstrb),
        .req_len_i(atomic_mem_req_len),
        .rsp_valid_o(atomic_mem_rsp_valid),
        .rsp_ready_i(atomic_mem_rsp_ready),
        .rsp_rdata_o(atomic_mem_rsp_rdata),
        .rsp_error_o(atomic_mem_rsp_error),
        .busy_o(atomic_bridge_busy),
        .req_fire_o(atomic_bridge_req_fire),
        .rsp_capture_o(atomic_bridge_rsp_capture),
        .rsp_fire_o(atomic_bridge_rsp_fire),
        .protocol_error_o(atomic_bridge_protocol_error)
    );
`else
    assign atomic_issue_ready_raw = 1'b0;
    assign atomic_completion_valid = 1'b0;
    assign atomic_completion_wb = '0;
    assign atomic_busy = 1'b0;
    assign atomic_memory_lock = 1'b0;
    assign atomic_write_request_fire = 1'b0;
    assign atomic_recovery_block = 1'b0;
    assign atomic_killed_read_drain = 1'b0;
    assign atomic_illegal_issue = 1'b0;
    assign atomic_flush_drop = 1'b0;
    assign atomic_reservation_valid = 1'b0;
    assign atomic_reservation_addr = 32'b0;
    assign atomic_sc_success = 1'b0;
    assign atomic_sc_failure = 1'b0;
    assign atomic_irreversible_flush_error = 1'b0;
    assign atomic_conservation_error = 1'b0;
    assign atomic_commit_valid = 1'b0;
    assign atomic_commit_tag = '0;
    assign atomic_mem_req_valid = 1'b0;
    assign atomic_mem_req_write = 1'b0;
    assign atomic_mem_req_addr = 32'b0;
    assign atomic_mem_req_wdata = 32'b0;
    assign atomic_mem_req_wstrb = 4'b0;
    assign atomic_mem_req_len = 3'b0;
    assign atomic_mem_req_ready = 1'b0;
    assign atomic_mem_rsp_valid = 1'b0;
    assign atomic_mem_rsp_ready = 1'b0;
    assign atomic_mem_rsp_rdata = 32'b0;
    assign atomic_mem_rsp_error = 1'b0;
    assign atomic_bridge_busy = 1'b0;
    assign atomic_bridge_req_fire = 1'b0;
    assign atomic_bridge_rsp_capture = 1'b0;
    assign atomic_bridge_rsp_fire = 1'b0;
    assign atomic_bridge_protocol_error = 1'b0;
`endif

`ifdef NPC_M_EXTENSION
    ooo_mdu_pipeline_1w u_mdu (
        .clk(clk),
        .reset(reset),
        .flush_i(completion_flush_c),
        .selective_kill_valid_i(1'b0), .selective_killed_rob_mask_i('0),
        .selective_kill_drop_o(),
        .issue_valid_i(mdu_issue_valid),
        .issue_uop_i(iq_issue_uop),
        .src1_data_i(prf_rs1_data),
        .src2_data_i(prf_rs2_data),
        .issue_ready_o(mdu_issue_ready_raw),
        .issue_accept_o(),
        .completion_wb_o(mdu_completion_wb),
        .completion_valid_o(mdu_completion_valid),
        .completion_ready_i(mdu_completion_ready),
        .occupied_o(mdu_busy),
        .flush_drop_o(mdu_flush_drop),
        .illegal_issue_o(mdu_illegal_issue)
    );
`else
    assign mdu_issue_ready_raw = 1'b0;
    assign mdu_completion_valid = 1'b0;
    assign mdu_completion_wb = '0;
    assign mdu_busy = 1'b0;
    assign mdu_flush_drop = 1'b0;
    assign mdu_illegal_issue = 1'b0;
`endif

    assign alu0_completion_ready =
        dual_wb_active_cycle ? dual_wb_source_clear_mask[0] :
        (selected_completion_grant_alu0 && wb_buffer_in_ready);
    assign alu1_completion_ready =
        dual_wb_active_cycle ? dual_wb_source_clear_mask[1] :
        (selected_completion_grant_alu1 && wb_buffer_in_ready);
    assign branch_completion_ready =
        !dual_wb_active_cycle && selected_completion_grant_bru && wb_buffer_in_ready;
    assign lsu_completion_ready =
        !dual_wb_active_cycle && selected_completion_grant_lsu && wb_buffer_in_ready;
    assign atomic_completion_ready =
        !dual_wb_active_cycle && selected_completion_grant_atomic &&
        wb_buffer_in_ready;
    assign csr_completion_ready =
        !dual_wb_active_cycle && selected_completion_grant_csr && wb_buffer_in_ready;
    assign mdu_completion_ready = csr_completion_ready && mdu_completion_valid;
    assign csr_local_completion_ready = csr_completion_ready &&
        !mdu_completion_valid;
    assign debug_completion_grant_alu_o = alu0_completion_ready || alu1_completion_ready;
    assign debug_completion_grant_alu0_o = alu0_completion_ready;
    assign debug_completion_grant_alu1_o = alu1_completion_ready;
    assign debug_completion_grant_bru_o = branch_completion_ready;
    assign debug_completion_grant_lsu_o = lsu_completion_ready;
    assign debug_completion_grant_csr_o = csr_completion_ready;
    assign debug_completion_hold_alu0_o = alu0_completion_valid && !alu0_completion_ready;
    assign debug_completion_hold_alu1_o = alu1_completion_valid && !alu1_completion_ready;
    assign debug_completion_hold_alu_o =
        debug_completion_hold_alu0_o || debug_completion_hold_alu1_o;
    assign debug_completion_hold_bru_o = branch_completion_valid && !branch_completion_ready;
    assign debug_completion_hold_lsu_o = lsu_completion_valid && !lsu_completion_ready;
    assign debug_completion_hold_csr_o = csr_completion_valid && !csr_completion_ready;
    assign debug_completion_oldest_arb_o = completion_oldest_mode && completion_selected_valid;
    assign debug_completion_fixed_arb_o = completion_fixed_mode && completion_selected_valid;
    assign debug_completion_oldest_grant_alu_o =
        completion_oldest_mode &&
        (selected_completion_grant_alu0 || selected_completion_grant_alu1) &&
        (wb_buffer_in_ready || dual_wb_active_cycle);
    assign debug_completion_oldest_grant_bru_o =
        completion_oldest_mode && selected_completion_grant_bru && wb_buffer_in_ready;
    assign debug_completion_oldest_grant_lsu_o =
        completion_oldest_mode && selected_completion_grant_lsu && wb_buffer_in_ready;
    assign debug_completion_oldest_grant_csr_o =
        completion_oldest_mode && selected_completion_grant_csr && wb_buffer_in_ready;
    assign debug_completion_fixed_would_choose_alu_o =
        fixed_completion_grant_alu0 || fixed_completion_grant_alu1;
    assign debug_completion_fixed_would_choose_bru_o = fixed_completion_grant_bru;
    assign debug_completion_fixed_would_choose_lsu_o = fixed_completion_grant_lsu;
    assign debug_completion_fixed_would_choose_csr_o = fixed_completion_grant_csr;
    assign debug_completion_oldest_differs_from_fixed_o = completion_oldest_differs_from_fixed;
    assign debug_duplicate_completion_tag_o = duplicate_completion_tag;
    assign debug_completion_arb_no_valid_bug_o = completion_arb_no_valid_bug;
    assign debug_alu_busy_o = alu0_busy || alu1_busy;
    assign debug_alu0_busy_o = alu0_busy;
    assign debug_alu1_busy_o = alu1_busy;
    assign debug_alu_completion_valid_o = alu0_completion_valid || alu1_completion_valid;
    assign debug_alu0_issue_o = alu0_issue_valid;
    assign debug_alu1_issue_o = alu1_issue_valid;
    assign debug_alu0_alu1_done_same_cycle_o =
        alu0_completion_valid && alu1_completion_valid;
    assign debug_alu0_alu1_wb_conflict_o =
        alu0_completion_valid && alu1_completion_valid &&
        !(alu0_completion_ready && alu1_completion_ready);

    alu_wb_buffer_1w u_wb_buffer (
        .clk(clk),
        .reset(reset),
        .flush_i(completion_flush_c),
        .in_wb_i(wb_buffer_in),
        .in_valid_i(wb_buffer_in_valid),
        .in_ready_o(wb_buffer_in_ready),
        .out_wb_o(wb_buffer_out),
        .out_valid_o(wb_buffer_out_valid),
        .out_accepted_i(wb_buffer_out_accepted),
        .out_drop_i(wb_buffer_out_drop),
        .debug_full_o(debug_wb_buffer_full_o)
    );

    /* verilator lint_off UNUSED */
    wire renamed_uop1_unused = ^renamed_uop1;
    wire alloc_tag1_unused = ^alloc_tag1;
    wire rob_alloc_fire_mask_unused = rob_alloc_fire_mask[1];
    wire branch_redirect_unused = branch_redirect_valid ^ ^branch_redirect;
    wire branch_debug_completion_valid_unused = branch_debug_completion_valid;
    wire lsu_commit_store_wstrb_unused = ^lsu_commit_store_wstrb;
    wire lsu_debug_mem_unused = lsu_debug_mem_req_valid ^ lsu_debug_mem_resp_valid;
    wire mdu_debug_unused = mdu_flush_drop ^ mdu_illegal_issue;
    wire atomic_debug_unused = atomic_write_request_fire ^
        atomic_recovery_block ^ atomic_killed_read_drain ^ atomic_illegal_issue ^
        atomic_flush_drop ^ atomic_reservation_valid ^
        (^atomic_reservation_addr) ^ atomic_sc_success ^ atomic_sc_failure ^
        atomic_irreversible_flush_error ^ atomic_conservation_error ^
        atomic_bridge_rsp_capture ^ atomic_bridge_rsp_fire ^
        atomic_bridge_protocol_error ^ atomic_lsu_collision_error_q;
    /* verilator lint_on UNUSED */

    always_ff @(posedge clk) begin
        if (reset) begin
            control_pending_q <= 1'b0;
            memory_pending_q <= 1'b0;
            completion_flush_q <= 1'b0;
            atomic_lsu_collision_error_q <= 1'b0;
            csr_busy_q <= 1'b0;
            csr_completion_wb_q <= '0;
            csr_mstatus_q <= 32'h0000_1800;
            csr_mtvec_q <= 32'b0;
            csr_mepc_q <= 32'b0;
            csr_mcause_q <= 32'b0;
            csr_mscratch_q <= 32'b0;
            csr_mie_q <= 32'b0;
            csr_mip_q <= 32'b0;
            csr_mtval_q <= 32'b0;
            csr_mcounteren_q <= 32'b0;
            csr_medeleg_q <= 32'b0;
            csr_mideleg_q <= 32'b0;
            csr_stvec_q <= 32'b0;
            csr_sscratch_q <= 32'b0;
            csr_sepc_q <= 32'b0;
            csr_scause_q <= 32'b0;
            csr_stval_q <= 32'b0;
            csr_scounteren_q <= 32'b0;
            priv_mode_q <= 2'b11;
        end else begin
            completion_flush_q <= completion_recovery_event_c;
            if (lsu_debug_mem_req_valid && atomic_bridge_req_fire) begin
                atomic_lsu_collision_error_q <= 1'b1;
            end
            if (csr_local_completion_valid && csr_local_completion_ready) begin
                csr_busy_q <= 1'b0;
                csr_completion_wb_q <= '0;
            end
            if (csr_issue_valid) begin
                csr_busy_q <= 1'b1;
                csr_completion_wb_q <= csr_completion_next_c;
            end

            if (commit_event_o.normal_commit_mask[0] && commit_event_o.slot0.is_csr &&
                commit_event_o.slot0.csr_write) begin
                unique case (commit_event_o.slot0.csr_addr)
                    12'h300: csr_mstatus_q <= mstatus_warl(csr_apply_write(commit_event_o.slot0.csr_addr, csr_mstatus_q, commit_event_o.slot0.csr_wdata));
`ifdef NPC_S_EXTENSION
                    12'h100: csr_mstatus_q <= mstatus_warl(csr_apply_write(commit_event_o.slot0.csr_addr, csr_mstatus_q, commit_event_o.slot0.csr_wdata));
                    12'h104: csr_mie_q <= csr_apply_write(commit_event_o.slot0.csr_addr, csr_mie_q, commit_event_o.slot0.csr_wdata);
                    12'h105: csr_stvec_q <= {commit_event_o.slot0.csr_wdata[31:2],
                        (commit_event_o.slot0.csr_wdata[1:0] == 2'b01) ? 2'b01 : 2'b00};
                    12'h106: csr_scounteren_q <= commit_event_o.slot0.csr_wdata;
                    12'h140: csr_sscratch_q <= commit_event_o.slot0.csr_wdata;
                    12'h141: csr_sepc_q <= {commit_event_o.slot0.csr_wdata[31:2], 2'b00};
                    12'h142: csr_scause_q <= commit_event_o.slot0.csr_wdata;
                    12'h143: csr_stval_q <= commit_event_o.slot0.csr_wdata;
                    12'h144: csr_mip_q <= csr_apply_write(commit_event_o.slot0.csr_addr, csr_mip_q, commit_event_o.slot0.csr_wdata);
                    12'h180: begin end
`endif
                    12'h302: csr_medeleg_q <= commit_event_o.slot0.csr_wdata & 32'h0000_b3ff;
                    12'h303: csr_mideleg_q <= commit_event_o.slot0.csr_wdata & 32'h0000_0222;
                    12'h304: csr_mie_q <= commit_event_o.slot0.csr_wdata;
                    12'h305: csr_mtvec_q <= {commit_event_o.slot0.csr_wdata[31:2],
                        (commit_event_o.slot0.csr_wdata[1:0] == 2'b01) ? 2'b01 : 2'b00};
                    12'h306: csr_mcounteren_q <= commit_event_o.slot0.csr_wdata;
                    12'h340: csr_mscratch_q <= commit_event_o.slot0.csr_wdata;
                    12'h341: csr_mepc_q <= {commit_event_o.slot0.csr_wdata[31:2], 2'b00};
                    12'h342: csr_mcause_q <= commit_event_o.slot0.csr_wdata;
                    12'h343: csr_mtval_q <= commit_event_o.slot0.csr_wdata;
                    12'h344: csr_mip_q <= commit_event_o.slot0.csr_wdata;
                    default: begin end
                endcase
            end
            if (commit_event_o.normal_commit_mask[0] && commit_event_o.slot0.is_system) begin
                if (commit_event_o.slot0.instr == 32'h0000_0073) begin
                    if (commit_trap_delegated_c) begin
                        csr_scause_q <= ecall_cause(priv_mode_q);
                        csr_sepc_q <= commit_event_o.slot0.pc;
                        csr_stval_q <= 32'b0;
                        csr_mstatus_q <= csr_trap_sstatus(csr_mstatus_q, priv_mode_q);
                        priv_mode_q <= 2'b01;
                    end else begin
                        csr_mcause_q <= ecall_cause(priv_mode_q);
                        csr_mepc_q <= commit_event_o.slot0.pc;
                        csr_mtval_q <= 32'b0;
                        csr_mstatus_q <= csr_trap_mstatus(csr_mstatus_q, priv_mode_q);
                        priv_mode_q <= 2'b11;
                    end
                end else if (commit_event_o.slot0.instr == 32'h3020_0073) begin
                    priv_mode_q <= csr_mstatus_q[12:11];
                    csr_mstatus_q <= csr_mret_mstatus(csr_mstatus_q);
                end else if (commit_event_o.slot0.instr == 32'h1020_0073) begin
                    priv_mode_q <= csr_mstatus_q[8] ? 2'b01 : 2'b00;
                    csr_mstatus_q <= csr_sret_mstatus(csr_mstatus_q);
                end
            end
            if (commit_event_o.control_event_valid &&
                (commit_event_o.control_event == BBUS_OOO_CTRL_EXCEPTION)) begin
                if (commit_trap_delegated_c) begin
                    csr_scause_q <= commit_event_o.slot0.exception.cause;
                    csr_sepc_q <= commit_event_o.slot0.pc;
                    csr_stval_q <= commit_event_o.slot0.exception.tval;
                    csr_mstatus_q <= csr_trap_sstatus(csr_mstatus_q, priv_mode_q);
                    priv_mode_q <= 2'b01;
                end else begin
                    csr_mcause_q <= commit_event_o.slot0.exception.cause;
                    csr_mepc_q <= commit_event_o.slot0.pc;
                    csr_mtval_q <= commit_event_o.slot0.exception.tval;
                    csr_mstatus_q <= csr_trap_mstatus(csr_mstatus_q, priv_mode_q);
                    priv_mode_q <= 2'b11;
                end
            end

            if (rename_fire_mask[0] &&
                ((renamed_uop0.fu_type == BBUS_OOO_FU_BRU) ||
                 renamed_uop0.is_load ||
                 renamed_uop0.is_ebreak ||
                 renamed_uop0.is_csr ||
                 renamed_uop0.is_system ||
                 (renamed_uop0.fu_type == BBUS_OOO_FU_AMO) ||
                 renamed_uop0.exception.valid)) begin
                control_pending_q <= 1'b1;
            end
            if (commit_redirect_valid_o ||
                commit_event_o.control_event_valid ||
                (commit_event_o.normal_commit_mask[0] &&
                 ((commit_event_o.slot0.fu_type == BBUS_OOO_FU_BRU) ||
                  commit_event_o.slot0.is_load || commit_event_o.slot0.is_csr ||
                  commit_event_o.slot0.is_system ||
                  (commit_event_o.slot0.fu_type == BBUS_OOO_FU_AMO)))) begin
                control_pending_q <= 1'b0;
            end
            if (rename_fire_mask[0] && renamed_uop0.is_store) begin
                memory_pending_q <= 1'b1;
            end
            if ((commit_event_o.normal_commit_mask[0] && commit_event_o.slot0.is_store) ||
                commit_event_o.control_event_valid) begin
                memory_pending_q <= 1'b0;
            end
        end
    end
endmodule
