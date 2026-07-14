set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set ROW 59
if {[info exists ::env(DUMP_ROW)]} { set ROW $::env(DUMP_ROW) }

set OUT_DIR "$repo/vivado_project/generated/int8_alignment/board_context60_row59"
file mkdir $OUT_DIR

proc r32 {addr} { return [expr {[mrd -force -value $addr] & 0xffffffff}] }

proc dump_row {base row path} {
    set f [open $path w]
    set row_base [expr {$base + ($row * 384)}]
    for {set wi 0} {$wi < 96} {incr wi} {
        set word [r32 [expr {$row_base + ($wi * 4)}]]
        for {set bi 0} {$bi < 4} {incr bi} {
            puts $f [format "%02x" [expr {($word >> ($bi * 8)) & 0xff}]]
        }
    }
    close $f
    puts [format "DUMP_STAGE row=%d base=0x%08x file=%s" $row $base $path]
}

connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}

dump_row 0x10020000 $ROW "$OUT_DIR/layer_05_input.mem"
dump_row 0x10040000 $ROW "$OUT_DIR/layer_05_q.mem"
dump_row [expr {0x10200000 + (5 * 0x00020000)}] $ROW "$OUT_DIR/layer_05_k.mem"
dump_row [expr {0x10400000 + (5 * 0x00020000)}] $ROW "$OUT_DIR/layer_05_v.mem"
dump_row 0x100a0000 $ROW "$OUT_DIR/layer_05_attn_in.mem"
dump_row 0x100c0000 $ROW "$OUT_DIR/layer_05_res1.mem"
dump_row 0x100e0000 $ROW "$OUT_DIR/layer_05_ln2_in.mem"
dump_row 0x10000000 $ROW "$OUT_DIR/layer_05_final.mem"

for {set layer 0} {$layer < 6} {incr layer} {
    set lname [format "layer_%02d" $layer]
    dump_row [expr {0x10200000 + ($layer * 0x00020000)}] $ROW "$OUT_DIR/${lname}_k.mem"
    dump_row [expr {0x10400000 + ($layer * 0x00020000)}] $ROW "$OUT_DIR/${lname}_v.mem"
}

set diag_names {input q attn_in attn_proj res1 ln2_in ffn final}
for {set slot 0} {$slot < 8} {incr slot} {
    set stage [lindex $diag_names $slot]
    dump_row [expr {0x10600000 + ($slot * 0x00001000)}] 0 "$OUT_DIR/layer_02_row58_${stage}.mem"
}

disconnect
puts "DUMP_CONTEXT_STAGES_PASS"
