`timescale 1ns / 1ps

`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
module StatMemCpi (
    input clk,
    input rst_n,
    input sample_en,
    input [63:0] bucket_mem_lsu_wait,
    input [63:0] dcache_req_wait_cycle,
    input [63:0] dcache_hit_resp_wait_cycle,
    input [63:0] dcache_miss_wait_cycle,
    input [63:0] dcache_writeback_cycle,
    input ms_stage_block_req_load,
    input ms_stage_block_req_store,
    input ms_stage_block_resp_load,
    input ms_stage_block_resp_store,
    input ms_stage_block_resp_phase
);
    reg [63:0] mem_load_req_wait;
    reg [63:0] mem_store_req_wait;
    reg [63:0] mem_load_resp_wait;
    reg [63:0] mem_store_resp_wait;
    reg [63:0] mem_single_outstanding_wait;

    task print_stats;
        begin
            $display("[MemCPI] dcache_load_miss_wait=%0d dcache_store_miss_wait=%0d uncached_wait=%0d store_response_wait=%0d load_response_wait=%0d slow_fallback_wait=%0d mem_single_outstanding_wait=%0d req_load_wait=%0d req_store_wait=%0d cache_req_wait_total=%0d cache_hit_resp_wait_total=%0d cache_miss_wait_total=%0d writeback_wait_total=%0d",
                64'd0, 64'd0, 64'd0, mem_store_resp_wait, mem_load_resp_wait,
                bucket_mem_lsu_wait, mem_single_outstanding_wait,
                mem_load_req_wait, mem_store_req_wait,
                dcache_req_wait_cycle, dcache_hit_resp_wait_cycle,
                dcache_miss_wait_cycle, dcache_writeback_cycle);
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            mem_load_req_wait <= 64'd0;
            mem_store_req_wait <= 64'd0;
            mem_load_resp_wait <= 64'd0;
            mem_store_resp_wait <= 64'd0;
            mem_single_outstanding_wait <= 64'd0;
        end else if (sample_en) begin
            if (ms_stage_block_req_load) mem_load_req_wait <= mem_load_req_wait + 64'd1;
            if (ms_stage_block_req_store) mem_store_req_wait <= mem_store_req_wait + 64'd1;
            if (ms_stage_block_resp_load) mem_load_resp_wait <= mem_load_resp_wait + 64'd1;
            if (ms_stage_block_resp_store) mem_store_resp_wait <= mem_store_resp_wait + 64'd1;
            if (ms_stage_block_resp_phase) begin
                mem_single_outstanding_wait <= mem_single_outstanding_wait + 64'd1;
            end
        end
    end
endmodule
`endif
`endif
