# Keep additional implementation margin while the PS FCLK remains exactly
# 100 MHz. This guard-band applies only to setup/recovery analysis.
set_clock_uncertainty -setup 0.750 [get_clocks clk_fpga_0]

# Debug-only status capture is not consumed by the model datapath.
set_false_path -to [get_pins -hier -filter {NAME =~ */u_core/full_mismatch_debug_reg_reg*/D}]

# Requantization inputs are held stable by the explicit *_QUANT_WAIT states.
set_multicycle_path 2 -setup -to [get_pins -hier -filter {NAME =~ */u_core/q_value_reg*/D}]
set_multicycle_path 1 -hold  -to [get_pins -hier -filter {NAME =~ */u_core/q_value_reg*/D}]

# The shared multiplier operand is loaded after DDR/ROM wait states and is
# consumed only in the following multiply state.
set_multicycle_path 2 -setup -to [get_pins -hier -filter {NAME =~ */u_core/ffn_mul_a_reg*/D}]
set_multicycle_path 1 -hold  -to [get_pins -hier -filter {NAME =~ */u_core/ffn_mul_a_reg*/D}]

# FFN W1 requantization is entered through ST_FFN_W1_QUANT_WAIT.
set_multicycle_path 2 -setup -to [get_pins -hier -filter {NAME =~ */u_core/ffn_mid_wr_data_reg*/D}]
set_multicycle_path 1 -hold  -to [get_pins -hier -filter {NAME =~ */u_core/ffn_mid_wr_data_reg*/D}]

# Quantized values cross residual/AXI wait states before the DDR write packer.
set_multicycle_path 2 -setup \
    -from [get_pins -hier -filter {NAME =~ */u_core/q_value_reg*/C}] \
    -to   [get_pins -hier -filter {NAME =~ */u_core/ddr_wdata_stage_reg*/D}]
set_multicycle_path 1 -hold \
    -from [get_pins -hier -filter {NAME =~ */u_core/q_value_reg*/C}] \
    -to   [get_pins -hier -filter {NAME =~ */u_core/ddr_wdata_stage_reg*/D}]

# The legacy LM-head path holds mac_dim throughout its DDR request/wait pair.
set_multicycle_path 2 -setup \
    -from [get_pins -hier -filter {NAME =~ */u_core/mac_dim_reg*/C}] \
    -to   [get_pins -hier -filter {NAME =~ */u_core/lm_acc_reg*/D}]
set_multicycle_path 1 -hold \
    -from [get_pins -hier -filter {NAME =~ */u_core/mac_dim_reg*/C}] \
    -to   [get_pins -hier -filter {NAME =~ */u_core/lm_acc_reg*/D}]
