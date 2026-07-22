`timescale 1ns / 1ps

`ifndef BBUS_OOO_DPI_PMEM_IMPORTS_SVH
`define BBUS_OOO_DPI_PMEM_IMPORTS_SVH
import "DPI-C" function void dpi_pmem_req(
    input int channel,
    input int is_write,
    input int unsigned addr,
    input int len,
    input int unsigned data
);

import "DPI-C" function int dpi_pmem_resp(
    input int channel,
    output int unsigned data
);
`endif

// One-outstanding production bridge for P4's decoupled LSU port. The DPI
// service owns actual memory timing; this bridge only turns polling into a
// stable valid/ready response packet.
module ooo_pipeline_dpi_mem_bridge_1w #(
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

    output logic rsp_valid_o,
    input  logic rsp_ready_i,
    output logic [31:0] rsp_rdata_o,
    output logic rsp_error_o,

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
    logic [31:0] rsp_rdata_q;
    logic protocol_error_q;
    int unsigned dpi_rdata;

    logic len_legal_c;
    logic request_fire_c;
    logic response_fire_c;

    assign len_legal_c =
        (req_len_i == 3'd1) || (req_len_i == 3'd2) ||
        (req_len_i == 3'd4);
    assign req_ready_o = !reset && (state_q == MEM_IDLE) && len_legal_c;
    assign request_fire_c = req_valid_i && req_ready_o;

    assign rsp_valid_o = !reset && (state_q == MEM_RESPONSE);
    assign rsp_rdata_o = rsp_rdata_q;
    assign rsp_error_o = 1'b0;
    assign response_fire_c = rsp_valid_o && rsp_ready_i;

    assign busy_o = (state_q != MEM_IDLE);
    assign protocol_error_o = protocol_error_q ||
        (req_valid_i && !len_legal_c);

    always_ff @(posedge clk) begin
        if (reset) begin
            state_q <= MEM_IDLE;
            rsp_rdata_q <= '0;
            protocol_error_q <= 1'b0;
            req_fire_o <= 1'b0;
            rsp_capture_o <= 1'b0;
            rsp_fire_o <= 1'b0;
        end else begin
            req_fire_o <= 1'b0;
            rsp_capture_o <= 1'b0;
            rsp_fire_o <= 1'b0;

            if (req_valid_i && !len_legal_c) begin
                protocol_error_q <= 1'b1;
            end

            unique case (state_q)
                MEM_IDLE: begin
                    if (request_fire_c) begin
                        dpi_pmem_req(
                            int'(DPI_CHANNEL),
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
                    if (dpi_pmem_resp(int'(DPI_CHANNEL), dpi_rdata) != 0) begin
                        rsp_rdata_q <= dpi_rdata;
                        rsp_capture_o <= 1'b1;
                        state_q <= MEM_RESPONSE;
                    end
                end

                MEM_RESPONSE: begin
                    if (response_fire_c) begin
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
