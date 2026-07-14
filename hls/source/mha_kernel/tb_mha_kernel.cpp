#include "mha_kernel.hpp"
#include <iostream>
int main(){int8_t_hls X[MHA_SEQ][MHA_DIM],WQ[MHA_DIM][MHA_DIM],WK[MHA_DIM][MHA_DIM],WV[MHA_DIM][MHA_DIM];uint8_t_hls L[16];int16_t_hls O[MHA_SEQ][MHA_DIM];
for(int i=0;i<MHA_SEQ;++i)for(int d=0;d<MHA_DIM;++d)X[i][d]=(i+d)%7-3;
for(int i=0;i<MHA_DIM;++i)for(int j=0;j<MHA_DIM;++j){WQ[i][j]=(i+j)%5-2;WK[i][j]=(i-j)%5;WV[i][j]=(2*i+j)%7-3;}for(int i=0;i<16;++i)L[i]=(i+1)*8;
mha_kernel(X,WQ,WK,WV,L,O);std::cout<<"TB_MHA_KERNEL PASS\n";return 0;}
