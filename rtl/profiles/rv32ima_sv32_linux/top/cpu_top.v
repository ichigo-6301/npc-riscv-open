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
import "DPI-C" function bit semihosting_ebreak_match (
    input int unsigned pc
);
import "DPI-C" function void inster_undefine (
    input int unsigned pc,
    input int unsigned instr
);
`ifdef NPC_DPI_CSR_UNDEFINE
import "DPI-C" function void csr_undefine (
    input int unsigned pc,
    input int unsigned csr_idx,
    input int unsigned instr
);
`endif
import "DPI-C" function void ideal_cache_record_dcache (
    input int unsigned addr,
    input int len,
    input int is_write
);
`endif

module cpu_top(
    input clk,
    input rst_n,
    output reg commit_valid,
    output reg [31:0] commit_pc,
    output reg [31:0] commit_instr,
    output reg [31:0] commit_nextpc,
    output reg [31:0] commit_src1_value,
    output reg commit_async_irq,
    output reg commit_sync_exception,

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
    // Post-frontend wrapper ownership map:
    // cpu_top remains the integration shell for global reset/clock/simulation
    // policy, trap/CSR/privilege ownership, redirect/fence priority, top-level
    // debug/DPI export, and external memory glue. Wrapper instances own
    // structural clusters only and keep policy-bearing sideband explicit.
`ifdef NPC_RESET_VECTOR
    localparam [31:0] RESET_VECTOR = `NPC_RESET_VECTOR;
`else
    localparam [31:0] RESET_VECTOR = 32'h80000000;
`endif
`ifdef NPC_BTB_ENTRIES
    localparam integer BPU_BTB_ENTRIES = `NPC_BTB_ENTRIES;
`else
    localparam integer BPU_BTB_ENTRIES = 128;
`endif
`ifdef NPC_BHT_ENTRIES
    localparam integer BPU_BHT_ENTRIES = `NPC_BHT_ENTRIES;
`else
    localparam integer BPU_BHT_ENTRIES = 128;
`endif
`ifdef NPC_BHR_BITS
    localparam integer BPU_BHR_BITS = `NPC_BHR_BITS;
`else
    localparam integer BPU_BHR_BITS = 8;
`endif
`ifdef NPC_GSHARE_ENABLE
    localparam BPU_GSHARE_ENABLE = 1'b1;
`else
    localparam BPU_GSHARE_ENABLE = 1'b0;
`endif
    localparam [2:0] BRANCH_DEFAULT = 3'b000;
    localparam [2:0] BRANCH_J = 3'b001;
    localparam [2:0] BRANCH_JR = 3'b010;
    localparam integer ICACHE_LINE_BYTES = 64;
    localparam integer ICACHE_LINE_COUNT = 64;
    localparam integer DCACHE_LINE_BYTES = 64;
    localparam integer DCACHE_LINE_COUNT = 64;
`ifdef NPC_DPI_MEM_LATENCY
    localparam integer DPI_MEM_LATENCY = `NPC_DPI_MEM_LATENCY;
`else
    localparam integer DPI_MEM_LATENCY = 2;
`endif
`ifdef NPC_TIMER_CLK_HZ
    localparam integer TIMER_CLK_HZ = `NPC_TIMER_CLK_HZ;
`else
    localparam integer TIMER_CLK_HZ = 100000000;
`endif
`ifdef NPC_TIMEBASE_HZ
    localparam integer TIMEBASE_HZ = `NPC_TIMEBASE_HZ;
`else
    localparam integer TIMEBASE_HZ = 1000000;
`endif
    localparam integer ICACHE_LINE_WORDS = ICACHE_LINE_BYTES / 4;
    localparam integer DCACHE_LINE_WORDS = DCACHE_LINE_BYTES / 4;
    localparam integer ICACHE_MISS_PENALTY = DPI_MEM_LATENCY + ICACHE_LINE_WORDS;
    localparam integer DCACHE_MISS_PENALTY = DPI_MEM_LATENCY + DCACHE_LINE_WORDS;
    localparam [4:0] ICACHE_LINE_BEATS =
        (ICACHE_LINE_WORDS == 16) ? 5'd16 :
        (ICACHE_LINE_WORDS == 8)  ? 5'd8  :
        (ICACHE_LINE_WORDS == 4)  ? 5'd4  :
        (ICACHE_LINE_WORDS == 2)  ? 5'd2  :
        5'd1;

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
    wire [1:0] csr_wen_eff;
    wire csr_raddr_illegal;
    wire csr_waddr1_illegal;
    wire csr_waddr2_illegal;

    wire fs_to_ds_valid /* verilator public_flat */;
    wire if_stall;
    wire [31:0] fs_pc /* verilator public_flat */;
    wire [31:0] fs_instr /* verilator public_flat */;
    wire fs_exc_valid;
    wire [31:0] fs_exc_cause;
    wire [31:0] fs_exc_tval;
    wire fs_pred_taken;
    wire [31:0] fs_pred_target;
    wire fs_pred_btb_hit;
    wire fs_pred_btb_is_cond;
    wire [1:0] fs_pred_bht_state;
    wire [31:0] fs_pred_pht_idx;

    wire ds_allowin /* verilator public_flat */;
    wire ds_to_es_valid /* verilator public_flat */;
    wire ds_to_es_fire;
    wire [31:0] ds_pc;
    wire [31:0] ds_instr;
    wire ds_exc_valid;
    wire [31:0] ds_exc_cause;
    wire [31:0] ds_exc_tval;
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
    wire ds_pred_btb_hit;
    wire ds_pred_btb_is_cond;
    wire [1:0] ds_pred_bht_state;
    wire [31:0] ds_pred_pht_idx;
    wire [31:0] ds_imm;
    wire [31:0] ds_zimm;
    wire [31:0] ds_scsr;
    wire [4:0] ds_rd;
    wire ds_reg_wen;
    wire [2:0] ds_branch;
    wire [1:0] ds_datatoreg;
    wire [1:0] ds_mem_wr;
    wire [2:0] ds_mem_op;
    wire ds_atomic_en;
    wire [3:0] ds_atomic_op;
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
    wire ds_stage_block_load_use;
    wire ds_stage_block_ex_raw;
    wire ds_stage_block_ms_raw;
    wire ds_stage_block_hidden_raw;
    wire ds_stat_uses_rs1;
    wire ds_stat_uses_rs2;
    wire ds_stat_rs1_match_es;
    wire ds_stat_rs1_match_ms;
    wire ds_stat_rs1_match_hidden;
    wire ds_stat_rs1_match_ws;
    wire ds_stat_rs2_match_es;
    wire ds_stat_rs2_match_ms;
    wire ds_stat_rs2_match_hidden;
    wire ds_stat_rs2_match_ws;
    wire ds_stat_csr_counter_hazard;
    wire ds_stat_rs1_ex_alu_fwd;
    wire ds_stat_rs2_ex_alu_fwd;
    wire ds_stat_fwd_load_block;
    wire ds_stat_fwd_csr_block;
    wire ds_stat_fwd_kill_block;
`else
    wire ds_stage_block = 1'b0;
    wire ds_stage_block_reg_hazard = 1'b0;
    wire ds_stage_block_csr_hazard = 1'b0;
    wire ds_stage_block_load_use = 1'b0;
    wire ds_stage_block_ex_raw = 1'b0;
    wire ds_stage_block_ms_raw = 1'b0;
    wire ds_stage_block_hidden_raw = 1'b0;
    wire ds_stat_uses_rs1 = 1'b0;
    wire ds_stat_uses_rs2 = 1'b0;
    wire ds_stat_rs1_match_es = 1'b0;
    wire ds_stat_rs1_match_ms = 1'b0;
    wire ds_stat_rs1_match_hidden = 1'b0;
    wire ds_stat_rs1_match_ws = 1'b0;
    wire ds_stat_rs2_match_es = 1'b0;
    wire ds_stat_rs2_match_ms = 1'b0;
    wire ds_stat_rs2_match_hidden = 1'b0;
    wire ds_stat_rs2_match_ws = 1'b0;
    wire ds_stat_csr_counter_hazard = 1'b0;
    wire ds_stat_rs1_ex_alu_fwd = 1'b0;
    wire ds_stat_rs2_ex_alu_fwd = 1'b0;
    wire ds_stat_fwd_load_block = 1'b0;
    wire ds_stat_fwd_csr_block = 1'b0;
    wire ds_stat_fwd_kill_block = 1'b0;
`endif
`endif
`ifdef NPC_M_EXTENSION
    wire ds_mdu_en;
    wire [2:0] ds_mdu_op;
`else
    wire ds_mdu_en_dummy;
    wire [2:0] ds_mdu_op_dummy;
`endif

    wire es_allowin /* verilator public_flat */;
    wire es_to_ms_valid /* verilator public_flat */;
    wire es_valid /* verilator public_flat */;
    wire es_result_bypassable;
    wire [31:0] es_pc /* verilator public_flat */;
    wire [31:0] es_instr /* verilator public_flat */;
    wire [31:0] es_nextpc /* verilator public_flat */;
    wire [4:0] es_rd;
    wire es_reg_wen;
    wire [1:0] es_datatoreg;
    wire [1:0] es_mem_wr;
    wire [2:0] es_mem_op;
    wire es_atomic_en;
    wire [3:0] es_atomic_op;
    wire [31:0] es_aluout;
    wire [31:0] es_mem_wdata;
    wire [31:0] es_csr_read_data;
    wire [1:0] es_csr_wen;
    wire [11:0] es_csr_waddr1;
    wire [11:0] es_csr_waddr2;
    wire [31:0] es_csr_wdata1;
    wire [31:0] es_csr_wdata2;
    wire es_illegal;
    wire es_exc_valid;
    wire [31:0] es_exc_cause;
    wire [31:0] es_exc_tval;
    wire es_is_ebreak;
    wire [2:0] es_branch;
    wire [31:0] es_src1_value;
    wire es_mem_fwd_dep;
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    wire es_stage_block;
    wire es_stage_block_mdu_wait;
    wire es_stage_block_redirect_wait;
    wire es_stat_is_mdu;
    wire es_stat_rs1_mem_alu_fwd;
    wire es_stat_rs2_mem_alu_fwd;
    wire es_stat_rs1_wb_fwd;
    wire es_stat_rs2_wb_fwd;
    wire es_stat_rs1_load_fwd;
    wire es_stat_rs2_load_fwd;
    wire [2:0] es_stat_mdu_op;
    wire es_stat_mdu_req_fire;
    wire es_stat_mdu_resp_valid;
    wire es_stat_mdu_busy;
    wire es_stat_mdu_result_ready;
    wire es_stat_fast_mul;
    wire es_stat_fast_mul_issue;
    wire es_stat_fast_mul_resp_unused;
    wire es_stat_fast_mul_kill;
    wire es_stat_fast_mul_flush_drop;
    wire es_stat_fast_mul_forward;
    wire es_stat_fast_mul_stall_wait_ready;
    wire es_stat_old_div_path;
    wire es_stat_old_rem_path;
`else
    wire es_stage_block = 1'b0;
    wire es_stage_block_mdu_wait = 1'b0;
    wire es_stage_block_redirect_wait = 1'b0;
    wire es_stat_is_mdu = 1'b0;
    wire es_stat_rs1_mem_alu_fwd = 1'b0;
    wire es_stat_rs2_mem_alu_fwd = 1'b0;
    wire es_stat_rs1_wb_fwd = 1'b0;
    wire es_stat_rs2_wb_fwd = 1'b0;
    wire es_stat_rs1_load_fwd = 1'b0;
    wire es_stat_rs2_load_fwd = 1'b0;
    wire [2:0] es_stat_mdu_op = 3'b0;
    wire es_stat_mdu_req_fire = 1'b0;
    wire es_stat_mdu_resp_valid = 1'b0;
    wire es_stat_mdu_busy = 1'b0;
    wire es_stat_mdu_result_ready = 1'b0;
    wire es_stat_fast_mul = 1'b0;
    wire es_stat_fast_mul_issue = 1'b0;
    wire es_stat_fast_mul_resp_unused = 1'b0;
    wire es_stat_fast_mul_kill = 1'b0;
    wire es_stat_fast_mul_flush_drop = 1'b0;
    wire es_stat_fast_mul_forward = 1'b0;
    wire es_stat_fast_mul_stall_wait_ready = 1'b0;
    wire es_stat_old_div_path = 1'b0;
    wire es_stat_old_rem_path = 1'b0;
`endif
`endif
    wire es_fast_mul_stat_to_mem;
    wire fast_mul_resp_wb;
    wire fast_mul_flush_drop_pipe;
    wire ex_flush_valid;
    wire [31:0] ex_flush_pc;
    wire ex_mispredict_flush_valid;
    wire [31:0] ex_mispredict_flush_pc;
    wire ex_redirect_fire;
    reg ex_redirect_seen_r;
    wire ex_branch_taken_actual;
    wire ex_branch_pred_taken;
    wire [31:0] ex_branch_pred_target;
    wire ex_branch_pred_btb_hit;
    wire ex_branch_pred_btb_is_cond;
    wire [1:0] ex_branch_pred_bht_state;
    wire [31:0] ex_branch_pred_pht_idx;
    wire ex_branch_target_mismatch;
    wire redirect_flush_valid;
    wire vm_flush_start;
    reg redirect_clear_valid;
    wire stop_clear_set;
    reg stop_clear_valid;
    wire pipe_clear_valid;
    wire stop_fetch;
    localparam [1:0] FENCEI_IDLE = 2'd0;
    localparam [1:0] FENCEI_WAIT_DCACHE = 2'd1;
    localparam [1:0] FENCEI_WAIT_ICACHE = 2'd2;
    reg [1:0] fencei_state_r;
    reg fencei_commit_pending_r;
    reg [31:0] fencei_commit_pc_r;
    reg [31:0] fencei_commit_instr_r;
    reg [31:0] fencei_commit_nextpc_r;
`ifndef NPC_USE_DPI
    reg cpu_halted;
`endif

    wire ms_allowin /* verilator public_flat */;
    wire ms_to_ws_valid /* verilator public_flat */;
    wire ms_valid /* verilator public_flat */;
    wire [31:0] ms_pc;
    wire [31:0] ms_instr /* verilator public_flat */;
    wire [31:0] ms_nextpc;
    wire [4:0] ms_rd;
    wire ms_reg_wen;
    wire [1:0] ms_datatoreg;
    wire [2:0] ms_mem_op;
    wire [31:0] ms_aluout;
    wire ms_alu_fwd_valid;
    wire [31:0] ms_mem_rdata;
    wire [31:0] ms_csr_read_data;
    wire [1:0] ms_csr_wen;
    wire [11:0] ms_csr_waddr1;
    wire [11:0] ms_csr_waddr2;
    wire [31:0] ms_csr_wdata1;
    wire [31:0] ms_csr_wdata2;
    wire ms_illegal;
    wire ms_exc_valid;
    wire [31:0] ms_exc_cause;
    wire [31:0] ms_exc_tval;
    wire ms_is_ebreak;
    wire [2:0] ms_branch;
    wire [31:0] ms_src1_value;
    wire ms_fast_mul_stat;
    wire ms_load_bypass_valid;
    wire [4:0] ms_load_bypass_rd;
    wire [31:0] ms_load_bypass_data;
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    wire ms_stage_block;
    wire ms_stage_block_req_phase;
    wire ms_stage_block_resp_phase;
    wire ms_stage_block_load;
    wire ms_stage_block_store;
    wire ms_stage_block_req_load;
    wire ms_stage_block_req_store;
    wire ms_stage_block_resp_load;
    wire ms_stage_block_resp_store;
    wire ms_fast_req_fire_trace;
    wire ms_slow_req_fire_trace;
    wire ms_slow_req_fwd_dep_fire_trace;
    wire ms_slow_req_nonfwd_fire_trace;
    wire ms_stat_load_visible;
    wire ms_stat_load_aligned;
    wire ms_stat_load_result_ready;
    wire ms_stat_load_fault;
    wire ms_stat_load_signext_ready;
    wire ms_stat_load_req_fire;
    wire ms_stat_load_resp_valid;
    wire ms_stat_load_resp_fire;
    wire ms_stat_load_data_ready;
    wire ms_stat_load_signext_data_ready;
    wire ms_stat_load_to_wb_valid;
    wire ms_stat_load_split_or_misaligned;
    wire ms_stat_load_uncached;
    wire ms_stat_load_atomic;
    wire ms_stat_load_killed;
    wire ms_stat_hidden_load;
    wire ms_stat_load_store_block;
    wire ms_stat_load_lsu_pending;
    wire ms_stat_mreq_valid;
    wire ms_stat_mreq_is_load;
    wire ms_stat_mreq_is_store;
    wire ms_stat_mreq_is_atomic;
    wire ms_stat_mreq_need_mem;
    wire ms_stat_mreq_fire;
    wire ms_stat_mreq_misaligned;
    wire ms_stat_mreq_split;
    wire ms_stat_mreq_fault;
    wire ms_stat_mreq_blocked_by_resp;
    wire ms_stat_mresp_valid;
    wire ms_stat_mresp_is_load;
    wire ms_stat_mresp_is_store;
    wire ms_stat_mresp_is_atomic;
    wire ms_stat_mresp_resp_valid;
    wire ms_stat_mresp_resp_fire;
    wire ms_stat_mresp_split;
    wire ms_stat_mresp_fault;
    wire ms_stat_store_visible;
    wire ms_stat_store_req_fire;
    wire ms_stat_store_resp_valid;
    wire ms_stat_store_resp_fire;
    wire ms_stat_store_aligned;
    wire ms_stat_store_fault;
    wire ms_stat_store_split_or_misaligned;
    wire ms_stat_store_uncached;
    wire ms_stat_store_atomic;
    wire ms_stat_store_killed;
    wire ms_stat_store_buffer_safe;
    wire ms_stat_store_resp_wait;
    wire ms_stat_single_outstanding_wait;
    wire ms_stat_uncached_wait;
    wire ms_stat_writeback_wait;
    wire [63:0] stat_exmem_skid_candidate;
    wire [63:0] stat_exmem_skid_enqueue;
    wire [63:0] stat_exmem_skid_dequeue;
    wire [63:0] stat_exmem_skid_full_stall;
    wire [63:0] stat_exmem_skid_flush_drop;
    wire [63:0] stat_exmem_skid_blocked_not_safe;
    wire [63:0] stat_exmem_skid_blocked_branch;
    wire [63:0] stat_exmem_skid_blocked_mem;
    wire [63:0] stat_exmem_skid_blocked_csr;
    wire [63:0] stat_exmem_skid_blocked_exception;
    wire [63:0] stat_exmem_skid_blocked_div;
    wire [63:0] stat_exmem_skid_blocked_structural;
    wire [63:0] stat_exmem_skid_hold_cycles;
    wire [63:0] stat_exmem_skid_hold_mem_wait_cycles;
    wire [63:0] stat_exmem_skid_dequeue_after_mem_release;
    wire [63:0] stat_exmem_skid_dequeue_same_cycle_mem_release;
    wire [63:0] stat_exmem_skid_dequeue_causes_wb_valid;
    wire stat_exmem_skid_valid;
    wire stat_exmem_skid_enqueue_fire;
    wire stat_exmem_skid_dequeue_fire;
    wire stat_exmem_skid_dequeue_commit_fire;
    wire stat_exmem_skid_dequeue_to_mreq_fire;
    wire stat_exmem_skid_mem_wait;
    wire stat_exmem_skid_mem_release;
`else
    wire ms_stage_block = 1'b0;
    wire ms_stage_block_req_phase = 1'b0;
    wire ms_stage_block_resp_phase = 1'b0;
    wire ms_stage_block_load = 1'b0;
    wire ms_stage_block_store = 1'b0;
    wire ms_stage_block_req_load = 1'b0;
    wire ms_stage_block_req_store = 1'b0;
    wire ms_stage_block_resp_load = 1'b0;
    wire ms_stage_block_resp_store = 1'b0;
    wire ms_fast_req_fire_trace = 1'b0;
    wire ms_slow_req_fire_trace = 1'b0;
    wire ms_slow_req_fwd_dep_fire_trace = 1'b0;
    wire ms_slow_req_nonfwd_fire_trace = 1'b0;
    wire ms_stat_load_visible = 1'b0;
    wire ms_stat_load_aligned = 1'b0;
    wire ms_stat_load_result_ready = 1'b0;
    wire ms_stat_load_fault = 1'b0;
    wire ms_stat_load_signext_ready = 1'b0;
    wire ms_stat_load_req_fire = 1'b0;
    wire ms_stat_load_resp_valid = 1'b0;
    wire ms_stat_load_resp_fire = 1'b0;
    wire ms_stat_load_data_ready = 1'b0;
    wire ms_stat_load_signext_data_ready = 1'b0;
    wire ms_stat_load_to_wb_valid = 1'b0;
    wire ms_stat_load_split_or_misaligned = 1'b0;
    wire ms_stat_load_uncached = 1'b0;
    wire ms_stat_load_atomic = 1'b0;
    wire ms_stat_load_killed = 1'b0;
    wire ms_stat_hidden_load = 1'b0;
    wire ms_stat_load_store_block = 1'b0;
    wire ms_stat_load_lsu_pending = 1'b0;
    wire ms_stat_mreq_valid = 1'b0;
    wire ms_stat_mreq_is_load = 1'b0;
    wire ms_stat_mreq_is_store = 1'b0;
    wire ms_stat_mreq_is_atomic = 1'b0;
    wire ms_stat_mreq_need_mem = 1'b0;
    wire ms_stat_mreq_fire = 1'b0;
    wire ms_stat_mreq_misaligned = 1'b0;
    wire ms_stat_mreq_split = 1'b0;
    wire ms_stat_mreq_fault = 1'b0;
    wire ms_stat_mreq_blocked_by_resp = 1'b0;
    wire ms_stat_mresp_valid = 1'b0;
    wire ms_stat_mresp_is_load = 1'b0;
    wire ms_stat_mresp_is_store = 1'b0;
    wire ms_stat_mresp_is_atomic = 1'b0;
    wire ms_stat_mresp_resp_valid = 1'b0;
    wire ms_stat_mresp_resp_fire = 1'b0;
    wire ms_stat_mresp_split = 1'b0;
    wire ms_stat_mresp_fault = 1'b0;
    wire ms_stat_store_visible = 1'b0;
    wire ms_stat_store_req_fire = 1'b0;
    wire ms_stat_store_resp_valid = 1'b0;
    wire ms_stat_store_resp_fire = 1'b0;
    wire ms_stat_store_aligned = 1'b0;
    wire ms_stat_store_fault = 1'b0;
    wire ms_stat_store_split_or_misaligned = 1'b0;
    wire ms_stat_store_uncached = 1'b0;
    wire ms_stat_store_atomic = 1'b0;
    wire ms_stat_store_killed = 1'b0;
    wire ms_stat_store_buffer_safe = 1'b0;
    wire ms_stat_store_resp_wait = 1'b0;
    wire ms_stat_single_outstanding_wait = 1'b0;
    wire ms_stat_uncached_wait = 1'b0;
    wire ms_stat_writeback_wait = 1'b0;
    wire [63:0] stat_exmem_skid_candidate = 64'd0;
    wire [63:0] stat_exmem_skid_enqueue = 64'd0;
    wire [63:0] stat_exmem_skid_dequeue = 64'd0;
    wire [63:0] stat_exmem_skid_full_stall = 64'd0;
    wire [63:0] stat_exmem_skid_flush_drop = 64'd0;
    wire [63:0] stat_exmem_skid_blocked_not_safe = 64'd0;
    wire [63:0] stat_exmem_skid_blocked_branch = 64'd0;
    wire [63:0] stat_exmem_skid_blocked_mem = 64'd0;
    wire [63:0] stat_exmem_skid_blocked_csr = 64'd0;
    wire [63:0] stat_exmem_skid_blocked_exception = 64'd0;
    wire [63:0] stat_exmem_skid_blocked_div = 64'd0;
    wire [63:0] stat_exmem_skid_blocked_structural = 64'd0;
    wire [63:0] stat_exmem_skid_hold_cycles = 64'd0;
    wire [63:0] stat_exmem_skid_hold_mem_wait_cycles = 64'd0;
    wire [63:0] stat_exmem_skid_dequeue_after_mem_release = 64'd0;
    wire [63:0] stat_exmem_skid_dequeue_same_cycle_mem_release = 64'd0;
    wire [63:0] stat_exmem_skid_dequeue_causes_wb_valid = 64'd0;
    wire stat_exmem_skid_valid = 1'b0;
    wire stat_exmem_skid_enqueue_fire = 1'b0;
    wire stat_exmem_skid_dequeue_fire = 1'b0;
    wire stat_exmem_skid_dequeue_commit_fire = 1'b0;
    wire stat_exmem_skid_dequeue_to_mreq_fire = 1'b0;
    wire stat_exmem_skid_mem_wait = 1'b0;
    wire stat_exmem_skid_mem_release = 1'b0;
