set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set OUT "$repo/vivado_project/generated/ffn64_debug/layer0_hello_board.bin"
set BASE 0x10020000
set BYTES [expr {11 * 384}]
file mkdir [file dirname $OUT]

connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}
set data [mrd -force -bin $BASE [expr {$BYTES / 4}]]
set f [open $OUT wb]
fconfigure $f -translation binary -encoding binary
puts -nonewline $f $data
close $f
disconnect
puts "LAYER0_HELLO_DUMP bytes=$BYTES file=$OUT"
