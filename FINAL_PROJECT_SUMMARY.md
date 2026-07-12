# nanoGPT-ZYNQ 最终工程总结

## 1. 项目结论

本工程完成了一个部署在 Zynq-7020 上的 6 层 INT8 nanoGPT 推理系统。最终板级版本采用 75 MHz 单时钟、DDR 存储权重和中间数据、PS 端串口交互、PL 端 Transformer 计算和 DDR K/V Cache。模型为 Shakespeare 字符级模型：输入英文字符，输出下一个英文字符。

最终版本已完成 200 字符串口生成和六层 hidden 对齐测试。最终提交只保留这一版工程，不包含旧双时钟工程、历史 `.bak` 文件和 Vivado 缓存。

## 2. 最终配置

| 项目 | 最终值 |
|---|---|
| FPGA | XC7Z020 (Zynq-7020) |
| PL 时钟 | 75 MHz |
| 模型结构 | 6 层 Transformer，`d_model=384`，上下文长度 256 |
| 词表 | 65 个 Shakespeare 字符级 token |
| 数值格式 | INT8 权重/激活，定点缩放参数保存在 DDR |
| 生成策略 | Greedy argmax |
| 输入输出 | 板载 FTDI UART，115200 baud，8N1 |
| 最多生成长度 | 200 字符 |
| 最终加速结构 | FFN 跨组预取 + 32 路 FFN 并行 + DDR K/V Cache |

## 3. 系统数据流

```text
PC 串口输入英文 prompt
        |
        v
PS: 字符编码 -> token id -> INT8 embedding 写入 DDR
        |
        v
DDR: 输入 hidden、权重、缩放参数、LUT、K/V Cache、输出 hidden/token
        |
        v
PL: 六层 Transformer INT8 推理 -> LM head argmax
        |
        v
PS: token id 解码为字符 -> UART 输出到 PC
```

DDR 中的主要数据如下。

| 数据 | 作用 |
|---|---|
| `input.bin` | 输入 hidden / 初始测试向量 |
| `weights.bin` | 导出的 INT8 模型权重，约 10.15 MB |
| `scales.bin` | 各层定点缩放参数 |
| `luts.bin` | softmax/GELU 等近似查找表 |
| `golden_final.bin` | 最终 hidden 的 golden 对照数据 |
| `quality_params.bin` | INT8 质量验证参数 |
| K/V Cache | 每层 K/V 保存于 DDR，首轮计算完整 prompt，后续优先只计算新增 token 行 |

## 4. 关键源码

| 文件 | 作用 |
|---|---|
| `fpga/rtl/hls_kernel_chain_axis_full_only_core.v` | PL 端核心：AXI4 DDR 主接口、六层 INT8 Transformer 控制状态机、FFN32 并行乘法和 LM head。 |
| `ps/main.c` | PS 端主程序：UART 字符收发、65 字符 token 编解码、embedding 量化写 DDR、K/V Cache 调度、LM head token 解码。 |
| `ps/run_ps_mailbox_runner.tcl` | JTAG 下载 bitstream/DDR 镜像/ELF，并启动 UART 控制台。 |
| `fpga/scripts/setup_vivado_project_ddr.tcl` | Vivado 工程和 PS7、DDR、AXI、PL 核连接脚本。 |
| `fpga/ddr_image/weights.bin` | 最终上板所需的 INT8 权重镜像。 |
| `python/tools/eval_int8_reference.py` | FP32/INT8 基准质量评估。 |
| `python/tools/simulate_int8_six_layer_sweep.py` | 六层 INT8 定点仿真和对齐分析。 |
| `python/tools/pack_int8_full_ddr_image.py` | 生成 PL 运行所需 DDR 数据镜像。 |

### 4.1 PS 端字符编码和解码

`ps/main.c` 定义 `VOCAB_SIZE=65`、`BLOCK_SIZE=256`、`D_MODEL=384`，使用 `g_itos` 保存 token 到字符的映射，并由 `encode_char()` 将输入字符编码为 token。该模型是字符级模型，不是词级模型。

```c
static int encode_char(char c)
{
    if (c == '\n') return 0;
    if (c == ' ') return 1;
    if (c >= 'A' && c <= 'Z') return 13 + (c - 'A');
    if (c >= 'a' && c <= 'z') return 39 + (c - 'a');
    return -1;
}
```

### 4.2 PS 端 K/V Cache 生成循环

`generate_greedy()` 首先计算整个 prompt。之后 token 的 embedding 缩放未变化时，将 `row_start` 设为新 token 所在行，只让 PL 计算新增行；各层 K/V 结果保存在 DDR。若动态 embedding 缩放发生变化，则为保证数值一致性重新计算完整上下文。

```c
rc = run_full_model_range(n, row_start);
rc = pl_lm_head_argmax_row(LAYER_A_BASE + ((n - 1u) * D_MODEL), &tok);
mailbox_write(MAILBOX_TOKEN_WORD_BASE + generated, (uint32_t)tok);
mailbox_write(MAILBOX_CHAR_WORD_BASE + generated,
              (tok < VOCAB_SIZE) ? (uint32_t)g_itos[tok] : (uint32_t)'?');
tokens[n++] = tok;
```

### 4.3 PL 端 32 路 FFN 并行

核心 RTL 的 `ffn_mul_b0` 至 `ffn_mul_b31` 和 `ffn_prod0` 至 `ffn_prod31` 形成 32 路并行乘法阵列，并强制综合到 DSP。DDR 权重读采用 64-bit AXI burst；`WLOAD_BURST_BEATS=16`，降低逐字读权重带来的等待。

