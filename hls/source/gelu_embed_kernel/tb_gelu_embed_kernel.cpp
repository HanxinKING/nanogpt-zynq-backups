#include "gelu_embed_kernel.hpp"
#include <iostream>
int main() {
 int8_t_hls X[GE_LEN],L[256],E[EMB_VOCAB][EMB_DIM],GO[GE_LEN],EO[EMB_DIM]; uint8_t_hls T[EMB_DIM];
 for(int i=0;i<GE_LEN;++i) X[i]=(i%31)-15; for(int i=0;i<256;++i) L[i]=i>127?63:-63;
 for(int r=0;r<EMB_VOCAB;++r) for(int c=0;c<EMB_DIM;++c) E[r][c]=(r+c)%16;
 for(int i=0;i<EMB_DIM;++i) T[i]=i;
 gelu_embed_kernel(X,T,L,E,GO,EO);
 for(int i=0;i<GE_LEN;++i) if(GO[i]!=L[(uint8_t_hls)X[i]]) return 1;
 for(int i=0;i<EMB_DIM;++i) if(EO[i]!=E[T[i]][i]) return 1;
 std::cout << "TB_GELU_EMBED PASS\n"; return 0;
}
