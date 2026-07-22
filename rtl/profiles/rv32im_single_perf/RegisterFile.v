`timescale 1ns / 1ps
module RegisterFile #(ADDR_WIDTH = 1, DATA_WIDTH = 1) (
  input clk,
  input rst_n,
  input [ADDR_WIDTH-1:0] raddr1,
  output [DATA_WIDTH-1:0] rdata1,
  input [ADDR_WIDTH-1:0] raddr2,
  output [DATA_WIDTH-1:0] rdata2,
  input [DATA_WIDTH-1:0] wdata,
  input [ADDR_WIDTH-1:0] waddr,
  input wen
);
  reg [DATA_WIDTH-1:0] rf [2**ADDR_WIDTH-1:0];
  // assign rf[0] = 0; // Register 0 is always 0 这行没用注释了
  assign rdata1 = rf[raddr1];
  assign rdata2 = rf[raddr2];
  always @(posedge clk) begin
    if (!rst_n) begin : reset_rf
      integer i;
        for (i = 0; i < 2**ADDR_WIDTH; i = i + 1) begin
            rf[i] <= {DATA_WIDTH{1'b0}};  // 复位为全0
        end
    end
    else if (wen && waddr != {ADDR_WIDTH{1'b0}}) rf[waddr] <= wdata; //禁止写入寄存器0
  end
endmodule
