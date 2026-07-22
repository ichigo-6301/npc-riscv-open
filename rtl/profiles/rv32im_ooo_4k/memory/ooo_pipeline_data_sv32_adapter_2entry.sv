`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// Two-slot tagged data translation adapter.
//
// Translation is serialized through one page walker.  Once translation has
// completed, two cacheable load accesses may own the physical memory path at
// the same time.  Store, AMO, and non-PMEM accesses remain exclusive.
module ooo_pipeline_data_sv32_adapter_2entry #(
    parameter logic [31:0] PMEM_BASE = 32'h8000_0000,
    parameter logic [31:0] PMEM_BYTES = 32'h0800_0000
) (
    input logic clk, input logic reset,
    input logic [31:0] satp_i, input logic [31:0] mstatus_i,
    input logic [1:0] priv_i,

    input logic req_valid_i, output logic req_ready_o,
    input logic req_write_i, input logic [1:0] req_access_i,
    input logic [31:0] req_addr_i, input logic [31:0] req_wdata_i,
    input logic [3:0] req_wstrb_i, input logic [2:0] req_len_i,
    input bbus_ooo_mem_token_t req_token_i,
    output logic rsp_valid_o, input logic rsp_ready_i,
    output logic [31:0] rsp_rdata_o, output logic rsp_error_o,
    output logic rsp_page_fault_o, output bbus_ooo_mem_token_t rsp_token_o,

    output logic mem_req_valid_o, input logic mem_req_ready_i,
    output logic mem_req_write_o, output logic [31:0] mem_req_addr_o,
    output logic [31:0] mem_req_wdata_o, output logic [3:0] mem_req_wstrb_o,
    output logic [2:0] mem_req_len_o, output bbus_ooo_mem_token_t mem_req_token_o,
    input logic mem_rsp_valid_i, output logic mem_rsp_ready_o,
    input logic [31:0] mem_rsp_rdata_i, input logic mem_rsp_error_i,
    input bbus_ooo_mem_token_t mem_rsp_token_i,
    output logic busy_o, output logic conservation_error_o
);
    typedef enum logic [2:0] {
        SLOT_FREE,
        SLOT_XLT_PENDING,
        SLOT_XLT_ACTIVE,
        SLOT_PHYS_READY,
        SLOT_PHYS_OUTSTANDING,
        SLOT_RESPONSE
    } slot_state_e;

    slot_state_e slot_state_q [1:0];
    logic [31:0] slot_vaddr_q [1:0];
    logic [31:0] slot_paddr_q [1:0];
    logic [31:0] slot_wdata_q [1:0];
    logic [31:0] slot_satp_q [1:0];
    logic [31:0] slot_mstatus_q [1:0];
    logic [63:0] slot_sequence_q [1:0];
    logic [3:0] slot_wstrb_q [1:0];
    logic [2:0] slot_len_q [1:0];
    logic [1:0] slot_access_q [1:0];
    logic [1:0] slot_priv_q [1:0];
    logic slot_write_q [1:0];
    bbus_ooo_mem_token_t slot_token_q [1:0];
    logic [31:0] slot_rsp_data_q [1:0];
    logic slot_rsp_error_q [1:0];
    logic slot_rsp_page_fault_q [1:0];

    logic [63:0] allocation_sequence_q;
    logic walker_owner_valid_q, walker_owner_slot_q;
    logic ptw_pending_q;
    logic [31:0] walker_generation_q;
    bbus_ooo_mem_token_t ptw_expected_token_q;
    logic response_hold_valid_q, response_hold_slot_q;
    logic physical_hold_valid_q, physical_hold_is_ptw_q;
    logic physical_hold_slot_q;
    logic conservation_error_q;

    logic effective_mprv_c;
    logic [1:0] effective_priv_c;
    logic [1:0] slot_live_c, effective_live_c, slot_free_c;
    logic request_token_legal_c, request_shape_legal_c, request_duplicate_c;
    logic request_exclusive_c, resident_exclusive_c;
    logic allocation_slot_c, request_fire_c;

    logic response_candidate_valid_c, response_candidate_slot_c;
    logic response_fire_c;

    logic walker_pending_valid_c, walker_pending_slot_c;
    logic walker_req_valid, walker_req_ready;
    logic walker_rsp_valid, walker_rsp_ready;
    logic [31:0] walker_paddr, walker_tval, walker_pte_addr;
    logic walker_page_fault, walker_access_fault, walker_busy, walker_error;
    logic walker_pte_req_valid, walker_pte_req_ready, walker_pte_rsp_ready;
    logic walker_req_fire_c, walker_rsp_fire_c;

    bbus_ooo_mem_token_t ptw_request_token_c;
    logic ptw_request_eligible_c;
    logic [1:0] final_eligible_c;
    logic final_candidate_valid_c, final_candidate_slot_c;
    logic physical_select_ptw_c, physical_select_final_c;
    logic physical_final_slot_c;
    logic physical_req_fire_c, physical_rsp_fire_c;
    logic physical_rsp_ptw_match_c;
    logic [1:0] physical_rsp_final_match_c;
    logic physical_rsp_known_c, physical_rsp_mismatch_c;
    logic noncacheable_outstanding_c;
    logic internal_invariant_error_c;

    function automatic logic token_equal(
        input bbus_ooo_mem_token_t a,
        input bbus_ooo_mem_token_t b
    );
        token_equal = a.valid && b.valid &&
            (a.client == b.client) && (a.slot == b.slot) &&
            (a.generation == b.generation) &&
            (a.recovery_epoch == b.recovery_epoch);
    endfunction

    function automatic logic cacheable_pmem(input logic [31:0] addr);
        logic [32:0] pmem_limit;
        begin
            pmem_limit = {1'b0, PMEM_BASE} + {1'b0, PMEM_BYTES};
            cacheable_pmem = ({1'b0, addr} >= {1'b0, PMEM_BASE}) &&
                ({1'b0, addr} < pmem_limit);
        end
    endfunction

    function automatic logic translation_bypassed(
        input logic [31:0] satp,
        input logic [1:0] privilege
    );
        translation_bypassed = !satp[31] || (privilege == 2'd3);
    endfunction

    assign effective_mprv_c = (priv_i == 2'd3) && mstatus_i[17];
    assign effective_priv_c = effective_mprv_c ? mstatus_i[12:11] : priv_i;

    always_comb begin
        slot_live_c[0] = (slot_state_q[0] != SLOT_FREE);
        slot_live_c[1] = (slot_state_q[1] != SLOT_FREE);

        response_candidate_valid_c = 1'b0;
        response_candidate_slot_c = 1'b0;
        if (response_hold_valid_q) begin
            response_candidate_valid_c = 1'b1;
            response_candidate_slot_c = response_hold_slot_q;
        end else if (slot_state_q[0] == SLOT_RESPONSE) begin
            response_candidate_valid_c = 1'b1;
            response_candidate_slot_c = 1'b0;
        end else if (slot_state_q[1] == SLOT_RESPONSE) begin
            response_candidate_valid_c = 1'b1;
            response_candidate_slot_c = 1'b1;
        end
    end

    assign rsp_valid_o = !reset && response_candidate_valid_c;
    assign rsp_rdata_o = slot_rsp_data_q[response_candidate_slot_c];
    assign rsp_error_o = slot_rsp_error_q[response_candidate_slot_c];
    assign rsp_page_fault_o = slot_rsp_page_fault_q[response_candidate_slot_c];
    assign rsp_token_o = slot_token_q[response_candidate_slot_c];
    assign response_fire_c = rsp_valid_o && rsp_ready_i;

    always_comb begin
        effective_live_c = slot_live_c;
        if (response_fire_c)
            effective_live_c[response_candidate_slot_c] = 1'b0;
        slot_free_c = ~effective_live_c;
    end

    assign request_token_legal_c = req_token_i.valid &&
        (req_token_i.client != BBUS_OOO_MEM_CLIENT_PTW);
    assign request_shape_legal_c =
        ((req_len_i == 3'd1) || (req_len_i == 3'd2) ||
         (req_len_i == 3'd4)) &&
        (((req_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_LOAD) &&
          !req_write_i && (req_access_i == 2'd1)) ||
         ((req_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_STORE) &&
          req_write_i && (req_access_i == 2'd2)) ||
         ((req_token_i.client == BBUS_OOO_MEM_CLIENT_AMO) &&
          ((req_access_i == 2'd1) || (req_access_i == 2'd2))));
    assign request_duplicate_c = request_token_legal_c &&
        ((effective_live_c[0] && token_equal(req_token_i, slot_token_q[0])) ||
         (effective_live_c[1] && token_equal(req_token_i, slot_token_q[1])));
    assign request_exclusive_c = request_token_legal_c &&
        ((req_token_i.client != BBUS_OOO_MEM_CLIENT_LSU_LOAD) ||
         (translation_bypassed(satp_i, effective_priv_c) &&
          !cacheable_pmem(req_addr_i)));
    assign resident_exclusive_c =
        (effective_live_c[0] &&
         ((slot_token_q[0].client != BBUS_OOO_MEM_CLIENT_LSU_LOAD) ||
          (((slot_state_q[0] == SLOT_PHYS_READY) ||
            (slot_state_q[0] == SLOT_PHYS_OUTSTANDING)) &&
           !cacheable_pmem(slot_paddr_q[0])))) ||
        (effective_live_c[1] &&
         ((slot_token_q[1].client != BBUS_OOO_MEM_CLIENT_LSU_LOAD) ||
          (((slot_state_q[1] == SLOT_PHYS_READY) ||
            (slot_state_q[1] == SLOT_PHYS_OUTSTANDING)) &&
           !cacheable_pmem(slot_paddr_q[1]))));
    assign allocation_slot_c = !slot_free_c[0];
    assign req_ready_o = !reset && request_token_legal_c &&
        request_shape_legal_c &&
        !request_duplicate_c && (|slot_free_c) && !resident_exclusive_c &&
        (!request_exclusive_c || (effective_live_c == 2'b00));
    assign request_fire_c = req_valid_i && req_ready_o;

    always_comb begin
        walker_pending_valid_c = 1'b0;
        walker_pending_slot_c = 1'b0;
        if (slot_state_q[0] == SLOT_XLT_PENDING) begin
            walker_pending_valid_c = 1'b1;
            walker_pending_slot_c = 1'b0;
        end
        if (slot_state_q[1] == SLOT_XLT_PENDING) begin
            if (!walker_pending_valid_c ||
                (slot_sequence_q[1] < slot_sequence_q[0])) begin
                walker_pending_valid_c = 1'b1;
                walker_pending_slot_c = 1'b1;
            end
        end
    end

    assign walker_req_valid = !walker_owner_valid_q && walker_pending_valid_c;
    assign walker_req_fire_c = walker_req_valid && walker_req_ready;
    assign walker_rsp_ready = walker_owner_valid_q;
    assign walker_rsp_fire_c = walker_rsp_valid && walker_rsp_ready;

    ooo_sv32_page_walker_1w u_walker (
        .clk(clk), .reset(reset), .req_valid_i(walker_req_valid),
        .req_ready_o(walker_req_ready),
        .req_vaddr_i(slot_vaddr_q[walker_pending_slot_c]),
        .req_access_i(slot_access_q[walker_pending_slot_c]),
        .req_priv_i(slot_priv_q[walker_pending_slot_c]),
        .req_sum_i(slot_mstatus_q[walker_pending_slot_c][18]),
        .req_mxr_i(slot_mstatus_q[walker_pending_slot_c][19]),
        .req_satp_i(slot_satp_q[walker_pending_slot_c]),
        .pte_req_valid_o(walker_pte_req_valid),
        .pte_req_ready_i(walker_pte_req_ready),
        .pte_req_addr_o(walker_pte_addr),
        .pte_rsp_valid_i(mem_rsp_valid_i && physical_rsp_ptw_match_c),
        .pte_rsp_ready_o(walker_pte_rsp_ready),
        .pte_rsp_data_i(mem_rsp_rdata_i),
        .pte_rsp_error_i(mem_rsp_error_i),
        .rsp_valid_o(walker_rsp_valid), .rsp_ready_i(walker_rsp_ready),
        .rsp_paddr_o(walker_paddr),
        .rsp_page_fault_o(walker_page_fault),
        .rsp_access_fault_o(walker_access_fault),
        .rsp_tval_o(walker_tval), .busy_o(walker_busy),
        .conservation_error_o(walker_error)
    );

    always_comb begin
        ptw_request_token_c = '0;
        ptw_request_token_c.valid = 1'b1;
        ptw_request_token_c.client = BBUS_OOO_MEM_CLIENT_PTW;
        ptw_request_token_c.slot = {1'b0, walker_owner_slot_q};
        ptw_request_token_c.generation = walker_generation_q;
        ptw_request_token_c.recovery_epoch =
            slot_token_q[walker_owner_slot_q].recovery_epoch;
    end

    assign noncacheable_outstanding_c =
        ((slot_state_q[0] == SLOT_PHYS_OUTSTANDING) &&
         !cacheable_pmem(slot_paddr_q[0])) ||
        ((slot_state_q[1] == SLOT_PHYS_OUTSTANDING) &&
         !cacheable_pmem(slot_paddr_q[1]));

    always_comb begin
        ptw_request_eligible_c = walker_pte_req_valid && !ptw_pending_q &&
            !noncacheable_outstanding_c;
        if (walker_owner_valid_q) begin
            if ((slot_state_q[0] == SLOT_PHYS_READY) &&
                !cacheable_pmem(slot_paddr_q[0]) &&
                (slot_sequence_q[0] <
                 slot_sequence_q[walker_owner_slot_q]))
                ptw_request_eligible_c = 1'b0;
            if ((slot_state_q[1] == SLOT_PHYS_READY) &&
                !cacheable_pmem(slot_paddr_q[1]) &&
                (slot_sequence_q[1] <
                 slot_sequence_q[walker_owner_slot_q]))
                ptw_request_eligible_c = 1'b0;
        end
    end

    always_comb begin
        final_eligible_c = 2'b00;
        for (int i = 0; i < 2; i++) begin
            if (slot_state_q[i] == SLOT_PHYS_READY) begin
                final_eligible_c[i] = 1'b1;
                if (noncacheable_outstanding_c)
                    final_eligible_c[i] = 1'b0;

                if (!cacheable_pmem(slot_paddr_q[i])) begin
                    if (ptw_pending_q ||
                        (slot_state_q[0] == SLOT_PHYS_OUTSTANDING) ||
                        (slot_state_q[1] == SLOT_PHYS_OUTSTANDING))
                        final_eligible_c[i] = 1'b0;
                    for (int j = 0; j < 2; j++) begin
                        if ((j != i) && slot_live_c[j] &&
                            (slot_sequence_q[j] < slot_sequence_q[i]) &&
                            (slot_state_q[j] != SLOT_RESPONSE))
                            final_eligible_c[i] = 1'b0;
                    end
                end else begin
                    for (int j = 0; j < 2; j++) begin
                        if ((j != i) && slot_live_c[j] &&
                            (slot_sequence_q[j] < slot_sequence_q[i])) begin
                            if ((slot_state_q[j] == SLOT_XLT_PENDING) ||
                                (slot_state_q[j] == SLOT_XLT_ACTIVE))
                                final_eligible_c[i] = 1'b0;
                            if (((slot_state_q[j] == SLOT_PHYS_READY) ||
                                 (slot_state_q[j] == SLOT_PHYS_OUTSTANDING)) &&
                                !cacheable_pmem(slot_paddr_q[j]))
                                final_eligible_c[i] = 1'b0;
                        end
                    end
                end
            end
        end

        final_candidate_valid_c = |final_eligible_c;
        final_candidate_slot_c = 1'b0;
        if (final_eligible_c == 2'b10)
            final_candidate_slot_c = 1'b1;
        else if (final_eligible_c == 2'b11)
            final_candidate_slot_c =
                (slot_sequence_q[1] < slot_sequence_q[0]);
    end

    always_comb begin
        physical_select_ptw_c = 1'b0;
        physical_select_final_c = 1'b0;
        physical_final_slot_c = final_candidate_slot_c;
        if (physical_hold_valid_q) begin
            physical_select_ptw_c = physical_hold_is_ptw_q;
            physical_select_final_c = !physical_hold_is_ptw_q;
            physical_final_slot_c = physical_hold_slot_q;
        end else if (ptw_request_eligible_c) begin
            physical_select_ptw_c = 1'b1;
        end else if (final_candidate_valid_c) begin
            physical_select_final_c = 1'b1;
        end
    end

    always_comb begin
        mem_req_valid_o = 1'b0;
        mem_req_write_o = 1'b0;
        mem_req_addr_o = 32'b0;
        mem_req_wdata_o = 32'b0;
        mem_req_wstrb_o = 4'b0;
        mem_req_len_o = 3'b0;
        mem_req_token_o = '0;

        if (physical_select_ptw_c) begin
            mem_req_valid_o = 1'b1;
            mem_req_addr_o = walker_pte_addr;
            mem_req_len_o = 3'd4;
            mem_req_token_o = ptw_request_token_c;
        end else if (physical_select_final_c) begin
            mem_req_valid_o = 1'b1;
            mem_req_write_o = slot_write_q[physical_final_slot_c];
            mem_req_addr_o = slot_paddr_q[physical_final_slot_c];
            mem_req_wdata_o = slot_wdata_q[physical_final_slot_c];
            mem_req_wstrb_o = slot_wstrb_q[physical_final_slot_c];
            mem_req_len_o = slot_len_q[physical_final_slot_c];
            mem_req_token_o = slot_token_q[physical_final_slot_c];
        end
    end

    assign walker_pte_req_ready = mem_req_ready_i && physical_select_ptw_c;
    assign physical_req_fire_c = mem_req_valid_o && mem_req_ready_i;

    assign physical_rsp_ptw_match_c = ptw_pending_q &&
        token_equal(mem_rsp_token_i, ptw_expected_token_q);
    assign physical_rsp_final_match_c[0] =
        (slot_state_q[0] == SLOT_PHYS_OUTSTANDING) &&
        token_equal(mem_rsp_token_i, slot_token_q[0]);
    assign physical_rsp_final_match_c[1] =
        (slot_state_q[1] == SLOT_PHYS_OUTSTANDING) &&
        token_equal(mem_rsp_token_i, slot_token_q[1]);
    assign physical_rsp_known_c = physical_rsp_ptw_match_c ||
        (|physical_rsp_final_match_c);
    assign physical_rsp_mismatch_c = mem_rsp_valid_i &&
        !physical_rsp_known_c;

    always_comb begin
        mem_rsp_ready_o = 1'b0;
        if (mem_rsp_valid_i && physical_rsp_mismatch_c)
            mem_rsp_ready_o = 1'b1;
        else if (physical_rsp_ptw_match_c)
            mem_rsp_ready_o = walker_pte_rsp_ready;
        else if (|physical_rsp_final_match_c)
            mem_rsp_ready_o = 1'b1;
    end
    assign physical_rsp_fire_c = mem_rsp_valid_i && mem_rsp_ready_o;

    assign internal_invariant_error_c =
        (walker_owner_valid_q &&
         (slot_state_q[walker_owner_slot_q] != SLOT_XLT_ACTIVE)) ||
        (!walker_owner_valid_q &&
         ((slot_state_q[0] == SLOT_XLT_ACTIVE) ||
          (slot_state_q[1] == SLOT_XLT_ACTIVE))) ||
        (ptw_pending_q && !walker_owner_valid_q) ||
        (response_hold_valid_q &&
         (slot_state_q[response_hold_slot_q] != SLOT_RESPONSE)) ||
        (physical_hold_valid_q && physical_hold_is_ptw_q &&
         !walker_pte_req_valid) ||
        (physical_hold_valid_q && !physical_hold_is_ptw_q &&
         (slot_state_q[physical_hold_slot_q] != SLOT_PHYS_READY)) ||
        (slot_live_c[0] && slot_live_c[1] &&
         token_equal(slot_token_q[0], slot_token_q[1])) ||
        (&physical_rsp_final_match_c);

    assign busy_o = (|slot_live_c) || walker_busy || ptw_pending_q;
    assign conservation_error_o = conservation_error_q || walker_error ||
        internal_invariant_error_c;

    always_ff @(posedge clk) begin
        if (reset) begin
            slot_state_q[0] <= SLOT_FREE;
            slot_state_q[1] <= SLOT_FREE;
            slot_vaddr_q[0] <= '0; slot_vaddr_q[1] <= '0;
            slot_paddr_q[0] <= '0; slot_paddr_q[1] <= '0;
            slot_wdata_q[0] <= '0; slot_wdata_q[1] <= '0;
            slot_satp_q[0] <= '0; slot_satp_q[1] <= '0;
            slot_mstatus_q[0] <= '0; slot_mstatus_q[1] <= '0;
            slot_sequence_q[0] <= '0; slot_sequence_q[1] <= '0;
            slot_wstrb_q[0] <= '0; slot_wstrb_q[1] <= '0;
            slot_len_q[0] <= '0; slot_len_q[1] <= '0;
            slot_access_q[0] <= '0; slot_access_q[1] <= '0;
            slot_priv_q[0] <= 2'd3; slot_priv_q[1] <= 2'd3;
            slot_write_q[0] <= 1'b0; slot_write_q[1] <= 1'b0;
            slot_token_q[0] <= '0; slot_token_q[1] <= '0;
            slot_rsp_data_q[0] <= '0; slot_rsp_data_q[1] <= '0;
            slot_rsp_error_q[0] <= 1'b0; slot_rsp_error_q[1] <= 1'b0;
            slot_rsp_page_fault_q[0] <= 1'b0;
            slot_rsp_page_fault_q[1] <= 1'b0;
            allocation_sequence_q <= '0;
            walker_owner_valid_q <= 1'b0;
            walker_owner_slot_q <= 1'b0;
            ptw_pending_q <= 1'b0;
            walker_generation_q <= '0;
            ptw_expected_token_q <= '0;
            response_hold_valid_q <= 1'b0;
            response_hold_slot_q <= 1'b0;
            physical_hold_valid_q <= 1'b0;
            physical_hold_is_ptw_q <= 1'b0;
            physical_hold_slot_q <= 1'b0;
            conservation_error_q <= 1'b0;
        end else begin
            if ((req_valid_i && (!request_token_legal_c ||
                 !request_shape_legal_c ||
                 request_duplicate_c)) || physical_rsp_mismatch_c ||
                internal_invariant_error_c)
                conservation_error_q <= 1'b1;

            if (rsp_valid_o && !rsp_ready_i && !response_hold_valid_q) begin
                response_hold_valid_q <= 1'b1;
                response_hold_slot_q <= response_candidate_slot_c;
            end
            if (response_fire_c) begin
                slot_state_q[response_candidate_slot_c] <= SLOT_FREE;
                slot_token_q[response_candidate_slot_c] <= '0;
                response_hold_valid_q <= 1'b0;
            end

            if (walker_req_fire_c) begin
                walker_owner_valid_q <= 1'b1;
                walker_owner_slot_q <= walker_pending_slot_c;
                slot_state_q[walker_pending_slot_c] <= SLOT_XLT_ACTIVE;
            end

            if (mem_req_valid_o && !mem_req_ready_i &&
                !physical_hold_valid_q) begin
                physical_hold_valid_q <= 1'b1;
                physical_hold_is_ptw_q <= physical_select_ptw_c;
                physical_hold_slot_q <= physical_final_slot_c;
            end

            if (physical_req_fire_c) begin
                physical_hold_valid_q <= 1'b0;
                if (physical_select_ptw_c) begin
                    ptw_pending_q <= 1'b1;
                    ptw_expected_token_q <= ptw_request_token_c;
                    walker_generation_q <= walker_generation_q + 32'd1;
                end else begin
                    slot_state_q[physical_final_slot_c] <=
                        SLOT_PHYS_OUTSTANDING;
                end
            end

            if (physical_rsp_fire_c && physical_rsp_ptw_match_c) begin
                ptw_pending_q <= 1'b0;
                ptw_expected_token_q <= '0;
            end

            if (physical_rsp_fire_c && physical_rsp_final_match_c[0]) begin
                slot_rsp_data_q[0] <= mem_rsp_rdata_i;
                slot_rsp_error_q[0] <= mem_rsp_error_i;
                slot_rsp_page_fault_q[0] <= 1'b0;
                slot_state_q[0] <= SLOT_RESPONSE;
            end
            if (physical_rsp_fire_c && physical_rsp_final_match_c[1]) begin
                slot_rsp_data_q[1] <= mem_rsp_rdata_i;
                slot_rsp_error_q[1] <= mem_rsp_error_i;
                slot_rsp_page_fault_q[1] <= 1'b0;
                slot_state_q[1] <= SLOT_RESPONSE;
            end

            if (walker_rsp_fire_c) begin
                walker_owner_valid_q <= 1'b0;
                if (walker_page_fault || walker_access_fault) begin
                    slot_rsp_data_q[walker_owner_slot_q] <= 32'b0;
                    slot_rsp_error_q[walker_owner_slot_q] <=
                        walker_access_fault;
                    slot_rsp_page_fault_q[walker_owner_slot_q] <=
                        walker_page_fault;
                    slot_state_q[walker_owner_slot_q] <= SLOT_RESPONSE;
                end else begin
                    slot_paddr_q[walker_owner_slot_q] <= walker_paddr;
                    slot_state_q[walker_owner_slot_q] <= SLOT_PHYS_READY;
                end
            end

            if (request_fire_c) begin
                slot_vaddr_q[allocation_slot_c] <= req_addr_i;
                slot_paddr_q[allocation_slot_c] <= req_addr_i;
                slot_wdata_q[allocation_slot_c] <= req_wdata_i;
                slot_satp_q[allocation_slot_c] <= satp_i;
                slot_mstatus_q[allocation_slot_c] <= mstatus_i;
                slot_sequence_q[allocation_slot_c] <= allocation_sequence_q;
                slot_wstrb_q[allocation_slot_c] <= req_wstrb_i;
                slot_len_q[allocation_slot_c] <= req_len_i;
                slot_access_q[allocation_slot_c] <= req_access_i;
                slot_priv_q[allocation_slot_c] <= effective_priv_c;
                slot_write_q[allocation_slot_c] <= req_write_i;
                slot_token_q[allocation_slot_c] <= req_token_i;
                slot_rsp_data_q[allocation_slot_c] <= 32'b0;
                slot_rsp_error_q[allocation_slot_c] <= 1'b0;
                slot_rsp_page_fault_q[allocation_slot_c] <= 1'b0;
                allocation_sequence_q <= allocation_sequence_q + 64'd1;
                slot_state_q[allocation_slot_c] <=
                    translation_bypassed(satp_i, effective_priv_c) ?
                    SLOT_PHYS_READY : SLOT_XLT_PENDING;
            end
        end
    end

    /* verilator lint_off UNUSED */
    wire walker_tval_unused = ^walker_tval;
    /* verilator lint_on UNUSED */
endmodule
