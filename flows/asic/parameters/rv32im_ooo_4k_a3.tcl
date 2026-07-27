# A3 source trial: O3 stable IQ, retained balanced selector, split payload read.
source [file join [file dirname [info script]] rv32im_ooo_4k_legacy.tcl]
lappend npc_asic_elaboration_parameters \
  FRONTEND_CAUSAL_REQUEST_CUT_ENABLE=0 \
  STABLE_ENTRY_IQ_ENABLE=1 \
  IQ_SPLIT_PAYLOAD_READ_ENABLE=1 \
  ROB_INDEXED_SERVICE_LEVEL=1
