if {$argc != 2} {
    error "Usage: vivado -mode batch -source export_hardware_xsa.tcl -tclargs <xpr> <xsa>"
}

set xpr [file normalize [lindex $argv 0]]
set xsa [file normalize [lindex $argv 1]]
file mkdir [file dirname $xsa]

open_project $xpr
set bd_files [get_files -quiet */system.bd]
if {[llength $bd_files] != 1} {
    error "Expected exactly one system.bd, found [llength $bd_files]"
}
open_bd_design [lindex $bd_files 0]
validate_bd_design
save_bd_design
write_hw_platform -fixed -force -file $xsa
close_project
puts "XSA=$xsa"
exit
