`timescale 1ns / 1ps

module Mdu(
    input clk,
    input rst_n,
    input req_valid,
    output req_ready,
    input [2:0] req_op,
    input [31:0] req_src1,
    input [31:0] req_src2,
    output reg resp_valid,
    input resp_ready,
    output reg [31:0] resp_data,
    output busy
);
    localparam [2:0] MDU_OP_MUL    = 3'd0;
    localparam [2:0] MDU_OP_MULH   = 3'd1;
    localparam [2:0] MDU_OP_MULHSU = 3'd2;
    localparam [2:0] MDU_OP_MULHU  = 3'd3;
    localparam [2:0] MDU_OP_DIV    = 3'd4;
    localparam [2:0] MDU_OP_DIVU   = 3'd5;
    localparam [2:0] MDU_OP_REM    = 3'd6;
    localparam [2:0] MDU_OP_REMU   = 3'd7;

    localparam integer MUL_PIPE_STAGES = 4;

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_MUL  = 2'd1;
    localparam [1:0] ST_DIV  = 2'd2;
    localparam [1:0] ST_RESP = 2'd3;

    reg [1:0] state;

    assign req_ready = (state == ST_IDLE);
    assign busy = (state != ST_IDLE);

    function [31:0] abs32;
        input [31:0] value;
        input sign;
        begin
            abs32 = sign ? (~value + 32'd1) : value;
        end
    endfunction

    wire is_mul_op = (req_op == MDU_OP_MUL) || (req_op == MDU_OP_MULH) ||
                     (req_op == MDU_OP_MULHSU) || (req_op == MDU_OP_MULHU);

    // Multiply pipeline registers
    reg [33:0] mul_a_ext_r;
    reg [33:0] mul_b_ext_r;
    reg [2:0] mul_op_r;
    reg [31:0] mul_cnt;

    reg [33:0] mul_p_ll_r;
    reg signed [33:0] mul_p_lh_r;
    reg signed [33:0] mul_p_hl_r;
    reg signed [33:0] mul_p_hh_r;

    reg [33:0] mul_p_ll_r2;
    reg signed [33:0] mul_p_hh_r2;
    reg signed [34:0] mul_cross_r;

    wire [16:0] mul_a_lo = mul_a_ext_r[16:0];
    wire signed [16:0] mul_a_hi = mul_a_ext_r[33:17];
    wire [16:0] mul_b_lo = mul_b_ext_r[16:0];
    wire signed [16:0] mul_b_hi = mul_b_ext_r[33:17];

    // DSP attribute: Vivado auto-infers DSP48 by default;
    // define NPC_NO_DSP to force LUT implementation
`ifdef NPC_NO_DSP
    (* use_dsp = "no" *)
`endif
    wire [33:0] mul_p_ll = mul_a_lo * mul_b_lo;
`ifdef NPC_NO_DSP
    (* use_dsp = "no" *)
`endif
    wire signed [33:0] mul_p_lh = $signed({1'b0, mul_a_lo}) * $signed(mul_b_hi);
`ifdef NPC_NO_DSP
    (* use_dsp = "no" *)
`endif
    wire signed [33:0] mul_p_hl = $signed(mul_a_hi) * $signed({1'b0, mul_b_lo});
`ifdef NPC_NO_DSP
    (* use_dsp = "no" *)
