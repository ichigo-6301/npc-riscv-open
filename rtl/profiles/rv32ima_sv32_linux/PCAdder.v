`timescale 1ns / 1ps
// module PCAdder(
//     input [31:0] imm
//     input [31:0] rs1,
//     input [31:0] PC,
//     input [2:0] Branch,
//     input Zero,
//     input Less,
//     input PCAsrc,
//     input PCBsrc,
//     output [31:0] NextPC
// );
//     always @(*) begin
//         casez ({Branch, Zero, Less, PCAsrc, PCBsrc})
//             7'b000_?_?_0_0: NextPC = PC + 4; // default case
//             7'b001_?_?_1_0: NextPC = PC + imm;
//             7'b010_?_?_1_1: NextPC = rs1 + imm;
//             7'b100_0_?_0_0: NextPC = PC + 4;
//             7'b100_1_?_1_0: NextPC = PC + imm;
//             7'b101_0_?_1_0: NextPC = PC + imm;
//             7'b101_1_?_0_0: NextPC = PC + 4;
//             7'b110_?_0_0_0: NextPC = PC + 4;
//             7'b110_?_1_1_0: NextPC = PC + imm;
//             7'b111_?_0_1_0: NextPC = PC + imm;
//             7'b111_?_1_0_0: NextPC = PC + 4;
//             default: NextPC = PC + 4; // default case
            
//         endcase
//     end
// endmodule

module PCAdder(
    input [31:0] PCA,
    input [31:0] PCB,
    output [31:0] NextPC
);
    // EX branch encoding reference:
    // 3'b000: PC + 4
    // 3'b001: PC + imm
    // 3'b010: rs1 + imm for jalr; the caller clears low bits after this adder
    // 3'b011: 0 + scsr for trap/mret target
    //
    // PCAdder itself is intentionally branch-independent. EX instantiates
    // multiple pure adders in parallel, then the branch condition selects the
    // final PC. This avoids putting a Branch-controlled mux in front of the
    // carry chain on the FPGA redirect path.
    assign NextPC = PCA + PCB;
endmodule