```verilog
logic signed [17:0] ffn_mul_b0;
// ... ffn_mul_b1 ... ffn_mul_b30
logic signed [17:0] ffn_mul_b31;

(* use_dsp = "yes" *) logic signed [42:0] ffn_prod0;
// ... ffn_prod1 ... ffn_prod30
(* use_dsp = "yes" *) logic signed [42:0] ffn_prod31;
```

## 5. INT8 质量指标

以下质量门限来自 `bittrue_fixed_eval/metrics.json`：对 8 个数据块、共 2048 个预测位置执行 FP32 与固定 INT8 对比。该测试用于确认量化误差保持在可接受范围。

| 指标 | FP32 | INT8 / 对比结果 |
|---|---:|---:|
| Loss | 1.576245 | 1.628690 |
| Perplexity (PPL) | 4.836758 | 5.097195 |
| PPL 回退 | - | 5.385% |
| Logits mean absolute error | - | 0.344568 |
| Top-1 match | - | 1837 / 2048 = 89.697% |
| INT8 质量门限 | - | 通过：PPL 回退小于 10% |

另一个全硬件语义质量记录 `hello_world_quality_exact/metrics.md` 显示：FP32 PPL 为 264.060077，W8A8 + q6 LayerNorm + q6 softmax + q8 GELU 的 PPL 为 284.159996，回退 7.612%，同样低于 10% 门限。

## 6. 优化过程与最终性能

| 步骤 | 实现 | 200 字符耗时 | 结果 |
|---|---|---:|---|
| 1 | FFN 跨组预取 | 99.080 s | 正确，逐字符一致 |
| 2 | 75/100 MHz 双时钟 DDR | 113.707 s | 正确但异步 FIFO 使短事务变慢，不作为最终版 |
| 3 | FFN 32 路并行 | 71.075 s | 最终采用，较 FFN16 提升 1.39 倍 |

步骤 3 中，FFN 仿真周期由 493,872 降为 327,864，减少 33.6%。

## 7. 时序和资源指标

最终 75 MHz 实现后的 Vivado post-route 报告如下。

| 指标 | 使用量 | 可用量 | 占用率 |
|---|---:|---:|---:|
| Slice LUT | 25,678 | 53,200 | 48.27% |
| Slice Register | 29,482 | 106,400 | 27.71% |
| Block RAM Tile | 109 | 140 | 77.86% |
| DSP | 102 | 220 | 46.36% |

| 时序指标 | 结果 |
|---|---:|
| WNS | +0.332 ns |
| TNS | 0.000 ns |
| WHS | +0.036 ns |
| 约束状态 | 全部满足 |

BRAM 是当前最紧张的资源，仍保留约 22.14% 余量；DSP 使用率为 46.36%，因此 FFN32 并行能够在资源和性能之间保持平衡。

## 8. 板级验收记录

串口使用 115200 baud、8N1，发送：

```text
200:everything with a man
```

板端返回的 200 字符输出开头如下：

```text
that we have stood
The seal of the sea of the war, the world begins
Of the seass of the seasons of the world,
Which the seals of the sea of the world,
```

串口日志记录总耗时为 71.075 s，逐字符流式返回。六层计算完成后的最后一行 hidden 对比为 96/96 个 32 位字一致，说明最终 PL 计算路径与参考结果对齐。

## 9. 复现和交付文件

1. 下载 `nanogpt-zynq-final-20260712.zip`。
2. 如需重新综合，在 `vivado_project/` 中执行 `source scripts/create_final_75mhz_project.tcl`；该脚本会生成本地 `nano_gpt.xpr` 并验证 Block Design。
3. 使用 `fpga/overlay/system/system.bit` 和 `system.hwh` 配置 PL。
4. 使用 `ps/run_ps_mailbox_runner.tcl` 将 `fpga/ddr_image/` 中的权重、缩放参数、LUT 和 golden 数据下载到 DDR，并启动 `ps/ps_mailbox_runner.elf`。
5. 串口设置为 115200, 8N1，输入 `200:everything with a man` 并发送回车。
6. 对照 `tests/step3_ffn32_resetfix_200.raw.txt` 与 `artifacts/reports/optimization_123_results_20260712.md`。

## 10. 原始证据文件

- `artifacts/reports/optimization_123_results_20260712.md`
- `artifacts/reports/timing_step3_ffn32_resetfix_true75_post_route.rpt`
- `artifacts/reports/utilization_step3_ffn32_resetfix_true75_post_route.rpt`
- `tests/step3_ffn32_resetfix_200.raw.txt`
- `tests/step3_ffn32_resetfix_200.raw.events.txt`

## 11. Final FFN32 Stage Profiling

The final PS runner now contains a non-intrusive stage profiler for the final
75 MHz FFN32 implementation. It records per-layer `ln1`, `q`, `k`, `v`,
`attention`, `projection`, `residual1`, `ln2`, `ffn`, and `residual2`, plus
LM-head and embedding-update time. The timer runs at 333.333 MHz, so
`milliseconds = ticks * 3 / 1,000,000`.

Use `ps/PROFILE_USAGE.md` and `ps/read_decode_profile.tcl` after programming
the board through JTAG. This instrumentation preserves model math, INT8 data,
DDR addresses, K/V cache behavior, and the UART protocol. The committed
performance result remains the separately verified 200-character run; no
earlier FFN16 profile values are presented as FFN32 measurements.
