`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// S8R production shell for the reusable P9->P6 pipeline. The FSM backend is
// selected outside this module, so the two implementations never share
// speculative ownership or DPI channels.
module ooo_pipeline_npc_core_top #(
    parameter logic [31:0] RESET_VECTOR = 32'h8000_0000,
    parameter bit EXTERNAL_MEMORY = 1'b0,
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
    parameter bit STRUCTURAL_THROUGHPUT_ORACLE_ENABLE = 1'b0,
    parameter bit SINGLETON_COALESCE_ORACLE_ENABLE = 1'b0,
    parameter bit PARTIAL_PAIR_ORACLE_ENABLE = 1'b0,
    parameter bit CACHED_CROSS_LINE_PAIR_ENABLE = 1'b0,
    parameter bit CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE = 1'b0
) (
    input  logic clk,
    input  logic reset,
    input  logic commit_ready_i,
    input  bbus_ooo_arch_reg_t debug_arch_idx_i,

    output logic ext_if_req_valid_o,
    input  logic ext_if_req_ready_i,
    output logic [31:0] ext_if_req_addr_o,
    output logic [31:0] ext_if_req_pc_o,
    input  logic ext_if_rsp_valid_i,
    output logic ext_if_rsp_ready_o,
    input  logic [31:0] ext_if_rsp_addr_i,
    input  logic [1:0] ext_if_rsp_valid_mask_i,
    input  logic [63:0] ext_if_rsp_data_i,
    input  logic ext_if_rsp_eof_i,
    input  logic ext_if_rsp_error_i,

    output logic ext_fetch_pte_req_valid_o,
    input  logic ext_fetch_pte_req_ready_i,
    output logic [31:0] ext_fetch_pte_req_addr_o,
    input  logic ext_fetch_pte_rsp_valid_i,
    output logic ext_fetch_pte_rsp_ready_o,
    input  logic [31:0] ext_fetch_pte_rsp_data_i,
    input  logic ext_fetch_pte_rsp_error_i,

    output logic ext_mem_req_valid_o,
    input  logic ext_mem_req_ready_i,
    output logic ext_mem_req_write_o,
    output logic [31:0] ext_mem_req_addr_o,
    output logic [31:0] ext_mem_req_wdata_o,
    output logic [3:0] ext_mem_req_wstrb_o,
    output logic [2:0] ext_mem_req_len_o,
    output bbus_ooo_mem_token_t ext_mem_req_token_o,
    input  logic ext_mem_rsp_valid_i,
    output logic ext_mem_rsp_ready_o,
    input  logic [31:0] ext_mem_rsp_rdata_i,
    input  logic ext_mem_rsp_error_i,
    input  bbus_ooo_mem_token_t ext_mem_rsp_token_i,

    output logic commit_valid_o,
    output bbus_ooo_commit_trace_packet_t commit_packet_o,
    output logic commit1_valid_o,
    output bbus_ooo_commit_trace_packet_t commit_packet1_o,
    output bbus_ooo_commit_event_t commit_event_o,

    output logic unsupported_seen_o,
    output logic [31:0] unsupported_pc_o,
    output logic [31:0] unsupported_instr_o,
    output logic idle_o,
    output logic halt_valid_o,
    output logic [31:0] halt_pc_o,
    output logic [31:0] halt_instr_o,
    output logic [3:0] halt_reason_o,

    output logic [31:0] debug_arch_gpr_o,
    output logic [31:0] debug_arch_pc_o,
    output logic [3:0] debug_rob_count_o,
    output logic [3:0] debug_iq_count_o,
    output logic debug_control_pending_o,
    output logic debug_memory_pending_o,
    output logic debug_frontend_busy_o,
    output logic debug_commit_fire_o,
    output logic debug_commit2_fire_o,
    output logic debug_trace_buffer_valid_o,
    output logic debug_conservation_error_o,
    output logic [9:0] perf_stage_widths_o,
    output logic [23:0] perf_lost_reasons_o,
    output logic [31:0] perf_occupancy_o,
    output logic [63:0] perf_events_o,
    output logic [7:0] perf_mixed_source_o,
    output logic [63:0] perf_structural_oracle_o,
    output logic [63:0] perf_structural_meta_o,
    output logic [63:0] perf_accounting_raw_o,
    output logic perf_selective_transaction_fire_o,
    output logic [2:0] perf_branch_pair_o,
    output logic [17:0] perf_operand_stage_o,
    output logic [8:0] perf_trace_width_oracle_o,
    output logic [63:0] perf_lifecycle_o,
    output logic [63:0] perf_branch_operand_o,
    output logic [63:0] perf_branch_producer_phase_o,
    output logic [63:0] perf_lsu_causality_o,
    output logic [63:0] perf_composite_load_turnover_o,
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
    output logic [63:0] perf_fetch_response_service_o,
    output logic [3:0] perf_branch_window_o,
    output logic [9:0] perf_checkpoint_state_o,
    output logic [3:0] perf_data_line_o,
    output logic [15:0] perf_data_line_causality_o,
    output logic [15:0] perf_data_line_coalescing_o,
    output logic [63:0] perf_data_line_store_origin_o,
    output logic [63:0] perf_store_transaction_o,
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
    output logic [63:0] perf_dispatch_instr_o
);
    localparam logic [3:0] HALT_REASON_EBREAK = 4'd1;
`ifdef NPC_SV32
    localparam bit PRECISE_STORE_BUFFER_ENABLE = 1'b0;
    localparam bit STORE_LOAD_FORWARDING_ENABLE = 1'b0;
    localparam bit EFFECTIVE_TARGET_LINE_HIT_ENABLE = 1'b0;
