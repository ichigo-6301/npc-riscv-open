`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// Synchronous control recovery sits above the existing branch controller.
// External recovery is highest priority; otherwise competing branch and
// synchronous-control ownership is resolved at ROB retirement age.
module ooo_pipeline_commit_control_recovery_1w (
    input  logic clk,
    input  logic reset,
    input  logic external_global_recover_i,

    input  logic [1:0] final_consume_mask_i,
    input  bbus_ooo_writeback_t final_wb0_i,
    input  bbus_ooo_writeback_t final_wb1_i,
    input  bbus_ooo_commit_event_t commit_event_i,
    input  logic [31:0] trap_target_i,
    input  logic [31:0] xret_target_i,

    input  logic branch_recovery_pulse_i,
    input  logic branch_redirect_valid_i,
    input  bbus_ooo_redirect_t branch_redirect_i,
    output logic branch_redirect_ready_o,
    output logic branch_cancel_o,
    output logic control_state_recovery_pulse_o,

    input  logic redirect_ready_i,
    output logic dispatch_freeze_o,
    output logic recovery_pending_o,
    output logic recovery_pulse_o,
    output logic redirect_valid_o,
    output bbus_ooo_redirect_t redirect_o,

    output logic control_final_seen_o,
    output logic control_commit_seen_o,
    output logic duplicate_control_error_o,
    output logic conservation_error_o
);
    typedef enum logic [1:0] {
        CTRL_IDLE,
        CTRL_PENDING,
        CTRL_RECOVER,
        CTRL_REDIRECT
    } control_state_e;

    typedef enum logic [1:0] {
        CTRL_KIND_NONE,
        CTRL_KIND_EXCEPTION,
        CTRL_KIND_SYSTEM
    } control_kind_e;

    control_state_e state_q;
    control_kind_e kind_q;
    bbus_ooo_rob_tag_t tag_q;
    bbus_ooo_redirect_t redirect_q;
    logic duplicate_control_error_q;

    logic control_final_seen_c;
    bbus_ooo_writeback_t control_final_wb_c;
    control_kind_e control_final_kind_c;
    logic control_commit_c;
    logic direct_exception_commit_c;
    logic branch_recovery_accept_c;

    function automatic logic tag_match(
        input bbus_ooo_rob_tag_t a,
        input bbus_ooo_rob_tag_t b
    );
        tag_match = a.valid && b.valid && (a.idx == b.idx) &&
            (a.gen == b.gen);
    endfunction

    function automatic control_kind_e wb_kind(input bbus_ooo_writeback_t wb);
        begin
            if (wb.exception.valid) begin
                wb_kind = CTRL_KIND_EXCEPTION;
            end else if (wb.is_system && (wb.redirect_valid || wb.is_control)) begin
                wb_kind = CTRL_KIND_SYSTEM;
            end else begin
                wb_kind = CTRL_KIND_NONE;
            end
        end
    endfunction

    function automatic logic is_control_wb(input bbus_ooo_writeback_t wb);
        is_control_wb = wb.valid && wb.done &&
            (wb.exception.valid ||
             (wb.is_system && wb.redirect_valid && wb.is_control));
    endfunction

    always_comb begin
        control_final_seen_c = 1'b0;
        control_final_wb_c = '0;
        if (final_consume_mask_i[0] && is_control_wb(final_wb0_i)) begin
            control_final_seen_c = 1'b1;
            control_final_wb_c = final_wb0_i;
        end else if (final_consume_mask_i[1] && is_control_wb(final_wb1_i)) begin
            control_final_seen_c = 1'b1;
            control_final_wb_c = final_wb1_i;
        end
    end

    assign control_final_kind_c = wb_kind(control_final_wb_c);
    assign direct_exception_commit_c =
        (state_q == CTRL_IDLE) &&
        commit_event_i.control_event_valid &&
        (commit_event_i.control_event == BBUS_OOO_CTRL_EXCEPTION) &&
        commit_event_i.slot0.valid;

    always_comb begin
        control_commit_c = 1'b0;
        if (kind_q == CTRL_KIND_EXCEPTION) begin
            control_commit_c = commit_event_i.control_event_valid &&
                (commit_event_i.control_event == BBUS_OOO_CTRL_EXCEPTION) &&
                tag_match(commit_event_i.slot0.rob_tag, tag_q);
        end else if (kind_q == CTRL_KIND_SYSTEM) begin
            control_commit_c = commit_event_i.normal_commit_mask[0] &&
                tag_match(commit_event_i.slot0.rob_tag, tag_q);
        end
    end

    // A final-consumed control completion only establishes pending ownership.
    // Recovery priority is decided at retirement age: if an older branch has
    // reached its commit-age pulse while a younger exception/system packet is
    // pending, the branch must recover and discard that younger ownership.
    assign branch_recovery_accept_c = branch_recovery_pulse_i &&
        (state_q != CTRL_RECOVER) && (state_q != CTRL_REDIRECT);
    assign branch_cancel_o = external_global_recover_i ||
        direct_exception_commit_c ||
        (state_q == CTRL_RECOVER) || (state_q == CTRL_REDIRECT);
    assign control_state_recovery_pulse_o = !external_global_recover_i &&
        (state_q == CTRL_RECOVER);
    assign branch_redirect_ready_o = !branch_cancel_o && redirect_ready_i;
    assign dispatch_freeze_o = external_global_recover_i ||
        control_final_seen_c || direct_exception_commit_c ||
        (state_q != CTRL_IDLE);
    assign recovery_pending_o = dispatch_freeze_o;
    assign recovery_pulse_o = !external_global_recover_i &&
        ((state_q == CTRL_RECOVER) ||
         branch_recovery_accept_c);
    assign redirect_valid_o = !external_global_recover_i &&
        ((state_q == CTRL_REDIRECT) ||
         (!direct_exception_commit_c &&
          (state_q != CTRL_RECOVER) && (state_q != CTRL_REDIRECT) &&
          branch_redirect_valid_i));
    assign redirect_o = (state_q == CTRL_REDIRECT) ? redirect_q :
        branch_redirect_i;
    assign control_final_seen_o = control_final_seen_c;
    assign control_commit_seen_o = control_commit_c || direct_exception_commit_c;
    assign duplicate_control_error_o = duplicate_control_error_q;
    assign conservation_error_o = duplicate_control_error_q;

    always_ff @(posedge clk) begin
        if (reset || external_global_recover_i) begin
            state_q <= CTRL_IDLE;
            kind_q <= CTRL_KIND_NONE;
            tag_q <= '0;
            redirect_q <= '0;
            duplicate_control_error_q <= 1'b0;
        end else begin
            if (control_final_seen_c && (state_q != CTRL_IDLE)) begin
                duplicate_control_error_q <= 1'b1;
            end

            if (branch_recovery_accept_c) begin
                // The committing branch is older than any pending control
                // completion. Its global recovery invalidates that ownership.
                state_q <= CTRL_IDLE;
                kind_q <= CTRL_KIND_NONE;
                tag_q <= '0;
                redirect_q <= '0;
            end else unique case (state_q)
                CTRL_IDLE: begin
                    redirect_q <= '0;
                    if (direct_exception_commit_c) begin
                        kind_q <= CTRL_KIND_EXCEPTION;
                        tag_q <= commit_event_i.slot0.rob_tag;
                        redirect_q.valid <= 1'b1;
                        redirect_q.rob_tag <= commit_event_i.slot0.rob_tag;
                        redirect_q.pc <= commit_event_i.slot0.pc;
                        redirect_q.reason <= BBUS_OOO_REDIRECT_EXCEPTION;
                        redirect_q.target <= trap_target_i;
                        state_q <= CTRL_RECOVER;
                    end else if (control_final_seen_c) begin
                        kind_q <= control_final_kind_c;
                        tag_q <= control_final_wb_c.rob_tag;
                        state_q <= CTRL_PENDING;
                    end
                end

                CTRL_PENDING: begin
                    if (control_commit_c) begin
                        redirect_q.valid <= 1'b1;
                        redirect_q.rob_tag <= tag_q;
                        redirect_q.pc <= commit_event_i.slot0.pc;
                        redirect_q.reason <= BBUS_OOO_REDIRECT_EXCEPTION;
                        redirect_q.target <=
                            ((commit_event_i.slot0.instr == 32'h3020_0073) ||
                             (commit_event_i.slot0.instr == 32'h1020_0073)) ?
                            xret_target_i :
                            ((commit_event_i.slot0.instr == 32'h0000_100f) ||
                             ((commit_event_i.slot0.instr & 32'hfe00_7fff) ==
                              32'h1200_0073)) ?
                            (commit_event_i.slot0.pc + 32'd4) :
                            trap_target_i;
                        state_q <= CTRL_RECOVER;
                    end
                end

                CTRL_RECOVER: begin
                    state_q <= CTRL_REDIRECT;
                end

                CTRL_REDIRECT: begin
                    if (redirect_ready_i) begin
                        state_q <= CTRL_IDLE;
                        kind_q <= CTRL_KIND_NONE;
                        tag_q <= '0;
                        redirect_q <= '0;
                    end
                end

                default: state_q <= CTRL_IDLE;
            endcase
        end
    end
endmodule
