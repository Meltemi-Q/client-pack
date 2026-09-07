$pyw = Join-Path $env:USERPROFILE "scoop\apps\python312\current\pythonw.exe"
if (-not (Test-Path $pyw)) {
    $pyw = Join-Path $env:USERPROFILE "scoop\apps\python312\current\python.exe"
}
$api = Join-Path $PSScriptRoot "pack_api.py"
$action = New-ScheduledTaskAction -Execute $pyw -Argument $api -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName GolgiCommunityPackAPI -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName GolgiCommunityPackAPI
Write-Host "Created logon task GolgiCommunityPackAPI (no console window)"
