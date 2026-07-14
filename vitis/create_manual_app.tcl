if {$argc != 1} {
    error "Usage: xsct create_manual_app.tcl <workspace>"
}

set workspace [file normalize [lindex $argv 0]]
setws $workspace

if {[catch {app remove ps_mailbox_runner_manual}]} {
    # The manual-import application does not exist on the first run.
}

app create \
    -name ps_mailbox_runner_manual \
    -platform nanogpt_qkt8_platform \
    -domain standalone_domain \
    -template {Empty Application(C)}

puts "WORKSPACE=$workspace"
puts "APPLICATION=ps_mailbox_runner_manual"
exit
