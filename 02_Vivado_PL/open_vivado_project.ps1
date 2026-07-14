$ErrorActionPreference = "Stop"

$root = Resolve-Path "$PSScriptRoot\.."
$vivado = "F:\Vivado2025.2\2025.2\Vivado\bin\vivado.bat"
$project = Join-Path $root "fpga\nano_gpt\nano_gpt.xpr"

if (-not (Test-Path $vivado)) { throw "Vivado not found: $vivado" }
if (-not (Test-Path $project)) { throw "Vivado project not found: $project" }

Start-Process -FilePath $vivado -ArgumentList @($project) -WorkingDirectory (Split-Path $project)
Write-Host "Vivado project opened: $project"
