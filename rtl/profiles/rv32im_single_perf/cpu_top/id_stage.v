`timescale 1ns / 1ps
`include "include/bbus_core_defs.svh"

module id_stage (
    input clk,
    input rst_n,

    input flush,

    input fs_to_ds_valid,
    input [31:0] fs_pc,
    input [31:0] fs_instr,
    input fs_pred_taken,
    input [31:0] fs_pred_target,
    output ds_allowin,
    input es_allowin,
    output ds_to_es_valid,

    output [4:0] rf_raddr1,
    input [31:0] rf_rdata1,
    output [4:0] rf_raddr2,
    input [31:0] rf_rdata2,
    output [11:0] csr_raddr,
    input [31:0] csr_rdata,
    input [1:0] csr_priv,
    input [31:0] csr_mstatus_value,

    input es_valid,
    input es_reg_wen,
    input [4:0] es_rd,
    input [1:0] es_csr_wen,
    input [11:0] es_csr_waddr1,
    input [11:0] es_csr_waddr2,

    input ms_valid,
    input ms_reg_wen,
    input [4:0] ms_rd,
    input [1:0] ms_csr_wen,
    input [11:0] ms_csr_waddr1,
    input [11:0] ms_csr_waddr2,

    input hidden_mreq_valid,
    input hidden_mreq_reg_wen,
    input [4:0] hidden_mreq_rd,
    input [1:0] hidden_mreq_csr_wen,
    input [11:0] hidden_mreq_csr_waddr1,
    input [11:0] hidden_mreq_csr_waddr2,

    input ws_valid,
    input [4:0] ws_rd,
    input ws_reg_wen,
    input [1:0] ws_csr_wen,
    input [11:0] ws_csr_waddr1,
    input [11:0] ws_csr_waddr2,
    input es_result_bypassable,
    input ms_fwd_valid,
    input [31:0] ms_fwd_data,

    output [31:0] ds_pc,
    output [31:0] ds_instr,
    output [4:0] ds_rs1,
    output [4:0] ds_rs2,
    output [31:0] ds_src1,
    output [31:0] ds_src2,
    output ds_src1_from_prev_ex,
    output ds_src2_from_prev_ex,
    output ds_src1_from_prev_wb,
    output ds_src2_from_prev_wb,
    output ds_pred_taken,
    output [31:0] ds_pred_target,
    output [31:0] ds_imm,
    output [31:0] ds_zimm,
    output [31:0] ds_scsr,
    output [4:0] ds_rd,
    output ds_reg_wen,
    output [2:0] ds_branch,
    output [1:0] ds_datatoreg,
    output [1:0] ds_mem_wr,
    output [2:0] ds_mem_op,
    output [1:0] ds_alu_a_src,
    output [1:0] ds_alu_b_src,
    output [3:0] ds_alu_ctr,
    output [1:0] ds_csr_wen,
    output [11:0] ds_csr_waddr1,
    output [11:0] ds_csr_waddr2,
    output [1:0] ds_csr_wdata_src1,
    output ds_csr_wdata_src2,
    output ds_illegal,
    output ds_is_ebreak,
    output ds_stop_fetch,
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    output ds_stage_block,
    output ds_stage_block_reg_hazard,
    output ds_stage_block_csr_hazard,
`endif
`endif
`ifdef NPC_M_EXTENSION
    output ds_mdu_en,
    output [2:0] ds_mdu_op
`else
    output ds_mdu_en_dummy,
    output [2:0] ds_mdu_op_dummy
`endif
);
    reg ds_valid;
    reg [31:0] ds_pc_r;
    reg [31:0] ds_instr_r;
    reg ds_pred_taken_r;
    reg [31:0] ds_pred_target_r;

    wire [4:0] rs1 = ds_instr_r[19:15];
    wire [4:0] rs2 = ds_instr_r[24:20];
    wire [4:0] rd = ds_instr_r[11:7];
    wire [11:0] csr = ds_instr_r[31:20];
    wire [31:0] zimm = {27'b0, rs1};

    wire [2:0] ext_op;
    wire reg_wen;
    wire [2:0] branch;
    wire [1:0] datatoreg;
    wire [1:0] mem_wr;
    wire [2:0] mem_op;
    wire [1:0] alu_a_src;
    wire [1:0] alu_b_src;
    wire [3:0] alu_ctr;
    wire [1:0] csr_rsrc;
    wire uses_csr_fast;
    wire [2:0] csr1src;
    wire [2:0] csr2src;
    wire [1:0] csr_wdata_src1;
    wire csr_wdata_src2;
    wire [1:0] csr_wen;
    wire illegal_instr;
    wire [31:0] imm;
`ifdef NPC_M_EXTENSION
    wire mdu_en;
    wire [2:0] mdu_op;
`endif
    bbus_fu_e ds_fu_class;
    bbus_uop_t ds_uop_view;
    bbus_uop_t slot0_uop_view;
    bbus_uop_t slot1_uop_view;
    bbus_pair_decision_t pairing_decision;
    bbus_slot_meta_t slot0_meta_view;
    bbus_slot_meta_t slot1_meta_view;
    bbus_decode_bundle_t decode_bundle_view;

    wire ds_valid_eff = ds_valid && !flush;

    wire [6:0] opcode = ds_instr_r[6:0];
    wire [2:0] funct3 = ds_instr_r[14:12];
    wire is_system = (opcode == 7'b1110011);
    wire is_ecall = (ds_instr_r == 32'h00000073);
    wire is_ebreak = (ds_instr_r == 32'h00100073);
    wire is_mret = (ds_instr_r == 32'h30200073);
    wire is_sret = (ds_instr_r == 32'h10200073);
    wire is_wfi = (ds_instr_r == 32'h10500073);
    wire is_sfence_vma =
        (opcode == 7'b1110011) &&
        (funct3 == 3'b000) &&
        (rd == 5'b00000) &&
        (ds_instr_r[31:25] == 7'b0001001);
    wire is_csr_instr =
        is_system && !is_ecall && !is_ebreak && !is_mret && !is_sret &&
        !is_wfi && !is_sfence_vma;
    wire csr_uses_rs1 = is_csr_instr && !funct3[2];
    wire csr_instr_writes =
        is_csr_instr &&
        ((funct3 == 3'b001) ||
         (funct3 == 3'b101) ||
         (((funct3 == 3'b010) || (funct3 == 3'b011) ||
           (funct3 == 3'b110) || (funct3 == 3'b111)) && (rs1 != 5'b00000)));
    wire is_jalr = (opcode == 7'b1100111);
    wire is_jal = (opcode == 7'b1101111);
    wire is_cond_branch = (opcode == 7'b1100011);

    wire uses_rs1 = ds_valid_eff && (
        (opcode == 7'b0110011) ||
        (opcode == 7'b0010011) ||
        (opcode == 7'b0000011) ||
        (opcode == 7'b0100011) ||
        (opcode == 7'b1100011) ||
        (opcode == 7'b1100111) ||
        csr_uses_rs1
    );

    wire uses_rs2 = ds_valid_eff && (
        (opcode == 7'b0110011) ||
        (opcode == 7'b0100011) ||
        (opcode == 7'b1100011)
    );

    wire [11:0] csr_raddr_real =
        (csr_rsrc == 2'b00) ? csr :
        (csr_rsrc == 2'b01) ? 12'h305 :
        (csr_rsrc == 2'b10) ? 12'h341 :
        12'h141;

    wire [11:0] csr_waddr1_real =
        (csr1src == 3'b000) ? csr :
        (csr1src == 3'b001) ? 12'h300 :
        (csr1src == 3'b010) ? 12'h305 :
        (csr1src == 3'b011) ? 12'h341 :
        12'h342;

    wire [11:0] csr_waddr2_real =
        (csr2src == 3'b000) ? csr :
        (csr2src == 3'b001) ? 12'h300 :
        (csr2src == 3'b010) ? 12'h305 :
        (csr2src == 3'b011) ? 12'h341 :
        12'h342;

    wire rs1_match_es = uses_rs1 && es_valid && es_reg_wen && (es_rd != 5'b0) && (es_rd == rs1);
    wire rs1_match_ms = uses_rs1 && ms_valid && ms_reg_wen && (ms_rd != 5'b0) && (ms_rd == rs1);
    wire rs1_match_hidden_mreq = uses_rs1 && hidden_mreq_valid && hidden_mreq_reg_wen &&
        (hidden_mreq_rd != 5'b0) && (hidden_mreq_rd == rs1);
    wire rs1_match_ws = uses_rs1 && ws_valid && ws_reg_wen && (ws_rd != 5'b0) && (ws_rd == rs1);

    wire rs2_match_es = uses_rs2 && es_valid && es_reg_wen && (es_rd != 5'b0) && (es_rd == rs2);
    wire rs2_match_ms = uses_rs2 && ms_valid && ms_reg_wen && (ms_rd != 5'b0) && (ms_rd == rs2);
    wire rs2_match_hidden_mreq = uses_rs2 && hidden_mreq_valid && hidden_mreq_reg_wen &&
        (hidden_mreq_rd != 5'b0) && (hidden_mreq_rd == rs2);
    wire rs2_match_ws = uses_rs2 && ws_valid && ws_reg_wen && (ws_rd != 5'b0) && (ws_rd == rs2);

    // Keep redirect-class consumers on the original stall/hold path so this
    // timing cleanup does not change branch/jalr execution behavior.
    wire rs1_prev_ex_bypass = rs1_match_es && es_result_bypassable &&
        !is_jalr && !is_cond_branch;
    wire rs2_prev_ex_bypass = rs2_match_es && es_result_bypassable &&
        !is_cond_branch;

    wire rs1_need_stall =
        (rs1_match_es && !rs1_prev_ex_bypass) ||
        (!rs1_match_es && rs1_match_ms && !ms_fwd_valid) ||
        (!rs1_match_es && !rs1_match_ms && rs1_match_hidden_mreq);

    wire rs2_need_stall =
        (rs2_match_es && !rs2_prev_ex_bypass) ||
        (!rs2_match_es && rs2_match_ms && !ms_fwd_valid) ||
        (!rs2_match_es && !rs2_match_ms && rs2_match_hidden_mreq);

    wire rs1_from_ms = !rs1_match_es && rs1_match_ms && ms_fwd_valid;
    wire rs2_from_ms = !rs2_match_es && rs2_match_ms && ms_fwd_valid;
    wire rs1_prev_wb_bypass = !rs1_match_es && !rs1_match_ms && !rs1_match_hidden_mreq && rs1_match_ws;
    wire rs2_prev_wb_bypass = !rs2_match_es && !rs2_match_ms && !rs2_match_hidden_mreq && rs2_match_ws;

    wire reg_hazard = rs1_need_stall || rs2_need_stall;

    function [4:0] csr_addr_to_idx;
        input [11:0] csr_addr;
        begin
            case (csr_addr)
                12'h300: csr_addr_to_idx = 5'd0;
                12'h100: csr_addr_to_idx = 5'd0;
                12'h305: csr_addr_to_idx = 5'd1;
                12'h341: csr_addr_to_idx = 5'd2;
                12'h141: csr_addr_to_idx = 5'd16;
                12'h342: csr_addr_to_idx = 5'd3;
                12'h343: csr_addr_to_idx = 5'd4;
                12'h340: csr_addr_to_idx = 5'd5;
                12'h304: csr_addr_to_idx = 5'd6;
                12'h344: csr_addr_to_idx = 5'd7;
                12'h302: csr_addr_to_idx = 5'd8;
                12'h303: csr_addr_to_idx = 5'd9;
                12'h180: csr_addr_to_idx = 5'd10;
                12'h3a0: csr_addr_to_idx = 5'd11;
                12'h3b0: csr_addr_to_idx = 5'd12;
                12'h744: csr_addr_to_idx = 5'd13;
                12'h306: csr_addr_to_idx = 5'd14;
                12'h106: csr_addr_to_idx = 5'd15;
                default: csr_addr_to_idx = 5'd0;
            endcase
        end
    endfunction

    function csr_addr_is_writable;
        input [11:0] csr_addr;
        begin
            csr_addr_is_writable =
                (csr_addr == 12'h300) ||
                (csr_addr == 12'h100) ||
                (csr_addr == 12'h305) ||
                (csr_addr == 12'h341) ||
                (csr_addr == 12'h141) ||
                (csr_addr == 12'h342) ||
                (csr_addr == 12'h343) ||
                (csr_addr == 12'h340) ||
                (csr_addr == 12'h304) ||
                (csr_addr == 12'h344) ||
                (csr_addr == 12'h302) ||
                (csr_addr == 12'h303) ||
                (csr_addr == 12'h180) ||
                (csr_addr == 12'h3a0) ||
                (csr_addr == 12'h3b0) ||
                (csr_addr == 12'h744) ||
                (csr_addr == 12'h306) ||
                (csr_addr == 12'h106);
        end
    endfunction

    function csr_addr_is_write_ignored;
        input [11:0] csr_addr;
        begin
            csr_addr_is_write_ignored =
                (csr_addr == 12'h301) ||
                (csr_addr == 12'h320) ||
                (csr_addr == 12'hb00) ||
                (csr_addr == 12'hb80) ||
                (csr_addr == 12'hb02) ||
                (csr_addr == 12'hb82) ||
                (csr_addr == 12'h7a0) ||
                (csr_addr == 12'h7a1) ||
                (csr_addr == 12'h7a2) ||
                (csr_addr == 12'h7a3) ||
                (csr_addr == 12'h7a4) ||
                (csr_addr == 12'h7a5);
        end
    endfunction

    function csr_addr_is_readonly_supported;
        input [11:0] csr_addr;
        begin
            csr_addr_is_readonly_supported =
                (csr_addr == 12'h301) ||
                (csr_addr == 12'hf11) ||
                (csr_addr == 12'hf12) ||
                (csr_addr == 12'hf13) ||
                (csr_addr == 12'hf14) ||
                (csr_addr == 12'hc00) ||
                (csr_addr == 12'hc01) ||
                (csr_addr == 12'hc02) ||
                (csr_addr == 12'hc80) ||
                (csr_addr == 12'hc81) ||
                (csr_addr == 12'hc82);
        end
    endfunction

    function csr_addr_is_supported;
        input [11:0] csr_addr;
        begin
            csr_addr_is_supported =
                csr_addr_is_writable(csr_addr) ||
                csr_addr_is_write_ignored(csr_addr) ||
                csr_addr_is_readonly_supported(csr_addr);
        end
    endfunction

`ifdef NPC_RVTEST_TRAP_STUB
    wire rvtest_needs_mtvec_for_dynamic_trap =
        ds_valid_eff && (is_jal || is_jalr || is_cond_branch);
    wire rvtest_csr_access_supported =
        csr_addr_is_supported(csr) &&
        (!csr_instr_writes || csr_addr_is_writable(csr) || csr_addr_is_write_ignored(csr));
    wire rvtest_unsupported_csr = ds_valid_eff && is_csr_instr && !rvtest_csr_access_supported;
    wire rvtest_privileged_csr = ds_valid_eff && is_csr_instr &&
        csr_addr_is_supported(csr) && (csr_priv < csr[9:8]);
    wire rvtest_sfence_vma_illegal = ds_valid_eff && is_sfence_vma &&
        ((csr_priv == 2'b00) || ((csr_priv == 2'b01) && csr_mstatus_value[20]));
    wire rvtest_satp_tvm_illegal = ds_valid_eff && is_csr_instr &&
        (csr == 12'h180) && (csr_priv == 2'b01) && csr_mstatus_value[20];
    wire rvtest_sret_illegal = ds_valid_eff && is_sret &&
        ((csr_priv == 2'b00) || ((csr_priv == 2'b01) && csr_mstatus_value[22]));
    wire rvtest_trap_candidate = ds_valid_eff &&
        (illegal_instr || rvtest_unsupported_csr || rvtest_privileged_csr ||
         rvtest_sfence_vma_illegal || rvtest_satp_tvm_illegal ||
         rvtest_sret_illegal || is_ebreak);
    wire ds_illegal_eff = 1'b0;
