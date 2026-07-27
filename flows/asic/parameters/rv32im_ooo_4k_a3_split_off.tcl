# A3 source control: production mechanisms retained, A3 implementation off.
source [file join [file dirname [info script]] rv32im_ooo_4k_legacy.tcl]
lappend npc_asic_elaboration_parameters \
  FRONTEND_CAUSAL_REQUEST_CUT_ENABLE=0 \
  STABLE_ENTRY_IQ_ENABLE=0 \
  IQ_SPLIT_PAYLOAD_READ_ENABLE=0 \
  ROB_INDEXED_SERVICE_LEVEL=0
