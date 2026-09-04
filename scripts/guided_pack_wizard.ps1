# Guided CMD wizard for client pack tools. UTF-8 with BOM.
# Colleague: double-click the ASCII .cmd wrappers (they chcp 65001).
# Agent: add -AutoContinue so it does not wait for Enter.

[CmdletBinding()]
param(
    [ValidateSet("Install", "Pack", "All")]
    [string]$Mode = "All",
    [string]$Repo = "",
    [switch]$AutoContinue,
    [switch]$SkipEnv
)

$ErrorActionPreference = "Continue"
$utf8 = New-Object System.Text.UTF8Encoding $false
try {
    [Console]::InputEncoding = $utf8
    [Console]::OutputEncoding = $utf8
} catch {}
$OutputEncoding = $utf8

$ScriptDir = $PSScriptRoot
$SkillRoot = Split-Path -Parent $ScriptDir
$Bootstrap = Join-Path $ScriptDir "bootstrap_pack_tools.ps1"
$CheckPs1 = Join-Path $ScriptDir "check_pack_env.ps1"
$EnsureSpec = Join-Path $ScriptDir "ensure_pack_spec.ps1"
$PackCmd = Join-Path $ScriptDir "pack_client.cmd"

function Write-Banner([string]$Text) {
    Write-Host ""
    Write-Host "========================================"
    Write-Host ("  " + $Text)
    Write-Host "========================================"
}

function Wait-Step([string]$Title) {
    Write-Banner $Title
    if ($AutoContinue) {
        Write-Host "[auto] continue"
        return
    }
    $ans = Read-Host "按 Enter 继续；输入 q 再 Enter 退出"
    if ($ans -eq "q" -or $ans -eq "Q") {
        Write-Host "已退出。"
        exit 2
    }
}

if ([string]::IsNullOrWhiteSpace($Repo)) {
    $cwdBat = Join-Path (Get-Location).Path "build_and_pack.bat"
    if (Test-Path -LiteralPath $cwdBat) {
        $Repo = (Get-Location).Path
    } else {
        $parent = Split-Path -Parent $SkillRoot
        $found = @()
        if (Test-Path -LiteralPath $parent) {
            Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                if (Test-Path -LiteralPath (Join-Path $_.FullName "build_and_pack.bat")) {
                    $found += $_.FullName
                }
            }
        }
        if ($found.Count -eq 1) {
            $Repo = $found[0]
        } elseif ($found.Count -gt 1) {
            Write-Host "Found client checkouts with build_and_pack.bat:"
            $found | ForEach-Object { Write-Host ("  " + $_) }
            $Repo = $found[0]
            Write-Host ("Using: " + $Repo)
            Write-Host "Pass -Repo to pick another."
        }
    }
}
if (-not [string]::IsNullOrWhiteSpace($Repo)) {
    try { $Repo = [IO.Path]::GetFullPath($Repo) } catch { }
}

Write-Banner "客户端打包引导"
Write-Host ("模式 : " + $Mode)
Write-Host ("仓库 : " + $(if ($Repo) { $Repo } else { "(未指定)" }))
Write-Host "本窗口会一步一步往下走。每一步先说明，再等你按 Enter（自动模式除外）。"
Write-Host "顺序：1 说明  2 检查  3 安装工具  4 Python环境  5 打包"

Wait-Step "第 1/5 步  先看会做什么"
Write-Host "这不是给用户装客户端软件的安装向导。"
Write-Host "这里只装「打包用的工具」，必要时再打出安装包。"
Write-Host "Miniconda：Anaconda 官网安装包，静默安装。"
Write-Host "Inno Setup：官网 6.7.3，静默安装。"
Write-Host "ffmpeg：Gyan essentials 真二进制，静默解压。商店/scoop 的小 shim 不能用。"
Write-Host "PyInstaller：没有单独安装包，在 golgi-build 里 pip 安装。"
Write-Host "下载时本窗口会显示 10%、20% …… 进度。"

