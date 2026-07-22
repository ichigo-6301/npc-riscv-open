`ifndef BBUS_OOO_TYPES_SVH
`define BBUS_OOO_TYPES_SVH

`include "bbus_ooo_cfg.svh"

typedef logic [`BBUS_OOO_ARCH_REG_W-1:0] bbus_ooo_arch_reg_t;
typedef logic [`BBUS_OOO_PHYS_REG_W-1:0] bbus_ooo_phys_reg_t;
typedef logic [`BBUS_OOO_ROB_IDX_W-1:0]  bbus_ooo_rob_idx_t;

typedef struct packed {
    logic valid;
    logic [`BBUS_OOO_ROB_GEN_W-1:0] gen;
    bbus_ooo_rob_idx_t idx;
} bbus_ooo_rob_tag_t;

typedef struct packed {
    logic valid;
    logic [31:0] cause;
    logic [31:0] tval;
} bbus_ooo_exception_t;

typedef enum logic [3:0] {
    BBUS_OOO_CTRL_NONE      = 4'd0,
    BBUS_OOO_CTRL_EXCEPTION = 4'd1,
    BBUS_OOO_CTRL_INTERRUPT = 4'd2,
    BBUS_OOO_CTRL_ECALL     = 4'd3,
    BBUS_OOO_CTRL_EBREAK    = 4'd4,
    BBUS_OOO_CTRL_MRET      = 4'd5,
    BBUS_OOO_CTRL_FENCEI    = 4'd6
} bbus_ooo_control_event_e;

typedef enum logic [3:0] {
    BBUS_OOO_SIDE_NONE  = 4'd0,
    BBUS_OOO_SIDE_STORE = 4'd1,
    BBUS_OOO_SIDE_CSR   = 4'd2,
    BBUS_OOO_SIDE_FENCE = 4'd3,
    BBUS_OOO_SIDE_SYS   = 4'd4
} bbus_ooo_side_effect_e;

typedef enum logic [3:0] {
    BBUS_OOO_FU_NONE = 4'd0,
    BBUS_OOO_FU_ALU  = 4'd1,
    BBUS_OOO_FU_BRU  = 4'd2,
    BBUS_OOO_FU_LSU  = 4'd3,
    BBUS_OOO_FU_CSR  = 4'd4,
    BBUS_OOO_FU_MDU  = 4'd5,
    BBUS_OOO_FU_SYS  = 4'd6,
    BBUS_OOO_FU_AMO  = 4'd7
} bbus_ooo_fu_type_e;

typedef enum logic [3:0] {
    BBUS_OOO_ALU_ADD = 4'd0,
    BBUS_OOO_ALU_SUB = 4'd1,
    BBUS_OOO_ALU_AND = 4'd2,
    BBUS_OOO_ALU_OR  = 4'd3,
    BBUS_OOO_ALU_XOR = 4'd4,
    BBUS_OOO_ALU_SLL = 4'd5,
    BBUS_OOO_ALU_SRL = 4'd6,
    BBUS_OOO_ALU_SRA = 4'd7,
    BBUS_OOO_ALU_SLT = 4'd8,
    BBUS_OOO_ALU_SLTU = 4'd9,
    BBUS_OOO_ALU_COPY_A = 4'd10,
    BBUS_OOO_ALU_COPY_B = 4'd11,
    BBUS_OOO_ALU_ANDN = 4'd12
} bbus_ooo_alu_op_e;

typedef enum logic [2:0] {
    BBUS_OOO_MDU_MUL    = 3'd0,
    BBUS_OOO_MDU_MULH   = 3'd1,
    BBUS_OOO_MDU_MULHSU = 3'd2,
    BBUS_OOO_MDU_MULHU  = 3'd3,
    BBUS_OOO_MDU_DIV    = 3'd4,
    BBUS_OOO_MDU_DIVU   = 3'd5,
    BBUS_OOO_MDU_REM    = 3'd6,
    BBUS_OOO_MDU_REMU   = 3'd7
} bbus_ooo_mdu_op_e;

typedef enum logic [3:0] {
    BBUS_OOO_AMO_LR    = 4'd0,
    BBUS_OOO_AMO_SC    = 4'd1,
    BBUS_OOO_AMO_SWAP  = 4'd2,
    BBUS_OOO_AMO_ADD   = 4'd3,
    BBUS_OOO_AMO_XOR   = 4'd4,
    BBUS_OOO_AMO_AND   = 4'd5,
    BBUS_OOO_AMO_OR    = 4'd6,
    BBUS_OOO_AMO_MIN   = 4'd7,
    BBUS_OOO_AMO_MAX   = 4'd8,
    BBUS_OOO_AMO_MINU  = 4'd9,
    BBUS_OOO_AMO_MAXU  = 4'd10
} bbus_ooo_atomic_op_e;

typedef enum logic [2:0] {
    BBUS_OOO_BR_BEQ  = 3'd0,
    BBUS_OOO_BR_BNE  = 3'd1,
    BBUS_OOO_BR_BLT  = 3'd2,
    BBUS_OOO_BR_BGE  = 3'd3,
    BBUS_OOO_BR_BLTU = 3'd4,
    BBUS_OOO_BR_BGEU = 3'd5,
    BBUS_OOO_BR_JAL  = 3'd6,
    BBUS_OOO_BR_JALR = 3'd7
} bbus_ooo_branch_op_e;

typedef enum logic [2:0] {
    BBUS_OOO_PRED_NONE        = 3'd0,
    BBUS_OOO_PRED_COND_MISS   = 3'd1,
    BBUS_OOO_PRED_COND_WEAK   = 3'd2,
    BBUS_OOO_PRED_COND_STRONG = 3'd3,
    BBUS_OOO_PRED_DIRECT_JAL  = 3'd4,
    BBUS_OOO_PRED_JALR_RAS    = 3'd5,
    BBUS_OOO_PRED_JALR_BTB    = 3'd6,
    BBUS_OOO_PRED_JALR_MISS   = 3'd7
} bbus_ooo_pred_source_e;

typedef logic [7:0] bbus_ooo_pred_history_t;
typedef logic [5:0] bbus_ooo_local_history_t;
typedef logic [2:0] bbus_ooo_multihistory_mask_t;

typedef enum logic [1:0] {
    BBUS_OOO_RAS_NONE     = 2'd0,
    BBUS_OOO_RAS_PUSH     = 2'd1,
    BBUS_OOO_RAS_POP      = 2'd2,
    BBUS_OOO_RAS_POP_PUSH = 2'd3
} bbus_ooo_ras_action_e;

typedef enum logic [2:0] {
    BBUS_OOO_MEM_NONE = 3'd0,
    BBUS_OOO_MEM_B_S  = 3'd1,
    BBUS_OOO_MEM_H_S  = 3'd2,
    BBUS_OOO_MEM_W    = 3'd3,
    BBUS_OOO_MEM_B_U  = 3'd4,
    BBUS_OOO_MEM_H_U  = 3'd5
} bbus_ooo_mem_op_e;

// End-to-end physical-memory ownership identity.  The token is transported
// unchanged with every request and response; adapters may use a private table
// index internally, but may not infer ownership from response order.
typedef enum logic [1:0] {
    BBUS_OOO_MEM_CLIENT_LSU_LOAD  = 2'd0,
    BBUS_OOO_MEM_CLIENT_LSU_STORE = 2'd1,
    BBUS_OOO_MEM_CLIENT_AMO       = 2'd2,
    BBUS_OOO_MEM_CLIENT_PTW       = 2'd3
} bbus_ooo_mem_client_e;

typedef struct packed {
    logic valid;
    bbus_ooo_mem_client_e client;
    logic [1:0] slot;
    logic [31:0] generation;
    logic [31:0] recovery_epoch;
} bbus_ooo_mem_token_t;

typedef struct packed {
    logic valid;
    logic [31:0] pc;
    logic [31:0] instr;
    logic branch_window_line;
    logic branch_window_line_word1;

    bbus_ooo_arch_reg_t arch_rs1;
    bbus_ooo_arch_reg_t arch_rs2;
    bbus_ooo_arch_reg_t arch_rd;

    logic uses_rs1;
    logic uses_rs2;
    logic rf_wen;
    bbus_ooo_fu_type_e fu_type;
    bbus_ooo_branch_op_e branch_op;
    logic pred_taken;
    logic [31:0] pred_target;
    bbus_ooo_pred_source_e pred_source;
    logic pred_correlated;
    logic pred_base_taken;
    logic pred_base_counter_valid;
    logic pred_base_counter_taken;
    logic pred_corr_candidate;
    logic pred_corr_raw_candidate;
    logic pred_corr_chooser_prefer;
    logic pred_corr_taken;
    bbus_ooo_pred_history_t pred_history;
    bbus_ooo_local_history_t pred_local_history;
    logic pred_local_strong;
    logic pred_local_taken;
    logic pred_local_chooser_prefer;
    logic pred_local_chooser_strong;
    bbus_ooo_multihistory_mask_t pred_multihistory_hit;
    bbus_ooo_multihistory_mask_t pred_multihistory_strong;
    bbus_ooo_multihistory_mask_t pred_multihistory_taken;
    bbus_ooo_multihistory_mask_t pred_multihistory_chooser_prefer;
    bbus_ooo_multihistory_mask_t pred_multihistory_chooser_strong;
    logic pred_ras_self_collision;
    bbus_ooo_alu_op_e alu_op;
    bbus_ooo_mdu_op_e mdu_op;
    bbus_ooo_atomic_op_e atomic_op;
    logic aq;
    logic rl;
    logic src1_is_pc;
    logic src2_is_imm;
    logic [31:0] imm;
    logic is_load;
    logic is_store;
    bbus_ooo_mem_op_e mem_op;
    logic is_csr;
    logic is_system;
    logic is_ebreak;
    logic [11:0] csr_addr;
    logic unsupported_class;

    bbus_ooo_exception_t exception;
} bbus_ooo_decode_uop_t;

typedef struct packed {
    logic valid;
    logic [31:0] pc;
    logic [31:0] instr;
    logic branch_window_line;
    logic branch_window_line_word1;

    bbus_ooo_arch_reg_t arch_rs1;
    bbus_ooo_arch_reg_t arch_rs2;
    bbus_ooo_arch_reg_t arch_rd;

    bbus_ooo_phys_reg_t phys_rs1;
    bbus_ooo_phys_reg_t phys_rs2;
    bbus_ooo_phys_reg_t phys_rd_new;
    bbus_ooo_phys_reg_t phys_rd_old;

    logic uses_rs1;
    logic uses_rs2;
    logic rf_wen;
    bbus_ooo_fu_type_e fu_type;
    bbus_ooo_branch_op_e branch_op;
    logic pred_taken;
    logic [31:0] pred_target;
    bbus_ooo_pred_source_e pred_source;
    logic pred_correlated;
    logic pred_base_taken;
    logic pred_base_counter_valid;
    logic pred_base_counter_taken;
    logic pred_corr_candidate;
    logic pred_corr_raw_candidate;
    logic pred_corr_chooser_prefer;
    logic pred_corr_taken;
    bbus_ooo_pred_history_t pred_history;
    bbus_ooo_local_history_t pred_local_history;
    logic pred_local_strong;
    logic pred_local_taken;
    logic pred_local_chooser_prefer;
    logic pred_local_chooser_strong;
    bbus_ooo_multihistory_mask_t pred_multihistory_hit;
    bbus_ooo_multihistory_mask_t pred_multihistory_strong;
    bbus_ooo_multihistory_mask_t pred_multihistory_taken;
    bbus_ooo_multihistory_mask_t pred_multihistory_chooser_prefer;
    bbus_ooo_multihistory_mask_t pred_multihistory_chooser_strong;
    logic pred_ras_self_collision;
    bbus_ooo_alu_op_e alu_op;
    bbus_ooo_mdu_op_e mdu_op;
    bbus_ooo_atomic_op_e atomic_op;
    logic aq;
    logic rl;
    logic src1_is_pc;
    logic src2_is_imm;
    logic [31:0] imm;
    logic is_load;
    logic is_store;
    bbus_ooo_mem_op_e mem_op;
    logic is_csr;
    logic is_system;
    logic is_ebreak;
    logic [11:0] csr_addr;
    logic unsupported_class;
    logic src1_ready;
    logic src2_ready;

    bbus_ooo_exception_t exception;
} bbus_ooo_renamed_uop_t;

typedef struct packed {
    logic valid;
    bbus_ooo_rob_tag_t rob_tag;

    logic [31:0] pc;
    logic [31:0] instr;

    bbus_ooo_arch_reg_t arch_rd;
    bbus_ooo_phys_reg_t phys_rd_new;
    bbus_ooo_phys_reg_t phys_rd_old;
    logic rf_wen;
    bbus_ooo_fu_type_e fu_type;
    bbus_ooo_branch_op_e branch_op;
    logic is_load;
    logic is_store;
    logic is_ebreak;
    logic is_csr;
    logic is_system;
    logic [11:0] csr_addr;
    bbus_ooo_mem_op_e mem_op;

    bbus_ooo_exception_t exception;
} bbus_ooo_rob_alloc_t;

typedef struct packed {
    logic valid;
    bbus_ooo_rob_tag_t rob_tag;

    logic [31:0] pc;
    logic [31:0] instr;

    bbus_ooo_arch_reg_t arch_rd;
    bbus_ooo_phys_reg_t phys_rs1;
    bbus_ooo_phys_reg_t phys_rs2;
    bbus_ooo_phys_reg_t phys_rd_new;

    logic rf_wen;
    bbus_ooo_fu_type_e fu_type;
    bbus_ooo_branch_op_e branch_op;
    logic pred_taken;
    logic [31:0] pred_target;
    bbus_ooo_pred_source_e pred_source;
    logic pred_correlated;
    logic pred_base_taken;
    logic pred_base_counter_valid;
    logic pred_base_counter_taken;
    logic pred_corr_candidate;
    logic pred_corr_raw_candidate;
    logic pred_corr_chooser_prefer;
    logic pred_corr_taken;
    bbus_ooo_pred_history_t pred_history;
    bbus_ooo_local_history_t pred_local_history;
    logic pred_local_strong;
    logic pred_local_taken;
    logic pred_local_chooser_prefer;
    logic pred_local_chooser_strong;
    bbus_ooo_multihistory_mask_t pred_multihistory_hit;
    bbus_ooo_multihistory_mask_t pred_multihistory_strong;
    bbus_ooo_multihistory_mask_t pred_multihistory_taken;
    bbus_ooo_multihistory_mask_t pred_multihistory_chooser_prefer;
    bbus_ooo_multihistory_mask_t pred_multihistory_chooser_strong;
    logic pred_ras_self_collision;
    bbus_ooo_alu_op_e alu_op;
    bbus_ooo_mdu_op_e mdu_op;
    bbus_ooo_atomic_op_e atomic_op;
    logic aq;
    logic rl;
    logic is_load;
    logic is_store;
    bbus_ooo_mem_op_e mem_op;
    logic src1_is_pc;
    logic src2_is_imm;
    logic [31:0] imm;
    logic is_csr;
    logic is_system;
    logic [11:0] csr_addr;
    logic src1_ready;
    logic src2_ready;
    bbus_ooo_exception_t exception;
} bbus_ooo_alu_iq_uop_t;

typedef struct packed {
    logic valid;
    bbus_ooo_rob_tag_t rob_tag;

    logic [31:0] pc;
    logic [31:0] instr;

    bbus_ooo_arch_reg_t arch_rd;
    bbus_ooo_phys_reg_t phys_rd;
    logic rf_wen;

    logic is_load;
    logic is_store;
    bbus_ooo_mem_op_e mem_op;
    logic [31:0] imm;
} bbus_ooo_lsu_uop_t;

typedef struct packed {
    logic valid;
    bbus_ooo_rob_tag_t rob_tag;

    bbus_ooo_phys_reg_t phys_rd;
    logic rf_wen;
    logic [31:0] result;
    logic done;

    logic is_control;
    logic is_branch;
    logic is_jal;
    logic is_jalr;
    logic actual_taken;
    logic [31:0] actual_nextpc;
    logic redirect_valid;

    logic is_load;
    logic is_store;
    bbus_ooo_mem_op_e mem_op;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [3:0] mem_wstrb;
    logic [2:0] mem_len;

    logic is_csr;
    logic is_system;
    logic [11:0] csr_addr;
    logic csr_write;
    logic [31:0] csr_wdata;

    bbus_ooo_exception_t exception;
} bbus_ooo_writeback_t;

typedef struct packed {
    logic valid;
    bbus_ooo_rob_tag_t rob_tag;

    logic [31:0] pc;
    logic [31:0] instr;

    bbus_ooo_arch_reg_t arch_rd;
    bbus_ooo_phys_reg_t phys_rd_new;
    bbus_ooo_phys_reg_t phys_rd_old;
    logic rf_wen;

    logic [31:0] wdata;
    logic wdata_valid;
    bbus_ooo_fu_type_e fu_type;
    bbus_ooo_branch_op_e branch_op;

    logic is_control;
    logic is_branch;
    logic is_jal;
    logic is_jalr;
    logic actual_taken;
    logic [31:0] commit_nextpc;
    logic redirect_valid;

    logic is_load;
    logic is_store;
    bbus_ooo_mem_op_e mem_op;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [3:0] mem_wstrb;
    logic [2:0] mem_len;

    logic is_csr;
    logic is_system;
    logic [11:0] csr_addr;
    logic csr_write;
    logic [31:0] csr_wdata;

    bbus_ooo_exception_t exception;
} bbus_ooo_commit_slot_t;

typedef struct packed {
    logic [1:0] normal_commit_mask;

    logic side_effect_commit_valid;
    bbus_ooo_side_effect_e side_effect_kind;

    logic control_event_valid;
    bbus_ooo_control_event_e control_event;

    bbus_ooo_commit_slot_t slot0;
    bbus_ooo_commit_slot_t slot1;
} bbus_ooo_commit_event_t;

typedef struct packed {
    logic valid;
    logic [1:0] commit_mask;
    logic commit_slot1;

    logic [31:0] pc;
    logic [31:0] instr;

    logic rf_wen;
    bbus_ooo_arch_reg_t arch_rd;
    logic [31:0] wdata;
    logic [31:0] commit_nextpc;

    logic is_control;
    logic is_branch;
    logic is_jal;
    logic is_jalr;
    logic is_load;
    logic is_store;
    bbus_ooo_mem_op_e mem_op;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [3:0] mem_wstrb;
    logic [2:0] mem_len;

    logic exception_valid;
    logic [31:0] exception_cause;

    logic skip;
    logic unsupported;

    bbus_ooo_rob_tag_t rob_tag;
} bbus_ooo_commit_trace_packet_t;

typedef enum logic [2:0] {
    BBUS_OOO_REDIRECT_NONE      = 3'd0,
    BBUS_OOO_REDIRECT_BRANCH    = 3'd1,
    BBUS_OOO_REDIRECT_JAL       = 3'd2,
    BBUS_OOO_REDIRECT_JALR      = 3'd3,
    BBUS_OOO_REDIRECT_EXCEPTION = 3'd4
} bbus_ooo_redirect_reason_e;

typedef struct packed {
    logic valid;
    bbus_ooo_rob_tag_t rob_tag;
    logic [31:0] pc;
    logic [31:0] instr;

    bbus_ooo_branch_op_e br_op;
    logic [31:0] imm;
    logic pred_taken;
    logic [31:0] pred_target;
    bbus_ooo_pred_source_e pred_source;
    logic pred_correlated;
    logic pred_base_taken;
    logic pred_base_counter_valid;
    logic pred_base_counter_taken;
    logic pred_corr_candidate;
    logic pred_corr_raw_candidate;
    logic pred_corr_chooser_prefer;
    logic pred_corr_taken;
    bbus_ooo_pred_history_t pred_history;
    bbus_ooo_local_history_t pred_local_history;
    logic pred_local_strong;
    logic pred_local_taken;
    logic pred_local_chooser_prefer;
    logic pred_local_chooser_strong;
    bbus_ooo_multihistory_mask_t pred_multihistory_hit;
    bbus_ooo_multihistory_mask_t pred_multihistory_strong;
    bbus_ooo_multihistory_mask_t pred_multihistory_taken;
    bbus_ooo_multihistory_mask_t pred_multihistory_chooser_prefer;
    bbus_ooo_multihistory_mask_t pred_multihistory_chooser_strong;
    logic pred_ras_self_collision;

    bbus_ooo_arch_reg_t arch_rd;
    bbus_ooo_phys_reg_t phys_rd;
    logic rf_wen;
} bbus_ooo_branch_uop_t;

typedef struct packed {
    logic valid;
    bbus_ooo_rob_tag_t rob_tag;
    logic [31:0] pc;
    bbus_ooo_branch_op_e br_op;

    logic pred_taken;
    logic [31:0] pred_target;
    bbus_ooo_pred_source_e pred_source;
    logic pred_correlated;
    logic pred_base_taken;
    logic pred_base_counter_valid;
    logic pred_base_counter_taken;
    logic pred_corr_candidate;
    logic pred_corr_raw_candidate;
    logic pred_corr_chooser_prefer;
    logic pred_corr_taken;
    bbus_ooo_pred_history_t pred_history;
    bbus_ooo_local_history_t pred_local_history;
    logic pred_local_strong;
    logic pred_local_taken;
    logic pred_local_chooser_prefer;
    logic pred_local_chooser_strong;
    bbus_ooo_multihistory_mask_t pred_multihistory_hit;
    bbus_ooo_multihistory_mask_t pred_multihistory_strong;
    bbus_ooo_multihistory_mask_t pred_multihistory_taken;
    bbus_ooo_multihistory_mask_t pred_multihistory_chooser_prefer;
    bbus_ooo_multihistory_mask_t pred_multihistory_chooser_strong;
    logic pred_ras_self_collision;
    logic actual_taken;
    logic [31:0] actual_target;
    logic mispredict;

    bbus_ooo_arch_reg_t arch_rd;
    bbus_ooo_phys_reg_t phys_rd;
    logic rf_wen;
    logic [31:0] link_wdata;
} bbus_ooo_branch_completion_t;

typedef struct packed {
    logic valid;
    bbus_ooo_rob_tag_t rob_tag;
    logic [31:0] pc;
    bbus_ooo_branch_op_e br_op;

    logic actual_taken;
    logic [31:0] actual_target;
    logic mispredict;
} bbus_ooo_branch_done_t;

typedef struct packed {
    logic valid;
    bbus_ooo_rob_tag_t rob_tag;
    logic [31:0] pc;
    bbus_ooo_redirect_reason_e reason;
    logic [31:0] target;
} bbus_ooo_redirect_t;

typedef struct packed {
    logic valid;
    bbus_ooo_rob_tag_t rob_tag;
    logic [31:0] pc;
    bbus_ooo_branch_op_e br_op;

    logic done;
    logic actual_taken;
    logic [31:0] actual_target;
    logic mispredict;

    logic redirect_seen;
    logic [31:0] redirect_target;

    logic [3:0] update_count;
} bbus_ooo_branch_table_entry_t;

typedef logic [2:0] bbus_ooo_checkpoint_id_t;

typedef logic [(`BBUS_OOO_ARCH_REGS * `BBUS_OOO_PHYS_REG_W)-1:0]
    bbus_ooo_rat_snapshot_t;

typedef struct packed {
    logic [3:0] count;
    logic [(8 * 32)-1:0] entries;
} bbus_ooo_ras_snapshot_t;

typedef struct packed {
    logic valid;
    bbus_ooo_checkpoint_id_t checkpoint_id;
    bbus_ooo_rob_tag_t branch_rob_tag;
    logic [31:0] branch_pc;
    bbus_ooo_branch_op_e branch_op;
    bbus_ooo_ras_action_e branch_ras_action;
    logic [31:0] branch_ras_link;
    bbus_ooo_rat_snapshot_t rat_snapshot;
    bbus_ooo_ras_snapshot_t ras_snapshot;
    bbus_ooo_rob_tag_t post_branch_tail_tag;
} bbus_ooo_real_checkpoint_t;

typedef struct packed {
    logic valid;
    bbus_ooo_checkpoint_id_t checkpoint_id;

    bbus_ooo_rob_tag_t branch_rob_tag;
    logic [31:0] branch_pc;
    bbus_ooo_branch_op_e branch_op;

    logic [7:0] rat_snapshot_id;
    logic [7:0] freelist_snapshot_id;
    logic [7:0] ready_snapshot_id;

    logic [7:0] alloc_order;
    logic selected_for_restore;
} bbus_ooo_branch_checkpoint_entry_t;

typedef struct packed {
    logic valid;
    bbus_ooo_checkpoint_id_t checkpoint_id;

    bbus_ooo_rob_tag_t branch_rob_tag;
    logic [31:0] branch_pc;

    logic [7:0] rat_snapshot_id;
    logic [7:0] freelist_snapshot_id;
    logic [7:0] ready_snapshot_id;

} bbus_ooo_checkpoint_restore_t;

typedef struct packed {
    logic valid;
    bbus_ooo_checkpoint_id_t checkpoint_id;

    bbus_ooo_rob_tag_t branch_rob_tag;
    logic [31:0] branch_pc;

    logic [7:0] rat_snapshot_id;
    logic [7:0] freelist_snapshot_id;
    logic [7:0] ready_snapshot_id;
} bbus_ooo_recovery_action_t;

typedef struct packed {
    logic valid;
    bbus_ooo_checkpoint_id_t checkpoint_id;

    bbus_ooo_rob_tag_t branch_rob_tag;
    logic [31:0] branch_pc;

    logic [7:0] rat_snapshot_id;
    logic [7:0] freelist_snapshot_id;
    logic [7:0] ready_snapshot_id;
} bbus_ooo_recovery_done_t;

`endif
