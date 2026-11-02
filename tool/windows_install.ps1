# Installation MSIX Authentik v2 (certificat + paquet, admin). Erreur 0x800B0109 si .msix seul.
param([string]$PackageDir = '')

$ErrorActionPreference = 'Stop'
$PublisherCerName = 'Authentik_v2_Publisher.cer'
$PackageName = 'com.acatech.authentik.v2'
$InstallLog = Join-Path $env:TEMP 'authentik_install.log'

function Write-Log([string]$Message) {
  Add-Content -LiteralPath $InstallLog -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -Encoding UTF8
}

function Test-Admin {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ToolRoot {
  if ((Split-Path $PSScriptRoot -Leaf) -eq 'dist') {
    return Split-Path $PSScriptRoot -Parent
  }
  return $PSScriptRoot
}

function Get-ProjectRoot {
  return Split-Path (Get-ToolRoot) -Parent
}

function Find-PackageDir([string]$Hint) {
  $tool = Get-ToolRoot
  $project = Get-ProjectRoot
  foreach ($dir in @($Hint, $PSScriptRoot, (Join-Path $tool 'dist'), (Join-Path $project 'build\windows\x64\runner\Release'))) {
    if ($dir -and (Test-Path (Join-Path $dir 'Authentik_v2.msix'))) { return (Resolve-Path $dir).Path }
  }
  return $null
}

function Get-CerPath([string]$Folder) {
  $p = Join-Path $Folder $PublisherCerName
  if (Test-Path -LiteralPath $p) { return $p }
  $legacy = Join-Path $Folder 'authentik_codesign.cer'
  if (Test-Path -LiteralPath $legacy) { return $legacy }
  return Join-Path (Join-Path (Get-ToolRoot) 'signing') 'authentik_codesign.cer'
}

function Get-PublisherThumbprint([string]$CerPath) {
  if (-not (Test-Path -LiteralPath $CerPath)) { return $null }
  return (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CerPath)).Thumbprint
}

function Test-PublisherTrusted([string]$CerPath) {
  $thumb = Get-PublisherThumbprint $CerPath
  if (-not $thumb) { return $false }
  $root = Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue
  return [bool]($root | Where-Object { $_.Thumbprint -eq $thumb })
}

function Install-PublisherTrust {
  param([string]$CerPath, [string]$MsixPath)
  if ($CerPath -and (Test-Path -LiteralPath $CerPath) -and -not (Test-PublisherTrusted $CerPath)) {
    Write-Log "certutil Root $CerPath"
    $null = & certutil.exe -addstore -f Root $CerPath 2>&1
    $null = & certutil.exe -addstore -f TrustedPeople $CerPath 2>&1
  }
  if (Test-PublisherTrusted $CerPath) { return }

  $sig = Get-AuthenticodeSignature -FilePath $MsixPath
  if (-not $sig.SignerCertificate) { throw 'Signature MSIX illisible.' }
  $tmp = Join-Path $env:TEMP 'authentik_signer.cer'
  [IO.File]::WriteAllBytes($tmp, $sig.SignerCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
  $null = & certutil.exe -addstore -f Root $tmp 2>&1
  $null = & certutil.exe -addstore -f TrustedPeople $tmp 2>&1
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  if (-not (Test-PublisherTrusted $CerPath)) {
    $t = $sig.SignerCertificate.Thumbprint
    if (-not (Get-ChildItem Cert:\LocalMachine\Root | Where-Object Thumbprint -eq $t)) {
      throw 'Certificat racine non approuvé (0x800B0109). UAC administrateur requis.'
    }
  }
}

function Install-Msix([string]$MsixPath) {
  $temp = Join-Path $env:TEMP ("Authentik_v2_" + [guid]::NewGuid().ToString('N') + '.msix')
  Copy-Item -LiteralPath $MsixPath -Destination $temp -Force
  try {
    Add-AppxPackage -Path $temp -ForceApplicationShutdown -ForceUpdateFromAnyVersion
  } finally {
    Remove-Item $temp -Force -ErrorAction SilentlyContinue
  }
}

if (-not (Test-Admin)) {
  $dir = Find-PackageDir $PackageDir
  $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  if ($dir) { $arg += " -PackageDir `"$dir`"" }
  Write-Log "UAC: $arg"
  $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList $arg
  if ($p.ExitCode -ne 0) {
    Write-Host "Annulé ou échec UAC. Cliquez Oui (administrateur)." -ForegroundColor Red
    exit 1
  }
  exit 0
}

$PackageDir = Find-PackageDir $PackageDir
if (-not $PackageDir) {
  Write-Host "Authentik_v2.msix introuvable. Lancez Build-MSIX.bat." -ForegroundColor Red
  exit 1
}

$msix = Join-Path $PackageDir 'Authentik_v2.msix'
$cer = Get-CerPath $PackageDir

Write-Host "=== Authentik v2 ===" -ForegroundColor Cyan
Write-Host "[1/2] Certificat éditeur…"
Install-PublisherTrust -CerPath $cer -MsixPath $msix
Write-Host "[2/2] Paquet MSIX…"
Install-Msix $msix
Write-Host "Installé. Menu Démarrer → Authentik v2" -ForegroundColor Green
