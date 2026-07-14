from __future__ import annotations

import argparse
import copy
import json
import math
import os
import pickle
import re
import sys
import time
from dataclasses import asdict
from pathlib import Path
from typing import Any

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F


NANOGPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = NANOGPT_ROOT.parent
if str(NANOGPT_ROOT) not in sys.path:
    sys.path.insert(0, str(NANOGPT_ROOT))

from model import GPT, GPTConfig  # noqa: E402


def load_torch(path: Path, map_location: str | torch.device) -> Any:
    try:
        return torch.load(path, map_location=map_location, weights_only=False)
    except TypeError:
        return torch.load(path, map_location=map_location)


def sanitize_name(name: str) -> str:
    return re.sub(r"[^0-9A-Za-z_]+", "_", name).strip("_")


def symmetric_quantize_per_tensor(x: torch.Tensor, bits: int = 8) -> tuple[torch.Tensor, torch.Tensor]:
    qmax = (1 << (bits - 1)) - 1
    max_abs = x.detach().abs().max()
    scale = torch.clamp(max_abs / qmax, min=torch.finfo(torch.float32).eps).to(torch.float32)
    q = torch.clamp(torch.round(x.detach().to(torch.float32) / scale), -qmax - 1, qmax).to(torch.int8)
    return q, scale


def symmetric_quantize_per_channel(
    x: torch.Tensor, ch_axis: int, bits: int = 8
) -> tuple[torch.Tensor, torch.Tensor]:
    qmax = (1 << (bits - 1)) - 1
    reduce_dims = [dim for dim in range(x.dim()) if dim != ch_axis]
    max_abs = x.detach().abs().amax(dim=reduce_dims, keepdim=True)
    scale = torch.clamp(max_abs / qmax, min=torch.finfo(torch.float32).eps).to(torch.float32)
    q = torch.clamp(torch.round(x.detach().to(torch.float32) / scale), -qmax - 1, qmax).to(torch.int8)
    return q, scale.squeeze()


def fake_quant_activation(x: torch.Tensor, scale: torch.Tensor | None) -> torch.Tensor:
    if scale is None:
        return x
    q = torch.clamp(torch.round(x.to(torch.float32) / scale), -128, 127).to(torch.int8)
    return q.to(torch.float32) * scale


class QuantizedLinear(nn.Module):
    def __init__(self, name: str, linear: nn.Linear, activation_scale: float | None):
        super().__init__()
        self.name = name
        qweight, weight_scale = symmetric_quantize_per_channel(linear.weight.detach().cpu(), ch_axis=0)
        self.register_buffer("qweight", qweight)
        self.register_buffer("weight_scale", weight_scale.to(torch.float32))
        if linear.bias is None:
            self.bias = None
        else:
            self.register_buffer("bias", linear.bias.detach().cpu().to(torch.float32))
        if activation_scale is None:
            self.activation_scale = None
        else:
            self.register_buffer("activation_scale", torch.tensor(float(activation_scale), dtype=torch.float32))

    def dequant_weight(self) -> torch.Tensor:
        shape = [self.qweight.shape[0]] + [1] * (self.qweight.dim() - 1)
        return self.qweight.to(torch.float32) * self.weight_scale.reshape(shape)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        xq = fake_quant_activation(x, self.activation_scale)
        return F.linear(xq, self.dequant_weight(), self.bias)


class QuantizedEmbedding(nn.Module):
    def __init__(self, name: str, embedding: nn.Embedding):
        super().__init__()
        self.name = name
        qweight, weight_scale = symmetric_quantize_per_channel(embedding.weight.detach().cpu(), ch_axis=0)
        self.register_buffer("qweight", qweight)
        self.register_buffer("weight_scale", weight_scale.to(torch.float32))
        self.padding_idx = embedding.padding_idx
        self.max_norm = embedding.max_norm
        self.norm_type = embedding.norm_type
        self.scale_grad_by_freq = embedding.scale_grad_by_freq
        self.sparse = embedding.sparse

    def dequant_weight(self) -> torch.Tensor:
        return self.qweight.to(torch.float32) * self.weight_scale.reshape(-1, 1)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return F.embedding(
            x,
            self.dequant_weight(),
            self.padding_idx,
            self.max_norm,
            self.norm_type,
            self.scale_grad_by_freq,
            self.sparse,
        )


