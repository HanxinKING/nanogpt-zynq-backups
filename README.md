# nanoGPT-ZYNQ final release

This release contains only the final verified deployment: single-clock 75 MHz, FFN cross-group prefetch, and FFN 32-way parallel execution.

The release was tested over the on-board FTDI UART at 115200 8N1. Prompt `everything with a man` generated 200 characters in 71.075 seconds. All six-layer final-row hidden values matched the reference (96/96 words), and post-route timing passed with WNS +0.332 ns and TNS 0.

## Contents

- `artifacts/`: final bitstream/HWH, final PS program/source, final RTL and measured reports/logs.
- `fpga/ddr_image/`: runtime INT8 DDR image, including model weights, scales, LUTs, input and golden vectors.
- `fpga/overlay/system/`: deployable PL bitstream, hardware handoff and debug probes.
- `fpga/rtl/`: final FFN32 hardware RTL source.
- `fpga/scripts/`: Vivado project-generation script for the final DDR design.
- `ps/`: final bare-metal PS source, ELF and UART/JTAG helper scripts.
- `python/`: nanoGPT model source and INT8 export/evaluation tools.
- `tests/`: final UART deployment and 200-character generation records.

## Deliberately excluded

Old experimental variants, `.bak` files, Vivado cache/run directories, historical debug dumps, and the 123 MB FP32 training checkpoint are intentionally excluded. The deployable INT8 weights required by the board are included as `fpga/ddr_image/weights.bin`.

## Deployment

1. Program `fpga/overlay/system/system.bit` and use its matching `system.hwh`.
2. Load the DDR image files at the addresses defined by `ps/run_ps_mailbox_runner.tcl`.
3. Run `ps/ps_mailbox_runner.elf`.
4. Connect the board UART at 115200 baud, 8 data bits, no parity, 1 stop bit; then send a prompt such as `200:everything with a man` followed by CR/LF.

