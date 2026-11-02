# Certificat de signature MSIX (une seule fois). Clé privée : tool\signing\authentik_codesign.pfx (gitignored).
param([string]$Password = $env:AUTHENTIK_MSIX_CERT_PASSWORD)

$ErrorActionPreference = 'Stop'
if (-not $Password) {
  $pwFile = Join-Path $PSScriptRoot '.cert_password'
  if (Test-Path $pwFile) { $Password = (Get-Content $pwFile -Raw).Trim() }
}
if (-not $Password) {
  $Password = 'AuthentikDev2026!'
  Write-Host "Mot de passe dev par défaut. Production : AUTHENTIK_MSIX_CERT_PASSWORD"
}

$pfx = Join-Path $PSScriptRoot 'authentik_codesign.pfx'
$cer = Join-Path $PSScriptRoot 'authentik_codesign.cer'
$subject = 'CN=Authentik v2, O=ACATech, C=CD'

if (Test-Path $pfx) {
  Write-Host "Certificat existant : $pfx"
  if (-not (Test-Path $cer)) {
    $secure = ConvertTo-SecureString -String $Password -Force -AsPlainText
    try {
      $c = Import-PfxCertificate -FilePath $pfx -Password $secure -CertStoreLocation 'Cert:\CurrentUser\My' -Exportable
      Export-Certificate -Cert $c -FilePath $cer | Out-Null
      Remove-Item "Cert:\CurrentUser\My\$($c.Thumbprint)" -Force -ErrorAction SilentlyContinue
    } catch {
      Write-Warning "Export .cer : vérifiez AUTHENTIK_MSIX_CERT_PASSWORD"
    }
  }
  exit 0
}

Write-Host "Création du certificat : $subject"
$cert = New-SelfSignedCertificate `
  -Type Custom -Subject $subject -KeyUsage DigitalSignature `
  -FriendlyName 'Authentik v2 MSIX' -CertStoreLocation 'Cert:\CurrentUser\My' `
  -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')

$secure = ConvertTo-SecureString -String $Password -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $secure | Out-Null
Export-Certificate -Cert $cert -FilePath $cer | Out-Null
Write-Host "Enregistré : $pfx et $cer"