def get_parent_module(root: nn.Module, dotted_name: str) -> tuple[nn.Module, str]:
    parts = dotted_name.split(".")
    parent = root
    for part in parts[:-1]:
        parent = getattr(parent, part)
    return parent, parts[-1]


def build_quantized_model(
    model: GPT, mode: str, activation_scales: dict[str, float]
) -> tuple[GPT, dict[str, dict[str, Any]]]:
    quantized = copy.deepcopy(model).cpu()
    module_report: dict[str, dict[str, Any]] = {}
    replacements: list[tuple[str, nn.Module]] = []

    for name, module in quantized.named_modules():
        if isinstance(module, nn.Linear):
            act_scale = activation_scales.get(name) if mode == "w8a8_fake_quant" else None
            replacements.append((name, QuantizedLinear(name, module, act_scale)))
            module_report[name] = {
                "type": "linear",
                "mode": mode,
                "weight_shape": list(module.weight.shape),
                "weight_scale_granularity": "per_output_channel",
                "activation_scale": act_scale,
            }
        elif isinstance(module, nn.Embedding):
            replacements.append((name, QuantizedEmbedding(name, module)))
            module_report[name] = {
                "type": "embedding",
                "mode": mode,
                "weight_shape": list(module.weight.shape),
                "weight_scale_granularity": "per_row",
                "activation_scale": None,
            }

    for name, module in replacements:
        parent, child = get_parent_module(quantized, name)
        setattr(parent, child, module)

    quantized.eval()
    return quantized, module_report


def load_checkpoint_model(ckpt_path: Path) -> tuple[GPT, dict[str, Any]]:
    checkpoint = load_torch(ckpt_path, map_location="cpu")
    gptconf = GPTConfig(**checkpoint["model_args"])
    model = GPT(gptconf)
    state_dict = checkpoint["model"]
    unwanted_prefix = "_orig_mod."
    for key in list(state_dict.keys()):
        if key.startswith(unwanted_prefix):
            state_dict[key[len(unwanted_prefix) :]] = state_dict.pop(key)
    model.load_state_dict(state_dict)
    model.eval()
    return model, checkpoint


def make_batch_indices(
    data_len: int, block_size: int, batch_size: int, iters: int, seed: int
) -> list[torch.Tensor]:
    generator = torch.Generator(device="cpu")
    generator.manual_seed(seed)
    return [torch.randint(data_len - block_size, (batch_size,), generator=generator) for _ in range(iters)]


def get_batch(data: np.memmap, indices: torch.Tensor, block_size: int, device: str) -> tuple[torch.Tensor, torch.Tensor]:
    x = torch.stack([torch.from_numpy((data[int(i) : int(i) + block_size]).astype(np.int64)) for i in indices])
    y = torch.stack(
        [torch.from_numpy((data[int(i) + 1 : int(i) + 1 + block_size]).astype(np.int64)) for i in indices]
    )
    if device.startswith("cuda"):
        x = x.pin_memory().to(device, non_blocking=True)
        y = y.pin_memory().to(device, non_blocking=True)
    else:
        x = x.to(device)
        y = y.to(device)
    return x, y


@torch.no_grad()
def calibrate_activation_scales(
    model: GPT,
    val_data: np.memmap,
    batch_indices: list[torch.Tensor],
    block_size: int,
    device: str,
) -> dict[str, float]:
    max_abs: dict[str, float] = {}
    hooks = []

    def make_hook(name: str):
        def hook(_module: nn.Module, inputs: tuple[torch.Tensor, ...]) -> None:
            if not inputs:
                return
            value = float(inputs[0].detach().abs().max().item())
            max_abs[name] = max(max_abs.get(name, 0.0), value)

        return hook

    for name, module in model.named_modules():
        if isinstance(module, nn.Linear):
            hooks.append(module.register_forward_pre_hook(make_hook(name)))

    model.to(device)
    model.eval()
    for indices in batch_indices:
        x, _ = get_batch(val_data, indices, block_size, device)
        model(x)

    for hook in hooks:
        hook.remove()

    eps = float(torch.finfo(torch.float32).eps)
    return {name: max(value / 127.0, eps) for name, value in max_abs.items()}


