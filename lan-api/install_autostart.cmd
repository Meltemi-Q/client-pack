@echo off
REM Run as the same Windows user that owns the pack env.
schtasks /Create /F /TN "GolgiCommunityPackAPI" /SC ONLOGON /RL HIGHEST /TR "\"%~dp0start_pack_api.cmd\""
echo Created logon task GolgiCommunityPackAPI
exit /b %ERRORLEVEL%
