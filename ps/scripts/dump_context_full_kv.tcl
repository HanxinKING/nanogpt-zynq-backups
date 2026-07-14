set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set ROWS 60
set BYTES [expr {$ROWS * 384}]
set OUT_DIR "$repo/vivado_project/generated/int8_alignment/board_context60_row59"
file mkdir $OUT_DIR

proc dump_binary {base bytes path} {
    set words [expr {$bytes / 4}]
    set data [mrd -force -bin $base $words]
    set f [open $path wb]
    fconfigure $f -translation binary -encoding binary
    puts -nonewline $f $data
    close $f
    puts [format "DUMP_BINARY base=0x%08x bytes=%d file=%s" $base $bytes $path]
}

connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}
for {set layer 0} {$layer < 4} {incr layer} {
    set lname [format "layer_%02d" $layer]
    dump_binary [expr {0x10200000 + ($layer * 0x00020000)}] $BYTES "$OUT_DIR/${lname}_k_full.bin"
    dump_binary [expr {0x10400000 + ($layer * 0x00020000)}] $BYTES "$OUT_DIR/${lname}_v_full.bin"
}
disconnect
puts "DUMP_CONTEXT_FULL_KV_PASS"
