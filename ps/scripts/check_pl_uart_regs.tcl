set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set nano "$repo/vivado_project"
set ps7_init "$repo/vitis/workspace/nanogpt_qkt8_platform/hw/ps7_init.tcl"
set bit_file "$repo/artifacts/system.bit"
set uart_status 0x40000074
set uart_rx_data 0x40000078
set uart_tx_data 0x4000007c

connect
source $ps7_init
targets -set -filter {name =~ "APU*"}
catch {rst -system}
after 1000
ps7_init
ps7_post_config
targets -set -filter {name =~ "xc7z020*"}
fpga -file $bit_file
after 1000
targets -set -filter {name =~ "APU*"}
ps7_init
ps7_post_config
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}

set status0 [expr {[mrd -force -value $uart_status] & 0xffffffff}]
puts [format "PL_UART_STATUS0=0x%08x" $status0]
if {($status0 & 0xff000000) != 0x55000000} {
    puts "PL_UART_REG_TEST=FAIL bad_signature"
    disconnect
    exit 1
}
if {($status0 & 0x2) == 0} {
    puts "PL_UART_REG_TEST=FAIL tx_not_ready"
    disconnect
    exit 1
}

mwr -force $uart_tx_data 0x55
after 10
set status1 [expr {[mrd -force -value $uart_status] & 0xffffffff}]
puts [format "PL_UART_STATUS1=0x%08x" $status1]
puts "PL_UART_REG_TEST=PASS"
disconnect
