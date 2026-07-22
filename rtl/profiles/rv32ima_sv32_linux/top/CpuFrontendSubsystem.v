`timescale 1ns / 1ps

module CpuFrontendSubsystem #(
    parameter integer ICACHE_LINE_BYTES = 64,
    parameter integer ICACHE_LINE_COUNT = 64
) (
    input clk,
    input rst_n,

    input redirect_flush_valid,
    input stop_clear_valid,
    input tlb_flush_all,
    input [1:0] priv_state,
    input [31:0] csr_satp,

    input ibus_req_valid_w,
    output ibus_req_ready,
    input [31:0] ibus_req_addr_w,
    input ibus_req_pred_taken,
    input [31:0] ibus_req_pred_target,
    input ibus_req_pred_btb_hit,
    input ibus_req_pred_btb_is_cond,
    input [1:0] ibus_req_pred_bht_state,
    input [31:0] ibus_req_pred_pht_idx,

    output ibus_resp_valid,
    input ibus_resp_ready_w,
    output [31:0] ibus_resp_data,
    output ibus_resp_exc_valid,
    output [31:0] ibus_resp_exc_cause,
    output [31:0] ibus_resp_exc_tval,
    output [31:0] ibus_resp_pc,
    output [31:0] ibus_resp_seq,
    output [15:0] ibus_resp_epoch,
    output ibus_resp_pred_taken,
    output [31:0] ibus_resp_pred_target,
    output ibus_resp_pred_btb_hit,
    output ibus_resp_pred_btb_is_cond,
    output [1:0] ibus_resp_pred_bht_state,
    output [31:0] ibus_resp_pred_pht_idx,

    output ibus_icache_pipe_resp_valid,
    output ibus_icache_pipe_resp_ready,

    input icache_maint_inv_req,
    output icache_maint_inv_done,

    output ibus_mem_req_valid,
    input ibus_mem_req_ready,
    output ibus_mem_req_write,
    output [31:0] ibus_mem_req_addr,
    output [31:0] ibus_mem_req_wdata,
    output [3:0] ibus_mem_req_wstrb,
    output [2:0] ibus_mem_req_len,
    input ibus_mem_resp_valid,
    output ibus_mem_resp_ready,
    input [31:0] ibus_mem_resp_data,

    output [63:0] if_mmu_req_count,
    output [63:0] if_mmu_bypass_count,
    output [63:0] if_mmu_translate_count,
    output [63:0] if_mmu_ptw_cycle_count,
    output [63:0] if_mmu_ptw_l1_read_count,
    output [63:0] if_mmu_ptw_l0_read_count,
    output [63:0] if_mmu_page_fault_count,
    output [63:0] if_mmu_ptw_walk_start_count,
    output [63:0] if_mmu_ptw_walk_done_count,
    output [63:0] if_mmu_ptw_walk_fault_count,
    output [63:0] if_mmu_tlb_hit_count,
    output [63:0] if_mmu_tlb_miss_count,
    output [63:0] if_mmu_tlb_hit_to_cache_req_cycle,
    output [63:0] if_mmu_cache_req_wait_cycle,
    output [63:0] if_mmu_cache_resp_wait_cycle,
    output [63:0] if_mmu_bridge_state_wait_cycle,
    output [63:0] if_mmu_fetch_req_count,
    output [63:0] if_mmu_fetch_resp_count,
    output [63:0] if_pipe_issue_count,
    output [63:0] if_pipe_resp_count,
    output [63:0] if_pipe_epoch_drop_count,
    output [63:0] if_pipe_replay_count,
    output [63:0] if_pipe_ptw_miss_count,
    output [63:0] if_pipe_ptw_fault_count,
    output [63:0] if_pipe_stall_cycle,
    output [63:0] if_pipe_icache_miss_count,
    output [63:0] if_pipe_icache_replay_count
`ifdef NPC_PIPE_STAT
    , output if_pipe_stat_outstanding
    , output if_pipe_stat_replay_valid
    , output if_pipe_stat_ptw_busy
    , output if_pipe_stat_req_valid
    , output if_pipe_stat_req_ready
    , output if_pipe_stat_resp_current
    , output if_pipe_stat_resp_stale
    , output if_pipe_stat_lower_req_valid
    , output if_pipe_stat_lower_req_ready
    , output if_pipe_stat_lower_resp_valid
    , output if_pipe_stat_lower_resp_ready
