function Read-UEToolSuiteProjectMarker {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $markerPath = Join-Path $RepoRoot ".ue-tools\global-cli.json"
  if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
    throw "UE Tool Suite project marker is missing: $markerPath"
  }
  $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
  if ([int]$marker.schemaVersion -ne 2 -or [string]$marker.mode -ne "global") {
    throw "UE Tool Suite project marker is unsupported. Re-run the current installer."
  }
  if ([string]$marker.version -notmatch '^\d+\.\d+\.\d+$') {
    throw "The project marker version '$([string]$marker.version)' is not a stable three-part version."
  }
  return $marker
}

function Get-UEToolSuiteLatestRelease {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepositoryUrl)

  $sourceOverride = [string]$env:UE_TOOLS_UPDATE_SOURCE_ROOT
  if (-not [string]::IsNullOrWhiteSpace($sourceOverride)) {
    $sourceRoot = [IO.Path]::GetFullPath($sourceOverride)
    $manifestPath = Join-Path $sourceRoot "payload\ue-tool-suite.manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
      throw "Trusted update source does not contain payload/ue-tool-suite.manifest.json: $sourceRoot"
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $version = [string]$manifest.payloadVersion
    if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Trusted update source declares invalid version '$version'." }
    return [pscustomobject]@{ Version = $version; Tag = "v$version"; SourceRoot = $sourceRoot }
  }

  $git = Get-Command git -ErrorAction SilentlyContinue
  if (-not $git) { throw "Git is required to fetch the latest UE Tool Suite package version." }
  $lines = @(& $git.Source ls-remote --tags --refs $RepositoryUrl "refs/tags/v*" 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "Could not fetch UE Tool Suite release tags from $RepositoryUrl." }
  $versions = foreach ($line in $lines) {
    if ([string]$line -match 'refs/tags/v(?<version>\d+\.\d+\.\d+)$') {
      [pscustomobject]@{ Version = [version]$Matches.version; Text = $Matches.version; Tag = "v$($Matches.version)" }
    }
  }
  $latest = @($versions | Sort-Object Version -Descending | Select-Object -First 1)
  if ($latest.Count -ne 1) { throw "No stable UE Tool Suite release tags were found at $RepositoryUrl." }
  return [pscustomobject]@{ Version = $latest[0].Text; Tag = $latest[0].Tag; SourceRoot = $null }
}

function Get-UEToolSuiteVersionStatus {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $marker = Read-UEToolSuiteProjectMarker -RepoRoot $RepoRoot
  $repositoryUrl = [string]$marker.bootstrap.repositoryUrl
  if ([string]::IsNullOrWhiteSpace($repositoryUrl)) { throw "The project marker does not declare an update repository." }
  $latest = Get-UEToolSuiteLatestRelease -RepositoryUrl $repositoryUrl
  $projectVersion = [version]([string]$marker.version)
  $latestVersion = [version]$latest.Version
  [pscustomobject]@{
    ProjectVersion = [string]$marker.version
    LatestVersion = [string]$latest.Version
    UpdateAvailable = ($latestVersion -gt $projectVersion)
    ProjectAhead = ($projectVersion -gt $latestVersion)
    RepositoryUrl = $repositoryUrl
    ReleaseTag = [string]$latest.Tag
    SourceRoot = $latest.SourceRoot
  }
}

function Invoke-UEToolSuiteVersionCommand {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $status = Get-UEToolSuiteVersionStatus -RepoRoot $RepoRoot
  Write-Output "Project version: $($status.ProjectVersion)"
  Write-Output "Latest published version: $($status.LatestVersion)"
  if ($status.UpdateAvailable) { Write-Output "Update available. Run 'ue update'." }
  elseif ($status.ProjectAhead) { Write-Output "This project version is newer than the latest published release." }
  else { Write-Output "This project is up to date." }
}

