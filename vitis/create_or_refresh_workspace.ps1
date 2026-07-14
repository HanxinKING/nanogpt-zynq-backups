$ErrorActionPreference = "Stop"

$root = Resolve-Path "$PSScriptRoot\.."
$vivado = "F:\Vivado2025.2\2025.2\Vivado\bin\vivado.bat"
$xsct = Join-Path $PSScriptRoot "run_xsct_with_env.cmd"
$xpr = Join-Path $root "fpga\nano_gpt\nano_gpt.xpr"
$xsa = Join-Path $PSScriptRoot "hardware\nanogpt_qkt8_100mhz.xsa"
$workspace = Join-Path $PSScriptRoot "workspace"
$sources = Join-Path $PSScriptRoot "workspace_sources\ps_mailbox_runner\src"
$psSource = Join-Path $root "fpga\nano_gpt\baremetal\ps_mailbox_runner\src"

New-Item -ItemType Directory -Force (Split-Path $xsa), $workspace, $sources | Out-Null

Write-Host "[1/3] Exporting XSA from Vivado project..."
$vivadoLog = Join-Path $PSScriptRoot "export_xsa.log"
$vivadoErr = Join-Path $PSScriptRoot "export_xsa.err"
$vivadoArgs = @("-mode", "batch", "-source", (Join-Path $PSScriptRoot "export_hardware_xsa.tcl"), "-tclargs", $xpr, $xsa)
$vivadoProc = Start-Process -FilePath $vivado -ArgumentList $vivadoArgs -WorkingDirectory $PSScriptRoot -Wait -PassThru -NoNewWindow -RedirectStandardOutput $vivadoLog -RedirectStandardError $vivadoErr
if ($vivadoProc.ExitCode -ne 0 -or -not (Test-Path $xsa)) {
    Get-Content $vivadoLog -Tail 80 -ErrorAction SilentlyContinue
    Get-Content $vivadoErr -Tail 80 -ErrorAction SilentlyContinue
    throw "Vivado XSA export failed"
}

Write-Host "[2/3] Preparing PS sources..."
Copy-Item (Join-Path $psSource "main.c") $sources -Force
Copy-Item (Join-Path $psSource "startup.S") $sources -Force
Copy-Item (Join-Path $psSource "lscript.ld") $sources -Force
Copy-Item (Join-Path $root "reference\int8_alignment\hardware_params\ps_bittrue_params.h") $sources -Force

Write-Host "[3/3] Creating Vitis standalone platform..."
$env:PATH = "F:\Vivado2025.2\2025.2\Vitis\gnuwin\bin;F:\Vivado2025.2\2025.2\gnu\aarch32\nt\gcc-arm-none-eabi\bin;$env:PATH"
$xsctLog = Join-Path $PSScriptRoot "create_platform.log"
$xsctErr = Join-Path $PSScriptRoot "create_platform.err"
Remove-Item $xsctLog, $xsctErr -Force -ErrorAction SilentlyContinue
$xsctProc = Start-Process -FilePath $xsct -ArgumentList @($workspace, $xsa, $sources) -WorkingDirectory $PSScriptRoot -Wait -PassThru -NoNewWindow -RedirectStandardOutput $xsctLog -RedirectStandardError $xsctErr
$platformError = (Select-String -Path $xsctLog, $xsctErr -Pattern "VITIS_PLATFORM_ERROR=|Failed to generate the platform|Failed to build" -ErrorAction SilentlyContinue)
$platformSuccess = (Select-String -Path $xsctLog -Pattern "PLATFORM=nanogpt_qkt8_platform" -SimpleMatch -ErrorAction SilentlyContinue)
if ($xsctProc.ExitCode -ne 0 -or $platformError -or -not $platformSuccess) {
    Get-Content $xsctLog -Tail 100 -ErrorAction SilentlyContinue
    Get-Content $xsctErr -Tail 100 -ErrorAction SilentlyContinue
    throw "Vitis platform creation failed"
}

$vitisAppSource = Join-Path $workspace "ps_mailbox_runner_vitis\src"
New-Item -ItemType Directory -Force $vitisAppSource | Out-Null
Copy-Item (Join-Path $sources "*") $vitisAppSource -Force

