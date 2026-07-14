from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import numpy as np


NANOGPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = NANOGPT_ROOT.parent

SEQ_LEN = 256
D_MODEL = 384
N_LAYER = 6
N_HEAD = 6
VOCAB_SIZE = 65
MLP_DIM = 1536
LAYER_WEIGHT_BYTES = 0x1B0000
WQ_OFF = 0x000000
WK_OFF = 0x024000
WV_OFF = 0x048000
WO_OFF = 0x06C000
W1_OFF = 0x090000
W2_OFF = 0x120000
LM_HEAD_OFF = 0x0A20000


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def read_i8_bin(path: Path, shape: tuple[int, ...]) -> np.ndarray:
    data = np.frombuffer(path.read_bytes(), dtype=np.int8).copy()
    return data.reshape(shape)


def read_weight(blob: bytes, base: int, rows: int, cols: int) -> np.ndarray:
    raw = np.frombuffer(blob, dtype=np.int8, count=rows * cols, offset=base).copy()
    return raw.reshape(rows, cols)


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


def round_shift_signed(value: np.ndarray, shift: int) -> np.ndarray:
    value64 = value.astype(np.int64)
    if shift <= 0:
        return value64 << (-shift)
    add = 1 << (shift - 1)
    pos = value64 >= 0
    out = np.empty_like(value64)
    out[pos] = (value64[pos] + add) >> shift
    out[~pos] = -(((-value64[~pos]) + add) >> shift)
    return out


def clamp_i8(value: np.ndarray) -> np.ndarray:
    return np.clip(value, -128, 127).astype(np.int8)


def mean_only_ln(x: np.ndarray) -> np.ndarray:
    sums = x.astype(np.int32).sum(axis=1, keepdims=True)
    # Verilog division truncates toward zero.
    means = np.trunc(sums.astype(np.float64) / D_MODEL).astype(np.int32)
    return clamp_i8(x.astype(np.int32) - means)


def q6_piecewise_ln(x: np.ndarray) -> np.ndarray:
    xi = x.astype(np.int32)
    sums = xi.sum(axis=1, keepdims=True)
    means = np.trunc(sums.astype(np.float64) / D_MODEL).astype(np.int32)
    sq_means = np.trunc((xi * xi).sum(axis=1, keepdims=True).astype(np.float64) / D_MODEL).astype(np.int32)
    var = np.maximum(sq_means - means * means + 1, 1)
    inv = np.zeros_like(var, dtype=np.int32)
    thresholds = [
        (1, 4096), (2, 2896), (4, 2048), (8, 1448),
        (16, 1024), (32, 724), (64, 512), (128, 362),
        (256, 256), (512, 181), (1024, 128), (2048, 91),
        (4096, 64), (8192, 45),
    ]
    prev = np.zeros_like(var, dtype=bool)
    for limit, value in thresholds:
        mask = (var <= limit) & ~prev
        inv[mask] = value
        prev |= mask
    inv[~prev] = 32
    centered = xi - means
    scaled = centered.astype(np.int64) * inv.astype(np.int64) * 32
    out = np.where(scaled >= 0, (scaled + 2048) >> 12, -(((-scaled) + 2048) >> 12))
    return np.clip(out, -32, 31).astype(np.int8)


def matmul_i8(x: np.ndarray, w: np.ndarray, shift: int) -> np.ndarray:
    acc = x.astype(np.int32) @ w.astype(np.int32)
    return clamp_i8(round_shift_signed(acc, shift))


def argmax_attention(q: np.ndarray, k: np.ndarray, v: np.ndarray) -> np.ndarray:
    out = np.zeros_like(v, dtype=np.int8)
    qi = q.astype(np.int32)
    ki = k.astype(np.int32)
    head_dim = D_MODEL // N_HEAD
    for row in range(SEQ_LEN):
        for head in range(N_HEAD):
            start = head * head_dim
            end = start + head_dim
            scores = qi[row : row + 1, start:end] @ ki[: row + 1, start:end].T
            best = int(np.argmax(scores.reshape(-1)))
            out[row, start:end] = v[best, start:end]
    return out


