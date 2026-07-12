from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[2]
FPGA_ROOT = REPO_ROOT / "fpga" / "nano_gpt"
QUALITY_ROOT = FPGA_ROOT / "generated" / "int8_quality_hw_exact_s256_d384_l6"
WEIGHTS_ROOT = FPGA_ROOT / "generated" / "int8_full_s256_d384_l6" / "weights"
GELU_LUT = FPGA_ROOT / "generated" / "int8_hw_ppl_pass_s256_d384_l6" / "luts" / "gelu_int8_to_i8.mem"

SEQ = 256
D = 384
MLP = 1536
W_BASE = 0x1100_0000
FULL_W1_BYTES = D * MLP


@dataclass
class CheckResult:
    name: str
    total: int
    mismatch: int
    first_index: int | None
    rtl: int | None
    py: int | None
    detail: str


def to_i8(value: int) -> int:
    value &= 0xFF
    return value if value < 128 else value - 256


def to_i32(value: int) -> int:
    value &= 0xFFFF_FFFF
    return value if value < 0x8000_0000 else value - 0x1_0000_0000


def read_mem_values(path: Path, signed_bits: int, expected_count: int | None = None) -> np.ndarray:
    vals: list[int] = []
    with path.open("r", encoding="ascii") as f:
        for line in f:
            text = line.strip()
            if not text:
                continue
            raw = int(text, 16)
            if signed_bits == 8:
                vals.append(to_i8(raw))
            elif signed_bits == 32:
                vals.append(to_i32(raw))
            else:
                vals.append(raw)
    if expected_count is not None and len(vals) != expected_count:
        raise ValueError(f"{path} count={len(vals)} expected={expected_count}")
    return np.asarray(vals, dtype=np.int64)


def read_i8_matrix(path: Path, shape: tuple[int, int]) -> np.ndarray:
    return read_mem_values(path, 8, shape[0] * shape[1]).reshape(shape)


def read_i32_matrix(path: Path, shape: tuple[int, int]) -> np.ndarray:
    return read_mem_values(path, 32, shape[0] * shape[1]).reshape(shape)


def read_final_i8_matrix(path: Path, shape: tuple[int, int]) -> np.ndarray:
    expected = shape[0] * shape[1]
    vals = read_mem_values(path, 8)
    if vals.size == expected:
        return vals.reshape(shape)

    # Older FFN_FULL_DIAG dumps wrote lane3 repeatedly while AWVALID waited.
    groups_per_row = shape[1] // 4
    legacy_group_len = 6
    legacy_count = shape[0] * groups_per_row * legacy_group_len
    if shape[1] % 4 == 0 and vals.size == legacy_count:
        return vals.reshape(shape[0], groups_per_row, legacy_group_len)[:, :, :4].reshape(shape)

    raise ValueError(f"{path} count={vals.size} expected={expected} or legacy={legacy_count}")


def round_shift_signed(values: np.ndarray, shift: int) -> np.ndarray:
    values = values.astype(np.int64)
    abs_values = np.abs(values)
    rounded = (abs_values + (1 << (shift - 1))) >> shift
    return np.where(values >= 0, rounded, -rounded)


def clamp_i8(values: np.ndarray) -> np.ndarray:
    return np.clip(values, -128, 127).astype(np.int64)


def compare_array(name: str, rtl: np.ndarray, py: np.ndarray, detail_fn=None) -> CheckResult:
    flat_rtl = rtl.reshape(-1)
    flat_py = py.reshape(-1)
    if flat_rtl.size != flat_py.size:
        raise ValueError(f"{name}: size mismatch rtl={flat_rtl.size} py={flat_py.size}")
    diff = flat_rtl != flat_py
    mismatch = int(diff.sum())
    first = int(np.argmax(diff)) if mismatch else None
    detail = ""
    if first is not None and detail_fn is not None:
        detail = detail_fn(first)
    return CheckResult(
        name=name,
        total=int(flat_rtl.size),
        mismatch=mismatch,
        first_index=first,
        rtl=int(flat_rtl[first]) if first is not None else None,
        py=int(flat_py[first]) if first is not None else None,
        detail=detail,
    )