function Invoke-UEToolSuiteUpdateCommand {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [AllowNull()][string[]]$CommandArguments = @()
  )

  $yes = $false
  foreach ($arg in @($CommandArguments)) {
    switch (([string]$arg).Trim().ToLowerInvariant()) {
      { $_ -in @('-y','--yes','-yes','/yes') } { $yes = $true; continue }
      default { throw "Unknown update option '$arg'. Usage: ue update [--yes]" }
    }
  }
  $status = Get-UEToolSuiteVersionStatus -RepoRoot $RepoRoot
  if (-not $status.UpdateAvailable) {
    if ($status.ProjectAhead) {
      Write-Output "No published update is available: $($status.ProjectVersion) is newer than latest published $($status.LatestVersion)."
    }
    else {
      Write-Output "UE Tool Suite $($status.ProjectVersion) is already the latest published version."
    }
    return
  }

  Write-Host "UE Tool Suite update available: $($status.ProjectVersion) -> $($status.LatestVersion)" -ForegroundColor Yellow
  if (-not $yes) {
    $ci = @([string]$env:CI, [string]$env:GITHUB_ACTIONS, [string]$env:TF_BUILD) | Where-Object { $_ -match '^(?i:1|true)$' }
    if ($ci.Count -gt 0) { throw "UE Tool Suite update requires confirmation. Re-run with --yes only when the update is explicitly approved." }
    $answer = [string](Read-Host "Update this project and install $($status.ReleaseTag) for this user now? [y/N]")
    if ($answer.Trim().ToLowerInvariant() -notin @('y','yes')) {
      Write-Output "UE Tool Suite update cancelled. No files were changed."
      return
    }
  }

  $sourceRoot = [string]$status.SourceRoot
  $removeSource = $false
  if ([string]::IsNullOrWhiteSpace($sourceRoot)) {
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
    $tempRoot = Join-Path $tempBase ("uetools-update-" + [Guid]::NewGuid().ToString('N'))
    $sourceRoot = Join-Path $tempRoot "source"
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    & git clone --quiet --depth 1 --branch $status.ReleaseTag --single-branch $status.RepositoryUrl $sourceRoot
    if ($LASTEXITCODE -ne 0) { throw "Could not download $($status.ReleaseTag) from $($status.RepositoryUrl)." }
    $removeSource = $true
  }
  try {
    $manifestPath = Join-Path $sourceRoot "payload\ue-tool-suite.manifest.json"
    $installerPath = Join-Path $sourceRoot "Install-UEToolSuite.ps1"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or -not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
      throw "Downloaded release is missing its installer or payload manifest."
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ([string]$manifest.payloadVersion -cne $status.LatestVersion) {
      throw "Downloaded payload version '$([string]$manifest.payloadVersion)' does not match $($status.ReleaseTag)."
    }
    $installerArgs = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$installerPath,'-TargetRepoRoot',$RepoRoot,'-SkipTests')
    if (-not [string]::IsNullOrWhiteSpace([string]$env:UE_TOOLS_GLOBAL_CLI_ROOT)) {
      $installerArgs += @('-GlobalCliRoot', [string]$env:UE_TOOLS_GLOBAL_CLI_ROOT)
    }
    & pwsh @installerArgs
    if ($LASTEXITCODE -ne 0) { throw "UE Tool Suite installer failed with exit code $LASTEXITCODE." }
    Write-Host "Updated this project to UE Tool Suite $($status.LatestVersion). Commit the managed project changes for teammates." -ForegroundColor Green
  }
  finally {
    if ($removeSource -and (Test-Path -LiteralPath $tempRoot)) {
      $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
      if ($resolvedTempRoot.StartsWith($tempBase + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
  }
}

Export-ModuleMember -Function Get-UEToolSuiteLatestRelease, Get-UEToolSuiteVersionStatus, Invoke-UEToolSuiteVersionCommand, Invoke-UEToolSuiteUpdateCommand
