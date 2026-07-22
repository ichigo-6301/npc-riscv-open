// `timescale 1ns / 1ps
// module CsrRegisterFile #(ADDR_WIDTH = 1, DATA_WIDTH = 1, HART_ID = 32'd0) (
//   input clk,
//   input rst_n,
//   input [ADDR_WIDTH-1:0] raddr1,
//   output [DATA_WIDTH-1:0] rdata1,
//   output raddr1_illegal,
//   input [DATA_WIDTH-1:0] wdata1,
//   input [ADDR_WIDTH-1:0] waddr1,
//   output waddr1_illegal,
//   input [DATA_WIDTH-1:0] wdata2,
//   input [ADDR_WIDTH-1:0] waddr2,
//   output waddr2_illegal,
//   input [1:0] wen
// );
//   // wen[1] for wdata enable, wen[0]=0 for waddr1 only, wen[0]=1 for waddr1&waddr2.
//   reg [31:0] csr [65:0];

//   // 对齐 NEMU 当前已建模 CSR 集合（reg.h: csr_ptr_or_null）:
//   // 常规 CSR + pmpcfg0..3 + pmpaddr0..15 + debug trigger CSR + ID CSR.
//   function [6:0] csr_addr_to_idx;
//     input [11:0] csr_addr;
//     begin
//       if (csr_addr >= 12'h3a0 && csr_addr <= 12'h3a3) begin
//         csr_addr_to_idx = 7'd46 + {5'b0, csr_addr[1:0]};  // pmpcfg0..3
//       end else if (csr_addr >= 12'h3b0 && csr_addr <= 12'h3bf) begin
//         csr_addr_to_idx = 7'd50 + {3'b0, csr_addr[3:0]};  // pmpaddr0..15
//       end else begin
//         case (csr_addr)
//           12'h300: csr_addr_to_idx = 7'd0;   // mstatus
//           12'h301: csr_addr_to_idx = 7'd1;   // misa
//           12'h302: csr_addr_to_idx = 7'd2;   // medeleg
//           12'h303: csr_addr_to_idx = 7'd3;   // mideleg
//           12'h304: csr_addr_to_idx = 7'd4;   // mie
//           12'h305: csr_addr_to_idx = 7'd5;   // mtvec
//           12'h306: csr_addr_to_idx = 7'd6;   // mcounteren
//           12'h310: csr_addr_to_idx = 7'd7;   // mstatush
//           12'h31a: csr_addr_to_idx = 7'd8;   // menvcfgh
//           12'h320: csr_addr_to_idx = 7'd9;   // mcountinhibit
//           12'h340: csr_addr_to_idx = 7'd10;  // mscratch
//           12'h341: csr_addr_to_idx = 7'd11;  // mepc
//           12'h342: csr_addr_to_idx = 7'd12;  // mcause
//           12'h343: csr_addr_to_idx = 7'd13;  // mtval
//           12'h344: csr_addr_to_idx = 7'd14;  // mip
//           12'h30a: csr_addr_to_idx = 7'd15;  // menvcfg

//           12'h100: csr_addr_to_idx = 7'd16;  // sstatus
//           12'h104: csr_addr_to_idx = 7'd17;  // sie
//           12'h105: csr_addr_to_idx = 7'd18;  // stvec
//           12'h106: csr_addr_to_idx = 7'd19;  // scounteren
//           12'h10a: csr_addr_to_idx = 7'd20;  // senvcfg
//           12'h140: csr_addr_to_idx = 7'd21;  // sscratch
//           12'h141: csr_addr_to_idx = 7'd22;  // sepc
//           12'h142: csr_addr_to_idx = 7'd23;  // scause
//           12'h143: csr_addr_to_idx = 7'd24;  // stval
//           12'h144: csr_addr_to_idx = 7'd25;  // sip
//           12'h180: csr_addr_to_idx = 7'd26;  // satp

//           12'hb00: csr_addr_to_idx = 7'd27;  // cycle
//           12'hc00: csr_addr_to_idx = 7'd27;  // cycle
//           12'hb80: csr_addr_to_idx = 7'd28;  // cycleh
//           12'hc80: csr_addr_to_idx = 7'd28;  // cycleh
//           12'hc01: csr_addr_to_idx = 7'd29;  // time
//           12'hc81: csr_addr_to_idx = 7'd30;  // timeh
//           12'hb02: csr_addr_to_idx = 7'd31;  // instret
//           12'hc02: csr_addr_to_idx = 7'd31;  // instret
//           12'hb82: csr_addr_to_idx = 7'd32;  // instreth
//           12'hc82: csr_addr_to_idx = 7'd32;  // instreth

//           12'h744: csr_addr_to_idx = 7'd33;  // mnstatus
//           12'h7a0: csr_addr_to_idx = 7'd34;  // tselect
//           12'h7a1: csr_addr_to_idx = 7'd35;  // tdata1
//           12'h7a2: csr_addr_to_idx = 7'd36;  // tdata2
//           12'h7a3: csr_addr_to_idx = 7'd37;  // tdata3
//           12'h7a4: csr_addr_to_idx = 7'd38;  // tinfo
//           12'h7a5: csr_addr_to_idx = 7'd39;  // tcontrol
//           12'h7a8: csr_addr_to_idx = 7'd40;  // mcontext
//           12'hda0: csr_addr_to_idx = 7'd41;  // scountovf

