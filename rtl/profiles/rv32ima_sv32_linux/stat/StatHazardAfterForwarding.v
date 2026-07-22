`timescale 1ns / 1ps

`ifdef NPC_USE_DPI
`ifdef NPC_PIPE_STAT
module StatHazardAfterForwarding (
    input [63:0] raw_alu_ex,
    input [63:0] raw_alu_mem,
    input [63:0] raw_load_mem,
    input [63:0] raw_load_wb,
    input [63:0] raw_muldiv,
    input [63:0] load_lsu_pending_cycles,
    input [63:0] load_hit_no_forward_wait
);
    task print_stats;
        begin
            $display("[HazardAfterForwarding] raw_alu_ex=%0d raw_alu_mem=%0d raw_load_mem=%0d raw_load_wb=%0d raw_muldiv=%0d load_lsu_pending_cycles=%0d load_hit_no_forward_wait=%0d",
                raw_alu_ex, raw_alu_mem, raw_load_mem, raw_load_wb,
                raw_muldiv, load_lsu_pending_cycles,
                load_hit_no_forward_wait);
        end
    endtask
endmodule
`endif
`endif
