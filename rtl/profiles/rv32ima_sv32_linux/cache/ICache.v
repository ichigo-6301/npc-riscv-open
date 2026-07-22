`timescale 1ns / 1ps

module ICache #(
    parameter integer LINE_BYTES = 32,
    parameter integer LINE_COUNT = 64,
    parameter [31:0] UNCACHED_BASE = 32'ha0000000,
    parameter [31:0] UNCACHED_MASK = 32'hf0000000
) (
    input clk,
    input rst_n,
    input maint_inv_req,
    output reg maint_inv_done,

    input cpu_req_valid,
    output cpu_req_ready,
    input [31:0] cpu_req_addr,
    output cpu_req_lookup_hit,
    output cpu_req_lookup_uncached,

    output reg cpu_resp_valid,
    input cpu_resp_ready,
    output [31:0] cpu_resp_rdata,

    input pipe_req_valid,
    output pipe_req_ready,
    input [31:0] pipe_req_paddr,
    input [31:0] pipe_req_vaddr,
    input [31:0] pipe_req_pc,
    input [31:0] pipe_req_seq,
    input [15:0] pipe_req_epoch,
    input pipe_req_pred_taken,
    input [31:0] pipe_req_pred_target,
    input pipe_req_pred_btb_hit,
    input pipe_req_pred_btb_is_cond,
    input [1:0] pipe_req_pred_bht_state,
    input [31:0] pipe_req_pred_pht_idx,
    input [1:0] pipe_req_priv,
    input pipe_req_exception_valid,
    input [31:0] pipe_req_exception_cause,
    input [31:0] pipe_req_exception_tval,

    output reg pipe_resp_valid,
    input pipe_resp_ready,
    output reg [31:0] pipe_resp_instr,
    output reg [31:0] pipe_resp_pc,
    output reg [31:0] pipe_resp_seq,
    output reg [15:0] pipe_resp_epoch,
    output reg pipe_resp_pred_taken,
    output reg [31:0] pipe_resp_pred_target,
    output reg pipe_resp_pred_btb_hit,
    output reg pipe_resp_pred_btb_is_cond,
    output reg [1:0] pipe_resp_pred_bht_state,
    output reg [31:0] pipe_resp_pred_pht_idx,
    output reg pipe_resp_exception_valid,
    output reg [31:0] pipe_resp_exception_cause,
    output reg [31:0] pipe_resp_exception_tval,
    output reg pipe_resp_hit,
    output reg pipe_resp_miss,

    output lower_req_valid,
    input lower_req_ready,
    output lower_req_write,
    output [31:0] lower_req_addr,
    output [31:0] lower_req_wdata,
    output [3:0] lower_req_wstrb,
    output [2:0] lower_req_len,

    input lower_resp_valid,
    output lower_resp_ready,
    input [31:0] lower_resp_rdata
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
    ,
    output reg [63:0] stat_access,
    output reg [63:0] stat_hit,
    output reg [63:0] stat_miss,
    output reg [63:0] stat_refill_req,
    output reg [63:0] stat_refill_resp,
    output reg [63:0] stat_refill_bypass,
    output reg [63:0] stat_req_wait_cycle,
    output reg [63:0] stat_hit_resp_wait_cycle,
    output reg [63:0] stat_miss_wait_cycle,
    output reg [63:0] stat_uncached_access,
    output reg [63:0] stat_pipe_req_valid_cycle,
    output reg [63:0] stat_pipe_req_ready_cycle,
    output reg [63:0] stat_pipe_req_fire_cycle,
    output reg [63:0] stat_pipe_req_valid_not_ready_cycle,
    output reg [63:0] stat_pipe_resp_valid_cycle,
    output reg [63:0] stat_pipe_resp_ready_cycle,
    output reg [63:0] stat_pipe_resp_fire_cycle,
    output reg [63:0] stat_pipe_data_valid_cycle,
    output reg [63:0] stat_pipe_resp_block_cycle,
    output reg [63:0] stat_pipe_ready_block_state_cycle,
    output reg [63:0] stat_pipe_ready_block_data_cycle,
    output reg [63:0] stat_pipe_ready_block_resp_cycle,
    output reg [63:0] stat_pipe_ready_block_cpu_cycle,
    output reg [63:0] stat_pipe_ready_block_maint_cycle,
    output reg [63:0] stat_pipe_state_idle_cycle,
    output reg [63:0] stat_pipe_state_refill_cycle,
    output reg [63:0] stat_pipe_state_uncached_cycle,
    output reg [63:0] stat_pipe_hit_fire_cycle,
    output reg [63:0] stat_pipe_miss_fire_cycle,
    output reg [63:0] stat_pipe_refill_busy_cycle,
    output reg [63:0] stat_pipe_resp_fifo_full_cycle
`endif
`endif
);
    function integer clog2;
        input integer value;
        integer tmp;
        begin
            tmp = value - 1;
            for (clog2 = 0; tmp > 0; clog2 = clog2 + 1) begin
                tmp = tmp >> 1;
            end
        end
    endfunction

    localparam integer WAY_NUM = 2;
    localparam integer SET_COUNT = LINE_COUNT / WAY_NUM;
    localparam integer WORD_BYTES = 4;
    localparam integer LINE_WORDS = LINE_BYTES / WORD_BYTES;
    localparam integer OFFSET_BITS = clog2(LINE_BYTES);
    localparam integer WORD_BITS = clog2(LINE_WORDS);
    localparam integer SET_BITS = clog2(SET_COUNT);
    localparam integer TAG_BITS = 32 - OFFSET_BITS - SET_BITS;
    localparam integer SET_WORD_ADDR_BITS = SET_BITS + WORD_BITS;
    localparam integer SET_WORDS = SET_COUNT * LINE_WORDS;
    localparam [WORD_BITS-1:0] REFILL_LAST_WORD = {WORD_BITS{1'b1}};
    localparam [SET_BITS-1:0] INIT_LAST_SET = {SET_BITS{1'b1}};

    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_INIT = 3'd1;
    localparam [2:0] S_REFILL_REQ = 3'd2;
    localparam [2:0] S_REFILL_WAIT = 3'd3;
    localparam [2:0] S_RESP = 3'd4;
    localparam [2:0] S_UNCACHED_REQ = 3'd5;
    localparam [2:0] S_UNCACHED_WAIT = 3'd6;

    reg [2:0] state;

    reg valid_mem_w0 [0:SET_COUNT-1];
    reg valid_mem_w1 [0:SET_COUNT-1];
    reg lru_mem [0:SET_COUNT-1]; // 0->victim way0, 1->victim way1
    reg [TAG_BITS-1:0] tag_mem_w0 [0:SET_COUNT-1];
    reg [TAG_BITS-1:0] tag_mem_w1 [0:SET_COUNT-1];

    // Refill line buffer: holds refill data for bypass to CPU
    reg [31:0] refill_line_buf_w0 [0:LINE_WORDS-1];
    reg [31:0] refill_line_buf_w1 [0:LINE_WORDS-1];
    reg [LINE_WORDS-1:0] refill_buf_valid_w0;
    reg [LINE_WORDS-1:0] refill_buf_valid_w1;

`ifdef NPC_USE_DPI
    (* ram_style = "block" *) reg [31:0] data_mem_w0 [0:SET_WORDS-1];
    (* ram_style = "block" *) reg [31:0] data_mem_w1 [0:SET_WORDS-1];
    reg [SET_WORD_ADDR_BITS-1:0] sim_raddr_w0_r;
    reg [SET_WORD_ADDR_BITS-1:0] sim_raddr_w1_r;
    reg [31:0] sim_rdata_w0_r;
    reg [31:0] sim_rdata_w1_r;
