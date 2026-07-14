proc r32 {addr} { return [expr {[mrd -force -value $addr] & 0xffffffff}] }

proc checksum_region {base words} {
    set sum 0
    set xors 0
    for {set i 0} {$i < $words} {incr i} {
        set value [r32 [expr {$base + ($i * 4)}]]
        set sum [expr {($sum + $value) & 0xffffffff}]
        set xors [expr {$xors ^ $value}]
    }
    return [list $sum $xors]
}

connect
targets -set -filter {name =~ "*Cortex-A9*#0"}

for {set pass 0} {$pass < 5} {incr pass} {
    set weights [checksum_region 0x11000000 256]
    set scales [checksum_region 0x11c00000 256]
    set status [r32 0x40000004]
    puts [format "DDR_STABILITY pass=%d weights_sum=0x%08x weights_xor=0x%08x scales_sum=0x%08x scales_xor=0x%08x pl_status=0x%08x" \
        $pass [lindex $weights 0] [lindex $weights 1] [lindex $scales 0] [lindex $scales 1] $status]
    after 100
}

disconnect
