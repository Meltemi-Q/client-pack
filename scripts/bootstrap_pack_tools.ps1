# Bootstrap pack tools for Golgi Windows clients.
# Source of truth for download URLs and silent-install flags.
# PyInstaller is NOT downloaded here. It is pip-installed by the repo's
# setup_build_env.bat into conda env golgi-build as pyinstaller==6.20.0.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File bootstrap_pack_tools.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File bootstrap_pack_tools.ps1 -Repo D:\path\to\client_repo
#   powershell -NoProfile -ExecutionPolicy Bypass -File bootstrap_pack_tools.ps1 -ToolsOnly
#
# Exit 0 RESULT=TOOLS_READY  (and RESULT=ENV_READY if -Repo setup succeeded)
# Exit 1 RESULT=FAIL         (read NEXT= line)

[CmdletBinding()]
param(
    [string]$Repo = "",
    [switch]$ToolsOnly,
    [switch]$SkipMiniconda,
    [switch]$SkipInno,
    [switch]$SkipFfmpeg
)

$ErrorActionPreference = "Continue"

# --- official sources (must match SKILL.md allowlist; do not invent mirrors) ---
# Miniconda docs: https://www.anaconda.com/docs/getting-started/miniconda/install/windows-cli-install
$MinicondaUrl = "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"
$MinicondaWingetId = "Anaconda.Miniconda3"
# Inno 6 (pinned). Official list: https://jrsoftware.org/isdl.php
# jrsoftware moved installers to immutable GitHub releases (2026-03-02).
# Do NOT use https://jrsoftware.org/download.php/is.exe — that now tracks latest (7.x).
$InnoUrl = "https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe"
$InnoWingetId = "JRSoftware.InnoSetup"
$InnoWingetVersion = "6.7.3"
# ffmpeg (real Windows build, not a scoop/winget shim). Landing: https://www.gyan.dev/ffmpeg/builds/
# Pin the GitHub immutable zip. Do NOT use gyan.dev/ffmpeg-release-essentials.zip as the
# fetch URL — it redirects and hangs on Windows PowerShell HttpWebRequest/some GET paths.
$FfmpegUrl = "https://github.com/GyanD/codexffmpeg/releases/download/8.0/ffmpeg-8.0-essentials_build.zip"
$FfmpegWingetId = "Gyan.FFmpeg.Essentials"
$FfmpegPrefix = Join-Path $env:LOCALAPPDATA "Programs\ffmpeg"
$MinicondaPrefix = Join-Path $env:USERPROFILE "Miniconda3"
$FfmpegMinBytes = 1000000

function Write-Step([string]$Msg) { Write-Host ("[bootstrap] " + $Msg) }
function Write-Next([string]$Msg) { Write-Host ("NEXT=" + $Msg) }

