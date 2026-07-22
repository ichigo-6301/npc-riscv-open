`timescale 1ns / 1ps
module BranchCond(
    input [2:0] Branch,
    input Zero,
    input Less,
    output reg [1:0] PCAsrc,
    output reg [1:0] PCBsrc
);
    // always @(*) begin
    //     casez ({Branch, Zero, Less, PCAsrc, PCBsrc})
    //         7'b000_?_?_0_0: NextPC = PC + 4; // default case
    //         7'b001_?_?_1_0: NextPC = PC + imm;
    //         7'b010_?_?_1_1: NextPC = rs1 + imm;
    //         7'b100_0_?_0_0: NextPC = PC + 4;
    //         7'b100_1_?_1_0: NextPC = PC + imm;
    //         7'b101_0_?_1_0: NextPC = PC + imm;
    //         7'b101_1_?_0_0: NextPC = PC + 4;
    //         7'b110_?_0_0_0: NextPC = PC + 4;
    //         7'b110_?_1_1_0: NextPC = PC + imm;
    //         7'b111_?_0_1_0: NextPC = PC + imm;
    //         7'b111_?_1_0_0: NextPC = PC + 4;
    //         default: NextPC = PC + 4; // default case
            
    //     endcase
    // end
    always @(*) begin
        casez ({Branch, Zero, Less})
            5'b000_?_?: begin //PC + 4
                PCAsrc = 2'b00;
                PCBsrc = 2'b00;
            end
            5'b001_?_?: begin //PC + imm
                PCAsrc = 2'b01;
                PCBsrc = 2'b00;
            end
            5'b010_?_?: begin //rs1 + imm
                PCAsrc = 2'b01;
                PCBsrc = 2'b01;
            end
            5'b011_?_?: begin // Exception handling, jump to mtvec or mepc address , mtvec|mepc + 0
                PCAsrc = 2'b10;
                PCBsrc = 2'b10;
            end
            5'b100_0_?: begin //PC + 4
                PCAsrc = 2'b00;
                PCBsrc = 2'b00;
            end
            5'b100_1_?: begin //PC + imm
                PCAsrc = 2'b01;
                PCBsrc = 2'b00;
            end
            5'b101_0_?: begin //PC + imm
                PCAsrc = 2'b01;
                PCBsrc = 2'b00;
            end
            5'b101_1_?: begin //PC + 4
                PCAsrc = 2'b00;
                PCBsrc = 2'b00;
            end
            5'b110_?_0: begin //PC + 4
                PCAsrc = 2'b00;
                PCBsrc = 2'b00;
            end
            5'b110_?_1: begin //PC + imm
                PCAsrc = 2'b01;
                PCBsrc = 2'b00;
            end
            5'b111_?_0: begin //PC + imm
                PCAsrc = 2'b01;
                PCBsrc = 2'b00;
            end
            5'b111_?_1: begin //PC + 4
                PCAsrc = 2'b00;
                PCBsrc = 2'b00;
            end
            default: begin // default case
                PCAsrc = 2'b00;
                PCBsrc = 2'b00;
            end
        endcase

    end
endmodule
