@echo off
REM ASCII-only launcher. Chinese UI is in guided_pack_wizard.ps1 (UTF-8 BOM).
chcp 65001 >nul
cd /d "%~dp0"
set "REPO=%~1"
if "%REPO%"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\guided_pack_wizard.ps1" -Mode Install -SkipEnv
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\guided_pack_wizard.ps1" -Mode Install -Repo "%REPO%"
)
exit /b %ERRORLEVEL%
