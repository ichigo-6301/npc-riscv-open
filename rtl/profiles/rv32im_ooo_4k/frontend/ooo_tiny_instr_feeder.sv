`timescale 1ns / 1ps

module ooo_tiny_instr_feeder (
    input  logic clk,
    input  logic reset,

    input  logic program_valid_i,
    input  logic [31:0] program_pc_i,
    input  logic [31:0] program_instr_i,
    output logic program_ready_o,

    input  logic consume_i,
    input  logic consume2_i,
    input  logic stop_i,
    input  logic flush_i,

    output logic fetch_valid_o,
    output logic [31:0] fetch_pc_o,
    output logic [31:0] fetch_instr_o,
    output logic fetch1_valid_o,
    output logic [31:0] fetch1_pc_o,
    output logic [31:0] fetch1_instr_o
);
    logic [1:0] count_q;
    logic [31:0] pc_q [1:0];
    logic [31:0] instr_q [1:0];
    logic [1:0] consume_count_c;
    logic [1:0] count_after_consume_c;

    assign consume_count_c =
        (consume2_i && (count_q >= 2'd2)) ? 2'd2 :
        ((consume_i && (count_q >= 2'd1)) ? 2'd1 : 2'd0);
    assign count_after_consume_c = count_q - consume_count_c;

    assign program_ready_o = (count_after_consume_c < 2'd2) && !stop_i && !flush_i;
    assign fetch_valid_o = (count_q >= 2'd1) && !stop_i && !flush_i;
    assign fetch_pc_o = pc_q[0];
    assign fetch_instr_o = instr_q[0];
    assign fetch1_valid_o = (count_q >= 2'd2) && !stop_i && !flush_i;
    assign fetch1_pc_o = pc_q[1];
    assign fetch1_instr_o = instr_q[1];

    always_ff @(posedge clk) begin
        if (reset || flush_i) begin
            count_q <= 2'd0;
            pc_q[0] <= 32'b0;
            pc_q[1] <= 32'b0;
            instr_q[0] <= 32'b0;
            instr_q[1] <= 32'b0;
        end else begin
            logic [1:0] next_count;
            logic [31:0] next_pc [1:0];
            logic [31:0] next_instr [1:0];

            next_count = count_q;
            next_pc[0] = pc_q[0];
            next_pc[1] = pc_q[1];
            next_instr[0] = instr_q[0];
            next_instr[1] = instr_q[1];

            if (consume_count_c == 2'd2) begin
                next_count = 2'd0;
                next_pc[0] = 32'b0;
                next_pc[1] = 32'b0;
                next_instr[0] = 32'b0;
                next_instr[1] = 32'b0;
            end else if (consume_count_c == 2'd1) begin
                next_count = count_q - 2'd1;
                next_pc[0] = pc_q[1];
                next_pc[1] = 32'b0;
                next_instr[0] = instr_q[1];
                next_instr[1] = 32'b0;
            end

            if (program_valid_i && program_ready_o) begin
                next_pc[next_count[0]] = program_pc_i;
                next_instr[next_count[0]] = program_instr_i;
                next_count = next_count + 2'd1;
            end

            count_q <= next_count;
            pc_q[0] <= next_pc[0];
            pc_q[1] <= next_pc[1];
            instr_q[0] <= next_instr[0];
            instr_q[1] <= next_instr[1];
        end
    end
endmodule
