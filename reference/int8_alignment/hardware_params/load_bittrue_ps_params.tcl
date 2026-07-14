set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set BITTRUE_LN_COEFF 0x13200000
set BITTRUE_LM_SCALE 0x13205000
dow -data -force -bypass-cache-sync "$repo/reference/int8_alignment/hardware_params/layernorm_coeff_q24.bin" $BITTRUE_LN_COEFF
dow -data -force -bypass-cache-sync "$repo/reference/int8_alignment/hardware_params/lm_head_scale_ratio_q30.bin" $BITTRUE_LM_SCALE