function Test-IsAdmin {
    $wid = [Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = New-Object Security.Principal.WindowsPrincipal($wid)
    return $prp.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-CondaBat {
    $whereOut = & where.exe conda.bat 2>$null
    if ($whereOut) {
        $hit = (@($whereOut) | Select-Object -First 1).ToString().Trim()
        if ($hit -and (Test-Path -LiteralPath $hit)) { return $hit }
    }
    $hints = @(
        (Join-Path $env:USERPROFILE "Miniconda3\condabin\conda.bat"),
        (Join-Path $env:USERPROFILE "miniconda3\condabin\conda.bat"),
        (Join-Path $env:USERPROFILE "Anaconda3\condabin\conda.bat"),
        (Join-Path $env:USERPROFILE "anaconda3\condabin\conda.bat"),
        (Join-Path $env:USERPROFILE "scoop\apps\miniconda3\current\condabin\conda.bat"),
        "C:\ProgramData\miniconda3\condabin\conda.bat",
        "C:\ProgramData\Miniconda3\condabin\conda.bat",
        "C:\ProgramData\anaconda3\condabin\conda.bat",
        "C:\ProgramData\Anaconda3\condabin\conda.bat"
    )
    foreach ($p in $hints) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Test-RealFfmpeg([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        return ((Get-Item -LiteralPath $Path).Length -ge $FfmpegMinBytes)
    } catch {
        return $false
    }
}

function Find-Ffmpeg {
    if (Test-RealFfmpeg $env:GOLGI_FFMPEG) { return $env:GOLGI_FFMPEG }
    $whereOut = & where.exe ffmpeg.exe 2>$null
    if ($whereOut) {
        foreach ($hit in @($whereOut)) {
            $p = $hit.ToString().Trim()
            if (Test-RealFfmpeg $p) { return $p }
        }
    }
    $hints = @(
        (Join-Path $FfmpegPrefix "bin\ffmpeg.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\ffmpeg\bin\ffmpeg.exe"),
        (Join-Path $env:USERPROFILE "ffmpeg\bin\ffmpeg.exe"),
        "C:\ffmpeg\bin\ffmpeg.exe",
        (Join-Path $env:USERPROFILE "scoop\apps\ffmpeg\current\bin\ffmpeg.exe")
    )
    foreach ($p in $hints) {
        if (Test-RealFfmpeg $p) { return $p }
    }
    $wingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path -LiteralPath $wingetRoot) {
        $hits = @(Get-ChildItem -LiteralPath $wingetRoot -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue)
        foreach ($h in $hits) {
            if (Test-RealFfmpeg $h.FullName) { return $h.FullName }
        }
    }
    return $null
}

function Find-Iscc {
    if (-not [string]::IsNullOrWhiteSpace($env:GOLGI_ISCC) -and (Test-Path -LiteralPath $env:GOLGI_ISCC)) {
        return $env:GOLGI_ISCC
    }
    $hints = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 7\ISCC.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 7\ISCC.exe"),
        "D:\Tools\Inno Setup 6\ISCC.exe",
        "D:\Tools\InnoSetup6\ISCC.exe"
    )
    foreach ($p in $hints) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

function Test-LocalPortOpen([int]$Port) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect("127.0.0.1", $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(400)
        $connected = $ok -and $tcp.Connected
        $tcp.Close()
        return $connected
    } catch {
        return $false
    }
}

function Clear-StaleLocalProxy {
    # conda/requests on Windows fall back to Internet Settings if env proxy is
    # empty. A closed Clash/V2Ray on 127.0.0.1:7890 then becomes ProxyError.
    $dead = @()
    $names = @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy")
    foreach ($n in $names) {
        $val = [Environment]::GetEnvironmentVariable($n, "Process")
        if ([string]::IsNullOrWhiteSpace($val)) { continue }
        if (($val -match '127\.0\.0\.1' -or $val -match 'localhost') -and $val -match ':(\d+)') {
            $port = [int]$Matches[1]
            if (-not (Test-LocalPortOpen $port)) {
                Remove-Item -Path ("Env:" + $n) -ErrorAction SilentlyContinue
                $dead += ($n + "=" + $val)
            }
        }
    }
    $ieProxy = ""
    try {
        $ie = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction Stop
        if ($ie.ProxyEnable -eq 1) { $ieProxy = [string]$ie.ProxyServer }
    } catch {}
    $ieDead = $false
    if ($ieProxy -and ($ieProxy -match '127\.0\.0\.1' -or $ieProxy -match 'localhost')) {
        $port = 7890
        if ($ieProxy -match ':(\d+)') { $port = [int]$Matches[1] }
        if (-not (Test-LocalPortOpen $port)) {
            $ieDead = $true
            $dead += ("InternetSettings=" + $ieProxy)
        }
    }
    if ($ieDead -or $dead.Count -gt 0) {
        # Non-empty env proxy dict stops urllib from using the registry proxy.
        $env:NO_PROXY = "*"
        $env:no_proxy = "*"
        Write-Step ("stale local proxy disabled via NO_PROXY=*: " + ($dead -join "; "))
    }
}

function Add-CondaToProcessPath([string]$CondaBat) {
    $condabin = Split-Path -Parent $CondaBat
    $root = Split-Path -Parent $condabin
    $scripts = Join-Path $root "Scripts"
    $env:PATH = ($condabin + ";" + $scripts + ";" + $root + ";" + $env:PATH)
}

function Get-Installer([string]$Url, [string]$OutFile) {
    Write-Step ("download " + $Url)
    Write-Step ("save    " + $OutFile)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    # Invoke-WebRequest follows redirects more reliably than HttpWebRequest on
    # Windows PowerShell 5.1 (gyan.dev ffmpeg zip redirects to GitHub).
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 300 -UserAgent "golgi-pack-bootstrap/1.0"
    if (-not (Test-Path -LiteralPath $OutFile)) {
        throw ("download produced no file: " + $OutFile)
    }
    $len = (Get-Item -LiteralPath $OutFile).Length
    if ($len -lt 100000) {
        throw ("download too small (" + $len + " bytes), not a real installer: " + $OutFile)
    }
    Write-Step ("download_ok bytes=" + $len)
}

function Invoke-WingetInstall {
    param(
        [string]$Id,
        [string]$Version = ""
    )
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { return $false }
    $args = @("install", "-e", "--id", $Id, "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity")
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        $args += @("--version", $Version)
        Write-Step ("winget install " + $Id + " --version " + $Version)
    } else {
        Write-Step ("winget install " + $Id)
    }
    & winget.exe @args
    return ($LASTEXITCODE -eq 0)
}

