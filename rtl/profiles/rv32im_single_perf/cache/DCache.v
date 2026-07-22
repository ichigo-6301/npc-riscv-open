`timescale 1ns / 1ps

module DCache #(
    parameter integer LINE_BYTES = 32,
    parameter integer LINE_COUNT = 64,
    parameter [31:0] UNCACHED_BASE = 32'ha0000000,
    parameter [31:0] UNCACHED_MASK = 32'hf0000000
) (
    input clk,
    input rst_n,

    input cpu_req_valid,
    output cpu_req_ready,
    input cpu_req_write,
    input [31:0] cpu_req_addr,
    input [31:0] cpu_req_wdata,
    input [3:0] cpu_req_wstrb,
    input [2:0] cpu_req_len,

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
    output reg [63:0] stat_load_access,
    output reg [63:0] stat_store_access,
    output reg [63:0] stat_load_hit,
    output reg [63:0] stat_load_miss,
    output reg [63:0] stat_store_hit,
    output reg [63:0] stat_store_miss,
    output reg [63:0] stat_refill_req,
    output reg [63:0] stat_refill_resp,
    output reg [63:0] stat_write_req,
    output reg [63:0] stat_write_resp,
    output reg [63:0] stat_refill_ld_bypass,
    output reg [63:0] stat_refill_store_merge
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

`ifdef NPC_DCACHE_WRITE_BACK
    localparam integer CFG_WRITE_BACK = `NPC_DCACHE_WRITE_BACK;
`else
    localparam integer CFG_WRITE_BACK = 1;
`endif
`ifdef NPC_DCACHE_WRITE_ALLOCATE
    localparam integer CFG_WRITE_ALLOCATE = `NPC_DCACHE_WRITE_ALLOCATE;
`else
    localparam integer CFG_WRITE_ALLOCATE = 1;
`endif

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
    localparam [WORD_BITS-1:0] WB_LAST_WORD = {WORD_BITS{1'b1}};
    localparam [SET_BITS-1:0] INIT_LAST_SET = {SET_BITS{1'b1}};

    localparam [3:0] S_IDLE = 4'd0;
    localparam [3:0] S_WB_REQ = 4'd1;
    localparam [3:0] S_WB_WAIT = 4'd2;
    localparam [3:0] S_REFILL_REQ = 4'd3;
    localparam [3:0] S_REFILL_WAIT = 4'd4;
    localparam [3:0] S_WT_REQ = 4'd5;
    localparam [3:0] S_WT_WAIT = 4'd6;
    localparam [3:0] S_UNCACHED_REQ = 4'd7;
    localparam [3:0] S_UNCACHED_WAIT = 4'd8;
    localparam [3:0] S_RESP = 4'd9;
    localparam [3:0] S_INIT = 4'd10;
    localparam [3:0] S_WB_READ = 4'd11;

    reg [3:0] state;

    reg valid_mem_w0 [0:SET_COUNT-1];
    reg valid_mem_w1 [0:SET_COUNT-1];
    reg dirty_mem_w0 [0:SET_COUNT-1];
    reg dirty_mem_w1 [0:SET_COUNT-1];
    reg lru_mem [0:SET_COUNT-1];
    reg [TAG_BITS-1:0] tag_mem_w0 [0:SET_COUNT-1];
    reg [TAG_BITS-1:0] tag_mem_w1 [0:SET_COUNT-1];

    // Refill line buffer: holds incoming refill data for CPU bypass / store merge
    reg [31:0] refill_line_buf_w0 [0:LINE_WORDS-1];
    reg [31:0] refill_line_buf_w1 [0:LINE_WORDS-1];
    reg [LINE_WORDS-1:0] refill_buf_valid_w0;
    reg [LINE_WORDS-1:0] refill_buf_valid_w1;

    // Pending store: a store hit the refilling line BEFORE its target word arrived
    reg [31:0] pending_store_wdata;
    reg [3:0]  pending_store_wstrb;
    reg pending_store_valid;

    reg req_write_r;
    reg [31:0] addr_r;
    reg [31:0] line_base_r;
    reg [31:0] wdata_r;
    reg [3:0] wstrb_r;
    reg [2:0] len_r;
    reg [SET_BITS-1:0] set_r;
    reg [WORD_BITS-1:0] word_r;
    reg [TAG_BITS-1:0] tag_r;
    reg victim_way_r;
    reg [TAG_BITS-1:0] victim_tag_r;
    reg [WORD_BITS-1:0] wb_word_r;
    reg [WORD_BITS-1:0] refill_word_r;
    reg [31:0] refill_hit_word_data_r;
    reg [31:0] cpu_resp_rdata_r;
    reg hit_resp_pending;
    reg hit_read_way_r;
    reg hit_bypass;
    reg hit_bypass_way_r;
    reg [WORD_BITS-1:0] bypass_word_r;  // word index of bypassed request
`ifdef NPC_ASIC
    reg [SET_BITS-1:0] init_set_r;
