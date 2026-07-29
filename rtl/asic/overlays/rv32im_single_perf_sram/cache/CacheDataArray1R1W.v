`timescale 1ns / 1ps

module CacheDataArray1R1W #(
    parameter integer ADDR_WIDTH = 8,
    parameter integer DATA_WIDTH = 32,
    parameter integer DEPTH = (1 << ADDR_WIDTH),
    parameter integer WSTRB_WIDTH = (DATA_WIDTH / 8),
    parameter integer MEMORY_KIND = 0
) (
    input clk,
    input ren,
    input [ADDR_WIDTH-1:0] raddr,
    output [DATA_WIDTH-1:0] rdata,
    input wen,
    input [ADDR_WIDTH-1:0] waddr,
    input [DATA_WIDTH-1:0] wdata,
    input [WSTRB_WIDTH-1:0] wstrb
);
`ifdef SYNTHESIS
`ifdef NPC_ASIC
`ifdef NPC_ASIC_SRAM
    generate
        if (ADDR_WIDTH <= 9 && DATA_WIDTH == 32 && WSTRB_WIDTH == 4 &&
            MEMORY_KIND == 0) begin : gen_asic_icache_macro
            wire [8:0] macro_raddr = {{(9 - ADDR_WIDTH){1'b0}}, raddr};
            wire [8:0] macro_waddr = {{(9 - ADDR_WIDTH){1'b0}}, waddr};
            npc_icache_data_1r1w_512x32 u_macro (
                .clk0(clk),
                .csb0(!wen),
                .addr0(macro_waddr),
                .din0(wdata),
                .clk1(clk),
                .csb1(!ren),
                .addr1(macro_raddr),
                .dout1(rdata)
            );
        end else if (ADDR_WIDTH <= 9 && DATA_WIDTH == 32 && WSTRB_WIDTH == 4 &&
                     MEMORY_KIND == 1) begin : gen_asic_dcache_macro
            wire [8:0] macro_raddr = {{(9 - ADDR_WIDTH){1'b0}}, raddr};
            wire [8:0] macro_waddr = {{(9 - ADDR_WIDTH){1'b0}}, waddr};
            npc_dcache_data_1r1w_512x32_b8 u_macro (
                .clk0(clk),
                .csb0(!wen),
                .wmask0(wstrb),
                .addr0(macro_waddr),
                .din0(wdata),
                .clk1(clk),
                .csb1(!ren),
                .addr1(macro_raddr),
                .dout1(rdata)
            );
        end else begin : gen_behavioral_fallback
            reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
            reg [DATA_WIDTH-1:0] rdata_r;
            integer byte_i;

            assign rdata = rdata_r;

            always @(posedge clk) begin
                if (ren) rdata_r <= mem[raddr];
                if (wen) begin
                    for (byte_i = 0; byte_i < WSTRB_WIDTH; byte_i = byte_i + 1) begin
                        if (wstrb[byte_i]) mem[waddr][byte_i * 8 +: 8] <= wdata[byte_i * 8 +: 8];
                    end
                end
            end
        end
    endgenerate
`else
`ifdef NPC_CACHE_DATA_ARRAY_BLACKBOX
    generate
        if (ADDR_WIDTH <= 9 && DATA_WIDTH == 32 && WSTRB_WIDTH == 4) begin : gen_asic_macro
            wire [8:0] macro_raddr = {{(9 - ADDR_WIDTH){1'b0}}, raddr};
            wire [8:0] macro_waddr = {{(9 - ADDR_WIDTH){1'b0}}, waddr};
            npc_cache_data_array_1r1w_512x32 u_macro (
                .clk(clk),
                .ren(ren),
                .raddr(macro_raddr),
                .rdata(rdata),
                .wen(wen),
                .waddr(macro_waddr),
                .wdata(wdata),
                .wmask(wstrb)
            );
        end else begin : gen_behavioral_fallback
            reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
            reg [DATA_WIDTH-1:0] rdata_r;
            integer byte_i;

            assign rdata = rdata_r;

            always @(posedge clk) begin
                if (ren) rdata_r <= mem[raddr];
                if (wen) begin
                    for (byte_i = 0; byte_i < WSTRB_WIDTH; byte_i = byte_i + 1) begin
                        if (wstrb[byte_i]) mem[waddr][byte_i * 8 +: 8] <= wdata[byte_i * 8 +: 8];
                    end
                end
            end
        end
    endgenerate
`else
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [DATA_WIDTH-1:0] rdata_r;
    integer byte_i;

    assign rdata = rdata_r;

    always @(posedge clk) begin
        if (ren) rdata_r <= mem[raddr];
        if (wen) begin
            for (byte_i = 0; byte_i < WSTRB_WIDTH; byte_i = byte_i + 1) begin
                if (wstrb[byte_i]) mem[waddr][byte_i * 8 +: 8] <= wdata[byte_i * 8 +: 8];
            end
        end
    end
`endif
`endif
`else
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [DATA_WIDTH-1:0] rdata_r;
    integer byte_i;

    assign rdata = rdata_r;

    always @(posedge clk) begin
        if (ren) rdata_r <= mem[raddr];
        if (wen) begin
            for (byte_i = 0; byte_i < WSTRB_WIDTH; byte_i = byte_i + 1) begin
                if (wstrb[byte_i]) mem[waddr][byte_i * 8 +: 8] <= wdata[byte_i * 8 +: 8];
            end
        end
    end
`endif
`else
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [DATA_WIDTH-1:0] rdata_r;
    integer byte_i;

    assign rdata = rdata_r;

    always @(posedge clk) begin
        if (ren) rdata_r <= mem[raddr];
        if (wen) begin
            for (byte_i = 0; byte_i < WSTRB_WIDTH; byte_i = byte_i + 1) begin
                if (wstrb[byte_i]) mem[waddr][byte_i * 8 +: 8] <= wdata[byte_i * 8 +: 8];
            end
        end
    end
`endif
endmodule
