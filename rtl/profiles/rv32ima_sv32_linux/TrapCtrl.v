`timescale 1ns / 1ps

module TrapCtrl (
    input [31:0] commit_pc,
    input [31:0] commit_instr,
    input commit_valid,
    input commit_illegal,
    input commit_exc_valid,
    input [31:0] commit_exc_cause,
    input [31:0] commit_exc_tval,
    input commit_is_ebreak,

    input [1:0] priv_i,
    input [31:0] mstatus_i,
    input [31:0] mtvec_i,
    input [31:0] stvec_i,
    input [31:0] mepc_i,
    input [31:0] sepc_i,
    input [31:0] medeleg_i,
    input [31:0] mideleg_i,
    input [31:0] mie_i,
    input [31:0] mip_i,
    input [31:0] mcounteren_i,
    input [31:0] scounteren_i,

    // Async interrupt hook (kept as entry only for now).
    input async_irq_valid,
    input [31:0] async_irq_cause,
    input [31:0] async_irq_tval,

    output trap_kill_side_effect,
    output trap_redirect_valid,
    output trap_redirect_async,
    output [31:0] trap_redirect_pc,

    output priv_upd_we,
    output priv_upd_priv_we,
    output [1:0] priv_upd_priv,
    output priv_upd_mstatus_we,
    output [31:0] priv_upd_mstatus,
    output priv_upd_mepc_we,
    output [31:0] priv_upd_mepc,
    output priv_upd_mcause_we,
    output [31:0] priv_upd_mcause,
    output priv_upd_mtval_we,
    output [31:0] priv_upd_mtval,
    output priv_upd_sepc_we,
    output [31:0] priv_upd_sepc,
    output priv_upd_scause_we,
    output [31:0] priv_upd_scause,
    output priv_upd_stval_we,
    output [31:0] priv_upd_stval,

    output commit_is_unsupported_csr
);
    localparam [1:0] PRIV_U = 2'b00;
    localparam [1:0] PRIV_S = 2'b01;
    localparam [1:0] PRIV_M = 2'b11;

    wire [6:0] opcode = commit_instr[6:0];
    wire [2:0] funct3 = commit_instr[14:12];
    wire [11:0] csr_idx = commit_instr[31:20];

    wire is_system = (opcode == 7'b1110011);
    wire is_ecall = (commit_instr == 32'h00000073);
    wire is_mret  = (commit_instr == 32'h30200073);
    wire is_sret  = (commit_instr == 32'h10200073);
    wire is_sfence_vma =
        (commit_instr[6:0] == 7'b1110011) &&
        (commit_instr[14:12] == 3'b000) &&
        (commit_instr[31:25] == 7'b0001001) &&
        (commit_instr[11:7] == 5'b00000);
    wire is_csr_instr = is_system && (funct3 != 3'b000);
    wire csr_write_attempt =
        is_csr_instr &&
        (
            (funct3 == 3'b001) || (funct3 == 3'b101) ||
            (((funct3 == 3'b010) || (funct3 == 3'b011) || (funct3 == 3'b110) || (funct3 == 3'b111)) &&
             (commit_instr[19:15] != 5'b00000))
        );

    function csr_addr_is_mapped;
        input [11:0] csr_addr;
        begin
            csr_addr_is_mapped =
                (csr_addr == 12'h300) || (csr_addr == 12'h301) || (csr_addr == 12'h302) ||
                (csr_addr == 12'h303) || (csr_addr == 12'h304) || (csr_addr == 12'h305) ||
                (csr_addr == 12'h306) || (csr_addr == 12'h310) || (csr_addr == 12'h31a) ||
                (csr_addr == 12'h320) || (csr_addr == 12'h340) || (csr_addr == 12'h341) ||
                (csr_addr == 12'h342) || (csr_addr == 12'h343) || (csr_addr == 12'h344) ||
                (csr_addr == 12'h30a) ||
                (csr_addr == 12'h100) || (csr_addr == 12'h104) || (csr_addr == 12'h105) ||
                (csr_addr == 12'h106) || (csr_addr == 12'h10a) || (csr_addr == 12'h140) ||
                (csr_addr == 12'h141) || (csr_addr == 12'h142) || (csr_addr == 12'h143) ||
                (csr_addr == 12'h144) || (csr_addr == 12'h180) ||
                (csr_addr == 12'hb00) || (csr_addr == 12'hc00) || (csr_addr == 12'hb80) ||
                (csr_addr == 12'hc80) || (csr_addr == 12'hc01) || (csr_addr == 12'hc81) ||
                (csr_addr == 12'hb02) || (csr_addr == 12'hc02) || (csr_addr == 12'hb82) ||
                (csr_addr == 12'hc82) || (csr_addr == 12'h744) ||
                (csr_addr == 12'h7a0) || (csr_addr == 12'h7a1) || (csr_addr == 12'h7a2) ||
                (csr_addr == 12'h7a3) || (csr_addr == 12'h7a4) || (csr_addr == 12'h7a5) ||
                (csr_addr == 12'h7a8) ||
                (csr_addr == 12'hf11) || (csr_addr == 12'hf12) || (csr_addr == 12'hf13) ||
                (csr_addr == 12'hf14) ||
                ((csr_addr >= 12'h3a0) && (csr_addr <= 12'h3a3)) ||
                ((csr_addr >= 12'h3a4) && (csr_addr <= 12'h3af)) ||
                ((csr_addr >= 12'h3b0) && (csr_addr <= 12'h3bf)) ||
                ((csr_addr >= 12'h3c0) && (csr_addr <= 12'h3ef)) ||
                ((csr_addr >= 12'hb03) && (csr_addr <= 12'hb1f)) ||
                ((csr_addr >= 12'hb83) && (csr_addr <= 12'hb9f)) ||
                ((csr_addr >= 12'hc03) && (csr_addr <= 12'hc1f)) ||
                ((csr_addr >= 12'hc83) && (csr_addr <= 12'hc9f));
        end
    endfunction

    wire csr_unmapped = is_csr_instr && !csr_addr_is_mapped(csr_idx);
    assign commit_is_unsupported_csr = commit_valid && csr_unmapped;

    function csr_is_counter;
        input [11:0] csr_addr;
        begin
            case (csr_addr)
                12'hc00, 12'hc80,
                12'hc01, 12'hc81,
                12'hc02, 12'hc82: csr_is_counter = 1'b1;
                default: csr_is_counter = 1'b0;
            endcase
        end
    endfunction

    function [1:0] csr_counter_bit;
        input [11:0] csr_addr;
        begin
            case (csr_addr)
                12'hc00, 12'hc80: csr_counter_bit = 2'd0; // cycle/cycleh -> CY
                12'hc01, 12'hc81: csr_counter_bit = 2'd1; // time/timeh -> TM
                12'hc02, 12'hc82: csr_counter_bit = 2'd2; // instret/instreth -> IR
                default:          csr_counter_bit = 2'd0;
            endcase
        end
    endfunction

    wire [1:0] csr_required_priv = csr_idx[9:8];
    wire csr_readonly = (csr_idx[11:10] == 2'b11);
    wire csr_priv_illegal = is_csr_instr && (priv_i < csr_required_priv);
    wire csr_readonly_illegal = csr_write_attempt && csr_readonly;
    wire csr_tvm_illegal = is_csr_instr && (csr_idx == 12'h180) && (priv_i == PRIV_S) && mstatus_i[20];
    wire csr_counter_access = is_csr_instr && csr_is_counter(csr_idx);
    wire [1:0] csr_ctr_bit = csr_counter_bit(csr_idx);
    wire csr_counter_m_enable =
        (csr_ctr_bit == 2'd0) ? mcounteren_i[0] :
        (csr_ctr_bit == 2'd1) ? mcounteren_i[1] :
                                mcounteren_i[2];
    wire csr_counter_s_enable =
        (csr_ctr_bit == 2'd0) ? scounteren_i[0] :
        (csr_ctr_bit == 2'd1) ? scounteren_i[1] :
                                scounteren_i[2];
    wire csr_counter_gate_illegal =
        csr_counter_access && (priv_i != PRIV_M) &&
        (!csr_counter_m_enable || ((priv_i == PRIV_U) && !csr_counter_s_enable));
    wire csr_access_illegal =
        csr_unmapped || csr_priv_illegal || csr_readonly_illegal || csr_tvm_illegal || csr_counter_gate_illegal;

    wire mstatus_tsr = mstatus_i[22];
    wire mstatus_tvm = mstatus_i[20];
    wire mret_illegal = is_mret && (priv_i != PRIV_M);
    wire sret_illegal = is_sret && ((priv_i == PRIV_U) || ((priv_i == PRIV_S) && mstatus_tsr));
    wire sfence_vma_illegal = is_sfence_vma && ((priv_i == PRIV_U) || ((priv_i == PRIV_S) && mstatus_tvm));
    wire ebreak_trap = commit_valid && commit_is_ebreak;

    wire take_pipe_exc = commit_valid && commit_exc_valid;
    wire take_illegal = commit_valid && !take_pipe_exc &&
        (commit_illegal || csr_access_illegal || mret_illegal || sret_illegal || sfence_vma_illegal);
    wire take_ecall = commit_valid && is_ecall;
    wire take_sync_exc = take_pipe_exc || take_illegal || take_ecall || ebreak_trap;
    wire take_xret = commit_valid && !take_sync_exc && (is_mret || is_sret);
    wire take_async = commit_valid && !take_sync_exc && !take_xret && async_irq_valid;

    wire [31:0] ecall_cause =
        (priv_i == PRIV_U) ? 32'd8 :
        (priv_i == PRIV_S) ? 32'd9 :
        32'd11;
    wire [31:0] exc_cause =
        take_pipe_exc ? commit_exc_cause :
        take_illegal ? 32'd2 :
        ebreak_trap ? 32'd3 :
        ecall_cause;
    wire [31:0] exc_tval =
        take_pipe_exc ? commit_exc_tval :
        take_illegal ? commit_instr :
        ebreak_trap ? 32'b0 :
        32'b0;

    wire cause_is_interrupt = take_async;
    wire [31:0] cause_word = take_async ? async_irq_cause : exc_cause;
    wire [31:0] tval_word = take_async ? async_irq_tval : exc_tval;
    wire [4:0] cause_no = cause_word[4:0];
    wire cause_has_tval = take_sync_exc &&
        ((cause_no == 5'd0) || (cause_no == 5'd2) ||
         (cause_no == 5'd4) || (cause_no == 5'd6) ||
         (cause_no == 5'd12) || (cause_no == 5'd13) ||
         (cause_no == 5'd15));

    wire delegated_exc = (priv_i != PRIV_M) && (medeleg_i[cause_no] == 1'b1);
    wire delegated_irq = (priv_i != PRIV_M) && (mideleg_i[cause_no] == 1'b1);
    wire delegate_to_s = cause_is_interrupt ? delegated_irq : delegated_exc;
    wire trap_to_m = !delegate_to_s;

    wire [31:0] trap_tvec = delegate_to_s ? stvec_i : mtvec_i;
    wire [31:0] trap_base = {trap_tvec[31:2], 2'b00};
    wire trap_vectored = cause_is_interrupt && (trap_tvec[1:0] == 2'b01);
    wire [31:0] trap_target_pc_calc = trap_vectored ? (trap_base + {25'b0, cause_no, 2'b00}) : trap_base;

    reg [31:0] mstatus_after_trap;
    always @(*) begin
        mstatus_after_trap = mstatus_i;
        if (trap_to_m) begin
            mstatus_after_trap[7] = mstatus_i[3];     // MPIE <- MIE
            mstatus_after_trap[3] = 1'b0;             // MIE <- 0
            mstatus_after_trap[12:11] = priv_i;       // MPP <- old priv
        end else begin
            mstatus_after_trap[5] = mstatus_i[1];     // SPIE <- SIE
            mstatus_after_trap[1] = 1'b0;             // SIE <- 0
            mstatus_after_trap[8] = (priv_i == PRIV_S); // SPP <- old priv==S
        end
    end

    wire [1:0] xret_to_priv = is_mret ? mstatus_i[12:11] :
        (mstatus_i[8] ? PRIV_S : PRIV_U);
    reg [31:0] mstatus_after_xret;
    always @(*) begin
        mstatus_after_xret = mstatus_i;
        if (is_mret) begin
            mstatus_after_xret[3] = mstatus_i[7];      // MIE <- MPIE
            mstatus_after_xret[7] = 1'b1;              // MPIE <- 1
            mstatus_after_xret[12:11] = PRIV_U;        // MPP <- U
            if (xret_to_priv != PRIV_M) mstatus_after_xret[17] = 1'b0; // clear MPRV
        end else begin
            mstatus_after_xret[1] = mstatus_i[5];      // SIE <- SPIE
            mstatus_after_xret[5] = 1'b1;              // SPIE <- 1
            mstatus_after_xret[8] = 1'b0;              // SPP <- U
            mstatus_after_xret[17] = 1'b0;             // clear MPRV
        end
    end

    wire [31:0] xret_target_pc = is_mret ? mepc_i : sepc_i;

    assign trap_redirect_valid = take_sync_exc || take_xret || take_async;
    assign trap_redirect_async = take_async;
    assign trap_kill_side_effect = trap_redirect_valid;
    assign trap_redirect_pc =
        (take_sync_exc || take_async) ? trap_target_pc_calc :
        xret_target_pc;

    assign priv_upd_we = trap_redirect_valid;
    assign priv_upd_priv_we = trap_redirect_valid;
    assign priv_upd_priv =
        (take_sync_exc || take_async) ? (delegate_to_s ? PRIV_S : PRIV_M) : xret_to_priv;

    assign priv_upd_mstatus_we = trap_redirect_valid;
    assign priv_upd_mstatus =
        (take_sync_exc || take_async) ? mstatus_after_trap : mstatus_after_xret;

    assign priv_upd_mepc_we = (take_sync_exc || take_async) && trap_to_m;
    assign priv_upd_mepc = commit_pc;
    assign priv_upd_mcause_we = (take_sync_exc || take_async) && trap_to_m;
    assign priv_upd_mcause = cause_word;
    assign priv_upd_mtval_we = ((take_sync_exc || take_async) && trap_to_m) ||
        cause_has_tval;
    assign priv_upd_mtval = tval_word;

    assign priv_upd_sepc_we = (take_sync_exc || take_async) && delegate_to_s;
    assign priv_upd_sepc = commit_pc;
    assign priv_upd_scause_we = (take_sync_exc || take_async) && delegate_to_s;
    assign priv_upd_scause = cause_word;
    assign priv_upd_stval_we = ((take_sync_exc || take_async) && delegate_to_s) ||
        cause_has_tval;
    assign priv_upd_stval = tval_word;

    // keep these connected for future IRQ qualify logic (entry reserved now)
    wire [31:0] _unused_irq_state = mie_i ^ mip_i;
    wire _unused_ebreak = commit_is_ebreak;

endmodule
