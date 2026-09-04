@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM Pack a Golgi Windows client. ASCII-only. No secrets.
REM Usage: pack_client.cmd [path\to\client_repo]

set "SKILL_SCRIPTS=%~dp0"
set "CHECK_PS1=%SKILL_SCRIPTS%check_pack_env.ps1"

set "REPO=%~1"
if "%REPO%"=="" set "REPO=%CD%"

if not exist "%REPO%\build_and_pack.bat" (
  echo [ERROR] Not a client pack repo: missing build_and_pack.bat
  echo Usage: pack_client.cmd [path\to\client checkout]
  echo Point at the client source tree, not this skill folder.
  exit /b 1
)
if not exist "%REPO%\setup_build_env.bat" (
  echo [ERROR] Missing setup_build_env.bat
  exit /b 1
)
if exist "%SKILL_SCRIPTS%ensure_pack_spec.ps1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%SKILL_SCRIPTS%ensure_pack_spec.ps1" "%REPO%"
)
set "FOUND_SPEC="
for %%F in ("%REPO%\*.spec") do set "FOUND_SPEC=1"
if not defined FOUND_SPEC (
  echo [ERROR] No .spec next to build_and_pack.bat
  echo Need an onedir spec ^(contains COLLECT^), not onefile.
  echo If git only has fNIRS_Community.spec, copy templates\Golgi_fNIRS_community.spec
  exit /b 1
)
if not exist "%CHECK_PS1%" (
  echo [ERROR] Missing env check script: %CHECK_PS1%
  exit /b 1
)

cd /d "%REPO%"
if errorlevel 1 (
  echo [ERROR] Cannot cd to %REPO%
  exit /b 1
)
set "REPO=%CD%"
set "GOLGI_NOPAUSE=1"

where conda.bat >nul 2>&1
if errorlevel 1 (
  if exist "%USERPROFILE%\miniconda3\condabin\conda.bat" set "PATH=%USERPROFILE%\miniconda3\condabin;%USERPROFILE%\miniconda3\Scripts;%USERPROFILE%\miniconda3;%PATH%"
  if exist "%USERPROFILE%\Miniconda3\condabin\conda.bat" set "PATH=%USERPROFILE%\Miniconda3\condabin;%USERPROFILE%\Miniconda3\Scripts;%USERPROFILE%\Miniconda3;%PATH%"
  if exist "%USERPROFILE%\anaconda3\condabin\conda.bat" set "PATH=%USERPROFILE%\anaconda3\condabin;%USERPROFILE%\anaconda3\Scripts;%USERPROFILE%\anaconda3;%PATH%"
  if exist "%USERPROFILE%\Anaconda3\condabin\conda.bat" set "PATH=%USERPROFILE%\Anaconda3\condabin;%USERPROFILE%\Anaconda3\Scripts;%USERPROFILE%\Anaconda3;%PATH%"
  if exist "%USERPROFILE%\scoop\apps\miniconda3\current\condabin\conda.bat" set "PATH=%USERPROFILE%\scoop\apps\miniconda3\current\condabin;%USERPROFILE%\scoop\apps\miniconda3\current\Scripts;%USERPROFILE%\scoop\apps\miniconda3\current;%PATH%"
  if exist "C:\ProgramData\miniconda3\condabin\conda.bat" set "PATH=C:\ProgramData\miniconda3\condabin;C:\ProgramData\miniconda3\Scripts;C:\ProgramData\miniconda3;%PATH%"
  if exist "C:\ProgramData\anaconda3\condabin\conda.bat" set "PATH=C:\ProgramData\anaconda3\condabin;C:\ProgramData\anaconda3\Scripts;C:\ProgramData\anaconda3;%PATH%"
)
where conda.bat >nul 2>&1
if errorlevel 1 (
  echo [ERROR] conda.bat still not found after searching common install locations.
  echo ACT: powershell -NoProfile -ExecutionPolicy Bypass -File "%SKILL_SCRIPTS%bootstrap_pack_tools.ps1" -Repo "%REPO%"
  echo Or double-click 一键安装打包工具.cmd
  echo Do not download PyInstaller.exe. Do not use system Python 3.11.
  exit /b 1
)

echo [pack] repo=%REPO%
echo [pack] GOLGI_NOPAUSE=%GOLGI_NOPAUSE%
if defined GOLGI_BUILD_ENV echo [pack] GOLGI_BUILD_ENV=%GOLGI_BUILD_ENV%
if defined GOLGI_FAST_BUILD echo [pack] GOLGI_FAST_BUILD=%GOLGI_FAST_BUILD%
if defined GOLGI_ISCC echo [pack] GOLGI_ISCC=%GOLGI_ISCC%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%CHECK_PS1%" "%REPO%"
set "CHK=!ERRORLEVEL!"

if not "!CHK!"=="0" if not "!CHK!"=="2" (
  echo [ERROR] Environment check failed. Fix FAIL lines, then retry. ^(exit !CHK!^)
  echo See client-pack\references\pitfalls.md
  exit /b 1
)

if "!CHK!"=="2" (
  echo [env] Env missing or pinned packages mismatch. Running setup_build_env.bat ...
  call "%REPO%\setup_build_env.bat"
  if errorlevel 1 (
    echo [ERROR] setup_build_env.bat failed.
    exit /b 1
  )
  echo.
  echo [env] Re-checking after setup ...
  powershell -NoProfile -ExecutionPolicy Bypass -File "%CHECK_PS1%" "%REPO%"
  set "CHK=!ERRORLEVEL!"
  if not "!CHK!"=="0" (
    echo [ERROR] Still not READY after setup_build_env.bat ^(exit !CHK!^).
    echo If Python is not 3.8 64-bit: conda remove -n golgi-build --all
    echo then run setup_build_env.bat again.
    exit /b 1
  )
)

if not defined GOLGI_FFMPEG (
  if exist "%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe" set "GOLGI_FFMPEG=%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe"
)
if defined GOLGI_FFMPEG echo [pack] GOLGI_FFMPEG=%GOLGI_FFMPEG%

echo.
echo [pack] Calling build_and_pack.bat ...
REM build_and_pack.bat still pauses on success/failure; feed a newline so unattended pack can finish.
echo.| call "%REPO%\build_and_pack.bat"
if errorlevel 1 (
  echo [ERROR] build_and_pack.bat failed.
  exit /b 1
)

echo.
set "OUT_DIR=%REPO%\dist\installer"
if not exist "%OUT_DIR%" (
  echo [ERROR] Installer dir missing: %OUT_DIR%
  exit /b 1
)

set "OUTPUT="
for /f "delims=" %%F in ('dir /b /o-d "%OUT_DIR%\*_setup_*.exe" 2^>nul') do (
  set "OUTPUT=!OUT_DIR!\%%F"
  goto :got_output
)

echo [ERROR] No installer matching *_setup_*.exe under dist\installer
exit /b 1

:got_output
echo ========================================
echo   Pack completed.
echo   OUTPUT=!OUTPUT!
echo ========================================
exit /b 0
