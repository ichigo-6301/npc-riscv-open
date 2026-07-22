`timescale 1ns / 1ps
`include "bbus_ooo_types.svh"

module ooo_prf (
    input  logic clk,
    input  logic reset,

    input  bbus_ooo_phys_reg_t read_rs1_phys_i,
    input  bbus_ooo_phys_reg_t read_rs2_phys_i,
    output logic [`BBUS_OOO_XLEN-1:0] read_rs1_data_o,
    output logic [`BBUS_OOO_XLEN-1:0] read_rs2_data_o,
    input  bbus_ooo_phys_reg_t read1_rs1_phys_i,
    input  bbus_ooo_phys_reg_t read1_rs2_phys_i,
    output logic [`BBUS_OOO_XLEN-1:0] read1_rs1_data_o,
    output logic [`BBUS_OOO_XLEN-1:0] read1_rs2_data_o,

    input  logic write_valid_i,
    input  bbus_ooo_phys_reg_t write_phys_i,
    input  logic [`BBUS_OOO_XLEN-1:0] write_data_i,
    input  logic write1_valid_i,
    input  bbus_ooo_phys_reg_t write1_phys_i,
    input  logic [`BBUS_OOO_XLEN-1:0] write1_data_i,

    input  bbus_ooo_phys_reg_t debug_phys_idx_i,
    output logic [`BBUS_OOO_XLEN-1:0] debug_data_o
);
    logic [`BBUS_OOO_XLEN-1:0] data_q [`BBUS_OOO_PHYS_REGS-1:0];

    assign read_rs1_data_o = (read_rs1_phys_i == `BBUS_OOO_PHYS_ZERO) ? '0 : data_q[read_rs1_phys_i];
    assign read_rs2_data_o = (read_rs2_phys_i == `BBUS_OOO_PHYS_ZERO) ? '0 : data_q[read_rs2_phys_i];
    assign read1_rs1_data_o = (read1_rs1_phys_i == `BBUS_OOO_PHYS_ZERO) ? '0 : data_q[read1_rs1_phys_i];
    assign read1_rs2_data_o = (read1_rs2_phys_i == `BBUS_OOO_PHYS_ZERO) ? '0 : data_q[read1_rs2_phys_i];
    assign debug_data_o = (debug_phys_idx_i == `BBUS_OOO_PHYS_ZERO) ? '0 : data_q[debug_phys_idx_i];

    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < `BBUS_OOO_PHYS_REGS; i = i + 1) begin
                data_q[i] <= `BBUS_OOO_XLEN'(i);
            end
            data_q[`BBUS_OOO_PHYS_ZERO] <= '0;
        end else begin
            assert (!(write_valid_i && write1_valid_i &&
                      (write_phys_i != `BBUS_OOO_PHYS_ZERO) &&
                      (write_phys_i == write1_phys_i)))
                else $fatal(1, "PRF dual-write conflict on p%0d", write_phys_i);
            if (write_valid_i && (write_phys_i != `BBUS_OOO_PHYS_ZERO)) begin
                data_q[write_phys_i] <= write_data_i;
            end
            if (write1_valid_i && (write1_phys_i != `BBUS_OOO_PHYS_ZERO)) begin
                data_q[write1_phys_i] <= write1_data_i;
            end
            data_q[`BBUS_OOO_PHYS_ZERO] <= '0;
        end
    end
endmodule
