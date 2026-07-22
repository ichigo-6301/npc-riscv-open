`timescale 1ns / 1ps
module ALU(
    input [31:0] A,
    input [31:0] B,
    input [3:0] ALUctr,
    output [31:0] ALUout,
    output Less,
    output Zero
);
    wire [2:0] ALUctr_out;
    wire A_L;
    wire L_R;
    wire U_S;
    wire Sub_Add;
    wire Carry;
    wire Overflow;
    wire Select_A_OR_B;

    wire [31:0] adder;
    wire [31:0] shift;
    wire [31:0] slt;
    wire [31:0] XOR;
    wire [31:0] OR;
    wire [31:0] AND;
    wire [31:0] B_selected;

    MuxKey #(2, 1, 1) i0 (Less, U_S, {
        1'b0, Overflow ^ adder[31],
        1'b1, Sub_Add ^ Carry
    });

    assign slt = {31'b0, Less};
    assign XOR = A ^ B;
    assign OR = A | B;
    assign AND = A & B;
    assign B_selected = Select_A_OR_B ? A : B;

    ALUControl ALUControl0(
        .ALUctr(ALUctr),
        .ALUctr_out(ALUctr_out),
        .A_L(A_L),
        .L_R(L_R),
        .U_S(U_S),
        .Sub_Add(Sub_Add),
        .Select_A_OR_B(Select_A_OR_B)
    );

    Adder adder0(
        .A1(A),
        .B1(B ^ {32{Sub_Add}}), // XOR with Sub/Add to perform subtraction
        .Cin(Sub_Add),
        .Carry(Carry),
        .Zero(Zero),
        .Overflow(Overflow),
        .Result(adder)
    );

    BarrelShifter barrelShifter0(
        .Din(A),
        .Shamt(B[4:0]),
        .SHIFTctr({L_R, A_L}),
        .shift(shift)
    );

    MuxKey #(8, 3, 32) i1 (ALUout, ALUctr_out, {
        3'b000, adder,
        3'b001, shift,
        3'b010, slt,
        3'b011, B_selected,
        3'b100, XOR,
        3'b101, shift,
        3'b110, OR,
        3'b111, AND
    });


endmodule


module Adder(
    input [31:0] A1,
    input [31:0] B1,
    input Cin,
    output Carry,
    output Zero,
    output Overflow,
    output [31:0] Result
);
    assign Result = A1 + B1 + {31'b0, Cin};
    assign Carry = (A1[31] & B1[31]) | ((A1[31] | B1[31]) & ~Result[31]);
    assign Overflow = (A1[31] & B1[31] & ~Result[31]) | (~A1[31] & ~B1[31] & Result[31]);
    assign Zero = (Result == 0);
endmodule

module BarrelShifter(
    input [31:0] Din,
    input [4:0] Shamt,
    input [1:0] SHIFTctr, //{L/R,A/L}
    output [31:0] shift
);
    // always @(*) begin
    //     case (SHIFTctr)
    //         2'b00: shift = Din >> Shamt; // Logical right shift
    //         2'b01: shift = $signed(Din) >>> Shamt; // Arithmetic right shift
    //         2'b10: shift = Din << Shamt; // Logical left shift
    //         // 2'b11: shift = $signed(Din) << Shamt; // Arithmetic left shift
    //         default: shift = 32'b0;
    //     endcase
    // end
    MuxKeyWithDefault #(4, 2, 32) i2 (shift, SHIFTctr, 32'b0, {
        2'b00, Din >> Shamt, // Logical right shift
        2'b01, $signed(Din) >>> Shamt, // Arithmetic right shift
        2'b10, Din << Shamt, // Logical left shift
        2'b11, $signed(Din) << Shamt // Arithmetic left shift
    });

endmodule

// import "DPI-C" function word_t pmem_read (input paddr_t addr, input int len);
// import "DPI-C" function void pmem_write (input paddr_t addr, input int len, input word_t data);
// word_t pmem_read(paddr_t addr, int len)
// void pmem_write(paddr_t addr, int len, word_t data)
module ALUControl(
    input [3:0] ALUctr,
    output [2:0] ALUctr_out,
    output reg A_L,
    output reg L_R,
    output reg U_S,
    output reg Sub_Add,
    output reg Select_A_OR_B
);
    assign ALUctr_out = ALUctr[2:0];
    always @(*) begin
        // $display("%d", pmem_read(0x80000000 + ALUctr, 4));
        casez (ALUctr)
            4'b0000: begin
                // Select ADDer and add
                A_L = 1'b0;
                L_R = 1'b0;
                U_S = 1'b0;
                Sub_Add = 1'b0;
                Select_A_OR_B = 1'b0;
            end
            4'b1000: begin
                // Select ADDer and sub
                A_L = 1'b0;
                L_R = 1'b0;
                U_S = 1'b0;
                Sub_Add = 1'b1;
                Select_A_OR_B = 1'b0;
            end
            4'b?001: begin
                // Select Barrel Shifter and left shift
                A_L = 1'b0;
                L_R = 1'b1;
                U_S = 1'b0;
                Sub_Add = 1'b0;
                Select_A_OR_B = 1'b0;
            end
            4'b0010: begin
                // Select Less than with signed
                A_L = 1'b0;
                L_R = 1'b1;
                U_S = 1'b0;
                Sub_Add = 1'b1;
                Select_A_OR_B = 1'b0;
            end
            4'b1010: begin
                // Select Less than with unsigned
                A_L = 1'b0;
                L_R = 1'b1;
                U_S = 1'b1;
                Sub_Add = 1'b1;
                Select_A_OR_B = 1'b0;
            end
            4'b0011: begin
                // Select B and output
                A_L = 1'b0;
                L_R = 1'b0;
                U_S = 1'b0;
                Sub_Add = 1'b0;
                Select_A_OR_B = 1'b0;
            end
            4'b1011: begin
                // Select A and output
                A_L = 1'b0;
                L_R = 1'b0;
                U_S = 1'b0;
                Sub_Add = 1'b0;
                Select_A_OR_B = 1'b1;
            end
            // 4'b1100: begin
            //     // Select XOR
            //     A_L = 1'b0;
            //     L_R = 1'b0;
            //     U_S = 1'b0;
            //     Sub_Add = 1'b0;
            //     Select_A_OR_B = 1'b0;
            // end
            4'b0101: begin
                // Select Barrel Shifter and logic right shift 
                A_L = 1'b0;
                L_R = 1'b0;
                U_S = 1'b1;
                Sub_Add = 1'b1;
                Select_A_OR_B = 1'b0;
            end
            4'b1101: begin
                // Select Barrel Shifter and  left shift
                A_L = 1'b1;
                L_R = 1'b0;
                U_S = 1'b1;
                Sub_Add = 1'b1;
                Select_A_OR_B = 1'b0;
            end
            // 4'b?110: begin
            //     // Select OR
            //     A_L = 1'b0;
            //     L_R = 1'b0;
            //     U_S = 1'b0;
            //     Sub_Add = 1'b0;
            //     Select_A_OR_B = 1'b0;
            // end
            // 4'b?111: begin
            //     // Select AND
            //     A_L = 1'b0;
            //     L_R = 1'b0;
            //     U_S = 1'b0;
            //     Sub_Add = 1'b0;
            //     Select_A_OR_B = 1'b0;
            // end
            // Add more cases for other ALU operations as needed
            default: begin
                // Default to AND
                A_L = 1'b0;
                L_R = 1'b0;
                U_S = 1'b0;
                Sub_Add = 1'b0;
                Select_A_OR_B = 1'b0;
            end
        endcase
    end
endmodule
