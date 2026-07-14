#include "mha_kernel.hpp"
static uint8_t_hls lut_weight(int16_t_hls x,const uint8_t_hls lut[16]) {
#pragma HLS INLINE
 int idx=(int)(x+32)>>2; if(idx<0)idx=0; if(idx>15)idx=15; return lut[idx];
}
void mha_kernel(const int8_t_hls X[MHA_SEQ][MHA_DIM], const int8_t_hls WQ[MHA_DIM][MHA_DIM],
                const int8_t_hls WK[MHA_DIM][MHA_DIM], const int8_t_hls WV[MHA_DIM][MHA_DIM],
                const uint8_t_hls softmax_lut[16], int16_t_hls OUT[MHA_SEQ][MHA_DIM]) {
 int16_t_hls Q[MHA_SEQ][MHA_DIM],K[MHA_SEQ][MHA_DIM],V[MHA_SEQ][MHA_DIM];
#pragma HLS ARRAY_PARTITION variable=X complete dim=2
#pragma HLS ARRAY_PARTITION variable=WQ complete dim=1
#pragma HLS ARRAY_PARTITION variable=WK complete dim=1
#pragma HLS ARRAY_PARTITION variable=WV complete dim=1
#pragma HLS ARRAY_PARTITION variable=Q complete dim=2
#pragma HLS ARRAY_PARTITION variable=K complete dim=2
#pragma HLS ARRAY_PARTITION variable=V complete dim=2
proj:
 for(int i=0;i<MHA_SEQ;++i) for(int o=0;o<MHA_DIM;++o) {
#pragma HLS PIPELINE II=1
   int32_t_hls qa=0,ka=0,va=0; for(int d=0;d<MHA_DIM;++d) {qa+=X[i][d]*WQ[d][o];ka+=X[i][d]*WK[d][o];va+=X[i][d]*WV[d][o];}
   Q[i][o]=qa;K[i][o]=ka;V[i][o]=va;
 }
heads:
 for(int h=0;h<MHA_HEADS;++h) for(int i=0;i<MHA_SEQ;++i) {
   uint8_t_hls weight[MHA_SEQ]; int16_t_hls score[MHA_SEQ],max_score=-32768; uint16_t_hls denom=0;
#pragma HLS ARRAY_PARTITION variable=weight complete dim=1
   for(int j=0;j<MHA_SEQ;++j) {int32_t_hls s=0;for(int d=0;d<MHA_HDIM;++d){int z=h*MHA_HDIM+d;s+=Q[i][z]*K[j][z];} score[j]=(j>i)?int16_t_hls(-32768):int16_t_hls(s>>2);if(score[j]>max_score)max_score=score[j];}
   for(int j=0;j<MHA_SEQ;++j){weight[j]=(j>i)?uint8_t_hls(0):lut_weight(score[j]-max_score,softmax_lut);denom+=weight[j];}
   for(int d=0;d<MHA_HDIM;++d){int z=h*MHA_HDIM+d;int32_t_hls a=0;for(int j=0;j<MHA_SEQ;++j)a+=weight[j]*V[j][z];OUT[i][z]=denom?int16_t_hls(a/denom):int16_t_hls(0);}
 }
}