`else
    wire rvtest_needs_mtvec_for_dynamic_trap = 1'b0;
    wire rvtest_trap_candidate = 1'b0;
    wire ds_illegal_eff = illegal_instr;
`endif

    wire [11:0] csr_raddr_use =
        (rvtest_trap_candidate || rvtest_needs_mtvec_for_dynamic_trap) ? 12'h305 :
        csr_raddr_real;
    wire uses_csr_for_hazard =
        uses_csr_fast || rvtest_trap_candidate || rvtest_needs_mtvec_for_dynamic_trap;
    wire [4:0] csr_ridx = csr_addr_to_idx(csr_raddr_use);
    wire csr_ridx_valid = csr_addr_is_writable(csr_raddr_use);

    wire [4:0] es_csr_widx1 = csr_addr_to_idx(es_csr_waddr1);
    wire [4:0] es_csr_widx2 = csr_addr_to_idx(es_csr_waddr2);
    wire es_csr_widx1_valid = csr_addr_is_writable(es_csr_waddr1);
    wire es_csr_widx2_valid = csr_addr_is_writable(es_csr_waddr2);

    wire [4:0] ms_csr_widx1 = csr_addr_to_idx(ms_csr_waddr1);
    wire [4:0] ms_csr_widx2 = csr_addr_to_idx(ms_csr_waddr2);
    wire ms_csr_widx1_valid = csr_addr_is_writable(ms_csr_waddr1);
    wire ms_csr_widx2_valid = csr_addr_is_writable(ms_csr_waddr2);

    wire [4:0] hidden_mreq_csr_widx1 = csr_addr_to_idx(hidden_mreq_csr_waddr1);
    wire [4:0] hidden_mreq_csr_widx2 = csr_addr_to_idx(hidden_mreq_csr_waddr2);
    wire hidden_mreq_csr_widx1_valid = csr_addr_is_writable(hidden_mreq_csr_waddr1);
    wire hidden_mreq_csr_widx2_valid = csr_addr_is_writable(hidden_mreq_csr_waddr2);

    wire [4:0] ws_csr_widx1 = csr_addr_to_idx(ws_csr_waddr1);
    wire [4:0] ws_csr_widx2 = csr_addr_to_idx(ws_csr_waddr2);
    wire ws_csr_widx1_valid = csr_addr_is_writable(ws_csr_waddr1);
    wire ws_csr_widx2_valid = csr_addr_is_writable(ws_csr_waddr2);

    wire csr_hazard =
        (ds_valid_eff && uses_csr_for_hazard && csr_ridx_valid && es_valid && es_csr_wen[1] &&
            ((es_csr_widx1_valid && (es_csr_widx1 == csr_ridx)) ||
             (es_csr_wen[0] && es_csr_widx2_valid && (es_csr_widx2 == csr_ridx)))) ||
        (ds_valid_eff && uses_csr_for_hazard && csr_ridx_valid && ms_valid && ms_csr_wen[1] &&
            ((ms_csr_widx1_valid && (ms_csr_widx1 == csr_ridx)) ||
             (ms_csr_wen[0] && ms_csr_widx2_valid && (ms_csr_widx2 == csr_ridx)))) ||
        (ds_valid_eff && uses_csr_for_hazard && csr_ridx_valid && hidden_mreq_valid && hidden_mreq_csr_wen[1] &&
            ((hidden_mreq_csr_widx1_valid && (hidden_mreq_csr_widx1 == csr_ridx)) ||
             (hidden_mreq_csr_wen[0] && hidden_mreq_csr_widx2_valid &&
                (hidden_mreq_csr_widx2 == csr_ridx)))) ||
        (ds_valid_eff && uses_csr_for_hazard && csr_ridx_valid && ws_valid && ws_csr_wen[1] &&
            ((ws_csr_widx1_valid && (ws_csr_widx1 == csr_ridx)) ||
             (ws_csr_wen[0] && ws_csr_widx2_valid && (ws_csr_widx2 == csr_ridx))));

    wire ds_ready_go = !ds_valid_eff || !(reg_hazard || csr_hazard);

    assign ds_fu_class =
