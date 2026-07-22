`timescale 1ns / 1ps

`ifndef NPC_HAS_MMU
`define NPC_HAS_MMU 1
`endif
`ifndef NPC_HAS_ITLB
`define NPC_HAS_ITLB 1
`endif
`ifndef NPC_ITLB_ENTRIES
`define NPC_ITLB_ENTRIES 16
`endif

// MVP frontend pipe for IF_HIT_PIPELINE=1.
//
// This module intentionally replaces the old experimental Sv32IFetchPipe path.
// Normal instruction fetches use the metadata-carrying ICache pipe interface;
// the legacy ICache cpu_req/cpu_resp port is not used as the frontend hit path.
// Phase-3 MVP supports bypass, ITLB-hit fetches, and a single outstanding
// ITLB-miss PTW/replay slow path.
module Sv32FrontendPipe (
    input clk,
    input rst_n,
    input flush,
    input tlb_flush_all,

    input cpu_req_valid,
    output cpu_req_ready,
    input [31:0] cpu_req_vaddr,
    input cpu_req_pred_taken,
    input [31:0] cpu_req_pred_target,
    input cpu_req_pred_btb_hit,
    input cpu_req_pred_btb_is_cond,
    input [1:0] cpu_req_pred_bht_state,
    input [31:0] cpu_req_pred_pht_idx,

    input [1:0] priv_i,
    input [31:0] satp_i,

    output cpu_resp_valid,
    input cpu_resp_ready,
    output [31:0] cpu_resp_rdata,
    output cpu_resp_exc_valid,
    output [31:0] cpu_resp_exc_cause,
    output [31:0] cpu_resp_exc_tval,
    output [31:0] cpu_resp_pc,
    output [31:0] cpu_resp_seq,
    output [15:0] cpu_resp_epoch,
    output cpu_resp_pred_taken,
    output [31:0] cpu_resp_pred_target,
    output cpu_resp_pred_btb_hit,
    output cpu_resp_pred_btb_is_cond,
    output [1:0] cpu_resp_pred_bht_state,
    output [31:0] cpu_resp_pred_pht_idx,

    output pipe_req_valid,
    input pipe_req_ready,
    output [31:0] pipe_req_paddr,
    output [31:0] pipe_req_vaddr,
    output [31:0] pipe_req_pc,
    output [31:0] pipe_req_seq,
    output [15:0] pipe_req_epoch,
    output pipe_req_pred_taken,
    output [31:0] pipe_req_pred_target,
    output pipe_req_pred_btb_hit,
    output pipe_req_pred_btb_is_cond,
    output [1:0] pipe_req_pred_bht_state,
    output [31:0] pipe_req_pred_pht_idx,
    output [1:0] pipe_req_priv,
    output pipe_req_exception_valid,
    output [31:0] pipe_req_exception_cause,
    output [31:0] pipe_req_exception_tval,

    input pipe_resp_valid,
    output pipe_resp_ready,
    input [31:0] pipe_resp_instr,
    input [31:0] pipe_resp_pc,
    input [31:0] pipe_resp_seq,
    input [15:0] pipe_resp_epoch,
    input pipe_resp_pred_taken,
    input [31:0] pipe_resp_pred_target,
    input pipe_resp_pred_btb_hit,
    input pipe_resp_pred_btb_is_cond,
    input [1:0] pipe_resp_pred_bht_state,
    input [31:0] pipe_resp_pred_pht_idx,
    input pipe_resp_exception_valid,
    input [31:0] pipe_resp_exception_cause,
    input [31:0] pipe_resp_exception_tval,
    input pipe_resp_hit,
    input pipe_resp_miss,

    output lower_req_valid,
    input lower_req_ready,
    output [31:0] lower_req_addr,
    input lower_resp_valid,
    output lower_resp_ready,
    input [31:0] lower_resp_rdata,

    output reg [63:0] stat_req_count,
    output reg [63:0] stat_bypass_count,
    output reg [63:0] stat_translate_count,
    output reg [63:0] stat_ptw_cycle_count,
    output reg [63:0] stat_ptw_l1_read_count,
    output reg [63:0] stat_ptw_l0_read_count,
    output reg [63:0] stat_page_fault_count,
    output reg [63:0] stat_ptw_walk_start_count,
    output reg [63:0] stat_ptw_walk_done_count,
    output reg [63:0] stat_ptw_walk_fault_count,
    output reg [63:0] stat_tlb_hit_count,
    output reg [63:0] stat_tlb_miss_count,
    output reg [63:0] stat_tlb_hit_to_cache_req_cycle,
    output reg [63:0] stat_cache_req_wait_cycle,
    output reg [63:0] stat_cache_resp_wait_cycle,
    output reg [63:0] stat_bridge_state_wait_cycle,
    output reg [63:0] stat_fetch_req_count,
    output reg [63:0] stat_fetch_resp_count,
    output reg [63:0] stat_if_pipe_issue_count,
    output reg [63:0] stat_if_pipe_resp_count,
    output reg [63:0] stat_if_pipe_epoch_drop_count,
    output reg [63:0] stat_if_pipe_replay_count,
    output reg [63:0] stat_if_pipe_ptw_miss_count,
    output reg [63:0] stat_if_pipe_ptw_fault_count,
    output reg [63:0] stat_if_pipe_stall_cycle,
    output reg [63:0] stat_if_pipe_icache_miss_count,
    output reg [63:0] stat_if_pipe_icache_replay_count
`ifdef NPC_PIPE_STAT
    ,
    output if_pipe_stat_outstanding,
    output if_pipe_stat_replay_valid,
    output if_pipe_stat_ptw_busy,
    output if_pipe_stat_req_valid,
    output if_pipe_stat_req_ready,
    output if_pipe_stat_resp_current,
    output if_pipe_stat_resp_stale,
    output if_pipe_stat_lower_req_valid,
    output if_pipe_stat_lower_req_ready,
    output if_pipe_stat_lower_resp_valid,
    output if_pipe_stat_lower_resp_ready
`endif
);
    localparam [1:0] PRIV_M = 2'b11;
    localparam [2:0] PTW_IDLE    = 3'd0;
    localparam [2:0] PTW_L1_REQ  = 3'd1;
    localparam [2:0] PTW_L1_WAIT = 3'd2;
    localparam [2:0] PTW_L0_REQ  = 3'd3;
    localparam [2:0] PTW_L0_WAIT = 3'd4;

    reg [31:0] seq_r;
    reg [15:0] epoch_r;
    reg outstanding_r;
    reg [3:0] in_flight_count_r;
    reg [31:0] expected_seq_r;
    reg [15:0] expected_epoch_r;
    reg [31:0] seq_fifo [0:3];
    reg [15:0] epoch_fifo [0:3];
    reg [1:0] seq_fifo_head_r;
    reg [1:0] seq_fifo_tail_r;
    reg [2:0] ptw_state_r;
    reg ptw_drop_resp_r;
    reg replay_valid_r;
    reg replay_exception_r;
    reg [31:0] replay_pc_r;
    reg [31:0] replay_paddr_r;
    reg [31:0] replay_seq_r;
    reg [15:0] replay_epoch_r;
    reg replay_pred_taken_r;
    reg [31:0] replay_pred_target_r;
    reg replay_pred_btb_hit_r;
    reg replay_pred_btb_is_cond_r;
    reg [1:0] replay_pred_bht_state_r;
    reg [31:0] replay_pred_pht_idx_r;
    reg [1:0] replay_priv_r;
    reg [31:0] replay_exc_cause_r;
    reg [31:0] replay_exc_tval_r;
    reg [31:0] miss_pc_va_r;
    reg [9:0] miss_vpn0_r;
    reg [31:0] miss_seq_r;
    reg [15:0] miss_epoch_r;
    reg miss_pred_taken_r;
    reg [31:0] miss_pred_target_r;
    reg miss_pred_btb_hit_r;
    reg miss_pred_btb_is_cond_r;
    reg [1:0] miss_pred_bht_state_r;
    reg [31:0] miss_pred_pht_idx_r;
    reg [1:0] miss_priv_r;
    reg [31:0] ptw_addr_r;
    reg walk_level_r;
    reg [31:0] ptw_refill_vaddr_r;
    reg [31:0] ptw_refill_pte_r;
    reg ptw_refill_level_r;
    reg ptw_refill_valid_r;

    wire req_translate_normal = (`NPC_HAS_MMU != 0) && satp_i[31] && (priv_i != PRIV_M);
`ifdef NPC_FORCE_MMU_BYPASS
    wire req_translate = 1'b0;
`elsif NPC_FORCE_MMU_TRANSLATE
    wire req_translate = satp_i[31];
`else
    wire req_translate = req_translate_normal;
`endif

    wire itlb_enabled = (`NPC_HAS_ITLB != 0);
    wire ptw_busy = (ptw_state_r != PTW_IDLE) || ptw_drop_resp_r;
    wire has_in_flight = (in_flight_count_r != 4'd0);
    wire issue_slot_available = (in_flight_count_r < 4'd4);
    wire slow_busy = replay_valid_r || ptw_busy;
    wire pipe_busy = slow_busy;
    wire itlb_lookup_valid = cpu_req_valid && !flush && req_translate && itlb_enabled && !slow_busy;
    wire itlb_lookup_hit;
    wire [31:0] itlb_lookup_paddr;
    wire [31:0] itlb_lookup_pte;
    wire itlb_lookup_level;

    function fetch_perm_ok;
        input [1:0] cur_priv;
        input [31:0] pte;
        begin
            fetch_perm_ok = pte[6] && pte[3] &&
                ((cur_priv == 2'b00) ? pte[4] : !pte[4]);
        end
    endfunction

    function [31:0] make_pte_addr;
        input [31:0] base;
        input [31:0] vpn;
        begin
            make_pte_addr = base + {20'b0, vpn[9:0], 2'b00};
        end
    endfunction

    function [31:0] make_pte_base;
        input [31:0] pte;
        reg [33:0] base34;
        begin
            base34 = {pte[31:10], 12'b0};
            make_pte_base = base34[31:0];
        end
    endfunction

    function [31:0] make_satp_base;
        input [31:0] satp;
        reg [33:0] base34;
        begin
            base34 = {satp[21:0], 12'b0};
            make_satp_base = base34[31:0];
        end
    endfunction

    function [31:0] make_phys_addr;
        input [31:0] pte;
        input [9:0] vpn0;
        input [11:0] offset;
        reg [33:0] addr34;
        begin
            addr34 = {pte[31:20], vpn0, offset};
            make_phys_addr = addr34[31:0];
        end
    endfunction

    wire itlb_perm_ok = fetch_perm_ok(priv_i, itlb_lookup_pte);
    wire can_issue_bypass = !req_translate;
    wire can_issue_itlb_hit = req_translate && itlb_enabled && itlb_lookup_hit;
    wire can_issue_fast = cpu_req_valid && !flush && !slow_busy && issue_slot_available &&
        (can_issue_bypass || can_issue_itlb_hit);
    wire can_accept_itlb_miss = cpu_req_valid && !flush && !slow_busy && !has_in_flight &&
        req_translate && (!itlb_enabled || !itlb_lookup_hit);
    wire replay_issue = replay_valid_r;
    wire can_issue = can_issue_fast || replay_issue;
    wire fast_exception = can_issue_itlb_hit && !itlb_perm_ok;
    wire issue_exception = replay_issue ? replay_exception_r : fast_exception;
    wire [31:0] issue_paddr =
        replay_issue ? replay_paddr_r :
        can_issue_bypass ? cpu_req_vaddr :
        itlb_lookup_paddr;
    wire [31:0] issue_vaddr = replay_issue ? replay_pc_r : cpu_req_vaddr;
    wire [31:0] issue_seq = replay_issue ? replay_seq_r : seq_r;
    wire [15:0] issue_epoch = replay_issue ? replay_epoch_r : epoch_r;
    wire issue_pred_taken = replay_issue ? replay_pred_taken_r : cpu_req_pred_taken;
    wire [31:0] issue_pred_target = replay_issue ? replay_pred_target_r : cpu_req_pred_target;
    wire issue_pred_btb_hit = replay_issue ? replay_pred_btb_hit_r : cpu_req_pred_btb_hit;
    wire issue_pred_btb_is_cond = replay_issue ? replay_pred_btb_is_cond_r : cpu_req_pred_btb_is_cond;
    wire [1:0] issue_pred_bht_state = replay_issue ? replay_pred_bht_state_r : cpu_req_pred_bht_state;
    wire [31:0] issue_pred_pht_idx = replay_issue ? replay_pred_pht_idx_r : cpu_req_pred_pht_idx;
    wire [1:0] issue_priv = replay_issue ? replay_priv_r : priv_i;
    wire [31:0] issue_exc_cause = replay_issue ? replay_exc_cause_r : 32'd12;
    wire [31:0] issue_exc_tval = replay_issue ? replay_exc_tval_r : cpu_req_vaddr;

    assign pipe_req_valid = can_issue;
    assign pipe_req_paddr = issue_paddr;
    assign pipe_req_vaddr = issue_vaddr;
    assign pipe_req_pc = issue_vaddr;
    assign pipe_req_seq = issue_seq;
    assign pipe_req_epoch = issue_epoch;
    assign pipe_req_pred_taken = issue_pred_taken;
    assign pipe_req_pred_target = issue_pred_target;
    assign pipe_req_pred_btb_hit = issue_pred_btb_hit;
    assign pipe_req_pred_btb_is_cond = issue_pred_btb_is_cond;
    assign pipe_req_pred_bht_state = issue_pred_bht_state;
    assign pipe_req_pred_pht_idx = issue_pred_pht_idx;
    assign pipe_req_priv = issue_priv;
    assign pipe_req_exception_valid = issue_exception;
    assign pipe_req_exception_cause = issue_exc_cause;
    assign pipe_req_exception_tval = issue_exc_tval;

    wire pipe_req_fire = pipe_req_valid && pipe_req_ready;
    wire replay_pipe_req_fire = pipe_req_fire && replay_issue;
    wire itlb_miss_fire = can_accept_itlb_miss;
    assign cpu_req_ready = (can_issue_fast && pipe_req_ready) || can_accept_itlb_miss;

    wire pipe_resp_current = pipe_resp_valid && (pipe_resp_epoch == epoch_r);
    wire pipe_resp_stale = pipe_resp_valid && (pipe_resp_epoch != epoch_r);
    wire pipe_resp_fire_current = pipe_resp_current && cpu_resp_ready;
    wire pipe_resp_drop_fire = pipe_resp_stale && pipe_resp_ready;

    assign cpu_resp_valid = pipe_resp_current;
    assign cpu_resp_rdata = pipe_resp_instr;
    assign cpu_resp_exc_valid = pipe_resp_exception_valid;
    assign cpu_resp_exc_cause = pipe_resp_exception_cause;
    assign cpu_resp_exc_tval = pipe_resp_exception_tval;
    assign cpu_resp_pc = pipe_resp_pc;
    assign cpu_resp_seq = pipe_resp_seq;
    assign cpu_resp_epoch = pipe_resp_epoch;
    assign cpu_resp_pred_taken = pipe_resp_pred_taken;
    assign cpu_resp_pred_target = pipe_resp_pred_target;
    assign cpu_resp_pred_btb_hit = pipe_resp_pred_btb_hit;
    assign cpu_resp_pred_btb_is_cond = pipe_resp_pred_btb_is_cond;
    assign cpu_resp_pred_bht_state = pipe_resp_pred_bht_state;
    assign cpu_resp_pred_pht_idx = pipe_resp_pred_pht_idx;
    assign pipe_resp_ready = pipe_resp_stale ? 1'b1 : (pipe_resp_current && cpu_resp_ready);

    wire lower_req_fire = lower_req_valid && lower_req_ready;
    wire lower_resp_fire = lower_resp_valid && lower_resp_ready;
    wire ptw_req_state = (ptw_state_r == PTW_L1_REQ) || (ptw_state_r == PTW_L0_REQ);
    wire ptw_wait_state = (ptw_state_r == PTW_L1_WAIT) || (ptw_state_r == PTW_L0_WAIT);
    assign lower_req_valid = ptw_req_state;
    assign lower_req_addr = ptw_addr_r;
    assign lower_resp_ready = ptw_drop_resp_r || ptw_wait_state;

`ifdef NPC_PIPE_STAT
    assign if_pipe_stat_outstanding = has_in_flight;
    assign if_pipe_stat_replay_valid = replay_valid_r;
    assign if_pipe_stat_ptw_busy = ptw_busy;
    assign if_pipe_stat_req_valid = pipe_req_valid;
    assign if_pipe_stat_req_ready = pipe_req_ready;
    assign if_pipe_stat_resp_current = pipe_resp_current;
    assign if_pipe_stat_resp_stale = pipe_resp_stale;
    assign if_pipe_stat_lower_req_valid = lower_req_valid;
    assign if_pipe_stat_lower_req_ready = lower_req_ready;
    assign if_pipe_stat_lower_resp_valid = lower_resp_valid;
    assign if_pipe_stat_lower_resp_ready = lower_resp_ready;
`endif

    wire [31:0] pte_word = lower_resp_rdata;
    wire pte_v = pte_word[0];
    wire pte_r_bit = pte_word[1];
    wire pte_w_bit = pte_word[2];
    wire pte_leaf = pte_word[1] || pte_word[3];
    wire pte_invalid = !pte_v || (!pte_r_bit && pte_w_bit);
    wire pte_superpage_misaligned =
        (walk_level_r == 1'b1) && (pte_word[19:10] != 10'b0);
    wire pte_perm_ok = fetch_perm_ok(miss_priv_r, pte_word);
    wire ptw_leaf_success =
        lower_resp_fire && ptw_wait_state &&
        !pte_invalid && pte_leaf && !pte_superpage_misaligned && pte_perm_ok;
    wire itlb_refill_valid = ptw_refill_valid_r;

    Sv32Tlb #(
        .ENTRY_COUNT(`NPC_ITLB_ENTRIES)
    ) u_itlb (
        .clk(clk),
        .rst_n(rst_n),
        .flush_all(tlb_flush_all),
        .lookup_valid(itlb_lookup_valid),
        .lookup_vaddr(cpu_req_vaddr),
        .lookup_hit(itlb_lookup_hit),
        .lookup_paddr(itlb_lookup_paddr),
        .lookup_pte(itlb_lookup_pte),
        .lookup_level(itlb_lookup_level),
        .refill_valid(itlb_refill_valid),
        .refill_vaddr(ptw_refill_vaddr_r),
        .refill_pte(ptw_refill_pte_r),
        .refill_level(ptw_refill_level_r)
    );

    wire [31:0] expected_seq_now = seq_fifo[seq_fifo_head_r];
    wire [15:0] expected_epoch_now = epoch_fifo[seq_fifo_head_r];
    wire seq_mismatch = pipe_resp_fire_current &&
        ((in_flight_count_r == 4'd0) ||
         (pipe_resp_seq != expected_seq_now) ||
         (pipe_resp_epoch != expected_epoch_now));

    integer fifo_i;

    always @(posedge clk) begin
        if (!rst_n) begin
            seq_r <= 32'd1;
            epoch_r <= 16'd1;
            outstanding_r <= 1'b0;
            in_flight_count_r <= 4'd0;
            expected_seq_r <= 32'b0;
            expected_epoch_r <= 16'b0;
            seq_fifo_head_r <= 2'b0;
            seq_fifo_tail_r <= 2'b0;
            for (fifo_i = 0; fifo_i < 4; fifo_i = fifo_i + 1) begin
                seq_fifo[fifo_i] <= 32'b0;
                epoch_fifo[fifo_i] <= 16'b0;
            end
            ptw_state_r <= PTW_IDLE;
            ptw_drop_resp_r <= 1'b0;
            replay_valid_r <= 1'b0;
            replay_exception_r <= 1'b0;
            replay_pc_r <= 32'b0;
            replay_paddr_r <= 32'b0;
            replay_seq_r <= 32'b0;
            replay_epoch_r <= 16'b0;
            replay_pred_taken_r <= 1'b0;
            replay_pred_target_r <= 32'b0;
            replay_pred_btb_hit_r <= 1'b0;
            replay_pred_btb_is_cond_r <= 1'b0;
            replay_pred_bht_state_r <= 2'b0;
            replay_pred_pht_idx_r <= 32'b0;
            replay_priv_r <= 2'b0;
            replay_exc_cause_r <= 32'b0;
            replay_exc_tval_r <= 32'b0;
            miss_pc_va_r <= 32'b0;
            miss_vpn0_r <= 10'b0;
            miss_seq_r <= 32'b0;
            miss_epoch_r <= 16'b0;
            miss_pred_taken_r <= 1'b0;
            miss_pred_target_r <= 32'b0;
            miss_pred_btb_hit_r <= 1'b0;
            miss_pred_btb_is_cond_r <= 1'b0;
            miss_pred_bht_state_r <= 2'b0;
            miss_pred_pht_idx_r <= 32'b0;
            miss_priv_r <= 2'b0;
            ptw_addr_r <= 32'b0;
            walk_level_r <= 1'b0;
            ptw_refill_vaddr_r <= 32'b0;
            ptw_refill_pte_r <= 32'b0;
            ptw_refill_level_r <= 1'b0;
            ptw_refill_valid_r <= 1'b0;
            stat_req_count <= 64'd0;
            stat_bypass_count <= 64'd0;
            stat_translate_count <= 64'd0;
            stat_ptw_cycle_count <= 64'd0;
            stat_ptw_l1_read_count <= 64'd0;
            stat_ptw_l0_read_count <= 64'd0;
            stat_page_fault_count <= 64'd0;
            stat_ptw_walk_start_count <= 64'd0;
            stat_ptw_walk_done_count <= 64'd0;
            stat_ptw_walk_fault_count <= 64'd0;
            stat_tlb_hit_count <= 64'd0;
            stat_tlb_miss_count <= 64'd0;
            stat_tlb_hit_to_cache_req_cycle <= 64'd0;
            stat_cache_req_wait_cycle <= 64'd0;
            stat_cache_resp_wait_cycle <= 64'd0;
            stat_bridge_state_wait_cycle <= 64'd0;
            stat_fetch_req_count <= 64'd0;
            stat_fetch_resp_count <= 64'd0;
            stat_if_pipe_issue_count <= 64'd0;
            stat_if_pipe_resp_count <= 64'd0;
            stat_if_pipe_epoch_drop_count <= 64'd0;
            stat_if_pipe_replay_count <= 64'd0;
            stat_if_pipe_ptw_miss_count <= 64'd0;
            stat_if_pipe_ptw_fault_count <= 64'd0;
            stat_if_pipe_stall_cycle <= 64'd0;
            stat_if_pipe_icache_miss_count <= 64'd0;
            stat_if_pipe_icache_replay_count <= 64'd0;
        end else begin
            if (flush) begin
                epoch_r <= epoch_r + 16'd1;
                outstanding_r <= 1'b0;
                in_flight_count_r <= 4'd0;
                expected_seq_r <= 32'b0;
                expected_epoch_r <= 16'b0;
                seq_fifo_head_r <= 2'b0;
                seq_fifo_tail_r <= 2'b0;
                replay_valid_r <= 1'b0;
                replay_exception_r <= 1'b0;
                replay_pred_taken_r <= 1'b0;
                replay_pred_target_r <= 32'b0;
                replay_pred_btb_hit_r <= 1'b0;
                replay_pred_btb_is_cond_r <= 1'b0;
                replay_pred_bht_state_r <= 2'b0;
                replay_pred_pht_idx_r <= 32'b0;
                ptw_refill_valid_r <= 1'b0;
                if (lower_req_fire || (ptw_wait_state && !lower_resp_fire)) begin
                    ptw_state_r <= PTW_IDLE;
                    ptw_drop_resp_r <= 1'b1;
                    stat_if_pipe_epoch_drop_count <= stat_if_pipe_epoch_drop_count + 64'd1;
                end else if (ptw_drop_resp_r && lower_resp_fire) begin
                    ptw_state_r <= PTW_IDLE;
                    ptw_drop_resp_r <= 1'b0;
                end else begin
                    ptw_state_r <= PTW_IDLE;
                end
`ifdef NPC_IF_PIPE_DBG
                if (ptw_busy || replay_valid_r || has_in_flight) begin
                    $display("[IFPipeDbg] flush epoch=%0d next_epoch=%0d ptw_state=%0d miss_seq=%0d miss_pc=0x%08x",
                        epoch_r, epoch_r + 16'd1, ptw_state_r, miss_seq_r, miss_pc_va_r);
                end
`endif
            end else begin
                ptw_refill_valid_r <= 1'b0;

                if ((ptw_state_r == PTW_L1_REQ) || (ptw_state_r == PTW_L1_WAIT) ||
                    (ptw_state_r == PTW_L0_REQ) || (ptw_state_r == PTW_L0_WAIT)) begin
                    stat_ptw_cycle_count <= stat_ptw_cycle_count + 64'd1;
                end

                if (ptw_drop_resp_r && lower_resp_fire) begin
                    ptw_drop_resp_r <= 1'b0;
`ifdef NPC_IF_PIPE_DBG
                    $display("[IFPipeDbg] miss_epoch_drop seq=%0d pc=0x%08x old_epoch=%0d current_epoch=%0d",
                        miss_seq_r, miss_pc_va_r, miss_epoch_r, epoch_r);
`endif
                end

                if (itlb_miss_fire) begin
                    miss_pc_va_r <= cpu_req_vaddr;
                    miss_vpn0_r <= cpu_req_vaddr[21:12];
                    miss_seq_r <= seq_r;
                    miss_epoch_r <= epoch_r;
                    miss_pred_taken_r <= cpu_req_pred_taken;
                    miss_pred_target_r <= cpu_req_pred_target;
                    miss_pred_btb_hit_r <= cpu_req_pred_btb_hit;
                    miss_pred_btb_is_cond_r <= cpu_req_pred_btb_is_cond;
                    miss_pred_bht_state_r <= cpu_req_pred_bht_state;
                    miss_pred_pht_idx_r <= cpu_req_pred_pht_idx;
                    miss_priv_r <= priv_i;
                    walk_level_r <= 1'b1;
                    ptw_addr_r <= make_pte_addr(make_satp_base(satp_i), {22'b0, cpu_req_vaddr[31:22]});
                    ptw_state_r <= PTW_L1_REQ;
                    seq_r <= seq_r + 32'd1;
                    stat_req_count <= stat_req_count + 64'd1;
                    stat_translate_count <= stat_translate_count + 64'd1;
                    if (itlb_enabled) begin
                        stat_tlb_miss_count <= stat_tlb_miss_count + 64'd1;
                    end
                    stat_ptw_walk_start_count <= stat_ptw_walk_start_count + 64'd1;
                    stat_if_pipe_ptw_miss_count <= stat_if_pipe_ptw_miss_count + 64'd1;
`ifdef NPC_IF_PIPE_DBG
                    $display("[IFPipeDbg] itlb_miss seq=%0d pc=0x%08x epoch=%0d satp=0x%08x priv=%0d pte_addr=0x%08x",
                        seq_r, cpu_req_vaddr, epoch_r, satp_i, priv_i,
                        make_pte_addr(make_satp_base(satp_i), {22'b0, cpu_req_vaddr[31:22]}));
`endif
                end

                if (lower_req_fire && (ptw_state_r == PTW_L1_REQ)) begin
                    ptw_state_r <= PTW_L1_WAIT;
                    stat_ptw_l1_read_count <= stat_ptw_l1_read_count + 64'd1;
`ifdef NPC_IF_PIPE_DBG
                    $display("[IFPipeDbg] ptw_l1_req seq=%0d pte_addr=0x%08x",
                        miss_seq_r, ptw_addr_r);
`endif
                end else if (lower_req_fire && (ptw_state_r == PTW_L0_REQ)) begin
                    ptw_state_r <= PTW_L0_WAIT;
                    stat_ptw_l0_read_count <= stat_ptw_l0_read_count + 64'd1;
`ifdef NPC_IF_PIPE_DBG
                    $display("[IFPipeDbg] ptw_l0_req seq=%0d pte_addr=0x%08x",
                        miss_seq_r, ptw_addr_r);
`endif
                end

                if (lower_resp_fire && ptw_wait_state) begin
`ifdef NPC_IF_PIPE_DBG
                    if (walk_level_r) begin
                        $display("[IFPipeDbg] ptw_l1_resp seq=%0d pte=0x%08x",
                            miss_seq_r, pte_word);
                    end else begin
                        $display("[IFPipeDbg] ptw_l0_resp seq=%0d pte=0x%08x",
                            miss_seq_r, pte_word);
                    end
`endif
                    if (pte_invalid) begin
                        ptw_state_r <= PTW_IDLE;
                        stat_page_fault_count <= stat_page_fault_count + 64'd1;
                        stat_ptw_walk_fault_count <= stat_ptw_walk_fault_count + 64'd1;
                        stat_if_pipe_ptw_fault_count <= stat_if_pipe_ptw_fault_count + 64'd1;
                        if (miss_epoch_r == epoch_r) begin
                            replay_valid_r <= 1'b1;
                            replay_exception_r <= 1'b1;
                            replay_pc_r <= miss_pc_va_r;
                            replay_paddr_r <= 32'b0;
                            replay_seq_r <= miss_seq_r;
                            replay_epoch_r <= miss_epoch_r;
                            replay_pred_taken_r <= miss_pred_taken_r;
                            replay_pred_target_r <= miss_pred_target_r;
                            replay_pred_btb_hit_r <= miss_pred_btb_hit_r;
                            replay_pred_btb_is_cond_r <= miss_pred_btb_is_cond_r;
                            replay_pred_bht_state_r <= miss_pred_bht_state_r;
                            replay_pred_pht_idx_r <= miss_pred_pht_idx_r;
                            replay_priv_r <= miss_priv_r;
                            replay_exc_cause_r <= 32'd12;
                            replay_exc_tval_r <= miss_pc_va_r;
                            stat_if_pipe_replay_count <= stat_if_pipe_replay_count + 64'd1;
`ifdef NPC_IF_PIPE_DBG
                            $display("[IFPipeDbg] ptw_fault seq=%0d pc=0x%08x cause=0x0000000c tval=0x%08x reason=invalid",
                                miss_seq_r, miss_pc_va_r, miss_pc_va_r);
`endif
                        end
                    end else if (pte_leaf) begin
                        if (pte_superpage_misaligned || !pte_perm_ok) begin
                            ptw_state_r <= PTW_IDLE;
                            stat_page_fault_count <= stat_page_fault_count + 64'd1;
                            stat_ptw_walk_fault_count <= stat_ptw_walk_fault_count + 64'd1;
                            stat_if_pipe_ptw_fault_count <= stat_if_pipe_ptw_fault_count + 64'd1;
                            if (miss_epoch_r == epoch_r) begin
                                replay_valid_r <= 1'b1;
                                replay_exception_r <= 1'b1;
                                replay_pc_r <= miss_pc_va_r;
                                replay_paddr_r <= 32'b0;
                                replay_seq_r <= miss_seq_r;
                                replay_epoch_r <= miss_epoch_r;
                                replay_pred_taken_r <= miss_pred_taken_r;
                                replay_pred_target_r <= miss_pred_target_r;
                                replay_pred_btb_hit_r <= miss_pred_btb_hit_r;
                                replay_pred_btb_is_cond_r <= miss_pred_btb_is_cond_r;
                                replay_pred_bht_state_r <= miss_pred_bht_state_r;
                                replay_pred_pht_idx_r <= miss_pred_pht_idx_r;
                                replay_priv_r <= miss_priv_r;
                                replay_exc_cause_r <= 32'd12;
                                replay_exc_tval_r <= miss_pc_va_r;
                                stat_if_pipe_replay_count <= stat_if_pipe_replay_count + 64'd1;
`ifdef NPC_IF_PIPE_DBG
                                $display("[IFPipeDbg] ptw_fault seq=%0d pc=0x%08x cause=0x0000000c tval=0x%08x reason=perm_or_superpage",
                                    miss_seq_r, miss_pc_va_r, miss_pc_va_r);
`endif
                            end
                        end else begin
                            ptw_state_r <= PTW_IDLE;
                            stat_ptw_walk_done_count <= stat_ptw_walk_done_count + 64'd1;
                            ptw_refill_valid_r <= itlb_enabled;
                            ptw_refill_vaddr_r <= miss_pc_va_r;
                            ptw_refill_pte_r <= pte_word;
                            ptw_refill_level_r <= walk_level_r;
                            if (miss_epoch_r == epoch_r) begin
                                replay_valid_r <= 1'b1;
                                replay_exception_r <= 1'b0;
                                replay_pc_r <= miss_pc_va_r;
                                replay_paddr_r <= walk_level_r ?
                                    make_phys_addr(pte_word, miss_vpn0_r, miss_pc_va_r[11:0]) :
                                    make_phys_addr(pte_word, pte_word[19:10], miss_pc_va_r[11:0]);
                                replay_seq_r <= miss_seq_r;
                                replay_epoch_r <= miss_epoch_r;
                                replay_pred_taken_r <= miss_pred_taken_r;
                                replay_pred_target_r <= miss_pred_target_r;
                                replay_pred_btb_hit_r <= miss_pred_btb_hit_r;
                                replay_pred_btb_is_cond_r <= miss_pred_btb_is_cond_r;
                                replay_pred_bht_state_r <= miss_pred_bht_state_r;
                                replay_pred_pht_idx_r <= miss_pred_pht_idx_r;
                                replay_priv_r <= miss_priv_r;
                                replay_exc_cause_r <= 32'b0;
                                replay_exc_tval_r <= 32'b0;
                                stat_if_pipe_replay_count <= stat_if_pipe_replay_count + 64'd1;
                                stat_if_pipe_icache_replay_count <= stat_if_pipe_icache_replay_count + 64'd1;
`ifdef NPC_IF_PIPE_DBG
                                $display("[IFPipeDbg] itlb_refill seq=%0d pc=0x%08x ppn=0x%08x level=%0d",
                                    miss_seq_r, miss_pc_va_r, pte_word[31:10], walk_level_r);
                                $display("[IFPipeDbg] replay seq=%0d pc=0x%08x epoch=%0d paddr=0x%08x",
                                    miss_seq_r, miss_pc_va_r, miss_epoch_r,
                                    walk_level_r ?
                                        make_phys_addr(pte_word, miss_vpn0_r, miss_pc_va_r[11:0]) :
                                        make_phys_addr(pte_word, pte_word[19:10], miss_pc_va_r[11:0]));
`endif
                            end else begin
`ifdef NPC_IF_PIPE_DBG
                                $display("[IFPipeDbg] miss_epoch_drop seq=%0d pc=0x%08x old_epoch=%0d current_epoch=%0d",
                                    miss_seq_r, miss_pc_va_r, miss_epoch_r, epoch_r);
`endif
                            end
                        end
                    end else begin
                        if (walk_level_r == 1'b0) begin
                            ptw_state_r <= PTW_IDLE;
                            stat_page_fault_count <= stat_page_fault_count + 64'd1;
                            stat_ptw_walk_fault_count <= stat_ptw_walk_fault_count + 64'd1;
                            stat_if_pipe_ptw_fault_count <= stat_if_pipe_ptw_fault_count + 64'd1;
                            if (miss_epoch_r == epoch_r) begin
                                replay_valid_r <= 1'b1;
                                replay_exception_r <= 1'b1;
                                replay_pc_r <= miss_pc_va_r;
                                replay_paddr_r <= 32'b0;
                               replay_seq_r <= miss_seq_r;
                               replay_epoch_r <= miss_epoch_r;
                                replay_pred_taken_r <= miss_pred_taken_r;
                                replay_pred_target_r <= miss_pred_target_r;
                                replay_pred_btb_hit_r <= miss_pred_btb_hit_r;
                                replay_pred_btb_is_cond_r <= miss_pred_btb_is_cond_r;
                                replay_pred_bht_state_r <= miss_pred_bht_state_r;
                                replay_pred_pht_idx_r <= miss_pred_pht_idx_r;
                               replay_priv_r <= miss_priv_r;
                                replay_exc_cause_r <= 32'd12;
                                replay_exc_tval_r <= miss_pc_va_r;
                                stat_if_pipe_replay_count <= stat_if_pipe_replay_count + 64'd1;
`ifdef NPC_IF_PIPE_DBG
                                $display("[IFPipeDbg] ptw_fault seq=%0d pc=0x%08x cause=0x0000000c tval=0x%08x reason=non_leaf_l0",
                                    miss_seq_r, miss_pc_va_r, miss_pc_va_r);
`endif
                            end
                        end else begin
                            walk_level_r <= 1'b0;
                            ptw_addr_r <= make_pte_addr(make_pte_base(pte_word), {22'b0, miss_vpn0_r});
                            ptw_state_r <= PTW_L0_REQ;
                        end
                    end
                end

                if (pipe_req_fire) begin
                    stat_fetch_req_count <= stat_fetch_req_count + 64'd1;
                    stat_if_pipe_issue_count <= stat_if_pipe_issue_count + 64'd1;
                    if (replay_pipe_req_fire) begin
                        replay_valid_r <= 1'b0;
                    end else begin
                        seq_r <= seq_r + 32'd1;
                        stat_req_count <= stat_req_count + 64'd1;
                        if (req_translate) begin
                            stat_translate_count <= stat_translate_count + 64'd1;
                            stat_tlb_hit_count <= stat_tlb_hit_count + 64'd1;
                        end else begin
                            stat_bypass_count <= stat_bypass_count + 64'd1;
                        end
                    end
                    if (fast_exception) begin
                        stat_page_fault_count <= stat_page_fault_count + 64'd1;
                    end
`ifdef NPC_IF_PIPE_DBG
                    $display("[IFPipeDbg] issue seq=%0d pc=0x%08x epoch=%0d translate=%0d paddr=0x%08x exc=%0d",
                        issue_seq, issue_vaddr, issue_epoch, !can_issue_bypass, issue_paddr, issue_exception);
`endif
                end

                if (pipe_resp_fire_current) begin
                    stat_fetch_resp_count <= stat_fetch_resp_count + 64'd1;
                    stat_if_pipe_resp_count <= stat_if_pipe_resp_count + 64'd1;
                    if (pipe_resp_miss) begin
                        stat_if_pipe_icache_miss_count <= stat_if_pipe_icache_miss_count + 64'd1;
                    end
`ifdef NPC_IF_PIPE_DBG
                    $display("[IFPipeDbg] resp seq=%0d pc=0x%08x instr=0x%08x epoch=%0d exc=%0d hit=%0d miss=%0d",
                        pipe_resp_seq, pipe_resp_pc, pipe_resp_instr, pipe_resp_epoch,
                        pipe_resp_exception_valid, pipe_resp_hit, pipe_resp_miss);
`endif
                end

                if (pipe_resp_drop_fire) begin
                    stat_if_pipe_epoch_drop_count <= stat_if_pipe_epoch_drop_count + 64'd1;
`ifdef NPC_IF_PIPE_DBG
                    $display("[IFPipeDbg] epoch_drop seq=%0d pc=0x%08x epoch=%0d current=%0d",
                        pipe_resp_seq, pipe_resp_pc, pipe_resp_epoch, epoch_r);
`endif
                end

                if (pipe_req_fire && !pipe_resp_fire_current) begin
                    in_flight_count_r <= in_flight_count_r + 4'd1;
                    outstanding_r <= 1'b1;
                end else if (!pipe_req_fire && pipe_resp_fire_current) begin
                    if (in_flight_count_r != 4'd0) begin
                        in_flight_count_r <= in_flight_count_r - 4'd1;
                        outstanding_r <= (in_flight_count_r > 4'd1);
                    end else begin
                        outstanding_r <= 1'b0;
                    end
                end else if (pipe_req_fire && pipe_resp_fire_current) begin
                    outstanding_r <= 1'b1;
                end

                if (pipe_req_fire) begin
                    seq_fifo[seq_fifo_tail_r] <= issue_seq;
                    epoch_fifo[seq_fifo_tail_r] <= issue_epoch;
                    seq_fifo_tail_r <= seq_fifo_tail_r + 2'd1;
                end
                if (pipe_resp_fire_current) begin
                    seq_fifo_head_r <= seq_fifo_head_r + 2'd1;
                end

                if (pipe_resp_fire_current) begin
                    if (pipe_req_fire && (in_flight_count_r == 4'd1)) begin
                        expected_seq_r <= issue_seq;
                        expected_epoch_r <= issue_epoch;
                    end else begin
                        expected_seq_r <= expected_seq_r + 32'd1;
                    end
                end else if (pipe_req_fire && (in_flight_count_r == 4'd0)) begin
                    expected_seq_r <= issue_seq;
                    expected_epoch_r <= issue_epoch;
                end
            end

            if (pipe_req_valid && !pipe_req_ready) begin
                stat_cache_req_wait_cycle <= stat_cache_req_wait_cycle + 64'd1;
            end
            if (pipe_resp_current && !cpu_resp_ready) begin
                stat_cache_resp_wait_cycle <= stat_cache_resp_wait_cycle + 64'd1;
            end
            if ((has_in_flight && !pipe_resp_current) || ptw_busy || replay_valid_r) begin
                stat_bridge_state_wait_cycle <= stat_bridge_state_wait_cycle + 64'd1;
                stat_if_pipe_stall_cycle <= stat_if_pipe_stall_cycle + 64'd1;
            end

            if (seq_mismatch) begin
                $display("[IFPipeDbg] seq_mismatch expected_seq=%0d got_seq=%0d expected_epoch=%0d got_epoch=%0d pc=0x%08x instr=0x%08x",
                    expected_seq_now, pipe_resp_seq, expected_epoch_now, pipe_resp_epoch,
                    pipe_resp_pc, pipe_resp_instr);
                $fatal;
            end
        end
    end

    wire unused_itlb_lookup_level = itlb_lookup_level;
    wire unused_ptw_leaf_success = ptw_leaf_success;
endmodule