`endif

    wire write_back_en = (CFG_WRITE_BACK != 0);
    wire write_allocate_en = (CFG_WRITE_ALLOCATE != 0);

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

    wire in_refill = (state == S_REFILL_WAIT);

    wire cpu_req_valid0 = valid_mem_w0[cpu_req_set];
    wire cpu_req_valid1 = valid_mem_w1[cpu_req_set];
    wire cpu_req_dirty0 = dirty_mem_w0[cpu_req_set];
    wire cpu_req_dirty1 = dirty_mem_w1[cpu_req_set];
    wire [TAG_BITS-1:0] cpu_req_tag0 = tag_mem_w0[cpu_req_set];
    wire [TAG_BITS-1:0] cpu_req_tag1 = tag_mem_w1[cpu_req_set];
    // During refill, victim way data is being overwritten word-by-word.
    // Mask victim-way tag-hit to avoid "old tag + new data" false hit window.
    wire refill_victim_hit_mask_w0 = in_refill && (cpu_req_set == set_r) && !victim_way_r;
    wire refill_victim_hit_mask_w1 = in_refill && (cpu_req_set == set_r) &&  victim_way_r;
    wire cpu_req_hit0 = cpu_req_valid0 && (cpu_req_tag0 == cpu_req_tag) && !refill_victim_hit_mask_w0;
    wire cpu_req_hit1 = cpu_req_valid1 && (cpu_req_tag1 == cpu_req_tag) && !refill_victim_hit_mask_w1;
    wire cpu_req_hit = cpu_req_hit0 || cpu_req_hit1;
    wire cpu_req_hit_way = cpu_req_hit1;
    wire cpu_req_victim_way =
        !cpu_req_valid0 ? 1'b0 :
        !cpu_req_valid1 ? 1'b1 :
        lru_mem[cpu_req_set];
    wire cpu_req_victim_valid = cpu_req_victim_way ? cpu_req_valid1 : cpu_req_valid0;
    wire cpu_req_victim_dirty = cpu_req_victim_way ? cpu_req_dirty1 : cpu_req_dirty0;
    wire [TAG_BITS-1:0] cpu_req_victim_tag = cpu_req_victim_way ? cpu_req_tag1 : cpu_req_tag0;

    // Refill bypass / store merge detection
    wire refill_same_set = in_refill && (cpu_req_set == set_r);
    wire refill_same_tag_w0 = refill_same_set && (cpu_req_tag == tag_r) && !victim_way_r;
    wire refill_same_tag_w1 = refill_same_set && (cpu_req_tag == tag_r) && victim_way_r;
    // Load bypass available if the requested word is already in the refill buffer
    wire refill_ld_bypass_w0 = refill_same_tag_w0 && refill_buf_valid_w0[cpu_req_word];
    wire refill_ld_bypass_w1 = refill_same_tag_w1 && refill_buf_valid_w1[cpu_req_word];
    wire refill_ld_bypass_avail = refill_ld_bypass_w0 || refill_ld_bypass_w1;
    wire refill_ld_bypass_way = refill_ld_bypass_w1;
    // Store merge: CPU store hits the refilling line
    wire refill_st_merge = in_refill && refill_same_set && cpu_req_write &&
        ((refill_same_tag_w0 && hit_resp_pending && !hit_read_way_r) || (refill_same_tag_w1 && hit_resp_pending && hit_read_way_r));

    wire [31:0] dmem_rdata_w0;
    wire [31:0] dmem_rdata_w1;

    wire wb_req_valid = (state == S_WB_REQ);
    wire [SET_WORD_ADDR_BITS-1:0] wb_set_word = {set_r, wb_word_r};
    wire [31:0] wb_addr = {victim_tag_r, set_r, wb_word_r, 2'b00};
    wire [31:0] wb_data = victim_way_r ? dmem_rdata_w1 : dmem_rdata_w0;
    wire wb_last = (wb_word_r == WB_LAST_WORD);
    wire [WORD_BITS-1:0] wb_word_next = wb_word_r + {{(WORD_BITS-1){1'b0}}, 1'b1};

    wire [WORD_BITS-1:0] refill_word_next =
        (refill_word_r == REFILL_LAST_WORD) ? {WORD_BITS{1'b0}} :
        (refill_word_r + {{(WORD_BITS-1){1'b0}}, 1'b1});
    wire refill_last = (refill_word_next == word_r);
    wire [SET_WORD_ADDR_BITS-1:0] refill_set_word = {set_r, refill_word_r};
    wire refill_store_merge = req_write_r && (refill_word_r == word_r);

    // Refill word data: apply pending store or in-flight store merge
    wire [31:0] wmask_r = {
        {8{wstrb_r[3]}}, {8{wstrb_r[2]}}, {8{wstrb_r[1]}}, {8{wstrb_r[0]}}
    };
    wire [31:0] pending_wmask = {
        {8{pending_store_wstrb[3]}}, {8{pending_store_wstrb[2]}},
        {8{pending_store_wstrb[1]}}, {8{pending_store_wstrb[0]}}
    };
    wire [31:0] refill_word_raw = lower_resp_rdata;
    reg [31:0] refill_word_data;
    always @(*) begin
        if (pending_store_valid && (refill_word_r == word_r))
            refill_word_data = (pending_store_wdata & pending_wmask) | (refill_word_raw & ~pending_wmask);
        else if (refill_store_merge)
            refill_word_data = (wdata_r & wmask_r) | (refill_word_raw & ~wmask_r);
        else
            refill_word_data = refill_word_raw;
    end

    // --- Data memory port assignment ---
    // Port A (write): store-hit + refill writes
    wire dmem_wr_hit = (state == S_IDLE) && cpu_req_fire && !cpu_req_uncached && cpu_req_hit && cpu_req_write;
    wire dmem_wr_refill = in_refill && lower_resp_fire;
    // Select write payload by phase (IDLE/store-hit vs REFILL) so write-data
    // path does not depend on address-driven hit compare logic.
    wire dmem_wr_from_refill = in_refill;
    wire dmem_way = dmem_wr_from_refill ? victim_way_r : cpu_req_hit_way;
    wire [SET_WORD_ADDR_BITS-1:0] dmem_waddr = dmem_wr_from_refill ? refill_set_word : cpu_req_set_word;
    wire [31:0] dmem_wdata = dmem_wr_from_refill ? refill_word_data : cpu_req_wdata;
    wire [3:0] dmem_wstrb_raw = dmem_wr_from_refill ? 4'b1111 : cpu_req_wstrb;
    // Generate per-way write strobes directly. This keeps WEBWE generation
    // from depending on an extra shared enable->gate stage.
    wire dmem_wen_w0 = dmem_wr_from_refill ? (dmem_wr_refill && !victim_way_r) : (dmem_wr_hit && !cpu_req_hit_way);
    wire dmem_wen_w1 = dmem_wr_from_refill ? (dmem_wr_refill &&  victim_way_r) : (dmem_wr_hit &&  cpu_req_hit_way);
    wire [3:0] dmem_wstrb_w0 = dmem_wen_w0 ? dmem_wstrb_raw : 4'b0000;
    wire [3:0] dmem_wstrb_w1 = dmem_wen_w1 ? dmem_wstrb_raw : 4'b0000;

    // Port B (read): CPU loads + writeback reads
    wire dmem_rd_cmd = (state == S_IDLE || state == S_REFILL_WAIT) &&
        cpu_req_fire && !cpu_req_uncached && cpu_req_hit && !cpu_req_write && !refill_ld_bypass_avail;
    wire dmem_rd_wb = (state == S_WB_READ);
    wire dmem_rd_cmd_any = dmem_rd_cmd || dmem_rd_wb;
    wire dmem_rd_way = dmem_rd_cmd ? cpu_req_hit_way : victim_way_r;
    wire [SET_WORD_ADDR_BITS-1:0] dmem_raddr = dmem_rd_cmd ? cpu_req_set_word : wb_set_word;
    wire dmem_ren_w0 = dmem_rd_cmd_any && !dmem_rd_way;
    wire dmem_ren_w1 = dmem_rd_cmd_any && dmem_rd_way;

    // CPU ready: in S_IDLE, or in S_REFILL_WAIT for loads to non-conflicting lines
    wire refill_same_way_w0 = (state == S_REFILL_WAIT) && refill_same_tag_w0;
    wire refill_same_way_w1 = (state == S_REFILL_WAIT) && refill_same_tag_w1;
    wire refill_conflict = (refill_same_way_w0 && !refill_buf_valid_w0[cpu_req_word]) ||
                           (refill_same_way_w1 && !refill_buf_valid_w1[cpu_req_word]);
    wire cpu_can_fire_during_refill = !cpu_req_write &&
        ((cpu_req_hit && !refill_conflict) || refill_ld_bypass_avail);
    wire cpu_can_fire = (state == S_IDLE) ||
        ((state == S_REFILL_WAIT) && cpu_can_fire_during_refill);
    // Allow accepting a new request in the same cycle when the previous
    // response is being consumed, matching ICache pipelined handshake style.
    assign cpu_req_ready = cpu_can_fire && (!cpu_resp_valid || cpu_resp_ready);

    wire refill_req_valid = (state == S_REFILL_REQ);
    wire wt_req_valid = (state == S_WT_REQ);
    wire unc_req_valid = (state == S_UNCACHED_REQ);
    assign lower_req_valid = refill_req_valid || wb_req_valid || wt_req_valid || unc_req_valid;
    assign lower_req_write = wb_req_valid || wt_req_valid || (unc_req_valid && req_write_r);
    // Refill uses miss address so AXI WRAP burst can return critical word first.
    assign lower_req_addr = wb_req_valid ? wb_addr : addr_r;
    assign lower_req_wdata = wb_req_valid ? wb_data : ((wt_req_valid || unc_req_valid) ? wdata_r : 32'b0);
    assign lower_req_wstrb = wb_req_valid ? 4'b1111 : ((wt_req_valid || unc_req_valid) ? wstrb_r : 4'b0);
    assign lower_req_len = refill_req_valid ? 3'd0 : (wb_req_valid ? 3'd0 : len_r);
    assign lower_resp_ready = (state == S_WB_WAIT) || in_refill || (state == S_WT_WAIT) || (state == S_UNCACHED_WAIT);

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
            dirty_mem_w0[reset_i] = 1'b0;
            dirty_mem_w1[reset_i] = 1'b0;
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
            req_write_r <= 1'b0;
            addr_r <= 32'b0;
            line_base_r <= 32'b0;
            wdata_r <= 32'b0;
            wstrb_r <= 4'b0;
            len_r <= 3'd4;
            set_r <= {SET_BITS{1'b0}};
            word_r <= {WORD_BITS{1'b0}};
            tag_r <= {TAG_BITS{1'b0}};
            victim_way_r <= 1'b0;
            victim_tag_r <= {TAG_BITS{1'b0}};
            wb_word_r <= {WORD_BITS{1'b0}};
            refill_word_r <= {WORD_BITS{1'b0}};
            refill_hit_word_data_r <= 32'b0;
            hit_resp_pending <= 1'b0;
            hit_read_way_r <= 1'b0;
            hit_bypass <= 1'b0;
            hit_bypass_way_r <= 1'b0;
            bypass_word_r <= {WORD_BITS{1'b0}};
            refill_buf_valid_w0 <= {LINE_WORDS{1'b0}};
            refill_buf_valid_w1 <= {LINE_WORDS{1'b0}};
            pending_store_valid <= 1'b0;
            pending_store_wdata <= 32'b0;
            pending_store_wstrb <= 4'b0;
            cpu_resp_valid <= 1'b0;
            cpu_resp_rdata_r <= 32'b0;
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
            stat_access <= 64'd0;
            stat_load_access <= 64'd0;
            stat_store_access <= 64'd0;
            stat_load_hit <= 64'd0;
            stat_load_miss <= 64'd0;
            stat_store_hit <= 64'd0;
            stat_store_miss <= 64'd0;
            stat_refill_req <= 64'd0;
            stat_refill_resp <= 64'd0;
            stat_write_req <= 64'd0;
            stat_write_resp <= 64'd0;
            stat_refill_ld_bypass <= 64'd0;
            stat_refill_store_merge <= 64'd0;
`endif
`endif
        end else begin
            if (cpu_resp_fire) begin
                cpu_resp_valid <= 1'b0;
                hit_resp_pending <= 1'b0;
                hit_bypass <= 1'b0;
            end

`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
            if (cpu_req_fire) begin
                stat_access <= stat_access + 64'd1;
                if (cpu_req_write) stat_store_access <= stat_store_access + 64'd1;
                else stat_load_access <= stat_load_access + 64'd1;
            end
            if (lower_req_fire) begin
                if (state == S_REFILL_REQ) stat_refill_req <= stat_refill_req + 64'd1;
                else if (state == S_WB_REQ || state == S_WT_REQ || (state == S_UNCACHED_REQ && req_write_r))
                    stat_write_req <= stat_write_req + 64'd1;
            end
            if (lower_resp_fire) begin
                if (state == S_REFILL_WAIT) stat_refill_resp <= stat_refill_resp + 64'd1;
                else if (state == S_WB_WAIT || state == S_WT_WAIT || (state == S_UNCACHED_WAIT && req_write_r))
                    stat_write_resp <= stat_write_resp + 64'd1;
            end