`endif
`endif
    wire hidden_mreq_valid;
    wire hidden_mreq_reg_wen;
    wire [4:0] hidden_mreq_rd;
    wire [1:0] hidden_mreq_datatoreg;
    wire [1:0] hidden_mreq_mem_wr;
    wire [31:0] hidden_mreq_aluout;
    wire [1:0] hidden_mreq_csr_wen;
    wire [11:0] hidden_mreq_csr_waddr1;
    wire [11:0] hidden_mreq_csr_waddr2;
    wire hidden_mreq_fast_mul_stat;
    wire dbg_mem_mreq_valid /* verilator public_flat */;
    wire dbg_mem_mresp_valid /* verilator public_flat */;
    wire dbg_mem_skid_valid /* verilator public_flat */;
    wire [31:0] dbg_mem_mreq_instr /* verilator public_flat */;
    wire [31:0] dbg_mem_mresp_instr /* verilator public_flat */;
    wire dbg_mem_mreq_need_mem /* verilator public_flat */;
    wire dbg_mem_mreq_req_valid /* verilator public_flat */;
    wire dbg_mem_mreq_mem_fire /* verilator public_flat */;
    wire dbg_mem_mreq_nonmem_fire /* verilator public_flat */;
    wire dbg_mem_mreq_consumed_eff /* verilator public_flat */;
    wire dbg_mem_mresp_ready_go /* verilator public_flat */;
    wire dbg_mem_mresp_commit_fire /* verilator public_flat */;
    wire dbg_mem_old_mreq_allowin /* verilator public_flat */;
    wire dbg_mem_mresp_atomic_en /* verilator public_flat */;
    wire dbg_mem_mresp_split /* verilator public_flat */;
    wire dbg_mem_mresp_phase1_amo_read /* verilator public_flat */;

    wire ws_allowin /* verilator public_flat */;
    wire ws_valid /* verilator public_flat */;
    wire [31:0] ws_pc /* verilator public_flat */;
    wire [31:0] ws_instr /* verilator public_flat */;
    wire [31:0] ws_nextpc /* verilator public_flat */;
    wire [4:0] ws_rd;
    wire ws_reg_wen;
    wire [31:0] ws_rf_wdata;
    wire ws_alu_fwd_valid;
    wire ws_load_fwd_valid;
    wire [1:0] ws_stat_datatoreg;
    wire [2:0] ws_stat_mem_op;
    wire ws_fast_mul_stat;
    wire [1:0] ws_csr_wen;
    wire [11:0] ws_csr_waddr1;
    wire [11:0] ws_csr_waddr2;
    wire [31:0] ws_csr_wdata1;
    wire [31:0] ws_csr_wdata2;
    wire ws_illegal;
    wire ws_exc_valid;
    wire [31:0] ws_exc_cause;
    wire [31:0] ws_exc_tval;
    wire ws_is_ebreak;
    wire [2:0] ws_branch;
    wire [31:0] ws_src1_value /* verilator public_flat */;
    wire ws_is_csr_instr;
    wire ws_is_unsupported_csr;
    wire [11:0] ws_csr_idx;
    wire [1:0] priv_state;
    wire [31:0] csr_mstatus;
    wire [31:0] csr_mtvec;
    wire [31:0] csr_stvec;
    wire [31:0] csr_mepc;
    wire [31:0] csr_sepc;
    wire [31:0] csr_mcause;
    wire [31:0] csr_scause;
    wire [31:0] csr_medeleg;
    wire [31:0] csr_mideleg;
    wire [31:0] csr_mie;
    wire [31:0] csr_mip /* verilator public_flat */;
    wire [31:0] csr_mcounteren;
    wire [31:0] csr_scounteren;
    wire [31:0] csr_satp;
    wire [63:0] if_mmu_req_count;
    wire [63:0] if_mmu_bypass_count;
    wire [63:0] if_mmu_translate_count;
    wire [63:0] if_mmu_ptw_cycle_count;
    wire [63:0] if_mmu_ptw_l1_read_count;
    wire [63:0] if_mmu_ptw_l0_read_count;
    wire [63:0] if_mmu_page_fault_count;
    wire [63:0] if_mmu_ptw_walk_start_count;
    wire [63:0] if_mmu_ptw_walk_done_count;
    wire [63:0] if_mmu_ptw_walk_fault_count;
    wire [63:0] if_mmu_tlb_hit_count;
    wire [63:0] if_mmu_tlb_miss_count;
    wire [63:0] if_mmu_tlb_hit_to_cache_req_cycle;
    wire [63:0] if_mmu_cache_req_wait_cycle;
    wire [63:0] if_mmu_cache_resp_wait_cycle;
    wire [63:0] if_mmu_bridge_state_wait_cycle;
    wire [63:0] if_mmu_fetch_req_count;
    wire [63:0] if_mmu_fetch_resp_count;
    wire [63:0] if_pipe_issue_count;
    wire [63:0] if_pipe_resp_count;
    wire [63:0] if_pipe_epoch_drop_count;
    wire [63:0] if_pipe_replay_count;
    wire [63:0] if_pipe_ptw_miss_count;
    wire [63:0] if_pipe_ptw_fault_count;
    wire [63:0] if_pipe_stall_cycle;
    wire [63:0] if_pipe_icache_miss_count;
    wire [63:0] if_pipe_icache_replay_count;
    wire [63:0] lsu_mmu_req_count;
    wire [63:0] lsu_mmu_bypass_count;
    wire [63:0] lsu_mmu_translate_count;
    wire [63:0] lsu_mmu_ptw_cycle_count;
    wire [63:0] lsu_mmu_ptw_l1_read_count;
    wire [63:0] lsu_mmu_ptw_l0_read_count;
    wire [63:0] lsu_mmu_page_fault_count;
    wire [63:0] lsu_mmu_ptw_walk_start_count;
    wire [63:0] lsu_mmu_ptw_walk_done_count;
    wire [63:0] lsu_mmu_ptw_walk_fault_count;
    wire [63:0] lsu_mmu_tlb_hit_count;
    wire [63:0] lsu_mmu_tlb_miss_count;
    wire [63:0] lsu_mmu_tlb_hit_to_cache_req_cycle;
    wire [63:0] lsu_mmu_cache_req_wait_cycle;
    wire [63:0] lsu_mmu_cache_resp_wait_cycle;
    wire [63:0] lsu_mmu_bridge_state_wait_cycle;
    wire [63:0] lsu_mmu_data_req_count;
    wire [63:0] lsu_mmu_data_resp_count;
    wire [63:0] lsu_mmu_uncached_req_count;
    wire [63:0] store_buffer_enqueue_count;
    wire [63:0] store_buffer_dequeue_count;
    wire [63:0] store_buffer_full_stall_count;
    wire [63:0] store_buffer_drain_req_count;
    wire [63:0] store_buffer_drain_resp_count;
    wire [63:0] store_buffer_drain_wait_count;
    wire [63:0] store_buffer_load_forward_count;
    wire [63:0] store_buffer_load_stall_conflict_count;
    wire [63:0] store_buffer_load_stall_buffer_nonempty_count;
    wire [63:0] store_buffer_fence_drain_wait_bridge_count;
    reg [63:0] store_buffer_fence_drain_wait_core_count;
    wire [63:0] store_buffer_fence_drain_wait_count =
        store_buffer_fence_drain_wait_bridge_count + store_buffer_fence_drain_wait_core_count;
    wire [63:0] store_buffer_uncached_drain_wait_count;
    wire [63:0] store_buffer_killed_store_block_count;
    wire [63:0] store_buffer_occupancy0_count;
    wire [63:0] store_buffer_occupancy1_count;
    wire [63:0] store_buffer_occupancy2_count;
    wire [63:0] store_buffer_max_occupancy_count;
    wire [63:0] store_buffer_enqueue_occ0_count;
    wire [63:0] store_buffer_enqueue_occ1_count;
    wire [63:0] store_buffer_enqueue_full_count;
    wire [63:0] lsu_mmu_ptw_cycle_total = lsu_mmu_ptw_cycle_count;
    wire [63:0] lsu_mmu_ptw_l1_read_total = lsu_mmu_ptw_l1_read_count;
    wire [63:0] lsu_mmu_ptw_l0_read_total = lsu_mmu_ptw_l0_read_count;
    wire [63:0] lsu_mmu_ptw_walk_start_total = lsu_mmu_ptw_walk_start_count;
    wire [63:0] lsu_mmu_ptw_walk_done_total = lsu_mmu_ptw_walk_done_count;
    wire [63:0] lsu_mmu_ptw_walk_fault_total = lsu_mmu_ptw_walk_fault_count;
    wire [63:0] lsu_pipe_issue_count;
    wire [63:0] lsu_pipe_resp_count;
    wire [63:0] lsu_pipe_epoch_drop_count;
    wire [63:0] lsu_pipe_dtlb_hit_count;
    wire [63:0] lsu_pipe_dtlb_miss_count;
    wire [63:0] lsu_pipe_replay_count;
    wire [63:0] lsu_pipe_fault_count;
    wire [63:0] lsu_pipe_stall_cycle;
    wire [63:0] lsu_pipe_dcache_hit_count;
    wire [63:0] lsu_pipe_dcache_miss_count;
    wire [63:0] lsu_pipe_store_hit_count;
    wire [63:0] lsu_pipe_load_hit_count;
    wire [63:0] lsu_pipe_slow_fallback_count;
    wire [63:0] lsu_pipe_load_miss_replay_count;
    wire [63:0] lsu_pipe_store_miss_replay_count;
    wire [63:0] lsu_pipe_direct_uncached_count;
    wire [63:0] lsu_pipe_direct_non_dtlb_hit_count;
    wire [63:0] lsu_pipe_direct_perm_fault_count;
    wire [63:0] lsu_pipe_direct_cross_page_count;
    wire [63:0] lsu_pipe_direct_fast_block_count;
    wire [63:0] lsu_pipe_direct_fast_block_atomic_count;
    wire [63:0] lsu_pipe_direct_fast_block_misaligned_count;
    wire [63:0] lsu_pipe_direct_fast_block_exception_count;
    wire [63:0] lsu_pipe_direct_fast_block_phase2_count;
    wire [63:0] lsu_pipe_direct_fast_block_other_count;
    wire [63:0] lsu_pipe_direct_other_count;
    wire [63:0] lsu_pipe_hit_latency_sum;
    wire [63:0] lsu_pipe_hit_latency_count;
    wire [63:0] lsu_pipe_hit_latency_max;
    wire [63:0] lsu_pipe_load_hit_latency_sum;
    wire [63:0] lsu_pipe_load_hit_latency_count;
    wire [63:0] lsu_pipe_load_hit_latency_max;
    wire [63:0] lsu_pipe_store_hit_latency_sum;
    wire [63:0] lsu_pipe_store_hit_latency_count;
    wire [63:0] lsu_pipe_store_hit_latency_max;
    wire [63:0] lsu_pipe_slow_fallback_latency_sum;
    wire [63:0] lsu_pipe_slow_fallback_latency_count;
    wire [63:0] lsu_pipe_slow_fallback_latency_max;
    wire [63:0] lsu_pipe_slow_direct_latency_sum;
    wire [63:0] lsu_pipe_slow_direct_latency_count;
    wire [63:0] lsu_pipe_slow_direct_latency_max;
    wire [63:0] lsu_pipe_slow_replay_latency_sum;
    wire [63:0] lsu_pipe_slow_replay_latency_count;
    wire [63:0] lsu_pipe_slow_replay_latency_max;

    // Commit, trap, and CSR policy stays top-owned. These sideband wires keep
    // architectural ownership outside the structural wrappers.
`ifdef NPC_USE_DPI
    wire ws_is_semihosting_ebreak = semihosting_ebreak_match(ws_pc);
`else
    wire ws_is_semihosting_ebreak = 1'b0;
`endif
    wire commit_is_ebreak = ws_is_ebreak && !ws_is_semihosting_ebreak;
    wire ws_is_mret = (ws_instr == 32'h30200073);
    wire ws_is_sret = (ws_instr == 32'h10200073);
    wire commit_sync_exception_w = ws_valid && trap_redirect_valid && !ws_is_mret && !ws_is_sret;
    wire csr_commit_valid =
        fencei_commit_fire ||
        (ws_valid && !store_buffer_drain_before_maint && !ws_is_fencei &&
            !fencei_maint_active && !fencei_commit_pending_r);
    wire [31:0] csr_commit_instr = fencei_commit_fire ? fencei_commit_instr_r : ws_instr;
    wire csr_commit_exception =
        fencei_commit_fire ? 1'b0 :
        (csr_commit_valid && trap_redirect_valid && !ws_is_mret && !ws_is_sret);

    wire trap_kill_side_effect;
    wire trap_redirect_valid;
    wire trap_redirect_async;
    wire [31:0] trap_redirect_pc;
    wire priv_upd_we;
    wire priv_upd_priv_we;
    wire [1:0] priv_upd_priv;
    wire priv_upd_mstatus_we;
    wire [31:0] priv_upd_mstatus;
    wire priv_upd_mepc_we;
    wire [31:0] priv_upd_mepc;
    wire priv_upd_mcause_we;
    wire [31:0] priv_upd_mcause;
    wire priv_upd_mtval_we;
    wire [31:0] priv_upd_mtval;
    wire priv_upd_sepc_we;
    wire [31:0] priv_upd_sepc;
    wire priv_upd_scause_we;
    wire [31:0] priv_upd_scause;
    wire priv_upd_stval_we;
    wire [31:0] priv_upd_stval;

    wire ms_fwd_valid;
    wire [31:0] ms_fwd_data;

    wire ibus_req_ready /* verilator public_flat */;
    wire ibus_resp_valid /* verilator public_flat */;
    wire [31:0] ibus_resp_data;
    wire ibus_resp_exc_valid;
    wire [31:0] ibus_resp_exc_cause;
    wire [31:0] ibus_resp_exc_tval;
    wire ibus_req_pred_taken;
    wire [31:0] ibus_req_pred_target;
    wire ibus_req_pred_btb_hit;
    wire ibus_req_pred_btb_is_cond;
    wire [1:0] ibus_req_pred_bht_state;
    wire [31:0] ibus_req_pred_pht_idx;
    wire [31:0] ibus_resp_pc;
    wire [31:0] ibus_resp_seq;
    wire [15:0] ibus_resp_epoch;
    wire ibus_resp_pred_taken;
    wire [31:0] ibus_resp_pred_target;
    wire ibus_resp_pred_btb_hit;
    wire ibus_resp_pred_btb_is_cond;
    wire [1:0] ibus_resp_pred_bht_state;
    wire [31:0] ibus_resp_pred_pht_idx;
    wire [31:0] ibus_req_addr_w;
    wire ibus_req_valid_w /* verilator public_flat */;
    wire [31:0] ibus_req_vaddr_w;
    wire [31:0] ibus_req_paddr_w;
    wire ibus_resp_ready_w /* verilator public_flat */;
    wire ibus_icache_req_valid;
    wire ibus_icache_req_ready;
    wire ibus_icache_resp_valid;
    wire ibus_icache_resp_ready;
    wire [31:0] ibus_icache_resp_data;
    wire ibus_icache_lookup_hit;
    wire ibus_icache_lookup_uncached;
    wire ibus_ptw_req_valid;
    wire ibus_ptw_req_ready;
    wire [31:0] ibus_ptw_req_addr;
    wire ibus_ptw_resp_valid;
    wire ibus_ptw_resp_ready;
    wire [31:0] ibus_ptw_resp_data;
    wire ibus_icache_pipe_req_valid;
    wire ibus_icache_pipe_req_ready;
    wire [31:0] ibus_icache_pipe_req_paddr;
    wire [31:0] ibus_icache_pipe_req_vaddr;
    wire [31:0] ibus_icache_pipe_req_pc;
    wire [31:0] ibus_icache_pipe_req_seq;
    wire [15:0] ibus_icache_pipe_req_epoch;
    wire ibus_icache_pipe_req_pred_taken;
    wire [31:0] ibus_icache_pipe_req_pred_target;
    wire ibus_icache_pipe_req_pred_btb_hit;
    wire ibus_icache_pipe_req_pred_btb_is_cond;
    wire [1:0] ibus_icache_pipe_req_pred_bht_state;
    wire [31:0] ibus_icache_pipe_req_pred_pht_idx;
    wire [1:0] ibus_icache_pipe_req_priv;
    wire ibus_icache_pipe_req_exception_valid;
    wire [31:0] ibus_icache_pipe_req_exception_cause;
    wire [31:0] ibus_icache_pipe_req_exception_tval;
    wire ibus_icache_pipe_resp_valid;
    wire ibus_icache_pipe_resp_ready;
    wire [31:0] ibus_icache_pipe_resp_instr;
    wire [31:0] ibus_icache_pipe_resp_pc;
    wire [31:0] ibus_icache_pipe_resp_seq;
    wire [15:0] ibus_icache_pipe_resp_epoch;
    wire ibus_icache_pipe_resp_pred_taken;
    wire [31:0] ibus_icache_pipe_resp_pred_target;
    wire ibus_icache_pipe_resp_pred_btb_hit;
    wire ibus_icache_pipe_resp_pred_btb_is_cond;
    wire [1:0] ibus_icache_pipe_resp_pred_bht_state;
    wire [31:0] ibus_icache_pipe_resp_pred_pht_idx;
    wire ibus_icache_pipe_resp_exception_valid;
    wire [31:0] ibus_icache_pipe_resp_exception_cause;
    wire [31:0] ibus_icache_pipe_resp_exception_tval;
    wire ibus_icache_pipe_resp_hit;
    wire ibus_icache_pipe_resp_miss;

    wire dbus_req_valid /* verilator public_flat */;
    wire dbus_req_ready /* verilator public_flat */;
    wire dbus_req_fast_ok;
    wire dbus_req_fast_block_atomic;
    wire dbus_req_fast_block_misaligned;
    wire dbus_req_fast_block_exception;
    wire dbus_req_fast_block_phase2;
    wire dbus_req_fast_block_other;
    wire dbus_req_write;
    wire dbus_req_atomic;
    wire dbus_req_store_bufferable;
    wire [31:0] dbus_req_addr;
    wire [31:0] dbus_req_vaddr;
    wire [31:0] dbus_req_paddr;
    wire [31:0] dbus_req_wdata;
    wire [3:0] dbus_req_wstrb;
    wire [2:0] dbus_req_len;
    wire dbus_resp_valid /* verilator public_flat */;
    wire dbus_resp_ready /* verilator public_flat */;
    wire [31:0] dbus_resp_data;
    wire dbus_resp_exc_valid;
    wire [31:0] dbus_resp_exc_cause;
    wire [31:0] dbus_resp_exc_tval;
    wire dbus_store_buffer_empty /* verilator public_flat */;
    wire dbus_store_buffer_busy /* verilator public_flat */;
    wire store_buffer_drain_before_maint /* verilator public_flat */;
    wire [2:0] dbg_dcache_bridge_state /* verilator public_flat */;
    wire dbg_dcache_bridge_drop_resp /* verilator public_flat */;
    wire dbg_dcache_bridge_req_write /* verilator public_flat */;
    wire dbg_dcache_bridge_req_store_bufferable /* verilator public_flat */;
    wire dbg_dcache_bridge_req_safe_store_bufferable /* verilator public_flat */;
    wire dbg_dcache_bridge_sbuf0_valid /* verilator public_flat */;
    wire dbg_dcache_bridge_sbuf1_valid /* verilator public_flat */;
    wire dbg_dcache_bridge_sbuf0_sent /* verilator public_flat */;
    wire dbg_dcache_bridge_sbuf1_sent /* verilator public_flat */;
    wire dbg_dcache_bridge_sbuf_drain_active /* verilator public_flat */;
    wire dbg_dcache_bridge_sbuf_drain_resp_pending /* verilator public_flat */;
    wire dbg_dcache_bridge_sbuf_drain_req_valid /* verilator public_flat */;
    wire dbg_dcache_bridge_sbuf_drain_grant /* verilator public_flat */;
    wire dbg_dcache_bridge_sbuf_drain_req_fire /* verilator public_flat */;
    wire dbg_dcache_bridge_sbuf_drain_resp_fire /* verilator public_flat */;
    wire dbg_dcache_bridge_data_req_fire /* verilator public_flat */;
    wire dbg_dcache_bridge_lower_resp_ready /* verilator public_flat */;
    wire dbg_dcache_bridge_lower_req_valid /* verilator public_flat */;
    wire dbg_dcache_bridge_lower_req_write /* verilator public_flat */;
    wire [31:0] dbg_dcache_bridge_lower_req_addr /* verilator public_flat */;
    wire dbg_dcache_bridge_sbuf_conflict_stall /* verilator public_flat */;
    wire dbg_dcache_bridge_req_store_buffer_full /* verilator public_flat */;
    wire dbg_dcache_bridge_sbuf_forward_hit /* verilator public_flat */;
    wire dbus_dcache_req_valid /* verilator public_flat */;
    wire dbus_dcache_req_ready /* verilator public_flat */;
    wire dbus_dcache_req_write /* verilator public_flat */;
    wire [31:0] dbus_dcache_req_wdata;
    wire [3:0] dbus_dcache_req_wstrb;
    wire [2:0] dbus_dcache_req_len;
    wire dbus_dcache_req_is_ptw /* verilator public_flat */;
    wire dbus_dcache_resp_valid /* verilator public_flat */;
    wire dbus_dcache_resp_ready /* verilator public_flat */;
    wire [31:0] dbus_dcache_resp_data;
    wire atomic_alu_ready;
    wire atomic_alu_req_valid;
    wire [3:0] atomic_alu_op;
    wire [31:0] atomic_alu_old;
    wire [31:0] atomic_alu_rs2;
    wire atomic_alu_resp_valid;
    wire [31:0] atomic_alu_result;

    wire ibus_mem_req_valid;
    wire ibus_mem_req_ready;
    wire ibus_mem_req_write;
    wire [31:0] ibus_mem_req_addr;
    wire [31:0] ibus_mem_req_wdata;
    wire [3:0] ibus_mem_req_wstrb;
    wire [2:0] ibus_mem_req_len;
    wire [31:0] ibus_mem_req_paddr;
    wire ibus_mem_resp_valid;
    wire ibus_mem_resp_ready;
    wire [31:0] ibus_mem_resp_data;
    wire ibus_icache_mem_req_valid;
    wire ibus_icache_mem_req_ready;
    wire ibus_icache_mem_req_write;
    wire [31:0] ibus_icache_mem_req_addr;
    wire [31:0] ibus_icache_mem_req_wdata;
    wire [3:0] ibus_icache_mem_req_wstrb;
    wire [2:0] ibus_icache_mem_req_len;
    wire ibus_icache_mem_resp_valid;
    wire ibus_icache_mem_resp_ready;
    wire [31:0] ibus_icache_mem_resp_data;

    wire [63:0] timer_time_value /* verilator public_flat */;
    wire [63:0] timer_timecmp_value /* verilator public_flat */;
    wire [31:0] timer_step_accum_value /* verilator public_flat */;
    wire timer_mtip /* verilator public_flat */;
    wire dcache_maint_flush_req;
    wire dcache_maint_flush_done;
    wire icache_maint_inv_req;
    wire icache_maint_inv_done;

`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
    wire [63:0] icache_stat_access;
    wire [63:0] icache_stat_hit;
    wire [63:0] icache_stat_miss;
    wire [63:0] icache_stat_refill_req;
    wire [63:0] icache_stat_refill_resp;
    wire [63:0] icache_stat_refill_bypass;
    wire [63:0] icache_stat_req_wait_cycle;
    wire [63:0] icache_stat_hit_resp_wait_cycle;
    wire [63:0] icache_stat_miss_wait_cycle;
    wire [63:0] icache_stat_uncached_access;
    wire [63:0] icache_pipe_req_valid_cycle;
    wire [63:0] icache_pipe_req_ready_cycle;
    wire [63:0] icache_pipe_req_fire_cycle;
    wire [63:0] icache_pipe_req_valid_not_ready_cycle;
    wire [63:0] icache_pipe_resp_valid_cycle;
    wire [63:0] icache_pipe_resp_ready_cycle;
    wire [63:0] icache_pipe_resp_fire_cycle;
    wire [63:0] icache_pipe_data_valid_cycle;
    wire [63:0] icache_pipe_resp_block_cycle;
    wire [63:0] icache_pipe_ready_block_state_cycle;
    wire [63:0] icache_pipe_ready_block_data_cycle;
    wire [63:0] icache_pipe_ready_block_resp_cycle;
    wire [63:0] icache_pipe_ready_block_cpu_cycle;
    wire [63:0] icache_pipe_ready_block_maint_cycle;
    wire [63:0] icache_pipe_state_idle_cycle;
    wire [63:0] icache_pipe_state_refill_cycle;
    wire [63:0] icache_pipe_state_uncached_cycle;
    wire [63:0] icache_pipe_hit_fire_cycle;
    wire [63:0] icache_pipe_miss_fire_cycle;
    wire [63:0] icache_pipe_refill_busy_cycle;
    wire [63:0] icache_pipe_resp_fifo_full_cycle;
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
    wire [63:0] dcache_stat_req_wait_cycle;
    wire [63:0] dcache_stat_hit_resp_wait_cycle;
    wire [63:0] dcache_stat_miss_wait_cycle;
    wire [63:0] dcache_stat_uncached_access;
    wire [63:0] dcache_stat_writeback_cycle;
