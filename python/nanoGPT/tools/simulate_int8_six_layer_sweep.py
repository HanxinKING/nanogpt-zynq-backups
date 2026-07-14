from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from types import SimpleNamespace

import numpy as np

from export_fpga_int8_tile_golden import export_tile


NANOGPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = NANOGPT_ROOT.parent


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def read_hex_tail(path: Path, count: int = 16) -> list[str]:
    lines = [line.strip() for line in path.read_text(encoding="ascii").splitlines() if line.strip()]
    return lines[:count]


def main() -> None:
    parser = argparse.ArgumentParser(description="Run six-layer INT8 tile sweep and export per-layer golden.")
    parser.add_argument("--ckpt", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt")
    parser.add_argument(
        "--int8-state",
        type=Path,
        default=NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference" / "int8_state_dict.pt",
    )
    parser.add_argument("--dataset", default="shakespeare_char")
    parser.add_argument("--token-offset", type=int, default=0)
    parser.add_argument(
        "--out-root",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_layer_sweep",
    )
    parser.add_argument("--layers", type=int, default=6)
    args = parser.parse_args()

    args.out_root.mkdir(parents=True, exist_ok=True)

    summary: dict[str, object] = {
        "checkpoint": str(args.ckpt),
        "int8_state": str(args.int8_state),
        "dataset": args.dataset,
        "token_offset": args.token_offset,
        "layers": [],
    }

    prev_final_mem: Path | None = None
    for layer_index in range(args.layers):
        layer_dir = args.out_root / f"layer_{layer_index:02d}"
        layer_dir.mkdir(parents=True, exist_ok=True)
        export_args = SimpleNamespace(
            ckpt=args.ckpt,
            int8_state=args.int8_state,
            dataset=args.dataset,
            token_offset=args.token_offset,
            layer_index=layer_index,
            input_mem=prev_final_mem,
            out_dir=layer_dir,
            sync_active=False,
        )
        metadata = export_tile(export_args)
        final_mem = layer_dir / "final.mem"
        if not final_mem.exists():
            raise FileNotFoundError(final_mem)

        layer_entry = {
            "layer_index": layer_index,
            "out_dir": str(layer_dir),
            "input_mem": None if prev_final_mem is None else str(prev_final_mem),
            "final_mem": str(final_mem),
            "final_sha256": file_sha256(final_mem),
            "first16_final": read_hex_tail(final_mem, 16),
            "metadata": metadata,
        }
        summary["layers"].append(layer_entry)
        prev_final_mem = final_mem

    summary["final_layer"] = summary["layers"][-1] if summary["layers"] else None
    summary["final_sha256"] = summary["layers"][-1]["final_sha256"] if summary["layers"] else None
    (args.out_root / "six_layer_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
