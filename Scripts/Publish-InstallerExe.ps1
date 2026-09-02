# Publishes the public Windows GUI installer as a self-contained single-file exe.

[CmdletBinding()]
param(
  [string]$Version = "1.0.1",
  [string]$Configuration = "Release",
  [string]$Runtime = "win-x64",
  [string]$DotNetPath,
  [string]$CertificateThumbprint,
  [string]$CertificatePath,
  [string]$CertificatePassword,
  [string]$TimestampUrl = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"

function Info($m) { Write-Host "[PublishInstaller] $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "[PublishInstaller] $m" -ForegroundColor Yellow }
function Ok($m) { Write-Host "[PublishInstaller] $m" -ForegroundColor Green }

function Resolve-DotNet {
  param([string]$ExplicitPath)

  if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
    if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
      throw "DotNetPath does not exist: $ExplicitPath"
    }
    return (Resolve-Path -LiteralPath $ExplicitPath).Path
  }

  $candidates = @(
    "C:\Program Files\dotnet\dotnet.exe",
    "C:\Program Files (x86)\dotnet\dotnet.exe"
  )

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return $candidate
    }
  }

  $command = Get-Command dotnet -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  throw "dotnet was not found. Install the .NET 10 SDK and try again."
}

function Assert-DotNetSdk {
  param([Parameter(Mandatory)][string]$ResolvedDotNetPath)

  $sdks = @(& $ResolvedDotNetPath --list-sdks 2>$null)
  if ($LASTEXITCODE -ne 0 -or $sdks.Count -eq 0) {
    throw "No .NET SDK was found for '$ResolvedDotNetPath'. Install the .NET 10 SDK and try again."
  }

  $hasNet10 = $false
  foreach ($sdk in $sdks) {
    if ($sdk -match '^10\.') {
      $hasNet10 = $true
      break
    }
  }

  if (-not $hasNet10) {
    throw "The GUI installer targets .NET 10. Install the .NET 10 SDK and try again. SDKs found: $($sdks -join '; ')"
  }
}

function Find-SignTool {
  $command = Get-Command signtool -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $sdkRoots = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
    "$env:ProgramFiles\Windows Kits\10\bin"
  )

  foreach ($root in $sdkRoots) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
      continue
    }

    $candidate = Get-ChildItem -LiteralPath $root -Filter signtool.exe -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -like "*\x64\signtool.exe" } |
      Sort-Object FullName -Descending |
      Select-Object -First 1
    if ($candidate) {
      return $candidate.FullName
    }
  }

  return $null
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$projectPath = Join-Path $repoRoot "src\UEToolSuiteInstaller.Gui\UEToolSuiteInstaller.Gui.csproj"
if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
  throw "GUI project not found: $projectPath"
}

$resolvedDotNet = Resolve-DotNet -ExplicitPath $DotNetPath
Assert-DotNetSdk -ResolvedDotNetPath $resolvedDotNet

$numericVersion = if ($Version -match '^(?<numeric>\d+(?:\.\d+){0,3})') {
  $Matches.numeric
}
else {
  throw "Version must start with a numeric version, for example 1.0.1 or 1.0.1-beta. Value: $Version"
}

$publishRoot = Join-Path $repoRoot "dist"
$publishDir = Join-Path $publishRoot "gui-publish-$Runtime"
$artifactPath = Join-Path $publishRoot ("UEToolSuiteInstaller-{0}-{1}.exe" -f $Version, $Runtime)

if (Test-Path -LiteralPath $publishDir) {
  Remove-Item -LiteralPath $publishDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $publishDir | Out-Null
New-Item -ItemType Directory -Force -Path $publishRoot | Out-Null

Info "Publishing GUI installer..."
& $resolvedDotNet publish $projectPath `
  --configuration $Configuration `
  --runtime $Runtime `
  --self-contained true `
  -p:PublishSingleFile=true `
  -p:IncludeAllContentForSelfExtract=true `
  -p:EnableCompressionInSingleFile=true `
  -p:Version=$Version `
  -p:AssemblyVersion=$numericVersion `
  -p:FileVersion=$numericVersion `
  -p:InformationalVersion=$Version `
  --output $publishDir

if ($LASTEXITCODE -ne 0) {
  throw "dotnet publish failed with exit code $LASTEXITCODE."
}

$publishedExe = Join-Path $publishDir "UEToolSuiteInstaller.exe"
if (-not (Test-Path -LiteralPath $publishedExe -PathType Leaf)) {
  throw "Published installer exe was not found: $publishedExe"
}

Copy-Item -LiteralPath $publishedExe -Destination $artifactPath -Force

if (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint) -and -not [string]::IsNullOrWhiteSpace($CertificatePath)) {
  throw "Pass either -CertificateThumbprint or -CertificatePath, not both."
}

if (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint) -or -not [string]::IsNullOrWhiteSpace($CertificatePath)) {
  $signTool = Find-SignTool
  if (-not $signTool) {
    throw "signtool.exe was not found. Install the Windows SDK or add signtool to PATH."
  }

  if (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
    Info "Signing artifact with certificate thumbprint $CertificateThumbprint..."
    & $signTool sign /fd SHA256 /td SHA256 /tr $TimestampUrl /sha1 $CertificateThumbprint $artifactPath
  }
  else {
    if (-not (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) {
      throw "CertificatePath does not exist: $CertificatePath"
    }

    Info "Signing artifact with PFX certificate..."
    if ([string]::IsNullOrWhiteSpace($CertificatePassword)) {
      & $signTool sign /fd SHA256 /td SHA256 /tr $TimestampUrl /f $CertificatePath $artifactPath
    }
    else {
      & $signTool sign /fd SHA256 /td SHA256 /tr $TimestampUrl /f $CertificatePath /p $CertificatePassword $artifactPath
    }
  }

  if ($LASTEXITCODE -ne 0) {
    throw "signtool failed with exit code $LASTEXITCODE."
  }
}
else {
  Warn "Skipping code signing. Pass -CertificateThumbprint or -CertificatePath for a public release build."
}

Ok "Artifact: $artifactPath"
