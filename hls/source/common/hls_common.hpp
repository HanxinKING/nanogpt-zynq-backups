#pragma once

#include <ap_int.h>
#include <ap_fixed.h>

typedef ap_int<8>  int8_t_hls;
typedef ap_int<16> int16_t_hls;
typedef ap_int<32> int32_t_hls;
typedef ap_uint<8> uint8_t_hls;
typedef ap_uint<16> uint16_t_hls;

template <typename T>
static T clamp_signed(T v, T lo, T hi) {
#pragma HLS INLINE
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}
