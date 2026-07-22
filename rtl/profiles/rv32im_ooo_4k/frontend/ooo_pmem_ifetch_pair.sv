`timescale 1ns / 1ps

`ifndef NPC_OOO_IF2PAIR_TEST_STALE_REDIRECT
`define NPC_OOO_IF2PAIR_TEST_STALE_REDIRECT 0
`endif

`ifndef BBUS_OOO_DPI_PMEM_PAIR_IMPORTS_SVH
`define BBUS_OOO_DPI_PMEM_PAIR_IMPORTS_SVH
import "DPI-C" function void dpi_pmem_pair_req(
    input int channel,
    input int unsigned addr
);

import "DPI-C" function int dpi_pmem_pair_resp(
    input int channel,
    output longint unsigned data
);
`endif

module ooo_pmem_ifetch_pair #(
    parameter logic [31:0] RESET_VECTOR = 32'h8000_0000,
    parameter int unsigned DPI_CHANNEL = 0
) (
    input  logic clk,
    input  logic reset,

    output logic fetch_valid_o,
    output logic [31:0] fetch_pc_o,
    output logic [31:0] fetch_instr_o,
    output logic fetch1_valid_o,
    output logic [31:0] fetch1_pc_o,
    output logic [31:0] fetch1_instr_o,

    input  logic consume_i,
    input  logic consume2_i,
    input  logic stop_i,
    input  logic redirect_valid_i,
    input  logic [31:0] redirect_pc_i,

    output logic debug_req_valid_o,
    output logic debug_resp_valid_o,
    output logic debug_resp_drop_o,
    output logic debug_stale_resp_kill_o,
    output logic debug_valid_mask_11_o,
    output logic debug_valid_mask_01_o,
    output logic debug_upper_half_single_o,
    output logic debug_slot1_only_bug_o,
    output logic debug_stale_accept_bug_o,
    output logic debug_fetch_endian_bug_o
);
    typedef enum logic [1:0] {
        PAIR_IDLE,
        PAIR_WAIT,
        PAIR_VALID
    } pair_state_e;

    pair_state_e state_q;
    logic [31:0] next_pc_q;
    logic [31:0] req_pc_q;
    logic [31:0] req_base_q;
    logic [1:0] valid_mask_q;
    logic [31:0] pc_q [1:0];
    logic [31:0] instr_q [1:0];
    logic drop_resp_q;
    logic test_stale_redirect_used_q;
    logic [1:0] consume_count_c;
    logic [1:0] mask_after_consume_c;
    logic buffer_empty_after_consume_c;
    logic issue_req_c;
    longint unsigned dpi_pair_data;
    localparam bit TEST_STALE_REDIRECT =
        (`NPC_OOO_IF2PAIR_TEST_STALE_REDIRECT != 0);

    assign fetch_valid_o = valid_mask_q[0] && !stop_i && !redirect_valid_i;
    assign fetch_pc_o = pc_q[0];
    assign fetch_instr_o = instr_q[0];
    assign fetch1_valid_o = valid_mask_q[1] && !stop_i && !redirect_valid_i;
    assign fetch1_pc_o = pc_q[1];
    assign fetch1_instr_o = instr_q[1];

    assign consume_count_c =
        (consume2_i && (valid_mask_q == 2'b11)) ? 2'd2 :
        ((consume_i && valid_mask_q[0]) ? 2'd1 : 2'd0);
    assign mask_after_consume_c =
        (consume_count_c == 2'd2) ? 2'b00 :
        ((consume_count_c == 2'd1) ?
            (valid_mask_q[1] ? 2'b01 : 2'b00) :
            valid_mask_q);
    assign buffer_empty_after_consume_c = (mask_after_consume_c == 2'b00);
    assign issue_req_c =
        (state_q != PAIR_WAIT) &&
        buffer_empty_after_consume_c &&
        !stop_i &&
        !redirect_valid_i;

    always_ff @(posedge clk) begin
        if (reset) begin
            state_q <= PAIR_IDLE;
            next_pc_q <= RESET_VECTOR;
            req_pc_q <= 32'b0;
            req_base_q <= 32'b0;
            valid_mask_q <= 2'b00;
            pc_q[0] <= 32'b0;
            pc_q[1] <= 32'b0;
            instr_q[0] <= 32'b0;
            instr_q[1] <= 32'b0;
            drop_resp_q <= 1'b0;
            test_stale_redirect_used_q <= 1'b0;
            debug_req_valid_o <= 1'b0;
            debug_resp_valid_o <= 1'b0;
            debug_resp_drop_o <= 1'b0;
            debug_stale_resp_kill_o <= 1'b0;
            debug_valid_mask_11_o <= 1'b0;
            debug_valid_mask_01_o <= 1'b0;
            debug_upper_half_single_o <= 1'b0;
            debug_slot1_only_bug_o <= 1'b0;
            debug_stale_accept_bug_o <= 1'b0;
            debug_fetch_endian_bug_o <= 1'b0;
        end else begin
            logic [1:0] next_valid_mask;
            logic [31:0] next_pc0;
            logic [31:0] next_pc1;
            logic [31:0] next_instr0;
            logic [31:0] next_instr1;
            logic [31:0] fetch_pair_base;

            debug_req_valid_o <= 1'b0;
            debug_resp_valid_o <= 1'b0;
            debug_resp_drop_o <= 1'b0;
            debug_stale_resp_kill_o <= 1'b0;
            debug_valid_mask_11_o <= 1'b0;
            debug_valid_mask_01_o <= 1'b0;
            debug_upper_half_single_o <= 1'b0;
            debug_slot1_only_bug_o <= 1'b0;
            debug_stale_accept_bug_o <= 1'b0;
            debug_fetch_endian_bug_o <= 1'b0;

            next_valid_mask = valid_mask_q;
            next_pc0 = pc_q[0];
            next_pc1 = pc_q[1];
            next_instr0 = instr_q[0];
            next_instr1 = instr_q[1];

            if (redirect_valid_i) begin
                valid_mask_q <= 2'b00;
                pc_q[0] <= 32'b0;
                pc_q[1] <= 32'b0;
                instr_q[0] <= 32'b0;
                instr_q[1] <= 32'b0;
                next_pc_q <= redirect_pc_i;
                req_pc_q <= redirect_pc_i;
                drop_resp_q <= (state_q == PAIR_WAIT);
                test_stale_redirect_used_q <= 1'b0;
                state_q <= (state_q == PAIR_WAIT) ? PAIR_WAIT : PAIR_IDLE;
            end else begin
                if (consume_count_c == 2'd2) begin
                    next_valid_mask = 2'b00;
                    next_pc0 = 32'b0;
                    next_pc1 = 32'b0;
                    next_instr0 = 32'b0;
                    next_instr1 = 32'b0;
                end else if (consume_count_c == 2'd1) begin
                    if (valid_mask_q[1]) begin
                        next_valid_mask = 2'b01;
                        next_pc0 = pc_q[1];
                        next_instr0 = instr_q[1];
                        next_pc1 = 32'b0;
                        next_instr1 = 32'b0;
                    end else begin
                        next_valid_mask = 2'b00;
                        next_pc0 = 32'b0;
                        next_pc1 = 32'b0;
                        next_instr0 = 32'b0;
                        next_instr1 = 32'b0;
                    end
                end

                unique case (state_q)
                    PAIR_IDLE, PAIR_VALID: begin
                        valid_mask_q <= next_valid_mask;
                        pc_q[0] <= next_pc0;
                        pc_q[1] <= next_pc1;
                        instr_q[0] <= next_instr0;
                        instr_q[1] <= next_instr1;
                        state_q <= (next_valid_mask == 2'b00) ? PAIR_IDLE : PAIR_VALID;

                        if (issue_req_c) begin
                            fetch_pair_base = {next_pc_q[31:3], 3'b000};
                            // S5D1_SIMPLIFICATION: pair fetch is a DPI PMEM model, not an ICache.
                            // FUTURE: replace with ICache/predictor frontend after IF2 ordering is proven.
                            dpi_pmem_pair_req(int'(DPI_CHANNEL), fetch_pair_base);
                            req_pc_q <= next_pc_q;
                            req_base_q <= fetch_pair_base;
                            state_q <= PAIR_WAIT;
                            debug_req_valid_o <= 1'b1;
                        end
                    end

                    PAIR_WAIT: begin
                        valid_mask_q <= next_valid_mask;
                        pc_q[0] <= next_pc0;
                        pc_q[1] <= next_pc1;
                        instr_q[0] <= next_instr0;
                        instr_q[1] <= next_instr1;
                        if (TEST_STALE_REDIRECT &&
                            !test_stale_redirect_used_q &&
                            !drop_resp_q) begin
                            // S5D1_SIMPLIFICATION: directed-only stale-response probe.
                            // FUTURE: remove this knob when a real ICache can naturally
                            // produce redirect-before-response timing.
                            valid_mask_q <= 2'b00;
                            pc_q[0] <= 32'b0;
                            pc_q[1] <= 32'b0;
                            instr_q[0] <= 32'b0;
                            instr_q[1] <= 32'b0;
                            drop_resp_q <= 1'b1;
                            test_stale_redirect_used_q <= 1'b1;
                        end else if (dpi_pmem_pair_resp(int'(DPI_CHANNEL), dpi_pair_data) != 0) begin
                            debug_resp_valid_o <= 1'b1;
                            if (drop_resp_q) begin
                                // S5D1_SIMPLIFICATION: single outstanding pair response.
                                // FUTURE: keep epoch/seq stale filtering when adding cache latency/MSHR.
                                drop_resp_q <= 1'b0;
                                debug_resp_drop_o <= 1'b1;
                                debug_stale_resp_kill_o <= 1'b1;
                                state_q <= PAIR_IDLE;
                            end else if (next_valid_mask == 2'b00) begin
                                if (req_pc_q[2] == 1'b0) begin
                                    valid_mask_q <= 2'b11;
                                    pc_q[0] <= req_pc_q;
                                    pc_q[1] <= req_pc_q + 32'd4;
                                    instr_q[0] <= dpi_pair_data[31:0];
                                    instr_q[1] <= dpi_pair_data[63:32];
                                    next_pc_q <= req_pc_q + 32'd8;
                                    debug_valid_mask_11_o <= 1'b1;
                                end else begin
                                    // S5D1_SIMPLIFICATION: if fetch_pc[2]==1, v1 emits only slot0 from upper word.
                                    // FUTURE: support cross-boundary pair fill with carry-over buffer or second aligned fetch.
                                    valid_mask_q <= 2'b01;
                                    pc_q[0] <= req_pc_q;
                                    pc_q[1] <= 32'b0;
                                    instr_q[0] <= dpi_pair_data[63:32];
                                    instr_q[1] <= 32'b0;
                                    next_pc_q <= req_pc_q + 32'd4;
                                    debug_valid_mask_01_o <= 1'b1;
                                    debug_upper_half_single_o <= 1'b1;
                                end
                                state_q <= stop_i ? PAIR_IDLE : PAIR_VALID;
                            end else begin
                                debug_stale_accept_bug_o <= 1'b1;
                                state_q <= PAIR_VALID;
                            end
                        end
                    end

                    default: begin
                        state_q <= PAIR_IDLE;
                    end
                endcase

                if (valid_mask_q == 2'b10 || next_valid_mask == 2'b10) begin
                    debug_slot1_only_bug_o <= 1'b1;
                end
            end
        end
    end

    wire req_base_unused = ^req_base_q;
endmodule
