#pragma once
#include "../common/hls_common.hpp"
const int GE_LEN=64, EMB_VOCAB=32, EMB_DIM=8;
void gelu_embed_kernel(const int8_t_hls X[GE_LEN], const uint8_t_hls token_ids[EMB_DIM],
                       const int8_t_hls gelu_lut[256], const int8_t_hls embed_lut[EMB_VOCAB][EMB_DIM],
                       int8_t_hls gelu_out[GE_LEN], int8_t_hls embed_out[EMB_DIM]);
