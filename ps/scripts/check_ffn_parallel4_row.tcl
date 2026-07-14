set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set root "$repo/vivado_project"
set input_file "$root/generated/int8_alignment/kv_cache_reference/decode_step_1/layer_00_ln2_in.bin"
set expected_file "$root/generated/int8_alignment/kv_cache_reference/decode_step_1/layer_00_ffn.bin"

set PL_BASE 0x40000000
set LN2_BASE 0x100e0000
set OUT_BASE 0x10020000
set W1_BASE 0x11090000
set ROW_START 11
set D_MODEL 384
set row_offset [expr {$ROW_START * $D_MODEL}]

proc w32 {addr value} { mwr -force $addr $value }
proc r32 {addr} { return [expr {[mrd -force -value $addr] & 0xffffffff}] }

connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}

dow -data -force -bypass-cache-sync $input_file [expr {$LN2_BASE + $row_offset}]
w32 [expr {$PL_BASE + 0x00}] 0x00000002
after 10
w32 [expr {$PL_BASE + 0x30}] 0x00000020
w32 [expr {$PL_BASE + 0x40}] $LN2_BASE
w32 [expr {$PL_BASE + 0x44}] $OUT_BASE
w32 [expr {$PL_BASE + 0x48}] $W1_BASE
w32 [expr {$PL_BASE + 0x4c}] 0
w32 [expr {$PL_BASE + 0x50}] 0
w32 [expr {$PL_BASE + 0x64}] 0
w32 [expr {$PL_BASE + 0x68}] 0
w32 [expr {$PL_BASE + 0x6c}] 0
w32 [expr {$PL_BASE + 0x70}] 0
w32 [expr {$PL_BASE + 0x80}] [expr {$ROW_START + 1}]
w32 [expr {$PL_BASE + 0x84}] $ROW_START
w32 [expr {$PL_BASE + 0x00}] 0x00000001

set done 0
for {set poll 0} {$poll < 120000} {incr poll} {
    set status [r32 [expr {$PL_BASE + 0x04}]]
    if {$status & 0x1} {
        set done 1
        break
    }
    after 1
}
if {!$done} {
    puts "FFN_BOARD_CHECK FAIL timeout"
    disconnect
    exit 1
}

set fd [open $expected_file rb]
fconfigure $fd -translation binary
set expected [read $fd]
close $fd

set mismatch 0
set first -1
for {set word_index 0} {$word_index < [expr {$D_MODEL / 4}]} {incr word_index} {
    set word [r32 [expr {$OUT_BASE + $row_offset + ($word_index * 4)}]]
    for {set lane 0} {$lane < 4} {incr lane} {
        set index [expr {$word_index * 4 + $lane}]
        set got [expr {($word >> ($lane * 8)) & 0xff}]
        binary scan [string index $expected $index] c exp_signed
        set exp [expr {$exp_signed & 0xff}]
        if {$got != $exp} {
            if {$first < 0} { set first $index }
            if {$mismatch < 16} {
                puts [format "FFN_BOARD_DETAIL offset=%d got=%02x expected=%02x" $index $got $exp]
            }
            incr mismatch
        }
    }
}

set status [r32 [expr {$PL_BASE + 0x04}]]
set full_status [r32 [expr {$PL_BASE + 0x54}]]
set stage [r32 [expr {$PL_BASE + 0x58}]]
set reads [r32 [expr {$PL_BASE + 0x2c}]]
puts [format "FFN_BOARD_CHECK mismatch=%d/%d first=%d status=0x%08x full=0x%08x stage=0x%08x reads=%d" \
      $mismatch $D_MODEL $first $status $full_status $stage $reads]
disconnect
if {$mismatch != 0} { exit 2 }
