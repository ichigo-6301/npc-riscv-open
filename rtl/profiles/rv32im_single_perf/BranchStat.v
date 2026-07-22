`timescale 1ns / 1ps
`include "cpu_top/include/bbus_core_defs.svh"

`ifdef NPC_BRANCH_STAT
module BranchStat #(
    parameter RING_BITS = 6,
    parameter RING_SIZE = 64
)(
    input clk,
    input rst_n,

    input fetch_req_valid,
    input [31:0] fetch_req_pc,
    input fetch_accept_valid,
    input [31:0] fetch_accept_pc,
    input [31:0] fetch_accept_instr,
    input fetch_drop_valid,
    input fetch_drop_redirect,
    input [31:0] fetch_drop_pc,
    input [31:0] fetch_drop_instr,

    input branch_resolve_valid,
    input [2:0] branch_kind,
    input [31:0] branch_pc,
    input [31:0] branch_instr,
    input [31:0] branch_nextpc,
    input branch_redirect,

    input stop_clear_valid,
    input [31:0] stop_clear_pc,
    input [31:0] stop_clear_instr,

    input commit_valid,
    input [31:0] commit_pc,
    input [31:0] commit_instr,
    input [31:0] commit_nextpc,
    input commit_is_ebreak,
    input commit_illegal,

    input ibus_req_valid,
    input ibus_req_ready,
    input ibus_resp_valid,
    input ibus_resp_ready,
    input dbus_req_valid,
    input dbus_req_ready,
    input dbus_resp_valid,
    input dbus_resp_ready
);
    localparam [2:0] BRANCH_DEFAULT = `BBUS_BR_NONE;
    localparam [2:0] BRANCH_J       = `BBUS_BR_J;
    localparam [2:0] BRANCH_JR      = `BBUS_BR_JR;
    localparam [2:0] BRANCH_E       = `BBUS_BR_E;
    localparam [2:0] BRANCH_BEQ     = `BBUS_BR_BEQ;
    localparam [2:0] BRANCH_BNE     = `BBUS_BR_BNE;
    localparam [2:0] BRANCH_BLT     = `BBUS_BR_BLT;
    localparam [2:0] BRANCH_BGE     = `BBUS_BR_BGE;

    reg [31:0] fetch_req_pc_ring [0:RING_SIZE-1];
    reg [63:0] fetch_req_seq_ring [0:RING_SIZE-1];
    reg fetch_req_ring_valid [0:RING_SIZE-1];

    reg [31:0] fetch_accept_pc_ring [0:RING_SIZE-1];
    reg [31:0] fetch_accept_instr_ring [0:RING_SIZE-1];
    reg [63:0] fetch_accept_seq_ring [0:RING_SIZE-1];
    reg fetch_accept_ring_valid [0:RING_SIZE-1];

    reg [63:0] cycle_count;
    reg [63:0] fetch_req_count;
    reg [63:0] fetch_accept_count;
    reg [63:0] fetch_drop_count;
    reg [63:0] fetch_drop_redirect_count;
    reg [63:0] commit_count;
    reg [63:0] cond_branch_total;
    reg [63:0] cond_branch_taken;
    reg [63:0] cond_branch_not_taken;
    reg [63:0] static_nt_mispredict;
    reg [63:0] pred_total;
    reg [63:0] pred_correct;
    reg [63:0] pred_wrong;
    reg [63:0] pred_dir_total;
    reg [63:0] pred_dir_correct;
    reg [63:0] pred_dir_wrong;
    reg [63:0] pred_target_total;
    reg [63:0] pred_target_correct;
    reg [63:0] pred_target_wrong;
    reg [63:0] jal_total;
    reg [63:0] jalr_total;
    reg [63:0] trap_redirect_total;
    reg [63:0] redirect_total;
    reg [63:0] redirect_cond_total;
    reg [63:0] redirect_jal_total;
    reg [63:0] redirect_jalr_total;
    reg [63:0] redirect_trap_total;
    reg [63:0] redirect_cond_accept_total;
    reg [63:0] redirect_jal_accept_total;
    reg [63:0] redirect_jalr_accept_total;
    reg [63:0] redirect_trap_accept_total;
    reg [63:0] redirect_cond_req_total;
    reg [63:0] redirect_jal_req_total;
    reg [63:0] redirect_jalr_req_total;
    reg [63:0] redirect_trap_req_total;
    reg [63:0] wrong_path_accept_total;
    reg [63:0] wrong_path_accept_max;
    reg [63:0] wrong_path_req_total;
    reg [63:0] wrong_path_req_max;
    reg [63:0] wrong_path_drop_est_total;
    reg [63:0] wrong_path_drop_est_max;
    reg [63:0] branch_accept_lookup_miss;
    reg [63:0] branch_req_lookup_miss;
    reg [63:0] stop_clear_total;
    reg [63:0] stop_clear_accept_total;
    reg [63:0] stop_clear_accept_max;
    reg [63:0] stop_clear_req_total;
    reg [63:0] stop_clear_req_max;
    reg [63:0] stop_clear_drop_est_total;
    reg [63:0] stop_clear_drop_est_max;
    reg [63:0] stop_clear_accept_lookup_miss;
    reg [63:0] stop_clear_req_lookup_miss;
    reg [63:0] ibus_req_wait_cycles;
    reg [63:0] ibus_resp_wait_cycles;
    reg [63:0] dbus_req_wait_cycles;
    reg [63:0] dbus_resp_wait_cycles;
    reg printed;

    reg branch_accept_found;
    reg branch_req_found;
    reg [63:0] branch_accept_seq;
    reg [63:0] branch_req_seq;
    reg [63:0] wrong_path_accept_this;
    reg [63:0] wrong_path_req_this;
    reg [63:0] wrong_path_drop_est_this;
    reg stop_accept_found;
    reg stop_req_found;
    reg [63:0] stop_accept_seq;
    reg [63:0] stop_req_seq;
    reg [63:0] stop_clear_accept_this;
    reg [63:0] stop_clear_req_this;
    reg [63:0] stop_clear_drop_est_this;
    reg [63:0] rate_x100;
    reg [63:0] avg_x100;
    integer i;

    wire [63:0] memory_wait_total =
        ibus_req_wait_cycles + ibus_resp_wait_cycles +
        dbus_req_wait_cycles + dbus_resp_wait_cycles;
    wire [63:0] core_cycle_approx =
        (cycle_count > memory_wait_total) ? (cycle_count - memory_wait_total) : 64'd0;

    wire [RING_BITS-1:0] fetch_req_ring_widx = fetch_req_count[RING_BITS-1:0];
    wire [RING_BITS-1:0] fetch_accept_ring_widx = fetch_accept_count[RING_BITS-1:0];
    wire [63:0] fetch_req_seq_next = fetch_req_count + 64'd1;
    wire [63:0] fetch_accept_seq_next = fetch_accept_count + 64'd1;
    wire branch_is_cond =
        (branch_kind == BRANCH_BEQ) ||
        (branch_kind == BRANCH_BNE) ||
        (branch_kind == BRANCH_BLT) ||
        (branch_kind == BRANCH_BGE);
    wire branch_is_control = branch_kind != BRANCH_DEFAULT;

    always @(*) begin
        branch_accept_found = 1'b0;
        branch_accept_seq = 64'd0;
        branch_req_found = 1'b0;
        branch_req_seq = 64'd0;
        stop_accept_found = 1'b0;
        stop_accept_seq = 64'd0;
        stop_req_found = 1'b0;
        stop_req_seq = 64'd0;
        for (i = 0; i < RING_SIZE; i = i + 1) begin
            if (fetch_accept_ring_valid[i] &&
                (fetch_accept_pc_ring[i] == branch_pc) &&
                (fetch_accept_instr_ring[i] == branch_instr) &&
                (!branch_accept_found || (fetch_accept_seq_ring[i] > branch_accept_seq))) begin
                branch_accept_found = 1'b1;
                branch_accept_seq = fetch_accept_seq_ring[i];
            end
            if (fetch_req_ring_valid[i] &&
                (fetch_req_pc_ring[i] == branch_pc) &&
                (!branch_req_found || (fetch_req_seq_ring[i] > branch_req_seq))) begin
                branch_req_found = 1'b1;
                branch_req_seq = fetch_req_seq_ring[i];
            end
            if (fetch_accept_ring_valid[i] &&
                (fetch_accept_pc_ring[i] == stop_clear_pc) &&
                (fetch_accept_instr_ring[i] == stop_clear_instr) &&
                (!stop_accept_found || (fetch_accept_seq_ring[i] > stop_accept_seq))) begin
                stop_accept_found = 1'b1;
                stop_accept_seq = fetch_accept_seq_ring[i];
            end
            if (fetch_req_ring_valid[i] &&
                (fetch_req_pc_ring[i] == stop_clear_pc) &&
                (!stop_req_found || (fetch_req_seq_ring[i] > stop_req_seq))) begin
                stop_req_found = 1'b1;
                stop_req_seq = fetch_req_seq_ring[i];
            end
        end

        if (branch_accept_found && (fetch_accept_count >= branch_accept_seq)) begin
            wrong_path_accept_this = fetch_accept_count - branch_accept_seq;
        end else begin
            wrong_path_accept_this = 64'd0;
        end

        if (branch_req_found && (fetch_req_count >= branch_req_seq)) begin
            wrong_path_req_this = fetch_req_count - branch_req_seq;
        end else begin
            wrong_path_req_this = 64'd0;
        end

        if (wrong_path_req_this > wrong_path_accept_this) begin
            wrong_path_drop_est_this = wrong_path_req_this - wrong_path_accept_this;
        end else begin
            wrong_path_drop_est_this = 64'd0;
        end

        if (stop_accept_found && (fetch_accept_count >= stop_accept_seq)) begin
            stop_clear_accept_this = fetch_accept_count - stop_accept_seq;
        end else begin
            stop_clear_accept_this = 64'd0;
        end

        if (stop_req_found && (fetch_req_count >= stop_req_seq)) begin
            stop_clear_req_this = fetch_req_count - stop_req_seq;
        end else begin
            stop_clear_req_this = 64'd0;
        end

        if (stop_clear_req_this > stop_clear_accept_this) begin
            stop_clear_drop_est_this = stop_clear_req_this - stop_clear_accept_this;
        end else begin
            stop_clear_drop_est_this = 64'd0;
        end
    end

    task print_percent;
        input [255:0] name;
        input [63:0] numerator;
        input [63:0] denominator;
        begin
            if (denominator == 64'd0) begin
                $display("[BranchStat] %0s=N/A", name);
            end else begin
                rate_x100 = (numerator * 64'd10000) / denominator;
                $display("[BranchStat] %0s=%0d.%02d%% (%0d/%0d)",
                    name, rate_x100 / 64'd100, rate_x100 % 64'd100,
                    numerator, denominator);
            end
        end
    endtask

    task print_cpi;
        input [255:0] name;
        input [63:0] cycles;
        begin
            if (commit_count == 64'd0) begin
                $display("[BranchStat] %0s=N/A", name);
            end else begin
                avg_x100 = (cycles * 64'd100) / commit_count;
                $display("[BranchStat] %0s=%0d.%02d (%0d/%0d)",
                    name, avg_x100 / 64'd100, avg_x100 % 64'd100,
                    cycles, commit_count);
            end
        end
    endtask

    task print_stats;
        begin
            $display("[BranchStat] cycles=%0d fetch_req=%0d fetch_accept=%0d fetch_drop=%0d redirect_drop=%0d commit=%0d",
                cycle_count, fetch_req_count, fetch_accept_count,
                fetch_drop_count, fetch_drop_redirect_count, commit_count);
            print_cpi("CPI_total", cycle_count);
            print_cpi("CPI_core_approx", core_cycle_approx);
            $display("[BranchStat] cond_branch total=%0d taken=%0d not_taken=%0d",
                cond_branch_total, cond_branch_taken, cond_branch_not_taken);
            print_percent("static_not_taken_mispredict_rate",
                static_nt_mispredict, cond_branch_total);
            $display("[BranchStat] pred_default_pc4 total=%0d correct=%0d wrong=%0d",
                pred_total, pred_correct, pred_wrong);
            print_percent("pred_default_pc4_wrong_rate", pred_wrong, pred_total);
            $display("[BranchStat] pred_dir cond_total=%0d correct=%0d wrong=%0d",
                pred_dir_total, pred_dir_correct, pred_dir_wrong);
            print_percent("pred_dir_wrong_rate", pred_dir_wrong, pred_dir_total);
            $display("[BranchStat] pred_target total=%0d correct=%0d wrong=%0d",
                pred_target_total, pred_target_correct, pred_target_wrong);
            print_percent("pred_target_wrong_rate", pred_target_wrong, pred_target_total);
            $display("[BranchStat] jump jal=%0d jalr=%0d trap_or_mret=%0d redirect=%0d",
                jal_total, jalr_total, trap_redirect_total, redirect_total);
            $display("[BranchStat] redirect_cause cond=%0d jal=%0d jalr=%0d trap_or_mret=%0d",
                redirect_cond_total, redirect_jal_total, redirect_jalr_total, redirect_trap_total);
            if (redirect_total == 64'd0) begin
                $display("[BranchStat] wrong_path_accept total=%0d avg=N/A max=%0d lookup_miss=%0d",
                    wrong_path_accept_total, wrong_path_accept_max, branch_accept_lookup_miss);
                $display("[BranchStat] wrong_path_req total=%0d avg=N/A max=%0d lookup_miss=%0d drop_est=%0d drop_est_max=%0d",
                    wrong_path_req_total, wrong_path_req_max, branch_req_lookup_miss,
                    wrong_path_drop_est_total, wrong_path_drop_est_max);
            end else begin
                avg_x100 = (wrong_path_accept_total * 64'd100) / redirect_total;
                $display("[BranchStat] wrong_path_accept total=%0d avg=%0d.%02d max=%0d lookup_miss=%0d",
                    wrong_path_accept_total, avg_x100 / 64'd100,
                    avg_x100 % 64'd100, wrong_path_accept_max,
                    branch_accept_lookup_miss);
                avg_x100 = (wrong_path_req_total * 64'd100) / redirect_total;
                $display("[BranchStat] wrong_path_req total=%0d avg=%0d.%02d max=%0d lookup_miss=%0d drop_est=%0d drop_est_max=%0d",
                    wrong_path_req_total, avg_x100 / 64'd100,
                    avg_x100 % 64'd100, wrong_path_req_max,
                    branch_req_lookup_miss, wrong_path_drop_est_total,
                    wrong_path_drop_est_max);
            end
            $display("[BranchStat] redirect_penalty_accept cond=%0d jal=%0d jalr=%0d trap_or_mret=%0d",
                redirect_cond_accept_total, redirect_jal_accept_total,
                redirect_jalr_accept_total, redirect_trap_accept_total);
            $display("[BranchStat] redirect_penalty_req cond=%0d jal=%0d jalr=%0d trap_or_mret=%0d",
                redirect_cond_req_total, redirect_jal_req_total,
                redirect_jalr_req_total, redirect_trap_req_total);
            if (stop_clear_total == 64'd0) begin
                $display("[BranchStat] stop_clear total=%0d accept=N/A max=%0d lookup_miss=%0d req=N/A req_max=%0d req_lookup_miss=%0d drop_est=%0d drop_est_max=%0d",
                    stop_clear_total, stop_clear_accept_max,
                    stop_clear_accept_lookup_miss, stop_clear_req_max,
                    stop_clear_req_lookup_miss, stop_clear_drop_est_total,
                    stop_clear_drop_est_max);
            end else begin
                avg_x100 = (stop_clear_accept_total * 64'd100) / stop_clear_total;
                $display("[BranchStat] stop_clear total=%0d accept=%0d avg=%0d.%02d max=%0d lookup_miss=%0d",
                    stop_clear_total, stop_clear_accept_total,
                    avg_x100 / 64'd100, avg_x100 % 64'd100,
                    stop_clear_accept_max, stop_clear_accept_lookup_miss);
                avg_x100 = (stop_clear_req_total * 64'd100) / stop_clear_total;
                $display("[BranchStat] stop_clear_req total=%0d avg=%0d.%02d max=%0d lookup_miss=%0d drop_est=%0d drop_est_max=%0d",
                    stop_clear_req_total, avg_x100 / 64'd100,
                    avg_x100 % 64'd100, stop_clear_req_max,
                    stop_clear_req_lookup_miss, stop_clear_drop_est_total,
                    stop_clear_drop_est_max);
            end
            $display("[BranchStat] fetch_account commit=%0d extra_req=%0d redirect_req=%0d stop_req=%0d accounted=%0d fetch_req=%0d",
                commit_count,
                wrong_path_req_total + stop_clear_req_total,
                wrong_path_req_total,
                stop_clear_req_total,
                commit_count + wrong_path_req_total + stop_clear_req_total,
                fetch_req_count);
            $display("[BranchStat] fetch_extra accept=%0d req=%0d drop_est=%0d",
                wrong_path_accept_total + stop_clear_accept_total,
                wrong_path_req_total + stop_clear_req_total,
                wrong_path_drop_est_total + stop_clear_drop_est_total);
            $display("[BranchStat] memory_wait ibus_req=%0d ibus_resp=%0d dbus_req=%0d dbus_resp=%0d total=%0d",
                ibus_req_wait_cycles, ibus_resp_wait_cycles,
                dbus_req_wait_cycles, dbus_resp_wait_cycles, memory_wait_total);
            $display("[BranchStat] halt pc=0x%08x instr=0x%08x nextpc=0x%08x illegal=%0d",
                commit_pc, commit_instr, commit_nextpc, commit_illegal);
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count = 64'd0;
            fetch_req_count = 64'd0;
            fetch_accept_count = 64'd0;
            fetch_drop_count = 64'd0;
            fetch_drop_redirect_count = 64'd0;
            commit_count = 64'd0;
            cond_branch_total = 64'd0;
            cond_branch_taken = 64'd0;
            cond_branch_not_taken = 64'd0;
            static_nt_mispredict = 64'd0;
            pred_total = 64'd0;
            pred_correct = 64'd0;
            pred_wrong = 64'd0;
            pred_dir_total = 64'd0;
            pred_dir_correct = 64'd0;
            pred_dir_wrong = 64'd0;
            pred_target_total = 64'd0;
            pred_target_correct = 64'd0;
            pred_target_wrong = 64'd0;
            jal_total = 64'd0;
            jalr_total = 64'd0;
            trap_redirect_total = 64'd0;
            redirect_total = 64'd0;
            redirect_cond_total = 64'd0;
            redirect_jal_total = 64'd0;
            redirect_jalr_total = 64'd0;
            redirect_trap_total = 64'd0;
            redirect_cond_accept_total = 64'd0;
            redirect_jal_accept_total = 64'd0;
            redirect_jalr_accept_total = 64'd0;
            redirect_trap_accept_total = 64'd0;
            redirect_cond_req_total = 64'd0;
            redirect_jal_req_total = 64'd0;
            redirect_jalr_req_total = 64'd0;
            redirect_trap_req_total = 64'd0;
            wrong_path_accept_total = 64'd0;
            wrong_path_accept_max = 64'd0;
            wrong_path_req_total = 64'd0;
            wrong_path_req_max = 64'd0;
            wrong_path_drop_est_total = 64'd0;
            wrong_path_drop_est_max = 64'd0;
            branch_accept_lookup_miss = 64'd0;
            branch_req_lookup_miss = 64'd0;
            stop_clear_total = 64'd0;
            stop_clear_accept_total = 64'd0;
            stop_clear_accept_max = 64'd0;
            stop_clear_req_total = 64'd0;
            stop_clear_req_max = 64'd0;
            stop_clear_drop_est_total = 64'd0;
            stop_clear_drop_est_max = 64'd0;
            stop_clear_accept_lookup_miss = 64'd0;
            stop_clear_req_lookup_miss = 64'd0;
            ibus_req_wait_cycles = 64'd0;
            ibus_resp_wait_cycles = 64'd0;
            dbus_req_wait_cycles = 64'd0;
            dbus_resp_wait_cycles = 64'd0;
            printed = 1'b0;
            for (i = 0; i < RING_SIZE; i = i + 1) begin
                fetch_req_pc_ring[i] = 32'b0;
                fetch_req_seq_ring[i] = 64'd0;
                fetch_req_ring_valid[i] = 1'b0;
                fetch_accept_pc_ring[i] = 32'b0;
                fetch_accept_instr_ring[i] = 32'b0;
                fetch_accept_seq_ring[i] = 64'd0;
                fetch_accept_ring_valid[i] = 1'b0;
            end
        end else if (!printed) begin
            cycle_count = cycle_count + 64'd1;

            if (fetch_req_valid) begin
                fetch_req_pc_ring[fetch_req_ring_widx] = fetch_req_pc;
                fetch_req_seq_ring[fetch_req_ring_widx] = fetch_req_seq_next;
                fetch_req_ring_valid[fetch_req_ring_widx] = 1'b1;
                fetch_req_count = fetch_req_seq_next;
            end

            if (fetch_accept_valid) begin
                fetch_accept_pc_ring[fetch_accept_ring_widx] = fetch_accept_pc;
                fetch_accept_instr_ring[fetch_accept_ring_widx] = fetch_accept_instr;
                fetch_accept_seq_ring[fetch_accept_ring_widx] = fetch_accept_seq_next;
                fetch_accept_ring_valid[fetch_accept_ring_widx] = 1'b1;
                fetch_accept_count = fetch_accept_seq_next;
            end

            if (fetch_drop_valid) begin
                fetch_drop_count = fetch_drop_count + 64'd1;
                if (fetch_drop_redirect) begin
                    fetch_drop_redirect_count = fetch_drop_redirect_count + 64'd1;
                end
`ifdef NPC_BRANCH_STAT_VERBOSE
                $display("[BranchStat] drop pc=0x%08x instr=0x%08x redirect=%0d",
                    fetch_drop_pc, fetch_drop_instr, fetch_drop_redirect);
