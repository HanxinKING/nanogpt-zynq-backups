from __future__ import annotations

import argparse
import copy
import json
import math
import pickle
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
    load_checkpoint_model,
    make_batch_indices,
)
from tools.search_hardware_semantics import (  # noqa: E402
    QuantizedGELU,
    patch_attention_softmax,
    replace_gelu,
    replace_layernorm,
)


SEQ_LEN = 256
D_MODEL = 384
N_LAYER = 6
VOCAB_SIZE = 65


def load_meta(dataset: str) -> dict[str, Any]:
    with (NANOGPT_ROOT / "data" / dataset / "meta.pkl").open("rb") as f:
        return pickle.load(f)


def load_tokens(dataset: str, token_offset: int) -> tuple[np.ndarray, np.ndarray]:
    val = np.memmap(NANOGPT_ROOT / "data" / dataset / "val.bin", dtype=np.uint16, mode="r")
    tokens = np.asarray(val[token_offset : token_offset + SEQ_LEN], dtype=np.int64)
    targets = np.asarray(val[token_offset + 1 : token_offset + 1 + SEQ_LEN], dtype=np.int64)
    if tokens.size != SEQ_LEN or targets.size != SEQ_LEN:
        raise ValueError("not enough validation tokens")
    return tokens, targets


def write_hex(path: Path, array: np.ndarray, width: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mask = (1 << width) - 1
    digits = (width + 3) // 4
    with path.open("w", encoding="ascii") as f:
        for value in array.reshape(-1):
            f.write(f"{int(value) & mask:0{digits}x}\n")


def write_bin(path: Path, array: np.ndarray, dtype: np.dtype) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(array.astype(dtype).reshape(-1).tobytes())


def write_i32_mem(path: Path, array: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii") as f:
        for value in array.reshape(-1):
            f.write(f"{int(value) & 0xFFFFFFFF:08x}\n")


def quant_i8_per_tensor(x: torch.Tensor) -> tuple[np.ndarray, float]:
    max_abs = float(x.detach().abs().max().item())
    scale = max(max_abs / 127.0, float(torch.finfo(torch.float32).eps))
    q = torch.clamp(torch.round(x.detach().cpu().float() / scale), -128, 127).to(torch.int8)
    return q.numpy().astype(np.int8), scale


def quant_i8_fixed(x: torch.Tensor, scale: float) -> torch.Tensor:
    return torch.clamp(torch.round(x.float() / float(scale)), -128, 127).to(torch.int8)


def choose_requant_params(real_scales: np.ndarray, max_shift: int = 30) -> tuple[np.ndarray, np.ndarray]:
    shifts = np.full(real_scales.shape, max_shift, dtype=np.int32)
    mult = np.rint(real_scales.astype(np.float64) * float(1 << max_shift)).astype(np.int64)
    mult = np.clip(mult, 0, (1 << 31) - 1).astype(np.int32)
    return mult, shifts


def round_requant_i32(acc: np.ndarray, mult: np.ndarray, shift: int = 30) -> np.ndarray:
    scaled = acc.astype(np.int64) * mult.reshape(1, -1).astype(np.int64)
    rounded = np.where(
        scaled >= 0,
        (scaled + (1 << (shift - 1))) >> shift,
        -(((-scaled) + (1 << (shift - 1))) >> shift),
    )
    return np.clip(rounded, -128, 127).astype(np.int8)


def residual_requant_tensor(a: torch.Tensor, b: torch.Tensor, out_bits: int = 8) -> tuple[torch.Tensor, float]:
    qmax = (1 << (out_bits - 1)) - 1
    qmin = -(1 << (out_bits - 1))
    y = a.float() + b.float()
    scale_a = torch.clamp(a.detach().abs().amax() / qmax, min=torch.finfo(torch.float32).eps)
    scale_b = torch.clamp(b.detach().abs().amax() / qmax, min=torch.finfo(torch.float32).eps)
    scale_y = torch.clamp(y.detach().abs().amax() / qmax, min=torch.finfo(torch.float32).eps)
    qa = torch.clamp(torch.round(a.float() / scale_a), qmin, qmax)
    qb = torch.clamp(torch.round(b.float() / scale_b), qmin, qmax)
    q = torch.clamp(torch.round(((qa * scale_a) + (qb * scale_b)) / scale_y), qmin, qmax)
    return q * scale_y, float(scale_y.detach().cpu())


def export_requant_params(out_dir: Path, modules: dict[str, Any], stage_quant: dict[str, dict[str, Any]]) -> dict[str, Any]:
    entries: dict[str, Any] = {}
    scale_dir = out_dir / "scale_params"

    def emit(name: str, module_key: str, output_scale: float, q_slice: slice | None = None) -> None:
        mod = modules[module_key]
        weight_scale = mod["weight_scale"].detach().cpu().numpy().astype(np.float64)
        if q_slice is not None:
            weight_scale = weight_scale[q_slice]
        act_scale = float(mod.get("activation_scale") or 1.0)
        real = act_scale * weight_scale / float(output_scale)
        mult, shift = choose_requant_params(real)
        rel = name.replace(".", "_")
        write_i32_mem(scale_dir / f"{rel}_mult_q30.mem", mult)
        write_i32_mem(scale_dir / f"{rel}_shift.mem", shift)
        entries[name] = {
            "module": module_key,
            "output_scale": float(output_scale),
            "activation_scale": act_scale,
            "channels": int(real.size),
            "mult_file": f"scale_params/{rel}_mult_q30.mem",
            "shift_file": f"scale_params/{rel}_shift.mem",
            "mult_frac_bits": 30,
            "real_scale_min": float(real.min()),
            "real_scale_max": float(real.max()),
        }

    for layer in range(N_LAYER):
        prefix = f"layer_{layer:02d}"
        c_attn = f"transformer.h.{layer}.attn.c_attn"
        emit(f"{prefix}.q", c_attn, stage_quant[f"{prefix}.q"]["scale"], slice(0, D_MODEL))
        emit(f"{prefix}.k", c_attn, stage_quant[f"{prefix}.k"]["scale"], slice(D_MODEL, 2 * D_MODEL))
        emit(f"{prefix}.v", c_attn, stage_quant[f"{prefix}.v"]["scale"], slice(2 * D_MODEL, 3 * D_MODEL))
        emit(f"{prefix}.attn_proj", f"transformer.h.{layer}.attn.c_proj", stage_quant[f"{prefix}.attn_proj"]["scale"])
        emit(f"{prefix}.ffn_mid", f"transformer.h.{layer}.mlp.c_fc", stage_quant[f"{prefix}.ffn_mid"]["scale"])
        emit(f"{prefix}.ffn", f"transformer.h.{layer}.mlp.c_proj", stage_quant[f"{prefix}.ffn"]["scale"])
    emit("lm_head", "lm_head", 1.0)
    manifest = {"kind": "quality_exact_requant_params", "entries": entries}
    (out_dir / "requant_params_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def overwrite_integer_linear_stages(out_dir: Path, modules: dict[str, Any]) -> dict[str, Any]:
    summary: dict[str, Any] = {"kind": "integer_linear_stage_rewrite", "entries": {}}

    def read_i8(rel: str, shape: tuple[int, ...]) -> np.ndarray:
        return np.frombuffer((out_dir / rel).read_bytes(), dtype=np.int8).reshape(shape).astype(np.int32)

    def read_mult(name: str) -> np.ndarray:
        path = out_dir / "scale_params" / f"{name}_mult_q30.mem"
        return np.array([int(x.strip(), 16) for x in path.read_text(encoding="ascii").splitlines() if x.strip()], dtype=np.int64)

    def write_stage(layer: int, stage: str, data: np.ndarray) -> None:
        stage_dir = out_dir / "layers" / f"layer_{layer:02d}"
        write_hex(stage_dir / f"{stage}.mem", data, 8)
        write_bin(stage_dir / f"{stage}.bin", data, np.int8)

    for layer in range(N_LAYER):
        prefix = f"layer_{layer:02d}"
        qkv_in = read_i8(f"layers/{prefix}/qkv_in_i8.bin", (SEQ_LEN, D_MODEL))
        c_attn = modules[f"transformer.h.{layer}.attn.c_attn"]["qweight"].detach().cpu().numpy().astype(np.int32)
        for stage, sl in [("q", slice(0, D_MODEL)), ("k", slice(D_MODEL, 2 * D_MODEL)), ("v", slice(2 * D_MODEL, 3 * D_MODEL))]:
            acc = qkv_in @ c_attn[sl, :].T
            out = round_requant_i32(acc, read_mult(f"{prefix}_{stage}"))
            write_stage(layer, stage, out)
            summary["entries"][f"{prefix}.{stage}"] = {"source": "integer_q30_requant", "shape": [SEQ_LEN, D_MODEL]}

    (out_dir / "integer_stage_rewrite.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def softmax_cross_entropy(logits: np.ndarray, targets: np.ndarray) -> tuple[float, float]:
    logits64 = logits.astype(np.float64)
    logits64 -= logits64.max(axis=1, keepdims=True)
    exp = np.exp(logits64)
    probs = exp / exp.sum(axis=1, keepdims=True)
    nll = -np.log(np.maximum(probs[np.arange(logits.shape[0]), targets], 1e-300))
    loss = float(nll.mean())
    return loss, float(math.exp(loss))


def quantized_softmax(scores: torch.Tensor, bits: int) -> torch.Tensor:
    probs = F.softmax(scores, dim=-1)
    qmax = (1 << bits) - 1
    q = torch.clamp(torch.round(probs * qmax), 0, qmax)
    denom = torch.clamp(q.sum(dim=-1, keepdim=True), min=1.0)
    return q / denom


def build_quality_model(
    fp32_model: GPT,
    activation_scales: dict[str, float],
    ln_bits: int,
    softmax_bits: int,
    gelu_bits: int,
) -> GPT:
    model, _module_report = build_quantized_model(fp32_model.cpu(), "w8a8_fake_quant", activation_scales)
    replace_layernorm(model, ln_bits)
    gelu_scale = float(np.median([v for k, v in activation_scales.items() if "mlp.c_fc" in k] or [1.0]))
    replace_gelu(model, QuantizedGELU(gelu_scale, bits=gelu_bits))
    patch_attention_softmax(model, softmax_bits)
    model.eval()
    return model


@torch.no_grad()
def run_manual_quality_block(model: GPT, tokens: np.ndarray, softmax_bits: int, device: str) -> tuple[torch.Tensor, dict[str, torch.Tensor], dict[str, torch.Tensor], torch.Tensor]:
    idx = torch.tensor(tokens, dtype=torch.long, device=device).unsqueeze(0)
    pos = torch.arange(0, idx.size(1), dtype=torch.long, device=device)
    hidden = model.transformer.drop(model.transformer.wte(idx) + model.transformer.wpe(pos))
    stage_tensors: dict[str, torch.Tensor] = {}
    linear_inputs_i8: dict[str, torch.Tensor] = {}
    for layer, block in enumerate(model.transformer.h):
        prefix = f"layer_{layer:02d}"
        stage_tensors[f"{prefix}.input"] = hidden.detach().cpu()
        ln1 = block.ln_1(hidden)
        qkv_in_q = quant_i8_fixed(ln1, float(block.attn.c_attn.activation_scale)).float()
        linear_inputs_i8[f"layer_{layer:02d}.qkv_in_i8"] = qkv_in_q.to(torch.int8).detach().cpu()
        qkv = block.attn.c_attn(ln1)
        q_raw, k_raw, v_raw = qkv.split(block.attn.n_embd, dim=2)
        bsz, seq, channels = hidden.size()
        head_dim = channels // block.attn.n_head
        q = q_raw.view(bsz, seq, block.attn.n_head, head_dim).transpose(1, 2)
        k = k_raw.view(bsz, seq, block.attn.n_head, head_dim).transpose(1, 2)
        v = v_raw.view(bsz, seq, block.attn.n_head, head_dim).transpose(1, 2)
        scores = (q @ k.transpose(-2, -1)) * (1.0 / math.sqrt(head_dim))
        mask = torch.tril(torch.ones(seq, seq, device=device, dtype=torch.bool))
        scores = scores.masked_fill(~mask, float("-inf"))
        probs = quantized_softmax(scores, softmax_bits)
        attn_raw = probs @ v
        attn_raw = attn_raw.transpose(1, 2).contiguous().view(bsz, seq, channels)
        attn_proj_in_q = quant_i8_fixed(attn_raw, float(block.attn.c_proj.activation_scale)).float()
        linear_inputs_i8[f"layer_{layer:02d}.attn_proj_in_i8"] = attn_proj_in_q.to(torch.int8).detach().cpu()
        attn_proj = block.attn.resid_dropout(block.attn.c_proj(attn_raw))
        res1, _res1_scale = residual_requant_tensor(hidden, attn_proj)
        ln2 = block.ln_2(res1)
        ffn_mid_in_q = quant_i8_fixed(ln2, float(block.mlp.c_fc.activation_scale)).float()
        linear_inputs_i8[f"layer_{layer:02d}.ffn_mid_in_i8"] = ffn_mid_in_q.to(torch.int8).detach().cpu()
        ffn_mid = block.mlp.c_fc(ln2)
        ffn_gelu = block.mlp.gelu(ffn_mid)
        ffn_in_q = quant_i8_fixed(ffn_gelu, float(block.mlp.c_proj.activation_scale)).float()
        linear_inputs_i8[f"layer_{layer:02d}.ffn_in_i8"] = ffn_in_q.to(torch.int8).detach().cpu()
        ffn = block.mlp.dropout(block.mlp.c_proj(ffn_gelu))
        final, _final_scale = residual_requant_tensor(res1, ffn)
        stage_tensors[f"{prefix}.ln1"] = ln1.detach().cpu()
        stage_tensors[f"{prefix}.q"] = q.transpose(1, 2).contiguous().view(bsz, seq, channels).detach().cpu()
        stage_tensors[f"{prefix}.k"] = k.transpose(1, 2).contiguous().view(bsz, seq, channels).detach().cpu()
        stage_tensors[f"{prefix}.v"] = v.transpose(1, 2).contiguous().view(bsz, seq, channels).detach().cpu()
        stage_tensors[f"{prefix}.attn"] = attn_raw.detach().cpu()
        stage_tensors[f"{prefix}.attn_proj"] = attn_proj.detach().cpu()
        stage_tensors[f"{prefix}.res1"] = res1.detach().cpu()
        stage_tensors[f"{prefix}.ln2"] = ln2.detach().cpu()
        stage_tensors[f"{prefix}.ffn_mid"] = ffn_mid.detach().cpu()
        stage_tensors[f"{prefix}.ffn_gelu"] = ffn_gelu.detach().cpu()
        stage_tensors[f"{prefix}.ffn"] = ffn.detach().cpu()
        stage_tensors[f"{prefix}.final"] = final.detach().cpu()
        hidden = final
    ln_f = model.transformer.ln_f(hidden)
    logits = model.lm_head(ln_f)
    stage_tensors["ln_f"] = ln_f.detach().cpu()
    return logits, stage_tensors, linear_inputs_i8, hidden.detach().cpu()


@torch.no_grad()
def export_one_block(args: argparse.Namespace) -> dict[str, Any]:
    fp32_model, checkpoint = load_checkpoint_model(args.ckpt)
    val_path = NANOGPT_ROOT / "data" / args.dataset / "val.bin"
    val_data = np.memmap(val_path, dtype=np.uint16, mode="r")
    block_size = int(checkpoint["model_args"]["block_size"])
    eval_indices = make_batch_indices(len(val_data), block_size, args.batch_size, args.eval_iters, args.seed)
    calib_indices = make_batch_indices(len(val_data), block_size, args.batch_size, args.calib_iters, args.seed + 1)
    activation_scales = calibrate_activation_scales(fp32_model, val_data, calib_indices, block_size, args.device)

    fp32_metrics = evaluate_model(copy.deepcopy(fp32_model), val_data, eval_indices, block_size, args.device)
    quality_model = build_quality_model(fp32_model, activation_scales, args.ln_bits, args.softmax_bits, args.gelu_bits)
    quality_metrics = evaluate_model(quality_model, val_data, eval_indices, block_size, args.device)
    regression = (quality_metrics["perplexity"] - fp32_metrics["perplexity"]) / fp32_metrics["perplexity"] * 100.0

    quality_model.to(args.device)
    quality_model.eval()
    tokens, targets = load_tokens(args.dataset, args.token_offset)
    logits, stage_tensors, linear_inputs_i8, _hidden = run_manual_quality_block(quality_model, tokens, args.softmax_bits, args.device)
    y = torch.tensor(targets, dtype=torch.long, device=args.device).unsqueeze(0)
    loss_tensor = F.cross_entropy(logits.view(-1, logits.size(-1)), y.view(-1), ignore_index=-1)

    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    layers_dir = out_dir / "layers"
    stage_quant: dict[str, dict[str, Any]] = {}
    for name, tensor in stage_tensors.items():
        arr = tensor.squeeze(0)
        q, scale = quant_i8_per_tensor(arr)
        stage_quant[name] = {"shape": list(q.shape), "scale": scale}
        if name.startswith("layer_"):
            layer, stage = name.split(".")
            stage_dir = layers_dir / layer
            write_hex(stage_dir / f"{stage}.mem", q, 8)
            write_bin(stage_dir / f"{stage}.bin", q, np.int8)
        else:
            write_hex(out_dir / f"{name}.mem", q, 8)
            write_bin(out_dir / f"{name}.bin", q, np.int8)
    for name, tensor in linear_inputs_i8.items():
        arr = tensor.squeeze(0).numpy().astype(np.int8)
        layer, stage = name.split(".")
        stage_dir = layers_dir / layer
        write_hex(stage_dir / f"{stage}.mem", arr, 8)
        write_bin(stage_dir / f"{stage}.bin", arr, np.int8)
    quant_modules = getattr(quality_model, "_modules")

    logits_np = logits.squeeze(0).detach().cpu().numpy().astype(np.float32)
    logits_i32 = np.rint(logits_np * args.logit_scale).astype(np.int32)
    argmax = np.argmax(logits_i32, axis=1).astype(np.int32)
    block_loss, block_ppl = softmax_cross_entropy(logits_np, targets)

    write_hex(out_dir / "logits_i32.mem", logits_i32, 32)
    write_bin(out_dir / "logits_i32.bin", logits_i32, np.dtype("<i4"))
    write_hex(out_dir / "argmax_tokens.mem", argmax, 16)
    write_hex(out_dir / "target_tokens.mem", targets.astype(np.int32), 16)
    write_hex(out_dir / "input_tokens.mem", tokens.astype(np.int32), 16)

    final_src = layers_dir / "layer_05" / "final"
    (out_dir / "final.bin").write_bytes((final_src.with_suffix(".bin")).read_bytes())
    (out_dir / "final.mem").write_text((final_src.with_suffix(".mem")).read_text(encoding="ascii"), encoding="ascii")

    metadata = {
        "kind": "quality_exact_hw_full",
        "checkpoint": str(args.ckpt),
        "dataset": args.dataset,
        "token_offset": args.token_offset,
        "seq_len": SEQ_LEN,
        "d_model": D_MODEL,
        "n_layer": N_LAYER,
        "vocab_size": VOCAB_SIZE,
        "semantics": {
            "base": "w8a8_fake_quant",
            "ln_bits": args.ln_bits,
            "softmax_bits": args.softmax_bits,
            "gelu_bits": args.gelu_bits,
        },
        "threshold_pct": args.threshold_pct,
        "fp32": fp32_metrics,
        "quality_exact": quality_metrics,
        "ppl_regression_pct": float(regression),
        "pass": bool(np.isfinite(regression) and regression <= args.threshold_pct),
        "single_block_loss": float(block_loss),
        "single_block_perplexity": float(block_ppl),
        "loss_from_model": float(loss_tensor.item()),
        "logit_scale": args.logit_scale,
        "stage_quant": stage_quant,
        "activation_scales": activation_scales,
        "argmax_first32": [int(v) for v in argmax[:32]],
        "target_first32": [int(v) for v in targets[:32]],
    }
    int8_state_path = args.int8_state
    if int8_state_path.exists():
        try:
            int8_state = torch.load(int8_state_path, map_location="cpu", weights_only=False)
        except TypeError:
            int8_state = torch.load(int8_state_path, map_location="cpu")
        metadata["requant_params"] = export_requant_params(out_dir, int8_state["modules"], stage_quant)
        metadata["integer_stage_rewrite"] = overwrite_integer_linear_stages(out_dir, int8_state["modules"])
    (out_dir / "metrics.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    lines = [
        "# Quality Exact HW Full INT8",
        "",
        f"- result: `{'PASS' if metadata['pass'] else 'FAIL'}`",
        f"- fp32_ppl: `{fp32_metrics['perplexity']:.6f}`",
        f"- quality_exact_ppl: `{quality_metrics['perplexity']:.6f}`",
        f"- ppl_regression_pct: `{regression:.3f}%`",
        f"- threshold: `<= {args.threshold_pct:.1f}%`",
        f"- semantics: `W8A8 + q{args.ln_bits} LN + q{args.softmax_bits} softmax + q{args.gelu_bits} GELU`",
        f"- out_dir: `{out_dir.as_posix()}`",
        "",
    ]
    (out_dir / "metrics.md").write_text("\n".join(lines), encoding="utf-8")
    return metadata


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export the quality-passing hardware-exact full INT8 target.")
    parser.add_argument("--ckpt", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt")
    parser.add_argument("--int8-state", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference" / "int8_state_dict.pt")
    parser.add_argument("--dataset", default="shakespeare_char")
    parser.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--eval-iters", type=int, default=200)
    parser.add_argument("--calib-iters", type=int, default=200)
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--token-offset", type=int, default=0)
    parser.add_argument("--threshold-pct", type=float, default=10.0)
    parser.add_argument("--ln-bits", type=int, default=6)
    parser.add_argument("--softmax-bits", type=int, default=6)
    parser.add_argument("--gelu-bits", type=int, default=8)
    parser.add_argument("--logit-scale", type=float, default=1024.0)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_quality_hw_exact_s256_d384_l6",
    )
    return parser.parse_args()


def main() -> None:
    metrics = export_one_block(parse_args())
    print(json.dumps({
        "out_dir": metrics["kind"],
        "pass": metrics["pass"],
        "fp32_ppl": metrics["fp32"]["perplexity"],
        "quality_exact_ppl": metrics["quality_exact"]["perplexity"],
        "ppl_regression_pct": metrics["ppl_regression_pct"],
        "argmax_first32": metrics["argmax_first32"],
    }, indent=2))
    if not metrics["pass"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
