set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set ROWS 11
set BYTES [expr {$ROWS * 384}]
set LABEL "candidate"
if {[info exists ::env(DUMP_LABEL)]} { set LABEL $::env(DUMP_LABEL) }
set OUT_DIR "$repo/vivado_project/generated/ffn64_debug/$LABEL"
file mkdir $OUT_DIR

proc dump_binary {base bytes path} {
    set data [mrd -force -bin $base [expr {$bytes / 4}]]
    set f [open $path wb]
    fconfigure $f -translation binary -encoding binary
    puts -nonewline $f $data
    close $f
}

connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}
foreach {name base} {
    q       0x10040000
    k       0x10060000
    v       0x10080000
    attn    0x100A0000
    res1    0x100C0000
    ln2     0x100E0000
    final   0x10020000
} {
    dump_binary $base $BYTES "$OUT_DIR/$name.bin"
}
disconnect
puts "LAYER0_STAGE_DUMP label=$LABEL bytes_per_stage=$BYTES dir=$OUT_DIR"
