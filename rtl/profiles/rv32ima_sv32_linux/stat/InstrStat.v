`timescale 1ns / 1ps

`ifdef NPC_USE_DPI
`ifdef NPC_INSTR_STAT
module InstrStat(
    input clk,
    input rst_n,
    input commit_valid,
    input [31:0] commit_instr,
    input commit_is_ebreak,
    input commit_illegal
);
    localparam [5:0] IDX_ADD    = 6'd0;
    localparam [5:0] IDX_ADDI   = 6'd1;
    localparam [5:0] IDX_AND    = 6'd2;
    localparam [5:0] IDX_ANDI   = 6'd3;
    localparam [5:0] IDX_AUIPC  = 6'd4;
    localparam [5:0] IDX_BEQ    = 6'd5;
    localparam [5:0] IDX_BGE    = 6'd6;
    localparam [5:0] IDX_BGEU   = 6'd7;
    localparam [5:0] IDX_BLT    = 6'd8;
    localparam [5:0] IDX_BLTU   = 6'd9;
    localparam [5:0] IDX_BNE    = 6'd10;
    localparam [5:0] IDX_CSRRS  = 6'd11;
    localparam [5:0] IDX_CSRRW  = 6'd12;
    localparam [5:0] IDX_EBREAK = 6'd13;
    localparam [5:0] IDX_ECALL  = 6'd14;
    localparam [5:0] IDX_JAL    = 6'd15;
    localparam [5:0] IDX_JALR   = 6'd16;
    localparam [5:0] IDX_LB     = 6'd17;
    localparam [5:0] IDX_LBU    = 6'd18;
    localparam [5:0] IDX_LH     = 6'd19;
    localparam [5:0] IDX_LHU    = 6'd20;
    localparam [5:0] IDX_LUI    = 6'd21;
    localparam [5:0] IDX_LW     = 6'd22;
    localparam [5:0] IDX_MRET   = 6'd23;
    localparam [5:0] IDX_OR     = 6'd24;
    localparam [5:0] IDX_ORI    = 6'd25;
    localparam [5:0] IDX_SB     = 6'd26;
    localparam [5:0] IDX_SH     = 6'd27;
    localparam [5:0] IDX_SLL    = 6'd28;
    localparam [5:0] IDX_SLLI   = 6'd29;
    localparam [5:0] IDX_SLT    = 6'd30;
    localparam [5:0] IDX_SLTU   = 6'd31;
    localparam [5:0] IDX_SLTI   = 6'd32;
    localparam [5:0] IDX_SLTIU  = 6'd33;
    localparam [5:0] IDX_SUB    = 6'd34;
    localparam [5:0] IDX_SRA    = 6'd35;
    localparam [5:0] IDX_SRAI   = 6'd36;
    localparam [5:0] IDX_SRL    = 6'd37;
    localparam [5:0] IDX_SRLI   = 6'd38;
    localparam [5:0] IDX_SW     = 6'd39;
    localparam [5:0] IDX_XOR    = 6'd40;
    localparam [5:0] IDX_XORI   = 6'd41;
    localparam [5:0] IDX_MUL    = 6'd42;
    localparam [5:0] IDX_MULH   = 6'd43;
    localparam [5:0] IDX_MULHSU = 6'd44;
    localparam [5:0] IDX_MULHU  = 6'd45;
    localparam [5:0] IDX_DIV    = 6'd46;
    localparam [5:0] IDX_DIVU   = 6'd47;
    localparam [5:0] IDX_REM    = 6'd48;
    localparam [5:0] IDX_REMU   = 6'd49;
    localparam [5:0] IDX_INV    = 6'd63;

`ifdef NPC_M_EXTENSION
    localparam integer INSTR_KIND_TOTAL = 50;
    localparam [63:0] INSTR_KIND_TOTAL_U64 = 64'd50;
