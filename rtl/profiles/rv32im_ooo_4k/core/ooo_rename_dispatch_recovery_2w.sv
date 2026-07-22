`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// Standalone Rename2/Dispatch2 state with an explicit global-recovery path.
// It intentionally does not share production rename_prf_core state.
module ooo_rename_dispatch_recovery_2w #(
    parameter bit PRECISE_STORE_BUFFER_ENABLE = 1'b0
) (
    input logic clk,
    input logic reset,
    input logic global_recover_i,
    input logic selective_restore_valid_i,
    input bbus_ooo_rat_snapshot_t selective_restore_rat_snapshot_i,
    input logic [`BBUS_OOO_PHYS_REGS-1:0] selective_restore_killed_phys_mask_i,
    output logic selective_restore_ready_o,
    output logic selective_restore_fire_o,
    output logic selective_restore_identity_error_o,
    input logic dispatch_freeze_i,
    input logic serial_dispatch_block_i,
    input logic memory_dispatch_block_i,
    input logic branch_nonblocking_i,
    input logic speculative_store_dispatch_i,

    input logic [1:0] decode_valid_mask_i,
    input bbus_ooo_decode_uop_t decode_uop0_i,
    input bbus_ooo_decode_uop_t decode_uop1_i,
    input logic [1:0] backend_capacity_count_i,
    input logic [1:0] backend_accept_mask_i,

    output logic [1:0] rename_offer_mask_o,
    output bbus_ooo_renamed_uop_t renamed_uop0_o,
    output bbus_ooo_renamed_uop_t renamed_uop1_o,
    output bbus_ooo_rat_snapshot_t checkpoint_rat_snapshot_o,

    input bbus_ooo_commit_event_t commit_event_i,
    input logic [1:0] final_wakeup_mask_i,
    input bbus_ooo_phys_reg_t final_wakeup_phys0_i,
    input bbus_ooo_phys_reg_t final_wakeup_phys1_i,

    input bbus_ooo_arch_reg_t debug_arch_idx_i,
    input bbus_ooo_phys_reg_t debug_phys_idx_i,
    output bbus_ooo_phys_reg_t debug_rat_phys_o,
    output bbus_ooo_phys_reg_t debug_rrat_phys_o,
    output logic debug_ready_o,
    output logic [6:0] debug_free_count_o,
    output bbus_ooo_phys_reg_t debug_next_free_phys_o,
    output logic slot1_retained_o,
    output logic atomicity_error_o,
    output logic recovery_mapping_error_o,
    output logic conservation_error_o
);
    bbus_ooo_phys_reg_t rat_q [`BBUS_OOO_ARCH_REGS-1:0];
    bbus_ooo_phys_reg_t rrat_q [`BBUS_OOO_ARCH_REGS-1:0];
    logic ready_q [`BBUS_OOO_PHYS_REGS-1:0];
    logic [`BBUS_OOO_PHYS_REGS-1:0] free_q;
    logic [`BBUS_OOO_PHYS_REGS-1:0] recovery_live_mask_c;
    logic [`BBUS_OOO_PHYS_REGS-1:0] selective_rat_live_mask_c;
    logic selective_restore_identity_ok_c;
    logic selective_restore_identity_error_q;

    bbus_ooo_phys_reg_t free_phys0_c;
    bbus_ooo_phys_reg_t free_phys1_c;
    logic [6:0] free_count_c;
    logic slot0_needs_phys_c;
    logic slot1_needs_phys_c;
    logic [1:0] phys_needed_c;
    logic slot0_offer_c;
    logic slot1_offer_c;
    logic [1:0] accepted_mask_c;
    bbus_ooo_renamed_uop_t renamed0_c;
    bbus_ooo_renamed_uop_t renamed1_c;
    logic free_conflict_c;

    function automatic logic needs_phys(input bbus_ooo_decode_uop_t uop);
        begin
            needs_phys = uop.valid && uop.rf_wen && (uop.arch_rd != 5'd0) &&
                !uop.exception.valid;
        end
    endfunction

    function automatic logic source_ready(
        input logic uses_src,
        input bbus_ooo_arch_reg_t arch,
        input bbus_ooo_phys_reg_t phys
    );
        begin
            source_ready = !uses_src || (arch == 5'd0) ||
                (phys == `BBUS_OOO_PHYS_ZERO) || ready_q[phys];
        end
    endfunction

    function automatic logic is_serial(input bbus_ooo_decode_uop_t uop);
        begin
            is_serial = uop.is_store || uop.is_csr || uop.is_system ||
                uop.exception.valid || (uop.fu_type == BBUS_OOO_FU_BRU) ||
                (uop.fu_type == BBUS_OOO_FU_MDU) ||
                (uop.fu_type == BBUS_OOO_FU_AMO);
        end
    endfunction

    function automatic logic ordinary_load(input bbus_ooo_decode_uop_t uop);
        begin
            ordinary_load = (uop.fu_type == BBUS_OOO_FU_LSU) && uop.is_load &&
                !uop.is_store && !uop.exception.valid;
        end
    endfunction
    function automatic logic memory_class(input bbus_ooo_decode_uop_t uop);
        begin
            memory_class = uop.is_load || uop.is_store ||
                (uop.fu_type == BBUS_OOO_FU_AMO);
        end
    endfunction

    function automatic logic blocked_serial(input bbus_ooo_decode_uop_t uop);
        begin
            blocked_serial = serial_dispatch_block_i && is_serial(uop) &&
                !(branch_nonblocking_i &&
                  (uop.fu_type == BBUS_OOO_FU_BRU)) &&
                !(PRECISE_STORE_BUFFER_ENABLE &&
                  speculative_store_dispatch_i && uop.is_store);
        end
    endfunction

    always_comb begin : select_free_and_check_maps
        integer p;
        integer a;
        logic found0;
        logic found1;

        free_phys0_c = `BBUS_OOO_PHYS_ZERO;
        free_phys1_c = `BBUS_OOO_PHYS_ZERO;
        free_count_c = '0;
        found0 = 1'b0;
        found1 = 1'b0;
        recovery_live_mask_c = '0;
        free_conflict_c = 1'b0;

        for (a = 0; a < `BBUS_OOO_ARCH_REGS; a = a + 1) begin
            recovery_live_mask_c[rrat_q[a]] = 1'b1;
        end
        recovery_live_mask_c[`BBUS_OOO_PHYS_ZERO] = 1'b1;

        for (p = 1; p < `BBUS_OOO_PHYS_REGS; p = p + 1) begin
            if (free_q[p]) begin
                free_count_c = free_count_c + 7'd1;
                if (!found0) begin
                    free_phys0_c = bbus_ooo_phys_reg_t'(p);
                    found0 = 1'b1;
                end else if (!found1) begin
                    free_phys1_c = bbus_ooo_phys_reg_t'(p);
                    found1 = 1'b1;
                end
                for (a = 0; a < `BBUS_OOO_ARCH_REGS; a = a + 1) begin
                    if ((rat_q[a] == bbus_ooo_phys_reg_t'(p)) ||
                        (rrat_q[a] == bbus_ooo_phys_reg_t'(p))) begin
                        free_conflict_c = 1'b1;
                    end
                end
            end
        end
    end

    always_comb begin : rename_comb
        bbus_ooo_phys_reg_t slot1_rs1_phys_pre;
        bbus_ooo_phys_reg_t slot1_rs2_phys_pre;
        logic slot1_rs1_ready_pre;
        logic slot1_rs2_ready_pre;
        logic lsu_lsu_pair;

        renamed0_c = '0;
        renamed1_c = '0;
        slot0_needs_phys_c = needs_phys(decode_uop0_i) && decode_valid_mask_i[0];
        slot1_needs_phys_c = needs_phys(decode_uop1_i) && decode_valid_mask_i[1] &&
            decode_valid_mask_i[0];
        phys_needed_c = {1'b0, slot0_needs_phys_c} +
            {1'b0, slot1_needs_phys_c};
        lsu_lsu_pair = ordinary_load(decode_uop0_i) && ordinary_load(decode_uop1_i);

        slot0_offer_c = !global_recover_i && !selective_restore_valid_i &&
            !dispatch_freeze_i &&
            !blocked_serial(decode_uop0_i) && decode_valid_mask_i[0] &&
            !(memory_dispatch_block_i && memory_class(decode_uop0_i) &&
              (!PRECISE_STORE_BUFFER_ENABLE || !decode_uop0_i.is_store)) &&
            (backend_capacity_count_i >= 2'd1) &&
            (!slot0_needs_phys_c || (free_count_c >= 7'd1));
        slot1_offer_c = slot0_offer_c && decode_valid_mask_i[1] &&
            !is_serial(decode_uop0_i) && !blocked_serial(decode_uop1_i) &&
            !decode_uop1_i.is_store &&
            !(memory_dispatch_block_i && memory_class(decode_uop1_i)) &&
            !lsu_lsu_pair &&
            (backend_capacity_count_i >= 2'd2) &&
            (free_count_c >= {5'd0, phys_needed_c});
        rename_offer_mask_o = {slot1_offer_c, slot0_offer_c};

        renamed0_c.valid = slot0_offer_c;
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
        renamed0_c.rf_wen = slot0_needs_phys_c;
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
        renamed0_c.phys_rs1 = decode_uop0_i.uses_rs1 ?
            rat_q[decode_uop0_i.arch_rs1] : `BBUS_OOO_PHYS_ZERO;
        renamed0_c.phys_rs2 = decode_uop0_i.uses_rs2 ?
            rat_q[decode_uop0_i.arch_rs2] : `BBUS_OOO_PHYS_ZERO;
        renamed0_c.src1_ready = source_ready(decode_uop0_i.uses_rs1,
            decode_uop0_i.arch_rs1, renamed0_c.phys_rs1);
        renamed0_c.src2_ready = source_ready(decode_uop0_i.uses_rs2,
            decode_uop0_i.arch_rs2, renamed0_c.phys_rs2);
        renamed0_c.phys_rd_old = slot0_needs_phys_c ?
            rat_q[decode_uop0_i.arch_rd] : `BBUS_OOO_PHYS_ZERO;
        renamed0_c.phys_rd_new = slot0_needs_phys_c ?
            free_phys0_c : `BBUS_OOO_PHYS_ZERO;

        slot1_rs1_phys_pre = decode_uop1_i.uses_rs1 ?
            rat_q[decode_uop1_i.arch_rs1] : `BBUS_OOO_PHYS_ZERO;
        slot1_rs2_phys_pre = decode_uop1_i.uses_rs2 ?
            rat_q[decode_uop1_i.arch_rs2] : `BBUS_OOO_PHYS_ZERO;
        slot1_rs1_ready_pre = source_ready(decode_uop1_i.uses_rs1,
            decode_uop1_i.arch_rs1, slot1_rs1_phys_pre);
        slot1_rs2_ready_pre = source_ready(decode_uop1_i.uses_rs2,
            decode_uop1_i.arch_rs2, slot1_rs2_phys_pre);

        renamed1_c.valid = slot1_offer_c;
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
        renamed1_c.rf_wen = slot1_needs_phys_c;
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
            (slot0_offer_c && slot0_needs_phys_c &&
             (decode_uop1_i.arch_rd == decode_uop0_i.arch_rd) &&
             (decode_uop1_i.arch_rd != 5'd0)) ? renamed0_c.phys_rd_new :
            (slot1_needs_phys_c ? rat_q[decode_uop1_i.arch_rd] :
             `BBUS_OOO_PHYS_ZERO);
        renamed1_c.phys_rd_new = slot1_needs_phys_c ?
            (slot0_needs_phys_c ? free_phys1_c : free_phys0_c) :
            `BBUS_OOO_PHYS_ZERO;

        if (slot0_offer_c && slot0_needs_phys_c) begin
            if (decode_uop1_i.uses_rs1 &&
                (decode_uop1_i.arch_rs1 == decode_uop0_i.arch_rd) &&
                (decode_uop0_i.arch_rd != 5'd0)) begin
                renamed1_c.phys_rs1 = renamed0_c.phys_rd_new;
                renamed1_c.src1_ready = 1'b0;
            end
            if (decode_uop1_i.uses_rs2 &&
                (decode_uop1_i.arch_rs2 == decode_uop0_i.arch_rd) &&
                (decode_uop0_i.arch_rd != 5'd0)) begin
                renamed1_c.phys_rs2 = renamed0_c.phys_rd_new;
                renamed1_c.src2_ready = 1'b0;
            end
        end

    end

    assign accepted_mask_c = backend_accept_mask_i & rename_offer_mask_o;
    assign slot1_retained_o = decode_valid_mask_i[1] && !slot1_offer_c &&
        !global_recover_i && !selective_restore_valid_i;
    assign atomicity_error_o = !global_recover_i &&
        !selective_restore_valid_i && !dispatch_freeze_i &&
        (backend_accept_mask_i != rename_offer_mask_o);
    assign renamed_uop0_o = renamed0_c;
    assign renamed_uop1_o = renamed1_c;
    always_comb begin : build_checkpoint_rat_snapshot
        for (int a = 0; a < `BBUS_OOO_ARCH_REGS; a = a + 1) begin
            checkpoint_rat_snapshot_o[
                (a * `BBUS_OOO_PHYS_REG_W) +: `BBUS_OOO_PHYS_REG_W] = rat_q[a];
        end
        if (accepted_mask_c[0] && slot0_needs_phys_c) begin
            checkpoint_rat_snapshot_o[
                (decode_uop0_i.arch_rd * `BBUS_OOO_PHYS_REG_W) +:
                `BBUS_OOO_PHYS_REG_W] = renamed0_c.phys_rd_new;
        end
        if (accepted_mask_c[1] && slot1_needs_phys_c) begin
            checkpoint_rat_snapshot_o[
                (decode_uop1_i.arch_rd * `BBUS_OOO_PHYS_REG_W) +:
                `BBUS_OOO_PHYS_REG_W] = renamed1_c.phys_rd_new;
        end
    end
    assign debug_rat_phys_o = rat_q[debug_arch_idx_i];
    assign debug_rrat_phys_o = rrat_q[debug_arch_idx_i];
    assign debug_ready_o = (debug_phys_idx_i == `BBUS_OOO_PHYS_ZERO) ?
        1'b1 : ready_q[debug_phys_idx_i];
    assign debug_free_count_o = free_count_c;
    assign debug_next_free_phys_o = free_phys0_c;
    assign recovery_mapping_error_o = free_conflict_c;
    assign conservation_error_o = atomicity_error_o || free_conflict_c ||
        selective_restore_identity_error_q ||
        (free_q[`BBUS_OOO_PHYS_ZERO] != 1'b0);

    always_comb begin : selective_restore_validate
        bbus_ooo_phys_reg_t snapshot_phys;

        selective_rat_live_mask_c = '0;
        selective_restore_identity_ok_c =
            !selective_restore_killed_phys_mask_i[`BBUS_OOO_PHYS_ZERO];
        for (int a = 0; a < `BBUS_OOO_ARCH_REGS; a = a + 1) begin
            snapshot_phys = selective_restore_rat_snapshot_i[
                (a * `BBUS_OOO_PHYS_REG_W) +: `BBUS_OOO_PHYS_REG_W];
            selective_rat_live_mask_c[snapshot_phys] = 1'b1;
            if ((a == 0) && (snapshot_phys != `BBUS_OOO_PHYS_ZERO))
                selective_restore_identity_ok_c = 1'b0;
            if ((snapshot_phys != `BBUS_OOO_PHYS_ZERO) && free_q[snapshot_phys])
                selective_restore_identity_ok_c = 1'b0;
        end
        selective_rat_live_mask_c[`BBUS_OOO_PHYS_ZERO] = 1'b1;
        if (|(selective_restore_killed_phys_mask_i &
              selective_rat_live_mask_c))
            selective_restore_identity_ok_c = 1'b0;
        if (|(selective_restore_killed_phys_mask_i & recovery_live_mask_c))
            selective_restore_identity_ok_c = 1'b0;
        if (|(selective_restore_killed_phys_mask_i & free_q))
            selective_restore_identity_ok_c = 1'b0;

        selective_restore_ready_o = !reset && !global_recover_i &&
            selective_restore_identity_ok_c;
    end
    assign selective_restore_fire_o = selective_restore_valid_i &&
        selective_restore_ready_o;
    assign selective_restore_identity_error_o =
        selective_restore_identity_error_q;

    always_ff @(posedge clk) begin : rename_state
        integer i;
        logic release0_valid;
        logic release1_valid;
        bbus_ooo_phys_reg_t release0_phys;
        bbus_ooo_phys_reg_t release1_phys;

        if (reset) begin
            selective_restore_identity_error_q <= 1'b0;
            for (i = 0; i < `BBUS_OOO_ARCH_REGS; i = i + 1) begin
                rat_q[i] <= bbus_ooo_phys_reg_t'(i);
                rrat_q[i] <= bbus_ooo_phys_reg_t'(i);
            end
            for (i = 0; i < `BBUS_OOO_PHYS_REGS; i = i + 1) begin
                ready_q[i] <= (i < `BBUS_OOO_ARCH_REGS);
                free_q[i] <= (i >= `BBUS_OOO_ARCH_REGS);
            end
            free_q[`BBUS_OOO_PHYS_ZERO] <= 1'b0;
        end else if (global_recover_i) begin
            selective_restore_identity_error_q <= 1'b0;
            for (i = 0; i < `BBUS_OOO_ARCH_REGS; i = i + 1) begin
                rat_q[i] <= rrat_q[i];
            end
            for (i = 0; i < `BBUS_OOO_PHYS_REGS; i = i + 1) begin
                ready_q[i] <= recovery_live_mask_c[i];
                free_q[i] <= (i != `BBUS_OOO_PHYS_ZERO) &&
                    !recovery_live_mask_c[i];
            end
            rat_q[0] <= `BBUS_OOO_PHYS_ZERO;
            rrat_q[0] <= `BBUS_OOO_PHYS_ZERO;
            ready_q[`BBUS_OOO_PHYS_ZERO] <= 1'b1;
            free_q[`BBUS_OOO_PHYS_ZERO] <= 1'b0;
        end else if (selective_restore_valid_i) begin
            if (!selective_restore_ready_o) begin
                selective_restore_identity_error_q <= 1'b1;
            end else begin
                for (i = 0; i < `BBUS_OOO_ARCH_REGS; i = i + 1) begin
                    rat_q[i] <= selective_restore_rat_snapshot_i[
                        (i * `BBUS_OOO_PHYS_REG_W) +: `BBUS_OOO_PHYS_REG_W];
                end

                if (final_wakeup_mask_i[0] &&
                    (final_wakeup_phys0_i != `BBUS_OOO_PHYS_ZERO))
                    ready_q[final_wakeup_phys0_i] <= 1'b1;
                if (final_wakeup_mask_i[1] &&
                    (final_wakeup_phys1_i != `BBUS_OOO_PHYS_ZERO))
                    ready_q[final_wakeup_phys1_i] <= 1'b1;

                release0_valid = commit_event_i.normal_commit_mask[0] &&
                    commit_event_i.slot0.rf_wen &&
                    (commit_event_i.slot0.arch_rd != 5'd0) &&
                    (commit_event_i.slot0.phys_rd_old != `BBUS_OOO_PHYS_ZERO);
                release1_valid = commit_event_i.normal_commit_mask[1] &&
                    commit_event_i.slot1.rf_wen &&
                    (commit_event_i.slot1.arch_rd != 5'd0) &&
                    (commit_event_i.slot1.phys_rd_old != `BBUS_OOO_PHYS_ZERO);
                release0_phys = commit_event_i.slot0.phys_rd_old;
                release1_phys = commit_event_i.slot1.phys_rd_old;

                if (commit_event_i.normal_commit_mask[0] &&
                    commit_event_i.slot0.rf_wen &&
                    (commit_event_i.slot0.arch_rd != 5'd0))
                    rrat_q[commit_event_i.slot0.arch_rd] <=
                        commit_event_i.slot0.phys_rd_new;
                if (commit_event_i.normal_commit_mask[1] &&
                    commit_event_i.slot1.rf_wen &&
                    (commit_event_i.slot1.arch_rd != 5'd0))
                    rrat_q[commit_event_i.slot1.arch_rd] <=
                        commit_event_i.slot1.phys_rd_new;
                if (release0_valid) free_q[release0_phys] <= 1'b1;
                if (release1_valid && (!release0_valid ||
                    (release1_phys != release0_phys)))
                    free_q[release1_phys] <= 1'b1;

                for (i = 1; i < `BBUS_OOO_PHYS_REGS; i = i + 1) begin
                    if (selective_restore_killed_phys_mask_i[i]) begin
                        free_q[i] <= 1'b1;
                        ready_q[i] <= 1'b0;
                    end
                end
                rat_q[0] <= `BBUS_OOO_PHYS_ZERO;
                rrat_q[0] <= `BBUS_OOO_PHYS_ZERO;
                ready_q[`BBUS_OOO_PHYS_ZERO] <= 1'b1;
                free_q[`BBUS_OOO_PHYS_ZERO] <= 1'b0;
            end
        end else begin
            if (final_wakeup_mask_i[0] &&
                (final_wakeup_phys0_i != `BBUS_OOO_PHYS_ZERO)) begin
                ready_q[final_wakeup_phys0_i] <= 1'b1;
            end
            if (final_wakeup_mask_i[1] &&
                (final_wakeup_phys1_i != `BBUS_OOO_PHYS_ZERO)) begin
                ready_q[final_wakeup_phys1_i] <= 1'b1;
            end

            release0_valid = commit_event_i.normal_commit_mask[0] &&
                commit_event_i.slot0.rf_wen &&
                (commit_event_i.slot0.arch_rd != 5'd0) &&
                (commit_event_i.slot0.phys_rd_old != `BBUS_OOO_PHYS_ZERO);
            release1_valid = commit_event_i.normal_commit_mask[1] &&
                commit_event_i.slot1.rf_wen &&
                (commit_event_i.slot1.arch_rd != 5'd0) &&
                (commit_event_i.slot1.phys_rd_old != `BBUS_OOO_PHYS_ZERO);
            release0_phys = commit_event_i.slot0.phys_rd_old;
            release1_phys = commit_event_i.slot1.phys_rd_old;

            if (commit_event_i.normal_commit_mask[0] &&
                commit_event_i.slot0.rf_wen &&
                (commit_event_i.slot0.arch_rd != 5'd0)) begin
                rrat_q[commit_event_i.slot0.arch_rd] <=
                    commit_event_i.slot0.phys_rd_new;
            end
            if (commit_event_i.normal_commit_mask[1] &&
                commit_event_i.slot1.rf_wen &&
                (commit_event_i.slot1.arch_rd != 5'd0)) begin
                rrat_q[commit_event_i.slot1.arch_rd] <=
                    commit_event_i.slot1.phys_rd_new;
            end
            if (release0_valid) begin
                free_q[release0_phys] <= 1'b1;
            end
            if (release1_valid && (!release0_valid ||
                (release1_phys != release0_phys))) begin
                free_q[release1_phys] <= 1'b1;
            end

            if (accepted_mask_c[0] && slot0_needs_phys_c) begin
                rat_q[decode_uop0_i.arch_rd] <= renamed0_c.phys_rd_new;
                ready_q[renamed0_c.phys_rd_new] <= 1'b0;
                free_q[renamed0_c.phys_rd_new] <= 1'b0;
            end
            if (accepted_mask_c[1] && slot1_needs_phys_c) begin
                rat_q[decode_uop1_i.arch_rd] <= renamed1_c.phys_rd_new;
                ready_q[renamed1_c.phys_rd_new] <= 1'b0;
                free_q[renamed1_c.phys_rd_new] <= 1'b0;
            end

            rat_q[0] <= `BBUS_OOO_PHYS_ZERO;
            rrat_q[0] <= `BBUS_OOO_PHYS_ZERO;
            ready_q[`BBUS_OOO_PHYS_ZERO] <= 1'b1;
            free_q[`BBUS_OOO_PHYS_ZERO] <= 1'b0;
        end
    end
endmodule
