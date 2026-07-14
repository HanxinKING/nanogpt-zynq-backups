# 第一步：Python 端浮点数、定点数与 INT8 量化演示

## 1. 本阶段要展示什么

本阶段只展示 PC 上的 Python 端，暂时不进入 Vivado、Vitis 或开发板。

建议用 5～8 分钟依次说明：

1. nanoGPT 原始 checkpoint 使用 FP32 浮点权重。
2. 浮点数精度高、动态范围大，但存储和硬件乘法开销较大。
3. FPGA 侧更适合整数或定点运算，因此把权重和激活映射为 INT8。
4. 点击 VSCode 的运行按钮，执行真实 nanoGPT W8A8 PTQ 量化。
5. 对比量化前后的存储量、PPL 和生成 Token，证明量化可用。

工程入口：

```text
<repository-root>
```

Python 演示目录：

```text
<repository-root>\01_VSCode_Python
```

## 2. 演示前准备

### 2.1 打开工程

双击：

```text
nanoGPT_Zynq_演示工程.code-workspace
```

在左侧资源管理器展开：

```text
01_VSCode_INT8与Token
```

本工程已经固定使用：

```text
python
```

点击运行时应使用编辑器右上角带提示 `Run Code (Ctrl+Alt+N)` 的蓝色三角按钮。

> 状态栏即使暂时显示 Python 3.12，也不影响蓝色 `Run Code` 按钮；工程的 Code Runner 已固定通过 `run_python_myenv.cmd` 使用 `myenv`。

### 2.2 需要打开的文件

按顺序打开以下文件：

```text
01_quantize_int8.py
demo_outputs/quantization_report.json
02_token_console.py
```

讲解时主要停留在 `01_quantize_int8.py`。

## 3. 浮点数与定点数怎么讲

### 3.1 FP32 浮点数

FP32 使用 32 bit 保存一个数，由符号、指数和尾数组成。它能表示很大的动态范围，适合模型训练和软件参考计算。

例如神经网络权重：

```text
0.7312
-0.1846
0.0027
```

FP32 可以直接保存这些小数，但每个权重占 4 byte。

本工程原始模型状态数据大小为：

```text
43,080,192 byte
```

### 3.2 定点数和 INT8

定点数不保存浮点指数，而是保存整数，并约定一个缩放比例。项目中的 INT8 量化可以理解为：

```text
真实值 ≈ INT8整数 × scale
```

对称量化的核心公式为：

```text
q = clip(round(x / scale), -128, 127)
x_reconstructed = q × scale
```

其中：

- `x`：原始 FP32 数值。
- `scale`：缩放尺度。
- `q`：保存到模型或送入 FPGA 的 INT8 整数。
- `x_reconstructed`：由 INT8 和尺度恢复出的近似值。

示例：假设 `scale = 0.01`：

| FP32 原值 `x` | INT8 `q` | 反量化值 `q×scale` | 误差 |
|---:|---:|---:|---:|
| 0.7312 | 73 | 0.73 | -0.0012 |
| -0.1846 | -18 | -0.18 | 0.0046 |
| 0.0027 | 0 | 0.00 | -0.0027 |

量化会产生舍入误差，但一个权重从 32 bit 减少为 8 bit，更适合 FPGA 的 BRAM、DDR 带宽和整数乘加单元。

### 3.3 不要混淆的概念

传统 `Qm.n` 定点格式通常给整组数据规定相同的小数位位置；本工程采用带 `scale` 的 INT8 量化表示。

本项目具体使用：

- Linear 权重：逐输出通道量化。
- Embedding 权重：逐行量化。
- 激活：使用提前标定的尺度进行 W8A8 fake-quant。
- 权重整数：实际以 `torch.int8` 保存。
- scale：保留额外的尺度张量，用于解释 INT8 数值代表的真实范围。

因此，展示时可以称为“INT8 定点化/整数化表示”，但要说明它不是所有层共用一个固定小数点位置。

## 4. 展示真实 FP32 模型

在 `01_quantize_int8.py` 中指出以下输入文件：

```python
CKPT_FILE = NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt"
CONFIG_FILE = NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference" / "quant_config.json"
```

说明：

- `ckpt.pt` 是真实 Shakespeare nanoGPT checkpoint，不是随机生成的演示数据。
- `quant_config.json` 保存已标定的激活尺度。
- 模型结构为 6 层 Transformer、6 个 Head、384 维 Embedding。
- 词表大小为 65，最大上下文长度为 256。

可使用下面的话术：

> 这里首先加载训练完成的 FP32 nanoGPT，FP32 模型作为软件参考。随后读取离线标定得到的激活尺度，把模型中的 Linear 和 Embedding 权重转换为 INT8，同时在激活路径插入 W8A8 fake-quant，用它模拟 FPGA 上的整数计算误差。

