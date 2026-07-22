`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// Standalone P8 adapter around the production-shared branch executor.
// It deliberately keeps prediction local: this pre-frontend slice always
// predicts not taken and exposes a normal serial writeback packet.
module ooo_branch_pipeline_1w #(
    parameter bit ISSUE_COMPLETION_FALLTHROUGH_ENABLE = 1'b0
) (
    input  logic clk,
    input  logic reset,
    input  logic flush_i,
    input  logic selective_kill_valid_i,
    input  logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_i,

    input  logic issue_valid_i,
    input  logic issue_completion_fallthrough_i,
    input  bbus_ooo_alu_iq_uop_t issue_uop_i,
    input  logic [31:0] src1_data_i,
    input  logic [31:0] src2_data_i,
    output logic issue_ready_o,
    output logic issue_accept_o,

    output bbus_ooo_writeback_t completion_wb_o,
    output logic completion_valid_o,
    input  logic completion_ready_i,

    output logic predictor_update_valid_o,
    output logic [31:0] predictor_update_pc_o,
    output logic [31:0] predictor_update_direct_target_o,
    output bbus_ooo_pred_history_t predictor_update_history_o,
    output logic predictor_update_base_taken_o,
    output logic predictor_update_base_counter_valid_o,
    output logic predictor_update_base_counter_taken_o,
    output logic predictor_update_correlated_candidate_o,
    output logic predictor_update_correlated_raw_candidate_o,
    output logic predictor_update_correlated_chooser_prefer_o,
    output logic predictor_update_correlated_taken_o,
    output bbus_ooo_local_history_t predictor_update_local_history_o,
    output logic predictor_update_local_strong_o,
    output logic predictor_update_local_taken_o,
    output logic predictor_update_local_chooser_prefer_o,
    output logic predictor_update_local_chooser_strong_o,
    output bbus_ooo_multihistory_mask_t predictor_update_multihistory_hit_o,
    output bbus_ooo_multihistory_mask_t predictor_update_multihistory_strong_o,
    output bbus_ooo_multihistory_mask_t predictor_update_multihistory_taken_o,
    output bbus_ooo_multihistory_mask_t
        predictor_update_multihistory_chooser_prefer_o,
    output bbus_ooo_multihistory_mask_t
        predictor_update_multihistory_chooser_strong_o,
    output logic predictor_update_current_taken_o,
    output logic predictor_update_taken_o,
    output logic predictor_history_recover_valid_o,
    output bbus_ooo_pred_history_t predictor_history_recover_snapshot_o,
    output logic predictor_history_recover_conditional_o,
    output logic predictor_history_recover_taken_o,
    output logic indirect_update_valid_o,
    output logic [31:0] indirect_update_pc_o,
    output logic [31:0] indirect_update_target_o,
    output logic [7:0] perf_predictor_o,
    output logic perf_ras_self_collision_o,

    output logic occupied_o,
    output logic flush_drop_o,
    output logic selective_kill_drop_o,
    output logic illegal_issue_o
);
    logic executor_reset;
    logic legal_issue_c;
    logic executor_issue_ready;
    logic executor_completion_valid;
    logic executor_redirect_valid;
    logic executor_busy;
    logic executor_completion_debug;
    logic target_misaligned_c;
    bbus_ooo_branch_uop_t executor_issue_uop;
    bbus_ooo_branch_completion_t executor_completion;
    bbus_ooo_redirect_t executor_redirect;
    logic [31:0] direct_target_q;
    logic executor_selective_drop;

    always_comb begin
        legal_issue_c = issue_uop_i.valid &&
            (issue_uop_i.fu_type == BBUS_OOO_FU_BRU) &&
            !issue_uop_i.is_load && !issue_uop_i.is_store &&
            !issue_uop_i.is_csr && !issue_uop_i.is_system &&
            !issue_uop_i.exception.valid;

        executor_issue_uop = '0;
        executor_issue_uop.valid = legal_issue_c;
        executor_issue_uop.rob_tag = issue_uop_i.rob_tag;
        executor_issue_uop.pc = issue_uop_i.pc;
        executor_issue_uop.instr = issue_uop_i.instr;
        executor_issue_uop.br_op = issue_uop_i.branch_op;
        executor_issue_uop.imm = issue_uop_i.imm;
        executor_issue_uop.pred_taken = issue_uop_i.pred_taken;
        executor_issue_uop.pred_target = issue_uop_i.pred_target;
        executor_issue_uop.pred_source = issue_uop_i.pred_source;
        executor_issue_uop.pred_correlated = issue_uop_i.pred_correlated;
        executor_issue_uop.pred_base_taken = issue_uop_i.pred_base_taken;
        executor_issue_uop.pred_base_counter_valid =
            issue_uop_i.pred_base_counter_valid;
        executor_issue_uop.pred_base_counter_taken =
            issue_uop_i.pred_base_counter_taken;
        executor_issue_uop.pred_corr_candidate = issue_uop_i.pred_corr_candidate;
        executor_issue_uop.pred_corr_raw_candidate =
            issue_uop_i.pred_corr_raw_candidate;
        executor_issue_uop.pred_corr_chooser_prefer =
            issue_uop_i.pred_corr_chooser_prefer;
        executor_issue_uop.pred_corr_taken = issue_uop_i.pred_corr_taken;
        executor_issue_uop.pred_history = issue_uop_i.pred_history;
        executor_issue_uop.pred_local_history =
            issue_uop_i.pred_local_history;
        executor_issue_uop.pred_local_strong = issue_uop_i.pred_local_strong;
        executor_issue_uop.pred_local_taken = issue_uop_i.pred_local_taken;
        executor_issue_uop.pred_local_chooser_prefer =
            issue_uop_i.pred_local_chooser_prefer;
        executor_issue_uop.pred_local_chooser_strong =
            issue_uop_i.pred_local_chooser_strong;
        executor_issue_uop.pred_multihistory_hit =
            issue_uop_i.pred_multihistory_hit;
        executor_issue_uop.pred_multihistory_strong =
            issue_uop_i.pred_multihistory_strong;
        executor_issue_uop.pred_multihistory_taken =
            issue_uop_i.pred_multihistory_taken;
        executor_issue_uop.pred_multihistory_chooser_prefer =
            issue_uop_i.pred_multihistory_chooser_prefer;
        executor_issue_uop.pred_multihistory_chooser_strong =
            issue_uop_i.pred_multihistory_chooser_strong;
        executor_issue_uop.pred_ras_self_collision =
            issue_uop_i.pred_ras_self_collision;
        executor_issue_uop.arch_rd = issue_uop_i.arch_rd;
        executor_issue_uop.phys_rd = issue_uop_i.phys_rd_new;
        executor_issue_uop.rf_wen = issue_uop_i.rf_wen;

        target_misaligned_c = executor_completion.valid &&
            executor_completion.actual_taken && executor_completion.actual_target[1];

        completion_wb_o = '0;
        completion_wb_o.valid = executor_completion.valid;
        completion_wb_o.rob_tag = executor_completion.rob_tag;
        completion_wb_o.phys_rd = executor_completion.phys_rd;
        completion_wb_o.rf_wen = executor_completion.rf_wen &&
            !target_misaligned_c;
        completion_wb_o.result = executor_completion.link_wdata;
        completion_wb_o.done = executor_completion.valid;
        completion_wb_o.is_control = executor_completion.valid &&
            !target_misaligned_c;
        completion_wb_o.is_branch = executor_completion.valid &&
            !target_misaligned_c &&
            (executor_completion.br_op != BBUS_OOO_BR_JAL) &&
            (executor_completion.br_op != BBUS_OOO_BR_JALR);
        completion_wb_o.is_jal = executor_completion.valid &&
            !target_misaligned_c &&
            (executor_completion.br_op == BBUS_OOO_BR_JAL);
        completion_wb_o.is_jalr = executor_completion.valid &&
            !target_misaligned_c &&
            (executor_completion.br_op == BBUS_OOO_BR_JALR);
        completion_wb_o.actual_taken = executor_completion.actual_taken;
        completion_wb_o.actual_nextpc = executor_completion.actual_target;
        completion_wb_o.redirect_valid = executor_completion.mispredict &&
            !target_misaligned_c;
        completion_wb_o.exception.valid = target_misaligned_c;
        completion_wb_o.exception.cause = target_misaligned_c ? 32'd0 : 32'b0;
        completion_wb_o.exception.tval = target_misaligned_c ?
            executor_completion.actual_target : 32'b0;

        illegal_issue_o = issue_valid_i && !legal_issue_c && !flush_i;
    end

    assign executor_reset = reset || flush_i;
    assign issue_ready_o = !flush_i && !selective_kill_valid_i &&
        legal_issue_c && executor_issue_ready;
    assign issue_accept_o = issue_valid_i && issue_ready_o;
    assign completion_valid_o = !flush_i && !selective_kill_valid_i &&
        executor_completion_valid;
    assign predictor_update_valid_o = completion_valid_o && completion_ready_i &&
        (executor_completion.br_op != BBUS_OOO_BR_JAL) &&
        (executor_completion.br_op != BBUS_OOO_BR_JALR);
    assign predictor_update_pc_o = executor_completion.pc;
    assign predictor_update_direct_target_o =
        (ISSUE_COMPLETION_FALLTHROUGH_ENABLE &&
         issue_completion_fallthrough_i && issue_accept_o &&
         completion_valid_o) ? (issue_uop_i.pc + issue_uop_i.imm) :
        direct_target_q;
    assign predictor_update_history_o = executor_completion.pred_history;
    assign predictor_update_base_taken_o =
        executor_completion.pred_base_taken;
    assign predictor_update_base_counter_valid_o =
        executor_completion.pred_base_counter_valid;
    assign predictor_update_base_counter_taken_o =
        executor_completion.pred_base_counter_taken;
    assign predictor_update_correlated_candidate_o =
        executor_completion.pred_corr_candidate;
    assign predictor_update_correlated_raw_candidate_o =
        executor_completion.pred_corr_raw_candidate;
    assign predictor_update_correlated_chooser_prefer_o =
        executor_completion.pred_corr_chooser_prefer;
    assign predictor_update_correlated_taken_o =
        executor_completion.pred_corr_taken;
    assign predictor_update_local_history_o =
        executor_completion.pred_local_history;
    assign predictor_update_local_strong_o =
        executor_completion.pred_local_strong;
    assign predictor_update_local_taken_o =
        executor_completion.pred_local_taken;
    assign predictor_update_local_chooser_prefer_o =
        executor_completion.pred_local_chooser_prefer;
    assign predictor_update_local_chooser_strong_o =
        executor_completion.pred_local_chooser_strong;
    assign predictor_update_multihistory_hit_o =
        executor_completion.pred_multihistory_hit;
    assign predictor_update_multihistory_strong_o =
        executor_completion.pred_multihistory_strong;
    assign predictor_update_multihistory_taken_o =
        executor_completion.pred_multihistory_taken;
    assign predictor_update_multihistory_chooser_prefer_o =
        executor_completion.pred_multihistory_chooser_prefer;
    assign predictor_update_multihistory_chooser_strong_o =
        executor_completion.pred_multihistory_chooser_strong;
    assign predictor_update_current_taken_o = executor_completion.pred_taken;
    assign predictor_update_taken_o = executor_completion.actual_taken;
    assign predictor_history_recover_valid_o = completion_valid_o &&
        completion_ready_i &&
        (executor_completion.mispredict || target_misaligned_c);
    assign predictor_history_recover_snapshot_o =
        executor_completion.pred_history;
    assign predictor_history_recover_conditional_o =
        (executor_completion.br_op != BBUS_OOO_BR_JAL) &&
        (executor_completion.br_op != BBUS_OOO_BR_JALR);
    assign predictor_history_recover_taken_o =
        executor_completion.actual_taken;
    assign indirect_update_valid_o = completion_valid_o && completion_ready_i &&
        (executor_completion.br_op == BBUS_OOO_BR_JALR);
    assign indirect_update_pc_o = executor_completion.pc;
    assign indirect_update_target_o = executor_completion.actual_target;
    assign perf_predictor_o = {
        executor_completion.pred_correlated,
        executor_completion.mispredict,
        executor_completion.actual_taken,
        executor_completion.pred_taken,
        executor_completion.pred_source,
        completion_valid_o && completion_ready_i
    };
    assign perf_ras_self_collision_o = completion_valid_o &&
        completion_ready_i && executor_completion.pred_ras_self_collision;
    assign occupied_o = executor_busy || executor_completion_valid;
    assign flush_drop_o = flush_i && occupied_o;
    assign selective_kill_drop_o = executor_selective_drop;

    always_ff @(posedge clk) begin
        if (reset || flush_i) begin
            direct_target_q <= 32'b0;
        end else if (selective_kill_valid_i) begin
            if (executor_selective_drop) direct_target_q <= 32'b0;
        end else if (issue_accept_o) begin
            direct_target_q <= issue_uop_i.pc + issue_uop_i.imm;
        end
    end

    ooo_branch_execute #(
        .ISSUE_COMPLETION_FALLTHROUGH_ENABLE(
            ISSUE_COMPLETION_FALLTHROUGH_ENABLE)
    ) u_executor (
        .clk(clk),
        .reset(executor_reset),
        .selective_kill_valid_i(selective_kill_valid_i),
        .selective_killed_rob_mask_i(selective_killed_rob_mask_i),
        .selective_kill_drop_o(executor_selective_drop),
        .issue_valid_i(issue_valid_i && legal_issue_c && !flush_i),
        .issue_completion_fallthrough_i(issue_completion_fallthrough_i),
        .issue_ready_o(executor_issue_ready),
        .issue_uop_i(executor_issue_uop),
        .src1_data_i(src1_data_i),
        .src2_data_i(src2_data_i),
        .completion_valid_o(executor_completion_valid),
        .completion_ready_i(completion_ready_i && !flush_i),
        .completion_o(executor_completion),
        .redirect_valid_o(executor_redirect_valid),
        .redirect_o(executor_redirect),
        .debug_busy_o(executor_busy),
        .debug_completion_valid_o(executor_completion_debug)
    );
endmodule
