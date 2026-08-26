# Check Golgi client pack env. ASCII-only. No secrets.
# Exit 0 READY, 2 NEEDS_SETUP, 1 FAIL.
param(
    [Parameter(Position = 0)]
    [string]$Repo = ""
)

$ErrorActionPreference = "Continue"
$hardFail = 0
$needSetup = 0

function Test-NonAscii([string]$Text) {
    foreach ($ch in $Text.ToCharArray()) {
        if ([int][char]$ch -gt 127) { return $true }
    }
    return $false
}

function Write-Check {
    param(
        [string]$Name,
        [ValidateSet("PASS", "FAIL")]
        [string]$Status,
        [string]$Detail
    )
    Write-Host ("[{0}] {1}: {2}" -f $Status, $Name, $Detail)
}

function Invoke-CondaPython {
    param(
        [string]$CondaBat,
        [string]$EnvName,
        [string]$Code
    )
    # Isolated dir: $env:TEMP often has leftover inspect.py / sitecustomize that
    # shadow stdlib because python puts the script directory on sys.path[0].
    $work = Join-Path $env:TEMP ("golgi_pack_check_" + [guid]::NewGuid().ToString("n"))
    New-Item -ItemType Directory -Path $work | Out-Null
    $tmp = Join-Path $work "probe.py"
    Set-Content -LiteralPath $tmp -Value $Code -Encoding ASCII
    try {
        # conda.bat must be invoked as a .bat; do not assume a PowerShell conda function.
        $output = & $CondaBat run -n $EnvName python $tmp 2>&1
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = 1 }
        return [pscustomobject]@{
            ExitCode = $code
            Output   = @($output | ForEach-Object { "$_" })
        }
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-TextLines([object]$Raw) {
    $text = ($Raw | ForEach-Object { "$_" }) -join "`n"
    return @(
        $text -split "`r?`n" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" }
    )
}

if ([string]::IsNullOrWhiteSpace($Repo)) {
    $Repo = (Get-Location).Path
}
try {
    $Repo = [IO.Path]::GetFullPath($Repo)
}
catch {
    Write-Check -Name "repo" -Status "FAIL" -Detail "Cannot resolve path: $Repo"
    Write-Host "RESULT=FAIL"
    exit 1
}

$envName = "golgi-build"
if (-not [string]::IsNullOrWhiteSpace($env:GOLGI_BUILD_ENV)) {
    $envName = $env:GOLGI_BUILD_ENV
}

Write-Host "=== client pack env check ==="
Write-Host ("Repo: {0}" -f $Repo)
Write-Host ("Env : {0}" -f $envName)

function Resolve-OnedirSpec([string]$Root) {
    $hits = @()
    Get-ChildItem -LiteralPath $Root -Filter "*.spec" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $raw = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($raw)) { return }
        if ($raw -notmatch "COLLECT") { return }
        $exe = $null
        $nameMatches = [regex]::Matches($raw, "name\s*=\s*'([^']+)'")
        if ($nameMatches.Count -eq 0) {
            $nameMatches = [regex]::Matches($raw, 'name\s*=\s*"([^"]+)"')
        }
        if ($nameMatches.Count -gt 0) {
            $exe = $nameMatches[$nameMatches.Count - 1].Groups[1].Value
        }
        $hits += [pscustomobject]@{
            SpecFile = $_.Name
            SpecPath = $_.FullName
            ExeName  = $exe
            Raw      = $raw
        }
    }
    if ($hits.Count -eq 0) { return $null }
    $hits = @($hits | Sort-Object { $_.SpecFile.Length } -Descending)
    $batPath = Join-Path $Root "build_and_pack.bat"
    if (Test-Path -LiteralPath $batPath) {
        $bat = Get-Content -LiteralPath $batPath -Raw -ErrorAction SilentlyContinue
        foreach ($h in $hits) {
            $token = '(?<![A-Za-z0-9_])' + [regex]::Escape($h.SpecFile) + '(?![A-Za-z0-9_])'
            if ($bat -and ($bat -match $token)) { return $h }
        }
    }
    return $hits[0]
}

$specInfo = Resolve-OnedirSpec $Repo
if ($null -ne $specInfo) {
    Write-Host ("Found spec: {0}" -f $specInfo.SpecFile)
    if ($specInfo.ExeName) { Write-Host ("Found exe name in spec: {0}" -f $specInfo.ExeName) }
}
Write-Host ""

# --- path ASCII ---
if (Test-NonAscii $Repo) {
    Write-Check -Name "path-ascii" -Status "FAIL" -Detail "Non-ASCII in project path. Move to ASCII-only path (no Chinese)."
    $hardFail++
}
else {
    Write-Check -Name "path-ascii" -Status "PASS" -Detail $Repo
}

