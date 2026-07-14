set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set dcp_path [file join $project_dir generated qkt8_pipe100_candidate system_routed.dcp]
set report_path [file join $project_dir generated qkt8_pipe100_candidate utilization_hierarchical_post_route.rpt]

if {![file exists $dcp_path]} {
    error "Routed checkpoint not found: $dcp_path"
}

open_checkpoint $dcp_path
report_utilization -hierarchical -hierarchical_depth 6 -file $report_path
puts "WROTE $report_path"
close_design
exit
