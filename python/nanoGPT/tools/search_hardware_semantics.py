from __future__ import annotations

import argparse
import copy
import json
import math
import sys
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
from tools.eval_int8_reference import (  # noqa: E402
    build_quantized_model,
    calibrate_activation_scales,
    evaluate_model,
    get_batch,
    load_checkpoint_model,
    make_batch_indices,
)


class QuantizedGELU(nn.Module):
    def __init__(self, scale: float, bits: int = 8):
        super().__init__()
        self.scale = float(max(scale, 1e-8))
        self.bits = int(bits)
        qmax = (1 << (bits - 1)) - 1
        qmin = -(1 << (bits - 1))
        xs = torch.arange(-128, 128, dtype=torch.float32) * self.scale
        ys = F.gelu(xs)
        lut = torch.clamp(torch.round(ys / self.scale), qmin, qmax).to(torch.float32) * self.scale
        self.register_buffer("lut", lut)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        q = torch.clamp(torch.round(x.float() / self.scale), -128, 127).to(torch.long) + 128
        return self.lut[q].to(x.device)


class QuantizedSoftmax(nn.Module):
    def __init__(self, bits: int = 8):
        super().__init__()
        self.bits = int(bits)
        self.qmax = (1 << bits) - 1

    def forward(self, x: torch.Tensor, dim: int = -1) -> torch.Tensor:
        probs = F.softmax(x, dim=dim)
        q = torch.clamp(torch.round(probs * self.qmax), 0, self.qmax)
        denom = torch.clamp(q.sum(dim=dim, keepdim=True), min=1.0)
        return q / denom


class QuantizedLayerNorm(nn.Module):
    def __init__(self, src: nn.LayerNorm, bits: int = 8):
        super().__init__()
        self.normalized_shape = src.normalized_shape
        self.eps = src.eps
        self.bits = int(bits)
        self.qmax = (1 << (bits - 1)) - 1
        self.qmin = -(1 << (bits - 1))
        if src.elementwise_affine:
            self.register_buffer("weight", src.weight.detach().cpu().clone())
            self.register_buffer("bias", src.bias.detach().cpu().clone() if src.bias is not None else torch.zeros_like(src.weight.detach().cpu()))
        else:
            self.weight = None
            self.bias = None

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        y = F.layer_norm(
            x,
            self.normalized_shape,
            None if self.weight is None else self.weight.to(x.device),
            None if self.bias is None else self.bias.to(x.device),
            self.eps,
        )
        scale = torch.clamp(y.detach().abs().amax(dim=-1, keepdim=True) / self.qmax, min=torch.finfo(torch.float32).eps)
        q = torch.clamp(torch.round(y / scale), self.qmin, self.qmax)
        return q * scale


def replace_layernorm(module: nn.Module, bits: int | None) -> None:
    if bits is None:
        return
    for name, child in list(module.named_children()):
        if isinstance(child, nn.LayerNorm):
            setattr(module, name, QuantizedLayerNorm(child, bits=bits))
        else:
            replace_layernorm(child, bits)


def replace_gelu(module: nn.Module, gelu_module: nn.Module) -> None:
    for name, child in list(module.named_children()):
        if isinstance(child, nn.GELU):
            setattr(module, name, copy.deepcopy(gelu_module))
        else:
            replace_gelu(child, gelu_module)


