#include "gelu_embed_kernel.hpp"
void gelu_embed_kernel(const int8_t_hls X[GE_LEN], const uint8_t_hls token_ids[EMB_DIM],
                       const int8_t_hls gelu_lut[256], const int8_t_hls embed_lut[EMB_VOCAB][EMB_DIM],
                       int8_t_hls gelu_out[GE_LEN], int8_t_hls embed_out[EMB_DIM]) {
#pragma HLS ARRAY_PARTITION variable=gelu_lut complete dim=1
#pragma HLS ARRAY_PARTITION variable=embed_lut complete dim=2
gelu:
    for(int i=0;i<GE_LEN;++i) {
#pragma HLS PIPELINE II=1
        gelu_out[i]=gelu_lut[(uint8_t_hls)X[i]];
    }
embed:
    for(int i=0;i<EMB_DIM;++i) {
#pragma HLS PIPELINE II=1
        embed_out[i]=embed_lut[token_ids[i]%EMB_VOCAB][i];
    }
}
