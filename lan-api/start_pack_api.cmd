@echo off
cd /d "%~dp0"
chcp 65001 >nul
set PYTHONUTF8=1
set "GOLGI_FFMPEG=%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe"
set "PACK_REPO=D:\golgi\medical_version_client"
set "PACK_CLIENT_PACK=D:\golgi\client-pack"
set "PACK_NAS_DIR=\\nas.golgi-bci.com\软件组共享\最新社区筛查客户端"
set "PACK_BRANCH=develop2"
set "PACK_API_PORT=8765"
set "PY=%LOCALAPPDATA%\Programs\Python\Python311\pythonw.exe"
if not exist "%PY%" set "PY=%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
if not exist "%PY%" set "PY=python"
start "community-pack-api" /MIN "%PY%" "%~dp0pack_api.py"
exit /b 0
