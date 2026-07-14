set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set bit_file "$repo/artifacts/system.bit"

if {![file exists $bit_file]} {
    puts "PROGRAM_100M_RESULT=FAIL reason=missing_bit"
    exit 1
}

open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target

set devices [get_hw_devices -quiet -filter {PART =~ "xc7z020*"}]
if {[llength $devices] == 0} {
    puts "PROGRAM_100M_RESULT=FAIL reason=xc7z020_not_found"
    exit 2
}

set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device -update_hw_probes false $device

puts [format "PROGRAM_100M_DEVICE=%s" $device]
puts [format "PROGRAM_100M_BIT=%s" $bit_file]
puts "PROGRAM_100M_RESULT=PASS"

close_hw_target
disconnect_hw_server
close_hw_manager
