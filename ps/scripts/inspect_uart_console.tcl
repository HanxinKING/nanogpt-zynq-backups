connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}
catch {rrd pc} pc
set uart_status [expr {[mrd -force -value 0x40000074] & 0xffffffff}]
set core_status [expr {[mrd -force -value 0x40000004] & 0xffffffff}]
set full_status [expr {[mrd -force -value 0x40000054] & 0xffffffff}]
set mailbox_state [expr {[mrd -force -value 0x00020004] & 0xffffffff}]
set generated [expr {[mrd -force -value 0x0002002c] & 0xffffffff}]
set token0 [expr {[mrd -force -value 0x00020400] & 0xffffffff}]
set char0 [expr {[mrd -force -value 0x00020900] & 0xffffffff}]
set cache_row_start [expr {[mrd -force -value 0x00020034] & 0xffffffff}]
set cache_active [expr {[mrd -force -value 0x00020038] & 0xffffffff}]
set cache_rows [expr {[mrd -force -value 0x0002003c] & 0xffffffff}]
puts [format "UART_INSPECT pc=%s uart=0x%08x core=0x%08x full=0x%08x mailbox=0x%08x" \
    $pc $uart_status $core_status $full_status $mailbox_state]
puts [format "UART_RESULT generated=%d token0=%d char0=0x%02x" $generated $token0 $char0]
puts [format "UART_CACHE row_start=%d active=%d context_rows=%d" \
    $cache_row_start $cache_active $cache_rows]
set toks {}
set chars ""
for {set i 0} {$i < $generated} {incr i} {
    lappend toks [expr {[mrd -force -value [expr {0x00020400 + ($i * 4)}]] & 0xffffffff}]
    set ch [expr {[mrd -force -value [expr {0x00020900 + ($i * 4)}]] & 0xff}]
    append chars [format %c $ch]
}
puts [format "UART_TOKENS %s" $toks]
puts [format "UART_TEXT %s" $chars]
catch {con}
disconnect
