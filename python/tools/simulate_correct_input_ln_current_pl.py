from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import numpy as np


NANOGPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = NANOGPT_ROOT.parent
GEN = REPO_ROOT / "fpga" / "nano_gpt" / "generated"
if str(NANOGPT_ROOT) not in sys.path:
    sys.path.insert(0, str(NANOGPT_ROOT))

from tools.analyze_fixed_layernorm import fixed_layernorm_i8  # noqa: E402
from tools.eval_int8_reference import load_checkpoint_model  # noqa: E402
from tools.validate_int8_autoregressive import load_activation_scales  # noqa: E402


def load_current_simulator():
    path = GEN / "simulate_current_ps_pl_prompt.py"
    spec = importlib.util.spec_from_file_location("current_pl_sim", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> None:
    current = load_current_simulator()
    prompt = "hello world"
    tokens = [current.STOI[ch] for ch in prompt]
    reference_dir = GEN / "int8_alignment" / "reference"
    x = np.frombuffer(
        (reference_dir / "layer_00_input_dynamic_i8.bin").read_bytes(), dtype=np.int8
    ).reshape(current.SEQ, current.D_MODEL).copy()

    model, _checkpoint = load_checkpoint_model(
        NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt"
    )
    activation_scales = load_activation_scales(
        NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference" / "int8_state_dict.pt"
    )
    weights = np.frombuffer((current.IMAGE / "weights.bin").read_bytes(), dtype=np.int8)
    exp_lut = current.load_exp_lut()
    gelu_lut = current.load_gelu_lut_from_exports()

    out_dir = GEN / "int8_alignment" / "hybrid_current_pl"
    out_dir.mkdir(parents=True, exist_ok=True)
    for layer in range(6):
        block = model.transformer.h[layer]
        wbase = layer * current.LAYER_STRIDE
        ln1 = fixed_layernorm_i8(
            x,
            block.ln_1.weight.detach().cpu().numpy(),
            activation_scales[f"transformer.h.{layer}.attn.c_attn"],
        )
        wq = weights[
            wbase + current.OFF_WQ : wbase + current.OFF_WQ + current.D_MODEL * current.D_MODEL
        ].reshape(current.D_MODEL, current.D_MODEL)
        wk = weights[
            wbase + current.OFF_WK : wbase + current.OFF_WK + current.D_MODEL * current.D_MODEL
        ].reshape(current.D_MODEL, current.D_MODEL)
        wv = weights[
            wbase + current.OFF_WV : wbase + current.OFF_WV + current.D_MODEL * current.D_MODEL
        ].reshape(current.D_MODEL, current.D_MODEL)
        wo = weights[
            wbase + current.OFF_WO : wbase + current.OFF_WO + current.D_MODEL * current.D_MODEL
        ].reshape(current.D_MODEL, current.D_MODEL)
        q = current.linear(ln1, wq, current.Q_SHIFTS[layer])
        k = current.linear(ln1, wk, current.K_SHIFTS[layer])
        v = current.linear(ln1, wv, current.V_SHIFTS[layer])
        attn = current.attention(q, k, v, layer, exp_lut)
        proj = current.linear(attn, wo, current.ATTN_SHIFTS[layer])
        res1 = current.res1(x, proj)
        ln2 = fixed_layernorm_i8(
            res1,
            block.ln_2.weight.detach().cpu().numpy(),
            activation_scales[f"transformer.h.{layer}.mlp.c_fc"],
        )
        w1 = weights[
            wbase + current.OFF_W1 : wbase + current.OFF_W1 + current.D_MODEL * current.MLP
        ].reshape(current.D_MODEL, current.MLP)
        w2 = weights[
            wbase + current.OFF_W2 : wbase + current.OFF_W2 + current.MLP * current.D_MODEL
        ].reshape(current.MLP, current.D_MODEL)
        mid = current.linear(ln2, w1, current.FFN_MID_SHIFTS[layer])
        mid_gelu = gelu_lut[mid.astype(np.int16) & 0xFF].astype(np.int8)
        ffn = current.linear(mid_gelu, w2, current.FFN_SHIFTS[layer])
        x = current.clamp_i8(res1.astype(np.int32) + ffn.astype(np.int32))
        (out_dir / f"layer_{layer:02d}_ln1.bin").write_bytes(ln1.tobytes())
        (out_dir / f"layer_{layer:02d}_final.bin").write_bytes(x.tobytes())
        print(f"layer={layer} first16={x.reshape(-1)[:16].tobytes().hex()}")

    lm_w = weights[
        current.OFF_LM : current.OFF_LM + current.D_MODEL * current.VOCAB
    ].reshape(current.D_MODEL, current.VOCAB)
    all_argmax = current.ps_lm_head(x, lm_w, len(tokens))
    token = int(all_argmax[len(tokens) - 1])
    summary = {
        "prompt": prompt,
        "last_prompt_row": len(tokens) - 1,
        "argmax_token": token,
        "decoded": current.ITOS[token],
        "all_prompt_row_argmax": all_argmax,
    }
    path = out_dir / "summary.json"
    path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
