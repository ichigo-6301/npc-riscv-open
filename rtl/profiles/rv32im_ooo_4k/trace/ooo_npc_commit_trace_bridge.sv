`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_npc_commit_trace_bridge #(
    parameter bit DUAL_TRACE_SINK_ENABLE = 1'b0
) (
    input  logic clk,
    input  logic reset,

    input  logic trace_valid_i,
    input  logic trace_ready_i,
    input  bbus_ooo_commit_trace_packet_t trace_packet_i,
    input  logic trace1_valid_i,
    input  bbus_ooo_commit_trace_packet_t trace_packet1_i,

    output logic commit_valid_o,
    output logic [1:0] commit_mask_o,
    output logic commit_slot1_o,
    output logic [31:0] commit_pc_o,
    output logic [31:0] commit_instr_o,
    output logic [31:0] commit_nextpc_o,
    output logic commit_rf_wen_o,
    output bbus_ooo_arch_reg_t commit_rd_o,
    output logic [31:0] commit_wdata_o,
    output logic commit_is_load_o,
    output logic commit_is_store_o,
    output logic commit_is_branch_o,
    output logic commit_is_jal_o,
    output logic commit_is_jalr_o,
    output logic [31:0] commit_mem_addr_o,
    output logic [31:0] commit_mem_wdata_o,
    output logic [3:0] commit_mem_wstrb_o,
    output logic [2:0] commit_mem_len_o,
    output logic commit_unsupported_o,
    output logic commit_exception_valid_o,
    output logic commit1_valid_o,
    output bbus_ooo_commit_trace_packet_t commit1_packet_o,
    output logic debug_lane1_without_lane0_o
);
    logic trace_fire;
    logic accepted_commit_fire;
    logic normal_commit_fire;
    logic trace1_fire;
    logic accepted_commit1_fire;

    assign trace_fire = trace_valid_i && trace_ready_i && trace_packet_i.valid;
    assign accepted_commit_fire =
        trace_fire &&
        !trace_packet_i.unsupported;
    assign normal_commit_fire =
        accepted_commit_fire && !trace_packet_i.exception_valid;
    assign trace1_fire = DUAL_TRACE_SINK_ENABLE && trace1_valid_i &&
        trace_ready_i && trace_packet1_i.valid;
    assign accepted_commit1_fire = trace1_fire &&
        !trace_packet1_i.unsupported;
    assign debug_lane1_without_lane0_o =
        accepted_commit1_fire && !accepted_commit_fire;

    always_ff @(posedge clk) begin
        if (reset) begin
            commit_valid_o <= 1'b0;
            commit_mask_o <= 2'b0;
            commit_slot1_o <= 1'b0;
            commit_pc_o <= 32'b0;
            commit_instr_o <= 32'b0;
            commit_nextpc_o <= 32'b0;
            commit_rf_wen_o <= 1'b0;
            commit_rd_o <= bbus_ooo_arch_reg_t'(5'd0);
            commit_wdata_o <= 32'b0;
            commit_is_load_o <= 1'b0;
            commit_is_store_o <= 1'b0;
            commit_is_branch_o <= 1'b0;
            commit_is_jal_o <= 1'b0;
            commit_is_jalr_o <= 1'b0;
            commit_mem_addr_o <= 32'b0;
            commit_mem_wdata_o <= 32'b0;
            commit_mem_wstrb_o <= 4'b0;
            commit_mem_len_o <= 3'b0;
            commit_unsupported_o <= 1'b0;
            commit_exception_valid_o <= 1'b0;
            commit1_valid_o <= 1'b0;
            commit1_packet_o <= '0;
        end else begin
            commit_valid_o <= accepted_commit_fire;
            commit_mask_o <= trace_fire ? trace_packet_i.commit_mask : 2'b0;
            commit_slot1_o <= trace_fire && trace_packet_i.commit_slot1;
            commit_pc_o <= trace_fire ? trace_packet_i.pc : 32'b0;
            commit_instr_o <= trace_fire ? trace_packet_i.instr : 32'b0;
            commit_nextpc_o <= trace_fire ? trace_packet_i.commit_nextpc : 32'b0;
            commit_rf_wen_o <=
                normal_commit_fire &&
                trace_packet_i.rf_wen &&
                (trace_packet_i.arch_rd != bbus_ooo_arch_reg_t'(5'd0));
            commit_rd_o <= trace_fire ? trace_packet_i.arch_rd : bbus_ooo_arch_reg_t'(5'd0);
            commit_wdata_o <= trace_fire ? trace_packet_i.wdata : 32'b0;
            commit_is_load_o <= trace_fire && trace_packet_i.is_load;
            commit_is_store_o <= trace_fire && trace_packet_i.is_store;
            commit_is_branch_o <= trace_fire && trace_packet_i.is_branch;
            commit_is_jal_o <= trace_fire && trace_packet_i.is_jal;
            commit_is_jalr_o <= trace_fire && trace_packet_i.is_jalr;
            commit_mem_addr_o <= trace_fire ? trace_packet_i.mem_addr : 32'b0;
            commit_mem_wdata_o <= trace_fire ? trace_packet_i.mem_wdata : 32'b0;
            commit_mem_wstrb_o <= trace_fire ? trace_packet_i.mem_wstrb : 4'b0;
            commit_mem_len_o <= trace_fire ? trace_packet_i.mem_len : 3'b0;
            commit_unsupported_o <= trace_fire && trace_packet_i.unsupported;
            commit_exception_valid_o <= trace_fire && trace_packet_i.exception_valid;
            commit1_valid_o <= accepted_commit1_fire;
            commit1_packet_o <= trace1_fire ? trace_packet1_i : '0;
            commit1_packet_o.valid <= accepted_commit1_fire;
            commit1_packet_o.rf_wen <=
                accepted_commit1_fire &&
                !trace_packet1_i.exception_valid &&
                trace_packet1_i.rf_wen &&
                (trace_packet1_i.arch_rd != bbus_ooo_arch_reg_t'(5'd0));
        end
    end
endmodule
