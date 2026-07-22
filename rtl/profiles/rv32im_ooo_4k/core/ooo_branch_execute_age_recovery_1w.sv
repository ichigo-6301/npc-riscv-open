`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// Execute-age two-branch recovery owner.  A mispredict is selected at the
// registered final-completion boundary, transacted on the following cycle,
// then exposed as one held redirect.  The selective transaction itself is
// performed by the ROB/Rename/backend coordinator; this controller only
// advances when that atomic fire is reported.
module ooo_branch_execute_age_recovery_1w #(
    parameter bit SELECTIVE_TRANSACTION_REDIRECT_OVERLAP_ENABLE = 1'b0
) (
    input logic clk,
    input logic reset,
    input logic external_global_recover_i,

    input logic branch_dispatch_fire_i,
    input bbus_ooo_rob_tag_t branch_dispatch_rob_tag_i,
    input logic branch_issue_accept_i,
    input bbus_ooo_rob_tag_t branch_issue_rob_tag_i,

    input logic [1:0] final_consume_mask_i,
    input bbus_ooo_writeback_t final_wb0_i,
    input bbus_ooo_writeback_t final_wb1_i,
    input logic checkpoint_lookup_hit_i,
    input logic [31:0] checkpoint_branch_pc_i,

    output logic checkpoint_release_valid_o,
    output bbus_ooo_rob_tag_t checkpoint_release_tag_o,
    output logic checkpoint_select_valid_o,
    output bbus_ooo_rob_tag_t checkpoint_select_tag_o,

    output logic selective_request_valid_o,
    output bbus_ooo_rob_tag_t selective_request_branch_tag_o,
    input logic selective_transaction_fire_i,
    input logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_i,

    input logic redirect_ready_i,
    output logic redirect_valid_o,
    output bbus_ooo_redirect_t redirect_o,
    output logic dispatch_freeze_o,
    output logic serial_dispatch_block_o,
    output logic branch_dispatch_allow_o,
    output logic branch_window_active_o,
    output logic [1:0] branch_window_count_o,
    output logic branch_recovery_pending_o,
    output logic admission_error_o,
    output logic unexpected_branch_final_o,
    output logic checkpoint_miss_error_o,
    output logic conservation_error_o
);
    typedef enum logic [1:0] {
        REC_ACTIVE,
        REC_TRANSACTION,
        REC_REDIRECT
    } recovery_state_e;

    recovery_state_e state_q;
    logic [1:0] window_valid_q;
    bbus_ooo_rob_tag_t window_tag0_q, window_tag1_q;
    bbus_ooo_rob_tag_t pending_tag_q;
    logic [31:0] pending_pc_q;
    logic [31:0] pending_target_q;
    bbus_ooo_redirect_reason_e pending_reason_q;
    bbus_ooo_redirect_t redirect_q;
    logic admission_error_q, unexpected_branch_final_q;
    logic checkpoint_miss_error_q;

    logic final_branch_seen_c, final_branch_mispredict_c;
    bbus_ooo_writeback_t final_branch_wb_c;
    logic final_match0_c, final_match1_c, correct_release_c;
    logic select_mispredict_c;
    logic transaction_redirect_valid_c, transaction_redirect_fire_c;
    logic [1:0] window_count_c;

    function automatic logic tag_match(
        input bbus_ooo_rob_tag_t a,
        input bbus_ooo_rob_tag_t b
    );
        tag_match = a.valid && b.valid &&
            (a.idx == b.idx) && (a.gen == b.gen);
    endfunction

    function automatic logic is_branch_wb(input bbus_ooo_writeback_t wb);
        is_branch_wb = wb.valid && wb.done && wb.is_control &&
            (wb.is_branch || wb.is_jal || wb.is_jalr);
    endfunction

    function automatic bbus_ooo_redirect_reason_e redirect_reason(
        input bbus_ooo_writeback_t wb
    );
        if (wb.is_jal) redirect_reason = BBUS_OOO_REDIRECT_JAL;
        else if (wb.is_jalr) redirect_reason = BBUS_OOO_REDIRECT_JALR;
        else redirect_reason = BBUS_OOO_REDIRECT_BRANCH;
    endfunction

    always_comb begin
        final_branch_seen_c = 1'b0;
        final_branch_wb_c = '0;
        if (final_consume_mask_i[0] && is_branch_wb(final_wb0_i)) begin
            final_branch_seen_c = 1'b1;
            final_branch_wb_c = final_wb0_i;
        end else if (final_consume_mask_i[1] && is_branch_wb(final_wb1_i)) begin
            final_branch_seen_c = 1'b1;
            final_branch_wb_c = final_wb1_i;
        end
        final_branch_mispredict_c = final_branch_seen_c &&
            final_branch_wb_c.redirect_valid;
        final_match0_c = final_branch_seen_c && window_valid_q[0] &&
            tag_match(final_branch_wb_c.rob_tag, window_tag0_q);
        final_match1_c = final_branch_seen_c && window_valid_q[1] &&
            tag_match(final_branch_wb_c.rob_tag, window_tag1_q);
        correct_release_c = (state_q == REC_ACTIVE) && final_branch_seen_c &&
            !final_branch_mispredict_c && (final_match0_c || final_match1_c);
        select_mispredict_c = (state_q == REC_ACTIVE) &&
            final_branch_mispredict_c && (final_match0_c || final_match1_c);
        window_count_c = {1'b0, window_valid_q[0]} +
            {1'b0, window_valid_q[1]};
    end

    assign checkpoint_release_valid_o = correct_release_c;
    assign checkpoint_release_tag_o = correct_release_c ?
        final_branch_wb_c.rob_tag : '0;
    assign checkpoint_select_valid_o = select_mispredict_c;
    assign checkpoint_select_tag_o = select_mispredict_c ?
        final_branch_wb_c.rob_tag : '0;
    assign selective_request_valid_o = !external_global_recover_i &&
        (state_q == REC_TRANSACTION);
    assign selective_request_branch_tag_o = pending_tag_q;
    // The redirect payload is already stable in REC_TRANSACTION. Expose it
    // early only when the atomic selective transaction is guaranteed to fire
    // on this edge; otherwise retain the registered REC_REDIRECT owner.
    assign transaction_redirect_valid_c =
        SELECTIVE_TRANSACTION_REDIRECT_OVERLAP_ENABLE &&
        !external_global_recover_i && (state_q == REC_TRANSACTION) &&
        selective_transaction_fire_i;
    assign transaction_redirect_fire_c = transaction_redirect_valid_c &&
        redirect_ready_i;
    assign redirect_valid_o = !external_global_recover_i &&
        ((state_q == REC_REDIRECT) || transaction_redirect_valid_c);
    always_comb begin
        redirect_o = redirect_q;
        if (transaction_redirect_valid_c) begin
            redirect_o = '0;
            redirect_o.valid = 1'b1;
            redirect_o.rob_tag = pending_tag_q;
            redirect_o.pc = pending_pc_q;
            redirect_o.target = pending_target_q;
            redirect_o.reason = pending_reason_q;
        end
    end
    assign dispatch_freeze_o = external_global_recover_i ||
        (state_q != REC_ACTIVE);
    assign serial_dispatch_block_o = external_global_recover_i ||
        (window_count_c != 0) || (state_q != REC_ACTIVE);
    assign branch_dispatch_allow_o = !external_global_recover_i &&
        (state_q == REC_ACTIVE) &&
        ((window_count_c < 2) || correct_release_c);
    assign branch_window_active_o = (window_count_c != 0) ||
        (state_q != REC_ACTIVE);
    assign branch_window_count_o = window_count_c;
    assign branch_recovery_pending_o = (state_q != REC_ACTIVE);
    assign admission_error_o = admission_error_q;
    assign unexpected_branch_final_o = unexpected_branch_final_q;
    assign checkpoint_miss_error_o = checkpoint_miss_error_q;
    assign conservation_error_o = admission_error_q ||
        unexpected_branch_final_q || checkpoint_miss_error_q;

    always_ff @(posedge clk) begin : update_recovery
        logic [1:0] next_valid;
        bbus_ooo_rob_tag_t next_tag0, next_tag1;

        if (reset || external_global_recover_i) begin
            state_q <= REC_ACTIVE;
            window_valid_q <= 2'b00;
            window_tag0_q <= '0;
            window_tag1_q <= '0;
            pending_tag_q <= '0;
            pending_pc_q <= '0;
            pending_target_q <= '0;
            pending_reason_q <= BBUS_OOO_REDIRECT_NONE;
            redirect_q <= '0;
            admission_error_q <= 1'b0;
            unexpected_branch_final_q <= 1'b0;
            checkpoint_miss_error_q <= 1'b0;
        end else begin
            next_valid = window_valid_q;
            next_tag0 = window_tag0_q;
            next_tag1 = window_tag1_q;

            if (branch_issue_accept_i &&
                !((window_valid_q[0] &&
                   tag_match(branch_issue_rob_tag_i, window_tag0_q)) ||
                  (window_valid_q[1] &&
                   tag_match(branch_issue_rob_tag_i, window_tag1_q)) ||
                  (branch_dispatch_fire_i &&
                   tag_match(branch_issue_rob_tag_i,
                             branch_dispatch_rob_tag_i))))
                admission_error_q <= 1'b1;

            if (final_branch_seen_c && !(final_match0_c || final_match1_c) &&
                (state_q == REC_ACTIVE))
                unexpected_branch_final_q <= 1'b1;

            if (correct_release_c) begin
                if (final_match0_c) begin
                    next_valid[0] = next_valid[1];
                    next_tag0 = next_tag1;
                    next_valid[1] = 1'b0;
                    next_tag1 = '0;
                end else begin
                    next_valid[1] = 1'b0;
                    next_tag1 = '0;
                end
            end

            if (branch_dispatch_fire_i) begin
                if (!branch_dispatch_allow_o ||
                    !branch_dispatch_rob_tag_i.valid) begin
                    admission_error_q <= 1'b1;
                end else if (!next_valid[0]) begin
                    next_valid[0] = 1'b1;
                    next_tag0 = branch_dispatch_rob_tag_i;
                end else if (!next_valid[1]) begin
                    next_valid[1] = 1'b1;
                    next_tag1 = branch_dispatch_rob_tag_i;
                end else begin
                    admission_error_q <= 1'b1;
                end
            end

            unique case (state_q)
                REC_ACTIVE: begin
                    redirect_q <= '0;
                    if (select_mispredict_c) begin
                        if (!checkpoint_lookup_hit_i) begin
                            checkpoint_miss_error_q <= 1'b1;
                        end else begin
                            pending_tag_q <= final_branch_wb_c.rob_tag;
                            pending_pc_q <= checkpoint_branch_pc_i;
                            pending_target_q <= final_branch_wb_c.actual_nextpc;
                            pending_reason_q <= redirect_reason(final_branch_wb_c);
                            state_q <= REC_TRANSACTION;
                        end
                    end
                end
                REC_TRANSACTION: begin
                    if (selective_transaction_fire_i) begin
                        for (int w = 0; w < 2; w = w + 1) begin
                            if (next_valid[w] &&
                                ((w == 0) ?
                                 (tag_match(next_tag0, pending_tag_q) ||
                                  selective_killed_rob_mask_i[next_tag0.idx]) :
                                 (tag_match(next_tag1, pending_tag_q) ||
                                  selective_killed_rob_mask_i[next_tag1.idx]))) begin
                                next_valid[w] = 1'b0;
                                if (w == 0) next_tag0 = '0;
                                else next_tag1 = '0;
                            end
                        end
                        if (!next_valid[0] && next_valid[1]) begin
                            next_valid[0] = 1'b1;
                            next_tag0 = next_tag1;
                            next_valid[1] = 1'b0;
                            next_tag1 = '0;
                        end
                        if (transaction_redirect_fire_c) begin
                            redirect_q <= '0;
                            pending_tag_q <= '0;
                            pending_pc_q <= '0;
                            pending_target_q <= '0;
                            pending_reason_q <= BBUS_OOO_REDIRECT_NONE;
                            state_q <= REC_ACTIVE;
                        end else begin
                            redirect_q.valid <= 1'b1;
                            redirect_q.rob_tag <= pending_tag_q;
                            redirect_q.pc <= pending_pc_q;
                            redirect_q.target <= pending_target_q;
                            redirect_q.reason <= pending_reason_q;
                            state_q <= REC_REDIRECT;
                        end
                    end
                end
                REC_REDIRECT: begin
                    if (redirect_valid_o && redirect_ready_i) begin
                        redirect_q <= '0;
                        pending_tag_q <= '0;
                        pending_pc_q <= '0;
                        pending_target_q <= '0;
                        pending_reason_q <= BBUS_OOO_REDIRECT_NONE;
                        state_q <= REC_ACTIVE;
                    end
                end
                default: state_q <= REC_ACTIVE;
            endcase

            window_valid_q <= next_valid;
            window_tag0_q <= next_tag0;
            window_tag1_q <= next_tag1;
        end
    end
endmodule
