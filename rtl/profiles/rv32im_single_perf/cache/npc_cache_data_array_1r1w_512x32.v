`timescale 1ns / 1ps

(* blackbox *)
module npc_cache_data_array_1r1w_512x32 (
    input clk,
    input ren,
    input [8:0] raddr,
    output [31:0] rdata,
    input wen,
    input [8:0] waddr,
    input [31:0] wdata,
    input [3:0] wmask
);
endmodule