`elsif NPC_HIT_PATH_STAT
    wire [63:0] icache_stat_req_wait_cycle = 64'd0;
    wire [63:0] icache_stat_hit_resp_wait_cycle = 64'd0;
    wire [63:0] icache_stat_miss_wait_cycle = 64'd0;
    wire [63:0] icache_stat_uncached_access = 64'd0;
    wire [63:0] dcache_stat_req_wait_cycle;
    wire [63:0] dcache_stat_hit_resp_wait_cycle;
    wire [63:0] dcache_stat_miss_wait_cycle;
    wire [63:0] dcache_stat_uncached_access;
    wire [63:0] dcache_stat_writeback_cycle;
`elsif NPC_PIPE_STAT
    wire [63:0] icache_stat_req_wait_cycle = 64'd0;
    wire [63:0] icache_stat_hit_resp_wait_cycle = 64'd0;
    wire [63:0] icache_stat_miss_wait_cycle = 64'd0;
    wire [63:0] icache_stat_uncached_access = 64'd0;
    wire [63:0] dcache_stat_req_wait_cycle;
    wire [63:0] dcache_stat_hit_resp_wait_cycle;
    wire [63:0] dcache_stat_miss_wait_cycle;
    wire [63:0] dcache_stat_uncached_access;
    wire [63:0] dcache_stat_writeback_cycle;
`else
    wire [63:0] icache_stat_access = 64'd0;
    wire [63:0] icache_stat_hit = 64'd0;
    wire [63:0] icache_stat_miss = 64'd0;
    wire [63:0] icache_stat_refill_req = 64'd0;
    wire [63:0] icache_stat_refill_resp = 64'd0;
    wire [63:0] icache_stat_refill_bypass = 64'd0;
    wire [63:0] icache_stat_req_wait_cycle = 64'd0;
    wire [63:0] icache_stat_hit_resp_wait_cycle = 64'd0;
    wire [63:0] icache_stat_miss_wait_cycle = 64'd0;
    wire [63:0] icache_stat_uncached_access = 64'd0;
    wire [63:0] icache_pipe_req_valid_cycle = 64'd0;
    wire [63:0] icache_pipe_req_ready_cycle = 64'd0;
    wire [63:0] icache_pipe_req_fire_cycle = 64'd0;
    wire [63:0] icache_pipe_req_valid_not_ready_cycle = 64'd0;
    wire [63:0] icache_pipe_resp_valid_cycle = 64'd0;
    wire [63:0] icache_pipe_resp_ready_cycle = 64'd0;
    wire [63:0] icache_pipe_resp_fire_cycle = 64'd0;
    wire [63:0] icache_pipe_data_valid_cycle = 64'd0;
    wire [63:0] icache_pipe_resp_block_cycle = 64'd0;
    wire [63:0] icache_pipe_ready_block_state_cycle = 64'd0;
    wire [63:0] icache_pipe_ready_block_data_cycle = 64'd0;
    wire [63:0] icache_pipe_ready_block_resp_cycle = 64'd0;
    wire [63:0] icache_pipe_ready_block_cpu_cycle = 64'd0;
    wire [63:0] icache_pipe_ready_block_maint_cycle = 64'd0;
    wire [63:0] icache_pipe_state_idle_cycle = 64'd0;
    wire [63:0] icache_pipe_state_refill_cycle = 64'd0;
    wire [63:0] icache_pipe_state_uncached_cycle = 64'd0;
    wire [63:0] icache_pipe_hit_fire_cycle = 64'd0;
    wire [63:0] icache_pipe_miss_fire_cycle = 64'd0;
    wire [63:0] icache_pipe_refill_busy_cycle = 64'd0;
    wire [63:0] icache_pipe_resp_fifo_full_cycle = 64'd0;
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
    wire [63:0] dcache_stat_req_wait_cycle;
    wire [63:0] dcache_stat_hit_resp_wait_cycle;
    wire [63:0] dcache_stat_miss_wait_cycle;
    wire [63:0] dcache_stat_uncached_access;
    wire [63:0] dcache_stat_writeback_cycle;
`endif
`endif

    wire [63:0] dhitopt_candidate_count;
    wire [63:0] dhitopt_success_count;
    wire [63:0] dhitopt_fallback_count;
    wire [63:0] dhitopt_block_store_buffer_count;
    wire [63:0] dhitopt_block_uncached_count;
    wire [63:0] dhitopt_block_fault_count;
    wire [63:0] dhitopt_block_miss_count;
    wire [63:0] dhitopt_block_alignment_count;
    wire [63:0] dhitopt_unknown_count;

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
    wire [63:0] bpu_btb_lookup_count;
    wire [63:0] bpu_btb_hit_count;
    wire [63:0] bpu_btb_miss_count;
    wire [63:0] bpu_bht_pred_taken_count;
    wire [63:0] bpu_bht_pred_not_taken_count;
    wire [63:0] bpu_btb_conflict_count;
    wire [63:0] bpu_btb_update_count;
    wire [63:0] bpu_btb_replace_count;
    wire [63:0] bpu_bht_lookup_count;
    wire [63:0] bpu_bht_update_count;
    wire [63:0] bpu_bht_weak_taken_count;
    wire [63:0] bpu_bht_weak_not_taken_count;
    wire [63:0] bpu_bht_strong_taken_count;
    wire [63:0] bpu_bht_strong_not_taken_count;
    wire [31:0] bpu_bhr_value;

    assign branch_stat_resolve_valid = es_valid && ms_allowin && (es_branch != BRANCH_DEFAULT);
`else
    wire branch_stat_fetch_req_valid = 1'b0;
    wire [31:0] branch_stat_fetch_req_pc = 32'b0;
    wire branch_stat_fetch_accept_valid = 1'b0;
    wire [31:0] branch_stat_fetch_accept_pc = 32'b0;
    wire [31:0] branch_stat_fetch_accept_instr = 32'b0;
    wire branch_stat_fetch_drop_valid = 1'b0;
    wire branch_stat_fetch_drop_redirect = 1'b0;
    wire [31:0] branch_stat_fetch_drop_pc = 32'b0;
    wire [31:0] branch_stat_fetch_drop_instr = 32'b0;
    wire branch_stat_resolve_valid = 1'b0;
    wire [63:0] bpu_btb_lookup_count = 64'd0;
    wire [63:0] bpu_btb_hit_count = 64'd0;
    wire [63:0] bpu_btb_miss_count = 64'd0;
    wire [63:0] bpu_bht_pred_taken_count = 64'd0;
    wire [63:0] bpu_bht_pred_not_taken_count = 64'd0;
    wire [63:0] bpu_btb_conflict_count = 64'd0;
    wire [63:0] bpu_btb_update_count = 64'd0;
    wire [63:0] bpu_btb_replace_count = 64'd0;
    wire [63:0] bpu_bht_lookup_count = 64'd0;
    wire [63:0] bpu_bht_update_count = 64'd0;
    wire [63:0] bpu_bht_weak_taken_count = 64'd0;
    wire [63:0] bpu_bht_weak_not_taken_count = 64'd0;
    wire [63:0] bpu_bht_strong_taken_count = 64'd0;
    wire [63:0] bpu_bht_strong_not_taken_count = 64'd0;
    wire [31:0] bpu_bhr_value = 32'b0;
`endif

`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    wire if_stat_fs_valid /* verilator public_flat */;
    wire [1:0] if_stat_queue_count /* verilator public_flat */;
    wire if_stat_fetch_room /* verilator public_flat */;
    wire if_stat_req_fire;
    wire if_stat_resp_fire;
    wire if_stat_resp_accept;
    wire if_stat_resp_drop;
    wire if_stat_bypass_direct;
    wire if_stat_waiting_resp /* verilator public_flat */;
    wire if_stat_drop_resp;
    wire if_stat_fs_pop;
    wire if_stat_resp_enq;
    wire if_stat_queue_full;
    wire if_stat_resp_block;
    wire if_pipe_stat_outstanding;
    wire if_pipe_stat_replay_valid;
    wire if_pipe_stat_ptw_busy;
    wire if_pipe_stat_req_valid;
    wire if_pipe_stat_req_ready;
    wire if_pipe_stat_resp_current;
    wire if_pipe_stat_resp_stale;
    wire if_pipe_stat_lower_req_valid;
    wire if_pipe_stat_lower_req_ready;
    wire if_pipe_stat_lower_resp_valid;
    wire if_pipe_stat_lower_resp_ready;
