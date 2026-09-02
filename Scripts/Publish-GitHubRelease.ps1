# Validates, builds, tags, and publishes a UE Tool Suite release from the local repository.

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidatePattern('^\d+\.\d+\.\d+$')]
  [string]$Version,

  [string]$Remote = "origin",
  [string]$Branch = "main",
  [switch]$Draft,
  [switch]$ValidateOnly,
  [string]$CertificateThumbprint,
  [string]$CertificatePath,
  [string]$CertificatePassword
)

$ErrorActionPreference = "Stop"

function Info([string]$Message) { Write-Host "[Release] $Message" -ForegroundColor Cyan }
function Warn([string]$Message) { Write-Host "[Release] $Message" -ForegroundColor Yellow }
function Ok([string]$Message) { Write-Host "[Release] $Message" -ForegroundColor Green }

function Assert-LastExitCode {
  param(
    [Parameter(Mandatory)][string]$Operation,
    [int]$ExitCode = $LASTEXITCODE
  )

  if ($ExitCode -ne 0) {
    throw "$Operation failed with exit code $ExitCode."
  }
}

function Invoke-ReleaseTest {
  param(
    [Parameter(Mandatory)][string]$PwshPath,
    [Parameter(Mandatory)][string]$TestRunnerPath,
    [string]$ExclusiveName
  )

  if ([string]::IsNullOrWhiteSpace($ExclusiveName)) {
    Info "Running the full non-mutating test suite..."
    & $PwshPath -NoLogo -NoProfile -ExecutionPolicy Bypass -File $TestRunnerPath -FailFast
    Assert-LastExitCode -Operation "Full non-mutating test suite"
    return
  }

  Info "Running exclusive test suite '$ExclusiveName'..."
  & $PwshPath -NoLogo -NoProfile -ExecutionPolicy Bypass -File $TestRunnerPath -IncludeExclusive -Name $ExclusiveName -FailFast
  Assert-LastExitCode -Operation "Exclusive test suite '$ExclusiveName'"
}

