from __future__ import annotations

import argparse
import json
import pickle
import sys
from datetime import datetime
from pathlib import Path

import numpy as np
import torch


ROOT = Path(__file__).resolve().parents[1]
NANOGPT_ROOT = ROOT / "python" / "nanoGPT"
if str(NANOGPT_ROOT) not in sys.path:
    sys.path.insert(0, str(NANOGPT_ROOT))

from tools.hardware_friendly_decoder import select_topk_integer
from tools.simulate_bittrue_dynamic_int8 import BitTrueModel, SEQ_LEN


CKPT_FILE = NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt"
INT8_STATE_FILE = (
    NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference" / "int8_state_dict.pt"
)
META_FILE = NANOGPT_ROOT / "data" / "shakespeare_char" / "meta.pkl"
FIXED_SCALES_FILE = (
    ROOT / "reference" / "int8_alignment" / "bittrue_q30_everything_200" / "summary.json"
)
OUTPUT_DIR = Path(__file__).resolve().parent / "demo_outputs"

TOP_K = 3
REPEAT_PENALTY_Q8 = 0
REPEAT_WINDOW = 48
NO_REPEAT_NGRAM = 8
SEED = 1337
MAX_COMPARE_TOKENS = 3


def choose_token(scores: list[int], history: list[int], rng_state: int) -> tuple[int, int]:
    token, rng_state, _trace = select_topk_integer(
        scores,
        history,
        top_k=TOP_K,
        temperature_q8=96,
        repeat_penalty_q8=REPEAT_PENALTY_Q8,
        repeat_window=REPEAT_WINDOW,
        no_repeat_ngram=NO_REPEAT_NGRAM,
        rng_state=rng_state,
        deterministic=True,
    )
    return token, rng_state


def generate_github_fp32(
    model: torch.nn.Module, input_ids: list[int], max_new_tokens: int
) -> list[int]:
    """Follow nanoGPT model.generate: temperature, top-k, softmax, multinomial."""
    generated: list[int] = []
    idx = torch.tensor([input_ids], dtype=torch.long)
    torch.manual_seed(SEED)
    model.eval()
    with torch.no_grad():
        for step in range(max_new_tokens):
            idx_cond = idx if idx.size(1) <= model.config.block_size else idx[:, -model.config.block_size :]
            logits, _loss = model(idx_cond)
            logits = logits[:, -1, :] / 0.8
            values, _indices = torch.topk(logits, min(200, logits.size(-1)))
            logits[logits < values[:, [-1]]] = -float("Inf")
            probabilities = torch.softmax(logits, dim=-1)
            next_token = torch.multinomial(probabilities, num_samples=1)
            token = int(next_token.item())
            generated.append(token)
            idx = torch.cat((idx, next_token), dim=1)
            print(f"  GitHub-FP32 step {step + 1:03d}: token={token}")
    return generated


def generate_bittrue(
    model: BitTrueModel,
    input_ids: list[int],
    fixed_scales: dict[str, float],
    max_new_tokens: int,
) -> tuple[list[int], list[np.ndarray]]:
    history = list(input_ids)
    generated: list[int] = []
    logits_trace: list[np.ndarray] = []
    rng_state = SEED
    space_token = int(model.stoi[" "])

    for step in range(max_new_tokens):
        context = history[-SEQ_LEN:]
        tokens = np.full((SEQ_LEN,), space_token, dtype=np.int64)
        tokens[: len(context)] = np.asarray(context, dtype=np.int64)
        result = model.run_block(tokens, reference_dir=None, fixed_scales=fixed_scales)
        row = len(context) - 1
        token, rng_state = choose_token(
            result["selection_scores"][row].tolist(), history, rng_state
        )
        logits_trace.append(result["logits"][row].astype(np.float32))
        generated.append(token)
        history.append(token)
        print(f"  INT8-Q30 step {step + 1:03d}: token={token}")
    return generated, logits_trace


