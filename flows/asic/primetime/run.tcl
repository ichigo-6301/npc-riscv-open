proc require_env {name} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "Missing required environment variable: $name"
  }
  return $::env($name)
}

proc require_file {path label} {
  if {![file isfile $path]} {error "Missing $label: $path"}
}

proc worst_slack {delay_type} {
  set paths [get_timing_paths -delay_type $delay_type -max_paths 1]
  if {[sizeof_collection $paths] == 0} {return NA}
  return [get_attribute [index_collection $paths 0] slack]
}

proc negative_path_stats {delay_type} {
  set paths [get_timing_paths -delay_type $delay_type \
    -slack_lesser_than 0.0 -max_paths 200000]
  set count 0
  set tns 0.0
  foreach_in_collection path $paths {
    set slack [get_attribute $path slack]
    if {$slack < 0.0} {
      incr count
      set tns [expr {$tns + $slack}]
    }
  }
  return [list $count $tns]
}

proc violation_count {path} {
  if {![file isfile $path]} {return -1}
  set fh [open $path r]
  set text [read $fh]
  close $fh
  return [regexp -all {\(VIOLATED\)} $text]
}

set top [require_env NPC_ASIC_TOP]
set output_dir [file normalize [require_env NPC_ASIC_OUTPUT_DIR]]
set netlist [file normalize [require_env NPC_ASIC_POSTROUTE_NETLIST]]
set sdc [file normalize [require_env NPC_ASIC_POSTROUTE_SDC]]
set spef [file normalize [require_env NPC_ASIC_POSTROUTE_SPEF]]
set expected_period [require_env NPC_ASIC_CLOCK_PERIOD_NS]
set memory_mode [require_env NPC_ASIC_MEMORY_MODE]
set expected_macro_count [require_env NPC_ASIC_EXPECTED_MACRO_COUNT]
set expected_macro_spec ""
if {[info exists ::env(NPC_ASIC_EXPECTED_MACROS)]} {
  set expected_macro_spec $::env(NPC_ASIC_EXPECTED_MACROS)
}
set macro_minimum_period_spec ""
if {[info exists ::env(NPC_ASIC_MACRO_MIN_PERIODS)]} {
  set macro_minimum_period_spec $::env(NPC_ASIC_MACRO_MIN_PERIODS)
}
file mkdir $output_dir
source [file normalize [require_env NPC_ASIC_PRIMETIME_SETUP]]

foreach {path label} [list \
  $npc_asic_stdcell_db "standard-cell DB" \
  $netlist "post-route netlist" \
  $sdc "post-route SDC" \
  $spef "post-route SPEF"] {
  require_file $path $label
}

set timing_libraries [list $npc_asic_stdcell_db]
if {[info exists ::env(NPC_ASIC_MACRO_DBS)] && $::env(NPC_ASIC_MACRO_DBS) ne ""} {
  foreach macro_db [split $::env(NPC_ASIC_MACRO_DBS) ":"] {
    set macro_db [file normalize $macro_db]
    require_file $macro_db "macro DB"
    lappend timing_libraries $macro_db
  }
}
set library_directories [list]
foreach library $timing_libraries {
  lappend library_directories [file dirname $library]
}
set_app_var search_path [concat $library_directories [get_app_var search_path]]
set_app_var target_library [list $npc_asic_stdcell_db]
set_app_var link_path [concat "*" $timing_libraries]
read_verilog $netlist
current_design $top
set link_ok [link_design $top]
if {!$link_ok} {error "PrimeTime link_design failed"}

set expected_macro_refs [list]
array set expected_macro_ref_count {}
foreach item [split $expected_macro_spec ","] {
  if {$item eq ""} {continue}
  set fields [split $item "="]
  if {[llength $fields] != 2} {error "Malformed expected macro contract: $item"}
  set ref [lindex $fields 0]
  set count [lindex $fields 1]
  lappend expected_macro_refs $ref
  set expected_macro_ref_count($ref) $count
  if {[sizeof_collection [get_lib_cells -quiet */$ref]] == 0} {
    error "PrimeTime link libraries do not contain expected macro $ref"
  }
}
set macro_count 0
array set linked_macro_ref_count {}
foreach ref $expected_macro_refs {set linked_macro_ref_count($ref) 0}
foreach_in_collection cell [get_cells -hierarchical -quiet *] {
  set ref [get_attribute $cell ref_name]
  if {[lsearch -exact $expected_macro_refs $ref] >= 0} {
    incr macro_count
    incr linked_macro_ref_count($ref)
  }
}
foreach ref $expected_macro_refs {
  if {$linked_macro_ref_count($ref) != $expected_macro_ref_count($ref)} {
    error "PrimeTime macro count mismatch for $ref: expected $expected_macro_ref_count($ref), got $linked_macro_ref_count($ref)"
  }
}
if {$macro_count != $expected_macro_count} {
  error "PrimeTime total macro count mismatch: expected $expected_macro_count, got $macro_count"
}
set read_sdc_ok 1
if {[catch {read_sdc $sdc} message]} {
  set read_sdc_ok 0
  error "PrimeTime read_sdc failed: $message"
}
set read_parasitics_ok 1
if {[catch {read_parasitics $spef} message]} {
  set read_parasitics_ok 0
  error "PrimeTime read_parasitics failed: $message"
}

set clocks [get_clocks -quiet npc_clk]
if {[sizeof_collection $clocks] != 1} {error "Expected exactly one npc_clk"}
set actual_period [get_attribute $clocks period]
if {[expr {abs($actual_period - $expected_period)}] > 0.0001} {
  error "Clock period mismatch: expected $expected_period, got $actual_period"
}

