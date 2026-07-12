# Final FFN32 75 MHz Board Stage Profile

## Measurement Setup

- Bitstream: `overlay/system/system.bit` (final single-clock 75 MHz FFN32).
- Runner: final `ps_mailbox_runner.elf` with mailbox-only timing probes.
- PS global timer: 333.333 MHz (`APU_FREQ=666666666 / 2`).
- Conversion: `milliseconds = ticks * 3 / 1,000,000`.
- Prompt: `everything with a man`.
- All values below are newly measured on the board on 2026-07-12.

The timing intervals include PS register programming and completion polling for
PL stages. `ln1`, `ln2`, and residual additions execute on PS. `q`, `k`, `v`,
attention, projection, FFN, and LM head include PL execution.

## A/B Correctness Check

The pre-profile PS ELF and the final profiling PS ELF were both run with the
same bitstream, DDR image, prompt, and one generated token. Both returned token
`1`, a space character. Therefore the profile mailbox writes do not change the
direct-mailbox result.

## Prompt Prefill: 21 Rows

Context: `active_rows=21`, `row_start=0`, `kv_incremental=0`.

| Stage, six layers total | Ticks | Time (ms) |
|---|---:|---:|
| LN1 | 27,789,279 | 83.368 |
| Q | 58,228,348 | 174.685 |
| K | 58,235,757 | 174.707 |
| V | 58,235,828 | 174.707 |
| Attention | 60,129,701 | 180.389 |
| Projection | 58,286,087 | 174.858 |
| Residual1 | 8,937,380 | 26.812 |
| LN2 | 29,439,863 | 88.320 |
| FFN | 985,065,258 | 2,955.196 |
| Residual2 | 8,938,859 | 26.817 |
| LM head | 362,412 | 1.087 |
| **Total** | **1,353,648,772** | **4,060.946** |

## K/V Cache Steady State: Last of 8 Tokens

Output tokens are `1 58 46 39 58 1 61 43`, decoding to ` that we`.
The final calculation used `active_rows=28`, `row_start=27`, and
`kv_incremental=1`: only the newly appended row went through the six layers.

| Stage, six layers total | Ticks | Time (ms) | Share |
|---|---:|---:|---:|
| LN1 | 1,269,460 | 3.808 | 1.59% |
| Q | 5,376,108 | 16.128 | 6.72% |
| K | 5,376,218 | 16.129 | 6.72% |
| V | 5,376,320 | 16.129 | 6.72% |
| Attention | 7,270,183 | 21.811 | 9.08% |
| Projection | 5,376,190 | 16.129 | 6.72% |
| Residual1 | 425,901 | 1.278 | 0.53% |
| LN2 | 1,274,041 | 3.822 | 1.59% |
| FFN | 47,328,235 | 141.985 | 59.13% |
| Residual2 | 425,253 | 1.276 | 0.53% |
| LM head | 361,092 | 1.083 | 0.45% |
| Next embedding | 181,432 | 0.544 | 0.23% |
| **Total** | **80,040,433** | **240.121** | **100.00%** |

The measured steady-state compute rate at this 28-character context is
approximately **4.165 characters/s**. FFN is the dominant cost at 59.13%; the
next largest groups are Q/K/V/projection together at 26.88% and attention at
9.08%.

## Evidence

- `profile_ffn32_75mhz_prefill_everything_with_a_man_1.profile.log`
- `profile_ffn32_75mhz_steady_everything_with_a_man_8.profile.log`
- `profile_ffn32_75mhz_steady_everything_with_a_man_8.stdout.log`
- `baseline_preprofile_everything_with_a_man_1.stdout.log`
