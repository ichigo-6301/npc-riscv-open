// Headless public wrapper for the frozen RV32IM single-issue source set.
// There are deliberately no board pins here: memory is owned by the public
// DPI service and all legacy AXI pins are tied off for the behavioral path.

module npc_public_sim_top (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [4:0]  debug_arch_idx,
    output logic        commit_valid,
    output logic [31:0] commit_pc,
    output logic [31:0] commit_instr,
    output logic [31:0] commit_nextpc,
    output logic        commit1_valid,
    output logic [31:0] commit1_pc,
    output logic [31:0] commit1_instr,
    output logic [31:0] commit1_nextpc,
    output logic        halt_valid,
    output logic [31:0] halt_pc,
    output logic [31:0] halt_instr,
    output logic [3:0]  halt_reason,
    output logic        idle,
    output logic [31:0] debug_arch_pc,
    output logic [31:0] debug_arch_gpr
);
    wire [31:0] ibus_awaddr, ibus_wdata, ibus_araddr, ibus_rdata;
    wire [7:0]  ibus_awlen, ibus_arlen;
    wire [2:0]  ibus_awsize, ibus_arsize;
    wire [1:0]  ibus_awburst, ibus_arburst, ibus_bresp, ibus_rresp;
    wire [3:0]  ibus_wstrb;
    wire        ibus_awvalid, ibus_awready, ibus_wlast, ibus_wvalid, ibus_wready;
    wire        ibus_bvalid, ibus_bready, ibus_arvalid, ibus_arready;
    wire        ibus_rvalid, ibus_rready, ibus_rlast;

    wire [31:0] dbus_awaddr, dbus_wdata, dbus_araddr, dbus_rdata;
    wire [7:0]  dbus_awlen, dbus_arlen;
    wire [2:0]  dbus_awsize, dbus_arsize;
    wire [1:0]  dbus_awburst, dbus_arburst, dbus_bresp, dbus_rresp;
    wire [3:0]  dbus_wstrb;
    wire        dbus_awvalid, dbus_awready, dbus_wlast, dbus_wvalid, dbus_wready;
    wire        dbus_bvalid, dbus_bready, dbus_arvalid, dbus_arready;
    wire        dbus_rvalid, dbus_rready, dbus_rlast;

    // The CPU's DPI bridge is selected by NPC_USE_DPI.  The AXI side remains
    // quiescent in the public behavioral profile and cannot form a ready loop.
    assign ibus_awready = 1'b0;
    assign ibus_wready  = 1'b0;
    assign ibus_bresp   = 2'b00;
    assign ibus_bvalid  = 1'b0;
    assign ibus_arready = 1'b0;
    assign ibus_rdata   = 32'b0;
    assign ibus_rresp   = 2'b00;
    assign ibus_rvalid  = 1'b0;
    assign ibus_rlast   = 1'b0;
    assign dbus_awready = 1'b0;
    assign dbus_wready  = 1'b0;
    assign dbus_bresp   = 2'b00;
    assign dbus_bvalid  = 1'b0;
    assign dbus_arready = 1'b0;
    assign dbus_rdata   = 32'b0;
    assign dbus_rresp   = 2'b00;
    assign dbus_rvalid  = 1'b0;
    assign dbus_rlast   = 1'b0;

    cpu_top u_cpu (
        .clk(clk), .rst_n(rst_n),
        .commit_valid(commit_valid), .commit_pc(commit_pc),
        .commit_instr(commit_instr), .commit_nextpc(commit_nextpc),
        .ibus_axi_awaddr(ibus_awaddr), .ibus_axi_awlen(ibus_awlen),
        .ibus_axi_awsize(ibus_awsize), .ibus_axi_awburst(ibus_awburst),
        .ibus_axi_awvalid(ibus_awvalid), .ibus_axi_awready(ibus_awready),
        .ibus_axi_wdata(ibus_wdata), .ibus_axi_wstrb(ibus_wstrb),
        .ibus_axi_wlast(ibus_wlast), .ibus_axi_wvalid(ibus_wvalid),
        .ibus_axi_wready(ibus_wready), .ibus_axi_bresp(ibus_bresp),
        .ibus_axi_bvalid(ibus_bvalid), .ibus_axi_bready(ibus_bready),
        .ibus_axi_araddr(ibus_araddr), .ibus_axi_arlen(ibus_arlen),
        .ibus_axi_arsize(ibus_arsize), .ibus_axi_arburst(ibus_arburst),
        .ibus_axi_arvalid(ibus_arvalid), .ibus_axi_arready(ibus_arready),
        .ibus_axi_rdata(ibus_rdata), .ibus_axi_rresp(ibus_rresp),
        .ibus_axi_rvalid(ibus_rvalid), .ibus_axi_rready(ibus_rready),
        .ibus_axi_rlast(ibus_rlast),
        .dbus_axi_awaddr(dbus_awaddr), .dbus_axi_awlen(dbus_awlen),
        .dbus_axi_awsize(dbus_awsize), .dbus_axi_awburst(dbus_awburst),
        .dbus_axi_awvalid(dbus_awvalid), .dbus_axi_awready(dbus_awready),
        .dbus_axi_wdata(dbus_wdata), .dbus_axi_wstrb(dbus_wstrb),
        .dbus_axi_wlast(dbus_wlast), .dbus_axi_wvalid(dbus_wvalid),
        .dbus_axi_wready(dbus_wready), .dbus_axi_bresp(dbus_bresp),
        .dbus_axi_bvalid(dbus_bvalid), .dbus_axi_bready(dbus_bready),
        .dbus_axi_araddr(dbus_araddr), .dbus_axi_arlen(dbus_arlen),
        .dbus_axi_arsize(dbus_arsize), .dbus_axi_arburst(dbus_arburst),
        .dbus_axi_arvalid(dbus_arvalid), .dbus_axi_arready(dbus_arready),
        .dbus_axi_rdata(dbus_rdata), .dbus_axi_rresp(dbus_rresp),
        .dbus_axi_rvalid(dbus_rvalid), .dbus_axi_rready(dbus_rready),
        .dbus_axi_rlast(dbus_rlast)
    );

    assign commit1_valid = 1'b0;
    assign commit1_pc = 32'b0;
    assign commit1_instr = 32'b0;
    assign commit1_nextpc = 32'b0;
    assign halt_valid = 1'b0;
    assign halt_pc = 32'b0;
    assign halt_instr = 32'b0;
    assign halt_reason = 4'b0;
    assign idle = 1'b0;
    assign debug_arch_pc = u_cpu.arch_pc;
    assign debug_arch_gpr = u_cpu.rf.rf[debug_arch_idx];
endmodule
