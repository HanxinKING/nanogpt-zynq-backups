`timescale 1ns/1ps

(* keep_hierarchy = "yes" *)
module hls_kernel_chain_axis_full_only_core #(
    parameter integer STREAM_BYTES = 8192,
    parameter integer BYPASS_HLS = 0,
    parameter integer PL_CLK_HZ = 75000000
) (
    input  wire         s_axi_aclk,
    input  wire         s_axi_aresetn,

    input  wire [7:0]   s_axi_awaddr,
    input  wire         s_axi_awvalid,
    output logic        s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [7:0]   s_axi_araddr,
    input  wire         s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  wire         s_axi_rready,

    input  wire [7:0]   s_axis_tdata,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire         s_axis_tlast,
    output wire [7:0]   m_axis_tdata,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready,
    output wire         m_axis_tlast,

    output logic [31:0] m_axi_ddr_araddr,
    output logic        m_axi_ddr_arvalid,
    input  wire         m_axi_ddr_arready,
    output wire [7:0]   m_axi_ddr_arlen,
    output wire [2:0]   m_axi_ddr_arsize,
    output wire [1:0]   m_axi_ddr_arburst,
    output wire [3:0]   m_axi_ddr_arcache,
    output wire [2:0]   m_axi_ddr_arprot,
    input  wire [63:0]  m_axi_ddr_rdata,
    input  wire         m_axi_ddr_rvalid,
    output logic        m_axi_ddr_rready,
    input  wire [1:0]   m_axi_ddr_rresp,
    input  wire         m_axi_ddr_rlast,
    output logic [31:0] m_axi_ddr_awaddr,
    output logic        m_axi_ddr_awvalid,
    input  wire         m_axi_ddr_awready,
    output wire [7:0]   m_axi_ddr_awlen,
    output wire [2:0]   m_axi_ddr_awsize,
    output wire [1:0]   m_axi_ddr_awburst,
    output wire [3:0]   m_axi_ddr_awcache,
    output wire [2:0]   m_axi_ddr_awprot,
    output logic [63:0] m_axi_ddr_wdata,
    output logic [7:0]  m_axi_ddr_wstrb,
    output logic        m_axi_ddr_wvalid,
    input  wire         m_axi_ddr_wready,
    output logic        m_axi_ddr_wlast,
    input  wire [1:0]   m_axi_ddr_bresp,
    input  wire         m_axi_ddr_bvalid,
    output logic        m_axi_ddr_bready,
    input  wire         uart_rx,
    output wire         uart_tx,
    output wire         irq
);
    localparam integer FULL_BYTES = 98304;
    localparam integer FULL_WORDS32 = FULL_BYTES / 4;
    localparam integer FULL_D_MODEL = 384;
    localparam integer FULL_N_LAYER = 6;
    localparam integer FULL_Q_OUT = 384;
    localparam integer FULL_Q_ROWS = 256;
    localparam integer FULL_MLP_DIM = 1536;
    localparam integer FULL_VOCAB_SIZE = 65;
    localparam integer FULL_LM_HEAD_BYTES = FULL_D_MODEL * FULL_VOCAB_SIZE;
    localparam integer FULL_Q_WEIGHT_BYTES = FULL_D_MODEL * FULL_Q_OUT;
    localparam integer FULL_Q_WEIGHT_WORDS64 = FULL_Q_WEIGHT_BYTES / 8;
    localparam integer WLOAD_PP_WORDS = 2048;
    localparam integer WLOAD_BURST_BEATS = 16;
    localparam integer FULL_W1_BYTES = FULL_D_MODEL * FULL_MLP_DIM;
    localparam logic [31:0] LAYER0_ATTN_OUT_MULT_Q30 = 32'h4D8D_C518;
    localparam logic [31:0] DEFAULT_WEIGHTS_BASE = 32'h1100_0000;
    localparam logic [31:0] DEFAULT_FULL_INPUT_BASE = 32'h1000_0000;
    localparam logic [31:0] DEFAULT_FULL_OUTPUT_BASE = 32'h1002_0000;
    localparam logic [31:0] DEFAULT_FULL_SCALES_BASE = 32'h11C0_0000;
    localparam logic [31:0] DEFAULT_FULL_DEBUG_BASE = 32'h12E0_0000;
    localparam logic [31:0] FULL_CONFIG_VERSION = 32'hF117_0001;
`ifndef FULL_INT8_Q_SHIFT
`define FULL_INT8_Q_SHIFT 13
`endif
`ifndef FULL_INT8_ATTN_PROJ_SHIFT
`define FULL_INT8_ATTN_PROJ_SHIFT 10
`endif
`ifndef FULL_INT8_FFN_MID_SHIFT
`define FULL_INT8_FFN_MID_SHIFT 13
`endif
`ifndef FULL_INT8_FFN_SHIFT
`define FULL_INT8_FFN_SHIFT 11
`endif
    localparam integer FULL_Q_SHIFT = `FULL_INT8_Q_SHIFT;
    localparam integer FULL_ATTN_PROJ_SHIFT = `FULL_INT8_ATTN_PROJ_SHIFT;
    localparam integer FULL_FFN_MID_SHIFT = `FULL_INT8_FFN_MID_SHIFT;
    localparam integer FULL_FFN_SHIFT = `FULL_INT8_FFN_SHIFT;

    typedef enum logic [7:0] {
        ST_IDLE,
        ST_COPY_READ_REQ,
        ST_COPY_READ_WAIT,
        ST_COPY_WRITE_ADDR,
        ST_COPY_WRITE_DATA,
        ST_COPY_WRITE_RESP,
        ST_Q_W_REQ,
        ST_Q_W_WAIT,
        ST_Q_W_SEG_DRAIN,
        ST_Q_W_DRAIN,
        ST_Q_INPUT_REQ,
        ST_Q_INPUT_WAIT,
        ST_Q_INPUT_CAPTURE,
        ST_Q_MEAN_PREP,
        ST_Q_MEAN_ITER,
        ST_Q_MEAN_DONE,
        ST_Q_VARIANCE_MUL,
        ST_Q_VARIANCE_CALC,
        ST_Q_INV_CALC,
        ST_Q_RD,
        ST_Q_RD_WAIT,
        ST_Q_MAC_PREP,
        ST_Q_MUL,
        ST_Q_MAC,
        ST_Q_MAC_FINAL,
        ST_Q_QUANT,
        ST_Q_QUANT_WAIT,
        ST_Q_WRITE_ADDR,
        ST_Q_WRITE_DATA,
        ST_Q_WRITE_RESP,
        ST_ATTN_Q_REQ,
        ST_ATTN_Q_WAIT,
        ST_ATTN_Q_CAP,
        ST_ATTN_SCORE_INIT,
        ST_ATTN_K_REQ,
        ST_ATTN_K_WAIT,
        ST_ATTN_K_MUL,
        ST_ATTN_K_ACC,
        ST_ATTN_K_FINAL,
        ST_ATTN_WEIGHT_INIT,
        ST_ATTN_WEIGHT_CALC,
        ST_ATTN_VALUE_INIT,
        ST_ATTN_V_REQ,
        ST_ATTN_V_WAIT,
        ST_ATTN_V_WEIGHT_LOAD,
        ST_ATTN_V_MUL,
        ST_ATTN_V_ACCUM,
        ST_ATTN_DIV_PREP,
        ST_ATTN_DIV_MUL,
        ST_ATTN_DIV_ABS,
        ST_ATTN_DIV_SAT,
        ST_ATTN_DIV_ITER,
        ST_ATTN_DIV_DONE,
        ST_ATTN_WRITE_ADDR,
        ST_ATTN_WRITE_DATA,
        ST_ATTN_WRITE_RESP,
        ST_PROJ_W_REQ,
        ST_PROJ_W_WAIT,
        ST_PROJ_W_SEG_DRAIN,
        ST_PROJ_W_DRAIN,
        ST_PROJ_INPUT_REQ,
        ST_PROJ_INPUT_WAIT,
        ST_PROJ_INPUT_CAPTURE,
        ST_PROJ_RD,
        ST_PROJ_RD_WAIT,
        ST_PROJ_MAC_PREP,
        ST_PROJ_MUL,
        ST_PROJ_MAC,
        ST_PROJ_MAC_FINAL,
        ST_PROJ_QUANT,
        ST_PROJ_QUANT_WAIT,
        ST_PROJ_RES_REQ,
        ST_PROJ_RES_WAIT,
        ST_PROJ_WRITE_ADDR,
        ST_PROJ_WRITE_DATA,
        ST_PROJ_WRITE_RESP,
        ST_LN2_INPUT_REQ,
        ST_LN2_INPUT_WAIT,
        ST_LN2_INPUT_CAPTURE,
        ST_LN2_MEAN_PREP,
        ST_LN2_MEAN_ITER,
        ST_LN2_MEAN_DONE,
        ST_LN2_VARIANCE_MUL,
        ST_LN2_VARIANCE_CALC,
        ST_LN2_INV_CALC,
        ST_LN2_HLS_START,
        ST_LN2_HLS_WAIT,
        ST_LN2_NORM_PREP,
        ST_LN2_NORM_MUL,
        ST_LN2_NORM_ROUND,
        ST_LN2_WRITE_ADDR,
        ST_LN2_WRITE_DATA,
        ST_LN2_WRITE_RESP,
        ST_FFN_INPUT_REQ,
        ST_FFN_INPUT_WAIT,
        ST_FFN_INPUT_CAPTURE,
        ST_FFN_W1_REQ,
        ST_FFN_W1_WAIT,
        ST_FFN_W1_MUL,
        ST_FFN_W1_MUL_WAIT,
        ST_FFN_W1_MAC,
        ST_FFN_W1_NEXT_WAIT,
        ST_FFN_W1_FINAL,
        ST_FFN_W1_QUANT,
        ST_FFN_W1_QUANT_WAIT,
        ST_FFN_GELU_LOAD_REQ,
        ST_FFN_GELU_LOAD_WAIT,
        ST_FFN_GELU_LOAD_CAP,
        ST_FFN_GELU_START,
        ST_FFN_GELU_WAIT,
        ST_FFN_GELU_DONE_DELAY,
        ST_FFN_GELU_WRITE,
        ST_FFN_W2_RD_MID,
        ST_FFN_W2_W_REQ,
        ST_FFN_W2_W_WAIT,
        ST_FFN_W2_MUL,
        ST_FFN_W2_MUL_WAIT,
        ST_FFN_W2_MAC,
        ST_FFN_W2_NEXT_WAIT,
        ST_FFN_W2_NEXT_MID_WAIT,
        ST_FFN_W2_FINAL,
        ST_FFN_W2_QUANT,
        ST_FFN_W2_QUANT_WAIT,
        ST_FFN_RES_REQ,
        ST_FFN_RES_WAIT,
        ST_FFN_WRITE_ADDR,
        ST_FFN_WRITE_DATA,
        ST_FFN_WRITE_RESP,
        ST_LM_LNF_REQ,
        ST_LM_LNF_WAIT,
        ST_LM_LNF_CAPTURE,
        ST_LM_FAST_GROUP_INIT,
        ST_LM_FAST_ROM_WAIT,
        ST_LM_FAST_MUL_LOAD,
        ST_LM_FAST_MUL_EXEC,
        ST_LM_FAST_ACCUM,
        ST_LM_FAST_SCALE_LOAD,
        ST_LM_FAST_SCALE_EXEC,
        ST_LM_FAST_SCALE_COMPARE,
        ST_LM_VOCAB_INIT,
        ST_LM_W_REQ,
        ST_LM_W_WAIT,
        ST_LM_MAC_LOAD,
        ST_LM_MAC_MUL,
        ST_LM_MAC,
        ST_LM_NEXT_VOCAB,
        ST_LM_WRITE_ADDR,
        ST_LM_WRITE_DATA,
        ST_LM_WRITE_RESP,
        ST_DONE,
        ST_ATTN_WEIGHT_APPLY,
        ST_ATTN_WEIGHT_MUL,
        ST_PROJ_RES_MUL,
        ST_PROJ_RES_CALC
    } state_t;

    state_t state;
    logic [31:0] mode_reg;
    logic [31:0] full_input_base_reg;
    logic [31:0] full_output_base_reg;
    logic [31:0] full_weights_base_reg;
    logic [31:0] full_scales_base_reg;
    logic [31:0] full_debug_base_reg;
    logic [4:0] full_q_shift_reg;
    logic [4:0] full_attn_proj_shift_reg;
    logic [4:0] full_ffn_mid_shift_reg;
    logic [4:0] full_ffn_shift_reg;
    logic [2:0] full_attn_layer_reg;
    logic [8:0] active_rows_reg;
    logic [8:0] row_start_reg;
    logic [31:0] full_status_reg;
    logic [31:0] full_stage_done_reg;
    logic [31:0] full_mismatch_debug_reg;
    logic [31:0] ddr_read_count;
    logic [31:0] ddr_error_count;
    logic [63:0] ddr_read_word;
    logic [1:0] ddr_read_resp;
    logic [63:0] ddr_wdata_stage;
    logic [31:0] word_index;
    logic [31:0] copy_word;
    logic [8:0] in_word_index;
    logic [7:0] row;
    logic [8:0] q_dim;
    logic [8:0] mac_dim;
    logic signed [18:0] row_sum;
    logic signed [9:0] row_mean;
    logic [31:0] row_sq_sum;
    logic [31:0] row_sq_sum_q;
    logic [15:0] row_inv_std_q12;
    logic [31:0] row_variance_q12;
    (* use_dsp = "yes" *) logic [31:0] row_sq_mean;
    (* use_dsp = "yes" *) logic [31:0] row_mean_sq;
    logic signed [31:0] q_acc;
    logic signed [31:0] q_final_acc;
    logic signed [18:0] row_sum_q;
    logic row_sum_q_neg;
    logic [18:0] div384_rem;
    logic [8:0] div384_quot;
    logic [3:0] div384_bit;
    logic signed [7:0] mac_ln1_value;
    logic signed [7:0] mac_weight_value;
    logic signed [7:0] q_value;
    logic [63:0] q_word_pack;
    logic [63:0] q_write_word;
    logic [7:0] attn_row;
    logic [2:0] attn_head;
    logic [7:0] attn_cand;
    logic [7:0] attn_best_col;
    logic [4:0] attn_word_index;
    logic signed [31:0] attn_score;
    logic signed [31:0] attn_next_score;
    logic signed [31:0] attn_best_score;
    logic [63:0] attn_weight_scaled_diff;
    logic signed [31:0] attn_weight_diff;
    logic attn_weight_diff_zero;
    logic signed [31:0] attn_score_mem [0:255];
    logic [5:0] attn_weight_mem [0:255];
    logic [5:0] attn_exp_q6_rom [0:255];
    logic [15:0] attn_den;
    logic signed [31:0] attn_sum0;
    logic signed [31:0] attn_sum1;
    logic signed [31:0] attn_sum2;
    logic signed [31:0] attn_sum3;
    logic [31:0] attn_read_word;
    logic [1:0] attn_read_resp;
    logic signed [15:0] attn_prod0;
    logic signed [15:0] attn_prod1;
    logic signed [15:0] attn_prod2;
    logic signed [15:0] attn_prod3;
    logic [5:0] attn_v_weight;
    logic [1:0] attn_div_lane;
    logic [6:0] attn_div_bit;
    logic attn_div_neg;
    logic signed [31:0] attn_div_value;
    logic signed [63:0] attn_div_scaled;
    logic [63:0] attn_div_num;
    logic [63:0] attn_div_den;
    logic [63:0] attn_div_rem;
    logic [63:0] attn_div_quot;
    logic [31:0] attn_write_word;
    logic [1:0] proj_res_lane;
    logic signed [7:0] proj_input_value;
    logic signed [7:0] proj_res_value;
    (* use_dsp = "yes" *) logic signed [63:0] proj_input_scaled;
    (* use_dsp = "yes" *) logic signed [63:0] proj_value_scaled;
    logic [8:0] ln2_dim;
    logic signed [7:0] ln2_value;
    logic [2:0] ln2_seg;
    logic ln2_hls_start_reg;
    logic signed [31:0] ln2_centered;
    logic signed [47:0] ln2_scaled;
    logic signed [31:0] ln2_rounded;
    logic [10:0] ffn_hidden_dim;
    logic [1:0] ffn_weight_lane;
    logic [4:0] ffn_parallel_lane;
    logic signed [31:0] ffn_acc0;
    logic signed [31:0] ffn_acc1;
    logic signed [31:0] ffn_acc2;
    logic signed [31:0] ffn_acc3;
    logic signed [31:0] ffn_acc4;
    logic signed [31:0] ffn_acc5;
    logic signed [31:0] ffn_acc6;
    logic signed [31:0] ffn_acc7;
    logic signed [31:0] ffn_acc8;
    logic signed [31:0] ffn_acc9;
    logic signed [31:0] ffn_acc10;
    logic signed [31:0] ffn_acc11;
    logic signed [31:0] ffn_acc12;
    logic signed [31:0] ffn_acc13;
    logic signed [31:0] ffn_acc14;
    logic signed [31:0] ffn_acc15;
    logic signed [31:0] ffn_acc16;
    logic signed [31:0] ffn_acc17;
    logic signed [31:0] ffn_acc18;
    logic signed [31:0] ffn_acc19;
    logic signed [31:0] ffn_acc20;
    logic signed [31:0] ffn_acc21;
    logic signed [31:0] ffn_acc22;
    logic signed [31:0] ffn_acc23;
    logic signed [31:0] ffn_acc24;
    logic signed [31:0] ffn_acc25;
    logic signed [31:0] ffn_acc26;
    logic signed [31:0] ffn_acc27;
    logic signed [31:0] ffn_acc28;
    logic signed [31:0] ffn_acc29;
    logic signed [31:0] ffn_acc30;
    logic signed [31:0] ffn_acc31;
    logic signed [31:0] ffn_final0;
    logic signed [31:0] ffn_final1;
    logic signed [31:0] ffn_final2;
    logic signed [31:0] ffn_final3;
    logic signed [31:0] ffn_final4;
    logic signed [31:0] ffn_final5;
    logic signed [31:0] ffn_final6;
    logic signed [31:0] ffn_final7;
    logic signed [31:0] ffn_final8;
    logic signed [31:0] ffn_final9;
    logic signed [31:0] ffn_final10;
    logic signed [31:0] ffn_final11;
    logic signed [31:0] ffn_final12;
    logic signed [31:0] ffn_final13;
    logic signed [31:0] ffn_final14;
    logic signed [31:0] ffn_final15;
    logic signed [31:0] ffn_final16;
    logic signed [31:0] ffn_final17;
    logic signed [31:0] ffn_final18;
    logic signed [31:0] ffn_final19;
    logic signed [31:0] ffn_final20;
    logic signed [31:0] ffn_final21;
    logic signed [31:0] ffn_final22;
    logic signed [31:0] ffn_final23;
    logic signed [31:0] ffn_final24;
    logic signed [31:0] ffn_final25;
    logic signed [31:0] ffn_final26;
    logic signed [31:0] ffn_final27;
    logic signed [31:0] ffn_final28;
    logic signed [31:0] ffn_final29;
    logic signed [31:0] ffn_final30;
    logic signed [31:0] ffn_final31;
    logic signed [24:0] ffn_mul_a;
    logic signed [17:0] ffn_mul_b0;
    logic signed [17:0] ffn_mul_b1;
    logic signed [17:0] ffn_mul_b2;
    logic signed [17:0] ffn_mul_b3;
    logic signed [17:0] ffn_mul_b4;
    logic signed [17:0] ffn_mul_b5;
    logic signed [17:0] ffn_mul_b6;
    logic signed [17:0] ffn_mul_b7;
    logic signed [17:0] ffn_mul_b8;
    logic signed [17:0] ffn_mul_b9;
    logic signed [17:0] ffn_mul_b10;
    logic signed [17:0] ffn_mul_b11;
    logic signed [17:0] ffn_mul_b12;
    logic signed [17:0] ffn_mul_b13;
    logic signed [17:0] ffn_mul_b14;
    logic signed [17:0] ffn_mul_b15;
    logic signed [17:0] ffn_mul_b16;
    logic signed [17:0] ffn_mul_b17;
    logic signed [17:0] ffn_mul_b18;
    logic signed [17:0] ffn_mul_b19;
    logic signed [17:0] ffn_mul_b20;
    logic signed [17:0] ffn_mul_b21;
    logic signed [17:0] ffn_mul_b22;
    logic signed [17:0] ffn_mul_b23;
    logic signed [17:0] ffn_mul_b24;
    logic signed [17:0] ffn_mul_b25;
    logic signed [17:0] ffn_mul_b26;
    logic signed [17:0] ffn_mul_b27;
    logic signed [17:0] ffn_mul_b28;
    logic signed [17:0] ffn_mul_b29;
    logic signed [17:0] ffn_mul_b30;
    logic signed [17:0] ffn_mul_b31;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod0;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod1;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod2;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod3;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod4;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod5;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod6;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod7;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod8;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod9;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod10;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod11;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod12;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod13;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod14;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod15;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod16;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod17;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod18;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod19;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod20;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod21;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod22;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod23;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod24;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod25;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod26;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod27;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod28;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod29;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod30;
    (* use_dsp = "yes" *) logic signed [42:0] ffn_prod31;
    logic [63:0] ffn_weight_ping;
    logic [63:0] ffn_weight_pong;
    logic [63:0] ffn_weight_tail;
    logic [63:0] ffn_weight_quad;
    logic [63:0] ffn_weight_next_ping;
    logic [63:0] ffn_weight_next_pong;
    logic [63:0] ffn_weight_next_tail;
    logic [63:0] ffn_weight_next_quad;
    logic [1:0] ffn_weight_beat;
    logic ffn_prefetch_ready;
    logic signed [7:0] ffn_mid_value;
    logic signed [7:0] ffn_res_value;
    logic ffn_add_residual;
    logic [63:0] ffn_word_pack;
    logic [63:0] ffn_write_word;
    logic [10:0] gelu_base;
    logic [5:0] gelu_idx;
    logic [2:0] gelu_done_delay;
    logic ge_hls_start_reg;
    logic signed [7:0] gelu_x_mem [0:63];
    logic [6:0] lm_vocab_idx;
    logic [6:0] lm_best_token;
    logic signed [31:0] lm_acc;
    logic signed [7:0] lm_ln_value;
    (* use_dsp = "yes" *) logic signed [15:0] lm_mac_product;
    logic signed [63:0] lm_best_score;
    logic signed [7:0] lm_weight_value;
    logic [1:0] lm_weight_lane;
    logic [1:0] lm_argmax_lane;
    logic [3:0] lm_group_idx;
    logic [2:0] lm_scale_lane;
    logic [11:0] lm_rom_addr;
    logic [63:0] lm_rom_data;
    logic signed [31:0] lm_scale_acc;
    logic [31:0] lm_scale_factor;
    (* use_dsp = "yes" *) logic signed [63:0] lm_scale_product;
    logic busy;
    logic done_latched;
    logic error_latched;
    logic start_pulse;
    logic clear_pulse;
    logic uart_rx_pop;
    logic uart_tx_push;
    logic uart_clear_errors;
    logic [7:0] uart_rx_data;
    logic [7:0] uart_tx_data;
    logic uart_rx_valid;
    logic uart_tx_ready;
    logic [4:0] uart_rx_count;
    logic [4:0] uart_tx_count;
    logic uart_rx_overrun;
    logic uart_rx_framing_error;
    wire [31:0] uart_status = {
        8'h55, 3'd0, uart_tx_count, 3'd0, uart_rx_count, 4'd0,
        uart_rx_framing_error, uart_rx_overrun, uart_tx_ready, uart_rx_valid
    };

    (* ram_style = "block" *) logic [63:0] wq_word_mem [0:FULL_Q_WEIGHT_WORDS64-1];
    (* rom_style = "block" *) logic [31:0] q_mult_q30_rom [0:FULL_N_LAYER*FULL_Q_OUT-1];
    (* rom_style = "block" *) logic [31:0] k_mult_q30_rom [0:FULL_N_LAYER*FULL_Q_OUT-1];
    (* rom_style = "block" *) logic [31:0] v_mult_q30_rom [0:FULL_N_LAYER*FULL_Q_OUT-1];
    (* rom_style = "block" *) logic [31:0] attn_proj_mult_q30_rom [0:FULL_N_LAYER*FULL_Q_OUT-1];
    (* rom_style = "block" *) logic [31:0] ffn_mid_mult_q30_rom [0:FULL_N_LAYER*FULL_MLP_DIM-1];
    (* rom_style = "block" *) logic [31:0] ffn_mult_q30_rom [0:FULL_N_LAYER*FULL_D_MODEL-1];
    (* rom_style = "block" *) logic [63:0] lm_head_weight_rom [0:3455];
    (* rom_style = "distributed" *) logic [31:0] lm_scale_ratio_rom [0:FULL_VOCAB_SIZE-1];
    logic [15:0] wq_rd_addr;
    logic [63:0] wq_rd_data;
    (* ram_style = "block" *) logic [63:0] wload_pp0 [0:WLOAD_PP_WORDS-1];
    (* ram_style = "block" *) logic [63:0] wload_pp1 [0:WLOAD_PP_WORDS-1];
    logic wload_fill_we;
    logic wload_fill_bank;
    logic wload_fill_bank_q;
    logic [10:0] wload_fill_addr;
    logic [63:0] wload_fill_data;
    logic [10:0] wload_fill_count;
    logic [15:0] wload_segment_base;
    logic [3:0] wload_burst_beat;
    (* max_fanout = 8 *) logic wload_drain_active;
    logic wload_drain_bank;
    logic [10:0] wload_drain_issue_addr;
    logic [15:0] wload_drain_base;
    logic [63:0] wload_pp0_rd_data;
    logic [63:0] wload_pp1_rd_data;
    logic wload_drain_pipe_valid;
    logic wload_drain_pipe_bank;
    logic [10:0] wload_drain_pipe_addr;
    logic [15:0] wload_drain_pipe_base;
    logic [31:0] q_mult_q30_data;
    logic [31:0] k_mult_q30_data;
    logic [31:0] v_mult_q30_data;
    logic [31:0] attn_proj_mult_q30_data;
    logic [31:0] ffn_mid_mult_q30_data;
    logic [31:0] ffn_mult_q30_data;
    (* ram_style = "block" *) logic signed [7:0] ffn_mid_mem [0:FULL_MLP_DIM-1];
    logic ffn_mid_we;
    logic [10:0] ffn_mid_wr_addr;
    logic signed [7:0] ffn_mid_wr_data;
    logic [10:0] ffn_mid_rd_addr;
    logic signed [7:0] ffn_mid_rd_data;
    logic signed [7:0] input_row [0:FULL_D_MODEL-1];
    logic signed [7:0] attn_q_head [0:63];
    logic [31:0] quality_argmax_base_reg;
    logic [511:0] quality_ln_x_flat;
    logic [511:0] quality_ln_y_flat;
    logic [511:0] quality_ge_x_flat;
    logic [511:0] quality_ge_y_flat;
    logic [2047:0] quality_tm_a_flat;
    logic [2047:0] quality_tm_b_flat;
    logic [8191:0] quality_tm_c_flat;
    logic [2047:0] quality_mha_x_flat;
    logic [2047:0] quality_mha_wq_flat;
    logic [2047:0] quality_mha_wk_flat;
    logic [2047:0] quality_mha_wv_flat;
    logic [4095:0] quality_mha_out_flat;
    logic quality_tm_done;
    logic quality_mha_done;
    logic quality_ln_done;
    logic quality_ge_done;
    logic [7:0] quality_tm_result_byte;
    logic [7:0] quality_mha_result_byte;
    logic [7:0] quality_ln_result_byte;
    logic [7:0] quality_ge_result_byte;
    wire quality_tm_start;
    wire quality_mha_start;
    wire quality_ln_start;
    wire quality_ge_start;
    wire [31:0] quality_hls_signature;

`ifdef FFN_FULL_DIAG
    string ffn_diag_dir;
    integer fd_ln2_full;
    integer fd_w1_addr_full;
    integer fd_w1_weight_full;
    integer fd_w1_acc_full;
    integer fd_ffn_mid_full;
    integer fd_gelu_in_full;
    integer fd_gelu_out_full;
    integer fd_w2_addr_full;
    integer fd_w2_weight_full;
    integer fd_w2_acc_full;
    integer fd_ffn_out_full;
    integer fd_final_full;

    initial begin
        if (!$value$plusargs("DUMP_DIR=%s", ffn_diag_dir)) begin
            ffn_diag_dir = "F:/nanogpt_ZYNQ/fpga/nano_gpt/generated/sim_dumps/ffn_full_diag_default";
        end
        fd_ln2_full      = $fopen({ffn_diag_dir, "/ln2_full.mem"}, "w");
        fd_w1_addr_full  = $fopen({ffn_diag_dir, "/w1_addr_full.mem"}, "w");
        fd_w1_weight_full= $fopen({ffn_diag_dir, "/w1_weight_full.mem"}, "w");
        fd_w1_acc_full   = $fopen({ffn_diag_dir, "/w1_acc_full.mem"}, "w");
        fd_ffn_mid_full  = $fopen({ffn_diag_dir, "/ffn_mid_full.mem"}, "w");
        fd_gelu_in_full  = $fopen({ffn_diag_dir, "/gelu_in_full.mem"}, "w");
        fd_gelu_out_full = $fopen({ffn_diag_dir, "/gelu_out_full.mem"}, "w");
        fd_w2_addr_full  = $fopen({ffn_diag_dir, "/w2_addr_full.mem"}, "w");
        fd_w2_weight_full= $fopen({ffn_diag_dir, "/w2_weight_full.mem"}, "w");
        fd_w2_acc_full   = $fopen({ffn_diag_dir, "/w2_acc_full.mem"}, "w");
        fd_ffn_out_full  = $fopen({ffn_diag_dir, "/ffn_out_full.mem"}, "w");
        fd_final_full    = $fopen({ffn_diag_dir, "/final_full.mem"}, "w");
    end

    task automatic diag_i8(input integer fd, input logic signed [7:0] value);
        if (fd != 0) $fwrite(fd, "%02x\n", value[7:0]);
    endtask

    task automatic diag_u32(input integer fd, input logic [31:0] value);
        if (fd != 0) $fwrite(fd, "%08x\n", value);
    endtask
