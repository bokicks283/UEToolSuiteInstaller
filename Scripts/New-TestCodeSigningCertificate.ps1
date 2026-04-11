# Creates a self-signed code-signing certificate for local signing tests only.

[CmdletBinding()]
param(
  [string]$Subject = "CN=UE Tool Suite Installer Test Signing",
  [string]$OutputDirectory = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "dist\signing"),
  [Parameter(Mandatory)][securestring]$Password
)

$ErrorActionPreference = "Stop"

function Info($m) { Write-Host "[TestCodeSigningCert] $m" -ForegroundColor Cyan }
function Ok($m) { Write-Host "[TestCodeSigningCert] $m" -ForegroundColor Green }

$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory | Out-Null

Info "Creating self-signed test code-signing certificate..."
$certificate = New-SelfSignedCertificate `
  -Type CodeSigningCert `
  -Subject $Subject `
  -CertStoreLocation "Cert:\CurrentUser\My" `
  -KeyAlgorithm RSA `
  -KeyLength 3072 `
  -HashAlgorithm SHA256 `
  -NotAfter (Get-Date).AddYears(1)

$safeName = ($Subject -replace '^CN=', '') -replace '[^A-Za-z0-9._-]+', '-'
$pfxPath = Join-Path $resolvedOutputDirectory "$safeName.pfx"
$base64Path = Join-Path $resolvedOutputDirectory "$safeName.pfx.base64"

Export-PfxCertificate `
  -Cert ("Cert:\CurrentUser\My\" + $certificate.Thumbprint) `
  -FilePath $pfxPath `
  -Password $Password | Out-Null

[Convert]::ToBase64String([IO.File]::ReadAllBytes($pfxPath)) |
  Set-Content -LiteralPath $base64Path -NoNewline

Ok "Created test certificate."
Write-Host "  Thumbprint: $($certificate.Thumbprint)" -ForegroundColor Green
Write-Host "  PFX:        $pfxPath" -ForegroundColor Green
Write-Host "  Base64:     $base64Path" -ForegroundColor Green
Write-Host ""
Write-Host "This certificate is self-signed and intended for local signing tests only." -ForegroundColor Yellow
