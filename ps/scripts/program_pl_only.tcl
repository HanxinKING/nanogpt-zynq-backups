set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set bit_file "$repo/vivado_project/overlay/system/system.bit"
if {[info exists ::env(BIT_FILE)]} { set bit_file $::env(BIT_FILE) }

if {![file exists $bit_file]} {
    puts [format "PROGRAM_PL_RESULT=FAIL missing_bit=%s" $bit_file]
    exit 1
}

connect
puts "PROGRAM_PL_TARGETS_BEGIN"
puts [targets]
puts "PROGRAM_PL_TARGETS_END"
targets -set -filter {name =~ "xc7z020*"}
fpga -file $bit_file
after 2000
puts [format "PROGRAM_PL_RESULT=PASS bit=%s" $bit_file]
disconnect
