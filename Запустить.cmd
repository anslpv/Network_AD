@echo off
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Start-NetInventory.ps1" -NoRelaunch
