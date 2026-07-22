`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_branch_execute #(
    parameter int LATENCY = 1,
    parameter bit ISSUE_COMPLETION_FALLTHROUGH_ENABLE = 1'b0
) (
    input  logic clk,
    input  logic reset,
    input  logic selective_kill_valid_i,
    input  logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_i,
    output logic selective_kill_drop_o,

    input  logic issue_valid_i,
    input  logic issue_completion_fallthrough_i,
    output logic issue_ready_o,
    input  bbus_ooo_branch_uop_t issue_uop_i,
    input  logic [`BBUS_OOO_XLEN-1:0] src1_data_i,
    input  logic [`BBUS_OOO_XLEN-1:0] src2_data_i,

    output logic completion_valid_o,
    input  logic completion_ready_i,
    output bbus_ooo_branch_completion_t completion_o,

    output logic redirect_valid_o,
    output bbus_ooo_redirect_t redirect_o,

    output logic debug_busy_o,
    output logic debug_completion_valid_o
);
    typedef enum logic [1:0] {
        BR_IDLE = 2'd0,
        BR_BUSY = 2'd1,
        BR_DONE = 2'd2
    } br_state_e;

    localparam int BR_CNT_W = $clog2(LATENCY + 1);

    br_state_e state_q;
    logic [BR_CNT_W-1:0] cnt_q;
    bbus_ooo_branch_completion_t completion_q;
    bbus_ooo_redirect_t redirect_q;

    logic issue_fire_c;
    logic actual_taken_c;
    logic [31:0] actual_target_c;
    logic mispredict_c;
    bbus_ooo_redirect_reason_e redirect_reason_c;
    bbus_ooo_branch_completion_t next_completion_c;
    bbus_ooo_redirect_t next_redirect_c;
    logic current_killed_c;
    logic direct_completion_c;

    assign current_killed_c = selective_kill_valid_i &&
        (state_q != BR_IDLE) && completion_q.rob_tag.valid &&
        selective_killed_rob_mask_i[completion_q.rob_tag.idx];
    assign selective_kill_drop_o = current_killed_c;
    assign issue_ready_o = !selective_kill_valid_i && (state_q == BR_IDLE);
    assign issue_fire_c = issue_valid_i && issue_ready_o && issue_uop_i.valid;
    assign direct_completion_c = ISSUE_COMPLETION_FALLTHROUGH_ENABLE &&
        issue_completion_fallthrough_i && (LATENCY <= 1) && issue_fire_c;
    assign completion_valid_o = !selective_kill_valid_i &&
        ((state_q == BR_DONE) || direct_completion_c);
    assign completion_o = direct_completion_c ? next_completion_c :
        completion_q;
    assign redirect_valid_o = completion_valid_o &&
        (direct_completion_c ? next_redirect_c.valid : redirect_q.valid);
    assign redirect_o = direct_completion_c ? next_redirect_c : redirect_q;
    assign debug_busy_o = (state_q == BR_BUSY);
    assign debug_completion_valid_o = completion_valid_o;

    always_comb begin
        actual_taken_c = 1'b0;
        unique case (issue_uop_i.br_op)
            BBUS_OOO_BR_BEQ : actual_taken_c = (src1_data_i == src2_data_i);
            BBUS_OOO_BR_BNE : actual_taken_c = (src1_data_i != src2_data_i);
            BBUS_OOO_BR_BLT : actual_taken_c = ($signed(src1_data_i) < $signed(src2_data_i));
            BBUS_OOO_BR_BGE : actual_taken_c = ($signed(src1_data_i) >= $signed(src2_data_i));
            BBUS_OOO_BR_BLTU: actual_taken_c = (src1_data_i < src2_data_i);
            BBUS_OOO_BR_BGEU: actual_taken_c = (src1_data_i >= src2_data_i);
            BBUS_OOO_BR_JAL : actual_taken_c = 1'b1;
            BBUS_OOO_BR_JALR: actual_taken_c = 1'b1;
            default         : actual_taken_c = 1'b0;
        endcase

        unique case (issue_uop_i.br_op)
            BBUS_OOO_BR_JAL: begin
                actual_target_c = issue_uop_i.pc + issue_uop_i.imm;
            end

            BBUS_OOO_BR_JALR: begin
                actual_target_c = (src1_data_i + issue_uop_i.imm) & ~32'd1;
            end

            default: begin
                actual_target_c = actual_taken_c ? (issue_uop_i.pc + issue_uop_i.imm)
                                                 : (issue_uop_i.pc + 32'd4);
            end
        endcase

        mispredict_c = (issue_uop_i.pred_taken != actual_taken_c) ||
            (issue_uop_i.pred_taken && actual_taken_c &&
             (issue_uop_i.pred_target != actual_target_c));

        unique case (issue_uop_i.br_op)
            BBUS_OOO_BR_JAL : redirect_reason_c = BBUS_OOO_REDIRECT_JAL;
            BBUS_OOO_BR_JALR: redirect_reason_c = BBUS_OOO_REDIRECT_JALR;
            default         : redirect_reason_c = BBUS_OOO_REDIRECT_BRANCH;
        endcase

        next_completion_c = '0;
        next_completion_c.valid = 1'b1;
        next_completion_c.rob_tag = issue_uop_i.rob_tag;
        next_completion_c.pc = issue_uop_i.pc;
        next_completion_c.br_op = issue_uop_i.br_op;
        next_completion_c.pred_taken = issue_uop_i.pred_taken;
        next_completion_c.pred_target = issue_uop_i.pred_target;
        next_completion_c.pred_source = issue_uop_i.pred_source;
        next_completion_c.pred_correlated = issue_uop_i.pred_correlated;
        next_completion_c.pred_base_taken = issue_uop_i.pred_base_taken;
        next_completion_c.pred_base_counter_valid =
            issue_uop_i.pred_base_counter_valid;
        next_completion_c.pred_base_counter_taken =
            issue_uop_i.pred_base_counter_taken;
        next_completion_c.pred_corr_candidate = issue_uop_i.pred_corr_candidate;
        next_completion_c.pred_corr_raw_candidate =
            issue_uop_i.pred_corr_raw_candidate;
        next_completion_c.pred_corr_chooser_prefer =
            issue_uop_i.pred_corr_chooser_prefer;
        next_completion_c.pred_corr_taken = issue_uop_i.pred_corr_taken;
        next_completion_c.pred_history = issue_uop_i.pred_history;
        next_completion_c.pred_local_history =
            issue_uop_i.pred_local_history;
        next_completion_c.pred_local_strong = issue_uop_i.pred_local_strong;
        next_completion_c.pred_local_taken = issue_uop_i.pred_local_taken;
        next_completion_c.pred_local_chooser_prefer =
            issue_uop_i.pred_local_chooser_prefer;
        next_completion_c.pred_local_chooser_strong =
            issue_uop_i.pred_local_chooser_strong;
        next_completion_c.pred_multihistory_hit =
            issue_uop_i.pred_multihistory_hit;
        next_completion_c.pred_multihistory_strong =
            issue_uop_i.pred_multihistory_strong;
        next_completion_c.pred_multihistory_taken =
            issue_uop_i.pred_multihistory_taken;
        next_completion_c.pred_multihistory_chooser_prefer =
            issue_uop_i.pred_multihistory_chooser_prefer;
        next_completion_c.pred_multihistory_chooser_strong =
            issue_uop_i.pred_multihistory_chooser_strong;
        next_completion_c.pred_ras_self_collision =
            issue_uop_i.pred_ras_self_collision;
        next_completion_c.actual_taken = actual_taken_c;
        next_completion_c.actual_target = actual_target_c;
        next_completion_c.mispredict = mispredict_c;
        next_completion_c.arch_rd = issue_uop_i.arch_rd;
        next_completion_c.phys_rd = issue_uop_i.phys_rd;
        next_completion_c.rf_wen = issue_uop_i.rf_wen;
        next_completion_c.link_wdata = issue_uop_i.pc + 32'd4;

        next_redirect_c = '0;
        next_redirect_c.valid = mispredict_c;
        next_redirect_c.rob_tag = issue_uop_i.rob_tag;
        next_redirect_c.pc = issue_uop_i.pc;
        next_redirect_c.reason = mispredict_c ? redirect_reason_c : BBUS_OOO_REDIRECT_NONE;
        next_redirect_c.target = actual_target_c;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state_q <= BR_IDLE;
            cnt_q <= '0;
            completion_q <= '0;
            redirect_q <= '0;
        end else if (selective_kill_valid_i) begin
            if (current_killed_c) begin
                state_q <= BR_IDLE;
                cnt_q <= '0;
                completion_q <= '0;
                redirect_q <= '0;
            end
        end else begin
            unique case (state_q)
                BR_IDLE: begin
                    if (issue_fire_c) begin
                        if (direct_completion_c && completion_ready_i) begin
                            completion_q <= '0;
                            redirect_q <= '0;
                        end else begin
                            completion_q <= next_completion_c;
                            redirect_q <= next_redirect_c;
                        end
                        if (direct_completion_c && completion_ready_i) begin
                            cnt_q <= '0;
                            state_q <= BR_IDLE;
                        end else if (LATENCY <= 1) begin
                            cnt_q <= '0;
                            state_q <= BR_DONE;
                        end else begin
                            cnt_q <= BR_CNT_W'(LATENCY - 1);
                            state_q <= BR_BUSY;
                        end
                    end
                end

                BR_BUSY: begin
                    if (cnt_q == BR_CNT_W'(1)) begin
                        cnt_q <= '0;
                        state_q <= BR_DONE;
                    end else begin
                        cnt_q <= cnt_q - BR_CNT_W'(1);
                    end
                end

                BR_DONE: begin
                    if (completion_ready_i) begin
                        completion_q <= '0;
                        redirect_q <= '0;
                        state_q <= BR_IDLE;
                    end
                end

                default: begin
                    cnt_q <= '0;
                    completion_q <= '0;
                    redirect_q <= '0;
                    state_q <= BR_IDLE;
                end
            endcase
        end
    end
endmodule
