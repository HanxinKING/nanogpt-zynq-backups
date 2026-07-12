set BITTRUE_LN_COEFF 0x13200000
set BITTRUE_LM_SCALE 0x13205000
set param_dir [file normalize [file dirname [info script]]]
dow -data -force -bypass-cache-sync [file join $param_dir layernorm_coeff_q24.bin] $BITTRUE_LN_COEFF
dow -data -force -bypass-cache-sync [file join $param_dir lm_head_scale_ratio_q30.bin] $BITTRUE_LM_SCALE
