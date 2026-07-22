`timescale 1ns / 1ps

`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
module StatStageLatencyBreakdown (
    input clk,
    input rst_n,
    input sample_en,
    input [63:0] bucket_stage_latency,
    input bucket_stage_latency_fire,
    input ms_valid,
    input ms_to_ws_valid,
    input es_valid,
    input es_to_ms_valid,
    input ds_to_es_valid,
    input fs_to_ds_valid,
    input if_stat_fs_valid
);
    reg [63:0] stage_latency_ifid_valid;
    reg [63:0] stage_latency_id_valid;
    reg [63:0] stage_latency_ex_valid;
    reg [63:0] stage_latency_mem_valid;
    reg [63:0] stage_latency_frontend_empty;

    task print_stats;
        begin
            $display("[StageLatencyBreakdown] stage_latency=%0d ifid_valid=%0d id_valid=%0d ex_valid=%0d mem_valid=%0d frontend_empty=%0d",
                bucket_stage_latency, stage_latency_ifid_valid,
                stage_latency_id_valid, stage_latency_ex_valid,
                stage_latency_mem_valid, stage_latency_frontend_empty);
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            stage_latency_ifid_valid <= 64'd0;
            stage_latency_id_valid <= 64'd0;
            stage_latency_ex_valid <= 64'd0;
            stage_latency_mem_valid <= 64'd0;
            stage_latency_frontend_empty <= 64'd0;
        end else if (sample_en && bucket_stage_latency_fire) begin
            if (ms_valid || ms_to_ws_valid) begin
                stage_latency_mem_valid <= stage_latency_mem_valid + 64'd1;
            end else if (es_valid || es_to_ms_valid) begin
                stage_latency_ex_valid <= stage_latency_ex_valid + 64'd1;
            end else if (ds_to_es_valid) begin
                stage_latency_id_valid <= stage_latency_id_valid + 64'd1;
            end else if (fs_to_ds_valid || if_stat_fs_valid) begin
                stage_latency_ifid_valid <= stage_latency_ifid_valid + 64'd1;
            end else begin
                stage_latency_frontend_empty <= stage_latency_frontend_empty + 64'd1;
            end
        end
    end
endmodule
`endif
`endif
