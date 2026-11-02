@echo off
title LINTAR Backup Agent
echo ========================================================
echo   MENJALANKAN LINTAR BACKUP AGENT (WORKER DAEMON)
echo ========================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BackupAgent.ps1" -ConfigFile "%~dp0agent.config.development.json"
pause