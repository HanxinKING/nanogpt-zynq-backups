from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import numpy as np
import torch


NANOGPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = NANOGPT_ROOT.parent


def load_torch(path: Path) -> Any:
    try:
        return torch.load(path, map_location="cpu", weights_only=False)
    except TypeError:
        return torch.load(path, map_location="cpu")


def write_f32_bin(path: Path, values: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(values.astype("<f4").reshape(-1).tobytes())


def write_f32_mem(path: Path, values: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii") as f:
        for value in values.astype(np.float32).reshape(-1):
            word = np.asarray([value], dtype="<f4").view("<u4")[0]
            f.write(f"{int(word):08x}\n")


def export(args: argparse.Namespace) -> dict[str, Any]:
    ckpt = load_torch(args.ckpt)
    int8_state = load_torch(args.int8_state)
    modules = int8_state["modules"]
    state = ckpt["model"]
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    entries: dict[str, dict[str, Any]] = {}
    blob = bytearray()

    def append(name: str, values: np.ndarray, rel: str) -> None:
        nonlocal blob
        while len(blob) % 64:
            blob.append(0)
        offset = len(blob)
        payload = values.astype("<f4").reshape(-1).tobytes()
        blob.extend(payload)
        write_f32_bin(out_dir / rel.replace(".mem", ".bin"), values)
        write_f32_mem(out_dir / rel, values)
        entries[name] = {
            "file": rel,
            "offset": offset,
            "bytes": len(payload),
            "shape": list(values.shape),
        }

    for layer in range(6):
        for ln in ["ln_1", "ln_2"]:
            key = f"transformer.h.{layer}.{ln}.weight"
            append(f"layer_{layer:02d}.{ln}.gamma", state[key].detach().cpu().numpy(), f"layer_{layer:02d}_{ln}_gamma.mem")
        for mod in ["attn.c_attn", "attn.c_proj", "mlp.c_fc", "mlp.c_proj"]:
            mkey = f"transformer.h.{layer}.{mod}"
            append(f"layer_{layer:02d}.{mod}.weight_scale", modules[mkey]["weight_scale"].detach().cpu().numpy(), f"layer_{layer:02d}_{mod.replace('.', '_')}_weight_scale.mem")
            act = modules[mkey].get("activation_scale")
            if act is not None:
                append(f"layer_{layer:02d}.{mod}.activation_scale", np.asarray([float(act)], dtype=np.float32), f"layer_{layer:02d}_{mod.replace('.', '_')}_activation_scale.mem")

    append("ln_f.gamma", state["transformer.ln_f.weight"].detach().cpu().numpy(), "ln_f_gamma.mem")
    append("lm_head.weight_scale", modules["lm_head"]["weight_scale"].detach().cpu().numpy(), "lm_head_weight_scale.mem")
    act = modules["lm_head"].get("activation_scale")
    if act is not None:
        append("lm_head.activation_scale", np.asarray([float(act)], dtype=np.float32), "lm_head_activation_scale.mem")

    (out_dir / "quality_params.bin").write_bytes(bytes(blob))
    manifest = {
        "kind": "quality_hw_params",
        "format": "float32 little-endian parameters for quality-mode implementation",
        "base_ddr_addr": args.base_ddr_addr,
        "size": len(blob),
        "entries": {
            name: {**entry, "ddr_addr": args.base_ddr_addr + entry["offset"]}
            for name, entry in entries.items()
        },
    }
    (out_dir / "quality_params_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export quality-mode scale/LN parameters.")
    parser.add_argument("--ckpt", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt")
    parser.add_argument("--int8-state", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference" / "int8_state_dict.pt")
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_hw_ppl_pass_s256_d384_l6" / "quality_params",
    )
    parser.add_argument("--base-ddr-addr", type=lambda x: int(x, 0), default=0x12200000)
    return parser.parse_args()


def main() -> None:
    manifest = export(parse_args())
    print(json.dumps({"size": manifest["size"], "entries": len(manifest["entries"])}, indent=2))


if __name__ == "__main__":
    main()
