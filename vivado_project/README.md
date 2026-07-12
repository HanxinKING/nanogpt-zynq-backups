# Vivado Rebuild Project

This directory contains the final 75 MHz source project for the XC7Z020CLG484-2 target. It is portable: no personal drive path is required.

## Contents

- `rtl/`: final PL RTL, including the FFN32 core and UART bridge.
- `constraints/`: final 75 MHz timing and UART pin constraints.
- `nano_gpt.srcs/`: Vivado Block Design and IP configuration source files.
- `generated/`: fixed-point `.mem` initialization files used by the PL core.
- `scripts/create_final_75mhz_project.tcl`: creates the local Vivado project and Block Design.

## Create The Project

Open a Vivado Tcl shell in this directory and run:

```tcl
source scripts/create_final_75mhz_project.tcl
```

This creates `nano_gpt.xpr` beside this README. The project is configured for the final 75 MHz implementation. Vivado regenerates `.gen`, `.cache`, `.runs`, and `.Xil` locally; these derived directories are intentionally not distributed.

After creation, run synthesis and implementation normally from Vivado. The final deployable bitstream in `../fpga/overlay/system/` remains the already-verified board image.