# --- repo identity + required files ---
$requiredFiles = @(
    "gorky.png",
    "bgkd.png",
    "SimSun.ttf",
    "SimHei.ttf",
    "GreenTek_v4.json",
    "valid_channel.json",
    "fnirs_app\config\defaults.toml",
    "VERSION.txt",
    "installer.iss",
    "build_and_pack.bat",
    "setup_build_env.bat",
    "requirements.txt"
)
if ($null -ne $specInfo) {
    $requiredFiles += $specInfo.SpecFile
}

$missing = @()
if ($null -eq $specInfo) {
    $missing += "onedir .spec (a *.spec next to build_and_pack.bat that contains COLLECT)"
}
foreach ($rel in $requiredFiles) {
    $full = Join-Path $Repo $rel
    if (-not (Test-Path -LiteralPath $full)) {
        $missing += $rel
    }
}

$wavRoots = @(
    "addfiles\audio_pool_template\fixed",
    "addfiles\audio_pool_template\say_word",
    "addfiles\audio_pool_template\say_word\word_grouping",
    "addfiles\audio_pool_template\dichotic"
)
$wavMissing = @()
foreach ($rel in $wavRoots) {
    $dir = Join-Path $Repo $rel
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        $wavMissing += "$rel (dir missing)"
        continue
    }
    $wavs = @(Get-ChildItem -LiteralPath $dir -Filter *.wav -Recurse -File -ErrorAction SilentlyContinue)
    if ($wavs.Count -lt 1) {
        $wavMissing += "$rel (no .wav)"
    }
}

if ($missing.Count -gt 0 -or $wavMissing.Count -gt 0) {
    $bits = @()
    if ($missing.Count -gt 0) { $bits += ("missing: " + ($missing -join ", ")) }
    if ($wavMissing.Count -gt 0) { $bits += ("wavs: " + ($wavMissing -join ", ")) }
    Write-Check -Name "required-files" -Status "FAIL" -Detail ($bits -join "; ")
    $hardFail++
}
else {
    Write-Check -Name "required-files" -Status "PASS" -Detail "core files + audio_pool_template wavs (fixed/say_word/word_grouping/dichotic)"
}

# spec / requirements sanity (repo content, not env)
if ($null -ne $specInfo) {
    $spec = Get-Content -LiteralPath $specInfo.SpecPath -Raw -ErrorAction SilentlyContinue
    $specBad = @()
    if ($spec -notmatch "COLLECT") { $specBad += "not onedir (no COLLECT)" }
    if ($spec -notmatch "console\s*=\s*False") { $specBad += "console is not False" }
    $exeEsc = [regex]::Escape($specInfo.ExeName)
    if ($spec -notmatch $exeEsc) { $specBad += ("missing name " + $specInfo.ExeName) }
    if ($specBad.Count -gt 0) {
        Write-Check -Name "spec" -Status "FAIL" -Detail ($specInfo.SpecFile + ": " + ($specBad -join "; ") + ". Need onedir (COLLECT), not onefile.")
        $hardFail++
    }
    else {
        Write-Check -Name "spec" -Status "PASS" -Detail ("onedir COLLECT, console=False, " + $specInfo.ExeName)
    }
}

$reqPath = Join-Path $Repo "requirements.txt"
if (Test-Path -LiteralPath $reqPath) {
    $req = Get-Content -LiteralPath $reqPath -ErrorAction SilentlyContinue
    $pinOk = $true
    $pinDetail = @()
    if (-not ($req | Where-Object { $_ -match '^\s*PySide6==6\.6\.2\s*$' })) {
        $pinOk = $false
        $pinDetail += "PySide6==6.6.2"
    }
    if (-not ($req | Where-Object { $_ -match '^\s*shiboken6==6\.6\.2\s*$' })) {
        $pinOk = $false
        $pinDetail += "shiboken6==6.6.2"
    }
    if (-not ($req | Where-Object { $_ -match '^\s*pyinstaller==6\.20\.0\s*$' })) {
        $pinOk = $false
        $pinDetail += "pyinstaller==6.20.0"
    }
    if ($pinOk) {
        Write-Check -Name "requirements-pin" -Status "PASS" -Detail "PySide6==6.6.2 shiboken6==6.6.2 pyinstaller==6.20.0"
    }
    else {
        Write-Check -Name "requirements-pin" -Status "FAIL" -Detail ("requirements.txt missing pins: " + ($pinDetail -join ", ") + ". Update this client checkout; do not use old onefile docs.")
        $hardFail++
    }
}

