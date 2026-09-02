# Updates every release-coupled UE Tool Suite version reference in one transaction.

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
  [Parameter(Mandatory)]
  [ValidatePattern('^\d+\.\d+\.\d+$')]
  [string]$Version
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifestPath = Join-Path $repoRoot 'payload\ue-tool-suite.manifest.json'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "Payload manifest not found: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$currentVersion = [string]$manifest.payloadVersion
if ($currentVersion -notmatch '^\d+\.\d+\.\d+$') {
  throw "Current payload version '$currentVersion' is not a stable three-part version."
}
if ($Version -ceq $currentVersion) {
  throw "The repository is already version $Version."
}
if ([version]$Version -le [version]$currentVersion) {
  throw "New version '$Version' must be greater than current version '$currentVersion'."
}

$requiredRelativePaths = @(
  'payload\ue-tool-suite.manifest.json',
  'payload\docs-managed-file-index.json',
  'payload\website-managed-file-index.json',
  'payload\Scripts\UETools\UETools.psd1',
  'Scripts\Publish-InstallerExe.ps1',
  'src\UEToolSuiteInstaller.Gui\app.manifest',
  'Tests\Test-Install-UEToolSuite.ps1',
  'Tests\Test-PackagingContracts.ps1',
  'Tests\Test-UpgradeCompatibility.ps1'
)

$optionalDocumentationPaths = @(
  'README.md',
  'MAINTAINER_GUIDE.md',
  'docs\Usage-Build-Release-Guide.md',
  'docs\EXE-Code-Signing-Certificate-Guide.md',
  'docs\DeveloperDocs\19-Command-Reference.md'
)

$changes = [Collections.Generic.List[object]]::new()
foreach ($relativePath in $requiredRelativePaths) {
  $path = Join-Path $repoRoot $relativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Required version-coupled file is missing: $relativePath"
  }

  $original = [IO.File]::ReadAllText($path)
  if (-not $original.Contains($currentVersion, [StringComparison]::Ordinal)) {
    throw "Required version-coupled file does not contain current version '$currentVersion': $relativePath"
  }
  $changes.Add([pscustomobject]@{
      RelativePath = $relativePath
      Path = $path
      Original = $original
      Updated = $original.Replace($currentVersion, $Version, [StringComparison]::Ordinal)
    })
}

foreach ($relativePath in $optionalDocumentationPaths) {
  $path = Join-Path $repoRoot $relativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    continue
  }

  $original = [IO.File]::ReadAllText($path)
  if (-not $original.Contains($currentVersion, [StringComparison]::Ordinal)) {
    continue
  }
  $changes.Add([pscustomobject]@{
      RelativePath = $relativePath
      Path = $path
      Original = $original
      Updated = $original.Replace($currentVersion, $Version, [StringComparison]::Ordinal)
    })
}

Write-Host "UE Tool Suite version bump: $currentVersion -> $Version" -ForegroundColor Cyan
foreach ($change in $changes) {
  Write-Host "  $($change.RelativePath)"
}

if (-not $PSCmdlet.ShouldProcess($repoRoot, "Update UE Tool Suite version from $currentVersion to $Version in $($changes.Count) files")) {
  return
}

$written = [Collections.Generic.List[object]]::new()
try {
  foreach ($change in $changes) {
    [IO.File]::WriteAllText($change.Path, $change.Updated, [Text.UTF8Encoding]::new($false))
    $written.Add($change)
  }

  $updatedManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  if ([string]$updatedManifest.payloadVersion -cne $Version) {
    throw "Version bump verification failed: payload manifest did not update to '$Version'."
  }
}
catch {
  foreach ($change in $written) {
    [IO.File]::WriteAllText($change.Path, $change.Original, [Text.UTF8Encoding]::new($false))
  }
  throw
}

Write-Host "Version updated to $Version. Review and commit the changes before publishing." -ForegroundColor Green
