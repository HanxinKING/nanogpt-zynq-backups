from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import numpy as np
import torch


NANOGPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = NANOGPT_ROOT.parent
if str(NANOGPT_ROOT) not in sys.path:
    sys.path.insert(0, str(NANOGPT_ROOT))

from tools.eval_int8_reference import load_checkpoint_model  # noqa: E402
from tools.validate_int8_autoregressive import load_activation_scales  # noqa: E402


D_MODEL = 384
COEFF_Q_BITS = 24


def compare(reference: np.ndarray, candidate: np.ndarray) -> dict[str, Any]:
    ref = reference.astype(np.int16).reshape(-1)
    cand = candidate.astype(np.int16).reshape(-1)
    diff = np.abs(ref - cand)
    mismatch = np.flatnonzero(diff)
    return {
        "elements": int(ref.size),
        "mismatch": int(mismatch.size),
        "match_ratio": float(1.0 - mismatch.size / ref.size),
        "mean_abs_error": float(diff.mean()),
        "max_abs_error": int(diff.max(initial=0)),
        "within_1_ratio": float(np.mean(diff <= 1)),
        "first_mismatch": int(mismatch[0]) if mismatch.size else None,
    }


def fixed_layernorm_i8(x: np.ndarray, gamma: np.ndarray, activation_scale: float) -> np.ndarray:
    xi = x.astype(np.int64)
    row_sum = xi.sum(axis=1, keepdims=True)
    row_sq_sum = (xi * xi).sum(axis=1, keepdims=True)
    variance_numerator = D_MODEL * row_sq_sum - row_sum * row_sum
    denominator = np.sqrt(np.maximum(variance_numerator.astype(np.float64), 1.0))
    centered_numerator = D_MODEL * xi - row_sum

    coeff_q24 = np.rint(
        gamma.astype(np.float64) / float(activation_scale) * float(1 << COEFF_Q_BITS)
    ).astype(np.int64)
    numerator_q24 = centered_numerator * coeff_q24.reshape(1, -1)
    denominator_q24 = denominator * float(1 << COEFF_Q_BITS)
    q = np.rint(numerator_q24.astype(np.float64) / denominator_q24)
    return np.clip(q, -128, 127).astype(np.int8)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Measure fixed LayerNorm against formal linear inputs.")
    parser.add_argument("--ckpt", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt")
    parser.add_argument(
        "--int8-state",
        type=Path,
        default=NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference" / "int8_state_dict.pt",
    )
    parser.add_argument(
        "--reference-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_alignment" / "reference",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    model, _checkpoint = load_checkpoint_model(args.ckpt)
    activation_scales = load_activation_scales(args.int8_state)
    results: dict[str, Any] = {}

    for layer in range(6):
        prefix = f"layer_{layer:02d}"
        block = model.transformer.h[layer]
        cases = [
            (
                "ln1",
                args.reference_dir / f"{prefix}_input_dynamic_i8.bin",
                args.reference_dir / f"{prefix}_qkv_in_i8.bin",
                block.ln_1.weight.detach().cpu().numpy(),
                activation_scales[f"transformer.h.{layer}.attn.c_attn"],
            ),
            (
                "ln2",
                args.reference_dir / f"{prefix}_res1_dynamic_i8.bin",
                args.reference_dir / f"{prefix}_ffn_mid_in_i8.bin",
                block.ln_2.weight.detach().cpu().numpy(),
                activation_scales[f"transformer.h.{layer}.mlp.c_fc"],
            ),
        ]
        for stage, input_path, reference_path, gamma, activation_scale in cases:
            x = np.frombuffer(input_path.read_bytes(), dtype=np.int8).reshape(256, D_MODEL)
            reference = np.frombuffer(reference_path.read_bytes(), dtype=np.int8).reshape(256, D_MODEL)
            candidate = fixed_layernorm_i8(x, gamma, activation_scale)
            key = f"{prefix}.{stage}"
            results[key] = {
                "activation_scale": float(activation_scale),
                "gamma_min": float(gamma.min()),
                "gamma_max": float(gamma.max()),
                "comparison": compare(reference, candidate),
            }
            (args.reference_dir / f"{prefix}_{stage}_fixed_candidate.bin").write_bytes(candidate.tobytes())

    summary = {
        "kind": "fixed_layernorm_analysis",
        "coefficient_q_bits": COEFF_Q_BITS,
        "results": results,
        "aggregate_mean_abs_error": float(
            np.mean([item["comparison"]["mean_abs_error"] for item in results.values()])
        ),
        "aggregate_within_1_ratio": float(
            np.mean([item["comparison"]["within_1_ratio"] for item in results.values()])
        ),
    }
    out_path = args.reference_dir / "fixed_layernorm_analysis.json"
    out_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
