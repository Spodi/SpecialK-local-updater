:: This is a wrapper to start the PowerShell script in the
:: same directory with the same name automatically.
:: PowerShell is a bit paranoid about starting scripts otherwise.
:: This also takes care of things if called from a 32-bit app.
@echo off
title SKSS
color 17
cd %~dp0
if exist "%systemroot%\SysNative\WindowsPowerShell\v1.0\powershell.exe" (
	echo Starting %systemroot%\SysNative\WindowsPowerShell\v1.0\powershell.exe -NoLogo -ExecutionPolicy Bypass -File "%~dpn0.ps1" %*
	start %systemroot%\SysNative\WindowsPowerShell\v1.0\powershell.exe -NoLogo -ExecutionPolicy Bypass -File "%~dpn0.ps1" %*
) else (
	echo Starting %systemroot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -ExecutionPolicy Bypass -File "%~dpn0.ps1" %*
	start %systemroot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -ExecutionPolicy Bypass -File "%~dpn0.ps1" %*
)
EXIT /b