function Get-RemoteTagCommit {
  param(
    [Parameter(Mandatory)][string]$RemoteName,
    [Parameter(Mandatory)][string]$TagName
  )

  $lines = @(& git ls-remote --tags $RemoteName "refs/tags/$TagName" "refs/tags/$TagName^{}" 2>&1)
  Assert-LastExitCode -Operation "Remote tag lookup"
  if ($lines.Count -eq 0) {
    return $null
  }

  $direct = $null
  $peeled = $null
  foreach ($line in $lines) {
    if ([string]$line -notmatch '^(?<hash>[0-9a-fA-F]{40})\s+(?<ref>.+)$') {
      continue
    }
    if ($Matches.ref.EndsWith('^{}', [StringComparison]::Ordinal)) {
      $peeled = $Matches.hash.ToLowerInvariant()
    }
    else {
      $direct = $Matches.hash.ToLowerInvariant()
    }
  }

  if ($peeled) { return $peeled }
  return $direct
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$manifestPath = Join-Path $repoRoot "payload\ue-tool-suite.manifest.json"
$docsIndexPath = Join-Path $repoRoot "payload\docs-managed-file-index.json"
$websiteIndexPath = Join-Path $repoRoot "payload\website-managed-file-index.json"
$moduleManifestPath = Join-Path $repoRoot "payload\Scripts\UETools\UETools.psd1"
$testRunnerPath = Join-Path $repoRoot "Tests\Run-UEToolSuiteTests.ps1"
$installerPublisherPath = Join-Path $repoRoot "Scripts\Publish-InstallerExe.ps1"
$artifactPath = Join-Path $repoRoot "dist\UEToolSuiteInstaller-$Version-win-x64.exe"
$tagName = "v$Version"

Push-Location $repoRoot
try {
  Info "Preflight for $tagName in $repoRoot"

  foreach ($commandName in @('git', 'gh', 'pwsh')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
      throw "Required command '$commandName' was not found."
    }
  }
  foreach ($requiredPath in @($manifestPath, $docsIndexPath, $websiteIndexPath, $moduleManifestPath, $testRunnerPath, $installerPublisherPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
      throw "Required release file is missing: $requiredPath"
    }
  }

  & git rev-parse --is-inside-work-tree | Out-Null
  Assert-LastExitCode -Operation "Git repository check"

  $currentBranch = [string](& git branch --show-current 2>&1)
  Assert-LastExitCode -Operation "Current branch lookup"
  $currentBranch = $currentBranch.Trim()
  if ($currentBranch -cne $Branch) {
    throw "Release must run from branch '$Branch'; current branch is '$currentBranch'."
  }

  $dirtyPaths = @(& git status --porcelain 2>&1)
  Assert-LastExitCode -Operation "Working tree status check"
  if ($dirtyPaths.Count -gt 0) {
    throw "Release requires a clean working tree. Commit or stash these paths:`n$($dirtyPaths -join "`n")"
  }

  Info "Refreshing $Remote/$Branch..."
  & git fetch --quiet $Remote $Branch
  Assert-LastExitCode -Operation "Git fetch for $Remote/$Branch"

  $headCommit = ([string](& git rev-parse HEAD 2>&1)).Trim().ToLowerInvariant()
  Assert-LastExitCode -Operation "HEAD lookup"
  $remoteBranchCommit = ([string](& git rev-parse "$Remote/$Branch" 2>&1)).Trim().ToLowerInvariant()
  Assert-LastExitCode -Operation "$Remote/$Branch lookup"
  if ($headCommit -cne $remoteBranchCommit) {
    throw "HEAD ($headCommit) must exactly match $Remote/$Branch ($remoteBranchCommit) before release. Push the release commit first."
  }

  & gh auth status | Out-Null
  Assert-LastExitCode -Operation "GitHub CLI authentication check"

  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  $docsIndex = Get-Content -LiteralPath $docsIndexPath -Raw | ConvertFrom-Json
  $websiteIndex = Get-Content -LiteralPath $websiteIndexPath -Raw | ConvertFrom-Json
  $moduleManifest = Import-PowerShellDataFile -LiteralPath $moduleManifestPath
  $declaredVersions = [ordered]@{
    'payload/ue-tool-suite.manifest.json' = [string]$manifest.payloadVersion
    'payload/docs-managed-file-index.json' = [string]$docsIndex.payloadVersion
    'payload/website-managed-file-index.json' = [string]$websiteIndex.payloadVersion
    'payload/Scripts/UETools/UETools.psd1' = [string]$moduleManifest.ModuleVersion
  }
  foreach ($entry in $declaredVersions.GetEnumerator()) {
    if ($entry.Value -cne $Version) {
      throw "Requested version '$Version' does not match $($entry.Key) version '$($entry.Value)'."
    }
  }

  $localTagCommit = $null
  & git show-ref --verify --quiet "refs/tags/$tagName"
  if ($LASTEXITCODE -eq 0) {
    $localTagCommit = ([string](& git rev-list -n 1 $tagName 2>&1)).Trim().ToLowerInvariant()
    Assert-LastExitCode -Operation "Local tag commit lookup"
    if ($localTagCommit -cne $headCommit) {
      throw "Local tag '$tagName' already points to $localTagCommit instead of HEAD $headCommit. Version tags are immutable; choose a new version."
    }
  }

  $remoteTagCommit = Get-RemoteTagCommit -RemoteName $Remote -TagName $tagName
  if ($remoteTagCommit -and $remoteTagCommit -cne $headCommit) {
    throw "Remote tag '$tagName' already points to $remoteTagCommit instead of HEAD $headCommit. Version tags are immutable; choose a new version."
  }

  $releaseLookup = @(& gh release view $tagName --json url 2>&1)
  $releaseLookupExit = $LASTEXITCODE
  if ($releaseLookupExit -eq 0) {
    throw "GitHub Release '$tagName' already exists. This script will not overwrite a published release."
  }
  if (($releaseLookup -join "`n") -notmatch '(?i)release not found') {
    throw "GitHub Release lookup failed:`n$($releaseLookup -join "`n")"
  }

  Ok "Preflight passed for $tagName at $headCommit."
  if ($ValidateOnly) {
    Ok "Validation-only run completed; no tests, build, tag, or release were created."
    return
  }

  $pwshPath = (Get-Command pwsh).Source
  Invoke-ReleaseTest -PwshPath $pwshPath -TestRunnerPath $testRunnerPath
  Invoke-ReleaseTest -PwshPath $pwshPath -TestRunnerPath $testRunnerPath -ExclusiveName 'ue-sync-automated'
  Invoke-ReleaseTest -PwshPath $pwshPath -TestRunnerPath $testRunnerPath -ExclusiveName 'binary-guard-fixes'

  Info "Building installer $artifactPath..."
  $publishArgs = @(
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $installerPublisherPath,
    '-Version', $Version
  )
  if (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
    $publishArgs += @('-CertificateThumbprint', $CertificateThumbprint)
  }
  if (-not [string]::IsNullOrWhiteSpace($CertificatePath)) {
    $publishArgs += @('-CertificatePath', $CertificatePath)
  }
  if ($null -ne $CertificatePassword) {
    $publishArgs += @('-CertificatePassword', $CertificatePassword)
  }
  & $pwshPath @publishArgs
  Assert-LastExitCode -Operation "Installer publish"
  if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
    throw "Installer publisher completed without creating the expected artifact: $artifactPath"
  }

  $signature = Get-AuthenticodeSignature -LiteralPath $artifactPath
  $signingRequested = -not [string]::IsNullOrWhiteSpace($CertificateThumbprint) -or -not [string]::IsNullOrWhiteSpace($CertificatePath)
  if ($signingRequested -and $signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    throw "Signing was requested, but the built installer signature status is '$($signature.Status)'."
  }
  if (-not $signingRequested -and $signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    Warn "The installer is unsigned. Windows may show a SmartScreen warning."
  }

  $artifactHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash
  Ok "Installer ready: $artifactPath"
  Info "SHA256: $artifactHash"

  if (-not $localTagCommit) {
    Info "Creating annotated local tag $tagName..."
    & git tag -a $tagName -m "UEToolSuiteInstaller $tagName"
    Assert-LastExitCode -Operation "Local tag creation"
  }
  if (-not $remoteTagCommit) {
    Info "Pushing $tagName to $Remote..."
    & git push $Remote "refs/tags/$tagName"
    Assert-LastExitCode -Operation "Tag push"
  }

  Info "Creating GitHub Release $tagName..."
  $releaseArgs = @(
    'release', 'create', $tagName,
    $artifactPath,
    '--verify-tag',
    '--title', "UE Tool Suite Installer $Version",
    '--generate-notes',
    '--notes', 'Download and run the Windows installer. PowerShell 7 is required on the target machine.'
  )
  if ($Draft) {
    $releaseArgs += '--draft'
  }
  & gh @releaseArgs
  Assert-LastExitCode -Operation "GitHub Release creation"

  $releaseJson = [string](& gh release view $tagName --json url,tagName,isDraft,assets 2>&1)
  Assert-LastExitCode -Operation "Published release verification"
  $release = $releaseJson | ConvertFrom-Json
  $assetNames = @($release.assets | ForEach-Object { [string]$_.name })
  if ($assetNames -notcontains (Split-Path -Leaf $artifactPath)) {
    throw "GitHub Release '$tagName' was created without the expected installer asset."
  }

  Ok "Published ${tagName}: $($release.url)"
  Info "SHA256: $artifactHash"
}
finally {
  Pop-Location
}
