`ifndef BBUS_CORE_DEFS_SVH
`define BBUS_CORE_DEFS_SVH

`define BBUS_XLEN 32
`define BBUS_REG_ADDR_W 5
`define BBUS_CSR_ADDR_W 12
`define BBUS_ISSUE_W 1
`define BBUS_LANE0 1'b0
`define BBUS_LANE1 1'b1

`define BBUS_BR_NONE 3'b000
`define BBUS_BR_J    3'b001
`define BBUS_BR_JR   3'b010
`define BBUS_BR_E    3'b011
`define BBUS_BR_BEQ  3'b100
`define BBUS_BR_BNE  3'b101
`define BBUS_BR_BLT  3'b110
`define BBUS_BR_BGE  3'b111

`define BBUS_EXC_ILLEGAL_INSTR         32'd2
`define BBUS_EXC_ECALL_FROM_M          32'd11
`define BBUS_EXC_LOAD_ADDR_MISALIGNED  32'd4
`define BBUS_EXC_STORE_ADDR_MISALIGNED 32'd6

typedef enum logic [2:0] {
    BBUS_BR_NONE_E = `BBUS_BR_NONE,
    BBUS_BR_J_E    = `BBUS_BR_J,
    BBUS_BR_JR_E   = `BBUS_BR_JR,
    BBUS_BR_E_E    = `BBUS_BR_E,
    BBUS_BR_BEQ_E  = `BBUS_BR_BEQ,
    BBUS_BR_BNE_E  = `BBUS_BR_BNE,
    BBUS_BR_BLT_E  = `BBUS_BR_BLT,
    BBUS_BR_BGE_E  = `BBUS_BR_BGE
} bbus_branch_e;

typedef enum logic [0:0] {
    BBUS_LANE0_E = `BBUS_LANE0,
    BBUS_LANE1_E = `BBUS_LANE1
} bbus_lane_e;

typedef enum logic [3:0] {
    BBUS_FU_NONE = 4'd0,
    BBUS_FU_ALU  = 4'd1,
    BBUS_FU_BRU  = 4'd2,
    BBUS_FU_LSU  = 4'd3,
    BBUS_FU_CSR  = 4'd4,
    BBUS_FU_MDU  = 4'd5,
    BBUS_FU_SYS  = 4'd6
} bbus_fu_e;

typedef enum logic [1:0] {
    BBUS_REDIR_NONE = 2'd0,
    BBUS_REDIR_FAST = 2'd1,
    BBUS_REDIR_SLOW = 2'd2
} bbus_redirect_class_e;

typedef struct packed {
    logic        valid;
    logic [31:0] cause;
    logic [31:0] tval;
    logic [31:0] epc;
} bbus_exception_t;

typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] target_pc;
    logic        is_fast;
    logic        is_slow;
    logic        kill_younger;
    logic        trace_is_redirect;
} bbus_redirect_t;

typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
    logic [31:0] nextpc;
    logic [4:0]  rd;
    logic [31:0] wdata;
    logic        rf_wen;
    logic        side_effect_valid;
    bbus_exception_t exc;
} bbus_commit_t;

typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic        is_cond;
    logic        taken;
    logic [31:0] target_pc;
    logic        mispredict;
} bbus_bpu_update_t;

typedef struct packed {
    logic        valid;

    logic [31:0] pc;
    logic [31:0] instr;
    logic [31:0] nextpc;

    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic        uses_rs1;
    logic        uses_rs2;
    logic        rf_wen;

    bbus_fu_e    fu;
    bbus_branch_e branch;

    logic [31:0] imm;
    logic [31:0] src1_value;
    logic [31:0] src2_value;

    logic [1:0]  mem_wr;
    logic [2:0]  mem_op;
    logic [1:0]  datatoreg;

    logic [1:0]  csr_wen;
    logic [11:0] csr_waddr1;
    logic [11:0] csr_waddr2;

    logic        pred_taken;
    logic [31:0] pred_target;

    logic        illegal;
    logic        is_ebreak;

    bbus_exception_t exc;
} bbus_uop_t;

typedef enum logic [3:0] {
    BBUS_PAIR_OK                = 4'd0,
    BBUS_PAIR_SLOT1_DISABLED    = 4'd1,
    BBUS_PAIR_SLOT0_INVALID     = 4'd2,
    BBUS_PAIR_SLOT1_INVALID     = 4'd3,
    BBUS_PAIR_SLOT1_NOT_ALU     = 4'd4,
    BBUS_PAIR_RAW_DEP           = 4'd5,
    BBUS_PAIR_WAW_DEP           = 4'd6,
    BBUS_PAIR_CONTROL           = 4'd7,
    BBUS_PAIR_MEM_OR_CSR        = 4'd8,
    BBUS_PAIR_SYS_OR_EXCEPTION  = 4'd9,
    BBUS_PAIR_RESERVED          = 4'd15
} bbus_pair_reason_e;

typedef struct packed {
    logic              pair_valid;
    logic              slot0_valid;
    logic              slot1_valid;
    logic [1:0]        issue_count;
    bbus_pair_reason_e reason;
} bbus_pair_decision_t;

typedef struct packed {
    logic       valid;
    bbus_lane_e lane;
    logic       older;
    logic       younger;
} bbus_slot_meta_t;

typedef struct packed {
    bbus_uop_t           slot0_uop;
    bbus_uop_t           slot1_uop;
    bbus_slot_meta_t     slot0_meta;
    bbus_slot_meta_t     slot1_meta;
    bbus_pair_decision_t pairing;
} bbus_decode_bundle_t;

`endif
