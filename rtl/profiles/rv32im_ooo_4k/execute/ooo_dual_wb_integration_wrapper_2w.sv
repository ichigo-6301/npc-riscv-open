`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_dual_wb_integration_wrapper_2w (
    input  logic clk,
    input  logic reset,

    input  bbus_ooo_writeback_t wb0_i,
    input  bbus_ooo_writeback_t wb1_i,

    input  logic wb0_rob_match_i,
    input  logic wb1_rob_match_i,
    input  logic wb0_killed_i,
    input  logic wb1_killed_i,

    input  logic lane0_consumer_block_i,
    input  logic lane1_consumer_block_i,
    input  logic lane1_buffer_full_i,
    input  logic lane1_ordering_block_i,

    output logic [1:0] raw_accept_mask_o,
    output logic [1:0] source_accept_mask_o,
    output logic [1:0] final_accept_mask_o,
    output logic [1:0] hold_mask_o,

    output bbus_ooo_writeback_t wb0_final_o,
    output bbus_ooo_writeback_t wb1_final_o,

    output logic [1:0] ordinary_wakeup_valid_final_o,
    output bbus_ooo_phys_reg_t wakeup_phys0_final_o,
    output bbus_ooo_phys_reg_t wakeup_phys1_final_o,

    output logic held_valid_o,
    output bbus_ooo_writeback_t held_wb_o,

    output logic dual_wb_raw_fire_o,
    output logic dual_wb_final_fire_o,
    output logic lane1_hold_o,
    output logic lane1_replay_o,
    output logic duplicate_phys_hold_o,
    output logic duplicate_rob_tag_hold_o,
    output logic lane0_block_hold_o,
    output logic lane1_consumer_block_hold_o,
    output logic lane1_buffer_full_hold_o,
    output logic lane1_ordering_block_hold_o,
    output logic held_blocked_o,
    output logic stale_drop0_o,
    output logic stale_drop1_o,
    output logic killed_drop0_o,
    output logic killed_drop1_o,
    output logic exception_no_wakeup0_o,
    output logic exception_no_wakeup1_o,
    output logic p0_wakeup_suppressed0_o,
    output logic p0_wakeup_suppressed1_o,
    output logic atomicity_mask_valid_o
);
    bbus_ooo_writeback_t wb0_raw;
    bbus_ooo_writeback_t wb1_raw;
    logic [1:0] ordinary_wakeup_valid_raw;
    bbus_ooo_phys_reg_t wakeup_phys0_raw;
    bbus_ooo_phys_reg_t wakeup_phys1_raw;
    logic dual_wakeup_fire_raw;
    logic duplicate_phys_bug_raw;
    logic duplicate_rob_tag_bug_raw;

    logic hold0_c;
    logic hold1_c;
    logic held_blocked_c;

    bbus_ooo_writeback_t held_wb_q;
    logic held_valid_q;

    ooo_dual_wb_bundle_2w u_raw_bundle (
        .clk(clk),
        .reset(reset),
        .wb0_i(wb0_i),
        .wb1_i(wb1_i),
        .wb0_rob_match_i(wb0_rob_match_i),
        .wb1_rob_match_i(wb1_rob_match_i),
        .wb0_killed_i(wb0_killed_i),
        .wb1_killed_i(wb1_killed_i),
        .wb_accept_mask_o(raw_accept_mask_o),
        .wb0_o(wb0_raw),
        .wb1_o(wb1_raw),
        .ordinary_wakeup_valid_o(ordinary_wakeup_valid_raw),
        .wakeup_phys0_o(wakeup_phys0_raw),
        .wakeup_phys1_o(wakeup_phys1_raw),
        .dual_wb_fire_o(dual_wb_raw_fire_o),
        .dual_wakeup_fire_o(dual_wakeup_fire_raw),
        .duplicate_phys_bug_o(duplicate_phys_bug_raw),
        .duplicate_rob_tag_bug_o(duplicate_rob_tag_bug_raw),
        .stale_drop0_o(stale_drop0_o),
        .stale_drop1_o(stale_drop1_o),
        .killed_drop0_o(killed_drop0_o),
        .killed_drop1_o(killed_drop1_o),
        .exception_no_wakeup0_o(exception_no_wakeup0_o),
        .exception_no_wakeup1_o(exception_no_wakeup1_o),
        .p0_wakeup_suppressed0_o(p0_wakeup_suppressed0_o),
        .p0_wakeup_suppressed1_o(p0_wakeup_suppressed1_o)
    );

    function automatic logic ordinary_wakeup(input bbus_ooo_writeback_t wb);
        begin
            ordinary_wakeup =
                wb.valid &&
                wb.rf_wen &&
                (wb.phys_rd != `BBUS_OOO_PHYS_ZERO) &&
                !wb.exception.valid;
        end
    endfunction

    assign hold0_c = lane0_consumer_block_i && (raw_accept_mask_o != 2'b00);
    assign hold1_c =
        raw_accept_mask_o[1] &&
        !hold0_c &&
        (duplicate_phys_bug_raw ||
         duplicate_rob_tag_bug_raw ||
         lane1_consumer_block_i ||
         lane1_buffer_full_i ||
         lane1_ordering_block_i);
    assign held_blocked_c =
        lane0_consumer_block_i ||
        lane1_consumer_block_i ||
        lane1_buffer_full_i ||
        lane1_ordering_block_i;

    assign held_valid_o = held_valid_q;
    assign held_wb_o = held_wb_q;
    assign source_accept_mask_o =
        held_valid_q ? 2'b00 :
        hold0_c ? 2'b00 :
        {wb1_i.valid, wb0_i.valid};

    always_ff @(posedge clk) begin
        if (reset) begin
            final_accept_mask_o <= 2'b00;
            hold_mask_o <= 2'b00;
            wb0_final_o <= '0;
            wb1_final_o <= '0;
            ordinary_wakeup_valid_final_o <= 2'b00;
            wakeup_phys0_final_o <= `BBUS_OOO_PHYS_ZERO;
            wakeup_phys1_final_o <= `BBUS_OOO_PHYS_ZERO;
            held_valid_q <= 1'b0;
            held_wb_q <= '0;
            dual_wb_final_fire_o <= 1'b0;
            lane1_hold_o <= 1'b0;
            lane1_replay_o <= 1'b0;
            duplicate_phys_hold_o <= 1'b0;
            duplicate_rob_tag_hold_o <= 1'b0;
            lane0_block_hold_o <= 1'b0;
            lane1_consumer_block_hold_o <= 1'b0;
            lane1_buffer_full_hold_o <= 1'b0;
            lane1_ordering_block_hold_o <= 1'b0;
            held_blocked_o <= 1'b0;
            atomicity_mask_valid_o <= 1'b0;
        end else begin
            final_accept_mask_o <= 2'b00;
            hold_mask_o <= 2'b00;
            wb0_final_o <= '0;
            wb1_final_o <= '0;
            ordinary_wakeup_valid_final_o <= 2'b00;
            wakeup_phys0_final_o <= `BBUS_OOO_PHYS_ZERO;
            wakeup_phys1_final_o <= `BBUS_OOO_PHYS_ZERO;
            dual_wb_final_fire_o <= 1'b0;
            lane1_hold_o <= 1'b0;
            lane1_replay_o <= 1'b0;
            duplicate_phys_hold_o <= 1'b0;
            duplicate_rob_tag_hold_o <= 1'b0;
            lane0_block_hold_o <= 1'b0;
            lane1_consumer_block_hold_o <= 1'b0;
            lane1_buffer_full_hold_o <= 1'b0;
            lane1_ordering_block_hold_o <= 1'b0;
            held_blocked_o <= 1'b0;
            atomicity_mask_valid_o <= 1'b1;

            if (held_valid_q) begin
                if (held_blocked_c) begin
                    hold_mask_o <= 2'b10;
                    held_blocked_o <= 1'b1;
                    lane0_block_hold_o <= lane0_consumer_block_i;
                    lane1_consumer_block_hold_o <= lane1_consumer_block_i;
                    lane1_buffer_full_hold_o <= lane1_buffer_full_i;
                    lane1_ordering_block_hold_o <= lane1_ordering_block_i;
                end else begin
                    final_accept_mask_o <= 2'b10;
                    wb1_final_o <= held_wb_q;
                    ordinary_wakeup_valid_final_o[1] <= ordinary_wakeup(held_wb_q);
                    wakeup_phys1_final_o <= ordinary_wakeup(held_wb_q) ?
                        held_wb_q.phys_rd : `BBUS_OOO_PHYS_ZERO;
                    held_valid_q <= 1'b0;
                    held_wb_q <= '0;
                    lane1_replay_o <= 1'b1;
                end
            end else begin
                if (hold0_c) begin
                    final_accept_mask_o <= 2'b00;
                    hold_mask_o <= raw_accept_mask_o;
                    lane0_block_hold_o <= 1'b1;
                end else begin
                    final_accept_mask_o[0] <= raw_accept_mask_o[0];
                    final_accept_mask_o[1] <= raw_accept_mask_o[1] && !hold1_c;
                    hold_mask_o[1] <= raw_accept_mask_o[1] && hold1_c;
                    wb0_final_o <= raw_accept_mask_o[0] ? wb0_raw : '0;
                    wb1_final_o <= (raw_accept_mask_o[1] && !hold1_c) ? wb1_raw : '0;
                    ordinary_wakeup_valid_final_o[0] <=
                        raw_accept_mask_o[0] && ordinary_wakeup_valid_raw[0];
                    ordinary_wakeup_valid_final_o[1] <=
                        raw_accept_mask_o[1] && !hold1_c && ordinary_wakeup_valid_raw[1];
                    wakeup_phys0_final_o <=
                        (raw_accept_mask_o[0] && ordinary_wakeup_valid_raw[0]) ?
                        wakeup_phys0_raw : `BBUS_OOO_PHYS_ZERO;
                    wakeup_phys1_final_o <=
                        (raw_accept_mask_o[1] && !hold1_c && ordinary_wakeup_valid_raw[1]) ?
                        wakeup_phys1_raw : `BBUS_OOO_PHYS_ZERO;
                    dual_wb_final_fire_o <=
                        raw_accept_mask_o[0] && raw_accept_mask_o[1] && !hold1_c;

                    if (hold1_c) begin
                        held_valid_q <= 1'b1;
                        held_wb_q <= wb1_raw;
                        lane1_hold_o <= 1'b1;
                        duplicate_phys_hold_o <= duplicate_phys_bug_raw;
                        duplicate_rob_tag_hold_o <= duplicate_rob_tag_bug_raw;
                        lane1_consumer_block_hold_o <= lane1_consumer_block_i;
                        lane1_buffer_full_hold_o <= lane1_buffer_full_i;
                        lane1_ordering_block_hold_o <= lane1_ordering_block_i;
                    end
                end
            end
        end
    end

endmodule
