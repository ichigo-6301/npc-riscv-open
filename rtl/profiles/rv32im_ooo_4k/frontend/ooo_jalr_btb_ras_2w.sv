`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_jalr_btb_ras_2w #(
    parameter integer BTB_ENTRIES = 64,
    parameter integer RAS_DEPTH = 8,
    parameter bit SAME_CYCLE_UPDATE_FORWARDING_ENABLE = 1'b0,
    parameter bit RAS_SELF_FORWARD_EXCLUSION_ENABLE = 1'b0
) (
    input logic clk,
    input logic reset,
    input logic clear_ras_i,
    input logic [1:0] lookup_valid_i,
    input logic [31:0] lookup_pc0_i,
    input logic [31:0] lookup_pc1_i,
    input logic lookup_return0_i,
    input logic lookup_return1_i,
    output logic pred_taken0_o,
    output logic pred_taken1_o,
    output logic [31:0] pred_target0_o,
    output logic [31:0] pred_target1_o,
    output logic btb_hit0_o,
    output logic btb_hit1_o,
    output logic ras_hit0_o,
    output logic ras_hit1_o,
    output logic [1:0] self_forward_collision_o,

    input logic btb_update_valid_i,
    input logic [31:0] btb_update_pc_i,
    input logic [31:0] btb_update_target_i,
    input logic ras_update_valid_i,
    input bbus_ooo_ras_action_e ras_update_action_i,
    input logic [31:0] ras_update_link_i,
    input logic ras_restore_valid_i,
    output logic ras_restore_ready_o,
    input bbus_ooo_ras_snapshot_t ras_restore_snapshot_i,
    output logic ras_restore_payload_valid_o,
    input bbus_ooo_ras_action_e ras_restore_replay_action_i,
    input logic [31:0] ras_restore_replay_link_i,
    output logic ras_restore_fire_o,
    output logic ras_restore_collision_error_o,
    output logic ras_restore_invalid_error_o,
    output bbus_ooo_ras_snapshot_t ras_snapshot_o
);
    localparam integer INDEX_BITS = $clog2(BTB_ENTRIES);
    localparam integer TAG_BITS = 32 - INDEX_BITS - 2;
    localparam integer RAS_PTR_BITS = $clog2(RAS_DEPTH);

    logic btb_valid_q [BTB_ENTRIES-1:0];
    logic [TAG_BITS-1:0] btb_tag_q [BTB_ENTRIES-1:0];
    logic [31:0] btb_target_q [BTB_ENTRIES-1:0];
    logic [31:0] ras_q [RAS_DEPTH-1:0];
    logic [RAS_PTR_BITS:0] ras_count_q;

    logic [INDEX_BITS-1:0] idx0_c, idx1_c, update_idx_c;
    logic [TAG_BITS-1:0] tag0_c, tag1_c, update_tag_c;
    logic [RAS_PTR_BITS-1:0] ras_lookup_top_idx0_c;
    logic [RAS_PTR_BITS-1:0] ras_lookup_top_idx1_c;
    bbus_ooo_ras_snapshot_t ras_forward_snapshot_c;
    bbus_ooo_ras_snapshot_t ras_lookup_snapshot0_c;
    bbus_ooo_ras_snapshot_t ras_lookup_snapshot1_c;
    logic [1:0] self_forward_collision_c;
    logic ras_restore_collision_error_q;
    logic ras_restore_invalid_error_q;

    function automatic bbus_ooo_ras_snapshot_t apply_ras_action(
        input bbus_ooo_ras_snapshot_t base,
        input bbus_ooo_ras_action_e action,
        input logic [31:0] link
    );
        bbus_ooo_ras_snapshot_t next;
        begin
            next = base;
            unique case (action)
                BBUS_OOO_RAS_PUSH: begin
                    if (next.count < RAS_DEPTH) begin
                        next.entries[(next.count * 32) +: 32] = link;
                        next.count = next.count + 1'b1;
                    end else begin
                        for (int r = 0; r < RAS_DEPTH-1; r = r + 1) begin
                            next.entries[(r * 32) +: 32] =
                                next.entries[((r + 1) * 32) +: 32];
                        end
                        next.entries[((RAS_DEPTH - 1) * 32) +: 32] = link;
                    end
                end
                BBUS_OOO_RAS_POP: begin
                    if (next.count != 0) next.count = next.count - 1'b1;
                end
                BBUS_OOO_RAS_POP_PUSH: begin
                    if (next.count != 0) begin
                        next.entries[((next.count - 1'b1) * 32) +: 32] = link;
                    end else begin
                        next.entries[31:0] = link;
                        next.count = 1;
                    end
                end
                default: begin end
            endcase
            apply_ras_action = next;
        end
    endfunction

    assign idx0_c = lookup_pc0_i[INDEX_BITS+1:2];
    assign idx1_c = lookup_pc1_i[INDEX_BITS+1:2];
    assign update_idx_c = btb_update_pc_i[INDEX_BITS+1:2];
    assign tag0_c = lookup_pc0_i[31:INDEX_BITS+2];
    assign tag1_c = lookup_pc1_i[31:INDEX_BITS+2];
    assign update_tag_c = btb_update_pc_i[31:INDEX_BITS+2];
    assign ras_lookup_top_idx0_c = (ras_lookup_snapshot0_c.count == 0) ? '0 :
        RAS_PTR_BITS'(ras_lookup_snapshot0_c.count - 1'b1);
    assign ras_lookup_top_idx1_c = (ras_lookup_snapshot1_c.count == 0) ? '0 :
        RAS_PTR_BITS'(ras_lookup_snapshot1_c.count - 1'b1);
    assign ras_restore_ready_o = !reset && !clear_ras_i;
    assign ras_restore_payload_valid_o =
        (ras_restore_snapshot_i.count <= RAS_DEPTH);
    assign ras_restore_fire_o = ras_restore_valid_i && ras_restore_ready_o &&
        ras_restore_payload_valid_o;
    assign ras_restore_collision_error_o = ras_restore_collision_error_q;
    assign ras_restore_invalid_error_o = ras_restore_invalid_error_q;

    always_comb begin
        ras_snapshot_o = '0;
        ras_snapshot_o.count = ras_count_q;
        for (int r = 0; r < RAS_DEPTH; r = r + 1) begin
            ras_snapshot_o.entries[(r * 32) +: 32] = ras_q[r];
        end
    end

    assign self_forward_collision_c[0] =
        SAME_CYCLE_UPDATE_FORWARDING_ENABLE && ras_update_valid_i &&
        !clear_ras_i && !ras_restore_valid_i && lookup_valid_i[0] &&
        lookup_return0_i && (ras_snapshot_o.count != 0) &&
        (ras_update_link_i == lookup_pc0_i + 32'd4);
    assign self_forward_collision_c[1] =
        SAME_CYCLE_UPDATE_FORWARDING_ENABLE && ras_update_valid_i &&
        !clear_ras_i && !ras_restore_valid_i && lookup_valid_i[1] &&
        lookup_return1_i && (ras_snapshot_o.count != 0) &&
        (ras_update_link_i == lookup_pc1_i + 32'd4);
    assign self_forward_collision_o = self_forward_collision_c;

    always_comb begin
        ras_forward_snapshot_c = ras_snapshot_o;
        if (SAME_CYCLE_UPDATE_FORWARDING_ENABLE && ras_update_valid_i &&
            !clear_ras_i && !ras_restore_valid_i) begin
            ras_forward_snapshot_c = apply_ras_action(
                ras_snapshot_o, ras_update_action_i, ras_update_link_i
            );
        end
        ras_lookup_snapshot0_c = ras_forward_snapshot_c;
        ras_lookup_snapshot1_c = ras_forward_snapshot_c;
        if (RAS_SELF_FORWARD_EXCLUSION_ENABLE &&
            self_forward_collision_c[0]) begin
            ras_lookup_snapshot0_c = ras_snapshot_o;
        end
        if (RAS_SELF_FORWARD_EXCLUSION_ENABLE &&
            self_forward_collision_c[1]) begin
            ras_lookup_snapshot1_c = ras_snapshot_o;
        end
    end

    always_comb begin
        btb_hit0_o = lookup_valid_i[0] && btb_valid_q[idx0_c] &&
            (btb_tag_q[idx0_c] == tag0_c);
        btb_hit1_o = lookup_valid_i[1] && btb_valid_q[idx1_c] &&
            (btb_tag_q[idx1_c] == tag1_c);
        ras_hit0_o = lookup_valid_i[0] && lookup_return0_i &&
            (ras_lookup_snapshot0_c.count != 0);
        ras_hit1_o = lookup_valid_i[1] && lookup_return1_i &&
            (ras_lookup_snapshot1_c.count != 0);
        pred_taken0_o = ras_hit0_o || btb_hit0_o;
        pred_taken1_o = ras_hit1_o || btb_hit1_o;
        pred_target0_o = ras_hit0_o ?
            ras_lookup_snapshot0_c.entries[
                (ras_lookup_top_idx0_c * 32) +: 32] :
            btb_hit0_o ? btb_target_q[idx0_c] : lookup_pc0_i + 32'd4;
        pred_target1_o = ras_hit1_o ?
            ras_lookup_snapshot1_c.entries[
                (ras_lookup_top_idx1_c * 32) +: 32] :
            btb_hit1_o ? btb_target_q[idx1_c] : lookup_pc1_i + 32'd4;
    end

    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
                btb_valid_q[i] <= 1'b0;
                btb_tag_q[i] <= '0;
                btb_target_q[i] <= '0;
            end
            for (i = 0; i < RAS_DEPTH; i = i + 1) begin
                ras_q[i] <= '0;
            end
            ras_count_q <= '0;
            ras_restore_collision_error_q <= 1'b0;
            ras_restore_invalid_error_q <= 1'b0;
        end else begin
            if (btb_update_valid_i) begin
                btb_valid_q[update_idx_c] <= 1'b1;
                btb_tag_q[update_idx_c] <= update_tag_c;
                btb_target_q[update_idx_c] <= btb_update_target_i;
            end
            if (clear_ras_i) begin
                ras_count_q <= '0;
                if (ras_restore_valid_i || ras_update_valid_i)
                    ras_restore_collision_error_q <= 1'b1;
            end else if (ras_restore_valid_i &&
                         (ras_restore_snapshot_i.count > RAS_DEPTH)) begin
                // Invalid payloads never participate in an atomic restore.
                // Report the request while leaving the live RAS unchanged.
                ras_restore_invalid_error_q <= 1'b1;
            end else if (ras_restore_fire_o) begin : apply_restore
                bbus_ooo_ras_snapshot_t restored;
                restored = apply_ras_action(ras_restore_snapshot_i,
                    ras_restore_replay_action_i,
                    ras_restore_replay_link_i);
                for (i = 0; i < RAS_DEPTH; i = i + 1)
                    ras_q[i] <= restored.entries[(i * 32) +: 32];
                ras_count_q <= restored.count;
                if (ras_update_valid_i)
                    ras_restore_collision_error_q <= 1'b1;
            end else if (ras_update_valid_i) begin : apply_update
                bbus_ooo_ras_snapshot_t current, updated;
                current = ras_snapshot_o;
                updated = apply_ras_action(current, ras_update_action_i,
                    ras_update_link_i);
                for (i = 0; i < RAS_DEPTH; i = i + 1)
                    ras_q[i] <= updated.entries[(i * 32) +: 32];
                ras_count_q <= updated.count;
            end
        end
    end
endmodule
