@echo off
setlocal
set "BIT_FILE=%~dp0..\artifacts\system.bit"
call "F:\Vivado2025.2\2025.2\Vitis\bin\xsct.bat" "%~dp0..\ps\scripts\program_pl_only.tcl"
exit /b %ERRORLEVEL%
