// `timescale 1ns / 1ps

// module DataMem(
//     input clk,
//     input rst_n,
//     input [31:0] Addr,
//     input [2:0] MemOp,
//     input [31:0] Datain,
//     input [1:0] WrEn,
//     output reg [31:0] rdata
// );  
//     import "DPI-C" function int unsigned pmem_read (input int unsigned addr, input int len);
//     import "DPI-C" function void pmem_write (input int unsigned addr, input int len, input int unsigned data);

//     reg [31:0] rdata_temp;
//     // wire [31:0] rdata_temp;
    
//     // wire [31:0] rdata_case [5];
//     wire [31:0] rdata_case0;
//     wire [31:0] rdata_case1;
//     wire [31:0] rdata_case4;
//     wire [31:0] rdata_case5;
//     assign rdata_case0 = {{24{rdata_temp[7]}}, rdata_temp[7:0]};
//     assign rdata_case1 = {{16{rdata_temp[15]}}, rdata_temp[15:0]};
//     assign rdata_case4 = {24'b0, rdata_temp[7:0]};
//     assign rdata_case5 = {16'b0, rdata_temp[15:0]};
//     MuxKeyWithDefault #(5, 3, 32) i1 (rdata, MemOp, 32'b0, {
//         3'b000, rdata_case0, // Byte read with sign extension
//         3'b001, rdata_case1, // Half-word read with sign extension
//         3'b010, rdata_temp, // Word read
//         3'b100, rdata_case4, // Byte read with zero extension
//         3'b101, rdata_case5 // Half-word read with zero extension
//     });
//     wire [31:0] wdata_temp;
//     wire [31:0] wdata_case0;
//     wire [31:0] wdata_case1;
//     wire [31:0] wdata_case4;
//     wire [31:0] wdata_case5;
//     assign wdata_case0 = {{24{Datain[7]}}, Datain[7:0]};
//     assign wdata_case1 = {{16{Datain[15]}}, Datain[15:0]};
//     assign wdata_case4 = {24'b0, Datain[7:0]};
//     assign wdata_case5 = {16'b0, Datain[15:0]};
//     MuxKeyWithDefault #(5, 3, 32) i2 (wdata_temp, MemOp, 32'b0, {
//         3'b000, wdata_case0, // Byte read with sign extension
//         3'b001, wdata_case1, // Half-word read with sign extension
//         3'b010, Datain, // Word read
//         3'b100, wdata_case4, // Byte read with zero extension
//         3'b101, wdata_case5 // Half-word read with zero extension
//     });
//     wire [2:0] size;
//     MuxKeyWithDefault #(5, 3, 3) i3 (size, MemOp, 3'b000, {
//         3'b000, 3'b001, // Byte
//         3'b001, 3'b010, // Half-word
//         3'b010, 3'b100, // Word
//         3'b100, 3'b001, // Byte with zero extension
//         3'b101, 3'b010 // Half-word with zero extension
//     });
//     // reg [66:0] match [5];
//     // assign match[0] = {3'b001, {24{Datain[7]}}, Datain[7:0], {24{rdata_temp[7]}}, rdata_temp[7:0]};
//     // assign match[1] = {3'b010, {16{Datain[15]}}, Datain[15:0], {16{rdata_temp[15]}}, rdata_temp[15:0]};
//     // assign match[2] = {3'b100, Datain, rdata_temp};
//     // assign match[3] = {3'b001, 24'b0, Datain[7:0], 24'b0, rdata_temp[7:0]};
//     // assign match[4] = {3'b010, 16'b0, Datain[15:0], 16'b0, rdata_temp[15:0]};
//     // MuxKeyWithDefault #(5, 3, 67) i1 ({size, wdata_temp, rdata}, MemOp, 67'b0, {
//     //     3'b000, match[0], // Byte read with sign extension
//     //     3'b001, match[1], // Half-word read with sign extension
//     //     3'b010, match[2], // Word read
//     //     3'b100, match[3], // Byte read with zero extension
//     //     3'b101, match[4] // Half-word read with zero extension
//     // });

//     // wire [31:0] rdata_temp;
//     // assign rdata_temp = pmem_read(Addr, 4);

//     // reg [31:0] wdata_temp;
//     // // reg [2:0] size;

//     // always @(*) begin
//     //     case (MemOp)
//     //         3'b000: rdata = {{24{rdata_temp[7]}}, rdata_temp[7:0]};        // Byte with sign extension
//     //         3'b001: rdata = {{16{rdata_temp[15]}}, rdata_temp[15:0]};      // Half-word with sign extension
//     //         3'b010: rdata = rdata_temp;                                    // Word
//     //         3'b100: rdata = {24'b0, rdata_temp[7:0]};                      // Byte with zero extension
//     //         3'b101: rdata = {16'b0, rdata_temp[15:0]};                     // Half-word with zero extension
//     //         default: rdata = 32'b0;
//     //     endcase
//     // end

//     // always @(*) begin
//     //     case (MemOp)
//     //         3'b000: wdata_temp = {{24{Datain[7]}}, Datain[7:0]};           // Byte with sign extension
//     //         3'b001: wdata_temp = {{16{Datain[15]}}, Datain[15:0]};         // Half-word with sign extension
//     //         3'b010: wdata_temp = Datain;                                   // Word
//     //         3'b100: wdata_temp = {24'b0, Datain[7:0]};                     // Byte with zero extension
//     //         3'b101: wdata_temp = {16'b0, Datain[15:0]};                    // Half-word with zero extension
//     //         default: wdata_temp = 32'b0;
//     //     endcase
//     // end

//     // always @(*) begin
//     //     case (MemOp)
//     //         3'b000, 3'b100: size = 3'b001; // Byte
//     //         3'b001, 3'b101: size = 3'b010; // Half-word
//     //         3'b010:         size = 3'b100; // Word
//     //         default:        size = 3'b000;
//     //     endcase
//     // end

//     always @(posedge clk) begin
//         // if (!rst_n) begin
//         //     rdata_temp <= 32'b0;
//         // end else 
//         if(WrEn[1]) begin
//             if (WrEn[0]) pmem_write(Addr, {29'b0, size}, wdata_temp);
//             // else begin
//             //     rdata_temp <= pmem_read(Addr, 4);
//             // end
//         end
//     end

//     always @(*) begin
//         if (!rst_n) begin
//             rdata_temp = 32'b0;
//         end else if(!WrEn[1]) begin
//             rdata_temp = pmem_read(Addr, 4);
//         end else begin
//             rdata_temp = 32'b0;
//         end
//     end

// endmodule