# Isolated temp dir: never write into $env:TEMP root (leftover inspect.py can shadow stdlib).
$work = Join-Path $env:TEMP "golgi_pack_bootstrap"
New-Item -ItemType Directory -Path $work -Force | Out-Null

Write-Step "start"
Write-Step ("admin=" + (Test-IsAdmin))
Write-Step ("work=" + $work)
Clear-StaleLocalProxy

# ----- Miniconda -----
$condaBat = Find-CondaBat
if ($SkipMiniconda) {
    Write-Step "miniconda skipped by flag"
} elseif ($condaBat) {
    Write-Step ("miniconda already present: " + $condaBat)
} else {
    Write-Step "miniconda missing; installing JustMe to %USERPROFILE%\Miniconda3"
    $got = Invoke-WingetInstall -Id $MinicondaWingetId
    $condaBat = Find-CondaBat
    if (-not $condaBat -and -not $got) {
        $setup = Join-Path $work "Miniconda3-latest-Windows-x86_64.exe"
        try {
            Get-Installer -Url $MinicondaUrl -OutFile $setup
        } catch {
            Write-Host "RESULT=FAIL"
            Write-Next ("download Miniconda failed: " + $_.Exception.Message + "  URL=" + $MinicondaUrl)
            exit 1
        }
        $arg = "/InstallationType=JustMe /RegisterPython=0 /AddToPath=0 /S /D=" + $MinicondaPrefix
        Write-Step ("silent install " + $arg)
        $p = Start-Process -FilePath $setup -ArgumentList $arg -Wait -PassThru
        if ($p.ExitCode -ne 0) {
            Write-Host "RESULT=FAIL"
            Write-Next ("Miniconda installer exit " + $p.ExitCode + ". Run the exe yourself: " + $setup)
            exit 1
        }
        $condaBat = Find-CondaBat
        if (-not $condaBat -and (Test-Path -LiteralPath (Join-Path $MinicondaPrefix "condabin\conda.bat"))) {
            $condaBat = Join-Path $MinicondaPrefix "condabin\conda.bat"
        }
    }
    if (-not $condaBat) {
        Write-Host "RESULT=FAIL"
        Write-Next "Miniconda installed but conda.bat not found. Close this window, open a new CMD, run: where conda.bat"
        exit 1
    }
    Write-Step ("miniconda ready: " + $condaBat)
    Add-CondaToProcessPath $condaBat
    Write-Step "conda init cmd.exe (so future CMD windows see conda.bat)"
    & $condaBat init cmd.exe | Out-Host
}

if ($condaBat) { Add-CondaToProcessPath $condaBat }