`else
    localparam bit PRECISE_STORE_BUFFER_ENABLE = !EXTERNAL_MEMORY;
    localparam bit STORE_LOAD_FORWARDING_ENABLE = !EXTERNAL_MEMORY;
    localparam bit EFFECTIVE_TARGET_LINE_HIT_ENABLE =
        TARGET_LINE_HIT_ENABLE;
`endif

    logic fetch_req_valid;
    logic fetch_req_ready;
    logic [31:0] fetch_req_addr;
    logic [31:0] fetch_req_pc;
    logic fetch_rsp_valid;
    logic fetch_rsp_ready;
    logic [31:0] fetch_rsp_addr;
    logic [1:0] fetch_rsp_valid_mask;
    logic [63:0] fetch_rsp_data;
    logic fetch_rsp_eof;
    logic fetch_rsp_error;
    logic fetch_rsp_page_fault;
    logic pair_fetch_req_valid, pair_fetch_req_ready;
    logic [31:0] pair_fetch_req_addr, pair_fetch_req_pc;
    logic pair_fetch_rsp_valid, pair_fetch_rsp_ready;
    logic [31:0] pair_fetch_rsp_addr;
    logic [1:0] pair_fetch_rsp_valid_mask;
    logic [63:0] pair_fetch_rsp_data;
    logic pair_fetch_rsp_eof, pair_fetch_rsp_error;
    logic [15:0] ifetch_bridge_service;
    logic [31:0] ifetch_bridge_req_pc;
    logic fetch_pte_req_valid, fetch_pte_req_ready;
    logic [31:0] fetch_pte_req_addr;
    logic fetch_pte_rsp_valid, fetch_pte_rsp_ready;
    logic [31:0] fetch_pte_rsp_data;
    logic fetch_pte_rsp_error;
    logic pair_ifetch_busy, fetch_pte_busy, fetch_translate_busy;
    logic fetch_translate_error, fetch_pte_protocol_error;
    logic ext_if_busy_q, ext_fetch_pte_busy_q;
    logic [1:0] ext_mem_outstanding_q;
    logic ext_mem_protocol_error_q;

    logic mem_req_valid;
    logic mem_req_ready;
    logic mem_req_write;
    logic [31:0] mem_req_addr;
    logic [31:0] mem_req_wdata;
    logic [3:0] mem_req_wstrb;
    logic [2:0] mem_req_len;
    bbus_ooo_mem_token_t mem_req_token;
    logic mem_rsp_valid;
    logic mem_rsp_ready;
    logic [31:0] mem_rsp_rdata;
    logic mem_rsp_error;
    bbus_ooo_mem_token_t mem_rsp_token;
    logic phys_mem_req_valid, phys_mem_req_ready;
    logic phys_mem_req_write;
    logic [31:0] phys_mem_req_addr, phys_mem_req_wdata;
    logic [3:0] phys_mem_req_wstrb;
    logic [2:0] phys_mem_req_len;
    bbus_ooo_mem_token_t phys_mem_req_token;
    logic phys_mem_rsp_valid, phys_mem_rsp_ready;
    logic [31:0] phys_mem_rsp_rdata;
    logic phys_mem_rsp_error;
    bbus_ooo_mem_token_t phys_mem_rsp_token;
    logic phys_mem_busy, phys_mem_protocol_error;
    logic data_line_busy, data_line_hit, data_line_miss;
    logic data_line_fill, data_line_invalidate, data_line_error;
    logic [15:0] data_line_causality;
    logic [15:0] data_line_coalescing;
    logic [7:0] data_line_invalidation_causality;
    logic pipeline_mem_req_valid, pipeline_mem_req_ready;
    logic pipeline_mem_req_write;
    logic [31:0] pipeline_mem_req_addr, pipeline_mem_req_wdata;
    logic [3:0] pipeline_mem_req_wstrb;
    logic [2:0] pipeline_mem_req_len;
    logic [1:0] pipeline_mem_req_access;
    bbus_ooo_mem_token_t pipeline_mem_req_token;
    logic pipeline_mem_rsp_valid, pipeline_mem_rsp_ready;
    logic [31:0] pipeline_mem_rsp_rdata;
    logic pipeline_mem_rsp_error, pipeline_mem_rsp_page_fault;
    bbus_ooo_mem_token_t pipeline_mem_rsp_token;
    logic data_translate_busy, data_translate_error;

    logic serial_issue_valid;
    logic serial_issue_ready;
    bbus_ooo_alu_iq_uop_t serial_issue_uop;
    logic [31:0] serial_issue_src1;
    logic [31:0] serial_issue_src2;
    logic [2:0] serial_issue_kind;
    logic serial_completion_valid;
    logic serial_completion_ready;
    bbus_ooo_writeback_t serial_completion_wb;
    logic [2:0] serial_completion_kind;

    logic trace_can_accept1;
    logic trace_can_accept2;
    logic trace_valid;
    logic trace1_valid;
    bbus_ooo_commit_trace_packet_t trace_packet;
    bbus_ooo_commit_trace_packet_t trace_packet1;
    logic trace_accept;
    logic trace_accept1;
    logic [2:0] trace_fifo_count;
    logic [1:0] trace_enqueue_count;
    logic [1:0] trace_dequeue_count;
    logic trace_packet_accepted;
    logic trace_fifo_overflow;
    logic bridge_commit_valid;
    logic [1:0] bridge_commit_mask;
    logic bridge_commit_slot1;
    logic [31:0] bridge_commit_pc, bridge_commit_instr;
    logic [31:0] bridge_commit_nextpc, bridge_commit_wdata;
    logic bridge_commit_rf_wen;
    bbus_ooo_arch_reg_t bridge_commit_rd;
    logic bridge_commit_is_load, bridge_commit_is_store;
    logic bridge_commit_is_branch, bridge_commit_is_jal, bridge_commit_is_jalr;
    logic [31:0] bridge_commit_mem_addr, bridge_commit_mem_wdata;
    logic [3:0] bridge_commit_mem_wstrb;
    logic [2:0] bridge_commit_mem_len;
    logic bridge_commit_unsupported, bridge_commit_exception;
    logic bridge_commit1_valid;
    bbus_ooo_commit_trace_packet_t bridge_commit1_packet;
    logic bridge_lane1_without_lane0;
    logic commit_enable;
    logic recovery_done;
    logic branch_window_active;
    logic branch_recovery_pending;
    logic dispatch_freeze;
    logic serial_dispatch_block;
    logic selective_kill_valid;
    logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask;
    logic serial_barrier;
    logic backend_busy;
    logic ifetch_busy;
    logic mem_busy;
    logic serial_occupied;
    logic frontend_request_outstanding;
    logic frontend_stale_response_pending;
    logic [1:0] frontend_raw_queue_valid_mask;
    logic [1:0] frontend_decode_buffer_valid_mask;
    logic [6:0] frontend_free_count;
    logic [1:0] pipeline_decode_width;
    logic [1:0] pipeline_dispatch_width;
    logic [1:0] pipeline_issue_width;
    logic [1:0] pipeline_final_consume;
    logic [3:0] pipeline_dispatch_reason0, pipeline_dispatch_reason1;
    logic [3:0] pipeline_issue_reason0, pipeline_issue_reason1;
    logic [3:0] pipeline_commit_reason0, pipeline_commit_reason1;
    logic [63:0] pipeline_perf_events;
    logic [10:0] pipeline_perf_store_buffer;
    logic [63:0] pipeline_perf_lifecycle;
    logic [63:0] pipeline_perf_branch_producer_phase;
    logic [155:0] pipeline_perf_lsu_causality;
    logic [31:0] pipeline_perf_store_admission;
    logic perf_raw_load_offer_valid;
    logic [31:0] perf_raw_load_offer_addr;
    logic [2:0] perf_raw_load_offer_len;
    bbus_ooo_mem_token_t perf_raw_load_offer_token;
    logic [7:0] tagged_bridge_load_turnover;
    logic [31:0] data_line_load_turnover;
    logic [63:0] data_line_store_origin;
    logic [1:0] pipeline_commit_width;
    logic [2:0] frontend_raw_occupancy;
    logic [2:0] frontend_decode_occupancy;
    logic frontend_fault;
    logic [31:0] frontend_fault_pc;
    logic frontend_eof;
    logic frontend_conservation_error;
    logic branch_protocol_error;
    logic recovery_conservation_error;
    logic backend_conservation_error;
    logic ifetch_protocol_error;
    logic mem_protocol_error;
    logic serial_illegal_issue;
    logic serial_fallthrough_conservation_error;
    logic serial_ebreak_accept;
    logic ebreak_inflight_q;
    logic ebreak_recover_q;
    logic ebreak_seen_q;
    logic [31:0] ebreak_pc_q;
    logic [31:0] ebreak_instr_q;
    logic ebreak_commit;
    logic [31:0] csr_mtvec;
    logic [31:0] csr_mepc;
    logic [31:0] csr_mstatus;
    logic [31:0] csr_satp;
    logic [1:0] csr_priv_mode;
    logic [31:0] csr_trap_target;
    logic [31:0] csr_xret_target;

    assign perf_raw_load_offer_valid = pipeline_perf_lsu_causality[41];
    assign perf_raw_load_offer_addr = pipeline_perf_lsu_causality[73:42];
    assign perf_raw_load_offer_len = pipeline_perf_lsu_causality[76:74];
    assign perf_raw_load_offer_token =
        bbus_ooo_mem_token_t'(pipeline_perf_lsu_causality[145:77]);

    // Requiring two free trace entries is conservative for one-wide commits,
    // but guarantees that a Commit2 event can never outrun difftest/trace.
    assign commit_enable = trace_can_accept2 && !ebreak_seen_q;
    assign trace_accept = trace_valid && commit_ready_i;
    assign trace_accept1 = trace1_valid && commit_ready_i;
    assign ebreak_commit = commit_event_o.control_event_valid &&
        (commit_event_o.control_event == BBUS_OOO_CTRL_EBREAK);

    ooo_pipeline_redirect_frontend_standalone_top #(
        .RESET_VECTOR(RESET_VECTOR),
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
        .FETCH_DECODE_FALLTHROUGH_ENABLE(
            FETCH_DECODE_FALLTHROUGH_ENABLE),
        .FETCH_RESPONSE_CREDIT_TURNOVER_ENABLE(
            FETCH_RESPONSE_CREDIT_TURNOVER_ENABLE),
        .ORDERED_TARGET_PREFETCH_ORACLE_ENABLE(
            ORDERED_TARGET_PREFETCH_ORACLE_ENABLE),
        .DEMAND_FETCH_LATENCY_ORACLE_ENABLE(
            DEMAND_FETCH_LATENCY_ORACLE_ENABLE),
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
        .TARGET_LINE_HIT_ENABLE(EFFECTIVE_TARGET_LINE_HIT_ENABLE),
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
        .STRUCTURAL_THROUGHPUT_ORACLE_ENABLE(
            STRUCTURAL_THROUGHPUT_ORACLE_ENABLE),
        .SINGLETON_COALESCE_ORACLE_ENABLE(
            SINGLETON_COALESCE_ORACLE_ENABLE),
        .PARTIAL_PAIR_ORACLE_ENABLE(PARTIAL_PAIR_ORACLE_ENABLE),
        .CACHED_CROSS_LINE_PAIR_ENABLE(CACHED_CROSS_LINE_PAIR_ENABLE),
        .CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE(
            CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE)
    ) u_pipeline (
        .clk(clk),
        .reset(reset),
        .external_global_recover_i(ebreak_recover_q),
        .frontend_stop_i(ebreak_inflight_q || ebreak_seen_q || frontend_fault),
        .trap_target_i(csr_trap_target),
        .xret_target_i(csr_xret_target),
        .fetch_req_valid_o(fetch_req_valid),
        .fetch_req_ready_i(fetch_req_ready),
        .fetch_req_addr_o(fetch_req_addr),
        .fetch_req_pc_o(fetch_req_pc),
        .fetch_rsp_valid_i(fetch_rsp_valid),
        .fetch_rsp_ready_o(fetch_rsp_ready),
        .fetch_rsp_addr_i(fetch_rsp_addr),
        .fetch_rsp_valid_mask_i(fetch_rsp_valid_mask),
        .fetch_rsp_data_i(fetch_rsp_data),
        .fetch_rsp_eof_i(fetch_rsp_eof),
        .fetch_rsp_error_i(fetch_rsp_error),
        .fetch_rsp_page_fault_i(fetch_rsp_page_fault),
        .mem_req_valid_o(pipeline_mem_req_valid),
        .mem_req_ready_i(pipeline_mem_req_ready),
        .mem_req_write_o(pipeline_mem_req_write),
        .mem_req_addr_o(pipeline_mem_req_addr),
        .mem_req_wdata_o(pipeline_mem_req_wdata),
        .mem_req_wstrb_o(pipeline_mem_req_wstrb),
        .mem_req_len_o(pipeline_mem_req_len),
        .mem_req_access_o(pipeline_mem_req_access),
        .mem_req_token_o(pipeline_mem_req_token),
        .mem_rsp_valid_i(pipeline_mem_rsp_valid),
        .mem_rsp_ready_o(pipeline_mem_rsp_ready),
        .mem_rsp_rdata_i(pipeline_mem_rsp_rdata),
        .mem_rsp_error_i(pipeline_mem_rsp_error),
        .mem_rsp_page_fault_i(pipeline_mem_rsp_page_fault),
        .mem_rsp_token_i(pipeline_mem_rsp_token),
        .serial_issue_valid_o(serial_issue_valid),
        .serial_issue_ready_i(serial_issue_ready),
        .serial_issue_uop_o(serial_issue_uop),
        .serial_issue_src1_o(serial_issue_src1),
        .serial_issue_src2_o(serial_issue_src2),
        .serial_issue_kind_o(serial_issue_kind),
        .serial_completion_valid_i(serial_completion_valid),
        .serial_completion_ready_o(serial_completion_ready),
        .serial_completion_wb_i(serial_completion_wb),
        .serial_completion_kind_i(serial_completion_kind),
        .commit_enable_i(commit_enable),
        .redirect_valid_o(),
        .redirect_o(),
        .recovery_done_o(recovery_done),
        .branch_window_active_o(branch_window_active),
        .branch_recovery_pending_o(branch_recovery_pending),
        .dispatch_freeze_o(dispatch_freeze),
        .serial_dispatch_block_o(serial_dispatch_block),
        .selective_kill_valid_o(selective_kill_valid),
        .selective_killed_rob_mask_o(selective_killed_rob_mask),
        .commit_event_o(commit_event_o),
        .serial_barrier_o(serial_barrier),
        .rename_fire_mask_o(),
        .backend_accept_mask_o(),
        .final_consume_mask_o(pipeline_final_consume),
        .final_wb0_o(),
        .final_wb1_o(),
        .rob_count_o(debug_rob_count_o),
        .iq_count_o(debug_iq_count_o),
        .backend_busy_o(backend_busy),
        .debug_arch_idx_i(debug_arch_idx_i),
        .debug_phys_idx_i('0),
        .debug_rat_phys_o(),
        .debug_rrat_phys_o(),
        .debug_ready_o(),
        .debug_free_count_o(frontend_free_count),
        .debug_next_free_phys_o(),
        .debug_decode_buffer_valid_mask_o(frontend_decode_buffer_valid_mask),
        .debug_decode_buffer_pc0_o(),
        .debug_decode_buffer_pc1_o(),
        .debug_renamed_uop0_o(),
        .debug_renamed_uop1_o(),
        .perf_decode_width_o(pipeline_decode_width),
        .perf_dispatch_width_o(pipeline_dispatch_width),
        .perf_issue_width_o(pipeline_issue_width),
        .perf_dispatch_reason0_o(pipeline_dispatch_reason0),
        .perf_dispatch_reason1_o(pipeline_dispatch_reason1),
        .perf_issue_reason0_o(pipeline_issue_reason0),
        .perf_issue_reason1_o(pipeline_issue_reason1),
        .perf_commit_reason0_o(pipeline_commit_reason0),
        .perf_commit_reason1_o(pipeline_commit_reason1),
        .perf_events_o(pipeline_perf_events),
        .perf_mixed_source_o(perf_mixed_source_o),
        .perf_structural_oracle_o(perf_structural_oracle_o),
        .perf_structural_meta_o(perf_structural_meta_o),
        .perf_accounting_raw_o(perf_accounting_raw_o),
        .perf_store_buffer_o(pipeline_perf_store_buffer),
        .perf_branch_pair_o(perf_branch_pair_o),
        .perf_operand_stage_o(perf_operand_stage_o),
        .perf_lifecycle_o(pipeline_perf_lifecycle),
        .perf_branch_operand_o(perf_branch_operand_o),
        .perf_branch_producer_phase_o(
            pipeline_perf_branch_producer_phase),
        .perf_lsu_causality_o(pipeline_perf_lsu_causality),
        .perf_store_admission_o(pipeline_perf_store_admission),
        .perf_issue_dependency_o(perf_issue_dependency_o),
        .perf_retirement_chain_o(perf_retirement_chain_o),
        .perf_complex_retire_pairing_o(perf_complex_retire_pairing_o),
        .perf_completion_ownership_o(perf_completion_ownership_o),
        .perf_serial_attribution_o(perf_serial_attribution_o),
        .perf_branch_resolution_o(perf_branch_resolution_o),
        .perf_target_line_o(perf_target_line_o),
        .perf_frontend_residual_o(perf_frontend_residual_o),
        .perf_frontend_no_candidate_o(perf_frontend_no_candidate_o),
        .perf_branch_window_supply_o(perf_branch_window_supply_o),
        .perf_branch_window_post_block_o(perf_branch_window_post_block_o),
        .perf_reservation_o(perf_reservation_o),
        .perf_fetch_response_credit_o(perf_fetch_response_credit_o),
        .perf_demand_fetch_identity_o(perf_demand_fetch_identity_o),
        .perf_branch_window_o(perf_branch_window_o),
        .perf_checkpoint_state_o(perf_checkpoint_state_o),
        .perf_fetch_delivery_width_o(perf_fetch_delivery_width_o),
        .perf_predictor_o(perf_predictor_o),
        .perf_predictor_detail_o(perf_predictor_detail_o),
        .perf_predictor_local_o(perf_predictor_local_o),
        .perf_predictor_multihistory_o(perf_predictor_multihistory_o),
        .perf_singleton_coalesce_o(perf_singleton_coalesce_o),
        .perf_singleton_target_pc_o(perf_singleton_target_pc_o),
        .perf_singleton_target_instr_o(perf_singleton_target_instr_o),
        .perf_partial_pair_o(perf_partial_pair_o),
        .perf_partial_pair_pc_o(perf_partial_pair_pc_o),
        .perf_partial_pair_instr_o(perf_partial_pair_instr_o),
        .perf_cross_line_pair_o(perf_cross_line_pair_o),
        .perf_cross_line_carry_o(perf_cross_line_carry_o),
        .perf_dispatch_pc_o(perf_dispatch_pc_o),
        .perf_dispatch_instr_o(perf_dispatch_instr_o),
        .frontend_fetch_pc_o(),
        .frontend_raw_queue_valid_mask_o(frontend_raw_queue_valid_mask),
        .frontend_raw_queue_pc0_o(),
        .frontend_raw_queue_pc1_o(),
        .frontend_request_outstanding_o(frontend_request_outstanding),
        .frontend_stale_response_pending_o(frontend_stale_response_pending),
        .frontend_fault_o(frontend_fault),
        .frontend_fault_pc_o(frontend_fault_pc),
        .frontend_eof_o(frontend_eof),
        .frontend_malformed_response_o(),
        .frontend_unsupported_seen_o(),
        .frontend_pending_clear_o(),
        .frontend_redirect_clear_o(),
        .frontend_stale_response_drop_o(),
        .frontend_conservation_error_o(frontend_conservation_error),
        .branch_protocol_error_o(branch_protocol_error),
        .recovery_conservation_error_o(recovery_conservation_error),
        .conservation_error_o(backend_conservation_error)
    );

    assign ext_if_req_valid_o = pair_fetch_req_valid;
    assign ext_if_req_addr_o = pair_fetch_req_addr;
    assign ext_if_req_pc_o = pair_fetch_req_pc;
    assign ext_if_rsp_ready_o = pair_fetch_rsp_ready;
    assign ext_fetch_pte_req_valid_o = fetch_pte_req_valid;
    assign ext_fetch_pte_req_addr_o = fetch_pte_req_addr;
    assign ext_fetch_pte_rsp_ready_o = fetch_pte_rsp_ready;
    assign ext_mem_req_valid_o = phys_mem_req_valid;
    assign ext_mem_req_write_o = phys_mem_req_write;
    assign ext_mem_req_addr_o = phys_mem_req_addr;
    assign ext_mem_req_wdata_o = phys_mem_req_wdata;
    assign ext_mem_req_wstrb_o = phys_mem_req_wstrb;
    assign ext_mem_req_len_o = phys_mem_req_len;
    assign ext_mem_req_token_o = phys_mem_req_token;
    assign ext_mem_rsp_ready_o = phys_mem_rsp_ready;

    generate
      if (EXTERNAL_MEMORY) begin : g_external_ifetch
        assign pair_fetch_req_ready = ext_if_req_ready_i;
        assign pair_fetch_rsp_valid = ext_if_rsp_valid_i;
        assign pair_fetch_rsp_addr = ext_if_rsp_addr_i;
        assign pair_fetch_rsp_valid_mask = ext_if_rsp_valid_mask_i;
        assign pair_fetch_rsp_data = ext_if_rsp_data_i;
        assign pair_fetch_rsp_eof = ext_if_rsp_eof_i;
        assign pair_fetch_rsp_error = ext_if_rsp_error_i;
        assign pair_ifetch_busy = ext_if_busy_q;
        assign ifetch_bridge_service = '0;
        assign ifetch_bridge_req_pc = '0;
        assign ifetch_protocol_error = 1'b0;
      end else begin : g_dpi_ifetch
        ooo_pipeline_dpi_ifetch_bridge_1w #(
            .DPI_CHANNEL(0),
            .SAME_EDGE_RESPONSE_CAPTURE_ENABLE(
                IFETCH_SAME_EDGE_RESPONSE_CAPTURE_ENABLE)
        ) u_ifetch_bridge (
            .clk(clk), .reset(reset),
            .req_valid_i(pair_fetch_req_valid), .req_ready_o(pair_fetch_req_ready),
            .req_addr_i(pair_fetch_req_addr), .req_pc_i(pair_fetch_req_pc),
            .rsp_valid_o(pair_fetch_rsp_valid), .rsp_ready_i(pair_fetch_rsp_ready),
            .rsp_addr_o(pair_fetch_rsp_addr),
            .rsp_valid_mask_o(pair_fetch_rsp_valid_mask),
            .rsp_data_o(pair_fetch_rsp_data), .rsp_eof_o(pair_fetch_rsp_eof),
            .rsp_error_o(pair_fetch_rsp_error), .busy_o(pair_ifetch_busy),
            .req_fire_o(), .rsp_capture_o(), .rsp_fire_o(),
            .debug_service_o(ifetch_bridge_service),
            .debug_req_pc_o(ifetch_bridge_req_pc),
            .protocol_error_o(ifetch_protocol_error)
        );
      end
    endgenerate

