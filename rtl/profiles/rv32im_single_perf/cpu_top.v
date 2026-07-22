`timescale 1ns / 1ps

`ifdef NPC_USE_DPI
import "DPI-C" function void ftrace_print (
    input bit is_jal,
    input int rd,
    input bit is_jalr,
    input int unsigned src1,
    input int unsigned pc,
    input int unsigned dnpc
);
import "DPI-C" function void ebreak (
    input int unsigned pc,
    input int unsigned instr
);
import "DPI-C" function void inster_undefine (
    input int unsigned pc,
    input int unsigned instr
);
`ifdef NPC_RVTEST_TRAP_STUB
import "DPI-C" function void npc_trap_stub (
    input int unsigned pc,
    input int unsigned instr,
    input int unsigned cause,
    input int unsigned tval
);
`endif
import "DPI-C" function void ideal_cache_record_dcache (
    input int unsigned addr,
    input int len,
    input int is_write
);
import "DPI-C" function void rvtest_check_store (
    input int unsigned addr,
    input int len,
    input int unsigned data
);
`endif

module cpu_top(
    input clk,
    input rst_n,
    output reg commit_valid,
    output reg [31:0] commit_pc,
    output reg [31:0] commit_instr,
    output reg [31:0] commit_nextpc,

    output [31:0] ibus_axi_awaddr,
    output [7:0] ibus_axi_awlen,
    output [2:0] ibus_axi_awsize,
    output [1:0] ibus_axi_awburst,
    output ibus_axi_awvalid,
    input ibus_axi_awready,
    output [31:0] ibus_axi_wdata,
    output [3:0] ibus_axi_wstrb,
    output ibus_axi_wlast,
    output ibus_axi_wvalid,
    input ibus_axi_wready,
    input [1:0] ibus_axi_bresp,
    input ibus_axi_bvalid,
    output ibus_axi_bready,
    output [31:0] ibus_axi_araddr,
    output [7:0] ibus_axi_arlen,
    output [2:0] ibus_axi_arsize,
    output [1:0] ibus_axi_arburst,
    output ibus_axi_arvalid,
    input ibus_axi_arready,
    input [31:0] ibus_axi_rdata,
    input [1:0] ibus_axi_rresp,
    input ibus_axi_rvalid,
    output ibus_axi_rready,
    input ibus_axi_rlast,

    output [31:0] dbus_axi_awaddr,
    output [7:0] dbus_axi_awlen,
    output [2:0] dbus_axi_awsize,
    output [1:0] dbus_axi_awburst,
    output dbus_axi_awvalid,
    input dbus_axi_awready,
    output [31:0] dbus_axi_wdata,
    output [3:0] dbus_axi_wstrb,
    output dbus_axi_wlast,
    output dbus_axi_wvalid,
    input dbus_axi_wready,
    input [1:0] dbus_axi_bresp,
    input dbus_axi_bvalid,
    output dbus_axi_bready,
    output [31:0] dbus_axi_araddr,
    output [7:0] dbus_axi_arlen,
    output [2:0] dbus_axi_arsize,
    output [1:0] dbus_axi_arburst,
    output dbus_axi_arvalid,
    input dbus_axi_arready,
    input [31:0] dbus_axi_rdata,
    input [1:0] dbus_axi_rresp,
    input dbus_axi_rvalid,
    output dbus_axi_rready,
    input dbus_axi_rlast
);
`ifdef NPC_RESET_VECTOR_HEX
    localparam [31:0] RESET_VECTOR = 32'h`NPC_RESET_VECTOR_HEX;
`else
    localparam [31:0] RESET_VECTOR = 32'h80000000;
`endif
    `include "cpu_top/include/bbus_core_defs.svh"
    localparam [2:0] BRANCH_DEFAULT = `BBUS_BR_NONE;
    localparam [2:0] BRANCH_J = `BBUS_BR_J;
    localparam [2:0] BRANCH_JR = `BBUS_BR_JR;
    localparam [2:0] BRANCH_E = `BBUS_BR_E;
    localparam [2:0] BRANCH_BEQ = `BBUS_BR_BEQ;
    localparam [2:0] BRANCH_BNE = `BBUS_BR_BNE;
    localparam [2:0] BRANCH_BLT = `BBUS_BR_BLT;
    localparam [2:0] BRANCH_BGE = `BBUS_BR_BGE;
    localparam integer ICACHE_LINE_BYTES = 64;
    localparam integer ICACHE_LINE_COUNT = 64;
    localparam integer DCACHE_LINE_BYTES = 64;
    localparam integer DCACHE_LINE_COUNT = 64;
`ifdef NPC_DPI_MEM_LATENCY
    localparam integer DPI_MEM_LATENCY = `NPC_DPI_MEM_LATENCY;
`else
    localparam integer DPI_MEM_LATENCY = 2;
`endif
    localparam integer ICACHE_LINE_WORDS = ICACHE_LINE_BYTES / 4;
    localparam integer DCACHE_LINE_WORDS = DCACHE_LINE_BYTES / 4;
    localparam integer ICACHE_MISS_PENALTY = DPI_MEM_LATENCY + ICACHE_LINE_WORDS;
    localparam integer DCACHE_MISS_PENALTY = DPI_MEM_LATENCY + DCACHE_LINE_WORDS;

    reg [31:0] PC /* verilator public_flat */;
    reg [31:0] instr /* verilator public_flat */;
    reg [31:0] NextPC /* verilator public_flat */;
    reg [31:0] arch_pc /* verilator public_flat */;

    wire [4:0] rf_raddr1;
    wire [4:0] rf_raddr2;
    wire [31:0] rf_rdata1;
    wire [31:0] rf_rdata2;
    wire [31:0] rf_wdata;
    wire [4:0] rf_waddr;
    wire rf_wen;

    wire [11:0] csr_raddr;
    wire [31:0] csr_rdata;
    wire [31:0] csr_wdata1;
    wire [11:0] csr_waddr1;
    wire [31:0] csr_wdata2;
    wire [11:0] csr_waddr2;
    wire [31:0] csr_wdata3;
    wire [11:0] csr_waddr3;
    wire csr_wen3;
    wire [1:0] csr_wen_eff;
    wire [1:0] csr_priv;
    wire [31:0] csr_mstatus_value;
    wire [31:0] csr_mtvec_value;
    wire [31:0] csr_mie_value;
    wire [31:0] csr_mip_value;
    wire [31:0] csr_mideleg_value;
    wire interrupt_trap_valid;
    wire [31:0] interrupt_trap_cause;
    wire [31:0] interrupt_trap_epc;
    wire [31:0] interrupt_trap_target_pc;

    wire fs_to_ds_valid;
    wire if_stall;
    wire [31:0] fs_pc;
    wire [31:0] fs_instr;
    wire fs_pred_taken;
    wire [31:0] fs_pred_target;

    wire ds_allowin;
    wire ds_to_es_valid;
    wire ds_to_es_fire;
    wire [31:0] ds_pc;
    wire [31:0] ds_instr;
    wire [4:0] ds_rs1;
    wire [4:0] ds_rs2;
    wire [31:0] ds_src1;
    wire [31:0] ds_src2;
    wire ds_src1_from_prev_ex;
    wire ds_src2_from_prev_ex;
    wire ds_src1_from_prev_wb;
    wire ds_src2_from_prev_wb;
    wire ds_pred_taken;
    wire [31:0] ds_pred_target;
    wire [31:0] ds_imm;
    wire [31:0] ds_zimm;
    wire [31:0] ds_scsr;
    wire [4:0] ds_rd;
    wire ds_reg_wen;
    wire [2:0] ds_branch;
    wire [1:0] ds_datatoreg;
    wire [1:0] ds_mem_wr;
    wire [2:0] ds_mem_op;
    wire [1:0] ds_alu_a_src;
    wire [1:0] ds_alu_b_src;
    wire [3:0] ds_alu_ctr;
    wire [1:0] ds_csr_wen;
    wire [11:0] ds_csr_waddr1;
    wire [11:0] ds_csr_waddr2;
    wire [1:0] ds_csr_wdata_src1;
    wire ds_csr_wdata_src2;
    wire ds_illegal;
    wire ds_is_ebreak;
    wire ds_stop_fetch;
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    wire ds_stage_block;
    wire ds_stage_block_reg_hazard;
    wire ds_stage_block_csr_hazard;
`endif
`endif
`ifdef NPC_M_EXTENSION
    wire ds_mdu_en;
    wire [2:0] ds_mdu_op;
`else
    wire ds_mdu_en_dummy;
    wire [2:0] ds_mdu_op_dummy;
`endif

    wire es_allowin;
    wire es_to_ms_valid;
    wire es_valid;
    wire es_result_bypassable;
    wire [31:0] es_pc;
    wire [31:0] es_instr;
    wire [31:0] es_nextpc;
    wire [4:0] es_rd;
    wire es_reg_wen;
    wire [1:0] es_datatoreg;
    wire [1:0] es_mem_wr;
    wire [2:0] es_mem_op;
    wire [31:0] es_aluout;
    wire [31:0] es_mem_wdata;
    wire [31:0] es_csr_read_data;
    wire [1:0] es_csr_wen;
    wire [11:0] es_csr_waddr1;
    wire [11:0] es_csr_waddr2;
    wire [31:0] es_csr_wdata1;
    wire [31:0] es_csr_wdata2;
    wire es_illegal;
    wire es_is_ebreak;
    wire [2:0] es_branch;
    wire [31:0] es_src1_value;
    wire es_mem_fwd_dep;
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    wire es_stage_block;
    wire es_stage_block_mdu_wait;
    wire es_stage_block_redirect_wait;
