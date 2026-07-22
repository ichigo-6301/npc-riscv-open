`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_shadow_arch_state #(
    parameter logic [31:0] RESET_VECTOR = 32'h8000_0000,
    parameter bit DUAL_COMMIT_ENABLE = 1'b0
) (
    input  logic clk,
    input  logic reset,

    input  logic commit_valid_i,
    input  logic [31:0] commit_nextpc_i,
    input  logic commit_rf_wen_i,
    input  bbus_ooo_arch_reg_t commit_rd_i,
    input  logic [31:0] commit_wdata_i,
    input  logic commit1_valid_i,
    input  logic [31:0] commit1_nextpc_i,
    input  logic commit1_rf_wen_i,
    input  bbus_ooo_arch_reg_t commit1_rd_i,
    input  logic [31:0] commit1_wdata_i,

    input  bbus_ooo_arch_reg_t debug_arch_idx_i,
    output logic [31:0] debug_arch_gpr_o,
    output logic [31:0] debug_arch_pc_o
);
    logic [31:0] arch_gpr_q [`BBUS_OOO_ARCH_REGS-1:0];
    logic [31:0] arch_pc_q;

    assign debug_arch_gpr_o =
        (debug_arch_idx_i == bbus_ooo_arch_reg_t'(5'd0)) ? 32'b0 : arch_gpr_q[debug_arch_idx_i];
    assign debug_arch_pc_o = arch_pc_q;

    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < `BBUS_OOO_ARCH_REGS; i = i + 1) begin
                arch_gpr_q[i] <= 32'(i);
            end
            arch_gpr_q[0] <= 32'b0;
            arch_pc_q <= RESET_VECTOR;
        end else begin
            if (commit_valid_i) begin
                arch_pc_q <= commit_nextpc_i;
                if (commit_rf_wen_i && (commit_rd_i != bbus_ooo_arch_reg_t'(5'd0))) begin
                    arch_gpr_q[commit_rd_i] <= commit_wdata_i;
                end
            end
            if (DUAL_COMMIT_ENABLE && commit1_valid_i) begin
                arch_pc_q <= commit1_nextpc_i;
                if (commit1_rf_wen_i &&
                    (commit1_rd_i != bbus_ooo_arch_reg_t'(5'd0))) begin
                    arch_gpr_q[commit1_rd_i] <= commit1_wdata_i;
                end
            end
            arch_gpr_q[0] <= 32'b0;
        end
    end
endmodule
