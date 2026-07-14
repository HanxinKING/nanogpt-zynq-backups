connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}
set addr 0x10001e00
if {[info exists ::env(DUMP_ADDR)]} { set addr $::env(DUMP_ADDR) }
puts [format "HIDDEN_DUMP_BEGIN addr=0x%08x words=96" $addr]
puts [mrd -force $addr 96]
puts "HIDDEN_DUMP_END"
disconnect
exit 0
