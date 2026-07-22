`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module rename_prf_core (
    input  logic clk,
    input  logic reset,

    input  logic [1:0] decode_valid_mask_i,
    input  bbus_ooo_decode_uop_t decode_uop0_i,
    input  bbus_ooo_decode_uop_t decode_uop1_i,
    input  logic [1:0] dispatch_slots_available_i,

    output logic [1:0] rename_fire_mask_o,
    output bbus_ooo_renamed_uop_t renamed_uop0_o,
    output bbus_ooo_renamed_uop_t renamed_uop1_o,

    input  bbus_ooo_commit_event_t commit_event_i,

    input  logic wb_ready_valid_i,
    input  bbus_ooo_phys_reg_t wb_ready_phys_i,
    input  logic wb_ready1_valid_i,
    input  bbus_ooo_phys_reg_t wb_ready1_phys_i,

    input  bbus_ooo_arch_reg_t debug_arch_idx_i,
    input  bbus_ooo_phys_reg_t debug_phys_idx_i,
    output bbus_ooo_phys_reg_t debug_rat_phys_o,
    output bbus_ooo_phys_reg_t debug_rrat_phys_o,
    output logic debug_ready_o,
    output logic [6:0] debug_free_count_o,
    output bbus_ooo_phys_reg_t debug_next_free_phys_o,
    output logic debug_commit2_rrat_update2_o,
    output logic debug_commit2_freelist_release2_o,
    output logic debug_commit2_same_rd_waw_o,
    output logic debug_commit2_duplicate_release_bug_o
);
    bbus_ooo_phys_reg_t rat_q [`BBUS_OOO_ARCH_REGS-1:0];
    bbus_ooo_phys_reg_t rrat_q [`BBUS_OOO_ARCH_REGS-1:0];
    logic ready_q [`BBUS_OOO_PHYS_REGS-1:0];

    bbus_ooo_phys_reg_t free_phys0;
    bbus_ooo_phys_reg_t free_phys1;
    logic [1:0] free_avail_count;
    logic [1:0] freelist_alloc_mask;

    logic release0_valid;
    logic release1_valid;
    logic release0_valid_raw;
    logic release1_valid_raw;
    logic release_duplicate_bug;
    logic exception_rollback;
    bbus_ooo_phys_reg_t release0_phys;
    bbus_ooo_phys_reg_t release1_phys;

    bbus_ooo_freelist u_freelist (
        .clk(clk),
        .reset(reset),
        .alloc_fire_mask_i(freelist_alloc_mask),
        .alloc_phys0_o(free_phys0),
        .alloc_phys1_o(free_phys1),
        .alloc_avail_count_o(free_avail_count),
        .release0_valid_i(release0_valid),
        .release0_phys_i(release0_phys),
        .release1_valid_i(release1_valid),
        .release1_phys_i(release1_phys),
        .debug_free_count_o(debug_free_count_o),
        .debug_next_phys_o(debug_next_free_phys_o)
    );

    function automatic logic needs_phys(input bbus_ooo_decode_uop_t u);
        begin
            needs_phys = u.valid && u.rf_wen && (u.arch_rd != 5'd0) && !u.exception.valid;
        end
    endfunction

    function automatic logic source_ready(input logic uses_src, input bbus_ooo_arch_reg_t arch, input bbus_ooo_phys_reg_t phys);
        begin
            source_ready = !uses_src || (arch == 5'd0) || (phys == `BBUS_OOO_PHYS_ZERO) || ready_q[phys];
        end
    endfunction

    logic slot0_needs_phys;
    logic slot1_needs_phys;
    logic slot0_can_fire;
    logic slot1_can_fire;
    logic [1:0] phys_needed_for_two;

    bbus_ooo_renamed_uop_t renamed0_c;
    bbus_ooo_renamed_uop_t renamed1_c;

    always_comb begin
        bbus_ooo_phys_reg_t slot1_rs1_phys_pre;
        bbus_ooo_phys_reg_t slot1_rs2_phys_pre;
        logic slot1_rs1_ready_pre;
        logic slot1_rs2_ready_pre;

        renamed0_c = '0;
        renamed1_c = '0;

        slot0_needs_phys = needs_phys(decode_uop0_i) && decode_valid_mask_i[0];
        slot1_needs_phys = needs_phys(decode_uop1_i) && decode_valid_mask_i[1] && decode_valid_mask_i[0];
        phys_needed_for_two = {1'b0, slot0_needs_phys} + {1'b0, slot1_needs_phys};

        slot0_can_fire =
            decode_valid_mask_i[0] &&
            (dispatch_slots_available_i >= 2'd1) &&
            (!slot0_needs_phys || (free_avail_count >= 2'd1));

        slot1_can_fire =
            slot0_can_fire &&
            decode_valid_mask_i[1] &&
            (dispatch_slots_available_i >= 2'd2) &&
            (free_avail_count >= phys_needed_for_two);

        rename_fire_mask_o = {slot1_can_fire, slot0_can_fire};
        freelist_alloc_mask = {
            slot1_can_fire && slot1_needs_phys,
            slot0_can_fire && slot0_needs_phys
        };

        renamed0_c.valid = slot0_can_fire;
        renamed0_c.pc = decode_uop0_i.pc;
        renamed0_c.instr = decode_uop0_i.instr;
        renamed0_c.branch_window_line = decode_uop0_i.branch_window_line;
        renamed0_c.branch_window_line_word1 =
            decode_uop0_i.branch_window_line_word1;
        renamed0_c.arch_rs1 = decode_uop0_i.arch_rs1;
        renamed0_c.arch_rs2 = decode_uop0_i.arch_rs2;
        renamed0_c.arch_rd = decode_uop0_i.arch_rd;
        renamed0_c.uses_rs1 = decode_uop0_i.uses_rs1;
        renamed0_c.uses_rs2 = decode_uop0_i.uses_rs2;
        renamed0_c.rf_wen = slot0_needs_phys;
        renamed0_c.fu_type = decode_uop0_i.fu_type;
        renamed0_c.branch_op = decode_uop0_i.branch_op;
        renamed0_c.pred_taken = decode_uop0_i.pred_taken;
        renamed0_c.pred_target = decode_uop0_i.pred_target;
        renamed0_c.pred_source = decode_uop0_i.pred_source;
        renamed0_c.pred_correlated = decode_uop0_i.pred_correlated;
        renamed0_c.pred_base_taken = decode_uop0_i.pred_base_taken;
        renamed0_c.pred_base_counter_valid =
            decode_uop0_i.pred_base_counter_valid;
        renamed0_c.pred_base_counter_taken =
            decode_uop0_i.pred_base_counter_taken;
        renamed0_c.pred_corr_candidate = decode_uop0_i.pred_corr_candidate;
        renamed0_c.pred_corr_raw_candidate =
            decode_uop0_i.pred_corr_raw_candidate;
        renamed0_c.pred_corr_chooser_prefer =
            decode_uop0_i.pred_corr_chooser_prefer;
        renamed0_c.pred_corr_taken = decode_uop0_i.pred_corr_taken;
        renamed0_c.pred_history = decode_uop0_i.pred_history;
        renamed0_c.pred_local_history = decode_uop0_i.pred_local_history;
        renamed0_c.pred_local_strong = decode_uop0_i.pred_local_strong;
        renamed0_c.pred_local_taken = decode_uop0_i.pred_local_taken;
        renamed0_c.pred_local_chooser_prefer =
            decode_uop0_i.pred_local_chooser_prefer;
        renamed0_c.pred_local_chooser_strong =
            decode_uop0_i.pred_local_chooser_strong;
        renamed0_c.pred_multihistory_hit =
            decode_uop0_i.pred_multihistory_hit;
        renamed0_c.pred_multihistory_strong =
            decode_uop0_i.pred_multihistory_strong;
        renamed0_c.pred_multihistory_taken =
            decode_uop0_i.pred_multihistory_taken;
        renamed0_c.pred_multihistory_chooser_prefer =
            decode_uop0_i.pred_multihistory_chooser_prefer;
        renamed0_c.pred_multihistory_chooser_strong =
            decode_uop0_i.pred_multihistory_chooser_strong;
        renamed0_c.pred_ras_self_collision =
            decode_uop0_i.pred_ras_self_collision;
        renamed0_c.alu_op = decode_uop0_i.alu_op;
        renamed0_c.mdu_op = decode_uop0_i.mdu_op;
        renamed0_c.atomic_op = decode_uop0_i.atomic_op;
        renamed0_c.aq = decode_uop0_i.aq;
        renamed0_c.rl = decode_uop0_i.rl;
        renamed0_c.src1_is_pc = decode_uop0_i.src1_is_pc;
        renamed0_c.src2_is_imm = decode_uop0_i.src2_is_imm;
        renamed0_c.imm = decode_uop0_i.imm;
        renamed0_c.is_load = decode_uop0_i.is_load;
        renamed0_c.is_store = decode_uop0_i.is_store;
        renamed0_c.mem_op = decode_uop0_i.mem_op;
        renamed0_c.is_csr = decode_uop0_i.is_csr;
        renamed0_c.is_system = decode_uop0_i.is_system;
        renamed0_c.is_ebreak = decode_uop0_i.is_ebreak;
        renamed0_c.csr_addr = decode_uop0_i.csr_addr;
        renamed0_c.unsupported_class = decode_uop0_i.unsupported_class;
        renamed0_c.exception = decode_uop0_i.exception;
        renamed0_c.phys_rs1 = decode_uop0_i.uses_rs1 ? rat_q[decode_uop0_i.arch_rs1] : `BBUS_OOO_PHYS_ZERO;
        renamed0_c.phys_rs2 = decode_uop0_i.uses_rs2 ? rat_q[decode_uop0_i.arch_rs2] : `BBUS_OOO_PHYS_ZERO;
        renamed0_c.src1_ready = source_ready(decode_uop0_i.uses_rs1, decode_uop0_i.arch_rs1, renamed0_c.phys_rs1);
        renamed0_c.src2_ready = source_ready(decode_uop0_i.uses_rs2, decode_uop0_i.arch_rs2, renamed0_c.phys_rs2);
        renamed0_c.phys_rd_old = slot0_needs_phys ? rat_q[decode_uop0_i.arch_rd] : `BBUS_OOO_PHYS_ZERO;
        renamed0_c.phys_rd_new = slot0_needs_phys ? free_phys0 : `BBUS_OOO_PHYS_ZERO;

        slot1_rs1_phys_pre = decode_uop1_i.uses_rs1 ? rat_q[decode_uop1_i.arch_rs1] : `BBUS_OOO_PHYS_ZERO;
        slot1_rs2_phys_pre = decode_uop1_i.uses_rs2 ? rat_q[decode_uop1_i.arch_rs2] : `BBUS_OOO_PHYS_ZERO;
        slot1_rs1_ready_pre = source_ready(decode_uop1_i.uses_rs1, decode_uop1_i.arch_rs1, slot1_rs1_phys_pre);
        slot1_rs2_ready_pre = source_ready(decode_uop1_i.uses_rs2, decode_uop1_i.arch_rs2, slot1_rs2_phys_pre);

        renamed1_c.valid = slot1_can_fire;
        renamed1_c.pc = decode_uop1_i.pc;
        renamed1_c.instr = decode_uop1_i.instr;
        renamed1_c.branch_window_line = decode_uop1_i.branch_window_line;
        renamed1_c.branch_window_line_word1 =
            decode_uop1_i.branch_window_line_word1;
        renamed1_c.arch_rs1 = decode_uop1_i.arch_rs1;
        renamed1_c.arch_rs2 = decode_uop1_i.arch_rs2;
        renamed1_c.arch_rd = decode_uop1_i.arch_rd;
        renamed1_c.uses_rs1 = decode_uop1_i.uses_rs1;
        renamed1_c.uses_rs2 = decode_uop1_i.uses_rs2;
        renamed1_c.rf_wen = slot1_needs_phys;
        renamed1_c.fu_type = decode_uop1_i.fu_type;
        renamed1_c.branch_op = decode_uop1_i.branch_op;
        renamed1_c.pred_taken = decode_uop1_i.pred_taken;
        renamed1_c.pred_target = decode_uop1_i.pred_target;
        renamed1_c.pred_source = decode_uop1_i.pred_source;
        renamed1_c.pred_correlated = decode_uop1_i.pred_correlated;
        renamed1_c.pred_base_taken = decode_uop1_i.pred_base_taken;
        renamed1_c.pred_base_counter_valid =
            decode_uop1_i.pred_base_counter_valid;
        renamed1_c.pred_base_counter_taken =
            decode_uop1_i.pred_base_counter_taken;
        renamed1_c.pred_corr_candidate = decode_uop1_i.pred_corr_candidate;
        renamed1_c.pred_corr_raw_candidate =
            decode_uop1_i.pred_corr_raw_candidate;
        renamed1_c.pred_corr_chooser_prefer =
            decode_uop1_i.pred_corr_chooser_prefer;
        renamed1_c.pred_corr_taken = decode_uop1_i.pred_corr_taken;
        renamed1_c.pred_history = decode_uop1_i.pred_history;
        renamed1_c.pred_local_history = decode_uop1_i.pred_local_history;
        renamed1_c.pred_local_strong = decode_uop1_i.pred_local_strong;
        renamed1_c.pred_local_taken = decode_uop1_i.pred_local_taken;
        renamed1_c.pred_local_chooser_prefer =
            decode_uop1_i.pred_local_chooser_prefer;
        renamed1_c.pred_local_chooser_strong =
            decode_uop1_i.pred_local_chooser_strong;
        renamed1_c.pred_multihistory_hit =
            decode_uop1_i.pred_multihistory_hit;
        renamed1_c.pred_multihistory_strong =
            decode_uop1_i.pred_multihistory_strong;
        renamed1_c.pred_multihistory_taken =
            decode_uop1_i.pred_multihistory_taken;
        renamed1_c.pred_multihistory_chooser_prefer =
            decode_uop1_i.pred_multihistory_chooser_prefer;
        renamed1_c.pred_multihistory_chooser_strong =
            decode_uop1_i.pred_multihistory_chooser_strong;
        renamed1_c.pred_ras_self_collision =
            decode_uop1_i.pred_ras_self_collision;
        renamed1_c.alu_op = decode_uop1_i.alu_op;
        renamed1_c.mdu_op = decode_uop1_i.mdu_op;
        renamed1_c.atomic_op = decode_uop1_i.atomic_op;
        renamed1_c.aq = decode_uop1_i.aq;
        renamed1_c.rl = decode_uop1_i.rl;
        renamed1_c.src1_is_pc = decode_uop1_i.src1_is_pc;
        renamed1_c.src2_is_imm = decode_uop1_i.src2_is_imm;
        renamed1_c.imm = decode_uop1_i.imm;
        renamed1_c.is_load = decode_uop1_i.is_load;
        renamed1_c.is_store = decode_uop1_i.is_store;
        renamed1_c.mem_op = decode_uop1_i.mem_op;
        renamed1_c.is_csr = decode_uop1_i.is_csr;
        renamed1_c.is_system = decode_uop1_i.is_system;
        renamed1_c.is_ebreak = decode_uop1_i.is_ebreak;
        renamed1_c.csr_addr = decode_uop1_i.csr_addr;
        renamed1_c.unsupported_class = decode_uop1_i.unsupported_class;
        renamed1_c.exception = decode_uop1_i.exception;
        renamed1_c.phys_rs1 = slot1_rs1_phys_pre;
        renamed1_c.phys_rs2 = slot1_rs2_phys_pre;
        renamed1_c.src1_ready = slot1_rs1_ready_pre;
        renamed1_c.src2_ready = slot1_rs2_ready_pre;
        renamed1_c.phys_rd_old =
            (slot0_can_fire && slot0_needs_phys && (decode_uop1_i.arch_rd == decode_uop0_i.arch_rd) && (decode_uop1_i.arch_rd != 5'd0)) ?
            renamed0_c.phys_rd_new :
            (slot1_needs_phys ? rat_q[decode_uop1_i.arch_rd] : `BBUS_OOO_PHYS_ZERO);
        renamed1_c.phys_rd_new =
            slot1_needs_phys ? (slot0_needs_phys ? free_phys1 : free_phys0) : `BBUS_OOO_PHYS_ZERO;

        if (slot0_can_fire && slot0_needs_phys) begin
            if (decode_uop1_i.uses_rs1 && (decode_uop1_i.arch_rs1 == decode_uop0_i.arch_rd) && (decode_uop0_i.arch_rd != 5'd0)) begin
                renamed1_c.phys_rs1 = renamed0_c.phys_rd_new;
                renamed1_c.src1_ready = 1'b0;
            end
            if (decode_uop1_i.uses_rs2 && (decode_uop1_i.arch_rs2 == decode_uop0_i.arch_rd) && (decode_uop0_i.arch_rd != 5'd0)) begin
                renamed1_c.phys_rs2 = renamed0_c.phys_rd_new;
                renamed1_c.src2_ready = 1'b0;
            end
        end
    end

    assign renamed_uop0_o = renamed0_c;
    assign renamed_uop1_o = renamed1_c;

    assign exception_rollback =
        commit_event_i.control_event_valid &&
        (commit_event_i.control_event == BBUS_OOO_CTRL_EXCEPTION) &&
        commit_event_i.slot0.rf_wen &&
        (commit_event_i.slot0.arch_rd != 5'd0) &&
        (commit_event_i.slot0.phys_rd_new != `BBUS_OOO_PHYS_ZERO);
    assign release0_valid_raw =
        exception_rollback ||
        (commit_event_i.normal_commit_mask[0] &&
         commit_event_i.slot0.rf_wen &&
         (commit_event_i.slot0.arch_rd != 5'd0) &&
         (commit_event_i.slot0.phys_rd_old != `BBUS_OOO_PHYS_ZERO));
    assign release1_valid_raw =
        commit_event_i.normal_commit_mask[1] &&
        commit_event_i.slot1.rf_wen &&
        (commit_event_i.slot1.arch_rd != 5'd0) &&
        (commit_event_i.slot1.phys_rd_old != `BBUS_OOO_PHYS_ZERO);
    assign release0_phys = exception_rollback ?
        commit_event_i.slot0.phys_rd_new : commit_event_i.slot0.phys_rd_old;
    assign release1_phys = commit_event_i.slot1.phys_rd_old;
    assign release_duplicate_bug =
        release0_valid_raw &&
        release1_valid_raw &&
        (release0_phys == release1_phys);
    assign release0_valid = release0_valid_raw;
    assign release1_valid = release1_valid_raw && !release_duplicate_bug;

    assign debug_rat_phys_o = rat_q[debug_arch_idx_i];
    assign debug_rrat_phys_o = rrat_q[debug_arch_idx_i];
    assign debug_ready_o = (debug_phys_idx_i == `BBUS_OOO_PHYS_ZERO) ? 1'b1 : ready_q[debug_phys_idx_i];
    assign debug_commit2_rrat_update2_o =
        commit_event_i.normal_commit_mask[0] &&
        commit_event_i.normal_commit_mask[1] &&
        commit_event_i.slot0.rf_wen &&
        commit_event_i.slot1.rf_wen &&
        (commit_event_i.slot0.arch_rd != 5'd0) &&
        (commit_event_i.slot1.arch_rd != 5'd0);
    assign debug_commit2_freelist_release2_o = release0_valid && release1_valid;
    assign debug_commit2_same_rd_waw_o =
        commit_event_i.normal_commit_mask[0] &&
        commit_event_i.normal_commit_mask[1] &&
        commit_event_i.slot0.rf_wen &&
        commit_event_i.slot1.rf_wen &&
        (commit_event_i.slot0.arch_rd != 5'd0) &&
        (commit_event_i.slot0.arch_rd == commit_event_i.slot1.arch_rd);
    assign debug_commit2_duplicate_release_bug_o = release_duplicate_bug;

    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < `BBUS_OOO_ARCH_REGS; i = i + 1) begin
                rat_q[i] <= bbus_ooo_phys_reg_t'(i[5:0]);
                rrat_q[i] <= bbus_ooo_phys_reg_t'(i[5:0]);
            end
            for (i = 0; i < `BBUS_OOO_PHYS_REGS; i = i + 1) begin
                ready_q[i] <= (i < `BBUS_OOO_ARCH_REGS);
            end
        end else begin
            ready_q[`BBUS_OOO_PHYS_ZERO] <= 1'b1;

            if (wb_ready_valid_i && (wb_ready_phys_i != `BBUS_OOO_PHYS_ZERO)) begin
                ready_q[wb_ready_phys_i] <= 1'b1;
            end
            if (wb_ready1_valid_i && (wb_ready1_phys_i != `BBUS_OOO_PHYS_ZERO)) begin
                ready_q[wb_ready1_phys_i] <= 1'b1;
            end

            if (commit_event_i.normal_commit_mask[0] && commit_event_i.slot0.rf_wen && (commit_event_i.slot0.arch_rd != 5'd0)) begin
                rrat_q[commit_event_i.slot0.arch_rd] <= commit_event_i.slot0.phys_rd_new;
            end
            if (commit_event_i.normal_commit_mask[1] && commit_event_i.slot1.rf_wen && (commit_event_i.slot1.arch_rd != 5'd0)) begin
                rrat_q[commit_event_i.slot1.arch_rd] <= commit_event_i.slot1.phys_rd_new;
            end

            if (exception_rollback) begin
                rat_q[commit_event_i.slot0.arch_rd] <=
                    commit_event_i.slot0.phys_rd_old;
            end

            if (rename_fire_mask_o[0] && slot0_needs_phys) begin
                rat_q[decode_uop0_i.arch_rd] <= renamed0_c.phys_rd_new;
                ready_q[renamed0_c.phys_rd_new] <= 1'b0;
            end
            if (rename_fire_mask_o[1] && slot1_needs_phys) begin
                rat_q[decode_uop1_i.arch_rd] <= renamed1_c.phys_rd_new;
                ready_q[renamed1_c.phys_rd_new] <= 1'b0;
            end

            rat_q[0] <= `BBUS_OOO_PHYS_ZERO;
            rrat_q[0] <= `BBUS_OOO_PHYS_ZERO;
            ready_q[`BBUS_OOO_PHYS_ZERO] <= 1'b1;
        end
    end
endmodule
