`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_alu #(
    parameter int LATENCY = 1,
    parameter bit PIPELINED = 1'b0
) (
    input  logic clk,
    input  logic reset,

    input  logic issue_valid_i,
    input  bbus_ooo_alu_iq_uop_t issue_uop_i,
    input  logic [`BBUS_OOO_XLEN-1:0] src1_data_i,
    input  logic [`BBUS_OOO_XLEN-1:0] src2_data_i,
    output logic issue_ready_o,

    output bbus_ooo_writeback_t completion_wb_o,
    output logic completion_valid_o,
    input  logic completion_ready_i,

    output logic debug_busy_o,
    output logic debug_completion_valid_o
);
    typedef enum logic [1:0] {
        ALU_IDLE = 2'd0,
        ALU_BUSY = 2'd1,
        ALU_DONE = 2'd2
    } alu_state_e;

    localparam int ALU_CNT_W = $clog2(LATENCY + 1);

    alu_state_e state_q;
    bbus_ooo_writeback_t completion_wb_q;
    logic [ALU_CNT_W-1:0] cnt_q;
    logic [`BBUS_OOO_XLEN-1:0] result_c;
    bbus_ooo_writeback_t next_completion_c;

    assign issue_ready_o = (state_q == ALU_IDLE);
    assign completion_wb_o = completion_wb_q;
    assign completion_valid_o = (state_q == ALU_DONE);
    assign debug_busy_o = (state_q == ALU_BUSY);
    assign debug_completion_valid_o = completion_valid_o;

    always_comb begin
        unique case (issue_uop_i.alu_op)
            BBUS_OOO_ALU_SUB: result_c = src1_data_i - src2_data_i;
            BBUS_OOO_ALU_AND: result_c = src1_data_i & src2_data_i;
            BBUS_OOO_ALU_OR : result_c = src1_data_i | src2_data_i;
            BBUS_OOO_ALU_XOR: result_c = src1_data_i ^ src2_data_i;
            BBUS_OOO_ALU_SLL: result_c = src1_data_i << src2_data_i[4:0];
            BBUS_OOO_ALU_SRL: result_c = src1_data_i >> src2_data_i[4:0];
            BBUS_OOO_ALU_SRA: result_c = $signed(src1_data_i) >>> src2_data_i[4:0];
            BBUS_OOO_ALU_SLT: result_c = {31'b0, $signed(src1_data_i) < $signed(src2_data_i)};
            BBUS_OOO_ALU_SLTU: result_c = {31'b0, src1_data_i < src2_data_i};
            BBUS_OOO_ALU_COPY_A: result_c = src1_data_i;
            BBUS_OOO_ALU_COPY_B: result_c = src2_data_i;
            BBUS_OOO_ALU_ANDN: result_c = src2_data_i & ~src1_data_i;
            default         : result_c = src1_data_i + src2_data_i;
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

    always_ff @(posedge clk) begin
        if (reset) begin
            state_q <= ALU_IDLE;
            completion_wb_q <= '0;
            cnt_q <= '0;
        end else begin
            unique case (state_q)
                ALU_IDLE: begin
                    if (issue_valid_i) begin
                        completion_wb_q <= next_completion_c;
                        if (LATENCY <= 1) begin
                            cnt_q <= '0;
                            state_q <= ALU_DONE;
                        end else begin
                            cnt_q <= ALU_CNT_W'(LATENCY - 1);
                            state_q <= ALU_BUSY;
                        end
                    end
                end

                ALU_BUSY: begin
                    if (cnt_q <= ALU_CNT_W'(1)) begin
                        cnt_q <= '0;
                        state_q <= ALU_DONE;
                    end else begin
                        cnt_q <= cnt_q - ALU_CNT_W'(1);
                    end
                end

                ALU_DONE: begin
                    if (completion_ready_i) begin
                        completion_wb_q <= '0;
                        state_q <= ALU_IDLE;
                    end
                end

                default: begin
                    completion_wb_q <= '0;
                    cnt_q <= '0;
                    state_q <= ALU_IDLE;
                end
            endcase
        end
    end

    /* verilator lint_off UNUSED */
    // S2D reserves PIPELINED for a future FU; this implementation is non-pipelined.
    wire pipelined_unused = PIPELINED;
    /* verilator lint_on UNUSED */
endmodule