def patch_attention_softmax(model: GPT, softmax_bits: int | None) -> list[Any]:
    if softmax_bits is None:
        return []
    modules: list[QuantizedSoftmax] = []
    originals: list[Any] = []
    for block in model.transformer.h:
        qsoftmax = QuantizedSoftmax(softmax_bits)
        modules.append(qsoftmax)
        attn = block.attn
        original_forward = attn.forward
        originals.append((attn, original_forward))

        def make_forward(attn_module: nn.Module, qsm: QuantizedSoftmax):
            def forward(x: torch.Tensor) -> torch.Tensor:
                B, T, C = x.size()
                q, k, v = attn_module.c_attn(x).split(attn_module.n_embd, dim=2)
                k = k.view(B, T, attn_module.n_head, C // attn_module.n_head).transpose(1, 2)
                q = q.view(B, T, attn_module.n_head, C // attn_module.n_head).transpose(1, 2)
                v = v.view(B, T, attn_module.n_head, C // attn_module.n_head).transpose(1, 2)
                y = F.scaled_dot_product_attention(
                    q,
                    k,
                    v,
                    attn_mask=None,
                    dropout_p=0.0,
                    is_causal=True,
                )
                # Recompute explicit attention if quantized probability is requested.
                if qsm.bits < 32:
                    scores = (q @ k.transpose(-2, -1)) * (1.0 / math.sqrt(k.size(-1)))
                    mask = torch.tril(torch.ones(T, T, device=x.device, dtype=torch.bool))
                    scores = scores.masked_fill(~mask, float("-inf"))
                    probs = qsm(scores, dim=-1)
                    y = probs @ v
                y = y.transpose(1, 2).contiguous().view(B, T, C)
                y = attn_module.resid_dropout(attn_module.c_proj(y))
                return y

            return forward

        attn.forward = make_forward(attn, qsoftmax)  # type: ignore[method-assign]
    return originals


def restore_attention(originals: list[Any]) -> None:
    for attn, forward in originals:
        attn.forward = forward  # type: ignore[method-assign]


def run_variant(
    fp32_model: GPT,
    val_data: np.memmap,
    eval_indices: list[torch.Tensor],
    activation_scales: dict[str, float],
    block_size: int,
    device: str,
    name: str,
    ln_bits: int | None,
    gelu_bits: int | None,
    softmax_bits: int | None,
) -> dict[str, Any]:
    model, module_report = build_quantized_model(fp32_model.cpu(), "w8a8_fake_quant", activation_scales)
    replace_layernorm(model, ln_bits)
    gelu_scale = float(np.median([v for k, v in activation_scales.items() if "mlp.c_fc" in k] or [1.0]))
    if gelu_bits is not None:
        replace_gelu(model, QuantizedGELU(gelu_scale, bits=gelu_bits))
    originals = patch_attention_softmax(model, softmax_bits)
    try:
        metrics = evaluate_model(model, val_data, eval_indices, block_size, device)
    finally:
        restore_attention(originals)
        model.cpu()
    return {
        "name": name,
        "ln_bits": ln_bits,
        "gelu_bits": gelu_bits,
        "softmax_bits": softmax_bits,
        "metrics": metrics,
        "module_count": len(module_report),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Search hardware-friendly INT8 semantics before FPGA deployment.")
    parser.add_argument("--ckpt", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt")
    parser.add_argument("--dataset", default="shakespeare_char")
    parser.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--eval-iters", type=int, default=50)
    parser.add_argument("--calib-iters", type=int, default=50)
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--threshold-pct", type=float, default=10.0)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "hardware_semantics_search",
    )
    args = parser.parse_args()

    fp32_model, checkpoint = load_checkpoint_model(args.ckpt)
    block_size = int(checkpoint["model_args"]["block_size"])
    val_path = NANOGPT_ROOT / "data" / args.dataset / "val.bin"
    val_data = np.memmap(val_path, dtype=np.uint16, mode="r")
    eval_indices = make_batch_indices(len(val_data), block_size, args.batch_size, args.eval_iters, args.seed)
    calib_indices = make_batch_indices(len(val_data), block_size, args.batch_size, args.calib_iters, args.seed + 1)
    activation_scales = calibrate_activation_scales(fp32_model, val_data, calib_indices, block_size, args.device)
    fp32_metrics = evaluate_model(fp32_model, val_data, eval_indices, block_size, args.device)

    variants = [
        ("w8a8_fp_ln_fp_softmax_fp_gelu", None, None, None),
        ("w8a8_q8ln_q8_softmax_q8_gelu", 8, 8, 8),
        ("w8a8_q8ln_q6_softmax_q8_gelu", 8, 8, 6),
        ("w8a8_q7ln_q6_softmax_q8_gelu", 7, 8, 6),
        ("w8a8_q6ln_q6_softmax_q8_gelu", 6, 8, 6),
    ]
    results = []
    best = None
    recommended = None
    for name, ln_bits, gelu_bits, softmax_bits in variants:
        item = run_variant(
            fp32_model,
            val_data,
            eval_indices,
            activation_scales,
            block_size,
            args.device,
            name,
            ln_bits,
            gelu_bits,
            softmax_bits,
        )
        ppl = float(item["metrics"]["perplexity"])
        regression = (ppl - fp32_metrics["perplexity"]) / fp32_metrics["perplexity"] * 100.0
        item["ppl_regression_pct"] = float(regression)
        item["pass"] = bool(np.isfinite(regression) and regression <= args.threshold_pct)
        results.append(item)
        if best is None or regression < best["ppl_regression_pct"]:
            best = item
        if item["pass"] and item["name"] == "w8a8_q6ln_q6_softmax_q8_gelu":
            recommended = item

    out = {
        "threshold_pct": args.threshold_pct,
        "fp32": fp32_metrics,
        "best": best,
        "recommended": recommended if recommended is not None else best,
        "results": results,
        "note": (
            "Search uses deployable approximations for LayerNorm/GELU/softmax on top of W8A8 fake quant. "
            "best is the lowest regression variant; recommended is the lower-bit RTL deployment target when it passes the threshold."
        ),
    }
    args.out_dir.mkdir(parents=True, exist_ok=True)
    (args.out_dir / "results.json").write_text(json.dumps(out, indent=2), encoding="utf-8")
    lines = ["# Hardware Semantics Search", ""]
    lines.append(f"- threshold: `<= {args.threshold_pct:.1f}%`")
    lines.append(f"- fp32_ppl: `{fp32_metrics['perplexity']:.6f}`")
    if best is not None:
        lines.append(f"- best: `{best['name']}` regression `{best['ppl_regression_pct']:.3f}%`")
    if out["recommended"] is not None:
        rec = out["recommended"]
        lines.append(
            f"- recommended_rtl_target: `{rec['name']}` regression `{rec['ppl_regression_pct']:.3f}%`"
        )
    lines.append("")
    lines.append("| variant | ln_bits | softmax_bits | gelu_bits | ppl | regression | pass |")
    lines.append("|---|---:|---:|---:|---:|---:|---|")
    for item in results:
        lines.append(
            f"| `{item['name']}` | `{item['ln_bits']}` | `{item['softmax_bits']}` | `{item['gelu_bits']}` | `{item['metrics']['perplexity']:.6f}` | `{item['ppl_regression_pct']:.3f}%` | `{item['pass']}` |"
        )
    (args.out_dir / "results.md").write_text("\n".join(lines), encoding="utf-8")
    (args.out_dir / "metrics.json").write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(json.dumps(out, indent=2))
    if best is None or not any(item["pass"] for item in results):
        raise SystemExit(2)


if __name__ == "__main__":
    main()