# Classic Vitis 2025.2 may create an ARM v7 project without selecting the
# Cortex-A9 CPU/FPU.  Patch the managed-build metadata so both GUI Build and
# future workspace refreshes use the same flags as the verified bare-metal ELF.
$cproject = Join-Path $workspace "ps_mailbox_runner_vitis\.cproject"
if (-not (Test-Path $cproject)) {
    throw "Vitis application metadata was not generated: $cproject"
}
$projectText = Get-Content -LiteralPath $cproject -Raw
$archFlags = "-mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -marm"
$bspLib = (Join-Path $workspace "nanogpt_qkt8_platform\ps7_cortexa9_0\standalone_domain\bsp\ps7_cortexa9_0\lib") -replace '\\', '/'
foreach ($configuration in @("debug", "release")) {
    if ($projectText -notmatch "nanogpt\.assembler\.flags\.$configuration") {
        $pattern = '(<tool[^>]+superClass="xilinx\.gnu\.armv7\.c\.toolchain\.assembler\.' + $configuration + '"[^>]*>)'
        $option = '$1' + "`r`n                                <option id=`"nanogpt.assembler.flags.$configuration`" superClass=`"xilinx.gnu.both.assembler.option.flags`" value=`"$archFlags`" valueType=`"string`"/>"
        $projectText = $projectText -replace $pattern, $option
    }
    if ($projectText -notmatch "nanogpt\.compiler\.flags\.$configuration") {
        $pattern = '(<tool[^>]+superClass="xilinx\.gnu\.armv7\.c\.toolchain\.compiler\.' + $configuration + '"[^>]*>)'
        $compilerFlags = '-c -fmessage-length=0 -MT&quot;$@&quot; ' + $archFlags
        $option = '$1' + "`r`n                                <option id=`"nanogpt.compiler.flags.$configuration`" superClass=`"xilinx.gnu.compiler.misc.other`" value=`"$compilerFlags`" valueType=`"string`"/>"
        $projectText = $projectText -replace $pattern, $option
    }
    if ($projectText -notmatch "nanogpt\.linker\.flags\.$configuration") {
        $pattern = '(<tool[^>]+superClass="xilinx\.gnu\.armv7\.c\.toolchain\.linker\.' + $configuration + '"[^>]*>)'
        $option = '$1' + "`r`n                                <option id=`"nanogpt.linker.flags.$configuration`" superClass=`"xilinx.gnu.c.link.option.ldflags`" value=`"$archFlags -nostartfiles -Wl,--build-id=none`" valueType=`"string`"/>"
        $projectText = $projectText -replace $pattern, $option
    }
    if ($projectText -notmatch "nanogpt\.linker\.path\.$configuration") {
        $pattern = '(<option[^>]+id="nanogpt\.linker\.flags\.' + $configuration + '"[^>]*/>)'
        $option = '$1' + "`r`n                                <option id=`"nanogpt.linker.path.$configuration`" superClass=`"xilinx.gnu.c.link.option.paths`" valueType=`"libPaths`">`r`n                                    <listOptionValue builtIn=`"false`" value=`"$bspLib`"/>`r`n                                </option>"
        $projectText = $projectText -replace $pattern, $option
    }
}
# Vitis Classic runs this post-step in a managed Windows environment. Prefixing
# the absolute tool path with cmd.exe /c avoids both PATH isolation and "F:" parsing.
$sizeCommand = 'cmd.exe /c F:/Vivado2025.2/2025.2/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-size.exe'
$projectText = $projectText -replace '(<tool)(?![^>]* command=)([^>]+superClass="xilinx\.gnu\.armv7\.size\.(?:debug|release)"[^>]*/>)', ('$1 command="' + $sizeCommand + '"$2')
$projectText = $projectText -replace '(<tool)(?![^>]* commandLinePattern=)([^>]+superClass="xilinx\.gnu\.armv7\.size\.(?:debug|release)"[^>]*/>)', ('$1 commandLinePattern="${COMMAND} ${FLAGS} ${INPUTS} &gt; ${OUTPUT}"$2')
Set-Content -LiteralPath $cproject -Value $projectText -Encoding UTF8

Write-Host "XSA       = $xsa"
Write-Host "Workspace = $workspace"
Write-Host "Vitis app = $(Join-Path $workspace 'ps_mailbox_runner_vitis')"
Write-Host "PS source = $vitisAppSource"
Write-Host "Existing ELF = $(Join-Path $root 'fpga\nano_gpt\baremetal\ps_mailbox_runner\build\ps_mailbox_runner.elf')"
