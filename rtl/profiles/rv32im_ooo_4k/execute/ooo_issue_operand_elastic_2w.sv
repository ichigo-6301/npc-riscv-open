`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_issue_operand_elastic_2w #(
    parameter bit FALLTHROUGH_ENABLE = 1'b0
) (
    input  logic clk,
    input  logic reset,
    input  logic flush_i,
    input  logic selective_kill_valid_i,
    input  logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_i,

    input  logic [1:0] in_valid_mask_i,
    input  bbus_ooo_alu_iq_uop_t in_uop0_i,
    input  bbus_ooo_alu_iq_uop_t in_uop1_i,
    input  logic [31:0] in_src10_i,
    input  logic [31:0] in_src20_i,
    input  logic [31:0] in_src11_i,
    input  logic [31:0] in_src21_i,
    output logic [1:0] in_ready_mask_o,
    output logic [1:0] in_accept_mask_o,

    output logic [1:0] out_valid_mask_o,
    output bbus_ooo_alu_iq_uop_t out_uop0_o,
    output bbus_ooo_alu_iq_uop_t out_uop1_o,
    output logic [31:0] out_src10_o,
    output logic [31:0] out_src20_o,
    output logic [31:0] out_src11_o,
    output logic [31:0] out_src21_o,
    input  logic [1:0] out_ready_mask_i,
    input  logic [1:0] fallthrough_ready_mask_i,
    output logic [1:0] out_fire_mask_o,

    output logic full_o,
    output logic pair_held_o,
    output logic input_pair_legal_o,
    output logic illegal_input_mask_o,
    output logic illegal_pair_o,
    output logic [1:0] flush_drop_mask_o,
    output logic [1:0] selective_kill_drop_mask_o,
    output logic same_cycle_replace_o,
    output logic [1:0] fallthrough_eligible_mask_o,
    output logic [1:0] direct_fire_mask_o
);
    logic [1:0] valid_mask_q;
    bbus_ooo_alu_iq_uop_t uop0_q;
    bbus_ooo_alu_iq_uop_t uop1_q;
    logic [31:0] src10_q;
    logic [31:0] src20_q;
    logic [31:0] src11_q;
    logic [31:0] src21_q;
    logic out_bundle_fire_c;
    logic registered_out_fire_c;
    logic direct_mode_c;
    logic in_bundle_accept_c;
    logic stage_can_accept_c;
    logic input_shape_legal_c;
    logic [1:0] selective_killed_lane_c;
    logic [1:0] visible_valid_mask_c;
    logic [1:0] output_valid_mask_c;

    function automatic logic tag_killed(input bbus_ooo_rob_tag_t tag);
        tag_killed = selective_kill_valid_i && tag.valid &&
            selective_killed_rob_mask_i[tag.idx];
    endfunction

    function automatic logic is_ordinary_alu(input bbus_ooo_alu_iq_uop_t uop);
        begin
            is_ordinary_alu =
                ((uop.fu_type == BBUS_OOO_FU_ALU) ||
                 (uop.fu_type == BBUS_OOO_FU_NONE)) &&
                !uop.is_load && !uop.is_store && !uop.is_csr && !uop.is_system;
        end
    endfunction

    function automatic logic is_ordinary_load(input bbus_ooo_alu_iq_uop_t uop);
        begin
            is_ordinary_load =
                (uop.fu_type == BBUS_OOO_FU_LSU) &&
                uop.is_load && !uop.is_store && !uop.is_csr && !uop.is_system;
        end
    endfunction

    function automatic logic legal_pair(
        input bbus_ooo_alu_iq_uop_t a,
        input bbus_ooo_alu_iq_uop_t b
    );
        begin
            legal_pair =
                (is_ordinary_alu(a) && is_ordinary_alu(b)) ||
                (is_ordinary_alu(a) && is_ordinary_load(b)) ||
                (is_ordinary_load(a) && is_ordinary_alu(b));
        end
    endfunction

    always_comb begin
        selective_killed_lane_c = {
            valid_mask_q[1] && tag_killed(uop1_q.rob_tag),
            valid_mask_q[0] && tag_killed(uop0_q.rob_tag)
        };
        visible_valid_mask_c = valid_mask_q & ~selective_killed_lane_c;
        input_shape_legal_c =
            (in_valid_mask_i == 2'b00) ||
            (in_valid_mask_i == 2'b01) ||
            (in_valid_mask_i == 2'b11);
        input_pair_legal_o =
            (in_valid_mask_i != 2'b11) || legal_pair(in_uop0_i, in_uop1_i);
        illegal_input_mask_o = !input_shape_legal_c;
        illegal_pair_o = (in_valid_mask_i == 2'b11) && !input_pair_legal_o;

        direct_mode_c = FALLTHROUGH_ENABLE && !flush_i &&
            !selective_kill_valid_i && (visible_valid_mask_c == 2'b00) &&
            input_shape_legal_c && input_pair_legal_o &&
            (in_valid_mask_i != 2'b00);
        output_valid_mask_c = direct_mode_c ?
            in_valid_mask_i : visible_valid_mask_c;
        out_bundle_fire_c = !flush_i && !selective_kill_valid_i && (
            (output_valid_mask_c == 2'b01) ? out_ready_mask_i[0] :
            (output_valid_mask_c == 2'b11) ? (&out_ready_mask_i) : 1'b0);
        registered_out_fire_c = out_bundle_fire_c && !direct_mode_c;
        direct_fire_mask_o = (out_bundle_fire_c && direct_mode_c) ?
            output_valid_mask_c : 2'b00;
        out_fire_mask_o = out_bundle_fire_c ? output_valid_mask_c : 2'b00;

        stage_can_accept_c = (visible_valid_mask_c == 2'b00) ||
            registered_out_fire_c;
        in_ready_mask_o = 2'b00;
        if (!flush_i && !selective_kill_valid_i && stage_can_accept_c &&
            input_shape_legal_c && input_pair_legal_o) begin
            unique case (in_valid_mask_i)
                2'b00: in_ready_mask_o = 2'b11;
                2'b01: in_ready_mask_o = 2'b01;
                2'b11: in_ready_mask_o = 2'b11;
                default: in_ready_mask_o = 2'b00;
            endcase
        end
        in_accept_mask_o = in_valid_mask_i & in_ready_mask_o;
        in_bundle_accept_c = |in_accept_mask_o;

        // Measurement-only counterfactual: with an empty registered owner,
        // report the input lanes that could be consumed directly by the
        // current downstream topology.  This signal never changes ready,
        // accept, storage, or output ownership.
        fallthrough_eligible_mask_o = 2'b00;
        if (!flush_i && !selective_kill_valid_i &&
            (visible_valid_mask_c == 2'b00) && input_shape_legal_c &&
            input_pair_legal_o) begin
            if ((in_valid_mask_i == 2'b01) &&
                fallthrough_ready_mask_i[0])
                fallthrough_eligible_mask_o = 2'b01;
            else if ((in_valid_mask_i == 2'b11) &&
                     (&fallthrough_ready_mask_i))
                fallthrough_eligible_mask_o = 2'b11;
        end

        flush_drop_mask_o = flush_i ? valid_mask_q : 2'b00;
        selective_kill_drop_mask_o = selective_kill_valid_i ?
            selective_killed_lane_c : 2'b00;
        same_cycle_replace_o = in_bundle_accept_c && registered_out_fire_c;
    end

    assign out_valid_mask_o = (flush_i || selective_kill_valid_i) ?
        2'b00 : output_valid_mask_c;
    assign out_uop0_o = direct_mode_c ? in_uop0_i : uop0_q;
    assign out_uop1_o = direct_mode_c ? in_uop1_i : uop1_q;
    assign out_src10_o = direct_mode_c ? in_src10_i : src10_q;
    assign out_src20_o = direct_mode_c ? in_src20_i : src20_q;
    assign out_src11_o = direct_mode_c ? in_src11_i : src11_q;
    assign out_src21_o = direct_mode_c ? in_src21_i : src21_q;
    assign full_o = valid_mask_q != 2'b00;
    assign pair_held_o = valid_mask_q == 2'b11;

    always_ff @(posedge clk) begin
        if (reset || flush_i) begin
            valid_mask_q <= 2'b00;
            uop0_q <= '0;
            uop1_q <= '0;
            src10_q <= 32'b0;
            src20_q <= 32'b0;
            src11_q <= 32'b0;
            src21_q <= 32'b0;
        end else if (selective_kill_valid_i) begin
            if (selective_killed_lane_c == 2'b01) begin
                uop0_q <= uop1_q;
                src10_q <= src11_q;
                src20_q <= src21_q;
                uop1_q <= '0;
                src11_q <= 32'b0;
                src21_q <= 32'b0;
                valid_mask_q <= {1'b0, valid_mask_q[1]};
            end else begin
            if (selective_killed_lane_c[0]) begin
                uop0_q <= '0;
                src10_q <= 32'b0;
                src20_q <= 32'b0;
            end
            if (selective_killed_lane_c[1]) begin
                uop1_q <= '0;
                src11_q <= 32'b0;
                src21_q <= 32'b0;
            end
            valid_mask_q <= visible_valid_mask_c;
            end
        end else if (in_bundle_accept_c && !(|direct_fire_mask_o)) begin
            valid_mask_q <= in_accept_mask_o;
            uop0_q <= in_uop0_i;
            uop1_q <= in_uop1_i;
            src10_q <= in_src10_i;
            src20_q <= in_src20_i;
            src11_q <= in_src11_i;
            src21_q <= in_src21_i;
        end else if (registered_out_fire_c || (|direct_fire_mask_o)) begin
            valid_mask_q <= 2'b00;
        end
    end
endmodule
