set root [file normalize [file join [file dirname [info script]] ".."]]
set proj_dir $root
set proj [file join $proj_dir "nano_gpt.xpr"]
if {[file exists $proj]} {
    open_project $proj
} else {
    create_project nano_gpt $proj_dir -part xc7z020clg484-2 -force
}
set_property source_mgmt_mode All [current_project]

set chain_rtl [list \
    "$root/rtl/layernorm_hls_wrapper.v" \
    "$root/rtl/gelu_embed_hls_wrapper.v" \
    "$root/rtl/tiled_matmul_hls_wrapper.v" \
    "$root/rtl/mha_hls_wrapper.v" \
    "$root/rtl/pl_uart_ps_bridge.v" \
    "$root/rtl/hls_kernel_chain_axis_top.v" \
    "$root/rtl/hls_kernel_chain_axis_full_only_core.v" \
    "$root/rtl/hls_kernel_chain_axis_wrapper.v" \
]

foreach f $chain_rtl {
    if {[llength [get_files -quiet $f]] == 0} {
        add_files -fileset sources_1 -norecurse $f
    }
}

foreach f [list \
    "$root/rtl/layernorm_hls_wrapper.v" \
    "$root/rtl/gelu_embed_hls_wrapper.v" \
    "$root/rtl/tiled_matmul_hls_wrapper.v" \
    "$root/rtl/mha_hls_wrapper.v" \
    "$root/rtl/pl_uart_ps_bridge.v" \
    "$root/rtl/hls_kernel_chain_axis_top.v" \
    "$root/rtl/hls_kernel_chain_axis_full_only_core.v" \
] {
    set_property file_type SystemVerilog [get_files $f]
}
set_property file_type Verilog [get_files "$root/rtl/hls_kernel_chain_axis_wrapper.v"]
set uart_xdc "$root/constraints/uart_sp2_v12_pl.xdc"
if {[llength [get_files -quiet $uart_xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse $uart_xdc
}
foreach stale_timing [get_files -quiet *timing_75mhz.xdc] {
    remove_files $stale_timing
}
set timing_xdc "$root/constraints/timing_75mhz.xdc"
if {[llength [get_files -quiet $timing_xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse $timing_xdc
}
set verilog_defines [list INT8_TILE_MODE]
foreach env_name {INT8_Q_SHIFT INT8_FFN_SHIFT INT8_ATTN_PROJ_SHIFT INT8_FFN_MID_SHIFT} {
    if {[info exists ::env($env_name)] && [string trim $::env($env_name)] ne ""} {
        lappend verilog_defines "$env_name=$::env($env_name)"
    }
}
set full_only_synth 1
if {[info exists ::env(FULL_ONLY_SYNTH)] && [string trim $::env(FULL_ONLY_SYNTH)] eq "0"} {
    set full_only_synth 0
}
if {$full_only_synth} {
    lappend verilog_defines FULL_ONLY_SYNTH
    puts "SYSTEM_DDR_FULL_ONLY_SYNTH=1"
} else {
    puts "SYSTEM_DDR_FULL_ONLY_SYNTH=0"
}
set_property verilog_define $verilog_defines [get_filesets sources_1]

foreach pattern [list \
    "$root/optional_hls_ip/tiled_matmul/sol1/impl/ip/hdl/verilog/*.v" \
    "$root/optional_hls_ip/mha_kernel/sol1/impl/ip/hdl/verilog/*.v" \
    "$root/optional_hls_ip/layernorm_kernel/sol1/impl/ip/hdl/verilog/*.v" \
    "$root/optional_hls_ip/gelu_embed_kernel/sol1/impl/ip/hdl/verilog/*.v" \
] {
    foreach f [glob -nocomplain $pattern] {
        if {[llength [get_files -quiet $f]] == 0} {
            add_files -fileset sources_1 -norecurse $f
        }
    }
}
# Include final fixed-point initialization files. Vivado copies these into the
# synthesis/simulation working directory, matching the portable readmemh names.
set mem_files [concat     [glob -nocomplain [file join $root generated int8_alignment hardware_params *.mem]]     [glob -nocomplain [file join $root generated int8_quality_hw_exact_s256_d384_l6 luts *.mem]] \
    [glob -nocomplain [file join $root mem *.mem]]]
foreach mem_file $mem_files {
    if {[llength [get_files -quiet $mem_file]] == 0} {
        add_files -fileset sources_1 -norecurse $mem_file
    }
}
update_compile_order -fileset sources_1

set bd_name "system"
foreach bd_file [get_files -quiet *.bd] {
    remove_files $bd_file
}
foreach stale_dir [list \
    "$root/nano_gpt.srcs/sources_1/bd/$bd_name" \
    "$root/nano_gpt.gen/sources_1/bd/$bd_name" \
    "$root/nano_gpt.gen/sources_1/bd/mref/hls_kernel_chain_axis_top" \
    "$root/nano_gpt.gen/sources_1/bd/mref/hls_kernel_chain_axis_wrapper" \
] {
    if {[file exists $stale_dir]} {
        file delete -force $stale_dir
    }
}

create_bd_design $bd_name
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "0" Master "Disable" Slave "Disable"} \
    [get_bd_cells processing_system7_0]

set pl_clk_mhz 75.0
if {[info exists ::env(PL_CLK_MHZ)] && $::env(PL_CLK_MHZ) ne ""} {
    set pl_clk_mhz $::env(PL_CLK_MHZ)
}
set pl_clk_hz [expr {int(round(double($pl_clk_mhz) * 1000000.0))}]
puts "SYSTEM_DDR_PL_CLK_MHZ=$pl_clk_mhz"
puts "SYSTEM_DDR_PL_CLK_HZ=$pl_clk_hz"

set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $pl_clk_mhz \
    CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125} \
    CONFIG.PCW_UIPARAM_DDR_DEVICE_CAPACITY {4096 MBits} \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {16 Bit} \
    CONFIG.PCW_UIPARAM_DDR_BANK_ADDR_COUNT {3} \
    CONFIG.PCW_UIPARAM_DDR_ROW_ADDR_COUNT {15} \
    CONFIG.PCW_UIPARAM_DDR_COL_ADDR_COUNT {10} \
    CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {533.333333} \
    CONFIG.PCW_UIPARAM_DDR_SPEED_BIN {DDR3_1066F} \
    CONFIG.PCW_UIPARAM_DDR_CL {7} \
    CONFIG.PCW_UIPARAM_DDR_CWL {6} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_DATA_EYE {1} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_READ_GATE {1} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_WRITE_LEVEL {1} \
    CONFIG.PCW_DDR_RAM_BASEADDR {0x00100000} \
    CONFIG.PCW_DDR_RAM_HIGHADDR {0x1FFFFFFF} \
] [get_bd_cells processing_system7_0]

# Zynq FCLK uses integer PLL divisors, so requests such as 85 MHz may resolve
# to a nearby realizable value. Propagate that exact frequency to every custom
# interface instead of retaining the requested nominal value.
set realized_pl_clk_hz [get_property CONFIG.FREQ_HZ [get_bd_pins processing_system7_0/FCLK_CLK0]]
if {$realized_pl_clk_hz ne ""} {
    set pl_clk_hz $realized_pl_clk_hz
    puts "SYSTEM_DDR_REALIZED_PL_CLK_HZ=$pl_clk_hz"
}

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_m_axi_mm2s_data_width {32} \
    CONFIG.c_m_axi_s2mm_data_width {32} \
    CONFIG.c_m_axis_mm2s_tdata_width {8} \
    CONFIG.c_s_axis_s2mm_tdata_width {8} \
] [get_bd_cells axi_dma_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_0_100M
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 smartconnect_gp0
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_ddr
set_property -dict [list CONFIG.NUM_MI {2}] [get_bd_cells smartconnect_gp0]
set_property -dict [list CONFIG.NUM_SI {3} CONFIG.NUM_MI {1}] [get_bd_cells smartconnect_ddr]

create_bd_cell -type module -reference hls_kernel_chain_axis_top hls_kernel_chain_axis_top_0
set_property -dict [list \
    CONFIG.STREAM_BYTES {8192} \
    CONFIG.BYPASS_HLS {0} \
    CONFIG.PL_CLK_HZ $pl_clk_hz \
] [get_bd_cells hls_kernel_chain_axis_top_0]
create_bd_port -dir I uart_rx
create_bd_port -dir O uart_tx
connect_bd_net [get_bd_ports uart_rx] [get_bd_pins hls_kernel_chain_axis_top_0/uart_rx]
connect_bd_net [get_bd_ports uart_tx] [get_bd_pins hls_kernel_chain_axis_top_0/uart_tx]
foreach intf_name {s_axi s_axis m_axis m_axi_ddr} {
    set intf_pin [get_bd_intf_pins -quiet hls_kernel_chain_axis_top_0/$intf_name]
    if {[llength $intf_pin] != 0} {
        set_property CONFIG.FREQ_HZ $pl_clk_hz $intf_pin
    }
}
set clk_pin [get_bd_pins -quiet hls_kernel_chain_axis_top_0/s_axi_aclk]
if {[llength $clk_pin] != 0} {
    set_property CONFIG.FREQ_HZ $pl_clk_hz $clk_pin
}

connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] \
               [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK] \
               [get_bd_pins rst_ps7_0_100M/slowest_sync_clk] \
               [get_bd_pins axi_dma_0/s_axi_lite_aclk] \
               [get_bd_pins axi_dma_0/m_axi_mm2s_aclk] \
               [get_bd_pins axi_dma_0/m_axi_s2mm_aclk] \
               [get_bd_pins smartconnect_gp0/ACLK] \
               [get_bd_pins smartconnect_gp0/S00_ACLK] \
               [get_bd_pins smartconnect_gp0/M00_ACLK] \
               [get_bd_pins smartconnect_gp0/M01_ACLK] \
               [get_bd_pins smartconnect_ddr/aclk] \
               [get_bd_pins hls_kernel_chain_axis_top_0/s_axi_aclk]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins rst_ps7_0_100M/ext_reset_in]
