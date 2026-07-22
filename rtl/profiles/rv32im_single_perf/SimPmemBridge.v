`timescale 1ns / 1ps

`ifdef NPC_USE_DPI
import "DPI-C" function void dpi_pmem_req(
    input int channel,
    input int is_write,
    input int unsigned addr,
    input int len,
    input int unsigned data
);
import "DPI-C" function int dpi_pmem_resp(
    input int channel,
    output int unsigned data
);
import "DPI-C" function int unsigned pmem_read(
    input int unsigned addr,
    input int len
);
import "DPI-C" function void pmem_write(
    input int unsigned addr,
    input int len,
    input int unsigned data
);

module SimPmemBridge #(
    parameter integer CHANNEL = 0,
    parameter integer BATCH_WORDS = 8,
    parameter integer MEM_LATENCY = 2
) (
    input clk,
    input rst_n,

    input req_valid,
    output req_ready,
    input req_write,
    input [31:0] req_addr,
    input [31:0] req_wdata,
    input [3:0] req_wstrb,
    input [2:0] req_len,

    output reg resp_valid,
    input resp_ready,
    output reg [31:0] resp_rdata
);
    reg busy;
    reg batch_read_mode;
    reg batch_write_mode;
    reg [31:0] batch_addr;
    reg [31:0] batch_line_base;
    reg [31:0] batch_start_word;
    reg [31:0] batch_word;
    reg [31:0] batch_wcount;
    reg [31:0] delay_left;
    reg [31:0] dpi_rdata;

    wire batch_write_accepting =
        busy && batch_write_mode && (batch_wcount < BATCH_WORDS) && !resp_valid;

    wire req_fire = req_valid && req_ready;
    wire resp_fire = resp_valid && resp_ready;

    wire batch_read_req = req_fire && !busy && !req_write && (req_len == 3'd0);
    wire batch_write_start_req = req_fire && !busy && req_write && (req_len == 3'd0);
    wire batch_write_cont_req = req_fire && batch_write_accepting;
    wire batch_last_word = (batch_word == (BATCH_WORDS - 1));
    wire batch_can_emit = busy && batch_read_mode && (!resp_valid || resp_fire);
    wire [31:0] wrap_word = (batch_start_word + batch_word) & (BATCH_WORDS - 1);
    wire [31:0] wrap_addr = batch_line_base + (wrap_word << 2);

    assign req_ready = (!busy && !resp_valid) || batch_write_accepting;

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            batch_read_mode <= 1'b0;
            batch_write_mode <= 1'b0;
            batch_addr <= 32'b0;
            batch_line_base <= 32'b0;
            batch_start_word <= 32'b0;
            batch_word <= 32'b0;
            batch_wcount <= 32'b0;
            delay_left <= 32'b0;
            resp_valid <= 1'b0;
            resp_rdata <= 32'b0;
        end else begin
            if (resp_fire) begin
                resp_valid <= 1'b0;
            end

            if (batch_write_cont_req) begin
                // Cache write-back burst always sends full words with byte-enable=1111.
                // The current burst write protocol uses req_len==0 and BATCH_WORDS beats.
                pmem_write(req_addr, 4, req_wdata);
                batch_wcount <= batch_wcount + 32'd1;
            end else if (batch_read_req) begin
                busy <= 1'b1;
                batch_read_mode <= 1'b1;
                batch_write_mode <= 1'b0;
                batch_addr <= req_addr;
                batch_line_base <= req_addr & ~(BATCH_WORDS * 4 - 1);
                batch_start_word <= (req_addr >> 2) & (BATCH_WORDS - 1);
                batch_word <= 32'b0;
                delay_left <= MEM_LATENCY;
            end else if (batch_write_start_req) begin
                busy <= 1'b1;
                batch_read_mode <= 1'b0;
                batch_write_mode <= 1'b1;
                batch_wcount <= 32'd1;
                delay_left <= MEM_LATENCY;
                pmem_write(req_addr, 4, req_wdata);
            end else if (req_fire) begin
                busy <= 1'b1;
                batch_read_mode <= 1'b0;
                batch_write_mode <= 1'b0;
                dpi_pmem_req(CHANNEL, {31'b0, req_write}, req_addr, {29'b0, req_len}, req_wdata);
            end

            if (busy && !batch_read_mode && !batch_write_mode) begin
                if (dpi_pmem_resp(CHANNEL, dpi_rdata) != 0) begin
                    resp_rdata <= dpi_rdata;
                    resp_valid <= 1'b1;
                    busy <= 1'b0;
                end
            end else if (batch_can_emit) begin
                if (delay_left != 32'b0) begin
                    delay_left <= delay_left - 32'd1;
                end else begin
                    // Cache-line burst read with wrap order (critical word first).
                    resp_rdata <= pmem_read(wrap_addr, 4);
                    resp_valid <= 1'b1;
                    if (batch_last_word) begin
                        busy <= 1'b0;
                        batch_read_mode <= 1'b0;
                    end else begin
                        batch_word <= batch_word + 32'd1;
                    end
                end
            end else if (busy && batch_write_mode && (batch_wcount == BATCH_WORDS) && !resp_valid) begin
                if (delay_left != 32'b0) begin
                    delay_left <= delay_left - 32'd1;
                end else begin
                    resp_rdata <= 32'b0;
                    resp_valid <= 1'b1;
                    busy <= 1'b0;
                    batch_write_mode <= 1'b0;
                end
            end
        end
    end
    wire unused_req_wstrb = |req_wstrb;
endmodule
`endif
