set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set ELF "$repo/vivado_project/baremetal/ps_mailbox_runner/build/ps_mailbox_runner.elf"
set MAILBOX 0x00020000
set PROMPT "hello world"

proc w32 {addr value} { mwr -force $addr [expr {$value & 0xffffffff}] }
proc r32 {addr} { return [expr {[mrd -force -value $addr] & 0xffffffff}] }

connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}
catch {rst -processor}
after 500
dow -force $ELF
w32 [expr {$MAILBOX + 0x00}] 0x4e475054
w32 [expr {$MAILBOX + 0x04}] 1
w32 [expr {$MAILBOX + 0x08}] [string length $PROMPT]
w32 [expr {$MAILBOX + 0x24}] 3
w32 [expr {$MAILBOX + 0x28}] 1
for {set i 0} {$i < [string length $PROMPT]} {incr i} {
    binary scan [string index $PROMPT $i] c ch
    w32 [expr {$MAILBOX + 0x100 + $i * 4}] [expr {$ch & 0xff}]
}
catch {rwr pc 0x00000000}
catch {con}
for {set i 0} {$i < 10000} {incr i} {
    set state [r32 [expr {$MAILBOX + 0x04}]]
    if {$state == 0x00009003 || (($state & 0xffff0000) == 0xdead0000)} { break }
    after 1
}
catch {stop}
puts [format "CMD3_STATE=0x%08x" [r32 [expr {$MAILBOX + 0x04}]]]
puts [format "LN_DEBUG sum=0x%08x sq=0x%08x var_lo=0x%08x var_hi=0x%08x sqrt_q16=0x%08x den_lo=0x%08x den_hi=0x%08x" \
    [r32 [expr {$MAILBOX + 0xc00}]] \
    [r32 [expr {$MAILBOX + 0xc04}]] \
    [r32 [expr {$MAILBOX + 0xc08}]] \
    [r32 [expr {$MAILBOX + 0xc0c}]] \
    [r32 [expr {$MAILBOX + 0xc10}]] \
    [r32 [expr {$MAILBOX + 0xc14}]] \
    [r32 [expr {$MAILBOX + 0xc18}]]]
disconnect
