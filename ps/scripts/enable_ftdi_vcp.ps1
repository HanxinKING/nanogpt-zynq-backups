[CmdletBinding()]
param(
    [string]$BoardSerial = "25SG051",
    [switch]$Elevated
)

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$scriptDir = Split-Path -Parent $PSCommandPath
$logDir = Resolve-Path (Join-Path $scriptDir "..\..\..\generated\int8_alignment\run_logs")
$log = Join-Path $logDir "enable_ftdi_vcp.log"

if (-not (Test-IsAdministrator)) {
    if ($Elevated) {
        throw "Administrator token was requested but not granted."
    }
    $argLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -BoardSerial "{1}" -Elevated' -f $PSCommandPath,$BoardSerial
    $process = Start-Process -FilePath "powershell.exe" -ArgumentList $argLine -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
}

$parentPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USB\VID_0403&PID_6010\$BoardSerial"
if (-not (Test-Path -LiteralPath $parentPath)) {
    throw "FT2232H parent $BoardSerial is not present."
}

$containerId = [string](Get-ItemProperty -LiteralPath $parentPath).ContainerID
$interfaceRoot = "HKLM:\SYSTEM\CurrentControlSet\Enum\USB\VID_0403&PID_6010&MI_01"
$interface = Get-ChildItem -LiteralPath $interfaceRoot | Where-Object {
    [string](Get-ItemProperty -LiteralPath $_.PSPath).ContainerID -eq $containerId
} | Select-Object -First 1

if (-not $interface) {
    throw "FT2232H channel B was not found for container $containerId."
}

$instanceId = "USB\VID_0403&PID_6010&MI_01\$($interface.PSChildName)"
$deviceParameters = Join-Path $interface.PSPath "Device Parameters"
$oldConfigData = [uint32](Get-ItemProperty -LiteralPath $deviceParameters).ConfigData
$newConfigData = $oldConfigData -bor 0x4
New-ItemProperty -LiteralPath $deviceParameters -Name ConfigData -PropertyType DWord -Value $newConfigData -Force | Out-Null
New-ItemProperty -LiteralPath $deviceParameters -Name LoadVCP -PropertyType DWord -Value 1 -Force | Out-Null
$parameters = Get-ItemProperty -LiteralPath $deviceParameters
$loadVcp = [uint32]$parameters.LoadVCP
$configData = [uint32]$parameters.ConfigData
if ($loadVcp -ne 1 -or ($configData -band 0x4) -eq 0) {
    throw "VCP registry verification failed."
}

@(
    "timestamp=$(Get-Date -Format o)"
    "instance=$instanceId"
    "container=$containerId"
    "LoadVCP=$loadVcp"
    "ConfigDataOld=0x$($oldConfigData.ToString('x8'))"
    "ConfigDataNew=0x$($configData.ToString('x8'))"
) | Set-Content -LiteralPath $log -Encoding ASCII

$pnputil = Join-Path $env:WINDIR "System32\pnputil.exe"
$restartOut = Join-Path $logDir "enable_ftdi_vcp.restart.stdout.txt"
$restartErr = Join-Path $logDir "enable_ftdi_vcp.restart.stderr.txt"
Remove-Item -LiteralPath $restartOut,$restartErr -Force -ErrorAction SilentlyContinue
$restart = Start-Process -FilePath $pnputil -ArgumentList @('/restart-device', "`"$instanceId`"") -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $restartOut -RedirectStandardError $restartErr

if ($restart.ExitCode -ne 0) {
    Add-Content -LiteralPath $log -Value "channel_restart_exit=$($restart.ExitCode)"
    $parentInstance = "USB\VID_0403&PID_6010\$BoardSerial"
    $parentOut = Join-Path $logDir "enable_ftdi_vcp.parent_restart.stdout.txt"
    $parentErr = Join-Path $logDir "enable_ftdi_vcp.parent_restart.stderr.txt"
    $restart = Start-Process -FilePath $pnputil -ArgumentList @('/restart-device', "`"$parentInstance`"") -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $parentOut -RedirectStandardError $parentErr
    Add-Content -LiteralPath $log -Value "parent_restart_exit=$($restart.ExitCode)"
    if ($restart.ExitCode -ne 0) {
        throw "LoadVCP was set, but PnP restart failed with exit code $($restart.ExitCode)."
    }
} else {
    Add-Content -LiteralPath $log -Value "channel_restart_exit=0"
}

Start-Sleep -Seconds 3
Write-Output "FTDI_VCP_CONFIGURED instance=$instanceId LoadVCP=$loadVcp ConfigData=0x$($configData.ToString('x8'))"