@torch.no_grad()
def evaluate_model(
    model: GPT,
    val_data: np.memmap,
    batch_indices: list[torch.Tensor],
    block_size: int,
    device: str,
) -> dict[str, float]:
    model.to(device)
    model.eval()
    losses = []
    start = time.perf_counter()
    for indices in batch_indices:
        x, y = get_batch(val_data, indices, block_size, device)
        _logits, loss = model(x, y)
        losses.append(float(loss.item()))
    elapsed_s = time.perf_counter() - start
    mean_loss = float(np.mean(losses))
    return {
        "val_loss": mean_loss,
        "perplexity": float(math.exp(mean_loss)),
        "elapsed_s": elapsed_s,
        "iters": float(len(batch_indices)),
    }


def load_codec(dataset_dir: Path):
    meta_path = dataset_dir / "meta.pkl"
    with meta_path.open("rb") as f:
        meta = pickle.load(f)
    stoi, itos = meta["stoi"], meta["itos"]
    encode = lambda s: [stoi[ch] for ch in s]
    decode = lambda ids: "".join([itos[int(i)] for i in ids])
    return encode, decode


@torch.no_grad()
def sample_model(
    model: GPT,
    dataset_dir: Path,
    prompt: str,
    device: str,
    seed: int,
    max_new_tokens: int,
    temperature: float,
    top_k: int,
) -> str:
    encode, decode = load_codec(dataset_dir)
    if prompt.startswith("FILE:"):
        prompt = Path(prompt[5:]).read_text(encoding="utf-8")
    torch.manual_seed(seed)
    if device.startswith("cuda"):
        torch.cuda.manual_seed(seed)
    model.to(device)
    model.eval()
    x = torch.tensor(encode(prompt), dtype=torch.long, device=device)[None, ...]
    y = model.generate(x, max_new_tokens=max_new_tokens, temperature=temperature, top_k=top_k)
    return decode(y[0].tolist())


def tensor_to_hex_lines(tensor: torch.Tensor) -> list[str]:
    flat = tensor.detach().cpu().numpy().astype(np.int16).reshape(-1)
    return [f"{int(v) & 0xFF:02x}" for v in flat]


def export_quantized_artifacts(
    quantized: GPT,
    module_report: dict[str, dict[str, Any]],
    out_dir: Path,
    fpga_dir: Path,
    config: dict[str, Any],
) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    weights_dir = fpga_dir / "weights_mem"
    weights_dir.mkdir(parents=True, exist_ok=True)

    state: dict[str, Any] = {
        "config": config,
        "modules": {},
    }
    manifest: dict[str, Any] = {
        "config": config,
        "modules": {},
    }
    scale_npz: dict[str, np.ndarray] = {}

    for name, module in quantized.named_modules():
        if not isinstance(module, (QuantizedLinear, QuantizedEmbedding)):
            continue
        safe = sanitize_name(name)
        mem_path = weights_dir / f"{safe}_weight_int8.mem"
        mem_path.write_text("\n".join(tensor_to_hex_lines(module.qweight)) + "\n", encoding="ascii")

        weight_scale = module.weight_scale.detach().cpu().numpy().astype(np.float32)
        scale_npz[f"{safe}_weight_scale"] = weight_scale
        activation_scale = None
        if isinstance(module, QuantizedLinear) and module.activation_scale is not None:
            activation_scale = float(module.activation_scale.detach().cpu().item())
            scale_npz[f"{safe}_activation_scale"] = np.array([activation_scale], dtype=np.float32)

        state["modules"][name] = {
            "qweight": module.qweight.detach().cpu(),
            "weight_scale": module.weight_scale.detach().cpu(),
            "activation_scale": activation_scale,
            "bias": None if getattr(module, "bias", None) is None else module.bias.detach().cpu(),
        }
        manifest["modules"][name] = {
            **module_report.get(name, {}),
            "mem_file": str(mem_path.relative_to(fpga_dir).as_posix()),
            "numel": int(module.qweight.numel()),
            "shape": list(module.qweight.shape),
            "activation_scale": activation_scale,
        }

    torch.save(state, out_dir / "int8_state_dict.pt")
    np.savez(out_dir / "scales.npz", **scale_npz)
    (fpga_dir / "shape_metadata.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    header_lines = [
        "#ifndef NANO_GPT_INT8_QUANT_METADATA_H",
        "#define NANO_GPT_INT8_QUANT_METADATA_H",
        "",
        f"#define NANO_GPT_INT8_NUM_MODULES {len(manifest['modules'])}",
        "#define NANO_GPT_INT8_WEIGHT_BITS 8",
        "#define NANO_GPT_INT8_ACCUM_BITS 32",
        "",
        "#endif",
        "",
    ]
    (fpga_dir / "quant_metadata.h").write_text("\n".join(header_lines), encoding="ascii")


