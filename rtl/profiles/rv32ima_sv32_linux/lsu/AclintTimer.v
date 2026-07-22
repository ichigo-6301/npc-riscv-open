`timescale 1ns / 1ps

module AclintTimer #(
    parameter integer CLK_HZ = 100000000,
    parameter integer TIMEBASE_HZ = 1000000,
    parameter [31:0] MTIME_BASE = 32'hA0020000,
    parameter [31:0] MTIMECMP_BASE = 32'hA0030000
) (
    input clk,
    input rst_n,

    input req_valid,
    output req_ready,
    input req_write,
    input [31:0] req_addr,
    input [31:0] req_wdata,
    input [3:0] req_wstrb,
    input [2:0] req_len,

    output reg resp_valid,
    input resp_ready,
    output reg [31:0] resp_rdata,

    output [63:0] time_value,
    output [63:0] timecmp_value,
    output [31:0] step_accum_value,
    output mtip
);
    localparam integer RAW_DIVIDER = (TIMEBASE_HZ <= 0) ? 1 : (CLK_HZ / TIMEBASE_HZ);
    localparam integer MTIME_DIVIDER = (RAW_DIVIDER <= 0) ? 1 : RAW_DIVIDER;

    reg [63:0] mtime_r /* verilator public_flat */;
    reg [63:0] mtimecmp_r /* verilator public_flat */;
    reg [31:0] div_count_r /* verilator public_flat */;

    wire req_fire = req_valid && req_ready;
    wire resp_fire = resp_valid && resp_ready;
    wire aligned_word = (req_len == 3'd4) && (req_addr[1:0] == 2'b00);
    wire mtime_sel = (req_addr >= MTIME_BASE) && (req_addr < MTIME_BASE + 32'd8);
    wire mtimecmp_sel = (req_addr >= MTIMECMP_BASE) && (req_addr < MTIMECMP_BASE + 32'd8);
    wire high_word = req_addr[2];
    wire timer_tick = (div_count_r == (MTIME_DIVIDER - 1));

    function [31:0] apply_wstrb;
        input [31:0] old_val;
        input [31:0] new_val;
        input [3:0] strb;
        begin
            apply_wstrb = {
                strb[3] ? new_val[31:24] : old_val[31:24],
                strb[2] ? new_val[23:16] : old_val[23:16],
                strb[1] ? new_val[15:8]  : old_val[15:8],
                strb[0] ? new_val[7:0]   : old_val[7:0]
            };
        end
    endfunction

    assign req_ready = !resp_valid || resp_ready;
    assign time_value = mtime_r;
    assign timecmp_value = mtimecmp_r;
    assign step_accum_value = div_count_r;
    assign mtip = (mtime_r >= mtimecmp_r);

    always @(posedge clk) begin
        if (!rst_n) begin
            mtime_r <= 64'b0;
            mtimecmp_r <= 64'hffff_ffff_ffff_ffff;
            div_count_r <= 32'b0;
            resp_valid <= 1'b0;
            resp_rdata <= 32'b0;
        end else begin
            if (resp_fire) begin
                resp_valid <= 1'b0;
            end

            if (timer_tick) begin
                div_count_r <= 32'b0;
                mtime_r <= mtime_r + 64'd1;
            end else begin
                div_count_r <= div_count_r + 32'd1;
            end

            if (req_fire) begin
                resp_valid <= 1'b1;
                resp_rdata <= 32'b0;

                if (aligned_word && mtime_sel) begin
                    if (req_write) begin
                        if (high_word) begin
                            mtime_r[63:32] <= apply_wstrb(mtime_r[63:32], req_wdata, req_wstrb);
                        end else begin
                            mtime_r[31:0] <= apply_wstrb(mtime_r[31:0], req_wdata, req_wstrb);
                        end
                    end else begin
                        resp_rdata <= high_word ? mtime_r[63:32] : mtime_r[31:0];
                    end
                end else if (aligned_word && mtimecmp_sel) begin
                    if (req_write) begin
                        if (high_word) begin
                            mtimecmp_r[63:32] <= apply_wstrb(mtimecmp_r[63:32], req_wdata, req_wstrb);
                        end else begin
                            mtimecmp_r[31:0] <= apply_wstrb(mtimecmp_r[31:0], req_wdata, req_wstrb);
                        end
                    end else begin
                        resp_rdata <= high_word ? mtimecmp_r[63:32] : mtimecmp_r[31:0];
                    end
                end
            end
        end
    end
endmodule