connect_bd_net [get_bd_pins rst_ps7_0_100M/interconnect_aresetn] \
               [get_bd_pins smartconnect_gp0/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] \
               [get_bd_pins axi_dma_0/axi_resetn] \
               [get_bd_pins hls_kernel_chain_axis_top_0/s_axi_aresetn] \
               [get_bd_pins smartconnect_gp0/S00_ARESETN] \
               [get_bd_pins smartconnect_gp0/M00_ARESETN] \
               [get_bd_pins smartconnect_gp0/M01_ARESETN]

connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] [get_bd_intf_pins smartconnect_gp0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_gp0/M00_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins smartconnect_gp0/M01_AXI] [get_bd_intf_pins hls_kernel_chain_axis_top_0/s_axi]

connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins smartconnect_ddr/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins smartconnect_ddr/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins hls_kernel_chain_axis_top_0/m_axi_ddr] [get_bd_intf_pins smartconnect_ddr/S02_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_ddr/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins hls_kernel_chain_axis_top_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins hls_kernel_chain_axis_top_0/m_axis] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

assign_bd_address

foreach seg [get_bd_addr_segs -quiet -hier *SEG_axi_dma_0_Reg] {
    set_property offset 0x40400000 $seg
    set_property range 0x00010000 $seg
}
foreach seg [get_bd_addr_segs -quiet -hier *SEG_hls_kernel_chain_axis_top_0_reg0] {
    set_property offset 0x40000000 $seg
    set_property range 0x00001000 $seg
}

