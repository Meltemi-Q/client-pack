# Sync origin/develop2 from this PC (already logged into GitHub) to the pack PC.
# Does not put a GitHub token on 105.
$ErrorActionPreference = 'Stop'
$Key = Join-Path $env:USERPROFILE '.ssh\id_ed25519_105_packsync'
$Repo = 'D:\Programs\golgi\geerji_all\medical_version_client'
$Remote = 'huawei@192.168.0.105:D:/golgi/medical_version_client'
$Ssh = "ssh -i $($Key.Replace('\','/')) -o IdentitiesOnly=yes -o BatchMode=yes"
$LogDir = 'D:\Programs\golgi\geerji_all\_pack_xfer'
$Log = Join-Path $LogDir 'sync105.log'

function Write-Log($msg) {
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Add-Content -Path $Log -Value $line -Encoding UTF8
  Write-Host $line
}

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
if (-not (Test-Path $Key)) { throw "missing SSH key $Key" }

$env:GIT_SSH_COMMAND = $Ssh
$env:GIT_TERMINAL_PROMPT = '0'
Set-Location $Repo
git fetch origin develop2
$want = (git rev-parse origin/develop2).Trim()
Write-Log "local origin/develop2 $want"

git -c lfs.locksverify=false push $Remote origin/develop2:refs/remotes/origin/develop2
if ($LASTEXITCODE -ne 0) { throw "git push to 105 failed: $LASTEXITCODE" }

& ssh.exe -i $Key -o IdentitiesOnly=yes -o BatchMode=yes huawei@192.168.0.105 'cmd.exe /c D:\golgi\pack-api\apply_lan_sync.cmd'
if ($LASTEXITCODE -ne 0) { throw "105 merge failed: $LASTEXITCODE" }

Write-Log 'sync ok'
