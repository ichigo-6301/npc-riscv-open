// D7 synthesis-only XPM compatibility models. They preserve the Linux cache
// port/latency contract while expanding storage into ordinary registers.
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
endmodule
