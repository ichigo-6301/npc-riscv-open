proc apply_sram_icache_write_data_isolation {output_dir expected_macro_count} {
  set macro_cells [get_cells -hierarchical -quiet \
    -filter "ref_name =~ npc_*cache_data_1r1w_512x32*"]
  set icache_macro_cells [filter_collection $macro_cells \
    "ref_name == npc_icache_data_1r1w_512x32"]
  set icache_pins [get_pins -of_objects $icache_macro_cells]
  set icache_input_pins [filter_collection $icache_pins "direction == in"]
  set icache_din_pins [filter_collection $icache_input_pins "name =~ din0*"]
  set buffer_cell [get_lib_cells -quiet */BUF_X16]
  set buf_cells_before [get_cells -hierarchical -quiet -filter {ref_name == BUF_X16}]

  if {[sizeof_collection $macro_cells] != $expected_macro_count} {
    error "SRAM isolation expected $expected_macro_count macros, found [sizeof_collection $macro_cells]"
  }
  if {[sizeof_collection $icache_macro_cells] != 2} {
    error "SRAM isolation expected two I-cache macros, found [sizeof_collection $icache_macro_cells]"
  }
  if {[sizeof_collection $icache_din_pins] != 64} {
    error "SRAM isolation expected 64 I-cache write-data pins, found [sizeof_collection $icache_din_pins]"
  }
  if {[sizeof_collection $buffer_cell] != 1} {
    error "SRAM isolation expected exactly one BUF_X16 library cell"
  }

  insert_buffer $icache_din_pins BUF_X16
  set buf_cells_after_insert [get_cells -hierarchical -quiet -filter {ref_name == BUF_X16}]
  set inserted_buf_cells [remove_from_collection $buf_cells_after_insert $buf_cells_before]
  if {[sizeof_collection $inserted_buf_cells] != 32} {
    error "SRAM isolation expected 32 shared data buffers, found [sizeof_collection $inserted_buf_cells]"
  }
  set_dont_touch $inserted_buf_cells true

  if {[catch {compile -incremental_mapping} message]} {
    error "SRAM isolation incremental mapping failed: $message"
  }

  set macro_cells_after [get_cells -hierarchical -quiet \
    -filter "ref_name =~ npc_*cache_data_1r1w_512x32*"]
  if {[sizeof_collection $macro_cells_after] != $expected_macro_count} {
    error "SRAM isolation changed the macro count"
  }
  if {[sizeof_collection $inserted_buf_cells] != 32} {
    error "SRAM isolation buffers were not preserved"
  }

  redirect -file "$output_dir/sram_input_isolation.rpt" {
    echo "revision=single_icache_write_data_shared_buf_x16_v1"
    echo "macro_count=[sizeof_collection $macro_cells_after]"
    echo "target_pin_count=[sizeof_collection $icache_din_pins]"
    echo "inserted_buffer_count=[sizeof_collection $inserted_buf_cells]"
    foreach_in_collection cell $inserted_buf_cells {
      echo "buffer=[get_object_name $cell] ref=[get_attribute $cell ref_name]"
    }
  }
  return [list [sizeof_collection $icache_din_pins] [sizeof_collection $inserted_buf_cells]]
}
