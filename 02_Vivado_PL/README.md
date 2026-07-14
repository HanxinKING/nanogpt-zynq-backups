# Vivado PL 正常工程

点击 `open_vivado_project.ps1`，或在 VSCode 中运行任务 `04 打开 Vivado PL 工程`。

真实工程位置：`../fpga/nano_gpt/nano_gpt.xpr`。

打开后可在 Vivado 中手动点击：

1. **IP Integrator -> Open Block Design**：查看 Zynq PS、DDR、AXI DMA、SmartConnect 与 PL Transformer 核连接。
2. **Flow Navigator -> Run Synthesis**：重新综合。
3. **Run Implementation**：布局布线。
4. **Generate Bitstream**：生成 bitstream。
5. **Reports -> Timing/Utilization**：查看 WNS、TNS 和资源。

工程当前已验证 `TOP=system_wrapper`、146 个源文件、2 个约束文件、缺失引用 0。重新实现耗时较长；教学查看不要求先重跑。
