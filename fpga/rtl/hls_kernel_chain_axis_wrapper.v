`timescale 1ns/1ps

(* keep_hierarchy = "yes" *)
module hls_kernel_chain_axis_top #(
    parameter integer STREAM_BYTES = 8192,
    parameter integer BYPASS_HLS = 0,
    parameter integer PL_CLK_HZ = 75000000
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi:s_axis:m_axis:m_axi_ddr, ASSOCIATED_RESET s_axi_aresetn" *)
    input  wire         s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire         s_axi_aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWADDR" *)
    input  wire [7:0]   s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWVALID" *)
    input  wire         s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWREADY" *)
    output wire         s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WDATA" *)
    input  wire [31:0]  s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WSTRB" *)
    input  wire [3:0]   s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WVALID" *)
    input  wire         s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WREADY" *)
    output wire         s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BRESP" *)
    output wire [1:0]   s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BVALID" *)
    output wire         s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BREADY" *)
    input  wire         s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARADDR" *)
    input  wire [7:0]   s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARVALID" *)
    input  wire         s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARREADY" *)
    output wire         s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RDATA" *)
    output wire [31:0]  s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RRESP" *)
    output wire [1:0]   s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RVALID" *)
    output wire         s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RREADY" *)
    input  wire         s_axi_rready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TDATA" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s_axis, TDATA_NUM_BYTES 1, HAS_TLAST 1, HAS_TKEEP 0, HAS_TSTRB 0, HAS_TREADY 1" *)
    input  wire [7:0]   s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TVALID" *)
    input  wire         s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TREADY" *)
    output wire         s_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TLAST" *)
    input  wire         s_axis_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TDATA" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME m_axis, TDATA_NUM_BYTES 1, HAS_TLAST 1, HAS_TKEEP 0, HAS_TSTRB 0, HAS_TREADY 1" *)
    output wire [7:0]   m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TVALID" *)
    output wire         m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TREADY" *)
    input  wire         m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TLAST" *)
    output wire         m_axis_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr ARADDR" *)
    output wire [31:0]  m_axi_ddr_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr ARVALID" *)
    output wire         m_axi_ddr_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr ARREADY" *)
    input  wire         m_axi_ddr_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr ARLEN" *)
    output wire [7:0]   m_axi_ddr_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr ARSIZE" *)
    output wire [2:0]   m_axi_ddr_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr ARBURST" *)
    output wire [1:0]   m_axi_ddr_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr ARCACHE" *)
    output wire [3:0]   m_axi_ddr_arcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr ARPROT" *)
    output wire [2:0]   m_axi_ddr_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr RDATA" *)
    input  wire [63:0]  m_axi_ddr_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr RVALID" *)
    input  wire         m_axi_ddr_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr RREADY" *)
    output wire         m_axi_ddr_rready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr RRESP" *)
    input  wire [1:0]   m_axi_ddr_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr RLAST" *)
    input  wire         m_axi_ddr_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr AWADDR" *)
    output wire [31:0]  m_axi_ddr_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr AWVALID" *)
    output wire         m_axi_ddr_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr AWREADY" *)
    input  wire         m_axi_ddr_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr AWLEN" *)
    output wire [7:0]   m_axi_ddr_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr AWSIZE" *)
    output wire [2:0]   m_axi_ddr_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr AWBURST" *)
    output wire [1:0]   m_axi_ddr_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr AWCACHE" *)
    output wire [3:0]   m_axi_ddr_awcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr AWPROT" *)
    output wire [2:0]   m_axi_ddr_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr WDATA" *)
    output wire [63:0]  m_axi_ddr_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr WSTRB" *)
    output wire [7:0]   m_axi_ddr_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr WVALID" *)
    output wire         m_axi_ddr_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr WREADY" *)
    input  wire         m_axi_ddr_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr WLAST" *)
    output wire         m_axi_ddr_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr BRESP" *)
    input  wire [1:0]   m_axi_ddr_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr BVALID" *)
    input  wire         m_axi_ddr_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr BREADY" *)
    output wire         m_axi_ddr_bready,
    input  wire         uart_rx,
    output wire         uart_tx,
    output wire         irq
);
`ifdef FULL_ONLY_SYNTH
    hls_kernel_chain_axis_full_only_core #(
        .STREAM_BYTES(STREAM_BYTES),
        .BYPASS_HLS(BYPASS_HLS),
        .PL_CLK_HZ(PL_CLK_HZ)
    ) u_core (
`else
    hls_kernel_chain_axis_core #(
        .STREAM_BYTES(STREAM_BYTES),
        .BYPASS_HLS(BYPASS_HLS),
        .PL_CLK_HZ(PL_CLK_HZ)
    ) u_core (
`endif
        .s_axi_aclk(s_axi_aclk),
        .s_axi_aresetn(s_axi_aresetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .m_axi_ddr_araddr(m_axi_ddr_araddr),
        .m_axi_ddr_arvalid(m_axi_ddr_arvalid),
        .m_axi_ddr_arready(m_axi_ddr_arready),
        .m_axi_ddr_arlen(m_axi_ddr_arlen),
        .m_axi_ddr_arsize(m_axi_ddr_arsize),
        .m_axi_ddr_arburst(m_axi_ddr_arburst),
        .m_axi_ddr_arcache(m_axi_ddr_arcache),
        .m_axi_ddr_arprot(m_axi_ddr_arprot),
        .m_axi_ddr_rdata(m_axi_ddr_rdata),
        .m_axi_ddr_rvalid(m_axi_ddr_rvalid),
        .m_axi_ddr_rready(m_axi_ddr_rready),
        .m_axi_ddr_rresp(m_axi_ddr_rresp),
        .m_axi_ddr_rlast(m_axi_ddr_rlast),
        .m_axi_ddr_awaddr(m_axi_ddr_awaddr),
        .m_axi_ddr_awvalid(m_axi_ddr_awvalid),
        .m_axi_ddr_awready(m_axi_ddr_awready),
        .m_axi_ddr_awlen(m_axi_ddr_awlen),
        .m_axi_ddr_awsize(m_axi_ddr_awsize),
        .m_axi_ddr_awburst(m_axi_ddr_awburst),
        .m_axi_ddr_awcache(m_axi_ddr_awcache),
        .m_axi_ddr_awprot(m_axi_ddr_awprot),
        .m_axi_ddr_wdata(m_axi_ddr_wdata),
        .m_axi_ddr_wstrb(m_axi_ddr_wstrb),
        .m_axi_ddr_wvalid(m_axi_ddr_wvalid),
        .m_axi_ddr_wready(m_axi_ddr_wready),
        .m_axi_ddr_wlast(m_axi_ddr_wlast),
        .m_axi_ddr_bresp(m_axi_ddr_bresp),
        .m_axi_ddr_bvalid(m_axi_ddr_bvalid),
        .m_axi_ddr_bready(m_axi_ddr_bready),
`ifdef FULL_ONLY_SYNTH
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
`endif
        .irq(irq)
    );
`ifndef FULL_ONLY_SYNTH
    assign uart_tx = 1'b1;
`endif
endmodule