def stream_check_w1(dump_dir: Path, check_weight: bool) -> CheckResult:
    path = dump_dir / ("w1_weight_full.mem" if check_weight else "w1_addr_full.mem")
    w1 = read_mem_values(WEIGHTS_ROOT / "layer_00_w1.mem", 8, D * MLP)
    total = 0
    mismatch = 0
    first = None
    rtl_first = None
    py_first = None
    detail = ""
    with path.open("r", encoding="ascii") as f:
        for row in range(SEQ):
            for hidden in range(MLP):
                for mac in range(D):
                    line = f.readline()
                    if not line:
                        raise ValueError(f"{path} ended at total={total}")
                    rtl_raw = int(line.strip(), 16)
                    offset = mac * MLP + hidden
                    byte_addr = W_BASE + offset
                    expected = int(w1[offset]) if check_weight else byte_addr & ~0x3
                    rtl_val = to_i8(rtl_raw) if check_weight else rtl_raw
                    if rtl_val != expected:
                        mismatch += 1
                        if first is None:
                            first = total
                            rtl_first = rtl_val
                            py_first = expected
                            detail = f"row={row} hidden={hidden} mac={mac} byte_addr=0x{byte_addr:08x} lane={byte_addr & 0x3}"
                    total += 1
        if f.readline():
            raise ValueError(f"{path} has trailing data after expected total={total}")
    return CheckResult("w1_weight" if check_weight else "w1_addr", total, mismatch, first, rtl_first, py_first, detail)


def stream_check_w2(dump_dir: Path, check_weight: bool) -> CheckResult:
    path = dump_dir / ("w2_weight_full.mem" if check_weight else "w2_addr_full.mem")
    w2 = read_mem_values(WEIGHTS_ROOT / "layer_00_w2.mem", 8, MLP * D)
    total = 0
    mismatch = 0
    first = None
    rtl_first = None
    py_first = None
    detail = ""
    with path.open("r", encoding="ascii") as f:
        for row in range(SEQ):
            for col in range(D):
                for hidden in range(MLP):
                    line = f.readline()
                    if not line:
                        raise ValueError(f"{path} ended at total={total}")
                    rtl_raw = int(line.strip(), 16)
                    offset = hidden * D + col
                    byte_addr = W_BASE + FULL_W1_BYTES + offset
                    expected = int(w2[offset]) if check_weight else byte_addr & ~0x3
                    rtl_val = to_i8(rtl_raw) if check_weight else rtl_raw
                    if rtl_val != expected:
                        mismatch += 1
                        if first is None:
                            first = total
                            rtl_first = rtl_val
                            py_first = expected
                            detail = f"row={row} col={col} hidden={hidden} byte_addr=0x{byte_addr:08x} lane={byte_addr & 0x3}"
                    total += 1
        if f.readline():
            raise ValueError(f"{path} has trailing data after expected total={total}")
    return CheckResult("w2_weight" if check_weight else "w2_addr", total, mismatch, first, rtl_first, py_first, detail)


