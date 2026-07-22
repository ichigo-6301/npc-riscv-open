`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_dual_wb_bundle_2w (
    input  logic clk,
    input  logic reset,

    input  bbus_ooo_writeback_t wb0_i,
    input  bbus_ooo_writeback_t wb1_i,

    input  logic wb0_rob_match_i,
    input  logic wb1_rob_match_i,
    input  logic wb0_killed_i,
    input  logic wb1_killed_i,

    output logic [1:0] wb_accept_mask_o,
    output bbus_ooo_writeback_t wb0_o,
    output bbus_ooo_writeback_t wb1_o,

    output logic [1:0] ordinary_wakeup_valid_o,
    output bbus_ooo_phys_reg_t wakeup_phys0_o,
    output bbus_ooo_phys_reg_t wakeup_phys1_o,

    output logic dual_wb_fire_o,
    output logic dual_wakeup_fire_o,
    output logic duplicate_phys_bug_o,
    output logic duplicate_rob_tag_bug_o,
    output logic stale_drop0_o,
    output logic stale_drop1_o,
    output logic killed_drop0_o,
    output logic killed_drop1_o,
    output logic exception_no_wakeup0_o,
    output logic exception_no_wakeup1_o,
    output logic p0_wakeup_suppressed0_o,
    output logic p0_wakeup_suppressed1_o
);
    logic accepted0_c;
    logic accepted1_c;
    logic ordinary_wakeup0_c;
    logic ordinary_wakeup1_c;

    assign accepted0_c = wb0_i.valid && wb0_rob_match_i && !wb0_killed_i;
    assign accepted1_c = wb1_i.valid && wb1_rob_match_i && !wb1_killed_i;

    assign ordinary_wakeup0_c =
        accepted0_c &&
        wb0_i.rf_wen &&
        (wb0_i.phys_rd != `BBUS_OOO_PHYS_ZERO) &&
        !wb0_i.exception.valid;
    assign ordinary_wakeup1_c =
        accepted1_c &&
        wb1_i.rf_wen &&
        (wb1_i.phys_rd != `BBUS_OOO_PHYS_ZERO) &&
        !wb1_i.exception.valid;

    assign wb_accept_mask_o = {accepted1_c, accepted0_c};
    assign wb0_o = accepted0_c ? wb0_i : '0;
    assign wb1_o = accepted1_c ? wb1_i : '0;

    assign ordinary_wakeup_valid_o = {ordinary_wakeup1_c, ordinary_wakeup0_c};
    assign wakeup_phys0_o = ordinary_wakeup0_c ? wb0_i.phys_rd : `BBUS_OOO_PHYS_ZERO;
    assign wakeup_phys1_o = ordinary_wakeup1_c ? wb1_i.phys_rd : `BBUS_OOO_PHYS_ZERO;

    assign dual_wb_fire_o = accepted0_c && accepted1_c;
    assign dual_wakeup_fire_o = ordinary_wakeup0_c && ordinary_wakeup1_c;

    assign duplicate_phys_bug_o =
        ordinary_wakeup0_c &&
        ordinary_wakeup1_c &&
        (wb0_i.phys_rd == wb1_i.phys_rd) &&
        (wb0_i.phys_rd != `BBUS_OOO_PHYS_ZERO);

    assign duplicate_rob_tag_bug_o =
        accepted0_c &&
        accepted1_c &&
        wb0_i.rob_tag.valid &&
        wb1_i.rob_tag.valid &&
        (wb0_i.rob_tag == wb1_i.rob_tag);

    assign stale_drop0_o = wb0_i.valid && !wb0_rob_match_i;
    assign stale_drop1_o = wb1_i.valid && !wb1_rob_match_i;
    assign killed_drop0_o = wb0_i.valid && wb0_killed_i;
    assign killed_drop1_o = wb1_i.valid && wb1_killed_i;

    assign exception_no_wakeup0_o = accepted0_c && wb0_i.exception.valid;
    assign exception_no_wakeup1_o = accepted1_c && wb1_i.exception.valid;
    assign p0_wakeup_suppressed0_o =
        accepted0_c &&
        wb0_i.rf_wen &&
        !wb0_i.exception.valid &&
        (wb0_i.phys_rd == `BBUS_OOO_PHYS_ZERO);
    assign p0_wakeup_suppressed1_o =
        accepted1_c &&
        wb1_i.rf_wen &&
        !wb1_i.exception.valid &&
        (wb1_i.phys_rd == `BBUS_OOO_PHYS_ZERO);
endmodule
