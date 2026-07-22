`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_dual_wb_buffered_wrapper_2w #(
    parameter bit RAW_TO_FINAL_BYPASS_ENABLE = 1'b0
) (
    input  logic clk,
    input  logic reset,
    input  logic selective_kill_valid_i,
    input  logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_i,

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
    input  logic final_consumer_ready_i,
    input  logic [1:0] final_consumer_accept_mask_i,
    input  logic [1:0] final_consumer_drop_mask_i,
    input  logic flush_i,

    output logic [1:0] raw_accept_mask_o,
    output logic [1:0] source_accept_mask_o,
    output logic [1:0] source_drop_mask_o,
    output logic [1:0] source_clear_mask_o,
    output logic [1:0] final_accept_mask_o,
    output logic [1:0] final_drop_mask_o,
    output logic [1:0] hold_mask_o,

    output bbus_ooo_writeback_t wb0_final_o,
    output bbus_ooo_writeback_t wb1_final_o,

    output logic [1:0] ordinary_wakeup_valid_final_o,
    output bbus_ooo_phys_reg_t wakeup_phys0_final_o,
    output bbus_ooo_phys_reg_t wakeup_phys1_final_o,

    output logic [1:0] pending_count_o,
    output logic buffer_full_o,
    output logic buffer_empty_o,
    output logic [1:0] registered_final_valid_mask_o,
    output logic [1:0] enqueue_mask_o,
    output logic [1:0] dequeue_mask_o,

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
    output logic buffer_full_hold_o,
    output logic stale_drop0_o,
    output logic stale_drop1_o,
    output logic killed_drop0_o,
    output logic killed_drop1_o,
    output logic [1:0] selective_final_drop_mask_o,
    output logic [1:0] selective_pending_drop_mask_o,
    output logic exception_no_wakeup0_o,
    output logic exception_no_wakeup1_o,
    output logic p0_wakeup_suppressed0_o,
    output logic p0_wakeup_suppressed1_o,
    output logic atomicity_mask_valid_o,
    output logic conservation_error_o
);
    typedef struct packed {
        logic lane;
        bbus_ooo_writeback_t wb;
    } pending_entry_t;

    pending_entry_t pending_q [1:0];
    logic [1:0] pending_valid_q;

    bbus_ooo_writeback_t wb0_raw;
    bbus_ooo_writeback_t wb1_raw;
    logic [1:0] ordinary_wakeup_valid_raw;
    bbus_ooo_phys_reg_t wakeup_phys0_raw;
    bbus_ooo_phys_reg_t wakeup_phys1_raw;
    logic dual_wakeup_fire_raw;
    logic duplicate_phys_bug_raw;
    logic duplicate_rob_tag_bug_raw;

    logic [1:0] raw_drop_mask_c;
    logic pending_nonempty_c;
    logic final_active_c;
    logic raw_path_open_c;
    logic [1:0] pending_count_c;
    logic [1:0] pending_room_c;
    logic lane0_block_c;
    logic lane1_hold_c;
    logic any_raw_hold_c;
    logic [1:0] enqueue_mask_c;
    logic [1:0] final_accept_mask_c;
    logic [1:0] source_accept_mask_c;
    logic [1:0] hold_mask_c;
    logic enqueue_overflow_c;
    logic [1:0] final_valid_mask_q;
    bbus_ooo_writeback_t wb0_final_q;
    bbus_ooo_writeback_t wb1_final_q;
    logic [1:0] ordinary_wakeup_valid_final_q;
    bbus_ooo_phys_reg_t wakeup_phys0_final_q;
    bbus_ooo_phys_reg_t wakeup_phys1_final_q;
    logic raw_bypass_active_c;
    logic [1:0] effective_final_valid_c;
    logic [1:0] direct_final_terminal_c;
    logic [1:0] final_consume_mask_c;
    logic [1:0] final_drop_mask_c;
    logic [1:0] final_clear_mask_c;
    logic [1:0] selective_final_killed_c;
    logic [1:0] selective_pending_killed_c;

    function automatic logic tag_killed(input bbus_ooo_rob_tag_t tag);
        tag_killed = selective_kill_valid_i && tag.valid &&
            selective_killed_rob_mask_i[tag.idx];
    endfunction

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

    function automatic logic [1:0] popcount2(input logic [1:0] mask);
        begin
            popcount2 = {1'b0, mask[0]} + {1'b0, mask[1]};
        end
    endfunction

    assign pending_count_c =
        {1'b0, pending_valid_q[0]} + {1'b0, pending_valid_q[1]};
    assign pending_nonempty_c = (pending_count_c != 2'd0);
    assign pending_room_c = 2'd2 - pending_count_c;
    assign final_active_c = (final_valid_mask_q != 2'b00);
    assign raw_path_open_c = !final_active_c && !pending_nonempty_c && !flush_i &&
        !selective_kill_valid_i;
    // A flush suppresses any registered final offer before consumers can observe it.
    assign selective_final_killed_c = {
        final_valid_mask_q[1] && tag_killed(wb1_final_q.rob_tag),
        final_valid_mask_q[0] && tag_killed(wb0_final_q.rob_tag)
    };
    assign selective_pending_killed_c = {
        pending_valid_q[1] && tag_killed(pending_q[1].wb.rob_tag),
        pending_valid_q[0] && tag_killed(pending_q[0].wb.rob_tag)
    };
    assign selective_final_drop_mask_o = selective_kill_valid_i ?
        selective_final_killed_c : 2'b00;
    assign selective_pending_drop_mask_o = selective_kill_valid_i ?
        selective_pending_killed_c : 2'b00;
    assign raw_drop_mask_c = {
        wb1_i.valid && (!wb1_rob_match_i || wb1_killed_i),
        wb0_i.valid && (!wb0_rob_match_i || wb0_killed_i)
    };

    assign lane0_block_c = lane0_consumer_block_i && (raw_accept_mask_o != 2'b00);
    assign lane1_hold_c =
        raw_accept_mask_o[1] &&
        !lane0_block_c &&
        (duplicate_phys_bug_raw ||
         duplicate_rob_tag_bug_raw ||
         lane1_consumer_block_i ||
         lane1_buffer_full_i ||
         lane1_ordering_block_i);
    assign any_raw_hold_c = lane0_block_c || lane1_hold_c;

    // The transparent path is selected from the raw producer side only.
    // Do not feed final-consumer acceptance back into this predicate: the
    // consumer probe is computed from the final packet itself, so doing so
    // creates a combinational loop (raw -> final packet -> probe -> accept ->
    // raw).  If the consumer does not accept this cycle, the sequential
    // capture path below retains the same packet in final_valid_mask_q.
    assign raw_bypass_active_c = RAW_TO_FINAL_BYPASS_ENABLE &&
        raw_path_open_c && !any_raw_hold_c && (raw_accept_mask_o != 2'b00);
    assign effective_final_valid_c = raw_bypass_active_c ?
        final_accept_mask_c : final_valid_mask_q;
    assign final_accept_mask_o = (flush_i || selective_kill_valid_i) ?
        2'b00 : effective_final_valid_c;
    assign final_consume_mask_c =
        (!selective_kill_valid_i && final_consumer_ready_i) ?
        (effective_final_valid_c & final_consumer_accept_mask_i) : 2'b00;
    // A final drop is terminal: the producer was already safely captured, or
    // is being transparently transferred on the raw edge, and the final
    // consumer has established that this lane can never be accepted.
    assign final_drop_mask_c =
        (!selective_kill_valid_i && final_consumer_ready_i) ?
        (effective_final_valid_c & final_consumer_drop_mask_i &
         ~final_consume_mask_c) : 2'b00;
    assign final_clear_mask_c = final_consume_mask_c | final_drop_mask_c;
    assign direct_final_terminal_c = raw_bypass_active_c ?
        final_clear_mask_c : 2'b00;
    assign final_drop_mask_o = final_drop_mask_c;

    always_comb begin
        wb0_final_o = wb0_final_q;
        wb1_final_o = wb1_final_q;
        ordinary_wakeup_valid_final_o = ordinary_wakeup_valid_final_q;
        wakeup_phys0_final_o = wakeup_phys0_final_q;
        wakeup_phys1_final_o = wakeup_phys1_final_q;
        if (raw_bypass_active_c) begin
            wb0_final_o = final_accept_mask_c[0] ? wb0_raw : '0;
            wb1_final_o = final_accept_mask_c[1] ? wb1_raw : '0;
            ordinary_wakeup_valid_final_o[0] =
                final_accept_mask_c[0] && ordinary_wakeup_valid_raw[0];
            ordinary_wakeup_valid_final_o[1] =
                final_accept_mask_c[1] && ordinary_wakeup_valid_raw[1];
            wakeup_phys0_final_o =
                (final_accept_mask_c[0] && ordinary_wakeup_valid_raw[0]) ?
                wakeup_phys0_raw : `BBUS_OOO_PHYS_ZERO;
            wakeup_phys1_final_o =
                (final_accept_mask_c[1] && ordinary_wakeup_valid_raw[1]) ?
                wakeup_phys1_raw : `BBUS_OOO_PHYS_ZERO;
        end
    end

    always_comb begin
        source_accept_mask_c = 2'b00;
        final_accept_mask_c = 2'b00;
        enqueue_mask_c = 2'b00;
        hold_mask_c = 2'b00;
        enqueue_overflow_c = 1'b0;

        if (raw_path_open_c) begin
            if (lane0_block_c) begin
                hold_mask_c = raw_accept_mask_o;
                if (pending_room_c >= popcount2(raw_accept_mask_o)) begin
                    enqueue_mask_c = raw_accept_mask_o;
                    source_accept_mask_c = raw_accept_mask_o;
                end else begin
                    enqueue_overflow_c = (raw_accept_mask_o != 2'b00);
                end
            end else if (lane1_hold_c) begin
                final_accept_mask_c[0] = raw_accept_mask_o[0];
                hold_mask_c[1] = 1'b1;
                if (pending_room_c != 2'd0) begin
                    enqueue_mask_c[1] = 1'b1;
                    source_accept_mask_c[1] = 1'b1;
                    source_accept_mask_c[0] = raw_accept_mask_o[0];
                end else begin
                    enqueue_overflow_c = 1'b1;
                end
            end else begin
                final_accept_mask_c = raw_accept_mask_o;
                source_accept_mask_c = raw_accept_mask_o;
            end
        end
    end

    assign source_accept_mask_o = source_accept_mask_c;
    // A killed raw source may be terminal-dropped during a flush. Otherwise a
    // final/pending packet has absolute priority over all raw source clearing.
    assign source_drop_mask_o =
        (flush_i || (!final_active_c && !pending_nonempty_c)) ? raw_drop_mask_c : 2'b00;
    assign source_clear_mask_o = source_accept_mask_o | source_drop_mask_o;
    assign pending_count_o = pending_count_c;
    assign buffer_full_o = (pending_count_c == 2'd2);
    assign buffer_empty_o = (pending_count_c == 2'd0);
    // Ownership arbitration must observe stored state, not the transient
    // raw-to-final offer.  Feeding effective_final_valid_c back into the raw
    // window predicate makes the transparent offer disable itself.
    assign registered_final_valid_mask_o = final_valid_mask_q;

    always_ff @(posedge clk) begin
        pending_entry_t next_pending [1:0];
        logic [1:0] next_valid;
        logic [1:0] capture_mask;

        if (reset || flush_i) begin
            pending_valid_q <= 2'b00;
            pending_q[0] <= '0;
            pending_q[1] <= '0;
            final_valid_mask_q <= 2'b00;
            hold_mask_o <= 2'b00;
            wb0_final_q <= '0;
            wb1_final_q <= '0;
            ordinary_wakeup_valid_final_q <= 2'b00;
            wakeup_phys0_final_q <= `BBUS_OOO_PHYS_ZERO;
            wakeup_phys1_final_q <= `BBUS_OOO_PHYS_ZERO;
            enqueue_mask_o <= 2'b00;
            dequeue_mask_o <= 2'b00;
            dual_wb_final_fire_o <= 1'b0;
            lane1_hold_o <= 1'b0;
            lane1_replay_o <= 1'b0;
            duplicate_phys_hold_o <= 1'b0;
            duplicate_rob_tag_hold_o <= 1'b0;
            lane0_block_hold_o <= 1'b0;
            lane1_consumer_block_hold_o <= 1'b0;
            lane1_buffer_full_hold_o <= 1'b0;
            lane1_ordering_block_hold_o <= 1'b0;
            buffer_full_hold_o <= 1'b0;
            atomicity_mask_valid_o <= 1'b0;
            conservation_error_o <= 1'b0;
        end else begin
            next_pending[0] = pending_q[0];
            next_pending[1] = pending_q[1];
            next_valid = pending_valid_q;
            capture_mask = final_accept_mask_c & ~direct_final_terminal_c;

            hold_mask_o <= hold_mask_c;
            enqueue_mask_o <= 2'b00;
            dequeue_mask_o <= 2'b00;
            dual_wb_final_fire_o <= 1'b0;
            lane1_hold_o <= 1'b0;
            lane1_replay_o <= 1'b0;
            duplicate_phys_hold_o <= 1'b0;
            duplicate_rob_tag_hold_o <= 1'b0;
            lane0_block_hold_o <= 1'b0;
            lane1_consumer_block_hold_o <= 1'b0;
            lane1_buffer_full_hold_o <= 1'b0;
            lane1_ordering_block_hold_o <= 1'b0;
            buffer_full_hold_o <= 1'b0;
            atomicity_mask_valid_o <= 1'b1;
            conservation_error_o <= enqueue_overflow_c;

            if (selective_kill_valid_i) begin
                int dst;
                dst = 0;
                next_pending[0] = '0;
                next_pending[1] = '0;
                next_valid = 2'b00;
                for (int src = 0; src < 2; src = src + 1) begin
                    if (pending_valid_q[src] &&
                        !tag_killed(pending_q[src].wb.rob_tag)) begin
                        next_pending[dst] = pending_q[src];
                        next_valid[dst] = 1'b1;
                        dst = dst + 1;
                    end
                end
                if (selective_final_killed_c[0]) begin
                    final_valid_mask_q[0] <= 1'b0;
                    wb0_final_q <= '0;
                    ordinary_wakeup_valid_final_q[0] <= 1'b0;
                    wakeup_phys0_final_q <= `BBUS_OOO_PHYS_ZERO;
                end
                if (selective_final_killed_c[1]) begin
                    final_valid_mask_q[1] <= 1'b0;
                    wb1_final_q <= '0;
                    ordinary_wakeup_valid_final_q[1] <= 1'b0;
                    wakeup_phys1_final_q <= `BBUS_OOO_PHYS_ZERO;
                end
                hold_mask_o <= 2'b00;
            end else if (final_active_c) begin
                hold_mask_o <= 2'b00;
                if (final_clear_mask_c != 2'b00) begin
                    dual_wb_final_fire_o <=
                        (final_valid_mask_q == 2'b11) && (final_consume_mask_c == 2'b11);
                    // The current final transfer may be retired while the
                    // oldest pending lane becomes the next registered offer.
                    // Raw input remains blocked for this whole cycle.
                    if (final_clear_mask_c != final_valid_mask_q) begin
                        // A consumer may accept or terminal-drop one lane
                        // while the other remains backpressured. Retain only
                        // the lane that was neither accepted nor dropped.
                        final_valid_mask_q <= final_valid_mask_q & ~final_clear_mask_c;
                        if (final_clear_mask_c[0]) begin
                            wb0_final_q <= '0;
                            ordinary_wakeup_valid_final_q[0] <= 1'b0;
                            wakeup_phys0_final_q <= `BBUS_OOO_PHYS_ZERO;
                        end
                        if (final_clear_mask_c[1]) begin
                            wb1_final_q <= '0;
                            ordinary_wakeup_valid_final_q[1] <= 1'b0;
                            wakeup_phys1_final_q <= `BBUS_OOO_PHYS_ZERO;
                        end
                    end else if (pending_nonempty_c) begin
                        if (pending_q[0].lane) begin
                            final_valid_mask_q <= 2'b10;
                            wb1_final_q <= pending_q[0].wb;
                            wb0_final_q <= '0;
                            ordinary_wakeup_valid_final_q[1] <= ordinary_wakeup(pending_q[0].wb);
                            ordinary_wakeup_valid_final_q[0] <= 1'b0;
                            wakeup_phys1_final_q <= ordinary_wakeup(pending_q[0].wb) ?
                                pending_q[0].wb.phys_rd : `BBUS_OOO_PHYS_ZERO;
                            wakeup_phys0_final_q <= `BBUS_OOO_PHYS_ZERO;
                            dequeue_mask_o <= 2'b10;
                            lane1_replay_o <= 1'b1;
                        end else begin
                            final_valid_mask_q <= 2'b01;
                            wb0_final_q <= pending_q[0].wb;
                            wb1_final_q <= '0;
                            ordinary_wakeup_valid_final_q[0] <= ordinary_wakeup(pending_q[0].wb);
                            ordinary_wakeup_valid_final_q[1] <= 1'b0;
                            wakeup_phys0_final_q <= ordinary_wakeup(pending_q[0].wb) ?
                                pending_q[0].wb.phys_rd : `BBUS_OOO_PHYS_ZERO;
                            wakeup_phys1_final_q <= `BBUS_OOO_PHYS_ZERO;
                            dequeue_mask_o <= 2'b01;
                        end
                        next_pending[0] = pending_q[1];
                        next_pending[1] = '0;
                        next_valid = {1'b0, pending_valid_q[1]};
                    end else begin
                        final_valid_mask_q <= 2'b00;
                        wb0_final_q <= '0;
                        wb1_final_q <= '0;
                        ordinary_wakeup_valid_final_q <= 2'b00;
                        wakeup_phys0_final_q <= `BBUS_OOO_PHYS_ZERO;
                        wakeup_phys1_final_q <= `BBUS_OOO_PHYS_ZERO;
                    end
                end
            end else if (pending_nonempty_c) begin
                if (pending_q[0].lane) begin
                    final_valid_mask_q <= 2'b10;
                    wb1_final_q <= pending_q[0].wb;
                    wb0_final_q <= '0;
                    ordinary_wakeup_valid_final_q[1] <= ordinary_wakeup(pending_q[0].wb);
                    ordinary_wakeup_valid_final_q[0] <= 1'b0;
                    wakeup_phys1_final_q <= ordinary_wakeup(pending_q[0].wb) ?
                        pending_q[0].wb.phys_rd : `BBUS_OOO_PHYS_ZERO;
                    wakeup_phys0_final_q <= `BBUS_OOO_PHYS_ZERO;
                    dequeue_mask_o <= 2'b10;
                    lane1_replay_o <= 1'b1;
                end else begin
                    final_valid_mask_q <= 2'b01;
                    wb0_final_q <= pending_q[0].wb;
                    wb1_final_q <= '0;
                    ordinary_wakeup_valid_final_q[0] <= ordinary_wakeup(pending_q[0].wb);
                    ordinary_wakeup_valid_final_q[1] <= 1'b0;
                    wakeup_phys0_final_q <= ordinary_wakeup(pending_q[0].wb) ?
                        pending_q[0].wb.phys_rd : `BBUS_OOO_PHYS_ZERO;
                    wakeup_phys1_final_q <= `BBUS_OOO_PHYS_ZERO;
                    dequeue_mask_o <= 2'b01;
                end
                next_pending[0] = pending_q[1];
                next_pending[1] = '0;
                next_valid = {1'b0, pending_valid_q[1]};
            end else begin
                final_valid_mask_q <= capture_mask;
                hold_mask_o <= hold_mask_c;
                wb0_final_q <= capture_mask[0] ? wb0_raw : '0;
                wb1_final_q <= capture_mask[1] ? wb1_raw : '0;
                ordinary_wakeup_valid_final_q[0] <=
                    capture_mask[0] && ordinary_wakeup_valid_raw[0];
                ordinary_wakeup_valid_final_q[1] <=
                    capture_mask[1] && ordinary_wakeup_valid_raw[1];
                wakeup_phys0_final_q <=
                    (capture_mask[0] && ordinary_wakeup_valid_raw[0]) ?
                    wakeup_phys0_raw : `BBUS_OOO_PHYS_ZERO;
                wakeup_phys1_final_q <=
                    (capture_mask[1] && ordinary_wakeup_valid_raw[1]) ?
                    wakeup_phys1_raw : `BBUS_OOO_PHYS_ZERO;
                if (raw_bypass_active_c &&
                    (direct_final_terminal_c != 2'b00)) begin
                    dual_wb_final_fire_o <=
                        (direct_final_terminal_c == 2'b11) &&
                        (final_consume_mask_c == 2'b11);
                end

                if (enqueue_mask_c[0]) begin
                    next_pending[0].lane = 1'b0;
                    next_pending[0].wb = wb0_raw;
                    next_valid[0] = 1'b1;
                    enqueue_mask_o[0] <= 1'b1;
                end
                if (enqueue_mask_c[1]) begin
                    if (next_valid[0]) begin
                        next_pending[1].lane = 1'b1;
                        next_pending[1].wb = wb1_raw;
                        next_valid[1] = 1'b1;
                    end else begin
                        next_pending[0].lane = 1'b1;
                        next_pending[0].wb = wb1_raw;
                        next_valid[0] = 1'b1;
                    end
                    enqueue_mask_o[1] <= 1'b1;
                    lane1_hold_o <= 1'b1;
                end

                if (lane0_block_c) begin
                    lane0_block_hold_o <= 1'b1;
                end
                if (lane1_hold_c) begin
                    duplicate_phys_hold_o <= duplicate_phys_bug_raw;
                    duplicate_rob_tag_hold_o <= duplicate_rob_tag_bug_raw;
                    lane1_consumer_block_hold_o <= lane1_consumer_block_i;
                    lane1_buffer_full_hold_o <= lane1_buffer_full_i;
                    lane1_ordering_block_hold_o <= lane1_ordering_block_i;
                end
                buffer_full_hold_o <= enqueue_overflow_c;
            end

            pending_q[0] <= next_pending[0];
            pending_q[1] <= next_pending[1];
            pending_valid_q <= next_valid;
        end
    end

endmodule
