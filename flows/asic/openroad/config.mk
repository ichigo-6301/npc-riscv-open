export PLATFORM = nangate45
export DESIGN_NICKNAME = $(NPC_ASIC_DESIGN_NICKNAME)
export DESIGN_NAME = $(NPC_ASIC_TOP)

# Preserve the Design Compiler mapping. synth_preamble.tcl copies this file to
# 1_2_yosys.v; the runner checks byte identity after ORFS returns.
export SYNTH_NETLIST_FILES = $(NPC_ASIC_MAPPED_NETLIST)
export VERILOG_FILES =
export SDC_FILE = $(NPC_ASIC_PNR_SDC)

export DIE_AREA = $(NPC_ASIC_DIE_AREA)
export CORE_AREA = $(NPC_ASIC_CORE_AREA)
export PLACE_DENSITY = $(NPC_ASIC_PLACE_DENSITY)

export MIN_ROUTING_LAYER = metal2
export MIN_CLK_ROUTING_LAYER = metal4
export MAX_ROUTING_LAYER = metal10
export TNS_END_PERCENT = 100
export SETUP_SLACK_MARGIN = 0.0
export HOLD_SLACK_MARGIN = 0.0
