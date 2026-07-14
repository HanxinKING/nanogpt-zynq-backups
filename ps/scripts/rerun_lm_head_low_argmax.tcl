set PL 0x40000000
set FINAL_HIDDEN 0x10000000
set LN_F_BUF 0x10120000
set WEIGHTS 0x11000000
set OFF_LM_HEAD 0x00A20000
set ARGMAX_LOW 0x12F00000

proc w32 {addr value} { mwr -force $addr $value }
proc r32 {addr} { return [expr {[mrd -force -value $addr] & 0xffffffff}] }
proc zero_words {base words} {
    for {set i 0} {$i < $words} {incr i} {
        mwr -force [expr {$base + ($i * 4)}] 0
    }
}
proc read_argmax {base n} {
    set toks {}
    for {set i 0} {$i < $n} {incr i} {
        set word [r32 [expr {$base + (($i >> 1) * 4)}]]
        if {[expr {$i & 1}] == 0} {
            lappend toks [expr {$word & 0xffff}]
        } else {
            lappend toks [expr {($word >> 16) & 0xffff}]
        }
    }
    puts [format "ARGMAX_LOW_TOKENS %s" $toks]
}

connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}
zero_words $ARGMAX_LOW 128
w32 [expr {$PL + 0x00}] 0x00000002
after 10
w32 [expr {$PL + 0x30}] 0x00000080
w32 [expr {$PL + 0x40}] $FINAL_HIDDEN
w32 [expr {$PL + 0x44}] $LN_F_BUF
w32 [expr {$PL + 0x48}] [expr {$WEIGHTS + $OFF_LM_HEAD}]
w32 [expr {$PL + 0x4c}] 0
w32 [expr {$PL + 0x50}] 0
w32 [expr {$PL + 0x64}] $ARGMAX_LOW
w32 [expr {$PL + 0x00}] 0x00000001
set status 0
for {set i 0} {$i < 900000} {incr i} {
    set status [r32 [expr {$PL + 0x04}]]
    if {($status & 0x1) != 0 || ($status & 0x4) != 0} { break }
    after 10
}
set full_status [r32 [expr {$PL + 0x54}]]
set stage [r32 [expr {$PL + 0x58}]]
set sig [r32 [expr {$PL + 0x60}]]
puts [format "RERUN_LM_RESULT status=0x%08x full_status=0x%08x stage=0x%08x hls_sig=0x%08x argmax=0x%08x" $status $full_status $stage $sig $ARGMAX_LOW]
read_argmax $ARGMAX_LOW 16
disconnect
