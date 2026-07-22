`timescale 1ns / 1ps

module PrivCsrRegs #(ADDR_WIDTH = 1, DATA_WIDTH = 1, HART_ID = 32'd0) (
  input clk,
  input rst_n,

  input [ADDR_WIDTH-1:0] raddr1,
  output [DATA_WIDTH-1:0] rdata1,
  output raddr1_illegal,

  input [DATA_WIDTH-1:0] wdata1,
  input [ADDR_WIDTH-1:0] waddr1,
  output waddr1_illegal,
  input [DATA_WIDTH-1:0] wdata2,
  input [ADDR_WIDTH-1:0] waddr2,
  output waddr2_illegal,
  input [1:0] wen,

  // Retire-side hooks for architectural counters. These signals are expected
  // to describe the instruction retiring in the current cycle, so CSR reads
  // can observe the same-cycle counter increment that software expects.
  input commit_valid,
  input [31:0] commit_instr,
  input commit_exception,
  input [63:0] time_value_i,
  input timer_mtip_i,

  // Privileged update path (trap/xret), higher priority than normal CSR write.
  input priv_upd_we,
  input priv_upd_priv_we,
  input [1:0] priv_upd_priv,
  input priv_upd_mstatus_we,
  input [31:0] priv_upd_mstatus,
  input priv_upd_mepc_we,
  input [31:0] priv_upd_mepc,
  input priv_upd_mcause_we,
  input [31:0] priv_upd_mcause,
  input priv_upd_mtval_we,
  input [31:0] priv_upd_mtval,
  input priv_upd_sepc_we,
  input [31:0] priv_upd_sepc,
  input priv_upd_scause_we,
  input [31:0] priv_upd_scause,
  input priv_upd_stval_we,
  input [31:0] priv_upd_stval,

  output [1:0] priv_o,
  output [31:0] mstatus_o,
  output [31:0] mtvec_o,
  output [31:0] stvec_o,
  output [31:0] mepc_o,
  output [31:0] sepc_o,
  output [31:0] mcause_o,
  output [31:0] scause_o,
  output [31:0] medeleg_o,
  output [31:0] mideleg_o,
  output [31:0] mie_o,
  output [31:0] mip_o,
  output [31:0] mcounteren_o,
  output [31:0] scounteren_o,
  output [31:0] satp_o
);
  // wen[1] for wdata enable, wen[0]=0 for waddr1 only, wen[0]=1 for waddr1&waddr2.
  reg [31:0] csr [127:0];
  reg [1:0] priv_r;
  reg [63:0] mcycle_r;
  reg [63:0] minstret_r;

  localparam [6:0] IDX_MSTATUS = 7'd0;
  localparam [6:0] IDX_MISA = 7'd1;
  localparam [6:0] IDX_MEDELEG = 7'd2;
  localparam [6:0] IDX_MIDELEG = 7'd3;
  localparam [6:0] IDX_MIE = 7'd4;
  localparam [6:0] IDX_MTVEC = 7'd5;
  localparam [6:0] IDX_MCOUNTEREN = 7'd6;
  localparam [6:0] IDX_MSTATUSH = 7'd7;
  localparam [6:0] IDX_MCOUNTINHIBIT = 7'd9;
  localparam [6:0] IDX_MSCRATCH = 7'd10;
  localparam [6:0] IDX_MEPC = 7'd11;
  localparam [6:0] IDX_MCAUSE = 7'd12;
  localparam [6:0] IDX_MTVAL = 7'd13;
  localparam [6:0] IDX_MIP = 7'd14;
  localparam [6:0] IDX_SCOUNTEREN = 7'd19;
  localparam [6:0] IDX_STVEC = 7'd18;
  localparam [6:0] IDX_SEPC = 7'd22;
  localparam [6:0] IDX_SCAUSE = 7'd23;
  localparam [6:0] IDX_STVAL = 7'd24;
  localparam [6:0] IDX_SATP = 7'd26;
  localparam [6:0] IDX_MNSTATUS = 7'd33;
  localparam [6:0] IDX_TSELECT = 7'd34;
  localparam [6:0] IDX_TDATA1 = 7'd35;
  localparam [6:0] IDX_TDATA2 = 7'd36;
  localparam [6:0] IDX_TDATA3 = 7'd37;
  localparam [6:0] IDX_TINFO = 7'd38;
  localparam [6:0] IDX_TCONTROL = 7'd39;
  localparam [6:0] IDX_MCONTEXT = 7'd40;
  localparam [6:0] IDX_SCOUNTOVF = 7'd41;
  localparam [6:0] IDX_MVENDORID = 7'd42;
  localparam [6:0] IDX_MARCHID = 7'd43;
  localparam [6:0] IDX_MIMPID = 7'd44;
  localparam [6:0] IDX_MHARTID = 7'd45;
  localparam [6:0] IDX_MCYCLECFG = 7'd66;
  localparam [6:0] IDX_MINSTRETCFG = 7'd67;
  localparam [6:0] IDX_MCYCLECFGH = 7'd68;
  localparam [6:0] IDX_MINSTRETCFGH = 7'd69;
  localparam [6:0] IDX_MHPMEVENT3 = 7'd70;
  localparam [6:0] IDX_MHPMEVENT3H = 7'd99;

  localparam [31:0] MISA_RESET = 32'h40141101;
  localparam [31:0] MSTATUS_RESET = 32'h00001800;
  localparam [31:0] MARCHID_RESET = 32'd5;
  localparam [31:0] SSTATUS_MASK = 32'h800de162;
  localparam [31:0] MSTATUS_WMASK = 32'h007e79bb;
  localparam [31:0] SIE_MASK = 32'h00000222;
  localparam [31:0] SIP_MASK = 32'h00000222;
  localparam [31:0] MIP_TIMER_MASK = 32'h00000080;
  localparam [31:0] MIDELEG_MASK = 32'h00000222;
  localparam [31:0] MEDELEG_MASK = 32'h0000b1fb;
  localparam [31:0] MCOUNTINHIBIT_MASK = 32'h00000007;
  localparam [31:0] COUNTEREN_MASK = 32'h00000007;

  function csr_pmp_hardwired_zero;
    input [11:0] csr_addr;
    begin
      csr_pmp_hardwired_zero =
        ((csr_addr >= 12'h3a4) && (csr_addr <= 12'h3af)) ||
        ((csr_addr >= 12'h3c0) && (csr_addr <= 12'h3ef));
    end
  endfunction

  function csr_hpm_hardwired_zero;
    input [11:0] csr_addr;
    begin
      csr_hpm_hardwired_zero =
        ((csr_addr >= 12'hb03) && (csr_addr <= 12'hb1f)) ||
        ((csr_addr >= 12'hb83) && (csr_addr <= 12'hb9f)) ||
        ((csr_addr >= 12'hc03) && (csr_addr <= 12'hc1f)) ||
        ((csr_addr >= 12'hc83) && (csr_addr <= 12'hc9f));
    end
  endfunction

  // 对齐 NEMU 当前已建模 CSR 集合（reg.h: csr_ptr_or_null）:
  // 常规 CSR + pmpcfg0..3 + pmpaddr0..15 + debug trigger CSR + ID CSR.
  function [6:0] csr_addr_to_idx;
    input [11:0] csr_addr;
    begin
      if (csr_addr >= 12'h3a0 && csr_addr <= 12'h3a3) begin
        csr_addr_to_idx = 7'd46 + {5'b0, csr_addr[1:0]};  // pmpcfg0..3
      end else if (csr_addr >= 12'h3b0 && csr_addr <= 12'h3bf) begin
        csr_addr_to_idx = 7'd50 + {3'b0, csr_addr[3:0]};  // pmpaddr0..15
      end else begin
        case (csr_addr)
          12'h300: csr_addr_to_idx = 7'd0;   // mstatus
          12'h301: csr_addr_to_idx = 7'd1;   // misa
          12'h302: csr_addr_to_idx = 7'd2;   // medeleg
          12'h303: csr_addr_to_idx = 7'd3;   // mideleg
          12'h304: csr_addr_to_idx = 7'd4;   // mie
          12'h305: csr_addr_to_idx = 7'd5;   // mtvec
          12'h306: csr_addr_to_idx = 7'd6;   // mcounteren
          12'h310: csr_addr_to_idx = 7'd7;   // mstatush
          12'h31a: csr_addr_to_idx = 7'd8;   // menvcfgh
          12'h320: csr_addr_to_idx = 7'd9;   // mcountinhibit
          12'h321: csr_addr_to_idx = IDX_MCYCLECFG;     // mcyclecfg
          12'h322: csr_addr_to_idx = IDX_MINSTRETCFG;   // minstretcfg
          12'h323: csr_addr_to_idx = IDX_MHPMEVENT3;    // mhpmevent3
          12'h324: csr_addr_to_idx = 7'd71;  // mhpmevent4
          12'h325: csr_addr_to_idx = 7'd72;  // mhpmevent5
          12'h326: csr_addr_to_idx = 7'd73;  // mhpmevent6
          12'h327: csr_addr_to_idx = 7'd74;  // mhpmevent7
          12'h328: csr_addr_to_idx = 7'd75;  // mhpmevent8
          12'h329: csr_addr_to_idx = 7'd76;  // mhpmevent9
          12'h32a: csr_addr_to_idx = 7'd77;  // mhpmevent10
          12'h32b: csr_addr_to_idx = 7'd78;  // mhpmevent11
          12'h32c: csr_addr_to_idx = 7'd79;  // mhpmevent12
          12'h32d: csr_addr_to_idx = 7'd80;  // mhpmevent13
          12'h32e: csr_addr_to_idx = 7'd81;  // mhpmevent14
          12'h32f: csr_addr_to_idx = 7'd82;  // mhpmevent15
          12'h330: csr_addr_to_idx = 7'd83;  // mhpmevent16
          12'h331: csr_addr_to_idx = 7'd84;  // mhpmevent17
          12'h332: csr_addr_to_idx = 7'd85;  // mhpmevent18
          12'h333: csr_addr_to_idx = 7'd86;  // mhpmevent19
          12'h334: csr_addr_to_idx = 7'd87;  // mhpmevent20
          12'h335: csr_addr_to_idx = 7'd88;  // mhpmevent21
          12'h336: csr_addr_to_idx = 7'd89;  // mhpmevent22
          12'h337: csr_addr_to_idx = 7'd90;  // mhpmevent23
          12'h338: csr_addr_to_idx = 7'd91;  // mhpmevent24
          12'h339: csr_addr_to_idx = 7'd92;  // mhpmevent25
          12'h33a: csr_addr_to_idx = 7'd93;  // mhpmevent26
          12'h33b: csr_addr_to_idx = 7'd94;  // mhpmevent27
          12'h33c: csr_addr_to_idx = 7'd95;  // mhpmevent28
          12'h33d: csr_addr_to_idx = 7'd96;  // mhpmevent29
          12'h33e: csr_addr_to_idx = 7'd97;  // mhpmevent30
          12'h33f: csr_addr_to_idx = 7'd98;  // mhpmevent31
          12'h340: csr_addr_to_idx = 7'd10;  // mscratch
          12'h341: csr_addr_to_idx = 7'd11;  // mepc
          12'h342: csr_addr_to_idx = 7'd12;  // mcause
          12'h343: csr_addr_to_idx = 7'd13;  // mtval
          12'h344: csr_addr_to_idx = 7'd14;  // mip
          12'h30a: csr_addr_to_idx = 7'd15;  // menvcfg

          12'h100: csr_addr_to_idx = 7'd16;  // sstatus
          12'h104: csr_addr_to_idx = 7'd17;  // sie
          12'h105: csr_addr_to_idx = 7'd18;  // stvec
          12'h106: csr_addr_to_idx = 7'd19;  // scounteren
          12'h10a: csr_addr_to_idx = 7'd20;  // senvcfg
          12'h140: csr_addr_to_idx = 7'd21;  // sscratch
          12'h141: csr_addr_to_idx = 7'd22;  // sepc
          12'h142: csr_addr_to_idx = 7'd23;  // scause
          12'h143: csr_addr_to_idx = 7'd24;  // stval
          12'h144: csr_addr_to_idx = 7'd25;  // sip
          12'h180: csr_addr_to_idx = 7'd26;  // satp

          12'hb00: csr_addr_to_idx = 7'd27;  // cycle
          12'hc00: csr_addr_to_idx = 7'd27;  // cycle
          12'hb80: csr_addr_to_idx = 7'd28;  // cycleh
          12'hc80: csr_addr_to_idx = 7'd28;  // cycleh
          12'hc01: csr_addr_to_idx = 7'd29;  // time
          12'hc81: csr_addr_to_idx = 7'd30;  // timeh
          12'hb02: csr_addr_to_idx = 7'd31;  // instret
          12'hc02: csr_addr_to_idx = 7'd31;  // instret
          12'hb82: csr_addr_to_idx = 7'd32;  // instreth
          12'hc82: csr_addr_to_idx = 7'd32;  // instreth
          12'h721: csr_addr_to_idx = IDX_MCYCLECFGH;    // mcyclecfgh
          12'h722: csr_addr_to_idx = IDX_MINSTRETCFGH;  // minstretcfgh
          12'h723: csr_addr_to_idx = IDX_MHPMEVENT3H;   // mhpmevent3h
          12'h724: csr_addr_to_idx = 7'd100; // mhpmevent4h
          12'h725: csr_addr_to_idx = 7'd101; // mhpmevent5h
          12'h726: csr_addr_to_idx = 7'd102; // mhpmevent6h
          12'h727: csr_addr_to_idx = 7'd103; // mhpmevent7h
          12'h728: csr_addr_to_idx = 7'd104; // mhpmevent8h
          12'h729: csr_addr_to_idx = 7'd105; // mhpmevent9h
          12'h72a: csr_addr_to_idx = 7'd106; // mhpmevent10h
          12'h72b: csr_addr_to_idx = 7'd107; // mhpmevent11h
          12'h72c: csr_addr_to_idx = 7'd108; // mhpmevent12h
          12'h72d: csr_addr_to_idx = 7'd109; // mhpmevent13h
          12'h72e: csr_addr_to_idx = 7'd110; // mhpmevent14h
          12'h72f: csr_addr_to_idx = 7'd111; // mhpmevent15h
          12'h730: csr_addr_to_idx = 7'd112; // mhpmevent16h
          12'h731: csr_addr_to_idx = 7'd113; // mhpmevent17h
          12'h732: csr_addr_to_idx = 7'd114; // mhpmevent18h
          12'h733: csr_addr_to_idx = 7'd115; // mhpmevent19h
          12'h734: csr_addr_to_idx = 7'd116; // mhpmevent20h
          12'h735: csr_addr_to_idx = 7'd117; // mhpmevent21h
          12'h736: csr_addr_to_idx = 7'd118; // mhpmevent22h
          12'h737: csr_addr_to_idx = 7'd119; // mhpmevent23h
          12'h738: csr_addr_to_idx = 7'd120; // mhpmevent24h
          12'h739: csr_addr_to_idx = 7'd121; // mhpmevent25h
          12'h73a: csr_addr_to_idx = 7'd122; // mhpmevent26h
          12'h73b: csr_addr_to_idx = 7'd123; // mhpmevent27h
          12'h73c: csr_addr_to_idx = 7'd124; // mhpmevent28h
          12'h73d: csr_addr_to_idx = 7'd125; // mhpmevent29h
          12'h73e: csr_addr_to_idx = 7'd126; // mhpmevent30h
          12'h73f: csr_addr_to_idx = 7'd127; // mhpmevent31h

          12'h744: csr_addr_to_idx = 7'd33;  // mnstatus
          12'h7a0: csr_addr_to_idx = 7'd34;  // tselect
          12'h7a1: csr_addr_to_idx = 7'd35;  // tdata1
          12'h7a2: csr_addr_to_idx = 7'd36;  // tdata2
          12'h7a3: csr_addr_to_idx = 7'd37;  // tdata3
          12'h7a4: csr_addr_to_idx = 7'd38;  // tinfo
          12'h7a5: csr_addr_to_idx = 7'd39;  // tcontrol
          12'h7a8: csr_addr_to_idx = 7'd40;  // mcontext
          12'hda0: csr_addr_to_idx = 7'd41;  // scountovf

          12'hf11: csr_addr_to_idx = 7'd42;  // mvendorid
          12'hf12: csr_addr_to_idx = 7'd43;  // marchid
          12'hf13: csr_addr_to_idx = 7'd44;  // mimpid
          12'hf14: csr_addr_to_idx = 7'd45;  // mhartid
          default: csr_addr_to_idx = 7'd0;
        endcase
      end
    end
  endfunction

  function csr_addr_is_mapped;
    input [11:0] csr_addr;
    begin
      csr_addr_is_mapped =
        (csr_addr == 12'h300) || (csr_addr == 12'h301) || (csr_addr == 12'h302) ||
        (csr_addr == 12'h303) || (csr_addr == 12'h304) || (csr_addr == 12'h305) ||
        (csr_addr == 12'h306) || (csr_addr == 12'h310) || (csr_addr == 12'h31a) ||
        (csr_addr == 12'h320) || (csr_addr == 12'h340) || (csr_addr == 12'h341) ||
        (csr_addr == 12'h342) || (csr_addr == 12'h343) || (csr_addr == 12'h344) ||
        (csr_addr == 12'h30a) ||
        (csr_addr == 12'h100) || (csr_addr == 12'h104) || (csr_addr == 12'h105) ||
        (csr_addr == 12'h106) || (csr_addr == 12'h10a) || (csr_addr == 12'h140) ||
        (csr_addr == 12'h141) || (csr_addr == 12'h142) || (csr_addr == 12'h143) ||
        (csr_addr == 12'h144) || (csr_addr == 12'h180) ||
        (csr_addr == 12'hb00) || (csr_addr == 12'hc00) || (csr_addr == 12'hb80) ||
        (csr_addr == 12'hc80) || (csr_addr == 12'hc01) || (csr_addr == 12'hc81) ||
        (csr_addr == 12'hb02) || (csr_addr == 12'hc02) || (csr_addr == 12'hb82) ||
        (csr_addr == 12'hc82) || (csr_addr == 12'h744) ||
        ((csr_addr >= 12'h321) && (csr_addr <= 12'h322)) ||
        ((csr_addr >= 12'h323) && (csr_addr <= 12'h33f)) ||
        ((csr_addr >= 12'h721) && (csr_addr <= 12'h722)) ||
        ((csr_addr >= 12'h723) && (csr_addr <= 12'h73f)) ||
        (csr_addr == 12'h7a0) || (csr_addr == 12'h7a1) || (csr_addr == 12'h7a2) ||
        (csr_addr == 12'h7a3) || (csr_addr == 12'h7a4) || (csr_addr == 12'h7a5) ||
        (csr_addr == 12'h7a8) ||
        (csr_addr == 12'hf11) || (csr_addr == 12'hf12) || (csr_addr == 12'hf13) ||
        (csr_addr == 12'hf14) ||
        ((csr_addr >= 12'h3a0) && (csr_addr <= 12'h3a3)) ||
        ((csr_addr >= 12'h3a4) && (csr_addr <= 12'h3af)) ||
        ((csr_addr >= 12'h3b0) && (csr_addr <= 12'h3bf)) ||
        ((csr_addr >= 12'h3c0) && (csr_addr <= 12'h3ef)) ||
        ((csr_addr >= 12'hb03) && (csr_addr <= 12'hb1f)) ||
        ((csr_addr >= 12'hb83) && (csr_addr <= 12'hb9f)) ||
        ((csr_addr >= 12'hc03) && (csr_addr <= 12'hc1f)) ||
        ((csr_addr >= 12'hc83) && (csr_addr <= 12'hc9f));
    end
  endfunction

  function csr_is_trigger_csr;
    input [11:0] csr_addr;
    begin
      csr_is_trigger_csr =
        ((csr_addr >= 12'h7a0) && (csr_addr <= 12'h7a5)) ||
        (csr_addr == 12'h7a8);
    end
  endfunction

  function csr_inst_writes;
    input [31:0] inst;
    begin
      if (inst[6:0] != 7'h73) begin
        csr_inst_writes = 1'b0;
      end else begin
        case (inst[14:12])
          3'b001, 3'b101: csr_inst_writes = 1'b1; // csrrw/csrrwi
          3'b010, 3'b011, 3'b110, 3'b111: csr_inst_writes = (inst[19:15] != 5'b00000);
          default: csr_inst_writes = 1'b0;
        endcase
      end
    end
  endfunction

  function [11:0] csr_inst_idx;
    input [31:0] inst;
    begin
      csr_inst_idx = inst[31:20];
    end
  endfunction

  function csr_inst_targets_any;
    input [31:0] inst;
    input [11:0] csr_a;
    input [11:0] csr_b;
    input [11:0] csr_c;
    input [11:0] csr_d;
    begin
      csr_inst_targets_any = csr_inst_writes(inst) &&
        ((csr_inst_idx(inst) == csr_a) || (csr_inst_idx(inst) == csr_b) ||
         (csr_inst_idx(inst) == csr_c) || (csr_inst_idx(inst) == csr_d));
    end
  endfunction

  task automatic apply_csr_write;
    input [11:0] csr_addr;
    input [31:0] csr_val;
    begin
      if (!(TRIGGER_SLOT_ENABLE == 1'b0 && csr_is_trigger_csr(csr_addr))) begin
        if (!csr_pmp_hardwired_zero(csr_addr) && !csr_hpm_hardwired_zero(csr_addr)) begin
          case (csr_addr)
            12'h300: csr[IDX_MSTATUS] <= (csr[IDX_MSTATUS] & ~MSTATUS_WMASK) | (csr_val & MSTATUS_WMASK);
            12'h100: csr[IDX_MSTATUS] <= (csr[IDX_MSTATUS] & ~SSTATUS_MASK) | (csr_val & SSTATUS_MASK);
            12'h104: csr[IDX_MIE] <= (csr[IDX_MIE] & ~SIE_MASK) | (csr_val & SIE_MASK);
            12'h144: csr[IDX_MIP] <= (csr[IDX_MIP] & ~SIP_MASK) | (csr_val & SIP_MASK);
            12'h344: csr[IDX_MIP] <= csr_val & ~MIP_TIMER_MASK;
            12'h302: csr[IDX_MEDELEG] <= csr_val & MEDELEG_MASK;
            12'h303: csr[IDX_MIDELEG] <= csr_val & MIDELEG_MASK;
            12'h306: csr[IDX_MCOUNTEREN] <= csr_val & COUNTEREN_MASK;
            12'h320: csr[IDX_MCOUNTINHIBIT] <= 32'b0;
            12'h106: csr[IDX_SCOUNTEREN] <= csr_val & COUNTEREN_MASK;
            12'h301: csr[IDX_MISA] <= MISA_RESET;
            12'hf11: csr[IDX_MVENDORID] <= 32'b0;
            12'hf12: csr[IDX_MARCHID] <= MARCHID_RESET;
            12'hf13: csr[IDX_MIMPID] <= 32'b0;
            12'hf14: csr[IDX_MHARTID] <= HART_ID[DATA_WIDTH-1:0];
            12'hb00: begin
              mcycle_r[31:0] <= csr_val;
              csr[27] <= csr_val;
            end
            12'hc00: begin
              mcycle_r[31:0] <= csr_val;
              csr[27] <= csr_val;
            end
            12'hb80: begin
              mcycle_r[63:32] <= csr_val;
              csr[28] <= csr_val;
            end
            12'hc80: begin
              mcycle_r[63:32] <= csr_val;
              csr[28] <= csr_val;
            end
            12'hb02: begin
              minstret_r[31:0] <= csr_val;
              csr[31] <= csr_val;
            end
            12'hc02: begin
              minstret_r[31:0] <= csr_val;
              csr[31] <= csr_val;
            end
            12'hb82: begin
              minstret_r[63:32] <= csr_val;
              csr[32] <= csr_val;
            end
            12'hc82: begin
              minstret_r[63:32] <= csr_val;
              csr[32] <= csr_val;
            end
            12'h7a0: if (TRIGGER_SLOT_ENABLE) csr[IDX_TSELECT] <= csr_val & 32'h1;
            12'h7a1: if (TRIGGER_SLOT_ENABLE) csr[IDX_TDATA1] <= csr_val;
            12'h7a2: if (TRIGGER_SLOT_ENABLE) csr[IDX_TDATA2] <= csr_val;
            12'h7a3: if (TRIGGER_SLOT_ENABLE) csr[IDX_TDATA3] <= csr_val;
            12'h7a4: if (TRIGGER_SLOT_ENABLE) csr[IDX_TINFO] <= csr_val;
            12'h7a5: if (TRIGGER_SLOT_ENABLE) csr[IDX_TCONTROL] <= csr_val;
            12'h7a8: if (TRIGGER_SLOT_ENABLE) csr[IDX_MCONTEXT] <= csr_val;
            default: if (csr_addr_is_mapped(csr_addr)) csr[csr_addr_to_idx(csr_addr)] <= csr_val;
          endcase
        end
      end
    end
  endtask

`ifdef NPC_TRIGGER_ENABLE
  localparam TRIGGER_SLOT_ENABLE = 1'b1;