`endif
    wire signed [33:0] mul_p_hh = $signed(mul_a_hi) * $signed(mul_b_hi);

    wire signed [34:0] mul_cross_next = $signed(mul_p_lh_r) + $signed(mul_p_hl_r);

    // Build 66-bit product: combine partial products with proper sign extension
    wire signed [65:0] mul_term_ll = $signed({32'b0, mul_p_ll_r2});
    wire signed [65:0] mul_term_cross = $signed({{31{mul_cross_r[34]}}, mul_cross_r}) <<< 17;
    wire signed [65:0] mul_term_hh = $signed({{32{mul_p_hh_r2[33]}}, mul_p_hh_r2}) <<< 34;
    wire signed [65:0] mul_prod_next = mul_term_ll + mul_term_cross + mul_term_hh;

    // Divider registers
    reg [31:0] div_num_r;
    reg [31:0] div_den_r;
    reg [31:0] div_quo_r;
    reg [32:0] div_rem_r;
    reg [5:0] div_cnt;
    reg div_signed_r;
    reg div_rem_op_r;
    reg div_sign_quot_r;
    reg div_sign_rem_r;

    wire div_signed = (req_op == MDU_OP_DIV) || (req_op == MDU_OP_REM);
    wire div_rem_op = (req_op == MDU_OP_REM) || (req_op == MDU_OP_REMU);
    wire div_by_zero = (req_src2 == 32'b0);
    wire div_overflow = div_signed && (req_src1 == 32'h80000000) && (req_src2 == 32'hffffffff);

    // Divider step temporaries (computed combinationally inside ST_DIV)
    reg [32:0] div_rem_next;
    reg [31:0] div_num_next;
    reg [31:0] div_quo_next;
    reg div_take;
    reg [31:0] div_quot_adj;
    reg [31:0] div_rem_adj;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            resp_valid <= 1'b0;
            resp_data <= 32'b0;
            mul_cnt <= 32'b0;
            mul_op_r <= 3'b0;
            mul_a_ext_r <= 34'b0;
            mul_b_ext_r <= 34'b0;
            mul_p_ll_r <= 34'b0;
            mul_p_lh_r <= 34'b0;
            mul_p_hl_r <= 34'b0;
            mul_p_hh_r <= 34'b0;
            mul_p_ll_r2 <= 34'b0;
            mul_p_hh_r2 <= 34'b0;
            mul_cross_r <= 35'b0;
            div_num_r <= 32'b0;
            div_den_r <= 32'b0;
            div_quo_r <= 32'b0;
            div_rem_r <= 33'b0;
            div_cnt <= 6'b0;
            div_signed_r <= 1'b0;
            div_rem_op_r <= 1'b0;
            div_sign_quot_r <= 1'b0;
            div_sign_rem_r <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    resp_valid <= 1'b0;
                    if (req_valid) begin
                        if (is_mul_op) begin
                            mul_op_r <= req_op;
                            mul_a_ext_r <= ((req_op == MDU_OP_MULH) || (req_op == MDU_OP_MULHSU)) ?
                                {{2{req_src1[31]}}, req_src1} : {2'b0, req_src1};
                            mul_b_ext_r <= (req_op == MDU_OP_MULH) ?
                                {{2{req_src2[31]}}, req_src2} : {2'b0, req_src2};
                            mul_cnt <= 32'b0;
                            state <= ST_MUL;
                        end else begin
                            if (div_by_zero) begin
                                resp_data <= div_rem_op ? req_src1 : 32'hffffffff;
                                resp_valid <= 1'b1;
                                state <= ST_RESP;
                            end else if (div_overflow) begin
                                resp_data <= div_rem_op ? 32'b0 : 32'h80000000;
                                resp_valid <= 1'b1;
                                state <= ST_RESP;
                            end else begin
                                div_signed_r <= div_signed;
                                div_rem_op_r <= div_rem_op;
                                div_sign_quot_r <= div_signed && (req_src1[31] ^ req_src2[31]);
                                div_sign_rem_r <= div_signed && req_src1[31];
                                div_num_r <= abs32(req_src1, div_signed && req_src1[31]);
                                div_den_r <= abs32(req_src2, div_signed && req_src2[31]);
                                div_quo_r <= 32'b0;
                                div_rem_r <= 33'b0;
                                div_cnt <= 6'b0;
                                state <= ST_DIV;
                            end
                        end
                    end
                end
                ST_MUL: begin
                    mul_p_ll_r <= mul_p_ll;
                    mul_p_lh_r <= mul_p_lh;
                    mul_p_hl_r <= mul_p_hl;
                    mul_p_hh_r <= mul_p_hh;

                    mul_p_ll_r2 <= mul_p_ll_r;
                    mul_p_hh_r2 <= mul_p_hh_r;
                    mul_cross_r <= mul_cross_next;

                    if (mul_cnt == (MUL_PIPE_STAGES - 1)) begin
                        resp_data <= (mul_op_r == MDU_OP_MUL) ? mul_prod_next[31:0] : mul_prod_next[63:32];
                        resp_valid <= 1'b1;
                        state <= ST_RESP;
                    end else begin
                        mul_cnt <= mul_cnt + 32'd1;
                    end
                end
                ST_DIV: begin
                    div_rem_next = {div_rem_r[31:0], div_num_r[31]};
                    div_take = (div_rem_next >= {1'b0, div_den_r});
                    if (div_take) begin
                        div_rem_next = div_rem_next - {1'b0, div_den_r};
                    end
                    div_num_next = {div_num_r[30:0], 1'b0};
                    div_quo_next = {div_quo_r[30:0], div_take};

                    div_rem_r <= div_rem_next;
                    div_num_r <= div_num_next;
                    div_quo_r <= div_quo_next;

                    if (div_cnt == 6'd31) begin
                        div_quot_adj = div_sign_quot_r ? (~div_quo_next + 32'd1) : div_quo_next;
                        div_rem_adj = div_sign_rem_r ? (~div_rem_next[31:0] + 32'd1) : div_rem_next[31:0];
                        resp_data <= div_rem_op_r ? div_rem_adj : div_quot_adj;
                        resp_valid <= 1'b1;
                        state <= ST_RESP;
                    end else begin
                        div_cnt <= div_cnt + 6'd1;
                    end
                end
                ST_RESP: begin
                    if (resp_ready) begin
                        resp_valid <= 1'b0;
                        state <= ST_IDLE;
                    end
                end
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
