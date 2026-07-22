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

module Sv32LSUPipe (
    input clk,
    input rst_n,
    input flush,
    input tlb_flush_all,

    input cpu_req_valid,
    output cpu_req_ready,
    input cpu_req_fast_ok,
    input cpu_req_fast_block_atomic,
    input cpu_req_fast_block_misaligned,
    input cpu_req_fast_block_exception,
    input cpu_req_fast_block_phase2,
    input cpu_req_fast_block_other,
    input cpu_req_write,
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

    output slow_req_valid,
    input slow_req_ready,
    output slow_req_write,
    output [31:0] slow_req_addr,
    output [31:0] slow_req_wdata,
    output [3:0] slow_req_wstrb,
    output [2:0] slow_req_len,
    input slow_resp_valid,
    output slow_resp_ready,
    input [31:0] slow_resp_rdata,
    input slow_resp_exc_valid,
    input [31:0] slow_resp_exc_cause,
    input [31:0] slow_resp_exc_tval,

    input slow_dtlb_refill_valid,
    input [31:0] slow_dtlb_refill_vaddr,
    input [31:0] slow_dtlb_refill_pte,
    input slow_dtlb_refill_level,

    output pipe_req_valid,
    input pipe_req_ready,
    output pipe_req_write,
    output [31:0] pipe_req_paddr,
    output [31:0] pipe_req_vaddr,
    output [31:0] pipe_req_wdata,
    output [3:0] pipe_req_wstrb,
    output [2:0] pipe_req_len,
    output [31:0] pipe_req_seq,
    output [15:0] pipe_req_epoch,
    output pipe_req_exception_valid,
    output [31:0] pipe_req_exception_cause,
    output [31:0] pipe_req_exception_tval,
    input pipe_resp_valid,
    output pipe_resp_ready,
    input [31:0] pipe_resp_rdata,
    input [31:0] pipe_resp_vaddr,
    input [31:0] pipe_resp_seq,
    input [15:0] pipe_resp_epoch,
    input pipe_resp_exception_valid,
    input [31:0] pipe_resp_exception_cause,
    input [31:0] pipe_resp_exception_tval,
    input pipe_resp_hit,
    input pipe_resp_miss,

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
    output reg [63:0] stat_lsu_pipe_issue_count,
    output reg [63:0] stat_lsu_pipe_resp_count,
    output reg [63:0] stat_lsu_pipe_epoch_drop_count,
    output reg [63:0] stat_lsu_pipe_dtlb_hit_count,
    output reg [63:0] stat_lsu_pipe_dtlb_miss_count,
    output reg [63:0] stat_lsu_pipe_replay_count,
    output reg [63:0] stat_lsu_pipe_fault_count,
    output reg [63:0] stat_lsu_pipe_stall_cycle,
    output reg [63:0] stat_lsu_pipe_dcache_hit_count,
    output reg [63:0] stat_lsu_pipe_dcache_miss_count,
    output reg [63:0] stat_lsu_pipe_store_hit_count,
    output reg [63:0] stat_lsu_pipe_load_hit_count,
    output reg [63:0] stat_lsu_pipe_slow_fallback_count,
    output reg [63:0] stat_lsu_pipe_load_miss_replay_count,
    output reg [63:0] stat_lsu_pipe_store_miss_replay_count,
    output reg [63:0] stat_lsu_pipe_direct_uncached_count,
    output reg [63:0] stat_lsu_pipe_direct_non_dtlb_hit_count,
    output reg [63:0] stat_lsu_pipe_direct_perm_fault_count,
    output reg [63:0] stat_lsu_pipe_direct_cross_page_count,
    output reg [63:0] stat_lsu_pipe_direct_fast_block_count,
    output reg [63:0] stat_lsu_pipe_direct_fast_block_atomic_count,
    output reg [63:0] stat_lsu_pipe_direct_fast_block_misaligned_count,
    output reg [63:0] stat_lsu_pipe_direct_fast_block_exception_count,
    output reg [63:0] stat_lsu_pipe_direct_fast_block_phase2_count,
    output reg [63:0] stat_lsu_pipe_direct_fast_block_other_count,
    output reg [63:0] stat_lsu_pipe_direct_other_count,
    output reg [63:0] stat_lsu_pipe_hit_latency_sum,
    output reg [63:0] stat_lsu_pipe_hit_latency_count,
    output reg [63:0] stat_lsu_pipe_hit_latency_max,
    output reg [63:0] stat_lsu_pipe_load_hit_latency_sum,
    output reg [63:0] stat_lsu_pipe_load_hit_latency_count,
    output reg [63:0] stat_lsu_pipe_load_hit_latency_max,
    output reg [63:0] stat_lsu_pipe_store_hit_latency_sum,
    output reg [63:0] stat_lsu_pipe_store_hit_latency_count,
    output reg [63:0] stat_lsu_pipe_store_hit_latency_max,
    output reg [63:0] stat_lsu_pipe_slow_fallback_latency_sum,
    output reg [63:0] stat_lsu_pipe_slow_fallback_latency_count,
    output reg [63:0] stat_lsu_pipe_slow_fallback_latency_max,
    output reg [63:0] stat_lsu_pipe_slow_direct_latency_sum,
    output reg [63:0] stat_lsu_pipe_slow_direct_latency_count,
    output reg [63:0] stat_lsu_pipe_slow_direct_latency_max,
    output reg [63:0] stat_lsu_pipe_slow_replay_latency_sum,
    output reg [63:0] stat_lsu_pipe_slow_replay_latency_count,
    output reg [63:0] stat_lsu_pipe_slow_replay_latency_max
);
    localparam [1:0] PRIV_U = 2'b00;
    localparam [1:0] PRIV_S = 2'b01;
    localparam [1:0] PRIV_M = 2'b11;

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_PIPE_WAIT = 2'd1;
    localparam [1:0] S_SLOW_REQ = 2'd2;
    localparam [1:0] S_SLOW_WAIT = 2'd3;

    reg [1:0] state_r;
    reg [31:0] seq_r;
    reg [15:0] epoch_r;
    reg drop_pipe_r;

    reg req_write_r;
    reg [31:0] req_vaddr_r;
    reg [31:0] req_paddr_r;
    reg [31:0] req_wdata_r;
    reg [3:0] req_wstrb_r;
    reg [2:0] req_len_r;
    reg [31:0] req_seq_r;
    reg [15:0] req_epoch_r;
    reg slow_req_pending_r;
    reg req_slow_replay_r;
    reg [63:0] req_latency_r;

    wire [63:0] req_latency_done = req_latency_r + 64'd1;

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
                    if (req_write) allow = pte[2];
                    else allow = pte[1] || (cur_mstatus[19] && pte[3]);
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
    wire pipe_req_fire = pipe_req_valid && pipe_req_ready;
    wire pipe_resp_fire = pipe_resp_valid && pipe_resp_ready;
    wire slow_req_fire = slow_req_valid && slow_req_ready;
    wire slow_resp_fire = slow_resp_valid && slow_resp_ready;

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
    wire [31:0] fast_paddr = req_translate ? dtlb_lookup_paddr : cpu_req_vaddr;
    wire req_uncached = ((fast_paddr & 32'hf0000000) == 32'ha0000000);

    wire dtlb_lookup_valid = cpu_req_valid && cpu_req_fast_ok && req_translate && !req_cross_page && dtlb_enabled &&
        (state_r == S_IDLE) && !cpu_resp_valid && !drop_pipe_r;
    wire dtlb_lookup_hit;
    wire [31:0] dtlb_lookup_paddr;
    wire [31:0] dtlb_lookup_pte;
    wire dtlb_lookup_level;
    wire dtlb_perm_ok = perm_ok(cpu_req_write, req_eff_priv, mstatus_i, dtlb_lookup_pte);
    wire dtlb_ad_ok = dtlb_lookup_pte[6] && (!cpu_req_write || dtlb_lookup_pte[7]);
    wire can_try_pipe = cpu_req_fast_ok && !req_cross_page &&
        (!req_translate || (dtlb_enabled && dtlb_lookup_hit && dtlb_perm_ok && dtlb_ad_ok)) &&
        !req_uncached;
    wire pipe_fault = cpu_req_fast_ok && req_translate && dtlb_enabled && dtlb_lookup_hit &&
        (!dtlb_perm_ok || !dtlb_ad_ok);

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
        .refill_valid(slow_dtlb_refill_valid),
        .refill_vaddr(slow_dtlb_refill_vaddr),
        .refill_pte(slow_dtlb_refill_pte),
        .refill_level(slow_dtlb_refill_level)
    );

    assign cpu_req_ready = (state_r == S_IDLE) && !cpu_resp_valid && !drop_pipe_r &&
        (can_try_pipe ? pipe_req_ready : 1'b1);

    assign pipe_req_valid = cpu_req_valid && cpu_req_ready && can_try_pipe;
    assign pipe_req_write = cpu_req_write;
    assign pipe_req_paddr = fast_paddr;
    assign pipe_req_vaddr = cpu_req_vaddr;
    assign pipe_req_wdata = cpu_req_wdata;
    assign pipe_req_wstrb = cpu_req_wstrb;
    assign pipe_req_len = cpu_req_len;
    assign pipe_req_seq = seq_r;
    assign pipe_req_epoch = epoch_r;
    assign pipe_req_exception_valid = 1'b0;
    assign pipe_req_exception_cause = 32'b0;
    assign pipe_req_exception_tval = 32'b0;
    assign pipe_resp_ready = drop_pipe_r || (state_r == S_PIPE_WAIT);

    assign slow_req_valid = slow_req_pending_r;
    assign slow_req_write = req_write_r;
    assign slow_req_addr = req_vaddr_r;
    assign slow_req_wdata = req_wdata_r;
    assign slow_req_wstrb = req_wstrb_r;
    assign slow_req_len = req_len_r;
    assign slow_resp_ready = (state_r == S_SLOW_WAIT);

    always @(posedge clk) begin
        if (!rst_n) begin
            state_r <= S_IDLE;
            seq_r <= 32'b0;
            epoch_r <= 16'b0;
            drop_pipe_r <= 1'b0;
            req_write_r <= 1'b0;
            req_vaddr_r <= 32'b0;
            req_paddr_r <= 32'b0;
            req_wdata_r <= 32'b0;
            req_wstrb_r <= 4'b0;
            req_len_r <= 3'b0;
            req_seq_r <= 32'b0;
            req_epoch_r <= 16'b0;
            slow_req_pending_r <= 1'b0;
            req_slow_replay_r <= 1'b0;
            req_latency_r <= 64'd0;
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
            stat_lsu_pipe_issue_count <= 64'd0;
            stat_lsu_pipe_resp_count <= 64'd0;
            stat_lsu_pipe_epoch_drop_count <= 64'd0;
            stat_lsu_pipe_dtlb_hit_count <= 64'd0;
            stat_lsu_pipe_dtlb_miss_count <= 64'd0;
            stat_lsu_pipe_replay_count <= 64'd0;
            stat_lsu_pipe_fault_count <= 64'd0;
            stat_lsu_pipe_stall_cycle <= 64'd0;
            stat_lsu_pipe_dcache_hit_count <= 64'd0;
            stat_lsu_pipe_dcache_miss_count <= 64'd0;
            stat_lsu_pipe_store_hit_count <= 64'd0;
            stat_lsu_pipe_load_hit_count <= 64'd0;
            stat_lsu_pipe_slow_fallback_count <= 64'd0;
            stat_lsu_pipe_load_miss_replay_count <= 64'd0;
            stat_lsu_pipe_store_miss_replay_count <= 64'd0;
            stat_lsu_pipe_direct_uncached_count <= 64'd0;
            stat_lsu_pipe_direct_non_dtlb_hit_count <= 64'd0;
            stat_lsu_pipe_direct_perm_fault_count <= 64'd0;
            stat_lsu_pipe_direct_cross_page_count <= 64'd0;
            stat_lsu_pipe_direct_fast_block_count <= 64'd0;
            stat_lsu_pipe_direct_fast_block_atomic_count <= 64'd0;
            stat_lsu_pipe_direct_fast_block_misaligned_count <= 64'd0;
            stat_lsu_pipe_direct_fast_block_exception_count <= 64'd0;
            stat_lsu_pipe_direct_fast_block_phase2_count <= 64'd0;
            stat_lsu_pipe_direct_fast_block_other_count <= 64'd0;
            stat_lsu_pipe_direct_other_count <= 64'd0;
            stat_lsu_pipe_hit_latency_sum <= 64'd0;
            stat_lsu_pipe_hit_latency_count <= 64'd0;
            stat_lsu_pipe_hit_latency_max <= 64'd0;
            stat_lsu_pipe_load_hit_latency_sum <= 64'd0;
            stat_lsu_pipe_load_hit_latency_count <= 64'd0;
            stat_lsu_pipe_load_hit_latency_max <= 64'd0;
            stat_lsu_pipe_store_hit_latency_sum <= 64'd0;
            stat_lsu_pipe_store_hit_latency_count <= 64'd0;
            stat_lsu_pipe_store_hit_latency_max <= 64'd0;
            stat_lsu_pipe_slow_fallback_latency_sum <= 64'd0;
            stat_lsu_pipe_slow_fallback_latency_count <= 64'd0;
            stat_lsu_pipe_slow_fallback_latency_max <= 64'd0;
            stat_lsu_pipe_slow_direct_latency_sum <= 64'd0;
            stat_lsu_pipe_slow_direct_latency_count <= 64'd0;
            stat_lsu_pipe_slow_direct_latency_max <= 64'd0;
            stat_lsu_pipe_slow_replay_latency_sum <= 64'd0;
            stat_lsu_pipe_slow_replay_latency_count <= 64'd0;
            stat_lsu_pipe_slow_replay_latency_max <= 64'd0;
        end else begin
            if (resp_fire) begin
                cpu_resp_valid <= 1'b0;
                cpu_resp_exc_valid <= 1'b0;
            end

            if (flush) begin
                epoch_r <= epoch_r + 16'd1;
                cpu_resp_valid <= 1'b0;
                cpu_resp_exc_valid <= 1'b0;
                cpu_resp_rdata <= 32'b0;
                cpu_resp_exc_cause <= 32'b0;
                cpu_resp_exc_tval <= 32'b0;
                slow_req_pending_r <= 1'b0;
                req_slow_replay_r <= 1'b0;
                req_latency_r <= 64'd0;
                if (state_r == S_PIPE_WAIT && !pipe_resp_fire) begin
                    drop_pipe_r <= 1'b1;
                    stat_lsu_pipe_epoch_drop_count <= stat_lsu_pipe_epoch_drop_count + 64'd1;
                end
                state_r <= S_IDLE;
            end else begin
                if (drop_pipe_r && pipe_resp_fire) begin
                    drop_pipe_r <= 1'b0;
                end

                if ((state_r == S_PIPE_WAIT) || (state_r == S_SLOW_REQ) || (state_r == S_SLOW_WAIT)) begin
                    stat_bridge_state_wait_cycle <= stat_bridge_state_wait_cycle + 64'd1;
                    stat_lsu_pipe_stall_cycle <= stat_lsu_pipe_stall_cycle + 64'd1;
                    req_latency_r <= req_latency_r + 64'd1;
                end
                if ((state_r == S_PIPE_WAIT) && !pipe_resp_valid) begin
                    stat_cache_resp_wait_cycle <= stat_cache_resp_wait_cycle + 64'd1;
                end
                if ((state_r == S_SLOW_REQ) && !slow_req_ready) begin
                    stat_cache_req_wait_cycle <= stat_cache_req_wait_cycle + 64'd1;
                end
                if ((state_r == S_SLOW_WAIT) && !slow_resp_valid) begin
                    stat_cache_resp_wait_cycle <= stat_cache_resp_wait_cycle + 64'd1;
                end

                if (req_fire) begin
                    stat_req_count <= stat_req_count + 64'd1;
                    req_write_r <= cpu_req_write;
                    req_vaddr_r <= cpu_req_vaddr;
                    req_paddr_r <= fast_paddr;
                    req_wdata_r <= cpu_req_wdata;
                    req_wstrb_r <= cpu_req_wstrb;
                    req_len_r <= cpu_req_len;
                    req_seq_r <= seq_r;
                    req_epoch_r <= epoch_r;
                    req_slow_replay_r <= 1'b0;
                    req_latency_r <= 64'd0;
                    seq_r <= seq_r + 32'd1;

                    if (req_translate) begin
                        stat_translate_count <= stat_translate_count + 64'd1;
                        if (dtlb_enabled && dtlb_lookup_hit) begin
                            stat_tlb_hit_count <= stat_tlb_hit_count + 64'd1;
                            stat_lsu_pipe_dtlb_hit_count <= stat_lsu_pipe_dtlb_hit_count + 64'd1;
                        end else if (dtlb_enabled) begin
                            stat_tlb_miss_count <= stat_tlb_miss_count + 64'd1;
                            stat_lsu_pipe_dtlb_miss_count <= stat_lsu_pipe_dtlb_miss_count + 64'd1;
                        end
                    end else begin
                        stat_bypass_count <= stat_bypass_count + 64'd1;
                    end

                    if (can_try_pipe) begin
                        stat_data_req_count <= stat_data_req_count + 64'd1;
                        stat_lsu_pipe_issue_count <= stat_lsu_pipe_issue_count + 64'd1;
                        state_r <= S_PIPE_WAIT;
`ifdef NPC_LSU_PIPE_DBG
                        $display("[LSUPipeDbg] issue seq=%0d vaddr=0x%08x paddr=0x%08x write=%0d epoch=%0d",
                            seq_r, cpu_req_vaddr, fast_paddr, cpu_req_write, epoch_r);
`endif
                    end else begin
                        stat_lsu_pipe_slow_fallback_count <= stat_lsu_pipe_slow_fallback_count + 64'd1;
                        if ((fast_paddr & 32'hf0000000) == 32'ha0000000) begin
                            stat_uncached_req_count <= stat_uncached_req_count + 64'd1;
                        end
                        if (!cpu_req_fast_ok) begin
                            stat_lsu_pipe_direct_fast_block_count <= stat_lsu_pipe_direct_fast_block_count + 64'd1;
                            if (cpu_req_fast_block_atomic) begin
                                stat_lsu_pipe_direct_fast_block_atomic_count <= stat_lsu_pipe_direct_fast_block_atomic_count + 64'd1;
                            end else if (cpu_req_fast_block_misaligned) begin
                                stat_lsu_pipe_direct_fast_block_misaligned_count <= stat_lsu_pipe_direct_fast_block_misaligned_count + 64'd1;
                            end else if (cpu_req_fast_block_exception) begin
                                stat_lsu_pipe_direct_fast_block_exception_count <= stat_lsu_pipe_direct_fast_block_exception_count + 64'd1;
                            end else if (cpu_req_fast_block_phase2) begin
                                stat_lsu_pipe_direct_fast_block_phase2_count <= stat_lsu_pipe_direct_fast_block_phase2_count + 64'd1;
                            end else begin
                                stat_lsu_pipe_direct_fast_block_other_count <= stat_lsu_pipe_direct_fast_block_other_count + 64'd1;
                            end
                        end else if (req_cross_page) begin
                            stat_lsu_pipe_direct_cross_page_count <= stat_lsu_pipe_direct_cross_page_count + 64'd1;
                        end else if (req_translate && (!dtlb_enabled || !dtlb_lookup_hit)) begin
                            stat_lsu_pipe_direct_non_dtlb_hit_count <= stat_lsu_pipe_direct_non_dtlb_hit_count + 64'd1;
                        end else if (pipe_fault) begin
                            stat_lsu_pipe_direct_perm_fault_count <= stat_lsu_pipe_direct_perm_fault_count + 64'd1;
                        end else if (req_uncached) begin
                            stat_lsu_pipe_direct_uncached_count <= stat_lsu_pipe_direct_uncached_count + 64'd1;
                        end else begin
                            stat_lsu_pipe_direct_other_count <= stat_lsu_pipe_direct_other_count + 64'd1;
                        end
                        slow_req_pending_r <= 1'b1;
                        state_r <= S_SLOW_REQ;
`ifdef NPC_LSU_PIPE_DBG
                        $display("[LSUPipeDbg] fallback seq=%0d vaddr=0x%08x write=%0d fast_ok=%0d translate=%0d dtlb_hit=%0d",
                            seq_r, cpu_req_vaddr, cpu_req_write, cpu_req_fast_ok, req_translate, dtlb_lookup_hit);
`endif
                    end
                end else if (state_r == S_SLOW_REQ) begin
                    if (slow_req_fire) begin
                        slow_req_pending_r <= 1'b0;
                        state_r <= S_SLOW_WAIT;
                    end
                end else if (state_r == S_PIPE_WAIT) begin
                    if (pipe_resp_fire) begin
                        if (pipe_resp_epoch != req_epoch_r || pipe_resp_seq != req_seq_r) begin
                            cpu_resp_valid <= 1'b0;
                            stat_lsu_pipe_epoch_drop_count <= stat_lsu_pipe_epoch_drop_count + 64'd1;
`ifdef NPC_LSU_PIPE_DBG
                            $display("[LSUPipeDbg] epoch_drop expected_seq=%0d got_seq=%0d expected_epoch=%0d got_epoch=%0d",
                                req_seq_r, pipe_resp_seq, req_epoch_r, pipe_resp_epoch);
`endif
                            state_r <= S_IDLE;
                        end else if (pipe_resp_miss) begin
                            stat_lsu_pipe_dcache_miss_count <= stat_lsu_pipe_dcache_miss_count + 64'd1;
                            stat_lsu_pipe_replay_count <= stat_lsu_pipe_replay_count + 64'd1;
                            stat_lsu_pipe_slow_fallback_count <= stat_lsu_pipe_slow_fallback_count + 64'd1;
                            if (req_write_r) begin
                                stat_lsu_pipe_store_miss_replay_count <= stat_lsu_pipe_store_miss_replay_count + 64'd1;
                            end else begin
                                stat_lsu_pipe_load_miss_replay_count <= stat_lsu_pipe_load_miss_replay_count + 64'd1;
                            end
                            req_slow_replay_r <= 1'b1;
                            slow_req_pending_r <= 1'b1;
                            state_r <= S_SLOW_REQ;
`ifdef NPC_LSU_PIPE_DBG
                            $display("[LSUPipeDbg] replay seq=%0d vaddr=0x%08x reason=dcache_miss",
                                req_seq_r, req_vaddr_r);
`endif
                        end else begin
                            cpu_resp_valid <= 1'b1;
                            cpu_resp_rdata <= pipe_resp_rdata;
                            cpu_resp_exc_valid <= pipe_resp_exception_valid;
                            cpu_resp_exc_cause <= pipe_resp_exception_cause;
                            cpu_resp_exc_tval <= pipe_resp_exception_tval;
                            stat_data_resp_count <= stat_data_resp_count + 64'd1;
                            stat_lsu_pipe_resp_count <= stat_lsu_pipe_resp_count + 64'd1;
                            if (pipe_resp_exception_valid) begin
                                stat_page_fault_count <= stat_page_fault_count + 64'd1;
                                stat_lsu_pipe_fault_count <= stat_lsu_pipe_fault_count + 64'd1;
                            end
                            if (pipe_resp_hit) begin
                                stat_lsu_pipe_dcache_hit_count <= stat_lsu_pipe_dcache_hit_count + 64'd1;
                                stat_lsu_pipe_hit_latency_sum <= stat_lsu_pipe_hit_latency_sum + req_latency_done;
                                stat_lsu_pipe_hit_latency_count <= stat_lsu_pipe_hit_latency_count + 64'd1;
                                if (req_latency_done > stat_lsu_pipe_hit_latency_max) begin
                                    stat_lsu_pipe_hit_latency_max <= req_latency_done;
                                end
                                if (req_write_r) stat_lsu_pipe_store_hit_count <= stat_lsu_pipe_store_hit_count + 64'd1;
                                else stat_lsu_pipe_load_hit_count <= stat_lsu_pipe_load_hit_count + 64'd1;
                                if (req_write_r) begin
                                    stat_lsu_pipe_store_hit_latency_sum <= stat_lsu_pipe_store_hit_latency_sum + req_latency_done;
                                    stat_lsu_pipe_store_hit_latency_count <= stat_lsu_pipe_store_hit_latency_count + 64'd1;
                                    if (req_latency_done > stat_lsu_pipe_store_hit_latency_max) begin
                                        stat_lsu_pipe_store_hit_latency_max <= req_latency_done;
                                    end
                                end else begin
                                    stat_lsu_pipe_load_hit_latency_sum <= stat_lsu_pipe_load_hit_latency_sum + req_latency_done;
                                    stat_lsu_pipe_load_hit_latency_count <= stat_lsu_pipe_load_hit_latency_count + 64'd1;
                                    if (req_latency_done > stat_lsu_pipe_load_hit_latency_max) begin
                                        stat_lsu_pipe_load_hit_latency_max <= req_latency_done;
                                    end
                                end
                            end
                            state_r <= S_IDLE;
`ifdef NPC_LSU_PIPE_DBG
                            $display("[LSUPipeDbg] resp seq=%0d vaddr=0x%08x data=0x%08x hit=%0d miss=%0d",
                                pipe_resp_seq, pipe_resp_vaddr, pipe_resp_rdata, pipe_resp_hit, pipe_resp_miss);
`endif
                        end
                    end
                end else if (state_r == S_SLOW_WAIT) begin
                    if (slow_resp_fire) begin
                        cpu_resp_valid <= 1'b1;
                        cpu_resp_rdata <= slow_resp_rdata;
                        cpu_resp_exc_valid <= slow_resp_exc_valid;
                        cpu_resp_exc_cause <= slow_resp_exc_cause;
                        cpu_resp_exc_tval <= slow_resp_exc_tval;
                        if (slow_resp_exc_valid) begin
                            stat_page_fault_count <= stat_page_fault_count + 64'd1;
                            stat_lsu_pipe_fault_count <= stat_lsu_pipe_fault_count + 64'd1;
                        end
                        stat_data_resp_count <= stat_data_resp_count + 64'd1;
                        stat_lsu_pipe_slow_fallback_latency_sum <= stat_lsu_pipe_slow_fallback_latency_sum + req_latency_done;
                        stat_lsu_pipe_slow_fallback_latency_count <= stat_lsu_pipe_slow_fallback_latency_count + 64'd1;
                        if (req_latency_done > stat_lsu_pipe_slow_fallback_latency_max) begin
                            stat_lsu_pipe_slow_fallback_latency_max <= req_latency_done;
                        end
                        if (req_slow_replay_r) begin
                            stat_lsu_pipe_slow_replay_latency_sum <= stat_lsu_pipe_slow_replay_latency_sum + req_latency_done;
                            stat_lsu_pipe_slow_replay_latency_count <= stat_lsu_pipe_slow_replay_latency_count + 64'd1;
                            if (req_latency_done > stat_lsu_pipe_slow_replay_latency_max) begin
                                stat_lsu_pipe_slow_replay_latency_max <= req_latency_done;
                            end
                        end else begin
                            stat_lsu_pipe_slow_direct_latency_sum <= stat_lsu_pipe_slow_direct_latency_sum + req_latency_done;
                            stat_lsu_pipe_slow_direct_latency_count <= stat_lsu_pipe_slow_direct_latency_count + 64'd1;
                            if (req_latency_done > stat_lsu_pipe_slow_direct_latency_max) begin
                                stat_lsu_pipe_slow_direct_latency_max <= req_latency_done;
                            end
                        end
                        state_r <= S_IDLE;
                    end
                end
            end
        end
    end
endmodule
