from __future__ import annotations

import argparse
import json
import pickle
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
from tools.export_quality_exact_hw_full import (  # noqa: E402
    build_quality_model,
    quant_i8_per_tensor,
    run_manual_quality_block,
)
from tools.validate_int8_autoregressive import load_activation_scales  # noqa: E402


def compare_i8(reference: np.ndarray, candidate: np.ndarray) -> dict[str, Any]:
    ref = reference.astype(np.int16).reshape(-1)
    cand = candidate.astype(np.int16).reshape(-1)
    if ref.shape != cand.shape:
        raise ValueError(f"Shape mismatch: {reference.shape} vs {candidate.shape}")
    diff = np.abs(ref - cand)
    indices = np.flatnonzero(diff)
    first = int(indices[0]) if indices.size else None
    return {
        "elements": int(ref.size),
        "mismatch": int(indices.size),
        "match_ratio": float(1.0 - indices.size / ref.size),
        "mean_abs_error": float(diff.mean()),
        "max_abs_error": int(diff.max(initial=0)),
        "first_mismatch_flat_index": first,
        "reference_first16": [int(value) for value in ref[:16]],
        "candidate_first16": [int(value) for value in cand[:16]],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export formal quality stages for INT8 alignment.")
    parser.add_argument("--prompt", default="hello world")
    parser.add_argument("--dataset", default="shakespeare_char")
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--ckpt", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt")
    parser.add_argument(
        "--int8-state",
        type=Path,
        default=NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference" / "int8_state_dict.pt",
    )
    parser.add_argument(
        "--ps-embedding-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "ps_ddr_embedding_tables",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_alignment" / "reference",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    with (NANOGPT_ROOT / "data" / args.dataset / "meta.pkl").open("rb") as handle:
        meta = pickle.load(handle)
    stoi = meta["stoi"]
    prompt_tokens = [int(stoi[ch]) for ch in args.prompt]
    block_size = 256
    tokens = np.full((block_size,), int(stoi[" "]), dtype=np.uint16)
    tokens[: len(prompt_tokens)] = np.asarray(prompt_tokens, dtype=np.uint16)

    fp32_model, checkpoint = load_checkpoint_model(args.ckpt)
    activation_scales = load_activation_scales(args.int8_state)
    quality_model = build_quality_model(
        fp32_model.cpu(), activation_scales, ln_bits=6, softmax_bits=6, gelu_bits=8
    )
    logits, stages, linear_inputs, _hidden = run_manual_quality_block(
        quality_model.to(args.device), tokens, softmax_bits=6, device=args.device
    )

    args.out_dir.mkdir(parents=True, exist_ok=True)
    stage_manifest: dict[str, Any] = {}
    for name, tensor in stages.items():
        array = tensor.squeeze(0).detach().cpu().float().numpy()
        quantized, scale = quant_i8_per_tensor(tensor.squeeze(0))
        stem = name.replace(".", "_")
        np.save(args.out_dir / f"{stem}_float.npy", array)
        (args.out_dir / f"{stem}_dynamic_i8.bin").write_bytes(quantized.tobytes())
        stage_manifest[name] = {
            "shape": list(array.shape),
            "dynamic_i8_scale": float(scale),
            "float_min": float(array.min()),
            "float_max": float(array.max()),
        }

    for name, tensor in linear_inputs.items():
        array = tensor.squeeze(0).detach().cpu().numpy().astype(np.int8)
        stem = name.replace(".", "_")
        (args.out_dir / f"{stem}.bin").write_bytes(array.tobytes())

    logits_np = logits.squeeze(0).detach().cpu().float().numpy()
    argmax = np.argmax(logits_np, axis=1).astype(np.int32)
    np.save(args.out_dir / "logits_float.npy", logits_np)
    (args.out_dir / "argmax_i32.bin").write_bytes(argmax.astype("<i4").tobytes())

    token_q = np.frombuffer(
        (args.ps_embedding_dir / "token_embedding_i8.bin").read_bytes(), dtype=np.int8
    ).reshape(65, 384)
    position_q = np.frombuffer(
        (args.ps_embedding_dir / "position_embedding_i8.bin").read_bytes(), dtype=np.int8
    ).reshape(block_size, 384)
    current_input = np.clip(
        token_q[tokens.astype(np.int64)].astype(np.int16) + position_q.astype(np.int16), -128, 127
    ).astype(np.int8)
    correct_input = np.frombuffer(
        (args.out_dir / "layer_00_input_dynamic_i8.bin").read_bytes(), dtype=np.int8
    ).reshape(block_size, 384)
    (args.out_dir / "current_ps_input_i8.bin").write_bytes(current_input.tobytes())

    last_row = len(prompt_tokens) - 1
    summary = {
        "kind": "int8_alignment_reference",
        "prompt": args.prompt,
        "input_tokens": prompt_tokens,
        "padding_token": int(stoi[" "]),
        "last_prompt_row": last_row,
        "quality_argmax_at_last_prompt_row": int(argmax[last_row]),
        "activation_scale_count": len(activation_scales),
        "model_args": checkpoint["model_args"],
        "embedding_compare": compare_i8(correct_input, current_input),
        "embedding_last_row_compare": compare_i8(correct_input[last_row], current_input[last_row]),
        "stages": stage_manifest,
        "linear_input_files": sorted(linear_inputs.keys()),
    }
    out_path = args.out_dir / "reference_manifest.json"
    out_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    print(f"REFERENCE_MANIFEST={out_path}")


if __name__ == "__main__":
    main()
