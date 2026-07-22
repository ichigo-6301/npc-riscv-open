`timescale 1ns / 1ps

`ifdef NPC_USE_DPI
`ifdef NPC_HIT_PATH_STAT
module HitPathStat (
    input clk,
    input rst_n,

    input commit_valid,
    input commit_is_ebreak,
    input commit_illegal,

    input [63:0] if_ptw_cycle,
    input [63:0] lsu_ptw_cycle,
    input [63:0] if_tlb_hit_to_cache_req_cycle,
    input [63:0] lsu_tlb_hit_to_cache_req_cycle,
    input [63:0] if_bridge_state_wait_cycle,
    input [63:0] lsu_bridge_state_wait_cycle,
    input [63:0] if_cache_req_wait_cycle,
    input [63:0] if_cache_resp_wait_cycle,
    input [63:0] lsu_cache_req_wait_cycle,
    input [63:0] lsu_cache_resp_wait_cycle,
    input [63:0] if_fetch_req_count,
    input [63:0] if_fetch_resp_count,
    input [63:0] if_pipe_issue_count,
    input [63:0] if_pipe_resp_count,
    input [63:0] if_pipe_epoch_drop_count,
    input [63:0] if_pipe_replay_count,
    input [63:0] if_pipe_ptw_miss_count,
    input [63:0] if_pipe_ptw_fault_count,
    input [63:0] if_pipe_stall_cycle,
    input [63:0] if_pipe_icache_miss_count,
    input [63:0] if_pipe_icache_replay_count,
    input [63:0] lsu_data_req_count,
    input [63:0] lsu_data_resp_count,
    input [63:0] lsu_uncached_req_count,
    input [63:0] lsu_pipe_issue_count,
    input [63:0] lsu_pipe_resp_count,
    input [63:0] lsu_pipe_epoch_drop_count,
    input [63:0] lsu_pipe_dtlb_hit_count,
    input [63:0] lsu_pipe_dtlb_miss_count,
    input [63:0] lsu_pipe_replay_count,
    input [63:0] lsu_pipe_fault_count,
    input [63:0] lsu_pipe_stall_cycle,
    input [63:0] lsu_pipe_dcache_hit_count,
    input [63:0] lsu_pipe_dcache_miss_count,
    input [63:0] lsu_pipe_store_hit_count,
    input [63:0] lsu_pipe_load_hit_count,
    input [63:0] lsu_pipe_slow_fallback_count,
    input [63:0] lsu_pipe_load_miss_replay_count,
    input [63:0] lsu_pipe_store_miss_replay_count,
    input [63:0] lsu_pipe_direct_uncached_count,
    input [63:0] lsu_pipe_direct_non_dtlb_hit_count,
    input [63:0] lsu_pipe_direct_perm_fault_count,
    input [63:0] lsu_pipe_direct_cross_page_count,
    input [63:0] lsu_pipe_direct_fast_block_count,
    input [63:0] lsu_pipe_direct_fast_block_atomic_count,
    input [63:0] lsu_pipe_direct_fast_block_misaligned_count,
    input [63:0] lsu_pipe_direct_fast_block_exception_count,
    input [63:0] lsu_pipe_direct_fast_block_phase2_count,
    input [63:0] lsu_pipe_direct_fast_block_other_count,
    input [63:0] lsu_pipe_direct_other_count,
    input [63:0] lsu_pipe_hit_latency_sum,
    input [63:0] lsu_pipe_hit_latency_count,
    input [63:0] lsu_pipe_hit_latency_max,
    input [63:0] lsu_pipe_load_hit_latency_sum,
    input [63:0] lsu_pipe_load_hit_latency_count,
    input [63:0] lsu_pipe_load_hit_latency_max,
    input [63:0] lsu_pipe_store_hit_latency_sum,
    input [63:0] lsu_pipe_store_hit_latency_count,
    input [63:0] lsu_pipe_store_hit_latency_max,
    input [63:0] lsu_pipe_slow_fallback_latency_sum,
    input [63:0] lsu_pipe_slow_fallback_latency_count,
    input [63:0] lsu_pipe_slow_fallback_latency_max,
    input [63:0] lsu_pipe_slow_direct_latency_sum,
    input [63:0] lsu_pipe_slow_direct_latency_count,
    input [63:0] lsu_pipe_slow_direct_latency_max,
    input [63:0] lsu_pipe_slow_replay_latency_sum,
    input [63:0] lsu_pipe_slow_replay_latency_count,
    input [63:0] lsu_pipe_slow_replay_latency_max,

    input [63:0] icache_req_wait_cycle,
    input [63:0] icache_hit_resp_wait_cycle,
    input [63:0] icache_miss_wait_cycle,
    input [63:0] icache_uncached_access,
    input [63:0] dcache_req_wait_cycle,
    input [63:0] dcache_hit_resp_wait_cycle,
    input [63:0] dcache_miss_wait_cycle,
    input [63:0] dcache_uncached_access,
    input [63:0] dcache_writeback_cycle,

    input [63:0] branch_redirect_wait_cycle,
    input [63:0] branch_redirect_count,
    input [63:0] branch_mispredict_count,
    input [63:0] load_use_stall_cycle,
    input [63:0] id_reg_hazard_cycle,
    input [63:0] ms_block_cycle
);
    reg [63:0] cycle_count;
    reg [63:0] commit_count;
    reg printed;
    reg [63:0] known_wait;
    reg [63:0] ptw_cycles;
    reg [63:0] tlb_hit_path_wait;
    reg [63:0] icache_wait;
    reg [63:0] dcache_wait;
    reg [63:0] bridge_wait;
    reg [63:0] other_stall;
    reg [63:0] cpi_x100;
    reg [63:0] avg_hit_x100;
    reg [63:0] avg_load_hit_x100;
    reg [63:0] avg_store_hit_x100;
    reg [63:0] avg_slow_x100;
    reg [63:0] avg_slow_direct_x100;
    reg [63:0] avg_slow_replay_x100;

    task print_cpi;
        begin
            if (commit_count == 64'd0) begin
                $display("[CPIBreakdown] CPI_total=N/A");
            end else begin
                cpi_x100 = (cycle_count * 64'd100) / commit_count;
                $display("[CPIBreakdown] CPI_total=%0d.%02d (%0d/%0d)",
                    cpi_x100 / 64'd100, cpi_x100 % 64'd100,
                    cycle_count, commit_count);
            end
        end
    endtask

    task print_stats;
        begin
            ptw_cycles = if_ptw_cycle + lsu_ptw_cycle;
            tlb_hit_path_wait = if_tlb_hit_to_cache_req_cycle + lsu_tlb_hit_to_cache_req_cycle;
            icache_wait = icache_req_wait_cycle + icache_hit_resp_wait_cycle + icache_miss_wait_cycle;
            dcache_wait = dcache_req_wait_cycle + dcache_hit_resp_wait_cycle +
                dcache_miss_wait_cycle + dcache_writeback_cycle;
            bridge_wait = if_bridge_state_wait_cycle + lsu_bridge_state_wait_cycle;
            known_wait = ptw_cycles + tlb_hit_path_wait + icache_wait + dcache_wait +
                branch_redirect_wait_cycle + load_use_stall_cycle;

            $display("[HitPathStat] if_bridge fetch_req=%0d fetch_resp=%0d tlb_hit_to_cache_req=%0d cache_req_wait=%0d cache_resp_wait=%0d bridge_wait=%0d",
                if_fetch_req_count, if_fetch_resp_count,
                if_tlb_hit_to_cache_req_cycle, if_cache_req_wait_cycle,
                if_cache_resp_wait_cycle, if_bridge_state_wait_cycle);
            $display("[IFPipeStat] issue=%0d resp=%0d epoch_drop=%0d replay=%0d ptw_miss=%0d ptw_fault=%0d stall=%0d icache_miss=%0d icache_replay=%0d",
                if_pipe_issue_count, if_pipe_resp_count, if_pipe_epoch_drop_count,
                if_pipe_replay_count, if_pipe_ptw_miss_count, if_pipe_ptw_fault_count,
                if_pipe_stall_cycle, if_pipe_icache_miss_count, if_pipe_icache_replay_count);
            $display("[HitPathStat] lsu_bridge data_req=%0d data_resp=%0d uncached_req=%0d tlb_hit_to_cache_req=%0d cache_req_wait=%0d cache_resp_wait=%0d bridge_wait=%0d",
                lsu_data_req_count, lsu_data_resp_count, lsu_uncached_req_count,
                lsu_tlb_hit_to_cache_req_cycle, lsu_cache_req_wait_cycle,
                lsu_cache_resp_wait_cycle, lsu_bridge_state_wait_cycle);
            $display("[LSUPipeStat] issue=%0d resp=%0d epoch_drop=%0d dtlb_hit=%0d dtlb_miss=%0d replay=%0d fault=%0d stall=%0d dcache_hit=%0d dcache_miss=%0d store_hit=%0d load_hit=%0d slow_fallback=%0d",
                lsu_pipe_issue_count, lsu_pipe_resp_count, lsu_pipe_epoch_drop_count,
                lsu_pipe_dtlb_hit_count, lsu_pipe_dtlb_miss_count,
                lsu_pipe_replay_count, lsu_pipe_fault_count, lsu_pipe_stall_cycle,
                lsu_pipe_dcache_hit_count, lsu_pipe_dcache_miss_count,
                lsu_pipe_store_hit_count, lsu_pipe_load_hit_count,
                lsu_pipe_slow_fallback_count);
            $display("[LSUPipeFallback] load_miss_replay=%0d store_miss_replay=%0d direct_uncached=%0d direct_non_dtlb_hit=%0d direct_perm_fault=%0d direct_cross_page=%0d direct_fast_block=%0d direct_other=%0d fast_block_atomic=%0d fast_block_misaligned=%0d fast_block_exception=%0d fast_block_phase2=%0d fast_block_other=%0d",
                lsu_pipe_load_miss_replay_count, lsu_pipe_store_miss_replay_count,
                lsu_pipe_direct_uncached_count, lsu_pipe_direct_non_dtlb_hit_count,
                lsu_pipe_direct_perm_fault_count, lsu_pipe_direct_cross_page_count,
                lsu_pipe_direct_fast_block_count, lsu_pipe_direct_other_count,
                lsu_pipe_direct_fast_block_atomic_count,
                lsu_pipe_direct_fast_block_misaligned_count,
                lsu_pipe_direct_fast_block_exception_count,
                lsu_pipe_direct_fast_block_phase2_count,
                lsu_pipe_direct_fast_block_other_count);
            avg_hit_x100 = (lsu_pipe_hit_latency_count == 64'd0) ? 64'd0 :
                (lsu_pipe_hit_latency_sum * 64'd100) / lsu_pipe_hit_latency_count;
            avg_load_hit_x100 = (lsu_pipe_load_hit_latency_count == 64'd0) ? 64'd0 :
                (lsu_pipe_load_hit_latency_sum * 64'd100) / lsu_pipe_load_hit_latency_count;
            avg_store_hit_x100 = (lsu_pipe_store_hit_latency_count == 64'd0) ? 64'd0 :
                (lsu_pipe_store_hit_latency_sum * 64'd100) / lsu_pipe_store_hit_latency_count;
            avg_slow_x100 = (lsu_pipe_slow_fallback_latency_count == 64'd0) ? 64'd0 :
                (lsu_pipe_slow_fallback_latency_sum * 64'd100) / lsu_pipe_slow_fallback_latency_count;
            avg_slow_direct_x100 = (lsu_pipe_slow_direct_latency_count == 64'd0) ? 64'd0 :
                (lsu_pipe_slow_direct_latency_sum * 64'd100) / lsu_pipe_slow_direct_latency_count;
            avg_slow_replay_x100 = (lsu_pipe_slow_replay_latency_count == 64'd0) ? 64'd0 :
                (lsu_pipe_slow_replay_latency_sum * 64'd100) / lsu_pipe_slow_replay_latency_count;
            $display("[LSUPipeLatency] hit count=%0d avg=%0d.%02d max=%0d load_hit count=%0d avg=%0d.%02d max=%0d store_hit count=%0d avg=%0d.%02d max=%0d slow count=%0d avg=%0d.%02d max=%0d slow_direct count=%0d avg=%0d.%02d max=%0d slow_replay count=%0d avg=%0d.%02d max=%0d",
                lsu_pipe_hit_latency_count, avg_hit_x100 / 64'd100, avg_hit_x100 % 64'd100,
                lsu_pipe_hit_latency_max,
                lsu_pipe_load_hit_latency_count, avg_load_hit_x100 / 64'd100, avg_load_hit_x100 % 64'd100,
                lsu_pipe_load_hit_latency_max,
                lsu_pipe_store_hit_latency_count, avg_store_hit_x100 / 64'd100, avg_store_hit_x100 % 64'd100,
                lsu_pipe_store_hit_latency_max,
                lsu_pipe_slow_fallback_latency_count, avg_slow_x100 / 64'd100, avg_slow_x100 % 64'd100,
                lsu_pipe_slow_fallback_latency_max,
                lsu_pipe_slow_direct_latency_count, avg_slow_direct_x100 / 64'd100, avg_slow_direct_x100 % 64'd100,
                lsu_pipe_slow_direct_latency_max,
                lsu_pipe_slow_replay_latency_count, avg_slow_replay_x100 / 64'd100, avg_slow_replay_x100 % 64'd100,
                lsu_pipe_slow_replay_latency_max);
            $display("[HitPathStat] cache_wait icache_req=%0d icache_hit_resp=%0d icache_miss=%0d icache_uncached=%0d dcache_req=%0d dcache_hit_resp=%0d dcache_miss=%0d dcache_writeback=%0d dcache_uncached=%0d",
                icache_req_wait_cycle, icache_hit_resp_wait_cycle, icache_miss_wait_cycle,
                icache_uncached_access, dcache_req_wait_cycle, dcache_hit_resp_wait_cycle,
                dcache_miss_wait_cycle, dcache_writeback_cycle, dcache_uncached_access);
            $display("[HitPathStat] control branch_redirect_wait=%0d branch_redirect_count=%0d branch_mispredict=%0d load_use_stall=%0d id_reg_hazard=%0d ms_block=%0d",
                branch_redirect_wait_cycle, branch_redirect_count, branch_mispredict_count,
                load_use_stall_cycle, id_reg_hazard_cycle, ms_block_cycle);
            $display("[CPIBreakdown] total_cycles=%0d commit=%0d", cycle_count, commit_count);
            print_cpi();
            $display("[CPIBreakdown] ptw_cycles=%0d tlb_hit_path_wait=%0d icache_wait=%0d dcache_wait=%0d branch_redirect_wait=%0d load_use_stall=%0d bridge_wait=%0d known_wait=%0d",
                ptw_cycles, tlb_hit_path_wait, icache_wait, dcache_wait,
                branch_redirect_wait_cycle, load_use_stall_cycle, bridge_wait, known_wait);
            if (cycle_count > commit_count + known_wait) begin
                other_stall = cycle_count - commit_count - known_wait;
                $display("[CPIBreakdown] other_stall=%0d", other_stall);
            end else begin
                $display("[CPIBreakdown] other_stall=N/A reason=overlap");
            end
            $display("[CPIBreakdown] note=reset_to_halt counters may overlap; use buckets for bottleneck direction, not exact exclusive accounting");
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 64'd0;
            commit_count <= 64'd0;
            printed <= 1'b0;
        end else begin
            cycle_count <= cycle_count + 64'd1;
            if (commit_valid && !commit_is_ebreak && !commit_illegal) begin
                commit_count <= commit_count + 64'd1;
            end
            if (!printed && commit_valid && (commit_is_ebreak || commit_illegal)) begin
                print_stats();
                printed <= 1'b1;
            end
        end
    end
endmodule
`endif
`endif
