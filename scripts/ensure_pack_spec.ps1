# Copy the onedir spec that build_and_pack.bat names, if the client checkout
# does not have it. Never overwrite an existing file.
# Usage: ensure_pack_spec.ps1 <client_repo>
param(
    [Parameter(Position = 0)]
    [string]$Repo = ""
)

$ErrorActionPreference = "Continue"
if ([string]::IsNullOrWhiteSpace($Repo)) {
    $Repo = (Get-Location).Path
}
try {
    $Repo = [IO.Path]::GetFullPath($Repo)
} catch {
    Write-Host ("[spec] bad repo path: " + $Repo)
    exit 1
}

$templateDir = Join-Path (Split-Path -Parent $PSScriptRoot) "templates"
$batPath = Join-Path $Repo "build_and_pack.bat"
$needed = @()
if (Test-Path -LiteralPath $batPath) {
    $raw = Get-Content -LiteralPath $batPath -Raw -ErrorAction SilentlyContinue
    if ($raw) {
        foreach ($m in [regex]::Matches($raw, "['""]([^'""\\]+\.spec)['""]")) {
            $needed += [IO.Path]::GetFileName($m.Groups[1].Value)
        }
    }
}
$needed = @($needed | Select-Object -Unique)
if ($needed.Count -eq 0) {
    $needed = @("Golgi_fNIRS_community.spec")
}

$copied = 0
foreach ($name in $needed) {
    $dest = Join-Path $Repo $name
    if (Test-Path -LiteralPath $dest) {
        Write-Host ("[spec] already present: " + $name)
        continue
    }
    $src = Join-Path $templateDir $name
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host ("[spec] missing " + $name + " and no template at " + $src)
        continue
    }
    Copy-Item -LiteralPath $src -Destination $dest
    Write-Host ("[spec] copied template " + $name + " into client checkout (git did not have this file)")
    $copied++
}
if ($copied -eq 0 -and -not (Get-ChildItem -LiteralPath $Repo -Filter "*.spec" -File -ErrorAction SilentlyContinue)) {
    Write-Host "[spec] no spec in client checkout and no matching template"
    exit 1
}
exit 0