`endif
            end

            if (commit_valid) begin
                commit_count = commit_count + 64'd1;
            end

            if (branch_resolve_valid && branch_is_control) begin
                pred_total = pred_total + 64'd1;
                if (branch_redirect) begin
                    pred_wrong = pred_wrong + 64'd1;
                end else begin
                    pred_correct = pred_correct + 64'd1;
                end

                if (branch_is_cond) begin
                    pred_dir_total = pred_dir_total + 64'd1;
                    cond_branch_total = cond_branch_total + 64'd1;
                    if (branch_redirect) begin
                        pred_dir_wrong = pred_dir_wrong + 64'd1;
                        cond_branch_taken = cond_branch_taken + 64'd1;
                        static_nt_mispredict = static_nt_mispredict + 64'd1;
                    end else begin
                        pred_dir_correct = pred_dir_correct + 64'd1;
                        cond_branch_not_taken = cond_branch_not_taken + 64'd1;
                    end
                end else if (branch_kind == BRANCH_J) begin
                    jal_total = jal_total + 64'd1;
                end else if (branch_kind == BRANCH_JR) begin
                    jalr_total = jalr_total + 64'd1;
                end else if (branch_kind == BRANCH_E) begin
                    trap_redirect_total = trap_redirect_total + 64'd1;
                end

                if (branch_redirect) begin
                    pred_target_total = pred_target_total + 64'd1;
                    pred_target_wrong = pred_target_wrong + 64'd1;
                    redirect_total = redirect_total + 64'd1;
                    if (branch_is_cond) begin
                        redirect_cond_total = redirect_cond_total + 64'd1;
                    end else if (branch_kind == BRANCH_J) begin
                        redirect_jal_total = redirect_jal_total + 64'd1;
                    end else if (branch_kind == BRANCH_JR) begin
                        redirect_jalr_total = redirect_jalr_total + 64'd1;
                    end else if (branch_kind == BRANCH_E) begin
                        redirect_trap_total = redirect_trap_total + 64'd1;
                    end
                    if (branch_accept_found) begin
                        wrong_path_accept_total = wrong_path_accept_total + wrong_path_accept_this;
                        if (branch_is_cond) begin
                            redirect_cond_accept_total = redirect_cond_accept_total + wrong_path_accept_this;
                        end else if (branch_kind == BRANCH_J) begin
                            redirect_jal_accept_total = redirect_jal_accept_total + wrong_path_accept_this;
                        end else if (branch_kind == BRANCH_JR) begin
                            redirect_jalr_accept_total = redirect_jalr_accept_total + wrong_path_accept_this;
                        end else if (branch_kind == BRANCH_E) begin
                            redirect_trap_accept_total = redirect_trap_accept_total + wrong_path_accept_this;
                        end
                        if (wrong_path_accept_this > wrong_path_accept_max) begin
                            wrong_path_accept_max = wrong_path_accept_this;
                        end
                    end else begin
                        branch_accept_lookup_miss = branch_accept_lookup_miss + 64'd1;
                    end

                    if (branch_req_found) begin
                        wrong_path_req_total = wrong_path_req_total + wrong_path_req_this;
                        if (branch_is_cond) begin
                            redirect_cond_req_total = redirect_cond_req_total + wrong_path_req_this;
                        end else if (branch_kind == BRANCH_J) begin
                            redirect_jal_req_total = redirect_jal_req_total + wrong_path_req_this;
                        end else if (branch_kind == BRANCH_JR) begin
                            redirect_jalr_req_total = redirect_jalr_req_total + wrong_path_req_this;
                        end else if (branch_kind == BRANCH_E) begin
                            redirect_trap_req_total = redirect_trap_req_total + wrong_path_req_this;
                        end
                        wrong_path_drop_est_total = wrong_path_drop_est_total + wrong_path_drop_est_this;
                        if (wrong_path_req_this > wrong_path_req_max) begin
                            wrong_path_req_max = wrong_path_req_this;
                        end
                        if (wrong_path_drop_est_this > wrong_path_drop_est_max) begin
                            wrong_path_drop_est_max = wrong_path_drop_est_this;
                        end
                    end else begin
                        branch_req_lookup_miss = branch_req_lookup_miss + 64'd1;
                    end
`ifdef NPC_BRANCH_STAT_VERBOSE
                    $display("[BranchStat] redirect pc=0x%08x instr=0x%08x target=0x%08x wrong_path_accept=%0d accept_found=%0d wrong_path_req=%0d req_found=%0d drop_est=%0d",
                        branch_pc, branch_instr, branch_nextpc,
                        wrong_path_accept_this, branch_accept_found,
                        wrong_path_req_this, branch_req_found,
                        wrong_path_drop_est_this);
