#include "layernorm_kernel.hpp"
#include <iostream>
int main() {
  int8_t_hls X[LN_DIM],Y[LN_DIM]; for(int i=0;i<LN_DIM;++i) X[i]=(i%11)-5;
  layernorm_kernel(X,Y); std::cout << "TB_LAYERNORM PASS\n"; return 0;
}
