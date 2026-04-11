# Installs or updates the portable UE 5 tooling payload into a target project.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(Mandatory)][string]$TargetRepoRoot,
  [string]$PayloadRoot,
  [string]$TargetUProjectPath,
  [switch]$RunInit,
  [switch]$SkipLfsPull,
  [switch]$SkipDocs,
  [switch]$SkipWebsite,
  [switch]$SkipTests,
  [switch]$SkipCodexTools,
  [switch]$SkipArtSourceTools,
  [switch]$SkipCodingStandardsTools,
  [switch]$SkipShellAliases,
  [switch]$SkipOptionalToolSetup,
  [switch]$SkipDocsSetup,
  [switch]$SkipDocsNpmInstall,
  [switch]$ForceDocsNpmInstall,
  [switch]$SkipDocsBridgeInstall,
  [switch]$SkipUnrealSync,
  [switch]$NoBuild,
  [switch]$NoRegen,
  [switch]$NoBackup,
  [switch]$NoLegacyCleanup
)

$ErrorActionPreference = "Stop"

function Info($m) { Write-Host "[UE Tool Suite Installer] $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "[UE Tool Suite Installer] $m" -ForegroundColor Yellow }
function Ok($m) { Write-Host "[UE Tool Suite Installer] $m" -ForegroundColor Green }

function Resolve-ExistingDirectory {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Name
  )

  $resolved = [System.IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
    throw "$Name does not exist or is not a directory: $resolved"
  }

  return (Resolve-Path -LiteralPath $resolved).Path
}

function Get-DefaultPayloadRoot {
  $scriptDir = Split-Path -Path $PSCommandPath -Parent
  if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    throw "Could not resolve installer script path. Pass -PayloadRoot explicitly."
  }

  return Join-Path $scriptDir "payload"
}

function Test-PathInsideRoot {
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Path
  )

  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $pathFull = [System.IO.Path]::GetFullPath($Path)
  return (
    $pathFull.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
    $pathFull.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
  )
}

function Resolve-TargetUProjectPath {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$UProjectPath
  )

  if (-not [string]::IsNullOrWhiteSpace($UProjectPath)) {
    $candidate = if ([System.IO.Path]::IsPathRooted($UProjectPath)) { $UProjectPath } else { Join-Path $RepoRoot $UProjectPath }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      throw "Target .uproject path does not exist: $candidate"
    }
    return (Resolve-Path -LiteralPath $candidate).Path
  }

  $uprojects = @(Get-ChildItem -LiteralPath $RepoRoot -Filter "*.uproject" -File -ErrorAction SilentlyContinue | Sort-Object Name)
  if ($uprojects.Count -eq 1) { return $uprojects[0].FullName }
  if ($uprojects.Count -eq 0) { throw "No .uproject file found in target repo root: $RepoRoot" }
  throw "Multiple .uproject files found in target repo root. Pass -TargetUProjectPath explicitly."
}

function Test-TargetLooksLikeUE5Project {
  param([Parameter(Mandatory)][string]$UProjectPath)

  $uprojectJson = Get-Content -LiteralPath $UProjectPath -Raw | ConvertFrom-Json
  $association = [string]$uprojectJson.EngineAssociation
  if ([string]::IsNullOrWhiteSpace($association)) {
    Warn "Target .uproject has no EngineAssociation. Continuing, but UE5 version could not be verified."
    return
  }

  if ($association -notmatch '^(UE_)?5(\.|$)') {
    Warn "Target EngineAssociation is '$association'. This installer is intended for UE 5 projects."
  }
}

function Copy-ToBackup {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$ExistingPath,
    [Parameter(Mandatory)][string]$BackupRoot
  )

  if ($NoBackup) { return }

  $backupPath = Join-Path $BackupRoot $RelativePath
  $backupParent = Split-Path -Path $backupPath -Parent
  if ($backupParent) {
    New-Item -ItemType Directory -Force -Path $backupParent | Out-Null
  }

  Copy-Item -LiteralPath $ExistingPath -Destination $backupPath -Recurse -Force
}

function Copy-ManagedItem {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$BackupRoot,
    [switch]$Optional
  )

  $source = Join-Path $SourceRoot $RelativePath
  $destination = Join-Path $TargetRoot $RelativePath

  if (-not (Test-Path -LiteralPath $source)) {
    if ($Optional) {
      Warn "Optional payload path missing, skipping: $RelativePath"
      return $false
    }

    throw "Required payload path missing: $source"
  }

  if (-not (Test-PathInsideRoot -Root $TargetRoot -Path $destination)) {
    throw "Refusing to copy outside target repo root: $destination"
  }

  $destinationParent = Split-Path -Path $destination -Parent
  if ($destinationParent -and -not (Test-PathInsideRoot -Root $TargetRoot -Path $destinationParent)) {
    throw "Refusing to create directory outside target repo root: $destinationParent"
  }

  if (Test-Path -LiteralPath $destination) {
    Copy-ToBackup -TargetRoot $TargetRoot -RelativePath $RelativePath -ExistingPath $destination -BackupRoot $BackupRoot
    if ($PSCmdlet.ShouldProcess($destination, "Replace managed UE tool suite path")) {
      Remove-Item -LiteralPath $destination -Recurse -Force
    }
  }

  if ($destinationParent -and $PSCmdlet.ShouldProcess($destinationParent, "Ensure destination directory")) {
    New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
  }

  if ($PSCmdlet.ShouldProcess($destination, "Install $RelativePath")) {
    Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
  }

  return $true
}

