# nanoGPT Zynq QKT8 100 MHz 最终工程

这是当前正式签核的 PS+PL 协同版本，同时包含可复现工程、板级产物、Python 定点参考和配套串口上位机。

## 最终指标

- PL：100 MHz，QKT8、Q/K/V/Projection16、FFN64、DDR 增量 K/V Cache。
- 时序：WNS `+0.181 ns`、TNS `0`、WHS `+0.036 ns`。
- 板级六层 hidden：`mismatch=0/4224`。
- 板端/Python Q30：200 token `mismatch=0/200`。
- 性能：`129.453 ms/token`，约 `7.72 char/s`。
- 质量：FP32 PPL `4.333494`，硬件对齐 INT8 PPL `4.509458`，回退 `4.0606%`。

## 从这里开始

1. 双击 `nanoGPT_Zynq_演示工程.code-workspace`。
2. VSCode 中点击 **终端 -> 运行任务**。
3. 依次运行：
   - `01 生成 INT8 量化包`
   - `02 交互输入 Prompt 并查看 Token`
   - `03 核对签核结果`
   - `04 打开 Vivado PL 工程`
   - `05 创建或刷新 Vitis PS Workspace`
   - `06 打开 Vitis PS Workspace`

详细入口：

- `01_VSCode_Python/README.md`：真实 checkpoint 的 W8A8 INT8 量化、输入 token、输出 token。
- `02_Vivado_PL/README.md`：正常 `.xpr` 工程、Block Design、综合、实现和 bitstream。
- `03_Vitis_PS/README.md`：导出 XSA、生成 Vitis platform、查看 PS 源码和 PS/PL 联调。
- `04_Demo_Results/README.md`：建议录屏顺序与答辩展示口径。
- `host_tools/nanogpt_uart_gui/`：科创课堂串口上位机源码、测试与 Windows EXE。
- `artifacts/`：最终 bitstream、HWH、routed DCP、时序与资源报告。
- `validation/`：200-token 板级输出和三轮性能 profile。
- `NanoGPT_PS+PL_重要参数汇总.md`：模型、DDR、寄存器、性能与资源完整参数。

## 仓库结构

```text
01_VSCode_Python/   Python 量化、FP32/INT8 token 演示
artifacts/          最终 system.bit、system.hwh、DCP、签核报告
fpga/               RTL、约束、IP、DDR 镜像和部署文件
hls/                HLS C/C++ 源码与生成资料
host_tools/         科创课堂 nanoGPT 串口平台
ps/                 Cortex-A9 裸机源码、脚本和 ELF
python/             nanoGPT 原始程序、定点工具和量化结果
reference/          Q30 参数、golden、embedding 和 DDR 镜像
validation/         板级 200-token 与性能测试记录
vitis/              Vitis Classic 2025.2 工程及平台资料
vivado_project/     可直接打开的 Vivado 2025.2 工程源码
```

仓库包含板端部署所需的 INT8 权重、scale、golden、bitstream 和 routed DCP。123 MiB 的 FP32 训练 checkpoint 不参与板端运行，因此未纳入仓库；可按 `python/nanoGPT/README.md` 重新训练生成。

## 正式工程与签核状态

- Vivado：`fpga/nano_gpt/nano_gpt.xpr`
- 顶层：`system_wrapper`
- PL：100 MHz，QKT8、Q/K/V/Projection16、FFN64、DDR incremental K/V cache
- 时序：WNS `+0.181 ns`、TNS `0`、WHS `+0.036 ns`
- 板级六层 hidden：`mismatch=0/4224`
- 板端/Python Q30：200 token `mismatch=0/200`
- 性能：约 `129.453 ms/token`，约 `7.72 char/s`
- Vitis Classic 2025.2：GUI 手动 Clean/Build All 已通过，PS ELF 错误数 `0`

Vitis 手动点击步骤与构建证据见 `03_Vitis_PS/VITIS_GUI_VALIDATION.md`。

原签核 RTL、checkpoint、DDR 镜像、bit/hwh、routed DCP 和报告没有被替换。新增演示输出只写入 `01_VSCode_Python/demo_outputs/`、`03_Vitis_PS/hardware/` 和 `03_Vitis_PS/workspace/`。
