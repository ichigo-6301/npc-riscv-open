`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

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

module ooo_lsu #(
    parameter int unsigned DPI_CHANNEL = 1
) (
    input  logic clk,
    input  logic reset,

    input  logic issue_valid_i,
    output logic issue_ready_o,
    input  bbus_ooo_lsu_uop_t issue_uop_i,
    input  logic [31:0] base_data_i,
    input  logic [31:0] store_data_i,

    output logic completion_valid_o,
    input  logic completion_ready_i,
    output bbus_ooo_writeback_t completion_wb_o,

    input  logic commit_store_valid_i,
    output logic commit_store_ready_o,
    input  logic [31:0] commit_store_addr_i,
    input  logic [31:0] commit_store_wdata_i,
    input  logic [2:0] commit_store_len_i,
    output logic commit_store_done_o,

    output logic debug_busy_o,
    output logic debug_mem_req_valid_o,
    output logic debug_mem_resp_valid_o
);
    typedef enum logic [1:0] {
        LSU_IDLE,
        LSU_LOAD_WAIT,
        LSU_DONE,
        LSU_STORE_COMMIT_WAIT
    } lsu_state_e;

    lsu_state_e state_q;
    bbus_ooo_writeback_t completion_q;
    logic [31:0] load_addr_q;
    bbus_ooo_mem_op_e load_mem_op_q;
    logic commit_store_done_q;
    int unsigned dpi_rdata;

    logic issue_fire_c;
    logic commit_store_fire_c;
    logic [31:0] addr_c;
    logic [2:0] len_c;
    logic [3:0] wstrb_c;
    logic [31:0] store_wdata_shifted_c;
    logic misaligned_c;
    bbus_ooo_writeback_t issue_completion_c;

    function automatic logic [2:0] mem_len(input bbus_ooo_mem_op_e mem_op);
        begin
            unique case (mem_op)
                BBUS_OOO_MEM_H_S,
                BBUS_OOO_MEM_H_U: mem_len = 3'd2;
                BBUS_OOO_MEM_W:   mem_len = 3'd4;
                default:          mem_len = 3'd1;
            endcase
        end
    endfunction

    function automatic logic [3:0] mem_mask(input logic [2:0] len);
        begin
            unique case (len)
                3'd1:   mem_mask = 4'b0001;
                3'd2:   mem_mask = 4'b0011;
                default: mem_mask = 4'b1111;
            endcase
        end
    endfunction

    function automatic logic mem_misaligned(input bbus_ooo_mem_op_e mem_op, input logic [31:0] addr);
        begin
            unique case (mem_op)
                BBUS_OOO_MEM_H_S,
                BBUS_OOO_MEM_H_U: mem_misaligned = addr[0];
                BBUS_OOO_MEM_W:   mem_misaligned = (addr[1:0] != 2'b00);
                default:          mem_misaligned = 1'b0;
            endcase
        end
    endfunction

    function automatic logic [31:0] extend_load(
        input bbus_ooo_mem_op_e mem_op,
        input logic [31:0] data
    );
        begin
            unique case (mem_op)
                BBUS_OOO_MEM_B_S: extend_load = {{24{data[7]}}, data[7:0]};
                BBUS_OOO_MEM_H_S: extend_load = {{16{data[15]}}, data[15:0]};
                BBUS_OOO_MEM_B_U: extend_load = {24'b0, data[7:0]};
                BBUS_OOO_MEM_H_U: extend_load = {16'b0, data[15:0]};
                default:          extend_load = data;
            endcase
        end
    endfunction

    assign issue_ready_o =
        (state_q == LSU_IDLE) &&
        !commit_store_valid_i &&
        !commit_store_done_q;
    assign commit_store_ready_o =
        (state_q == LSU_IDLE) &&
        !commit_store_done_q;
    assign issue_fire_c = issue_valid_i && issue_ready_o && issue_uop_i.valid;
    assign commit_store_fire_c = commit_store_valid_i && commit_store_ready_o;
    assign completion_valid_o = (state_q == LSU_DONE);
    assign completion_wb_o = completion_q;
    assign commit_store_done_o = commit_store_done_q;
    assign debug_busy_o = (state_q != LSU_IDLE);

    assign addr_c = base_data_i + issue_uop_i.imm;
    assign len_c = mem_len(issue_uop_i.mem_op);
    assign wstrb_c = mem_mask(len_c) << addr_c[1:0];
    assign store_wdata_shifted_c = store_data_i << {addr_c[1:0], 3'b000};
    assign misaligned_c = mem_misaligned(issue_uop_i.mem_op, addr_c);

    always_comb begin
        issue_completion_c = '0;
        issue_completion_c.valid = issue_uop_i.valid;
        issue_completion_c.rob_tag = issue_uop_i.rob_tag;
        issue_completion_c.phys_rd = issue_uop_i.phys_rd;
        issue_completion_c.rf_wen = issue_uop_i.rf_wen && issue_uop_i.is_load;
        issue_completion_c.done = 1'b1;
        issue_completion_c.is_load = issue_uop_i.is_load;
        issue_completion_c.is_store = issue_uop_i.is_store;
        issue_completion_c.mem_op = issue_uop_i.mem_op;
        issue_completion_c.mem_addr = addr_c;
        issue_completion_c.mem_wdata = store_wdata_shifted_c;
        issue_completion_c.mem_wstrb = wstrb_c;
        issue_completion_c.mem_len = len_c;
        if (misaligned_c) begin
            issue_completion_c.exception.valid = 1'b1;
            issue_completion_c.exception.cause = issue_uop_i.is_store ? 32'd6 : 32'd4;
            issue_completion_c.exception.tval = addr_c;
            issue_completion_c.rf_wen = 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state_q <= LSU_IDLE;
            completion_q <= '0;
            load_addr_q <= 32'b0;
            load_mem_op_q <= BBUS_OOO_MEM_NONE;
            commit_store_done_q <= 1'b0;
            debug_mem_req_valid_o <= 1'b0;
            debug_mem_resp_valid_o <= 1'b0;
        end else begin
            commit_store_done_q <= 1'b0;
            debug_mem_req_valid_o <= 1'b0;
            debug_mem_resp_valid_o <= 1'b0;

            unique case (state_q)
                LSU_IDLE: begin
                    completion_q <= '0;
                    if (commit_store_fire_c) begin
                        dpi_pmem_req(
                            int'(DPI_CHANNEL),
                            1,
                            commit_store_addr_i,
                            int'(commit_store_len_i),
                            commit_store_wdata_i
                        );
                        debug_mem_req_valid_o <= 1'b1;
                        state_q <= LSU_STORE_COMMIT_WAIT;
                    end else if (issue_fire_c) begin
                        if (misaligned_c || issue_uop_i.is_store) begin
                            completion_q <= issue_completion_c;
                            state_q <= LSU_DONE;
                        end else begin
                            dpi_pmem_req(int'(DPI_CHANNEL), 0, addr_c, int'(len_c), 32'b0);
                            load_addr_q <= addr_c;
                            load_mem_op_q <= issue_uop_i.mem_op;
                            completion_q <= issue_completion_c;
                            debug_mem_req_valid_o <= 1'b1;
                            state_q <= LSU_LOAD_WAIT;
                        end
                    end
                end

                LSU_LOAD_WAIT: begin
                    if (dpi_pmem_resp(int'(DPI_CHANNEL), dpi_rdata) != 0) begin
                        completion_q.result <= extend_load(
                            load_mem_op_q,
                            32'(dpi_rdata) >> {load_addr_q[1:0], 3'b000}
                        );
                        debug_mem_resp_valid_o <= 1'b1;
                        state_q <= LSU_DONE;
                    end
                end

                LSU_DONE: begin
                    if (completion_ready_i) begin
                        completion_q <= '0;
                        state_q <= LSU_IDLE;
                    end
                end

                LSU_STORE_COMMIT_WAIT: begin
                    if (dpi_pmem_resp(int'(DPI_CHANNEL), dpi_rdata) != 0) begin
                        commit_store_done_q <= 1'b1;
                        debug_mem_resp_valid_o <= 1'b1;
                        state_q <= LSU_IDLE;
                    end
                end

                default: begin
                    state_q <= LSU_IDLE;
                    completion_q <= '0;
                end
            endcase
        end
    end
endmodule
