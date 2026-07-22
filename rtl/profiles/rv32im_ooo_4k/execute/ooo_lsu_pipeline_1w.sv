`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// One-word LSU with a two-entry load ingress queue.
//
// D1 deliberately keeps the external memory boundary one-outstanding.  The
// ingress queue decouples issue from a waiting request, while the tagged queue
// token prevents a late response from updating a slot which has been killed or
// reused.  Stores continue to be owned by the precise commit-side state
// machine and have priority over new load requests.
module ooo_lsu_pipeline_1w #(
    parameter bit PRECISE_STORE_BUFFER_ENABLE = 1'b0,
    parameter bit STORE_LOAD_FORWARDING_ENABLE = 1'b0,
    parameter bit LOAD_RESPONSE_COMPLETION_BYPASS_ENABLE = 1'b0,
    parameter bit LSU_REQUEST_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE = 1'b0,
    parameter bit POSTED_STORE_RESPONSE_PIPELINE_ENABLE = 1'b0,
    parameter bit DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE = 1'b0,
    parameter logic [31:0] PMEM_BASE = 32'h8000_0000,
    parameter logic [31:0] PMEM_BYTES = 32'h0800_0000
) (
    input  logic clk,
    input  logic reset,
    input  logic flush_i,
    input  logic selective_kill_valid_i,
    input  logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_i,

    input  logic issue_valid_i,
    input  bbus_ooo_alu_iq_uop_t issue_uop_i,
    input  logic [31:0] base_data_i,
    input  logic [31:0] store_data_i,
    output logic issue_ready_o,
    output logic issue_accept_o,

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
    input  logic mem_rsp_page_fault_i,
    input  bbus_ooo_mem_token_t mem_rsp_token_i,

    output logic load_completion_valid_o,
    input  logic load_completion_ready_i,
    output bbus_ooo_writeback_t load_completion_wb_o,

    output logic exception_completion_valid_o,
    input  logic exception_completion_ready_i,
    output bbus_ooo_writeback_t exception_completion_wb_o,

    input  logic commit_store_valid_i,
    output logic commit_store_ready_o,
    input  bbus_ooo_rob_tag_t commit_store_rob_tag_i,
    input  logic [31:0] commit_store_addr_i,
    input  logic [31:0] commit_store_wdata_i,
    input  logic [3:0] commit_store_wstrb_i,
    input  logic [2:0] commit_store_len_i,
    output logic commit_store_done_valid_o,
    input  logic commit_store_done_ready_i,
    output bbus_ooo_rob_tag_t commit_store_done_rob_tag_o,
    output logic commit_store_fault_valid_o,
    input  logic commit_store_fault_ready_i,
    output bbus_ooo_rob_tag_t commit_store_fault_rob_tag_o,
    output logic [31:0] commit_store_fault_tval_o,

    output logic occupied_o,
    output logic load_outstanding_o,
    output logic load_occupied_o,
    output logic drop_wait_o,
    output logic commit_store_outstanding_o,
    output logic [2:0] store_buffer_count_o,
    output logic store_buffer_enq_fire_o,
    output logic store_buffer_ack_fire_o,
    output logic store_buffer_full_o,
    output logic store_buffer_req_fire_o,
    output logic store_buffer_rsp_fire_o,
    output logic store_buffer_response_owner_valid_o,
    output logic store_buffer_request_release_fire_o,
    output logic store_buffer_busy_o,
    output logic store_load_forward_fire_o,
    output logic store_load_disjoint_fire_o,
    output logic store_load_blocked_o,
    output logic issue_serializing_o,
    output logic illegal_issue_o,
    output logic flush_drop_o,
    output logic selective_kill_drop_o,
    output logic conservation_error_o,
    output logic [15:0] debug_load_phase_o,
    output logic debug_pre_arbiter_load_offer_valid_o,
    output logic [1:0] debug_pre_arbiter_load_offer_source_o,
    output logic [31:0] debug_pre_arbiter_load_offer_addr_o,
    output logic [2:0] debug_pre_arbiter_load_offer_len_o,
    output bbus_ooo_mem_token_t debug_pre_arbiter_load_offer_token_o,
    output logic debug_pre_arbiter_load_response_ready_o,
    output logic debug_load_response_match_o,
    output logic debug_load_response_live_o,
    output logic [2:0] debug_store_block_reason_o,
    output logic [2:0] debug_store_service_phase_o,
    output logic [29:0] debug_store_admission_o
);
    typedef enum logic [2:0] {
        LSU_PIPE_IDLE,
        LSU_PIPE_STORE_REQ,
        LSU_PIPE_STORE_WAIT,
        LSU_PIPE_STORE_DONE,
        LSU_PIPE_STORE_FAULT
    } lsu_pipe_state_e;

    localparam logic [2:0] STORE_BLOCK_READY_OR_ACCEPT = 3'd0;
    localparam logic [2:0] STORE_BLOCK_RECOVERY = 3'd1;
    localparam logic [2:0] STORE_BLOCK_LEGACY_OR_STATE = 3'd2;
    localparam logic [2:0] STORE_BLOCK_DISJOINT_LOADS = 3'd3;
    localparam logic [2:0] STORE_BLOCK_OVERLAPPING_LOADS = 3'd4;
    localparam logic [2:0] STORE_BLOCK_BUFFER_UNAVAILABLE = 3'd5;
    localparam logic [2:0] STORE_BLOCK_ACK_WAIT = 3'd6;
    localparam logic [2:0] STORE_BLOCK_OTHER_LOADS = 3'd7;

    localparam logic [2:0] STORE_SERVICE_NONE = 3'd0;
    localparam logic [2:0] STORE_SERVICE_ADMISSION_WAIT = 3'd1;
    localparam logic [2:0] STORE_SERVICE_REQUEST_NOT_ACCEPTED = 3'd2;
    localparam logic [2:0] STORE_SERVICE_PHYSICAL_RESPONSE_WAIT = 3'd3;
    localparam logic [2:0] STORE_SERVICE_RESPONSE_ACCEPTED = 3'd4;
    localparam logic [2:0] STORE_SERVICE_COMMIT_ACK_WAIT = 3'd5;
    localparam logic [2:0] STORE_SERVICE_RECOVERY = 3'd6;
    localparam logic [2:0] STORE_SERVICE_OTHER = 3'd7;

    lsu_pipe_state_e state_q;
    bbus_ooo_rob_tag_t commit_store_rob_tag_q;
    logic [31:0] req_addr_q;
    logic [31:0] req_wdata_q;
    logic [3:0] req_wstrb_q;
    logic [2:0] req_len_q;
    logic [31:0] store_generation_q;

    logic [31:0] issue_addr_c;
    logic [2:0] issue_len_c;
    logic issue_load_c;
    logic issue_store_c;
    logic issue_legal_c;
    logic issue_misaligned_c;
    bbus_ooo_writeback_t issue_completion_c;

    logic [1:0] lq_alloc_valid_c;
    logic [1:0] lq_alloc_ready_c;
    logic [1:0] lq_alloc_fire_c;
    logic [1:0] lq_req_valid_c;
    logic [1:0] lq_req_ready_c;
    logic [1:0] lq_req_fire_c;
    logic [1:0] lq_req_candidate_c;
    logic lq_rsp_ready_c;
    logic lq_completion_valid_c;
    logic lq_completion_ready_c;
    bbus_ooo_writeback_t lq_completion_wb_c;
    logic [1:0] lq_valid_mask_c;
    logic [1:0] lq_issued_mask_c;
    logic [1:0] lq_done_mask_c;
    logic lq_unknown_drop_c, lq_stale_drop_c, lq_duplicate_drop_c;
    logic lq_conservation_error_c;
    logic [31:0] lq_recovery_epoch_unused;
    logic lq_req_sel_c;
    logic lq_req_sel_valid_c;

    logic [1:0] physical_valid_q;
    logic [1:0] physical_drop_q;
    logic [31:0] physical_gen_q [1:0];
    logic [31:0] physical_epoch_q [1:0];
    logic [1:0] physical_killed_c;
    logic [1:0] store_lq_overlap_c;
    logic [1:0] store_lq_shape_known_c;
    logic store_has_lq_c, store_any_lq_overlap_c;
    logic store_all_lq_shapes_known_c, store_physical_owner_known_c;
    logic store_disjoint_load_candidate_c;
    logic [32:0] commit_store_limit_c;
    logic [32:0] lq_limit_c [1:0];
    logic response_slot_c;
    logic response_owner_valid_c;
    logic load_rsp_fire_c;
    logic load_rsp_consume_c;
    logic store_req_fire_c;
    logic store_rsp_fire_c;
    logic store_rsp_consume_c;
    logic legacy_store_done_fire_c;
    logic store_fault_fire_c;
    logic load_completion_fire_c;
    logic exception_completion_fire_c;
    logic [31:0] lq_rsp_data_c;
    logic load_rsp_token_match_c;
    logic store_rsp_token_match_c;

    logic store_buffer_eligible_c, store_buffer_path_c;
    logic store_buffer_enq_valid_c, store_buffer_enq_ready_c;
    logic store_buffer_ack_valid_c, store_buffer_ack_ready_c;
    bbus_ooo_rob_tag_t store_buffer_ack_tag_c;
    logic store_buffer_mem_req_valid_c, store_buffer_mem_req_ready_c;
    logic [31:0] store_buffer_mem_req_addr_c;
    logic [31:0] store_buffer_mem_req_wdata_c;
    logic [3:0] store_buffer_mem_req_wstrb_c;
    logic [2:0] store_buffer_mem_req_len_c;
    bbus_ooo_mem_token_t store_buffer_mem_req_token_c;
    logic store_buffer_mem_rsp_valid_c, store_buffer_mem_rsp_ready_c;
    logic store_buffer_busy_c, store_buffer_full_c;
    logic [2:0] store_buffer_count_c;
    logic store_buffer_req_fire_c, store_buffer_rsp_fire_c;
    logic store_buffer_response_owner_valid_c;
    logic [1:0] store_buffer_response_owner_count_c;
    logic store_buffer_request_release_fire_c;
    logic store_buffer_unknown_rsp_c, store_buffer_error_c;
    logic select_store_buffer_req_c;
    logic select_load_req_c;
    logic unexpected_store_rsp_fire_c, unexpected_store_rsp_q;
    logic [32:0] store_buffer_last_byte_c, store_buffer_pmem_limit_c;
    logic [32:0] issue_last_byte_c;
    logic issue_pmem_c, issue_store_buffer_block_c;
    logic issue_forward_valid_c, issue_disjoint_valid_c;
    logic store_buffer_query_overlap_c, store_buffer_query_full_c;
    logic store_buffer_query_uncertain_c;
    logic [31:0] store_buffer_query_data_c;
    logic [1:0] store_load_budget_q;

    function automatic logic [2:0] mem_len(input bbus_ooo_mem_op_e mem_op);
        begin
            unique case (mem_op)
                BBUS_OOO_MEM_H_S, BBUS_OOO_MEM_H_U: mem_len = 3'd2;
                BBUS_OOO_MEM_W:                     mem_len = 3'd4;
                default:                            mem_len = 3'd1;
            endcase
        end
    endfunction

    function automatic logic mem_misaligned(
        input bbus_ooo_mem_op_e mem_op,
        input logic [31:0] addr
    );
        begin
            unique case (mem_op)
                BBUS_OOO_MEM_H_S, BBUS_OOO_MEM_H_U: mem_misaligned = addr[0];
                BBUS_OOO_MEM_W:                     mem_misaligned = (addr[1:0] != 2'b00);
                default:                            mem_misaligned = 1'b0;
            endcase
        end
    endfunction

    function automatic logic [31:0] extend_load(
        input bbus_ooo_mem_op_e mem_op,
        input logic [31:0] shifted_data
    );
        begin
            unique case (mem_op)
                BBUS_OOO_MEM_B_S: extend_load = {{24{shifted_data[7]}}, shifted_data[7:0]};
                BBUS_OOO_MEM_H_S: extend_load = {{16{shifted_data[15]}}, shifted_data[15:0]};
                BBUS_OOO_MEM_B_U: extend_load = {24'b0, shifted_data[7:0]};
                BBUS_OOO_MEM_H_U: extend_load = {16'b0, shifted_data[15:0]};
                default:          extend_load = shifted_data;
            endcase
        end
    endfunction

    assign store_buffer_pmem_limit_c =
        {1'b0, PMEM_BASE} + {1'b0, PMEM_BYTES};
    assign store_buffer_last_byte_c = {1'b0, commit_store_addr_i} +
        {30'b0, commit_store_len_i} - 33'd1;
    assign store_buffer_eligible_c = PRECISE_STORE_BUFFER_ENABLE &&
        ((commit_store_len_i == 3'd1) ||
         ((commit_store_len_i == 3'd2) && !commit_store_addr_i[0]) ||
         ((commit_store_len_i == 3'd4) &&
          (commit_store_addr_i[1:0] == 2'b00))) &&
        ({1'b0, commit_store_addr_i} >= {1'b0, PMEM_BASE}) &&
        (store_buffer_last_byte_c < store_buffer_pmem_limit_c);
    assign store_buffer_path_c = commit_store_valid_i &&
        store_buffer_eligible_c;

    assign issue_addr_c = base_data_i + issue_uop_i.imm;
    assign issue_len_c = mem_len(issue_uop_i.mem_op);
    assign issue_last_byte_c = {1'b0, issue_addr_c} +
        {30'b0, issue_len_c} - 33'd1;
    assign issue_pmem_c = ({1'b0, issue_addr_c} >= {1'b0, PMEM_BASE}) &&
        (issue_last_byte_c < store_buffer_pmem_limit_c);
    assign issue_load_c = issue_uop_i.valid &&
        (issue_uop_i.fu_type == BBUS_OOO_FU_LSU) && issue_uop_i.is_load &&
        !issue_uop_i.is_store && !issue_uop_i.is_csr && !issue_uop_i.is_system;
    assign issue_store_c = issue_uop_i.valid &&
        ((issue_uop_i.fu_type == BBUS_OOO_FU_LSU) || issue_uop_i.is_store) &&
        issue_uop_i.is_store;
    assign issue_legal_c = issue_load_c;
    assign issue_misaligned_c = mem_misaligned(issue_uop_i.mem_op, issue_addr_c);
    assign issue_forward_valid_c = STORE_LOAD_FORWARDING_ENABLE &&
        store_buffer_busy_c && issue_pmem_c && !issue_misaligned_c &&
        store_buffer_query_full_c && !store_buffer_query_uncertain_c;
    assign issue_disjoint_valid_c = STORE_LOAD_FORWARDING_ENABLE &&
        store_buffer_busy_c && issue_pmem_c && !issue_misaligned_c &&
        !store_buffer_query_overlap_c && !store_buffer_query_uncertain_c;
    assign issue_store_buffer_block_c = store_buffer_busy_c &&
        (!STORE_LOAD_FORWARDING_ENABLE ||
         (!issue_misaligned_c &&
          (!issue_pmem_c || store_buffer_query_uncertain_c ||
           (store_buffer_query_overlap_c && !store_buffer_query_full_c))));

    always_comb begin
        issue_completion_c = '0;
        issue_completion_c.valid = issue_uop_i.valid;
        issue_completion_c.rob_tag = issue_uop_i.rob_tag;
        issue_completion_c.phys_rd = issue_uop_i.phys_rd_new;
        issue_completion_c.rf_wen = issue_uop_i.rf_wen;
        issue_completion_c.done = 1'b1;
        issue_completion_c.is_load = 1'b1;
        issue_completion_c.mem_op = issue_uop_i.mem_op;
        issue_completion_c.mem_addr = issue_addr_c;
        issue_completion_c.mem_len = issue_len_c;
        if (issue_misaligned_c) begin
            issue_completion_c.rf_wen = 1'b0;
            issue_completion_c.exception.valid = 1'b1;
            issue_completion_c.exception.cause = 32'd4;
            issue_completion_c.exception.tval = issue_addr_c;
        end
    end

    assign lq_alloc_valid_c = {1'b0, issue_valid_i && issue_load_c &&
        (state_q == LSU_PIPE_IDLE) && !commit_store_valid_i &&
        !issue_store_buffer_block_c &&
        !flush_i && !selective_kill_valid_i};
    assign issue_ready_o = !flush_i && !selective_kill_valid_i &&
        (state_q == LSU_PIPE_IDLE) && !commit_store_valid_i &&
        !issue_store_buffer_block_c &&
        lq_alloc_ready_c[0];
    assign issue_accept_o = issue_valid_i && issue_legal_c && issue_ready_o &&
        lq_alloc_fire_c[0];
    assign issue_serializing_o = issue_valid_i && issue_store_c;
    assign illegal_issue_o = issue_valid_i && !issue_legal_c && !issue_store_c;

    // Store and AMO traffic remain exclusive in D2.  A precise committed store
    // is accepted only after queued and physically accepted loads have drained.
    assign commit_store_ready_o = !flush_i && !selective_kill_valid_i &&
        (state_q == LSU_PIPE_IDLE) && (physical_valid_q == 2'b00) &&
        (lq_valid_mask_c == 2'b00) &&
        (store_buffer_path_c ? store_buffer_enq_ready_c :
         !store_buffer_busy_c);
    assign store_buffer_enq_valid_c = commit_store_valid_i &&
        commit_store_ready_o && store_buffer_eligible_c;

    always_comb begin
        lq_req_sel_c = 1'b0;
        lq_req_sel_valid_c = 1'b0;
        // req_valid already includes the guarded empty-LQ allocation offer.
        // Keep the physical scoreboard exclusion here so the outer arbiter
        // can select either a registered request or that allocation-cycle
        // offer through the same token/metadata path.
        lq_req_candidate_c = lq_req_valid_c & ~physical_valid_q;
        if (state_q == LSU_PIPE_IDLE && !commit_store_valid_i &&
            (!store_buffer_busy_c || STORE_LOAD_FORWARDING_ENABLE) &&
            (physical_valid_q != 2'b11) &&
            !flush_i && !selective_kill_valid_i) begin
            if (lq_req_candidate_c[0]) begin
                lq_req_sel_c = 1'b0;
                lq_req_sel_valid_c = 1'b1;
            end else if (lq_req_candidate_c[1]) begin
                lq_req_sel_c = 1'b1;
                lq_req_sel_valid_c = 1'b1;
            end
        end
    end

    assign select_load_req_c = (state_q == LSU_PIPE_IDLE) &&
        lq_req_sel_valid_c &&
        (!store_buffer_mem_req_valid_c ||
         (STORE_LOAD_FORWARDING_ENABLE && (store_load_budget_q != 2'd0)));
    assign select_store_buffer_req_c = (state_q == LSU_PIPE_IDLE) &&
        store_buffer_mem_req_valid_c && !select_load_req_c;
    always_comb begin
        lq_req_ready_c = '0;
        if (select_load_req_c && mem_req_ready_i)
            lq_req_ready_c[lq_req_sel_c] = 1'b1;
    end
    assign store_buffer_mem_req_ready_c = mem_req_ready_i &&
        select_store_buffer_req_c;
    assign mem_req_valid_o = (state_q == LSU_PIPE_STORE_REQ) ? 1'b1 :
        select_store_buffer_req_c ? store_buffer_mem_req_valid_c :
        select_load_req_c;
    assign mem_req_write_o = (state_q == LSU_PIPE_STORE_REQ) ||
        select_store_buffer_req_c;
    assign mem_req_addr_o = (state_q == LSU_PIPE_STORE_REQ) ? req_addr_q :
        select_store_buffer_req_c ? store_buffer_mem_req_addr_c :
        (lq_req_sel_c ? lq_req_addr1_c : lq_req_addr0_c);
    assign mem_req_wdata_o = (state_q == LSU_PIPE_STORE_REQ) ? req_wdata_q :
        select_store_buffer_req_c ? store_buffer_mem_req_wdata_c : 32'b0;
    assign mem_req_wstrb_o = (state_q == LSU_PIPE_STORE_REQ) ? req_wstrb_q :
        select_store_buffer_req_c ? store_buffer_mem_req_wstrb_c : 4'b0;
    assign mem_req_len_o = (state_q == LSU_PIPE_STORE_REQ) ? req_len_q :
        select_store_buffer_req_c ? store_buffer_mem_req_len_c :
        (lq_req_sel_c ? lq_req_len1_c : lq_req_len0_c);

    always_comb begin
        mem_req_token_o = '0;
        mem_req_token_o.valid = mem_req_valid_o;
        if (state_q == LSU_PIPE_STORE_REQ) begin
            mem_req_token_o.client = BBUS_OOO_MEM_CLIENT_LSU_STORE;
            mem_req_token_o.slot = {1'b0, commit_store_rob_tag_q.idx[0]};
            mem_req_token_o.generation = store_generation_q;
            mem_req_token_o.recovery_epoch = 32'b0;
        end else if (select_store_buffer_req_c) begin
            mem_req_token_o = store_buffer_mem_req_token_c;
        end else begin
            mem_req_token_o.client = BBUS_OOO_MEM_CLIENT_LSU_LOAD;
            mem_req_token_o.slot = {1'b0,
                lq_req_sel_c ? lq_req_token_slot1_c : lq_req_token_slot0_c};
            mem_req_token_o.generation = lq_req_sel_c ?
                lq_req_token_gen1_c : lq_req_token_gen0_c;
            mem_req_token_o.recovery_epoch = lq_req_sel_c ?
                lq_req_token_epoch1_c : lq_req_token_epoch0_c;
        end
    end

    // Queue request metadata is declared separately to keep the external
    // memory port free of the internal response token.
    logic [31:0] lq_req_addr0_c, lq_req_addr1_c;
    logic [2:0] lq_req_len0_c, lq_req_len1_c;
    bbus_ooo_mem_op_e lq_req_mem_op0_c, lq_req_mem_op1_c;
    logic lq_req_token_slot0_c, lq_req_token_slot1_c;
    logic [31:0] lq_req_token_gen0_c, lq_req_token_gen1_c;
    logic [31:0] lq_req_token_epoch0_c, lq_req_token_epoch1_c;
    bbus_ooo_rob_tag_t lq_req_rob_tag0_c, lq_req_rob_tag1_c;

    assign commit_store_limit_c = {1'b0, commit_store_addr_i} +
        {30'b0, commit_store_len_i};
    assign lq_limit_c[0] = {1'b0, lq_req_addr0_c} +
        {30'b0, lq_req_len0_c};
    assign lq_limit_c[1] = {1'b0, lq_req_addr1_c} +
        {30'b0, lq_req_len1_c};
    always_comb begin
        store_lq_overlap_c = '0;
        store_lq_shape_known_c = '0;
        for (int unsigned slot = 0; slot < 2; slot++) begin
            store_lq_shape_known_c[slot] =
                (slot ? lq_req_len1_c : lq_req_len0_c) == 3'd1 ||
                (slot ? lq_req_len1_c : lq_req_len0_c) == 3'd2 ||
                (slot ? lq_req_len1_c : lq_req_len0_c) == 3'd4;
            store_lq_overlap_c[slot] = lq_valid_mask_c[slot] &&
                ({1'b0, commit_store_addr_i} < lq_limit_c[slot]) &&
                ({1'b0, slot ? lq_req_addr1_c : lq_req_addr0_c} <
                 commit_store_limit_c);
        end
    end
    assign store_has_lq_c = |lq_valid_mask_c;
    assign store_any_lq_overlap_c = |store_lq_overlap_c;
    assign store_all_lq_shapes_known_c =
        &(store_lq_shape_known_c | ~lq_valid_mask_c);
    assign store_physical_owner_known_c =
        (physical_valid_q & ~lq_valid_mask_c) == 2'b00;
    assign store_disjoint_load_candidate_c = commit_store_valid_i &&
        store_buffer_eligible_c && !flush_i && !selective_kill_valid_i &&
        (state_q == LSU_PIPE_IDLE) && store_buffer_enq_ready_c &&
        store_has_lq_c && !store_any_lq_overlap_c &&
        store_all_lq_shapes_known_c && store_physical_owner_known_c;

    always_comb begin
        debug_store_block_reason_o = STORE_BLOCK_READY_OR_ACCEPT;
        if ((flush_i || selective_kill_valid_i) &&
            (commit_store_valid_i || (state_q != LSU_PIPE_IDLE))) begin
            debug_store_block_reason_o = STORE_BLOCK_RECOVERY;
        end else if (state_q != LSU_PIPE_IDLE) begin
            debug_store_block_reason_o = STORE_BLOCK_LEGACY_OR_STATE;
        end else if (commit_store_valid_i && !commit_store_ready_o) begin
            if (!store_buffer_eligible_c) begin
                debug_store_block_reason_o = STORE_BLOCK_LEGACY_OR_STATE;
            end else if (!store_buffer_enq_ready_c) begin
                debug_store_block_reason_o = STORE_BLOCK_BUFFER_UNAVAILABLE;
            end else if (store_disjoint_load_candidate_c) begin
                debug_store_block_reason_o = STORE_BLOCK_DISJOINT_LOADS;
            end else if (store_has_lq_c && store_any_lq_overlap_c &&
                         store_all_lq_shapes_known_c &&
                         store_physical_owner_known_c) begin
                debug_store_block_reason_o =
                    STORE_BLOCK_OVERLAPPING_LOADS;
            end else begin
                debug_store_block_reason_o = STORE_BLOCK_OTHER_LOADS;
            end
        end else if (store_buffer_ack_valid_c) begin
            debug_store_block_reason_o = STORE_BLOCK_ACK_WAIT;
        end
    end

    always_comb begin
        debug_store_service_phase_o = STORE_SERVICE_NONE;
        if ((flush_i || selective_kill_valid_i) &&
            (commit_store_valid_i || (state_q != LSU_PIPE_IDLE))) begin
            debug_store_service_phase_o = STORE_SERVICE_RECOVERY;
        end else begin
            unique case (state_q)
                LSU_PIPE_STORE_REQ:
                    debug_store_service_phase_o = store_req_fire_c ?
                        STORE_SERVICE_PHYSICAL_RESPONSE_WAIT :
                        STORE_SERVICE_REQUEST_NOT_ACCEPTED;
                LSU_PIPE_STORE_WAIT:
                    debug_store_service_phase_o = store_rsp_fire_c ?
                        STORE_SERVICE_RESPONSE_ACCEPTED :
                        STORE_SERVICE_PHYSICAL_RESPONSE_WAIT;
                LSU_PIPE_STORE_DONE,
                LSU_PIPE_STORE_FAULT:
                    debug_store_service_phase_o =
                        STORE_SERVICE_COMMIT_ACK_WAIT;
                LSU_PIPE_IDLE: begin
                    if (commit_store_valid_i && !commit_store_ready_o)
                        debug_store_service_phase_o =
                            STORE_SERVICE_ADMISSION_WAIT;
                    else if (store_buffer_ack_valid_c)
                        debug_store_service_phase_o =
                            STORE_SERVICE_COMMIT_ACK_WAIT;
                end
                default:
                    debug_store_service_phase_o = STORE_SERVICE_OTHER;
            endcase
        end
    end

    assign response_slot_c = mem_rsp_token_i.slot[0];
    assign response_owner_valid_c = physical_valid_q[response_slot_c];
    assign load_rsp_token_match_c = mem_rsp_token_i.valid &&
        (mem_rsp_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_LOAD) &&
        (mem_rsp_token_i.slot[1] == 1'b0) && response_owner_valid_c &&
        (mem_rsp_token_i.generation == physical_gen_q[response_slot_c]) &&
        (mem_rsp_token_i.recovery_epoch == physical_epoch_q[response_slot_c]);
    assign debug_load_response_match_o = load_rsp_token_match_c;
    assign debug_load_response_live_o = load_rsp_token_match_c &&
        lq_valid_mask_c[response_slot_c] &&
        !physical_drop_q[response_slot_c] &&
        !physical_killed_c[response_slot_c] &&
        !flush_i && !selective_kill_valid_i;
    assign store_rsp_token_match_c = mem_rsp_token_i.valid &&
        (mem_rsp_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_STORE) &&
        (mem_rsp_token_i.generation == store_generation_q);
    assign load_rsp_consume_c = mem_rsp_valid_i && mem_rsp_ready_o &&
        (mem_rsp_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_LOAD);
    assign load_rsp_fire_c = load_rsp_consume_c && load_rsp_token_match_c;
    assign lq_rsp_data_c = extend_load(
        response_slot_c ? lq_req_mem_op1_c : lq_req_mem_op0_c,
        mem_rsp_rdata_i >> {
            response_slot_c ? lq_req_addr1_c[1:0] : lq_req_addr0_c[1:0],
            3'b000});
    assign store_buffer_mem_rsp_valid_c = (state_q == LSU_PIPE_IDLE) &&
        store_buffer_busy_c && mem_rsp_valid_i && mem_rsp_token_i.valid &&
        (mem_rsp_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_STORE);
    assign unexpected_store_rsp_fire_c = (state_q == LSU_PIPE_IDLE) &&
        !store_buffer_busy_c && mem_rsp_valid_i && mem_rsp_token_i.valid &&
        (mem_rsp_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_STORE);
    assign mem_rsp_ready_o = (state_q == LSU_PIPE_STORE_WAIT) ? 1'b1 :
        store_buffer_mem_rsp_valid_c ? store_buffer_mem_rsp_ready_c :
        unexpected_store_rsp_fire_c ? 1'b1 :
        ((state_q == LSU_PIPE_IDLE) && mem_rsp_token_i.valid &&
         (mem_rsp_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_LOAD) &&
         (!selective_kill_valid_i || flush_i || !load_rsp_token_match_c ||
          physical_drop_q[response_slot_c] || physical_killed_c[response_slot_c]));

    assign load_completion_valid_o = lq_completion_valid_c &&
        !lq_completion_wb_c.exception.valid;
    assign exception_completion_valid_o = lq_completion_valid_c &&
        lq_completion_wb_c.exception.valid;
    assign load_completion_wb_o = lq_completion_wb_c;
    assign exception_completion_wb_o = lq_completion_wb_c;
    // The external response ready is qualified by the real response token.
    // Export the token-independent sink capacity for the P77 counterfactual.
    assign debug_pre_arbiter_load_response_ready_o = !reset &&
        (state_q == LSU_PIPE_IDLE) && !flush_i && !selective_kill_valid_i;
    assign load_completion_fire_c = load_completion_valid_o && load_completion_ready_i;
    assign exception_completion_fire_c = exception_completion_valid_o && exception_completion_ready_i;
    assign lq_completion_ready_c = lq_completion_wb_c.exception.valid ?
        exception_completion_ready_i : load_completion_ready_i;

    assign commit_store_done_valid_o = store_buffer_ack_valid_c ||
        (state_q == LSU_PIPE_STORE_DONE);
    assign commit_store_done_rob_tag_o = store_buffer_ack_valid_c ?
        store_buffer_ack_tag_c : commit_store_rob_tag_q;
    assign store_buffer_ack_ready_c = store_buffer_ack_valid_c &&
        commit_store_done_ready_i;
    assign legacy_store_done_fire_c = !store_buffer_ack_valid_c &&
        (state_q == LSU_PIPE_STORE_DONE) && commit_store_done_ready_i;
    assign commit_store_fault_valid_o = (state_q == LSU_PIPE_STORE_FAULT);
    assign commit_store_fault_rob_tag_o = commit_store_rob_tag_q;
    assign commit_store_fault_tval_o = req_addr_q;
    assign store_fault_fire_c = commit_store_fault_valid_o && commit_store_fault_ready_i;
    assign store_req_fire_c = (state_q == LSU_PIPE_STORE_REQ) && mem_req_ready_i;
    assign store_rsp_consume_c = (state_q == LSU_PIPE_STORE_WAIT) &&
        mem_rsp_valid_i && mem_rsp_ready_o;
    assign store_rsp_fire_c = store_rsp_consume_c && store_rsp_token_match_c;

    assign occupied_o = (state_q != LSU_PIPE_IDLE) ||
        store_buffer_busy_c || (|physical_valid_q) || (|lq_valid_mask_c);
    // Preserve event19's historical service-occupancy meaning.  Queued but
    // unissued ingress entries are LQ occupancy, not memory outstanding.
    assign load_outstanding_o = (|physical_valid_q) || (|lq_issued_mask_c);
    assign load_occupied_o = (|physical_valid_q) || (|lq_valid_mask_c);
    assign physical_killed_c[0] = physical_valid_q[0] && lq_valid_mask_c[0] &&
        selective_kill_valid_i &&
        selective_killed_rob_mask_i[lq_req_rob_tag0_c.idx];
    assign physical_killed_c[1] = physical_valid_q[1] && lq_valid_mask_c[1] &&
        selective_kill_valid_i &&
        selective_killed_rob_mask_i[lq_req_rob_tag1_c.idx];
    assign drop_wait_o = |(physical_valid_q & physical_drop_q);
    assign commit_store_outstanding_o = (state_q != LSU_PIPE_IDLE) ||
        store_buffer_busy_c;
    assign store_buffer_count_o = store_buffer_count_c;
    assign store_buffer_enq_fire_o = store_buffer_enq_valid_c &&
        store_buffer_enq_ready_c;
    assign store_buffer_ack_fire_o = store_buffer_ack_valid_c &&
        store_buffer_ack_ready_c;
    assign store_buffer_full_o = store_buffer_full_c;
    assign store_buffer_req_fire_o = store_buffer_req_fire_c;
    assign store_buffer_rsp_fire_o = store_buffer_rsp_fire_c;
    assign store_buffer_response_owner_valid_o =
        store_buffer_response_owner_valid_c;
    assign store_buffer_request_release_fire_o =
        store_buffer_request_release_fire_c;
    assign store_buffer_busy_o = store_buffer_busy_c;
    assign store_load_forward_fire_o = issue_accept_o &&
        issue_forward_valid_c;
    assign store_load_disjoint_fire_o = issue_accept_o &&
        issue_disjoint_valid_c;
    assign store_load_blocked_o = STORE_LOAD_FORWARDING_ENABLE &&
        issue_valid_i && issue_load_c && store_buffer_busy_c &&
        issue_store_buffer_block_c && !flush_i && !selective_kill_valid_i;
    always_comb begin
        // Simulation-only store-buffer service state.  This sideband does not
        // feed any request, completion, recovery, or admission decision.
        debug_store_admission_o = '0;
        debug_store_admission_o[2:0] = store_buffer_count_c;
        debug_store_admission_o[3] = store_buffer_full_c;
        debug_store_admission_o[4] = commit_store_valid_i;
        debug_store_admission_o[5] = store_buffer_eligible_c;
        debug_store_admission_o[6] = commit_store_ready_o;
        debug_store_admission_o[7] = store_buffer_enq_ready_c;
        debug_store_admission_o[8] = store_buffer_enq_fire_o;
        debug_store_admission_o[9] = store_buffer_ack_valid_c;
        debug_store_admission_o[10] = store_buffer_ack_fire_o;
        debug_store_admission_o[11] = store_buffer_mem_req_valid_c;
        debug_store_admission_o[12] = select_load_req_c;
        debug_store_admission_o[13] = select_store_buffer_req_c;
        debug_store_admission_o[14] = mem_req_ready_i;
        debug_store_admission_o[15] = store_buffer_req_fire_c;
        debug_store_admission_o[16] = store_buffer_mem_rsp_valid_c;
        debug_store_admission_o[17] = store_buffer_rsp_fire_c;
        debug_store_admission_o[19:18] = lq_valid_mask_c;
        debug_store_admission_o[21:20] = physical_valid_q;
        debug_store_admission_o[22] = |lq_req_candidate_c;
        debug_store_admission_o[23] = |lq_req_fire_c;
        debug_store_admission_o[24] = store_buffer_full_c &&
            store_buffer_rsp_fire_c && store_buffer_enq_fire_o;
        debug_store_admission_o[25] = store_buffer_full_c &&
            store_buffer_rsp_fire_c;
        debug_store_admission_o[26] = state_q == LSU_PIPE_IDLE;
        debug_store_admission_o[27] = store_buffer_busy_c;
        debug_store_admission_o[29:28] = store_load_budget_q;
    end
    assign flush_drop_o = flush_i && ((|physical_valid_q) || (|lq_valid_mask_c));
    assign selective_kill_drop_o = !flush_i && selective_kill_valid_i &&
        (((lq_valid_mask_c[0] && selective_killed_rob_mask_i[lq_req_rob_tag0_c.idx]) ||
          (lq_valid_mask_c[1] && selective_killed_rob_mask_i[lq_req_rob_tag1_c.idx])));
    assign conservation_error_o = lq_conservation_error_c ||
        (load_rsp_consume_c && !load_rsp_token_match_c) ||
        (store_rsp_consume_c && !store_rsp_token_match_c) ||
        store_buffer_error_c || unexpected_store_rsp_q;

    generate
        if (PRECISE_STORE_BUFFER_ENABLE) begin : g_precise_store_buffer
            ooo_precise_store_buffer_4entry #(
                .POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE(
                    POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE),
                .POSTED_STORE_RESPONSE_PIPELINE_ENABLE(
                    POSTED_STORE_RESPONSE_PIPELINE_ENABLE),
                .DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE(
                    DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE),
                .PMEM_BASE(PMEM_BASE), .PMEM_BYTES(PMEM_BYTES)
            ) store_buffer (
                .clk(clk), .reset(reset),
                .enq_valid_i(store_buffer_enq_valid_c),
                .enq_ready_o(store_buffer_enq_ready_c),
                .enq_rob_tag_i(commit_store_rob_tag_i),
                .enq_addr_i(commit_store_addr_i),
                .enq_wdata_i(commit_store_wdata_i),
                .enq_wstrb_i(commit_store_wstrb_i),
                .enq_len_i(commit_store_len_i),
                .query_valid_i(issue_load_c),
                .query_addr_i(issue_addr_c),
                .query_len_i(issue_len_c),
                .query_overlap_o(store_buffer_query_overlap_c),
                .query_full_forward_o(store_buffer_query_full_c),
                .query_uncertain_o(store_buffer_query_uncertain_c),
                .query_data_o(store_buffer_query_data_c),
                .ack_valid_o(store_buffer_ack_valid_c),
                .ack_ready_i(store_buffer_ack_ready_c),
                .ack_rob_tag_o(store_buffer_ack_tag_c),
                .mem_req_valid_o(store_buffer_mem_req_valid_c),
                .mem_req_ready_i(store_buffer_mem_req_ready_c),
                .mem_req_addr_o(store_buffer_mem_req_addr_c),
                .mem_req_wdata_o(store_buffer_mem_req_wdata_c),
                .mem_req_wstrb_o(store_buffer_mem_req_wstrb_c),
                .mem_req_len_o(store_buffer_mem_req_len_c),
                .mem_req_token_o(store_buffer_mem_req_token_c),
                .mem_rsp_valid_i(store_buffer_mem_rsp_valid_c),
                .mem_rsp_ready_o(store_buffer_mem_rsp_ready_c),
                .mem_rsp_error_i(mem_rsp_error_i),
                .mem_rsp_page_fault_i(mem_rsp_page_fault_i),
                .mem_rsp_token_i(mem_rsp_token_i),
                .busy_o(store_buffer_busy_c),
                .full_o(store_buffer_full_c),
                .count_o(store_buffer_count_c),
                .req_fire_o(store_buffer_req_fire_c),
                .rsp_fire_o(store_buffer_rsp_fire_c),
                .response_owner_valid_o(
                    store_buffer_response_owner_valid_c),
                .response_owner_count_o(
                    store_buffer_response_owner_count_c),
                .request_release_fire_o(
                    store_buffer_request_release_fire_c),
                .unknown_response_o(store_buffer_unknown_rsp_c),
                .conservation_error_o(store_buffer_error_c)
            );
        end else begin : g_no_precise_store_buffer
            assign store_buffer_enq_ready_c = 1'b0;
            assign store_buffer_ack_valid_c = 1'b0;
            assign store_buffer_ack_tag_c = '0;
            assign store_buffer_mem_req_valid_c = 1'b0;
            assign store_buffer_mem_req_addr_c = 32'b0;
            assign store_buffer_mem_req_wdata_c = 32'b0;
            assign store_buffer_mem_req_wstrb_c = 4'b0;
            assign store_buffer_mem_req_len_c = 3'b0;
            assign store_buffer_mem_req_token_c = '0;
            assign store_buffer_mem_rsp_ready_c = 1'b0;
            assign store_buffer_query_overlap_c = 1'b0;
            assign store_buffer_query_full_c = 1'b0;
            assign store_buffer_query_uncertain_c = 1'b0;
            assign store_buffer_query_data_c = 32'b0;
            assign store_buffer_busy_c = 1'b0;
            assign store_buffer_full_c = 1'b0;
            assign store_buffer_count_c = 3'b0;
            assign store_buffer_req_fire_c = 1'b0;
            assign store_buffer_rsp_fire_c = 1'b0;
            assign store_buffer_response_owner_valid_c = 1'b0;
            assign store_buffer_response_owner_count_c = 2'b0;
            assign store_buffer_request_release_fire_c = 1'b0;
            assign store_buffer_unknown_rsp_c = 1'b0;
            assign store_buffer_error_c = 1'b0;
        end
    endgenerate

    ooo_load_queue_2entry #(
        .RESPONSE_COMPLETION_BYPASS_ENABLE(
            LOAD_RESPONSE_COMPLETION_BYPASS_ENABLE),
        .REQUEST_FALLTHROUGH_ENABLE(LSU_REQUEST_FALLTHROUGH_ENABLE)
    ) load_queue (
        .clk(clk), .reset(reset), .flush_i(flush_i),
        .selective_kill_valid_i(selective_kill_valid_i),
        .selective_killed_rob_mask_i(selective_killed_rob_mask_i),
        .alloc_valid_i(lq_alloc_valid_c), .alloc_ready_o(lq_alloc_ready_c),
        .alloc_fire_o(lq_alloc_fire_c),
        .alloc0_rob_tag_i(issue_uop_i.rob_tag), .alloc1_rob_tag_i('0),
        .alloc0_phys_rd_i(issue_uop_i.phys_rd_new), .alloc1_phys_rd_i('0),
        .alloc0_rf_wen_i(issue_uop_i.rf_wen), .alloc1_rf_wen_i(1'b0),
        .alloc0_exception_i(issue_completion_c.exception), .alloc1_exception_i('0),
        .alloc0_result_valid_i(issue_forward_valid_c),
        .alloc1_result_valid_i(1'b0),
        .alloc0_result_i(extend_load(issue_uop_i.mem_op,
            store_buffer_query_data_c)),
        .alloc1_result_i(32'b0),
        .alloc0_addr_i(issue_addr_c), .alloc1_addr_i('0),
        .alloc0_len_i(issue_len_c), .alloc1_len_i('0),
        .alloc0_mem_op_i(issue_uop_i.mem_op), .alloc1_mem_op_i(BBUS_OOO_MEM_NONE),
        .req_valid_o(lq_req_valid_c), .req_ready_i(lq_req_ready_c),
        .req_fire_o(lq_req_fire_c),
        .req0_rob_tag_o(lq_req_rob_tag0_c), .req1_rob_tag_o(lq_req_rob_tag1_c),
        .req0_addr_o(lq_req_addr0_c), .req1_addr_o(lq_req_addr1_c),
        .req0_len_o(lq_req_len0_c), .req1_len_o(lq_req_len1_c),
        .req0_mem_op_o(lq_req_mem_op0_c), .req1_mem_op_o(lq_req_mem_op1_c),
        .req0_token_slot_o(lq_req_token_slot0_c), .req1_token_slot_o(lq_req_token_slot1_c),
        .req0_token_gen_o(lq_req_token_gen0_c), .req1_token_gen_o(lq_req_token_gen1_c),
        .req0_token_epoch_o(lq_req_token_epoch0_c), .req1_token_epoch_o(lq_req_token_epoch1_c),
        .rsp_valid_i(load_rsp_consume_c), .rsp_ready_o(lq_rsp_ready_c),
        .rsp_token_slot_i(mem_rsp_token_i.slot[0]),
        .rsp_token_gen_i(mem_rsp_token_i.generation),
        .rsp_token_epoch_i(mem_rsp_token_i.recovery_epoch), .rsp_rdata_i(lq_rsp_data_c),
        .rsp_error_i(mem_rsp_error_i), .rsp_page_fault_i(mem_rsp_page_fault_i),
        .completion_valid_o(lq_completion_valid_c), .completion_ready_i(lq_completion_ready_c),
        .completion_wb_o(lq_completion_wb_c), .valid_mask_o(lq_valid_mask_c),
        .issued_mask_o(lq_issued_mask_c), .done_mask_o(lq_done_mask_c),
        .recovery_epoch_o(lq_recovery_epoch_unused),
        .unknown_response_drop_o(lq_unknown_drop_c),
        .stale_response_drop_o(lq_stale_drop_c), .duplicate_response_drop_o(lq_duplicate_drop_c),
        .conservation_error_o(lq_conservation_error_c)
    );

    assign debug_load_phase_o = {
        lq_req_rob_tag1_c.gen, lq_req_rob_tag1_c.idx,
        lq_done_mask_c[1], lq_issued_mask_c[1], lq_valid_mask_c[1],
        lq_req_rob_tag0_c.gen, lq_req_rob_tag0_c.idx,
        lq_done_mask_c[0], lq_issued_mask_c[0], lq_valid_mask_c[0]
    };

    // P77 observation-only offer before commit/store selection suppresses the
    // LSU load request. Slot order matches the production LQ selector.
    always_comb begin
        debug_pre_arbiter_load_offer_valid_o = |lq_req_candidate_c;
        debug_pre_arbiter_load_offer_source_o = 2'd0;
        debug_pre_arbiter_load_offer_addr_o = lq_req_addr0_c;
        debug_pre_arbiter_load_offer_len_o = lq_req_len0_c;
        debug_pre_arbiter_load_offer_token_o = '0;
        debug_pre_arbiter_load_offer_token_o.valid =
            debug_pre_arbiter_load_offer_valid_o;
        debug_pre_arbiter_load_offer_token_o.client =
            BBUS_OOO_MEM_CLIENT_LSU_LOAD;
        debug_pre_arbiter_load_offer_token_o.slot =
            {1'b0, lq_req_token_slot0_c};
        debug_pre_arbiter_load_offer_token_o.generation =
            lq_req_token_gen0_c;
        debug_pre_arbiter_load_offer_token_o.recovery_epoch =
            lq_req_token_epoch0_c;
        if (lq_req_candidate_c[0]) begin
            debug_pre_arbiter_load_offer_source_o =
                ((lq_valid_mask_c == 2'b00) && lq_alloc_fire_c[0]) ?
                2'd2 : 2'd0;
        end else if (lq_req_candidate_c[1]) begin
            debug_pre_arbiter_load_offer_source_o = 2'd1;
            debug_pre_arbiter_load_offer_addr_o = lq_req_addr1_c;
            debug_pre_arbiter_load_offer_len_o = lq_req_len1_c;
            debug_pre_arbiter_load_offer_token_o.slot =
                {1'b0, lq_req_token_slot1_c};
            debug_pre_arbiter_load_offer_token_o.generation =
                lq_req_token_gen1_c;
            debug_pre_arbiter_load_offer_token_o.recovery_epoch =
                lq_req_token_epoch1_c;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state_q <= LSU_PIPE_IDLE;
            commit_store_rob_tag_q <= '0;
            req_addr_q <= '0;
            req_wdata_q <= '0;
            req_wstrb_q <= '0;
            req_len_q <= '0;
            store_generation_q <= '0;
            physical_valid_q <= 2'b00;
            physical_drop_q <= 2'b00;
            physical_gen_q[0] <= '0;
            physical_gen_q[1] <= '0;
            physical_epoch_q[0] <= '0;
            physical_epoch_q[1] <= '0;
            unexpected_store_rsp_q <= 1'b0;
            store_load_budget_q <= 2'd0;
        end else begin
            if (unexpected_store_rsp_fire_c)
                unexpected_store_rsp_q <= 1'b1;
            if (lq_req_fire_c[0]) begin
                physical_valid_q[0] <= 1'b1;
                physical_drop_q[0] <= 1'b0;
                physical_gen_q[0] <= lq_req_token_gen0_c;
                physical_epoch_q[0] <= lq_req_token_epoch0_c;
            end
            if (lq_req_fire_c[1]) begin
                physical_valid_q[1] <= 1'b1;
                physical_drop_q[1] <= 1'b0;
                physical_gen_q[1] <= lq_req_token_gen1_c;
                physical_epoch_q[1] <= lq_req_token_epoch1_c;
            end
            if (load_rsp_fire_c) begin
                physical_valid_q[response_slot_c] <= 1'b0;
                physical_drop_q[response_slot_c] <= 1'b0;
                physical_gen_q[response_slot_c] <= '0;
                physical_epoch_q[response_slot_c] <= '0;
            end
            if (!store_buffer_busy_c)
                store_load_budget_q <= 2'd0;
            else if (store_buffer_rsp_fire_c)
                store_load_budget_q <= 2'd2;
            else if ((|lq_req_fire_c) && (store_load_budget_q != 2'd0))
                store_load_budget_q <= store_load_budget_q - 2'd1;
            if (flush_i) begin
                physical_drop_q <= physical_valid_q;
            end else if (selective_kill_valid_i) begin
                physical_drop_q <= physical_drop_q | physical_killed_c;
            end

            unique case (state_q)
                LSU_PIPE_IDLE: begin
                    if (!flush_i && !selective_kill_valid_i && commit_store_valid_i &&
                        commit_store_ready_o && !store_buffer_eligible_c) begin
                        store_generation_q <= store_generation_q + 32'd1;
                        commit_store_rob_tag_q <= commit_store_rob_tag_i;
                        req_addr_q <= commit_store_addr_i;
                        req_wdata_q <= commit_store_wdata_i;
                        req_wstrb_q <= commit_store_wstrb_i;
                        req_len_q <= commit_store_len_i;
                        state_q <= LSU_PIPE_STORE_REQ;
                    end
                end
                LSU_PIPE_STORE_REQ: begin
                    if (store_req_fire_c) state_q <= LSU_PIPE_STORE_WAIT;
                end
                LSU_PIPE_STORE_WAIT: begin
                    if (store_rsp_fire_c)
                        state_q <= ((mem_rsp_page_fault_i === 1'b1) ||
                                    (mem_rsp_error_i === 1'b1)) ?
                            LSU_PIPE_STORE_FAULT : LSU_PIPE_STORE_DONE;
                end
                LSU_PIPE_STORE_DONE: begin
                    if (legacy_store_done_fire_c) begin
                        commit_store_rob_tag_q <= '0;
                        state_q <= LSU_PIPE_IDLE;
                    end
                end
                LSU_PIPE_STORE_FAULT: begin
                    if (store_fault_fire_c) begin
                        commit_store_rob_tag_q <= '0;
                        state_q <= LSU_PIPE_IDLE;
                    end
                end
                default: state_q <= LSU_PIPE_IDLE;
            endcase
        end
    end
endmodule
