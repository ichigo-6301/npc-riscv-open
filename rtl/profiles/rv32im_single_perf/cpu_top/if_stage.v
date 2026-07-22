`timescale 1ns / 1ps

module if_stage #(
    parameter integer BTB_ENTRIES = 128
) (
    input clk,
    input rst_n,

    input ds_allowin,
    input stop_fetch,
    input redirect_flush,
    input stop_clear,
    input [31:0] flush_pc,

    input bpu_update_valid,
    input [31:0] bpu_update_pc,
    input bpu_update_is_cond,
    input bpu_update_taken,
    input [31:0] bpu_update_target,

    output fs_to_ds_valid,
    output [31:0] fs_pc,
    output [31:0] fs_instr,
    output fs_pred_taken,
    output [31:0] fs_pred_target,
    output if_stall,

    output ibus_req_valid,
    input ibus_req_ready,
    output [31:0] ibus_req_addr,
    input ibus_resp_valid,
    output ibus_resp_ready,
    input [31:0] ibus_resp_data
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
    output [31:0] fetch_drop_trace_instr
`endif
);
`ifdef NPC_RESET_VECTOR_HEX
    localparam [31:0] RESET_VECTOR = 32'h`NPC_RESET_VECTOR_HEX;
`else
    localparam [31:0] RESET_VECTOR = 32'h80000000;
`endif

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
    localparam integer BTB_INIT_LAST_INT = BTB_ENTRIES - 1;

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
    reg queue_pred_taken0;
    reg [31:0] queue_pred_target0;
    reg [31:0] queue_pc1;
    reg [31:0] queue_instr1;
    reg queue_pred_taken1;
    reg [31:0] queue_pred_target1;

    reg waiting_resp;
    reg drop_resp;
    reg stop_fetch_r;
`ifdef NPC_BRANCH_STAT
    reg drop_resp_redirect;
`endif
    reg [31:0] next_fetch_pc;
    reg [31:0] req_pc;
    reg req_pred_taken;
    reg [31:0] req_pred_target;
    reg btb_init_active_r;
    reg [BTB_IDX_BITS-1:0] btb_init_idx_r;

    (* ram_style = "distributed" *) reg btb_valid [0:BTB_ENTRIES-1];
    (* ram_style = "distributed" *) reg [BTB_TAG_BITS-1:0] btb_tag [0:BTB_ENTRIES-1];
    (* ram_style = "distributed" *) reg [31:0] btb_target [0:BTB_ENTRIES-1];
    (* ram_style = "distributed" *) reg btb_is_cond [0:BTB_ENTRIES-1];
    (* ram_style = "distributed" *) reg [1:0] pht_ctr [0:BTB_ENTRIES-1];

    integer i;
