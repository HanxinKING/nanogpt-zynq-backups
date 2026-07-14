set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set root "$repo"
set nano "$repo/vivado_project"
set ps7_init "$repo/vitis/workspace/nanogpt_qkt8_platform/hw/ps7_init.tcl"
set image_dir "$repo/reference/ddr_image"
set emb_dir "$repo/reference/ps_ddr_embedding_tables"
set elf "$repo/ps/build/ps_mailbox_runner.elf"
if {[info exists ::env(MAILBOX_ELF)]} { set elf $::env(MAILBOX_ELF) }

set BIT "$repo/artifacts/system.bit"
if {[info exists ::env(BIT_FILE)]} { set BIT $::env(BIT_FILE) }
set PS7_INIT $ps7_init
set LAYER_A 0x10000000
set WEIGHTS 0x11000000
set SCALES 0x11C00000
set GOLDEN 0x12000000
set LUTS 0x12100000
set QUALITY_PARAMS 0x12200000
set MAILBOX 0x00020000
set MAILBOX_CMD 0
set PROMPT_TEXT "hello world"
set MAX_NEW_TOKENS 8
set UART_CONSOLE 0
if {[info exists ::env(MAILBOX_CMD)]} { set MAILBOX_CMD $::env(MAILBOX_CMD) }
if {[info exists ::env(MAILBOX_PROMPT)]} { set PROMPT_TEXT $::env(MAILBOX_PROMPT) }
if {[info exists ::env(MAILBOX_MAX_NEW_TOKENS)]} { set MAX_NEW_TOKENS $::env(MAILBOX_MAX_NEW_TOKENS) }
if {[info exists ::env(UART_CONSOLE)]} { set UART_CONSOLE $::env(UART_CONSOLE) }

proc w32 {addr value} { mwr -force $addr $value }
proc r32 {addr} { return [expr {[mrd -force -value $addr] & 0xffffffff}] }

proc download_bin {base file label} {
    if {![file exists $file]} {
        puts [format "MAILBOX_RUN_FAIL missing_%s=%s" $label $file]
        exit 1
    }
    puts [format "DOWNLOAD %s base=0x%08x file=%s" $label $base $file]
    dow -data -force -bypass-cache-sync $file $base
}

proc write_prompt {base text} {
    global MAILBOX_CMD MAX_NEW_TOKENS
    set n [string length $text]
    w32 [expr {$base + 0x00}] 0x4e475054
    w32 [expr {$base + 0x04}] 0x00000001
    w32 [expr {$base + 0x08}] $n
    w32 [expr {$base + 0x24}] $MAILBOX_CMD
    w32 [expr {$base + 0x28}] $MAX_NEW_TOKENS
    for {set i 0} {$i < $n} {incr i} {
        binary scan [string index $text $i] c ch
        mwr -force [expr {$base + 0x100 + ($i * 4)}] [expr {$ch & 0xff}]
    }
}

proc poll_mailbox {base timeout_ms} {
    set elapsed 0
    set last_state 0xffffffff
    while {$elapsed < $timeout_ms} {
        set state [r32 [expr {$base + 0x04}]]
        set rc [r32 [expr {$base + 0x0c}]]
        set status [r32 [expr {$base + 0x10}]]
        set full_status [r32 [expr {$base + 0x14}]]
        set stage [r32 [expr {$base + 0x18}]]
        set layer [r32 [expr {$base + 0x20}]]
        if {$state != $last_state || [expr {$elapsed % 10000}] == 0} {
            puts [format "POLL t=%d state=0x%08x rc=0x%08x status=0x%08x full_status=0x%08x stage=0x%08x layer=%d" $elapsed $state $rc $status $full_status $stage $layer]
            set last_state $state
        }
        if {$state == 0x00009001 || $state == 0x00009002 || $state == 0x00009003 || $state == 0x00009005 || $state == 0x0000900d || (($state & 0xffff0000) == 0xdead0000)} {
            return
        }
        after 1000
        incr elapsed 1000
    }
    puts [format "POLL_TIMEOUT timeout_ms=%d" $timeout_ms]
}