def qsoftmax_attention(q: np.ndarray, k: np.ndarray, v: np.ndarray, bits: int, score_shift: int) -> np.ndarray:
    """Hardware-friendly causal attention: int dot scores -> q-prob -> int weighted V."""
    out = np.zeros_like(v, dtype=np.int8)
    qi = q.astype(np.int32)
    ki = k.astype(np.int32)
    vi = v.astype(np.int32)
    qmax = (1 << bits) - 1
    head_dim = D_MODEL // N_HEAD
    for row in range(SEQ_LEN):
        for head in range(N_HEAD):
            start = head * head_dim
            end = start + head_dim
            scores = (qi[row : row + 1, start:end] @ ki[: row + 1, start:end].T).reshape(-1)
            scores = round_shift_signed(scores, score_shift).astype(np.float64)
            scores -= scores.max()
            probs = np.exp(scores)
            probs /= np.maximum(probs.sum(), 1e-300)
            qprob = np.clip(np.rint(probs * qmax), 0, qmax).astype(np.int32)
            denom = int(max(qprob.sum(), 1))
            weighted = qprob.reshape(1, -1) @ vi[: row + 1, start:end]
            rounded = np.where(
                weighted >= 0,
                (weighted + (denom // 2)) // denom,
                -(((-weighted) + (denom // 2)) // denom),
            )
            out[row, start:end] = clamp_i8(rounded.reshape(-1))
    return out


def gelu_lut_apply(x: np.ndarray, lut: np.ndarray) -> np.ndarray:
    idx = x.astype(np.int16) & 0xFF
    return clamp_i8(lut[idx])


def logits_argmax(hidden: np.ndarray, lm_head: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    logits = hidden.astype(np.int32) @ lm_head.astype(np.int32)
    argmax = np.argmax(logits, axis=1).astype(np.int32)
    return logits.astype(np.int32), argmax


def softmax_cross_entropy(logits: np.ndarray, targets: np.ndarray) -> tuple[float, float]:
    logits64 = logits.astype(np.float64)
    logits64 -= logits64.max(axis=1, keepdims=True)
    exp = np.exp(logits64)
    probs = exp / exp.sum(axis=1, keepdims=True)
    nll = -np.log(np.maximum(probs[np.arange(logits.shape[0]), targets], 1e-300))
    loss = float(nll.mean())
    return loss, float(math.exp(loss))


def ln_inv_std_lut_q12(max_var_q12: int = 32768, scale: float = 1.0) -> np.ndarray:
    xs = np.arange(1, max_var_q12 + 1, dtype=np.float64) / float(1 << 12)
    inv = 1.0 / np.sqrt(xs)
    q = np.clip(np.rint(inv * (1 << 12) * scale), 0, 65535).astype(np.int32)
    return q


def export_stage(root: Path, layer: int, stage: str, data: np.ndarray) -> None:
    out_dir = root / "layers" / f"layer_{layer:02d}"
    write_hex(out_dir / f"{stage}.mem", data, 8)
    write_bin(out_dir / f"{stage}.bin", data, np.int8)


def main() -> None:
    parser = argparse.ArgumentParser(description="Export Python hardware-exact approximation for the current HLS full path.")
    parser.add_argument(
        "--quality-root",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_hw_ppl_pass_s256_d384_l6",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "hardware_exact_hls_full",
    )
    parser.add_argument("--q-shifts", default="13,12,12,12,12,12")
    parser.add_argument("--k-shifts", default="13,13,13,12,12,12")
    parser.add_argument("--v-shifts", default="13,13,12,12,12,12")
    parser.add_argument("--attn-proj-shifts", default="10,10,11,10,10,10")
    parser.add_argument("--ffn-mid-shifts", default="13,13,13,12,12,13")
    parser.add_argument("--ffn-shifts", default="11,11,11,12,11,10")
    parser.add_argument("--attention-mode", choices=["argmax", "qsoftmax"], default="argmax")
    parser.add_argument("--softmax-bits", type=int, default=6)
    parser.add_argument("--score-shift", type=int, default=8)
    parser.add_argument("--threshold-pct", type=float, default=5.0)
    args = parser.parse_args()

    quality_full = args.quality_root / "quality_full"
    ddr_image = args.quality_root / "ddr_image"
    out_dir = args.out_dir
    weights = (ddr_image / "weights.bin").read_bytes()
    input_act = read_i8_bin(ddr_image / "input.bin", (SEQ_LEN, D_MODEL))
    targets_mem = quality_full / "target_tokens.mem"
    if targets_mem.exists():
        targets = np.array([int(line.strip(), 16) for line in targets_mem.read_text(encoding="ascii").splitlines() if line.strip()], dtype=np.int64)
    else:
        targets = np.zeros((SEQ_LEN,), dtype=np.int64)

    gelu_lut_path = args.quality_root / "luts" / "gelu_int8_to_i16.mem"
    gelu_lut = np.array([int(line.strip(), 16) for line in gelu_lut_path.read_text(encoding="ascii").splitlines() if line.strip()], dtype=np.int32)
    gelu_lut = np.where(gelu_lut >= 0x8000, gelu_lut - 0x10000, gelu_lut)
    ln_lut = ln_inv_std_lut_q12()

    hidden = input_act
    def parse_shifts(text: str) -> list[int]:
        values = [int(x.strip()) for x in text.split(",") if x.strip()]
        if len(values) != N_LAYER:
            raise ValueError(f"expected {N_LAYER} shifts, got {values}")
        return values

    q_shifts = parse_shifts(args.q_shifts)
    k_shifts = parse_shifts(args.k_shifts)
    v_shifts = parse_shifts(args.v_shifts)
    attn_proj_shifts = parse_shifts(args.attn_proj_shifts)
    ffn_mid_shifts = parse_shifts(args.ffn_mid_shifts)
    ffn_shifts = parse_shifts(args.ffn_shifts)

    metadata: dict[str, Any] = {
        "kind": "hardware_exact_hls_full",
        "note": "Matches the current deployable integer/HLS scheduler semantics for diagnosis; quality PASS requires ppl <= threshold.",
        "seq_len": SEQ_LEN,
        "d_model": D_MODEL,
        "n_layer": N_LAYER,
        "shifts": {
            "q": q_shifts,
            "k": k_shifts,
            "v": v_shifts,
            "attn_proj": attn_proj_shifts,
            "ffn_mid": ffn_mid_shifts,
            "ffn": ffn_shifts,
        },
        "threshold_pct": args.threshold_pct,
        "attention": {
            "mode": args.attention_mode,
            "softmax_bits": args.softmax_bits,
            "score_shift": args.score_shift,
        },
        "layers": [],
    }
    write_hex(out_dir / "ln_inv_std_q12.mem", ln_lut, 16)
    write_bin(out_dir / "ln_inv_std_q12.bin", ln_lut.astype(np.uint16), np.dtype("<u2"))

    for layer in range(N_LAYER):
        base = layer * LAYER_WEIGHT_BYTES
        wq = read_weight(weights, base + WQ_OFF, D_MODEL, D_MODEL)
        wk = read_weight(weights, base + WK_OFF, D_MODEL, D_MODEL)
        wv = read_weight(weights, base + WV_OFF, D_MODEL, D_MODEL)
        wo = read_weight(weights, base + WO_OFF, D_MODEL, D_MODEL)
        w1 = read_weight(weights, base + W1_OFF, D_MODEL, MLP_DIM)
        w2 = read_weight(weights, base + W2_OFF, MLP_DIM, D_MODEL)

        ln1 = q6_piecewise_ln(hidden)
        q = matmul_i8(ln1, wq, q_shifts[layer])
        k = matmul_i8(ln1, wk, k_shifts[layer])
        v = matmul_i8(ln1, wv, v_shifts[layer])
        if args.attention_mode == "qsoftmax":
            attn = qsoftmax_attention(q, k, v, args.softmax_bits, args.score_shift)
        else:
            attn = argmax_attention(q, k, v)
        attn_proj = matmul_i8(attn, wo, attn_proj_shifts[layer])
        res1 = clamp_i8(hidden.astype(np.int32) + attn_proj.astype(np.int32))
        ln2 = q6_piecewise_ln(res1)
        ffn_mid = matmul_i8(ln2, w1, ffn_mid_shifts[layer])
        ffn_gelu = gelu_lut_apply(ffn_mid, gelu_lut)
        ffn = matmul_i8(ffn_gelu, w2, ffn_shifts[layer])
        final = clamp_i8(res1.astype(np.int32) + ffn.astype(np.int32))

        for stage, data in [
            ("ln1", ln1),
            ("q", q),
            ("k", k),
            ("v", v),
            ("attn", attn),
            ("attn_proj", attn_proj),
            ("res1", res1),
            ("ln2", ln2),
            ("ffn_mid", ffn_mid),
            ("ffn_gelu", ffn_gelu),
            ("ffn", ffn),
            ("final", final),
        ]:
            export_stage(out_dir, layer, stage, data)
        metadata["layers"].append({"layer": layer, "final_first16": [int(x) & 0xFF for x in final.reshape(-1)[:16]]})
        hidden = final

    ln_f = q6_piecewise_ln(hidden)
    lm_head = read_weight(weights, LM_HEAD_OFF, D_MODEL, VOCAB_SIZE)
    logits_i32, argmax = logits_argmax(ln_f, lm_head)
    loss, ppl = softmax_cross_entropy(logits_i32, targets)

    write_hex(out_dir / "final.mem", hidden, 8)
    write_bin(out_dir / "final.bin", hidden, np.int8)
    write_hex(out_dir / "ln_f.mem", ln_f, 8)
    write_bin(out_dir / "ln_f.bin", ln_f, np.int8)
    write_hex(out_dir / "logits_i32.mem", logits_i32, 32)
    write_bin(out_dir / "logits_i32.bin", logits_i32, np.dtype("<i4"))
    write_hex(out_dir / "argmax_tokens.mem", argmax, 16)

    quality_metrics = load_json(args.quality_root / "quality_metrics.json")
    fp32_ppl = float(quality_metrics["fp32"]["perplexity"])
    regression = ((ppl - fp32_ppl) / fp32_ppl) * 100.0
    metadata.update(
        {
            "fp32_perplexity": fp32_ppl,
            "hardware_exact_loss": loss,
            "hardware_exact_perplexity": ppl,
            "ppl_regression_pct": regression,
            "pass": bool(np.isfinite(regression) and regression <= args.threshold_pct),
            "argmax_first32": [int(x) for x in argmax[:32]],
            "ln_inv_std_lut": {
                "file": "ln_inv_std_q12.mem",
                "entries": int(ln_lut.size),
                "width": 16,
                "scale_q12": 4096,
            },
        }
    )
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "metrics.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    report = [
        "# Hardware-exact HLS Full INT8 Report",
        "",
        f"- result: `{'PASS' if metadata['pass'] else 'FAIL'}`",
        f"- fp32_ppl: `{fp32_ppl:.6f}`",
        f"- hardware_exact_ppl: `{ppl:.6f}`",
        f"- ppl_regression_pct: `{regression:.3f}%`",
        f"- threshold: `<= {args.threshold_pct:.1f}%`",
        f"- attention_mode: `{args.attention_mode}`",
        f"- softmax_bits: `{args.softmax_bits}`",
        f"- score_shift: `{args.score_shift}`",
        f"- out_dir: `{out_dir.as_posix()}`",
        "",
        "说明：此报告用于对齐当前 HLS/RTL 可部署语义；若 FAIL，不能作为最终精度版本上板验收。",
        "",
    ]
    (out_dir / "metrics.md").write_text("\n".join(report), encoding="utf-8")
    print(json.dumps(metadata, indent=2))
    if not metadata["pass"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
