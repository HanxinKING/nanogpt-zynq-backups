#pragma once
#include "../common/hls_common.hpp"

const int TM_ROWS = 16;
const int TM_COLS = 16;
const int TM_K = 16;
const int TM_TILE = 4;

void tiled_matmul_kernel(const int8_t_hls A[TM_ROWS][TM_K],
                         const int8_t_hls B[TM_K][TM_COLS],
                         int32_t_hls C[TM_ROWS][TM_COLS]);
