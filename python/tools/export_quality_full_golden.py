from __future__ import annotations

import argparse
import json
import math
import pickle
import sys
from pathlib import Path
from typing import Any

import numpy as np
import torch
import torch.nn.functional as F


NANOGPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = NANOGPT_ROOT.parent
if str(NANOGPT_ROOT) not in sys.path:
    sys.path.insert(0, str(NANOGPT_ROOT))

from model import GPT, GPTConfig  # noqa: E402


SEQ_LEN = 256
D_MODEL = 384
N_LAYER = 6
VOCAB_SIZE = 65


def load_torch(path: Path) -> Any:
    try:
        return torch.load(path, map_location="cpu", weights_only=False)
    except TypeError:
        return torch.load(path, map_location="cpu")


def load_checkpoint_model(ckpt_path: Path) -> GPT:
    checkpoint = load_torch(ckpt_path)
    model = GPT(GPTConfig(**checkpoint["model_args"]))
    state_dict = checkpoint["model"]
    unwanted_prefix = "_orig_mod."
    for key in list(state_dict.keys()):
        if key.startswith(unwanted_prefix):
            state_dict[key[len(unwanted_prefix) :]] = state_dict.pop(key)
    model.load_state_dict(state_dict)
    model.eval()
    return model


def load_meta(dataset: str) -> dict[str, Any]:
    meta_path = NANOGPT_ROOT / "data" / dataset / "meta.pkl"
    with meta_path.open("rb") as f:
        return pickle.load(f)


def load_tokens(dataset: str, token_offset: int) -> tuple[np.ndarray, np.ndarray]:
    val = np.memmap(NANOGPT_ROOT / "data" / dataset / "val.bin", dtype=np.uint16, mode="r")
    tokens = np.asarray(val[token_offset : token_offset + SEQ_LEN], dtype=np.int64)
    targets = np.asarray(val[token_offset + 1 : token_offset + 1 + SEQ_LEN], dtype=np.int64)
    if tokens.size != SEQ_LEN or targets.size != SEQ_LEN:
        raise ValueError("not enough validation tokens")
    return tokens, targets


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


def softmax_cross_entropy(logits: np.ndarray, targets: np.ndarray) -> tuple[float, float]:
    logits64 = logits.astype(np.float64)
    logits64 -= logits64.max(axis=1, keepdims=True)
    logsumexp = np.log(np.exp(logits64).sum(axis=1))
    nll = -logits64[np.arange(logits64.shape[0]), targets] + logsumexp
    loss = float(nll.mean())
    return loss, float(math.exp(loss))


def quant_i8_per_tensor(x: torch.Tensor) -> tuple[np.ndarray, float]:
    max_abs = float(x.detach().abs().max().item())
    scale = max(max_abs / 127.0, float(torch.finfo(torch.float32).eps))
    q = torch.clamp(torch.round(x.detach().cpu().float() / scale), -128, 127).to(torch.int8)
    return q.numpy().astype(np.int8), scale


def export_quality(args: argparse.Namespace) -> dict[str, Any]:
    model = load_checkpoint_model(args.ckpt)
    tokens, targets = load_tokens(args.dataset, args.token_offset)
    x = torch.tensor(tokens, dtype=torch.long).unsqueeze(0)

    stage_tensors: dict[str, torch.Tensor] = {}
    hooks = []

    def save_hook(name: str):
        def hook(_module, _inputs, output):
            if isinstance(output, tuple):
                value = output[0]
            else:
                value = output
            if torch.is_tensor(value):
                stage_tensors[name] = value.detach().cpu()

        return hook

    for i, block in enumerate(model.transformer.h):
        hooks.append(block.ln_1.register_forward_hook(save_hook(f"layer_{i:02d}.ln1")))
        hooks.append(block.attn.register_forward_hook(save_hook(f"layer_{i:02d}.attn")))
        hooks.append(block.ln_2.register_forward_hook(save_hook(f"layer_{i:02d}.ln2")))
        hooks.append(block.mlp.register_forward_hook(save_hook(f"layer_{i:02d}.ffn")))
        hooks.append(block.register_forward_hook(save_hook(f"layer_{i:02d}.final")))
    hooks.append(model.transformer.ln_f.register_forward_hook(save_hook("ln_f")))

    with torch.no_grad():
        logits, _ = model(x, torch.tensor(targets, dtype=torch.long).unsqueeze(0))
    for h in hooks:
        h.remove()

    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    layers_dir = out_dir / "layers"
    q_stage: dict[str, dict[str, Any]] = {}
    for name, tensor in stage_tensors.items():
        arr = tensor.squeeze(0)
        q, scale = quant_i8_per_tensor(arr)
        q_stage[name] = {"shape": list(q.shape), "scale": scale}
        if name.startswith("layer_"):
            layer, stage = name.split(".")
            stage_dir = layers_dir / layer
            write_hex(stage_dir / f"{stage}.mem", q, 8)
            write_bin(stage_dir / f"{stage}.bin", q, np.int8)
        else:
            write_hex(out_dir / f"{name}.mem", q, 8)
            write_bin(out_dir / f"{name}.bin", q, np.int8)

    logits_np = logits.squeeze(0).detach().cpu().numpy().astype(np.float32)
    logits_i32 = np.rint(logits_np * args.logit_scale).astype(np.int32)
    argmax = np.argmax(logits_i32, axis=1).astype(np.int32)
    loss, ppl = softmax_cross_entropy(logits_np, targets)

    write_hex(out_dir / "logits_i32.mem", logits_i32, 32)
    write_bin(out_dir / "logits_i32.bin", logits_i32, np.dtype("<i4"))
    write_hex(out_dir / "argmax_tokens.mem", argmax, 16)
    write_hex(out_dir / "target_tokens.mem", targets.astype(np.int32), 16)
    write_hex(out_dir / "input_tokens.mem", tokens.astype(np.int32), 16)

    final_q = (layers_dir / "layer_05" / "final.bin").read_bytes()
    (out_dir / "final.bin").write_bytes(final_q)
    (out_dir / "final.mem").write_text((layers_dir / "layer_05" / "final.mem").read_text(encoding="ascii"), encoding="ascii")

    metadata = {
        "kind": "quality_full_golden",
        "checkpoint": str(args.ckpt),
        "dataset": args.dataset,
        "token_offset": args.token_offset,
        "seq_len": SEQ_LEN,
        "d_model": D_MODEL,
        "n_layer": N_LAYER,
        "vocab_size": VOCAB_SIZE,
        "logit_scale": args.logit_scale,
        "loss": loss,
        "perplexity": ppl,
        "stage_quant": q_stage,
        "argmax_first32": [int(v) for v in argmax[:32]],
        "target_first32": [int(v) for v in targets[:32]],
    }
    (out_dir / "quality_full_metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return metadata


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export high-quality full-model golden for FPGA quality mode.")
    parser.add_argument("--ckpt", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt")
    parser.add_argument("--dataset", default="shakespeare_char")
    parser.add_argument("--token-offset", type=int, default=0)
    parser.add_argument("--logit-scale", type=float, default=1024.0)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_hw_ppl_pass_s256_d384_l6" / "quality_full",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    metadata = export_quality(args)
    print(json.dumps({
        "out_dir": str(args.out_dir),
        "loss": metadata["loss"],
        "perplexity": metadata["perplexity"],
        "argmax_first32": metadata["argmax_first32"],
    }, indent=2))


if __name__ == "__main__":
    main()
