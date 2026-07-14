# INT8 软件参考模型验收报告

- checkpoint: `out-shakespeare-char\ckpt.pt`
- dataset: `shakespeare_char`
- mode: `w8a8_fake_quant`
- FP32 val loss: `1.474584`
- FP32 perplexity: `4.369217`
- INT8 val loss: `1.476334`
- INT8 perplexity: `4.376869`
- perplexity regression: `0.175%`
- pass threshold: `<= 10.0%`
- result: `PASS`

## 说明

- 本结果使用 PTQ fake-quant INT8 软件参考模型。
- Linear/Attention/MLP 权重为 INT8 per-output-channel，激活为 INT8 per-tensor。
- MatMul 语义对应 INT8 输入/权重、INT32 累加，再反量化回 FP32 计算 loss。
- 该结果用于量化精度验收，不代表当前 FPGA RTL 已完全等价实现该软件参考。