`endif
`endif
    wire ex_flush_valid;
    wire [31:0] ex_flush_pc;
    wire ex_mispredict_flush_valid;
    wire [31:0] ex_mispredict_flush_pc;
    wire ex_branch_taken_actual;
    wire redirect_token_valid;
    wire [31:0] redirect_token_target_pc;
    wire redirect_token_kill_younger;
    wire redirect_token_trace_is_redirect;
    wire trap_redirect_request_valid;
    wire [31:0] trap_redirect_request_pc;
    wire fast_redirect_valid;
    wire [31:0] fast_redirect_pc;
    wire ex_branch_e_slowpath_fire;
    wire interrupt_prepare_kill_valid;
    wire slowpath_prepare_kill_valid;
    wire redirect_flush_valid;
    reg redirect_clear_valid;
    wire stop_clear_set;
    reg stop_clear_valid;
    reg trap_slowpath_pending;
    reg slow_redirect_valid_r;
    reg [31:0] slow_redirect_pc_r;
    reg slow_redirect_trace_is_redirect_r;
    bbus_redirect_t fast_redirect_token;
    bbus_redirect_t slow_redirect_token;
    bbus_redirect_t active_redirect_token;
    bbus_exception_t commit_exception_token;
    bbus_commit_t commit_token;
    bbus_uop_t commit_uop_view;
    bbus_bpu_update_t bpu_update_token;
    wire pipe_clear_valid;
    wire stop_fetch;
`ifndef NPC_USE_DPI
    reg cpu_halted;
`endif

    wire ms_allowin;
    wire ms_to_ws_valid;
    wire ms_valid;
    wire [31:0] ms_pc;
    wire [31:0] ms_instr;
    wire [31:0] ms_nextpc;
    wire [4:0] ms_rd;
    wire ms_reg_wen;
    wire [1:0] ms_datatoreg;
    wire [2:0] ms_mem_op;
    wire [31:0] ms_aluout;
    wire [31:0] ms_mem_rdata;
    wire [31:0] ms_csr_read_data;
    wire [1:0] ms_csr_wen;
    wire [11:0] ms_csr_waddr1;
    wire [11:0] ms_csr_waddr2;
    wire [31:0] ms_csr_wdata1;
    wire [31:0] ms_csr_wdata2;
    wire ms_illegal;
    wire ms_is_ebreak;
    wire [2:0] ms_branch;
    wire [31:0] ms_src1_value;
    wire ms_slowpath_prepare_kill_valid;
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    wire ms_stage_block;
    wire ms_stage_block_req_phase;
    wire ms_stage_block_resp_phase;
    wire ms_fast_req_fire_trace;
    wire ms_slow_req_fire_trace;
    wire ms_slow_req_fwd_dep_fire_trace;
    wire ms_slow_req_nonfwd_fire_trace;
`endif
`endif
    wire hidden_mreq_valid;
    wire hidden_mreq_reg_wen;
    wire [4:0] hidden_mreq_rd;
    wire [1:0] hidden_mreq_csr_wen;
    wire [11:0] hidden_mreq_csr_waddr1;
    wire [11:0] hidden_mreq_csr_waddr2;

    wire ws_allowin;
    wire ws_valid;
    wire [31:0] ws_pc;
    wire [31:0] ws_instr;
    wire [31:0] ws_nextpc;
    wire [4:0] ws_rd;
    wire ws_reg_wen;
    wire [31:0] ws_aluout;
    wire [31:0] ws_rf_wdata;
    wire [1:0] ws_csr_wen;
    wire [11:0] ws_csr_waddr1;
    wire [11:0] ws_csr_waddr2;
    wire [31:0] ws_csr_wdata1;
    wire [31:0] ws_csr_wdata2;
    wire ws_illegal;
    wire ws_is_ebreak;
    wire [2:0] ws_branch;
    wire [31:0] ws_src1_value;

    wire ms_fwd_valid;
    wire [31:0] ms_fwd_data;

    wire ibus_req_ready;
    wire ibus_resp_valid;
    wire [31:0] ibus_resp_data;
    wire ibus_req_valid_w;
    wire [31:0] ibus_req_addr_w;
    wire ibus_resp_ready_w;

    wire dbus_req_valid;
    wire dbus_req_ready;
    wire dbus_req_write;
    wire [31:0] dbus_req_addr;
    wire [31:0] dbus_req_wdata;
    wire [3:0] dbus_req_wstrb;
    wire [2:0] dbus_req_len;
    wire dbus_resp_valid;
    wire dbus_resp_ready;
    wire [31:0] dbus_resp_data;

    wire ibus_mem_req_valid;
    wire ibus_mem_req_ready;
    wire ibus_mem_req_write;
    wire [31:0] ibus_mem_req_addr;
    wire [31:0] ibus_mem_req_wdata;
    wire [3:0] ibus_mem_req_wstrb;
    wire [2:0] ibus_mem_req_len;
    wire ibus_mem_resp_valid;
    wire ibus_mem_resp_ready;
    wire [31:0] ibus_mem_resp_data;

    wire dbus_mem_req_valid;
    wire dbus_mem_req_ready;
    wire dbus_mem_req_write;
    wire [31:0] dbus_mem_req_addr;
    wire [31:0] dbus_mem_req_wdata;
    wire [3:0] dbus_mem_req_wstrb;
    wire [2:0] dbus_mem_req_len;
    wire dbus_mem_resp_valid;
    wire dbus_mem_resp_ready;
    wire [31:0] dbus_mem_resp_data;

`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
    wire [63:0] icache_stat_access;
    wire [63:0] icache_stat_hit;
    wire [63:0] icache_stat_miss;
    wire [63:0] icache_stat_refill_req;
    wire [63:0] icache_stat_refill_resp;
    wire [63:0] icache_stat_refill_bypass;
    wire [63:0] dcache_stat_access;
    wire [63:0] dcache_stat_load_access;
    wire [63:0] dcache_stat_store_access;
    wire [63:0] dcache_stat_load_hit;
    wire [63:0] dcache_stat_load_miss;
    wire [63:0] dcache_stat_store_hit;
    wire [63:0] dcache_stat_store_miss;
    wire [63:0] dcache_stat_refill_req;
    wire [63:0] dcache_stat_refill_resp;
    wire [63:0] dcache_stat_write_req;
    wire [63:0] dcache_stat_write_resp;
    wire [63:0] dcache_stat_refill_ld_bypass;
    wire [63:0] dcache_stat_refill_store_merge;
`endif
`endif

`ifdef NPC_BRANCH_STAT
    wire branch_stat_fetch_req_valid;
    wire [31:0] branch_stat_fetch_req_pc;
    wire branch_stat_fetch_accept_valid;
    wire [31:0] branch_stat_fetch_accept_pc;
    wire [31:0] branch_stat_fetch_accept_instr;
    wire branch_stat_fetch_drop_valid;
    wire branch_stat_fetch_drop_redirect;
    wire [31:0] branch_stat_fetch_drop_pc;
    wire [31:0] branch_stat_fetch_drop_instr;
    wire branch_stat_resolve_valid;

    assign branch_stat_resolve_valid =
        es_valid && ms_allowin && (es_branch != BRANCH_DEFAULT) && (es_branch != BRANCH_E);