`endif

    reg [31:0] addr_r;
    reg [31:0] line_base_r;
    reg [SET_BITS-1:0] set_r;
    reg [WORD_BITS-1:0] word_r;
    reg [TAG_BITS-1:0] tag_r;
    reg victim_way_r;
    reg [WORD_BITS-1:0] refill_word_r;
    reg [31:0] cpu_resp_rdata_r;
    reg hit_resp_pending;
    reg hit_read_way_r;
    reg hit_bypass;
    reg hit_bypass_way_r;
    reg [WORD_BITS-1:0] bypass_word_r;  // word index of the bypassed CPU request
    reg pipe_data_valid;
    reg pipe_data_way_r;
    reg [31:0] pipe_data_pc_r;
    reg [31:0] pipe_data_seq_r;
    reg [15:0] pipe_data_epoch_r;
    reg pipe_data_pred_taken_r;
    reg [31:0] pipe_data_pred_target_r;
    reg pipe_data_pred_btb_hit_r;
    reg pipe_data_pred_btb_is_cond_r;
    reg [1:0] pipe_data_pred_bht_state_r;
    reg [31:0] pipe_data_pred_pht_idx_r;
    reg pipe_data_exception_valid_r;
    reg [31:0] pipe_data_exception_cause_r;
    reg [31:0] pipe_data_exception_tval_r;
    reg pipe_data_hit_r;
    reg pipe_data_miss_r;
    reg slow_owner_pipe_r;
    reg [31:0] pipe_slow_pc_r;
    reg [31:0] pipe_slow_seq_r;
    reg [15:0] pipe_slow_epoch_r;
    reg pipe_slow_pred_taken_r;
    reg [31:0] pipe_slow_pred_target_r;
    reg pipe_slow_pred_btb_hit_r;
    reg pipe_slow_pred_btb_is_cond_r;
    reg [1:0] pipe_slow_pred_bht_state_r;
    reg [31:0] pipe_slow_pred_pht_idx_r;
`ifdef NPC_ASIC
    reg [SET_BITS-1:0] init_set_r;
