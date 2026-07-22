`timescale 1ns / 1ps

module CpuDmemSubsystem #(
    parameter integer DCACHE_LINE_BYTES = 64,
    parameter integer DCACHE_LINE_COUNT = 64,
    parameter integer DCACHE_LINE_WORDS = 16,
    parameter integer DPI_MEM_LATENCY = 2,
    parameter integer TIMER_CLK_HZ = 100000000,
    parameter integer TIMEBASE_HZ = 1000000
) (
    input clk,
    input rst_n,

    input flush_mem,
    input tlb_flush_all,
    input dcache_maint_flush_req,
    input [1:0] priv_state,
    input [31:0] csr_mstatus,
    input [31:0] csr_satp,

    input dbus_req_valid,
    output dbus_req_ready,
    input dbus_req_write,
    input dbus_req_atomic,
    input dbus_req_store_bufferable,
    input [31:0] dbus_req_addr,
    input [31:0] dbus_req_wdata,
    input [3:0] dbus_req_wstrb,
    input [2:0] dbus_req_len,
    output dbus_resp_valid,
    input dbus_resp_ready,
    output [31:0] dbus_resp_data,
    output dbus_resp_exc_valid,
    output [31:0] dbus_resp_exc_cause,
    output [31:0] dbus_resp_exc_tval,

    output [31:0] dbus_req_paddr,
    output dbus_dcache_req_valid,
    output dbus_dcache_req_ready,
    output dbus_dcache_req_write,
    output [2:0] dbus_dcache_req_len,
    output dbus_dcache_req_is_ptw,

    output dbus_store_buffer_empty,
    output dbus_store_buffer_busy,
    output [2:0] dbg_dcache_bridge_state,
    output dbg_dcache_bridge_drop_resp,
    output dbg_dcache_bridge_req_write,
    output dbg_dcache_bridge_req_store_bufferable,
    output dbg_dcache_bridge_req_safe_store_bufferable,
    output dbg_dcache_bridge_sbuf0_valid,
    output dbg_dcache_bridge_sbuf1_valid,
    output dbg_dcache_bridge_sbuf0_sent,
    output dbg_dcache_bridge_sbuf1_sent,
    output dbg_dcache_bridge_sbuf_drain_active,
    output dbg_dcache_bridge_sbuf_drain_resp_pending,
    output dbg_dcache_bridge_sbuf_drain_req_valid,
    output dbg_dcache_bridge_sbuf_drain_grant,
    output dbg_dcache_bridge_sbuf_drain_req_fire,
    output dbg_dcache_bridge_sbuf_drain_resp_fire,
    output dbg_dcache_bridge_data_req_fire,
    output dbg_dcache_bridge_lower_resp_ready,
    output dbg_dcache_bridge_lower_req_valid,
    output dbg_dcache_bridge_lower_req_write,
    output [31:0] dbg_dcache_bridge_lower_req_addr,
    output dbg_dcache_bridge_sbuf_conflict_stall,
    output dbg_dcache_bridge_req_store_buffer_full,
    output dbg_dcache_bridge_sbuf_forward_hit,

    output dcache_maint_flush_done,
    output [63:0] timer_time_value,
    output [63:0] timer_timecmp_value,
    output [31:0] timer_step_accum_value,
    output timer_mtip,

    output [63:0] lsu_mmu_req_count,
    output [63:0] lsu_mmu_bypass_count,
    output [63:0] lsu_mmu_translate_count,
    output [63:0] lsu_mmu_ptw_cycle_count,
    output [63:0] lsu_mmu_ptw_l1_read_count,
    output [63:0] lsu_mmu_ptw_l0_read_count,
    output [63:0] lsu_mmu_page_fault_count,
    output [63:0] lsu_mmu_ptw_walk_start_count,
    output [63:0] lsu_mmu_ptw_walk_done_count,
    output [63:0] lsu_mmu_ptw_walk_fault_count,
    output [63:0] lsu_mmu_tlb_hit_count,
    output [63:0] lsu_mmu_tlb_miss_count,
    output [63:0] lsu_mmu_tlb_hit_to_cache_req_cycle,
    output [63:0] lsu_mmu_cache_req_wait_cycle,
    output [63:0] lsu_mmu_cache_resp_wait_cycle,
    output [63:0] lsu_mmu_bridge_state_wait_cycle,
    output [63:0] lsu_mmu_data_req_count,
    output [63:0] lsu_mmu_data_resp_count,
    output [63:0] lsu_mmu_uncached_req_count,
    output [63:0] store_buffer_enqueue_count,
    output [63:0] store_buffer_dequeue_count,
    output [63:0] store_buffer_full_stall_count,
    output [63:0] store_buffer_drain_req_count,
    output [63:0] store_buffer_drain_resp_count,
    output [63:0] store_buffer_drain_wait_count,
    output [63:0] store_buffer_load_forward_count,
    output [63:0] store_buffer_load_stall_conflict_count,
    output [63:0] store_buffer_load_stall_buffer_nonempty_count,
    output [63:0] store_buffer_fence_drain_wait_bridge_count,
    output [63:0] store_buffer_uncached_drain_wait_count,
    output [63:0] store_buffer_killed_store_block_count,
    output [63:0] store_buffer_occupancy0_count,
    output [63:0] store_buffer_occupancy1_count,
    output [63:0] store_buffer_occupancy2_count,
    output [63:0] store_buffer_max_occupancy_count,
    output [63:0] store_buffer_enqueue_occ0_count,
    output [63:0] store_buffer_enqueue_occ1_count,
    output [63:0] store_buffer_enqueue_full_count,
    output [63:0] dhitopt_candidate_count,
    output [63:0] dhitopt_success_count,
    output [63:0] dhitopt_fallback_count,
    output [63:0] dhitopt_block_store_buffer_count,
    output [63:0] dhitopt_block_uncached_count,
    output [63:0] dhitopt_block_fault_count,
    output [63:0] dhitopt_block_miss_count,
    output [63:0] dhitopt_block_alignment_count,
    output [63:0] dhitopt_unknown_count,
    output [63:0] dcache_stat_access,
    output [63:0] dcache_stat_load_access,
    output [63:0] dcache_stat_store_access,
    output [63:0] dcache_stat_load_hit,
    output [63:0] dcache_stat_load_miss,
    output [63:0] dcache_stat_store_hit,
    output [63:0] dcache_stat_store_miss,
    output [63:0] dcache_stat_refill_req,
    output [63:0] dcache_stat_refill_resp,
    output [63:0] dcache_stat_write_req,
    output [63:0] dcache_stat_write_resp,
    output [63:0] dcache_stat_refill_ld_bypass,
    output [63:0] dcache_stat_refill_store_merge,
    output [63:0] dcache_stat_req_wait_cycle,
    output [63:0] dcache_stat_hit_resp_wait_cycle,
    output [63:0] dcache_stat_miss_wait_cycle,
    output [63:0] dcache_stat_uncached_access,
    output [63:0] dcache_stat_writeback_cycle,

    output [31:0] dbus_axi_awaddr,
    output [7:0] dbus_axi_awlen,
    output [2:0] dbus_axi_awsize,
    output [1:0] dbus_axi_awburst,
    output dbus_axi_awvalid,
    input dbus_axi_awready,
    output [31:0] dbus_axi_wdata,
    output [3:0] dbus_axi_wstrb,
    output dbus_axi_wlast,
    output dbus_axi_wvalid,
    input dbus_axi_wready,
    input [1:0] dbus_axi_bresp,
    input dbus_axi_bvalid,
    output dbus_axi_bready,
    output [31:0] dbus_axi_araddr,
    output [7:0] dbus_axi_arlen,
    output [2:0] dbus_axi_arsize,
    output [1:0] dbus_axi_arburst,
    output dbus_axi_arvalid,
    input dbus_axi_arready,
    input [31:0] dbus_axi_rdata,
    input [1:0] dbus_axi_rresp,
    input dbus_axi_rvalid,
    output dbus_axi_rready,
    input dbus_axi_rlast
);
    wire [31:0] dbus_dcache_req_wdata;
    wire [3:0] dbus_dcache_req_wstrb;
    wire dbus_dcache_resp_valid;
    wire dbus_dcache_resp_ready;
    wire [31:0] dbus_dcache_resp_data;
    wire dbus_dcache_mem_req_valid;
    wire dbus_dcache_mem_req_ready;
    wire dbus_dcache_mem_req_write;
    wire [31:0] dbus_dcache_mem_req_addr;
    wire [31:0] dbus_dcache_mem_req_wdata;
    wire [3:0] dbus_dcache_mem_req_wstrb;
    wire [2:0] dbus_dcache_mem_req_len;
    wire dbus_dcache_mem_resp_valid;
    wire dbus_dcache_mem_resp_ready;
    wire [31:0] dbus_dcache_mem_resp_data;
    wire dbus_mem_req_valid;
    wire dbus_mem_req_ready;
    wire dbus_mem_req_write;
    wire [31:0] dbus_mem_req_addr;
    wire [31:0] dbus_mem_req_wdata;
    wire [3:0] dbus_mem_req_wstrb;
    wire [2:0] dbus_mem_req_len;
    wire dbus_mem_resp_valid;
    wire dbus_mem_resp_ready;
    wire [31:0] dbus_mem_resp_data;
    wire timer_req_valid;
    wire timer_req_ready;
    wire timer_req_write;
    wire [31:0] timer_req_addr;
    wire [31:0] timer_req_wdata;
    wire [3:0] timer_req_wstrb;
    wire [2:0] timer_req_len;
    wire timer_resp_valid;
    wire timer_resp_ready;
    wire [31:0] timer_resp_data;
    wire dbus_pipe_req_valid;
    wire dbus_pipe_req_ready;
    wire dbus_pipe_req_write;
    wire [31:0] dbus_pipe_req_paddr;
    wire [31:0] dbus_pipe_req_vaddr;
    wire [31:0] dbus_pipe_req_wdata;
    wire [3:0] dbus_pipe_req_wstrb;
    wire [2:0] dbus_pipe_req_len;
    wire [31:0] dbus_pipe_req_seq;
    wire [15:0] dbus_pipe_req_epoch;
    wire dbus_pipe_req_exception_valid;
    wire [31:0] dbus_pipe_req_exception_cause;
    wire [31:0] dbus_pipe_req_exception_tval;
    wire dbus_pipe_resp_valid;
    wire dbus_pipe_resp_ready;
    wire [31:0] dbus_pipe_resp_rdata;
    wire [31:0] dbus_pipe_resp_vaddr;
    wire [31:0] dbus_pipe_resp_seq;
    wire [15:0] dbus_pipe_resp_epoch;
    wire dbus_pipe_resp_exception_valid;
    wire [31:0] dbus_pipe_resp_exception_cause;
    wire [31:0] dbus_pipe_resp_exception_tval;
    wire dbus_pipe_resp_hit;
    wire dbus_pipe_resp_miss;

    assign dbus_pipe_req_valid = 1'b0;
    assign dbus_pipe_req_write = 1'b0;
    assign dbus_pipe_req_paddr = 32'b0;
    assign dbus_pipe_req_vaddr = 32'b0;
    assign dbus_pipe_req_wdata = 32'b0;
    assign dbus_pipe_req_wstrb = 4'b0;
    assign dbus_pipe_req_len = 3'b0;
    assign dbus_pipe_req_seq = 32'b0;
    assign dbus_pipe_req_epoch = 16'b0;
    assign dbus_pipe_req_exception_valid = 1'b0;
    assign dbus_pipe_req_exception_cause = 32'b0;
    assign dbus_pipe_req_exception_tval = 32'b0;
    assign dbus_pipe_resp_ready = 1'b1;

    Sv32DCacheBridge u_dcache_bridge(
        .clk(clk),
        .rst_n(rst_n),
        .flush(flush_mem),
        .tlb_flush_all(tlb_flush_all),
        .cpu_req_valid(dbus_req_valid),
        .cpu_req_ready(dbus_req_ready),
        .cpu_req_write(dbus_req_write),
        .cpu_req_atomic(dbus_req_atomic),
        .cpu_req_store_bufferable(dbus_req_store_bufferable),
        .cpu_req_vaddr(dbus_req_addr),
        .cpu_req_wdata(dbus_req_wdata),
        .cpu_req_wstrb(dbus_req_wstrb),
        .cpu_req_len(dbus_req_len),
        .priv_i(priv_state),
        .mstatus_i(csr_mstatus),
        .satp_i(csr_satp),
        .cpu_resp_valid(dbus_resp_valid),
        .cpu_resp_ready(dbus_resp_ready),
        .cpu_resp_rdata(dbus_resp_data),
        .cpu_resp_exc_valid(dbus_resp_exc_valid),
        .cpu_resp_exc_cause(dbus_resp_exc_cause),
        .cpu_resp_exc_tval(dbus_resp_exc_tval),
        .lower_req_valid(dbus_dcache_req_valid),
        .lower_req_ready(dbus_dcache_req_ready),
        .lower_req_write(dbus_dcache_req_write),
        .lower_req_addr(dbus_req_paddr),
        .lower_req_wdata(dbus_dcache_req_wdata),
        .lower_req_wstrb(dbus_dcache_req_wstrb),
        .lower_req_len(dbus_dcache_req_len),
        .lower_req_is_ptw(dbus_dcache_req_is_ptw),
        .lower_resp_valid(dbus_dcache_resp_valid),
        .lower_resp_ready(dbus_dcache_resp_ready),
        .lower_resp_rdata(dbus_dcache_resp_data),
        .dtlb_refill_valid_o(),
        .dtlb_refill_vaddr_o(),
        .dtlb_refill_pte_o(),
        .dtlb_refill_level_o(),
        .stat_req_count(lsu_mmu_req_count),
        .stat_bypass_count(lsu_mmu_bypass_count),
        .stat_translate_count(lsu_mmu_translate_count),
        .stat_ptw_cycle_count(lsu_mmu_ptw_cycle_count),
        .stat_ptw_l1_read_count(lsu_mmu_ptw_l1_read_count),
        .stat_ptw_l0_read_count(lsu_mmu_ptw_l0_read_count),
        .stat_page_fault_count(lsu_mmu_page_fault_count),
        .stat_ptw_walk_start_count(lsu_mmu_ptw_walk_start_count),
        .stat_ptw_walk_done_count(lsu_mmu_ptw_walk_done_count),
        .stat_ptw_walk_fault_count(lsu_mmu_ptw_walk_fault_count),
        .stat_tlb_hit_count(lsu_mmu_tlb_hit_count),
        .stat_tlb_miss_count(lsu_mmu_tlb_miss_count),
        .stat_tlb_hit_to_cache_req_cycle(lsu_mmu_tlb_hit_to_cache_req_cycle),
        .stat_cache_req_wait_cycle(lsu_mmu_cache_req_wait_cycle),
        .stat_cache_resp_wait_cycle(lsu_mmu_cache_resp_wait_cycle),
        .stat_bridge_state_wait_cycle(lsu_mmu_bridge_state_wait_cycle),
        .stat_data_req_count(lsu_mmu_data_req_count),
        .stat_data_resp_count(lsu_mmu_data_resp_count),
        .stat_uncached_req_count(lsu_mmu_uncached_req_count),
        .store_buffer_empty(dbus_store_buffer_empty),
        .store_buffer_busy(dbus_store_buffer_busy),
        .stat_sbuf_enqueue(store_buffer_enqueue_count),
        .stat_sbuf_dequeue(store_buffer_dequeue_count),
        .stat_sbuf_full_stall(store_buffer_full_stall_count),
        .stat_sbuf_drain_req(store_buffer_drain_req_count),
        .stat_sbuf_drain_resp(store_buffer_drain_resp_count),
        .stat_sbuf_drain_wait(store_buffer_drain_wait_count),
        .stat_sbuf_load_forward(store_buffer_load_forward_count),
        .stat_sbuf_load_stall_conflict(store_buffer_load_stall_conflict_count),
        .stat_sbuf_load_stall_buffer_nonempty(store_buffer_load_stall_buffer_nonempty_count),
        .stat_sbuf_fence_drain_wait(store_buffer_fence_drain_wait_bridge_count),
        .stat_sbuf_uncached_drain_wait(store_buffer_uncached_drain_wait_count),
        .stat_sbuf_killed_store_block(store_buffer_killed_store_block_count),
        .stat_sbuf_occupancy0(store_buffer_occupancy0_count),
        .stat_sbuf_occupancy1(store_buffer_occupancy1_count),
        .stat_sbuf_occupancy2(store_buffer_occupancy2_count),
        .stat_sbuf_max_occupancy(store_buffer_max_occupancy_count),
        .stat_sbuf_enqueue_occ0(store_buffer_enqueue_occ0_count),
        .stat_sbuf_enqueue_occ1(store_buffer_enqueue_occ1_count),
        .stat_sbuf_enqueue_full(store_buffer_enqueue_full_count),
        .stat_dhitopt_candidate(dhitopt_candidate_count),
        .stat_dhitopt_success(dhitopt_success_count),
        .stat_dhitopt_fallback(dhitopt_fallback_count),
        .stat_dhitopt_block_store_buffer(dhitopt_block_store_buffer_count),
        .stat_dhitopt_block_uncached(dhitopt_block_uncached_count),
        .stat_dhitopt_block_fault(dhitopt_block_fault_count),
        .stat_dhitopt_block_miss(dhitopt_block_miss_count),
        .stat_dhitopt_block_alignment(dhitopt_block_alignment_count),
        .stat_dhitopt_unknown(dhitopt_unknown_count),
        .dbg_state(dbg_dcache_bridge_state),
        .dbg_drop_resp(dbg_dcache_bridge_drop_resp),
        .dbg_req_write(dbg_dcache_bridge_req_write),
        .dbg_req_store_bufferable(dbg_dcache_bridge_req_store_bufferable),
        .dbg_req_safe_store_bufferable(dbg_dcache_bridge_req_safe_store_bufferable),
        .dbg_sbuf0_valid(dbg_dcache_bridge_sbuf0_valid),
        .dbg_sbuf1_valid(dbg_dcache_bridge_sbuf1_valid),
        .dbg_sbuf0_sent(dbg_dcache_bridge_sbuf0_sent),
        .dbg_sbuf1_sent(dbg_dcache_bridge_sbuf1_sent),
        .dbg_sbuf_drain_active(dbg_dcache_bridge_sbuf_drain_active),
        .dbg_sbuf_drain_resp_pending(dbg_dcache_bridge_sbuf_drain_resp_pending),
        .dbg_sbuf_drain_req_valid(dbg_dcache_bridge_sbuf_drain_req_valid),
        .dbg_sbuf_drain_grant(dbg_dcache_bridge_sbuf_drain_grant),
        .dbg_sbuf_drain_req_fire(dbg_dcache_bridge_sbuf_drain_req_fire),
        .dbg_sbuf_drain_resp_fire(dbg_dcache_bridge_sbuf_drain_resp_fire),
        .dbg_data_req_fire(dbg_dcache_bridge_data_req_fire),
        .dbg_lower_resp_ready(dbg_dcache_bridge_lower_resp_ready),
        .dbg_lower_req_valid(dbg_dcache_bridge_lower_req_valid),
        .dbg_lower_req_write(dbg_dcache_bridge_lower_req_write),
        .dbg_lower_req_addr(dbg_dcache_bridge_lower_req_addr),
        .dbg_sbuf_conflict_stall(dbg_dcache_bridge_sbuf_conflict_stall),
        .dbg_req_store_buffer_full(dbg_dcache_bridge_req_store_buffer_full),
        .dbg_sbuf_forward_hit(dbg_dcache_bridge_sbuf_forward_hit)
    );

    DCache #(
        .LINE_BYTES(DCACHE_LINE_BYTES),
        .LINE_COUNT(DCACHE_LINE_COUNT)
    ) u_dcache (
        .clk(clk),
        .rst_n(rst_n),
        .maint_flush_req(dcache_maint_flush_req),
        .maint_flush_done(dcache_maint_flush_done),
        .cpu_req_valid(dbus_dcache_req_valid),
        .cpu_req_ready(dbus_dcache_req_ready),
        .cpu_req_write(dbus_dcache_req_write),
        .cpu_req_addr(dbus_req_paddr),
        .cpu_req_wdata(dbus_dcache_req_wdata),
        .cpu_req_wstrb(dbus_dcache_req_wstrb),
        .cpu_req_len(dbus_dcache_req_len),
        .cpu_resp_valid(dbus_dcache_resp_valid),
        .cpu_resp_ready(dbus_dcache_resp_ready),
        .cpu_resp_rdata(dbus_dcache_resp_data),
        .pipe_req_valid(dbus_pipe_req_valid),
        .pipe_req_ready(dbus_pipe_req_ready),
        .pipe_req_write(dbus_pipe_req_write),
        .pipe_req_paddr(dbus_pipe_req_paddr),
        .pipe_req_vaddr(dbus_pipe_req_vaddr),
        .pipe_req_wdata(dbus_pipe_req_wdata),
        .pipe_req_wstrb(dbus_pipe_req_wstrb),
        .pipe_req_len(dbus_pipe_req_len),
        .pipe_req_seq(dbus_pipe_req_seq),
        .pipe_req_epoch(dbus_pipe_req_epoch),
        .pipe_req_exception_valid(dbus_pipe_req_exception_valid),
        .pipe_req_exception_cause(dbus_pipe_req_exception_cause),
        .pipe_req_exception_tval(dbus_pipe_req_exception_tval),
        .pipe_resp_valid(dbus_pipe_resp_valid),
        .pipe_resp_ready(dbus_pipe_resp_ready),
        .pipe_resp_rdata(dbus_pipe_resp_rdata),
        .pipe_resp_vaddr(dbus_pipe_resp_vaddr),
        .pipe_resp_seq(dbus_pipe_resp_seq),
        .pipe_resp_epoch(dbus_pipe_resp_epoch),
        .pipe_resp_exception_valid(dbus_pipe_resp_exception_valid),
        .pipe_resp_exception_cause(dbus_pipe_resp_exception_cause),
        .pipe_resp_exception_tval(dbus_pipe_resp_exception_tval),
        .pipe_resp_hit(dbus_pipe_resp_hit),
        .pipe_resp_miss(dbus_pipe_resp_miss),
        .lower_req_valid(dbus_dcache_mem_req_valid),
        .lower_req_ready(dbus_dcache_mem_req_ready),
        .lower_req_write(dbus_dcache_mem_req_write),
        .lower_req_addr(dbus_dcache_mem_req_addr),
        .lower_req_wdata(dbus_dcache_mem_req_wdata),
        .lower_req_wstrb(dbus_dcache_mem_req_wstrb),
        .lower_req_len(dbus_dcache_mem_req_len),
        .lower_resp_valid(dbus_dcache_mem_resp_valid),
        .lower_resp_ready(dbus_dcache_mem_resp_ready),
        .lower_resp_rdata(dbus_dcache_mem_resp_data)
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
        ,
        .stat_access(dcache_stat_access),
        .stat_load_access(dcache_stat_load_access),
        .stat_store_access(dcache_stat_store_access),
        .stat_load_hit(dcache_stat_load_hit),
        .stat_load_miss(dcache_stat_load_miss),
        .stat_store_hit(dcache_stat_store_hit),
        .stat_store_miss(dcache_stat_store_miss),
        .stat_refill_req(dcache_stat_refill_req),
        .stat_refill_resp(dcache_stat_refill_resp),
        .stat_write_req(dcache_stat_write_req),
        .stat_write_resp(dcache_stat_write_resp),
        .stat_refill_ld_bypass(dcache_stat_refill_ld_bypass),
        .stat_refill_store_merge(dcache_stat_refill_store_merge),
        .stat_req_wait_cycle(dcache_stat_req_wait_cycle),
        .stat_hit_resp_wait_cycle(dcache_stat_hit_resp_wait_cycle),
        .stat_miss_wait_cycle(dcache_stat_miss_wait_cycle),
        .stat_uncached_access(dcache_stat_uncached_access),
        .stat_writeback_cycle(dcache_stat_writeback_cycle)
`endif
`endif
    );

`ifdef NPC_USE_DPI
`ifndef NPC_CACHE_STAT
    assign dcache_stat_access = 64'd0;
    assign dcache_stat_load_access = 64'd0;
    assign dcache_stat_store_access = 64'd0;
    assign dcache_stat_load_hit = 64'd0;
    assign dcache_stat_load_miss = 64'd0;
    assign dcache_stat_store_hit = 64'd0;
    assign dcache_stat_store_miss = 64'd0;
    assign dcache_stat_refill_req = 64'd0;
    assign dcache_stat_refill_resp = 64'd0;
    assign dcache_stat_write_req = 64'd0;
    assign dcache_stat_write_resp = 64'd0;
    assign dcache_stat_refill_ld_bypass = 64'd0;
    assign dcache_stat_refill_store_merge = 64'd0;
    assign dcache_stat_req_wait_cycle = 64'd0;
    assign dcache_stat_hit_resp_wait_cycle = 64'd0;
    assign dcache_stat_miss_wait_cycle = 64'd0;
    assign dcache_stat_uncached_access = 64'd0;
    assign dcache_stat_writeback_cycle = 64'd0;
`endif
`else
    assign dcache_stat_access = 64'd0;
    assign dcache_stat_load_access = 64'd0;
    assign dcache_stat_store_access = 64'd0;
    assign dcache_stat_load_hit = 64'd0;
    assign dcache_stat_load_miss = 64'd0;
    assign dcache_stat_store_hit = 64'd0;
    assign dcache_stat_store_miss = 64'd0;
    assign dcache_stat_refill_req = 64'd0;
    assign dcache_stat_refill_resp = 64'd0;
    assign dcache_stat_write_req = 64'd0;
    assign dcache_stat_write_resp = 64'd0;
    assign dcache_stat_refill_ld_bypass = 64'd0;
    assign dcache_stat_refill_store_merge = 64'd0;
    assign dcache_stat_req_wait_cycle = 64'd0;
    assign dcache_stat_hit_resp_wait_cycle = 64'd0;
    assign dcache_stat_miss_wait_cycle = 64'd0;
    assign dcache_stat_uncached_access = 64'd0;
    assign dcache_stat_writeback_cycle = 64'd0;
`endif

    DCacheMmioMux u_dcache_mmio_mux (
        .clk(clk),
        .rst_n(rst_n),
        .in_req_valid(dbus_dcache_mem_req_valid),
        .in_req_ready(dbus_dcache_mem_req_ready),
        .in_req_write(dbus_dcache_mem_req_write),
        .in_req_addr(dbus_dcache_mem_req_addr),
        .in_req_wdata(dbus_dcache_mem_req_wdata),
        .in_req_wstrb(dbus_dcache_mem_req_wstrb),
        .in_req_len(dbus_dcache_mem_req_len),
        .in_resp_valid(dbus_dcache_mem_resp_valid),
        .in_resp_ready(dbus_dcache_mem_resp_ready),
        .in_resp_rdata(dbus_dcache_mem_resp_data),
        .mem_req_valid(dbus_mem_req_valid),
        .mem_req_ready(dbus_mem_req_ready),
        .mem_req_write(dbus_mem_req_write),
        .mem_req_addr(dbus_mem_req_addr),
        .mem_req_wdata(dbus_mem_req_wdata),
        .mem_req_wstrb(dbus_mem_req_wstrb),
        .mem_req_len(dbus_mem_req_len),
        .mem_resp_valid(dbus_mem_resp_valid),
        .mem_resp_ready(dbus_mem_resp_ready),
        .mem_resp_rdata(dbus_mem_resp_data),
        .timer_req_valid(timer_req_valid),
        .timer_req_ready(timer_req_ready),
        .timer_req_write(timer_req_write),
        .timer_req_addr(timer_req_addr),
        .timer_req_wdata(timer_req_wdata),
        .timer_req_wstrb(timer_req_wstrb),
        .timer_req_len(timer_req_len),
        .timer_resp_valid(timer_resp_valid),
        .timer_resp_ready(timer_resp_ready),
        .timer_resp_rdata(timer_resp_data)
    );

    AclintTimer #(
        .CLK_HZ(TIMER_CLK_HZ),
        .TIMEBASE_HZ(TIMEBASE_HZ)
    ) u_aclint_timer (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(timer_req_valid),
        .req_ready(timer_req_ready),
        .req_write(timer_req_write),
        .req_addr(timer_req_addr),
        .req_wdata(timer_req_wdata),
        .req_wstrb(timer_req_wstrb),
        .req_len(timer_req_len),
        .resp_valid(timer_resp_valid),
        .resp_ready(timer_resp_ready),
        .resp_rdata(timer_resp_data),
        .time_value(timer_time_value),
        .timecmp_value(timer_timecmp_value),
        .step_accum_value(timer_step_accum_value),
        .mtip(timer_mtip)
    );