`ifdef NPC_SV32
    generate
      if (EXTERNAL_MEMORY) begin : g_external_fetch_pte
        assign fetch_pte_req_ready = ext_fetch_pte_req_ready_i;
        assign fetch_pte_rsp_valid = ext_fetch_pte_rsp_valid_i;
        assign fetch_pte_rsp_data = ext_fetch_pte_rsp_data_i;
        assign fetch_pte_rsp_error = ext_fetch_pte_rsp_error_i;
        assign fetch_pte_busy = ext_fetch_pte_busy_q;
        assign fetch_pte_protocol_error = 1'b0;
      end else begin : g_dpi_fetch_pte
        ooo_pipeline_dpi_mem_bridge_1w #(.DPI_CHANNEL(0)) u_fetch_pte_bridge (
            .clk(clk), .reset(reset), .req_valid_i(fetch_pte_req_valid),
            .req_ready_o(fetch_pte_req_ready), .req_write_i(1'b0),
            .req_addr_i(fetch_pte_req_addr), .req_wdata_i(32'b0),
            .req_wstrb_i(4'b0), .req_len_i(3'd4),
            .rsp_valid_o(fetch_pte_rsp_valid),
            .rsp_ready_i(fetch_pte_rsp_ready),
            .rsp_rdata_o(fetch_pte_rsp_data),
            .rsp_error_o(fetch_pte_rsp_error),
            .busy_o(fetch_pte_busy), .req_fire_o(), .rsp_capture_o(),
            .rsp_fire_o(), .protocol_error_o(fetch_pte_protocol_error)
        );
      end
    endgenerate

    ooo_pipeline_fetch_sv32_adapter_1w u_fetch_translate (
        .clk(clk), .reset(reset), .satp_i(csr_satp),
        .mstatus_i(csr_mstatus), .priv_i(csr_priv_mode),
        .req_valid_i(fetch_req_valid), .req_ready_o(fetch_req_ready),
        .req_addr_i(fetch_req_addr), .req_pc_i(fetch_req_pc),
        .rsp_valid_o(fetch_rsp_valid), .rsp_ready_i(fetch_rsp_ready),
        .rsp_addr_o(fetch_rsp_addr), .rsp_valid_mask_o(fetch_rsp_valid_mask),
        .rsp_data_o(fetch_rsp_data), .rsp_eof_o(fetch_rsp_eof),
        .rsp_error_o(fetch_rsp_error),
        .rsp_page_fault_o(fetch_rsp_page_fault),
        .pte_req_valid_o(fetch_pte_req_valid),
        .pte_req_ready_i(fetch_pte_req_ready),
        .pte_req_addr_o(fetch_pte_req_addr),
        .pte_rsp_valid_i(fetch_pte_rsp_valid),
        .pte_rsp_ready_o(fetch_pte_rsp_ready),
        .pte_rsp_data_i(fetch_pte_rsp_data),
        .pte_rsp_error_i(fetch_pte_rsp_error),
        .pair_req_valid_o(pair_fetch_req_valid),
        .pair_req_ready_i(pair_fetch_req_ready),
        .pair_req_addr_o(pair_fetch_req_addr),
        .pair_req_pc_o(pair_fetch_req_pc),
        .pair_rsp_valid_i(pair_fetch_rsp_valid),
        .pair_rsp_ready_o(pair_fetch_rsp_ready),
        .pair_rsp_addr_i(pair_fetch_rsp_addr),
        .pair_rsp_valid_mask_i(pair_fetch_rsp_valid_mask),
        .pair_rsp_data_i(pair_fetch_rsp_data),
        .pair_rsp_eof_i(pair_fetch_rsp_eof),
        .pair_rsp_error_i(pair_fetch_rsp_error),
        .busy_o(fetch_translate_busy),
        .conservation_error_o(fetch_translate_error)
    );
`else
    assign pair_fetch_req_valid = fetch_req_valid;
    assign fetch_req_ready = pair_fetch_req_ready;
    assign pair_fetch_req_addr = fetch_req_addr;
    assign pair_fetch_req_pc = fetch_req_pc;
    assign fetch_rsp_valid = pair_fetch_rsp_valid;
    assign pair_fetch_rsp_ready = fetch_rsp_ready;
    assign fetch_rsp_addr = pair_fetch_rsp_addr;
    assign fetch_rsp_valid_mask = pair_fetch_rsp_valid_mask;
    assign fetch_rsp_data = pair_fetch_rsp_data;
    assign fetch_rsp_eof = pair_fetch_rsp_eof;
    assign fetch_rsp_error = pair_fetch_rsp_error;
    assign fetch_rsp_page_fault = 1'b0;
    assign fetch_pte_req_valid = 1'b0;
    assign fetch_pte_req_addr = 32'b0;
    assign fetch_pte_rsp_ready = 1'b0;
    assign fetch_pte_busy = 1'b0;
    assign fetch_translate_busy = 1'b0;
    assign fetch_translate_error = 1'b0;
    assign fetch_pte_protocol_error = 1'b0;
