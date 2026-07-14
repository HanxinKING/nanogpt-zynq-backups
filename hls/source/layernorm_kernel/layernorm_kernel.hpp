#pragma once
#include "../common/hls_common.hpp"
const int LN_DIM = 64;
void layernorm_kernel(const int8_t_hls X[LN_DIM], int8_t_hls Y[LN_DIM]);
