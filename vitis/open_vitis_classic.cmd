@echo off
call "F:\Vivado2025.2\2025.2\Vitis\settings64.bat"
set "PATH=F:\Vivado2025.2\2025.2\Vitis\lib\win64.o;F:\Vivado2025.2\2025.2\Vitis\bin;F:\Vivado2025.2\2025.2\Vitis\gnuwin\bin;F:\Vivado2025.2\2025.2\Vitis\gnu\aarch32\nt\gcc-arm-none-eabi\bin;%PATH%"
start "Vitis PS Workspace" "F:\Vivado2025.2\2025.2\Vitis\eclipse\win64.o\eclipse.exe" -vm "F:\Vivado2025.2\2025.2\Vitis\tps\win64\jre21.0.5_11\bin\javaw.exe" -data "%~dp0workspace"
