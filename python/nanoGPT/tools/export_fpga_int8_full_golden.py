from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

import numpy as np
import torch


NANOGPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = NANOGPT_ROOT.parent
if str(NANOGPT_ROOT) not in sys.path:
    sys.path.insert(0, str(NANOGPT_ROOT))


SEQ_LEN = 256
D_MODEL = 384
N_LAYER = 6
N_HEAD = 6
HEAD_DIM = 64
MLP_DIM = 4 * D_MODEL
VOCAB_SIZE = 65

STAGES = ["input", "ln1", "q", "k", "v", "attn", "res1", "ln2", "ffn", "final"]


def load_torch(path: Path) -> Any:
    try:
        return torch.load(path, map_location="cpu", weights_only=False)
    except TypeError:
        return torch.load(path, map_location="cpu")


def load_int8_modules(path: Path) -> dict[str, dict[str, Any]]:
    state = load_torch(path)
    return state["modules"]


def qweight(modules: dict[str, dict[str, Any]], name: str) -> np.ndarray:
    return modules[name]["qweight"].detach().cpu().numpy().astype(np.int32)


def sat_int8(x: np.ndarray | int) -> np.ndarray:
    return np.clip(x, -128, 127).astype(np.int32)


def choose_shift(x: np.ndarray, target_abs: int = 96) -> int:
    max_abs = int(np.max(np.abs(x))) if x.size else 0
    if max_abs <= target_abs:
        return 0
    return int(math.ceil(math.log2(max_abs / float(target_abs))))


def round_shift(x: np.ndarray, shift: int) -> np.ndarray:
    x64 = x.astype(np.int64)
    if shift <= 0:
        return x64.astype(np.int32)
    add = 1 << (shift - 1)
    pos = x64 >= 0
    out = np.empty_like(x64)
    out[pos] = (x64[pos] + add) >> shift
    out[~pos] = -(((-x64[~pos]) + add) >> shift)
    return out.astype(np.int32)


