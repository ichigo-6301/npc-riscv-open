`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_commit_trace_adapter #(
    parameter bit DUAL_TRACE_SINK_ENABLE = 1'b0
) (
    input  logic clk,
    input  logic reset,

    input  bbus_ooo_commit_event_t commit_event_i,
    input  logic exception_nextpc_valid_i,
    input  logic [31:0] exception_nextpc_i,

    output logic trace_can_accept1_o,
    output logic trace_can_accept2_o,
    output logic trace_valid_o,
    output logic trace1_valid_o,
    input  logic trace_ready_i,
    output bbus_ooo_commit_trace_packet_t trace_packet_o,
    output bbus_ooo_commit_trace_packet_t trace_packet1_o,

    output logic debug_packet_buffer_valid_o,
    output logic debug_last_packet_accepted_o,
    output logic debug_last_commit_dropped_o,
    output logic debug_commit2_trace_slot1_o,
    output logic [2:0] debug_fifo_count_o,
    output logic [1:0] debug_enqueue_count_o,
    output logic [1:0] debug_dequeue_count_o,
    output logic debug_packet_accepted_o,
    output logic debug_fifo_overflow_o
);
    localparam int TRACE_FIFO_DEPTH = 4;

    bbus_ooo_commit_trace_packet_t fifo_q [TRACE_FIFO_DEPTH-1:0];
    bbus_ooo_commit_trace_packet_t fifo_d [TRACE_FIFO_DEPTH-1:0];
    logic [2:0] fifo_count_q;
    logic [2:0] fifo_count_d;

    logic slot0_commit;
    logic slot1_commit;
    logic illegal_slot1_only;
    logic supported_fence_side_effect;
    logic supported_fencei_control;
    logic supported_exception_control;
    logic unsupported_side_effect_commit;
    logic unsupported_control_commit;
    logic unsupported_commit;
    logic packet_accepted;
    logic [1:0] dequeue_count;
    logic [1:0] enqueue_count;
    logic [2:0] free_after_pop;
    logic fifo_overflow;
    logic drop_commit;

    function automatic bbus_ooo_commit_trace_packet_t make_trace_packet(
        input bbus_ooo_commit_slot_t commit_slot,
        input logic [1:0] commit_mask,
        input logic commit_slot1,
        input logic unsupported,
        input logic nextpc_override_valid,
        input logic [31:0] nextpc_override
    );
        begin
            make_trace_packet = '0;
            make_trace_packet.valid = 1'b1;
            make_trace_packet.commit_mask = commit_mask;
            make_trace_packet.commit_slot1 = commit_slot1;
            make_trace_packet.pc = commit_slot.pc;
            make_trace_packet.instr = commit_slot.instr;
            make_trace_packet.rf_wen =
                commit_slot.rf_wen && (commit_slot.arch_rd != bbus_ooo_arch_reg_t'(5'd0));
            make_trace_packet.arch_rd = commit_slot.arch_rd;
            make_trace_packet.wdata = commit_slot.wdata;
            make_trace_packet.commit_nextpc = nextpc_override_valid ?
                nextpc_override : commit_slot.commit_nextpc;
            make_trace_packet.is_control = commit_slot.is_control;
            make_trace_packet.is_branch = commit_slot.is_branch;
            make_trace_packet.is_jal = commit_slot.is_jal;
            make_trace_packet.is_jalr = commit_slot.is_jalr;
            make_trace_packet.is_load = commit_slot.is_load;
            make_trace_packet.is_store = commit_slot.is_store;
            make_trace_packet.mem_op = commit_slot.mem_op;
            make_trace_packet.mem_addr = commit_slot.mem_addr;
            make_trace_packet.mem_wdata = commit_slot.mem_wdata;
            make_trace_packet.mem_wstrb = commit_slot.mem_wstrb;
            make_trace_packet.mem_len = commit_slot.mem_len;
            make_trace_packet.exception_valid = commit_slot.exception.valid;
            make_trace_packet.exception_cause = commit_slot.exception.cause;
            make_trace_packet.unsupported = unsupported;
            make_trace_packet.rob_tag = commit_slot.rob_tag;
        end
    endfunction

    assign slot0_commit = commit_event_i.normal_commit_mask[0];
    assign slot1_commit = commit_event_i.normal_commit_mask[1];
    assign illegal_slot1_only = slot1_commit && !slot0_commit;
    assign supported_fence_side_effect =
        commit_event_i.side_effect_commit_valid &&
        (commit_event_i.side_effect_kind == BBUS_OOO_SIDE_FENCE) &&
        (commit_event_i.normal_commit_mask == 2'b01) &&
        !commit_event_i.control_event_valid &&
        (commit_event_i.slot0.instr[6:0] == 7'b0001111) &&
        (commit_event_i.slot0.instr[14:12] == 3'b000) &&
        (commit_event_i.slot0.instr[11:7] == 5'd0) &&
        (commit_event_i.slot0.instr[19:15] == 5'd0);
    assign supported_fencei_control =
        commit_event_i.control_event_valid &&
        (commit_event_i.control_event == BBUS_OOO_CTRL_FENCEI) &&
        (commit_event_i.normal_commit_mask == 2'b01) &&
        !commit_event_i.side_effect_commit_valid &&
        (commit_event_i.slot0.instr == 32'h0000_100f);
    assign supported_exception_control =
        commit_event_i.control_event_valid &&
        (commit_event_i.control_event == BBUS_OOO_CTRL_EXCEPTION) &&
        (commit_event_i.normal_commit_mask == 2'b00) &&
        !commit_event_i.side_effect_commit_valid &&
        commit_event_i.slot0.valid &&
        commit_event_i.slot0.exception.valid;
    assign unsupported_side_effect_commit =
        commit_event_i.side_effect_commit_valid &&
        !((commit_event_i.side_effect_kind == BBUS_OOO_SIDE_STORE) ||
          supported_fence_side_effect);
    assign unsupported_control_commit =
        commit_event_i.control_event_valid &&
        !supported_fencei_control &&
        !supported_exception_control;
    assign unsupported_commit =
        unsupported_side_effect_commit ||
        unsupported_control_commit ||
        illegal_slot1_only;
    always_comb begin
        dequeue_count = 2'd0;
        if (trace_ready_i && (fifo_count_q != 3'd0)) begin
            if (DUAL_TRACE_SINK_ENABLE && (fifo_count_q >= 3'd2))
                dequeue_count = 2'd2;
            else
                dequeue_count = 2'd1;
        end
    end
    assign packet_accepted = (dequeue_count != 2'd0);
    assign enqueue_count = {1'b0, slot0_commit} +
        {1'b0, slot1_commit} + {1'b0, supported_exception_control};
    assign free_after_pop =
        3'd4 - fifo_count_q + {1'b0, dequeue_count};
    assign fifo_overflow = ({1'b0, enqueue_count} > free_after_pop);
    assign drop_commit =
        fifo_overflow ||
        unsupported_commit;

    assign trace_can_accept1_o = (free_after_pop >= 3'd1);
    assign trace_can_accept2_o = (free_after_pop >= 3'd2);
    assign trace_valid_o = (fifo_count_q != 3'd0);
    assign trace1_valid_o = DUAL_TRACE_SINK_ENABLE &&
        (fifo_count_q >= 3'd2);
    assign trace_packet_o = (fifo_count_q != 3'd0) ? fifo_q[0] : '0;
    assign trace_packet1_o = trace1_valid_o ? fifo_q[1] : '0;
    assign debug_packet_buffer_valid_o = (fifo_count_q != 3'd0);
    assign debug_fifo_count_o = fifo_count_q;
    assign debug_enqueue_count_o = enqueue_count;
    assign debug_dequeue_count_o = dequeue_count;
    assign debug_packet_accepted_o = packet_accepted;
    assign debug_fifo_overflow_o = fifo_overflow;

    always_comb begin
        int i;
        int out_idx;

        for (i = 0; i < TRACE_FIFO_DEPTH; i = i + 1) begin
            fifo_d[i] = '0;
        end
        fifo_count_d = fifo_count_q - {1'b0, dequeue_count};

        out_idx = 0;
        for (i = 0; i < TRACE_FIFO_DEPTH; i = i + 1) begin
            if (i + dequeue_count < fifo_count_q) begin
                fifo_d[out_idx] = fifo_q[i + dequeue_count];
                out_idx = out_idx + 1;
            end
        end

        if (slot0_commit && !fifo_overflow && !illegal_slot1_only) begin
            fifo_d[fifo_count_d[1:0]] = make_trace_packet(
                commit_event_i.slot0,
                commit_event_i.normal_commit_mask,
                1'b0,
                unsupported_commit,
                1'b0,
                32'b0
            );
            fifo_count_d = fifo_count_d + 3'd1;
        end
        if (slot1_commit && slot0_commit && !fifo_overflow) begin
            fifo_d[fifo_count_d[1:0]] = make_trace_packet(
                commit_event_i.slot1,
                commit_event_i.normal_commit_mask,
                1'b1,
                unsupported_commit,
                1'b0,
                32'b0
            );
            fifo_count_d = fifo_count_d + 3'd1;
        end
        if (supported_exception_control && !fifo_overflow) begin
            fifo_d[fifo_count_d[1:0]] = make_trace_packet(
                commit_event_i.slot0,
                2'b01,
                1'b0,
                1'b0,
                exception_nextpc_valid_i,
                exception_nextpc_i
            );
            fifo_count_d = fifo_count_d + 3'd1;
        end
    end

    always_ff @(posedge clk) begin
        integer i;

        if (reset) begin
            for (i = 0; i < TRACE_FIFO_DEPTH; i = i + 1) begin
                fifo_q[i] <= '0;
            end
            fifo_count_q <= 3'd0;
            debug_last_packet_accepted_o <= 1'b0;
            debug_last_commit_dropped_o <= 1'b0;
            debug_commit2_trace_slot1_o <= 1'b0;
        end else begin
            for (i = 0; i < TRACE_FIFO_DEPTH; i = i + 1) begin
                fifo_q[i] <= fifo_d[i];
            end
            fifo_count_q <= fifo_count_d;
            debug_last_packet_accepted_o <= packet_accepted;
            debug_last_commit_dropped_o <= drop_commit;
            debug_commit2_trace_slot1_o <=
                ((dequeue_count != 2'd0) && trace_packet_o.valid &&
                 trace_packet_o.commit_mask[1] &&
                 trace_packet_o.commit_slot1) ||
                ((dequeue_count == 2'd2) && trace_packet1_o.valid &&
                 trace_packet1_o.commit_mask[1] &&
                 trace_packet1_o.commit_slot1);
        end
    end
endmodule
