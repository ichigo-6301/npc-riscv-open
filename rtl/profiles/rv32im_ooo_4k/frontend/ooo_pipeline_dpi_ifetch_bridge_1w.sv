`timescale 1ns / 1ps

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

// Ordered four-request production bridge between the P9 raw IF2 frontend and
// the pipelined DPI pair-fetch service. Recovery never resets this bridge; P9
// absorbs flushed responses through its request-epoch contract.
module ooo_pipeline_dpi_ifetch_bridge_1w #(
    parameter int unsigned DPI_CHANNEL = 0,
    parameter bit SAME_EDGE_RESPONSE_CAPTURE_ENABLE = 1'b0
) (
    input  logic clk,
    input  logic reset,

    input  logic req_valid_i,
    output logic req_ready_o,
    input  logic [31:0] req_addr_i,
    input  logic [31:0] req_pc_i,

    output logic rsp_valid_o,
    input  logic rsp_ready_i,
    output logic [31:0] rsp_addr_o,
    output logic [1:0] rsp_valid_mask_o,
    output logic [63:0] rsp_data_o,
    output logic rsp_eof_o,
    output logic rsp_error_o,

    output logic busy_o,
    output logic req_fire_o,
    output logic rsp_capture_o,
    output logic rsp_fire_o,
    output logic [15:0] debug_service_o,
    output logic [31:0] debug_req_pc_o,
    output logic protocol_error_o
);
    logic [31:0] req_addr_q [0:3];
    logic [31:0] req_pc_q [0:3];
    logic [1:0] req_head_q;
    logic [1:0] req_tail_q;
    logic [2:0] req_count_q;
    logic rsp_valid_q;
    logic [31:0] rsp_addr_q;
    logic [31:0] rsp_pc_q;
    logic [63:0] rsp_data_q;
    logic [31:0] req_event_pc_q;
    logic rsp_poll_q;
    logic protocol_error_q;
    longint unsigned dpi_pair_data;

    logic request_legal_c;
    logic request_fire_c;
    logic response_fire_c;
    logic response_slot_available_c;
    logic response_from_new_request_c;
    integer dpi_response_ready;

    assign request_legal_c =
        (req_addr_i[2:0] == 3'b000) &&
        (req_addr_i == {req_pc_i[31:3], 3'b000});
    assign req_ready_o = !reset && request_legal_c && (req_count_q < 3'd4);
    assign request_fire_c = req_valid_i && req_ready_o;

    assign rsp_valid_o = !reset && rsp_valid_q;
    assign rsp_addr_o = rsp_addr_q;
    assign rsp_valid_mask_o = rsp_pc_q[2] ? 2'b01 : 2'b11;
    assign rsp_data_o = rsp_data_q;
    assign rsp_eof_o = 1'b0;
    assign rsp_error_o = 1'b0;
    assign response_fire_c = rsp_valid_o && rsp_ready_i;
    assign response_slot_available_c = !rsp_valid_q || response_fire_c;

    assign busy_o = (req_count_q != 3'd0) || rsp_valid_q;
    assign debug_service_o = {
        protocol_error_o,
        SAME_EDGE_RESPONSE_CAPTURE_ENABLE,
        response_from_new_request_c,
        response_slot_available_c,
        req_count_q,
        request_fire_c,
        response_fire_c,
        rsp_ready_i,
        rsp_valid_o,
        rsp_fire_o,
        rsp_capture_o,
        rsp_poll_q,
        req_fire_o,
        1'b1
    };
    assign debug_req_pc_o = req_event_pc_q;
    assign protocol_error_o = protocol_error_q ||
        (req_valid_i && !request_legal_c);

    always_ff @(posedge clk) begin
        if (reset) begin
            req_head_q <= '0;
            req_tail_q <= '0;
            req_count_q <= '0;
            rsp_valid_q <= 1'b0;
            rsp_addr_q <= '0;
            rsp_pc_q <= '0;
            rsp_data_q <= '0;
            req_event_pc_q <= '0;
            rsp_poll_q <= 1'b0;
            protocol_error_q <= 1'b0;
            req_fire_o <= 1'b0;
            rsp_poll_q <= 1'b0;
            rsp_capture_o <= 1'b0;
            rsp_fire_o <= 1'b0;
        end else begin
            dpi_response_ready = 0;
            req_fire_o <= 1'b0;
            rsp_capture_o <= 1'b0;
            rsp_fire_o <= 1'b0;

            if (req_valid_i && !request_legal_c) begin
                protocol_error_q <= 1'b1;
            end

            if (response_fire_c) begin
                rsp_valid_q <= 1'b0;
                rsp_fire_o <= 1'b1;
            end

            // With the guarded turnaround path enabled, enqueue the DPI
            // request before polling.  A zero-latency service can then be
            // captured on this edge and exposed as a normal registered
            // response during the following cycle.  Feature-off preserves
            // the legacy poll-before-request ordering exactly.
            if (SAME_EDGE_RESPONSE_CAPTURE_ENABLE && request_fire_c) begin
                dpi_pmem_pair_req(int'(DPI_CHANNEL), req_addr_i);
            end

            response_from_new_request_c =
                SAME_EDGE_RESPONSE_CAPTURE_ENABLE && request_fire_c &&
                (req_count_q == 3'd0);
            if (((req_count_q != 3'd0) || response_from_new_request_c) &&
                response_slot_available_c) begin
                rsp_poll_q <= 1'b1;
                dpi_response_ready =
                    dpi_pmem_pair_resp(int'(DPI_CHANNEL), dpi_pair_data);
                if (dpi_response_ready != 0) begin
                    rsp_valid_q <= 1'b1;
                    rsp_addr_q <= response_from_new_request_c ? req_addr_i :
                        req_addr_q[req_head_q];
                    rsp_pc_q <= response_from_new_request_c ? req_pc_i :
                        req_pc_q[req_head_q];
                    rsp_data_q <= dpi_pair_data;
                    req_head_q <= req_head_q + 2'd1;
                    rsp_capture_o <= 1'b1;
                end
            end

            if (request_fire_c) begin
                if (!SAME_EDGE_RESPONSE_CAPTURE_ENABLE) begin
                    dpi_pmem_pair_req(int'(DPI_CHANNEL), req_addr_i);
                end
                req_addr_q[req_tail_q] <= req_addr_i;
                req_pc_q[req_tail_q] <= req_pc_i;
                req_tail_q <= req_tail_q + 2'd1;
                req_event_pc_q <= req_pc_i;
                req_fire_o <= 1'b1;
            end

            unique case ({request_fire_c, (dpi_response_ready != 0)})
                2'b10: req_count_q <= req_count_q + 3'd1;
                2'b01: req_count_q <= req_count_q - 3'd1;
                default: req_count_q <= req_count_q;
            endcase
        end
    end
endmodule