`endif
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
    , output [63:0] icache_stat_access
    , output [63:0] icache_stat_hit
    , output [63:0] icache_stat_miss
    , output [63:0] icache_stat_refill_req
    , output [63:0] icache_stat_refill_resp
    , output [63:0] icache_stat_refill_bypass
    , output [63:0] icache_stat_req_wait_cycle
    , output [63:0] icache_stat_hit_resp_wait_cycle
    , output [63:0] icache_stat_miss_wait_cycle
    , output [63:0] icache_stat_uncached_access
    , output [63:0] icache_pipe_req_valid_cycle
    , output [63:0] icache_pipe_req_ready_cycle
    , output [63:0] icache_pipe_req_fire_cycle
    , output [63:0] icache_pipe_req_valid_not_ready_cycle
    , output [63:0] icache_pipe_resp_valid_cycle
    , output [63:0] icache_pipe_resp_ready_cycle
    , output [63:0] icache_pipe_resp_fire_cycle
    , output [63:0] icache_pipe_data_valid_cycle
    , output [63:0] icache_pipe_resp_block_cycle
    , output [63:0] icache_pipe_ready_block_state_cycle
    , output [63:0] icache_pipe_ready_block_data_cycle
    , output [63:0] icache_pipe_ready_block_resp_cycle
    , output [63:0] icache_pipe_ready_block_cpu_cycle
    , output [63:0] icache_pipe_ready_block_maint_cycle
    , output [63:0] icache_pipe_state_idle_cycle
    , output [63:0] icache_pipe_state_refill_cycle
    , output [63:0] icache_pipe_state_uncached_cycle
    , output [63:0] icache_pipe_hit_fire_cycle
    , output [63:0] icache_pipe_miss_fire_cycle
    , output [63:0] icache_pipe_refill_busy_cycle
    , output [63:0] icache_pipe_resp_fifo_full_cycle
`endif
`endif
);
    localparam integer ICACHE_LINE_WORDS = ICACHE_LINE_BYTES / 4;
    localparam [4:0] ICACHE_LINE_BEATS =
        (ICACHE_LINE_WORDS == 16) ? 5'd16 :
        (ICACHE_LINE_WORDS == 8)  ? 5'd8  :
        (ICACHE_LINE_WORDS == 4)  ? 5'd4  :
        (ICACHE_LINE_WORDS == 2)  ? 5'd2  :
                                    5'd1;

    wire [31:0] ibus_req_vaddr_w;
    wire [31:0] ibus_req_paddr_w;
    wire ibus_icache_req_valid;
    wire ibus_icache_req_ready;
    wire ibus_icache_resp_valid;
    wire ibus_icache_resp_ready;
    wire [31:0] ibus_icache_resp_data;
    wire ibus_icache_lookup_hit;
    wire ibus_icache_lookup_uncached;
    wire ibus_ptw_req_valid;
    wire ibus_ptw_req_ready;
    wire [31:0] ibus_ptw_req_addr;
    wire ibus_ptw_resp_valid;
    wire ibus_ptw_resp_ready;
    wire [31:0] ibus_ptw_resp_data;
    wire ibus_icache_pipe_req_valid;
    wire ibus_icache_pipe_req_ready;
    wire [31:0] ibus_icache_pipe_req_paddr;
    wire [31:0] ibus_icache_pipe_req_vaddr;
    wire [31:0] ibus_icache_pipe_req_pc;
    wire [31:0] ibus_icache_pipe_req_seq;
    wire [15:0] ibus_icache_pipe_req_epoch;
    wire ibus_icache_pipe_req_pred_taken;
    wire [31:0] ibus_icache_pipe_req_pred_target;
    wire ibus_icache_pipe_req_pred_btb_hit;
    wire ibus_icache_pipe_req_pred_btb_is_cond;
    wire [1:0] ibus_icache_pipe_req_pred_bht_state;
    wire [31:0] ibus_icache_pipe_req_pred_pht_idx;
    wire [1:0] ibus_icache_pipe_req_priv;
    wire ibus_icache_pipe_req_exception_valid;
    wire [31:0] ibus_icache_pipe_req_exception_cause;
    wire [31:0] ibus_icache_pipe_req_exception_tval;
    wire [31:0] ibus_icache_pipe_resp_instr;
    wire [31:0] ibus_icache_pipe_resp_pc;
    wire [31:0] ibus_icache_pipe_resp_seq;
    wire [15:0] ibus_icache_pipe_resp_epoch;
    wire ibus_icache_pipe_resp_pred_taken;
    wire [31:0] ibus_icache_pipe_resp_pred_target;
    wire ibus_icache_pipe_resp_pred_btb_hit;
    wire ibus_icache_pipe_resp_pred_btb_is_cond;
    wire [1:0] ibus_icache_pipe_resp_pred_bht_state;
    wire [31:0] ibus_icache_pipe_resp_pred_pht_idx;
    wire ibus_icache_pipe_resp_exception_valid;
    wire [31:0] ibus_icache_pipe_resp_exception_cause;
    wire [31:0] ibus_icache_pipe_resp_exception_tval;
    wire ibus_icache_pipe_resp_hit;
    wire ibus_icache_pipe_resp_miss;
    wire ibus_icache_mem_req_valid;
    wire ibus_icache_mem_req_ready;
    wire ibus_icache_mem_req_write;
    wire [31:0] ibus_icache_mem_req_addr;
    wire [31:0] ibus_icache_mem_req_wdata;
    wire [3:0] ibus_icache_mem_req_wstrb;
    wire [2:0] ibus_icache_mem_req_len;
    wire ibus_icache_mem_resp_valid;
    wire ibus_icache_mem_resp_ready;
    wire [31:0] ibus_icache_mem_resp_data;

    reg ibus_mem_owner_valid;
    reg ibus_mem_owner_ptw;
    reg [4:0] ibus_mem_resp_left;
    wire ibus_mem_idle = !ibus_mem_owner_valid;
    wire ibus_icache_mem_grant = ibus_mem_idle && ibus_icache_mem_req_valid;
    wire ibus_ptw_mem_grant = ibus_mem_idle && !ibus_icache_mem_req_valid && ibus_ptw_req_valid;
    wire ibus_mem_req_fire = ibus_mem_req_valid && ibus_mem_req_ready;
    wire ibus_mem_resp_fire = ibus_mem_resp_valid && ibus_mem_resp_ready;
    wire [4:0] ibus_mem_req_beats =
        (ibus_mem_req_len == 3'd0) ? ICACHE_LINE_BEATS : 5'd1;

    assign ibus_req_vaddr_w = ibus_req_addr_w;

`ifdef NPC_IF_HIT_PIPELINE
    Sv32FrontendPipe u_frontend_pipe(
        .clk(clk),
        .rst_n(rst_n),
        // New frontend pipe owns epoch/drop handling, so pulse-style frontend
        // redirects can kill in-flight hit-path metadata without waiting for
        // old responses. Keep long fence maintenance out of this flush.
        .flush(redirect_flush_valid || stop_clear_valid),
        .tlb_flush_all(tlb_flush_all),
        .cpu_req_valid(ibus_req_valid_w),
        .cpu_req_ready(ibus_req_ready),
        .cpu_req_vaddr(ibus_req_vaddr_w),
        .cpu_req_pred_taken(ibus_req_pred_taken),
        .cpu_req_pred_target(ibus_req_pred_target),
        .cpu_req_pred_btb_hit(ibus_req_pred_btb_hit),
        .cpu_req_pred_btb_is_cond(ibus_req_pred_btb_is_cond),
        .cpu_req_pred_bht_state(ibus_req_pred_bht_state),
        .cpu_req_pred_pht_idx(ibus_req_pred_pht_idx),
        .priv_i(priv_state),
        .satp_i(csr_satp),
        .cpu_resp_valid(ibus_resp_valid),
        .cpu_resp_ready(ibus_resp_ready_w),
        .cpu_resp_rdata(ibus_resp_data),
        .cpu_resp_exc_valid(ibus_resp_exc_valid),
        .cpu_resp_exc_cause(ibus_resp_exc_cause),
        .cpu_resp_exc_tval(ibus_resp_exc_tval),
        .cpu_resp_pc(ibus_resp_pc),
        .cpu_resp_seq(ibus_resp_seq),
        .cpu_resp_epoch(ibus_resp_epoch),
        .cpu_resp_pred_taken(ibus_resp_pred_taken),
        .cpu_resp_pred_target(ibus_resp_pred_target),
        .cpu_resp_pred_btb_hit(ibus_resp_pred_btb_hit),
        .cpu_resp_pred_btb_is_cond(ibus_resp_pred_btb_is_cond),
        .cpu_resp_pred_bht_state(ibus_resp_pred_bht_state),
        .cpu_resp_pred_pht_idx(ibus_resp_pred_pht_idx),
        .pipe_req_valid(ibus_icache_pipe_req_valid),
        .pipe_req_ready(ibus_icache_pipe_req_ready),
        .pipe_req_paddr(ibus_icache_pipe_req_paddr),
        .pipe_req_vaddr(ibus_icache_pipe_req_vaddr),
        .pipe_req_pc(ibus_icache_pipe_req_pc),
        .pipe_req_seq(ibus_icache_pipe_req_seq),
        .pipe_req_epoch(ibus_icache_pipe_req_epoch),
        .pipe_req_pred_taken(ibus_icache_pipe_req_pred_taken),
        .pipe_req_pred_target(ibus_icache_pipe_req_pred_target),
        .pipe_req_pred_btb_hit(ibus_icache_pipe_req_pred_btb_hit),
        .pipe_req_pred_btb_is_cond(ibus_icache_pipe_req_pred_btb_is_cond),
        .pipe_req_pred_bht_state(ibus_icache_pipe_req_pred_bht_state),
        .pipe_req_pred_pht_idx(ibus_icache_pipe_req_pred_pht_idx),
        .pipe_req_priv(ibus_icache_pipe_req_priv),
        .pipe_req_exception_valid(ibus_icache_pipe_req_exception_valid),
        .pipe_req_exception_cause(ibus_icache_pipe_req_exception_cause),
        .pipe_req_exception_tval(ibus_icache_pipe_req_exception_tval),
        .pipe_resp_valid(ibus_icache_pipe_resp_valid),
        .pipe_resp_ready(ibus_icache_pipe_resp_ready),
        .pipe_resp_instr(ibus_icache_pipe_resp_instr),
        .pipe_resp_pc(ibus_icache_pipe_resp_pc),
        .pipe_resp_seq(ibus_icache_pipe_resp_seq),
        .pipe_resp_epoch(ibus_icache_pipe_resp_epoch),
        .pipe_resp_pred_taken(ibus_icache_pipe_resp_pred_taken),
        .pipe_resp_pred_target(ibus_icache_pipe_resp_pred_target),
        .pipe_resp_pred_btb_hit(ibus_icache_pipe_resp_pred_btb_hit),
        .pipe_resp_pred_btb_is_cond(ibus_icache_pipe_resp_pred_btb_is_cond),
        .pipe_resp_pred_bht_state(ibus_icache_pipe_resp_pred_bht_state),
        .pipe_resp_pred_pht_idx(ibus_icache_pipe_resp_pred_pht_idx),
        .pipe_resp_exception_valid(ibus_icache_pipe_resp_exception_valid),
        .pipe_resp_exception_cause(ibus_icache_pipe_resp_exception_cause),
        .pipe_resp_exception_tval(ibus_icache_pipe_resp_exception_tval),
        .pipe_resp_hit(ibus_icache_pipe_resp_hit),
        .pipe_resp_miss(ibus_icache_pipe_resp_miss),
        .lower_req_valid(ibus_ptw_req_valid),
        .lower_req_ready(ibus_ptw_req_ready),
        .lower_req_addr(ibus_ptw_req_addr),
        .lower_resp_valid(ibus_ptw_resp_valid),
        .lower_resp_ready(ibus_ptw_resp_ready),
        .lower_resp_rdata(ibus_ptw_resp_data),
        .stat_req_count(if_mmu_req_count),
        .stat_bypass_count(if_mmu_bypass_count),
        .stat_translate_count(if_mmu_translate_count),
        .stat_ptw_cycle_count(if_mmu_ptw_cycle_count),
        .stat_ptw_l1_read_count(if_mmu_ptw_l1_read_count),
        .stat_ptw_l0_read_count(if_mmu_ptw_l0_read_count),
        .stat_page_fault_count(if_mmu_page_fault_count),
        .stat_ptw_walk_start_count(if_mmu_ptw_walk_start_count),
        .stat_ptw_walk_done_count(if_mmu_ptw_walk_done_count),
        .stat_ptw_walk_fault_count(if_mmu_ptw_walk_fault_count),
        .stat_tlb_hit_count(if_mmu_tlb_hit_count),
        .stat_tlb_miss_count(if_mmu_tlb_miss_count),
        .stat_tlb_hit_to_cache_req_cycle(if_mmu_tlb_hit_to_cache_req_cycle),
        .stat_cache_req_wait_cycle(if_mmu_cache_req_wait_cycle),
        .stat_cache_resp_wait_cycle(if_mmu_cache_resp_wait_cycle),
        .stat_bridge_state_wait_cycle(if_mmu_bridge_state_wait_cycle),
        .stat_fetch_req_count(if_mmu_fetch_req_count),
        .stat_fetch_resp_count(if_mmu_fetch_resp_count),
        .stat_if_pipe_issue_count(if_pipe_issue_count),
        .stat_if_pipe_resp_count(if_pipe_resp_count),
        .stat_if_pipe_epoch_drop_count(if_pipe_epoch_drop_count),
        .stat_if_pipe_replay_count(if_pipe_replay_count),
        .stat_if_pipe_ptw_miss_count(if_pipe_ptw_miss_count),
        .stat_if_pipe_ptw_fault_count(if_pipe_ptw_fault_count),
        .stat_if_pipe_stall_cycle(if_pipe_stall_cycle),
        .stat_if_pipe_icache_miss_count(if_pipe_icache_miss_count),
        .stat_if_pipe_icache_replay_count(if_pipe_icache_replay_count)
`ifdef NPC_PIPE_STAT
        ,
        .if_pipe_stat_outstanding(if_pipe_stat_outstanding),
        .if_pipe_stat_replay_valid(if_pipe_stat_replay_valid),
        .if_pipe_stat_ptw_busy(if_pipe_stat_ptw_busy),
        .if_pipe_stat_req_valid(if_pipe_stat_req_valid),
        .if_pipe_stat_req_ready(if_pipe_stat_req_ready),
        .if_pipe_stat_resp_current(if_pipe_stat_resp_current),
        .if_pipe_stat_resp_stale(if_pipe_stat_resp_stale),
        .if_pipe_stat_lower_req_valid(if_pipe_stat_lower_req_valid),
        .if_pipe_stat_lower_req_ready(if_pipe_stat_lower_req_ready),
        .if_pipe_stat_lower_resp_valid(if_pipe_stat_lower_resp_valid),
        .if_pipe_stat_lower_resp_ready(if_pipe_stat_lower_resp_ready)
`endif
    );