`ifndef NPC_ASIC
    integer reset_i;
`endif

    wire fs_valid = (queue_count != 2'd0);
    wire fs_pop = fs_valid && ds_allowin;
    wire req_fire = ibus_req_valid && ibus_req_ready;
    wire resp_fire = ibus_resp_valid && ibus_resp_ready;
    wire btb_init_done = (btb_init_idx_r == BTB_INIT_LAST_INT[BTB_IDX_BITS-1:0]);

    wire [BTB_IDX_BITS-1:0] pred_idx = next_fetch_pc[BTB_IDX_BITS+1:2];
    wire [BTB_TAG_BITS-1:0] pred_tag = next_fetch_pc[31:BTB_IDX_BITS+2];
    wire pred_hit = btb_valid[pred_idx] && (btb_tag[pred_idx] == pred_tag);
    wire pred_taken = pred_hit && (!btb_is_cond[pred_idx] || pht_ctr[pred_idx][1]);
    wire [31:0] pred_target = pred_hit ? btb_target[pred_idx] : (next_fetch_pc + 32'd4);

    wire [BTB_IDX_BITS-1:0] bpu_upd_idx = bpu_update_pc[BTB_IDX_BITS+1:2];
    wire [BTB_TAG_BITS-1:0] bpu_upd_tag = bpu_update_pc[31:BTB_IDX_BITS+2];
    wire bpu_upd_hit = btb_valid[bpu_upd_idx] && (btb_tag[bpu_upd_idx] == bpu_upd_tag);

    // Redirect does not directly participate in IF combinational req/resp logic.
    // A redirect may therefore allow one last wrong-path request/response in the
    // same cycle; IF will discard it locally by setting drop_resp in the clocked
    // state update below.
    wire resp_accept = resp_fire && !drop_resp && !stop_clear;
    // Direct IF->ID bypass: when queue is empty and ID can accept now,
    // consume this response directly without writing queue data regs.
    wire bypass_direct = resp_accept && (queue_count == 2'd0) && ds_allowin;
    wire resp_enq = resp_accept && !bypass_direct;
    wire resp_drop = resp_fire && (drop_resp || stop_clear);
    wire resp_data_write = resp_enq;

    // Permit a new hit request in the same cycle that the previous response is
    // consumed. Keep the rule conservative when the local queue is non-empty,
    // so ID backpressure still cannot overflow the two-entry fetch queue.
    wire fetch_room = (!waiting_resp && (queue_count < 2'd2)) ||
                      (waiting_resp && resp_fire && (queue_count == 2'd0));

    // Whether a request/response will still be outstanding after this cycle.
    // Used to decide whether redirect/stop_clear must leave drop_resp asserted.
    wire outstanding_after_cycle = req_fire || (waiting_resp && !resp_fire);

    assign fs_to_ds_valid = fs_valid || bypass_direct;
    assign fs_pc = fs_valid ? queue_pc0 : req_pc;
    assign fs_instr = fs_valid ? queue_instr0 : ibus_resp_data;
    assign fs_pred_taken = fs_valid ? queue_pred_taken0 : req_pred_taken;
    assign fs_pred_target = fs_valid ? queue_pred_target0 : req_pred_target;

    // Do not use ds_allowin here. ID backpressure only pops this queue, while
    // IF keeps fetching until the queue and the single outstanding request slot
    // are both occupied. stop_fetch/stop_clear are registered or local sidebands,
    // so ID-stage ebreak/illegal decode does not feed next_fetch_pc directly.
    assign ibus_req_valid = !btb_init_active_r && !stop_fetch_r && !stop_clear && fetch_room;
    assign ibus_req_addr = next_fetch_pc;
    assign ibus_resp_ready = waiting_resp;

    // IF is considered stalled when frontend is active but cannot move fetch
    // forward this cycle (queue/outstanding full or downstream req backpressure).
    assign if_stall = !btb_init_active_r && !stop_fetch_r && !stop_clear &&
                      (!fetch_room || (ibus_req_valid && !ibus_req_ready));

`ifdef NPC_BRANCH_STAT
    // Simulation-only trace points. Request/accept/drop are separated so the
    // branch monitor can count wrong-path requests even when the response is
    // later discarded before entering the IF queue.
    assign fetch_req_trace_valid = req_fire;
    assign fetch_req_trace_pc = ibus_req_addr;
    assign fetch_accept_trace_valid = resp_accept;
    assign fetch_accept_trace_pc = req_pc;
    assign fetch_accept_trace_instr = ibus_resp_data;
    assign fetch_drop_trace_valid = resp_drop;
    assign fetch_drop_trace_redirect = drop_resp_redirect || (redirect_flush && flush_trace_is_redirect);
    assign fetch_drop_trace_pc = req_pc;
    assign fetch_drop_trace_instr = ibus_resp_data;
`endif

`ifndef NPC_ASIC
    initial begin
        for (reset_i = 0; reset_i < BTB_ENTRIES; reset_i = reset_i + 1) begin
            btb_valid[reset_i] = 1'b0;
        end
    end
`endif

    always @(posedge clk) begin
        if (!rst_n) begin
            queue_count <= 2'd0;
            waiting_resp <= 1'b0;
            drop_resp <= 1'b0;
            stop_fetch_r <= 1'b0;
            btb_init_active_r <= 1'b1;
            btb_init_idx_r <= {BTB_IDX_BITS{1'b0}};
`ifdef NPC_BRANCH_STAT
            drop_resp_redirect <= 1'b0;
`endif
            next_fetch_pc <= RESET_VECTOR;
            req_pc <= RESET_VECTOR;
            req_pred_taken <= 1'b0;
            req_pred_target <= RESET_VECTOR + 32'd4;
        end else if (btb_init_active_r) begin
            queue_count <= 2'd0;
            waiting_resp <= 1'b0;
            drop_resp <= 1'b0;
            stop_fetch_r <= 1'b0;
            next_fetch_pc <= RESET_VECTOR;
            req_pc <= RESET_VECTOR;
            req_pred_taken <= 1'b0;
            req_pred_target <= RESET_VECTOR + 32'd4;
            btb_valid[btb_init_idx_r] <= 1'b0;
            if (btb_init_done) begin
                btb_init_active_r <= 1'b0;
            end else begin
                btb_init_idx_r <= btb_init_idx_r + {{(BTB_IDX_BITS-1){1'b0}}, 1'b1};
            end
`ifdef NPC_BRANCH_STAT
            drop_resp_redirect <= 1'b0;
`endif
        end else begin
            if (bpu_update_valid) begin
                if (bpu_update_is_cond) begin
                    if (bpu_upd_hit || bpu_update_taken) begin
                        btb_valid[bpu_upd_idx] <= 1'b1;
                        btb_tag[bpu_upd_idx] <= bpu_upd_tag;
                        btb_is_cond[bpu_upd_idx] <= 1'b1;
                        if (bpu_update_taken) begin
                            btb_target[bpu_upd_idx] <= bpu_update_target;
                        end
                        if (!bpu_upd_hit) begin
                            pht_ctr[bpu_upd_idx] <= bpu_update_taken ? 2'b10 : 2'b01;
                        end else if (bpu_update_taken) begin
                            if (pht_ctr[bpu_upd_idx] != 2'b11) begin
                                pht_ctr[bpu_upd_idx] <= pht_ctr[bpu_upd_idx] + 2'd1;
                            end
                        end else begin
                            if (pht_ctr[bpu_upd_idx] != 2'b00) begin
                                pht_ctr[bpu_upd_idx] <= pht_ctr[bpu_upd_idx] - 2'd1;
                            end
                        end
                    end
                end else if (bpu_update_taken) begin
                    btb_valid[bpu_upd_idx] <= 1'b1;
                    btb_tag[bpu_upd_idx] <= bpu_upd_tag;
                    btb_target[bpu_upd_idx] <= bpu_update_target;
                    btb_is_cond[bpu_upd_idx] <= 1'b0;
                    pht_ctr[bpu_upd_idx] <= 2'b11;
                end
            end

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
                drop_resp <= outstanding_after_cycle;
`ifdef NPC_BRANCH_STAT
                drop_resp_redirect <= outstanding_after_cycle && flush_trace_is_redirect;
`endif
            end else if (stop_clear) begin
                queue_count <= 2'd0;
                stop_fetch_r <= 1'b1;
                drop_resp <= outstanding_after_cycle;
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
                if (resp_fire && drop_resp) begin
                    drop_resp <= 1'b0;
`ifdef NPC_BRANCH_STAT
                    drop_resp_redirect <= 1'b0;
`endif
                end
            end

            case ({req_fire, resp_fire})
                2'b10: waiting_resp <= 1'b1;
                2'b01: waiting_resp <= 1'b0;
                2'b11: waiting_resp <= 1'b1;
                default: waiting_resp <= waiting_resp;
            endcase

            // Record the address and prediction metadata of the issued request.
            if (req_fire) begin
                req_pc <= next_fetch_pc;
                req_pred_taken <= pred_taken;
                req_pred_target <= pred_target;
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
            queue_pred_taken0 <= 1'b0;
            queue_pred_target0 <= 32'b0;
            queue_pc1 <= 32'b0;
            queue_instr1 <= 32'b0;
            queue_pred_taken1 <= 1'b0;
            queue_pred_target1 <= 32'b0;
        end else if (btb_init_active_r) begin
            queue_pc0 <= 32'b0;
            queue_instr0 <= 32'b0;
            queue_pred_taken0 <= 1'b0;
            queue_pred_target0 <= 32'b0;
            queue_pc1 <= 32'b0;
            queue_instr1 <= 32'b0;
            queue_pred_taken1 <= 1'b0;
            queue_pred_target1 <= 32'b0;
        end else if (resp_data_write) begin
            if (fs_pop && (queue_count == 2'd2)) begin
                queue_pc0 <= queue_pc1;
                queue_instr0 <= queue_instr1;
                queue_pred_taken0 <= queue_pred_taken1;
                queue_pred_target0 <= queue_pred_target1;
                queue_pc1 <= req_pc;
                queue_instr1 <= ibus_resp_data;
                queue_pred_taken1 <= req_pred_taken;
                queue_pred_target1 <= req_pred_target;
            end else if (fs_pop || (queue_count == 2'd0)) begin
                queue_pc0 <= req_pc;
                queue_instr0 <= ibus_resp_data;
                queue_pred_taken0 <= req_pred_taken;
                queue_pred_target0 <= req_pred_target;
            end else if (queue_count == 2'd1) begin
                queue_pc1 <= req_pc;
                queue_instr1 <= ibus_resp_data;
                queue_pred_taken1 <= req_pred_taken;
                queue_pred_target1 <= req_pred_target;
            end
        end else if (fs_pop && (queue_count == 2'd2)) begin
            queue_pc0 <= queue_pc1;
            queue_instr0 <= queue_instr1;
            queue_pred_taken0 <= queue_pred_taken1;
            queue_pred_target0 <= queue_pred_target1;
        end
    end

endmodule
