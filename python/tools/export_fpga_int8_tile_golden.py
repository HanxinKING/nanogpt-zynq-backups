from __future__ import annotations

import argparse
import json
import math
import shutil
import sys
from pathlib import Path
from typing import Any

import numpy as np
import torch


NANOGPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = NANOGPT_ROOT.parent
if str(NANOGPT_ROOT) not in sys.path:
    sys.path.insert(0, str(NANOGPT_ROOT))


SEQ_LEN = 32
D_MODEL = 256
N_HEAD = 4
HEAD_DIM = 64
HIDDEN_TILE = 256
INPUT_WORDS = SEQ_LEN * D_MODEL
WEIGHT_WORDS = D_MODEL * D_MODEL


def load_torch(path: Path) -> Any:
    try:
        return torch.load(path, map_location="cpu", weights_only=False)
    except TypeError:
        return torch.load(path, map_location="cpu")


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


def mean_norm_int8(x: np.ndarray) -> np.ndarray:
    mean = (x.sum(axis=1, dtype=np.int32) >> 8).reshape(SEQ_LEN, 1)
    return sat_int8(x.astype(np.int32) - mean)


def write_hex(path: Path, array: np.ndarray, width: int) -> None:
    mask = (1 << width) - 1
    digits = max(1, (width + 3) // 4)
    flat = array.reshape(-1)
    with path.open("w", encoding="ascii") as f:
        for value in flat:
            f.write(f"{int(value) & mask:0{digits}x}\n")


def assert_shape(name: str, array: np.ndarray, shape: tuple[int, ...]) -> None:
    if array.shape != shape:
        raise ValueError(f"{name} shape {array.shape} != {shape}")


def linear_tile(
    x: np.ndarray,
    w_in_out: np.ndarray,
    shift: int | None = None,
) -> tuple[np.ndarray, np.ndarray, int]:
    acc = x.astype(np.int32) @ w_in_out.astype(np.int32)
    used_shift = choose_shift(acc) if shift is None else shift
    out = sat_int8(round_shift(acc, used_shift))
    return out, acc.astype(np.int32), used_shift


def causal_argmax_attention(q: np.ndarray, k: np.ndarray, v: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    scores = np.full((N_HEAD, SEQ_LEN, SEQ_LEN), -(1 << 30), dtype=np.int32)
    choices = np.zeros((N_HEAD, SEQ_LEN), dtype=np.int32)
    attn = np.zeros((SEQ_LEN, D_MODEL), dtype=np.int32)
    for head in range(N_HEAD):
        sl = slice(head * HEAD_DIM, (head + 1) * HEAD_DIM)
        for row in range(SEQ_LEN):
            best_score = -(1 << 30)
            best_col = 0
            for col in range(row + 1):
                score = int(np.dot(q[row, sl].astype(np.int32), k[col, sl].astype(np.int32)))
                scores[head, row, col] = score
                if score > best_score:
                    best_score = score
                    best_col = col
            choices[head, row] = best_col
            attn[row, sl] = v[best_col, sl]
    return attn.astype(np.int32), scores, choices


def load_int8_modules(path: Path) -> dict[str, dict[str, Any]]:
    state = load_torch(path)
    return state["modules"]


def qweight(modules: dict[str, dict[str, Any]], name: str) -> np.ndarray:
    return modules[name]["qweight"].detach().cpu().numpy().astype(np.int32)


def load_input_tile(args: argparse.Namespace, tokens: np.ndarray) -> np.ndarray:
    if args.input_mem is not None:
        flat = np.asarray(
            [int(line.strip(), 16) if line.strip() else 0 for line in args.input_mem.read_text(encoding="ascii").splitlines()],
            dtype=np.int32,
        )
        if flat.size != INPUT_WORDS:
            raise ValueError(f"input_mem has {flat.size} rows, expected {INPUT_WORDS}")
        flat = np.where(flat >= 128, flat - 256, flat).astype(np.int32)
        return sat_int8(flat.reshape(SEQ_LEN, D_MODEL))

    if args.layer_index != 0:
        raise ValueError("layer_index > 0 requires --input-mem")

    return tokens


def export_tile(args: argparse.Namespace) -> dict[str, Any]:
    modules = load_int8_modules(args.int8_state)
    val = np.memmap(NANOGPT_ROOT / "data" / args.dataset / "val.bin", dtype=np.uint16, mode="r")
    tokens = np.asarray(val[args.token_offset : args.token_offset + SEQ_LEN], dtype=np.int64)
    if tokens.size != SEQ_LEN:
        raise ValueError("not enough tokens for tile")

    layer_prefix = f"transformer.h.{args.layer_index}"
    wte = qweight(modules, "transformer.wte")
    wpe = qweight(modules, "transformer.wpe")
    c_attn = qweight(modules, f"{layer_prefix}.attn.c_attn")
    c_proj = qweight(modules, f"{layer_prefix}.attn.c_proj")
    c_fc = qweight(modules, f"{layer_prefix}.mlp.c_fc")
    c_mlp_proj = qweight(modules, f"{layer_prefix}.mlp.c_proj")

    # Current FPGA tile is 32x256. Embedding uses real INT8 token and position rows,
    # cropped to dims [0, 255], then saturated to the stream activation type.
    if args.input_mem is None:
        x = sat_int8(wte[tokens, :D_MODEL] + wpe[np.arange(SEQ_LEN), :D_MODEL])
    else:
        x = load_input_tile(args, tokens)
    ln1 = mean_norm_int8(x)

    # PyTorch Linear weight layout is [out, in]; RTL tile layout is [in, out].
    wq = c_attn[0:D_MODEL, 0:D_MODEL].T.copy()
    wk = c_attn[384 : 384 + D_MODEL, 0:D_MODEL].T.copy()
    wv = c_attn[768 : 768 + D_MODEL, 0:D_MODEL].T.copy()
    q, q_acc, q_shift = linear_tile(ln1, wq)
    k, k_acc, k_shift = linear_tile(ln1, wk)
    v, v_acc, v_shift = linear_tile(ln1, wv)

    attn, scores, choices = causal_argmax_attention(q, k, v)
    # Use c_proj first 256x256 tile as the attention output projection. This keeps
    # the stage tied to real nanoGPT parameters while matching the current RTL size.
    wo = c_proj[0:D_MODEL, 0:D_MODEL].T.copy()
    attn_proj, attn_proj_acc, attn_proj_shift = linear_tile(attn, wo)
    res1 = sat_int8(x + attn_proj)

    ln2 = mean_norm_int8(res1)
    w1 = c_fc[0:HIDDEN_TILE, 0:D_MODEL].T.copy()
    w2 = c_mlp_proj[0:D_MODEL, 0:HIDDEN_TILE].T.copy()
    ffn_mid, ffn_mid_acc, ffn_mid_shift = linear_tile(ln2, w1)
    ffn, ffn_acc, ffn_shift = linear_tile(ffn_mid, w2)
    final = sat_int8(res1 + ffn)

    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    write_hex(out_dir / "input.mem", x, 8)
    write_hex(out_dir / "ln1.mem", ln1, 8)
    write_hex(out_dir / "q.mem", q, 8)
    write_hex(out_dir / "q_i8.mem", q, 8)
    write_hex(out_dir / "q_acc.mem", q_acc, 32)
    write_hex(out_dir / "k.mem", k, 8)
    write_hex(out_dir / "k_i8.mem", k, 8)
    write_hex(out_dir / "k_acc.mem", k_acc, 32)
    write_hex(out_dir / "v.mem", v, 8)
    write_hex(out_dir / "v_i8.mem", v, 8)
    write_hex(out_dir / "v_acc.mem", v_acc, 32)
    write_hex(out_dir / "scores.mem", scores, 32)
    write_hex(out_dir / "choices.mem", choices, 8)
    write_hex(out_dir / "attn.mem", attn, 8)
    write_hex(out_dir / "attn_proj.mem", attn_proj, 8)
    write_hex(out_dir / "res1.mem", res1, 8)
    write_hex(out_dir / "ln2.mem", ln2, 8)
    write_hex(out_dir / "ffn_mid.mem", ffn_mid_acc, 32)
    write_hex(out_dir / "ffn_mid_i8.mem", ffn_mid, 8)
    write_hex(out_dir / "ffn.mem", ffn, 8)
    write_hex(out_dir / "ffn_out.mem", ffn_acc, 32)
    write_hex(out_dir / "final.mem", final, 8)
    write_hex(out_dir / "wq.mem", wq, 8)
    write_hex(out_dir / "wk.mem", wk, 8)
    write_hex(out_dir / "wv.mem", wv, 8)
    write_hex(out_dir / "wo.mem", wo, 8)
    write_hex(out_dir / "w1.mem", w1, 8)
    write_hex(out_dir / "w2.mem", w2, 8)

    np.savez_compressed(
        out_dir / "software_true_snapshot.npz",
        tokens=tokens,
        input=x,
        ln1=ln1,
        q_acc=q_acc,
        k_acc=k_acc,
        v_acc=v_acc,
        q=q,
        k=k,
        v=v,
        scores=scores,
        choices=choices,
        attn=attn,
        attn_proj_acc=attn_proj_acc,
        attn_proj=attn_proj,
        res1=res1,
        ln2=ln2,
        ffn_mid_acc=ffn_mid_acc,
        ffn_mid=ffn_mid,
        ffn_acc=ffn_acc,
        ffn=ffn,
        final=final,
    )

    metadata = {
        "checkpoint": str(args.ckpt),
        "int8_state": str(args.int8_state),
        "dataset": args.dataset,
        "layer": args.layer_index,
        "token_offset": args.token_offset,
        "seq_len": SEQ_LEN,
        "d_model_tile": D_MODEL,
        "n_head_tile": N_HEAD,
        "head_dim": HEAD_DIM,
        "hidden_tile": HIDDEN_TILE,
        "source_model": {
            "n_layer": 6,
            "n_head": 6,
            "n_embd": 384,
            "block_size": 256,
        },
        "dim_range": [0, D_MODEL - 1],
        "head_range": [0, N_HEAD - 1],
        "algorithm": "hardware_tile_golden_int8_argmax_attention",
        "input_source": "token_embedding" if args.input_mem is None else str(args.input_mem),
        "shifts": {
            "q": q_shift,
            "k": k_shift,
            "v": v_shift,
            "attn_proj": attn_proj_shift,
            "ffn_mid": ffn_mid_shift,
            "ffn": ffn_shift,
        },
        "files": {
            "activation_rows": INPUT_WORDS,
            "weight_rows": WEIGHT_WORDS,
            "active_sync_required": bool(args.sync_active),
        },
    }
    (out_dir / "tile_metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    for name, array, shape in [
        ("input", x, (SEQ_LEN, D_MODEL)),
        ("ln1", ln1, (SEQ_LEN, D_MODEL)),
        ("q", q, (SEQ_LEN, D_MODEL)),
        ("k", k, (SEQ_LEN, D_MODEL)),
        ("v", v, (SEQ_LEN, D_MODEL)),
        ("attn", attn, (SEQ_LEN, D_MODEL)),
        ("res1", res1, (SEQ_LEN, D_MODEL)),
        ("ln2", ln2, (SEQ_LEN, D_MODEL)),
        ("ffn", ffn, (SEQ_LEN, D_MODEL)),
        ("final", final, (SEQ_LEN, D_MODEL)),
        ("wq", wq, (D_MODEL, D_MODEL)),
        ("wk", wk, (D_MODEL, D_MODEL)),
        ("wv", wv, (D_MODEL, D_MODEL)),
        ("w1", w1, (D_MODEL, HIDDEN_TILE)),
        ("w2", w2, (HIDDEN_TILE, D_MODEL)),
    ]:
        assert_shape(name, array, shape)

    if args.sync_active:
        active = REPO_ROOT / "fpga" / "nano_gpt" / "generated"
        for file_name in [
            "input.mem",
            "ln1.mem",
            "q.mem",
            "k.mem",
            "v.mem",
            "scores.mem",
            "choices.mem",
            "attn.mem",
            "res1.mem",
            "ln2.mem",
            "ffn_mid.mem",
            "ffn_out.mem",
            "final.mem",
            "wq.mem",
            "wk.mem",
            "wv.mem",
            "w1.mem",
            "w2.mem",
        ]:
            shutil.copy2(out_dir / file_name, active / file_name)
        shutil.copy2(out_dir / "ffn.mem", active / "ffn.mem")
        shutil.copy2(out_dir / "tile_metadata.json", active / "tile_metadata.json")

    return metadata


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export real INT8 nanoGPT tile golden for FPGA.")
    parser.add_argument("--ckpt", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt")
    parser.add_argument(
        "--int8-state",
        type=Path,
        default=NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference" / "int8_state_dict.pt",
    )
    parser.add_argument("--dataset", default="shakespeare_char")
    parser.add_argument("--token-offset", type=int, default=0)
    parser.add_argument("--layer-index", type=int, default=0)
    parser.add_argument("--input-mem", type=Path, default=None)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_tile_l0_s32_d256",
    )
    parser.add_argument("--sync-active", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    metadata = export_tile(args)
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
