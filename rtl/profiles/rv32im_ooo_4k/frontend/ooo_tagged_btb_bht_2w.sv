`timescale 1ns / 1ps

module ooo_tagged_btb_bht_2w #(
    parameter integer ENTRIES = 64,
    parameter bit CORRELATED_ENABLE = 1'b0,
    parameter bit LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE = 1'b0,
    parameter bit MULTIHISTORY_REACHABILITY_ORACLE_ENABLE = 1'b0
) (
    input logic clk,
    input logic reset,

    input logic [1:0] lookup_valid_i,
    input logic [31:0] lookup_pc0_i,
    input logic [31:0] lookup_pc1_i,
    input logic fallback_taken0_i,
    input logic fallback_taken1_i,
    input logic [31:0] direct_target0_i,
    input logic [31:0] direct_target1_i,
    input logic [7:0] lookup_history0_i,
    input logic [7:0] lookup_history1_i,
    output logic hit0_o,
    output logic hit1_o,
    output logic strong0_o,
    output logic strong1_o,
    output logic correlated0_o,
    output logic correlated1_o,
    output logic base_taken0_o,
    output logic base_taken1_o,
    output logic base_counter_valid0_o,
    output logic base_counter_valid1_o,
    output logic base_counter_taken0_o,
    output logic base_counter_taken1_o,
    output logic correlated_candidate0_o,
    output logic correlated_candidate1_o,
    output logic correlated_raw_candidate0_o,
    output logic correlated_raw_candidate1_o,
    output logic correlated_chooser_prefer0_o,
    output logic correlated_chooser_prefer1_o,
    output logic correlated_taken0_o,
    output logic correlated_taken1_o,
    output logic [5:0] local_history0_o,
    output logic [5:0] local_history1_o,
    output logic local_strong0_o,
    output logic local_strong1_o,
    output logic local_taken0_o,
    output logic local_taken1_o,
    output logic local_chooser_prefer0_o,
    output logic local_chooser_prefer1_o,
    output logic local_chooser_strong0_o,
    output logic local_chooser_strong1_o,
    output logic [2:0] multihistory_hit0_o,
    output logic [2:0] multihistory_hit1_o,
    output logic [2:0] multihistory_strong0_o,
    output logic [2:0] multihistory_strong1_o,
    output logic [2:0] multihistory_taken0_o,
    output logic [2:0] multihistory_taken1_o,
    output logic [2:0]
        multihistory_chooser_prefer0_o,
    output logic [2:0]
        multihistory_chooser_prefer1_o,
    output logic [2:0]
        multihistory_chooser_strong0_o,
    output logic [2:0]
        multihistory_chooser_strong1_o,
    output logic pred_taken0_o,
    output logic pred_taken1_o,
    output logic [31:0] pred_target0_o,
    output logic [31:0] pred_target1_o,

    input logic update_valid_i,
    input logic [31:0] update_pc_i,
    input logic [31:0] update_direct_target_i,
    input logic [7:0] update_history_i,
    input logic update_base_taken_i,
    input logic update_correlated_candidate_i,
    input logic update_correlated_taken_i,
    input logic [5:0] update_local_history_i,
    input logic update_local_strong_i,
    input logic update_local_taken_i,
    input logic [2:0] update_multihistory_strong_i,
    input logic [2:0] update_multihistory_taken_i,
    input logic update_current_taken_i,
    input logic update_taken_i
);
    localparam integer INDEX_BITS = $clog2(ENTRIES);
    localparam integer TAG_BITS = 32 - INDEX_BITS - 2;
    localparam integer LOCAL_ENTRIES = 256;
    localparam integer LOCAL_INDEX_BITS = $clog2(LOCAL_ENTRIES);
    localparam integer MULTIHISTORY_TABLES = 3;
    localparam integer MULTIHISTORY_ENTRIES = 256;
    localparam integer MULTIHISTORY_INDEX_BITS =
        $clog2(MULTIHISTORY_ENTRIES);

    logic [ENTRIES-1:0] valid_q;
    logic [TAG_BITS-1:0] tag_q [ENTRIES-1:0];
    logic [31:0] target_q [ENTRIES-1:0];
    logic [1:0] counter_q [ENTRIES-1:0];

    logic [ENTRIES-1:0] correlated_valid_q;
    logic [TAG_BITS-1:0] correlated_tag_q [ENTRIES-1:0];
    logic [31:0] correlated_target_q [ENTRIES-1:0];
    logic [1:0] correlated_counter_q [ENTRIES-1:0];
    logic [2:0] correlated_confidence_q [ENTRIES-1:0];
    logic [1:0] correlated_chooser_q [ENTRIES-1:0];

    logic [LOCAL_ENTRIES-1:0] local_valid_q;
    logic [31:0] local_pc_q [LOCAL_ENTRIES-1:0];
    logic [31:0] local_target_q [LOCAL_ENTRIES-1:0];
    logic [5:0] local_history_q [LOCAL_ENTRIES-1:0];
    logic [63:0] local_pattern_valid_q [LOCAL_ENTRIES-1:0];
    logic [1:0] local_counter_q [LOCAL_ENTRIES-1:0][63:0];
    logic [1:0] local_chooser_q [LOCAL_ENTRIES-1:0][63:0];

    logic [MULTIHISTORY_ENTRIES-1:0] multihistory_valid_q
        [MULTIHISTORY_TABLES-1:0];
    logic [31:0] multihistory_pc_q
        [MULTIHISTORY_TABLES-1:0][MULTIHISTORY_ENTRIES-1:0];
    logic [31:0] multihistory_target_q
        [MULTIHISTORY_TABLES-1:0][MULTIHISTORY_ENTRIES-1:0];
    logic [7:0] multihistory_history_q
        [MULTIHISTORY_TABLES-1:0][MULTIHISTORY_ENTRIES-1:0];
    logic [1:0] multihistory_counter_q
        [MULTIHISTORY_TABLES-1:0][MULTIHISTORY_ENTRIES-1:0];
    logic [1:0] multihistory_chooser_q
        [MULTIHISTORY_TABLES-1:0][MULTIHISTORY_ENTRIES-1:0];

    logic [INDEX_BITS-1:0] lookup_idx0_c, lookup_idx1_c, update_idx_c;
    logic [INDEX_BITS-1:0] correlated_lookup_idx0_c;
    logic [INDEX_BITS-1:0] correlated_lookup_idx1_c;
    logic [INDEX_BITS-1:0] correlated_update_idx_c;
    logic [TAG_BITS-1:0] lookup_tag0_c, lookup_tag1_c, update_tag_c;
    logic update_hit_c;
    logic base_hit0_c, base_hit1_c;
    logic base_strong0_c, base_strong1_c;
    logic base_taken0_c, base_taken1_c;
    logic correlated_hit0_c, correlated_hit1_c;
    logic correlated_counter_strong0_c, correlated_counter_strong1_c;
    logic correlated_strong0_c, correlated_strong1_c;
    logic correlated_update_hit_c;
    logic [LOCAL_INDEX_BITS-1:0] local_lookup_idx0_c;
    logic [LOCAL_INDEX_BITS-1:0] local_lookup_idx1_c;
    logic [LOCAL_INDEX_BITS-1:0] local_update_idx_c;
    logic local_hit0_c, local_hit1_c, local_update_hit_c;
    logic [5:0] local_lookup_history0_c, local_lookup_history1_c;
    logic local_pattern_hit0_c, local_pattern_hit1_c;
    logic [7:0] multihistory_lookup_history0_c
        [MULTIHISTORY_TABLES-1:0];
    logic [7:0] multihistory_lookup_history1_c
        [MULTIHISTORY_TABLES-1:0];
    logic [7:0] multihistory_update_history_c
        [MULTIHISTORY_TABLES-1:0];
    logic [MULTIHISTORY_INDEX_BITS-1:0] multihistory_lookup_idx0_c
        [MULTIHISTORY_TABLES-1:0];
    logic [MULTIHISTORY_INDEX_BITS-1:0] multihistory_lookup_idx1_c
        [MULTIHISTORY_TABLES-1:0];
    logic [MULTIHISTORY_INDEX_BITS-1:0] multihistory_update_idx_c
        [MULTIHISTORY_TABLES-1:0];
    logic [2:0] multihistory_update_hit_c;

    function automatic logic [1:0] saturating_update(
        input logic [1:0] old_counter,
        input logic taken
    );
        begin
            if (taken) begin
                saturating_update = (old_counter == 2'b11) ?
                    2'b11 : old_counter + 2'b01;
            end else begin
                saturating_update = (old_counter == 2'b00) ?
                    2'b00 : old_counter - 2'b01;
            end
        end
    endfunction

    function automatic logic [INDEX_BITS-1:0] fold_history(
        input logic [7:0] history
    );
        logic [INDEX_BITS-1:0] folded;
        begin
            folded = '0;
            for (int bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1)
                folded[bit_idx % INDEX_BITS] =
                    folded[bit_idx % INDEX_BITS] ^ history[bit_idx];
            fold_history = folded;
        end
    endfunction

    function automatic logic [7:0] multihistory_mask(
        input logic [7:0] history,
        input integer table_index
    );
        begin
            case (table_index)
                0: multihistory_mask = history & 8'h03;
                1: multihistory_mask = history & 8'h0f;
                default: multihistory_mask = history;
            endcase
        end
    endfunction

    assign lookup_idx0_c = lookup_pc0_i[INDEX_BITS+1:2];
    assign lookup_idx1_c = lookup_pc1_i[INDEX_BITS+1:2];
    assign lookup_tag0_c = lookup_pc0_i[31:INDEX_BITS+2];
    assign lookup_tag1_c = lookup_pc1_i[31:INDEX_BITS+2];
    assign update_idx_c = update_pc_i[INDEX_BITS+1:2];
    assign update_tag_c = update_pc_i[31:INDEX_BITS+2];
    assign correlated_lookup_idx0_c = lookup_idx0_c ^
        fold_history(lookup_history0_i);
    assign correlated_lookup_idx1_c = lookup_idx1_c ^
        fold_history(lookup_history1_i);
    assign correlated_update_idx_c = update_idx_c ^
        fold_history(update_history_i);
    assign local_lookup_idx0_c = lookup_pc0_i[LOCAL_INDEX_BITS+1:2];
    assign local_lookup_idx1_c = lookup_pc1_i[LOCAL_INDEX_BITS+1:2];
    assign local_update_idx_c = update_pc_i[LOCAL_INDEX_BITS+1:2];
    assign update_hit_c = update_valid_i && valid_q[update_idx_c] &&
        (tag_q[update_idx_c] == update_tag_c) &&
        (target_q[update_idx_c] == update_direct_target_i);
    assign correlated_update_hit_c = CORRELATED_ENABLE && update_valid_i &&
        correlated_valid_q[correlated_update_idx_c] &&
        (correlated_tag_q[correlated_update_idx_c] == update_tag_c) &&
        (correlated_target_q[correlated_update_idx_c] ==
         update_direct_target_i);
    assign local_update_hit_c = LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE &&
        update_valid_i && local_valid_q[local_update_idx_c] &&
        (local_pc_q[local_update_idx_c] == update_pc_i) &&
        (local_target_q[local_update_idx_c] == update_direct_target_i);

    always_comb begin
        base_hit0_c = lookup_valid_i[0] && valid_q[lookup_idx0_c] &&
            (tag_q[lookup_idx0_c] == lookup_tag0_c) &&
            (target_q[lookup_idx0_c] == direct_target0_i);
        base_hit1_c = lookup_valid_i[1] && valid_q[lookup_idx1_c] &&
            (tag_q[lookup_idx1_c] == lookup_tag1_c) &&
            (target_q[lookup_idx1_c] == direct_target1_i);
        base_strong0_c = base_hit0_c &&
            ((counter_q[lookup_idx0_c] == 2'b00) ||
            (counter_q[lookup_idx0_c] == 2'b11));
        base_strong1_c = base_hit1_c &&
            ((counter_q[lookup_idx1_c] == 2'b00) ||
            (counter_q[lookup_idx1_c] == 2'b11));
        base_taken0_c = base_hit0_c &&
            (counter_q[lookup_idx0_c] == 2'b11) ? 1'b1 :
            base_hit0_c && (counter_q[lookup_idx0_c] == 2'b00) ? 1'b0 :
            fallback_taken0_i;
        base_taken1_c = base_hit1_c &&
            (counter_q[lookup_idx1_c] == 2'b11) ? 1'b1 :
            base_hit1_c && (counter_q[lookup_idx1_c] == 2'b00) ? 1'b0 :
            fallback_taken1_i;

        correlated_hit0_c = CORRELATED_ENABLE && lookup_valid_i[0] &&
            correlated_valid_q[correlated_lookup_idx0_c] &&
            (correlated_tag_q[correlated_lookup_idx0_c] == lookup_tag0_c) &&
            (correlated_target_q[correlated_lookup_idx0_c] == direct_target0_i);
        correlated_hit1_c = CORRELATED_ENABLE && lookup_valid_i[1] &&
            correlated_valid_q[correlated_lookup_idx1_c] &&
            (correlated_tag_q[correlated_lookup_idx1_c] == lookup_tag1_c) &&
            (correlated_target_q[correlated_lookup_idx1_c] == direct_target1_i);
        correlated_counter_strong0_c = correlated_hit0_c &&
            ((correlated_counter_q[correlated_lookup_idx0_c] == 2'b00) ||
             (correlated_counter_q[correlated_lookup_idx0_c] == 2'b11));
        correlated_counter_strong1_c = correlated_hit1_c &&
            ((correlated_counter_q[correlated_lookup_idx1_c] == 2'b00) ||
             (correlated_counter_q[correlated_lookup_idx1_c] == 2'b11));
        correlated_strong0_c = correlated_counter_strong0_c &&
            (correlated_confidence_q[correlated_lookup_idx0_c] == 3'b111);
        correlated_strong1_c = correlated_counter_strong1_c &&
            (correlated_confidence_q[correlated_lookup_idx1_c] == 3'b111);

        local_hit0_c = LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE &&
            lookup_valid_i[0] && local_valid_q[local_lookup_idx0_c] &&
            (local_pc_q[local_lookup_idx0_c] == lookup_pc0_i) &&
            (local_target_q[local_lookup_idx0_c] == direct_target0_i);
        local_hit1_c = LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE &&
            lookup_valid_i[1] && local_valid_q[local_lookup_idx1_c] &&
            (local_pc_q[local_lookup_idx1_c] == lookup_pc1_i) &&
            (local_target_q[local_lookup_idx1_c] == direct_target1_i);
        local_lookup_history0_c = local_hit0_c ?
            local_history_q[local_lookup_idx0_c] : 6'b0;
        local_lookup_history1_c = local_hit1_c ?
            local_history_q[local_lookup_idx1_c] : 6'b0;
        local_pattern_hit0_c = local_hit0_c &&
            local_pattern_valid_q[local_lookup_idx0_c]
                [local_lookup_history0_c];
        local_pattern_hit1_c = local_hit1_c &&
            local_pattern_valid_q[local_lookup_idx1_c]
                [local_lookup_history1_c];

        multihistory_hit0_o = '0;
        multihistory_hit1_o = '0;
        multihistory_strong0_o = '0;
        multihistory_strong1_o = '0;
        multihistory_taken0_o = '0;
        multihistory_taken1_o = '0;
        multihistory_chooser_prefer0_o = '0;
        multihistory_chooser_prefer1_o = '0;
        multihistory_chooser_strong0_o = '0;
        multihistory_chooser_strong1_o = '0;
        multihistory_update_hit_c = '0;
        for (int table_index = 0;
             table_index < MULTIHISTORY_TABLES; table_index++) begin
            multihistory_lookup_history0_c[table_index] =
                multihistory_mask(lookup_history0_i, table_index);
            multihistory_lookup_history1_c[table_index] =
                multihistory_mask(lookup_history1_i, table_index);
            multihistory_update_history_c[table_index] =
                multihistory_mask(update_history_i, table_index);
            multihistory_lookup_idx0_c[table_index] =
                lookup_pc0_i[MULTIHISTORY_INDEX_BITS+1:2] ^
                multihistory_lookup_history0_c[table_index];
            multihistory_lookup_idx1_c[table_index] =
                lookup_pc1_i[MULTIHISTORY_INDEX_BITS+1:2] ^
                multihistory_lookup_history1_c[table_index];
            multihistory_update_idx_c[table_index] =
                update_pc_i[MULTIHISTORY_INDEX_BITS+1:2] ^
                multihistory_update_history_c[table_index];
            multihistory_hit0_o[table_index] =
                MULTIHISTORY_REACHABILITY_ORACLE_ENABLE &&
                lookup_valid_i[0] &&
                multihistory_valid_q[table_index]
                    [multihistory_lookup_idx0_c[table_index]] &&
                (multihistory_pc_q[table_index]
                    [multihistory_lookup_idx0_c[table_index]] ==
                    lookup_pc0_i) &&
                (multihistory_target_q[table_index]
                    [multihistory_lookup_idx0_c[table_index]] ==
                    direct_target0_i) &&
                (multihistory_history_q[table_index]
                    [multihistory_lookup_idx0_c[table_index]] ==
                    multihistory_lookup_history0_c[table_index]);
            multihistory_hit1_o[table_index] =
                MULTIHISTORY_REACHABILITY_ORACLE_ENABLE &&
                lookup_valid_i[1] &&
                multihistory_valid_q[table_index]
                    [multihistory_lookup_idx1_c[table_index]] &&
                (multihistory_pc_q[table_index]
                    [multihistory_lookup_idx1_c[table_index]] ==
                    lookup_pc1_i) &&
                (multihistory_target_q[table_index]
                    [multihistory_lookup_idx1_c[table_index]] ==
                    direct_target1_i) &&
                (multihistory_history_q[table_index]
                    [multihistory_lookup_idx1_c[table_index]] ==
                    multihistory_lookup_history1_c[table_index]);
            multihistory_update_hit_c[table_index] =
                MULTIHISTORY_REACHABILITY_ORACLE_ENABLE &&
                update_valid_i &&
                multihistory_valid_q[table_index]
                    [multihistory_update_idx_c[table_index]] &&
                (multihistory_pc_q[table_index]
                    [multihistory_update_idx_c[table_index]] ==
                    update_pc_i) &&
                (multihistory_target_q[table_index]
                    [multihistory_update_idx_c[table_index]] ==
                    update_direct_target_i) &&
                (multihistory_history_q[table_index]
                    [multihistory_update_idx_c[table_index]] ==
                    multihistory_update_history_c[table_index]);
            multihistory_strong0_o[table_index] =
                multihistory_hit0_o[table_index] &&
                ((multihistory_counter_q[table_index]
                    [multihistory_lookup_idx0_c[table_index]] == 2'b00) ||
                 (multihistory_counter_q[table_index]
                    [multihistory_lookup_idx0_c[table_index]] == 2'b11));
            multihistory_strong1_o[table_index] =
                multihistory_hit1_o[table_index] &&
                ((multihistory_counter_q[table_index]
                    [multihistory_lookup_idx1_c[table_index]] == 2'b00) ||
                 (multihistory_counter_q[table_index]
                    [multihistory_lookup_idx1_c[table_index]] == 2'b11));
            multihistory_taken0_o[table_index] =
                multihistory_hit0_o[table_index] &&
                multihistory_counter_q[table_index]
                    [multihistory_lookup_idx0_c[table_index]][1];
            multihistory_taken1_o[table_index] =
                multihistory_hit1_o[table_index] &&
                multihistory_counter_q[table_index]
                    [multihistory_lookup_idx1_c[table_index]][1];
            multihistory_chooser_prefer0_o[table_index] =
                multihistory_hit0_o[table_index] &&
                multihistory_chooser_q[table_index]
                    [multihistory_lookup_idx0_c[table_index]][1];
            multihistory_chooser_prefer1_o[table_index] =
                multihistory_hit1_o[table_index] &&
                multihistory_chooser_q[table_index]
                    [multihistory_lookup_idx1_c[table_index]][1];
            multihistory_chooser_strong0_o[table_index] =
                multihistory_hit0_o[table_index] &&
                (multihistory_chooser_q[table_index]
                    [multihistory_lookup_idx0_c[table_index]] == 2'b11);
            multihistory_chooser_strong1_o[table_index] =
                multihistory_hit1_o[table_index] &&
                (multihistory_chooser_q[table_index]
                    [multihistory_lookup_idx1_c[table_index]] == 2'b11);
        end

        base_taken0_o = base_taken0_c;
        base_taken1_o = base_taken1_c;
        base_counter_valid0_o = base_hit0_c;
        base_counter_valid1_o = base_hit1_c;
        base_counter_taken0_o = base_hit0_c &&
            counter_q[lookup_idx0_c][1];
        base_counter_taken1_o = base_hit1_c &&
            counter_q[lookup_idx1_c][1];
        correlated_candidate0_o = correlated_strong0_c;
        correlated_candidate1_o = correlated_strong1_c;
        correlated_raw_candidate0_o = correlated_counter_strong0_c;
        correlated_raw_candidate1_o = correlated_counter_strong1_c;
        correlated_chooser_prefer0_o = correlated_hit0_c &&
            correlated_chooser_q[correlated_lookup_idx0_c][1];
        correlated_chooser_prefer1_o = correlated_hit1_c &&
            correlated_chooser_q[correlated_lookup_idx1_c][1];
        correlated_taken0_o =
            correlated_counter_q[correlated_lookup_idx0_c][1];
        correlated_taken1_o =
            correlated_counter_q[correlated_lookup_idx1_c][1];
        local_history0_o = local_lookup_history0_c;
        local_history1_o = local_lookup_history1_c;
        local_strong0_o = local_pattern_hit0_c &&
            ((local_counter_q[local_lookup_idx0_c]
                [local_lookup_history0_c] == 2'b00) ||
             (local_counter_q[local_lookup_idx0_c]
                [local_lookup_history0_c] == 2'b11));
        local_strong1_o = local_pattern_hit1_c &&
            ((local_counter_q[local_lookup_idx1_c]
                [local_lookup_history1_c] == 2'b00) ||
             (local_counter_q[local_lookup_idx1_c]
                [local_lookup_history1_c] == 2'b11));
        local_taken0_o = local_pattern_hit0_c &&
            local_counter_q[local_lookup_idx0_c][local_lookup_history0_c][1];
        local_taken1_o = local_pattern_hit1_c &&
            local_counter_q[local_lookup_idx1_c][local_lookup_history1_c][1];
        local_chooser_prefer0_o = local_pattern_hit0_c &&
            local_chooser_q[local_lookup_idx0_c][local_lookup_history0_c][1];
        local_chooser_prefer1_o = local_pattern_hit1_c &&
            local_chooser_q[local_lookup_idx1_c][local_lookup_history1_c][1];
        local_chooser_strong0_o = local_pattern_hit0_c &&
            (local_chooser_q[local_lookup_idx0_c]
                [local_lookup_history0_c] == 2'b11);
        local_chooser_strong1_o = local_pattern_hit1_c &&
            (local_chooser_q[local_lookup_idx1_c]
                [local_lookup_history1_c] == 2'b11);
        correlated0_o = correlated_candidate0_o &&
            (correlated_chooser_q[correlated_lookup_idx0_c] == 2'b11) &&
            (correlated_taken0_o != base_taken0_o);
        correlated1_o = correlated_candidate1_o &&
            (correlated_chooser_q[correlated_lookup_idx1_c] == 2'b11) &&
            (correlated_taken1_o != base_taken1_o);
        hit0_o = base_hit0_c || correlated0_o;
        hit1_o = base_hit1_c || correlated1_o;
        strong0_o = correlated0_o || base_strong0_c;
        strong1_o = correlated1_o || base_strong1_c;
        pred_taken0_o = correlated0_o ?
            correlated_counter_q[correlated_lookup_idx0_c][1] : base_taken0_c;
        pred_taken1_o = correlated1_o ?
            correlated_counter_q[correlated_lookup_idx1_c][1] : base_taken1_c;
        pred_target0_o = pred_taken0_o ? direct_target0_i : lookup_pc0_i + 32'd4;
        pred_target1_o = pred_taken1_o ? direct_target1_i : lookup_pc1_i + 32'd4;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            valid_q <= '0;
            correlated_valid_q <= '0;
            local_valid_q <= '0;
            for (int table_index = 0;
                 table_index < MULTIHISTORY_TABLES; table_index++)
                multihistory_valid_q[table_index] <= '0;
        end else if (update_valid_i) begin
            valid_q[update_idx_c] <= 1'b1;
            tag_q[update_idx_c] <= update_tag_c;
            target_q[update_idx_c] <= update_direct_target_i;
            counter_q[update_idx_c] <= update_hit_c ?
                saturating_update(counter_q[update_idx_c], update_taken_i) :
                (update_taken_i ? 2'b10 : 2'b01);
            if (CORRELATED_ENABLE) begin
                correlated_valid_q[correlated_update_idx_c] <= 1'b1;
                correlated_tag_q[correlated_update_idx_c] <= update_tag_c;
                correlated_target_q[correlated_update_idx_c] <=
                    update_direct_target_i;
                correlated_counter_q[correlated_update_idx_c] <=
                    correlated_update_hit_c ?
                    saturating_update(
                        correlated_counter_q[correlated_update_idx_c],
                        update_taken_i
                    ) : (update_taken_i ? 2'b10 : 2'b01);
                if (!correlated_update_hit_c) begin
                    correlated_confidence_q[correlated_update_idx_c] <= 3'b000;
                    correlated_chooser_q[correlated_update_idx_c] <= 2'b01;
                end else if (correlated_counter_q[correlated_update_idx_c][1] ==
                             update_taken_i) begin
                    correlated_confidence_q[correlated_update_idx_c] <=
                        (correlated_confidence_q[correlated_update_idx_c] ==
                         3'b111) ? 3'b111 :
                        correlated_confidence_q[correlated_update_idx_c] + 3'b001;
                end else begin
                    correlated_confidence_q[correlated_update_idx_c] <= 3'b000;
                end
                if (correlated_update_hit_c &&
                    update_correlated_candidate_i &&
                    (update_base_taken_i != update_correlated_taken_i)) begin
                    if ((update_correlated_taken_i == update_taken_i) &&
                        (update_base_taken_i != update_taken_i)) begin
                        correlated_chooser_q[correlated_update_idx_c] <=
                            saturating_update(
                                correlated_chooser_q[correlated_update_idx_c],
                                1'b1
                            );
                    end else if ((update_base_taken_i == update_taken_i) &&
                                 (update_correlated_taken_i != update_taken_i)) begin
                        correlated_chooser_q[correlated_update_idx_c] <=
                            saturating_update(
                                correlated_chooser_q[correlated_update_idx_c],
                                1'b0
                            );
                    end
                end
            end
            if (LOCAL_HISTORY_REACHABILITY_ORACLE_ENABLE) begin
                local_valid_q[local_update_idx_c] <= 1'b1;
                local_pc_q[local_update_idx_c] <= update_pc_i;
                local_target_q[local_update_idx_c] <=
                    update_direct_target_i;
                local_history_q[local_update_idx_c] <=
                    {update_local_history_i[4:0], update_taken_i};
                if (!local_update_hit_c) begin
                    local_pattern_valid_q[local_update_idx_c] <= 64'b0;
                    local_pattern_valid_q[local_update_idx_c]
                        [update_local_history_i] <= 1'b1;
                    local_counter_q[local_update_idx_c]
                        [update_local_history_i] <=
                        update_taken_i ? 2'b10 : 2'b01;
                    local_chooser_q[local_update_idx_c]
                        [update_local_history_i] <= 2'b01;
                end else if (!local_pattern_valid_q[local_update_idx_c]
                             [update_local_history_i]) begin
                    local_pattern_valid_q[local_update_idx_c]
                        [update_local_history_i] <= 1'b1;
                    local_counter_q[local_update_idx_c]
                        [update_local_history_i] <=
                        update_taken_i ? 2'b10 : 2'b01;
                    local_chooser_q[local_update_idx_c]
                        [update_local_history_i] <= 2'b01;
                end else begin
                    local_counter_q[local_update_idx_c]
                        [update_local_history_i] <= saturating_update(
                            local_counter_q[local_update_idx_c]
                                [update_local_history_i],
                            update_taken_i
                        );
                    if (update_local_strong_i &&
                        (update_local_taken_i != update_current_taken_i)) begin
                        if ((update_local_taken_i == update_taken_i) &&
                            (update_current_taken_i != update_taken_i)) begin
                            local_chooser_q[local_update_idx_c]
                                [update_local_history_i] <= saturating_update(
                                    local_chooser_q[local_update_idx_c]
                                        [update_local_history_i],
                                    1'b1
                                );
                        end else if ((update_current_taken_i == update_taken_i) &&
                                     (update_local_taken_i != update_taken_i)) begin
                            local_chooser_q[local_update_idx_c]
                                [update_local_history_i] <= saturating_update(
                                    local_chooser_q[local_update_idx_c]
                                        [update_local_history_i],
                                    1'b0
                                );
                        end
                    end
                end
            end
            if (MULTIHISTORY_REACHABILITY_ORACLE_ENABLE) begin
                for (int table_index = 0;
                     table_index < MULTIHISTORY_TABLES; table_index++) begin
                    multihistory_valid_q[table_index]
                        [multihistory_update_idx_c[table_index]] <= 1'b1;
                    multihistory_pc_q[table_index]
                        [multihistory_update_idx_c[table_index]] <=
                        update_pc_i;
                    multihistory_target_q[table_index]
                        [multihistory_update_idx_c[table_index]] <=
                        update_direct_target_i;
                    multihistory_history_q[table_index]
                        [multihistory_update_idx_c[table_index]] <=
                        multihistory_update_history_c[table_index];
                    if (!multihistory_update_hit_c[table_index]) begin
                        multihistory_counter_q[table_index]
                            [multihistory_update_idx_c[table_index]] <=
                            update_taken_i ? 2'b10 : 2'b01;
                        multihistory_chooser_q[table_index]
                            [multihistory_update_idx_c[table_index]] <= 2'b01;
                    end else begin
                        multihistory_counter_q[table_index]
                            [multihistory_update_idx_c[table_index]] <=
                            saturating_update(
                                multihistory_counter_q[table_index]
                                    [multihistory_update_idx_c[table_index]],
                                update_taken_i
                            );
                        if (update_multihistory_strong_i[table_index] &&
                            (update_multihistory_taken_i[table_index] !=
                             update_current_taken_i)) begin
                            if ((update_multihistory_taken_i[table_index] ==
                                 update_taken_i) &&
                                (update_current_taken_i != update_taken_i)) begin
                                multihistory_chooser_q[table_index]
                                    [multihistory_update_idx_c[table_index]] <=
                                    saturating_update(
                                        multihistory_chooser_q[table_index]
                                            [multihistory_update_idx_c
                                                [table_index]],
                                        1'b1
                                    );
                            end else if ((update_current_taken_i ==
                                         update_taken_i) &&
                                        (update_multihistory_taken_i
                                            [table_index] !=
                                         update_taken_i)) begin
                                multihistory_chooser_q[table_index]
                                    [multihistory_update_idx_c[table_index]] <=
                                    saturating_update(
                                        multihistory_chooser_q[table_index]
                                            [multihistory_update_idx_c
                                                [table_index]],
                                        1'b0
                                    );
                            end
                        end
                    end
                end
            end
        end
    end
endmodule
