# Build Windows release + MSIX + dossier tool\dist (MSIX + certificat public).
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

function Get-AppVersion {
  $yaml = Get-Content -LiteralPath 'pubspec.yaml' -Raw
  if ($yaml -notmatch '(?m)^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)(?:\+([0-9]+))?') {
    throw 'version introuvable dans pubspec.yaml (attendu : major.minor.patch+build)'
  }
  $major = [int]$Matches[1]
  $minor = [int]$Matches[2]
  $patch = [int]$Matches[3]
  $build = if ($Matches[4]) { [int]$Matches[4] } else { 0 }
  foreach ($n in @($major, $minor, $patch, $build)) {
    if ($n -lt 0 -or $n -gt 65535) {
      throw "Composant de version hors plage MSIX (0..65535) : $n"
    }
  }
  [pscustomobject]@{
    Flutter     = "$major.$minor.$patch+$build"
    BuildName   = "$major.$minor.$patch"
    BuildNumber = "$build"
    Msix        = "$major.$minor.$patch.$build"
  }
}

function Set-MsixVersionInPubspec([string]$MsixVersion) {
  $path = (Resolve-Path 'pubspec.yaml').Path
  $yaml = [System.IO.File]::ReadAllText($path)
  if ($yaml -notmatch '(?m)^\s*msix_version:\s*[\d.]+') {
    throw "msix_version introuvable dans pubspec.yaml (impossible de synchroniser $MsixVersion)"
  }
  if ($yaml -match "(?m)^\s*msix_version:\s*$([regex]::Escape($MsixVersion))\s*$") {
    return
  }
  $updated = [regex]::Replace(
    $yaml,
    '(?m)^(\s*msix_version:\s*)[\d.]+',
    "`${1}$MsixVersion",
    1
  )
  [System.IO.File]::WriteAllText($path, $updated)
}

& "$PSScriptRoot\signing\create_cert.ps1"

$certPassword = $env:AUTHENTIK_MSIX_CERT_PASSWORD
if (-not $certPassword -and (Test-Path "$PSScriptRoot\signing\.cert_password")) {
  $certPassword = (Get-Content "$PSScriptRoot\signing\.cert_password" -Raw).Trim()
}
if (-not $certPassword) { $certPassword = 'AuthentikDev2026!' }

$ver = Get-AppVersion
Set-MsixVersionInPubspec $ver.Msix
Write-Host "Version Flutter : $($ver.Flutter)"
Write-Host "Version MSIX    : $($ver.Msix)  (dérivée de version: X.Y.Z+N → X.Y.Z.N)"

python "$PSScriptRoot\generate_icons.py"
flutter pub get

Write-Host "Génération MSIX $($ver.Msix)…"
$msixArgs = @(
  'run', 'msix:create',
  '--certificate-password', $certPassword,
  '--version', $ver.Msix,
  '--windows-build-args', "--build-name=$($ver.BuildName) --build-number=$($ver.BuildNumber)",
  '--install-certificate', 'false'
)
& dart @msixArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$msix = Get-ChildItem "build\windows\x64\runner\Release\*.msix" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $msix) {
  Write-Host "ERREUR : aucun .msix produit." -ForegroundColor Red
  exit 1
}

$dist = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$cerSource = Join-Path $PSScriptRoot 'signing\authentik_codesign.cer'
if (-not (Test-Path $cerSource)) {
  Write-Host "ERREUR : certificat public manquant dans tool\signing\" -ForegroundColor Red
  exit 1
}

Copy-Item $msix.FullName (Join-Path $dist 'Authentik_v2.msix') -Force
Copy-Item $cerSource (Join-Path $dist 'Authentik_v2_Publisher.cer') -Force
Copy-Item (Join-Path $PSScriptRoot 'windows_install.ps1') (Join-Path $dist 'windows_install.ps1') -Force

$installBat = Join-Path $dist 'Install.bat'
@(
  '@echo off'
  'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows_install.ps1"'
) | Set-Content -LiteralPath $installBat -Encoding ascii

$readme = Join-Path $dist 'LISEZMOI.txt'
if (-not (Test-Path -LiteralPath $readme)) {
  @(
    'Authentik v2 — installation Windows (MSIX sideload)'
    ''
    '1. Double-cliquez sur Install.bat et acceptez l''UAC administrateur.'
    '2. Le script installe le certificat éditeur puis le paquet .msix.'
    ''
    'Ne pas ouvrir Authentik_v2.msix seul : Windows refuse un paquet'
    'non signé par une racine approuvée (erreur 0x800B0109).'
  ) | Set-Content -LiteralPath $readme -Encoding utf8
}

Write-Host ""
Write-Host "Version : $($ver.Msix)"
Write-Host "MSIX    : $($msix.FullName)"
Write-Host "Distribution : $dist"
Write-Host "  Authentik_v2.msix + Authentik_v2_Publisher.cer + Install.bat"
