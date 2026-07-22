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
            print_percent("icache_miss_rate", icache_miss, icache_access);
            $display("[CacheStat] dcache access=%0d load=%0d store=%0d hit=%0d miss=%0d",
                dcache_access, dcache_load_access, dcache_store_access,
                dcache_hit, dcache_miss);
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