def trunc_div(x: np.ndarray, denom: int) -> np.ndarray:
    out = np.empty_like(x, dtype=np.int32)
    pos = x >= 0
    out[pos] = x[pos] // denom
    out[~pos] = -((-x[~pos]) // denom)
    return out


def mean_norm_int8(x: np.ndarray) -> np.ndarray:
    sums = x.sum(axis=1, dtype=np.int32).reshape(x.shape[0], 1)
    mean = trunc_div(sums, x.shape[1])
    return sat_int8(x.astype(np.int32) - mean)


def linear_int8(
    x: np.ndarray,
    w_in_out: np.ndarray,
    shift: int | None = None,
    return_acc: bool = False,
) -> tuple[np.ndarray, np.ndarray | None, int]:
    acc = x.astype(np.int32) @ w_in_out.astype(np.int32)
    used_shift = choose_shift(acc) if shift is None else shift
    out = sat_int8(round_shift(acc, used_shift))
    return out, acc.astype(np.int32) if return_acc else None, used_shift


def causal_argmax_attention(q: np.ndarray, k: np.ndarray, v: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    attn = np.zeros((SEQ_LEN, D_MODEL), dtype=np.int32)
    choices = np.zeros((N_HEAD, SEQ_LEN), dtype=np.int32)
    mask = np.triu(np.ones((SEQ_LEN, SEQ_LEN), dtype=bool), k=1)
    for head in range(N_HEAD):
        sl = slice(head * HEAD_DIM, (head + 1) * HEAD_DIM)
        scores = q[:, sl].astype(np.int32) @ k[:, sl].astype(np.int32).T
        scores = scores.astype(np.int32)
        scores[mask] = -(1 << 30)
        choice = np.argmax(scores, axis=1).astype(np.int32)
        choices[head, :] = choice
        attn[:, sl] = v[choice, sl]
    return attn, choices


def write_hex(path: Path, array: np.ndarray, width: int) -> None:
    mask = (1 << width) - 1
    digits = max(1, (width + 3) // 4)
    flat = array.reshape(-1)
    with path.open("w", encoding="ascii") as f:
        for value in flat:
            f.write(f"{int(value) & mask:0{digits}x}\n")


def write_bin(path: Path, array: np.ndarray) -> None:
    path.write_bytes(array.astype(np.int8).reshape(-1).tobytes())


def sha256_file(path: Path) -> str:
    import hashlib

    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_tokens(dataset: str, token_offset: int) -> tuple[np.ndarray, np.ndarray]:
    val = np.memmap(NANOGPT_ROOT / "data" / dataset / "val.bin", dtype=np.uint16, mode="r")
    tokens = np.asarray(val[token_offset : token_offset + SEQ_LEN], dtype=np.int64)
    targets = np.asarray(val[token_offset + 1 : token_offset + 1 + SEQ_LEN], dtype=np.int64)
    if tokens.size != SEQ_LEN or targets.size != SEQ_LEN:
        raise ValueError("not enough validation tokens for full block")
    return tokens, targets


def softmax_cross_entropy(logits: np.ndarray, targets: np.ndarray) -> tuple[float, float]:
    logits64 = logits.astype(np.float64)
    logits64 = logits64 - logits64.max(axis=1, keepdims=True)
    logsumexp = np.log(np.exp(logits64).sum(axis=1))
    nll = -logits64[np.arange(logits64.shape[0]), targets] + logsumexp
    loss = float(nll.mean())
    return loss, float(np.exp(loss))


def export_full(args: argparse.Namespace) -> dict[str, Any]:
    modules = load_int8_modules(args.int8_state)
    tokens, targets = load_tokens(args.dataset, args.token_offset)

    out_dir = args.out_dir
    layers_dir = out_dir / "layers"
    weights_dir = out_dir / "weights"
    out_dir.mkdir(parents=True, exist_ok=True)
    layers_dir.mkdir(parents=True, exist_ok=True)
    weights_dir.mkdir(parents=True, exist_ok=True)

    wte = qweight(modules, "transformer.wte")
    wpe = qweight(modules, "transformer.wpe")
    x = sat_int8(wte[tokens, :D_MODEL] + wpe[np.arange(SEQ_LEN), :D_MODEL])
    input_full = x.copy()
    write_hex(out_dir / "input.mem", input_full, 8)
    write_bin(out_dir / "input.bin", input_full)

    layer_summaries: list[dict[str, Any]] = []
    scale_words: list[int] = []
    weight_entries: dict[str, dict[str, Any]] = {}

    for layer in range(N_LAYER):
        prefix = f"transformer.h.{layer}"
        layer_dir = layers_dir / f"layer_{layer:02d}"
        layer_dir.mkdir(parents=True, exist_ok=True)

        c_attn = qweight(modules, f"{prefix}.attn.c_attn")
        c_proj = qweight(modules, f"{prefix}.attn.c_proj")
        c_fc = qweight(modules, f"{prefix}.mlp.c_fc")
        c_mlp_proj = qweight(modules, f"{prefix}.mlp.c_proj")

        wq = c_attn[0:D_MODEL, 0:D_MODEL].T.copy()
        wk = c_attn[D_MODEL : 2 * D_MODEL, 0:D_MODEL].T.copy()
        wv = c_attn[2 * D_MODEL : 3 * D_MODEL, 0:D_MODEL].T.copy()
        wo = c_proj[0:D_MODEL, 0:D_MODEL].T.copy()
        w1 = c_fc[0:MLP_DIM, 0:D_MODEL].T.copy()
        w2 = c_mlp_proj[0:D_MODEL, 0:MLP_DIM].T.copy()
        for name, arr in [("wq", wq), ("wk", wk), ("wv", wv), ("wo", wo), ("w1", w1), ("w2", w2)]:
            rel = f"layer_{layer:02d}_{name}.mem"
            write_hex(weights_dir / rel, arr, 8)
            weight_entries[f"layer_{layer:02d}.{name}"] = {
                "file": f"weights/{rel}",
                "shape": list(arr.shape),
                "bytes": int(arr.size),
            }

        ln1 = mean_norm_int8(x)
        q, _, q_shift = linear_int8(ln1, wq)
        k, _, k_shift = linear_int8(ln1, wk)
        v, _, v_shift = linear_int8(ln1, wv)
        attn, choices = causal_argmax_attention(q, k, v)
        attn_proj, _, attn_proj_shift = linear_int8(attn, wo)
        res1 = sat_int8(x + attn_proj)
        ln2 = mean_norm_int8(res1)
        ffn_mid, _, ffn_mid_shift = linear_int8(ln2, w1)
        # Matches the existing tile kernel semantics. The current RTL tile path
        # does not apply a GELU nonlinearity between w1 and w2.
        ffn, _, ffn_shift = linear_int8(ffn_mid, w2)
        final = sat_int8(res1 + ffn)

        stage_map = {
            "input": x,
            "ln1": ln1,
            "q": q,
            "k": k,
            "v": v,
            "attn": attn,
            "res1": res1,
            "ln2": ln2,
            "ffn": ffn,
            "final": final,
        }
        for stage, arr in stage_map.items():
            write_hex(layer_dir / f"{stage}.mem", arr, 8)
            write_bin(layer_dir / f"{stage}.bin", arr)
        write_hex(layer_dir / "choices.mem", choices, 16)

        shifts = {
            "q": q_shift,
            "k": k_shift,
            "v": v_shift,
            "attn_proj": attn_proj_shift,
            "ffn_mid": ffn_mid_shift,
            "ffn": ffn_shift,
        }
        for key in ["q", "k", "v", "attn_proj", "ffn_mid", "ffn"]:
            scale_words.append(shifts[key] & 0xFFFFFFFF)

        final_path = layer_dir / "final.bin"
        layer_summaries.append(
            {
                "layer": layer,
                "stage_shapes": {stage: list(arr.shape) for stage, arr in stage_map.items()},
                "shifts": shifts,
                "final_sha256": sha256_file(final_path),
                "first16_final": [int(vv) & 0xFF for vv in final.reshape(-1)[:16]],
            }
        )
        x = final

    ln_f = mean_norm_int8(x)
    lm_head = qweight(modules, "lm_head")[0:VOCAB_SIZE, 0:D_MODEL].T.copy()
    logits_i32 = ln_f.astype(np.int32) @ lm_head.astype(np.int32)
    lm_shift = choose_shift(logits_i32, target_abs=24)
    logits_eval = round_shift(logits_i32, lm_shift)
    pred_tokens = np.argmax(logits_i32, axis=1).astype(np.int32)
    loss, ppl = softmax_cross_entropy(logits_eval, targets)

    write_hex(out_dir / "final.mem", x, 8)
    write_bin(out_dir / "final.bin", x)
    write_hex(out_dir / "ln_f.mem", ln_f, 8)
    write_bin(out_dir / "ln_f.bin", ln_f)
    write_hex(out_dir / "lm_head.mem", lm_head, 8)
    write_hex(out_dir / "logits_i32.mem", logits_i32, 32)
    write_hex(out_dir / "logits_eval_i8.mem", sat_int8(logits_eval), 8)
    write_hex(out_dir / "argmax_tokens.mem", pred_tokens, 16)
    write_hex(out_dir / "target_tokens.mem", targets.astype(np.int32), 16)
    np.asarray(scale_words, dtype="<u4").tofile(out_dir / "scales.bin")

    metadata = {
        "checkpoint": str(args.ckpt),
        "int8_state": str(args.int8_state),
        "dataset": args.dataset,
        "token_offset": args.token_offset,
        "mode": "full_int8_hardware_golden",
        "seq_len": SEQ_LEN,
        "d_model": D_MODEL,
        "n_layer": N_LAYER,
        "n_head": N_HEAD,
        "head_dim": HEAD_DIM,
        "mlp_dim": MLP_DIM,
        "vocab_size": VOCAB_SIZE,
        "stages": STAGES,
        "layernorm": "integer row mean normalization over 384 dims, truncating signed division toward zero",
        "attention": "causal argmax attention, matching the existing FPGA tile kernel family",
        "ffn_activation": "identity_between_w1_w2_to_match_current_tile_kernel",
        "input_shape": [SEQ_LEN, D_MODEL],
        "activation_rows_per_stage": SEQ_LEN * D_MODEL,
        "weight_entries": weight_entries,
        "layer_summaries": layer_summaries,
        "final": {
            "sha256": sha256_file(out_dir / "final.bin"),
            "first16": [int(vv) & 0xFF for vv in x.reshape(-1)[:16]],
        },
        "ln_f": {"sha256": sha256_file(out_dir / "ln_f.bin")},
        "lm_head": {
            "logits_shape": list(logits_i32.shape),
            "logits_eval_shift": lm_shift,
            "loss": loss,
            "perplexity": ppl,
            "argmax_first32": [int(vv) for vv in pred_tokens[:32]],
            "target_first32": [int(vv) for vv in targets[:32]],
        },
    }
    (out_dir / "full_metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return metadata


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export full 256x384x6 INT8 nanoGPT golden for FPGA scheduling.")
    parser.add_argument("--ckpt", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt")
    parser.add_argument(
        "--int8-state",
        type=Path,
        default=NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference" / "int8_state_dict.pt",
    )
    parser.add_argument("--dataset", default="shakespeare_char")
    parser.add_argument("--token-offset", type=int, default=0)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_full_s256_d384_l6",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    metadata = export_full(args)
    print(json.dumps({
        "mode": metadata["mode"],
        "out_dir": str(args.out_dir),
        "seq_len": metadata["seq_len"],
        "d_model": metadata["d_model"],
        "n_layer": metadata["n_layer"],
        "final_sha256": metadata["final"]["sha256"],
        "loss": metadata["lm_head"]["loss"],
        "perplexity": metadata["lm_head"]["perplexity"],
    }, indent=2))


if __name__ == "__main__":
    main()
