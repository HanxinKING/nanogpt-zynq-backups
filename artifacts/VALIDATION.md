# QKT MAC8 + QKV/Projection16 + FFN64, 100 MHz

## Change

- Q head and K head reads use aligned 64-bit DDR beats.
- QK transpose dot product uses eight INT8 products per iteration.
- A 64-dimensional head requires 8 iterations instead of 16.
- The signed-off 100 MHz requantization pipeline is retained unchanged.

## Timing And Resources

- Clock: 100.000 MHz with 0.750 ns setup uncertainty.
- WNS: +0.181 ns; TNS: 0.000 ns; WHS: +0.036 ns.
- LUT: 27,630 / 53,200 (51.94%).
- FF: 31,892 / 106,400 (29.97%).
- BRAM: 109 / 140 (77.86%).
- DSP: 114 / 220 (51.82%).
- Bitstream SHA256: BB17CAB47AEFE0D41D1E77794F06E9CBC7F5D663A5DDD889B1E64A83F9E61567.

## Validation

- ModelSim layers 0 through 5: all Q/K/V/Attention/Projection comparisons mismatch=0.
- Board six-layer hidden: mismatch=0/4224 bytes.
- Three consecutive short generations produced identical tokens and stable profiles.
- Attention: about 978,093 -> 745,103 ticks, 1.313x faster.
- Full profile: about 44,550,150 -> 43,151,071 ticks, 1.032x faster.
- Versus the 75 MHz QKV16 build: 1.260x overall.
- Estimated generation rate: 7.72 characters/s.
- Board 200-token sequence versus Python Q30 reference: mismatch=0/200.
