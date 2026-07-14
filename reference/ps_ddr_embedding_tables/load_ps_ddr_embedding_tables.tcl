set repo [file normalize [file dirname [info script]]]
while {![file exists [file join $repo README.md]] && [file dirname $repo] ne $repo} { set repo [file dirname $repo] }

set TOK_EMB_I8 0x13000000
set POS_EMB_I8 0x13010000
set TOK_EMB_SCALE_Q30 0x13028000
set POS_EMB_SCALE_Q30 0x13028400
dow -data -force -bypass-cache-sync "$repo/reference/ps_ddr_embedding_tables/token_embedding_i8.bin" $TOK_EMB_I8
dow -data -force -bypass-cache-sync "$repo/reference/ps_ddr_embedding_tables/position_embedding_i8.bin" $POS_EMB_I8
dow -data -force -bypass-cache-sync "$repo/reference/ps_ddr_embedding_tables/token_embedding_scale_q30.bin" $TOK_EMB_SCALE_Q30
dow -data -force -bypass-cache-sync "$repo/reference/ps_ddr_embedding_tables/position_embedding_scale_q30.bin" $POS_EMB_SCALE_Q30
