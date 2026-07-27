`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// No-DPI production wrapper used only for relative synthesis/PPA tracking.
// The instantiated core is the same pipeline core as ooo_npc_top; memory
// timing and storage arrays remain outside this boundary.
module ooo_pipeline_synth_core_top #(
    parameter bit RAW_COMPLETION_WAKEUP_ENABLE = 1'b1,
    parameter bit SAME_CYCLE_DEPENDENCY_FORWARDING_ENABLE = 1'b1,
    parameter bit HEAD_LOAD_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b1,
    parameter bit HEAD_ALU_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b0,
    parameter bit HEAD_BRU_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b0,
    parameter bit LOAD_RESPONSE_COMPLETION_BYPASS_ENABLE = 1'b1,
    parameter bit PAIR_RAW_TO_FINAL_BYPASS_ENABLE = 1'b0,
    parameter bit DECODE_DISPATCH_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit FETCH_DECODE_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit FETCH_RESPONSE_CREDIT_TURNOVER_ENABLE = 1'b0,
    parameter bit IFETCH_SAME_EDGE_RESPONSE_CAPTURE_ENABLE = 1'b0,
    parameter bit TARGET_LINE_HIT_ENABLE = 1'b1,
    parameter int unsigned TARGET_LINE_ENTRY_COUNT = 128,
    parameter int unsigned TARGET_LINE_WAY_COUNT = 1,
    parameter int unsigned CONDITIONAL_PRED_ENTRIES = 256,
    parameter bit CORRELATED_PREDICTOR_ENABLE = 1'b1,
    parameter bit SAME_CYCLE_RAS_UPDATE_FORWARDING_ENABLE = 1'b1,
    parameter bit SEQUENTIAL_LINE_HIT_ENABLE = 1'b1,
    parameter bit BRANCH_WINDOW_LINE_DELIVERY_ENABLE = 1'b1,
    parameter bit SPECULATIVE_STORE_DISPATCH_ENABLE = 1'b1,
    parameter bit ORDERED_TARGET_PREFETCH_ORACLE_ENABLE = 1'b0,
    parameter bit DEMAND_FETCH_LATENCY_ORACLE_ENABLE = 1'b0,
    parameter bit FETCH_RESPONSE_SERVICE_ORACLE_ENABLE = 1'b0,
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
    parameter bit SAME_CYCLE_DISPATCH_ISSUE_ENABLE = 1'b0,
    parameter bit SAME_CYCLE_BRANCH_DISPATCH_ISSUE_ENABLE = 1'b0,
    parameter bit SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE = 1'b0,
    parameter bit LSU_REQUEST_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit CORRECT_BRANCH_DUAL_RETIRE_ENABLE = 1'b0,
    parameter bit YOUNGER_SLOT1_CONTROL_DUAL_RETIRE_ENABLE = 1'b0,
    parameter bit POST_SELECTIVE_REDIRECT_COMMIT_ENABLE = 1'b0,
    parameter bit SELECTIVE_TRANSACTION_REDIRECT_OVERLAP_ENABLE = 1'b0,
    parameter bit STRONG_BRANCH_LINE_DELIVERY_ENABLE = 1'b0,
    parameter bit CACHED_CROSS_LINE_PAIR_ENABLE = 1'b0,
    parameter bit CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE = 1'b0,
    parameter bit DUAL_TRACE_SINK_ENABLE = 1'b0,
    parameter bit DATA_LINE_SAME_WORD_MISS_COALESCING_ENABLE = 1'b0,
    parameter bit DATA_LINE_STORE_RESPONSE_UPDATE_ENABLE = 1'b0,
    parameter bit RAS_SELF_FORWARD_EXCLUSION_ENABLE = 1'b0,
    parameter bit DATA_LINE_HIT_ENABLE = 1'b1,
    parameter int unsigned DATA_LINE_COUNT = 64,
    parameter int unsigned DATA_LINE_WAY_COUNT = 1
) (
    input  logic clk,
    input  logic reset,

    output logic if_req_valid_o,
    input  logic if_req_ready_i,
    output logic [31:0] if_req_addr_o,
    output logic [31:0] if_req_pc_o,
    input  logic if_rsp_valid_i,
    output logic if_rsp_ready_o,
    input  logic [31:0] if_rsp_addr_i,
    input  logic [1:0] if_rsp_valid_mask_i,
    input  logic [63:0] if_rsp_data_i,
    input  logic if_rsp_eof_i,
    input  logic if_rsp_error_i,

    output logic fetch_pte_req_valid_o,
    input  logic fetch_pte_req_ready_i,
    output logic [31:0] fetch_pte_req_addr_o,
    input  logic fetch_pte_rsp_valid_i,
    output logic fetch_pte_rsp_ready_o,
    input  logic [31:0] fetch_pte_rsp_data_i,
    input  logic fetch_pte_rsp_error_i,

    output logic mem_req_valid_o,
    input  logic mem_req_ready_i,
    output logic mem_req_write_o,
    output logic [31:0] mem_req_addr_o,
    output logic [31:0] mem_req_wdata_o,
    output logic [3:0] mem_req_wstrb_o,
    output logic [2:0] mem_req_len_o,
    output bbus_ooo_mem_token_t mem_req_token_o,
    input  logic mem_rsp_valid_i,
    output logic mem_rsp_ready_o,
    input  logic [31:0] mem_rsp_rdata_i,
    input  logic mem_rsp_error_i,
    input  bbus_ooo_mem_token_t mem_rsp_token_i,

    output logic commit_valid_o,
    output logic [31:0] commit_pc_o,
    output logic [31:0] commit_instr_o,
    output logic [31:0] commit_nextpc_o,
    output logic halt_valid_o,
    output logic conservation_error_o,
    output logic [3:0] rob_count_o,
    output logic [3:0] iq_count_o
);
    bbus_ooo_commit_trace_packet_t commit_packet;
    bbus_ooo_commit_event_t commit_event;
    logic unsupported_seen;
    logic [31:0] unsupported_pc, unsupported_instr;
    logic idle;
    logic [31:0] halt_pc, halt_instr;
    logic [3:0] halt_reason;
    logic [31:0] arch_gpr, arch_pc;
    logic control_pending, memory_pending, frontend_busy;
    logic commit_fire, commit2_fire, trace_buffer_valid;
    logic [7:0] perf_mixed_source;
    logic [63:0] perf_structural_oracle;
    logic [63:0] perf_structural_meta;
    logic [8:0] perf_trace_width_oracle;

    ooo_pipeline_npc_core_top #(
        .RESET_VECTOR(32'h8000_0000),
        .EXTERNAL_MEMORY(1'b1),
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
        .PAIR_RAW_TO_FINAL_BYPASS_ENABLE(PAIR_RAW_TO_FINAL_BYPASS_ENABLE),
        .DECODE_DISPATCH_FALLTHROUGH_ENABLE(
            DECODE_DISPATCH_FALLTHROUGH_ENABLE),
        .FETCH_DECODE_FALLTHROUGH_ENABLE(
            FETCH_DECODE_FALLTHROUGH_ENABLE),
        .FETCH_RESPONSE_CREDIT_TURNOVER_ENABLE(
            FETCH_RESPONSE_CREDIT_TURNOVER_ENABLE),
        .IFETCH_SAME_EDGE_RESPONSE_CAPTURE_ENABLE(
            IFETCH_SAME_EDGE_RESPONSE_CAPTURE_ENABLE),
        .TARGET_LINE_HIT_ENABLE(TARGET_LINE_HIT_ENABLE),
        .TARGET_LINE_ENTRY_COUNT(TARGET_LINE_ENTRY_COUNT),
        .TARGET_LINE_WAY_COUNT(TARGET_LINE_WAY_COUNT),
        .CONDITIONAL_PRED_ENTRIES(CONDITIONAL_PRED_ENTRIES),
        .CORRELATED_PREDICTOR_ENABLE(CORRELATED_PREDICTOR_ENABLE),
        .SAME_CYCLE_RAS_UPDATE_FORWARDING_ENABLE(
            SAME_CYCLE_RAS_UPDATE_FORWARDING_ENABLE),
        .SEQUENTIAL_LINE_HIT_ENABLE(SEQUENTIAL_LINE_HIT_ENABLE),
        .BRANCH_WINDOW_LINE_DELIVERY_ENABLE(
            BRANCH_WINDOW_LINE_DELIVERY_ENABLE),
        .SPECULATIVE_STORE_DISPATCH_ENABLE(
            SPECULATIVE_STORE_DISPATCH_ENABLE),
        .ORDERED_TARGET_PREFETCH_ORACLE_ENABLE(
            ORDERED_TARGET_PREFETCH_ORACLE_ENABLE),
        .DEMAND_FETCH_LATENCY_ORACLE_ENABLE(
            DEMAND_FETCH_LATENCY_ORACLE_ENABLE),
        .FETCH_RESPONSE_SERVICE_ORACLE_ENABLE(
            FETCH_RESPONSE_SERVICE_ORACLE_ENABLE),
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
        .SAME_CYCLE_DISPATCH_ISSUE_ENABLE(
            SAME_CYCLE_DISPATCH_ISSUE_ENABLE),
        .SAME_CYCLE_BRANCH_DISPATCH_ISSUE_ENABLE(
            SAME_CYCLE_BRANCH_DISPATCH_ISSUE_ENABLE),
        .SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE(
            SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE),
        .LSU_REQUEST_FALLTHROUGH_ENABLE(
            LSU_REQUEST_FALLTHROUGH_ENABLE),
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
        .RAS_SELF_FORWARD_EXCLUSION_ENABLE(
            RAS_SELF_FORWARD_EXCLUSION_ENABLE),
        .CACHED_CROSS_LINE_PAIR_ENABLE(CACHED_CROSS_LINE_PAIR_ENABLE),
        .CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE(
            CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE),
        .DUAL_TRACE_SINK_ENABLE(DUAL_TRACE_SINK_ENABLE),
        .DATA_LINE_HIT_ENABLE(DATA_LINE_HIT_ENABLE),
        .DATA_LINE_SAME_WORD_MISS_COALESCING_ENABLE(
            DATA_LINE_SAME_WORD_MISS_COALESCING_ENABLE),
        .DATA_LINE_STORE_RESPONSE_UPDATE_ENABLE(
            DATA_LINE_STORE_RESPONSE_UPDATE_ENABLE),
        .DATA_LINE_COUNT(DATA_LINE_COUNT),
        .DATA_LINE_WAY_COUNT(DATA_LINE_WAY_COUNT)
    ) u_core (
        .clk(clk), .reset(reset), .commit_ready_i(1'b1),
        .debug_arch_idx_i('0),
        .ext_if_req_valid_o(if_req_valid_o),
        .ext_if_req_ready_i(if_req_ready_i),
        .ext_if_req_addr_o(if_req_addr_o), .ext_if_req_pc_o(if_req_pc_o),
        .ext_if_rsp_valid_i(if_rsp_valid_i),
        .ext_if_rsp_ready_o(if_rsp_ready_o),
        .ext_if_rsp_addr_i(if_rsp_addr_i),
        .ext_if_rsp_valid_mask_i(if_rsp_valid_mask_i),
        .ext_if_rsp_data_i(if_rsp_data_i), .ext_if_rsp_eof_i(if_rsp_eof_i),
        .ext_if_rsp_error_i(if_rsp_error_i),
        .ext_fetch_pte_req_valid_o(fetch_pte_req_valid_o),
        .ext_fetch_pte_req_ready_i(fetch_pte_req_ready_i),
        .ext_fetch_pte_req_addr_o(fetch_pte_req_addr_o),
        .ext_fetch_pte_rsp_valid_i(fetch_pte_rsp_valid_i),
        .ext_fetch_pte_rsp_ready_o(fetch_pte_rsp_ready_o),
        .ext_fetch_pte_rsp_data_i(fetch_pte_rsp_data_i),
        .ext_fetch_pte_rsp_error_i(fetch_pte_rsp_error_i),
        .ext_mem_req_valid_o(mem_req_valid_o),
        .ext_mem_req_ready_i(mem_req_ready_i),
        .ext_mem_req_write_o(mem_req_write_o),
        .ext_mem_req_addr_o(mem_req_addr_o),
        .ext_mem_req_wdata_o(mem_req_wdata_o),
        .ext_mem_req_wstrb_o(mem_req_wstrb_o),
        .ext_mem_req_len_o(mem_req_len_o),
        .ext_mem_req_token_o(mem_req_token_o),
        .ext_mem_rsp_valid_i(mem_rsp_valid_i),
        .ext_mem_rsp_ready_o(mem_rsp_ready_o),
        .ext_mem_rsp_rdata_i(mem_rsp_rdata_i),
        .ext_mem_rsp_error_i(mem_rsp_error_i),
        .ext_mem_rsp_token_i(mem_rsp_token_i),
        .commit_valid_o(commit_valid_o), .commit_packet_o(commit_packet),
        .commit_event_o(commit_event), .unsupported_seen_o(unsupported_seen),
        .unsupported_pc_o(unsupported_pc),
        .unsupported_instr_o(unsupported_instr), .idle_o(idle),
        .halt_valid_o(halt_valid_o), .halt_pc_o(halt_pc),
        .halt_instr_o(halt_instr), .halt_reason_o(halt_reason),
        .debug_arch_gpr_o(arch_gpr), .debug_arch_pc_o(arch_pc),
        .debug_rob_count_o(rob_count_o), .debug_iq_count_o(iq_count_o),
        .debug_control_pending_o(control_pending),
        .debug_memory_pending_o(memory_pending),
        .debug_frontend_busy_o(frontend_busy),
        .debug_commit_fire_o(commit_fire), .debug_commit2_fire_o(commit2_fire),
        .debug_trace_buffer_valid_o(trace_buffer_valid),
        .debug_conservation_error_o(conservation_error_o),
        .perf_stage_widths_o(), .perf_lost_reasons_o(), .perf_occupancy_o(),
        .perf_events_o(), .perf_mixed_source_o(perf_mixed_source),
        .perf_structural_oracle_o(perf_structural_oracle),
        .perf_structural_meta_o(perf_structural_meta),
        .perf_accounting_raw_o(), .perf_branch_pair_o(),
        .perf_selective_transaction_fire_o(),
        .perf_operand_stage_o(),
        .perf_trace_width_oracle_o(perf_trace_width_oracle),
        .perf_lifecycle_o(),
        .perf_lsu_causality_o(),
        .perf_composite_load_turnover_o(),
        .perf_store_admission_o(),
        .perf_branch_resolution_o(), .perf_target_line_o(),
        .perf_frontend_residual_o(), .perf_frontend_no_candidate_o(),
        .perf_branch_window_supply_o(),
        .perf_branch_window_post_block_o(),
        .perf_checkpoint_state_o(),
        .perf_reservation_o(),
        .perf_data_line_o(), .perf_data_line_causality_o(),
        .perf_data_line_store_origin_o(),
        .perf_store_transaction_o(),
        .perf_predictor_o(),
        .perf_predictor_detail_o()
    );

    assign commit_pc_o = commit_packet.pc;
    assign commit_instr_o = commit_packet.instr;
    assign commit_nextpc_o = commit_packet.commit_nextpc;

    /* verilator lint_off UNUSED */
    wire unused = (^commit_event) ^ unsupported_seen ^ (^unsupported_pc) ^
        (^unsupported_instr) ^ idle ^ (^halt_pc) ^ (^halt_instr) ^
        (^halt_reason) ^ (^arch_gpr) ^ (^arch_pc) ^ control_pending ^
        memory_pending ^ frontend_busy ^ commit_fire ^ commit2_fire ^
        trace_buffer_valid ^ (^perf_mixed_source) ^
        (^perf_structural_oracle) ^ (^perf_structural_meta) ^
        (^perf_trace_width_oracle);
    /* verilator lint_on UNUSED */
endmodule