`else
    localparam integer INSTR_KIND_TOTAL = 42;
    localparam [63:0] INSTR_KIND_TOTAL_U64 = 64'd42;
`endif

    reg [49:0] covered;
    reg [31:0] instr_count [0:49];
    reg [31:0] commit_count;
    reg [31:0] covered_count;
    reg printed;
    reg [63:0] cov_x100;
    integer i;
    integer tmp_count;
    reg [5:0] idx;

    function [5:0] instr_kind_idx;
        input [31:0] instr;
        reg [6:0] opcode;
        reg [2:0] funct3;
        reg [6:0] funct7;
        begin
            opcode = instr[6:0];
            funct3 = instr[14:12];
            funct7 = instr[31:25];
            instr_kind_idx = IDX_INV;
            case (opcode)
                7'b0110011: begin
                    if (funct7 == 7'b0000000) begin
                        case (funct3)
                            3'b000: instr_kind_idx = IDX_ADD;
                            3'b001: instr_kind_idx = IDX_SLL;
                            3'b010: instr_kind_idx = IDX_SLT;
                            3'b011: instr_kind_idx = IDX_SLTU;
                            3'b100: instr_kind_idx = IDX_XOR;
                            3'b101: instr_kind_idx = IDX_SRL;
                            3'b110: instr_kind_idx = IDX_OR;
                            3'b111: instr_kind_idx = IDX_AND;
                            default: instr_kind_idx = IDX_INV;
                        endcase
                    end else if (funct7 == 7'b0100000) begin
                        case (funct3)
                            3'b000: instr_kind_idx = IDX_SUB;
                            3'b101: instr_kind_idx = IDX_SRA;
                            default: instr_kind_idx = IDX_INV;
                        endcase
`ifdef NPC_M_EXTENSION
                    end else if (funct7 == 7'b0000001) begin
                        case (funct3)
                            3'b000: instr_kind_idx = IDX_MUL;
                            3'b001: instr_kind_idx = IDX_MULH;
                            3'b010: instr_kind_idx = IDX_MULHSU;
                            3'b011: instr_kind_idx = IDX_MULHU;
                            3'b100: instr_kind_idx = IDX_DIV;
                            3'b101: instr_kind_idx = IDX_DIVU;
                            3'b110: instr_kind_idx = IDX_REM;
                            3'b111: instr_kind_idx = IDX_REMU;
                            default: instr_kind_idx = IDX_INV;
                        endcase
`endif
                    end
                end
                7'b0010011: begin
                    case (funct3)
                        3'b000: instr_kind_idx = IDX_ADDI;
                        3'b001: if (funct7 == 7'b0000000) instr_kind_idx = IDX_SLLI;
                        3'b010: instr_kind_idx = IDX_SLTI;
                        3'b011: instr_kind_idx = IDX_SLTIU;
                        3'b100: instr_kind_idx = IDX_XORI;
                        3'b101: begin
                            if (funct7 == 7'b0000000) instr_kind_idx = IDX_SRLI;
                            else if (funct7 == 7'b0100000) instr_kind_idx = IDX_SRAI;
                        end
                        3'b110: instr_kind_idx = IDX_ORI;
                        3'b111: instr_kind_idx = IDX_ANDI;
                        default: instr_kind_idx = IDX_INV;
                    endcase
                end
                7'b0000011: begin
                    case (funct3)
                        3'b000: instr_kind_idx = IDX_LB;
                        3'b001: instr_kind_idx = IDX_LH;
                        3'b010: instr_kind_idx = IDX_LW;
                        3'b100: instr_kind_idx = IDX_LBU;
                        3'b101: instr_kind_idx = IDX_LHU;
                        default: instr_kind_idx = IDX_INV;
                    endcase
                end
                7'b0100011: begin
                    case (funct3)
                        3'b000: instr_kind_idx = IDX_SB;
                        3'b001: instr_kind_idx = IDX_SH;
                        3'b010: instr_kind_idx = IDX_SW;
                        default: instr_kind_idx = IDX_INV;
                    endcase
                end
                7'b1100011: begin
                    case (funct3)
                        3'b000: instr_kind_idx = IDX_BEQ;
                        3'b001: instr_kind_idx = IDX_BNE;
                        3'b100: instr_kind_idx = IDX_BLT;
                        3'b101: instr_kind_idx = IDX_BGE;
                        3'b110: instr_kind_idx = IDX_BLTU;
                        3'b111: instr_kind_idx = IDX_BGEU;
                        default: instr_kind_idx = IDX_INV;
                    endcase
                end
                7'b0110111: instr_kind_idx = IDX_LUI;
                7'b0010111: instr_kind_idx = IDX_AUIPC;
                7'b1101111: instr_kind_idx = IDX_JAL;
                7'b1100111: if (funct3 == 3'b000) instr_kind_idx = IDX_JALR;
                7'b1110011: begin
                    if (instr == 32'h00000073) instr_kind_idx = IDX_ECALL;
                    else if (instr == 32'h00100073) instr_kind_idx = IDX_EBREAK;
                    else if (instr == 32'h30200073) instr_kind_idx = IDX_MRET;
                    else if (funct3 == 3'b001) instr_kind_idx = IDX_CSRRW;
                    else if (funct3 == 3'b010) instr_kind_idx = IDX_CSRRS;
                end
                default: instr_kind_idx = IDX_INV;
            endcase
        end
    endfunction

    task print_stats;
        begin
            tmp_count = 0;
            for (i = 0; i < INSTR_KIND_TOTAL; i = i + 1) begin
                if (covered[i]) tmp_count = tmp_count + 1;
            end
            cov_x100 = (tmp_count * 64'd10000) / INSTR_KIND_TOTAL_U64;
            $display("[InstrStat] committed=%0d", commit_count);
            $display("[InstrStat] covered_kinds=%0d/%0d", tmp_count, INSTR_KIND_TOTAL);
            $display("[InstrStat] coverage=%0d.%02d%%", cov_x100 / 100, cov_x100 % 100);
            $display("[InstrStat] -------------------------------------------------");
            $display("[InstrStat] | idx | mnemonic | count      | covered |");
            $display("[InstrStat] -------------------------------------------------");
            for (i = 0; i < INSTR_KIND_TOTAL; i = i + 1) begin
                case (i[5:0])
                    IDX_ADD:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "add",    instr_count[i], covered[i]);
                    IDX_ADDI:   $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "addi",   instr_count[i], covered[i]);
                    IDX_AND:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "and",    instr_count[i], covered[i]);
                    IDX_ANDI:   $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "andi",   instr_count[i], covered[i]);
                    IDX_AUIPC:  $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "auipc",  instr_count[i], covered[i]);
                    IDX_BEQ:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "beq",    instr_count[i], covered[i]);
                    IDX_BGE:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "bge",    instr_count[i], covered[i]);
                    IDX_BGEU:   $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "bgeu",   instr_count[i], covered[i]);
                    IDX_BLT:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "blt",    instr_count[i], covered[i]);
                    IDX_BLTU:   $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "bltu",   instr_count[i], covered[i]);
                    IDX_BNE:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "bne",    instr_count[i], covered[i]);
                    IDX_CSRRS:  $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "csrrs",  instr_count[i], covered[i]);
                    IDX_CSRRW:  $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "csrrw",  instr_count[i], covered[i]);
                    IDX_EBREAK: $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "ebreak", instr_count[i], covered[i]);
                    IDX_ECALL:  $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "ecall",  instr_count[i], covered[i]);
                    IDX_JAL:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "jal",    instr_count[i], covered[i]);
                    IDX_JALR:   $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "jalr",   instr_count[i], covered[i]);
                    IDX_LB:     $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "lb",     instr_count[i], covered[i]);
                    IDX_LBU:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "lbu",    instr_count[i], covered[i]);
                    IDX_LH:     $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "lh",     instr_count[i], covered[i]);
                    IDX_LHU:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "lhu",    instr_count[i], covered[i]);
                    IDX_LUI:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "lui",    instr_count[i], covered[i]);
                    IDX_LW:     $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "lw",     instr_count[i], covered[i]);
                    IDX_MRET:   $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "mret",   instr_count[i], covered[i]);
                    IDX_OR:     $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "or",     instr_count[i], covered[i]);
                    IDX_ORI:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "ori",    instr_count[i], covered[i]);
                    IDX_SB:     $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "sb",     instr_count[i], covered[i]);
                    IDX_SH:     $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "sh",     instr_count[i], covered[i]);
                    IDX_SLL:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "sll",    instr_count[i], covered[i]);
                    IDX_SLLI:   $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "slli",   instr_count[i], covered[i]);
                    IDX_SLT:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "slt",    instr_count[i], covered[i]);
                    IDX_SLTU:   $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "sltu",   instr_count[i], covered[i]);
                    IDX_SLTI:   $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "slti",   instr_count[i], covered[i]);
                    IDX_SLTIU:  $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "sltiu",  instr_count[i], covered[i]);
                    IDX_SUB:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "sub",    instr_count[i], covered[i]);
                    IDX_SRA:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "sra",    instr_count[i], covered[i]);
                    IDX_SRAI:   $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "srai",   instr_count[i], covered[i]);
                    IDX_SRL:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "srl",    instr_count[i], covered[i]);
                    IDX_SRLI:   $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "srli",   instr_count[i], covered[i]);
                    IDX_SW:     $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "sw",     instr_count[i], covered[i]);
                    IDX_XOR:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "xor",    instr_count[i], covered[i]);
                    IDX_XORI:   $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "xori",   instr_count[i], covered[i]);
                    IDX_MUL:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "mul",    instr_count[i], covered[i]);
                    IDX_MULH:   $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "mulh",   instr_count[i], covered[i]);
                    IDX_MULHSU: $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "mulhsu", instr_count[i], covered[i]);
                    IDX_MULHU:  $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "mulhu",  instr_count[i], covered[i]);
                    IDX_DIV:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "div",    instr_count[i], covered[i]);
                    IDX_DIVU:   $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "divu",   instr_count[i], covered[i]);
                    IDX_REM:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "rem",    instr_count[i], covered[i]);
                    IDX_REMU:   $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "remu",   instr_count[i], covered[i]);
                    default:    $display("[InstrStat] | %3d | %-8s | %10d | %7d |", i, "unknown",instr_count[i], covered[i]);
                endcase
            end
            $display("[InstrStat] -------------------------------------------------");
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            covered <= 50'b0;
            for (i = 0; i < 50; i = i + 1) begin
                instr_count[i] <= 32'b0;
            end
            commit_count <= 32'b0;
            covered_count <= 32'b0;
            printed <= 1'b0;
        end else begin
            if (commit_valid) begin
                commit_count <= commit_count + 32'd1;
                idx = instr_kind_idx(commit_instr);
                if (idx != 6'd63) begin
                    instr_count[idx] <= instr_count[idx] + 32'd1;
                    if (!covered[idx]) begin
                        covered[idx] <= 1'b1;
                        covered_count <= covered_count + 32'd1;
                    end
                end
            end

            if (!printed && commit_valid && (commit_is_ebreak || commit_illegal)) begin
                print_stats();
                printed <= 1'b1;
            end
        end
    end
endmodule
`endif
`endif
