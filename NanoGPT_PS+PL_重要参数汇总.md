# nanoGPT Zynq 最佳版本重要参数汇总

更新时间：2026-07-14  
版本：QKT8 + Q/K/V/Projection16 + FFN64 + 100 MHz + DDR 增量 K/V Cache

## 1. 最终版本定位

这是当前工程中性能、定点一致性和时序均已正式签核的最佳版本。系统采用 PS+PL 协同结构：PS 负责串口交互、字符/token 编解码、DDR 数据组织、PL 寄存器配置和任务调度；PL 负责六层 Transformer 的主要定点计算及 LM Head argmax。

```text
PC 串口输入
  -> PL UART 桥
  -> PS 字符级 tokenizer
  -> PS 写入 DDR 输入、权重地址和控制参数
  -> PL 从 DDR 读取数据并执行六层 INT8 Transformer
  -> PL LM Head argmax 得到 token ID
  -> PS 将 token ID 解码为字符
  -> PL UART 返回 PC
```

## 2. 最终签核结论

| 项目 | 最终结果 |
|---|---:|
| PL 主频 | 100 MHz |
| 路由后 WNS | +0.181 ns |
| 路由后 TNS | 0 ns |
| 路由后 WHS | +0.036 ns |
| 六层 hidden 对齐 | mismatch = 0 / 4224 |
| 板端与 Python Q30 生成对齐 | mismatch = 0 / 200 token |
| 单 token 平均延时 | 129.453 ms |
| 平均生成速度 | 约 7.72 字符/s |
| 相对正式报告中的纯 PS 基准 | 约 16.4 倍 |
| 连续稳定性 | 3 次短文本生成 token 与 profile 一致 |
| INT8 PPL 回退 | 4.0605717546% |
| 量化验收 | PASS，低于 10% 门槛 |

## 3. 板卡与硬件环境

| 项目 | 参数 |
|---|---|
| FPGA SoC | Zynq-7000 XC7Z020 |
| Vivado 目标器件 | `xc7z020clg484-2` |
| 当前适配板卡 | Smart Zynq SP2 V1.2 |
| PS CPU | 双核 ARM Cortex-A9 |
| PL 时钟 | 100.000 MHz |
| 时钟周期 | 10 ns |
| Setup uncertainty | 0.750 ns |
| UART 芯片 | 板载 FT2232H B 通道 |
| 当前电脑串口 | COM11 |
| UART 格式 | 115200 baud、8N1、无流控 |
| PL UART RX / TX | M17 / L17 |
| JTAG | FT2232H A 通道 |

## 4. 模型结构

| 参数 | 数值 |
|---|---:|
| 数据集 | Shakespeare character-level |
| Transformer 层数 `n_layer` | 6 |
| Attention 头数 `n_head` | 6 |
| 隐藏维度 `n_embd` | 384 |
| 单头维度 | 64 |
| FFN 中间维度 | 1536 |
| 最大上下文 `block_size` | 256 token |
| 词表大小 | 65 |
| Bias | false |
| 训练配置中的 dropout | 0.2 |
| 默认生成长度 | 8 token |
| 串口请求最大生成长度 | 200 token |
| 实际可生成长度 | `min(请求 token 数, 256 - prompt token 数)` |
| 输出策略 | Greedy argmax |

本模型是字符级模型。每个英文字母、空格、换行或标点一般对应一个 token，不是按英文单词分词。词表包含 65 个 Shakespeare 数据集字符，不支持汉字。

## 5. INT8 与定点实现

| 对象 | 实现 |
|---|---|
| 权重 | INT8 |
| 激活 | INT8 |
| 矩阵乘累加 | INT32 |
| 重量化乘数 | Q30 |
| LayerNorm 参数 | 定点参数 |
| Attention score | 定点缩放 |
| GELU | LUT |
| Softmax/exp | LUT 近似 |
| LM Head 输出 | 65 类 logits argmax |

量化包统计：

