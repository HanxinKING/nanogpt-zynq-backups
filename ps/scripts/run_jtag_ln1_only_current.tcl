set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set root "$repo"
set nano "$repo/vivado_project"
set bit_file "$repo/artifacts/system.bit"
set ps7_init "$repo/vitis/workspace/nanogpt_qkt8_platform/hw/ps7_init.tcl"
set image_dir "$repo/reference/ddr_image"

set PL 0x40000000
set LAYER_A 0x10000000
set LN2BUF 0x100E0000

proc w32 {addr value} { mwr -force $addr [expr {$value & 0xffffffff}] }
proc r32 {addr} { return [expr {[mrd -force -value $addr] & 0xffffffff}] }

proc download_bin {base file label} {
    if {![file exists $file]} {
        puts [format "JTAG_LN1_RESULT=FAIL missing_%s file=%s" $label $file]
        exit
    }
    set size [file size $file]
    puts [format "DOWNLOAD %s base=0x%08x bytes=%u file=%s" $label $base $size $file]
    dow -data $file $base
}

connect
source $ps7_init
puts "JTAG_LN1_TARGETS_BEFORE_RECOVER"
puts [targets]
catch {targets -set 1}
catch {rst -system} rst_msg
puts [format "RST_SYSTEM=%s" $rst_msg]
after 3000
puts "JTAG_LN1_TARGETS_AFTER_RECOVER"
puts [targets]
catch {targets -set -filter {name =~ "APU*"}}
ps7_init
ps7_post_config
targets -set -filter {name =~ "xc7z020*"}
fpga -file $bit_file
after 2000
catch {targets -set -filter {name =~ "APU*"}}
ps7_init
ps7_post_config
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}
catch {memmap -addr 0x00000000 -size 0x40000000 -flags rw}

download_bin $LAYER_A "$image_dir/input.bin" input

w32 [expr {$PL + 0x00}] 0x00000002
after 10
w32 [expr {$PL + 0x30}] 0x00000010
w32 [expr {$PL + 0x40}] $LAYER_A
w32 [expr {$PL + 0x44}] $LN2BUF
w32 [expr {$PL + 0x48}] 0x00000000
w32 [expr {$PL + 0x4c}] 0x00000000
w32 [expr {$PL + 0x50}] 0x00000000
puts [format "REGS mode=0x%08x input=0x%08x output=0x%08x" [r32 [expr {$PL + 0x30}]] [r32 [expr {$PL + 0x40}]] [r32 [expr {$PL + 0x44}]]]
w32 [expr {$PL + 0x00}] 0x00000001

set status 0
for {set i 0} {$i < 120000} {incr i} {
    set status [r32 [expr {$PL + 0x04}]]
    if {($status & 0x1) != 0 || ($status & 0x4) != 0} { break }
    if {($i % 1000) == 0} {
        puts [format "POLL i=%u status=0x%08x full_status=0x%08x stage=0x%08x reads=%u debug=0x%08x sig=0x%08x" $i $status [r32 [expr {$PL + 0x54}]] [r32 [expr {$PL + 0x58}]] [r32 [expr {$PL + 0x2c}]] [r32 [expr {$PL + 0x5c}]] [r32 [expr {$PL + 0x60}]]]
    }
    after 10
}

set full_status [r32 [expr {$PL + 0x54}]]
set stage [r32 [expr {$PL + 0x58}]]
set reads [r32 [expr {$PL + 0x2c}]]
set debug [r32 [expr {$PL + 0x5c}]]
set sig [r32 [expr {$PL + 0x60}]]
puts [format "JTAG_LN1_RESULT status=0x%08x full_status=0x%08x stage=0x%08x reads=%u debug=0x%08x sig=0x%08x" $status $full_status $stage $reads $debug $sig]
disconnect
