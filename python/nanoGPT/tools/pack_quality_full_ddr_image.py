from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]

DDR_LAYOUT = {
    "input": 0x10000000,
    "output": 0x10020000,
    "weights": 0x11000000,
    "scales": 0x11C00000,
    "golden": 0x12000000,
    "lut": 0x12100000,
    "quality_params": 0x12200000,
    "debug": 0x12E00000,
    "mailbox": 0x12F00000,
}


def write_words_tcl(path: Path, blob: bytes, var_name: str) -> None:
    with path.open("w", encoding="ascii") as f:
        f.write(f"set {var_name} {{\n")
        for idx in range(0, len(blob), 4):
            word = 0
            for byte_idx, value in enumerate(blob[idx : idx + 4]):
                word |= value << (8 * byte_idx)
            f.write(f"    0x{word:08x}\n")
        f.write("}\n")


def read_hex_bytes(path: Path, byte_width: int = 1) -> bytes:
    out = bytearray()
    with path.open("r", encoding="ascii") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            value = int(line, 16)
            for i in range(byte_width):
                out.append((value >> (8 * i)) & 0xFF)
    return bytes(out)


def append_aligned(blob: bytearray, payload: bytes, align: int = 64) -> tuple[int, int]:
    while len(blob) % align:
        blob.append(0)
    offset = len(blob)
    blob.extend(payload)
    return offset, len(payload)


def pack(args: argparse.Namespace) -> dict:
    quality_root = args.quality_root
    quality_full = quality_root / "quality_full"
    base_ddr = args.base_ddr
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    if not quality_full.exists():
        raise FileNotFoundError(quality_full)
    if not base_ddr.exists():
        raise FileNotFoundError(base_ddr)

    input_blob = (base_ddr / "input.bin").read_bytes()
    final_blob = (quality_full / "final.bin").read_bytes()
    argmax_blob = read_hex_bytes(quality_full / "argmax_tokens.mem", byte_width=2)
    logits_blob = (quality_full / "logits_i32.bin").read_bytes()
    weights_blob = (base_ddr / "weights.bin").read_bytes()
    scales_blob = (base_ddr / "scales.bin").read_bytes()
    params_dir = quality_root / "quality_params"
    params_blob = (params_dir / "quality_params.bin").read_bytes()

    lut_blob = bytearray()
    lut_entries = {}
    for name, width in [
        ("gelu_int8_to_i16", 2),
        ("softmax_exp2_q15", 2),
        ("softmax_recip_q15", 2),
    ]:
        payload = read_hex_bytes(quality_root / "luts" / f"{name}.mem", byte_width=width)
        offset, size = append_aligned(lut_blob, payload)
        lut_entries[name] = {
            "offset": offset,
            "size": size,
            "ddr_addr": DDR_LAYOUT["lut"] + offset,
        }

    (out_dir / "input.bin").write_bytes(input_blob)
    (out_dir / "golden_final.bin").write_bytes(final_blob)
    (out_dir / "golden_argmax.bin").write_bytes(argmax_blob)
    (out_dir / "golden_logits_i32.bin").write_bytes(logits_blob)
    (out_dir / "weights.bin").write_bytes(weights_blob)
    (out_dir / "scales.bin").write_bytes(scales_blob)
    (out_dir / "luts.bin").write_bytes(bytes(lut_blob))
    (out_dir / "quality_params.bin").write_bytes(params_blob)
    write_words_tcl(out_dir / "input_words.tcl", input_blob, "quality_input_words")
    write_words_tcl(out_dir / "golden_argmax_words.tcl", argmax_blob, "quality_argmax_words")

    base_manifest = json.loads((base_ddr / "manifest.json").read_text(encoding="utf-8"))
    quality_metadata = json.loads((quality_full / "quality_full_metadata.json").read_text(encoding="utf-8"))
    manifest = {
        "kind": "quality_full_ddr_image",
        "ddr_layout": DDR_LAYOUT,
        "input": {"size": len(input_blob), "ddr_addr": DDR_LAYOUT["input"]},
        "output": {"size": len(final_blob), "ddr_addr": DDR_LAYOUT["output"]},
        "golden": {"size": len(final_blob), "ddr_addr": DDR_LAYOUT["golden"]},
        "argmax": {"size": len(argmax_blob), "ddr_addr": DDR_LAYOUT["mailbox"]},
        "weights": {
            "size": len(weights_blob),
            "ddr_addr": DDR_LAYOUT["weights"],
            "entries": base_manifest["weights"]["entries"],
        },
        "scales": {"size": len(scales_blob), "ddr_addr": DDR_LAYOUT["scales"]},
        "luts": {"size": len(lut_blob), "ddr_addr": DDR_LAYOUT["lut"], "entries": lut_entries},
        "quality_params": {
            "size": len(params_blob),
            "ddr_addr": DDR_LAYOUT["quality_params"],
            "manifest": json.loads((params_dir / "quality_params_manifest.json").read_text(encoding="utf-8")),
        },
        "quality_metadata": quality_metadata,
        "source_base_manifest": str(base_ddr / "manifest.json"),
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    shutil.copy2(quality_full / "argmax_tokens.mem", out_dir / "golden_argmax.mem")
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Pack quality full INT8 DDR image.")
    parser.add_argument(
        "--quality-root",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_hw_ppl_pass_s256_d384_l6",
    )
    parser.add_argument(
        "--base-ddr",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_full_s256_d384_l6" / "ddr_image",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_hw_ppl_pass_s256_d384_l6" / "ddr_image",
    )
    return parser.parse_args()


def main() -> None:
    manifest = pack(parse_args())
    print(json.dumps({
        "kind": manifest["kind"],
        "input_size": manifest["input"]["size"],
        "weights_size": manifest["weights"]["size"],
        "luts_size": manifest["luts"]["size"],
        "quality_params_size": manifest["quality_params"]["size"],
        "argmax_size": manifest["argmax"]["size"],
    }, indent=2))


if __name__ == "__main__":
    main()
