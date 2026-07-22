`timescale 1ns / 1ps

module ooo_sv32_page_walker_1w (
    input  logic clk,
    input  logic reset,

    input  logic req_valid_i,
    output logic req_ready_o,
    input  logic [31:0] req_vaddr_i,
    input  logic [1:0] req_access_i,
    input  logic [1:0] req_priv_i,
    input  logic req_sum_i,
    input  logic req_mxr_i,
    input  logic [31:0] req_satp_i,

    output logic pte_req_valid_o,
    input  logic pte_req_ready_i,
    output logic [31:0] pte_req_addr_o,
    input  logic pte_rsp_valid_i,
    output logic pte_rsp_ready_o,
    input  logic [31:0] pte_rsp_data_i,
    input  logic pte_rsp_error_i,

    output logic rsp_valid_o,
    input  logic rsp_ready_i,
    output logic [31:0] rsp_paddr_o,
    output logic rsp_page_fault_o,
    output logic rsp_access_fault_o,
    output logic [31:0] rsp_tval_o,
    output logic busy_o,
    output logic conservation_error_o
);
    localparam logic [1:0] ACCESS_FETCH = 2'd0;
    localparam logic [1:0] ACCESS_LOAD  = 2'd1;
    localparam logic [1:0] ACCESS_STORE = 2'd2;
    localparam logic [1:0] PRIV_U = 2'd0;
    localparam logic [1:0] PRIV_S = 2'd1;
    localparam logic [1:0] PRIV_M = 2'd3;

    typedef enum logic [2:0] {W_IDLE, W_PTE_REQ, W_PTE_WAIT, W_RESULT} state_e;
    state_e state_q;
    logic [31:0] vaddr_q, table_addr_q, paddr_q;
    logic [1:0] access_q, priv_q;
    logic sum_q, mxr_q, level_q, page_fault_q, access_fault_q;
    logic conservation_error_q;

    logic req_fire_c, pte_req_fire_c, pte_rsp_fire_c, rsp_fire_c;
    logic pte_v, pte_r, pte_w, pte_x, pte_u, pte_a, pte_d;
    logic leaf_c, permission_ok_c, privilege_ok_c, ad_ok_c, superpage_ok_c;
    logic [31:0] leaf_paddr_c;

    assign req_ready_o = !reset && (state_q == W_IDLE);
    assign req_fire_c = req_valid_i && req_ready_o;
    assign pte_req_valid_o = !reset && (state_q == W_PTE_REQ);
    assign pte_req_addr_o = table_addr_q;
    assign pte_req_fire_c = pte_req_valid_o && pte_req_ready_i;
    assign pte_rsp_ready_o = !reset && (state_q == W_PTE_WAIT);
    assign pte_rsp_fire_c = pte_rsp_valid_i && pte_rsp_ready_o;
    assign rsp_valid_o = !reset && (state_q == W_RESULT);
    assign rsp_paddr_o = paddr_q;
    assign rsp_page_fault_o = page_fault_q;
    assign rsp_access_fault_o = access_fault_q;
    assign rsp_tval_o = vaddr_q;
    assign rsp_fire_c = rsp_valid_o && rsp_ready_i;
    assign busy_o = (state_q != W_IDLE);
    assign conservation_error_o = conservation_error_q;

    assign pte_v = pte_rsp_data_i[0];
    assign pte_r = pte_rsp_data_i[1];
    assign pte_w = pte_rsp_data_i[2];
    assign pte_x = pte_rsp_data_i[3];
    assign pte_u = pte_rsp_data_i[4];
    assign pte_a = pte_rsp_data_i[6];
    assign pte_d = pte_rsp_data_i[7];
    assign leaf_c = pte_r || pte_x;
    assign permission_ok_c =
        (access_q == ACCESS_FETCH) ? pte_x :
        (access_q == ACCESS_LOAD) ? (pte_r || (mxr_q && pte_x)) : pte_w;
    assign privilege_ok_c =
        (priv_q == PRIV_U) ? pte_u :
        (priv_q == PRIV_S) ? (!pte_u || ((access_q != ACCESS_FETCH) && sum_q)) :
        1'b1;
    assign ad_ok_c = pte_a && ((access_q != ACCESS_STORE) || pte_d);
    assign superpage_ok_c = !level_q || (pte_rsp_data_i[19:10] == 10'b0);
    // The standalone NPC PMEM address path is 32 bits. Sv32 defines a
    // 34-bit physical address, so the two high PPN bits are deliberately
    // truncated in the same way as the current reference model.
    assign leaf_paddr_c = level_q ?
        {pte_rsp_data_i[29:20], vaddr_q[21:12], vaddr_q[11:0]} :
        {pte_rsp_data_i[29:10], vaddr_q[11:0]};

    always_ff @(posedge clk) begin
        if (reset) begin
            state_q <= W_IDLE;
            vaddr_q <= '0; table_addr_q <= '0; paddr_q <= '0;
            access_q <= ACCESS_FETCH; priv_q <= PRIV_M; sum_q <= 0; mxr_q <= 0;
            level_q <= 1'b0; page_fault_q <= 0; access_fault_q <= 0;
            conservation_error_q <= 0;
        end else begin
            unique case (state_q)
                W_IDLE: if (req_fire_c) begin
                    vaddr_q <= req_vaddr_i;
                    access_q <= req_access_i; priv_q <= req_priv_i;
                    sum_q <= req_sum_i; mxr_q <= req_mxr_i;
                    paddr_q <= 32'b0;
                    page_fault_q <= 1'b0; access_fault_q <= 1'b0;
                    if (!req_satp_i[31] || (req_priv_i == PRIV_M)) begin
                        paddr_q <= req_vaddr_i;
                        state_q <= W_RESULT;
                    end else begin
                        level_q <= 1'b1;
                        table_addr_q <= {req_satp_i[19:0], 12'b0} +
                            {20'b0, req_vaddr_i[31:22], 2'b00};
                        state_q <= W_PTE_REQ;
                    end
                end
                W_PTE_REQ: if (pte_req_fire_c) state_q <= W_PTE_WAIT;
                W_PTE_WAIT: if (pte_rsp_fire_c) begin
                    if (pte_rsp_error_i) begin
                        access_fault_q <= 1'b1; state_q <= W_RESULT;
                    end else if (!pte_v || (!pte_r && pte_w)) begin
                        page_fault_q <= 1'b1; state_q <= W_RESULT;
                    end else if (!leaf_c && (pte_u || pte_a || pte_d)) begin
                        page_fault_q <= 1'b1; state_q <= W_RESULT;
                    end else if (leaf_c) begin
                        if (!permission_ok_c || !privilege_ok_c ||
                            !ad_ok_c || !superpage_ok_c) begin
                            page_fault_q <= 1'b1;
                        end else begin
                            paddr_q <= leaf_paddr_c;
                        end
                        state_q <= W_RESULT;
                    end else if (level_q) begin
                        level_q <= 1'b0;
                        table_addr_q <= {pte_rsp_data_i[29:10], 12'b0} +
                            {20'b0, vaddr_q[21:12], 2'b00};
                        state_q <= W_PTE_REQ;
                    end else begin
                        page_fault_q <= 1'b1; state_q <= W_RESULT;
                    end
                end
                W_RESULT: if (rsp_fire_c) state_q <= W_IDLE;
                default: begin state_q <= W_IDLE; conservation_error_q <= 1'b1; end
            endcase
        end
    end
endmodule
