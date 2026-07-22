`timescale 1ns / 1ps

module ooo_pipeline_fetch_sv32_adapter_1w (
    input logic clk,
    input logic reset,
    input logic [31:0] satp_i,
    input logic [31:0] mstatus_i,
    input logic [1:0] priv_i,

    input logic req_valid_i,
    output logic req_ready_o,
    input logic [31:0] req_addr_i,
    input logic [31:0] req_pc_i,
    output logic rsp_valid_o,
    input logic rsp_ready_i,
    output logic [31:0] rsp_addr_o,
    output logic [1:0] rsp_valid_mask_o,
    output logic [63:0] rsp_data_o,
    output logic rsp_eof_o,
    output logic rsp_error_o,
    output logic rsp_page_fault_o,

    output logic pte_req_valid_o,
    input logic pte_req_ready_i,
    output logic [31:0] pte_req_addr_o,
    input logic pte_rsp_valid_i,
    output logic pte_rsp_ready_o,
    input logic [31:0] pte_rsp_data_i,
    input logic pte_rsp_error_i,

    output logic pair_req_valid_o,
    input logic pair_req_ready_i,
    output logic [31:0] pair_req_addr_o,
    output logic [31:0] pair_req_pc_o,
    input logic pair_rsp_valid_i,
    output logic pair_rsp_ready_o,
    input logic [31:0] pair_rsp_addr_i,
    input logic [1:0] pair_rsp_valid_mask_i,
    input logic [63:0] pair_rsp_data_i,
    input logic pair_rsp_eof_i,
    input logic pair_rsp_error_i,

    output logic busy_o,
    output logic conservation_error_o
);
    typedef enum logic [2:0] {
        F_IDLE, F_WALK_REQ, F_WALK_WAIT, F_PAIR_REQ, F_PAIR_WAIT, F_RESPONSE
    } state_e;

    state_e state_q;
    logic [31:0] vaddr_q, vpc_q, paddr_q, satp_q, mstatus_q;
    logic [1:0] priv_q;
    logic [1:0] rsp_mask_q;
    logic [63:0] rsp_data_q;
    logic rsp_eof_q, rsp_error_q, rsp_page_fault_q;
    logic conservation_error_q;
    logic walker_req_valid, walker_req_ready, walker_rsp_valid;
    logic walker_rsp_ready, walker_page_fault, walker_access_fault;
    logic [31:0] walker_paddr, walker_tval;
    logic walker_busy, walker_error;

    assign req_ready_o = !reset && (state_q == F_IDLE);
    assign walker_req_valid = (state_q == F_WALK_REQ);
    assign walker_rsp_ready = (state_q == F_WALK_WAIT);
    assign pair_req_valid_o = (state_q == F_PAIR_REQ);
    assign pair_req_addr_o = {paddr_q[31:3], 3'b000};
    assign pair_req_pc_o = {paddr_q[31:3], vpc_q[2], 2'b00};
    assign pair_rsp_ready_o = (state_q == F_PAIR_WAIT);

    assign rsp_valid_o = !reset && (state_q == F_RESPONSE);
    assign rsp_addr_o = vaddr_q;
    assign rsp_valid_mask_o = rsp_mask_q;
    assign rsp_data_o = rsp_data_q;
    assign rsp_eof_o = rsp_eof_q;
    assign rsp_error_o = rsp_error_q;
    assign rsp_page_fault_o = rsp_page_fault_q;
    assign busy_o = state_q != F_IDLE;
    assign conservation_error_o = conservation_error_q || walker_error;

    ooo_sv32_page_walker_1w u_walker (
        .clk(clk), .reset(reset), .req_valid_i(walker_req_valid),
        .req_ready_o(walker_req_ready), .req_vaddr_i(vaddr_q),
        .req_access_i(2'd0), .req_priv_i(priv_q),
        .req_sum_i(mstatus_q[18]), .req_mxr_i(mstatus_q[19]),
        .req_satp_i(satp_q), .pte_req_valid_o(pte_req_valid_o),
        .pte_req_ready_i(pte_req_ready_i), .pte_req_addr_o(pte_req_addr_o),
        .pte_rsp_valid_i(pte_rsp_valid_i), .pte_rsp_ready_o(pte_rsp_ready_o),
        .pte_rsp_data_i(pte_rsp_data_i), .pte_rsp_error_i(pte_rsp_error_i),
        .rsp_valid_o(walker_rsp_valid), .rsp_ready_i(walker_rsp_ready),
        .rsp_paddr_o(walker_paddr), .rsp_page_fault_o(walker_page_fault),
        .rsp_access_fault_o(walker_access_fault), .rsp_tval_o(walker_tval),
        .busy_o(walker_busy), .conservation_error_o(walker_error)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            state_q <= F_IDLE;
            vaddr_q <= '0;
            vpc_q <= '0;
            paddr_q <= '0;
            satp_q <= '0;
            mstatus_q <= '0;
            priv_q <= 2'd3;
            rsp_mask_q <= '0;
            rsp_data_q <= '0;
            rsp_eof_q <= 1'b0;
            rsp_error_q <= 1'b0;
            rsp_page_fault_q <= 1'b0;
            conservation_error_q <= 1'b0;
        end else begin
            unique case (state_q)
                F_IDLE: if (req_valid_i && req_ready_o) begin
                    vaddr_q <= req_addr_i;
                    vpc_q <= req_pc_i;
                    satp_q <= satp_i;
                    mstatus_q <= mstatus_i;
                    priv_q <= priv_i;
                    rsp_mask_q <= '0;
                    rsp_data_q <= '0;
                    rsp_eof_q <= 1'b0;
                    rsp_error_q <= 1'b0;
                    rsp_page_fault_q <= 1'b0;
                    state_q <= F_WALK_REQ;
                end
                F_WALK_REQ: if (walker_req_valid && walker_req_ready)
                    state_q <= F_WALK_WAIT;
                F_WALK_WAIT: if (walker_rsp_valid) begin
                    if (walker_page_fault) begin
                        rsp_page_fault_q <= 1'b1;
                        state_q <= F_RESPONSE;
                    end else if (walker_access_fault) begin
                        rsp_error_q <= 1'b1;
                        state_q <= F_RESPONSE;
                    end else begin
                        paddr_q <= walker_paddr;
                        state_q <= F_PAIR_REQ;
                    end
                end
                F_PAIR_REQ: if (pair_req_valid_o && pair_req_ready_i)
                    state_q <= F_PAIR_WAIT;
                F_PAIR_WAIT: if (pair_rsp_valid_i && pair_rsp_ready_o) begin
                    rsp_mask_q <= pair_rsp_valid_mask_i;
                    rsp_data_q <= pair_rsp_data_i;
                    rsp_eof_q <= pair_rsp_eof_i;
                    rsp_error_q <= pair_rsp_error_i ||
                        (pair_rsp_addr_i != pair_req_addr_o);
                    state_q <= F_RESPONSE;
                end
                F_RESPONSE: if (rsp_valid_o && rsp_ready_i)
                    state_q <= F_IDLE;
                default: begin
                    state_q <= F_IDLE;
                    conservation_error_q <= 1'b1;
                end
            endcase
        end
    end

    /* verilator lint_off UNUSED */
    wire walker_debug_unused = walker_busy ^ (^walker_tval);
    /* verilator lint_on UNUSED */
endmodule