`else
  localparam TRIGGER_SLOT_ENABLE = 1'b0;
`endif

  wire [6:0] raddr1_real = csr_addr_to_idx(raddr1);
  wire [6:0] waddr1_real = csr_addr_to_idx(waddr1);
  wire [6:0] waddr2_real = csr_addr_to_idx(waddr2);

  wire raddr1_valid = csr_addr_is_mapped(raddr1);
  wire waddr1_valid = csr_addr_is_mapped(waddr1);
  wire waddr2_valid = csr_addr_is_mapped(waddr2);
  wire commit_writes_cycle = commit_valid &&
      csr_inst_targets_any(commit_instr, 12'hb00, 12'hb80, 12'hc00, 12'hc80);
  wire commit_writes_instret = commit_valid &&
      csr_inst_targets_any(commit_instr, 12'hb02, 12'hb82, 12'hc02, 12'hc82);
  wire will_inc_cycle = commit_valid && !commit_exception &&
      !commit_writes_cycle && !csr[IDX_MCOUNTINHIBIT][0];
  wire will_inc_instret = commit_valid && !commit_exception &&
      !commit_writes_instret && !csr[IDX_MCOUNTINHIBIT][2];
  wire [63:0] mcycle_visible = mcycle_r + (will_inc_cycle ? 64'd1 : 64'd0);
  wire [63:0] mtime_visible = time_value_i;
  wire [63:0] minstret_visible = minstret_r + (will_inc_instret ? 64'd1 : 64'd0);
  wire [31:0] mip_visible = (csr[IDX_MIP] & ~MIP_TIMER_MASK) |
      (timer_mtip_i ? MIP_TIMER_MASK : 32'b0);

  assign raddr1_illegal = !raddr1_valid;
  assign waddr1_illegal = !waddr1_valid;
  assign waddr2_illegal = !waddr2_valid;

  assign rdata1 = !raddr1_valid ? {DATA_WIDTH{1'b0}} :
                  ((!TRIGGER_SLOT_ENABLE) && csr_is_trigger_csr(raddr1)) ? {DATA_WIDTH{1'b0}} :
                  csr_pmp_hardwired_zero(raddr1) ? {DATA_WIDTH{1'b0}} :
                  csr_hpm_hardwired_zero(raddr1) ? {DATA_WIDTH{1'b0}} :
                  (raddr1 == 12'h100) ? (csr[IDX_MSTATUS] & SSTATUS_MASK) :
                  (raddr1 == 12'h104) ? (csr[IDX_MIE] & SIE_MASK) :
                  (raddr1 == 12'h144) ? (mip_visible & SIP_MASK) :
                  (raddr1 == 12'h344) ? mip_visible :
                  ((raddr1 == 12'hb00) || (raddr1 == 12'hc00)) ? mcycle_visible[31:0] :
                  ((raddr1 == 12'hb80) || (raddr1 == 12'hc80)) ? mcycle_visible[63:32] :
                  (raddr1 == 12'hc01) ? mtime_visible[31:0] :
                  (raddr1 == 12'hc81) ? mtime_visible[63:32] :
                  ((raddr1 == 12'hb02) || (raddr1 == 12'hc02)) ? minstret_visible[31:0] :
                  ((raddr1 == 12'hb82) || (raddr1 == 12'hc82)) ? minstret_visible[63:32] :
                  (raddr1 == 12'h320) ? 32'b0 :
                  (raddr1 == 12'h301) ? MISA_RESET :
                  (raddr1 == 12'hf11) ? 32'b0 :
                  (raddr1 == 12'hf12) ? MARCHID_RESET :
                  (raddr1 == 12'hf13) ? 32'b0 :
                  (raddr1 == 12'hf14) ? HART_ID[DATA_WIDTH-1:0] :
                  csr[raddr1_real];

  assign priv_o = priv_r;
  assign mstatus_o = csr[IDX_MSTATUS];
  assign mtvec_o = csr[IDX_MTVEC];
  assign stvec_o = csr[IDX_STVEC];
  assign mepc_o = csr[IDX_MEPC];
  assign sepc_o = csr[IDX_SEPC];
  assign mcause_o = csr[IDX_MCAUSE];
  assign scause_o = csr[IDX_SCAUSE];
  assign medeleg_o = csr[IDX_MEDELEG];
  assign mideleg_o = csr[IDX_MIDELEG];
  assign mie_o = csr[IDX_MIE];
  assign mip_o = mip_visible;
  assign mcounteren_o = csr[IDX_MCOUNTEREN];
  assign scounteren_o = csr[IDX_SCOUNTEREN];
  assign satp_o = csr[IDX_SATP];

  always @(posedge clk) begin
    if (!rst_n) begin : reset_csr
      integer i;
      for (i = 0; i < 128; i = i + 1) begin
        csr[i] = {DATA_WIDTH{1'b0}};
      end
      csr[IDX_MSTATUS] <= MSTATUS_RESET;
      csr[IDX_MISA] <= MISA_RESET;
      csr[IDX_MARCHID] <= MARCHID_RESET;
      csr[IDX_MHARTID] <= HART_ID[DATA_WIDTH-1:0];
      mcycle_r <= 64'b0;
      minstret_r <= 64'b0;
      priv_r <= 2'b11; // M-mode
    end else begin
      if (will_inc_cycle) begin
        mcycle_r <= mcycle_r + 64'd1;
        csr[27] <= mcycle_visible[31:0];
        csr[28] <= mcycle_visible[63:32];
      end
      if (will_inc_instret) begin
        minstret_r <= minstret_r + 64'd1;
        csr[31] <= minstret_visible[31:0];
        csr[32] <= minstret_visible[63:32];
      end

      if (priv_upd_we) begin
        if (priv_upd_mstatus_we) csr[IDX_MSTATUS] <= priv_upd_mstatus;
        if (priv_upd_mepc_we) csr[IDX_MEPC] <= priv_upd_mepc;
        if (priv_upd_mcause_we) csr[IDX_MCAUSE] <= priv_upd_mcause;
        if (priv_upd_mtval_we) csr[IDX_MTVAL] <= priv_upd_mtval;
        if (priv_upd_sepc_we) csr[IDX_SEPC] <= priv_upd_sepc;
        if (priv_upd_scause_we) csr[IDX_SCAUSE] <= priv_upd_scause;
        if (priv_upd_stval_we) csr[IDX_STVAL] <= priv_upd_stval;
        if (priv_upd_priv_we) priv_r <= priv_upd_priv;
      end else if (wen[1]) begin
        apply_csr_write(waddr1, wdata1);
        if (wen[0]) begin
          apply_csr_write(waddr2, wdata2);
        end
      end
    end
  end
endmodule