`endif

    wire cpu_req_fire = cpu_req_valid && cpu_req_ready;
    wire cpu_resp_fire = cpu_resp_valid && cpu_resp_ready;
    wire pipe_req_fire = pipe_req_valid && pipe_req_ready;
    wire pipe_resp_fire = pipe_resp_valid && pipe_resp_ready;
    wire lower_req_fire = lower_req_valid && lower_req_ready;
    wire lower_resp_fire = lower_resp_valid && lower_resp_ready;

    wire [SET_BITS-1:0] cpu_req_set = cpu_req_addr[OFFSET_BITS + SET_BITS - 1:OFFSET_BITS];
    wire [WORD_BITS-1:0] cpu_req_word = cpu_req_addr[OFFSET_BITS - 1:2];
    wire [TAG_BITS-1:0] cpu_req_tag = cpu_req_addr[31:OFFSET_BITS + SET_BITS];
    wire [SET_WORD_ADDR_BITS-1:0] cpu_req_set_word = {cpu_req_set, cpu_req_word};
    wire [31:0] cpu_req_line_base = {cpu_req_addr[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
    wire cpu_req_uncached = ((cpu_req_addr & UNCACHED_MASK) == UNCACHED_BASE);

    wire cpu_req_valid0 = valid_mem_w0[cpu_req_set];
    wire cpu_req_valid1 = valid_mem_w1[cpu_req_set];
    wire [TAG_BITS-1:0] cpu_req_tag0 = tag_mem_w0[cpu_req_set];
    wire [TAG_BITS-1:0] cpu_req_tag1 = tag_mem_w1[cpu_req_set];
    wire refill_same_set = (state == S_REFILL_WAIT) && (cpu_req_set == set_r);
    wire refill_victim_hit_mask_w0 = refill_same_set && !victim_way_r;
    wire refill_victim_hit_mask_w1 = refill_same_set && victim_way_r;
    wire cpu_req_hit0 = cpu_req_valid0 && (cpu_req_tag0 == cpu_req_tag) && !refill_victim_hit_mask_w0;
    wire cpu_req_hit1 = cpu_req_valid1 && (cpu_req_tag1 == cpu_req_tag) && !refill_victim_hit_mask_w1;
    wire cpu_req_hit = cpu_req_hit0 || cpu_req_hit1;
    wire cpu_req_hit_way = cpu_req_hit1;
    wire cpu_req_victim_way =
        !cpu_req_valid0 ? 1'b0 :
        !cpu_req_valid1 ? 1'b1 :
        lru_mem[cpu_req_set];

    wire [SET_BITS-1:0] pipe_req_set = pipe_req_paddr[OFFSET_BITS + SET_BITS - 1:OFFSET_BITS];
    wire [WORD_BITS-1:0] pipe_req_word = pipe_req_paddr[OFFSET_BITS - 1:2];
    wire [TAG_BITS-1:0] pipe_req_tag = pipe_req_paddr[31:OFFSET_BITS + SET_BITS];
    wire [SET_WORD_ADDR_BITS-1:0] pipe_req_set_word = {pipe_req_set, pipe_req_word};
    wire [31:0] pipe_req_line_base = {pipe_req_paddr[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
    wire pipe_req_uncached = ((pipe_req_paddr & UNCACHED_MASK) == UNCACHED_BASE);
    wire pipe_req_valid0 = valid_mem_w0[pipe_req_set];
    wire pipe_req_valid1 = valid_mem_w1[pipe_req_set];
    wire [TAG_BITS-1:0] pipe_req_tag0 = tag_mem_w0[pipe_req_set];
    wire [TAG_BITS-1:0] pipe_req_tag1 = tag_mem_w1[pipe_req_set];
    wire pipe_req_hit0 = pipe_req_valid0 && (pipe_req_tag0 == pipe_req_tag);
    wire pipe_req_hit1 = pipe_req_valid1 && (pipe_req_tag1 == pipe_req_tag);
    wire pipe_req_hit = pipe_req_hit0 || pipe_req_hit1;
    wire pipe_req_hit_way = pipe_req_hit1;
    wire pipe_req_victim_way =
        !pipe_req_valid0 ? 1'b0 :
        !pipe_req_valid1 ? 1'b1 :
        lru_mem[pipe_req_set];

    // Refill bypass detection: CPU hits same set+tag+way as the inflight refill
    wire refill_same_tag_way0 = refill_same_set && (cpu_req_tag == tag_r) && !victim_way_r;
    wire refill_same_tag_way1 = refill_same_set && (cpu_req_tag == tag_r) && victim_way_r;
    wire refill_bypass_avail_w0 = refill_same_tag_way0 && refill_buf_valid_w0[cpu_req_word];
    wire refill_bypass_avail_w1 = refill_same_tag_way1 && refill_buf_valid_w1[cpu_req_word];
    wire refill_bypass_hit = refill_bypass_avail_w0 || refill_bypass_avail_w1;
    wire refill_bypass_way = refill_bypass_avail_w1;

    assign cpu_req_lookup_hit = cpu_req_hit || refill_bypass_hit;
    assign cpu_req_lookup_uncached = cpu_req_uncached;

    wire [WORD_BITS-1:0] refill_word_next =
        (refill_word_r == REFILL_LAST_WORD) ? {WORD_BITS{1'b0}} :
        (refill_word_r + {{(WORD_BITS-1){1'b0}}, 1'b1});
    wire refill_last = (refill_word_next == word_r);
    wire [SET_WORD_ADDR_BITS-1:0] refill_set_word = {set_r, refill_word_r};

    // Port A (write): refill data written to data_mem as each word arrives
    wire dmem_wr_refill = (state == S_REFILL_WAIT) && lower_resp_fire;
    wire [SET_WORD_ADDR_BITS-1:0] dmem_waddr = refill_set_word;
    wire [31:0] dmem_wdata = lower_resp_rdata;
    wire dmem_wen_w0 = dmem_wr_refill && !victim_way_r;
    wire dmem_wen_w1 = dmem_wr_refill && victim_way_r;

    // Port B (read): CPU reads from data_mem (not for bypass hits)
    wire cpu_dmem_rd_cmd = (state == S_IDLE || state == S_REFILL_WAIT) &&
        cpu_req_fire && !cpu_req_uncached && cpu_req_hit && !refill_bypass_hit;
    wire pipe_dmem_rd_cmd = (state == S_IDLE) && pipe_req_fire &&
        !pipe_req_exception_valid && !pipe_req_uncached && pipe_req_hit;
    wire dmem_rd_cmd = cpu_dmem_rd_cmd || pipe_dmem_rd_cmd;
    wire dmem_rd_way = pipe_dmem_rd_cmd ? pipe_req_hit_way : cpu_req_hit_way;
    wire [SET_WORD_ADDR_BITS-1:0] dmem_raddr =
        pipe_dmem_rd_cmd ? pipe_req_set_word : cpu_req_set_word;
    wire dmem_ren_w0 = dmem_rd_cmd && !dmem_rd_way;
    wire dmem_ren_w1 = dmem_rd_cmd && dmem_rd_way;

`ifdef NPC_USE_DPI
    wire [31:0] dmem_rdata_w0 = sim_rdata_w0_r;
    wire [31:0] dmem_rdata_w1 = sim_rdata_w1_r;
