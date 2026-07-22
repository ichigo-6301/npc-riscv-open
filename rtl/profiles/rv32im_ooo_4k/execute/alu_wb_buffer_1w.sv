`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module alu_wb_buffer_1w (
    input  logic clk,
    input  logic reset,
    input  logic flush_i,
    input  logic selective_kill_valid_i,
    input  logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_i,
    output logic selective_kill_drop_o,

    input  bbus_ooo_writeback_t in_wb_i,
    input  logic in_valid_i,
    output logic in_ready_o,

    output bbus_ooo_writeback_t out_wb_o,
    output logic out_valid_o,
    input  logic out_accepted_i,
    input  logic out_drop_i,

    output logic debug_full_o
);
    bbus_ooo_writeback_t wb_q;
    logic full_q;
    logic resident_killed_c;

    assign resident_killed_c = selective_kill_valid_i && full_q &&
        wb_q.rob_tag.valid && selective_killed_rob_mask_i[wb_q.rob_tag.idx];
    assign selective_kill_drop_o = resident_killed_c;
    assign in_ready_o = !selective_kill_valid_i &&
        (!full_q || out_accepted_i || out_drop_i);
    assign out_wb_o = wb_q;
    assign out_valid_o = !selective_kill_valid_i && full_q;
    assign debug_full_o = full_q;

    always_ff @(posedge clk) begin
        if (reset || flush_i) begin
            wb_q <= '0;
            full_q <= 1'b0;
        end else if (selective_kill_valid_i) begin
            if (resident_killed_c) begin
                wb_q <= '0;
                full_q <= 1'b0;
            end
        end else begin
            if (in_valid_i && in_ready_o) begin
                wb_q <= in_wb_i;
                full_q <= 1'b1;
            end else if (out_accepted_i || out_drop_i) begin
                wb_q <= '0;
                full_q <= 1'b0;
            end
        end
    end
endmodule
