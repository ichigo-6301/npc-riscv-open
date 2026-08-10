`timescale 1ns / 1ps

(* blackbox *)
module npc_dcache_data_1r1w_512x32_b8 (
    input  logic clk0,
    input  logic csb0,
    input  logic [3:0] wmask0,
    input  logic [8:0] addr0,
    input  logic [31:0] din0,
    input  logic clk1,
    input  logic csb1,
    input  logic [8:0] addr1,
    output logic [31:0] dout1
);
endmodule

(* blackbox *)
module npc_ooo_data_word_1r1w_1024x32_b8 (
    input  logic clk0,
    input  logic csb0,
    input  logic [3:0] wmask0,
    input  logic [9:0] addr0,
    input  logic [31:0] din0,
    input  logic clk1,
    input  logic csb1,
    input  logic [9:0] addr1,
    output logic [31:0] dout1
);
endmodule
