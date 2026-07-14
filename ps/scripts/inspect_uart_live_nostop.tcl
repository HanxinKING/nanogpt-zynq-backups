proc r32 {addr} { return [expr {[mrd -force -value $addr] & 0xffffffff}] }
connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {rrd pc} pc
puts [format "LIVE pc=%s uart=0x%08x core=0x%08x full=0x%08x mailbox=0x%08x generated=%d row_start=%d active=%d rows=%d" \
    $pc [r32 0x40000074] [r32 0x40000004] [r32 0x40000054] [r32 0x00020004] \
    [r32 0x0002002c] [r32 0x00020034] [r32 0x00020038] [r32 0x0002003c]]
disconnect
