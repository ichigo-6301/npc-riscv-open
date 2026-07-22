`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module bbus_ooo_freelist (
    input  logic clk,
    input  logic reset,

    input  logic [1:0] alloc_fire_mask_i,
    output bbus_ooo_phys_reg_t alloc_phys0_o,
    output bbus_ooo_phys_reg_t alloc_phys1_o,
    output logic [1:0] alloc_avail_count_o,

    input  logic release0_valid_i,
    input  bbus_ooo_phys_reg_t release0_phys_i,
    input  logic release1_valid_i,
    input  bbus_ooo_phys_reg_t release1_phys_i,

    output logic [6:0] debug_free_count_o,
    output bbus_ooo_phys_reg_t debug_next_phys_o
);
    bbus_ooo_phys_reg_t queue_q [`BBUS_OOO_PHYS_REGS-1:0];
    logic [5:0] head_q;
    logic [5:0] tail_q;
    logic [6:0] count_q;

    function automatic [5:0] bump(input [5:0] ptr, input [1:0] inc);
        begin
            bump = ptr + {4'b0, inc};
        end
    endfunction

    function automatic [1:0] pop_count(input logic [1:0] mask);
        begin
            pop_count = {1'b0, mask[0]} + {1'b0, mask[1]};
        end
    endfunction

    wire [5:0] head_plus_one = bump(head_q, 2'd1);
    wire [1:0] release_count =
        {1'b0, (release0_valid_i && (release0_phys_i != `BBUS_OOO_PHYS_ZERO))} +
        {1'b0, (release1_valid_i && (release1_phys_i != `BBUS_OOO_PHYS_ZERO))};

    assign alloc_phys0_o = (count_q != 7'd0) ? queue_q[head_q] : `BBUS_OOO_PHYS_ZERO;
    assign alloc_phys1_o = (count_q > 7'd1) ? queue_q[head_plus_one] : `BBUS_OOO_PHYS_ZERO;
    assign alloc_avail_count_o = (count_q >= 7'd2) ? 2'd2 : count_q[1:0];
    assign debug_free_count_o = count_q;
    assign debug_next_phys_o = alloc_phys0_o;

    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            head_q <= 6'd0;
            tail_q <= 6'd32;
            count_q <= 7'd32;
            for (i = 0; i < `BBUS_OOO_PHYS_REGS; i = i + 1) begin
                if (i < 32) begin
                    queue_q[i] <= bbus_ooo_phys_reg_t'(i + 32);
                end else begin
                    queue_q[i] <= bbus_ooo_phys_reg_t'(i);
                end
            end
        end else begin
            logic [1:0] alloc_count;
            logic [5:0] tail_after_release0;

            alloc_count = pop_count(alloc_fire_mask_i);
            head_q <= bump(head_q, alloc_count);
            count_q <= count_q - {5'b0, alloc_count} + {5'b0, release_count};

            tail_after_release0 = tail_q;
            if (release0_valid_i && (release0_phys_i != `BBUS_OOO_PHYS_ZERO)) begin
                queue_q[tail_q] <= release0_phys_i;
                tail_after_release0 = bump(tail_q, 2'd1);
            end
            if (release1_valid_i && (release1_phys_i != `BBUS_OOO_PHYS_ZERO)) begin
                queue_q[tail_after_release0] <= release1_phys_i;
            end
            tail_q <= bump(tail_q, release_count);
        end
    end
endmodule