`else
    wire [31:0] dmem_rdata_w0;
    wire [31:0] dmem_rdata_w1;
`endif

    // CPU ready: allow firing in S_IDLE, or in S_REFILL_WAIT for hits
    // on non-conflicting lines (different set / tag) or bypass hits
    wire refill_same_way_w0 = (state == S_REFILL_WAIT) && refill_same_tag_way0;
    wire refill_same_way_w1 = (state == S_REFILL_WAIT) && refill_same_tag_way1;
    wire refill_conflict = (refill_same_way_w0 && !refill_buf_valid_w0[cpu_req_word]) ||
                           (refill_same_way_w1 && !refill_buf_valid_w1[cpu_req_word]);
    wire cpu_can_fire_during_refill = (cpu_req_hit || refill_bypass_hit) && !refill_conflict;
    wire cpu_can_fire = (state == S_IDLE) ||
        ((state == S_REFILL_WAIT) && cpu_can_fire_during_refill);

    assign cpu_req_ready = cpu_can_fire && (!cpu_resp_valid || cpu_resp_ready) &&
        !maint_inv_req && !pipe_req_valid;

    wire pipe_resp_allowin = !pipe_resp_valid || pipe_resp_ready;
    wire pipe_data_allowin = !pipe_data_valid || pipe_resp_allowin;
    wire pipe_req_fast_path = pipe_req_exception_valid ||
        (!pipe_req_uncached && pipe_req_hit);
    wire pipe_slow_accept_slot = !pipe_data_valid && !pipe_resp_valid;
    wire pipe_accept_allowin = pipe_req_fast_path ? pipe_data_allowin : pipe_slow_accept_slot;
    wire pipe_ready_block_state = (state != S_IDLE);
    wire pipe_ready_block_data = (state == S_IDLE) && !pipe_accept_allowin &&
        (pipe_req_fast_path || pipe_data_valid);
    wire pipe_ready_block_resp = (state == S_IDLE) && !pipe_accept_allowin &&
        (!pipe_req_fast_path || !pipe_resp_allowin || pipe_resp_valid);
    wire pipe_ready_block_maint = (state == S_IDLE) && pipe_data_allowin && maint_inv_req;
    wire pipe_ready_block_cpu = (state == S_IDLE) && pipe_accept_allowin &&
        !maint_inv_req && cpu_req_valid;
    assign pipe_req_ready = (state == S_IDLE) && pipe_accept_allowin &&
        !maint_inv_req && !cpu_req_valid;

    assign lower_req_valid = (state == S_REFILL_REQ) || (state == S_UNCACHED_REQ);
    assign lower_req_write = 1'b0;
    // Refill uses miss address so AXI WRAP burst can return critical word first.
    assign lower_req_addr = addr_r;
    assign lower_req_wdata = 32'b0;
    assign lower_req_wstrb = 4'b0;
    assign lower_req_len = (state == S_UNCACHED_REQ) ? 3'd4 : 3'd0;
    assign lower_resp_ready = (state == S_REFILL_WAIT) || (state == S_UNCACHED_WAIT);

    // Response data: bypass from refill buffer, or from data_mem
    wire [31:0] dmem_rd_result = hit_read_way_r ? dmem_rdata_w1 : dmem_rdata_w0;
    reg [31:0] resp_data;
    always @(*) begin
        if (hit_bypass)
            resp_data = hit_bypass_way_r ? refill_line_buf_w1[bypass_word_r] : refill_line_buf_w0[bypass_word_r];
        else if (hit_resp_pending)
            resp_data = dmem_rd_result;
        else
            resp_data = cpu_resp_rdata_r;
    end
    assign cpu_resp_rdata = resp_data;

    integer reset_i;

`ifndef NPC_ASIC
    initial begin
        for (reset_i = 0; reset_i < SET_COUNT; reset_i = reset_i + 1) begin
            valid_mem_w0[reset_i] = 1'b0;
            valid_mem_w1[reset_i] = 1'b0;
            lru_mem[reset_i] = 1'b0;
        end
    end
`endif

    always @(posedge clk) begin
        if (!rst_n) begin
`ifdef NPC_ASIC
            state <= S_INIT;
            init_set_r <= {SET_BITS{1'b0}};
`else
            state <= S_IDLE;
