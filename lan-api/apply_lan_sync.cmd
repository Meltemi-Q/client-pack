@echo off
set GIT_LFS_SKIP_SMUDGE=1
set GIT_TERMINAL_PROMPT=0
cd /d D:\golgi\medical_version_client
git merge --ff-only origin/develop2
git log -1 --oneline
exit /b %ERRORLEVEL%
