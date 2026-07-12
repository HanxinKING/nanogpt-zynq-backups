`timescale 1ns/1ps
module layernorm_hls_wrapper(
    input ap_clk,
    input ap_rst,
    input start,
    input [511:0] x_flat,
    output done,
    output [7:0] result_byte,
    output [511:0] y_flat
);
wire ap_done, ap_idle, ap_ready;
wire [5:0] Y_address0;
wire Y_ce0, Y_we0;
wire [7:0] Y_d0;
reg [7:0] y_mem [0:63];
genvar gi;
assign done = ap_done;
assign result_byte = y_mem[0];
generate
    for (gi = 0; gi < 64; gi = gi + 1) begin : g_y_flat
        assign y_flat[gi*8 +: 8] = y_mem[gi];
    end
endgenerate
always @(posedge ap_clk) begin
    if (Y_ce0 && Y_we0) y_mem[Y_address0] <= Y_d0;
end
layernorm_kernel u_ln(
    .ap_clk(ap_clk), .ap_rst(ap_rst), .ap_start(start), .ap_done(ap_done), .ap_idle(ap_idle), .ap_ready(ap_ready),
    .X_0(x_flat[0*8 +: 8]), .X_1(x_flat[1*8 +: 8]), .X_2(x_flat[2*8 +: 8]), .X_3(x_flat[3*8 +: 8]),
    .X_4(x_flat[4*8 +: 8]), .X_5(x_flat[5*8 +: 8]), .X_6(x_flat[6*8 +: 8]), .X_7(x_flat[7*8 +: 8]),
    .X_8(x_flat[8*8 +: 8]), .X_9(x_flat[9*8 +: 8]), .X_10(x_flat[10*8 +: 8]), .X_11(x_flat[11*8 +: 8]),
    .X_12(x_flat[12*8 +: 8]), .X_13(x_flat[13*8 +: 8]), .X_14(x_flat[14*8 +: 8]), .X_15(x_flat[15*8 +: 8]),
    .X_16(x_flat[16*8 +: 8]), .X_17(x_flat[17*8 +: 8]), .X_18(x_flat[18*8 +: 8]), .X_19(x_flat[19*8 +: 8]),
    .X_20(x_flat[20*8 +: 8]), .X_21(x_flat[21*8 +: 8]), .X_22(x_flat[22*8 +: 8]), .X_23(x_flat[23*8 +: 8]),
    .X_24(x_flat[24*8 +: 8]), .X_25(x_flat[25*8 +: 8]), .X_26(x_flat[26*8 +: 8]), .X_27(x_flat[27*8 +: 8]),
    .X_28(x_flat[28*8 +: 8]), .X_29(x_flat[29*8 +: 8]), .X_30(x_flat[30*8 +: 8]), .X_31(x_flat[31*8 +: 8]),
    .X_32(x_flat[32*8 +: 8]), .X_33(x_flat[33*8 +: 8]), .X_34(x_flat[34*8 +: 8]), .X_35(x_flat[35*8 +: 8]),
    .X_36(x_flat[36*8 +: 8]), .X_37(x_flat[37*8 +: 8]), .X_38(x_flat[38*8 +: 8]), .X_39(x_flat[39*8 +: 8]),
    .X_40(x_flat[40*8 +: 8]), .X_41(x_flat[41*8 +: 8]), .X_42(x_flat[42*8 +: 8]), .X_43(x_flat[43*8 +: 8]),
    .X_44(x_flat[44*8 +: 8]), .X_45(x_flat[45*8 +: 8]), .X_46(x_flat[46*8 +: 8]), .X_47(x_flat[47*8 +: 8]),
    .X_48(x_flat[48*8 +: 8]), .X_49(x_flat[49*8 +: 8]), .X_50(x_flat[50*8 +: 8]), .X_51(x_flat[51*8 +: 8]),
    .X_52(x_flat[52*8 +: 8]), .X_53(x_flat[53*8 +: 8]), .X_54(x_flat[54*8 +: 8]), .X_55(x_flat[55*8 +: 8]),
    .X_56(x_flat[56*8 +: 8]), .X_57(x_flat[57*8 +: 8]), .X_58(x_flat[58*8 +: 8]), .X_59(x_flat[59*8 +: 8]),
    .X_60(x_flat[60*8 +: 8]), .X_61(x_flat[61*8 +: 8]), .X_62(x_flat[62*8 +: 8]), .X_63(x_flat[63*8 +: 8]),
    .Y_address0(Y_address0), .Y_ce0(Y_ce0), .Y_we0(Y_we0), .Y_d0(Y_d0)
);
endmodule