`else
    wire if_stat_fs_valid = 1'b0;
    wire [1:0] if_stat_queue_count = 2'b0;
    wire if_stat_fetch_room = 1'b0;
    wire if_stat_req_fire = 1'b0;
    wire if_stat_resp_fire = 1'b0;
    wire if_stat_resp_accept = 1'b0;
    wire if_stat_resp_drop = 1'b0;
    wire if_stat_bypass_direct = 1'b0;
    wire if_stat_waiting_resp = 1'b0;
    wire if_stat_drop_resp = 1'b0;
    wire if_stat_fs_pop = 1'b0;
    wire if_stat_resp_enq = 1'b0;
    wire if_stat_queue_full = 1'b0;
    wire if_stat_resp_block = 1'b0;
    wire if_pipe_stat_outstanding = 1'b0;
    wire if_pipe_stat_replay_valid = 1'b0;
    wire if_pipe_stat_ptw_busy = 1'b0;
    wire if_pipe_stat_req_valid = 1'b0;
    wire if_pipe_stat_req_ready = 1'b0;
    wire if_pipe_stat_resp_current = 1'b0;
    wire if_pipe_stat_resp_stale = 1'b0;
    wire if_pipe_stat_lower_req_valid = 1'b0;
    wire if_pipe_stat_lower_req_ready = 1'b0;
    wire if_pipe_stat_lower_resp_valid = 1'b0;
    wire if_pipe_stat_lower_resp_ready = 1'b0;
`endif
`else
    wire if_stat_fs_valid = 1'b0;
    wire [1:0] if_stat_queue_count = 2'b0;
    wire if_stat_fetch_room = 1'b0;
    wire if_stat_req_fire = 1'b0;
    wire if_stat_resp_fire = 1'b0;
    wire if_stat_resp_accept = 1'b0;
    wire if_stat_resp_drop = 1'b0;
    wire if_stat_bypass_direct = 1'b0;
    wire if_stat_waiting_resp = 1'b0;
    wire if_stat_drop_resp = 1'b0;
    wire if_stat_fs_pop = 1'b0;
    wire if_stat_resp_enq = 1'b0;
    wire if_stat_queue_full = 1'b0;
    wire if_stat_resp_block = 1'b0;
    wire if_pipe_stat_outstanding = 1'b0;
    wire if_pipe_stat_replay_valid = 1'b0;
    wire if_pipe_stat_ptw_busy = 1'b0;
    wire if_pipe_stat_req_valid = 1'b0;
    wire if_pipe_stat_req_ready = 1'b0;
    wire if_pipe_stat_resp_current = 1'b0;
    wire if_pipe_stat_resp_stale = 1'b0;
    wire if_pipe_stat_lower_req_valid = 1'b0;
    wire if_pipe_stat_lower_req_ready = 1'b0;
    wire if_pipe_stat_lower_resp_valid = 1'b0;
    wire if_pipe_stat_lower_resp_ready = 1'b0;
`endif

    wire bpu_update_is_cond =
        (es_branch == 3'b100) ||
        (es_branch == 3'b101) ||
        (es_branch == 3'b110) ||
        (es_branch == 3'b111);
    wire bpu_update_valid =
        es_valid && ms_allowin &&
        ((es_branch == BRANCH_J) || bpu_update_is_cond);

`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    assign es_fast_mul_stat_to_mem = es_stat_fast_mul;
`else
    assign es_fast_mul_stat_to_mem = 1'b0;
`endif
`else
    assign es_fast_mul_stat_to_mem = 1'b0;
`endif

    assign ws_is_csr_instr = (ws_instr[6:0] == 7'b1110011) && (ws_instr[14:12] != 3'b000);
    assign ws_csr_idx = ws_instr[31:20];
    wire ws_is_store_instr = (ws_instr[6:0] == 7'b0100011);
    wire ws_is_atomic_instr = (ws_instr[6:0] == 7'b0101111);
    wire ws_has_mem_side_effect = ws_is_store_instr || ws_is_atomic_instr;
    wire ws_is_fence = (ws_instr[6:0] == 7'b0001111) && (ws_instr[14:12] == 3'b000);
    wire ws_is_fencei = (ws_instr == 32'h0000100f);
    wire ws_is_sfence_vma = (ws_instr[6:0] == 7'b1110011) &&
        (ws_instr[14:12] == 3'b000) && (ws_instr[31:25] == 7'b0001001);
    wire fencei_maint_active = (fencei_state_r != FENCEI_IDLE);
    assign store_buffer_drain_before_maint = dbus_store_buffer_busy &&
        (ws_is_fence || ws_is_fencei || ws_is_sfence_vma ||
            (ws_is_csr_instr && (ws_csr_idx == 12'h180)));
    wire fencei_start = ws_valid && ws_is_fencei && !trap_redirect_valid &&
        !store_buffer_drain_before_maint && (fencei_state_r == FENCEI_IDLE);
    assign vm_flush_start = ws_valid && !trap_redirect_valid && !fencei_start &&
        !store_buffer_drain_before_maint && !fencei_maint_active && !fencei_commit_pending_r &&
        ((ws_is_csr_instr && (ws_csr_idx == 12'h180)) || ws_is_sfence_vma);
    wire tlb_flush_all = vm_flush_start;
    wire cache_maint_start = fencei_start || vm_flush_start;
    wire fencei_commit_fire = (fencei_state_r == FENCEI_WAIT_ICACHE) && icache_maint_inv_done && fencei_commit_pending_r;
    assign dcache_maint_flush_req = (fencei_state_r == FENCEI_WAIT_DCACHE);
    assign icache_maint_inv_req = (fencei_state_r == FENCEI_WAIT_ICACHE);

    wire commit_side_effect = ws_valid && !store_buffer_drain_before_maint &&
        !ws_is_ebreak && !trap_kill_side_effect &&
        !fencei_maint_active && !fencei_commit_pending_r;

    wire [31:0] ms_load_data_ext =
        (ms_mem_op == 3'b000) ? {{24{ms_mem_rdata[7]}}, ms_mem_rdata[7:0]} :
        (ms_mem_op == 3'b001) ? {{16{ms_mem_rdata[15]}}, ms_mem_rdata[15:0]} :
        (ms_mem_op == 3'b100) ? {24'b0, ms_mem_rdata[7:0]} :
        (ms_mem_op == 3'b101) ? {16'b0, ms_mem_rdata[15:0]} :
        ms_mem_rdata;
    wire ms_load_late_fwd_valid = ms_valid && ms_reg_wen && (ms_rd != 5'b0) &&
        (ms_datatoreg == 2'b01) && ms_to_ws_valid;
    wire ms_is_atomic_instr = (ms_instr[6:0] == 7'b0101111);
    assign ms_load_bypass_valid =
`ifdef NPC_LSU_LOAD_BYPASS
        ms_load_late_fwd_valid && !ms_exc_valid && !flush_mem &&
        !ms_is_atomic_instr;
`else
        1'b0;
`endif
    assign ms_load_bypass_rd = ms_rd;
    assign ms_load_bypass_data = ms_load_data_ext;
    wire ms_nonload_fwd_valid = ms_valid && ms_reg_wen && (ms_rd != 5'b0) &&
        (ms_datatoreg != 2'b01);
    assign ms_alu_fwd_valid = ms_valid && ms_reg_wen && (ms_rd != 5'b0) &&
        (ms_datatoreg == 2'b00) && !ms_exc_valid;
    wire hidden_alu_fwd_valid = hidden_mreq_valid && hidden_mreq_reg_wen &&
        (hidden_mreq_rd != 5'b0) && (hidden_mreq_datatoreg == 2'b00) &&
        (hidden_mreq_mem_wr == 2'b00) && (hidden_mreq_csr_wen == 2'b00);
    assign ws_alu_fwd_valid = commit_side_effect && ws_reg_wen && (ws_rd != 5'b0) &&
        (ws_stat_datatoreg == 2'b00) && !ws_exc_valid;
    assign ws_load_fwd_valid =
`ifdef NPC_LSU_LOAD_BYPASS
        commit_side_effect && ws_reg_wen && (ws_rd != 5'b0) &&
        (ws_stat_datatoreg == 2'b01) && !ws_exc_valid &&
        !ws_is_atomic_instr;
`else
        1'b0;
`endif
    assign fast_mul_resp_wb = commit_side_effect && ws_fast_mul_stat && !ws_exc_valid;
    assign fast_mul_flush_drop_pipe =
        (flush_mem && ms_fast_mul_stat) ||
        ((trap_redirect_valid || fencei_start || fencei_maint_active) && ws_fast_mul_stat);
    // Preserve load late-result same-cycle forwarding from MS when memory
    // response is accepted this cycle (ms_to_ws_valid). This avoids adding an
    // extra load-use bubble while still keeping EX input hold registers.
    assign ms_fwd_valid = ms_load_late_fwd_valid || ms_nonload_fwd_valid;
    assign ms_fwd_data =
        (ms_datatoreg == 2'b00) ? ms_aluout :
        (ms_datatoreg == 2'b01) ? ms_load_data_ext :
        ms_csr_read_data;

    // Redirect priority is intentionally top-owned: trap/xret first, then
    // fence.i/sfence maintenance, then EX branch redirect. Wrapper cleanup must
    // not reorder these valid/ready or flush gates.
    assign ex_redirect_fire = ex_mispredict_flush_valid && !ex_redirect_seen_r;
    assign redirect_flush_valid = trap_redirect_valid || fencei_start || vm_flush_start || ex_redirect_fire;
    wire [31:0] redirect_flush_pc =
        trap_redirect_valid ? trap_redirect_pc :
        ((fencei_start || vm_flush_start) ? ws_nextpc : ex_mispredict_flush_pc);
    assign ds_to_es_fire = ds_to_es_valid && !redirect_flush_valid && !redirect_clear_valid && !stop_clear_valid;
    // FPGA timing note:
    // Redirects still update IF immediately, but ID is cleared from a registered
    // event. The same-cycle redirect gate above prevents the wrong-path ID
    // instruction from entering EX while cutting the EX-compare -> ID-valid path.
    //
    // ebreak only needs to stop and clear younger instructions. Register
    // the stop clear sideband so ID decode does not feed IF next_fetch_pc in the
    // same cycle on FPGA.
    assign stop_clear_set = ds_to_es_fire && es_allowin && ds_is_ebreak;
    assign pipe_clear_valid = redirect_clear_valid || stop_clear_valid;
    wire flush_id = pipe_clear_valid || trap_redirect_valid || fencei_start || vm_flush_start || fencei_maint_active;
    wire flush_ex = trap_redirect_valid || fencei_start || vm_flush_start || fencei_maint_active;
    wire flush_mem = trap_redirect_valid || fencei_start || vm_flush_start || fencei_maint_active;
    assign stop_fetch =
`ifndef NPC_USE_DPI
        cpu_halted ||
`endif
        ds_stop_fetch ||
        (es_valid && es_is_ebreak) ||
        (ms_valid && ms_is_ebreak) ||
        (ws_valid && ws_is_ebreak);

    always @(posedge clk) begin
        if (!rst_n) begin
            store_buffer_fence_drain_wait_core_count <= 64'd0;
        end else if (store_buffer_drain_before_maint) begin
            store_buffer_fence_drain_wait_core_count <= store_buffer_fence_drain_wait_core_count + 64'd1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ex_redirect_seen_r <= 1'b0;
        end else if (flush_ex || !es_valid || es_allowin) begin
            ex_redirect_seen_r <= 1'b0;
        end else if (ex_redirect_fire) begin
            ex_redirect_seen_r <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            redirect_clear_valid <= 1'b0;
            stop_clear_valid <= 1'b0;
            fencei_state_r <= FENCEI_IDLE;
            fencei_commit_pending_r <= 1'b0;
            fencei_commit_pc_r <= 32'b0;
            fencei_commit_instr_r <= 32'b0;
            fencei_commit_nextpc_r <= 32'b0;
        end else begin
            redirect_clear_valid <= redirect_flush_valid;
            stop_clear_valid <= stop_clear_set;
            if (fencei_start) begin
                fencei_commit_pending_r <= 1'b1;
                fencei_commit_pc_r <= ws_pc;
                fencei_commit_instr_r <= ws_instr;
                fencei_commit_nextpc_r <= ws_nextpc;
            end
            case (fencei_state_r)
                FENCEI_IDLE: begin
                    if (cache_maint_start) fencei_state_r <= FENCEI_WAIT_DCACHE;
                end
                FENCEI_WAIT_DCACHE: begin
                    if (dcache_maint_flush_done) fencei_state_r <= FENCEI_WAIT_ICACHE;
                end
                FENCEI_WAIT_ICACHE: begin
                    if (icache_maint_inv_done) begin
                        fencei_state_r <= FENCEI_IDLE;
                        fencei_commit_pending_r <= 1'b0;
                    end
                end
                default: fencei_state_r <= FENCEI_IDLE;
            endcase
        end
    end

    assign rf_wdata = ws_rf_wdata;
    assign rf_waddr = ws_rd;
    assign rf_wen = commit_side_effect && ws_reg_wen;

    assign csr_wdata1 = ws_csr_wdata1;
    assign csr_waddr1 = ws_csr_waddr1;
    assign csr_wdata2 = ws_csr_wdata2;
    assign csr_waddr2 = ws_csr_waddr2;
    assign csr_wen_eff = commit_side_effect ? ws_csr_wen : 2'b00;

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

    wire irq_pending_1  = csr_mip[1]  & csr_mie[1];
    wire irq_pending_3  = csr_mip[3]  & csr_mie[3];
    wire irq_pending_5  = csr_mip[5]  & csr_mie[5];
    wire irq_pending_7  = csr_mip[7]  & csr_mie[7];
    wire irq_pending_9  = csr_mip[9]  & csr_mie[9];
    wire irq_pending_11 = csr_mip[11] & csr_mie[11];
    wire irq_pending_13 = csr_mip[13] & csr_mie[13];

    function irq_can_take;
        input [1:0] cur_priv;
        input [31:0] cur_mstatus;
        input [31:0] cur_mideleg;
        input [4:0] irq_no;
        reg delegated;
        begin
            delegated = cur_mideleg[irq_no];
            if (!delegated) begin
                irq_can_take = (cur_priv < 2'b11) || ((cur_priv == 2'b11) && cur_mstatus[3]);
            end else begin
                irq_can_take = (cur_priv < 2'b01) || ((cur_priv == 2'b01) && cur_mstatus[1]);
            end
        end
    endfunction

    wire irq_deliver_11 = irq_pending_11 && irq_can_take(priv_state, csr_mstatus, csr_mideleg, 5'd11);
    wire irq_deliver_3  = irq_pending_3  && irq_can_take(priv_state, csr_mstatus, csr_mideleg, 5'd3);
    wire irq_deliver_7  = irq_pending_7  && irq_can_take(priv_state, csr_mstatus, csr_mideleg, 5'd7);
    wire irq_deliver_9  = irq_pending_9  && irq_can_take(priv_state, csr_mstatus, csr_mideleg, 5'd9);
    wire irq_deliver_1  = irq_pending_1  && irq_can_take(priv_state, csr_mstatus, csr_mideleg, 5'd1);
    wire irq_deliver_5  = irq_pending_5  && irq_can_take(priv_state, csr_mstatus, csr_mideleg, 5'd5);
    wire irq_deliver_13 = irq_pending_13 && irq_can_take(priv_state, csr_mstatus, csr_mideleg, 5'd13);
    wire async_irq_valid = irq_deliver_11 || irq_deliver_3 || irq_deliver_7 ||
        irq_deliver_9 || irq_deliver_1 || irq_deliver_5 || irq_deliver_13;
    wire [4:0] async_irq_no =
        irq_deliver_11 ? 5'd11 :
        irq_deliver_3  ? 5'd3 :
        irq_deliver_7  ? 5'd7 :
        irq_deliver_9  ? 5'd9 :
        irq_deliver_1  ? 5'd1 :
        irq_deliver_5  ? 5'd5 :
        irq_deliver_13 ? 5'd13 :
        5'd0;
    wire [31:0] async_irq_cause = {1'b1, 26'b0, async_irq_no};

    // TrapCtrl decides trap/xret redirects and privilege updates. PrivCsrRegs
    // owns architectural CSR state; wrappers consume the resulting sideband.
    TrapCtrl u_trap_ctrl(
        .commit_pc(ws_pc),
        .commit_instr(ws_instr),
        .commit_valid(ws_valid),
        .commit_illegal(ws_illegal),
        .commit_exc_valid(ws_exc_valid),
        .commit_exc_cause(ws_exc_cause),
        .commit_exc_tval(ws_exc_tval),
        .commit_is_ebreak(commit_is_ebreak),
        .priv_i(priv_state),
        .mstatus_i(csr_mstatus),
        .mtvec_i(csr_mtvec),
        .stvec_i(csr_stvec),
        .mepc_i(csr_mepc),
        .sepc_i(csr_sepc),
        .medeleg_i(csr_medeleg),
        .mideleg_i(csr_mideleg),
        .mie_i(csr_mie),
        .mip_i(csr_mip),
        .mcounteren_i(csr_mcounteren),
        .scounteren_i(csr_scounteren),
        .async_irq_valid(async_irq_valid && !ws_has_mem_side_effect),
        .async_irq_cause(async_irq_cause),
        .async_irq_tval(32'b0),
        .trap_kill_side_effect(trap_kill_side_effect),
        .trap_redirect_valid(trap_redirect_valid),
        .trap_redirect_async(trap_redirect_async),
        .trap_redirect_pc(trap_redirect_pc),
        .priv_upd_we(priv_upd_we),
        .priv_upd_priv_we(priv_upd_priv_we),
        .priv_upd_priv(priv_upd_priv),
        .priv_upd_mstatus_we(priv_upd_mstatus_we),
        .priv_upd_mstatus(priv_upd_mstatus),
        .priv_upd_mepc_we(priv_upd_mepc_we),
        .priv_upd_mepc(priv_upd_mepc),
        .priv_upd_mcause_we(priv_upd_mcause_we),
        .priv_upd_mcause(priv_upd_mcause),
        .priv_upd_mtval_we(priv_upd_mtval_we),
        .priv_upd_mtval(priv_upd_mtval),
        .priv_upd_sepc_we(priv_upd_sepc_we),
        .priv_upd_sepc(priv_upd_sepc),
        .priv_upd_scause_we(priv_upd_scause_we),
        .priv_upd_scause(priv_upd_scause),
        .priv_upd_stval_we(priv_upd_stval_we),
        .priv_upd_stval(priv_upd_stval),
        .commit_is_unsupported_csr(ws_is_unsupported_csr)
    );

    PrivCsrRegs #(12, 32) csrf(
        .clk(clk),
        .rst_n(rst_n),
        .raddr1(csr_raddr),
        .rdata1(csr_rdata),
        .raddr1_illegal(csr_raddr_illegal),
        .wdata1(csr_wdata1),
        .waddr1(csr_waddr1),
        .waddr1_illegal(csr_waddr1_illegal),
        .wdata2(csr_wdata2),
        .waddr2(csr_waddr2),
        .waddr2_illegal(csr_waddr2_illegal),
        .wen(csr_wen_eff),
        .commit_valid(csr_commit_valid),
        .commit_instr(csr_commit_instr),
        .commit_exception(csr_commit_exception),
        .time_value_i(timer_time_value),
        .timer_mtip_i(timer_mtip),
        .priv_upd_we(priv_upd_we),
        .priv_upd_priv_we(priv_upd_priv_we),
        .priv_upd_priv(priv_upd_priv),
        .priv_upd_mstatus_we(priv_upd_mstatus_we),
        .priv_upd_mstatus(priv_upd_mstatus),
        .priv_upd_mepc_we(priv_upd_mepc_we),
        .priv_upd_mepc(priv_upd_mepc),
        .priv_upd_mcause_we(priv_upd_mcause_we),
        .priv_upd_mcause(priv_upd_mcause),
        .priv_upd_mtval_we(priv_upd_mtval_we),
        .priv_upd_mtval(priv_upd_mtval),
        .priv_upd_sepc_we(priv_upd_sepc_we),
        .priv_upd_sepc(priv_upd_sepc),
        .priv_upd_scause_we(priv_upd_scause_we),
        .priv_upd_scause(priv_upd_scause),
        .priv_upd_stval_we(priv_upd_stval_we),
        .priv_upd_stval(priv_upd_stval),
        .priv_o(priv_state),
        .mstatus_o(csr_mstatus),
        .mtvec_o(csr_mtvec),
        .stvec_o(csr_stvec),
        .mepc_o(csr_mepc),
        .sepc_o(csr_sepc),
        .mcause_o(csr_mcause),
        .scause_o(csr_scause),
        .medeleg_o(csr_medeleg),
        .mideleg_o(csr_mideleg),
        .mie_o(csr_mie),
        .mip_o(csr_mip),
        .mcounteren_o(csr_mcounteren),
        .scounteren_o(csr_scounteren),
        .satp_o(csr_satp)
    );

`ifdef NPC_PRIV_DEBUG
    reg privdbg_reset_printed;
    reg privdbg_seen_s_commit;
    wire privdbg_csr_satp_write = ws_valid && (csr_wen_eff != 2'b00) && (csr_waddr1 == 12'h180);
    wire privdbg_sfence_vma = ws_valid && (ws_instr == 32'h12000073);
    wire privdbg_mret = ws_valid && ws_is_mret;
    wire privdbg_page_fault = ws_valid && ws_exc_valid &&
        ((ws_exc_cause == 32'd12) || (ws_exc_cause == 32'd13) || (ws_exc_cause == 32'd15));
    wire privdbg_first_s_commit = ws_valid && !privdbg_seen_s_commit && (priv_state == 2'b01);

    always @(posedge clk) begin
        if (!rst_n) begin
            privdbg_reset_printed <= 1'b0;
            privdbg_seen_s_commit <= 1'b0;
        end else begin
            if (!privdbg_reset_printed) begin
                $display("[PrivDbg] pc=0x%08x instr=0x%08x priv=%0d satp=0x%08x mstatus=0x%08x mepc=0x%08x sepc=0x%08x mcause=0x%08x scause=0x%08x event=reset",
                    RESET_VECTOR, 32'h00000000, priv_state, csr_satp, csr_mstatus,
                    csr_mepc, csr_sepc, csr_mcause, csr_scause);
                privdbg_reset_printed <= 1'b1;
            end

            if (privdbg_csr_satp_write) begin
                $display("[PrivDbg] pc=0x%08x instr=0x%08x priv=%0d satp=0x%08x satp_wdata=0x%08x mstatus=0x%08x mepc=0x%08x sepc=0x%08x mcause=0x%08x scause=0x%08x event=csrw_satp",
                    ws_pc, ws_instr, priv_state, csr_satp, ws_csr_wdata1, csr_mstatus,
                    csr_mepc, csr_sepc, csr_mcause, csr_scause);
            end

            if (privdbg_sfence_vma) begin
                $display("[PrivDbg] pc=0x%08x instr=0x%08x priv=%0d satp=0x%08x mstatus=0x%08x mepc=0x%08x sepc=0x%08x mcause=0x%08x scause=0x%08x event=sfence_vma",
                    ws_pc, ws_instr, priv_state, csr_satp, csr_mstatus,
                    csr_mepc, csr_sepc, csr_mcause, csr_scause);
            end

            if (privdbg_mret) begin
                $display("[PrivDbg] pc=0x%08x instr=0x%08x priv=%0d satp=0x%08x mstatus=0x%08x mpp=%0d mepc=0x%08x sepc=0x%08x mcause=0x%08x scause=0x%08x event=mret",
                    ws_pc, ws_instr, priv_state, csr_satp, csr_mstatus, csr_mstatus[12:11],
                    csr_mepc, csr_sepc, csr_mcause, csr_scause);
            end

            if (privdbg_first_s_commit) begin
                $display("[PrivDbg] pc=0x%08x instr=0x%08x priv=%0d satp=0x%08x mstatus=0x%08x mepc=0x%08x sepc=0x%08x mcause=0x%08x scause=0x%08x event=first_s_commit",
                    ws_pc, ws_instr, priv_state, csr_satp, csr_mstatus,
                    csr_mepc, csr_sepc, csr_mcause, csr_scause);
                privdbg_seen_s_commit <= 1'b1;
            end

            if (privdbg_page_fault) begin
                $display("[PrivDbg] pc=0x%08x instr=0x%08x priv=%0d satp=0x%08x mstatus=0x%08x tval=0x%08x cause=0x%08x mepc=0x%08x sepc=0x%08x mcause=0x%08x scause=0x%08x event=page_fault",
                    ws_pc, ws_instr, priv_state, csr_satp, csr_mstatus, ws_exc_tval,
                    ws_exc_cause, csr_mepc, csr_sepc, csr_mcause, csr_scause);
            end

            if (ws_valid && commit_is_ebreak) begin
                $display("[PrivDbg] pc=0x%08x instr=0x%08x priv=%0d satp=0x%08x mstatus=0x%08x mepc=0x%08x sepc=0x%08x mcause=0x%08x scause=0x%08x event=ebreak",
                    ws_pc, ws_instr, priv_state, csr_satp, csr_mstatus,
                    csr_mepc, csr_sepc, csr_mcause, csr_scause);
            end
        end
    end
`endif

    assign ibus_req_vaddr_w = ibus_req_addr_w;
    assign dbus_req_vaddr = dbus_req_addr;
    assign ibus_mem_req_paddr = ibus_mem_req_addr;

    // CpuCorePipeline owns only IF/ID/EX/MEM/WB stage instances. Top-level
    // glue still composes redirect/flush, fence maintenance, CSR/trap sideband,
    // register-file ownership, and predictor update policy.
    CpuCorePipeline #(
        .BPU_BTB_ENTRIES(BPU_BTB_ENTRIES),
        .BPU_BHT_ENTRIES(BPU_BHT_ENTRIES),
        .BPU_BHR_BITS(BPU_BHR_BITS),
        .RESET_VECTOR(RESET_VECTOR)
    ) u_core_pipeline(
        .clk(clk),
        .rst_n(rst_n),
        .ds_allowin(ds_allowin),
        .stop_fetch(stop_fetch),
        .store_buffer_drain_before_maint(store_buffer_drain_before_maint),
        .hold_fetch(fencei_start || fencei_maint_active || fencei_commit_pending_r),
        .redirect_flush_valid(redirect_flush_valid),
        .stop_clear_valid(stop_clear_valid),
        .redirect_flush_pc(redirect_flush_pc),
        .bpu_update_valid(bpu_update_valid),
        .es_pc(es_pc),
        .bpu_update_is_cond(bpu_update_is_cond),
        .ex_branch_taken_actual(ex_branch_taken_actual),
        .es_nextpc(es_nextpc),
        .ex_branch_pred_pht_idx(ex_branch_pred_pht_idx),
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_pc(fs_pc),
        .fs_instr(fs_instr),
        .fs_exc_valid(fs_exc_valid),
        .fs_exc_cause(fs_exc_cause),
        .fs_exc_tval(fs_exc_tval),
        .fs_pred_taken(fs_pred_taken),
        .fs_pred_target(fs_pred_target),
        .fs_pred_btb_hit(fs_pred_btb_hit),
        .fs_pred_btb_is_cond(fs_pred_btb_is_cond),
        .fs_pred_bht_state(fs_pred_bht_state),
        .fs_pred_pht_idx(fs_pred_pht_idx),
        .if_stall(if_stall),
        .ibus_req_valid_w(ibus_req_valid_w),
        .ibus_req_ready(ibus_req_ready),
        .ibus_req_addr_w(ibus_req_addr_w),
        .ibus_req_pred_taken(ibus_req_pred_taken),
        .ibus_req_pred_target(ibus_req_pred_target),
        .ibus_req_pred_btb_hit(ibus_req_pred_btb_hit),
        .ibus_req_pred_btb_is_cond(ibus_req_pred_btb_is_cond),
        .ibus_req_pred_bht_state(ibus_req_pred_bht_state),
        .ibus_req_pred_pht_idx(ibus_req_pred_pht_idx),
        .ibus_resp_valid(ibus_resp_valid),
        .ibus_resp_ready_w(ibus_resp_ready_w),
        .ibus_resp_data(ibus_resp_data),
        .ibus_resp_exc_valid(ibus_resp_exc_valid),
        .ibus_resp_exc_cause(ibus_resp_exc_cause),
        .ibus_resp_exc_tval(ibus_resp_exc_tval),
        .if_stat_fs_valid(if_stat_fs_valid),
        .if_stat_queue_count(if_stat_queue_count),
        .if_stat_fetch_room(if_stat_fetch_room),
        .if_stat_req_fire(if_stat_req_fire),
        .if_stat_resp_fire(if_stat_resp_fire),
        .if_stat_resp_accept(if_stat_resp_accept),
        .if_stat_resp_drop(if_stat_resp_drop),
        .if_stat_bypass_direct(if_stat_bypass_direct),
        .if_stat_waiting_resp(if_stat_waiting_resp),
        .if_stat_drop_resp(if_stat_drop_resp),
        .if_stat_fs_pop(if_stat_fs_pop),
        .if_stat_resp_enq(if_stat_resp_enq),
        .if_stat_queue_full(if_stat_queue_full),
        .if_stat_resp_block(if_stat_resp_block),
        .ibus_resp_pc(ibus_resp_pc),
        .ibus_resp_seq(ibus_resp_seq),
        .ibus_resp_epoch(ibus_resp_epoch),
        .ibus_resp_pred_taken(ibus_resp_pred_taken),
        .ibus_resp_pred_target(ibus_resp_pred_target),
        .ibus_resp_pred_btb_hit(ibus_resp_pred_btb_hit),
        .ibus_resp_pred_btb_is_cond(ibus_resp_pred_btb_is_cond),
        .ibus_resp_pred_bht_state(ibus_resp_pred_bht_state),
        .ibus_resp_pred_pht_idx(ibus_resp_pred_pht_idx),
        .ex_mispredict_flush_valid(ex_mispredict_flush_valid),
        .branch_stat_fetch_req_valid(branch_stat_fetch_req_valid),
        .branch_stat_fetch_req_pc(branch_stat_fetch_req_pc),
        .branch_stat_fetch_accept_valid(branch_stat_fetch_accept_valid),
        .branch_stat_fetch_accept_pc(branch_stat_fetch_accept_pc),
        .branch_stat_fetch_accept_instr(branch_stat_fetch_accept_instr),
        .branch_stat_fetch_drop_valid(branch_stat_fetch_drop_valid),
        .branch_stat_fetch_drop_redirect(branch_stat_fetch_drop_redirect),
        .branch_stat_fetch_drop_pc(branch_stat_fetch_drop_pc),
        .branch_stat_fetch_drop_instr(branch_stat_fetch_drop_instr),
        .bpu_btb_lookup_count(bpu_btb_lookup_count),
        .bpu_btb_hit_count(bpu_btb_hit_count),
        .bpu_btb_miss_count(bpu_btb_miss_count),
        .bpu_bht_pred_taken_count(bpu_bht_pred_taken_count),
        .bpu_bht_pred_not_taken_count(bpu_bht_pred_not_taken_count),
        .bpu_btb_conflict_count(bpu_btb_conflict_count),
        .bpu_btb_update_count(bpu_btb_update_count),
        .bpu_btb_replace_count(bpu_btb_replace_count),
        .bpu_bht_lookup_count(bpu_bht_lookup_count),
        .bpu_bht_update_count(bpu_bht_update_count),
        .bpu_bht_weak_taken_count(bpu_bht_weak_taken_count),
        .bpu_bht_weak_not_taken_count(bpu_bht_weak_not_taken_count),
        .bpu_bht_strong_taken_count(bpu_bht_strong_taken_count),
        .bpu_bht_strong_not_taken_count(bpu_bht_strong_not_taken_count),
        .bpu_bhr_value(bpu_bhr_value),
        .flush_id(flush_id),
        .es_allowin(es_allowin),
        .ds_to_es_valid(ds_to_es_valid),
        .rf_raddr1(rf_raddr1),
        .rf_rdata1(rf_rdata1),
        .rf_raddr2(rf_raddr2),
        .rf_rdata2(rf_rdata2),
        .csr_raddr(csr_raddr),
        .csr_rdata(csr_rdata),
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
        .ms_alu_fwd_valid(ms_alu_fwd_valid),
        .ms_load_bypass_valid(ms_load_bypass_valid),
        .ms_load_bypass_rd(ms_load_bypass_rd),
        .ws_alu_fwd_valid(ws_alu_fwd_valid),
        .ms_fwd_valid(ms_fwd_valid),
        .ms_fwd_data(ms_fwd_data),
        .ds_pc(ds_pc),
        .ds_instr(ds_instr),
        .ds_exc_valid(ds_exc_valid),
        .ds_exc_cause(ds_exc_cause),
        .ds_exc_tval(ds_exc_tval),
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
        .ds_pred_btb_hit(ds_pred_btb_hit),
        .ds_pred_btb_is_cond(ds_pred_btb_is_cond),
        .ds_pred_bht_state(ds_pred_bht_state),
        .ds_pred_pht_idx(ds_pred_pht_idx),
        .ds_imm(ds_imm),
        .ds_zimm(ds_zimm),
        .ds_scsr(ds_scsr),
        .ds_rd(ds_rd),
        .ds_reg_wen(ds_reg_wen),
        .ds_branch(ds_branch),
        .ds_datatoreg(ds_datatoreg),
        .ds_mem_wr(ds_mem_wr),
        .ds_mem_op(ds_mem_op),
        .ds_atomic_en(ds_atomic_en),
        .ds_atomic_op(ds_atomic_op),
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
        .ds_stage_block(ds_stage_block),
        .ds_stage_block_reg_hazard(ds_stage_block_reg_hazard),
        .ds_stage_block_csr_hazard(ds_stage_block_csr_hazard),
        .ds_stage_block_load_use(ds_stage_block_load_use),
        .ds_stage_block_ex_raw(ds_stage_block_ex_raw),
        .ds_stage_block_ms_raw(ds_stage_block_ms_raw),
        .ds_stage_block_hidden_raw(ds_stage_block_hidden_raw),
        .ds_stat_uses_rs1(ds_stat_uses_rs1),
        .ds_stat_uses_rs2(ds_stat_uses_rs2),
        .ds_stat_rs1_match_es(ds_stat_rs1_match_es),
        .ds_stat_rs1_match_ms(ds_stat_rs1_match_ms),
        .ds_stat_rs1_match_hidden(ds_stat_rs1_match_hidden),
        .ds_stat_rs1_match_ws(ds_stat_rs1_match_ws),
        .ds_stat_rs2_match_es(ds_stat_rs2_match_es),
        .ds_stat_rs2_match_ms(ds_stat_rs2_match_ms),
        .ds_stat_rs2_match_hidden(ds_stat_rs2_match_hidden),
        .ds_stat_rs2_match_ws(ds_stat_rs2_match_ws),
        .ds_stat_csr_counter_hazard(ds_stat_csr_counter_hazard),
        .ds_stat_rs1_ex_alu_fwd(ds_stat_rs1_ex_alu_fwd),
        .ds_stat_rs2_ex_alu_fwd(ds_stat_rs2_ex_alu_fwd),
        .ds_stat_fwd_load_block(ds_stat_fwd_load_block),
        .ds_stat_fwd_csr_block(ds_stat_fwd_csr_block),
        .ds_stat_fwd_kill_block(ds_stat_fwd_kill_block),
`ifdef NPC_M_EXTENSION
        .ds_mdu_en(ds_mdu_en),
        .ds_mdu_op(ds_mdu_op),
`else
        .ds_mdu_en_dummy(ds_mdu_en_dummy),
        .ds_mdu_op_dummy(ds_mdu_op_dummy),
`endif
        .flush_ex(flush_ex),
        .ds_to_es_fire(ds_to_es_fire),
        .ms_allowin(ms_allowin),
        .es_to_ms_valid(es_to_ms_valid),
        .ws_rf_wdata(ws_rf_wdata),
        .ms_aluout(ms_aluout),
        .ms_fast_mul_stat(ms_fast_mul_stat),
        .ms_load_bypass_data(ms_load_bypass_data),
        .hidden_alu_fwd_valid(hidden_alu_fwd_valid),
        .hidden_mreq_aluout(hidden_mreq_aluout),
        .hidden_mreq_fast_mul_stat(hidden_mreq_fast_mul_stat),
        .ws_load_fwd_valid(ws_load_fwd_valid),
        .ws_fast_mul_stat(ws_fast_mul_stat),
        .es_instr(es_instr),
        .es_datatoreg(es_datatoreg),
        .es_mem_wr(es_mem_wr),
        .es_mem_op(es_mem_op),
        .es_atomic_en(es_atomic_en),
        .es_atomic_op(es_atomic_op),
        .es_aluout(es_aluout),
        .es_mem_wdata(es_mem_wdata),
        .es_csr_read_data(es_csr_read_data),
        .es_csr_wdata1(es_csr_wdata1),
        .es_csr_wdata2(es_csr_wdata2),
        .es_illegal(es_illegal),
        .es_exc_valid(es_exc_valid),
        .es_exc_cause(es_exc_cause),
        .es_exc_tval(es_exc_tval),
        .es_is_ebreak(es_is_ebreak),
        .es_branch(es_branch),
        .es_src1_value(es_src1_value),
        .es_mem_fwd_dep(es_mem_fwd_dep),
        .atomic_alu_ready(atomic_alu_ready),
        .atomic_alu_req_valid(atomic_alu_req_valid),
        .atomic_alu_op(atomic_alu_op),
        .atomic_alu_old(atomic_alu_old),
        .atomic_alu_rs2(atomic_alu_rs2),
        .atomic_alu_resp_valid(atomic_alu_resp_valid),
        .atomic_alu_result(atomic_alu_result),
        .es_stage_block(es_stage_block),
        .es_stage_block_mdu_wait(es_stage_block_mdu_wait),
        .es_stage_block_redirect_wait(es_stage_block_redirect_wait),
        .es_stat_is_mdu(es_stat_is_mdu),
        .es_stat_rs1_mem_alu_fwd(es_stat_rs1_mem_alu_fwd),
        .es_stat_rs2_mem_alu_fwd(es_stat_rs2_mem_alu_fwd),
        .es_stat_rs1_wb_fwd(es_stat_rs1_wb_fwd),
        .es_stat_rs2_wb_fwd(es_stat_rs2_wb_fwd),
        .es_stat_rs1_load_fwd(es_stat_rs1_load_fwd),
        .es_stat_rs2_load_fwd(es_stat_rs2_load_fwd),
        .es_stat_mdu_op(es_stat_mdu_op),
        .es_stat_mdu_req_fire(es_stat_mdu_req_fire),
        .es_stat_mdu_resp_valid(es_stat_mdu_resp_valid),
        .es_stat_mdu_busy(es_stat_mdu_busy),
        .es_stat_mdu_result_ready(es_stat_mdu_result_ready),
        .es_stat_fast_mul(es_stat_fast_mul),
        .es_stat_fast_mul_issue(es_stat_fast_mul_issue),
        .es_stat_fast_mul_resp_unused(es_stat_fast_mul_resp_unused),
        .es_stat_fast_mul_kill(es_stat_fast_mul_kill),
        .es_stat_fast_mul_flush_drop(es_stat_fast_mul_flush_drop),
        .es_stat_fast_mul_forward(es_stat_fast_mul_forward),
        .es_stat_fast_mul_stall_wait_ready(es_stat_fast_mul_stall_wait_ready),
        .es_stat_old_div_path(es_stat_old_div_path),
        .es_stat_old_rem_path(es_stat_old_rem_path),
        .ex_flush_valid(ex_flush_valid),
        .ex_flush_pc(ex_flush_pc),
        .ex_mispredict_flush_pc(ex_mispredict_flush_pc),
        .ex_branch_pred_taken(ex_branch_pred_taken),
        .ex_branch_pred_target(ex_branch_pred_target),
        .ex_branch_pred_btb_hit(ex_branch_pred_btb_hit),
        .ex_branch_pred_btb_is_cond(ex_branch_pred_btb_is_cond),
        .ex_branch_pred_bht_state(ex_branch_pred_bht_state),
        .ex_branch_target_mismatch(ex_branch_target_mismatch),
        .flush_mem(flush_mem),
        .ws_allowin(ws_allowin),
        .ms_to_ws_valid(ms_to_ws_valid),
        .es_fast_mul_stat_to_mem(es_fast_mul_stat_to_mem),
        .ms_pc(ms_pc),
        .ms_instr(ms_instr),
        .ms_nextpc(ms_nextpc),
        .ms_datatoreg(ms_datatoreg),
        .ms_mem_op(ms_mem_op),
        .ms_mem_rdata(ms_mem_rdata),
        .ms_csr_read_data(ms_csr_read_data),
        .ms_csr_wdata1(ms_csr_wdata1),
        .ms_csr_wdata2(ms_csr_wdata2),
        .ms_illegal(ms_illegal),
        .ms_exc_valid(ms_exc_valid),
        .ms_exc_cause(ms_exc_cause),
        .ms_exc_tval(ms_exc_tval),
        .ms_is_ebreak(ms_is_ebreak),
        .ms_branch(ms_branch),
        .ms_src1_value(ms_src1_value),
        .ms_stage_block(ms_stage_block),
        .ms_stage_block_req_phase(ms_stage_block_req_phase),
        .ms_stage_block_resp_phase(ms_stage_block_resp_phase),
        .ms_stage_block_load(ms_stage_block_load),
        .ms_stage_block_store(ms_stage_block_store),
        .ms_stage_block_req_load(ms_stage_block_req_load),
        .ms_stage_block_req_store(ms_stage_block_req_store),
        .ms_stage_block_resp_load(ms_stage_block_resp_load),
        .ms_stage_block_resp_store(ms_stage_block_resp_store),
        .ms_fast_req_fire_trace(ms_fast_req_fire_trace),
        .ms_slow_req_fire_trace(ms_slow_req_fire_trace),
        .ms_slow_req_fwd_dep_fire_trace(ms_slow_req_fwd_dep_fire_trace),
        .ms_slow_req_nonfwd_fire_trace(ms_slow_req_nonfwd_fire_trace),
        .ms_stat_load_visible(ms_stat_load_visible),
        .ms_stat_load_aligned(ms_stat_load_aligned),
        .ms_stat_load_result_ready(ms_stat_load_result_ready),
        .ms_stat_load_fault(ms_stat_load_fault),
        .ms_stat_load_signext_ready(ms_stat_load_signext_ready),
        .ms_stat_load_req_fire(ms_stat_load_req_fire),
        .ms_stat_load_resp_valid(ms_stat_load_resp_valid),
        .ms_stat_load_resp_fire(ms_stat_load_resp_fire),
        .ms_stat_load_data_ready(ms_stat_load_data_ready),
        .ms_stat_load_signext_data_ready(ms_stat_load_signext_data_ready),
        .ms_stat_load_to_wb_valid(ms_stat_load_to_wb_valid),
        .ms_stat_load_split_or_misaligned(ms_stat_load_split_or_misaligned),
        .ms_stat_load_uncached(ms_stat_load_uncached),
        .ms_stat_load_atomic(ms_stat_load_atomic),
        .ms_stat_load_killed(ms_stat_load_killed),
        .ms_stat_hidden_load(ms_stat_hidden_load),
        .ms_stat_load_store_block(ms_stat_load_store_block),
        .ms_stat_load_lsu_pending(ms_stat_load_lsu_pending),
        .ms_stat_mreq_valid(ms_stat_mreq_valid),
        .ms_stat_mreq_is_load(ms_stat_mreq_is_load),
        .ms_stat_mreq_is_store(ms_stat_mreq_is_store),
        .ms_stat_mreq_is_atomic(ms_stat_mreq_is_atomic),
        .ms_stat_mreq_need_mem(ms_stat_mreq_need_mem),
        .ms_stat_mreq_fire(ms_stat_mreq_fire),
        .ms_stat_mreq_misaligned(ms_stat_mreq_misaligned),
        .ms_stat_mreq_split(ms_stat_mreq_split),
        .ms_stat_mreq_fault(ms_stat_mreq_fault),
        .ms_stat_mreq_blocked_by_resp(ms_stat_mreq_blocked_by_resp),
        .ms_stat_mresp_valid(ms_stat_mresp_valid),
        .ms_stat_mresp_is_load(ms_stat_mresp_is_load),
        .ms_stat_mresp_is_store(ms_stat_mresp_is_store),
        .ms_stat_mresp_is_atomic(ms_stat_mresp_is_atomic),
        .ms_stat_mresp_resp_valid(ms_stat_mresp_resp_valid),
        .ms_stat_mresp_resp_fire(ms_stat_mresp_resp_fire),
        .ms_stat_mresp_split(ms_stat_mresp_split),
        .ms_stat_mresp_fault(ms_stat_mresp_fault),
        .ms_stat_store_visible(ms_stat_store_visible),
        .ms_stat_store_req_fire(ms_stat_store_req_fire),
        .ms_stat_store_resp_valid(ms_stat_store_resp_valid),
        .ms_stat_store_resp_fire(ms_stat_store_resp_fire),
        .ms_stat_store_aligned(ms_stat_store_aligned),
        .ms_stat_store_fault(ms_stat_store_fault),
        .ms_stat_store_split_or_misaligned(ms_stat_store_split_or_misaligned),
        .ms_stat_store_uncached(ms_stat_store_uncached),
        .ms_stat_store_atomic(ms_stat_store_atomic),
        .ms_stat_store_killed(ms_stat_store_killed),
        .ms_stat_store_buffer_safe(ms_stat_store_buffer_safe),
        .ms_stat_store_resp_wait(ms_stat_store_resp_wait),
        .ms_stat_single_outstanding_wait(ms_stat_single_outstanding_wait),
        .ms_stat_uncached_wait(ms_stat_uncached_wait),
        .ms_stat_writeback_wait(ms_stat_writeback_wait),
        .stat_exmem_skid_candidate(stat_exmem_skid_candidate),
        .stat_exmem_skid_enqueue(stat_exmem_skid_enqueue),
        .stat_exmem_skid_dequeue(stat_exmem_skid_dequeue),
        .stat_exmem_skid_full_stall(stat_exmem_skid_full_stall),
        .stat_exmem_skid_flush_drop(stat_exmem_skid_flush_drop),
        .stat_exmem_skid_blocked_not_safe(stat_exmem_skid_blocked_not_safe),
        .stat_exmem_skid_blocked_branch(stat_exmem_skid_blocked_branch),
        .stat_exmem_skid_blocked_mem(stat_exmem_skid_blocked_mem),
        .stat_exmem_skid_blocked_csr(stat_exmem_skid_blocked_csr),
        .stat_exmem_skid_blocked_exception(stat_exmem_skid_blocked_exception),
        .stat_exmem_skid_blocked_div(stat_exmem_skid_blocked_div),
        .stat_exmem_skid_blocked_structural(stat_exmem_skid_blocked_structural),
        .stat_exmem_skid_hold_cycles(stat_exmem_skid_hold_cycles),
        .stat_exmem_skid_hold_mem_wait_cycles(stat_exmem_skid_hold_mem_wait_cycles),
        .stat_exmem_skid_dequeue_after_mem_release(stat_exmem_skid_dequeue_after_mem_release),
        .stat_exmem_skid_dequeue_same_cycle_mem_release(stat_exmem_skid_dequeue_same_cycle_mem_release),
        .stat_exmem_skid_dequeue_causes_wb_valid(stat_exmem_skid_dequeue_causes_wb_valid),
        .stat_exmem_skid_valid(stat_exmem_skid_valid),
        .stat_exmem_skid_enqueue_fire(stat_exmem_skid_enqueue_fire),
        .stat_exmem_skid_dequeue_fire(stat_exmem_skid_dequeue_fire),
        .stat_exmem_skid_dequeue_commit_fire(stat_exmem_skid_dequeue_commit_fire),
        .stat_exmem_skid_dequeue_to_mreq_fire(stat_exmem_skid_dequeue_to_mreq_fire),
        .stat_exmem_skid_mem_wait(stat_exmem_skid_mem_wait),
        .stat_exmem_skid_mem_release(stat_exmem_skid_mem_release),
        .hidden_mreq_datatoreg(hidden_mreq_datatoreg),
        .hidden_mreq_mem_wr(hidden_mreq_mem_wr),
        .dbus_req_valid(dbus_req_valid),
        .dbus_req_ready(dbus_req_ready),
        .dbus_req_fast_ok(dbus_req_fast_ok),
        .dbus_req_fast_block_atomic(dbus_req_fast_block_atomic),
        .dbus_req_fast_block_misaligned(dbus_req_fast_block_misaligned),
        .dbus_req_fast_block_exception(dbus_req_fast_block_exception),
        .dbus_req_fast_block_phase2(dbus_req_fast_block_phase2),
        .dbus_req_fast_block_other(dbus_req_fast_block_other),
        .dbus_req_write(dbus_req_write),
        .dbus_req_atomic(dbus_req_atomic),
        .dbus_req_store_bufferable(dbus_req_store_bufferable),
        .dbus_req_addr(dbus_req_addr),
        .dbus_req_wdata(dbus_req_wdata),
        .dbus_req_wstrb(dbus_req_wstrb),
        .dbus_req_len(dbus_req_len),
        .dbus_resp_valid(dbus_resp_valid),
        .dbus_resp_ready(dbus_resp_ready),
        .dbus_resp_data(dbus_resp_data),
        .dbus_resp_exc_valid(dbus_resp_exc_valid),
        .dbus_resp_exc_cause(dbus_resp_exc_cause),
        .dbus_resp_exc_tval(dbus_resp_exc_tval),
        .dbg_mem_mreq_valid(dbg_mem_mreq_valid),
        .dbg_mem_mresp_valid(dbg_mem_mresp_valid),
        .dbg_mem_skid_valid(dbg_mem_skid_valid),
        .dbg_mem_mreq_instr(dbg_mem_mreq_instr),
        .dbg_mem_mresp_instr(dbg_mem_mresp_instr),
        .dbg_mem_mreq_need_mem(dbg_mem_mreq_need_mem),
        .dbg_mem_mreq_req_valid(dbg_mem_mreq_req_valid),
        .dbg_mem_mreq_mem_fire(dbg_mem_mreq_mem_fire),
        .dbg_mem_mreq_nonmem_fire(dbg_mem_mreq_nonmem_fire),
        .dbg_mem_mreq_consumed_eff(dbg_mem_mreq_consumed_eff),
        .dbg_mem_mresp_ready_go(dbg_mem_mresp_ready_go),
        .dbg_mem_mresp_commit_fire(dbg_mem_mresp_commit_fire),
        .dbg_mem_old_mreq_allowin(dbg_mem_old_mreq_allowin),
        .dbg_mem_mresp_atomic_en(dbg_mem_mresp_atomic_en),
        .dbg_mem_mresp_split(dbg_mem_mresp_split),
        .dbg_mem_mresp_phase1_amo_read(dbg_mem_mresp_phase1_amo_read),
        .wb_flush(trap_redirect_valid || fencei_start || vm_flush_start || fencei_maint_active),
        .ws_pc(ws_pc),
        .ws_instr(ws_instr),
        .ws_nextpc(ws_nextpc),
        .ws_stat_datatoreg(ws_stat_datatoreg),
        .ws_stat_mem_op(ws_stat_mem_op),
        .ws_csr_wdata1(ws_csr_wdata1),
        .ws_csr_wdata2(ws_csr_wdata2),
        .ws_illegal(ws_illegal),
        .ws_exc_valid(ws_exc_valid),
        .ws_exc_cause(ws_exc_cause),
        .ws_exc_tval(ws_exc_tval),
        .ws_is_ebreak(ws_is_ebreak),
        .ws_branch(ws_branch),
        .ws_src1_value(ws_src1_value)
    );

`ifdef NPC_LSU_HIT_PIPELINE
    // v1 keeps LSU_HIT_PIPELINE as a metadata/stat shell only. Functional
    // D-side access must still go through Sv32DCacheBridge so store buffer,
    // DCACHE_HIT_OPT, AMO ordering, faults, uncached and miss paths agree.
    assign lsu_pipe_issue_count = lsu_mmu_data_req_count;
    assign lsu_pipe_resp_count = lsu_mmu_data_resp_count;
    assign lsu_pipe_epoch_drop_count = 64'b0;
    assign lsu_pipe_dtlb_hit_count = lsu_mmu_tlb_hit_count;
    assign lsu_pipe_dtlb_miss_count = lsu_mmu_tlb_miss_count;
    assign lsu_pipe_replay_count = 64'b0;
    assign lsu_pipe_fault_count = lsu_mmu_page_fault_count;
    assign lsu_pipe_stall_cycle = lsu_mmu_bridge_state_wait_cycle;
    assign lsu_pipe_dcache_hit_count = dhitopt_success_count;
    assign lsu_pipe_dcache_miss_count = dhitopt_block_miss_count;
    assign lsu_pipe_store_hit_count = store_buffer_enqueue_count;
    assign lsu_pipe_load_hit_count = dhitopt_success_count;
    assign lsu_pipe_slow_fallback_count =
        (lsu_mmu_data_req_count >= dhitopt_success_count) ?
        (lsu_mmu_data_req_count - dhitopt_success_count) : 64'b0;
    assign lsu_pipe_load_miss_replay_count = 64'b0;
    assign lsu_pipe_store_miss_replay_count = 64'b0;
    assign lsu_pipe_direct_uncached_count = lsu_mmu_uncached_req_count;
    assign lsu_pipe_direct_non_dtlb_hit_count = lsu_mmu_tlb_miss_count;
    assign lsu_pipe_direct_perm_fault_count = lsu_mmu_page_fault_count;
    assign lsu_pipe_direct_cross_page_count = 64'b0;
    assign lsu_pipe_direct_fast_block_count = 64'b0;
    assign lsu_pipe_direct_fast_block_atomic_count = 64'b0;
    assign lsu_pipe_direct_fast_block_misaligned_count = 64'b0;
    assign lsu_pipe_direct_fast_block_exception_count = 64'b0;
    assign lsu_pipe_direct_fast_block_phase2_count = 64'b0;
    assign lsu_pipe_direct_fast_block_other_count = 64'b0;
    assign lsu_pipe_direct_other_count = 64'b0;
    assign lsu_pipe_hit_latency_sum = 64'b0;
    assign lsu_pipe_hit_latency_count = 64'b0;
    assign lsu_pipe_hit_latency_max = 64'b0;
    assign lsu_pipe_load_hit_latency_sum = 64'b0;
    assign lsu_pipe_load_hit_latency_count = 64'b0;
    assign lsu_pipe_load_hit_latency_max = 64'b0;
    assign lsu_pipe_store_hit_latency_sum = 64'b0;
    assign lsu_pipe_store_hit_latency_count = 64'b0;
    assign lsu_pipe_store_hit_latency_max = 64'b0;
    assign lsu_pipe_slow_fallback_latency_sum = 64'b0;
    assign lsu_pipe_slow_fallback_latency_count = 64'b0;
    assign lsu_pipe_slow_fallback_latency_max = 64'b0;
    assign lsu_pipe_slow_direct_latency_sum = 64'b0;
    assign lsu_pipe_slow_direct_latency_count = 64'b0;
    assign lsu_pipe_slow_direct_latency_max = 64'b0;
    assign lsu_pipe_slow_replay_latency_sum = 64'b0;
    assign lsu_pipe_slow_replay_latency_count = 64'b0;
    assign lsu_pipe_slow_replay_latency_max = 64'b0;
`else
    assign lsu_pipe_issue_count = 64'b0;
    assign lsu_pipe_resp_count = 64'b0;
    assign lsu_pipe_epoch_drop_count = 64'b0;
    assign lsu_pipe_dtlb_hit_count = 64'b0;
    assign lsu_pipe_dtlb_miss_count = 64'b0;
    assign lsu_pipe_replay_count = 64'b0;
    assign lsu_pipe_fault_count = 64'b0;
    assign lsu_pipe_stall_cycle = 64'b0;
    assign lsu_pipe_dcache_hit_count = 64'b0;
    assign lsu_pipe_dcache_miss_count = 64'b0;
    assign lsu_pipe_store_hit_count = 64'b0;
    assign lsu_pipe_load_hit_count = 64'b0;
    assign lsu_pipe_slow_fallback_count = 64'b0;
    assign lsu_pipe_load_miss_replay_count = 64'b0;
    assign lsu_pipe_store_miss_replay_count = 64'b0;
    assign lsu_pipe_direct_uncached_count = 64'b0;
    assign lsu_pipe_direct_non_dtlb_hit_count = 64'b0;
    assign lsu_pipe_direct_perm_fault_count = 64'b0;
    assign lsu_pipe_direct_cross_page_count = 64'b0;
    assign lsu_pipe_direct_fast_block_count = 64'b0;
    assign lsu_pipe_direct_fast_block_atomic_count = 64'b0;
    assign lsu_pipe_direct_fast_block_misaligned_count = 64'b0;
    assign lsu_pipe_direct_fast_block_exception_count = 64'b0;
    assign lsu_pipe_direct_fast_block_phase2_count = 64'b0;
    assign lsu_pipe_direct_fast_block_other_count = 64'b0;
    assign lsu_pipe_direct_other_count = 64'b0;
    assign lsu_pipe_hit_latency_sum = 64'b0;
    assign lsu_pipe_hit_latency_count = 64'b0;
    assign lsu_pipe_hit_latency_max = 64'b0;
    assign lsu_pipe_load_hit_latency_sum = 64'b0;
    assign lsu_pipe_load_hit_latency_count = 64'b0;
    assign lsu_pipe_load_hit_latency_max = 64'b0;
    assign lsu_pipe_store_hit_latency_sum = 64'b0;
    assign lsu_pipe_store_hit_latency_count = 64'b0;
    assign lsu_pipe_store_hit_latency_max = 64'b0;
    assign lsu_pipe_slow_fallback_latency_sum = 64'b0;
    assign lsu_pipe_slow_fallback_latency_count = 64'b0;
    assign lsu_pipe_slow_fallback_latency_max = 64'b0;
    assign lsu_pipe_slow_direct_latency_sum = 64'b0;
    assign lsu_pipe_slow_direct_latency_count = 64'b0;
    assign lsu_pipe_slow_direct_latency_max = 64'b0;
    assign lsu_pipe_slow_replay_latency_sum = 64'b0;
    assign lsu_pipe_slow_replay_latency_count = 64'b0;
    assign lsu_pipe_slow_replay_latency_max = 64'b0;
`endif

    // CpuDmemSubsystem owns the D-side bridge/cache/timer/dbus instances. Top
    // still owns trap/CSR/privilege policy and passes maintenance sideband in.
    CpuDmemSubsystem #(
        .DCACHE_LINE_BYTES(DCACHE_LINE_BYTES),
        .DCACHE_LINE_COUNT(DCACHE_LINE_COUNT),
        .DCACHE_LINE_WORDS(DCACHE_LINE_WORDS),
        .DPI_MEM_LATENCY(DPI_MEM_LATENCY),
        .TIMER_CLK_HZ(TIMER_CLK_HZ),
        .TIMEBASE_HZ(TIMEBASE_HZ)
    ) u_dmem_subsystem (
        .clk(clk),
        .rst_n(rst_n),
        .flush_mem(flush_mem),
        .tlb_flush_all(tlb_flush_all),
        .dcache_maint_flush_req(dcache_maint_flush_req),
        .priv_state(priv_state),
        .csr_mstatus(csr_mstatus),
        .csr_satp(csr_satp),
        .dbus_req_valid(dbus_req_valid),
        .dbus_req_ready(dbus_req_ready),
        .dbus_req_write(dbus_req_write),
        .dbus_req_atomic(dbus_req_atomic),
        .dbus_req_store_bufferable(dbus_req_store_bufferable),
        .dbus_req_addr(dbus_req_addr),
        .dbus_req_wdata(dbus_req_wdata),
        .dbus_req_wstrb(dbus_req_wstrb),
        .dbus_req_len(dbus_req_len),
        .dbus_resp_valid(dbus_resp_valid),
        .dbus_resp_ready(dbus_resp_ready),
        .dbus_resp_data(dbus_resp_data),
        .dbus_resp_exc_valid(dbus_resp_exc_valid),
        .dbus_resp_exc_cause(dbus_resp_exc_cause),
        .dbus_resp_exc_tval(dbus_resp_exc_tval),
        .dbus_req_paddr(dbus_req_paddr),
        .dbus_dcache_req_valid(dbus_dcache_req_valid),
        .dbus_dcache_req_ready(dbus_dcache_req_ready),
        .dbus_dcache_req_write(dbus_dcache_req_write),
        .dbus_dcache_req_len(dbus_dcache_req_len),
        .dbus_dcache_req_is_ptw(dbus_dcache_req_is_ptw),
        .dbus_store_buffer_empty(dbus_store_buffer_empty),
        .dbus_store_buffer_busy(dbus_store_buffer_busy),
        .dbg_dcache_bridge_state(dbg_dcache_bridge_state),
        .dbg_dcache_bridge_drop_resp(dbg_dcache_bridge_drop_resp),
        .dbg_dcache_bridge_req_write(dbg_dcache_bridge_req_write),
        .dbg_dcache_bridge_req_store_bufferable(dbg_dcache_bridge_req_store_bufferable),
        .dbg_dcache_bridge_req_safe_store_bufferable(dbg_dcache_bridge_req_safe_store_bufferable),
        .dbg_dcache_bridge_sbuf0_valid(dbg_dcache_bridge_sbuf0_valid),
        .dbg_dcache_bridge_sbuf1_valid(dbg_dcache_bridge_sbuf1_valid),
        .dbg_dcache_bridge_sbuf0_sent(dbg_dcache_bridge_sbuf0_sent),
        .dbg_dcache_bridge_sbuf1_sent(dbg_dcache_bridge_sbuf1_sent),
        .dbg_dcache_bridge_sbuf_drain_active(dbg_dcache_bridge_sbuf_drain_active),
        .dbg_dcache_bridge_sbuf_drain_resp_pending(dbg_dcache_bridge_sbuf_drain_resp_pending),
        .dbg_dcache_bridge_sbuf_drain_req_valid(dbg_dcache_bridge_sbuf_drain_req_valid),
        .dbg_dcache_bridge_sbuf_drain_grant(dbg_dcache_bridge_sbuf_drain_grant),
        .dbg_dcache_bridge_sbuf_drain_req_fire(dbg_dcache_bridge_sbuf_drain_req_fire),
        .dbg_dcache_bridge_sbuf_drain_resp_fire(dbg_dcache_bridge_sbuf_drain_resp_fire),
        .dbg_dcache_bridge_data_req_fire(dbg_dcache_bridge_data_req_fire),
        .dbg_dcache_bridge_lower_resp_ready(dbg_dcache_bridge_lower_resp_ready),
        .dbg_dcache_bridge_lower_req_valid(dbg_dcache_bridge_lower_req_valid),
        .dbg_dcache_bridge_lower_req_write(dbg_dcache_bridge_lower_req_write),
        .dbg_dcache_bridge_lower_req_addr(dbg_dcache_bridge_lower_req_addr),
        .dbg_dcache_bridge_sbuf_conflict_stall(dbg_dcache_bridge_sbuf_conflict_stall),
        .dbg_dcache_bridge_req_store_buffer_full(dbg_dcache_bridge_req_store_buffer_full),
        .dbg_dcache_bridge_sbuf_forward_hit(dbg_dcache_bridge_sbuf_forward_hit),
        .dcache_maint_flush_done(dcache_maint_flush_done),
        .timer_time_value(timer_time_value),
        .timer_timecmp_value(timer_timecmp_value),
        .timer_step_accum_value(timer_step_accum_value),
        .timer_mtip(timer_mtip),
        .lsu_mmu_req_count(lsu_mmu_req_count),
        .lsu_mmu_bypass_count(lsu_mmu_bypass_count),
        .lsu_mmu_translate_count(lsu_mmu_translate_count),
        .lsu_mmu_ptw_cycle_count(lsu_mmu_ptw_cycle_count),
        .lsu_mmu_ptw_l1_read_count(lsu_mmu_ptw_l1_read_count),
        .lsu_mmu_ptw_l0_read_count(lsu_mmu_ptw_l0_read_count),
        .lsu_mmu_page_fault_count(lsu_mmu_page_fault_count),
        .lsu_mmu_ptw_walk_start_count(lsu_mmu_ptw_walk_start_count),
        .lsu_mmu_ptw_walk_done_count(lsu_mmu_ptw_walk_done_count),
        .lsu_mmu_ptw_walk_fault_count(lsu_mmu_ptw_walk_fault_count),
        .lsu_mmu_tlb_hit_count(lsu_mmu_tlb_hit_count),
        .lsu_mmu_tlb_miss_count(lsu_mmu_tlb_miss_count),
        .lsu_mmu_tlb_hit_to_cache_req_cycle(lsu_mmu_tlb_hit_to_cache_req_cycle),
        .lsu_mmu_cache_req_wait_cycle(lsu_mmu_cache_req_wait_cycle),
        .lsu_mmu_cache_resp_wait_cycle(lsu_mmu_cache_resp_wait_cycle),
        .lsu_mmu_bridge_state_wait_cycle(lsu_mmu_bridge_state_wait_cycle),
        .lsu_mmu_data_req_count(lsu_mmu_data_req_count),
        .lsu_mmu_data_resp_count(lsu_mmu_data_resp_count),
        .lsu_mmu_uncached_req_count(lsu_mmu_uncached_req_count),
        .store_buffer_enqueue_count(store_buffer_enqueue_count),
        .store_buffer_dequeue_count(store_buffer_dequeue_count),
        .store_buffer_full_stall_count(store_buffer_full_stall_count),
        .store_buffer_drain_req_count(store_buffer_drain_req_count),
        .store_buffer_drain_resp_count(store_buffer_drain_resp_count),
        .store_buffer_drain_wait_count(store_buffer_drain_wait_count),
        .store_buffer_load_forward_count(store_buffer_load_forward_count),
        .store_buffer_load_stall_conflict_count(store_buffer_load_stall_conflict_count),
        .store_buffer_load_stall_buffer_nonempty_count(store_buffer_load_stall_buffer_nonempty_count),
        .store_buffer_fence_drain_wait_bridge_count(store_buffer_fence_drain_wait_bridge_count),
        .store_buffer_uncached_drain_wait_count(store_buffer_uncached_drain_wait_count),
        .store_buffer_killed_store_block_count(store_buffer_killed_store_block_count),
        .store_buffer_occupancy0_count(store_buffer_occupancy0_count),
        .store_buffer_occupancy1_count(store_buffer_occupancy1_count),
        .store_buffer_occupancy2_count(store_buffer_occupancy2_count),
        .store_buffer_max_occupancy_count(store_buffer_max_occupancy_count),
        .store_buffer_enqueue_occ0_count(store_buffer_enqueue_occ0_count),
        .store_buffer_enqueue_occ1_count(store_buffer_enqueue_occ1_count),
        .store_buffer_enqueue_full_count(store_buffer_enqueue_full_count),
        .dhitopt_candidate_count(dhitopt_candidate_count),
        .dhitopt_success_count(dhitopt_success_count),
        .dhitopt_fallback_count(dhitopt_fallback_count),
        .dhitopt_block_store_buffer_count(dhitopt_block_store_buffer_count),
        .dhitopt_block_uncached_count(dhitopt_block_uncached_count),
        .dhitopt_block_fault_count(dhitopt_block_fault_count),
        .dhitopt_block_miss_count(dhitopt_block_miss_count),
        .dhitopt_block_alignment_count(dhitopt_block_alignment_count),
        .dhitopt_unknown_count(dhitopt_unknown_count)
`ifdef NPC_USE_DPI
        ,
        .dcache_stat_access(dcache_stat_access),
        .dcache_stat_load_access(dcache_stat_load_access),
        .dcache_stat_store_access(dcache_stat_store_access),
        .dcache_stat_load_hit(dcache_stat_load_hit),
        .dcache_stat_load_miss(dcache_stat_load_miss),
        .dcache_stat_store_hit(dcache_stat_store_hit),
        .dcache_stat_store_miss(dcache_stat_store_miss),
        .dcache_stat_refill_req(dcache_stat_refill_req),
        .dcache_stat_refill_resp(dcache_stat_refill_resp),
        .dcache_stat_write_req(dcache_stat_write_req),
        .dcache_stat_write_resp(dcache_stat_write_resp),
        .dcache_stat_refill_ld_bypass(dcache_stat_refill_ld_bypass),
        .dcache_stat_refill_store_merge(dcache_stat_refill_store_merge),
        .dcache_stat_req_wait_cycle(dcache_stat_req_wait_cycle),
        .dcache_stat_hit_resp_wait_cycle(dcache_stat_hit_resp_wait_cycle),
        .dcache_stat_miss_wait_cycle(dcache_stat_miss_wait_cycle),
        .dcache_stat_uncached_access(dcache_stat_uncached_access),
        .dcache_stat_writeback_cycle(dcache_stat_writeback_cycle)
`endif
        ,
        .dbus_axi_awaddr(dbus_axi_awaddr),
        .dbus_axi_awlen(dbus_axi_awlen),
        .dbus_axi_awsize(dbus_axi_awsize),
        .dbus_axi_awburst(dbus_axi_awburst),
        .dbus_axi_awvalid(dbus_axi_awvalid),
        .dbus_axi_awready(dbus_axi_awready),
        .dbus_axi_wdata(dbus_axi_wdata),
        .dbus_axi_wstrb(dbus_axi_wstrb),
        .dbus_axi_wlast(dbus_axi_wlast),
        .dbus_axi_wvalid(dbus_axi_wvalid),
        .dbus_axi_wready(dbus_axi_wready),
        .dbus_axi_bresp(dbus_axi_bresp),
        .dbus_axi_bvalid(dbus_axi_bvalid),
        .dbus_axi_bready(dbus_axi_bready),
        .dbus_axi_araddr(dbus_axi_araddr),
        .dbus_axi_arlen(dbus_axi_arlen),
        .dbus_axi_arsize(dbus_axi_arsize),
        .dbus_axi_arburst(dbus_axi_arburst),
        .dbus_axi_arvalid(dbus_axi_arvalid),
        .dbus_axi_arready(dbus_axi_arready),
        .dbus_axi_rdata(dbus_axi_rdata),
        .dbus_axi_rresp(dbus_axi_rresp),
        .dbus_axi_rvalid(dbus_axi_rvalid),
        .dbus_axi_rready(dbus_axi_rready),
        .dbus_axi_rlast(dbus_axi_rlast)
    );

    // CpuFrontendSubsystem owns the frontend / I-side structural cluster.
    // Redirect/fence/CSR policy stays in cpu_top and crosses as explicit
    // sideband so wrapper cleanup cannot change priority or timing.
    CpuFrontendSubsystem #(
        .ICACHE_LINE_BYTES(ICACHE_LINE_BYTES),
        .ICACHE_LINE_COUNT(ICACHE_LINE_COUNT)
    ) u_frontend_subsystem (
        .clk(clk),
        .rst_n(rst_n),
        .redirect_flush_valid(redirect_flush_valid),
        .stop_clear_valid(stop_clear_valid),
        .tlb_flush_all(tlb_flush_all),
        .priv_state(priv_state),
        .csr_satp(csr_satp),
        .ibus_req_valid_w(ibus_req_valid_w),
        .ibus_req_ready(ibus_req_ready),
        .ibus_req_addr_w(ibus_req_addr_w),
        .ibus_req_pred_taken(ibus_req_pred_taken),
        .ibus_req_pred_target(ibus_req_pred_target),
        .ibus_req_pred_btb_hit(ibus_req_pred_btb_hit),
        .ibus_req_pred_btb_is_cond(ibus_req_pred_btb_is_cond),
        .ibus_req_pred_bht_state(ibus_req_pred_bht_state),
        .ibus_req_pred_pht_idx(ibus_req_pred_pht_idx),
        .ibus_resp_valid(ibus_resp_valid),
        .ibus_resp_ready_w(ibus_resp_ready_w),
        .ibus_resp_data(ibus_resp_data),
        .ibus_resp_exc_valid(ibus_resp_exc_valid),
        .ibus_resp_exc_cause(ibus_resp_exc_cause),
        .ibus_resp_exc_tval(ibus_resp_exc_tval),
        .ibus_resp_pc(ibus_resp_pc),
        .ibus_resp_seq(ibus_resp_seq),
        .ibus_resp_epoch(ibus_resp_epoch),
        .ibus_resp_pred_taken(ibus_resp_pred_taken),
        .ibus_resp_pred_target(ibus_resp_pred_target),
        .ibus_resp_pred_btb_hit(ibus_resp_pred_btb_hit),
        .ibus_resp_pred_btb_is_cond(ibus_resp_pred_btb_is_cond),
        .ibus_resp_pred_bht_state(ibus_resp_pred_bht_state),
        .ibus_resp_pred_pht_idx(ibus_resp_pred_pht_idx),
        .ibus_icache_pipe_resp_valid(ibus_icache_pipe_resp_valid),
        .ibus_icache_pipe_resp_ready(ibus_icache_pipe_resp_ready),
        .icache_maint_inv_req(icache_maint_inv_req),
        .icache_maint_inv_done(icache_maint_inv_done),
        .ibus_mem_req_valid(ibus_mem_req_valid),
        .ibus_mem_req_ready(ibus_mem_req_ready),
        .ibus_mem_req_write(ibus_mem_req_write),
        .ibus_mem_req_addr(ibus_mem_req_addr),
        .ibus_mem_req_wdata(ibus_mem_req_wdata),
        .ibus_mem_req_wstrb(ibus_mem_req_wstrb),
        .ibus_mem_req_len(ibus_mem_req_len),
        .ibus_mem_resp_valid(ibus_mem_resp_valid),
        .ibus_mem_resp_ready(ibus_mem_resp_ready),
        .ibus_mem_resp_data(ibus_mem_resp_data),
        .if_mmu_req_count(if_mmu_req_count),
        .if_mmu_bypass_count(if_mmu_bypass_count),
        .if_mmu_translate_count(if_mmu_translate_count),
        .if_mmu_ptw_cycle_count(if_mmu_ptw_cycle_count),
        .if_mmu_ptw_l1_read_count(if_mmu_ptw_l1_read_count),
        .if_mmu_ptw_l0_read_count(if_mmu_ptw_l0_read_count),
        .if_mmu_page_fault_count(if_mmu_page_fault_count),
        .if_mmu_ptw_walk_start_count(if_mmu_ptw_walk_start_count),
        .if_mmu_ptw_walk_done_count(if_mmu_ptw_walk_done_count),
        .if_mmu_ptw_walk_fault_count(if_mmu_ptw_walk_fault_count),
        .if_mmu_tlb_hit_count(if_mmu_tlb_hit_count),
        .if_mmu_tlb_miss_count(if_mmu_tlb_miss_count),
        .if_mmu_tlb_hit_to_cache_req_cycle(if_mmu_tlb_hit_to_cache_req_cycle),
        .if_mmu_cache_req_wait_cycle(if_mmu_cache_req_wait_cycle),
        .if_mmu_cache_resp_wait_cycle(if_mmu_cache_resp_wait_cycle),
        .if_mmu_bridge_state_wait_cycle(if_mmu_bridge_state_wait_cycle),
        .if_mmu_fetch_req_count(if_mmu_fetch_req_count),
        .if_mmu_fetch_resp_count(if_mmu_fetch_resp_count),
        .if_pipe_issue_count(if_pipe_issue_count),
        .if_pipe_resp_count(if_pipe_resp_count),
        .if_pipe_epoch_drop_count(if_pipe_epoch_drop_count),
        .if_pipe_replay_count(if_pipe_replay_count),
        .if_pipe_ptw_miss_count(if_pipe_ptw_miss_count),
        .if_pipe_ptw_fault_count(if_pipe_ptw_fault_count),
        .if_pipe_stall_cycle(if_pipe_stall_cycle),
        .if_pipe_icache_miss_count(if_pipe_icache_miss_count),
        .if_pipe_icache_replay_count(if_pipe_icache_replay_count)
`ifdef NPC_PIPE_STAT
        ,
        .if_pipe_stat_outstanding(if_pipe_stat_outstanding),
        .if_pipe_stat_replay_valid(if_pipe_stat_replay_valid),
        .if_pipe_stat_ptw_busy(if_pipe_stat_ptw_busy),
        .if_pipe_stat_req_valid(if_pipe_stat_req_valid),
        .if_pipe_stat_req_ready(if_pipe_stat_req_ready),
        .if_pipe_stat_resp_current(if_pipe_stat_resp_current),
        .if_pipe_stat_resp_stale(if_pipe_stat_resp_stale),
        .if_pipe_stat_lower_req_valid(if_pipe_stat_lower_req_valid),
        .if_pipe_stat_lower_req_ready(if_pipe_stat_lower_req_ready),
        .if_pipe_stat_lower_resp_valid(if_pipe_stat_lower_resp_valid),
        .if_pipe_stat_lower_resp_ready(if_pipe_stat_lower_resp_ready)
`endif
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
        ,
        .icache_stat_access(icache_stat_access),
        .icache_stat_hit(icache_stat_hit),
        .icache_stat_miss(icache_stat_miss),
        .icache_stat_refill_req(icache_stat_refill_req),
        .icache_stat_refill_resp(icache_stat_refill_resp),
        .icache_stat_refill_bypass(icache_stat_refill_bypass),
        .icache_stat_req_wait_cycle(icache_stat_req_wait_cycle),
        .icache_stat_hit_resp_wait_cycle(icache_stat_hit_resp_wait_cycle),
        .icache_stat_miss_wait_cycle(icache_stat_miss_wait_cycle),
        .icache_stat_uncached_access(icache_stat_uncached_access),
        .icache_pipe_req_valid_cycle(icache_pipe_req_valid_cycle),
        .icache_pipe_req_ready_cycle(icache_pipe_req_ready_cycle),
        .icache_pipe_req_fire_cycle(icache_pipe_req_fire_cycle),
        .icache_pipe_req_valid_not_ready_cycle(icache_pipe_req_valid_not_ready_cycle),
        .icache_pipe_resp_valid_cycle(icache_pipe_resp_valid_cycle),
        .icache_pipe_resp_ready_cycle(icache_pipe_resp_ready_cycle),
        .icache_pipe_resp_fire_cycle(icache_pipe_resp_fire_cycle),
        .icache_pipe_data_valid_cycle(icache_pipe_data_valid_cycle),
        .icache_pipe_resp_block_cycle(icache_pipe_resp_block_cycle),
        .icache_pipe_ready_block_state_cycle(icache_pipe_ready_block_state_cycle),
        .icache_pipe_ready_block_data_cycle(icache_pipe_ready_block_data_cycle),
        .icache_pipe_ready_block_resp_cycle(icache_pipe_ready_block_resp_cycle),
        .icache_pipe_ready_block_cpu_cycle(icache_pipe_ready_block_cpu_cycle),
        .icache_pipe_ready_block_maint_cycle(icache_pipe_ready_block_maint_cycle),
        .icache_pipe_state_idle_cycle(icache_pipe_state_idle_cycle),
        .icache_pipe_state_refill_cycle(icache_pipe_state_refill_cycle),
        .icache_pipe_state_uncached_cycle(icache_pipe_state_uncached_cycle),
        .icache_pipe_hit_fire_cycle(icache_pipe_hit_fire_cycle),
        .icache_pipe_miss_fire_cycle(icache_pipe_miss_fire_cycle),
        .icache_pipe_refill_busy_cycle(icache_pipe_refill_busy_cycle),
        .icache_pipe_resp_fifo_full_cycle(icache_pipe_resp_fifo_full_cycle)
`endif
`endif
    );

    // CpuPerfMonitors owns stat-module instantiations only. Top keeps the
    // legacy debug/stat visibility and decides when monitor output prints.
    CpuPerfMonitors #(
        .ICACHE_MISS_PENALTY(ICACHE_MISS_PENALTY),
        .DCACHE_MISS_PENALTY(DCACHE_MISS_PENALTY)
    ) u_perf_monitors (
        .clk(clk),
        .rst_n(rst_n),
        .ws_valid(ws_valid),
        .commit_is_ebreak(commit_is_ebreak),
        .ws_illegal(ws_illegal),
        .ws_pc(ws_pc),
        .ws_instr(ws_instr),
        .ws_nextpc(ws_nextpc),
        .ibus_req_valid_w(ibus_req_valid_w),
        .ibus_req_ready(ibus_req_ready),
        .ibus_resp_valid(ibus_resp_valid),
        .ibus_resp_ready_w(ibus_resp_ready_w),
        .dbus_req_valid(dbus_req_valid),
        .dbus_req_ready(dbus_req_ready),
        .dbus_resp_valid(dbus_resp_valid),
        .dbus_resp_ready(dbus_resp_ready),
        .icache_stat_access(icache_stat_access),
        .icache_stat_hit(icache_stat_hit),
        .icache_stat_miss(icache_stat_miss),
        .icache_stat_refill_req(icache_stat_refill_req),
        .icache_stat_refill_resp(icache_stat_refill_resp),
        .icache_stat_refill_bypass(icache_stat_refill_bypass),
        .icache_stat_req_wait_cycle(icache_stat_req_wait_cycle),
        .icache_stat_hit_resp_wait_cycle(icache_stat_hit_resp_wait_cycle),
        .icache_stat_miss_wait_cycle(icache_stat_miss_wait_cycle),
        .icache_stat_uncached_access(icache_stat_uncached_access),
        .icache_pipe_req_valid_cycle(icache_pipe_req_valid_cycle),
        .icache_pipe_req_ready_cycle(icache_pipe_req_ready_cycle),
        .icache_pipe_req_fire_cycle(icache_pipe_req_fire_cycle),
        .icache_pipe_req_valid_not_ready_cycle(icache_pipe_req_valid_not_ready_cycle),
        .icache_pipe_resp_valid_cycle(icache_pipe_resp_valid_cycle),
        .icache_pipe_resp_ready_cycle(icache_pipe_resp_ready_cycle),
        .icache_pipe_resp_fire_cycle(icache_pipe_resp_fire_cycle),
        .icache_pipe_data_valid_cycle(icache_pipe_data_valid_cycle),
        .icache_pipe_resp_block_cycle(icache_pipe_resp_block_cycle),
        .icache_pipe_ready_block_state_cycle(icache_pipe_ready_block_state_cycle),
        .icache_pipe_ready_block_data_cycle(icache_pipe_ready_block_data_cycle),
        .icache_pipe_ready_block_resp_cycle(icache_pipe_ready_block_resp_cycle),
        .icache_pipe_ready_block_cpu_cycle(icache_pipe_ready_block_cpu_cycle),
        .icache_pipe_ready_block_maint_cycle(icache_pipe_ready_block_maint_cycle),
        .icache_pipe_state_idle_cycle(icache_pipe_state_idle_cycle),
        .icache_pipe_state_refill_cycle(icache_pipe_state_refill_cycle),
        .icache_pipe_state_uncached_cycle(icache_pipe_state_uncached_cycle),
        .icache_pipe_hit_fire_cycle(icache_pipe_hit_fire_cycle),
        .icache_pipe_miss_fire_cycle(icache_pipe_miss_fire_cycle),
        .icache_pipe_refill_busy_cycle(icache_pipe_refill_busy_cycle),
        .icache_pipe_resp_fifo_full_cycle(icache_pipe_resp_fifo_full_cycle),
        .dcache_stat_access(dcache_stat_access),
        .dcache_stat_load_access(dcache_stat_load_access),
        .dcache_stat_store_access(dcache_stat_store_access),
        .dcache_stat_load_hit(dcache_stat_load_hit),
        .dcache_stat_load_miss(dcache_stat_load_miss),
        .dcache_stat_store_hit(dcache_stat_store_hit),
        .dcache_stat_store_miss(dcache_stat_store_miss),
        .dcache_stat_refill_req(dcache_stat_refill_req),
        .dcache_stat_refill_resp(dcache_stat_refill_resp),
        .dcache_stat_write_req(dcache_stat_write_req),
        .dcache_stat_write_resp(dcache_stat_write_resp),
        .dcache_stat_refill_ld_bypass(dcache_stat_refill_ld_bypass),
        .dcache_stat_refill_store_merge(dcache_stat_refill_store_merge),
        .dcache_stat_req_wait_cycle(dcache_stat_req_wait_cycle),
        .dcache_stat_hit_resp_wait_cycle(dcache_stat_hit_resp_wait_cycle),
        .dcache_stat_miss_wait_cycle(dcache_stat_miss_wait_cycle),
        .dcache_stat_uncached_access(dcache_stat_uncached_access),
        .dcache_stat_writeback_cycle(dcache_stat_writeback_cycle),
        .dhitopt_candidate_count(dhitopt_candidate_count),
        .dhitopt_success_count(dhitopt_success_count),
        .dhitopt_fallback_count(dhitopt_fallback_count),
        .dhitopt_block_store_buffer_count(dhitopt_block_store_buffer_count),
        .dhitopt_block_uncached_count(dhitopt_block_uncached_count),
        .dhitopt_block_fault_count(dhitopt_block_fault_count),
        .dhitopt_block_miss_count(dhitopt_block_miss_count),
        .dhitopt_block_alignment_count(dhitopt_block_alignment_count),
        .dhitopt_unknown_count(dhitopt_unknown_count),
        .ds_allowin(ds_allowin),
        .ds_instr(ds_instr),
        .ds_pc(ds_pc),
        .ds_stage_block(ds_stage_block),
        .ds_stage_block_csr_hazard(ds_stage_block_csr_hazard),
        .ds_stage_block_ex_raw(ds_stage_block_ex_raw),
        .ds_stage_block_hidden_raw(ds_stage_block_hidden_raw),
        .ds_stage_block_load_use(ds_stage_block_load_use),
        .ds_stage_block_ms_raw(ds_stage_block_ms_raw),
        .ds_stage_block_reg_hazard(ds_stage_block_reg_hazard),
        .ds_stat_csr_counter_hazard(ds_stat_csr_counter_hazard),
        .ds_stat_fwd_csr_block(ds_stat_fwd_csr_block),
        .ds_stat_fwd_kill_block(ds_stat_fwd_kill_block),
        .ds_stat_fwd_load_block(ds_stat_fwd_load_block),
        .ds_stat_rs1_ex_alu_fwd(ds_stat_rs1_ex_alu_fwd),
        .ds_stat_rs1_match_es(ds_stat_rs1_match_es),
        .ds_stat_rs1_match_hidden(ds_stat_rs1_match_hidden),
        .ds_stat_rs1_match_ms(ds_stat_rs1_match_ms),
        .ds_stat_rs1_match_ws(ds_stat_rs1_match_ws),
        .ds_stat_rs2_ex_alu_fwd(ds_stat_rs2_ex_alu_fwd),
        .ds_stat_rs2_match_es(ds_stat_rs2_match_es),
        .ds_stat_rs2_match_hidden(ds_stat_rs2_match_hidden),
        .ds_stat_rs2_match_ms(ds_stat_rs2_match_ms),
        .ds_stat_rs2_match_ws(ds_stat_rs2_match_ws),
        .ds_stat_uses_rs1(ds_stat_uses_rs1),
        .ds_stat_uses_rs2(ds_stat_uses_rs2),
        .ds_to_es_valid(ds_to_es_valid),
        .es_allowin(es_allowin),
        .es_atomic_en(es_atomic_en),
        .es_branch(es_branch),
        .es_csr_wen(es_csr_wen),
        .es_datatoreg(es_datatoreg),
        .es_instr(es_instr),
        .es_mem_fwd_dep(es_mem_fwd_dep),
        .es_mem_wr(es_mem_wr),
        .es_nextpc(es_nextpc),
        .es_pc(es_pc),
        .es_result_bypassable(es_result_bypassable),
        .es_stage_block(es_stage_block),
        .es_stage_block_mdu_wait(es_stage_block_mdu_wait),
        .es_stage_block_redirect_wait(es_stage_block_redirect_wait),
        .es_stat_fast_mul(es_stat_fast_mul),
        .es_stat_fast_mul_flush_drop(es_stat_fast_mul_flush_drop),
        .es_stat_fast_mul_forward(es_stat_fast_mul_forward),
        .es_stat_fast_mul_issue(es_stat_fast_mul_issue),
        .es_stat_fast_mul_kill(es_stat_fast_mul_kill),
        .es_stat_fast_mul_stall_wait_ready(es_stat_fast_mul_stall_wait_ready),
        .es_stat_is_mdu(es_stat_is_mdu),
        .es_stat_mdu_busy(es_stat_mdu_busy),
        .es_stat_mdu_op(es_stat_mdu_op),
        .es_stat_mdu_req_fire(es_stat_mdu_req_fire),
        .es_stat_mdu_resp_valid(es_stat_mdu_resp_valid),
        .es_stat_mdu_result_ready(es_stat_mdu_result_ready),
        .es_stat_old_div_path(es_stat_old_div_path),
        .es_stat_old_rem_path(es_stat_old_rem_path),
        .es_stat_rs1_load_fwd(es_stat_rs1_load_fwd),
        .es_stat_rs1_mem_alu_fwd(es_stat_rs1_mem_alu_fwd),
        .es_stat_rs1_wb_fwd(es_stat_rs1_wb_fwd),
        .es_stat_rs2_load_fwd(es_stat_rs2_load_fwd),
        .es_stat_rs2_mem_alu_fwd(es_stat_rs2_mem_alu_fwd),
        .es_stat_rs2_wb_fwd(es_stat_rs2_wb_fwd),
        .es_to_ms_valid(es_to_ms_valid),
        .es_valid(es_valid),
        .ex_branch_pred_bht_state(ex_branch_pred_bht_state),
        .ex_branch_pred_btb_hit(ex_branch_pred_btb_hit),
        .ex_branch_pred_btb_is_cond(ex_branch_pred_btb_is_cond),
        .ex_branch_pred_taken(ex_branch_pred_taken),
        .ex_branch_pred_target(ex_branch_pred_target),
        .ex_branch_taken_actual(ex_branch_taken_actual),
        .ex_branch_target_mismatch(ex_branch_target_mismatch),
        .ex_mispredict_flush_valid(ex_mispredict_flush_valid),
        .fast_mul_resp_wb(fast_mul_resp_wb),
        .fencei_maint_active(fencei_maint_active),
        .fencei_start(fencei_start),
        .fs_to_ds_valid(fs_to_ds_valid),
        .hidden_mreq_csr_wen(hidden_mreq_csr_wen),
        .hidden_mreq_datatoreg(hidden_mreq_datatoreg),
        .hidden_mreq_mem_wr(hidden_mreq_mem_wr),
        .ibus_icache_pipe_resp_ready(ibus_icache_pipe_resp_ready),
        .ibus_icache_pipe_resp_valid(ibus_icache_pipe_resp_valid),
        .if_mmu_bridge_state_wait_cycle(if_mmu_bridge_state_wait_cycle),
        .if_mmu_bypass_count(if_mmu_bypass_count),
        .if_mmu_cache_req_wait_cycle(if_mmu_cache_req_wait_cycle),
        .if_mmu_cache_resp_wait_cycle(if_mmu_cache_resp_wait_cycle),
        .if_mmu_fetch_req_count(if_mmu_fetch_req_count),
        .if_mmu_fetch_resp_count(if_mmu_fetch_resp_count),
        .if_mmu_page_fault_count(if_mmu_page_fault_count),
        .if_mmu_ptw_cycle_count(if_mmu_ptw_cycle_count),
        .if_mmu_ptw_l0_read_count(if_mmu_ptw_l0_read_count),
        .if_mmu_ptw_l1_read_count(if_mmu_ptw_l1_read_count),
        .if_mmu_ptw_walk_done_count(if_mmu_ptw_walk_done_count),
        .if_mmu_ptw_walk_fault_count(if_mmu_ptw_walk_fault_count),
        .if_mmu_ptw_walk_start_count(if_mmu_ptw_walk_start_count),
        .if_mmu_req_count(if_mmu_req_count),
        .if_mmu_tlb_hit_count(if_mmu_tlb_hit_count),
        .if_mmu_tlb_hit_to_cache_req_cycle(if_mmu_tlb_hit_to_cache_req_cycle),
        .if_mmu_tlb_miss_count(if_mmu_tlb_miss_count),
        .if_mmu_translate_count(if_mmu_translate_count),
        .if_pipe_epoch_drop_count(if_pipe_epoch_drop_count),
        .if_pipe_icache_miss_count(if_pipe_icache_miss_count),
        .if_pipe_icache_replay_count(if_pipe_icache_replay_count),
        .if_pipe_issue_count(if_pipe_issue_count),
        .if_pipe_ptw_fault_count(if_pipe_ptw_fault_count),
        .if_pipe_ptw_miss_count(if_pipe_ptw_miss_count),
        .if_pipe_replay_count(if_pipe_replay_count),
        .if_pipe_resp_count(if_pipe_resp_count),
        .if_pipe_stall_cycle(if_pipe_stall_cycle),
        .if_pipe_stat_lower_req_ready(if_pipe_stat_lower_req_ready),
        .if_pipe_stat_lower_req_valid(if_pipe_stat_lower_req_valid),
        .if_pipe_stat_lower_resp_ready(if_pipe_stat_lower_resp_ready),
        .if_pipe_stat_lower_resp_valid(if_pipe_stat_lower_resp_valid),
        .if_pipe_stat_outstanding(if_pipe_stat_outstanding),
        .if_pipe_stat_ptw_busy(if_pipe_stat_ptw_busy),
        .if_pipe_stat_replay_valid(if_pipe_stat_replay_valid),
        .if_pipe_stat_req_ready(if_pipe_stat_req_ready),
        .if_pipe_stat_req_valid(if_pipe_stat_req_valid),
        .if_pipe_stat_resp_current(if_pipe_stat_resp_current),
        .if_pipe_stat_resp_stale(if_pipe_stat_resp_stale),
        .if_stall(if_stall),
        .if_stat_bypass_direct(if_stat_bypass_direct),
        .if_stat_drop_resp(if_stat_drop_resp),
        .if_stat_fetch_room(if_stat_fetch_room),
        .if_stat_fs_pop(if_stat_fs_pop),
        .if_stat_fs_valid(if_stat_fs_valid),
        .if_stat_queue_count(if_stat_queue_count),
        .if_stat_queue_full(if_stat_queue_full),
        .if_stat_req_fire(if_stat_req_fire),
        .if_stat_resp_accept(if_stat_resp_accept),
        .if_stat_resp_block(if_stat_resp_block),
        .if_stat_resp_drop(if_stat_resp_drop),
        .if_stat_resp_enq(if_stat_resp_enq),
        .if_stat_resp_fire(if_stat_resp_fire),
        .if_stat_waiting_resp(if_stat_waiting_resp),
        .lsu_mmu_bridge_state_wait_cycle(lsu_mmu_bridge_state_wait_cycle),
        .lsu_mmu_bypass_count(lsu_mmu_bypass_count),
        .lsu_mmu_cache_req_wait_cycle(lsu_mmu_cache_req_wait_cycle),
        .lsu_mmu_cache_resp_wait_cycle(lsu_mmu_cache_resp_wait_cycle),
        .lsu_mmu_data_req_count(lsu_mmu_data_req_count),
        .lsu_mmu_data_resp_count(lsu_mmu_data_resp_count),
        .lsu_mmu_page_fault_count(lsu_mmu_page_fault_count),
        .lsu_mmu_ptw_cycle_total(lsu_mmu_ptw_cycle_total),
        .lsu_mmu_ptw_l0_read_total(lsu_mmu_ptw_l0_read_total),
        .lsu_mmu_ptw_l1_read_total(lsu_mmu_ptw_l1_read_total),
        .lsu_mmu_ptw_walk_done_total(lsu_mmu_ptw_walk_done_total),
        .lsu_mmu_ptw_walk_fault_total(lsu_mmu_ptw_walk_fault_total),
        .lsu_mmu_ptw_walk_start_total(lsu_mmu_ptw_walk_start_total),
        .lsu_mmu_req_count(lsu_mmu_req_count),
        .lsu_mmu_tlb_hit_count(lsu_mmu_tlb_hit_count),
        .lsu_mmu_tlb_hit_to_cache_req_cycle(lsu_mmu_tlb_hit_to_cache_req_cycle),
        .lsu_mmu_tlb_miss_count(lsu_mmu_tlb_miss_count),
        .lsu_mmu_translate_count(lsu_mmu_translate_count),
        .lsu_mmu_uncached_req_count(lsu_mmu_uncached_req_count),
        .lsu_pipe_dcache_hit_count(lsu_pipe_dcache_hit_count),
        .lsu_pipe_dcache_miss_count(lsu_pipe_dcache_miss_count),
        .lsu_pipe_direct_cross_page_count(lsu_pipe_direct_cross_page_count),
        .lsu_pipe_direct_fast_block_atomic_count(lsu_pipe_direct_fast_block_atomic_count),
        .lsu_pipe_direct_fast_block_count(lsu_pipe_direct_fast_block_count),
        .lsu_pipe_direct_fast_block_exception_count(lsu_pipe_direct_fast_block_exception_count),
        .lsu_pipe_direct_fast_block_misaligned_count(lsu_pipe_direct_fast_block_misaligned_count),
        .lsu_pipe_direct_fast_block_other_count(lsu_pipe_direct_fast_block_other_count),
        .lsu_pipe_direct_fast_block_phase2_count(lsu_pipe_direct_fast_block_phase2_count),
        .lsu_pipe_direct_non_dtlb_hit_count(lsu_pipe_direct_non_dtlb_hit_count),
        .lsu_pipe_direct_other_count(lsu_pipe_direct_other_count),
        .lsu_pipe_direct_perm_fault_count(lsu_pipe_direct_perm_fault_count),
        .lsu_pipe_direct_uncached_count(lsu_pipe_direct_uncached_count),
        .lsu_pipe_dtlb_hit_count(lsu_pipe_dtlb_hit_count),
        .lsu_pipe_dtlb_miss_count(lsu_pipe_dtlb_miss_count),
        .lsu_pipe_epoch_drop_count(lsu_pipe_epoch_drop_count),
        .lsu_pipe_fault_count(lsu_pipe_fault_count),
        .lsu_pipe_hit_latency_count(lsu_pipe_hit_latency_count),
        .lsu_pipe_hit_latency_max(lsu_pipe_hit_latency_max),
        .lsu_pipe_hit_latency_sum(lsu_pipe_hit_latency_sum),
        .lsu_pipe_issue_count(lsu_pipe_issue_count),
        .lsu_pipe_load_hit_count(lsu_pipe_load_hit_count),
        .lsu_pipe_load_hit_latency_count(lsu_pipe_load_hit_latency_count),
        .lsu_pipe_load_hit_latency_max(lsu_pipe_load_hit_latency_max),
        .lsu_pipe_load_hit_latency_sum(lsu_pipe_load_hit_latency_sum),
        .lsu_pipe_load_miss_replay_count(lsu_pipe_load_miss_replay_count),
        .lsu_pipe_replay_count(lsu_pipe_replay_count),
        .lsu_pipe_resp_count(lsu_pipe_resp_count),
        .lsu_pipe_slow_direct_latency_count(lsu_pipe_slow_direct_latency_count),
        .lsu_pipe_slow_direct_latency_max(lsu_pipe_slow_direct_latency_max),
        .lsu_pipe_slow_direct_latency_sum(lsu_pipe_slow_direct_latency_sum),
        .lsu_pipe_slow_fallback_count(lsu_pipe_slow_fallback_count),
        .lsu_pipe_slow_fallback_latency_count(lsu_pipe_slow_fallback_latency_count),
        .lsu_pipe_slow_fallback_latency_max(lsu_pipe_slow_fallback_latency_max),
        .lsu_pipe_slow_fallback_latency_sum(lsu_pipe_slow_fallback_latency_sum),
        .lsu_pipe_slow_replay_latency_count(lsu_pipe_slow_replay_latency_count),
        .lsu_pipe_slow_replay_latency_max(lsu_pipe_slow_replay_latency_max),
        .lsu_pipe_slow_replay_latency_sum(lsu_pipe_slow_replay_latency_sum),
        .lsu_pipe_stall_cycle(lsu_pipe_stall_cycle),
        .lsu_pipe_store_hit_count(lsu_pipe_store_hit_count),
        .lsu_pipe_store_hit_latency_count(lsu_pipe_store_hit_latency_count),
        .lsu_pipe_store_hit_latency_max(lsu_pipe_store_hit_latency_max),
        .lsu_pipe_store_hit_latency_sum(lsu_pipe_store_hit_latency_sum),
        .lsu_pipe_store_miss_replay_count(lsu_pipe_store_miss_replay_count),
        .ms_allowin(ms_allowin),
        .ms_csr_wen(ms_csr_wen),
        .ms_datatoreg(ms_datatoreg),
        .ms_fast_req_fire_trace(ms_fast_req_fire_trace),
        .ms_fwd_valid(ms_fwd_valid),
        .ms_slow_req_fire_trace(ms_slow_req_fire_trace),
        .ms_slow_req_fwd_dep_fire_trace(ms_slow_req_fwd_dep_fire_trace),
        .ms_slow_req_nonfwd_fire_trace(ms_slow_req_nonfwd_fire_trace),
        .ms_stage_block(ms_stage_block),
        .ms_stage_block_load(ms_stage_block_load),
        .ms_stage_block_req_load(ms_stage_block_req_load),
        .ms_stage_block_req_phase(ms_stage_block_req_phase),
        .ms_stage_block_req_store(ms_stage_block_req_store),
        .ms_stage_block_resp_load(ms_stage_block_resp_load),
        .ms_stage_block_resp_phase(ms_stage_block_resp_phase),
        .ms_stage_block_resp_store(ms_stage_block_resp_store),
        .ms_stage_block_store(ms_stage_block_store),
        .ms_stat_hidden_load(ms_stat_hidden_load),
        .ms_stat_load_aligned(ms_stat_load_aligned),
        .ms_stat_load_atomic(ms_stat_load_atomic),
        .ms_stat_load_data_ready(ms_stat_load_data_ready),
        .ms_stat_load_fault(ms_stat_load_fault),
        .ms_stat_load_killed(ms_stat_load_killed),
        .ms_stat_load_lsu_pending(ms_stat_load_lsu_pending),
        .ms_stat_load_req_fire(ms_stat_load_req_fire),
        .ms_stat_load_resp_fire(ms_stat_load_resp_fire),
        .ms_stat_load_resp_valid(ms_stat_load_resp_valid),
        .ms_stat_load_result_ready(ms_stat_load_result_ready),
        .ms_stat_load_signext_data_ready(ms_stat_load_signext_data_ready),
        .ms_stat_load_signext_ready(ms_stat_load_signext_ready),
        .ms_stat_load_split_or_misaligned(ms_stat_load_split_or_misaligned),
        .ms_stat_load_store_block(ms_stat_load_store_block),
        .ms_stat_load_to_wb_valid(ms_stat_load_to_wb_valid),
        .ms_stat_load_uncached(ms_stat_load_uncached),
        .ms_stat_load_visible(ms_stat_load_visible),
        .ms_stat_mreq_blocked_by_resp(ms_stat_mreq_blocked_by_resp),
        .ms_stat_mreq_fault(ms_stat_mreq_fault),
        .ms_stat_mreq_fire(ms_stat_mreq_fire),
        .ms_stat_mreq_is_atomic(ms_stat_mreq_is_atomic),
        .ms_stat_mreq_is_load(ms_stat_mreq_is_load),
        .ms_stat_mreq_is_store(ms_stat_mreq_is_store),
        .ms_stat_mreq_misaligned(ms_stat_mreq_misaligned),
        .ms_stat_mreq_need_mem(ms_stat_mreq_need_mem),
        .ms_stat_mreq_split(ms_stat_mreq_split),
        .ms_stat_mreq_valid(ms_stat_mreq_valid),
        .ms_stat_mresp_fault(ms_stat_mresp_fault),
        .ms_stat_mresp_is_atomic(ms_stat_mresp_is_atomic),
        .ms_stat_mresp_is_load(ms_stat_mresp_is_load),
        .ms_stat_mresp_is_store(ms_stat_mresp_is_store),
        .ms_stat_mresp_resp_fire(ms_stat_mresp_resp_fire),
        .ms_stat_mresp_resp_valid(ms_stat_mresp_resp_valid),
        .ms_stat_mresp_split(ms_stat_mresp_split),
        .ms_stat_mresp_valid(ms_stat_mresp_valid),
        .ms_stat_single_outstanding_wait(ms_stat_single_outstanding_wait),
        .ms_stat_store_aligned(ms_stat_store_aligned),
        .ms_stat_store_atomic(ms_stat_store_atomic),
        .ms_stat_store_buffer_safe(ms_stat_store_buffer_safe),
        .ms_stat_store_fault(ms_stat_store_fault),
        .ms_stat_store_killed(ms_stat_store_killed),
        .ms_stat_store_req_fire(ms_stat_store_req_fire),
        .ms_stat_store_resp_fire(ms_stat_store_resp_fire),
        .ms_stat_store_resp_valid(ms_stat_store_resp_valid),
        .ms_stat_store_resp_wait(ms_stat_store_resp_wait),
        .ms_stat_store_split_or_misaligned(ms_stat_store_split_or_misaligned),
        .ms_stat_store_uncached(ms_stat_store_uncached),
        .ms_stat_store_visible(ms_stat_store_visible),
        .ms_stat_uncached_wait(ms_stat_uncached_wait),
        .ms_stat_writeback_wait(ms_stat_writeback_wait),
        .ms_to_ws_valid(ms_to_ws_valid),
        .ms_valid(ms_valid),
        .redirect_clear_valid(redirect_clear_valid),
        .redirect_flush_valid(redirect_flush_valid),
        .stat_exmem_skid_blocked_branch(stat_exmem_skid_blocked_branch),
        .stat_exmem_skid_blocked_csr(stat_exmem_skid_blocked_csr),
        .stat_exmem_skid_blocked_div(stat_exmem_skid_blocked_div),
        .stat_exmem_skid_blocked_exception(stat_exmem_skid_blocked_exception),
        .stat_exmem_skid_blocked_mem(stat_exmem_skid_blocked_mem),
        .stat_exmem_skid_blocked_not_safe(stat_exmem_skid_blocked_not_safe),
        .stat_exmem_skid_blocked_structural(stat_exmem_skid_blocked_structural),
        .stat_exmem_skid_candidate(stat_exmem_skid_candidate),
        .stat_exmem_skid_dequeue(stat_exmem_skid_dequeue),
        .stat_exmem_skid_dequeue_after_mem_release(stat_exmem_skid_dequeue_after_mem_release),
        .stat_exmem_skid_dequeue_causes_wb_valid(stat_exmem_skid_dequeue_causes_wb_valid),
        .stat_exmem_skid_dequeue_commit_fire(stat_exmem_skid_dequeue_commit_fire),
        .stat_exmem_skid_dequeue_fire(stat_exmem_skid_dequeue_fire),
        .stat_exmem_skid_dequeue_same_cycle_mem_release(stat_exmem_skid_dequeue_same_cycle_mem_release),
        .stat_exmem_skid_dequeue_to_mreq_fire(stat_exmem_skid_dequeue_to_mreq_fire),
        .stat_exmem_skid_enqueue(stat_exmem_skid_enqueue),
        .stat_exmem_skid_enqueue_fire(stat_exmem_skid_enqueue_fire),
        .stat_exmem_skid_flush_drop(stat_exmem_skid_flush_drop),
        .stat_exmem_skid_full_stall(stat_exmem_skid_full_stall),
        .stat_exmem_skid_hold_cycles(stat_exmem_skid_hold_cycles),
        .stat_exmem_skid_hold_mem_wait_cycles(stat_exmem_skid_hold_mem_wait_cycles),
        .stat_exmem_skid_mem_release(stat_exmem_skid_mem_release),
        .stat_exmem_skid_mem_wait(stat_exmem_skid_mem_wait),
        .stat_exmem_skid_valid(stat_exmem_skid_valid),
        .stop_clear_valid(stop_clear_valid),
        .store_buffer_dequeue_count(store_buffer_dequeue_count),
        .store_buffer_drain_req_count(store_buffer_drain_req_count),
        .store_buffer_drain_resp_count(store_buffer_drain_resp_count),
        .store_buffer_drain_wait_count(store_buffer_drain_wait_count),
        .store_buffer_enqueue_count(store_buffer_enqueue_count),
        .store_buffer_enqueue_full_count(store_buffer_enqueue_full_count),
        .store_buffer_enqueue_occ0_count(store_buffer_enqueue_occ0_count),
        .store_buffer_enqueue_occ1_count(store_buffer_enqueue_occ1_count),
        .store_buffer_fence_drain_wait_count(store_buffer_fence_drain_wait_count),
        .store_buffer_full_stall_count(store_buffer_full_stall_count),
        .store_buffer_killed_store_block_count(store_buffer_killed_store_block_count),
        .store_buffer_load_forward_count(store_buffer_load_forward_count),
        .store_buffer_load_stall_buffer_nonempty_count(store_buffer_load_stall_buffer_nonempty_count),
        .store_buffer_load_stall_conflict_count(store_buffer_load_stall_conflict_count),
        .store_buffer_max_occupancy_count(store_buffer_max_occupancy_count),
        .store_buffer_occupancy0_count(store_buffer_occupancy0_count),
        .store_buffer_occupancy1_count(store_buffer_occupancy1_count),
        .store_buffer_occupancy2_count(store_buffer_occupancy2_count),
        .store_buffer_uncached_drain_wait_count(store_buffer_uncached_drain_wait_count),
        .trap_redirect_valid(trap_redirect_valid),
        .vm_flush_start(vm_flush_start),
        .ws_allowin(ws_allowin),
        .ws_csr_wen(ws_csr_wen),
        .ws_stat_datatoreg(ws_stat_datatoreg),
        .ws_stat_mem_op(ws_stat_mem_op),
        .branch_stat_fetch_req_valid(branch_stat_fetch_req_valid),
        .branch_stat_fetch_req_pc(branch_stat_fetch_req_pc),
        .branch_stat_fetch_accept_valid(branch_stat_fetch_accept_valid),
        .branch_stat_fetch_accept_pc(branch_stat_fetch_accept_pc),
        .branch_stat_fetch_accept_instr(branch_stat_fetch_accept_instr),
        .branch_stat_fetch_drop_valid(branch_stat_fetch_drop_valid),
        .branch_stat_fetch_drop_redirect(branch_stat_fetch_drop_redirect),
        .branch_stat_fetch_drop_pc(branch_stat_fetch_drop_pc),
        .branch_stat_fetch_drop_instr(branch_stat_fetch_drop_instr),
        .branch_stat_resolve_valid(branch_stat_resolve_valid),
        .bpu_btb_lookup_count(bpu_btb_lookup_count),
        .bpu_btb_hit_count(bpu_btb_hit_count),
        .bpu_btb_miss_count(bpu_btb_miss_count),
        .bpu_bht_pred_taken_count(bpu_bht_pred_taken_count),
        .bpu_bht_pred_not_taken_count(bpu_bht_pred_not_taken_count),
        .bpu_btb_conflict_count(bpu_btb_conflict_count),
        .bpu_btb_update_count(bpu_btb_update_count),
        .bpu_btb_replace_count(bpu_btb_replace_count),
        .bpu_bht_lookup_count(bpu_bht_lookup_count),
        .bpu_bht_update_count(bpu_bht_update_count),
        .bpu_bht_weak_taken_count(bpu_bht_weak_taken_count),
        .bpu_bht_weak_not_taken_count(bpu_bht_weak_not_taken_count),
        .bpu_bht_strong_taken_count(bpu_bht_strong_taken_count),
        .bpu_bht_strong_not_taken_count(bpu_bht_strong_not_taken_count),
        .bpu_gshare_enable(BPU_GSHARE_ENABLE),
        .bpu_bhr_bits(BPU_BHR_BITS),
        .bpu_bhr_value(bpu_bhr_value)
    );

`ifdef NPC_USE_DPI
    // DPI simulation keeps external IBUS AXI inactive and uses SimPmemBridge
    // as the top-owned instruction memory context.
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

`endif

`ifndef NPC_USE_DPI
    // FPGA path has no DPI ebreak() to stop simulation. Latch a halted state
    // once ebreak reaches WB so IF stays stopped after the pipeline
    // drains and the final commit PC remains observable by ILA.
    always @(posedge clk) begin
        if (!rst_n) begin
            cpu_halted <= 1'b0;
        end else if (ws_valid && ws_is_ebreak && !trap_redirect_valid) begin
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
            commit_src1_value <= 32'b0;
            commit_async_irq <= 1'b0;
            commit_sync_exception <= 1'b0;
            PC <= RESET_VECTOR;
            instr <= 32'b0;
            NextPC <= RESET_VECTOR;
            arch_pc <= RESET_VECTOR;
        end else begin
            commit_valid <= 1'b0;
            commit_async_irq <= 1'b0;
            commit_sync_exception <= 1'b0;

            if (fencei_commit_fire) begin
                commit_valid <= 1'b1;
                commit_pc <= fencei_commit_pc_r;
                commit_instr <= fencei_commit_instr_r;
                commit_nextpc <= fencei_commit_nextpc_r;
                commit_src1_value <= 32'b0;
                commit_async_irq <= 1'b0;
                commit_sync_exception <= 1'b0;

                PC <= fencei_commit_pc_r;
                instr <= fencei_commit_instr_r;
                NextPC <= fencei_commit_nextpc_r;
                arch_pc <= fencei_commit_nextpc_r;
            end else if (ws_valid && !store_buffer_drain_before_maint &&
                    !ws_is_fencei && !fencei_maint_active && !fencei_commit_pending_r) begin
                commit_valid <= 1'b1;
                commit_pc <= ws_pc;
                commit_instr <= ws_instr;
                commit_nextpc <= trap_redirect_valid ? trap_redirect_pc : ws_nextpc;
                commit_src1_value <= ws_src1_value;
                commit_async_irq <= trap_redirect_async;
                commit_sync_exception <= commit_sync_exception_w;

                PC <= ws_pc;
                instr <= ws_instr;
                NextPC <= trap_redirect_valid ? trap_redirect_pc : ws_nextpc;
                arch_pc <= trap_redirect_valid ? trap_redirect_pc : ws_nextpc;

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
                end else if (ws_is_unsupported_csr && !trap_redirect_valid) begin
`ifdef NPC_USE_DPI
`ifdef NPC_DPI_CSR_UNDEFINE
                    csr_undefine(ws_pc, {20'b0, ws_csr_idx}, ws_instr);
`else
                    inster_undefine(ws_pc, ws_instr);
`endif
`endif
                end else if (ws_illegal && !trap_redirect_valid) begin
`ifdef NPC_USE_DPI
                    inster_undefine(ws_pc, ws_instr);
`endif
                end
            end

`ifdef NPC_USE_DPI
            if (dbus_dcache_req_valid && dbus_dcache_req_ready && !dbus_dcache_req_is_ptw) begin
                ideal_cache_record_dcache(dbus_req_paddr, {29'b0, dbus_dcache_req_len}, {31'b0, dbus_dcache_req_write});
            end
`endif
        end
    end
endmodule
