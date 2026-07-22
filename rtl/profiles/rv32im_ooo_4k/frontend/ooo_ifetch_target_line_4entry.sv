`timescale 1ns / 1ps

// Configurable set-associative cache for already validated 64-bit instruction
// pairs. Ownership, faults, and refill ordering remain outside this block.
module ooo_ifetch_target_line_4entry #(
    parameter bit ENABLE = 1'b0,
    parameter bit SECOND_LOOKUP_ENABLE = 1'b0,
    parameter int unsigned ENTRY_COUNT = 4,
    parameter int unsigned WAY_COUNT = 1,
    localparam int unsigned SET_COUNT = ENTRY_COUNT / WAY_COUNT,
    localparam int unsigned SET_INDEX_W =
        (SET_COUNT > 1) ? $clog2(SET_COUNT) : 1,
    localparam int unsigned WAY_INDEX_W =
        (WAY_COUNT > 1) ? $clog2(WAY_COUNT) : 1
) (
    input  logic clk,
    input  logic reset,
    input  logic invalidate_i,

    input  logic lookup_valid_i,
    input  logic [31:0] lookup_addr_i,
    output logic lookup_hit_o,
    output logic lookup_entry_valid_o,
    output logic [63:0] lookup_data_o,

    input  logic lookup1_valid_i,
    input  logic [31:0] lookup1_addr_i,
    output logic lookup1_hit_o,
    output logic lookup1_entry_valid_o,
    output logic [63:0] lookup1_data_o,

    input  logic fill_valid_i,
    input  logic [31:0] fill_addr_i,
    input  logic [63:0] fill_data_i
);
    logic valid_q [0:ENTRY_COUNT-1];
    logic [28:0] line_addr_q [0:ENTRY_COUNT-1];
    logic [63:0] data_q [0:ENTRY_COUNT-1];
    logic [WAY_INDEX_W-1:0] next_replace_q [0:SET_COUNT-1];
    logic [SET_INDEX_W-1:0] lookup_set_c, lookup1_set_c, fill_set_c;
    logic [WAY_INDEX_W-1:0] fill_way_c;
    logic fill_match_c, fill_invalid_c;

    generate
        if (SET_COUNT == 1) begin : gen_single_set
            assign lookup_set_c = '0;
            assign lookup1_set_c = '0;
            assign fill_set_c = '0;
        end else begin : gen_indexed_sets
            assign lookup_set_c =
                lookup_addr_i[SET_INDEX_W+2:3];
            assign lookup1_set_c =
                lookup1_addr_i[SET_INDEX_W+2:3];
            assign fill_set_c = fill_addr_i[SET_INDEX_W+2:3];
        end
    endgenerate

    integer lookup_way_i;
    integer lookup_entry_i;
    always_comb begin
        lookup_entry_valid_o = 1'b0;
        lookup_hit_o = 1'b0;
        lookup_data_o = 64'b0;
        lookup_entry_i = 0;
        if (ENABLE && lookup_valid_i && !invalidate_i) begin
            for (lookup_way_i = 0; lookup_way_i < WAY_COUNT;
                 lookup_way_i = lookup_way_i + 1) begin
                lookup_entry_i = (lookup_set_c * WAY_COUNT) + lookup_way_i;
                if (valid_q[lookup_entry_i]) begin
                    lookup_entry_valid_o = 1'b1;
                    if (!lookup_hit_o &&
                        (line_addr_q[lookup_entry_i] == lookup_addr_i[31:3])) begin
                        lookup_hit_o = 1'b1;
                        lookup_data_o = data_q[lookup_entry_i];
                    end
                end
            end
        end
    end

    integer lookup1_way_i;
    integer lookup1_entry_i;
    always_comb begin
        lookup1_entry_valid_o = 1'b0;
        lookup1_hit_o = 1'b0;
        lookup1_data_o = 64'b0;
        lookup1_entry_i = 0;
        if (ENABLE && SECOND_LOOKUP_ENABLE && lookup1_valid_i &&
            !invalidate_i) begin
            for (lookup1_way_i = 0; lookup1_way_i < WAY_COUNT;
                 lookup1_way_i = lookup1_way_i + 1) begin
                lookup1_entry_i =
                    (lookup1_set_c * WAY_COUNT) + lookup1_way_i;
                if (valid_q[lookup1_entry_i]) begin
                    lookup1_entry_valid_o = 1'b1;
                    if (!lookup1_hit_o &&
                        (line_addr_q[lookup1_entry_i] ==
                         lookup1_addr_i[31:3])) begin
                        lookup1_hit_o = 1'b1;
                        lookup1_data_o = data_q[lookup1_entry_i];
                    end
                end
            end
        end
    end

    integer fill_way_i;
    integer fill_entry_i;
    always_comb begin
        fill_way_c = next_replace_q[fill_set_c];
        fill_match_c = 1'b0;
        fill_invalid_c = 1'b0;
        fill_entry_i = 0;
        for (fill_way_i = 0; fill_way_i < WAY_COUNT;
             fill_way_i = fill_way_i + 1) begin
            fill_entry_i = (fill_set_c * WAY_COUNT) + fill_way_i;
            if (!fill_match_c && valid_q[fill_entry_i] &&
                (line_addr_q[fill_entry_i] == fill_addr_i[31:3])) begin
                fill_way_c = fill_way_i;
                fill_match_c = 1'b1;
            end
        end
        for (fill_way_i = 0; fill_way_i < WAY_COUNT;
             fill_way_i = fill_way_i + 1) begin
            fill_entry_i = (fill_set_c * WAY_COUNT) + fill_way_i;
            if (!fill_match_c && !fill_invalid_c &&
                !valid_q[fill_entry_i]) begin
                fill_way_c = fill_way_i;
                fill_invalid_c = 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (reset || invalidate_i) begin
            valid_q <= '{default: 1'b0};
            line_addr_q <= '{default: '0};
            data_q <= '{default: '0};
            next_replace_q <= '{default: '0};
        end else if (ENABLE && fill_valid_i) begin
            valid_q[(fill_set_c * WAY_COUNT) + fill_way_c] <= 1'b1;
            line_addr_q[(fill_set_c * WAY_COUNT) + fill_way_c] <=
                fill_addr_i[31:3];
            data_q[(fill_set_c * WAY_COUNT) + fill_way_c] <= fill_data_i;
            if ((WAY_COUNT > 1) && !fill_match_c) begin
                if (fill_way_c == WAY_COUNT - 1)
                    next_replace_q[fill_set_c] <= '0;
                else
                    next_replace_q[fill_set_c] <= fill_way_c + 1'b1;
            end
        end
    end
endmodule
