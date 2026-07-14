from __future__ import annotations

import argparse
import hashlib
import json
import math
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

from tools.eval_int8_reference import load_checkpoint_model, load_torch  # noqa: E402


D_MODEL = 384
MLP_DIM = 1536
VOCAB_SIZE = 65
N_LAYER = 6
Q30 = 1 << 30
Q24 = 1 << 24


def q30(values: np.ndarray) -> np.ndarray:
    return np.clip(np.rint(values.astype(np.float64) * Q30), 0, (1 << 31) - 1).astype(np.uint32)


def write_u32_mem(path: Path, values: np.ndarray) -> None:
    path.write_text("".join(f"{int(value) & 0xFFFFFFFF:08x}\n" for value in values.reshape(-1)), encoding="ascii")


def write_i32_mem(path: Path, values: np.ndarray) -> None:
    path.write_text("".join(f"{int(value) & 0xFFFFFFFF:08x}\n" for value in values.reshape(-1)), encoding="ascii")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export coherent fixed-scale INT8 hardware parameters.")
    parser.add_argument("--ckpt", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt")
    parser.add_argument(
        "--int8-state",
        type=Path,
        default=NANOGPT_ROOT / "out-shakespeare-char" / "int8_reference" / "int8_state_dict.pt",
    )
    parser.add_argument(
        "--scale-json",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_alignment" / "bittrue_dynamic" / "summary.json",
    )
    parser.add_argument(
        "--existing-weights",
        type=Path,
        default=REPO_ROOT
        / "fpga"
        / "nano_gpt"
        / "generated"
        / "rtl_lut_board_ddr_image_20260525_195055"
        / "weights.bin",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_alignment" / "hardware_params",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    state = load_torch(args.int8_state, map_location="cpu")
    modules = state["modules"]
    fp32_model, checkpoint = load_checkpoint_model(args.ckpt)
    scale_doc = json.loads(args.scale_json.read_text(encoding="utf-8"))
    stage_scales = {name: float(value) for name, value in scale_doc["first_step_scales"].items()}
    gelu_scale = float(
        np.median(
            [
                float(module["activation_scale"])
                for name, module in modules.items()
                if "mlp.c_fc" in name and module.get("activation_scale") is not None
            ]
        )
    )

    weights = bytearray()
    parameter_sets: dict[str, list[np.ndarray]] = {
        "q_mult_q30": [],
        "k_mult_q30": [],
        "v_mult_q30": [],
        "attn_proj_mult_q30": [],
        "ffn_mid_mult_q30": [],
        "ffn_mult_q30": [],
    }
    ln_coefficients: list[np.ndarray] = []
    attention_score_q16: list[int] = []
    attention_out_mult_q30: list[int] = []
    residuals: dict[str, dict[str, float | int]] = {}

    for layer in range(N_LAYER):
        prefix = f"layer_{layer:02d}"
        c_attn = modules[f"transformer.h.{layer}.attn.c_attn"]
        qkv_q = c_attn["qweight"].detach().cpu().numpy().astype(np.int8)
        qkv_wscale = c_attn["weight_scale"].detach().cpu().numpy().astype(np.float64)
        qkv_act = float(c_attn["activation_scale"])
        q_out, k_out, v_out = (
            stage_scales[f"{prefix}.q"],
            stage_scales[f"{prefix}.k"],
            stage_scales[f"{prefix}.v"],
        )
        parameter_sets["q_mult_q30"].append(q30(qkv_act * qkv_wscale[:D_MODEL] / q_out))
        parameter_sets["k_mult_q30"].append(q30(qkv_act * qkv_wscale[D_MODEL : 2 * D_MODEL] / k_out))
        parameter_sets["v_mult_q30"].append(q30(qkv_act * qkv_wscale[2 * D_MODEL :] / v_out))

        attn_proj = modules[f"transformer.h.{layer}.attn.c_proj"]
        attn_proj_q = attn_proj["qweight"].detach().cpu().numpy().astype(np.int8)
        attn_proj_wscale = attn_proj["weight_scale"].detach().cpu().numpy().astype(np.float64)
        attn_proj_act = float(attn_proj["activation_scale"])
        attn_proj_out = stage_scales[f"{prefix}.attn_proj"]
        parameter_sets["attn_proj_mult_q30"].append(
            q30(attn_proj_act * attn_proj_wscale / attn_proj_out)
        )

        fc = modules[f"transformer.h.{layer}.mlp.c_fc"]
        fc_q = fc["qweight"].detach().cpu().numpy().astype(np.int8)
        fc_wscale = fc["weight_scale"].detach().cpu().numpy().astype(np.float64)
        fc_act = float(fc["activation_scale"])
        parameter_sets["ffn_mid_mult_q30"].append(q30(fc_act * fc_wscale / gelu_scale))

        ffn = modules[f"transformer.h.{layer}.mlp.c_proj"]
        ffn_q = ffn["qweight"].detach().cpu().numpy().astype(np.int8)
        ffn_wscale = ffn["weight_scale"].detach().cpu().numpy().astype(np.float64)
        ffn_out = stage_scales[f"{prefix}.ffn"]
        parameter_sets["ffn_mult_q30"].append(q30(gelu_scale * ffn_wscale / ffn_out))

        for matrix in (
            qkv_q[:D_MODEL],
            qkv_q[D_MODEL : 2 * D_MODEL],
            qkv_q[2 * D_MODEL :],
            attn_proj_q,
            fc_q,
            ffn_q,
        ):
            weights.extend(matrix.T.copy(order="C").tobytes())

        block = fp32_model.transformer.h[layer]
        ln1_gamma = block.ln_1.weight.detach().cpu().numpy().astype(np.float64)
        ln2_gamma = block.ln_2.weight.detach().cpu().numpy().astype(np.float64)
        ln_coefficients.append(np.rint(ln1_gamma / qkv_act * Q24).astype(np.int32))
        ln_coefficients.append(np.rint(ln2_gamma / fc_act * Q24).astype(np.int32))

        attention_score_q16.append(int(round(2.0 * q_out * k_out * (1 << 16))))
        attention_out_mult_q30.append(int(q30(np.asarray([v_out / attn_proj_act]))[0]))

        input_scale = stage_scales["layer_00.input"] if layer == 0 else stage_scales[f"layer_{layer-1:02d}.final"]
        res1_scale = stage_scales[f"{prefix}.res1"]
        final_scale = stage_scales[f"{prefix}.final"]
        residuals[prefix] = {
            "input_scale": input_scale,
            "attn_proj_scale": attn_proj_out,
            "res1_scale": res1_scale,
            "res1_input_mult_q30": int(q30(np.asarray([input_scale / res1_scale]))[0]),
            "res1_proj_mult_q30": int(q30(np.asarray([attn_proj_out / res1_scale]))[0]),
            "ffn_scale": ffn_out,
            "final_scale": final_scale,
            "final_res1_mult_q30": int(q30(np.asarray([res1_scale / final_scale]))[0]),
            "final_ffn_mult_q30": int(q30(np.asarray([ffn_out / final_scale]))[0]),
        }

    lm = modules["lm_head"]
    lm_q = lm["qweight"].detach().cpu().numpy().astype(np.int8)
    weights.extend(lm_q.T.copy(order="C").tobytes())
    lm_wscale = lm["weight_scale"].detach().cpu().numpy().astype(np.float64)
    lm_scale_ratio_q30 = q30(lm_wscale / float(lm_wscale.max()))
    lm_act = float(lm["activation_scale"])
    ln_f_gamma = fp32_model.transformer.ln_f.weight.detach().cpu().numpy().astype(np.float64)
    ln_coefficients.append(np.rint(ln_f_gamma / lm_act * Q24).astype(np.int32))

    weights_path = args.out_dir / "weights.bin"
    weights_path.write_bytes(bytes(weights))
    for name, chunks in parameter_sets.items():
        values = np.concatenate(chunks)
        write_u32_mem(args.out_dir / f"{name}.mem", values)
        (args.out_dir / f"{name}.bin").write_bytes(values.astype("<u4").tobytes())
    ln_values = np.concatenate(ln_coefficients)
    write_i32_mem(args.out_dir / "layernorm_coeff_q24.mem", ln_values)
    (args.out_dir / "layernorm_coeff_q24.bin").write_bytes(ln_values.astype("<i4").tobytes())
    write_u32_mem(args.out_dir / "lm_head_scale_ratio_q30.mem", lm_scale_ratio_q30)
    (args.out_dir / "lm_head_scale_ratio_q30.bin").write_bytes(
        lm_scale_ratio_q30.astype("<u4").tobytes()
    )
    write_u32_mem(args.out_dir / "attention_score_q16.mem", np.asarray(attention_score_q16, dtype=np.uint32))
    write_u32_mem(
        args.out_dir / "attention_out_mult_q30.mem", np.asarray(attention_out_mult_q30, dtype=np.uint32)
    )

    xs = torch.arange(-128, 128, dtype=torch.float32) * gelu_scale
    gelu_lut_signed = torch.clamp(torch.round(F.gelu(xs) / gelu_scale), -128, 127).to(torch.int8).numpy()
    gelu_lut = np.empty((256,), dtype=np.int8)
    signed_inputs = np.arange(-128, 128, dtype=np.int16)
    gelu_lut[signed_inputs.astype(np.uint8)] = gelu_lut_signed
    (args.out_dir / "gelu_global_i8.bin").write_bytes(gelu_lut.tobytes())
    (args.out_dir / "gelu_global_i8.mem").write_text(
        "".join(f"{int(value) & 0xFF:02x}\n" for value in gelu_lut), encoding="ascii"
    )

    existing_same = args.existing_weights.exists() and args.existing_weights.read_bytes() == weights_path.read_bytes()
    manifest = {
        "kind": "bittrue_fixed_hardware_params",
        "model_args": checkpoint["model_args"],
        "gelu_scale": gelu_scale,
        "stage_scales": stage_scales,
        "attention_score_q16": attention_score_q16,
        "attention_out_mult_q30": attention_out_mult_q30,
        "residuals": residuals,
        "layouts": {
            "q_k_v_attn_proj": "6 layers x 384 u32 Q30",
            "ffn_mid": "6 layers x 1536 u32 Q30",
            "ffn": "6 layers x 384 u32 Q30",
            "layernorm": "13 stages x 384 i32 Q24 in layer0_ln1, layer0_ln2, ..., ln_f order",
            "gelu": "256 i8 entries indexed by the two's-complement uint8 bit pattern of the INT8 input",
            "weights": "six layer strides of WQ/WK/WV/WO/W1/W2 followed by transposed LM head",
        },
        "weights_bytes": len(weights),
        "weights_sha256": sha256(weights_path),
        "existing_weights_same": existing_same,
        "existing_weights_sha256": sha256(args.existing_weights) if args.existing_weights.exists() else None,
    }
    manifest_path = args.out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    def c_array(name: str, values: list[int]) -> str:
        body = ", ".join(f"0x{value & 0xFFFFFFFF:08x}u" for value in values)
        return f"static const uint32_t {name}[6] = {{{body}}};"

    header_lines = [
        "#ifndef NANO_GPT_PS_BITTRUE_PARAMS_H",
        "#define NANO_GPT_PS_BITTRUE_PARAMS_H",
        "",
        "#define BITTRUE_LN_COEFF_BASE 0x13200000u",
        "#define BITTRUE_LM_SCALE_BASE 0x13205000u",
        "#define BITTRUE_LN_STAGE_BYTES (384u * 4u)",
        "#define BITTRUE_LN_FINAL_STAGE 12u",
        "",
        c_array(
            "g_res1_input_mult_q30",
            [int(residuals[f"layer_{layer:02d}"]["res1_input_mult_q30"]) for layer in range(6)],
        ),
        c_array(
            "g_res1_proj_mult_q30",
            [int(residuals[f"layer_{layer:02d}"]["res1_proj_mult_q30"]) for layer in range(6)],
        ),
        c_array(
            "g_final_res1_mult_q30",
            [int(residuals[f"layer_{layer:02d}"]["final_res1_mult_q30"]) for layer in range(6)],
        ),
        c_array(
            "g_final_ffn_mult_q30",
            [int(residuals[f"layer_{layer:02d}"]["final_ffn_mult_q30"]) for layer in range(6)],
        ),
        "",
        "#endif",
        "",
    ]
    (args.out_dir / "ps_bittrue_params.h").write_text("\n".join(header_lines), encoding="ascii")
    print(json.dumps(manifest, indent=2))
    if len(weights) != 10_641_792:
        raise SystemExit(f"Unexpected weights size: {len(weights)}")


if __name__ == "__main__":
    main()
