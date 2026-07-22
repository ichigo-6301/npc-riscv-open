`timescale 1ns / 1ps

`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
module PipeStat (
    input clk,
    input rst_n,

    input fs_to_ds_valid,  // IF wants to push to ID
    input if_stall,        // IF cannot continue fetch in this cycle
    input ds_allowin,       // ID can accept
    input ds_to_es_valid,   // ID wants to push to EX
    input es_allowin,       // EX can accept
    input es_to_ms_valid,   // EX wants to push to MEM
    input ms_allowin,       // MEM can accept
    input ms_to_ws_valid,   // MEM wants to push to WB
    input ws_allowin,       // WB can accept
    // Root-cause inputs from stage-local blocking conditions
    input id_stage_block,
    input id_stage_block_reg_hazard,
    input id_stage_block_csr_hazard,
    input id_stage_block_load_use,
    input id_stage_block_ex_raw,
    input id_stage_block_ms_raw,
    input id_stage_block_hidden_raw,
    input ex_stage_block,
    input ex_stage_block_mdu_wait,
    input ex_stage_block_redirect_wait,
    input ms_stage_block,
    input ms_stage_block_req_phase,
    input ms_stage_block_resp_phase,
    input [1:0] es_mem_wr,
    input es_mem_fast_block,
    input ms_fast_req_fire,
    input ms_slow_req_fire,
    input ms_slow_req_fwd_dep_fire,
    input ms_slow_req_nonfwd_fire,

    input commit_valid,     // instruction retired
    input commit_is_ebreak,
    input commit_illegal,

    output [63:0] stat_load_use_stall_cycle,
    output [63:0] stat_id_reg_hazard_cycle,
    output [63:0] stat_ms_block_cycle
);
    reg [63:0] total_cycles;
    reg [63:0] ifid_fire_cycles;          // fs_valid=1, ds_allowin=1
    reg [63:0] ifid_stall_cycles;         // fs_valid=1, ds_allowin=0
    reg [63:0] ifid_bubble_cycles;        // fs_valid=0, ds_allowin=1
    reg [63:0] ifid_blocked_empty_cycles; // fs_valid=0, ds_allowin=0
    reg [63:0] idex_fire_cycles;          // ds_to_es_valid=1, es_allowin=1
    reg [63:0] idex_stall_cycles;         // ds_to_es_valid=1, es_allowin=0
    reg [63:0] idex_bubble_cycles;        // ds_to_es_valid=0, es_allowin=1
    reg [63:0] idex_blocked_empty_cycles; // ds_to_es_valid=0, es_allowin=0
    reg [63:0] exmem_fire_cycles;         // es_to_ms_valid=1, ms_allowin=1
    reg [63:0] exmem_stall_cycles;        // es_to_ms_valid=1, ms_allowin=0
    reg [63:0] exmem_bubble_cycles;       // es_to_ms_valid=0, ms_allowin=1
    reg [63:0] exmem_blocked_empty_cycles;// es_to_ms_valid=0, ms_allowin=0
    reg [63:0] memwb_fire_cycles;         // ms_to_ws_valid=1, ws_allowin=1
    reg [63:0] memwb_stall_cycles;        // ms_to_ws_valid=1, ws_allowin=0
    reg [63:0] memwb_bubble_cycles;       // ms_to_ws_valid=0, ws_allowin=1
    reg [63:0] memwb_blocked_empty_cycles;// ms_to_ws_valid=0, ws_allowin=0
    reg [63:0] id_stall_cycles;
    reg [63:0] if_stall_cycles;
    reg [63:0] ex_stall_cycles;
    reg [63:0] ms_stall_cycles;
    reg [63:0] ws_stall_cycles;
    reg [63:0] id_block_cycles;
    reg [63:0] id_block_reg_hazard_cycles;
    reg [63:0] id_block_csr_hazard_cycles;
    reg [63:0] id_block_load_use_cycles;
    reg [63:0] id_block_ex_raw_cycles;
    reg [63:0] id_block_ms_raw_cycles;
    reg [63:0] id_block_hidden_raw_cycles;
    reg [63:0] id_block_other_cycles;
    reg [63:0] ex_block_cycles;
    reg [63:0] ex_block_mdu_wait_cycles;
    reg [63:0] ex_block_redirect_wait_cycles;
    reg [63:0] ex_block_other_cycles;
    reg [63:0] ms_block_cycles;
    reg [63:0] ms_block_req_phase_cycles;
    reg [63:0] ms_block_resp_phase_cycles;
    reg [63:0] ms_block_other_cycles;
    reg [63:0] mem_inst_total;
    reg [63:0] mem_load_total;
    reg [63:0] mem_store_total;
    reg [63:0] mem_fwd_dep_total;
    reg [63:0] mem_fwd_dep_load;
    reg [63:0] mem_fwd_dep_store;
    reg [63:0] mem_fast_req_fire_total;
    reg [63:0] mem_slow_req_fire_total;
    reg [63:0] mem_slow_req_fwd_dep_fire_total;
    reg [63:0] mem_slow_req_nonfwd_fire_total;
    reg [63:0] commit_count;
    reg printed;

    // Stage stalls:
    //   ID stalled = IF has instr, ID can't accept
    //   EX stalled = ID sends instr, EX can't accept
    //   MEM stalled = EX sends instr, MEM can't accept
    //   WB stalled = MEM sends instr, WB can't accept
    wire id_stall  = fs_to_ds_valid && !ds_allowin;
    wire ex_stall  = ds_to_es_valid && !es_allowin;
    wire ms_stall  = es_to_ms_valid && !ms_allowin;
    wire ws_stall  = ms_to_ws_valid && !ws_allowin;
    wire ifid_fire         = fs_to_ds_valid &&  ds_allowin;
    wire ifid_stall        = fs_to_ds_valid && !ds_allowin;
    wire ifid_bubble       = !fs_to_ds_valid &&  ds_allowin;
    wire ifid_blocked_idle = !fs_to_ds_valid && !ds_allowin;
    wire idex_fire         = ds_to_es_valid &&  es_allowin;
    wire idex_stall        = ds_to_es_valid && !es_allowin;
    wire idex_bubble       = !ds_to_es_valid &&  es_allowin;
    wire idex_blocked_idle = !ds_to_es_valid && !es_allowin;
    wire exmem_fire         = es_to_ms_valid &&  ms_allowin;
    wire exmem_stall        = es_to_ms_valid && !ms_allowin;
    wire exmem_bubble       = !es_to_ms_valid &&  ms_allowin;
    wire exmem_blocked_idle = !es_to_ms_valid && !ms_allowin;
    wire memwb_fire         = ms_to_ws_valid &&  ws_allowin;
    wire memwb_stall        = ms_to_ws_valid && !ws_allowin;
    wire memwb_bubble       = !ms_to_ws_valid &&  ws_allowin;
    wire memwb_blocked_idle = !ms_to_ws_valid && !ws_allowin;
    wire es_mem_inst = es_to_ms_valid && (es_mem_wr != 2'b00);
    wire es_mem_store = es_mem_inst && (es_mem_wr == 2'b11);
    wire es_mem_load = es_mem_inst && (es_mem_wr != 2'b11);
    wire es_mem_fwd_dep = es_mem_inst && es_mem_fast_block;
    assign stat_load_use_stall_cycle = id_block_load_use_cycles;
    assign stat_id_reg_hazard_cycle = id_block_reg_hazard_cycles;
    assign stat_ms_block_cycle = ms_block_cycles;

    always @(posedge clk) begin
        if (!rst_n) begin
            total_cycles    <= 64'd0;
            ifid_fire_cycles <= 64'd0;
            ifid_stall_cycles <= 64'd0;
            ifid_bubble_cycles <= 64'd0;
            ifid_blocked_empty_cycles <= 64'd0;
            idex_fire_cycles <= 64'd0;
            idex_stall_cycles <= 64'd0;
            idex_bubble_cycles <= 64'd0;
            idex_blocked_empty_cycles <= 64'd0;
            exmem_fire_cycles <= 64'd0;
            exmem_stall_cycles <= 64'd0;
            exmem_bubble_cycles <= 64'd0;
            exmem_blocked_empty_cycles <= 64'd0;
            memwb_fire_cycles <= 64'd0;
            memwb_stall_cycles <= 64'd0;
            memwb_bubble_cycles <= 64'd0;
            memwb_blocked_empty_cycles <= 64'd0;
            id_stall_cycles <= 64'd0;
            if_stall_cycles <= 64'd0;
            ex_stall_cycles <= 64'd0;
            ms_stall_cycles <= 64'd0;
            ws_stall_cycles <= 64'd0;
            id_block_cycles <= 64'd0;
            id_block_reg_hazard_cycles <= 64'd0;
            id_block_csr_hazard_cycles <= 64'd0;
            id_block_load_use_cycles <= 64'd0;
            id_block_ex_raw_cycles <= 64'd0;
            id_block_ms_raw_cycles <= 64'd0;
            id_block_hidden_raw_cycles <= 64'd0;
            id_block_other_cycles <= 64'd0;
            ex_block_cycles <= 64'd0;
            ex_block_mdu_wait_cycles <= 64'd0;
            ex_block_redirect_wait_cycles <= 64'd0;
            ex_block_other_cycles <= 64'd0;
            ms_block_cycles <= 64'd0;
            ms_block_req_phase_cycles <= 64'd0;
            ms_block_resp_phase_cycles <= 64'd0;
            ms_block_other_cycles <= 64'd0;
            mem_inst_total <= 64'd0;
            mem_load_total <= 64'd0;
            mem_store_total <= 64'd0;
            mem_fwd_dep_total <= 64'd0;
            mem_fwd_dep_load <= 64'd0;
            mem_fwd_dep_store <= 64'd0;
            mem_fast_req_fire_total <= 64'd0;
            mem_slow_req_fire_total <= 64'd0;
            mem_slow_req_fwd_dep_fire_total <= 64'd0;
            mem_slow_req_nonfwd_fire_total <= 64'd0;
            commit_count    <= 64'd0;
            printed         <= 1'b0;
        end else begin
            total_cycles <= total_cycles + 64'd1;
            if (ifid_fire)         ifid_fire_cycles <= ifid_fire_cycles + 64'd1;
            if (ifid_stall)        ifid_stall_cycles <= ifid_stall_cycles + 64'd1;
            if (ifid_bubble)       ifid_bubble_cycles <= ifid_bubble_cycles + 64'd1;
            if (ifid_blocked_idle) ifid_blocked_empty_cycles <= ifid_blocked_empty_cycles + 64'd1;
            if (idex_fire)         idex_fire_cycles <= idex_fire_cycles + 64'd1;
            if (idex_stall)        idex_stall_cycles <= idex_stall_cycles + 64'd1;
            if (idex_bubble)       idex_bubble_cycles <= idex_bubble_cycles + 64'd1;
            if (idex_blocked_idle) idex_blocked_empty_cycles <= idex_blocked_empty_cycles + 64'd1;
            if (exmem_fire)         exmem_fire_cycles <= exmem_fire_cycles + 64'd1;
            if (exmem_stall)        exmem_stall_cycles <= exmem_stall_cycles + 64'd1;
            if (exmem_bubble)       exmem_bubble_cycles <= exmem_bubble_cycles + 64'd1;
            if (exmem_blocked_idle) exmem_blocked_empty_cycles <= exmem_blocked_empty_cycles + 64'd1;
            if (memwb_fire)         memwb_fire_cycles <= memwb_fire_cycles + 64'd1;
            if (memwb_stall)        memwb_stall_cycles <= memwb_stall_cycles + 64'd1;
            if (memwb_bubble)       memwb_bubble_cycles <= memwb_bubble_cycles + 64'd1;
            if (memwb_blocked_idle) memwb_blocked_empty_cycles <= memwb_blocked_empty_cycles + 64'd1;
            if (id_stall)  id_stall_cycles  <= id_stall_cycles  + 64'd1;
            if (if_stall)  if_stall_cycles  <= if_stall_cycles  + 64'd1;
            if (ex_stall)  ex_stall_cycles  <= ex_stall_cycles  + 64'd1;
            if (ms_stall)  ms_stall_cycles  <= ms_stall_cycles  + 64'd1;
            if (ws_stall)  ws_stall_cycles  <= ws_stall_cycles  + 64'd1;
            if (id_stage_block) begin
                id_block_cycles <= id_block_cycles + 64'd1;
                if (id_stage_block_reg_hazard) begin
                    id_block_reg_hazard_cycles <= id_block_reg_hazard_cycles + 64'd1;
                    if (id_stage_block_load_use) id_block_load_use_cycles <= id_block_load_use_cycles + 64'd1;
                    if (id_stage_block_ex_raw) id_block_ex_raw_cycles <= id_block_ex_raw_cycles + 64'd1;
                    if (id_stage_block_ms_raw) id_block_ms_raw_cycles <= id_block_ms_raw_cycles + 64'd1;
                    if (id_stage_block_hidden_raw) id_block_hidden_raw_cycles <= id_block_hidden_raw_cycles + 64'd1;
                end else if (id_stage_block_csr_hazard) begin
                    id_block_csr_hazard_cycles <= id_block_csr_hazard_cycles + 64'd1;
                end else begin
                    id_block_other_cycles <= id_block_other_cycles + 64'd1;
                end
            end
            if (ex_stage_block) begin
                ex_block_cycles <= ex_block_cycles + 64'd1;
                if (ex_stage_block_mdu_wait) begin
                    ex_block_mdu_wait_cycles <= ex_block_mdu_wait_cycles + 64'd1;
                end else if (ex_stage_block_redirect_wait) begin
                    ex_block_redirect_wait_cycles <= ex_block_redirect_wait_cycles + 64'd1;
                end else begin
                    ex_block_other_cycles <= ex_block_other_cycles + 64'd1;
                end
            end
            if (ms_stage_block) begin
                ms_block_cycles <= ms_block_cycles + 64'd1;
                if (ms_stage_block_req_phase) begin
                    ms_block_req_phase_cycles <= ms_block_req_phase_cycles + 64'd1;
                end else if (ms_stage_block_resp_phase) begin
                    ms_block_resp_phase_cycles <= ms_block_resp_phase_cycles + 64'd1;
                end else begin
                    ms_block_other_cycles <= ms_block_other_cycles + 64'd1;
                end
            end
            if (es_mem_inst) begin
                mem_inst_total <= mem_inst_total + 64'd1;
                if (es_mem_store) begin
                    mem_store_total <= mem_store_total + 64'd1;
                end else begin
                    mem_load_total <= mem_load_total + 64'd1;
                end
                if (es_mem_fwd_dep) begin
                    mem_fwd_dep_total <= mem_fwd_dep_total + 64'd1;
                    if (es_mem_store) begin
                        mem_fwd_dep_store <= mem_fwd_dep_store + 64'd1;
                    end else begin
                        mem_fwd_dep_load <= mem_fwd_dep_load + 64'd1;
                    end
                end
            end
            if (ms_fast_req_fire) mem_fast_req_fire_total <= mem_fast_req_fire_total + 64'd1;
            if (ms_slow_req_fire) mem_slow_req_fire_total <= mem_slow_req_fire_total + 64'd1;
            if (ms_slow_req_fwd_dep_fire) mem_slow_req_fwd_dep_fire_total <= mem_slow_req_fwd_dep_fire_total + 64'd1;
            if (ms_slow_req_nonfwd_fire) mem_slow_req_nonfwd_fire_total <= mem_slow_req_nonfwd_fire_total + 64'd1;
            // Commit at WB → ID push indicates a real instruction (not ebreak/illegal)
            if (commit_valid && !commit_is_ebreak && !commit_illegal)
                commit_count <= commit_count + 64'd1;

            if (commit_is_ebreak) begin
                `ifndef NPC_USE_DPI
                // In simulation (DPI=0), print once at ebreak
                if (!printed) begin
                    printed <= 1'b1;
                    $display("[PipeStat] total_cycles=%0d", total_cycles);
                    $display("[PipeStat] commit_inst=%0d", commit_count);
                    $display("[PipeStat] ifid_fire_cycles= %0d", ifid_fire_cycles);
                    $display("[PipeStat] ifid_stall_cycles= %0d", ifid_stall_cycles);
                    $display("[PipeStat] ifid_bubble_cycles= %0d", ifid_bubble_cycles);
                    $display("[PipeStat] ifid_blocked_empty_cycles= %0d", ifid_blocked_empty_cycles);
                    $display("[PipeStat] ifid_sum_check=%0d",
                        ifid_fire_cycles + ifid_stall_cycles + ifid_bubble_cycles + ifid_blocked_empty_cycles);
                    $display("[PipeStat] idex_fire_cycles= %0d", idex_fire_cycles);
                    $display("[PipeStat] idex_stall_cycles= %0d", idex_stall_cycles);
                    $display("[PipeStat] idex_bubble_cycles= %0d", idex_bubble_cycles);
                    $display("[PipeStat] idex_blocked_empty_cycles= %0d", idex_blocked_empty_cycles);
                    $display("[PipeStat] idex_sum_check=%0d",
                        idex_fire_cycles + idex_stall_cycles + idex_bubble_cycles + idex_blocked_empty_cycles);
                    $display("[PipeStat] exmem_fire_cycles= %0d", exmem_fire_cycles);
                    $display("[PipeStat] exmem_stall_cycles= %0d", exmem_stall_cycles);
                    $display("[PipeStat] exmem_bubble_cycles= %0d", exmem_bubble_cycles);
                    $display("[PipeStat] exmem_blocked_empty_cycles= %0d", exmem_blocked_empty_cycles);
                    $display("[PipeStat] exmem_sum_check=%0d",
                        exmem_fire_cycles + exmem_stall_cycles + exmem_bubble_cycles + exmem_blocked_empty_cycles);
                    $display("[PipeStat] memwb_fire_cycles= %0d", memwb_fire_cycles);
                    $display("[PipeStat] memwb_stall_cycles= %0d", memwb_stall_cycles);
                    $display("[PipeStat] memwb_bubble_cycles= %0d", memwb_bubble_cycles);
                    $display("[PipeStat] memwb_blocked_empty_cycles= %0d", memwb_blocked_empty_cycles);
                    $display("[PipeStat] memwb_sum_check=%0d",
                        memwb_fire_cycles + memwb_stall_cycles + memwb_bubble_cycles + memwb_blocked_empty_cycles);
                    $display("[PipeStat] id_stall_cycles= %0d  (load-use / CSR / reg hazard)", id_stall_cycles);
                    $display("[PipeStat] if_stall_cycles= %0d  (I$ / fetch queue / req backpressure)", if_stall_cycles);
                    $display("[PipeStat] ex_stall_cycles= %0d  (MDU / ALU multi-cycle)", ex_stall_cycles);
                    $display("[PipeStat] ms_stall_cycles= %0d  (DCache miss)", ms_stall_cycles);
                    $display("[PipeStat] ws_stall_cycles= %0d  (WB back-pressure)", ws_stall_cycles);
                    $display("[PipeStat] id_block total=%0d reg_hazard=%0d csr_hazard=%0d other=%0d sum=%0d",
                        id_block_cycles, id_block_reg_hazard_cycles, id_block_csr_hazard_cycles,
                        id_block_other_cycles,
                        id_block_reg_hazard_cycles + id_block_csr_hazard_cycles + id_block_other_cycles);
                    $display("[PipeStat] id_block_detail load_use=%0d ex_raw=%0d ms_raw=%0d hidden_raw=%0d csr=%0d",
                        id_block_load_use_cycles, id_block_ex_raw_cycles, id_block_ms_raw_cycles,
                        id_block_hidden_raw_cycles, id_block_csr_hazard_cycles);
                    $display("[PipeStat] ex_block total=%0d mdu_wait=%0d redirect_wait=%0d other=%0d sum=%0d",
                        ex_block_cycles, ex_block_mdu_wait_cycles, ex_block_redirect_wait_cycles,
                        ex_block_other_cycles,
                        ex_block_mdu_wait_cycles + ex_block_redirect_wait_cycles + ex_block_other_cycles);
                    $display("[PipeStat] ms_block total=%0d req_phase=%0d resp_phase=%0d other=%0d sum=%0d",
                        ms_block_cycles, ms_block_req_phase_cycles, ms_block_resp_phase_cycles,
                        ms_block_other_cycles,
                        ms_block_req_phase_cycles + ms_block_resp_phase_cycles + ms_block_other_cycles);
                    $display("[PipeStat] mem_trace total=%0d load=%0d store=%0d",
                        mem_inst_total, mem_load_total, mem_store_total);
                    $display("[PipeStat] mem_trace fwd_dep total=%0d load=%0d store=%0d",
                        mem_fwd_dep_total, mem_fwd_dep_load, mem_fwd_dep_store);
                    $display("[PipeStat] mem_trace req_fire fast=%0d slow=%0d",
                        mem_fast_req_fire_total, mem_slow_req_fire_total);
                    $display("[PipeStat] mem_trace slow_req_cause fwd_dep=%0d nonfwd=%0d",
                        mem_slow_req_fwd_dep_fire_total, mem_slow_req_nonfwd_fire_total);
                    $display("[PipeStat] IPC=%0d.%02d",
                        commit_count / total_cycles,
                        (commit_count * 100 / total_cycles) % 100);
                    $display("[PipeStat] CPI=%.2f", total_cycles * 1.0 / (commit_count > 0 ? commit_count : 1));
                end
                `endif
            end
        end
    end

    // In NPC_USE_DPI mode, print on the rising edge of printed after commit_is_ebreak
    `ifdef NPC_USE_DPI
    always @(posedge clk) begin
        if (!rst_n) begin
            printed <= 1'b0;
        end else if (!printed && commit_is_ebreak) begin
            printed <= 1'b1;
            $display("[PipeStat] total_cycles=%0d", total_cycles);
            $display("[PipeStat] commit_inst=%0d", commit_count);
            $display("[PipeStat] ifid_fire_cycles= %0d", ifid_fire_cycles);
            $display("[PipeStat] ifid_stall_cycles= %0d", ifid_stall_cycles);
            $display("[PipeStat] ifid_bubble_cycles= %0d", ifid_bubble_cycles);
            $display("[PipeStat] ifid_blocked_empty_cycles= %0d", ifid_blocked_empty_cycles);
            $display("[PipeStat] ifid_sum_check=%0d",
                ifid_fire_cycles + ifid_stall_cycles + ifid_bubble_cycles + ifid_blocked_empty_cycles);
            $display("[PipeStat] idex_fire_cycles= %0d", idex_fire_cycles);
            $display("[PipeStat] idex_stall_cycles= %0d", idex_stall_cycles);
            $display("[PipeStat] idex_bubble_cycles= %0d", idex_bubble_cycles);
            $display("[PipeStat] idex_blocked_empty_cycles= %0d", idex_blocked_empty_cycles);
            $display("[PipeStat] idex_sum_check=%0d",
                idex_fire_cycles + idex_stall_cycles + idex_bubble_cycles + idex_blocked_empty_cycles);
            $display("[PipeStat] exmem_fire_cycles= %0d", exmem_fire_cycles);
            $display("[PipeStat] exmem_stall_cycles= %0d", exmem_stall_cycles);
            $display("[PipeStat] exmem_bubble_cycles= %0d", exmem_bubble_cycles);
            $display("[PipeStat] exmem_blocked_empty_cycles= %0d", exmem_blocked_empty_cycles);
            $display("[PipeStat] exmem_sum_check=%0d",
                exmem_fire_cycles + exmem_stall_cycles + exmem_bubble_cycles + exmem_blocked_empty_cycles);
            $display("[PipeStat] memwb_fire_cycles= %0d", memwb_fire_cycles);
            $display("[PipeStat] memwb_stall_cycles= %0d", memwb_stall_cycles);
            $display("[PipeStat] memwb_bubble_cycles= %0d", memwb_bubble_cycles);
            $display("[PipeStat] memwb_blocked_empty_cycles= %0d", memwb_blocked_empty_cycles);
            $display("[PipeStat] memwb_sum_check=%0d",
                memwb_fire_cycles + memwb_stall_cycles + memwb_bubble_cycles + memwb_blocked_empty_cycles);
            $display("[PipeStat] id_stall_cycles= %0d  (load-use / CSR / reg hazard)", id_stall_cycles);
            $display("[PipeStat] if_stall_cycles= %0d  (I$ / fetch queue / req backpressure)", if_stall_cycles);
            $display("[PipeStat] ex_stall_cycles= %0d  (MDU / ALU multi-cycle)", ex_stall_cycles);
            $display("[PipeStat] ms_stall_cycles= %0d  (DCache miss)", ms_stall_cycles);
            $display("[PipeStat] ws_stall_cycles= %0d  (WB back-pressure)", ws_stall_cycles);
            $display("[PipeStat] id_block total=%0d reg_hazard=%0d csr_hazard=%0d other=%0d sum=%0d",
                id_block_cycles, id_block_reg_hazard_cycles, id_block_csr_hazard_cycles,
                id_block_other_cycles,
                id_block_reg_hazard_cycles + id_block_csr_hazard_cycles + id_block_other_cycles);
            $display("[PipeStat] id_block_detail load_use=%0d ex_raw=%0d ms_raw=%0d hidden_raw=%0d csr=%0d",
                id_block_load_use_cycles, id_block_ex_raw_cycles, id_block_ms_raw_cycles,
                id_block_hidden_raw_cycles, id_block_csr_hazard_cycles);
            $display("[PipeStat] ex_block total=%0d mdu_wait=%0d redirect_wait=%0d other=%0d sum=%0d",
                ex_block_cycles, ex_block_mdu_wait_cycles, ex_block_redirect_wait_cycles,
                ex_block_other_cycles,
                ex_block_mdu_wait_cycles + ex_block_redirect_wait_cycles + ex_block_other_cycles);
            $display("[PipeStat] ms_block total=%0d req_phase=%0d resp_phase=%0d other=%0d sum=%0d",
                ms_block_cycles, ms_block_req_phase_cycles, ms_block_resp_phase_cycles,
                ms_block_other_cycles,
                ms_block_req_phase_cycles + ms_block_resp_phase_cycles + ms_block_other_cycles);
            $display("[PipeStat] mem_trace total=%0d load=%0d store=%0d",
                mem_inst_total, mem_load_total, mem_store_total);
            $display("[PipeStat] mem_trace fwd_dep total=%0d load=%0d store=%0d",
                mem_fwd_dep_total, mem_fwd_dep_load, mem_fwd_dep_store);
            $display("[PipeStat] mem_trace req_fire fast=%0d slow=%0d",
                mem_fast_req_fire_total, mem_slow_req_fire_total);
            $display("[PipeStat] mem_trace slow_req_cause fwd_dep=%0d nonfwd=%0d",
                mem_slow_req_fwd_dep_fire_total, mem_slow_req_nonfwd_fire_total);
            $display("[PipeStat] IPC=%0d.%02d",
                commit_count / total_cycles,
                (commit_count * 100 / total_cycles) % 100);
            $display("[PipeStat] CPI=%.2f", total_cycles * 1.0 / (commit_count > 0 ? commit_count : 1));
        end
    end
    `endif
endmodule
`endif
`endif
