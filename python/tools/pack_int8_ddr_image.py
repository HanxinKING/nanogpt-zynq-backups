from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


NANOGPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = NANOGPT_ROOT.parent


DDR_LAYOUT = {
    "input": 0x10000000,
    "output": 0x10002000,
    "weights": 0x11000000,
    "scales": 0x11C00000,
    "golden": 0x12000000,
    "mailbox": 0x12F00000,
}


def read_hex_bytes(path: Path) -> bytes:
    values = []
    with path.open("r", encoding="ascii") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            values.append(int(line, 16) & 0xFF)
    return bytes(values)


def read_hex_words_as_bytes(path: Path, width_bits: int) -> bytes:
    byte_count = max(1, width_bits // 8)
    out = bytearray()
    with path.open("r", encoding="ascii") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            value = int(line, 16)
            for byte_idx in range(byte_count):
                out.append((value >> (8 * byte_idx)) & 0xFF)
    return bytes(out)


def write_words_tcl(path: Path, blob: bytes, var_name: str) -> None:
    words = []
    for idx in range(0, len(blob), 4):
        chunk = blob[idx : idx + 4]
        word = 0
        for byte_idx, value in enumerate(chunk):
            word |= value << (8 * byte_idx)
        words.append(word)
    with path.open("w", encoding="ascii") as f:
        f.write(f"set {var_name} {{\n")
        for word in words:
            f.write(f"    0x{word:08x}\n")
        f.write("}\n")


def append_aligned(blob: bytearray, payload: bytes, align: int = 64) -> tuple[int, int]:
    while len(blob) % align:
        blob.append(0)
    offset = len(blob)
    blob.extend(payload)
    return offset, len(payload)


def pack(args: argparse.Namespace) -> dict:
    tile_dir = args.tile_dir
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    weights_blob = bytearray()
    weight_entries = {}
    for name in ["wq", "wk", "wv", "wo", "w1", "w2"]:
        payload = read_hex_bytes(tile_dir / f"{name}.mem")
        offset, size = append_aligned(weights_blob, payload)
        weight_entries[name] = {
            "file": f"{name}.mem",
            "offset": offset,
            "size": size,
            "ddr_addr": DDR_LAYOUT["weights"] + offset,
        }

    # Store quantization shifts and selected floating scales as compact metadata
    # for the PS loader. PL does not consume this yet, but the DDR image layout is fixed.
    metadata = json.loads((tile_dir / "tile_metadata.json").read_text(encoding="utf-8"))
    scale_words = []
    for key in ["q", "k", "v", "attn_proj", "ffn_mid", "ffn"]:
        scale_words.append(int(metadata["shifts"][key]) & 0xFFFFFFFF)
    scales_blob = np.asarray(scale_words, dtype="<u4").tobytes()

    input_blob = read_hex_bytes(tile_dir / "input.mem")
    golden_blob = read_hex_bytes(tile_dir / "final.mem")
    (out_dir / "input.bin").write_bytes(input_blob)
    (out_dir / "golden_final.bin").write_bytes(golden_blob)
    (out_dir / "weights.bin").write_bytes(bytes(weights_blob))
    (out_dir / "scales.bin").write_bytes(scales_blob)

    write_words_tcl(out_dir / "input_words.tcl", input_blob, "input_words")
    write_words_tcl(out_dir / "golden_words.tcl", golden_blob, "golden_words")
    write_words_tcl(out_dir / "weights_words.tcl", bytes(weights_blob), "weights_words")
    write_words_tcl(out_dir / "scales_words.tcl", scales_blob, "scales_words")

    manifest = {
        "ddr_layout": DDR_LAYOUT,
        "tile_dir": str(tile_dir),
        "input": {"size": len(input_blob), "ddr_addr": DDR_LAYOUT["input"]},
        "output": {"size": len(input_blob), "ddr_addr": DDR_LAYOUT["output"]},
        "golden": {"size": len(golden_blob), "ddr_addr": DDR_LAYOUT["golden"]},
        "weights": {
            "size": len(weights_blob),
            "ddr_addr": DDR_LAYOUT["weights"],
            "entries": weight_entries,
        },
        "scales": {
            "size": len(scales_blob),
            "ddr_addr": DDR_LAYOUT["scales"],
            "entries": list(metadata["shifts"].keys()),
        },
        "metadata": metadata,
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Pack INT8 tile data for JTAG/DDR loading.")
    parser.add_argument(
        "--tile-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_tile_l0_s32_d256",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_tile_l0_s32_d256" / "ddr_image",
    )
    return parser.parse_args()


def main() -> None:
    manifest = pack(parse_args())
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
