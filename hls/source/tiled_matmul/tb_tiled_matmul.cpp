#include "tiled_matmul.hpp"
#include <iostream>
int main() {
    int8_t_hls A[TM_ROWS][TM_K], B[TM_K][TM_COLS];
    int32_t_hls C[TM_ROWS][TM_COLS];
    int errors = 0;
    for (int i=0;i<TM_ROWS;++i) for (int k=0;k<TM_K;++k) A[i][k]=(i+k)%8-4;
    for (int k=0;k<TM_K;++k) for (int j=0;j<TM_COLS;++j) B[k][j]=(j-k)%8;
    tiled_matmul_kernel(A,B,C);
    for (int i=0;i<TM_ROWS;++i) for (int j=0;j<TM_COLS;++j) {
        int ref=0; for (int k=0;k<TM_K;++k) ref+=(int)A[i][k]*(int)B[k][j];
        if ((int)C[i][j]!=ref) ++errors;
    }
    std::cout << "TB_TILED_MATMUL " << (errors ? "FAIL" : "PASS") << "\n";
    return errors ? 1 : 0;
}
