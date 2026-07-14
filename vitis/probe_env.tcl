puts "TCL_PATH=$::env(PATH)"
if {[catch {exec cmd.exe /d /c where make} result]} {
    puts stderr "WHERE_MAKE_ERROR=$result"
} else {
    puts "WHERE_MAKE=$result"
}
if {[catch {exec cmd.exe /d /c where arm-none-eabi-gcc} result]} {
    puts stderr "WHERE_GCC_ERROR=$result"
} else {
    puts "WHERE_GCC=$result"
}
exit
