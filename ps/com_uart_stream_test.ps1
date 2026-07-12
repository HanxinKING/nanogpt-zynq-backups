[CmdletBinding()]
param(
    [string]$Port = "COM11",
    [string]$Line = "hello world",
    [int]$TimeoutSeconds = 900,
    [string]$RawLog = "",
    [int]$InterCharDelayMs = 5
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RawLog)) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $RawLog = Join-Path (Split-Path -Parent $PSScriptRoot) "build\uart_stream_$stamp.txt"
}
$eventLog = [IO.Path]::ChangeExtension($RawLog, ".events.txt")
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $RawLog) | Out-Null
Set-Content -LiteralPath $RawLog -Value "" -Encoding ascii
Set-Content -LiteralPath $eventLog -Value "" -Encoding ascii

$serial = [System.IO.Ports.SerialPort]::new(
    $Port,
    115200,
    [System.IO.Ports.Parity]::None,
    8,
    [System.IO.Ports.StopBits]::One
)
$serial.ReadTimeout = 200
$serial.WriteTimeout = 1000
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$watch = [Diagnostics.Stopwatch]::StartNew()
$response = ""

function Add-Chunk([string]$Chunk) {
    if ([string]::IsNullOrEmpty($Chunk)) { return }
    [IO.File]::AppendAllText($RawLog, $Chunk, [Text.Encoding]::ASCII)
    $escaped = $Chunk.Replace("`r", "<CR>").Replace("`n", "<LF>")
    Add-Content -LiteralPath $eventLog -Encoding ascii -Value `
        ("{0:F3}s RX {1}" -f $watch.Elapsed.TotalSeconds, $escaped)
    Write-Output $Chunk
}

try {
    $serial.Open()
    Start-Sleep -Milliseconds 200
    Add-Chunk $serial.ReadExisting()
    foreach ($ch in "$Line`r".ToCharArray()) {
        $serial.Write([string]$ch)
        if ($InterCharDelayMs -gt 0) {
            Start-Sleep -Milliseconds $InterCharDelayMs
        }
    }
    Add-Content -LiteralPath $eventLog -Encoding ascii -Value `
        ("{0:F3}s TX {1}<CR>" -f $watch.Elapsed.TotalSeconds, $Line)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 50
        $chunk = $serial.ReadExisting()
        if (-not [string]::IsNullOrEmpty($chunk)) {
            $response += $chunk
            Add-Chunk $chunk
            if ($response -match 'output: ' -and $response -match "`r?`n> $") { break }
        }
    }
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
    $watch.Stop()
}

if ($response -notmatch 'output: ' -or $response -notmatch "`r?`n> $") {
    throw "UART response timed out after $TimeoutSeconds seconds. raw=$RawLog events=$eventLog"
}

$summary = "COM_UART_STREAM_PASS port=$Port elapsed_s={0:F3} raw=$RawLog events=$eventLog" -f $watch.Elapsed.TotalSeconds
Add-Content -LiteralPath $eventLog -Encoding ascii -Value $summary
Write-Output $summary
