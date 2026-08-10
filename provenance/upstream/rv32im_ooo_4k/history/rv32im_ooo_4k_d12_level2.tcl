# D12 acyclic performance paths, enabled only after Level 1 structural closure.
source [file join [file dirname [info script]] rv32im_ooo_4k_d12_level1.tcl]
lappend npc_asic_elaboration_parameters \
  CAUSAL_OWNERSHIP_LEVEL=2
