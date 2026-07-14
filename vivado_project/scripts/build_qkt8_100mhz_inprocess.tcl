set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set root "$repo/vivado_project"
set generated "$root/generated"
set candidate "$generated/qkt8_pipe100_candidate"
set variant "$root/rtl/hls_kernel_chain_axis_full_only_core_ffn64_qp16_pipe100_qkt8.v"

open_project "$root/nano_gpt.xpr"
set_param general.maxThreads 2
set_property source_mgmt_mode All [current_project]
foreach old [list \
    "$root/rtl/hls_kernel_chain_axis_full_only_core_ffn64_qp16_pipe100.v" \
    "$root/rtl/hls_kernel_chain_axis_full_only_core_ffn64_qp16.v" \
    "$root/rtl/hls_kernel_chain_axis_full_only_core_ffn64.v" \
    "$root/rtl/hls_kernel_chain_axis_full_only_core.v"] {
    foreach f [get_files -quiet $old] { remove_files $f }
}
if {[llength [get_files -quiet $variant]] == 0} { add_files -fileset sources_1 -norecurse $variant }
set_property file_type SystemVerilog [get_files $variant]
set_property top system_wrapper [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
set_property verilog_define {INT8_TILE_MODE FULL_ONLY_SYNTH} [get_filesets sources_1]
update_compile_order -fileset sources_1

synth_design -top system_wrapper -part xc7z020clg484-2 -resource_sharing off
file mkdir $candidate
write_checkpoint -force "$candidate/system_synth.dcp"
opt_design -directive Explore
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore
report_timing_summary -file "$generated/timing_qkt8_pipe100_post_route.rpt" -warn_on_violation
report_utilization -file "$generated/utilization_qkt8_pipe100_post_route.rpt"
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
puts "QKT8_PIPE100_TIMING WNS=$wns TNS=[expr {$wns >= 0.0 ? 0.0 : {violated}}]"
if {$wns < 0.0} { error "QKT8 does not meet 100 MHz" }
write_checkpoint -force "$candidate/system_routed.dcp"
write_bitstream -force "$candidate/system.bit"
file copy -force "$root/nano_gpt.gen/sources_1/bd/system/hw_handoff/system.hwh" "$candidate/system.hwh"
puts "QKT8_PIPE100_READY bit=$candidate/system.bit"
close_project
exit
