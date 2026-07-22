`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_lsu_atomic_mem_arbiter_1w (
    input  logic clk,
    input  logic reset,

    input  logic lsu_req_valid_i,
    output logic lsu_req_ready_o,
    input  logic lsu_req_write_i,
    input  logic [31:0] lsu_req_addr_i,
    input  logic [31:0] lsu_req_wdata_i,
    input  logic [3:0] lsu_req_wstrb_i,
    input  logic [2:0] lsu_req_len_i,
    input  bbus_ooo_mem_token_t lsu_req_token_i,
    output logic lsu_rsp_valid_o,
    input  logic lsu_rsp_ready_i,
    output logic [31:0] lsu_rsp_rdata_o,
    output logic lsu_rsp_error_o,
    output logic lsu_rsp_page_fault_o,
    output bbus_ooo_mem_token_t lsu_rsp_token_o,

    input  logic atomic_lock_i,
    input  logic atomic_req_valid_i,
    output logic atomic_req_ready_o,
    input  logic atomic_req_write_i,
    input  logic [31:0] atomic_req_addr_i,
    input  logic [31:0] atomic_req_wdata_i,
    input  logic [3:0] atomic_req_wstrb_i,
    input  logic [2:0] atomic_req_len_i,
    input  logic [1:0] atomic_req_access_i,
    input  bbus_ooo_mem_token_t atomic_req_token_i,
    output logic atomic_rsp_valid_o,
    input  logic atomic_rsp_ready_i,
    output logic [31:0] atomic_rsp_rdata_o,
    output logic atomic_rsp_error_o,
    output logic atomic_rsp_page_fault_o,
    output bbus_ooo_mem_token_t atomic_rsp_token_o,

    output logic mem_req_valid_o,
    input  logic mem_req_ready_i,
    output logic mem_req_write_o,
    output logic [31:0] mem_req_addr_o,
    output logic [31:0] mem_req_wdata_o,
    output logic [3:0] mem_req_wstrb_o,
    output logic [2:0] mem_req_len_o,
    output logic [1:0] mem_req_access_o,
    output bbus_ooo_mem_token_t mem_req_token_o,
    input  logic mem_rsp_valid_i,
    output logic mem_rsp_ready_o,
    input  logic [31:0] mem_rsp_rdata_i,
    input  logic mem_rsp_error_i,
    input  logic mem_rsp_page_fault_i,
    input  bbus_ooo_mem_token_t mem_rsp_token_i,

    output logic [1:0] owner_o,
    output logic collision_guard_o,
    output logic partial_handoff_guard_o,
    output logic conservation_error_o
);
    localparam logic [1:0] OWNER_NONE = 2'd0;
    localparam logic [1:0] OWNER_LSU  = 2'd1;
    localparam logic [1:0] OWNER_AMO  = 2'd2;

    logic [1:0] owner_q;
    logic response_pending_q;
    logic select_atomic_c;
    logic common_req_fire_c;
    logic common_rsp_fire_c;
    logic response_token_match_c;
    logic response_route_lsu_c;
    logic response_route_atomic_c;
    bbus_ooo_mem_token_t expected_token_q;

    assign select_atomic_c =
        (owner_q == OWNER_AMO) ||
        ((owner_q == OWNER_NONE) && atomic_lock_i);

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
            mem_req_valid_o = atomic_req_valid_i;
            mem_req_write_o = atomic_req_write_i;
            mem_req_addr_o = atomic_req_addr_i;
            mem_req_wdata_o = atomic_req_wdata_i;
            mem_req_wstrb_o = atomic_req_wstrb_i;
            mem_req_len_o = atomic_req_len_i;
            mem_req_access_o = atomic_req_access_i;
            mem_req_token_o = atomic_req_token_i;
            atomic_req_ready_o = mem_req_ready_i;
        end else if ((owner_q == OWNER_LSU) || (owner_q == OWNER_NONE)) begin
            mem_req_valid_o = lsu_req_valid_i;
            mem_req_write_o = lsu_req_write_i;
            mem_req_addr_o = lsu_req_addr_i;
            mem_req_wdata_o = lsu_req_wdata_i;
            mem_req_wstrb_o = lsu_req_wstrb_i;
            mem_req_len_o = lsu_req_len_i;
            mem_req_access_o = lsu_req_write_i ? 2'd2 : 2'd1;
            mem_req_token_o = lsu_req_token_i;
            lsu_req_ready_o = mem_req_ready_i;
        end
    end

    assign common_req_fire_c = mem_req_valid_o && mem_req_ready_i;
    assign response_route_lsu_c = mem_rsp_token_i.valid &&
        ((mem_rsp_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_LOAD) ||
         (mem_rsp_token_i.client == BBUS_OOO_MEM_CLIENT_LSU_STORE));
    assign response_route_atomic_c = mem_rsp_token_i.valid &&
        (mem_rsp_token_i.client == BBUS_OOO_MEM_CLIENT_AMO);
    assign response_token_match_c = response_pending_q &&
        (mem_rsp_token_i == expected_token_q);
    assign lsu_rsp_valid_o = mem_rsp_valid_i && response_route_lsu_c;
    assign atomic_rsp_valid_o = mem_rsp_valid_i && response_route_atomic_c;
    assign lsu_rsp_rdata_o = mem_rsp_rdata_i;
    assign atomic_rsp_rdata_o = mem_rsp_rdata_i;
    assign lsu_rsp_error_o = mem_rsp_error_i;
    assign lsu_rsp_page_fault_o = mem_rsp_page_fault_i;
    assign atomic_rsp_error_o = mem_rsp_error_i;
    assign atomic_rsp_page_fault_o = mem_rsp_page_fault_i;
    assign lsu_rsp_token_o = mem_rsp_token_i;
    assign atomic_rsp_token_o = mem_rsp_token_i;
    assign mem_rsp_ready_o =
        response_route_lsu_c ? lsu_rsp_ready_i :
        response_route_atomic_c ? atomic_rsp_ready_i : mem_rsp_valid_i;
    assign common_rsp_fire_c = mem_rsp_valid_i && mem_rsp_ready_o;

    assign owner_o = owner_q;
    assign collision_guard_o =
        atomic_lock_i && lsu_req_valid_i;
    assign partial_handoff_guard_o =
        ((owner_q == OWNER_NONE) && mem_rsp_valid_i) ||
        (mem_rsp_valid_i && (!response_token_match_c ||
          (!response_route_lsu_c && !response_route_atomic_c))) ||
        ((owner_q == OWNER_LSU) && atomic_req_ready_o) ||
        ((owner_q == OWNER_AMO) && lsu_req_ready_o);
    assign conservation_error_o = partial_handoff_guard_o ||
        (response_pending_q && common_req_fire_c);

    always_ff @(posedge clk) begin
        if (reset) begin
            owner_q <= OWNER_NONE;
            response_pending_q <= 1'b0;
            expected_token_q <= '0;
        end else begin
            if (common_req_fire_c) begin
                response_pending_q <= 1'b1;
                expected_token_q <= mem_req_token_o;
                if (owner_q == OWNER_NONE) begin
                    owner_q <= select_atomic_c ? OWNER_AMO : OWNER_LSU;
                end
            end
            if (common_rsp_fire_c && response_token_match_c) begin
                response_pending_q <= 1'b0;
                expected_token_q <= '0;
                if (owner_q == OWNER_LSU) begin
                    owner_q <= OWNER_NONE;
                end
            end

            if ((owner_q == OWNER_AMO) && !response_pending_q &&
                !atomic_lock_i && !atomic_req_valid_i) begin
                owner_q <= OWNER_NONE;
            end
        end
    end
endmodule