def write_reports(
    out_dir: Path,
    fpga_dir: Path,
    quant_config: dict[str, Any],
    metrics: dict[str, Any],
    samples: dict[str, str],
) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    fpga_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "quant_config.json").write_text(json.dumps(quant_config, indent=2), encoding="utf-8")
    (out_dir / "metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    (out_dir / "samples_fp32.txt").write_text(samples["fp32"], encoding="utf-8")
    (out_dir / "samples_int8.txt").write_text(samples["int8"], encoding="utf-8")

    lines = [
        "# INT8 软件参考模型验收报告",
        "",
        f"- checkpoint: `{metrics['checkpoint']}`",
        f"- dataset: `{metrics['dataset']}`",
        f"- mode: `{metrics['primary_mode']}`",
        f"- FP32 val loss: `{metrics['fp32']['val_loss']:.6f}`",
        f"- FP32 perplexity: `{metrics['fp32']['perplexity']:.6f}`",
        f"- INT8 val loss: `{metrics['int8']['val_loss']:.6f}`",
        f"- INT8 perplexity: `{metrics['int8']['perplexity']:.6f}`",
        f"- perplexity regression: `{metrics['ppl_regression_pct']:.3f}%`",
        f"- pass threshold: `<= {metrics['pass_threshold_pct']:.1f}%`",
        f"- result: `{'PASS' if metrics['pass'] else 'FAIL'}`",
        "",
        "## 说明",
        "",
        "- 本结果使用 PTQ fake-quant INT8 软件参考模型。",
        "- Linear/Attention/MLP 权重为 INT8 per-output-channel，激活为 INT8 per-tensor。",
        "- MatMul 语义对应 INT8 输入/权重、INT32 累加，再反量化回 FP32 计算 loss。",
        "- 该结果用于量化精度验收，不代表当前 FPGA RTL 已完全等价实现该软件参考。",
        "",
    ]
    if "diagnostic_weight_only" in metrics:
        diag = metrics["diagnostic_weight_only"]
        lines.extend(
            [
                "## 诊断结果",
                "",
                f"- W8 weight-only val loss: `{diag['val_loss']:.6f}`",
                f"- W8 weight-only perplexity: `{diag['perplexity']:.6f}`",
                f"- W8 weight-only regression: `{diag['ppl_regression_pct']:.3f}%`",
                "",
            ]
        )
    (out_dir / "metrics.md").write_text("\n".join(lines), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate nanoGPT INT8 PTQ reference model.")
    parser.add_argument("--ckpt", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt")
    parser.add_argument("--dataset", type=str, default="shakespeare_char")
    parser.add_argument("--device", type=str, default="cuda" if torch.cuda.is_available() else "cpu")
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--eval-iters", type=int, default=200)
    parser.add_argument("--calib-iters", type=int, default=200)
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--threshold-pct", type=float, default=10.0)
    parser.add_argument("--mode", choices=["w8a8_fake_quant", "w8_weight_only"], default="w8a8_fake_quant")
    parser.add_argument("--run-weight-only-diagnostic", action="store_true")
    parser.add_argument("--out-dir", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference")
    parser.add_argument("--fpga-out-dir", type=Path, default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_reference")
    parser.add_argument("--prompt", type=str, default="\n")
    parser.add_argument("--max-new-tokens", type=int, default=200)
    parser.add_argument("--temperature", type=float, default=0.8)
    parser.add_argument("--top-k", type=int, default=40)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.device.startswith("cuda") and not torch.cuda.is_available():
        raise RuntimeError("CUDA was requested but torch.cuda.is_available() is false")

    torch.manual_seed(args.seed)
    if args.device.startswith("cuda"):
        torch.cuda.manual_seed(args.seed)
        torch.backends.cuda.matmul.allow_tf32 = False
        torch.backends.cudnn.allow_tf32 = False

    dataset_dir = NANOGPT_ROOT / "data" / args.dataset
    val_path = dataset_dir / "val.bin"
    if not args.ckpt.exists():
        raise FileNotFoundError(args.ckpt)
    if not val_path.exists():
        raise FileNotFoundError(val_path)

    fp32_model, checkpoint = load_checkpoint_model(args.ckpt)
    block_size = int(checkpoint["model_args"]["block_size"])
    val_data = np.memmap(val_path, dtype=np.uint16, mode="r")
    eval_indices = make_batch_indices(len(val_data), block_size, args.batch_size, args.eval_iters, args.seed)
    calib_indices = make_batch_indices(len(val_data), block_size, args.batch_size, args.calib_iters, args.seed + 1)

    activation_scales = calibrate_activation_scales(
        fp32_model, val_data, calib_indices, block_size, args.device
    )
    fp32_metrics = evaluate_model(fp32_model, val_data, eval_indices, block_size, args.device)

    quantized_model, module_report = build_quantized_model(fp32_model.cpu(), args.mode, activation_scales)
    int8_metrics = evaluate_model(quantized_model, val_data, eval_indices, block_size, args.device)
    regression_pct = (
        (int8_metrics["perplexity"] - fp32_metrics["perplexity"]) / fp32_metrics["perplexity"] * 100.0
    )

    metrics: dict[str, Any] = {
        "checkpoint": str(args.ckpt),
        "dataset": args.dataset,
        "primary_mode": args.mode,
        "device": args.device,
        "batch_size": args.batch_size,
        "eval_iters": args.eval_iters,
        "calib_iters": args.calib_iters,
        "seed": args.seed,
        "model_args": checkpoint["model_args"],
        "fp32": fp32_metrics,
        "int8": int8_metrics,
        "ppl_regression_pct": float(regression_pct),
        "pass_threshold_pct": args.threshold_pct,
        "pass": bool(np.isfinite(regression_pct) and regression_pct <= args.threshold_pct),
    }

    if (not metrics["pass"]) or args.run_weight_only_diagnostic:
        weight_only_model, _ = build_quantized_model(fp32_model.cpu(), "w8_weight_only", activation_scales)
        weight_only_metrics = evaluate_model(weight_only_model, val_data, eval_indices, block_size, args.device)
        weight_only_regression = (
            (weight_only_metrics["perplexity"] - fp32_metrics["perplexity"])
            / fp32_metrics["perplexity"]
            * 100.0
        )
        metrics["diagnostic_weight_only"] = {
            **weight_only_metrics,
            "ppl_regression_pct": float(weight_only_regression),
        }

    quant_config = {
        "format": "PTQ fake quant INT8 reference",
        "primary_mode": args.mode,
        "weight_bits": 8,
        "activation_bits": 8 if args.mode == "w8a8_fake_quant" else None,
        "accum_bits": 32,
        "linear_weight_quant": "symmetric per-output-channel int8",
        "embedding_weight_quant": "symmetric per-row int8",
        "activation_quant": "symmetric per-tensor int8 calibrated from validation batches",
        "layernorm": "fp32 in software reference",
        "softmax": "fp32 in software reference",
        "gelu": "fp32 in software reference",
        "block_size": block_size,
        "vocab_size": checkpoint["model_args"]["vocab_size"],
        "n_layer": checkpoint["model_args"]["n_layer"],
        "n_head": checkpoint["model_args"]["n_head"],
        "n_embd": checkpoint["model_args"]["n_embd"],
        "activation_scales": activation_scales,
    }

    fp32_sample = sample_model(
        fp32_model,
        dataset_dir,
        args.prompt,
        args.device,
        args.seed,
        args.max_new_tokens,
        args.temperature,
        args.top_k,
    )
    int8_sample = sample_model(
        quantized_model,
        dataset_dir,
        args.prompt,
        args.device,
        args.seed,
        args.max_new_tokens,
        args.temperature,
        args.top_k,
    )
    samples = {"fp32": fp32_sample, "int8": int8_sample}

    export_quantized_artifacts(quantized_model.cpu(), module_report, args.out_dir, args.fpga_out_dir, quant_config)
    write_reports(args.out_dir, args.fpga_out_dir, quant_config, metrics, samples)

    print(json.dumps(metrics, indent=2))
    if not metrics["pass"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
