`timescale 1ns / 1ps
`include "include/bbus_core_defs.svh"

module pairing_unit #(
    parameter SLOT1_ENABLE = 1'b0
) (
    input  bbus_uop_t slot0_uop,
    input  bbus_uop_t slot1_uop,
    output bbus_pair_decision_t decision
);
    wire slot1_enabled = SLOT1_ENABLE;

    wire slot0_has_control =
        slot0_uop.valid &&
        ((slot0_uop.fu == BBUS_FU_BRU) ||
         (slot0_uop.branch != BBUS_BR_NONE_E));

    wire slot0_has_mem_or_csr =
        slot0_uop.valid &&
        ((slot0_uop.fu == BBUS_FU_LSU) ||
         (slot0_uop.fu == BBUS_FU_CSR) ||
         (slot0_uop.fu == BBUS_FU_MDU) ||
         (slot0_uop.mem_wr != 2'b00) ||
         (slot0_uop.csr_wen != 2'b00));

    wire slot0_has_sys_or_exception =
        slot0_uop.valid &&
        ((slot0_uop.fu == BBUS_FU_SYS) ||
         slot0_uop.illegal ||
         slot0_uop.is_ebreak ||
         slot0_uop.exc.valid);

    wire slot1_is_restricted_alu =
        slot1_uop.valid &&
        (slot1_uop.fu == BBUS_FU_ALU) &&
        (slot1_uop.branch == BBUS_BR_NONE_E) &&
        (slot1_uop.mem_wr == 2'b00) &&
        (slot1_uop.csr_wen == 2'b00) &&
        !slot1_uop.illegal &&
        !slot1_uop.is_ebreak &&
        !slot1_uop.exc.valid;

    wire slot0_writes_rd =
        slot0_uop.valid &&
        slot0_uop.rf_wen &&
        (slot0_uop.rd != 5'b0);

    wire slot1_writes_rd =
        slot1_uop.valid &&
        slot1_uop.rf_wen &&
        (slot1_uop.rd != 5'b0);

    wire raw_dep =
        slot0_writes_rd &&
        ((slot1_uop.uses_rs1 && (slot1_uop.rs1 == slot0_uop.rd)) ||
         (slot1_uop.uses_rs2 && (slot1_uop.rs2 == slot0_uop.rd)));

    wire waw_dep =
        slot0_writes_rd &&
        slot1_writes_rd &&
        (slot0_uop.rd == slot1_uop.rd);

    wire pair_is_legal =
        slot0_uop.valid &&
        slot1_enabled &&
        slot1_uop.valid &&
        !slot0_has_sys_or_exception &&
        !slot0_has_mem_or_csr &&
        !slot0_has_control &&
        slot1_is_restricted_alu &&
        !raw_dep &&
        !waw_dep;

    wire [1:0] issue_count =
        pair_is_legal ? 2'd2 :
        slot0_uop.valid ? 2'd1 :
        2'd0;

    bbus_pair_reason_e reason;

    assign reason =
        !slot0_uop.valid              ? BBUS_PAIR_SLOT0_INVALID :
        !slot1_enabled                ? BBUS_PAIR_SLOT1_DISABLED :
        !slot1_uop.valid              ? BBUS_PAIR_SLOT1_INVALID :
        slot0_has_sys_or_exception    ? BBUS_PAIR_SYS_OR_EXCEPTION :
        slot0_has_mem_or_csr          ? BBUS_PAIR_MEM_OR_CSR :
        slot0_has_control             ? BBUS_PAIR_CONTROL :
        !slot1_is_restricted_alu      ? BBUS_PAIR_SLOT1_NOT_ALU :
        raw_dep                       ? BBUS_PAIR_RAW_DEP :
        waw_dep                       ? BBUS_PAIR_WAW_DEP :
        pair_is_legal                 ? BBUS_PAIR_OK :
        BBUS_PAIR_RESERVED;

    assign decision.pair_valid = pair_is_legal;
    assign decision.slot0_valid = slot0_uop.valid;
    assign decision.slot1_valid = pair_is_legal;
    assign decision.issue_count = issue_count;
    assign decision.reason = reason;
endmodule
