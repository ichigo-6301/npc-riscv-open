# D12 strict causal ownership backbone on the D10 line32 cache candidate.
source [file join [file dirname [info script]] rv32im_ooo_4k_d10_line32.tcl]
lappend npc_asic_elaboration_parameters \
  LQ_RESPONSE_CAUSAL_CUT_ENABLE=0 \
  STABLE_ENTRY_IQ_ENABLE=1 \
  IQ_SPLIT_PAYLOAD_READ_ENABLE=1 \
  ROB_INDEXED_SERVICE_LEVEL=1 \
  CAUSAL_OWNERSHIP_LEVEL=1