`endif

    assign ifetch_busy = pair_ifetch_busy || fetch_pte_busy || fetch_translate_busy;
    assign perf_fetch_response_service_o =
        FETCH_RESPONSE_SERVICE_ORACLE_ENABLE ?
        {ifetch_bridge_req_pc, 16'b0, ifetch_bridge_service} : 64'b0;

    generate
      if (EXTERNAL_MEMORY) begin : g_external_data
        assign phys_mem_req_ready = ext_mem_req_ready_i;
        assign phys_mem_rsp_valid = ext_mem_rsp_valid_i;
        assign phys_mem_rsp_rdata = ext_mem_rsp_rdata_i;
        assign phys_mem_rsp_error = ext_mem_rsp_error_i;
        assign phys_mem_rsp_token = ext_mem_rsp_token_i;
        assign phys_mem_busy = |ext_mem_outstanding_q;
        assign phys_mem_protocol_error = ext_mem_protocol_error_q;
        assign tagged_bridge_load_turnover = '0;
      end else begin : g_dpi_data
        logic bridge_protocol_error;
        logic bridge_unknown_response;
        logic bridge_duplicate_response;

        ooo_pipeline_tagged_dpi_mem_bridge_2entry #(
            .DPI_CHANNEL(1),
            .LOAD_TRANSACTION_DEPTH3_ENABLE(LOAD_TRANSACTION_DEPTH3_ENABLE)
        ) u_mem_bridge (
            .clk(clk), .reset(reset),
            .req_valid_i(phys_mem_req_valid), .req_ready_o(phys_mem_req_ready),
            .req_write_i(phys_mem_req_write), .req_addr_i(phys_mem_req_addr),
            .req_wdata_i(phys_mem_req_wdata),
            .req_wstrb_i(phys_mem_req_wstrb),
            .req_len_i(phys_mem_req_len), .req_token_i(phys_mem_req_token),
            .debug_load_offer_valid_i(perf_raw_load_offer_valid),
            .debug_load_offer_len_i(perf_raw_load_offer_len),
            .debug_load_offer_token_i(perf_raw_load_offer_token),
            .rsp_valid_o(phys_mem_rsp_valid),
            .rsp_ready_i(phys_mem_rsp_ready),
            .rsp_rdata_o(phys_mem_rsp_rdata),
            .rsp_error_o(phys_mem_rsp_error),
            .rsp_token_o(phys_mem_rsp_token),
            .busy_o(phys_mem_busy),
            .outstanding_count_o(), .max_outstanding_o(),
            .req_fire_o(), .rsp_capture_o(), .rsp_fire_o(),
            .unknown_response_guard_o(bridge_unknown_response),
            .duplicate_response_guard_o(bridge_duplicate_response),
            .protocol_error_o(bridge_protocol_error),
            .debug_load_turnover_o(tagged_bridge_load_turnover)
        );
        assign phys_mem_protocol_error = bridge_protocol_error ||
            bridge_unknown_response || bridge_duplicate_response;
      end
    endgenerate

    ooo_data_line_cache #(
        .ENABLE(DATA_LINE_HIT_ENABLE),
        .SAME_WORD_MISS_COALESCING_ENABLE(
            DATA_LINE_SAME_WORD_MISS_COALESCING_ENABLE),
        .STORE_RESPONSE_UPDATE_ENABLE(
            DATA_LINE_STORE_RESPONSE_UPDATE_ENABLE),
        .LINE_COUNT(DATA_LINE_COUNT),
        .WAY_COUNT(DATA_LINE_WAY_COUNT)
    ) u_data_line_cache (
        .clk(clk), .reset(reset),
        .req_valid_i(mem_req_valid), .req_ready_o(mem_req_ready),
        .req_write_i(mem_req_write), .req_addr_i(mem_req_addr),
        .req_wdata_i(mem_req_wdata), .req_wstrb_i(mem_req_wstrb),
        .req_len_i(mem_req_len), .req_token_i(mem_req_token),
        .debug_load_offer_valid_i(perf_raw_load_offer_valid),
        .debug_load_offer_addr_i(perf_raw_load_offer_addr),
        .debug_load_offer_len_i(perf_raw_load_offer_len),
        .debug_load_offer_token_i(perf_raw_load_offer_token),
        .debug_bridge_load_ready_i(tagged_bridge_load_turnover[6]),
        .debug_bridge_load_depth3_ready_i(tagged_bridge_load_turnover[7]),
        .rsp_valid_o(mem_rsp_valid), .rsp_ready_i(mem_rsp_ready),
        .rsp_rdata_o(mem_rsp_rdata), .rsp_error_o(mem_rsp_error),
        .rsp_token_o(mem_rsp_token),
        .mem_req_valid_o(phys_mem_req_valid),
        .mem_req_ready_i(phys_mem_req_ready),
        .mem_req_write_o(phys_mem_req_write),
        .mem_req_addr_o(phys_mem_req_addr),
        .mem_req_wdata_o(phys_mem_req_wdata),
        .mem_req_wstrb_o(phys_mem_req_wstrb),
        .mem_req_len_o(phys_mem_req_len),
        .mem_req_token_o(phys_mem_req_token),
        .mem_rsp_valid_i(phys_mem_rsp_valid),
        .mem_rsp_ready_o(phys_mem_rsp_ready),
        .mem_rsp_rdata_i(phys_mem_rsp_rdata),
        .mem_rsp_error_i(phys_mem_rsp_error),
        .mem_rsp_token_i(phys_mem_rsp_token),
        .busy_o(data_line_busy), .hit_o(data_line_hit),
        .miss_o(data_line_miss), .fill_o(data_line_fill),
        .invalidate_o(data_line_invalidate),
        .perf_causality_o(data_line_causality),
        .perf_coalescing_o(data_line_coalescing),
        .perf_invalidation_causality_o(
            data_line_invalidation_causality),
        .perf_store_origin_o(data_line_store_origin),
        .debug_load_turnover_o(data_line_load_turnover),
        .conservation_error_o(data_line_error)
    );
    assign mem_busy = phys_mem_busy || data_line_busy;
    assign mem_protocol_error = phys_mem_protocol_error || data_line_error;

    always_ff @(posedge clk) begin
      if (reset || !EXTERNAL_MEMORY) begin
        ext_if_busy_q <= 1'b0;
        ext_fetch_pte_busy_q <= 1'b0;
        ext_mem_outstanding_q <= 2'b00;
        ext_mem_protocol_error_q <= 1'b0;
      end else begin
        if (pair_fetch_req_valid && pair_fetch_req_ready)
          ext_if_busy_q <= 1'b1;
        if (pair_fetch_rsp_valid && pair_fetch_rsp_ready)
          ext_if_busy_q <= 1'b0;
        if (fetch_pte_req_valid && fetch_pte_req_ready)
          ext_fetch_pte_busy_q <= 1'b1;
        if (fetch_pte_rsp_valid && fetch_pte_rsp_ready)
          ext_fetch_pte_busy_q <= 1'b0;
        if ((phys_mem_rsp_valid && phys_mem_rsp_ready &&
             (ext_mem_outstanding_q == 2'b00)) ||
            (phys_mem_req_valid && phys_mem_req_ready &&
             !(phys_mem_rsp_valid && phys_mem_rsp_ready) &&
             (ext_mem_outstanding_q == 2'd2)))
          ext_mem_protocol_error_q <= 1'b1;
        unique case ({phys_mem_req_valid && phys_mem_req_ready,
                      phys_mem_rsp_valid && phys_mem_rsp_ready})
          2'b10: if (ext_mem_outstanding_q != 2'd2)
            ext_mem_outstanding_q <= ext_mem_outstanding_q + 2'd1;
          2'b01: if (ext_mem_outstanding_q != 2'd0)
            ext_mem_outstanding_q <= ext_mem_outstanding_q - 2'd1;
          default: ext_mem_outstanding_q <= ext_mem_outstanding_q;
        endcase
      end
    end

`ifdef NPC_SV32
    ooo_pipeline_data_sv32_adapter_2entry u_data_translate (
        .clk(clk), .reset(reset), .satp_i(csr_satp),
        .mstatus_i(csr_mstatus), .priv_i(csr_priv_mode),
        .req_valid_i(pipeline_mem_req_valid),
        .req_ready_o(pipeline_mem_req_ready),
        .req_write_i(pipeline_mem_req_write),
        .req_access_i(pipeline_mem_req_access),
        .req_addr_i(pipeline_mem_req_addr),
        .req_wdata_i(pipeline_mem_req_wdata),
        .req_wstrb_i(pipeline_mem_req_wstrb),
        .req_len_i(pipeline_mem_req_len),
        .req_token_i(pipeline_mem_req_token),
        .rsp_valid_o(pipeline_mem_rsp_valid),
        .rsp_ready_i(pipeline_mem_rsp_ready),
        .rsp_rdata_o(pipeline_mem_rsp_rdata),
        .rsp_error_o(pipeline_mem_rsp_error),
        .rsp_page_fault_o(pipeline_mem_rsp_page_fault),
        .rsp_token_o(pipeline_mem_rsp_token),
        .mem_req_valid_o(mem_req_valid), .mem_req_ready_i(mem_req_ready),
        .mem_req_write_o(mem_req_write), .mem_req_addr_o(mem_req_addr),
        .mem_req_wdata_o(mem_req_wdata), .mem_req_wstrb_o(mem_req_wstrb),
        .mem_req_len_o(mem_req_len), .mem_req_token_o(mem_req_token),
        .mem_rsp_valid_i(mem_rsp_valid),
        .mem_rsp_ready_o(mem_rsp_ready), .mem_rsp_rdata_i(mem_rsp_rdata),
        .mem_rsp_error_i(mem_rsp_error), .mem_rsp_token_i(mem_rsp_token),
        .busy_o(data_translate_busy),
        .conservation_error_o(data_translate_error)
    );
