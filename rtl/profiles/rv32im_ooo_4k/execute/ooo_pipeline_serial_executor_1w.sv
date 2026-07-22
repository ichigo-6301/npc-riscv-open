`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// Production-compatible one-wide executor for the P6/P8 external serial
// boundary. It deliberately covers only the already-supported FSM behavior:
// store address generation, CSR accesses, fence/fence.i, ecall/mret, and
// terminal ebreak.
module ooo_pipeline_serial_executor_1w #(
    parameter bit STORE_ISSUE_FINAL_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit MDU_MUL_COMPLETION_FALLTHROUGH_ENABLE = 1'b0
) (
    input  logic clk,
    input  logic reset,
    input  logic flush_i,
    input  logic selective_kill_valid_i,
    input  logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_i,

    input  logic issue_valid_i,
    input  bbus_ooo_alu_iq_uop_t issue_uop_i,
    input  logic [31:0] src1_data_i,
    input  logic [31:0] src2_data_i,
    input  logic [2:0] issue_kind_i,
    output logic issue_ready_o,
    output logic issue_accept_o,

    output logic completion_valid_o,
    input  logic completion_ready_i,
    output bbus_ooo_writeback_t completion_wb_o,
    output logic [2:0] completion_kind_o,

    input  bbus_ooo_commit_event_t commit_event_i,

    output logic occupied_o,
    output logic flush_drop_o,
    output logic selective_kill_drop_o,
    output logic illegal_issue_o,
    output logic ebreak_accept_o,
    output logic exception_accept_o,
    output logic [31:0] debug_csr_mstatus_o,
    output logic [31:0] debug_csr_mtvec_o,
    output logic [31:0] debug_csr_mepc_o,
    output logic [31:0] debug_csr_mcause_o,
    output logic [31:0] debug_csr_satp_o,
    output logic [1:0] debug_priv_mode_o,
    output logic [31:0] debug_trap_target_o,
    output logic [31:0] debug_xret_target_o,
    output logic debug_store_fallthrough_valid_o,
    output logic debug_store_fallthrough_accept_o,
    output logic debug_store_fallthrough_capture_o,
    output logic fallthrough_conservation_error_o
);
`ifdef NPC_OOO_EBREAK_TRAP
    localparam bit EBREAK_TRAP_ENABLE = 1'b1;
`else
    localparam bit EBREAK_TRAP_ENABLE = 1'b0;
`endif
`ifdef NPC_SV32
    localparam bit SV32_ENABLE = 1'b1;
`else
    localparam bit SV32_ENABLE = 1'b0;
