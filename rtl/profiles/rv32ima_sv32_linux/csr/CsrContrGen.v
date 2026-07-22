`timescale 1ns / 1ps

// CSR-only decode path, split from core control decode for timing.
module CsrContrGen(
    input rst_n,
    input [31:0] instr,
    output uses_csr,
    output reg [11:0] csr_raddr,
    output reg [11:0] csr_waddr1,
    output reg [11:0] csr_waddr2,
    output reg [1:0] CsrWdatasrc1,
    output reg CsrWdatasrc2,
    output reg [1:0] csr_wen
);
    `define ysyx_25050145_CSRWdata1_src1 2'b00
    `define ysyx_25050145_CSRWdata1_zimm 2'b01
    `define ysyx_25050145_CSRWdata1_ALU 2'b10
    `define ysyx_25050145_CSRWdata1_ecall 2'b11
    `define ysyx_25050145_CSRWdata2_PC 1'b0

    `define ysyx_25050145_CSR_wen_default 2'b00
    `define ysyx_25050145_CSR_wen_w1 2'b10
    `define ysyx_25050145_CSR_wen_w1_w2 2'b11

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [4:0] rs1 = instr[19:15];
    wire is_system = (opcode == 7'b1110011);
    wire is_csrrw = is_system && (funct3 == 3'b001);
    wire is_csrrs = is_system && (funct3 == 3'b010);
    wire is_csrrc = is_system && (funct3 == 3'b011);
    wire is_csrrwi = is_system && (funct3 == 3'b101);
    wire is_csrrsi = is_system && (funct3 == 3'b110);
    wire is_csrrci = is_system && (funct3 == 3'b111);

    // Fast decode path: no dependency on ContrGen outputs.
    // Keep this block focused on regular CSR instructions only.
    // Trap-like system ops (ecall/mret/sret/interrupt) are handled at commit by TrapCtrl.
    assign uses_csr = is_csrrw || is_csrrs || is_csrrc || is_csrrwi || is_csrrsi || is_csrrci;

    always @(*) begin
        if (!rst_n) begin
            csr_raddr = 12'b0;
            csr_waddr1 = 12'b0;
            csr_waddr2 = 12'b0;
            CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_src1;
            CsrWdatasrc2 = `ysyx_25050145_CSRWdata2_PC;
            csr_wen = `ysyx_25050145_CSR_wen_default;
        end else begin
            csr_raddr = instr[31:20];
            csr_waddr1 = instr[31:20];
            csr_waddr2 = instr[31:20];
            CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_src1;
            CsrWdatasrc2 = `ysyx_25050145_CSRWdata2_PC;
            csr_wen = `ysyx_25050145_CSR_wen_default;

            if (is_csrrs || is_csrrc) begin
                CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_ALU;
                // csrrs/csrrc with rs1=x0 degrade to pure CSR read.
                if (rs1 == 5'b00000) csr_wen = `ysyx_25050145_CSR_wen_default;
                else csr_wen = `ysyx_25050145_CSR_wen_w1;
            end else if (is_csrrsi || is_csrrci) begin
                CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_ALU;
                // csrrsi/csrrci with zimm=0 degrade to pure CSR read.
                if (rs1 == 5'b00000) csr_wen = `ysyx_25050145_CSR_wen_default;
                else csr_wen = `ysyx_25050145_CSR_wen_w1;
            end else if (is_csrrwi) begin
                CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_zimm;
                csr_wen = `ysyx_25050145_CSR_wen_w1;
            end else if (is_csrrw) begin
                CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_src1;
                csr_wen = `ysyx_25050145_CSR_wen_w1;
            end
        end
    end
endmodule
