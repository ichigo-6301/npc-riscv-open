`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_atomic_pipeline_1w (
    input  logic clk,
    input  logic reset,
    input  logic flush_i,

    input  logic issue_valid_i,
    input  bbus_ooo_alu_iq_uop_t issue_uop_i,
    input  logic [31:0] address_i,
    input  logic [31:0] operand_i,
    output logic issue_ready_o,
    output logic issue_accept_o,

    output logic mem_req_valid_o,
    input  logic mem_req_ready_i,
    output logic mem_req_write_o,
    output logic [31:0] mem_req_addr_o,
    output logic [31:0] mem_req_wdata_o,
    output logic [3:0] mem_req_wstrb_o,
    output logic [2:0] mem_req_len_o,
    output logic [1:0] mem_req_access_o,
    output bbus_ooo_mem_token_t mem_req_token_o,
    input  logic mem_rsp_valid_i,
    output logic mem_rsp_ready_o,
    input  logic [31:0] mem_rsp_rdata_i,
    input  logic mem_rsp_error_i,
    input  logic mem_rsp_page_fault_i,
    input  bbus_ooo_mem_token_t mem_rsp_token_i,

    output logic completion_valid_o,
    input  logic completion_ready_i,
    output bbus_ooo_writeback_t completion_wb_o,

    input  logic commit_valid_i,
    input  bbus_ooo_rob_tag_t commit_rob_tag_i,
    input  logic reservation_invalidate_i,

    output logic occupied_o,
    output logic memory_lock_o,
    output logic write_request_fire_o,
    output logic recovery_block_o,
    output logic killed_read_drain_o,
    output logic illegal_issue_o,
    output logic flush_drop_o,
    output logic reservation_valid_o,
    output logic [31:0] reservation_addr_o,
    output logic sc_success_o,
    output logic sc_failure_o,
    output logic irreversible_flush_error_o,
    output logic conservation_error_o
);
    typedef enum logic [3:0] {
        AMO_IDLE,
        AMO_READ_REQ,
        AMO_READ_WAIT,
        AMO_WRITE_REQ,
        AMO_WRITE_WAIT,
        AMO_COMPLETION,
        AMO_COMMIT_WAIT,
        AMO_DROP_READ_WAIT,
        AMO_DROP_WRITE_WAIT
    } amo_state_e;

    amo_state_e state_q;
    bbus_ooo_alu_iq_uop_t uop_q;
    logic [31:0] addr_q;
    logic [31:0] operand_q;
    logic [31:0] old_value_q;
    logic [31:0] new_value_q;
    bbus_ooo_writeback_t completion_q;
    logic irreversible_q;
    logic reservation_valid_q;
    logic [31:0] reservation_addr_q;
    logic lr_completed_ok_q;
    logic issue_legal_c;
    logic issue_misaligned_c;
    logic issue_lr_c;
    logic issue_sc_c;
    logic sc_reservation_match_c;
    logic req_fire_c;
    logic rsp_fire_c;
    logic completion_fire_c;
    logic commit_match_c;
    logic [31:0] mem_generation_q;
    bbus_ooo_mem_token_t pending_mem_token_q;
    logic rsp_token_match_c;

    function automatic logic amo_v1_supported(input bbus_ooo_atomic_op_e op);
        begin
            amo_v1_supported =
                (op == BBUS_OOO_AMO_LR) ||
                (op == BBUS_OOO_AMO_SC) ||
                (op == BBUS_OOO_AMO_SWAP) ||
                (op == BBUS_OOO_AMO_ADD) ||
                (op == BBUS_OOO_AMO_XOR) ||
                (op == BBUS_OOO_AMO_AND) ||
                (op == BBUS_OOO_AMO_OR) ||
                (op == BBUS_OOO_AMO_MIN) ||
                (op == BBUS_OOO_AMO_MAX) ||
                (op == BBUS_OOO_AMO_MINU) ||
                (op == BBUS_OOO_AMO_MAXU);
        end
    endfunction

    function automatic logic [31:0] amo_result(
        input bbus_ooo_atomic_op_e op,
        input logic [31:0] old_value,
        input logic [31:0] operand
    );
        begin
            unique case (op)
                BBUS_OOO_AMO_SWAP: amo_result = operand;
                BBUS_OOO_AMO_ADD:  amo_result = old_value + operand;
                BBUS_OOO_AMO_XOR:  amo_result = old_value ^ operand;
                BBUS_OOO_AMO_AND:  amo_result = old_value & operand;
                BBUS_OOO_AMO_OR:   amo_result = old_value | operand;
                BBUS_OOO_AMO_MIN:  amo_result =
                    ($signed(old_value) < $signed(operand)) ? old_value : operand;
                BBUS_OOO_AMO_MAX:  amo_result =
                    ($signed(old_value) > $signed(operand)) ? old_value : operand;
                BBUS_OOO_AMO_MINU: amo_result =
                    (old_value < operand) ? old_value : operand;
                BBUS_OOO_AMO_MAXU: amo_result =
                    (old_value > operand) ? old_value : operand;
                default:           amo_result = old_value;
            endcase
        end
    endfunction

    assign issue_legal_c =
        issue_uop_i.valid &&
        (issue_uop_i.fu_type == BBUS_OOO_FU_AMO) &&
        amo_v1_supported(issue_uop_i.atomic_op) &&
        !issue_uop_i.exception.valid;
    assign issue_misaligned_c = (address_i[1:0] != 2'b00);
    assign issue_lr_c = issue_uop_i.atomic_op == BBUS_OOO_AMO_LR;
    assign issue_sc_c = issue_uop_i.atomic_op == BBUS_OOO_AMO_SC;
    assign sc_reservation_match_c = reservation_valid_q &&
        (reservation_addr_q == {address_i[31:2], 2'b00});
    assign issue_ready_o = !reset && !flush_i && (state_q == AMO_IDLE);
    assign issue_accept_o = issue_valid_i && issue_ready_o && issue_legal_c;
    assign illegal_issue_o = issue_valid_i && issue_ready_o && !issue_legal_c;

    assign mem_req_valid_o =
        (state_q == AMO_READ_REQ) || (state_q == AMO_WRITE_REQ);
    assign mem_req_write_o = (state_q == AMO_WRITE_REQ);
    assign mem_req_addr_o = addr_q;
    assign mem_req_wdata_o = new_value_q;
    assign mem_req_wstrb_o = (state_q == AMO_WRITE_REQ) ? 4'b1111 : 4'b0000;
    assign mem_req_len_o = 3'd4;
    assign mem_req_access_o =
        (uop_q.atomic_op == BBUS_OOO_AMO_LR) ? 2'd1 : 2'd2;
    always_comb begin
        mem_req_token_o = '0;
        mem_req_token_o.valid = mem_req_valid_o;
        mem_req_token_o.client = BBUS_OOO_MEM_CLIENT_AMO;
        mem_req_token_o.slot = {1'b0, state_q == AMO_WRITE_REQ};
        mem_req_token_o.generation = mem_generation_q;
        mem_req_token_o.recovery_epoch = 32'b0;
    end
    assign req_fire_c = mem_req_valid_o && mem_req_ready_i;
    assign write_request_fire_o =
        (state_q == AMO_WRITE_REQ) && mem_req_ready_i;

    assign mem_rsp_ready_o =
        (state_q == AMO_READ_WAIT) ||
        (state_q == AMO_WRITE_WAIT) ||
        (state_q == AMO_DROP_READ_WAIT) ||
        (state_q == AMO_DROP_WRITE_WAIT);
    assign rsp_token_match_c = mem_rsp_token_i.valid &&
        (mem_rsp_token_i == pending_mem_token_q);
    assign rsp_fire_c = mem_rsp_valid_i && mem_rsp_ready_o && rsp_token_match_c;

    assign completion_valid_o = !flush_i && (state_q == AMO_COMPLETION);
    assign completion_wb_o = completion_q;
    assign completion_fire_c = completion_valid_o && completion_ready_i;
    assign commit_match_c =
        commit_valid_i && uop_q.rob_tag.valid &&
        (commit_rob_tag_i == uop_q.rob_tag);

    assign occupied_o = (state_q != AMO_IDLE);
    assign memory_lock_o = occupied_o;
    assign recovery_block_o = irreversible_q || write_request_fire_o;
    assign killed_read_drain_o = (state_q == AMO_DROP_READ_WAIT);
    assign flush_drop_o = flush_i && occupied_o;
    assign reservation_valid_o = reservation_valid_q;
    assign reservation_addr_o = reservation_addr_q;

    always_ff @(posedge clk) begin
        if (reset) begin
            state_q <= AMO_IDLE;
            uop_q <= '0;
            addr_q <= 32'b0;
            operand_q <= 32'b0;
            old_value_q <= 32'b0;
            new_value_q <= 32'b0;
            completion_q <= '0;
            irreversible_q <= 1'b0;
            reservation_valid_q <= 1'b0;
            reservation_addr_q <= 32'b0;
            lr_completed_ok_q <= 1'b0;
            sc_success_o <= 1'b0;
            sc_failure_o <= 1'b0;
            irreversible_flush_error_o <= 1'b0;
            conservation_error_o <= 1'b0;
            mem_generation_q <= 32'b0;
            pending_mem_token_q <= '0;
        end else begin
            sc_success_o <= 1'b0;
            sc_failure_o <= 1'b0;
            if (flush_i || reservation_invalidate_i) begin
                reservation_valid_q <= 1'b0;
            end
            if (req_fire_c) begin
                pending_mem_token_q <= mem_req_token_o;
                mem_generation_q <= mem_generation_q + 32'd1;
            end
            if (rsp_fire_c) pending_mem_token_q <= '0;
            if (mem_rsp_valid_i && mem_rsp_ready_o && !rsp_token_match_c)
                conservation_error_o <= 1'b1;
            unique case (state_q)
                AMO_IDLE: begin
                    completion_q <= '0;
                    irreversible_q <= 1'b0;
                    lr_completed_ok_q <= 1'b0;
                    if (issue_accept_o) begin
                        uop_q <= issue_uop_i;
                        addr_q <= address_i;
                        operand_q <= operand_i;
                        old_value_q <= 32'b0;
                        new_value_q <= 32'b0;
                        completion_q <= '0;
                        completion_q.valid <= 1'b1;
                        completion_q.rob_tag <= issue_uop_i.rob_tag;
                        completion_q.phys_rd <= issue_uop_i.phys_rd_new;
                        completion_q.rf_wen <= issue_uop_i.rf_wen;
                        completion_q.done <= 1'b1;
                        completion_q.mem_addr <= address_i;
                        completion_q.mem_wstrb <= issue_lr_c ? 4'b0000 : 4'b1111;
                        completion_q.mem_len <= 3'd4;
                        if (!issue_lr_c) begin
                            reservation_valid_q <= 1'b0;
                        end
                        if (issue_sc_c) begin
                            sc_success_o <= !issue_misaligned_c &&
                                sc_reservation_match_c;
                            sc_failure_o <= issue_misaligned_c ||
                                !sc_reservation_match_c;
                        end
                        if (issue_misaligned_c) begin
                            completion_q.rf_wen <= 1'b0;
                            completion_q.exception.valid <= 1'b1;
                            completion_q.exception.cause <=
                                issue_lr_c ? 32'd4 : 32'd6;
                            completion_q.exception.tval <= address_i;
                            state_q <= AMO_COMPLETION;
                        end else if (issue_sc_c) begin
                            completion_q.result <= sc_reservation_match_c ?
                                32'd0 : 32'd1;
                            new_value_q <= operand_i;
                            completion_q.mem_wdata <= operand_i;
                            state_q <= sc_reservation_match_c ?
                                AMO_WRITE_REQ : AMO_COMPLETION;
                        end else begin
                            state_q <= AMO_READ_REQ;
                        end
                    end
                end

                AMO_READ_REQ: begin
                    if (flush_i) begin
                        completion_q <= '0;
                        state_q <= req_fire_c ? AMO_DROP_READ_WAIT : AMO_IDLE;
                    end else if (req_fire_c) begin
                        state_q <= AMO_READ_WAIT;
                    end
                end

                AMO_READ_WAIT: begin
                    if (flush_i) begin
                        completion_q <= '0;
                        state_q <= rsp_fire_c ? AMO_IDLE : AMO_DROP_READ_WAIT;
                    end else if (rsp_fire_c) begin
                        if (mem_rsp_page_fault_i === 1'b1) begin
                            completion_q.rf_wen <= 1'b0;
                            completion_q.exception.valid <= 1'b1;
                            completion_q.exception.cause <=
                                (uop_q.atomic_op == BBUS_OOO_AMO_LR) ?
                                32'd13 : 32'd15;
                            completion_q.exception.tval <= addr_q;
                            state_q <= AMO_COMPLETION;
                        end else if (mem_rsp_error_i) begin
                            completion_q.rf_wen <= 1'b0;
                            completion_q.exception.valid <= 1'b1;
                            completion_q.exception.cause <=
                                (uop_q.atomic_op == BBUS_OOO_AMO_LR) ?
                                32'd5 : 32'd7;
                            completion_q.exception.tval <= addr_q;
                            state_q <= AMO_COMPLETION;
                        end else if (uop_q.atomic_op == BBUS_OOO_AMO_LR) begin
                            old_value_q <= mem_rsp_rdata_i;
                            completion_q.result <= mem_rsp_rdata_i;
                            lr_completed_ok_q <= 1'b1;
                            state_q <= AMO_COMPLETION;
                        end else begin
                            old_value_q <= mem_rsp_rdata_i;
                            new_value_q <= amo_result(
                                uop_q.atomic_op, mem_rsp_rdata_i, operand_q);
                            completion_q.result <= mem_rsp_rdata_i;
                            completion_q.mem_wdata <= amo_result(
                                uop_q.atomic_op, mem_rsp_rdata_i, operand_q);
                            state_q <= AMO_WRITE_REQ;
                        end
                    end
                end

                AMO_WRITE_REQ: begin
                    if (flush_i) begin
                        completion_q <= '0;
                        if (req_fire_c) begin
                            irreversible_q <= 1'b1;
                            irreversible_flush_error_o <= 1'b1;
                            state_q <= AMO_DROP_WRITE_WAIT;
                        end else begin
                            state_q <= AMO_IDLE;
                        end
                    end else if (req_fire_c) begin
                        irreversible_q <= 1'b1;
                        state_q <= AMO_WRITE_WAIT;
                    end
                end

                AMO_WRITE_WAIT: begin
                    if (flush_i) begin
                        completion_q <= '0;
                        irreversible_flush_error_o <= 1'b1;
                        state_q <= rsp_fire_c ? AMO_IDLE : AMO_DROP_WRITE_WAIT;
                    end else if (rsp_fire_c) begin
                        if (mem_rsp_page_fault_i === 1'b1) begin
                            completion_q.rf_wen <= 1'b0;
                            completion_q.exception.valid <= 1'b1;
                            completion_q.exception.cause <= 32'd15;
                            completion_q.exception.tval <= addr_q;
                        end else if (mem_rsp_error_i) begin
                            completion_q.rf_wen <= 1'b0;
                            completion_q.exception.valid <= 1'b1;
                            completion_q.exception.cause <= 32'd7;
                            completion_q.exception.tval <= addr_q;
                        end
                        state_q <= AMO_COMPLETION;
                    end
                end

                AMO_COMPLETION: begin
                    if (flush_i) begin
                        if (irreversible_q) begin
                            irreversible_flush_error_o <= 1'b1;
                        end
                        completion_q <= '0;
                        state_q <= AMO_IDLE;
                    end else if (completion_fire_c) begin
                        completion_q <= '0;
                        state_q <= AMO_COMMIT_WAIT;
                    end
                end

                AMO_COMMIT_WAIT: begin
                    if (flush_i) begin
                        if (irreversible_q) begin
                            irreversible_flush_error_o <= 1'b1;
                        end
                        state_q <= AMO_IDLE;
                        irreversible_q <= 1'b0;
                        uop_q <= '0;
                    end else if (commit_match_c) begin
                        if ((uop_q.atomic_op == BBUS_OOO_AMO_LR) &&
                            lr_completed_ok_q && !reservation_invalidate_i) begin
                            reservation_valid_q <= 1'b1;
                            reservation_addr_q <= {addr_q[31:2], 2'b00};
                        end
                        state_q <= AMO_IDLE;
                        irreversible_q <= 1'b0;
                        lr_completed_ok_q <= 1'b0;
                        uop_q <= '0;
                    end
                end

                AMO_DROP_READ_WAIT: begin
                    if (rsp_fire_c) begin
                        state_q <= AMO_IDLE;
                        lr_completed_ok_q <= 1'b0;
                        uop_q <= '0;
                    end
                end

                AMO_DROP_WRITE_WAIT: begin
                    if (rsp_fire_c) begin
                        state_q <= AMO_IDLE;
                        irreversible_q <= 1'b0;
                        uop_q <= '0;
                    end
                end

                default: begin
                    state_q <= AMO_IDLE;
                    conservation_error_o <= 1'b1;
                end
            endcase
        end
    end

    /* verilator lint_off UNUSED */
    wire ordering_bits_used = uop_q.aq ^ uop_q.rl;
    wire old_value_used = ^old_value_q;
    /* verilator lint_on UNUSED */
endmodule