update_timing -full
set check_timing_ok 1
if {[catch {redirect -file "$output_dir/check_timing.rpt" {
  check_timing -verbose
}} message]} {
  set check_timing_ok 0
  set fh [open "$output_dir/check_timing.rpt" w]
  puts $fh "check_timing failed: $message"
  close $fh
}
redirect -file "$output_dir/clock.rpt" {report_clock}
redirect -file "$output_dir/setup_timing.rpt" {
  report_timing -delay_type max -slack_lesser_than 999 -max_paths 20 -path full
}
redirect -file "$output_dir/hold_timing.rpt" {
  report_timing -delay_type min -slack_lesser_than 999 -max_paths 20 -path full
}
redirect -file "$output_dir/setup_summary.rpt" {report_global_timing -delay_type max}
redirect -file "$output_dir/hold_summary.rpt" {report_global_timing -delay_type min}
redirect -file "$output_dir/constraint_violations.rpt" {report_constraint -all_violators}
redirect -file "$output_dir/constraints_max_transition.rpt" {
  report_constraint -max_transition -all_violators
}
redirect -file "$output_dir/constraints_max_capacitance.rpt" {
  report_constraint -max_capacitance -all_violators
}
redirect -file "$output_dir/constraints_max_fanout.rpt" {
  report_constraint -max_fanout -all_violators
}
redirect -file "$output_dir/constraints_min_period.rpt" {
  report_constraint -min_period -all_violators
}
redirect -file "$output_dir/macro_instances.rpt" {
  echo "memory_mode=$memory_mode"
  echo "expected_total=$expected_macro_count"
  echo "linked_total=$macro_count"
  echo "minimum_period_contract=$macro_minimum_period_spec"
  foreach ref $expected_macro_refs {
    echo "ref=$ref expected=$expected_macro_ref_count($ref) linked=$linked_macro_ref_count($ref)"
  }
  foreach_in_collection cell [get_cells -hierarchical -quiet *] {
    set ref [get_attribute $cell ref_name]
    if {[lsearch -exact $expected_macro_refs $ref] >= 0} {
      echo "instance=[get_object_name $cell] ref=$ref"
    }
  }
}
redirect -file "$output_dir/constraints_min_pulse_width.rpt" {
  report_constraint -min_pulse_width -all_violators
}
redirect -file "$output_dir/analysis_coverage.rpt" {report_analysis_coverage}
redirect -file "$output_dir/qor.rpt" {report_qor}
if {[catch {redirect -file "$output_dir/parasitic_annotation.rpt" {
  report_annotated_parasitics -check
}} message]} {
  set fh [open "$output_dir/parasitic_annotation.rpt" w]
  puts $fh "report_annotated_parasitics unavailable: $message"
  close $fh
}
set registers [all_registers]
set clocked_registers [all_registers -clock npc_clk]
set register_count [sizeof_collection $registers]
set clocked_register_count [sizeof_collection $clocked_registers]
set unclocked_sync_endpoint_count [expr {$register_count - $clocked_register_count}]
set synchronous_endpoint_coverage_percent 0.0
if {$register_count > 0} {
  set synchronous_endpoint_coverage_percent \
    [expr {100.0 * $clocked_register_count / $register_count}]
}
set setup_wns [worst_slack max]
set hold_wns [worst_slack min]
set setup_stats [negative_path_stats max]
set hold_stats [negative_path_stats min]
set max_transition_count [violation_count "$output_dir/constraints_max_transition.rpt"]
set max_capacitance_count [violation_count "$output_dir/constraints_max_capacitance.rpt"]
set max_fanout_count [violation_count "$output_dir/constraints_max_fanout.rpt"]
set min_period_count [violation_count "$output_dir/constraints_min_period.rpt"]
set min_pulse_width_count [violation_count "$output_dir/constraints_min_pulse_width.rpt"]
redirect -file "$output_dir/run_contract.txt" {
  echo "top=$top"
  echo "analysis=postroute_extracted_internal_timing"
  echo "memory_mode=$memory_mode"
  echo "expected_macro_count=$expected_macro_count"
  echo "macro_count=$macro_count"
  echo "macro_minimum_period_contract=$macro_minimum_period_spec"
  echo "clock_period_ns=$actual_period"
  echo "clock_frequency_mhz=[expr {1000.0 / $actual_period}]"
  echo "link_ok=$link_ok"
  echo "read_sdc_ok=$read_sdc_ok"
  echo "read_parasitics_ok=$read_parasitics_ok"
  echo "check_timing_ok=$check_timing_ok"
  echo "setup_wns_ns=$setup_wns"
  echo "setup_tns_ns=[lindex $setup_stats 1]"
  echo "setup_violation_count=[lindex $setup_stats 0]"
  echo "hold_wns_ns=$hold_wns"
  echo "hold_tns_ns=[lindex $hold_stats 1]"
  echo "hold_violation_count=[lindex $hold_stats 0]"
  echo "register_count=$register_count"
  echo "clocked_register_count=$clocked_register_count"
  echo "unclocked_sync_endpoint_count=$unclocked_sync_endpoint_count"
  echo "synchronous_endpoint_coverage_percent=$synchronous_endpoint_coverage_percent"
  echo "max_transition_violation_count=$max_transition_count"
  echo "max_capacitance_violation_count=$max_capacitance_count"
  echo "max_fanout_violation_count=$max_fanout_count"
  echo "min_period_violation_count=$min_period_count"
  echo "min_pulse_width_violation_count=$min_pulse_width_count"
}
puts "INFO: PrimeTime post-route STA completed"
quit
