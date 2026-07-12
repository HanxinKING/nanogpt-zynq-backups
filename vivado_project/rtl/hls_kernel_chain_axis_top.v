`timescale 1ns/1ps

(* keep_hierarchy = "yes" *)
module hls_kernel_chain_axis_core #(
    parameter integer STREAM_BYTES = 8192,
    parameter integer BYPASS_HLS = 0,
    parameter integer PL_CLK_HZ = 75000000
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi:s_axis:m_axis:m_axi_ddr, ASSOCIATED_RESET s_axi_aresetn, FREQ_HZ 75000000" *)
    input  wire         s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire         s_axi_aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWADDR" *)
    input  wire [7:0]   s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWVALID" *)
    input  wire         s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWREADY" *)
    output logic        s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WDATA" *)
    input  wire [31:0]  s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WSTRB" *)
    input  wire [3:0]   s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WVALID" *)
    input  wire         s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WREADY" *)
    output logic        s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BRESP" *)
    output logic [1:0]  s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BVALID" *)
    output logic        s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BREADY" *)
    input  wire         s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARADDR" *)
    input  wire [7:0]   s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARVALID" *)
    input  wire         s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARREADY" *)
    output logic        s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RDATA" *)
    output logic [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RRESP" *)
    output logic [1:0]  s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RVALID" *)
    output logic        s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RREADY" *)
    input  wire         s_axi_rready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TDATA" *)
    (* X_INTERFACE_PARAMETER = "TDATA_NUM_BYTES 1, FREQ_HZ 75000000" *)
    input  wire [7:0]   s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TVALID" *)
    input  wire         s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TREADY" *)
    output logic        s_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TLAST" *)
    input  wire         s_axis_tlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TDATA" *)
    (* X_INTERFACE_PARAMETER = "TDATA_NUM_BYTES 1, FREQ_HZ 50000000" *)
    output logic [7:0]  m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TVALID" *)
    output logic        m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TREADY" *)
    input  wire         m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TLAST" *)
    output logic        m_axis_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr ARADDR" *)
    output logic [31:0] m_axi_ddr_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr ARVALID" *)
    output logic        m_axi_ddr_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr ARREADY" *)
    input  wire         m_axi_ddr_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr ARLEN" *)
    output logic [7:0]  m_axi_ddr_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr ARSIZE" *)
    output logic [2:0]  m_axi_ddr_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr ARBURST" *)
    output logic [1:0]  m_axi_ddr_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr ARCACHE" *)
    output logic [3:0]  m_axi_ddr_arcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr ARPROT" *)
    output logic [2:0]  m_axi_ddr_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr RDATA" *)
    input  wire [63:0]  m_axi_ddr_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr RVALID" *)
    input  wire         m_axi_ddr_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr RREADY" *)
    output logic        m_axi_ddr_rready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr RRESP" *)
    input  wire [1:0]   m_axi_ddr_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr RLAST" *)
    input  wire         m_axi_ddr_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr AWADDR" *)
    output logic [31:0] m_axi_ddr_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr AWVALID" *)
    output logic        m_axi_ddr_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr AWREADY" *)
    input  wire         m_axi_ddr_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr AWLEN" *)
    output logic [7:0]  m_axi_ddr_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr AWSIZE" *)
    output logic [2:0]  m_axi_ddr_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr AWBURST" *)
    output logic [1:0]  m_axi_ddr_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr AWCACHE" *)
    output logic [3:0]  m_axi_ddr_awcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr AWPROT" *)
    output logic [2:0]  m_axi_ddr_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr WDATA" *)
    output logic [63:0] m_axi_ddr_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr WSTRB" *)
    output logic [7:0]  m_axi_ddr_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr WVALID" *)
    output logic        m_axi_ddr_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr WREADY" *)
    input  wire         m_axi_ddr_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr WLAST" *)
    output logic        m_axi_ddr_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr BRESP" *)
    input  wire [1:0]   m_axi_ddr_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr BVALID" *)
    input  wire         m_axi_ddr_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 m_axi_ddr BREADY" *)
    output logic        m_axi_ddr_bready,
    output logic        irq
);
    localparam integer SEQ_LEN = 32;
    localparam integer D_MODEL = 256;
    localparam integer N_HEAD = 4;
    localparam integer HEAD_DIM = 64;
    localparam integer INPUT_WORDS = 8192;
    localparam integer WEIGHT_BYTES = 65536;
    localparam integer WEIGHT_WORDS32 = WEIGHT_BYTES / 4;
    localparam integer FULL_BYTES = 98304;
    localparam integer FULL_WORDS32 = FULL_BYTES / 4;
    localparam integer FULL_D_MODEL = 384;
    localparam integer FULL_Q_OUT = 256;
    localparam integer FULL_Q_ROWS = 32;
    localparam integer FULL_Q_WEIGHT_BYTES = FULL_D_MODEL * FULL_Q_OUT;
    localparam integer FULL_Q_WEIGHT_WORDS32 = FULL_Q_WEIGHT_BYTES / 4;
`ifndef FULL_INT8_Q_SHIFT
`define FULL_INT8_Q_SHIFT 13
`endif
    localparam integer FULL_Q_SHIFT = `FULL_INT8_Q_SHIFT;
    localparam logic [31:0] DEFAULT_WEIGHTS_BASE = 32'h1100_0000;
    localparam logic [31:0] DEFAULT_FULL_INPUT_BASE = 32'h1000_0000;
    localparam logic [31:0] DEFAULT_FULL_OUTPUT_BASE = 32'h1002_0000;
    localparam logic [31:0] DEFAULT_FULL_SCALES_BASE = 32'h11C0_0000;
    localparam logic [31:0] DEFAULT_FULL_DEBUG_BASE = 32'h12E0_0000;
    localparam logic [31:0] FULL_CONFIG_VERSION = 32'hF117_0001;
`ifndef INT8_Q_SHIFT
`define INT8_Q_SHIFT 12
`endif
`ifndef INT8_FFN_SHIFT
`define INT8_FFN_SHIFT 2
`endif
    localparam integer Q_SHIFT = `INT8_Q_SHIFT;
    localparam integer FFN_SHIFT = `INT8_FFN_SHIFT;
    localparam logic [12:0] EMIT_LAST = STREAM_BYTES - 1;
`ifdef FULL_ONLY_SYNTH
    localparam integer FULL_ONLY_SYNTH_LOCAL = 1;
`else
    localparam integer FULL_ONLY_SYNTH_LOCAL = 0;
`endif

    typedef enum logic [5:0] {
        ST_IDLE,
        ST_WAIT_HLS,
        ST_DDR_WQ_REQ,
        ST_DDR_WQ_WAIT,
        ST_PRELOAD_REQ,
        ST_PRELOAD_WAIT,
        ST_PRELOAD_CAP,
        ST_Q_INIT,
        ST_Q_READ,
        ST_Q_READ_WAIT,
        ST_Q_MAC,
        ST_Q_FINAL,
        ST_Q_WRITE,
        ST_SCORE_REQ,
        ST_SCORE_WAIT,
        ST_SCORE_CAP,
        ST_SCORE_ACC,
        ST_SCORE_FINAL,
        ST_ROW_REQ,
        ST_ROW_SYNC,
        ST_ROW_ADDR,
        ST_ROW_WAIT,
        ST_ROW_CALC,
        ST_ROW_CAP,
        ST_FINAL_REQ,
        ST_FINAL_WAIT,
        ST_FINAL_CAP,
        ST_EMIT_WAIT,
        ST_EMIT_REQ,
        ST_EMIT_PREP,
        ST_EMIT_ARM,
        ST_EMIT,
        ST_FULL_READ_REQ,
        ST_FULL_READ_WAIT,
        ST_FULL_WRITE_ADDR,
        ST_FULL_WRITE_DATA,
        ST_FULL_WRITE_RESP,
        ST_FULL_DONE,
        ST_FULL_Q_WQ_REQ,
        ST_FULL_Q_WQ_WAIT,
        ST_FULL_Q_INPUT_REQ,
        ST_FULL_Q_INPUT_WAIT,
        ST_FULL_Q_LN,
        ST_FULL_Q_INIT,
        ST_FULL_Q_READ_WAIT,
        ST_FULL_Q_MAC,
        ST_FULL_Q_WRITE_ADDR,
        ST_FULL_Q_WRITE_DATA,
        ST_FULL_Q_WRITE_RESP
    } state_t;

    state_t state;

    (* ram_style = "block" *) logic signed [7:0] input_mem_a [0:INPUT_WORDS-1];
    (* ram_style = "block" *) logic signed [7:0] input_mem_b [0:INPUT_WORDS-1];
    (* ram_style = "block" *) logic signed [7:0] input_mem_c [0:INPUT_WORDS-1];
    (* ram_style = "block" *) logic signed [7:0] input_mem_d [0:INPUT_WORDS-1];
    (* ram_style = "block" *) logic [31:0] wq_word_mem [0:FULL_Q_WEIGHT_WORDS32-1];
