# Final FFN32 Performance Profile

This runner profiles the final 75 MHz FFN32 bitstream without changing model
math, INT8 parameters, DDR addresses, K/V cache behavior, or UART protocol.

## What is measured

The PS global timer is clocked at CPU frequency / 2. `ps7_init.tcl` sets
`APU_FREQ=666666666`, therefore the timer frequency is 333.333 MHz and:

```text
milliseconds = timer_ticks * 3 / 1,000,000
```

For each of the six transformer layers, the runner writes these elapsed counts
to the DDR mailbox:

| Stage | Measurement boundary |
|---|---|
| `ln1`, `ln2` | PS fixed-point layer normalization |
| `q`, `k`, `v` | PS control writes + PL matrix-vector execution + completion polling |
| `attention` | PS control writes + PL cached causal attention + completion polling |
| `projection`, `ffn` | PS control writes + PL execution + completion polling |
| `residual1`, `residual2` | PS fixed-point residual addition |
| `lm_head` | final PS layer normalization + PL fast LM-head argmax |
| `embedding` | preparation of the next INT8 hidden row or full refresh on scale change |

The profile entry represents the latest generated token. With one generated
token it measures the prompt prefill path; with multiple generated tokens it
measures the last incremental K/V-cache step.

## Board procedure

1. Build the runner:

```powershell
& .\scripts\build.ps1
```

2. Run one-token prefill measurement through JTAG:

```powershell
$env:MAILBOX_PROMPT = 'everything with a man'
$env:MAILBOX_MAX_NEW_TOKENS = '1'
& 'F:\Vivado2025.2\2025.2\Vitis\bin\xsct.bat' .\scripts\run_ps_mailbox_runner.tcl
```

3. While the processor remains halted at the completion breakpoint, read the
mailbox profile:

```powershell
& 'F:\Vivado2025.2\2025.2\Vitis\bin\xsct.bat' .\scripts\read_decode_profile.tcl
```

For a steady-state sample, repeat step 2 with `MAILBOX_MAX_NEW_TOKENS=8`.
The generated characters must still match the normal final runner before using
the timings for optimization decisions.

## Mailbox layout

`0x500 + layer * 16 + stage` stores the ten stage counts. `0x560`, `0x561`,
and `0x562` store LM head, embedding update, and guard-delay measurements.
The mailbox is in PS DDR at `0x00020000` and is outside all token/result words.
