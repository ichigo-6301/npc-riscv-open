`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_dual_wb_lsu_load_adapter_3src (
    input  logic clk,
    input  logic reset,

    input  bbus_ooo_rob_idx_t rob_head_i,

    input  bbus_ooo_writeback_t alu0_wb_i,
    input  logic alu0_valid_i,
    input  logic alu0_rob_match_i,
    input  logic alu0_killed_i,

    input  bbus_ooo_writeback_t alu1_wb_i,
    input  logic alu1_valid_i,
    input  logic alu1_rob_match_i,
    input  logic alu1_killed_i,

    input  bbus_ooo_writeback_t lsu_wb_i,
    input  logic lsu_valid_i,
    input  logic lsu_rob_match_i,
    input  logic lsu_killed_i,

    input  logic pending_nonempty_i,

    input  logic [1:0] wrapper_source_accept_mask_i,
    input  logic [1:0] wrapper_source_drop_mask_i,
    input  logic [1:0] wrapper_source_clear_mask_i,

    output bbus_ooo_writeback_t lane0_wb_o,
    output bbus_ooo_writeback_t lane1_wb_o,
    output logic lane0_valid_o,
    output logic lane1_valid_o,

    output logic [1:0] lane0_source_id_o,
    output logic [1:0] lane1_source_id_o,

    output logic [2:0] selected_source_mask_o,
    output logic [2:0] source_accept_mask_o,
    output logic [2:0] source_drop_mask_o,
    output logic [2:0] source_clear_mask_o,

    output logic serializing_lsu_o,
    output logic lsu_load_pairable_o,
    output logic lsu_store_block_o,
    output logic lsu_exception_block_o,
    output logic pending_priority_o,
    output logic duplicate_phys_guard_o,
    output logic duplicate_rob_tag_guard_o
);
    localparam logic [1:0] SRC_ALU0     = 2'd0;
    localparam logic [1:0] SRC_ALU1     = 2'd1;
    localparam logic [1:0] SRC_LSU_LOAD = 2'd2;
    localparam logic [1:0] SRC_NONE     = 2'd3;

    localparam int SRC_N = 3;
    localparam int ROB_N = `BBUS_OOO_ROB_ENTRIES;

    bbus_ooo_writeback_t src_wb [SRC_N-1:0];
    logic [SRC_N-1:0] src_valid;
    logic [SRC_N-1:0] src_rob_match;
    logic [SRC_N-1:0] src_killed;
    logic [SRC_N-1:0] src_eligible;
    logic [SRC_N-1:0] src_pairable;
    logic [SRC_N-1:0] src_serializing;
    logic [SRC_N-1:0] src_drop;
    logic [SRC_N-1:0] raw_source_drop_mask_c;

    logic lsu_eligible_c;
    logic lsu_serializing_c;
    int best0;
    int best1;
    int serializing_best;
    logic best0_valid;
    logic best1_valid;
    logic serializing_best_valid;

    assign src_wb[0] = alu0_wb_i;
    assign src_wb[1] = alu1_wb_i;
    assign src_wb[2] = lsu_wb_i;
    assign src_valid[0] = alu0_valid_i;
    assign src_valid[1] = alu1_valid_i;
    assign src_valid[2] = lsu_valid_i;
    assign src_rob_match[0] = alu0_rob_match_i;
    assign src_rob_match[1] = alu1_rob_match_i;
    assign src_rob_match[2] = lsu_rob_match_i;
    assign src_killed[0] = alu0_killed_i;
    assign src_killed[1] = alu1_killed_i;
    assign src_killed[2] = lsu_killed_i;

    function automatic logic alu_pairable(input bbus_ooo_writeback_t wb);
        begin
            alu_pairable =
                wb.valid &&
                !wb.exception.valid &&
                !wb.is_control &&
                !wb.redirect_valid;
        end
    endfunction

    function automatic logic lsu_load_pairable(input bbus_ooo_writeback_t wb);
        begin
            lsu_load_pairable =
                wb.valid &&
                wb.is_load &&
                !wb.is_store &&
                !wb.exception.valid &&
                !wb.is_control &&
                !wb.redirect_valid &&
                !wb.is_csr &&
                !wb.is_system;
        end
    endfunction

    function automatic logic exception_or_control(input bbus_ooo_writeback_t wb);
        begin
            exception_or_control =
                wb.valid &&
                (wb.exception.valid ||
                 wb.is_control ||
                 wb.redirect_valid ||
                 wb.is_csr ||
                 wb.is_system);
        end
    endfunction

    function automatic int fixed_rank(input int source_id);
        begin
            case (source_id)
                int'(SRC_LSU_LOAD): fixed_rank = 0;
                int'(SRC_ALU0):     fixed_rank = 1;
                int'(SRC_ALU1):     fixed_rank = 2;
                default:            fixed_rank = 3;
            endcase
        end
    endfunction

    function automatic int rob_age(input int source_id);
        int idx_i;
        begin
            idx_i = int'(src_wb[source_id].rob_tag.idx);
            rob_age = (idx_i + ROB_N - int'(rob_head_i)) % ROB_N;
        end
    endfunction

    function automatic logic older_than(input int lhs, input int rhs);
        int lhs_age;
        int rhs_age;
        begin
            lhs_age = rob_age(lhs);
            rhs_age = rob_age(rhs);
            older_than =
                (lhs_age < rhs_age) ||
                ((lhs_age == rhs_age) && (fixed_rank(lhs) < fixed_rank(rhs)));
        end
    endfunction

    always_comb begin
        int i;

        for (i = 0; i < SRC_N; i++) begin
            src_drop[i] =
                src_valid[i] &&
                src_wb[i].valid &&
                (!src_rob_match[i] || src_killed[i]);
            src_eligible[i] =
                src_valid[i] &&
                src_wb[i].valid &&
                src_rob_match[i] &&
                !src_killed[i];
            src_pairable[i] = 1'b0;
            src_serializing[i] =
                src_eligible[i] && exception_or_control(src_wb[i]);
        end

        src_pairable[int'(SRC_ALU0)] =
            src_eligible[int'(SRC_ALU0)] && alu_pairable(src_wb[int'(SRC_ALU0)]);
        src_pairable[int'(SRC_ALU1)] =
            src_eligible[int'(SRC_ALU1)] && alu_pairable(src_wb[int'(SRC_ALU1)]);
        src_pairable[int'(SRC_LSU_LOAD)] =
            src_eligible[int'(SRC_LSU_LOAD)] && lsu_load_pairable(src_wb[int'(SRC_LSU_LOAD)]);

        lsu_eligible_c = src_eligible[int'(SRC_LSU_LOAD)];
        lsu_serializing_c = src_serializing[int'(SRC_LSU_LOAD)];

        best0 = 0;
        best1 = 0;
        serializing_best = 0;
        best0_valid = 1'b0;
        best1_valid = 1'b0;
        serializing_best_valid = 1'b0;

        // Exception/control packets are never pairable. Select exactly one
        // serializing source so an eligible ALU exception cannot wait forever
        // behind a selector that only knows how to serialize LSU packets.
        for (i = 0; i < SRC_N; i++) begin
            if (src_serializing[i] &&
                (!serializing_best_valid || older_than(i, serializing_best))) begin
                serializing_best = i;
                serializing_best_valid = 1'b1;
            end
        end

        lane0_wb_o = '0;
        lane1_wb_o = '0;
        lane0_valid_o = 1'b0;
        lane1_valid_o = 1'b0;
        lane0_source_id_o = SRC_NONE;
        lane1_source_id_o = SRC_NONE;
        selected_source_mask_o = 3'b000;
        raw_source_drop_mask_c = 3'b000;
        serializing_lsu_o = 1'b0;
        lsu_load_pairable_o = 1'b0;
        lsu_store_block_o = 1'b0;
        lsu_exception_block_o = 1'b0;
        pending_priority_o = pending_nonempty_i;
        duplicate_phys_guard_o = 1'b0;
        duplicate_rob_tag_guard_o = 1'b0;

        if (!pending_nonempty_i) begin
            raw_source_drop_mask_c = src_drop;
            lsu_load_pairable_o = src_pairable[int'(SRC_LSU_LOAD)];
            lsu_store_block_o =
                lsu_eligible_c &&
                src_wb[int'(SRC_LSU_LOAD)].is_store && !lsu_serializing_c;
            lsu_exception_block_o = lsu_serializing_c;
            serializing_lsu_o = lsu_serializing_c;

            if (serializing_best_valid) begin
                lane0_wb_o = src_wb[serializing_best];
                lane0_valid_o = 1'b1;
                lane0_source_id_o = serializing_best[1:0];
                selected_source_mask_o[serializing_best] = 1'b1;
            end else begin
                for (i = 0; i < SRC_N; i++) begin
                    if (src_pairable[i]) begin
                        if (!best0_valid) begin
                            best0 = i;
                            best0_valid = 1'b1;
                        end else if (older_than(i, best0)) begin
                            best1 = best0;
                            best1_valid = 1'b1;
                            best0 = i;
                        end else if (!best1_valid) begin
                            best1 = i;
                            best1_valid = 1'b1;
                        end else if (older_than(i, best1)) begin
                            best1 = i;
                        end
                    end
                end

                if (best0_valid) begin
                    lane0_wb_o = src_wb[best0];
                    lane0_valid_o = 1'b1;
                    lane0_source_id_o = best0[1:0];
                    selected_source_mask_o[best0] = 1'b1;
                end
                if (best1_valid) begin
                    lane1_wb_o = src_wb[best1];
                    lane1_valid_o = 1'b1;
                    lane1_source_id_o = best1[1:0];
                    selected_source_mask_o[best1] = 1'b1;
                end
            end

        end

        if (lane0_valid_o && lane1_valid_o) begin
            duplicate_phys_guard_o =
                (lane0_wb_o.phys_rd == lane1_wb_o.phys_rd) &&
                (lane0_wb_o.phys_rd != `BBUS_OOO_PHYS_ZERO);
            duplicate_rob_tag_guard_o =
                lane0_wb_o.rob_tag.valid &&
                lane1_wb_o.rob_tag.valid &&
                (lane0_wb_o.rob_tag == lane1_wb_o.rob_tag);
        end
    end

    always_comb begin
        source_accept_mask_o = 3'b000;
        source_drop_mask_o = raw_source_drop_mask_c;

        if (!pending_nonempty_i) begin
            if (lane0_valid_o && (lane0_source_id_o != SRC_NONE) &&
                wrapper_source_drop_mask_i[0] && wrapper_source_clear_mask_i[0]) begin
                source_drop_mask_o[lane0_source_id_o] = 1'b1;
            end
            if (lane1_valid_o && (lane1_source_id_o != SRC_NONE) &&
                wrapper_source_drop_mask_i[1] && wrapper_source_clear_mask_i[1]) begin
                source_drop_mask_o[lane1_source_id_o] = 1'b1;
            end
            if (lane0_valid_o && (lane0_source_id_o != SRC_NONE)) begin
                source_accept_mask_o[lane0_source_id_o] =
                    wrapper_source_accept_mask_i[0] && wrapper_source_clear_mask_i[0];
            end
            if (lane1_valid_o && (lane1_source_id_o != SRC_NONE)) begin
                source_accept_mask_o[lane1_source_id_o] =
                    wrapper_source_accept_mask_i[1] && wrapper_source_clear_mask_i[1];
            end
        end

        source_clear_mask_o = source_accept_mask_o | source_drop_mask_o;
    end

endmodule
