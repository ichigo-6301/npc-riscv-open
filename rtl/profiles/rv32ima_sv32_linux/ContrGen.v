`timescale 1ns / 1ps

// Core control decode (non-CSR path).
// CSR-specific decode is split to CsrContrGen for timing isolation.
module ContrGen(
    input rst_n,
    input [31:0] instr,
    output reg [2:0] ExtOP,
    output reg RegWr,
    output reg [2:0] Branch,
    output reg [1:0] DatatoReg,
    output reg [1:0] MemWr,
    output reg [2:0] MemOP,
    output reg [1:0] ALUAsrc,
    output reg [1:0] ALUBsrc,
    output reg [3:0] ALUctr,
`ifdef NPC_M_EXTENSION
    output reg MduEn,
    output reg [2:0] MduOp,
`endif
    output reg AtomicEn,
    output reg [3:0] AtomicOp,
    output reg Illegal
);
    `define ysyx_25050145_immI 3'b000
    `define ysyx_25050145_immU 3'b001
    `define ysyx_25050145_immS 3'b010
    `define ysyx_25050145_immB 3'b011
    `define ysyx_25050145_immJ 3'b100

    `define ysyx_25050145_Branch_default 3'b000
    `define ysyx_25050145_Branch_J 3'b001
    `define ysyx_25050145_Branch_J_r 3'b010
    `define ysyx_25050145_Branch_E 3'b011
    `define ysyx_25050145_Branch_B_eq 3'b100
    `define ysyx_25050145_Branch_B_ne 3'b101
    `define ysyx_25050145_Branch_B_lt 3'b110
    `define ysyx_25050145_Branch_B_ge 3'b111

    `define ysyx_25050145_DatatoReg_ALU 2'b00
    `define ysyx_25050145_DatatoReg_Mem 2'b01
    `define ysyx_25050145_DatatoReg_Csr 2'b10

    `define ysyx_25050145_MemOP_default 3'b000
    `define ysyx_25050145_MemOP_B_S 3'b000
    `define ysyx_25050145_MemOP_2B_S 3'b001
    `define ysyx_25050145_MemOP_4B 3'b010
    `define ysyx_25050145_MemOP_B_U 3'b100
    `define ysyx_25050145_MemOP_2B_U 3'b101

    `define ysyx_25050145_ALUctr_default 4'b0000
    `define ysyx_25050145_ALUctr_add_add 4'b0000
    `define ysyx_25050145_ALUctr_add_sub 4'b1000
    `define ysyx_25050145_ALUctr_shift_left 4'b0001
    `define ysyx_25050145_ALUctr_less_S 4'b0010
    `define ysyx_25050145_ALUctr_less_U 4'b1010
    `define ysyx_25050145_ALUctr_B 4'b0011
    `define ysyx_25050145_ALUctr_A 4'b1011
    `define ysyx_25050145_ALUctr_XOR 4'b0100
    `define ysyx_25050145_ALUctr_shift_logic_right 4'b0101
    `define ysyx_25050145_ALUctr_shift_arithmetic_right 4'b1101
    `define ysyx_25050145_ALUctr_OR 4'b0110
    `define ysyx_25050145_ALUctr_AND 4'b0111

    `define ysyx_25050145_ALUAsrc_rs1 2'b00
    `define ysyx_25050145_ALUAsrc_PC 2'b01
    `define ysyx_25050145_ALUAsrc_zimm 2'b10

    `define ysyx_25050145_ALUBsrc_rs2 2'b00
    `define ysyx_25050145_ALUBsrc_imm 2'b01
    `define ysyx_25050145_ALUBsrc_4 2'b10
    `define ysyx_25050145_ALUBsrc_scsr 2'b11

    always @(*) begin
        if (!rst_n) begin
            ExtOP = 3'b000;
            RegWr = 1'b0;
            Branch = 3'b000;
            DatatoReg = `ysyx_25050145_DatatoReg_ALU;
            MemWr = 2'b00;
            MemOP = 3'b000;
            ALUAsrc = 2'b00;
            ALUBsrc = 2'b00;
            ALUctr = 4'b0000;
