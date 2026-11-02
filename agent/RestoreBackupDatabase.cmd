@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RestoreBackupDatabase.ps1" -ConfigPath "%~dp0agent.config.development.json"