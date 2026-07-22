`timescale 1ns / 1ps

// CSR-only decode path, split from core control decode for timing.
module CsrContrGen(
    input rst_n,
    input [31:0] instr,
    output uses_csr,
    output reg [1:0] CsrRsrc,
    output reg [2:0] Csr1src,
    output reg [2:0] Csr2src,
    output reg [1:0] CsrWdatasrc1,
    output reg CsrWdatasrc2,
    output reg [1:0] csr_wen
);
    `define ysyx_25050145_CsrRsrc_csr 2'b00
    `define ysyx_25050145_CsrRsrc_mtvec 2'b01
    `define ysyx_25050145_CsrRsrc_mepc 2'b10
    `define ysyx_25050145_CsrRsrc_sepc 2'b11

    `define ysyx_25050145_CSRsrc_csr 3'b000
    `define ysyx_25050145_CSRsrc_mstatus 3'b001
    `define ysyx_25050145_CSRsrc_mtvec 3'b010
    `define ysyx_25050145_CSRsrc_mepc 3'b011
    `define ysyx_25050145_CSRsrc_mcause 3'b100

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
    wire is_system = (opcode == 7'b1110011);
    wire is_ecall = (instr == 32'h00000073);
    wire is_mret = (instr == 32'h30200073);
    wire is_sret = (instr == 32'h10200073);
    wire is_csrrw = is_system && (funct3 == 3'b001);
    wire is_csrrs = is_system && (funct3 == 3'b010);
    wire is_csrrc = is_system && (funct3 == 3'b011);
    wire is_csrrwi = is_system && (funct3 == 3'b101);
    wire is_csrrsi = is_system && (funct3 == 3'b110);
    wire is_csrrci = is_system && (funct3 == 3'b111);

    // Fast decode path: no dependency on ContrGen outputs.
    assign uses_csr = is_csrrw || is_csrrs || is_csrrc ||
        is_csrrwi || is_csrrsi || is_csrrci || is_ecall || is_mret || is_sret;

    always @(*) begin
        if (!rst_n) begin
            CsrRsrc = `ysyx_25050145_CsrRsrc_csr;
            Csr1src = `ysyx_25050145_CSRsrc_csr;
            Csr2src = `ysyx_25050145_CSRsrc_csr;
            CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_src1;
            CsrWdatasrc2 = `ysyx_25050145_CSRWdata2_PC;
            csr_wen = `ysyx_25050145_CSR_wen_default;
        end else begin
            CsrRsrc = `ysyx_25050145_CsrRsrc_csr;
            Csr1src = `ysyx_25050145_CSRsrc_csr;
            Csr2src = `ysyx_25050145_CSRsrc_csr;
            CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_src1;
            CsrWdatasrc2 = `ysyx_25050145_CSRWdata2_PC;
            csr_wen = `ysyx_25050145_CSR_wen_default;

            if (is_csrrs) begin
                CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_ALU;
                csr_wen = `ysyx_25050145_CSR_wen_w1;
            end else if (is_csrrc) begin
                CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_ALU;
                csr_wen = `ysyx_25050145_CSR_wen_w1;
            end else if (is_csrrw) begin
                CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_src1;
                csr_wen = `ysyx_25050145_CSR_wen_w1;
            end else if (is_csrrwi) begin
                CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_zimm;
                csr_wen = `ysyx_25050145_CSR_wen_w1;
            end else if (is_csrrsi) begin
                CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_ALU;
                csr_wen = `ysyx_25050145_CSR_wen_w1;
            end else if (is_csrrci) begin
                CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_ALU;
                csr_wen = `ysyx_25050145_CSR_wen_w1;
            end else if (is_ecall) begin
                CsrRsrc = `ysyx_25050145_CsrRsrc_mtvec;
                Csr1src = `ysyx_25050145_CSRsrc_mcause;
                Csr2src = `ysyx_25050145_CSRsrc_mepc;
                CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_ecall;
                CsrWdatasrc2 = `ysyx_25050145_CSRWdata2_PC;
                csr_wen = `ysyx_25050145_CSR_wen_w1_w2;
            end else if (is_mret) begin
                CsrRsrc = `ysyx_25050145_CsrRsrc_mepc;
                Csr1src = `ysyx_25050145_CSRsrc_mstatus;
                CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_ecall;
                csr_wen = `ysyx_25050145_CSR_wen_w1;
            end else if (is_sret) begin
                CsrRsrc = `ysyx_25050145_CsrRsrc_sepc;
                Csr1src = `ysyx_25050145_CSRsrc_mstatus;
                CsrWdatasrc1 = `ysyx_25050145_CSRWdata1_ecall;
                csr_wen = `ysyx_25050145_CSR_wen_w1;
            end
        end
    end
endmodule