Wait-Step "第 2/5 步  检查这台电脑已经有什么"
if (-not [string]::IsNullOrWhiteSpace($Repo) -and (Test-Path -LiteralPath $EnsureSpec)) {
    Write-Host "若客户端缺 build_and_pack.bat 点名的 spec，会从 templates 拷一份（不覆盖已有文件）。"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $EnsureSpec $Repo
}
if ([string]::IsNullOrWhiteSpace($Repo)) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CheckPs1
} else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CheckPs1 $Repo
}
$checkCode = $LASTEXITCODE
Write-Host ("检查退出码=" + $checkCode)
if ($checkCode -eq 0) { Write-Host "结果：READY，工具和环境都齐" }
elseif ($checkCode -eq 2) { Write-Host "结果：NEEDS_SETUP，工具齐，还要跑 setup_build_env.bat" }
else { Write-Host "结果：FAIL。若提示缺 conda 或 ISCC，下一步会下载安装。" }

$needTools = $true
if ($checkCode -eq 0 -or $checkCode -eq 2) { $needTools = $false }

if ($Mode -eq "Install" -or $Mode -eq "All") {
    Wait-Step "第 3/5 步  安装 Miniconda、Inno Setup 6、ffmpeg（已有则跳过）"
    if (-not $needTools) {
        Write-Host "本机已有 conda 和 ISCC，跳过下载。"
    } else {
        Write-Host "开始安装。请看 [bootstrap] download N% 这些行。"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Bootstrap -ToolsOnly
        if ($LASTEXITCODE -ne 0) {
            Write-Host "工具安装失败。请看上面的 NEXT= 。"
            if (-not $AutoContinue) { Read-Host "按 Enter 关闭" }
            exit 1
        }
        Write-Host "工具这一步完成。"
    }
} else {
    Write-Host "本次不装工具（打包模式）。若缺 conda/ISCC，请先运行 一键安装打包工具.cmd"
}

$doEnv = ($Mode -eq "Install" -or $Mode -eq "All") -and (-not $SkipEnv) -and (-not [string]::IsNullOrWhiteSpace($Repo))
if ($doEnv) {
    Wait-Step "第 4/5 步  创建 golgi-build 并安装 PyInstaller 6.20.0"
    Write-Host "这一步可能要好几分钟，pip 日志会在窗口里刷。"
    $setupBat = Join-Path $Repo "setup_build_env.bat"
    if (-not (Test-Path -LiteralPath $setupBat)) {
        Write-Host ("找不到 setup_build_env.bat：" + $setupBat)
        exit 1
    }
    $env:GOLGI_NOPAUSE = "1"
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", "call", $setupBat) -WorkingDirectory $Repo -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) {
        Write-Host ("setup_build_env.bat 退出码 " + $p.ExitCode)
        if (-not $AutoContinue) { Read-Host "按 Enter 关闭" }
        exit 1
    }
    Write-Host "Python 环境这一步完成。"
} else {
    Write-Host "本次不跑 Python 环境安装。"
}

if ($Mode -eq "Pack" -or $Mode -eq "All") {
    if ([string]::IsNullOrWhiteSpace($Repo)) {
        Write-Host "没有仓库路径，无法打包。"
        exit 1
    }
    Wait-Step "第 5/5 步  开始打包（PyInstaller + Inno）"
    Write-Host "这一步可能要 10 到 20 分钟，日志会在窗口里刷。"
    $env:GOLGI_NOPAUSE = "1"
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", "call", $PackCmd, $Repo) -WorkingDirectory $Repo -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) {
        Write-Host ("打包失败，退出码 " + $p.ExitCode)
        if (-not $AutoContinue) { Read-Host "按 Enter 关闭" }
        exit 1
    }
    Write-Host "打包完成。请向上找 OUTPUT= 那一行。"
} else {
    Write-Host "本次不打包。下一步请运行 一键打包.cmd"
}

Write-Banner "全部结束"
if (-not $AutoContinue) { Read-Host "按 Enter 关闭窗口" }
exit 0
