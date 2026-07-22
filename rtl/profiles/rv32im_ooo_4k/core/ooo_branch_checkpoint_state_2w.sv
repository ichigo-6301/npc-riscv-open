`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_branch_checkpoint_state_2w (
    input logic clk,
    input logic reset,
    input logic clear_all_i,

    output logic alloc_ready_o,
    output bbus_ooo_checkpoint_id_t alloc_checkpoint_id_o,
    input logic alloc_fire_i,
    input bbus_ooo_rob_tag_t alloc_branch_rob_tag_i,
    input logic [31:0] alloc_branch_pc_i,
    input bbus_ooo_branch_op_e alloc_branch_op_i,
    input bbus_ooo_ras_action_e alloc_branch_ras_action_i,
    input logic [31:0] alloc_branch_ras_link_i,
    input bbus_ooo_rat_snapshot_t alloc_rat_snapshot_i,
    input bbus_ooo_ras_snapshot_t alloc_ras_snapshot_i,
    input bbus_ooo_rob_tag_t alloc_post_branch_tail_tag_i,
    input logic alloc_line_delivery_safe_i,
    input bbus_ooo_pred_source_e alloc_pred_source_i,

    input logic release_valid_i,
    input bbus_ooo_rob_tag_t release_branch_rob_tag_i,

    input logic selective_purge_valid_i,
    input bbus_ooo_rob_tag_t selective_purge_branch_rob_tag_i,
    input logic [`BBUS_OOO_ROB_ENTRIES-1:0]
        selective_purge_killed_rob_mask_i,
    output logic selective_purge_ready_o,
    output logic selective_purge_fire_o,
    output logic [1:0] selective_purged_mask_o,

    input logic lookup_valid_i,
    input bbus_ooo_rob_tag_t lookup_branch_rob_tag_i,
    output logic lookup_hit_o,
    output bbus_ooo_real_checkpoint_t lookup_checkpoint_o,

    input bbus_ooo_checkpoint_id_t debug_query_checkpoint_id_i,
    output logic debug_query_hit_o,
    output bbus_ooo_real_checkpoint_t debug_query_checkpoint_o,

    output logic [1:0] valid_mask_o,
    output logic [1:0] checkpoint_count_o,
    output logic line_delivery_safe_o,
    output logic blocking_pred_source_valid_o,
    output bbus_ooo_pred_source_e blocking_pred_source_o,
    output bbus_ooo_rob_tag_t blocking_branch_rob_tag_o,
    output logic duplicate_alloc_error_o,
    output logic invalid_alloc_error_o,
    output logic stale_release_error_o,
    output logic stale_lookup_error_o,
    output logic stale_purge_error_o,
    output logic conservation_error_o
);
    bbus_ooo_real_checkpoint_t entries_q [1:0];
    bbus_ooo_real_checkpoint_t entries_d [1:0];
    logic [1:0] line_delivery_safe_q, line_delivery_safe_d;
    bbus_ooo_pred_source_e pred_source_q [1:0];
    bbus_ooo_pred_source_e pred_source_d [1:0];
    logic oldest_idx_q, oldest_idx_d, blocking_idx_c;
    logic source_order_error_c;
    logic duplicate_alloc_error_q, invalid_alloc_error_q;
    logic stale_release_error_q, stale_lookup_error_q, stale_purge_error_q;
    logic release_hit_c, lookup_hit_c, duplicate_hit_c;
    logic selective_purge_resolving_hit_c;
    logic [0:0] release_idx_c, lookup_idx_c;
    logic [1:0] post_release_valid_c;
    logic [0:0] alloc_idx_c;

    function automatic logic tag_match(
        input bbus_ooo_rob_tag_t a,
        input bbus_ooo_rob_tag_t b
    );
        tag_match = a.valid && b.valid &&
            (a.idx == b.idx) && (a.gen == b.gen);
    endfunction

    always_comb begin
        release_hit_c = 1'b0;
        release_idx_c = '0;
        lookup_hit_c = 1'b0;
        lookup_idx_c = '0;
        duplicate_hit_c = 1'b0;
        selective_purge_resolving_hit_c = 1'b0;
        for (int i = 0; i < 2; i = i + 1) begin
            if (entries_q[i].valid &&
                tag_match(entries_q[i].branch_rob_tag,
                          release_branch_rob_tag_i) && !release_hit_c) begin
                release_hit_c = 1'b1;
                release_idx_c = i[0:0];
            end
            if (entries_q[i].valid &&
                tag_match(entries_q[i].branch_rob_tag,
                          lookup_branch_rob_tag_i) && !lookup_hit_c) begin
                lookup_hit_c = 1'b1;
                lookup_idx_c = i[0:0];
            end
            if (entries_q[i].valid &&
                tag_match(entries_q[i].branch_rob_tag,
                          alloc_branch_rob_tag_i)) begin
                duplicate_hit_c = 1'b1;
            end
            if (entries_q[i].valid &&
                tag_match(entries_q[i].branch_rob_tag,
                          selective_purge_branch_rob_tag_i)) begin
                selective_purge_resolving_hit_c = 1'b1;
            end
        end

        post_release_valid_c = {entries_q[1].valid, entries_q[0].valid};
        if (release_valid_i && release_hit_c) begin
            post_release_valid_c[release_idx_c] = 1'b0;
        end
        alloc_idx_c = !post_release_valid_c[0] ? 1'b0 : 1'b1;
        alloc_ready_o = !selective_purge_valid_i && !(&post_release_valid_c);
        alloc_checkpoint_id_o = bbus_ooo_checkpoint_id_t'(alloc_idx_c);

        lookup_hit_o = lookup_valid_i && lookup_hit_c;
        lookup_checkpoint_o = '0;
        if (lookup_hit_o) lookup_checkpoint_o = entries_q[lookup_idx_c];

        debug_query_hit_o = 1'b0;
        debug_query_checkpoint_o = '0;
        for (int i = 0; i < 2; i = i + 1) begin
            if (entries_q[i].valid &&
                (entries_q[i].checkpoint_id ==
                 debug_query_checkpoint_id_i)) begin
                debug_query_hit_o = 1'b1;
                debug_query_checkpoint_o = entries_q[i];
            end
        end

        valid_mask_o = {entries_q[1].valid, entries_q[0].valid};
        checkpoint_count_o = {1'b0, entries_q[0].valid} +
            {1'b0, entries_q[1].valid};
        line_delivery_safe_o = (|valid_mask_o) &&
            (!valid_mask_o[0] || line_delivery_safe_q[0]) &&
            (!valid_mask_o[1] || line_delivery_safe_q[1]);
        blocking_idx_c = oldest_idx_q;
        if (!entries_q[blocking_idx_c].valid ||
            line_delivery_safe_q[blocking_idx_c]) begin
            blocking_idx_c = !oldest_idx_q;
        end
        blocking_pred_source_valid_o =
            entries_q[blocking_idx_c].valid &&
            !line_delivery_safe_q[blocking_idx_c];
        blocking_pred_source_o = BBUS_OOO_PRED_NONE;
        blocking_branch_rob_tag_o = '0;
        if (blocking_pred_source_valid_o) begin
            blocking_pred_source_o = pred_source_q[blocking_idx_c];
            blocking_branch_rob_tag_o =
                entries_q[blocking_idx_c].branch_rob_tag;
        end
        source_order_error_c = (|valid_mask_o) &&
            !entries_q[oldest_idx_q].valid;
        selective_purge_ready_o = selective_purge_resolving_hit_c &&
            !clear_all_i && selective_purge_branch_rob_tag_i.valid &&
            !selective_purge_killed_rob_mask_i[
                selective_purge_branch_rob_tag_i.idx];
        selective_purge_fire_o = selective_purge_valid_i &&
            selective_purge_ready_o;
        selective_purged_mask_o = 2'b00;
        if (selective_purge_fire_o) begin
            for (int i = 0; i < 2; i = i + 1) begin
                selective_purged_mask_o[i] = entries_q[i].valid &&
                    (tag_match(entries_q[i].branch_rob_tag,
                               selective_purge_branch_rob_tag_i) ||
                     selective_purge_killed_rob_mask_i[
                         entries_q[i].branch_rob_tag.idx]);
            end
        end
    end

    always_comb begin
        entries_d[0] = entries_q[0];
        entries_d[1] = entries_q[1];
        line_delivery_safe_d = line_delivery_safe_q;
        pred_source_d[0] = pred_source_q[0];
        pred_source_d[1] = pred_source_q[1];
        oldest_idx_d = oldest_idx_q;

        if (clear_all_i) begin
            entries_d[0] = '0;
            entries_d[1] = '0;
            line_delivery_safe_d = '0;
            pred_source_d[0] = BBUS_OOO_PRED_NONE;
            pred_source_d[1] = BBUS_OOO_PRED_NONE;
        end else if (selective_purge_fire_o) begin
            for (int i = 0; i < 2; i = i + 1) begin
                if (selective_purged_mask_o[i] ||
                    (release_valid_i && release_hit_c &&
                     (release_idx_c == i[0:0]))) begin
                    entries_d[i] = '0;
                    line_delivery_safe_d[i] = 1'b0;
                    pred_source_d[i] = BBUS_OOO_PRED_NONE;
                end
            end
        end else begin
            if (release_valid_i && release_hit_c) begin
                entries_d[release_idx_c] = '0;
                line_delivery_safe_d[release_idx_c] = 1'b0;
                pred_source_d[release_idx_c] = BBUS_OOO_PRED_NONE;
            end
            if (alloc_fire_i && alloc_ready_o &&
                alloc_branch_rob_tag_i.valid && !duplicate_hit_c) begin
                entries_d[alloc_idx_c] = '0;
                entries_d[alloc_idx_c].valid = 1'b1;
                entries_d[alloc_idx_c].checkpoint_id =
                    bbus_ooo_checkpoint_id_t'(alloc_idx_c);
                entries_d[alloc_idx_c].branch_rob_tag =
                    alloc_branch_rob_tag_i;
                entries_d[alloc_idx_c].branch_pc = alloc_branch_pc_i;
                entries_d[alloc_idx_c].branch_op = alloc_branch_op_i;
                entries_d[alloc_idx_c].branch_ras_action =
                    alloc_branch_ras_action_i;
                entries_d[alloc_idx_c].branch_ras_link =
                    alloc_branch_ras_link_i;
                entries_d[alloc_idx_c].rat_snapshot = alloc_rat_snapshot_i;
                entries_d[alloc_idx_c].ras_snapshot = alloc_ras_snapshot_i;
                entries_d[alloc_idx_c].post_branch_tail_tag =
                    alloc_post_branch_tail_tag_i;
                line_delivery_safe_d[alloc_idx_c] =
                    alloc_line_delivery_safe_i;
                pred_source_d[alloc_idx_c] = alloc_pred_source_i;
            end
        end

        if (!entries_d[0].valid) begin
            oldest_idx_d = entries_d[1].valid;
        end else if (!entries_d[1].valid) begin
            oldest_idx_d = 1'b0;
        end else if (alloc_fire_i && alloc_ready_o &&
                     alloc_branch_rob_tag_i.valid && !duplicate_hit_c) begin
            oldest_idx_d = !alloc_idx_c;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            entries_q[0] <= '0;
            entries_q[1] <= '0;
            line_delivery_safe_q <= '0;
            pred_source_q[0] <= BBUS_OOO_PRED_NONE;
            pred_source_q[1] <= BBUS_OOO_PRED_NONE;
            oldest_idx_q <= 1'b0;
            duplicate_alloc_error_q <= 1'b0;
            invalid_alloc_error_q <= 1'b0;
            stale_release_error_q <= 1'b0;
            stale_lookup_error_q <= 1'b0;
            stale_purge_error_q <= 1'b0;
        end else begin
            entries_q[0] <= entries_d[0];
            entries_q[1] <= entries_d[1];
            line_delivery_safe_q <= line_delivery_safe_d;
            pred_source_q[0] <= pred_source_d[0];
            pred_source_q[1] <= pred_source_d[1];
            oldest_idx_q <= oldest_idx_d;
            if (clear_all_i) begin
                duplicate_alloc_error_q <= 1'b0;
                invalid_alloc_error_q <= 1'b0;
                stale_release_error_q <= 1'b0;
                stale_lookup_error_q <= 1'b0;
                stale_purge_error_q <= 1'b0;
            end else begin
                if (alloc_fire_i && duplicate_hit_c)
                    duplicate_alloc_error_q <= 1'b1;
                if (alloc_fire_i && !alloc_branch_rob_tag_i.valid)
                    invalid_alloc_error_q <= 1'b1;
                if (alloc_fire_i && selective_purge_valid_i)
                    invalid_alloc_error_q <= 1'b1;
                if (release_valid_i && !release_hit_c)
                    stale_release_error_q <= 1'b1;
                if (lookup_valid_i && !lookup_hit_c)
                    stale_lookup_error_q <= 1'b1;
                if (selective_purge_valid_i &&
                    (!selective_purge_resolving_hit_c ||
                     selective_purge_killed_rob_mask_i[
                         selective_purge_branch_rob_tag_i.idx]))
                    stale_purge_error_q <= 1'b1;
            end
        end
    end

    assign duplicate_alloc_error_o = duplicate_alloc_error_q;
    assign invalid_alloc_error_o = invalid_alloc_error_q;
    assign stale_release_error_o = stale_release_error_q;
    assign stale_lookup_error_o = stale_lookup_error_q;
    assign stale_purge_error_o = stale_purge_error_q;
    assign conservation_error_o = duplicate_alloc_error_q ||
        invalid_alloc_error_q || stale_release_error_q || stale_lookup_error_q ||
        stale_purge_error_q || source_order_error_c ||
        (!line_delivery_safe_o && (|valid_mask_o) &&
         !blocking_pred_source_valid_o);
endmodule