`endif
`endif

            case (state)
`ifdef NPC_ASIC
                S_INIT: begin
                    valid_mem_w0[init_set_r] <= 1'b0;
                    valid_mem_w1[init_set_r] <= 1'b0;
                    dirty_mem_w0[init_set_r] <= 1'b0;
                    dirty_mem_w1[init_set_r] <= 1'b0;
                    lru_mem[init_set_r] <= 1'b0;
                    if (init_set_r == INIT_LAST_SET) state <= S_IDLE;
                    else init_set_r <= init_set_r + {{(SET_BITS-1){1'b0}}, 1'b1};
                end
`endif

                S_IDLE: begin
                    if (cpu_req_fire) begin
                        req_write_r <= cpu_req_write;
                        addr_r <= cpu_req_addr;
                        line_base_r <= cpu_req_line_base;
                        wdata_r <= cpu_req_wdata;
                        wstrb_r <= cpu_req_wstrb;
                        len_r <= cpu_req_len;
                        set_r <= cpu_req_set;
                        word_r <= cpu_req_word;
                        tag_r <= cpu_req_tag;
                        victim_way_r <= cpu_req_victim_way;
                        victim_tag_r <= cpu_req_victim_tag;

                        if (cpu_req_uncached) begin
                            state <= S_UNCACHED_REQ;
                        end else if (cpu_req_hit) begin
                            lru_mem[cpu_req_set] <= cpu_req_hit0 ? 1'b1 : 1'b0;
                            if (cpu_req_write) begin
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
                                stat_store_hit <= stat_store_hit + 64'd1;