`endif

    wire bpu_update_valid =
        es_valid && ms_allowin && (es_branch != BRANCH_DEFAULT) && (es_branch != BRANCH_E);
    wire bpu_update_is_cond =
        (es_branch == BRANCH_BEQ) ||
        (es_branch == BRANCH_BNE) ||
        (es_branch == BRANCH_BLT) ||
        (es_branch == BRANCH_BGE);
    assign bpu_update_token.valid = bpu_update_valid;
    assign bpu_update_token.pc = es_pc;
    assign bpu_update_token.is_cond = bpu_update_is_cond;
    assign bpu_update_token.taken = ex_branch_taken_actual;
    assign bpu_update_token.target_pc = es_nextpc;
    assign bpu_update_token.mispredict = ex_mispredict_flush_valid;

    function [31:0] csr_value_after_writes;
        input [31:0] current_value;
        input [11:0] target_addr;
        input wen1;
        input [11:0] waddr1;
        input [31:0] wdata1;
        input wen2;
        input [11:0] waddr2;
        input [31:0] wdata2;
        input wen3;
        input [11:0] waddr3;
        input [31:0] wdata3;
        begin
            csr_value_after_writes =
                (wen3 && (waddr3 == target_addr)) ? wdata3 :
                (wen2 && (waddr2 == target_addr)) ? wdata2 :
                (wen1 && (waddr1 == target_addr)) ? wdata1 :
                current_value;
        end
    endfunction

    function [4:0] interrupt_priority_cause;
        input [31:0] deliverable;
        begin
            if (deliverable[11]) interrupt_priority_cause = 5'd11;
            else if (deliverable[3]) interrupt_priority_cause = 5'd3;
            else if (deliverable[7]) interrupt_priority_cause = 5'd7;
            else if (deliverable[9]) interrupt_priority_cause = 5'd9;
            else if (deliverable[1]) interrupt_priority_cause = 5'd1;
            else if (deliverable[5]) interrupt_priority_cause = 5'd5;
            else if (deliverable[13]) interrupt_priority_cause = 5'd13;
            else if (deliverable[0]) interrupt_priority_cause = 5'd0;
            else if (deliverable[2]) interrupt_priority_cause = 5'd2;
            else if (deliverable[4]) interrupt_priority_cause = 5'd4;
            else if (deliverable[6]) interrupt_priority_cause = 5'd6;
            else if (deliverable[8]) interrupt_priority_cause = 5'd8;
            else if (deliverable[10]) interrupt_priority_cause = 5'd10;
            else if (deliverable[12]) interrupt_priority_cause = 5'd12;
            else if (deliverable[14]) interrupt_priority_cause = 5'd14;
            else interrupt_priority_cause = 5'd15;
        end
    endfunction

    function [31:0] interrupt_tvec_target;
        input [31:0] tvec;
        input [4:0] cause;
        begin
            interrupt_tvec_target =
                (tvec[1:0] == 2'b01) ?
                ((tvec & 32'hfffffffc) + {25'b0, cause, 2'b00}) :
                (tvec & 32'hfffffffc);
        end
    endfunction

    wire commit_side_effect = ws_valid && !ws_is_ebreak && !ws_illegal;

    // Local CommitPacket alias. This is a naming contract only.
    // Keep WB module ports, RF writeback, difftest, and stat behavior unchanged.
    wire        commit_pkt_valid = ws_valid;
    wire [31:0] commit_pkt_pc = ws_pc;
    wire [31:0] commit_pkt_instr = ws_instr;
    wire [31:0] commit_pkt_nextpc = ws_nextpc;
    wire [4:0]  commit_pkt_rd = ws_rd;
    wire [31:0] commit_pkt_wdata = ws_rf_wdata;
    wire        commit_pkt_reg_wen = ws_reg_wen;
    wire        commit_pkt_side_effect_valid = commit_side_effect;
    wire        commit_pkt_is_fence_i =
        commit_pkt_valid && commit_pkt_side_effect_valid &&
        (commit_pkt_instr[6:0] == 7'b0001111) &&
        (commit_pkt_instr[14:12] == 3'b001);
    wire commit_pkt_is_jal = commit_pkt_instr[6:0] == 7'b1101111;
    wire commit_pkt_is_jalr = commit_pkt_instr[6:0] == 7'b1100111;
    wire commit_pkt_is_branch = commit_pkt_instr[6:0] == 7'b1100011;
    wire commit_pkt_is_mret = commit_pkt_instr == 32'h30200073;
    wire commit_pkt_is_sret = commit_pkt_instr == 32'h10200073;
    wire commit_pkt_is_xret = commit_pkt_is_mret || commit_pkt_is_sret;
    wire [31:0] commit_pkt_imm_i =
        {{20{commit_pkt_instr[31]}}, commit_pkt_instr[31:20]};
    wire [31:0] commit_pkt_imm_b =
        {{19{commit_pkt_instr[31]}}, commit_pkt_instr[31], commit_pkt_instr[7],
         commit_pkt_instr[30:25], commit_pkt_instr[11:8], 1'b0};
    wire [31:0] commit_pkt_imm_j =
        {{11{commit_pkt_instr[31]}}, commit_pkt_instr[31], commit_pkt_instr[19:12],
         commit_pkt_instr[20], commit_pkt_instr[30:21], 1'b0};
    wire commit_pkt_inst_addr_misaligned_trap =
        commit_pkt_valid && commit_pkt_side_effect_valid &&
        (ws_csr_wen == 2'b11) &&
        (ws_csr_waddr1 == 12'h342) &&
        (ws_csr_waddr2 == 12'h341) &&
        (ws_csr_wdata1 == 32'd0) &&
        (commit_pkt_is_jal || commit_pkt_is_jalr || commit_pkt_is_branch);
    wire [31:0] commit_pkt_inst_addr_misaligned_tval =
        commit_pkt_is_jalr ? ((ws_src1_value + commit_pkt_imm_i) & 32'hfffffffe) :
        commit_pkt_is_jal ? (commit_pkt_pc + commit_pkt_imm_j) :
        (commit_pkt_pc + commit_pkt_imm_b);
    wire commit_pkt_trap_csr_write =
        (ws_csr_wen == 2'b11) &&
        (ws_csr_waddr1 == 12'h342) &&
        (ws_csr_waddr2 == 12'h341);
    wire commit_pkt_illegal_inst_trap =
        commit_pkt_valid && commit_pkt_side_effect_valid &&
        commit_pkt_trap_csr_write &&
        (ws_csr_wdata1 == 32'd2);
    wire commit_pkt_load_addr_misaligned_trap =
        commit_pkt_valid && commit_pkt_side_effect_valid &&
        commit_pkt_trap_csr_write &&
        (ws_csr_wdata1 == 32'd4);
    wire commit_pkt_store_addr_misaligned_trap =
        commit_pkt_valid && commit_pkt_side_effect_valid &&
        commit_pkt_trap_csr_write &&
        (ws_csr_wdata1 == 32'd6);
    wire commit_pkt_mem_addr_misaligned_trap =
        commit_pkt_load_addr_misaligned_trap || commit_pkt_store_addr_misaligned_trap;

`ifdef NPC_RVTEST_TRAP_STUB
    wire es_csr_wen1_for_interrupt = es_to_ms_valid && es_csr_wen[1];
    wire es_csr_wen2_for_interrupt = es_to_ms_valid && es_csr_wen[1] && es_csr_wen[0];
    wire [31:0] es_mstatus_after = csr_value_after_writes(
        csr_mstatus_value, 12'h300,
        es_csr_wen1_for_interrupt, es_csr_waddr1, es_csr_wdata1,
        es_csr_wen2_for_interrupt, es_csr_waddr2, es_csr_wdata2,
        1'b0, 12'b0, 32'b0
    );
    wire [31:0] es_mie_after = csr_value_after_writes(
        csr_mie_value, 12'h304,
        es_csr_wen1_for_interrupt, es_csr_waddr1, es_csr_wdata1,
        es_csr_wen2_for_interrupt, es_csr_waddr2, es_csr_wdata2,
        1'b0, 12'b0, 32'b0
    );
    wire [31:0] es_mip_after = csr_value_after_writes(
        csr_mip_value, 12'h344,
        es_csr_wen1_for_interrupt, es_csr_waddr1, es_csr_wdata1,
        es_csr_wen2_for_interrupt, es_csr_waddr2, es_csr_wdata2,
        1'b0, 12'b0, 32'b0
    );
    wire [31:0] es_mideleg_after = csr_value_after_writes(
        csr_mideleg_value, 12'h303,
        es_csr_wen1_for_interrupt, es_csr_waddr1, es_csr_wdata1,
        es_csr_wen2_for_interrupt, es_csr_waddr2, es_csr_wdata2,
        1'b0, 12'b0, 32'b0
    );
    wire es_interrupt_can_take_m =
        (csr_priv < 2'b11) || ((csr_priv == 2'b11) && es_mstatus_after[3]);
    wire [31:0] es_interrupt_deliverable =
        (es_mip_after & es_mie_after & ~es_mideleg_after) &
        {32{es_interrupt_can_take_m}};
    assign interrupt_prepare_kill_valid =
        es_to_ms_valid && !es_illegal && !es_is_ebreak &&
        (es_interrupt_deliverable != 32'b0);

    wire commit_csr_wen1_for_interrupt = csr_wen_eff[1];
    wire commit_csr_wen2_for_interrupt = csr_wen_eff[1] && csr_wen_eff[0];
    wire [31:0] commit_mstatus_after = csr_value_after_writes(
        csr_mstatus_value, 12'h300,
        commit_csr_wen1_for_interrupt, csr_waddr1, csr_wdata1,
        commit_csr_wen2_for_interrupt, csr_waddr2, csr_wdata2,
        csr_wen3, csr_waddr3, csr_wdata3
    );
    wire [31:0] commit_mtvec_after = csr_value_after_writes(
        csr_mtvec_value, 12'h305,
        commit_csr_wen1_for_interrupt, csr_waddr1, csr_wdata1,
        commit_csr_wen2_for_interrupt, csr_waddr2, csr_wdata2,
        csr_wen3, csr_waddr3, csr_wdata3
    );
    wire [31:0] commit_mie_after = csr_value_after_writes(
        csr_mie_value, 12'h304,
        commit_csr_wen1_for_interrupt, csr_waddr1, csr_wdata1,
        commit_csr_wen2_for_interrupt, csr_waddr2, csr_wdata2,
        csr_wen3, csr_waddr3, csr_wdata3
    );
    wire [31:0] commit_mip_after = csr_value_after_writes(
        csr_mip_value, 12'h344,
        commit_csr_wen1_for_interrupt, csr_waddr1, csr_wdata1,
        commit_csr_wen2_for_interrupt, csr_waddr2, csr_wdata2,
        csr_wen3, csr_waddr3, csr_wdata3
    );
    wire [31:0] commit_mideleg_after = csr_value_after_writes(
        csr_mideleg_value, 12'h303,
        commit_csr_wen1_for_interrupt, csr_waddr1, csr_wdata1,
        commit_csr_wen2_for_interrupt, csr_waddr2, csr_wdata2,
        csr_wen3, csr_waddr3, csr_wdata3
    );
    wire commit_interrupt_can_take_m =
        (csr_priv < 2'b11) || ((csr_priv == 2'b11) && commit_mstatus_after[3]);
    wire [31:0] commit_interrupt_deliverable =
        (commit_mip_after & commit_mie_after & ~commit_mideleg_after) &
        {32{commit_interrupt_can_take_m}};
    wire [4:0] commit_interrupt_cause = interrupt_priority_cause(commit_interrupt_deliverable);
    assign interrupt_trap_valid =
        commit_pkt_valid && commit_pkt_side_effect_valid &&
        !commit_pkt_trap_csr_write &&
        !commit_pkt_is_xret &&
        (commit_interrupt_deliverable != 32'b0);
    assign interrupt_trap_cause = 32'h80000000 | {27'b0, commit_interrupt_cause};
    assign interrupt_trap_epc = commit_pkt_nextpc;
    assign interrupt_trap_target_pc = interrupt_tvec_target(commit_mtvec_after, commit_interrupt_cause);
