param(
    [string]$Prompt = "春风吹过",
    [int]$TrainIters = 500,
    [int]$MaxNewTokens = 120,
    [string]$Device = "cpu"
)

$ErrorActionPreference = "Stop"

$NanoRoot = Split-Path -Parent $PSScriptRoot
$Python = Join-Path $NanoRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $Python)) {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        throw "No usable Python found. Expected $Python or python in PATH."
    }
    $Python = $cmd.Source
}

$OutDir = Join-Path $NanoRoot "out-zh-char"
$ReportDir = Join-Path $NanoRoot "..\fpga\nano_gpt\generated\reports"
$LogDir = Join-Path $NanoRoot "..\fpga\nano_gpt\generated\run_logs"
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$Ts = Get-Date -Format "yyyyMMdd_HHmmss"
$PrepareLog = Join-Path $LogDir "zh_char_prepare_$Ts.log"
$TrainLog = Join-Path $LogDir "zh_char_train_$Ts.log"
$Fp32Log = Join-Path $LogDir "zh_char_fp32_sample_$Ts.log"
$Int8Log = Join-Path $LogDir "zh_char_int8_eval_$Ts.log"
$Report = Join-Path $ReportDir "zh_char_io_test_$Ts.md"

Push-Location $NanoRoot
try {
    & $Python "data\zh_char\prepare.py" *> $PrepareLog
    if (-not (Test-Path "data\zh_char\train.bin") -or -not (Test-Path "data\zh_char\val.bin")) {
        throw "prepare.py produced no train.bin/val.bin. Check Python runtime. Log: $PrepareLog"
    }

    if (-not (Test-Path (Join-Path $OutDir "ckpt.pt"))) {
        & $Python "train.py" "config\train_zh_char.py" "--device=$Device" "--max_iters=$TrainIters" "--compile=False" *> $TrainLog
    }
    if (-not (Test-Path (Join-Path $OutDir "ckpt.pt"))) {
        throw "training produced no checkpoint. Check Python runtime or train log: $TrainLog"
    }

    & $Python "sample.py" `
        "--out_dir=out-zh-char" `
        "--start=$Prompt" `
        "--num_samples=2" `
        "--max_new_tokens=$MaxNewTokens" `
        "--device=$Device" `
        "--dtype=float32" `
        "--compile=False" *> $Fp32Log
    if ((Get-Item -LiteralPath $Fp32Log).Length -eq 0) {
        throw "FP32 sample produced an empty log. Check sample log: $Fp32Log"
    }

    & $Python "tools\eval_int8_reference.py" `
        "--ckpt" "out-zh-char\ckpt.pt" `
        "--dataset" "zh_char" `
        "--device" $Device `
        "--batch-size" "8" `
        "--eval-iters" "20" `
        "--calib-iters" "20" `
        "--seed" "1337" `
        "--threshold-pct" "10.0" `
        "--mode" "w8a8_fake_quant" `
        "--out-dir" "out-zh-char\int8_reference" `
        "--fpga-out-dir" "..\fpga\nano_gpt\generated\zh_char_int8_reference" `
        "--prompt" $Prompt `
        "--max-new-tokens" $MaxNewTokens `
        "--temperature" "0.8" `
        "--top-k" "40" *> $Int8Log
    if (-not (Test-Path (Join-Path $OutDir "int8_reference\samples_fp32.txt")) -or
        -not (Test-Path (Join-Path $OutDir "int8_reference\samples_int8.txt"))) {
        throw "INT8 eval produced no sample files. Check INT8 log: $Int8Log"
    }

    $Fp32Text = Get-Content -LiteralPath $Fp32Log -Raw -Encoding UTF8
    $Int8Fp32Text = Get-Content -LiteralPath (Join-Path $OutDir "int8_reference\samples_fp32.txt") -Raw -Encoding UTF8
    $Int8Text = Get-Content -LiteralPath (Join-Path $OutDir "int8_reference\samples_int8.txt") -Raw -Encoding UTF8
    $Metrics = Get-Content -LiteralPath (Join-Path $OutDir "int8_reference\metrics.json") -Raw -Encoding UTF8

    $Lines = @(
        "# 中文输入输出测试 - $Ts",
        "",
        "- prompt: ``$Prompt``",
        "- dataset: ``zh_char``",
        "- checkpoint: ``$OutDir\ckpt.pt``",
        "- FP32 log: ``$Fp32Log``",
        "- INT8 log: ``$Int8Log``",
        "",
        "## FP32 sample.py 输出",
        "",
        '```text',
        $Fp32Text,
        '```',
        "",
        "## INT8 eval 同 prompt 的 FP32 输出",
        "",
        '```text',
        $Int8Fp32Text,
        '```',
        "",
        "## INT8 fake-quant 输出",
        "",
        '```text',
        $Int8Text,
        '```',
        "",
        "## metrics.json",
        "",
        '```json',
        $Metrics,
        '```'
    )
    $Lines -join "`n" | Set-Content -LiteralPath $Report -Encoding UTF8

    Write-Output "REPORT=$Report"
    Write-Output "FP32_LOG=$Fp32Log"
    Write-Output "INT8_LOG=$Int8Log"
}
finally {
    Pop-Location
}
