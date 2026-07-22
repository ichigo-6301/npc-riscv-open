`timescale 1ns / 1ps
module CsrRegisterFile #(ADDR_WIDTH = 1, DATA_WIDTH = 1) (
  input clk,
  input rst_n,
  input [ADDR_WIDTH-1:0] raddr1,
  output [DATA_WIDTH-1:0] rdata1,
  input [DATA_WIDTH-1:0] wdata1,
  input [ADDR_WIDTH-1:0] waddr1,
  input [DATA_WIDTH-1:0] wdata2,
  input [ADDR_WIDTH-1:0] waddr2,
  input [DATA_WIDTH-1:0] wdata3,
  input [ADDR_WIDTH-1:0] waddr3,
  input wen3,
  input interrupt_trap_valid,
  input [DATA_WIDTH-1:0] interrupt_trap_cause,
  input [DATA_WIDTH-1:0] interrupt_trap_epc,
  input [1:0] wen,
  output [1:0] priv,
  output [DATA_WIDTH-1:0] mstatus_value,
  output [DATA_WIDTH-1:0] mtvec_value,
  output [DATA_WIDTH-1:0] mie_value,
  output [DATA_WIDTH-1:0] mip_value,
  output [DATA_WIDTH-1:0] mideleg_value
);
  // wen[1] for wd enable, wen[0] = 1'b0 for waddr1 enable, wen[0] = 1'b1 for waddr1 && waddr2 enable
  localparam integer CSR_COUNT = 17;

  localparam [4:0] CSR_IDX_MSTATUS  = 5'd0;
  localparam [4:0] CSR_IDX_MTVEC    = 5'd1;
  localparam [4:0] CSR_IDX_MEPC     = 5'd2;
  localparam [4:0] CSR_IDX_MCAUSE   = 5'd3;
  localparam [4:0] CSR_IDX_MTVAL    = 5'd4;
  localparam [4:0] CSR_IDX_MSCRATCH = 5'd5;
  localparam [4:0] CSR_IDX_MIE      = 5'd6;
  localparam [4:0] CSR_IDX_MIP      = 5'd7;
  localparam [4:0] CSR_IDX_MEDELEG  = 5'd8;
  localparam [4:0] CSR_IDX_MIDELEG  = 5'd9;
  localparam [4:0] CSR_IDX_SATP     = 5'd10;
  localparam [4:0] CSR_IDX_PMPCFG0  = 5'd11;
  localparam [4:0] CSR_IDX_PMPADDR0 = 5'd12;
  localparam [4:0] CSR_IDX_MNSTATUS = 5'd13;
  localparam [4:0] CSR_IDX_MCOUNTEREN = 5'd14;
  localparam [4:0] CSR_IDX_SCOUNTEREN = 5'd15;
  localparam [4:0] CSR_IDX_SEPC = 5'd16;
  localparam [1:0] PRIV_U = 2'b00;
  localparam [1:0] PRIV_S = 2'b01;
  localparam [1:0] PRIV_M = 2'b11;
  localparam [DATA_WIDTH-1:0] SSTATUS_MASK = 32'h800de162;

  reg [DATA_WIDTH-1:0] csr [0:CSR_COUNT-1];
  reg [1:0] priv_r;

  function [4:0] csr_addr_to_idx;
      input [ADDR_WIDTH-1:0] csr_addr;
      begin
          case (csr_addr)
              12'h300: csr_addr_to_idx = CSR_IDX_MSTATUS;
              12'h100: csr_addr_to_idx = CSR_IDX_MSTATUS;
              12'h305: csr_addr_to_idx = CSR_IDX_MTVEC;
              12'h341: csr_addr_to_idx = CSR_IDX_MEPC;
              12'h141: csr_addr_to_idx = CSR_IDX_SEPC;
              12'h342: csr_addr_to_idx = CSR_IDX_MCAUSE;
              12'h343: csr_addr_to_idx = CSR_IDX_MTVAL;
              12'h340: csr_addr_to_idx = CSR_IDX_MSCRATCH;
              12'h304: csr_addr_to_idx = CSR_IDX_MIE;
              12'h344: csr_addr_to_idx = CSR_IDX_MIP;
              12'h302: csr_addr_to_idx = CSR_IDX_MEDELEG;
              12'h303: csr_addr_to_idx = CSR_IDX_MIDELEG;
              12'h180: csr_addr_to_idx = CSR_IDX_SATP;
              12'h3a0: csr_addr_to_idx = CSR_IDX_PMPCFG0;
              12'h3b0: csr_addr_to_idx = CSR_IDX_PMPADDR0;
              12'h744: csr_addr_to_idx = CSR_IDX_MNSTATUS;
              12'h306: csr_addr_to_idx = CSR_IDX_MCOUNTEREN;
              12'h106: csr_addr_to_idx = CSR_IDX_SCOUNTEREN;
              default: csr_addr_to_idx = CSR_IDX_MSTATUS;
          endcase
      end
  endfunction

  function csr_addr_is_writable;
      input [ADDR_WIDTH-1:0] csr_addr;
      begin
          csr_addr_is_writable =
              (csr_addr == 12'h300) ||
              (csr_addr == 12'h100) ||
              (csr_addr == 12'h305) ||
              (csr_addr == 12'h341) ||
              (csr_addr == 12'h141) ||
              (csr_addr == 12'h342) ||
              (csr_addr == 12'h343) ||
              (csr_addr == 12'h340) ||
              (csr_addr == 12'h304) ||
              (csr_addr == 12'h344) ||
              (csr_addr == 12'h302) ||
              (csr_addr == 12'h303) ||
              (csr_addr == 12'h180) ||
              (csr_addr == 12'h3a0) ||
              (csr_addr == 12'h3b0) ||
              (csr_addr == 12'h744) ||
              (csr_addr == 12'h306) ||
              (csr_addr == 12'h106);
      end
  endfunction

  function csr_addr_is_write_ignored;
      input [ADDR_WIDTH-1:0] csr_addr;
      begin
          csr_addr_is_write_ignored =
              (csr_addr == 12'h301) ||
              (csr_addr == 12'h320) ||
              (csr_addr == 12'hb00) ||
              (csr_addr == 12'hb80) ||
              (csr_addr == 12'hb02) ||
              (csr_addr == 12'hb82) ||
              (csr_addr == 12'h7a0) ||
              (csr_addr == 12'h7a1) ||
              (csr_addr == 12'h7a2) ||
              (csr_addr == 12'h7a3) ||
              (csr_addr == 12'h7a4) ||
              (csr_addr == 12'h7a5);
      end
  endfunction

  function [DATA_WIDTH-1:0] csr_read_const;
      input [ADDR_WIDTH-1:0] csr_addr;
      begin
          case (csr_addr)
              12'h301: csr_read_const = 32'h40141101;
              12'hf11: csr_read_const = {DATA_WIDTH{1'b0}};
              12'hf12: csr_read_const = 32'h00000005;
              12'hf13: csr_read_const = {DATA_WIDTH{1'b0}};
              12'hf14: csr_read_const = {DATA_WIDTH{1'b0}};
              12'h320: csr_read_const = {DATA_WIDTH{1'b0}};
              12'hb00: csr_read_const = {DATA_WIDTH{1'b0}};
              12'hb80: csr_read_const = {DATA_WIDTH{1'b0}};
              12'hb02: csr_read_const = {DATA_WIDTH{1'b0}};
              12'hb82: csr_read_const = {DATA_WIDTH{1'b0}};
              12'hc00: csr_read_const = {DATA_WIDTH{1'b0}};
              12'hc01: csr_read_const = {DATA_WIDTH{1'b0}};
              12'hc02: csr_read_const = {DATA_WIDTH{1'b0}};
              12'hc80: csr_read_const = {DATA_WIDTH{1'b0}};
              12'hc81: csr_read_const = {DATA_WIDTH{1'b0}};
              12'hc82: csr_read_const = {DATA_WIDTH{1'b0}};
              12'h7a0: csr_read_const = {DATA_WIDTH{1'b0}};
              12'h7a1: csr_read_const = {DATA_WIDTH{1'b0}};
              12'h7a2: csr_read_const = {DATA_WIDTH{1'b0}};
              12'h7a3: csr_read_const = {DATA_WIDTH{1'b0}};
              12'h7a4: csr_read_const = {DATA_WIDTH{1'b0}};
              12'h7a5: csr_read_const = {DATA_WIDTH{1'b0}};
              default: csr_read_const = {DATA_WIDTH{1'b0}};
          endcase
      end
  endfunction

  function [DATA_WIDTH-1:0] csr_read_writable;
      input [ADDR_WIDTH-1:0] csr_addr;
      begin
          case (csr_addr)
              12'h100: csr_read_writable = csr[CSR_IDX_MSTATUS] & SSTATUS_MASK;
              default: csr_read_writable = csr[csr_addr_to_idx(csr_addr)];
          endcase
      end
  endfunction

  function [DATA_WIDTH-1:0] csr_write_mask;
      input [ADDR_WIDTH-1:0] csr_addr;
      begin
          case (csr_addr)
              12'h100: csr_write_mask = SSTATUS_MASK;
              default: csr_write_mask = {DATA_WIDTH{1'b1}};
          endcase
      end
  endfunction

  function [DATA_WIDTH-1:0] csr_write_next;
      input [DATA_WIDTH-1:0] old_value;
      input [ADDR_WIDTH-1:0] csr_addr;
      input [DATA_WIDTH-1:0] csr_wdata;
      reg [DATA_WIDTH-1:0] mask;
      begin
          mask = csr_write_mask(csr_addr);
          csr_write_next = (old_value & ~mask) | (csr_wdata & mask);
      end
  endfunction

  function [DATA_WIDTH-1:0] trap_mstatus_next;
      input [DATA_WIDTH-1:0] old_mstatus;
      input [1:0] prev_priv;
      begin
          trap_mstatus_next =
              (old_mstatus & ~(32'h00001888)) |
              ({30'b0, prev_priv} << 11) |
              ({31'b0, old_mstatus[3]} << 7);
      end
  endfunction

  function [DATA_WIDTH-1:0] mret_mstatus_next;
      input [DATA_WIDTH-1:0] old_mstatus;
      reg [DATA_WIDTH-1:0] next_status;
      begin
          next_status = (old_mstatus & ~(32'h00000008)) |
              ({31'b0, old_mstatus[7]} << 3);
          next_status = next_status | 32'h00000080;
          next_status = next_status & ~(32'h00001800);
          if (old_mstatus[12:11] != PRIV_M) begin
              next_status = next_status & ~(32'h00020000);
          end
          mret_mstatus_next = next_status;
      end
  endfunction

  function [DATA_WIDTH-1:0] sret_mstatus_next;
      input [DATA_WIDTH-1:0] old_mstatus;
      reg [DATA_WIDTH-1:0] next_status;
      begin
          next_status = (old_mstatus & ~(32'h00000002)) |
              ({31'b0, old_mstatus[5]} << 1);
          next_status = next_status | 32'h00000020;
          next_status = next_status & ~(32'h00000100);
          next_status = next_status & ~(32'h00020000);
          sret_mstatus_next = next_status;
      end
  endfunction

  wire [4:0] raddr1_real = csr_addr_to_idx(raddr1);
  wire [4:0] waddr1_real = csr_addr_to_idx(waddr1);
  wire [4:0] waddr2_real = csr_addr_to_idx(waddr2);
  wire [4:0] waddr3_real = csr_addr_to_idx(waddr3);
  wire raddr1_writable = csr_addr_is_writable(raddr1);
  wire waddr1_writable = csr_addr_is_writable(waddr1);
  wire waddr2_writable = csr_addr_is_writable(waddr2);
  wire waddr3_writable = csr_addr_is_writable(waddr3);
  wire exception_trap_write = wen[1] && wen[0] && (waddr1 == 12'h342) && (waddr2 == 12'h341);
  wire ecall_trap_write = exception_trap_write && (wdata1 == 32'd11);
  wire mret_status_write = wen[1] && !wen[0] && (waddr1 == 12'h300) &&
      (waddr2 == 12'h302) && (wdata1 == 32'h00000080);
  wire sret_status_write = wen[1] && !wen[0] && (waddr1 == 12'h300) &&
      (waddr2 == 12'h102) && (wdata1 == 32'h00000020);
  wire [DATA_WIDTH-1:0] ecall_cause =
      (priv_r == PRIV_U) ? {{(DATA_WIDTH-4){1'b0}}, 4'd8} :
      (priv_r == PRIV_S) ? {{(DATA_WIDTH-4){1'b0}}, 4'd9} :
      {{(DATA_WIDTH-4){1'b0}}, 4'd11};
  wire [DATA_WIDTH-1:0] wdata1_eff = ecall_trap_write ? ecall_cause : wdata1;
  wire normal_wen1 = wen[1] && waddr1_writable;
  wire normal_wen2 = wen[1] && wen[0] && waddr2_writable;
  wire normal_wen3 = wen[1] && wen3 && waddr3_writable;
  wire [DATA_WIDTH-1:0] normal_mstatus_next =
      (normal_wen3 && (waddr3 == 12'h300)) ? wdata3 :
      (normal_wen2 && (waddr2 == 12'h300)) ? wdata2 :
      (normal_wen1 && (waddr1 == 12'h300)) ? wdata1_eff :
      csr[CSR_IDX_MSTATUS];
  wire [1:0] mret_priv_next =
      (csr[CSR_IDX_MSTATUS][12:11] == PRIV_M) ? PRIV_M :
      (csr[CSR_IDX_MSTATUS][12:11] == PRIV_S) ? PRIV_S :
      PRIV_U;
  wire [1:0] sret_priv_next = csr[CSR_IDX_MSTATUS][8] ? PRIV_S : PRIV_U;
  wire [DATA_WIDTH-1:0] interrupt_mstatus_next =
      trap_mstatus_next(normal_mstatus_next, priv_r);

  assign priv = priv_r;
  assign mstatus_value = csr[CSR_IDX_MSTATUS];
  assign mtvec_value = csr[CSR_IDX_MTVEC];
  assign mie_value = csr[CSR_IDX_MIE];
  assign mip_value = csr[CSR_IDX_MIP];
  assign mideleg_value = csr[CSR_IDX_MIDELEG];
  assign rdata1 = raddr1_writable ? csr_read_writable(raddr1) : csr_read_const(raddr1);
  always @(posedge clk) begin
    if (!rst_n) begin : reset_csr
      integer i;
        for (i = 0; i < CSR_COUNT; i = i + 1) begin
            csr[i] <= {DATA_WIDTH{1'b0}};
        end
        csr[CSR_IDX_MSTATUS] <= 32'h1800;
        priv_r <= PRIV_M;
    end
    // else if (wen && waddr != {ADDR_WIDTH{1'b0}}) rf[waddr] <= wdata; //禁止写入寄存器0
    else begin
        if(wen[1]) begin
            if(exception_trap_write) begin
                priv_r <= PRIV_M;
            end else if(mret_status_write) begin
                priv_r <= mret_priv_next;
            end else if(sret_status_write) begin
                priv_r <= sret_priv_next;
            end
            if(waddr1_writable) begin
                csr[waddr1_real] <=
                    mret_status_write ? mret_mstatus_next(csr[CSR_IDX_MSTATUS]) :
                    sret_status_write ? sret_mstatus_next(csr[CSR_IDX_MSTATUS]) :
                    csr_write_next(csr[waddr1_real], waddr1, wdata1_eff);
            end
            // print_csr({20'b0, waddr1}, wdata1);
            if(wen[0] && waddr2_writable) begin
                csr[waddr2_real] <= csr_write_next(csr[waddr2_real], waddr2, wdata2);
            end
            if(wen3 && waddr3_writable) begin
                csr[waddr3_real] <= csr_write_next(csr[waddr3_real], waddr3, wdata3);
            end
            if(exception_trap_write) begin
                csr[CSR_IDX_MSTATUS] <= trap_mstatus_next(csr[CSR_IDX_MSTATUS], priv_r);
            end
        end
        if(interrupt_trap_valid) begin
            priv_r <= PRIV_M;
            csr[CSR_IDX_MSTATUS] <= interrupt_mstatus_next;
            csr[CSR_IDX_MCAUSE] <= interrupt_trap_cause;
            csr[CSR_IDX_MEPC] <= interrupt_trap_epc;
            csr[CSR_IDX_MTVAL] <= {DATA_WIDTH{1'b0}};
        end
    end
  end
endmodule
