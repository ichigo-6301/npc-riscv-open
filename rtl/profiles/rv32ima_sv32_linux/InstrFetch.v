// `timescale 1ns / 1ps
// module InstrFatch(
//     input clk,
//     input rst_n,
//     input [31:0] NextPC,
//     output reg [31:0] instr
// );
//     import "DPI-C" function int unsigned pmem_read (input int unsigned addr, input int len);

//     always @(posedge clk) begin
//         if (!rst_n) instr <= pmem_read(32'h80000000, 4);
//         else instr <= pmem_read(NextPC, 4);
//     end

// endmodule