`endif
`endif
                                if (write_back_en) begin
                                    if (!cpu_req_hit_way) dirty_mem_w0[cpu_req_set] <= 1'b1;
                                    else                  dirty_mem_w1[cpu_req_set] <= 1'b1;
                                    cpu_resp_valid <= 1'b1;
                                    state <= S_IDLE;
                                end else begin
                                    state <= S_WT_REQ;
                                end
                            end else begin
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
                                stat_load_hit <= stat_load_hit + 64'd1;
`endif
`endif
                                hit_read_way_r <= cpu_req_hit_way;
                                cpu_resp_valid <= 1'b1;
                                hit_resp_pending <= 1'b1;
                            end
                        end else begin
                            // Miss
                            if (cpu_req_write) begin
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
                                stat_store_miss <= stat_store_miss + 64'd1;
`endif
`endif
                                if (!write_allocate_en) begin
                                    state <= S_WT_REQ;
                                end else begin
                                    refill_word_r <= cpu_req_word;
                                    refill_hit_word_data_r <= 32'b0;
                                    refill_buf_valid_w0 <= {LINE_WORDS{1'b0}};
                                    refill_buf_valid_w1 <= {LINE_WORDS{1'b0}};
                                    pending_store_valid <= 1'b0;
                                    if (write_back_en && cpu_req_victim_valid && cpu_req_victim_dirty) begin
                                        wb_word_r <= {WORD_BITS{1'b0}};
                                        state <= S_WB_READ;
                                    end else begin
                                        state <= S_REFILL_REQ;
                                    end
                                end
                            end else begin
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
                                stat_load_miss <= stat_load_miss + 64'd1;
`endif
`endif
                                refill_word_r <= cpu_req_word;
                                refill_hit_word_data_r <= 32'b0;
                                refill_buf_valid_w0 <= {LINE_WORDS{1'b0}};
                                refill_buf_valid_w1 <= {LINE_WORDS{1'b0}};
                                pending_store_valid <= 1'b0;
                                if (write_back_en && cpu_req_victim_valid && cpu_req_victim_dirty) begin
                                    wb_word_r <= {WORD_BITS{1'b0}};
                                    state <= S_WB_READ;
                                end else begin
                                    state <= S_REFILL_REQ;
                                end
                            end
                        end
                    end
                end

                S_WB_READ: state <= S_WB_REQ;

                S_WB_REQ: begin
                    if (lower_req_fire) begin
                        if (wb_last) state <= S_WB_WAIT;
                        else begin wb_word_r <= wb_word_next; state <= S_WB_READ; end
                    end
                end

                S_WB_WAIT: begin
                    if (lower_resp_fire) begin
                        if (!victim_way_r) dirty_mem_w0[set_r] <= 1'b0;
                        else               dirty_mem_w1[set_r] <= 1'b0;
                        refill_word_r <= word_r;
                        refill_hit_word_data_r <= 32'b0;
                        state <= S_REFILL_REQ;
                    end
                end

                S_REFILL_REQ: begin
                    if (lower_req_fire) state <= S_REFILL_WAIT;
                end

                S_REFILL_WAIT: begin
                    // Load hit during refill: bypass from buffer or serve from data_mem
                    if (cpu_req_fire && !cpu_req_write && !cpu_req_uncached &&
                        (cpu_req_hit || refill_ld_bypass_avail)) begin
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
                        stat_load_hit <= stat_load_hit + 64'd1;
`endif
`endif
                        lru_mem[cpu_req_set] <= cpu_req_hit0 ? 1'b1 : 1'b0;
                        if (refill_ld_bypass_avail) begin
`ifdef NPC_USE_DPI
`ifdef NPC_CACHE_STAT
                            stat_refill_ld_bypass <= stat_refill_ld_bypass + 64'd1;
`endif
`endif
                            hit_bypass <= 1'b1;
                            hit_bypass_way_r <= refill_ld_bypass_way;
                            bypass_word_r <= cpu_req_word;
                        end else begin
                            hit_read_way_r <= cpu_req_hit_way;
                            hit_resp_pending <= 1'b1;
                        end
                        cpu_resp_valid <= 1'b1;
                    end

                    if (lower_resp_fire) begin
                        // Store in refill line buffer
                        if (!victim_way_r) begin
                            refill_line_buf_w0[refill_word_r] <= refill_word_data;
                            refill_buf_valid_w0[refill_word_r] <= 1'b1;
                        end else begin
                            refill_line_buf_w1[refill_word_r] <= refill_word_data;
                            refill_buf_valid_w1[refill_word_r] <= 1'b1;
                        end

                        // Clear pending store after its target word arrives
                        if (pending_store_valid && refill_word_r == word_r)
                            pending_store_valid <= 1'b0;

                        // Capture the requested word for response.
                        // For load misses: respond immediately so CPU can continue.
                        if (refill_word_r == word_r) begin
                            refill_hit_word_data_r <= refill_word_data;
                            if (!req_write_r) begin
                                cpu_resp_rdata_r <= refill_word_data;
                                cpu_resp_valid <= 1'b1;
                                hit_resp_pending <= 1'b0;
                            end
                        end

                        if (refill_last) begin
                            if (!victim_way_r) begin
                                tag_mem_w0[set_r] <= tag_r;
                                valid_mem_w0[set_r] <= 1'b1;
                                dirty_mem_w0[set_r] <= req_write_r && write_back_en;
                            end else begin
                                tag_mem_w1[set_r] <= tag_r;
                                valid_mem_w1[set_r] <= 1'b1;
                                dirty_mem_w1[set_r] <= req_write_r && write_back_en;
                            end
                            lru_mem[set_r] <= victim_way_r ? 1'b0 : 1'b1;
                            refill_buf_valid_w0 <= {LINE_WORDS{1'b0}};
                            refill_buf_valid_w1 <= {LINE_WORDS{1'b0}};
                            pending_store_valid <= 1'b0;

                            if (req_write_r) begin
                                if (write_back_en) begin
                                    cpu_resp_valid <= 1'b1;
                                    state <= S_IDLE;
                                end else begin
                                    state <= S_WT_REQ;
                                end
                            end else begin
                                // Load miss: already responded at critical word arrival
                                state <= S_IDLE;
                            end
                        end else begin
                            refill_word_r <= refill_word_next;
                        end
                    end
                end

                S_WT_REQ: begin
                    if (lower_req_fire) state <= S_WT_WAIT;
                end

                S_WT_WAIT: begin
                    if (lower_resp_fire) begin
                        cpu_resp_valid <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                S_UNCACHED_REQ: begin
                    if (lower_req_fire) state <= S_UNCACHED_WAIT;
                end

                S_UNCACHED_WAIT: begin
                    if (lower_resp_fire) begin
                        cpu_resp_rdata_r <= req_write_r ? 32'b0 : lower_resp_rdata;
                        cpu_resp_valid <= 1'b1;
                        hit_resp_pending <= 1'b0;
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
    ) u_dmem_w0 (
        .clk(clk),
        .ren(dmem_ren_w0),
        .raddr(dmem_raddr),
        .rdata(dmem_rdata_w0),
        .wen(dmem_wen_w0),
        .waddr(dmem_waddr),
        .wdata(dmem_wdata),
        .wstrb(dmem_wstrb_w0)
    );

    CacheDataArray1R1W #(
        .ADDR_WIDTH(SET_WORD_ADDR_BITS),
        .DATA_WIDTH(32),
        .DEPTH(SET_WORDS),
        .WSTRB_WIDTH(4)
    ) u_dmem_w1 (
        .clk(clk),
        .ren(dmem_ren_w1),
        .raddr(dmem_raddr),
        .rdata(dmem_rdata_w1),
        .wen(dmem_wen_w1),
        .waddr(dmem_waddr),
        .wdata(dmem_wdata),
        .wstrb(dmem_wstrb_w1)
    );

endmodule
