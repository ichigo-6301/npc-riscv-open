`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_pipeline_completion_fabric_2w #(
    parameter bit PAIR_RAW_TO_FINAL_BYPASS_ENABLE = 1'b0,
    parameter bit BRU_RAW_TO_FINAL_BYPASS_ENABLE = 1'b0,
    parameter bit STORE_ISSUE_FINAL_FALLTHROUGH_ENABLE = 1'b0,
    parameter bit SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE = 1'b0
) (
    input  logic clk,
    input  logic reset,
    input  logic flush_i,
    input  logic selective_kill_valid_i,
    input  logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_i,
    input  bbus_ooo_rob_idx_t rob_head_i,

    input  bbus_ooo_writeback_t alu0_wb_i,
    input  logic alu0_valid_i,
    input  logic alu0_rob_match_i,
    input  logic alu0_killed_i,
    input  bbus_ooo_writeback_t alu1_wb_i,
    input  logic alu1_valid_i,
    input  logic alu1_rob_match_i,
    input  logic alu1_killed_i,
    input  bbus_ooo_writeback_t lsu_load_wb_i,
    input  logic lsu_load_valid_i,
    input  logic lsu_load_rob_match_i,
    input  logic lsu_load_killed_i,

    input  bbus_ooo_writeback_t bru_wb_i,
    input  logic bru_valid_i,
    input  logic bru_rob_match_i,
    input  logic bru_killed_i,
    input  bbus_ooo_writeback_t lsu_exception_wb_i,
    input  logic lsu_exception_valid_i,
    input  logic lsu_exception_rob_match_i,
    input  logic lsu_exception_killed_i,
    input  bbus_ooo_writeback_t csr_wb_i,
    input  logic csr_valid_i,
    input  logic csr_rob_match_i,
    input  logic csr_killed_i,
    input  bbus_ooo_writeback_t system_wb_i,
    input  logic system_valid_i,
    input  logic system_rob_match_i,
    input  logic system_killed_i,
    input  bbus_ooo_writeback_t mdu_wb_i,
    input  logic mdu_valid_i,
    input  logic mdu_rob_match_i,
    input  logic mdu_killed_i,
    input  bbus_ooo_writeback_t amo_wb_i,
    input  logic amo_valid_i,
    input  logic amo_rob_match_i,
    input  logic amo_killed_i,

    input  logic final_consumer_ready_i,
    input  logic [1:0] final_consumer_accept_mask_i,
    input  logic [1:0] final_consumer_drop_mask_i,

    output logic [2:0] pair_source_accept_mask_o,
    output logic [2:0] pair_source_drop_mask_o,
    output logic [2:0] pair_source_clear_mask_o,
    output logic [5:0] serial_source_accept_mask_o,
    output logic [5:0] serial_source_drop_mask_o,
    output logic [5:0] serial_source_clear_mask_o,

    output bbus_ooo_writeback_t final_wb0_o,
    output bbus_ooo_writeback_t final_wb1_o,
    output logic [1:0] final_valid_mask_o,
    output logic [1:0] final_consume_mask_o,
    output logic [1:0] final_drop_mask_o,
    output logic [1:0] ordinary_wakeup_valid_o,
    output bbus_ooo_phys_reg_t wakeup_phys0_o,
    output bbus_ooo_phys_reg_t wakeup_phys1_o,

    output logic [1:0] active_owner_o,
    output logic [2:0] selected_serial_source_id_o,
    output logic serial_selected_o,
    output logic serial_buffer_full_o,
    output logic [1:0] dual_pending_count_o,
    output logic raw_window_open_o,
    output logic serial_priority_block_o,
    output logic [63:0] perf_completion_ownership_o,
    output logic cross_owner_guard_o,
    output logic conservation_error_o
);
    localparam int SERIAL_N = 6;
    localparam logic [2:0] SERIAL_BRU    = 3'd0;
    localparam logic [2:0] SERIAL_LSU_EX = 3'd1;
    localparam logic [2:0] SERIAL_CSR    = 3'd2;
    localparam logic [2:0] SERIAL_SYSTEM = 3'd3;
    localparam logic [2:0] SERIAL_MDU    = 3'd4;
    localparam logic [2:0] SERIAL_AMO    = 3'd5;
    localparam logic [2:0] SERIAL_NONE   = 3'd7;
    localparam logic [1:0] OWNER_NONE   = 2'd0;
    localparam logic [1:0] OWNER_DUAL   = 2'd1;
    localparam logic [1:0] OWNER_SERIAL = 2'd2;
    localparam int ROB_N = `BBUS_OOO_ROB_ENTRIES;

    bbus_ooo_writeback_t serial_wb [SERIAL_N-1:0];
    logic [SERIAL_N-1:0] serial_valid;
    logic [SERIAL_N-1:0] serial_match;
    logic [SERIAL_N-1:0] serial_killed;
    logic [SERIAL_N-1:0] serial_eligible;
    logic [SERIAL_N-1:0] serial_stale;
    integer serial_best;
    integer serial_best_age;
    logic serial_best_valid;

    bbus_ooo_writeback_t adapter_lane0_wb;
    bbus_ooo_writeback_t adapter_lane1_wb;
    logic adapter_lane0_valid;
    logic adapter_lane1_valid;
    logic [2:0] adapter_accept_mask;
    logic [2:0] adapter_drop_mask;
    logic [2:0] adapter_clear_mask;
    logic [2:0] adapter_selected_mask;
    logic [1:0] wrapper_source_accept_mask;
    logic [1:0] wrapper_source_drop_mask;
    logic [1:0] wrapper_source_clear_mask;
    logic [1:0] wrapper_final_valid_mask;
    logic [1:0] wrapper_final_drop_mask;
    bbus_ooo_writeback_t wrapper_final_wb0;
    bbus_ooo_writeback_t wrapper_final_wb1;
    logic [1:0] wrapper_wakeup_valid;
    bbus_ooo_phys_reg_t wrapper_wakeup_phys0;
    bbus_ooo_phys_reg_t wrapper_wakeup_phys1;
    logic [1:0] wrapper_pending_count;
    logic wrapper_buffer_empty;
    logic [1:0] wrapper_registered_final_valid_mask;
    logic wrapper_conservation_error;

    bbus_ooo_writeback_t serial_selected_wb;
    logic serial_capture_valid;
    logic serial_capture_ready;
    logic serial_capture_fire;
    logic serial_selective_drop;
    logic [1:0] wrapper_selective_final_drop;
    logic [1:0] wrapper_selective_pending_drop;
    bbus_ooo_writeback_t serial_buffer_wb;
    logic serial_buffer_valid;
    logic serial_buffer_accept;
    logic serial_buffer_drop;
    logic dual_owner_active;
    logic serial_owner_active;
    logic pair_raw_enable;
    logic bru_direct_active;
    logic bru_direct_terminal;
    logic store_direct_active;
    logic store_direct_terminal;
    logic serial_direct_active;
    logic serial_direct_terminal;
    logic serial_final_active;
    logic concurrent_pair_window;
    logic concurrent_ordinary_active;
    logic concurrent_wrapper_lane;
    logic concurrent_ordinary_terminal;
    logic [1:0] wrapper_consumer_accept_mask;
    logic [1:0] wrapper_consumer_drop_mask;
    logic wrapper_consumer_ready;
    logic concurrent_duplicate_guard;

    function automatic logic ordinary_wakeup(input bbus_ooo_writeback_t wb);
        begin
            ordinary_wakeup =
                wb.valid && wb.rf_wen &&
                (wb.phys_rd != `BBUS_OOO_PHYS_ZERO) &&
                !wb.exception.valid;
        end
    endfunction

    assign serial_wb[SERIAL_BRU] = bru_wb_i;
    assign serial_wb[SERIAL_LSU_EX] = lsu_exception_wb_i;
    assign serial_wb[SERIAL_CSR] = csr_wb_i;
    assign serial_wb[SERIAL_SYSTEM] = system_wb_i;
    assign serial_wb[SERIAL_MDU] = mdu_wb_i;
    assign serial_wb[SERIAL_AMO] = amo_wb_i;
    assign serial_valid = {
        amo_valid_i, mdu_valid_i, system_valid_i, csr_valid_i,
        lsu_exception_valid_i, bru_valid_i
    };
    assign serial_match = {
        amo_rob_match_i, mdu_rob_match_i, system_rob_match_i, csr_rob_match_i,
        lsu_exception_rob_match_i, bru_rob_match_i
    };
    assign serial_killed = {
        amo_killed_i, mdu_killed_i, system_killed_i, csr_killed_i,
        lsu_exception_killed_i, bru_killed_i
    };

    always_comb begin
        int candidate_age;
        serial_best = 0;
        serial_best_age = 0;
        candidate_age = 0;
        serial_best_valid = 1'b0;
        serial_selected_wb = '0;
        selected_serial_source_id_o = SERIAL_NONE;
        serial_eligible[0] = bru_valid_i && bru_wb_i.valid && bru_rob_match_i && !bru_killed_i;
        serial_eligible[1] = lsu_exception_valid_i && lsu_exception_wb_i.valid && lsu_exception_rob_match_i && !lsu_exception_killed_i;
        serial_eligible[2] = csr_valid_i && csr_wb_i.valid && csr_rob_match_i && !csr_killed_i;
        serial_eligible[3] = system_valid_i && system_wb_i.valid && system_rob_match_i && !system_killed_i;
        serial_eligible[4] = mdu_valid_i && mdu_wb_i.valid && mdu_rob_match_i && !mdu_killed_i;
        serial_eligible[5] = amo_valid_i && amo_wb_i.valid && amo_rob_match_i && !amo_killed_i;
        serial_stale[0] = bru_valid_i && bru_wb_i.valid && (!bru_rob_match_i || bru_killed_i);
        serial_stale[1] = lsu_exception_valid_i && lsu_exception_wb_i.valid && (!lsu_exception_rob_match_i || lsu_exception_killed_i);
        serial_stale[2] = csr_valid_i && csr_wb_i.valid && (!csr_rob_match_i || csr_killed_i);
        serial_stale[3] = system_valid_i && system_wb_i.valid && (!system_rob_match_i || system_killed_i);
        serial_stale[4] = mdu_valid_i && mdu_wb_i.valid && (!mdu_rob_match_i || mdu_killed_i);
        serial_stale[5] = amo_valid_i && amo_wb_i.valid && (!amo_rob_match_i || amo_killed_i);

        if (serial_eligible[0]) begin
            serial_best=0; serial_best_age=(int'(bru_wb_i.rob_tag.idx)+ROB_N-int'(rob_head_i))%ROB_N;
            serial_best_valid=1; serial_selected_wb=bru_wb_i; selected_serial_source_id_o=SERIAL_BRU;
        end
        candidate_age=(int'(lsu_exception_wb_i.rob_tag.idx)+ROB_N-int'(rob_head_i))%ROB_N;
        if (serial_eligible[1] && (!serial_best_valid || candidate_age<serial_best_age)) begin
            serial_best=1; serial_best_age=candidate_age; serial_best_valid=1; serial_selected_wb=lsu_exception_wb_i; selected_serial_source_id_o=SERIAL_LSU_EX;
        end
        candidate_age=(int'(csr_wb_i.rob_tag.idx)+ROB_N-int'(rob_head_i))%ROB_N;
        if (serial_eligible[2] && (!serial_best_valid || candidate_age<serial_best_age)) begin
            serial_best=2; serial_best_age=candidate_age; serial_best_valid=1; serial_selected_wb=csr_wb_i; selected_serial_source_id_o=SERIAL_CSR;
        end
        candidate_age=(int'(system_wb_i.rob_tag.idx)+ROB_N-int'(rob_head_i))%ROB_N;
        if (serial_eligible[3] && (!serial_best_valid || candidate_age<serial_best_age)) begin
            serial_best=3; serial_best_age=candidate_age; serial_best_valid=1; serial_selected_wb=system_wb_i; selected_serial_source_id_o=SERIAL_SYSTEM;
        end
        candidate_age=(int'(mdu_wb_i.rob_tag.idx)+ROB_N-int'(rob_head_i))%ROB_N;
        if (serial_eligible[4] && (!serial_best_valid || candidate_age<serial_best_age)) begin
            serial_best=4; serial_best_age=candidate_age; serial_best_valid=1; serial_selected_wb=mdu_wb_i; selected_serial_source_id_o=SERIAL_MDU;
        end
        candidate_age=(int'(amo_wb_i.rob_tag.idx)+ROB_N-int'(rob_head_i))%ROB_N;
        if (serial_eligible[5] && (!serial_best_valid || candidate_age<serial_best_age)) begin
            serial_best=5; serial_best_age=candidate_age; serial_best_valid=1; serial_selected_wb=amo_wb_i; selected_serial_source_id_o=SERIAL_AMO;
        end
    end

    assign serial_owner_active = serial_buffer_valid;
    assign dual_owner_active =
        (wrapper_pending_count != 2'b00) ||
        (wrapper_registered_final_valid_mask != 2'b00);
    assign raw_window_open_o =
        !flush_i && !selective_kill_valid_i && !serial_owner_active &&
        !dual_owner_active;
    assign serial_selected_o = serial_best_valid;
    assign serial_priority_block_o = raw_window_open_o && serial_best_valid;
    assign concurrent_pair_window =
        SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE &&
        !flush_i && !selective_kill_valid_i && !dual_owner_active &&
        (serial_owner_active ||
         (raw_window_open_o && serial_best_valid));
    assign pair_raw_enable =
        (raw_window_open_o && !serial_best_valid) || concurrent_pair_window;

    assign bru_direct_active = BRU_RAW_TO_FINAL_BYPASS_ENABLE &&
        raw_window_open_o && serial_best_valid &&
        (selected_serial_source_id_o == SERIAL_BRU);
    assign bru_direct_terminal = bru_direct_active &&
        (final_consume_mask_o[0] || final_drop_mask_o[0]);
    assign store_direct_active = STORE_ISSUE_FINAL_FALLTHROUGH_ENABLE &&
        raw_window_open_o && serial_best_valid &&
        (selected_serial_source_id_o == SERIAL_LSU_EX) &&
        serial_selected_wb.is_store && !serial_selected_wb.exception.valid;
    assign store_direct_terminal = store_direct_active &&
        (final_consume_mask_o[0] || final_drop_mask_o[0]);
    assign serial_direct_active = bru_direct_active || store_direct_active;
    assign serial_direct_terminal = bru_direct_terminal ||
        store_direct_terminal;
    assign serial_capture_valid = raw_window_open_o && serial_best_valid &&
        !serial_direct_terminal;
    assign serial_capture_fire = serial_capture_valid && serial_capture_ready;
    assign serial_final_active = serial_owner_active || serial_direct_active;

    alu_wb_buffer_1w u_serial_buffer (
        .clk(clk),
        .reset(reset),
        .flush_i(flush_i),
        .selective_kill_valid_i(selective_kill_valid_i),
        .selective_killed_rob_mask_i(selective_killed_rob_mask_i),
        .selective_kill_drop_o(serial_selective_drop),
        .in_wb_i(serial_selected_wb),
        .in_valid_i(serial_capture_valid),
        .in_ready_o(serial_capture_ready),
        .out_wb_o(serial_buffer_wb),
        .out_valid_o(serial_buffer_valid),
        .out_accepted_i(serial_buffer_accept),
        .out_drop_i(serial_buffer_drop),
        .debug_full_o(serial_buffer_full_o)
    );

    always_comb begin
        int i;
        serial_source_accept_mask_o = 6'b0;
        serial_source_drop_mask_o = 6'b0;
        if (serial_capture_fire || serial_direct_terminal) begin
            serial_source_accept_mask_o[serial_best] = 1'b1;
        end
        if (raw_window_open_o) begin
            for (i = 0; i < SERIAL_N; i++) begin
                serial_source_drop_mask_o[i] = serial_stale[i];
            end
        end
        serial_source_clear_mask_o =
            serial_source_accept_mask_o | serial_source_drop_mask_o;
    end

    ooo_dual_wb_lsu_load_adapter_3src u_pair_adapter (
        .clk(clk),
        .reset(reset),
        .rob_head_i(rob_head_i),
        .alu0_wb_i(alu0_wb_i),
        .alu0_valid_i(pair_raw_enable && alu0_valid_i),
        .alu0_rob_match_i(alu0_rob_match_i),
        .alu0_killed_i(alu0_killed_i),
        .alu1_wb_i(alu1_wb_i),
        .alu1_valid_i(pair_raw_enable && alu1_valid_i),
        .alu1_rob_match_i(alu1_rob_match_i),
        .alu1_killed_i(alu1_killed_i),
        .lsu_wb_i(lsu_load_wb_i),
        .lsu_valid_i(pair_raw_enable && lsu_load_valid_i),
        .lsu_rob_match_i(lsu_load_rob_match_i),
        .lsu_killed_i(lsu_load_killed_i),
        .pending_nonempty_i(!pair_raw_enable),
        .wrapper_source_accept_mask_i(wrapper_source_accept_mask),
        .wrapper_source_drop_mask_i(wrapper_source_drop_mask),
        .wrapper_source_clear_mask_i(wrapper_source_clear_mask),
        .lane0_wb_o(adapter_lane0_wb),
        .lane1_wb_o(adapter_lane1_wb),
        .lane0_valid_o(adapter_lane0_valid),
        .lane1_valid_o(adapter_lane1_valid),
        .selected_source_mask_o(adapter_selected_mask),
        .source_accept_mask_o(adapter_accept_mask),
        .source_drop_mask_o(adapter_drop_mask),
        .source_clear_mask_o(adapter_clear_mask)
    );

    assign pair_source_accept_mask_o = adapter_accept_mask;
    assign pair_source_drop_mask_o = adapter_drop_mask;
    assign pair_source_clear_mask_o = adapter_clear_mask;

    always_comb begin
        wrapper_consumer_ready =
            final_consumer_ready_i && !serial_owner_active;
        wrapper_consumer_accept_mask = final_consumer_accept_mask_i;
        wrapper_consumer_drop_mask = final_consumer_drop_mask_i;
        concurrent_wrapper_lane = 1'b0;

        if (SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE &&
            serial_final_active) begin
            wrapper_consumer_ready = final_consumer_ready_i;
            wrapper_consumer_accept_mask = 2'b00;
            wrapper_consumer_drop_mask = 2'b00;
            if (wrapper_final_valid_mask[0]) begin
                concurrent_wrapper_lane = 1'b0;
                wrapper_consumer_accept_mask[0] =
                    final_consumer_accept_mask_i[1];
                wrapper_consumer_drop_mask[0] =
                    final_consumer_drop_mask_i[1];
            end else if (wrapper_final_valid_mask[1]) begin
                concurrent_wrapper_lane = 1'b1;
                wrapper_consumer_accept_mask[1] =
                    final_consumer_accept_mask_i[1];
                wrapper_consumer_drop_mask[1] =
                    final_consumer_drop_mask_i[1];
            end
        end
    end

    ooo_dual_wb_buffered_wrapper_2w #(
        .RAW_TO_FINAL_BYPASS_ENABLE(PAIR_RAW_TO_FINAL_BYPASS_ENABLE)
    ) u_pair_wrapper (
        .clk(clk),
        .reset(reset),
        .selective_kill_valid_i(selective_kill_valid_i),
        .selective_killed_rob_mask_i(selective_killed_rob_mask_i),
        .wb0_i(adapter_lane0_wb),
        .wb1_i(adapter_lane1_wb),
        .wb0_rob_match_i(1'b1),
        .wb1_rob_match_i(1'b1),
        .wb0_killed_i(1'b0),
        .wb1_killed_i(1'b0),
        .lane0_consumer_block_i(1'b0),
        .lane1_consumer_block_i(1'b0),
        .lane1_buffer_full_i(1'b0),
        .lane1_ordering_block_i(1'b0),
        .final_consumer_ready_i(wrapper_consumer_ready),
        .final_consumer_accept_mask_i(wrapper_consumer_accept_mask),
        .final_consumer_drop_mask_i(wrapper_consumer_drop_mask),
        .flush_i(flush_i),
        .selective_final_drop_mask_o(wrapper_selective_final_drop),
        .selective_pending_drop_mask_o(wrapper_selective_pending_drop),
        .source_accept_mask_o(wrapper_source_accept_mask),
        .source_drop_mask_o(wrapper_source_drop_mask),
        .source_clear_mask_o(wrapper_source_clear_mask),
        .final_accept_mask_o(wrapper_final_valid_mask),
        .final_drop_mask_o(wrapper_final_drop_mask),
        .wb0_final_o(wrapper_final_wb0),
        .wb1_final_o(wrapper_final_wb1),
        .ordinary_wakeup_valid_final_o(wrapper_wakeup_valid),
        .wakeup_phys0_final_o(wrapper_wakeup_phys0),
        .wakeup_phys1_final_o(wrapper_wakeup_phys1),
        .pending_count_o(wrapper_pending_count),
        .buffer_empty_o(wrapper_buffer_empty),
        .registered_final_valid_mask_o(
            wrapper_registered_final_valid_mask),
        .conservation_error_o(wrapper_conservation_error)
    );

    assign concurrent_ordinary_active =
        SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE &&
        serial_final_active && (wrapper_final_valid_mask != 2'b00);

    always_comb begin
        final_wb0_o = '0;
        final_wb1_o = '0;
        final_valid_mask_o = 2'b00;
        ordinary_wakeup_valid_o = 2'b00;
        wakeup_phys0_o = `BBUS_OOO_PHYS_ZERO;
        wakeup_phys1_o = `BBUS_OOO_PHYS_ZERO;

        if (!flush_i && !selective_kill_valid_i) begin
            if (serial_owner_active) begin
                final_wb0_o = serial_buffer_wb;
                final_valid_mask_o = 2'b01;
                ordinary_wakeup_valid_o[0] = ordinary_wakeup(serial_buffer_wb);
                wakeup_phys0_o = serial_buffer_wb.phys_rd;
                if (concurrent_ordinary_active) begin
                    final_wb1_o = concurrent_wrapper_lane ?
                        wrapper_final_wb1 : wrapper_final_wb0;
                    final_valid_mask_o[1] = 1'b1;
                    ordinary_wakeup_valid_o[1] = concurrent_wrapper_lane ?
                        wrapper_wakeup_valid[1] : wrapper_wakeup_valid[0];
                    wakeup_phys1_o = concurrent_wrapper_lane ?
                        wrapper_wakeup_phys1 : wrapper_wakeup_phys0;
                end
            end else if (serial_direct_active) begin
                final_wb0_o = serial_selected_wb;
                final_valid_mask_o = 2'b01;
                ordinary_wakeup_valid_o[0] =
                    ordinary_wakeup(serial_selected_wb);
                wakeup_phys0_o = serial_selected_wb.phys_rd;
                if (concurrent_ordinary_active) begin
                    final_wb1_o = concurrent_wrapper_lane ?
                        wrapper_final_wb1 : wrapper_final_wb0;
                    final_valid_mask_o[1] = 1'b1;
                    ordinary_wakeup_valid_o[1] = concurrent_wrapper_lane ?
                        wrapper_wakeup_valid[1] : wrapper_wakeup_valid[0];
                    wakeup_phys1_o = concurrent_wrapper_lane ?
                        wrapper_wakeup_phys1 : wrapper_wakeup_phys0;
                end
            end else begin
                final_wb0_o = wrapper_final_wb0;
                final_wb1_o = wrapper_final_wb1;
                final_valid_mask_o = wrapper_final_valid_mask;
                ordinary_wakeup_valid_o = wrapper_wakeup_valid;
                wakeup_phys0_o = wrapper_wakeup_phys0;
                wakeup_phys1_o = wrapper_wakeup_phys1;
            end
        end

        final_consume_mask_o = final_consumer_ready_i ?
            (final_valid_mask_o & final_consumer_accept_mask_i) : 2'b00;
        final_drop_mask_o = final_consumer_ready_i ?
            (final_valid_mask_o & final_consumer_drop_mask_i &
             ~final_consume_mask_o) : 2'b00;
    end

    assign serial_buffer_accept =
        serial_owner_active && final_consume_mask_o[0];
    assign serial_buffer_drop =
        serial_owner_active && final_drop_mask_o[0];
    assign concurrent_ordinary_terminal = concurrent_ordinary_active &&
        (final_consume_mask_o[1] || final_drop_mask_o[1]);

    assign concurrent_duplicate_guard = concurrent_ordinary_active &&
        final_wb0_o.rob_tag.valid && final_wb1_o.rob_tag.valid &&
        (final_wb0_o.rob_tag == final_wb1_o.rob_tag);

    always_comb begin
        if (serial_owner_active || serial_direct_active) begin
            active_owner_o = OWNER_SERIAL;
        end else if (dual_owner_active) begin
            active_owner_o = OWNER_DUAL;
        end else begin
            active_owner_o = OWNER_NONE;
        end
    end

    assign dual_pending_count_o = wrapper_pending_count;
    assign cross_owner_guard_o = serial_owner_active && dual_owner_active &&
        !SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE;
    assign conservation_error_o =
        wrapper_conservation_error || cross_owner_guard_o ||
        concurrent_duplicate_guard ||
        (bru_direct_active && store_direct_active) ||
        ((pair_source_accept_mask_o & pair_source_drop_mask_o) != 3'b0) ||
        ((serial_source_accept_mask_o & serial_source_drop_mask_o) != 6'b0);

    // Simulation observability only. This sideband never participates in
    // completion selection, ownership, backpressure, or architectural state.
    always_comb begin
        perf_completion_ownership_o = 64'b0;
        perf_completion_ownership_o[0] = raw_window_open_o;
        perf_completion_ownership_o[1] = serial_owner_active;
        perf_completion_ownership_o[2] = dual_owner_active;
        perf_completion_ownership_o[3] = serial_best_valid;
        perf_completion_ownership_o[6:4] = selected_serial_source_id_o;
        perf_completion_ownership_o[7] = serial_buffer_full_o;
        perf_completion_ownership_o[9:8] = wrapper_pending_count;
        perf_completion_ownership_o[11:10] =
            wrapper_registered_final_valid_mask;
        perf_completion_ownership_o[12] = bru_direct_active;
        perf_completion_ownership_o[13] = bru_direct_terminal;
        perf_completion_ownership_o[16:14] = adapter_selected_mask;
        perf_completion_ownership_o[19:17] = pair_source_accept_mask_o;
        perf_completion_ownership_o[22:20] = {
            lsu_load_valid_i && lsu_load_wb_i.valid && lsu_load_rob_match_i &&
                !lsu_load_killed_i,
            alu1_valid_i && alu1_wb_i.valid && alu1_rob_match_i &&
                !alu1_killed_i,
            alu0_valid_i && alu0_wb_i.valid && alu0_rob_match_i &&
                !alu0_killed_i
        };
        perf_completion_ownership_o[24:23] = final_valid_mask_o;
        perf_completion_ownership_o[26:25] = final_consume_mask_o;
        perf_completion_ownership_o[28:27] = final_drop_mask_o;
        perf_completion_ownership_o[29] = flush_i;
        perf_completion_ownership_o[30] = selective_kill_valid_i;
        perf_completion_ownership_o[31] = conservation_error_o;
        perf_completion_ownership_o[32] = final_consumer_ready_i;
        perf_completion_ownership_o[33] = pair_raw_enable;
        perf_completion_ownership_o[34] = wrapper_buffer_empty;
        perf_completion_ownership_o[35] = serial_capture_valid;
        perf_completion_ownership_o[36] = serial_capture_ready;
        perf_completion_ownership_o[37] = serial_capture_fire;
        perf_completion_ownership_o[38] =
            SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE;
        perf_completion_ownership_o[39] = serial_final_active;
        perf_completion_ownership_o[40] = concurrent_ordinary_active;
        perf_completion_ownership_o[41] = concurrent_wrapper_lane;
        perf_completion_ownership_o[42] = concurrent_ordinary_terminal;
        perf_completion_ownership_o[43] = concurrent_pair_window;
        perf_completion_ownership_o[44] = concurrent_duplicate_guard;
        perf_completion_ownership_o[45] =
            SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE &&
            (serial_source_accept_mask_o != 6'b0) &&
            ((pair_source_accept_mask_o == 3'b011) ||
             (pair_source_accept_mask_o == 3'b101) ||
             (pair_source_accept_mask_o == 3'b110));
        perf_completion_ownership_o[46] = store_direct_active;
        perf_completion_ownership_o[47] = store_direct_terminal;
        perf_completion_ownership_o[48] =
            STORE_ISSUE_FINAL_FALLTHROUGH_ENABLE;
    end
endmodule

// Moves ordinary ALU/load data availability to the raw-source capture edge.
// A marker remains live until the same exact packet reaches the final
// terminal edge, where the legacy PRF write is suppressed. Serial and
// exceptional packets continue to use the final path.
module ooo_raw_completion_wakeup_2w #(
    parameter bit ENABLE = 1'b0
) (
    input logic clk,
    input logic reset,
    input logic flush_i,
    input logic selective_kill_valid_i,
    input logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_i,

    input logic [2:0] raw_accept_mask_i,
    input bbus_ooo_writeback_t raw_alu0_wb_i,
    input bbus_ooo_writeback_t raw_alu1_wb_i,
    input bbus_ooo_writeback_t raw_lsu_wb_i,

    input logic [1:0] final_consume_mask_i,
    input logic [1:0] final_drop_mask_i,
    input logic [1:0] final_wakeup_mask_i,
    input bbus_ooo_writeback_t final_wb0_i,
    input bbus_ooo_writeback_t final_wb1_i,

    output logic [1:0] write_mask_o,
    output bbus_ooo_writeback_t write_wb0_o,
    output bbus_ooo_writeback_t write_wb1_o,
    output logic [2:0] early_source_mask_o,
    output logic [1:0] final_suppress_mask_o,
    output logic [3:0] marker_count_o,
    output logic conservation_error_o
);
    bbus_ooo_writeback_t raw_wb [2:0];
    logic [2:0] early_candidate_c;
    logic [`BBUS_OOO_ROB_ENTRIES-1:0] marker_valid_q;
    bbus_ooo_rob_tag_t marker_tag_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    bbus_ooo_phys_reg_t marker_phys_q [`BBUS_OOO_ROB_ENTRIES-1:0];
    logic [1:0] final_terminal_c;
    logic [1:0] final_marker_match_c;
    logic [1:0] final_same_cycle_raw_match_c;
    logic [1:0] final_selected_raw_match_c;
    logic [2:0] early_terminal_source_c;
    logic [2:0] early_consumed_source_c;
    logic protocol_error_c, protocol_error_q;

    function automatic logic ordinary_write(input bbus_ooo_writeback_t wb);
        ordinary_write = wb.valid && wb.rob_tag.valid && wb.rf_wen &&
            (wb.phys_rd != `BBUS_OOO_PHYS_ZERO) && !wb.exception.valid &&
            !wb.is_control && !wb.is_csr && !wb.is_system;
    endfunction

    function automatic logic exact_marker_match(
        input bbus_ooo_writeback_t wb
    );
        exact_marker_match = wb.rob_tag.valid &&
            marker_valid_q[wb.rob_tag.idx] &&
            (marker_tag_q[wb.rob_tag.idx] == wb.rob_tag) &&
            (marker_phys_q[wb.rob_tag.idx] == wb.phys_rd);
    endfunction

    function automatic logic exact_packet_match(
        input bbus_ooo_writeback_t a,
        input bbus_ooo_writeback_t b
    );
        exact_packet_match = a.valid && b.valid && a.rob_tag.valid &&
            (a.rob_tag == b.rob_tag) && (a.phys_rd == b.phys_rd);
    endfunction

    assign raw_wb[0] = raw_alu0_wb_i;
    assign raw_wb[1] = raw_alu1_wb_i;
    assign raw_wb[2] = raw_lsu_wb_i;
    assign final_terminal_c = final_consume_mask_i | final_drop_mask_i;
    assign final_marker_match_c[0] = ENABLE &&
        exact_marker_match(final_wb0_i);
    assign final_marker_match_c[1] = ENABLE &&
        exact_marker_match(final_wb1_i);
    always_comb begin
        final_same_cycle_raw_match_c = 2'b00;
        early_terminal_source_c = 3'b000;
        early_consumed_source_c = 3'b000;
        if (ENABLE) begin
            for (int lane = 0; lane < 2; lane = lane + 1) begin
                for (int source = 0; source < 3; source = source + 1) begin
                    if (raw_accept_mask_i[source] &&
                        ordinary_write(raw_wb[source]) &&
                        exact_packet_match(
                            lane == 0 ? final_wb0_i : final_wb1_i,
                            raw_wb[source])) begin
                        final_same_cycle_raw_match_c[lane] = 1'b1;
                        if (final_terminal_c[lane]) begin
                            early_terminal_source_c[source] = 1'b1;
                            if (final_consume_mask_i[lane] &&
                                final_wakeup_mask_i[lane])
                                early_consumed_source_c[source] = 1'b1;
                        end
                    end
                end
            end
        end
    end

    always_comb begin
        final_selected_raw_match_c = 2'b00;
        if (ENABLE) begin
            for (int lane = 0; lane < 2; lane = lane + 1) begin
                for (int source = 0; source < 3; source = source + 1) begin
                    if (early_source_mask_o[source] &&
                        exact_packet_match(
                            lane == 0 ? final_wb0_i : final_wb1_i,
                            raw_wb[source]))
                        final_selected_raw_match_c[lane] = 1'b1;
                end
            end
        end
    end
    assign final_suppress_mask_o = final_consume_mask_i &
        final_wakeup_mask_i &
        (final_marker_match_c | final_selected_raw_match_c);

    always_comb begin : select_write_edge
        integer source;
        integer write_lane;
        integer final_lane;

        early_candidate_c = 3'b000;
        early_source_mask_o = 3'b000;
        write_mask_o = 2'b00;
        write_wb0_o = '0;
        write_wb1_o = '0;
        protocol_error_c = 1'b0;
        write_lane = 0;

        if (!ENABLE) begin
            write_mask_o = final_consume_mask_i & final_wakeup_mask_i;
            write_wb0_o = final_wb0_i;
            write_wb1_o = final_wb1_i;
        end else begin
            for (source = 0; source < 3; source = source + 1) begin
                early_candidate_c[source] = raw_accept_mask_i[source] &&
                    ordinary_write(raw_wb[source]);
                if (raw_accept_mask_i[source] && raw_wb[source].valid &&
                    raw_wb[source].rf_wen && !ordinary_write(raw_wb[source]))
                    protocol_error_c = 1'b1;
            end

            // Final packets that do not correspond to a same-cycle raw
            // candidate own the write ports first. This preserves serial
            // results (for example a JAL link) when P34 pairs them with an
            // ordinary raw completion.
            for (final_lane = 0; final_lane < 2;
                 final_lane = final_lane + 1) begin
                if (final_consume_mask_i[final_lane] &&
                    final_wakeup_mask_i[final_lane] &&
                    !final_marker_match_c[final_lane] &&
                    !final_same_cycle_raw_match_c[final_lane]) begin
                    if (write_lane == 0) begin
                        write_mask_o[0] = 1'b1;
                        write_wb0_o = final_lane == 0 ?
                            final_wb0_i : final_wb1_i;
                    end else if (write_lane == 1) begin
                        write_mask_o[1] = 1'b1;
                        write_wb1_o = final_lane == 0 ?
                            final_wb0_i : final_wb1_i;
                    end
                    write_lane = write_lane + 1;
                end
            end

            // A raw packet that is also terminal at Final must be selected
            // before a retained raw packet; the terminal packet has no later
            // replay opportunity. Remaining raw packets may stay in the
            // completion wrapper and receive their normal Final write later.
            for (source = 0; source < 3; source = source + 1) begin
                if (early_candidate_c[source] &&
                    early_consumed_source_c[source] &&
                    (write_lane < 2)) begin
                    early_source_mask_o[source] = 1'b1;
                    if (write_lane == 0) begin
                        write_mask_o[0] = 1'b1;
                        write_wb0_o = raw_wb[source];
                    end else begin
                        write_mask_o[1] = 1'b1;
                        write_wb1_o = raw_wb[source];
                    end
                    write_lane = write_lane + 1;
                end
            end
            for (source = 0; source < 3; source = source + 1) begin
                if (early_candidate_c[source] &&
                    !early_terminal_source_c[source] &&
                    (write_lane < 2)) begin
                    early_source_mask_o[source] = 1'b1;
                    if (write_lane == 0) begin
                        write_mask_o[0] = 1'b1;
                        write_wb0_o = raw_wb[source];
                    end else begin
                        write_mask_o[1] = 1'b1;
                        write_wb1_o = raw_wb[source];
                    end
                    write_lane = write_lane + 1;
                end
            end

            if (early_candidate_c[0] && early_candidate_c[1] &&
                ((raw_wb[0].rob_tag == raw_wb[1].rob_tag) ||
                 (raw_wb[0].phys_rd == raw_wb[1].phys_rd)))
                protocol_error_c = 1'b1;
            if (early_candidate_c[0] && early_candidate_c[2] &&
                ((raw_wb[0].rob_tag == raw_wb[2].rob_tag) ||
                 (raw_wb[0].phys_rd == raw_wb[2].phys_rd)))
                protocol_error_c = 1'b1;
            if (early_candidate_c[1] && early_candidate_c[2] &&
                ((raw_wb[1].rob_tag == raw_wb[2].rob_tag) ||
                 (raw_wb[1].phys_rd == raw_wb[2].phys_rd)))
                protocol_error_c = 1'b1;

            if (final_consume_mask_i[0] && final_wakeup_mask_i[0] &&
                final_wb0_i.rob_tag.valid &&
                marker_valid_q[final_wb0_i.rob_tag.idx] &&
                !final_marker_match_c[0])
                protocol_error_c = 1'b1;
            if (final_consume_mask_i[1] && final_wakeup_mask_i[1] &&
                final_wb1_i.rob_tag.valid &&
                marker_valid_q[final_wb1_i.rob_tag.idx] &&
                !final_marker_match_c[1])
                protocol_error_c = 1'b1;

            for (source = 0; source < 3; source = source + 1) begin
                if (early_candidate_c[source] &&
                    marker_valid_q[raw_wb[source].rob_tag.idx])
                    protocol_error_c = 1'b1;
            end
        end
    end

    always_comb begin
        marker_count_o = 4'd0;
        for (int marker = 0; marker < `BBUS_OOO_ROB_ENTRIES;
             marker = marker + 1) begin
            marker_count_o = marker_count_o +
                {3'b000, marker_valid_q[marker]};
        end
    end

    always_ff @(posedge clk) begin : update_early_markers
        if (reset || flush_i || !ENABLE) begin
            marker_valid_q <= '0;
            protocol_error_q <= 1'b0;
            for (int marker = 0; marker < `BBUS_OOO_ROB_ENTRIES;
                 marker = marker + 1) begin
                marker_tag_q[marker] <= '0;
                marker_phys_q[marker] <= `BBUS_OOO_PHYS_ZERO;
            end
        end else begin
            protocol_error_q <= protocol_error_q || protocol_error_c;

            if (selective_kill_valid_i) begin
                for (int marker = 0; marker < `BBUS_OOO_ROB_ENTRIES;
                     marker = marker + 1) begin
                    if (marker_valid_q[marker] &&
                        selective_killed_rob_mask_i[marker]) begin
                        marker_valid_q[marker] <= 1'b0;
                        marker_tag_q[marker] <= '0;
                        marker_phys_q[marker] <= `BBUS_OOO_PHYS_ZERO;
                    end
                end
            end else begin
                if (final_terminal_c[0] && final_marker_match_c[0]) begin
                    marker_valid_q[final_wb0_i.rob_tag.idx] <= 1'b0;
                    marker_tag_q[final_wb0_i.rob_tag.idx] <= '0;
                    marker_phys_q[final_wb0_i.rob_tag.idx] <=
                        `BBUS_OOO_PHYS_ZERO;
                end
                if (final_terminal_c[1] && final_marker_match_c[1]) begin
                    marker_valid_q[final_wb1_i.rob_tag.idx] <= 1'b0;
                    marker_tag_q[final_wb1_i.rob_tag.idx] <= '0;
                    marker_phys_q[final_wb1_i.rob_tag.idx] <=
                        `BBUS_OOO_PHYS_ZERO;
                end
                for (int source = 0; source < 3; source = source + 1) begin
                    if (early_source_mask_o[source] &&
                        !early_terminal_source_c[source]) begin
                        marker_valid_q[raw_wb[source].rob_tag.idx] <= 1'b1;
                        marker_tag_q[raw_wb[source].rob_tag.idx] <=
                            raw_wb[source].rob_tag;
                        marker_phys_q[raw_wb[source].rob_tag.idx] <=
                            raw_wb[source].phys_rd;
                    end
                end
            end
        end
    end

    assign conservation_error_o = protocol_error_q || protocol_error_c;
endmodule
