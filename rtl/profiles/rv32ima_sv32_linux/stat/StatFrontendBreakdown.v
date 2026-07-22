`timescale 1ns / 1ps

`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
module StatFrontendBreakdown (
    input clk,
    input rst_n,
    input sample_en,
    input real_commit,
    input [63:0] bucket_frontend_wait,
    input bucket_frontend_wait_fire,
    input epoch_recovery_now,
    input ptw_wait_now,
    input icache_miss_delta,
    input icache_req_delta,
    input ifid_queue_full_now,
    input id_not_ready_now,
    input ex_not_ready_now,
    input if_pipe_req_not_ready_now,
    input if_pipe_no_resp_now,
    input frontend_self_wait_now,
    input frontend_backpressure_like_now,
    input ibus_req_valid,
    input ibus_req_ready
);
    reg [63:0] frontend_self_wait;
    reg [63:0] frontend_backpressure_wait;
    reg [63:0] frontend_ifid_queue_full_wait;
    reg [63:0] frontend_id_not_ready_backpressure;
    reg [63:0] frontend_ex_not_ready_backpressure;
    reg [63:0] frontend_if_pipe_no_resp_wait;
    reg [63:0] frontend_if_pipe_req_not_ready_wait;
    reg [63:0] frontend_icache_miss_refill_wait;
    reg [63:0] frontend_icache_req_wait;
    reg [63:0] frontend_epoch_drop_recovery_wait;
    reg [63:0] frontend_ptw_wait;
    reg [63:0] frontend_unknown;

    wire [63:0] frontend_sum =
        frontend_self_wait + frontend_backpressure_wait +
        frontend_ifid_queue_full_wait + frontend_id_not_ready_backpressure +
        frontend_ex_not_ready_backpressure + frontend_if_pipe_no_resp_wait +
        frontend_if_pipe_req_not_ready_wait + frontend_icache_miss_refill_wait +
        frontend_icache_req_wait + frontend_epoch_drop_recovery_wait +
        frontend_ptw_wait + frontend_unknown;
    wire [63:0] frontend_mismatch = (frontend_sum >= bucket_frontend_wait) ?
        (frontend_sum - bucket_frontend_wait) :
        (bucket_frontend_wait - frontend_sum);

    task print_stats;
        begin
            $display("[FrontendBreakdown] frontend_wait=%0d self_wait=%0d backpressure_wait=%0d ifid_full=%0d id_not_ready=%0d ex_mem_wb_backpressure=%0d no_resp=%0d req_not_ready=%0d icache_miss=%0d icache_req_wait=%0d epoch_recovery=%0d ptw=%0d unknown=%0d sum=%0d mismatch=%0d",
                bucket_frontend_wait, frontend_self_wait, frontend_backpressure_wait,
                frontend_ifid_queue_full_wait, frontend_id_not_ready_backpressure,
                frontend_ex_not_ready_backpressure, frontend_if_pipe_no_resp_wait,
                frontend_if_pipe_req_not_ready_wait, frontend_icache_miss_refill_wait,
                frontend_icache_req_wait, frontend_epoch_drop_recovery_wait,
                frontend_ptw_wait, frontend_unknown, frontend_sum, frontend_mismatch);
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            frontend_self_wait <= 64'd0;
            frontend_backpressure_wait <= 64'd0;
            frontend_ifid_queue_full_wait <= 64'd0;
            frontend_id_not_ready_backpressure <= 64'd0;
            frontend_ex_not_ready_backpressure <= 64'd0;
            frontend_if_pipe_no_resp_wait <= 64'd0;
            frontend_if_pipe_req_not_ready_wait <= 64'd0;
            frontend_icache_miss_refill_wait <= 64'd0;
            frontend_icache_req_wait <= 64'd0;
            frontend_epoch_drop_recovery_wait <= 64'd0;
            frontend_ptw_wait <= 64'd0;
            frontend_unknown <= 64'd0;
        end else if (sample_en && !real_commit && bucket_frontend_wait_fire) begin
            if (epoch_recovery_now) begin
                frontend_epoch_drop_recovery_wait <= frontend_epoch_drop_recovery_wait + 64'd1;
            end else if (ptw_wait_now) begin
                frontend_ptw_wait <= frontend_ptw_wait + 64'd1;
            end else if (icache_miss_delta) begin
                frontend_icache_miss_refill_wait <= frontend_icache_miss_refill_wait + 64'd1;
            end else if (icache_req_delta || (ibus_req_valid && !ibus_req_ready)) begin
                frontend_icache_req_wait <= frontend_icache_req_wait + 64'd1;
            end else if (ifid_queue_full_now) begin
                frontend_ifid_queue_full_wait <= frontend_ifid_queue_full_wait + 64'd1;
            end else if (id_not_ready_now) begin
                frontend_id_not_ready_backpressure <= frontend_id_not_ready_backpressure + 64'd1;
            end else if (ex_not_ready_now) begin
                frontend_ex_not_ready_backpressure <= frontend_ex_not_ready_backpressure + 64'd1;
            end else if (if_pipe_req_not_ready_now) begin
                frontend_if_pipe_req_not_ready_wait <= frontend_if_pipe_req_not_ready_wait + 64'd1;
            end else if (if_pipe_no_resp_now) begin
                frontend_if_pipe_no_resp_wait <= frontend_if_pipe_no_resp_wait + 64'd1;
            end else if (frontend_self_wait_now) begin
                frontend_self_wait <= frontend_self_wait + 64'd1;
            end else if (frontend_backpressure_like_now) begin
                frontend_backpressure_wait <= frontend_backpressure_wait + 64'd1;
            end else begin
                frontend_unknown <= frontend_unknown + 64'd1;
            end
        end
    end
endmodule
`endif
`endif