`else
    Sv32ICacheBridge u_icache_bridge(
        .clk(clk),
        .rst_n(rst_n),
        // IF owns redirect/drop handling. Flushing this bridge on sfence/satp
        // can cancel a response that IF is still waiting for and deadlock fetch.
        .flush(1'b0),
        .tlb_flush_all(tlb_flush_all),
        .cpu_req_valid(ibus_req_valid_w),
        .cpu_req_ready(ibus_req_ready),
        .cpu_req_vaddr(ibus_req_vaddr_w),
        .priv_i(priv_state),
        .satp_i(csr_satp),
        .cpu_resp_valid(ibus_resp_valid),
        .cpu_resp_ready(ibus_resp_ready_w),
        .cpu_resp_rdata(ibus_resp_data),
        .cpu_resp_exc_valid(ibus_resp_exc_valid),
        .cpu_resp_exc_cause(ibus_resp_exc_cause),
        .cpu_resp_exc_tval(ibus_resp_exc_tval),
        .lower_req_valid(ibus_icache_req_valid),
        .lower_req_ready(ibus_icache_req_ready),
        .lower_req_addr(ibus_req_paddr_w),
        .lower_resp_valid(ibus_icache_resp_valid),
        .lower_resp_ready(ibus_icache_resp_ready),
        .lower_resp_rdata(ibus_icache_resp_data),
        .stat_req_count(if_mmu_req_count),
        .stat_bypass_count(if_mmu_bypass_count),
        .stat_translate_count(if_mmu_translate_count),
        .stat_ptw_cycle_count(if_mmu_ptw_cycle_count),
        .stat_ptw_l1_read_count(if_mmu_ptw_l1_read_count),
        .stat_ptw_l0_read_count(if_mmu_ptw_l0_read_count),
        .stat_page_fault_count(if_mmu_page_fault_count),
        .stat_ptw_walk_start_count(if_mmu_ptw_walk_start_count),
        .stat_ptw_walk_done_count(if_mmu_ptw_walk_done_count),
        .stat_ptw_walk_fault_count(if_mmu_ptw_walk_fault_count),
        .stat_tlb_hit_count(if_mmu_tlb_hit_count),
        .stat_tlb_miss_count(if_mmu_tlb_miss_count),
        .stat_tlb_hit_to_cache_req_cycle(if_mmu_tlb_hit_to_cache_req_cycle),
        .stat_cache_req_wait_cycle(if_mmu_cache_req_wait_cycle),
        .stat_cache_resp_wait_cycle(if_mmu_cache_resp_wait_cycle),
        .stat_bridge_state_wait_cycle(if_mmu_bridge_state_wait_cycle),
        .stat_fetch_req_count(if_mmu_fetch_req_count),
        .stat_fetch_resp_count(if_mmu_fetch_resp_count)
    );
    assign ibus_resp_pc = 32'b0;
    assign ibus_resp_seq = 32'b0;
    assign ibus_resp_epoch = 16'b0;
    assign ibus_resp_pred_taken = 1'b0;
    assign ibus_resp_pred_target = 32'b0;
    assign ibus_resp_pred_btb_hit = 1'b0;
    assign ibus_resp_pred_btb_is_cond = 1'b0;
    assign ibus_resp_pred_bht_state = 2'b0;
    assign ibus_resp_pred_pht_idx = 32'b0;
    assign if_pipe_issue_count = 64'b0;
    assign if_pipe_resp_count = 64'b0;
    assign if_pipe_epoch_drop_count = 64'b0;
    assign if_pipe_replay_count = 64'b0;
    assign if_pipe_ptw_miss_count = 64'b0;
    assign if_pipe_ptw_fault_count = 64'b0;
    assign if_pipe_stall_cycle = 64'b0;
    assign if_pipe_icache_miss_count = 64'b0;
    assign if_pipe_icache_replay_count = 64'b0;
`ifdef NPC_PIPE_STAT
    assign if_pipe_stat_outstanding = 1'b0;
    assign if_pipe_stat_replay_valid = 1'b0;
    assign if_pipe_stat_ptw_busy = 1'b0;
    assign if_pipe_stat_req_valid = 1'b0;
    assign if_pipe_stat_req_ready = 1'b0;
    assign if_pipe_stat_resp_current = 1'b0;
    assign if_pipe_stat_resp_stale = 1'b0;
    assign if_pipe_stat_lower_req_valid = 1'b0;
    assign if_pipe_stat_lower_req_ready = 1'b0;
    assign if_pipe_stat_lower_resp_valid = 1'b0;
    assign if_pipe_stat_lower_resp_ready = 1'b0;
