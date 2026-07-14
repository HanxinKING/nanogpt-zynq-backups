# QKT8 100 MHz Performance and Resource Report

## Signoff configuration

- Design: six-layer nanoGPT, DDR incremental KV cache
- PL clock: 100 MHz
- Parallelism: QKT8, Q/K/V/Projection16, FFN64
- Post-route timing: WNS +0.181 ns, TNS 0, WHS +0.036 ns
- Board/Python Q30 generation: 0 mismatches in 200 tokens
- Six-layer hidden validation: 0 mismatches in 4224 values

## Per-token latency

The table is the mean of three board runs. The ARM global timer runs at 333.333333 MHz. Transformer stage values are the sum of all six layers.

| Stage | Mean timer ticks | Time (ms) | Share |
|---|---:|---:|---:|
| Embedding | 181,978 | 0.546 | 0.42% |
| LayerNorm 1 | 1,269,838 | 3.810 | 2.94% |
| Q projection | 3,415,959 | 10.248 | 7.92% |
| K projection | 3,416,102 | 10.248 | 7.92% |
| V projection | 3,416,172 | 10.249 | 7.92% |
| Attention (QKT) | 4,470,627 | 13.412 | 10.36% |
| Output projection | 3,416,034 | 10.248 | 7.92% |
| Residual 1 | 426,227 | 1.279 | 0.99% |
| LayerNorm 2 | 1,275,028 | 3.825 | 2.95% |
| FFN | 21,029,940 | 63.090 | 48.74% |
| Residual 2 | 425,912 | 1.278 | 0.99% |
| LM head | 360,727 | 1.082 | 0.84% |
| Guard delay | 46,529 | 0.140 | 0.11% |
| **Total** | **43,151,071** | **129.453** | **100%** |

This is about 7.72 generated characters/s. Against the measured pure-PS baseline of about 0.47 characters/s, the current PS+PL path is about 16.4x faster.

## Post-route resources

| Hierarchy | LUT | FF | RAMB36 | RAMB18 | DSP |
|---|---:|---:|---:|---:|---:|
| Whole system | 27,630 | 31,892 | 108 | 2 | 114 |
| Transformer core including HLS wrappers | 22,304 | 24,925 | 106 | 2 | 114 |
| Main time-multiplexed RTL core | 20,939 | 22,621 | 106 | 2 | 97 |
| LayerNorm HLS wrapper | 841 | 1,390 | 0 | 0 | 17 |
| GELU/embed HLS wrapper | 218 | 559 | 0 | 0 | 0 |
| AXI DMA | 1,129 | 1,634 | 2 | 0 | 0 |
| DDR SmartConnect | 3,677 | 4,639 | 0 | 0 | 0 |
| GP0 SmartConnect | 505 | 657 | 0 | 0 | 0 |

Device totals are 53,200 LUT, 106,400 FF, 140 BRAM36-equivalent blocks, and 220 DSP. Utilization is 51.94% LUT, 29.97% FF, 77.86% BRAM, and 51.82% DSP.

Q/K/V, QKT attention, projection, residual, and FFN are states inside one shared RTL hierarchy. Their arithmetic and memories are time-multiplexed, so Vivado cannot truthfully assign independent resource totals to those runtime stages. The hierarchy table is the finest reliable post-route split.

