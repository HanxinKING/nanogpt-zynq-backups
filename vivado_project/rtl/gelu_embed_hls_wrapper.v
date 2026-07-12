`timescale 1ns/1ps
module gelu_embed_hls_wrapper(
    input ap_clk,
    input ap_rst,
    input start,
    input [511:0] x_flat,
    output done,
    output [7:0] result_byte,
    output [511:0] gelu_out_flat
);
wire ap_done, ap_idle, ap_ready;
wire [5:0] X_address0; wire X_ce0; reg [7:0] X_q0;
wire [2:0] token_ids_address0; wire token_ids_ce0; wire [7:0] token_ids_q0;
wire [4:0] embed_lut_0_address0,embed_lut_1_address0,embed_lut_2_address0,embed_lut_3_address0,embed_lut_4_address0,embed_lut_5_address0,embed_lut_6_address0,embed_lut_7_address0;
wire embed_lut_0_ce0,embed_lut_1_ce0,embed_lut_2_ce0,embed_lut_3_ce0,embed_lut_4_ce0,embed_lut_5_ce0,embed_lut_6_ce0,embed_lut_7_ce0;
wire [7:0] embed_lut_0_q0,embed_lut_1_q0,embed_lut_2_q0,embed_lut_3_q0,embed_lut_4_q0,embed_lut_5_q0,embed_lut_6_q0,embed_lut_7_q0;
wire [5:0] gelu_out_address0; wire gelu_out_ce0, gelu_out_we0; wire [7:0] gelu_out_d0;
wire [2:0] embed_out_address0; wire embed_out_ce0, embed_out_we0; wire [7:0] embed_out_d0;
reg [7:0] token_mem [0:7]; reg [7:0] embed_mem [0:7][0:31]; reg [7:0] gelu_lut_mem [0:255]; reg [7:0] gelu_out_mem [0:63]; reg [7:0] embed_out_mem [0:7]; integer r,c;
assign done = ap_done;
assign result_byte = gelu_out_mem[0] ^ embed_out_mem[0];
genvar gi;
generate
  for (gi = 0; gi < 64; gi = gi + 1) begin : g_gelu_out_flat
    assign gelu_out_flat[gi*8 +: 8] = gelu_out_mem[gi];
  end
endgenerate
initial begin
  $readmemh("gelu_global_i8.mem", gelu_lut_mem);
  for(r=0;r<8;r=r+1) token_mem[r]=r;
  for(r=0;r<8;r=r+1) for(c=0;c<32;c=c+1) embed_mem[r][c]=(r+c)%16;
end
assign token_ids_q0 = token_mem[token_ids_address0];
assign embed_lut_0_q0 = embed_mem[0][embed_lut_0_address0]; assign embed_lut_1_q0 = embed_mem[1][embed_lut_1_address0];
assign embed_lut_2_q0 = embed_mem[2][embed_lut_2_address0]; assign embed_lut_3_q0 = embed_mem[3][embed_lut_3_address0];
assign embed_lut_4_q0 = embed_mem[4][embed_lut_4_address0]; assign embed_lut_5_q0 = embed_mem[5][embed_lut_5_address0];
assign embed_lut_6_q0 = embed_mem[6][embed_lut_6_address0]; assign embed_lut_7_q0 = embed_mem[7][embed_lut_7_address0];
always @(posedge ap_clk) begin
  if(X_ce0) X_q0 <= x_flat[X_address0*8 +: 8];
  if(gelu_out_ce0 && gelu_out_we0) gelu_out_mem[gelu_out_address0] <= gelu_out_d0;
  if(embed_out_ce0 && embed_out_we0) embed_out_mem[embed_out_address0] <= embed_out_d0;
end
gelu_embed_kernel u_ge(
  .ap_clk(ap_clk), .ap_rst(ap_rst), .ap_start(start), .ap_done(ap_done), .ap_idle(ap_idle), .ap_ready(ap_ready),
  .X_address0(X_address0), .X_ce0(X_ce0), .X_q0(X_q0), .token_ids_address0(token_ids_address0), .token_ids_ce0(token_ids_ce0), .token_ids_q0(token_ids_q0),
  .gelu_lut_0(gelu_lut_mem[0]), .gelu_lut_1(gelu_lut_mem[1]), .gelu_lut_2(gelu_lut_mem[2]), .gelu_lut_3(gelu_lut_mem[3]), .gelu_lut_4(gelu_lut_mem[4]), .gelu_lut_5(gelu_lut_mem[5]), .gelu_lut_6(gelu_lut_mem[6]), .gelu_lut_7(gelu_lut_mem[7]),
  .gelu_lut_8(gelu_lut_mem[8]), .gelu_lut_9(gelu_lut_mem[9]), .gelu_lut_10(gelu_lut_mem[10]), .gelu_lut_11(gelu_lut_mem[11]), .gelu_lut_12(gelu_lut_mem[12]), .gelu_lut_13(gelu_lut_mem[13]), .gelu_lut_14(gelu_lut_mem[14]), .gelu_lut_15(gelu_lut_mem[15]),
  .gelu_lut_16(gelu_lut_mem[16]), .gelu_lut_17(gelu_lut_mem[17]), .gelu_lut_18(gelu_lut_mem[18]), .gelu_lut_19(gelu_lut_mem[19]), .gelu_lut_20(gelu_lut_mem[20]), .gelu_lut_21(gelu_lut_mem[21]), .gelu_lut_22(gelu_lut_mem[22]), .gelu_lut_23(gelu_lut_mem[23]),
  .gelu_lut_24(gelu_lut_mem[24]), .gelu_lut_25(gelu_lut_mem[25]), .gelu_lut_26(gelu_lut_mem[26]), .gelu_lut_27(gelu_lut_mem[27]), .gelu_lut_28(gelu_lut_mem[28]), .gelu_lut_29(gelu_lut_mem[29]), .gelu_lut_30(gelu_lut_mem[30]), .gelu_lut_31(gelu_lut_mem[31]),
  .gelu_lut_32(gelu_lut_mem[32]), .gelu_lut_33(gelu_lut_mem[33]), .gelu_lut_34(gelu_lut_mem[34]), .gelu_lut_35(gelu_lut_mem[35]), .gelu_lut_36(gelu_lut_mem[36]), .gelu_lut_37(gelu_lut_mem[37]), .gelu_lut_38(gelu_lut_mem[38]), .gelu_lut_39(gelu_lut_mem[39]),
  .gelu_lut_40(gelu_lut_mem[40]), .gelu_lut_41(gelu_lut_mem[41]), .gelu_lut_42(gelu_lut_mem[42]), .gelu_lut_43(gelu_lut_mem[43]), .gelu_lut_44(gelu_lut_mem[44]), .gelu_lut_45(gelu_lut_mem[45]), .gelu_lut_46(gelu_lut_mem[46]), .gelu_lut_47(gelu_lut_mem[47]),
  .gelu_lut_48(gelu_lut_mem[48]), .gelu_lut_49(gelu_lut_mem[49]), .gelu_lut_50(gelu_lut_mem[50]), .gelu_lut_51(gelu_lut_mem[51]), .gelu_lut_52(gelu_lut_mem[52]), .gelu_lut_53(gelu_lut_mem[53]), .gelu_lut_54(gelu_lut_mem[54]), .gelu_lut_55(gelu_lut_mem[55]),
  .gelu_lut_56(gelu_lut_mem[56]), .gelu_lut_57(gelu_lut_mem[57]), .gelu_lut_58(gelu_lut_mem[58]), .gelu_lut_59(gelu_lut_mem[59]), .gelu_lut_60(gelu_lut_mem[60]), .gelu_lut_61(gelu_lut_mem[61]), .gelu_lut_62(gelu_lut_mem[62]), .gelu_lut_63(gelu_lut_mem[63]),
  .gelu_lut_64(gelu_lut_mem[64]), .gelu_lut_65(gelu_lut_mem[65]), .gelu_lut_66(gelu_lut_mem[66]), .gelu_lut_67(gelu_lut_mem[67]), .gelu_lut_68(gelu_lut_mem[68]), .gelu_lut_69(gelu_lut_mem[69]), .gelu_lut_70(gelu_lut_mem[70]), .gelu_lut_71(gelu_lut_mem[71]),
  .gelu_lut_72(gelu_lut_mem[72]), .gelu_lut_73(gelu_lut_mem[73]), .gelu_lut_74(gelu_lut_mem[74]), .gelu_lut_75(gelu_lut_mem[75]), .gelu_lut_76(gelu_lut_mem[76]), .gelu_lut_77(gelu_lut_mem[77]), .gelu_lut_78(gelu_lut_mem[78]), .gelu_lut_79(gelu_lut_mem[79]),
  .gelu_lut_80(gelu_lut_mem[80]), .gelu_lut_81(gelu_lut_mem[81]), .gelu_lut_82(gelu_lut_mem[82]), .gelu_lut_83(gelu_lut_mem[83]), .gelu_lut_84(gelu_lut_mem[84]), .gelu_lut_85(gelu_lut_mem[85]), .gelu_lut_86(gelu_lut_mem[86]), .gelu_lut_87(gelu_lut_mem[87]),
  .gelu_lut_88(gelu_lut_mem[88]), .gelu_lut_89(gelu_lut_mem[89]), .gelu_lut_90(gelu_lut_mem[90]), .gelu_lut_91(gelu_lut_mem[91]), .gelu_lut_92(gelu_lut_mem[92]), .gelu_lut_93(gelu_lut_mem[93]), .gelu_lut_94(gelu_lut_mem[94]), .gelu_lut_95(gelu_lut_mem[95]),
  .gelu_lut_96(gelu_lut_mem[96]), .gelu_lut_97(gelu_lut_mem[97]), .gelu_lut_98(gelu_lut_mem[98]), .gelu_lut_99(gelu_lut_mem[99]), .gelu_lut_100(gelu_lut_mem[100]), .gelu_lut_101(gelu_lut_mem[101]), .gelu_lut_102(gelu_lut_mem[102]), .gelu_lut_103(gelu_lut_mem[103]),
  .gelu_lut_104(gelu_lut_mem[104]), .gelu_lut_105(gelu_lut_mem[105]), .gelu_lut_106(gelu_lut_mem[106]), .gelu_lut_107(gelu_lut_mem[107]), .gelu_lut_108(gelu_lut_mem[108]), .gelu_lut_109(gelu_lut_mem[109]), .gelu_lut_110(gelu_lut_mem[110]), .gelu_lut_111(gelu_lut_mem[111]),
  .gelu_lut_112(gelu_lut_mem[112]), .gelu_lut_113(gelu_lut_mem[113]), .gelu_lut_114(gelu_lut_mem[114]), .gelu_lut_115(gelu_lut_mem[115]), .gelu_lut_116(gelu_lut_mem[116]), .gelu_lut_117(gelu_lut_mem[117]), .gelu_lut_118(gelu_lut_mem[118]), .gelu_lut_119(gelu_lut_mem[119]),
  .gelu_lut_120(gelu_lut_mem[120]), .gelu_lut_121(gelu_lut_mem[121]), .gelu_lut_122(gelu_lut_mem[122]), .gelu_lut_123(gelu_lut_mem[123]), .gelu_lut_124(gelu_lut_mem[124]), .gelu_lut_125(gelu_lut_mem[125]), .gelu_lut_126(gelu_lut_mem[126]), .gelu_lut_127(gelu_lut_mem[127]),
  .gelu_lut_128(gelu_lut_mem[128]), .gelu_lut_129(gelu_lut_mem[129]), .gelu_lut_130(gelu_lut_mem[130]), .gelu_lut_131(gelu_lut_mem[131]), .gelu_lut_132(gelu_lut_mem[132]), .gelu_lut_133(gelu_lut_mem[133]), .gelu_lut_134(gelu_lut_mem[134]), .gelu_lut_135(gelu_lut_mem[135]),
  .gelu_lut_136(gelu_lut_mem[136]), .gelu_lut_137(gelu_lut_mem[137]), .gelu_lut_138(gelu_lut_mem[138]), .gelu_lut_139(gelu_lut_mem[139]), .gelu_lut_140(gelu_lut_mem[140]), .gelu_lut_141(gelu_lut_mem[141]), .gelu_lut_142(gelu_lut_mem[142]), .gelu_lut_143(gelu_lut_mem[143]),
  .gelu_lut_144(gelu_lut_mem[144]), .gelu_lut_145(gelu_lut_mem[145]), .gelu_lut_146(gelu_lut_mem[146]), .gelu_lut_147(gelu_lut_mem[147]), .gelu_lut_148(gelu_lut_mem[148]), .gelu_lut_149(gelu_lut_mem[149]), .gelu_lut_150(gelu_lut_mem[150]), .gelu_lut_151(gelu_lut_mem[151]),
  .gelu_lut_152(gelu_lut_mem[152]), .gelu_lut_153(gelu_lut_mem[153]), .gelu_lut_154(gelu_lut_mem[154]), .gelu_lut_155(gelu_lut_mem[155]), .gelu_lut_156(gelu_lut_mem[156]), .gelu_lut_157(gelu_lut_mem[157]), .gelu_lut_158(gelu_lut_mem[158]), .gelu_lut_159(gelu_lut_mem[159]),
  .gelu_lut_160(gelu_lut_mem[160]), .gelu_lut_161(gelu_lut_mem[161]), .gelu_lut_162(gelu_lut_mem[162]), .gelu_lut_163(gelu_lut_mem[163]), .gelu_lut_164(gelu_lut_mem[164]), .gelu_lut_165(gelu_lut_mem[165]), .gelu_lut_166(gelu_lut_mem[166]), .gelu_lut_167(gelu_lut_mem[167]),
  .gelu_lut_168(gelu_lut_mem[168]), .gelu_lut_169(gelu_lut_mem[169]), .gelu_lut_170(gelu_lut_mem[170]), .gelu_lut_171(gelu_lut_mem[171]), .gelu_lut_172(gelu_lut_mem[172]), .gelu_lut_173(gelu_lut_mem[173]), .gelu_lut_174(gelu_lut_mem[174]), .gelu_lut_175(gelu_lut_mem[175]),
  .gelu_lut_176(gelu_lut_mem[176]), .gelu_lut_177(gelu_lut_mem[177]), .gelu_lut_178(gelu_lut_mem[178]), .gelu_lut_179(gelu_lut_mem[179]), .gelu_lut_180(gelu_lut_mem[180]), .gelu_lut_181(gelu_lut_mem[181]), .gelu_lut_182(gelu_lut_mem[182]), .gelu_lut_183(gelu_lut_mem[183]),
  .gelu_lut_184(gelu_lut_mem[184]), .gelu_lut_185(gelu_lut_mem[185]), .gelu_lut_186(gelu_lut_mem[186]), .gelu_lut_187(gelu_lut_mem[187]), .gelu_lut_188(gelu_lut_mem[188]), .gelu_lut_189(gelu_lut_mem[189]), .gelu_lut_190(gelu_lut_mem[190]), .gelu_lut_191(gelu_lut_mem[191]),
  .gelu_lut_192(gelu_lut_mem[192]), .gelu_lut_193(gelu_lut_mem[193]), .gelu_lut_194(gelu_lut_mem[194]), .gelu_lut_195(gelu_lut_mem[195]), .gelu_lut_196(gelu_lut_mem[196]), .gelu_lut_197(gelu_lut_mem[197]), .gelu_lut_198(gelu_lut_mem[198]), .gelu_lut_199(gelu_lut_mem[199]),
  .gelu_lut_200(gelu_lut_mem[200]), .gelu_lut_201(gelu_lut_mem[201]), .gelu_lut_202(gelu_lut_mem[202]), .gelu_lut_203(gelu_lut_mem[203]), .gelu_lut_204(gelu_lut_mem[204]), .gelu_lut_205(gelu_lut_mem[205]), .gelu_lut_206(gelu_lut_mem[206]), .gelu_lut_207(gelu_lut_mem[207]),
  .gelu_lut_208(gelu_lut_mem[208]), .gelu_lut_209(gelu_lut_mem[209]), .gelu_lut_210(gelu_lut_mem[210]), .gelu_lut_211(gelu_lut_mem[211]), .gelu_lut_212(gelu_lut_mem[212]), .gelu_lut_213(gelu_lut_mem[213]), .gelu_lut_214(gelu_lut_mem[214]), .gelu_lut_215(gelu_lut_mem[215]),
  .gelu_lut_216(gelu_lut_mem[216]), .gelu_lut_217(gelu_lut_mem[217]), .gelu_lut_218(gelu_lut_mem[218]), .gelu_lut_219(gelu_lut_mem[219]), .gelu_lut_220(gelu_lut_mem[220]), .gelu_lut_221(gelu_lut_mem[221]), .gelu_lut_222(gelu_lut_mem[222]), .gelu_lut_223(gelu_lut_mem[223]),
  .gelu_lut_224(gelu_lut_mem[224]), .gelu_lut_225(gelu_lut_mem[225]), .gelu_lut_226(gelu_lut_mem[226]), .gelu_lut_227(gelu_lut_mem[227]), .gelu_lut_228(gelu_lut_mem[228]), .gelu_lut_229(gelu_lut_mem[229]), .gelu_lut_230(gelu_lut_mem[230]), .gelu_lut_231(gelu_lut_mem[231]),
  .gelu_lut_232(gelu_lut_mem[232]), .gelu_lut_233(gelu_lut_mem[233]), .gelu_lut_234(gelu_lut_mem[234]), .gelu_lut_235(gelu_lut_mem[235]), .gelu_lut_236(gelu_lut_mem[236]), .gelu_lut_237(gelu_lut_mem[237]), .gelu_lut_238(gelu_lut_mem[238]), .gelu_lut_239(gelu_lut_mem[239]),
  .gelu_lut_240(gelu_lut_mem[240]), .gelu_lut_241(gelu_lut_mem[241]), .gelu_lut_242(gelu_lut_mem[242]), .gelu_lut_243(gelu_lut_mem[243]), .gelu_lut_244(gelu_lut_mem[244]), .gelu_lut_245(gelu_lut_mem[245]), .gelu_lut_246(gelu_lut_mem[246]), .gelu_lut_247(gelu_lut_mem[247]),
  .gelu_lut_248(gelu_lut_mem[248]), .gelu_lut_249(gelu_lut_mem[249]), .gelu_lut_250(gelu_lut_mem[250]), .gelu_lut_251(gelu_lut_mem[251]), .gelu_lut_252(gelu_lut_mem[252]), .gelu_lut_253(gelu_lut_mem[253]), .gelu_lut_254(gelu_lut_mem[254]), .gelu_lut_255(gelu_lut_mem[255]),
  .embed_lut_0_address0(embed_lut_0_address0), .embed_lut_0_ce0(embed_lut_0_ce0), .embed_lut_0_q0(embed_lut_0_q0), .embed_lut_1_address0(embed_lut_1_address0), .embed_lut_1_ce0(embed_lut_1_ce0), .embed_lut_1_q0(embed_lut_1_q0),
  .embed_lut_2_address0(embed_lut_2_address0), .embed_lut_2_ce0(embed_lut_2_ce0), .embed_lut_2_q0(embed_lut_2_q0), .embed_lut_3_address0(embed_lut_3_address0), .embed_lut_3_ce0(embed_lut_3_ce0), .embed_lut_3_q0(embed_lut_3_q0),
  .embed_lut_4_address0(embed_lut_4_address0), .embed_lut_4_ce0(embed_lut_4_ce0), .embed_lut_4_q0(embed_lut_4_q0), .embed_lut_5_address0(embed_lut_5_address0), .embed_lut_5_ce0(embed_lut_5_ce0), .embed_lut_5_q0(embed_lut_5_q0),
  .embed_lut_6_address0(embed_lut_6_address0), .embed_lut_6_ce0(embed_lut_6_ce0), .embed_lut_6_q0(embed_lut_6_q0), .embed_lut_7_address0(embed_lut_7_address0), .embed_lut_7_ce0(embed_lut_7_ce0), .embed_lut_7_q0(embed_lut_7_q0),
  .gelu_out_address0(gelu_out_address0), .gelu_out_ce0(gelu_out_ce0), .gelu_out_we0(gelu_out_we0), .gelu_out_d0(gelu_out_d0),
  .embed_out_address0(embed_out_address0), .embed_out_ce0(embed_out_ce0), .embed_out_we0(embed_out_we0), .embed_out_d0(embed_out_d0)
);
endmodule


