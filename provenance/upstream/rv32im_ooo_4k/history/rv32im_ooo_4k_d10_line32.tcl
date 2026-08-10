# D10 4 KiB sectored D-cache with 32-byte replacement lines.
source [file join [file dirname [info script]] rv32im_ooo_4k_legacy.tcl]
lappend npc_asic_elaboration_parameters \
  DATA_SECTORED_CACHE_ENABLE=1 \
  DATA_SECTOR_LINE_BYTES=32 \
  DATA_SECTOR_WAY_COUNT=2 \
  DATA_CACHE_CAPACITY_BYTES=4096
