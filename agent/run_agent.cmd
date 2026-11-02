@echo off
title LINTAR Backup Agent
echo ========================================================
echo   MENJALANKAN LINTAR BACKUP AGENT (WORKER DAEMON)
echo ========================================================
echo Agen akan berjalan terus menerus di latar belakang.
echo Tekan Ctrl+C di jendela ini jika ingin menghentikan.
echo ========================================================
echo.

:loop
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BackupAgent.ps1" -ConfigFile "%~dp0agent.config.development.json"
echo [%date% %time%] Siklus selesai, menunggu 5 detik sebelum siklus berikutnya...
timeout /t 5 >nul
goto loop
