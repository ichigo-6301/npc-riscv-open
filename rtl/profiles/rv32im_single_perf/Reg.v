`timescale 1ns / 1ps
// 触发器模板
module Reg #(WIDTH = 1, RESET_VAL = 0) (
  input clk,
  input rst_n,
  input [WIDTH-1:0] din,
  output reg [WIDTH-1:0] dout,
  input wen
);
  always @(posedge clk) begin
    if (!rst_n) dout <= RESET_VAL;
    else if (wen) dout <= din;
  end
endmodule
