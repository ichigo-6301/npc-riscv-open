`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// Two-entry raw Decode2 holding stage. Optional empty-buffer fall-through
// removes the fixed capture cycle while retaining this stage as the skid
// owner whenever Rename2/Dispatch2 cannot consume the complete input bundle.
module ooo_decode_bundle_elastic_2w #(
    parameter bit DECODE_DISPATCH_FALLTHROUGH_ENABLE = 1'b0
) (
    input logic clk,
    input logic reset,
    input logic flush_i,

    input logic [1:0] in_valid_mask_i,
    input bbus_ooo_decode_uop_t in_uop0_i,
    input bbus_ooo_decode_uop_t in_uop1_i,
    output logic [1:0] in_ready_mask_o,
    output logic [1:0] in_accept_mask_o,

    output logic [1:0] out_valid_mask_o,
    output bbus_ooo_decode_uop_t out_uop0_o,
    output bbus_ooo_decode_uop_t out_uop1_o,
    input logic [1:0] out_fire_mask_i,

    output logic [1:0] occupancy_o,
    output logic illegal_input_mask_o,
    output logic illegal_fire_mask_o,
    output logic conservation_error_o
);
    bbus_ooo_decode_uop_t q0_q;
    bbus_ooo_decode_uop_t q1_q;
    bbus_ooo_decode_uop_t q0_d;
    bbus_ooo_decode_uop_t q1_d;
    logic [1:0] count_q;
    logic [1:0] count_d;
    logic [1:0] pop_count_c;
    logic [1:0] queued_pop_count_c;
    logic [1:0] direct_consume_count_c;
    logic [1:0] accepted_count_c;
    logic [1:0] free_after_pop_c;
    logic valid_input_prefix_c;
    logic legal_fire_c;
    logic fallthrough_mode_c;
    logic fallthrough_accounting_error_c;

    function automatic logic [1:0] prefix_mask(input logic [1:0] mask);
        begin
            unique case (mask)
                2'b00: prefix_mask = 2'b00;
                2'b01: prefix_mask = 2'b01;
                2'b11: prefix_mask = 2'b11;
                default: prefix_mask = 2'b00;
            endcase
        end
    endfunction

    assign valid_input_prefix_c = (in_valid_mask_i != 2'b10);

    always_comb begin
        illegal_input_mask_o = !valid_input_prefix_c && !flush_i;
        legal_fire_c = (out_fire_mask_i == prefix_mask(out_fire_mask_i)) &&
            ((out_fire_mask_i & ~out_valid_mask_o) == 2'b00);
        illegal_fire_mask_o = !legal_fire_c && !flush_i;
        pop_count_c = legal_fire_c ?
            ({1'b0, out_fire_mask_i[0]} + {1'b0, out_fire_mask_i[1]}) : 2'b00;
        fallthrough_mode_c = DECODE_DISPATCH_FALLTHROUGH_ENABLE &&
            (count_q == 2'd0) && !flush_i;
        queued_pop_count_c = fallthrough_mode_c ? 2'd0 : pop_count_c;
        direct_consume_count_c = fallthrough_mode_c ? pop_count_c : 2'd0;

        // Empty-buffer ready depends only on available skid storage. It does
        // not depend on the direct consumer, avoiding a downstream-ready loop.
        free_after_pop_c = 2'd2 - (count_q - queued_pop_count_c);
        in_ready_mask_o = 2'b00;
        if (!flush_i && (free_after_pop_c >= 2'd1)) in_ready_mask_o[0] = 1'b1;
        if (!flush_i && (free_after_pop_c >= 2'd2)) in_ready_mask_o[1] = 1'b1;
        in_accept_mask_o = valid_input_prefix_c ?
            (in_valid_mask_i & in_ready_mask_o) : 2'b00;
        accepted_count_c = {1'b0, in_accept_mask_o[0]} +
            {1'b0, in_accept_mask_o[1]};

        q0_d = '0;
        q1_d = '0;
        count_d = 2'b00;
        if (fallthrough_mode_c) begin
            // The source bundle is accepted into this boundary exactly once.
            // Directly consumed prefix entries are omitted from skid storage.
            unique case (direct_consume_count_c)
                2'd0: begin
                    if (in_accept_mask_o[0]) begin
                        q0_d = in_uop0_i;
                        q0_d.valid = 1'b1;
                        count_d = 2'd1;
                    end
                    if (in_accept_mask_o[1]) begin
                        q1_d = in_uop1_i;
                        q1_d.valid = 1'b1;
                        count_d = 2'd2;
                    end
                end
                2'd1: begin
                    if (in_accept_mask_o[1]) begin
                        q0_d = in_uop1_i;
                        q0_d.valid = 1'b1;
                        count_d = 2'd1;
                    end
                end
                default: begin
                end
            endcase
        end else begin
            unique case (queued_pop_count_c)
                2'd0: begin
                    if (count_q >= 2'd1) begin
                        q0_d = q0_q;
                        count_d = 2'd1;
                    end
                    if (count_q >= 2'd2) begin
                        q1_d = q1_q;
                        count_d = 2'd2;
                    end
                end
                2'd1: begin
                    if (count_q >= 2'd2) begin
                        q0_d = q1_q;
                        count_d = 2'd1;
                    end
                end
                default: begin
                end
            endcase

            if (in_accept_mask_o[0]) begin
                if (count_d == 2'd0) begin
                    q0_d = in_uop0_i;
                    q0_d.valid = 1'b1;
                end else begin
                    q1_d = in_uop0_i;
                    q1_d.valid = 1'b1;
                end
                count_d = count_d + 2'd1;
            end
            if (in_accept_mask_o[1]) begin
                q1_d = in_uop1_i;
                q1_d.valid = 1'b1;
                count_d = count_d + 2'd1;
            end
        end

        fallthrough_accounting_error_c = fallthrough_mode_c &&
            ({1'b0, accepted_count_c} !=
             ({1'b0, direct_consume_count_c} + {1'b0, count_d}));
    end

    assign out_valid_mask_o = flush_i ? 2'b00 :
        ((count_q != 2'd0) ?
         {(count_q >= 2'd2), (count_q >= 2'd1)} :
         ((DECODE_DISPATCH_FALLTHROUGH_ENABLE && valid_input_prefix_c) ?
          in_valid_mask_i : 2'b00));
    assign out_uop0_o = fallthrough_mode_c ? in_uop0_i : q0_q;
    assign out_uop1_o = fallthrough_mode_c ? in_uop1_i : q1_q;
    assign occupancy_o = count_q;
    assign conservation_error_o = illegal_input_mask_o || illegal_fire_mask_o ||
        fallthrough_accounting_error_c ||
        (count_q > 2'd2) || (count_d > 2'd2);

    always_ff @(posedge clk) begin
        if (reset || flush_i) begin
            q0_q <= '0;
            q1_q <= '0;
            count_q <= 2'b00;
        end else begin
            q0_q <= q0_d;
            q1_q <= q1_d;
            count_q <= count_d;
        end
    end
endmodule
