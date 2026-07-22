`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_pipeline_data_sv32_adapter_1w (
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
        D_IDLE, D_WALK_REQ, D_WALK_WAIT, D_FINAL_REQ, D_FINAL_WAIT, D_RESPONSE
    } state_e;
    state_e state_q;
    logic [31:0] addr_q, paddr_q, wdata_q, rdata_q, satp_q, mstatus_q;
    logic [3:0] wstrb_q; logic [2:0] len_q; logic [1:0] access_q, priv_q;
    logic write_q, error_q, page_fault_q, conservation_error_q;
    bbus_ooo_mem_token_t upstream_token_q, physical_expected_token_q;
    bbus_ooo_mem_token_t ptw_request_token_c;
    logic [31:0] walker_generation_q;
    logic physical_pending_q;
    logic walker_req_valid, walker_req_ready, walker_rsp_valid, walker_rsp_ready;
    logic [31:0] walker_paddr, walker_tval, walker_pte_addr;
    logic walker_page_fault, walker_access_fault, walker_busy, walker_error;
    logic walker_pte_req_valid, walker_pte_req_ready, walker_pte_rsp_ready;
    logic effective_mprv_c; logic [1:0] effective_priv_c;
    logic walk_state_c, physical_rsp_token_match_c;
    logic physical_rsp_ptw_match_c, physical_rsp_final_match_c;
    logic physical_rsp_mismatch_c, physical_req_fire_c, physical_rsp_fire_c;

    assign effective_mprv_c = (priv_i == 2'd3) && mstatus_i[17];
    assign effective_priv_c = effective_mprv_c ? mstatus_i[12:11] : priv_i;
    assign req_ready_o = !reset && (state_q == D_IDLE);
    assign walker_req_valid = (state_q == D_WALK_REQ);
    assign walker_rsp_ready = (state_q == D_WALK_WAIT);
    assign walk_state_c = (state_q == D_WALK_REQ) || (state_q == D_WALK_WAIT);
    assign walker_pte_req_ready = mem_req_ready_i && !physical_pending_q &&
        walk_state_c;

    always_comb begin
        ptw_request_token_c = '0;
        ptw_request_token_c.valid = 1'b1;
        ptw_request_token_c.client = BBUS_OOO_MEM_CLIENT_PTW;
        ptw_request_token_c.slot = 2'b00;
        ptw_request_token_c.generation = walker_generation_q;
        ptw_request_token_c.recovery_epoch = upstream_token_q.recovery_epoch;
    end

    assign physical_rsp_token_match_c = physical_pending_q &&
        physical_expected_token_q.valid && mem_rsp_token_i.valid &&
        (mem_rsp_token_i.client == physical_expected_token_q.client) &&
        (mem_rsp_token_i.slot == physical_expected_token_q.slot) &&
        (mem_rsp_token_i.generation == physical_expected_token_q.generation) &&
        (mem_rsp_token_i.recovery_epoch == physical_expected_token_q.recovery_epoch);
    assign physical_rsp_ptw_match_c = physical_rsp_token_match_c &&
        (mem_rsp_token_i.client == BBUS_OOO_MEM_CLIENT_PTW) && walk_state_c;
    assign physical_rsp_final_match_c = physical_rsp_token_match_c &&
        (mem_rsp_token_i.client != BBUS_OOO_MEM_CLIENT_PTW) &&
        (state_q == D_FINAL_WAIT);
    assign physical_rsp_mismatch_c = mem_rsp_valid_i &&
        !(physical_rsp_ptw_match_c || physical_rsp_final_match_c);
    assign physical_req_fire_c = mem_req_valid_o && mem_req_ready_i;
    assign physical_rsp_fire_c = mem_rsp_valid_i && mem_rsp_ready_o;

    always_comb begin
        mem_req_valid_o = 1'b0; mem_req_write_o = 1'b0; mem_req_addr_o = 0;
        mem_req_wdata_o = 0; mem_req_wstrb_o = 0; mem_req_len_o = 0;
        mem_req_token_o = '0;
        mem_rsp_ready_o = 1'b0;
        if (walk_state_c) begin
            mem_req_valid_o = walker_pte_req_valid && !physical_pending_q;
            mem_req_addr_o = walker_pte_addr;
            mem_req_len_o = 3'd4;
            mem_req_token_o = ptw_request_token_c;
            mem_req_token_o.valid = mem_req_valid_o;
        end else if (state_q == D_FINAL_REQ) begin
            mem_req_valid_o = !physical_pending_q; mem_req_write_o = write_q;
            mem_req_addr_o = paddr_q; mem_req_wdata_o = wdata_q;
            mem_req_wstrb_o = wstrb_q; mem_req_len_o = len_q;
            mem_req_token_o = upstream_token_q;
        end

        if (mem_rsp_valid_i && physical_rsp_mismatch_c) begin
            // Consume an unknown/stale response without allowing it to reach
            // either the walker or the architectural requester.  Retain the
            // legitimate pending owner so its exact response can still drain.
            mem_rsp_ready_o = 1'b1;
        end else if (physical_rsp_ptw_match_c) begin
            mem_rsp_ready_o = walker_pte_rsp_ready;
        end else if (physical_rsp_final_match_c) begin
            mem_rsp_ready_o = 1'b1;
        end
    end

    assign rsp_valid_o = !reset && (state_q == D_RESPONSE);
    assign rsp_rdata_o = rdata_q; assign rsp_error_o = error_q;
    assign rsp_page_fault_o = page_fault_q;
    assign rsp_token_o = upstream_token_q;
    assign busy_o = (state_q != D_IDLE) || walker_busy;
    assign conservation_error_o = conservation_error_q || walker_error;

    ooo_sv32_page_walker_1w u_walker (
        .clk(clk), .reset(reset), .req_valid_i(walker_req_valid),
        .req_ready_o(walker_req_ready), .req_vaddr_i(addr_q),
        .req_access_i(access_q), .req_priv_i(priv_q),
        .req_sum_i(mstatus_q[18]), .req_mxr_i(mstatus_q[19]), .req_satp_i(satp_q),
        .pte_req_valid_o(walker_pte_req_valid), .pte_req_ready_i(walker_pte_req_ready),
        .pte_req_addr_o(walker_pte_addr),
        .pte_rsp_valid_i(mem_rsp_valid_i && physical_rsp_ptw_match_c),
        .pte_rsp_ready_o(walker_pte_rsp_ready), .pte_rsp_data_i(mem_rsp_rdata_i),
        .pte_rsp_error_i(mem_rsp_error_i), .rsp_valid_o(walker_rsp_valid),
        .rsp_ready_i(walker_rsp_ready), .rsp_paddr_o(walker_paddr),
        .rsp_page_fault_o(walker_page_fault), .rsp_access_fault_o(walker_access_fault),
        .rsp_tval_o(walker_tval), .busy_o(walker_busy), .conservation_error_o(walker_error)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            state_q <= D_IDLE; addr_q <= 0; paddr_q <= 0; wdata_q <= 0; rdata_q <= 0;
            satp_q <= 0; mstatus_q <= 0; priv_q <= 3; access_q <= 0; write_q <= 0;
            wstrb_q <= 0; len_q <= 0; error_q <= 0; page_fault_q <= 0;
            upstream_token_q <= '0; physical_expected_token_q <= '0;
            walker_generation_q <= '0; physical_pending_q <= 1'b0;
            conservation_error_q <= 0;
        end else begin
            if (physical_req_fire_c) begin
                physical_expected_token_q <= mem_req_token_o;
                physical_pending_q <= 1'b1;
                if (mem_req_token_o.client == BBUS_OOO_MEM_CLIENT_PTW)
                    walker_generation_q <= walker_generation_q + 32'd1;
            end
            if (physical_rsp_fire_c &&
                (physical_rsp_ptw_match_c || physical_rsp_final_match_c)) begin
                physical_expected_token_q <= '0;
                physical_pending_q <= 1'b0;
            end
            if (physical_rsp_fire_c && physical_rsp_mismatch_c)
                conservation_error_q <= 1'b1;

            unique case (state_q)
                D_IDLE: if (req_valid_i && req_ready_o) begin
                    addr_q <= req_addr_i; wdata_q <= req_wdata_i; wstrb_q <= req_wstrb_i;
                    len_q <= req_len_i; write_q <= req_write_i; access_q <= req_access_i;
                    satp_q <= satp_i; mstatus_q <= mstatus_i; priv_q <= effective_priv_c;
                    upstream_token_q <= req_token_i;
                    if (!req_token_i.valid ||
                        (req_token_i.client == BBUS_OOO_MEM_CLIENT_PTW))
                        conservation_error_q <= 1'b1;
                    error_q <= 0; page_fault_q <= 0; state_q <= D_WALK_REQ;
                end
                D_WALK_REQ: if (walker_req_valid && walker_req_ready)
                    state_q <= D_WALK_WAIT;
                D_WALK_WAIT: if (walker_rsp_valid) begin
                    if (walker_page_fault) begin page_fault_q <= 1; state_q <= D_RESPONSE; end
                    else if (walker_access_fault) begin error_q <= 1; state_q <= D_RESPONSE; end
                    else begin paddr_q <= walker_paddr; state_q <= D_FINAL_REQ; end
                end
                D_FINAL_REQ: if (mem_req_valid_o && mem_req_ready_i) state_q <= D_FINAL_WAIT;
                D_FINAL_WAIT: if (mem_rsp_valid_i && mem_rsp_ready_o &&
                    physical_rsp_final_match_c) begin
                    rdata_q <= mem_rsp_rdata_i; error_q <= mem_rsp_error_i; state_q <= D_RESPONSE;
                end
                D_RESPONSE: if (rsp_valid_o && rsp_ready_i) begin
                    upstream_token_q <= '0;
                    state_q <= D_IDLE;
                end
                default: begin state_q <= D_IDLE; conservation_error_q <= 1; end
            endcase
        end
    end
endmodule
