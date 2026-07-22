`timescale 1ns / 1ps

`ifndef NPC_HAS_MMU
`define NPC_HAS_MMU 1
`endif
`ifndef NPC_HAS_DTLB
`define NPC_HAS_DTLB 1
`endif
`ifndef NPC_DTLB_ENTRIES
`define NPC_DTLB_ENTRIES 16
`endif

// Sv32 data-side translation + DCache bridge.
//
// The bridge accepts a virtual-address request from mem_stage, walks page
// tables through the physical DCache port when Sv32 is enabled, and then
// forwards the translated physical request to DCache. Page faults are returned
// back to mem_stage as a response sideband so the existing commit-side trap
// path can stay untouched.
module Sv32DCacheBridge (
    input clk,
    input rst_n,
    input flush,
    input tlb_flush_all,

    input cpu_req_valid,
    output cpu_req_ready,
    input cpu_req_write,
    input cpu_req_atomic,
    input cpu_req_store_bufferable,
    input [31:0] cpu_req_vaddr,
    input [31:0] cpu_req_wdata,
    input [3:0] cpu_req_wstrb,
    input [2:0] cpu_req_len,

    input [1:0] priv_i,
    input [31:0] mstatus_i,
    input [31:0] satp_i,

    output reg cpu_resp_valid,
    input cpu_resp_ready,
    output reg [31:0] cpu_resp_rdata,
    output reg cpu_resp_exc_valid,
    output reg [31:0] cpu_resp_exc_cause,
    output reg [31:0] cpu_resp_exc_tval,

    output lower_req_valid,
    input lower_req_ready,
    output lower_req_write,
    output [31:0] lower_req_addr,
    output [31:0] lower_req_wdata,
    output [3:0] lower_req_wstrb,
    output [2:0] lower_req_len,
    output lower_req_is_ptw,
    input lower_resp_valid,
    output lower_resp_ready,
    input [31:0] lower_resp_rdata,

    output dtlb_refill_valid_o,
    output [31:0] dtlb_refill_vaddr_o,
    output [31:0] dtlb_refill_pte_o,
    output dtlb_refill_level_o,

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
    output reg [63:0] stat_data_req_count,
    output reg [63:0] stat_data_resp_count,
    output reg [63:0] stat_uncached_req_count,

    output store_buffer_empty,
    output store_buffer_busy,
    output reg [63:0] stat_sbuf_enqueue,
    output reg [63:0] stat_sbuf_dequeue,
    output reg [63:0] stat_sbuf_full_stall,
    output reg [63:0] stat_sbuf_drain_req,
    output reg [63:0] stat_sbuf_drain_resp,
    output reg [63:0] stat_sbuf_drain_wait,
    output reg [63:0] stat_sbuf_load_forward,
    output reg [63:0] stat_sbuf_load_stall_conflict,
    output reg [63:0] stat_sbuf_load_stall_buffer_nonempty,
    output reg [63:0] stat_sbuf_fence_drain_wait,
    output reg [63:0] stat_sbuf_uncached_drain_wait,
    output reg [63:0] stat_sbuf_killed_store_block,
    output reg [63:0] stat_sbuf_occupancy0,
    output reg [63:0] stat_sbuf_occupancy1,
    output reg [63:0] stat_sbuf_occupancy2,
    output reg [63:0] stat_sbuf_max_occupancy,
    output reg [63:0] stat_sbuf_enqueue_occ0,
    output reg [63:0] stat_sbuf_enqueue_occ1,
    output reg [63:0] stat_sbuf_enqueue_full,
    output reg [63:0] stat_dhitopt_candidate,
    output reg [63:0] stat_dhitopt_success,
    output reg [63:0] stat_dhitopt_fallback,
    output reg [63:0] stat_dhitopt_block_store_buffer,
    output reg [63:0] stat_dhitopt_block_uncached,
    output reg [63:0] stat_dhitopt_block_fault,
    output reg [63:0] stat_dhitopt_block_miss,
    output reg [63:0] stat_dhitopt_block_alignment,
    output reg [63:0] stat_dhitopt_unknown,

    output [2:0] dbg_state,
    output dbg_drop_resp,
    output dbg_req_write,
    output dbg_req_store_bufferable,
    output dbg_req_safe_store_bufferable,
    output dbg_sbuf0_valid,
    output dbg_sbuf1_valid,
    output dbg_sbuf0_sent,
    output dbg_sbuf1_sent,
    output dbg_sbuf_drain_active,
    output dbg_sbuf_drain_resp_pending,
    output dbg_sbuf_drain_req_valid,
    output dbg_sbuf_drain_grant,
    output dbg_sbuf_drain_req_fire,
    output dbg_sbuf_drain_resp_fire,
    output dbg_data_req_fire,
    output dbg_lower_resp_ready,
    output dbg_lower_req_valid,
    output dbg_lower_req_write,
    output [31:0] dbg_lower_req_addr,
    output dbg_sbuf_conflict_stall,
    output dbg_req_store_buffer_full,
    output dbg_sbuf_forward_hit
);
    localparam [1:0] PRIV_U = 2'b00;
    localparam [1:0] PRIV_S = 2'b01;
    localparam [1:0] PRIV_M = 2'b11;

    localparam [2:0] S_IDLE      = 3'd0;
    localparam [2:0] S_PTW_REQ   = 3'd1;
    localparam [2:0] S_PTW_WAIT  = 3'd2;
    localparam [2:0] S_DATA_REQ  = 3'd3;
    localparam [2:0] S_DATA_WAIT = 3'd4;
    localparam [2:0] S_RESP      = 3'd5;
