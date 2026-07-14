if {$argc != 3} {
    error "Usage: xsct create_platform.tcl <workspace> <xsa> <ps_source_dir>"
}

set workspace [file normalize [lindex $argv 0]]
set xsa [file normalize [lindex $argv 1]]
set ps_source_dir [file normalize [lindex $argv 2]]
set make_dir {F:/Vivado2025.2/2025.2/Vitis/gnuwin/bin}
set gcc_dir {F:/Vivado2025.2/2025.2/gnu/aarch32/nt/gcc-arm-none-eabi/bin}
set ::env(PATH) "$make_dir;$gcc_dir;$::env(PATH)"
set ::env(Path) $::env(PATH)
if {[catch {exec C:/Windows/System32/where.exe make} make_probe]} {
    puts stderr "MAKE_PROBE_ERROR=$make_probe"
} else {
    puts "MAKE_PROBE=$make_probe"
}
if {[catch {exec C:/Windows/System32/where.exe arm-none-eabi-gcc} gcc_probe]} {
    puts stderr "GCC_PROBE_ERROR=$gcc_probe"
} else {
    puts "GCC_PROBE=$gcc_probe"
}
file mkdir $workspace
setws $workspace

if {[catch {platform remove nanogpt_qkt8_platform}]} {
    # The platform may not exist on the first run.
}
if {[catch {
    platform create -name nanogpt_qkt8_platform -hw $xsa -proc ps7_cortexa9_0 -os standalone
    set wrapper_text {@echo off
set "PATH=F:\Vivado2025.2\2025.2\Vitis\gnuwin\bin;F:\Vivado2025.2\2025.2\gnu\aarch32\nt\gcc-arm-none-eabi\bin;%SystemRoot%\System32;%PATH%"
"F:\Vivado2025.2\2025.2\Vitis\gnuwin\bin\make.exe" %*
}
    foreach build_dir [list \
        [file join $workspace nanogpt_qkt8_platform zynq_fsbl] \
        [file join $workspace nanogpt_qkt8_platform ps7_cortexa9_0 standalone_domain bsp]] {
        file mkdir $build_dir
        set wrapper [open [file join $build_dir make.cmd] w]
        puts -nonewline $wrapper $wrapper_text
        close $wrapper
        foreach runtime_file {make.exe libiconv2.dll libintl3.dll} {
            file copy -force \
                [file join {F:/Vivado2025.2/2025.2/Vitis/gnuwin/bin} $runtime_file] \
                [file join $build_dir $runtime_file]
        }
    }
    set make_exe {F:/Vivado2025.2/2025.2/Vitis/gnuwin/bin/make.exe}
    set fsbl_dir [file join $workspace nanogpt_qkt8_platform zynq_fsbl]
    set bsp_dir [file join $workspace nanogpt_qkt8_platform ps7_cortexa9_0 standalone_domain bsp]
    puts "MANUAL_BUILD=FSBL_BSP"
    puts [exec $make_exe -C [file join $fsbl_dir zynq_fsbl_bsp] 2>@1]
    puts "MANUAL_BUILD=FSBL_APP"
    puts [exec $make_exe -C $fsbl_dir 2>@1]
    puts "MANUAL_BUILD=STANDALONE_BSP"
    puts [exec $make_exe -C $bsp_dir 2>@1]
    platform write
    if {[catch {app remove ps_mailbox_runner_vitis}]} {
        # The application may not exist on the first run.
    }
    app create -name ps_mailbox_runner_vitis -platform nanogpt_qkt8_platform -domain standalone_domain -template {Empty Application(C)}
    set app_source_dir [file join $workspace ps_mailbox_runner_vitis src]
    file mkdir $app_source_dir
    foreach source_file [glob -nocomplain -directory $ps_source_dir *] {
        file copy -force $source_file $app_source_dir
    }
} message options]} {
    puts stderr "VITIS_PLATFORM_ERROR=$message"
    puts stderr [dict get $options -errorinfo]
    exit 1
}
puts "WORKSPACE=$workspace"
puts "PLATFORM=nanogpt_qkt8_platform"
puts "APPLICATION=ps_mailbox_runner_vitis"
exit
