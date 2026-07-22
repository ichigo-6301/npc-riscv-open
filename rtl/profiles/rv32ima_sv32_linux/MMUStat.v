`timescale 1ns / 1ps

`ifdef NPC_MMU_STAT
module MMUStat (
    input clk,
    input rst_n,
    input commit_valid,
    input commit_is_ebreak,
    input commit_illegal,

    input [63:0] if_req_count,
    input [63:0] if_bypass_count,
    input [63:0] if_translate_count,
    input [63:0] if_ptw_cycle_count,
    input [63:0] if_ptw_l1_read_count,
    input [63:0] if_ptw_l0_read_count,
    input [63:0] if_page_fault_count,
    input [63:0] if_ptw_walk_start_count,
    input [63:0] if_ptw_walk_done_count,
    input [63:0] if_ptw_walk_fault_count,
    input [63:0] if_tlb_hit_count,
    input [63:0] if_tlb_miss_count,

    input [63:0] lsu_req_count,
    input [63:0] lsu_bypass_count,
    input [63:0] lsu_translate_count,
    input [63:0] lsu_ptw_cycle_count,
    input [63:0] lsu_ptw_l1_read_count,
    input [63:0] lsu_ptw_l0_read_count,
    input [63:0] lsu_page_fault_count,
    input [63:0] lsu_ptw_walk_start_count,
    input [63:0] lsu_ptw_walk_done_count,
    input [63:0] lsu_ptw_walk_fault_count,
    input [63:0] lsu_tlb_hit_count,
    input [63:0] lsu_tlb_miss_count
);
    reg printed;
    reg [63:0] avg_cycle;

    task print_ptw_walk;
        input [255:0] name;
        input [63:0] start_count;
        input [63:0] done_count;
        input [63:0] fault_count;
        input [63:0] cycle_count;
        begin
            if (done_count == 64'd0) begin
                $display("[MMUStat] %0s start=%0d done=%0d fault=%0d avg_cycle=N/A",
                    name, start_count, done_count, fault_count);
            end else begin
                avg_cycle = cycle_count / done_count;
                $display("[MMUStat] %0s start=%0d done=%0d fault=%0d avg_cycle=%0d",
                    name, start_count, done_count, fault_count, avg_cycle);
            end
        end
    endtask

    task print_stats;
        begin
            $display("[MMUStat] if_req=%0d if_bypass=%0d if_translate=%0d if_ptw_cycle=%0d",
                if_req_count, if_bypass_count, if_translate_count, if_ptw_cycle_count);
            $display("[MMUStat] if_l1_read=%0d if_l0_read=%0d if_page_fault=%0d if_tlb_hit=%0d if_tlb_miss=%0d",
                if_ptw_l1_read_count, if_ptw_l0_read_count, if_page_fault_count,
                if_tlb_hit_count, if_tlb_miss_count);
            print_ptw_walk("if_ptw_walk", if_ptw_walk_start_count, if_ptw_walk_done_count,
                if_ptw_walk_fault_count, if_ptw_cycle_count);
            $display("[MMUStat] lsu_req=%0d lsu_bypass=%0d lsu_translate=%0d lsu_ptw_cycle=%0d",
                lsu_req_count, lsu_bypass_count, lsu_translate_count, lsu_ptw_cycle_count);
            $display("[MMUStat] lsu_l1_read=%0d lsu_l0_read=%0d lsu_page_fault=%0d lsu_tlb_hit=%0d lsu_tlb_miss=%0d",
                lsu_ptw_l1_read_count, lsu_ptw_l0_read_count, lsu_page_fault_count,
                lsu_tlb_hit_count, lsu_tlb_miss_count);
            print_ptw_walk("lsu_ptw_walk", lsu_ptw_walk_start_count, lsu_ptw_walk_done_count,
                lsu_ptw_walk_fault_count, lsu_ptw_cycle_count);
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            printed <= 1'b0;
        end else if (!printed && commit_valid && (commit_is_ebreak || commit_illegal)) begin
            print_stats();
            printed <= 1'b1;
        end
    end
endmodule
`endif
