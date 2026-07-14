set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set PL 0x40000000
set INPUT 0x10000000
set OUTPUT 0x100E0000
set OUT_FILE "$repo/vivado_project/baremetal/ps_mailbox_runner/build/current_ln1_qkv_input.bin"

proc w32 {addr value} { mwr -force $addr [expr {$value & 0xffffffff}] }
proc r32 {addr} { return [expr {[mrd -force -value $addr] & 0xffffffff}] }

connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}

w32 [expr {$PL + 0x00}] 0x00000002
after 10
w32 [expr {$PL + 0x30}] 0x00000010
w32 [expr {$PL + 0x40}] $INPUT
w32 [expr {$PL + 0x44}] $OUTPUT
w32 [expr {$PL + 0x48}] 0
w32 [expr {$PL + 0x4c}] 0
w32 [expr {$PL + 0x50}] 0
w32 [expr {$PL + 0x00}] 0x00000001

set status 0
for {set i 0} {$i < 120000} {incr i} {
    set status [r32 [expr {$PL + 0x04}]]
    if {($status & 0x1) != 0 || ($status & 0x4) != 0} { break }
    after 1
}
set stage [r32 [expr {$PL + 0x58}]]
if {($status & 0x1) == 0 || ($stage & 0x1f) != 0x1f} {
    puts [format "LN1_PROBE_FAIL status=0x%08x stage=0x%08x" $status $stage]
    disconnect
    exit 1
}

set f [open $OUT_FILE wb]
for {set wi 0} {$wi < [expr {98304 / 4}]} {incr wi} {
    set word [r32 [expr {$OUTPUT + ($wi * 4)}]]
    puts -nonewline $f [binary format cccc [expr {$word & 0xff}] [expr {($word >> 8) & 0xff}] [expr {($word >> 16) & 0xff}] [expr {($word >> 24) & 0xff}]]
}
close $f
puts [format "LN1_PROBE_PASS status=0x%08x stage=0x%08x output=%s" $status $stage $OUT_FILE]
disconnect
