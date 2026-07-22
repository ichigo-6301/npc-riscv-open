`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

// Standalone Q0 contract for a tagged two-entry load queue.
//
// A memory transaction is identified by {slot, slot_gen, recovery_epoch}; the
// ROB tag is payload, not the response-routing key.  This distinction is what
// makes a late response harmless after queue-slot reuse, ROB-tag reuse, or a
// global recovery.  Both request lanes may fire in one cycle and the single
// tagged response stream may return them in either order.
module ooo_load_queue_2entry #(
    parameter bit RESPONSE_COMPLETION_BYPASS_ENABLE = 1'b0,
    parameter bit REQUEST_FALLTHROUGH_ENABLE = 1'b0
) (
    input  logic clk,
    input  logic reset,
    input  logic flush_i,
    input  logic selective_kill_valid_i,
    input  logic [`BBUS_OOO_ROB_ENTRIES-1:0] selective_killed_rob_mask_i,

    input  logic [1:0] alloc_valid_i,
    output logic [1:0] alloc_ready_o,
    output logic [1:0] alloc_fire_o,
    input  bbus_ooo_rob_tag_t alloc0_rob_tag_i,
    input  bbus_ooo_rob_tag_t alloc1_rob_tag_i,
    input  bbus_ooo_phys_reg_t alloc0_phys_rd_i,
    input  bbus_ooo_phys_reg_t alloc1_phys_rd_i,
    input  logic alloc0_rf_wen_i,
    input  logic alloc1_rf_wen_i,
    input  bbus_ooo_exception_t alloc0_exception_i,
    input  bbus_ooo_exception_t alloc1_exception_i,
    input  logic alloc0_result_valid_i,
    input  logic alloc1_result_valid_i,
    input  logic [31:0] alloc0_result_i,
    input  logic [31:0] alloc1_result_i,
    input  logic [31:0] alloc0_addr_i,
    input  logic [31:0] alloc1_addr_i,
    input  logic [2:0] alloc0_len_i,
    input  logic [2:0] alloc1_len_i,
    input  bbus_ooo_mem_op_e alloc0_mem_op_i,
    input  bbus_ooo_mem_op_e alloc1_mem_op_i,

    output logic [1:0] req_valid_o,
    input  logic [1:0] req_ready_i,
    output logic [1:0] req_fire_o,
    output bbus_ooo_rob_tag_t req0_rob_tag_o,
    output bbus_ooo_rob_tag_t req1_rob_tag_o,
    output logic [31:0] req0_addr_o,
    output logic [31:0] req1_addr_o,
    output logic [2:0] req0_len_o,
    output logic [2:0] req1_len_o,
    output bbus_ooo_mem_op_e req0_mem_op_o,
    output bbus_ooo_mem_op_e req1_mem_op_o,
    output logic req0_token_slot_o,
    output logic req1_token_slot_o,
    output logic [31:0] req0_token_gen_o,
    output logic [31:0] req1_token_gen_o,
    output logic [31:0] req0_token_epoch_o,
    output logic [31:0] req1_token_epoch_o,

    input  logic rsp_valid_i,
    output logic rsp_ready_o,
    input  logic rsp_token_slot_i,
    input  logic [31:0] rsp_token_gen_i,
    input  logic [31:0] rsp_token_epoch_i,
    input  logic [31:0] rsp_rdata_i,
    input  logic rsp_error_i,
    input  logic rsp_page_fault_i,

    output logic completion_valid_o,
    input  logic completion_ready_i,
    output bbus_ooo_writeback_t completion_wb_o,

    output logic [1:0] valid_mask_o,
    output logic [1:0] issued_mask_o,
    output logic [1:0] done_mask_o,
    output logic [31:0] recovery_epoch_o,
    output logic unknown_response_drop_o,
    output logic stale_response_drop_o,
    output logic duplicate_response_drop_o,
    output logic conservation_error_o
);
    typedef struct packed {
        logic valid;
        logic issued;
        logic done;
        bbus_ooo_exception_t exception;
        logic [31:0] token_gen;
        logic [31:0] token_epoch;
        bbus_ooo_rob_tag_t rob_tag;
        bbus_ooo_phys_reg_t phys_rd;
        logic rf_wen;
        logic [31:0] addr;
        logic [2:0] len;
        bbus_ooo_mem_op_e mem_op;
        logic [31:0] result;
    } entry_t;

    entry_t entry_q [1:0];
    logic [31:0] slot_gen_q [1:0];
    logic [31:0] epoch_q;
    logic stale_valid_q [1:0];
    logic [31:0] stale_gen_q [1:0];
    logic [31:0] stale_epoch_q [1:0];

    logic [1:0] kill_now_c;
    logic [1:0] free_mask_c;
    logic [1:0] alloc_slot0_c, alloc_slot1_c;
    logic alloc_slot1_valid_c;
    logic [1:0] completion_pick_c;
    logic rsp_exact_c, rsp_active_c, rsp_done_c, rsp_unissued_c, stale_token_c;
    logic rsp_fire_c, completion_fire_c;
    logic [1:0] valid_count_c, kill_count_c, alloc_count_c;
    logic [31:0] allocation_total_q, terminal_total_q;
    logic completion_hold_q;
    logic completion_hold_slot_q;
    logic completion_from_response_c;
    logic completion_selected_slot_c;
    logic response_completion_fire_c;
    logic fallthrough_alloc0_c;

    function automatic logic tag_equal(
        input bbus_ooo_rob_tag_t a,
        input bbus_ooo_rob_tag_t b
    );
        tag_equal = a.valid && b.valid && (a.idx == b.idx) && (a.gen == b.gen);
    endfunction

    always_comb begin
        integer i;
        integer free_count;
        free_count = 0;
        free_mask_c = '0;
        kill_now_c = '0;
        valid_mask_o = '0;
        issued_mask_o = '0;
        done_mask_o = '0;
        for (i = 0; i < 2; i = i + 1) begin
            valid_mask_o[i] = entry_q[i].valid;
            issued_mask_o[i] = entry_q[i].valid && entry_q[i].issued;
            done_mask_o[i] = entry_q[i].valid && entry_q[i].done;
            if (!entry_q[i].valid) begin
                free_mask_c[i] = 1'b1;
                free_count = free_count + 1;
            end
            kill_now_c[i] = entry_q[i].valid &&
                (flush_i || (selective_kill_valid_i && entry_q[i].rob_tag.valid &&
                             selective_killed_rob_mask_i[entry_q[i].rob_tag.idx]));
        end
        valid_count_c = {1'b0, valid_mask_o[0]} + {1'b0, valid_mask_o[1]};
        kill_count_c = {1'b0, kill_now_c[0]} + {1'b0, kill_now_c[1]};

        alloc_ready_o = '0;
        if (!reset && !flush_i && !selective_kill_valid_i && free_count != 0) begin
            alloc_ready_o[0] = 1'b1;
            alloc_ready_o[1] = alloc_valid_i[0] && (free_count >= 2);
        end
        alloc_fire_o = alloc_valid_i & alloc_ready_o;
        alloc_count_c = {1'b0, alloc_fire_o[0]} + {1'b0, alloc_fire_o[1]};

        alloc_slot0_c = free_mask_c[0] ? 2'b01 :
                        free_mask_c[1] ? 2'b10 : 2'b00;
        alloc_slot1_c = (free_mask_c == 2'b11) ? 2'b10 : 2'b00;
        alloc_slot1_valid_c = (free_mask_c == 2'b11);

        // An empty queue has no registered request owner to preserve.  The
        // allocation token is already determined combinationally, so it may
        // be offered to memory on the allocation cycle without making
        // allocation readiness depend on memory readiness.  If memory stalls,
        // the entry is simply retained as an ordinary unissued queue entry.
        fallthrough_alloc0_c = REQUEST_FALLTHROUGH_ENABLE &&
            (valid_count_c == 0) && alloc_fire_o[0] &&
            !alloc0_exception_i.valid && !alloc0_result_valid_i;

        req_valid_o[0] = (entry_q[0].valid && !entry_q[0].issued &&
            !entry_q[0].done && !kill_now_c[0]) || fallthrough_alloc0_c;
        req_valid_o[1] = entry_q[1].valid && !entry_q[1].issued &&
            !entry_q[1].done && !kill_now_c[1];
        req_fire_o = req_valid_o & req_ready_i;
        req0_rob_tag_o = fallthrough_alloc0_c ?
            alloc0_rob_tag_i : entry_q[0].rob_tag;
        req1_rob_tag_o = entry_q[1].rob_tag;
        req0_addr_o = fallthrough_alloc0_c ? alloc0_addr_i : entry_q[0].addr;
        req1_addr_o = entry_q[1].addr;
        req0_len_o = fallthrough_alloc0_c ? alloc0_len_i : entry_q[0].len;
        req1_len_o = entry_q[1].len;
        req0_mem_op_o = fallthrough_alloc0_c ?
            alloc0_mem_op_i : entry_q[0].mem_op;
        req1_mem_op_o = entry_q[1].mem_op;
        req0_token_slot_o = 1'b0;
        req1_token_slot_o = 1'b1;
        req0_token_gen_o = fallthrough_alloc0_c ?
            (slot_gen_q[0] + 32'd1) : entry_q[0].token_gen;
        req1_token_gen_o = entry_q[1].token_gen;
        req0_token_epoch_o = fallthrough_alloc0_c ?
            epoch_q : entry_q[0].token_epoch;
        req1_token_epoch_o = entry_q[1].token_epoch;

        rsp_ready_o = !reset;
        rsp_fire_c = rsp_valid_i && rsp_ready_o;
        rsp_exact_c = entry_q[rsp_token_slot_i].valid &&
            (entry_q[rsp_token_slot_i].token_gen == rsp_token_gen_i) &&
            (entry_q[rsp_token_slot_i].token_epoch == rsp_token_epoch_i);
        rsp_active_c = rsp_exact_c &&
            (entry_q[rsp_token_slot_i].issued || req_fire_o[rsp_token_slot_i]) &&
            !entry_q[rsp_token_slot_i].done && !kill_now_c[rsp_token_slot_i];
        rsp_done_c = rsp_exact_c && entry_q[rsp_token_slot_i].done;
        rsp_unissued_c = rsp_exact_c && !entry_q[rsp_token_slot_i].issued &&
            !req_fire_o[rsp_token_slot_i];
        stale_token_c = stale_valid_q[rsp_token_slot_i] &&
            (stale_gen_q[rsp_token_slot_i] == rsp_token_gen_i) &&
            (stale_epoch_q[rsp_token_slot_i] == rsp_token_epoch_i);

        completion_pick_c = '0;
        if (!flush_i && !selective_kill_valid_i) begin
            if (completion_hold_q && entry_q[completion_hold_slot_q].valid &&
                entry_q[completion_hold_slot_q].done &&
                !kill_now_c[completion_hold_slot_q])
                completion_pick_c[completion_hold_slot_q] = 1'b1;
            else if (entry_q[0].valid && entry_q[0].done && !kill_now_c[0])
                completion_pick_c = 2'b01;
            else if (entry_q[1].valid && entry_q[1].done && !kill_now_c[1])
                completion_pick_c = 2'b10;
        end
        completion_from_response_c = RESPONSE_COMPLETION_BYPASS_ENABLE &&
            rsp_fire_c && rsp_active_c && !(|completion_pick_c);
        completion_valid_o = (|completion_pick_c) ||
            completion_from_response_c;
        completion_selected_slot_c = completion_from_response_c ?
            rsp_token_slot_i : completion_pick_c[1];
        completion_wb_o = '0;
        if (completion_valid_o) begin
            completion_wb_o.valid = 1'b1;
            completion_wb_o.rob_tag = entry_q[completion_selected_slot_c].rob_tag;
            completion_wb_o.phys_rd = entry_q[completion_selected_slot_c].phys_rd;
            completion_wb_o.rf_wen = entry_q[completion_selected_slot_c].rf_wen;
            completion_wb_o.result = completion_from_response_c ?
                rsp_rdata_i : entry_q[completion_selected_slot_c].result;
            completion_wb_o.done = 1'b1;
            completion_wb_o.is_load = 1'b1;
            completion_wb_o.mem_op = entry_q[completion_selected_slot_c].mem_op;
            completion_wb_o.mem_addr = entry_q[completion_selected_slot_c].addr;
            completion_wb_o.mem_len = entry_q[completion_selected_slot_c].len;
            if (completion_from_response_c) begin
                completion_wb_o.exception.valid = rsp_error_i ||
                    rsp_page_fault_i;
                completion_wb_o.exception.cause = rsp_page_fault_i ? 32'd13 :
                    (rsp_error_i ? 32'd5 : 32'd0);
                completion_wb_o.exception.tval =
                    entry_q[completion_selected_slot_c].addr;
            end else begin
                completion_wb_o.exception =
                    entry_q[completion_selected_slot_c].exception;
            end
            completion_wb_o.rf_wen = completion_wb_o.rf_wen &&
                !completion_wb_o.exception.valid;
        end
        recovery_epoch_o = epoch_q;
    end

    // Keep completion readiness out of the packet-selection combinational
    // cone.  Besides avoiding a ready/metadata loop for integrating clients,
    // this makes the held completion packet visibly independent of backpressure.
    assign completion_fire_c = completion_valid_o && completion_ready_i;
    assign response_completion_fire_c = completion_from_response_c &&
        completion_fire_c;

    always_ff @(posedge clk) begin
        integer i;
        if (reset) begin
            for (i = 0; i < 2; i = i + 1) begin
                entry_q[i] <= '0;
                slot_gen_q[i] <= '0;
                stale_valid_q[i] <= 1'b0;
                stale_gen_q[i] <= '0;
                stale_epoch_q[i] <= '0;
            end
            epoch_q <= '0;
            unknown_response_drop_o <= 1'b0;
            stale_response_drop_o <= 1'b0;
            duplicate_response_drop_o <= 1'b0;
            conservation_error_o <= 1'b0;
            allocation_total_q <= '0;
            terminal_total_q <= '0;
            completion_hold_q <= 1'b0;
            completion_hold_slot_q <= 1'b0;
        end else begin
            unknown_response_drop_o <= 1'b0;
            stale_response_drop_o <= 1'b0;
            duplicate_response_drop_o <= 1'b0;

            if (flush_i || (selective_kill_valid_i && completion_hold_q &&
                kill_now_c[completion_hold_slot_q])) begin
                completion_hold_q <= 1'b0;
            end else if (completion_fire_c) begin
                completion_hold_q <= 1'b0;
            end else if (completion_valid_o && !completion_ready_i) begin
                completion_hold_q <= 1'b1;
                completion_hold_slot_q <= completion_selected_slot_c;
            end

            if (flush_i) epoch_q <= epoch_q + 32'd1;
            allocation_total_q <= allocation_total_q + alloc_count_c;
            terminal_total_q <= terminal_total_q + kill_count_c +
                (completion_fire_c ? 32'd1 : 32'd0);

            if (allocation_total_q != (terminal_total_q + valid_count_c))
                conservation_error_o <= 1'b1;

            if (rsp_fire_c) begin
                if (rsp_active_c) begin
                    // Matching data is recorded below.
                end else if (rsp_done_c) begin
                    duplicate_response_drop_o <= 1'b1;
                end else if (stale_token_c || kill_now_c[rsp_token_slot_i]) begin
                    stale_response_drop_o <= 1'b1;
                end else if (rsp_unissued_c ||
                             ((!entry_q[rsp_token_slot_i].valid) &&
                              (rsp_token_epoch_i == epoch_q) &&
                              (rsp_token_gen_i == slot_gen_q[rsp_token_slot_i]))) begin
                    unknown_response_drop_o <= 1'b1;
                end else begin
                    stale_response_drop_o <= 1'b1;
                end
            end

            for (i = 0; i < 2; i = i + 1) begin
                if (entry_q[i].valid && kill_now_c[i]) begin
                    stale_valid_q[i] <= 1'b1;
                    stale_gen_q[i] <= entry_q[i].token_gen;
                    stale_epoch_q[i] <= entry_q[i].token_epoch;
                    entry_q[i] <= '0;
                end else if (entry_q[i].valid && completion_fire_c &&
                             (completion_pick_c[i] ||
                              (response_completion_fire_c &&
                               (rsp_token_slot_i == i[0])))) begin
                    stale_valid_q[i] <= 1'b1;
                    stale_gen_q[i] <= entry_q[i].token_gen;
                    stale_epoch_q[i] <= entry_q[i].token_epoch;
                    entry_q[i] <= '0;
                end else begin
                    if (req_fire_o[i]) entry_q[i].issued <= 1'b1;
                    if (rsp_fire_c && rsp_active_c && (rsp_token_slot_i == i[0])) begin
                        entry_q[i].done <= 1'b1;
                        entry_q[i].exception.valid <= rsp_error_i || rsp_page_fault_i;
                        entry_q[i].exception.cause <= rsp_page_fault_i ? 32'd13 : 32'd5;
                        entry_q[i].exception.tval <= entry_q[i].addr;
                        entry_q[i].result <= rsp_rdata_i;
                    end
                end
            end

            if (!flush_i && !selective_kill_valid_i) begin
                if (alloc_fire_o[0]) begin
                    if (alloc_slot0_c[0]) begin
                        slot_gen_q[0] <= slot_gen_q[0] + 32'd1;
                        entry_q[0] <= '{valid:1'b1,
                            issued:alloc0_exception_i.valid ||
                                alloc0_result_valid_i ||
                                (fallthrough_alloc0_c && req_fire_o[0]),
                            done:alloc0_exception_i.valid || alloc0_result_valid_i,
                            exception:alloc0_exception_i,
                            token_gen:slot_gen_q[0] + 32'd1, token_epoch:epoch_q,
                            rob_tag:alloc0_rob_tag_i, phys_rd:alloc0_phys_rd_i,
                            rf_wen:alloc0_rf_wen_i, addr:alloc0_addr_i,
                            len:alloc0_len_i, mem_op:alloc0_mem_op_i,
                            result:alloc0_result_valid_i ? alloc0_result_i : '0};
                    end else begin
                        slot_gen_q[1] <= slot_gen_q[1] + 32'd1;
                        entry_q[1] <= '{valid:1'b1,
                            issued:alloc0_exception_i.valid || alloc0_result_valid_i,
                            done:alloc0_exception_i.valid || alloc0_result_valid_i,
                            exception:alloc0_exception_i,
                            token_gen:slot_gen_q[1] + 32'd1, token_epoch:epoch_q,
                            rob_tag:alloc0_rob_tag_i, phys_rd:alloc0_phys_rd_i,
                            rf_wen:alloc0_rf_wen_i, addr:alloc0_addr_i,
                            len:alloc0_len_i, mem_op:alloc0_mem_op_i,
                            result:alloc0_result_valid_i ? alloc0_result_i : '0};
                    end
                end
                if (alloc_fire_o[1] && alloc_slot1_valid_c) begin
                    slot_gen_q[1] <= slot_gen_q[1] + 32'd1;
                    entry_q[1] <= '{valid:1'b1,
                        issued:alloc1_exception_i.valid || alloc1_result_valid_i,
                        done:alloc1_exception_i.valid || alloc1_result_valid_i,
                        exception:alloc1_exception_i,
                        token_gen:slot_gen_q[1] + 32'd1, token_epoch:epoch_q,
                        rob_tag:alloc1_rob_tag_i, phys_rd:alloc1_phys_rd_i,
                        rf_wen:alloc1_rf_wen_i, addr:alloc1_addr_i,
                        len:alloc1_len_i, mem_op:alloc1_mem_op_i,
                        result:alloc1_result_valid_i ? alloc1_result_i : '0};
                end
            end

            if ((alloc_fire_o[0] && !alloc0_rob_tag_i.valid) ||
                (alloc_fire_o[1] && !alloc1_rob_tag_i.valid) ||
                (alloc_fire_o == 2'b11 && tag_equal(alloc0_rob_tag_i, alloc1_rob_tag_i))) begin
                conservation_error_o <= 1'b1;
            end
        end
    end
endmodule
