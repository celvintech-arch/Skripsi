@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RestoreBackupDatabase.ps1" -ConfigPath "C:\BackupAgent\agent.config.production.json"
