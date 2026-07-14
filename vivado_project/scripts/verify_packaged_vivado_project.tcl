if {$argc != 1} {
    error "Usage: vivado -mode batch -source verify_packaged_vivado_project.tcl -tclargs <nano_gpt.xpr>"
}

set xpr [file normalize [lindex $argv 0]]
set output [file join [file dirname $xpr] package_vivado_check.txt]
open_project $xpr
update_compile_order -fileset sources_1

set missing {}
foreach source [get_files -quiet] {
    set path [get_property NAME $source]
    if {![file exists $path]} {
        lappend missing $path
    }
}

set fp [open $output w]
puts $fp "PROJECT=$xpr"
puts $fp "TOP=[get_property TOP [get_filesets sources_1]]"
puts $fp "SOURCE_FILES=[llength [get_files -quiet -of_objects [get_filesets sources_1]]]"
puts $fp "CONSTRAINT_FILES=[llength [get_files -quiet -of_objects [get_filesets constrs_1]]]"
puts $fp "MISSING_FILES=[llength $missing]"
foreach path $missing { puts $fp "MISSING=$path" }
close $fp
close_project
if {[llength $missing] != 0} { error "Packaged project has missing files" }
exit
