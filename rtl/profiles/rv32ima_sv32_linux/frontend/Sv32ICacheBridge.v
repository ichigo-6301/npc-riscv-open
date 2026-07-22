`timescale 1ns / 1ps

`ifndef NPC_HAS_MMU
`define NPC_HAS_MMU 1
`endif
`ifndef NPC_HAS_ITLB
`define NPC_HAS_ITLB 1
`endif
`ifndef NPC_ITLB_ENTRIES
`define NPC_ITLB_ENTRIES 16
`endif

// Sv32 instruction-side translation bridge.
//
// IF keeps PCs as virtual addresses. This bridge walks Sv32 page tables for
// S/U-mode fetches and forwards the translated physical address to ICache.
module Sv32ICacheBridge (
    input clk,
    input rst_n,
    input flush,
    input tlb_flush_all,

    input cpu_req_valid,
    output cpu_req_ready,
    input [31:0] cpu_req_vaddr,

    input [1:0] priv_i,
    input [31:0] satp_i,

    output reg cpu_resp_valid,
    input cpu_resp_ready,
    output reg [31:0] cpu_resp_rdata,
    output reg cpu_resp_exc_valid,
    output reg [31:0] cpu_resp_exc_cause,
    output reg [31:0] cpu_resp_exc_tval,

    output lower_req_valid,
    input lower_req_ready,
    output [31:0] lower_req_addr,
    input lower_resp_valid,
    output lower_resp_ready,
    input [31:0] lower_resp_rdata,

    output reg [63:0] stat_req_count,
    output reg [63:0] stat_bypass_count,
    output reg [63:0] stat_translate_count,
    output reg [63:0] stat_ptw_cycle_count,
    output reg [63:0] stat_ptw_l1_read_count,
    output reg [63:0] stat_ptw_l0_read_count,
    output reg [63:0] stat_page_fault_count,
    output reg [63:0] stat_ptw_walk_start_count,
    output reg [63:0] stat_ptw_walk_done_count,
    output reg [63:0] stat_ptw_walk_fault_count,
    output reg [63:0] stat_tlb_hit_count,
    output reg [63:0] stat_tlb_miss_count,
    output reg [63:0] stat_tlb_hit_to_cache_req_cycle,
    output reg [63:0] stat_cache_req_wait_cycle,
    output reg [63:0] stat_cache_resp_wait_cycle,
    output reg [63:0] stat_bridge_state_wait_cycle,
    output reg [63:0] stat_fetch_req_count,
    output reg [63:0] stat_fetch_resp_count
);
    localparam [1:0] PRIV_M = 2'b11;

    localparam [2:0] S_IDLE      = 3'd0;
    localparam [2:0] S_PTW_REQ   = 3'd1;
    localparam [2:0] S_PTW_WAIT  = 3'd2;
    localparam [2:0] S_FETCH_REQ = 3'd3;
    localparam [2:0] S_FETCH_WAIT = 3'd4;
    localparam [2:0] S_RESP      = 3'd5;

    reg [2:0] state;
    reg drop_resp_r;
    reg [31:0] req_vaddr_r;
    reg [31:0] ptw_addr_r;
    reg [9:0] ptw_vpn0_r;
    reg [31:0] phys_addr_r;
    reg walk_level_r; // 1 -> first level, 0 -> second level
    reg req_from_tlb_hit_r;

    wire req_fire = cpu_req_valid && cpu_req_ready;
    wire resp_fire = cpu_resp_valid && cpu_resp_ready;
    wire lower_req_fire = lower_req_valid && lower_req_ready;
    wire lower_resp_fire = lower_resp_valid && lower_resp_ready;
    wire req_translate_normal = (`NPC_HAS_MMU != 0) && satp_i[31] && (priv_i != PRIV_M);
`ifdef NPC_FORCE_MMU_BYPASS
    wire req_translate = 1'b0;
`elsif NPC_FORCE_MMU_TRANSLATE
    wire req_translate = satp_i[31];
`else
    wire req_translate = req_translate_normal;
`endif
    wire itlb_enabled = (`NPC_HAS_ITLB != 0);
    wire itlb_lookup_valid = req_fire && req_translate && itlb_enabled;
    wire itlb_lookup_hit;
    wire [31:0] itlb_lookup_paddr;
    wire [31:0] itlb_lookup_pte;
    wire itlb_lookup_level;

    function [31:0] make_pte_addr;
        input [31:0] base;
        input [31:0] vpn;
        begin
            make_pte_addr = base + {20'b0, vpn[9:0], 2'b00};
        end
    endfunction

    function [31:0] make_pte_base;
        input [31:0] pte;
        reg [33:0] base34;
        begin
            base34 = {pte[31:10], 12'b0};
            make_pte_base = base34[31:0];
        end
    endfunction

    function [31:0] make_satp_base;
        input [31:0] satp;
        reg [33:0] base34;
        begin
            base34 = {satp[21:0], 12'b0};
            make_satp_base = base34[31:0];
        end
    endfunction

    function [31:0] make_phys_addr;
        input [31:0] pte;
        input [9:0] vpn0;
        input [11:0] offset;
        reg [33:0] addr34;
        begin
            addr34 = {pte[31:20], vpn0, offset};
            make_phys_addr = addr34[31:0];
        end
    endfunction

    function fetch_perm_ok;
        input [1:0] cur_priv;
        input [31:0] pte;
        begin
            fetch_perm_ok = pte[6] && pte[3] &&
                ((cur_priv == 2'b00) ? pte[4] : !pte[4]);
        end
    endfunction

    wire [31:0] pte_word = lower_resp_rdata;
    wire pte_v = pte_word[0];
    wire pte_r_bit = pte_word[1];
    wire pte_w_bit = pte_word[2];
    wire pte_x_bit = pte_word[3];
    wire pte_leaf = pte_word[1] || pte_word[3];
    wire pte_invalid = !pte_v || (!pte_r_bit && pte_w_bit);
    wire pte_superpage_misaligned =
        (walk_level_r == 1'b1) && (pte_word[19:10] != 10'b0);
    wire pte_perm_ok = fetch_perm_ok(priv_i, pte_word);
    wire itlb_perm_ok = fetch_perm_ok(priv_i, itlb_lookup_pte);
    wire itlb_refill_valid =
        itlb_enabled && (state == S_PTW_WAIT) && lower_resp_fire &&
        !pte_invalid && pte_leaf && !pte_superpage_misaligned && pte_perm_ok;

    Sv32Tlb #(
        .ENTRY_COUNT(`NPC_ITLB_ENTRIES)
    ) u_itlb (
        .clk(clk),
        .rst_n(rst_n),
        .flush_all(tlb_flush_all),
        .lookup_valid(itlb_lookup_valid),
        .lookup_vaddr(cpu_req_vaddr),
        .lookup_hit(itlb_lookup_hit),
        .lookup_paddr(itlb_lookup_paddr),
        .lookup_pte(itlb_lookup_pte),
        .lookup_level(itlb_lookup_level),
        .refill_valid(itlb_refill_valid),
        .refill_vaddr(req_vaddr_r),
        .refill_pte(pte_word),
        .refill_level(walk_level_r)
    );

`ifdef NPC_ICACHE_MMU_DEBUG
    integer dbg_cycle;
    always @(posedge clk) begin
        if (!rst_n) begin
            dbg_cycle <= 0;
        end else if (dbg_cycle < 300) begin
            dbg_cycle <= dbg_cycle + 1;
            if (cpu_req_valid || cpu_resp_valid || lower_req_valid || lower_resp_valid || state != S_IDLE) begin
                $display("[icmmu] cyc=%0d st=%0d drop=%0d priv=%0d satp=%08x cpu_v=%0d cpu_r=%0d vaddr=%08x resp_v=%0d resp_r=%0d lower_v=%0d lower_r=%0d lower_addr=%08x lower_resp_v=%0d lower_resp_r=%0d lower_data=%08x",
                    dbg_cycle, state, drop_resp_r, priv_i, satp_i,
                    cpu_req_valid, cpu_req_ready, cpu_req_vaddr,
                    cpu_resp_valid, cpu_resp_ready,
                    lower_req_valid, lower_req_ready, lower_req_addr,
                    lower_resp_valid, lower_resp_ready, lower_resp_rdata);
            end
        end
    end
`endif

    assign cpu_req_ready = (state == S_IDLE) && !cpu_resp_valid && !drop_resp_r;
    assign lower_req_valid = (state == S_PTW_REQ) || (state == S_FETCH_REQ);
    assign lower_req_addr =
        (state == S_PTW_REQ) ? ptw_addr_r :
        (state == S_FETCH_REQ) ? phys_addr_r :
        32'b0;
    assign lower_resp_ready = drop_resp_r || (state == S_PTW_WAIT) || (state == S_FETCH_WAIT);

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
            drop_resp_r <= 1'b0;
            req_vaddr_r <= 32'b0;
            ptw_addr_r <= 32'b0;
            ptw_vpn0_r <= 10'b0;
            phys_addr_r <= 32'b0;
            walk_level_r <= 1'b0;
            cpu_resp_valid <= 1'b0;
            cpu_resp_rdata <= 32'b0;
            cpu_resp_exc_valid <= 1'b0;
            cpu_resp_exc_cause <= 32'b0;
            cpu_resp_exc_tval <= 32'b0;
            stat_req_count <= 64'd0;
            stat_bypass_count <= 64'd0;
            stat_translate_count <= 64'd0;
            stat_ptw_cycle_count <= 64'd0;
            stat_ptw_l1_read_count <= 64'd0;
            stat_ptw_l0_read_count <= 64'd0;
            stat_page_fault_count <= 64'd0;
            stat_ptw_walk_start_count <= 64'd0;
            stat_ptw_walk_done_count <= 64'd0;
            stat_ptw_walk_fault_count <= 64'd0;
            stat_tlb_hit_count <= 64'd0;
            stat_tlb_miss_count <= 64'd0;
            stat_tlb_hit_to_cache_req_cycle <= 64'd0;
            stat_cache_req_wait_cycle <= 64'd0;
            stat_cache_resp_wait_cycle <= 64'd0;
            stat_bridge_state_wait_cycle <= 64'd0;
            stat_fetch_req_count <= 64'd0;
            stat_fetch_resp_count <= 64'd0;
            req_from_tlb_hit_r <= 1'b0;
        end else begin
            if ((state == S_PTW_REQ) || (state == S_PTW_WAIT)) begin
                stat_ptw_cycle_count <= stat_ptw_cycle_count + 64'd1;
            end

            if ((state == S_FETCH_REQ) || (state == S_FETCH_WAIT) || (state == S_RESP)) begin
                stat_bridge_state_wait_cycle <= stat_bridge_state_wait_cycle + 64'd1;
            end
            if ((state == S_FETCH_REQ) && !lower_req_ready) begin
                stat_cache_req_wait_cycle <= stat_cache_req_wait_cycle + 64'd1;
            end
            if ((state == S_FETCH_WAIT) && !lower_resp_valid) begin
                stat_cache_resp_wait_cycle <= stat_cache_resp_wait_cycle + 64'd1;
            end
            if ((state == S_FETCH_REQ) && req_from_tlb_hit_r && !lower_req_fire) begin
                stat_tlb_hit_to_cache_req_cycle <= stat_tlb_hit_to_cache_req_cycle + 64'd1;
            end

            if (lower_req_fire && (state == S_PTW_REQ)) begin
                if (walk_level_r) begin
                    stat_ptw_l1_read_count <= stat_ptw_l1_read_count + 64'd1;
                end else begin
                    stat_ptw_l0_read_count <= stat_ptw_l0_read_count + 64'd1;
                end
            end
            if (lower_req_fire && (state == S_FETCH_REQ)) begin
                stat_fetch_req_count <= stat_fetch_req_count + 64'd1;
                req_from_tlb_hit_r <= 1'b0;
            end
            if (lower_resp_fire && (state == S_FETCH_WAIT)) begin
                stat_fetch_resp_count <= stat_fetch_resp_count + 64'd1;
            end

            if (resp_fire) begin
                cpu_resp_valid <= 1'b0;
                cpu_resp_exc_valid <= 1'b0;
            end

            if (flush) begin
                cpu_resp_valid <= 1'b0;
                cpu_resp_rdata <= 32'b0;
                cpu_resp_exc_valid <= 1'b0;
                state <= S_IDLE;
                req_from_tlb_hit_r <= 1'b0;
                if (lower_req_fire || (state == S_PTW_WAIT) || (state == S_FETCH_WAIT)) begin
                    drop_resp_r <= !lower_resp_fire;
                end else if (drop_resp_r && lower_resp_fire) begin
                    drop_resp_r <= 1'b0;
                end
            end else begin
                if (drop_resp_r && lower_resp_fire) begin
                    drop_resp_r <= 1'b0;
                end

                case (state)
                    S_IDLE: begin
                        if (req_fire) begin
                            stat_req_count <= stat_req_count + 64'd1;
                            req_vaddr_r <= cpu_req_vaddr;
                            cpu_resp_rdata <= 32'b0;
                            cpu_resp_exc_valid <= 1'b0;
                            if (!req_translate) begin
                                stat_bypass_count <= stat_bypass_count + 64'd1;
                                phys_addr_r <= cpu_req_vaddr;
                                req_from_tlb_hit_r <= 1'b0;
                                state <= S_FETCH_REQ;
                            end else if (itlb_enabled && itlb_lookup_hit) begin
                                stat_translate_count <= stat_translate_count + 64'd1;
                                stat_tlb_hit_count <= stat_tlb_hit_count + 64'd1;
                                if (!itlb_perm_ok) begin
                                    cpu_resp_valid <= 1'b1;
                                    cpu_resp_rdata <= 32'h00000000;
                                    cpu_resp_exc_valid <= 1'b1;
                                    cpu_resp_exc_cause <= 32'd12;
                                    cpu_resp_exc_tval <= cpu_req_vaddr;
                                    stat_page_fault_count <= stat_page_fault_count + 64'd1;
                                    state <= S_RESP;
                                end else begin
                                    phys_addr_r <= itlb_lookup_paddr;
                                    req_from_tlb_hit_r <= 1'b1;
                                    state <= S_FETCH_REQ;
                                end
                            end else begin
                                stat_translate_count <= stat_translate_count + 64'd1;
                                if (itlb_enabled) begin
                                    stat_tlb_miss_count <= stat_tlb_miss_count + 64'd1;
                                end
                                stat_ptw_walk_start_count <= stat_ptw_walk_start_count + 64'd1;
                                ptw_vpn0_r <= cpu_req_vaddr[21:12];
                                walk_level_r <= 1'b1;
                                ptw_addr_r <= make_pte_addr(make_satp_base(satp_i), {22'b0, cpu_req_vaddr[31:22]});
                                state <= S_PTW_REQ;
                            end
                        end
                    end

                    S_PTW_REQ: begin
                        if (lower_req_fire) state <= S_PTW_WAIT;
                    end

                    S_PTW_WAIT: begin
                        if (lower_resp_fire) begin
                            if (pte_invalid) begin
                                cpu_resp_valid <= 1'b1;
                                cpu_resp_rdata <= 32'h00000000;
                                cpu_resp_exc_valid <= 1'b1;
                                cpu_resp_exc_cause <= 32'd12;
                                cpu_resp_exc_tval <= req_vaddr_r;
                                stat_page_fault_count <= stat_page_fault_count + 64'd1;
                                stat_ptw_walk_fault_count <= stat_ptw_walk_fault_count + 64'd1;
                                state <= S_RESP;
                            end else if (pte_leaf) begin
                                if (pte_superpage_misaligned || !pte_perm_ok) begin
                                    cpu_resp_valid <= 1'b1;
                                    cpu_resp_rdata <= 32'h00000000;
                                    cpu_resp_exc_valid <= 1'b1;
                                    cpu_resp_exc_cause <= 32'd12;
                                    cpu_resp_exc_tval <= req_vaddr_r;
                                    stat_page_fault_count <= stat_page_fault_count + 64'd1;
                                    stat_ptw_walk_fault_count <= stat_ptw_walk_fault_count + 64'd1;
                                    state <= S_RESP;
                                end else begin
                                    if (walk_level_r == 1'b1) begin
                                        phys_addr_r <= make_phys_addr(pte_word, ptw_vpn0_r, req_vaddr_r[11:0]);
                                    end else begin
                                        phys_addr_r <= make_phys_addr(pte_word, pte_word[19:10], req_vaddr_r[11:0]);
                                    end
                                    stat_ptw_walk_done_count <= stat_ptw_walk_done_count + 64'd1;
                                    req_from_tlb_hit_r <= 1'b0;
                                    state <= S_FETCH_REQ;
                                end
                            end else begin
                                if (walk_level_r == 1'b0) begin
                                    cpu_resp_valid <= 1'b1;
                                    cpu_resp_rdata <= 32'h00000000;
                                    cpu_resp_exc_valid <= 1'b1;
                                    cpu_resp_exc_cause <= 32'd12;
                                    cpu_resp_exc_tval <= req_vaddr_r;
                                    stat_page_fault_count <= stat_page_fault_count + 64'd1;
                                    stat_ptw_walk_fault_count <= stat_ptw_walk_fault_count + 64'd1;
                                    state <= S_RESP;
                                end else begin
                                    walk_level_r <= 1'b0;
                                    ptw_addr_r <= make_pte_addr(make_pte_base(pte_word), {22'b0, ptw_vpn0_r});
                                    state <= S_PTW_REQ;
                                end
                            end
                        end
                    end

                    S_FETCH_REQ: begin
                        if (lower_req_fire) state <= S_FETCH_WAIT;
                    end

                    S_FETCH_WAIT: begin
                        if (lower_resp_fire) begin
                            cpu_resp_valid <= 1'b1;
                            cpu_resp_rdata <= lower_resp_rdata;
                            cpu_resp_exc_valid <= 1'b0;
                            state <= S_RESP;
                        end
                    end

                    S_RESP: begin
                        if (resp_fire) state <= S_IDLE;
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end
endmodule
