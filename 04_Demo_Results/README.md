# 演示和答辩时展示的结果

建议按以下顺序录屏：

1. VSCode：执行 INT8 量化，展示量化模块数、PPL 回退和输出包。
2. VSCode：输入 prompt，展示字符、输入 token id、逐步输出 token id 和生成文本。
3. Vivado：打开 Block Design，说明 PS、DDR、AXI 和 PL Transformer 数据流。
4. Vivado：打开已签核 timing/utilization 报告，展示 100 MHz、WNS `+0.181 ns`、TNS `0`。
5. Vitis：展示 `ps7_cortexa9_0` platform 和 `main.c` 中的 token 编解码、DDR 调度及 PL 启动逻辑。
6. 最后展示板级结果：六层 hidden `0/4224` mismatch、200 token `0/200` mismatch、约 `7.72 char/s`。

正式证据仍以根目录 `PERFORMANCE_RESOURCES.md`、`artifacts/VALIDATION.md` 和 post-route 报告为准。
