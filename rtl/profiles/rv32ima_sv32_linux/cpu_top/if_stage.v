`timescale 1ns / 1ps

module if_stage #(
    parameter integer BTB_ENTRIES = 128,
    parameter integer BHT_ENTRIES = 128,
    parameter integer BHR_BITS = 8,
    parameter [31:0] RESET_VECTOR = 32'h80000000
) (
    input clk,
    input rst_n,

    input ds_allowin,
    input stop_fetch,
    input pause_fetch,
    input hold_fetch,
    input redirect_flush,
    input stop_clear,
    input [31:0] flush_pc,

    input bpu_update_valid,
    input [31:0] bpu_update_pc,
    input bpu_update_is_cond,
    input bpu_update_taken,
    input [31:0] bpu_update_target,
    input [31:0] bpu_update_pht_idx,

    output fs_to_ds_valid,
    output [31:0] fs_pc,
    output [31:0] fs_instr,
    output fs_exc_valid,
    output [31:0] fs_exc_cause,
    output [31:0] fs_exc_tval,
    output fs_pred_taken,
    output [31:0] fs_pred_target,
    output fs_pred_btb_hit,
    output fs_pred_btb_is_cond,
    output [1:0] fs_pred_bht_state,
    output [31:0] fs_pred_pht_idx,
    output if_stall,

    output ibus_req_valid,
    input ibus_req_ready,
    output [31:0] ibus_req_addr,
    output ibus_req_pred_taken,
    output [31:0] ibus_req_pred_target,
    output ibus_req_pred_btb_hit,
    output ibus_req_pred_btb_is_cond,
    output [1:0] ibus_req_pred_bht_state,
    output [31:0] ibus_req_pred_pht_idx,
    input ibus_resp_valid,
    output ibus_resp_ready,
    input [31:0] ibus_resp_data,
    input ibus_resp_exc_valid,
    input [31:0] ibus_resp_exc_cause,
    input [31:0] ibus_resp_exc_tval
`ifdef NPC_IF_HIT_PIPELINE
    ,
    input [31:0] ibus_resp_pc,
    input [31:0] ibus_resp_seq,
    input [15:0] ibus_resp_epoch,
    input ibus_resp_pred_taken,
    input [31:0] ibus_resp_pred_target,
    input ibus_resp_pred_btb_hit,
    input ibus_resp_pred_btb_is_cond,
    input [1:0] ibus_resp_pred_bht_state,
    input [31:0] ibus_resp_pred_pht_idx
`endif
`ifdef NPC_BRANCH_STAT
    ,
    input flush_trace_is_redirect,
    output fetch_req_trace_valid,
    output [31:0] fetch_req_trace_pc,
    output fetch_accept_trace_valid,
    output [31:0] fetch_accept_trace_pc,
    output [31:0] fetch_accept_trace_instr,
    output fetch_drop_trace_valid,
    output fetch_drop_trace_redirect,
    output [31:0] fetch_drop_trace_pc,
    output [31:0] fetch_drop_trace_instr,
    output [63:0] bpu_btb_lookup_count,
    output [63:0] bpu_btb_hit_count,
    output [63:0] bpu_btb_miss_count,
    output [63:0] bpu_bht_pred_taken_count,
    output [63:0] bpu_bht_pred_not_taken_count,
    output [63:0] bpu_btb_conflict_count,
    output [63:0] bpu_btb_update_count,
    output [63:0] bpu_btb_replace_count,
    output [63:0] bpu_bht_lookup_count,
    output [63:0] bpu_bht_update_count,
    output [63:0] bpu_bht_weak_taken_count,
    output [63:0] bpu_bht_weak_not_taken_count,
    output [63:0] bpu_bht_strong_taken_count,
    output [63:0] bpu_bht_strong_not_taken_count,
    output [31:0] bpu_bhr_value
