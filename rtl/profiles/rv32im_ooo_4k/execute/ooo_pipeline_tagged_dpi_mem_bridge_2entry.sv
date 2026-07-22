`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

`ifndef BBUS_OOO_TAGGED_DPI_PMEM_IMPORTS_SVH
`define BBUS_OOO_TAGGED_DPI_PMEM_IMPORTS_SVH
import "DPI-C" function void dpi_pmem_tagged_req(
    input int channel,
    input int client,
    input int slot,
    input int unsigned generation,
    input int unsigned epoch,
    input int is_write,
    input int unsigned addr,
    input int len,
    input int unsigned data
);

import "DPI-C" function int dpi_pmem_tagged_resp(
    input int channel,
    output int client,
    output int slot,
    output int unsigned generation,
    output int unsigned epoch,
    output int unsigned data,
    output int error
);
`endif

// Two-entry tagged DPI memory bridge.
//
// A scoreboard entry remains live from request acceptance until its response
// is consumed by the upstream client.  Consequently response backpressure is
// included in the two-transaction capacity, rather than creating an implicit
// third accepted transaction behind the response holding register.
module ooo_pipeline_tagged_dpi_mem_bridge_2entry #(
    parameter int unsigned DPI_CHANNEL = 1,
    parameter bit LOAD_TRANSACTION_DEPTH3_ENABLE = 1'b0
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
    input  logic [2:0] debug_load_offer_len_i,
    input  bbus_ooo_mem_token_t debug_load_offer_token_i,

    output logic rsp_valid_o,
    input  logic rsp_ready_i,
    output logic [31:0] rsp_rdata_o,
    output logic rsp_error_o,
    output bbus_ooo_mem_token_t rsp_token_o,

    output logic busy_o,
    output logic [1:0] outstanding_count_o,
    output logic [1:0] max_outstanding_o,
    output logic req_fire_o,
    output logic rsp_capture_o,
    output logic rsp_fire_o,
    output logic unknown_response_guard_o,
    output logic duplicate_response_guard_o,
    output logic protocol_error_o,
    output logic [7:0] debug_load_turnover_o
);
    logic [2:0] entry_valid_q;
    logic [2:0] entry_responded_q;
    bbus_ooo_mem_token_t entry_token_q [2:0];

    logic response_valid_q;
    logic [1:0] response_entry_q;
    bbus_ooo_mem_token_t response_token_q;
    logic [31:0] response_data_q;
    logic response_error_q;

    logic [1:0] retired_valid_q;
    bbus_ooo_mem_token_t retired_token_q [1:0];

    logic [1:0] max_outstanding_q;
    logic unknown_response_q;
    logic duplicate_response_q;
    logic protocol_error_q;

    int dpi_client;
    int dpi_slot;
    int unsigned dpi_generation;
    int unsigned dpi_epoch;
    int unsigned dpi_data;
    int dpi_error;

    logic len_legal_c;
    logic request_protocol_error_c;
    logic duplicate_request_c;
    logic request_fire_c;
    logic response_fire_c;
    logic [1:0] allocation_slot_c;
    logic [2:0] effective_valid_c;
    logic [2:0] outstanding_count_c;
    logic [2:0] next_outstanding_count_c;
    logic internal_invariant_error_c;
    logic debug_load_token_legal_c, debug_load_len_legal_c;
    logic debug_load_duplicate_c, debug_load_ready_c;
    logic debug_load_depth3_ready_c;
    logic [2:0] capacity_c;
    logic [2:0] effective_count_c;

    function automatic logic token_equal(
        input bbus_ooo_mem_token_t a,
        input bbus_ooo_mem_token_t b
    );
        token_equal = a.valid && b.valid &&
            (a.client == b.client) && (a.slot == b.slot) &&
            (a.generation == b.generation) &&
            (a.recovery_epoch == b.recovery_epoch);
    endfunction

    function automatic logic dpi_token_equal(
        input bbus_ooo_mem_token_t token,
        input int client,
        input int slot,
        input int unsigned generation,
        input int unsigned epoch
    );
        dpi_token_equal = token.valid &&
            (client == int'(token.client)) &&
            (slot == int'(token.slot)) &&
            (generation == token.generation) &&
            (epoch == token.recovery_epoch);
    endfunction

    assign len_legal_c =
        (req_len_i == 3'd1) || (req_len_i == 3'd2) ||
        (req_len_i == 3'd4);
    assign response_fire_c = response_valid_q && rsp_ready_i;

    // A response consumed on this edge frees its scoreboard slot immediately,
    // allowing a full bridge to accept one replacement request on the same
    // edge without ever exceeding two accepted transactions.
    always_comb begin
        effective_valid_c = entry_valid_q;
        if (response_fire_c)
            effective_valid_c[response_entry_q] = 1'b0;
    end

    assign duplicate_request_c = req_token_i.valid &&
        ((effective_valid_c[0] && token_equal(req_token_i, entry_token_q[0])) ||
         (effective_valid_c[1] && token_equal(req_token_i, entry_token_q[1])) ||
         (effective_valid_c[2] && token_equal(req_token_i, entry_token_q[2])));
    assign request_protocol_error_c = req_valid_i &&
        (!len_legal_c || !req_token_i.valid || duplicate_request_c);
    assign capacity_c = LOAD_TRANSACTION_DEPTH3_ENABLE ? 3'd3 : 3'd2;
    assign effective_count_c = {2'b0, effective_valid_c[0]} +
        {2'b0, effective_valid_c[1]} + {2'b0, effective_valid_c[2]};
    assign req_ready_o = !reset && len_legal_c && req_token_i.valid &&
        !duplicate_request_c && (effective_count_c < capacity_c);
    assign request_fire_c = req_valid_i && req_ready_o;
    always_comb begin
        allocation_slot_c = 2'd0;
        if (effective_valid_c[0])
            allocation_slot_c = effective_valid_c[1] ? 2'd2 : 2'd1;
    end

    assign debug_load_token_legal_c = debug_load_offer_token_i.valid &&
        (debug_load_offer_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_LOAD);
    assign debug_load_len_legal_c =
        (debug_load_offer_len_i == 3'd1) ||
        (debug_load_offer_len_i == 3'd2) ||
        (debug_load_offer_len_i == 3'd4);
    assign debug_load_duplicate_c = debug_load_token_legal_c &&
        ((effective_valid_c[0] &&
         token_equal(debug_load_offer_token_i, entry_token_q[0])) ||
         (effective_valid_c[1] &&
          token_equal(debug_load_offer_token_i, entry_token_q[1])) ||
         (effective_valid_c[2] &&
          token_equal(debug_load_offer_token_i, entry_token_q[2])));
    assign debug_load_ready_c = debug_load_offer_valid_i && !reset &&
        debug_load_token_legal_c && debug_load_len_legal_c &&
        !debug_load_duplicate_c && (effective_count_c < capacity_c);
    assign debug_load_depth3_ready_c = debug_load_offer_valid_i && !reset &&
        debug_load_token_legal_c && debug_load_len_legal_c &&
        !debug_load_duplicate_c;

    always_comb begin
        debug_load_turnover_o = '0;
        debug_load_turnover_o[0] = debug_load_offer_valid_i;
        debug_load_turnover_o[1] = debug_load_token_legal_c &&
            debug_load_len_legal_c;
        debug_load_turnover_o[2] = debug_load_duplicate_c;
        debug_load_turnover_o[3] = outstanding_count_c >= capacity_c;
        debug_load_turnover_o[4] = response_fire_c;
        debug_load_turnover_o[5] = effective_count_c < capacity_c;
        debug_load_turnover_o[6] = debug_load_ready_c;
        debug_load_turnover_o[7] = debug_load_depth3_ready_c;
    end

    assign rsp_valid_o = !reset && response_valid_q;
    assign rsp_rdata_o = response_data_q;
    assign rsp_error_o = response_error_q;
    assign rsp_token_o = response_token_q;

    assign outstanding_count_c =
        {2'b0, entry_valid_q[0]} + {2'b0, entry_valid_q[1]} +
        {2'b0, entry_valid_q[2]};
    always_comb begin
        next_outstanding_count_c = outstanding_count_c;
        if (request_fire_c)
            next_outstanding_count_c = next_outstanding_count_c + 3'd1;
        if (response_fire_c)
            next_outstanding_count_c = next_outstanding_count_c - 3'd1;
    end
    assign outstanding_count_o = outstanding_count_c[1:0];
    assign max_outstanding_o = max_outstanding_q;
    assign busy_o = |entry_valid_q;
    assign unknown_response_guard_o = unknown_response_q;
    assign duplicate_response_guard_o = duplicate_response_q;

    // Exactly one responded scoreboard entry must correspond to the single
    // response holding register.  All other live entries are still owned by
    // the DPI service.
    assign internal_invariant_error_c =
        (|(entry_responded_q & ~entry_valid_q)) ||
        (response_valid_q &&
         (!entry_valid_q[response_entry_q] ||
          !entry_responded_q[response_entry_q] ||
          !token_equal(response_token_q, entry_token_q[response_entry_q]))) ||
        (!response_valid_q && (|entry_responded_q)) ||
        (response_valid_q &&
         (({2'b0, entry_responded_q[0]} +
           {2'b0, entry_responded_q[1]} +
           {2'b0, entry_responded_q[2]}) > 3'd1)) ||
        (!LOAD_TRANSACTION_DEPTH3_ENABLE && entry_valid_q[2]);
    assign protocol_error_o = protocol_error_q ||
        request_protocol_error_c || internal_invariant_error_c;

    always_ff @(posedge clk) begin
        if (reset) begin
            entry_valid_q <= 3'b000;
            entry_responded_q <= 3'b000;
            entry_token_q[0] <= '0;
            entry_token_q[1] <= '0;
            entry_token_q[2] <= '0;
            response_valid_q <= 1'b0;
            response_entry_q <= 2'd0;
            response_token_q <= '0;
            response_data_q <= '0;
            response_error_q <= 1'b0;
            retired_valid_q <= 2'b00;
            retired_token_q[0] <= '0;
            retired_token_q[1] <= '0;
            max_outstanding_q <= 2'b00;
            unknown_response_q <= 1'b0;
            duplicate_response_q <= 1'b0;
            protocol_error_q <= 1'b0;
            req_fire_o <= 1'b0;
            rsp_capture_o <= 1'b0;
            rsp_fire_o <= 1'b0;
        end else begin
            req_fire_o <= 1'b0;
            rsp_capture_o <= 1'b0;
            rsp_fire_o <= 1'b0;

            if (request_protocol_error_c || internal_invariant_error_c ||
                (next_outstanding_count_c > capacity_c))
                protocol_error_q <= 1'b1;

            if (next_outstanding_count_c[1:0] > max_outstanding_q)
                max_outstanding_q <= next_outstanding_count_c[1:0];

            if (response_fire_c) begin
                retired_valid_q[1] <= retired_valid_q[0];
                retired_token_q[1] <= retired_token_q[0];
                retired_valid_q[0] <= 1'b1;
                retired_token_q[0] <= response_token_q;
                entry_valid_q[response_entry_q] <= 1'b0;
                entry_responded_q[response_entry_q] <= 1'b0;
                entry_token_q[response_entry_q] <= '0;
                response_valid_q <= 1'b0;
                response_token_q <= '0;
                response_error_q <= 1'b0;
                rsp_fire_o <= 1'b1;
            end

            // Poll before issuing a same-edge request.  A zero-latency service
            // therefore cannot return a request before its scoreboard entry
            // becomes visible, while an older response may still make room for
            // a replacement request on this edge.
            if (!response_valid_q || response_fire_c) begin
                if (dpi_pmem_tagged_resp(
                    int'(DPI_CHANNEL), dpi_client, dpi_slot,
                    dpi_generation, dpi_epoch, dpi_data, dpi_error
                ) != 0) begin
                    if ((dpi_client < 0) || (dpi_client >= 4) ||
                        (dpi_slot < 0) || (dpi_slot >= 4)) begin
                        unknown_response_q <= 1'b1;
                        protocol_error_q <= 1'b1;
                    end else if (
                        dpi_token_equal(entry_token_q[0], dpi_client, dpi_slot,
                            dpi_generation, dpi_epoch) &&
                        dpi_token_equal(entry_token_q[1], dpi_client, dpi_slot,
                            dpi_generation, dpi_epoch) ||
                        dpi_token_equal(entry_token_q[0], dpi_client, dpi_slot,
                            dpi_generation, dpi_epoch) &&
                        dpi_token_equal(entry_token_q[2], dpi_client, dpi_slot,
                            dpi_generation, dpi_epoch) ||
                        dpi_token_equal(entry_token_q[1], dpi_client, dpi_slot,
                            dpi_generation, dpi_epoch) &&
                        dpi_token_equal(entry_token_q[2], dpi_client, dpi_slot,
                            dpi_generation, dpi_epoch)) begin
                        duplicate_response_q <= 1'b1;
                        protocol_error_q <= 1'b1;
                    end else if (dpi_token_equal(entry_token_q[0], dpi_client,
                        dpi_slot, dpi_generation, dpi_epoch)) begin
                        if (entry_responded_q[0]) begin
                            duplicate_response_q <= 1'b1;
                        end else begin
                            response_valid_q <= 1'b1;
                            response_entry_q <= 2'd0;
                            response_token_q.valid <= 1'b1;
                            response_token_q.client <=
                                bbus_ooo_mem_client_e'(dpi_client);
                            response_token_q.slot <= dpi_slot[1:0];
                            response_token_q.generation <= dpi_generation;
                            response_token_q.recovery_epoch <= dpi_epoch;
                            response_data_q <= dpi_data;
                            response_error_q <= (dpi_error != 0);
                            entry_responded_q[0] <= 1'b1;
                            rsp_capture_o <= 1'b1;
                        end
                    end else if (dpi_token_equal(entry_token_q[1], dpi_client,
                        dpi_slot, dpi_generation, dpi_epoch)) begin
                        if (entry_responded_q[1]) begin
                            duplicate_response_q <= 1'b1;
                        end else begin
                            response_valid_q <= 1'b1;
                            response_entry_q <= 2'd1;
                            response_token_q.valid <= 1'b1;
                            response_token_q.client <=
                                bbus_ooo_mem_client_e'(dpi_client);
                            response_token_q.slot <= dpi_slot[1:0];
                            response_token_q.generation <= dpi_generation;
                            response_token_q.recovery_epoch <= dpi_epoch;
                            response_data_q <= dpi_data;
                            response_error_q <= (dpi_error != 0);
                            entry_responded_q[1] <= 1'b1;
                            rsp_capture_o <= 1'b1;
                        end
                    end else if (dpi_token_equal(entry_token_q[2], dpi_client,
                        dpi_slot, dpi_generation, dpi_epoch)) begin
                        if (entry_responded_q[2]) begin
                            duplicate_response_q <= 1'b1;
                        end else begin
                            response_valid_q <= 1'b1;
                            response_entry_q <= 2'd2;
                            response_token_q.valid <= 1'b1;
                            response_token_q.client <=
                                bbus_ooo_mem_client_e'(dpi_client);
                            response_token_q.slot <= dpi_slot[1:0];
                            response_token_q.generation <= dpi_generation;
                            response_token_q.recovery_epoch <= dpi_epoch;
                            response_data_q <= dpi_data;
                            response_error_q <= (dpi_error != 0);
                            entry_responded_q[2] <= 1'b1;
                            rsp_capture_o <= 1'b1;
                        end
                    end else if (
                        (retired_valid_q[0] &&
                         dpi_token_equal(retired_token_q[0], dpi_client, dpi_slot,
                             dpi_generation, dpi_epoch)) ||
                        (retired_valid_q[1] &&
                         dpi_token_equal(retired_token_q[1], dpi_client, dpi_slot,
                             dpi_generation, dpi_epoch))) begin
                        duplicate_response_q <= 1'b1;
                    end else begin
                        unknown_response_q <= 1'b1;
                    end
                end
            end

            if (request_fire_c) begin
                dpi_pmem_tagged_req(
                    int'(DPI_CHANNEL), int'(req_token_i.client),
                    int'(req_token_i.slot), req_token_i.generation,
                    req_token_i.recovery_epoch, req_write_i ? 1 : 0,
                    req_addr_i, int'(req_len_i), req_wdata_i
                );
                entry_valid_q[allocation_slot_c] <= 1'b1;
                entry_responded_q[allocation_slot_c] <= 1'b0;
                entry_token_q[allocation_slot_c] <= req_token_i;
                req_fire_o <= 1'b1;
            end
        end
    end

    /* verilator lint_off UNUSED */
    wire req_wstrb_unused = ^req_wstrb_i;
    /* verilator lint_on UNUSED */
endmodule
