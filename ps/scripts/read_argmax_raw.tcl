set ARGMAX_OUT 0x12F00000

connect
puts "READ_ARGMAX_TARGETS_BEGIN"
puts [targets]
puts "READ_ARGMAX_TARGETS_END"
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}
puts "READ_ARGMAX_RAW_BEGIN"
for {set i 0} {$i < 16} {incr i} {
    set addr [expr {$ARGMAX_OUT + ($i * 4)}]
    set word [mrd -force -value $addr]
    puts [format "ARGMAX_WORD_%02d addr=0x%08x word=0x%08x tok0=%u tok1=%u" $i $addr [expr {$word & 0xffffffff}] [expr {$word & 0xffff}] [expr {($word >> 16) & 0xffff}]]
}
puts "READ_ARGMAX_RAW_END"
disconnect