`endif
                end
            end

            if (stop_clear_valid) begin
                stop_clear_total = stop_clear_total + 64'd1;
                if (stop_accept_found) begin
                    stop_clear_accept_total = stop_clear_accept_total + stop_clear_accept_this;
                    if (stop_clear_accept_this > stop_clear_accept_max) begin
                        stop_clear_accept_max = stop_clear_accept_this;
                    end
                end else begin
                    stop_clear_accept_lookup_miss = stop_clear_accept_lookup_miss + 64'd1;
                end

                if (stop_req_found) begin
                    stop_clear_req_total = stop_clear_req_total + stop_clear_req_this;
                    stop_clear_drop_est_total = stop_clear_drop_est_total + stop_clear_drop_est_this;
                    if (stop_clear_req_this > stop_clear_req_max) begin
                        stop_clear_req_max = stop_clear_req_this;
                    end
                    if (stop_clear_drop_est_this > stop_clear_drop_est_max) begin
                        stop_clear_drop_est_max = stop_clear_drop_est_this;
                    end
                end else begin
                    stop_clear_req_lookup_miss = stop_clear_req_lookup_miss + 64'd1;
                end
`ifdef NPC_BRANCH_STAT_VERBOSE
                $display("[BranchStat] stop_clear pc=0x%08x instr=0x%08x accept=%0d accept_found=%0d req=%0d req_found=%0d drop_est=%0d",
                    stop_clear_pc, stop_clear_instr,
                    stop_clear_accept_this, stop_accept_found,
                    stop_clear_req_this, stop_req_found,
                    stop_clear_drop_est_this);
`endif
            end

            if (ibus_req_valid && !ibus_req_ready) begin
                ibus_req_wait_cycles = ibus_req_wait_cycles + 64'd1;
            end
            if (ibus_resp_ready && !ibus_resp_valid) begin
                ibus_resp_wait_cycles = ibus_resp_wait_cycles + 64'd1;
            end
            if (dbus_req_valid && !dbus_req_ready) begin
                dbus_req_wait_cycles = dbus_req_wait_cycles + 64'd1;
            end
            if (dbus_resp_ready && !dbus_resp_valid) begin
                dbus_resp_wait_cycles = dbus_resp_wait_cycles + 64'd1;
            end

            if (commit_valid && (commit_is_ebreak || commit_illegal)) begin
                print_stats();
                printed = 1'b1;
            end
        end
    end
endmodule
`endif