`ifdef NPC_M_EXTENSION
        mdu_en ? BBUS_FU_MDU :
`endif
        (ds_illegal_eff || ds_is_ebreak || is_ecall || is_mret || is_sret ||
         is_wfi || is_sfence_vma || rvtest_trap_candidate) ? BBUS_FU_SYS :
        (mem_wr != 2'b00) ? BBUS_FU_LSU :
        (ds_csr_wen != 2'b00) ? BBUS_FU_CSR :
        (ds_branch != `BBUS_BR_NONE) ? BBUS_FU_BRU :
        BBUS_FU_ALU;

    assign ds_allowin = flush || !ds_valid || (ds_ready_go && es_allowin);
    assign ds_to_es_valid = ds_valid_eff && ds_ready_go;

    assign rf_raddr1 = rs1;
    assign rf_raddr2 = rs2;
    assign csr_raddr = csr_raddr_use;

    assign ds_pc = ds_pc_r;
    assign ds_instr = ds_instr_r;
    assign ds_rs1 = rs1;
    assign ds_rs2 = rs2;
    assign ds_src1 = rs1_from_ms ? ms_fwd_data : rf_rdata1;
    assign ds_src2 = rs2_from_ms ? ms_fwd_data : rf_rdata2;
    assign ds_src1_from_prev_ex = rs1_prev_ex_bypass;
    assign ds_src2_from_prev_ex = rs2_prev_ex_bypass;
    assign ds_src1_from_prev_wb = rs1_prev_wb_bypass;
    assign ds_src2_from_prev_wb = rs2_prev_wb_bypass;
    assign ds_pred_taken = ds_pred_taken_r;
    assign ds_pred_target = ds_pred_target_r;
    assign ds_imm = imm;
    assign ds_zimm = zimm;
    assign ds_scsr = csr_rdata;
    assign ds_rd = rd;
    assign ds_reg_wen = rvtest_trap_candidate ? 1'b0 : reg_wen;
    assign ds_branch = rvtest_trap_candidate ? `BBUS_BR_E : branch;
    assign ds_datatoreg = datatoreg;
    assign ds_mem_wr = mem_wr;
    assign ds_mem_op = mem_op;
    assign ds_alu_a_src = alu_a_src;
    assign ds_alu_b_src = alu_b_src;
    assign ds_alu_ctr = alu_ctr;
    assign ds_csr_wen = rvtest_trap_candidate ? 2'b11 : csr_wen;
    assign ds_csr_waddr1 = rvtest_trap_candidate ? 12'h342 : csr_waddr1_real;
    assign ds_csr_waddr2 = rvtest_trap_candidate ? 12'h341 : csr_waddr2_real;
    assign ds_csr_wdata_src1 = rvtest_trap_candidate ? 2'b11 : csr_wdata_src1;
    assign ds_csr_wdata_src2 = csr_wdata_src2;
    assign ds_illegal = ds_illegal_eff;
    assign ds_is_ebreak = is_ebreak && !rvtest_trap_candidate;
    assign ds_stop_fetch = ds_valid_eff && (ds_is_ebreak || ds_illegal_eff);

    assign ds_uop_view.valid = ds_valid_eff;
    assign ds_uop_view.pc = ds_pc_r;
    assign ds_uop_view.instr = ds_instr_r;
    assign ds_uop_view.nextpc = ds_pc_r + 32'd4;
    assign ds_uop_view.rs1 = rs1;
    assign ds_uop_view.rs2 = rs2;
    assign ds_uop_view.rd = rd;
    assign ds_uop_view.uses_rs1 = uses_rs1;
    assign ds_uop_view.uses_rs2 = uses_rs2;
    assign ds_uop_view.rf_wen = ds_reg_wen;
    assign ds_uop_view.fu = ds_fu_class;
    assign ds_uop_view.branch = bbus_branch_e'(ds_branch);
    assign ds_uop_view.imm = imm;
    assign ds_uop_view.src1_value = ds_src1;
    assign ds_uop_view.src2_value = ds_src2;
    assign ds_uop_view.mem_wr = mem_wr;
    assign ds_uop_view.mem_op = mem_op;
    assign ds_uop_view.datatoreg = datatoreg;
    assign ds_uop_view.csr_wen = ds_csr_wen;
    assign ds_uop_view.csr_waddr1 = ds_csr_waddr1;
    assign ds_uop_view.csr_waddr2 = ds_csr_waddr2;
    assign ds_uop_view.pred_taken = ds_pred_taken_r;
    assign ds_uop_view.pred_target = ds_pred_target_r;
    assign ds_uop_view.illegal = ds_illegal_eff;
    assign ds_uop_view.is_ebreak = ds_is_ebreak;
    assign ds_uop_view.exc.valid = 1'b0;
    assign ds_uop_view.exc.cause = 32'b0;
    assign ds_uop_view.exc.tval = 32'b0;
    assign ds_uop_view.exc.epc = 32'b0;

    assign slot0_uop_view.valid = ds_uop_view.valid;
    assign slot0_uop_view.pc = ds_uop_view.pc;
    assign slot0_uop_view.instr = ds_uop_view.instr;
    assign slot0_uop_view.nextpc = ds_uop_view.nextpc;
    assign slot0_uop_view.rs1 = ds_uop_view.rs1;
    assign slot0_uop_view.rs2 = ds_uop_view.rs2;
    assign slot0_uop_view.rd = ds_uop_view.rd;
    assign slot0_uop_view.uses_rs1 = ds_uop_view.uses_rs1;
    assign slot0_uop_view.uses_rs2 = ds_uop_view.uses_rs2;
    assign slot0_uop_view.rf_wen = ds_uop_view.rf_wen;
    assign slot0_uop_view.fu = ds_uop_view.fu;
    assign slot0_uop_view.branch = ds_uop_view.branch;
    assign slot0_uop_view.imm = ds_uop_view.imm;
    assign slot0_uop_view.src1_value = ds_uop_view.src1_value;
    assign slot0_uop_view.src2_value = ds_uop_view.src2_value;
    assign slot0_uop_view.mem_wr = ds_uop_view.mem_wr;
    assign slot0_uop_view.mem_op = ds_uop_view.mem_op;
    assign slot0_uop_view.datatoreg = ds_uop_view.datatoreg;
    assign slot0_uop_view.csr_wen = ds_uop_view.csr_wen;
    assign slot0_uop_view.csr_waddr1 = ds_uop_view.csr_waddr1;
    assign slot0_uop_view.csr_waddr2 = ds_uop_view.csr_waddr2;
    assign slot0_uop_view.pred_taken = ds_uop_view.pred_taken;
    assign slot0_uop_view.pred_target = ds_uop_view.pred_target;
    assign slot0_uop_view.illegal = ds_uop_view.illegal;
    assign slot0_uop_view.is_ebreak = ds_uop_view.is_ebreak;
    assign slot0_uop_view.exc.valid = ds_uop_view.exc.valid;
    assign slot0_uop_view.exc.cause = ds_uop_view.exc.cause;
    assign slot0_uop_view.exc.tval = ds_uop_view.exc.tval;
    assign slot0_uop_view.exc.epc = ds_uop_view.exc.epc;

    assign slot1_uop_view.valid = 1'b0;
    assign slot1_uop_view.pc = 32'b0;
    assign slot1_uop_view.instr = 32'b0;
    assign slot1_uop_view.nextpc = 32'b0;
    assign slot1_uop_view.rs1 = 5'b0;
    assign slot1_uop_view.rs2 = 5'b0;
    assign slot1_uop_view.rd = 5'b0;
    assign slot1_uop_view.uses_rs1 = 1'b0;
    assign slot1_uop_view.uses_rs2 = 1'b0;
    assign slot1_uop_view.rf_wen = 1'b0;
    assign slot1_uop_view.fu = BBUS_FU_NONE;
    assign slot1_uop_view.branch = BBUS_BR_NONE_E;
    assign slot1_uop_view.imm = 32'b0;
    assign slot1_uop_view.src1_value = 32'b0;
    assign slot1_uop_view.src2_value = 32'b0;
    assign slot1_uop_view.mem_wr = 2'b00;
    assign slot1_uop_view.mem_op = 3'b000;
    assign slot1_uop_view.datatoreg = 2'b00;
    assign slot1_uop_view.csr_wen = 2'b00;
    assign slot1_uop_view.csr_waddr1 = 12'b0;
    assign slot1_uop_view.csr_waddr2 = 12'b0;
    assign slot1_uop_view.pred_taken = 1'b0;
    assign slot1_uop_view.pred_target = 32'b0;
    assign slot1_uop_view.illegal = 1'b0;
    assign slot1_uop_view.is_ebreak = 1'b0;
    assign slot1_uop_view.exc.valid = 1'b0;
    assign slot1_uop_view.exc.cause = 32'b0;
    assign slot1_uop_view.exc.tval = 32'b0;
    assign slot1_uop_view.exc.epc = 32'b0;

    pairing_unit #(
        .SLOT1_ENABLE(1'b0)
    ) u_pairing_unit (
        .slot0_uop(slot0_uop_view),
        .slot1_uop(slot1_uop_view),
        .decision(pairing_decision)
    );

    assign slot0_meta_view.valid = slot0_uop_view.valid;
    assign slot0_meta_view.lane = BBUS_LANE0_E;
    assign slot0_meta_view.older = slot0_uop_view.valid;
    assign slot0_meta_view.younger = 1'b0;

    assign slot1_meta_view.valid = 1'b0;
    assign slot1_meta_view.lane = BBUS_LANE1_E;
    assign slot1_meta_view.older = 1'b0;
    assign slot1_meta_view.younger = 1'b1;

    assign decode_bundle_view.slot0_uop = slot0_uop_view;
    assign decode_bundle_view.slot1_uop = slot1_uop_view;
    assign decode_bundle_view.slot0_meta = slot0_meta_view;
    assign decode_bundle_view.slot1_meta = slot1_meta_view;
    assign decode_bundle_view.pairing = pairing_decision;

    /* verilator lint_off UNUSED */
    wire ds_uop_view_unused = ^ds_uop_view;
    wire pairing_decision_unused = ^pairing_decision;
    wire decode_bundle_view_unused = ^decode_bundle_view;
    /* verilator lint_on UNUSED */
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    assign ds_stage_block = ds_valid_eff && !ds_ready_go;
    assign ds_stage_block_reg_hazard = ds_valid_eff && reg_hazard;
    assign ds_stage_block_csr_hazard = ds_valid_eff && csr_hazard;
`endif
`endif
`ifdef NPC_M_EXTENSION
    assign ds_mdu_en = mdu_en;
    assign ds_mdu_op = mdu_op;
`else
    assign ds_mdu_en_dummy = 1'b0;
    assign ds_mdu_op_dummy = 3'b0;
`endif

    ContrGen contr_gen(
        .rst_n(rst_n),
        .instr(ds_instr_r),
        .ExtOP(ext_op),
        .RegWr(reg_wen),
        .Branch(branch),
        .DatatoReg(datatoreg),
        .MemWr(mem_wr),
        .MemOP(mem_op),
        .ALUAsrc(alu_a_src),
        .ALUBsrc(alu_b_src),
        .ALUctr(alu_ctr),
`ifdef NPC_M_EXTENSION
        .MduEn(mdu_en),
        .MduOp(mdu_op),
`endif
        .Illegal(illegal_instr)
    );

    CsrContrGen csr_contr_gen(
        .rst_n(rst_n),
        .instr(ds_instr_r),
        .uses_csr(uses_csr_fast),
        .CsrRsrc(csr_rsrc),
        .Csr1src(csr1src),
        .Csr2src(csr2src),
        .CsrWdatasrc1(csr_wdata_src1),
        .CsrWdatasrc2(csr_wdata_src2),
        .csr_wen(csr_wen)
    );

    ImmGen imm_gen(
        .instr(ds_instr_r),
        .ExtOP(ext_op),
        .imm(imm)
    );

    // Treat flush as killing the current ID slot. It also opens ds_allowin so a
    // correctly redirected fetch response can be accepted without adding an
    // extra stall cycle after the registered clear event.
    always @(posedge clk) begin
        if (!rst_n) begin
            ds_valid <= 1'b0;
        end else if (flush) begin
            ds_valid <= fs_to_ds_valid;
        end else if (ds_allowin) begin
            ds_valid <= fs_to_ds_valid;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ds_pc_r <= 32'b0;
            ds_instr_r <= 32'b0;
            ds_pred_taken_r <= 1'b0;
            ds_pred_target_r <= 32'b0;
        end else if (ds_allowin) begin
            ds_pc_r <= fs_pc;
            ds_instr_r <= fs_instr;
            ds_pred_taken_r <= fs_pred_taken;
            ds_pred_target_r <= fs_pred_target;
        end
    end
endmodule
