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

module ooo_pmem_ifetch #(
    parameter logic [31:0] RESET_VECTOR = 32'h8000_0000,
    parameter int unsigned DPI_CHANNEL = 0
) (
    input  logic clk,
    input  logic reset,

    output logic fetch_valid_o,
    output logic [31:0] fetch_pc_o,
    output logic [31:0] fetch_instr_o,
    input  logic fetch_ready_i,

    input  logic stop_i,
    input  logic redirect_valid_i,
    input  logic [31:0] redirect_pc_i,

    output logic debug_req_valid_o,
    output logic debug_resp_valid_o,
    output logic [31:0] debug_fetch_pc_o
);
    typedef enum logic [1:0] {
        FETCH_IDLE,
        FETCH_WAIT,
        FETCH_VALID
    } fetch_state_e;

    fetch_state_e state_q;
    logic [31:0] next_pc_q;
    logic [31:0] req_pc_q;
    logic [31:0] instr_q;
    logic drop_resp_q;
    logic [31:0] sequential_next_pc;
    int unsigned dpi_rdata;

    assign fetch_valid_o = (state_q == FETCH_VALID) && !stop_i && !redirect_valid_i;
    assign fetch_pc_o = req_pc_q;
    assign fetch_instr_o = instr_q;
    assign debug_fetch_pc_o = next_pc_q;
    assign sequential_next_pc = req_pc_q + 32'd4;

    always_ff @(posedge clk) begin
        if (reset) begin
            state_q <= FETCH_IDLE;
            next_pc_q <= RESET_VECTOR;
            req_pc_q <= 32'b0;
            instr_q <= 32'b0;
            drop_resp_q <= 1'b0;
            debug_req_valid_o <= 1'b0;
            debug_resp_valid_o <= 1'b0;
        end else begin
            debug_req_valid_o <= 1'b0;
            debug_resp_valid_o <= 1'b0;

            if (redirect_valid_i) begin
                next_pc_q <= redirect_pc_i;
                req_pc_q <= redirect_pc_i;
                instr_q <= 32'b0;
                drop_resp_q <= (state_q == FETCH_WAIT);
                state_q <= (state_q == FETCH_WAIT) ? FETCH_WAIT : FETCH_IDLE;
            end else begin
                unique case (state_q)
                    FETCH_IDLE: begin
                        if (!stop_i && fetch_ready_i) begin
                            dpi_pmem_req(int'(DPI_CHANNEL), 0, next_pc_q, 4, 32'b0);
                            req_pc_q <= next_pc_q;
                            state_q <= FETCH_WAIT;
                            debug_req_valid_o <= 1'b1;
                        end
                    end

                    FETCH_WAIT: begin
                        if (dpi_pmem_resp(int'(DPI_CHANNEL), dpi_rdata) != 0) begin
                            debug_resp_valid_o <= 1'b1;
                            if (drop_resp_q) begin
                                drop_resp_q <= 1'b0;
                                state_q <= FETCH_IDLE;
                            end else begin
                                instr_q <= dpi_rdata;
                                state_q <= stop_i ? FETCH_IDLE : FETCH_VALID;
                            end
                        end
                    end

                    FETCH_VALID: begin
                        if (stop_i) begin
                            state_q <= FETCH_IDLE;
                        end else if (fetch_ready_i) begin
                            dpi_pmem_req(int'(DPI_CHANNEL), 0, sequential_next_pc, 4, 32'b0);
                            next_pc_q <= sequential_next_pc;
                            req_pc_q <= sequential_next_pc;
                            state_q <= FETCH_WAIT;
                            debug_req_valid_o <= 1'b1;
                        end
                    end

                    default: begin
                        state_q <= FETCH_IDLE;
                    end
                endcase
            end
        end
    end
endmodule