function Remove-LegacyTargetPath {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$BackupRoot
  )

  $target = Join-Path $TargetRoot $RelativePath
  if (-not (Test-Path -LiteralPath $target)) { return }

  Copy-ToBackup -TargetRoot $TargetRoot -RelativePath $RelativePath -ExistingPath $target -BackupRoot $BackupRoot
  if ($PSCmdlet.ShouldProcess($target, "Remove legacy in-project installer path")) {
    Remove-Item -LiteralPath $target -Recurse -Force
  }
}

$resolvedPayloadRoot = if ([string]::IsNullOrWhiteSpace($PayloadRoot)) {
  Resolve-ExistingDirectory -Path (Get-DefaultPayloadRoot) -Name "PayloadRoot"
}
else {
  Resolve-ExistingDirectory -Path $PayloadRoot -Name "PayloadRoot"
}

$resolvedTargetRoot = Resolve-ExistingDirectory -Path $TargetRepoRoot -Name "TargetRepoRoot"
$targetUProject = Resolve-TargetUProjectPath -RepoRoot $resolvedTargetRoot -UProjectPath $TargetUProjectPath
Test-TargetLooksLikeUE5Project -UProjectPath $targetUProject

$backupRoot = Join-Path $resolvedTargetRoot (".ue-tools-installer-backups\" + (Get-Date).ToString("yyyyMMdd-HHmmss"))

Info "Payload: $resolvedPayloadRoot"
Info "Target repo: $resolvedTargetRoot"
Info "Target project: $targetUProject"
if (-not $NoBackup) { Info "Backup root for replaced paths: $backupRoot" }

$managedItems = @(
  ".githooks",
  "Scripts/Init-Repo.ps1",
  "Scripts/README.md",
  "Scripts/git-hooks",
  "Scripts/git-tools",
  "Scripts/Unreal/ProjectContext.ps1",
  "Scripts/Unreal/ProjectShellAliases.ps1",
  "Scripts/Unreal/UESyncShellAliases.ps1",
  "Scripts/Unreal/UnrealSync.ps1"
)

if (-not $SkipArtSourceTools) { $managedItems += "Scripts/Unreal/New-ArtSourcePath.ps1" }
if (-not $SkipCodexTools) { $managedItems += "Scripts/Codex" }
if (-not $SkipTests) { $managedItems += "Scripts/Tests" }

if (-not $SkipDocs) {
  $managedItems += @(
    "Docs/README.md",
    "Docs/Setup.md",
    "Docs/Testing.md",
    "Docs/Codex",
    "Docs/DocsSite",
    "Docs/Pipeline"
  )

  if (-not $SkipCodingStandardsTools) {
    $managedItems += "Docs/CodingStandards"
  }
}

if (-not $SkipWebsite) {
  $managedItems += "Scripts/Docs"
  $managedItems += "website"
}
elseif (-not $SkipDocs) {
  $managedItems += "Scripts/Docs"
}

$installed = New-Object System.Collections.Generic.List[string]
foreach ($item in @($managedItems | Sort-Object -Unique)) {
  if (Copy-ManagedItem -SourceRoot $resolvedPayloadRoot -TargetRoot $resolvedTargetRoot -RelativePath $item -BackupRoot $backupRoot -Optional) {
    [void]$installed.Add($item)
  }
}

if (-not $NoLegacyCleanup) {
  Remove-LegacyTargetPath -TargetRoot $resolvedTargetRoot -RelativePath "Scripts/Install-UEProjectTools.ps1" -BackupRoot $backupRoot
}

Ok "Installed/updated UE tool suite paths: $($installed.Count)"

if ($RunInit) {
  $initScript = Join-Path $resolvedTargetRoot "Scripts\Init-Repo.ps1"
  $initArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $initScript,
    "-RepoRoot", $resolvedTargetRoot,
    "-UProjectPath", $targetUProject
  )

  if ($SkipShellAliases) { $initArgs += "-SkipShellAliases" }
  if ($SkipLfsPull) { $initArgs += "-SkipLfsPull" }
  if ($SkipOptionalToolSetup) { $initArgs += "-SkipOptionalToolSetup" }
  if ($SkipDocsSetup) { $initArgs += "-SkipDocsSetup" }
  if ($SkipDocsNpmInstall) { $initArgs += "-SkipDocsNpmInstall" }
  if ($ForceDocsNpmInstall) { $initArgs += "-ForceDocsNpmInstall" }
  if ($SkipDocsBridgeInstall) { $initArgs += "-SkipDocsBridgeInstall" }
  if ($SkipUnrealSync) { $initArgs += "-SkipUnrealSync" }
  if ($NoBuild) { $initArgs += "-NoBuild" }
  if ($NoRegen) { $initArgs += "-NoRegen" }

  Info "Running target bootstrap: pwsh $($initArgs -join ' ')"
  if ($PSCmdlet.ShouldProcess($resolvedTargetRoot, "Run Init-Repo.ps1 in target repo")) {
    & pwsh @initArgs
    if ($LASTEXITCODE -ne 0) {
      throw "Target Init-Repo.ps1 failed with exit code $LASTEXITCODE."
    }
  }
}
else {
  Info "Next step in the target repo:"
  Write-Host "  pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Init-Repo.ps1 -RepoRoot `"$resolvedTargetRoot`"" -ForegroundColor Cyan
}

Ok "Done."
