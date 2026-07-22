`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_mdu_pipeline_1w #(
    parameter int unsigned MUL_LATENCY = 4,
    parameter bit MUL_COMPLETION_FALLTHROUGH_ENABLE = 1'b0
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
    output logic issue_ready_o,
    output logic issue_accept_o,

    output bbus_ooo_writeback_t completion_wb_o,
    output logic completion_valid_o,
    input  logic completion_ready_i,

    output logic occupied_o,
    output logic flush_drop_o,
    output logic selective_kill_drop_o,
    output logic illegal_issue_o
);
    localparam int unsigned MUL_COUNT_W =
        (MUL_LATENCY <= 1) ? 1 : $clog2(MUL_LATENCY + 1);

    typedef enum logic [1:0] {
        MDU_IDLE,
        MDU_MUL_WAIT,
        MDU_DIV_RUN,
        MDU_DONE
    } mdu_state_e;

    mdu_state_e state_q;
    bbus_ooo_writeback_t completion_q;
    bbus_ooo_mdu_op_e op_q;
    logic [63:0] mul_result_q;
    logic [MUL_COUNT_W-1:0] mul_count_q;
    logic [31:0] div_num_q;
    logic [31:0] div_den_q;
    logic [31:0] div_quot_q;
    logic [32:0] div_rem_q;
    logic [5:0] div_count_q;
    logic div_quot_negative_q;
    logic div_rem_negative_q;

    logic issue_legal_c;
    logic issue_is_mul_c;
    logic issue_is_signed_div_c;
    logic issue_is_remainder_c;
    logic div_by_zero_c;
    logic div_overflow_c;
    logic [63:0] mul_result_c;
    logic signed [63:0] mul_src1_signed_c;
    logic signed [63:0] mul_src2_signed_c;
    logic [63:0] mul_src1_unsigned_c;
    logic [63:0] mul_src2_unsigned_c;
    logic signed [64:0] mul_src1_signed65_c;
    logic signed [64:0] mul_src2_unsigned65_c;
    logic [32:0] div_rem_shift_c;
    logic div_take_c;
    logic [32:0] div_rem_next_c;
    logic [31:0] div_num_next_c;
    logic [31:0] div_quot_next_c;
    logic [31:0] div_quot_result_c;
    logic [31:0] div_rem_result_c;
    logic current_killed_c;
    logic mul_fallthrough_valid_c;
    bbus_ooo_writeback_t mul_fallthrough_wb_c;

    function automatic logic [31:0] magnitude32(
        input logic [31:0] value,
        input logic negative
    );
        begin
            magnitude32 = negative ? (~value + 32'd1) : value;
        end
    endfunction

    assign issue_legal_c = issue_uop_i.valid &&
        (issue_uop_i.fu_type == BBUS_OOO_FU_MDU) &&
        !issue_uop_i.is_load && !issue_uop_i.is_store &&
        !issue_uop_i.is_csr && !issue_uop_i.is_system &&
        !issue_uop_i.exception.valid;
    assign issue_is_mul_c = issue_uop_i.mdu_op <= BBUS_OOO_MDU_MULHU;
    assign issue_is_signed_div_c =
        (issue_uop_i.mdu_op == BBUS_OOO_MDU_DIV) ||
        (issue_uop_i.mdu_op == BBUS_OOO_MDU_REM);
    assign issue_is_remainder_c =
        (issue_uop_i.mdu_op == BBUS_OOO_MDU_REM) ||
        (issue_uop_i.mdu_op == BBUS_OOO_MDU_REMU);
    assign div_by_zero_c = src2_data_i == 32'b0;
    assign div_overflow_c = issue_is_signed_div_c &&
        (src1_data_i == 32'h8000_0000) &&
        (src2_data_i == 32'hffff_ffff);

    assign mul_src1_signed_c = {{32{src1_data_i[31]}}, src1_data_i};
    assign mul_src2_signed_c = {{32{src2_data_i[31]}}, src2_data_i};
    assign mul_src1_unsigned_c = {32'b0, src1_data_i};
    assign mul_src2_unsigned_c = {32'b0, src2_data_i};
    assign mul_src1_signed65_c = {{33{src1_data_i[31]}}, src1_data_i};
    assign mul_src2_unsigned65_c = {33'b0, src2_data_i};

    always_comb begin
        unique case (issue_uop_i.mdu_op)
            BBUS_OOO_MDU_MULH:
                mul_result_c = $unsigned(
                    mul_src1_signed_c * mul_src2_signed_c
                );
            BBUS_OOO_MDU_MULHSU:
                mul_result_c = $unsigned(
                    mul_src1_signed65_c * mul_src2_unsigned65_c
                );
            default:
                mul_result_c = mul_src1_unsigned_c * mul_src2_unsigned_c;
        endcase
    end

    assign div_rem_shift_c = {div_rem_q[31:0], div_num_q[31]};
    assign div_take_c = div_rem_shift_c >= {1'b0, div_den_q};
    assign div_rem_next_c = div_take_c ?
        (div_rem_shift_c - {1'b0, div_den_q}) : div_rem_shift_c;
    assign div_num_next_c = {div_num_q[30:0], 1'b0};
    assign div_quot_next_c = {div_quot_q[30:0], div_take_c};
    assign div_quot_result_c = div_quot_negative_q ?
        (~div_quot_next_c + 32'd1) : div_quot_next_c;
    assign div_rem_result_c = div_rem_negative_q ?
        (~div_rem_next_c[31:0] + 32'd1) : div_rem_next_c[31:0];

    assign current_killed_c = selective_kill_valid_i &&
        (state_q != MDU_IDLE) && completion_q.rob_tag.valid &&
        selective_killed_rob_mask_i[completion_q.rob_tag.idx];
    assign issue_ready_o = !reset && !flush_i && !selective_kill_valid_i &&
        (state_q == MDU_IDLE);
    assign issue_accept_o = issue_valid_i && issue_ready_o && issue_legal_c;
    assign illegal_issue_o = issue_valid_i && !issue_legal_c;
    assign mul_fallthrough_valid_c = MUL_COMPLETION_FALLTHROUGH_ENABLE &&
        issue_accept_o && issue_is_mul_c;
    always_comb begin
        mul_fallthrough_wb_c = '0;
        mul_fallthrough_wb_c.valid = 1'b1;
        mul_fallthrough_wb_c.rob_tag = issue_uop_i.rob_tag;
        mul_fallthrough_wb_c.phys_rd = issue_uop_i.phys_rd_new;
        mul_fallthrough_wb_c.rf_wen = issue_uop_i.rf_wen;
        mul_fallthrough_wb_c.done = 1'b1;
        mul_fallthrough_wb_c.result =
            (issue_uop_i.mdu_op == BBUS_OOO_MDU_MUL) ?
            mul_result_c[31:0] : mul_result_c[63:32];
    end
    assign completion_valid_o = !reset && !flush_i &&
        !selective_kill_valid_i &&
        ((state_q == MDU_DONE) || mul_fallthrough_valid_c);
    assign completion_wb_o = mul_fallthrough_valid_c ?
        mul_fallthrough_wb_c : completion_q;
    assign occupied_o = state_q != MDU_IDLE;
    assign flush_drop_o = flush_i && (state_q != MDU_IDLE);
    assign selective_kill_drop_o = current_killed_c;

    always_ff @(posedge clk) begin
        if (reset || flush_i) begin
            state_q <= MDU_IDLE;
            completion_q <= '0;
            op_q <= BBUS_OOO_MDU_MUL;
            mul_result_q <= '0;
            mul_count_q <= '0;
            div_num_q <= '0;
            div_den_q <= '0;
            div_quot_q <= '0;
            div_rem_q <= '0;
            div_count_q <= '0;
            div_quot_negative_q <= 1'b0;
            div_rem_negative_q <= 1'b0;
        end else if (selective_kill_valid_i) begin
            if (current_killed_c) begin
                state_q <= MDU_IDLE;
                completion_q <= '0;
                op_q <= BBUS_OOO_MDU_MUL;
                mul_result_q <= '0;
                mul_count_q <= '0;
                div_num_q <= '0;
                div_den_q <= '0;
                div_quot_q <= '0;
                div_rem_q <= '0;
                div_count_q <= '0;
                div_quot_negative_q <= 1'b0;
                div_rem_negative_q <= 1'b0;
            end
        end else begin
            unique case (state_q)
                MDU_IDLE: begin
                    if (issue_accept_o) begin
                        completion_q <= '0;
                        completion_q.valid <= 1'b1;
                        completion_q.rob_tag <= issue_uop_i.rob_tag;
                        completion_q.phys_rd <= issue_uop_i.phys_rd_new;
                        completion_q.rf_wen <= issue_uop_i.rf_wen;
                        completion_q.done <= 1'b1;
                        op_q <= issue_uop_i.mdu_op;

                        if (issue_is_mul_c &&
                            MUL_COMPLETION_FALLTHROUGH_ENABLE) begin
                            completion_q <= mul_fallthrough_wb_c;
                            if (completion_ready_i) begin
                                state_q <= MDU_IDLE;
                            end else begin
                                state_q <= MDU_DONE;
                            end
                        end else if (issue_is_mul_c) begin
                            mul_result_q <= mul_result_c;
                            mul_count_q <= MUL_COUNT_W'(MUL_LATENCY);
                            state_q <= MDU_MUL_WAIT;
                        end else if (div_by_zero_c) begin
                            completion_q.result <= issue_is_remainder_c ?
                                src1_data_i : 32'hffff_ffff;
                            state_q <= MDU_DONE;
                        end else if (div_overflow_c) begin
                            completion_q.result <= issue_is_remainder_c ?
                                32'b0 : 32'h8000_0000;
                            state_q <= MDU_DONE;
                        end else begin
                            div_num_q <= magnitude32(
                                src1_data_i,
                                issue_is_signed_div_c && src1_data_i[31]
                            );
                            div_den_q <= magnitude32(
                                src2_data_i,
                                issue_is_signed_div_c && src2_data_i[31]
                            );
                            div_quot_q <= '0;
                            div_rem_q <= '0;
                            div_count_q <= '0;
                            div_quot_negative_q <= issue_is_signed_div_c &&
                                (src1_data_i[31] ^ src2_data_i[31]);
                            div_rem_negative_q <= issue_is_signed_div_c &&
                                src1_data_i[31];
                            state_q <= MDU_DIV_RUN;
                        end
                    end
                end

                MDU_MUL_WAIT: begin
                    if (mul_count_q <= MUL_COUNT_W'(1)) begin
                        completion_q.result <= (op_q == BBUS_OOO_MDU_MUL) ?
                            mul_result_q[31:0] : mul_result_q[63:32];
                        state_q <= MDU_DONE;
                    end else begin
                        mul_count_q <= mul_count_q - MUL_COUNT_W'(1);
                    end
                end

                MDU_DIV_RUN: begin
                    div_num_q <= div_num_next_c;
                    div_quot_q <= div_quot_next_c;
                    div_rem_q <= div_rem_next_c;
                    if (div_count_q == 6'd31) begin
                        completion_q.result <=
                            ((op_q == BBUS_OOO_MDU_REM) ||
                             (op_q == BBUS_OOO_MDU_REMU)) ?
                            div_rem_result_c : div_quot_result_c;
                        state_q <= MDU_DONE;
                    end else begin
                        div_count_q <= div_count_q + 6'd1;
                    end
                end

                MDU_DONE: begin
                    if (completion_ready_i) begin
                        state_q <= MDU_IDLE;
                        completion_q <= '0;
                    end
                end

                default: begin
                    state_q <= MDU_IDLE;
                    completion_q <= '0;
                end
            endcase
        end
    end
endmodule
