`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module small_rob #(
    parameter bit COMMIT2_ENABLE = 1'b1,
    parameter bit COMMIT_STORE_TAG_CHECK_ENABLE = 1'b0,
    parameter bit EARLY_TERMINAL_DONE_ENABLE = 1'b1,
    parameter bit PRECISE_STORE_ACCEPT_RETIRE_ENABLE = 1'b0,
    parameter bit HEAD_LOAD_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b0,
    parameter bit HEAD_ALU_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b0,
    parameter bit HEAD_BRU_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b0,
    parameter bit SLOT1_FINAL_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b0,
    parameter bit CORRECT_BRANCH_DUAL_RETIRE_ENABLE = 1'b0,
    parameter bit YOUNGER_SLOT1_CONTROL_DUAL_RETIRE_ENABLE = 1'b0
) (
    input  logic clk,
    input  logic reset,
    input  logic flush_i,

    input  logic [1:0] alloc_valid_mask_i,
    input  bbus_ooo_rob_alloc_t alloc_slot0_i,
    input  bbus_ooo_rob_alloc_t alloc_slot1_i,
    output logic [1:0] alloc_fire_mask_o,
    output bbus_ooo_rob_tag_t alloc_tag0_o,
    output bbus_ooo_rob_tag_t alloc_tag1_o,
    output bbus_ooo_rob_tag_t alloc_post_tail_tag_o,
    output logic [1:0] available_slots_o,

    input logic selective_squash_valid_i,
    input bbus_ooo_rob_tag_t selective_squash_branch_tag_i,
    input bbus_ooo_rob_tag_t selective_squash_post_tail_tag_i,
    output logic selective_squash_ready_o,
    output logic selective_squash_fire_o,
    output logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_o,
    output logic [`BBUS_OOO_PHYS_REGS-1:0] selective_killed_phys_mask_o,
    output logic [3:0] selective_killed_count_o,
    output logic selective_squash_identity_error_o,

    input  bbus_ooo_writeback_t writeback_i,
    output logic writeback_accepted_o,
    input  bbus_ooo_writeback_t writeback1_i,
    output logic writeback1_accepted_o,
    input  bbus_ooo_writeback_t writeback_probe0_i,
    input  bbus_ooo_writeback_t writeback_probe1_i,
    output logic writeback_probe0_match_o,
    output logic writeback_probe1_match_o,
    input  logic [8:0] raw_probe_valid_mask_i,
    input  bbus_ooo_writeback_t raw_probe_wb_i [8:0],
    output logic [8:0] raw_probe_fresh_mask_o,

    input  logic commit_enable_i,
    output logic commit_store_valid_o,
    input  logic commit_store_ready_i,
    input  logic commit_store_accept_is_done_i,
    input  logic commit_store_done_i,
    output bbus_ooo_rob_tag_t commit_store_rob_tag_o,
    input  bbus_ooo_rob_tag_t commit_store_done_rob_tag_i,
    output logic commit_store_done_match_o,
    output logic commit_store_done_drop_o,
    output logic commit_store_done_clear_o,
    input  logic commit_store_fault_i,
    input  bbus_ooo_rob_tag_t commit_store_fault_rob_tag_i,
    input  logic [31:0] commit_store_fault_tval_i,
    output logic commit_store_fault_match_o,
    output logic commit_store_fault_drop_o,
    output logic commit_store_fault_clear_o,
    output logic [31:0] commit_store_addr_o,
    output logic [31:0] commit_store_wdata_o,
    output logic [3:0] commit_store_wstrb_o,
    output logic [2:0] commit_store_len_o,
    output bbus_ooo_commit_event_t commit_event_o,
    output logic [1:0] debug_commit_width_mode_o,
    output logic debug_commit2_candidate_o,
    output logic debug_commit2_fire_o,
    output logic debug_commit2_slot0_only_o,
    output logic debug_commit2_block_slot0_not_ready_o,
    output logic debug_commit2_block_slot1_not_ready_o,
    output logic debug_commit2_block_slot0_complex_o,
    output logic debug_commit2_block_slot1_complex_o,
    output logic debug_commit2_slot1_without_slot0_bug_o,
    output logic debug_commit2_complex_slot_bug_o,
    output logic [3:0] perf_commit_reason0_o,
    output logic [3:0] perf_commit_reason1_o,
    output logic [18:0] perf_slot1_bypass_oracle_o,
    output logic [63:0] perf_complex_retire_pairing_o,

    input  bbus_ooo_rob_idx_t debug_rob_idx_i,
    output logic debug_rob_valid_o,
    output logic debug_rob_done_o,
    output logic [31:0] debug_rob_result_o,
    output logic [3:0] debug_rob_count_o,
    output bbus_ooo_rob_idx_t debug_rob_head_o,
    output bbus_ooo_rob_idx_t debug_rob_tail_o,
    output bbus_ooo_rob_tag_t rob_head_tag_o
);
    logic valid_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic done_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic [`BBUS_OOO_ROB_GEN_W-1:0] gen_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic [31:0] pc_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic [31:0] instr_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    bbus_ooo_arch_reg_t arch_rd_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    bbus_ooo_phys_reg_t phys_new_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    bbus_ooo_phys_reg_t phys_old_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic rf_wen_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    bbus_ooo_fu_type_e fu_type_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    bbus_ooo_branch_op_e branch_op_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic is_load_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic is_store_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic is_ebreak_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic is_csr_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic is_system_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic [11:0] csr_addr_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic csr_write_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic [31:0] csr_wdata_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    bbus_ooo_mem_op_e mem_op_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic [31:0] mem_addr_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic [31:0] mem_wdata_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic [3:0] mem_wstrb_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic [2:0] mem_len_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic [31:0] result_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic result_valid_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic is_control_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic is_branch_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic is_jal_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic is_jalr_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic actual_taken_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic [31:0] commit_nextpc_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic redirect_valid_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    // A redirecting branch is owned by execute-age recovery until the
    // selective transaction has truncated the ROB.  Keep that proof with
    // the ROB entry so Commit cannot retire the branch in the completion
    // cycle and strand recovery on a tag that no longer exists.
    logic selective_recovered_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    bbus_ooo_exception_t exception_q [`BBUS_OOO_ROB_ENTRIES-1:0];

    bbus_ooo_rob_idx_t head_q;
    bbus_ooo_rob_idx_t tail_q;
    logic [3:0] count_q;
    logic selective_squash_identity_error_q;
    logic selective_branch_match_c;
    logic selective_boundary_match_c;
    logic [3:0] selective_branch_distance_c;
    logic [3:0] selective_survivor_count_c;
    logic operation_blocked_c;

    function automatic bbus_ooo_rob_idx_t bump(input bbus_ooo_rob_idx_t ptr, input logic [1:0] inc);
        logic [3:0] sum;
        begin
            sum = {1'b0, ptr} + {2'b0, inc};
            bump = (sum >= `BBUS_OOO_ROB_ENTRIES) ? bbus_ooo_rob_idx_t'(sum - `BBUS_OOO_ROB_ENTRIES) : bbus_ooo_rob_idx_t'(sum);
        end
    endfunction

    function automatic bbus_ooo_rob_idx_t advance(
        input bbus_ooo_rob_idx_t ptr,
        input logic [3:0] inc
    );
        logic [4:0] sum;
        begin
            sum = {2'b0, ptr} + {1'b0, inc};
            advance = bbus_ooo_rob_idx_t'(sum % `BBUS_OOO_ROB_ENTRIES);
        end
    endfunction

    function automatic logic [3:0] distance_from_head(
        input bbus_ooo_rob_idx_t idx
    );
        begin
            if (idx >= head_q) distance_from_head = {1'b0, idx - head_q};
            else distance_from_head = `BBUS_OOO_ROB_ENTRIES - head_q + idx;
        end
    endfunction

    function automatic logic [1:0] bit_count2(input logic [1:0] mask);
        begin
            bit_count2 = {1'b0, mask[0]} + {1'b0, mask[1]};
        end
    endfunction

    function automatic logic wb_tag_matches(input bbus_ooo_writeback_t wb);
        begin
            wb_tag_matches =
                wb.valid &&
                wb.rob_tag.valid &&
                valid_q[wb.rob_tag.idx] &&
                (gen_q[wb.rob_tag.idx] == wb.rob_tag.gen);
        end
    endfunction

    function automatic logic wb_phys_matches(input bbus_ooo_writeback_t wb);
        begin
            wb_phys_matches =
                !wb.rf_wen ||
                (wb_tag_matches(wb) && (wb.phys_rd == phys_new_q[wb.rob_tag.idx]));
        end
    endfunction

    function automatic bbus_ooo_commit_slot_t make_slot(input bbus_ooo_rob_idx_t idx);
        begin
            make_slot = '0;
            make_slot.valid = valid_q[idx];
            make_slot.rob_tag.valid = valid_q[idx];
            make_slot.rob_tag.idx = idx;
            make_slot.rob_tag.gen = gen_q[idx];
            make_slot.pc = pc_q[idx];
            make_slot.instr = instr_q[idx];
            make_slot.arch_rd = arch_rd_q[idx];
            make_slot.phys_rd_new = phys_new_q[idx];
            make_slot.phys_rd_old = phys_old_q[idx];
            make_slot.rf_wen = rf_wen_q[idx];
            make_slot.wdata = result_q[idx];
            make_slot.wdata_valid = result_valid_q[idx];
            make_slot.fu_type = fu_type_q[idx];
            make_slot.branch_op = branch_op_q[idx];
            make_slot.is_load = is_load_q[idx];
            make_slot.is_store = is_store_q[idx];
            make_slot.mem_op = mem_op_q[idx];
            make_slot.mem_addr = mem_addr_q[idx];
            make_slot.mem_wdata = mem_wdata_q[idx];
            make_slot.mem_wstrb = mem_wstrb_q[idx];
            make_slot.mem_len = mem_len_q[idx];
            make_slot.is_csr = is_csr_q[idx];
            make_slot.is_system = is_system_q[idx];
            make_slot.csr_addr = csr_addr_q[idx];
            make_slot.csr_write = csr_write_q[idx];
            make_slot.csr_wdata = csr_wdata_q[idx];
            make_slot.is_control = is_control_q[idx];
            make_slot.is_branch = is_branch_q[idx];
            make_slot.is_jal = is_jal_q[idx];
            make_slot.is_jalr = is_jalr_q[idx];
            make_slot.actual_taken = actual_taken_q[idx];
            make_slot.commit_nextpc = commit_nextpc_q[idx];
            make_slot.redirect_valid = redirect_valid_q[idx];
            make_slot.exception = exception_q[idx];
        end
    endfunction

    function automatic bbus_ooo_commit_slot_t make_slot_with_writeback(
        input bbus_ooo_rob_idx_t idx,
        input bbus_ooo_writeback_t wb
    );
        begin
            make_slot_with_writeback = make_slot(idx);
            make_slot_with_writeback.wdata = wb.result;
            make_slot_with_writeback.wdata_valid =
                wb.rf_wen &&
                (wb.phys_rd != `BBUS_OOO_PHYS_ZERO) &&
                !wb.exception.valid;
            make_slot_with_writeback.is_load = wb.is_load;
            make_slot_with_writeback.is_store = wb.is_store;
            make_slot_with_writeback.mem_op = wb.mem_op;
            make_slot_with_writeback.mem_addr = wb.mem_addr;
            make_slot_with_writeback.mem_wdata = wb.mem_wdata;
            make_slot_with_writeback.mem_wstrb = wb.mem_wstrb;
            make_slot_with_writeback.mem_len = wb.mem_len;
            make_slot_with_writeback.is_csr = wb.is_csr;
            make_slot_with_writeback.is_system = wb.is_system;
            make_slot_with_writeback.csr_addr = wb.csr_addr;
            make_slot_with_writeback.csr_write = wb.csr_write;
            make_slot_with_writeback.csr_wdata = wb.csr_wdata;
            make_slot_with_writeback.is_control = wb.is_control;
            make_slot_with_writeback.is_branch = wb.is_branch;
            make_slot_with_writeback.is_jal = wb.is_jal;
            make_slot_with_writeback.is_jalr = wb.is_jalr;
            make_slot_with_writeback.actual_taken = wb.actual_taken;
            make_slot_with_writeback.commit_nextpc =
                wb.is_control ? wb.actual_nextpc : (pc_q[idx] + 32'd4);
            make_slot_with_writeback.redirect_valid = wb.redirect_valid;
            make_slot_with_writeback.exception = wb.exception;
        end
    endfunction

    function automatic logic slot_ready_no_exception(input bbus_ooo_rob_idx_t idx);
        begin
            slot_ready_no_exception =
                valid_q[idx] &&
                done_q[idx] &&
                !exception_q[idx].valid;
        end
    endfunction

    task automatic record_writeback(input bbus_ooo_writeback_t wb);
        begin
            done_q[wb.rob_tag.idx] <= wb.done;
            result_q[wb.rob_tag.idx] <= wb.result;
            is_control_q[wb.rob_tag.idx] <= wb.is_control;
            is_branch_q[wb.rob_tag.idx] <= wb.is_branch;
            is_jal_q[wb.rob_tag.idx] <= wb.is_jal;
            is_jalr_q[wb.rob_tag.idx] <= wb.is_jalr;
            actual_taken_q[wb.rob_tag.idx] <= wb.actual_taken;
            is_load_q[wb.rob_tag.idx] <= wb.is_load;
            is_store_q[wb.rob_tag.idx] <= wb.is_store;
            is_csr_q[wb.rob_tag.idx] <= wb.is_csr;
            is_system_q[wb.rob_tag.idx] <= wb.is_system;
            csr_addr_q[wb.rob_tag.idx] <= wb.csr_addr;
            csr_write_q[wb.rob_tag.idx] <= wb.csr_write;
            csr_wdata_q[wb.rob_tag.idx] <= wb.csr_wdata;
            mem_op_q[wb.rob_tag.idx] <= wb.mem_op;
            mem_addr_q[wb.rob_tag.idx] <= wb.mem_addr;
            mem_wdata_q[wb.rob_tag.idx] <= wb.mem_wdata;
            mem_wstrb_q[wb.rob_tag.idx] <= wb.mem_wstrb;
            mem_len_q[wb.rob_tag.idx] <= wb.mem_len;
            commit_nextpc_q[wb.rob_tag.idx] <=
                wb.is_control ? wb.actual_nextpc : (pc_q[wb.rob_tag.idx] + 32'd4);
            redirect_valid_q[wb.rob_tag.idx] <= wb.redirect_valid;
            result_valid_q[wb.rob_tag.idx] <=
                wb.rf_wen && (wb.phys_rd != `BBUS_OOO_PHYS_ZERO) &&
                !wb.exception.valid;
            if (wb.exception.valid) begin
                exception_q[wb.rob_tag.idx] <= wb.exception;
                done_q[wb.rob_tag.idx] <= 1'b1;
                result_valid_q[wb.rob_tag.idx] <= 1'b0;
            end
        end
    endtask

    function automatic logic slot_commit2_complex(input bbus_ooo_rob_idx_t idx);
        logic correct_conditional_branch;
        begin
            // P21 deliberately covers only a registered, completed branch.
            // Redirecting branches and jumps retain the precise Commit1
            // boundary. Same-cycle writeback has separate ownership below.
            correct_conditional_branch =
                is_control_q[idx] && is_branch_q[idx] &&
                !is_jal_q[idx] && !is_jalr_q[idx] &&
                !redirect_valid_q[idx] && !exception_q[idx].valid;
            slot_commit2_complex =
                is_store_q[idx] ||
                (is_control_q[idx] &&
                 !(CORRECT_BRANCH_DUAL_RETIRE_ENABLE &&
                   correct_conditional_branch)) ||
                is_csr_q[idx] ||
                is_system_q[idx] ||
                is_ebreak_q[idx] ||
                (fu_type_q[idx] == BBUS_OOO_FU_AMO);
        end
    endfunction

    function automatic logic wb_correct_conditional_branch(
        input bbus_ooo_writeback_t wb
    );
        begin
            wb_correct_conditional_branch =
                wb.valid && wb.done && wb.is_control && wb.is_branch &&
                !wb.is_jal && !wb.is_jalr && !wb.redirect_valid &&
                !wb.exception.valid;
        end
    endfunction

    function automatic logic slot_p64_strict_ordinary(
        input bbus_ooo_rob_idx_t idx
    );
        begin
            // P64 is a narrow retirement relaxation: only a completed ALU or
            // load in the older slot can share the Commit edge with the
            // explicitly safe younger control classes below.
            slot_p64_strict_ordinary =
                !is_store_q[idx] && !is_control_q[idx] &&
                !is_csr_q[idx] && !is_system_q[idx] &&
                !is_ebreak_q[idx] &&
                (fu_type_q[idx] != BBUS_OOO_FU_AMO) &&
                !redirect_valid_q[idx] && !exception_q[idx].valid &&
                (((fu_type_q[idx] == BBUS_OOO_FU_ALU) &&
                  !is_load_q[idx]) ||
                 ((fu_type_q[idx] == BBUS_OOO_FU_LSU) &&
                  is_load_q[idx]));
        end
    endfunction

    function automatic logic wb_p64_strict_ordinary(
        input bbus_ooo_writeback_t wb,
        input bbus_ooo_rob_idx_t idx
    );
        begin
            wb_p64_strict_ordinary =
                wb.valid && wb.done &&
                !wb.is_store && !wb.is_control &&
                !wb.is_csr && !wb.is_system &&
                !is_store_q[idx] && !is_ebreak_q[idx] &&
                (fu_type_q[idx] != BBUS_OOO_FU_AMO) &&
                !wb.redirect_valid && !wb.exception.valid &&
                (((fu_type_q[idx] == BBUS_OOO_FU_ALU) &&
                  !is_load_q[idx] && !wb.is_load) ||
                 ((fu_type_q[idx] == BBUS_OOO_FU_LSU) &&
                  is_load_q[idx] && wb.is_load));
        end
    endfunction

    function automatic logic slot_p64_safe_control(
        input bbus_ooo_rob_idx_t idx
    );
        logic redirecting_conditional;
        logic nonredirect_jump;
        begin
            redirecting_conditional =
                is_branch_q[idx] && !is_jal_q[idx] && !is_jalr_q[idx] &&
                redirect_valid_q[idx];
            nonredirect_jump =
                (is_jal_q[idx] || is_jalr_q[idx]) &&
                !redirect_valid_q[idx];
            slot_p64_safe_control =
                is_control_q[idx] &&
                !is_store_q[idx] && !is_csr_q[idx] &&
                !is_system_q[idx] && !is_ebreak_q[idx] &&
                (fu_type_q[idx] == BBUS_OOO_FU_BRU) &&
                !exception_q[idx].valid &&
                (redirecting_conditional || nonredirect_jump) &&
                (!redirecting_conditional || selective_recovered_q[idx]);
        end
    endfunction

    function automatic logic wb_p64_safe_control(
        input bbus_ooo_writeback_t wb,
        input bbus_ooo_rob_idx_t idx
    );
        logic redirecting_conditional;
        logic nonredirect_jump;
        begin
            redirecting_conditional =
                wb.is_branch && !wb.is_jal && !wb.is_jalr &&
                wb.redirect_valid;
            nonredirect_jump =
                (wb.is_jal || wb.is_jalr) && !wb.redirect_valid;
            wb_p64_safe_control =
                wb.valid && wb.done && wb.is_control &&
                !wb.is_store && !wb.is_csr && !wb.is_system &&
                !is_store_q[idx] && !is_ebreak_q[idx] &&
                (fu_type_q[idx] == BBUS_OOO_FU_BRU) &&
                !wb.exception.valid &&
                (redirecting_conditional || nonredirect_jump) &&
                (!redirecting_conditional || selective_recovered_q[idx]);
        end
    endfunction

    function automatic logic [2:0] slot_commit2_complex_class(
        input bbus_ooo_rob_idx_t idx
    );
        begin
            if (is_store_q[idx])
                slot_commit2_complex_class = 3'd1;
            else if (is_csr_q[idx])
                slot_commit2_complex_class = 3'd3;
            else if (is_system_q[idx] || is_ebreak_q[idx])
                slot_commit2_complex_class = 3'd4;
            else if (fu_type_q[idx] == BBUS_OOO_FU_AMO)
                slot_commit2_complex_class = 3'd5;
            else if (is_control_q[idx])
                slot_commit2_complex_class = 3'd2;
            else
                slot_commit2_complex_class = 3'd6;
        end
    endfunction

    function automatic logic [2:0] slot_control_subclass(
        input bbus_ooo_rob_idx_t idx
    );
        begin
            if (is_branch_q[idx])
                slot_control_subclass = redirect_valid_q[idx] ? 3'd2 : 3'd1;
            else if (is_jal_q[idx])
                slot_control_subclass = 3'd3;
            else if (is_jalr_q[idx])
                slot_control_subclass = 3'd4;
            else
                slot_control_subclass = 3'd5;
        end
    endfunction

    function automatic logic [2:0] wb_commit2_complex_class(
        input bbus_ooo_writeback_t wb,
        input bbus_ooo_rob_idx_t idx
    );
        begin
            if (wb.is_store)
                wb_commit2_complex_class = 3'd1;
            else if (wb.is_csr)
                wb_commit2_complex_class = 3'd3;
            else if (wb.is_system || is_ebreak_q[idx])
                wb_commit2_complex_class = 3'd4;
            else if (fu_type_q[idx] == BBUS_OOO_FU_AMO)
                wb_commit2_complex_class = 3'd5;
            else if (wb.is_control)
                wb_commit2_complex_class = 3'd2;
            else
                wb_commit2_complex_class = 3'd6;
        end
    endfunction

    function automatic logic [2:0] wb_control_subclass(
        input bbus_ooo_writeback_t wb
    );
        begin
            if (wb.is_branch)
                wb_control_subclass = wb.redirect_valid ? 3'd2 : 3'd1;
            else if (wb.is_jal)
                wb_control_subclass = 3'd3;
            else if (wb.is_jalr)
                wb_control_subclass = 3'd4;
            else
                wb_control_subclass = 3'd5;
        end
    endfunction

    bbus_ooo_rob_idx_t head1;
    bbus_ooo_rob_idx_t alloc_post_tail_idx_c;
    logic [1:0] alloc_count_c;
    logic [3:0] free_count_full;
    logic [1:0] free_slots;
    logic wb_tag_match;
    logic wb_phys_match;
    logic wb_accept;
    logic wb1_tag_match;
    logic wb1_phys_match;
    logic wb1_accept;
    bbus_ooo_commit_event_t commit_event_c;
    logic [1:0] commit_count_c;
    logic slot0_ready_for_commit2_c;
    logic slot1_ready_for_commit2_c;
    logic slot0_complex_for_commit2_c;
    logic slot1_complex_for_commit2_c;
    logic slot0_commit2_ok_c;
    logic slot1_commit2_ok_c;
    logic slot0_p64_strict_ordinary_c;
    logic slot1_p64_safe_control_c;
    logic slot1_p64_allow_c;
    logic head_same_cycle_wb0_c;
    logic head_same_cycle_wb1_c;
    logic head_same_cycle_wb_valid_c;
    bbus_ooo_writeback_t head_same_cycle_wb_c;
    logic head1_same_cycle_wb0_c;
    logic head1_same_cycle_wb1_c;
    logic head1_exact_wb0_alu_c;
    logic head1_exact_wb1_alu_c;
    logic head1_exact_wb1_load_c;
    logic head1_exact_wb1_other_c;
    logic slot1_not_ready_target_c;
    logic complex_single_target_c;
    logic complex_single_slot0_c;
    logic complex_single_slot1_c;
    logic [2:0] complex_single_class_c;
    logic complex_single_detail_error_c;
    logic [2:0] complex_control_subclass_c;
    logic complex_control_detail_error_c;
    logic [2:0] slot0_semantic_class_c;
    logic [2:0] slot1_semantic_class_c;
    logic [2:0] slot0_control_subclass_oracle_c;
    logic [2:0] slot1_control_subclass_oracle_c;
    logic slot0_registered_ready_c;
    logic slot1_registered_ready_c;
    logic slot0_ordinary_for_pairing_c;
    logic slot1_ordinary_for_pairing_c;
    logic complex_pairing_detail_error_c;
    logic slot1_same_cycle_wb_c;
    logic slot1_same_cycle_wb_complex_c;
    bbus_ooo_writeback_t slot1_same_cycle_wb_data_c;
    logic commit2_candidate_c;
    logic store_done_q;
    logic store_done_effective_c;
    logic store_owner_valid_q;
    bbus_ooo_rob_tag_t store_owner_tag_q;
    logic commit_store_request_fire_c;
    logic precise_store_accept_done_c;
    logic head_store_wb0_c, head_store_wb1_c, head_store_wb_valid_c;
    bbus_ooo_writeback_t head_store_wb_c;

    assign commit_store_rob_tag_o = '{
        valid: valid_q[head_q] && is_store_q[head_q],
        gen: gen_q[head_q],
        idx: head_q
    };
    assign precise_store_accept_done_c =
        PRECISE_STORE_ACCEPT_RETIRE_ENABLE &&
        commit_store_accept_is_done_i && commit_store_request_fire_c;
    assign commit_store_done_match_o =
        commit_store_done_i && !operation_blocked_c && valid_q[head_q] &&
        is_store_q[head_q] &&
        (!COMMIT_STORE_TAG_CHECK_ENABLE ||
         (store_owner_valid_q && commit_store_done_rob_tag_i.valid &&
          (store_owner_tag_q == commit_store_done_rob_tag_i) &&
          (commit_store_rob_tag_o == commit_store_done_rob_tag_i)));
    assign commit_store_done_drop_o =
        COMMIT_STORE_TAG_CHECK_ENABLE && commit_store_done_i &&
        !operation_blocked_c &&
        !commit_store_done_match_o;
    assign commit_store_done_clear_o =
        commit_store_done_match_o || commit_store_done_drop_o;
    assign commit_store_fault_match_o =
        (commit_store_fault_i === 1'b1) && !operation_blocked_c &&
        valid_q[head_q] && is_store_q[head_q] &&
        store_owner_valid_q && commit_store_fault_rob_tag_i.valid &&
        (store_owner_tag_q == commit_store_fault_rob_tag_i) &&
        (commit_store_rob_tag_o == commit_store_fault_rob_tag_i);
    assign commit_store_fault_drop_o =
        COMMIT_STORE_TAG_CHECK_ENABLE &&
        (commit_store_fault_i === 1'b1) && !operation_blocked_c &&
        !commit_store_fault_match_o;
    assign commit_store_fault_clear_o =
        commit_store_fault_match_o || commit_store_fault_drop_o;
    assign store_done_effective_c =
        store_done_q || commit_store_done_match_o ||
        precise_store_accept_done_c;

    assign head1 = bump(head_q, 2'd1);
    assign free_count_full = `BBUS_OOO_ROB_ENTRIES - count_q;
    assign free_slots = (free_count_full >= 4'd2) ? 2'd2 : free_count_full[1:0];
    assign available_slots_o = operation_blocked_c ? 2'b00 : free_slots;
    assign alloc_fire_mask_o[0] = !operation_blocked_c &&
        alloc_valid_mask_i[0] && (free_slots >= 2'd1);
    assign alloc_fire_mask_o[1] = !operation_blocked_c &&
        alloc_valid_mask_i[1] && alloc_valid_mask_i[0] &&
        (free_slots >= 2'd2);

    assign alloc_tag0_o = '{
        valid: alloc_fire_mask_o[0],
        gen: gen_q[tail_q] + 2'd1,
        idx: tail_q
    };
    assign alloc_tag1_o = '{
        valid: alloc_fire_mask_o[1],
        gen: gen_q[bump(tail_q, 2'd1)] + 2'd1,
        idx: bump(tail_q, 2'd1)
    };
    assign alloc_count_c = {1'b0, alloc_fire_mask_o[0]} +
        {1'b0, alloc_fire_mask_o[1]};
    assign alloc_post_tail_idx_c = bump(tail_q, alloc_count_c);
    assign alloc_post_tail_tag_o = '{
        valid: (alloc_count_c != 0),
        gen: gen_q[alloc_post_tail_idx_c] + 2'd1,
        idx: alloc_post_tail_idx_c
    };

    always_comb begin : selective_squash_preview
        bbus_ooo_rob_idx_t kill_idx;
        bbus_ooo_rob_idx_t expected_tail_idx;
        logic expected_boundary_gen_match;

        selective_branch_distance_c = distance_from_head(
            selective_squash_branch_tag_i.idx);
        selective_survivor_count_c = selective_branch_distance_c + 4'd1;
        selective_branch_match_c = selective_squash_branch_tag_i.valid &&
            (selective_branch_distance_c < count_q) &&
            valid_q[selective_squash_branch_tag_i.idx] &&
            is_control_q[selective_squash_branch_tag_i.idx] &&
            (gen_q[selective_squash_branch_tag_i.idx] ==
             selective_squash_branch_tag_i.gen);
        expected_tail_idx = advance(selective_squash_branch_tag_i.idx, 4'd1);
        expected_boundary_gen_match = 1'b0;
        if (selective_survivor_count_c < count_q) begin
            expected_boundary_gen_match =
                valid_q[expected_tail_idx] &&
                (gen_q[expected_tail_idx] ==
                 selective_squash_post_tail_tag_i.gen);
        end else begin
            expected_boundary_gen_match =
                (tail_q == expected_tail_idx) &&
                ((gen_q[expected_tail_idx] + 2'd1) ==
                 selective_squash_post_tail_tag_i.gen);
        end
        selective_boundary_match_c =
            selective_squash_post_tail_tag_i.valid &&
            (selective_squash_post_tail_tag_i.idx == expected_tail_idx) &&
            expected_boundary_gen_match;
        selective_squash_ready_o = !flush_i && selective_branch_match_c &&
            selective_boundary_match_c;
        selective_killed_rob_mask_o = '0;
        selective_killed_phys_mask_o = '0;
        selective_killed_count_o = '0;
        kill_idx = '0;
        // Preview masks are valid as soon as the exact branch and checkpoint
        // boundary identity is ready.  The atomic coordinator uses this
        // side-effect-free preview to validate Rename and the other sinks
        // before it allows selective_squash_valid_i to commit the truncation.
        if (selective_squash_ready_o) begin
            selective_killed_count_o = count_q - selective_survivor_count_c;
            for (int age = 0; age < `BBUS_OOO_ROB_ENTRIES; age = age + 1) begin
                if ((age >= selective_survivor_count_c) && (age < count_q)) begin
                    kill_idx = advance(head_q, age[3:0]);
                    selective_killed_rob_mask_o[kill_idx] = valid_q[kill_idx];
                    if (valid_q[kill_idx] && rf_wen_q[kill_idx] &&
                        (phys_new_q[kill_idx] != `BBUS_OOO_PHYS_ZERO)) begin
                        selective_killed_phys_mask_o[phys_new_q[kill_idx]] = 1'b1;
                    end
                end
            end
        end
    end

    assign selective_squash_fire_o = selective_squash_valid_i &&
        selective_squash_ready_o;

    assign operation_blocked_c = flush_i || selective_squash_valid_i;
    assign selective_squash_identity_error_o = selective_squash_identity_error_q;

    // 04: stale writeback gen filter, plus phys_rd consistency for normal writes.
    assign wb_tag_match = wb_tag_matches(writeback_i);
    assign wb_phys_match = wb_phys_matches(writeback_i);
    // A completed ROB entry must reject every replay lane, including lane0.
    // Otherwise a held final packet can update PRF/IQ after ROB ignores it.
    assign wb_accept =
        !flush_i && (!selective_squash_valid_i || selective_squash_fire_o) &&
        wb_tag_match &&
        !(selective_squash_fire_o &&
          selective_killed_rob_mask_o[writeback_i.rob_tag.idx]) &&
        wb_phys_match &&
        !done_q[writeback_i.rob_tag.idx];
    assign wb1_tag_match = wb_tag_matches(writeback1_i);
    assign wb1_phys_match = wb_phys_matches(writeback1_i);
    assign wb1_accept =
        !flush_i && (!selective_squash_valid_i || selective_squash_fire_o) &&
        wb1_tag_match &&
        !(selective_squash_fire_o &&
          selective_killed_rob_mask_o[writeback1_i.rob_tag.idx]) &&
        wb1_phys_match &&
        !(wb_accept && writeback_i.rob_tag.valid && writeback1_i.rob_tag.valid &&
          (writeback_i.rob_tag == writeback1_i.rob_tag)) &&
        !done_q[writeback1_i.rob_tag.idx];
    assign writeback_accepted_o = wb_accept;
    assign writeback1_accepted_o = wb1_accept;
    // A final, exact ordinary load or ALU writeback may close the ROB-head
    // done bubble on the consume edge. Raw wakeup, serial, store, and
    // exceptional packets remain on the registered done path so retirement
    // stays response-precise.
    assign head_same_cycle_wb0_c =
        wb_accept && writeback_i.done &&
        (writeback_i.rob_tag.idx == head_q) &&
        !writeback_i.exception.valid && !writeback_i.is_store &&
        !writeback_i.redirect_valid &&
        !is_store_q[head_q] && !is_ebreak_q[head_q] &&
        (((!writeback_i.is_control && !writeback_i.is_csr &&
           !writeback_i.is_system) &&
          ((HEAD_LOAD_WRITEBACK_COMMIT_BYPASS_ENABLE &&
            (fu_type_q[head_q] == BBUS_OOO_FU_LSU) &&
            is_load_q[head_q] && writeback_i.is_load) ||
           (HEAD_ALU_WRITEBACK_COMMIT_BYPASS_ENABLE &&
            (fu_type_q[head_q] == BBUS_OOO_FU_ALU) &&
            !is_load_q[head_q] && !writeback_i.is_load))) ||
         (HEAD_BRU_WRITEBACK_COMMIT_BYPASS_ENABLE &&
          (fu_type_q[head_q] == BBUS_OOO_FU_BRU) &&
          writeback_i.is_control &&
          (writeback_i.is_branch || writeback_i.is_jal ||
           writeback_i.is_jalr)));
    assign head_same_cycle_wb1_c =
        wb1_accept && writeback1_i.done &&
        (writeback1_i.rob_tag.idx == head_q) &&
        !writeback1_i.exception.valid && !writeback1_i.is_store &&
        !writeback1_i.redirect_valid &&
        !is_store_q[head_q] && !is_ebreak_q[head_q] &&
        (((!writeback1_i.is_control && !writeback1_i.is_csr &&
           !writeback1_i.is_system) &&
          ((HEAD_LOAD_WRITEBACK_COMMIT_BYPASS_ENABLE &&
            (fu_type_q[head_q] == BBUS_OOO_FU_LSU) &&
            is_load_q[head_q] && writeback1_i.is_load) ||
           (HEAD_ALU_WRITEBACK_COMMIT_BYPASS_ENABLE &&
            (fu_type_q[head_q] == BBUS_OOO_FU_ALU) &&
            !is_load_q[head_q] && !writeback1_i.is_load))) ||
         (HEAD_BRU_WRITEBACK_COMMIT_BYPASS_ENABLE &&
          (fu_type_q[head_q] == BBUS_OOO_FU_BRU) &&
          writeback1_i.is_control &&
          (writeback1_i.is_branch || writeback1_i.is_jal ||
           writeback1_i.is_jalr)));
    assign head_same_cycle_wb_valid_c =
        head_same_cycle_wb0_c || head_same_cycle_wb1_c;
    assign head1_same_cycle_wb0_c =
        wb_accept && writeback_i.done &&
        (writeback_i.rob_tag.idx == head1) &&
        (gen_q[head1] == writeback_i.rob_tag.gen) &&
        !writeback_i.exception.valid;
    assign head1_same_cycle_wb1_c = wb1_accept &&
        writeback1_i.done && (writeback1_i.rob_tag.idx == head1) &&
        !writeback1_i.exception.valid && !writeback1_i.is_store &&
        !writeback1_i.is_control && !writeback1_i.redirect_valid &&
        !writeback1_i.is_csr && !writeback1_i.is_system &&
        !is_store_q[head1] && !is_ebreak_q[head1] &&
        (((HEAD_LOAD_WRITEBACK_COMMIT_BYPASS_ENABLE &&
           (fu_type_q[head1] == BBUS_OOO_FU_LSU) &&
           is_load_q[head1] && writeback1_i.is_load)) ||
         (SLOT1_FINAL_WRITEBACK_COMMIT_BYPASS_ENABLE &&
          HEAD_ALU_WRITEBACK_COMMIT_BYPASS_ENABLE &&
          (fu_type_q[head1] == BBUS_OOO_FU_ALU) &&
          !is_load_q[head1] && !writeback1_i.is_load));
    assign head1_exact_wb0_alu_c = wb_accept && writeback_i.done &&
        (writeback_i.rob_tag.idx == head1) &&
        (gen_q[head1] == writeback_i.rob_tag.gen) &&
        !writeback_i.exception.valid && !writeback_i.is_store &&
        !writeback_i.is_control && !writeback_i.redirect_valid &&
        !writeback_i.is_csr && !writeback_i.is_system &&
        !is_store_q[head1] && !is_ebreak_q[head1] &&
        (fu_type_q[head1] == BBUS_OOO_FU_ALU) && !is_load_q[head1] &&
        !writeback_i.is_load;
    assign head1_exact_wb1_alu_c = wb1_accept && writeback1_i.done &&
        (writeback1_i.rob_tag.idx == head1) &&
        (gen_q[head1] == writeback1_i.rob_tag.gen) &&
        !writeback1_i.exception.valid && !writeback1_i.is_store &&
        !writeback1_i.is_control && !writeback1_i.redirect_valid &&
        !writeback1_i.is_csr && !writeback1_i.is_system &&
        !is_store_q[head1] && !is_ebreak_q[head1] &&
        (fu_type_q[head1] == BBUS_OOO_FU_ALU) && !is_load_q[head1] &&
        !writeback1_i.is_load;
    assign head1_exact_wb1_load_c = wb1_accept && writeback1_i.done &&
        (writeback1_i.rob_tag.idx == head1) &&
        (gen_q[head1] == writeback1_i.rob_tag.gen) &&
        !writeback1_i.exception.valid && !writeback1_i.is_store &&
        !writeback1_i.is_control && !writeback1_i.redirect_valid &&
        !writeback1_i.is_csr && !writeback1_i.is_system &&
        !is_store_q[head1] && !is_ebreak_q[head1] &&
        (fu_type_q[head1] == BBUS_OOO_FU_LSU) && is_load_q[head1] &&
        writeback1_i.is_load;
    assign head1_exact_wb1_other_c = wb1_accept && writeback1_i.done &&
        (writeback1_i.rob_tag.idx == head1) &&
        (gen_q[head1] == writeback1_i.rob_tag.gen) &&
        !head1_exact_wb1_alu_c && !head1_exact_wb1_load_c;
    always_comb begin
        head_same_cycle_wb_c = '0;
        if (head_same_cycle_wb0_c)
            head_same_cycle_wb_c = writeback_i;
        else if (head_same_cycle_wb1_c)
            head_same_cycle_wb_c = writeback1_i;

        slot1_same_cycle_wb_data_c = '0;
        if (head1_same_cycle_wb0_c)
            slot1_same_cycle_wb_data_c = writeback_i;
        else if (head1_same_cycle_wb1_c)
            slot1_same_cycle_wb_data_c = writeback1_i;
    end
    assign head_store_wb0_c = PRECISE_STORE_ACCEPT_RETIRE_ENABLE &&
        wb_accept && writeback_i.done && writeback_i.is_store &&
        !writeback_i.exception.valid &&
        (writeback_i.rob_tag.idx == head_q);
    assign head_store_wb1_c = PRECISE_STORE_ACCEPT_RETIRE_ENABLE &&
        wb1_accept && writeback1_i.done && writeback1_i.is_store &&
        !writeback1_i.exception.valid &&
        (writeback1_i.rob_tag.idx == head_q);
    assign head_store_wb_valid_c = head_store_wb0_c || head_store_wb1_c;
    always_comb begin
        head_store_wb_c = '0;
        if (head_store_wb0_c)
            head_store_wb_c = writeback_i;
        else if (head_store_wb1_c)
            head_store_wb_c = writeback1_i;
    end
    assign writeback_probe0_match_o =
        !flush_i && (!selective_squash_valid_i || selective_squash_fire_o) &&
        wb_tag_matches(writeback_probe0_i) &&
        !(selective_squash_fire_o &&
          selective_killed_rob_mask_o[writeback_probe0_i.rob_tag.idx]) &&
        wb_phys_matches(writeback_probe0_i) &&
        !done_q[writeback_probe0_i.rob_tag.idx];
    assign writeback_probe1_match_o =
        !flush_i && (!selective_squash_valid_i || selective_squash_fire_o) &&
        wb_tag_matches(writeback_probe1_i) &&
        !(selective_squash_fire_o &&
          selective_killed_rob_mask_o[writeback_probe1_i.rob_tag.idx]) &&
        wb_phys_matches(writeback_probe1_i) &&
        !done_q[writeback_probe1_i.rob_tag.idx];

    always_comb begin
        for (int raw_i = 0; raw_i < 9; raw_i = raw_i + 1) begin
            raw_probe_fresh_mask_o[raw_i] =
                !flush_i &&
                (!selective_squash_valid_i || selective_squash_fire_o) &&
                raw_probe_valid_mask_i[raw_i] &&
                wb_tag_matches(raw_probe_wb_i[raw_i]) &&
                !(selective_squash_fire_o &&
                  selective_killed_rob_mask_o[
                      raw_probe_wb_i[raw_i].rob_tag.idx]) &&
                wb_phys_matches(raw_probe_wb_i[raw_i]) &&
                !done_q[raw_probe_wb_i[raw_i].rob_tag.idx];
        end
    end

    always_comb begin
        logic slot0_ready_normal;
        logic slot0_exception;
        logic slot0_store;
        logic slot0_ebreak;
        logic slot0_fence;
        logic slot0_fencei;

        commit_event_c = '0;
        commit_event_c.side_effect_kind = BBUS_OOO_SIDE_NONE;
        commit_event_c.control_event = BBUS_OOO_CTRL_NONE;
        commit_count_c = 2'd0;
        commit_store_valid_o = 1'b0;
        commit_store_addr_o = head_store_wb_valid_c ?
            head_store_wb_c.mem_addr : mem_addr_q[head_q];
        commit_store_wdata_o = head_store_wb_valid_c ?
            head_store_wb_c.mem_wdata : mem_wdata_q[head_q];
        commit_store_wstrb_o = head_store_wb_valid_c ?
            head_store_wb_c.mem_wstrb : mem_wstrb_q[head_q];
        commit_store_len_o = head_store_wb_valid_c ?
            head_store_wb_c.mem_len : mem_len_q[head_q];

        slot0_exception = valid_q[head_q] && done_q[head_q] && exception_q[head_q].valid;
        slot0_ready_normal =
            (valid_q[head_q] && done_q[head_q] && !exception_q[head_q].valid) ||
            head_same_cycle_wb_valid_c;
        slot0_store = (slot0_ready_normal && is_store_q[head_q]) ||
            head_store_wb_valid_c;
        slot0_ebreak = valid_q[head_q] && done_q[head_q] &&
            !exception_q[head_q].valid && is_ebreak_q[head_q];
        slot0_fence = valid_q[head_q] && done_q[head_q] &&
            !exception_q[head_q].valid &&
            (instr_q[head_q][6:0] == 7'b0001111) &&
            (instr_q[head_q][14:12] == 3'b000) &&
            (instr_q[head_q][11:7] == 5'd0) &&
            (instr_q[head_q][19:15] == 5'd0);
        slot0_fencei = valid_q[head_q] && done_q[head_q] &&
            !exception_q[head_q].valid &&
            (instr_q[head_q] == 32'h0000_100f);
        slot1_same_cycle_wb_c =
            head1_same_cycle_wb0_c || head1_same_cycle_wb1_c;
        slot1_same_cycle_wb_complex_c =
            slot1_same_cycle_wb_data_c.is_store ||
            (slot1_same_cycle_wb_data_c.is_control &&
             !(CORRECT_BRANCH_DUAL_RETIRE_ENABLE &&
               wb_correct_conditional_branch(
                   slot1_same_cycle_wb_data_c))) ||
            slot1_same_cycle_wb_data_c.is_csr ||
            slot1_same_cycle_wb_data_c.is_system ||
            is_ebreak_q[head1] ||
            (fu_type_q[head1] == BBUS_OOO_FU_AMO);
        slot0_ready_for_commit2_c =
            slot_ready_no_exception(head_q) || head_same_cycle_wb_valid_c;
        slot1_ready_for_commit2_c = slot_ready_no_exception(head1) || slot1_same_cycle_wb_c;
        slot0_p64_strict_ordinary_c =
            slot0_ready_for_commit2_c &&
            (slot_ready_no_exception(head_q) ?
                slot_p64_strict_ordinary(head_q) :
                wb_p64_strict_ordinary(head_same_cycle_wb_c, head_q));
        slot1_p64_safe_control_c =
            slot1_ready_for_commit2_c &&
            (slot_ready_no_exception(head1) ?
                slot_p64_safe_control(head1) :
                wb_p64_safe_control(slot1_same_cycle_wb_data_c, head1));
        slot1_p64_allow_c =
            YOUNGER_SLOT1_CONTROL_DUAL_RETIRE_ENABLE &&
            slot0_p64_strict_ordinary_c && slot1_p64_safe_control_c;
        slot0_complex_for_commit2_c =
            slot0_ready_for_commit2_c &&
            (slot_ready_no_exception(head_q) ?
                slot_commit2_complex(head_q) : 1'b0);
        slot1_complex_for_commit2_c =
            slot1_ready_for_commit2_c &&
            (slot_ready_no_exception(head1) ?
                slot_commit2_complex(head1) :
                slot1_same_cycle_wb_complex_c) &&
            !slot1_p64_allow_c;
        slot0_commit2_ok_c =
            slot0_ready_for_commit2_c && !slot0_complex_for_commit2_c;
        slot1_commit2_ok_c =
            slot1_ready_for_commit2_c &&
            !slot1_complex_for_commit2_c;
        commit2_candidate_c =
            COMMIT2_ENABLE &&
            commit_enable_i &&
            valid_q[head_q] &&
            (count_q > 4'd1);

        if (!operation_blocked_c && commit_enable_i && slot0_exception) begin
            commit_event_c.control_event_valid = 1'b1;
            commit_event_c.control_event = BBUS_OOO_CTRL_EXCEPTION;
            commit_event_c.slot0 = make_slot(head_q);
            commit_count_c = 2'd1;
        end else if (!operation_blocked_c && commit_enable_i && slot0_ebreak) begin
            commit_event_c.control_event_valid = 1'b1;
            commit_event_c.control_event = BBUS_OOO_CTRL_EBREAK;
            commit_event_c.slot0 = make_slot(head_q);
            commit_count_c = 2'd1;
        end else if (!operation_blocked_c && commit_enable_i && slot0_store) begin
            commit_store_valid_o =
                !(store_done_q || commit_store_done_match_o) &&
                (!COMMIT_STORE_TAG_CHECK_ENABLE || !store_owner_valid_q);
            if (store_done_effective_c) begin
                commit_event_c.normal_commit_mask[0] = 1'b1;
                commit_event_c.side_effect_commit_valid = 1'b1;
                commit_event_c.side_effect_kind = BBUS_OOO_SIDE_STORE;
                commit_event_c.slot0 = head_store_wb_valid_c ?
                    make_slot_with_writeback(head_q, head_store_wb_c) :
                    make_slot(head_q);
                commit_count_c = 2'd1;
            end
        end else if (!operation_blocked_c && commit_enable_i && slot0_ready_normal) begin
            commit_event_c.normal_commit_mask[0] = 1'b1;
            commit_event_c.slot0 = head_same_cycle_wb_valid_c ?
                make_slot_with_writeback(head_q, head_same_cycle_wb_c) :
                make_slot(head_q);
            commit_count_c = 2'd1;
            if (slot0_fence) begin
                commit_event_c.side_effect_commit_valid = 1'b1;
                commit_event_c.side_effect_kind = BBUS_OOO_SIDE_FENCE;
            end else if (slot0_fencei) begin
                commit_event_c.control_event_valid = 1'b1;
                commit_event_c.control_event = BBUS_OOO_CTRL_FENCEI;
            end
            // Commit2 remains normal-mask-only. P21/P64 selectively classify
            // safe control entries as normal; side-effect and serial classes
            // still degrade to Commit1 at this precise boundary.
            if (COMMIT2_ENABLE && (count_q > 4'd1) &&
                slot0_commit2_ok_c && slot1_commit2_ok_c) begin
                commit_event_c.normal_commit_mask[1] = 1'b1;
                commit_event_c.slot1 =
                    slot_ready_no_exception(head1) ?
                    make_slot(head1) :
                    make_slot_with_writeback(
                        head1, slot1_same_cycle_wb_data_c);
                commit_count_c = 2'd2;
            end
        end
    end

    assign commit_event_o = commit_event_c;
    assign commit_store_request_fire_c =
        commit_store_valid_o && commit_store_ready_i;
    assign debug_commit_width_mode_o = COMMIT2_ENABLE ? 2'd2 : 2'd1;
    assign debug_commit2_candidate_o = commit2_candidate_c;
    assign debug_commit2_fire_o =
        commit_event_c.normal_commit_mask[0] &&
        commit_event_c.normal_commit_mask[1];
    assign debug_commit2_slot0_only_o =
        commit_event_c.normal_commit_mask[0] &&
        !commit_event_c.normal_commit_mask[1];
    assign debug_commit2_block_slot0_not_ready_o =
        commit2_candidate_c && !slot0_ready_for_commit2_c;
    assign debug_commit2_block_slot1_not_ready_o =
        commit2_candidate_c &&
        slot0_commit2_ok_c &&
        !slot1_ready_for_commit2_c;
    assign debug_commit2_block_slot0_complex_o =
        commit2_candidate_c && slot0_ready_for_commit2_c && slot0_complex_for_commit2_c;
    assign debug_commit2_block_slot1_complex_o =
        commit2_candidate_c &&
        slot0_commit2_ok_c &&
        slot1_ready_for_commit2_c &&
        slot1_complex_for_commit2_c;
    assign debug_commit2_slot1_without_slot0_bug_o =
        commit_event_c.normal_commit_mask[1] &&
        !commit_event_c.normal_commit_mask[0];
    assign debug_commit2_complex_slot_bug_o =
        debug_commit2_fire_o &&
        (slot0_complex_for_commit2_c || slot1_complex_for_commit2_c);
    assign slot1_not_ready_target_c = commit2_candidate_c &&
        slot0_commit2_ok_c && !slot1_ready_for_commit2_c;
    assign complex_single_target_c = perf_commit_reason1_o == 4'd7;
    assign complex_single_slot0_c = complex_single_target_c &&
        (slot0_complex_for_commit2_c || !slot1_complex_for_commit2_c);
    assign complex_single_slot1_c = complex_single_target_c &&
        !slot0_complex_for_commit2_c && slot1_complex_for_commit2_c;
    assign complex_single_class_c = !complex_single_target_c ? 3'd0 :
        (slot0_complex_for_commit2_c ?
            slot_commit2_complex_class(head_q) :
         slot1_complex_for_commit2_c ?
            slot_commit2_complex_class(head1) : 3'd6);
    assign complex_single_detail_error_c = complex_single_target_c &&
        (!(complex_single_slot0_c ^ complex_single_slot1_c) ||
         (complex_single_class_c == 3'd0));
    assign complex_control_subclass_c =
        (complex_single_class_c != 3'd2) ? 3'd0 :
        complex_single_slot0_c ? slot_control_subclass(head_q) :
        slot_control_subclass(head1);
    assign complex_control_detail_error_c = complex_single_target_c &&
        (((complex_single_class_c == 3'd2) &&
          (complex_control_subclass_c == 3'd0)) ||
         ((complex_single_class_c != 3'd2) &&
          (complex_control_subclass_c != 3'd0)));
    assign perf_slot1_bypass_oracle_o = {
        complex_control_detail_error_c,
        complex_control_subclass_c,
        complex_single_detail_error_c,
        complex_single_class_c,
        complex_single_slot1_c,
        complex_single_slot0_c,
        complex_single_target_c,
        slot1_not_ready_target_c && head1_exact_wb1_other_c,
        slot1_not_ready_target_c && head1_exact_wb1_load_c,
        slot1_not_ready_target_c && head1_exact_wb1_alu_c,
        head1_exact_wb0_alu_c,
        head1_exact_wb1_other_c,
        head1_exact_wb1_load_c,
        head1_exact_wb1_alu_c,
        slot1_not_ready_target_c
    };

    assign slot0_registered_ready_c = slot_ready_no_exception(head_q);
    assign slot1_registered_ready_c = slot_ready_no_exception(head1);
    assign slot0_semantic_class_c =
        (head_same_cycle_wb_valid_c && !slot0_registered_ready_c) ?
            wb_commit2_complex_class(head_same_cycle_wb_c, head_q) :
            slot_commit2_complex_class(head_q);
    assign slot1_semantic_class_c =
        (slot1_same_cycle_wb_c && !slot1_registered_ready_c) ?
            wb_commit2_complex_class(slot1_same_cycle_wb_data_c, head1) :
            slot_commit2_complex_class(head1);
    assign slot0_control_subclass_oracle_c =
        (slot0_semantic_class_c != 3'd2) ? 3'd0 :
        (head_same_cycle_wb_valid_c && !slot0_registered_ready_c) ?
            wb_control_subclass(head_same_cycle_wb_c) :
            slot_control_subclass(head_q);
    assign slot1_control_subclass_oracle_c =
        (slot1_semantic_class_c != 3'd2) ? 3'd0 :
        (slot1_same_cycle_wb_c && !slot1_registered_ready_c) ?
            wb_control_subclass(slot1_same_cycle_wb_data_c) :
            slot_control_subclass(head1);
    assign slot0_ordinary_for_pairing_c =
        slot0_ready_for_commit2_c && !slot0_complex_for_commit2_c;
    assign slot1_ordinary_for_pairing_c =
        slot1_ready_for_commit2_c && !slot1_complex_for_commit2_c;
    assign complex_pairing_detail_error_c =
        complex_single_target_c &&
        (!commit2_candidate_c || !commit_event_c.slot0.valid ||
         commit_event_c.slot1.valid ||
         !(slot0_complex_for_commit2_c || slot1_complex_for_commit2_c) ||
         !valid_q[head1] ||
         (slot0_semantic_class_c == 3'd0) ||
         (slot1_semantic_class_c == 3'd0));

    always_comb begin
        perf_complex_retire_pairing_o = '0;
        perf_complex_retire_pairing_o[0] = complex_single_target_c;
        perf_complex_retire_pairing_o[1] = slot0_ready_for_commit2_c;
        perf_complex_retire_pairing_o[2] = slot1_ready_for_commit2_c;
        perf_complex_retire_pairing_o[3] = slot0_complex_for_commit2_c;
        perf_complex_retire_pairing_o[4] = slot1_complex_for_commit2_c;
        perf_complex_retire_pairing_o[5] = slot0_ordinary_for_pairing_c;
        perf_complex_retire_pairing_o[6] = slot1_ordinary_for_pairing_c;
        perf_complex_retire_pairing_o[7] = commit_event_c.slot0.valid;
        perf_complex_retire_pairing_o[8] = commit_event_c.slot1.valid;
        perf_complex_retire_pairing_o[9] =
            commit_event_c.side_effect_commit_valid &&
            (commit_event_c.side_effect_kind == BBUS_OOO_SIDE_STORE);
        perf_complex_retire_pairing_o[10] = redirect_valid_q[head_q];
        perf_complex_retire_pairing_o[11] =
            (slot1_same_cycle_wb_c && !slot1_registered_ready_c) ?
                slot1_same_cycle_wb_data_c.redirect_valid :
                redirect_valid_q[head1];
        perf_complex_retire_pairing_o[12] =
            slot0_semantic_class_c == 3'd2 &&
            slot0_control_subclass_oracle_c == 3'd1;
        perf_complex_retire_pairing_o[13] =
            slot1_semantic_class_c == 3'd2 &&
            slot1_control_subclass_oracle_c == 3'd1;
        perf_complex_retire_pairing_o[14] =
            slot0_semantic_class_c == 3'd2 &&
            ((slot0_control_subclass_oracle_c == 3'd3) ||
             (slot0_control_subclass_oracle_c == 3'd4)) &&
            !perf_complex_retire_pairing_o[10];
        perf_complex_retire_pairing_o[15] =
            slot1_semantic_class_c == 3'd2 &&
            ((slot1_control_subclass_oracle_c == 3'd3) ||
             (slot1_control_subclass_oracle_c == 3'd4)) &&
            !perf_complex_retire_pairing_o[11];
        perf_complex_retire_pairing_o[16] = exception_q[head_q].valid;
        perf_complex_retire_pairing_o[17] =
            (slot1_same_cycle_wb_c && !slot1_registered_ready_c) ?
                slot1_same_cycle_wb_data_c.exception.valid :
                exception_q[head1].valid;
        perf_complex_retire_pairing_o[18] = head_same_cycle_wb_valid_c;
        perf_complex_retire_pairing_o[19] = slot1_same_cycle_wb_c;
        perf_complex_retire_pairing_o[20] = store_done_effective_c;
        perf_complex_retire_pairing_o[21] = commit_enable_i;
        perf_complex_retire_pairing_o[22] = commit2_candidate_c;
        perf_complex_retire_pairing_o[23] = complex_pairing_detail_error_c;
        perf_complex_retire_pairing_o[28:24] = {gen_q[head_q], head_q};
        perf_complex_retire_pairing_o[29] = valid_q[head_q];
        perf_complex_retire_pairing_o[34:30] = {gen_q[head1], head1};
        perf_complex_retire_pairing_o[35] = valid_q[head1];
        perf_complex_retire_pairing_o[38:36] = slot0_semantic_class_c;
        perf_complex_retire_pairing_o[41:39] = slot1_semantic_class_c;
        perf_complex_retire_pairing_o[44:42] =
            slot0_control_subclass_oracle_c;
        perf_complex_retire_pairing_o[47:45] =
            slot1_control_subclass_oracle_c;
        perf_complex_retire_pairing_o[48] = is_store_q[head_q];
        perf_complex_retire_pairing_o[49] = is_store_q[head1];
        perf_complex_retire_pairing_o[50] = is_control_q[head_q];
        perf_complex_retire_pairing_o[51] = is_control_q[head1];
        perf_complex_retire_pairing_o[52] = is_csr_q[head_q];
        perf_complex_retire_pairing_o[53] = is_csr_q[head1];
        perf_complex_retire_pairing_o[54] =
            is_system_q[head_q] || is_ebreak_q[head_q];
        perf_complex_retire_pairing_o[55] =
            is_system_q[head1] || is_ebreak_q[head1];
        perf_complex_retire_pairing_o[56] =
            fu_type_q[head_q] == BBUS_OOO_FU_AMO;
        perf_complex_retire_pairing_o[57] =
            fu_type_q[head1] == BBUS_OOO_FU_AMO;
        perf_complex_retire_pairing_o[58] = slot0_registered_ready_c;
        perf_complex_retire_pairing_o[59] = slot1_registered_ready_c;
        perf_complex_retire_pairing_o[60] =
            complex_single_target_c &&
            (slot0_complex_for_commit2_c ^ slot1_complex_for_commit2_c) &&
            slot0_ready_for_commit2_c && slot1_ready_for_commit2_c;
        perf_complex_retire_pairing_o[61] =
            perf_complex_retire_pairing_o[60] &&
            slot0_complex_for_commit2_c;
        perf_complex_retire_pairing_o[62] =
            perf_complex_retire_pairing_o[60] &&
            slot1_complex_for_commit2_c;
        perf_complex_retire_pairing_o[63] =
            complex_single_target_c &&
            (((slot0_semantic_class_c == 3'd2) !=
              (slot0_control_subclass_oracle_c != 3'd0)) ||
             ((slot1_semantic_class_c == 3'd2) !=
              (slot1_control_subclass_oracle_c != 3'd0)));
    end

    // Simulation-only retirement-slot attribution. Code zero means that the
    // slot retired; nonzero codes are exclusive and interpreted by npc/csrc.
    always_comb begin
        perf_commit_reason0_o = 4'd0;
        if (!commit_event_c.slot0.valid) begin
            if (flush_i) perf_commit_reason0_o = 4'd1;
            else if (!commit_enable_i) perf_commit_reason0_o = 4'd2;
            else if (count_q == 4'd0) perf_commit_reason0_o = 4'd3;
            else if (valid_q[head_q] && is_store_q[head_q] &&
                     !store_done_effective_c) perf_commit_reason0_o = 4'd5;
            else if (valid_q[head_q] &&
                     (fu_type_q[head_q] == BBUS_OOO_FU_AMO) &&
                     !done_q[head_q]) perf_commit_reason0_o = 4'd6;
            else if (valid_q[head_q] && !done_q[head_q]) begin
                case (fu_type_q[head_q])
                    BBUS_OOO_FU_ALU: perf_commit_reason0_o = 4'd4;
                    BBUS_OOO_FU_LSU: perf_commit_reason0_o = 4'd11;
                    BBUS_OOO_FU_BRU: perf_commit_reason0_o = 4'd12;
                    BBUS_OOO_FU_MDU: perf_commit_reason0_o = 4'd13;
                    BBUS_OOO_FU_CSR,
                    BBUS_OOO_FU_SYS: perf_commit_reason0_o = 4'd14;
                    default: perf_commit_reason0_o = 4'd15;
                endcase
            end
            else perf_commit_reason0_o = 4'd10;
        end

        perf_commit_reason1_o = 4'd0;
        if (!commit_event_c.slot1.valid) begin
            if (!commit_event_c.slot0.valid) begin
                perf_commit_reason1_o = perf_commit_reason0_o;
            end else if (count_q <= 4'd1) begin
                perf_commit_reason1_o = 4'd8;
            end else if (slot0_complex_for_commit2_c) begin
                perf_commit_reason1_o = 4'd7;
            end else if (!slot1_ready_for_commit2_c) begin
                perf_commit_reason1_o = 4'd9;
            end else if (slot1_complex_for_commit2_c) begin
                perf_commit_reason1_o = 4'd7;
            end else begin
                perf_commit_reason1_o = 4'd10;
            end
        end
    end

    assign debug_rob_valid_o = valid_q[debug_rob_idx_i];
    assign debug_rob_done_o = done_q[debug_rob_idx_i];
    assign debug_rob_result_o = result_q[debug_rob_idx_i];
    assign debug_rob_count_o = count_q;
    assign debug_rob_head_o = head_q;
    assign debug_rob_tail_o = tail_q;
    assign rob_head_tag_o = '{
        valid: valid_q[head_q],
        gen: gen_q[head_q],
        idx: head_q
    };

    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            head_q <= '0;
            tail_q <= '0;
            count_q <= '0;
            store_done_q <= 1'b0;
            store_owner_valid_q <= 1'b0;
            store_owner_tag_q <= '0;
            selective_squash_identity_error_q <= 1'b0;
            for (i = 0; i < `BBUS_OOO_ROB_ENTRIES; i = i + 1) begin
                valid_q[i] <= 1'b0;
                done_q[i] <= 1'b0;
                gen_q[i] <= '0;
                pc_q[i] <= 32'b0;
                instr_q[i] <= 32'b0;
                arch_rd_q[i] <= 5'b0;
                phys_new_q[i] <= `BBUS_OOO_PHYS_ZERO;
                phys_old_q[i] <= `BBUS_OOO_PHYS_ZERO;
                rf_wen_q[i] <= 1'b0;
                fu_type_q[i] <= BBUS_OOO_FU_NONE;
                branch_op_q[i] <= BBUS_OOO_BR_BEQ;
                is_load_q[i] <= 1'b0;
                is_store_q[i] <= 1'b0;
                is_ebreak_q[i] <= 1'b0;
                is_csr_q[i] <= 1'b0;
                is_system_q[i] <= 1'b0;
                csr_addr_q[i] <= 12'b0;
                csr_write_q[i] <= 1'b0;
                csr_wdata_q[i] <= 32'b0;
                mem_op_q[i] <= BBUS_OOO_MEM_NONE;
                mem_addr_q[i] <= 32'b0;
                mem_wdata_q[i] <= 32'b0;
                mem_wstrb_q[i] <= 4'b0;
                mem_len_q[i] <= 3'b0;
                result_q[i] <= 32'b0;
                result_valid_q[i] <= 1'b0;
                is_control_q[i] <= 1'b0;
                is_branch_q[i] <= 1'b0;
                is_jal_q[i] <= 1'b0;
                is_jalr_q[i] <= 1'b0;
                actual_taken_q[i] <= 1'b0;
                commit_nextpc_q[i] <= 32'b0;
                redirect_valid_q[i] <= 1'b0;
                selective_recovered_q[i] <= 1'b0;
                exception_q[i] <= '0;
            end
        end else if (flush_i) begin
            head_q <= '0;
            tail_q <= '0;
            count_q <= '0;
            store_done_q <= 1'b0;
            store_owner_valid_q <= 1'b0;
            store_owner_tag_q <= '0;
            selective_squash_identity_error_q <= 1'b0;
            for (i = 0; i < `BBUS_OOO_ROB_ENTRIES; i = i + 1) begin
                valid_q[i] <= 1'b0;
                done_q[i] <= 1'b0;
                pc_q[i] <= 32'b0;
                instr_q[i] <= 32'b0;
                arch_rd_q[i] <= 5'b0;
                phys_new_q[i] <= `BBUS_OOO_PHYS_ZERO;
                phys_old_q[i] <= `BBUS_OOO_PHYS_ZERO;
                rf_wen_q[i] <= 1'b0;
                fu_type_q[i] <= BBUS_OOO_FU_NONE;
                branch_op_q[i] <= BBUS_OOO_BR_BEQ;
                is_load_q[i] <= 1'b0;
                is_store_q[i] <= 1'b0;
                is_ebreak_q[i] <= 1'b0;
                is_csr_q[i] <= 1'b0;
                is_system_q[i] <= 1'b0;
                csr_addr_q[i] <= 12'b0;
                csr_write_q[i] <= 1'b0;
                csr_wdata_q[i] <= 32'b0;
                mem_op_q[i] <= BBUS_OOO_MEM_NONE;
                mem_addr_q[i] <= 32'b0;
                mem_wdata_q[i] <= 32'b0;
                mem_wstrb_q[i] <= 4'b0;
                mem_len_q[i] <= 3'b0;
                result_q[i] <= 32'b0;
                result_valid_q[i] <= 1'b0;
                is_control_q[i] <= 1'b0;
                is_branch_q[i] <= 1'b0;
                is_jal_q[i] <= 1'b0;
                is_jalr_q[i] <= 1'b0;
                actual_taken_q[i] <= 1'b0;
                commit_nextpc_q[i] <= 32'b0;
                redirect_valid_q[i] <= 1'b0;
                selective_recovered_q[i] <= 1'b0;
                exception_q[i] <= '0;
            end
        end else if (selective_squash_valid_i) begin
            if (!selective_squash_ready_o) begin
                selective_squash_identity_error_q <= 1'b1;
            end else begin
                if (wb_accept) begin
                    record_writeback(writeback_i);
                end
                if (wb1_accept) begin
                    record_writeback(writeback1_i);
                end
                tail_q <= selective_squash_post_tail_tag_i.idx;
                count_q <= selective_survivor_count_c;
                // The branch remains in the survivor prefix, but recovery
                // ownership is now complete and it may be considered for
                // the guarded P64 dual-retire path on the next cycle.
                selective_recovered_q[selective_squash_branch_tag_i.idx] <=
                    1'b1;
                if (store_owner_valid_q &&
                    selective_killed_rob_mask_o[store_owner_tag_q.idx] &&
                    (gen_q[store_owner_tag_q.idx] == store_owner_tag_q.gen)) begin
                    store_owner_valid_q <= 1'b0;
                    store_owner_tag_q <= '0;
                    store_done_q <= 1'b0;
                end
                for (i = 0; i < `BBUS_OOO_ROB_ENTRIES; i = i + 1) begin
                    if (selective_killed_rob_mask_o[i]) begin
                        valid_q[i] <= 1'b0;
                        done_q[i] <= 1'b0;
                        pc_q[i] <= 32'b0;
                        instr_q[i] <= 32'b0;
                        arch_rd_q[i] <= 5'b0;
                        phys_new_q[i] <= `BBUS_OOO_PHYS_ZERO;
                        phys_old_q[i] <= `BBUS_OOO_PHYS_ZERO;
                        rf_wen_q[i] <= 1'b0;
                        fu_type_q[i] <= BBUS_OOO_FU_NONE;
                        branch_op_q[i] <= BBUS_OOO_BR_BEQ;
                        is_load_q[i] <= 1'b0;
                        is_store_q[i] <= 1'b0;
                        is_ebreak_q[i] <= 1'b0;
                        is_csr_q[i] <= 1'b0;
                        is_system_q[i] <= 1'b0;
                        csr_addr_q[i] <= 12'b0;
                        csr_write_q[i] <= 1'b0;
                        csr_wdata_q[i] <= 32'b0;
                        mem_op_q[i] <= BBUS_OOO_MEM_NONE;
                        mem_addr_q[i] <= 32'b0;
                        mem_wdata_q[i] <= 32'b0;
                        mem_wstrb_q[i] <= 4'b0;
                        mem_len_q[i] <= 3'b0;
                        result_q[i] <= 32'b0;
                        result_valid_q[i] <= 1'b0;
                        is_control_q[i] <= 1'b0;
                        is_branch_q[i] <= 1'b0;
                        is_jal_q[i] <= 1'b0;
                        is_jalr_q[i] <= 1'b0;
                        actual_taken_q[i] <= 1'b0;
                        commit_nextpc_q[i] <= 32'b0;
                        redirect_valid_q[i] <= 1'b0;
                        selective_recovered_q[i] <= 1'b0;
                        exception_q[i] <= '0;
                    end
                end
            end
        end else begin
            logic [1:0] alloc_count;
            bbus_ooo_rob_idx_t alloc_idx0;
            bbus_ooo_rob_idx_t alloc_idx1;

            alloc_count = bit_count2(alloc_fire_mask_o);
            alloc_idx0 = tail_q;
            alloc_idx1 = bump(tail_q, 2'd1);

            if (COMMIT_STORE_TAG_CHECK_ENABLE) begin
                if (commit_store_done_match_o || commit_store_fault_match_o ||
                    precise_store_accept_done_c) begin
                    store_owner_valid_q <= 1'b0;
                    store_owner_tag_q <= '0;
                end else if (commit_store_request_fire_c) begin
                    store_owner_valid_q <= 1'b1;
                    store_owner_tag_q <= commit_store_rob_tag_o;
                end
            end

            if ((commit_count_c != 2'd0) && is_store_q[head_q]) begin
                store_done_q <= 1'b0;
            end else if (commit_store_done_match_o) begin
                store_done_q <= 1'b1;
            end

            if (commit_store_fault_match_o) begin
                done_q[head_q] <= 1'b1;
                store_done_q <= 1'b0;
                result_valid_q[head_q] <= 1'b0;
                exception_q[head_q].valid <= 1'b1;
                exception_q[head_q].cause <= 32'd15;
                exception_q[head_q].tval <= commit_store_fault_tval_i;
            end

            if (wb_accept) begin
                done_q[writeback_i.rob_tag.idx] <= writeback_i.done;
                result_q[writeback_i.rob_tag.idx] <= writeback_i.result;
                is_control_q[writeback_i.rob_tag.idx] <= writeback_i.is_control;
                is_branch_q[writeback_i.rob_tag.idx] <= writeback_i.is_branch;
                is_jal_q[writeback_i.rob_tag.idx] <= writeback_i.is_jal;
                is_jalr_q[writeback_i.rob_tag.idx] <= writeback_i.is_jalr;
                actual_taken_q[writeback_i.rob_tag.idx] <= writeback_i.actual_taken;
                is_load_q[writeback_i.rob_tag.idx] <= writeback_i.is_load;
                is_store_q[writeback_i.rob_tag.idx] <= writeback_i.is_store;
                is_csr_q[writeback_i.rob_tag.idx] <= writeback_i.is_csr;
                is_system_q[writeback_i.rob_tag.idx] <= writeback_i.is_system;
                csr_addr_q[writeback_i.rob_tag.idx] <= writeback_i.csr_addr;
                csr_write_q[writeback_i.rob_tag.idx] <= writeback_i.csr_write;
                csr_wdata_q[writeback_i.rob_tag.idx] <= writeback_i.csr_wdata;
                mem_op_q[writeback_i.rob_tag.idx] <= writeback_i.mem_op;
                mem_addr_q[writeback_i.rob_tag.idx] <= writeback_i.mem_addr;
                mem_wdata_q[writeback_i.rob_tag.idx] <= writeback_i.mem_wdata;
                mem_wstrb_q[writeback_i.rob_tag.idx] <= writeback_i.mem_wstrb;
                mem_len_q[writeback_i.rob_tag.idx] <= writeback_i.mem_len;
                commit_nextpc_q[writeback_i.rob_tag.idx] <=
                    writeback_i.is_control ? writeback_i.actual_nextpc :
                    (pc_q[writeback_i.rob_tag.idx] + 32'd4);
                redirect_valid_q[writeback_i.rob_tag.idx] <= writeback_i.redirect_valid;
                // 03/04: exception-only writeback does not produce a normal GPR result.
                result_valid_q[writeback_i.rob_tag.idx] <=
                    writeback_i.rf_wen &&
                    (writeback_i.phys_rd != `BBUS_OOO_PHYS_ZERO) &&
                    !writeback_i.exception.valid;
                if (writeback_i.exception.valid) begin
                    exception_q[writeback_i.rob_tag.idx] <= writeback_i.exception;
                    done_q[writeback_i.rob_tag.idx] <= 1'b1;
                    result_valid_q[writeback_i.rob_tag.idx] <= 1'b0;
                end
            end

            if (wb1_accept) begin
                done_q[writeback1_i.rob_tag.idx] <= writeback1_i.done;
                result_q[writeback1_i.rob_tag.idx] <= writeback1_i.result;
                is_control_q[writeback1_i.rob_tag.idx] <= writeback1_i.is_control;
                is_branch_q[writeback1_i.rob_tag.idx] <= writeback1_i.is_branch;
                is_jal_q[writeback1_i.rob_tag.idx] <= writeback1_i.is_jal;
                is_jalr_q[writeback1_i.rob_tag.idx] <= writeback1_i.is_jalr;
                actual_taken_q[writeback1_i.rob_tag.idx] <= writeback1_i.actual_taken;
                is_load_q[writeback1_i.rob_tag.idx] <= writeback1_i.is_load;
                is_store_q[writeback1_i.rob_tag.idx] <= writeback1_i.is_store;
                is_csr_q[writeback1_i.rob_tag.idx] <= writeback1_i.is_csr;
                is_system_q[writeback1_i.rob_tag.idx] <= writeback1_i.is_system;
                csr_addr_q[writeback1_i.rob_tag.idx] <= writeback1_i.csr_addr;
                csr_write_q[writeback1_i.rob_tag.idx] <= writeback1_i.csr_write;
                csr_wdata_q[writeback1_i.rob_tag.idx] <= writeback1_i.csr_wdata;
                mem_op_q[writeback1_i.rob_tag.idx] <= writeback1_i.mem_op;
                mem_addr_q[writeback1_i.rob_tag.idx] <= writeback1_i.mem_addr;
                mem_wdata_q[writeback1_i.rob_tag.idx] <= writeback1_i.mem_wdata;
                mem_wstrb_q[writeback1_i.rob_tag.idx] <= writeback1_i.mem_wstrb;
                mem_len_q[writeback1_i.rob_tag.idx] <= writeback1_i.mem_len;
                commit_nextpc_q[writeback1_i.rob_tag.idx] <=
                    writeback1_i.is_control ? writeback1_i.actual_nextpc :
                    (pc_q[writeback1_i.rob_tag.idx] + 32'd4);
                redirect_valid_q[writeback1_i.rob_tag.idx] <= writeback1_i.redirect_valid;
                result_valid_q[writeback1_i.rob_tag.idx] <=
                    writeback1_i.rf_wen &&
                    (writeback1_i.phys_rd != `BBUS_OOO_PHYS_ZERO) &&
                    !writeback1_i.exception.valid;
                if (writeback1_i.exception.valid) begin
                    exception_q[writeback1_i.rob_tag.idx] <= writeback1_i.exception;
                    done_q[writeback1_i.rob_tag.idx] <= 1'b1;
                    result_valid_q[writeback1_i.rob_tag.idx] <= 1'b0;
                end
            end

            if (commit_count_c != 2'd0) begin
                valid_q[head_q] <= 1'b0;
                done_q[head_q] <= 1'b0;
                result_valid_q[head_q] <= 1'b0;
                is_load_q[head_q] <= 1'b0;
                is_store_q[head_q] <= 1'b0;
                is_ebreak_q[head_q] <= 1'b0;
                is_csr_q[head_q] <= 1'b0;
                is_system_q[head_q] <= 1'b0;
                csr_addr_q[head_q] <= 12'b0;
                csr_write_q[head_q] <= 1'b0;
                csr_wdata_q[head_q] <= 32'b0;
                mem_op_q[head_q] <= BBUS_OOO_MEM_NONE;
                mem_addr_q[head_q] <= 32'b0;
                mem_wdata_q[head_q] <= 32'b0;
                mem_wstrb_q[head_q] <= 4'b0;
                mem_len_q[head_q] <= 3'b0;
                is_control_q[head_q] <= 1'b0;
                is_branch_q[head_q] <= 1'b0;
                is_jal_q[head_q] <= 1'b0;
                is_jalr_q[head_q] <= 1'b0;
                actual_taken_q[head_q] <= 1'b0;
                commit_nextpc_q[head_q] <= 32'b0;
                redirect_valid_q[head_q] <= 1'b0;
                selective_recovered_q[head_q] <= 1'b0;
                exception_q[head_q] <= '0;
                if (commit_count_c == 2'd2) begin
                    valid_q[head1] <= 1'b0;
                    done_q[head1] <= 1'b0;
                    result_valid_q[head1] <= 1'b0;
                    is_load_q[head1] <= 1'b0;
                    is_store_q[head1] <= 1'b0;
                    is_ebreak_q[head1] <= 1'b0;
                    is_csr_q[head1] <= 1'b0;
                    is_system_q[head1] <= 1'b0;
                    csr_addr_q[head1] <= 12'b0;
                    csr_write_q[head1] <= 1'b0;
                    csr_wdata_q[head1] <= 32'b0;
                    mem_op_q[head1] <= BBUS_OOO_MEM_NONE;
                    mem_addr_q[head1] <= 32'b0;
                    mem_wdata_q[head1] <= 32'b0;
                    mem_wstrb_q[head1] <= 4'b0;
                    mem_len_q[head1] <= 3'b0;
                    is_control_q[head1] <= 1'b0;
                    is_branch_q[head1] <= 1'b0;
                    is_jal_q[head1] <= 1'b0;
                    is_jalr_q[head1] <= 1'b0;
                    actual_taken_q[head1] <= 1'b0;
                    commit_nextpc_q[head1] <= 32'b0;
                    redirect_valid_q[head1] <= 1'b0;
                    selective_recovered_q[head1] <= 1'b0;
                    exception_q[head1] <= '0;
                end
                head_q <= bump(head_q, commit_count_c);
            end

            if (alloc_fire_mask_o[0]) begin
                valid_q[alloc_idx0] <= 1'b1;
                done_q[alloc_idx0] <= EARLY_TERMINAL_DONE_ENABLE &&
                    (alloc_slot0_i.exception.valid || alloc_slot0_i.is_ebreak);
                gen_q[alloc_idx0] <= alloc_tag0_o.gen;
                pc_q[alloc_idx0] <= alloc_slot0_i.pc;
                instr_q[alloc_idx0] <= alloc_slot0_i.instr;
                arch_rd_q[alloc_idx0] <= alloc_slot0_i.arch_rd;
                phys_new_q[alloc_idx0] <= alloc_slot0_i.phys_rd_new;
                phys_old_q[alloc_idx0] <= alloc_slot0_i.phys_rd_old;
                rf_wen_q[alloc_idx0] <= alloc_slot0_i.rf_wen;
                fu_type_q[alloc_idx0] <= alloc_slot0_i.fu_type;
                branch_op_q[alloc_idx0] <= alloc_slot0_i.branch_op;
                is_load_q[alloc_idx0] <= alloc_slot0_i.is_load;
                is_store_q[alloc_idx0] <= alloc_slot0_i.is_store;
                is_ebreak_q[alloc_idx0] <= alloc_slot0_i.is_ebreak;
                is_csr_q[alloc_idx0] <= alloc_slot0_i.is_csr;
                is_system_q[alloc_idx0] <= alloc_slot0_i.is_system;
                csr_addr_q[alloc_idx0] <= alloc_slot0_i.csr_addr;
                csr_write_q[alloc_idx0] <= 1'b0;
                csr_wdata_q[alloc_idx0] <= 32'b0;
                mem_op_q[alloc_idx0] <= alloc_slot0_i.mem_op;
                mem_addr_q[alloc_idx0] <= 32'b0;
                mem_wdata_q[alloc_idx0] <= 32'b0;
                mem_wstrb_q[alloc_idx0] <= 4'b0;
                mem_len_q[alloc_idx0] <= 3'b0;
                result_q[alloc_idx0] <= 32'b0;
                result_valid_q[alloc_idx0] <= 1'b0;
                is_control_q[alloc_idx0] <=
                    (alloc_slot0_i.fu_type == BBUS_OOO_FU_BRU) ||
                    (alloc_slot0_i.fu_type == BBUS_OOO_FU_SYS);
                is_branch_q[alloc_idx0] <=
                    (alloc_slot0_i.fu_type == BBUS_OOO_FU_BRU) &&
                    (alloc_slot0_i.branch_op != BBUS_OOO_BR_JAL) &&
                    (alloc_slot0_i.branch_op != BBUS_OOO_BR_JALR);
                is_jal_q[alloc_idx0] <=
                    (alloc_slot0_i.fu_type == BBUS_OOO_FU_BRU) &&
                    (alloc_slot0_i.branch_op == BBUS_OOO_BR_JAL);
                is_jalr_q[alloc_idx0] <=
                    (alloc_slot0_i.fu_type == BBUS_OOO_FU_BRU) &&
                    (alloc_slot0_i.branch_op == BBUS_OOO_BR_JALR);
                actual_taken_q[alloc_idx0] <= 1'b0;
                commit_nextpc_q[alloc_idx0] <= alloc_slot0_i.pc + 32'd4;
                redirect_valid_q[alloc_idx0] <= 1'b0;
                selective_recovered_q[alloc_idx0] <= 1'b0;
                exception_q[alloc_idx0] <= alloc_slot0_i.exception;
            end

            if (alloc_fire_mask_o[1]) begin
                valid_q[alloc_idx1] <= 1'b1;
                done_q[alloc_idx1] <= EARLY_TERMINAL_DONE_ENABLE &&
                    (alloc_slot1_i.exception.valid || alloc_slot1_i.is_ebreak);
                gen_q[alloc_idx1] <= alloc_tag1_o.gen;
                pc_q[alloc_idx1] <= alloc_slot1_i.pc;
                instr_q[alloc_idx1] <= alloc_slot1_i.instr;
                arch_rd_q[alloc_idx1] <= alloc_slot1_i.arch_rd;
                phys_new_q[alloc_idx1] <= alloc_slot1_i.phys_rd_new;
                phys_old_q[alloc_idx1] <= alloc_slot1_i.phys_rd_old;
                rf_wen_q[alloc_idx1] <= alloc_slot1_i.rf_wen;
                fu_type_q[alloc_idx1] <= alloc_slot1_i.fu_type;
                branch_op_q[alloc_idx1] <= alloc_slot1_i.branch_op;
                is_load_q[alloc_idx1] <= alloc_slot1_i.is_load;
                is_store_q[alloc_idx1] <= alloc_slot1_i.is_store;
                is_ebreak_q[alloc_idx1] <= alloc_slot1_i.is_ebreak;
                is_csr_q[alloc_idx1] <= alloc_slot1_i.is_csr;
                is_system_q[alloc_idx1] <= alloc_slot1_i.is_system;
                csr_addr_q[alloc_idx1] <= alloc_slot1_i.csr_addr;
                csr_write_q[alloc_idx1] <= 1'b0;
                csr_wdata_q[alloc_idx1] <= 32'b0;
                mem_op_q[alloc_idx1] <= alloc_slot1_i.mem_op;
                mem_addr_q[alloc_idx1] <= 32'b0;
                mem_wdata_q[alloc_idx1] <= 32'b0;
                mem_wstrb_q[alloc_idx1] <= 4'b0;
                mem_len_q[alloc_idx1] <= 3'b0;
                result_q[alloc_idx1] <= 32'b0;
                result_valid_q[alloc_idx1] <= 1'b0;
                is_control_q[alloc_idx1] <=
                    (alloc_slot1_i.fu_type == BBUS_OOO_FU_BRU) ||
                    (alloc_slot1_i.fu_type == BBUS_OOO_FU_SYS);
                is_branch_q[alloc_idx1] <=
                    (alloc_slot1_i.fu_type == BBUS_OOO_FU_BRU) &&
                    (alloc_slot1_i.branch_op != BBUS_OOO_BR_JAL) &&
                    (alloc_slot1_i.branch_op != BBUS_OOO_BR_JALR);
                is_jal_q[alloc_idx1] <=
                    (alloc_slot1_i.fu_type == BBUS_OOO_FU_BRU) &&
                    (alloc_slot1_i.branch_op == BBUS_OOO_BR_JAL);
                is_jalr_q[alloc_idx1] <=
                    (alloc_slot1_i.fu_type == BBUS_OOO_FU_BRU) &&
                    (alloc_slot1_i.branch_op == BBUS_OOO_BR_JALR);
                actual_taken_q[alloc_idx1] <= 1'b0;
                commit_nextpc_q[alloc_idx1] <= alloc_slot1_i.pc + 32'd4;
                redirect_valid_q[alloc_idx1] <= 1'b0;
                selective_recovered_q[alloc_idx1] <= 1'b0;
                exception_q[alloc_idx1] <= alloc_slot1_i.exception;
            end

            if (alloc_count != 2'd0) begin
                tail_q <= bump(tail_q, alloc_count);
            end
            count_q <= count_q - {2'b0, commit_count_c} + {2'b0, alloc_count};
        end
    end
endmodule