`else
    assign mem_req_valid = pipeline_mem_req_valid;
    assign pipeline_mem_req_ready = mem_req_ready;
    assign mem_req_write = pipeline_mem_req_write;
    assign mem_req_addr = pipeline_mem_req_addr;
    assign mem_req_wdata = pipeline_mem_req_wdata;
    assign mem_req_wstrb = pipeline_mem_req_wstrb;
    assign mem_req_len = pipeline_mem_req_len;
    assign mem_req_token = pipeline_mem_req_token;
    assign pipeline_mem_rsp_valid = mem_rsp_valid;
    assign mem_rsp_ready = pipeline_mem_rsp_ready;
    assign pipeline_mem_rsp_rdata = mem_rsp_rdata;
    assign pipeline_mem_rsp_error = mem_rsp_error;
    assign pipeline_mem_rsp_page_fault = 1'b0;
    assign pipeline_mem_rsp_token = mem_rsp_token;
    assign data_translate_busy = 1'b0;
    assign data_translate_error = 1'b0;
`endif

    ooo_pipeline_serial_executor_1w #(
        .STORE_ISSUE_FINAL_FALLTHROUGH_ENABLE(
            STORE_ISSUE_FINAL_FALLTHROUGH_ENABLE),
        .MDU_MUL_COMPLETION_FALLTHROUGH_ENABLE(
            MDU_MUL_COMPLETION_FALLTHROUGH_ENABLE)
    ) u_serial_executor (
        .clk(clk), .reset(reset), .flush_i(recovery_done),
        .selective_kill_valid_i(selective_kill_valid),
        .selective_killed_rob_mask_i(selective_killed_rob_mask),
        .selective_kill_drop_o(),
        .issue_valid_i(serial_issue_valid), .issue_uop_i(serial_issue_uop),
        .src1_data_i(serial_issue_src1), .src2_data_i(serial_issue_src2),
        .issue_kind_i(serial_issue_kind), .issue_ready_o(serial_issue_ready),
        .issue_accept_o(), .completion_valid_o(serial_completion_valid),
        .completion_ready_i(serial_completion_ready),
        .completion_wb_o(serial_completion_wb),
        .completion_kind_o(serial_completion_kind),
        .commit_event_i(commit_event_o), .occupied_o(serial_occupied),
        .flush_drop_o(), .illegal_issue_o(serial_illegal_issue),
        .ebreak_accept_o(serial_ebreak_accept), .exception_accept_o(),
        .debug_csr_mstatus_o(csr_mstatus), .debug_csr_mtvec_o(csr_mtvec),
        .debug_csr_mepc_o(csr_mepc), .debug_csr_mcause_o(),
        .debug_csr_satp_o(csr_satp), .debug_priv_mode_o(csr_priv_mode),
        .debug_trap_target_o(csr_trap_target),
        .debug_xret_target_o(csr_xret_target),
        .debug_store_fallthrough_valid_o(),
        .debug_store_fallthrough_accept_o(),
        .debug_store_fallthrough_capture_o(),
        .fallthrough_conservation_error_o(
            serial_fallthrough_conservation_error)
    );

    ooo_commit_trace_adapter #(
        .DUAL_TRACE_SINK_ENABLE(DUAL_TRACE_SINK_ENABLE)
    ) u_trace (
        .clk(clk), .reset(reset), .commit_event_i(commit_event_o),
        .exception_nextpc_valid_i(1'b1),
        .exception_nextpc_i(csr_trap_target),
        .trace_can_accept1_o(trace_can_accept1),
        .trace_can_accept2_o(trace_can_accept2),
        .trace_valid_o(trace_valid), .trace1_valid_o(trace1_valid),
        .trace_ready_i(commit_ready_i),
        .trace_packet_o(trace_packet), .trace_packet1_o(trace_packet1),
        .debug_packet_buffer_valid_o(debug_trace_buffer_valid_o),
        .debug_last_packet_accepted_o(), .debug_last_commit_dropped_o(),
        .debug_commit2_trace_slot1_o(),
        .debug_fifo_count_o(trace_fifo_count),
        .debug_enqueue_count_o(trace_enqueue_count),
        .debug_dequeue_count_o(trace_dequeue_count),
        .debug_packet_accepted_o(trace_packet_accepted),
        .debug_fifo_overflow_o(trace_fifo_overflow)
    );
    assign perf_trace_width_oracle_o = {
        trace_fifo_overflow, trace_can_accept2, trace_fifo_count,
        trace_dequeue_count, trace_enqueue_count
    };

    ooo_shadow_arch_state #(
        .RESET_VECTOR(RESET_VECTOR),
        .DUAL_COMMIT_ENABLE(DUAL_TRACE_SINK_ENABLE)
    ) u_arch_shadow (
        .clk(clk), .reset(reset), .commit_valid_i(trace_accept),
        .commit_nextpc_i(trace_packet.commit_nextpc),
        .commit_rf_wen_i(trace_packet.rf_wen &&
            !trace_packet.exception_valid && !trace_packet.unsupported),
        .commit_rd_i(trace_packet.arch_rd),
        .commit_wdata_i(trace_packet.wdata),
        .commit1_valid_i(trace_accept1),
        .commit1_nextpc_i(trace_packet1.commit_nextpc),
        .commit1_rf_wen_i(trace_packet1.rf_wen &&
            !trace_packet1.exception_valid && !trace_packet1.unsupported),
        .commit1_rd_i(trace_packet1.arch_rd),
        .commit1_wdata_i(trace_packet1.wdata),
        .debug_arch_idx_i(debug_arch_idx_i),
        .debug_arch_gpr_o(debug_arch_gpr_o),
        .debug_arch_pc_o(debug_arch_pc_o)
    );

    ooo_npc_commit_trace_bridge #(
        .DUAL_TRACE_SINK_ENABLE(DUAL_TRACE_SINK_ENABLE)
    ) u_trace_bridge (
        .clk(clk), .reset(reset), .trace_valid_i(trace_valid),
        .trace_ready_i(commit_ready_i), .trace_packet_i(trace_packet),
        .trace1_valid_i(trace1_valid), .trace_packet1_i(trace_packet1),
        .commit_valid_o(bridge_commit_valid),
        .commit_mask_o(bridge_commit_mask),
        .commit_slot1_o(bridge_commit_slot1),
        .commit_pc_o(bridge_commit_pc), .commit_instr_o(bridge_commit_instr),
        .commit_nextpc_o(bridge_commit_nextpc),
        .commit_rf_wen_o(bridge_commit_rf_wen),
        .commit_rd_o(bridge_commit_rd), .commit_wdata_o(bridge_commit_wdata),
        .commit_is_load_o(bridge_commit_is_load),
        .commit_is_store_o(bridge_commit_is_store),
        .commit_is_branch_o(bridge_commit_is_branch),
        .commit_is_jal_o(bridge_commit_is_jal),
        .commit_is_jalr_o(bridge_commit_is_jalr),
        .commit_mem_addr_o(bridge_commit_mem_addr),
        .commit_mem_wdata_o(bridge_commit_mem_wdata),
        .commit_mem_wstrb_o(bridge_commit_mem_wstrb),
        .commit_mem_len_o(bridge_commit_mem_len),
        .commit_unsupported_o(bridge_commit_unsupported),
        .commit_exception_valid_o(bridge_commit_exception),
        .commit1_valid_o(bridge_commit1_valid),
        .commit1_packet_o(bridge_commit1_packet),
        .debug_lane1_without_lane0_o(bridge_lane1_without_lane0)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            ebreak_seen_q <= 1'b0;
            ebreak_inflight_q <= 1'b0;
            ebreak_recover_q <= 1'b0;
            ebreak_pc_q <= '0;
            ebreak_instr_q <= '0;
        end else begin
            ebreak_recover_q <= 1'b0;
            if (serial_ebreak_accept) begin
                ebreak_inflight_q <= 1'b1;
            end
            if (ebreak_commit && !ebreak_seen_q) begin
                ebreak_seen_q <= 1'b1;
                ebreak_recover_q <= 1'b1;
                ebreak_pc_q <= commit_event_o.slot0.pc;
                ebreak_instr_q <= commit_event_o.slot0.instr;
            end
        end
    end

    always_comb begin
        commit_packet_o = '0;
        commit_packet_o.valid = bridge_commit_valid;
        commit_packet_o.commit_mask = bridge_commit_mask;
        commit_packet_o.commit_slot1 = bridge_commit_slot1;
        commit_packet_o.pc = bridge_commit_pc;
        commit_packet_o.instr = bridge_commit_instr;
        commit_packet_o.commit_nextpc = bridge_commit_nextpc;
        commit_packet_o.rf_wen = bridge_commit_rf_wen;
        commit_packet_o.arch_rd = bridge_commit_rd;
        commit_packet_o.wdata = bridge_commit_wdata;
        commit_packet_o.is_load = bridge_commit_is_load;
        commit_packet_o.is_store = bridge_commit_is_store;
        commit_packet_o.is_branch = bridge_commit_is_branch;
        commit_packet_o.is_jal = bridge_commit_is_jal;
        commit_packet_o.is_jalr = bridge_commit_is_jalr;
        commit_packet_o.mem_addr = bridge_commit_mem_addr;
        commit_packet_o.mem_wdata = bridge_commit_mem_wdata;
        commit_packet_o.mem_wstrb = bridge_commit_mem_wstrb;
        commit_packet_o.mem_len = bridge_commit_mem_len;
        commit_packet_o.unsupported = bridge_commit_unsupported;
        commit_packet_o.exception_valid = bridge_commit_exception;
    end
    assign commit_valid_o = bridge_commit_valid;
    assign commit1_valid_o = bridge_commit1_valid;
    assign commit_packet1_o = bridge_commit1_packet;
    assign unsupported_seen_o = frontend_fault;
    assign unsupported_pc_o = frontend_fault_pc;
    assign unsupported_instr_o = 32'b0;
    assign debug_control_pending_o = branch_window_active ||
        branch_recovery_pending || dispatch_freeze || serial_dispatch_block ||
        serial_barrier;
    assign debug_memory_pending_o = mem_busy || data_translate_busy;
    assign debug_frontend_busy_o = ifetch_busy || frontend_request_outstanding ||
        frontend_stale_response_pending;
    assign idle_o = !backend_busy && !serial_occupied && !ifetch_busy &&
        !mem_busy && !data_translate_busy && !trace_valid &&
        !bridge_commit_valid && !bridge_commit1_valid &&
        (frontend_raw_queue_valid_mask == 2'b00) &&
        (frontend_decode_buffer_valid_mask == 2'b00);
    assign halt_valid_o = ebreak_seen_q && idle_o;
    assign halt_pc_o = ebreak_pc_q;
    assign halt_instr_o = ebreak_instr_q;
    assign halt_reason_o = halt_valid_o ? HALT_REASON_EBREAK : 4'd0;
    assign debug_commit_fire_o = bridge_commit_valid;
    assign debug_commit2_fire_o = bridge_commit_valid && bridge_commit_mask[1];
    assign pipeline_commit_width = {1'b0, commit_event_o.slot0.valid} +
        {1'b0, commit_event_o.slot1.valid};
    assign frontend_raw_occupancy = {2'b0, frontend_raw_queue_valid_mask[0]} +
        {2'b0, frontend_raw_queue_valid_mask[1]};
    assign frontend_decode_occupancy =
        {2'b0, frontend_decode_buffer_valid_mask[0]} +
        {2'b0, frontend_decode_buffer_valid_mask[1]};
    assign perf_stage_widths_o = {
        pipeline_commit_width,
        ({1'b0, pipeline_final_consume[0]} +
         {1'b0, pipeline_final_consume[1]}),
        pipeline_issue_width,
        pipeline_dispatch_width,
        pipeline_decode_width
    };
    assign perf_lost_reasons_o = {
        pipeline_commit_reason1, pipeline_commit_reason0,
        pipeline_issue_reason1, pipeline_issue_reason0,
        pipeline_dispatch_reason1, pipeline_dispatch_reason0
    };
    assign perf_occupancy_o = {
        pipeline_perf_store_buffer,
        frontend_decode_occupancy,
        frontend_raw_occupancy,
        frontend_free_count,
        debug_iq_count_o,
        debug_rob_count_o
    };
    assign perf_selective_transaction_fire_o = selective_kill_valid;
    assign perf_store_admission_o = pipeline_perf_store_admission;
    always_comb begin
        perf_events_o = pipeline_perf_events;
        perf_events_o[48] = pair_fetch_req_valid && pair_fetch_req_ready;
        perf_events_o[49] = pair_fetch_rsp_valid && pair_fetch_rsp_ready;
        perf_events_o[50] = fetch_pte_req_valid && fetch_pte_req_ready;
        perf_events_o[51] = fetch_pte_rsp_valid && fetch_pte_rsp_ready;
        perf_events_o[52] = pipeline_mem_req_valid && pipeline_mem_req_ready;
        perf_events_o[53] = pipeline_mem_rsp_valid && pipeline_mem_rsp_ready;
        perf_events_o[54] = phys_mem_req_valid && phys_mem_req_ready;
        perf_events_o[55] = phys_mem_rsp_valid && phys_mem_rsp_ready;
        perf_events_o[56] = fetch_translate_busy;
        perf_events_o[57] = data_translate_busy;
        perf_events_o[58] = trace_valid && !commit_ready_i;
        perf_events_o[59] = (debug_rob_count_o != 4'd0) && !commit_enable;
        perf_events_o[60] = fetch_rsp_page_fault || pipeline_mem_rsp_page_fault;
        perf_events_o[61] = frontend_fault;
        perf_events_o[62] = halt_valid_o;
        perf_events_o[63] = debug_conservation_error_o;

        perf_lifecycle_o = pipeline_perf_lifecycle;
        perf_lifecycle_o[13] = selective_kill_valid;
        if (selective_kill_valid)
            perf_lifecycle_o[23:16] = selective_killed_rob_mask;
        // Use the final physical data-memory boundary so page walks and the
        // translated access are measured exactly as accepted by channel 1.
        perf_lifecycle_o[11] = phys_mem_req_valid && phys_mem_req_ready;
        perf_lifecycle_o[12] = phys_mem_rsp_valid && phys_mem_rsp_ready;
        perf_branch_producer_phase_o =
            pipeline_perf_branch_producer_phase;
        perf_lsu_causality_o = '0;
        perf_lsu_causality_o[31:0] = pipeline_perf_lsu_causality;
        if (data_line_causality[1]) begin
            perf_lsu_causality_o[32] = 1'b1;
            perf_lsu_causality_o[36:33] = 4'd2;
        end else if (data_line_coalescing[0]) begin
            perf_lsu_causality_o[32] = 1'b1;
            perf_lsu_causality_o[36:33] = 4'd3;
        end else if (data_line_causality[3]) begin
            perf_lsu_causality_o[32] = 1'b1;
            perf_lsu_causality_o[36:33] = 4'd4;
        end else if (data_line_causality[4]) begin
            perf_lsu_causality_o[32] = 1'b1;
            perf_lsu_causality_o[36:33] = 4'd5;
        end else if (data_line_causality[5]) begin
            perf_lsu_causality_o[32] = 1'b1;
            perf_lsu_causality_o[36:33] = 4'd6;
        end else if (phys_mem_req_valid && phys_mem_req_ready &&
                     phys_mem_req_token.valid &&
                     (phys_mem_req_token.client ==
                      BBUS_OOO_MEM_CLIENT_LSU_LOAD)) begin
            perf_lsu_causality_o[32] = 1'b1;
            perf_lsu_causality_o[36:33] = 4'd7;
        end
        if (perf_lsu_causality_o[32] &&
            (perf_lsu_causality_o[36:33] == 4'd7)) begin
            perf_lsu_causality_o[41:37] = phys_mem_req_token.slot[0] ?
                pipeline_perf_branch_producer_phase[15:11] :
                pipeline_perf_branch_producer_phase[7:3];
            perf_lsu_causality_o[54] = phys_mem_req_token.slot[0] ?
                pipeline_perf_branch_producer_phase[8] :
                pipeline_perf_branch_producer_phase[0];
        end else begin
            perf_lsu_causality_o[41:37] = mem_req_token.slot[0] ?
                pipeline_perf_branch_producer_phase[15:11] :
                pipeline_perf_branch_producer_phase[7:3];
            perf_lsu_causality_o[54] = mem_req_token.slot[0] ?
                pipeline_perf_branch_producer_phase[8] :
                pipeline_perf_branch_producer_phase[0];
        end
        perf_lsu_causality_o[42] = perf_lsu_causality_o[32] &&
            ((perf_lsu_causality_o[36:33] < 4'd2) ||
             (perf_lsu_causality_o[36:33] > 4'd7));
        perf_lsu_causality_o[43] = phys_mem_req_valid &&
            phys_mem_req_ready && phys_mem_req_token.valid;
        perf_lsu_causality_o[45:44] = phys_mem_req_token.client;
        perf_lsu_causality_o[46] = phys_mem_rsp_valid &&
            phys_mem_rsp_ready && phys_mem_rsp_token.valid;
        perf_lsu_causality_o[47] = perf_lsu_causality_o[46] &&
            (phys_mem_rsp_token.client == BBUS_OOO_MEM_CLIENT_LSU_LOAD);
        perf_lsu_causality_o[52:48] =
            data_line_invalidation_causality[4:0];
        perf_lsu_causality_o[63:55] =
            pipeline_perf_lsu_causality[40:32];
        perf_composite_load_turnover_o = '0;
        perf_composite_load_turnover_o[31:0] = data_line_load_turnover;
        perf_composite_load_turnover_o[39:32] =
            tagged_bridge_load_turnover;
`ifdef NPC_SV32
        perf_composite_load_turnover_o[40] = 1'b1;
`endif
        perf_composite_load_turnover_o[41] =
            pipeline_mem_req_valid && pipeline_mem_req_ready &&
            !pipeline_mem_req_write && pipeline_mem_req_token.valid &&
            (pipeline_mem_req_token.client ==
             BBUS_OOO_MEM_CLIENT_LSU_LOAD);
        perf_composite_load_turnover_o[42] =
            phys_mem_req_valid && phys_mem_req_ready;
        perf_composite_load_turnover_o[43] = perf_raw_load_offer_valid;
        perf_composite_load_turnover_o[44] =
            perf_raw_load_offer_token.slot[0];
        perf_composite_load_turnover_o[45] =
            perf_raw_load_offer_token.valid;
        perf_composite_load_turnover_o[46] = pipeline_mem_req_valid;
        perf_composite_load_turnover_o[47] = pipeline_mem_req_ready;
        perf_composite_load_turnover_o[48] = mem_req_valid;
        perf_composite_load_turnover_o[49] = mem_req_ready;
        perf_composite_load_turnover_o[50] = phys_mem_req_valid;
        perf_composite_load_turnover_o[51] = phys_mem_req_ready;
        perf_composite_load_turnover_o[52] =
            phys_mem_rsp_valid && phys_mem_rsp_ready;
        perf_composite_load_turnover_o[53] =
            mem_rsp_valid && mem_rsp_ready;
        perf_composite_load_turnover_o[60:54] =
            pipeline_perf_lsu_causality[152:146];
        perf_composite_load_turnover_o[62:61] =
            pipeline_perf_lsu_causality[154:153];
        perf_composite_load_turnover_o[63] =
            pipeline_perf_lsu_causality[155];
        perf_data_line_o = {
            data_line_invalidate, data_line_miss,
            data_line_fill, data_line_hit
        };
        perf_data_line_causality_o = data_line_causality;
        perf_data_line_coalescing_o = data_line_coalescing;
        perf_data_line_store_origin_o = data_line_store_origin;
        // Request and response may fire together with different generations.
        // Event validity remains on perf_lsu_causality_o[23:24].
        perf_store_transaction_o = {
            mem_rsp_token.generation, mem_req_token.generation
        };
    end
    assign debug_conservation_error_o = frontend_conservation_error ||
        branch_protocol_error || recovery_conservation_error ||
        backend_conservation_error || ifetch_protocol_error ||
        fetch_pte_protocol_error || fetch_translate_error ||
        mem_protocol_error || data_translate_error || serial_illegal_issue ||
        serial_fallthrough_conservation_error ||
        trace_fifo_overflow || bridge_lane1_without_lane0;

    /* verilator lint_off UNUSED */
    wire trace_can_accept1_unused = trace_can_accept1;
    wire frontend_eof_unused = frontend_eof;
    /* verilator lint_on UNUSED */
endmodule
