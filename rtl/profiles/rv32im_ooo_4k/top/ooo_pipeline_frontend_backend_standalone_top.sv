`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// S8I standalone integration only. This is intentionally not a production
// frontend and is not instantiated by ooo_s2_alu1_standalone_top.
module ooo_pipeline_frontend_backend_standalone_top #(
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
    parameter bit STRUCTURAL_THROUGHPUT_ORACLE_ENABLE = 1'b0
) (
    input logic clk,
    input logic reset,
    input logic global_recover_i,
    // P8 policy inputs. Existing P7 users tie all three low.
    input logic branch_nonblocking_i,
    input logic dispatch_freeze_i,
    input logic serial_dispatch_block_i,
    input logic speculative_store_dispatch_i,
    input logic selective_recovery_pending_i,
    input logic selective_squash_valid_i,
    input bbus_ooo_rob_tag_t selective_squash_branch_tag_i,
    input bbus_ooo_rob_tag_t selective_squash_post_tail_tag_i,
    input bbus_ooo_rat_snapshot_t selective_restore_rat_snapshot_i,
    output logic selective_squash_ready_o,
    output logic selective_squash_fire_o,
    output logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_o,
    output logic [`BBUS_OOO_PHYS_REGS-1:0] selective_killed_phys_mask_o,
    output logic [3:0] selective_killed_count_o,
    output logic selective_recovery_identity_error_o,

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

    output logic serial_issue_valid_o,
    input logic serial_issue_ready_i,
    output bbus_ooo_alu_iq_uop_t serial_issue_uop_o,
    output logic [31:0] serial_issue_src1_o,
    output logic [31:0] serial_issue_src2_o,
    output logic [2:0] serial_issue_kind_o,
    output logic serial_issue_from_dispatch_o,
    input logic serial_completion_valid_i,
    output logic serial_completion_ready_o,
    input bbus_ooo_writeback_t serial_completion_wb_i,
    input logic [2:0] serial_completion_kind_i,

    input logic commit_enable_i,
    output bbus_ooo_commit_event_t commit_event_o,
    output logic recovery_done_o,
    output logic serial_barrier_o,
    output logic [1:0] rename_fire_mask_o,
    output logic [1:0] backend_accept_mask_o,
    output bbus_ooo_rob_tag_t backend_dispatch_tag0_o,
    output bbus_ooo_rob_tag_t backend_dispatch_tag1_o,
    output bbus_ooo_rob_tag_t backend_dispatch_post_tail_tag_o,
    output bbus_ooo_rat_snapshot_t checkpoint_rat_snapshot_o,
    output logic [1:0] final_consume_mask_o,
    output bbus_ooo_writeback_t final_wb0_o,
    output bbus_ooo_writeback_t final_wb1_o,
    output logic [3:0] rob_count_o,
    output logic [3:0] iq_count_o,
    output logic backend_busy_o,
    output logic atomic_recovery_deferred_o,
    output logic [1:0] perf_dispatch_width_o,
    output logic [1:0] perf_issue_width_o,
    output logic [3:0] perf_dispatch_reason0_o,
    output logic [3:0] perf_dispatch_reason1_o,
    output logic [3:0] perf_issue_reason0_o,
    output logic [3:0] perf_issue_reason1_o,
    output logic [3:0] perf_commit_reason0_o,
    output logic [3:0] perf_commit_reason1_o,
    output logic [1:0] perf_branch_iq_ready_count_o,
    output logic [63:0] perf_backend_events_o,
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
    output logic recovery_mapping_error_o,
    output logic conservation_error_o
);
    logic [1:0] decode_buffer_valid;
    logic [1:0] decode_buffer_ready;
    logic [1:0] decode_buffer_accept;
    logic [1:0] decode_buffer_fire;
    bbus_ooo_decode_uop_t decode_buffer_uop0;
    bbus_ooo_decode_uop_t decode_buffer_uop1;
    logic [1:0] decode_buffer_occupancy;
    logic decode_illegal_input;
    logic decode_illegal_fire;
    logic decode_conservation;

    logic [1:0] backend_capacity;
    logic [1:0] backend_ready;
    logic [1:0] backend_accept;
    logic [1:0] ordinary_wakeup_mask;
    bbus_ooo_phys_reg_t ordinary_wakeup_phys0;
    bbus_ooo_phys_reg_t ordinary_wakeup_phys1;
    bbus_ooo_commit_event_t backend_commit_event;
    logic rename_atomicity_error;
    logic rename_conservation;
    logic selective_restore_ready;
    logic selective_restore_fire;
    logic selective_restore_error;
    logic backend_selective_ready;
    logic backend_selective_valid;
    logic backend_selective_fire;
    logic backend_selective_identity_error;
    logic backend_conservation;
    logic slot1_retained;
    logic [1:0] backend_final_consume;
    bbus_ooo_writeback_t backend_final_wb0;
    bbus_ooo_writeback_t backend_final_wb1;
    logic backend_atomic_recovery_block;
    logic backend_atomic_occupied;
    logic recovery_pending_q;
    logic effective_recover_c;
    logic recovery_freeze_c;
    logic [1:0] backend_perf_issue_width;
    logic [3:0] backend_perf_issue_reason0;
    logic [3:0] backend_perf_issue_reason1;
    logic [3:0] backend_perf_commit_reason0;
    logic [3:0] backend_perf_commit_reason1;
    logic [63:0] backend_perf_events;
    logic [63:0] backend_perf_lifecycle;
    logic backend_memory_dispatch_barrier;
    logic perf_serial_blocked_slot0_c;
    logic perf_serial_blocked_slot1_c;
    bbus_ooo_decode_uop_t perf_serial_blocked_uop_c;

    function automatic logic perf_is_serial(
        input bbus_ooo_decode_uop_t uop
    );
        perf_is_serial = uop.is_store || uop.is_csr || uop.is_system ||
            uop.exception.valid || (uop.fu_type == BBUS_OOO_FU_BRU) ||
            (uop.fu_type == BBUS_OOO_FU_MDU) ||
            (uop.fu_type == BBUS_OOO_FU_AMO);
    endfunction

    function automatic logic perf_blocked_serial(
        input bbus_ooo_decode_uop_t uop
    );
        perf_blocked_serial = serial_dispatch_block_i && perf_is_serial(uop) &&
            !(branch_nonblocking_i &&
              (uop.fu_type == BBUS_OOO_FU_BRU)) &&
            !(PRECISE_STORE_BUFFER_ENABLE &&
              speculative_store_dispatch_i && uop.is_store);
    endfunction

    assign effective_recover_c =
        (global_recover_i || recovery_pending_q) &&
        !backend_atomic_recovery_block;
    assign recovery_freeze_c = dispatch_freeze_i || global_recover_i ||
        recovery_pending_q || selective_recovery_pending_i;
    assign atomic_recovery_deferred_o = recovery_pending_q ||
        (global_recover_i && backend_atomic_recovery_block);

    ooo_decode_bundle_elastic_2w #(
        .DECODE_DISPATCH_FALLTHROUGH_ENABLE(
            DECODE_DISPATCH_FALLTHROUGH_ENABLE)
    ) u_decode_buffer (
        .clk(clk),
        .reset(reset),
        .flush_i(effective_recover_c || selective_squash_fire_o),
        .in_valid_mask_i(recovery_freeze_c ? 2'b00 : decode_valid_mask_i),
        .in_uop0_i(decode_uop0_i),
        .in_uop1_i(decode_uop1_i),
        .in_ready_mask_o(decode_buffer_ready),
        .in_accept_mask_o(decode_buffer_accept),
        .out_valid_mask_o(decode_buffer_valid),
        .out_uop0_o(decode_buffer_uop0),
        .out_uop1_o(decode_buffer_uop1),
        .out_fire_mask_i(decode_buffer_fire),
        .occupancy_o(decode_buffer_occupancy),
        .illegal_input_mask_o(decode_illegal_input),
        .illegal_fire_mask_o(decode_illegal_fire),
        .conservation_error_o(decode_conservation)
    );

    ooo_rename_dispatch_recovery_2w #(
        .PRECISE_STORE_BUFFER_ENABLE(PRECISE_STORE_BUFFER_ENABLE)
    ) u_rename (
        .clk(clk),
        .reset(reset),
        .global_recover_i(effective_recover_c),
        .selective_restore_valid_i(backend_selective_fire),
        .selective_restore_rat_snapshot_i(selective_restore_rat_snapshot_i),
        .selective_restore_killed_phys_mask_i(selective_killed_phys_mask_o),
        .selective_restore_ready_o(selective_restore_ready),
        .selective_restore_fire_o(selective_restore_fire),
        .selective_restore_identity_error_o(selective_restore_error),
        .dispatch_freeze_i(recovery_freeze_c),
        .serial_dispatch_block_i(serial_dispatch_block_i),
        .memory_dispatch_block_i(backend_memory_dispatch_barrier),
        .branch_nonblocking_i(branch_nonblocking_i),
        .speculative_store_dispatch_i(speculative_store_dispatch_i),
        .decode_valid_mask_i(decode_buffer_valid),
        .decode_uop0_i(decode_buffer_uop0),
        .decode_uop1_i(decode_buffer_uop1),
        .backend_capacity_count_i(backend_capacity),
        .backend_accept_mask_i(backend_accept),
        .rename_offer_mask_o(rename_fire_mask_o),
        .renamed_uop0_o(debug_renamed_uop0_o),
        .renamed_uop1_o(debug_renamed_uop1_o),
        .checkpoint_rat_snapshot_o(checkpoint_rat_snapshot_o),
        .commit_event_i(backend_commit_event),
        .final_wakeup_mask_i(ordinary_wakeup_mask),
        .final_wakeup_phys0_i(ordinary_wakeup_phys0),
        .final_wakeup_phys1_i(ordinary_wakeup_phys1),
        .debug_arch_idx_i(debug_arch_idx_i),
        .debug_phys_idx_i(debug_phys_idx_i),
        .debug_rat_phys_o(debug_rat_phys_o),
        .debug_rrat_phys_o(debug_rrat_phys_o),
        .debug_ready_o(debug_ready_o),
        .debug_free_count_o(debug_free_count_o),
        .debug_next_free_phys_o(debug_next_free_phys_o),
        .slot1_retained_o(slot1_retained),
        .atomicity_error_o(rename_atomicity_error),
        .recovery_mapping_error_o(recovery_mapping_error_o),
        .conservation_error_o(rename_conservation)
    );

    assign decode_buffer_fire = rename_fire_mask_o;
    assign decode_ready_mask_o = recovery_freeze_c ? 2'b00 : decode_buffer_ready;
    assign decode_accept_mask_o = recovery_freeze_c ? 2'b00 : decode_buffer_accept;
    assign backend_accept_mask_o = backend_accept;
    assign debug_decode_buffer_valid_mask_o = {
        (decode_buffer_occupancy >= 2'd2),
        (decode_buffer_occupancy >= 2'd1)
    };
    assign debug_decode_buffer_pc0_o = decode_buffer_uop0.pc;
    assign debug_decode_buffer_pc1_o = decode_buffer_uop1.pc;

    ooo_pipeline_backend_standalone_top #(
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
        .CORRECT_BRANCH_DUAL_RETIRE_ENABLE(
            CORRECT_BRANCH_DUAL_RETIRE_ENABLE),
        .YOUNGER_SLOT1_CONTROL_DUAL_RETIRE_ENABLE(
            YOUNGER_SLOT1_CONTROL_DUAL_RETIRE_ENABLE),
        .STRUCTURAL_THROUGHPUT_ORACLE_ENABLE(
            STRUCTURAL_THROUGHPUT_ORACLE_ENABLE)
    ) u_backend (
        .clk(clk),
        .reset(reset),
        .flush_i(effective_recover_c),
        .branch_nonblocking_i(branch_nonblocking_i),
        .dispatch_valid_mask_i(rename_fire_mask_o),
        .dispatch_uop0_i(debug_renamed_uop0_o),
        .dispatch_uop1_i(debug_renamed_uop1_o),
        .dispatch_capacity_count_o(backend_capacity),
        .dispatch_ready_mask_o(backend_ready),
        .dispatch_accept_mask_o(backend_accept),
        .dispatch_tag0_o(backend_dispatch_tag0_o),
        .dispatch_tag1_o(backend_dispatch_tag1_o),
        .dispatch_post_tail_tag_o(backend_dispatch_post_tail_tag_o),
        .selective_squash_valid_i(backend_selective_valid),
        .selective_squash_branch_tag_i(selective_squash_branch_tag_i),
        .selective_squash_post_tail_tag_i(selective_squash_post_tail_tag_i),
        .selective_squash_ready_o(backend_selective_ready),
        .selective_squash_fire_o(backend_selective_fire),
        .selective_killed_rob_mask_o(selective_killed_rob_mask_o),
        .selective_killed_phys_mask_o(selective_killed_phys_mask_o),
        .selective_killed_count_o(selective_killed_count_o),
        .selective_squash_identity_error_o(backend_selective_identity_error),
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
        .serial_issue_from_dispatch_o(serial_issue_from_dispatch_o),
        .serial_completion_valid_i(serial_completion_valid_i),
        .serial_completion_ready_o(serial_completion_ready_o),
        .serial_completion_wb_i(serial_completion_wb_i),
        .serial_completion_kind_i(serial_completion_kind_i),
        .commit_enable_i(commit_enable_i && !effective_recover_c &&
            !selective_recovery_pending_i),
        .commit_event_o(backend_commit_event),
        .serial_barrier_o(serial_barrier_o),
        .memory_dispatch_barrier_o(backend_memory_dispatch_barrier),
        .rob_count_o(rob_count_o),
        .iq_count_o(iq_count_o),
        .final_consume_mask_o(backend_final_consume),
        .final_wb0_o(backend_final_wb0),
        .final_wb1_o(backend_final_wb1),
        .ordinary_wakeup_mask_o(ordinary_wakeup_mask),
        .ordinary_wakeup_phys0_o(ordinary_wakeup_phys0),
        .ordinary_wakeup_phys1_o(ordinary_wakeup_phys1),
        .backend_busy_o(backend_busy_o),
        .atomic_recovery_block_o(backend_atomic_recovery_block),
        .atomic_occupied_o(backend_atomic_occupied),
        .perf_issue_width_o(backend_perf_issue_width),
        .perf_issue_reason0_o(backend_perf_issue_reason0),
        .perf_issue_reason1_o(backend_perf_issue_reason1),
        .perf_commit_reason0_o(backend_perf_commit_reason0),
        .perf_commit_reason1_o(backend_perf_commit_reason1),
        .perf_branch_iq_ready_count_o(perf_branch_iq_ready_count_o),
        .perf_events_o(backend_perf_events),
        .perf_mixed_source_o(perf_mixed_source_o),
        .perf_structural_oracle_o(perf_structural_oracle_o),
        .perf_structural_meta_o(perf_structural_meta_o),
        .perf_accounting_raw_o(perf_accounting_raw_o),
        .perf_store_buffer_o(perf_store_buffer_o),
        .perf_branch_pair_o(perf_branch_pair_o),
        .perf_operand_stage_o(perf_operand_stage_o),
        .perf_lifecycle_o(backend_perf_lifecycle),
        .perf_branch_operand_o(perf_branch_operand_o),
        .perf_branch_producer_phase_o(perf_branch_producer_phase_o),
        .perf_lsu_causality_o(perf_lsu_causality_o),
        .perf_store_admission_o(perf_store_admission_o),
        .perf_issue_dependency_o(perf_issue_dependency_o),
        .perf_retirement_chain_o(perf_retirement_chain_o),
        .perf_complex_retire_pairing_o(perf_complex_retire_pairing_o),
        .perf_completion_ownership_o(perf_completion_ownership_o),
        .conservation_error_o(backend_conservation)
    );

    assign perf_dispatch_width_o = {1'b0, backend_accept[0]} +
        {1'b0, backend_accept[1]};
    assign perf_issue_width_o = backend_perf_issue_width;
    assign perf_issue_reason0_o = backend_perf_issue_reason0;
    assign perf_issue_reason1_o = backend_perf_issue_reason1;
    assign perf_commit_reason0_o = backend_perf_commit_reason0;
    assign perf_commit_reason1_o = backend_perf_commit_reason1;
    assign perf_serial_blocked_slot0_c = !backend_accept[0] &&
        decode_buffer_valid[0] && perf_blocked_serial(decode_buffer_uop0);
    assign perf_serial_blocked_slot1_c = backend_accept[0] &&
        !backend_accept[1] && decode_buffer_valid[1] &&
        perf_blocked_serial(decode_buffer_uop1);
    assign perf_serial_blocked_uop_c = perf_serial_blocked_slot0_c ?
        decode_buffer_uop0 : decode_buffer_uop1;
    assign perf_backend_events_o = backend_perf_events;
    always_comb begin
        perf_serial_attribution_o = '0;
        perf_serial_attribution_o[0] = serial_dispatch_block_i;
        perf_serial_attribution_o[1] = perf_serial_blocked_slot0_c;
        perf_serial_attribution_o[2] = perf_serial_blocked_slot1_c;
        if (perf_serial_blocked_slot0_c || perf_serial_blocked_slot1_c) begin
            if (perf_serial_blocked_uop_c.is_store) begin
                perf_serial_attribution_o[4] = 1'b1;
            end else if (perf_serial_blocked_uop_c.fu_type == BBUS_OOO_FU_BRU) begin
                perf_serial_attribution_o[3] = 1'b1;
            end else if (perf_serial_blocked_uop_c.fu_type == BBUS_OOO_FU_MDU) begin
                perf_serial_attribution_o[5] = 1'b1;
            end else if (perf_serial_blocked_uop_c.fu_type == BBUS_OOO_FU_AMO) begin
                perf_serial_attribution_o[7] = 1'b1;
            end else begin
                perf_serial_attribution_o[6] = 1'b1;
            end
        end
    end
    assign perf_lifecycle_o = backend_perf_lifecycle;

    assign selective_squash_ready_o = backend_selective_ready &&
        selective_restore_ready && !backend_atomic_occupied;
    assign backend_selective_valid = selective_squash_valid_i &&
        selective_restore_ready && !backend_atomic_occupied;
    assign selective_squash_fire_o = backend_selective_fire &&
        selective_restore_fire;
    assign selective_recovery_identity_error_o =
        backend_selective_identity_error || selective_restore_error ||
        (backend_selective_fire != selective_restore_fire);

    always_comb begin
        perf_dispatch_reason0_o = 4'd0;
        if (!backend_accept[0]) begin
            if (recovery_freeze_c) perf_dispatch_reason0_o = 4'd1;
            else if (!decode_buffer_valid[0]) perf_dispatch_reason0_o = 4'd2;
            else if (serial_dispatch_block_i || backend_atomic_occupied ||
                     serial_barrier_o) perf_dispatch_reason0_o = 4'd3;
            else if (debug_free_count_o == 7'd0) perf_dispatch_reason0_o = 4'd6;
            else if (rob_count_o >= `BBUS_OOO_ROB_ENTRIES) perf_dispatch_reason0_o = 4'd4;
            else if (iq_count_o >= 4'd8) perf_dispatch_reason0_o = 4'd5;
            else perf_dispatch_reason0_o = 4'd8;
        end

        perf_dispatch_reason1_o = 4'd0;
        if (!backend_accept[1]) begin
            if (!backend_accept[0]) begin
                perf_dispatch_reason1_o = perf_dispatch_reason0_o;
            end else if (!decode_buffer_valid[1]) begin
                perf_dispatch_reason1_o = 4'd2;
            end else if (serial_dispatch_block_i || serial_barrier_o ||
                         backend_atomic_occupied) begin
                perf_dispatch_reason1_o = 4'd3;
            end else if (debug_free_count_o < 7'd2) begin
                perf_dispatch_reason1_o = 4'd6;
            end else if (rob_count_o >= (`BBUS_OOO_ROB_ENTRIES - 1)) begin
                perf_dispatch_reason1_o = 4'd4;
            end else if (iq_count_o >= 4'd7) begin
                perf_dispatch_reason1_o = 4'd5;
            end else if ((debug_renamed_uop0_o.is_load &&
                         !debug_renamed_uop0_o.is_store) &&
                        (debug_renamed_uop1_o.is_load &&
                         !debug_renamed_uop1_o.is_store)) begin
                perf_dispatch_reason1_o = 4'd7;
            end else begin
                perf_dispatch_reason1_o = 4'd8;
            end
        end
    end

    // The backend already disables commit and flushes the completion fabric
    // during effective recovery. Gating these outputs with effective_recover_c
    // creates a combinational commit->recovery->commit loop at the production
    // control shell without adding any architectural protection.
    assign commit_event_o = backend_commit_event;
    assign final_consume_mask_o = backend_final_consume;
    assign final_wb0_o = backend_final_wb0;
    assign final_wb1_o = backend_final_wb1;

    always_ff @(posedge clk) begin
        if (reset) begin
            recovery_done_o <= 1'b0;
            recovery_pending_q <= 1'b0;
        end else begin
            recovery_done_o <= effective_recover_c;
            if (effective_recover_c) begin
                recovery_pending_q <= 1'b0;
            end else if (global_recover_i && backend_atomic_recovery_block) begin
                recovery_pending_q <= 1'b1;
            end
        end
    end

    assign conservation_error_o = decode_conservation || rename_conservation ||
        backend_conservation || rename_atomicity_error ||
        selective_recovery_identity_error_o ||
        (rename_fire_mask_o != backend_accept) ||
        (effective_recover_c && (decode_accept_mask_o != 2'b00)) ||
        (recovery_freeze_c && (decode_accept_mask_o != 2'b00));

    /* verilator lint_off UNUSED */
    wire backend_atomic_occupied_used = backend_atomic_occupied;
    /* verilator lint_on UNUSED */
endmodule
