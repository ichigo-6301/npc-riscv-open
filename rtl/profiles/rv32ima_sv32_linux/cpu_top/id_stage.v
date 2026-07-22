`timescale 1ns / 1ps

module id_stage (
    input clk,
    input rst_n,

    input flush,

    input fs_to_ds_valid,
    input [31:0] fs_pc,
    input [31:0] fs_instr,
    input fs_exc_valid,
    input [31:0] fs_exc_cause,
    input [31:0] fs_exc_tval,
    input fs_pred_taken,
    input [31:0] fs_pred_target,
    input fs_pred_btb_hit,
    input fs_pred_btb_is_cond,
    input [1:0] fs_pred_bht_state,
    input [31:0] fs_pred_pht_idx,
    output ds_allowin,
    input es_allowin,
    output ds_to_es_valid,

    output [4:0] rf_raddr1,
    input [31:0] rf_rdata1,
    output [4:0] rf_raddr2,
    input [31:0] rf_rdata2,
    output [11:0] csr_raddr,
    input [31:0] csr_rdata,

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
    input ms_alu_fwd_valid,
    input ms_load_bypass_valid,
    input [4:0] ms_load_bypass_rd,
    input ws_alu_fwd_valid,
    input ms_fwd_valid,
    input [31:0] ms_fwd_data,

    output [31:0] ds_pc,
    output [31:0] ds_instr,
    output ds_exc_valid,
    output [31:0] ds_exc_cause,
    output [31:0] ds_exc_tval,
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
    output ds_pred_btb_hit,
    output ds_pred_btb_is_cond,
    output [1:0] ds_pred_bht_state,
    output [31:0] ds_pred_pht_idx,
    output [31:0] ds_imm,
    output [31:0] ds_zimm,
    output [31:0] ds_scsr,
    output [4:0] ds_rd,
    output ds_reg_wen,
    output [2:0] ds_branch,
    output [1:0] ds_datatoreg,
    output [1:0] ds_mem_wr,
    output [2:0] ds_mem_op,
    output ds_atomic_en,
    output [3:0] ds_atomic_op,
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
    output ds_stage_block_load_use,
    output ds_stage_block_ex_raw,
    output ds_stage_block_ms_raw,
    output ds_stage_block_hidden_raw,
    output ds_stat_uses_rs1,
    output ds_stat_uses_rs2,
    output ds_stat_rs1_match_es,
    output ds_stat_rs1_match_ms,
    output ds_stat_rs1_match_hidden,
    output ds_stat_rs1_match_ws,
    output ds_stat_rs2_match_es,
    output ds_stat_rs2_match_ms,
    output ds_stat_rs2_match_hidden,
    output ds_stat_rs2_match_ws,
    output ds_stat_csr_counter_hazard,
    output ds_stat_rs1_ex_alu_fwd,
    output ds_stat_rs2_ex_alu_fwd,
    output ds_stat_fwd_load_block,
    output ds_stat_fwd_csr_block,
    output ds_stat_fwd_kill_block,
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
    reg ds_exc_valid_r;
    reg [31:0] ds_exc_cause_r;
    reg [31:0] ds_exc_tval_r;
    reg ds_pred_taken_r;
    reg [31:0] ds_pred_target_r;
    reg ds_pred_btb_hit_r;
    reg ds_pred_btb_is_cond_r;
    reg [1:0] ds_pred_bht_state_r;
    reg [31:0] ds_pred_pht_idx_r;

    wire [4:0] rs1 = ds_instr_r[19:15];
    wire [4:0] rs2 = ds_instr_r[24:20];
    wire [4:0] rd = ds_instr_r[11:7];
    wire [31:0] zimm = {27'b0, rs1};

    wire [2:0] ext_op;
    wire reg_wen;
    wire [2:0] branch;
    wire [1:0] datatoreg;
    wire [1:0] mem_wr;
    wire [2:0] mem_op;
    wire atomic_en;
    wire [3:0] atomic_op;
    wire [1:0] alu_a_src;
    wire [1:0] alu_b_src;
    wire [3:0] alu_ctr;
    wire uses_csr_fast;
    wire [11:0] csr_raddr_real;
    wire [11:0] csr_waddr1_real;
    wire [11:0] csr_waddr2_real;
    wire [1:0] csr_wdata_src1;
    wire csr_wdata_src2;
    wire [1:0] csr_wen;
    wire illegal_instr;
    wire [31:0] imm;
`ifdef NPC_M_EXTENSION
    wire mdu_en;
    wire [2:0] mdu_op;
