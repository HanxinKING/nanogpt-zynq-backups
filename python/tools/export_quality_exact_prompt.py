from __future__ import annotations

import argparse
import gc
import json
import pickle
import time
from pathlib import Path
from types import SimpleNamespace

import numpy as np

from export_quality_exact_hw_full import export_one_block, NANOGPT_ROOT, REPO_ROOT, SEQ_LEN


def encode_prompt(dataset: str, prompt: str, fill_char: str) -> np.ndarray:
    with (NANOGPT_ROOT / "data" / dataset / "meta.pkl").open("rb") as f:
        meta = pickle.load(f)
    stoi = meta["stoi"]
    fill_token = int(stoi[fill_char])
    tokens = np.full((SEQ_LEN,), fill_token, dtype=np.uint16)
    for i, ch in enumerate(prompt[:SEQ_LEN]):
        tokens[i] = int(stoi.get(ch, fill_token))
    return tokens


def main() -> None:
    parser = argparse.ArgumentParser(description="Export quality-exact INT8 stages for an explicit prompt.")
    parser.add_argument("--prompt", default="hello world")
    parser.add_argument("--fill-char", default=" ")
    parser.add_argument("--dataset", default="shakespeare_char")
    parser.add_argument("--ckpt", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt")
    parser.add_argument(
        "--int8-state",
        type=Path,
        default=NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference" / "int8_state_dict.pt",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "hello_world_quality_exact",
    )
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--eval-iters", type=int, default=200)
    parser.add_argument("--calib-iters", type=int, default=200)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--threshold-pct", type=float, default=10.0)
    parser.add_argument("--logit-scale", type=float, default=1024.0)
    parser.add_argument("--ln-bits", type=int, default=6)
    parser.add_argument("--softmax-bits", type=int, default=6)
    parser.add_argument("--gelu-bits", type=int, default=8)
    args = parser.parse_args()

    prompt_tokens = encode_prompt(args.dataset, args.prompt, args.fill_char)
    data_path = NANOGPT_ROOT / "data" / args.dataset / "val.bin"
    original = data_path.read_bytes()
    backup_path = args.out_dir / "original_val.bin"
    args.out_dir.mkdir(parents=True, exist_ok=True)
    backup_path.write_bytes(original)
    try:
        repeats = 64
        prompt_with_target = np.tile(prompt_tokens, repeats).astype(np.uint16)
        data_path.write_bytes(prompt_with_target.tobytes())
        export_args = SimpleNamespace(
            ckpt=args.ckpt,
            int8_state=args.int8_state,
            dataset=args.dataset,
            token_offset=0,
            out_dir=args.out_dir,
            device=args.device,
            eval_iters=args.eval_iters,
            calib_iters=args.calib_iters,
            batch_size=args.batch_size,
            seed=args.seed,
            threshold_pct=args.threshold_pct,
            logit_scale=args.logit_scale,
            ln_bits=args.ln_bits,
            softmax_bits=args.softmax_bits,
            gelu_bits=args.gelu_bits,
        )
        metrics = export_one_block(export_args)
        prompt_meta = {
            "prompt": args.prompt,
            "fill_char": args.fill_char,
            "tokens_first32": [int(v) for v in prompt_tokens[:32]],
        }
        (args.out_dir / "prompt_metadata.json").write_text(json.dumps(prompt_meta, indent=2), encoding="utf-8")
        print(json.dumps({"out_dir": str(args.out_dir), "argmax_first32": metrics["argmax_first32"]}, indent=2))
    finally:
        gc.collect()
        for attempt in range(10):
            try:
                data_path.write_bytes(original)
                break
            except OSError:
                if attempt == 9:
                    raise
                time.sleep(0.2)


if __name__ == "__main__":
    main()
