@echo off
title Otimizar Windows
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Otimizar-Windows.ps1" %*