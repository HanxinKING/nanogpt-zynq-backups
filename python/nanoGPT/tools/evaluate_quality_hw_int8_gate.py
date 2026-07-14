from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


NANOGPT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = NANOGPT_ROOT.parent


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def run_reference_eval(args: argparse.Namespace, out_dir: Path, fpga_out_dir: Path) -> None:
    cmd = [
        sys.executable,
        str(NANOGPT_ROOT / "tools" / "eval_int8_reference.py"),
        "--ckpt",
        str(args.ckpt),
        "--dataset",
        args.dataset,
        "--device",
        args.device,
        "--batch-size",
        str(args.batch_size),
        "--eval-iters",
        str(args.eval_iters),
        "--calib-iters",
        str(args.calib_iters),
        "--seed",
        str(args.seed),
        "--threshold-pct",
        str(args.threshold_pct),
        "--mode",
        "w8a8_fake_quant",
        "--out-dir",
        str(out_dir),
        "--fpga-out-dir",
        str(fpga_out_dir),
        "--max-new-tokens",
        str(args.max_new_tokens),
    ]
    subprocess.run(cmd, cwd=REPO_ROOT, check=True)


def copy_if_exists(src: Path, dst: Path) -> None:
    if src.exists():
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)


def write_gate_report(
    report_path: Path,
    metrics: dict[str, Any],
    out_dir: Path,
    fpga_out_dir: Path,
    pass_gate: bool,
) -> None:
    fp32_ppl = float(metrics["fp32"]["perplexity"])
    int8_ppl = float(metrics["int8"]["perplexity"])
    regression = float(metrics["ppl_regression_pct"])
    lines = [
        "# Quality HW INT8 PPL Gate 报告",
        "",
        "## 结论",
        "",
        f"- 结果：`{'PASS' if pass_gate else 'FAIL'}`",
        f"- FP32 perplexity：`{fp32_ppl:.6f}`",
        f"- Quality INT8 perplexity：`{int8_ppl:.6f}`",
        f"- ppl 回退：`{regression:.3f}%`",
        f"- 阈值：`<= {float(metrics['pass_threshold_pct']):.1f}%`",
        "",
        "## 当前质量语义",
        "",
        "- 权重：INT8 per-output-channel / per-row。",
        "- 激活：INT8 per-tensor fake quant。",
        "- MatMul：按 W8A8/INT32 累加语义建模。",
        "- LayerNorm / softmax / GELU：当前 gate 仍沿用软件参考中的高精度语义，用作质量上限和部署目标。",
        "",
        "## 对 FPGA 的含义",
        "",
        f"- 这个 gate 证明：只要 PL 端实现接近该质量语义，ppl 回退可以满足 `<={float(metrics['pass_threshold_pct']):.1f}%`。",
        "- 不能把当前 mean-only LN、argmax attention、identity FFN 的旧 RTL 当作该 gate 的等价实现。",
        "- 下一步 FPGA 只能接入与本 gate 匹配的 LN/softmax/GELU/scale；否则必须重新跑本 gate 并重新报告 ppl。",
        "",
        "## 产物",
        "",
        f"- 软件评估目录：`{out_dir.as_posix()}`",
        f"- FPGA 导出目录：`{fpga_out_dir.as_posix()}`",
        "",
    ]
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text("\n".join(lines), encoding="utf-8")


def write_quality_manifest(
    manifest_path: Path,
    metrics: dict[str, Any],
    source_int8_dir: Path,
    fpga_out_dir: Path,
) -> None:
    manifest = {
        "kind": "quality_hw_int8_gate",
        "status": "PASS" if metrics["pass"] else "FAIL",
        "checkpoint": metrics["checkpoint"],
        "dataset": metrics["dataset"],
        "fp32_perplexity": metrics["fp32"]["perplexity"],
        "quality_int8_perplexity": metrics["int8"]["perplexity"],
        "ppl_regression_pct": metrics["ppl_regression_pct"],
        "threshold_pct": metrics["pass_threshold_pct"],
        "source_int8_dir": str(source_int8_dir),
        "fpga_out_dir": str(fpga_out_dir),
        "hardware_contract": {
            "weights": "int8",
            "activations": "int8 fake-quant reference",
            "matmul": "int8 x int8 -> int32 accumulate",
            "layernorm": "must match quality reference closely enough to keep ppl gate passing",
            "attention": "must implement softmax-equivalent quality path, not argmax attention",
            "gelu": "must implement GELU LUT or equivalent quality path, not identity",
            "lm_head": "int8 weight matmul with logits/argmax output",
        },
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the quality gate before FPGA full deployment.")
    parser.add_argument("--ckpt", type=Path, default=NANOGPT_ROOT / "out-shakespeare-char" / "ckpt.pt")
    parser.add_argument("--dataset", default="shakespeare_char")
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--eval-iters", type=int, default=200)
    parser.add_argument("--calib-iters", type=int, default=200)
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--threshold-pct", type=float, default=10.0)
    parser.add_argument("--max-new-tokens", type=int, default=80)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=NANOGPT_ROOT / "out-shakespeare-char" / "quality_hw_int8_gate",
    )
    parser.add_argument(
        "--fpga-out-dir",
        type=Path,
        default=REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "int8_hw_ppl_pass_s256_d384_l6",
    )
    parser.add_argument(
        "--reuse-existing",
        action="store_true",
        help="Use an existing metrics.json if present instead of rerunning eval_int8_reference.py.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    metrics_path = args.out_dir / "metrics.json"
    if not args.reuse_existing or not metrics_path.exists():
        run_reference_eval(args, args.out_dir, args.fpga_out_dir)

    metrics = load_json(metrics_path)
    regression = float(metrics["ppl_regression_pct"])
    pass_gate = bool(math.isfinite(regression) and regression <= args.threshold_pct)
    metrics["pass_threshold_pct"] = float(args.threshold_pct)
    metrics["pass"] = pass_gate
    metrics["quality_hw_gate_note"] = (
        "PASS means the deploy target must preserve this quality semantic; "
        "the current simplified argmax-attention RTL is not equivalent."
    )
    metrics_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    args.fpga_out_dir.mkdir(parents=True, exist_ok=True)
    copy_if_exists(args.out_dir / "int8_state_dict.pt", args.fpga_out_dir / "int8_state_dict.pt")
    copy_if_exists(args.out_dir / "quant_config.json", args.fpga_out_dir / "quant_config.json")
    copy_if_exists(args.out_dir / "metrics.json", args.fpga_out_dir / "quality_metrics.json")
    copy_if_exists(args.out_dir / "metrics.md", args.fpga_out_dir / "quality_metrics.md")

    report_path = REPO_ROOT / "fpga" / "nano_gpt" / "generated" / "reports" / "quality_hw_int8_ppl_gate.md"
    write_gate_report(report_path, metrics, args.out_dir, args.fpga_out_dir, pass_gate)
    write_quality_manifest(args.fpga_out_dir / "quality_manifest.json", metrics, args.out_dir, args.fpga_out_dir)

    print(
        json.dumps(
            {
                "result": "PASS" if pass_gate else "FAIL",
                "fp32_perplexity": metrics["fp32"]["perplexity"],
                "quality_int8_perplexity": metrics["int8"]["perplexity"],
                "ppl_regression_pct": metrics["ppl_regression_pct"],
                "report": str(report_path),
                "fpga_out_dir": str(args.fpga_out_dir),
            },
            indent=2,
        )
    )
    if not pass_gate:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