`endif
`ifdef NPC_PIPE_STAT
    ,
    output if_stat_fs_valid,
    output [1:0] if_stat_queue_count,
    output if_stat_fetch_room,
    output if_stat_req_fire,
    output if_stat_resp_fire,
    output if_stat_resp_accept,
    output if_stat_resp_drop,
    output if_stat_bypass_direct,
    output if_stat_waiting_resp,
    output if_stat_drop_resp,
    output if_stat_fs_pop,
    output if_stat_resp_enq,
    output if_stat_queue_full,
    output if_stat_resp_block
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

    localparam integer BTB_IDX_BITS = clog2(BTB_ENTRIES);
    localparam integer BTB_TAG_BITS = 30 - BTB_IDX_BITS;
    localparam integer BHT_IDX_BITS = clog2(BHT_ENTRIES);
    localparam integer BTB_INIT_LAST_INT = BTB_ENTRIES - 1;
    localparam integer BHT_INIT_LAST_INT = BHT_ENTRIES - 1;
    localparam integer INIT_ENTRIES = (BTB_ENTRIES > BHT_ENTRIES) ? BTB_ENTRIES : BHT_ENTRIES;
    localparam integer INIT_IDX_BITS = clog2(INIT_ENTRIES);
    localparam integer INIT_LAST_INT = INIT_ENTRIES - 1;

    function [BHT_IDX_BITS-1:0] bhr_to_bht_idx;
        input [BHR_BITS-1:0] bhr;
        integer bit_i;
        begin
            bhr_to_bht_idx = {BHT_IDX_BITS{1'b0}};
            for (bit_i = 0; bit_i < BHT_IDX_BITS; bit_i = bit_i + 1) begin
                if (bit_i < BHR_BITS) begin
                    bhr_to_bht_idx[bit_i] = bhr[bit_i];
                end
            end
        end
    endfunction

    function [31:0] bhr_to_u32;
        input [BHR_BITS-1:0] bhr;
        integer bit_i;
        begin
            bhr_to_u32 = 32'b0;
            for (bit_i = 0; bit_i < 32; bit_i = bit_i + 1) begin
                if (bit_i < BHR_BITS) begin
                    bhr_to_u32[bit_i] = bhr[bit_i];
                end
            end
        end
    endfunction

    function [BHR_BITS-1:0] bhr_next_value;
        input [BHR_BITS-1:0] bhr;
        input taken;
        integer bit_i;
        begin
            bhr_next_value = {BHR_BITS{1'b0}};
            bhr_next_value[0] = taken;
            for (bit_i = 1; bit_i < BHR_BITS; bit_i = bit_i + 1) begin
                bhr_next_value[bit_i] = bhr[bit_i-1];
            end
        end
    endfunction

    // FPGA timing note:
    // Keep fetch request generation local to IF. ID-stage hazard/allowin only
    // pops this queue; it must not decide whether next_fetch_pc advances in the
    // same cycle. ASIC routing delay is usually much smaller, so this is mainly
    // an FPGA-friendly implementation tradeoff rather than an ISA-visible change.
    //
    // Redirect handling is intentionally treated as a *timed event* inside IF:
    // EX may assert redirect_flush/flush_pc combinationally, but IF only uses
    // them inside sequential state updates. Wrong-path outstanding responses are
    // dropped locally via drop_resp; IF does not try to cancel cache activity.
    reg [1:0] queue_count;
    reg [31:0] queue_pc0;
    reg [31:0] queue_instr0;
    reg queue_exc_valid0;
    reg [31:0] queue_exc_cause0;
    reg [31:0] queue_exc_tval0;
    reg queue_pred_taken0;
    reg [31:0] queue_pred_target0;
    reg queue_pred_btb_hit0;
    reg queue_pred_btb_is_cond0;
    reg [1:0] queue_pred_bht_state0;
    reg [31:0] queue_pred_pht_idx0;
    reg [31:0] queue_pc1;
    reg [31:0] queue_instr1;
    reg queue_exc_valid1;
    reg [31:0] queue_exc_cause1;
    reg [31:0] queue_exc_tval1;
    reg queue_pred_taken1;
    reg [31:0] queue_pred_target1;
    reg queue_pred_btb_hit1;
    reg queue_pred_btb_is_cond1;
    reg [1:0] queue_pred_bht_state1;
    reg [31:0] queue_pred_pht_idx1;

    reg waiting_resp;
    reg drop_resp;
    reg stop_fetch_r;
`ifdef NPC_BRANCH_STAT
    reg drop_resp_redirect;
    reg [63:0] bpu_btb_lookup_count_r;
    reg [63:0] bpu_btb_hit_count_r;
    reg [63:0] bpu_btb_miss_count_r;
    reg [63:0] bpu_bht_pred_taken_count_r;
    reg [63:0] bpu_bht_pred_not_taken_count_r;
    reg [63:0] bpu_btb_conflict_count_r;
    reg [63:0] bpu_btb_update_count_r;
    reg [63:0] bpu_btb_replace_count_r;
    reg [63:0] bpu_bht_lookup_count_r;
    reg [63:0] bpu_bht_update_count_r;
    reg [63:0] bpu_bht_weak_taken_count_r;
    reg [63:0] bpu_bht_weak_not_taken_count_r;
    reg [63:0] bpu_bht_strong_taken_count_r;
    reg [63:0] bpu_bht_strong_not_taken_count_r;
`endif
    reg [31:0] next_fetch_pc;
    reg [31:0] req_pc;
    reg req_pred_taken;
    reg [31:0] req_pred_target;
    reg req_pred_btb_hit;
    reg req_pred_btb_is_cond;
    reg [1:0] req_pred_bht_state;
    reg [31:0] req_pred_pht_idx;
    reg btb_init_active_r;
    reg [INIT_IDX_BITS-1:0] btb_init_idx_r;
    reg [BHR_BITS-1:0] global_history_r;

    (* ram_style = "distributed" *) reg btb_valid [0:BTB_ENTRIES-1];
    (* ram_style = "distributed" *) reg [BTB_TAG_BITS-1:0] btb_tag [0:BTB_ENTRIES-1];
    (* ram_style = "distributed" *) reg [31:0] btb_target [0:BTB_ENTRIES-1];
    (* ram_style = "distributed" *) reg btb_is_cond [0:BTB_ENTRIES-1];
    (* ram_style = "distributed" *) reg [1:0] pht_ctr [0:BHT_ENTRIES-1];

    integer i;
`ifndef NPC_ASIC
    integer reset_i;
`endif

    wire fs_valid = (queue_count != 2'd0);
    wire fs_pop = fs_valid && ds_allowin;
    wire req_fire = ibus_req_valid && ibus_req_ready;
    wire resp_fire = ibus_resp_valid && ibus_resp_ready;
    wire btb_init_done = (btb_init_idx_r == INIT_LAST_INT[INIT_IDX_BITS-1:0]);
    wire [31:0] btb_init_idx_ext = {{(32-INIT_IDX_BITS){1'b0}}, btb_init_idx_r};

    wire [BTB_IDX_BITS-1:0] pred_idx = next_fetch_pc[BTB_IDX_BITS+1:2];
    wire [BHT_IDX_BITS-1:0] pred_bht_idx = next_fetch_pc[BHT_IDX_BITS+1:2];
    wire [BHT_IDX_BITS-1:0] gshare_hist_idx = bhr_to_bht_idx(global_history_r);
`ifdef NPC_GSHARE_ENABLE
    wire [BHT_IDX_BITS-1:0] pred_pht_idx = pred_bht_idx ^ gshare_hist_idx;
`else
    wire [BHT_IDX_BITS-1:0] pred_pht_idx = pred_bht_idx;
`endif
    wire [BTB_TAG_BITS-1:0] pred_tag = next_fetch_pc[31:BTB_IDX_BITS+2];
    wire pred_hit = btb_valid[pred_idx] && (btb_tag[pred_idx] == pred_tag);
    wire pred_conflict = btb_valid[pred_idx] && (btb_tag[pred_idx] != pred_tag);
    wire pred_btb_is_cond = pred_hit && btb_is_cond[pred_idx];
    wire [1:0] pred_bht_state = pht_ctr[pred_pht_idx];
`ifdef NPC_BRANCH_PRED
    wire pred_taken = pred_hit && (!btb_is_cond[pred_idx] || pred_bht_state[1]);
    wire [31:0] pred_target = pred_taken ? btb_target[pred_idx] : (next_fetch_pc + 32'd4);
`else
    wire pred_taken = 1'b0;
    wire [31:0] pred_target = next_fetch_pc + 32'd4;
`endif

    wire [BTB_IDX_BITS-1:0] bpu_upd_idx = bpu_update_pc[BTB_IDX_BITS+1:2];
    wire [BHT_IDX_BITS-1:0] bpu_upd_pc_bht_idx = bpu_update_pc[BHT_IDX_BITS+1:2];
`ifdef NPC_GSHARE_ENABLE
    wire [BHT_IDX_BITS-1:0] bpu_upd_bht_idx = bpu_update_pht_idx[BHT_IDX_BITS-1:0];
`else
    wire [BHT_IDX_BITS-1:0] bpu_upd_bht_idx = bpu_upd_pc_bht_idx;
`endif
    wire [BTB_TAG_BITS-1:0] bpu_upd_tag = bpu_update_pc[31:BTB_IDX_BITS+2];
    wire bpu_upd_hit = btb_valid[bpu_upd_idx] && (btb_tag[bpu_upd_idx] == bpu_upd_tag);
    wire bpu_upd_replace = btb_valid[bpu_upd_idx] && (btb_tag[bpu_upd_idx] != bpu_upd_tag);
    wire bpu_will_update_btb = bpu_update_valid && (bpu_update_taken || !bpu_update_is_cond);

    // Redirect does not directly participate in IF combinational req/resp logic.
    // A redirect may therefore allow one last wrong-path request/response in the
    // same cycle; IF will discard it locally by setting drop_resp in the clocked
    // state update below.
    // During hold_fetch (e.g. fence.i maintenance), IF must not deliver any
    // response into ID/queue. Still keep ready high to drain one outstanding
    // response, but mark it as dropped.
`ifdef NPC_IF_HIT_PIPELINE
    wire resp_accept = resp_fire && !redirect_flush && !stop_clear && !hold_fetch;
`else
    wire resp_accept = resp_fire && !drop_resp && !stop_clear && !hold_fetch;
`endif
    // Direct IF->ID bypass: when queue is empty and ID can accept now,
    // consume this response directly without writing queue data regs.
    wire bypass_direct = resp_accept && (queue_count == 2'd0) && ds_allowin;
    wire resp_enq = resp_accept && !bypass_direct;
`ifdef NPC_IF_HIT_PIPELINE
    wire resp_drop = resp_fire && (redirect_flush || stop_clear || hold_fetch);
`else
    wire resp_drop = resp_fire && (drop_resp || stop_clear || hold_fetch);
`endif
    wire resp_data_write = resp_enq;

    // Permit a new hit request in the same cycle that the previous response is
    // consumed. Keep the rule conservative when the local queue is non-empty,
    // so ID backpressure still cannot overflow the two-entry fetch queue.
`ifdef NPC_IF_HIT_PIPELINE
    wire fetch_room = (queue_count < 2'd2) ||
                      (resp_fire && (queue_count == 2'd0));
`else
    wire fetch_room = (!waiting_resp && (queue_count < 2'd2)) ||
                      (waiting_resp && resp_fire && (queue_count == 2'd0));
`endif

    // Whether a request/response will still be outstanding after this cycle.
    // Used to decide whether redirect/stop_clear must leave drop_resp asserted.
    wire outstanding_after_cycle = req_fire || (waiting_resp && !resp_fire);

`ifdef NPC_IF_HIT_PIPELINE
    wire [31:0] resp_pc = ibus_resp_pc;
    wire resp_pred_taken = ibus_resp_pred_taken;
    wire [31:0] resp_pred_target = ibus_resp_pred_target;
    wire resp_pred_btb_hit = ibus_resp_pred_btb_hit;
    wire resp_pred_btb_is_cond = ibus_resp_pred_btb_is_cond;
    wire [1:0] resp_pred_bht_state = ibus_resp_pred_bht_state;
    wire [31:0] resp_pred_pht_idx = ibus_resp_pred_pht_idx;
`else
    wire [31:0] resp_pc = req_pc;
    wire resp_pred_taken = req_pred_taken;
    wire [31:0] resp_pred_target = req_pred_target;
    wire resp_pred_btb_hit = req_pred_btb_hit;
    wire resp_pred_btb_is_cond = req_pred_btb_is_cond;
    wire [1:0] resp_pred_bht_state = req_pred_bht_state;
    wire [31:0] resp_pred_pht_idx = req_pred_pht_idx;
`endif

    assign fs_to_ds_valid = fs_valid || bypass_direct;
    assign fs_pc = fs_valid ? queue_pc0 : resp_pc;
    assign fs_instr = fs_valid ? queue_instr0 : ibus_resp_data;
    assign fs_exc_valid = fs_valid ? queue_exc_valid0 : ibus_resp_exc_valid;
    assign fs_exc_cause = fs_valid ? queue_exc_cause0 : ibus_resp_exc_cause;
    assign fs_exc_tval = fs_valid ? queue_exc_tval0 : ibus_resp_exc_tval;
    assign fs_pred_taken = fs_valid ? queue_pred_taken0 : resp_pred_taken;
    assign fs_pred_target = fs_valid ? queue_pred_target0 : resp_pred_target;
    assign fs_pred_btb_hit = fs_valid ? queue_pred_btb_hit0 : resp_pred_btb_hit;
    assign fs_pred_btb_is_cond = fs_valid ? queue_pred_btb_is_cond0 : resp_pred_btb_is_cond;
    assign fs_pred_bht_state = fs_valid ? queue_pred_bht_state0 : resp_pred_bht_state;
    assign fs_pred_pht_idx = fs_valid ? queue_pred_pht_idx0 : resp_pred_pht_idx;

    // Do not use ds_allowin here. ID backpressure only pops this queue, while
    // IF keeps fetching until the queue and the single outstanding request slot
    // are both occupied. stop_fetch/stop_clear are registered or local sidebands,
    // so ID-stage ebreak/illegal decode does not feed next_fetch_pc directly.
    assign ibus_req_valid = !btb_init_active_r && !stop_fetch_r && !pause_fetch &&
                            !hold_fetch && !stop_clear && fetch_room;
    assign ibus_req_addr = next_fetch_pc;
    assign ibus_req_pred_taken = pred_taken;
    assign ibus_req_pred_target = pred_target;
    assign ibus_req_pred_btb_hit = pred_hit;
    assign ibus_req_pred_btb_is_cond = pred_btb_is_cond;
    assign ibus_req_pred_bht_state = pred_bht_state;
    assign ibus_req_pred_pht_idx = {{(32-BHT_IDX_BITS){1'b0}}, pred_pht_idx};
`ifdef NPC_IF_HIT_PIPELINE
    assign ibus_resp_ready = (redirect_flush || stop_clear || hold_fetch) ||
        (queue_count < 2'd2) || ds_allowin;
`else
    assign ibus_resp_ready = waiting_resp;
`endif

`ifdef NPC_IF_HIT_PIPELINE
    wire unused_resp_seq = |ibus_resp_seq;
    wire unused_resp_epoch = |ibus_resp_epoch;
`endif

    // IF is considered stalled when frontend is active but cannot move fetch
    // forward this cycle (queue/outstanding full or downstream req backpressure).
    assign if_stall = !btb_init_active_r && !stop_fetch_r && !pause_fetch && !hold_fetch && !stop_clear &&
                      (!fetch_room || (ibus_req_valid && !ibus_req_ready));

`ifdef NPC_PIPE_STAT
    assign if_stat_fs_valid = fs_valid;
    assign if_stat_queue_count = queue_count;
    assign if_stat_fetch_room = fetch_room;
    assign if_stat_req_fire = req_fire;
    assign if_stat_resp_fire = resp_fire;
    assign if_stat_resp_accept = resp_accept;
    assign if_stat_resp_drop = resp_drop;
    assign if_stat_bypass_direct = bypass_direct;
    assign if_stat_waiting_resp = waiting_resp;
    assign if_stat_drop_resp = drop_resp;
    assign if_stat_fs_pop = fs_pop;
    assign if_stat_resp_enq = resp_enq;
    assign if_stat_queue_full = (queue_count == 2'd2);
    assign if_stat_resp_block = ibus_resp_valid && !ibus_resp_ready;
`endif

`ifdef NPC_BRANCH_STAT
    // Simulation-only trace points. Request/accept/drop are separated so the
    // branch monitor can count wrong-path requests even when the response is
    // later discarded before entering the IF queue.
    assign fetch_req_trace_valid = req_fire;
    assign fetch_req_trace_pc = ibus_req_addr;
    assign fetch_accept_trace_valid = resp_accept;
    assign fetch_accept_trace_pc = resp_pc;
    assign fetch_accept_trace_instr = ibus_resp_data;
    assign fetch_drop_trace_valid = resp_drop;
    assign fetch_drop_trace_redirect = drop_resp_redirect || (redirect_flush && flush_trace_is_redirect);
    assign fetch_drop_trace_pc = resp_pc;
    assign fetch_drop_trace_instr = ibus_resp_data;
    assign bpu_btb_lookup_count = bpu_btb_lookup_count_r;
    assign bpu_btb_hit_count = bpu_btb_hit_count_r;
    assign bpu_btb_miss_count = bpu_btb_miss_count_r;
    assign bpu_bht_pred_taken_count = bpu_bht_pred_taken_count_r;
    assign bpu_bht_pred_not_taken_count = bpu_bht_pred_not_taken_count_r;
    assign bpu_btb_conflict_count = bpu_btb_conflict_count_r;
    assign bpu_btb_update_count = bpu_btb_update_count_r;
    assign bpu_btb_replace_count = bpu_btb_replace_count_r;
    assign bpu_bht_lookup_count = bpu_bht_lookup_count_r;
    assign bpu_bht_update_count = bpu_bht_update_count_r;
    assign bpu_bht_weak_taken_count = bpu_bht_weak_taken_count_r;
    assign bpu_bht_weak_not_taken_count = bpu_bht_weak_not_taken_count_r;
    assign bpu_bht_strong_taken_count = bpu_bht_strong_taken_count_r;
    assign bpu_bht_strong_not_taken_count = bpu_bht_strong_not_taken_count_r;
`ifdef NPC_GSHARE_ENABLE
    assign bpu_bhr_value = bhr_to_u32(global_history_r);
`else
    assign bpu_bhr_value = 32'b0;
`endif
`endif

`ifndef NPC_ASIC
    initial begin
        for (reset_i = 0; reset_i < INIT_ENTRIES; reset_i = reset_i + 1) begin
            if (reset_i < BTB_ENTRIES) begin
                btb_valid[reset_i] = 1'b0;
            end
            if (reset_i < BHT_ENTRIES) begin
                pht_ctr[reset_i] = 2'b01;
            end
        end
    end
`endif

    always @(posedge clk) begin
        if (!rst_n) begin
            queue_count <= 2'd0;
            waiting_resp <= 1'b0;
            drop_resp <= 1'b0;
            stop_fetch_r <= 1'b0;
`ifdef NPC_USE_DPI
            btb_init_active_r <= 1'b0;
`else
            btb_init_active_r <= 1'b1;
`endif
            btb_init_idx_r <= {INIT_IDX_BITS{1'b0}};
`ifdef NPC_BRANCH_STAT
            drop_resp_redirect <= 1'b0;
            bpu_btb_lookup_count_r <= 64'd0;
            bpu_btb_hit_count_r <= 64'd0;
            bpu_btb_miss_count_r <= 64'd0;
            bpu_bht_pred_taken_count_r <= 64'd0;
            bpu_bht_pred_not_taken_count_r <= 64'd0;
            bpu_btb_conflict_count_r <= 64'd0;
            bpu_btb_update_count_r <= 64'd0;
            bpu_btb_replace_count_r <= 64'd0;
            bpu_bht_lookup_count_r <= 64'd0;
            bpu_bht_update_count_r <= 64'd0;
            bpu_bht_weak_taken_count_r <= 64'd0;
            bpu_bht_weak_not_taken_count_r <= 64'd0;
            bpu_bht_strong_taken_count_r <= 64'd0;
            bpu_bht_strong_not_taken_count_r <= 64'd0;
`endif
            next_fetch_pc <= RESET_VECTOR;
            req_pc <= RESET_VECTOR;
            req_pred_taken <= 1'b0;
            req_pred_target <= RESET_VECTOR + 32'd4;
            req_pred_btb_hit <= 1'b0;
            req_pred_btb_is_cond <= 1'b0;
            req_pred_bht_state <= 2'b0;
            req_pred_pht_idx <= 32'b0;
            global_history_r <= {BHR_BITS{1'b0}};
        end else if (btb_init_active_r) begin
            queue_count <= 2'd0;
            waiting_resp <= 1'b0;
            drop_resp <= 1'b0;
            stop_fetch_r <= 1'b0;
            next_fetch_pc <= RESET_VECTOR;
            req_pc <= RESET_VECTOR;
            req_pred_taken <= 1'b0;
            req_pred_target <= RESET_VECTOR + 32'd4;
            req_pred_btb_hit <= 1'b0;
            req_pred_btb_is_cond <= 1'b0;
            req_pred_bht_state <= 2'b0;
            req_pred_pht_idx <= 32'b0;
            if (btb_init_idx_ext < BTB_ENTRIES) begin
                btb_valid[btb_init_idx_r[BTB_IDX_BITS-1:0]] <= 1'b0;
            end
            if (btb_init_idx_ext < BHT_ENTRIES) begin
                pht_ctr[btb_init_idx_r[BHT_IDX_BITS-1:0]] <= 2'b01;
            end
            if (btb_init_done) begin
                btb_init_active_r <= 1'b0;
            end else begin
                btb_init_idx_r <= btb_init_idx_r + {{(INIT_IDX_BITS-1){1'b0}}, 1'b1};
            end
`ifdef NPC_BRANCH_STAT
            drop_resp_redirect <= 1'b0;
`endif
        end else begin
`ifdef NPC_BRANCH_PRED
            if (bpu_update_valid) begin
`ifdef NPC_BRANCH_STAT
                if (bpu_will_update_btb) begin
                    bpu_btb_update_count_r <= bpu_btb_update_count_r + 64'd1;
                    if (bpu_upd_replace) begin
                        bpu_btb_replace_count_r <= bpu_btb_replace_count_r + 64'd1;
                    end
                end
                if (bpu_update_is_cond) begin
                    bpu_bht_update_count_r <= bpu_bht_update_count_r + 64'd1;
                end
`endif
                if (bpu_update_is_cond) begin
                    if (bpu_upd_hit || bpu_update_taken) begin
                        btb_valid[bpu_upd_idx] <= 1'b1;
                        btb_tag[bpu_upd_idx] <= bpu_upd_tag;
                        btb_is_cond[bpu_upd_idx] <= 1'b1;
                        if (bpu_update_taken) begin
                            btb_target[bpu_upd_idx] <= bpu_update_target;
                        end
                        if (!bpu_upd_hit) begin
                            pht_ctr[bpu_upd_bht_idx] <= bpu_update_taken ? 2'b10 : 2'b01;
                        end else if (bpu_update_taken) begin
                            if (pht_ctr[bpu_upd_bht_idx] != 2'b11) begin
                                pht_ctr[bpu_upd_bht_idx] <= pht_ctr[bpu_upd_bht_idx] + 2'd1;
                            end
                        end else begin
                            if (pht_ctr[bpu_upd_bht_idx] != 2'b00) begin
                                pht_ctr[bpu_upd_bht_idx] <= pht_ctr[bpu_upd_bht_idx] - 2'd1;
                            end
                        end
                    end
`ifdef NPC_GSHARE_ENABLE
                    global_history_r <= bhr_next_value(global_history_r, bpu_update_taken);
`endif
                end else if (bpu_update_taken) begin
                    btb_valid[bpu_upd_idx] <= 1'b1;
                    btb_tag[bpu_upd_idx] <= bpu_upd_tag;
                    btb_target[bpu_upd_idx] <= bpu_update_target;
                    btb_is_cond[bpu_upd_idx] <= 1'b0;
                end
            end
`endif

            // ------------------------------------------------------------
            // Local IF state handling for redirect / stop clear.
            // Redirect is sampled here as a timed event. It clears the queue,
            // installs the new fetch PC, and marks any already-issued response
            // to be dropped later. It does NOT directly gate IF combinational
            // req/resp logic.
            // ------------------------------------------------------------
            if (redirect_flush) begin
                queue_count <= 2'd0;
                stop_fetch_r <= 1'b0;
                next_fetch_pc <= flush_pc;
`ifndef NPC_IF_HIT_PIPELINE
                drop_resp <= outstanding_after_cycle;
`endif
`ifdef NPC_BRANCH_STAT
`ifdef NPC_IF_HIT_PIPELINE
                drop_resp_redirect <= 1'b0;
`else
                drop_resp_redirect <= outstanding_after_cycle && flush_trace_is_redirect;
`endif
`endif
            end else if (stop_clear) begin
                queue_count <= 2'd0;
                stop_fetch_r <= 1'b1;
`ifndef NPC_IF_HIT_PIPELINE
                drop_resp <= outstanding_after_cycle;
`endif
`ifdef NPC_BRANCH_STAT
                drop_resp_redirect <= 1'b0;
`endif
            end else begin
                if (stop_fetch) begin
                    stop_fetch_r <= 1'b1;
                end

                case ({resp_enq, fs_pop})
                    2'b01: queue_count <= (queue_count == 2'd0) ? 2'd0 : (queue_count - 2'd1);
                    2'b10: queue_count <= (queue_count == 2'd2) ? 2'd2 : (queue_count + 2'd1);
                    default: queue_count <= queue_count;
                endcase

                // Clear drop marker once the marked wrong-path response is
                // actually consumed/dropped. This stays local to IF.
`ifndef NPC_IF_HIT_PIPELINE
                if (resp_fire && drop_resp) begin
                    drop_resp <= 1'b0;
`ifdef NPC_BRANCH_STAT
                    drop_resp_redirect <= 1'b0;
`endif
                end
`endif
            end

`ifndef NPC_IF_HIT_PIPELINE
            case ({req_fire, resp_fire})
                2'b10: waiting_resp <= 1'b1;
                2'b01: waiting_resp <= 1'b0;
                2'b11: waiting_resp <= 1'b1;
                default: waiting_resp <= waiting_resp;
            endcase
`endif

            // Record the address and prediction metadata of the issued request.
            if (req_fire) begin
                req_pc <= next_fetch_pc;
                req_pred_taken <= pred_taken;
                req_pred_target <= pred_target;
                req_pred_btb_hit <= pred_hit;
                req_pred_btb_is_cond <= pred_btb_is_cond;
                req_pred_bht_state <= pred_bht_state;
                req_pred_pht_idx <= {{(32-BHT_IDX_BITS){1'b0}}, pred_pht_idx};
`ifdef NPC_BRANCH_STAT
`ifdef NPC_BRANCH_PRED
                bpu_btb_lookup_count_r <= bpu_btb_lookup_count_r + 64'd1;
                if (pred_conflict) begin
                    bpu_btb_conflict_count_r <= bpu_btb_conflict_count_r + 64'd1;
                end
                if (pred_hit) begin
                    bpu_btb_hit_count_r <= bpu_btb_hit_count_r + 64'd1;
                    if (btb_is_cond[pred_idx]) begin
                        bpu_bht_lookup_count_r <= bpu_bht_lookup_count_r + 64'd1;
                        case (pred_bht_state)
                            2'b00: bpu_bht_strong_not_taken_count_r <= bpu_bht_strong_not_taken_count_r + 64'd1;
                            2'b01: bpu_bht_weak_not_taken_count_r <= bpu_bht_weak_not_taken_count_r + 64'd1;
                            2'b10: bpu_bht_weak_taken_count_r <= bpu_bht_weak_taken_count_r + 64'd1;
                            2'b11: bpu_bht_strong_taken_count_r <= bpu_bht_strong_taken_count_r + 64'd1;
                        endcase
                        if (pred_bht_state[1]) begin
                            bpu_bht_pred_taken_count_r <= bpu_bht_pred_taken_count_r + 64'd1;
                        end else begin
                            bpu_bht_pred_not_taken_count_r <= bpu_bht_pred_not_taken_count_r + 64'd1;
                        end
                    end
                end else begin
                    bpu_btb_miss_count_r <= bpu_btb_miss_count_r + 64'd1;
                end
`endif
`endif
            end

            if (!redirect_flush && !stop_clear && req_fire) begin
                next_fetch_pc <= pred_taken ? pred_target : (next_fetch_pc + 32'd4);
            end
        end
    end

    // Keep redirect/flush out of the data-register enables. A redirect only
    // clears queue_count above; any stale data written in the same cycle is
    // invalid because queue_count is zeroed.
    always @(posedge clk) begin
        if (!rst_n) begin
            queue_pc0 <= 32'b0;
            queue_instr0 <= 32'b0;
            queue_exc_valid0 <= 1'b0;
            queue_exc_cause0 <= 32'b0;
            queue_exc_tval0 <= 32'b0;
            queue_pred_taken0 <= 1'b0;
            queue_pred_target0 <= 32'b0;
            queue_pred_btb_hit0 <= 1'b0;
            queue_pred_btb_is_cond0 <= 1'b0;
            queue_pred_bht_state0 <= 2'b0;
            queue_pred_pht_idx0 <= 32'b0;
            queue_pc1 <= 32'b0;
            queue_instr1 <= 32'b0;
            queue_exc_valid1 <= 1'b0;
            queue_exc_cause1 <= 32'b0;
            queue_exc_tval1 <= 32'b0;
            queue_pred_taken1 <= 1'b0;
            queue_pred_target1 <= 32'b0;
            queue_pred_btb_hit1 <= 1'b0;
            queue_pred_btb_is_cond1 <= 1'b0;
            queue_pred_bht_state1 <= 2'b0;
            queue_pred_pht_idx1 <= 32'b0;
        end else if (btb_init_active_r) begin
            queue_pc0 <= 32'b0;
            queue_instr0 <= 32'b0;
            queue_exc_valid0 <= 1'b0;
            queue_exc_cause0 <= 32'b0;
            queue_exc_tval0 <= 32'b0;
            queue_pred_taken0 <= 1'b0;
            queue_pred_target0 <= 32'b0;
            queue_pred_btb_hit0 <= 1'b0;
            queue_pred_btb_is_cond0 <= 1'b0;
            queue_pred_bht_state0 <= 2'b0;
            queue_pred_pht_idx0 <= 32'b0;
            queue_pc1 <= 32'b0;
            queue_instr1 <= 32'b0;
            queue_exc_valid1 <= 1'b0;
            queue_exc_cause1 <= 32'b0;
            queue_exc_tval1 <= 32'b0;
            queue_pred_taken1 <= 1'b0;
            queue_pred_target1 <= 32'b0;
            queue_pred_btb_hit1 <= 1'b0;
            queue_pred_btb_is_cond1 <= 1'b0;
            queue_pred_bht_state1 <= 2'b0;
            queue_pred_pht_idx1 <= 32'b0;
        end else if (resp_data_write) begin
            if (fs_pop && (queue_count == 2'd2)) begin
                queue_pc0 <= queue_pc1;
                queue_instr0 <= queue_instr1;
                queue_exc_valid0 <= queue_exc_valid1;
                queue_exc_cause0 <= queue_exc_cause1;
                queue_exc_tval0 <= queue_exc_tval1;
                queue_pred_taken0 <= queue_pred_taken1;
                queue_pred_target0 <= queue_pred_target1;
                queue_pred_btb_hit0 <= queue_pred_btb_hit1;
                queue_pred_btb_is_cond0 <= queue_pred_btb_is_cond1;
                queue_pred_bht_state0 <= queue_pred_bht_state1;
                queue_pred_pht_idx0 <= queue_pred_pht_idx1;
                queue_pc1 <= resp_pc;
                queue_instr1 <= ibus_resp_data;
                queue_exc_valid1 <= ibus_resp_exc_valid;
                queue_exc_cause1 <= ibus_resp_exc_cause;
                queue_exc_tval1 <= ibus_resp_exc_tval;
                queue_pred_taken1 <= resp_pred_taken;
                queue_pred_target1 <= resp_pred_target;
                queue_pred_btb_hit1 <= resp_pred_btb_hit;
                queue_pred_btb_is_cond1 <= resp_pred_btb_is_cond;
                queue_pred_bht_state1 <= resp_pred_bht_state;
                queue_pred_pht_idx1 <= resp_pred_pht_idx;
            end else if (fs_pop || (queue_count == 2'd0)) begin
                queue_pc0 <= resp_pc;
                queue_instr0 <= ibus_resp_data;
                queue_exc_valid0 <= ibus_resp_exc_valid;
                queue_exc_cause0 <= ibus_resp_exc_cause;
                queue_exc_tval0 <= ibus_resp_exc_tval;
                queue_pred_taken0 <= resp_pred_taken;
                queue_pred_target0 <= resp_pred_target;
                queue_pred_btb_hit0 <= resp_pred_btb_hit;
                queue_pred_btb_is_cond0 <= resp_pred_btb_is_cond;
                queue_pred_bht_state0 <= resp_pred_bht_state;
                queue_pred_pht_idx0 <= resp_pred_pht_idx;
            end else if (queue_count == 2'd1) begin
                queue_pc1 <= resp_pc;
                queue_instr1 <= ibus_resp_data;
                queue_exc_valid1 <= ibus_resp_exc_valid;
                queue_exc_cause1 <= ibus_resp_exc_cause;
                queue_exc_tval1 <= ibus_resp_exc_tval;
                queue_pred_taken1 <= resp_pred_taken;
                queue_pred_target1 <= resp_pred_target;
                queue_pred_btb_hit1 <= resp_pred_btb_hit;
                queue_pred_btb_is_cond1 <= resp_pred_btb_is_cond;
                queue_pred_bht_state1 <= resp_pred_bht_state;
                queue_pred_pht_idx1 <= resp_pred_pht_idx;
            end
        end else if (fs_pop && (queue_count == 2'd2)) begin
            queue_pc0 <= queue_pc1;
            queue_instr0 <= queue_instr1;
            queue_exc_valid0 <= queue_exc_valid1;
            queue_exc_cause0 <= queue_exc_cause1;
            queue_exc_tval0 <= queue_exc_tval1;
            queue_pred_taken0 <= queue_pred_taken1;
            queue_pred_target0 <= queue_pred_target1;
            queue_pred_btb_hit0 <= queue_pred_btb_hit1;
            queue_pred_btb_is_cond0 <= queue_pred_btb_is_cond1;
            queue_pred_bht_state0 <= queue_pred_bht_state1;
            queue_pred_pht_idx0 <= queue_pred_pht_idx1;
        end
    end

endmodule
