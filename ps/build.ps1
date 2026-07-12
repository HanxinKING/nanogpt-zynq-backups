$ErrorActionPreference = "Stop"

$proj = Resolve-Path "$PSScriptRoot\.."
$root = Resolve-Path "$proj\..\system_dma_jtag"
$src = Join-Path $proj "src"
$build = Join-Path $proj "build"
$sharedSrc = Join-Path $root "src"
$gccDir = "F:\Vivado2025.2\2025.2\Vitis\gnu\aarch32\nt\gcc-arm-none-eabi\bin"
$gcc = Join-Path $gccDir "arm-none-eabi-gcc.exe"
$objdump = Join-Path $gccDir "arm-none-eabi-objdump.exe"
$size = Join-Path $gccDir "arm-none-eabi-size.exe"

New-Item -ItemType Directory -Force $build | Out-Null

$args = @(
    "-mcpu=cortex-a9",
    "-mfpu=vfpv3",
    "-mfloat-abi=hard",
    "-marm",
    "-ffreestanding",
    "-fno-builtin",
    "-O2",
    "-Wall",
    "-Wextra",
    "-T", (Join-Path $src "lscript.ld"),
    "-nostartfiles",
    "-Wl,--build-id=none",
    "-Wl,--gc-sections",
    "-o", (Join-Path $build "ps_mailbox_runner.elf"),
    (Join-Path $sharedSrc "startup.S"),
    (Join-Path $src "main.c")
)
$gccOut = Join-Path $build "gcc.stdout.txt"
$gccErr = Join-Path $build "gcc.stderr.txt"
$proc = Start-Process -FilePath $gcc -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $gccOut -RedirectStandardError $gccErr
if ($proc.ExitCode -ne 0) {
    Get-Content $gccOut -ErrorAction SilentlyContinue
    Get-Content $gccErr -ErrorAction SilentlyContinue
    throw "arm-none-eabi-gcc failed with exit code $($proc.ExitCode)"
}

$sizeOut = Join-Path $build "size.txt"
$objdumpOut = Join-Path $build "ps_mailbox_runner.sections.txt"
Start-Process -FilePath $size -ArgumentList @((Join-Path $build "ps_mailbox_runner.elf")) -NoNewWindow -Wait -RedirectStandardOutput $sizeOut
Start-Process -FilePath $objdump -ArgumentList @("-h", (Join-Path $build "ps_mailbox_runner.elf")) -NoNewWindow -Wait -RedirectStandardOutput $objdumpOut
Get-Content $sizeOut
Write-Output "ELF=$build\ps_mailbox_runner.elf"
