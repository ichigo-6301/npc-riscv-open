# Academic internal reg-to-reg constraint. Integration-level IO timing is not claimed.
if {![info exists ::env(NPC_ASIC_CLOCK_PERIOD_NS)]} {
  error "Missing NPC_ASIC_CLOCK_PERIOD_NS"
}
if {![info exists ::env(NPC_ASIC_CLOCK_PORT)]} {
  error "Missing NPC_ASIC_CLOCK_PORT"
}
if {![info exists ::env(NPC_ASIC_RESET_PORT)]} {
  error "Missing NPC_ASIC_RESET_PORT"
}
set npc_clock_period $::env(NPC_ASIC_CLOCK_PERIOD_NS)
set npc_clock_port $::env(NPC_ASIC_CLOCK_PORT)
create_clock -name npc_clk -period $npc_clock_period [get_ports $npc_clock_port]
set_clock_uncertainty -setup 0.100 [get_clocks npc_clk]
set_clock_uncertainty -hold 0.000 [get_clocks npc_clk]

# D7 intentionally measures the internal register-to-register implementation.
# External memory/commit IO timing is an integration responsibility and stays
# visible as an explicit caveat rather than receiving invented board delays.
set npc_reset_port $::env(NPC_ASIC_RESET_PORT)
set npc_async_inputs [remove_from_collection [all_inputs] \
  [get_ports [list $npc_clock_port $npc_reset_port]]]
if {[sizeof_collection $npc_async_inputs] > 0} {
  set_false_path -from $npc_async_inputs
}
set_false_path -from [get_ports $npc_reset_port]
if {[sizeof_collection [all_outputs]] > 0} {
  set_false_path -to [all_outputs]
}

set_max_transition 0.20 [current_design]
set_max_fanout 32 [current_design]