## 5. 手动点击执行 INT8 量化

### 5.1 点击位置

1. 在 VSCode 中打开 `01_quantize_int8.py`。
2. 点击编辑器右上角蓝色三角形 `Run Code`。
3. 下方自动打开“输出”面板。
4. 等待看到 `[Done] exited with code=0`。

脚本会自动执行四个阶段：

```text
[1/4] 加载真实 6 层 Shakespeare nanoGPT checkpoint
[2/4] 读取已签核的 W8A8 激活标定尺度
[3/4] 量化 Linear、Embedding，并插入激活 fake-quant
[4/4] 完成
```

### 5.2 应该看到的结果

```text
量化模块数       : 27
INT8 权重字节数  : 10,765,056
尺度字节数       : 84,588
硬件质量基线     : FP32 PPL 4.333494 -> INT8 PPL 4.509458，回退 4.0606%
结果             : PASS
```

输出文件：

```text
demo_outputs/nanogpt_w8a8_demo.pt
demo_outputs/quantization_report.json
```

反复点击会重新生成演示量化包，不会覆盖原始 `ckpt.pt`、FPGA DDR 镜像或 bitstream。

## 6. 量化结果如何解释

### 6.1 存储量对比

| 项目 | 字节数 |
|---|---:|
| FP32 模型状态 | 43,080,192 |
| INT8 权重 | 10,765,056 |
| 量化尺度 | 84,588 |
| INT8 权重加尺度 | 10,849,644 |

结论：

- 包含尺度后约压缩 `3.97×`。
- 存储量约减少 `74.82%`。
- 单独比较 FP32 权重和 INT8 权重，接近理论上的 `4×` 压缩。

### 6.2 精度对比

| 模型 | PPL |
|---|---:|
| FP32 | 4.333494 |
| INT8 严格硬件对齐 Q30 | 4.509458 |

PPL 回退为：

```text
严格硬件对齐 Q30：4.0606%
```

该工程的量化门槛是回退小于 10%，当前结果为 `PASS`。

可以这样总结：

> INT8 将主要权重存储量减少约四分之三。严格硬件对齐 Q30 的正式质量回退为 4.0606%，通过 10% 门槛。

## 7. 接着展示输入和输出 Token

完成量化后：

1. 打开 `02_token_console.py`。
2. 点击右上角蓝色 `Run Code`。
3. 在弹出的 `nanoGPT Token 输入` 窗口中输入英文提示词，例如：

```text
ROMEO:
```

4. 点击“确定”。
5. 在 VSCode 输出面板观察输入字符、输入 Token ID、逐步输出 Token ID 和生成文本。

已验证的输入示例：

```text
输入文本: 'ROMEO:'
Token IDs: [30, 27, 25, 17, 27, 10]
```

输出中会分别显示：

```text
=== INT8 W8A8 逐 Token 输出 ===
step 01: token=...
step 02: token=...
...
INT8 新 Token IDs: [...]
INT8 完整输出: '...'
```

若未选择 `--skip-fp32`，脚本还会运行 GitHub 原始 FP32 采样输出；界面不统计 mistake/mismatch 数量。

## 8. 第一阶段结束时的总结话术

> 第一阶段在 Python 软件端完成。原始 nanoGPT 使用 FP32 参数，随后通过带尺度的 W8A8 INT8 量化，将 Linear 和 Embedding 权重转换为整数表示。真实模型的权重与尺度合计约 10.85 MB，相对 FP32 状态压缩约 3.97 倍。用于 FPGA 验收的严格硬件对齐 Q30 指标为 FP32 PPL 4.333494、INT8 PPL 4.509458、回退 4.0606%，通过 10% 质量门槛。

## 9. 常见问题

### 点击后出现 `python 不是内部或外部命令`

必须通过本工程的 `.code-workspace` 打开，并点击 `Run Code`。工程已配置 `run_python_myenv.cmd`，不要在未配置的普通文件夹窗口中使用系统默认 `python`。

### 中文输出乱码

工程启动器已经设置：

```text
PYTHONUTF8=1
PYTHONIOENCODING=utf-8
```

并且 Code Runner 使用 VSCode“输出”面板显示结果。

### 为什么叫 W8A8

- `W8`：权重使用 8 bit 整数表示。
- `A8`：激活按 8 bit 量化规则模拟。

### `nanogpt_w8a8_demo.pt` 是否是可直接替代训练 checkpoint 的普通 FP32 模型

不是。它是面向量化演示和重复加载的状态包，包含 INT8 权重、scale、激活尺度及模型参数信息；原始 FP32 checkpoint 仍保留作为参考基线。
