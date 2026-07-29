proc require_env {name} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    error "Missing required environment variable: $name"
  }
  return $::env($name)
}

set liberty_path [file normalize [require_env NPC_ASIC_MACRO_LIBERTY]]
set library_name [require_env NPC_ASIC_MACRO_LIBRARY_NAME]
set db_path [file normalize [require_env NPC_ASIC_MACRO_DB]]

if {![file isfile $liberty_path]} {error "Missing macro Liberty: $liberty_path"}
if {[catch {read_lib $liberty_path} message]} {
  error "OpenRAM Liberty read failed: $message"
}
if {[catch {write_lib $library_name -format db -output $db_path} message]} {
  error "OpenRAM DB write failed: $message"
}
if {![file isfile $db_path]} {error "Library Compiler did not create $db_path"}
puts "INFO: compiled $liberty_path to $db_path"
quit
