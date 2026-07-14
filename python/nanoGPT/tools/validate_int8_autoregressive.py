from __future__ import annotations

import argparse
import json
import pickle
import sys
from pathlib import Path
from typing import Any

import numpy as np
import torch


NANOGPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = NANOGPT_ROOT.parent
if str(NANOGPT_ROOT) not in sys.path:
    sys.path.insert(0, str(NANOGPT_ROOT))

from tools.eval_int8_reference import build_quantized_model, load_checkpoint_model, load_torch  # noqa: E402
from tools.export_quality_exact_hw_full import build_quality_model  # noqa: E402


def load_codec(dataset: str) -> tuple[dict[str, int], dict[int, str]]:
    meta_path = NANOGPT_ROOT / "data" / dataset / "meta.pkl"
    with meta_path.open("rb") as handle:
        meta = pickle.load(handle)
    return meta["stoi"], meta["itos"]


def load_activation_scales(state_path: Path) -> dict[str, float]:
    state = load_torch(state_path, map_location="cpu")
    scales: dict[str, float] = {}
    for name, module in state["modules"].items():
        value = module.get("activation_scale")
        if value is not None:
            scales[name] = float(value)
    if not scales:
        raise RuntimeError(f"No activation scales found in {state_path}")
    return scales


@torch.no_grad()
def greedy_trace(
    model: torch.nn.Module,
    prompt_tokens: list[int],
    itos: dict[int, str],
    new_tokens: int,
    block_size: int,
    device: str,
) -> dict[str, Any]:
    model.to(device)
    model.eval()
    tokens = list(prompt_tokens)
    generated: list[int] = []
    logits_trace: list[np.ndarray] = []
    for _ in range(new_tokens):
        context = tokens[-block_size:]
        idx = torch.tensor(context, dtype=torch.long, device=device).unsqueeze(0)
        logits, _loss = model(idx)
        last = logits[0, -1].detach().cpu().float().numpy()
        token = int(np.argmax(last))
        logits_trace.append(last)
        generated.append(token)
        tokens.append(token)
    logits_np = np.stack(logits_trace, axis=0)
    return {
        "generated_tokens": generated,
        "generated_text": "".join(itos[token] for token in generated),
        "full_text": "".join(itos[token] for token in tokens),
        "logits": logits_np,
    }


def summarize_trace(trace: dict[str, Any]) -> dict[str, Any]:
    logits = trace["logits"]
    return {
        "generated_tokens": trace["generated_tokens"],
        "generated_text": trace["generated_text"],
        "full_text": trace["full_text"],
        "logits_shape": list(logits.shape),
        "logits_first_step_first8": [float(value) for value in logits[0, :8]],
    }


def compare_logits(reference: np.ndarray, candidate: np.ndarray) -> dict[str, Any]:
    diff = np.abs(reference.astype(np.float64) - candidate.astype(np.float64))
    ref_top1 = np.argmax(reference, axis=1)
    cand_top1 = np.argmax(candidate, axis=1)
    return {
        "mean_abs_error": float(diff.mean()),
        "max_abs_error": float(diff.max()),
        "top1_match_count": int(np.count_nonzero(ref_top1 == cand_top1)),
        "top1_total": int(ref_top1.size),
        "top1_match_ratio": float(np.mean(ref_top1 == cand_top1)),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Deterministic FP32/INT8/quality greedy reference.")
    parser.add_argument("--prompt", default="hello world")
    parser.add_argument("--new-tokens", type=int, default=8)
    parser.add_argument("--dataset", default="shakespeare_char")
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--ckpt", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt")
    parser.add_argument(
        "--int8-state",
        type=Path,
        default=NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference" / "int8_state_dict.pt",
    )
    parser.add_argument(
        "--formal-metrics",
        type=Path,
        default=REPO_ROOT
        / "fpga"
        / "nano_gpt"
        / "generated"
        / "int8_quality_hw_exact_s256_d384_l6"
        / "metrics.json",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_alignment" / "golden",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.new_tokens <= 0:
        raise ValueError("--new-tokens must be positive")

    torch.manual_seed(1337)
    stoi, itos = load_codec(args.dataset)
    try:
        prompt_tokens = [int(stoi[ch]) for ch in args.prompt]
    except KeyError as exc:
        raise ValueError(f"Unsupported prompt character: {exc.args[0]!r}") from exc

    fp32_model, checkpoint = load_checkpoint_model(args.ckpt)
    activation_scales = load_activation_scales(args.int8_state)
    fake_quant_model, _report = build_quantized_model(
        fp32_model.cpu(), "w8a8_fake_quant", activation_scales
    )
    quality_model = build_quality_model(
        fp32_model.cpu(), activation_scales, ln_bits=6, softmax_bits=6, gelu_bits=8
    )
    block_size = int(checkpoint["model_args"]["block_size"])

    traces = {
        "fp32": greedy_trace(fp32_model, prompt_tokens, itos, args.new_tokens, block_size, args.device),
        "w8a8_fake_quant": greedy_trace(
            fake_quant_model, prompt_tokens, itos, args.new_tokens, block_size, args.device
        ),
        "quality_exact": greedy_trace(
            quality_model, prompt_tokens, itos, args.new_tokens, block_size, args.device
        ),
    }

    formal_metrics = json.loads(args.formal_metrics.read_text(encoding="utf-8"))
    summary = {
        "kind": "int8_autoregressive_golden",
        "prompt": args.prompt,
        "input_tokens": prompt_tokens,
        "new_tokens": args.new_tokens,
        "checkpoint": str(args.ckpt),
        "int8_state": str(args.int8_state),
        "activation_scale_count": len(activation_scales),
        "formal_quality_metrics": {
            "fp32_loss": formal_metrics["fp32"]["val_loss"],
            "fp32_ppl": formal_metrics["fp32"]["perplexity"],
            "quality_loss": formal_metrics["quality_exact"]["val_loss"],
            "quality_ppl": formal_metrics["quality_exact"]["perplexity"],
            "ppl_regression_pct": formal_metrics["ppl_regression_pct"],
            "pass": formal_metrics["pass"],
        },
        "traces": {name: summarize_trace(trace) for name, trace in traces.items()},
        "comparisons": {
            "fp32_vs_w8a8_fake_quant": compare_logits(
                traces["fp32"]["logits"], traces["w8a8_fake_quant"]["logits"]
            ),
            "fp32_vs_quality_exact": compare_logits(
                traces["fp32"]["logits"], traces["quality_exact"]["logits"]
            ),
            "w8a8_vs_quality_exact": compare_logits(
                traces["w8a8_fake_quant"]["logits"], traces["quality_exact"]["logits"]
            ),
        },
    }

    args.out_dir.mkdir(parents=True, exist_ok=True)
    for name, trace in traces.items():
        np.save(args.out_dir / f"{name}_logits.npy", trace["logits"])
    out_path = args.out_dir / "autoregressive_golden.json"
    out_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    print(f"GOLDEN_JSON={out_path}")


if __name__ == "__main__":
    main()
