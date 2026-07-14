set MAILBOX 0x00020000
set PROFILE_BASE_WORD 0x500
set PROFILE_LAYER_WORDS 16
set PROFILE_LM_WORD 0x560
set PROFILE_EMBED_WORD 0x561
set PROFILE_GUARD_WORD 0x562
set stage_names {ln1 q k v attention projection residual1 ln2 ffn residual2}

proc r32 {addr} { return [expr {[mrd -force -value $addr] & 0xffffffff}] }

connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
puts [format "PROFILE_CONTEXT active_rows=%u row_start=%u kv_incremental=%u" \
    [r32 [expr {$MAILBOX + 0x3c}]] \
    [r32 [expr {$MAILBOX + 0x34}]] \
    [r32 [expr {$MAILBOX + 0x38}]]]
for {set layer 0} {$layer < 6} {incr layer} {
    set fields {}
    for {set stage 0} {$stage < 10} {incr stage} {
        set word [expr {$PROFILE_BASE_WORD + $layer * $PROFILE_LAYER_WORDS + $stage}]
        set ticks [r32 [expr {$MAILBOX + $word * 4}]]
        lappend fields [format "%s=%u" [lindex $stage_names $stage] $ticks]
    }
    puts [format "PROFILE layer=%d %s" $layer [join $fields " "]]
}
puts [format "PROFILE lm_head=%u embedding=%u guard_delay=%u timer_control=0x%08x" \
    [r32 [expr {$MAILBOX + $PROFILE_LM_WORD * 4}]] \
    [r32 [expr {$MAILBOX + $PROFILE_EMBED_WORD * 4}]] \
    [r32 [expr {$MAILBOX + $PROFILE_GUARD_WORD * 4}]] \
    [r32 0xF8F00208]]
disconnect
