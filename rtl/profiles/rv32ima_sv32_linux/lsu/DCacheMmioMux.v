`timescale 1ns / 1ps

module DCacheMmioMux #(
    parameter [31:0] MTIME_BASE = 32'hA0020000,
    parameter [31:0] MTIMECMP_BASE = 32'hA0030000
) (
    input clk,
    input rst_n,

    input in_req_valid,
    output in_req_ready,
    input in_req_write,
    input [31:0] in_req_addr,
    input [31:0] in_req_wdata,
    input [3:0] in_req_wstrb,
    input [2:0] in_req_len,
    output in_resp_valid,
    input in_resp_ready,
    output [31:0] in_resp_rdata,

    output mem_req_valid,
    input mem_req_ready,
    output mem_req_write,
    output [31:0] mem_req_addr,
    output [31:0] mem_req_wdata,
    output [3:0] mem_req_wstrb,
    output [2:0] mem_req_len,
    input mem_resp_valid,
    output mem_resp_ready,
    input [31:0] mem_resp_rdata,

    output timer_req_valid,
    input timer_req_ready,
    output timer_req_write,
    output [31:0] timer_req_addr,
    output [31:0] timer_req_wdata,
    output [3:0] timer_req_wstrb,
    output [2:0] timer_req_len,
    input timer_resp_valid,
    output timer_resp_ready,
    input [31:0] timer_resp_rdata
);
    reg timer_active_r;

    wire timer_addr =
        ((in_req_addr >= MTIME_BASE) && (in_req_addr < MTIME_BASE + 32'd8)) ||
        ((in_req_addr >= MTIMECMP_BASE) && (in_req_addr < MTIMECMP_BASE + 32'd8));
    wire timer_path = timer_addr && (in_req_len != 3'd0);
    wire timer_req = in_req_valid && timer_path;
    wire mem_req = in_req_valid && !timer_path;
    wire timer_req_fire = timer_req && timer_req_ready && !timer_active_r;
    wire timer_resp_fire = timer_resp_valid && in_resp_ready;

    assign in_req_ready = timer_active_r ? 1'b0 :
                          (timer_path ? timer_req_ready : mem_req_ready);

    assign mem_req_valid = mem_req && !timer_active_r;
    assign mem_req_write = in_req_write;
    assign mem_req_addr = in_req_addr;
    assign mem_req_wdata = in_req_wdata;
    assign mem_req_wstrb = in_req_wstrb;
    assign mem_req_len = in_req_len;

    assign timer_req_valid = timer_req && !timer_active_r;
    assign timer_req_write = in_req_write;
    assign timer_req_addr = in_req_addr;
    assign timer_req_wdata = in_req_wdata;
    assign timer_req_wstrb = in_req_wstrb;
    assign timer_req_len = in_req_len;

    assign in_resp_valid = timer_active_r ? timer_resp_valid : mem_resp_valid;
    assign in_resp_rdata = timer_active_r ? timer_resp_rdata : mem_resp_rdata;
    assign mem_resp_ready = timer_active_r ? 1'b0 : in_resp_ready;
    assign timer_resp_ready = timer_active_r ? in_resp_ready : 1'b0;

    always @(posedge clk) begin
        if (!rst_n) begin
            timer_active_r <= 1'b0;
        end else begin
            if (timer_req_fire) begin
                timer_active_r <= 1'b1;
            end
            if (timer_resp_fire) begin
                timer_active_r <= 1'b0;
            end
        end
    end
endmodule