# ----- Inno Setup 6 -----
$iscc = Find-Iscc
if ($SkipInno) {
    Write-Step "inno skipped by flag"
} elseif ($iscc) {
    Write-Step ("ISCC already present: " + $iscc)
} else {
    Write-Step "ISCC missing; installing pinned Inno Setup 6.7.3 (not latest 7)"
    $got = Invoke-WingetInstall -Id $InnoWingetId -Version $InnoWingetVersion
    $iscc = Find-Iscc
    if (-not $iscc) {
        $setup = Join-Path $work "innosetup-6.7.3.exe"
        try {
            Get-Installer -Url $InnoUrl -OutFile $setup
        } catch {
            Write-Host "RESULT=FAIL"
            Write-Next ("download Inno Setup failed: " + $_.Exception.Message + "  URL=" + $InnoUrl)
            exit 1
        }
        if (Test-IsAdmin) {
            $dir = "${env:ProgramFiles(x86)}\Inno Setup 6"
            $arg = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /ALLUSERS /DIR="' + $dir + '"'
        } else {
            $dir = Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6"
            $arg = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CURRENTUSER /DIR="' + $dir + '"'
        }
        Write-Step ("silent install " + $arg)
        $p = Start-Process -FilePath $setup -ArgumentList $arg -Wait -PassThru
        if ($p.ExitCode -ne 0) {
            Write-Host "RESULT=FAIL"
            Write-Next ("Inno installer exit " + $p.ExitCode + ". Run the exe yourself: " + $setup)
            exit 1
        }
        $iscc = Join-Path $dir "ISCC.exe"
        if (-not (Test-Path -LiteralPath $iscc)) {
            $iscc = Find-Iscc
        }
    }
    if (-not $iscc -or -not (Test-Path -LiteralPath $iscc)) {
        Write-Host "RESULT=FAIL"
        Write-Next "Inno Setup ran but ISCC.exe not found. Install Inno Setup 6 and re-run. Expected: C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
        exit 1
    }
    $defaultV6 = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
    )
    $onDefaultV6 = $false
    foreach ($p in $defaultV6) {
        if ($iscc -and (([IO.Path]::GetFullPath($iscc)) -eq ([IO.Path]::GetFullPath($p)))) { $onDefaultV6 = $true }
    }
    if (-not $onDefaultV6) {
        Write-Step ("ISCC not the default Inno Setup 6 Program Files path; set user env GOLGI_ISCC=" + $iscc)
        [Environment]::SetEnvironmentVariable("GOLGI_ISCC", $iscc, "User")
        $env:GOLGI_ISCC = $iscc
    }
    Write-Step ("inno ready: " + $iscc)
}

# ----- ffmpeg (real binary, >= 1MB; required by build_and_pack.bat) -----
$ffmpeg = Find-Ffmpeg
if ($SkipFfmpeg) {
    Write-Step "ffmpeg skipped by flag"
} elseif ($ffmpeg) {
    Write-Step ("ffmpeg already present: " + $ffmpeg)
} else {
    Write-Step "ffmpeg missing; installing Gyan essentials build (not a scoop/store shim)"
    $got = Invoke-WingetInstall -Id $FfmpegWingetId
    $ffmpeg = Find-Ffmpeg
    if (-not $ffmpeg) {
        $zip = Join-Path $work "ffmpeg-release-essentials.zip"
        try {
            Get-Installer -Url $FfmpegUrl -OutFile $zip
        } catch {
            Write-Host "RESULT=FAIL"
            Write-Next ("download ffmpeg failed: " + $_.Exception.Message + "  URL=" + $FfmpegUrl)
            exit 1
        }
        $extract = Join-Path $work "ffmpeg_extract"
        if (Test-Path -LiteralPath $extract) {
            Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $extract -Force | Out-Null
        Write-Step ("extract " + $zip)
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $foundExe = @(Get-ChildItem -LiteralPath $extract -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Where-Object { $_.Length -ge $FfmpegMinBytes } | Select-Object -First 1)
        if ($foundExe.Count -lt 1) {
            Write-Host "RESULT=FAIL"
            Write-Next "ffmpeg zip extracted but ffmpeg.exe >= 1MB was not inside it"
            exit 1
        }
        $buildRoot = $foundExe[0].Directory.Parent.FullName
        if (Test-Path -LiteralPath $FfmpegPrefix) {
            Remove-Item -LiteralPath $FfmpegPrefix -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $FfmpegPrefix) -Force | Out-Null
        Write-Step ("install to " + $FfmpegPrefix)
        Copy-Item -LiteralPath $buildRoot -Destination $FfmpegPrefix -Recurse -Force
        $ffmpeg = Join-Path $FfmpegPrefix "bin\ffmpeg.exe"
        if (-not (Test-RealFfmpeg $ffmpeg)) {
            $ffmpeg = Find-Ffmpeg
        }
    }
    if (-not (Test-RealFfmpeg $ffmpeg)) {
        Write-Host "RESULT=FAIL"
        Write-Next "ffmpeg installed but no real ffmpeg.exe (>= 1MB) was found. Set GOLGI_FFMPEG to the real binary."
        exit 1
    }
    Write-Step ("set user env GOLGI_FFMPEG=" + $ffmpeg)
    [Environment]::SetEnvironmentVariable("GOLGI_FFMPEG", $ffmpeg, "User")
    $env:GOLGI_FFMPEG = $ffmpeg
    $ffBin = Split-Path -Parent $ffmpeg
    if ($env:PATH -notlike ("*" + $ffBin + "*")) {
        $env:PATH = ($ffBin + ";" + $env:PATH)
    }
    Write-Step ("ffmpeg ready: " + $ffmpeg)
}

$condaBat = Find-CondaBat
$iscc = Find-Iscc
$ffmpeg = Find-Ffmpeg
if (-not $condaBat) {
    Write-Host "RESULT=FAIL"
    Write-Next "conda.bat still missing after bootstrap"
    exit 1
}
if (-not $iscc) {
    Write-Host "RESULT=FAIL"
    Write-Next "ISCC.exe still missing after bootstrap"
    exit 1
}
if (-not $ffmpeg) {
    Write-Host "RESULT=FAIL"
    Write-Next "ffmpeg.exe still missing after bootstrap (need a real binary >= 1MB, not a shim)"
    exit 1
}

Write-Host "RESULT=TOOLS_READY"
Write-Host ("CONDA_BAT=" + $condaBat)
Write-Host ("ISCC=" + $iscc)
Write-Host ("FFMPEG=" + $ffmpeg)

# ----- optional golgi-build + PyInstaller pin -----
if ($ToolsOnly) {
    Write-Step "ToolsOnly: not running setup_build_env.bat (PyInstaller is installed there, not as a Windows setup.exe)"
    Write-Next "run pack_client.cmd <repo>  OR  bootstrap_pack_tools.ps1 -Repo <repo>"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Repo)) {
    Write-Step "no -Repo: tools only. PyInstaller comes later from the repo setup_build_env.bat"
    Write-Next "If packing: bootstrap_pack_tools.ps1 -Repo <client_repo>   then pack_client.cmd <client_repo>"
    exit 0
}

