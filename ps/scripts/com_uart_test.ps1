[CmdletBinding()]
param(
    [string]$Port = "COM11",
    [string]$Line = "echo:hello world",
    [int]$TimeoutSeconds = 10
)

$ErrorActionPreference = "Stop"
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
$response = ""

try {
    $serial.Open()
    Start-Sleep -Milliseconds 200
    $response += $serial.ReadExisting()
    $serial.Write("$Line`r")
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 50
        $response += $serial.ReadExisting()
        if ($response -match 'output: ' -and $response -match '\r?\n> $') {
            break
        }
    }
} finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }
    $serial.Dispose()
}

Write-Output $response
if ($response -notmatch 'output: ' -or $response -notmatch '\r?\n> $') {
    throw "UART response timed out or was incomplete."
}
Write-Output "COM_UART_PASS port=$Port baud=115200 line=$Line"
