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

// Tagged one-outstanding DPI memory bridge.
//
// This checkpoint deliberately retains the existing one-request capacity.  It
// establishes the end-to-end tagged DPI ABI and a stable response packet so a
// later bridge can increase capacity without changing token semantics.
module ooo_pipeline_tagged_dpi_mem_bridge_1w #(
    parameter int unsigned DPI_CHANNEL = 1
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

    output logic rsp_valid_o,
    input  logic rsp_ready_i,
    output logic [31:0] rsp_rdata_o,
    output logic rsp_error_o,
    output bbus_ooo_mem_token_t rsp_token_o,

    output logic busy_o,
    output logic req_fire_o,
    output logic rsp_capture_o,
    output logic rsp_fire_o,
    output logic protocol_error_o
);
    typedef enum logic [1:0] {
        MEM_IDLE,
        MEM_WAIT,
        MEM_RESPONSE
    } mem_state_e;

    mem_state_e state_q;
    bbus_ooo_mem_token_t request_token_q;
    bbus_ooo_mem_token_t response_token_q;
    logic [31:0] response_data_q;
    logic response_error_q;
    logic protocol_error_q;

    int dpi_client;
    int dpi_slot;
    int unsigned dpi_generation;
    int unsigned dpi_epoch;
    int unsigned dpi_data;
    int dpi_error;

    logic len_legal_c;
    logic request_fire_c;
    logic response_fire_c;

    assign len_legal_c =
        (req_len_i == 3'd1) || (req_len_i == 3'd2) ||
        (req_len_i == 3'd4);
    assign req_ready_o = !reset && (state_q == MEM_IDLE) &&
        len_legal_c && req_token_i.valid;
    assign request_fire_c = req_valid_i && req_ready_o;

    assign rsp_valid_o = !reset && (state_q == MEM_RESPONSE);
    assign rsp_rdata_o = response_data_q;
    assign rsp_error_o = response_error_q;
    assign rsp_token_o = response_token_q;
    assign response_fire_c = rsp_valid_o && rsp_ready_i;

    assign busy_o = (state_q != MEM_IDLE);
    assign protocol_error_o = protocol_error_q ||
        (req_valid_i && (!len_legal_c || !req_token_i.valid));

    always_ff @(posedge clk) begin
        if (reset) begin
            state_q <= MEM_IDLE;
            request_token_q <= '0;
            response_token_q <= '0;
            response_data_q <= '0;
            response_error_q <= 1'b0;
            protocol_error_q <= 1'b0;
            req_fire_o <= 1'b0;
            rsp_capture_o <= 1'b0;
            rsp_fire_o <= 1'b0;
        end else begin
            req_fire_o <= 1'b0;
            rsp_capture_o <= 1'b0;
            rsp_fire_o <= 1'b0;

            if (req_valid_i && (!len_legal_c || !req_token_i.valid))
                protocol_error_q <= 1'b1;

            unique case (state_q)
                MEM_IDLE: begin
                    if (request_fire_c) begin
                        request_token_q <= req_token_i;
                        dpi_pmem_tagged_req(
                            int'(DPI_CHANNEL),
                            int'(req_token_i.client),
                            int'(req_token_i.slot),
                            req_token_i.generation,
                            req_token_i.recovery_epoch,
                            req_write_i ? 1 : 0,
                            req_addr_i,
                            int'(req_len_i),
                            req_wdata_i
                        );
                        req_fire_o <= 1'b1;
                        state_q <= MEM_WAIT;
                    end
                end

                MEM_WAIT: begin
                    if (dpi_pmem_tagged_resp(
                        int'(DPI_CHANNEL), dpi_client, dpi_slot,
                        dpi_generation, dpi_epoch, dpi_data, dpi_error
                    ) != 0) begin
                        response_token_q.valid <= 1'b1;
                        response_token_q.client <=
                            bbus_ooo_mem_client_e'(dpi_client);
                        response_token_q.slot <= dpi_slot[1:0];
                        response_token_q.generation <= dpi_generation;
                        response_token_q.recovery_epoch <= dpi_epoch;
                        response_data_q <= dpi_data;
                        response_error_q <= (dpi_error != 0);
                        rsp_capture_o <= 1'b1;
                        if ((dpi_client != int'(request_token_q.client)) ||
                            (dpi_slot != int'(request_token_q.slot)) ||
                            (dpi_generation != request_token_q.generation) ||
                            (dpi_epoch != request_token_q.recovery_epoch))
                            protocol_error_q <= 1'b1;
                        state_q <= MEM_RESPONSE;
                    end
                end

                MEM_RESPONSE: begin
                    if (response_fire_c) begin
                        response_token_q <= '0;
                        response_error_q <= 1'b0;
                        rsp_fire_o <= 1'b1;
                        state_q <= MEM_IDLE;
                    end
                end

                default: begin
                    state_q <= MEM_IDLE;
                    protocol_error_q <= 1'b1;
                end
            endcase
        end
    end

    /* verilator lint_off UNUSED */
    wire req_wstrb_unused = ^req_wstrb_i;
    /* verilator lint_on UNUSED */
endmodule
