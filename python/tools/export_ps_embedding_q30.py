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

from tools.eval_int8_reference import load_torch  # noqa: E402


Q_BITS = 30
Q_ONE = 1 << Q_BITS


def round_div_signed(values: np.ndarray, denominator: int) -> np.ndarray:
    wide = values.astype(np.int64)
    absolute = np.abs(wide)
    rounded = (absolute + denominator // 2) // denominator
    return np.where(wide < 0, -rounded, rounded)


def compare_i8(reference: np.ndarray, candidate: np.ndarray) -> dict[str, Any]:
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
        "first_mismatch_flat_index": int(mismatch[0]) if mismatch.size else None,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export per-row Q30 embedding scales for PS.")
    parser.add_argument("--prompt", default="hello world")
    parser.add_argument("--dataset", default="shakespeare_char")
    parser.add_argument(
        "--int8-state",
        type=Path,
        default=NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference" / "int8_state_dict.pt",
    )
    parser.add_argument(
        "--embedding-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "ps_ddr_embedding_tables",
    )
    parser.add_argument(
        "--reference-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_alignment" / "reference",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    state = load_torch(args.int8_state, map_location="cpu")
    token_module = state["modules"]["transformer.wte"]
    position_module = state["modules"]["transformer.wpe"]
    token_q = token_module["qweight"].detach().cpu().numpy().astype(np.int8)
    position_q = position_module["qweight"].detach().cpu().numpy().astype(np.int8)
    token_scale = token_module["weight_scale"].detach().cpu().numpy().astype(np.float32)
    position_scale = position_module["weight_scale"].detach().cpu().numpy().astype(np.float32)
    token_scale_q30 = np.rint(token_scale.astype(np.float64) * Q_ONE).astype(np.int32)
    position_scale_q30 = np.rint(position_scale.astype(np.float64) * Q_ONE).astype(np.int32)

    args.embedding_dir.mkdir(parents=True, exist_ok=True)
    token_scale_path = args.embedding_dir / "token_embedding_scale_q30.bin"
    position_scale_path = args.embedding_dir / "position_embedding_scale_q30.bin"
    token_scale_path.write_bytes(token_scale_q30.astype("<i4").tobytes())
    position_scale_path.write_bytes(position_scale_q30.astype("<i4").tobytes())

    with (NANOGPT_ROOT / "data" / args.dataset / "meta.pkl").open("rb") as handle:
        meta = pickle.load(handle)
    stoi = meta["stoi"]
    prompt_tokens = [int(stoi[ch]) for ch in args.prompt]
    tokens = np.full((256,), int(stoi[" "]), dtype=np.int64)
    tokens[: len(prompt_tokens)] = np.asarray(prompt_tokens, dtype=np.int64)

    token_terms = token_q[tokens].astype(np.int64) * token_scale_q30[tokens, None].astype(np.int64)
    position_terms = position_q.astype(np.int64) * position_scale_q30[:, None].astype(np.int64)
    hidden_q30 = token_terms + position_terms
    max_abs_q30 = int(np.abs(hidden_q30).max())
    ps_i8 = np.clip(round_div_signed(hidden_q30 * 127, max_abs_q30), -128, 127).astype(np.int8)
    (args.embedding_dir / "hello_world_hidden_q30_i8.bin").write_bytes(ps_i8.tobytes())

    reference = np.frombuffer(
        (args.reference_dir / "layer_00_input_dynamic_i8.bin").read_bytes(), dtype=np.int8
    ).reshape(256, 384)
    comparison = compare_i8(reference, ps_i8)
    manifest = {
        "kind": "ps_embedding_q30",
        "q_bits": Q_BITS,
        "token_scale": {
            "shape": list(token_scale_q30.shape),
            "ddr_base": "0x13028000",
            "file": str(token_scale_path),
        },
        "position_scale": {
            "shape": list(position_scale_q30.shape),
            "ddr_base": "0x13028400",
            "file": str(position_scale_path),
        },
        "algorithm": "hidden_q30 = token_i8*token_scale_q30 + position_i8*position_scale_q30; hidden_i8 = round(hidden_q30*127/max_abs_q30)",
        "prompt": args.prompt,
        "max_abs_q30": max_abs_q30,
        "comparison_to_quality_input": comparison,
    }
    manifest_path = args.embedding_dir / "q30_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    if comparison["max_abs_error"] > 1:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
