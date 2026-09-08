@echo off
setlocal
set "TEST_DIR=%~dp0"
set "REPORT_DIR=C:\BackupAgent\TestResults"
if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TEST_DIR%Run-BackupTests.ps1" -ApplicationRoot "C:\inetpub\wwwroot\backup_data" -ConfigPath "C:\BackupAgent\agent.config.development.json" -ReportPath "%REPORT_DIR%\latest.json"
set "TEST_EXIT=%ERRORLEVEL%"
echo.
if "%TEST_EXIT%"=="0" (
  echo Semua pengujian wajib berhasil.
) else (
  echo Ada pengujian yang gagal. Periksa tabel hasil di atas.
)
exit /b %TEST_EXIT%
