set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set LAYER_A 0x10000000
set MAILBOX 0x00020000
set OUT_FILE "$repo/vivado_project/baremetal/ps_mailbox_runner/build/embedding_hidden_dump.bin"
set TOK_FILE "$repo/vivado_project/baremetal/ps_mailbox_runner/build/encoded_tokens.txt"

proc r32 {addr} { return [expr {[mrd -force -value $addr] & 0xffffffff}] }

connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}

set f [open $OUT_FILE wb]
for {set wi 0} {$wi < [expr {98304 / 4}]} {incr wi} {
    set word [r32 [expr {$LAYER_A + ($wi * 4)}]]
    puts -nonewline $f [binary format cccc [expr {$word & 0xff}] [expr {($word >> 8) & 0xff}] [expr {($word >> 16) & 0xff}] [expr {($word >> 24) & 0xff}]]
}
close $f

set tf [open $TOK_FILE w]
for {set i 0} {$i < 16} {incr i} {
    puts $tf [format "%u" [r32 [expr {$MAILBOX + 0x200 + ($i * 4)}]]]
}
close $tf
puts [format "DUMP_EMBED_RESULT=PASS hidden=%s tokens=%s" $OUT_FILE $TOK_FILE]
disconnect
