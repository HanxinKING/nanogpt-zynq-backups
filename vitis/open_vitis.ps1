$ErrorActionPreference = "Stop"

$launcher = Join-Path $PSScriptRoot "open_vitis_classic.cmd"
$workspace = Join-Path $PSScriptRoot "workspace"
if (-not (Test-Path $launcher)) { throw "Vitis launcher not found: $launcher" }
if (-not (Test-Path $workspace)) {
    throw "Workspace not found. Run create_or_refresh_workspace.ps1 first."
}

Start-Process -FilePath $launcher -WorkingDirectory $PSScriptRoot
Write-Host "Vitis workspace opened: $workspace"
