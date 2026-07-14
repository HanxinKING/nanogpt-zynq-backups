set FINAL_HIDDEN 0x10000000
set LN_F_BUF 0x10120000
set ARGMAX_OUT 0x12F00000

proc r32 {addr} { return [expr {[mrd -force -value $addr] & 0xffffffff}] }
proc summarize_words {label base count} {
    set zero 0
    puts [format "%s_BEGIN base=0x%08x" $label $base]
    for {set i 0} {$i < $count} {incr i} {
        set addr [expr {$base + ($i * 4)}]
        set word [r32 $addr]
        if {$word == 0} { incr zero }
        puts [format "%s_WORD_%02d addr=0x%08x word=0x%08x" $label $i $addr $word]
    }
    puts [format "%s_SUMMARY sampled=%d zero_words=%d" $label $count $zero]
}

connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}
summarize_words FINAL_HIDDEN $FINAL_HIDDEN 32
summarize_words LN_F_BUF $LN_F_BUF 32
summarize_words ARGMAX_OUT $ARGMAX_OUT 16
disconnect