validate_bd_design
save_bd_design

set system_bd [get_files "$root/nano_gpt.srcs/sources_1/bd/system/system.bd"]
set_property synth_checkpoint_mode None $system_bd
reset_target all $system_bd
generate_target all $system_bd

make_wrapper -files [get_files "$root/nano_gpt.srcs/sources_1/bd/system/system.bd"] -top
add_files -norecurse "$root/nano_gpt.gen/sources_1/bd/system/hdl/system_wrapper.v"
set_property source_mgmt_mode All [current_project]
# Include final fixed-point initialization files. Vivado copies these into the
# synthesis/simulation working directory, matching the portable readmemh names.
set mem_files [concat     [glob -nocomplain [file join $root generated int8_alignment hardware_params *.mem]]     [glob -nocomplain [file join $root generated int8_quality_hw_exact_s256_d384_l6 luts *.mem]] \
    [glob -nocomplain [file join $root mem *.mem]]]
foreach mem_file $mem_files {
    if {[llength [get_files -quiet $mem_file]] == 0} {
        add_files -fileset sources_1 -norecurse $mem_file
    }
}
update_compile_order -fileset sources_1
set_property top system_wrapper [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
puts "SYSTEM_DDR_BD_DONE dma_memory_target=processing_system7_0/S_AXI_HP0 ddr_input=0x10000000 ddr_output=0x10002000"
close_project

