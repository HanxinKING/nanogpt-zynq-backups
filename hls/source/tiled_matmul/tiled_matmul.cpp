#include "tiled_matmul.hpp"

void tiled_matmul_kernel(const int8_t_hls A[TM_ROWS][TM_K],
                         const int8_t_hls B[TM_K][TM_COLS],
                         int32_t_hls C[TM_ROWS][TM_COLS]) {
#pragma HLS ARRAY_PARTITION variable=A complete dim=2
#pragma HLS ARRAY_PARTITION variable=B complete dim=1
#pragma HLS ARRAY_PARTITION variable=C complete dim=2
tile_i:
    for (int ii = 0; ii < TM_ROWS; ii += TM_TILE) {
    tile_j:
        for (int jj = 0; jj < TM_COLS; jj += TM_TILE) {
            int32_t_hls acc[TM_TILE][TM_TILE];
#pragma HLS ARRAY_PARTITION variable=acc complete dim=0
        init:
            for (int i = 0; i < TM_TILE; ++i)
                for (int j = 0; j < TM_TILE; ++j) {
#pragma HLS UNROLL
                    acc[i][j] = 0;
                }
        dot:
            for (int k = 0; k < TM_K; ++k) {
#pragma HLS PIPELINE II=1
                for (int i = 0; i < TM_TILE; ++i)
                    for (int j = 0; j < TM_TILE; ++j) {
#pragma HLS UNROLL
                        acc[i][j] += A[ii+i][k] * B[k][jj+j];
                    }
            }
        store:
            for (int i = 0; i < TM_TILE; ++i)
                for (int j = 0; j < TM_TILE; ++j) {
#pragma HLS UNROLL
                    C[ii+i][jj+j] = acc[i][j];
                }
        }
    }
}
