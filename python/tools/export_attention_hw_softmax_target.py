from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
import torch


REPO_ROOT = Path(__file__).resolve().parents[2]
SEQ_LEN = 256
D_MODEL = 384
N_HEAD = 6
HEAD_DIM = D_MODEL // N_HEAD
N_LAYER = 6


def write_hex(path: Path, array: np.ndarray, width: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mask = (1 << width) - 1
    digits = (width + 3) // 4
    with path.open("w", encoding="ascii") as f:
        for value in array.reshape(-1):
            f.write(f"{int(value) & mask:0{digits}x}\n")


def write_bin(path: Path, array: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(array.astype(np.int8).reshape(-1).tobytes())


def read_i8(path: Path) -> np.ndarray:
    return np.frombuffer(path.read_bytes(), dtype=np.int8).reshape(SEQ_LEN, D_MODEL)


def qsoftmax_from_hw_qkv(
    q_i8: np.ndarray,
    k_i8: np.ndarray,
    v_i8: np.ndarray,
    q_scale: float,
    k_scale: float,
    v_scale: float,
    out_scale: float,
    softmax_bits: int,
    temperature: float,
) -> np.ndarray:
    qmax = (1 << softmax_bits) - 1
    out = np.zeros((SEQ_LEN, D_MODEL), dtype=np.int8)
    for head in range(N_HEAD):
        start = head * HEAD_DIM
        end = start + HEAD_DIM
        q = torch.tensor(q_i8[:, start:end].astype(np.float32) * q_scale)
        k = torch.tensor(k_i8[:, start:end].astype(np.float32) * k_scale)
        v = torch.tensor(v_i8[:, start:end].astype(np.float32) * v_scale)
        scores = (q @ k.T) * (temperature / math.sqrt(HEAD_DIM))
        mask = torch.tril(torch.ones(SEQ_LEN, SEQ_LEN, dtype=torch.bool))
        scores = scores.masked_fill(~mask, -float("inf"))
        probs = torch.softmax(scores, dim=-1)
        qprob = torch.clamp(torch.round(probs * qmax), 0, qmax)
        probs_q = qprob / torch.clamp(qprob.sum(dim=-1, keepdim=True), min=1.0)
        attn = probs_q @ v
        out[:, start:end] = torch.clamp(torch.round(attn / out_scale), -128, 127).to(torch.int8).numpy()
    return out


def compare(a: np.ndarray, b: np.ndarray) -> dict[str, object]:
    flat_a = a.reshape(-1)
    flat_b = b.reshape(-1)
    mismatch = flat_a != flat_b
    first = int(np.argmax(mismatch)) if mismatch.any() else -1
    return {
        "mismatch": int(mismatch.sum()),
        "total": int(flat_a.size),
        "mae": float(np.mean(np.abs(flat_a.astype(np.int16) - flat_b.astype(np.int16)))),
        "first": first,
        "got": int(flat_a[first]) if first >= 0 else None,
        "expected": int(flat_b[first]) if first >= 0 else None,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Export hardware-QKV q-softmax attention target.")
    parser.add_argument(
        "--root",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_quality_hw_exact_s256_d384_l6",
    )
    parser.add_argument("--softmax-bits", type=int, default=6)
    parser.add_argument("--temperature", type=float, default=1.0)
    args = parser.parse_args()

    metrics = json.loads((args.root / "metrics.json").read_text(encoding="utf-8"))
    requant = json.loads((args.root / "requant_params_manifest.json").read_text(encoding="utf-8"))
    summary: dict[str, object] = {
        "kind": "hardware_qkv_qsoftmax_attention_target",
        "softmax_bits": args.softmax_bits,
        "temperature": args.temperature,
        "layers": [],
    }

    for layer in range(N_LAYER):
        layer_name = f"layer_{layer:02d}"
        layer_dir = args.root / "layers" / layer_name
        q = read_i8(layer_dir / "q.bin")
        k = read_i8(layer_dir / "k.bin")
        v = read_i8(layer_dir / "v.bin")
        q_scale = float(metrics["stage_quant"][f"{layer_name}.q"]["scale"])
        k_scale = float(metrics["stage_quant"][f"{layer_name}.k"]["scale"])
        v_scale = float(metrics["stage_quant"][f"{layer_name}.v"]["scale"])
        out_scale = float(requant["entries"][f"{layer_name}.attn_proj"]["activation_scale"])
        out = qsoftmax_from_hw_qkv(
            q,
            k,
            v,
            q_scale,
            k_scale,
            v_scale,
            out_scale,
            args.softmax_bits,
            args.temperature,
        )
        write_bin(layer_dir / "attn_proj_in_hw_softmax.bin", out)
        write_hex(layer_dir / "attn_proj_in_hw_softmax.mem", out, 8)
        expected_path = layer_dir / "attn_proj_in_i8.bin"
        entry = {"layer": layer_name, "output": f"layers/{layer_name}/attn_proj_in_hw_softmax.mem"}
        if expected_path.exists():
            entry["vs_quality_attn_proj_in_i8"] = compare(out, read_i8(expected_path))
        summary["layers"].append(entry)

    out_path = args.root / "attention_hw_softmax_summary.json"
    out_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