`endif
`endif

`ifndef NPC_IF_HIT_PIPELINE
    assign ibus_icache_pipe_req_valid = 1'b0;
    assign ibus_icache_pipe_req_paddr = 32'b0;
    assign ibus_icache_pipe_req_vaddr = 32'b0;
    assign ibus_icache_pipe_req_pc = 32'b0;
    assign ibus_icache_pipe_req_seq = 32'b0;
    assign ibus_icache_pipe_req_epoch = 16'b0;
    assign ibus_icache_pipe_req_pred_taken = 1'b0;
    assign ibus_icache_pipe_req_pred_target = 32'b0;
    assign ibus_icache_pipe_req_pred_btb_hit = 1'b0;
    assign ibus_icache_pipe_req_pred_btb_is_cond = 1'b0;
    assign ibus_icache_pipe_req_pred_bht_state = 2'b0;
    assign ibus_icache_pipe_req_pred_pht_idx = 32'b0;
    assign ibus_icache_pipe_req_priv = 2'b0;
    assign ibus_icache_pipe_req_exception_valid = 1'b0;
    assign ibus_icache_pipe_req_exception_cause = 32'b0;
    assign ibus_icache_pipe_req_exception_tval = 32'b0;
    assign ibus_icache_pipe_resp_ready = 1'b0;
`endif

    assign ibus_icache_mem_req_ready = ibus_icache_mem_grant && ibus_mem_req_ready;
    assign ibus_ptw_req_ready = ibus_ptw_mem_grant && ibus_mem_req_ready;
    assign ibus_mem_req_valid = ibus_icache_mem_grant || ibus_ptw_mem_grant;
    assign ibus_mem_req_write = ibus_icache_mem_grant ? ibus_icache_mem_req_write : 1'b0;
    assign ibus_mem_req_addr = ibus_icache_mem_grant ? ibus_icache_mem_req_addr : ibus_ptw_req_addr;
    assign ibus_mem_req_wdata = ibus_icache_mem_grant ? ibus_icache_mem_req_wdata : 32'b0;
    assign ibus_mem_req_wstrb = ibus_icache_mem_grant ? ibus_icache_mem_req_wstrb : 4'b0;
    assign ibus_mem_req_len = ibus_icache_mem_grant ? ibus_icache_mem_req_len : 3'd4;
    assign ibus_icache_mem_resp_valid = ibus_mem_resp_valid && ibus_mem_owner_valid && !ibus_mem_owner_ptw;
    assign ibus_ptw_resp_valid = ibus_mem_resp_valid && ibus_mem_owner_valid && ibus_mem_owner_ptw;
    assign ibus_icache_mem_resp_data = ibus_mem_resp_data;
    assign ibus_ptw_resp_data = ibus_mem_resp_data;
    assign ibus_mem_resp_ready =
        ibus_mem_owner_valid &&
        (ibus_mem_owner_ptw ? ibus_ptw_resp_ready : ibus_icache_mem_resp_ready);

    always @(posedge clk) begin
        if (!rst_n) begin
            ibus_mem_owner_valid <= 1'b0;
            ibus_mem_owner_ptw <= 1'b0;
            ibus_mem_resp_left <= 5'b0;
        end else begin
            if (ibus_mem_req_fire) begin
                ibus_mem_owner_valid <= 1'b1;
                ibus_mem_owner_ptw <= ibus_ptw_mem_grant;
                ibus_mem_resp_left <= ibus_mem_req_beats;
            end else if (ibus_mem_resp_fire && ibus_mem_owner_valid) begin
                if (ibus_mem_resp_left <= 5'd1) begin
                    ibus_mem_owner_valid <= 1'b0;
                    ibus_mem_owner_ptw <= 1'b0;
                    ibus_mem_resp_left <= 5'b0;
                end else begin
                    ibus_mem_resp_left <= ibus_mem_resp_left - 4'd1;
                end
            end
        end
    end

    ICache #(
        .LINE_BYTES(ICACHE_LINE_BYTES),
        .LINE_COUNT(ICACHE_LINE_COUNT)
    ) u_icache (
        .clk(clk),
        .rst_n(rst_n),
        .maint_inv_req(icache_maint_inv_req),
        .maint_inv_done(icache_maint_inv_done),
        .cpu_req_valid(ibus_icache_req_valid),
        .cpu_req_ready(ibus_icache_req_ready),
        .cpu_req_addr(ibus_req_paddr_w),
        .cpu_req_lookup_hit(ibus_icache_lookup_hit),
        .cpu_req_lookup_uncached(ibus_icache_lookup_uncached),
        .cpu_resp_valid(ibus_icache_resp_valid),
        .cpu_resp_ready(ibus_icache_resp_ready),
        .cpu_resp_rdata(ibus_icache_resp_data),
        .pipe_req_valid(ibus_icache_pipe_req_valid),
        .pipe_req_ready(ibus_icache_pipe_req_ready),
        .pipe_req_paddr(ibus_icache_pipe_req_paddr),
        .pipe_req_vaddr(ibus_icache_pipe_req_vaddr),
        .pipe_req_pc(ibus_icache_pipe_req_pc),
        .pipe_req_seq(ibus_icache_pipe_req_seq),
        .pipe_req_epoch(ibus_icache_pipe_req_epoch),
        .pipe_req_pred_taken(ibus_icache_pipe_req_pred_taken),
        .pipe_req_pred_target(ibus_icache_pipe_req_pred_target),
        .pipe_req_pred_btb_hit(ibus_icache_pipe_req_pred_btb_hit),
        .pipe_req_pred_btb_is_cond(ibus_icache_pipe_req_pred_btb_is_cond),
        .pipe_req_pred_bht_state(ibus_icache_pipe_req_pred_bht_state),
        .pipe_req_pred_pht_idx(ibus_icache_pipe_req_pred_pht_idx),
        .pipe_req_priv(ibus_icache_pipe_req_priv),
        .pipe_req_exception_valid(ibus_icache_pipe_req_exception_valid),
        .pipe_req_exception_cause(ibus_icache_pipe_req_exception_cause),
        .pipe_req_exception_tval(ibus_icache_pipe_req_exception_tval),
        .pipe_resp_valid(ibus_icache_pipe_resp_valid),
        .pipe_resp_ready(ibus_icache_pipe_resp_ready),
        .pipe_resp_instr(ibus_icache_pipe_resp_instr),
        .pipe_resp_pc(ibus_icache_pipe_resp_pc),
        .pipe_resp_seq(ibus_icache_pipe_resp_seq),
        .pipe_resp_epoch(ibus_icache_pipe_resp_epoch),
        .pipe_resp_pred_taken(ibus_icache_pipe_resp_pred_taken),
        .pipe_resp_pred_target(ibus_icache_pipe_resp_pred_target),
        .pipe_resp_pred_btb_hit(ibus_icache_pipe_resp_pred_btb_hit),
        .pipe_resp_pred_btb_is_cond(ibus_icache_pipe_resp_pred_btb_is_cond),
        .pipe_resp_pred_bht_state(ibus_icache_pipe_resp_pred_bht_state),
        .pipe_resp_pred_pht_idx(ibus_icache_pipe_resp_pred_pht_idx),
        .pipe_resp_exception_valid(ibus_icache_pipe_resp_exception_valid),
        .pipe_resp_exception_cause(ibus_icache_pipe_resp_exception_cause),
        .pipe_resp_exception_tval(ibus_icache_pipe_resp_exception_tval),
        .pipe_resp_hit(ibus_icache_pipe_resp_hit),
        .pipe_resp_miss(ibus_icache_pipe_resp_miss),
        .lower_req_valid(ibus_icache_mem_req_valid),
        .lower_req_ready(ibus_icache_mem_req_ready),
        .lower_req_write(ibus_icache_mem_req_write),
        .lower_req_addr(ibus_icache_mem_req_addr),
        .lower_req_wdata(ibus_icache_mem_req_wdata),
        .lower_req_wstrb(ibus_icache_mem_req_wstrb),
        .lower_req_len(ibus_icache_mem_req_len),
        .lower_resp_valid(ibus_icache_mem_resp_valid),
        .lower_resp_ready(ibus_icache_mem_resp_ready),
        .lower_resp_rdata(ibus_icache_mem_resp_data)
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
        ,
        .stat_access(icache_stat_access),
        .stat_hit(icache_stat_hit),
        .stat_miss(icache_stat_miss),
        .stat_refill_req(icache_stat_refill_req),
        .stat_refill_resp(icache_stat_refill_resp),
        .stat_refill_bypass(icache_stat_refill_bypass),
        .stat_req_wait_cycle(icache_stat_req_wait_cycle),
        .stat_hit_resp_wait_cycle(icache_stat_hit_resp_wait_cycle),
        .stat_miss_wait_cycle(icache_stat_miss_wait_cycle),
        .stat_uncached_access(icache_stat_uncached_access),
        .stat_pipe_req_valid_cycle(icache_pipe_req_valid_cycle),
        .stat_pipe_req_ready_cycle(icache_pipe_req_ready_cycle),
        .stat_pipe_req_fire_cycle(icache_pipe_req_fire_cycle),
        .stat_pipe_req_valid_not_ready_cycle(icache_pipe_req_valid_not_ready_cycle),
        .stat_pipe_resp_valid_cycle(icache_pipe_resp_valid_cycle),
        .stat_pipe_resp_ready_cycle(icache_pipe_resp_ready_cycle),
        .stat_pipe_resp_fire_cycle(icache_pipe_resp_fire_cycle),
        .stat_pipe_data_valid_cycle(icache_pipe_data_valid_cycle),
        .stat_pipe_resp_block_cycle(icache_pipe_resp_block_cycle),
        .stat_pipe_ready_block_state_cycle(icache_pipe_ready_block_state_cycle),
        .stat_pipe_ready_block_data_cycle(icache_pipe_ready_block_data_cycle),
        .stat_pipe_ready_block_resp_cycle(icache_pipe_ready_block_resp_cycle),
        .stat_pipe_ready_block_cpu_cycle(icache_pipe_ready_block_cpu_cycle),
        .stat_pipe_ready_block_maint_cycle(icache_pipe_ready_block_maint_cycle),
        .stat_pipe_state_idle_cycle(icache_pipe_state_idle_cycle),
        .stat_pipe_state_refill_cycle(icache_pipe_state_refill_cycle),
        .stat_pipe_state_uncached_cycle(icache_pipe_state_uncached_cycle),
        .stat_pipe_hit_fire_cycle(icache_pipe_hit_fire_cycle),
        .stat_pipe_miss_fire_cycle(icache_pipe_miss_fire_cycle),
        .stat_pipe_refill_busy_cycle(icache_pipe_refill_busy_cycle),
        .stat_pipe_resp_fifo_full_cycle(icache_pipe_resp_fifo_full_cycle)
`endif
`endif
    );
endmodule