`ifdef NPC_STORE_BUFFER_ENTRIES
    localparam integer SBUF_ENTRY_COUNT = `NPC_STORE_BUFFER_ENTRIES;
`else
    localparam integer SBUF_ENTRY_COUNT = 2;
`endif
`ifdef NPC_STORE_BUFFER_ENABLE
    localparam SBUF_ENABLE = 1'b1;
`else
    localparam SBUF_ENABLE = 1'b0;
`endif
`ifdef NPC_DCACHE_HIT_OPT
    localparam DCACHE_HIT_OPT_ENABLE = 1'b1;
`else
    localparam DCACHE_HIT_OPT_ENABLE = 1'b0;
`endif

    function [2:0] access_bytes;
        input [2:0] len;
        begin
            case (len)
                3'd4: access_bytes = 3'd4;
                3'd3: access_bytes = 3'd3;
                3'd2: access_bytes = 3'd2;
                default: access_bytes = 3'd1;
            endcase
        end
    endfunction

    function [1:0] effective_priv;
        input [1:0] cur_priv;
        input [31:0] cur_mstatus;
        begin
            effective_priv = cur_priv;
            if (cur_priv == PRIV_M && cur_mstatus[17]) begin
                effective_priv = cur_mstatus[12:11];
            end
        end
    endfunction

    function perm_ok;
        input req_write;
        input [1:0] eff_priv;
        input [31:0] cur_mstatus;
        input [31:0] pte;
        reg allow;
        begin
            allow = 1'b0;
            if (eff_priv == PRIV_M) begin
                allow = 1'b1;
            end else begin
                if (eff_priv == PRIV_U) begin
                    allow = pte[4];
                end else if (eff_priv == PRIV_S) begin
                    allow = !pte[4] || cur_mstatus[18];
                end

                if (allow) begin
                    if (req_write) begin
                        allow = pte[2];
                    end else begin
                        allow = pte[1] || (cur_mstatus[19] && pte[3]);
                    end
                end
            end

            if (allow) begin
                allow = pte[6];
                if (req_write) allow = allow && pte[7];
            end
            perm_ok = allow;
        end
    endfunction

    function [31:0] page_fault_cause;
        input req_write;
        begin
            page_fault_cause = req_write ? 32'd15 : 32'd13;
        end
    endfunction

    wire req_fire = cpu_req_valid && cpu_req_ready;
    wire resp_fire = cpu_resp_valid && cpu_resp_ready;
    wire lower_req_fire = lower_req_valid && lower_req_ready;
    wire lower_resp_fire = lower_resp_valid && lower_resp_ready;

    wire [1:0] req_eff_priv = effective_priv(priv_i, mstatus_i);
    wire req_translate_normal = (`NPC_HAS_MMU != 0) && satp_i[31] && (req_eff_priv != PRIV_M);
`ifdef NPC_FORCE_MMU_BYPASS
    wire req_translate = 1'b0;
`elsif NPC_FORCE_MMU_TRANSLATE
    wire req_translate = satp_i[31];
`else
    wire req_translate = req_translate_normal;
`endif
    wire dtlb_enabled = (`NPC_HAS_DTLB != 0);
    wire [2:0] req_bytes = access_bytes(cpu_req_len);
    wire [12:0] req_end_off = {1'b0, cpu_req_vaddr[11:0]} + {10'b0, req_bytes} - 13'd1;
    wire req_cross_page = req_translate && req_end_off[12];
    wire dtlb_lookup_valid = req_fire && req_translate && !req_cross_page && dtlb_enabled;
    wire dtlb_lookup_hit;
    wire [31:0] dtlb_lookup_paddr;
    wire [31:0] dtlb_lookup_pte;
    wire dtlb_lookup_level;

    reg [2:0] state;
    reg drop_resp_r;

    reg req_write_r;
    reg req_atomic_r;
    reg req_store_bufferable_r;
    reg [31:0] req_vaddr_r;
    reg [31:0] req_wdata_r;
    reg [3:0] req_wstrb_r;
    reg [2:0] req_len_r;
    reg [1:0] req_eff_priv_r;
    reg [31:0] req_mstatus_r;

    reg [31:0] ptw_addr_r;
    reg [9:0] ptw_vpn0_r;
    reg [31:0] phys_addr_r;
    reg walk_level_r; // 1 -> first level, 0 -> second level
    reg req_from_tlb_hit_r;
    reg sbuf0_valid_r;
    reg sbuf1_valid_r;
    reg sbuf0_sent_r;
    reg sbuf1_sent_r;
    reg [31:0] sbuf0_paddr_r;
    reg [31:0] sbuf1_paddr_r;
    reg [31:0] sbuf0_wdata_r;
    reg [31:0] sbuf1_wdata_r;
    reg [3:0] sbuf0_wstrb_r;
    reg [3:0] sbuf1_wstrb_r;
    reg [2:0] sbuf0_len_r;
    reg [2:0] sbuf1_len_r;
    reg sbuf_head_is_1_r;
    reg sbuf_drain_active_r;
    reg dhitopt_active_r;
    reg [3:0] dhitopt_wait_r;

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

    wire [31:0] pte_vaddr = req_vaddr_r;
    wire [31:0] pte_word = lower_resp_rdata;
    wire pte_v = pte_word[0];
    wire pte_r_bit = pte_word[1];
    wire pte_w_bit = pte_word[2];
    wire pte_a_bit = pte_word[6];
    wire pte_d_bit = pte_word[7];
    wire pte_leaf = pte_word[1] || pte_word[3];
    wire pte_invalid = !pte_v || (!pte_r_bit && pte_w_bit);
    wire pte_superpage_misaligned =
        (walk_level_r == 1'b1) && (pte_word[19:10] != 10'b0);
    wire pte_perm_ok = perm_ok(req_write_r, req_eff_priv_r, req_mstatus_r, pte_word);
    wire pte_ad_ok = pte_a_bit && (!req_write_r || pte_d_bit);
    wire dtlb_perm_ok = perm_ok(cpu_req_write, req_eff_priv, mstatus_i, dtlb_lookup_pte);
    wire dtlb_ad_ok = dtlb_lookup_pte[6] && (!cpu_req_write || dtlb_lookup_pte[7]);
    wire dtlb_refill_valid =
        dtlb_enabled && (state == S_PTW_WAIT) && lower_resp_fire &&
        !pte_invalid && pte_leaf && !pte_superpage_misaligned && pte_perm_ok && pte_ad_ok;
    assign dtlb_refill_valid_o = dtlb_refill_valid;
    assign dtlb_refill_vaddr_o = req_vaddr_r;
    assign dtlb_refill_pte_o = pte_word;
    assign dtlb_refill_level_o = walk_level_r;

    function [3:0] load_byte_mask;
        input [31:0] addr;
        input [2:0] len;
        begin
            case (len)
                3'd4: load_byte_mask = 4'b1111;
                3'd2: load_byte_mask = 4'b0011 << addr[1:0];
                default: load_byte_mask = 4'b0001 << addr[1:0];
            endcase
        end
    endfunction

    wire sbuf_any_valid = sbuf0_valid_r || sbuf1_valid_r;
    wire [1:0] sbuf_occupancy =
        {1'b0, sbuf0_valid_r} + {1'b0, sbuf1_valid_r};
    wire sbuf_has_space =
        (SBUF_ENTRY_COUNT <= 1) ? !sbuf0_valid_r : (!sbuf0_valid_r || !sbuf1_valid_r);
    wire sbuf_head_valid = sbuf0_valid_r || sbuf1_valid_r;
    wire sbuf_head_is_1 =
        (SBUF_ENTRY_COUNT > 1) && sbuf1_valid_r && (!sbuf0_valid_r || sbuf_head_is_1_r);
    wire sbuf_head_sent = sbuf_head_is_1 ? sbuf1_sent_r : sbuf0_sent_r;
    wire sbuf_drain_resp_pending =
        SBUF_ENABLE && (sbuf_drain_active_r || (sbuf_head_valid && sbuf_head_sent));
    wire [31:0] sbuf_head_paddr = sbuf_head_is_1 ? sbuf1_paddr_r : sbuf0_paddr_r;
    wire [31:0] sbuf_head_wdata = sbuf_head_is_1 ? sbuf1_wdata_r : sbuf0_wdata_r;
    wire [3:0] sbuf_head_wstrb = sbuf_head_is_1 ? sbuf1_wstrb_r : sbuf0_wstrb_r;
    wire [2:0] sbuf_head_len = sbuf_head_is_1 ? sbuf1_len_r : sbuf0_len_r;
    wire req_uncached = ((phys_addr_r & 32'hf0000000) == 32'ha0000000);
    wire dtlb_load_uncached = ((dtlb_lookup_paddr & 32'hf0000000) == 32'ha0000000);
    wire dtlb_load_aligned =
        ((cpu_req_len == 3'd4) && (cpu_req_vaddr[1:0] == 2'b00)) ||
        ((cpu_req_len == 3'd2) && (cpu_req_vaddr[0] == 1'b0)) ||
        (cpu_req_len == 3'd1);
    wire dhitopt_candidate =
        DCACHE_HIT_OPT_ENABLE && req_fire && req_translate && dtlb_enabled &&
        !cpu_req_write && !req_cross_page && dtlb_lookup_hit &&
        dtlb_perm_ok && dtlb_ad_ok && !flush;
    wire dhitopt_safe_candidate =
        dhitopt_candidate && dtlb_load_aligned && !dtlb_load_uncached &&
        !sbuf_any_valid && !sbuf_drain_resp_pending;
    wire dhitopt_fast_valid = dhitopt_safe_candidate;
    wire dhitopt_fast_fire = dhitopt_fast_valid && lower_req_ready;
    wire req_safe_store_bufferable = SBUF_ENABLE && req_write_r &&
        req_store_bufferable_r && !req_uncached && sbuf_has_space;
    wire req_store_buffer_full = SBUF_ENABLE && req_write_r &&
        req_store_bufferable_r && !req_uncached && !sbuf_has_space;
    wire req_load_can_check_sbuf = SBUF_ENABLE && !req_write_r && sbuf_any_valid && !req_uncached;
    wire [3:0] req_load_mask = load_byte_mask(phys_addr_r, req_len_r);
    wire sbuf0_same_word = sbuf0_valid_r &&
        (sbuf0_paddr_r[31:2] == phys_addr_r[31:2]);
    wire sbuf1_same_word = sbuf1_valid_r &&
        (sbuf1_paddr_r[31:2] == phys_addr_r[31:2]);
    wire [3:0] sbuf0_cover = sbuf0_wstrb_r & req_load_mask;
    wire [3:0] sbuf1_cover = sbuf1_wstrb_r & req_load_mask;
    wire [3:0] sbuf0_mask = sbuf0_same_word ? sbuf0_wstrb_r : 4'b0000;
    wire [3:0] sbuf1_mask = sbuf1_same_word ? sbuf1_wstrb_r : 4'b0000;
    wire [3:0] sbuf_merged_cover = (sbuf0_mask | sbuf1_mask) & req_load_mask;
    wire sbuf_younger_is_1 =
        sbuf0_valid_r && sbuf1_valid_r ? !sbuf_head_is_1_r : sbuf1_valid_r;
    wire [3:0] sbuf_younger_mask = sbuf_younger_is_1 ? sbuf1_mask : sbuf0_mask;
    wire [31:0] sbuf_older_wdata =
        (sbuf0_valid_r && sbuf1_valid_r && sbuf_head_is_1_r) ? sbuf1_wdata_r :
        (sbuf0_valid_r ? sbuf0_wdata_r : sbuf1_wdata_r);
    wire [31:0] sbuf_younger_wdata = sbuf_younger_is_1 ? sbuf1_wdata_r : sbuf0_wdata_r;
    wire [31:0] sbuf_younger_byte_mask = {
        {8{sbuf_younger_mask[3]}}, {8{sbuf_younger_mask[2]}},
        {8{sbuf_younger_mask[1]}}, {8{sbuf_younger_mask[0]}}
    };
    wire [31:0] sbuf_merged_data =
        (sbuf_younger_wdata & sbuf_younger_byte_mask) |
        (sbuf_older_wdata & ~sbuf_younger_byte_mask);
    wire sbuf_any_overlap = (sbuf0_same_word && (sbuf0_cover != 4'b0)) ||
        (sbuf1_same_word && (sbuf1_cover != 4'b0));
    wire sbuf_forward_hit = req_load_can_check_sbuf && (sbuf_merged_cover == req_load_mask);
    wire [31:0] sbuf_forward_data = sbuf_merged_data;
    wire sbuf_conflict_stall = req_load_can_check_sbuf && sbuf_any_overlap && !sbuf_forward_hit;
    wire req_wait_for_sbuf_drain = SBUF_ENABLE && req_atomic_r && sbuf_any_valid;
    wire stale_lower_resp_in_req =
        ((state == S_DATA_REQ) || (state == S_PTW_REQ)) &&
        lower_resp_valid && !sbuf_drain_resp_pending;
    wire stale_lower_resp_before_sbuf_drain =
        (state == S_IDLE) && sbuf_drain_req_valid &&
        lower_resp_valid && !sbuf_drain_resp_pending;
    wire req_blocked_by_full_sbuf_load =
        (state == S_DATA_REQ) && SBUF_ENABLE && !req_write_r &&
        !req_atomic_r && !req_uncached && sbuf_any_valid &&
        !sbuf_forward_hit && !stale_lower_resp_in_req;
    wire req_blocked_by_full_sbuf_store =
        (state == S_DATA_REQ) && req_store_buffer_full;
    wire sbuf_drain_req_valid = SBUF_ENABLE && sbuf_head_valid && !sbuf_head_sent;
    wire sbuf_drain_grant = sbuf_drain_req_valid &&
        (state != S_PTW_REQ) && ((state != S_DATA_REQ) || req_wait_for_sbuf_drain ||
            stale_lower_resp_in_req || req_blocked_by_full_sbuf_load ||
            req_blocked_by_full_sbuf_store);
    wire sbuf_drain_req_fire = sbuf_drain_grant && lower_req_ready;
    wire sbuf_drain_resp_fire = sbuf_drain_resp_pending && lower_resp_fire;
    wire data_req_fire = lower_req_fire && (state == S_DATA_REQ) && !sbuf_drain_grant;

    assign store_buffer_empty = !sbuf_any_valid && !sbuf_drain_resp_pending;
    assign store_buffer_busy = !store_buffer_empty;

    Sv32Tlb #(
        .ENTRY_COUNT(`NPC_DTLB_ENTRIES)
    ) u_dtlb (
        .clk(clk),
        .rst_n(rst_n),
        .flush_all(tlb_flush_all),
        .lookup_valid(dtlb_lookup_valid),
        .lookup_vaddr(cpu_req_vaddr),
        .lookup_hit(dtlb_lookup_hit),
        .lookup_paddr(dtlb_lookup_paddr),
        .lookup_pte(dtlb_lookup_pte),
        .lookup_level(dtlb_lookup_level),
        .refill_valid(dtlb_refill_valid),
        .refill_vaddr(req_vaddr_r),
        .refill_pte(pte_word),
        .refill_level(walk_level_r)
    );

    assign cpu_req_ready = (state == S_IDLE) && !cpu_resp_valid && !drop_resp_r &&
        !sbuf_drain_resp_pending;
    assign lower_req_valid = dhitopt_fast_valid || (state == S_PTW_REQ) ||
        ((state == S_DATA_REQ) && !req_safe_store_bufferable && !req_store_buffer_full &&
            !sbuf_conflict_stall &&
            !req_wait_for_sbuf_drain && !stale_lower_resp_in_req) ||
        sbuf_drain_grant;
    assign lower_req_write =
        dhitopt_fast_valid ? 1'b0 :
        sbuf_drain_grant ? 1'b1 :
        (state == S_DATA_REQ) ? req_write_r : 1'b0;
    assign lower_req_addr =
        dhitopt_fast_valid ? dtlb_lookup_paddr :
        (state == S_PTW_REQ) ? ptw_addr_r :
        sbuf_drain_grant ? sbuf_head_paddr :
        (state == S_DATA_REQ) ? phys_addr_r : 32'b0;
    assign lower_req_wdata =
        dhitopt_fast_valid ? 32'b0 :
        sbuf_drain_grant ? sbuf_head_wdata :
        (state == S_DATA_REQ) ? req_wdata_r : 32'b0;
    assign lower_req_wstrb =
        dhitopt_fast_valid ? 4'b0 :
        sbuf_drain_grant ? sbuf_head_wstrb :
        (state == S_DATA_REQ) ? req_wstrb_r : 4'b0;
    assign lower_req_len =
        dhitopt_fast_valid ? cpu_req_len :
        (state == S_PTW_REQ) ? 3'd4 :
        sbuf_drain_grant ? sbuf_head_len :
        (state == S_DATA_REQ) ? req_len_r : 3'b0;
    assign lower_req_is_ptw = (state == S_PTW_REQ);
    assign lower_resp_ready = drop_resp_r || sbuf_drain_resp_pending ||
        stale_lower_resp_in_req || stale_lower_resp_before_sbuf_drain ||
        (state == S_PTW_WAIT) || (state == S_DATA_WAIT);
    assign dbg_state = state;
    assign dbg_drop_resp = drop_resp_r;
    assign dbg_req_write = req_write_r;
    assign dbg_req_store_bufferable = req_store_bufferable_r;
    assign dbg_req_safe_store_bufferable = req_safe_store_bufferable;
    assign dbg_sbuf0_valid = sbuf0_valid_r;
    assign dbg_sbuf1_valid = sbuf1_valid_r;
    assign dbg_sbuf0_sent = sbuf0_sent_r;
    assign dbg_sbuf1_sent = sbuf1_sent_r;
    assign dbg_sbuf_drain_active = sbuf_drain_active_r;
    assign dbg_sbuf_drain_resp_pending = sbuf_drain_resp_pending;
    assign dbg_sbuf_drain_req_valid = sbuf_drain_req_valid;
    assign dbg_sbuf_drain_grant = sbuf_drain_grant;
    assign dbg_sbuf_drain_req_fire = sbuf_drain_req_fire;
    assign dbg_sbuf_drain_resp_fire = sbuf_drain_resp_fire;
    assign dbg_data_req_fire = data_req_fire;
    assign dbg_lower_resp_ready = lower_resp_ready;
    assign dbg_lower_req_valid = lower_req_valid;
    assign dbg_lower_req_write = lower_req_write;
    assign dbg_lower_req_addr = lower_req_addr;
    assign dbg_sbuf_conflict_stall = sbuf_conflict_stall;
    assign dbg_req_store_buffer_full = req_store_buffer_full;
    assign dbg_sbuf_forward_hit = sbuf_forward_hit;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
            drop_resp_r <= 1'b0;
            req_write_r <= 1'b0;
            req_atomic_r <= 1'b0;
            req_store_bufferable_r <= 1'b0;
            req_vaddr_r <= 32'b0;
            req_wdata_r <= 32'b0;
            req_wstrb_r <= 4'b0;
            req_len_r <= 3'b0;
            req_eff_priv_r <= PRIV_M;
            req_mstatus_r <= 32'b0;
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
            stat_data_req_count <= 64'd0;
            stat_data_resp_count <= 64'd0;
            stat_uncached_req_count <= 64'd0;
            stat_sbuf_enqueue <= 64'd0;
            stat_sbuf_dequeue <= 64'd0;
            stat_sbuf_full_stall <= 64'd0;
            stat_sbuf_drain_req <= 64'd0;
            stat_sbuf_drain_resp <= 64'd0;
            stat_sbuf_drain_wait <= 64'd0;
            stat_sbuf_load_forward <= 64'd0;
            stat_sbuf_load_stall_conflict <= 64'd0;
            stat_sbuf_load_stall_buffer_nonempty <= 64'd0;
            stat_sbuf_fence_drain_wait <= 64'd0;
            stat_sbuf_uncached_drain_wait <= 64'd0;
            stat_sbuf_killed_store_block <= 64'd0;
            stat_sbuf_occupancy0 <= 64'd0;
            stat_sbuf_occupancy1 <= 64'd0;
            stat_sbuf_occupancy2 <= 64'd0;
            stat_sbuf_max_occupancy <= 64'd0;
            stat_sbuf_enqueue_occ0 <= 64'd0;
            stat_sbuf_enqueue_occ1 <= 64'd0;
            stat_sbuf_enqueue_full <= 64'd0;
            stat_dhitopt_candidate <= 64'd0;
            stat_dhitopt_success <= 64'd0;
            stat_dhitopt_fallback <= 64'd0;
            stat_dhitopt_block_store_buffer <= 64'd0;
            stat_dhitopt_block_uncached <= 64'd0;
            stat_dhitopt_block_fault <= 64'd0;
            stat_dhitopt_block_miss <= 64'd0;
            stat_dhitopt_block_alignment <= 64'd0;
            stat_dhitopt_unknown <= 64'd0;
            req_from_tlb_hit_r <= 1'b0;
            sbuf0_valid_r <= 1'b0;
            sbuf1_valid_r <= 1'b0;
            sbuf0_sent_r <= 1'b0;
            sbuf1_sent_r <= 1'b0;
            sbuf0_paddr_r <= 32'b0;
            sbuf1_paddr_r <= 32'b0;
            sbuf0_wdata_r <= 32'b0;
            sbuf1_wdata_r <= 32'b0;
            sbuf0_wstrb_r <= 4'b0;
            sbuf1_wstrb_r <= 4'b0;
            sbuf0_len_r <= 3'b0;
            sbuf1_len_r <= 3'b0;
            sbuf_head_is_1_r <= 1'b0;
            sbuf_drain_active_r <= 1'b0;
            dhitopt_active_r <= 1'b0;
            dhitopt_wait_r <= 4'd0;
        end else begin
            if ((state == S_PTW_REQ) || (state == S_PTW_WAIT)) begin
                stat_ptw_cycle_count <= stat_ptw_cycle_count + 64'd1;
            end

            if (SBUF_ENABLE) begin
                case (sbuf_occupancy)
                    2'd0: stat_sbuf_occupancy0 <= stat_sbuf_occupancy0 + 64'd1;
                    2'd1: stat_sbuf_occupancy1 <= stat_sbuf_occupancy1 + 64'd1;
                    default: stat_sbuf_occupancy2 <= stat_sbuf_occupancy2 + 64'd1;
                endcase
                if ({62'b0, sbuf_occupancy} > stat_sbuf_max_occupancy) begin
                    stat_sbuf_max_occupancy <= {62'b0, sbuf_occupancy};
                end
            end

            if ((state == S_DATA_REQ) || (state == S_DATA_WAIT) || (state == S_RESP)) begin
                stat_bridge_state_wait_cycle <= stat_bridge_state_wait_cycle + 64'd1;
            end
            if ((state == S_DATA_REQ) && !lower_req_ready) begin
                stat_cache_req_wait_cycle <= stat_cache_req_wait_cycle + 64'd1;
            end
            if ((state == S_DATA_WAIT) && !lower_resp_valid) begin
                stat_cache_resp_wait_cycle <= stat_cache_resp_wait_cycle + 64'd1;
            end
            if ((state == S_DATA_REQ) && req_from_tlb_hit_r && !data_req_fire) begin
                stat_tlb_hit_to_cache_req_cycle <= stat_tlb_hit_to_cache_req_cycle + 64'd1;
            end
            if (SBUF_ENABLE && sbuf_head_valid && sbuf_head_sent && !sbuf_drain_resp_fire) begin
                stat_sbuf_drain_wait <= stat_sbuf_drain_wait + 64'd1;
            end
            if (SBUF_ENABLE && req_store_buffer_full && (state == S_DATA_REQ)) begin
                stat_sbuf_full_stall <= stat_sbuf_full_stall + 64'd1;
                stat_sbuf_enqueue_full <= stat_sbuf_enqueue_full + 64'd1;
            end
            if (SBUF_ENABLE && sbuf_conflict_stall && (state == S_DATA_REQ)) begin
                stat_sbuf_load_stall_conflict <= stat_sbuf_load_stall_conflict + 64'd1;
            end
            if (SBUF_ENABLE && !req_write_r && req_uncached && sbuf_any_valid &&
                    (state == S_DATA_REQ)) begin
                stat_sbuf_uncached_drain_wait <= stat_sbuf_uncached_drain_wait + 64'd1;
            end

            if (lower_req_fire && (state == S_PTW_REQ)) begin
                if (walk_level_r) begin
                    stat_ptw_l1_read_count <= stat_ptw_l1_read_count + 64'd1;
                end else begin
                    stat_ptw_l0_read_count <= stat_ptw_l0_read_count + 64'd1;
                end
            end
            if (data_req_fire || dhitopt_fast_fire) begin
                stat_data_req_count <= stat_data_req_count + 64'd1;
                if (dhitopt_fast_fire ? dtlb_load_uncached :
                        ((phys_addr_r & 32'hf0000000) == 32'ha0000000)) begin
                    stat_uncached_req_count <= stat_uncached_req_count + 64'd1;
                end
                req_from_tlb_hit_r <= 1'b0;
            end
            if (sbuf_drain_req_fire) begin
                stat_sbuf_drain_req <= stat_sbuf_drain_req + 64'd1;
                sbuf_drain_active_r <= 1'b1;
                if (sbuf_head_is_1) begin
                    sbuf1_sent_r <= 1'b1;
                end else begin
                    sbuf0_sent_r <= 1'b1;
                end
            end
            if (lower_resp_fire && (state == S_DATA_WAIT)) begin
                stat_data_resp_count <= stat_data_resp_count + 64'd1;
            end
            if (sbuf_drain_resp_fire) begin
                stat_sbuf_drain_resp <= stat_sbuf_drain_resp + 64'd1;
                stat_sbuf_dequeue <= stat_sbuf_dequeue + 64'd1;
                sbuf_drain_active_r <= 1'b0;
                if (sbuf_head_is_1) begin
                    sbuf1_valid_r <= 1'b0;
                    sbuf1_sent_r <= 1'b0;
                    if (sbuf0_valid_r) begin
                        sbuf_head_is_1_r <= 1'b0;
                    end
                end else begin
                    sbuf0_valid_r <= 1'b0;
                    sbuf0_sent_r <= 1'b0;
                    if (sbuf1_valid_r) begin
                        sbuf_head_is_1_r <= 1'b1;
                    end
                end
            end
            if (dhitopt_active_r && !lower_resp_fire) begin
                dhitopt_wait_r <= dhitopt_wait_r + 4'd1;
            end
            if (dhitopt_active_r && lower_resp_fire) begin
                if (dhitopt_wait_r <= 4'd2) begin
                    stat_dhitopt_success <= stat_dhitopt_success + 64'd1;
                end else begin
                    stat_dhitopt_block_miss <= stat_dhitopt_block_miss + 64'd1;
                end
                dhitopt_active_r <= 1'b0;
                dhitopt_wait_r <= 4'd0;
            end

            if (resp_fire) begin
                cpu_resp_valid <= 1'b0;
                cpu_resp_exc_valid <= 1'b0;
            end

            if (flush) begin
                // Keep draining a stale lower response if one was already
                // accepted, but drop any pending upper response.
                cpu_resp_valid <= 1'b0;
                cpu_resp_exc_valid <= 1'b0;
                cpu_resp_rdata <= 32'b0;
                cpu_resp_exc_cause <= 32'b0;
                cpu_resp_exc_tval <= 32'b0;
                state <= S_IDLE;
                req_from_tlb_hit_r <= 1'b0;
                if (dhitopt_active_r && !lower_resp_fire) begin
                    stat_dhitopt_unknown <= stat_dhitopt_unknown + 64'd1;
                end
                dhitopt_active_r <= 1'b0;
                dhitopt_wait_r <= 4'd0;
                if (lower_req_fire || (state == S_PTW_WAIT) || (state == S_DATA_WAIT)) begin
                    if (!lower_resp_fire) begin
                        drop_resp_r <= 1'b1;
                    end else begin
                        drop_resp_r <= 1'b0;
                    end
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
                            req_write_r <= cpu_req_write;
                            req_atomic_r <= cpu_req_atomic;
                            req_store_bufferable_r <= cpu_req_store_bufferable;
                            req_vaddr_r <= cpu_req_vaddr;
                            req_wdata_r <= cpu_req_wdata;
                            req_wstrb_r <= cpu_req_wstrb;
                            req_len_r <= cpu_req_len;
                            req_eff_priv_r <= req_eff_priv;
                            req_mstatus_r <= mstatus_i;
                            cpu_resp_rdata <= 32'b0;
                            cpu_resp_exc_valid <= 1'b0;
                            cpu_resp_exc_cause <= 32'b0;
                            cpu_resp_exc_tval <= 32'b0;

                            if (req_cross_page) begin
                                cpu_resp_valid <= 1'b1;
                                cpu_resp_exc_valid <= 1'b1;
                                cpu_resp_exc_cause <= page_fault_cause(cpu_req_write);
                                cpu_resp_exc_tval <= cpu_req_vaddr;
                                stat_translate_count <= stat_translate_count + 64'd1;
                                stat_page_fault_count <= stat_page_fault_count + 64'd1;
                                stat_ptw_walk_fault_count <= stat_ptw_walk_fault_count + 64'd1;
                                state <= S_RESP;
                            end else if (!req_translate) begin
                                stat_bypass_count <= stat_bypass_count + 64'd1;
                                phys_addr_r <= cpu_req_vaddr;
                                req_from_tlb_hit_r <= 1'b0;
                                state <= S_DATA_REQ;
                            end else if (dtlb_enabled && dtlb_lookup_hit) begin
                                stat_translate_count <= stat_translate_count + 64'd1;
                                stat_tlb_hit_count <= stat_tlb_hit_count + 64'd1;
                                if (DCACHE_HIT_OPT_ENABLE && !cpu_req_write) begin
                                    stat_dhitopt_candidate <=
                                        stat_dhitopt_candidate + 64'd1;
                                end
                                if (!dtlb_perm_ok || !dtlb_ad_ok) begin
                                    cpu_resp_valid <= 1'b1;
                                    cpu_resp_exc_valid <= 1'b1;
                                    cpu_resp_exc_cause <= page_fault_cause(cpu_req_write);
                                    cpu_resp_exc_tval <= cpu_req_vaddr;
                                    cpu_resp_rdata <= 32'b0;
                                    stat_page_fault_count <= stat_page_fault_count + 64'd1;
                                    if (DCACHE_HIT_OPT_ENABLE && !cpu_req_write) begin
                                        stat_dhitopt_block_fault <=
                                            stat_dhitopt_block_fault + 64'd1;
                                    end
                                    state <= S_RESP;
                                end else begin
                                    phys_addr_r <= dtlb_lookup_paddr;
                                    req_from_tlb_hit_r <= 1'b1;
                                    if (dhitopt_fast_fire) begin
                                        dhitopt_active_r <= 1'b1;
                                        dhitopt_wait_r <= 4'd1;
                                        state <= S_DATA_WAIT;
                                    end else begin
                                        if (DCACHE_HIT_OPT_ENABLE && !cpu_req_write) begin
                                            if (!dtlb_load_aligned) begin
                                                stat_dhitopt_block_alignment <=
                                                    stat_dhitopt_block_alignment + 64'd1;
                                            end else if (dtlb_load_uncached) begin
                                                stat_dhitopt_block_uncached <=
                                                    stat_dhitopt_block_uncached + 64'd1;
                                            end else if (sbuf_any_valid || sbuf_drain_resp_pending) begin
                                                stat_dhitopt_block_store_buffer <=
                                                    stat_dhitopt_block_store_buffer + 64'd1;
                                            end else if (dhitopt_safe_candidate && !lower_req_ready) begin
                                                stat_dhitopt_fallback <=
                                                    stat_dhitopt_fallback + 64'd1;
                                            end else begin
                                                stat_dhitopt_unknown <=
                                                    stat_dhitopt_unknown + 64'd1;
                                            end
                                        end
                                        state <= S_DATA_REQ;
                                    end
                                end
                            end else begin
                                stat_translate_count <= stat_translate_count + 64'd1;
                                if (dtlb_enabled) begin
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
                        if (lower_req_fire) begin
                            state <= S_PTW_WAIT;
                        end
                    end

                    S_PTW_WAIT: begin
                        if (lower_resp_fire) begin
                            if (pte_invalid) begin
                                cpu_resp_valid <= 1'b1;
                                cpu_resp_exc_valid <= 1'b1;
                                cpu_resp_exc_cause <= page_fault_cause(req_write_r);
                                cpu_resp_exc_tval <= pte_vaddr;
                                cpu_resp_rdata <= 32'b0;
                                stat_page_fault_count <= stat_page_fault_count + 64'd1;
                                stat_ptw_walk_fault_count <= stat_ptw_walk_fault_count + 64'd1;
                                state <= S_RESP;
                            end else if (pte_leaf) begin
                                if (pte_superpage_misaligned || !pte_perm_ok || !pte_ad_ok) begin
                                    cpu_resp_valid <= 1'b1;
                                    cpu_resp_exc_valid <= 1'b1;
                                    cpu_resp_exc_cause <= page_fault_cause(req_write_r);
                                    cpu_resp_exc_tval <= pte_vaddr;
                                    cpu_resp_rdata <= 32'b0;
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
                                    state <= S_DATA_REQ;
                                end
                            end else begin
                                if (walk_level_r == 1'b0) begin
                                    cpu_resp_valid <= 1'b1;
                                    cpu_resp_exc_valid <= 1'b1;
                                    cpu_resp_exc_cause <= page_fault_cause(req_write_r);
                                    cpu_resp_exc_tval <= pte_vaddr;
                                    cpu_resp_rdata <= 32'b0;
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

                    S_DATA_REQ: begin
                        if (req_safe_store_bufferable) begin
                            if (!sbuf0_valid_r) begin
                                sbuf0_valid_r <= 1'b1;
                                sbuf0_sent_r <= 1'b0;
                                sbuf0_paddr_r <= phys_addr_r;
                                sbuf0_wdata_r <= req_wdata_r;
                                sbuf0_wstrb_r <= req_wstrb_r;
                                sbuf0_len_r <= req_len_r;
                                if (!sbuf1_valid_r) begin
                                    sbuf_head_is_1_r <= 1'b0;
                                end
                            end else begin
                                sbuf1_valid_r <= 1'b1;
                                sbuf1_sent_r <= 1'b0;
                                sbuf1_paddr_r <= phys_addr_r;
                                sbuf1_wdata_r <= req_wdata_r;
                                sbuf1_wstrb_r <= req_wstrb_r;
                                sbuf1_len_r <= req_len_r;
                                if (!sbuf0_valid_r) begin
                                    sbuf_head_is_1_r <= 1'b1;
                                end
                            end
                            stat_sbuf_enqueue <= stat_sbuf_enqueue + 64'd1;
                            if (sbuf_occupancy == 2'd0) begin
                                stat_sbuf_enqueue_occ0 <= stat_sbuf_enqueue_occ0 + 64'd1;
                            end else if (sbuf_occupancy == 2'd1) begin
                                stat_sbuf_enqueue_occ1 <= stat_sbuf_enqueue_occ1 + 64'd1;
                            end else begin
                                stat_sbuf_enqueue_full <= stat_sbuf_enqueue_full + 64'd1;
                            end
                            cpu_resp_valid <= 1'b1;
                            cpu_resp_exc_valid <= 1'b0;
                            cpu_resp_exc_cause <= 32'b0;
                            cpu_resp_exc_tval <= 32'b0;
                            cpu_resp_rdata <= 32'b0;
                            req_from_tlb_hit_r <= 1'b0;
                            state <= S_RESP;
                        end else if (sbuf_forward_hit) begin
                            stat_sbuf_load_forward <= stat_sbuf_load_forward + 64'd1;
                            cpu_resp_valid <= 1'b1;
                            cpu_resp_exc_valid <= 1'b0;
                            cpu_resp_exc_cause <= 32'b0;
                            cpu_resp_exc_tval <= 32'b0;
                            cpu_resp_rdata <= sbuf_forward_data;
                            req_from_tlb_hit_r <= 1'b0;
                            state <= S_RESP;
                        end else if (sbuf_conflict_stall) begin
                            stat_sbuf_load_stall_buffer_nonempty <=
                                stat_sbuf_load_stall_buffer_nonempty + 64'd1;
                        end else if (data_req_fire) begin
                            state <= S_DATA_WAIT;
                        end
                    end

                    S_DATA_WAIT: begin
                        if (lower_resp_fire) begin
                            cpu_resp_valid <= 1'b1;
                            cpu_resp_exc_valid <= 1'b0;
                            cpu_resp_exc_cause <= 32'b0;
                            cpu_resp_exc_tval <= 32'b0;
                            cpu_resp_rdata <= lower_resp_rdata;
                            state <= S_RESP;
                        end
                    end

                    S_RESP: begin
                        if (resp_fire) begin
                            cpu_resp_exc_valid <= 1'b0;
                            state <= S_IDLE;
                        end
                    end

                    default: begin
                        state <= S_IDLE;
                    end
                endcase
            end
        end
    end
endmodule
