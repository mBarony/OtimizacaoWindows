@echo off
title Reverter Otimizacao
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Reverter-Windows.ps1"