`ifdef NPC_USE_DPI
    assign dbus_axi_awaddr = 32'b0;
    assign dbus_axi_awlen = 8'b0;
    assign dbus_axi_awsize = 3'b0;
    assign dbus_axi_awburst = 2'b0;
    assign dbus_axi_awvalid = 1'b0;
    assign dbus_axi_wdata = 32'b0;
    assign dbus_axi_wstrb = 4'b0;
    assign dbus_axi_wlast = 1'b0;
    assign dbus_axi_wvalid = 1'b0;
    assign dbus_axi_bready = 1'b0;
    assign dbus_axi_araddr = 32'b0;
    assign dbus_axi_arlen = 8'b0;
    assign dbus_axi_arsize = 3'b0;
    assign dbus_axi_arburst = 2'b0;
    assign dbus_axi_arvalid = 1'b0;
    assign dbus_axi_rready = 1'b0;

    SimPmemBridge #(
        .CHANNEL(1),
        .BATCH_WORDS(DCACHE_LINE_WORDS),
        .MEM_LATENCY(DPI_MEM_LATENCY)
    ) dbus_bridge (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(dbus_mem_req_valid),
        .req_ready(dbus_mem_req_ready),
        .req_write(dbus_mem_req_write),
        .req_addr(dbus_mem_req_addr),
        .req_wdata(dbus_mem_req_wdata),
        .req_wstrb(dbus_mem_req_wstrb),
        .req_len(dbus_mem_req_len),
        .resp_valid(dbus_mem_resp_valid),
        .resp_ready(dbus_mem_resp_ready),
        .resp_rdata(dbus_mem_resp_data)
    );
`else
    AxiPmemBridge #(
        .BATCH_WORDS(DCACHE_LINE_WORDS)
    ) dbus_bridge (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(dbus_mem_req_valid),
        .req_ready(dbus_mem_req_ready),
        .req_write(dbus_mem_req_write),
        .req_addr(dbus_mem_req_addr),
        .req_wdata(dbus_mem_req_wdata),
        .req_wstrb(dbus_mem_req_wstrb),
        .req_len(dbus_mem_req_len),
        .resp_valid(dbus_mem_resp_valid),
        .resp_ready(dbus_mem_resp_ready),
        .resp_rdata(dbus_mem_resp_data),
        .m_axi_awaddr(dbus_axi_awaddr),
        .m_axi_awlen(dbus_axi_awlen),
        .m_axi_awsize(dbus_axi_awsize),
        .m_axi_awburst(dbus_axi_awburst),
        .m_axi_awvalid(dbus_axi_awvalid),
        .m_axi_awready(dbus_axi_awready),
        .m_axi_wdata(dbus_axi_wdata),
        .m_axi_wstrb(dbus_axi_wstrb),
        .m_axi_wlast(dbus_axi_wlast),
        .m_axi_wvalid(dbus_axi_wvalid),
        .m_axi_wready(dbus_axi_wready),
        .m_axi_bresp(dbus_axi_bresp),
        .m_axi_bvalid(dbus_axi_bvalid),
        .m_axi_bready(dbus_axi_bready),
        .m_axi_araddr(dbus_axi_araddr),
        .m_axi_arlen(dbus_axi_arlen),
        .m_axi_arsize(dbus_axi_arsize),
        .m_axi_arburst(dbus_axi_arburst),
        .m_axi_arvalid(dbus_axi_arvalid),
        .m_axi_arready(dbus_axi_arready),
        .m_axi_rdata(dbus_axi_rdata),
        .m_axi_rresp(dbus_axi_rresp),
        .m_axi_rvalid(dbus_axi_rvalid),
        .m_axi_rready(dbus_axi_rready),
        .m_axi_rlast(dbus_axi_rlast)
    );
`endif
endmodule