`else
    assign interrupt_prepare_kill_valid = 1'b0;
    assign interrupt_trap_valid = 1'b0;
    assign interrupt_trap_cause = 32'b0;
    assign interrupt_trap_epc = 32'b0;
    assign interrupt_trap_target_pc = 32'b0;
`endif

    // Local TrapToken alias for the current rv32mi slow path. The architectural
    // redirect target is now selected at commit age; EX Branch_E only prepares
    // a frontend clear so younger instructions cannot pass the slow path.
    /* verilator lint_off UNUSED */
    wire trap_token_exception_valid =
        commit_pkt_valid && commit_pkt_side_effect_valid &&
        commit_pkt_trap_csr_write &&
        !commit_pkt_is_xret;
    wire        trap_token_is_xret =
        commit_pkt_valid && commit_pkt_side_effect_valid &&
        commit_pkt_is_xret;
    wire        trap_token_is_interrupt = interrupt_trap_valid;
    wire        trap_token_valid =
        trap_token_exception_valid || trap_token_is_xret || trap_token_is_interrupt;
    wire [31:0] trap_token_cause =
        trap_token_is_interrupt ? interrupt_trap_cause :
        trap_token_exception_valid ? ws_csr_wdata1 :
        32'b0;
    wire [31:0] trap_token_tval =
        commit_pkt_inst_addr_misaligned_trap ? commit_pkt_inst_addr_misaligned_tval :
        commit_pkt_mem_addr_misaligned_trap ? ws_aluout :
        commit_pkt_illegal_inst_trap ? commit_pkt_instr :
        32'b0;
    wire [31:0] trap_token_epc =
        trap_token_is_interrupt ? interrupt_trap_epc :
        trap_token_exception_valid ? ws_csr_wdata2 :
        commit_pkt_pc;
    wire [31:0] trap_token_vector_pc =
        trap_token_is_interrupt ? interrupt_trap_target_pc :
        (csr_mtvec_value & 32'hfffffffc);
    wire [31:0] trap_token_xret_pc = commit_pkt_nextpc;
    wire        trap_token_arch_redirect_valid = trap_token_valid;
    wire [31:0] trap_token_arch_redirect_pc =
        trap_token_is_xret ? trap_token_xret_pc : trap_token_vector_pc;
    wire        trap_token_kill_side_effect =
        trap_token_exception_valid && !trap_token_is_interrupt;
    wire        trap_token_source_commit = trap_token_valid && commit_pkt_valid;
    /* verilator lint_on UNUSED */
    wire commit_arch_nextpc_redirect_visible =
        trap_token_arch_redirect_valid && !trap_token_is_interrupt;
    wire [31:0] commit_arch_nextpc =
        commit_arch_nextpc_redirect_visible ? trap_token_arch_redirect_pc : commit_pkt_nextpc;

    assign commit_exception_token.valid = trap_token_exception_valid || trap_token_is_interrupt;
    assign commit_exception_token.cause = trap_token_cause;
    assign commit_exception_token.tval = trap_token_tval;
    assign commit_exception_token.epc = trap_token_epc;

    assign commit_token.valid = commit_pkt_valid;
    assign commit_token.pc = commit_pkt_pc;
    assign commit_token.instr = commit_pkt_instr;
    assign commit_token.nextpc = commit_arch_nextpc;
    assign commit_token.rd = commit_pkt_rd;
    assign commit_token.wdata = commit_pkt_wdata;
    assign commit_token.rf_wen = commit_pkt_reg_wen;
    assign commit_token.side_effect_valid = commit_pkt_side_effect_valid;
    assign commit_token.exc.valid = commit_exception_token.valid;
    assign commit_token.exc.cause = commit_exception_token.cause;
    assign commit_token.exc.tval = commit_exception_token.tval;
    assign commit_token.exc.epc = commit_exception_token.epc;

    assign commit_uop_view.valid = commit_token.valid;
    assign commit_uop_view.pc = commit_token.pc;
    assign commit_uop_view.instr = commit_token.instr;
    assign commit_uop_view.nextpc = commit_token.nextpc;
    assign commit_uop_view.rs1 = 5'b0;
    assign commit_uop_view.rs2 = 5'b0;
    assign commit_uop_view.rd = commit_token.rd;
    assign commit_uop_view.uses_rs1 = 1'b0;
    assign commit_uop_view.uses_rs2 = 1'b0;
    assign commit_uop_view.rf_wen = commit_token.rf_wen;
    assign commit_uop_view.fu =
        (ws_illegal || ws_is_ebreak || commit_token.exc.valid) ? BBUS_FU_SYS :
        (ws_branch != BRANCH_DEFAULT) ? BBUS_FU_BRU :
        BBUS_FU_NONE;
    assign commit_uop_view.branch = bbus_branch_e'(ws_branch);
    assign commit_uop_view.imm = 32'b0;
    assign commit_uop_view.src1_value = ws_src1_value;
    assign commit_uop_view.src2_value = 32'b0;
    assign commit_uop_view.mem_wr = 2'b00;
    assign commit_uop_view.mem_op = 3'b000;
    assign commit_uop_view.datatoreg = 2'b00;
    assign commit_uop_view.csr_wen = ws_csr_wen;
    assign commit_uop_view.csr_waddr1 = ws_csr_waddr1;
    assign commit_uop_view.csr_waddr2 = ws_csr_waddr2;
    assign commit_uop_view.pred_taken = 1'b0;
    assign commit_uop_view.pred_target = 32'b0;
    assign commit_uop_view.illegal = ws_illegal;
    assign commit_uop_view.is_ebreak = ws_is_ebreak;
    assign commit_uop_view.exc.valid = commit_token.exc.valid;
    assign commit_uop_view.exc.cause = commit_token.exc.cause;
    assign commit_uop_view.exc.tval = commit_token.exc.tval;
    assign commit_uop_view.exc.epc = commit_token.exc.epc;
    /* verilator lint_off UNUSED */
    wire commit_uop_view_unused = ^commit_uop_view;
    /* verilator lint_on UNUSED */

    wire [31:0] ms_load_data_ext =
        (ms_mem_op == 3'b000) ? {{24{ms_mem_rdata[7]}}, ms_mem_rdata[7:0]} :
        (ms_mem_op == 3'b001) ? {{16{ms_mem_rdata[15]}}, ms_mem_rdata[15:0]} :
        (ms_mem_op == 3'b100) ? {24'b0, ms_mem_rdata[7:0]} :
        (ms_mem_op == 3'b101) ? {16'b0, ms_mem_rdata[15:0]} :
        ms_mem_rdata;
    wire ms_load_late_fwd_valid = ms_valid && ms_reg_wen && (ms_rd != 5'b0) &&
        (ms_datatoreg == 2'b01) && ms_to_ws_valid;
    wire ms_nonload_fwd_valid = ms_valid && ms_reg_wen && (ms_rd != 5'b0) &&
        (ms_datatoreg != 2'b01);
    // Preserve load late-result same-cycle forwarding from MS when memory
    // response is accepted this cycle (ms_to_ws_valid). This avoids adding an
    // extra load-use bubble while still keeping EX input hold registers.
    assign ms_fwd_valid = ms_load_late_fwd_valid || ms_nonload_fwd_valid;
    assign ms_fwd_data =
        (ms_datatoreg == 2'b00) ? ms_aluout :
        (ms_datatoreg == 2'b01) ? ms_load_data_ext :
        ms_csr_read_data;

    assign trap_redirect_request_valid = trap_token_arch_redirect_valid;
    assign trap_redirect_request_pc = trap_token_arch_redirect_pc;
    assign ex_branch_e_slowpath_fire = ex_flush_valid && (es_branch == BRANCH_E);
    assign slowpath_prepare_kill_valid =
        ex_branch_e_slowpath_fire || ms_slowpath_prepare_kill_valid ||
        interrupt_prepare_kill_valid;
    assign fast_redirect_valid = ex_mispredict_flush_valid;
    assign fast_redirect_pc = ex_mispredict_flush_pc;

    assign fast_redirect_token.valid = fast_redirect_valid;
    assign fast_redirect_token.pc = es_pc;
    assign fast_redirect_token.target_pc = fast_redirect_pc;
    assign fast_redirect_token.is_fast = fast_redirect_valid;
    assign fast_redirect_token.is_slow = 1'b0;
    assign fast_redirect_token.kill_younger = fast_redirect_valid;
    assign fast_redirect_token.trace_is_redirect = fast_redirect_valid;

    assign slow_redirect_token.valid = slow_redirect_valid_r;
    assign slow_redirect_token.pc = 32'b0;
    assign slow_redirect_token.target_pc = slow_redirect_pc_r;
    assign slow_redirect_token.is_fast = 1'b0;
    assign slow_redirect_token.is_slow = slow_redirect_valid_r;
    assign slow_redirect_token.kill_younger = slow_redirect_valid_r;
    assign slow_redirect_token.trace_is_redirect = slow_redirect_trace_is_redirect_r;

    assign active_redirect_token.valid =
        slow_redirect_token.valid || fast_redirect_token.valid;
    assign active_redirect_token.pc =
        slow_redirect_token.valid ? slow_redirect_token.pc : fast_redirect_token.pc;
    assign active_redirect_token.target_pc =
        slow_redirect_token.valid ? slow_redirect_token.target_pc : fast_redirect_token.target_pc;
    assign active_redirect_token.is_fast =
        fast_redirect_token.is_fast && !slow_redirect_token.valid;
    assign active_redirect_token.is_slow = slow_redirect_token.is_slow;
    assign active_redirect_token.kill_younger =
        slow_redirect_token.kill_younger || fast_redirect_token.kill_younger;
    assign active_redirect_token.trace_is_redirect =
        slow_redirect_token.trace_is_redirect || fast_redirect_token.trace_is_redirect;

    // IF sees two redirect classes:
    //   1. same-cycle EX fast redirect for normal branch/jump mispredicts
    //   2. registered commit-age slow redirect for trap/xret/interrupt events
    // Keep the IF-facing mux shallow so trap target selection never feeds the
    // EX mispredict fast path combinationally.
    assign redirect_token_valid = active_redirect_token.valid;
    assign redirect_token_target_pc = active_redirect_token.target_pc;
    assign redirect_token_kill_younger = active_redirect_token.kill_younger;
    assign redirect_token_trace_is_redirect = active_redirect_token.trace_is_redirect;
    assign redirect_flush_valid = redirect_token_valid;
    assign ds_to_es_fire = ds_to_es_valid && !redirect_token_kill_younger &&
        !slowpath_prepare_kill_valid && !trap_slowpath_pending &&
        !redirect_clear_valid && !stop_clear_valid;
    // FPGA timing note:
    // Redirects still update IF immediately, but ID is cleared from a registered
    // event. The same-cycle redirect gate above prevents the wrong-path ID
    // instruction from entering EX while cutting the EX-compare -> ID-valid path.
    //
    // ebreak/illegal only need to stop and clear younger instructions. Register
    // the stop clear sideband so ID decode does not feed IF next_fetch_pc in the
    // same cycle on FPGA.
    assign stop_clear_set =
        slowpath_prepare_kill_valid ||
        (ds_to_es_fire && es_allowin && (ds_is_ebreak || ds_illegal));
    assign pipe_clear_valid = redirect_clear_valid || stop_clear_valid;
    assign stop_fetch =
`ifndef NPC_USE_DPI
        cpu_halted ||
`endif
        trap_slowpath_pending ||
        slowpath_prepare_kill_valid ||
        ds_stop_fetch ||
        (es_valid && (es_is_ebreak || es_illegal)) ||
        (ms_valid && (ms_is_ebreak || ms_illegal)) ||
        (ws_valid && (ws_is_ebreak || ws_illegal));

    always @(posedge clk) begin
        if (!rst_n) begin
            redirect_clear_valid <= 1'b0;
            stop_clear_valid <= 1'b0;
            trap_slowpath_pending <= 1'b0;
            slow_redirect_valid_r <= 1'b0;
            slow_redirect_pc_r <= 32'b0;
            slow_redirect_trace_is_redirect_r <= 1'b0;
        end else begin
            redirect_clear_valid <= redirect_flush_valid;
            stop_clear_valid <= stop_clear_set;
            slow_redirect_valid_r <= trap_redirect_request_valid;
            if (trap_redirect_request_valid) begin
                slow_redirect_pc_r <= trap_redirect_request_pc;
            end
            slow_redirect_trace_is_redirect_r <= trap_redirect_request_valid;

            if (slow_redirect_valid_r) begin
                trap_slowpath_pending <= 1'b0;
            end else if (slowpath_prepare_kill_valid) begin
                trap_slowpath_pending <= 1'b1;
            end
        end
    end

    assign rf_wdata = commit_token.wdata;
    assign rf_waddr = commit_token.rd;
    assign rf_wen = commit_token.side_effect_valid && commit_token.rf_wen;

    assign csr_wdata1 = ws_csr_wdata1;
    assign csr_waddr1 = ws_csr_waddr1;
    assign csr_wdata2 = ws_csr_wdata2;
    assign csr_waddr2 = ws_csr_waddr2;
    assign csr_wdata3 =
        commit_pkt_inst_addr_misaligned_trap ? commit_pkt_inst_addr_misaligned_tval :
        commit_pkt_mem_addr_misaligned_trap ? ws_aluout :
        commit_pkt_instr;
    assign csr_waddr3 = 12'h343;
    assign csr_wen3 =
        commit_pkt_inst_addr_misaligned_trap || commit_pkt_mem_addr_misaligned_trap ||
        commit_pkt_illegal_inst_trap;
    assign csr_wen_eff = commit_pkt_side_effect_valid ? ws_csr_wen : 2'b00;

    RegisterFile #(5, 32) rf(
        .clk(clk),
        .rst_n(rst_n),
        .raddr1(rf_raddr1),
        .rdata1(rf_rdata1),
        .raddr2(rf_raddr2),
        .rdata2(rf_rdata2),
        .wdata(rf_wdata),
        .waddr(rf_waddr),
        .wen(rf_wen)
    );

    CsrRegisterFile #(12, 32) csrf(
        .clk(clk),
        .rst_n(rst_n),
        .raddr1(csr_raddr),
        .rdata1(csr_rdata),
        .wdata1(csr_wdata1),
        .waddr1(csr_waddr1),
        .wdata2(csr_wdata2),
        .waddr2(csr_waddr2),
        .wdata3(csr_wdata3),
        .waddr3(csr_waddr3),
        .wen3(csr_wen3),
        .interrupt_trap_valid(interrupt_trap_valid),
        .interrupt_trap_cause(interrupt_trap_cause),
        .interrupt_trap_epc(interrupt_trap_epc),
        .wen(csr_wen_eff),
        .priv(csr_priv),
        .mstatus_value(csr_mstatus_value),
        .mtvec_value(csr_mtvec_value),
        .mie_value(csr_mie_value),
        .mip_value(csr_mip_value),
        .mideleg_value(csr_mideleg_value)
    );

    if_stage #(
        .BTB_ENTRIES(128)
    ) u_if_stage(
        .clk(clk),
        .rst_n(rst_n),
        .ds_allowin(ds_allowin),
        .stop_fetch(stop_fetch),
        .redirect_flush(redirect_flush_valid),
        .stop_clear(stop_clear_valid),
        .flush_pc(redirect_token_target_pc),
        .bpu_update_valid(bpu_update_token.valid),
        .bpu_update_pc(bpu_update_token.pc),
        .bpu_update_is_cond(bpu_update_token.is_cond),
        .bpu_update_taken(bpu_update_token.taken),
        .bpu_update_target(bpu_update_token.target_pc),
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_pc(fs_pc),
        .fs_instr(fs_instr),
        .fs_pred_taken(fs_pred_taken),
        .fs_pred_target(fs_pred_target),
        .if_stall(if_stall),
        .ibus_req_valid(ibus_req_valid_w),
        .ibus_req_ready(ibus_req_ready),
        .ibus_req_addr(ibus_req_addr_w),
        .ibus_resp_valid(ibus_resp_valid),
        .ibus_resp_ready(ibus_resp_ready_w),
        .ibus_resp_data(ibus_resp_data)
`ifdef NPC_BRANCH_STAT
        ,
        .flush_trace_is_redirect(redirect_token_trace_is_redirect),
        .fetch_req_trace_valid(branch_stat_fetch_req_valid),
        .fetch_req_trace_pc(branch_stat_fetch_req_pc),
        .fetch_accept_trace_valid(branch_stat_fetch_accept_valid),
        .fetch_accept_trace_pc(branch_stat_fetch_accept_pc),
        .fetch_accept_trace_instr(branch_stat_fetch_accept_instr),
        .fetch_drop_trace_valid(branch_stat_fetch_drop_valid),
        .fetch_drop_trace_redirect(branch_stat_fetch_drop_redirect),
        .fetch_drop_trace_pc(branch_stat_fetch_drop_pc),
        .fetch_drop_trace_instr(branch_stat_fetch_drop_instr)
`endif
    );

    id_stage u_id_stage(
        .clk(clk),
        .rst_n(rst_n),
        .flush(pipe_clear_valid),
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_pc(fs_pc),
        .fs_instr(fs_instr),
        .fs_pred_taken(fs_pred_taken),
        .fs_pred_target(fs_pred_target),
        .ds_allowin(ds_allowin),
        .es_allowin(es_allowin),
        .ds_to_es_valid(ds_to_es_valid),
        .rf_raddr1(rf_raddr1),
        .rf_rdata1(rf_rdata1),
        .rf_raddr2(rf_raddr2),
        .rf_rdata2(rf_rdata2),
        .csr_raddr(csr_raddr),
        .csr_rdata(csr_rdata),
        .csr_priv(csr_priv),
        .csr_mstatus_value(csr_mstatus_value),
        .es_valid(es_valid),
        .es_reg_wen(es_reg_wen),
        .es_rd(es_rd),
        .es_csr_wen(es_csr_wen),
        .es_csr_waddr1(es_csr_waddr1),
        .es_csr_waddr2(es_csr_waddr2),
        .ms_valid(ms_valid),
        .ms_reg_wen(ms_reg_wen),
        .ms_rd(ms_rd),
        .ms_csr_wen(ms_csr_wen),
        .ms_csr_waddr1(ms_csr_waddr1),
        .ms_csr_waddr2(ms_csr_waddr2),
        .hidden_mreq_valid(hidden_mreq_valid),
        .hidden_mreq_reg_wen(hidden_mreq_reg_wen),
        .hidden_mreq_rd(hidden_mreq_rd),
        .hidden_mreq_csr_wen(hidden_mreq_csr_wen),
        .hidden_mreq_csr_waddr1(hidden_mreq_csr_waddr1),
        .hidden_mreq_csr_waddr2(hidden_mreq_csr_waddr2),
        .ws_valid(ws_valid),
        .ws_rd(ws_rd),
        .ws_reg_wen(ws_reg_wen),
        .ws_csr_wen(ws_csr_wen),
        .ws_csr_waddr1(ws_csr_waddr1),
        .ws_csr_waddr2(ws_csr_waddr2),
        .es_result_bypassable(es_result_bypassable),
        .ms_fwd_valid(ms_fwd_valid),
        .ms_fwd_data(ms_fwd_data),
        .ds_pc(ds_pc),
        .ds_instr(ds_instr),
        .ds_rs1(ds_rs1),
        .ds_rs2(ds_rs2),
        .ds_src1(ds_src1),
        .ds_src2(ds_src2),
        .ds_src1_from_prev_ex(ds_src1_from_prev_ex),
        .ds_src2_from_prev_ex(ds_src2_from_prev_ex),
        .ds_src1_from_prev_wb(ds_src1_from_prev_wb),
        .ds_src2_from_prev_wb(ds_src2_from_prev_wb),
        .ds_pred_taken(ds_pred_taken),
        .ds_pred_target(ds_pred_target),
        .ds_imm(ds_imm),
        .ds_zimm(ds_zimm),
        .ds_scsr(ds_scsr),
        .ds_rd(ds_rd),
        .ds_reg_wen(ds_reg_wen),
        .ds_branch(ds_branch),
        .ds_datatoreg(ds_datatoreg),
        .ds_mem_wr(ds_mem_wr),
        .ds_mem_op(ds_mem_op),
        .ds_alu_a_src(ds_alu_a_src),
        .ds_alu_b_src(ds_alu_b_src),
        .ds_alu_ctr(ds_alu_ctr),
        .ds_csr_wen(ds_csr_wen),
        .ds_csr_waddr1(ds_csr_waddr1),
        .ds_csr_waddr2(ds_csr_waddr2),
        .ds_csr_wdata_src1(ds_csr_wdata_src1),
        .ds_csr_wdata_src2(ds_csr_wdata_src2),
        .ds_illegal(ds_illegal),
        .ds_is_ebreak(ds_is_ebreak),
        .ds_stop_fetch(ds_stop_fetch),
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
        .ds_stage_block(ds_stage_block),
        .ds_stage_block_reg_hazard(ds_stage_block_reg_hazard),
        .ds_stage_block_csr_hazard(ds_stage_block_csr_hazard),
`endif
`endif
`ifdef NPC_M_EXTENSION
        .ds_mdu_en(ds_mdu_en),
        .ds_mdu_op(ds_mdu_op)
`else
        .ds_mdu_en_dummy(ds_mdu_en_dummy),
        .ds_mdu_op_dummy(ds_mdu_op_dummy)
`endif
    );

    ex_stage u_ex_stage(
        .clk(clk),
        .rst_n(rst_n),
        .ds_to_es_valid(ds_to_es_fire),
        .es_allowin(es_allowin),
        .ms_allowin(ms_allowin),
        .es_to_ms_valid(es_to_ms_valid),
        .ds_pc(ds_pc),
        .ds_instr(ds_instr),
        .ds_src1(ds_src1),
        .ds_src2(ds_src2),
        .ds_src1_from_prev_ex(ds_src1_from_prev_ex),
        .ds_src2_from_prev_ex(ds_src2_from_prev_ex),
        .ds_src1_from_prev_wb(ds_src1_from_prev_wb),
        .ds_src2_from_prev_wb(ds_src2_from_prev_wb),
        .ds_pred_taken(ds_pred_taken),
        .ds_pred_target(ds_pred_target),
        .ws_rf_wdata(ws_rf_wdata),
        .ds_imm(ds_imm),
        .ds_zimm(ds_zimm),
        .ds_scsr(ds_scsr),
        .ds_rd(ds_rd),
        .ds_reg_wen(ds_reg_wen),
        .ds_branch(ds_branch),
        .ds_datatoreg(ds_datatoreg),
        .ds_mem_wr(ds_mem_wr),
        .ds_mem_op(ds_mem_op),
        .ds_alu_a_src(ds_alu_a_src),
        .ds_alu_b_src(ds_alu_b_src),
        .ds_alu_ctr(ds_alu_ctr),
        .ds_csr_wen(ds_csr_wen),
        .ds_csr_waddr1(ds_csr_waddr1),
        .ds_csr_waddr2(ds_csr_waddr2),
        .ds_csr_wdata_src1(ds_csr_wdata_src1),
        .ds_csr_wdata_src2(ds_csr_wdata_src2),
        .ds_illegal(ds_illegal),
        .ds_is_ebreak(ds_is_ebreak),
`ifdef NPC_M_EXTENSION
        .ds_mdu_en(ds_mdu_en),
        .ds_mdu_op(ds_mdu_op),
`endif
        .es_valid(es_valid),
        .es_result_bypassable(es_result_bypassable),
        .es_pc(es_pc),
        .es_instr(es_instr),
        .es_nextpc(es_nextpc),
        .es_rd(es_rd),
        .es_reg_wen(es_reg_wen),
        .es_datatoreg(es_datatoreg),
        .es_mem_wr(es_mem_wr),
        .es_mem_op(es_mem_op),
        .es_aluout(es_aluout),
        .es_mem_wdata(es_mem_wdata),
        .es_csr_read_data(es_csr_read_data),
        .es_csr_wen(es_csr_wen),
        .es_csr_waddr1(es_csr_waddr1),
        .es_csr_waddr2(es_csr_waddr2),
        .es_csr_wdata1(es_csr_wdata1),
        .es_csr_wdata2(es_csr_wdata2),
        .es_illegal(es_illegal),
        .es_is_ebreak(es_is_ebreak),
        .es_branch(es_branch),
        .es_src1_value(es_src1_value),
        .es_mem_fwd_dep(es_mem_fwd_dep),
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
        .es_stage_block(es_stage_block),
        .es_stage_block_mdu_wait(es_stage_block_mdu_wait),
        .es_stage_block_redirect_wait(es_stage_block_redirect_wait),
`endif
`endif
        .flush_valid(ex_flush_valid),
        .flush_pc(ex_flush_pc),
        .mispredict_flush_valid(ex_mispredict_flush_valid),
        .mispredict_flush_pc(ex_mispredict_flush_pc),
        .branch_taken_actual(ex_branch_taken_actual)
    );

    mem_stage u_mem_stage(
        .clk(clk),
        .rst_n(rst_n),
        .es_to_ms_valid(es_to_ms_valid),
        .ms_allowin(ms_allowin),
        .ws_allowin(ws_allowin),
        .ms_to_ws_valid(ms_to_ws_valid),
        .es_pc(es_pc),
        .es_instr(es_instr),
        .es_nextpc(es_nextpc),
        .es_rd(es_rd),
        .es_reg_wen(es_reg_wen),
        .es_datatoreg(es_datatoreg),
        .es_mem_wr(es_mem_wr),
        .es_mem_op(es_mem_op),
        .es_aluout(es_aluout),
        .es_mem_wdata(es_mem_wdata),
        .es_mem_fwd_dep(es_mem_fwd_dep),
        .es_csr_read_data(es_csr_read_data),
        .es_csr_wen(es_csr_wen),
        .es_csr_waddr1(es_csr_waddr1),
        .es_csr_waddr2(es_csr_waddr2),
        .es_csr_wdata1(es_csr_wdata1),
        .es_csr_wdata2(es_csr_wdata2),
        .es_illegal(es_illegal),
        .es_is_ebreak(es_is_ebreak),
        .es_branch(es_branch),
        .es_src1_value(es_src1_value),
        .ms_valid(ms_valid),
        .ms_pc(ms_pc),
        .ms_instr(ms_instr),
        .ms_nextpc(ms_nextpc),
        .ms_rd(ms_rd),
        .ms_reg_wen(ms_reg_wen),
        .ms_datatoreg(ms_datatoreg),
        .ms_mem_op(ms_mem_op),
        .ms_aluout(ms_aluout),
        .ms_mem_rdata(ms_mem_rdata),
        .ms_csr_read_data(ms_csr_read_data),
        .ms_csr_wen(ms_csr_wen),
        .ms_csr_waddr1(ms_csr_waddr1),
        .ms_csr_waddr2(ms_csr_waddr2),
        .ms_csr_wdata1(ms_csr_wdata1),
        .ms_csr_wdata2(ms_csr_wdata2),
        .ms_illegal(ms_illegal),
        .ms_is_ebreak(ms_is_ebreak),
        .ms_branch(ms_branch),
        .ms_src1_value(ms_src1_value),
        .ms_slowpath_prepare_kill_valid(ms_slowpath_prepare_kill_valid),
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
        .ms_stage_block(ms_stage_block),
        .ms_stage_block_req_phase(ms_stage_block_req_phase),
        .ms_stage_block_resp_phase(ms_stage_block_resp_phase),
        .fast_req_fire_trace(ms_fast_req_fire_trace),
        .slow_req_fire_trace(ms_slow_req_fire_trace),
        .slow_req_fwd_dep_fire_trace(ms_slow_req_fwd_dep_fire_trace),
        .slow_req_nonfwd_fire_trace(ms_slow_req_nonfwd_fire_trace),
`endif
`endif
        .hidden_mreq_valid(hidden_mreq_valid),
        .hidden_mreq_reg_wen(hidden_mreq_reg_wen),
        .hidden_mreq_rd(hidden_mreq_rd),
        .hidden_mreq_csr_wen(hidden_mreq_csr_wen),
        .hidden_mreq_csr_waddr1(hidden_mreq_csr_waddr1),
        .hidden_mreq_csr_waddr2(hidden_mreq_csr_waddr2),
        .dbus_req_valid(dbus_req_valid),
        .dbus_req_ready(dbus_req_ready),
        .dbus_req_write(dbus_req_write),
        .dbus_req_addr(dbus_req_addr),
        .dbus_req_wdata(dbus_req_wdata),
        .dbus_req_wstrb(dbus_req_wstrb),
        .dbus_req_len(dbus_req_len),
        .dbus_resp_valid(dbus_resp_valid),
        .dbus_resp_ready(dbus_resp_ready),
        .dbus_resp_data(dbus_resp_data)
    );

    wb_stage u_wb_stage(
        .clk(clk),
        .rst_n(rst_n),
        .ms_to_ws_valid(ms_to_ws_valid),
        .ws_allowin(ws_allowin),
        .ms_pc(ms_pc),
        .ms_instr(ms_instr),
        .ms_nextpc(ms_nextpc),
        .ms_rd(ms_rd),
        .ms_reg_wen(ms_reg_wen),
        .ms_datatoreg(ms_datatoreg),
        .ms_mem_op(ms_mem_op),
        .ms_aluout(ms_aluout),
        .ms_mem_rdata(ms_mem_rdata),
        .ms_csr_read_data(ms_csr_read_data),
        .ms_csr_wen(ms_csr_wen),
        .ms_csr_waddr1(ms_csr_waddr1),
        .ms_csr_waddr2(ms_csr_waddr2),
        .ms_csr_wdata1(ms_csr_wdata1),
        .ms_csr_wdata2(ms_csr_wdata2),
        .ms_illegal(ms_illegal),
        .ms_is_ebreak(ms_is_ebreak),
        .ms_branch(ms_branch),
        .ms_src1_value(ms_src1_value),
        .ws_valid(ws_valid),
        .ws_pc(ws_pc),
        .ws_instr(ws_instr),
        .ws_nextpc(ws_nextpc),
        .ws_rd(ws_rd),
        .ws_reg_wen(ws_reg_wen),
        .ws_aluout(ws_aluout),
        .ws_rf_wdata(ws_rf_wdata),
        .ws_csr_wen(ws_csr_wen),
        .ws_csr_waddr1(ws_csr_waddr1),
        .ws_csr_waddr2(ws_csr_waddr2),
        .ws_csr_wdata1(ws_csr_wdata1),
        .ws_csr_wdata2(ws_csr_wdata2),
        .ws_illegal(ws_illegal),
        .ws_is_ebreak(ws_is_ebreak),
        .ws_branch(ws_branch),
        .ws_src1_value(ws_src1_value)
    );

`ifdef NPC_USE_DPI
`ifdef NPC_BRANCH_STAT
    BranchStat u_branch_stat(
        .clk(clk),
        .rst_n(rst_n),
        .fetch_req_valid(branch_stat_fetch_req_valid),
        .fetch_req_pc(branch_stat_fetch_req_pc),
        .fetch_accept_valid(branch_stat_fetch_accept_valid),
        .fetch_accept_pc(branch_stat_fetch_accept_pc),
        .fetch_accept_instr(branch_stat_fetch_accept_instr),
        .fetch_drop_valid(branch_stat_fetch_drop_valid),
        .fetch_drop_redirect(branch_stat_fetch_drop_redirect),
        .fetch_drop_pc(branch_stat_fetch_drop_pc),
        .fetch_drop_instr(branch_stat_fetch_drop_instr),
        .branch_resolve_valid(branch_stat_resolve_valid),
        .branch_kind(es_branch),
        .branch_pc(es_pc),
        .branch_instr(es_instr),
        .branch_nextpc(ex_flush_valid ? ex_flush_pc : es_nextpc),
        .branch_redirect(ex_flush_valid),
        .stop_clear_valid(stop_clear_valid),
        .stop_clear_pc(ds_pc),
        .stop_clear_instr(ds_instr),
        .commit_valid(commit_pkt_valid),
        .commit_pc(commit_pkt_pc),
        .commit_instr(commit_pkt_instr),
        .commit_nextpc(commit_pkt_nextpc),
        .commit_is_ebreak(ws_is_ebreak),
        .commit_illegal(ws_illegal),
        .ibus_req_valid(ibus_req_valid_w),
        .ibus_req_ready(ibus_req_ready),
        .ibus_resp_valid(ibus_resp_valid),
        .ibus_resp_ready(ibus_resp_ready_w),
        .dbus_req_valid(dbus_req_valid),
        .dbus_req_ready(dbus_req_ready),
        .dbus_resp_valid(dbus_resp_valid),
        .dbus_resp_ready(dbus_resp_ready)
    );
`endif
`endif

`ifdef NPC_USE_DPI
`ifdef NPC_INSTR_STAT
    InstrStat u_instr_stat(
        .clk(clk),
        .rst_n(rst_n),
        .commit_valid(commit_pkt_valid),
        .commit_instr(commit_pkt_instr),
        .commit_is_ebreak(ws_is_ebreak),
        .commit_illegal(ws_illegal)
    );
`endif
`endif

`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
    CacheStat #(
        .ICACHE_MISS_PENALTY(ICACHE_MISS_PENALTY),
        .DCACHE_MISS_PENALTY(DCACHE_MISS_PENALTY)
    ) u_cache_stat(
        .clk(clk),
        .rst_n(rst_n),
        .commit_valid(commit_pkt_valid),
        .commit_is_ebreak(ws_is_ebreak),
        .commit_illegal(ws_illegal),
        .icache_access(icache_stat_access),
        .icache_hit(icache_stat_hit),
        .icache_miss(icache_stat_miss),
        .icache_refill_req(icache_stat_refill_req),
        .icache_refill_resp(icache_stat_refill_resp),
        .icache_refill_bypass(icache_stat_refill_bypass),
        .dcache_access(dcache_stat_access),
        .dcache_load_access(dcache_stat_load_access),
        .dcache_store_access(dcache_stat_store_access),
        .dcache_load_hit(dcache_stat_load_hit),
        .dcache_load_miss(dcache_stat_load_miss),
        .dcache_store_hit(dcache_stat_store_hit),
        .dcache_store_miss(dcache_stat_store_miss),
        .dcache_refill_req(dcache_stat_refill_req),
        .dcache_refill_resp(dcache_stat_refill_resp),
        .dcache_write_req(dcache_stat_write_req),
        .dcache_write_resp(dcache_stat_write_resp),
        .dcache_refill_ld_bypass(dcache_stat_refill_ld_bypass),
        .dcache_refill_store_merge(dcache_stat_refill_store_merge),
        .ibus_req_valid(ibus_req_valid_w),
        .ibus_req_ready(ibus_req_ready),
        .ibus_resp_valid(ibus_resp_valid),
        .ibus_resp_ready(ibus_resp_ready_w),
        .dbus_req_valid(dbus_req_valid),
        .dbus_req_ready(dbus_req_ready),
        .dbus_resp_valid(dbus_resp_valid),
        .dbus_resp_ready(dbus_resp_ready)
    );
`endif
`endif

`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    PipeStat u_pipe_stat(
        .clk(clk),
        .rst_n(rst_n),
        .fs_to_ds_valid(fs_to_ds_valid),
        .if_stall(if_stall),
        .ds_allowin(ds_allowin),
        .ds_to_es_valid(ds_to_es_valid),
        .es_allowin(es_allowin),
        .es_to_ms_valid(es_to_ms_valid),
        .ms_allowin(ms_allowin),
        .ms_to_ws_valid(ms_to_ws_valid),
        .ws_allowin(ws_allowin),
        .id_stage_block(ds_stage_block),
        .id_stage_block_reg_hazard(ds_stage_block_reg_hazard),
        .id_stage_block_csr_hazard(ds_stage_block_csr_hazard),
        .ex_stage_block(es_stage_block),
        .ex_stage_block_mdu_wait(es_stage_block_mdu_wait),
        .ex_stage_block_redirect_wait(es_stage_block_redirect_wait),
        .ms_stage_block(ms_stage_block),
        .ms_stage_block_req_phase(ms_stage_block_req_phase),
        .ms_stage_block_resp_phase(ms_stage_block_resp_phase),
        .es_mem_wr(es_mem_wr),
        .es_mem_fast_block(es_mem_fwd_dep),
        .ms_fast_req_fire(ms_fast_req_fire_trace),
        .ms_slow_req_fire(ms_slow_req_fire_trace),
        .ms_slow_req_fwd_dep_fire(ms_slow_req_fwd_dep_fire_trace),
        .ms_slow_req_nonfwd_fire(ms_slow_req_nonfwd_fire_trace),
        .commit_valid(commit_pkt_valid),
        .commit_is_ebreak(ws_is_ebreak),
        .commit_illegal(ws_illegal)
    );
`endif
`endif

    ICache #(
        .LINE_BYTES(ICACHE_LINE_BYTES),
        .LINE_COUNT(ICACHE_LINE_COUNT)
    ) u_icache (
        .clk(clk),
        .rst_n(rst_n),
        .flush(commit_pkt_is_fence_i),
        .cpu_req_valid(ibus_req_valid_w),
        .cpu_req_ready(ibus_req_ready),
        .cpu_req_addr(ibus_req_addr_w),
        .cpu_resp_valid(ibus_resp_valid),
        .cpu_resp_ready(ibus_resp_ready_w),
        .cpu_resp_rdata(ibus_resp_data),
        .lower_req_valid(ibus_mem_req_valid),
        .lower_req_ready(ibus_mem_req_ready),
        .lower_req_write(ibus_mem_req_write),
        .lower_req_addr(ibus_mem_req_addr),
        .lower_req_wdata(ibus_mem_req_wdata),
        .lower_req_wstrb(ibus_mem_req_wstrb),
        .lower_req_len(ibus_mem_req_len),
        .lower_resp_valid(ibus_mem_resp_valid),
        .lower_resp_ready(ibus_mem_resp_ready),
        .lower_resp_rdata(ibus_mem_resp_data)
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
        ,
        .stat_access(icache_stat_access),
        .stat_hit(icache_stat_hit),
        .stat_miss(icache_stat_miss),
        .stat_refill_req(icache_stat_refill_req),
        .stat_refill_resp(icache_stat_refill_resp),
        .stat_refill_bypass(icache_stat_refill_bypass)
`endif
`endif
    );

    DCache #(
        .LINE_BYTES(DCACHE_LINE_BYTES),
        .LINE_COUNT(DCACHE_LINE_COUNT)
    ) u_dcache (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_req_valid(dbus_req_valid),
        .cpu_req_ready(dbus_req_ready),
        .cpu_req_write(dbus_req_write),
        .cpu_req_addr(dbus_req_addr),
        .cpu_req_wdata(dbus_req_wdata),
        .cpu_req_wstrb(dbus_req_wstrb),
        .cpu_req_len(dbus_req_len),
        .cpu_resp_valid(dbus_resp_valid),
        .cpu_resp_ready(dbus_resp_ready),
        .cpu_resp_rdata(dbus_resp_data),
        .lower_req_valid(dbus_mem_req_valid),
        .lower_req_ready(dbus_mem_req_ready),
        .lower_req_write(dbus_mem_req_write),
        .lower_req_addr(dbus_mem_req_addr),
        .lower_req_wdata(dbus_mem_req_wdata),
        .lower_req_wstrb(dbus_mem_req_wstrb),
        .lower_req_len(dbus_mem_req_len),
        .lower_resp_valid(dbus_mem_resp_valid),
        .lower_resp_ready(dbus_mem_resp_ready),
        .lower_resp_rdata(dbus_mem_resp_data)
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
        ,
        .stat_access(dcache_stat_access),
        .stat_load_access(dcache_stat_load_access),
        .stat_store_access(dcache_stat_store_access),
        .stat_load_hit(dcache_stat_load_hit),
        .stat_load_miss(dcache_stat_load_miss),
        .stat_store_hit(dcache_stat_store_hit),
        .stat_store_miss(dcache_stat_store_miss),
        .stat_refill_req(dcache_stat_refill_req),
        .stat_refill_resp(dcache_stat_refill_resp),
        .stat_write_req(dcache_stat_write_req),
        .stat_write_resp(dcache_stat_write_resp),
        .stat_refill_ld_bypass(dcache_stat_refill_ld_bypass),
        .stat_refill_store_merge(dcache_stat_refill_store_merge)
`endif
`endif
    );

`ifdef NPC_USE_DPI
    assign ibus_axi_awaddr = 32'b0;
    assign ibus_axi_awlen = 8'b0;
    assign ibus_axi_awsize = 3'b0;
    assign ibus_axi_awburst = 2'b0;
    assign ibus_axi_awvalid = 1'b0;
    assign ibus_axi_wdata = 32'b0;
    assign ibus_axi_wstrb = 4'b0;
    assign ibus_axi_wlast = 1'b0;
    assign ibus_axi_wvalid = 1'b0;
    assign ibus_axi_bready = 1'b0;
    assign ibus_axi_araddr = 32'b0;
    assign ibus_axi_arlen = 8'b0;
    assign ibus_axi_arsize = 3'b0;
    assign ibus_axi_arburst = 2'b0;
    assign ibus_axi_arvalid = 1'b0;
    assign ibus_axi_rready = 1'b0;

    assign dbus_axi_awaddr = 32'b0;
    assign dbus_axi_awlen = 8'b0;
    assign dbus_axi_awsize = 3'b0;
    assign dbus_axi_awburst = 2'b0;
    assign dbus_axi_awvalid = 1'b0;
    assign dbus_axi_wdata = 32'b0;
    assign dbus_axi_wstrb = 4'b0;
    assign dbus_axi_wlast = 1'b0;
    assign dbus_axi_wvalid = 1'b0;
    assign dbus_axi_bready = 1'b0;
    assign dbus_axi_araddr = 32'b0;
    assign dbus_axi_arlen = 8'b0;
    assign dbus_axi_arsize = 3'b0;
    assign dbus_axi_arburst = 2'b0;
    assign dbus_axi_arvalid = 1'b0;
    assign dbus_axi_rready = 1'b0;

    SimPmemBridge #(
        .CHANNEL(0),
        .BATCH_WORDS(ICACHE_LINE_WORDS),
        .MEM_LATENCY(DPI_MEM_LATENCY)
    ) ibus_bridge(
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(ibus_mem_req_valid),
        .req_ready(ibus_mem_req_ready),
        .req_write(ibus_mem_req_write),
        .req_addr(ibus_mem_req_addr),
        .req_wdata(ibus_mem_req_wdata),
        .req_wstrb(ibus_mem_req_wstrb),
        .req_len(ibus_mem_req_len),
        .resp_valid(ibus_mem_resp_valid),
        .resp_ready(ibus_mem_resp_ready),
        .resp_rdata(ibus_mem_resp_data)
    );

    SimPmemBridge #(
        .CHANNEL(1),
        .BATCH_WORDS(DCACHE_LINE_WORDS),
        .MEM_LATENCY(DPI_MEM_LATENCY)
    ) dbus_bridge(
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(dbus_mem_req_valid),
        .req_ready(dbus_mem_req_ready),
        .req_write(dbus_mem_req_write),
        .req_addr(dbus_mem_req_addr),
        .req_wdata(dbus_mem_req_wdata),
        .req_wstrb(dbus_mem_req_wstrb),
        .req_len(dbus_mem_req_len),
        .resp_valid(dbus_mem_resp_valid),
        .resp_ready(dbus_mem_resp_ready),
        .resp_rdata(dbus_mem_resp_data)
    );
`else
    AxiPmemBridge #(
        .BATCH_WORDS(ICACHE_LINE_WORDS)
    ) ibus_bridge(
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(ibus_mem_req_valid),
        .req_ready(ibus_mem_req_ready),
        .req_write(ibus_mem_req_write),
        .req_addr(ibus_mem_req_addr),
        .req_wdata(ibus_mem_req_wdata),
        .req_wstrb(ibus_mem_req_wstrb),
        .req_len(ibus_mem_req_len),
        .resp_valid(ibus_mem_resp_valid),
        .resp_ready(ibus_mem_resp_ready),
        .resp_rdata(ibus_mem_resp_data),
        .m_axi_awaddr(ibus_axi_awaddr),
        .m_axi_awlen(ibus_axi_awlen),
        .m_axi_awsize(ibus_axi_awsize),
        .m_axi_awburst(ibus_axi_awburst),
        .m_axi_awvalid(ibus_axi_awvalid),
        .m_axi_awready(ibus_axi_awready),
        .m_axi_wdata(ibus_axi_wdata),
        .m_axi_wstrb(ibus_axi_wstrb),
        .m_axi_wlast(ibus_axi_wlast),
        .m_axi_wvalid(ibus_axi_wvalid),
        .m_axi_wready(ibus_axi_wready),
        .m_axi_bresp(ibus_axi_bresp),
        .m_axi_bvalid(ibus_axi_bvalid),
        .m_axi_bready(ibus_axi_bready),
        .m_axi_araddr(ibus_axi_araddr),
        .m_axi_arlen(ibus_axi_arlen),
        .m_axi_arsize(ibus_axi_arsize),
        .m_axi_arburst(ibus_axi_arburst),
        .m_axi_arvalid(ibus_axi_arvalid),
        .m_axi_arready(ibus_axi_arready),
        .m_axi_rdata(ibus_axi_rdata),
        .m_axi_rresp(ibus_axi_rresp),
        .m_axi_rvalid(ibus_axi_rvalid),
        .m_axi_rready(ibus_axi_rready),
        .m_axi_rlast(ibus_axi_rlast)
    );

    AxiPmemBridge #(
        .BATCH_WORDS(DCACHE_LINE_WORDS)
    ) dbus_bridge(
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(dbus_mem_req_valid),
        .req_ready(dbus_mem_req_ready),
        .req_write(dbus_mem_req_write),
        .req_addr(dbus_mem_req_addr),
        .req_wdata(dbus_mem_req_wdata),
        .req_wstrb(dbus_mem_req_wstrb),
        .req_len(dbus_mem_req_len),
        .resp_valid(dbus_mem_resp_valid),
        .resp_ready(dbus_mem_resp_ready),
        .resp_rdata(dbus_mem_resp_data),
        .m_axi_awaddr(dbus_axi_awaddr),
        .m_axi_awlen(dbus_axi_awlen),
        .m_axi_awsize(dbus_axi_awsize),
        .m_axi_awburst(dbus_axi_awburst),
        .m_axi_awvalid(dbus_axi_awvalid),
        .m_axi_awready(dbus_axi_awready),
        .m_axi_wdata(dbus_axi_wdata),
        .m_axi_wstrb(dbus_axi_wstrb),
        .m_axi_wlast(dbus_axi_wlast),
        .m_axi_wvalid(dbus_axi_wvalid),
        .m_axi_wready(dbus_axi_wready),
        .m_axi_bresp(dbus_axi_bresp),
        .m_axi_bvalid(dbus_axi_bvalid),
        .m_axi_bready(dbus_axi_bready),
        .m_axi_araddr(dbus_axi_araddr),
        .m_axi_arlen(dbus_axi_arlen),
        .m_axi_arsize(dbus_axi_arsize),
        .m_axi_arburst(dbus_axi_arburst),
        .m_axi_arvalid(dbus_axi_arvalid),
        .m_axi_arready(dbus_axi_arready),
        .m_axi_rdata(dbus_axi_rdata),
        .m_axi_rresp(dbus_axi_rresp),
        .m_axi_rvalid(dbus_axi_rvalid),
        .m_axi_rready(dbus_axi_rready),
        .m_axi_rlast(dbus_axi_rlast)
    );
`endif

`ifndef NPC_USE_DPI
    // FPGA path has no DPI ebreak() to stop simulation. Latch a halted state
    // once ebreak/illegal reaches WB so IF stays stopped after the pipeline
    // drains and the final commit PC remains observable by ILA.
    always @(posedge clk) begin
        if (!rst_n) begin
            cpu_halted <= 1'b0;
        end else if (ws_valid && (ws_is_ebreak || ws_illegal)) begin
            cpu_halted <= 1'b1;
        end
    end
`endif

    always @(posedge clk) begin
        if (!rst_n) begin
            commit_valid <= 1'b0;
            commit_pc <= 32'b0;
            commit_instr <= 32'b0;
            commit_nextpc <= 32'b0;
            PC <= RESET_VECTOR;
            instr <= 32'b0;
            NextPC <= RESET_VECTOR;
            arch_pc <= RESET_VECTOR;
        end else begin
            commit_valid <= 1'b0;

            if (commit_token.valid) begin
                commit_valid <= 1'b1;
                commit_pc <= commit_token.pc;
                commit_instr <= commit_token.instr;
                commit_nextpc <= commit_token.nextpc;

                PC <= commit_token.pc;
                instr <= commit_token.instr;
                NextPC <= commit_token.nextpc;
                arch_pc <= (ws_is_ebreak || ws_illegal) ? commit_token.pc : commit_token.nextpc;

                if (ws_branch == BRANCH_J) begin
`ifdef NPC_USE_DPI
                    ftrace_print(1'b1, {27'b0, ws_instr[11:7]}, 1'b0, ws_src1_value, ws_pc, ws_nextpc);
`endif
                end else if (ws_branch == BRANCH_JR) begin
`ifdef NPC_USE_DPI
                    ftrace_print(1'b0, {27'b0, ws_instr[11:7]}, 1'b1, ws_src1_value, ws_pc, ws_nextpc);
`endif
                end

                if (ws_is_ebreak) begin
`ifdef NPC_USE_DPI
                    ebreak(ws_pc, ws_instr);
`endif
                end else if (ws_illegal) begin
`ifdef NPC_USE_DPI
`ifdef NPC_RVTEST_TRAP_STUB
                    npc_trap_stub(ws_pc, ws_instr, 32'd2, ws_instr);
`else
                    inster_undefine(ws_pc, ws_instr);
`endif
`endif
                end
            end

`ifdef NPC_USE_DPI
            if (dbus_req_valid && dbus_req_ready) begin
                ideal_cache_record_dcache(dbus_req_addr, {29'b0, dbus_req_len}, {31'b0, dbus_req_write});
                if (dbus_req_write) begin
                    rvtest_check_store(dbus_req_addr, {29'b0, dbus_req_len}, dbus_req_wdata);
                end
            end
`endif
        end
    end
endmodule
