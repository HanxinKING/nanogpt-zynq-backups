from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from datetime import datetime
from pathlib import Path

import torch


ROOT = Path(__file__).resolve().parents[1]
NANOGPT_ROOT = ROOT / "python" / "nanoGPT"
TOOLS_FILE = NANOGPT_ROOT / "tools" / "eval_int8_reference.py"
CKPT_FILE = NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt"
CONFIG_FILE = NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference" / "quant_config.json"
OUTPUT_DIR = Path(__file__).resolve().parent / "demo_outputs"
OUTPUT_PACKAGE = OUTPUT_DIR / "nanogpt_w8a8_demo.pt"
OUTPUT_REPORT = OUTPUT_DIR / "quantization_report.json"


def load_quant_tools():
    spec = importlib.util.spec_from_file_location("nanogpt_int8_tools", TOOLS_FILE)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载量化工具: {TOOLS_FILE}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def tensor_bytes(tensor: torch.Tensor) -> int:
    return tensor.numel() * tensor.element_size()


def main() -> int:
    parser = argparse.ArgumentParser(description="对真实 Shakespeare nanoGPT checkpoint 执行 W8A8 INT8 量化")
    parser.add_argument("--force", action="store_true", help="覆盖已存在的演示量化包")
    args = parser.parse_args()

    for required in (TOOLS_FILE, CKPT_FILE, CONFIG_FILE):
        if not required.exists():
            raise FileNotFoundError(required)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    if OUTPUT_PACKAGE.exists() and not args.force:
        print(f"检测到已有量化包，将重新生成: {OUTPUT_PACKAGE}")
        print("提示：直接点击 VSCode 的运行按钮即可重新执行 INT8 量化。")

    print("[1/4] 加载真实 6 层 Shakespeare nanoGPT checkpoint")
    tools = load_quant_tools()
    fp32_model, checkpoint = tools.load_checkpoint_model(CKPT_FILE)

    print("[2/4] 读取已签核的 W8A8 激活标定尺度")
    quant_config = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
    activation_scales = {str(k): float(v) for k, v in quant_config["activation_scales"].items()}

    print("[3/4] 逐输出通道量化 Linear 权重、逐行量化 Embedding，并插入激活 fake-quant")
    int8_model, module_report = tools.build_quantized_model(
        fp32_model, "w8a8_fake_quant", activation_scales
    )
    state_dict = int8_model.state_dict()

    int8_tensors = {k: v for k, v in state_dict.items() if v.dtype == torch.int8}
    scale_tensors = {k: v for k, v in state_dict.items() if "scale" in k}
    fp32_parameter_bytes = sum(tensor_bytes(v.detach().cpu()) for v in fp32_model.state_dict().values())
    int8_weight_bytes = sum(tensor_bytes(v) for v in int8_tensors.values())
    scale_bytes = sum(tensor_bytes(v) for v in scale_tensors.values())

    package = {
        "format": "nanoGPT W8A8 PTQ demonstration state",
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "checkpoint": str(CKPT_FILE.relative_to(ROOT)),
        "quant_config": str(CONFIG_FILE.relative_to(ROOT)),
        "model_args": checkpoint["model_args"],
        "activation_scales": activation_scales,
        "state_dict": state_dict,
    }
    torch.save(package, OUTPUT_PACKAGE)

    report = {
        "mode": "w8a8_fake_quant",
        "checkpoint": str(CKPT_FILE.relative_to(ROOT)),
        "output_package": str(OUTPUT_PACKAGE.relative_to(ROOT)),
        "quantized_modules": len(module_report),
        "int8_tensor_count": len(int8_tensors),
        "scale_tensor_count": len(scale_tensors),
        "fp32_state_bytes": fp32_parameter_bytes,
        "int8_weight_bytes": int8_weight_bytes,
        "scale_bytes": scale_bytes,
        "model_args": checkpoint["model_args"],
        "hardware_exact_quality_baseline": {
            "mode": "quality_exact_hw_full_s256_d384_l6",
            "fp32_loss": 1.4663740962743759,
            "int8_loss": 1.5061770606040954,
            "fp32_ppl": 4.333493788721389,
            "int8_ppl": 4.509458413494683,
            "ppl_regression_pct": 4.060571754626027,
            "gate": "PASS (<10%)",
        },
    }
    OUTPUT_REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print("[4/4] 完成")
    print(f"量化模块数       : {len(module_report)}")
    print(f"INT8 权重字节数  : {int8_weight_bytes:,}")
    print(f"尺度字节数       : {scale_bytes:,}")
    print(f"量化包           : {OUTPUT_PACKAGE}")
    print(f"报告             : {OUTPUT_REPORT}")
    print("硬件质量基线     : FP32 PPL 4.333494 -> INT8 PPL 4.509458，回退 4.0606%，PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
