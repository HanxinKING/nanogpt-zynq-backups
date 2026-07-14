from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import numpy as np


NANOGPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = NANOGPT_ROOT.parent


def write_hex(path: Path, values: np.ndarray, width: int) -> None:
    mask = (1 << width) - 1
    digits = (width + 3) // 4
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii") as f:
        for value in values.reshape(-1):
            f.write(f"{int(value) & mask:0{digits}x}\n")


def gelu_lut_i16(scale: float, in_min: int = -128, in_max: int = 127) -> np.ndarray:
    xs = np.arange(in_min, in_max + 1, dtype=np.float64)
    xf = xs * scale
    yf = 0.5 * xf * (1.0 + np.tanh(math.sqrt(2.0 / math.pi) * (xf + 0.044715 * xf**3)))
    q = np.clip(np.rint(yf / scale), -32768, 32767).astype(np.int32)
    return q


def exp2_lut_q15(diff_min: int = -256, diff_max: int = 0, shift: int = 6) -> np.ndarray:
    diffs = np.arange(diff_min, diff_max + 1, dtype=np.float64)
    vals = np.exp2(diffs / float(1 << shift))
    q = np.clip(np.rint(vals * 32768.0), 0, 32767).astype(np.int32)
    return q


def reciprocal_lut_q15(max_sum: int = 4096) -> np.ndarray:
    xs = np.arange(1, max_sum + 1, dtype=np.float64)
    vals = 1.0 / xs
    q = np.clip(np.rint(vals * 32768.0), 0, 32767).astype(np.int32)
    return q


def parse_metrics(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Export quality INT8 hardware contract LUTs and manifest.")
    parser.add_argument(
        "--quality-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_hw_ppl_pass_s256_d384_l6",
    )
    parser.add_argument("--activation-scale", type=float, default=1.0)
    args = parser.parse_args()

    quality_dir = args.quality_dir
    lut_dir = quality_dir / "luts"
    metrics = parse_metrics(quality_dir / "quality_metrics.json")
    manifest = parse_metrics(quality_dir / "quality_manifest.json")

    gelu = gelu_lut_i16(args.activation_scale)
    exp2 = exp2_lut_q15()
    recip = reciprocal_lut_q15()
    write_hex(lut_dir / "gelu_int8_to_i16.mem", gelu, 16)
    write_hex(lut_dir / "softmax_exp2_q15.mem", exp2, 16)
    write_hex(lut_dir / "softmax_recip_q15.mem", recip, 16)

    contract = {
        "kind": "quality_hw_deploy_contract",
        "ppl_gate": {
            "status": "PASS" if metrics["pass"] else "FAIL",
            "fp32_perplexity": metrics["fp32"]["perplexity"],
            "quality_int8_perplexity": metrics["int8"]["perplexity"],
            "ppl_regression_pct": metrics["ppl_regression_pct"],
            "threshold_pct": metrics["pass_threshold_pct"],
        },
        "required_pl_semantics": {
            "layernorm": "mean + variance normalization with reciprocal sqrt approximation or closer",
            "attention": "causal softmax attention approximation, not argmax attention",
            "gelu": "GELU LUT or piecewise equivalent, not identity",
            "scales": "per-layer/per-stage scale or shift from manifest; no single global shift",
            "matmul": "int8 x int8 -> int32 accumulate",
            "lm_head": "int8 x int8 -> int32 logits and argmax",
        },
        "luts": {
            "gelu_int8_to_i16": {
                "file": "luts/gelu_int8_to_i16.mem",
                "entries": int(gelu.size),
                "input_range": [-128, 127],
                "width": 16,
            },
            "softmax_exp2_q15": {
                "file": "luts/softmax_exp2_q15.mem",
                "entries": int(exp2.size),
                "input_diff_range": [-256, 0],
                "score_shift": 6,
                "width": 16,
            },
            "softmax_recip_q15": {
                "file": "luts/softmax_recip_q15.mem",
                "entries": int(recip.size),
                "sum_range": [1, int(recip.size)],
                "width": 16,
            },
        },
        "source_manifest": manifest,
    }
    (quality_dir / "quality_deploy_contract.json").write_text(
        json.dumps(contract, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    print(json.dumps({"contract": str(quality_dir / "quality_deploy_contract.json")}, indent=2))


if __name__ == "__main__":
    main()