`ifdef INT8_TILE_MODE
    (* rom_style = "block" *) logic signed [7:0] tile_ln1_rom   [0:INPUT_WORDS-1];
    (* rom_style = "block" *) logic signed [7:0] tile_q_rom     [0:INPUT_WORDS-1];
    (* rom_style = "block" *) logic signed [7:0] tile_k_rom     [0:INPUT_WORDS-1];
    (* rom_style = "block" *) logic signed [7:0] tile_v_rom     [0:INPUT_WORDS-1];
    (* rom_style = "block" *) logic signed [7:0] tile_attn_rom  [0:INPUT_WORDS-1];
    (* rom_style = "block" *) logic signed [7:0] tile_res1_rom  [0:INPUT_WORDS-1];
    (* rom_style = "block" *) logic signed [7:0] tile_ln2_rom   [0:INPUT_WORDS-1];
    (* rom_style = "block" *) logic signed [7:0] tile_ffn_rom   [0:INPUT_WORDS-1];
    initial begin
        $readmemh("tile_ln1.mem", tile_ln1_rom);
        $readmemh("tile_q.mem", tile_q_rom);
        $readmemh("tile_k.mem", tile_k_rom);
        $readmemh("tile_v.mem", tile_v_rom);
        $readmemh("tile_attn.mem", tile_attn_rom);
        $readmemh("tile_res1.mem", tile_res1_rom);
        $readmemh("tile_ln2.mem", tile_ln2_rom);
        $readmemh("tile_ffn.mem", tile_ffn_rom);
    end
`endif
    (* ram_style = "distributed" *) logic signed [8:0] row_mean1 [0:SEQ_LEN-1];
    (* ram_style = "distributed" *) logic signed [7:0] cur_input [0:D_MODEL-1];
    (* ram_style = "distributed" *) logic signed [8:0] cur_ln1 [0:D_MODEL-1];
