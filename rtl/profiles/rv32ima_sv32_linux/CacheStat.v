`timescale 1ns / 1ps

`ifdef NPC_CACHE_STAT
module CacheStat #(
    parameter integer ICACHE_MISS_PENALTY = 20,
    parameter integer DCACHE_MISS_PENALTY = 20
) (
    input clk,
    input rst_n,

    input commit_valid,
    input commit_is_ebreak,
    input commit_illegal,

    input [63:0] icache_access,
    input [63:0] icache_hit,
    input [63:0] icache_miss,
    input [63:0] icache_refill_req,
    input [63:0] icache_refill_resp,
    input [63:0] icache_refill_bypass,
    input [63:0] icache_req_wait_cycle,
    input [63:0] icache_hit_resp_wait_cycle,
    input [63:0] icache_miss_wait_cycle,
    input [63:0] icache_uncached_access,
    input [63:0] icache_pipe_req_valid_cycle,
    input [63:0] icache_pipe_req_ready_cycle,
    input [63:0] icache_pipe_req_fire_cycle,
    input [63:0] icache_pipe_req_valid_not_ready_cycle,
    input [63:0] icache_pipe_resp_valid_cycle,
    input [63:0] icache_pipe_resp_ready_cycle,
    input [63:0] icache_pipe_resp_fire_cycle,
    input [63:0] icache_pipe_data_valid_cycle,
    input [63:0] icache_pipe_resp_block_cycle,
    input [63:0] icache_pipe_ready_block_state_cycle,
    input [63:0] icache_pipe_ready_block_data_cycle,
    input [63:0] icache_pipe_ready_block_resp_cycle,
    input [63:0] icache_pipe_ready_block_cpu_cycle,
    input [63:0] icache_pipe_ready_block_maint_cycle,
    input [63:0] icache_pipe_state_idle_cycle,
    input [63:0] icache_pipe_state_refill_cycle,
    input [63:0] icache_pipe_state_uncached_cycle,
    input [63:0] icache_pipe_hit_fire_cycle,
    input [63:0] icache_pipe_miss_fire_cycle,
    input [63:0] icache_pipe_refill_busy_cycle,
    input [63:0] icache_pipe_resp_fifo_full_cycle,
    input [63:0] if_pipe_epoch_drop_count,

    input [63:0] dcache_access,
    input [63:0] dcache_load_access,
    input [63:0] dcache_store_access,
    input [63:0] dcache_load_hit,
    input [63:0] dcache_load_miss,
    input [63:0] dcache_store_hit,
    input [63:0] dcache_store_miss,
    input [63:0] dcache_refill_req,
    input [63:0] dcache_refill_resp,
    input [63:0] dcache_write_req,
    input [63:0] dcache_write_resp,
    input [63:0] dcache_refill_ld_bypass,
    input [63:0] dcache_refill_store_merge,
    input [63:0] dcache_req_wait_cycle,
    input [63:0] dcache_hit_resp_wait_cycle,
    input [63:0] dcache_miss_wait_cycle,
    input [63:0] dcache_uncached_access,
    input [63:0] dcache_writeback_cycle,

    input ibus_req_valid,
    input ibus_req_ready,
    input ibus_resp_valid,
    input ibus_resp_ready,
    input dbus_req_valid,
    input dbus_req_ready,
    input dbus_resp_valid,
    input dbus_resp_ready
);
    reg printed;
    reg [63:0] rate_x100;
    reg [63:0] ibus_req_wait_cycles;
    reg [63:0] ibus_resp_wait_cycles;
    reg [63:0] dbus_req_wait_cycles;
    reg [63:0] dbus_resp_wait_cycles;
    wire [63:0] dcache_hit = dcache_load_hit + dcache_store_hit;
    wire [63:0] dcache_miss = dcache_load_miss + dcache_store_miss;
    wire [63:0] icache_tmt = icache_miss * ICACHE_MISS_PENALTY;
    wire [63:0] dcache_tmt = dcache_load_miss * DCACHE_MISS_PENALTY;
    wire [63:0] total_tmt = icache_tmt + dcache_tmt;
    wire [63:0] memory_wait_total =
        ibus_req_wait_cycles + ibus_resp_wait_cycles +
        dbus_req_wait_cycles + dbus_resp_wait_cycles;

    task print_percent;
        input [255:0] name;
        input [63:0] numerator;
        input [63:0] denominator;
        begin
            if (denominator == 64'd0) begin
                $display("[CacheStat] %0s=N/A", name);
            end else begin
                rate_x100 = (numerator * 64'd10000) / denominator;
                $display("[CacheStat] %0s=%0d.%02d%% (%0d/%0d)",
                    name, rate_x100 / 64'd100, rate_x100 % 64'd100,
                    numerator, denominator);
            end
        end
    endtask

    task print_stats;
        begin
            $display("[CacheStat] icache access=%0d hit=%0d miss=%0d refill_req=%0d refill_resp=%0d refill_bypass=%0d",
                icache_access, icache_hit, icache_miss,
                icache_refill_req, icache_refill_resp, icache_refill_bypass);
            $display("[CacheStat] icache_wait req=%0d hit_resp=%0d miss=%0d uncached=%0d",
                icache_req_wait_cycle, icache_hit_resp_wait_cycle,
                icache_miss_wait_cycle, icache_uncached_access);
            $display("[ICachePipeStat] req_valid=%0d req_ready=%0d req_fire=%0d req_block=%0d resp_valid=%0d resp_ready=%0d resp_fire=%0d resp_block=%0d resp_skid_valid=%0d resp_fifo_full=%0d resp_epoch_drop=%0d",
                icache_pipe_req_valid_cycle, icache_pipe_req_ready_cycle,
                icache_pipe_req_fire_cycle, icache_pipe_req_valid_not_ready_cycle,
                icache_pipe_resp_valid_cycle, icache_pipe_resp_ready_cycle,
                icache_pipe_resp_fire_cycle, icache_pipe_resp_block_cycle,
                icache_pipe_data_valid_cycle, icache_pipe_resp_fifo_full_cycle,
                if_pipe_epoch_drop_count);
            $display("[ICachePipeStat] ready_block state=%0d data=%0d resp=%0d cpu=%0d maint=%0d state_idle=%0d state_refill=%0d state_uncached=%0d hit_fire=%0d miss_fire=%0d refill_busy=%0d",
                icache_pipe_ready_block_state_cycle, icache_pipe_ready_block_data_cycle,
                icache_pipe_ready_block_resp_cycle, icache_pipe_ready_block_cpu_cycle,
                icache_pipe_ready_block_maint_cycle, icache_pipe_state_idle_cycle,
                icache_pipe_state_refill_cycle, icache_pipe_state_uncached_cycle,
                icache_pipe_hit_fire_cycle, icache_pipe_miss_fire_cycle,
                icache_pipe_refill_busy_cycle);
            print_percent("icache_miss_rate", icache_miss, icache_access);
            $display("[CacheStat] dcache access=%0d load=%0d store=%0d hit=%0d miss=%0d",
                dcache_access, dcache_load_access, dcache_store_access,
                dcache_hit, dcache_miss);
            $display("[CacheStat] dcache_wait req=%0d hit_resp=%0d miss=%0d writeback=%0d uncached=%0d",
                dcache_req_wait_cycle, dcache_hit_resp_wait_cycle,
                dcache_miss_wait_cycle, dcache_writeback_cycle, dcache_uncached_access);
            $display("[CacheStat] dcache_load hit=%0d miss=%0d refill_req=%0d refill_resp=%0d refill_ld_bypass=%0d",
                dcache_load_hit, dcache_load_miss,
                dcache_refill_req, dcache_refill_resp, dcache_refill_ld_bypass);
            print_percent("dcache_load_miss_rate", dcache_load_miss, dcache_load_access);
            $display("[CacheStat] dcache_store hit=%0d miss=%0d write_req=%0d write_resp=%0d refill_store_merge=%0d",
                dcache_store_hit, dcache_store_miss,
                dcache_write_req, dcache_write_resp, dcache_refill_store_merge);
            print_percent("dcache_store_miss_rate", dcache_store_miss, dcache_store_access);
            $display("[CacheStat] memory_wait ibus_req=%0d ibus_resp=%0d dbus_req=%0d dbus_resp=%0d total=%0d",
                ibus_req_wait_cycles, ibus_resp_wait_cycles,
                dbus_req_wait_cycles, dbus_resp_wait_cycles, memory_wait_total);
            $display("[CacheStat] TMT icache=%0d dcache_load=%0d total=%0d penalty_i=%0d penalty_d=%0d",
                icache_tmt, dcache_tmt, total_tmt,
                ICACHE_MISS_PENALTY, DCACHE_MISS_PENALTY);
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            printed <= 1'b0;
            ibus_req_wait_cycles <= 64'd0;
            ibus_resp_wait_cycles <= 64'd0;
            dbus_req_wait_cycles <= 64'd0;
            dbus_resp_wait_cycles <= 64'd0;
        end else begin
            if (ibus_req_valid && !ibus_req_ready) begin
                ibus_req_wait_cycles <= ibus_req_wait_cycles + 64'd1;
            end
            if (ibus_resp_ready && !ibus_resp_valid) begin
                ibus_resp_wait_cycles <= ibus_resp_wait_cycles + 64'd1;
            end
            if (dbus_req_valid && !dbus_req_ready) begin
                dbus_req_wait_cycles <= dbus_req_wait_cycles + 64'd1;
            end
            if (dbus_resp_ready && !dbus_resp_valid) begin
                dbus_resp_wait_cycles <= dbus_resp_wait_cycles + 64'd1;
            end

            if (!printed && commit_valid && (commit_is_ebreak || commit_illegal)) begin
                print_stats();
                printed <= 1'b1;
            end
        end
    end
endmodule
`endif
