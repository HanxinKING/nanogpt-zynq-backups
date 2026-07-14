param(
    [string]$Python = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dist = Join-Path $root "dist"
$build = Join-Path $root "build"
$exe = Join-Path $dist "KeChuangNanoGPT.exe"

if (-not $Python) {
    $Python = (Get-Command python -ErrorAction Stop).Source
}

if (-not (Test-Path -LiteralPath $Python)) {
    throw "Python not found: $Python"
}

$stdout = Join-Path $root "pyinstaller.stdout.log"
$stderr = Join-Path $root "pyinstaller.stderr.log"
Remove-Item $stdout, $stderr -ErrorAction SilentlyContinue
Get-Process -Name "KeChuangNanoGPT" -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item $exe -Force -ErrorAction SilentlyContinue
Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $root "__pycache__") -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $root "tests\__pycache__") -Recurse -Force -ErrorAction SilentlyContinue

$arguments = @(
    "-m", "PyInstaller",
    "--noconfirm",
    "--clean",
    "--distpath", $dist,
    "--workpath", $build,
    (Join-Path $root "KeChuangNanoGPT.spec")
)

$process = Start-Process -FilePath $Python `
    -ArgumentList $arguments `
    -WorkingDirectory $root `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -WindowStyle Hidden `
    -PassThru
$process.WaitForExit()

if (-not (Test-Path -LiteralPath $exe)) {
    Get-Content $stdout -ErrorAction SilentlyContinue
    Get-Content $stderr -ErrorAction SilentlyContinue
    throw "PyInstaller did not create the executable."
}

Write-Output "EXE=$exe"
