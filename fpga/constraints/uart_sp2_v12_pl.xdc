# Smart Zynq SP2 V1.2 onboard FT2232H PL UART, 3.3 V, 115200 8N1.
# Board schematic: ZYNQ_RX=M17 and ZYNQ_TX=L17.
set_property PACKAGE_PIN M17 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
set_property PULLUP true [get_ports uart_rx]

set_property PACKAGE_PIN L17 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
set_property DRIVE 8 [get_ports uart_tx]
set_property SLEW SLOW [get_ports uart_tx]
