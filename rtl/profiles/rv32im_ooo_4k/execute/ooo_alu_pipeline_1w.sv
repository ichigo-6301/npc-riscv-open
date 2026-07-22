`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_alu_pipeline_1w (
    input  logic clk,
    input  logic reset,
    input  logic flush_i,
    input  logic selective_kill_valid_i,
    input  logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_i,

    input  logic issue_valid_i,
    input  bbus_ooo_alu_iq_uop_t issue_uop_i,
    input  logic [31:0] src1_data_i,
    input  logic [31:0] src2_data_i,
    output logic issue_ready_o,
    output logic issue_accept_o,

    output bbus_ooo_writeback_t completion_wb_o,
    output logic completion_valid_o,
    input  logic completion_ready_i,

    output logic occupied_o,
    output logic same_cycle_replace_o,
    output logic flush_drop_o,
    output logic selective_kill_drop_o,
    output logic illegal_issue_o
);
    logic completion_valid_q;
    bbus_ooo_writeback_t completion_wb_q;
    logic [31:0] result_c;
    bbus_ooo_writeback_t next_completion_c;
    logic issue_legal_c;
    logic completion_fire_c;
    logic capacity_available_c;
    logic completion_killed_c;

    function automatic logic ordinary_alu(input bbus_ooo_alu_iq_uop_t uop);
        begin
            ordinary_alu =
                ((uop.fu_type == BBUS_OOO_FU_ALU) ||
                 (uop.fu_type == BBUS_OOO_FU_NONE)) &&
                !uop.is_load && !uop.is_store && !uop.is_csr && !uop.is_system;
        end
    endfunction

    always_comb begin
        unique case (issue_uop_i.alu_op)
            BBUS_OOO_ALU_SUB:    result_c = src1_data_i - src2_data_i;
            BBUS_OOO_ALU_AND:    result_c = src1_data_i & src2_data_i;
            BBUS_OOO_ALU_OR:     result_c = src1_data_i | src2_data_i;
            BBUS_OOO_ALU_XOR:    result_c = src1_data_i ^ src2_data_i;
            BBUS_OOO_ALU_SLL:    result_c = src1_data_i << src2_data_i[4:0];
            BBUS_OOO_ALU_SRL:    result_c = src1_data_i >> src2_data_i[4:0];
            BBUS_OOO_ALU_SRA:    result_c = $signed(src1_data_i) >>> src2_data_i[4:0];
            BBUS_OOO_ALU_SLT:    result_c = {31'b0, $signed(src1_data_i) < $signed(src2_data_i)};
            BBUS_OOO_ALU_SLTU:   result_c = {31'b0, src1_data_i < src2_data_i};
            BBUS_OOO_ALU_COPY_A: result_c = src1_data_i;
            BBUS_OOO_ALU_COPY_B: result_c = src2_data_i;
            BBUS_OOO_ALU_ANDN:   result_c = src2_data_i & ~src1_data_i;
            default:             result_c = src1_data_i + src2_data_i;
        endcase

        next_completion_c = '0;
        next_completion_c.valid = 1'b1;
        next_completion_c.rob_tag = issue_uop_i.rob_tag;
        next_completion_c.phys_rd = issue_uop_i.phys_rd_new;
        next_completion_c.rf_wen = issue_uop_i.rf_wen;
        next_completion_c.result = result_c;
        next_completion_c.done = 1'b1;
        next_completion_c.exception = '0;

    end

    assign issue_legal_c = ordinary_alu(issue_uop_i);
    assign completion_killed_c = selective_kill_valid_i &&
        completion_wb_q.rob_tag.valid &&
        selective_killed_rob_mask_i[completion_wb_q.rob_tag.idx];
    assign completion_fire_c =
        !flush_i && !selective_kill_valid_i && completion_valid_q &&
        completion_ready_i;
    assign capacity_available_c = !completion_valid_q || completion_fire_c;
    // Ready advertises capacity only. Legality qualifies acceptance so a
    // combinational router may use ready without creating a valid/ready loop.
    assign issue_ready_o = !flush_i && !selective_kill_valid_i &&
        capacity_available_c;
    assign issue_accept_o = issue_valid_i && issue_ready_o && issue_legal_c;
    assign illegal_issue_o = issue_valid_i && !issue_legal_c;
    assign same_cycle_replace_o = completion_fire_c && issue_accept_o;
    assign flush_drop_o = flush_i && completion_valid_q;
    assign selective_kill_drop_o = completion_valid_q && completion_killed_c;

    assign completion_valid_o = (flush_i || selective_kill_valid_i) ?
        1'b0 : completion_valid_q;
    assign completion_wb_o = completion_wb_q;
    assign occupied_o = completion_valid_q;

    always_ff @(posedge clk) begin
        if (reset || flush_i) begin
            completion_valid_q <= 1'b0;
            completion_wb_q <= '0;
        end else if (completion_killed_c) begin
            completion_valid_q <= 1'b0;
            completion_wb_q <= '0;
        end else if (issue_accept_o) begin
            completion_valid_q <= 1'b1;
            completion_wb_q <= next_completion_c;
        end else if (completion_fire_c) begin
            completion_valid_q <= 1'b0;
            completion_wb_q <= '0;
        end
    end
endmodule
