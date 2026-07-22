`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// Four-entry FIFO for architecturally committed, fault-free PMEM stores.
//
// Enqueue acceptance is the precise commit point. The caller may acknowledge
// the ROB on the following cycle because address, alignment, translation, and
// PMEM range checks have already made a late architectural fault impossible.
// A physical error after acceptance is therefore a protocol failure, not a
// recoverable store exception.
module ooo_precise_store_buffer_4entry #(
    parameter bit POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE = 1'b0,
    parameter bit POSTED_STORE_RESPONSE_PIPELINE_ENABLE = 1'b0,
    parameter bit DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE = 1'b0,
    parameter logic [31:0] PMEM_BASE = 32'h8000_0000,
    parameter logic [31:0] PMEM_BYTES = 32'h0800_0000
) (
    input logic clk,
    input logic reset,

    input logic enq_valid_i,
    output logic enq_ready_o,
    input bbus_ooo_rob_tag_t enq_rob_tag_i,
    input logic [31:0] enq_addr_i,
    input logic [31:0] enq_wdata_i,
    input logic [3:0] enq_wstrb_i,
    input logic [2:0] enq_len_i,

    input logic query_valid_i,
    input logic [31:0] query_addr_i,
    input logic [2:0] query_len_i,
    output logic query_overlap_o,
    output logic query_full_forward_o,
    output logic query_uncertain_o,
    output logic [31:0] query_data_o,

    output logic ack_valid_o,
    input logic ack_ready_i,
    output bbus_ooo_rob_tag_t ack_rob_tag_o,

    output logic mem_req_valid_o,
    input logic mem_req_ready_i,
    output logic [31:0] mem_req_addr_o,
    output logic [31:0] mem_req_wdata_o,
    output logic [3:0] mem_req_wstrb_o,
    output logic [2:0] mem_req_len_o,
    output bbus_ooo_mem_token_t mem_req_token_o,

    input logic mem_rsp_valid_i,
    output logic mem_rsp_ready_o,
    input logic mem_rsp_error_i,
    input logic mem_rsp_page_fault_i,
    input bbus_ooo_mem_token_t mem_rsp_token_i,

    output logic busy_o,
    output logic full_o,
    output logic [2:0] count_o,
    output logic req_fire_o,
    output logic rsp_fire_o,
    output logic response_owner_valid_o,
    output logic [1:0] response_owner_count_o,
    output logic request_release_fire_o,
    output logic unknown_response_o,
    output logic conservation_error_o
);
    typedef struct packed {
        logic valid;
        logic response_seen;
        bbus_ooo_rob_tag_t rob_tag;
        bbus_ooo_mem_token_t token;
        logic [31:0] addr;
        logic [31:0] wdata;
        logic [3:0] wstrb;
        logic [2:0] len;
    } response_owner_t;

    logic [1:0] head_q, tail_q;
    logic [2:0] count_q;
    logic [3:0] entry_valid_q, entry_issued_q;
    bbus_ooo_rob_tag_t entry_rob_tag_q [3:0];
    logic [31:0] entry_addr_q [3:0];
    logic [31:0] entry_wdata_q [3:0];
    logic [3:0] entry_wstrb_q [3:0];
    logic [2:0] entry_len_q [3:0];
    logic [31:0] entry_generation_q [3:0];
    logic [31:0] store_generation_q;

    logic ack_valid_q;
    bbus_ooo_rob_tag_t ack_rob_tag_q;
    response_owner_t response_owner_q [1:0];
    response_owner_t response_owner_d [1:0];
    response_owner_t request_owner_c;
    logic protocol_error_q;

    logic enq_shape_legal_c, enq_range_legal_c;
    logic enq_fire_c, ack_fire_c, req_fire_c, fifo_release_fire_c;
    logic rsp_token_match_c, rsp_owner_match0_c, rsp_owner_match1_c;
    logic rsp_fire_c, rsp_unknown_fire_c, owner_append_full_c;
    logic response_release_success_c, can_replace_head_c;
    logic [1:0] response_owner_count_c, response_pending_count_c;
    logic [1:0] response_owner_capacity_c;
    logic [32:0] enq_last_byte_c, pmem_limit_c;
    logic [31:0] next_store_generation_c;
    logic internal_invariant_error_c;
    bbus_ooo_mem_token_t request_token_c;

    function automatic logic token_equal(
        input bbus_ooo_mem_token_t a,
        input bbus_ooo_mem_token_t b
    );
        token_equal = a.valid && b.valid &&
            (a.client == b.client) && (a.slot == b.slot) &&
            (a.generation == b.generation) &&
            (a.recovery_epoch == b.recovery_epoch);
    endfunction

    assign pmem_limit_c = {1'b0, PMEM_BASE} + {1'b0, PMEM_BYTES};
    assign enq_last_byte_c = {1'b0, enq_addr_i} +
        {30'b0, enq_len_i} - 33'd1;
    assign enq_shape_legal_c = enq_rob_tag_i.valid &&
        ((enq_len_i == 3'd1) || (enq_len_i == 3'd2) ||
         (enq_len_i == 3'd4)) &&
        ((enq_len_i == 3'd1) ||
         ((enq_len_i == 3'd2) && !enq_addr_i[0]) ||
         ((enq_len_i == 3'd4) && (enq_addr_i[1:0] == 2'b00)));
    assign enq_range_legal_c =
        ({1'b0, enq_addr_i} >= {1'b0, PMEM_BASE}) &&
        (enq_last_byte_c < pmem_limit_c);

    assign ack_valid_o = !reset && ack_valid_q;
    assign ack_rob_tag_o = ack_rob_tag_q;
    assign ack_fire_c = ack_valid_o && ack_ready_i;

    always_comb begin
        request_token_c = '0;
        request_token_c.valid = (count_q != 3'd0) &&
            entry_valid_q[head_q];
        request_token_c.client = BBUS_OOO_MEM_CLIENT_LSU_STORE;
        request_token_c.slot = {1'b0, head_q[0]};
        request_token_c.generation = entry_generation_q[head_q];
        request_token_c.recovery_epoch = 32'b0;
        mem_req_token_o = request_token_c;
        mem_req_token_o.valid = mem_req_valid_o;
    end

    assign rsp_token_match_c = POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE ?
        (rsp_owner_match0_c || rsp_owner_match1_c) :
        ((count_q != 3'd0) && entry_valid_q[head_q] &&
         entry_issued_q[head_q] &&
         token_equal(mem_rsp_token_i, request_token_c));
    assign rsp_owner_match0_c = response_owner_q[0].valid &&
        !response_owner_q[0].response_seen &&
        token_equal(mem_rsp_token_i, response_owner_q[0].token);
    assign rsp_owner_match1_c = response_owner_q[1].valid &&
        !response_owner_q[1].response_seen &&
        token_equal(mem_rsp_token_i, response_owner_q[1].token);
    assign mem_rsp_ready_o = !reset && mem_rsp_valid_i;
    assign rsp_fire_c = mem_rsp_valid_i && mem_rsp_ready_o &&
        rsp_token_match_c;
    assign rsp_unknown_fire_c = mem_rsp_valid_i && mem_rsp_ready_o &&
        !rsp_token_match_c;
    assign response_release_success_c =
        POSTED_STORE_RESPONSE_PIPELINE_ENABLE && rsp_fire_c &&
        rsp_owner_match0_c &&
        !mem_rsp_error_i && !mem_rsp_page_fault_i;
    assign can_replace_head_c =
        (!POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE && rsp_fire_c) ||
        (POSTED_STORE_RESPONSE_PIPELINE_ENABLE && req_fire_c);

    assign enq_ready_o = !reset && enq_shape_legal_c &&
        enq_range_legal_c && (!ack_valid_q || ack_fire_c) &&
        ((count_q < 3'd4) || can_replace_head_c);
    assign enq_fire_c = enq_valid_i && enq_ready_o;
    assign next_store_generation_c = store_generation_q + 32'd1;

    always_comb begin
        request_owner_c = '0;
        request_owner_c.valid = request_token_c.valid;
        request_owner_c.rob_tag = entry_rob_tag_q[head_q];
        request_owner_c.token = request_token_c;
        request_owner_c.addr = entry_addr_q[head_q];
        request_owner_c.wdata = entry_wdata_q[head_q];
        request_owner_c.wstrb = entry_wstrb_q[head_q];
        request_owner_c.len = entry_len_q[head_q];
    end

    assign response_owner_count_c =
        {1'b0, response_owner_q[0].valid} +
        {1'b0, response_owner_q[1].valid};
    assign response_pending_count_c =
        {1'b0, response_owner_q[0].valid &&
         !response_owner_q[0].response_seen} +
        {1'b0, response_owner_q[1].valid &&
         !response_owner_q[1].response_seen};
    assign response_owner_capacity_c =
        DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE ? 2'd2 : 2'd1;

    assign mem_req_valid_o = !reset && (count_q != 3'd0) &&
        entry_valid_q[head_q] && !entry_issued_q[head_q] &&
        (!POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE ||
         (response_owner_count_c < response_owner_capacity_c) ||
         response_release_success_c);
    assign mem_req_addr_o = entry_addr_q[head_q];
    assign mem_req_wdata_o = entry_wdata_q[head_q];
    assign mem_req_wstrb_o = entry_wstrb_q[head_q];
    assign mem_req_len_o = entry_len_q[head_q];
    assign req_fire_c = mem_req_valid_o && mem_req_ready_i;
    assign fifo_release_fire_c =
        POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE ? req_fire_c : rsp_fire_c;

    assign busy_o = (count_q != 3'd0) || ack_valid_q ||
        (response_owner_count_c != 2'd0);
    assign full_o = (count_q == 3'd4);
    assign count_o = count_q;
    assign req_fire_o = req_fire_c;
    assign rsp_fire_o = rsp_fire_c;
    assign response_owner_valid_o = response_pending_count_c != 2'd0;
    assign response_owner_count_o = response_pending_count_c;
    assign request_release_fire_o =
        POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE && req_fire_c;
    assign unknown_response_o = rsp_unknown_fire_c;

    assign internal_invariant_error_c =
        (count_q > 3'd4) ||
        ((count_q == 3'd0) && (|entry_valid_q)) ||
        ((count_q != 3'd0) && !entry_valid_q[head_q]) ||
        (|(entry_issued_q & ~entry_valid_q)) ||
        (POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE &&
         (|entry_issued_q)) ||
        (!POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE &&
         (response_owner_count_c != 2'd0)) ||
        (POSTED_STORE_RESPONSE_PIPELINE_ENABLE &&
         !POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE) ||
        (DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE &&
         (!POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE ||
          !POSTED_STORE_RESPONSE_PIPELINE_ENABLE)) ||
        (response_owner_count_c > response_owner_capacity_c) ||
        (response_owner_q[1].valid && !response_owner_q[0].valid) ||
        (response_owner_q[0].response_seen) ||
        (response_owner_q[1].response_seen &&
         !response_owner_q[0].valid) ||
        (response_owner_q[0].valid &&
         (!response_owner_q[0].token.valid ||
          !response_owner_q[0].rob_tag.valid)) ||
        (response_owner_q[1].valid &&
         (!response_owner_q[1].token.valid ||
          !response_owner_q[1].rob_tag.valid)) ||
        (response_owner_q[0].valid && response_owner_q[1].valid &&
         (response_owner_q[0].token == response_owner_q[1].token));
    assign conservation_error_o = protocol_error_q ||
        internal_invariant_error_c;

    // A younger response cannot release its forwarding payload while an older
    // store remains pending.  Keep it as seen state until owner 0 responds.
    always_comb begin
        response_owner_d[0] = response_owner_q[0];
        response_owner_d[1] = response_owner_q[1];
        owner_append_full_c = 1'b0;
        if (POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE && rsp_fire_c) begin
            if (rsp_owner_match0_c) begin
                if (response_owner_q[1].valid &&
                    response_owner_q[1].response_seen) begin
                    response_owner_d[0] = '0;
                    response_owner_d[1] = '0;
                end else begin
                    response_owner_d[0] = response_owner_q[1];
                    response_owner_d[1] = '0;
                end
            end else if (rsp_owner_match1_c) begin
                response_owner_d[1].response_seen = 1'b1;
            end
        end
        if (POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE && req_fire_c) begin
            if (!response_owner_d[0].valid)
                response_owner_d[0] = request_owner_c;
            else if (!response_owner_d[1].valid)
                response_owner_d[1] = request_owner_c;
            else
                owner_append_full_c = 1'b1;
        end
    end

    // Search oldest-to-youngest so a younger committed store overwrites an
    // older byte. query_data_o is packed from the queried address at byte 0.
    always_comb begin : query_committed_stores
        integer age;
        integer byte_idx;
        integer entry_idx;
        integer owner_idx;
        logic [3:0] requested_mask;
        logic [3:0] covered_mask;
        logic [3:0] expected_wstrb;
        logic [32:0] entry_limit;
        logic [32:0] query_byte_addr;

        query_overlap_o = 1'b0;
        query_full_forward_o = 1'b0;
        query_uncertain_o = 1'b0;
        query_data_o = 32'b0;
        requested_mask = 4'b0000;
        covered_mask = 4'b0000;
        unique case (query_len_i)
            3'd1: requested_mask = 4'b0001;
            3'd2: requested_mask = 4'b0011;
            3'd4: requested_mask = 4'b1111;
            default: requested_mask = 4'b0000;
        endcase

        if (query_valid_i && (requested_mask == 4'b0000))
            query_uncertain_o = 1'b1;

        // Detached requests are normalized oldest-to-youngest. Apply both
        // before the FIFO so every younger buffered store can overwrite them.
        for (owner_idx = 0; owner_idx < 2;
             owner_idx = owner_idx + 1) begin
          if (query_valid_i && response_owner_q[owner_idx].valid) begin
            unique case (response_owner_q[owner_idx].len)
                3'd1: expected_wstrb =
                    4'b0001 << response_owner_q[owner_idx].addr[1:0];
                3'd2: expected_wstrb =
                    4'b0011 << response_owner_q[owner_idx].addr[1:0];
                3'd4: expected_wstrb = 4'b1111;
                default: expected_wstrb = 4'b0000;
            endcase
            if ((expected_wstrb == 4'b0000) ||
                (response_owner_q[owner_idx].wstrb != expected_wstrb))
                query_uncertain_o = 1'b1;

            entry_limit = {1'b0, response_owner_q[owner_idx].addr} +
                {30'b0, response_owner_q[owner_idx].len};
            for (byte_idx = 0; byte_idx < 4;
                 byte_idx = byte_idx + 1) begin
                query_byte_addr = {1'b0, query_addr_i} + byte_idx;
                if (requested_mask[byte_idx] &&
                    (query_byte_addr >=
                     {1'b0, response_owner_q[owner_idx].addr}) &&
                    (query_byte_addr < entry_limit)) begin
                    query_overlap_o = 1'b1;
                    if ((response_owner_q[owner_idx].wstrb ==
                         expected_wstrb) &&
                        response_owner_q[owner_idx].wstrb
                            [query_byte_addr[1:0]]) begin
                        covered_mask[byte_idx] = 1'b1;
                        query_data_o[byte_idx * 8 +: 8] =
                            response_owner_q[owner_idx].wdata
                                [query_byte_addr[1:0] * 8 +: 8];
                    end
                end
            end
          end
        end

        for (age = 0; age < 4; age = age + 1) begin
            entry_idx = (int'(head_q) + age) & 3;
            if (query_valid_i && (age < int'(count_q)) &&
                entry_valid_q[entry_idx]) begin
                unique case (entry_len_q[entry_idx])
                    3'd1: expected_wstrb =
                        4'b0001 << entry_addr_q[entry_idx][1:0];
                    3'd2: expected_wstrb =
                        4'b0011 << entry_addr_q[entry_idx][1:0];
                    3'd4: expected_wstrb = 4'b1111;
                    default: expected_wstrb = 4'b0000;
                endcase
                if ((expected_wstrb == 4'b0000) ||
                    (entry_wstrb_q[entry_idx] != expected_wstrb))
                    query_uncertain_o = 1'b1;

                entry_limit = {1'b0, entry_addr_q[entry_idx]} +
                    {30'b0, entry_len_q[entry_idx]};
                for (byte_idx = 0; byte_idx < 4;
                     byte_idx = byte_idx + 1) begin
                    query_byte_addr = {1'b0, query_addr_i} + byte_idx;
                    if (requested_mask[byte_idx] &&
                        (query_byte_addr >=
                         {1'b0, entry_addr_q[entry_idx]}) &&
                        (query_byte_addr < entry_limit)) begin
                        query_overlap_o = 1'b1;
                        if ((entry_wstrb_q[entry_idx] == expected_wstrb) &&
                            entry_wstrb_q[entry_idx]
                                [query_byte_addr[1:0]]) begin
                            covered_mask[byte_idx] = 1'b1;
                            query_data_o[byte_idx * 8 +: 8] =
                                entry_wdata_q[entry_idx]
                                    [query_byte_addr[1:0] * 8 +: 8];
                        end
                    end
                end
            end
        end

        query_full_forward_o = query_valid_i && !query_uncertain_o &&
            (requested_mask != 4'b0000) &&
            ((covered_mask & requested_mask) == requested_mask);
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            head_q <= 2'b00;
            tail_q <= 2'b00;
            count_q <= 3'd0;
            entry_valid_q <= 4'b0000;
            entry_issued_q <= 4'b0000;
            ack_valid_q <= 1'b0;
            ack_rob_tag_q <= '0;
            response_owner_q[0] <= '0;
            response_owner_q[1] <= '0;
            protocol_error_q <= 1'b0;
            store_generation_q <= 32'b0;
            for (int i = 0; i < 4; i++) begin
                entry_rob_tag_q[i] <= '0;
                entry_addr_q[i] <= 32'b0;
                entry_wdata_q[i] <= 32'b0;
                entry_wstrb_q[i] <= 4'b0;
                entry_len_q[i] <= 3'b0;
                entry_generation_q[i] <= 32'b0;
            end
        end else begin
            if ((enq_valid_i && (!enq_shape_legal_c ||
                 !enq_range_legal_c)) || rsp_unknown_fire_c ||
                owner_append_full_c ||
                internal_invariant_error_c)
                protocol_error_q <= 1'b1;
            if (rsp_fire_c && (mem_rsp_error_i || mem_rsp_page_fault_i))
                protocol_error_q <= 1'b1;

            response_owner_q[0] <= response_owner_d[0];
            response_owner_q[1] <= response_owner_d[1];

            if (ack_fire_c) begin
                ack_valid_q <= 1'b0;
                ack_rob_tag_q <= '0;
            end

            if (req_fire_c) begin
                if (POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE) begin
                    entry_valid_q[head_q] <= 1'b0;
                    entry_issued_q[head_q] <= 1'b0;
                    entry_rob_tag_q[head_q] <= '0;
                    entry_addr_q[head_q] <= 32'b0;
                    entry_wdata_q[head_q] <= 32'b0;
                    entry_wstrb_q[head_q] <= 4'b0;
                    entry_len_q[head_q] <= 3'b0;
                    entry_generation_q[head_q] <= 32'b0;
                    head_q <= head_q + 2'd1;
                end else begin
                    entry_issued_q[head_q] <= 1'b1;
                end
            end

            if (rsp_fire_c) begin
                if (!POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE) begin
                    entry_valid_q[head_q] <= 1'b0;
                    entry_issued_q[head_q] <= 1'b0;
                    entry_rob_tag_q[head_q] <= '0;
                    entry_addr_q[head_q] <= 32'b0;
                    entry_wdata_q[head_q] <= 32'b0;
                    entry_wstrb_q[head_q] <= 4'b0;
                    entry_len_q[head_q] <= 3'b0;
                    entry_generation_q[head_q] <= 32'b0;
                    head_q <= head_q + 2'd1;
                end
            end

            if (enq_fire_c) begin
                entry_valid_q[tail_q] <= 1'b1;
                entry_issued_q[tail_q] <= 1'b0;
                entry_rob_tag_q[tail_q] <= enq_rob_tag_i;
                entry_addr_q[tail_q] <= enq_addr_i;
                entry_wdata_q[tail_q] <= enq_wdata_i;
                entry_wstrb_q[tail_q] <= enq_wstrb_i;
                entry_len_q[tail_q] <= enq_len_i;
                entry_generation_q[tail_q] <= next_store_generation_c;
                store_generation_q <= next_store_generation_c;
                tail_q <= tail_q + 2'd1;
                ack_valid_q <= 1'b1;
                ack_rob_tag_q <= enq_rob_tag_i;
            end

            unique case ({enq_fire_c, fifo_release_fire_c})
                2'b10: count_q <= count_q + 3'd1;
                2'b01: count_q <= count_q - 3'd1;
                default: count_q <= count_q;
            endcase
        end
    end
endmodule
