// ASIC-only XPM compatibility models. Register mode expands storage into
// ordinary registers; SRAM mode binds only the exact Linux 512x32 cache leaves.
module xpm_memory_sdpram #(
    parameter integer ADDR_WIDTH_A = 1,
    parameter integer ADDR_WIDTH_B = 1,
    parameter integer AUTO_SLEEP_TIME = 0,
    parameter integer BYTE_WRITE_WIDTH_A = 8,
    parameter integer CASCADE_HEIGHT = 0,
    parameter CLOCKING_MODE = "common_clock",
    parameter ECC_MODE = "no_ecc",
    parameter MEMORY_INIT_FILE = "none",
    parameter MEMORY_INIT_PARAM = "0",
    parameter MEMORY_OPTIMIZATION = "true",
    parameter MEMORY_PRIMITIVE = "block",
    parameter integer MEMORY_SIZE = 32,
    parameter integer MESSAGE_CONTROL = 0,
    parameter integer READ_DATA_WIDTH_B = 32,
    parameter integer READ_LATENCY_B = 1,
    parameter READ_RESET_VALUE_B = "0",
    parameter RST_MODE_A = "SYNC",
    parameter RST_MODE_B = "SYNC",
    parameter integer SIM_ASSERT_CHK = 0,
    parameter integer USE_EMBEDDED_CONSTRAINT = 0,
    parameter integer USE_MEM_INIT = 0,
    parameter WAKEUP_TIME = "disable_sleep",
    parameter integer WRITE_DATA_WIDTH_A = 32,
    parameter WRITE_MODE_B = "no_change"
) (
    output logic dbiterrb,
    output logic [READ_DATA_WIDTH_B-1:0] doutb,
    output logic sbiterrb,
    input  logic [ADDR_WIDTH_A-1:0] addra,
    input  logic [ADDR_WIDTH_B-1:0] addrb,
    input  logic clka,
    input  logic clkb,
    input  logic [WRITE_DATA_WIDTH_A-1:0] dina,
    input  logic ena,
    input  logic enb,
    input  logic injectdbiterra,
    input  logic injectsbiterra,
    input  logic regceb,
    input  logic rstb,
    input  logic sleep,
    input  logic [(WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A)-1:0] wea
);
`ifdef NPC_ASIC_SRAM
    generate
        if (ADDR_WIDTH_A == 9 && ADDR_WIDTH_B == 9 &&
            BYTE_WRITE_WIDTH_A == 8 && MEMORY_SIZE == 16384 &&
            READ_DATA_WIDTH_B == 32 && READ_LATENCY_B == 1 &&
            WRITE_DATA_WIDTH_A == 32) begin : gen_asic_icache_macro
            wire [31:0] macro_dout;
            wire macro_write_enable = ena && !sleep && (|wea);
            wire macro_read_enable = enb && regceb && !sleep && !rstb;

            npc_icache_data_1r1w_512x32 u_macro (
                .clk0(clka),
                .csb0(!macro_write_enable),
                .addr0(addra),
                .din0(dina),
                .clk1(clkb),
                .csb1(!macro_read_enable),
                .addr1(addrb),
                .dout1(macro_dout)
            );

            assign doutb = rstb ? '0 : macro_dout;
        end else begin : gen_unsupported_sram_configuration
            npc_unsupported_sram_xpm_sdpram_configuration u_unsupported();
        end
    endgenerate
`else
    localparam integer DEPTH = 1 << ADDR_WIDTH_A;
    localparam integer BYTE_LANES = WRITE_DATA_WIDTH_A / BYTE_WRITE_WIDTH_A;
    logic [WRITE_DATA_WIDTH_A-1:0] mem [0:DEPTH-1];
    integer lane;

    always_ff @(posedge clka) begin
        if (ena && !sleep) begin
            for (lane = 0; lane < BYTE_LANES; lane = lane + 1) begin
                if (wea[lane])
                    mem[addra][lane*BYTE_WRITE_WIDTH_A +: BYTE_WRITE_WIDTH_A] <=
                        dina[lane*BYTE_WRITE_WIDTH_A +: BYTE_WRITE_WIDTH_A];
            end
        end
    end

    always_ff @(posedge clkb) begin
        if (rstb)
            doutb <= '0;
        else if (enb && regceb && !sleep)
            doutb <= mem[addrb];
    end