`endif
    localparam logic [2:0] SK_BRU = 3'd0;
    localparam logic [2:0] SK_LSU = 3'd1;
    localparam logic [2:0] SK_CSR = 3'd2;
    localparam logic [2:0] SK_SYS = 3'd3;
    localparam logic [2:0] SK_MDU = 3'd4;

    typedef enum logic {
        SERIAL_IDLE,
        SERIAL_DONE
    } serial_state_e;

    serial_state_e state_q;
    bbus_ooo_writeback_t completion_q;
    logic [2:0] completion_kind_q;
    logic [31:0] csr_mstatus_q;
    logic [31:0] csr_mtvec_q;
    logic [31:0] csr_mepc_q;
    logic [31:0] csr_mcause_q;
    logic [31:0] csr_mscratch_q;
    logic [31:0] csr_mie_q;
    logic [31:0] csr_mip_q;
    logic [31:0] csr_mtval_q;
    logic [31:0] csr_mcounteren_q;
    logic [31:0] csr_medeleg_q;
    logic [31:0] csr_mideleg_q;
    logic [31:0] csr_stvec_q;
    logic [31:0] csr_sscratch_q;
    logic [31:0] csr_sepc_q;
    logic [31:0] csr_scause_q;
    logic [31:0] csr_stval_q;
    logic [31:0] csr_scounteren_q;
    logic [31:0] csr_satp_q;
    logic [1:0] priv_mode_q;

    logic issue_is_store_c;
    logic issue_is_csr_c;
    logic issue_is_ebreak_c;
    logic issue_is_ecall_c;
    logic issue_is_mret_c;
    logic issue_is_sret_c;
    logic issue_is_wfi_c;
    logic issue_is_sfence_vma_c;
    logic issue_is_fence_c;
    logic issue_is_fencei_c;
    logic issue_is_exception_c;
    logic issue_is_mdu_c;
    logic issue_legal_c;
    logic issue_fire_c;
    logic completion_fire_c;
    logic store_fallthrough_valid_c;
    logic store_fallthrough_accept_c;
    logic store_fallthrough_capture_c;
    logic local_completion_killed_c;
    logic mdu_selective_drop;
    logic local_completion_valid_c;
    logic mdu_issue_valid;
    logic mdu_issue_ready;
    logic mdu_issue_accept;
    logic mdu_completion_valid;
    logic mdu_completion_ready;
    bbus_ooo_writeback_t mdu_completion_wb;
    logic mdu_occupied;
    logic mdu_flush_drop;
    logic mdu_illegal_issue;
    logic [31:0] issue_addr_c;
    logic [2:0] issue_len_c;
    logic [3:0] issue_wstrb_c;
    logic [31:0] issue_wdata_c;
    logic issue_misaligned_c;
    logic [31:0] csr_read_data_c;
    logic [31:0] csr_operand_c;
    logic csr_write_c;
    logic csr_access_illegal_c;
    logic mret_illegal_c;
    logic sret_illegal_c;
    logic wfi_illegal_c;
    logic sfence_illegal_c;
    logic commit_trap_delegated_c;
    logic [31:0] commit_trap_cause_c;
    logic [31:0] issue_trap_target_c;
    logic [31:0] csr_wdata_c;
    bbus_ooo_writeback_t issue_completion_c;

    function automatic logic [2:0] mem_len(input bbus_ooo_mem_op_e mem_op);
        begin
            unique case (mem_op)
                BBUS_OOO_MEM_H_S,
                BBUS_OOO_MEM_H_U: mem_len = 3'd2;
                BBUS_OOO_MEM_W:   mem_len = 3'd4;
                default:          mem_len = 3'd1;
            endcase
        end
    endfunction

    function automatic logic mem_misaligned(
        input bbus_ooo_mem_op_e mem_op,
        input logic [31:0] addr
    );
        begin
            unique case (mem_op)
                BBUS_OOO_MEM_H_S,
                BBUS_OOO_MEM_H_U: mem_misaligned = addr[0];
                BBUS_OOO_MEM_W:   mem_misaligned = (addr[1:0] != 2'b00);
                default:          mem_misaligned = 1'b0;
            endcase
        end
    endfunction

    function automatic logic [31:0] csr_read_value(input logic [11:0] addr);
        begin
            unique case (addr)
`ifdef NPC_S_EXTENSION
                12'h100: csr_read_value = csr_mstatus_q & 32'h000c_0122;
                12'h104: csr_read_value = csr_mie_q & csr_mideleg_q & 32'h0000_0222;
                12'h105: csr_read_value = csr_stvec_q;
                12'h106: csr_read_value = csr_scounteren_q;
                12'h140: csr_read_value = csr_sscratch_q;
                12'h141: csr_read_value = csr_sepc_q;
                12'h142: csr_read_value = csr_scause_q;
                12'h143: csr_read_value = csr_stval_q;
                12'h144: csr_read_value = csr_mip_q & csr_mideleg_q & 32'h0000_0222;
                12'h180: csr_read_value = csr_satp_q;
`endif
                12'h300: csr_read_value = csr_mstatus_q;
                12'h301: begin
                    csr_read_value = 32'h4010_0100;
`ifdef NPC_M_EXTENSION
                    csr_read_value = csr_read_value | 32'h0000_1000;
`endif
`ifdef NPC_A_EXTENSION
                    csr_read_value = csr_read_value | 32'h0000_0001;
`endif
`ifdef NPC_S_EXTENSION
                    csr_read_value = csr_read_value | 32'h0004_0000;
`endif
                end
                12'h302: csr_read_value = csr_medeleg_q;
                12'h303: csr_read_value = csr_mideleg_q;
                12'h304: csr_read_value = csr_mie_q;
                12'h305: csr_read_value = csr_mtvec_q;
                12'h306: csr_read_value = csr_mcounteren_q;
                12'h340: csr_read_value = csr_mscratch_q;
                12'h341: csr_read_value = csr_mepc_q;
                12'h342: csr_read_value = csr_mcause_q;
                12'h343: csr_read_value = csr_mtval_q;
                12'h344: csr_read_value = csr_mip_q;
                12'hb00,
                12'hb02,
                12'hb80,
                12'hb82,
                12'hc00,
                12'hc02,
                12'hc80,
                12'hc82: begin
                    // TODO(S9_COUNTERS): add architectural mcycle/minstret
                    // state and a directed DUT/NEMU counter test.
                    csr_read_value = 32'b0;
                end
                12'hf11: csr_read_value = 32'b0;
                12'hf12: csr_read_value = 32'h0000_0005;
                12'hf13: csr_read_value = 32'b0;
                12'hf14: csr_read_value = 32'b0;
                default: csr_read_value = 32'b0;
            endcase
        end
    endfunction

    function automatic logic csr_implemented(input logic [11:0] addr);
        begin
            unique case (addr)
`ifdef NPC_S_EXTENSION
                12'h100, 12'h104, 12'h105, 12'h106,
                12'h140, 12'h141, 12'h142, 12'h143, 12'h144, 12'h180,
