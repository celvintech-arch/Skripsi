@echo off
setlocal
set "TEST_DIR=%~dp0"
set "REPO_ROOT=%TEST_DIR%.."
set "REPORT_DIR=%REPO_ROOT%\TestResults"
if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TEST_DIR%Run-BackupTests.ps1" -ApplicationRoot "%REPO_ROOT%\web\backup_data" -ToolingRoot "%REPO_ROOT%" -ConfigPath "%REPO_ROOT%\agent\agent.config.development.example.json" -SkipApi -SkipLocalDatabase -ReportPath "%REPORT_DIR%\latest.json"
set "TEST_EXIT=%ERRORLEVEL%"
echo.
if "%TEST_EXIT%"=="0" (
  echo Semua pengujian wajib berhasil.
) else (
  echo Ada pengujian yang gagal. Periksa tabel hasil di atas.
)
exit /b %TEST_EXIT%
