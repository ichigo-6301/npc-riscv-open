`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// Tagged two-load memory owner.
//
// Ordinary loads may have two exact tokens outstanding.  AMO and legacy
// stores remain exclusive.  One precise buffered store may share the two
// physical owners with a proven-disjoint load when the caller marks it safe.
module ooo_lsu_atomic_mem_arbiter_2e #(
    parameter bit POSTED_STORE_RESPONSE_PIPELINE_ENABLE = 1'b0,
    parameter bit DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE = 1'b0,
    parameter bit PRE_ARBITER_LOAD_HIT_ORACLE_ENABLE = 1'b0,
    parameter bit LOAD_TRANSACTION_DEPTH3_ENABLE = 1'b0
) (
    input logic clk, input logic reset,

    input logic lsu_req_valid_i, output logic lsu_req_ready_o,
    input logic lsu_req_write_i, input logic [31:0] lsu_req_addr_i,
    input logic [31:0] lsu_req_wdata_i, input logic [3:0] lsu_req_wstrb_i,
    input logic [2:0] lsu_req_len_i,
    input bbus_ooo_mem_token_t lsu_req_token_i,
    input logic lsu_store_relaxed_i,
    output logic lsu_rsp_valid_o, input logic lsu_rsp_ready_i,
    output logic [31:0] lsu_rsp_rdata_o, output logic lsu_rsp_error_o,
    output logic lsu_rsp_page_fault_o,
    output bbus_ooo_mem_token_t lsu_rsp_token_o,

    input logic atomic_lock_i,
    input logic atomic_req_valid_i, output logic atomic_req_ready_o,
    input logic atomic_req_write_i, input logic [31:0] atomic_req_addr_i,
    input logic [31:0] atomic_req_wdata_i,
    input logic [3:0] atomic_req_wstrb_i, input logic [2:0] atomic_req_len_i,
    input logic [1:0] atomic_req_access_i,
    input bbus_ooo_mem_token_t atomic_req_token_i,
    output logic atomic_rsp_valid_o, input logic atomic_rsp_ready_i,
    output logic [31:0] atomic_rsp_rdata_o,
    output logic atomic_rsp_error_o, output logic atomic_rsp_page_fault_o,
    output bbus_ooo_mem_token_t atomic_rsp_token_o,

    output logic mem_req_valid_o, input logic mem_req_ready_i,
    output logic mem_req_write_o, output logic [31:0] mem_req_addr_o,
    output logic [31:0] mem_req_wdata_o,
    output logic [3:0] mem_req_wstrb_o, output logic [2:0] mem_req_len_o,
    output logic [1:0] mem_req_access_o,
    output bbus_ooo_mem_token_t mem_req_token_o,
    input logic mem_rsp_valid_i, output logic mem_rsp_ready_o,
    input logic [31:0] mem_rsp_rdata_i, input logic mem_rsp_error_i,
    input logic mem_rsp_page_fault_i,
    input bbus_ooo_mem_token_t mem_rsp_token_i,

    output logic [1:0] load_outstanding_count_o,
    output logic exclusive_active_o,
    output logic third_load_backpressure_o,
    output logic unknown_response_o,
    output logic duplicate_request_o,
    output logic [1:0] owner_o,
    output logic collision_guard_o,
    output logic partial_handoff_guard_o,
    output logic conservation_error_o,
    output logic [15:0] debug_load_turnover_o
);
    typedef enum logic [1:0] {
        EXCL_NONE,
        EXCL_STORE,
        EXCL_AMO
    } exclusive_e;

    exclusive_e exclusive_q;
    logic exclusive_pending_q;
    bbus_ooo_mem_token_t exclusive_token_q;
    logic second_store_pending_q;
    bbus_ooo_mem_token_t second_store_token_q;
    logic [2:0] load_valid_q;
    bbus_ooo_mem_token_t load_token_q [2:0];
    logic store_relaxed_q;

    logic load_req_c, store_req_c, atomic_req_c;
    logic select_atomic_c, select_lsu_c;
    logic common_req_fire_c, common_rsp_fire_c;
    logic load_match0_c, load_match1_c, load_match2_c, load_match_c;
    logic exclusive_match_c, second_store_match_c, response_known_c;
    logic load_request_duplicate_c, store_request_duplicate_c;
    logic request_duplicate_c;
    logic [1:0] alloc_load_slot_c;
    logic relaxed_store_active_c;
    logic [2:0] total_outstanding_c;
    logic store_response_release_c;
    logic store_response_failure_c;
    logic primary_store_release_c, second_store_release_c;
    logic store_capacity_available_c;
    logic store_alloc_primary_c, store_alloc_second_c;
    logic [2:0] effective_outstanding_c;
    logic load_response_release_c;
    logic [2:0] load_turnover_effective_outstanding_c;
    logic load_turnover_arbitration_clear_c;
    logic [2:0] load_turnover_owner_composition_c;
    logic protocol_error_q;
    logic internal_invariant_error_c;
    logic [2:0] load_capacity_c;

    assign load_req_c = lsu_req_valid_i && !lsu_req_write_i &&
        lsu_req_token_i.valid &&
        (lsu_req_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_LOAD);
    assign store_req_c = lsu_req_valid_i && lsu_req_write_i &&
        lsu_req_token_i.valid &&
        (lsu_req_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_STORE);
    assign atomic_req_c = atomic_req_valid_i && atomic_req_token_i.valid &&
        (atomic_req_token_i.client == BBUS_OOO_MEM_CLIENT_AMO);

    assign load_request_duplicate_c = load_req_c &&
        ((load_valid_q[0] && (load_token_q[0] == lsu_req_token_i)) ||
         (load_valid_q[1] && (load_token_q[1] == lsu_req_token_i)) ||
         (load_valid_q[2] && (load_token_q[2] == lsu_req_token_i)));
    assign store_request_duplicate_c = store_req_c &&
        (((exclusive_q == EXCL_STORE) && exclusive_pending_q &&
          (exclusive_token_q == lsu_req_token_i)) ||
         (second_store_pending_q &&
          (second_store_token_q == lsu_req_token_i)));
    assign request_duplicate_c = load_request_duplicate_c ||
        store_request_duplicate_c;
    always_comb begin
        alloc_load_slot_c = 2'd0;
        if (load_valid_q[0])
            alloc_load_slot_c = load_valid_q[1] ? 2'd2 : 2'd1;
    end
    assign load_capacity_c = LOAD_TRANSACTION_DEPTH3_ENABLE ? 3'd3 : 3'd2;
    assign relaxed_store_active_c = (exclusive_q == EXCL_STORE) &&
        exclusive_pending_q && store_relaxed_q;
    assign total_outstanding_c = {2'b0, load_valid_q[0]} +
        {2'b0, load_valid_q[1]} + {2'b0, load_valid_q[2]} +
        {2'b0, exclusive_pending_q} +
        {2'b0, second_store_pending_q};
    assign store_response_release_c =
        POSTED_STORE_RESPONSE_PIPELINE_ENABLE && mem_rsp_valid_i &&
        lsu_rsp_ready_i &&
        (((exclusive_q == EXCL_STORE) && exclusive_match_c) ||
         second_store_match_c) && !mem_rsp_error_i &&
        !mem_rsp_page_fault_i;
    assign store_response_failure_c = mem_rsp_valid_i &&
        lsu_rsp_ready_i &&
        (((exclusive_q == EXCL_STORE) && exclusive_match_c) ||
         second_store_match_c) &&
        (mem_rsp_error_i || mem_rsp_page_fault_i);
    assign effective_outstanding_c = total_outstanding_c -
        {2'b0, store_response_release_c};
    assign load_response_release_c = mem_rsp_valid_i && lsu_rsp_ready_i &&
        load_match_c;
    assign load_turnover_effective_outstanding_c = total_outstanding_c -
        {2'b0, load_response_release_c};
    assign primary_store_release_c = store_response_release_c &&
        (exclusive_q == EXCL_STORE) && exclusive_match_c;
    assign second_store_release_c = store_response_release_c &&
        second_store_match_c;
    assign store_capacity_available_c = !exclusive_pending_q ||
        primary_store_release_c ||
        (DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE &&
         (!second_store_pending_q || second_store_release_c));

    assign select_atomic_c = (exclusive_q == EXCL_AMO) ||
        ((exclusive_q == EXCL_NONE) && (load_valid_q == 3'b000) &&
         atomic_lock_i);
    assign select_lsu_c = !select_atomic_c;

    always_comb begin
        mem_req_valid_o = 1'b0;
        mem_req_write_o = 1'b0;
        mem_req_addr_o = 32'b0;
        mem_req_wdata_o = 32'b0;
        mem_req_wstrb_o = 4'b0;
        mem_req_len_o = 3'b0;
        mem_req_access_o = 2'd1;
        mem_req_token_o = '0;
        lsu_req_ready_o = 1'b0;
        atomic_req_ready_o = 1'b0;

        if (select_atomic_c) begin
            if (!exclusive_pending_q) begin
                mem_req_valid_o = atomic_req_c;
                mem_req_write_o = atomic_req_write_i;
                mem_req_addr_o = atomic_req_addr_i;
                mem_req_wdata_o = atomic_req_wdata_i;
                mem_req_wstrb_o = atomic_req_wstrb_i;
                mem_req_len_o = atomic_req_len_i;
                mem_req_access_o = atomic_req_access_i;
                mem_req_token_o = atomic_req_token_i;
                atomic_req_ready_o = mem_req_ready_i && atomic_req_token_i.valid;
            end
        end else if (select_lsu_c &&
            ((exclusive_q == EXCL_NONE) || relaxed_store_active_c)) begin
            if (store_req_c) begin
                if (lsu_store_relaxed_i ?
                    (!atomic_lock_i && !store_response_failure_c &&
                     store_capacity_available_c &&
                     (effective_outstanding_c < 3'd2)) :
                    (!exclusive_pending_q &&
                     !second_store_pending_q &&
                    (load_valid_q == 3'b000))) begin
                    mem_req_valid_o = 1'b1;
                    mem_req_write_o = 1'b1;
                    mem_req_addr_o = lsu_req_addr_i;
                    mem_req_wdata_o = lsu_req_wdata_i;
                    mem_req_wstrb_o = lsu_req_wstrb_i;
                    mem_req_len_o = lsu_req_len_i;
                    mem_req_access_o = 2'd2;
                    mem_req_token_o = lsu_req_token_i;
                    lsu_req_ready_o = mem_req_ready_i;
                end
            end else if (load_req_c && !atomic_lock_i &&
                (total_outstanding_c < load_capacity_c) &&
                !request_duplicate_c) begin
                mem_req_valid_o = 1'b1;
                mem_req_addr_o = lsu_req_addr_i;
                mem_req_len_o = lsu_req_len_i;
                mem_req_access_o = 2'd1;
                mem_req_token_o = lsu_req_token_i;
                lsu_req_ready_o = mem_req_ready_i;
            end
        end
    end

    assign common_req_fire_c = mem_req_valid_o && mem_req_ready_i;

    assign load_match0_c = mem_rsp_token_i.valid && load_valid_q[0] &&
        (mem_rsp_token_i == load_token_q[0]);
    assign load_match1_c = mem_rsp_token_i.valid && load_valid_q[1] &&
        (mem_rsp_token_i == load_token_q[1]);
    assign load_match2_c = mem_rsp_token_i.valid && load_valid_q[2] &&
        (mem_rsp_token_i == load_token_q[2]);
    assign load_match_c = load_match0_c || load_match1_c || load_match2_c;
    assign exclusive_match_c = mem_rsp_token_i.valid && exclusive_pending_q &&
        (mem_rsp_token_i == exclusive_token_q);
    assign second_store_match_c = mem_rsp_token_i.valid &&
        second_store_pending_q &&
        (mem_rsp_token_i == second_store_token_q);
    assign response_known_c = load_match_c || exclusive_match_c ||
        second_store_match_c;

    assign lsu_rsp_valid_o = mem_rsp_valid_i &&
        (load_match_c || (exclusive_match_c &&
         (exclusive_q == EXCL_STORE)) || second_store_match_c);
    assign atomic_rsp_valid_o = mem_rsp_valid_i && exclusive_match_c &&
        (exclusive_q == EXCL_AMO);
    assign lsu_rsp_rdata_o = mem_rsp_rdata_i;
    assign lsu_rsp_error_o = mem_rsp_error_i;
    assign lsu_rsp_page_fault_o = mem_rsp_page_fault_i;
    assign lsu_rsp_token_o = mem_rsp_token_i;
    assign atomic_rsp_rdata_o = mem_rsp_rdata_i;
    assign atomic_rsp_error_o = mem_rsp_error_i;
    assign atomic_rsp_page_fault_o = mem_rsp_page_fault_i;
    assign atomic_rsp_token_o = mem_rsp_token_i;
    assign mem_rsp_ready_o = load_match_c ? lsu_rsp_ready_i :
        (exclusive_match_c && (exclusive_q == EXCL_STORE)) ? lsu_rsp_ready_i :
        second_store_match_c ? lsu_rsp_ready_i :
        (exclusive_match_c && (exclusive_q == EXCL_AMO)) ? atomic_rsp_ready_i :
        mem_rsp_valid_i;
    assign common_rsp_fire_c = mem_rsp_valid_i && mem_rsp_ready_o;
    assign store_alloc_primary_c = common_req_fire_c && store_req_c &&
        (!exclusive_pending_q || primary_store_release_c);
    assign store_alloc_second_c = common_req_fire_c && store_req_c &&
        !store_alloc_primary_c && DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE &&
        (!second_store_pending_q || second_store_release_c);

    assign load_outstanding_count_o = {1'b0, load_valid_q[0]} +
        {1'b0, load_valid_q[1]} + {1'b0, load_valid_q[2]};
    assign exclusive_active_o = (exclusive_q != EXCL_NONE);
    assign third_load_backpressure_o = load_req_c &&
        (total_outstanding_c >= load_capacity_c);
    assign unknown_response_o = mem_rsp_valid_i && !response_known_c;
    assign duplicate_request_o = request_duplicate_c;
    assign owner_o = (exclusive_q == EXCL_AMO) ? 2'd2 :
        ((exclusive_q == EXCL_STORE) || (load_valid_q != 3'b000)) ? 2'd1 : 2'd0;
    assign collision_guard_o = atomic_lock_i && lsu_req_valid_i;
    assign partial_handoff_guard_o = unknown_response_o;
    assign internal_invariant_error_c =
        (DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE &&
         !POSTED_STORE_RESPONSE_PIPELINE_ENABLE) ||
        (!DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE &&
         second_store_pending_q) ||
        (second_store_pending_q &&
         (!exclusive_pending_q || (exclusive_q != EXCL_STORE) ||
          !second_store_token_q.valid)) ||
        (second_store_pending_q &&
         (second_store_token_q == exclusive_token_q)) ||
        (total_outstanding_c > load_capacity_c) ||
        (!LOAD_TRANSACTION_DEPTH3_ENABLE && load_valid_q[2]);
    assign conservation_error_o = protocol_error_q ||
        internal_invariant_error_c;
    always_comb begin
        load_turnover_owner_composition_c = 3'd5;
        if (exclusive_q == EXCL_AMO) begin
            load_turnover_owner_composition_c = 3'd4;
        end else if (total_outstanding_c < load_capacity_c) begin
            load_turnover_owner_composition_c = 3'd0;
        end else if ((load_valid_q == 3'b011) && !exclusive_pending_q &&
                     !second_store_pending_q) begin
            load_turnover_owner_composition_c = 3'd1;
        end else if ((load_valid_q != 3'b000) &&
                     (exclusive_q == EXCL_STORE) && exclusive_pending_q &&
                     !second_store_pending_q) begin
            load_turnover_owner_composition_c = 3'd2;
        end else if ((load_valid_q == 3'b000) &&
                     (exclusive_q == EXCL_STORE) && exclusive_pending_q &&
                     second_store_pending_q) begin
            load_turnover_owner_composition_c = 3'd3;
        end

        debug_load_turnover_o = '0;
        debug_load_turnover_o[0] = load_req_c;
        debug_load_turnover_o[1] = load_req_c &&
            (total_outstanding_c >= load_capacity_c);
        debug_load_turnover_o[2] = mem_rsp_valid_i && load_match_c;
        debug_load_turnover_o[3] = load_response_release_c;
        debug_load_turnover_o[4] =
            load_turnover_effective_outstanding_c < load_capacity_c;
        debug_load_turnover_o[5] = select_lsu_c &&
            ((exclusive_q == EXCL_NONE) || relaxed_store_active_c) &&
            !atomic_lock_i && !request_duplicate_c;
        debug_load_turnover_o[6] = mem_req_ready_i;
        debug_load_turnover_o[7] = debug_load_turnover_o[1] &&
            debug_load_turnover_o[3] && debug_load_turnover_o[4] &&
            debug_load_turnover_o[5] && debug_load_turnover_o[6];
        debug_load_turnover_o[8] = lsu_req_token_i.slot[0];
        if (PRE_ARBITER_LOAD_HIT_ORACLE_ENABLE) begin
            debug_load_turnover_o[11:9] =
                load_turnover_owner_composition_c;
            debug_load_turnover_o[13:12] = total_outstanding_c[1:0];
            debug_load_turnover_o[14] = lsu_rsp_valid_o;
            debug_load_turnover_o[15] = lsu_rsp_ready_i;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            exclusive_q <= EXCL_NONE;
            exclusive_pending_q <= 1'b0;
            exclusive_token_q <= '0;
            second_store_pending_q <= 1'b0;
            second_store_token_q <= '0;
            load_valid_q <= 3'b000;
            load_token_q[0] <= '0;
            load_token_q[1] <= '0;
            load_token_q[2] <= '0;
            store_relaxed_q <= 1'b0;
            protocol_error_q <= 1'b0;
        end else begin
            if ((lsu_req_valid_i && !load_req_c && !store_req_c) ||
                (lsu_req_valid_i && lsu_store_relaxed_i && !store_req_c) ||
                (atomic_req_valid_i && !atomic_req_c) ||
                request_duplicate_c || internal_invariant_error_c)
                protocol_error_q <= 1'b1;

            if (common_req_fire_c) begin
                if (mem_req_token_o.client == BBUS_OOO_MEM_CLIENT_LSU_LOAD) begin
                    load_valid_q[alloc_load_slot_c] <= 1'b1;
                    load_token_q[alloc_load_slot_c] <= mem_req_token_o;
                end else if (mem_req_token_o.client ==
                             BBUS_OOO_MEM_CLIENT_LSU_STORE) begin
                    if (store_alloc_primary_c) begin
                        exclusive_pending_q <= 1'b1;
                        exclusive_token_q <= mem_req_token_o;
                        exclusive_q <= EXCL_STORE;
                        store_relaxed_q <= lsu_store_relaxed_i;
                    end else if (store_alloc_second_c) begin
                        second_store_pending_q <= 1'b1;
                        second_store_token_q <= mem_req_token_o;
                    end else begin
                        protocol_error_q <= 1'b1;
                    end
                end else begin
                    exclusive_pending_q <= 1'b1;
                    exclusive_token_q <= mem_req_token_o;
                    exclusive_q <= EXCL_AMO;
                    store_relaxed_q <= 1'b0;
                end
            end

            if (common_rsp_fire_c) begin
                if (load_match0_c) begin
                    load_valid_q[0] <= 1'b0;
                    load_token_q[0] <= '0;
                end else if (load_match1_c) begin
                    load_valid_q[1] <= 1'b0;
                    load_token_q[1] <= '0;
                end else if (load_match2_c) begin
                    load_valid_q[2] <= 1'b0;
                    load_token_q[2] <= '0;
                end else if (second_store_match_c) begin
                    if (!store_alloc_second_c) begin
                        second_store_pending_q <= 1'b0;
                        second_store_token_q <= '0;
                    end
                end else if (exclusive_match_c) begin
                    // Preserve a new exclusive request installed on the same
                    // edge that releases the old posted-store response owner.
                    if ((exclusive_q == EXCL_STORE) &&
                        !store_alloc_primary_c && second_store_pending_q) begin
                        exclusive_pending_q <= 1'b1;
                        exclusive_token_q <= second_store_token_q;
                        exclusive_q <= EXCL_STORE;
                        store_relaxed_q <= 1'b1;
                        second_store_pending_q <= 1'b0;
                        second_store_token_q <= '0;
                    end else if (!store_alloc_primary_c) begin
                        exclusive_pending_q <= 1'b0;
                        exclusive_token_q <= '0;
                        store_relaxed_q <= 1'b0;
                        if (exclusive_q == EXCL_STORE)
                            exclusive_q <= EXCL_NONE;
                    end
                end else begin
                    protocol_error_q <= 1'b1;
                end
            end

            if ((exclusive_q == EXCL_AMO) && !exclusive_pending_q &&
                !atomic_lock_i && !atomic_req_valid_i)
                exclusive_q <= EXCL_NONE;
        end
    end
endmodule