`endif

    genvar hls_i;
    generate
        for (hls_i = 0; hls_i < 64; hls_i = hls_i + 1) begin : g_quality_ln_seed
            assign quality_ln_x_flat[hls_i*8 +: 8] = input_row[(ln2_seg * 64) + hls_i];
            assign quality_ge_x_flat[hls_i*8 +: 8] = gelu_x_mem[hls_i];
        end
        for (hls_i = 0; hls_i < 256; hls_i = hls_i + 1) begin : g_quality_tm_seed
            assign quality_tm_a_flat[hls_i*8 +: 8] = input_row[hls_i % FULL_D_MODEL];
            assign quality_tm_b_flat[hls_i*8 +: 8] = input_row[(hls_i + 64) % FULL_D_MODEL];
            assign quality_mha_x_flat[hls_i*8 +: 8] = input_row[hls_i % FULL_D_MODEL];
            assign quality_mha_wq_flat[hls_i*8 +: 8] = input_row[(hls_i + 64) % FULL_D_MODEL];
            assign quality_mha_wk_flat[hls_i*8 +: 8] = input_row[(hls_i + 128) % FULL_D_MODEL];
            assign quality_mha_wv_flat[hls_i*8 +: 8] = input_row[(hls_i + 192) % FULL_D_MODEL];
        end
    endgenerate

    assign quality_tm_start = start_pulse && (mode_reg[1] || mode_reg[3] || mode_reg[8]);
    assign quality_mha_start = start_pulse && (mode_reg[2] || mode_reg[8]);
    assign quality_ln_start = (start_pulse && (mode_reg[7] || mode_reg[8])) || ln2_hls_start_reg;
    assign quality_ge_start = (start_pulse && (mode_reg[5] || mode_reg[6] || mode_reg[8])) || ge_hls_start_reg;

    // TM/MHA HLS wrappers were signature-only in this core; the layer0 full
    // datapath below uses the explicit DDR-backed Q/K/V and attention RTL.
    // Keeping the unused wrappers forced large HLS IP into the bitstream and
    // blocked Zynq-7020 placement without changing model outputs.
    assign quality_tm_done = quality_tm_start;
    assign quality_mha_done = quality_mha_start;
    assign quality_tm_result_byte = 8'h74;  // t: trimmed signature-only HLS
    assign quality_mha_result_byte = 8'h6d; // m: trimmed signature-only HLS
    assign quality_tm_c_flat = 8192'd0;
    assign quality_mha_out_flat = 4096'd0;

    (* keep_hierarchy = "yes" *) layernorm_hls_wrapper u_quality_ln (
        .ap_clk(s_axi_aclk),
        .ap_rst(~s_axi_aresetn),
        .start(quality_ln_start),
        .x_flat(quality_ln_x_flat),
        .done(quality_ln_done),
        .result_byte(quality_ln_result_byte),
        .y_flat(quality_ln_y_flat)
    );
    (* keep_hierarchy = "yes" *) gelu_embed_hls_wrapper u_quality_ge (
        .ap_clk(s_axi_aclk),
        .ap_rst(~s_axi_aresetn),
        .start(quality_ge_start),
        .x_flat(quality_ge_x_flat),
        .done(quality_ge_done),
        .result_byte(quality_ge_result_byte),
        .gelu_out_flat(quality_ge_y_flat)
    );

    assign s_axis_tready = 1'b0;
    assign m_axis_tdata = 8'd0;
    assign m_axis_tvalid = 1'b0;
    assign m_axis_tlast = 1'b0;
    assign irq = done_latched;
    assign m_axi_ddr_arlen = ((state == ST_Q_W_REQ) || (state == ST_PROJ_W_REQ)) ?
                              (WLOAD_BURST_BEATS-1) :
                             ((state == ST_FFN_W1_REQ) || (state == ST_FFN_W1_MUL) ||
                              (state == ST_FFN_W1_MUL_WAIT) || (state == ST_FFN_W1_MAC) ||
                              (state == ST_FFN_W1_NEXT_WAIT) ||
                              (state == ST_FFN_W2_W_REQ) || (state == ST_FFN_W2_MUL) ||
                              (state == ST_FFN_W2_MUL_WAIT) || (state == ST_FFN_W2_MAC) ||
                              (state == ST_FFN_W2_NEXT_WAIT)) ?
                              8'd3 : 8'd0;
    assign m_axi_ddr_arsize = ((state == ST_Q_W_REQ) || (state == ST_PROJ_W_REQ) ||
                               (state == ST_FFN_W1_REQ) || (state == ST_FFN_W1_MUL) ||
                               (state == ST_FFN_W1_MUL_WAIT) || (state == ST_FFN_W1_MAC) ||
                               (state == ST_FFN_W1_NEXT_WAIT) ||
                               (state == ST_FFN_W2_W_REQ) || (state == ST_FFN_W2_MUL) ||
                               (state == ST_FFN_W2_MUL_WAIT) || (state == ST_FFN_W2_MAC) ||
                               (state == ST_FFN_W2_NEXT_WAIT)) ?
                              3'd3 : 3'd2;
    assign m_axi_ddr_arburst = 2'b01;
    assign m_axi_ddr_arcache = 4'b0011;
    assign m_axi_ddr_arprot = 3'b000;
    assign m_axi_ddr_awlen = 8'd0;
    assign m_axi_ddr_awsize = ((state == ST_Q_WRITE_ADDR) || (state == ST_Q_WRITE_DATA) ||
                               (state == ST_Q_WRITE_RESP) ||
                               (mode_reg[9] && ((state == ST_PROJ_WRITE_ADDR) ||
                                                (state == ST_PROJ_WRITE_DATA) ||
                                                (state == ST_PROJ_WRITE_RESP))) ||
                               ((state == ST_FFN_WRITE_ADDR) || (state == ST_FFN_WRITE_DATA) ||
                                (state == ST_FFN_WRITE_RESP))) ? 3'd3 : 3'd2;
    assign m_axi_ddr_awburst = 2'b01;
    assign m_axi_ddr_awcache = 4'b0011;
    assign m_axi_ddr_awprot = 3'b000;

    function automatic logic signed [7:0] clamp8(input logic signed [31:0] value);
        if (value > 127) clamp8 = 8'sd127;
        else if (value < -128) clamp8 = -8'sd128;
        else clamp8 = value[7:0];
    endfunction

    function automatic logic signed [31:0] round_shift_signed(input logic signed [31:0] value, input integer shift);
        logic signed [31:0] abs_value;
        begin
            if (shift <= 0) round_shift_signed = value;
            else if (value >= 0) round_shift_signed = (value + (32'sd1 <<< (shift - 1))) >>> shift;
            else begin
                abs_value = -value;
                round_shift_signed = -((abs_value + (32'sd1 <<< (shift - 1))) >>> shift);
            end
        end
    endfunction

    function automatic logic signed [7:0] select_word_byte_signed(input logic [31:0] word, input logic [1:0] lane);
        case (lane)
            2'd0: select_word_byte_signed = $signed(word[7:0]);
            2'd1: select_word_byte_signed = $signed(word[15:8]);
            2'd2: select_word_byte_signed = $signed(word[23:16]);
            default: select_word_byte_signed = $signed(word[31:24]);
        endcase
    endfunction

    function automatic logic signed [7:0] select_dword_byte_signed(input logic [63:0] word, input logic [2:0] lane);
        select_dword_byte_signed = $signed(word[lane*8 +: 8]);
    endfunction

    function automatic logic [31:0] select_axi_word32(input logic [63:0] word, input logic high_half);
        select_axi_word32 = high_half ? word[63:32] : word[31:0];
    endfunction

    function automatic logic [63:0] align_axi_wdata32(input logic [31:0] word, input logic high_half);
        align_axi_wdata32 = high_half ? {word, 32'd0} : {32'd0, word};
    endfunction

    function automatic logic [7:0] align_axi_wstrb4(input logic [3:0] strb, input logic high_half);
        align_axi_wstrb4 = high_half ? {strb, 4'd0} : {4'd0, strb};
    endfunction

    function automatic logic signed [7:0] requant_full_q(input logic signed [31:0] value, input integer shift);
        requant_full_q = clamp8(round_shift_signed(value, shift));
    endfunction

    function automatic logic signed [7:0] requant_q30(input logic signed [31:0] value, input logic [31:0] mult_q30);
        logic signed [63:0] scaled;
        logic signed [63:0] rounded;
        begin
            scaled = $signed(value) * $signed({1'b0, mult_q30[30:0]});
            if (scaled >= 0) rounded = (scaled + 64'sd536870912) >>> 30;
            else rounded = -(((-scaled) + 64'sd536870912) >>> 30);
            requant_q30 = clamp8(rounded[31:0]);
        end
    endfunction

    function automatic logic signed [7:0] requant_full_attn_proj(input logic signed [31:0] value, input integer shift);
        requant_full_attn_proj = clamp8(round_shift_signed(value, shift));
    endfunction

    function automatic logic signed [7:0] residual_res1_q30(
        input logic signed [7:0] input_value,
        input logic signed [7:0] proj_value
    );
        logic signed [63:0] scaled;
        logic signed [63:0] rounded;
        begin
            scaled = ($signed(input_value) * 64'sd343412280) + ($signed(proj_value) * 64'sd1023343639);
            if (scaled >= 0) rounded = (scaled + 64'sd536870912) >>> 30;
            else rounded = -(((-scaled) + 64'sd536870912) >>> 30);
            residual_res1_q30 = clamp8(rounded[31:0]);
        end
    endfunction

    function automatic logic signed [7:0] requant_full_ffn_mid(input logic signed [31:0] value, input integer shift);
        requant_full_ffn_mid = clamp8(round_shift_signed(value, shift));
    endfunction

    function automatic logic signed [7:0] requant_full_ffn(input logic signed [31:0] value, input integer shift);
        requant_full_ffn = clamp8(round_shift_signed(value, shift));
    endfunction

    function automatic logic [31:0] div384_u32(input logic [31:0] value);
        // 683 / 2^18 is a close multiplier approximation of 1/384.
        div384_u32 = ((value * 32'd683) >> 18);
    endfunction

    function automatic logic [31:0] square_i8_u32(input logic signed [7:0] value);
        logic signed [15:0] wide;
        logic signed [31:0] product;
        begin
            wide = value;
            product = wide * wide;
            square_i8_u32 = product[31:0];
        end
    endfunction

    function automatic logic [31:0] variance_from_sum_q12(
        input logic [31:0] sq_sum,
        input logic signed [31:0] mean
    );
        logic [31:0] sq_mean;
        logic [31:0] mean_sq;
        begin
            sq_mean = div384_u32(sq_sum);
            mean_sq = mean * mean;
            variance_from_sum_q12 = (sq_mean > mean_sq) ? (sq_mean - mean_sq + 32'd1) : 32'd1;
        end
    endfunction

    function automatic logic [15:0] ln_inv_std_piecewise_q12(input logic [31:0] var_value);
        begin
            if (var_value <= 32'd1) ln_inv_std_piecewise_q12 = 16'd4096;
            else if (var_value <= 32'd2) ln_inv_std_piecewise_q12 = 16'd2896;
            else if (var_value <= 32'd4) ln_inv_std_piecewise_q12 = 16'd2048;
            else if (var_value <= 32'd8) ln_inv_std_piecewise_q12 = 16'd1448;
            else if (var_value <= 32'd16) ln_inv_std_piecewise_q12 = 16'd1024;
            else if (var_value <= 32'd32) ln_inv_std_piecewise_q12 = 16'd724;
            else if (var_value <= 32'd64) ln_inv_std_piecewise_q12 = 16'd512;
            else if (var_value <= 32'd128) ln_inv_std_piecewise_q12 = 16'd362;
            else if (var_value <= 32'd256) ln_inv_std_piecewise_q12 = 16'd256;
            else if (var_value <= 32'd512) ln_inv_std_piecewise_q12 = 16'd181;
            else if (var_value <= 32'd1024) ln_inv_std_piecewise_q12 = 16'd128;
            else if (var_value <= 32'd2048) ln_inv_std_piecewise_q12 = 16'd91;
            else if (var_value <= 32'd4096) ln_inv_std_piecewise_q12 = 16'd64;
            else if (var_value <= 32'd8192) ln_inv_std_piecewise_q12 = 16'd45;
            else ln_inv_std_piecewise_q12 = 16'd32;
        end
    endfunction

    function automatic logic signed [7:0] ln_norm_q6(
        input logic signed [31:0] value,
        input logic signed [31:0] mean,
        input logic [15:0] inv_std_q12
    );
        logic signed [31:0] centered;
        logic signed [47:0] scaled;
        logic signed [31:0] rounded;
        begin
            centered = value - mean;
            scaled = centered * $signed({1'b0, inv_std_q12}) * 16'sd32;
            if (scaled >= 0) rounded = (scaled + 48'sd2048) >>> 12;
            else rounded = -(((-scaled) + 48'sd2048) >>> 12);
            if (rounded > 31) ln_norm_q6 = 8'sd31;
            else if (rounded < -32) ln_norm_q6 = -8'sd32;
            else ln_norm_q6 = rounded[7:0];
        end
    endfunction

    function automatic logic [19:0] attn_score_scale_q20(input logic [2:0] layer_id);
        begin
            unique case (layer_id)
                3'd0: attn_score_scale_q20 = 20'd433;
                3'd1: attn_score_scale_q20 = 20'd145;
                3'd2: attn_score_scale_q20 = 20'd260;
                3'd3: attn_score_scale_q20 = 20'd240;
                3'd4: attn_score_scale_q20 = 20'd211;
                3'd5: attn_score_scale_q20 = 20'd134;
                default: attn_score_scale_q20 = 20'd433;
            endcase
        end
    endfunction

    function automatic logic [31:0] attn_out_mult_q30(input logic [2:0] layer_id);
        begin
            unique case (layer_id)
                3'd0: attn_out_mult_q30 = 32'd1352935877;
                3'd1: attn_out_mult_q30 = 32'd1340909985;
                3'd2: attn_out_mult_q30 = 32'd891066387;
                3'd3: attn_out_mult_q30 = 32'd681624339;
                3'd4: attn_out_mult_q30 = 32'd913857528;
                3'd5: attn_out_mult_q30 = 32'd807585780;
                default: attn_out_mult_q30 = 32'd1352935877;
            endcase
        end
    endfunction

    function automatic logic [7:0] round_div_i8(
        input logic signed [31:0] value,
        input logic [15:0] denom
    );
        logic signed [31:0] rounded;
        begin
            if (denom == 16'd0) rounded = 32'sd0;
            else if (value >= 0) rounded = (value + $signed({16'd0, denom >> 1})) / $signed({16'd0, denom});
            else rounded = -(((-value) + $signed({16'd0, denom >> 1})) / $signed({16'd0, denom}));
            if (rounded > 127) round_div_i8 = 8'h7f;
            else if (rounded < -128) round_div_i8 = 8'h80;
            else round_div_i8 = rounded[7:0];
        end
    endfunction

    function automatic logic [7:0] scale_div_i8_q30(
        input logic signed [31:0] value,
        input logic [15:0] denom,
        input logic [31:0] mult_q30
    );
        logic signed [63:0] scaled;
        logic signed [63:0] divisor;
        logic signed [63:0] rounded;
        begin
            if (denom == 16'd0) rounded = 64'sd0;
            else begin
                scaled = $signed(value) * $signed({1'b0, mult_q30[30:0]});
                divisor = $signed({48'd0, denom}) <<< 30;
                if (scaled >= 0) rounded = (scaled + (divisor >>> 1)) / divisor;
                else rounded = -(((-scaled) + (divisor >>> 1)) / divisor);
            end
            if (rounded > 127) scale_div_i8_q30 = 8'h7f;
            else if (rounded < -128) scale_div_i8_q30 = 8'h80;
            else scale_div_i8_q30 = rounded[7:0];
        end
    endfunction


    always_ff @(posedge s_axi_aclk) begin
        if (wload_drain_pipe_valid)
            wq_word_mem[wload_drain_pipe_base + wload_drain_pipe_addr] <=
                wload_drain_pipe_bank ? wload_pp1_rd_data : wload_pp0_rd_data;
        wq_rd_data <= wq_word_mem[wq_rd_addr];
        q_mult_q30_data <= q_mult_q30_rom[full_attn_layer_reg*FULL_Q_OUT + q_dim];
        k_mult_q30_data <= k_mult_q30_rom[full_attn_layer_reg*FULL_Q_OUT + q_dim];
        v_mult_q30_data <= v_mult_q30_rom[full_attn_layer_reg*FULL_Q_OUT + q_dim];
        attn_proj_mult_q30_data <= attn_proj_mult_q30_rom[full_attn_layer_reg*FULL_Q_OUT + q_dim];
        ffn_mid_mult_q30_data <= ffn_mid_mult_q30_rom[full_attn_layer_reg*FULL_MLP_DIM + ffn_hidden_dim];
        ffn_mult_q30_data <= ffn_mult_q30_rom[full_attn_layer_reg*FULL_D_MODEL + q_dim];
        lm_rom_data <= lm_head_weight_rom[lm_rom_addr];
        if (ffn_mid_we) ffn_mid_mem[ffn_mid_wr_addr] <= ffn_mid_wr_data;
        ffn_mid_rd_data <= ffn_mid_mem[ffn_mid_rd_addr];
    end

    always_ff @(posedge s_axi_aclk) begin
        if (wload_fill_we && !wload_fill_bank_q)
            wload_pp0[wload_fill_addr] <= wload_fill_data;
        wload_pp0_rd_data <= wload_pp0[wload_drain_issue_addr];
    end

    always_ff @(posedge s_axi_aclk) begin
        if (wload_fill_we && wload_fill_bank_q)
            wload_pp1[wload_fill_addr] <= wload_fill_data;
        wload_pp1_rd_data <= wload_pp1[wload_drain_issue_addr];
    end

    initial begin
        $readmemh("F:/nanogpt_ZYNQ/nanogpt_ZYNQ/fpga/nano_gpt/generated/int8_alignment/hardware_params/q_mult_q30.mem", q_mult_q30_rom);
        $readmemh("F:/nanogpt_ZYNQ/nanogpt_ZYNQ/fpga/nano_gpt/generated/int8_alignment/hardware_params/k_mult_q30.mem", k_mult_q30_rom);
        $readmemh("F:/nanogpt_ZYNQ/nanogpt_ZYNQ/fpga/nano_gpt/generated/int8_alignment/hardware_params/v_mult_q30.mem", v_mult_q30_rom);
        $readmemh("F:/nanogpt_ZYNQ/nanogpt_ZYNQ/fpga/nano_gpt/generated/int8_alignment/hardware_params/attn_proj_mult_q30.mem", attn_proj_mult_q30_rom);
        $readmemh("F:/nanogpt_ZYNQ/nanogpt_ZYNQ/fpga/nano_gpt/generated/int8_alignment/hardware_params/ffn_mid_mult_q30.mem", ffn_mid_mult_q30_rom);
        $readmemh("F:/nanogpt_ZYNQ/nanogpt_ZYNQ/fpga/nano_gpt/generated/int8_alignment/hardware_params/ffn_mult_q30.mem", ffn_mult_q30_rom);
        $readmemh("F:/nanogpt_ZYNQ/nanogpt_ZYNQ/fpga/nano_gpt/generated/int8_alignment/hardware_params/lm_head_weights_padded64.mem", lm_head_weight_rom);
        $readmemh("F:/nanogpt_ZYNQ/nanogpt_ZYNQ/fpga/nano_gpt/generated/int8_alignment/hardware_params/lm_head_scale_ratio_q30.mem", lm_scale_ratio_rom);
        $readmemh("F:/nanogpt_ZYNQ/nanogpt_ZYNQ/fpga/nano_gpt/generated/int8_quality_hw_exact_s256_d384_l6/luts/attn_exp_neg_q6_q4.mem", attn_exp_q6_rom);
    end
    assign quality_hls_signature = {quality_tm_result_byte, quality_mha_result_byte, quality_ln_result_byte, quality_ge_result_byte};

    pl_uart_ps_bridge #(
        .CLK_HZ(PL_CLK_HZ),
        .BAUD(115200),
        .FIFO_DEPTH(16)
    ) u_pl_uart_ps_bridge (
        .clk(s_axi_aclk),
        .rstn(s_axi_aresetn),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .rx_data(uart_rx_data),
        .rx_valid(uart_rx_valid),
        .rx_pop(uart_rx_pop),
        .rx_count(uart_rx_count),
        .tx_data(uart_tx_data),
        .tx_push(uart_tx_push),
        .tx_ready(uart_tx_ready),
        .tx_count(uart_tx_count),
        .clear_errors(uart_clear_errors),
        .rx_overrun(uart_rx_overrun),
        .rx_framing_error(uart_rx_framing_error)
    );

    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_arready <= 1'b0;
            s_axi_rvalid <= 1'b0;
            s_axi_rresp <= 2'b00;
            s_axi_rdata <= 32'd0;
            mode_reg <= 32'd3;
            full_input_base_reg <= DEFAULT_FULL_INPUT_BASE;
            full_output_base_reg <= DEFAULT_FULL_OUTPUT_BASE;
            full_weights_base_reg <= DEFAULT_WEIGHTS_BASE;
            full_scales_base_reg <= DEFAULT_FULL_SCALES_BASE;
            full_debug_base_reg <= DEFAULT_FULL_DEBUG_BASE;
            quality_argmax_base_reg <= DEFAULT_FULL_DEBUG_BASE;
            full_q_shift_reg <= FULL_Q_SHIFT;
            full_attn_proj_shift_reg <= FULL_ATTN_PROJ_SHIFT;
            full_ffn_mid_shift_reg <= FULL_FFN_MID_SHIFT;
            full_ffn_shift_reg <= FULL_FFN_SHIFT;
            full_attn_layer_reg <= 3'd0;
            active_rows_reg <= FULL_Q_ROWS;
            row_start_reg <= '0;
            start_pulse <= 1'b0;
            clear_pulse <= 1'b0;
            uart_rx_pop <= 1'b0;
            uart_tx_push <= 1'b0;
            uart_clear_errors <= 1'b0;
            uart_tx_data <= 8'd0;
        end else begin
            start_pulse <= 1'b0;
            clear_pulse <= 1'b0;
            uart_rx_pop <= 1'b0;
            uart_tx_push <= 1'b0;
            uart_clear_errors <= 1'b0;
            if (!s_axi_awready && !s_axi_bvalid && s_axi_awvalid && s_axi_wvalid) begin
                s_axi_awready <= 1'b1;
                s_axi_wready <= 1'b1;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= 2'b00;
                unique case (s_axi_awaddr[7:2])
                    6'h00: begin
                        start_pulse <= s_axi_wdata[0];
                        clear_pulse <= s_axi_wdata[1];
                    end
                    6'h0c: mode_reg <= s_axi_wdata;
                    6'h10: full_input_base_reg <= s_axi_wdata;
                    6'h11: full_output_base_reg <= s_axi_wdata;
                    6'h12: full_weights_base_reg <= s_axi_wdata;
                    6'h13: begin
                        if (s_axi_wdata[31:5] == 27'd0) full_q_shift_reg <= s_axi_wdata[4:0];
                        else full_scales_base_reg <= s_axi_wdata;
                    end
                    6'h14: full_debug_base_reg <= s_axi_wdata;
                    6'h19: begin
                        if (s_axi_wdata[31:5] == 27'd0) full_attn_proj_shift_reg <= s_axi_wdata[4:0];
                        else quality_argmax_base_reg <= s_axi_wdata;
                    end
                    6'h1a: full_ffn_mid_shift_reg <= s_axi_wdata[4:0];
                    6'h1b: full_ffn_shift_reg <= s_axi_wdata[4:0];
                    6'h1c: full_attn_layer_reg <= s_axi_wdata[2:0];
                    6'h1d: uart_clear_errors <= s_axi_wdata[0];
                    6'h1f: begin
                        if (s_axi_wstrb[0] && uart_tx_ready) begin
                            uart_tx_data <= s_axi_wdata[7:0];
                            uart_tx_push <= 1'b1;
                        end
                    end
                    6'h20: begin
                        if (s_axi_wdata == 0) active_rows_reg <= 9'd1;
                        else if (s_axi_wdata > FULL_Q_ROWS) active_rows_reg <= FULL_Q_ROWS;
                        else active_rows_reg <= s_axi_wdata[8:0];
                    end
                    6'h21: begin
                        if (s_axi_wdata >= FULL_Q_ROWS) row_start_reg <= FULL_Q_ROWS-1;
                        else row_start_reg <= s_axi_wdata[8:0];
                    end
                    default: ;
                endcase
            end else begin
                s_axi_awready <= 1'b0;
                s_axi_wready <= 1'b0;
                if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
            end

            if (!s_axi_arready && !s_axi_rvalid && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= 2'b00;
                unique case (s_axi_araddr[7:2])
                    6'h01: s_axi_rdata <= {27'd0, 1'b1, error_latched, busy, done_latched};
                    6'h0b: s_axi_rdata <= ddr_read_count;
                    6'h0c: s_axi_rdata <= mode_reg;
                    6'h10: s_axi_rdata <= full_input_base_reg;
                    6'h11: s_axi_rdata <= full_output_base_reg;
                    6'h12: s_axi_rdata <= full_weights_base_reg;
                    6'h13: s_axi_rdata <= full_scales_base_reg;
                    6'h14: s_axi_rdata <= full_debug_base_reg;
                    6'h15: s_axi_rdata <= full_status_reg;
                    6'h16: s_axi_rdata <= full_stage_done_reg;
                    6'h17: s_axi_rdata <= full_mismatch_debug_reg;
                    6'h18: s_axi_rdata <= quality_hls_signature;
                    6'h19: s_axi_rdata <= quality_argmax_base_reg;
                    6'h1a: s_axi_rdata <= {27'd0, full_ffn_mid_shift_reg};
                    6'h1b: s_axi_rdata <= {27'd0, full_ffn_shift_reg};
                    6'h1c: s_axi_rdata <= {29'd0, full_attn_layer_reg};
                    6'h1d: s_axi_rdata <= uart_status;
                    6'h1e: begin
                        s_axi_rdata <= {24'd0, uart_rx_data};
                        if (uart_rx_valid) uart_rx_pop <= 1'b1;
                    end
                    6'h20: s_axi_rdata <= {23'd0, active_rows_reg};
                    6'h21: s_axi_rdata <= {23'd0, row_start_reg};
                    default: s_axi_rdata <= 32'd0;
                endcase
            end else begin
                s_axi_arready <= 1'b0;
                if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
            end
        end
    end

    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            state <= ST_IDLE;
            busy <= 1'b0;
            done_latched <= 1'b0;
            error_latched <= 1'b0;
            full_status_reg <= FULL_CONFIG_VERSION;
            full_stage_done_reg <= 32'd0;
            full_mismatch_debug_reg <= 32'd0;
            ddr_read_count <= 32'd0;
            ddr_error_count <= 32'd0;
            ddr_read_word <= 32'd0;
            ddr_read_resp <= 2'b00;
            word_index <= 32'd0;
            copy_word <= 32'd0;
            in_word_index <= '0;
            row <= '0;
            q_dim <= '0;
            mac_dim <= '0;
            row_sum <= '0;
            row_mean <= '0;
            row_sq_sum <= '0;
            row_sq_sum_q <= '0;
            row_inv_std_q12 <= '0;
            row_variance_q12 <= '0;
            row_sq_mean <= '0;
            row_mean_sq <= '0;
            q_acc <= '0;
            q_final_acc <= '0;
            row_sum_q <= '0;
            row_sum_q_neg <= 1'b0;
            div384_rem <= '0;
            div384_quot <= '0;
            div384_bit <= '0;
            mac_ln1_value <= '0;
            mac_weight_value <= '0;
            q_value <= '0;
            q_word_pack <= '0;
            q_write_word <= '0;
            attn_row <= '0;
            attn_head <= '0;
            attn_cand <= '0;
            attn_best_col <= '0;
            attn_word_index <= '0;
            attn_score <= '0;
            attn_next_score <= '0;
            attn_best_score <= -(32'sd1 <<< 30);
            attn_weight_scaled_diff <= '0;
            attn_weight_diff <= '0;
            attn_weight_diff_zero <= 1'b0;
            attn_read_word <= 32'd0;
            attn_read_resp <= 2'b00;
            attn_prod0 <= '0;
            attn_prod1 <= '0;
            attn_prod2 <= '0;
            attn_prod3 <= '0;
            attn_v_weight <= '0;
            attn_div_lane <= '0;
            attn_div_bit <= '0;
            attn_div_neg <= 1'b0;
            attn_div_value <= '0;
            attn_div_scaled <= '0;
            attn_div_num <= '0;
            attn_div_den <= '0;
            attn_div_rem <= '0;
            attn_div_quot <= '0;
            attn_write_word <= '0;
            proj_res_lane <= '0;
            proj_input_value <= '0;
            proj_res_value <= '0;
            proj_input_scaled <= '0;
            proj_value_scaled <= '0;
            ln2_dim <= '0;
            ln2_value <= '0;
            ln2_seg <= '0;
            ln2_hls_start_reg <= 1'b0;
            ln2_centered <= '0;
            ln2_scaled <= '0;
            ln2_rounded <= '0;
            ffn_hidden_dim <= '0;
            ffn_weight_lane <= '0;
            ffn_parallel_lane <= '0;
            ffn_acc0 <= '0;
            ffn_acc1 <= '0;
            ffn_acc2 <= '0;
            ffn_acc3 <= '0;
            ffn_acc4 <= '0;
            ffn_acc5 <= '0;
            ffn_acc6 <= '0;
            ffn_acc7 <= '0;
            ffn_acc8 <= '0;
            ffn_acc9 <= '0;
            ffn_acc10 <= '0;
            ffn_acc11 <= '0;
            ffn_acc12 <= '0;
            ffn_acc13 <= '0;
            ffn_acc14 <= '0;
            ffn_acc15 <= '0;
            ffn_acc16 <= '0;
            ffn_acc17 <= '0;
            ffn_acc18 <= '0;
            ffn_acc19 <= '0;
            ffn_acc20 <= '0;
            ffn_acc21 <= '0;
            ffn_acc22 <= '0;
            ffn_acc23 <= '0;
            ffn_acc24 <= '0;
            ffn_acc25 <= '0;
            ffn_acc26 <= '0;
            ffn_acc27 <= '0;
            ffn_acc28 <= '0;
            ffn_acc29 <= '0;
            ffn_acc30 <= '0;
            ffn_acc31 <= '0;
            ffn_final0 <= '0;
            ffn_final1 <= '0;
            ffn_final2 <= '0;
            ffn_final3 <= '0;
            ffn_final4 <= '0;
            ffn_final5 <= '0;
            ffn_final6 <= '0;
            ffn_final7 <= '0;
            ffn_final8 <= '0;
            ffn_final9 <= '0;
            ffn_final10 <= '0;
            ffn_final11 <= '0;
            ffn_final12 <= '0;
            ffn_final13 <= '0;
            ffn_final14 <= '0;
            ffn_final15 <= '0;
            ffn_final16 <= '0;
            ffn_final17 <= '0;
            ffn_final18 <= '0;
            ffn_final19 <= '0;
            ffn_final20 <= '0;
            ffn_final21 <= '0;
            ffn_final22 <= '0;
            ffn_final23 <= '0;
            ffn_mul_a <= '0;
            ffn_mul_b0 <= '0;
            ffn_mul_b1 <= '0;
            ffn_mul_b2 <= '0;
            ffn_mul_b3 <= '0;
            ffn_mul_b4 <= '0;
            ffn_mul_b5 <= '0;
            ffn_mul_b6 <= '0;
            ffn_mul_b7 <= '0;
            ffn_mul_b8 <= '0;
            ffn_mul_b9 <= '0;
            ffn_mul_b10 <= '0;
            ffn_mul_b11 <= '0;
            ffn_mul_b12 <= '0;
            ffn_mul_b13 <= '0;
            ffn_mul_b14 <= '0;
            ffn_mul_b15 <= '0;
            ffn_mul_b16 <= '0;
            ffn_mul_b17 <= '0;
            ffn_mul_b18 <= '0;
            ffn_mul_b19 <= '0;
            ffn_mul_b20 <= '0;
            ffn_mul_b21 <= '0;
            ffn_mul_b22 <= '0;
            ffn_mul_b23 <= '0;
            ffn_prod0 <= '0;
            ffn_prod1 <= '0;
            ffn_prod2 <= '0;
            ffn_prod3 <= '0;
            ffn_prod4 <= '0;
            ffn_prod5 <= '0;
            ffn_prod6 <= '0;
            ffn_prod7 <= '0;
            ffn_prod8 <= '0;
            ffn_prod9 <= '0;
            ffn_prod10 <= '0;
            ffn_prod11 <= '0;
            ffn_prod12 <= '0;
            ffn_prod13 <= '0;
            ffn_prod14 <= '0;
            ffn_prod15 <= '0;
            ffn_prod16 <= '0;
            ffn_prod17 <= '0;
            ffn_prod18 <= '0;
            ffn_prod19 <= '0;
            ffn_prod20 <= '0;
            ffn_prod21 <= '0;
            ffn_prod22 <= '0;
            ffn_prod23 <= '0;
            ffn_weight_ping <= '0;
            ffn_weight_pong <= '0;
            ffn_weight_tail <= '0;
            ffn_weight_next_ping <= '0;
            ffn_weight_next_pong <= '0;
            ffn_weight_next_tail <= '0;
            ffn_weight_beat <= '0;
            ffn_prefetch_ready <= 1'b0;
            ffn_mid_value <= '0;
            ffn_res_value <= '0;
            ffn_add_residual <= 1'b0;
            ffn_word_pack <= '0;
            ffn_write_word <= '0;
            gelu_done_delay <= '0;
            lm_vocab_idx <= '0;
            lm_best_token <= '0;
            lm_acc <= '0;
            lm_ln_value <= '0;
            lm_mac_product <= '0;
            lm_best_score <= -(64'sd1 <<< 62);
            lm_weight_value <= '0;
            lm_weight_lane <= '0;
            lm_argmax_lane <= '0;
            lm_group_idx <= '0;
            lm_scale_lane <= '0;
            lm_rom_addr <= '0;
            lm_scale_acc <= '0;
            lm_scale_factor <= '0;
            lm_scale_product <= '0;
            m_axi_ddr_araddr <= 32'd0;
            m_axi_ddr_arvalid <= 1'b0;
            m_axi_ddr_rready <= 1'b0;
            m_axi_ddr_awaddr <= 32'd0;
            m_axi_ddr_awvalid <= 1'b0;
            m_axi_ddr_wdata <= 64'd0;
            ddr_wdata_stage <= 64'd0;
            m_axi_ddr_wstrb <= 8'd0;
            m_axi_ddr_wvalid <= 1'b0;
            m_axi_ddr_wlast <= 1'b0;
            m_axi_ddr_bready <= 1'b0;
            wq_rd_addr <= '0;
            wload_fill_we <= 1'b0;
            wload_fill_bank <= 1'b0;
            wload_fill_bank_q <= 1'b0;
            wload_fill_addr <= '0;
            wload_fill_data <= '0;
            wload_fill_count <= '0;
            wload_segment_base <= '0;
            wload_burst_beat <= '0;
            wload_drain_active <= 1'b0;
            wload_drain_bank <= 1'b0;
            wload_drain_issue_addr <= '0;
            wload_drain_base <= '0;
            wload_drain_pipe_valid <= 1'b0;
            wload_drain_pipe_bank <= 1'b0;
            wload_drain_pipe_addr <= '0;
            wload_drain_pipe_base <= '0;
            ffn_mid_we <= 1'b0;
            ffn_mid_wr_addr <= '0;
            ffn_mid_wr_data <= '0;
            ffn_mid_rd_addr <= '0;
        end else begin
            m_axi_ddr_awvalid <= 1'b0;
            m_axi_ddr_wdata <= ddr_wdata_stage;
            m_axi_ddr_wvalid <= 1'b0;
            m_axi_ddr_wlast <= 1'b0;
            m_axi_ddr_bready <= 1'b0;
            wload_fill_we <= 1'b0;
            ffn_mid_we <= 1'b0;
            ln2_hls_start_reg <= 1'b0;
            ge_hls_start_reg <= 1'b0;
            wload_drain_pipe_valid <= wload_drain_active;
            if (wload_drain_active) begin
                wload_drain_pipe_bank <= wload_drain_bank;
                wload_drain_pipe_addr <= wload_drain_issue_addr;
                wload_drain_pipe_base <= wload_drain_base;
                if (wload_drain_issue_addr == WLOAD_PP_WORDS-1)
                    wload_drain_active <= 1'b0;
                else
                    wload_drain_issue_addr <= wload_drain_issue_addr + 1'b1;
            end
            if (clear_pulse) begin
                done_latched <= 1'b0;
                error_latched <= 1'b0;
            end

            unique case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start_pulse) begin
                        busy <= 1'b1;
                        done_latched <= 1'b0;
                        error_latched <= 1'b0;
                        full_stage_done_reg <= 32'd0;
                        full_mismatch_debug_reg <= 32'd0;
                        ddr_read_count <= 32'd0;
                        ddr_error_count <= 32'd0;
                        ddr_read_word <= 32'd0;
                        ddr_read_resp <= 2'b00;
                        word_index <= 32'd0;
                        in_word_index <= '0;
                        row <= '0;
                        q_dim <= '0;
                        mac_dim <= '0;
                        row_sum <= '0;
                        row_sq_sum <= '0;
                        q_acc <= '0;
                        q_final_acc <= '0;
                        q_word_pack <= '0;
                        q_write_word <= '0;
                        row_sum_q <= '0;
                        row_sum_q_neg <= 1'b0;
                        div384_rem <= '0;
                        div384_quot <= '0;
                        div384_bit <= '0;
                        mac_ln1_value <= '0;
                        mac_weight_value <= '0;
                        ffn_hidden_dim <= '0;
                        ffn_weight_lane <= '0;
                        ffn_parallel_lane <= '0;
                        ffn_acc0 <= '0;
                        ffn_acc1 <= '0;
                        ffn_acc2 <= '0;
                        ffn_acc3 <= '0;
                        ffn_acc4 <= '0;
                        ffn_acc5 <= '0;
                        ffn_acc6 <= '0;
                        ffn_acc7 <= '0;
                        ffn_acc8 <= '0;
                        ffn_acc9 <= '0;
                        ffn_acc10 <= '0;
                        ffn_acc11 <= '0;
                        ffn_acc12 <= '0;
                        ffn_acc13 <= '0;
                        ffn_acc14 <= '0;
                        ffn_acc15 <= '0;
                        ffn_acc16 <= '0;
                        ffn_acc17 <= '0;
                        ffn_acc18 <= '0;
                        ffn_acc19 <= '0;
                        ffn_acc20 <= '0;
                        ffn_acc21 <= '0;
                        ffn_acc22 <= '0;
            ffn_acc23 <= '0;
            ffn_acc24 <= '0;
            ffn_acc25 <= '0;
            ffn_acc26 <= '0;
            ffn_acc27 <= '0;
            ffn_acc28 <= '0;
            ffn_acc29 <= '0;
            ffn_acc30 <= '0;
            ffn_acc31 <= '0;
            ffn_final0 <= '0;
                        ffn_final1 <= '0;
                        ffn_final2 <= '0;
                        ffn_final3 <= '0;
                        ffn_final4 <= '0;
                        ffn_final5 <= '0;
                        ffn_final6 <= '0;
                        ffn_final7 <= '0;
                        ffn_final8 <= '0;
                        ffn_final9 <= '0;
                        ffn_final10 <= '0;
                        ffn_final11 <= '0;
                        ffn_final12 <= '0;
                        ffn_final13 <= '0;
                        ffn_final14 <= '0;
                        ffn_final15 <= '0;
                        ffn_final16 <= '0;
                        ffn_final17 <= '0;
                        ffn_final18 <= '0;
                        ffn_final19 <= '0;
                        ffn_final20 <= '0;
                        ffn_final21 <= '0;
                        ffn_final22 <= '0;
                        ffn_final23 <= '0;
                        ffn_mul_a <= '0;
                        ffn_mul_b0 <= '0;
                        ffn_mul_b1 <= '0;
                        ffn_mul_b2 <= '0;
                        ffn_mul_b3 <= '0;
                        ffn_mul_b4 <= '0;
                        ffn_mul_b5 <= '0;
                        ffn_mul_b6 <= '0;
                        ffn_mul_b7 <= '0;
                        ffn_prod0 <= '0;
                        ffn_prod1 <= '0;
                        ffn_prod2 <= '0;
                        ffn_prod3 <= '0;
                        ffn_prod4 <= '0;
                        ffn_prod5 <= '0;
                        ffn_prod6 <= '0;
                        ffn_prod7 <= '0;
                        ffn_prod8 <= '0;
                        ffn_prod9 <= '0;
                        ffn_prod10 <= '0;
                        ffn_prod11 <= '0;
                        ffn_prod12 <= '0;
                        ffn_prod13 <= '0;
                        ffn_prod14 <= '0;
                        ffn_prod15 <= '0;
                        ffn_prod16 <= '0;
                        ffn_prod17 <= '0;
                        ffn_prod18 <= '0;
                        ffn_prod19 <= '0;
                        ffn_prod20 <= '0;
                        ffn_prod21 <= '0;
                        ffn_prod22 <= '0;
                        ffn_prod23 <= '0;
                        ffn_mid_value <= '0;
                        ffn_res_value <= '0;
                        ffn_add_residual <= 1'b0;
                        ffn_word_pack <= '0;
                        ffn_write_word <= '0;
                        gelu_base <= '0;
                        gelu_idx <= '0;
                        gelu_done_delay <= '0;
                        ge_hls_start_reg <= 1'b0;
                        ln2_dim <= '0;
                        ln2_value <= '0;
                        ln2_seg <= '0;
                        ln2_hls_start_reg <= 1'b0;
                        ln2_centered <= '0;
                        ln2_scaled <= '0;
                        ln2_rounded <= '0;
                        lm_vocab_idx <= '0;
                        lm_best_token <= '0;
                        lm_acc <= '0;
                        lm_best_score <= -(64'sd1 <<< 62);
                        lm_weight_value <= '0;
                        lm_weight_lane <= '0;
                        lm_argmax_lane <= '0;
                        lm_group_idx <= '0;
                        lm_scale_lane <= '0;
                        lm_rom_addr <= '0;
                        lm_scale_acc <= '0;
                        lm_scale_factor <= '0;
                        lm_scale_product <= '0;
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b0;
                        wload_fill_bank <= 1'b0;
                        wload_fill_count <= '0;
                        wload_segment_base <= '0;
                        wload_burst_beat <= '0;
                        wload_drain_active <= 1'b0;
                        wload_drain_issue_addr <= '0;
                        if (mode_reg[10]) begin
                            full_status_reg <= FULL_CONFIG_VERSION | 32'h0000_1000;
                            row <= '0;
                            in_word_index <= '0;
                            row_sum <= '0;
                            lm_vocab_idx <= '0;
                            lm_group_idx <= '0;
                            lm_scale_lane <= '0;
                            mac_dim <= '0;
                            lm_acc <= '0;
                            lm_best_token <= '0;
                            lm_best_score <= -(64'sd1 <<< 62);
                            state <= ST_LM_LNF_REQ;
                        end else if (mode_reg[8]) begin
                            full_status_reg <= FULL_CONFIG_VERSION | 32'h0000_0800;
                            full_stage_done_reg <= 32'h0000_0100;
                            full_mismatch_debug_reg <= 32'h484c_5351; // HLSQ: quality path uses HLS-backed entry.
                            row <= '0;
                            in_word_index <= '0;
                            row_sum <= '0;
                            lm_vocab_idx <= '0;
                            mac_dim <= '0;
                            lm_acc <= '0;
                            lm_best_token <= '0;
                            lm_best_score <= -(64'sd1 <<< 62);
                            state <= ST_LM_LNF_REQ;
                        end else if (mode_reg[7]) begin
                            full_status_reg <= FULL_CONFIG_VERSION | 32'h400;
                            row <= '0;
                            in_word_index <= '0;
                            row_sum <= '0;
                            lm_vocab_idx <= '0;
                            mac_dim <= '0;
                            lm_acc <= '0;
                            lm_best_token <= '0;
                            lm_best_score <= -(64'sd1 <<< 62);
                            state <= ST_LM_LNF_REQ;
                        end else if (mode_reg[6] || mode_reg[5]) begin
                            full_status_reg <= FULL_CONFIG_VERSION | 32'h200;
                            row <= row_start_reg;
                            in_word_index <= '0;
                            ffn_hidden_dim <= '0;
                            q_dim <= '0;
                            mac_dim <= '0;
                            q_acc <= '0;
                            ffn_parallel_lane <= '0;
                            ffn_acc0 <= '0;
                            ffn_acc1 <= '0;
                            ffn_acc2 <= '0;
                            ffn_acc3 <= '0;
                            ffn_acc4 <= '0;
                            ffn_acc5 <= '0;
                            ffn_acc6 <= '0;
                            ffn_acc7 <= '0;
                            ffn_acc8 <= '0;
                            ffn_acc9 <= '0;
                            ffn_acc10 <= '0;
                            ffn_acc11 <= '0;
                            ffn_acc12 <= '0;
                            ffn_acc13 <= '0;
                            ffn_acc14 <= '0;
                            ffn_acc15 <= '0;
                            ffn_acc16 <= '0;
                            ffn_acc17 <= '0;
                            ffn_acc18 <= '0;
                            ffn_acc19 <= '0;
                            ffn_acc20 <= '0;
                            ffn_acc21 <= '0;
                            ffn_acc22 <= '0;
            ffn_acc23 <= '0;
            ffn_acc24 <= '0;
            ffn_acc25 <= '0;
            ffn_acc26 <= '0;
            ffn_acc27 <= '0;
            ffn_acc28 <= '0;
            ffn_acc29 <= '0;
            ffn_acc30 <= '0;
            ffn_acc31 <= '0;
            ffn_final0 <= '0;
                            ffn_final1 <= '0;
                            ffn_final2 <= '0;
                            ffn_final3 <= '0;
                            ffn_final4 <= '0;
                            ffn_final5 <= '0;
                        ffn_final6 <= '0;
                        ffn_final7 <= '0;
                        ffn_final8 <= '0;
                        ffn_final9 <= '0;
                        ffn_final10 <= '0;
                        ffn_final11 <= '0;
                        ffn_final12 <= '0;
                        ffn_final13 <= '0;
                        ffn_final14 <= '0;
                        ffn_final15 <= '0;
                        ffn_final16 <= '0;
                        ffn_final17 <= '0;
                        ffn_final18 <= '0;
                        ffn_final19 <= '0;
                        ffn_final20 <= '0;
                        ffn_final21 <= '0;
                        ffn_final22 <= '0;
                        ffn_final23 <= '0;
                        ffn_add_residual <= mode_reg[6];
                        ffn_weight_ping <= '0;
                        ffn_weight_pong <= '0;
                        ffn_weight_tail <= '0;
                        ffn_weight_next_ping <= '0;
                        ffn_weight_next_pong <= '0;
                        ffn_weight_next_tail <= '0;
                        ffn_weight_beat <= '0;
                        ffn_prefetch_ready <= 1'b0;
                            ffn_word_pack <= '0;
                            ffn_write_word <= '0;
                            gelu_base <= '0;
                            gelu_idx <= '0;
                            state <= ST_FFN_INPUT_REQ;
                        end else if (mode_reg[4]) begin
                            full_status_reg <= FULL_CONFIG_VERSION | 32'h100;
                            row <= row_start_reg;
                            in_word_index <= '0;
                            row_sum <= '0;
                            row_sq_sum <= '0;
                            state <= ST_LN2_INPUT_REQ;
                        end else if (mode_reg[3]) begin
                            full_status_reg <= FULL_CONFIG_VERSION | 32'h80;
                            state <= ST_PROJ_W_REQ;
                        end else if (mode_reg[2]) begin
                            full_status_reg <= FULL_CONFIG_VERSION | 32'h40;
                            attn_row <= row_start_reg;
                            attn_head <= '0;
                            attn_cand <= '0;
                            attn_best_col <= '0;
                            attn_word_index <= '0;
                            attn_score <= '0;
                            attn_next_score <= '0;
                            attn_best_score <= -(32'sd1 <<< 30);
                            state <= ST_ATTN_Q_REQ;
                        end else if (mode_reg[1]) begin
                            full_status_reg <= FULL_CONFIG_VERSION | 32'h20;
                            state <= ST_Q_W_REQ;
                        end else begin
                            full_status_reg <= FULL_CONFIG_VERSION | 32'h02;
                            state <= ST_COPY_READ_REQ;
                        end
                    end
                end

                ST_COPY_READ_REQ: begin
                    m_axi_ddr_araddr <= full_input_base_reg + (word_index << 2);
                    m_axi_ddr_arvalid <= 1'b1;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        state <= ST_COPY_READ_WAIT;
                    end
                end

                ST_COPY_READ_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        m_axi_ddr_rready <= 1'b0;
                        copy_word <= select_axi_word32(m_axi_ddr_rdata, m_axi_ddr_araddr[2]);
                        ddr_read_count <= ddr_read_count + 1'b1;
                        if (m_axi_ddr_rresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        state <= ST_COPY_WRITE_ADDR;
                    end
                end

                ST_COPY_WRITE_ADDR: begin
                    logic [31:0] byte_addr;
                    byte_addr = full_output_base_reg + (word_index << 2);
                    m_axi_ddr_awaddr <= byte_addr;
                    ddr_wdata_stage <= align_axi_wdata32(copy_word, byte_addr[2]);
                    m_axi_ddr_awvalid <= 1'b1;
                    if (m_axi_ddr_awvalid && m_axi_ddr_awready) begin
                        m_axi_ddr_awvalid <= 1'b0;
                        state <= ST_COPY_WRITE_DATA;
                    end
                end

                ST_COPY_WRITE_DATA: begin
                    m_axi_ddr_wstrb <= align_axi_wstrb4(4'hf, m_axi_ddr_awaddr[2]);
                    m_axi_ddr_wvalid <= 1'b1;
                    m_axi_ddr_wlast <= 1'b1;
                    if (m_axi_ddr_wvalid && m_axi_ddr_wready) begin
                        m_axi_ddr_wvalid <= 1'b0;
                        m_axi_ddr_wlast <= 1'b0;
                        m_axi_ddr_bready <= 1'b1;
                        state <= ST_COPY_WRITE_RESP;
                    end
                end

                ST_COPY_WRITE_RESP: begin
                    m_axi_ddr_bready <= 1'b1;
                    if (m_axi_ddr_bvalid && m_axi_ddr_bready) begin
                        m_axi_ddr_bready <= 1'b0;
                        if (m_axi_ddr_bresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        if (word_index == FULL_WORDS32-1) begin
                            full_stage_done_reg <= 32'h1;
                            full_status_reg <= FULL_CONFIG_VERSION | 32'h1;
                            state <= ST_DONE;
                        end else begin
                            word_index <= word_index + 1'b1;
                            state <= ST_COPY_READ_REQ;
                        end
                    end
                end

                ST_Q_W_REQ: begin
                    m_axi_ddr_araddr <= full_weights_base_reg + (word_index << 3);
                    m_axi_ddr_arvalid <= 1'b1;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        wload_burst_beat <= '0;
                        state <= ST_Q_W_WAIT;
                    end
                end

                ST_Q_W_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        wload_fill_we <= 1'b1;
                        wload_fill_bank_q <= wload_fill_bank;
                        wload_fill_addr <= wload_fill_count;
                        wload_fill_data <= m_axi_ddr_rdata;
                        ddr_read_count <= ddr_read_count + 1'b1;
                        if (m_axi_ddr_rresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        if (m_axi_ddr_rlast || (wload_burst_beat == WLOAD_BURST_BEATS-1)) begin
                            m_axi_ddr_rready <= 1'b0;
                            if (wload_fill_count == WLOAD_PP_WORDS-1) begin
                                wload_drain_active <= 1'b1;
                                wload_drain_bank <= wload_fill_bank;
                                wload_drain_issue_addr <= '0;
                                wload_drain_base <= wload_segment_base;
                                if (word_index == FULL_Q_WEIGHT_WORDS64-1) begin
                                    state <= ST_Q_W_DRAIN;
                                end else begin
                                    state <= ST_Q_W_SEG_DRAIN;
                                end
                            end else begin
                                word_index <= word_index + 1'b1;
                                wload_fill_count <= wload_fill_count + 1'b1;
                                state <= ST_Q_W_REQ;
                            end
                        end else begin
                            word_index <= word_index + 1'b1;
                            wload_fill_count <= wload_fill_count + 1'b1;
                            wload_burst_beat <= wload_burst_beat + 1'b1;
                        end
                    end
                end

                ST_Q_W_SEG_DRAIN: begin
                    if (wload_drain_pipe_valid && (wload_drain_pipe_addr == WLOAD_PP_WORDS-1)) begin
                        word_index <= word_index + 1'b1;
                        wload_fill_bank <= ~wload_fill_bank;
                        wload_fill_count <= '0;
                        wload_segment_base <= wload_segment_base + WLOAD_PP_WORDS;
                        state <= ST_Q_W_REQ;
                    end
                end

                ST_Q_W_DRAIN: begin
                    if (wload_drain_pipe_valid && (wload_drain_pipe_addr == WLOAD_PP_WORDS-1)) begin
                        full_stage_done_reg <= 32'h2;
                        word_index <= 32'd0;
                        row <= row_start_reg;
                        in_word_index <= '0;
                        row_sum <= '0;
                        row_sq_sum <= '0;
                        state <= ST_Q_INPUT_REQ;
                    end
                end

                ST_Q_INPUT_REQ: begin
                    m_axi_ddr_araddr <= full_input_base_reg + (row * FULL_D_MODEL) + (in_word_index << 2);
                    m_axi_ddr_arvalid <= 1'b1;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        state <= ST_Q_INPUT_WAIT;
                    end
                end

                ST_Q_INPUT_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        m_axi_ddr_rready <= 1'b0;
                        ddr_read_word <= {32'd0, select_axi_word32(m_axi_ddr_rdata, m_axi_ddr_araddr[2])};
                        ddr_read_resp <= m_axi_ddr_rresp;
                        ddr_read_count <= ddr_read_count + 1'b1;
                        state <= ST_Q_INPUT_CAPTURE;
                    end
                end

                ST_Q_INPUT_CAPTURE: begin
                    logic signed [7:0] b0;
                    logic signed [7:0] b1;
                    logic signed [7:0] b2;
                    logic signed [7:0] b3;
                    b0 = select_word_byte_signed(ddr_read_word, 2'd0);
                    b1 = select_word_byte_signed(ddr_read_word, 2'd1);
                    b2 = select_word_byte_signed(ddr_read_word, 2'd2);
                    b3 = select_word_byte_signed(ddr_read_word, 2'd3);
                        input_row[(in_word_index << 2) + 0] <= b0;
                        input_row[(in_word_index << 2) + 1] <= b1;
                        input_row[(in_word_index << 2) + 2] <= b2;
                        input_row[(in_word_index << 2) + 3] <= b3;
                        row_sum <= row_sum + $signed(b0) + $signed(b1) + $signed(b2) + $signed(b3);
                        row_sq_sum <= row_sq_sum
                            + square_i8_u32(b0)
                            + square_i8_u32(b1)
                            + square_i8_u32(b2)
                            + square_i8_u32(b3);
                    if (ddr_read_resp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        if (in_word_index == (FULL_D_MODEL/4)-1) begin
                        state <= ST_Q_MEAN_PREP;
                        end else begin
                            in_word_index <= in_word_index + 1'b1;
                            state <= ST_Q_INPUT_REQ;
                        end
                end

                ST_Q_MEAN_PREP: begin
                    row_sum_q <= row_sum;
                    row_sq_sum_q <= row_sq_sum;
                    row_sum_q_neg <= row_sum < 0;
                    div384_rem <= (row_sum < 0) ? -row_sum : row_sum;
                    div384_quot <= '0;
                    div384_bit <= 4'd8;
                    state <= ST_Q_MEAN_ITER;
                end

                ST_Q_MEAN_ITER: begin
                    logic [18:0] denom_shifted;
                    denom_shifted = 19'd384 << div384_bit;
                    if (div384_rem >= denom_shifted) begin
                        div384_rem <= div384_rem - denom_shifted;
                        div384_quot[div384_bit] <= 1'b1;
                    end
                    if (div384_bit == 0) begin
                        state <= ST_Q_MEAN_DONE;
                    end else begin
                        div384_bit <= div384_bit - 1'b1;
                    end
                end

                ST_Q_MEAN_DONE: begin
                    logic signed [31:0] mean_next;
                    mean_next = row_sum_q_neg ? -$signed({1'b0, div384_quot}) : $signed({1'b0, div384_quot});
                    row_mean <= mean_next;
                    q_dim <= '0;
                    mac_dim <= '0;
                    q_acc <= '0;
                    ffn_parallel_lane <= '0;
                    ffn_acc0 <= '0;
                    ffn_acc1 <= '0;
                    ffn_acc2 <= '0;
                    ffn_acc3 <= '0;
                    ffn_acc4 <= '0;
                    ffn_acc5 <= '0;
                    ffn_acc6 <= '0;
                    ffn_acc7 <= '0;
                    ffn_final0 <= '0;
                    ffn_final1 <= '0;
                    ffn_final2 <= '0;
                    ffn_final3 <= '0;
                    ffn_final4 <= '0;
                    ffn_final5 <= '0;
                    ffn_final6 <= '0;
                    ffn_final7 <= '0;
                    q_word_pack <= '0;
                    q_write_word <= '0;
                    state <= ST_Q_VARIANCE_MUL;
                end

                ST_Q_VARIANCE_MUL: begin
                    row_sq_mean <= div384_u32(row_sq_sum_q);
                    row_mean_sq <= $signed(row_mean) * $signed(row_mean);
                    state <= ST_Q_VARIANCE_CALC;
                end

                ST_Q_VARIANCE_CALC: begin
                    row_variance_q12 <= (row_sq_mean > row_mean_sq) ?
                                        (row_sq_mean - row_mean_sq + 32'd1) : 32'd1;
                    state <= ST_Q_INV_CALC;
                end

                ST_Q_INV_CALC: begin
                    row_inv_std_q12 <= ln_inv_std_piecewise_q12(row_variance_q12);
                    state <= ST_Q_RD;
                end

                ST_Q_RD: begin
                    wq_rd_addr <= (mac_dim * (FULL_Q_OUT/8)) + q_dim[8:3];
                    state <= ST_Q_RD_WAIT;
                end

                ST_Q_RD_WAIT: begin
                    state <= ST_Q_MAC_PREP;
                end

                ST_Q_MAC_PREP: begin
                    logic signed [7:0] mac_input;
                    if (full_debug_base_reg == 32'h12E0_0001 || full_debug_base_reg == 32'h12E0_0002 || full_debug_base_reg == 32'h12E0_0003)
                        mac_input = input_row[mac_dim];
                    else
                        mac_input = ln_norm_q6($signed(input_row[mac_dim]), $signed(row_mean), row_inv_std_q12);
                    mac_ln1_value <= mac_input;
                    ffn_mul_a <= $signed(mac_input);
                    ffn_mul_b0 <= $signed(select_dword_byte_signed(wq_rd_data, 3'd0));
                    ffn_mul_b1 <= $signed(select_dword_byte_signed(wq_rd_data, 3'd1));
                    ffn_mul_b2 <= $signed(select_dword_byte_signed(wq_rd_data, 3'd2));
                    ffn_mul_b3 <= $signed(select_dword_byte_signed(wq_rd_data, 3'd3));
                    ffn_mul_b4 <= $signed(select_dword_byte_signed(wq_rd_data, 3'd4));
                    ffn_mul_b5 <= $signed(select_dword_byte_signed(wq_rd_data, 3'd5));
                    ffn_mul_b6 <= $signed(select_dword_byte_signed(wq_rd_data, 3'd6));
                    ffn_mul_b7 <= $signed(select_dword_byte_signed(wq_rd_data, 3'd7));
                    state <= ST_Q_MUL;
                end

                ST_Q_MUL: begin
                    ffn_prod0 <= ffn_mul_a * ffn_mul_b0;
                    ffn_prod1 <= ffn_mul_a * ffn_mul_b1;
                    ffn_prod2 <= ffn_mul_a * ffn_mul_b2;
                    ffn_prod3 <= ffn_mul_a * ffn_mul_b3;
                    ffn_prod4 <= ffn_mul_a * ffn_mul_b4;
                    ffn_prod5 <= ffn_mul_a * ffn_mul_b5;
                    ffn_prod6 <= ffn_mul_a * ffn_mul_b6;
                    ffn_prod7 <= ffn_mul_a * ffn_mul_b7;
                    state <= ST_Q_MAC;
                end

                ST_Q_MAC: begin
                    logic signed [31:0] next_acc0;
                    logic signed [31:0] next_acc1;
                    logic signed [31:0] next_acc2;
                    logic signed [31:0] next_acc3;
                    logic signed [31:0] next_acc4;
                    logic signed [31:0] next_acc5;
                    logic signed [31:0] next_acc6;
                    logic signed [31:0] next_acc7;
                    next_acc0 = $signed(ffn_acc0) + $signed(ffn_prod0);
                    next_acc1 = $signed(ffn_acc1) + $signed(ffn_prod1);
                    next_acc2 = $signed(ffn_acc2) + $signed(ffn_prod2);
                    next_acc3 = $signed(ffn_acc3) + $signed(ffn_prod3);
                    next_acc4 = $signed(ffn_acc4) + $signed(ffn_prod4);
                    next_acc5 = $signed(ffn_acc5) + $signed(ffn_prod5);
                    next_acc6 = $signed(ffn_acc6) + $signed(ffn_prod6);
                    next_acc7 = $signed(ffn_acc7) + $signed(ffn_prod7);
                    if (mac_dim == FULL_D_MODEL-1) begin
                        ffn_final0 <= next_acc0;
                        ffn_final1 <= next_acc1;
                        ffn_final2 <= next_acc2;
                        ffn_final3 <= next_acc3;
                        ffn_final4 <= next_acc4;
                        ffn_final5 <= next_acc5;
                        ffn_final6 <= next_acc6;
                        ffn_final7 <= next_acc7;
                        q_acc <= '0;
                        ffn_acc0 <= '0;
                        ffn_acc1 <= '0;
                        ffn_acc2 <= '0;
                        ffn_acc3 <= '0;
                        ffn_acc4 <= '0;
                        ffn_acc5 <= '0;
                        ffn_acc6 <= '0;
                        ffn_acc7 <= '0;
                        ffn_acc4 <= '0;
                        ffn_acc5 <= '0;
                        ffn_acc6 <= '0;
                        ffn_acc7 <= '0;
                        ffn_parallel_lane <= '0;
                        state <= ST_Q_MAC_FINAL;
                    end else begin
                        ffn_acc0 <= next_acc0;
                        ffn_acc1 <= next_acc1;
                        ffn_acc2 <= next_acc2;
                        ffn_acc3 <= next_acc3;
                        ffn_acc4 <= next_acc4;
                        ffn_acc5 <= next_acc5;
                        ffn_acc6 <= next_acc6;
                        ffn_acc7 <= next_acc7;
                        mac_dim <= mac_dim + 1'b1;
                        state <= ST_Q_RD;
                    end
                end

                ST_Q_MAC_FINAL: begin
                    state <= ST_Q_QUANT;
                end

                ST_Q_QUANT: begin
                    logic signed [31:0] selected_final;
                    case (ffn_parallel_lane)
                        3'd0: selected_final = ffn_final0;
                        3'd1: selected_final = ffn_final1;
                        3'd2: selected_final = ffn_final2;
                        3'd3: selected_final = ffn_final3;
                        3'd4: selected_final = ffn_final4;
                        3'd5: selected_final = ffn_final5;
                        3'd6: selected_final = ffn_final6;
                        default: selected_final = ffn_final7;
                    endcase
                    if (full_debug_base_reg == 32'h12E0_0001) q_value <= requant_q30(selected_final, q_mult_q30_data);
                    else if (full_debug_base_reg == 32'h12E0_0002) q_value <= requant_q30(selected_final, k_mult_q30_data);
                    else if (full_debug_base_reg == 32'h12E0_0003) q_value <= requant_q30(selected_final, v_mult_q30_data);
                    else q_value <= requant_full_q(selected_final, full_q_shift_reg);
                    state <= ST_Q_WRITE_ADDR;
                end

                ST_Q_QUANT_WAIT: begin
                    state <= ST_Q_QUANT;
                end

                ST_Q_WRITE_ADDR: begin
                    logic [31:0] byte_addr;
                    logic [63:0] packed_word;
                    packed_word = q_word_pack;
                    packed_word[q_dim[2:0]*8 +: 8] = q_value;
                    if (q_dim[2:0] == 3'd7) begin
                        byte_addr = full_output_base_reg + (row * FULL_Q_OUT) + {q_dim[8:3], 3'b000};
                        q_write_word <= packed_word;
                        ddr_wdata_stage <= packed_word;
                        m_axi_ddr_awaddr <= {byte_addr[31:3], 3'b000};
                        m_axi_ddr_awvalid <= 1'b1;
                        if (m_axi_ddr_awvalid && m_axi_ddr_awready) begin
                            m_axi_ddr_awvalid <= 1'b0;
                            state <= ST_Q_WRITE_DATA;
                        end
                    end else begin
                        q_word_pack <= packed_word;
                        q_dim <= q_dim + 1'b1;
                        ffn_parallel_lane <= ffn_parallel_lane + 1'b1;
                        state <= ST_Q_QUANT_WAIT;
                    end
                end

                ST_Q_WRITE_DATA: begin
                    m_axi_ddr_wstrb <= 8'hff;
                    m_axi_ddr_wvalid <= 1'b1;
                    m_axi_ddr_wlast <= 1'b1;
                    if (m_axi_ddr_wvalid && m_axi_ddr_wready) begin
                        m_axi_ddr_wvalid <= 1'b0;
                        m_axi_ddr_wlast <= 1'b0;
                        m_axi_ddr_bready <= 1'b1;
                        state <= ST_Q_WRITE_RESP;
                    end
                end

                ST_Q_WRITE_RESP: begin
                    m_axi_ddr_bready <= 1'b1;
                    if (m_axi_ddr_bvalid && m_axi_ddr_bready) begin
                        m_axi_ddr_bready <= 1'b0;
                        if (m_axi_ddr_bresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        if (q_dim == FULL_Q_OUT-1) begin
                            if (row == active_rows_reg-1'b1) begin
                                full_stage_done_reg <= 32'h3;
                                full_status_reg <= FULL_CONFIG_VERSION | 32'h1;
                                state <= ST_DONE;
                            end else begin
                                row <= row + 1'b1;
                                in_word_index <= '0;
                                row_sum <= '0;
                                row_sq_sum <= '0;
                                ffn_parallel_lane <= '0;
                                q_word_pack <= '0;
                                state <= ST_Q_INPUT_REQ;
                            end
                        end else begin
                            q_dim <= q_dim + 1'b1;
                            mac_dim <= '0;
                            q_acc <= '0;
                            q_final_acc <= '0;
                            ffn_parallel_lane <= '0;
                            ffn_acc0 <= '0;
                            ffn_acc1 <= '0;
                            ffn_acc2 <= '0;
                            ffn_acc3 <= '0;
                            ffn_acc4 <= '0;
                            ffn_acc5 <= '0;
                            ffn_acc6 <= '0;
                            ffn_acc7 <= '0;
                            ffn_final0 <= '0;
                            ffn_final1 <= '0;
                            ffn_final2 <= '0;
                            ffn_final3 <= '0;
                            ffn_final4 <= '0;
                            ffn_final5 <= '0;
                            ffn_final6 <= '0;
                            ffn_final7 <= '0;
                            q_word_pack <= '0;
                            state <= ST_Q_RD;
                        end
                    end
                end

                ST_ATTN_Q_REQ: begin
                    m_axi_ddr_araddr <= full_weights_base_reg + (attn_row * FULL_Q_OUT) + (attn_head * 64) + (attn_word_index << 2);
                    m_axi_ddr_arvalid <= 1'b1;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        state <= ST_ATTN_Q_WAIT;
                    end
                end

                ST_ATTN_Q_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        m_axi_ddr_rready <= 1'b0;
                        attn_read_word <= select_axi_word32(m_axi_ddr_rdata, m_axi_ddr_araddr[2]);
                        attn_read_resp <= m_axi_ddr_rresp;
                        ddr_read_count <= ddr_read_count + 1'b1;
                        state <= ST_ATTN_Q_CAP;
                    end
                end

                ST_ATTN_Q_CAP: begin
                    attn_q_head[(attn_word_index << 2) + 0] <= select_word_byte_signed(attn_read_word, 2'd0);
                    attn_q_head[(attn_word_index << 2) + 1] <= select_word_byte_signed(attn_read_word, 2'd1);
                    attn_q_head[(attn_word_index << 2) + 2] <= select_word_byte_signed(attn_read_word, 2'd2);
                    attn_q_head[(attn_word_index << 2) + 3] <= select_word_byte_signed(attn_read_word, 2'd3);
                    if (attn_read_resp != 2'b00) begin
                        error_latched <= 1'b1;
                        ddr_error_count <= ddr_error_count + 1'b1;
                    end
                    if (attn_word_index == 15) begin
                        attn_word_index <= '0;
                        attn_cand <= '0;
                        attn_best_col <= '0;
                        attn_score <= '0;
                        attn_next_score <= '0;
                        attn_best_score <= -(32'sd1 <<< 30);
                        state <= ST_ATTN_SCORE_INIT;
                    end else begin
                        attn_word_index <= attn_word_index + 1'b1;
                        state <= ST_ATTN_Q_REQ;
                    end
                end

                ST_ATTN_SCORE_INIT: begin
                    attn_word_index <= '0;
                    attn_score <= '0;
                    attn_next_score <= '0;
                    state <= ST_ATTN_K_REQ;
                end

                ST_ATTN_K_REQ: begin
                    m_axi_ddr_araddr <= full_scales_base_reg + (attn_cand * FULL_Q_OUT) + (attn_head * 64) + (attn_word_index << 2);
                    m_axi_ddr_arvalid <= 1'b1;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        state <= ST_ATTN_K_WAIT;
                    end
                end

                ST_ATTN_K_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        m_axi_ddr_rready <= 1'b0;
                        attn_read_word <= select_axi_word32(m_axi_ddr_rdata, m_axi_ddr_araddr[2]);
                        attn_read_resp <= m_axi_ddr_rresp;
                        ddr_read_count <= ddr_read_count + 1'b1;
                        state <= ST_ATTN_K_MUL;
                    end
                end

                ST_ATTN_K_MUL: begin
                    attn_prod0 <= $signed(attn_q_head[(attn_word_index << 2) + 0]) * select_word_byte_signed(attn_read_word, 2'd0);
                    attn_prod1 <= $signed(attn_q_head[(attn_word_index << 2) + 1]) * select_word_byte_signed(attn_read_word, 2'd1);
                    attn_prod2 <= $signed(attn_q_head[(attn_word_index << 2) + 2]) * select_word_byte_signed(attn_read_word, 2'd2);
                    attn_prod3 <= $signed(attn_q_head[(attn_word_index << 2) + 3]) * select_word_byte_signed(attn_read_word, 2'd3);
                    if (attn_read_resp != 2'b00) begin
                        error_latched <= 1'b1;
                        ddr_error_count <= ddr_error_count + 1'b1;
                    end
                    state <= ST_ATTN_K_ACC;
                end

                ST_ATTN_K_ACC: begin
                    attn_next_score <= attn_score + $signed(attn_prod0) + $signed(attn_prod1) + $signed(attn_prod2) + $signed(attn_prod3);
                    if (attn_word_index == 15) begin
                        state <= ST_ATTN_K_FINAL;
                    end else begin
                        attn_score <= attn_score + $signed(attn_prod0) + $signed(attn_prod1) + $signed(attn_prod2) + $signed(attn_prod3);
                        attn_word_index <= attn_word_index + 1'b1;
                        state <= ST_ATTN_K_REQ;
                    end
                end

                ST_ATTN_K_FINAL: begin
                    attn_score_mem[attn_cand] <= attn_next_score;
                    if (attn_row == 8'd1 && attn_head == 3'd0 && attn_cand == 8'd1) begin
                        full_mismatch_debug_reg <= {8'hd7, attn_score_mem[0][11:0], attn_next_score[11:0]};
                    end
                    if ((attn_cand == 0) || (attn_next_score > attn_best_score)) begin
                        attn_best_score <= attn_next_score;
                        attn_best_col <= attn_cand;
                    end
                    if (attn_cand == attn_row) begin
                        attn_cand <= '0;
                        attn_den <= '0;
                        state <= ST_ATTN_WEIGHT_INIT;
                    end else begin
                        attn_cand <= attn_cand + 1'b1;
                        attn_word_index <= '0;
                        attn_score <= '0;
                        attn_next_score <= '0;
                        state <= ST_ATTN_K_REQ;
                    end
                end

                ST_ATTN_WEIGHT_INIT: begin
                    attn_cand <= '0;
                    attn_den <= '0;
                    state <= ST_ATTN_WEIGHT_CALC;
                end

                ST_ATTN_WEIGHT_CALC: begin
                    logic signed [31:0] diff_score;
                    diff_score = attn_best_score - attn_score_mem[attn_cand];
                    attn_weight_diff <= diff_score;
                    attn_weight_diff_zero <= (diff_score == 32'sd0);
                    state <= ST_ATTN_WEIGHT_MUL;
                end

                ST_ATTN_WEIGHT_MUL: begin
                    attn_weight_scaled_diff <= $unsigned(attn_weight_diff) * attn_score_scale_q20(full_attn_layer_reg);
                    state <= ST_ATTN_WEIGHT_APPLY;
                end

                ST_ATTN_WEIGHT_APPLY: begin
                    logic [63:0] scaled_idx;
                    logic [7:0] exp_idx;
                    logic [5:0] exp_value;
                    scaled_idx = (attn_weight_scaled_diff + 64'd32768) >> 16;
                    if (scaled_idx > 64'd255) exp_idx = 8'd255;
                    else exp_idx = scaled_idx[7:0];
                    exp_value = attn_weight_diff_zero ? 6'd63 : attn_exp_q6_rom[exp_idx];
                    attn_weight_mem[attn_cand] <= exp_value;
                    attn_den <= attn_den + {10'd0, exp_value};
                    if (attn_cand == attn_row) begin
                        if (1'b0 && attn_row == 8'd1 && attn_head == 3'd0) begin
                            full_mismatch_debug_reg <= {8'hd6, 2'b00, attn_weight_mem[0], 2'b00, exp_value, attn_den[7:0]};
                        end else if (attn_row == 8'd0 && attn_head == 3'd0) begin
                            full_mismatch_debug_reg <= {8'hd1, 2'b00, exp_value, attn_den + {10'd0, exp_value}};
                        end
                        attn_word_index <= '0;
                        state <= ST_ATTN_VALUE_INIT;
                    end else begin
                        attn_cand <= attn_cand + 1'b1;
                        state <= ST_ATTN_WEIGHT_CALC;
                    end
                end

                ST_ATTN_VALUE_INIT: begin
                    attn_cand <= '0;
                    attn_sum0 <= '0;
                    attn_sum1 <= '0;
                    attn_sum2 <= '0;
                    attn_sum3 <= '0;
                    attn_div_lane <= '0;
                    attn_write_word <= '0;
                    state <= ST_ATTN_V_REQ;
                end

                ST_ATTN_V_REQ: begin
                    m_axi_ddr_araddr <= full_debug_base_reg + (attn_cand * FULL_Q_OUT) + (attn_head * 64) + (attn_word_index << 2);
                    m_axi_ddr_arvalid <= 1'b1;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        state <= ST_ATTN_V_WAIT;
                    end
                end

                ST_ATTN_V_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        m_axi_ddr_rready <= 1'b0;
                        attn_read_word <= select_axi_word32(m_axi_ddr_rdata, m_axi_ddr_araddr[2]);
                        attn_read_resp <= m_axi_ddr_rresp;
                        ddr_read_count <= ddr_read_count + 1'b1;
                        state <= ST_ATTN_V_WEIGHT_LOAD;
                    end
                end

                ST_ATTN_V_WEIGHT_LOAD: begin
                    attn_v_weight <= attn_weight_mem[attn_cand];
                    state <= ST_ATTN_V_MUL;
                end

                ST_ATTN_V_MUL: begin
                    attn_prod0 <= $signed(select_word_byte_signed(attn_read_word, 2'd0)) * $signed({1'b0, attn_v_weight});
                    attn_prod1 <= $signed(select_word_byte_signed(attn_read_word, 2'd1)) * $signed({1'b0, attn_v_weight});
                    attn_prod2 <= $signed(select_word_byte_signed(attn_read_word, 2'd2)) * $signed({1'b0, attn_v_weight});
                    attn_prod3 <= $signed(select_word_byte_signed(attn_read_word, 2'd3)) * $signed({1'b0, attn_v_weight});
                    state <= ST_ATTN_V_ACCUM;
                end

                ST_ATTN_V_ACCUM: begin
                    attn_sum0 <= attn_sum0 + $signed(attn_prod0);
                    attn_sum1 <= attn_sum1 + $signed(attn_prod1);
                    attn_sum2 <= attn_sum2 + $signed(attn_prod2);
                    attn_sum3 <= attn_sum3 + $signed(attn_prod3);
                    if (attn_cand == attn_row) begin
                        if (attn_row == 8'd0 && attn_head == 3'd0 && attn_word_index == 4'd0) begin
                            full_mismatch_debug_reg <= 32'hd200_0000 | ((attn_sum0 + $signed(attn_prod0)) & 32'h00ff_ffff);
                        end
                        attn_div_lane <= '0;
                        attn_write_word <= '0;
                        state <= ST_ATTN_DIV_PREP;
                    end else begin
                        attn_cand <= attn_cand + 1'b1;
                        state <= ST_ATTN_V_REQ;
                    end
                end

                ST_ATTN_DIV_PREP: begin
                    unique case (attn_div_lane)
                        2'd0: attn_div_value <= attn_sum0;
                        2'd1: attn_div_value <= attn_sum1;
                        2'd2: attn_div_value <= attn_sum2;
                        default: attn_div_value <= attn_sum3;
                    endcase
                    if (attn_den == 16'd0) begin
                        unique case (attn_div_lane)
                            2'd0: attn_write_word[7:0] <= 8'd0;
                            2'd1: attn_write_word[15:8] <= 8'd0;
                            2'd2: attn_write_word[23:16] <= 8'd0;
                            default: attn_write_word[31:24] <= 8'd0;
                        endcase
                        if (attn_div_lane == 2'd3) begin
                            state <= ST_ATTN_WRITE_ADDR;
                        end else begin
                            attn_div_lane <= attn_div_lane + 1'b1;
                        end
                    end else begin
                        attn_div_den <= {48'd0, attn_den} << 30;
                        state <= ST_ATTN_DIV_MUL;
                    end
                end

                ST_ATTN_DIV_MUL: begin
                    attn_div_scaled <= $signed(attn_div_value)
                        * $signed(attn_out_mult_q30(full_attn_layer_reg));
                    state <= ST_ATTN_DIV_ABS;
                end

                ST_ATTN_DIV_ABS: begin
                    attn_div_neg <= (attn_div_scaled < 0);
                    attn_div_num <= ((attn_div_scaled < 0) ? $unsigned(-attn_div_scaled) : $unsigned(attn_div_scaled)) + (attn_div_den >> 1);
                    state <= ST_ATTN_DIV_SAT;
                end

                ST_ATTN_DIV_SAT: begin
                    if (attn_div_num >= (attn_div_den << 7)) begin
                        unique case (attn_div_lane)
                            2'd0: attn_write_word[7:0] <= attn_div_neg ? 8'h80 : 8'h7f;
                            2'd1: attn_write_word[15:8] <= attn_div_neg ? 8'h80 : 8'h7f;
                            2'd2: attn_write_word[23:16] <= attn_div_neg ? 8'h80 : 8'h7f;
                            default: attn_write_word[31:24] <= attn_div_neg ? 8'h80 : 8'h7f;
                        endcase
                        if (attn_div_lane == 2'd3) begin
                            state <= ST_ATTN_WRITE_ADDR;
                        end else begin
                            attn_div_lane <= attn_div_lane + 1'b1;
                            state <= ST_ATTN_DIV_PREP;
                        end
                    end else begin
                        attn_div_rem <= attn_div_num;
                        attn_div_quot <= 64'd0;
                        attn_div_bit <= 7'd6;
                        state <= ST_ATTN_DIV_ITER;
                    end
                end

                ST_ATTN_DIV_ITER: begin
                    logic [63:0] shifted_den;
                    shifted_den = attn_div_den << attn_div_bit[5:0];
                    if (attn_div_rem >= shifted_den) begin
                        attn_div_rem <= attn_div_rem - shifted_den;
                        attn_div_quot[attn_div_bit[5:0]] <= 1'b1;
                    end
                    if (attn_div_bit == 7'd0) begin
                        state <= ST_ATTN_DIV_DONE;
                    end else begin
                        attn_div_bit <= attn_div_bit - 1'b1;
                    end
                end

                ST_ATTN_DIV_DONE: begin
                    logic [7:0] div_byte;
                    if (attn_div_neg) begin
                        if (attn_div_quot > 64'd128) div_byte = 8'h80;
                        else div_byte = 8'd0 - attn_div_quot[7:0];
                    end else begin
                        if (attn_div_quot > 64'd127) div_byte = 8'h7f;
                        else div_byte = attn_div_quot[7:0];
                    end
                    unique case (attn_div_lane)
                        2'd0: attn_write_word[7:0] <= div_byte;
                        2'd1: attn_write_word[15:8] <= div_byte;
                        2'd2: attn_write_word[23:16] <= div_byte;
                        default: attn_write_word[31:24] <= div_byte;
                    endcase
                    if (attn_row == 8'd0 && attn_head == 3'd0 && attn_word_index == 4'd0 && attn_div_lane == 2'd1) begin
                        full_mismatch_debug_reg <= {8'hd4, attn_div_value[7:0], attn_div_quot[7:0], attn_den[7:0]};
                    end
                    if (attn_div_lane == 2'd3) begin
                        state <= ST_ATTN_WRITE_ADDR;
                    end else begin
                        attn_div_lane <= attn_div_lane + 1'b1;
                        state <= ST_ATTN_DIV_PREP;
                    end
                end

                ST_ATTN_WRITE_ADDR: begin
                    logic [31:0] byte_addr;
                    byte_addr = full_output_base_reg + (attn_row * FULL_Q_OUT) + (attn_head * 64) + (attn_word_index << 2);
                    m_axi_ddr_awaddr <= byte_addr;
                    ddr_wdata_stage <= align_axi_wdata32(attn_write_word, byte_addr[2]);
                    m_axi_ddr_awvalid <= 1'b1;
                    if (m_axi_ddr_awvalid && m_axi_ddr_awready) begin
                        m_axi_ddr_awvalid <= 1'b0;
                        state <= ST_ATTN_WRITE_DATA;
                    end
                end

                ST_ATTN_WRITE_DATA: begin
                    m_axi_ddr_wstrb <= align_axi_wstrb4(4'hf, m_axi_ddr_awaddr[2]);
                    m_axi_ddr_wvalid <= 1'b1;
                    m_axi_ddr_wlast <= 1'b1;
                    if (m_axi_ddr_wvalid && m_axi_ddr_wready) begin
                        m_axi_ddr_wvalid <= 1'b0;
                        m_axi_ddr_wlast <= 1'b0;
                        m_axi_ddr_bready <= 1'b1;
                        state <= ST_ATTN_WRITE_RESP;
                    end
                end

                ST_ATTN_WRITE_RESP: begin
                    m_axi_ddr_bready <= 1'b1;
                    if (m_axi_ddr_bvalid && m_axi_ddr_bready) begin
                        m_axi_ddr_bready <= 1'b0;
                        if (m_axi_ddr_bresp != 2'b00 || attn_read_resp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        if (attn_word_index == 15) begin
                            if (attn_head == 5) begin
                                if (attn_row == active_rows_reg-1'b1) begin
                                    full_stage_done_reg <= 32'h0000_0007;
                                    full_status_reg <= FULL_CONFIG_VERSION | 32'h1;
                                    state <= ST_DONE;
                                end else begin
                                    attn_row <= attn_row + 1'b1;
                                    attn_head <= '0;
                                    attn_word_index <= '0;
                                    state <= ST_ATTN_Q_REQ;
                                end
                            end else begin
                                attn_head <= attn_head + 1'b1;
                                attn_word_index <= '0;
                                state <= ST_ATTN_Q_REQ;
                            end
                        end else begin
                            attn_word_index <= attn_word_index + 1'b1;
                            state <= ST_ATTN_VALUE_INIT;
                        end
                    end
                end

                ST_PROJ_W_REQ: begin
                    m_axi_ddr_araddr <= full_weights_base_reg + (word_index << 3);
                    m_axi_ddr_arvalid <= 1'b1;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        wload_burst_beat <= '0;
                        state <= ST_PROJ_W_WAIT;
                    end
                end

                ST_PROJ_W_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        wload_fill_we <= 1'b1;
                        wload_fill_bank_q <= wload_fill_bank;
                        wload_fill_addr <= wload_fill_count;
                        wload_fill_data <= m_axi_ddr_rdata;
                        ddr_read_count <= ddr_read_count + 1'b1;
                        if (m_axi_ddr_rresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        if (m_axi_ddr_rlast || (wload_burst_beat == WLOAD_BURST_BEATS-1)) begin
                            m_axi_ddr_rready <= 1'b0;
                            if (wload_fill_count == WLOAD_PP_WORDS-1) begin
                                wload_drain_active <= 1'b1;
                                wload_drain_bank <= wload_fill_bank;
                                wload_drain_issue_addr <= '0;
                                wload_drain_base <= wload_segment_base;
                                if (word_index == FULL_Q_WEIGHT_WORDS64-1) begin
                                    state <= ST_PROJ_W_DRAIN;
                                end else begin
                                    state <= ST_PROJ_W_SEG_DRAIN;
                                end
                            end else begin
                                word_index <= word_index + 1'b1;
                                wload_fill_count <= wload_fill_count + 1'b1;
                                state <= ST_PROJ_W_REQ;
                            end
                        end else begin
                            word_index <= word_index + 1'b1;
                            wload_fill_count <= wload_fill_count + 1'b1;
                            wload_burst_beat <= wload_burst_beat + 1'b1;
                        end
                    end
                end

                ST_PROJ_W_SEG_DRAIN: begin
                    if (wload_drain_pipe_valid && (wload_drain_pipe_addr == WLOAD_PP_WORDS-1)) begin
                        word_index <= word_index + 1'b1;
                        wload_fill_bank <= ~wload_fill_bank;
                        wload_fill_count <= '0;
                        wload_segment_base <= wload_segment_base + WLOAD_PP_WORDS;
                        state <= ST_PROJ_W_REQ;
                    end
                end

                ST_PROJ_W_DRAIN: begin
                    if (wload_drain_pipe_valid && (wload_drain_pipe_addr == WLOAD_PP_WORDS-1)) begin
                        full_stage_done_reg <= 32'h0000_0008;
                        word_index <= 32'd0;
                        row <= row_start_reg;
                        in_word_index <= '0;
                        state <= ST_PROJ_INPUT_REQ;
                    end
                end

                ST_PROJ_INPUT_REQ: begin
                    m_axi_ddr_araddr <= full_input_base_reg + (row * FULL_D_MODEL) + (in_word_index << 2);
                    m_axi_ddr_arvalid <= 1'b1;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        state <= ST_PROJ_INPUT_WAIT;
                    end
                end

                ST_PROJ_INPUT_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        m_axi_ddr_rready <= 1'b0;
                        ddr_read_word <= {32'd0, select_axi_word32(m_axi_ddr_rdata, m_axi_ddr_araddr[2])};
                        ddr_read_resp <= m_axi_ddr_rresp;
                        ddr_read_count <= ddr_read_count + 1'b1;
                        state <= ST_PROJ_INPUT_CAPTURE;
                    end
                end

                ST_PROJ_INPUT_CAPTURE: begin
                    input_row[(in_word_index << 2) + 0] <= select_word_byte_signed(ddr_read_word, 2'd0);
                    input_row[(in_word_index << 2) + 1] <= select_word_byte_signed(ddr_read_word, 2'd1);
                    input_row[(in_word_index << 2) + 2] <= select_word_byte_signed(ddr_read_word, 2'd2);
                    input_row[(in_word_index << 2) + 3] <= select_word_byte_signed(ddr_read_word, 2'd3);
                    if (ddr_read_resp != 2'b00) begin
                        error_latched <= 1'b1;
                        ddr_error_count <= ddr_error_count + 1'b1;
                    end
                    if (in_word_index == (FULL_D_MODEL/4)-1) begin
                        q_dim <= '0;
                        mac_dim <= '0;
                        q_acc <= '0;
                        ffn_parallel_lane <= '0;
                        ffn_acc0 <= '0;
                        ffn_acc1 <= '0;
                        ffn_acc2 <= '0;
                        ffn_acc3 <= '0;
                        ffn_acc4 <= '0;
                        ffn_acc5 <= '0;
                        ffn_acc6 <= '0;
                        ffn_acc7 <= '0;
                        ffn_final0 <= '0;
                        ffn_final1 <= '0;
                        ffn_final2 <= '0;
                        ffn_final3 <= '0;
                        ffn_final4 <= '0;
                        ffn_final5 <= '0;
                        ffn_final6 <= '0;
                        ffn_final7 <= '0;
                        q_word_pack <= '0;
                        state <= ST_PROJ_RD;
                    end else begin
                        in_word_index <= in_word_index + 1'b1;
                        state <= ST_PROJ_INPUT_REQ;
                    end
                end

                ST_PROJ_RD: begin
                    wq_rd_addr <= (mac_dim * (FULL_Q_OUT/8)) + q_dim[8:3];
                    state <= ST_PROJ_RD_WAIT;
                end

                ST_PROJ_RD_WAIT: begin
                    state <= ST_PROJ_MAC_PREP;
                end

                ST_PROJ_MAC_PREP: begin
                    mac_ln1_value <= input_row[mac_dim];
                    ffn_mul_a <= $signed(input_row[mac_dim]);
                    ffn_mul_b0 <= $signed(select_dword_byte_signed(wq_rd_data, 3'd0));
                    ffn_mul_b1 <= $signed(select_dword_byte_signed(wq_rd_data, 3'd1));
                    ffn_mul_b2 <= $signed(select_dword_byte_signed(wq_rd_data, 3'd2));
                    ffn_mul_b3 <= $signed(select_dword_byte_signed(wq_rd_data, 3'd3));
                    ffn_mul_b4 <= $signed(select_dword_byte_signed(wq_rd_data, 3'd4));
                    ffn_mul_b5 <= $signed(select_dword_byte_signed(wq_rd_data, 3'd5));
                    ffn_mul_b6 <= $signed(select_dword_byte_signed(wq_rd_data, 3'd6));
                    ffn_mul_b7 <= $signed(select_dword_byte_signed(wq_rd_data, 3'd7));
                    state <= ST_PROJ_MUL;
                end

                ST_PROJ_MUL: begin
                    ffn_prod0 <= ffn_mul_a * ffn_mul_b0;
                    ffn_prod1 <= ffn_mul_a * ffn_mul_b1;
                    ffn_prod2 <= ffn_mul_a * ffn_mul_b2;
                    ffn_prod3 <= ffn_mul_a * ffn_mul_b3;
                    ffn_prod4 <= ffn_mul_a * ffn_mul_b4;
                    ffn_prod5 <= ffn_mul_a * ffn_mul_b5;
                    ffn_prod6 <= ffn_mul_a * ffn_mul_b6;
                    ffn_prod7 <= ffn_mul_a * ffn_mul_b7;
                    state <= ST_PROJ_MAC;
                end

                ST_PROJ_MAC: begin
                    logic signed [31:0] next_acc0;
                    logic signed [31:0] next_acc1;
                    logic signed [31:0] next_acc2;
                    logic signed [31:0] next_acc3;
                    logic signed [31:0] next_acc4;
                    logic signed [31:0] next_acc5;
                    logic signed [31:0] next_acc6;
                    logic signed [31:0] next_acc7;
                    next_acc0 = $signed(ffn_acc0) + $signed(ffn_prod0);
                    next_acc1 = $signed(ffn_acc1) + $signed(ffn_prod1);
                    next_acc2 = $signed(ffn_acc2) + $signed(ffn_prod2);
                    next_acc3 = $signed(ffn_acc3) + $signed(ffn_prod3);
                    next_acc4 = $signed(ffn_acc4) + $signed(ffn_prod4);
                    next_acc5 = $signed(ffn_acc5) + $signed(ffn_prod5);
                    next_acc6 = $signed(ffn_acc6) + $signed(ffn_prod6);
                    next_acc7 = $signed(ffn_acc7) + $signed(ffn_prod7);
                    if (mac_dim == FULL_D_MODEL-1) begin
                        ffn_final0 <= next_acc0;
                        ffn_final1 <= next_acc1;
                        ffn_final2 <= next_acc2;
                        ffn_final3 <= next_acc3;
                        ffn_final4 <= next_acc4;
                        ffn_final5 <= next_acc5;
                        ffn_final6 <= next_acc6;
                        ffn_final7 <= next_acc7;
                        q_acc <= '0;
                        ffn_acc0 <= '0;
                        ffn_acc1 <= '0;
                        ffn_acc2 <= '0;
                        ffn_acc3 <= '0;
                        ffn_acc4 <= '0;
                        ffn_acc5 <= '0;
                        ffn_acc6 <= '0;
                        ffn_acc7 <= '0;
                        ffn_acc4 <= '0;
                        ffn_acc5 <= '0;
                        ffn_acc6 <= '0;
                        ffn_acc7 <= '0;
                        ffn_parallel_lane <= '0;
                        state <= ST_PROJ_MAC_FINAL;
                    end else begin
                        ffn_acc0 <= next_acc0;
                        ffn_acc1 <= next_acc1;
                        ffn_acc2 <= next_acc2;
                        ffn_acc3 <= next_acc3;
                        ffn_acc4 <= next_acc4;
                        ffn_acc5 <= next_acc5;
                        ffn_acc6 <= next_acc6;
                        ffn_acc7 <= next_acc7;
                        mac_dim <= mac_dim + 1'b1;
                        state <= ST_PROJ_RD;
                    end
                end

                ST_PROJ_MAC_FINAL: begin
                    state <= ST_PROJ_QUANT;
                end

                ST_PROJ_QUANT: begin
                    logic signed [31:0] selected_final;
                    case (ffn_parallel_lane)
                        3'd0: selected_final = ffn_final0;
                        3'd1: selected_final = ffn_final1;
                        3'd2: selected_final = ffn_final2;
                        3'd3: selected_final = ffn_final3;
                        3'd4: selected_final = ffn_final4;
                        3'd5: selected_final = ffn_final5;
                        3'd6: selected_final = ffn_final6;
                        default: selected_final = ffn_final7;
                    endcase
                    q_value <= requant_q30(selected_final, attn_proj_mult_q30_data);
                    proj_res_lane <= q_dim[1:0];
                    state <= mode_reg[9] ? ST_PROJ_WRITE_ADDR : ST_PROJ_RES_REQ;
                end

                ST_PROJ_QUANT_WAIT: begin
                    state <= ST_PROJ_QUANT;
                end

                ST_PROJ_RES_REQ: begin
                    m_axi_ddr_araddr <= full_debug_base_reg + (row * FULL_D_MODEL) + {q_dim[8:2], 2'b00};
                    m_axi_ddr_arvalid <= 1'b1;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        state <= ST_PROJ_RES_WAIT;
                    end
                end

                ST_PROJ_RES_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        m_axi_ddr_rready <= 1'b0;
                        proj_input_value <= select_word_byte_signed(select_axi_word32(m_axi_ddr_rdata, m_axi_ddr_araddr[2]), proj_res_lane);
                        ddr_read_count <= ddr_read_count + 1'b1;
                        if (m_axi_ddr_rresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        state <= ST_PROJ_RES_MUL;
                    end
                end

                ST_PROJ_RES_MUL: begin
                    proj_input_scaled <= $signed(proj_input_value) * 64'sd343412280;
                    proj_value_scaled <= $signed(q_value) * 64'sd1023343639;
                    state <= ST_PROJ_RES_CALC;
                end

                ST_PROJ_RES_CALC: begin
                    logic signed [63:0] scaled;
                    logic signed [63:0] rounded;
                    scaled = $signed(proj_input_scaled) + $signed(proj_value_scaled);
                    if (scaled >= 0) rounded = (scaled + 64'sd536870912) >>> 30;
                    else rounded = -(((-scaled) + 64'sd536870912) >>> 30);
                    proj_res_value <= clamp8(rounded[31:0]);
                    state <= ST_PROJ_WRITE_ADDR;
                end

                ST_PROJ_WRITE_ADDR: begin
                    logic [31:0] byte_addr;
                    logic [2:0] lane;
                    logic [63:0] packed_word;
                    logic signed [7:0] res_value;
                    lane = q_dim[2:0];
                    packed_word = q_word_pack;
                    if (mode_reg[9]) begin
                        packed_word[lane*8 +: 8] = q_value;
                        if (lane == 3'd7) begin
                            byte_addr = full_output_base_reg + (row * FULL_D_MODEL) + {q_dim[8:3], 3'b000};
                            q_write_word <= packed_word;
                            ddr_wdata_stage <= packed_word;
                            m_axi_ddr_awaddr <= {byte_addr[31:3], 3'b000};
                            m_axi_ddr_awvalid <= 1'b1;
                            if (m_axi_ddr_awvalid && m_axi_ddr_awready) begin
                                m_axi_ddr_awvalid <= 1'b0;
                                state <= ST_PROJ_WRITE_DATA;
                            end
                        end else begin
                            q_word_pack <= packed_word;
                            q_dim <= q_dim + 1'b1;
                            ffn_parallel_lane <= ffn_parallel_lane + 1'b1;
                            state <= ST_PROJ_QUANT_WAIT;
                        end
                    end else begin
                        byte_addr = full_output_base_reg + (row * FULL_D_MODEL) + q_dim;
                        res_value = proj_res_value;
                        ddr_wdata_stage <= align_axi_wdata32({4{res_value}} << (lane[1:0] * 8), byte_addr[2]);
                        m_axi_ddr_awaddr <= {byte_addr[31:2], 2'b00};
                        m_axi_ddr_awvalid <= 1'b1;
                        if (m_axi_ddr_awvalid && m_axi_ddr_awready) begin
                            m_axi_ddr_awvalid <= 1'b0;
                            state <= ST_PROJ_WRITE_DATA;
                        end
                    end
                end

                ST_PROJ_WRITE_DATA: begin
                    logic [2:0] lane;
                    lane = q_dim[2:0];
                    m_axi_ddr_wstrb <= mode_reg[9] ? 8'hff :
                                       align_axi_wstrb4(4'b0001 << lane[1:0], m_axi_ddr_awaddr[2]);
                    m_axi_ddr_wvalid <= 1'b1;
                    m_axi_ddr_wlast <= 1'b1;
                    if (m_axi_ddr_wvalid && m_axi_ddr_wready) begin
                        m_axi_ddr_wvalid <= 1'b0;
                        m_axi_ddr_wlast <= 1'b0;
                        m_axi_ddr_bready <= 1'b1;
                        state <= ST_PROJ_WRITE_RESP;
                    end
                end

                ST_PROJ_WRITE_RESP: begin
                    m_axi_ddr_bready <= 1'b1;
                    if (m_axi_ddr_bvalid && m_axi_ddr_bready) begin
                        m_axi_ddr_bready <= 1'b0;
                        if (m_axi_ddr_bresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        if (q_dim == FULL_Q_OUT-1) begin
                            if (row == active_rows_reg-1'b1) begin
                                full_stage_done_reg <= 32'h0000_000f;
                                full_status_reg <= FULL_CONFIG_VERSION | 32'h1;
                                state <= ST_DONE;
                            end else begin
                                row <= row + 1'b1;
                                in_word_index <= '0;
                                ffn_parallel_lane <= '0;
                                q_word_pack <= '0;
                                state <= ST_PROJ_INPUT_REQ;
                            end
                        end else if (ffn_parallel_lane != 3'd7) begin
                            q_dim <= q_dim + 1'b1;
                            ffn_parallel_lane <= ffn_parallel_lane + 1'b1;
                            state <= ST_PROJ_QUANT_WAIT;
                        end else begin
                            q_dim <= q_dim + 1'b1;
                            mac_dim <= '0;
                            q_acc <= '0;
                            q_final_acc <= '0;
                            ffn_parallel_lane <= '0;
                            ffn_acc0 <= '0;
                            ffn_acc1 <= '0;
                            ffn_acc2 <= '0;
                            ffn_acc3 <= '0;
                            ffn_acc4 <= '0;
                            ffn_acc5 <= '0;
                            ffn_acc6 <= '0;
                            ffn_acc7 <= '0;
                            ffn_acc4 <= '0;
                            ffn_acc5 <= '0;
                            ffn_acc6 <= '0;
                            ffn_acc7 <= '0;
                            ffn_final0 <= '0;
                            ffn_final1 <= '0;
                            ffn_final2 <= '0;
                            ffn_final3 <= '0;
                            ffn_final4 <= '0;
                            ffn_final5 <= '0;
                            ffn_final6 <= '0;
                            ffn_final7 <= '0;
                            q_word_pack <= '0;
                            state <= ST_PROJ_RD;
                        end
                    end
                end

                ST_LN2_INPUT_REQ: begin
                    m_axi_ddr_araddr <= full_input_base_reg + (row * FULL_D_MODEL) + (in_word_index << 2);
                    m_axi_ddr_arvalid <= 1'b1;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        state <= ST_LN2_INPUT_WAIT;
                    end
                end

                ST_LN2_INPUT_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        m_axi_ddr_rready <= 1'b0;
                        ddr_read_word <= {32'd0, select_axi_word32(m_axi_ddr_rdata, m_axi_ddr_araddr[2])};
                        ddr_read_resp <= m_axi_ddr_rresp;
                        ddr_read_count <= ddr_read_count + 1'b1;
                        state <= ST_LN2_INPUT_CAPTURE;
                    end
                end

                ST_LN2_INPUT_CAPTURE: begin
                    logic signed [7:0] b0;
                    logic signed [7:0] b1;
                    logic signed [7:0] b2;
                    logic signed [7:0] b3;
                    b0 = select_word_byte_signed(ddr_read_word, 2'd0);
                    b1 = select_word_byte_signed(ddr_read_word, 2'd1);
                    b2 = select_word_byte_signed(ddr_read_word, 2'd2);
                    b3 = select_word_byte_signed(ddr_read_word, 2'd3);
                    input_row[(in_word_index << 2) + 0] <= b0;
                    input_row[(in_word_index << 2) + 1] <= b1;
                    input_row[(in_word_index << 2) + 2] <= b2;
                    input_row[(in_word_index << 2) + 3] <= b3;
                    row_sum <= row_sum + $signed(b0) + $signed(b1) + $signed(b2) + $signed(b3);
                    row_sq_sum <= row_sq_sum
                        + square_i8_u32(b0)
                        + square_i8_u32(b1)
                        + square_i8_u32(b2)
                        + square_i8_u32(b3);
                    if (ddr_read_resp != 2'b00) begin
                        error_latched <= 1'b1;
                        ddr_error_count <= ddr_error_count + 1'b1;
                    end
                    if (in_word_index == (FULL_D_MODEL/4)-1) begin
                        state <= ST_LN2_MEAN_PREP;
                    end else begin
                        in_word_index <= in_word_index + 1'b1;
                        state <= ST_LN2_INPUT_REQ;
                    end
                end

                ST_LN2_MEAN_PREP: begin
                    row_sum_q <= row_sum;
                    row_sq_sum_q <= row_sq_sum;
                    row_sum_q_neg <= row_sum < 0;
                    div384_rem <= (row_sum < 0) ? -row_sum : row_sum;
                    div384_quot <= '0;
                    div384_bit <= 4'd8;
                    state <= ST_LN2_MEAN_ITER;
                end

                ST_LN2_MEAN_ITER: begin
                    logic [18:0] denom_shifted;
                    denom_shifted = 19'd384 << div384_bit;
                    if (div384_rem >= denom_shifted) begin
                        div384_rem <= div384_rem - denom_shifted;
                        div384_quot[div384_bit] <= 1'b1;
                    end
                    if (div384_bit == 0) begin
                        state <= ST_LN2_MEAN_DONE;
                    end else begin
                        div384_bit <= div384_bit - 1'b1;
                    end
                end

                ST_LN2_MEAN_DONE: begin
                    logic signed [31:0] mean_next;
                    mean_next = row_sum_q_neg ? -$signed({1'b0, div384_quot}) : $signed({1'b0, div384_quot});
                    row_mean <= mean_next;
                    ln2_dim <= '0;
                    state <= ST_LN2_VARIANCE_MUL;
                end

                ST_LN2_VARIANCE_MUL: begin
                    row_sq_mean <= div384_u32(row_sq_sum_q);
                    row_mean_sq <= $signed(row_mean) * $signed(row_mean);
                    state <= ST_LN2_VARIANCE_CALC;
                end

                ST_LN2_VARIANCE_CALC: begin
                    row_variance_q12 <= (row_sq_mean > row_mean_sq) ?
                                        (row_sq_mean - row_mean_sq + 32'd1) : 32'd1;
                    state <= ST_LN2_INV_CALC;
                end

                ST_LN2_INV_CALC: begin
                    row_inv_std_q12 <= ln_inv_std_piecewise_q12(row_variance_q12);
                    if (mode_reg[7] || mode_reg[8]) begin
                        lm_vocab_idx <= '0;
                        lm_best_token <= '0;
                        lm_best_score <= -(64'sd1 <<< 62);
                        state <= ST_LM_VOCAB_INIT;
                    end else begin
                        ln2_seg <= '0;
                        state <= ST_LN2_NORM_PREP;
                    end
                end

                ST_LN2_HLS_START: begin
                    ln2_hls_start_reg <= 1'b1;
                    state <= ST_LN2_HLS_WAIT;
                end

                ST_LN2_HLS_WAIT: begin
                    if (quality_ln_done) begin
                        ln2_dim <= {ln2_seg, 6'd0};
                        state <= ST_LN2_NORM_PREP;
                    end
                end

                ST_LN2_NORM_PREP: begin
                    ln2_centered <= $signed(input_row[ln2_dim]) - $signed(row_mean);
                    state <= ST_LN2_NORM_MUL;
                end

                ST_LN2_NORM_MUL: begin
                    ln2_scaled <= ($signed(ln2_centered) * $signed({1'b0, row_inv_std_q12})) <<< 5;
                    state <= ST_LN2_NORM_ROUND;
                end

                ST_LN2_NORM_ROUND: begin
                    logic signed [31:0] rounded_next;
                    logic signed [7:0] value_next;
                    logic [1:0] lane;
                    if (ln2_scaled >= 0) rounded_next = (ln2_scaled + 48'sd2048) >>> 12;
                    else rounded_next = -(((-ln2_scaled) + 48'sd2048) >>> 12);
                    if (rounded_next > 31) value_next = 8'sd31;
                    else if (rounded_next < -32) value_next = -8'sd32;
                    else value_next = rounded_next[7:0];
                    lane = ln2_dim[1:0];
                    ln2_rounded <= rounded_next;
                    ln2_value <= value_next;
                    ddr_wdata_stage <= {4{value_next}} << (lane * 8);
                    state <= ST_LN2_WRITE_ADDR;
                end

                ST_LN2_WRITE_ADDR: begin
                    logic [31:0] byte_addr;
                    byte_addr = full_output_base_reg + (row * FULL_D_MODEL) + ln2_dim;
                    ddr_wdata_stage <= align_axi_wdata32({4{ln2_value}} << (ln2_dim[1:0] * 8), byte_addr[2]);
                    m_axi_ddr_awaddr <= {byte_addr[31:2], 2'b00};
                    m_axi_ddr_awvalid <= 1'b1;
                    if (m_axi_ddr_awvalid && m_axi_ddr_awready) begin
                        m_axi_ddr_awvalid <= 1'b0;
                        state <= ST_LN2_WRITE_DATA;
                    end
                end

                ST_LN2_WRITE_DATA: begin
                    logic [1:0] lane;
                    lane = ln2_dim[1:0];
                    m_axi_ddr_wstrb <= align_axi_wstrb4(4'b0001 << lane, m_axi_ddr_awaddr[2]);
                    m_axi_ddr_wvalid <= 1'b1;
                    m_axi_ddr_wlast <= 1'b1;
                    if (m_axi_ddr_wvalid && m_axi_ddr_wready) begin
                        m_axi_ddr_wvalid <= 1'b0;
                        m_axi_ddr_wlast <= 1'b0;
                        m_axi_ddr_bready <= 1'b1;
                        state <= ST_LN2_WRITE_RESP;
                    end
                end

                ST_LN2_WRITE_RESP: begin
                    m_axi_ddr_bready <= 1'b1;
                    if (m_axi_ddr_bvalid && m_axi_ddr_bready) begin
                        m_axi_ddr_bready <= 1'b0;
                        if (m_axi_ddr_bresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        if (ln2_dim == FULL_D_MODEL-1) begin
                            if (row == active_rows_reg-1'b1) begin
                                full_stage_done_reg <= 32'h0000_001f;
                                full_status_reg <= FULL_CONFIG_VERSION | 32'h1;
                                state <= ST_DONE;
                            end else begin
                                row <= row + 1'b1;
                                in_word_index <= '0;
                                row_sum <= '0;
                                row_sq_sum <= '0;
                                state <= ST_LN2_INPUT_REQ;
                            end
                        end else if (ln2_dim[5:0] == 6'd63) begin
                            ln2_seg <= ln2_seg + 1'b1;
                            ln2_dim <= ln2_dim + 1'b1;
                            state <= ST_LN2_NORM_PREP;
                        end else begin
                            ln2_dim <= ln2_dim + 1'b1;
                            state <= ST_LN2_NORM_PREP;
                        end
                    end
                end

                ST_FFN_INPUT_REQ: begin
                    m_axi_ddr_araddr <= full_input_base_reg + (row * FULL_D_MODEL) + (in_word_index << 2);
                    m_axi_ddr_arvalid <= 1'b1;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        state <= ST_FFN_INPUT_WAIT;
                    end
                end

                ST_FFN_INPUT_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        m_axi_ddr_rready <= 1'b0;
                        ddr_read_word <= {32'd0, select_axi_word32(m_axi_ddr_rdata, m_axi_ddr_araddr[2])};
                        ddr_read_resp <= m_axi_ddr_rresp;
                        ddr_read_count <= ddr_read_count + 1'b1;
                        state <= ST_FFN_INPUT_CAPTURE;
                    end
                end

                ST_FFN_INPUT_CAPTURE: begin
                    input_row[(in_word_index << 2) + 0] <= select_word_byte_signed(ddr_read_word, 2'd0);
                    input_row[(in_word_index << 2) + 1] <= select_word_byte_signed(ddr_read_word, 2'd1);
                    input_row[(in_word_index << 2) + 2] <= select_word_byte_signed(ddr_read_word, 2'd2);
                    input_row[(in_word_index << 2) + 3] <= select_word_byte_signed(ddr_read_word, 2'd3);
`ifdef FFN_FULL_DIAG
                    if (!ffn_add_residual) begin
                        diag_i8(fd_ln2_full, select_word_byte_signed(ddr_read_word, 2'd0));
                        diag_i8(fd_ln2_full, select_word_byte_signed(ddr_read_word, 2'd1));
                        diag_i8(fd_ln2_full, select_word_byte_signed(ddr_read_word, 2'd2));
                        diag_i8(fd_ln2_full, select_word_byte_signed(ddr_read_word, 2'd3));
                    end
`endif
                    if (ddr_read_resp != 2'b00) begin
                        error_latched <= 1'b1;
                        ddr_error_count <= ddr_error_count + 1'b1;
                    end
                    if (in_word_index == (FULL_D_MODEL/4)-1) begin
                        ffn_hidden_dim <= '0;
                        mac_dim <= '0;
                        q_acc <= '0;
                        ffn_parallel_lane <= '0;
                        ffn_acc0 <= '0;
                        ffn_acc1 <= '0;
                        ffn_acc2 <= '0;
                        ffn_acc3 <= '0;
                        ffn_acc4 <= '0;
                        ffn_acc5 <= '0;
                        ffn_acc6 <= '0;
                        ffn_acc7 <= '0;
                        ffn_acc8 <= '0;
                        ffn_acc9 <= '0;
                        ffn_acc10 <= '0;
                        ffn_acc11 <= '0;
                        ffn_acc12 <= '0;
                        ffn_acc13 <= '0;
                        ffn_acc14 <= '0;
                        ffn_acc15 <= '0;
                        ffn_acc16 <= '0;
                        ffn_acc17 <= '0;
                        ffn_acc18 <= '0;
                        ffn_acc19 <= '0;
                        ffn_acc20 <= '0;
                        ffn_acc21 <= '0;
                        ffn_acc22 <= '0;
                        ffn_acc23 <= '0;
                        ffn_acc24 <= '0;
                        ffn_acc25 <= '0;
                        ffn_acc26 <= '0;
                        ffn_acc27 <= '0;
                        ffn_acc28 <= '0;
                        ffn_acc29 <= '0;
                        ffn_acc30 <= '0;
                        ffn_acc31 <= '0;
                        state <= ST_FFN_W1_REQ;
                    end else begin
                        in_word_index <= in_word_index + 1'b1;
                        state <= ST_FFN_INPUT_REQ;
                    end
                end

                ST_FFN_W1_REQ: begin
                    logic [31:0] byte_addr;
                    byte_addr = full_weights_base_reg + (mac_dim * FULL_MLP_DIM) + ffn_hidden_dim;
                    m_axi_ddr_araddr <= {byte_addr[31:3], 3'b000};
                    m_axi_ddr_arvalid <= 1'b1;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        ffn_weight_beat <= '0;
                        ffn_prefetch_ready <= 1'b0;
                        state <= ST_FFN_W1_WAIT;
                    end
                end

                ST_FFN_W1_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        case (ffn_weight_beat)
                            2'd0: begin
                                ffn_weight_ping <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd1;
                            end
                            2'd1: begin
                                ffn_weight_pong <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd2;
                            end
                            2'd2: begin
                                ffn_weight_tail <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd3;
                            end
                            default: begin
                                ffn_weight_quad <= m_axi_ddr_rdata;
                                ffn_weight_beat <= '0;
                                m_axi_ddr_rready <= 1'b0;
                                state <= ST_FFN_W1_MUL;
                            end
                        endcase
                        ddr_read_resp <= m_axi_ddr_rresp;
                        ddr_read_count <= ddr_read_count + 1'b1;
                        if (m_axi_ddr_rresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
`ifdef FFN_FULL_DIAG
                        if (!ffn_add_residual) begin
                            diag_u32(fd_w1_addr_full, m_axi_ddr_araddr + 0);
                            diag_u32(fd_w1_addr_full, m_axi_ddr_araddr + 1);
                            diag_u32(fd_w1_addr_full, m_axi_ddr_araddr + 2);
                            diag_u32(fd_w1_addr_full, m_axi_ddr_araddr + 3);
                            diag_i8(fd_w1_weight_full, select_word_byte_signed(m_axi_ddr_rdata, 2'd0));
                            diag_i8(fd_w1_weight_full, select_word_byte_signed(m_axi_ddr_rdata, 2'd1));
                            diag_i8(fd_w1_weight_full, select_word_byte_signed(m_axi_ddr_rdata, 2'd2));
                            diag_i8(fd_w1_weight_full, select_word_byte_signed(m_axi_ddr_rdata, 2'd3));
                        end
`endif
                    end
                end

                ST_FFN_W1_MUL: begin
                    logic [31:0] next_byte_addr;
                    ffn_mul_a <= $signed(input_row[mac_dim]);
                    ffn_mul_b0 <= $signed(select_dword_byte_signed(ffn_weight_ping, 3'd0));
                    ffn_mul_b1 <= $signed(select_dword_byte_signed(ffn_weight_ping, 3'd1));
                    ffn_mul_b2 <= $signed(select_dword_byte_signed(ffn_weight_ping, 3'd2));
                    ffn_mul_b3 <= $signed(select_dword_byte_signed(ffn_weight_ping, 3'd3));
                    ffn_mul_b4 <= $signed(select_dword_byte_signed(ffn_weight_ping, 3'd4));
                    ffn_mul_b5 <= $signed(select_dword_byte_signed(ffn_weight_ping, 3'd5));
                    ffn_mul_b6 <= $signed(select_dword_byte_signed(ffn_weight_ping, 3'd6));
                    ffn_mul_b7 <= $signed(select_dword_byte_signed(ffn_weight_ping, 3'd7));
                    ffn_mul_b8 <= $signed(select_dword_byte_signed(ffn_weight_pong, 3'd0));
                    ffn_mul_b9 <= $signed(select_dword_byte_signed(ffn_weight_pong, 3'd1));
                    ffn_mul_b10 <= $signed(select_dword_byte_signed(ffn_weight_pong, 3'd2));
                    ffn_mul_b11 <= $signed(select_dword_byte_signed(ffn_weight_pong, 3'd3));
                    ffn_mul_b12 <= $signed(select_dword_byte_signed(ffn_weight_pong, 3'd4));
                    ffn_mul_b13 <= $signed(select_dword_byte_signed(ffn_weight_pong, 3'd5));
                    ffn_mul_b14 <= $signed(select_dword_byte_signed(ffn_weight_pong, 3'd6));
                    ffn_mul_b15 <= $signed(select_dword_byte_signed(ffn_weight_pong, 3'd7));
                    ffn_mul_b16 <= $signed(select_dword_byte_signed(ffn_weight_tail, 3'd0));
                    ffn_mul_b17 <= $signed(select_dword_byte_signed(ffn_weight_tail, 3'd1));
                    ffn_mul_b18 <= $signed(select_dword_byte_signed(ffn_weight_tail, 3'd2));
                    ffn_mul_b19 <= $signed(select_dword_byte_signed(ffn_weight_tail, 3'd3));
                    ffn_mul_b20 <= $signed(select_dword_byte_signed(ffn_weight_tail, 3'd4));
                    ffn_mul_b21 <= $signed(select_dword_byte_signed(ffn_weight_tail, 3'd5));
                    ffn_mul_b22 <= $signed(select_dword_byte_signed(ffn_weight_tail, 3'd6));
                    ffn_mul_b23 <= $signed(select_dword_byte_signed(ffn_weight_tail, 3'd7));
                    ffn_mul_b24 <= $signed(select_dword_byte_signed(ffn_weight_quad, 3'd0));
                    ffn_mul_b25 <= $signed(select_dword_byte_signed(ffn_weight_quad, 3'd1));
                    ffn_mul_b26 <= $signed(select_dword_byte_signed(ffn_weight_quad, 3'd2));
                    ffn_mul_b27 <= $signed(select_dword_byte_signed(ffn_weight_quad, 3'd3));
                    ffn_mul_b28 <= $signed(select_dword_byte_signed(ffn_weight_quad, 3'd4));
                    ffn_mul_b29 <= $signed(select_dword_byte_signed(ffn_weight_quad, 3'd5));
                    ffn_mul_b30 <= $signed(select_dword_byte_signed(ffn_weight_quad, 3'd6));
                    ffn_mul_b31 <= $signed(select_dword_byte_signed(ffn_weight_quad, 3'd7));
                    if (mac_dim != FULL_D_MODEL-1) begin
                        next_byte_addr = full_weights_base_reg + ((mac_dim + 1'b1) * FULL_MLP_DIM) + ffn_hidden_dim;
                        m_axi_ddr_araddr <= {next_byte_addr[31:3], 3'b000};
                        m_axi_ddr_arvalid <= 1'b1;
                        ffn_weight_beat <= '0;
                        ffn_prefetch_ready <= 1'b0;
                    end
                    state <= ST_FFN_W1_MUL_WAIT;
                end

                ST_FFN_W1_MUL_WAIT: begin
                    ffn_prod0 <= ffn_mul_a * ffn_mul_b0;
                    ffn_prod1 <= ffn_mul_a * ffn_mul_b1;
                    ffn_prod2 <= ffn_mul_a * ffn_mul_b2;
                    ffn_prod3 <= ffn_mul_a * ffn_mul_b3;
                    ffn_prod4 <= ffn_mul_a * ffn_mul_b4;
                    ffn_prod5 <= ffn_mul_a * ffn_mul_b5;
                    ffn_prod6 <= ffn_mul_a * ffn_mul_b6;
                    ffn_prod7 <= ffn_mul_a * ffn_mul_b7;
                    ffn_prod8 <= ffn_mul_a * ffn_mul_b8;
                    ffn_prod9 <= ffn_mul_a * ffn_mul_b9;
                    ffn_prod10 <= ffn_mul_a * ffn_mul_b10;
                    ffn_prod11 <= ffn_mul_a * ffn_mul_b11;
                    ffn_prod12 <= ffn_mul_a * ffn_mul_b12;
                    ffn_prod13 <= ffn_mul_a * ffn_mul_b13;
                    ffn_prod14 <= ffn_mul_a * ffn_mul_b14;
                    ffn_prod15 <= ffn_mul_a * ffn_mul_b15;
                    ffn_prod16 <= ffn_mul_a * ffn_mul_b16;
                    ffn_prod17 <= ffn_mul_a * ffn_mul_b17;
                    ffn_prod18 <= ffn_mul_a * ffn_mul_b18;
                    ffn_prod19 <= ffn_mul_a * ffn_mul_b19;
                    ffn_prod20 <= ffn_mul_a * ffn_mul_b20;
                    ffn_prod21 <= ffn_mul_a * ffn_mul_b21;
                    ffn_prod22 <= ffn_mul_a * ffn_mul_b22;
                    ffn_prod23 <= ffn_mul_a * ffn_mul_b23;
                    ffn_prod24 <= ffn_mul_a * ffn_mul_b24;
                    ffn_prod25 <= ffn_mul_a * ffn_mul_b25;
                    ffn_prod26 <= ffn_mul_a * ffn_mul_b26;
                    ffn_prod27 <= ffn_mul_a * ffn_mul_b27;
                    ffn_prod28 <= ffn_mul_a * ffn_mul_b28;
                    ffn_prod29 <= ffn_mul_a * ffn_mul_b29;
                    ffn_prod30 <= ffn_mul_a * ffn_mul_b30;
                    ffn_prod31 <= ffn_mul_a * ffn_mul_b31;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                    end
                    state <= ST_FFN_W1_MAC;
                end

                ST_FFN_W1_MAC: begin
                    logic signed [31:0] next_acc0;
                    logic signed [31:0] next_acc1;
                    logic signed [31:0] next_acc2;
                    logic signed [31:0] next_acc3;
                    logic signed [31:0] next_acc4;
                    logic signed [31:0] next_acc5;
                    logic signed [31:0] next_acc6;
                    logic signed [31:0] next_acc7;
                    logic signed [31:0] next_acc8;
                    logic signed [31:0] next_acc9;
                    logic signed [31:0] next_acc10;
                    logic signed [31:0] next_acc11;
                    logic signed [31:0] next_acc12;
                    logic signed [31:0] next_acc13;
                    logic signed [31:0] next_acc14;
                    logic signed [31:0] next_acc15;
                    logic signed [31:0] next_acc16;
                    logic signed [31:0] next_acc17;
                    logic signed [31:0] next_acc18;
                    logic signed [31:0] next_acc19;
                    logic signed [31:0] next_acc20;
                    logic signed [31:0] next_acc21;
                    logic signed [31:0] next_acc22;
                    logic signed [31:0] next_acc23;
                    logic signed [31:0] next_acc24;
                    logic signed [31:0] next_acc25;
                    logic signed [31:0] next_acc26;
                    logic signed [31:0] next_acc27;
                    logic signed [31:0] next_acc28;
                    logic signed [31:0] next_acc29;
                    logic signed [31:0] next_acc30;
                    logic signed [31:0] next_acc31;
                    next_acc0 = $signed(ffn_acc0) + $signed(ffn_prod0);
                    next_acc1 = $signed(ffn_acc1) + $signed(ffn_prod1);
                    next_acc2 = $signed(ffn_acc2) + $signed(ffn_prod2);
                    next_acc3 = $signed(ffn_acc3) + $signed(ffn_prod3);
                    next_acc4 = $signed(ffn_acc4) + $signed(ffn_prod4);
                    next_acc5 = $signed(ffn_acc5) + $signed(ffn_prod5);
                    next_acc6 = $signed(ffn_acc6) + $signed(ffn_prod6);
                    next_acc7 = $signed(ffn_acc7) + $signed(ffn_prod7);
                    next_acc8 = $signed(ffn_acc8) + $signed(ffn_prod8);
                    next_acc9 = $signed(ffn_acc9) + $signed(ffn_prod9);
                    next_acc10 = $signed(ffn_acc10) + $signed(ffn_prod10);
                    next_acc11 = $signed(ffn_acc11) + $signed(ffn_prod11);
                    next_acc12 = $signed(ffn_acc12) + $signed(ffn_prod12);
                    next_acc13 = $signed(ffn_acc13) + $signed(ffn_prod13);
                    next_acc14 = $signed(ffn_acc14) + $signed(ffn_prod14);
                    next_acc15 = $signed(ffn_acc15) + $signed(ffn_prod15);
                    next_acc16 = $signed(ffn_acc16) + $signed(ffn_prod16);
                    next_acc17 = $signed(ffn_acc17) + $signed(ffn_prod17);
                    next_acc18 = $signed(ffn_acc18) + $signed(ffn_prod18);
                    next_acc19 = $signed(ffn_acc19) + $signed(ffn_prod19);
                    next_acc20 = $signed(ffn_acc20) + $signed(ffn_prod20);
                    next_acc21 = $signed(ffn_acc21) + $signed(ffn_prod21);
                    next_acc22 = $signed(ffn_acc22) + $signed(ffn_prod22);
                    next_acc23 = $signed(ffn_acc23) + $signed(ffn_prod23);
                    next_acc24 = $signed(ffn_acc24) + $signed(ffn_prod24);
                    next_acc25 = $signed(ffn_acc25) + $signed(ffn_prod25);
                    next_acc26 = $signed(ffn_acc26) + $signed(ffn_prod26);
                    next_acc27 = $signed(ffn_acc27) + $signed(ffn_prod27);
                    next_acc28 = $signed(ffn_acc28) + $signed(ffn_prod28);
                    next_acc29 = $signed(ffn_acc29) + $signed(ffn_prod29);
                    next_acc30 = $signed(ffn_acc30) + $signed(ffn_prod30);
                    next_acc31 = $signed(ffn_acc31) + $signed(ffn_prod31);
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                    end
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        ddr_read_count <= ddr_read_count + 1'b1;
                        if (m_axi_ddr_rresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        case (ffn_weight_beat)
                            2'd0: begin
                                ffn_weight_next_ping <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd1;
                            end
                            2'd1: begin
                                ffn_weight_next_pong <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd2;
                            end
                            2'd2: begin
                                ffn_weight_next_tail <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd3;
                            end
                            default: begin
                                ffn_weight_next_quad <= m_axi_ddr_rdata;
                                ffn_weight_beat <= '0;
                                ffn_prefetch_ready <= 1'b1;
                                m_axi_ddr_rready <= 1'b0;
                            end
                        endcase
                    end
                    if (ddr_read_resp != 2'b00) begin
                        error_latched <= 1'b1;
                        ddr_error_count <= ddr_error_count + 1'b1;
                    end
                    if (mac_dim == FULL_D_MODEL-1) begin
                        ffn_final0 <= next_acc0;
                        ffn_final1 <= next_acc1;
                        ffn_final2 <= next_acc2;
                        ffn_final3 <= next_acc3;
                        ffn_final4 <= next_acc4;
                        ffn_final5 <= next_acc5;
                        ffn_final6 <= next_acc6;
                        ffn_final7 <= next_acc7;
                        ffn_final8 <= next_acc8;
                        ffn_final9 <= next_acc9;
                        ffn_final10 <= next_acc10;
                        ffn_final11 <= next_acc11;
                        ffn_final12 <= next_acc12;
                        ffn_final13 <= next_acc13;
                        ffn_final14 <= next_acc14;
                        ffn_final15 <= next_acc15;
                        ffn_final16 <= next_acc16;
                        ffn_final17 <= next_acc17;
                        ffn_final18 <= next_acc18;
                        ffn_final19 <= next_acc19;
                        ffn_final20 <= next_acc20;
                        ffn_final21 <= next_acc21;
                        ffn_final22 <= next_acc22;
                        ffn_final23 <= next_acc23;
                        ffn_final24 <= next_acc24;
                        ffn_final25 <= next_acc25;
                        ffn_final26 <= next_acc26;
                        ffn_final27 <= next_acc27;
                        ffn_final28 <= next_acc28;
                        ffn_final29 <= next_acc29;
                        ffn_final30 <= next_acc30;
                        ffn_final31 <= next_acc31;
                        ffn_acc0 <= '0;
                        ffn_acc1 <= '0;
                        ffn_acc2 <= '0;
                        ffn_acc3 <= '0;
                        ffn_acc4 <= '0;
                        ffn_acc5 <= '0;
                        ffn_acc6 <= '0;
                        ffn_acc7 <= '0;
                        ffn_acc8 <= '0;
                        ffn_acc9 <= '0;
                        ffn_acc10 <= '0;
                        ffn_acc11 <= '0;
                        ffn_acc12 <= '0;
                        ffn_acc13 <= '0;
                        ffn_acc14 <= '0;
                        ffn_acc15 <= '0;
                        ffn_acc16 <= '0;
                        ffn_acc17 <= '0;
                        ffn_acc18 <= '0;
                        ffn_acc19 <= '0;
                        ffn_acc20 <= '0;
                        ffn_acc21 <= '0;
                        ffn_acc22 <= '0;
                        ffn_acc23 <= '0;
                        ffn_acc24 <= '0;
                        ffn_acc25 <= '0;
                        ffn_acc26 <= '0;
                        ffn_acc27 <= '0;
                        ffn_acc28 <= '0;
                        ffn_acc29 <= '0;
                        ffn_acc30 <= '0;
                        ffn_acc31 <= '0;
                        ffn_parallel_lane <= '0;
`ifdef FFN_FULL_DIAG
                        if (!ffn_add_residual) begin
                            diag_u32(fd_w1_acc_full, next_acc0);
                            diag_u32(fd_w1_acc_full, next_acc1);
                            diag_u32(fd_w1_acc_full, next_acc2);
                            diag_u32(fd_w1_acc_full, next_acc3);
                        end
`endif
                        state <= ST_FFN_W1_FINAL;
                    end else begin
                        ffn_acc0 <= next_acc0;
                        ffn_acc1 <= next_acc1;
                        ffn_acc2 <= next_acc2;
                        ffn_acc3 <= next_acc3;
                        ffn_acc4 <= next_acc4;
                        ffn_acc5 <= next_acc5;
                        ffn_acc6 <= next_acc6;
                        ffn_acc7 <= next_acc7;
                        ffn_acc8 <= next_acc8;
                        ffn_acc9 <= next_acc9;
                        ffn_acc10 <= next_acc10;
                        ffn_acc11 <= next_acc11;
                        ffn_acc12 <= next_acc12;
                        ffn_acc13 <= next_acc13;
                        ffn_acc14 <= next_acc14;
                        ffn_acc15 <= next_acc15;
                        ffn_acc16 <= next_acc16;
                        ffn_acc17 <= next_acc17;
                        ffn_acc18 <= next_acc18;
                        ffn_acc19 <= next_acc19;
                        ffn_acc20 <= next_acc20;
                        ffn_acc21 <= next_acc21;
                        ffn_acc22 <= next_acc22;
                        ffn_acc23 <= next_acc23;
                        ffn_acc24 <= next_acc24;
                        ffn_acc25 <= next_acc25;
                        ffn_acc26 <= next_acc26;
                        ffn_acc27 <= next_acc27;
                        ffn_acc28 <= next_acc28;
                        ffn_acc29 <= next_acc29;
                        ffn_acc30 <= next_acc30;
                        ffn_acc31 <= next_acc31;
                        state <= ST_FFN_W1_NEXT_WAIT;
                    end
                end

                ST_FFN_W1_NEXT_WAIT: begin
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                    end
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        ddr_read_count <= ddr_read_count + 1'b1;
                        if (m_axi_ddr_rresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        case (ffn_weight_beat)
                            2'd0: begin
                                ffn_weight_next_ping <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd1;
                            end
                            2'd1: begin
                                ffn_weight_next_pong <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd2;
                            end
                            2'd2: begin
                                ffn_weight_next_tail <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd3;
                            end
                            default: begin
                                ffn_weight_next_quad <= m_axi_ddr_rdata;
                                ffn_weight_beat <= '0;
                                ffn_prefetch_ready <= 1'b1;
                                m_axi_ddr_rready <= 1'b0;
                            end
                        endcase
                    end
                    if (ffn_prefetch_ready) begin
                        ffn_weight_ping <= ffn_weight_next_ping;
                        ffn_weight_pong <= ffn_weight_next_pong;
                        ffn_weight_tail <= ffn_weight_next_tail;
                        ffn_weight_quad <= ffn_weight_next_quad;
                        ffn_prefetch_ready <= 1'b0;
                        mac_dim <= mac_dim + 1'b1;
                        state <= ST_FFN_W1_MUL;
                    end
                end

                ST_FFN_W1_FINAL: begin
                    state <= ST_FFN_W1_QUANT;
                end

                ST_FFN_W1_QUANT: begin
                    logic signed [31:0] selected_final;
                    case (ffn_parallel_lane)
                        4'd0: selected_final = ffn_final0;
                        4'd1: selected_final = ffn_final1;
                        4'd2: selected_final = ffn_final2;
                        4'd3: selected_final = ffn_final3;
                        4'd4: selected_final = ffn_final4;
                        4'd5: selected_final = ffn_final5;
                        4'd6: selected_final = ffn_final6;
                        4'd7: selected_final = ffn_final7;
                        4'd8: selected_final = ffn_final8;
                        4'd9: selected_final = ffn_final9;
                        4'd10: selected_final = ffn_final10;
                        4'd11: selected_final = ffn_final11;
                        4'd12: selected_final = ffn_final12;
                        4'd13: selected_final = ffn_final13;
                        4'd14: selected_final = ffn_final14;
                        4'd15: selected_final = ffn_final15;
                        5'd16: selected_final = ffn_final16;
                        5'd17: selected_final = ffn_final17;
                        5'd18: selected_final = ffn_final18;
                        5'd19: selected_final = ffn_final19;
                        5'd20: selected_final = ffn_final20;
                        5'd21: selected_final = ffn_final21;
                        5'd22: selected_final = ffn_final22;
                        5'd23: selected_final = ffn_final23;
                        5'd24: selected_final = ffn_final24;
                        5'd25: selected_final = ffn_final25;
                        5'd26: selected_final = ffn_final26;
                        5'd27: selected_final = ffn_final27;
                        5'd28: selected_final = ffn_final28;
                        5'd29: selected_final = ffn_final29;
                        5'd30: selected_final = ffn_final30;
                        default: selected_final = ffn_final31;
                    endcase
                    ffn_mid_we <= 1'b1;
                    ffn_mid_wr_addr <= ffn_hidden_dim;
                    ffn_mid_wr_data <= requant_q30(selected_final, ffn_mid_mult_q30_data);
`ifdef FFN_FULL_DIAG
                    if (!ffn_add_residual) diag_i8(fd_ffn_mid_full, requant_full_ffn_mid(selected_final, full_ffn_mid_shift_reg));
`endif
                    if (ffn_parallel_lane == 5'd31) begin
                        if (ffn_hidden_dim == FULL_MLP_DIM-1) begin
                            q_dim <= '0;
                            ffn_hidden_dim <= '0;
                            q_acc <= '0;
                            ffn_parallel_lane <= '0;
                            gelu_base <= '0;
                            gelu_idx <= '0;
                            ffn_mid_rd_addr <= '0;
                            state <= ST_FFN_GELU_LOAD_REQ;
                        end else begin
                            ffn_hidden_dim <= ffn_hidden_dim + 1'b1;
                            ffn_parallel_lane <= '0;
                            mac_dim <= '0;
                            ffn_acc0 <= '0;
                            ffn_acc1 <= '0;
                            ffn_acc2 <= '0;
                            ffn_acc3 <= '0;
                            ffn_acc4 <= '0;
                            ffn_acc5 <= '0;
                            ffn_acc6 <= '0;
                            ffn_acc7 <= '0;
                            ffn_acc8 <= '0;
                            ffn_acc9 <= '0;
                            ffn_acc10 <= '0;
                            ffn_acc11 <= '0;
                            ffn_acc12 <= '0;
                            ffn_acc13 <= '0;
                            ffn_acc14 <= '0;
                            ffn_acc15 <= '0;
                            ffn_acc16 <= '0;
                            ffn_acc17 <= '0;
                            ffn_acc18 <= '0;
                            ffn_acc19 <= '0;
                            ffn_acc20 <= '0;
                            ffn_acc21 <= '0;
                            ffn_acc22 <= '0;
            ffn_acc23 <= '0;
            ffn_acc24 <= '0;
            ffn_acc25 <= '0;
            ffn_acc26 <= '0;
            ffn_acc27 <= '0;
            ffn_acc28 <= '0;
            ffn_acc29 <= '0;
            ffn_acc30 <= '0;
            ffn_acc31 <= '0;
            ffn_final0 <= '0;
                            ffn_final1 <= '0;
                            ffn_final2 <= '0;
                            ffn_final3 <= '0;
                            ffn_final4 <= '0;
                            ffn_final5 <= '0;
                            ffn_final6 <= '0;
                            ffn_final7 <= '0;
                            ffn_final8 <= '0;
                            ffn_final9 <= '0;
                            ffn_final10 <= '0;
                            ffn_final11 <= '0;
                            ffn_final12 <= '0;
                            ffn_final13 <= '0;
                            ffn_final14 <= '0;
                            ffn_final15 <= '0;
                            ffn_final16 <= '0;
                            ffn_final17 <= '0;
                            ffn_final18 <= '0;
                            ffn_final19 <= '0;
                            ffn_final20 <= '0;
                            ffn_final21 <= '0;
                            ffn_final22 <= '0;
                            ffn_final23 <= '0;
                            state <= ST_FFN_W1_REQ;
                        end
                    end else begin
                        ffn_hidden_dim <= ffn_hidden_dim + 1'b1;
                        ffn_parallel_lane <= ffn_parallel_lane + 1'b1;
                        state <= ST_FFN_W1_QUANT_WAIT;
                    end
                end

                ST_FFN_W1_QUANT_WAIT: begin
                    state <= ST_FFN_W1_QUANT;
                end

                ST_FFN_GELU_LOAD_REQ: begin
                    ffn_mid_rd_addr <= gelu_base + gelu_idx;
                    state <= ST_FFN_GELU_LOAD_WAIT;
                end

                ST_FFN_GELU_LOAD_WAIT: begin
                    state <= ST_FFN_GELU_LOAD_CAP;
                end

                ST_FFN_GELU_LOAD_CAP: begin
                    gelu_x_mem[gelu_idx] <= ffn_mid_rd_data;
`ifdef FFN_FULL_DIAG
                    if (!ffn_add_residual) diag_i8(fd_gelu_in_full, ffn_mid_rd_data);
`endif
                    if (gelu_idx == 6'd63) begin
                        gelu_idx <= '0;
                        state <= ST_FFN_GELU_START;
                    end else begin
                        gelu_idx <= gelu_idx + 1'b1;
                        state <= ST_FFN_GELU_LOAD_REQ;
                    end
                end

                ST_FFN_GELU_START: begin
                    ge_hls_start_reg <= 1'b1;
                    state <= ST_FFN_GELU_WAIT;
                end

                ST_FFN_GELU_WAIT: begin
                    if (quality_ge_done) begin
                        gelu_idx <= '0;
                        gelu_done_delay <= 3'd4;
                        state <= ST_FFN_GELU_DONE_DELAY;
                    end
                end

                ST_FFN_GELU_DONE_DELAY: begin
                    if (gelu_done_delay == 3'd0) begin
                        state <= ST_FFN_GELU_WRITE;
                    end else begin
                        gelu_done_delay <= gelu_done_delay - 1'b1;
                    end
                end

                ST_FFN_GELU_WRITE: begin
                    ffn_mid_we <= 1'b1;
                    ffn_mid_wr_addr <= gelu_base + gelu_idx;
                    ffn_mid_wr_data <= quality_ge_y_flat[gelu_idx*8 +: 8];
`ifdef FFN_FULL_DIAG
                    if (!ffn_add_residual) diag_i8(fd_gelu_out_full, quality_ge_y_flat[gelu_idx*8 +: 8]);
`endif
                    if (gelu_idx == 6'd63) begin
                        if (gelu_base == FULL_MLP_DIM-64) begin
                            q_dim <= '0;
                            ffn_hidden_dim <= '0;
                            q_acc <= '0;
                            ffn_parallel_lane <= '0;
                            ffn_acc0 <= '0;
                            ffn_acc1 <= '0;
                            ffn_acc2 <= '0;
                            ffn_acc3 <= '0;
                            ffn_acc4 <= '0;
                            ffn_acc5 <= '0;
                            ffn_acc6 <= '0;
                            ffn_acc7 <= '0;
                            ffn_mid_rd_addr <= '0;
                            state <= ST_FFN_W2_RD_MID;
                        end else begin
                            gelu_base <= gelu_base + 11'd64;
                            gelu_idx <= '0;
                            state <= ST_FFN_GELU_LOAD_REQ;
                        end
                    end else begin
                        gelu_idx <= gelu_idx + 1'b1;
                    end
                end

                ST_FFN_W2_RD_MID: begin
                    ffn_mid_rd_addr <= ffn_hidden_dim;
                    state <= ST_FFN_W2_W_REQ;
                end

                ST_FFN_W2_W_REQ: begin
                    logic [31:0] byte_addr;
                    byte_addr = full_weights_base_reg + FULL_W1_BYTES + (ffn_hidden_dim * FULL_D_MODEL) + q_dim;
                    m_axi_ddr_araddr <= {byte_addr[31:3], 3'b000};
                    m_axi_ddr_arvalid <= 1'b1;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        ffn_weight_beat <= '0;
                        ffn_prefetch_ready <= 1'b0;
                        state <= ST_FFN_W2_W_WAIT;
                    end
                end

                ST_FFN_W2_W_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        case (ffn_weight_beat)
                            2'd0: begin
                                ffn_weight_ping <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd1;
                            end
                            2'd1: begin
                                ffn_weight_pong <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd2;
                            end
                            2'd2: begin
                                ffn_weight_tail <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd3;
                            end
                            default: begin
                                ffn_weight_quad <= m_axi_ddr_rdata;
                                ffn_weight_beat <= '0;
                                m_axi_ddr_rready <= 1'b0;
                                state <= ST_FFN_W2_MUL;
                            end
                        endcase
                        ddr_read_resp <= m_axi_ddr_rresp;
                        ddr_read_count <= ddr_read_count + 1'b1;
                        if (m_axi_ddr_rresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
`ifdef FFN_FULL_DIAG
                        if (!ffn_add_residual) begin
                            diag_u32(fd_w2_addr_full, m_axi_ddr_araddr + 0);
                            diag_u32(fd_w2_addr_full, m_axi_ddr_araddr + 1);
                            diag_u32(fd_w2_addr_full, m_axi_ddr_araddr + 2);
                            diag_u32(fd_w2_addr_full, m_axi_ddr_araddr + 3);
                            diag_i8(fd_w2_weight_full, select_word_byte_signed(m_axi_ddr_rdata, 2'd0));
                            diag_i8(fd_w2_weight_full, select_word_byte_signed(m_axi_ddr_rdata, 2'd1));
                            diag_i8(fd_w2_weight_full, select_word_byte_signed(m_axi_ddr_rdata, 2'd2));
                            diag_i8(fd_w2_weight_full, select_word_byte_signed(m_axi_ddr_rdata, 2'd3));
                        end
`endif
                    end
                end

                ST_FFN_W2_MUL: begin
                    logic [31:0] next_byte_addr;
                    ffn_mul_a <= $signed(ffn_mid_rd_data);
                    ffn_mul_b0 <= $signed(select_dword_byte_signed(ffn_weight_ping, 3'd0));
                    ffn_mul_b1 <= $signed(select_dword_byte_signed(ffn_weight_ping, 3'd1));
                    ffn_mul_b2 <= $signed(select_dword_byte_signed(ffn_weight_ping, 3'd2));
                    ffn_mul_b3 <= $signed(select_dword_byte_signed(ffn_weight_ping, 3'd3));
                    ffn_mul_b4 <= $signed(select_dword_byte_signed(ffn_weight_ping, 3'd4));
                    ffn_mul_b5 <= $signed(select_dword_byte_signed(ffn_weight_ping, 3'd5));
                    ffn_mul_b6 <= $signed(select_dword_byte_signed(ffn_weight_ping, 3'd6));
                    ffn_mul_b7 <= $signed(select_dword_byte_signed(ffn_weight_ping, 3'd7));
                    ffn_mul_b8 <= $signed(select_dword_byte_signed(ffn_weight_pong, 3'd0));
                    ffn_mul_b9 <= $signed(select_dword_byte_signed(ffn_weight_pong, 3'd1));
                    ffn_mul_b10 <= $signed(select_dword_byte_signed(ffn_weight_pong, 3'd2));
                    ffn_mul_b11 <= $signed(select_dword_byte_signed(ffn_weight_pong, 3'd3));
                    ffn_mul_b12 <= $signed(select_dword_byte_signed(ffn_weight_pong, 3'd4));
                    ffn_mul_b13 <= $signed(select_dword_byte_signed(ffn_weight_pong, 3'd5));
                    ffn_mul_b14 <= $signed(select_dword_byte_signed(ffn_weight_pong, 3'd6));
                    ffn_mul_b15 <= $signed(select_dword_byte_signed(ffn_weight_pong, 3'd7));
                    ffn_mul_b16 <= $signed(select_dword_byte_signed(ffn_weight_tail, 3'd0));
                    ffn_mul_b17 <= $signed(select_dword_byte_signed(ffn_weight_tail, 3'd1));
                    ffn_mul_b18 <= $signed(select_dword_byte_signed(ffn_weight_tail, 3'd2));
                    ffn_mul_b19 <= $signed(select_dword_byte_signed(ffn_weight_tail, 3'd3));
                    ffn_mul_b20 <= $signed(select_dword_byte_signed(ffn_weight_tail, 3'd4));
                    ffn_mul_b21 <= $signed(select_dword_byte_signed(ffn_weight_tail, 3'd5));
                    ffn_mul_b22 <= $signed(select_dword_byte_signed(ffn_weight_tail, 3'd6));
                    ffn_mul_b23 <= $signed(select_dword_byte_signed(ffn_weight_tail, 3'd7));
                    ffn_mul_b24 <= $signed(select_dword_byte_signed(ffn_weight_quad, 3'd0));
                    ffn_mul_b25 <= $signed(select_dword_byte_signed(ffn_weight_quad, 3'd1));
                    ffn_mul_b26 <= $signed(select_dword_byte_signed(ffn_weight_quad, 3'd2));
                    ffn_mul_b27 <= $signed(select_dword_byte_signed(ffn_weight_quad, 3'd3));
                    ffn_mul_b28 <= $signed(select_dword_byte_signed(ffn_weight_quad, 3'd4));
                    ffn_mul_b29 <= $signed(select_dword_byte_signed(ffn_weight_quad, 3'd5));
                    ffn_mul_b30 <= $signed(select_dword_byte_signed(ffn_weight_quad, 3'd6));
                    ffn_mul_b31 <= $signed(select_dword_byte_signed(ffn_weight_quad, 3'd7));
                    if (ffn_hidden_dim != FULL_MLP_DIM-1) begin
                        next_byte_addr = full_weights_base_reg + FULL_W1_BYTES +
                                         ((ffn_hidden_dim + 1'b1) * FULL_D_MODEL) + q_dim;
                        m_axi_ddr_araddr <= {next_byte_addr[31:3], 3'b000};
                        m_axi_ddr_arvalid <= 1'b1;
                        ffn_weight_beat <= '0;
                        ffn_prefetch_ready <= 1'b0;
                    end
                    state <= ST_FFN_W2_MUL_WAIT;
                end

                ST_FFN_W2_MUL_WAIT: begin
                    ffn_prod0 <= ffn_mul_a * ffn_mul_b0;
                    ffn_prod1 <= ffn_mul_a * ffn_mul_b1;
                    ffn_prod2 <= ffn_mul_a * ffn_mul_b2;
                    ffn_prod3 <= ffn_mul_a * ffn_mul_b3;
                    ffn_prod4 <= ffn_mul_a * ffn_mul_b4;
                    ffn_prod5 <= ffn_mul_a * ffn_mul_b5;
                    ffn_prod6 <= ffn_mul_a * ffn_mul_b6;
                    ffn_prod7 <= ffn_mul_a * ffn_mul_b7;
                    ffn_prod8 <= ffn_mul_a * ffn_mul_b8;
                    ffn_prod9 <= ffn_mul_a * ffn_mul_b9;
                    ffn_prod10 <= ffn_mul_a * ffn_mul_b10;
                    ffn_prod11 <= ffn_mul_a * ffn_mul_b11;
                    ffn_prod12 <= ffn_mul_a * ffn_mul_b12;
                    ffn_prod13 <= ffn_mul_a * ffn_mul_b13;
                    ffn_prod14 <= ffn_mul_a * ffn_mul_b14;
                    ffn_prod15 <= ffn_mul_a * ffn_mul_b15;
                    ffn_prod16 <= ffn_mul_a * ffn_mul_b16;
                    ffn_prod17 <= ffn_mul_a * ffn_mul_b17;
                    ffn_prod18 <= ffn_mul_a * ffn_mul_b18;
                    ffn_prod19 <= ffn_mul_a * ffn_mul_b19;
                    ffn_prod20 <= ffn_mul_a * ffn_mul_b20;
                    ffn_prod21 <= ffn_mul_a * ffn_mul_b21;
                    ffn_prod22 <= ffn_mul_a * ffn_mul_b22;
                    ffn_prod23 <= ffn_mul_a * ffn_mul_b23;
                    ffn_prod24 <= ffn_mul_a * ffn_mul_b24;
                    ffn_prod25 <= ffn_mul_a * ffn_mul_b25;
                    ffn_prod26 <= ffn_mul_a * ffn_mul_b26;
                    ffn_prod27 <= ffn_mul_a * ffn_mul_b27;
                    ffn_prod28 <= ffn_mul_a * ffn_mul_b28;
                    ffn_prod29 <= ffn_mul_a * ffn_mul_b29;
                    ffn_prod30 <= ffn_mul_a * ffn_mul_b30;
                    ffn_prod31 <= ffn_mul_a * ffn_mul_b31;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                    end
                    state <= ST_FFN_W2_MAC;
                end

                ST_FFN_W2_MAC: begin
                    logic signed [31:0] next_acc0;
                    logic signed [31:0] next_acc1;
                    logic signed [31:0] next_acc2;
                    logic signed [31:0] next_acc3;
                    logic signed [31:0] next_acc4;
                    logic signed [31:0] next_acc5;
                    logic signed [31:0] next_acc6;
                    logic signed [31:0] next_acc7;
                    logic signed [31:0] next_acc8;
                    logic signed [31:0] next_acc9;
                    logic signed [31:0] next_acc10;
                    logic signed [31:0] next_acc11;
                    logic signed [31:0] next_acc12;
                    logic signed [31:0] next_acc13;
                    logic signed [31:0] next_acc14;
                    logic signed [31:0] next_acc15;
                    logic signed [31:0] next_acc16;
                    logic signed [31:0] next_acc17;
                    logic signed [31:0] next_acc18;
                    logic signed [31:0] next_acc19;
                    logic signed [31:0] next_acc20;
                    logic signed [31:0] next_acc21;
                    logic signed [31:0] next_acc22;
                    logic signed [31:0] next_acc23;
                    logic signed [31:0] next_acc24;
                    logic signed [31:0] next_acc25;
                    logic signed [31:0] next_acc26;
                    logic signed [31:0] next_acc27;
                    logic signed [31:0] next_acc28;
                    logic signed [31:0] next_acc29;
                    logic signed [31:0] next_acc30;
                    logic signed [31:0] next_acc31;
                    next_acc0 = $signed(ffn_acc0) + $signed(ffn_prod0);
                    next_acc1 = $signed(ffn_acc1) + $signed(ffn_prod1);
                    next_acc2 = $signed(ffn_acc2) + $signed(ffn_prod2);
                    next_acc3 = $signed(ffn_acc3) + $signed(ffn_prod3);
                    next_acc4 = $signed(ffn_acc4) + $signed(ffn_prod4);
                    next_acc5 = $signed(ffn_acc5) + $signed(ffn_prod5);
                    next_acc6 = $signed(ffn_acc6) + $signed(ffn_prod6);
                    next_acc7 = $signed(ffn_acc7) + $signed(ffn_prod7);
                    next_acc8 = $signed(ffn_acc8) + $signed(ffn_prod8);
                    next_acc9 = $signed(ffn_acc9) + $signed(ffn_prod9);
                    next_acc10 = $signed(ffn_acc10) + $signed(ffn_prod10);
                    next_acc11 = $signed(ffn_acc11) + $signed(ffn_prod11);
                    next_acc12 = $signed(ffn_acc12) + $signed(ffn_prod12);
                    next_acc13 = $signed(ffn_acc13) + $signed(ffn_prod13);
                    next_acc14 = $signed(ffn_acc14) + $signed(ffn_prod14);
                    next_acc15 = $signed(ffn_acc15) + $signed(ffn_prod15);
                    next_acc16 = $signed(ffn_acc16) + $signed(ffn_prod16);
                    next_acc17 = $signed(ffn_acc17) + $signed(ffn_prod17);
                    next_acc18 = $signed(ffn_acc18) + $signed(ffn_prod18);
                    next_acc19 = $signed(ffn_acc19) + $signed(ffn_prod19);
                    next_acc20 = $signed(ffn_acc20) + $signed(ffn_prod20);
                    next_acc21 = $signed(ffn_acc21) + $signed(ffn_prod21);
                    next_acc22 = $signed(ffn_acc22) + $signed(ffn_prod22);
                    next_acc23 = $signed(ffn_acc23) + $signed(ffn_prod23);
                    next_acc24 = $signed(ffn_acc24) + $signed(ffn_prod24);
                    next_acc25 = $signed(ffn_acc25) + $signed(ffn_prod25);
                    next_acc26 = $signed(ffn_acc26) + $signed(ffn_prod26);
                    next_acc27 = $signed(ffn_acc27) + $signed(ffn_prod27);
                    next_acc28 = $signed(ffn_acc28) + $signed(ffn_prod28);
                    next_acc29 = $signed(ffn_acc29) + $signed(ffn_prod29);
                    next_acc30 = $signed(ffn_acc30) + $signed(ffn_prod30);
                    next_acc31 = $signed(ffn_acc31) + $signed(ffn_prod31);
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                    end
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        ddr_read_count <= ddr_read_count + 1'b1;
                        if (m_axi_ddr_rresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        case (ffn_weight_beat)
                            2'd0: begin
                                ffn_weight_next_ping <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd1;
                            end
                            2'd1: begin
                                ffn_weight_next_pong <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd2;
                            end
                            2'd2: begin
                                ffn_weight_next_tail <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd3;
                            end
                            default: begin
                                ffn_weight_next_quad <= m_axi_ddr_rdata;
                                ffn_weight_beat <= '0;
                                ffn_prefetch_ready <= 1'b1;
                                m_axi_ddr_rready <= 1'b0;
                            end
                        endcase
                    end
                    if (ddr_read_resp != 2'b00) begin
                        error_latched <= 1'b1;
                        ddr_error_count <= ddr_error_count + 1'b1;
                    end
                    if (ffn_hidden_dim == FULL_MLP_DIM-1) begin
                        ffn_final0 <= next_acc0;
                        ffn_final1 <= next_acc1;
                        ffn_final2 <= next_acc2;
                        ffn_final3 <= next_acc3;
                        ffn_final4 <= next_acc4;
                        ffn_final5 <= next_acc5;
                        ffn_final6 <= next_acc6;
                        ffn_final7 <= next_acc7;
                        ffn_final8 <= next_acc8;
                        ffn_final9 <= next_acc9;
                        ffn_final10 <= next_acc10;
                        ffn_final11 <= next_acc11;
                        ffn_final12 <= next_acc12;
                        ffn_final13 <= next_acc13;
                        ffn_final14 <= next_acc14;
                        ffn_final15 <= next_acc15;
                        ffn_final16 <= next_acc16;
                        ffn_final17 <= next_acc17;
                        ffn_final18 <= next_acc18;
                        ffn_final19 <= next_acc19;
                        ffn_final20 <= next_acc20;
                        ffn_final21 <= next_acc21;
                        ffn_final22 <= next_acc22;
                        ffn_final23 <= next_acc23;
                        ffn_final24 <= next_acc24;
                        ffn_final25 <= next_acc25;
                        ffn_final26 <= next_acc26;
                        ffn_final27 <= next_acc27;
                        ffn_final28 <= next_acc28;
                        ffn_final29 <= next_acc29;
                        ffn_final30 <= next_acc30;
                        ffn_final31 <= next_acc31;
                        ffn_acc0 <= '0;
                        ffn_acc1 <= '0;
                        ffn_acc2 <= '0;
                        ffn_acc3 <= '0;
                        ffn_acc4 <= '0;
                        ffn_acc5 <= '0;
                        ffn_acc6 <= '0;
                        ffn_acc7 <= '0;
                        ffn_acc8 <= '0;
                        ffn_acc9 <= '0;
                        ffn_acc10 <= '0;
                        ffn_acc11 <= '0;
                        ffn_acc12 <= '0;
                        ffn_acc13 <= '0;
                        ffn_acc14 <= '0;
                        ffn_acc15 <= '0;
                        ffn_acc16 <= '0;
                        ffn_acc17 <= '0;
                        ffn_acc18 <= '0;
                        ffn_acc19 <= '0;
                        ffn_acc20 <= '0;
                        ffn_acc21 <= '0;
                        ffn_acc22 <= '0;
                        ffn_acc23 <= '0;
                        ffn_acc24 <= '0;
                        ffn_acc25 <= '0;
                        ffn_acc26 <= '0;
                        ffn_acc27 <= '0;
                        ffn_acc28 <= '0;
                        ffn_acc29 <= '0;
                        ffn_acc30 <= '0;
                        ffn_acc31 <= '0;
                        ffn_parallel_lane <= '0;
`ifdef FFN_FULL_DIAG
                        if (!ffn_add_residual) begin
                            diag_u32(fd_w2_acc_full, next_acc0);
                            diag_u32(fd_w2_acc_full, next_acc1);
                            diag_u32(fd_w2_acc_full, next_acc2);
                            diag_u32(fd_w2_acc_full, next_acc3);
                        end
`endif
                        state <= ST_FFN_W2_FINAL;
                    end else begin
                        ffn_acc0 <= next_acc0;
                        ffn_acc1 <= next_acc1;
                        ffn_acc2 <= next_acc2;
                        ffn_acc3 <= next_acc3;
                        ffn_acc4 <= next_acc4;
                        ffn_acc5 <= next_acc5;
                        ffn_acc6 <= next_acc6;
                        ffn_acc7 <= next_acc7;
                        ffn_acc8 <= next_acc8;
                        ffn_acc9 <= next_acc9;
                        ffn_acc10 <= next_acc10;
                        ffn_acc11 <= next_acc11;
                        ffn_acc12 <= next_acc12;
                        ffn_acc13 <= next_acc13;
                        ffn_acc14 <= next_acc14;
                        ffn_acc15 <= next_acc15;
                        ffn_acc16 <= next_acc16;
                        ffn_acc17 <= next_acc17;
                        ffn_acc18 <= next_acc18;
                        ffn_acc19 <= next_acc19;
                        ffn_acc20 <= next_acc20;
                        ffn_acc21 <= next_acc21;
                        ffn_acc22 <= next_acc22;
                        ffn_acc23 <= next_acc23;
                        ffn_acc24 <= next_acc24;
                        ffn_acc25 <= next_acc25;
                        ffn_acc26 <= next_acc26;
                        ffn_acc27 <= next_acc27;
                        ffn_acc28 <= next_acc28;
                        ffn_acc29 <= next_acc29;
                        ffn_acc30 <= next_acc30;
                        ffn_acc31 <= next_acc31;
                        state <= ST_FFN_W2_NEXT_WAIT;
                    end
                end

                ST_FFN_W2_NEXT_WAIT: begin
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                    end
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        ddr_read_count <= ddr_read_count + 1'b1;
                        if (m_axi_ddr_rresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        case (ffn_weight_beat)
                            2'd0: begin
                                ffn_weight_next_ping <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd1;
                            end
                            2'd1: begin
                                ffn_weight_next_pong <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd2;
                            end
                            2'd2: begin
                                ffn_weight_next_tail <= m_axi_ddr_rdata;
                                ffn_weight_beat <= 2'd3;
                            end
                            default: begin
                                ffn_weight_next_quad <= m_axi_ddr_rdata;
                                ffn_weight_beat <= '0;
                                ffn_prefetch_ready <= 1'b1;
                                m_axi_ddr_rready <= 1'b0;
                            end
                        endcase
                    end
                    if (ffn_prefetch_ready) begin
                        ffn_weight_ping <= ffn_weight_next_ping;
                        ffn_weight_pong <= ffn_weight_next_pong;
                        ffn_weight_tail <= ffn_weight_next_tail;
                        ffn_weight_quad <= ffn_weight_next_quad;
                        ffn_prefetch_ready <= 1'b0;
                        ffn_hidden_dim <= ffn_hidden_dim + 1'b1;
                        ffn_mid_rd_addr <= ffn_hidden_dim + 1'b1;
                        state <= ST_FFN_W2_NEXT_MID_WAIT;
                    end
                end

                ST_FFN_W2_NEXT_MID_WAIT: begin
                    state <= ST_FFN_W2_MUL;
                end

                ST_FFN_W2_FINAL: begin
                    state <= ST_FFN_W2_QUANT;
                end

                ST_FFN_W2_QUANT: begin
                    logic signed [31:0] selected_final;
                    case (ffn_parallel_lane)
                        4'd0: selected_final = ffn_final0;
                        4'd1: selected_final = ffn_final1;
                        4'd2: selected_final = ffn_final2;
                        4'd3: selected_final = ffn_final3;
                        4'd4: selected_final = ffn_final4;
                        4'd5: selected_final = ffn_final5;
                        4'd6: selected_final = ffn_final6;
                        4'd7: selected_final = ffn_final7;
                        4'd8: selected_final = ffn_final8;
                        4'd9: selected_final = ffn_final9;
                        4'd10: selected_final = ffn_final10;
                        4'd11: selected_final = ffn_final11;
                        4'd12: selected_final = ffn_final12;
                        4'd13: selected_final = ffn_final13;
                        4'd14: selected_final = ffn_final14;
                        4'd15: selected_final = ffn_final15;
                        5'd16: selected_final = ffn_final16;
                        5'd17: selected_final = ffn_final17;
                        5'd18: selected_final = ffn_final18;
                        5'd19: selected_final = ffn_final19;
                        5'd20: selected_final = ffn_final20;
                        5'd21: selected_final = ffn_final21;
                        5'd22: selected_final = ffn_final22;
                        5'd23: selected_final = ffn_final23;
                        5'd24: selected_final = ffn_final24;
                        5'd25: selected_final = ffn_final25;
                        5'd26: selected_final = ffn_final26;
                        5'd27: selected_final = ffn_final27;
                        5'd28: selected_final = ffn_final28;
                        5'd29: selected_final = ffn_final29;
                        5'd30: selected_final = ffn_final30;
                        default: selected_final = ffn_final31;
                    endcase
                    q_value <= requant_q30(selected_final, ffn_mult_q30_data);
`ifdef FFN_FULL_DIAG
                    if (!ffn_add_residual) diag_i8(fd_ffn_out_full, requant_full_ffn(selected_final, full_ffn_shift_reg));
`endif
                    proj_res_lane <= q_dim[1:0];
                    state <= ST_FFN_RES_REQ;
                end

                ST_FFN_W2_QUANT_WAIT: begin
                    state <= ST_FFN_W2_QUANT;
                end

                ST_FFN_RES_REQ: begin
                    m_axi_ddr_araddr <= full_debug_base_reg + (row * FULL_D_MODEL) + {q_dim[8:2], 2'b00};
                    m_axi_ddr_arvalid <= 1'b1;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        state <= ST_FFN_RES_WAIT;
                    end
                end

                ST_FFN_RES_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        m_axi_ddr_rready <= 1'b0;
                        ffn_res_value <= select_word_byte_signed(select_axi_word32(m_axi_ddr_rdata, m_axi_ddr_araddr[2]), proj_res_lane);
                        ddr_read_count <= ddr_read_count + 1'b1;
                        if (m_axi_ddr_rresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        state <= ST_FFN_WRITE_ADDR;
                    end
                end

                ST_FFN_WRITE_ADDR: begin
                    logic [31:0] byte_addr;
                    logic [63:0] packed_word;
                    logic signed [7:0] final_value;
                    packed_word = ffn_word_pack;
                    final_value = ffn_add_residual ? clamp8($signed(ffn_res_value) + $signed(q_value)) : q_value;
`ifdef FFN_FULL_DIAG
                    if (ffn_add_residual && q_dim[1:0] != 2'd3) diag_i8(fd_final_full, final_value);
`endif
                    packed_word[q_dim[2:0]*8 +: 8] = final_value;
                    if (q_dim[2:0] == 3'd7) begin
                        byte_addr = full_output_base_reg + (row * FULL_D_MODEL) + {q_dim[8:3], 3'b000};
                        ffn_write_word <= packed_word;
                        ddr_wdata_stage <= packed_word;
                        m_axi_ddr_awaddr <= {byte_addr[31:3], 3'b000};
                        m_axi_ddr_awvalid <= 1'b1;
                        if (m_axi_ddr_awvalid && m_axi_ddr_awready) begin
`ifdef FFN_FULL_DIAG
                            if (ffn_add_residual) diag_i8(fd_final_full, final_value);
`endif
                            m_axi_ddr_awvalid <= 1'b0;
                            state <= ST_FFN_WRITE_DATA;
                        end
                    end else begin
                        ffn_word_pack <= packed_word;
                        q_dim <= q_dim + 1'b1;
                        ffn_parallel_lane <= ffn_parallel_lane + 1'b1;
                        state <= ST_FFN_W2_QUANT_WAIT;
                    end
                end

                ST_FFN_WRITE_DATA: begin
                    m_axi_ddr_wstrb <= 8'hff;
                    m_axi_ddr_wvalid <= 1'b1;
                    m_axi_ddr_wlast <= 1'b1;
                    if (m_axi_ddr_wvalid && m_axi_ddr_wready) begin
                        m_axi_ddr_wvalid <= 1'b0;
                        m_axi_ddr_wlast <= 1'b0;
                        m_axi_ddr_bready <= 1'b1;
                        state <= ST_FFN_WRITE_RESP;
                    end
                end

                ST_FFN_WRITE_RESP: begin
                    m_axi_ddr_bready <= 1'b1;
                    if (m_axi_ddr_bvalid && m_axi_ddr_bready) begin
                        m_axi_ddr_bready <= 1'b0;
                        if (m_axi_ddr_bresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        if (q_dim == FULL_D_MODEL-1) begin
                            if (row == active_rows_reg-1'b1) begin
                                full_stage_done_reg <= ffn_add_residual ? 32'h0000_007f : 32'h0000_003f;
                                full_status_reg <= FULL_CONFIG_VERSION | 32'h1;
                                state <= ST_DONE;
                            end else begin
                                row <= row + 1'b1;
                                in_word_index <= '0;
                                ffn_hidden_dim <= '0;
                                q_dim <= '0;
                                mac_dim <= '0;
                                q_acc <= '0;
                                q_final_acc <= '0;
                                ffn_mid_rd_addr <= '0;
                                ffn_mid_wr_addr <= '0;
                                ffn_word_pack <= '0;
                                state <= ST_FFN_INPUT_REQ;
                            end
                        end else if (ffn_parallel_lane != 5'd31) begin
                            q_dim <= q_dim + 1'b1;
                            ffn_parallel_lane <= ffn_parallel_lane + 1'b1;
                            ffn_word_pack <= '0;
                            state <= ST_FFN_W2_QUANT_WAIT;
                        end else begin
                            q_dim <= q_dim + 1'b1;
                            ffn_hidden_dim <= '0;
                            q_acc <= '0;
                            q_final_acc <= '0;
                            ffn_parallel_lane <= '0;
                            ffn_acc0 <= '0;
                            ffn_acc1 <= '0;
                            ffn_acc2 <= '0;
                            ffn_acc3 <= '0;
                            ffn_acc4 <= '0;
                            ffn_acc5 <= '0;
                            ffn_acc6 <= '0;
                            ffn_acc7 <= '0;
                            ffn_acc8 <= '0;
                            ffn_acc9 <= '0;
                            ffn_acc10 <= '0;
                            ffn_acc11 <= '0;
                            ffn_acc12 <= '0;
                            ffn_acc13 <= '0;
                            ffn_acc14 <= '0;
                            ffn_acc15 <= '0;
                            ffn_acc16 <= '0;
                            ffn_acc17 <= '0;
                            ffn_acc18 <= '0;
                            ffn_acc19 <= '0;
                            ffn_acc20 <= '0;
                            ffn_acc21 <= '0;
                            ffn_acc22 <= '0;
            ffn_acc23 <= '0;
            ffn_acc24 <= '0;
            ffn_acc25 <= '0;
            ffn_acc26 <= '0;
            ffn_acc27 <= '0;
            ffn_acc28 <= '0;
            ffn_acc29 <= '0;
            ffn_acc30 <= '0;
            ffn_acc31 <= '0;
            ffn_final0 <= '0;
                            ffn_final1 <= '0;
                            ffn_final2 <= '0;
                            ffn_final3 <= '0;
                            ffn_final4 <= '0;
                            ffn_final5 <= '0;
                            ffn_final6 <= '0;
                            ffn_final7 <= '0;
                            ffn_final8 <= '0;
                            ffn_final9 <= '0;
                            ffn_final10 <= '0;
                            ffn_final11 <= '0;
                            ffn_final12 <= '0;
                            ffn_final13 <= '0;
                            ffn_final14 <= '0;
                            ffn_final15 <= '0;
                            ffn_final16 <= '0;
                            ffn_final17 <= '0;
                            ffn_final18 <= '0;
                            ffn_final19 <= '0;
                            ffn_final20 <= '0;
                            ffn_final21 <= '0;
                            ffn_final22 <= '0;
                            ffn_final23 <= '0;
                            ffn_mid_rd_addr <= '0;
                            ffn_word_pack <= '0;
                            state <= ST_FFN_W2_RD_MID;
                        end
                    end
                end

                ST_LM_LNF_REQ: begin
                    m_axi_ddr_araddr <= full_input_base_reg + (row * FULL_D_MODEL) + (in_word_index << 2);
                    m_axi_ddr_arvalid <= 1'b1;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        state <= ST_LM_LNF_WAIT;
                    end
                end

                ST_LM_LNF_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        m_axi_ddr_rready <= 1'b0;
                        ddr_read_word <= {32'd0, select_axi_word32(m_axi_ddr_rdata, m_axi_ddr_araddr[2])};
                        ddr_read_resp <= m_axi_ddr_rresp;
                        ddr_read_count <= ddr_read_count + 1'b1;
                        state <= ST_LM_LNF_CAPTURE;
                    end
                end

                ST_LM_LNF_CAPTURE: begin
                    logic signed [7:0] b0;
                    logic signed [7:0] b1;
                    logic signed [7:0] b2;
                    logic signed [7:0] b3;
                    b0 = select_word_byte_signed(ddr_read_word, 2'd0);
                    b1 = select_word_byte_signed(ddr_read_word, 2'd1);
                    b2 = select_word_byte_signed(ddr_read_word, 2'd2);
                    b3 = select_word_byte_signed(ddr_read_word, 2'd3);
                    input_row[(in_word_index << 2) + 0] <= b0;
                    input_row[(in_word_index << 2) + 1] <= b1;
                    input_row[(in_word_index << 2) + 2] <= b2;
                    input_row[(in_word_index << 2) + 3] <= b3;
                    row_sum <= row_sum + $signed(b0) + $signed(b1) + $signed(b2) + $signed(b3);
                    if (ddr_read_resp != 2'b00) begin
                        error_latched <= 1'b1;
                        ddr_error_count <= ddr_error_count + 1'b1;
                    end
                    if (in_word_index == (FULL_D_MODEL/4)-1) begin
                        if (mode_reg[10]) begin
                            lm_group_idx <= '0;
                            lm_scale_lane <= '0;
                            lm_rom_addr <= '0;
                            lm_best_token <= '0;
                            lm_best_score <= -(64'sd1 <<< 62);
                            state <= ST_LM_FAST_GROUP_INIT;
                        end else begin
                            row_sum_q <= row_sum + $signed(b0) + $signed(b1) + $signed(b2) + $signed(b3);
                            row_sum_q_neg <= (row_sum + $signed(b0) + $signed(b1) + $signed(b2) + $signed(b3)) < 0;
                            div384_rem <= ((row_sum + $signed(b0) + $signed(b1) + $signed(b2) + $signed(b3)) < 0) ?
                                          -(row_sum + $signed(b0) + $signed(b1) + $signed(b2) + $signed(b3)) :
                                          (row_sum + $signed(b0) + $signed(b1) + $signed(b2) + $signed(b3));
                            div384_quot <= '0;
                            div384_bit <= 4'd8;
                            state <= ST_LN2_MEAN_ITER;
                        end
                    end else begin
                        in_word_index <= in_word_index + 1'b1;
                        state <= ST_LM_LNF_REQ;
                    end
                end

                ST_LM_FAST_GROUP_INIT: begin
                    mac_dim <= '0;
                    ffn_acc0 <= '0;
                    ffn_acc1 <= '0;
                    ffn_acc2 <= '0;
                    ffn_acc3 <= '0;
                    ffn_acc4 <= '0;
                    ffn_acc5 <= '0;
                    ffn_acc6 <= '0;
                    ffn_acc7 <= '0;
                    lm_rom_addr <= lm_group_idx;
                    state <= ST_LM_FAST_ROM_WAIT;
                end

                ST_LM_FAST_ROM_WAIT: begin
                    state <= ST_LM_FAST_MUL_LOAD;
                end

                ST_LM_FAST_MUL_LOAD: begin
                    ffn_mul_a <= $signed(input_row[mac_dim]);
                    ffn_mul_b0 <= $signed(lm_rom_data[7:0]);
                    ffn_mul_b1 <= $signed(lm_rom_data[15:8]);
                    ffn_mul_b2 <= $signed(lm_rom_data[23:16]);
                    ffn_mul_b3 <= $signed(lm_rom_data[31:24]);
                    ffn_mul_b4 <= $signed(lm_rom_data[39:32]);
                    ffn_mul_b5 <= $signed(lm_rom_data[47:40]);
                    ffn_mul_b6 <= $signed(lm_rom_data[55:48]);
                    ffn_mul_b7 <= $signed(lm_rom_data[63:56]);
                    state <= ST_LM_FAST_MUL_EXEC;
                end

                ST_LM_FAST_MUL_EXEC: begin
                    ffn_prod0 <= ffn_mul_a * ffn_mul_b0;
                    ffn_prod1 <= ffn_mul_a * ffn_mul_b1;
                    ffn_prod2 <= ffn_mul_a * ffn_mul_b2;
                    ffn_prod3 <= ffn_mul_a * ffn_mul_b3;
                    ffn_prod4 <= ffn_mul_a * ffn_mul_b4;
                    ffn_prod5 <= ffn_mul_a * ffn_mul_b5;
                    ffn_prod6 <= ffn_mul_a * ffn_mul_b6;
                    ffn_prod7 <= ffn_mul_a * ffn_mul_b7;
                    state <= ST_LM_FAST_ACCUM;
                end

                ST_LM_FAST_ACCUM: begin
                    logic signed [31:0] next_acc0;
                    logic signed [31:0] next_acc1;
                    logic signed [31:0] next_acc2;
                    logic signed [31:0] next_acc3;
                    logic signed [31:0] next_acc4;
                    logic signed [31:0] next_acc5;
                    logic signed [31:0] next_acc6;
                    logic signed [31:0] next_acc7;
                    next_acc0 = $signed(ffn_acc0) + $signed(ffn_prod0);
                    next_acc1 = $signed(ffn_acc1) + $signed(ffn_prod1);
                    next_acc2 = $signed(ffn_acc2) + $signed(ffn_prod2);
                    next_acc3 = $signed(ffn_acc3) + $signed(ffn_prod3);
                    next_acc4 = $signed(ffn_acc4) + $signed(ffn_prod4);
                    next_acc5 = $signed(ffn_acc5) + $signed(ffn_prod5);
                    next_acc6 = $signed(ffn_acc6) + $signed(ffn_prod6);
                    next_acc7 = $signed(ffn_acc7) + $signed(ffn_prod7);
                    if (mac_dim == FULL_D_MODEL-1) begin
                        ffn_final0 <= next_acc0;
                        ffn_final1 <= next_acc1;
                        ffn_final2 <= next_acc2;
                        ffn_final3 <= next_acc3;
                        ffn_final4 <= next_acc4;
                        ffn_final5 <= next_acc5;
                        ffn_final6 <= next_acc6;
                        ffn_final7 <= next_acc7;
                        lm_scale_lane <= '0;
                        state <= ST_LM_FAST_SCALE_LOAD;
                    end else begin
                        ffn_acc0 <= next_acc0;
                        ffn_acc1 <= next_acc1;
                        ffn_acc2 <= next_acc2;
                        ffn_acc3 <= next_acc3;
                        ffn_acc4 <= next_acc4;
                        ffn_acc5 <= next_acc5;
                        ffn_acc6 <= next_acc6;
                        ffn_acc7 <= next_acc7;
                        mac_dim <= mac_dim + 1'b1;
                        lm_rom_addr <= lm_rom_addr + 12'd9;
                        state <= ST_LM_FAST_ROM_WAIT;
                    end
                end

                ST_LM_FAST_SCALE_LOAD: begin
                    logic [6:0] candidate;
                    candidate = {lm_group_idx, 3'b000} + lm_scale_lane;
                    lm_vocab_idx <= candidate;
                    unique case (lm_scale_lane)
                        3'd0: lm_scale_acc <= ffn_final0;
                        3'd1: lm_scale_acc <= ffn_final1;
                        3'd2: lm_scale_acc <= ffn_final2;
                        3'd3: lm_scale_acc <= ffn_final3;
                        3'd4: lm_scale_acc <= ffn_final4;
                        3'd5: lm_scale_acc <= ffn_final5;
                        3'd6: lm_scale_acc <= ffn_final6;
                        default: lm_scale_acc <= ffn_final7;
                    endcase
                    lm_scale_factor <= lm_scale_ratio_rom[candidate];
                    state <= ST_LM_FAST_SCALE_EXEC;
                end

                ST_LM_FAST_SCALE_EXEC: begin
                    lm_scale_product <= $signed(lm_scale_acc) * $signed({1'b0, lm_scale_factor[30:0]});
                    state <= ST_LM_FAST_SCALE_COMPARE;
                end

                ST_LM_FAST_SCALE_COMPARE: begin
                    if (lm_vocab_idx == 0 || lm_scale_product > lm_best_score) begin
                        lm_best_score <= lm_scale_product;
                        lm_best_token <= lm_vocab_idx;
                    end
                    if (lm_vocab_idx == FULL_VOCAB_SIZE-1) begin
                        state <= ST_LM_WRITE_ADDR;
                    end else if (lm_scale_lane == 3'd7) begin
                        lm_group_idx <= lm_group_idx + 1'b1;
                        state <= ST_LM_FAST_GROUP_INIT;
                    end else begin
                        lm_scale_lane <= lm_scale_lane + 1'b1;
                        state <= ST_LM_FAST_SCALE_LOAD;
                    end
                end

                ST_LM_VOCAB_INIT: begin
                    lm_acc <= '0;
                    mac_dim <= '0;
                    state <= ST_LM_W_REQ;
                end

                ST_LM_W_REQ: begin
                    logic [31:0] byte_addr;
                    byte_addr = full_weights_base_reg + (mac_dim * FULL_VOCAB_SIZE) + lm_vocab_idx;
                    m_axi_ddr_araddr <= {byte_addr[31:2], 2'b00};
                    lm_weight_lane <= byte_addr[1:0];
                    m_axi_ddr_arvalid <= 1'b1;
                    if (m_axi_ddr_arvalid && m_axi_ddr_arready) begin
                        m_axi_ddr_arvalid <= 1'b0;
                        m_axi_ddr_rready <= 1'b1;
                        state <= ST_LM_W_WAIT;
                    end
                end

                ST_LM_W_WAIT: begin
                    if (m_axi_ddr_rvalid && m_axi_ddr_rready) begin
                        m_axi_ddr_rready <= 1'b0;
                        lm_weight_value <= select_word_byte_signed(select_axi_word32(m_axi_ddr_rdata, m_axi_ddr_araddr[2]), lm_weight_lane);
                        if (m_axi_ddr_rresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        ddr_read_count <= ddr_read_count + 1'b1;
                        state <= ST_LM_MAC_LOAD;
                    end
                end

                ST_LM_MAC_LOAD: begin
                    lm_ln_value <= clamp8($signed(input_row[mac_dim]) - $signed(row_mean));
                    state <= ST_LM_MAC_MUL;
                end

                ST_LM_MAC_MUL: begin
                    lm_mac_product <= $signed(lm_ln_value) * $signed(lm_weight_value);
                    state <= ST_LM_MAC;
                end

                ST_LM_MAC: begin
                    lm_acc <= lm_acc + $signed(lm_mac_product);
                    if (mac_dim == FULL_D_MODEL-1) begin
                        state <= ST_LM_NEXT_VOCAB;
                    end else begin
                        mac_dim <= mac_dim + 1'b1;
                        state <= ST_LM_W_REQ;
                    end
                end

                ST_LM_NEXT_VOCAB: begin
                    if (lm_vocab_idx == 0 || lm_acc > lm_best_score) begin
                        lm_best_score <= lm_acc;
                        lm_best_token <= lm_vocab_idx;
                    end
                    if (lm_vocab_idx == FULL_VOCAB_SIZE-1) begin
                        state <= ST_LM_WRITE_ADDR;
                    end else begin
                        lm_vocab_idx <= lm_vocab_idx + 1'b1;
                        state <= ST_LM_VOCAB_INIT;
                    end
                end

                ST_LM_WRITE_ADDR: begin
                    logic [31:0] byte_addr;
                    logic [15:0] token_word;
                    byte_addr = quality_argmax_base_reg + (row << 1);
                    token_word = {9'd0, lm_best_token};
                    lm_argmax_lane <= byte_addr[1:0];
                    ddr_wdata_stage <= align_axi_wdata32({2{token_word}} << (byte_addr[1:0] * 8), byte_addr[2]);
                    m_axi_ddr_awaddr <= {byte_addr[31:2], 2'b00};
                    m_axi_ddr_awvalid <= 1'b1;
                    if (m_axi_ddr_awvalid && m_axi_ddr_awready) begin
                        m_axi_ddr_awvalid <= 1'b0;
                        state <= ST_LM_WRITE_DATA;
                    end
                end

                ST_LM_WRITE_DATA: begin
                    m_axi_ddr_wstrb <= align_axi_wstrb4(4'b0011 << lm_argmax_lane, m_axi_ddr_awaddr[2]);
                    m_axi_ddr_wvalid <= 1'b1;
                    m_axi_ddr_wlast <= 1'b1;
                    if (m_axi_ddr_wvalid && m_axi_ddr_wready) begin
                        m_axi_ddr_wvalid <= 1'b0;
                        m_axi_ddr_wlast <= 1'b0;
                        m_axi_ddr_bready <= 1'b1;
                        state <= ST_LM_WRITE_RESP;
                    end
                end

                ST_LM_WRITE_RESP: begin
                    m_axi_ddr_bready <= 1'b1;
                    if (m_axi_ddr_bvalid && m_axi_ddr_bready) begin
                        m_axi_ddr_bready <= 1'b0;
                        if (m_axi_ddr_bresp != 2'b00) begin
                            error_latched <= 1'b1;
                            ddr_error_count <= ddr_error_count + 1'b1;
                        end
                        if (row == active_rows_reg-1'b1) begin
                            full_stage_done_reg <= 32'h0000_00ff;
                            full_status_reg <= FULL_CONFIG_VERSION | 32'h1;
                            state <= ST_DONE;
                        end else begin
                            row <= row + 1'b1;
                            in_word_index <= '0;
                            row_sum <= '0;
                            lm_vocab_idx <= '0;
                            mac_dim <= '0;
                            lm_acc <= '0;
                            lm_best_token <= '0;
                            lm_best_score <= -(64'sd1 <<< 62);
                            state <= ST_LM_LNF_REQ;
                        end
                    end
                end

                ST_DONE: begin
                    busy <= 1'b0;
                    done_latched <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
