#pragma once
#include "../common/hls_common.hpp"
const int MHA_SEQ=16, MHA_DIM=16, MHA_HEADS=4, MHA_HDIM=4;
void mha_kernel(const int8_t_hls X[MHA_SEQ][MHA_DIM], const int8_t_hls WQ[MHA_DIM][MHA_DIM],
                const int8_t_hls WK[MHA_DIM][MHA_DIM], const int8_t_hls WV[MHA_DIM][MHA_DIM],
                const uint8_t_hls softmax_lut[16], int16_t_hls OUT[MHA_SEQ][MHA_DIM]);