| 项目 | 数值 |
|---|---:|
| 量化模块数 | 27 |
| INT8 权重张量数 | 27 |
| Scale 张量数 | 52 |
| FP32 state 大小 | 43,080,192 B |
| INT8 权重大小 | 10,765,056 B |
| Scale 大小 | 84,588 B |
| INT8 权重与 scale 合计 | 10,849,644 B |
| 相对 FP32 压缩比 | 约 3.97 倍 |

六层主要移位参数：

```text
Q shift         = [13, 12, 12, 12, 12, 12]
K shift         = [13, 13, 13, 12, 12, 12]
V shift         = [13, 13, 12, 12, 12, 12]
Attention proj  = [10, 10, 11, 10, 10, 10]
FFN middle      = [13, 13, 13, 12, 12, 13]
FFN output      = [11, 11, 11, 12, 11, 10]
```

## 6. 量化质量

正式质量基线使用严格硬件对齐的完整 `S256 / D384 / L6` Q30 数据通路：

| 指标 | FP32 | INT8/Q30 |
|---|---:|---:|
| Validation loss | 1.4663740963 | 1.5061770606 |
| PPL | 4.3334937887 | 4.5094584135 |
| PPL 回退 | - | 4.0605717546% |
| 门槛 | - | 小于 10% |
| 结果 | - | PASS |

这里的 4.0606% 是正式硬件对齐结果，不使用较轻的软件 fake-quant 回退代替。

## 7. 主要加速优化

### 7.1 DDR 增量 K/V Cache

- 首次 prompt 执行完整 prefill。
- 后续每个 token 只计算新增的一行。
- 之前的 K/V 结果保存在 DDR，不重新计算整个上下文。
- `ROW_START = active_rows - 1` 表示从新增 token 行开始计算。
- 量化尺度变化时自动完整刷新，避免复用尺度不一致的 Cache。

### 7.2 Q/K/V 与 Projection 16 路并行

- Q、K、V 和输出 Projection 每次并行处理 16 个乘法项。
- 减少矩阵投影循环次数。
- 主要利用 DSP 和宽数据读取提高吞吐量。

### 7.3 FFN64 并行

- FFN 主计算并行度提高到 64 路。
- FFN 仍占单 token 时间的 48.74%，是当前最大耗时模块。

### 7.4 QKT8 Attention

- Q、K head 使用对齐的 64-bit DDR beat 读取。
- QK 转置点积每轮执行 8 个 INT8 乘法。
- 一个 64 维 head 从 16 轮缩短到 8 轮。
- Attention profile 从约 978,093 ticks 降至约 745,103 ticks，提升约 1.313 倍。

### 7.5 100 MHz 重量化流水线

- 保留已经签核的 requantization pipeline。
- 通过寄存器打拍控制组合路径。
- 路由后 100 MHz 时序满足，WNS 为 +0.181 ns。

### 7.6 共享核与时分复用

Q/K/V、QKT Attention、Projection、Residual 和 FFN 位于共享 RTL 层次中，通过状态机时分复用存储和算术资源，避免为每一层复制完整硬件。

## 8. DDR 数据布局

| 地址 | 数据 |
|---|---|
| `0x10000000` | 当前输入 / hidden A |
| `0x10020000` | hidden B |
| `0x10040000` | Q buffer |
| `0x10060000` | K buffer |
| `0x10080000` | V buffer |
| `0x100A0000` | Attention buffer |
| `0x100C0000` | Residual-1 buffer |
| `0x100E0000` | LayerNorm-2 buffer |
| `0x10120000` | Final LayerNorm buffer |
| `0x10140000` | Argmax 输出区 |
| `0x10200000` | K Cache 起始地址 |
| `0x10400000` | V Cache 起始地址 |
| `0x11000000` | 六层权重 |
| `0x11C00000` | Scale 参数 |
| `0x12000000` | Golden hidden |
| `0x12100000` | LUT |
| `0x12200000` | Quality 参数 |
| `0x12E00000` | Debug 区 |
| `0x13000000` | Token Embedding INT8 |
| `0x13010000` | Position Embedding INT8 |
| `0x13028000` | Token Embedding Q30 scale |
| `0x13028400` | Position Embedding Q30 scale |
| `0x00020000` | PS/调试 Mailbox |

