`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// Physically tagged read cache in front of the tagged data transport. Load
// misses fetch an aligned word; all non-load traffic keeps its original shape.
module ooo_data_line_cache #(
    parameter bit ENABLE = 1'b0,
    parameter bit SAME_WORD_MISS_COALESCING_ENABLE = 1'b0,
    parameter bit STORE_RESPONSE_UPDATE_ENABLE = 1'b0,
    parameter int unsigned LINE_COUNT = 64,
    parameter int unsigned WAY_COUNT = 1,
    parameter logic [31:0] PMEM_BASE = 32'h8000_0000,
    parameter logic [31:0] PMEM_BYTES = 32'h0800_0000,
    localparam int unsigned INDEX_W = $clog2(LINE_COUNT),
    localparam int unsigned WAY_W = (WAY_COUNT > 1) ? $clog2(WAY_COUNT) : 1,
    localparam int unsigned TAG_W = 32 - INDEX_W - 2
) (
    input  logic clk,
    input  logic reset,

    input  logic req_valid_i,
    output logic req_ready_o,
    input  logic req_write_i,
    input  logic [31:0] req_addr_i,
    input  logic [31:0] req_wdata_i,
    input  logic [3:0] req_wstrb_i,
    input  logic [2:0] req_len_i,
    input  bbus_ooo_mem_token_t req_token_i,

    input  logic debug_load_offer_valid_i,
    input  logic [31:0] debug_load_offer_addr_i,
    input  logic [2:0] debug_load_offer_len_i,
    input  bbus_ooo_mem_token_t debug_load_offer_token_i,
    input  logic debug_bridge_load_ready_i,
    input  logic debug_bridge_load_depth3_ready_i,

    output logic rsp_valid_o,
    input  logic rsp_ready_i,
    output logic [31:0] rsp_rdata_o,
    output logic rsp_error_o,
    output bbus_ooo_mem_token_t rsp_token_o,

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

    output logic busy_o,
    output logic hit_o,
    output logic miss_o,
    output logic fill_o,
    output logic invalidate_o,
    output logic [15:0] perf_causality_o,
    output logic [15:0] perf_coalescing_o,
    output logic [7:0] perf_invalidation_causality_o,
    output logic [63:0] perf_store_origin_o,
    output logic [31:0] debug_load_turnover_o,
    output logic conservation_error_o
);
    localparam logic [1:0] INVALID_ORIGIN_COLD = 2'd0;
    localparam logic [1:0] INVALID_ORIGIN_STORE = 2'd1;
    localparam logic [1:0] INVALID_ORIGIN_AMO = 2'd2;

    logic [WAY_COUNT-1:0][LINE_COUNT-1:0] line_valid_q;
    logic [TAG_W-1:0] line_tag_q [0:WAY_COUNT-1][0:LINE_COUNT-1];
    logic [31:0] line_data_q [0:WAY_COUNT-1][0:LINE_COUNT-1];
    logic [WAY_COUNT-1:0][LINE_COUNT-1:0][1:0]
        line_invalid_origin_q;
    logic [WAY_COUNT-1:0][LINE_COUNT-1:0][31:0]
        line_invalid_store_generation_q;
    logic [WAY_COUNT-1:0][LINE_COUNT-1:0]
        line_invalid_store_response_seen_q;
    logic [LINE_COUNT-1:0][WAY_W-1:0] replacement_way_q;

    logic [1:0] meta_valid_q;
    bbus_ooo_mem_token_t meta_token_q [0:1];
    logic meta_cacheable_load_q [0:1];
    logic meta_store_invalidation_q [0:1];
    logic [31:0] meta_word_addr_q [0:1];
    logic [31:0] meta_store_wdata_q [0:1];
    logic [3:0] meta_store_wstrb_q [0:1];
    logic [1:0] meta_waiter_valid_q;
    bbus_ooo_mem_token_t meta_waiter_token_q [0:1];

    logic hit_rsp_valid_q;
    logic [31:0] hit_rsp_data_q;
    bbus_ooo_mem_token_t hit_rsp_token_q;
    logic waiter_rsp_valid_q;
    logic [31:0] waiter_rsp_data_q;
    logic waiter_rsp_error_q;
    bbus_ooo_mem_token_t waiter_rsp_token_q;
    logic conservation_error_q;

    logic req_len_legal_c, req_shape_legal_c, req_protocol_legal_c;
    logic req_cacheable_range_c, req_cacheable_load_c;
    logic [32:0] req_last_byte_c, pmem_limit_c;
    logic [31:0] req_word_addr_c;
    logic [INDEX_W-1:0] req_index_c;
    logic [TAG_W-1:0] req_tag_c;
    logic [WAY_COUNT-1:0] req_way_hit_c, req_way_invalid_c;
    logic [WAY_W-1:0] req_hit_way_c;
    logic req_array_hit_c, req_duplicate_c;
    logic hit_slot_available_c, hit_req_fire_c, hit_rsp_fire_c;
    logic waiter_rsp_fire_c;
    logic forwarded_req_fire_c;
    logic cacheable_load_fire_c, miss_fire_c;
    logic [1:0] req_same_word_meta_c, req_coalesce_match_c;
    logic req_coalesce_match_known_c, req_coalesce_slot_c;
    logic req_coalesce_candidate_c, req_coalesce_fire_c;
    logic coalesce_waiter_full_fallback_c;
    logic miss_same_word_inflight_c, miss_any_invalid_way_c;
    logic miss_primary_same_word_c, miss_primary_invalid_way_c;
    logic miss_primary_full_set_c;
    logic miss_invalid_store_same_tag_c, miss_invalid_amo_same_tag_c;
    logic miss_invalid_store_other_tag_c, miss_invalid_cold_or_other_c;
    logic miss_invalid_store_response_seen_c;
    logic [31:0] miss_invalid_store_generation_c;
    logic invalidation_causality_error_c;

    logic [1:0] rsp_meta_match_c;
    logic rsp_meta_known_c, rsp_meta_slot_c;
    logic down_rsp_fire_c;
    logic primary_rsp_has_waiter_c, coalesce_on_primary_rsp_c;
    logic waiter_rsp_enqueue_c;
    bbus_ooo_mem_token_t waiter_rsp_enqueue_token_c;
    logic fill_c;
    logic [INDEX_W-1:0] fill_index_c;
    logic [TAG_W-1:0] fill_tag_c;
    logic [WAY_COUNT-1:0] fill_way_match_c, fill_way_invalid_c;
    logic [WAY_W-1:0] fill_way_c;
    logic fill_way_selected_c;
    logic fill_same_word_other_inflight_c;

    logic [1:0] effective_meta_valid_c;
    logic meta_slot_available_c, meta_alloc_slot_c;
    logic store_req_fire_c, store_invalidate_c, amo_invalidate_c;
    logic store_poison_same_word_inflight_c;
    logic [INDEX_W-1:0] store_index_c;
    logic [TAG_W-1:0] store_tag_c;
    logic [WAY_COUNT-1:0] store_way_match_c;
    logic [WAY_COUNT-1:0] store_way_chain_match_c;
    logic [WAY_COUNT-1:0] store_way_owner_c;
    logic response_fill_invalidated_c;
    logic store_rsp_invalidation_c;
    logic [INDEX_W-1:0] store_rsp_index_c;
    logic [TAG_W-1:0] store_rsp_tag_c;
    logic [WAY_COUNT-1:0] store_rsp_origin_match_c;
    logic store_rsp_update_opportunity_c;
    logic store_rsp_update_write_conflict_c;
    logic store_rsp_update_fire_c;
    logic store_rsp_update_disabled_c;
    logic store_rsp_update_error_c;
    logic store_rsp_update_conflict_c;
    logic store_rsp_update_invariant_error_c;
    logic line_metadata_invariant_error_c;
    logic internal_invariant_error_c, coalescing_invariant_error_c;
    logic perf_causality_error_c;

    logic debug_load_len_legal_c, debug_load_shape_legal_c;
    logic debug_load_protocol_legal_c, debug_load_cacheable_range_c;
    logic debug_load_cacheable_c, debug_load_duplicate_c;
    logic [32:0] debug_load_last_byte_c;
    logic [31:0] debug_load_word_addr_c;
    logic [INDEX_W-1:0] debug_load_index_c;
    logic [TAG_W-1:0] debug_load_tag_c;
    logic [WAY_COUNT-1:0] debug_load_way_hit_c;
    logic debug_load_array_hit_c;
    logic [1:0] debug_load_same_word_meta_c;
    logic [1:0] debug_load_coalesce_match_c;
    logic debug_load_coalesce_candidate_c;
    logic debug_load_miss_path_c;
    logic debug_load_ready_c, debug_load_depth3_ready_c;

    function automatic logic token_equal(
        input bbus_ooo_mem_token_t a,
        input bbus_ooo_mem_token_t b
    );
        token_equal = a.valid && b.valid &&
            (a.client == b.client) && (a.slot == b.slot) &&
            (a.generation == b.generation) &&
            (a.recovery_epoch == b.recovery_epoch);
    endfunction

    function automatic logic [31:0] merge_store_bytes(
        input logic [31:0] prior_data,
        input logic [31:0] store_data,
        input logic [3:0] store_strobe
    );
        logic [31:0] merged;
        merged = prior_data;
        for (int unsigned byte_idx = 0; byte_idx < 4; byte_idx++) begin
            if (store_strobe[byte_idx])
                merged[byte_idx * 8 +: 8] =
                    store_data[byte_idx * 8 +: 8];
        end
        merge_store_bytes = merged;
    endfunction

    assign pmem_limit_c = {1'b0, PMEM_BASE} + {1'b0, PMEM_BYTES};
    assign req_last_byte_c = {1'b0, req_addr_i} +
        {30'b0, req_len_i} - 33'd1;
    assign req_len_legal_c = (req_len_i == 3'd1) ||
        (req_len_i == 3'd2) || (req_len_i == 3'd4);
    assign req_shape_legal_c = req_len_legal_c &&
        ((req_len_i != 3'd2) || !req_addr_i[0]) &&
        ((req_len_i != 3'd4) || (req_addr_i[1:0] == 2'b00));
    assign req_protocol_legal_c = req_token_i.valid && req_shape_legal_c &&
        (((req_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_LOAD) &&
          !req_write_i) ||
         ((req_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_STORE) &&
          req_write_i) ||
         (req_token_i.client == BBUS_OOO_MEM_CLIENT_AMO) ||
         ((req_token_i.client == BBUS_OOO_MEM_CLIENT_PTW) &&
          !req_write_i));
    assign req_cacheable_range_c =
        ({1'b0, req_addr_i} >= {1'b0, PMEM_BASE}) &&
        (req_last_byte_c < pmem_limit_c);
    assign req_cacheable_load_c = ENABLE && req_protocol_legal_c &&
        (req_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_LOAD) &&
        req_cacheable_range_c;
    assign req_word_addr_c = {req_addr_i[31:2], 2'b00};
    assign req_index_c = req_word_addr_c[INDEX_W+1:2];
    assign req_tag_c = req_word_addr_c[31:INDEX_W+2];
    always_comb begin
        req_way_hit_c = '0;
        req_way_invalid_c = '0;
        req_hit_way_c = '0;
        for (int unsigned way = 0; way < WAY_COUNT; way++) begin
            req_way_invalid_c[way] = !line_valid_q[way][req_index_c];
            req_way_hit_c[way] = req_cacheable_load_c &&
                line_valid_q[way][req_index_c] &&
                (line_tag_q[way][req_index_c] == req_tag_c);
            if (req_way_hit_c[way])
                req_hit_way_c = WAY_W'(way);
        end
    end
    assign req_array_hit_c = |req_way_hit_c;

    assign debug_load_last_byte_c = {1'b0, debug_load_offer_addr_i} +
        {30'b0, debug_load_offer_len_i} - 33'd1;
    assign debug_load_len_legal_c =
        (debug_load_offer_len_i == 3'd1) ||
        (debug_load_offer_len_i == 3'd2) ||
        (debug_load_offer_len_i == 3'd4);
    assign debug_load_shape_legal_c = debug_load_len_legal_c &&
        ((debug_load_offer_len_i != 3'd2) ||
         !debug_load_offer_addr_i[0]) &&
        ((debug_load_offer_len_i != 3'd4) ||
         (debug_load_offer_addr_i[1:0] == 2'b00));
    assign debug_load_protocol_legal_c =
        debug_load_offer_token_i.valid && debug_load_shape_legal_c &&
        (debug_load_offer_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_LOAD);
    assign debug_load_cacheable_range_c =
        ({1'b0, debug_load_offer_addr_i} >= {1'b0, PMEM_BASE}) &&
        (debug_load_last_byte_c < pmem_limit_c);
    assign debug_load_cacheable_c = ENABLE &&
        debug_load_protocol_legal_c && debug_load_cacheable_range_c;
    assign debug_load_word_addr_c =
        {debug_load_offer_addr_i[31:2], 2'b00};
    assign debug_load_index_c =
        debug_load_word_addr_c[INDEX_W+1:2];
    assign debug_load_tag_c =
        debug_load_word_addr_c[31:INDEX_W+2];

    always_comb begin
        debug_load_way_hit_c = '0;
        debug_load_same_word_meta_c = '0;
        debug_load_coalesce_match_c = '0;
        for (int unsigned way = 0; way < WAY_COUNT; way++) begin
            debug_load_way_hit_c[way] = debug_load_cacheable_c &&
                line_valid_q[way][debug_load_index_c] &&
                (line_tag_q[way][debug_load_index_c] == debug_load_tag_c);
        end
        for (int unsigned slot = 0; slot < 2; slot++) begin
            debug_load_same_word_meta_c[slot] =
                debug_load_cacheable_c && meta_valid_q[slot] &&
                meta_cacheable_load_q[slot] &&
                (meta_word_addr_q[slot] == debug_load_word_addr_c);
            debug_load_coalesce_match_c[slot] =
                SAME_WORD_MISS_COALESCING_ENABLE &&
                debug_load_same_word_meta_c[slot] &&
                !meta_waiter_valid_q[slot];
        end
    end
    assign debug_load_array_hit_c = |debug_load_way_hit_c;
    assign debug_load_coalesce_candidate_c =
        !debug_load_array_hit_c && (|debug_load_coalesce_match_c);
    assign debug_load_miss_path_c = !debug_load_array_hit_c &&
        !debug_load_coalesce_candidate_c;
    assign debug_load_duplicate_c = debug_load_offer_token_i.valid &&
        ((meta_valid_q[0] &&
          token_equal(debug_load_offer_token_i, meta_token_q[0])) ||
         (meta_valid_q[1] &&
          token_equal(debug_load_offer_token_i, meta_token_q[1])) ||
         (meta_waiter_valid_q[0] &&
          token_equal(debug_load_offer_token_i, meta_waiter_token_q[0])) ||
         (meta_waiter_valid_q[1] &&
          token_equal(debug_load_offer_token_i, meta_waiter_token_q[1])) ||
         (hit_rsp_valid_q &&
          token_equal(debug_load_offer_token_i, hit_rsp_token_q)) ||
         (waiter_rsp_valid_q &&
          token_equal(debug_load_offer_token_i, waiter_rsp_token_q)));
    assign debug_load_ready_c = debug_load_offer_valid_i && !reset &&
        debug_load_protocol_legal_c && !debug_load_duplicate_c &&
        (debug_load_array_hit_c ? hit_slot_available_c :
         (debug_load_coalesce_candidate_c ? 1'b1 :
          (meta_slot_available_c && debug_bridge_load_ready_i)));
    assign debug_load_depth3_ready_c = debug_load_offer_valid_i && !reset &&
        debug_load_protocol_legal_c && !debug_load_duplicate_c &&
        (debug_load_array_hit_c ? hit_slot_available_c :
         (debug_load_coalesce_candidate_c ? 1'b1 :
          debug_bridge_load_depth3_ready_i));

    always_comb begin
        debug_load_turnover_o = '0;
        debug_load_turnover_o[0] = debug_load_offer_valid_i;
        debug_load_turnover_o[1] = debug_load_protocol_legal_c;
        debug_load_turnover_o[2] = debug_load_duplicate_c;
        debug_load_turnover_o[3] = debug_load_cacheable_c;
        debug_load_turnover_o[4] = debug_load_array_hit_c;
        debug_load_turnover_o[5] = hit_slot_available_c;
        debug_load_turnover_o[6] = debug_load_coalesce_candidate_c;
        debug_load_turnover_o[7] = meta_slot_available_c;
        debug_load_turnover_o[8] = debug_bridge_load_ready_i;
        debug_load_turnover_o[9] = debug_load_ready_c;
        debug_load_turnover_o[10] = debug_bridge_load_depth3_ready_i;
        debug_load_turnover_o[11] = debug_load_depth3_ready_c;
        debug_load_turnover_o[12] = down_rsp_fire_c;
        debug_load_turnover_o[14:13] = meta_valid_q;
        debug_load_turnover_o[15] = hit_rsp_valid_q;
        debug_load_turnover_o[16] = waiter_rsp_valid_q;
        debug_load_turnover_o[17] = req_valid_i && req_ready_o &&
            !req_write_i && req_token_i.valid &&
            (req_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_LOAD);
        debug_load_turnover_o[18] = req_valid_i;
        debug_load_turnover_o[19] = debug_load_miss_path_c;
        debug_load_turnover_o[20] = &meta_valid_q;
        debug_load_turnover_o[21] = |debug_load_same_word_meta_c;
        debug_load_turnover_o[22] = SAME_WORD_MISS_COALESCING_ENABLE;
        debug_load_turnover_o[23] = ENABLE;
    end

    assign waiter_rsp_fire_c = waiter_rsp_valid_q && rsp_ready_i;
    assign hit_rsp_fire_c = hit_rsp_valid_q && !waiter_rsp_valid_q &&
        rsp_ready_i;
    assign hit_slot_available_c = !hit_rsp_valid_q || hit_rsp_fire_c;

    assign rsp_meta_match_c[0] = meta_valid_q[0] &&
        token_equal(mem_rsp_token_i, meta_token_q[0]);
    assign rsp_meta_match_c[1] = meta_valid_q[1] &&
        token_equal(mem_rsp_token_i, meta_token_q[1]);
    assign rsp_meta_known_c = |rsp_meta_match_c;
    assign rsp_meta_slot_c = rsp_meta_match_c[1];

    assign rsp_valid_o = !reset && (waiter_rsp_valid_q || hit_rsp_valid_q ||
        mem_rsp_valid_i);
    assign rsp_rdata_o = waiter_rsp_valid_q ? waiter_rsp_data_q :
        (hit_rsp_valid_q ? hit_rsp_data_q : mem_rsp_rdata_i);
    assign rsp_error_o = waiter_rsp_valid_q ? waiter_rsp_error_q :
        (hit_rsp_valid_q ? 1'b0 : mem_rsp_error_i);
    assign rsp_token_o = waiter_rsp_valid_q ? waiter_rsp_token_q :
        (hit_rsp_valid_q ? hit_rsp_token_q : mem_rsp_token_i);
    assign mem_rsp_ready_o = !reset && !waiter_rsp_valid_q &&
        !hit_rsp_valid_q && rsp_ready_i;
    assign down_rsp_fire_c = mem_rsp_valid_i && mem_rsp_ready_o;

    always_comb begin
        effective_meta_valid_c = meta_valid_q;
        if (down_rsp_fire_c && rsp_meta_known_c)
            effective_meta_valid_c[rsp_meta_slot_c] = 1'b0;
    end
    assign meta_slot_available_c = !(&effective_meta_valid_c);
    assign meta_alloc_slot_c = effective_meta_valid_c[0];

    always_comb begin
        req_same_word_meta_c = '0;
        req_coalesce_match_c = '0;
        req_coalesce_match_known_c = 1'b0;
        req_coalesce_slot_c = 1'b0;
        for (int unsigned slot = 0; slot < 2; slot++) begin
            req_same_word_meta_c[slot] = req_cacheable_load_c &&
                meta_valid_q[slot] && meta_cacheable_load_q[slot] &&
                (meta_word_addr_q[slot] == req_word_addr_c);
            req_coalesce_match_c[slot] =
                SAME_WORD_MISS_COALESCING_ENABLE &&
                req_same_word_meta_c[slot] && !meta_waiter_valid_q[slot];
            if (req_coalesce_match_c[slot] &&
                !req_coalesce_match_known_c) begin
                req_coalesce_match_known_c = 1'b1;
                req_coalesce_slot_c = slot[0];
            end
        end
    end
    assign req_coalesce_candidate_c = !req_array_hit_c &&
        req_coalesce_match_known_c;

    assign req_duplicate_c = req_token_i.valid &&
        ((meta_valid_q[0] && token_equal(req_token_i, meta_token_q[0])) ||
         (meta_valid_q[1] && token_equal(req_token_i, meta_token_q[1])) ||
         (meta_waiter_valid_q[0] &&
          token_equal(req_token_i, meta_waiter_token_q[0])) ||
         (meta_waiter_valid_q[1] &&
          token_equal(req_token_i, meta_waiter_token_q[1])) ||
         (hit_rsp_valid_q && token_equal(req_token_i, hit_rsp_token_q)) ||
         (waiter_rsp_valid_q &&
          token_equal(req_token_i, waiter_rsp_token_q)));

    assign req_ready_o = !reset && req_protocol_legal_c && !req_duplicate_c &&
        (req_array_hit_c ? hit_slot_available_c :
         (req_coalesce_candidate_c ? 1'b1 :
          (meta_slot_available_c && mem_req_ready_i)));
    assign hit_req_fire_c = req_valid_i && req_ready_o && req_array_hit_c;
    assign req_coalesce_fire_c = req_valid_i && req_ready_o &&
        req_coalesce_candidate_c;

    assign mem_req_valid_o = !reset && req_valid_i && req_protocol_legal_c &&
        !req_duplicate_c && !req_array_hit_c &&
        !req_coalesce_candidate_c && meta_slot_available_c;
    assign mem_req_write_o = req_write_i;
    assign mem_req_addr_o = req_cacheable_load_c ? req_word_addr_c : req_addr_i;
    assign mem_req_wdata_o = req_cacheable_load_c ? 32'b0 : req_wdata_i;
    assign mem_req_wstrb_o = req_cacheable_load_c ? 4'b0 : req_wstrb_i;
    assign mem_req_len_o = req_cacheable_load_c ? 3'd4 : req_len_i;
    assign mem_req_token_o = req_token_i;
    assign forwarded_req_fire_c = mem_req_valid_o && mem_req_ready_i;
    assign cacheable_load_fire_c = hit_req_fire_c ||
        (forwarded_req_fire_c && req_cacheable_load_c) ||
        req_coalesce_fire_c;
    assign miss_fire_c = forwarded_req_fire_c && req_cacheable_load_c;
    assign miss_same_word_inflight_c = miss_fire_c &&
        (|req_same_word_meta_c);
    assign coalesce_waiter_full_fallback_c = miss_same_word_inflight_c &&
        SAME_WORD_MISS_COALESCING_ENABLE &&
        !req_coalesce_match_known_c;
    assign miss_any_invalid_way_c = |req_way_invalid_c;
    assign miss_primary_same_word_c = miss_same_word_inflight_c;
    assign miss_primary_invalid_way_c = miss_fire_c &&
        !miss_same_word_inflight_c && miss_any_invalid_way_c;
    assign miss_primary_full_set_c = miss_fire_c &&
        !miss_same_word_inflight_c && !miss_any_invalid_way_c;

    always_comb begin
        logic store_same_tag;
        logic amo_same_tag;
        logic store_other_tag;
        store_same_tag = 1'b0;
        amo_same_tag = 1'b0;
        store_other_tag = 1'b0;
        miss_invalid_store_response_seen_c = 1'b0;
        miss_invalid_store_generation_c = 32'b0;
        for (int unsigned way = 0; way < WAY_COUNT; way++) begin
            if (req_way_invalid_c[way] &&
                (line_invalid_origin_q[way][req_index_c] ==
                 INVALID_ORIGIN_STORE)) begin
                if (line_tag_q[way][req_index_c] == req_tag_c) begin
                    store_same_tag = 1'b1;
                    miss_invalid_store_response_seen_c =
                        line_invalid_store_response_seen_q[way][req_index_c];
                    miss_invalid_store_generation_c =
                        line_invalid_store_generation_q[way][req_index_c];
                end else begin
                    store_other_tag = 1'b1;
                end
            end
            if (req_way_invalid_c[way] &&
                (line_invalid_origin_q[way][req_index_c] ==
                 INVALID_ORIGIN_AMO) &&
                (line_tag_q[way][req_index_c] == req_tag_c))
                amo_same_tag = 1'b1;
        end
        miss_invalid_store_same_tag_c = miss_primary_invalid_way_c &&
            store_same_tag;
        miss_invalid_amo_same_tag_c = miss_primary_invalid_way_c &&
            !store_same_tag && amo_same_tag;
        miss_invalid_store_other_tag_c = miss_primary_invalid_way_c &&
            !store_same_tag && !amo_same_tag && store_other_tag;
        miss_invalid_cold_or_other_c = miss_primary_invalid_way_c &&
            !store_same_tag && !amo_same_tag && !store_other_tag;
    end

    assign primary_rsp_has_waiter_c = down_rsp_fire_c &&
        rsp_meta_known_c && meta_waiter_valid_q[rsp_meta_slot_c];
    assign coalesce_on_primary_rsp_c = req_coalesce_fire_c &&
        down_rsp_fire_c && rsp_meta_known_c &&
        (req_coalesce_slot_c == rsp_meta_slot_c);
    assign waiter_rsp_enqueue_c = primary_rsp_has_waiter_c ||
        coalesce_on_primary_rsp_c;
    assign waiter_rsp_enqueue_token_c = coalesce_on_primary_rsp_c ?
        req_token_i : meta_waiter_token_q[rsp_meta_slot_c];

    assign fill_index_c =
        meta_word_addr_q[rsp_meta_slot_c][INDEX_W+1:2];
    assign fill_tag_c =
        meta_word_addr_q[rsp_meta_slot_c][31:INDEX_W+2];
    always_comb begin
        fill_way_match_c = '0;
        fill_way_invalid_c = '0;
        fill_way_c = replacement_way_q[fill_index_c];
        fill_way_selected_c = 1'b0;
        for (int unsigned way = 0; way < WAY_COUNT; way++) begin
            fill_way_match_c[way] = line_valid_q[way][fill_index_c] &&
                (line_tag_q[way][fill_index_c] == fill_tag_c);
            fill_way_invalid_c[way] = !line_valid_q[way][fill_index_c];
            if (fill_way_match_c[way] && !fill_way_selected_c) begin
                fill_way_c = WAY_W'(way);
                fill_way_selected_c = 1'b1;
            end
        end
        if (!fill_way_selected_c) begin
            for (int unsigned way = 0; way < WAY_COUNT; way++) begin
                if (fill_way_invalid_c[way] && !fill_way_selected_c) begin
                    fill_way_c = WAY_W'(way);
                    fill_way_selected_c = 1'b1;
                end
            end
        end
    end

    always_comb begin
        fill_same_word_other_inflight_c = 1'b0;
        for (int unsigned slot = 0; slot < 2; slot++) begin
            if (down_rsp_fire_c && rsp_meta_known_c &&
                (slot != rsp_meta_slot_c) && meta_valid_q[slot] &&
                meta_cacheable_load_q[slot] &&
                (meta_word_addr_q[slot] ==
                 meta_word_addr_q[rsp_meta_slot_c]))
                fill_same_word_other_inflight_c = 1'b1;
        end
        if (fill_c && miss_fire_c &&
            (req_word_addr_c == meta_word_addr_q[rsp_meta_slot_c]))
            fill_same_word_other_inflight_c = 1'b1;
    end

    assign store_req_fire_c = forwarded_req_fire_c && req_write_i &&
        (req_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_STORE);
    assign store_invalidate_c = forwarded_req_fire_c && req_write_i &&
        (req_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_STORE) &&
        req_cacheable_range_c;
    assign store_index_c = req_addr_i[INDEX_W+1:2];
    assign store_tag_c = req_addr_i[31:INDEX_W+2];
    always_comb begin
        store_way_match_c = '0;
        store_way_chain_match_c = '0;
        for (int unsigned way = 0; way < WAY_COUNT; way++) begin
            store_way_match_c[way] = line_valid_q[way][store_index_c] &&
                (line_tag_q[way][store_index_c] == store_tag_c);
            store_way_chain_match_c[way] =
                !line_valid_q[way][store_index_c] &&
                (line_invalid_origin_q[way][store_index_c] ==
                 INVALID_ORIGIN_STORE) &&
                (line_tag_q[way][store_index_c] == store_tag_c) &&
                (line_invalid_store_generation_q[way][store_index_c] !=
                 32'b0);
        end
    end
    assign store_way_owner_c = store_way_match_c |
        store_way_chain_match_c;
    assign amo_invalidate_c = forwarded_req_fire_c &&
        (req_token_i.client == BBUS_OOO_MEM_CLIENT_AMO);
    assign store_poison_same_word_inflight_c = store_invalidate_c &&
        ((meta_valid_q[0] && meta_cacheable_load_q[0] &&
          (meta_word_addr_q[0] == req_word_addr_c)) ||
         (meta_valid_q[1] && meta_cacheable_load_q[1] &&
          (meta_word_addr_q[1] == req_word_addr_c)));
    // A store/AMO may pass the cache while an older aligned-word load miss is
    // still in flight.  The load result itself remains valid, but its whole
    // word response predates the write and must not repopulate the cache.
    // Cover both a write racing the response in this cycle and writes which
    // poisoned the matching miss metadata in an earlier cycle.
    assign response_fill_invalidated_c = amo_invalidate_c ||
        (store_invalidate_c &&
         (meta_word_addr_q[rsp_meta_slot_c] == req_word_addr_c));
    assign fill_c = down_rsp_fire_c && rsp_meta_known_c &&
        meta_cacheable_load_q[rsp_meta_slot_c] && !mem_rsp_error_i &&
        !response_fill_invalidated_c;

    assign store_rsp_invalidation_c = down_rsp_fire_c && rsp_meta_known_c &&
        (meta_token_q[rsp_meta_slot_c].client ==
         BBUS_OOO_MEM_CLIENT_LSU_STORE) &&
        meta_store_invalidation_q[rsp_meta_slot_c];
    assign store_rsp_index_c =
        meta_word_addr_q[rsp_meta_slot_c][INDEX_W+1:2];
    assign store_rsp_tag_c =
        meta_word_addr_q[rsp_meta_slot_c][31:INDEX_W+2];
    always_comb begin
        store_rsp_origin_match_c = '0;
        for (int unsigned way = 0; way < WAY_COUNT; way++) begin
            store_rsp_origin_match_c[way] = store_rsp_invalidation_c &&
                !line_valid_q[way][store_rsp_index_c] &&
                (line_invalid_origin_q[way][store_rsp_index_c] ==
                 INVALID_ORIGIN_STORE) &&
                (line_tag_q[way][store_rsp_index_c] == store_rsp_tag_c) &&
                (line_invalid_store_generation_q[way][store_rsp_index_c] ==
                 meta_token_q[rsp_meta_slot_c].generation);
        end
    end
    assign store_rsp_update_opportunity_c = store_rsp_invalidation_c &&
        (|store_rsp_origin_match_c);
    assign store_rsp_update_write_conflict_c = amo_invalidate_c ||
        (store_invalidate_c &&
         (req_word_addr_c == meta_word_addr_q[rsp_meta_slot_c]));
    assign store_rsp_update_fire_c = store_rsp_update_opportunity_c &&
        STORE_RESPONSE_UPDATE_ENABLE && !mem_rsp_error_i &&
        !store_rsp_update_write_conflict_c;
    assign store_rsp_update_disabled_c = store_rsp_update_opportunity_c &&
        !STORE_RESPONSE_UPDATE_ENABLE;
    assign store_rsp_update_error_c = store_rsp_update_opportunity_c &&
        STORE_RESPONSE_UPDATE_ENABLE && mem_rsp_error_i;
    assign store_rsp_update_conflict_c = store_rsp_update_opportunity_c &&
        STORE_RESPONSE_UPDATE_ENABLE && !mem_rsp_error_i &&
        store_rsp_update_write_conflict_c;

    assign hit_o = hit_req_fire_c;
    assign miss_o = miss_fire_c;
    assign fill_o = fill_c;
    assign invalidate_o = amo_invalidate_c ||
        (store_invalidate_c && (|store_way_match_c));
    assign busy_o = hit_rsp_valid_q || waiter_rsp_valid_q || (|meta_valid_q);

    assign perf_causality_error_c =
        (cacheable_load_fire_c !=
         (hit_req_fire_c || miss_fire_c || req_coalesce_fire_c)) ||
        !$onehot0({hit_req_fire_c, miss_fire_c, req_coalesce_fire_c}) ||
        (miss_fire_c != (miss_primary_same_word_c ||
                         miss_primary_invalid_way_c ||
                         miss_primary_full_set_c)) ||
        (miss_fire_c != ((miss_fire_c && miss_any_invalid_way_c) ||
                         (miss_fire_c && !miss_any_invalid_way_c)));

    always_comb begin
        perf_causality_o = '0;
        perf_causality_o[0] = cacheable_load_fire_c;
        perf_causality_o[1] = hit_req_fire_c;
        perf_causality_o[2] = miss_fire_c;
        perf_causality_o[3] = miss_primary_same_word_c;
        perf_causality_o[4] = miss_primary_invalid_way_c;
        perf_causality_o[5] = miss_primary_full_set_c;
        perf_causality_o[6] = miss_same_word_inflight_c;
        perf_causality_o[7] = miss_fire_c && miss_any_invalid_way_c;
        perf_causality_o[8] = miss_fire_c && !miss_any_invalid_way_c;
        perf_causality_o[9] = fill_c;
        perf_causality_o[10] = fill_c && (|fill_way_match_c);
        perf_causality_o[11] = fill_c &&
            fill_same_word_other_inflight_c;
        perf_causality_o[12] = store_req_fire_c;
        // Provenance ownership includes first invalidation and a younger
        // same-tag store taking over an already invalid store-owned line.
        perf_causality_o[13] = store_invalidate_c &&
            (|store_way_owner_c);
        perf_causality_o[14] = store_poison_same_word_inflight_c;
        perf_causality_o[15] = perf_causality_error_c;
    end

    always_comb begin
        perf_coalescing_o = '0;
        perf_coalescing_o[0] = req_coalesce_fire_c;
        perf_coalescing_o[1] = waiter_rsp_enqueue_c;
        perf_coalescing_o[2] = waiter_rsp_fire_c;
        perf_coalescing_o[3] = waiter_rsp_valid_q && !rsp_ready_i;
        perf_coalescing_o[4] = req_valid_i && !req_duplicate_c &&
            !req_array_hit_c && req_coalesce_match_known_c;
        perf_coalescing_o[5] = coalesce_waiter_full_fallback_c;
        perf_coalescing_o[6] = coalesce_on_primary_rsp_c;
        perf_coalescing_o[7] = waiter_rsp_enqueue_c && mem_rsp_error_i;
        perf_coalescing_o[8] = meta_waiter_valid_q[0];
        perf_coalescing_o[9] = meta_waiter_valid_q[1];
        perf_coalescing_o[10] = waiter_rsp_valid_q;
        perf_coalescing_o[11] = req_coalesce_fire_c && mem_req_valid_o;
        perf_coalescing_o[12] = coalescing_invariant_error_c;
        perf_coalescing_o[13] = SAME_WORD_MISS_COALESCING_ENABLE;
        perf_coalescing_o[14] = primary_rsp_has_waiter_c;
        perf_coalescing_o[15] = miss_primary_same_word_c;
    end

    assign invalidation_causality_error_c =
        (miss_primary_invalid_way_c !=
         (miss_invalid_store_same_tag_c ||
          miss_invalid_amo_same_tag_c ||
          miss_invalid_store_other_tag_c ||
          miss_invalid_cold_or_other_c)) ||
        !$onehot0({miss_invalid_store_same_tag_c,
                    miss_invalid_amo_same_tag_c,
                    miss_invalid_store_other_tag_c,
                    miss_invalid_cold_or_other_c});
    always_comb begin
        perf_invalidation_causality_o = '0;
        perf_invalidation_causality_o[0] =
            miss_invalid_store_same_tag_c;
        perf_invalidation_causality_o[1] = miss_invalid_amo_same_tag_c;
        perf_invalidation_causality_o[2] =
            miss_invalid_store_other_tag_c;
        perf_invalidation_causality_o[3] = miss_invalid_cold_or_other_c;
        perf_invalidation_causality_o[4] =
            invalidation_causality_error_c;
    end

    // The low bits retain the P43 lifecycle provenance.  P44 uses bits 42+
    // for the guarded response-update partition; when the feature is disabled,
    // these counters remain observational and cache population is unchanged.
    always_comb begin
        perf_store_origin_o = '0;
        perf_store_origin_o[0] = miss_invalid_store_same_tag_c;
        perf_store_origin_o[1] = miss_invalid_store_same_tag_c &&
            !miss_invalid_store_response_seen_c;
        perf_store_origin_o[2] = miss_invalid_store_same_tag_c &&
            miss_invalid_store_response_seen_c;
        perf_store_origin_o[3] = miss_invalid_store_same_tag_c &&
            !(perf_store_origin_o[1] ^ perf_store_origin_o[2]);
        perf_store_origin_o[4] = store_rsp_invalidation_c;
        perf_store_origin_o[5] = store_rsp_invalidation_c &&
            (|store_rsp_origin_match_c);
        perf_store_origin_o[6] = store_rsp_invalidation_c &&
            !(|store_rsp_origin_match_c);
        perf_store_origin_o[7] = store_invalidate_c &&
            (|store_way_owner_c);
        perf_store_origin_o[39:8] = miss_invalid_store_generation_c;
        perf_store_origin_o[40] = !$onehot0(store_rsp_origin_match_c);
        perf_store_origin_o[41] = miss_invalid_store_same_tag_c &&
            (miss_invalid_store_generation_c == 32'b0);
        perf_store_origin_o[42] = store_rsp_update_opportunity_c;
        perf_store_origin_o[43] = store_rsp_update_fire_c;
        perf_store_origin_o[44] = store_rsp_update_disabled_c;
        perf_store_origin_o[45] = store_rsp_update_error_c;
        perf_store_origin_o[46] = store_rsp_update_conflict_c;
        perf_store_origin_o[47] = store_rsp_update_fire_c &&
            (&meta_store_wstrb_q[rsp_meta_slot_c]);
        perf_store_origin_o[48] = store_rsp_update_fire_c &&
            !(&meta_store_wstrb_q[rsp_meta_slot_c]);
        perf_store_origin_o[49] = STORE_RESPONSE_UPDATE_ENABLE;
        perf_store_origin_o[50] = store_rsp_update_invariant_error_c;
    end

    assign store_rsp_update_invariant_error_c =
        (store_rsp_update_opportunity_c !=
         (store_rsp_update_fire_c || store_rsp_update_disabled_c ||
          store_rsp_update_error_c || store_rsp_update_conflict_c)) ||
        !$onehot0({store_rsp_update_fire_c, store_rsp_update_disabled_c,
                    store_rsp_update_error_c,
                    store_rsp_update_conflict_c}) ||
        (store_rsp_update_fire_c &&
         (!$onehot(store_rsp_origin_match_c) ||
          !(|meta_store_wstrb_q[rsp_meta_slot_c])));

    always_comb begin
        line_metadata_invariant_error_c = 1'b0;
        for (int unsigned way = 0; way < WAY_COUNT; way++) begin
            for (int unsigned index = 0; index < LINE_COUNT; index++) begin
                if (line_valid_q[way][index] &&
                    ((line_invalid_store_generation_q[way][index] != 32'b0) ||
                     line_invalid_store_response_seen_q[way][index]))
                    line_metadata_invariant_error_c = 1'b1;
            end
        end
    end

    assign coalescing_invariant_error_c =
        (!SAME_WORD_MISS_COALESCING_ENABLE &&
         ((|meta_waiter_valid_q) || waiter_rsp_valid_q)) ||
        (meta_waiter_valid_q[0] &&
         (!meta_valid_q[0] || !meta_waiter_token_q[0].valid ||
          (meta_waiter_token_q[0].client !=
           BBUS_OOO_MEM_CLIENT_LSU_LOAD) ||
          token_equal(meta_waiter_token_q[0], meta_token_q[0]))) ||
        (meta_waiter_valid_q[1] &&
         (!meta_valid_q[1] || !meta_waiter_token_q[1].valid ||
          (meta_waiter_token_q[1].client !=
           BBUS_OOO_MEM_CLIENT_LSU_LOAD) ||
          token_equal(meta_waiter_token_q[1], meta_token_q[1]))) ||
        (meta_waiter_valid_q[0] && meta_waiter_valid_q[1] &&
         token_equal(meta_waiter_token_q[0], meta_waiter_token_q[1])) ||
        (meta_waiter_valid_q[0] && meta_valid_q[1] &&
         token_equal(meta_waiter_token_q[0], meta_token_q[1])) ||
        (meta_waiter_valid_q[1] && meta_valid_q[0] &&
         token_equal(meta_waiter_token_q[1], meta_token_q[0])) ||
        (waiter_rsp_valid_q &&
         (!waiter_rsp_token_q.valid ||
          (waiter_rsp_token_q.client != BBUS_OOO_MEM_CLIENT_LSU_LOAD))) ||
        (waiter_rsp_valid_q && hit_rsp_valid_q &&
         token_equal(waiter_rsp_token_q, hit_rsp_token_q)) ||
        !$onehot0(req_coalesce_match_c) ||
        (waiter_rsp_enqueue_c && waiter_rsp_valid_q) ||
        (req_coalesce_fire_c && mem_req_valid_o);

    assign internal_invariant_error_c =
        (&rsp_meta_match_c) ||
        (meta_valid_q[0] && meta_valid_q[1] &&
         token_equal(meta_token_q[0], meta_token_q[1])) ||
        (hit_rsp_valid_q && !hit_rsp_token_q.valid) ||
        (meta_valid_q[0] && meta_cacheable_load_q[0] &&
         (meta_token_q[0].client != BBUS_OOO_MEM_CLIENT_LSU_LOAD)) ||
        (meta_valid_q[1] && meta_cacheable_load_q[1] &&
         (meta_token_q[1].client != BBUS_OOO_MEM_CLIENT_LSU_LOAD)) ||
        !$onehot0(req_way_hit_c) || !$onehot0(fill_way_match_c) ||
        coalescing_invariant_error_c ||
        store_rsp_update_invariant_error_c ||
        line_metadata_invariant_error_c;
    assign conservation_error_o = conservation_error_q ||
        internal_invariant_error_c;

    always_ff @(posedge clk) begin
        if (reset) begin
            line_valid_q <= '0;
            for (int unsigned way = 0; way < WAY_COUNT; way++) begin
                for (int unsigned index = 0; index < LINE_COUNT; index++) begin
                    line_invalid_store_generation_q[way][index] <= 32'b0;
                    line_invalid_store_response_seen_q[way][index] <= 1'b0;
                end
            end
            replacement_way_q <= '0;
            meta_valid_q <= 2'b00;
            meta_token_q[0] <= '0;
            meta_token_q[1] <= '0;
            meta_cacheable_load_q[0] <= 1'b0;
            meta_cacheable_load_q[1] <= 1'b0;
            meta_store_invalidation_q[0] <= 1'b0;
            meta_store_invalidation_q[1] <= 1'b0;
            meta_word_addr_q[0] <= '0;
            meta_word_addr_q[1] <= '0;
            meta_store_wdata_q[0] <= '0;
            meta_store_wdata_q[1] <= '0;
            meta_store_wstrb_q[0] <= '0;
            meta_store_wstrb_q[1] <= '0;
            meta_waiter_valid_q <= 2'b00;
            meta_waiter_token_q[0] <= '0;
            meta_waiter_token_q[1] <= '0;
            hit_rsp_valid_q <= 1'b0;
            hit_rsp_data_q <= '0;
            hit_rsp_token_q <= '0;
            waiter_rsp_valid_q <= 1'b0;
            waiter_rsp_data_q <= '0;
            waiter_rsp_error_q <= 1'b0;
            waiter_rsp_token_q <= '0;
            conservation_error_q <= 1'b0;
            for (int unsigned way = 0; way < WAY_COUNT; way++) begin
                for (int unsigned index = 0; index < LINE_COUNT; index++)
                    line_invalid_origin_q[way][index] <=
                        INVALID_ORIGIN_COLD;
            end
        end else begin
            if ((req_valid_i && (!req_protocol_legal_c || req_duplicate_c)) ||
                (down_rsp_fire_c && !rsp_meta_known_c) ||
                internal_invariant_error_c)
                conservation_error_q <= 1'b1;

            if (hit_rsp_fire_c) begin
                hit_rsp_valid_q <= 1'b0;
                hit_rsp_data_q <= '0;
                hit_rsp_token_q <= '0;
            end
            if (hit_req_fire_c) begin
                hit_rsp_valid_q <= 1'b1;
                hit_rsp_data_q <= line_data_q[req_hit_way_c][req_index_c];
                hit_rsp_token_q <= req_token_i;
                if (WAY_COUNT > 1)
                    replacement_way_q[req_index_c] <=
                        req_hit_way_c + 1'b1;
            end

            if (waiter_rsp_fire_c) begin
                waiter_rsp_valid_q <= 1'b0;
                waiter_rsp_data_q <= '0;
                waiter_rsp_error_q <= 1'b0;
                waiter_rsp_token_q <= '0;
            end
            if (waiter_rsp_enqueue_c) begin
                waiter_rsp_valid_q <= 1'b1;
                waiter_rsp_data_q <= mem_rsp_rdata_i;
                waiter_rsp_error_q <= mem_rsp_error_i;
                waiter_rsp_token_q <= waiter_rsp_enqueue_token_c;
            end

            if (down_rsp_fire_c && rsp_meta_known_c) begin
                meta_valid_q[rsp_meta_slot_c] <= 1'b0;
                meta_token_q[rsp_meta_slot_c] <= '0;
                meta_cacheable_load_q[rsp_meta_slot_c] <= 1'b0;
                meta_store_invalidation_q[rsp_meta_slot_c] <= 1'b0;
                meta_word_addr_q[rsp_meta_slot_c] <= '0;
                meta_store_wdata_q[rsp_meta_slot_c] <= '0;
                meta_store_wstrb_q[rsp_meta_slot_c] <= '0;
                meta_waiter_valid_q[rsp_meta_slot_c] <= 1'b0;
                meta_waiter_token_q[rsp_meta_slot_c] <= '0;
            end
            if (forwarded_req_fire_c) begin
                meta_valid_q[meta_alloc_slot_c] <= 1'b1;
                meta_token_q[meta_alloc_slot_c] <= req_token_i;
                meta_cacheable_load_q[meta_alloc_slot_c] <=
                    req_cacheable_load_c;
                meta_store_invalidation_q[meta_alloc_slot_c] <=
                    store_invalidate_c && (|store_way_owner_c);
                meta_word_addr_q[meta_alloc_slot_c] <= req_word_addr_c;
                meta_store_wdata_q[meta_alloc_slot_c] <= req_wdata_i;
                meta_store_wstrb_q[meta_alloc_slot_c] <= req_wstrb_i;
                meta_waiter_valid_q[meta_alloc_slot_c] <= 1'b0;
                meta_waiter_token_q[meta_alloc_slot_c] <= '0;
            end
            if (req_coalesce_fire_c && !coalesce_on_primary_rsp_c) begin
                meta_waiter_valid_q[req_coalesce_slot_c] <= 1'b1;
                meta_waiter_token_q[req_coalesce_slot_c] <= req_token_i;
            end

            // Do not let a pre-write load response refill stale bytes after a
            // committed store or AMO has become globally visible.  Keep the
            // metadata entry alive so the original load response is still
            // routed to its requester; only revoke its permission to fill.
            if (amo_invalidate_c) begin
                meta_cacheable_load_q[0] <= 1'b0;
                meta_cacheable_load_q[1] <= 1'b0;
            end else if (store_invalidate_c) begin
                if (meta_valid_q[0] && meta_cacheable_load_q[0] &&
                    (meta_word_addr_q[0] == req_word_addr_c))
                    meta_cacheable_load_q[0] <= 1'b0;
                if (meta_valid_q[1] && meta_cacheable_load_q[1] &&
                    (meta_word_addr_q[1] == req_word_addr_c))
                    meta_cacheable_load_q[1] <= 1'b0;
            end

            if (fill_c) begin
                line_valid_q[fill_way_c][fill_index_c] <= 1'b1;
                line_tag_q[fill_way_c][fill_index_c] <= fill_tag_c;
                line_data_q[fill_way_c][fill_index_c] <= mem_rsp_rdata_i;
                line_invalid_origin_q[fill_way_c][fill_index_c] <=
                    INVALID_ORIGIN_COLD;
                line_invalid_store_generation_q[fill_way_c][fill_index_c] <=
                    32'b0;
                line_invalid_store_response_seen_q[fill_way_c][fill_index_c] <=
                    1'b0;
                if (WAY_COUNT > 1)
                    replacement_way_q[fill_index_c] <= fill_way_c + 1'b1;
            end

            if (store_invalidate_c) begin
                for (int unsigned way = 0; way < WAY_COUNT; way++) begin
                    if (store_way_owner_c[way]) begin
                        line_valid_q[way][store_index_c] <= 1'b0;
                        // Store invalidation has priority over a same-edge
                        // different-tag fill selecting this way.  Rewrite the
                        // tag with the generation owner so provenance cannot
                        // combine the fill tag with the store token.
                        line_tag_q[way][store_index_c] <= store_tag_c;
                        line_invalid_origin_q[way][store_index_c] <=
                            INVALID_ORIGIN_STORE;
                        line_invalid_store_generation_q[way][store_index_c] <=
                            req_token_i.generation;
                        line_invalid_store_response_seen_q[way][store_index_c]
                            <= 1'b0;
                        // Keep the store chain hidden until its youngest
                        // generation responds, but preserve every partial
                        // byte update needed to reconstruct the final word.
                        line_data_q[way][store_index_c] <= merge_store_bytes(
                            line_data_q[way][store_index_c],
                            req_wdata_i, req_wstrb_i);
                    end
                end
            end
            if (store_rsp_invalidation_c) begin
                for (int unsigned way = 0; way < WAY_COUNT; way++) begin
                    if (store_rsp_origin_match_c[way] &&
                        !(store_invalidate_c &&
                          store_way_owner_c[way] &&
                          (store_index_c == store_rsp_index_c)))
                        line_invalid_store_response_seen_q
                            [way][store_rsp_index_c] <= 1'b1;
                end
            end
            if (store_rsp_update_fire_c) begin
                for (int unsigned way = 0; way < WAY_COUNT; way++) begin
                    if (store_rsp_origin_match_c[way]) begin
                        line_valid_q[way][store_rsp_index_c] <= 1'b1;
                        line_data_q[way][store_rsp_index_c] <=
                            merge_store_bytes(
                                line_data_q[way][store_rsp_index_c],
                                meta_store_wdata_q[rsp_meta_slot_c],
                                meta_store_wstrb_q[rsp_meta_slot_c]);
                        line_invalid_origin_q[way][store_rsp_index_c] <=
                            INVALID_ORIGIN_COLD;
                        line_invalid_store_generation_q
                            [way][store_rsp_index_c] <= 32'b0;
                        line_invalid_store_response_seen_q
                            [way][store_rsp_index_c] <= 1'b0;
                    end
                end
            end
            if (amo_invalidate_c) begin
                line_valid_q <= '0;
                for (int unsigned way = 0; way < WAY_COUNT; way++) begin
                    for (int unsigned index = 0; index < LINE_COUNT;
                         index++) begin
                        line_invalid_store_generation_q[way][index] <= 32'b0;
                        line_invalid_store_response_seen_q[way][index] <= 1'b0;
                        if (line_valid_q[way][index])
                            line_invalid_origin_q[way][index] <=
                                INVALID_ORIGIN_AMO;
                    end
                end
            end
        end
    end
endmodule