`endif

    wire ds_valid_eff = ds_valid && !flush;

    wire [6:0] opcode = ds_instr_r[6:0];
    // AMO(opcode=0101111)虽然属于原子访存，但源寄存器依赖规则与普通 R-type 类似：
    // rs1 提供地址基址，rs2 提供参与运算的写入操作数。
    wire is_amo = (opcode == 7'b0101111);
    wire is_load_like = (opcode == 7'b0000011) || is_amo;
    wire is_store_like = (opcode == 7'b0100011) || (opcode == 7'b0101111);
    wire is_data_mem = is_load_like || is_store_like;
    wire is_system = (opcode == 7'b1110011);
    wire is_ecall = (ds_instr_r == 32'h00000073);
    wire is_ebreak = (ds_instr_r == 32'h00100073);
    wire is_csr_instr = is_system && (ds_instr_r[14:12] != 3'b000);
    wire is_jalr = (opcode == 7'b1100111);
    wire is_cond_branch = (opcode == 7'b1100011);

    // 将 AMO 纳入 uses_rs1/uses_rs2，确保 hazard 检测与旁路覆盖到 AMO。
    // 否则可能在连续 AMO 场景下读取到旧的 rs1/rs2 值，导致 difftest 偏差。
    wire uses_rs1 = ds_valid_eff && (
        (opcode == 7'b0110011) ||
        (opcode == 7'b0010011) ||
        (opcode == 7'b0000011) ||
        (opcode == 7'b0100011) ||
        is_amo ||
        (opcode == 7'b1100011) ||
        (opcode == 7'b1100111) ||
        is_csr_instr
    );

    wire uses_rs2 = ds_valid_eff && (
        (opcode == 7'b0110011) ||
        (opcode == 7'b0100011) ||
        is_amo ||
        (opcode == 7'b1100011)
    );

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

    // Do not use the old same-cycle EX result capture path. It could let an
    // immediately following consumer latch a stale producer operand. For ALU
    // producers we only release the stall here; the consumer will select the
    // value from MEM/WB when it reaches EX.
    wire rs1_prev_ex_bypass = 1'b0;
    wire rs2_prev_ex_bypass = 1'b0;
    wire rs1_ex_alu_forwardable = rs1_match_es && es_result_bypassable;
    wire rs2_ex_alu_forwardable = rs2_match_es && es_result_bypassable;
    wire rs1_ms_alu_forwardable = rs1_match_ms && ms_alu_fwd_valid;
    wire rs2_ms_alu_forwardable = rs2_match_ms && ms_alu_fwd_valid;
    wire rs1_ms_load_bypassable = uses_rs1 && ms_load_bypass_valid &&
        (ms_load_bypass_rd != 5'b0) && (ms_load_bypass_rd == rs1);
    wire rs2_ms_load_bypassable = uses_rs2 && ms_load_bypass_valid &&
        (ms_load_bypass_rd != 5'b0) && (ms_load_bypass_rd == rs2);
    wire rs1_ms_forwardable = rs1_ms_alu_forwardable || rs1_ms_load_bypassable;
    wire rs2_ms_forwardable = rs2_ms_alu_forwardable || rs2_ms_load_bypassable;
    wire rs1_ws_alu_forwardable =
        !rs1_match_es && !rs1_match_ms && !rs1_match_hidden_mreq &&
        rs1_match_ws && ws_alu_fwd_valid;
    wire rs2_ws_alu_forwardable =
        !rs2_match_es && !rs2_match_ms && !rs2_match_hidden_mreq &&
        rs2_match_ws && ws_alu_fwd_valid;

    wire rs1_need_stall =
        (rs1_match_es && !rs1_ex_alu_forwardable) ||
        (!rs1_match_es && rs1_match_ms && !rs1_ms_forwardable) ||
        (!rs1_match_es && !rs1_match_ms && rs1_match_hidden_mreq);

    wire rs2_need_stall =
        (rs2_match_es && !rs2_ex_alu_forwardable) ||
        (!rs2_match_es && rs2_match_ms && !rs2_ms_forwardable) ||
        (!rs2_match_es && !rs2_match_ms && rs2_match_hidden_mreq);

    wire rs1_from_ms = 1'b0;
    wire rs2_from_ms = 1'b0;
    wire rs1_prev_wb_bypass =
        !rs1_match_es && !rs1_match_ms && !rs1_match_hidden_mreq && rs1_match_ws;
    wire rs2_prev_wb_bypass =
        !rs2_match_es && !rs2_match_ms && !rs2_match_hidden_mreq && rs2_match_ws;

    wire reg_hazard = rs1_need_stall || rs2_need_stall;
    wire ex_raw_hazard =
        (rs1_match_es && !rs1_ex_alu_forwardable) ||
        (rs2_match_es && !rs2_ex_alu_forwardable);
    wire ms_raw_hazard =
        (!rs1_match_es && rs1_match_ms && !rs1_ms_forwardable) ||
        (!rs2_match_es && rs2_match_ms && !rs2_ms_forwardable);
    wire hidden_raw_hazard =
        (!rs1_match_es && !rs1_match_ms && rs1_match_hidden_mreq) ||
        (!rs2_match_es && !rs2_match_ms && rs2_match_hidden_mreq);
    wire ms_load_like_hazard = ms_raw_hazard;
    wire fwd_load_block =
        (rs1_match_es && !rs1_ex_alu_forwardable) ||
        (rs2_match_es && !rs2_ex_alu_forwardable) ||
        (!rs1_match_es && rs1_match_ms && !rs1_ms_forwardable) ||
        (!rs2_match_es && rs2_match_ms && !rs2_ms_forwardable) ||
        hidden_raw_hazard;

    wire csr_hazard =
        (ds_valid_eff && uses_csr_fast && es_valid && es_csr_wen[1] &&
            ((es_csr_waddr1 == csr_raddr_real) ||
             (es_csr_wen[0] && (es_csr_waddr2 == csr_raddr_real)))) ||
        (ds_valid_eff && uses_csr_fast && ms_valid && ms_csr_wen[1] &&
            ((ms_csr_waddr1 == csr_raddr_real) ||
             (ms_csr_wen[0] && (ms_csr_waddr2 == csr_raddr_real)))) ||
        (ds_valid_eff && uses_csr_fast && hidden_mreq_valid && hidden_mreq_csr_wen[1] &&
            ((hidden_mreq_csr_waddr1 == csr_raddr_real) ||
             (hidden_mreq_csr_wen[0] && (hidden_mreq_csr_waddr2 == csr_raddr_real)))) ||
        (ds_valid_eff && uses_csr_fast && ws_valid && ws_csr_wen[1] &&
            ((ws_csr_waddr1 == csr_raddr_real) ||
             (ws_csr_wen[0] && (ws_csr_waddr2 == csr_raddr_real))));

    wire es_writes_mem_perm_csr = es_csr_wen[1] &&
        ((es_csr_waddr1 == 12'h300) || (es_csr_waddr1 == 12'h100) ||
         (es_csr_wen[0] && ((es_csr_waddr2 == 12'h300) || (es_csr_waddr2 == 12'h100))));
    wire ms_writes_mem_perm_csr = ms_csr_wen[1] &&
        ((ms_csr_waddr1 == 12'h300) || (ms_csr_waddr1 == 12'h100) ||
         (ms_csr_wen[0] && ((ms_csr_waddr2 == 12'h300) || (ms_csr_waddr2 == 12'h100))));
    wire hidden_writes_mem_perm_csr = hidden_mreq_csr_wen[1] &&
        ((hidden_mreq_csr_waddr1 == 12'h300) || (hidden_mreq_csr_waddr1 == 12'h100) ||
         (hidden_mreq_csr_wen[0] &&
          ((hidden_mreq_csr_waddr2 == 12'h300) || (hidden_mreq_csr_waddr2 == 12'h100))));
    wire ws_writes_mem_perm_csr = ws_csr_wen[1] &&
        ((ws_csr_waddr1 == 12'h300) || (ws_csr_waddr1 == 12'h100) ||
         (ws_csr_wen[0] && ((ws_csr_waddr2 == 12'h300) || (ws_csr_waddr2 == 12'h100))));

    // D-side permission checks depend on mstatus.{MPRV,SUM,MXR}. CSR writes
    // retire in WB, so wait one extra cycle after older mstatus/sstatus writes.
    wire lsu_priv_csr_hazard = ds_valid_eff && is_data_mem &&
        ((es_valid && es_writes_mem_perm_csr) ||
         (ms_valid && ms_writes_mem_perm_csr) ||
         (hidden_mreq_valid && hidden_writes_mem_perm_csr) ||
         (ws_valid && ws_writes_mem_perm_csr));

    // `cycle/time/instret` 这类 CSR 由提交路径统一维护。为了保证读到“前序
    // 指令全部退休后的值”，这里保守地等前面流水段清空，再发射当前 counter CSR 读。
    wire csr_counter_read =
        ds_valid_eff && uses_csr_fast &&
        ((csr_raddr_real == 12'hb00) || (csr_raddr_real == 12'hc00) ||
         (csr_raddr_real == 12'hb80) || (csr_raddr_real == 12'hc80) ||
         (csr_raddr_real == 12'hc01) || (csr_raddr_real == 12'hc81) ||
         (csr_raddr_real == 12'hb02) || (csr_raddr_real == 12'hc02) ||
         (csr_raddr_real == 12'hb82) || (csr_raddr_real == 12'hc82));
    wire csr_counter_hazard =
        csr_counter_read && (es_valid || ms_valid || hidden_mreq_valid || ws_valid);

    wire ds_ready_go = !ds_valid_eff ||
        !(reg_hazard || csr_hazard || csr_counter_hazard || lsu_priv_csr_hazard);

    assign ds_allowin = flush || !ds_valid || (ds_ready_go && es_allowin);
    assign ds_to_es_valid = ds_valid_eff && ds_ready_go;

    assign rf_raddr1 = rs1;
    assign rf_raddr2 = rs2;
    assign csr_raddr = csr_raddr_real;

    assign ds_pc = ds_pc_r;
    assign ds_instr = ds_instr_r;
    assign ds_exc_valid = ds_exc_valid_r;
    assign ds_exc_cause = ds_exc_cause_r;
    assign ds_exc_tval = ds_exc_tval_r;
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
    assign ds_pred_btb_hit = ds_pred_btb_hit_r;
    assign ds_pred_btb_is_cond = ds_pred_btb_is_cond_r;
    assign ds_pred_bht_state = ds_pred_bht_state_r;
    assign ds_pred_pht_idx = ds_pred_pht_idx_r;
    assign ds_imm = imm;
    assign ds_zimm = zimm;
    assign ds_scsr = csr_rdata;
    assign ds_rd = rd;
    assign ds_reg_wen = reg_wen;
    assign ds_branch = branch;
    assign ds_datatoreg = datatoreg;
    assign ds_mem_wr = mem_wr;
    assign ds_mem_op = mem_op;
    assign ds_atomic_en = atomic_en;
    assign ds_atomic_op = atomic_op;
    assign ds_alu_a_src = alu_a_src;
    assign ds_alu_b_src = alu_b_src;
    assign ds_alu_ctr = alu_ctr;
    assign ds_csr_wen = csr_wen;
    assign ds_csr_waddr1 = csr_waddr1_real;
    assign ds_csr_waddr2 = csr_waddr2_real;
    assign ds_csr_wdata_src1 = csr_wdata_src1;
    assign ds_csr_wdata_src2 = csr_wdata_src2;
    assign ds_illegal = illegal_instr;
    assign ds_is_ebreak = is_ebreak;
    assign ds_stop_fetch = ds_valid_eff && is_ebreak;
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    assign ds_stage_block = ds_valid_eff && !ds_ready_go;
    assign ds_stage_block_reg_hazard = ds_valid_eff && reg_hazard;
    assign ds_stage_block_csr_hazard = ds_valid_eff && (csr_hazard || lsu_priv_csr_hazard);
    assign ds_stage_block_load_use = ds_valid_eff && ms_load_like_hazard;
    assign ds_stage_block_ex_raw = ds_valid_eff && ex_raw_hazard;
    assign ds_stage_block_ms_raw = ds_valid_eff && ms_raw_hazard;
    assign ds_stage_block_hidden_raw = ds_valid_eff && hidden_raw_hazard;
    assign ds_stat_uses_rs1 = uses_rs1;
    assign ds_stat_uses_rs2 = uses_rs2;
    assign ds_stat_rs1_match_es = rs1_match_es;
    assign ds_stat_rs1_match_ms = rs1_match_ms;
    assign ds_stat_rs1_match_hidden = rs1_match_hidden_mreq;
    assign ds_stat_rs1_match_ws = rs1_match_ws;
    assign ds_stat_rs2_match_es = rs2_match_es;
    assign ds_stat_rs2_match_ms = rs2_match_ms;
    assign ds_stat_rs2_match_hidden = rs2_match_hidden_mreq;
    assign ds_stat_rs2_match_ws = rs2_match_ws;
    assign ds_stat_csr_counter_hazard = csr_counter_hazard;
    assign ds_stat_rs1_ex_alu_fwd = ds_valid_eff && rs1_ex_alu_forwardable &&
        !csr_hazard && !csr_counter_hazard && !lsu_priv_csr_hazard;
    assign ds_stat_rs2_ex_alu_fwd = ds_valid_eff && rs2_ex_alu_forwardable &&
        !csr_hazard && !csr_counter_hazard && !lsu_priv_csr_hazard;
    assign ds_stat_fwd_load_block = ds_valid_eff && fwd_load_block;
    assign ds_stat_fwd_csr_block = ds_valid_eff &&
        (csr_hazard || csr_counter_hazard || lsu_priv_csr_hazard);
    assign ds_stat_fwd_kill_block = ds_valid && flush;
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
        .AtomicEn(atomic_en),
        .AtomicOp(atomic_op),
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
        .csr_raddr(csr_raddr_real),
        .csr_waddr1(csr_waddr1_real),
        .csr_waddr2(csr_waddr2_real),
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
            ds_exc_valid_r <= 1'b0;
            ds_exc_cause_r <= 32'b0;
            ds_exc_tval_r <= 32'b0;
            ds_pred_taken_r <= 1'b0;
            ds_pred_target_r <= 32'b0;
            ds_pred_btb_hit_r <= 1'b0;
            ds_pred_btb_is_cond_r <= 1'b0;
            ds_pred_bht_state_r <= 2'b0;
            ds_pred_pht_idx_r <= 32'b0;
        end else if (ds_allowin) begin
            ds_pc_r <= fs_pc;
            ds_instr_r <= fs_instr;
            ds_exc_valid_r <= fs_exc_valid;
            ds_exc_cause_r <= fs_exc_cause;
            ds_exc_tval_r <= fs_exc_tval;
            ds_pred_taken_r <= fs_pred_taken;
            ds_pred_target_r <= fs_pred_target;
            ds_pred_btb_hit_r <= fs_pred_btb_hit;
            ds_pred_btb_is_cond_r <= fs_pred_btb_is_cond;
            ds_pred_bht_state_r <= fs_pred_bht_state;
            ds_pred_pht_idx_r <= fs_pred_pht_idx;
        end
    end
endmodule