//           12'hf11: csr_addr_to_idx = 7'd42;  // mvendorid
//           12'hf12: csr_addr_to_idx = 7'd43;  // marchid
//           12'hf13: csr_addr_to_idx = 7'd44;  // mimpid
//           12'hf14: csr_addr_to_idx = 7'd45;  // mhartid
//           default: csr_addr_to_idx = 7'd0;
//         endcase
//       end
//     end
//   endfunction

//   function csr_addr_is_mapped;
//     input [11:0] csr_addr;
//     begin
//       csr_addr_is_mapped =
//         (csr_addr == 12'h300) || (csr_addr == 12'h301) || (csr_addr == 12'h302) ||
//         (csr_addr == 12'h303) || (csr_addr == 12'h304) || (csr_addr == 12'h305) ||
//         (csr_addr == 12'h306) || (csr_addr == 12'h310) || (csr_addr == 12'h31a) ||
//         (csr_addr == 12'h320) || (csr_addr == 12'h340) || (csr_addr == 12'h341) ||
//         (csr_addr == 12'h342) || (csr_addr == 12'h343) || (csr_addr == 12'h344) ||
//         (csr_addr == 12'h30a) ||
//         (csr_addr == 12'h100) || (csr_addr == 12'h104) || (csr_addr == 12'h105) ||
//         (csr_addr == 12'h106) || (csr_addr == 12'h10a) || (csr_addr == 12'h140) ||
//         (csr_addr == 12'h141) || (csr_addr == 12'h142) || (csr_addr == 12'h143) ||
//         (csr_addr == 12'h144) || (csr_addr == 12'h180) ||
//         (csr_addr == 12'hb00) || (csr_addr == 12'hc00) || (csr_addr == 12'hb80) ||
//         (csr_addr == 12'hc80) || (csr_addr == 12'hc01) || (csr_addr == 12'hc81) ||
//         (csr_addr == 12'hb02) || (csr_addr == 12'hc02) || (csr_addr == 12'hb82) ||
//         (csr_addr == 12'hc82) || (csr_addr == 12'h744) ||
//         (csr_addr == 12'h7a0) || (csr_addr == 12'h7a1) || (csr_addr == 12'h7a2) ||
//         (csr_addr == 12'h7a3) || (csr_addr == 12'h7a4) || (csr_addr == 12'h7a5) ||
//         (csr_addr == 12'h7a8) || (csr_addr == 12'hda0) ||
//         (csr_addr == 12'hf11) || (csr_addr == 12'hf12) || (csr_addr == 12'hf13) ||
//         (csr_addr == 12'hf14) ||
//         ((csr_addr >= 12'h3a0) && (csr_addr <= 12'h3a3)) ||
//         ((csr_addr >= 12'h3b0) && (csr_addr <= 12'h3bf));
//     end
//   endfunction

//   function csr_is_trigger_csr;
//     input [11:0] csr_addr;
//     begin
//       csr_is_trigger_csr =
//         ((csr_addr >= 12'h7a0) && (csr_addr <= 12'h7a5)) ||
//         (csr_addr == 12'h7a8);
//     end
//   endfunction

// `ifdef NPC_TRIGGER_ENABLE
//   localparam TRIGGER_SLOT_ENABLE = 1'b1;
// `else
//   localparam TRIGGER_SLOT_ENABLE = 1'b0;
// `endif

//   wire [6:0] raddr1_real = csr_addr_to_idx(raddr1);
//   wire [6:0] waddr1_real = csr_addr_to_idx(waddr1);
//   wire [6:0] waddr2_real = csr_addr_to_idx(waddr2);

//   wire raddr1_valid = csr_addr_is_mapped(raddr1);
//   wire waddr1_valid = csr_addr_is_mapped(waddr1);
//   wire waddr2_valid = csr_addr_is_mapped(waddr2);

//   assign raddr1_illegal = !raddr1_valid;
//   assign waddr1_illegal = !waddr1_valid;
//   assign waddr2_illegal = !waddr2_valid;

//   assign rdata1 = !raddr1_valid ? {DATA_WIDTH{1'b0}} :
//                   ((!TRIGGER_SLOT_ENABLE) && csr_is_trigger_csr(raddr1)) ? {DATA_WIDTH{1'b0}} :
//                   (raddr1 == 12'hf14) ? HART_ID[DATA_WIDTH-1:0] :
//                   csr[raddr1_real];

//   always @(posedge clk) begin
//     if (!rst_n) begin : reset_csr
//       integer i;
//       for (i = 0; i < 66; i = i + 1) begin
//         csr[i] = {DATA_WIDTH{1'b0}};
//       end
//       csr[12] <= 32'h00001800;              // mcause reset value used by existing NPC model
//       csr[45] <= HART_ID[DATA_WIDTH-1:0];   // mhartid
//     end else if (wen[1]) begin
//       if (waddr1_valid && (TRIGGER_SLOT_ENABLE || !csr_is_trigger_csr(waddr1))) csr[waddr1_real] <= wdata1;
//       if (wen[0]) begin
//         if (waddr2_valid && (TRIGGER_SLOT_ENABLE || !csr_is_trigger_csr(waddr2))) csr[waddr2_real] <= wdata2;
//       end
//     end
//   end
// endmodule
