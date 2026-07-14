param(
    [int]$MaxLayers = 2,
    [switch]$FastFinalOnly,
    [switch]$EnableLmHead,
    [switch]$LmFastTest,
    [switch]$BittrueStageTest,
    [ValidateRange(1, 256)]
    [int]$ActiveRows = 11,
    [ValidateRange(0, 255)]
    [int]$RowStart = 0,
    [ValidateRange(1, 6)]
    [int]$StageLimit = 5,
    [ValidateRange(0, 5)]
    [int]$BittrueLayer = 0,
    [switch]$FfnFullDiag,
    [string]$DumpDir = "",
    [string]$CoreFile = "rtl\hls_kernel_chain_axis_full_only_core.v",
    [string]$Tag = ""
)

$ErrorActionPreference = "Stop"

if ($MaxLayers -lt 1 -or $MaxLayers -gt 6) {
    throw "MaxLayers must be in 1..6, got $MaxLayers"
}

$fpga = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repo = (Resolve-Path (Join-Path $fpga "..")).Path
$hlsGenerated = Join-Path $repo "hls\generated"
$modelsim = "D:\modelsim2020.4\win64"
$vlib = Join-Path $modelsim "vlib.exe"
$vlog = Join-Path $modelsim "vlog.exe"
$vsim = Join-Path $modelsim "vsim.exe"
$env:PATH = "$modelsim;" + $env:PATH
$env:MGLS_LICENSE_FILE = "D:\modelsim2020.4\LICENSE.TXT"
$env:LM_LICENSE_FILE = "D:\modelsim2020.4\LICENSE.TXT"

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
if ([string]::IsNullOrWhiteSpace($Tag)) {
    if ($LmFastTest) {
        $Tag = "lm_fast_pl_$stamp"
    } elseif ($BittrueStageTest) {
        $Tag = "bittrue_pl_layer${BittrueLayer}_stage${StageLimit}_start${RowStart}_rows${ActiveRows}_$stamp"
    } else {
        $Tag = "full_model_${MaxLayers}layer_gateA_$stamp"
    }
}
$logDir = Join-Path $fpga "generated\run_logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$transcript = Join-Path $logDir "$Tag.transcript"
$transcriptForModelsim = $transcript.Replace('\', '/')
$doneFile = Join-Path $logDir "$Tag.done.txt"

Push-Location $fpga
try {
    if (-not (Test-Path ".\layernorm_kernel_seed_lut_ROM_AUTO_1R.dat")) {
        Copy-Item (Join-Path $hlsGenerated "layernorm_kernel\sol1\impl\ip\hdl\verilog\layernorm_kernel_seed_lut_ROM_AUTO_1R.dat") ".\layernorm_kernel_seed_lut_ROM_AUTO_1R.dat" -Force
    }

    $hlsFiles = @()
    $hlsFiles += Get-ChildItem (Join-Path $hlsGenerated "tiled_matmul\sol1\impl\ip\hdl\verilog\*.v") | ForEach-Object { $_.FullName }
    $hlsFiles += Get-ChildItem (Join-Path $hlsGenerated "mha_kernel\sol1\impl\ip\hdl\verilog\*.v") | ForEach-Object { $_.FullName }
    $hlsFiles += Get-ChildItem (Join-Path $hlsGenerated "layernorm_kernel\sol1\impl\ip\hdl\verilog\*.v") | ForEach-Object { $_.FullName }
    $hlsFiles += Get-ChildItem (Join-Path $hlsGenerated "gelu_embed_kernel\sol1\impl\ip\hdl\verilog\*.v") | ForEach-Object { $_.FullName }

    $work = if ($LmFastTest) { "work_lm_fast_pl" } elseif ($BittrueStageTest) { "work_bittrue_pl_stage" } else { "work_full_model_multilayer_real_hls_${MaxLayers}" }
    if (Test-Path $work) {
        $resolvedWork = (Resolve-Path $work).Path
        if (-not $resolvedWork.StartsWith($fpga, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove simulation work directory outside FPGA root: $resolvedWork"
        }
        Remove-Item -LiteralPath $work -Recurse -Force
    }
    $vlibOut = Join-Path $logDir "$Tag.vlib.stdout.txt"
    $vlibErr = Join-Path $logDir "$Tag.vlib.stderr.txt"
    $proc = Start-Process -FilePath $vlib -ArgumentList @($work) -WorkingDirectory $fpga `
        -NoNewWindow -Wait -PassThru -RedirectStandardOutput $vlibOut -RedirectStandardError $vlibErr
    if ($proc.ExitCode -ne 0) {
        Get-Content $vlibOut -ErrorAction SilentlyContinue
        Get-Content $vlibErr -ErrorAction SilentlyContinue
        exit $proc.ExitCode
    }

    $vlogArgs = @(
        "-work", $work, "-sv", "+define+FULL_ONLY_SYNTH",
        "rtl\hls_kernel_chain_axis_top.v",
        $CoreFile,
        "rtl\hls_kernel_chain_axis_wrapper.v",
        "rtl\tiled_matmul_hls_wrapper.v",
        "rtl\mha_hls_wrapper.v",
        "rtl\layernorm_hls_wrapper.v",
        "rtl\gelu_embed_hls_wrapper.v",
        "rtl\pl_uart_ps_bridge.v"
    )
    if ($FfnFullDiag) { $vlogArgs += "+define+FFN_FULL_DIAG" }
    $vlogArgs += $hlsFiles
    $vlogArgs += "tb\tb_hls_kernel_chain_axis_full_model_multilayer.sv"
    $vlogOut = Join-Path $logDir "$Tag.vlog.stdout.txt"
    $vlogErr = Join-Path $logDir "$Tag.vlog.stderr.txt"
    $proc = Start-Process -FilePath $vlog -ArgumentList $vlogArgs -WorkingDirectory $fpga `
        -NoNewWindow -Wait -PassThru -RedirectStandardOutput $vlogOut -RedirectStandardError $vlogErr
    if ($proc.ExitCode -ne 0) {
        Get-Content $vlogOut -ErrorAction SilentlyContinue
        Get-Content $vlogErr -ErrorAction SilentlyContinue
        exit $proc.ExitCode
    }

    $doFile = Join-Path $logDir "$Tag.do"
    @(
        "transcript file `"$transcriptForModelsim`"",
        "run -all",
        "quit -f"
    ) | Set-Content -LiteralPath $doFile -Encoding ascii
    $plusArgs = @("+MAX_LAYERS=$MaxLayers")
    if ($FastFinalOnly) { $plusArgs += "+FAST_FINAL_ONLY=1" }
    if ($EnableLmHead) { $plusArgs += "+ENABLE_LM_HEAD=1" }
    if ($LmFastTest) { $plusArgs += "+LM_FAST_TEST=1" }
    if ($BittrueStageTest) {
        $plusArgs += "+BITTRUE_STAGE_TEST=1"
        $plusArgs += "+ACTIVE_ROWS=$ActiveRows"
        $plusArgs += "+ROW_START=$RowStart"
        $plusArgs += "+STAGE_LIMIT=$StageLimit"
        $plusArgs += "+BITTRUE_LAYER=$BittrueLayer"
    }
    if ($FfnFullDiag) {
        if ([string]::IsNullOrWhiteSpace($DumpDir)) {
            $DumpDir = Join-Path $fpga "generated\sim_dumps\$Tag"
        }
        New-Item -ItemType Directory -Force -Path $DumpDir | Out-Null
        $plusArgs += "+DUMP_DIR=$($DumpDir.Replace('\', '/'))"
    }
    $vsimArgs = @("-c", "$work.tb_hls_kernel_chain_axis_full_model_multilayer")
    $vsimArgs += $plusArgs
    $vsimArgs += @("-do", $doFile)
    $vsimOut = Join-Path $logDir "$Tag.vsim.stdout.txt"
    $vsimErr = Join-Path $logDir "$Tag.vsim.stderr.txt"
    $proc = Start-Process -FilePath $vsim -ArgumentList $vsimArgs -WorkingDirectory $fpga `
        -NoNewWindow -Wait -PassThru -RedirectStandardOutput $vsimOut -RedirectStandardError $vsimErr
    $simExit = $proc.ExitCode
    if ($simExit -eq 0 -and (Test-Path $transcript)) {
        $semanticFailure = Select-String -LiteralPath $transcript `
            -Pattern 'TB_[A-Z0-9_ ]*FAIL|mismatch=[1-9][0-9]*' -Quiet
        if ($semanticFailure) {
            Write-Host "SIM_SEMANTIC_FAIL transcript=$transcript"
            $simExit = 1
        }
    }
    Get-Content $vsimOut -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
    Get-Content $vsimErr -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
    "exit=$simExit`nmax_layers=$MaxLayers`nfast_final_only=$($FastFinalOnly.IsPresent)`nenable_lm_head=$($EnableLmHead.IsPresent)`nbittrue_stage_test=$($BittrueStageTest.IsPresent)`nbittrue_layer=$BittrueLayer`nrow_start=$RowStart`nactive_rows=$ActiveRows`nstage_limit=$StageLimit`ntag=$Tag`ntranscript=$transcript" | Set-Content -LiteralPath $doneFile -Encoding ascii
    exit $simExit
} finally {
    Pop-Location
}
