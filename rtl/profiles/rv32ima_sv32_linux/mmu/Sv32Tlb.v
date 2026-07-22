`timescale 1ns / 1ps

// Small fully-associative Sv32 TLB.
//
// This module only matches VPNs, generates physical addresses, and stores the
// leaf PTE for the bridge to run the same permission checks as the PTW path.
// It intentionally uses reg arrays / parallel compare instead of BRAM.
module Sv32Tlb #(
    parameter ENTRY_COUNT = 16
) (
    input clk,
    input rst_n,
    input flush_all,

    input lookup_valid,
    input [31:0] lookup_vaddr,
    output reg lookup_hit,
    output reg [31:0] lookup_paddr,
    output reg [31:0] lookup_pte,
    output reg lookup_level,

    input refill_valid,
    input [31:0] refill_vaddr,
    input [31:0] refill_pte,
    input refill_level
);
    reg entry_valid [0:ENTRY_COUNT-1];
    reg entry_level [0:ENTRY_COUNT-1];
    reg [9:0] entry_vpn1 [0:ENTRY_COUNT-1];
    reg [9:0] entry_vpn0 [0:ENTRY_COUNT-1];
    reg [31:0] entry_pte [0:ENTRY_COUNT-1];

    integer rr_ptr;
    integer i;

    wire [9:0] lookup_vpn1 = lookup_vaddr[31:22];
    wire [9:0] lookup_vpn0 = lookup_vaddr[21:12];
    wire [9:0] refill_vpn1 = refill_vaddr[31:22];
    wire [9:0] refill_vpn0 = refill_vaddr[21:12];

    function automatic entry_matches;
        input valid;
        input level;
        input [9:0] ent_vpn1;
        input [9:0] ent_vpn0;
        input [9:0] req_vpn1;
        input [9:0] req_vpn0;
        begin
            entry_matches = valid && (ent_vpn1 == req_vpn1) &&
                (level || (ent_vpn0 == req_vpn0));
        end
    endfunction

    function automatic [31:0] paddr_from_pte;
        input [31:0] pte;
        input level;
        input [31:0] vaddr;
        reg [33:0] addr34;
        begin
            addr34 = 34'b0;
            if (level) begin
                addr34 = {pte[31:20], vaddr[21:0]};
            end else begin
                addr34 = {pte[31:10], vaddr[11:0]};
            end
            paddr_from_pte = addr34[31:0];
        end
    endfunction

    always @(*) begin
        lookup_hit = 1'b0;
        lookup_paddr = 32'b0;
        lookup_pte = 32'b0;
        lookup_level = 1'b0;

        if (lookup_valid) begin
            for (i = 0; i < ENTRY_COUNT; i = i + 1) begin
                if (!lookup_hit &&
                    entry_matches(entry_valid[i], entry_level[i],
                        entry_vpn1[i], entry_vpn0[i], lookup_vpn1, lookup_vpn0)) begin
                    lookup_hit = 1'b1;
                    lookup_pte = entry_pte[i];
                    lookup_level = entry_level[i];
                    lookup_paddr = paddr_from_pte(entry_pte[i], entry_level[i], lookup_vaddr);
                end
            end
        end
    end

    reg refill_match_found;
    integer refill_match_idx;
    reg refill_invalid_found;
    integer refill_invalid_idx;
    integer refill_idx;

    always @(*) begin
        refill_match_found = 1'b0;
        refill_match_idx = 0;
        refill_invalid_found = 1'b0;
        refill_invalid_idx = 0;
        refill_idx = rr_ptr;

        for (i = 0; i < ENTRY_COUNT; i = i + 1) begin
            if (!refill_match_found &&
                entry_matches(entry_valid[i], entry_level[i],
                    entry_vpn1[i], entry_vpn0[i], refill_vpn1, refill_vpn0)) begin
                refill_match_found = 1'b1;
                refill_match_idx = i;
            end
            if (!refill_invalid_found && !entry_valid[i]) begin
                refill_invalid_found = 1'b1;
                refill_invalid_idx = i;
            end
        end

        if (refill_match_found) begin
            refill_idx = refill_match_idx;
        end else if (refill_invalid_found) begin
            refill_idx = refill_invalid_idx;
        end
    end

    always @(posedge clk) begin
        if (!rst_n || flush_all) begin
            rr_ptr <= 0;
            for (i = 0; i < ENTRY_COUNT; i = i + 1) begin
                entry_valid[i] <= 1'b0;
                entry_level[i] <= 1'b0;
                entry_vpn1[i] <= 10'b0;
                entry_vpn0[i] <= 10'b0;
                entry_pte[i] <= 32'b0;
            end
        end else if (refill_valid) begin
            entry_valid[refill_idx] <= 1'b1;
            entry_level[refill_idx] <= refill_level;
            entry_vpn1[refill_idx] <= refill_vpn1;
            entry_vpn0[refill_idx] <= refill_vpn0;
            entry_pte[refill_idx] <= refill_pte;

            if (refill_idx == ENTRY_COUNT - 1) begin
                rr_ptr <= 0;
            end else begin
                rr_ptr <= refill_idx + 1;
            end
        end
    end
endmodule
