#include "layernorm_kernel.hpp"

static ap_fixed<24,12> rsqrt_newton(ap_fixed<24,12> x) {
#pragma HLS INLINE
    ap_fixed<24,12> y = 1.0;
    if (x < 1.0) y = 1.4142;
    for (int i=0;i<2;++i) {
#pragma HLS UNROLL
        y = y * (ap_fixed<24,12>(1.5) - ap_fixed<24,12>(0.5)*x*y*y);
    }
    return y;
}

void layernorm_kernel(const int8_t_hls X[LN_DIM], int8_t_hls Y[LN_DIM]) {
#pragma HLS ARRAY_PARTITION variable=X complete dim=1
    ap_fixed<24,12> sum=0, sq_sum=0;
accum:
    for (int i=0;i<LN_DIM;++i) {
#pragma HLS PIPELINE II=1
        ap_fixed<24,12> x=X[i]; sum+=x; sq_sum+=x*x;
    }
    ap_fixed<24,12> mean=sum/LN_DIM;
    ap_fixed<24,12> var=sq_sum/LN_DIM-mean*mean+ap_fixed<24,12>(0.0625);
    if (var < 0.5) var=0.5; if (var > 8.0) var=8.0;
    ap_fixed<24,12> inv=rsqrt_newton(var);
norm:
    for (int i=0;i<LN_DIM;++i) {
#pragma HLS PIPELINE II=1
        int16_t_hls q=(int16_t_hls)((ap_fixed<24,12>(X[i])-mean)*inv*16);
        Y[i]=clamp_signed<int16_t_hls>(q,-128,127);
    }
}
