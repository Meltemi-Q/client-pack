@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "if (-not (Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue)) { Start-ScheduledTask -TaskName GolgiCommunityPackAPI; Start-Sleep -Seconds 2 }; Start-Process 'http://192.168.0.226:8765'"