`ifdef NPC_M_EXTENSION
            MduEn = 1'b0;
            MduOp = 3'b000;
`endif
            AtomicEn = 1'b0;
            AtomicOp = 4'd0;
            Illegal = 1'b0;
        end else begin
            ExtOP = `ysyx_25050145_immI;
            RegWr = 1'b0;
            Branch = `ysyx_25050145_Branch_default;
            DatatoReg = `ysyx_25050145_DatatoReg_ALU;
            MemWr = 2'b00;
            MemOP = `ysyx_25050145_MemOP_default;
            ALUAsrc = `ysyx_25050145_ALUAsrc_rs1;
            ALUBsrc = `ysyx_25050145_ALUBsrc_rs2;
            ALUctr = `ysyx_25050145_ALUctr_add_add;
`ifdef NPC_M_EXTENSION
            MduEn = 1'b0;
            MduOp = 3'b000;
`endif
            AtomicEn = 1'b0;
            AtomicOp = 4'd0;
            Illegal = 1'b0;

            casez (instr)
                32'b0000000_?????_?????_000_?????_01100_11: begin // add
                    RegWr = 1'b1;
                end
                32'b???????_?????_?????_000_?????_00100_11: begin // addi
                    RegWr = 1'b1;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                end
                32'b0000000_?????_?????_111_?????_01100_11: begin // and
                    RegWr = 1'b1;
                    ALUctr = `ysyx_25050145_ALUctr_AND;
                end
                32'b???????_?????_?????_111_?????_00100_11: begin // andi
                    RegWr = 1'b1;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                    ALUctr = `ysyx_25050145_ALUctr_AND;
                end
                // Atomic A-extension (word). First version:
                // - LR/SC and AMO* decoded here.
                // - LSU MEM stage performs the multi-cycle RMW sequence.
                // Decode priority note: keep lr/sc specific patterns before generic amo pattern class.
                32'b00010??_00000_?????_010_?????_01011_11: begin // lr.w
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Mem;
                    MemWr = 2'b01;
                    MemOP = `ysyx_25050145_MemOP_4B;
                    ALUctr = `ysyx_25050145_ALUctr_A; // address = rs1
                    AtomicEn = 1'b1;
                    AtomicOp = 4'd1;
                end
                32'b00011??_?????_?????_010_?????_01011_11: begin // sc.w
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Mem; // return success/fail code
                    MemWr = 2'b01;
                    MemOP = `ysyx_25050145_MemOP_4B;
                    ALUctr = `ysyx_25050145_ALUctr_A; // address = rs1
                    AtomicEn = 1'b1;
                    AtomicOp = 4'd2;
                end
                32'b00001??_?????_?????_010_?????_01011_11: begin // amoswap.w
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Mem;
                    MemWr = 2'b01;
                    MemOP = `ysyx_25050145_MemOP_4B;
                    ALUctr = `ysyx_25050145_ALUctr_A;
                    AtomicEn = 1'b1;
                    AtomicOp = 4'd3;
                end
                32'b00000??_?????_?????_010_?????_01011_11: begin // amoadd.w
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Mem;
                    MemWr = 2'b01;
                    MemOP = `ysyx_25050145_MemOP_4B;
                    ALUctr = `ysyx_25050145_ALUctr_A;
                    AtomicEn = 1'b1;
                    AtomicOp = 4'd4;
                end
                32'b00100??_?????_?????_010_?????_01011_11: begin // amoxor.w
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Mem;
                    MemWr = 2'b01;
                    MemOP = `ysyx_25050145_MemOP_4B;
                    ALUctr = `ysyx_25050145_ALUctr_A;
                    AtomicEn = 1'b1;
                    AtomicOp = 4'd5;
                end
                32'b01100??_?????_?????_010_?????_01011_11: begin // amoand.w
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Mem;
                    MemWr = 2'b01;
                    MemOP = `ysyx_25050145_MemOP_4B;
                    ALUctr = `ysyx_25050145_ALUctr_A;
                    AtomicEn = 1'b1;
                    AtomicOp = 4'd6;
                end
                32'b01000??_?????_?????_010_?????_01011_11: begin // amoor.w
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Mem;
                    MemWr = 2'b01;
                    MemOP = `ysyx_25050145_MemOP_4B;
                    ALUctr = `ysyx_25050145_ALUctr_A;
                    AtomicEn = 1'b1;
                    AtomicOp = 4'd7;
                end
                32'b10000??_?????_?????_010_?????_01011_11: begin // amomin.w
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Mem;
                    MemWr = 2'b01;
                    MemOP = `ysyx_25050145_MemOP_4B;
                    ALUctr = `ysyx_25050145_ALUctr_A;
                    AtomicEn = 1'b1;
                    AtomicOp = 4'd8;
                end
                32'b10100??_?????_?????_010_?????_01011_11: begin // amomax.w
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Mem;
                    MemWr = 2'b01;
                    MemOP = `ysyx_25050145_MemOP_4B;
                    ALUctr = `ysyx_25050145_ALUctr_A;
                    AtomicEn = 1'b1;
                    AtomicOp = 4'd9;
                end
                32'b11000??_?????_?????_010_?????_01011_11: begin // amominu.w
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Mem;
                    MemWr = 2'b01;
                    MemOP = `ysyx_25050145_MemOP_4B;
                    ALUctr = `ysyx_25050145_ALUctr_A;
                    AtomicEn = 1'b1;
                    AtomicOp = 4'd10;
                end
                32'b11100??_?????_?????_010_?????_01011_11: begin // amomaxu.w
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Mem;
                    MemWr = 2'b01;
                    MemOP = `ysyx_25050145_MemOP_4B;
                    ALUctr = `ysyx_25050145_ALUctr_A;
                    AtomicEn = 1'b1;
                    AtomicOp = 4'd11;
                end
                32'b???????_?????_?????_???_?????_00101_11: begin // auipc
                    ExtOP = `ysyx_25050145_immU;
                    RegWr = 1'b1;
                    ALUAsrc = `ysyx_25050145_ALUAsrc_PC;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                end
                32'b???????_?????_?????_000_?????_11000_11: begin // beq
                    ExtOP = `ysyx_25050145_immB;
                    Branch = `ysyx_25050145_Branch_B_eq;
                    ALUctr = `ysyx_25050145_ALUctr_less_U;
                end
                32'b???????_?????_?????_101_?????_11000_11: begin // bge
                    ExtOP = `ysyx_25050145_immB;
                    Branch = `ysyx_25050145_Branch_B_ge;
                    ALUctr = `ysyx_25050145_ALUctr_less_S;
                end
                32'b???????_?????_?????_111_?????_11000_11: begin // bgeu
                    ExtOP = `ysyx_25050145_immB;
                    Branch = `ysyx_25050145_Branch_B_ge;
                    ALUctr = `ysyx_25050145_ALUctr_less_U;
                end
                32'b???????_?????_?????_100_?????_11000_11: begin // blt
                    ExtOP = `ysyx_25050145_immB;
                    Branch = `ysyx_25050145_Branch_B_lt;
                    ALUctr = `ysyx_25050145_ALUctr_less_S;
                end
                32'b???????_?????_?????_110_?????_11000_11: begin // bltu
                    ExtOP = `ysyx_25050145_immB;
                    Branch = `ysyx_25050145_Branch_B_lt;
                    ALUctr = `ysyx_25050145_ALUctr_less_U;
                end
                32'b???????_?????_?????_001_?????_11000_11: begin // bne
                    ExtOP = `ysyx_25050145_immB;
                    Branch = `ysyx_25050145_Branch_B_ne;
                    ALUctr = `ysyx_25050145_ALUctr_less_U;
                end
                32'b???????_?????_?????_010_?????_11100_11: begin // csrrs
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Csr;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_scsr;
                    ALUctr = `ysyx_25050145_ALUctr_OR;
                end
                32'b???????_?????_?????_011_?????_11100_11: begin // csrrc
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Csr;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_scsr;
                    ALUctr = `ysyx_25050145_ALUctr_AND;
                end
                32'b???????_?????_?????_101_?????_11100_11: begin // csrrwi/csrwi
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Csr;
                    ALUAsrc = `ysyx_25050145_ALUAsrc_zimm;
                    ALUctr = `ysyx_25050145_ALUctr_A;
                end
                32'b???????_?????_?????_110_?????_11100_11: begin // csrrsi/csrsi
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Csr;
                    ALUAsrc = `ysyx_25050145_ALUAsrc_zimm;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_scsr;
                    ALUctr = `ysyx_25050145_ALUctr_OR;
                end
                32'b???????_?????_?????_111_?????_11100_11: begin // csrrci/csrci
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Csr;
                    ALUAsrc = `ysyx_25050145_ALUAsrc_zimm;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_scsr;
                    ALUctr = `ysyx_25050145_ALUctr_AND;
                end
                32'b???????_?????_?????_001_?????_11100_11: begin // csrrw
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Csr;
                    ALUAsrc = `ysyx_25050145_ALUAsrc_rs1;
                    ALUctr = `ysyx_25050145_ALUctr_A;
                end
                32'b0000000_00001_00000_000_00000_11100_11: begin // ebreak
                    ALUAsrc = `ysyx_25050145_ALUAsrc_PC;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_4;
                end
                32'b0000000_00000_00000_000_00000_11100_11: begin // ecall
                    // Trap entry is handled at commit by TrapCtrl.
                end
                32'b????_????_????_????_000_00000_00011_11: begin // fence / pause (Zifencei/Zihintpause)
                    // Current NPC policy keeps fence as nop (no store buffer / no OoO memory reordering yet).
                    // Keep default controls: no reg write, no mem write, no branch.
                end
                32'b0000000_00000_00000_001_00000_00011_11: begin // fence.i
                    // Decode-side still keeps default controls.
                    // Cache/pipeline maintenance behavior (drain dirty DCache + invalidate ICache + restart fetch)
                    // is expected to be handled by dedicated commit-side control logic.
                end
                32'b???????_?????_?????_???_?????_11011_11: begin // jal
                    ExtOP = `ysyx_25050145_immJ;
                    RegWr = 1'b1;
                    Branch = `ysyx_25050145_Branch_J;
                    ALUAsrc = `ysyx_25050145_ALUAsrc_PC;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_4;
                end
                32'b???????_?????_?????_000_?????_11001_11: begin // jalr
                    RegWr = 1'b1;
                    Branch = `ysyx_25050145_Branch_J_r;
                    ALUAsrc = `ysyx_25050145_ALUAsrc_PC;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_4;
                end
                32'b???????_?????_?????_000_?????_00000_11: begin // lb
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Mem;
                    MemWr = 2'b01;
                    MemOP = `ysyx_25050145_MemOP_B_S;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                end
                32'b???????_?????_?????_100_?????_00000_11: begin // lbu
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Mem;
                    MemWr = 2'b01;
                    MemOP = `ysyx_25050145_MemOP_B_U;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                end
                32'b???????_?????_?????_001_?????_00000_11: begin // lh
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Mem;
                    MemWr = 2'b01;
                    MemOP = `ysyx_25050145_MemOP_2B_S;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                end
                32'b???????_?????_?????_101_?????_00000_11: begin // lhu
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Mem;
                    MemWr = 2'b01;
                    MemOP = `ysyx_25050145_MemOP_2B_U;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                end
                32'b???????_?????_?????_???_?????_01101_11: begin // lui
                    ExtOP = `ysyx_25050145_immU;
                    RegWr = 1'b1;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                    ALUctr = `ysyx_25050145_ALUctr_B;
                end
                32'b???????_?????_?????_010_?????_00000_11: begin // lw
                    RegWr = 1'b1;
                    DatatoReg = `ysyx_25050145_DatatoReg_Mem;
                    MemWr = 2'b01;
                    MemOP = `ysyx_25050145_MemOP_4B;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                end
                32'b0011000_00010_00000_000_00000_11100_11: begin // mret
                    // Trap return is handled at commit by TrapCtrl.
                end
                32'b0001000_00010_00000_000_00000_11100_11: begin // sret
                    // Trap return is handled at commit by TrapCtrl.
                end
                32'b0001000_00101_00000_000_00000_11100_11: begin // wfi
                    // Treat WFI as a legal hint/nop; interrupt delivery is handled at commit.
                end
                32'b0001001_?????_?????_000_00000_11100_11: begin // sfence.vma
                    // Legal privilege/system op; TrapCtrl checks U-mode and TVM cases.
                end
                32'b0000000_?????_?????_110_?????_01100_11: begin // or
                    RegWr = 1'b1;
                    ALUctr = `ysyx_25050145_ALUctr_OR;
                end
                32'b???????_?????_?????_110_?????_00100_11: begin // ori
                    RegWr = 1'b1;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                    ALUctr = `ysyx_25050145_ALUctr_OR;
                end
                32'b???????_?????_?????_000_?????_01000_11: begin // sb
                    ExtOP = `ysyx_25050145_immS;
                    MemWr = 2'b11;
                    MemOP = `ysyx_25050145_MemOP_B_U;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                end
                32'b???????_?????_?????_001_?????_01000_11: begin // sh
                    ExtOP = `ysyx_25050145_immS;
                    MemWr = 2'b11;
                    MemOP = `ysyx_25050145_MemOP_2B_U;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                end
                32'b0000000_?????_?????_001_?????_01100_11: begin // sll
                    RegWr = 1'b1;
                    ALUctr = `ysyx_25050145_ALUctr_shift_left;
                end
                32'b0000000_?????_?????_001_?????_00100_11: begin // slli
                    RegWr = 1'b1;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                    ALUctr = `ysyx_25050145_ALUctr_shift_left;
                end
                32'b0000000_?????_?????_010_?????_01100_11: begin // slt
                    RegWr = 1'b1;
                    ALUctr = `ysyx_25050145_ALUctr_less_S;
                end
                32'b0000000_?????_?????_011_?????_01100_11: begin // sltu
                    RegWr = 1'b1;
                    ALUctr = `ysyx_25050145_ALUctr_less_U;
                end
                32'b???????_?????_?????_010_?????_00100_11: begin // slti
                    RegWr = 1'b1;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                    ALUctr = `ysyx_25050145_ALUctr_less_S;
                end
                32'b???????_?????_?????_011_?????_00100_11: begin // sltiu
                    RegWr = 1'b1;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                    ALUctr = `ysyx_25050145_ALUctr_less_U;
                end
                32'b0100000_?????_?????_000_?????_01100_11: begin // sub
                    RegWr = 1'b1;
                    ALUctr = `ysyx_25050145_ALUctr_add_sub;
                end
                32'b0100000_?????_?????_101_?????_01100_11: begin // sra
                    RegWr = 1'b1;
                    ALUctr = `ysyx_25050145_ALUctr_shift_arithmetic_right;
                end
                32'b0100000_?????_?????_101_?????_00100_11: begin // srai
                    RegWr = 1'b1;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                    ALUctr = `ysyx_25050145_ALUctr_shift_arithmetic_right;
                end
                32'b0000000_?????_?????_101_?????_01100_11: begin // srl
                    RegWr = 1'b1;
                    ALUctr = `ysyx_25050145_ALUctr_shift_logic_right;
                end
                32'b0000000_?????_?????_101_?????_00100_11: begin // srli
                    RegWr = 1'b1;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                    ALUctr = `ysyx_25050145_ALUctr_shift_logic_right;
                end
                32'b???????_?????_?????_010_?????_01000_11: begin // sw
                    ExtOP = `ysyx_25050145_immS;
                    MemWr = 2'b11;
                    MemOP = `ysyx_25050145_MemOP_4B;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                end
                32'b0000000_?????_?????_100_?????_01100_11: begin // xor
                    RegWr = 1'b1;
                    ALUctr = `ysyx_25050145_ALUctr_XOR;
                end
                32'b???????_?????_?????_100_?????_00100_11: begin // xori
                    RegWr = 1'b1;
                    ALUBsrc = `ysyx_25050145_ALUBsrc_imm;
                    ALUctr = `ysyx_25050145_ALUctr_XOR;
                end
`ifdef NPC_M_EXTENSION
                32'b0000001_?????_?????_000_?????_01100_11: begin // mul
                    RegWr = 1'b1;
                    MduEn = 1'b1;
                    MduOp = 3'd0;
                end
                32'b0000001_?????_?????_001_?????_01100_11: begin // mulh
                    RegWr = 1'b1;
                    MduEn = 1'b1;
                    MduOp = 3'd1;
                end
                32'b0000001_?????_?????_010_?????_01100_11: begin // mulhsu
                    RegWr = 1'b1;
                    MduEn = 1'b1;
                    MduOp = 3'd2;
                end
                32'b0000001_?????_?????_011_?????_01100_11: begin // mulhu
                    RegWr = 1'b1;
                    MduEn = 1'b1;
                    MduOp = 3'd3;
                end
                32'b0000001_?????_?????_100_?????_01100_11: begin // div
                    RegWr = 1'b1;
                    MduEn = 1'b1;
                    MduOp = 3'd4;
                end
                32'b0000001_?????_?????_101_?????_01100_11: begin // divu
                    RegWr = 1'b1;
                    MduEn = 1'b1;
                    MduOp = 3'd5;
                end
                32'b0000001_?????_?????_110_?????_01100_11: begin // rem
                    RegWr = 1'b1;
                    MduEn = 1'b1;
                    MduOp = 3'd6;
                end
                32'b0000001_?????_?????_111_?????_01100_11: begin // remu
                    RegWr = 1'b1;
                    MduEn = 1'b1;
                    MduOp = 3'd7;
                end
`endif
                default: begin
                    Illegal = 1'b1;
                end
            endcase
        end
    end
endmodule