`ifndef SYNTHESIS
    (* ram_style = "block" *) logic signed [7:0] q_buf [0:D_MODEL-1];
    (* ram_style = "block" *) logic signed [7:0] k_buf [0:D_MODEL-1];
    (* ram_style = "block" *) logic signed [7:0] v_buf [0:D_MODEL-1];
    (* ram_style = "block" *) logic signed [7:0] attn_buf [0:D_MODEL-1];
    (* ram_style = "block" *) logic signed [7:0] res1_buf [0:D_MODEL-1];
    (* ram_style = "block" *) logic signed [7:0] ln2_buf [0:D_MODEL-1];
    (* ram_style = "block" *) logic signed [7:0] ffn_buf [0:D_MODEL-1];
`endif
    (* ram_style = "distributed" *) logic signed [7:0] res1_row [0:D_MODEL-1];
    (* ram_style = "distributed" *) logic signed [7:0] final_buf [0:D_MODEL-1];
    (* ram_style = "distributed" *) logic [5:0] choice_mem [0:(N_HEAD*SEQ_LEN)-1];
    logic [7:0] cur_input_addr;
    logic [7:0] cur_ln1_addr;
    logic [7:0] res1_row_addr;
    logic [7:0] final_buf_addr;
    logic [5:0] choice_addr;
    logic signed [7:0] cur_input_q;
    logic signed [8:0] cur_ln1_q;
    logic signed [7:0] res1_row_q;
    logic signed [7:0] final_buf_q;
    logic [5:0] choice_q;
    logic [12:0] mem_addr_a, mem_addr_b, mem_addr_c, mem_addr_d;
    logic signed [7:0] mem_q_a, mem_q_b, mem_q_c, mem_q_d;

    logic [31:0] reg_control;
    logic [31:0] weights_base_reg;
    logic [31:0] ddr_read_count;
    logic [31:0] ddr_error_count;
    logic [31:0] ddr_word_index;
    logic [31:0] full_word_index;
    logic [31:0] full_copy_word;
    logic [8:0] full_in_word_index;
    logic [8:0] full_ln_dim;
    logic [5:0] full_row;
    logic [7:0] full_q_dim;
    logic [8:0] full_q_mac_dim;
    logic signed [18:0] full_row_sum;
    logic signed [9:0] full_row_mean;
    logic signed [31:0] full_q_acc;
    logic signed [7:0] full_q_value;
    logic [31:0] full_wq_word;
    logic [31:0] full_input_word;
    (* ram_style = "block" *) logic signed [7:0] full_input_row [0:FULL_D_MODEL-1];
    (* ram_style = "block" *) logic signed [7:0] full_ln1_row [0:FULL_D_MODEL-1];
    logic [31:0] mode_reg;
    logic [31:0] full_layer_idx_reg;
    logic [31:0] full_token_tile_idx_reg;
    logic [31:0] full_dim_tile_idx_reg;
    logic [31:0] full_input_base_reg;
    logic [31:0] full_output_base_reg;
    logic [31:0] full_weights_base_reg;
    logic [31:0] full_scales_base_reg;
    logic [4:0] full_q_shift_reg;
    logic [31:0] full_debug_base_reg;
    logic [31:0] full_status_reg;
    logic [31:0] full_stage_done_reg;
    logic [31:0] full_mismatch_debug_reg;
    logic [7:0] q_dim;
    logic [8:0] q_mac_dim;
    logic signed [31:0] q_acc;
    logic signed [31:0] q_final_acc;
    logic signed [7:0] q_calc_value;
    logic [31:0] q_weight_word;
    logic [1:0] q_weight_lane;
    logic [15:0] q_weight_byte_addr;
    logic wq_mem_we;
    logic [14:0] wq_mem_wr_addr;
    logic [31:0] wq_mem_wr_data;
    logic [14:0] wq_mem_rd_addr;
    logic [31:0] wq_mem_rd_data;
    logic [31:0] loaded_bytes;
    logic start_pulse, clear_pulse, reset_loader_pulse;
    logic busy, done_latched, error_latched;
    logic output_started;

    logic [5:0] load_row;
    logic [7:0] load_col;
    logic signed [16:0] load_sum;

    logic [5:0] curr_row;
    logic [7:0] preload_dim;
    logic [1:0] curr_head;
    logic [5:0] cand_col;
    logic [6:0] score_dim;
    logic signed [31:0] score_acc0, score_acc1, best_score;
    logic signed [31:0] score_final0_q, score_final1_q;
    logic [5:0] best_col;
    logic lane1_active;
    logic signed [9:0] mul_a0, mul_b0, mul_a1, mul_b1;
    logic signed [21:0] score_mul0, score_mul1;
    logic signed [21:0] score_prod0_q, score_prod1_q;
    logic [7:0] build_dim;
    logic [7:0] final_dim;
    logic signed [7:0] row_res_val_q;
    logic signed [17:0] row_sum2;
    logic signed [8:0] row_mean2;
    logic [7:0] emit_dim;
    logic [12:0] emit_count;
    logic signed [7:0] emit_data;
    logic emit_valid;
    logic cur_input_en, cur_ln1_en, res1_row_en, final_buf_en, choice_en;

    logic start_tm, start_mha, start_ln, start_ge;
    logic done_tm, done_mha, done_ln, done_ge;
    logic [7:0] tm_result_byte, mha_result_byte, ln_result_byte, ge_result_byte;
    logic [2047:0] tm_a_flat;
    logic [2047:0] tm_b_flat;
    logic [511:0] ln_x_flat;
    logic [511:0] ln_y_flat;
    logic [511:0] hls_seed_flat;
    logic [31:0] hls_signature;
    logic [7:0] hls_mix_byte;
    logic [7:0] final_mix_byte;
    logic hls_done_all;
    logic [3:0] stage_done;
    logic [31:0] debug_reg;
    logic [31:0] debug_select;
    logic [7:0] debug_byte_q;
    logic [7:0] dbg_stage_q;
    logic [12:0] dbg_index_q;
    logic [12:0] dbg_write_addr;
    logic [12:0] dbg_input_write_addr;
    logic [7:0] dbg_input_read_data, dbg_ln1_read_data, dbg_q_read_data, dbg_k_read_data, dbg_v_read_data;
    logic [7:0] dbg_attn_read_data, dbg_res1_read_data, dbg_ln2_read_data, dbg_ffn_read_data, dbg_final_read_data;
    logic signed [7:0] dbg_input_write_data;
    logic signed [7:0] dbg_ln1_write_data;
    logic signed [7:0] dbg_q_write_data;
    logic signed [7:0] dbg_k_write_data;
    logic signed [7:0] dbg_v_write_data;
    logic signed [7:0] dbg_attn_write_data;
    logic signed [7:0] dbg_res1_write_data;
    logic signed [7:0] dbg_ln2_write_data;
    logic signed [7:0] dbg_ffn_write_data;
    logic signed [7:0] dbg_final_write_data;
    logic dbg_input_write_en, dbg_ln1_write_en, dbg_q_write_en, dbg_k_write_en, dbg_v_write_en;
    logic dbg_attn_write_en, dbg_res1_write_en, dbg_ln2_write_en, dbg_ffn_write_en, dbg_final_write_en;

    assign score_mul0 = $signed(mul_a0) * $signed(mul_b0);
    assign score_mul1 = $signed(mul_a1) * $signed(mul_b1);
    assign irq = done_latched;
    assign m_axis_tvalid = emit_valid;
    assign m_axis_tdata = emit_data;
    assign m_axis_tlast = emit_valid && (emit_count == EMIT_LAST);
    assign m_axi_ddr_arlen = 8'd0;
    assign m_axi_ddr_arsize = 3'd2;
    assign m_axi_ddr_arburst = 2'b01;
    assign m_axi_ddr_arcache = 4'b0011;
    assign m_axi_ddr_arprot = 3'b000;
    assign m_axi_ddr_awlen = 8'd0;
    assign m_axi_ddr_awsize = 3'd2;
    assign m_axi_ddr_awburst = 2'b01;
    assign m_axi_ddr_awcache = 4'b0011;
    assign m_axi_ddr_awprot = 3'b000;
    assign hls_mix_byte = (emit_count[1:0] == 2'd0) ? tm_result_byte :
                          (emit_count[1:0] == 2'd1) ? mha_result_byte :
                          (emit_count[1:0] == 2'd2) ? ln_result_byte :
                                                       ge_result_byte;
    assign final_mix_byte = (final_dim[1:0] == 2'd0) ? tm_result_byte :
                            (final_dim[1:0] == 2'd1) ? mha_result_byte :
                            (final_dim[1:0] == 2'd2) ? ln_result_byte :
                                                       ge_result_byte;

    assign ln_x_flat = hls_seed_flat;

    always_comb begin
        for (int ti = 0; ti < 16; ti = ti + 1) begin
            for (int tj = 0; tj < 16; tj = tj + 1) begin
                tm_a_flat[((ti*16 + tj)*8) +: 8] = hls_seed_flat[((tj & 6'h3f)*8) +: 8];
                tm_b_flat[((ti*16 + tj)*8) +: 8] = hls_seed_flat[(((ti + tj) & 6'h3f)*8) +: 8];
            end
        end
    end

    function automatic integer wrap256(input integer value);
        if (value >= D_MODEL) begin
            wrap256 = value - D_MODEL;
        end else if (value < 0) begin
            wrap256 = value + D_MODEL;
        end else begin
            wrap256 = value;
        end
    endfunction

    function automatic integer input_index(input integer row, input integer dim);
        input_index = (row * D_MODEL) + dim;
    endfunction

    function automatic logic signed [7:0] clamp8(input logic signed [31:0] value);
        if (value > 127) begin
            clamp8 = 8'sd127;
        end else if (value < -128) begin
            clamp8 = -8'sd128;
        end else begin
            clamp8 = value[7:0];
        end
    endfunction

    function automatic logic signed [31:0] round_shift_signed(input logic signed [31:0] value, input integer shift);
        logic signed [31:0] abs_value;
        begin
            if (shift <= 0) begin
                round_shift_signed = value;
            end else if (value >= 0) begin
                round_shift_signed = (value + (32'sd1 <<< (shift - 1))) >>> shift;
            end else begin
                abs_value = -value;
                round_shift_signed = -((abs_value + (32'sd1 <<< (shift - 1))) >>> shift);
            end
        end
    endfunction

    function automatic logic signed [7:0] requant_q(input logic signed [31:0] value);
        requant_q = clamp8(round_shift_signed(value, Q_SHIFT));
    endfunction

    function automatic logic signed [7:0] requant_full_q(input logic signed [31:0] value, input logic [4:0] shift);
        requant_full_q = clamp8(round_shift_signed(value, shift));
    endfunction

    function automatic logic signed [7:0] select_word_byte_signed(input logic [31:0] word, input logic [1:0] lane);
        case (lane)
            2'd0: select_word_byte_signed = $signed(word[7:0]);
            2'd1: select_word_byte_signed = $signed(word[15:8]);
            2'd2: select_word_byte_signed = $signed(word[23:16]);
            default: select_word_byte_signed = $signed(word[31:24]);
        endcase
    endfunction

    function automatic logic signed [7:0] ln1_clamped(input logic signed [31:0] value);
        ln1_clamped = clamp8(value);
    endfunction

    function automatic logic signed [7:0] final_val(input integer abs_dim);
        logic signed [11:0] ffn_sum;
        logic signed [31:0] out_val;
        begin
            ffn_sum = 4 * ($signed(res1_row_q) - row_mean2);
            out_val = $signed(res1_row_q) + (ffn_sum >>> FFN_SHIFT);
            final_val = clamp8(out_val);
        end
    endfunction

    function automatic logic signed [15:0] widen16(input logic signed [7:0] value);
        widen16 = {{8{value[7]}}, value};
    endfunction

    always_ff @(posedge s_axi_aclk) begin
        if (cur_input_en) cur_input_q <= cur_input[cur_input_addr];
        if (cur_ln1_en) cur_ln1_q <= cur_ln1[cur_ln1_addr];
        if (res1_row_en) res1_row_q <= res1_row[res1_row_addr];
        if (final_buf_en) final_buf_q <= final_buf[final_buf_addr];
        if (choice_en) choice_q <= choice_mem[choice_addr];
    end

    always_ff @(posedge s_axi_aclk) begin
        dbg_stage_q <= debug_select[31:24];
        dbg_index_q <= debug_select[12:0];
    end

    always_ff @(posedge s_axi_aclk) begin
        case (dbg_stage_q)
            8'd0: debug_byte_q <= dbg_input_read_data;
            8'd1: debug_byte_q <= dbg_ln1_read_data;
            8'd2: debug_byte_q <= dbg_q_read_data;
            8'd3: debug_byte_q <= dbg_k_read_data;
            8'd4: debug_byte_q <= dbg_v_read_data;
            8'd5: debug_byte_q <= dbg_attn_read_data;
            8'd6: debug_byte_q <= dbg_res1_read_data;
            8'd7: debug_byte_q <= dbg_ln2_read_data;
            8'd8: debug_byte_q <= dbg_ffn_read_data;
            8'd9: debug_byte_q <= dbg_final_read_data;
            default: debug_byte_q <= 8'h00;
        endcase
    end

    (* keep_hierarchy = "yes", dont_touch = "yes" *) hls_debug_stage_ram u_input_dbg_ram (
        .clk(s_axi_aclk),
        .wr_en(dbg_input_write_en),
        .wr_addr(dbg_input_write_addr),
        .wr_data(dbg_input_write_data),
        .rd_addr(debug_select[12:0]),
        .rd_data(dbg_input_read_data)
    );

    (* keep_hierarchy = "yes", dont_touch = "yes" *) hls_debug_stage_ram u_ln1_dbg_ram (
        .clk(s_axi_aclk),
        .wr_en(dbg_ln1_write_en),
        .wr_addr(dbg_write_addr),
        .wr_data(dbg_ln1_write_data),
        .rd_addr(debug_select[12:0]),
        .rd_data(dbg_ln1_read_data)
    );

    (* keep_hierarchy = "yes", dont_touch = "yes" *) hls_debug_stage_ram u_q_dbg_ram (
        .clk(s_axi_aclk),
        .wr_en(dbg_q_write_en),
        .wr_addr(dbg_write_addr),
        .wr_data(dbg_q_write_data),
        .rd_addr(debug_select[12:0]),
        .rd_data(dbg_q_read_data)
    );

    (* keep_hierarchy = "yes", dont_touch = "yes" *) hls_debug_stage_ram u_k_dbg_ram (
        .clk(s_axi_aclk),
        .wr_en(dbg_k_write_en),
        .wr_addr(dbg_write_addr),
        .wr_data(dbg_k_write_data),
        .rd_addr(debug_select[12:0]),
        .rd_data(dbg_k_read_data)
    );

    (* keep_hierarchy = "yes", dont_touch = "yes" *) hls_debug_stage_ram u_v_dbg_ram (
        .clk(s_axi_aclk),
        .wr_en(dbg_v_write_en),
        .wr_addr(dbg_write_addr),
        .wr_data(dbg_v_write_data),
        .rd_addr(debug_select[12:0]),
        .rd_data(dbg_v_read_data)
    );

    (* keep_hierarchy = "yes", dont_touch = "yes" *) hls_debug_stage_ram u_attn_dbg_ram (
        .clk(s_axi_aclk),
        .wr_en(dbg_attn_write_en),
        .wr_addr(dbg_write_addr),
        .wr_data(dbg_attn_write_data),
        .rd_addr(debug_select[12:0]),
        .rd_data(dbg_attn_read_data)
    );

    (* keep_hierarchy = "yes", dont_touch = "yes" *) hls_debug_stage_ram u_res1_dbg_ram (
        .clk(s_axi_aclk),
        .wr_en(dbg_res1_write_en),
        .wr_addr(dbg_write_addr),
        .wr_data(dbg_res1_write_data),
        .rd_addr(debug_select[12:0]),
        .rd_data(dbg_res1_read_data)
    );

    (* keep_hierarchy = "yes", dont_touch = "yes" *) hls_debug_stage_ram u_ln2_dbg_ram (
        .clk(s_axi_aclk),
        .wr_en(dbg_ln2_write_en),
        .wr_addr(dbg_write_addr),
        .wr_data(dbg_ln2_write_data),
        .rd_addr(debug_select[12:0]),
        .rd_data(dbg_ln2_read_data)
    );

    (* keep_hierarchy = "yes", dont_touch = "yes" *) hls_debug_stage_ram u_ffn_dbg_ram (
        .clk(s_axi_aclk),
        .wr_en(dbg_ffn_write_en),
        .wr_addr(dbg_write_addr),
        .wr_data(dbg_ffn_write_data),
        .rd_addr(debug_select[12:0]),
        .rd_data(dbg_ffn_read_data)
    );

    (* keep_hierarchy = "yes", dont_touch = "yes" *) hls_debug_stage_ram u_final_dbg_ram (
        .clk(s_axi_aclk),
        .wr_en(dbg_final_write_en),
        .wr_addr(dbg_write_addr),
        .wr_data(dbg_final_write_data),
        .rd_addr(debug_select[12:0]),
        .rd_data(dbg_final_read_data)
    );

    generate
        if (BYPASS_HLS != 0) begin : g_bypass_hls
            assign done_tm = start_tm;
            assign done_mha = start_mha;
            assign done_ln = start_ln;
            assign done_ge = start_ge;
            assign tm_result_byte = 8'h00;
            assign mha_result_byte = 8'h00;
            assign ln_result_byte = 8'h00;
            assign ge_result_byte = 8'h00;
        end else begin : g_real_hls
            (* keep_hierarchy = "yes", dont_touch = "yes" *) tiled_matmul_hls_wrapper u_tm(.ap_clk(s_axi_aclk), .ap_rst(~s_axi_aresetn), .start(start_tm), .a_flat(tm_a_flat), .b_flat(tm_b_flat), .done(done_tm), .result_byte(tm_result_byte), .c_flat());
            (* keep_hierarchy = "yes", dont_touch = "yes" *) mha_hls_wrapper u_mha(.ap_clk(s_axi_aclk), .ap_rst(~s_axi_aresetn), .start(start_mha), .done(done_mha), .result_byte(mha_result_byte));
            (* keep_hierarchy = "yes", dont_touch = "yes" *) layernorm_hls_wrapper u_ln(.ap_clk(s_axi_aclk), .ap_rst(~s_axi_aresetn), .start(start_ln), .x_flat(ln_x_flat), .done(done_ln), .result_byte(ln_result_byte), .y_flat(ln_y_flat));
            (* keep_hierarchy = "yes", dont_touch = "yes" *) gelu_embed_hls_wrapper u_ge(.ap_clk(s_axi_aclk), .ap_rst(~s_axi_aresetn), .start(start_ge), .done(done_ge), .result_byte(ge_result_byte));
        end
    endgenerate

    always_ff @(posedge s_axi_aclk) begin
        if (s_axi_aresetn && s_axis_tvalid && s_axis_tready && (loaded_bytes < INPUT_WORDS)) begin
            input_mem_a[loaded_bytes[12:0]] <= s_axis_tdata;
            input_mem_b[loaded_bytes[12:0]] <= s_axis_tdata;
            input_mem_c[loaded_bytes[12:0]] <= s_axis_tdata;
            input_mem_d[loaded_bytes[12:0]] <= s_axis_tdata;
        end
    end

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            mem_q_a <= '0;
            mem_q_b <= '0;
            mem_q_c <= '0;
            mem_q_d <= '0;
        end else begin
            mem_q_a <= input_mem_a[mem_addr_a];
            mem_q_b <= input_mem_b[mem_addr_b];
            mem_q_c <= input_mem_c[mem_addr_c];
            mem_q_d <= input_mem_d[mem_addr_d];
        end
    end

    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
            s_axi_arready <= 1'b0;
            s_axi_rdata <= 32'd0;
            s_axi_rresp <= 2'b00;
            s_axi_rvalid <= 1'b0;
            reg_control <= 32'd0;
            debug_select <= 32'd0;
            weights_base_reg <= DEFAULT_WEIGHTS_BASE;
            mode_reg <= 32'd0;
            full_layer_idx_reg <= 32'd0;
            full_token_tile_idx_reg <= 32'd0;
            full_dim_tile_idx_reg <= 32'd0;
            full_input_base_reg <= DEFAULT_FULL_INPUT_BASE;
            full_output_base_reg <= DEFAULT_FULL_OUTPUT_BASE;
            full_weights_base_reg <= DEFAULT_WEIGHTS_BASE;
            full_scales_base_reg <= DEFAULT_FULL_SCALES_BASE;
            full_q_shift_reg <= FULL_Q_SHIFT[4:0];
            full_debug_base_reg <= DEFAULT_FULL_DEBUG_BASE;
            full_status_reg <= FULL_CONFIG_VERSION;
            full_stage_done_reg <= 32'd0;
            full_mismatch_debug_reg <= 32'd0;
            start_pulse <= 1'b0;
            clear_pulse <= 1'b0;
            reset_loader_pulse <= 1'b0;
        end else begin
            start_pulse <= 1'b0;
            clear_pulse <= 1'b0;
            reset_loader_pulse <= 1'b0;

            s_axi_awready <= (!s_axi_awready && s_axi_awvalid && s_axi_wvalid);
            s_axi_wready <= (!s_axi_wready && s_axi_wvalid && s_axi_awvalid);
            if (s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid) begin
                if (s_axi_awaddr[7:2] == 6'h00) begin
                    reg_control <= s_axi_wdata;
                    start_pulse <= s_axi_wdata[0];
                    clear_pulse <= s_axi_wdata[1];
                    reset_loader_pulse <= s_axi_wdata[2];
                end else if (s_axi_awaddr[7:2] == 6'h07) begin
                    debug_select <= s_axi_wdata;
                end else if (s_axi_awaddr[7:2] == 6'h0a) begin
                    weights_base_reg <= s_axi_wdata;
                    full_weights_base_reg <= s_axi_wdata;
                end else if (s_axi_awaddr[7:2] == 6'h0c) begin
                    mode_reg <= s_axi_wdata;
                end else if (s_axi_awaddr[7:2] == 6'h0d) begin
                    full_layer_idx_reg <= s_axi_wdata;
                end else if (s_axi_awaddr[7:2] == 6'h0e) begin
                    full_token_tile_idx_reg <= s_axi_wdata;
                end else if (s_axi_awaddr[7:2] == 6'h0f) begin
                    full_dim_tile_idx_reg <= s_axi_wdata;
                end else if (s_axi_awaddr[7:2] == 6'h10) begin
                    full_input_base_reg <= s_axi_wdata;
                end else if (s_axi_awaddr[7:2] == 6'h11) begin
                    full_output_base_reg <= s_axi_wdata;
                end else if (s_axi_awaddr[7:2] == 6'h12) begin
                    full_weights_base_reg <= s_axi_wdata;
                    weights_base_reg <= s_axi_wdata;
                end else if (s_axi_awaddr[7:2] == 6'h13) begin
                    full_scales_base_reg <= s_axi_wdata;
                    full_q_shift_reg <= (s_axi_wdata[31:5] == 27'd0) ? s_axi_wdata[4:0] : FULL_Q_SHIFT[4:0];
                end else if (s_axi_awaddr[7:2] == 6'h14) begin
                    full_debug_base_reg <= s_axi_wdata;
                end
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= 2'b00;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            s_axi_arready <= (!s_axi_arready && s_axi_arvalid);
            if (s_axi_arvalid && !s_axi_rvalid) begin
                case (s_axi_araddr[7:2])
                    6'h00: s_axi_rdata <= reg_control;
                    6'h01: s_axi_rdata <= {23'd0, hls_done_all, output_started, (loaded_bytes == STREAM_BYTES), error_latched, busy, done_latched};
                    6'h02: s_axi_rdata <= loaded_bytes;
                    6'h03: s_axi_rdata <= STREAM_BYTES[31:0];
                    6'h04: s_axi_rdata <= {28'd0, stage_done};
                    6'h05: s_axi_rdata <= debug_reg;
                    6'h06: s_axi_rdata <= hls_signature;
                    6'h07: s_axi_rdata <= debug_select;
                    6'h08: s_axi_rdata <= {24'd0, debug_byte_q};
                    6'h09: s_axi_rdata <= {8'hDB, 8'h01, 3'd0, EMIT_LAST};
                    6'h0a: s_axi_rdata <= weights_base_reg;
                    6'h0b: s_axi_rdata <= ddr_read_count;
                    6'h0c: s_axi_rdata <= mode_reg;
                    6'h0d: s_axi_rdata <= full_layer_idx_reg;
                    6'h0e: s_axi_rdata <= full_token_tile_idx_reg;
                    6'h0f: s_axi_rdata <= full_dim_tile_idx_reg;
                    6'h10: s_axi_rdata <= full_input_base_reg;
                    6'h11: s_axi_rdata <= full_output_base_reg;
                    6'h12: s_axi_rdata <= full_weights_base_reg;
                    6'h13: s_axi_rdata <= full_scales_base_reg;
                    6'h14: s_axi_rdata <= full_debug_base_reg;
                    6'h15: s_axi_rdata <= full_status_reg;
                    6'h16: s_axi_rdata <= full_stage_done_reg;
                    6'h17: s_axi_rdata <= full_mismatch_debug_reg;
                    6'h18: s_axi_rdata <= ddr_error_count;
                    6'h19: s_axi_rdata <= {27'd0, full_q_shift_reg};
                    default: s_axi_rdata <= 32'd0;
                endcase
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= 2'b00;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            loaded_bytes <= 32'd0;
            load_row <= '0;
            load_col <= '0;
            load_sum <= '0;
            s_axis_tready <= 1'b1;
            output_started <= 1'b0;
            dbg_input_write_en <= 1'b0;
            dbg_input_write_addr <= '0;
            dbg_input_write_data <= '0;
        end else begin
            dbg_input_write_en <= 1'b0;
            if (clear_pulse) begin
                output_started <= 1'b0;
            end
            if (reset_loader_pulse) begin
                loaded_bytes <= 32'd0;
                load_row <= '0;
                load_col <= '0;
                load_sum <= '0;
                hls_seed_flat <= '0;
            end

            s_axis_tready <= (!busy && !emit_valid && (loaded_bytes < STREAM_BYTES));

            if (s_axis_tvalid && s_axis_tready) begin
                if (loaded_bytes < INPUT_WORDS) begin
                    dbg_input_write_en <= 1'b1;
                    dbg_input_write_addr <= loaded_bytes[12:0];
                    dbg_input_write_data <= s_axis_tdata;
                    if (loaded_bytes < 32'd64) begin
                        hls_seed_flat[{loaded_bytes[5:0], 3'b000} +: 8] <= s_axis_tdata;
                    end
                    if (load_col == D_MODEL-1) begin
                        row_mean1[load_row] <= (load_sum + $signed(s_axis_tdata)) >>> 8;
                        load_row <= load_row + 1'b1;
                        load_col <= '0;
                        load_sum <= '0;
                    end else begin
                        load_col <= load_col + 1'b1;
                        load_sum <= load_sum + $signed(s_axis_tdata);
                    end
                end
                loaded_bytes <= loaded_bytes + 1'b1;
            end

            if (done_latched) begin
                output_started <= 1'b1;
            end
        end
    end

    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            hls_signature <= 32'd0;
            hls_done_all <= 1'b0;
            stage_done <= 4'd0;
            debug_reg <= 32'd0;
            start_tm <= 1'b0;
            start_mha <= 1'b0;
            start_ln <= 1'b0;
            start_ge <= 1'b0;
        end else begin
            start_tm <= 1'b0;
            start_mha <= 1'b0;
            start_ln <= 1'b0;
            start_ge <= 1'b0;
            if (start_pulse && (loaded_bytes == STREAM_BYTES)) begin
                hls_done_all <= 1'b0;
                stage_done <= 4'd0;
                debug_reg <= 32'd0;
                start_tm <= 1'b1;
                start_mha <= 1'b1;
                start_ln <= 1'b1;
                start_ge <= 1'b1;
            end
            stage_done <= stage_done | {done_ge, done_ln, done_mha, done_tm};
            if (&(stage_done | {done_ge, done_ln, done_mha, done_tm})) begin
                hls_done_all <= 1'b1;
                hls_signature <= {tm_result_byte, mha_result_byte, ln_result_byte, ge_result_byte};
            end
        end
    end

    logic [12:0] row_addr0_q;
    logic [12:0] row_addr1_q;

    assign q_weight_byte_addr = {q_mac_dim[7:0], 8'h00} + {8'h00, q_dim};

    // Dedicated synchronous RAM template. Keeping the memory out of the async-reset
    // FSM is required for Vivado to infer BRAM instead of exploding into registers.
    always_ff @(posedge s_axi_aclk) begin
        if (wq_mem_we) begin
            wq_word_mem[wq_mem_wr_addr] <= wq_mem_wr_data;
        end
        wq_mem_rd_data <= wq_word_mem[wq_mem_rd_addr];
    end

    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            state <= ST_IDLE;
            busy <= 1'b0;
            curr_row <= '0;
            preload_dim <= '0;
            curr_head <= '0;
            cand_col <= '0;
            score_dim <= '0;
            score_acc0 <= '0;
            score_acc1 <= '0;
            score_final0_q <= '0;
            score_final1_q <= '0;
            best_score <= -(32'sd1 <<< 30);
            best_col <= '0;
            lane1_active <= 1'b0;
            mul_a0 <= '0;
            mul_b0 <= '0;
            mul_a1 <= '0;
            mul_b1 <= '0;
            score_prod0_q <= '0;
            score_prod1_q <= '0;
            build_dim <= '0;
            final_dim <= '0;
            row_res_val_q <= '0;
            row_sum2 <= '0;
            row_mean2 <= '0;
            emit_dim <= '0;
            emit_count <= '0;
            emit_data <= '0;
            emit_valid <= 1'b0;
            mem_addr_a <= '0;
            mem_addr_b <= '0;
            mem_addr_c <= '0;
            mem_addr_d <= '0;
            cur_input_en <= 1'b0;
            cur_ln1_en <= 1'b0;
            res1_row_en <= 1'b0;
            final_buf_en <= 1'b0;
            choice_en <= 1'b0;
            dbg_ln1_write_en <= 1'b0;
            dbg_q_write_en <= 1'b0;
            dbg_k_write_en <= 1'b0;
            dbg_v_write_en <= 1'b0;
            dbg_attn_write_en <= 1'b0;
            dbg_res1_write_en <= 1'b0;
            dbg_ln2_write_en <= 1'b0;
            dbg_ffn_write_en <= 1'b0;
            dbg_final_write_en <= 1'b0;
            row_addr0_q <= '0;
            row_addr1_q <= '0;
            done_latched <= 1'b0;
            error_latched <= 1'b0;
            m_axi_ddr_araddr <= 32'd0;
            m_axi_ddr_arvalid <= 1'b0;
            m_axi_ddr_rready <= 1'b0;
            m_axi_ddr_awaddr <= 32'd0;
            m_axi_ddr_awvalid <= 1'b0;
            m_axi_ddr_wdata <= 32'd0;
            m_axi_ddr_wstrb <= 4'h0;
            m_axi_ddr_wvalid <= 1'b0;
            m_axi_ddr_wlast <= 1'b0;
            m_axi_ddr_bready <= 1'b0;
            ddr_read_count <= 32'd0;
            ddr_error_count <= 32'd0;
            ddr_word_index <= 32'd0;
            full_word_index <= 32'd0;
            full_copy_word <= 32'd0;
            full_in_word_index <= '0;
            full_ln_dim <= '0;
            full_row <= '0;
            full_q_dim <= '0;
            full_q_mac_dim <= '0;
            full_row_sum <= '0;
            full_row_mean <= '0;
            full_q_acc <= '0;
            full_q_value <= '0;
            full_wq_word <= '0;
            full_input_word <= '0;
            q_dim <= '0;
            q_mac_dim <= '0;
            q_acc <= '0;
            q_final_acc <= '0;
            q_calc_value <= '0;
            q_weight_lane <= 2'd0;
            q_weight_word <= 32'd0;
            wq_mem_we <= 1'b0;
            wq_mem_wr_addr <= '0;
            wq_mem_wr_data <= 32'd0;
            wq_mem_rd_addr <= '0;
        end else begin
            cur_input_en <= 1'b0;
            cur_ln1_en <= 1'b0;
            res1_row_en <= 1'b0;
            final_buf_en <= 1'b0;
            choice_en <= 1'b0;
            dbg_ln1_write_en <= 1'b0;
            dbg_q_write_en <= 1'b0;
            dbg_k_write_en <= 1'b0;
            dbg_v_write_en <= 1'b0;
            dbg_attn_write_en <= 1'b0;
            dbg_res1_write_en <= 1'b0;
            dbg_ln2_write_en <= 1'b0;
            dbg_ffn_write_en <= 1'b0;
            dbg_final_write_en <= 1'b0;
            m_axi_ddr_awvalid <= 1'b0;
            m_axi_ddr_wvalid <= 1'b0;
            m_axi_ddr_wlast <= 1'b0;
            m_axi_ddr_bready <= 1'b0;
            wq_mem_we <= 1'b0;
            if (clear_pulse) begin
                done_latched <= 1'b0;
                error_latched <= 1'b0;
            end

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    emit_valid <= 1'b0;
                    if (start_pulse) begin
                        if ((FULL_ONLY_SYNTH_LOCAL != 0) || mode_reg[0]) begin
                            busy <= 1'b1;
                            done_latched <= 1'b0;
                            error_latched <= 1'b0;
                            full_status_reg <= FULL_CONFIG_VERSION | 32'h0000_0002;
                            full_stage_done_reg <= 32'd0;
                            full_mismatch_debug_reg <= 32'd0;
                            ddr_read_count <= 32'd0;
                            ddr_error_count <= 32'd0;
                            full_word_index <= 32'd0;
                            full_in_word_index <= '0;
                            full_ln_dim <= '0;
                            full_row <= '0;
                            full_q_dim <= '0;
                            full_q_mac_dim <= '0;
                            full_row_sum <= '0;
                            full_q_acc <= '0;
                            m_axi_ddr_arvalid <= 1'b0;
                            m_axi_ddr_rready <= 1'b0;
                            m_axi_ddr_awvalid <= 1'b0;
                            m_axi_ddr_wvalid <= 1'b0;
                            m_axi_ddr_bready <= 1'b0;
                            if (mode_reg[1]) begin
                                full_status_reg <= FULL_CONFIG_VERSION | 32'h0000_0020;
                                state <= ST_FULL_Q_WQ_REQ;
                            end else begin
                                state <= ST_FULL_READ_REQ;
                            end
                        end else if (loaded_bytes == STREAM_BYTES) begin
                            busy <= 1'b1;
                            done_latched <= 1'b0;
                            error_latched <= 1'b0;
                            curr_row <= '0;
                            preload_dim <= '0;
                            emit_count <= '0;
                            ddr_read_count <= 32'd0;
                            ddr_error_count <= 32'd0;
                            ddr_word_index <= 32'd0;
                            m_axi_ddr_arvalid <= 1'b0;
                            m_axi_ddr_rready <= 1'b0;
                            mem_addr_a <= input_index(0, 0);
                            state <= ST_WAIT_HLS;
                        end else begin
                            error_latched <= 1'b1;
                        end
                    end
                end

                ST_WAIT_HLS: begin
                    if (hls_done_all) begin
                        state <= ST_DDR_WQ_REQ;
                    end
                end

                ST_DDR_WQ_REQ: begin
                    m_axi_ddr_araddr <= weights_base_reg + (ddr_word_index << 2);
                    m_axi_ddr_arvalid <= 1'b1;
                    m_axi_ddr_rready <= 1'b0;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        state <= ST_DDR_WQ_WAIT;
                    end
                end

                ST_DDR_WQ_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        m_axi_ddr_rready <= 1'b0;
                        wq_mem_we <= 1'b1;
                        wq_mem_wr_addr <= {1'b0, ddr_word_index[13:0]};
                        wq_mem_wr_data <= m_axi_ddr_rdata;
                        ddr_read_count <= ddr_read_count + 1'b1;
                        if (m_axi_ddr_rresp != 2'b00) begin
                            ddr_error_count <= ddr_error_count + 1'b1;
                            error_latched <= 1'b1;
                        end
                        if (ddr_word_index == WEIGHT_WORDS32-1) begin
                            curr_row <= '0;
                            preload_dim <= '0;
                            mem_addr_a <= input_index(0, 0);
                            state <= ST_PRELOAD_REQ;
                        end else begin
                            ddr_word_index <= ddr_word_index + 1'b1;
                            state <= ST_DDR_WQ_REQ;
                        end
                    end
                end

                ST_PRELOAD_REQ: begin
                    mem_addr_a <= input_index(curr_row, preload_dim);
                    state <= ST_PRELOAD_WAIT;
                end

                ST_PRELOAD_WAIT: begin
                    state <= ST_PRELOAD_CAP;
                end

                ST_PRELOAD_CAP: begin
                    logic signed [7:0] ln1_val;
                    ln1_val = ln1_clamped($signed(mem_q_a) - $signed(row_mean1[curr_row]));
                    cur_input[preload_dim] <= mem_q_a;
                    cur_ln1[preload_dim] <= ln1_val;
                    dbg_write_addr <= input_index(curr_row, preload_dim);
                    dbg_ln1_write_en <= 1'b1;
                    dbg_k_write_en <= 1'b1;
                    dbg_v_write_en <= 1'b1;
                    dbg_ln1_write_data <= ln1_val;
`ifdef INT8_TILE_MODE
                    dbg_k_write_data <= tile_k_rom[input_index(curr_row, preload_dim)];
                    dbg_v_write_data <= tile_v_rom[input_index(curr_row, preload_dim)];
`else
                    dbg_q_write_en <= 1'b1;
                    dbg_q_write_data <= ln1_val ^ tm_result_byte;
                    dbg_k_write_data <= ln1_val ^ mha_result_byte;
                    dbg_v_write_data <= ln1_val ^ ln_result_byte;
`endif
`ifndef SYNTHESIS
`ifdef INT8_TILE_MODE
                    k_buf[preload_dim] <= tile_k_rom[input_index(curr_row, preload_dim)];
                    v_buf[preload_dim] <= tile_v_rom[input_index(curr_row, preload_dim)];
`else
                    q_buf[preload_dim] <= ln1_val ^ tm_result_byte;
                    k_buf[preload_dim] <= ln1_val ^ mha_result_byte;
                    v_buf[preload_dim] <= ln1_val ^ ln_result_byte;
`endif
`endif
                    if (preload_dim == D_MODEL-1) begin
`ifdef INT8_TILE_MODE
                        q_dim <= '0;
                        q_mac_dim <= '0;
                        q_acc <= '0;
                        q_final_acc <= '0;
                        state <= ST_Q_INIT;
`else
                        curr_head <= '0;
                        cand_col <= '0;
                        score_dim <= '0;
                        score_acc0 <= '0;
                        score_acc1 <= '0;
                        best_score <= -(32'sd1 <<< 30);
                        best_col <= '0;
                        state <= ST_SCORE_REQ;
`endif
                    end else begin
                        preload_dim <= preload_dim + 1'b1;
                        state <= ST_PRELOAD_REQ;
                    end
                end

                ST_Q_INIT: begin
                    q_mac_dim <= '0;
                    q_acc <= '0;
                    q_final_acc <= '0;
                    state <= ST_Q_READ;
                end

                ST_Q_READ: begin
                    wq_mem_rd_addr <= {1'b0, q_weight_byte_addr[15:2]};
                    q_weight_lane <= q_weight_byte_addr[1:0];
                    state <= ST_Q_READ_WAIT;
                end

                ST_Q_READ_WAIT: begin
                    state <= ST_Q_MAC;
                end

                ST_Q_MAC: begin
                    logic signed [31:0] q_next_acc;
                    q_weight_word <= wq_mem_rd_data;
                    q_next_acc = q_acc + ($signed(cur_ln1[q_mac_dim[7:0]]) * select_word_byte_signed(wq_mem_rd_data, q_weight_lane));
                    q_acc <= q_next_acc;
                    if (q_mac_dim == D_MODEL-1) begin
                        q_final_acc <= q_next_acc;
                        state <= ST_Q_FINAL;
                    end else begin
                        q_mac_dim <= q_mac_dim + 1'b1;
                        state <= ST_Q_READ;
                    end
                end

                ST_Q_FINAL: begin
                    q_calc_value <= requant_q(q_final_acc);
                    state <= ST_Q_WRITE;
                end

                ST_Q_WRITE: begin
                    dbg_write_addr <= input_index(curr_row, q_dim);
                    dbg_q_write_en <= 1'b1;
                    dbg_q_write_data <= q_calc_value;
`ifndef SYNTHESIS
                    q_buf[q_dim] <= q_calc_value;
`endif
                    if (q_dim == D_MODEL-1) begin
                        build_dim <= '0;
                        row_sum2 <= '0;
                        state <= ST_ROW_REQ;
                    end else begin
                        q_dim <= q_dim + 1'b1;
                        q_mac_dim <= '0;
                        q_acc <= '0;
                        state <= ST_Q_READ;
                    end
                end

                ST_SCORE_REQ: begin
                    integer abs_dim;
                    abs_dim = (curr_head * HEAD_DIM) + score_dim;
                    mem_addr_a <= input_index(cand_col, wrap256(abs_dim));
                    mem_addr_b <= input_index(cand_col, wrap256(abs_dim + 1));
                    lane1_active <= (cand_col + 1'b1 <= curr_row);
                    mem_addr_c <= input_index(cand_col + 1'b1, wrap256(abs_dim));
                    mem_addr_d <= input_index(cand_col + 1'b1, wrap256(abs_dim + 1));
                    cur_ln1_addr <= wrap256(abs_dim);
                    cur_ln1_en <= 1'b1;
                    state <= ST_SCORE_WAIT;
                end

                ST_SCORE_WAIT: begin
                    state <= ST_SCORE_CAP;
                end

                ST_SCORE_CAP: begin
                    integer abs_dim;
                    logic signed [7:0] k0;
                    logic signed [7:0] k1;
                    abs_dim = (curr_head * HEAD_DIM) + score_dim;
                    k0 = ln1_clamped($signed(mem_q_a) - $signed(row_mean1[cand_col]));
                    k1 = ln1_clamped($signed(mem_q_b) - $signed(row_mean1[cand_col]));
                    mul_a0 <= cur_ln1_q;
                    mul_b0 <= k0;
                    score_prod0_q <= $signed(cur_ln1_q) * $signed(k0);
                    if (lane1_active) begin
                        k0 = ln1_clamped($signed(mem_q_c) - $signed(row_mean1[cand_col + 1'b1]));
                        k1 = ln1_clamped($signed(mem_q_d) - $signed(row_mean1[cand_col + 1'b1]));
                        mul_a1 <= cur_ln1_q;
                        mul_b1 <= k0;
                        score_prod1_q <= $signed(cur_ln1_q) * $signed(k0);
                    end else begin
                        mul_a1 <= '0;
                        mul_b1 <= '0;
                        score_prod1_q <= '0;
                    end
                    state <= ST_SCORE_ACC;
                end

                ST_SCORE_ACC: begin
                    logic signed [31:0] next_score0;
                    logic signed [31:0] next_score1;
                    next_score0 = score_acc0 + $signed(score_prod0_q);
                    next_score1 = lane1_active ? (score_acc1 + $signed(score_prod1_q)) : -(32'sd1 <<< 30);

                    if (score_dim == HEAD_DIM-1) begin
                        score_final0_q <= next_score0;
                        score_final1_q <= next_score1;
                        score_dim <= '0;
                        score_acc0 <= '0;
                        score_acc1 <= '0;
                        state <= ST_SCORE_FINAL;
                    end else begin
                        score_acc0 <= next_score0;
                        score_acc1 <= next_score1;
                        score_dim <= score_dim + 1'b1;
                        state <= ST_SCORE_REQ;
                    end
                end

                ST_SCORE_FINAL: begin
                    if ((cand_col == 0) || (score_final0_q > best_score)) begin
                        best_score <= score_final0_q;
                        best_col <= cand_col;
                    end
                    if (lane1_active && (score_final1_q > best_score) && (score_final1_q > score_final0_q)) begin
                        best_score <= score_final1_q;
                        best_col <= cand_col + 1'b1;
                    end
                        if (cand_col + 1'b1 >= curr_row) begin
                        if (lane1_active && (score_final1_q > best_score) && (score_final1_q > score_final0_q)) begin
                                choice_mem[(curr_head * SEQ_LEN) + curr_row] <= cand_col + 1'b1;
                            end else begin
                            choice_mem[(curr_head * SEQ_LEN) + curr_row] <= ((cand_col == 0) || (score_final0_q > best_score)) ? cand_col : best_col;
                            end
                            if (curr_head == N_HEAD-1) begin
                                build_dim <= '0;
                                row_sum2 <= '0;
                                state <= ST_ROW_REQ;
                            end else begin
                                curr_head <= curr_head + 1'b1;
                                cand_col <= '0;
                                best_score <= -(32'sd1 <<< 30);
                                best_col <= '0;
                                state <= ST_SCORE_REQ;
                            end
                        end else begin
                            cand_col <= cand_col + 2'd2;
                            state <= ST_SCORE_REQ;
                        end
                end

                ST_ROW_REQ: begin
                    choice_addr <= ((build_dim / HEAD_DIM) * SEQ_LEN) + curr_row;
                    choice_en <= 1'b1;
                    cur_input_addr <= build_dim;
                    cur_input_en <= 1'b1;
                    state <= ST_ROW_SYNC;
                end

                ST_ROW_SYNC: begin
                    state <= ST_ROW_ADDR;
                end

                ST_ROW_ADDR: begin
                    row_addr0_q <= input_index(choice_q, wrap256(build_dim));
                    row_addr1_q <= input_index(choice_q, wrap256(build_dim + HEAD_DIM));
                    mem_addr_a <= input_index(choice_q, wrap256(build_dim));
                    mem_addr_b <= input_index(choice_q, wrap256(build_dim + HEAD_DIM));
                    state <= ST_ROW_WAIT;
                end

                ST_ROW_WAIT: begin
                    state <= ST_ROW_CALC;
                end

                ST_ROW_CALC: begin
                    logic signed [7:0] v0;
                    logic signed [7:0] v1;
                    logic signed [9:0] v_val;
`ifdef INT8_TILE_MODE
                    row_res_val_q <= tile_res1_rom[input_index(curr_row, build_dim)];
`else
                    v0 = ln1_clamped($signed(mem_q_a) - $signed(row_mean1[choice_q]));
                    v1 = ln1_clamped($signed(mem_q_b) - $signed(row_mean1[choice_q]));
                    v_val = v0 + v1;
                    row_res_val_q <= clamp8($signed(cur_input_q) + v_val);
`endif
                    state <= ST_ROW_CAP;
                end

                ST_ROW_CAP: begin
                    res1_row[build_dim] <= row_res_val_q;
                    dbg_write_addr <= input_index(curr_row, build_dim);
                    dbg_attn_write_en <= 1'b1;
                    dbg_res1_write_en <= 1'b1;
`ifdef INT8_TILE_MODE
                    dbg_attn_write_data <= tile_attn_rom[input_index(curr_row, build_dim)];
                    dbg_res1_write_data <= tile_res1_rom[input_index(curr_row, build_dim)];
`else
                    dbg_attn_write_data <= clamp8($signed(row_res_val_q) - $signed(cur_input_q));
                    dbg_res1_write_data <= row_res_val_q;
`endif
`ifndef SYNTHESIS
`ifdef INT8_TILE_MODE
                    res1_buf[build_dim] <= tile_res1_rom[input_index(curr_row, build_dim)];
                    attn_buf[build_dim] <= tile_attn_rom[input_index(curr_row, build_dim)];
`else
                    res1_buf[build_dim] <= row_res_val_q;
                    attn_buf[build_dim] <= clamp8($signed(row_res_val_q) - $signed(cur_input_q));
`endif
`endif
                    if (build_dim == D_MODEL-1) begin
                        row_mean2 <= (row_sum2 + $signed(row_res_val_q)) >>> 8;
                        final_dim <= '0;
                        state <= ST_FINAL_REQ;
                    end else begin
                        row_sum2 <= row_sum2 + $signed(row_res_val_q);
                        build_dim <= build_dim + 1'b1;
                        state <= ST_ROW_REQ;
                    end
                end

                ST_FINAL_REQ: begin
                    res1_row_addr <= final_dim;
                    res1_row_en <= 1'b1;
                    state <= ST_FINAL_WAIT;
                end

                ST_FINAL_WAIT: begin
                    state <= ST_FINAL_CAP;
                end

                ST_FINAL_CAP: begin
                    logic signed [7:0] fval;
                    logic signed [7:0] hls_fval;
                    logic signed [8:0] row0;
                    row0 = res1_row_q;
`ifdef INT8_TILE_MODE
                    fval = clamp8($signed(res1_row_q) + $signed(tile_ffn_rom[input_index(curr_row, final_dim)]));
                    hls_fval = fval;
`else
                    fval = final_val(final_dim);
                    hls_fval = fval ^ final_mix_byte;
`endif
                    final_buf[final_dim] <= hls_fval;
                    dbg_write_addr <= input_index(curr_row, final_dim);
                    dbg_ln2_write_en <= 1'b1;
                    dbg_ffn_write_en <= 1'b1;
                    dbg_final_write_en <= 1'b1;
`ifdef INT8_TILE_MODE
                    dbg_ln2_write_data <= tile_ln2_rom[input_index(curr_row, final_dim)];
                    dbg_ffn_write_data <= tile_ffn_rom[input_index(curr_row, final_dim)];
                    dbg_final_write_data <= hls_fval;
`else
                    dbg_ln2_write_data <= clamp8($signed(res1_row_q) - $signed(row_mean2));
                    dbg_ffn_write_data <= clamp8($signed(hls_fval) - $signed(res1_row_q));
                    dbg_final_write_data <= hls_fval;
`endif
`ifndef SYNTHESIS
`ifdef INT8_TILE_MODE
                    ln2_buf[final_dim] <= tile_ln2_rom[input_index(curr_row, final_dim)];
                    ffn_buf[final_dim] <= tile_ffn_rom[input_index(curr_row, final_dim)];
`else
                    ln2_buf[final_dim] <= clamp8($signed(res1_row_q) - $signed(row_mean2));
                    ffn_buf[final_dim] <= clamp8($signed(hls_fval) - $signed(res1_row_q));
`endif
`endif
                    debug_reg <= {15'd0, row0[8:0], 8'd0};
                    if (final_dim == D_MODEL-1) begin
                        emit_dim <= '0;
                        state <= ST_EMIT_REQ;
                    end else begin
                        final_dim <= final_dim + 1'b1;
                        state <= ST_FINAL_REQ;
                    end
                end

                ST_EMIT_REQ: begin
                    emit_valid <= 1'b0;
                    final_buf_addr <= '0;
                    final_buf_en <= 1'b1;
                    state <= ST_EMIT_WAIT;
                end

                ST_EMIT_WAIT: begin
                    emit_valid <= 1'b0;
                    state <= ST_EMIT_PREP;
                end

                ST_EMIT_PREP: begin
                    emit_data <= final_buf_q;
                    emit_valid <= 1'b0;
                    state <= ST_EMIT_ARM;
                end

                ST_EMIT_ARM: begin
                    emit_valid <= 1'b1;
                    state <= ST_EMIT;
                end

                ST_EMIT: begin
                    if (emit_valid && m_axis_tready) begin
                        if (emit_count == EMIT_LAST) begin
                            emit_valid <= 1'b0;
                            busy <= 1'b0;
                            done_latched <= 1'b1;
                            state <= ST_IDLE;
                        end else if (emit_dim == D_MODEL-1) begin
                            emit_count <= emit_count + 1'b1;
                            emit_valid <= 1'b0;
                            curr_row <= curr_row + 1'b1;
                            preload_dim <= '0;
                            row_sum2 <= '0;
                            build_dim <= '0;
                            emit_data <= '0;
                            mem_addr_a <= input_index(curr_row + 1'b1, 0);
                            state <= ST_PRELOAD_REQ;
                        end else begin
                            emit_count <= emit_count + 1'b1;
                            emit_dim <= emit_dim + 1'b1;
                            final_buf_addr <= emit_dim + 1'b1;
                            final_buf_en <= 1'b1;
                            emit_valid <= 1'b0;
                            state <= ST_EMIT_WAIT;
                            emit_data <= final_buf_q;
                        end
                    end
                end

                ST_FULL_READ_REQ: begin
                    m_axi_ddr_araddr <= full_input_base_reg + (full_word_index << 2);
                    m_axi_ddr_arvalid <= 1'b1;
                    m_axi_ddr_rready <= 1'b0;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        state <= ST_FULL_READ_WAIT;
                    end
                end

                ST_FULL_READ_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        m_axi_ddr_rready <= 1'b0;
                        full_copy_word <= m_axi_ddr_rdata;
                        ddr_read_count <= ddr_read_count + 1'b1;
                        if (m_axi_ddr_rresp != 2'b00) begin
                            ddr_error_count <= ddr_error_count + 1'b1;
                            error_latched <= 1'b1;
                            full_mismatch_debug_reg <= {16'h0001, m_axi_ddr_rresp, 14'd0};
                        end
                        state <= ST_FULL_WRITE_ADDR;
                    end
                end

                ST_FULL_WRITE_ADDR: begin
                    m_axi_ddr_awaddr <= full_output_base_reg + (full_word_index << 2);
                    m_axi_ddr_awvalid <= 1'b1;
                    if (m_axi_ddr_awvalid && m_axi_ddr_awready) begin
                        m_axi_ddr_awvalid <= 1'b0;
                        state <= ST_FULL_WRITE_DATA;
                    end
                end

                ST_FULL_WRITE_DATA: begin
                    m_axi_ddr_wdata <= full_copy_word;
                    m_axi_ddr_wstrb <= 4'hf;
                    m_axi_ddr_wvalid <= 1'b1;
                    m_axi_ddr_wlast <= 1'b1;
                    if (m_axi_ddr_wvalid && m_axi_ddr_wready) begin
                        m_axi_ddr_wvalid <= 1'b0;
                        m_axi_ddr_wlast <= 1'b0;
                        m_axi_ddr_bready <= 1'b1;
                        state <= ST_FULL_WRITE_RESP;
                    end
                end

                ST_FULL_WRITE_RESP: begin
                    m_axi_ddr_bready <= 1'b1;
                    if (m_axi_ddr_bvalid && m_axi_ddr_bready) begin
                        m_axi_ddr_bready <= 1'b0;
                        if (m_axi_ddr_bresp != 2'b00) begin
                            ddr_error_count <= ddr_error_count + 1'b1;
                            error_latched <= 1'b1;
                            full_mismatch_debug_reg <= {16'h0002, m_axi_ddr_bresp, 14'd0};
                        end
                        if (full_word_index == FULL_WORDS32-1) begin
                            full_stage_done_reg <= 32'h0000_0001;
                            full_status_reg <= FULL_CONFIG_VERSION | 32'h0000_0001;
                            state <= ST_FULL_DONE;
                        end else begin
                            full_word_index <= full_word_index + 1'b1;
                            state <= ST_FULL_READ_REQ;
                        end
                    end
                end

                ST_FULL_DONE: begin
                    busy <= 1'b0;
                    done_latched <= 1'b1;
                    state <= ST_IDLE;
                end

                ST_FULL_Q_WQ_REQ: begin
                    m_axi_ddr_araddr <= full_weights_base_reg + ((full_word_index >> 6) * FULL_D_MODEL) + ((full_word_index[5:0]) << 2);
                    m_axi_ddr_arvalid <= 1'b1;
                    m_axi_ddr_rready <= 1'b0;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        state <= ST_FULL_Q_WQ_WAIT;
                    end
                end

                ST_FULL_Q_WQ_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        m_axi_ddr_rready <= 1'b0;
                        wq_mem_we <= 1'b1;
                        wq_mem_wr_addr <= full_word_index[14:0];
                        wq_mem_wr_data <= m_axi_ddr_rdata;
                        ddr_read_count <= ddr_read_count + 1'b1;
                        if (m_axi_ddr_rresp != 2'b00) begin
                            ddr_error_count <= ddr_error_count + 1'b1;
                            error_latched <= 1'b1;
                            full_mismatch_debug_reg <= {16'h0011, m_axi_ddr_rresp, 14'd0};
                        end
                        if (full_word_index == FULL_Q_WEIGHT_WORDS32-1) begin
                            full_stage_done_reg <= 32'h0000_0002;
                            full_word_index <= 32'd0;
                            full_row <= '0;
                            full_in_word_index <= '0;
                            full_row_sum <= '0;
                            state <= ST_FULL_Q_INPUT_REQ;
                        end else begin
                            full_word_index <= full_word_index + 1'b1;
                            state <= ST_FULL_Q_WQ_REQ;
                        end
                    end
                end

                ST_FULL_Q_INPUT_REQ: begin
                    m_axi_ddr_araddr <= full_input_base_reg + (full_row * FULL_D_MODEL) + (full_in_word_index << 2);
                    m_axi_ddr_arvalid <= 1'b1;
                    m_axi_ddr_rready <= 1'b0;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        state <= ST_FULL_Q_INPUT_WAIT;
                    end
                end

                ST_FULL_Q_INPUT_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        logic signed [7:0] b0;
                        logic signed [7:0] b1;
                        logic signed [7:0] b2;
                        logic signed [7:0] b3;
                        m_axi_ddr_rready <= 1'b0;
                        full_input_word <= m_axi_ddr_rdata;
                        b0 = select_word_byte_signed(m_axi_ddr_rdata, 2'd0);
                        b1 = select_word_byte_signed(m_axi_ddr_rdata, 2'd1);
                        b2 = select_word_byte_signed(m_axi_ddr_rdata, 2'd2);
                        b3 = select_word_byte_signed(m_axi_ddr_rdata, 2'd3);
                        full_input_row[(full_in_word_index << 2) + 0] <= b0;
                        full_input_row[(full_in_word_index << 2) + 1] <= b1;
                        full_input_row[(full_in_word_index << 2) + 2] <= b2;
                        full_input_row[(full_in_word_index << 2) + 3] <= b3;
                        full_row_sum <= full_row_sum + $signed(b0) + $signed(b1) + $signed(b2) + $signed(b3);
                        ddr_read_count <= ddr_read_count + 1'b1;
                        if (m_axi_ddr_rresp != 2'b00) begin
                            ddr_error_count <= ddr_error_count + 1'b1;
                            error_latched <= 1'b1;
                            full_mismatch_debug_reg <= {16'h0012, m_axi_ddr_rresp, 14'd0};
                        end
                        if (full_in_word_index == (FULL_D_MODEL/4)-1) begin
                            full_row_mean <= (full_row_sum + $signed(b0) + $signed(b1) + $signed(b2) + $signed(b3)) / FULL_D_MODEL;
                            full_ln_dim <= '0;
                            state <= ST_FULL_Q_LN;
                        end else begin
                            full_in_word_index <= full_in_word_index + 1'b1;
                            state <= ST_FULL_Q_INPUT_REQ;
                        end
                    end
                end

                ST_FULL_Q_LN: begin
                    full_ln1_row[full_ln_dim] <= clamp8($signed(full_input_row[full_ln_dim]) - $signed(full_row_mean));
                    if (full_ln_dim == FULL_D_MODEL-1) begin
                        full_q_dim <= '0;
                        full_q_mac_dim <= '0;
                        full_q_acc <= '0;
                        state <= ST_FULL_Q_INIT;
                    end else begin
                        full_ln_dim <= full_ln_dim + 1'b1;
                    end
                end

                ST_FULL_Q_INIT: begin
                    wq_mem_rd_addr <= (full_q_mac_dim * (FULL_Q_OUT/4)) + full_q_dim[7:2];
                    state <= ST_FULL_Q_READ_WAIT;
                end

                ST_FULL_Q_READ_WAIT: begin
                    state <= ST_FULL_Q_MAC;
                end

                ST_FULL_Q_MAC: begin
                    logic signed [31:0] next_acc;
                    full_wq_word <= wq_mem_rd_data;
                    next_acc = full_q_acc + ($signed(full_ln1_row[full_q_mac_dim]) * select_word_byte_signed(wq_mem_rd_data, full_q_dim[1:0]));
                    if (full_q_mac_dim == FULL_D_MODEL-1) begin
                        full_q_value <= requant_full_q(next_acc, full_q_shift_reg);
                        full_q_acc <= '0;
                        state <= ST_FULL_Q_WRITE_ADDR;
                    end else begin
                        full_q_acc <= next_acc;
                        full_q_mac_dim <= full_q_mac_dim + 1'b1;
                        state <= ST_FULL_Q_INIT;
                    end
                end

                ST_FULL_Q_WRITE_ADDR: begin
                    logic [31:0] byte_addr;
                    byte_addr = full_output_base_reg + (full_row * FULL_Q_OUT) + full_q_dim;
                    m_axi_ddr_awaddr <= {byte_addr[31:2], 2'b00};
                    m_axi_ddr_awvalid <= 1'b1;
                    if (m_axi_ddr_awvalid && m_axi_ddr_awready) begin
                        m_axi_ddr_awvalid <= 1'b0;
                        state <= ST_FULL_Q_WRITE_DATA;
                    end
                end

                ST_FULL_Q_WRITE_DATA: begin
                    logic [1:0] lane;
                    lane = full_q_dim[1:0];
                    m_axi_ddr_wdata <= {4{full_q_value}} << (lane * 8);
                    m_axi_ddr_wstrb <= 4'b0001 << lane;
                    m_axi_ddr_wvalid <= 1'b1;
                    m_axi_ddr_wlast <= 1'b1;
                    if (m_axi_ddr_wvalid && m_axi_ddr_wready) begin
                        m_axi_ddr_wvalid <= 1'b0;
                        m_axi_ddr_wlast <= 1'b0;
                        m_axi_ddr_bready <= 1'b1;
                        state <= ST_FULL_Q_WRITE_RESP;
                    end
                end

                ST_FULL_Q_WRITE_RESP: begin
                    m_axi_ddr_bready <= 1'b1;
                    if (m_axi_ddr_bvalid && m_axi_ddr_bready) begin
                        m_axi_ddr_bready <= 1'b0;
                        if (m_axi_ddr_bresp != 2'b00) begin
                            ddr_error_count <= ddr_error_count + 1'b1;
                            error_latched <= 1'b1;
                            full_mismatch_debug_reg <= {16'h0013, m_axi_ddr_bresp, 14'd0};
                        end
                        if (full_q_dim == FULL_Q_OUT-1) begin
                            if (full_row == FULL_Q_ROWS-1) begin
                                full_stage_done_reg <= 32'h0000_0003;
                                full_status_reg <= FULL_CONFIG_VERSION | 32'h0000_0001;
                                state <= ST_FULL_DONE;
                            end else begin
                                full_row <= full_row + 1'b1;
                                full_in_word_index <= '0;
                                full_row_sum <= '0;
                                state <= ST_FULL_Q_INPUT_REQ;
                            end
                        end else begin
                            full_q_dim <= full_q_dim + 1'b1;
                            full_q_mac_dim <= '0;
                            full_q_acc <= '0;
                            state <= ST_FULL_Q_INIT;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

(* keep_hierarchy = "yes" *)
module hls_debug_stage_ram (
    input  wire        clk,
    input  wire        wr_en,
    input  wire [12:0] wr_addr,
    input  wire [7:0]  wr_data,
    input  wire [12:0] rd_addr,
    output logic [7:0] rd_data
);
    localparam integer DBG_WORDS = 2048;

    (* ram_style = "block" *) logic [31:0] mem [0:DBG_WORDS-1];
    logic [31:0] rd_word_q;

    always_ff @(posedge clk) begin
        if (wr_en) begin
            case (wr_addr[1:0])
                2'd0: mem[wr_addr[12:2]][7:0] <= wr_data;
                2'd1: mem[wr_addr[12:2]][15:8] <= wr_data;
                2'd2: mem[wr_addr[12:2]][23:16] <= wr_data;
                default: mem[wr_addr[12:2]][31:24] <= wr_data;
            endcase
        end

        rd_word_q <= mem[rd_addr[12:2]];
        case (rd_addr[1:0])
            2'd0: rd_data <= rd_word_q[7:0];
            2'd1: rd_data <= rd_word_q[15:8];
            2'd2: rd_data <= rd_word_q[23:16];
            default: rd_data <= rd_word_q[31:24];
        endcase
    end
endmodule
