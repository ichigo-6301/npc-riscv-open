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

// Deprecated experimental frontend from the first IF_HIT_PIPELINE attempt.
// Keep this file for reference only; cpu_top.v must instantiate
// Sv32FrontendPipe for the active IF_HIT_PIPELINE=1 MVP path.
module Sv32IFetchPipe (
    input clk,
    input rst_n,
    input flush,
    input tlb_flush_all,

    input cpu_req_valid,
    output cpu_req_ready,
    input [31:0] cpu_req_vaddr,

    input [1:0] priv_i,
    input [31:0] satp_i,

    output cpu_resp_valid,
    input cpu_resp_ready,
    output [31:0] cpu_resp_rdata,
    output cpu_resp_exc_valid,
    output [31:0] cpu_resp_exc_cause,
    output [31:0] cpu_resp_exc_tval,

    output pipe_req_valid,
    input pipe_req_ready,
    output [31:0] pipe_req_paddr,
    output [31:0] pipe_req_vaddr,
    output [31:0] pipe_req_pc,
    output [31:0] pipe_req_seq,
    output [15:0] pipe_req_epoch,
    output [1:0] pipe_req_priv,
    output pipe_req_exception_valid,
    output [31:0] pipe_req_exception_cause,
    output [31:0] pipe_req_exception_tval,

    input pipe_resp_valid,
    output pipe_resp_ready,
    input [31:0] pipe_resp_instr,
    input [31:0] pipe_resp_pc,
    input [31:0] pipe_resp_seq,
    input [15:0] pipe_resp_epoch,
    input pipe_resp_exception_valid,
    input [31:0] pipe_resp_exception_cause,
    input [31:0] pipe_resp_exception_tval,
    input pipe_resp_hit,
    input pipe_resp_miss,

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

    localparam [1:0] PTW_IDLE  = 2'd0;
    localparam [1:0] PTW_REQ   = 2'd1;
    localparam [1:0] PTW_WAIT  = 2'd2;
    localparam [1:0] PTW_FETCH = 2'd3;

    reg [1:0] ptw_state;
    reg [31:0] req_vaddr_r;
    reg [31:0] ptw_addr_r;
    reg [9:0] ptw_vpn0_r;
    reg [31:0] ptw_phys_addr_r;
    reg walk_level_r;

    reg [31:0] seq_r;
    reg [15:0] epoch_r;
    reg [2:0] pipe_outstanding_r;

    reg [31:0] ptw_seq_r;
    reg [15:0] ptw_epoch_r;

    reg direct_resp_valid_r;
    reg [15:0] direct_resp_epoch_r;
    reg [31:0] direct_resp_cause_r;
    reg [31:0] direct_resp_tval_r;

    wire req_translate_normal = (`NPC_HAS_MMU != 0) && satp_i[31] && (priv_i != PRIV_M);
`ifdef NPC_FORCE_MMU_BYPASS
    wire req_translate = 1'b0;
`elsif NPC_FORCE_MMU_TRANSLATE
    wire req_translate = satp_i[31];
`else
    wire req_translate = req_translate_normal;
`endif
    wire itlb_enabled = (`NPC_HAS_ITLB != 0);
    wire itlb_lookup_valid = cpu_req_valid && (ptw_state == PTW_IDLE) &&
        req_translate && itlb_enabled && !flush;
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
    wire pte_leaf = pte_word[1] || pte_word[3];
    wire pte_invalid = !pte_v || (!pte_r_bit && pte_w_bit);
    wire pte_superpage_misaligned =
        (walk_level_r == 1'b1) && (pte_word[19:10] != 10'b0);
    wire pte_perm_ok = fetch_perm_ok(priv_i, pte_word);
    wire itlb_perm_ok = fetch_perm_ok(priv_i, itlb_lookup_pte);
    wire itlb_refill_valid =
        itlb_enabled && (ptw_state == PTW_WAIT) && lower_resp_valid && lower_resp_ready &&
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

    wire direct_resp_current = direct_resp_valid_r && (direct_resp_epoch_r == epoch_r);
    wire pipe_resp_current = pipe_resp_valid && (pipe_resp_epoch == epoch_r);
    wire pipe_resp_stale = pipe_resp_valid && (pipe_resp_epoch != epoch_r);
    wire direct_resp_fire = direct_resp_current && cpu_resp_ready;
    wire pipe_resp_fire_current = pipe_resp_current && !direct_resp_current && cpu_resp_ready;

    assign cpu_resp_valid = direct_resp_current || pipe_resp_current;
    assign cpu_resp_rdata = direct_resp_current ? 32'b0 : pipe_resp_instr;
    assign cpu_resp_exc_valid = direct_resp_current ? 1'b1 : pipe_resp_exception_valid;
    assign cpu_resp_exc_cause = direct_resp_current ? direct_resp_cause_r : pipe_resp_exception_cause;
    assign cpu_resp_exc_tval = direct_resp_current ? direct_resp_tval_r : pipe_resp_exception_tval;
    assign pipe_resp_ready = pipe_resp_stale ? 1'b1 : pipe_resp_fire_current;

    wire fast_candidate = cpu_req_valid && (ptw_state == PTW_IDLE) &&
        !direct_resp_valid_r &&
        (!req_translate || (itlb_enabled && itlb_lookup_hit));
    wire fast_exception = fast_candidate && req_translate &&
        itlb_enabled && itlb_lookup_hit && !itlb_perm_ok;
    wire [31:0] fast_paddr = (!req_translate) ? cpu_req_vaddr : itlb_lookup_paddr;

    wire ptw_candidate = cpu_req_valid && (ptw_state == PTW_IDLE) &&
        !direct_resp_valid_r && req_translate &&
        (!itlb_enabled || !itlb_lookup_hit) &&
        (pipe_outstanding_r == 3'd0) && !pipe_resp_current;
    wire ptw_fetch_active = (ptw_state == PTW_FETCH);
    wire [31:0] req_seq_w = ptw_fetch_active ? ptw_seq_r : seq_r;
    wire [15:0] req_epoch_w = ptw_fetch_active ? ptw_epoch_r : epoch_r;

    assign pipe_req_valid = !flush && (ptw_fetch_active || fast_candidate);
    assign pipe_req_paddr = ptw_fetch_active ? ptw_phys_addr_r : fast_paddr;
    assign pipe_req_vaddr = ptw_fetch_active ? req_vaddr_r : cpu_req_vaddr;
    assign pipe_req_pc = ptw_fetch_active ? req_vaddr_r : cpu_req_vaddr;
    assign pipe_req_seq = req_seq_w;
    assign pipe_req_epoch = req_epoch_w;
    assign pipe_req_priv = priv_i;
    assign pipe_req_exception_valid = !ptw_fetch_active && fast_exception;
    assign pipe_req_exception_cause = 32'd12;
    assign pipe_req_exception_tval = cpu_req_vaddr;

    assign cpu_req_ready = !flush &&
        (fast_candidate ? pipe_req_ready :
         ptw_candidate ? 1'b1 :
         1'b0);

    assign lower_req_valid = (ptw_state == PTW_REQ);
    assign lower_req_addr = ptw_addr_r;
    assign lower_resp_ready = (ptw_state == PTW_WAIT);

    wire cpu_req_fire = cpu_req_valid && cpu_req_ready;
    wire pipe_req_fire = pipe_req_valid && pipe_req_ready;
    wire lower_req_fire = lower_req_valid && lower_req_ready;
    wire lower_resp_fire = lower_resp_valid && lower_resp_ready;
    wire pipe_resp_drop_fire = pipe_resp_valid && pipe_resp_ready && pipe_resp_stale;
    wire pipe_resp_retire_fire = pipe_resp_fire_current;

`ifdef NPC_IFPIPE_DEBUG
    integer dbg_cycle;
    integer dbg_print_count;
    always @(posedge clk) begin
        if (!rst_n) begin
            dbg_cycle <= 0;
            dbg_print_count <= 0;
        end else begin
            dbg_cycle <= dbg_cycle + 1;
            if ((dbg_print_count < 300) &&
                (satp_i[31] || (priv_i != PRIV_M) || (ptw_state != PTW_IDLE) ||
                 direct_resp_valid_r) &&
                (cpu_req_valid || cpu_resp_valid || pipe_req_valid || pipe_resp_valid ||
                 lower_req_valid || lower_resp_valid || ptw_state != PTW_IDLE ||
                 pipe_outstanding_r != 3'd0 || direct_resp_valid_r)) begin
                $display("[ifpipe] cyc=%0d epoch=%0d ptw=%0d out=%0d cpu_v=%0d cpu_r=%0d va=%08x trans=%0d tlbh=%0d pipe_req_v=%0d pipe_req_r=%0d pa=%08x seq=%0d pipe_resp_v=%0d pipe_resp_r=%0d resp_epoch=%0d resp_seq=%0d stale=%0d direct=%0d",
                    dbg_cycle, epoch_r, ptw_state, pipe_outstanding_r,
                    cpu_req_valid, cpu_req_ready, cpu_req_vaddr, req_translate, itlb_lookup_hit,
                    pipe_req_valid, pipe_req_ready, pipe_req_paddr, pipe_req_seq,
                    pipe_resp_valid, pipe_resp_ready, pipe_resp_epoch, pipe_resp_seq,
                    pipe_resp_stale, direct_resp_valid_r);
                dbg_print_count <= dbg_print_count + 1;
            end
        end
    end
`endif

    always @(posedge clk) begin
        if (!rst_n) begin
            ptw_state <= PTW_IDLE;
            req_vaddr_r <= 32'b0;
            ptw_addr_r <= 32'b0;
            ptw_vpn0_r <= 10'b0;
            ptw_phys_addr_r <= 32'b0;
            walk_level_r <= 1'b0;
            seq_r <= 32'd1;
            epoch_r <= 16'd1;
            pipe_outstanding_r <= 3'd0;
            ptw_seq_r <= 32'b0;
            ptw_epoch_r <= 16'b0;
            direct_resp_valid_r <= 1'b0;
            direct_resp_epoch_r <= 16'b0;
            direct_resp_cause_r <= 32'b0;
            direct_resp_tval_r <= 32'b0;
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
        end else begin
            if ((ptw_state == PTW_REQ) || (ptw_state == PTW_WAIT)) begin
                stat_ptw_cycle_count <= stat_ptw_cycle_count + 64'd1;
            end
            if ((ptw_state != PTW_IDLE) || (pipe_outstanding_r != 3'd0) ||
                direct_resp_valid_r || pipe_resp_valid) begin
                stat_bridge_state_wait_cycle <= stat_bridge_state_wait_cycle + 64'd1;
            end
            if (pipe_req_valid && !pipe_req_ready) begin
                stat_cache_req_wait_cycle <= stat_cache_req_wait_cycle + 64'd1;
            end
            if ((pipe_outstanding_r != 3'd0) && !pipe_resp_current) begin
                stat_cache_resp_wait_cycle <= stat_cache_resp_wait_cycle + 64'd1;
            end
            if (fast_candidate && req_translate && itlb_enabled && itlb_lookup_hit &&
                itlb_perm_ok && !pipe_req_ready) begin
                stat_tlb_hit_to_cache_req_cycle <= stat_tlb_hit_to_cache_req_cycle + 64'd1;
            end

            if (flush) begin
                ptw_state <= PTW_IDLE;
                epoch_r <= epoch_r + 16'd1;
                pipe_outstanding_r <= 3'd0;
                direct_resp_valid_r <= 1'b0;
            end else begin
                if (direct_resp_fire) begin
                    direct_resp_valid_r <= 1'b0;
                end

                if (pipe_req_fire) begin
                    stat_fetch_req_count <= stat_fetch_req_count + 64'd1;
                    pipe_outstanding_r <= pipe_outstanding_r + 3'd1;
                end
                if (pipe_resp_retire_fire && (pipe_outstanding_r != 3'd0)) begin
                    stat_fetch_resp_count <= stat_fetch_resp_count + 64'd1;
                    pipe_outstanding_r <= pipe_outstanding_r - 3'd1;
                end
                if (pipe_req_fire && pipe_resp_retire_fire) begin
                    pipe_outstanding_r <= pipe_outstanding_r;
                end
                if (pipe_resp_drop_fire) begin
                    stat_fetch_resp_count <= stat_fetch_resp_count + 64'd1;
                end

                if (cpu_req_fire) begin
                    stat_req_count <= stat_req_count + 64'd1;
                    seq_r <= seq_r + 32'd1;
                    if (!req_translate) begin
                        stat_bypass_count <= stat_bypass_count + 64'd1;
                    end else begin
                        stat_translate_count <= stat_translate_count + 64'd1;
                    end

                    if (fast_exception) begin
                        stat_tlb_hit_count <= stat_tlb_hit_count + 64'd1;
                        stat_page_fault_count <= stat_page_fault_count + 64'd1;
                    end else if (req_translate && itlb_enabled && itlb_lookup_hit) begin
                        stat_tlb_hit_count <= stat_tlb_hit_count + 64'd1;
                    end else if (ptw_candidate) begin
                        if (itlb_enabled) begin
                            stat_tlb_miss_count <= stat_tlb_miss_count + 64'd1;
                        end
                        stat_ptw_walk_start_count <= stat_ptw_walk_start_count + 64'd1;
                        req_vaddr_r <= cpu_req_vaddr;
                        ptw_seq_r <= seq_r;
                        ptw_epoch_r <= epoch_r;
                        ptw_vpn0_r <= cpu_req_vaddr[21:12];
                        walk_level_r <= 1'b1;
                        ptw_addr_r <= make_pte_addr(make_satp_base(satp_i), {22'b0, cpu_req_vaddr[31:22]});
                        ptw_state <= PTW_REQ;
                    end
                end

                case (ptw_state)
                    PTW_REQ: begin
                        if (lower_req_fire) begin
                            if (walk_level_r) begin
                                stat_ptw_l1_read_count <= stat_ptw_l1_read_count + 64'd1;
                            end else begin
                                stat_ptw_l0_read_count <= stat_ptw_l0_read_count + 64'd1;
                            end
                            ptw_state <= PTW_WAIT;
                        end
                    end

                    PTW_WAIT: begin
                        if (lower_resp_fire) begin
                            if (pte_invalid) begin
                                stat_page_fault_count <= stat_page_fault_count + 64'd1;
                                stat_ptw_walk_fault_count <= stat_ptw_walk_fault_count + 64'd1;
                                direct_resp_valid_r <= 1'b1;
                                direct_resp_epoch_r <= ptw_epoch_r;
                                direct_resp_cause_r <= 32'd12;
                                direct_resp_tval_r <= req_vaddr_r;
                                ptw_state <= PTW_IDLE;
                            end else if (pte_leaf) begin
                                if (pte_superpage_misaligned || !pte_perm_ok) begin
                                    stat_page_fault_count <= stat_page_fault_count + 64'd1;
                                    stat_ptw_walk_fault_count <= stat_ptw_walk_fault_count + 64'd1;
                                    direct_resp_valid_r <= 1'b1;
                                    direct_resp_epoch_r <= ptw_epoch_r;
                                    direct_resp_cause_r <= 32'd12;
                                    direct_resp_tval_r <= req_vaddr_r;
                                    ptw_state <= PTW_IDLE;
                                end else begin
                                    if (walk_level_r == 1'b1) begin
                                        ptw_phys_addr_r <= make_phys_addr(pte_word, ptw_vpn0_r, req_vaddr_r[11:0]);
                                    end else begin
                                        ptw_phys_addr_r <= make_phys_addr(pte_word, pte_word[19:10], req_vaddr_r[11:0]);
                                    end
                                    stat_ptw_walk_done_count <= stat_ptw_walk_done_count + 64'd1;
                                    ptw_state <= PTW_FETCH;
                                end
                            end else begin
                                if (walk_level_r == 1'b0) begin
                                    stat_page_fault_count <= stat_page_fault_count + 64'd1;
                                    stat_ptw_walk_fault_count <= stat_ptw_walk_fault_count + 64'd1;
                                    direct_resp_valid_r <= 1'b1;
                                    direct_resp_epoch_r <= ptw_epoch_r;
                                    direct_resp_cause_r <= 32'd12;
                                    direct_resp_tval_r <= req_vaddr_r;
                                    ptw_state <= PTW_IDLE;
                                end else begin
                                    walk_level_r <= 1'b0;
                                    ptw_addr_r <= make_pte_addr(make_pte_base(pte_word), {22'b0, ptw_vpn0_r});
                                    ptw_state <= PTW_REQ;
                                end
                            end
                        end
                    end

                    PTW_FETCH: begin
                        if (pipe_req_fire) begin
                            ptw_state <= PTW_IDLE;
                        end
                    end

                    default: begin
                        ptw_state <= PTW_IDLE;
                    end
                endcase
            end
        end
    end

    wire unused_pipe_resp_pc = |pipe_resp_pc;
    wire unused_pipe_resp_hit = pipe_resp_hit;
    wire unused_pipe_resp_miss = pipe_resp_miss;
    wire unused_pipe_req_vaddr = |pipe_req_vaddr;
    wire unused_pipe_req_priv = |pipe_req_priv;
    wire unused_itlb_level = itlb_lookup_level;
endmodule