K/V Cache 参数：

| 项目 | 数值 |
|---|---:|
| 单层单个 K 或 V | `256 x 384 = 98,304 B` |
| 每层地址步长 | `0x00020000` |
| 6 层 K + 6 层 V | 1,179,648 B，约 1.125 MiB |

## 9. AXI 控制寄存器

PL AXI Lite 基址为 `0x40000000`。

| 偏移 | 名称 | 功能 |
|---|---|---|
| `0x00` | CONTROL | 启动与清除 |
| `0x04` | STATUS | 核状态 |
| `0x30` | MODE | 运算模式 |
| `0x40` | FULL_INPUT | 输入 DDR 地址 |
| `0x44` | FULL_OUTPUT | 输出 DDR 地址 |
| `0x48` | FULL_WEIGHTS | 权重 DDR 地址 |
| `0x4C` | FULL_SCALES | Scale DDR 地址 |
| `0x50` | FULL_DEBUG | Debug DDR 地址 |
| `0x54` | FULL_STATUS | 全模型状态 |
| `0x58` | FULL_STAGE | 当前阶段 |
| `0x60` | HLS_SIGNATURE | IP 核签名 |
| `0x64` | ARGMAX_BASE | Argmax 输出地址 |
| `0x68` | FFN_MID_SHIFT | FFN 中间移位 |
| `0x6C` | FFN_SHIFT | FFN 输出移位 |
| `0x70` | ATTN_LAYER | 当前 Attention 层 |
| `0x74` | UART_STATUS | UART 状态 |
| `0x78` | UART_RX_DATA | UART 接收 |
| `0x7C` | UART_TX_DATA | UART 发送 |
| `0x80` | ACTIVE_ROWS | 当前有效 token 数 |
| `0x84` | ROW_START | 增量计算起始行 |

## 10. 单 Token 耗时

以下数据为 3 次板级测试平均值，ARM Global Timer 为 333.333333 MHz；Transformer 阶段为六层合计。

| 阶段 | Timer ticks | 时间 | 占比 |
|---|---:|---:|---:|
| Embedding | 181,978 | 0.546 ms | 0.42% |
| LayerNorm 1 | 1,269,838 | 3.810 ms | 2.94% |
| Q Projection | 3,415,959 | 10.248 ms | 7.92% |
| K Projection | 3,416,102 | 10.248 ms | 7.92% |
| V Projection | 3,416,172 | 10.249 ms | 7.92% |
| Attention QKT | 4,470,627 | 13.412 ms | 10.36% |
| Output Projection | 3,416,034 | 10.248 ms | 7.92% |
| Residual 1 | 426,227 | 1.279 ms | 0.99% |
| LayerNorm 2 | 1,275,028 | 3.825 ms | 2.95% |
| FFN | 21,029,940 | 63.090 ms | 48.74% |
| Residual 2 | 425,912 | 1.278 ms | 0.99% |
| LM Head | 360,727 | 1.082 ms | 0.84% |
| Guard delay | 46,529 | 0.140 ms | 0.11% |
| **总计** | **43,151,071** | **129.453 ms** | **100%** |

性能关系：

```text
单 token 延时 = 129.453 ms
生成速度      = 1000 / 129.453 = 7.72 token/s
字符级模型中  = 约 7.72 字符/s
```

与 75 MHz QKV16 版本相比，当前版本总体提升约 1.260 倍。

## 11. 路由后资源占用

### 11.1 整机资源

| 资源 | 使用 | 总量 | 占用率 |
|---|---:|---:|---:|
| LUT | 27,630 | 53,200 | 51.94% |
| FF | 31,892 | 106,400 | 29.97% |
| BRAM | 109 | 140 | 77.86% |
| DSP | 114 | 220 | 51.82% |

### 11.2 层次资源

