set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set FINAL_HIDDEN 0x10000000
set OUT_FILE "$repo/vivado_project/baremetal/ps_mailbox_runner/build/current_final_hidden_row0.mem"

proc r32 {addr} { return [expr {[mrd -force -value $addr] & 0xffffffff}] }

connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}
set f [open $OUT_FILE w]
for {set wi 0} {$wi < 96} {incr wi} {
    set word [r32 [expr {$FINAL_HIDDEN + ($wi * 4)}]]
    for {set bi 0} {$bi < 4} {incr bi} {
        puts $f [format "%02x" [expr {($word >> ($bi * 8)) & 0xff}]]
    }
}
close $f
puts [format "DUMP_ROW0_RESULT=PASS file=%s bytes=384" $OUT_FILE]
disconnect
