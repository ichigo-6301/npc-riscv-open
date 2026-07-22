`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module alu_issue_queue_1w #(
    parameter int IQ_DEPTH = 8,
    parameter bit SAME_CYCLE_WAKEUP_ENABLE = 1'b0,
    parameter bit SAME_CYCLE_DISPATCH_ISSUE_ENABLE = 1'b0,
    parameter bit SAME_CYCLE_BRANCH_DISPATCH_ISSUE_ENABLE = 1'b0,
    parameter bit BRANCH_ORDINARY_CONCURRENT_ISSUE_ENABLE = 1'b0,
    parameter bit BRANCH_YOUNGER_ORDINARY_CONCURRENT_ISSUE_ENABLE = 1'b0,
    parameter bit REGISTERED_BRU_DISPATCH_ORDINARY_ISSUE2_ENABLE = 1'b0,
    parameter bit PRECISE_STORE_BUFFER_ENABLE = 1'b0,
    parameter bit STRUCTURAL_THROUGHPUT_ORACLE_ENABLE = 1'b0,
    localparam int IQ_IDX_W = $clog2(IQ_DEPTH),
    localparam int IQ_COUNT_W = $clog2(IQ_DEPTH + 1)
) (
    input  logic clk,
    input  logic reset,
    input  logic flush_i,
    input  logic selective_kill_valid_i,
    input  logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_i,
    output logic [3:0] selective_killed_count_o,
    input  bbus_ooo_rob_idx_t rob_head_i,
    input  bbus_ooo_rob_tag_t rob_head_tag_i,
    input  logic alu0_available_i,
    input  logic alu1_available_i,
    input  logic lsu_available_i,
    input  logic bru_available_i,
    input  logic csr_sys_available_i,
    input  logic atomic_available_i,

    input  logic dispatch_valid_i,
    input  bbus_ooo_alu_iq_uop_t dispatch_uop_i,
    input  logic dispatch1_valid_i,
    input  bbus_ooo_alu_iq_uop_t dispatch1_uop_i,
    input  logic [1:0] oracle_offer_valid_mask_i,
    input  bbus_ooo_alu_iq_uop_t oracle_offer_uop0_i,
    input  bbus_ooo_alu_iq_uop_t oracle_offer_uop1_i,
    input  logic [1:0] oracle_stage_ready_mask_i,
    input  logic oracle_serial_ready_i,
    output logic dispatch_ready_o,
    output logic dispatch1_ready_o,
    output logic [1:0] dispatch_ready_count_o,
    output logic [1:0] dispatch_fire_mask_o,

    input  logic wakeup_valid_i,
    input  bbus_ooo_phys_reg_t wakeup_phys_i,
    input  logic wakeup1_valid_i,
    input  bbus_ooo_phys_reg_t wakeup1_phys_i,

    output logic issue_valid_o,
    output bbus_ooo_alu_iq_uop_t issue_uop_o,
    input  logic issue_ready_i,
    output logic issue1_valid_o,
    output bbus_ooo_alu_iq_uop_t issue1_uop_o,
    input  logic issue1_ready_i,
    output logic issue2_pair_valid_o,
    output logic issue2_pair_is_alu_lsu_o,
    output logic issue2_pair_is_alu_alu_o,
    output logic issue2_pair_legal_o,
    output logic [1:0] issue_same_cycle_wakeup_mask_o,

    output logic [IQ_COUNT_W-1:0] debug_count_o,
    output logic [IQ_COUNT_W-1:0] debug_ready_count_o,
    output logic [IQ_COUNT_W-1:0] debug_ready_alu_count_o,
    output logic [IQ_COUNT_W-1:0] debug_ready_lsu_count_o,
    output logic [IQ_COUNT_W-1:0] debug_ready_bru_count_o,
    output logic [IQ_COUNT_W-1:0] debug_ready_csr_sys_count_o,
    output logic [IQ_COUNT_W-1:0] debug_ready_any_count_o,
    output logic [IQ_COUNT_W-1:0] debug_issue_candidate_count_o,
    output logic [41:0] debug_bru_operand_o,
    output logic [63:0] debug_dependency_operand_o,
    output logic [6:0] debug_retirement_head_o,
    output logic [1:0] debug_bru_no_older_ready_o,
    output logic [5:0] debug_bru_pred_source_o,
    output logic [1:0] debug_bru_pred_correlated_o,
    output logic debug_issue_multi_candidate_o,
    output logic debug_issue0_fire_o,
    output logic debug_issue1_fire_o,
    output logic debug_issue2_fire_o,
    output logic [1:0] debug_issue_from_dispatch_mask_o,
    output logic debug_mixed_source_valid_o,
    output logic [2:0] debug_mixed_source_reason_o,
    output logic [1:0] debug_mixed_source_pair_kind_o,
    output logic [63:0] debug_structural_oracle_o,
    output logic [47:0] debug_structural_meta_o,
    output logic debug_duplicate_issue_guard_o
);
    // S6B3: issue age priority uses ROB-head-relative compare at IQ_DEPTH=8.
    // S6_SIMPLIFICATION: IQ remains compacting and selector remains a 2-wide scan.
    // FUTURE: consider stable entries, age matrix, or staged select before larger depths.
    localparam logic [`BBUS_OOO_ROB_IDX_W:0] ROB_ENTRIES_EXT = `BBUS_OOO_ROB_ENTRIES;

    bbus_ooo_alu_iq_uop_t entry_q [IQ_DEPTH-1:0];
    logic [IQ_COUNT_W-1:0] count_q;
    logic [IQ_IDX_W-1:0] issue_idx_c;
    logic [IQ_IDX_W-1:0] issue1_idx_c;
    logic issue_found_c;
    logic issue1_found_c;
    logic issue_fire_c;
    logic issue1_fire_c;
    logic [IQ_COUNT_W-1:0] free_count_c;
    logic dispatch0_fire_c;
    logic dispatch1_fire_c;
    logic grant_hold_q;
    logic grant1_hold_q;
    logic [IQ_IDX_W-1:0] grant_idx_q;
    logic [IQ_IDX_W-1:0] grant1_idx_q;
    bbus_ooo_alu_iq_uop_t grant_uop_q;
    bbus_ooo_alu_iq_uop_t grant1_uop_q;
    bbus_ooo_alu_iq_uop_t issue_uop_select_c;
    bbus_ooo_alu_iq_uop_t issue1_uop_select_c;
    logic [IQ_IDX_W-1:0] issue_idx_selected_c;
    logic [IQ_IDX_W-1:0] issue1_idx_selected_c;
    logic issue_from_dispatch0_c;
    logic issue1_from_dispatch0_c;
    logic issue1_from_dispatch1_c;
    logic registered_issue_found_c;
    logic registered_issue1_found_c;
    bbus_ooo_alu_iq_uop_t registered_issue_uop_c;

    localparam int STRUCT_MODEL_COUNT = 7;
    localparam int STRUCT_PHASE_COUNT = 3;
    localparam int STRUCT_CANDIDATE_COUNT = IQ_DEPTH + 4;
    localparam int STRUCT_MODEL_ACTUAL = 0;
    localparam int STRUCT_MODEL_CURRENT_MAX = 1;
    localparam int STRUCT_MODEL_ACCEPTED = 2;
    localparam int STRUCT_MODEL_OFFERED = 3;
    localparam int STRUCT_MODEL_BRANCH = 4;
    localparam int STRUCT_MODEL_STORE = 5;
    localparam int STRUCT_MODEL_IDEAL_READY = 6;
    localparam int STRUCT_PHASE_SELECT = 0;
    localparam int STRUCT_PHASE_PORT = 1;
    localparam int STRUCT_PHASE_DOWNSTREAM = 2;

    localparam logic [2:0] STRUCT_SOURCE_REGISTERED = 3'd0;
    localparam logic [2:0] STRUCT_SOURCE_DISPATCH0 = 3'd1;
    localparam logic [2:0] STRUCT_SOURCE_DISPATCH1 = 3'd2;
    localparam logic [2:0] STRUCT_SOURCE_OFFER0 = 3'd3;
    localparam logic [2:0] STRUCT_SOURCE_OFFER1 = 3'd4;

    localparam logic [3:0] STRUCT_REASON_PROGRESS = 4'd0;
    localparam logic [3:0] STRUCT_REASON_RECOVERY = 4'd1;
    localparam logic [3:0] STRUCT_REASON_DOWNSTREAM = 4'd2;
    localparam logic [3:0] STRUCT_REASON_SUPPLY = 4'd3;
    localparam logic [3:0] STRUCT_REASON_OPERAND = 4'd4;
    localparam logic [3:0] STRUCT_REASON_ADMISSION = 4'd5;
    localparam logic [3:0] STRUCT_REASON_SOURCE = 4'd6;
    localparam logic [3:0] STRUCT_REASON_GREEDY = 4'd7;
    localparam logic [3:0] STRUCT_REASON_TOPOLOGY = 4'd8;
    localparam logic [3:0] STRUCT_REASON_BRANCH = 4'd9;
    localparam logic [3:0] STRUCT_REASON_STORE = 4'd10;
    localparam logic [3:0] STRUCT_REASON_PORT = 4'd11;
    localparam logic [3:0] STRUCT_REASON_OTHER = 4'd12;

    bbus_ooo_alu_iq_uop_t struct_candidate_uop_c [STRUCT_CANDIDATE_COUNT-1:0];
    logic struct_candidate_valid_c [STRUCT_CANDIDATE_COUNT-1:0];
    logic struct_candidate_ready_c [STRUCT_CANDIDATE_COUNT-1:0];
    logic struct_candidate_ideal_ready_c [STRUCT_CANDIDATE_COUNT-1:0];
    logic [2:0] struct_candidate_source_c [STRUCT_CANDIDATE_COUNT-1:0];
    logic struct_model_include_c [STRUCT_MODEL_COUNT-1:0]
        [STRUCT_CANDIDATE_COUNT-1:0];
    logic [1:0] struct_width_c [STRUCT_MODEL_COUNT-1:0]
        [STRUCT_PHASE_COUNT-1:0];
    integer struct_best_select_i_c [STRUCT_MODEL_COUNT-1:0];
    integer struct_best_select_j_c [STRUCT_MODEL_COUNT-1:0];
    integer struct_best_port_i_c [STRUCT_MODEL_COUNT-1:0];
    integer struct_best_port_j_c [STRUCT_MODEL_COUNT-1:0];
    integer struct_best_down_i_c [STRUCT_MODEL_COUNT-1:0];
    integer struct_best_down_j_c [STRUCT_MODEL_COUNT-1:0];
    integer struct_best_select_key_c [STRUCT_MODEL_COUNT-1:0];
    integer struct_best_port_key_c [STRUCT_MODEL_COUNT-1:0];
    integer struct_best_down_key_c [STRUCT_MODEL_COUNT-1:0];
    logic [3:0] struct_reason_c;
    logic [11:0] struct_overlap_c;
    logic struct_state_error_c;
    integer struct_selected_model_c;
    integer struct_selected_i_c;
    integer struct_selected_j_c;
    logic [2:0] struct_selected_source0_c, struct_selected_source1_c;
    logic [2:0] struct_selected_fu0_c, struct_selected_fu1_c;
    logic [4:0] struct_selected_tag0_c, struct_selected_tag1_c;
    logic [1:0] struct_selected_tag_valid_c;
    logic [1:0] struct_branch_relation_c;
    logic [3:0] struct_pair_kind_c;

    localparam logic [2:0] MIXED_REASON_REGISTERED_PAIR = 3'd0;
    localparam logic [2:0] MIXED_REASON_NO_DISPATCH = 3'd1;
    localparam logic [2:0] MIXED_REASON_INCOMING_NOT_READY = 3'd2;
    localparam logic [2:0] MIXED_REASON_ILLEGAL_PAIR = 3'd3;
    localparam logic [2:0] MIXED_REASON_PORT_UNAVAILABLE = 3'd4;
    localparam logic [2:0] MIXED_REASON_SERIAL_RECOVERY = 3'd5;
    localparam logic [2:0] MIXED_REASON_ELIGIBLE = 3'd7;

    function automatic logic wakeup_match(input bbus_ooo_phys_reg_t phys);
        begin
            wakeup_match = SAME_CYCLE_WAKEUP_ENABLE &&
                (phys != `BBUS_OOO_PHYS_ZERO) &&
                ((wakeup_valid_i && (wakeup_phys_i == phys)) ||
                 (wakeup1_valid_i && (wakeup1_phys_i == phys)));
        end
    endfunction

    function automatic logic operand_ready(
        input logic registered_ready,
        input bbus_ooo_phys_reg_t phys
    );
        operand_ready = registered_ready || wakeup_match(phys);
    endfunction

    function automatic logic entry_ready(input bbus_ooo_alu_iq_uop_t entry);
        begin
            entry_ready = entry.valid &&
                operand_ready(entry.src1_ready, entry.phys_rs1) &&
                operand_ready(entry.src2_ready, entry.phys_rs2) &&
                !(selective_kill_valid_i && entry.rob_tag.valid &&
                  selective_killed_rob_mask_i[entry.rob_tag.idx]);
        end
    endfunction

    function automatic logic entry_src1_waiting(
        input bbus_ooo_alu_iq_uop_t entry
    );
        entry_src1_waiting = !operand_ready(
            entry.src1_ready, entry.phys_rs1);
    endfunction

    function automatic logic entry_src2_waiting(
        input bbus_ooo_alu_iq_uop_t entry
    );
        entry_src2_waiting = !operand_ready(
            entry.src2_ready, entry.phys_rs2);
    endfunction

    function automatic logic entry_dependency_waiting(
        input bbus_ooo_alu_iq_uop_t entry
    );
        entry_dependency_waiting = entry.valid &&
            (entry_src1_waiting(entry) || entry_src2_waiting(entry));
    endfunction

    function automatic logic entry_uses_same_cycle_wakeup(
        input bbus_ooo_alu_iq_uop_t entry
    );
        entry_uses_same_cycle_wakeup = SAME_CYCLE_WAKEUP_ENABLE &&
            ((!entry.src1_ready && wakeup_match(entry.phys_rs1)) ||
             (!entry.src2_ready && wakeup_match(entry.phys_rs2)));
    endfunction

    function automatic logic struct_is_bru(input bbus_ooo_alu_iq_uop_t entry);
        struct_is_bru = entry.valid &&
            (entry.fu_type == BBUS_OOO_FU_BRU) && !entry.exception.valid;
    endfunction

    function automatic logic struct_is_store(input bbus_ooo_alu_iq_uop_t entry);
        struct_is_store = entry.valid && entry.is_store &&
            (entry.fu_type == BBUS_OOO_FU_LSU) && !entry.exception.valid;
    endfunction

    function automatic logic struct_is_mdu(input bbus_ooo_alu_iq_uop_t entry);
        struct_is_mdu = entry.valid &&
            (entry.fu_type == BBUS_OOO_FU_MDU) && !entry.exception.valid;
    endfunction

    function automatic logic struct_is_ordinary(
        input bbus_ooo_alu_iq_uop_t entry
    );
        struct_is_ordinary = is_alu_like(entry) || is_lsu_load(entry);
    endfunction

    function automatic logic struct_current_dispatch_allowed(
        input bbus_ooo_alu_iq_uop_t entry
    );
        struct_current_dispatch_allowed =
            (SAME_CYCLE_DISPATCH_ISSUE_ENABLE &&
             struct_is_ordinary(entry)) ||
            (SAME_CYCLE_BRANCH_DISPATCH_ISSUE_ENABLE &&
             struct_is_bru(entry));
    endfunction

    function automatic logic [2:0] struct_fu_class(
        input bbus_ooo_alu_iq_uop_t entry
    );
        begin
            if (is_alu_like(entry)) struct_fu_class = 3'd1;
            else if (is_lsu_load(entry)) struct_fu_class = 3'd2;
            else if (struct_is_bru(entry)) struct_fu_class = 3'd3;
            else if (struct_is_store(entry)) struct_fu_class = 3'd4;
            else if (struct_is_mdu(entry)) struct_fu_class = 3'd5;
            else if (entry.valid &&
                     ((entry.fu_type == BBUS_OOO_FU_AMO)))
                struct_fu_class = 3'd7;
            else if (entry.valid) struct_fu_class = 3'd6;
            else struct_fu_class = 3'd0;
        end
    endfunction

    function automatic logic struct_current_branch_pair_type(
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        struct_current_branch_pair_type =
            (BRANCH_ORDINARY_CONCURRENT_ISSUE_ENABLE &&
             struct_is_ordinary(a) && struct_is_bru(b)) ||
            (BRANCH_YOUNGER_ORDINARY_CONCURRENT_ISSUE_ENABLE &&
             struct_is_bru(a) && struct_is_ordinary(b));
    endfunction

    function automatic logic struct_current_pair_type(
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        struct_current_pair_type =
            (is_alu_like(a) && is_alu_like(b)) ||
            (is_alu_like(a) && is_lsu_load(b)) ||
            (is_lsu_load(a) && is_alu_like(b)) ||
            struct_current_branch_pair_type(a, b);
    endfunction

    function automatic logic struct_branch_pair_type(
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        struct_branch_pair_type =
            (struct_is_bru(a) && struct_is_ordinary(b)) ||
            (struct_is_ordinary(a) && struct_is_bru(b));
    endfunction

    function automatic logic struct_store_pair_type(
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        struct_store_pair_type = PRECISE_STORE_BUFFER_ENABLE &&
            ((struct_is_store(a) && struct_is_ordinary(b)) ||
             (struct_is_ordinary(a) && struct_is_store(b)));
    endfunction

    function automatic logic struct_pair_type_for_model(
        input integer model,
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        begin
            struct_pair_type_for_model = struct_current_pair_type(a, b);
            if (model >= STRUCT_MODEL_BRANCH)
                struct_pair_type_for_model = struct_pair_type_for_model ||
                    struct_branch_pair_type(a, b);
            if (model >= STRUCT_MODEL_STORE)
                struct_pair_type_for_model = struct_pair_type_for_model ||
                    struct_store_pair_type(a, b);
        end
    endfunction

    function automatic logic struct_single_port_available(
        input bbus_ooo_alu_iq_uop_t entry
    );
        begin
            if (is_alu_like(entry))
                struct_single_port_available = alu0_available_i || alu1_available_i;
            else if (is_lsu_load(entry))
                struct_single_port_available = lsu_available_i;
            else if (struct_is_bru(entry))
                struct_single_port_available = bru_available_i;
            else if (struct_is_store(entry) || struct_is_mdu(entry))
                struct_single_port_available = csr_sys_available_i;
            else
                struct_single_port_available = entry_fu_available(entry);
        end
    endfunction

    function automatic logic struct_pair_ports_available(
        input integer model,
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        begin
            struct_pair_ports_available = 1'b0;
            if (struct_current_pair_type(a, b)) begin
                struct_pair_ports_available =
                    ((is_alu_like(a) && is_alu_like(b)) &&
                     alu0_available_i && alu1_available_i) ||
                    (((is_alu_like(a) && is_lsu_load(b)) ||
                      (is_lsu_load(a) && is_alu_like(b))) &&
                     (alu0_available_i || alu1_available_i) &&
                     lsu_available_i) ||
                    (struct_current_branch_pair_type(a, b) &&
                     bru_available_i &&
                     ((is_alu_like(a) || is_alu_like(b)) ?
                        (alu0_available_i || alu1_available_i) :
                        lsu_available_i));
            end else if ((model >= STRUCT_MODEL_BRANCH) &&
                         struct_branch_pair_type(a, b)) begin
                struct_pair_ports_available = bru_available_i &&
                    ((is_alu_like(a) || is_alu_like(b)) ?
                        (alu0_available_i || alu1_available_i) :
                        lsu_available_i);
            end else if ((model >= STRUCT_MODEL_STORE) &&
                         struct_store_pair_type(a, b)) begin
                struct_pair_ports_available = csr_sys_available_i &&
                    ((is_alu_like(a) || is_alu_like(b)) ?
                        (alu0_available_i || alu1_available_i) :
                        lsu_available_i);
            end
        end
    endfunction

    function automatic logic struct_single_downstream_available(
        input bbus_ooo_alu_iq_uop_t entry
    );
        begin
            if (struct_is_bru(entry) || struct_is_store(entry) ||
                struct_is_mdu(entry))
                struct_single_downstream_available = oracle_serial_ready_i;
            else
                struct_single_downstream_available = oracle_stage_ready_mask_i[0];
        end
    endfunction

    function automatic logic struct_pair_downstream_available(
        input integer model,
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        begin
            if (struct_current_branch_pair_type(a, b))
                struct_pair_downstream_available = oracle_serial_ready_i &&
                    oracle_stage_ready_mask_i[0];
            else if (struct_current_pair_type(a, b))
                struct_pair_downstream_available = &oracle_stage_ready_mask_i;
            else if (((model >= STRUCT_MODEL_BRANCH) &&
                      struct_branch_pair_type(a, b)) ||
                     ((model >= STRUCT_MODEL_STORE) &&
                      struct_store_pair_type(a, b)))
                struct_pair_downstream_available = oracle_serial_ready_i &&
                    oracle_stage_ready_mask_i[0];
            else
                struct_pair_downstream_available = 1'b0;
        end
    endfunction

    function automatic integer struct_age(
        input bbus_ooo_alu_iq_uop_t entry,
        input logic [2:0] source
    );
        begin
            if (entry.rob_tag.valid)
                struct_age = rob_age_distance(entry.rob_tag.idx, rob_head_i);
            else if (source == STRUCT_SOURCE_OFFER0)
                struct_age = `BBUS_OOO_ROB_ENTRIES;
            else
                struct_age = `BBUS_OOO_ROB_ENTRIES + 1;
        end
    endfunction

    function automatic logic tag_killed(input bbus_ooo_rob_tag_t tag);
        tag_killed = selective_kill_valid_i && tag.valid &&
            selective_killed_rob_mask_i[tag.idx];
    endfunction

    function automatic logic [`BBUS_OOO_ROB_IDX_W:0] rob_age_distance(
        input bbus_ooo_rob_idx_t idx,
        input bbus_ooo_rob_idx_t head
    );
        begin
            if (idx >= head) begin
                rob_age_distance = {1'b0, idx - head};
            end else begin
                rob_age_distance =
                    ROB_ENTRIES_EXT + {1'b0, idx} - {1'b0, head};
            end
        end
    endfunction

    function automatic logic entry_older_than(
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        begin
            entry_older_than =
                rob_age_distance(a.rob_tag.idx, rob_head_i) <
                rob_age_distance(b.rob_tag.idx, rob_head_i);
        end
    endfunction

    function automatic logic [23:0] dependency_debug_record(
        input bbus_ooo_alu_iq_uop_t entry
    );
        logic src1_waiting;
        logic src2_waiting;
        begin
            src1_waiting = entry_src1_waiting(entry);
            src2_waiting = entry_src2_waiting(entry);
            dependency_debug_record = '0;
            dependency_debug_record[0] = entry.valid;
            dependency_debug_record[3:1] = entry.rob_tag.idx;
            dependency_debug_record[5:4] = entry.rob_tag.gen;
            dependency_debug_record[9:6] = entry.fu_type;
            dependency_debug_record[10] = src1_waiting;
            dependency_debug_record[11] = src2_waiting;
            dependency_debug_record[17:12] = entry.phys_rs1;
            dependency_debug_record[23:18] = entry.phys_rs2;
        end
    endfunction

    function automatic logic is_alu_like(input bbus_ooo_alu_iq_uop_t entry);
        begin
            is_alu_like =
                entry.valid &&
                !entry.is_load &&
                !entry.is_store &&
                !entry.is_csr &&
                !entry.is_system &&
                ((entry.fu_type == BBUS_OOO_FU_ALU) ||
                 (entry.fu_type == BBUS_OOO_FU_NONE));
        end
    endfunction

    function automatic logic is_lsu_load(input bbus_ooo_alu_iq_uop_t entry);
        begin
            is_lsu_load =
                entry.valid &&
                (entry.fu_type == BBUS_OOO_FU_LSU) &&
                entry.is_load &&
                !entry.is_store;
        end
    endfunction

    function automatic logic amo_v1_supported(input bbus_ooo_atomic_op_e op);
        begin
            amo_v1_supported =
                (op == BBUS_OOO_AMO_LR) ||
                (op == BBUS_OOO_AMO_SC) ||
                (op == BBUS_OOO_AMO_SWAP) ||
                (op == BBUS_OOO_AMO_ADD) ||
                (op == BBUS_OOO_AMO_XOR) ||
                (op == BBUS_OOO_AMO_AND) ||
                (op == BBUS_OOO_AMO_OR) ||
                (op == BBUS_OOO_AMO_MIN) ||
                (op == BBUS_OOO_AMO_MAX) ||
                (op == BBUS_OOO_AMO_MINU) ||
                (op == BBUS_OOO_AMO_MAXU);
        end
    endfunction

    function automatic logic entry_fu_available(input bbus_ooo_alu_iq_uop_t entry);
        begin
            unique case (entry.fu_type)
                BBUS_OOO_FU_ALU,
                BBUS_OOO_FU_NONE: entry_fu_available = alu0_available_i || alu1_available_i;
                BBUS_OOO_FU_LSU: entry_fu_available = lsu_available_i;
                BBUS_OOO_FU_BRU: entry_fu_available = bru_available_i;
                BBUS_OOO_FU_CSR,
                BBUS_OOO_FU_SYS,
                BBUS_OOO_FU_MDU: entry_fu_available = csr_sys_available_i;
                BBUS_OOO_FU_AMO: entry_fu_available =
                    atomic_available_i &&
                    amo_v1_supported(entry.atomic_op) &&
                    entry.rob_tag.valid && rob_head_tag_i.valid &&
                    (entry.rob_tag == rob_head_tag_i);
                default: entry_fu_available = 1'b0;
            endcase
        end
    endfunction

    function automatic logic older_ready_entry_exists(
        input bbus_ooo_alu_iq_uop_t entry
    );
        begin
            older_ready_entry_exists = 1'b0;
            for (int j = 0; j < IQ_DEPTH; j = j + 1) begin
                if (entry_ready(entry_q[j]) &&
                    entry_fu_available(entry_q[j]) &&
                    entry_older_than(entry_q[j], entry))
                    older_ready_entry_exists = 1'b1;
            end
        end
    endfunction

    function automatic logic pair_ports_available(
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        begin
            pair_ports_available =
                (legal_alu_alu_pair(a, b) && alu0_available_i && alu1_available_i) ||
                (legal_alu_lsu_pair(a, b) && alu0_available_i && lsu_available_i) ||
                (legal_branch_ordinary_pair(a, b) && bru_available_i &&
                 (((is_alu_like(a) || is_alu_like(b)) &&
                   (alu0_available_i || alu1_available_i)) ||
                  ((is_lsu_load(a) || is_lsu_load(b)) && lsu_available_i)));
        end
    endfunction

    function automatic logic legal_alu_lsu_pair(
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        begin
            legal_alu_lsu_pair =
                entry_ready(a) &&
                entry_ready(b) &&
                ((is_alu_like(a) && is_lsu_load(b)) ||
                 (is_lsu_load(a) && is_alu_like(b)));
        end
    endfunction

    function automatic logic legal_alu_alu_pair(
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        begin
            legal_alu_alu_pair =
                entry_ready(a) &&
                entry_ready(b) &&
                is_alu_like(a) &&
                is_alu_like(b);
        end
    endfunction

    function automatic logic legal_branch_ordinary_pair(
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        begin
            legal_branch_ordinary_pair =
                entry_ready(a) && entry_ready(b) &&
                ((BRANCH_ORDINARY_CONCURRENT_ISSUE_ENABLE &&
                  struct_is_ordinary(a) && struct_is_bru(b)) ||
                 (BRANCH_YOUNGER_ORDINARY_CONCURRENT_ISSUE_ENABLE &&
                  struct_is_bru(a) && struct_is_ordinary(b)));
        end
    endfunction

    function automatic logic legal_issue2_pair(
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        begin
            legal_issue2_pair =
                legal_alu_lsu_pair(a, b) ||
                legal_alu_alu_pair(a, b) ||
                legal_branch_ordinary_pair(a, b);
        end
    endfunction

    always_comb begin
        integer i;
        integer debug_bru_count;
        integer debug_dependency_count;
        logic debug_src1_wait;
        logic debug_src2_wait;
        logic debug_dependency_found0;
        logic debug_dependency_found1;
        logic debug_dependency_invalid;
        logic debug_head_found;
        logic debug_head_src1_wait;
        logic debug_head_src2_wait;
        logic debug_head_ready;
        logic debug_head_invalid;
        bbus_ooo_alu_iq_uop_t debug_dependency_uop0;
        bbus_ooo_alu_iq_uop_t debug_dependency_uop1;

        issue_found_c = 1'b0;
        issue1_found_c = 1'b0;
        issue_idx_c = '0;
        issue1_idx_c = '0;
        issue_uop_select_c = '0;
        issue1_uop_select_c = '0;
        issue_from_dispatch0_c = 1'b0;
        issue1_from_dispatch0_c = 1'b0;
        issue1_from_dispatch1_c = 1'b0;
        registered_issue_found_c = 1'b0;
        registered_issue1_found_c = 1'b0;
        registered_issue_uop_c = '0;
        debug_ready_count_o = '0;
        debug_ready_alu_count_o = '0;
        debug_ready_lsu_count_o = '0;
        debug_ready_bru_count_o = '0;
        debug_ready_csr_sys_count_o = '0;
        debug_bru_operand_o = '0;
        debug_dependency_operand_o = '0;
        debug_retirement_head_o = '0;
        debug_bru_no_older_ready_o = '0;
        debug_bru_pred_source_o = '0;
        debug_bru_pred_correlated_o = '0;
        debug_bru_count = 0;
        debug_dependency_count = 0;
        debug_src1_wait = 1'b0;
        debug_src2_wait = 1'b0;
        debug_dependency_found0 = 1'b0;
        debug_dependency_found1 = 1'b0;
        debug_dependency_invalid = 1'b0;
        debug_head_found = 1'b0;
        debug_head_src1_wait = 1'b0;
        debug_head_src2_wait = 1'b0;
        debug_head_ready = 1'b0;
        debug_head_invalid = 1'b0;
        debug_dependency_uop0 = '0;
        debug_dependency_uop1 = '0;

        for (i = 0; i < IQ_DEPTH; i = i + 1) begin
            if (entry_q[i].valid && rob_head_tag_i.valid &&
                (entry_q[i].rob_tag == rob_head_tag_i)) begin
                if (debug_head_found)
                    debug_head_invalid = 1'b1;
                debug_head_found = 1'b1;
                debug_head_src1_wait = entry_src1_waiting(entry_q[i]);
                debug_head_src2_wait = entry_src2_waiting(entry_q[i]);
                debug_head_ready = entry_ready(entry_q[i]);
            end
            if (entry_dependency_waiting(entry_q[i])) begin
                debug_dependency_count = debug_dependency_count + 1;
                if (!entry_q[i].rob_tag.valid ||
                    (entry_src1_waiting(entry_q[i]) &&
                     (entry_q[i].phys_rs1 == `BBUS_OOO_PHYS_ZERO)) ||
                    (entry_src2_waiting(entry_q[i]) &&
                     (entry_q[i].phys_rs2 == `BBUS_OOO_PHYS_ZERO)) ||
                    (entry_q[i].fu_type > BBUS_OOO_FU_AMO))
                    debug_dependency_invalid = 1'b1;
                if (!debug_dependency_found0 ||
                    entry_older_than(entry_q[i], debug_dependency_uop0)) begin
                    if (debug_dependency_found0) begin
                        debug_dependency_uop1 = debug_dependency_uop0;
                        debug_dependency_found1 = 1'b1;
                    end
                    debug_dependency_uop0 = entry_q[i];
                    debug_dependency_found0 = 1'b1;
                end else if (!debug_dependency_found1 ||
                    entry_older_than(entry_q[i], debug_dependency_uop1)) begin
                    debug_dependency_uop1 = entry_q[i];
                    debug_dependency_found1 = 1'b1;
                end
            end
            if (entry_q[i].valid &&
                (entry_q[i].fu_type == BBUS_OOO_FU_BRU)) begin
                debug_src1_wait = !operand_ready(
                    entry_q[i].src1_ready, entry_q[i].phys_rs1);
                debug_src2_wait = !operand_ready(
                    entry_q[i].src2_ready, entry_q[i].phys_rs2);
                if (debug_bru_count < 2) begin
                    debug_bru_operand_o[debug_bru_count * 20 +: 20] = {
                        entry_q[i].phys_rs2,
                        debug_src2_wait,
                        entry_q[i].phys_rs1,
                        debug_src1_wait,
                        entry_q[i].rob_tag.gen,
                        entry_q[i].rob_tag.idx,
                        1'b1
                    };
                    debug_bru_no_older_ready_o[debug_bru_count] =
                        !grant_hold_q &&
                        !older_ready_entry_exists(entry_q[i]);
                    debug_bru_pred_source_o[
                        debug_bru_count * 3 +: 3] =
                        entry_q[i].pred_source;
                    debug_bru_pred_correlated_o[debug_bru_count] =
                        entry_q[i].pred_correlated;
                end else begin
                    debug_bru_operand_o[40] = 1'b1;
                end
                if ((debug_src1_wait &&
                     (entry_q[i].phys_rs1 == `BBUS_OOO_PHYS_ZERO)) ||
                    (debug_src2_wait &&
                     (entry_q[i].phys_rs2 == `BBUS_OOO_PHYS_ZERO)) ||
                    !entry_q[i].rob_tag.valid)
                    debug_bru_operand_o[41] = 1'b1;
                debug_bru_count = debug_bru_count + 1;
            end
            if (entry_ready(entry_q[i])) begin
                debug_ready_count_o = debug_ready_count_o + IQ_COUNT_W'(1);
                unique case (entry_q[i].fu_type)
                    BBUS_OOO_FU_ALU,
                    BBUS_OOO_FU_NONE: begin
                        debug_ready_alu_count_o = debug_ready_alu_count_o + IQ_COUNT_W'(1);
                    end
                    BBUS_OOO_FU_LSU: begin
                        debug_ready_lsu_count_o = debug_ready_lsu_count_o + IQ_COUNT_W'(1);
                    end
                    BBUS_OOO_FU_BRU: begin
                        debug_ready_bru_count_o = debug_ready_bru_count_o + IQ_COUNT_W'(1);
                    end
                    BBUS_OOO_FU_CSR,
                    BBUS_OOO_FU_SYS: begin
                        debug_ready_csr_sys_count_o = debug_ready_csr_sys_count_o + IQ_COUNT_W'(1);
                    end
                    default: begin
                    end
                endcase
                if (entry_fu_available(entry_q[i]) &&
                    (!issue_found_c || entry_older_than(entry_q[i], issue_uop_select_c))) begin
                    issue_found_c = 1'b1;
                    issue_idx_c = IQ_IDX_W'(i);
                    issue_uop_select_c = entry_q[i];
                end
            end
        end

        if (debug_dependency_found0)
            debug_dependency_operand_o[23:0] =
                dependency_debug_record(debug_dependency_uop0);
        if (debug_dependency_found1)
            debug_dependency_operand_o[47:24] =
                dependency_debug_record(debug_dependency_uop1);
        debug_dependency_operand_o[51:48] = 4'(debug_dependency_count);
        debug_dependency_operand_o[52] = debug_dependency_invalid;
        debug_dependency_operand_o[53] = (debug_dependency_count > 2);
        debug_retirement_head_o[0] = debug_head_found;
        debug_retirement_head_o[1] = debug_head_src1_wait;
        debug_retirement_head_o[2] = debug_head_src2_wait;
        debug_retirement_head_o[3] = debug_head_ready;

        // S6_SIMPLIFICATION: issue2 select is still a fixed 2-wide scan.
        // FUTURE: stage or matrix this select before increasing beyond depth 8.
        if (issue_found_c) begin
            for (i = 0; i < IQ_DEPTH; i = i + 1) begin
                if ((IQ_IDX_W'(i) != issue_idx_c) &&
                    legal_issue2_pair(issue_uop_select_c, entry_q[i]) &&
                    pair_ports_available(issue_uop_select_c, entry_q[i])) begin
                    if (!issue1_found_c || entry_older_than(entry_q[i], issue1_uop_select_c)) begin
                        issue1_found_c = 1'b1;
                        issue1_idx_c = IQ_IDX_W'(i);
                        issue1_uop_select_c = entry_q[i];
                    end
                end
            end
        end

        registered_issue_found_c = issue_found_c;
        registered_issue1_found_c = issue1_found_c;
        registered_issue_uop_c = issue_uop_select_c;

        // P80: preserve registered-pair priority, then allow an accepted
        // Dispatch0 ordinary uop to fill lane1 beside the selected registered
        // BRU. Dispatch ready remains capacity-only; if the atomic pair cannot
        // fire, Dispatch0 is buffered by the unchanged enqueue path below.
        if (REGISTERED_BRU_DISPATCH_ORDINARY_ISSUE2_ENABLE &&
            !grant_hold_q && registered_issue_found_c &&
            !registered_issue1_found_c && dispatch0_fire_c &&
            (registered_issue_uop_c.fu_type == BBUS_OOO_FU_BRU) &&
            entry_ready(dispatch_uop_i) &&
            entry_older_than(registered_issue_uop_c, dispatch_uop_i) &&
            legal_issue2_pair(registered_issue_uop_c, dispatch_uop_i) &&
            pair_ports_available(registered_issue_uop_c, dispatch_uop_i)) begin
            issue1_found_c = 1'b1;
            issue1_idx_c = '0;
            issue1_uop_select_c = dispatch_uop_i;
            issue1_from_dispatch0_c = 1'b1;
        end

        // When no registered-ready candidate exists, a newly allocated
        // ordinary ALU/load, or an independently enabled branch, may use the
        // existing issue path on the dispatch edge without displacing any
        // older ready instruction.
        // Backpressure is handled by the normal dispatch enqueue below; the
        // bypass never creates a held grant or drops an unaccepted uop.
        if (SAME_CYCLE_DISPATCH_ISSUE_ENABLE && !grant_hold_q &&
            !issue_found_c && dispatch0_fire_c &&
            entry_ready(dispatch_uop_i) &&
            entry_fu_available(dispatch_uop_i) &&
            ((SAME_CYCLE_DISPATCH_ISSUE_ENABLE &&
              (is_alu_like(dispatch_uop_i) ||
               is_lsu_load(dispatch_uop_i))) ||
             (SAME_CYCLE_BRANCH_DISPATCH_ISSUE_ENABLE &&
              (dispatch_uop_i.fu_type == BBUS_OOO_FU_BRU)))) begin
            issue_found_c = 1'b1;
            issue_idx_c = '0;
            issue_uop_select_c = dispatch_uop_i;
            issue_from_dispatch0_c = 1'b1;
            if (dispatch1_fire_c &&
                legal_issue2_pair(dispatch_uop_i, dispatch1_uop_i) &&
                pair_ports_available(dispatch_uop_i, dispatch1_uop_i)) begin
                issue1_found_c = 1'b1;
                issue1_idx_c = IQ_IDX_W'(1);
                issue1_uop_select_c = dispatch1_uop_i;
                issue1_from_dispatch1_c = 1'b1;
            end else begin
                issue1_found_c = 1'b0;
                issue1_idx_c = '0;
                issue1_uop_select_c = '0;
            end
        end
        debug_retirement_head_o[4] = rob_head_tag_i.valid &&
            (grant_hold_q || issue_found_c) &&
            ((grant_hold_q ? grant_uop_q.rob_tag :
              issue_uop_select_c.rob_tag) == rob_head_tag_i);
        debug_retirement_head_o[5] = rob_head_tag_i.valid &&
            (grant_hold_q ? grant1_hold_q : issue1_found_c) &&
            ((grant_hold_q ? grant1_uop_q.rob_tag :
              issue1_uop_select_c.rob_tag) == rob_head_tag_i);
        debug_retirement_head_o[6] = debug_head_invalid ||
            ((debug_head_src1_wait || debug_head_src2_wait) &&
             debug_head_ready);
    end


    // P8 measurement-only oracle. This classifies whether an accepted
    // dispatch slot0 could fill lane1 beside the selected registered owner.
    // It does not participate in issue selection.
    always_comb begin
        debug_mixed_source_valid_o = registered_issue_found_c;
        debug_mixed_source_reason_o = MIXED_REASON_NO_DISPATCH;
        debug_mixed_source_pair_kind_o = 2'd0;

        if (legal_alu_alu_pair(registered_issue_uop_c, dispatch_uop_i)) begin
            debug_mixed_source_pair_kind_o = 2'd1;
        end else if (legal_alu_lsu_pair(
                         registered_issue_uop_c, dispatch_uop_i)) begin
            debug_mixed_source_pair_kind_o =
                is_alu_like(registered_issue_uop_c) ? 2'd2 : 2'd3;
        end

        if (registered_issue_found_c) begin
            if (registered_issue1_found_c) begin
                debug_mixed_source_reason_o = MIXED_REASON_REGISTERED_PAIR;
            end else if (grant_hold_q || flush_i || selective_kill_valid_i) begin
                debug_mixed_source_reason_o = MIXED_REASON_SERIAL_RECOVERY;
            end else if (!dispatch0_fire_c) begin
                debug_mixed_source_reason_o = MIXED_REASON_NO_DISPATCH;
            end else if (!entry_ready(dispatch_uop_i)) begin
                debug_mixed_source_reason_o = MIXED_REASON_INCOMING_NOT_READY;
            end else if ((debug_mixed_source_pair_kind_o == 2'd0) ||
                         !legal_issue2_pair(
                             registered_issue_uop_c, dispatch_uop_i)) begin
                debug_mixed_source_reason_o = MIXED_REASON_ILLEGAL_PAIR;
            end else if (!pair_ports_available(
                             registered_issue_uop_c, dispatch_uop_i)) begin
                debug_mixed_source_reason_o = MIXED_REASON_PORT_UNAVAILABLE;
            end else begin
                debug_mixed_source_reason_o = MIXED_REASON_ELIGIBLE;
            end
        end
    end

    // P9 measurement-only structural oracle. None of these values feed queue
    // ownership, selection, ready, or fire.
    generate
    if (STRUCTURAL_THROUGHPUT_ORACLE_ENABLE) begin : g_structural_oracle
    always_comb begin : structural_oracle
        integer i;
        integer j;
        integer model;
        integer phase;
        integer age_i;
        integer age_j;
        integer pair_key;
        integer registered_valid_count;
        integer registered_ready_count;
        integer accepted_valid_count;
        integer accepted_ready_count;
        integer offered_valid_count;
        integer offered_ready_count;
        integer total_valid_count;
        integer total_ready_count;
        integer fallback_key;
        integer fallback_i;
        integer fallback_j;
        integer selected_age_i;
        integer selected_age_j;
        integer single_first_model;
        integer pair_first_model;
        logic single_port;
        logic single_downstream;
        logic pair_current;
        logic pair_branch;
        logic pair_store;
        logic pair_supported;
        logic pair_actual_ready;
        logic pair_ideal_ready;
        logic pair_in_current;
        logic pair_in_accepted;
        logic pair_in_offered;
        logic pair_ports;
        logic pair_downstream;
        logic any_port_loss;
        logic oracle_blocked;

        debug_structural_oracle_o = '0;
        debug_structural_meta_o = '0;
        struct_reason_c = STRUCT_REASON_OTHER;
        struct_overlap_c = '0;
        struct_state_error_c = 1'b0;
        struct_selected_model_c = -1;
        struct_selected_i_c = -1;
        struct_selected_j_c = -1;
        struct_selected_source0_c = '0;
        struct_selected_source1_c = '0;
        struct_selected_fu0_c = '0;
        struct_selected_fu1_c = '0;
        struct_selected_tag0_c = '0;
        struct_selected_tag1_c = '0;
        struct_selected_tag_valid_c = '0;
        struct_branch_relation_c = '0;
        struct_pair_kind_c = '0;
        registered_valid_count = 0;
        registered_ready_count = 0;
        accepted_valid_count = 0;
        accepted_ready_count = 0;
        offered_valid_count = 0;
        offered_ready_count = 0;
        total_valid_count = 0;
        total_ready_count = 0;
        fallback_key = 32'h7fff_ffff;
        fallback_i = -1;
        fallback_j = -1;
        selected_age_i = 0;
        selected_age_j = 0;
        any_port_loss = 1'b0;
        oracle_blocked = flush_i || selective_kill_valid_i || grant_hold_q;

        for (i = 0; i < STRUCT_CANDIDATE_COUNT; i = i + 1) begin
            struct_candidate_uop_c[i] = '0;
            struct_candidate_valid_c[i] = 1'b0;
            struct_candidate_ready_c[i] = 1'b0;
            struct_candidate_ideal_ready_c[i] = 1'b0;
            struct_candidate_source_c[i] = STRUCT_SOURCE_REGISTERED;
            for (model = 0; model < STRUCT_MODEL_COUNT; model = model + 1)
                struct_model_include_c[model][i] = 1'b0;
        end

        for (i = 0; i < IQ_DEPTH; i = i + 1) begin
            struct_candidate_uop_c[i] = entry_q[i];
            struct_candidate_valid_c[i] = entry_q[i].valid;
            struct_candidate_source_c[i] = STRUCT_SOURCE_REGISTERED;
        end
        struct_candidate_uop_c[IQ_DEPTH] = dispatch_uop_i;
        struct_candidate_valid_c[IQ_DEPTH] = dispatch0_fire_c;
        struct_candidate_source_c[IQ_DEPTH] = STRUCT_SOURCE_DISPATCH0;
        struct_candidate_uop_c[IQ_DEPTH + 1] = dispatch1_uop_i;
        struct_candidate_valid_c[IQ_DEPTH + 1] = dispatch1_fire_c;
        struct_candidate_source_c[IQ_DEPTH + 1] = STRUCT_SOURCE_DISPATCH1;
        struct_candidate_uop_c[IQ_DEPTH + 2] = oracle_offer_uop0_i;
        struct_candidate_uop_c[IQ_DEPTH + 2].valid =
            oracle_offer_valid_mask_i[0] && !dispatch0_fire_c;
        struct_candidate_valid_c[IQ_DEPTH + 2] =
            oracle_offer_valid_mask_i[0] && !dispatch0_fire_c;
        struct_candidate_source_c[IQ_DEPTH + 2] = STRUCT_SOURCE_OFFER0;
        struct_candidate_uop_c[IQ_DEPTH + 3] = oracle_offer_uop1_i;
        struct_candidate_uop_c[IQ_DEPTH + 3].valid =
            oracle_offer_valid_mask_i[1] && !dispatch1_fire_c;
        struct_candidate_valid_c[IQ_DEPTH + 3] =
            oracle_offer_valid_mask_i[1] && !dispatch1_fire_c;
        struct_candidate_source_c[IQ_DEPTH + 3] = STRUCT_SOURCE_OFFER1;

        for (i = 0; i < STRUCT_CANDIDATE_COUNT; i = i + 1) begin
            struct_candidate_ready_c[i] = struct_candidate_valid_c[i] &&
                entry_ready(struct_candidate_uop_c[i]);
            struct_candidate_ideal_ready_c[i] =
                struct_candidate_valid_c[i] &&
                !(selective_kill_valid_i &&
                  struct_candidate_uop_c[i].rob_tag.valid &&
                  selective_killed_rob_mask_i[
                      struct_candidate_uop_c[i].rob_tag.idx]);
            total_valid_count = total_valid_count +
                (struct_candidate_valid_c[i] ? 1 : 0);
            total_ready_count = total_ready_count +
                (struct_candidate_ready_c[i] ? 1 : 0);
            if (i < IQ_DEPTH) begin
                registered_valid_count = registered_valid_count +
                    (struct_candidate_valid_c[i] ? 1 : 0);
                registered_ready_count = registered_ready_count +
                    (struct_candidate_ready_c[i] ? 1 : 0);
            end else if (i < IQ_DEPTH + 2) begin
                accepted_valid_count = accepted_valid_count +
                    (struct_candidate_valid_c[i] ? 1 : 0);
                accepted_ready_count = accepted_ready_count +
                    (struct_candidate_ready_c[i] ? 1 : 0);
            end else begin
                offered_valid_count = offered_valid_count +
                    (struct_candidate_valid_c[i] ? 1 : 0);
                offered_ready_count = offered_ready_count +
                    (struct_candidate_ready_c[i] ? 1 : 0);
            end

            if (i < IQ_DEPTH) begin
                struct_model_include_c[STRUCT_MODEL_CURRENT_MAX][i] =
                    registered_issue_found_c;
                for (model = STRUCT_MODEL_ACCEPTED;
                     model < STRUCT_MODEL_COUNT; model = model + 1)
                    struct_model_include_c[model][i] = 1'b1;
            end else if (i < IQ_DEPTH + 2) begin
                struct_model_include_c[STRUCT_MODEL_CURRENT_MAX][i] =
                    !registered_issue_found_c &&
                    struct_current_dispatch_allowed(struct_candidate_uop_c[i]);
                // P80 extends the current implementation's source ownership:
                // an accepted Dispatch0 ordinary may be the second source
                // beside the selected registered BRU.  Reflect that boundary
                // in CURRENT_MAX as well as in ACTUAL, otherwise every real
                // P80 pair incorrectly violates the Oracle nesting invariant.
                // Dispatch1 remains excluded because P80 never bypasses it.
                if ((i == IQ_DEPTH) &&
                    REGISTERED_BRU_DISPATCH_ORDINARY_ISSUE2_ENABLE &&
                    registered_issue_found_c &&
                    !registered_issue1_found_c &&
                    (registered_issue_uop_c.fu_type == BBUS_OOO_FU_BRU) &&
                    entry_older_than(registered_issue_uop_c,
                                     struct_candidate_uop_c[i]))
                    struct_model_include_c[STRUCT_MODEL_CURRENT_MAX][i] = 1'b1;
                for (model = STRUCT_MODEL_ACCEPTED;
                     model < STRUCT_MODEL_COUNT; model = model + 1)
                    struct_model_include_c[model][i] = 1'b1;
            end else begin
                for (model = STRUCT_MODEL_OFFERED;
                     model < STRUCT_MODEL_COUNT; model = model + 1)
                    struct_model_include_c[model][i] = 1'b1;
            end
        end

        for (model = 0; model < STRUCT_MODEL_COUNT; model = model + 1) begin
            for (phase = 0; phase < STRUCT_PHASE_COUNT; phase = phase + 1)
                struct_width_c[model][phase] = 2'd0;
            struct_best_select_i_c[model] = -1;
            struct_best_select_j_c[model] = -1;
            struct_best_port_i_c[model] = -1;
            struct_best_port_j_c[model] = -1;
            struct_best_down_i_c[model] = -1;
            struct_best_down_j_c[model] = -1;
            struct_best_select_key_c[model] = 32'h7fff_ffff;
            struct_best_port_key_c[model] = 32'h7fff_ffff;
            struct_best_down_key_c[model] = 32'h7fff_ffff;
        end

        struct_width_c[STRUCT_MODEL_ACTUAL][STRUCT_PHASE_SELECT] =
            {1'b0, issue_valid_o} + {1'b0, issue1_valid_o};
        struct_width_c[STRUCT_MODEL_ACTUAL][STRUCT_PHASE_PORT] =
            struct_width_c[STRUCT_MODEL_ACTUAL][STRUCT_PHASE_SELECT];
        struct_width_c[STRUCT_MODEL_ACTUAL][STRUCT_PHASE_DOWNSTREAM] =
            {1'b0, issue_fire_c} + {1'b0, issue1_fire_c};

        // Candidate inclusion, readiness, and pair topology are monotonic
        // across the structural models. Classify each candidate and pair once,
        // then propagate it from the first model where it is reachable.
        for (i = 0; i < STRUCT_CANDIDATE_COUNT; i = i + 1) begin
            single_first_model = -1;
            if (struct_candidate_ready_c[i]) begin
                if (struct_model_include_c[STRUCT_MODEL_CURRENT_MAX][i])
                    single_first_model = STRUCT_MODEL_CURRENT_MAX;
                else if (struct_model_include_c[STRUCT_MODEL_ACCEPTED][i])
                    single_first_model = STRUCT_MODEL_ACCEPTED;
                else if (struct_model_include_c[STRUCT_MODEL_OFFERED][i])
                    single_first_model = STRUCT_MODEL_OFFERED;
            end else if (struct_candidate_ideal_ready_c[i] &&
                         struct_model_include_c[STRUCT_MODEL_IDEAL_READY][i]) begin
                single_first_model = STRUCT_MODEL_IDEAL_READY;
            end
            single_port = struct_single_port_available(
                struct_candidate_uop_c[i]);
            single_downstream = single_port &&
                struct_single_downstream_available(struct_candidate_uop_c[i]);
            if (single_first_model >= 0) begin
                for (model = STRUCT_MODEL_CURRENT_MAX;
                     model < STRUCT_MODEL_COUNT; model = model + 1) begin
                    if (model >= single_first_model) begin
                        if (struct_width_c[model][STRUCT_PHASE_SELECT] < 2'd1)
                            struct_width_c[model][STRUCT_PHASE_SELECT] = 2'd1;
                        if (single_port &&
                            (struct_width_c[model][STRUCT_PHASE_PORT] < 2'd1))
                            struct_width_c[model][STRUCT_PHASE_PORT] = 2'd1;
                        if (single_downstream &&
                            (struct_width_c[model][STRUCT_PHASE_DOWNSTREAM] < 2'd1))
                            struct_width_c[model][STRUCT_PHASE_DOWNSTREAM] = 2'd1;
                    end
                end
            end

            age_i = struct_age(struct_candidate_uop_c[i],
                struct_candidate_source_c[i]);
            for (j = i + 1; j < STRUCT_CANDIDATE_COUNT; j = j + 1) begin
                age_j = struct_age(struct_candidate_uop_c[j],
                    struct_candidate_source_c[j]);
                pair_key = ((age_i < age_j) ? age_i : age_j) * 32 +
                    ((age_i < age_j) ? age_j : age_i);
                pair_current = struct_current_pair_type(
                    struct_candidate_uop_c[i], struct_candidate_uop_c[j]);
                pair_branch = struct_branch_pair_type(
                    struct_candidate_uop_c[i], struct_candidate_uop_c[j]);
                pair_store = struct_store_pair_type(
                    struct_candidate_uop_c[i], struct_candidate_uop_c[j]);
                pair_supported = pair_current || pair_branch || pair_store;
                pair_actual_ready = struct_candidate_ready_c[i] &&
                    struct_candidate_ready_c[j];
                pair_ideal_ready = struct_candidate_ideal_ready_c[i] &&
                    struct_candidate_ideal_ready_c[j];
                pair_in_current =
                    struct_model_include_c[STRUCT_MODEL_CURRENT_MAX][i] &&
                    struct_model_include_c[STRUCT_MODEL_CURRENT_MAX][j];
                pair_in_accepted =
                    struct_model_include_c[STRUCT_MODEL_ACCEPTED][i] &&
                    struct_model_include_c[STRUCT_MODEL_ACCEPTED][j];
                pair_in_offered =
                    struct_model_include_c[STRUCT_MODEL_OFFERED][i] &&
                    struct_model_include_c[STRUCT_MODEL_OFFERED][j];

                if (pair_in_offered && pair_actual_ready &&
                    (pair_key < fallback_key)) begin
                    fallback_key = pair_key;
                    fallback_i = i;
                    fallback_j = j;
                end

                pair_first_model = -1;
                if (pair_actual_ready && pair_current) begin
                    if (pair_in_current)
                        pair_first_model = STRUCT_MODEL_CURRENT_MAX;
                    else if (pair_in_accepted)
                        pair_first_model = STRUCT_MODEL_ACCEPTED;
                    else if (pair_in_offered)
                        pair_first_model = STRUCT_MODEL_OFFERED;
                end
                if ((pair_first_model < 0) && pair_actual_ready &&
                    pair_in_offered && pair_branch)
                    pair_first_model = STRUCT_MODEL_BRANCH;
                if ((pair_first_model < 0) && pair_actual_ready &&
                    pair_in_offered && pair_store)
                    pair_first_model = STRUCT_MODEL_STORE;
                if ((pair_first_model < 0) && pair_ideal_ready &&
                    pair_in_offered && pair_supported)
                    pair_first_model = STRUCT_MODEL_IDEAL_READY;

                pair_ports = pair_supported &&
                    struct_pair_ports_available(STRUCT_MODEL_STORE,
                        struct_candidate_uop_c[i], struct_candidate_uop_c[j]);
                pair_downstream = pair_ports &&
                    struct_pair_downstream_available(STRUCT_MODEL_STORE,
                        struct_candidate_uop_c[i], struct_candidate_uop_c[j]);
                if (pair_first_model >= 0) begin
                    for (model = STRUCT_MODEL_CURRENT_MAX;
                         model < STRUCT_MODEL_COUNT; model = model + 1) begin
                        if (model >= pair_first_model) begin
                            struct_width_c[model][STRUCT_PHASE_SELECT] = 2'd2;
                            if (pair_key < struct_best_select_key_c[model]) begin
                                struct_best_select_key_c[model] = pair_key;
                                struct_best_select_i_c[model] = i;
                                struct_best_select_j_c[model] = j;
                            end
                            if (pair_ports) begin
                                struct_width_c[model][STRUCT_PHASE_PORT] = 2'd2;
                                if (pair_key < struct_best_port_key_c[model]) begin
                                    struct_best_port_key_c[model] = pair_key;
                                    struct_best_port_i_c[model] = i;
                                    struct_best_port_j_c[model] = j;
                                end
                            end
                            if (pair_downstream) begin
                                struct_width_c[model][STRUCT_PHASE_DOWNSTREAM] = 2'd2;
                                if (pair_key < struct_best_down_key_c[model]) begin
                                    struct_best_down_key_c[model] = pair_key;
                                    struct_best_down_i_c[model] = i;
                                    struct_best_down_j_c[model] = j;
                                end
                            end
                        end
                    end
                end
            end
        end

        if (oracle_blocked) begin
            for (model = STRUCT_MODEL_CURRENT_MAX;
                 model < STRUCT_MODEL_COUNT; model = model + 1)
                for (phase = 0; phase < STRUCT_PHASE_COUNT; phase = phase + 1)
                    struct_width_c[model][phase] =
                        struct_width_c[STRUCT_MODEL_ACTUAL][phase];
        end

        for (model = 0; model < STRUCT_MODEL_COUNT; model = model + 1) begin
            if ((struct_width_c[model][STRUCT_PHASE_PORT] >
                 struct_width_c[model][STRUCT_PHASE_SELECT]) ||
                (struct_width_c[model][STRUCT_PHASE_DOWNSTREAM] >
                 struct_width_c[model][STRUCT_PHASE_PORT]))
                struct_state_error_c = 1'b1;
            if ((struct_width_c[model][STRUCT_PHASE_SELECT] == 2) &&
                (struct_width_c[model][STRUCT_PHASE_PORT] < 2))
                any_port_loss = 1'b1;
        end
        if (!oracle_blocked) begin
            for (model = STRUCT_MODEL_ACCEPTED;
                 model < STRUCT_MODEL_COUNT; model = model + 1)
                for (phase = 0; phase < STRUCT_PHASE_COUNT; phase = phase + 1)
                    if (struct_width_c[model][phase] <
                        struct_width_c[model - 1][phase])
                        struct_state_error_c = 1'b1;
            for (phase = 0; phase < STRUCT_PHASE_COUNT; phase = phase + 1)
                if (struct_width_c[STRUCT_MODEL_CURRENT_MAX][phase] <
                    struct_width_c[STRUCT_MODEL_ACTUAL][phase])
                    struct_state_error_c = 1'b1;
        end

        struct_overlap_c[0] = oracle_blocked;
        struct_overlap_c[1] =
            (struct_width_c[STRUCT_MODEL_ACTUAL][STRUCT_PHASE_SELECT] >
             struct_width_c[STRUCT_MODEL_ACTUAL][STRUCT_PHASE_DOWNSTREAM]);
        struct_overlap_c[2] = (total_valid_count < 2);
        struct_overlap_c[3] =
            (total_valid_count >= 2) && (total_ready_count < 2);
        struct_overlap_c[4] =
            (struct_width_c[STRUCT_MODEL_OFFERED][STRUCT_PHASE_DOWNSTREAM] >
             struct_width_c[STRUCT_MODEL_ACCEPTED][STRUCT_PHASE_DOWNSTREAM]);
        struct_overlap_c[5] =
            (struct_width_c[STRUCT_MODEL_ACCEPTED][STRUCT_PHASE_DOWNSTREAM] >
             struct_width_c[STRUCT_MODEL_CURRENT_MAX][STRUCT_PHASE_DOWNSTREAM]);
        struct_overlap_c[6] =
            (struct_width_c[STRUCT_MODEL_CURRENT_MAX][STRUCT_PHASE_DOWNSTREAM] >
             struct_width_c[STRUCT_MODEL_ACTUAL][STRUCT_PHASE_DOWNSTREAM]);
        struct_overlap_c[7] = (total_ready_count >= 2) &&
            (struct_width_c[STRUCT_MODEL_OFFERED][STRUCT_PHASE_SELECT] < 2);
        struct_overlap_c[8] =
            (struct_width_c[STRUCT_MODEL_BRANCH][STRUCT_PHASE_DOWNSTREAM] >
             struct_width_c[STRUCT_MODEL_OFFERED][STRUCT_PHASE_DOWNSTREAM]);
        struct_overlap_c[9] =
            (struct_width_c[STRUCT_MODEL_STORE][STRUCT_PHASE_DOWNSTREAM] >
             struct_width_c[STRUCT_MODEL_BRANCH][STRUCT_PHASE_DOWNSTREAM]);
        struct_overlap_c[10] = any_port_loss;
        struct_overlap_c[11] = (total_ready_count >= 2) &&
            (struct_width_c[STRUCT_MODEL_STORE][STRUCT_PHASE_SELECT] < 2);

        if (struct_width_c[STRUCT_MODEL_ACTUAL][STRUCT_PHASE_DOWNSTREAM] == 2) begin
            struct_reason_c = STRUCT_REASON_PROGRESS;
        end else if (oracle_blocked) begin
            struct_reason_c = STRUCT_REASON_RECOVERY;
        end else if (struct_overlap_c[1]) begin
            struct_reason_c = STRUCT_REASON_DOWNSTREAM;
        end else if (total_valid_count < 2) begin
            struct_reason_c = STRUCT_REASON_SUPPLY;
        end else if ((struct_width_c[STRUCT_MODEL_IDEAL_READY]
                        [STRUCT_PHASE_DOWNSTREAM] == 2) &&
                     (struct_width_c[STRUCT_MODEL_STORE]
                        [STRUCT_PHASE_DOWNSTREAM] < 2)) begin
            struct_reason_c = STRUCT_REASON_OPERAND;
            struct_selected_model_c = STRUCT_MODEL_IDEAL_READY;
        end else if (struct_overlap_c[4]) begin
            struct_reason_c = STRUCT_REASON_ADMISSION;
            struct_selected_model_c = STRUCT_MODEL_OFFERED;
        end else if (struct_overlap_c[5]) begin
            struct_reason_c = STRUCT_REASON_SOURCE;
            struct_selected_model_c = STRUCT_MODEL_ACCEPTED;
        end else if (struct_overlap_c[6]) begin
            struct_reason_c = STRUCT_REASON_GREEDY;
            struct_selected_model_c = STRUCT_MODEL_CURRENT_MAX;
        end else if (struct_overlap_c[8]) begin
            struct_reason_c = STRUCT_REASON_BRANCH;
            struct_selected_model_c = STRUCT_MODEL_BRANCH;
        end else if (struct_overlap_c[9]) begin
            struct_reason_c = STRUCT_REASON_STORE;
            struct_selected_model_c = STRUCT_MODEL_STORE;
        end else if (any_port_loss) begin
            struct_reason_c = STRUCT_REASON_PORT;
            for (model = STRUCT_MODEL_CURRENT_MAX;
                 model < STRUCT_MODEL_COUNT; model = model + 1)
                if ((struct_selected_model_c < 0) &&
                    (struct_width_c[model][STRUCT_PHASE_SELECT] == 2) &&
                    (struct_width_c[model][STRUCT_PHASE_PORT] < 2))
                    struct_selected_model_c = model;
        end else if (total_ready_count >= 2) begin
            struct_reason_c = STRUCT_REASON_TOPOLOGY;
            struct_selected_model_c = STRUCT_MODEL_OFFERED;
        end else begin
            struct_reason_c = STRUCT_REASON_OTHER;
        end

        if (struct_selected_model_c >= 0) begin
            if (struct_best_down_i_c[struct_selected_model_c] >= 0) begin
                struct_selected_i_c =
                    struct_best_down_i_c[struct_selected_model_c];
                struct_selected_j_c =
                    struct_best_down_j_c[struct_selected_model_c];
            end else if (struct_best_port_i_c[struct_selected_model_c] >= 0) begin
                struct_selected_i_c =
                    struct_best_port_i_c[struct_selected_model_c];
                struct_selected_j_c =
                    struct_best_port_j_c[struct_selected_model_c];
            end else begin
                struct_selected_i_c =
                    struct_best_select_i_c[struct_selected_model_c];
                struct_selected_j_c =
                    struct_best_select_j_c[struct_selected_model_c];
            end
        end

        if ((struct_reason_c == STRUCT_REASON_TOPOLOGY) &&
            (struct_selected_i_c < 0)) begin
            struct_selected_i_c = fallback_i;
            struct_selected_j_c = fallback_j;
        end

        if ((struct_selected_i_c >= 0) && (struct_selected_j_c >= 0)) begin
            selected_age_i = struct_age(
                struct_candidate_uop_c[struct_selected_i_c],
                struct_candidate_source_c[struct_selected_i_c]);
            selected_age_j = struct_age(
                struct_candidate_uop_c[struct_selected_j_c],
                struct_candidate_source_c[struct_selected_j_c]);
            if (selected_age_i <= selected_age_j) begin
                i = struct_selected_i_c;
                j = struct_selected_j_c;
            end else begin
                i = struct_selected_j_c;
                j = struct_selected_i_c;
            end
            struct_selected_source0_c = struct_candidate_source_c[i];
            struct_selected_source1_c = struct_candidate_source_c[j];
            struct_selected_fu0_c = struct_fu_class(struct_candidate_uop_c[i]);
            struct_selected_fu1_c = struct_fu_class(struct_candidate_uop_c[j]);
            struct_selected_tag0_c = {
                struct_candidate_uop_c[i].rob_tag.gen,
                struct_candidate_uop_c[i].rob_tag.idx};
            struct_selected_tag1_c = {
                struct_candidate_uop_c[j].rob_tag.gen,
                struct_candidate_uop_c[j].rob_tag.idx};
            struct_selected_tag_valid_c[0] =
                struct_candidate_uop_c[i].rob_tag.valid &&
                (struct_candidate_source_c[i] <= STRUCT_SOURCE_DISPATCH1);
            struct_selected_tag_valid_c[1] =
                struct_candidate_uop_c[j].rob_tag.valid &&
                (struct_candidate_source_c[j] <= STRUCT_SOURCE_DISPATCH1);

            if ((struct_selected_fu0_c == 3'd3) &&
                ((struct_selected_fu1_c == 3'd1) ||
                 (struct_selected_fu1_c == 3'd2)))
                struct_branch_relation_c = 2'd2;
            else if ((struct_selected_fu1_c == 3'd3) &&
                     ((struct_selected_fu0_c == 3'd1) ||
                      (struct_selected_fu0_c == 3'd2)))
                struct_branch_relation_c = 2'd1;

            if ((struct_selected_fu0_c == 3'd1) &&
                (struct_selected_fu1_c == 3'd1))
                struct_pair_kind_c = 4'd1;
            else if (((struct_selected_fu0_c == 3'd1) &&
                      (struct_selected_fu1_c == 3'd2)) ||
                     ((struct_selected_fu0_c == 3'd2) &&
                      (struct_selected_fu1_c == 3'd1)))
                struct_pair_kind_c = 4'd2;
            else if (((struct_selected_fu0_c == 3'd1) &&
                      (struct_selected_fu1_c == 3'd3)) ||
                     ((struct_selected_fu0_c == 3'd3) &&
                      (struct_selected_fu1_c == 3'd1)))
                struct_pair_kind_c = 4'd3;
            else if (((struct_selected_fu0_c == 3'd2) &&
                      (struct_selected_fu1_c == 3'd3)) ||
                     ((struct_selected_fu0_c == 3'd3) &&
                      (struct_selected_fu1_c == 3'd2)))
                struct_pair_kind_c = 4'd4;
            else if (((struct_selected_fu0_c == 3'd1) &&
                      (struct_selected_fu1_c == 3'd4)) ||
                     ((struct_selected_fu0_c == 3'd4) &&
                      (struct_selected_fu1_c == 3'd1)))
                struct_pair_kind_c = 4'd5;
            else if (((struct_selected_fu0_c == 3'd2) &&
                      (struct_selected_fu1_c == 3'd4)) ||
                     ((struct_selected_fu0_c == 3'd4) &&
                      (struct_selected_fu1_c == 3'd2)))
                struct_pair_kind_c = 4'd6;
            else
                struct_pair_kind_c = 4'd15;

            if (struct_selected_tag_valid_c[0] &&
                struct_selected_tag_valid_c[1] &&
                (struct_selected_tag0_c == struct_selected_tag1_c))
                struct_state_error_c = 1'b1;
        end

        for (model = 0; model < STRUCT_MODEL_COUNT; model = model + 1)
            for (phase = 0; phase < STRUCT_PHASE_COUNT; phase = phase + 1)
                debug_structural_oracle_o[
                    model * STRUCT_PHASE_COUNT * 2 + phase * 2 +: 2] =
                    struct_width_c[model][phase];
        debug_structural_oracle_o[45:42] = struct_reason_c;
        debug_structural_oracle_o[57:46] = struct_overlap_c;
        debug_structural_oracle_o[58] = struct_state_error_c;
        debug_structural_oracle_o[59] = oracle_blocked;
        debug_structural_oracle_o[61:60] = struct_selected_tag_valid_c;

        debug_structural_meta_o[3:0] = 4'(registered_valid_count);
        debug_structural_meta_o[7:4] = 4'(registered_ready_count);
        debug_structural_meta_o[9:8] = 2'(accepted_valid_count);
        debug_structural_meta_o[11:10] = 2'(accepted_ready_count);
        debug_structural_meta_o[13:12] = 2'(offered_valid_count);
        debug_structural_meta_o[15:14] = 2'(offered_ready_count);
        debug_structural_meta_o[20:16] = struct_selected_tag0_c;
        debug_structural_meta_o[25:21] = struct_selected_tag1_c;
        debug_structural_meta_o[28:26] = struct_selected_source0_c;
        debug_structural_meta_o[31:29] = struct_selected_source1_c;
        debug_structural_meta_o[34:32] = struct_selected_fu0_c;
        debug_structural_meta_o[37:35] = struct_selected_fu1_c;
        debug_structural_meta_o[40:38] =
            (struct_selected_model_c >= 0) ?
                3'(struct_selected_model_c) : 3'd0;
        debug_structural_meta_o[42:41] = struct_branch_relation_c;
        debug_structural_meta_o[46:43] = struct_pair_kind_c;
        debug_structural_meta_o[47] = struct_state_error_c;
    end
    end else begin : g_no_structural_oracle
        always_comb begin
            debug_structural_oracle_o = '0;
            debug_structural_meta_o = '0;
        end
    end
    endgenerate

    assign free_count_c = IQ_COUNT_W'(IQ_DEPTH) - count_q;
    assign dispatch_ready_count_o =
        (flush_i || selective_kill_valid_i) ? 2'd0 :
        ((free_count_c >= IQ_COUNT_W'(2)) ? 2'd2 :
         ((free_count_c >= IQ_COUNT_W'(1)) ? 2'd1 : 2'd0));
    assign dispatch_ready_o = (dispatch_ready_count_o >= 2'd1);
    assign dispatch1_ready_o = (dispatch_ready_count_o >= 2'd2);
    assign dispatch0_fire_c = dispatch_valid_i && dispatch_ready_o;
    assign dispatch1_fire_c = dispatch0_fire_c && dispatch1_valid_i && dispatch1_ready_o;
    assign dispatch_fire_mask_o = {dispatch1_fire_c, dispatch0_fire_c};
    // Flush is an architectural kill boundary, not merely a sequential clear.
    // Suppress handshakes for the whole asserted cycle so a consumer cannot
    // issue an entry that will be discarded at this edge.
    always_comb begin
        issue_idx_selected_c = grant_hold_q ? grant_idx_q : issue_idx_c;
        issue1_idx_selected_c = grant_hold_q ? grant1_idx_q : issue1_idx_c;
        issue_uop_o = grant_hold_q ? grant_uop_q : issue_uop_select_c;
        issue1_uop_o = grant_hold_q ? grant1_uop_q : issue1_uop_select_c;
    end

    assign issue_valid_o = !flush_i && !selective_kill_valid_i &&
        (grant_hold_q || issue_found_c);
    assign issue1_valid_o = !flush_i && !selective_kill_valid_i &&
        (grant_hold_q ? grant1_hold_q : issue1_found_c);
    assign issue2_pair_valid_o = !flush_i && !selective_kill_valid_i &&
        (grant_hold_q ? grant1_hold_q : (issue_found_c && issue1_found_c));
    assign issue2_pair_is_alu_lsu_o =
        issue2_pair_valid_o && legal_alu_lsu_pair(issue_uop_o, issue1_uop_o);
    assign issue2_pair_is_alu_alu_o =
        issue2_pair_valid_o && legal_alu_alu_pair(issue_uop_o, issue1_uop_o);
    assign issue2_pair_legal_o =
        issue2_pair_valid_o && legal_issue2_pair(issue_uop_o, issue1_uop_o);
    assign issue_same_cycle_wakeup_mask_o = {
        issue1_valid_o && entry_uses_same_cycle_wakeup(issue1_uop_o),
        issue_valid_o && entry_uses_same_cycle_wakeup(issue_uop_o)
    };
    // A visible pair is an atomic grant. Never retire lane0 alone because the
    // compacting queue would invalidate the held lane1 index.
    assign issue_fire_c =
        issue_valid_o && issue_ready_i && (!issue1_valid_o || issue1_ready_i);
    assign issue1_fire_c = issue1_valid_o && issue_ready_i && issue1_ready_i;
    assign debug_count_o = count_q;
    assign debug_ready_any_count_o = debug_ready_count_o;
    assign debug_issue_candidate_count_o = debug_ready_count_o;
    assign debug_issue_multi_candidate_o = (debug_ready_count_o >= IQ_COUNT_W'(2));
    assign debug_issue0_fire_o = issue_fire_c;
    assign debug_issue1_fire_o = issue1_fire_c;
    assign debug_issue2_fire_o = issue_fire_c && issue1_fire_c;
    assign debug_issue_from_dispatch_mask_o = grant_hold_q ? 2'b00 : {
        issue1_from_dispatch0_c || issue1_from_dispatch1_c,
        issue_from_dispatch0_c
    };
    assign debug_duplicate_issue_guard_o =
        issue2_pair_valid_o && !issue_from_dispatch0_c &&
        !issue1_from_dispatch0_c && !issue1_from_dispatch1_c &&
        (issue_idx_selected_c == issue1_idx_selected_c);

    always_comb begin
        selective_killed_count_o = '0;
        if (selective_kill_valid_i) begin
            for (int k = 0; k < IQ_DEPTH; k = k + 1) begin
                if (entry_q[k].valid && tag_killed(entry_q[k].rob_tag))
                    selective_killed_count_o = selective_killed_count_o + 4'd1;
            end
        end
    end

    always_ff @(posedge clk) begin
        integer i;

        if (reset || flush_i) begin
            count_q <= '0;
            grant_hold_q <= 1'b0;
            grant1_hold_q <= 1'b0;
            grant_idx_q <= '0;
            grant1_idx_q <= '0;
            grant_uop_q <= '0;
            grant1_uop_q <= '0;
            for (i = 0; i < IQ_DEPTH; i = i + 1) begin
                entry_q[i] <= '0;
            end
        end else begin
            bbus_ooo_alu_iq_uop_t next_entry [IQ_DEPTH-1:0];
            logic [IQ_COUNT_W-1:0] next_count;
            integer j;

            next_count = '0;

            if (selective_kill_valid_i) begin
                grant_hold_q <= 1'b0;
                grant1_hold_q <= 1'b0;
            end else if (grant_hold_q) begin
                if (issue_fire_c) begin
                    grant_hold_q <= 1'b0;
                    grant1_hold_q <= 1'b0;
                end
            end else if (!issue_from_dispatch0_c &&
                         !issue1_from_dispatch0_c &&
                         !issue1_from_dispatch1_c && issue_valid_o &&
                         (!issue_fire_c || (issue1_valid_o && !issue1_fire_c))) begin
                grant_hold_q <= 1'b1;
                grant1_hold_q <= issue1_valid_o;
                grant_idx_q <= issue_idx_c;
                grant1_idx_q <= issue1_idx_c;
                grant_uop_q <= issue_uop_o;
                grant1_uop_q <= issue1_uop_o;
                grant_uop_q.src1_ready <= 1'b1;
                grant_uop_q.src2_ready <= 1'b1;
                grant1_uop_q.src1_ready <= 1'b1;
                grant1_uop_q.src2_ready <= 1'b1;
            end
            for (i = 0; i < IQ_DEPTH; i = i + 1) begin
                next_entry[i] = '0;
            end

            for (i = 0; i < IQ_DEPTH; i = i + 1) begin
                if (entry_q[i].valid &&
                    !tag_killed(entry_q[i].rob_tag) &&
                    !(issue_fire_c && !issue_from_dispatch0_c &&
                      (IQ_IDX_W'(i) == issue_idx_selected_c)) &&
                    !(issue1_fire_c && !issue1_from_dispatch0_c &&
                      !issue1_from_dispatch1_c &&
                      (IQ_IDX_W'(i) == issue1_idx_selected_c))) begin
                    next_entry[next_count[IQ_IDX_W-1:0]] = entry_q[i];
                    if (wakeup_valid_i && (wakeup_phys_i != `BBUS_OOO_PHYS_ZERO)) begin
                        if (next_entry[next_count[IQ_IDX_W-1:0]].phys_rs1 == wakeup_phys_i) begin
                            next_entry[next_count[IQ_IDX_W-1:0]].src1_ready = 1'b1;
                        end
                        if (next_entry[next_count[IQ_IDX_W-1:0]].phys_rs2 == wakeup_phys_i) begin
                            next_entry[next_count[IQ_IDX_W-1:0]].src2_ready = 1'b1;
                        end
                    end
                    if (wakeup1_valid_i && (wakeup1_phys_i != `BBUS_OOO_PHYS_ZERO)) begin
                        if (next_entry[next_count[IQ_IDX_W-1:0]].phys_rs1 == wakeup1_phys_i) begin
                            next_entry[next_count[IQ_IDX_W-1:0]].src1_ready = 1'b1;
                        end
                        if (next_entry[next_count[IQ_IDX_W-1:0]].phys_rs2 == wakeup1_phys_i) begin
                            next_entry[next_count[IQ_IDX_W-1:0]].src2_ready = 1'b1;
                        end
                    end
                    next_count = next_count + IQ_COUNT_W'(1);
                end
            end

            if (dispatch0_fire_c &&
                !(issue_from_dispatch0_c && issue_fire_c) &&
                !(issue1_from_dispatch0_c && issue1_fire_c)) begin
                next_entry[next_count[IQ_IDX_W-1:0]] = dispatch_uop_i;
                next_entry[next_count[IQ_IDX_W-1:0]].valid = 1'b1;
                if (wakeup_valid_i && (wakeup_phys_i != `BBUS_OOO_PHYS_ZERO)) begin
                    if (next_entry[next_count[IQ_IDX_W-1:0]].phys_rs1 == wakeup_phys_i) begin
                        next_entry[next_count[IQ_IDX_W-1:0]].src1_ready = 1'b1;
                    end
                    if (next_entry[next_count[IQ_IDX_W-1:0]].phys_rs2 == wakeup_phys_i) begin
                        next_entry[next_count[IQ_IDX_W-1:0]].src2_ready = 1'b1;
                    end
                end
                if (wakeup1_valid_i && (wakeup1_phys_i != `BBUS_OOO_PHYS_ZERO)) begin
                    if (next_entry[next_count[IQ_IDX_W-1:0]].phys_rs1 == wakeup1_phys_i) begin
                        next_entry[next_count[IQ_IDX_W-1:0]].src1_ready = 1'b1;
                    end
                    if (next_entry[next_count[IQ_IDX_W-1:0]].phys_rs2 == wakeup1_phys_i) begin
                        next_entry[next_count[IQ_IDX_W-1:0]].src2_ready = 1'b1;
                    end
                end
                next_count = next_count + IQ_COUNT_W'(1);
            end

            if (dispatch1_fire_c &&
                !(issue1_from_dispatch1_c && issue1_fire_c)) begin
                next_entry[next_count[IQ_IDX_W-1:0]] = dispatch1_uop_i;
                next_entry[next_count[IQ_IDX_W-1:0]].valid = 1'b1;
                if (wakeup_valid_i && (wakeup_phys_i != `BBUS_OOO_PHYS_ZERO)) begin
                    if (next_entry[next_count[IQ_IDX_W-1:0]].phys_rs1 == wakeup_phys_i) begin
                        next_entry[next_count[IQ_IDX_W-1:0]].src1_ready = 1'b1;
                    end
                    if (next_entry[next_count[IQ_IDX_W-1:0]].phys_rs2 == wakeup_phys_i) begin
                        next_entry[next_count[IQ_IDX_W-1:0]].src2_ready = 1'b1;
                    end
                end
                if (wakeup1_valid_i && (wakeup1_phys_i != `BBUS_OOO_PHYS_ZERO)) begin
                    if (next_entry[next_count[IQ_IDX_W-1:0]].phys_rs1 == wakeup1_phys_i) begin
                        next_entry[next_count[IQ_IDX_W-1:0]].src1_ready = 1'b1;
                    end
                    if (next_entry[next_count[IQ_IDX_W-1:0]].phys_rs2 == wakeup1_phys_i) begin
                        next_entry[next_count[IQ_IDX_W-1:0]].src2_ready = 1'b1;
                    end
                end
                next_count = next_count + IQ_COUNT_W'(1);
            end

            for (j = 0; j < IQ_DEPTH; j = j + 1) begin
                entry_q[j] <= next_entry[j];
            end
            count_q <= next_count;
        end
    end
endmodule