try {
    $Repo = [IO.Path]::GetFullPath($Repo)
} catch {
    Write-Host "RESULT=FAIL"
    Write-Next ("bad -Repo path: " + $Repo)
    exit 1
}

$setupBat = Join-Path $Repo "setup_build_env.bat"
if (-not (Test-Path -LiteralPath $setupBat)) {
    Write-Host "RESULT=FAIL"
    Write-Next ("-Repo has no setup_build_env.bat: " + $Repo)
    exit 1
}

Write-Step "ensure conda env golgi-build exists as Python 3.8 64-bit (conda-forge 3.8.20)"
$probeEnv = & $condaBat run -n golgi-build python -c "import sys,struct; raise SystemExit(0 if sys.version_info[:2]==(3,8) and struct.calcsize('P')*8==64 else 2)" 2>$null
$probeCode = $LASTEXITCODE
if ($probeCode -ne 0) {
    Write-Step "creating conda env golgi-build python=3.8.20 -c conda-forge"
    & $condaBat create -y -n golgi-build python=3.8.20 pip -c conda-forge
    if ($LASTEXITCODE -ne 0) {
        Write-Host "RESULT=FAIL"
        Write-Next "conda create golgi-build python=3.8.20 -c conda-forge failed"
        exit 1
    }
}

Write-Step ("running setup_build_env.bat in " + $Repo)
Write-Step "this pip-installs PySide6==6.6.2, shiboken6==6.6.2, pyinstaller==6.20.0 into golgi-build"
$env:GOLGI_NOPAUSE = "1"
if ($ffmpeg) { $env:GOLGI_FFMPEG = $ffmpeg }
# PyPI on company networks often stalls on large wheels (PySide6/pywin32).
$env:PIP_DEFAULT_TIMEOUT = "300"
$env:PIP_RETRIES = "15"
$setupProc = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", "call", $setupBat) -WorkingDirectory $Repo -Wait -PassThru -NoNewWindow
$setupCode = $setupProc.ExitCode
if ($setupCode -ne 0) {
    Write-Host "RESULT=FAIL"
    Write-Next ("setup_build_env.bat exit " + $setupCode + ". If Python 3.8 env already exists but is wrong: conda remove -n golgi-build --all then re-run.")
    exit 1
}

Write-Host "RESULT=ENV_READY"
Write-Next ("run pack: " + (Join-Path $PSScriptRoot "pack_client.cmd") + " " + $Repo)
exit 0
