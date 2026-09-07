@echo off
cd /d %~dp0
set PYTHONUTF8=1
set PACK_REPO=D:\Programs\golgi\geerji_all\medical_version_client
set PACK_CLIENT_PACK=D:\Programs\golgi\geerji_all\client-pack
set PACK_LOCAL_OUT=D:\Programs\golgi\geerji_all\_pack_out
set PACK_CONDA_ROOT=%USERPROFILE%\scoop\apps\miniconda3\current
set PACK_BRANCH=develop2
set PACK_API_PORT=8765
set GOLGI_FFMPEG=%USERPROFILE%\scoop\apps\ffmpeg\current\bin\ffmpeg.exe
if not exist "%GOLGI_FFMPEG%" set GOLGI_FFMPEG=%USERPROFILE%\scoop\apps\ffmpeg\8.0.1\bin\ffmpeg.exe
set NO_PROXY=*
set no_proxy=*
set PY=%USERPROFILE%\scoop\apps\python312\current\pythonw.exe
if not exist "%PY%" set PY=%USERPROFILE%\scoop\apps\python312\current\python.exe
start "" "%PY%" "%~dp0pack_api.py"
exit /b 0
