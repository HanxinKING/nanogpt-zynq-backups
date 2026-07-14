from __future__ import annotations

import json
from pathlib import Path

import numpy as np


SEQ_LEN = 32
D_MODEL = 256
N_HEAD = 4
HEAD_DIM = D_MODEL // N_HEAD
ATTN_SHIFT = 0
FFN_SHIFT = 2

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "fpga" / "nano_gpt" / "generated"


def sat_int8(x: np.ndarray) -> np.ndarray:
    return np.clip(x, -128, 127).astype(np.int32)


def mean_norm_int(x: np.ndarray) -> np.ndarray:
    mean = (x.sum(axis=1, dtype=np.int32) >> 8).reshape(SEQ_LEN, 1)
    return sat_int8(x - mean)


def mean_norm_float(x: np.ndarray) -> np.ndarray:
    return x - x.mean(axis=1, keepdims=True)


def make_sparse_weight(kind: str) -> np.ndarray:
    weight = np.zeros((D_MODEL, D_MODEL), dtype=np.int32)
    for out_idx in range(D_MODEL):
        weight[out_idx, out_idx] = 1
        if kind == "q":
            weight[(out_idx - 1) % D_MODEL, out_idx] = 1
        elif kind == "k":
            weight[(out_idx + 1) % D_MODEL, out_idx] = 1
        elif kind == "v":
            weight[(out_idx + HEAD_DIM) % D_MODEL, out_idx] = 1
        elif kind == "w1":
            weight[(out_idx + 3) % D_MODEL, out_idx] = 1
        elif kind == "w2":
            weight[(out_idx + 5) % D_MODEL, out_idx] = 1
        else:
            raise ValueError(f"unsupported kind: {kind}")
    return weight


def build_input() -> np.ndarray:
    x = np.zeros((SEQ_LEN, D_MODEL), dtype=np.int32)
    for row in range(SEQ_LEN):
        for col in range(D_MODEL):
            x[row, col] = ((row * 11 + col * 7) % 17) - 8
        x[row, row] += 24
    return sat_int8(x)


def exact_float_reference(
    x: np.ndarray,
    wq: np.ndarray,
    wk: np.ndarray,
    wv: np.ndarray,
    w1: np.ndarray,
    w2: np.ndarray,
) -> np.ndarray:
    x_f = x.astype(np.float64)
    ln1 = mean_norm_float(x_f)
    q = ln1 @ wq.astype(np.float64)
    k = ln1 @ wk.astype(np.float64)
    v = ln1 @ wv.astype(np.float64)

    attn = np.zeros((SEQ_LEN, D_MODEL), dtype=np.float64)
    for head in range(N_HEAD):
        sl = slice(head * HEAD_DIM, (head + 1) * HEAD_DIM)
        scores = q[:, sl] @ k[:, sl].T
        scores[np.triu_indices(SEQ_LEN, 1)] = -1e9
        scores = scores - scores.max(axis=1, keepdims=True)
        probs = np.exp(scores)
        probs = probs / probs.sum(axis=1, keepdims=True)
        attn[:, sl] = probs @ v[:, sl]

    res1 = x_f + attn
    ln2 = mean_norm_float(res1)
    ffn = (ln2 @ w1.astype(np.float64)) @ w2.astype(np.float64)
    return res1 + (ffn / float(1 << FFN_SHIFT))


def fixed_reference(
    x: np.ndarray,
    wq: np.ndarray,
    wk: np.ndarray,
    wv: np.ndarray,
    w1: np.ndarray,
    w2: np.ndarray,
):
    ln1 = mean_norm_int(x)
    q = ln1 @ wq
    k = ln1 @ wk
    v = ln1 @ wv

    scores = np.zeros((N_HEAD, SEQ_LEN, SEQ_LEN), dtype=np.int32)
    choices = np.zeros((N_HEAD, SEQ_LEN), dtype=np.int32)
    attn = np.zeros((SEQ_LEN, D_MODEL), dtype=np.int32)

    for head in range(N_HEAD):
        sl = slice(head * HEAD_DIM, (head + 1) * HEAD_DIM)
        for row in range(SEQ_LEN):
            best_score = None
            best_idx = 0
            for col in range(SEQ_LEN):
                if col > row:
                    score = -(1 << 30)
                else:
                    score = int((q[row, sl] * k[col, sl]).sum())
                scores[head, row, col] = score
                if best_score is None or score > best_score:
                    best_score = score
                    best_idx = col
            choices[head, row] = best_idx
            attn[row, sl] = v[best_idx, sl]

    res1 = sat_int8(x + (attn >> ATTN_SHIFT))
    ln2 = mean_norm_int(res1)
    ffn_mid = ln2 @ w1
    ffn_out = ffn_mid @ w2
    final_out = sat_int8(res1 + (ffn_out >> FFN_SHIFT))

    return {
        "ln1": ln1,
        "q": q.astype(np.int32),
        "k": k.astype(np.int32),
        "v": v.astype(np.int32),
        "scores": scores,
        "choices": choices,
        "attn": attn.astype(np.int32),
        "res1": res1,
        "ln2": ln2,
        "ffn_mid": ffn_mid.astype(np.int32),
        "ffn_out": ffn_out.astype(np.int32),
        "final": final_out,
    }


