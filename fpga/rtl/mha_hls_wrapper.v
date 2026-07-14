`timescale 1ns/1ps

module mha_hls_wrapper (
    input  logic ap_clk,
    input  logic ap_rst,
    input  logic start,
    input  logic [2047:0] x_flat,
    input  logic [2047:0] wq_flat,
    input  logic [2047:0] wk_flat,
    input  logic [2047:0] wv_flat,
    output logic done,
    output logic [7:0] result_byte,
    output logic [4095:0] out_flat
);
    logic ap_start;
    logic ap_done, ap_idle, ap_ready;
    logic [7:0] X_mem [0:15][0:15];
    logic [7:0] WQ_mem [0:15][0:15];
    logic [7:0] WK_mem [0:15][0:15];
    logic [7:0] WV_mem [0:15][0:15];
    logic [7:0] softmax_lut_mem [0:15];
    logic [15:0] OUT_mem [0:255];
    integer r, c;
    genvar go;
    assign ap_start = start;
    assign done = ap_done;
    assign result_byte = OUT_mem[0][7:0];
    generate
        for (go = 0; go < 256; go = go + 1) begin : g_out_flat
            assign out_flat[go*16 +: 16] = OUT_mem[go];
        end
    endgenerate
    logic [3:0] X_0_address0;
    logic       X_0_ce0;
    logic [7:0] X_0_q0;
    logic [3:0] WQ_0_address0;
    logic       WQ_0_ce0;
    logic [7:0] WQ_0_q0;
    logic [3:0] WK_0_address0;
    logic       WK_0_ce0;
    logic [7:0] WK_0_q0;
    logic [3:0] WV_0_address0;
    logic       WV_0_ce0;
    logic [7:0] WV_0_q0;
    logic [3:0] X_1_address0;
    logic       X_1_ce0;
    logic [7:0] X_1_q0;
    logic [3:0] WQ_1_address0;
    logic       WQ_1_ce0;
    logic [7:0] WQ_1_q0;
    logic [3:0] WK_1_address0;
    logic       WK_1_ce0;
    logic [7:0] WK_1_q0;
    logic [3:0] WV_1_address0;
    logic       WV_1_ce0;
    logic [7:0] WV_1_q0;
    logic [3:0] X_2_address0;
    logic       X_2_ce0;
    logic [7:0] X_2_q0;
    logic [3:0] WQ_2_address0;
    logic       WQ_2_ce0;
    logic [7:0] WQ_2_q0;
    logic [3:0] WK_2_address0;
    logic       WK_2_ce0;
    logic [7:0] WK_2_q0;
    logic [3:0] WV_2_address0;
    logic       WV_2_ce0;
    logic [7:0] WV_2_q0;
    logic [3:0] X_3_address0;
    logic       X_3_ce0;
    logic [7:0] X_3_q0;
    logic [3:0] WQ_3_address0;
    logic       WQ_3_ce0;
    logic [7:0] WQ_3_q0;
    logic [3:0] WK_3_address0;
    logic       WK_3_ce0;
    logic [7:0] WK_3_q0;
    logic [3:0] WV_3_address0;
    logic       WV_3_ce0;
    logic [7:0] WV_3_q0;
    logic [3:0] X_4_address0;
    logic       X_4_ce0;
    logic [7:0] X_4_q0;
    logic [3:0] WQ_4_address0;
    logic       WQ_4_ce0;
    logic [7:0] WQ_4_q0;
    logic [3:0] WK_4_address0;
    logic       WK_4_ce0;
    logic [7:0] WK_4_q0;
    logic [3:0] WV_4_address0;
    logic       WV_4_ce0;
    logic [7:0] WV_4_q0;
    logic [3:0] X_5_address0;
    logic       X_5_ce0;
    logic [7:0] X_5_q0;
    logic [3:0] WQ_5_address0;
    logic       WQ_5_ce0;
    logic [7:0] WQ_5_q0;
    logic [3:0] WK_5_address0;
    logic       WK_5_ce0;
    logic [7:0] WK_5_q0;
    logic [3:0] WV_5_address0;
    logic       WV_5_ce0;
    logic [7:0] WV_5_q0;
    logic [3:0] X_6_address0;
    logic       X_6_ce0;
    logic [7:0] X_6_q0;
    logic [3:0] WQ_6_address0;
    logic       WQ_6_ce0;
    logic [7:0] WQ_6_q0;
    logic [3:0] WK_6_address0;
    logic       WK_6_ce0;
    logic [7:0] WK_6_q0;
    logic [3:0] WV_6_address0;
    logic       WV_6_ce0;
    logic [7:0] WV_6_q0;
    logic [3:0] X_7_address0;
    logic       X_7_ce0;
    logic [7:0] X_7_q0;
    logic [3:0] WQ_7_address0;
    logic       WQ_7_ce0;
    logic [7:0] WQ_7_q0;
    logic [3:0] WK_7_address0;
    logic       WK_7_ce0;
    logic [7:0] WK_7_q0;
    logic [3:0] WV_7_address0;
    logic       WV_7_ce0;
    logic [7:0] WV_7_q0;
    logic [3:0] X_8_address0;
    logic       X_8_ce0;
    logic [7:0] X_8_q0;
    logic [3:0] WQ_8_address0;
    logic       WQ_8_ce0;
    logic [7:0] WQ_8_q0;
    logic [3:0] WK_8_address0;
    logic       WK_8_ce0;
    logic [7:0] WK_8_q0;
    logic [3:0] WV_8_address0;
    logic       WV_8_ce0;
    logic [7:0] WV_8_q0;
    logic [3:0] X_9_address0;
    logic       X_9_ce0;
    logic [7:0] X_9_q0;
    logic [3:0] WQ_9_address0;
    logic       WQ_9_ce0;
    logic [7:0] WQ_9_q0;
    logic [3:0] WK_9_address0;
    logic       WK_9_ce0;
    logic [7:0] WK_9_q0;
    logic [3:0] WV_9_address0;
    logic       WV_9_ce0;
    logic [7:0] WV_9_q0;
    logic [3:0] X_10_address0;
    logic       X_10_ce0;
    logic [7:0] X_10_q0;
    logic [3:0] WQ_10_address0;
    logic       WQ_10_ce0;
    logic [7:0] WQ_10_q0;
    logic [3:0] WK_10_address0;
    logic       WK_10_ce0;
    logic [7:0] WK_10_q0;
    logic [3:0] WV_10_address0;
    logic       WV_10_ce0;
    logic [7:0] WV_10_q0;
    logic [3:0] X_11_address0;
    logic       X_11_ce0;
    logic [7:0] X_11_q0;
    logic [3:0] WQ_11_address0;
    logic       WQ_11_ce0;
    logic [7:0] WQ_11_q0;
    logic [3:0] WK_11_address0;
    logic       WK_11_ce0;
    logic [7:0] WK_11_q0;
    logic [3:0] WV_11_address0;
    logic       WV_11_ce0;
    logic [7:0] WV_11_q0;
    logic [3:0] X_12_address0;
    logic       X_12_ce0;
    logic [7:0] X_12_q0;
    logic [3:0] WQ_12_address0;
    logic       WQ_12_ce0;
    logic [7:0] WQ_12_q0;
    logic [3:0] WK_12_address0;
    logic       WK_12_ce0;
    logic [7:0] WK_12_q0;
    logic [3:0] WV_12_address0;
    logic       WV_12_ce0;
    logic [7:0] WV_12_q0;
    logic [3:0] X_13_address0;
    logic       X_13_ce0;
    logic [7:0] X_13_q0;
    logic [3:0] WQ_13_address0;
    logic       WQ_13_ce0;
    logic [7:0] WQ_13_q0;
    logic [3:0] WK_13_address0;
    logic       WK_13_ce0;
    logic [7:0] WK_13_q0;
    logic [3:0] WV_13_address0;
    logic       WV_13_ce0;
    logic [7:0] WV_13_q0;
    logic [3:0] X_14_address0;
    logic       X_14_ce0;
    logic [7:0] X_14_q0;
    logic [3:0] WQ_14_address0;
    logic       WQ_14_ce0;
    logic [7:0] WQ_14_q0;
    logic [3:0] WK_14_address0;
    logic       WK_14_ce0;
    logic [7:0] WK_14_q0;
    logic [3:0] WV_14_address0;
    logic       WV_14_ce0;
    logic [7:0] WV_14_q0;
    logic [3:0] X_15_address0;
    logic       X_15_ce0;
    logic [7:0] X_15_q0;
    logic [3:0] WQ_15_address0;
    logic       WQ_15_ce0;
    logic [7:0] WQ_15_q0;
    logic [3:0] WK_15_address0;
    logic       WK_15_ce0;
    logic [7:0] WK_15_q0;
    logic [3:0] WV_15_address0;
    logic       WV_15_ce0;
    logic [7:0] WV_15_q0;
    logic [3:0] softmax_lut_address0;
    logic       softmax_lut_ce0;
    logic [7:0] softmax_lut_q0;
    logic [7:0] OUT_r_address0;
    logic       OUT_r_ce0;
    logic       OUT_r_we0;
    logic [15:0] OUT_r_d0;
    initial begin
        for (r = 0; r < 16; r = r + 1) begin
            softmax_lut_mem[r] = (r + 1) * 8;
            for (c = 0; c < 16; c = c + 1) begin
                X_mem[r][c]  = 8'd0;
                WQ_mem[r][c] = 8'd0;
                WK_mem[r][c] = 8'd0;
                WV_mem[r][c] = 8'd0;
            end
        end
        
    end
    always @(posedge ap_clk) begin
        if (start) begin
            for (r = 0; r < 16; r = r + 1) begin
                for (c = 0; c < 16; c = c + 1) begin
                    X_mem[r][c]  <= x_flat[(r*16+c)*8 +: 8];
                    WQ_mem[r][c] <= wq_flat[(r*16+c)*8 +: 8];
                    WK_mem[r][c] <= wk_flat[(r*16+c)*8 +: 8];
                    WV_mem[r][c] <= wv_flat[(r*16+c)*8 +: 8];
                end
            end
        end
    end
    assign X_0_q0 = X_mem[X_0_address0][0];
    assign WQ_0_q0 = WQ_mem[WQ_0_address0][0];
    assign WK_0_q0 = WK_mem[WK_0_address0][0];
    assign WV_0_q0 = WV_mem[WV_0_address0][0];
    assign X_1_q0 = X_mem[X_1_address0][1];
    assign WQ_1_q0 = WQ_mem[WQ_1_address0][1];
    assign WK_1_q0 = WK_mem[WK_1_address0][1];
    assign WV_1_q0 = WV_mem[WV_1_address0][1];
    assign X_2_q0 = X_mem[X_2_address0][2];
    assign WQ_2_q0 = WQ_mem[WQ_2_address0][2];
    assign WK_2_q0 = WK_mem[WK_2_address0][2];
    assign WV_2_q0 = WV_mem[WV_2_address0][2];
    assign X_3_q0 = X_mem[X_3_address0][3];
    assign WQ_3_q0 = WQ_mem[WQ_3_address0][3];
    assign WK_3_q0 = WK_mem[WK_3_address0][3];
    assign WV_3_q0 = WV_mem[WV_3_address0][3];
    assign X_4_q0 = X_mem[X_4_address0][4];
    assign WQ_4_q0 = WQ_mem[WQ_4_address0][4];
    assign WK_4_q0 = WK_mem[WK_4_address0][4];
    assign WV_4_q0 = WV_mem[WV_4_address0][4];
    assign X_5_q0 = X_mem[X_5_address0][5];
    assign WQ_5_q0 = WQ_mem[WQ_5_address0][5];
    assign WK_5_q0 = WK_mem[WK_5_address0][5];
    assign WV_5_q0 = WV_mem[WV_5_address0][5];
    assign X_6_q0 = X_mem[X_6_address0][6];
    assign WQ_6_q0 = WQ_mem[WQ_6_address0][6];
    assign WK_6_q0 = WK_mem[WK_6_address0][6];
    assign WV_6_q0 = WV_mem[WV_6_address0][6];
    assign X_7_q0 = X_mem[X_7_address0][7];
    assign WQ_7_q0 = WQ_mem[WQ_7_address0][7];
    assign WK_7_q0 = WK_mem[WK_7_address0][7];
    assign WV_7_q0 = WV_mem[WV_7_address0][7];
    assign X_8_q0 = X_mem[X_8_address0][8];
    assign WQ_8_q0 = WQ_mem[WQ_8_address0][8];
    assign WK_8_q0 = WK_mem[WK_8_address0][8];
    assign WV_8_q0 = WV_mem[WV_8_address0][8];
    assign X_9_q0 = X_mem[X_9_address0][9];
    assign WQ_9_q0 = WQ_mem[WQ_9_address0][9];
    assign WK_9_q0 = WK_mem[WK_9_address0][9];
    assign WV_9_q0 = WV_mem[WV_9_address0][9];
    assign X_10_q0 = X_mem[X_10_address0][10];
    assign WQ_10_q0 = WQ_mem[WQ_10_address0][10];
    assign WK_10_q0 = WK_mem[WK_10_address0][10];
    assign WV_10_q0 = WV_mem[WV_10_address0][10];
    assign X_11_q0 = X_mem[X_11_address0][11];
    assign WQ_11_q0 = WQ_mem[WQ_11_address0][11];
    assign WK_11_q0 = WK_mem[WK_11_address0][11];
    assign WV_11_q0 = WV_mem[WV_11_address0][11];
    assign X_12_q0 = X_mem[X_12_address0][12];
    assign WQ_12_q0 = WQ_mem[WQ_12_address0][12];
    assign WK_12_q0 = WK_mem[WK_12_address0][12];
    assign WV_12_q0 = WV_mem[WV_12_address0][12];
    assign X_13_q0 = X_mem[X_13_address0][13];
    assign WQ_13_q0 = WQ_mem[WQ_13_address0][13];
    assign WK_13_q0 = WK_mem[WK_13_address0][13];
    assign WV_13_q0 = WV_mem[WV_13_address0][13];
    assign X_14_q0 = X_mem[X_14_address0][14];
    assign WQ_14_q0 = WQ_mem[WQ_14_address0][14];
    assign WK_14_q0 = WK_mem[WK_14_address0][14];
    assign WV_14_q0 = WV_mem[WV_14_address0][14];
    assign X_15_q0 = X_mem[X_15_address0][15];
    assign WQ_15_q0 = WQ_mem[WQ_15_address0][15];
    assign WK_15_q0 = WK_mem[WK_15_address0][15];
    assign WV_15_q0 = WV_mem[WV_15_address0][15];
    assign softmax_lut_q0 = softmax_lut_mem[softmax_lut_address0];
    always @(posedge ap_clk) begin
        if (OUT_r_ce0 && OUT_r_we0) OUT_mem[OUT_r_address0] <= OUT_r_d0;
    end
    mha_kernel u_mha (.*);
endmodule

