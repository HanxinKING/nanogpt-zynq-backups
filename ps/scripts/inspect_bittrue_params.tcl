connect
targets -set -filter {name =~ "*Cortex-A9*#0"}
catch {stop}
puts "LN_COEFF_HEAD"
puts [mrd -force 0x13200000 16]
puts "LM_SCALE_HEAD"
puts [mrd -force 0x13205000 8]
disconnect