proc read_results {base max_new_tokens} {
    set magic [r32 [expr {$base + 0x00}]]
    set state [r32 [expr {$base + 0x04}]]
    set rc [r32 [expr {$base + 0x0c}]]
    set status [r32 [expr {$base + 0x10}]]
    set full_status [r32 [expr {$base + 0x14}]]
    set stage [r32 [expr {$base + 0x18}]]
    set sig [r32 [expr {$base + 0x1c}]]
    puts [format "MAILBOX_RESULT magic=0x%08x state=0x%08x rc=0x%08x status=0x%08x full_status=0x%08x stage=0x%08x hls_sig=0x%08x" $magic $state $rc $status $full_status $stage $sig]
    set generated [r32 [expr {$base + 0x2c}]]
    if {$generated > $max_new_tokens} { set generated $max_new_tokens }
    set toks {}
    set chars ""
    for {set i 0} {$i < $generated} {incr i} {
        lappend toks [r32 [expr {$base + 0x400 + ($i * 4)}]]
        set c [r32 [expr {$base + 0x900 + ($i * 4)}]]
        append chars [format %c $c]
    }
    puts [format "GENERATED_COUNT %d" $generated]
    puts [format "GENERATED_TOKENS %s" $toks]
    puts [format "GENERATED %s" $chars]
}

if {![file exists $elf]} {
    puts [format "MAILBOX_RUN_FAIL missing_elf=%s" $elf]
    exit 1
}

connect
puts "TARGETS_BEFORE_RECOVER"
puts [targets]
source $PS7_INIT
catch {targets -set 1}
catch {rst -system} rst_msg
puts [format "TARGET1_RST_SYSTEM=%s" $rst_msg]
after 3000
puts "TARGETS_AFTER_RECOVER"
puts [targets]
catch {targets -set -filter {name =~ "APU*"}}
ps7_init
ps7_post_config
targets -set -filter {name =~ "xc7z020*"}
fpga -file $BIT
after 2000
catch {targets -set -filter {name =~ "APU*"}}
ps7_init
ps7_post_config
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}
catch {rst -processor}
after 1000
catch {stop}
catch {memmap -addr 0x00000000 -size 0x40000000 -flags rw}

if {$MAILBOX_CMD == 1} {
    puts "DOWNLOAD_SKIP embedding_only"
} else {
    download_bin $LAYER_A "$image_dir/input.bin" input
    download_bin $WEIGHTS "$image_dir/weights.bin" weights
    download_bin $SCALES "$image_dir/scales.bin" scales
    download_bin $GOLDEN "$image_dir/golden_final.bin" golden_final
    download_bin $LUTS "$image_dir/luts.bin" luts
    download_bin $QUALITY_PARAMS "$image_dir/quality_params.bin" quality_params
}
source "$emb_dir/load_ps_ddr_embedding_tables.tcl"
source "$nano/generated/int8_alignment/hardware_params/load_bittrue_ps_params.tcl"

catch {rst -processor}
after 1000
dow -force $elf
catch {mrd -force 0x00000000 4} elf_head
puts [format "ELF_HEAD %s" $elf_head]
catch {rrd pc} pc_after_dow
puts [format "PC_AFTER_DOW %s" $pc_after_dow]
catch {rwr pc 0x00000000} pc_set_msg
puts [format "PC_SET_0 %s" $pc_set_msg]
catch {rrd pc} pc_after_set
puts [format "PC_AFTER_SET %s" $pc_after_set]
if {$UART_CONSOLE == 1} {
    w32 [expr {$MAILBOX + 0x08}] 0
    w32 [expr {$MAILBOX + 0x04}] 0
    puts "UART_CONSOLE_START baud=115200 format=8N1 rx=M17 tx=L17 onboard_ftdi=1"
    catch {con} con_msg
    puts [format "CON_RESULT %s" $con_msg]
    after 2000
    disconnect
    exit 0
}
puts [format "MAILBOX_CONFIG cmd=%s prompt=%s" $MAILBOX_CMD $PROMPT_TEXT]
write_prompt $MAILBOX $PROMPT_TEXT
catch {con} con_msg
puts [format "CON_RESULT %s" $con_msg]
poll_mailbox $MAILBOX 3600000
catch {stop}
catch {rrd pc} pc_after_stop
puts [format "PC_AFTER_STOP %s" $pc_after_stop]
read_results $MAILBOX $MAX_NEW_TOKENS
disconnect
