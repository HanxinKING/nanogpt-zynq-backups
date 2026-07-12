from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[2]
SEQ_LEN = 256
D_MODEL = 384
N_HEAD = 6
HEAD_DIM = D_MODEL // N_HEAD


def read_i8_mem(path: Path, shape: tuple[int, ...] = (SEQ_LEN, D_MODEL)) -> np.ndarray:
    vals: list[int] = []
    for line in path.read_text(encoding="ascii").splitlines():
        text = line.strip()
        if not text:
            continue
        val = int(text, 16)
        vals.append(val if val < 128 else val - 256)
    return np.asarray(vals, dtype=np.int16).reshape(shape)


def read_u6_mem(path: Path) -> np.ndarray:
    return np.asarray(
        [int(line.strip(), 16) & 0x3F for line in path.read_text(encoding="ascii").splitlines() if line.strip()],
        dtype=np.int16,
    )


def read_u32_mem(path: Path) -> np.ndarray:
    return np.asarray(
        [int(line.strip(), 16) & 0xFFFFFFFF for line in path.read_text(encoding="ascii").splitlines() if line.strip()],
        dtype=np.int64,
    )


def write_i8_mem(path: Path, data: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii") as f:
        for value in data.astype(np.int16).reshape(-1):
            f.write(f"{int(value) & 0xFF:02x}\n")


def write_i8_bin(path: Path, data: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data.astype(np.int8).reshape(-1).tobytes())


def read_lut_i8(path: Path) -> np.ndarray:
    vals: list[int] = []
    for line in path.read_text(encoding="ascii").splitlines():
        text = line.strip()
        if not text:
            continue
        val = int(text, 16)
        vals.append(val if val < 128 else val - 256)
    return np.asarray(vals, dtype=np.int16)


def clamp_i8(value: int) -> int:
    return max(-128, min(127, value))


def round_div_signed(num: int, den: int) -> int:
    if den == 0:
        return 0
    half = den // 2
    if num >= 0:
        return (num + half) // den
    return -((-num + half) // den)


def rtl_scaled_div_i8(acc: int, den: int, mult_q30: int) -> int:
    divisor = den << 30
    return clamp_i8(round_div_signed(acc * mult_q30, divisor))


def requant_q30(acc: int, mult_q30: int) -> int:
    return clamp_i8(round_div_signed(acc * mult_q30, 1 << 30))


def residual_res1_q30(input_value: int, proj_value: int) -> int:
    # Mirrors hls_kernel_chain_axis_full_only_core.v residual_res1_q30.
    scaled = (input_value * 343_412_280) + (proj_value * 1_023_343_639)
    return clamp_i8(round_div_signed(scaled, 1 << 30))


def square_i8(value: int) -> int:
    return value * value


def div384_u32(value: int) -> int:
    return (value * 683) >> 18


def ln_inv_std_piecewise_q12(var_value: int) -> int:
    if var_value <= 1:
        return 4096
    if var_value <= 2:
        return 2896
    if var_value <= 4:
        return 2048
    if var_value <= 8:
        return 1448
    if var_value <= 16:
        return 1024
    if var_value <= 32:
        return 724
    if var_value <= 64:
        return 512
    if var_value <= 128:
        return 362
    if var_value <= 256:
        return 256
    if var_value <= 512:
        return 181
    if var_value <= 1024:
        return 128
    if var_value <= 2048:
        return 91
    if var_value <= 4096:
        return 64
    if var_value <= 8192:
        return 45
    return 32


def ln_norm_q6(value: int, mean: int, inv_std_q12: int) -> int:
    centered = value - mean
    rounded = round_div_signed(centered * inv_std_q12 * 32, 1 << 12)
    return max(-32, min(31, rounded))


def rtl_ln2_from_res1(res1: np.ndarray) -> np.ndarray:
    out = np.zeros_like(res1, dtype=np.int16)
    for row in range(SEQ_LEN):
        vals = res1[row, :].astype(np.int32)
        row_sum = int(vals.sum())
        abs_sum = abs(row_sum)
        mean_mag = abs_sum // 384
        mean = -mean_mag if row_sum < 0 else mean_mag
        sq_sum = int(sum(square_i8(int(x)) for x in vals))
        sq_mean = div384_u32(sq_sum)
        mean_sq = mean * mean
        var_value = (sq_mean - mean_sq + 1) if sq_mean > mean_sq else 1
        inv = ln_inv_std_piecewise_q12(var_value)
        for col in range(D_MODEL):
            out[row, col] = ln_norm_q6(int(vals[col]), mean, inv)
    return out


def round_shift_array(values: np.ndarray, shift: int) -> np.ndarray:
    abs_values = np.abs(values.astype(np.int64))
    rounded = (abs_values + (1 << (shift - 1))) >> shift
    return np.where(values >= 0, rounded, -rounded)


def clamp_i8_array(values: np.ndarray) -> np.ndarray:
    return np.clip(values, -128, 127).astype(np.int16)


def qkv_shift(kind: str, layer: int) -> int:
    q_shifts = [13, 12, 12, 12, 12, 12]
    k_shifts = [13, 13, 13, 12, 12, 12]
    v_shifts = [13, 13, 12, 12, 12, 12]
    if kind == "q":
        return q_shifts[layer]
    if kind == "k":
        return k_shifts[layer]
    return v_shifts[layer]


def stage_shift(kind: str, layer: int) -> int:
    attn_proj_shifts = [10, 10, 11, 10, 10, 10]
    ffn_mid_shifts = [13, 13, 13, 12, 12, 13]
    ffn_shifts = [11, 11, 11, 12, 11, 10]
    if kind == "attn_proj":
        return attn_proj_shifts[layer]
    if kind == "ffn_mid":
        return ffn_mid_shifts[layer]
    return ffn_shifts[layer]


def rtl_ln1_from_input(input_i8: np.ndarray) -> np.ndarray:
    return rtl_ln2_from_res1(input_i8)


def matmul_shift_i8(x: np.ndarray, w: np.ndarray, shift: int) -> np.ndarray:
    return clamp_i8_array(round_shift_array(x.astype(np.int64) @ w.astype(np.int64), shift))


def export_layer(root: Path, layer: int, input_override: np.ndarray | None = None) -> tuple[dict[str, object], np.ndarray]:
    metrics = json.loads((root / "metrics.json").read_text(encoding="utf-8"))
    requant = json.loads((root / "requant_params_manifest.json").read_text(encoding="utf-8"))
    name = f"layer_{layer:02d}"
    layer_dir = root / "layers" / name
    weights_root = REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_full_s256_d384_l6" / "weights"
    input_i8 = (
        input_override.astype(np.int16)
        if input_override is not None
        else read_i8_mem(layer_dir / "input.mem").astype(np.int16)
    )
    write_i8_mem(layer_dir / "input_rtl_lut.mem", input_i8)
    write_i8_bin(layer_dir / "input_rtl_lut.bin", input_i8)

    if layer == 0:
        q = read_i8_mem(layer_dir / "q.mem").astype(np.int32)
        k = read_i8_mem(layer_dir / "k.mem").astype(np.int32)
        v = read_i8_mem(layer_dir / "v.mem").astype(np.int32)
        write_i8_mem(layer_dir / "q_rtl_lut.mem", q)
        write_i8_bin(layer_dir / "q_rtl_lut.bin", q)
        write_i8_mem(layer_dir / "k_rtl_lut.mem", k)
        write_i8_bin(layer_dir / "k_rtl_lut.bin", k)
        write_i8_mem(layer_dir / "v_rtl_lut.mem", v)
        write_i8_bin(layer_dir / "v_rtl_lut.bin", v)
    else:
        ln1 = rtl_ln1_from_input(input_i8)
        write_i8_mem(layer_dir / "ln1_rtl_lut.mem", ln1)
        write_i8_bin(layer_dir / "ln1_rtl_lut.bin", ln1)
        wq = read_i8_mem(weights_root / f"layer_{layer:02d}_wq.mem", (D_MODEL, D_MODEL)).astype(np.int64)
        wk = read_i8_mem(weights_root / f"layer_{layer:02d}_wk.mem", (D_MODEL, D_MODEL)).astype(np.int64)
        wv = read_i8_mem(weights_root / f"layer_{layer:02d}_wv.mem", (D_MODEL, D_MODEL)).astype(np.int64)
        q = matmul_shift_i8(ln1, wq, qkv_shift("q", layer)).astype(np.int32)
        k = matmul_shift_i8(ln1, wk, qkv_shift("k", layer)).astype(np.int32)
        v = matmul_shift_i8(ln1, wv, qkv_shift("v", layer)).astype(np.int32)
        write_i8_mem(layer_dir / "q_rtl_lut.mem", q)
        write_i8_bin(layer_dir / "q_rtl_lut.bin", q)
        write_i8_mem(layer_dir / "k_rtl_lut.mem", k)
        write_i8_bin(layer_dir / "k_rtl_lut.bin", k)
        write_i8_mem(layer_dir / "v_rtl_lut.mem", v)
        write_i8_bin(layer_dir / "v_rtl_lut.bin", v)
    exp_lut = read_u6_mem(root / "luts" / "attn_exp_neg_q6_q4.mem").astype(np.int32)

    q_scale = float(metrics["stage_quant"][f"{name}.q"]["scale"])
    k_scale = float(metrics["stage_quant"][f"{name}.k"]["scale"])
    v_scale = float(metrics["stage_quant"][f"{name}.v"]["scale"])
    out_scale = float(requant["entries"][f"{name}.attn_proj"]["activation_scale"])
    score_scale_q20_values = [373, 142, 299, 215, 250, 176]
    score_scale_q20 = score_scale_q20_values[layer]
    # Mirrors the current RTL constant used in ST_ATTN_DIV_MUL. The present
    # bit does not switch this multiplier per layer.
    out_mult_q30 = 0x4D8DC518

    out = np.zeros((SEQ_LEN, D_MODEL), dtype=np.int16)
    for row in range(SEQ_LEN):
        for head in range(N_HEAD):
            start = head * HEAD_DIM
            end = start + HEAD_DIM
            scores = q[row, start:end] @ k[: row + 1, start:end].T
            best = int(scores.max())
            diff = best - scores
            idx = ((diff.astype(np.int64) * score_scale_q20 + 32768) >> 16).clip(0, 255)
            weights = exp_lut[idx].astype(np.int32)
            den = int(weights.sum())
            for dim in range(HEAD_DIM):
                acc = int((v[: row + 1, start + dim] * weights).sum())
                out[row, start + dim] = rtl_scaled_div_i8(acc, den, out_mult_q30)

    write_i8_mem(layer_dir / "attn_proj_in_rtl_lut.mem", out)
    write_i8_bin(layer_dir / "attn_proj_in_rtl_lut.bin", out)

    wo = read_i8_mem(weights_root / f"layer_{layer:02d}_wo.mem", (D_MODEL, D_MODEL)).astype(np.int32)
    # The current RTL initializes one attn projection ROM from layer_00 and
    # reuses it for all scheduled layers.
    attn_proj_mult = read_u32_mem(root / "scale_params" / "layer_00_attn_proj_mult_q30.mem")
    attn_proj = np.zeros((SEQ_LEN, D_MODEL), dtype=np.int16)
    for row in range(SEQ_LEN):
        for col in range(D_MODEL):
            acc = int(out[row, :].astype(np.int32) @ wo[:, col])
            attn_proj[row, col] = requant_q30(acc, int(attn_proj_mult[col]))
    write_i8_mem(layer_dir / "attn_proj_rtl_lut.mem", attn_proj)
    write_i8_bin(layer_dir / "attn_proj_rtl_lut.bin", attn_proj)

    res1 = np.zeros((SEQ_LEN, D_MODEL), dtype=np.int16)
    for row in range(SEQ_LEN):
        for col in range(D_MODEL):
            res1[row, col] = residual_res1_q30(int(input_i8[row, col]), int(attn_proj[row, col]))
    write_i8_mem(layer_dir / "res1_rtl_lut.mem", res1)
    write_i8_bin(layer_dir / "res1_rtl_lut.bin", res1)

    ln2 = rtl_ln2_from_res1(res1)
    write_i8_mem(layer_dir / "ln2_rtl_lut.mem", ln2)
    write_i8_bin(layer_dir / "ln2_rtl_lut.bin", ln2)

    # RTL addresses W1 as W_BASE + mac_dim * 1536 + hidden_dim, so the file
    # layout is D_MODEL x MLP_DIM and the Python reference must use ln2 @ w1.
    w1 = read_i8_mem(weights_root / f"layer_{layer:02d}_w1.mem", (D_MODEL, 1536)).astype(np.int64)
    w2 = read_i8_mem(weights_root / f"layer_{layer:02d}_w2.mem", (1536, D_MODEL)).astype(np.int64)
    gelu_lut = read_lut_i8(
        REPO_ROOT
        / "fpga"
        / "nano_gpt"
        / "generated"
        / "int8_hw_ppl_pass_s256_d384_l6"
        / "luts"
        / "gelu_int8_to_i8.mem"
    )
    ffn_mid = clamp_i8_array(round_shift_array(ln2.astype(np.int64) @ w1, stage_shift("ffn_mid", layer)))
    ffn_gelu = gelu_lut[ffn_mid.astype(np.int16) & 0xFF].astype(np.int16)
    ffn = clamp_i8_array(round_shift_array(ffn_gelu.astype(np.int64) @ w2, stage_shift("ffn", layer)))
    final = clamp_i8_array(res1.astype(np.int32) + ffn.astype(np.int32))
    write_i8_mem(layer_dir / "ffn_rtl_lut.mem", ffn)
    write_i8_bin(layer_dir / "ffn_rtl_lut.bin", ffn)
    write_i8_mem(layer_dir / "final_rtl_lut.mem", final)
    write_i8_bin(layer_dir / "final_rtl_lut.bin", final)
    return {
        "layer": name,
        "score_scale_q20": score_scale_q20,
        "out_mult_q30": out_mult_q30,
        "outputs": {
            "attn_proj_in": f"layers/{name}/attn_proj_in_rtl_lut.mem",
            "attn_proj": f"layers/{name}/attn_proj_rtl_lut.mem",
            "res1": f"layers/{name}/res1_rtl_lut.mem",
            "ln2": f"layers/{name}/ln2_rtl_lut.mem",
            "ffn": f"layers/{name}/ffn_rtl_lut.mem",
            "final": f"layers/{name}/final_rtl_lut.mem",
        },
    }, final


def export_layers(root: Path, max_layers: int) -> dict[str, object]:
    input_override: np.ndarray | None = None
    layers = []
    for layer in range(max_layers):
        result, input_override = export_layer(root, layer, input_override)
        layers.append(result)
    if input_override is not None:
        write_i8_mem(root / "final_rtl_lut.mem", input_override)
        write_i8_bin(root / "final_rtl_lut.bin", input_override)
    return {"layers": layers, "final": "final_rtl_lut.mem"}


def main() -> None:
    parser = argparse.ArgumentParser(description="Export RTL LUT-exact attention target.")
    parser.add_argument(
        "--root",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_quality_hw_exact_s256_d384_l6",
    )
    parser.add_argument("--layer", type=int, default=0)
    parser.add_argument("--max-layers", type=int, default=None)
    args = parser.parse_args()
    if args.max_layers is not None:
        result = export_layers(args.root, args.max_layers)
    else:
        result, _ = export_layer(args.root, args.layer)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