`endif
            addr_r <= 32'b0;
            line_base_r <= 32'b0;
            set_r <= {SET_BITS{1'b0}};
            word_r <= {WORD_BITS{1'b0}};
            tag_r <= {TAG_BITS{1'b0}};
            victim_way_r <= 1'b0;
            refill_word_r <= {WORD_BITS{1'b0}};
            cpu_resp_rdata_r <= 32'b0;
            hit_resp_pending <= 1'b0;
            hit_read_way_r <= 1'b0;
            hit_bypass <= 1'b0;
            hit_bypass_way_r <= 1'b0;
            bypass_word_r <= {WORD_BITS{1'b0}};
            pipe_data_valid <= 1'b0;
            pipe_data_way_r <= 1'b0;
            pipe_data_pc_r <= 32'b0;
            pipe_data_seq_r <= 32'b0;
            pipe_data_epoch_r <= 16'b0;
            pipe_data_pred_taken_r <= 1'b0;
            pipe_data_pred_target_r <= 32'b0;
            pipe_data_pred_btb_hit_r <= 1'b0;
            pipe_data_pred_btb_is_cond_r <= 1'b0;
            pipe_data_pred_bht_state_r <= 2'b0;
            pipe_data_pred_pht_idx_r <= 32'b0;
            pipe_data_exception_valid_r <= 1'b0;
            pipe_data_exception_cause_r <= 32'b0;
            pipe_data_exception_tval_r <= 32'b0;
            pipe_data_hit_r <= 1'b0;
            pipe_data_miss_r <= 1'b0;
            slow_owner_pipe_r <= 1'b0;
            pipe_slow_pc_r <= 32'b0;
            pipe_slow_seq_r <= 32'b0;
            pipe_slow_epoch_r <= 16'b0;
            pipe_slow_pred_taken_r <= 1'b0;
            pipe_slow_pred_target_r <= 32'b0;
            pipe_slow_pred_btb_hit_r <= 1'b0;
            pipe_slow_pred_btb_is_cond_r <= 1'b0;
            pipe_slow_pred_bht_state_r <= 2'b0;
            pipe_slow_pred_pht_idx_r <= 32'b0;
            refill_buf_valid_w0 <= {LINE_WORDS{1'b0}};
            refill_buf_valid_w1 <= {LINE_WORDS{1'b0}};
            maint_inv_done <= 1'b0;
`ifdef NPC_USE_DPI
            sim_raddr_w0_r <= {SET_WORD_ADDR_BITS{1'b0}};
            sim_raddr_w1_r <= {SET_WORD_ADDR_BITS{1'b0}};
            sim_rdata_w0_r <= 32'b0;
            sim_rdata_w1_r <= 32'b0;
`endif
            cpu_resp_valid <= 1'b0;
            pipe_resp_valid <= 1'b0;
            pipe_resp_instr <= 32'b0;
            pipe_resp_pc <= 32'b0;
            pipe_resp_seq <= 32'b0;
            pipe_resp_epoch <= 16'b0;
            pipe_resp_pred_taken <= 1'b0;
            pipe_resp_pred_target <= 32'b0;
            pipe_resp_pred_btb_hit <= 1'b0;
            pipe_resp_pred_btb_is_cond <= 1'b0;
            pipe_resp_pred_bht_state <= 2'b0;
            pipe_resp_pred_pht_idx <= 32'b0;
            pipe_resp_exception_valid <= 1'b0;
            pipe_resp_exception_cause <= 32'b0;
            pipe_resp_exception_tval <= 32'b0;
            pipe_resp_hit <= 1'b0;
            pipe_resp_miss <= 1'b0;
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
            stat_access <= 64'd0;
            stat_hit <= 64'd0;
            stat_miss <= 64'd0;
            stat_refill_req <= 64'd0;
            stat_refill_resp <= 64'd0;
            stat_refill_bypass <= 64'd0;
            stat_req_wait_cycle <= 64'd0;
            stat_hit_resp_wait_cycle <= 64'd0;
            stat_miss_wait_cycle <= 64'd0;
            stat_uncached_access <= 64'd0;
            stat_pipe_req_valid_cycle <= 64'd0;
            stat_pipe_req_ready_cycle <= 64'd0;
            stat_pipe_req_fire_cycle <= 64'd0;
            stat_pipe_req_valid_not_ready_cycle <= 64'd0;
            stat_pipe_resp_valid_cycle <= 64'd0;
            stat_pipe_resp_ready_cycle <= 64'd0;
            stat_pipe_resp_fire_cycle <= 64'd0;
            stat_pipe_data_valid_cycle <= 64'd0;
            stat_pipe_resp_block_cycle <= 64'd0;
            stat_pipe_ready_block_state_cycle <= 64'd0;
            stat_pipe_ready_block_data_cycle <= 64'd0;
            stat_pipe_ready_block_resp_cycle <= 64'd0;
            stat_pipe_ready_block_cpu_cycle <= 64'd0;
            stat_pipe_ready_block_maint_cycle <= 64'd0;
            stat_pipe_state_idle_cycle <= 64'd0;
            stat_pipe_state_refill_cycle <= 64'd0;
            stat_pipe_state_uncached_cycle <= 64'd0;
            stat_pipe_hit_fire_cycle <= 64'd0;
            stat_pipe_miss_fire_cycle <= 64'd0;
            stat_pipe_refill_busy_cycle <= 64'd0;
            stat_pipe_resp_fifo_full_cycle <= 64'd0;
`endif
`endif
        end else begin
            if (maint_inv_done && !maint_inv_req) begin
                maint_inv_done <= 1'b0;
            end
            if (cpu_resp_fire) begin
                cpu_resp_valid <= 1'b0;
                hit_resp_pending <= 1'b0;
                hit_bypass <= 1'b0;
            end
            if (pipe_resp_fire) begin
                pipe_resp_valid <= 1'b0;
                pipe_resp_exception_valid <= 1'b0;
                pipe_resp_hit <= 1'b0;
                pipe_resp_miss <= 1'b0;
            end
            if (pipe_resp_allowin && pipe_data_valid) begin
                pipe_resp_valid <= 1'b1;
                pipe_resp_instr <= pipe_data_exception_valid_r ? 32'b0 :
                    (pipe_data_way_r ? dmem_rdata_w1 : dmem_rdata_w0);
                pipe_resp_pc <= pipe_data_pc_r;
                pipe_resp_seq <= pipe_data_seq_r;
                pipe_resp_epoch <= pipe_data_epoch_r;
                pipe_resp_pred_taken <= pipe_data_pred_taken_r;
                pipe_resp_pred_target <= pipe_data_pred_target_r;
                pipe_resp_pred_btb_hit <= pipe_data_pred_btb_hit_r;
                pipe_resp_pred_btb_is_cond <= pipe_data_pred_btb_is_cond_r;
                pipe_resp_pred_bht_state <= pipe_data_pred_bht_state_r;
                pipe_resp_pred_pht_idx <= pipe_data_pred_pht_idx_r;
                pipe_resp_exception_valid <= pipe_data_exception_valid_r;
                pipe_resp_exception_cause <= pipe_data_exception_cause_r;
                pipe_resp_exception_tval <= pipe_data_exception_tval_r;
                pipe_resp_hit <= pipe_data_hit_r;
                pipe_resp_miss <= pipe_data_miss_r;
                pipe_data_valid <= 1'b0;
            end

`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
            if (cpu_req_fire || pipe_req_fire) stat_access <= stat_access + 64'd1;
            if ((cpu_req_valid && !cpu_req_ready) || (pipe_req_valid && !pipe_req_ready))
                stat_req_wait_cycle <= stat_req_wait_cycle + 64'd1;
            if (((cpu_resp_valid && !cpu_resp_ready) || (pipe_resp_valid && !pipe_resp_ready)) &&
                (state == S_IDLE || state == S_REFILL_WAIT))
                stat_hit_resp_wait_cycle <= stat_hit_resp_wait_cycle + 64'd1;
            if ((state == S_REFILL_REQ) || (state == S_REFILL_WAIT))
                stat_miss_wait_cycle <= stat_miss_wait_cycle + 64'd1;
            if (lower_req_fire && (state == S_REFILL_REQ))
                stat_refill_req <= stat_refill_req + 64'd1;
            if (lower_resp_fire && (state == S_REFILL_WAIT))
                stat_refill_resp <= stat_refill_resp + 64'd1;
            if (pipe_req_valid)
                stat_pipe_req_valid_cycle <= stat_pipe_req_valid_cycle + 64'd1;
            if (pipe_req_ready)
                stat_pipe_req_ready_cycle <= stat_pipe_req_ready_cycle + 64'd1;
            if (pipe_req_fire)
                stat_pipe_req_fire_cycle <= stat_pipe_req_fire_cycle + 64'd1;
            if (pipe_req_valid && !pipe_req_ready)
                stat_pipe_req_valid_not_ready_cycle <= stat_pipe_req_valid_not_ready_cycle + 64'd1;
            if (pipe_resp_valid)
                stat_pipe_resp_valid_cycle <= stat_pipe_resp_valid_cycle + 64'd1;
            if (pipe_resp_ready)
                stat_pipe_resp_ready_cycle <= stat_pipe_resp_ready_cycle + 64'd1;
            if (pipe_resp_fire)
                stat_pipe_resp_fire_cycle <= stat_pipe_resp_fire_cycle + 64'd1;
            if (pipe_data_valid)
                stat_pipe_data_valid_cycle <= stat_pipe_data_valid_cycle + 64'd1;
            if (pipe_resp_valid && !pipe_resp_ready)
                stat_pipe_resp_block_cycle <= stat_pipe_resp_block_cycle + 64'd1;
            if (pipe_req_valid && !pipe_req_ready && pipe_ready_block_state)
                stat_pipe_ready_block_state_cycle <= stat_pipe_ready_block_state_cycle + 64'd1;
            if (pipe_req_valid && !pipe_req_ready && pipe_ready_block_data)
                stat_pipe_ready_block_data_cycle <= stat_pipe_ready_block_data_cycle + 64'd1;
            if (pipe_req_valid && !pipe_req_ready && pipe_ready_block_resp)
                stat_pipe_ready_block_resp_cycle <= stat_pipe_ready_block_resp_cycle + 64'd1;
            if (pipe_req_valid && !pipe_req_ready && pipe_ready_block_cpu)
                stat_pipe_ready_block_cpu_cycle <= stat_pipe_ready_block_cpu_cycle + 64'd1;
            if (pipe_req_valid && !pipe_req_ready && pipe_ready_block_maint)
                stat_pipe_ready_block_maint_cycle <= stat_pipe_ready_block_maint_cycle + 64'd1;
            if (state == S_IDLE)
                stat_pipe_state_idle_cycle <= stat_pipe_state_idle_cycle + 64'd1;
            if ((state == S_REFILL_REQ) || (state == S_REFILL_WAIT))
                stat_pipe_state_refill_cycle <= stat_pipe_state_refill_cycle + 64'd1;
            if ((state == S_UNCACHED_REQ) || (state == S_UNCACHED_WAIT))
                stat_pipe_state_uncached_cycle <= stat_pipe_state_uncached_cycle + 64'd1;
            if (pipe_req_fire && !pipe_req_exception_valid && !pipe_req_uncached && pipe_req_hit)
                stat_pipe_hit_fire_cycle <= stat_pipe_hit_fire_cycle + 64'd1;
            if (pipe_req_fire && !pipe_req_exception_valid && !pipe_req_uncached && !pipe_req_hit)
                stat_pipe_miss_fire_cycle <= stat_pipe_miss_fire_cycle + 64'd1;
            if ((state == S_REFILL_REQ) || (state == S_REFILL_WAIT))
                stat_pipe_refill_busy_cycle <= stat_pipe_refill_busy_cycle + 64'd1;
            if (pipe_data_valid && pipe_resp_valid && !pipe_resp_ready)
                stat_pipe_resp_fifo_full_cycle <= stat_pipe_resp_fifo_full_cycle + 64'd1;
`endif
`endif

            case (state)
`ifdef NPC_ASIC
                S_INIT: begin
                    valid_mem_w0[init_set_r] <= 1'b0;
                    valid_mem_w1[init_set_r] <= 1'b0;
                    lru_mem[init_set_r] <= 1'b0;
                    if (init_set_r == INIT_LAST_SET)
                        state <= S_IDLE;
                    else
                        init_set_r <= init_set_r + {{(SET_BITS-1){1'b0}}, 1'b1};
                end
`endif

                S_IDLE: begin
                    if (maint_inv_req && !maint_inv_done) begin
                        for (reset_i = 0; reset_i < SET_COUNT; reset_i = reset_i + 1) begin
                            valid_mem_w0[reset_i] <= 1'b0;
                            valid_mem_w1[reset_i] <= 1'b0;
                            lru_mem[reset_i] <= 1'b0;
                        end
                        refill_buf_valid_w0 <= {LINE_WORDS{1'b0}};
                        refill_buf_valid_w1 <= {LINE_WORDS{1'b0}};
                        hit_resp_pending <= 1'b0;
                        hit_bypass <= 1'b0;
                        cpu_resp_valid <= 1'b0;
                        pipe_data_valid <= 1'b0;
                        pipe_resp_valid <= 1'b0;
                        pipe_resp_exception_valid <= 1'b0;
                        slow_owner_pipe_r <= 1'b0;
                        maint_inv_done <= 1'b1;
                    end else if (pipe_req_fire) begin
                        addr_r <= pipe_req_paddr;
                        line_base_r <= pipe_req_line_base;
                        set_r <= pipe_req_set;
                        word_r <= pipe_req_word;
                        tag_r <= pipe_req_tag;
                        victim_way_r <= pipe_req_victim_way;
                        slow_owner_pipe_r <= 1'b0;
                        if (pipe_req_exception_valid) begin
                            pipe_data_valid <= 1'b1;
                            pipe_data_way_r <= 1'b0;
                            pipe_data_pc_r <= pipe_req_pc;
                            pipe_data_seq_r <= pipe_req_seq;
                            pipe_data_epoch_r <= pipe_req_epoch;
                            pipe_data_pred_taken_r <= pipe_req_pred_taken;
                            pipe_data_pred_target_r <= pipe_req_pred_target;
                            pipe_data_pred_btb_hit_r <= pipe_req_pred_btb_hit;
                            pipe_data_pred_btb_is_cond_r <= pipe_req_pred_btb_is_cond;
                            pipe_data_pred_bht_state_r <= pipe_req_pred_bht_state;
                            pipe_data_pred_pht_idx_r <= pipe_req_pred_pht_idx;
                            pipe_data_exception_valid_r <= 1'b1;
                            pipe_data_exception_cause_r <= pipe_req_exception_cause;
                            pipe_data_exception_tval_r <= pipe_req_exception_tval;
                            pipe_data_hit_r <= 1'b0;
                            pipe_data_miss_r <= 1'b0;
                        end else if (pipe_req_uncached) begin
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
                            stat_uncached_access <= stat_uncached_access + 64'd1;
`endif
`endif
                            slow_owner_pipe_r <= 1'b1;
                            pipe_slow_pc_r <= pipe_req_pc;
                            pipe_slow_seq_r <= pipe_req_seq;
                            pipe_slow_epoch_r <= pipe_req_epoch;
                            pipe_slow_pred_taken_r <= pipe_req_pred_taken;
                            pipe_slow_pred_target_r <= pipe_req_pred_target;
                            pipe_slow_pred_btb_hit_r <= pipe_req_pred_btb_hit;
                            pipe_slow_pred_btb_is_cond_r <= pipe_req_pred_btb_is_cond;
                            pipe_slow_pred_bht_state_r <= pipe_req_pred_bht_state;
                            pipe_slow_pred_pht_idx_r <= pipe_req_pred_pht_idx;
                            state <= S_UNCACHED_REQ;
                        end else if (pipe_req_hit) begin
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
                            stat_hit <= stat_hit + 64'd1;
`endif
`endif
                            lru_mem[pipe_req_set] <= pipe_req_hit0 ? 1'b1 : 1'b0;
                            pipe_data_valid <= 1'b1;
                            pipe_data_way_r <= pipe_req_hit_way;
                            pipe_data_pc_r <= pipe_req_pc;
                            pipe_data_seq_r <= pipe_req_seq;
                            pipe_data_epoch_r <= pipe_req_epoch;
                            pipe_data_pred_taken_r <= pipe_req_pred_taken;
                            pipe_data_pred_target_r <= pipe_req_pred_target;
                            pipe_data_pred_btb_hit_r <= pipe_req_pred_btb_hit;
                            pipe_data_pred_btb_is_cond_r <= pipe_req_pred_btb_is_cond;
                            pipe_data_pred_bht_state_r <= pipe_req_pred_bht_state;
                            pipe_data_pred_pht_idx_r <= pipe_req_pred_pht_idx;
                            pipe_data_exception_valid_r <= 1'b0;
                            pipe_data_exception_cause_r <= 32'b0;
                            pipe_data_exception_tval_r <= 32'b0;
                            pipe_data_hit_r <= 1'b1;
                            pipe_data_miss_r <= 1'b0;
                        end else begin
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
                            stat_miss <= stat_miss + 64'd1;
`endif
`endif
                            slow_owner_pipe_r <= 1'b1;
                            pipe_slow_pc_r <= pipe_req_pc;
                            pipe_slow_seq_r <= pipe_req_seq;
                            pipe_slow_epoch_r <= pipe_req_epoch;
                            pipe_slow_pred_taken_r <= pipe_req_pred_taken;
                            pipe_slow_pred_target_r <= pipe_req_pred_target;
                            pipe_slow_pred_btb_hit_r <= pipe_req_pred_btb_hit;
                            pipe_slow_pred_btb_is_cond_r <= pipe_req_pred_btb_is_cond;
                            pipe_slow_pred_bht_state_r <= pipe_req_pred_bht_state;
                            pipe_slow_pred_pht_idx_r <= pipe_req_pred_pht_idx;
                            refill_word_r <= pipe_req_word;
                            refill_buf_valid_w0 <= {LINE_WORDS{1'b0}};
                            refill_buf_valid_w1 <= {LINE_WORDS{1'b0}};
                            state <= S_REFILL_REQ;
                        end
                    end else if (cpu_req_fire) begin
                        addr_r <= cpu_req_addr;
                        line_base_r <= cpu_req_line_base;
                        set_r <= cpu_req_set;
                        word_r <= cpu_req_word;
                        tag_r <= cpu_req_tag;
                        victim_way_r <= cpu_req_victim_way;
                        if (cpu_req_uncached) begin
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
                            stat_uncached_access <= stat_uncached_access + 64'd1;
`endif
`endif
                            state <= S_UNCACHED_REQ;
                        end else if (cpu_req_hit) begin
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
                            stat_hit <= stat_hit + 64'd1;
`endif
`endif
                            lru_mem[cpu_req_set] <= cpu_req_hit0 ? 1'b1 : 1'b0;
                            hit_read_way_r <= cpu_req_hit_way;
                            cpu_resp_valid <= 1'b1;
                            hit_resp_pending <= 1'b1;
                        end else begin
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
                            stat_miss <= stat_miss + 64'd1;
`endif
`endif
                            refill_word_r <= cpu_req_word;
                            refill_buf_valid_w0 <= {LINE_WORDS{1'b0}};
                            refill_buf_valid_w1 <= {LINE_WORDS{1'b0}};
                            state <= S_REFILL_REQ;
                        end
                    end
                end

                S_REFILL_REQ: begin
                    if (lower_req_fire)
                        state <= S_REFILL_WAIT;
                end

                S_REFILL_WAIT: begin
                    // CPU hit on refilling line (bypass) or other set (normal hit)
                    if (cpu_req_fire && (cpu_req_hit || refill_bypass_hit) && !cpu_req_uncached) begin
                        if (refill_bypass_hit) begin
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
                            stat_hit <= stat_hit + 64'd1;
                            stat_refill_bypass <= stat_refill_bypass + 64'd1;
`endif
`endif
                            lru_mem[cpu_req_set] <= cpu_req_hit0 ? 1'b1 : 1'b0;
                            hit_bypass <= 1'b1;
                            hit_bypass_way_r <= refill_bypass_way;
                            bypass_word_r <= cpu_req_word;
                            cpu_resp_valid <= 1'b1;
                        end else begin
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
                            stat_hit <= stat_hit + 64'd1;
`endif
`endif
                            lru_mem[cpu_req_set] <= cpu_req_hit0 ? 1'b1 : 1'b0;
                            hit_read_way_r <= cpu_req_hit_way;
                            cpu_resp_valid <= 1'b1;
                            hit_resp_pending <= 1'b1;
                        end
                        // NOTE: do NOT overwrite word_r / tag_r / set_r here;
                        // the original miss context must be preserved for
                        // refill data capture and final response.
                    end

                    if (lower_resp_fire) begin
                        // Store in refill line buffer for bypass
                        if (!victim_way_r) begin
                            refill_line_buf_w0[refill_word_r] <= lower_resp_rdata;
                            refill_buf_valid_w0[refill_word_r] <= 1'b1;
                        end else begin
                            refill_line_buf_w1[refill_word_r] <= lower_resp_rdata;
                            refill_buf_valid_w1[refill_word_r] <= 1'b1;
                        end

                        // Critical-word-first: respond as soon as the requested
                        // word arrives, so the CPU can proceed immediately
                        if (refill_word_r == word_r) begin
                            if (slow_owner_pipe_r) begin
                                pipe_resp_valid <= 1'b1;
                                pipe_resp_instr <= lower_resp_rdata;
                                pipe_resp_pc <= pipe_slow_pc_r;
                                pipe_resp_seq <= pipe_slow_seq_r;
                                pipe_resp_epoch <= pipe_slow_epoch_r;
                                pipe_resp_pred_taken <= pipe_slow_pred_taken_r;
                                pipe_resp_pred_target <= pipe_slow_pred_target_r;
                                pipe_resp_pred_btb_hit <= pipe_slow_pred_btb_hit_r;
                                pipe_resp_pred_btb_is_cond <= pipe_slow_pred_btb_is_cond_r;
                                pipe_resp_pred_bht_state <= pipe_slow_pred_bht_state_r;
                                pipe_resp_pred_pht_idx <= pipe_slow_pred_pht_idx_r;
                                pipe_resp_exception_valid <= 1'b0;
                                pipe_resp_exception_cause <= 32'b0;
                                pipe_resp_exception_tval <= 32'b0;
                                pipe_resp_hit <= 1'b0;
                                pipe_resp_miss <= 1'b1;
                            end else begin
                                cpu_resp_rdata_r <= lower_resp_rdata;
                                cpu_resp_valid <= 1'b1;
                                hit_resp_pending <= 1'b0;
                            end
                        end

                        if (refill_last) begin
                            if (!victim_way_r) begin
                                tag_mem_w0[set_r] <= tag_r;
                                valid_mem_w0[set_r] <= 1'b1;
                            end else begin
                                tag_mem_w1[set_r] <= tag_r;
                                valid_mem_w1[set_r] <= 1'b1;
                            end
                            lru_mem[set_r] <= victim_way_r ? 1'b0 : 1'b1;
                            refill_buf_valid_w0 <= {LINE_WORDS{1'b0}};
                            refill_buf_valid_w1 <= {LINE_WORDS{1'b0}};
                            slow_owner_pipe_r <= 1'b0;
                            state <= S_IDLE;
                        end else begin
                            refill_word_r <= refill_word_next;
                        end
                    end
                end

                S_UNCACHED_REQ: begin
                    if (lower_req_fire) state <= S_UNCACHED_WAIT;
                end

                S_UNCACHED_WAIT: begin
                    if (lower_resp_fire) begin
                        if (slow_owner_pipe_r) begin
                            pipe_resp_valid <= 1'b1;
                            pipe_resp_instr <= lower_resp_rdata;
                            pipe_resp_pc <= pipe_slow_pc_r;
                            pipe_resp_seq <= pipe_slow_seq_r;
                            pipe_resp_epoch <= pipe_slow_epoch_r;
                            pipe_resp_pred_taken <= pipe_slow_pred_taken_r;
                            pipe_resp_pred_target <= pipe_slow_pred_target_r;
                            pipe_resp_pred_btb_hit <= pipe_slow_pred_btb_hit_r;
                            pipe_resp_pred_btb_is_cond <= pipe_slow_pred_btb_is_cond_r;
                            pipe_resp_pred_bht_state <= pipe_slow_pred_bht_state_r;
                            pipe_resp_pred_pht_idx <= pipe_slow_pred_pht_idx_r;
                            pipe_resp_exception_valid <= 1'b0;
                            pipe_resp_exception_cause <= 32'b0;
                            pipe_resp_exception_tval <= 32'b0;
                            pipe_resp_hit <= 1'b0;
                            pipe_resp_miss <= 1'b1;
                            slow_owner_pipe_r <= 1'b0;
                        end else begin
                            cpu_resp_rdata_r <= lower_resp_rdata;
                            cpu_resp_valid <= 1'b1;
                        end
                        state <= S_IDLE;
                    end
                end

                S_RESP: begin
                    if (cpu_resp_fire) state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase

`ifdef NPC_USE_DPI
            if (dmem_ren_w0) begin
                sim_raddr_w0_r <= dmem_raddr;
                sim_rdata_w0_r <= data_mem_w0[dmem_raddr];
            end
            if (dmem_ren_w1) begin
                sim_raddr_w1_r <= dmem_raddr;
                sim_rdata_w1_r <= data_mem_w1[dmem_raddr];
            end
            if (dmem_wen_w0) data_mem_w0[dmem_waddr] <= dmem_wdata;
            if (dmem_wen_w1) data_mem_w1[dmem_waddr] <= dmem_wdata;
`endif

        end
    end

`ifndef NPC_USE_DPI
    // FPGA: SDPRAM (Simple Dual Port RAM)
    // Port A (write): refill controller writes received data
    // Port B (read): CPU reads data with 1-cycle latency
    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(SET_WORD_ADDR_BITS),
        .ADDR_WIDTH_B(SET_WORD_ADDR_BITS),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(8),
        .CASCADE_HEIGHT(0),
        .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(32 * SET_WORDS),
        .MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_B(32),
        .READ_LATENCY_B(1),
        .READ_RESET_VALUE_B("0"),
        .RST_MODE_A("SYNC"),
        .RST_MODE_B("SYNC"),
        .SIM_ASSERT_CHK(0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT(0),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(32),
        .WRITE_MODE_B("no_change")
    ) u_imem_w0 (
        .dbiterrb(), .doutb(dmem_rdata_w0), .sbiterrb(),
        .addra(dmem_waddr), .addrb(dmem_raddr),
        .clka(clk), .clkb(clk),
        .dina(dmem_wdata), .ena(dmem_wen_w0), .enb(dmem_ren_w0),
        .injectdbiterra(1'b0), .injectsbiterra(1'b0),
        .regceb(1'b1), .rstb(1'b0), .sleep(1'b0),
        .wea(4'b1111)
    );

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A(SET_WORD_ADDR_BITS),
        .ADDR_WIDTH_B(SET_WORD_ADDR_BITS),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(8),
        .CASCADE_HEIGHT(0),
        .CLOCKING_MODE("common_clock"),
        .ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"),
        .MEMORY_INIT_PARAM("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE("block"),
        .MEMORY_SIZE(32 * SET_WORDS),
        .MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_B(32),
        .READ_LATENCY_B(1),
        .READ_RESET_VALUE_B("0"),
        .RST_MODE_A("SYNC"),
        .RST_MODE_B("SYNC"),
        .SIM_ASSERT_CHK(0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT(0),
        .WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(32),
        .WRITE_MODE_B("no_change")
    ) u_imem_w1 (
        .dbiterrb(), .doutb(dmem_rdata_w1), .sbiterrb(),
        .addra(dmem_waddr), .addrb(dmem_raddr),
        .clka(clk), .clkb(clk),
        .dina(dmem_wdata), .ena(dmem_wen_w1), .enb(dmem_ren_w1),
        .injectdbiterra(1'b0), .injectsbiterra(1'b0),
        .regceb(1'b1), .rstb(1'b0), .sleep(1'b0),
        .wea(4'b1111)
    );
`endif

    wire unused_addr_r = |addr_r;
endmodule