`endif

    assign dbiterrb = 1'b0;
    assign sbiterrb = 1'b0;
    logic unused = &{1'b0, injectdbiterra, injectsbiterra};
endmodule

module xpm_memory_tdpram #(
    parameter integer ADDR_WIDTH_A = 1,
    parameter integer ADDR_WIDTH_B = 1,
    parameter integer BYTE_WRITE_WIDTH_A = 8,
    parameter CLOCKING_MODE = "common_clock",
    parameter ECC_MODE = "no_ecc",
    parameter MEMORY_INIT_FILE = "none",
    parameter MEMORY_INIT_PARAM = "0",
    parameter MEMORY_OPTIMIZATION = "true",
    parameter MEMORY_PRIMITIVE = "block",
    parameter integer MEMORY_SIZE = 32,
    parameter integer MESSAGE_CONTROL = 0,
    parameter integer READ_DATA_WIDTH_A = 32,
    parameter integer READ_LATENCY_A = 1,
    parameter integer READ_DATA_WIDTH_B = 32,
    parameter integer READ_LATENCY_B = 1,
    parameter READ_RESET_VALUE_A = "0",
    parameter READ_RESET_VALUE_B = "0",
    parameter RST_MODE_A = "SYNC",
    parameter RST_MODE_B = "SYNC",
    parameter integer SIM_ASSERT_CHK = 0,
    parameter integer USE_EMBEDDED_CONSTRAINT = 0,
    parameter integer USE_MEM_INIT = 0,
    parameter WAKEUP_TIME = "disable_sleep",
    parameter integer WRITE_DATA_WIDTH_A = 32,
    parameter WRITE_MODE_A = "no_change",
    parameter integer WRITE_DATA_WIDTH_B = 32,
    parameter WRITE_MODE_B = "no_change"
) (
    output logic [READ_DATA_WIDTH_A-1:0] douta,
    output logic [READ_DATA_WIDTH_B-1:0] doutb,
    input  logic [ADDR_WIDTH_A-1:0] addra,
    input  logic [ADDR_WIDTH_B-1:0] addrb,
    input  logic clka,
    input  logic clkb,
    input  logic [WRITE_DATA_WIDTH_A-1:0] dina,
    input  logic [WRITE_DATA_WIDTH_B-1:0] dinb,
    input  logic ena,
    input  logic enb,
    input  logic [(WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A)-1:0] wea,
    input  logic [(WRITE_DATA_WIDTH_B/BYTE_WRITE_WIDTH_A)-1:0] web
);
`ifdef NPC_ASIC_SRAM
    generate
        if (ADDR_WIDTH_A == 9 && ADDR_WIDTH_B == 9 &&
            BYTE_WRITE_WIDTH_A == 8 && MEMORY_SIZE == 16384 &&
            READ_DATA_WIDTH_A == 32 && READ_LATENCY_A == 1 &&
            READ_DATA_WIDTH_B == 32 && READ_LATENCY_B == 1 &&
            WRITE_DATA_WIDTH_A == 32 && WRITE_DATA_WIDTH_B == 32) begin : gen_asic_dcache_macro
            wire [31:0] macro_dout;
            wire macro_write_enable = ena && (|wea);

            npc_dcache_data_1r1w_512x32_b8 u_macro (
                .clk0(clka),
                .csb0(!macro_write_enable),
                .wmask0(wea),
                .addr0(addra),
                .din0(dina),
                .clk1(clkb),
                .csb1(!enb),
                .addr1(addrb),
                .dout1(macro_dout)
            );

            assign douta = '0;
            assign doutb = macro_dout;
        end else begin : gen_unsupported_sram_configuration
            npc_unsupported_sram_xpm_tdpram_configuration u_unsupported();
        end
    endgenerate
    wire unused_port_b_write = &{1'b0, dinb, web};
`else
    localparam integer DEPTH = 1 << ADDR_WIDTH_A;
    localparam integer BYTE_LANES_A = WRITE_DATA_WIDTH_A / BYTE_WRITE_WIDTH_A;
    localparam integer BYTE_LANES_B = WRITE_DATA_WIDTH_B / BYTE_WRITE_WIDTH_A;
    logic [WRITE_DATA_WIDTH_A-1:0] mem [0:DEPTH-1];
    integer lane_a;

    always_ff @(posedge clka) begin
        if (ena) begin
            douta <= mem[addra];
            for (lane_a = 0; lane_a < BYTE_LANES_A; lane_a = lane_a + 1) begin
                if (wea[lane_a])
                    mem[addra][lane_a*BYTE_WRITE_WIDTH_A +: BYTE_WRITE_WIDTH_A] <=
                        dina[lane_a*BYTE_WRITE_WIDTH_A +: BYTE_WRITE_WIDTH_A];
            end
        end
    end

    always_ff @(posedge clkb) begin
        if (enb)
            doutb <= mem[addrb];
    end
    wire unused_port_b_write = &{1'b0, dinb, web};
`endif
endmodule