def write_hex(path: Path, array: np.ndarray, width: int) -> None:
    mask = (1 << width) - 1
    flat = array.reshape(-1)
    digits = max(1, (width + 3) // 4)
    with path.open("w", encoding="ascii") as f:
        for value in flat:
            f.write(f"{int(value) & mask:0{digits}x}\n")


def build_stream_words(x, wq, wk, wv, w1, w2) -> np.ndarray:
    payload = np.concatenate(
        [
            x.reshape(-1),
            wq.reshape(-1),
            wk.reshape(-1),
            wv.reshape(-1),
            w1.reshape(-1),
            w2.reshape(-1),
        ]
    ).astype(np.int32)

    words = []
    for idx in range(0, payload.size, 4):
        chunk = payload[idx : idx + 4]
        word = 0
        for byte_idx, value in enumerate(chunk):
            word |= (int(value) & 0xFF) << (8 * byte_idx)
        words.append(word)
    return np.array(words, dtype=np.uint32)


def build_stream_bytes(x, wq, wk, wv, w1, w2) -> np.ndarray:
    return np.concatenate(
        [
            x.reshape(-1),
            wq.reshape(-1),
            wk.reshape(-1),
            wv.reshape(-1),
            w1.reshape(-1),
            w2.reshape(-1),
        ]
    ).astype(np.int32)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    x = build_input()
    wq = make_sparse_weight("q")
    wk = make_sparse_weight("k")
    wv = make_sparse_weight("v")
    w1 = make_sparse_weight("w1")
    w2 = make_sparse_weight("w2")

    float_ref = exact_float_reference(x, wq, wk, wv, w1, w2)
    fixed = fixed_reference(x, wq, wk, wv, w1, w2)

    fixed_float = fixed["final"].astype(np.float64)
    diff = np.abs(fixed_float - float_ref)
    rel = np.mean(diff / np.maximum(np.abs(float_ref), 1.0))
    cos = float(
        np.dot(fixed_float.reshape(-1), float_ref.reshape(-1))
        / (np.linalg.norm(fixed_float.reshape(-1)) * np.linalg.norm(float_ref.reshape(-1)))
    )
    max_abs = float(diff.max())

    write_hex(OUT_DIR / "input.mem", x, 8)
    write_hex(OUT_DIR / "wq.mem", wq, 8)
    write_hex(OUT_DIR / "wk.mem", wk, 8)
    write_hex(OUT_DIR / "wv.mem", wv, 8)
    write_hex(OUT_DIR / "w1.mem", w1, 8)
    write_hex(OUT_DIR / "w2.mem", w2, 8)
    write_hex(OUT_DIR / "ln1.mem", fixed["ln1"], 8)
    write_hex(OUT_DIR / "q.mem", fixed["q"], 16)
    write_hex(OUT_DIR / "k.mem", fixed["k"], 16)
    write_hex(OUT_DIR / "v.mem", fixed["v"], 16)
    write_hex(OUT_DIR / "scores.mem", fixed["scores"], 32)
    write_hex(OUT_DIR / "choices.mem", fixed["choices"], 8)
    write_hex(OUT_DIR / "attn.mem", fixed["attn"], 16)
    write_hex(OUT_DIR / "res1.mem", fixed["res1"], 8)
    write_hex(OUT_DIR / "ln2.mem", fixed["ln2"], 8)
    write_hex(OUT_DIR / "ffn_mid.mem", fixed["ffn_mid"], 32)
    write_hex(OUT_DIR / "ffn_out.mem", fixed["ffn_out"], 32)
    write_hex(OUT_DIR / "final.mem", fixed["final"], 8)
    write_hex(OUT_DIR / "float_ref_quantized.mem", sat_int8(np.round(float_ref)), 8)
    write_hex(OUT_DIR / "stream_words.mem", build_stream_words(x, wq, wk, wv, w1, w2), 32)
    write_hex(OUT_DIR / "stream_bytes.mem", build_stream_bytes(x, wq, wk, wv, w1, w2), 8)

    report = {
        "seq_len": SEQ_LEN,
        "d_model": D_MODEL,
        "n_head": N_HEAD,
        "head_dim": HEAD_DIM,
        "attn_shift": ATTN_SHIFT,
        "ffn_shift": FFN_SHIFT,
        "average_relative_error": rel,
        "cosine_similarity": cos,
        "max_absolute_error": max_abs,
        "pass": bool(rel <= 0.10 and cos >= 0.98),
    }
    (OUT_DIR / "metrics.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
