@echo off
:: Lance le script PowerShell avec GUI
powershell.exe -ExecutionPolicy Bypass -NoLogo -NoProfile -File "%~dp0install-gui.ps1"
