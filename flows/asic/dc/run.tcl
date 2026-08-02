proc require_env {name} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "Missing required environment variable: $name"
  }
  return $::env($name)
}

proc fail {message} {
  echo "ERROR: $message"
  exit 1
}

proc worst_slack {delay_type} {
  set paths [get_timing_paths -delay_type $delay_type -max_paths 1]
  if {[sizeof_collection $paths] == 0} {return NA}
  return [get_attribute [index_collection $paths 0] slack]
}

proc negative_path_stats {delay_type} {
  set paths [get_timing_paths -delay_type $delay_type \
    -slack_lesser_than 0.0 -max_paths 100000]
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

proc collection_count_or_invalid {script} {
  if {[catch {set collection [uplevel 1 $script]} message]} {
    echo "ERROR: diagnostic collection query failed: $message"
    return -1
  }
  return [sizeof_collection $collection]
}

set root [file normalize [require_env NPC_ASIC_ROOT]]
set profile [require_env NPC_ASIC_PROFILE]
set top [require_env NPC_ASIC_TOP]
set filelist [file normalize [require_env NPC_ASIC_FILELIST]]
set sdc [file normalize [require_env NPC_ASIC_SDC]]
set output_dir [file normalize [require_env NPC_ASIC_OUTPUT_DIR]]
file mkdir $output_dir
source [file normalize [require_env NPC_ASIC_DC_SETUP]]
set memory_mode [require_env NPC_ASIC_MEMORY_MODE]
set expected_macro_count [require_env NPC_ASIC_EXPECTED_MACRO_COUNT]
set expected_blackbox_count [require_env NPC_ASIC_EXPECTED_BLACKBOX_COUNT]
set expected_macro_spec $::env(NPC_ASIC_EXPECTED_MACROS)
set compile_recipe compile_ultra_then_incremental_mapping_v1
set sram_input_isolation_revision disabled
set sram_input_isolation_target_pin_count 0
set sram_input_isolation_expected_target_pin_count 0
set sram_input_isolation_buffer_count 0
set sram_input_isolation_expected_buffer_count 0

if {[info exists ::env(NPC_ASIC_MACRO_DBS)] && $::env(NPC_ASIC_MACRO_DBS) ne ""} {
  set macro_link_libraries [list]
  foreach macro_db [split $::env(NPC_ASIC_MACRO_DBS) ":"] {
    set macro_db [file normalize $macro_db]
    if {![file isfile $macro_db]} {fail "Missing macro DB: $macro_db"}
    lappend macro_link_libraries $macro_db
    lappend search_path [file dirname $macro_db]
  }
  set link_library [concat "*" $target_library $macro_link_libraries]
}

set_app_var sh_continue_on_error false
set_app_var hdlin_check_no_latch true

set rtl_files [list]
set include_dirs [list]
set rtl_defines [list]
set fh [open $filelist r]
while {[gets $fh raw_line] >= 0} {
  regsub {//.*$} $raw_line "" without_comment
  set line [string trim $without_comment]
  if {$line eq ""} {continue}
  if {[string match "+incdir+*" $line]} {
    foreach entry [split [string range $line 8 end] "+"] {
      set path [file normalize [file join $root $entry]]
      if {![file isdirectory $path]} {close $fh; fail "Missing include directory: $path"}
      lappend include_dirs $path
    }
  } elseif {[string match "+define+*" $line]} {
    lappend rtl_defines [string range $line 8 end]
  } elseif {[string index $line 0] eq "+"} {
    close $fh
    fail "Unsupported ASIC filelist directive: $line"
  } else {
    set path [file normalize [file join $root $line]]
    if {![file isfile $path]} {close $fh; fail "Missing RTL source: $path"}
    lappend rtl_files $path
  }
}
close $fh

if {[info exists ::env(NPC_ASIC_EXTRA_DEFINES)] && $::env(NPC_ASIC_EXTRA_DEFINES) ne ""} {
  foreach define [split $::env(NPC_ASIC_EXTRA_DEFINES) ","] {
    if {$define ne ""} {lappend rtl_defines $define}
  }
}
if {[llength $rtl_files] == 0} {fail "ASIC filelist contains no RTL"}
if {[lsearch -glob $rtl_defines "NPC_USE_DPI*"] >= 0} {fail "NPC_USE_DPI is forbidden in ASIC synthesis"}

set_app_var search_path [concat $include_dirs [get_app_var search_path]]
set_host_options -max_cores 8
set analyze_command [list analyze -format sverilog]
if {[llength $rtl_defines] > 0} {lappend analyze_command -define $rtl_defines}
lappend analyze_command $rtl_files
if {[catch {set analyze_ok [eval $analyze_command]} message] || !$analyze_ok} {
  fail "analyze failed: $message"
}

set npc_asic_elaboration_parameters [list]
if {[info exists ::env(NPC_ASIC_PARAMETER_FILE)] && $::env(NPC_ASIC_PARAMETER_FILE) ne ""} {
  source [file normalize $::env(NPC_ASIC_PARAMETER_FILE)]
}
set elaborate_command [list elaborate $top]
if {[llength $npc_asic_elaboration_parameters] > 0} {
  lappend elaborate_command -parameters [join $npc_asic_elaboration_parameters ","]
}
if {[catch {set elaborate_ok [eval $elaborate_command]} message] || !$elaborate_ok} {
  fail "elaborate failed: $message"
}
current_design $top
if {[catch {set link_ok [link]} message] || !$link_ok} {fail "link failed: $message"}
uniquify

set expected_macro_refs [list]
array set expected_macro_ref_count {}
foreach item [split $expected_macro_spec ","] {
  if {$item eq ""} {continue}
  set fields [split $item "="]
  if {[llength $fields] != 2} {fail "Malformed expected macro contract: $item"}
  set ref [lindex $fields 0]
  set count [lindex $fields 1]
  lappend expected_macro_refs $ref
  set expected_macro_ref_count($ref) $count
}
set macro_cells [get_cells -hierarchical -quiet __npc_no_macro_match__]
array set linked_macro_ref_count {}
foreach ref $expected_macro_refs {set linked_macro_ref_count($ref) 0}
foreach_in_collection cell [get_cells -hierarchical -quiet *] {
  set ref [get_attribute $cell ref_name]
  if {[lsearch -exact $expected_macro_refs $ref] >= 0} {
    set macro_cells [add_to_collection $macro_cells $cell]
    incr linked_macro_ref_count($ref)
  }
}
if {[sizeof_collection $macro_cells] > 0} {set_dont_touch $macro_cells}
foreach ref $expected_macro_refs {
  if {$linked_macro_ref_count($ref) != $expected_macro_ref_count($ref)} {
    fail "Macro link count mismatch for $ref: expected $expected_macro_ref_count($ref), got $linked_macro_ref_count($ref)"
  }
}
set unresolved_precompile_count [collection_count_or_invalid {
  get_cells -hierarchical -quiet -filter "is_logical_black_box == true"
}]
if {$unresolved_precompile_count != 0} {
  fail "Unresolved references remain after link: $unresolved_precompile_count"
}

redirect -file "$output_dir/inferred_memory_precompile.rpt" {
  if {[catch {report_memory} message]} {echo "report_memory unavailable: $message"}
}

if {[catch {source $sdc} message]} {fail "constraint load failed: $message"}
set clocks [get_clocks -quiet npc_clk]
if {[sizeof_collection $clocks] != 1} {fail "Expected exactly one npc_clk"}
set expected_period [require_env NPC_ASIC_CLOCK_PERIOD_NS]
set actual_period [get_attribute $clocks period]
if {[expr {abs($actual_period - $expected_period)}] > 0.0001} {
  fail "Clock period mismatch: expected $expected_period, got $actual_period"
}

set_fix_multiple_port_nets -all -buffer_constants
if {[catch {compile_ultra} message]} {fail "compile_ultra failed: $message"}
if {[catch {compile -incremental_mapping} message]} {
  fail "compile -incremental_mapping cleanup failed: $message"
}
if {$memory_mode eq "sram"} {
  set isolation_hook [file normalize [file join $root flows/asic/dc/sram_input_isolation.tcl]]
  if {![file isfile $isolation_hook]} {fail "Missing SRAM input isolation hook: $isolation_hook"}
  if {[catch {source $isolation_hook} message]} {
    fail "SRAM input isolation hook load failed: $message"
  }
  if {[catch {
    set isolation_result [apply_sram_icache_write_data_isolation \
      $output_dir $expected_macro_count]
  } message]} {
    fail "SRAM input isolation failed: $message"
  }
  set sram_input_isolation_revision single_icache_write_data_shared_buf_x16_v1
  set sram_input_isolation_target_pin_count [lindex $isolation_result 0]
  set sram_input_isolation_expected_target_pin_count 64
  set sram_input_isolation_buffer_count [lindex $isolation_result 1]
  set sram_input_isolation_expected_buffer_count 32
  set compile_recipe compile_ultra_then_incremental_mapping_then_sram_icache_din_isolation_v2
} else {
  redirect -file "$output_dir/sram_input_isolation.rpt" {
    echo "revision=disabled"
    echo "macro_count=0"
    echo "target_pin_count=0"
    echo "inserted_buffer_count=0"
  }
}

set check_design_ok 0
redirect -file "$output_dir/check_design.rpt" {set check_design_ok [check_design]}
set check_timing_ok 0
redirect -file "$output_dir/check_timing.rpt" {
  set check_timing_ok [check_timing]
}
redirect -file "$output_dir/clock.rpt" {report_clock}
redirect -file "$output_dir/timing.rpt" {report_timing -delay_type max -max_paths 20 -path full}
redirect -file "$output_dir/qor.rpt" {report_qor}
redirect -file "$output_dir/area.rpt" {report_area -hierarchy}
redirect -file "$output_dir/references.rpt" {report_reference -hierarchy}
redirect -file "$output_dir/constraints.rpt" {report_constraint -all_violators}
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
redirect -file "$output_dir/constraints_min_pulse_width.rpt" {
  report_constraint -min_pulse_width -all_violators
}
if {[catch {redirect -file "$output_dir/timing_loops.rpt" {report_timing -loops}} message]} {
  set fh [open "$output_dir/timing_loops.rpt" w]
  puts $fh "report_timing -loops unavailable: $message"
  close $fh
}
if {[catch {redirect -file "$output_dir/memory.rpt" {report_memory}}]} {
  set fh [open "$output_dir/memory.rpt" w]
  puts $fh "report_memory unavailable"
  close $fh
}
if {[catch {redirect -file "$output_dir/disabled_timing.rpt" {report_disable_timing}}]} {
  set fh [open "$output_dir/disabled_timing.rpt" w]
  puts $fh "report_disable_timing unavailable"
  close $fh
}

set macro_count 0
set macro_area 0.0
array set mapped_macro_ref_count {}
foreach ref $expected_macro_refs {set mapped_macro_ref_count($ref) 0}
foreach_in_collection cell [get_cells -hierarchical -quiet *] {
  set ref [get_attribute $cell ref_name]
  if {[lsearch -exact $expected_macro_refs $ref] >= 0} {
    incr macro_count
    incr mapped_macro_ref_count($ref)
    if {![catch {set cell_area [get_attribute $cell area]}] && $cell_area ne ""} {
      set macro_area [expr {$macro_area + $cell_area}]
    }
  }
}
set blackbox_count [collection_count_or_invalid {
  get_cells -hierarchical -quiet -filter "is_logical_black_box == true"
}]
set unresolved_reference_count $blackbox_count
set cell_count [sizeof_collection [get_cells -hierarchical -quiet *]]
set register_count [sizeof_collection [all_registers]]
set clocked_register_count [sizeof_collection [all_registers -clock npc_clk]]
set unclocked_sync_endpoint_count [expr {$register_count - $clocked_register_count}]
set latch_count [collection_count_or_invalid {
  all_registers -level_sensitive
}]
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
  echo "profile=$profile"
  echo "top=$top"
  echo "memory_mode=$memory_mode"
  echo "expected_macro_count=$expected_macro_count"
  echo "expected_blackbox_count=$expected_blackbox_count"
  echo "macro_count=$macro_count"
  echo "macro_area=$macro_area"
  echo "blackbox_count=$blackbox_count"
  echo "cell_count=$cell_count"
  echo "register_count=$register_count"
  echo "clocked_register_count=$clocked_register_count"
  echo "unclocked_sync_endpoint_count=$unclocked_sync_endpoint_count"
  echo "latch_count=$latch_count"
  echo "unresolved_reference_count=$unresolved_reference_count"
  echo "check_design_ok=$check_design_ok"
  echo "check_timing_ok=$check_timing_ok"
  echo "setup_wns_ns=$setup_wns"
  echo "setup_tns_ns=[lindex $setup_stats 1]"
  echo "setup_violation_count=[lindex $setup_stats 0]"
  echo "hold_wns_ns=$hold_wns"
  echo "hold_tns_ns=[lindex $hold_stats 1]"
  echo "hold_violation_count=[lindex $hold_stats 0]"
  echo "max_transition_violation_count=$max_transition_count"
  echo "max_capacitance_violation_count=$max_capacitance_count"
  echo "max_fanout_violation_count=$max_fanout_count"
  echo "min_period_violation_count=$min_period_count"
  echo "min_pulse_width_violation_count=$min_pulse_width_count"
  echo "sram_input_isolation_revision=$sram_input_isolation_revision"
  echo "sram_input_isolation_target_pin_count=$sram_input_isolation_target_pin_count"
  echo "sram_input_isolation_expected_target_pin_count=$sram_input_isolation_expected_target_pin_count"
  echo "sram_input_isolation_buffer_count=$sram_input_isolation_buffer_count"
  echo "sram_input_isolation_expected_buffer_count=$sram_input_isolation_expected_buffer_count"
  echo "inferred_memory_bits=NA"
  echo "inferred_memory_bits_status=dc_o_2018_06_report_memory_unavailable"
  echo "clock_period_ns=$actual_period"
  echo "clock_frequency_mhz=[expr {1000.0 / $actual_period}]"
  echo "compile_recipe=$compile_recipe"
  echo "elaboration_parameters=$npc_asic_elaboration_parameters"
  echo "rtl_defines=$rtl_defines"
}
redirect -file "$output_dir/macro_instances.rpt" {
  echo "memory_mode=$memory_mode"
  echo "expected_total=$expected_macro_count"
  echo "mapped_total=$macro_count"
  foreach ref $expected_macro_refs {
    echo "ref=$ref expected=$expected_macro_ref_count($ref) mapped=$mapped_macro_ref_count($ref)"
  }
  foreach_in_collection cell [get_cells -hierarchical -quiet *] {
    set ref [get_attribute $cell ref_name]
    if {[lsearch -exact $expected_macro_refs $ref] >= 0} {
      echo "instance=[get_object_name $cell] ref=$ref"
    }
  }
}
foreach ref $expected_macro_refs {
  if {$mapped_macro_ref_count($ref) != $expected_macro_ref_count($ref)} {
    fail "Mapped macro count mismatch for $ref"
  }
}
if {$macro_count != $expected_macro_count ||
    $blackbox_count != $expected_blackbox_count ||
    $unresolved_reference_count != 0} {
  fail "Memory contract failed: macros=$macro_count/$expected_macro_count blackboxes=$blackbox_count/$expected_blackbox_count unresolved=$unresolved_reference_count"
}

change_names -rules verilog -hierarchy
write -format verilog -hierarchy -output "$output_dir/${top}_mapped.v"
write_sdc "$output_dir/${top}_mapped.sdc"
write -format ddc -hierarchy -output "$output_dir/${top}_mapped.ddc"
echo "INFO: NPC ASIC Design Compiler run completed"
quit
