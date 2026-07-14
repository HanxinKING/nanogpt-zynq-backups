# VSCode 中运行 FP32 与严格 Q30 INT8

1. 打开根目录的 `nanoGPT_Zynq_演示工程.code-workspace`。
2. 在 VSCode 中选择“终端 -> 运行任务”。
3. `01 生成 INT8 量化包`用于演示 W8A8 PTQ 和快速质量评估。
4. `02 交互输入 Prompt 并查看 Token`用于 FP32 与板卡对齐 Q30 INT8 的输入输出比较。

`02_token_console.py`不再读取演示用 `nanogpt_w8a8_demo.pt`，而是直接使用：

- `../python/nanoGPT/out-shakespeare-char/ckpt.pt`
- `../python/nanoGPT/out-shakespeare-char/int8_reference/int8_state_dict.pt`
- `../reference/int8_alignment/hardware_params/`
- `../reference/int8_alignment/bittrue_q30_everything_200/summary.json`

FP32 和 INT8 使用相同的确定性 loop-guard。程序显示：

- 输入字符与 token ID
- FP32 和 Q30 INT8 的生成 token
- 生成 token mismatch
- 首步 logits mean absolute error
- 两种模式的完整输出文本

运行记录写入 `demo_outputs/last_token_run.json`。严格 Q30 仿真比快速 fake-quant 慢，这是逐 token 对齐板卡所需的计算路径。
