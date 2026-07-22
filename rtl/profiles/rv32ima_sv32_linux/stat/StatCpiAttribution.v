`timescale 1ns / 1ps

`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
module StatCpiAttribution (
    input clk,
    input rst_n,
    input sample_en,
    input real_commit,
    input trap_flush_now,
    input wb_block_now,
    input store_wait_now,
    input dcache_wait_now,
    input mem_lsu_wait_now,
    input load_use_now,
    input raw_hazard_now,
    input csr_special_now,
    input id_stall_now,
    input ex_stall_now,
    input if_id_empty_now,
    input frontend_wait_now,
    input icache_fetch_wait_now,
    input branch_recovery_now,
    input icache_pipe_resp_block_now,
    input stage_latency_now,

    output reg [63:0] cycle_count,
    output reg [63:0] commit_count,
    output reg [63:0] bucket_trap_flush,
    output reg [63:0] bucket_wb_block,
    output reg [63:0] bucket_mem_lsu_wait,
    output reg [63:0] bucket_dcache_wait,
    output reg [63:0] bucket_store_wait,
    output reg [63:0] bucket_load_use,
    output reg [63:0] bucket_raw_hazard,
    output reg [63:0] bucket_csr_special,
    output reg [63:0] bucket_id_stall,
    output reg [63:0] bucket_ex_stall,
    output reg [63:0] bucket_if_id_empty,
    output reg [63:0] bucket_frontend_wait,
    output reg [63:0] bucket_icache_fetch_wait,
    output reg [63:0] bucket_branch_recovery,
    output reg [63:0] bucket_resp_block,
    output reg [63:0] bucket_stage_latency,
    output reg [63:0] bucket_unknown,
    output [63:0] cpi_attr_mismatch,
    output bucket_frontend_wait_fire,
    output bucket_stage_latency_fire
);
    reg [63:0] bubble_count;

    wire bubble_sample = sample_en && !real_commit;
    wire bucket_trap_flush_fire = bubble_sample && trap_flush_now;
    wire bucket_wb_block_fire = bubble_sample && !trap_flush_now && wb_block_now;
    wire bucket_store_wait_fire = bubble_sample && !trap_flush_now &&
        !wb_block_now && store_wait_now;
    wire bucket_dcache_wait_fire = bubble_sample && !trap_flush_now &&
        !wb_block_now && !store_wait_now && dcache_wait_now;
    wire bucket_mem_lsu_wait_fire = bubble_sample && !trap_flush_now &&
        !wb_block_now && !store_wait_now && !dcache_wait_now &&
        mem_lsu_wait_now;
    wire bucket_load_use_fire = bubble_sample && !trap_flush_now &&
        !wb_block_now && !store_wait_now && !dcache_wait_now &&
        !mem_lsu_wait_now && load_use_now;
    wire bucket_raw_hazard_fire = bubble_sample && !trap_flush_now &&
        !wb_block_now && !store_wait_now && !dcache_wait_now &&
        !mem_lsu_wait_now && !load_use_now && raw_hazard_now;
    wire bucket_csr_special_fire = bubble_sample && !trap_flush_now &&
        !wb_block_now && !store_wait_now && !dcache_wait_now &&
        !mem_lsu_wait_now && !load_use_now && !raw_hazard_now &&
        csr_special_now;
    wire bucket_id_stall_fire = bubble_sample && !trap_flush_now &&
        !wb_block_now && !store_wait_now && !dcache_wait_now &&
        !mem_lsu_wait_now && !load_use_now && !raw_hazard_now &&
        !csr_special_now && id_stall_now;
    wire bucket_ex_stall_fire = bubble_sample && !trap_flush_now &&
        !wb_block_now && !store_wait_now && !dcache_wait_now &&
        !mem_lsu_wait_now && !load_use_now && !raw_hazard_now &&
        !csr_special_now && !id_stall_now && ex_stall_now;
    wire bucket_if_id_empty_fire = bubble_sample && !trap_flush_now &&
        !wb_block_now && !store_wait_now && !dcache_wait_now &&
        !mem_lsu_wait_now && !load_use_now && !raw_hazard_now &&
        !csr_special_now && !id_stall_now && !ex_stall_now &&
        if_id_empty_now;
    assign bucket_frontend_wait_fire = bubble_sample && !trap_flush_now &&
        !wb_block_now && !store_wait_now && !dcache_wait_now &&
        !mem_lsu_wait_now && !load_use_now && !raw_hazard_now &&
        !csr_special_now && !id_stall_now && !ex_stall_now &&
        !if_id_empty_now && frontend_wait_now;
    wire bucket_icache_fetch_wait_fire = bubble_sample && !trap_flush_now &&
        !wb_block_now && !store_wait_now && !dcache_wait_now &&
        !mem_lsu_wait_now && !load_use_now && !raw_hazard_now &&
        !csr_special_now && !id_stall_now && !ex_stall_now &&
        !if_id_empty_now && !frontend_wait_now && icache_fetch_wait_now;
    wire bucket_branch_recovery_fire = bubble_sample && !trap_flush_now &&
        !wb_block_now && !store_wait_now && !dcache_wait_now &&
        !mem_lsu_wait_now && !load_use_now && !raw_hazard_now &&
        !csr_special_now && !id_stall_now && !ex_stall_now &&
        !if_id_empty_now && !frontend_wait_now && !icache_fetch_wait_now &&
        branch_recovery_now;
    wire bucket_resp_block_fire = bubble_sample && !trap_flush_now &&
        !wb_block_now && !store_wait_now && !dcache_wait_now &&
        !mem_lsu_wait_now && !load_use_now && !raw_hazard_now &&
        !csr_special_now && !id_stall_now && !ex_stall_now &&
        !if_id_empty_now && !frontend_wait_now && !icache_fetch_wait_now &&
        !branch_recovery_now && icache_pipe_resp_block_now;
    assign bucket_stage_latency_fire = bubble_sample && !trap_flush_now &&
        !wb_block_now && !store_wait_now && !dcache_wait_now &&
        !mem_lsu_wait_now && !load_use_now && !raw_hazard_now &&
        !csr_special_now && !id_stall_now && !ex_stall_now &&
        !if_id_empty_now && !frontend_wait_now && !icache_fetch_wait_now &&
        !branch_recovery_now && !icache_pipe_resp_block_now &&
        stage_latency_now;
    wire bucket_unknown_fire = bubble_sample && !trap_flush_now &&
        !wb_block_now && !store_wait_now && !dcache_wait_now &&
        !mem_lsu_wait_now && !load_use_now && !raw_hazard_now &&
        !csr_special_now && !id_stall_now && !ex_stall_now &&
        !if_id_empty_now && !frontend_wait_now && !icache_fetch_wait_now &&
        !branch_recovery_now && !icache_pipe_resp_block_now &&
        !stage_latency_now;

    wire [63:0] bubble_sum =
        bucket_trap_flush + bucket_wb_block + bucket_mem_lsu_wait +
        bucket_dcache_wait + bucket_store_wait + bucket_load_use +
        bucket_raw_hazard + bucket_csr_special + bucket_id_stall +
        bucket_ex_stall + bucket_if_id_empty + bucket_frontend_wait +
        bucket_icache_fetch_wait + bucket_branch_recovery +
        bucket_resp_block + bucket_stage_latency + bucket_unknown;
    wire [63:0] bubble_expected = cycle_count - commit_count;
    assign cpi_attr_mismatch = (bubble_sum >= bubble_expected) ?
        (bubble_sum - bubble_expected) : (bubble_expected - bubble_sum);

    task print_cpi_line;
        input [255:0] prefix;
        input [255:0] name;
        input [63:0] cycles;
        reg [63:0] x100;
        begin
            if (commit_count == 64'd0) begin
                $display("[%0s] %0s=N/A", prefix, name);
            end else begin
                x100 = (cycles * 64'd100) / commit_count;
                $display("[%0s] %0s=%0d.%02d (%0d/%0d)",
                    prefix, name, x100 / 64'd100, x100 % 64'd100,
                    cycles, commit_count);
            end
        end
    endtask

    task print_stats;
        begin
            $display("[CPIAttribution] cycles=%0d commit=%0d bubble=%0d CPI_ideal_commit=1.00",
                cycle_count, commit_count, bubble_expected);
            print_cpi_line("CPIAttribution", "CPI_total", cycle_count);
            $display("[CPIAttribution] exclusive_bubbles trap_flush=%0d wb_block=%0d mem_lsu_wait=%0d dcache_wait=%0d store_wait=%0d load_use=%0d raw_hazard=%0d csr_or_special=%0d id_stage_stall=%0d ex_stage_stall=%0d if_id_empty=%0d frontend_wait=%0d icache_fetch_wait=%0d branch_recovery=%0d resp_block=%0d stage_latency=%0d unknown=%0d sum=%0d mismatch=%0d",
                bucket_trap_flush, bucket_wb_block, bucket_mem_lsu_wait,
                bucket_dcache_wait, bucket_store_wait, bucket_load_use,
                bucket_raw_hazard, bucket_csr_special, bucket_id_stall,
                bucket_ex_stall, bucket_if_id_empty, bucket_frontend_wait,
                bucket_icache_fetch_wait, bucket_branch_recovery,
                bucket_resp_block, bucket_stage_latency, bucket_unknown,
                bubble_sum, cpi_attr_mismatch);
            print_cpi_line("CPIAttribution", "redirect_contrib",
                bucket_trap_flush + bucket_branch_recovery);
            print_cpi_line("CPIAttribution", "frontend_wait_contrib",
                bucket_frontend_wait + bucket_icache_fetch_wait);
            print_cpi_line("CPIAttribution", "mem_lsu_wait_contrib",
                bucket_mem_lsu_wait + bucket_dcache_wait + bucket_store_wait);
            print_cpi_line("CPIAttribution", "hazard_contrib",
                bucket_load_use + bucket_raw_hazard + bucket_csr_special);
            print_cpi_line("CPIAttribution", "resp_block_contrib",
                bucket_resp_block);
            print_cpi_line("CPIAttribution", "stage_latency_contrib",
                bucket_stage_latency);
            print_cpi_line("CPIAttribution", "unknown_contrib", bucket_unknown);
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count <= 64'd0;
            commit_count <= 64'd0;
            bubble_count <= 64'd0;
            bucket_trap_flush <= 64'd0;
            bucket_wb_block <= 64'd0;
            bucket_mem_lsu_wait <= 64'd0;
            bucket_dcache_wait <= 64'd0;
            bucket_store_wait <= 64'd0;
            bucket_load_use <= 64'd0;
            bucket_raw_hazard <= 64'd0;
            bucket_csr_special <= 64'd0;
            bucket_id_stall <= 64'd0;
            bucket_ex_stall <= 64'd0;
            bucket_if_id_empty <= 64'd0;
            bucket_frontend_wait <= 64'd0;
            bucket_icache_fetch_wait <= 64'd0;
            bucket_branch_recovery <= 64'd0;
            bucket_resp_block <= 64'd0;
            bucket_stage_latency <= 64'd0;
            bucket_unknown <= 64'd0;
        end else if (sample_en) begin
            cycle_count <= cycle_count + 64'd1;
            if (real_commit) begin
                commit_count <= commit_count + 64'd1;
            end else begin
                bubble_count <= bubble_count + 64'd1;
                if (bucket_trap_flush_fire) begin
                    bucket_trap_flush <= bucket_trap_flush + 64'd1;
                end else if (bucket_wb_block_fire) begin
                    bucket_wb_block <= bucket_wb_block + 64'd1;
                end else if (bucket_store_wait_fire) begin
                    bucket_store_wait <= bucket_store_wait + 64'd1;
                end else if (bucket_dcache_wait_fire) begin
                    bucket_dcache_wait <= bucket_dcache_wait + 64'd1;
                end else if (bucket_mem_lsu_wait_fire) begin
                    bucket_mem_lsu_wait <= bucket_mem_lsu_wait + 64'd1;
                end else if (bucket_load_use_fire) begin
                    bucket_load_use <= bucket_load_use + 64'd1;
                end else if (bucket_raw_hazard_fire) begin
                    bucket_raw_hazard <= bucket_raw_hazard + 64'd1;
                end else if (bucket_csr_special_fire) begin
                    bucket_csr_special <= bucket_csr_special + 64'd1;
                end else if (bucket_id_stall_fire) begin
                    bucket_id_stall <= bucket_id_stall + 64'd1;
                end else if (bucket_ex_stall_fire) begin
                    bucket_ex_stall <= bucket_ex_stall + 64'd1;
                end else if (bucket_if_id_empty_fire) begin
                    bucket_if_id_empty <= bucket_if_id_empty + 64'd1;
                end else if (bucket_frontend_wait_fire) begin
                    bucket_frontend_wait <= bucket_frontend_wait + 64'd1;
                end else if (bucket_icache_fetch_wait_fire) begin
                    bucket_icache_fetch_wait <= bucket_icache_fetch_wait + 64'd1;
                end else if (bucket_branch_recovery_fire) begin
                    bucket_branch_recovery <= bucket_branch_recovery + 64'd1;
                end else if (bucket_resp_block_fire) begin
                    bucket_resp_block <= bucket_resp_block + 64'd1;
                end else if (bucket_stage_latency_fire) begin
                    bucket_stage_latency <= bucket_stage_latency + 64'd1;
                end else if (bucket_unknown_fire) begin
                    bucket_unknown <= bucket_unknown + 64'd1;
                end
            end
        end
    end
endmodule
`endif
`endif