# --- VERSION.txt ---
$verPath = Join-Path $Repo "VERSION.txt"
if (-not (Test-Path -LiteralPath $verPath)) {
    Write-Check -Name "VERSION.txt" -Status "FAIL" -Detail "missing"
    $hardFail++
}
else {
    $verRaw = (Get-Content -LiteralPath $verPath -Raw -ErrorAction SilentlyContinue)
    if ($null -eq $verRaw) { $verRaw = "" }
    $verRaw = $verRaw.Trim().Trim([char]0xFEFF)
    if ($verRaw -match '^[Vv]?[0-9]+(\.[0-9]+)*$') {
        $verNum = $verRaw
        if ($verNum.Substring(0, 1) -match '[Vv]') {
            $verNum = $verNum.Substring(1)
        }
        Write-Check -Name "VERSION.txt" -Status "PASS" -Detail ("{0} -> V{1}" -f $verRaw, $verNum)
    }
    else {
        Write-Check -Name "VERSION.txt" -Status "FAIL" -Detail ("invalid '{0}', expected 1.0 | 1.0.0 | V1.0" -f $verRaw)
        $hardFail++
    }
}

# --- conda.bat ---
$condaBat = $null
$whereOut = & where.exe conda.bat 2>$null
if ($whereOut) {
    $condaBat = (@($whereOut) | Select-Object -First 1).ToString().Trim()
}
if (-not $condaBat -or -not (Test-Path -LiteralPath $condaBat)) {
    $hintPaths = @(
        (Join-Path $env:USERPROFILE "miniconda3\condabin\conda.bat"),
        (Join-Path $env:USERPROFILE "anaconda3\condabin\conda.bat"),
        (Join-Path $env:USERPROFILE "Miniconda3\condabin\conda.bat"),
        (Join-Path $env:USERPROFILE "Anaconda3\condabin\conda.bat"),
        (Join-Path $env:USERPROFILE "scoop\apps\miniconda3\current\condabin\conda.bat"),
        "C:\ProgramData\miniconda3\condabin\conda.bat",
        "C:\ProgramData\Anaconda3\condabin\conda.bat",
        "C:\ProgramData\miniconda3\Scripts\conda.bat",
        "C:\ProgramData\Anaconda3\Scripts\conda.bat"
    )
    $foundHint = @($hintPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
    $boot = Join-Path $PSScriptRoot "bootstrap_pack_tools.ps1"
    $msg = "conda.bat not on PATH. ACT: powershell -NoProfile -ExecutionPolicy Bypass -File `"$boot`""
    if ($foundHint.Count -gt 0) {
        $msg = $msg + ("  Found off-PATH: {0}. Add that condabin to PATH or conda init cmd.exe." -f $foundHint[0])
    }
    Write-Check -Name "conda.bat" -Status "FAIL" -Detail $msg
    $hardFail++
    $condaBat = $null
}
else {
    Write-Check -Name "conda.bat" -Status "PASS" -Detail $condaBat
}

# --- golgi-build python + pins ---
if ($null -ne $condaBat) {
    $probe = Invoke-CondaPython -CondaBat $condaBat -EnvName $envName -Code @"
import sys, struct
print("Python=%d.%d" % (sys.version_info[0], sys.version_info[1]))
print("PythonFull=" + sys.version.split()[0])
print("Arch=%d" % (struct.calcsize("P") * 8))
print("Exe=" + sys.executable)
"@
    $probeText = ($probe.Output -join "`n")
    $envMissing = ($probe.ExitCode -ne 0) -and (
        $probeText -match "Could not find conda environment" -or
        $probeText -match "EnvironmentLocationNotFound" -or
        $probeText -match "Not a conda environment"
    )

    if ($envMissing -or ($probe.ExitCode -ne 0 -and $probeText -notmatch "Python=")) {
        Write-Check -Name "golgi-build-python" -Status "FAIL" -Detail ("env '{0}' missing or not runnable. Fix: setup_build_env.bat" -f $envName)
        $needSetup++
        Write-Check -Name "pinned-packages" -Status "FAIL" -Detail "skipped (env not runnable)"
        $needSetup++
    }
    else {
        $kv = @{}
        foreach ($line in (Get-TextLines $probe.Output)) {
            if ($line -match '^(Python|PythonFull|Arch|Exe)=(.*)$') {
                $kv[$matches[1]] = $matches[2]
            }
        }
        $pyMm = $kv["Python"]
        $pyFull = $kv["PythonFull"]
        $arch = $kv["Arch"]
        $pyExe = $kv["Exe"]
        $pyOk = ($pyMm -eq "3.8")
        $archOk = ($arch -eq "64")
        if ($pyOk -and $archOk) {
            $note = ""
            if ($pyFull -and $pyFull -ne "3.8.20") {
                $note = " (setup_build_env creates 3.8.20; pack only requires 3.8)"
            }
            Write-Check -Name "golgi-build-python" -Status "PASS" -Detail ("{0} {1}-bit {2}{3}" -f $pyFull, $arch, $pyExe, $note)
        }
        else {
            $why = @()
            if (-not $pyOk) { $why += ("Python {0} (need 3.8)" -f $(if ($pyFull) { $pyFull } else { $pyMm })) }
            if (-not $archOk) { $why += ("arch {0}-bit (need 64)" -f $arch) }
            Write-Check -Name "golgi-build-python" -Status "FAIL" -Detail (
                ("{0}. setup_build_env.bat REUSES this env and will not fix Python. conda remove -n {1} --all then setup_build_env.bat. exe={2}" -f ($why -join "; "), $envName, $pyExe)
            )
            $hardFail++
        }

        $pkg = Invoke-CondaPython -CondaBat $condaBat -EnvName $envName -Code @"
import PySide6, shiboken6, PyInstaller, scipy, pyqtgraph, serial, PIL
print("PySide6=" + PySide6.__version__)
print("shiboken6=" + shiboken6.__version__)
print("PyInstaller=" + PyInstaller.__version__)
"@
        if ($pkg.ExitCode -ne 0) {
            Write-Check -Name "pinned-packages" -Status "FAIL" -Detail "import failed (need PySide6 6.6.2, shiboken6 6.6.2, PyInstaller 6.20.0, scipy, pyqtgraph, pyserial, Pillow). Fix: setup_build_env.bat"
            $needSetup++
        }
        else {
            $got = @{}
            foreach ($line in (Get-TextLines $pkg.Output)) {
                if ($line -match '^(PySide6|shiboken6|PyInstaller)=(.*)$') {
                    $got[$matches[1]] = $matches[2]
                }
            }
            $reqMap = @{
                PySide6     = "6.6.2"
                shiboken6   = "6.6.2"
                PyInstaller = "6.20.0"
            }
            $bad = @()
            foreach ($k in @("PySide6", "shiboken6", "PyInstaller")) {
                if ($got[$k] -ne $reqMap[$k]) {
                    $bad += ("{0}: required {1}, got {2}" -f $k, $reqMap[$k], $(if ($got.ContainsKey($k)) { $got[$k] } else { "?" }))
                }
            }
            if ($bad.Count -gt 0) {
                Write-Check -Name "pinned-packages" -Status "FAIL" -Detail (($bad -join "; ") + ". Fix: setup_build_env.bat")
                $needSetup++
            }
            else {
                Write-Check -Name "pinned-packages" -Status "PASS" -Detail "Python=3.8 PySide6=6.6.2 shiboken6=6.6.2 PyInstaller=6.20.0"
            }
        }
    }
}
else {
    Write-Check -Name "golgi-build-python" -Status "FAIL" -Detail "skipped (no conda.bat)"
    Write-Check -Name "pinned-packages" -Status "FAIL" -Detail "skipped (no conda.bat)"
}

# --- ISCC ---
$iscc = $null
if (-not [string]::IsNullOrWhiteSpace($env:GOLGI_ISCC)) {
    $iscc = $env:GOLGI_ISCC
}
if (-not $iscc -or -not (Test-Path -LiteralPath $iscc)) {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 7\ISCC.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) {
            $iscc = $c
            break
        }
    }
}
if ($iscc -and (Test-Path -LiteralPath $iscc)) {
    Write-Check -Name "ISCC" -Status "PASS" -Detail $iscc
}
else {
    $boot = Join-Path $PSScriptRoot "bootstrap_pack_tools.ps1"
    $hint = "ISCC.exe missing. ACT: powershell -NoProfile -ExecutionPolicy Bypass -File `"$boot`". Do not install Inno 5."
    if ($env:GOLGI_ISCC) {
        $hint = ("GOLGI_ISCC not found: {0}. {1}" -f $env:GOLGI_ISCC, $hint)
    }
    Write-Check -Name "ISCC" -Status "FAIL" -Detail $hint
    $hardFail++
}

Write-Host ""
if ($hardFail -gt 0) {
    Write-Host ("RESULT=FAIL  hard={0} setup={1}" -f $hardFail, $needSetup)
    Write-Host "See client-pack\references\pitfalls.md"
    exit 1
}
if ($needSetup -gt 0) {
    Write-Host "RESULT=NEEDS_SETUP"
    Write-Host "Next: run setup_build_env.bat in the repo (pack_client.cmd does this)."
    exit 2
}
Write-Host "RESULT=READY"
exit 0
