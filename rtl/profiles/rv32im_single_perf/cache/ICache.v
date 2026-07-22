`timescale 1ns / 1ps

module ICache #(
    parameter integer LINE_BYTES = 32,
    parameter integer LINE_COUNT = 64,
    parameter [31:0] UNCACHED_BASE = 32'ha0000000,
    parameter [31:0] UNCACHED_MASK = 32'hf0000000
) (
    input clk,
    input rst_n,
    input flush,

    input cpu_req_valid,
    output cpu_req_ready,
    input [31:0] cpu_req_addr,

    output reg cpu_resp_valid,
    input cpu_resp_ready,
    output [31:0] cpu_resp_rdata,

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
    output reg [63:0] stat_refill_bypass
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
    reg refill_drop_r;
`ifdef NPC_ASIC
    reg [SET_BITS-1:0] init_set_r;
`endif

    wire cpu_req_fire = cpu_req_valid && cpu_req_ready;
    wire cpu_resp_fire = cpu_resp_valid && cpu_resp_ready;
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

    // Refill bypass detection: CPU hits same set+tag+way as the inflight refill
    wire refill_same_tag_way0 = refill_same_set && (cpu_req_tag == tag_r) && !victim_way_r;
    wire refill_same_tag_way1 = refill_same_set && (cpu_req_tag == tag_r) && victim_way_r;
    wire refill_bypass_avail_w0 = refill_same_tag_way0 && refill_buf_valid_w0[cpu_req_word];
    wire refill_bypass_avail_w1 = refill_same_tag_way1 && refill_buf_valid_w1[cpu_req_word];
    wire refill_bypass_hit = refill_bypass_avail_w0 || refill_bypass_avail_w1;
    wire refill_bypass_way = refill_bypass_avail_w1;

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
    wire dmem_rd_cmd = (state == S_IDLE || state == S_REFILL_WAIT) &&
        cpu_req_fire && !cpu_req_uncached && cpu_req_hit && !refill_bypass_hit;
    wire dmem_rd_way = cpu_req_hit_way;
    wire [SET_WORD_ADDR_BITS-1:0] dmem_raddr = cpu_req_set_word;
    wire dmem_ren_w0 = dmem_rd_cmd && !dmem_rd_way;
    wire dmem_ren_w1 = dmem_rd_cmd && dmem_rd_way;

    wire [31:0] dmem_rdata_w0;
    wire [31:0] dmem_rdata_w1;

    // CPU ready: allow firing in S_IDLE, or in S_REFILL_WAIT for hits
    // on non-conflicting lines (different set / tag) or bypass hits
    wire refill_same_way_w0 = (state == S_REFILL_WAIT) && refill_same_tag_way0;
    wire refill_same_way_w1 = (state == S_REFILL_WAIT) && refill_same_tag_way1;
    wire refill_conflict = (refill_same_way_w0 && !refill_buf_valid_w0[cpu_req_word]) ||
                           (refill_same_way_w1 && !refill_buf_valid_w1[cpu_req_word]);
    wire cpu_can_fire_during_refill = (cpu_req_hit || refill_bypass_hit) && !refill_conflict;
    wire cpu_can_fire = (state == S_IDLE) ||
        ((state == S_REFILL_WAIT) && cpu_can_fire_during_refill);

    assign cpu_req_ready = cpu_can_fire && (!cpu_resp_valid || cpu_resp_ready);

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
            refill_drop_r <= 1'b0;
            refill_buf_valid_w0 <= {LINE_WORDS{1'b0}};
            refill_buf_valid_w1 <= {LINE_WORDS{1'b0}};
            cpu_resp_valid <= 1'b0;
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
            stat_access <= 64'd0;
            stat_hit <= 64'd0;
            stat_miss <= 64'd0;
            stat_refill_req <= 64'd0;
            stat_refill_resp <= 64'd0;
            stat_refill_bypass <= 64'd0;
`endif
`endif
        end else begin
            if (flush) begin
                for (reset_i = 0; reset_i < SET_COUNT; reset_i = reset_i + 1) begin
                    valid_mem_w0[reset_i] <= 1'b0;
                    valid_mem_w1[reset_i] <= 1'b0;
                end
                refill_buf_valid_w0 <= {LINE_WORDS{1'b0}};
                refill_buf_valid_w1 <= {LINE_WORDS{1'b0}};
                cpu_resp_valid <= 1'b0;
                hit_resp_pending <= 1'b0;
                hit_bypass <= 1'b0;
                if ((state == S_REFILL_REQ) || (state == S_REFILL_WAIT)) begin
                    refill_drop_r <= 1'b1;
                end
            end

            if (cpu_resp_fire) begin
                cpu_resp_valid <= 1'b0;
                hit_resp_pending <= 1'b0;
                hit_bypass <= 1'b0;
            end

`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
            if (cpu_req_fire)   stat_access <= stat_access + 64'd1;
            if (lower_req_fire && (state == S_REFILL_REQ))
                stat_refill_req <= stat_refill_req + 64'd1;
            if (lower_resp_fire && (state == S_REFILL_WAIT))
                stat_refill_resp <= stat_refill_resp + 64'd1;
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
                    if (cpu_req_fire) begin
                        addr_r <= cpu_req_addr;
                        line_base_r <= cpu_req_line_base;
                        set_r <= cpu_req_set;
                        word_r <= cpu_req_word;
                        tag_r <= cpu_req_tag;
                        victim_way_r <= cpu_req_victim_way;
                        if (cpu_req_uncached) begin
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
                    if (!refill_drop_r && cpu_req_fire && (cpu_req_hit || refill_bypass_hit) && !cpu_req_uncached) begin
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
                        if (!refill_drop_r) begin
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
                                cpu_resp_rdata_r <= lower_resp_rdata;
                                cpu_resp_valid <= 1'b1;
                                hit_resp_pending <= 1'b0;
                            end
                        end

                        if (refill_last) begin
                            if (!refill_drop_r) begin
                                if (!victim_way_r) begin
                                    tag_mem_w0[set_r] <= tag_r;
                                    valid_mem_w0[set_r] <= 1'b1;
                                end else begin
                                    tag_mem_w1[set_r] <= tag_r;
                                    valid_mem_w1[set_r] <= 1'b1;
                                end
                            end
                            lru_mem[set_r] <= victim_way_r ? 1'b0 : 1'b1;
                            refill_buf_valid_w0 <= {LINE_WORDS{1'b0}};
                            refill_buf_valid_w1 <= {LINE_WORDS{1'b0}};
                            refill_drop_r <= 1'b0;
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
                        cpu_resp_rdata_r <= lower_resp_rdata;
                        cpu_resp_valid <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                S_RESP: begin
                    if (cpu_resp_fire) state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase

        end
    end

    CacheDataArray1R1W #(
        .ADDR_WIDTH(SET_WORD_ADDR_BITS),
        .DATA_WIDTH(32),
        .DEPTH(SET_WORDS),
        .WSTRB_WIDTH(4)
    ) u_imem_w0 (
        .clk(clk),
        .ren(dmem_ren_w0),
        .raddr(dmem_raddr),
        .rdata(dmem_rdata_w0),
        .wen(dmem_wen_w0),
        .waddr(dmem_waddr),
        .wdata(dmem_wdata),
        .wstrb(4'b1111)
    );

    CacheDataArray1R1W #(
        .ADDR_WIDTH(SET_WORD_ADDR_BITS),
        .DATA_WIDTH(32),
        .DEPTH(SET_WORDS),
        .WSTRB_WIDTH(4)
    ) u_imem_w1 (
        .clk(clk),
        .ren(dmem_ren_w1),
        .raddr(dmem_raddr),
        .rdata(dmem_rdata_w1),
        .wen(dmem_wen_w1),
        .waddr(dmem_waddr),
        .wdata(dmem_wdata),
        .wstrb(4'b1111)
    );

    wire unused_addr_r = |addr_r;
endmodule