def format_result(r: CheckResult) -> str:
    first = "none" if r.first_index is None else str(r.first_index)
    rtl = "none" if r.rtl is None else str(r.rtl)
    py = "none" if r.py is None else str(r.py)
    detail = "" if not r.detail else f" | {r.detail}"
    return f"| {r.name} | {r.mismatch} / {r.total} | {first} | {rtl} | {py} |{detail} |"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dump-dir", type=Path, required=True)
    args = parser.parse_args()
    dump_dir = args.dump_dir.resolve()

    results: list[CheckResult] = []

    ln2 = read_i8_matrix(dump_dir / "ln2_full.mem", (SEQ, D))
    ln2_expected = read_i8_matrix(QUALITY_ROOT / "layers" / "layer_00" / "ln2_rtl_lut.mem", (SEQ, D))
    results.append(compare_array("ln2", ln2, ln2_expected, lambda i: f"row={i // D} col={i % D}"))

    # Address/weight streams are large; check them before derived math so layout bugs are explicit.
    results.append(stream_check_w1(dump_dir, check_weight=False))
    results.append(stream_check_w1(dump_dir, check_weight=True))

    w1 = read_mem_values(WEIGHTS_ROOT / "layer_00_w1.mem", 8, D * MLP).reshape(D, MLP)
    w1_acc_py = ln2.astype(np.int64) @ w1.astype(np.int64)
    w1_acc_rtl = read_i32_matrix(dump_dir / "w1_acc_full.mem", (SEQ, MLP))
    results.append(compare_array("w1_acc", w1_acc_rtl, w1_acc_py, lambda i: f"row={i // MLP} hidden={i % MLP}"))

    ffn_mid_py = clamp_i8(round_shift_signed(w1_acc_py, 13))
    ffn_mid_rtl = read_i8_matrix(dump_dir / "ffn_mid_full.mem", (SEQ, MLP))
    results.append(compare_array("ffn_mid", ffn_mid_rtl, ffn_mid_py, lambda i: f"row={i // MLP} hidden={i % MLP}"))

    gelu_in_rtl = read_i8_matrix(dump_dir / "gelu_in_full.mem", (SEQ, MLP))
    results.append(compare_array("gelu_in_vs_ffn_mid", gelu_in_rtl, ffn_mid_rtl, lambda i: f"row={i // MLP} hidden={i % MLP}"))

    gelu_lut = read_mem_values(GELU_LUT, 8, 256)
    gelu_py = gelu_lut[gelu_in_rtl.astype(np.int16) & 0xFF]
    gelu_out_rtl = read_i8_matrix(dump_dir / "gelu_out_full.mem", (SEQ, MLP))
    results.append(compare_array("gelu_out", gelu_out_rtl, gelu_py, lambda i: f"row={i // MLP} hidden={i % MLP}"))

    results.append(stream_check_w2(dump_dir, check_weight=False))
    results.append(stream_check_w2(dump_dir, check_weight=True))

    w2 = read_mem_values(WEIGHTS_ROOT / "layer_00_w2.mem", 8, MLP * D).reshape(MLP, D)
    w2_acc_py = gelu_out_rtl.astype(np.int64) @ w2.astype(np.int64)
    w2_acc_rtl = read_i32_matrix(dump_dir / "w2_acc_full.mem", (SEQ, D))
    results.append(compare_array("w2_acc", w2_acc_rtl, w2_acc_py, lambda i: f"row={i // D} col={i % D}"))

    ffn_py = clamp_i8(round_shift_signed(w2_acc_py, 11))
    ffn_rtl = read_i8_matrix(dump_dir / "ffn_out_full.mem", (SEQ, D))
    results.append(compare_array("ffn_out", ffn_rtl, ffn_py, lambda i: f"row={i // D} col={i % D}"))

    res1 = read_i8_matrix(QUALITY_ROOT / "layers" / "layer_00" / "res1_rtl_lut.mem", (SEQ, D))
    final_py = clamp_i8(res1.astype(np.int64) + ffn_rtl.astype(np.int64))
    final_rtl = read_final_i8_matrix(dump_dir / "final_full.mem", (SEQ, D))
    results.append(compare_array("final", final_rtl, final_py, lambda i: f"row={i // D} col={i % D}"))

    first_bad = next((r for r in results if r.mismatch), None)
    if first_bad is None:
        conclusion = "PASS: FFN diagnostic dump matches Python RTL-exact analysis."
    elif first_bad.name.startswith("w1_addr") or first_bad.name.startswith("w1_weight"):
        conclusion = "First divergence category: W1 address/layout."
    elif first_bad.name in {"w1_acc", "ffn_mid"}:
        conclusion = "First divergence category: W1 accumulate or shift."
    elif first_bad.name.startswith("gelu"):
        conclusion = "First divergence category: GELU HLS input/output."
    elif first_bad.name.startswith("w2_addr") or first_bad.name.startswith("w2_weight"):
        conclusion = "First divergence category: W2 address/layout."
    elif first_bad.name in {"w2_acc", "ffn_out"}:
        conclusion = "First divergence category: W2 accumulate or shift."
    else:
        conclusion = "First divergence category: final residual."

    lines = [
        "# FFN Full Diagnostic Report",
        "",
        f"- dump_dir: `{dump_dir}`",
        f"- conclusion: `{conclusion}`",
        "",
        "| stage | mismatch | first_index | rtl | python | detail |",
        "|---|---:|---:|---:|---:|---|",
    ]
    lines.extend(format_result(r) for r in results)
    report = dump_dir / "ffn_full_diag_report.md"
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"FFN_FULL_DIAG_REPORT={report}")
    print(conclusion)


if __name__ == "__main__":
    main()
