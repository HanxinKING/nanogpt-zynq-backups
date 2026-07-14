# INT8 软件参考模型验收报告

- checkpoint: `python/nanoGPT/out-shakespeare-char/ckpt.pt`（需按 README 重新训练生成）
- dataset: `shakespeare_char`
- mode: `w8a8_fake_quant`
- FP32 val loss: `1.466374`
- FP32 perplexity: `4.333494`
- INT8 val loss: `1.468349`
- INT8 perplexity: `4.342062`
- perplexity regression: `0.198%`
- pass threshold: `<= 10.0%`
- result: `PASS`

## 说明

- 本结果使用 PTQ fake-quant INT8 软件参考模型。
- Linear/Attention/MLP 权重为 INT8 per-output-channel，激活为 INT8 per-tensor。
- MatMul 语义对应 INT8 输入/权重、INT32 累加，再反量化回 FP32 计算 loss。
- 该结果用于量化精度验收，不代表当前 FPGA RTL 已完全等价实现该软件参考。

## 诊断结果

- W8 weight-only val loss: `1.466359`
- W8 weight-only perplexity: `4.333427`
- W8 weight-only regression: `-0.002%`