def read_prompt(argument: str | None) -> str:
    if argument is not None:
        return argument
    from tkinter import Tk, simpledialog

    dialog_root = Tk()
    dialog_root.withdraw()
    prompt = simpledialog.askstring(
        "nanoGPT Token 输入",
        "请输入英文 Prompt，例如 hello world 或 ROMEO:",
        parent=dialog_root,
    )
    dialog_root.destroy()
    return prompt or ""


def main() -> int:
    parser = argparse.ArgumentParser(description="FP32 与板卡对齐 Q30 INT8 输入输出比较")
    parser.add_argument("--prompt", default=None)
    parser.add_argument("--max-new-tokens", type=int, default=MAX_COMPARE_TOKENS)
    parser.add_argument("--skip-fp32", action="store_true")
    args = parser.parse_args()
    if args.max_new_tokens <= 0:
        raise ValueError("--max-new-tokens 必须大于 0")
    compare_tokens = min(args.max_new_tokens, MAX_COMPARE_TOKENS)
    if args.max_new_tokens > MAX_COMPARE_TOKENS:
        print(f"PC 对照最多生成 {MAX_COMPARE_TOKENS} 个字符，本次已自动限制。")

    required = [CKPT_FILE, INT8_STATE_FILE, META_FILE, FIXED_SCALES_FILE]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise FileNotFoundError("缺少严格 Q30 文件:\n" + "\n".join(missing))

    with META_FILE.open("rb") as handle:
        meta = pickle.load(handle)
    stoi: dict[str, int] = meta["stoi"]
    itos: dict[int, str] = meta["itos"]
    prompt = read_prompt(args.prompt)
    if not prompt:
        raise ValueError("Prompt 不能为空")
    unknown = sorted({character for character in prompt if character not in stoi})
    if unknown:
        raise ValueError(f"词表不包含这些字符: {unknown}")
    input_ids = [int(stoi[character]) for character in prompt]

    scale_document = json.loads(FIXED_SCALES_FILE.read_text(encoding="utf-8"))
    fixed_scales = {
        name: float(value) for name, value in scale_document["first_step_scales"].items()
    }
    bittrue_model = BitTrueModel(CKPT_FILE, INT8_STATE_FILE, "shakespeare_char")

    print("\n=== 输入 ===")
    print(f"文本: {prompt!r}")
    print(f"Token IDs: {input_ids}")
    print("\n=== 板卡对齐 INT8 Q30 ===")
    int8_generated, _int8_logits = generate_bittrue(
        bittrue_model, input_ids, fixed_scales, compare_tokens
    )
    int8_text = prompt + "".join(itos[token] for token in int8_generated)
    print(f"INT8 新 Token IDs: {int8_generated}")
    print(f"INT8 完整输出: {int8_text!r}")

    fp32_generated: list[int] | None = None
    fp32_text: str | None = None
    if not args.skip_fp32:
        print("\n=== GitHub 原始 FP32 采样 ===")
        fp32_generated = generate_github_fp32(
            bittrue_model.fp32_model, input_ids, compare_tokens
        )
        fp32_text = prompt + "".join(itos[token] for token in fp32_generated)
        print(f"GitHub FP32 新 Token IDs: {fp32_generated}")
        print(f"FP32 完整输出: {fp32_text!r}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    report_file = OUTPUT_DIR / "last_token_run.json"
    report_file.write_text(
        json.dumps(
            {
                "created_at": datetime.now().isoformat(timespec="seconds"),
                "reference_mode": "hardware_q30_bittrue",
                "int8_decoder": "deterministic_top1_with_top3_8gram_fallback",
                "fp32_decoder": "github_temperature_0.8_top_k_200_multinomial_seed_1337",
                "prompt": prompt,
                "requested_new_tokens": args.max_new_tokens,
                "compared_new_tokens": compare_tokens,
                "input_token_ids": input_ids,
                "int8_generated_token_ids": int8_generated,
                "int8_text": int8_text,
                "fp32_generated_token_ids": fp32_generated,
                "fp32_text": fp32_text,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"\n运行记录: {report_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
