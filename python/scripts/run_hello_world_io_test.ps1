param(
    [string]$Prompt = "hello world",
    [int]$MaxNewTokens = 120,
    [string]$Device = "cpu"
)

$ErrorActionPreference = "Stop"

$NanoRoot = Split-Path -Parent $PSScriptRoot
$PythonCandidates = @(
    "C:\Users\Lenovo\.conda\envs\myenv\python.exe",
    "C:\Users\Lenovo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe",
    (Join-Path $NanoRoot ".venv\Scripts\python.exe"),
    "D:\Anaconda\python.exe"
)

$Python = $null
foreach ($Candidate in $PythonCandidates) {
    if (Test-Path $Candidate) {
        $Python = $Candidate
        break
    }
}
if ($null -eq $Python) {
    throw "No usable Python found."
}

function Invoke-PythonChecked {
    param(
        [string[]]$Arguments,
        [string]$StdoutPath,
        [string]$StderrPath
    )
    Remove-Item -LiteralPath $StdoutPath, $StderrPath -ErrorAction SilentlyContinue
    $Proc = Start-Process `
        -FilePath $Python `
        -ArgumentList $Arguments `
        -WorkingDirectory $NanoRoot `
        -NoNewWindow `
        -Wait `
        -PassThru `
        -RedirectStandardOutput $StdoutPath `
        -RedirectStandardError $StderrPath
    if ($Proc.ExitCode -ne 0) {
        $ErrText = Get-Content -LiteralPath $StderrPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        throw "Python command failed with exit code $($Proc.ExitCode). stderr: $ErrText"
    }
}

$OutDir = Join-Path $NanoRoot "out-shakespeare-char"
$ReportDir = Join-Path $NanoRoot "..\fpga\nano_gpt\generated\reports"
$LogDir = Join-Path $NanoRoot "..\fpga\nano_gpt\generated\run_logs"
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$Ts = Get-Date -Format "yyyyMMdd_HHmmss"
$Fp32Log = Join-Path $LogDir "hello_world_fp32_sample_$Ts.log"
$Fp32Err = Join-Path $LogDir "hello_world_fp32_sample_$Ts.err.log"
$Int8Log = Join-Path $LogDir "hello_world_int8_eval_$Ts.log"
$Int8Err = Join-Path $LogDir "hello_world_int8_eval_$Ts.err.log"
$Report = Join-Path $ReportDir "hello_world_io_test_$Ts.md"
$Int8Out = Join-Path $OutDir "hello_world_int8_reference_$Ts"
$FpgaOut = Join-Path $NanoRoot "..\fpga\nano_gpt\generated\hello_world_int8_reference_$Ts"
$PromptFile = Join-Path $NanoRoot "hello_world_prompt.txt"

Push-Location $NanoRoot
try {
    if (-not (Test-Path (Join-Path $OutDir "ckpt.pt"))) {
        throw "Missing checkpoint: $(Join-Path $OutDir 'ckpt.pt')"
    }

    Set-Content -LiteralPath $PromptFile -Value $Prompt -Encoding ASCII

    Invoke-PythonChecked `
        -Arguments @(
            "sample.py",
            "--out_dir=out-shakespeare-char",
            "--start=FILE:$PromptFile",
            "--num_samples=2",
            "--max_new_tokens=$MaxNewTokens",
            "--device=$Device",
            "--dtype=float32",
            "--compile=False"
        ) `
        -StdoutPath $Fp32Log `
        -StderrPath $Fp32Err
    if ((Get-Item -LiteralPath $Fp32Log).Length -eq 0) {
        throw "FP32 sample produced an empty log. Log: $Fp32Log"
    }

    Invoke-PythonChecked `
        -Arguments @(
            "tools\eval_int8_reference.py",
            "--ckpt", "out-shakespeare-char\ckpt.pt",
            "--dataset", "shakespeare_char",
            "--device", $Device,
            "--batch-size", "16",
            "--eval-iters", "50",
            "--calib-iters", "50",
            "--seed", "1337",
            "--threshold-pct", "10.0",
            "--mode", "w8a8_fake_quant",
            "--out-dir", $Int8Out,
            "--fpga-out-dir", $FpgaOut,
            "--prompt", "FILE:$PromptFile",
            "--max-new-tokens", "$MaxNewTokens",
            "--temperature", "0.8",
            "--top-k", "40"
        ) `
        -StdoutPath $Int8Log `
        -StderrPath $Int8Err
    if (-not (Test-Path (Join-Path $Int8Out "samples_fp32.txt")) -or
        -not (Test-Path (Join-Path $Int8Out "samples_int8.txt"))) {
        throw "INT8 eval produced no sample files. Log: $Int8Log"
    }

    $Fp32Text = Get-Content -LiteralPath $Fp32Log -Raw -Encoding UTF8
    $Int8Fp32Text = Get-Content -LiteralPath (Join-Path $Int8Out "samples_fp32.txt") -Raw -Encoding UTF8
    $Int8Text = Get-Content -LiteralPath (Join-Path $Int8Out "samples_int8.txt") -Raw -Encoding UTF8
    $Metrics = Get-Content -LiteralPath (Join-Path $Int8Out "metrics.json") -Raw -Encoding UTF8

    $Lines = @(
        "# hello world IO test - $Ts",
        "",
        "- prompt: ``$Prompt``",
        "- python: ``$Python``",
        "- dataset: ``shakespeare_char``",
        "- checkpoint: ``$OutDir\ckpt.pt``",
        "- FP32 log: ``$Fp32Log``",
        "- FP32 stderr: ``$Fp32Err``",
        "- INT8 log: ``$Int8Log``",
        "- INT8 stderr: ``$Int8Err``",
        "",
        "## FP32 sample.py output",
        "",
        '```text',
        $Fp32Text,
        '```',
        "",
        "## FP32 output from INT8 eval",
        "",
        '```text',
        $Int8Fp32Text,
        '```',
        "",
        "## INT8 fake-quant output",
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
    Write-Output "INT8_OUT=$Int8Out"
}
finally {
    Pop-Location
}
