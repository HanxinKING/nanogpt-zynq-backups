@echo off
setlocal
set "PATH=F:\Vivado2025.2\2025.2\Vitis\gnuwin\bin;F:\Vivado2025.2\2025.2\gnu\aarch32\nt\gcc-arm-none-eabi\bin;%SystemRoot%\System32;%SystemRoot%;%PATH%"
call "F:\Vivado2025.2\2025.2\Vitis\bin\xsct.bat" "%~dp0create_platform.tcl" "%~1" "%~2" "%~3"
exit /b %ERRORLEVEL%
