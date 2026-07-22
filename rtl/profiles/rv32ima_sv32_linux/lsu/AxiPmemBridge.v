`timescale 1ns / 1ps

module AxiPmemBridge #(
    parameter integer BATCH_WORDS = 8
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
    output reg [31:0] resp_rdata,

    output [31:0] m_axi_awaddr,
    output [7:0] m_axi_awlen,
    output [2:0] m_axi_awsize,
    output [1:0] m_axi_awburst,
    output reg m_axi_awvalid,
    input m_axi_awready,

    output [31:0] m_axi_wdata,
    output [3:0] m_axi_wstrb,
    output m_axi_wlast,
    output reg m_axi_wvalid,
    input m_axi_wready,

    input [1:0] m_axi_bresp,
    input m_axi_bvalid,
    output m_axi_bready,

    output [31:0] m_axi_araddr,
    output [7:0] m_axi_arlen,
    output [2:0] m_axi_arsize,
    output [1:0] m_axi_arburst,
    output reg m_axi_arvalid,
    input m_axi_arready,

    input [31:0] m_axi_rdata,
    input [1:0] m_axi_rresp,
    input m_axi_rvalid,
    output m_axi_rready,
    input m_axi_rlast
);
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_WRITE_RESP = 3'd1;
    localparam [2:0] S_READ_RESP = 3'd2;
    localparam [2:0] S_RESP = 3'd3;
    localparam [2:0] S_WRITE_BURST_DATA = 3'd4;
    localparam [2:0] S_WRITE_BURST_RESP = 3'd5;

    function [7:0] burst_len;
        input integer words;
        integer i;
        begin
            burst_len = 8'd0;
            for (i = 1; i < words; i = i + 1) begin
                burst_len = burst_len + 8'd1;
            end
        end
    endfunction

    localparam [7:0] BATCH_AXI_LEN = burst_len(BATCH_WORDS);
    localparam WRAP_BURST_LEGAL =
        (BATCH_WORDS == 2) || (BATCH_WORDS == 4) ||
        (BATCH_WORDS == 8) || (BATCH_WORDS == 16);

    reg [2:0] state;
    reg [31:0] addr_r;
    reg [31:0] wdata_r;
    reg [3:0] wstrb_r;
    reg [2:0] len_r;
    reg burst_read_r;
    reg burst_write_r;

    reg bw_aw_done;
    reg [7:0] bw_beats_rcvd;
    reg [7:0] bw_beats_sent;
    reg bw_buf_valid;
    reg [31:0] bw_buf_wdata;
    reg [3:0] bw_buf_wstrb;

    wire req_fire = req_valid && req_ready;
    wire aw_fire = m_axi_awvalid && m_axi_awready;
    wire w_fire = m_axi_wvalid && m_axi_wready;
    wire b_fire = m_axi_bvalid && m_axi_bready;
    wire ar_fire = m_axi_arvalid && m_axi_arready;
    wire r_fire = m_axi_rvalid && m_axi_rready;
    wire resp_fire = resp_valid && resp_ready;

    wire req_burst_read = req_fire && !req_write && (req_len == 3'd0);
    wire req_burst_write = req_fire && req_write && (req_len == 3'd0);
    wire read_done = burst_read_r ? (r_fire && m_axi_rlast) : r_fire;

    wire [2:0] size =
        (len_r == 3'd0) ? 3'b010 :
        (len_r == 3'd4) ? 3'b010 :
        (len_r == 3'd2) ? 3'b001 :
        3'b000;
    wire [2:0] awsize_eff = burst_write_r ? 3'b010 : size;

    wire bw_sender_ready = bw_aw_done && m_axi_wready && m_axi_wvalid;
    wire bw_need_more_req = (bw_beats_rcvd < BATCH_WORDS);
    wire bw_can_take_req = !bw_buf_valid || bw_sender_ready;
    wire bw_w_fire = (state == S_WRITE_BURST_DATA) && bw_aw_done && bw_buf_valid && m_axi_wready;
    wire bw_last_w_fire = bw_w_fire && (bw_beats_sent == (BATCH_WORDS - 1));

    // Local request protocol:
    // - read req_len==0  => line read burst
    // - write req_len==0 => line write burst (BATCH_WORDS beats from req channel)
    assign req_ready =
        ((state == S_IDLE) && !resp_valid) ||
        ((state == S_WRITE_BURST_DATA) && !resp_valid && bw_need_more_req && bw_can_take_req);

    assign m_axi_awaddr = addr_r;
    assign m_axi_awlen = burst_write_r ? BATCH_AXI_LEN : 8'd0;
    assign m_axi_awsize = awsize_eff;
    assign m_axi_awburst = 2'b01;

    assign m_axi_wdata = burst_write_r ? bw_buf_wdata : wdata_r;
    assign m_axi_wstrb = burst_write_r ? bw_buf_wstrb : wstrb_r;
    assign m_axi_wlast = burst_write_r ? (bw_beats_sent == (BATCH_WORDS - 1)) : 1'b1;
    assign m_axi_bready =
        ((state == S_WRITE_RESP) || (state == S_WRITE_BURST_RESP)) && !resp_valid;

    assign m_axi_araddr = addr_r;
    assign m_axi_arlen = burst_read_r ? BATCH_AXI_LEN : 8'd0;
    assign m_axi_arsize = size;
    // Cache-line refill uses WRAP so the critical word can be returned first.
    // Fallback to INCR when burst length is not legal for AXI WRAP.
    assign m_axi_arburst = (burst_read_r && WRAP_BURST_LEGAL) ? 2'b10 : 2'b01;
    assign m_axi_rready = (state == S_READ_RESP) && (!resp_valid || resp_ready);

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
            addr_r <= 32'b0;
            wdata_r <= 32'b0;
            wstrb_r <= 4'b0;
            len_r <= 3'd4;
            burst_read_r <= 1'b0;
            burst_write_r <= 1'b0;
            bw_aw_done <= 1'b0;
            bw_beats_rcvd <= 8'd0;
            bw_beats_sent <= 8'd0;
            bw_buf_valid <= 1'b0;
            bw_buf_wdata <= 32'b0;
            bw_buf_wstrb <= 4'b0;
            resp_valid <= 1'b0;
            resp_rdata <= 32'b0;
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid <= 1'b0;
            m_axi_arvalid <= 1'b0;
        end else begin
            if (resp_fire) begin
                resp_valid <= 1'b0;
            end

            if (aw_fire) begin
                m_axi_awvalid <= 1'b0;
            end
            if (ar_fire) begin
                m_axi_arvalid <= 1'b0;
            end

            case (state)
                S_IDLE: begin
                    m_axi_wvalid <= 1'b0;
                    bw_aw_done <= 1'b0;
                    bw_beats_rcvd <= 8'd0;
                    bw_beats_sent <= 8'd0;
                    bw_buf_valid <= 1'b0;

                    if (req_fire) begin
                        addr_r <= req_addr;
                        wdata_r <= req_wdata;
                        wstrb_r <= req_wstrb;
                        len_r <= req_len;
                        burst_read_r <= req_burst_read;
                        burst_write_r <= req_burst_write;
                        if (req_write) begin
                            m_axi_awvalid <= 1'b1;
                            if (req_burst_write) begin
                                // First beat is carried by this first req.
                                bw_beats_rcvd <= 8'd1;
                                bw_beats_sent <= 8'd0;
                                bw_buf_valid <= 1'b1;
                                bw_buf_wdata <= req_wdata;
                                bw_buf_wstrb <= req_wstrb;
                                state <= S_WRITE_BURST_DATA;
                            end else begin
                                m_axi_wvalid <= 1'b1;
                                state <= S_WRITE_RESP;
                            end
                        end else begin
                            m_axi_arvalid <= 1'b1;
                            state <= S_READ_RESP;
                        end
                    end
                end

                S_WRITE_RESP: begin
                    if (w_fire) begin
                        m_axi_wvalid <= 1'b0;
                    end
                    if (b_fire) begin
                        resp_rdata <= 32'b0;
                        resp_valid <= 1'b1;
                        state <= S_RESP;
                    end
                end

                S_WRITE_BURST_DATA: begin
                    if (aw_fire) begin
                        bw_aw_done <= 1'b1;
                    end

                    // Issue one W beat when the buffer holds data and AW handshake is done.
                    m_axi_wvalid <= bw_aw_done && bw_buf_valid;

                    if (bw_w_fire) begin
                        bw_buf_valid <= 1'b0;
                        bw_beats_sent <= bw_beats_sent + 8'd1;
                    end

                    // Capture the next burst beat from req channel.
                    if (req_fire && bw_need_more_req) begin
                        bw_buf_wdata <= req_wdata;
                        bw_buf_wstrb <= req_wstrb;
                        bw_buf_valid <= 1'b1;
                        bw_beats_rcvd <= bw_beats_rcvd + 8'd1;
                    end

                    // All beats accepted and sent -> wait for one B response.
                    if (bw_last_w_fire) begin
                        m_axi_wvalid <= 1'b0;
                        state <= S_WRITE_BURST_RESP;
                    end
                end

                S_WRITE_BURST_RESP: begin
                    if (b_fire) begin
                        resp_rdata <= 32'b0;
                        resp_valid <= 1'b1;
                        state <= S_RESP;
                    end
                end

                S_READ_RESP: begin
                    if (r_fire) begin
                        resp_rdata <= m_axi_rdata;
                        resp_valid <= 1'b1;
                        if (read_done) begin
                            state <= S_RESP;
                        end
                    end
                end

                S_RESP: begin
                    if (resp_fire) begin
                        burst_read_r <= 1'b0;
                        burst_write_r <= 1'b0;
                        state <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    wire unused_axi_resp = (|m_axi_bresp) | (|m_axi_rresp) | m_axi_rlast;
endmodule
