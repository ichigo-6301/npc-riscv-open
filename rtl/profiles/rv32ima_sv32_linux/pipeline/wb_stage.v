`timescale 1ns / 1ps

module wb_stage (
    input clk,
    input rst_n,
    input flush,
    input hold,

    input ms_to_ws_valid,
    output ws_allowin,

    input [31:0] ms_pc,
    input [31:0] ms_instr,
    input [31:0] ms_nextpc,
    input [4:0] ms_rd,
    input ms_reg_wen,
    input [1:0] ms_datatoreg,
    input [2:0] ms_mem_op,
    input [31:0] ms_aluout,
    input [31:0] ms_mem_rdata,
    input [31:0] ms_csr_read_data,
    input [1:0] ms_csr_wen,
    input [11:0] ms_csr_waddr1,
    input [11:0] ms_csr_waddr2,
    input [31:0] ms_csr_wdata1,
    input [31:0] ms_csr_wdata2,
    input ms_illegal,
    input ms_exc_valid,
    input [31:0] ms_exc_cause,
    input [31:0] ms_exc_tval,
    input ms_is_ebreak,
    input [2:0] ms_branch,
    input [31:0] ms_src1_value,
    input ms_fast_mul_stat,

    output ws_valid,
    output [31:0] ws_pc,
    output [31:0] ws_instr,
    output [31:0] ws_nextpc,
    output [4:0] ws_rd,
    output ws_reg_wen,
    output [31:0] ws_rf_wdata,
    output [1:0] ws_csr_wen,
    output [11:0] ws_csr_waddr1,
    output [11:0] ws_csr_waddr2,
    output [31:0] ws_csr_wdata1,
    output [31:0] ws_csr_wdata2,
    output ws_illegal,
    output ws_exc_valid,
    output [31:0] ws_exc_cause,
    output [31:0] ws_exc_tval,
    output ws_is_ebreak,
    output [2:0] ws_branch,
    output [31:0] ws_src1_value,
    output [1:0] ws_stat_datatoreg,
    output [2:0] ws_stat_mem_op,
    output ws_fast_mul_stat
);
    reg ws_valid_r;
    reg [31:0] ws_pc_r;
    reg [31:0] ws_instr_r;
    reg [31:0] ws_nextpc_r;
    reg [4:0] ws_rd_r;
    reg ws_reg_wen_r;
    reg [1:0] ws_datatoreg_r;
    reg [2:0] ws_mem_op_r;
    reg [31:0] ws_aluout_r;
    reg [31:0] ws_mem_rdata_r;
    reg [31:0] ws_csr_read_data_r;
    reg [1:0] ws_csr_wen_r;
    reg [11:0] ws_csr_waddr1_r;
    reg [11:0] ws_csr_waddr2_r;
    reg [31:0] ws_csr_wdata1_r;
    reg [31:0] ws_csr_wdata2_r;
    reg ws_illegal_r;
    reg ws_exc_valid_r;
    reg [31:0] ws_exc_cause_r;
    reg [31:0] ws_exc_tval_r;
    reg ws_is_ebreak_r;
    reg [2:0] ws_branch_r;
    reg [31:0] ws_src1_value_r;
    reg ws_fast_mul_stat_r;

    wire [31:0] load_data_ext =
        (ws_mem_op_r == 3'b000) ? {{24{ws_mem_rdata_r[7]}}, ws_mem_rdata_r[7:0]} :
        (ws_mem_op_r == 3'b001) ? {{16{ws_mem_rdata_r[15]}}, ws_mem_rdata_r[15:0]} :
        (ws_mem_op_r == 3'b100) ? {24'b0, ws_mem_rdata_r[7:0]} :
        (ws_mem_op_r == 3'b101) ? {16'b0, ws_mem_rdata_r[15:0]} :
        ws_mem_rdata_r;

    assign ws_allowin = !hold;

    assign ws_valid = ws_valid_r;
    assign ws_pc = ws_pc_r;
    assign ws_instr = ws_instr_r;
    assign ws_nextpc = ws_nextpc_r;
    assign ws_rd = ws_rd_r;
    assign ws_reg_wen = ws_reg_wen_r;
    assign ws_rf_wdata =
        (ws_datatoreg_r == 2'b00) ? ws_aluout_r :
        (ws_datatoreg_r == 2'b01) ? load_data_ext :
        ws_csr_read_data_r;
    assign ws_csr_wen = ws_csr_wen_r;
    assign ws_csr_waddr1 = ws_csr_waddr1_r;
    assign ws_csr_waddr2 = ws_csr_waddr2_r;
    assign ws_csr_wdata1 = ws_csr_wdata1_r;
    assign ws_csr_wdata2 = ws_csr_wdata2_r;
    assign ws_illegal = ws_illegal_r;
    assign ws_exc_valid = ws_exc_valid_r;
    assign ws_exc_cause = ws_exc_cause_r;
    assign ws_exc_tval = ws_exc_tval_r;
    assign ws_is_ebreak = ws_is_ebreak_r;
    assign ws_branch = ws_branch_r;
    assign ws_src1_value = ws_src1_value_r;
    assign ws_stat_datatoreg = ws_datatoreg_r;
    assign ws_stat_mem_op = ws_mem_op_r;
    assign ws_fast_mul_stat = ws_fast_mul_stat_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            ws_valid_r <= 1'b0;
            ws_pc_r <= 32'b0;
            ws_instr_r <= 32'b0;
            ws_nextpc_r <= 32'b0;
            ws_rd_r <= 5'b0;
            ws_reg_wen_r <= 1'b0;
            ws_datatoreg_r <= 2'b00;
            ws_mem_op_r <= 3'b000;
            ws_aluout_r <= 32'b0;
            ws_mem_rdata_r <= 32'b0;
            ws_csr_read_data_r <= 32'b0;
            ws_csr_wen_r <= 2'b00;
            ws_csr_waddr1_r <= 12'b0;
            ws_csr_waddr2_r <= 12'b0;
            ws_csr_wdata1_r <= 32'b0;
            ws_csr_wdata2_r <= 32'b0;
            ws_illegal_r <= 1'b0;
            ws_exc_valid_r <= 1'b0;
            ws_exc_cause_r <= 32'b0;
            ws_exc_tval_r <= 32'b0;
            ws_is_ebreak_r <= 1'b0;
            ws_branch_r <= 3'b000;
            ws_src1_value_r <= 32'b0;
            ws_fast_mul_stat_r <= 1'b0;
        end else if (flush) begin
            ws_valid_r <= 1'b0;
        end else if (!hold) begin
            ws_valid_r <= ms_to_ws_valid;
            if (ms_to_ws_valid) begin
                ws_pc_r <= ms_pc;
                ws_instr_r <= ms_instr;
                ws_nextpc_r <= ms_nextpc;
                ws_rd_r <= ms_rd;
                ws_reg_wen_r <= ms_reg_wen;
                ws_datatoreg_r <= ms_datatoreg;
                ws_mem_op_r <= ms_mem_op;
                ws_aluout_r <= ms_aluout;
                ws_mem_rdata_r <= ms_mem_rdata;
                ws_csr_read_data_r <= ms_csr_read_data;
                ws_csr_wen_r <= ms_csr_wen;
                ws_csr_waddr1_r <= ms_csr_waddr1;
                ws_csr_waddr2_r <= ms_csr_waddr2;
                ws_csr_wdata1_r <= ms_csr_wdata1;
                ws_csr_wdata2_r <= ms_csr_wdata2;
                ws_illegal_r <= ms_illegal;
                ws_exc_valid_r <= ms_exc_valid;
                ws_exc_cause_r <= ms_exc_cause;
                ws_exc_tval_r <= ms_exc_tval;
                ws_is_ebreak_r <= ms_is_ebreak;
                ws_branch_r <= ms_branch;
                ws_src1_value_r <= ms_src1_value;
                ws_fast_mul_stat_r <= ms_fast_mul_stat;
            end
        end
    end
endmodule
