# Design Compiler can emit constant nets at multiple hierarchy levels that
# OpenDB classifies as POWER/GROUND. They are ordinary routed signals, not
# members of the PDN.
set block [ord::get_db_block]
if {[string equal $block "NULL"]} {
  error "D8 constant-net audit requires a loaded OpenDB block"
}
if {![info exists ::env(NPC_ASIC_CONSTANT_NET_REPORT)] ||
    $::env(NPC_ASIC_CONSTANT_NET_REPORT) eq ""} {
  error "NPC_ASIC_CONSTANT_NET_REPORT is required"
}

set found 0
set normalized 0
set already_signal 0
set report [open $::env(NPC_ASIC_CONSTANT_NET_REPORT) w]
puts $report "schema=npc-riscv-open/d8-dc-constant-net-normalization-v2"

set constant_names {}
foreach net [$block getNets] {
  set name [$net getName]
  if {[regexp {(^|/)(one_|zero_)$} $name]} {
    lappend constant_names $name
  }
}

foreach name [lsort -dictionary $constant_names] {
  set net [$block findNet $name]
  if {[string equal $net "NULL"]} {
    close $report
    error "DC constant net disappeared during audit: $name"
  }
  incr found
  set before [$net getSigType]
  if {$before eq "POWER" || $before eq "GROUND"} {
    $net setSigType SIGNAL
    incr normalized
  } elseif {$before eq "SIGNAL"} {
    incr already_signal
  } else {
    close $report
    error "Unexpected signal type $before for DC constant net $name"
  }
  set after [$net getSigType]
  if {$after ne "SIGNAL"} {
    close $report
    error "Failed to normalize DC constant net $name: $before -> $after"
  }
  puts $report "net=$name before=$before after=$after"
}

puts $report "found=$found"
puts $report "normalized=$normalized"
puts $report "already_signal=$already_signal"
close $report
puts "D8 constant-net audit: found=$found normalized=$normalized already_signal=$already_signal"
