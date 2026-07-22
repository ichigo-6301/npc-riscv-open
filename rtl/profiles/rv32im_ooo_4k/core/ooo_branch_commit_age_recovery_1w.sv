`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// Two-entry branch window with commit-age global recovery. This is the
// measured transition point before real rename/ROB selective checkpoints.
module ooo_branch_commit_age_recovery_1w (
    input  logic clk,
    input  logic reset,
    input  logic external_global_recover_i,

    input  logic branch_dispatch_fire_i,
    input  bbus_ooo_rob_tag_t branch_dispatch_rob_tag_i,
    input  logic branch_issue_accept_i,
    input  bbus_ooo_rob_tag_t branch_issue_rob_tag_i,

    input  logic [1:0] final_consume_mask_i,
    input  bbus_ooo_writeback_t final_wb0_i,
    input  bbus_ooo_writeback_t final_wb1_i,
    input  bbus_ooo_commit_event_t commit_event_i,

    input  logic redirect_ready_i,
    output logic dispatch_freeze_o,
    output logic serial_dispatch_block_o,
    output logic branch_dispatch_allow_o,
    output logic branch_window_active_o,
    output logic branch_recovery_pending_o,
    output logic recovery_pulse_o,
    output logic redirect_valid_o,
    output bbus_ooo_redirect_t redirect_o,

    output logic debug_branch_final_seen_o,
    output logic debug_branch_commit_seen_o,
    output logic pending_select_o,
    output logic checkpoint_release_valid_o,
    output bbus_ooo_rob_tag_t checkpoint_release_tag_o,
    output logic checkpoint_select_valid_o,
    output bbus_ooo_rob_tag_t checkpoint_select_tag_o,
    output logic admission_error_o,
    output logic unexpected_branch_final_o,
    output logic conservation_error_o
);
    typedef enum logic [1:0] {
        REC_ACTIVE,
        REC_PENDING,
        REC_RECOVER,
        REC_REDIRECT
    } recovery_state_e;

    recovery_state_e state_q;
    logic [1:0] window_valid_q;
    bbus_ooo_rob_tag_t window_tag0_q, window_tag1_q;
    bbus_ooo_rob_tag_t pending_tag_q;
    logic [31:0] pending_target_q;
    bbus_ooo_redirect_reason_e pending_reason_q;
    bbus_ooo_redirect_t redirect_q;
    logic admission_error_q, unexpected_branch_final_q;
    logic debug_branch_final_seen_q, debug_branch_commit_seen_q;

    logic final_branch_seen_c, final_branch_mispredict_c;
    bbus_ooo_writeback_t final_branch_wb_c;
    logic final_match0_c, final_match1_c;
    logic correct_release_c;
    logic pending_match0_c, pending_match1_c;
    logic pending_commit_c;
    logic [1:0] window_count_c;
    logic choose_new_pending_c;

    function automatic logic tag_match(
        input bbus_ooo_rob_tag_t a,
        input bbus_ooo_rob_tag_t b
    );
        tag_match = a.valid && b.valid && (a.idx == b.idx) && (a.gen == b.gen);
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
        correct_release_c = final_branch_seen_c &&
            !final_branch_mispredict_c && (final_match0_c || final_match1_c);
        pending_match0_c = window_valid_q[0] &&
            tag_match(pending_tag_q, window_tag0_q);
        pending_match1_c = window_valid_q[1] &&
            tag_match(pending_tag_q, window_tag1_q);
        pending_commit_c = commit_event_i.normal_commit_mask[0] &&
            tag_match(commit_event_i.slot0.rob_tag, pending_tag_q);
        window_count_c = {1'b0, window_valid_q[0]} +
            {1'b0, window_valid_q[1]};
        choose_new_pending_c = final_branch_mispredict_c &&
            (final_match0_c || final_match1_c) &&
            ((state_q == REC_ACTIVE) ||
             (final_match0_c && pending_match1_c));
    end

    assign branch_dispatch_allow_o = !external_global_recover_i &&
        (state_q == REC_ACTIVE) &&
        ((window_count_c < 2) || correct_release_c);
    assign dispatch_freeze_o = external_global_recover_i ||
        (state_q != REC_ACTIVE);
    // Non-BRU serial classes remain blocked behind any unresolved branch.
    // Rename may bypass this signal only for BRU while allow_o is asserted.
    assign serial_dispatch_block_o = external_global_recover_i ||
        (window_count_c != 0) || (state_q != REC_ACTIVE);
    assign branch_window_active_o = (window_count_c != 0) ||
        (state_q != REC_ACTIVE);
    assign branch_recovery_pending_o = state_q != REC_ACTIVE;
    assign recovery_pulse_o = !external_global_recover_i &&
        (state_q == REC_RECOVER);
    assign redirect_valid_o = !external_global_recover_i &&
        (state_q == REC_REDIRECT);
    assign redirect_o = redirect_q;
    assign debug_branch_final_seen_o = debug_branch_final_seen_q;
    assign debug_branch_commit_seen_o = debug_branch_commit_seen_q;
    assign pending_select_o = choose_new_pending_c;
    assign checkpoint_release_valid_o = correct_release_c;
    assign checkpoint_release_tag_o = correct_release_c ?
        final_branch_wb_c.rob_tag : '0;
    assign checkpoint_select_valid_o = choose_new_pending_c;
    assign checkpoint_select_tag_o = choose_new_pending_c ?
        final_branch_wb_c.rob_tag : '0;
    assign admission_error_o = admission_error_q;
    assign unexpected_branch_final_o = unexpected_branch_final_q;
    assign conservation_error_o = admission_error_q || unexpected_branch_final_q;

    always_ff @(posedge clk) begin : update_window
        logic [1:0] next_valid;
        bbus_ooo_rob_tag_t next_tag0, next_tag1;

        if (reset || external_global_recover_i) begin
            state_q <= REC_ACTIVE;
            window_valid_q <= 2'b00;
            window_tag0_q <= '0;
            window_tag1_q <= '0;
            pending_tag_q <= '0;
            pending_target_q <= '0;
            pending_reason_q <= BBUS_OOO_REDIRECT_NONE;
            redirect_q <= '0;
            admission_error_q <= 1'b0;
            unexpected_branch_final_q <= 1'b0;
            debug_branch_final_seen_q <= 1'b0;
            debug_branch_commit_seen_q <= 1'b0;
        end else begin
            debug_branch_final_seen_q <= final_branch_seen_c;
            debug_branch_commit_seen_q <= pending_commit_c;
            next_valid = window_valid_q;
            next_tag0 = window_tag0_q;
            next_tag1 = window_tag1_q;

            if (branch_issue_accept_i &&
                !((window_valid_q[0] &&
                   tag_match(branch_issue_rob_tag_i, window_tag0_q)) ||
                  (window_valid_q[1] &&
                   tag_match(branch_issue_rob_tag_i, window_tag1_q)))) begin
                admission_error_q <= 1'b1;
            end

            if (final_branch_seen_c && !(final_match0_c || final_match1_c) &&
                ((state_q == REC_ACTIVE) || (state_q == REC_PENDING))) begin
                unexpected_branch_final_q <= 1'b1;
            end

            if (final_branch_seen_c && !final_branch_mispredict_c) begin
                if (final_match0_c) begin
                    next_valid[0] = next_valid[1];
                    next_tag0 = next_tag1;
                    next_valid[1] = 1'b0;
                    next_tag1 = '0;
                end else if (final_match1_c) begin
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

            window_valid_q <= next_valid;
            window_tag0_q <= next_tag0;
            window_tag1_q <= next_tag1;

            if (choose_new_pending_c) begin
                pending_tag_q <= final_branch_wb_c.rob_tag;
                pending_target_q <= final_branch_wb_c.actual_nextpc;
                pending_reason_q <= redirect_reason(final_branch_wb_c);
                state_q <= REC_PENDING;
            end else unique case (state_q)
                REC_ACTIVE: begin
                    redirect_q <= '0;
                end
                REC_PENDING: begin
                    if (pending_commit_c) begin
                        redirect_q.valid <= 1'b1;
                        redirect_q.rob_tag <= pending_tag_q;
                        redirect_q.pc <= commit_event_i.slot0.pc;
                        redirect_q.reason <= pending_reason_q;
                        redirect_q.target <= pending_target_q;
                        state_q <= REC_RECOVER;
                    end
                end
                REC_RECOVER: state_q <= REC_REDIRECT;
                REC_REDIRECT: begin
                    if (redirect_ready_i) begin
                        state_q <= REC_ACTIVE;
                        window_valid_q <= 2'b00;
                        window_tag0_q <= '0;
                        window_tag1_q <= '0;
                        pending_tag_q <= '0;
                        redirect_q <= '0;
                    end
                end
                default: state_q <= REC_ACTIVE;
            endcase
        end
    end
endmodule