`endif
                12'h300, 12'h301, 12'h302, 12'h303, 12'h304, 12'h305,
                12'h306, 12'h340, 12'h341, 12'h342, 12'h343, 12'h344,
                12'h3a0, 12'h3b0,
                12'h7a0, 12'h7a1, 12'h7a2, 12'h7a3, 12'h7a4,
                12'hb00, 12'hb02, 12'hb80, 12'hb82,
                12'hc00, 12'hc02, 12'hc80, 12'hc82,
                12'hf11, 12'hf12, 12'hf13, 12'hf14:
                    csr_implemented = 1'b1;
                default: csr_implemented = 1'b0;
            endcase
        end
    endfunction

    function automatic logic csr_counter_access_ok(
        input logic [11:0] addr,
        input logic [1:0] priv,
        input logic [31:0] mcounteren,
        input logic [31:0] scounteren
    );
        logic enabled;
        begin
            csr_counter_access_ok = 1'b1;
            enabled = 1'b1;
            if (priv != 2'b11) begin
                unique case (addr)
                    12'hc00, 12'hc80: enabled = mcounteren[0];
                    12'hc02, 12'hc82: enabled = mcounteren[2];
                    default: enabled = 1'b1;
                endcase
                if ((priv == 2'b00) && enabled) begin
                    unique case (addr)
                        12'hc00, 12'hc80: enabled = scounteren[0];
                        12'hc02, 12'hc82: enabled = scounteren[2];
                        default: enabled = 1'b1;
                    endcase
                end
            end
            csr_counter_access_ok = enabled;
        end
    endfunction

    function automatic logic [31:0] mstatus_warl(input logic [31:0] value);
        logic [31:0] result;
        begin
`ifdef NPC_S_EXTENSION
            result = value & 32'h007e_19aa;
            if (value[12:11] == 2'b10) begin
                result[12:11] = 2'b00;
            end
`else
            result = value & 32'h0002_1888;
            if ((value[12:11] == 2'b01) || (value[12:11] == 2'b10)) begin
                result[12:11] = 2'b00;
            end
`endif
            mstatus_warl = result;
        end
    endfunction

    function automatic logic [31:0] csr_write_mask(input logic [11:0] addr);
        begin
            unique case (addr)
                12'h100: csr_write_mask = 32'h000c_0122;
                12'h104, 12'h144: csr_write_mask = csr_mideleg_q & 32'h0000_0222;
`ifdef NPC_S_EXTENSION
                12'h300: csr_write_mask = 32'h007e_19aa;
`else
                12'h300: csr_write_mask = 32'h0002_1888;
`endif
                12'h302: csr_write_mask = 32'h0000_b3ff;
                12'h303: csr_write_mask = 32'h0000_0222;
                default: csr_write_mask = 32'hffff_ffff;
            endcase
        end
    endfunction

    function automatic logic [31:0] csr_apply_write(
        input logic [11:0] addr,
        input logic [31:0] old_value,
        input logic [31:0] wdata
    );
        logic [31:0] mask;
        begin
            mask = csr_write_mask(addr);
            csr_apply_write = (old_value & ~mask) | (wdata & mask);
        end
    endfunction

    function automatic logic [31:0] csr_trap_mstatus(
        input logic [31:0] old_mstatus,
        input logic [1:0] old_priv
    );
        begin
            csr_trap_mstatus =
                (old_mstatus & ~32'h0000_1888) |
                ({30'b0, old_priv} << 11) |
                ({31'b0, old_mstatus[3]} << 7);
        end
    endfunction

    function automatic logic [31:0] ecall_cause(input logic [1:0] priv);
        begin
            unique case (priv)
                2'b00: ecall_cause = 32'd8;
                2'b01: ecall_cause = 32'd9;
                default: ecall_cause = 32'd11;
            endcase
        end
    endfunction

    function automatic logic [31:0] csr_mret_mstatus(input logic [31:0] old_mstatus);
        logic [31:0] next_status;
        logic [1:0] return_priv;
        begin
            return_priv = old_mstatus[12:11];
            next_status = (old_mstatus & ~32'h0000_0008) |
                ({31'b0, old_mstatus[7]} << 3);
            next_status = next_status | 32'h0000_0080;
            next_status = next_status & ~32'h0000_1800;
            if (return_priv != 2'b11) begin
                next_status = next_status & ~32'h0002_0000;
            end
            csr_mret_mstatus = next_status;
        end
    endfunction

    function automatic logic [31:0] csr_sret_mstatus(input logic [31:0] old_mstatus);
        logic [31:0] next_status;
        begin
            next_status = (old_mstatus & ~32'h0000_0002) |
                ({31'b0, old_mstatus[5]} << 1);
            next_status = next_status | 32'h0000_0020;
            next_status = next_status & ~32'h0002_0100;
            csr_sret_mstatus = next_status;
        end
    endfunction

    function automatic logic [31:0] csr_trap_sstatus(
        input logic [31:0] old_mstatus,
        input logic [1:0] old_priv
    );
        logic [31:0] next_status;
        begin
            next_status = (old_mstatus & ~32'h0000_0122) |
                ({31'b0, old_mstatus[1]} << 5);
            if (old_priv == 2'b01) next_status = next_status | 32'h0000_0100;
            csr_trap_sstatus = next_status;
        end
    endfunction

    assign issue_is_store_c = issue_uop_i.valid && issue_uop_i.is_store &&
        (issue_kind_i == SK_LSU);
    assign issue_is_csr_c = issue_uop_i.valid && issue_uop_i.is_csr &&
        (issue_kind_i == SK_CSR);
    assign issue_is_ebreak_c = issue_uop_i.valid && issue_uop_i.is_system &&
        (issue_uop_i.instr == 32'h0010_0073) && (issue_kind_i == SK_SYS);
    assign issue_is_ecall_c = issue_uop_i.valid && issue_uop_i.is_system &&
        (issue_uop_i.instr == 32'h0000_0073) && (issue_kind_i == SK_SYS);
    assign issue_is_mret_c = issue_uop_i.valid && issue_uop_i.is_system &&
        (issue_uop_i.instr == 32'h3020_0073) && (issue_kind_i == SK_SYS);
    assign issue_is_sret_c = issue_uop_i.valid && issue_uop_i.is_system &&
        (issue_uop_i.instr == 32'h1020_0073) && (issue_kind_i == SK_SYS);
    assign issue_is_wfi_c = issue_uop_i.valid && issue_uop_i.is_system &&
        (issue_uop_i.instr == 32'h1050_0073) && (issue_kind_i == SK_SYS);
    assign issue_is_sfence_vma_c = issue_uop_i.valid && issue_uop_i.is_system &&
        (issue_uop_i.instr[31:25] == 7'b0001001) &&
        (issue_uop_i.instr[14:7] == 8'b0) && (issue_kind_i == SK_SYS);
    assign issue_is_fence_c = issue_uop_i.valid && issue_uop_i.is_system &&
        (issue_uop_i.instr[6:0] == 7'b0001111) &&
        (issue_uop_i.instr[14:12] == 3'b000) &&
        (issue_uop_i.instr[11:7] == 5'd0) &&
        (issue_uop_i.instr[19:15] == 5'd0) &&
        (issue_kind_i == SK_SYS);
    assign issue_is_fencei_c = issue_uop_i.valid && issue_uop_i.is_system &&
        (issue_uop_i.instr == 32'h0000_100f) && (issue_kind_i == SK_SYS);
    assign issue_is_exception_c = issue_uop_i.valid && issue_uop_i.exception.valid &&
        (issue_kind_i == SK_LSU);
`ifdef NPC_M_EXTENSION
    assign issue_is_mdu_c = issue_uop_i.valid &&
        (issue_uop_i.fu_type == BBUS_OOO_FU_MDU) &&
        (issue_kind_i == SK_MDU);
`else
    assign issue_is_mdu_c = 1'b0;
`endif
    assign issue_legal_c = issue_is_store_c || issue_is_csr_c ||
        issue_is_ebreak_c || issue_is_ecall_c || issue_is_mret_c ||
        issue_is_sret_c || issue_is_wfi_c || issue_is_sfence_vma_c ||
        issue_is_fence_c || issue_is_fencei_c || issue_is_exception_c ||
        issue_is_mdu_c;

    assign local_completion_killed_c = selective_kill_valid_i &&
        (state_q == SERIAL_DONE) && completion_q.rob_tag.valid &&
        selective_killed_rob_mask_i[completion_q.rob_tag.idx];
    assign issue_ready_o = !reset && !flush_i && !selective_kill_valid_i &&
        (state_q == SERIAL_IDLE) && !mdu_occupied && issue_legal_c &&
        (!issue_is_mdu_c || mdu_issue_ready);
    assign issue_fire_c = issue_valid_i && issue_ready_o;
    assign issue_accept_o = issue_fire_c;
    assign local_completion_valid_c = !reset && !flush_i &&
        !selective_kill_valid_i &&
        (state_q == SERIAL_DONE);
    assign store_fallthrough_valid_c =
        STORE_ISSUE_FINAL_FALLTHROUGH_ENABLE && issue_fire_c &&
        issue_is_store_c && !issue_completion_c.exception.valid;
    assign store_fallthrough_accept_c = store_fallthrough_valid_c &&
        completion_ready_i;
    assign store_fallthrough_capture_c = store_fallthrough_valid_c &&
        !completion_ready_i;
    assign completion_valid_o = mdu_completion_valid ||
        local_completion_valid_c || store_fallthrough_valid_c;
    assign completion_wb_o = mdu_completion_valid ? mdu_completion_wb :
        local_completion_valid_c ? completion_q :
        store_fallthrough_valid_c ? issue_completion_c : completion_q;
    assign completion_kind_o = mdu_completion_valid ? SK_MDU :
        local_completion_valid_c ? completion_kind_q :
        store_fallthrough_valid_c ? SK_LSU : completion_kind_q;
    assign completion_fire_c = local_completion_valid_c && completion_ready_i &&
        !mdu_completion_valid;
    assign mdu_completion_ready = completion_ready_i && mdu_completion_valid;
    assign occupied_o = (state_q == SERIAL_DONE) || mdu_occupied;
    assign flush_drop_o = (flush_i && (state_q == SERIAL_DONE)) || mdu_flush_drop;
    assign selective_kill_drop_o = local_completion_killed_c ||
        mdu_selective_drop;
    assign illegal_issue_o = issue_valid_i && !issue_legal_c;
    assign mdu_issue_valid = issue_valid_i && issue_is_mdu_c &&
        (state_q == SERIAL_IDLE) && !flush_i && !selective_kill_valid_i;
    assign debug_store_fallthrough_valid_o = store_fallthrough_valid_c;
    assign debug_store_fallthrough_accept_o = store_fallthrough_accept_c;
    assign debug_store_fallthrough_capture_o = store_fallthrough_capture_c;
    assign fallthrough_conservation_error_o =
        (store_fallthrough_accept_c && store_fallthrough_capture_c) ||
        (store_fallthrough_valid_c && local_completion_valid_c) ||
        (store_fallthrough_valid_c && mdu_completion_valid) ||
        (store_fallthrough_valid_c &&
         ((completion_wb_o != issue_completion_c) ||
          (completion_kind_o != SK_LSU)));

`ifdef NPC_M_EXTENSION
    ooo_mdu_pipeline_1w #(
        .MUL_COMPLETION_FALLTHROUGH_ENABLE(
            MDU_MUL_COMPLETION_FALLTHROUGH_ENABLE)
    ) u_mdu (
        .clk(clk),
        .reset(reset),
        .flush_i(flush_i),
        .selective_kill_valid_i(selective_kill_valid_i),
        .selective_killed_rob_mask_i(selective_killed_rob_mask_i),
        .selective_kill_drop_o(mdu_selective_drop),
        .issue_valid_i(mdu_issue_valid),
        .issue_uop_i(issue_uop_i),
        .src1_data_i(src1_data_i),
        .src2_data_i(src2_data_i),
        .issue_ready_o(mdu_issue_ready),
        .issue_accept_o(mdu_issue_accept),
        .completion_wb_o(mdu_completion_wb),
        .completion_valid_o(mdu_completion_valid),
        .completion_ready_i(mdu_completion_ready),
        .occupied_o(mdu_occupied),
        .flush_drop_o(mdu_flush_drop),
        .illegal_issue_o(mdu_illegal_issue)
    );
`else
    assign mdu_issue_ready = 1'b0;
    assign mdu_issue_accept = 1'b0;
    assign mdu_completion_valid = 1'b0;
    assign mdu_completion_wb = '0;
    assign mdu_occupied = 1'b0;
    assign mdu_flush_drop = 1'b0;
    assign mdu_selective_drop = 1'b0;
    assign mdu_illegal_issue = 1'b0;
`endif

    assign issue_addr_c = src1_data_i + issue_uop_i.imm;
    assign issue_trap_target_c =
`ifdef NPC_S_EXTENSION
        ((priv_mode_q != 2'b11) && csr_medeleg_q[ecall_cause(priv_mode_q)]) ?
            {csr_stvec_q[31:2], 2'b00} :
`endif
            {csr_mtvec_q[31:2], 2'b00};
    assign issue_len_c = mem_len(issue_uop_i.mem_op);
    assign issue_wstrb_c =
        ((issue_len_c == 3'd1) ? 4'b0001 :
         (issue_len_c == 3'd2) ? 4'b0011 : 4'b1111) << issue_addr_c[1:0];
    assign issue_wdata_c = src2_data_i << {issue_addr_c[1:0], 3'b000};
    assign issue_misaligned_c = mem_misaligned(issue_uop_i.mem_op, issue_addr_c);
    assign csr_read_data_c = csr_read_value(issue_uop_i.csr_addr);
    assign csr_operand_c = issue_uop_i.instr[14] ?
        {27'b0, issue_uop_i.instr[19:15]} : src1_data_i;

    always_comb begin
        csr_write_c = 1'b0;
        csr_wdata_c = csr_read_data_c;
        unique case (issue_uop_i.instr[14:12])
            3'b001,
            3'b101: begin
                csr_write_c = issue_is_csr_c;
                csr_wdata_c = csr_operand_c;
            end
            3'b010,
            3'b110: begin
                csr_write_c = issue_is_csr_c && (issue_uop_i.instr[19:15] != 5'd0);
                csr_wdata_c = csr_read_data_c | csr_operand_c;
            end
            3'b011,
            3'b111: begin
                csr_write_c = issue_is_csr_c && (issue_uop_i.instr[19:15] != 5'd0);
                csr_wdata_c = csr_read_data_c & ~csr_operand_c;
            end
            default: begin
                csr_write_c = 1'b0;
                csr_wdata_c = csr_read_data_c;
            end
        endcase

        csr_access_illegal_c = issue_is_csr_c &&
            (!csr_implemented(issue_uop_i.csr_addr) ||
             (priv_mode_q < issue_uop_i.csr_addr[9:8]) ||
             (csr_write_c && (issue_uop_i.csr_addr[11:10] == 2'b11)) ||
             ((issue_uop_i.csr_addr == 12'h180) && (priv_mode_q == 2'b01) &&
              csr_mstatus_q[20]) ||
             !csr_counter_access_ok(
                 issue_uop_i.csr_addr,
                 priv_mode_q,
                 csr_mcounteren_q,
                 csr_scounteren_q
             ));
        mret_illegal_c = issue_is_mret_c && (priv_mode_q != 2'b11);
`ifdef NPC_S_EXTENSION
        sret_illegal_c = issue_is_sret_c &&
            ((priv_mode_q == 2'b00) || ((priv_mode_q == 2'b01) && csr_mstatus_q[22]));
        wfi_illegal_c = issue_is_wfi_c &&
            ((priv_mode_q == 2'b00) || ((priv_mode_q == 2'b01) && csr_mstatus_q[21]));
        sfence_illegal_c = issue_is_sfence_vma_c &&
            ((priv_mode_q == 2'b00) || ((priv_mode_q == 2'b01) && csr_mstatus_q[20]));
`else
        sret_illegal_c = issue_is_sret_c;
        wfi_illegal_c = issue_is_wfi_c;
        sfence_illegal_c = issue_is_sfence_vma_c;
`endif

        issue_completion_c = '0;
        issue_completion_c.valid = issue_valid_i;
        issue_completion_c.rob_tag = issue_uop_i.rob_tag;
        issue_completion_c.phys_rd = issue_uop_i.phys_rd_new;
        issue_completion_c.done = 1'b1;

        if (issue_is_store_c) begin
            issue_completion_c.rf_wen = 1'b0;
            issue_completion_c.is_store = 1'b1;
            issue_completion_c.mem_op = issue_uop_i.mem_op;
            issue_completion_c.mem_addr = issue_addr_c;
            issue_completion_c.mem_wdata = issue_wdata_c;
            issue_completion_c.mem_wstrb = issue_wstrb_c;
            issue_completion_c.mem_len = issue_len_c;
            if (issue_misaligned_c) begin
                issue_completion_c.exception.valid = 1'b1;
                issue_completion_c.exception.cause = 32'd6;
                issue_completion_c.exception.tval = issue_addr_c;
            end
        end else if (issue_is_csr_c) begin
            if (csr_access_illegal_c) begin
                issue_completion_c.rf_wen = 1'b0;
                issue_completion_c.exception.valid = 1'b1;
                issue_completion_c.exception.cause = 32'd2;
                issue_completion_c.exception.tval = issue_uop_i.instr;
            end else begin
                issue_completion_c.rf_wen = issue_uop_i.rf_wen;
                issue_completion_c.result = csr_read_data_c;
                issue_completion_c.is_csr = 1'b1;
                issue_completion_c.is_system = issue_uop_i.is_system;
                issue_completion_c.csr_addr = issue_uop_i.csr_addr;
                issue_completion_c.csr_write = csr_write_c;
                issue_completion_c.csr_wdata = csr_wdata_c;
            end
        end else if (mret_illegal_c || sret_illegal_c ||
                     wfi_illegal_c || sfence_illegal_c) begin
            issue_completion_c.rf_wen = 1'b0;
            issue_completion_c.exception.valid = 1'b1;
            issue_completion_c.exception.cause = 32'd2;
            issue_completion_c.exception.tval = issue_uop_i.instr;
        end else if (issue_is_ecall_c || issue_is_mret_c ||
                     issue_is_sret_c || issue_is_fencei_c ||
                     (SV32_ENABLE && issue_is_sfence_vma_c)) begin
            issue_completion_c.rf_wen = 1'b0;
            issue_completion_c.is_control = 1'b1;
            issue_completion_c.actual_taken = 1'b1;
            issue_completion_c.actual_nextpc =
                issue_is_ecall_c ? issue_trap_target_c :
                issue_is_mret_c ? csr_mepc_q :
                issue_is_sret_c ? csr_sepc_q :
                (issue_uop_i.pc + 32'd4);
            issue_completion_c.redirect_valid = 1'b1;
            issue_completion_c.is_system = 1'b1;
        end else if (issue_is_ebreak_c) begin
            issue_completion_c.rf_wen = 1'b0;
            if (EBREAK_TRAP_ENABLE) begin
                issue_completion_c.exception.valid = 1'b1;
                issue_completion_c.exception.cause = 32'd3;
                issue_completion_c.exception.tval = 32'b0;
            end else begin
                issue_completion_c.is_system = 1'b1;
            end
        end else if (issue_is_fence_c || issue_is_wfi_c || issue_is_sfence_vma_c) begin
            issue_completion_c.rf_wen = 1'b0;
            issue_completion_c.is_system = 1'b1;
        end else if (issue_is_exception_c) begin
            issue_completion_c.rf_wen = 1'b0;
            issue_completion_c.exception = issue_uop_i.exception;
        end
    end

    assign debug_csr_mstatus_o = csr_mstatus_q;
    assign debug_csr_mtvec_o = csr_mtvec_q;
    assign debug_csr_mepc_o = csr_mepc_q;
    assign debug_csr_mcause_o = csr_mcause_q;
    assign debug_csr_satp_o = csr_satp_q;
    assign debug_priv_mode_o = priv_mode_q;
    always_comb begin
        commit_trap_cause_c = commit_event_i.slot0.exception.valid ?
            commit_event_i.slot0.exception.cause : ecall_cause(priv_mode_q);
        commit_trap_delegated_c = 1'b0;
`ifdef NPC_S_EXTENSION
        commit_trap_delegated_c = (priv_mode_q != 2'b11) &&
            csr_medeleg_q[commit_trap_cause_c[4:0]];
`endif
        debug_trap_target_o = commit_trap_delegated_c ?
            {csr_stvec_q[31:2], 2'b00} : {csr_mtvec_q[31:2], 2'b00};
        debug_xret_target_o =
            (commit_event_i.slot0.instr == 32'h1020_0073) ? csr_sepc_q : csr_mepc_q;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state_q <= SERIAL_IDLE;
            completion_q <= '0;
            completion_kind_q <= SK_SYS;
            ebreak_accept_o <= 1'b0;
            exception_accept_o <= 1'b0;
            csr_mstatus_q <= 32'h0000_1800;
            csr_mtvec_q <= 32'b0;
            csr_mepc_q <= 32'b0;
            csr_mcause_q <= 32'b0;
            csr_mscratch_q <= 32'b0;
            csr_mie_q <= 32'b0;
            csr_mip_q <= 32'b0;
            csr_mtval_q <= 32'b0;
            csr_mcounteren_q <= 32'b0;
            csr_medeleg_q <= 32'b0;
            csr_mideleg_q <= 32'b0;
            csr_stvec_q <= 32'b0;
            csr_sscratch_q <= 32'b0;
            csr_sepc_q <= 32'b0;
            csr_scause_q <= 32'b0;
            csr_stval_q <= 32'b0;
            csr_scounteren_q <= 32'b0;
            csr_satp_q <= 32'b0;
            priv_mode_q <= 2'b11;
        end else begin
            ebreak_accept_o <= 1'b0;
            exception_accept_o <= 1'b0;

            if (commit_event_i.normal_commit_mask[0] &&
                commit_event_i.slot0.is_csr && commit_event_i.slot0.csr_write) begin
                unique case (commit_event_i.slot0.csr_addr)
                    12'h300: csr_mstatus_q <= mstatus_warl(csr_apply_write(
                        commit_event_i.slot0.csr_addr,
                        csr_mstatus_q,
                        commit_event_i.slot0.csr_wdata
                    ));
`ifdef NPC_S_EXTENSION
                    12'h100: csr_mstatus_q <= mstatus_warl(csr_apply_write(
                        commit_event_i.slot0.csr_addr,
                        csr_mstatus_q,
                        commit_event_i.slot0.csr_wdata
                    ));
                    12'h104: csr_mie_q <= csr_apply_write(
                        commit_event_i.slot0.csr_addr,
                        csr_mie_q,
                        commit_event_i.slot0.csr_wdata
                    );
                    12'h105: csr_stvec_q <= {commit_event_i.slot0.csr_wdata[31:2],
                        (commit_event_i.slot0.csr_wdata[1:0] == 2'b01) ? 2'b01 : 2'b00};
                    12'h106: csr_scounteren_q <= commit_event_i.slot0.csr_wdata;
                    12'h140: csr_sscratch_q <= commit_event_i.slot0.csr_wdata;
                    12'h141: csr_sepc_q <= {commit_event_i.slot0.csr_wdata[31:2], 2'b00};
                    12'h142: csr_scause_q <= commit_event_i.slot0.csr_wdata;
                    12'h143: csr_stval_q <= commit_event_i.slot0.csr_wdata;
                    12'h144: csr_mip_q <= csr_apply_write(
                        commit_event_i.slot0.csr_addr,
                        csr_mip_q,
                        commit_event_i.slot0.csr_wdata
                    );
                    12'h180: begin
`ifdef NPC_SV32
                        csr_satp_q <= {
                            commit_event_i.slot0.csr_wdata[31],
                            commit_event_i.slot0.csr_wdata[30:22],
                            commit_event_i.slot0.csr_wdata[21:0]
                        };
`else
                        csr_satp_q <= 32'b0;
`endif
                    end
`endif
                    12'h302: csr_medeleg_q <= commit_event_i.slot0.csr_wdata & 32'h0000_b3ff;
                    12'h303: csr_mideleg_q <= commit_event_i.slot0.csr_wdata & 32'h0000_0222;
                    12'h304: csr_mie_q <= commit_event_i.slot0.csr_wdata;
                    12'h305: csr_mtvec_q <= {commit_event_i.slot0.csr_wdata[31:2],
                        (commit_event_i.slot0.csr_wdata[1:0] == 2'b01) ? 2'b01 : 2'b00};
                    12'h306: csr_mcounteren_q <= commit_event_i.slot0.csr_wdata;
                    12'h340: csr_mscratch_q <= commit_event_i.slot0.csr_wdata;
                    12'h341: csr_mepc_q <= {commit_event_i.slot0.csr_wdata[31:2], 2'b00};
                    12'h342: csr_mcause_q <= commit_event_i.slot0.csr_wdata;
                    12'h343: csr_mtval_q <= commit_event_i.slot0.csr_wdata;
                    12'h344: csr_mip_q <= commit_event_i.slot0.csr_wdata;
                    default: begin end
                endcase
            end

            if (commit_event_i.normal_commit_mask[0] &&
                commit_event_i.slot0.is_system) begin
                if (commit_event_i.slot0.instr == 32'h0000_0073) begin
                    if (commit_trap_delegated_c) begin
                        csr_scause_q <= ecall_cause(priv_mode_q);
                        csr_sepc_q <= commit_event_i.slot0.pc;
                        csr_stval_q <= 32'b0;
                        csr_mstatus_q <= csr_trap_sstatus(csr_mstatus_q, priv_mode_q);
                        priv_mode_q <= 2'b01;
                    end else begin
                        csr_mcause_q <= ecall_cause(priv_mode_q);
                        csr_mepc_q <= commit_event_i.slot0.pc;
                        csr_mtval_q <= 32'b0;
                        csr_mstatus_q <= csr_trap_mstatus(csr_mstatus_q, priv_mode_q);
                        priv_mode_q <= 2'b11;
                    end
                end else if (commit_event_i.slot0.instr == 32'h3020_0073) begin
                    priv_mode_q <= csr_mstatus_q[12:11];
                    csr_mstatus_q <= csr_mret_mstatus(csr_mstatus_q);
                end else if (commit_event_i.slot0.instr == 32'h1020_0073) begin
                    priv_mode_q <= csr_mstatus_q[8] ? 2'b01 : 2'b00;
                    csr_mstatus_q <= csr_sret_mstatus(csr_mstatus_q);
                end
            end

            if (commit_event_i.control_event_valid &&
                (commit_event_i.control_event == BBUS_OOO_CTRL_EXCEPTION)) begin
                if (commit_trap_delegated_c) begin
                    csr_scause_q <= commit_event_i.slot0.exception.cause;
                    csr_sepc_q <= commit_event_i.slot0.pc;
                    csr_stval_q <= commit_event_i.slot0.exception.tval;
                    csr_mstatus_q <= csr_trap_sstatus(csr_mstatus_q, priv_mode_q);
                    priv_mode_q <= 2'b01;
                end else begin
                    csr_mcause_q <= commit_event_i.slot0.exception.cause;
                    csr_mepc_q <= commit_event_i.slot0.pc;
                    csr_mtval_q <= commit_event_i.slot0.exception.tval;
                    csr_mstatus_q <= csr_trap_mstatus(csr_mstatus_q, priv_mode_q);
                    priv_mode_q <= 2'b11;
                end
            end

            if (flush_i) begin
                state_q <= SERIAL_IDLE;
                completion_q <= '0;
            end else if (selective_kill_valid_i) begin
                if (local_completion_killed_c) begin
                    state_q <= SERIAL_IDLE;
                    completion_q <= '0;
                end
            end else if (state_q == SERIAL_DONE) begin
                if (completion_fire_c) begin
                    state_q <= SERIAL_IDLE;
                    completion_q <= '0;
                end
            end else if (issue_fire_c && !issue_is_mdu_c) begin
                ebreak_accept_o <= issue_is_ebreak_c && !EBREAK_TRAP_ENABLE;
                exception_accept_o <= issue_is_exception_c;
                if (store_fallthrough_accept_c) begin
                    completion_q <= '0;
                    state_q <= SERIAL_IDLE;
                end else begin
                    completion_q <= issue_completion_c;
                    if (issue_is_store_c || issue_is_exception_c) begin
                        completion_kind_q <= SK_LSU;
                    end else if (issue_is_csr_c) begin
                        completion_kind_q <= SK_CSR;
                    end else begin
                        completion_kind_q <= SK_SYS;
                    end
                    state_q <= SERIAL_DONE;
                end
            end
        end
    end

    /* verilator lint_off UNUSED */
    wire sk_bru_unused = ^SK_BRU;
    wire mdu_debug_unused = mdu_issue_accept ^ mdu_illegal_issue;
    /* verilator lint_on UNUSED */
endmodule
