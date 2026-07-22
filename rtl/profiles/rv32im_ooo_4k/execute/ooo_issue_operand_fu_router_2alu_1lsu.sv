`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_issue_operand_fu_router_2alu_1lsu (
    input  logic [1:0] bundle_valid_mask_i,
    input  bbus_ooo_alu_iq_uop_t bundle_uop0_i,
    input  bbus_ooo_alu_iq_uop_t bundle_uop1_i,
    input  logic [31:0] bundle_src10_i,
    input  logic [31:0] bundle_src20_i,
    input  logic [31:0] bundle_src11_i,
    input  logic [31:0] bundle_src21_i,

    input  logic alu0_ready_i,
    input  logic alu1_ready_i,
    input  logic lsu_ready_i,

    output logic [1:0] bundle_ready_mask_o,
    output logic [1:0] bundle_fire_mask_o,

    output logic alu0_valid_o,
    output bbus_ooo_alu_iq_uop_t alu0_uop_o,
    output logic [31:0] alu0_src1_o,
    output logic [31:0] alu0_src2_o,
    output logic alu0_source_lane_o,

    output logic alu1_valid_o,
    output bbus_ooo_alu_iq_uop_t alu1_uop_o,
    output logic [31:0] alu1_src1_o,
    output logic [31:0] alu1_src2_o,
    output logic alu1_source_lane_o,

    output logic lsu_valid_o,
    output bbus_ooo_alu_iq_uop_t lsu_uop_o,
    output logic [31:0] lsu_src1_o,
    output logic [31:0] lsu_src2_o,
    output logic lsu_source_lane_o,

    output logic route_single_alu0_o,
    output logic route_single_alu1_o,
    output logic route_single_lsu_o,
    output logic route_alu_alu_o,
    output logic route_alu_lsu_o,
    output logic route_mixed_alu1_fallback_o,
    output logic illegal_bundle_o,
    output logic serializing_block_o,
    output logic partial_fire_guard_o
);
    logic lane0_alu;
    logic lane1_alu;
    logic lane0_load;
    logic lane1_load;
    logic lane0_serializing;
    logic lane1_serializing;
    logic pair_can_fire;

    function automatic logic ordinary_alu(input bbus_ooo_alu_iq_uop_t uop);
        begin
            ordinary_alu =
                ((uop.fu_type == BBUS_OOO_FU_ALU) ||
                 (uop.fu_type == BBUS_OOO_FU_NONE)) &&
                !uop.is_load && !uop.is_store && !uop.is_csr && !uop.is_system;
        end
    endfunction

    function automatic logic ordinary_load(input bbus_ooo_alu_iq_uop_t uop);
        begin
            ordinary_load =
                (uop.fu_type == BBUS_OOO_FU_LSU) && uop.is_load &&
                !uop.is_store && !uop.is_csr && !uop.is_system;
        end
    endfunction

    function automatic logic serializing(input bbus_ooo_alu_iq_uop_t uop);
        begin
            serializing = uop.is_store || uop.is_csr || uop.is_system ||
                (uop.fu_type == BBUS_OOO_FU_BRU) ||
                (uop.fu_type == BBUS_OOO_FU_CSR) ||
                (uop.fu_type == BBUS_OOO_FU_SYS);
        end
    endfunction

    always_comb begin
        lane0_alu = ordinary_alu(bundle_uop0_i);
        lane1_alu = ordinary_alu(bundle_uop1_i);
        lane0_load = ordinary_load(bundle_uop0_i);
        lane1_load = ordinary_load(bundle_uop1_i);
        lane0_serializing = serializing(bundle_uop0_i);
        lane1_serializing = serializing(bundle_uop1_i);

        bundle_ready_mask_o = 2'b00;
        alu0_valid_o = 1'b0;
        alu1_valid_o = 1'b0;
        lsu_valid_o = 1'b0;
        alu0_uop_o = '0;
        alu1_uop_o = '0;
        lsu_uop_o = '0;
        alu0_src1_o = '0;
        alu0_src2_o = '0;
        alu1_src1_o = '0;
        alu1_src2_o = '0;
        lsu_src1_o = '0;
        lsu_src2_o = '0;
        alu0_source_lane_o = 1'b0;
        alu1_source_lane_o = 1'b0;
        lsu_source_lane_o = 1'b0;
        route_single_alu0_o = 1'b0;
        route_single_alu1_o = 1'b0;
        route_single_lsu_o = 1'b0;
        route_alu_alu_o = 1'b0;
        route_alu_lsu_o = 1'b0;
        route_mixed_alu1_fallback_o = 1'b0;
        illegal_bundle_o = 1'b0;
        serializing_block_o = 1'b0;
        pair_can_fire = 1'b0;

        unique case (bundle_valid_mask_i)
            2'b00: begin
            end

            2'b01: begin
                if (lane0_alu) begin
                    if (alu0_ready_i) begin
                        bundle_ready_mask_o = 2'b01;
                        alu0_valid_o = 1'b1;
                        alu0_uop_o = bundle_uop0_i;
                        alu0_src1_o = bundle_src10_i;
                        alu0_src2_o = bundle_src20_i;
                        route_single_alu0_o = 1'b1;
                    end else if (alu1_ready_i) begin
                        bundle_ready_mask_o = 2'b01;
                        alu1_valid_o = 1'b1;
                        alu1_uop_o = bundle_uop0_i;
                        alu1_src1_o = bundle_src10_i;
                        alu1_src2_o = bundle_src20_i;
                        route_single_alu1_o = 1'b1;
                    end
                end else if (lane0_load) begin
                    lsu_valid_o = 1'b1;
                    lsu_uop_o = bundle_uop0_i;
                    lsu_src1_o = bundle_src10_i;
                    lsu_src2_o = bundle_src20_i;
                    route_single_lsu_o = 1'b1;
                    if (lsu_ready_i) begin
                        bundle_ready_mask_o = 2'b01;
                    end
                end else if (lane0_serializing) begin
                    serializing_block_o = 1'b1;
                end else begin
                    illegal_bundle_o = 1'b1;
                end
            end

            2'b11: begin
                if (lane0_alu && lane1_alu) begin
                    pair_can_fire = alu0_ready_i && alu1_ready_i;
                    if (pair_can_fire) begin
                        bundle_ready_mask_o = 2'b11;
                        alu0_valid_o = 1'b1;
                        alu1_valid_o = 1'b1;
                        alu0_uop_o = bundle_uop0_i;
                        alu1_uop_o = bundle_uop1_i;
                        alu0_src1_o = bundle_src10_i;
                        alu0_src2_o = bundle_src20_i;
                        alu1_src1_o = bundle_src11_i;
                        alu1_src2_o = bundle_src21_i;
                        alu1_source_lane_o = 1'b1;
                        route_alu_alu_o = 1'b1;
                    end
                end else if ((lane0_alu && lane1_load) ||
                             (lane0_load && lane1_alu)) begin
                    lsu_valid_o = 1'b1;
                    lsu_source_lane_o = lane1_load;
                    lsu_uop_o = lane1_load ? bundle_uop1_i : bundle_uop0_i;
                    lsu_src1_o = lane1_load ? bundle_src11_i : bundle_src10_i;
                    lsu_src2_o = lane1_load ? bundle_src21_i : bundle_src20_i;
                    pair_can_fire = lsu_ready_i && (alu0_ready_i || alu1_ready_i);
                    if (pair_can_fire) begin
                        bundle_ready_mask_o = 2'b11;
                        route_alu_lsu_o = 1'b1;
                        if (alu0_ready_i) begin
                            alu0_valid_o = 1'b1;
                            alu0_source_lane_o = lane1_alu;
                            alu0_uop_o = lane1_alu ? bundle_uop1_i : bundle_uop0_i;
                            alu0_src1_o = lane1_alu ? bundle_src11_i : bundle_src10_i;
                            alu0_src2_o = lane1_alu ? bundle_src21_i : bundle_src20_i;
                        end else begin
                            alu1_valid_o = 1'b1;
                            alu1_source_lane_o = lane1_alu;
                            alu1_uop_o = lane1_alu ? bundle_uop1_i : bundle_uop0_i;
                            alu1_src1_o = lane1_alu ? bundle_src11_i : bundle_src10_i;
                            alu1_src2_o = lane1_alu ? bundle_src21_i : bundle_src20_i;
                            route_mixed_alu1_fallback_o = 1'b1;
                        end
                    end
                end else if (lane0_serializing || lane1_serializing) begin
                    serializing_block_o = 1'b1;
                end else begin
                    illegal_bundle_o = 1'b1;
                end
            end

            default: illegal_bundle_o = 1'b1;
        endcase

        bundle_fire_mask_o = bundle_valid_mask_i & bundle_ready_mask_o;
        partial_fire_guard_o =
            ((bundle_valid_mask_i == 2'b11) &&
             ((bundle_fire_mask_o != 2'b00) && (bundle_fire_mask_o != 2'b11))) ||
            ((alu0_valid_o || alu1_valid_o) &&
             (bundle_fire_mask_o == 2'b00));
    end
endmodule
