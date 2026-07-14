set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set LN2BUF 0x100E0000
set OUT_FILE "$repo/vivado_project/baremetal/ps_mailbox_runner/build/ln2_buffer_dump.bin"

proc r32 {addr} { return [expr {[mrd -force -value $addr] & 0xffffffff}] }

connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}
set f [open $OUT_FILE wb]
for {set wi 0} {$wi < [expr {98304 / 4}]} {incr wi} {
    set word [r32 [expr {$LN2BUF + ($wi * 4)}]]
    puts -nonewline $f [binary format cccc [expr {$word & 0xff}] [expr {($word >> 8) & 0xff}] [expr {($word >> 16) & 0xff}] [expr {($word >> 24) & 0xff}]]
}
close $f
puts [format "DUMP_LN2_PASS output=%s" $OUT_FILE]
disconnect
