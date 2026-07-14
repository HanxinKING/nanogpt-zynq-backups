# Vitis PS 工程与 PS/PL 联调

本目录把 Vivado 导出的 Zynq 硬件平台导入 Vitis Classic 2025.2，并提供可在软件内手动点击、查看和编译的 PS 裸机应用。

## Vitis 在本工程中的作用

- Vivado 负责 PL：查看 Block Design、RTL、综合、实现和 bitstream。
- Vitis 负责 PS：基于 XSA/BSP 编译 ARM Cortex-A9 裸机程序，生成可下载到 Zynq PS 的 ELF。
- VSCode/Python 负责模型侧：INT8 量化、Prompt 输入、输入/输出 token 展示和签核检查。

PS 程序负责字符/token 编解码、DDR 地址与权重镜像调度、启动 PL、读取 argmax token，并通过 UART 输出。Vitis 不执行 Python 量化，也不代替 Vivado 综合 PL。

## 直接手动点击

1. 在根目录双击 `nanoGPT_Zynq_演示工程.code-workspace`。
2. VSCode 点击 **终端 -> 运行任务 -> 06 打开 Vitis PS Workspace**。
3. 也可以直接双击本目录的 `open_vitis.ps1`；实际启动器为 `open_vitis_classic.cmd`。
4. 在 Vitis 左下角 **Assistant** 选择 `ps_mailbox_runner_vitis`。
5. 点击 **Project -> Build All**，或按 `Ctrl+B`。
6. 需要完全重编译时，点击 **Project -> Clean... -> Clean all projects -> Start a build immediately -> Clean**。

构建成功产物：

- ELF：`workspace/ps_mailbox_runner_vitis/Debug/ps_mailbox_runner_vitis.elf`
- Size：`workspace/ps_mailbox_runner_vitis/Debug/ps_mailbox_runner_vitis.elf.size`
- GUI 构建日志：`workspace/ps_mailbox_runner_vitis/Debug/ps_mailbox_runner_vitis_Debug.build.ui.log`

## 从硬件平台重新生成

在 VSCode 点击 **终端 -> 运行任务 -> 05 创建或刷新 Vitis PS Workspace**。该任务会：

1. 从正常 Vivado 工程导出 `hardware/nanogpt_qkt8_100mhz.xsa`。
2. 创建 `nanogpt_qkt8_platform`、`ps7_cortexa9_0` 和 standalone domain/BSP。
3. 创建 `ps_mailbox_runner_vitis` 应用工程并导入 `main.c`、`startup.S`、`lscript.ld`。
4. 固化 Cortex-A9 hard-float 编译/链接参数和 Windows Size 后处理命令。

## 当前验证

- Vitis Classic 2025.2 GUI：可启动、可选工程、可 Clean、可 Build All。
- GUI Build：`Build Finished`，错误数 `0`。
- ELF SHA256：`1F828C34C4C58A42D4C2897FA01FEB662F40C34DDBFD5B9B8111E2F2C36278E9`。
- ELF size：text `13552`、data `8`、bss `16392`、总计 `29952` 字节。

板卡下载/运行仍需要连接实际 Zynq 板、JTAG 和 UART；未连接硬件时可以完成平台查看和软件编译，但不能证明板上 PS/PL 联调运行。
