set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set root "$repo"
set nano "$repo/vivado_project"
set elf "$repo/ps/build/ps_mailbox_runner.elf"
set mailbox 0x00020000

if {![file exists $elf]} {
    puts [format "UART_RESTART_FAIL missing_elf=%s" $elf]
    exit 1
}

connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}
catch {rst -processor}
after 500
catch {memmap -addr 0x00000000 -size 0x40000000 -flags rw}
dow -force $elf
mwr -force [expr {$mailbox + 0x08}] 0
mwr -force [expr {$mailbox + 0x04}] 0
catch {rwr pc 0x00000000}
catch {con} con_msg
puts [format "UART_CONSOLE_RESTARTED elf=%s con=%s" $elf $con_msg]
after 500
disconnect
