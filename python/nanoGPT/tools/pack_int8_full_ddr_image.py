from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


NANOGPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = NANOGPT_ROOT.parent


DDR_LAYOUT = {
    "input": 0x10000000,
    "output": 0x10020000,
    "weights": 0x11000000,
    "scales": 0x11C00000,
    "golden": 0x12000000,
    "debug": 0x12E00000,
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


def write_words_tcl(path: Path, blob: bytes, var_name: str) -> None:
    with path.open("w", encoding="ascii") as f:
        f.write(f"set {var_name} {{\n")
        for idx in range(0, len(blob), 4):
            chunk = blob[idx : idx + 4]
            word = 0
            for byte_idx, value in enumerate(chunk):
                word |= value << (8 * byte_idx)
            f.write(f"    0x{word:08x}\n")
        f.write("}\n")


def append_aligned(blob: bytearray, payload: bytes, align: int = 64) -> tuple[int, int]:
    while len(blob) % align:
        blob.append(0)
    offset = len(blob)
    blob.extend(payload)
    return offset, len(payload)


def pack(args: argparse.Namespace) -> dict:
    full_dir = args.full_dir
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    metadata = json.loads((full_dir / "full_metadata.json").read_text(encoding="utf-8"))
    input_blob = (full_dir / "input.bin").read_bytes() if (full_dir / "input.bin").exists() else read_hex_bytes(full_dir / "input.mem")
    golden_blob = (full_dir / "final.bin").read_bytes() if (full_dir / "final.bin").exists() else read_hex_bytes(full_dir / "final.mem")
    scales_blob = (full_dir / "scales.bin").read_bytes()

    weights_blob = bytearray()
    weight_entries = {}
    for name, entry in metadata["weight_entries"].items():
        rel = entry["file"]
        payload = read_hex_bytes(full_dir / rel)
        offset, size = append_aligned(weights_blob, payload)
        weight_entries[name] = {
            **entry,
            "offset": offset,
            "size": size,
            "ddr_addr": DDR_LAYOUT["weights"] + offset,
        }

    lm_head_payload = read_hex_bytes(full_dir / "lm_head.mem")
    lm_head_offset, lm_head_size = append_aligned(weights_blob, lm_head_payload)
    weight_entries["lm_head"] = {
        "file": "lm_head.mem",
        "shape": [metadata["d_model"], metadata["vocab_size"]],
        "offset": lm_head_offset,
        "size": lm_head_size,
        "ddr_addr": DDR_LAYOUT["weights"] + lm_head_offset,
    }

    weights_bytes = bytes(weights_blob)
    (out_dir / "input.bin").write_bytes(input_blob)
    (out_dir / "golden_final.bin").write_bytes(golden_blob)
    (out_dir / "weights.bin").write_bytes(weights_bytes)
    (out_dir / "scales.bin").write_bytes(scales_blob)
    write_words_tcl(out_dir / "input_words.tcl", input_blob, "input_words")
    write_words_tcl(out_dir / "golden_words.tcl", golden_blob, "golden_words")

    scale_words = np.frombuffer(scales_blob, dtype="<u4")
    manifest = {
        "kind": "full_int8_ddr_image",
        "full_dir": str(full_dir),
        "ddr_layout": DDR_LAYOUT,
        "input": {"size": len(input_blob), "ddr_addr": DDR_LAYOUT["input"]},
        "output": {"size": len(golden_blob), "ddr_addr": DDR_LAYOUT["output"]},
        "golden": {"size": len(golden_blob), "ddr_addr": DDR_LAYOUT["golden"]},
        "weights": {
            "size": len(weights_bytes),
            "ddr_addr": DDR_LAYOUT["weights"],
            "entries": weight_entries,
            "fits_before_scales_base": DDR_LAYOUT["weights"] + len(weights_bytes) <= DDR_LAYOUT["scales"],
        },
        "scales": {
            "size": len(scales_blob),
            "word_count": int(scale_words.size),
            "ddr_addr": DDR_LAYOUT["scales"],
        },
        "metadata": metadata,
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Pack full INT8 model artifacts into a PS DDR image layout.")
    parser.add_argument(
        "--full-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_full_s256_d384_l6",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_full_s256_d384_l6" / "ddr_image",
    )
    return parser.parse_args()


def main() -> None:
    manifest = pack(parse_args())
    print(json.dumps({
        "kind": manifest["kind"],
        "input_size": manifest["input"]["size"],
        "output_size": manifest["output"]["size"],
        "weights_size": manifest["weights"]["size"],
        "scales_size": manifest["scales"]["size"],
        "fits_before_scales_base": manifest["weights"]["fits_before_scales_base"],
    }, indent=2))


if __name__ == "__main__":
    main()
