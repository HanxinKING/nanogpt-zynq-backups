# Vitis HLS 可编辑工程

`source/` 是 VSCode 可直接编辑的 HLS C++，并非自动生成的 Verilog 副本。

| 模块 | 设计文件 | 测试文件 | 顶层函数 |
| --- | --- | --- | --- |
| LayerNorm | `source/layernorm_kernel/layernorm_kernel.cpp` | `source/layernorm_kernel/tb_layernorm_kernel.cpp` | `layernorm_kernel` |
| GELU + Token Embedding | `source/gelu_embed_kernel/gelu_embed_kernel.cpp` | `source/gelu_embed_kernel/tb_gelu_embed_kernel.cpp` | `gelu_embed_kernel` |
| 16x16 INT8 MatMul | `source/tiled_matmul/tiled_matmul.cpp` | `source/tiled_matmul/tb_tiled_matmul.cpp` | `tiled_matmul_kernel` |
| 多头注意力 | `source/mha_kernel/mha_kernel.cpp` | `source/mha_kernel/tb_mha_kernel.cpp` | `mha_kernel` |

公共定点类型、INT8 饱和裁剪在 `source/common/hls_common.hpp`。

## 手动创建 HLS 组件

1. 双击 `F:\Vivado2025.2\2025.2\Vitis\bin\vitis.bat`。
2. 在 **Open Folder** 选择仓库内的 `hls` 目录。
3. 点 **Vitis → New HLS Component → Empty HLS Component**。
4. 组件名分别为 `layernorm_hls`、`gelu_embed_hls`、`tiled_matmul_hls`、`mha_hls`。
5. 在 **Source Files** 加入表中的设计 `.cpp`；在 **Test Bench Files** 加入表中的 `tb_*.cpp`；填写对应顶层函数。
6. Hardware 搜索并选择 `xc7z020clg484-2`。
7. Settings 填 `10ns`，保持 `flow_target=vivado` 与 `package.output.format=ip_catalog`。
8. 左侧依次点击 **C Simulation → Run**、**C Synthesis → Run**。综合后 Package 的 `ip_catalog` 输出可作为 Vivado IP Repository 导入。

## 已创建组件

`layernorm_hls/` 已通过上述图形向导创建，已配置为 `xc7z020clg484-2`、10ns、IP Catalog。配置文件为 `layernorm_hls/hls_config.cfg`。

## 当前 Vitis 安装问题

本机 Vitis Unified IDE 2025.2 的 GUI 执行 C 仿真时错误调用 Unix 版 `Vitis/bin/loader`；Windows CMD 应调用 `loader.bat`，所以报“不是内部或外部命令”。这是启动器问题，尚未进入 C++ 编译。复现日志：

`layernorm_hls/layernorm_kernel/logs/hls_run_csim.log`

不要将这一错误误判为 LayerNorm 或 INT8 算法错误。
