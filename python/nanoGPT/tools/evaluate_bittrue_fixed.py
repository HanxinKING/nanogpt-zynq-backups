from __future__ import annotations

import argparse
import json
import math
import sys
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F


NANOGPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = NANOGPT_ROOT.parent
if str(NANOGPT_ROOT) not in sys.path:
    sys.path.insert(0, str(NANOGPT_ROOT))

from tools.simulate_bittrue_dynamic_int8 import BitTrueModel  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate fixed-scale coherent INT8 model.")
    parser.add_argument("--dataset", default="shakespeare_char")
    parser.add_argument("--blocks", type=int, default=8)
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--ckpt", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt")
    parser.add_argument(
        "--int8-state",
        type=Path,
        default=NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference" / "int8_state_dict.pt",
    )
    parser.add_argument(
        "--fixed-scales",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_alignment" / "bittrue_dynamic" / "summary.json",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_alignment" / "bittrue_fixed_eval",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    model = BitTrueModel(args.ckpt, args.int8_state, args.dataset)
    scale_document = json.loads(args.fixed_scales.read_text(encoding="utf-8"))
    fixed_scales = {
        name: float(value) for name, value in scale_document["first_step_scales"].items()
    }
    val = np.memmap(NANOGPT_ROOT / "data" / args.dataset / "val.bin", dtype=np.uint16, mode="r")
    generator = np.random.default_rng(args.seed)
    starts = generator.integers(0, len(val) - 257, size=args.blocks, endpoint=False)

    fp32_losses: list[float] = []
    int8_losses: list[float] = []
    mean_abs_errors: list[float] = []
    top1_matches = 0
    top1_total = 0
    started = time.perf_counter()
    model.fp32_model.eval()
    for block_index, start in enumerate(starts):
        tokens = np.asarray(val[int(start) : int(start) + 256], dtype=np.int64)
        targets = np.asarray(val[int(start) + 1 : int(start) + 257], dtype=np.int64)
        result = model.run_block(tokens, fixed_scales=fixed_scales)
        int8_logits = result["logits"].astype(np.float64)
        max_logits = np.max(int8_logits, axis=1, keepdims=True)
        logsumexp = np.log(np.exp(int8_logits - max_logits).sum(axis=1)) + max_logits[:, 0]
        int8_loss = float(np.mean(logsumexp - int8_logits[np.arange(256), targets]))

        with torch.no_grad():
            idx = torch.from_numpy(tokens).long().unsqueeze(0)
            fp32_logits, _ = model.fp32_model(idx, torch.from_numpy(targets).long().unsqueeze(0))
            fp32_loss = float(
                F.cross_entropy(fp32_logits.view(-1, fp32_logits.size(-1)), torch.from_numpy(targets).long()).item()
            )
            fp32_np = fp32_logits[0].detach().cpu().float().numpy().astype(np.float64)

        fp32_losses.append(fp32_loss)
        int8_losses.append(int8_loss)
        mean_abs_errors.append(float(np.mean(np.abs(fp32_np - int8_logits))))
        top1_matches += int(np.count_nonzero(np.argmax(fp32_np, axis=1) == np.argmax(int8_logits, axis=1)))
        top1_total += 256
        print(
            f"block={block_index} start={int(start)} fp32_loss={fp32_loss:.6f} "
            f"int8_loss={int8_loss:.6f} top1={top1_matches}/{top1_total}"
        )

    fp32_loss = float(np.mean(fp32_losses))
    int8_loss = float(np.mean(int8_losses))
    fp32_ppl = float(math.exp(fp32_loss))
    int8_ppl = float(math.exp(int8_loss))
    regression = (int8_ppl - fp32_ppl) / fp32_ppl * 100.0
    summary = {
        "kind": "bittrue_fixed_eval",
        "blocks": args.blocks,
        "seed": args.seed,
        "starts": [int(value) for value in starts],
        "fp32_loss": fp32_loss,
        "int8_loss": int8_loss,
        "fp32_ppl": fp32_ppl,
        "int8_ppl": int8_ppl,
        "ppl_regression_pct": float(regression),
        "logits_mean_abs_error": float(np.mean(mean_abs_errors)),
        "top1_match": int(top1_matches),
        "top1_total": int(top1_total),
        "top1_match_ratio": float(top1_matches / top1_total),
        "elapsed_s": float(time.perf_counter() - started),
        "pass_10pct": bool(np.isfinite(regression) and regression <= 10.0),
    }
    args.out_dir.mkdir(parents=True, exist_ok=True)
    out_path = args.out_dir / "metrics.json"
    out_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    if not summary["pass_10pct"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
