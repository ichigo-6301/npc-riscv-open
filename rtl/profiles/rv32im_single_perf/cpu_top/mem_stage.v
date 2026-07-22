`timescale 1ns / 1ps
`include "include/bbus_core_defs.svh"

module mem_stage (
    input clk,
    input rst_n,

    input es_to_ms_valid,
    output ms_allowin,
    input ws_allowin,
    output ms_to_ws_valid,

    input [31:0] es_pc,
    input [31:0] es_instr,
    input [31:0] es_nextpc,
    input [4:0] es_rd,
    input es_reg_wen,
    input [1:0] es_datatoreg,
    input [1:0] es_mem_wr,
    input [2:0] es_mem_op,
    input [31:0] es_aluout,
    input [31:0] es_mem_wdata,
    input es_mem_fwd_dep,
    input [31:0] es_csr_read_data,
    input [1:0] es_csr_wen,
    input [11:0] es_csr_waddr1,
    input [11:0] es_csr_waddr2,
    input [31:0] es_csr_wdata1,
    input [31:0] es_csr_wdata2,
    input es_illegal,
    input es_is_ebreak,
    input [2:0] es_branch,
    input [31:0] es_src1_value,

    output ms_valid,
    output [31:0] ms_pc,
    output [31:0] ms_instr,
    output [31:0] ms_nextpc,
    output [4:0] ms_rd,
    output ms_reg_wen,
    output [1:0] ms_datatoreg,
    output [2:0] ms_mem_op,
    output [31:0] ms_aluout,
    output [31:0] ms_mem_rdata,
    output [31:0] ms_csr_read_data,
    output [1:0] ms_csr_wen,
    output [11:0] ms_csr_waddr1,
    output [11:0] ms_csr_waddr2,
    output [31:0] ms_csr_wdata1,
    output [31:0] ms_csr_wdata2,
    output ms_illegal,
    output ms_is_ebreak,
    output [2:0] ms_branch,
    output [31:0] ms_src1_value,
    output ms_slowpath_prepare_kill_valid,
`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    output ms_stage_block,
    output ms_stage_block_req_phase,
    output ms_stage_block_resp_phase,
    output fast_req_fire_trace,
    output slow_req_fire_trace,
    output slow_req_fwd_dep_fire_trace,
    output slow_req_nonfwd_fire_trace,
`endif
`endif
    output hidden_mreq_valid,
    output hidden_mreq_reg_wen,
    output [4:0] hidden_mreq_rd,
    output [1:0] hidden_mreq_csr_wen,
    output [11:0] hidden_mreq_csr_waddr1,
    output [11:0] hidden_mreq_csr_waddr2,

    output dbus_req_valid,
    input dbus_req_ready,
    output dbus_req_write,
    output [31:0] dbus_req_addr,
    output [31:0] dbus_req_wdata,
    output [3:0] dbus_req_wstrb,
    output [2:0] dbus_req_len,
    input dbus_resp_valid,
    output dbus_resp_ready,
    input [31:0] dbus_resp_data
);
    reg mreq_valid_r;
    reg [31:0] mreq_pc_r;
    reg [31:0] mreq_instr_r;
    reg [31:0] mreq_nextpc_r;
    reg [4:0] mreq_rd_r;
    reg mreq_reg_wen_r;
    reg [1:0] mreq_datatoreg_r;
    reg [1:0] mreq_mem_wr_r;
    reg [2:0] mreq_mem_op_r;
    reg [31:0] mreq_aluout_r;
    reg [31:0] mreq_store_data_r;
    reg [31:0] mreq_csr_read_data_r;
    reg [1:0] mreq_csr_wen_r;
    reg [11:0] mreq_csr_waddr1_r;
    reg [11:0] mreq_csr_waddr2_r;
    reg [31:0] mreq_csr_wdata1_r;
    reg [31:0] mreq_csr_wdata2_r;
    reg mreq_illegal_r;
    reg mreq_is_ebreak_r;
    reg [2:0] mreq_branch_r;
    reg [31:0] mreq_src1_value_r;
    reg mreq_from_fwd_dep_r;

    reg mresp_valid_r;
    reg [31:0] mresp_pc_r;
    reg [31:0] mresp_instr_r;
    reg [31:0] mresp_nextpc_r;
    reg [4:0] mresp_rd_r;
    reg mresp_reg_wen_r;
    reg [1:0] mresp_datatoreg_r;
    reg [2:0] mresp_mem_op_r;
    reg [31:0] mresp_aluout_r;
    reg [31:0] mresp_csr_read_data_r;
    reg [1:0] mresp_csr_wen_r;
    reg [11:0] mresp_csr_waddr1_r;
    reg [11:0] mresp_csr_waddr2_r;
    reg [31:0] mresp_csr_wdata1_r;
    reg [31:0] mresp_csr_wdata2_r;
    reg mresp_illegal_r;
    reg mresp_is_ebreak_r;
    reg [2:0] mresp_branch_r;
    reg [31:0] mresp_src1_value_r;
    wire es_mem_is_load = (es_mem_wr == 2'b01);
    wire es_mem_is_store = (es_mem_wr == 2'b11);
    wire es_mem_access_half = (es_mem_op == 3'b001) || (es_mem_op == 3'b101);
    wire es_mem_access_word = (es_mem_op == 3'b010);
    wire es_mem_addr_misaligned_raw =
        (es_mem_access_word && (es_aluout[1:0] != 2'b00)) ||
        (es_mem_access_half && es_aluout[0]);
    wire es_load_addr_misaligned =
        es_to_ms_valid && !es_illegal && !es_is_ebreak &&
        es_mem_is_load && es_mem_addr_misaligned_raw;
    wire es_store_addr_misaligned =
        es_to_ms_valid && !es_illegal && !es_is_ebreak &&
        es_mem_is_store && es_mem_addr_misaligned_raw;
    wire es_mem_addr_misaligned =
        es_load_addr_misaligned || es_store_addr_misaligned;
    wire [31:0] es_mem_misaligned_cause =
        es_store_addr_misaligned ? 32'd6 : 32'd4;

    wire mreq_need_mem = mreq_valid_r && (mreq_mem_wr_r != 2'b00);
    wire mreq_is_store = (mreq_mem_wr_r == 2'b11);

    wire [4:0] mreq_mem_shift = {mreq_aluout_r[1:0], 3'b000};
    wire [4:0] mresp_mem_shift = {mresp_aluout_r[1:0], 3'b000};
    function [2:0] mem_access_len;
        input [2:0] mem_op;
        begin
            mem_access_len =
                (mem_op == 3'b010) ? 3'd4 :
                ((mem_op == 3'b001) || (mem_op == 3'b101)) ? 3'd2 :
                3'd1;
        end
    endfunction

    function [3:0] byte_mask_for_len;
        input [2:0] len;
        begin
            case (len)
                3'd1: byte_mask_for_len = 4'b0001;
                3'd2: byte_mask_for_len = 4'b0011;
                3'd3: byte_mask_for_len = 4'b0111;
                default: byte_mask_for_len = 4'b1111;
            endcase
        end
    endfunction

    wire [2:0] mreq_access_len = mem_access_len(mreq_mem_op_r);
    wire [3:0] mreq_raw_wstrb = byte_mask_for_len(mreq_access_len);
    wire [31:0] mresp_load_data_aligned = dbus_resp_data >> mresp_mem_shift;
    wire [31:0] mresp_mem_rdata_final = mresp_load_data_aligned;

    wire mem_resp_fire = mresp_valid_r && dbus_resp_valid && dbus_resp_ready;
    wire mem_resp_final_fire = mem_resp_fire;
    wire mresp_can_accept = !mresp_valid_r || mem_resp_final_fire;
    wire mreq_mem_fire =
        mreq_need_mem && mresp_can_accept && dbus_req_ready;
    wire mreq_nonmem_fire = mreq_valid_r && !mreq_need_mem && !mresp_valid_r && ws_allowin;
    wire mreq_consumed = mreq_mem_fire || mreq_nonmem_fire;

    assign ms_allowin = !mreq_valid_r || mreq_consumed;

    assign dbus_req_valid = mreq_need_mem && mresp_can_accept;
    assign dbus_req_write = mreq_is_store;
    assign dbus_req_addr = mreq_aluout_r;
    assign dbus_req_wdata = mreq_store_data_r << mreq_mem_shift;
    assign dbus_req_wstrb = mreq_raw_wstrb << mreq_aluout_r[1:0];
    assign dbus_req_len = mreq_access_len;
    assign dbus_resp_ready = mresp_valid_r && ws_allowin;

    wire mresp_selected = mresp_valid_r;
    wire mresp_ready_go = mresp_valid_r && dbus_resp_valid;
    wire mreq_ready_go = mreq_valid_r && !mreq_need_mem && !mresp_valid_r;

    assign ms_to_ws_valid = (mresp_ready_go || mreq_ready_go) && ws_allowin;
    assign ms_valid = mresp_valid_r || mreq_valid_r;
    assign ms_pc = mresp_selected ? mresp_pc_r : mreq_pc_r;
    assign ms_instr = mresp_selected ? mresp_instr_r : mreq_instr_r;
    assign ms_nextpc = mresp_selected ? mresp_nextpc_r : mreq_nextpc_r;
    assign ms_rd = mresp_selected ? mresp_rd_r : mreq_rd_r;
    assign ms_reg_wen = mresp_selected ? mresp_reg_wen_r : mreq_reg_wen_r;
    assign ms_datatoreg = mresp_selected ? mresp_datatoreg_r : mreq_datatoreg_r;
    assign ms_mem_op = mresp_selected ? mresp_mem_op_r : mreq_mem_op_r;
    assign ms_aluout = mresp_selected ? mresp_aluout_r : mreq_aluout_r;
    assign ms_mem_rdata = mresp_mem_rdata_final;
    assign ms_csr_read_data = mresp_selected ? mresp_csr_read_data_r : mreq_csr_read_data_r;
    assign ms_csr_wen = mresp_selected ? mresp_csr_wen_r : mreq_csr_wen_r;
    assign ms_csr_waddr1 = mresp_selected ? mresp_csr_waddr1_r : mreq_csr_waddr1_r;
    assign ms_csr_waddr2 = mresp_selected ? mresp_csr_waddr2_r : mreq_csr_waddr2_r;
    assign ms_csr_wdata1 = mresp_selected ? mresp_csr_wdata1_r : mreq_csr_wdata1_r;
    assign ms_csr_wdata2 = mresp_selected ? mresp_csr_wdata2_r : mreq_csr_wdata2_r;
    assign ms_illegal = mresp_selected ? mresp_illegal_r : mreq_illegal_r;
    assign ms_is_ebreak = mresp_selected ? mresp_is_ebreak_r : mreq_is_ebreak_r;
    assign ms_branch = mresp_selected ? mresp_branch_r : mreq_branch_r;
    assign ms_src1_value = mresp_selected ? mresp_src1_value_r : mreq_src1_value_r;
    assign ms_slowpath_prepare_kill_valid = es_mem_addr_misaligned;

`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
    assign ms_stage_block = (mreq_valid_r && !mreq_consumed) ||
                            (mresp_valid_r && !dbus_resp_valid);
    assign ms_stage_block_req_phase = mreq_need_mem && !mreq_mem_fire;
    assign ms_stage_block_resp_phase = mresp_valid_r && !dbus_resp_valid;
    // Two-level LSU has no fast request path; all issued memory requests are
    // classified as "slow" for compatibility with existing PipeStat outputs.
    assign fast_req_fire_trace = 1'b0;
    assign slow_req_fire_trace = mreq_mem_fire;
    assign slow_req_fwd_dep_fire_trace = mreq_mem_fire && mreq_from_fwd_dep_r;
    assign slow_req_nonfwd_fire_trace = mreq_mem_fire && !mreq_from_fwd_dep_r;
`endif
`endif
    // When an older memory request is in mresp, the mreq slot is hidden behind
    // it on the normal ms_* outputs. Keep that younger destination visible to
    // ID hazard detection, but do not create another bypass data path.
    assign hidden_mreq_valid = mresp_valid_r && mreq_valid_r;
    assign hidden_mreq_reg_wen = mreq_reg_wen_r;
    assign hidden_mreq_rd = mreq_rd_r;
    assign hidden_mreq_csr_wen = mreq_csr_wen_r;
    assign hidden_mreq_csr_waddr1 = mreq_csr_waddr1_r;
    assign hidden_mreq_csr_waddr2 = mreq_csr_waddr2_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            mreq_valid_r <= 1'b0;
            mreq_pc_r <= 32'b0;
            mreq_instr_r <= 32'b0;
            mreq_nextpc_r <= 32'b0;
            mreq_rd_r <= 5'b0;
            mreq_reg_wen_r <= 1'b0;
            mreq_datatoreg_r <= 2'b00;
            mreq_mem_wr_r <= 2'b00;
            mreq_mem_op_r <= 3'b000;
            mreq_aluout_r <= 32'b0;
            mreq_store_data_r <= 32'b0;
            mreq_csr_read_data_r <= 32'b0;
            mreq_csr_wen_r <= 2'b00;
            mreq_csr_waddr1_r <= 12'b0;
            mreq_csr_waddr2_r <= 12'b0;
            mreq_csr_wdata1_r <= 32'b0;
            mreq_csr_wdata2_r <= 32'b0;
            mreq_illegal_r <= 1'b0;
            mreq_is_ebreak_r <= 1'b0;
            mreq_branch_r <= 3'b000;
            mreq_src1_value_r <= 32'b0;
            mreq_from_fwd_dep_r <= 1'b0;

            mresp_valid_r <= 1'b0;
            mresp_pc_r <= 32'b0;
            mresp_instr_r <= 32'b0;
            mresp_nextpc_r <= 32'b0;
            mresp_rd_r <= 5'b0;
            mresp_reg_wen_r <= 1'b0;
            mresp_datatoreg_r <= 2'b00;
            mresp_mem_op_r <= 3'b000;
            mresp_aluout_r <= 32'b0;
            mresp_csr_read_data_r <= 32'b0;
            mresp_csr_wen_r <= 2'b00;
            mresp_csr_waddr1_r <= 12'b0;
            mresp_csr_waddr2_r <= 12'b0;
            mresp_csr_wdata1_r <= 32'b0;
            mresp_csr_wdata2_r <= 32'b0;
            mresp_illegal_r <= 1'b0;
            mresp_is_ebreak_r <= 1'b0;
            mresp_branch_r <= 3'b000;
            mresp_src1_value_r <= 32'b0;
        end else begin
            if (mem_resp_final_fire && !mreq_mem_fire) begin
                mresp_valid_r <= 1'b0;
            end

            if (mreq_mem_fire) begin
                mresp_valid_r <= 1'b1;
                mresp_pc_r <= mreq_pc_r;
                mresp_instr_r <= mreq_instr_r;
                mresp_nextpc_r <= mreq_nextpc_r;
                mresp_rd_r <= mreq_rd_r;
                mresp_reg_wen_r <= mreq_reg_wen_r;
                mresp_datatoreg_r <= mreq_datatoreg_r;
                mresp_mem_op_r <= mreq_mem_op_r;
                mresp_aluout_r <= mreq_aluout_r;
                mresp_csr_read_data_r <= mreq_csr_read_data_r;
                mresp_csr_wen_r <= mreq_csr_wen_r;
                mresp_csr_waddr1_r <= mreq_csr_waddr1_r;
                mresp_csr_waddr2_r <= mreq_csr_waddr2_r;
                mresp_csr_wdata1_r <= mreq_csr_wdata1_r;
                mresp_csr_wdata2_r <= mreq_csr_wdata2_r;
                mresp_illegal_r <= mreq_illegal_r;
                mresp_is_ebreak_r <= mreq_is_ebreak_r;
                mresp_branch_r <= mreq_branch_r;
                mresp_src1_value_r <= mreq_src1_value_r;
            end

            if (ms_allowin) begin
                mreq_valid_r <= es_to_ms_valid;
                if (es_to_ms_valid) begin
                    mreq_pc_r <= es_pc;
                    mreq_instr_r <= es_instr;
                    mreq_nextpc_r <= es_nextpc;
                    mreq_rd_r <= es_rd;
                    mreq_reg_wen_r <= es_mem_addr_misaligned ? 1'b0 : es_reg_wen;
                    mreq_datatoreg_r <= es_mem_addr_misaligned ? 2'b00 : es_datatoreg;
                    mreq_mem_wr_r <= es_mem_addr_misaligned ? 2'b00 : es_mem_wr;
                    mreq_mem_op_r <= es_mem_op;
                    mreq_aluout_r <= es_aluout;
                    mreq_store_data_r <= es_mem_wdata;
                    mreq_csr_read_data_r <= es_csr_read_data;
                    mreq_csr_wen_r <= es_mem_addr_misaligned ? 2'b11 : es_csr_wen;
                    mreq_csr_waddr1_r <= es_mem_addr_misaligned ? 12'h342 : es_csr_waddr1;
                    mreq_csr_waddr2_r <= es_mem_addr_misaligned ? 12'h341 : es_csr_waddr2;
                    mreq_csr_wdata1_r <= es_mem_addr_misaligned ? es_mem_misaligned_cause : es_csr_wdata1;
                    mreq_csr_wdata2_r <= es_mem_addr_misaligned ? es_pc : es_csr_wdata2;
                    mreq_illegal_r <= es_mem_addr_misaligned ? 1'b0 : es_illegal;
                    mreq_is_ebreak_r <= es_mem_addr_misaligned ? 1'b0 : es_is_ebreak;
                    mreq_branch_r <= es_mem_addr_misaligned ? `BBUS_BR_E : es_branch;
                    mreq_src1_value_r <= es_src1_value;
                    mreq_from_fwd_dep_r <= es_mem_fwd_dep;
                end
            end
        end
    end
endmodule