| 层次 | LUT | FF | RAMB36 | RAMB18 | DSP |
|---|---:|---:|---:|---:|---:|
| Whole system | 27,630 | 31,892 | 108 | 2 | 114 |
| Transformer core + HLS wrappers | 22,304 | 24,925 | 106 | 2 | 114 |
| Main shared RTL core | 20,939 | 22,621 | 106 | 2 | 97 |
| LayerNorm HLS wrapper | 841 | 1,390 | 0 | 0 | 17 |
| GELU/Embedding HLS wrapper | 218 | 559 | 0 | 0 | 0 |
| AXI DMA | 1,129 | 1,634 | 2 | 0 | 0 |
| DDR SmartConnect | 3,677 | 4,639 | 0 | 0 | 0 |
| GP0 SmartConnect | 505 | 657 | 0 | 0 | 0 |

Q/K/V、Attention、Projection 和 FFN 是共享核内部的运行阶段，Vivado 无法为这些时分复用阶段分别给出独立、可相加的资源总量。

## 12. PS 软件参数

| 项目 | 参数 |
|---|---|
| Vitis | Vitis Classic 2025.2 |
| Domain | `ps7_cortexa9_0` standalone |
| 编译方式 | Cortex-A9 hard-float |
| PS 功能 | tokenizer、DDR 调度、PL 启动、状态轮询、argmax token 读取、UART 输出 |
| ELF text | 13,552 B |
| ELF data | 8 B |
| ELF bss | 16,392 B |
| ELF 总计 | 29,952 B |
| GUI 构建 | Clean/Build All 通过，错误数 0 |
| ELF SHA256 | `1F828C34C4C58A42D4C2897FA01FEB662F40C34DDBFD5B9B8111E2F2C36278E9` |

## 13. 串口交互协议

| 输入 | 作用 |
|---|---|
| `hello world` + CR | 默认生成 8 个字符 |
| `1:hello world` + CR | 生成 1 个字符 |
| `N:hello world` + CR | 生成 N 个字符，N 为 1 至 200 |
| `echo:hello world` + CR | 只测试 UART 回环，不运行模型 |

启动提示：

```text
nanoGPT Zynq UART ready
> 
```

## 14. 实际 200 Token 示例

测试 prompt：

```text
everything with a man
```

板级生成开头：

```text
 that we have stood
The seal of the sea of the war, the world begins
Of the seass of the seasons of the world,
Which the seals of the sea of the world,
```

该次测试生成 200 token，板端 token 序列与 Python Q30 参考结果 mismatch 为 0/200。

## 15. 验收覆盖范围

- ModelSim 第 0 至第 5 层 Q/K/V/Attention/Projection 全部 mismatch=0。
- 板级六层最终 hidden mismatch=0/4224 bytes。
- 200 token 板端/Python Q30 mismatch=0/200。
- 三次连续短文本运行结果一致。
- 100 MHz 路由后时序通过。
- Vitis PS 工程 Clean/Build All 通过，错误数 0。
- INT8 严格硬件质量 PPL 回退 4.0606%，通过 10% 门槛。

## 16. 关键交付文件

```text
Vivado 工程:
fpga/nano_gpt/nano_gpt.xpr

顶层:
system_wrapper

最终 bitstream:
artifacts/system.bit

硬件描述:
artifacts/system.hwh

路由 checkpoint:
artifacts/system_routed.dcp

时序报告:
artifacts/timing_post_route.rpt

资源报告:
artifacts/utilization_post_route.rpt
artifacts/utilization_hierarchical_post_route.rpt

PS 主程序:
fpga/nano_gpt/baremetal/ps_mailbox_runner/src/main.c

性能报告:
PERFORMANCE_RESOURCES.md

签核报告:
artifacts/VALIDATION.md

Python 量化与 token 演示:
01_VSCode_Python/01_quantize_int8.py
01_VSCode_Python/02_token_console.py
01_VSCode_Python/03_verify_signoff.py
```

最终 bitstream SHA256：

```text
BB17CAB47AEFE0D41D1E77794F06E9CBC7F5D663A5DDD889B1E64A83F9E61567
```

