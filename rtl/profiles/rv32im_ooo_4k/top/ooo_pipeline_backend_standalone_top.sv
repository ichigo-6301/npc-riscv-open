`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_pipeline_backend_standalone_top #(
    parameter bit PRECISE_STORE_BUFFER_ENABLE = 1'b0,
    parameter bit STORE_LOAD_FORWARDING_ENABLE = 1'b0,
    parameter bit RAW_COMPLETION_WAKEUP_ENABLE = 1'b0,
    parameter bit SAME_CYCLE_DEPENDENCY_FORWARDING_ENABLE = 1'b0,
    parameter bit HEAD_LOAD_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b0,
    parameter bit HEAD_ALU_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b0,
    parameter bit HEAD_BRU_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b0,
    parameter bit LOAD_RESPONSE_COMPLETION_BYPASS_ENABLE = 1'b0,
    parameter bit LSU_REQUEST_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit PAIR_RAW_TO_FINAL_BYPASS_ENABLE = 1'b0,
    parameter bit SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE = 1'b0,
    parameter bit SAME_CYCLE_DISPATCH_ISSUE_ENABLE = 1'b0,
    parameter bit SAME_CYCLE_BRANCH_DISPATCH_ISSUE_ENABLE = 1'b0,
    parameter bit BRANCH_ORDINARY_CONCURRENT_ISSUE_ENABLE = 1'b0,
    parameter bit BRANCH_YOUNGER_ORDINARY_CONCURRENT_ISSUE_ENABLE = 1'b0,
    parameter bit REGISTERED_BRU_DISPATCH_ORDINARY_ISSUE2_ENABLE = 1'b0,
    parameter bit ISSUE_OPERAND_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit SLOT1_FINAL_WRITEBACK_COMMIT_BYPASS_ENABLE = 1'b0,
    parameter bit BRANCH_ISSUE_FINAL_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit REGISTERED_BRANCH_ISSUE_FINAL_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit STORE_ISSUE_FINAL_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit MDU_MUL_COMPLETION_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE = 1'b0,
    parameter bit POSTED_STORE_RESPONSE_PIPELINE_ENABLE = 1'b0,
    parameter bit DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE = 1'b0,
    parameter bit PRE_ARBITER_LOAD_HIT_ORACLE_ENABLE = 1'b0,
    parameter bit LOAD_TRANSACTION_DEPTH3_ENABLE = 1'b0,
    parameter bit CORRECT_BRANCH_DUAL_RETIRE_ENABLE = 1'b0,
    parameter bit YOUNGER_SLOT1_CONTROL_DUAL_RETIRE_ENABLE = 1'b0,
    parameter bit STRUCTURAL_THROUGHPUT_ORACLE_ENABLE = 1'b0
) (
    input logic clk, input logic reset, input logic flush_i,
    // P8 only: when set, BRU does not create the conservative all-dispatch
    // serial barrier. Other serializing classes remain blocking.
    input logic branch_nonblocking_i,
    input logic [1:0] dispatch_valid_mask_i,
    input bbus_ooo_renamed_uop_t dispatch_uop0_i,
    input bbus_ooo_renamed_uop_t dispatch_uop1_i,
    // Registered-state-only capacity preview for the P7 atomic rename shell.
    output logic [1:0] dispatch_capacity_count_o,
    output logic [1:0] dispatch_ready_mask_o,
    output logic [1:0] dispatch_accept_mask_o,
    output bbus_ooo_rob_tag_t dispatch_tag0_o,
    output bbus_ooo_rob_tag_t dispatch_tag1_o,
    output bbus_ooo_rob_tag_t dispatch_post_tail_tag_o,

    input logic selective_squash_valid_i,
    input bbus_ooo_rob_tag_t selective_squash_branch_tag_i,
    input bbus_ooo_rob_tag_t selective_squash_post_tail_tag_i,
    output logic selective_squash_ready_o,
    output logic selective_squash_fire_o,
    output logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_o,
    output logic [`BBUS_OOO_PHYS_REGS-1:0] selective_killed_phys_mask_o,
    output logic [3:0] selective_killed_count_o,
    output logic selective_squash_identity_error_o,

    output logic mem_req_valid_o, input logic mem_req_ready_i,
    output logic mem_req_write_o, output logic [31:0] mem_req_addr_o,
    output logic [31:0] mem_req_wdata_o, output logic [3:0] mem_req_wstrb_o,
    output logic [2:0] mem_req_len_o, output logic [1:0] mem_req_access_o,
    output bbus_ooo_mem_token_t mem_req_token_o,
    input logic mem_rsp_valid_i, output logic mem_rsp_ready_o,
    input logic [31:0] mem_rsp_rdata_i, input logic mem_rsp_error_i,
    input logic mem_rsp_page_fault_i,
    input bbus_ooo_mem_token_t mem_rsp_token_i,

    output logic serial_issue_valid_o, input logic serial_issue_ready_i,
    output bbus_ooo_alu_iq_uop_t serial_issue_uop_o,
    output logic [31:0] serial_issue_src1_o,
    output logic [31:0] serial_issue_src2_o,
    output logic [2:0] serial_issue_kind_o,
    output logic serial_issue_from_dispatch_o,
    input logic serial_completion_valid_i,
    output logic serial_completion_ready_o,
    input bbus_ooo_writeback_t serial_completion_wb_i,
    input logic [2:0] serial_completion_kind_i,

    input logic commit_enable_i,
    output bbus_ooo_commit_event_t commit_event_o,
    output logic serial_barrier_o,
    output logic memory_dispatch_barrier_o,
    output logic [3:0] rob_count_o,
    output logic [3:0] iq_count_o,
    output logic [1:0] final_consume_mask_o,
    output bbus_ooo_writeback_t final_wb0_o,
    output bbus_ooo_writeback_t final_wb1_o,
    output logic [1:0] ordinary_wakeup_mask_o,
    output bbus_ooo_phys_reg_t ordinary_wakeup_phys0_o,
    output bbus_ooo_phys_reg_t ordinary_wakeup_phys1_o,
    output logic [1:0] same_cycle_dependency_issue_mask_o,
    output logic backend_busy_o,
    output logic atomic_recovery_block_o,
    output logic atomic_occupied_o,
    output logic [1:0] perf_issue_width_o,
    output logic [3:0] perf_issue_reason0_o,
    output logic [3:0] perf_issue_reason1_o,
    output logic [3:0] perf_commit_reason0_o,
    output logic [3:0] perf_commit_reason1_o,
    output logic [1:0] perf_branch_iq_ready_count_o,
    output logic [63:0] perf_events_o,
    output logic [7:0] perf_mixed_source_o,
    output logic [63:0] perf_structural_oracle_o,
    output logic [63:0] perf_structural_meta_o,
    output logic [63:0] perf_accounting_raw_o,
    output logic [10:0] perf_store_buffer_o,
    output logic [2:0] perf_branch_pair_o,
    output logic [17:0] perf_operand_stage_o,
    output logic [63:0] perf_lifecycle_o,
    output logic [63:0] perf_branch_operand_o,
    output logic [63:0] perf_branch_producer_phase_o,
    output logic [155:0] perf_lsu_causality_o,
    output logic [31:0] perf_store_admission_o,
    output logic [63:0] perf_issue_dependency_o,
    output logic [31:0] perf_retirement_chain_o,
    output logic [63:0] perf_complex_retire_pairing_o,
    output logic [63:0] perf_completion_ownership_o,
    output logic conservation_error_o
);
    localparam logic [2:0] SK_BRU=0, SK_LSU=1, SK_CSR=2, SK_SYS=3, SK_MDU=4;
    logic [1:0] rob_slots, rob_alloc_valid, rob_alloc_fire;
    bbus_ooo_rob_tag_t rob_tag0,rob_tag1;
    bbus_ooo_rob_alloc_t ra0,ra1;
    bbus_ooo_alu_iq_uop_t du0,du1,ou0,ou1,iu0,iu1;
    bbus_ooo_alu_iq_uop_t stage_in_uop0_c, stage_in_uop1_c;
    logic [1:0] iq_ready_count,iq_fire;
    logic iq_dispatch_r0,iq_dispatch_r1,issue_ready0,issue_ready1,iv0,iv1;
    logic pair_valid,pair_al,pair_aa,pair_legal;
    logic [1:0] iq_issue_from_dispatch;
    logic [63:0] iq_structural_oracle;
    logic [47:0] iq_structural_meta;
    logic [3:0] structural_dispatch_reason0;
    logic [3:0] structural_dispatch_reason1;
    logic iq_mixed_source_valid;
    logic [2:0] iq_mixed_source_reason;
    logic [2:0] perf_mixed_source_reason;
    logic [1:0] iq_mixed_source_pair_kind;
    logic [1:0] stage_in_mask,stage_in_ready,stage_in_accept,stage_out_mask,route_ready,stage_fire;
    logic [1:0] stage_fallthrough_eligible;
    logic [1:0] stage_fallthrough_ready;
    logic [1:0] stage_direct_fire;
    logic stage_full, stage_pair_held;
    logic lsu_iq_available;
    bbus_ooo_alu_iq_uop_t su0,su1;
    logic [31:0] prf_a0,prf_b0,prf_a1,prf_b1,sa0,sb0,sa1,sb1;
    logic [31:0] issue_a0_c, issue_b0_c, issue_a1_c, issue_b1_c;
    logic [31:0] stage_in_src10_c, stage_in_src20_c;
    logic [31:0] stage_in_src11_c, stage_in_src21_c;
    logic a0v,a1v,lsuv,a0r,a1r,lsur,a0acc,a1acc;
    bbus_ooo_alu_iq_uop_t a0u,a1u,lsuu;
    logic [31:0] a0a,a0b,a1a,a1b,lsua,lsub;
    bbus_ooo_writeback_t aw0,aw1,lw,xw,fw0,fw1;
    logic aw0v,aw1v,lwv,xwv;
    logic [2:0] paccept, pdrop, pclear;
    logic [5:0] saccept, sclear;
    logic [8:0] accounting_raw_accept_mask;
    logic [3:0] accounting_raw_fu [8:0];
    logic [1:0] fvalid,fconsume,fdrop,fwake;
    bbus_ooo_phys_reg_t wake0,wake1;
    logic [1:0] effective_write_mask;
    bbus_ooo_writeback_t effective_write_wb0, effective_write_wb1;
    logic [2:0] early_source_mask;
    logic [1:0] final_write_suppress_mask;
    logic [3:0] early_marker_count;
    logic raw_wakeup_ce;
    logic probe0,probe1,wbacc0,wbacc1;
    logic serial_pending_q; bbus_ooo_rob_tag_t serial_tag_q;
    logic [`BBUS_OOO_ROB_ENTRIES-1:0] store_pending_mask_q;
    logic [`BBUS_OOO_ROB_ENTRIES-1:0] store_pending_mask_next_c;
    logic memory_dispatch_barrier_c;
    logic issue0_serial, issue0_ordinary, issue1_ordinary;
    logic issue0_store, serial_issue_fire;
    logic branch_ordinary_pair_c, branch_lane1_c;
    logic branch_ordinary_pair_accept_c;
    logic branch_ordinary_pair_protocol_error_c;
    logic stage_direct_protocol_error_c;
    logic commit_serial_match;
    logic commit_store_valid,commit_store_ready,commit_store_done;
    logic commit_store_done_match,commit_store_done_drop,commit_store_done_clear;
    logic commit_store_fault,commit_store_fault_match;
    logic commit_store_fault_drop,commit_store_fault_clear;
    bbus_ooo_rob_tag_t commit_store_tag,commit_store_done_tag;
    bbus_ooo_rob_tag_t commit_store_fault_tag;
    logic [31:0] commit_store_fault_tval;
    logic [31:0] cs_addr,cs_data; logic [3:0] cs_strb; logic [2:0] cs_len;
    logic lsu_occ,lsu_load_out,lsu_load_occupied,lsu_store_out,lsu_ce,fabric_ce;
    logic [2:0] lsu_store_buffer_count;
    logic lsu_store_buffer_enq, lsu_store_buffer_ack;
    logic lsu_store_buffer_full, lsu_store_buffer_req, lsu_store_buffer_rsp;
    logic lsu_store_response_owner, lsu_store_request_release;
    logic lsu_store_buffer_busy;
    logic lsu_store_load_forward, lsu_store_load_disjoint;
    logic lsu_store_load_blocked;
    logic [2:0] lsu_store_block_reason;
    logic [2:0] lsu_store_service_phase;
    logic [29:0] lsu_store_admission;
    logic lsu_load_response_match, lsu_load_response_live;
    logic lsu_pre_arbiter_load_offer_valid;
    logic [1:0] lsu_pre_arbiter_load_offer_source;
    logic [31:0] lsu_pre_arbiter_load_offer_addr;
    logic [2:0] lsu_pre_arbiter_load_offer_len;
    bbus_ooo_mem_token_t lsu_pre_arbiter_load_offer_token;
    logic lsu_pre_arbiter_load_response_ready;
    logic selective_unused_lsu_drop;
    logic [4:0] ext_serial_valid;
    bbus_ooo_writeback_t serial_wb [4:0];
    logic [4:0] serial_match;
    logic [8:0] raw_probe_valid_mask;
    bbus_ooo_writeback_t raw_probe_wb [8:0];
    logic [8:0] raw_probe_fresh_mask;
    logic [1:0] candidate_mask;
    bbus_ooo_rob_idx_t rob_head;
    bbus_ooo_rob_tag_t rob_head_tag;
    logic issue0_atomic, atomic_issue_ready, atomic_issue_accept, atomic_available;
    logic atomic_completion_valid, atomic_occupied, atomic_lock;
    logic atomic_write_fire, atomic_recovery_block, atomic_drop_wait;
    logic atomic_illegal, atomic_flush_drop, atomic_flush_error, atomic_ce;
    logic atomic_reservation_valid, atomic_sc_success, atomic_sc_failure;
    logic [31:0] atomic_reservation_addr;
    logic reservation_invalidate;
    bbus_ooo_writeback_t atomic_wb;
    logic atomic_commit_valid;
    bbus_ooo_rob_tag_t atomic_commit_tag;
    logic lsu_mem_req_valid,lsu_mem_req_ready,lsu_mem_req_write;
    logic [31:0] lsu_mem_req_addr,lsu_mem_req_wdata;
    logic [3:0] lsu_mem_req_wstrb; logic [2:0] lsu_mem_req_len;
    logic lsu_mem_rsp_valid,lsu_mem_rsp_ready;
    logic [31:0] lsu_mem_rsp_rdata; logic lsu_mem_rsp_error,lsu_mem_rsp_page_fault;
    bbus_ooo_mem_token_t lsu_mem_req_token,lsu_mem_rsp_token;
    logic lsu_store_relaxed;
    logic atomic_mem_req_valid,atomic_mem_req_ready,atomic_mem_req_write;
    logic [31:0] atomic_mem_req_addr,atomic_mem_req_wdata;
    logic [1:0] atomic_mem_req_access;
    logic [3:0] atomic_mem_req_wstrb; logic [2:0] atomic_mem_req_len;
    logic atomic_mem_rsp_valid,atomic_mem_rsp_ready;
    logic [31:0] atomic_mem_rsp_rdata; logic atomic_mem_rsp_error,atomic_mem_rsp_page_fault;
    bbus_ooo_mem_token_t atomic_mem_req_token,atomic_mem_rsp_token;
    logic [1:0] mem_owner;
    logic mem_collision,mem_partial,mem_ce;
    logic [1:0] mem_load_outstanding_count;
    logic mem_exclusive_active,mem_third_load_backpressure;
    logic mem_unknown_response,mem_duplicate_request;
    logic [15:0] mem_load_turnover;
    logic [3:0] iq_ready_total;
    logic [3:0] selective_unused_iq_killed_count;
    logic [1:0] selective_unused_stage_drop;
    logic selective_unused_alu0_drop, selective_unused_alu1_drop;
    logic [3:0] iq_ready_alu;
    logic [3:0] iq_ready_lsu;
    logic [3:0] iq_ready_bru;
    logic [3:0] iq_ready_csr_sys;
    logic [3:0] iq_ready_any;
    logic [3:0] iq_issue_candidates;
    logic [41:0] iq_branch_operand;
    logic [63:0] iq_dependency_operand;
    logic [6:0] iq_retirement_head;
    logic [1:0] iq_branch_no_older_ready;
    logic [5:0] iq_branch_pred_source;
    logic [1:0] iq_branch_pred_correlated;
    logic [15:0] lsu_branch_producer_phase;
    logic iq_multi_candidate;
    logic [1:0] iq_same_cycle_wakeup_mask;
    logic [3:0] rob_commit_reason0;
    logic [3:0] rob_commit_reason1;
    logic [18:0] rob_slot1_bypass_oracle;
    logic [63:0] rob_complex_retire_pairing;
    logic issue_fire0, issue_fire1;

    function automatic logic is_serial(input bbus_ooo_renamed_uop_t u);
        is_serial=u.is_store||u.is_csr||u.is_system||u.exception.valid||
          (u.fu_type==BBUS_OOO_FU_BRU)||(u.fu_type==BBUS_OOO_FU_MDU)||
          (u.fu_type==BBUS_OOO_FU_AMO);
    endfunction
    function automatic logic serial_blocks_dispatch(input bbus_ooo_renamed_uop_t u);
        begin
            serial_blocks_dispatch = is_serial(u) && !u.is_store &&
                !(branch_nonblocking_i && (u.fu_type == BBUS_OOO_FU_BRU));
        end
    endfunction
    function automatic logic is_memory(input bbus_ooo_renamed_uop_t u);
        is_memory = u.is_load || u.is_store || (u.fu_type == BBUS_OOO_FU_AMO);
    endfunction
    function automatic logic operand_ordinary_alu(
        input bbus_ooo_alu_iq_uop_t u
    );
        operand_ordinary_alu =
            ((u.fu_type == BBUS_OOO_FU_ALU) ||
             (u.fu_type == BBUS_OOO_FU_NONE)) &&
            !u.is_load && !u.is_store && !u.is_csr && !u.is_system;
    endfunction
    function automatic logic operand_ordinary_load(
        input bbus_ooo_alu_iq_uop_t u
    );
        operand_ordinary_load =
            (u.fu_type == BBUS_OOO_FU_LSU) && u.is_load &&
            !u.is_store && !u.is_csr && !u.is_system;
    endfunction
    function automatic bbus_ooo_rob_alloc_t to_alloc(input bbus_ooo_renamed_uop_t u);
        bbus_ooo_rob_alloc_t x; begin x='0;x.valid=u.valid;x.pc=u.pc;x.instr=u.instr;
        x.arch_rd=u.arch_rd;x.phys_rd_new=u.phys_rd_new;x.phys_rd_old=u.phys_rd_old;x.rf_wen=u.rf_wen;
        x.fu_type=u.fu_type;x.branch_op=u.branch_op;x.is_load=u.is_load;x.is_store=u.is_store;
        x.is_ebreak=u.is_ebreak;x.is_csr=u.is_csr;x.is_system=u.is_system;x.csr_addr=u.csr_addr;
        x.mem_op=u.mem_op;x.exception=u.exception;to_alloc=x;end
    endfunction
    function automatic bbus_ooo_alu_iq_uop_t to_iq(input bbus_ooo_renamed_uop_t u,input bbus_ooo_rob_tag_t t);
        bbus_ooo_alu_iq_uop_t x; begin x='0;x.valid=u.valid;x.rob_tag=t;x.pc=u.pc;x.instr=u.instr;
        x.arch_rd=u.arch_rd;x.phys_rs1=u.phys_rs1;x.phys_rs2=u.phys_rs2;x.phys_rd_new=u.phys_rd_new;
        x.rf_wen=u.rf_wen;x.fu_type=u.fu_type;x.branch_op=u.branch_op;x.pred_taken=u.pred_taken;x.pred_target=u.pred_target;x.pred_source=u.pred_source;x.pred_correlated=u.pred_correlated;x.pred_base_taken=u.pred_base_taken;x.pred_base_counter_valid=u.pred_base_counter_valid;x.pred_base_counter_taken=u.pred_base_counter_taken;x.pred_corr_candidate=u.pred_corr_candidate;x.pred_corr_raw_candidate=u.pred_corr_raw_candidate;x.pred_corr_chooser_prefer=u.pred_corr_chooser_prefer;x.pred_corr_taken=u.pred_corr_taken;x.pred_history=u.pred_history;x.pred_local_history=u.pred_local_history;x.pred_local_strong=u.pred_local_strong;x.pred_local_taken=u.pred_local_taken;x.pred_local_chooser_prefer=u.pred_local_chooser_prefer;x.pred_local_chooser_strong=u.pred_local_chooser_strong;x.pred_multihistory_hit=u.pred_multihistory_hit;x.pred_multihistory_strong=u.pred_multihistory_strong;x.pred_multihistory_taken=u.pred_multihistory_taken;x.pred_multihistory_chooser_prefer=u.pred_multihistory_chooser_prefer;x.pred_multihistory_chooser_strong=u.pred_multihistory_chooser_strong;x.pred_ras_self_collision=u.pred_ras_self_collision;x.alu_op=u.alu_op;x.mdu_op=u.mdu_op;
        x.atomic_op=u.atomic_op;x.aq=u.aq;x.rl=u.rl;
        x.is_load=u.is_load;x.is_store=u.is_store;x.mem_op=u.mem_op;x.src1_is_pc=u.src1_is_pc;
        x.src2_is_imm=u.src2_is_imm;x.imm=u.imm;x.is_csr=u.is_csr;x.is_system=u.is_system;
        x.csr_addr=u.csr_addr;x.src1_ready=u.src1_ready;x.src2_ready=u.src2_ready;x.exception=u.exception;to_iq=x;end
    endfunction

    function automatic logic [31:0] forwarded_prf_data(
        input bbus_ooo_phys_reg_t phys,
        input logic [31:0] registered_data
    );
        begin
            forwarded_prf_data = registered_data;
            if (SAME_CYCLE_DEPENDENCY_FORWARDING_ENABLE &&
                effective_write_mask[0] &&
                (phys != `BBUS_OOO_PHYS_ZERO) &&
                (effective_write_wb0.phys_rd == phys))
                forwarded_prf_data = effective_write_wb0.result;
            else if (SAME_CYCLE_DEPENDENCY_FORWARDING_ENABLE &&
                     effective_write_mask[1] &&
                     (phys != `BBUS_OOO_PHYS_ZERO) &&
                     (effective_write_wb1.phys_rd == phys))
                forwarded_prf_data = effective_write_wb1.result;
        end
    endfunction

    always_comb begin
        dispatch_capacity_count_o = 2'b00;
        if (!flush_i && !serial_pending_q) begin
            if ((rob_slots >= 2'd2) && (iq_ready_count >= 2'd2)) begin
                dispatch_capacity_count_o = 2'd2;
            end else if ((rob_slots >= 2'd1) && (iq_ready_count >= 2'd1)) begin
                dispatch_capacity_count_o = 2'd1;
            end
        end
    end
    assign dispatch_tag0_o = rob_tag0;
    assign dispatch_tag1_o = rob_tag1;

    always_comb begin
        candidate_mask=0;
        if(!flush_i && !serial_pending_q && dispatch_valid_mask_i[0] &&
           !(memory_dispatch_barrier_c && is_memory(dispatch_uop0_i) &&
             (!PRECISE_STORE_BUFFER_ENABLE || !dispatch_uop0_i.is_store)) &&
           (dispatch_capacity_count_o >= 2'd1)) candidate_mask[0]=1;
        // The frozen S8 machine has one LSU issue port. Never admit a pair
        // that P3 cannot route atomically; retain the younger load upstream.
        if(candidate_mask[0] && dispatch_valid_mask_i[1] && !is_serial(dispatch_uop0_i) &&
           !dispatch_uop1_i.is_store &&
           !((memory_dispatch_barrier_c || dispatch_uop0_i.is_store) &&
             is_memory(dispatch_uop1_i)) &&
           !((dispatch_uop0_i.is_load && !dispatch_uop0_i.is_store) &&
             (dispatch_uop1_i.is_load && !dispatch_uop1_i.is_store)) &&
           (dispatch_capacity_count_o >= 2'd2)) candidate_mask[1]=1;
        dispatch_ready_mask_o=candidate_mask;
        rob_alloc_valid=candidate_mask;
        ra0=to_alloc(dispatch_uop0_i);ra1=to_alloc(dispatch_uop1_i);
        du0=to_iq(dispatch_uop0_i,rob_tag0);du1=to_iq(dispatch_uop1_i,rob_tag1);
        ou0=to_iq(dispatch_uop0_i,rob_tag0);ou1=to_iq(dispatch_uop1_i,rob_tag1);
        du0.valid=rob_alloc_fire[0];du1.valid=rob_alloc_fire[1];
        ou0.valid=dispatch_valid_mask_i[0];ou1.valid=dispatch_valid_mask_i[1];
        dispatch_accept_mask_o=rob_alloc_fire;
    end

    always_comb begin
      structural_dispatch_reason0 = 4'd0;
      structural_dispatch_reason1 = 4'd0;
      if (!rob_alloc_fire[0]) begin
        if (!dispatch_valid_mask_i[0]) structural_dispatch_reason0 = 4'd1;
        else if (flush_i || selective_squash_valid_i) structural_dispatch_reason0 = 4'd2;
        else if (serial_pending_q || atomic_occupied) structural_dispatch_reason0 = 4'd3;
        else if (memory_dispatch_barrier_c && is_memory(dispatch_uop0_i) &&
                 (!PRECISE_STORE_BUFFER_ENABLE || !dispatch_uop0_i.is_store))
          structural_dispatch_reason0 = 4'd4;
        else if (rob_slots == 0) structural_dispatch_reason0 = 4'd5;
        else if (iq_ready_count == 0) structural_dispatch_reason0 = 4'd6;
        else structural_dispatch_reason0 = 4'd11;
      end
      if (!rob_alloc_fire[1]) begin
        if (!dispatch_valid_mask_i[1]) structural_dispatch_reason1 = 4'd1;
        else if (!candidate_mask[0])
          structural_dispatch_reason1 = structural_dispatch_reason0;
        else if (is_serial(dispatch_uop0_i)) structural_dispatch_reason1 = 4'd8;
        else if (dispatch_uop1_i.is_store) structural_dispatch_reason1 = 4'd9;
        else if ((memory_dispatch_barrier_c || dispatch_uop0_i.is_store) &&
                 is_memory(dispatch_uop1_i)) structural_dispatch_reason1 = 4'd4;
        else if (dispatch_uop0_i.is_load && !dispatch_uop0_i.is_store &&
                 dispatch_uop1_i.is_load && !dispatch_uop1_i.is_store)
          structural_dispatch_reason1 = 4'd10;
        else if (rob_slots < 2) structural_dispatch_reason1 = 4'd5;
        else if (iq_ready_count < 2) structural_dispatch_reason1 = 4'd6;
        else structural_dispatch_reason1 = 4'd11;
      end
    end
    always_comb begin
      // Counterfactual ready for an empty operand stage.  This mirrors the
      // production router topology but never feeds real Issue acceptance.
      stage_fallthrough_ready = 2'b00;
      unique case (stage_in_mask)
        2'b01: begin
          if (operand_ordinary_alu(stage_in_uop0_c) && (a0r || a1r))
            stage_fallthrough_ready = 2'b01;
          else if (operand_ordinary_load(stage_in_uop0_c) && lsur)
            stage_fallthrough_ready = 2'b01;
        end
        2'b11: begin
          if (operand_ordinary_alu(stage_in_uop0_c) &&
              operand_ordinary_alu(stage_in_uop1_c) && a0r && a1r)
            stage_fallthrough_ready = 2'b11;
          else if (((operand_ordinary_alu(stage_in_uop0_c) &&
                     operand_ordinary_load(stage_in_uop1_c)) ||
                    (operand_ordinary_load(stage_in_uop0_c) &&
                     operand_ordinary_alu(stage_in_uop1_c))) &&
                   lsur && (a0r || a1r))
            stage_fallthrough_ready = 2'b11;
        end
        default: stage_fallthrough_ready = 2'b00;
      endcase
    end

    small_rob #(.COMMIT_STORE_TAG_CHECK_ENABLE(1'b1),
      .EARLY_TERMINAL_DONE_ENABLE(1'b0),
      .PRECISE_STORE_ACCEPT_RETIRE_ENABLE(PRECISE_STORE_BUFFER_ENABLE),
      .HEAD_LOAD_WRITEBACK_COMMIT_BYPASS_ENABLE(
        HEAD_LOAD_WRITEBACK_COMMIT_BYPASS_ENABLE),
      .HEAD_ALU_WRITEBACK_COMMIT_BYPASS_ENABLE(
        HEAD_ALU_WRITEBACK_COMMIT_BYPASS_ENABLE),
      .HEAD_BRU_WRITEBACK_COMMIT_BYPASS_ENABLE(
        HEAD_BRU_WRITEBACK_COMMIT_BYPASS_ENABLE),
      .SLOT1_FINAL_WRITEBACK_COMMIT_BYPASS_ENABLE(
        SLOT1_FINAL_WRITEBACK_COMMIT_BYPASS_ENABLE),
      .CORRECT_BRANCH_DUAL_RETIRE_ENABLE(
        CORRECT_BRANCH_DUAL_RETIRE_ENABLE),
      .YOUNGER_SLOT1_CONTROL_DUAL_RETIRE_ENABLE(
        YOUNGER_SLOT1_CONTROL_DUAL_RETIRE_ENABLE))
    u_rob(.clk(clk),.reset(reset),.flush_i(flush_i),.alloc_valid_mask_i(rob_alloc_valid),.alloc_slot0_i(ra0),.alloc_slot1_i(ra1),
      .alloc_fire_mask_o(rob_alloc_fire),.alloc_tag0_o(rob_tag0),.alloc_tag1_o(rob_tag1),
      .alloc_post_tail_tag_o(dispatch_post_tail_tag_o),.available_slots_o(rob_slots),
      .selective_squash_valid_i(selective_squash_valid_i),.selective_squash_branch_tag_i(selective_squash_branch_tag_i),
      .selective_squash_post_tail_tag_i(selective_squash_post_tail_tag_i),.selective_squash_ready_o(selective_squash_ready_o),
      .selective_squash_fire_o(selective_squash_fire_o),.selective_killed_rob_mask_o(selective_killed_rob_mask_o),
      .selective_killed_phys_mask_o(selective_killed_phys_mask_o),.selective_killed_count_o(selective_killed_count_o),
      .selective_squash_identity_error_o(selective_squash_identity_error_o),
      .writeback_i(fw0),.writeback_accepted_o(wbacc0),.writeback1_i(fw1),.writeback1_accepted_o(wbacc1),
      .writeback_probe0_i(fw0),.writeback_probe1_i(fw1),.writeback_probe0_match_o(probe0),.writeback_probe1_match_o(probe1),
      .raw_probe_valid_mask_i(raw_probe_valid_mask),.raw_probe_wb_i(raw_probe_wb),.raw_probe_fresh_mask_o(raw_probe_fresh_mask),
      .commit_enable_i(commit_enable_i),.commit_store_valid_o(commit_store_valid),.commit_store_ready_i(commit_store_ready),
      .commit_store_accept_is_done_i(lsu_store_buffer_enq),
      .commit_store_done_i(commit_store_done),.commit_store_rob_tag_o(commit_store_tag),.commit_store_done_rob_tag_i(commit_store_done_tag),
      .commit_store_done_match_o(commit_store_done_match),.commit_store_done_drop_o(commit_store_done_drop),.commit_store_done_clear_o(commit_store_done_clear),
      .commit_store_fault_i(commit_store_fault),.commit_store_fault_rob_tag_i(commit_store_fault_tag),
      .commit_store_fault_tval_i(commit_store_fault_tval),.commit_store_fault_match_o(commit_store_fault_match),
      .commit_store_fault_drop_o(commit_store_fault_drop),.commit_store_fault_clear_o(commit_store_fault_clear),
      .commit_store_addr_o(cs_addr),.commit_store_wdata_o(cs_data),
      .commit_store_wstrb_o(cs_strb),.commit_store_len_o(cs_len),.commit_event_o(commit_event_o),
      .perf_commit_reason0_o(rob_commit_reason0),.perf_commit_reason1_o(rob_commit_reason1),
      .perf_slot1_bypass_oracle_o(rob_slot1_bypass_oracle),
      .perf_complex_retire_pairing_o(rob_complex_retire_pairing),
      .debug_rob_count_o(rob_count_o),.debug_rob_head_o(rob_head),.rob_head_tag_o(rob_head_tag));

    // IQ owns a serial grant until the external FU actually accepts it. Do
    // not use external ready as issue eligibility: valid/uop must stay stable
    // during serial-FU backpressure.
    alu_issue_queue_1w #(
      .SAME_CYCLE_WAKEUP_ENABLE(
        SAME_CYCLE_DEPENDENCY_FORWARDING_ENABLE),
      .SAME_CYCLE_DISPATCH_ISSUE_ENABLE(
        SAME_CYCLE_DISPATCH_ISSUE_ENABLE),
      .SAME_CYCLE_BRANCH_DISPATCH_ISSUE_ENABLE(
        SAME_CYCLE_BRANCH_DISPATCH_ISSUE_ENABLE),
      .BRANCH_ORDINARY_CONCURRENT_ISSUE_ENABLE(
        BRANCH_ORDINARY_CONCURRENT_ISSUE_ENABLE),
      .BRANCH_YOUNGER_ORDINARY_CONCURRENT_ISSUE_ENABLE(
        BRANCH_YOUNGER_ORDINARY_CONCURRENT_ISSUE_ENABLE),
        .REGISTERED_BRU_DISPATCH_ORDINARY_ISSUE2_ENABLE(
            REGISTERED_BRU_DISPATCH_ORDINARY_ISSUE2_ENABLE),
      .PRECISE_STORE_BUFFER_ENABLE(PRECISE_STORE_BUFFER_ENABLE),
      .STRUCTURAL_THROUGHPUT_ORACLE_ENABLE(
        STRUCTURAL_THROUGHPUT_ORACLE_ENABLE)
    ) u_iq(.clk(clk),.reset(reset),.flush_i(flush_i),.selective_kill_valid_i(selective_squash_fire_o),.selective_killed_rob_mask_i(selective_killed_rob_mask_o),.selective_killed_count_o(selective_unused_iq_killed_count),.rob_head_i(rob_head),.rob_head_tag_i(rob_head_tag),
      .alu0_available_i(a0r),.alu1_available_i(a1r),
      .lsu_available_i(lsu_iq_available),
      .bru_available_i(1'b1),.csr_sys_available_i(1'b1),.atomic_available_i(atomic_available),
      .dispatch_valid_i(du0.valid),.dispatch_uop_i(du0),.dispatch1_valid_i(du1.valid),.dispatch1_uop_i(du1),
      .oracle_offer_valid_mask_i(dispatch_valid_mask_i),
      .oracle_offer_uop0_i(ou0),.oracle_offer_uop1_i(ou1),
      .oracle_stage_ready_mask_i(stage_in_ready),
      .oracle_serial_ready_i(serial_issue_ready_i),
      .dispatch_ready_o(iq_dispatch_r0),.dispatch1_ready_o(iq_dispatch_r1),.dispatch_ready_count_o(iq_ready_count),.dispatch_fire_mask_o(iq_fire),
      .wakeup_valid_i(effective_write_mask[0]),.wakeup_phys_i(effective_write_wb0.phys_rd),.wakeup1_valid_i(effective_write_mask[1]),.wakeup1_phys_i(effective_write_wb1.phys_rd),
      .issue_valid_o(iv0),.issue_uop_o(iu0),.issue_ready_i(issue_ready0),.issue1_valid_o(iv1),.issue1_uop_o(iu1),.issue1_ready_i(issue_ready1),
      .issue2_pair_valid_o(pair_valid),.issue2_pair_is_alu_lsu_o(pair_al),.issue2_pair_is_alu_alu_o(pair_aa),.issue2_pair_legal_o(pair_legal),
      .issue_same_cycle_wakeup_mask_o(iq_same_cycle_wakeup_mask),
      .debug_ready_count_o(iq_ready_total),.debug_ready_alu_count_o(iq_ready_alu),
      .debug_ready_lsu_count_o(iq_ready_lsu),.debug_ready_bru_count_o(iq_ready_bru),
      .debug_ready_csr_sys_count_o(iq_ready_csr_sys),.debug_ready_any_count_o(iq_ready_any),
      .debug_issue_candidate_count_o(iq_issue_candidates),.debug_bru_operand_o(iq_branch_operand),
      .debug_dependency_operand_o(iq_dependency_operand),
      .debug_retirement_head_o(iq_retirement_head),
      .debug_bru_no_older_ready_o(iq_branch_no_older_ready),
      .debug_bru_pred_source_o(iq_branch_pred_source),
      .debug_bru_pred_correlated_o(iq_branch_pred_correlated),
      .debug_issue_multi_candidate_o(iq_multi_candidate),
      .debug_issue_from_dispatch_mask_o(iq_issue_from_dispatch),
      .debug_mixed_source_valid_o(iq_mixed_source_valid),
      .debug_mixed_source_reason_o(iq_mixed_source_reason),
      .debug_mixed_source_pair_kind_o(iq_mixed_source_pair_kind),
      .debug_structural_oracle_o(iq_structural_oracle),
      .debug_structural_meta_o(iq_structural_meta),
      .debug_count_o(iq_count_o));

    assign perf_mixed_source_reason = !iq_mixed_source_valid ? 3'd0 :
      ((iq_mixed_source_reason == 3'd4) &&
       (!stage_in_ready[0] || !stage_in_ready[1])) ?
        3'd6 : iq_mixed_source_reason;
    assign perf_structural_oracle_o = iq_structural_oracle;
    assign perf_structural_meta_o = {
      serial_pending_q || atomic_occupied,
      memory_dispatch_barrier_c,
      structural_dispatch_reason1,
      structural_dispatch_reason0,
      rob_alloc_fire,
      candidate_mask,
      dispatch_valid_mask_i,
      iq_structural_meta
    };

    assign issue0_store=iv0&&iu0.is_store;
    assign issue0_atomic=iv0&&(iu0.fu_type==BBUS_OOO_FU_AMO);
    assign issue0_serial=iv0&&(iu0.is_store||iu0.is_csr||iu0.is_system||iu0.exception.valid||(iu0.fu_type==BBUS_OOO_FU_BRU)||(iu0.fu_type==BBUS_OOO_FU_MDU));
    assign issue0_ordinary = iv0 && !iu0.exception.valid &&
      (((iu0.fu_type == BBUS_OOO_FU_ALU) ||
        (iu0.fu_type == BBUS_OOO_FU_NONE)) &&
       !iu0.is_load && !iu0.is_store && !iu0.is_csr && !iu0.is_system ||
       ((iu0.fu_type == BBUS_OOO_FU_LSU) && iu0.is_load && !iu0.is_store));
    assign issue1_ordinary = iv1 && !iu1.exception.valid &&
      ((((iu1.fu_type == BBUS_OOO_FU_ALU) ||
         (iu1.fu_type == BBUS_OOO_FU_NONE)) &&
        !iu1.is_load && !iu1.is_store && !iu1.is_csr && !iu1.is_system) ||
       ((iu1.fu_type == BBUS_OOO_FU_LSU) && iu1.is_load && !iu1.is_store));
    assign branch_ordinary_pair_c =
      pair_valid && pair_legal &&
      ((BRANCH_ORDINARY_CONCURRENT_ISSUE_ENABLE && issue0_ordinary &&
        (iu1.fu_type == BBUS_OOO_FU_BRU) && !iu1.exception.valid) ||
       (BRANCH_YOUNGER_ORDINARY_CONCURRENT_ISSUE_ENABLE && issue1_ordinary &&
        (iu0.fu_type == BBUS_OOO_FU_BRU) && !iu0.exception.valid));
    assign branch_lane1_c = branch_ordinary_pair_c &&
      (iu1.fu_type == BBUS_OOO_FU_BRU);
    always_comb begin
      // Buffered-store AGU execution has no memory side effect.  It may run
      // while an older load is still owned; in-order ROB retirement prevents
      // the store from reaching the precise enqueue point before that load.
      // The legacy path retains its original whole-LSU drain requirement.
      stage_in_uop0_c = iu0;
      stage_in_uop1_c = iu1;
      stage_in_src10_c = iu0.src1_is_pc ? iu0.pc : issue_a0_c;
      stage_in_src20_c = (iu0.fu_type == BBUS_OOO_FU_LSU) ? issue_b0_c :
        (iu0.src2_is_imm ? iu0.imm : issue_b0_c);
      stage_in_src11_c = iu1.src1_is_pc ? iu1.pc : issue_a1_c;
      stage_in_src21_c = (iu1.fu_type == BBUS_OOO_FU_LSU) ? issue_b1_c :
        (iu1.src2_is_imm ? iu1.imm : issue_b1_c);

      serial_issue_uop_o = branch_lane1_c ? iu1 : iu0;
      serial_issue_src1_o = branch_lane1_c ?
        (iu1.src1_is_pc ? iu1.pc : issue_a1_c) :
        (iu0.src1_is_pc ? iu0.pc : issue_a0_c);
      serial_issue_src2_o = branch_lane1_c ?
        (iu1.src2_is_imm ? iu1.imm : issue_b1_c) :
        ((iu0.fu_type == BBUS_OOO_FU_LSU) ? issue_b0_c :
         (iu0.src2_is_imm ? iu0.imm : issue_b0_c));
      serial_issue_kind_o=SK_SYS;
      serial_issue_from_dispatch_o = 1'b0;
      if (branch_ordinary_pair_c) begin
        serial_issue_kind_o = SK_BRU;
        // The ordinary partner is compacted into elastic lane 0.  Gate each
        // destination valid with the other destination's readiness so the IQ
        // pair is consumed atomically and neither side can escape alone.
        if (branch_lane1_c) begin
          stage_in_uop0_c = iu0;
          stage_in_src10_c = iu0.src1_is_pc ? iu0.pc : issue_a0_c;
          stage_in_src20_c = (iu0.fu_type == BBUS_OOO_FU_LSU) ? issue_b0_c :
            (iu0.src2_is_imm ? iu0.imm : issue_b0_c);
        end else begin
          stage_in_uop0_c = iu1;
          stage_in_src10_c = iu1.src1_is_pc ? iu1.pc : issue_a1_c;
          stage_in_src20_c = (iu1.fu_type == BBUS_OOO_FU_LSU) ? issue_b1_c :
            (iu1.src2_is_imm ? iu1.imm : issue_b1_c);
        end
        stage_in_uop1_c = '0;
        stage_in_src11_c = '0;
        stage_in_src21_c = '0;
        stage_in_mask = serial_issue_ready_i ? 2'b01 : 2'b00;
        serial_issue_valid_o = stage_in_ready[0];
      end else begin
        serial_issue_valid_o=issue0_serial &&
          (!issue0_store || PRECISE_STORE_BUFFER_ENABLE || !lsu_occ);
        if(iu0.is_store||iu0.exception.valid)serial_issue_kind_o=SK_LSU;
        else if(iu0.fu_type==BBUS_OOO_FU_BRU)serial_issue_kind_o=SK_BRU;
        else if(iu0.is_csr)serial_issue_kind_o=SK_CSR;
        else if(iu0.fu_type==BBUS_OOO_FU_MDU)serial_issue_kind_o=SK_MDU;
        stage_in_mask=(issue0_serial||issue0_atomic)?0:{iv1,iv0};
      end
      if (REGISTERED_BRANCH_ISSUE_FINAL_FALLTHROUGH_ENABLE &&
          serial_issue_valid_o && (serial_issue_kind_o == SK_BRU))
        serial_issue_from_dispatch_o = branch_lane1_c ?
          iq_issue_from_dispatch[1] : iq_issue_from_dispatch[0];
    end
    assign serial_issue_fire = serial_issue_valid_o && serial_issue_ready_i;
    assign branch_ordinary_pair_accept_c = branch_ordinary_pair_c &&
      serial_issue_fire && stage_in_accept[0];
    assign branch_ordinary_pair_protocol_error_c = branch_ordinary_pair_c &&
      ((serial_issue_fire != stage_in_accept[0]) ||
       (issue_ready0 != issue_ready1) || stage_in_accept[1] ||
       (serial_issue_kind_o != SK_BRU));
    assign stage_direct_protocol_error_c =
      ((!ISSUE_OPERAND_FALLTHROUGH_ENABLE) && (|stage_direct_fire)) ||
      (ISSUE_OPERAND_FALLTHROUGH_ENABLE &&
       (stage_direct_fire != stage_fallthrough_eligible)) ||
      (|(stage_direct_fire & ~(stage_in_accept &
                              stage_fallthrough_eligible)));
    // D4 must first capture load operands before the LSU can compare the real
    // address against committed stores. The elastic stage then holds partial
    // overlaps until the buffer query becomes safe.
    assign lsu_iq_available = STORE_LOAD_FORWARDING_ENABLE ?
      stage_in_ready[0] : lsur;
    assign issue_ready0 = branch_ordinary_pair_c ?
      branch_ordinary_pair_accept_c :
      (issue0_atomic ? atomic_issue_accept :
       (issue0_serial ? serial_issue_fire : stage_in_accept[0]));
    assign issue_ready1 = branch_ordinary_pair_c ?
      branch_ordinary_pair_accept_c :
      ((issue0_serial||issue0_atomic) ? 1'b0 : stage_in_accept[1]);
    assign serial_match=raw_probe_fresh_mask[7:3];

    ooo_prf u_prf(.clk(clk),.reset(reset),.read_rs1_phys_i(iu0.phys_rs1),.read_rs2_phys_i(iu0.phys_rs2),
      .read_rs1_data_o(prf_a0),.read_rs2_data_o(prf_b0),.read1_rs1_phys_i(iu1.phys_rs1),.read1_rs2_phys_i(iu1.phys_rs2),
      .read1_rs1_data_o(prf_a1),.read1_rs2_data_o(prf_b1),.write_valid_i(effective_write_mask[0]),.write_phys_i(effective_write_wb0.phys_rd),.write_data_i(effective_write_wb0.result),
      .write1_valid_i(effective_write_mask[1]),.write1_phys_i(effective_write_wb1.phys_rd),.write1_data_i(effective_write_wb1.result));
    always_comb begin
      issue_a0_c=forwarded_prf_data(iu0.phys_rs1,prf_a0);
      issue_b0_c=forwarded_prf_data(iu0.phys_rs2,prf_b0);
      issue_a1_c=forwarded_prf_data(iu1.phys_rs1,prf_a1);
      issue_b1_c=forwarded_prf_data(iu1.phys_rs2,prf_b1);
    end
    ooo_issue_operand_elastic_2w #(
      .FALLTHROUGH_ENABLE(ISSUE_OPERAND_FALLTHROUGH_ENABLE)
    ) u_stage(.clk(clk),.reset(reset),.flush_i(flush_i),.selective_kill_valid_i(selective_squash_fire_o),.selective_killed_rob_mask_i(selective_killed_rob_mask_o),.in_valid_mask_i(stage_in_mask),.in_uop0_i(stage_in_uop0_c),.in_uop1_i(stage_in_uop1_c),
      .in_src10_i(stage_in_src10_c),.in_src20_i(stage_in_src20_c),
      .in_src11_i(stage_in_src11_c),.in_src21_i(stage_in_src21_c),.in_ready_mask_o(stage_in_ready),.in_accept_mask_o(stage_in_accept),
      .out_valid_mask_o(stage_out_mask),.out_uop0_o(su0),.out_uop1_o(su1),.out_src10_o(sa0),.out_src20_o(sb0),.out_src11_o(sa1),.out_src21_o(sb1),
      .out_ready_mask_i(route_ready),
      .fallthrough_ready_mask_i(stage_fallthrough_ready),
      .out_fire_mask_o(stage_fire),
      .full_o(stage_full),.pair_held_o(stage_pair_held),
      .selective_kill_drop_mask_o(selective_unused_stage_drop),
      .fallthrough_eligible_mask_o(stage_fallthrough_eligible),
      .direct_fire_mask_o(stage_direct_fire));
    ooo_issue_operand_fu_router_2alu_1lsu u_router(.bundle_valid_mask_i(stage_out_mask),.bundle_uop0_i(su0),.bundle_uop1_i(su1),
      .bundle_src10_i(sa0),.bundle_src20_i(sb0),.bundle_src11_i(sa1),.bundle_src21_i(sb1),.alu0_ready_i(a0r),.alu1_ready_i(a1r),.lsu_ready_i(lsur),
      .bundle_ready_mask_o(route_ready),.alu0_valid_o(a0v),.alu0_uop_o(a0u),.alu0_src1_o(a0a),.alu0_src2_o(a0b),
      .alu1_valid_o(a1v),.alu1_uop_o(a1u),.alu1_src1_o(a1a),.alu1_src2_o(a1b),.lsu_valid_o(lsuv),.lsu_uop_o(lsuu),.lsu_src1_o(lsua),.lsu_src2_o(lsub));
    ooo_alu_pipeline_1w u_a0(.clk(clk),.reset(reset),.flush_i(flush_i),.selective_kill_valid_i(selective_squash_fire_o),.selective_killed_rob_mask_i(selective_killed_rob_mask_o),.selective_kill_drop_o(selective_unused_alu0_drop),.issue_valid_i(a0v),.issue_uop_i(a0u),.src1_data_i(a0a),.src2_data_i(a0b),.issue_ready_o(a0r),.issue_accept_o(a0acc),.completion_wb_o(aw0),.completion_valid_o(aw0v),.completion_ready_i(pclear[0]));
    ooo_alu_pipeline_1w u_a1(.clk(clk),.reset(reset),.flush_i(flush_i),.selective_kill_valid_i(selective_squash_fire_o),.selective_killed_rob_mask_i(selective_killed_rob_mask_o),.selective_kill_drop_o(selective_unused_alu1_drop),.issue_valid_i(a1v),.issue_uop_i(a1u),.src1_data_i(a1a),.src2_data_i(a1b),.issue_ready_o(a1r),.issue_accept_o(a1acc),.completion_wb_o(aw1),.completion_valid_o(aw1v),.completion_ready_i(pclear[1]));
    ooo_lsu_pipeline_1w #(
      .PRECISE_STORE_BUFFER_ENABLE(PRECISE_STORE_BUFFER_ENABLE),
      .STORE_LOAD_FORWARDING_ENABLE(STORE_LOAD_FORWARDING_ENABLE),
      .LOAD_RESPONSE_COMPLETION_BYPASS_ENABLE(
        LOAD_RESPONSE_COMPLETION_BYPASS_ENABLE),
      .LSU_REQUEST_FALLTHROUGH_ENABLE(LSU_REQUEST_FALLTHROUGH_ENABLE),
      .POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE(
        POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE),
      .POSTED_STORE_RESPONSE_PIPELINE_ENABLE(
        POSTED_STORE_RESPONSE_PIPELINE_ENABLE),
      .DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE(
        DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE)
    ) u_lsu(.clk(clk),.reset(reset),.flush_i(flush_i),.selective_kill_valid_i(selective_squash_fire_o),.selective_killed_rob_mask_i(selective_killed_rob_mask_o),.issue_valid_i(lsuv && (|stage_fire)),.issue_uop_i(lsuu),.base_data_i(lsua),.store_data_i(lsub),.issue_ready_o(lsur),
      .mem_req_valid_o(lsu_mem_req_valid),.mem_req_ready_i(lsu_mem_req_ready),.mem_req_write_o(lsu_mem_req_write),.mem_req_addr_o(lsu_mem_req_addr),.mem_req_wdata_o(lsu_mem_req_wdata),.mem_req_wstrb_o(lsu_mem_req_wstrb),.mem_req_len_o(lsu_mem_req_len),
      .mem_req_token_o(lsu_mem_req_token),.mem_rsp_valid_i(lsu_mem_rsp_valid),.mem_rsp_ready_o(lsu_mem_rsp_ready),.mem_rsp_rdata_i(lsu_mem_rsp_rdata),.mem_rsp_error_i(lsu_mem_rsp_error),.mem_rsp_page_fault_i(lsu_mem_rsp_page_fault),.mem_rsp_token_i(lsu_mem_rsp_token),
      .load_completion_valid_o(lwv),.load_completion_ready_i(pclear[2]),.load_completion_wb_o(lw),.exception_completion_valid_o(xwv),.exception_completion_ready_i(sclear[1]),.exception_completion_wb_o(xw),
      .commit_store_valid_i(commit_store_valid),.commit_store_ready_o(commit_store_ready),.commit_store_rob_tag_i(commit_store_tag),.commit_store_addr_i(cs_addr),.commit_store_wdata_i(cs_data),.commit_store_wstrb_i(cs_strb),.commit_store_len_i(cs_len),
      .commit_store_done_valid_o(commit_store_done),.commit_store_done_ready_i(commit_store_done_clear),.commit_store_done_rob_tag_o(commit_store_done_tag),
      .commit_store_fault_valid_o(commit_store_fault),.commit_store_fault_ready_i(commit_store_fault_clear),
      .commit_store_fault_rob_tag_o(commit_store_fault_tag),.commit_store_fault_tval_o(commit_store_fault_tval),
      .occupied_o(lsu_occ),.load_outstanding_o(lsu_load_out),
      .load_occupied_o(lsu_load_occupied),
      .commit_store_outstanding_o(lsu_store_out),
      .store_buffer_count_o(lsu_store_buffer_count),
      .store_buffer_enq_fire_o(lsu_store_buffer_enq),
      .store_buffer_ack_fire_o(lsu_store_buffer_ack),
      .store_buffer_full_o(lsu_store_buffer_full),
      .store_buffer_req_fire_o(lsu_store_buffer_req),
      .store_buffer_rsp_fire_o(lsu_store_buffer_rsp),
      .store_buffer_response_owner_valid_o(lsu_store_response_owner),
      .store_buffer_request_release_fire_o(lsu_store_request_release),
      .store_buffer_busy_o(lsu_store_buffer_busy),
      .store_load_forward_fire_o(lsu_store_load_forward),
      .store_load_disjoint_fire_o(lsu_store_load_disjoint),
      .store_load_blocked_o(lsu_store_load_blocked),
      .selective_kill_drop_o(selective_unused_lsu_drop),.conservation_error_o(lsu_ce),
      .debug_load_phase_o(lsu_branch_producer_phase),
      .debug_pre_arbiter_load_offer_valid_o(
        lsu_pre_arbiter_load_offer_valid),
      .debug_pre_arbiter_load_offer_source_o(
        lsu_pre_arbiter_load_offer_source),
      .debug_pre_arbiter_load_offer_addr_o(
        lsu_pre_arbiter_load_offer_addr),
      .debug_pre_arbiter_load_offer_len_o(
        lsu_pre_arbiter_load_offer_len),
      .debug_pre_arbiter_load_offer_token_o(
        lsu_pre_arbiter_load_offer_token),
      .debug_pre_arbiter_load_response_ready_o(
        lsu_pre_arbiter_load_response_ready),
      .debug_load_response_match_o(lsu_load_response_match),
      .debug_load_response_live_o(lsu_load_response_live),
      .debug_store_block_reason_o(lsu_store_block_reason),
      .debug_store_service_phase_o(lsu_store_service_phase),
      .debug_store_admission_o(lsu_store_admission));

    assign atomic_available=!atomic_occupied&&!lsu_occ&&(mem_owner==2'd0);
    assign lsu_store_relaxed = STORE_LOAD_FORWARDING_ENABLE &&
      lsu_mem_req_write && lsu_store_buffer_busy;
    assign atomic_commit_valid=commit_event_o.slot0.valid&&
      (commit_event_o.slot0.fu_type==BBUS_OOO_FU_AMO);
    assign atomic_commit_tag=commit_event_o.slot0.rob_tag;
    assign reservation_invalidate=lsu_mem_rsp_valid&&lsu_mem_rsp_ready&&
      (lsu_mem_rsp_token.client==BBUS_OOO_MEM_CLIENT_LSU_STORE)&&
      !lsu_mem_rsp_error&&!lsu_mem_rsp_page_fault;
    ooo_atomic_pipeline_1w u_atomic(.clk(clk),.reset(reset),.flush_i(flush_i),
      .issue_valid_i(issue0_atomic),.issue_uop_i(iu0),.address_i(issue_a0_c),.operand_i(issue_b0_c),
      .issue_ready_o(atomic_issue_ready),.issue_accept_o(atomic_issue_accept),
      .mem_req_valid_o(atomic_mem_req_valid),.mem_req_ready_i(atomic_mem_req_ready),
      .mem_req_write_o(atomic_mem_req_write),.mem_req_addr_o(atomic_mem_req_addr),
      .mem_req_wdata_o(atomic_mem_req_wdata),.mem_req_wstrb_o(atomic_mem_req_wstrb),.mem_req_len_o(atomic_mem_req_len),.mem_req_access_o(atomic_mem_req_access),
      .mem_req_token_o(atomic_mem_req_token),
      .mem_rsp_valid_i(atomic_mem_rsp_valid),.mem_rsp_ready_o(atomic_mem_rsp_ready),
      .mem_rsp_rdata_i(atomic_mem_rsp_rdata),.mem_rsp_error_i(atomic_mem_rsp_error),.mem_rsp_page_fault_i(atomic_mem_rsp_page_fault),.mem_rsp_token_i(atomic_mem_rsp_token),
      .completion_valid_o(atomic_completion_valid),.completion_ready_i(sclear[5]),.completion_wb_o(atomic_wb),
      .commit_valid_i(atomic_commit_valid),.commit_rob_tag_i(atomic_commit_tag),
      .reservation_invalidate_i(reservation_invalidate),
      .occupied_o(atomic_occupied),.memory_lock_o(atomic_lock),.write_request_fire_o(atomic_write_fire),
      .recovery_block_o(atomic_recovery_block),.killed_read_drain_o(atomic_drop_wait),
      .illegal_issue_o(atomic_illegal),.flush_drop_o(atomic_flush_drop),
      .reservation_valid_o(atomic_reservation_valid),.reservation_addr_o(atomic_reservation_addr),
      .sc_success_o(atomic_sc_success),.sc_failure_o(atomic_sc_failure),
      .irreversible_flush_error_o(atomic_flush_error),
      .conservation_error_o(atomic_ce));

    ooo_lsu_atomic_mem_arbiter_2e #(
      .POSTED_STORE_RESPONSE_PIPELINE_ENABLE(
        POSTED_STORE_RESPONSE_PIPELINE_ENABLE),
      .DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE(
        DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE),
      .PRE_ARBITER_LOAD_HIT_ORACLE_ENABLE(
        PRE_ARBITER_LOAD_HIT_ORACLE_ENABLE),
      .LOAD_TRANSACTION_DEPTH3_ENABLE(LOAD_TRANSACTION_DEPTH3_ENABLE)
    ) u_mem_owner(.clk(clk),.reset(reset),
      .lsu_req_valid_i(lsu_mem_req_valid),.lsu_req_ready_o(lsu_mem_req_ready),
      .lsu_req_write_i(lsu_mem_req_write),.lsu_req_addr_i(lsu_mem_req_addr),
      .lsu_req_wdata_i(lsu_mem_req_wdata),.lsu_req_wstrb_i(lsu_mem_req_wstrb),.lsu_req_len_i(lsu_mem_req_len),
      .lsu_req_token_i(lsu_mem_req_token),.lsu_store_relaxed_i(lsu_store_relaxed),
      .lsu_rsp_valid_o(lsu_mem_rsp_valid),.lsu_rsp_ready_i(lsu_mem_rsp_ready),
      .lsu_rsp_rdata_o(lsu_mem_rsp_rdata),.lsu_rsp_error_o(lsu_mem_rsp_error),.lsu_rsp_token_o(lsu_mem_rsp_token),
      .atomic_lock_i(atomic_lock),.atomic_req_valid_i(atomic_mem_req_valid),.atomic_req_ready_o(atomic_mem_req_ready),
      .atomic_req_write_i(atomic_mem_req_write),.atomic_req_addr_i(atomic_mem_req_addr),
      .atomic_req_wdata_i(atomic_mem_req_wdata),.atomic_req_wstrb_i(atomic_mem_req_wstrb),.atomic_req_len_i(atomic_mem_req_len),.atomic_req_access_i(atomic_mem_req_access),
      .atomic_req_token_i(atomic_mem_req_token),
      .atomic_rsp_valid_o(atomic_mem_rsp_valid),.atomic_rsp_ready_i(atomic_mem_rsp_ready),
      .atomic_rsp_rdata_o(atomic_mem_rsp_rdata),.atomic_rsp_error_o(atomic_mem_rsp_error),.atomic_rsp_page_fault_o(atomic_mem_rsp_page_fault),.atomic_rsp_token_o(atomic_mem_rsp_token),
      .mem_req_valid_o(mem_req_valid_o),.mem_req_ready_i(mem_req_ready_i),.mem_req_write_o(mem_req_write_o),
      .mem_req_addr_o(mem_req_addr_o),.mem_req_wdata_o(mem_req_wdata_o),.mem_req_wstrb_o(mem_req_wstrb_o),.mem_req_len_o(mem_req_len_o),.mem_req_access_o(mem_req_access_o),
      .mem_req_token_o(mem_req_token_o),.mem_rsp_valid_i(mem_rsp_valid_i),.mem_rsp_ready_o(mem_rsp_ready_o),.mem_rsp_rdata_i(mem_rsp_rdata_i),.mem_rsp_error_i(mem_rsp_error_i),.mem_rsp_page_fault_i(mem_rsp_page_fault_i),.mem_rsp_token_i(mem_rsp_token_i),
      .lsu_rsp_page_fault_o(lsu_mem_rsp_page_fault),
      .load_outstanding_count_o(mem_load_outstanding_count),
      .exclusive_active_o(mem_exclusive_active),
      .third_load_backpressure_o(mem_third_load_backpressure),
      .unknown_response_o(mem_unknown_response),
      .duplicate_request_o(mem_duplicate_request),
      .owner_o(mem_owner),.collision_guard_o(mem_collision),
      .partial_handoff_guard_o(mem_partial),
      .conservation_error_o(mem_ce),
      .debug_load_turnover_o(mem_load_turnover));

    always_comb begin
      ext_serial_valid=0;for(int k=0;k<5;k++)serial_wb[k]='0;
      if(serial_completion_kind_i<5)begin ext_serial_valid[serial_completion_kind_i]=serial_completion_valid_i;serial_wb[serial_completion_kind_i]=serial_completion_wb_i;end
      if(xwv)begin ext_serial_valid[1]=1;serial_wb[1]=xw;end
      raw_probe_valid_mask={atomic_completion_valid,ext_serial_valid,lwv,aw1v,aw0v};
      raw_probe_wb[0]=aw0;raw_probe_wb[1]=aw1;raw_probe_wb[2]=lw;
      raw_probe_wb[3]=serial_wb[0];raw_probe_wb[4]=serial_wb[1];
      raw_probe_wb[5]=serial_wb[2];raw_probe_wb[6]=serial_wb[3];raw_probe_wb[7]=serial_wb[4];
      raw_probe_wb[8]=atomic_wb;
    end
    assign serial_completion_ready_o = (serial_completion_kind_i < 5) ?
      sclear[serial_completion_kind_i] : 1'b0;
    ooo_pipeline_completion_fabric_2w #(
      .PAIR_RAW_TO_FINAL_BYPASS_ENABLE(PAIR_RAW_TO_FINAL_BYPASS_ENABLE),
      .BRU_RAW_TO_FINAL_BYPASS_ENABLE(
        BRANCH_ISSUE_FINAL_FALLTHROUGH_ENABLE),
      .STORE_ISSUE_FINAL_FALLTHROUGH_ENABLE(
        STORE_ISSUE_FINAL_FALLTHROUGH_ENABLE),
      .SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE(
        SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE)
    ) u_fabric(.clk(clk),.reset(reset),.flush_i(flush_i),.selective_kill_valid_i(selective_squash_fire_o),.selective_killed_rob_mask_i(selective_killed_rob_mask_o),.rob_head_i(rob_head),
      .alu0_wb_i(aw0),.alu0_valid_i(aw0v),.alu0_rob_match_i(raw_probe_fresh_mask[0]),.alu0_killed_i(1'b0),.alu1_wb_i(aw1),.alu1_valid_i(aw1v),.alu1_rob_match_i(raw_probe_fresh_mask[1]),.alu1_killed_i(1'b0),
      .lsu_load_wb_i(lw),.lsu_load_valid_i(lwv),.lsu_load_rob_match_i(raw_probe_fresh_mask[2]),.lsu_load_killed_i(1'b0),
      .bru_wb_i(serial_wb[0]),.bru_valid_i(ext_serial_valid[0]),.bru_rob_match_i(serial_match[0]),.bru_killed_i(1'b0),
      .lsu_exception_wb_i(serial_wb[1]),.lsu_exception_valid_i(ext_serial_valid[1]),.lsu_exception_rob_match_i(serial_match[1]),.lsu_exception_killed_i(1'b0),
      .csr_wb_i(serial_wb[2]),.csr_valid_i(ext_serial_valid[2]),.csr_rob_match_i(serial_match[2]),.csr_killed_i(1'b0),
      .system_wb_i(serial_wb[3]),.system_valid_i(ext_serial_valid[3]),.system_rob_match_i(serial_match[3]),.system_killed_i(1'b0),
      .mdu_wb_i(serial_wb[4]),.mdu_valid_i(ext_serial_valid[4]),.mdu_rob_match_i(serial_match[4]),.mdu_killed_i(1'b0),
      .amo_wb_i(atomic_wb),.amo_valid_i(atomic_completion_valid),.amo_rob_match_i(raw_probe_fresh_mask[8]),.amo_killed_i(1'b0),
      .final_consumer_ready_i(1'b1),.final_consumer_accept_mask_i({probe1,probe0}),.final_consumer_drop_mask_i(~{probe1,probe0}),
      .pair_source_accept_mask_o(paccept),.pair_source_drop_mask_o(pdrop),.pair_source_clear_mask_o(pclear),.serial_source_accept_mask_o(saccept),.serial_source_clear_mask_o(sclear),.final_wb0_o(fw0),.final_wb1_o(fw1),.final_valid_mask_o(fvalid),.final_consume_mask_o(fconsume),.final_drop_mask_o(fdrop),
      .ordinary_wakeup_valid_o(fwake),.wakeup_phys0_o(wake0),.wakeup_phys1_o(wake1),.perf_completion_ownership_o(perf_completion_ownership_o),.conservation_error_o(fabric_ce));

    ooo_raw_completion_wakeup_2w #(
      .ENABLE(RAW_COMPLETION_WAKEUP_ENABLE)
    ) u_raw_wakeup(.clk(clk),.reset(reset),.flush_i(flush_i),
      .selective_kill_valid_i(selective_squash_fire_o),
      .selective_killed_rob_mask_i(selective_killed_rob_mask_o),
      .raw_accept_mask_i(paccept),.raw_alu0_wb_i(aw0),
      .raw_alu1_wb_i(aw1),.raw_lsu_wb_i(lw),
      .final_consume_mask_i(fconsume),.final_drop_mask_i(fdrop),
      .final_wakeup_mask_i(fwake),.final_wb0_i(fw0),.final_wb1_i(fw1),
      .write_mask_o(effective_write_mask),
      .write_wb0_o(effective_write_wb0),
      .write_wb1_o(effective_write_wb1),
      .early_source_mask_o(early_source_mask),
      .final_suppress_mask_o(final_write_suppress_mask),
      .marker_count_o(early_marker_count),
      .conservation_error_o(raw_wakeup_ce));

    assign final_consume_mask_o=fconsume;
    assign final_wb0_o=fw0;
    assign final_wb1_o=fw1;
    assign ordinary_wakeup_mask_o=effective_write_mask;
    assign ordinary_wakeup_phys0_o=effective_write_wb0.phys_rd;
    assign ordinary_wakeup_phys1_o=effective_write_wb1.phys_rd;
    assign same_cycle_dependency_issue_mask_o =
      iq_same_cycle_wakeup_mask & {issue_fire1,issue_fire0};
    assign commit_serial_match=(serial_pending_q&&((commit_event_o.slot0.valid&&commit_event_o.slot0.rob_tag==serial_tag_q)||(commit_event_o.slot1.valid&&commit_event_o.slot1.rob_tag==serial_tag_q)));
    assign memory_dispatch_barrier_c = (|store_pending_mask_q) ||
      (lsu_store_out &&
       (!STORE_LOAD_FORWARDING_ENABLE || !lsu_store_buffer_busy));
    assign memory_dispatch_barrier_o = memory_dispatch_barrier_c;
    always_ff @(posedge clk)begin if(reset||flush_i)begin serial_pending_q<=0;serial_tag_q<='0;end else begin
      if(selective_squash_fire_o&&serial_pending_q&&serial_tag_q.valid&&selective_killed_rob_mask_o[serial_tag_q.idx])begin serial_pending_q<=0;serial_tag_q<='0;end
      else if(rob_alloc_fire[0]&&serial_blocks_dispatch(dispatch_uop0_i))begin serial_pending_q<=1;serial_tag_q<=rob_tag0;end
      else if(rob_alloc_fire[1]&&serial_blocks_dispatch(dispatch_uop1_i))begin serial_pending_q<=1;serial_tag_q<=rob_tag1;end
      else if(commit_serial_match)serial_pending_q<=0;end end
    always_comb begin
      store_pending_mask_next_c = store_pending_mask_q;
      if (selective_squash_fire_o)
        store_pending_mask_next_c = store_pending_mask_next_c &
          ~selective_killed_rob_mask_o;
      if (commit_event_o.slot0.valid && commit_event_o.slot0.is_store)
        store_pending_mask_next_c[commit_event_o.slot0.rob_tag.idx] = 1'b0;
      if (commit_event_o.slot1.valid && commit_event_o.slot1.is_store)
        store_pending_mask_next_c[commit_event_o.slot1.rob_tag.idx] = 1'b0;
      if (rob_alloc_fire[0] && dispatch_uop0_i.is_store)
        store_pending_mask_next_c[rob_tag0.idx] = 1'b1;
      if (rob_alloc_fire[1] && dispatch_uop1_i.is_store)
        store_pending_mask_next_c[rob_tag1.idx] = 1'b1;
    end
    always_ff @(posedge clk) begin
      if (reset || flush_i)
        store_pending_mask_q <= '0;
      else
        store_pending_mask_q <= store_pending_mask_next_c;
    end
    assign serial_barrier_o=serial_pending_q;
    assign backend_busy_o=(rob_count_o!=0)||(iq_count_o!=0)||serial_pending_q||
      (|store_pending_mask_q)||lsu_occ||atomic_occupied||(mem_owner!=0)||(fvalid!=0);
    assign atomic_recovery_block_o=atomic_recovery_block;
    assign atomic_occupied_o=atomic_occupied;
    assign issue_fire0 = iv0 && issue_ready0;
    assign issue_fire1 = iv1 && issue_ready1;
    assign perf_issue_width_o = {1'b0, issue_fire0} + {1'b0, issue_fire1};
    assign perf_branch_iq_ready_count_o = (iq_ready_bru >= 4'd2) ?
      2'd2 : iq_ready_bru[1:0];
    assign perf_commit_reason0_o = rob_commit_reason0;
    assign perf_commit_reason1_o = rob_commit_reason1;
    assign perf_store_buffer_o = {
      lsu_store_load_blocked, lsu_store_load_disjoint,
      lsu_store_load_forward,
      lsu_store_buffer_rsp, lsu_store_buffer_req, lsu_store_buffer_full,
      lsu_store_buffer_ack, lsu_store_buffer_enq, lsu_store_buffer_count};

    // Simulation-only raw-completion lifecycle sideband. It reports the
    // exact fresh packets accepted by the completion fabric and never feeds
    // selection, backpressure, recovery, or architectural state.
    always_comb begin
      int raw_i;
      int accepted_count;
      accounting_raw_accept_mask = {saccept, paccept};
      accounting_raw_fu[0] = BBUS_OOO_FU_ALU;
      accounting_raw_fu[1] = BBUS_OOO_FU_ALU;
      accounting_raw_fu[2] = BBUS_OOO_FU_LSU;
      accounting_raw_fu[3] = BBUS_OOO_FU_BRU;
      accounting_raw_fu[4] = BBUS_OOO_FU_LSU;
      accounting_raw_fu[5] = BBUS_OOO_FU_CSR;
      accounting_raw_fu[6] = BBUS_OOO_FU_SYS;
      accounting_raw_fu[7] = BBUS_OOO_FU_MDU;
      accounting_raw_fu[8] = BBUS_OOO_FU_AMO;
      perf_accounting_raw_o = '0;
      perf_accounting_raw_o[28:20] =
          raw_probe_valid_mask & raw_probe_fresh_mask;
      perf_accounting_raw_o[29] =
          (|(raw_probe_valid_mask & raw_probe_fresh_mask)) &&
          !(|accounting_raw_accept_mask);
      perf_accounting_raw_o[30] = |fvalid;
      accepted_count = 0;
      for (raw_i = 0; raw_i < 9; raw_i = raw_i + 1) begin
        if (accounting_raw_accept_mask[raw_i]) begin
          if (accepted_count == 0) begin
            perf_accounting_raw_o[6:2] = {
              raw_probe_wb[raw_i].rob_tag.gen,
              raw_probe_wb[raw_i].rob_tag.idx
            };
            perf_accounting_raw_o[15:12] = accounting_raw_fu[raw_i];
          end else if (accepted_count == 1) begin
            perf_accounting_raw_o[11:7] = {
              raw_probe_wb[raw_i].rob_tag.gen,
              raw_probe_wb[raw_i].rob_tag.idx
            };
            perf_accounting_raw_o[19:16] = accounting_raw_fu[raw_i];
          end else if (accepted_count == 2) begin
            // The linear ExecuteRaw ledger remains two slots wide. P34 may
            // additionally capture one serial packet as a service-plane
            // event, so export its identity only for Level-2 lifecycle
            // accounting.
            perf_accounting_raw_o[32] = 1'b1;
            perf_accounting_raw_o[37:33] = {
              raw_probe_wb[raw_i].rob_tag.gen,
              raw_probe_wb[raw_i].rob_tag.idx
            };
            perf_accounting_raw_o[41:38] = accounting_raw_fu[raw_i];
          end
          accepted_count = accepted_count + 1;
          if (!raw_probe_valid_mask[raw_i] ||
              !raw_probe_fresh_mask[raw_i] ||
              !raw_probe_wb[raw_i].rob_tag.valid)
            perf_accounting_raw_o[31] = 1'b1;
        end
      end
      perf_accounting_raw_o[0] = accepted_count >= 1;
      perf_accounting_raw_o[1] = accepted_count >= 2;
      if ((accepted_count > 2) &&
          !(SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE &&
            (accepted_count == 3) && (saccept != 6'b0) &&
            ((paccept == 3'b011) || (paccept == 3'b101) ||
             (paccept == 3'b110))))
        perf_accounting_raw_o[31] = 1'b1;
    end

    always_comb begin
      perf_issue_reason0_o = 4'd0;
      if (!issue_fire0) begin
        if (flush_i) perf_issue_reason0_o = 4'd1;
        else if (iq_count_o == 4'd0) perf_issue_reason0_o = 4'd2;
        else if (iq_ready_total == 4'd0) perf_issue_reason0_o = 4'd3;
        else if (iv0 && (issue0_serial || issue0_atomic)) perf_issue_reason0_o = 4'd5;
        else if (iv0 && !stage_in_ready[0]) perf_issue_reason0_o = 4'd8;
        else if (iv0 && !issue_ready0) perf_issue_reason0_o = 4'd6;
        else perf_issue_reason0_o = 4'd9;
      end

      perf_issue_reason1_o = 4'd0;
      if (!issue_fire1) begin
        if (!issue_fire0) perf_issue_reason1_o = perf_issue_reason0_o;
        else if (iq_ready_total < 4'd2) perf_issue_reason1_o = 4'd4;
        else if (issue0_serial || issue0_atomic) perf_issue_reason1_o = 4'd5;
        else if (pair_valid && !pair_legal) perf_issue_reason1_o = 4'd7;
        else if (iv1 && !stage_in_ready[1]) perf_issue_reason1_o = 4'd8;
        else if (iv1 && !issue_ready1) perf_issue_reason1_o = 4'd6;
        else perf_issue_reason1_o = 4'd9;
      end

      perf_events_o = 64'd0;
      perf_events_o[0] = a0acc;
      perf_events_o[1] = a1acc;
      perf_events_o[2] = lsuv && lsur;
      perf_events_o[3] = serial_issue_fire && (serial_issue_kind_o == SK_BRU);
      perf_events_o[4] = serial_issue_fire && (serial_issue_kind_o == SK_CSR);
      perf_events_o[5] = serial_issue_fire && (serial_issue_kind_o == SK_SYS);
      perf_events_o[6] = serial_issue_fire && (serial_issue_kind_o == SK_MDU);
      perf_events_o[7] = atomic_issue_accept;
      perf_events_o[8] = aw0v && pclear[0];
      perf_events_o[9] = aw1v && pclear[1];
      perf_events_o[10] = lwv && pclear[2];
      perf_events_o[11] = ext_serial_valid[0] && sclear[0];
      perf_events_o[12] = ext_serial_valid[2] && sclear[2];
      perf_events_o[13] = ext_serial_valid[3] && sclear[3];
      perf_events_o[14] = ext_serial_valid[4] && sclear[4];
      perf_events_o[15] = atomic_completion_valid && sclear[5];
      perf_events_o[16] = xwv && sclear[1];
      perf_events_o[17] = mem_req_valid_o && mem_req_ready_i;
      perf_events_o[18] = mem_rsp_valid_i && mem_rsp_ready_o;
      perf_events_o[19] = lsu_load_out;
      perf_events_o[20] = lsu_store_out;
      perf_events_o[21] = atomic_occupied;
      perf_events_o[22] = serial_pending_q;
      perf_events_o[23] = (|raw_probe_valid_mask) &&
        !((|pclear) || (|sclear));
      perf_events_o[24] = commit_store_valid && commit_store_ready;
      perf_events_o[25] = commit_store_done && commit_store_done_clear;
      perf_events_o[26] = commit_store_fault && commit_store_fault_clear;
      perf_events_o[27] = flush_i;
      perf_events_o[28] = fabric_ce || lsu_ce || atomic_ce || mem_ce;
      perf_events_o[29] = iq_multi_candidate;
      perf_events_o[30] = pair_valid && pair_legal;
      perf_events_o[31] = atomic_recovery_block;
      perf_mixed_source_o = {
        issue_fire1 && iq_issue_from_dispatch[1],
        issue_fire0 && iq_issue_from_dispatch[0],
        iq_mixed_source_pair_kind,
        perf_mixed_source_reason,
        iq_mixed_source_valid
      };
      perf_branch_pair_o[0] = branch_ordinary_pair_accept_c;
      perf_branch_pair_o[1] = branch_ordinary_pair_accept_c &&
        !branch_lane1_c;
      perf_branch_pair_o[2] = branch_ordinary_pair_accept_c &&
        !branch_lane1_c && !iq_issue_from_dispatch[0] &&
        iq_issue_from_dispatch[1];
      perf_operand_stage_o = {
        stage_direct_fire,
        stage_in_uop1_c.rob_tag.gen, stage_in_uop1_c.rob_tag.idx,
        stage_in_uop0_c.rob_tag.gen, stage_in_uop0_c.rob_tag.idx,
        stage_fallthrough_eligible, stage_in_accept,
        stage_pair_held, stage_full
      };

      // Simulation-only lifecycle transport. Event-valid bits are separate
      // from the modulo-4 ROB identity so tag value zero remains observable.
      perf_lifecycle_o = 64'd0;
      perf_lifecycle_o[0] = rob_alloc_fire[0];
      perf_lifecycle_o[1] = rob_alloc_fire[1];
      perf_lifecycle_o[2] = issue_fire0;
      perf_lifecycle_o[3] = issue_fire1;
      perf_lifecycle_o[4] = fconsume[0];
      perf_lifecycle_o[5] = fconsume[1];
      perf_lifecycle_o[6] = commit_event_o.slot0.valid;
      perf_lifecycle_o[7] = commit_event_o.slot1.valid;
      perf_lifecycle_o[8] = flush_i;
      perf_lifecycle_o[11] = mem_req_valid_o && mem_req_ready_i;
      perf_lifecycle_o[12] = mem_rsp_valid_i && mem_rsp_ready_o;
      perf_lifecycle_o[16 +: 5] = {rob_tag0.gen, rob_tag0.idx};
      perf_lifecycle_o[21 +: 5] = {rob_tag1.gen, rob_tag1.idx};
      perf_lifecycle_o[26 +: 5] = {iu0.rob_tag.gen, iu0.rob_tag.idx};
      perf_lifecycle_o[31 +: 5] = {iu1.rob_tag.gen, iu1.rob_tag.idx};
      perf_lifecycle_o[36 +: 5] = {fw0.rob_tag.gen, fw0.rob_tag.idx};
      perf_lifecycle_o[41 +: 5] = {fw1.rob_tag.gen, fw1.rob_tag.idx};
      perf_lifecycle_o[46 +: 5] = {
        commit_event_o.slot0.rob_tag.gen, commit_event_o.slot0.rob_tag.idx};
      perf_lifecycle_o[51 +: 5] = {
        commit_event_o.slot1.rob_tag.gen, commit_event_o.slot1.rob_tag.idx};
      perf_lifecycle_o[56 +: 4] = dispatch_uop0_i.fu_type;
      perf_lifecycle_o[60 +: 4] = dispatch_uop1_i.fu_type;

      perf_branch_operand_o = 64'd0;
      perf_branch_operand_o[5:0] = dispatch_uop0_i.phys_rd_new;
      perf_branch_operand_o[6] = dispatch_uop0_i.rf_wen;
      perf_branch_operand_o[10:7] = dispatch_uop0_i.fu_type;
      perf_branch_operand_o[16:11] = dispatch_uop1_i.phys_rd_new;
      perf_branch_operand_o[17] = dispatch_uop1_i.rf_wen;
      perf_branch_operand_o[21:18] = dispatch_uop1_i.fu_type;
      perf_branch_operand_o[63:22] = iq_branch_operand;

      perf_branch_producer_phase_o = 64'd0;
      perf_branch_producer_phase_o[15:0] = lsu_branch_producer_phase;
      perf_branch_producer_phase_o[22:16] = {
        aw0.rob_tag.gen, aw0.rob_tag.idx, paccept[0], aw0v};
      perf_branch_producer_phase_o[29:23] = {
        aw1.rob_tag.gen, aw1.rob_tag.idx, paccept[1], aw1v};
      perf_branch_producer_phase_o[36:30] = {
        lw.rob_tag.gen, lw.rob_tag.idx, paccept[2], lwv};
      perf_branch_producer_phase_o[37] =
        (paccept[0] && !aw0v) || (paccept[1] && !aw1v) ||
        (paccept[2] && !lwv) ||
        (aw0v && !aw0.rob_tag.valid) ||
        (aw1v && !aw1.rob_tag.valid) ||
        (lwv && !lw.rob_tag.valid);
      perf_branch_producer_phase_o[39:38] = iq_branch_no_older_ready;
      perf_branch_producer_phase_o[45:40] = iq_branch_pred_source;
      perf_branch_producer_phase_o[47:46] = iq_branch_pred_correlated;
      perf_branch_producer_phase_o[61] = lsu_mem_rsp_valid;
      perf_branch_producer_phase_o[62] = lsu_mem_rsp_ready;
      perf_branch_producer_phase_o[63] =
        lsu_mem_rsp_valid && lsu_mem_rsp_ready;
      perf_lsu_causality_o = '0;
      perf_lsu_causality_o[2:0] = lsu_store_block_reason;
      perf_lsu_causality_o[5:3] = lsu_store_service_phase;
      perf_lsu_causality_o[6] = lsu_store_load_forward;
      perf_lsu_causality_o[11:7] = {
        lsuu.rob_tag.gen, lsuu.rob_tag.idx};
      perf_lsu_causality_o[12] = lsu_mem_rsp_valid &&
        lsu_mem_rsp_token.valid &&
        (lsu_mem_rsp_token.client == BBUS_OOO_MEM_CLIENT_LSU_LOAD);
      perf_lsu_causality_o[13] = lsu_mem_rsp_ready;
      perf_lsu_causality_o[14] = perf_lsu_causality_o[12] &&
        lsu_mem_rsp_ready;
      perf_lsu_causality_o[15] = perf_lsu_causality_o[12] &&
        lsu_load_response_live;
      perf_lsu_causality_o[20:16] = lsu_mem_rsp_token.slot[0] ?
        lsu_branch_producer_phase[15:11] :
        lsu_branch_producer_phase[7:3];
      perf_lsu_causality_o[21] = perf_lsu_causality_o[12] &&
        (lsu_mem_rsp_error || lsu_mem_rsp_page_fault);
      perf_lsu_causality_o[22] = lsu_store_buffer_enq;
      perf_lsu_causality_o[23] = lsu_store_buffer_req;
      perf_lsu_causality_o[24] = lsu_store_buffer_rsp;
      perf_lsu_causality_o[25] = lsu_store_buffer_ack;
      perf_lsu_causality_o[26] = commit_store_valid;
      perf_lsu_causality_o[27] = commit_store_ready;
      perf_lsu_causality_o[28] = perf_lsu_causality_o[12] &&
        lsu_load_response_match && !lsu_load_response_live;
      perf_lsu_causality_o[29] = lsu_store_response_owner;
      perf_lsu_causality_o[30] = lsu_store_request_release;
      perf_lsu_causality_o[31] =
        POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE;
      perf_lsu_causality_o[40:32] = mem_load_turnover[8:0];
      // P77 moves only the observation boundary ahead of LSU request
      // selection. Feature-off preserves the P59 raw-offer bus exactly.
      if (PRE_ARBITER_LOAD_HIT_ORACLE_ENABLE) begin
        perf_lsu_causality_o[41] = lsu_pre_arbiter_load_offer_valid;
        perf_lsu_causality_o[73:42] = lsu_pre_arbiter_load_offer_addr;
        perf_lsu_causality_o[76:74] = lsu_pre_arbiter_load_offer_len;
        perf_lsu_causality_o[145:77] =
          lsu_pre_arbiter_load_offer_token;
        perf_lsu_causality_o[154:153] =
          lsu_pre_arbiter_load_offer_source;
        perf_lsu_causality_o[155] =
          lsu_pre_arbiter_load_response_ready;
      end else begin
        perf_lsu_causality_o[41] = lsu_mem_req_valid &&
          !lsu_mem_req_write && lsu_mem_req_token.valid &&
          (lsu_mem_req_token.client == BBUS_OOO_MEM_CLIENT_LSU_LOAD);
        perf_lsu_causality_o[73:42] = lsu_mem_req_addr;
        perf_lsu_causality_o[76:74] = lsu_mem_req_len;
        perf_lsu_causality_o[145:77] = lsu_mem_req_token;
      end
      perf_lsu_causality_o[152:146] = mem_load_turnover[15:9];
      perf_store_admission_o = '0;
      perf_store_admission_o[29:0] = lsu_store_admission;
      perf_store_admission_o[30] = commit_store_done_match;
      perf_store_admission_o[31] = commit_store_done_drop;
      perf_issue_dependency_o = iq_dependency_operand;
      perf_retirement_chain_o[5:0] = {
        rob_head_tag.valid, rob_head_tag.gen, rob_head_tag.idx};
      perf_retirement_chain_o[12:6] = iq_retirement_head;
      perf_retirement_chain_o[20:13] = rob_slot1_bypass_oracle[7:0];
      perf_retirement_chain_o[27:21] = rob_slot1_bypass_oracle[14:8];
      perf_retirement_chain_o[31:28] = rob_slot1_bypass_oracle[18:15];
      // Use the exported mutually-exclusive Commit owner as the authoritative
      // target.  Rebuild the target intersections here so they conserve
      // exactly with the P10 slot1_not_done ledger.
      perf_retirement_chain_o[13] = rob_commit_reason1 == 4'd9;
      perf_retirement_chain_o[18] =
        (rob_commit_reason1 == 4'd9) && rob_slot1_bypass_oracle[1];
      perf_retirement_chain_o[19] =
        (rob_commit_reason1 == 4'd9) && rob_slot1_bypass_oracle[2];
      perf_retirement_chain_o[20] =
        (rob_commit_reason1 == 4'd9) && rob_slot1_bypass_oracle[3];
      perf_complex_retire_pairing_o = rob_complex_retire_pairing;
    end
    assign conservation_error_o=fabric_ce||raw_wakeup_ce||lsu_ce||atomic_ce||mem_ce||atomic_illegal||atomic_flush_error||mem_collision||mem_partial||branch_ordinary_pair_protocol_error_c||stage_direct_protocol_error_c||(rob_alloc_fire!=iq_fire);
    /* verilator lint_off UNUSED */
    wire atomic_reservation_debug_used = atomic_reservation_valid ^
      (^atomic_reservation_addr) ^ atomic_sc_success ^ atomic_sc_failure;
    wire perf_iq_debug_used = (^iq_ready_alu) ^ (^iq_ready_lsu) ^
      (^iq_ready_bru) ^ (^iq_ready_csr_sys) ^ (^iq_ready_any) ^
      (^iq_issue_candidates);
    /* verilator lint_on UNUSED */
endmodule
