function Add-UEToolSuiteInitToolReadinessEntry {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$ReadinessList,
    [Parameter(Mandatory)][string]$Tool,
    [Parameter(Mandatory)][ValidateSet("OK", "WARN", "SKIP")][string]$Status,
    [Parameter(Mandatory)][string]$Detail
  )

  [void]$ReadinessList.Add([pscustomobject]@{
      Tool = $Tool
      Status = $Status
      Detail = $Detail
    })
}

function Test-UEToolSuiteInitCommandAvailable {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Name)
  return ($null -ne (Get-Command $Name -ErrorAction SilentlyContinue))
}

function Assert-UEToolSuiteInitCommandAvailable {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$InstallHint
  )

  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $command) {
    throw "$Name not found. $InstallHint"
  }

  return $command
}

function Assert-UEToolSuiteInitNodeVersion {
  [CmdletBinding()]
  param()

  $nodeVersion = ((& node --version 2>$null) | Select-Object -First 1)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($nodeVersion)) {
    throw "node --version failed. Install Node.js 20+ and try again."
  }

  $versionText = $nodeVersion.Trim()
  if ($versionText -notmatch '^v?(?<major>\d+)') {
    throw "Could not parse Node.js version '$versionText'. Install Node.js 20+ and try again."
  }

  $major = [int]$Matches.major
  if ($major -lt 20) {
    throw "Node.js 20+ is required for docs tooling. Current: $versionText"
  }

  return $versionText
}

function Invoke-UEToolSuiteInitCheckedTool {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Description,
    [Parameter(Mandatory)][string]$FilePath,
    [string[]]$Arguments = @(),
    [string]$WorkingDirectory
  )

  $oldLocation = (Get-Location).Path
  try {
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
      Set-Location -LiteralPath $WorkingDirectory
    }

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "$Description failed (exit $LASTEXITCODE)."
    }
  }
  finally {
    Set-Location -LiteralPath $oldLocation
  }
}

function Get-UEToolSuiteInitGitHubRepoSlugFromRemoteUrl {
  [CmdletBinding()]
  param([string]$RemoteUrl)

  if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
    return $null
  }

  $trimmed = $RemoteUrl.Trim()
  if ($trimmed -match 'github\.com[:/](?<slug>[^/\s]+/[^/\s]+?)(?:\.git)?$') {
    return $Matches.slug
  }

  return $null
}

function ConvertTo-UEToolSuiteInitTypeScriptSingleQuotedString {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Value)

  return "'" + (($Value -replace "\\", "\\") -replace "'", "\'") + "'"
}

function Set-UEToolSuiteInitTypeScriptStringProperty {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$PropertyName,
    [Parameter(Mandatory)][string]$Value
  )

  $quotedValue = ConvertTo-UEToolSuiteInitTypeScriptSingleQuotedString -Value $Value
  $pattern = "(?m)^(\s*" + [regex]::Escape($PropertyName) + "\s*:\s*)(['""]).*?\2(,?\s*)$"
  if (-not [regex]::IsMatch($Text, $pattern)) {
    return $Text
  }

  return [regex]::Replace(
    $Text,
    $pattern,
    [System.Text.RegularExpressions.MatchEvaluator] {
      param($match)
      return $match.Groups[1].Value + $quotedValue + $match.Groups[3].Value
    },
    1
  )
}

function Resolve-UEToolSuiteInitRepoRoot {
  [CmdletBinding()]
  param(
    [string]$ExplicitRepoRoot,
    [string]$InvocationName = "Init-Repo",
    [switch]$AllowNonGit
  )

  if ([string]::IsNullOrWhiteSpace($ExplicitRepoRoot)) {
    $gitRoot = ((git rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($gitRoot)) {
      throw "Not inside a git repository (git rev-parse failed). Pass -RepoRoot when running from outside the repo."
    }

    return $gitRoot.Trim()
  }

  $candidate = [System.IO.Path]::GetFullPath($ExplicitRepoRoot)
  if (-not (Test-Path -LiteralPath $candidate)) {
    throw "RepoRoot does not exist: $candidate"
  }

  $gitRootFromCandidate = ((git -C $candidate rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($gitRootFromCandidate)) {
    if ($AllowNonGit) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }

    throw "RepoRoot is not inside a git repository: $candidate"
  }

  return $gitRootFromCandidate.Trim()
}

function Test-UEToolSuiteInitGitRepository {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $resolvedRoot = [System.IO.Path]::GetFullPath($RepoRoot)
  if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
    return $false
  }

  $gitRoot = ((git -C $resolvedRoot rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
  return (-not [string]::IsNullOrWhiteSpace($gitRoot))
}

function Initialize-UEToolSuiteInitGitRepository {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $resolvedRoot = [System.IO.Path]::GetFullPath($RepoRoot)
  if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
    throw "Repo root does not exist: $resolvedRoot"
  }

  & git -C $resolvedRoot init | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "git init failed for repo root '$resolvedRoot' (exit $LASTEXITCODE)."
  }

  return $resolvedRoot
}

function Show-UEToolSuiteInitToolReadinessSummary {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][System.Collections.IEnumerable]$Entries,
    [string]$Prefix = "[Init]"
  )

  $entryArray = @($Entries)
  if ($entryArray.Count -eq 0) {
    return
  }

  Write-Host "$Prefix Tool readiness summary:" -ForegroundColor Cyan
  foreach ($entry in $entryArray) {
    $color = [ConsoleColor]::Gray
    if ($entry.Status -eq "OK") {
      $color = [ConsoleColor]::Green
    }
    elseif ($entry.Status -eq "WARN") {
      $color = [ConsoleColor]::Yellow
    }
    elseif ($entry.Status -eq "SKIP") {
      $color = [ConsoleColor]::DarkYellow
    }

    Write-Host ("  [{0}] {1}: {2}" -f $entry.Status, $entry.Tool, $entry.Detail) -ForegroundColor $color
  }
}

function Invoke-UEToolSuiteInitDocusaurusMetadataUpdate {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [AllowNull()][string]$RepoSlug
  )

  $configPath = Join-Path $ResolvedRepoRoot "website\docusaurus.config.ts"
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    return [pscustomobject]@{ Status = "SKIP"; Detail = "website/docusaurus.config.ts is not installed." }
  }

  if ([string]::IsNullOrWhiteSpace($RepoSlug) -or $RepoSlug -notmatch '^(?<owner>[^/]+)/(?<name>[^/]+)$') {
    return [pscustomobject]@{ Status = "SKIP"; Detail = "origin does not point to a GitHub owner/repo slug." }
  }

  $owner = $Matches.owner
  $repoName = $Matches.name
  $configText = Get-Content -LiteralPath $configPath -Raw
  $updatedText = Set-UEToolSuiteInitTypeScriptStringProperty -Text $configText -PropertyName "organizationName" -Value $owner
  $updatedText = Set-UEToolSuiteInitTypeScriptStringProperty -Text $updatedText -PropertyName "projectName" -Value $repoName

  if ($updatedText -eq $configText) {
    return [pscustomobject]@{ Status = "WARN"; Detail = "Could not find organizationName/projectName in website/docusaurus.config.ts." }
  }

  if (Get-Command -Name "Write-UEToolSuiteUtf8NoBomFile" -ErrorAction SilentlyContinue) {
    Write-UEToolSuiteUtf8NoBomFile -Path $configPath -Content $updatedText
  }
  else {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($configPath, $updatedText, $utf8NoBom)
  }

  return [pscustomobject]@{ Status = "OK"; Detail = "Set Docusaurus GitHub owner/repo metadata to $owner/$repoName." }
}

function Get-UEToolSuiteInitArtTemplateReadiness {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $artModulePath = Join-Path $ResolvedRepoRoot "Scripts\UETools\UEToolSuite.Art.psm1"
  if (-not (Test-Path -LiteralPath $artModulePath -PathType Leaf)) {
    return [pscustomobject]@{ Status = "SKIP"; Detail = "Art module is not installed in this repo." }
  }

  $artSourceRoot = Join-Path $ResolvedRepoRoot "ArtSource"
  if (-not (Test-Path -LiteralPath $artSourceRoot -PathType Container)) {
    return [pscustomobject]@{ Status = "SKIP"; Detail = "No ArtSource folder found; art tooling is not applicable yet." }
  }

  $missing = @()
  foreach ($relativePath in @("_Template", "_Template\\Source", "_Template\\Textures", "_Template\\Exports")) {
    $candidate = Join-Path $artSourceRoot $relativePath
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
      $missing += (Join-Path "ArtSource" $relativePath)
    }
  }

  if ($missing.Count -gt 0) {
    return [pscustomobject]@{ Status = "WARN"; Detail = "Missing template folder(s): $($missing -join ', '). Run ue-tools art once after restoring the template." }
  }

  return [pscustomobject]@{ Status = "OK"; Detail = "ArtSource/_Template contains Source, Textures, and Exports." }
}

function ConvertTo-UEToolSuiteInitParameters {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [AllowNull()][string[]]$CommandArguments = @()
  )

  $switchMap = @{
    "skiplfspull" = "SkipLfsPull"
    "skipunrealsync" = "SkipUnrealSync"
    "skipshellaliases" = "SkipShellAliases"
    "skipoptionaltoolsetup" = "SkipOptionalToolSetup"
    "skipdocssetup" = "SkipDocsSetup"
    "skipdocsnpminstall" = "SkipDocsNpmInstall"
    "forcedocsnpminstall" = "ForceDocsNpmInstall"
    "skipdocsbridgeinstall" = "SkipDocsBridgeInstall"
    "nobuild" = "NoBuild"
    "noregen" = "NoRegen"
    "noninteractive" = "NonInteractive"
    "skipignoreduntrack" = "SkipIgnoredUntrack"
  }
  $valueMap = @{
    "reporoot" = "RepoRoot"
    "uprojectpath" = "UProjectPath"
    "workspacepath" = "WorkspacePath"
    "config" = "Config"
    "platform" = "Platform"
  }

  $parameters = @{
    RepoRoot = $RepoRoot
  }

  $argsList = @()
  foreach ($argument in @($CommandArguments)) {
    if ($null -eq $argument) { continue }
    $text = [string]$argument
    if ([string]::IsNullOrWhiteSpace($text)) { continue }
    $argsList += $text
  }

  $i = 0
  while ($i -lt $argsList.Count) {
    $token = [string]$argsList[$i]
    if (-not ($token.StartsWith("-") -or $token.StartsWith("/"))) {
      throw "Unknown init argument '$token'. Run 'ue-tools help init'."
    }

    $normalized = $token.TrimStart('-', '/').ToLowerInvariant()
    if ($switchMap.ContainsKey($normalized)) {
      $parameters[$switchMap[$normalized]] = $true
      $i += 1
      continue
    }

    if ($valueMap.ContainsKey($normalized)) {
      if (($i + 1) -ge $argsList.Count) {
        throw "Missing value for init option '$token'."
      }
      $parameters[$valueMap[$normalized]] = [string]$argsList[$i + 1]
      $i += 2
      continue
    }

    throw "Unknown init option '$token'. Run 'ue-tools help init'."
  }

  return $parameters
}

function Invoke-UEToolSuiteInitCommand {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [AllowNull()][string[]]$CommandArguments = @()
  )

  $resolvedRepoRoot = $RepoRoot
  $parameters = ConvertTo-UEToolSuiteInitParameters -RepoRoot $resolvedRepoRoot -CommandArguments $CommandArguments

  if (-not (Get-Command -Name "Invoke-UEToolSuiteInitRuntime" -CommandType Function -ErrorAction SilentlyContinue)) {
    throw "Init runtime entrypoint function is unavailable in UEToolSuite.Init.psm1."
  }

  Invoke-UEToolSuiteInitRuntime @parameters
}

Export-ModuleMember -Function `
  Add-UEToolSuiteInitToolReadinessEntry, `
  Test-UEToolSuiteInitCommandAvailable, `
  Assert-UEToolSuiteInitCommandAvailable, `
  Assert-UEToolSuiteInitNodeVersion, `
  Invoke-UEToolSuiteInitCheckedTool, `
  Get-UEToolSuiteInitGitHubRepoSlugFromRemoteUrl, `
  ConvertTo-UEToolSuiteInitTypeScriptSingleQuotedString, `
  Set-UEToolSuiteInitTypeScriptStringProperty, `
  Resolve-UEToolSuiteInitRepoRoot, `
  Test-UEToolSuiteInitGitRepository, `
  Initialize-UEToolSuiteInitGitRepository, `
  Show-UEToolSuiteInitToolReadinessSummary, `
  Invoke-UEToolSuiteInitDocusaurusMetadataUpdate, `
  Get-UEToolSuiteInitArtTemplateReadiness, `
  ConvertTo-UEToolSuiteInitParameters, `
  Invoke-UEToolSuiteInitCommand, `
  Invoke-UEToolSuiteInitRuntime

# -----------------------------------------------------------------------------
# Migrated runtime implementation (Init-Repo)
# Source previously lived in: payload/Scripts/UETools/UEToolSuite.Init.psm1
# -----------------------------------------------------------------------------
function Invoke-UEToolSuiteInitRuntime {
  [CmdletBinding()]
  param(
    [switch]$SkipLfsPull,
    [switch]$SkipUnrealSync,
    [switch]$SkipShellAliases,
    [switch]$SkipOptionalToolSetup,
    [switch]$SkipDocsSetup,
    [switch]$SkipDocsNpmInstall,
    [switch]$ForceDocsNpmInstall,
    [switch]$SkipDocsBridgeInstall,
    [switch]$NonInteractive,
    [switch]$SkipIgnoredUntrack,
    [switch]$NoBuild,
    [switch]$NoRegen,
    [string]$RepoRoot,
    [string]$UProjectPath,
    [string]$WorkspacePath,
  
    [ValidateSet("Development", "Debug")]
    [string]$Config = "Development",
  
    [ValidateSet("Win64")]
    [string]$Platform = "Win64"
  )
  
  
  $ErrorActionPreference = "Stop"
  
  $script:InitScriptsRoot = Split-Path -Parent $PSScriptRoot
  $coreModuleEntryPath = Join-Path $script:InitScriptsRoot "UETools\UETools.psd1"
  if (-not (Test-Path -LiteralPath $coreModuleEntryPath -PathType Leaf)) {
    $coreModuleEntryPath = Join-Path $script:InitScriptsRoot "UETools\UEToolSuite.Core.psm1"
  }
  if (-not (Test-Path -LiteralPath $coreModuleEntryPath -PathType Leaf)) {
    throw "Core module entry not found: $coreModuleEntryPath"
  }
  Import-Module -Name $coreModuleEntryPath -Force -DisableNameChecking
  
  Set-UEToolSuiteRuntimeContext -ScriptsRoot $script:InitScriptsRoot -StateKey "init-repo" -LogPrefix "[Init]" -CommandAvailabilityFunctionName "Test-UEToolSuiteInitCommandAvailable"

  if (-not (Import-UEToolSuiteCoreModule)) {
    throw "UETools module entry not found under $script:InitScriptsRoot\UETools."
  }

  $initDomainModulePath = Join-Path $script:InitScriptsRoot "UETools\UEToolSuite.Init.psm1"
  if (-not (Test-Path -LiteralPath $initDomainModulePath -PathType Leaf)) {
    throw "Init domain module not found: $initDomainModulePath"
  }
  Import-Module -Name $initDomainModulePath -Force
  
  $aliasDomainModulePath = Join-Path $script:InitScriptsRoot "UETools\UEToolSuite.Aliases.psm1"
  if (-not (Test-Path -LiteralPath $aliasDomainModulePath -PathType Leaf)) {
    throw "Aliases domain module not found: $aliasDomainModulePath"
  }
  Import-Module -Name $aliasDomainModulePath -Force
  
  $script:ToolReadiness = New-Object System.Collections.Generic.List[object]
  
  function Add-ToolReadiness {
    param(
      [Parameter(Mandatory)][string]$Tool,
      [Parameter(Mandatory)][ValidateSet("OK", "WARN", "SKIP")][string]$Status,
      [Parameter(Mandatory)][string]$Detail
    )
  
    Add-UEToolSuiteInitToolReadinessEntry -ReadinessList $script:ToolReadiness -Tool $Tool -Status $Status -Detail $Detail
  }
  
  function Assert-CommandAvailable {
    param(
      [Parameter(Mandatory)][string]$Name,
      [Parameter(Mandatory)][string]$InstallHint
    )
    return (Assert-UEToolSuiteInitCommandAvailable -Name $Name -InstallHint $InstallHint)
  }
  
  function Assert-NodeVersion {
    return (Assert-UEToolSuiteInitNodeVersion)
  }
  
  function Invoke-CheckedTool {
    param(
      [Parameter(Mandatory)][string]$Description,
      [Parameter(Mandatory)][string]$FilePath,
      [string[]]$Arguments = @(),
      [string]$WorkingDirectory
    )
    Invoke-UEToolSuiteInitCheckedTool -Description $Description -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory
  }
  
  function Get-GitHubRepoSlugFromRemoteUrl {
    param([string]$RemoteUrl)
    return (Get-UEToolSuiteInitGitHubRepoSlugFromRemoteUrl -RemoteUrl $RemoteUrl)
  }
  
  function Update-DocusaurusGitHubMetadata {
    param(
      [Parameter(Mandatory)][string]$ResolvedRepoRoot,
      [AllowNull()][string]$RepoSlug
    )
  
    $result = Invoke-UEToolSuiteInitDocusaurusMetadataUpdate -ResolvedRepoRoot $ResolvedRepoRoot -RepoSlug $RepoSlug
    Add-ToolReadiness -Tool "docs site metadata" -Status $result.Status -Detail $result.Detail
  }
  
  function Resolve-InitRepoRoot {
    param(
      [string]$ExplicitRepoRoot,
      [switch]$AllowNonGit
    )

    return (Resolve-UEToolSuiteInitRepoRoot -ExplicitRepoRoot $ExplicitRepoRoot -InvocationName "Init-Repo" -AllowNonGit:$AllowNonGit)
  }

  function Read-InitYesNo {
    param(
      [Parameter(Mandatory)][string]$Prompt,
      [bool]$DefaultYes = $true
    )

    while ($true) {
      $suffix = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
      $response = ([string](Read-Host "$Prompt $suffix")).Trim().ToLowerInvariant()
      if ([string]::IsNullOrWhiteSpace($response)) {
        return $DefaultYes
      }

      switch ($response) {
        "y" { return $true }
        "yes" { return $true }
        "n" { return $false }
        "no" { return $false }
        default { Warn "Please enter y or n." }
      }
    }
  }

  function Get-InitDefaultCommitMessage {
    return "chore: initialize repository with UE Tool Suite defaults"
  }

  function Get-IgnoredTrackedFiles {
    param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

    $ignoredTracked = @(& git -C $ResolvedRepoRoot ls-files -ci --exclude-standard 2>$null)
    if ($LASTEXITCODE -ne 0) {
      return @()
    }

    return @(
      $ignoredTracked |
        ForEach-Object { [string]$_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim() } |
        Sort-Object -Unique
    )
  }

  function Write-UEToolSuiteInitGitPathspecFile {
    param(
      [Parameter(Mandatory)][string]$Path,
      [Parameter(Mandatory)][string[]]$Paths
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
      foreach ($entry in @($Paths)) {
        $bytes = $encoding.GetBytes([string]$entry)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.WriteByte(0)
      }
    }
    finally {
      $stream.Dispose()
    }
  }

  function Invoke-UEToolSuiteInitGitUntrackBatch {
    param(
      [Parameter(Mandatory)][string]$ResolvedRepoRoot,
      [Parameter(Mandatory)][string[]]$Paths
    )

    $pathspecFile = Join-Path ([System.IO.Path]::GetTempPath()) ("ue-tools-ignored-tracked-" + [Guid]::NewGuid().ToString("N") + ".txt")
    try {
      Write-UEToolSuiteInitGitPathspecFile -Path $pathspecFile -Paths $Paths
      & git -C $ResolvedRepoRoot rm --cached --ignore-unmatch "--pathspec-from-file=$pathspecFile" --pathspec-file-nul 2>$null | Out-Null
      return ($LASTEXITCODE -eq 0)
    }
    finally {
      if (Test-Path -LiteralPath $pathspecFile) {
        Remove-Item -LiteralPath $pathspecFile -Force -ErrorAction SilentlyContinue
      }
    }
  }

  function Untrack-IgnoredFiles {
    param(
      [Parameter(Mandatory)][string]$ResolvedRepoRoot,
      [Parameter(Mandatory)][string[]]$Paths
    )

    $batchSize = 512
    $pathsToUntrack = @($Paths)
    $failures = New-Object System.Collections.Generic.List[string]
    $batchCount = [Math]::Ceiling($pathsToUntrack.Count / $batchSize)

    for ($offset = 0; $offset -lt $pathsToUntrack.Count; $offset += $batchSize) {
      $upperBound = [Math]::Min($offset + $batchSize - 1, $pathsToUntrack.Count - 1)
      $batch = @($pathsToUntrack[$offset..$upperBound])
      $batchNumber = [int]([Math]::Floor($offset / $batchSize) + 1)
      Info ("[Init] Untracking ignored tracked files batch {0}/{1} ({2}-{3} of {4})..." -f $batchNumber, $batchCount, ($offset + 1), ($upperBound + 1), $pathsToUntrack.Count)

      if (Invoke-UEToolSuiteInitGitUntrackBatch -ResolvedRepoRoot $ResolvedRepoRoot -Paths $batch) {
        continue
      }

      foreach ($path in $batch) {
        & git -C $ResolvedRepoRoot rm --cached --ignore-unmatch -- $path 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
          [void]$failures.Add($path)
        }
      }
    }

    return [pscustomobject]@{
      Attempted = $pathsToUntrack.Count
      Failed = @($failures.ToArray())
    }
  }

  function Ensure-IgnoredTrackedFilesUntracked {
    param(
      [Parameter(Mandatory)][string]$ResolvedRepoRoot,
      [switch]$NonInteractiveMode,
      [switch]$SkipUntrack
    )

    if ($SkipUntrack) {
      Add-ToolReadiness -Tool "ignored tracked files" -Status "SKIP" -Detail "Ignored tracked file cleanup skipped by parameter."
      return
    }

    $ignoredTracked = @(Get-IgnoredTrackedFiles -ResolvedRepoRoot $ResolvedRepoRoot)
    if ($ignoredTracked.Count -eq 0) {
      Add-ToolReadiness -Tool "ignored tracked files" -Status "OK" -Detail "No tracked files matched .gitignore rules."
      return
    }

    if ($NonInteractiveMode) {
      Warn "Non-interactive mode: untracking $($ignoredTracked.Count) ignored tracked file(s) from git index."
    }
    else {
      Warn "Found $($ignoredTracked.Count) tracked file(s) now matched by .gitignore rules."
      foreach ($path in $ignoredTracked) {
        Write-Host "  - $path" -ForegroundColor Yellow
      }

      $shouldUntrack = Read-InitYesNo -Prompt "Remove these from git tracking now (keeps local files)?" -DefaultYes $true
      if (-not $shouldUntrack) {
        Add-ToolReadiness -Tool "ignored tracked files" -Status "WARN" -Detail "Ignored tracked files remain tracked. Run: git ls-files -ci --exclude-standard | ForEach-Object { git rm --cached -- $_ }"
        return
      }
    }

    $result = Untrack-IgnoredFiles -ResolvedRepoRoot $ResolvedRepoRoot -Paths $ignoredTracked
    if ($result.Failed.Count -gt 0) {
      $failedList = ($result.Failed -join ", ")
      Add-ToolReadiness -Tool "ignored tracked files" -Status "WARN" -Detail "Untracked $($result.Attempted - $result.Failed.Count)/$($result.Attempted) ignored tracked file(s). Failed: $failedList"
      return
    }

    Add-ToolReadiness -Tool "ignored tracked files" -Status "OK" -Detail "Untracked $($result.Attempted) ignored tracked file(s) from git index (local files retained)."
  }

  function Invoke-InitialRepositoryCommit {
    param(
      [Parameter(Mandatory)][string]$ResolvedRepoRoot,
      [switch]$NonInteractiveMode
    )

    $defaultMessage = Get-InitDefaultCommitMessage
    $commitMessage = $defaultMessage

    if (-not $NonInteractiveMode) {
      $customMessage = [string](Read-Host "Enter initial commit message (press Enter for default)")
      if (-not [string]::IsNullOrWhiteSpace($customMessage)) {
        $commitMessage = $customMessage.Trim()
      }
    }
    else {
      Info "Non-interactive mode: using default initial commit message."
    }

    & git -C $ResolvedRepoRoot add -A
    if ($LASTEXITCODE -ne 0) {
      Add-ToolReadiness -Tool "initial commit" -Status "WARN" -Detail "git add -A failed. Commit was not created."
      return
    }

    $commitOutput = @(& git -C $ResolvedRepoRoot commit -m $commitMessage 2>&1)
    $commitText = @($commitOutput | ForEach-Object { [string]$_ }) -join " "
    if ($LASTEXITCODE -ne 0) {
      if ($commitText -match "nothing to commit") {
        Add-ToolReadiness -Tool "initial commit" -Status "SKIP" -Detail "No tracked changes to commit."
        return
      }

      Add-ToolReadiness -Tool "initial commit" -Status "WARN" -Detail "git commit failed. Configure git user.name/user.email and commit manually."
      return
    }

    Add-ToolReadiness -Tool "initial commit" -Status "OK" -Detail "Created initial commit with message: $commitMessage"
  }
  
  function Test-ArtSourceTemplateReady {
    param([Parameter(Mandatory)][string]$ResolvedRepoRoot)
  
    $result = Get-UEToolSuiteInitArtTemplateReadiness -ResolvedRepoRoot $ResolvedRepoRoot
    Add-ToolReadiness -Tool "ue-tools art" -Status $result.Status -Detail $result.Detail
  }
  
  function Show-ToolReadinessSummary {
    Show-UEToolSuiteInitToolReadinessSummary -Entries $script:ToolReadiness -Prefix "[Init]"
  }

  function Get-DocsDependencyStatePath {
    param([Parameter(Mandatory)][string]$WebsiteRoot)
    return (Join-Path $WebsiteRoot "node_modules\.ue-tools-docs-deps-state.json")
  }

  function Get-DocsDependencyFingerprint {
    param([Parameter(Mandatory)][string]$WebsiteRoot)

    $packagePath = Join-Path $WebsiteRoot "package.json"
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
      throw "Docs dependency fingerprint requires website/package.json."
    }

    $lockPath = Join-Path $WebsiteRoot "package-lock.json"
    $packageText = Get-Content -LiteralPath $packagePath -Raw
    $lockText = if (Test-Path -LiteralPath $lockPath -PathType Leaf) { Get-Content -LiteralPath $lockPath -Raw } else { "" }
    $composite = "$packageText`n`n$lockText"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($composite)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
      $hash = $sha.ComputeHash($bytes)
      return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    }
    finally {
      $sha.Dispose()
    }
  }

  function Get-DocsRequiredDependencyNames {
    param([Parameter(Mandatory)][string]$WebsiteRoot)

    $packagePath = Join-Path $WebsiteRoot "package.json"
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
      return @()
    }

    $packageJson = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
    $dependencyNames = New-Object System.Collections.Generic.List[string]
    if ($packageJson.PSObject.Properties["dependencies"]) {
      foreach ($property in $packageJson.dependencies.PSObject.Properties) {
        if ([string]::IsNullOrWhiteSpace([string]$property.Name)) { continue }
        [void]$dependencyNames.Add([string]$property.Name)
      }
    }

    return @($dependencyNames.ToArray() | Sort-Object -Unique)
  }

  function Read-DocsDependencyState {
    param([Parameter(Mandatory)][string]$WebsiteRoot)

    $statePath = Get-DocsDependencyStatePath -WebsiteRoot $WebsiteRoot
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
      return $null
    }

    try {
      return (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json)
    }
    catch {
      return $null
    }
  }

  function Write-DocsDependencyState {
    param(
      [Parameter(Mandatory)][string]$WebsiteRoot,
      [Parameter(Mandatory)][string]$DependencyHash,
      [Parameter(Mandatory)][string[]]$RequiredDependencies,
      [Parameter(Mandatory)][string]$InstallCommand
    )

    $statePath = Get-DocsDependencyStatePath -WebsiteRoot $WebsiteRoot
    $stateDir = Split-Path -Path $statePath -Parent
    if ($stateDir) {
      New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    }

    $payload = [ordered]@{
      dependencyHash = $DependencyHash
      requiredDependencies = @($RequiredDependencies | Sort-Object -Unique)
      installCommand = $InstallCommand
      packageLockPresent = (Test-Path -LiteralPath (Join-Path $WebsiteRoot "package-lock.json") -PathType Leaf)
      updatedUtc = (Get-Date).ToUniversalTime().ToString("o")
    }

    $json = ($payload | ConvertTo-Json -Depth 8)
    if (Get-Command -Name "Write-UEToolSuiteUtf8NoBomFile" -ErrorAction SilentlyContinue) {
      Write-UEToolSuiteUtf8NoBomFile -Path $statePath -Content $json
    }
    else {
      $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
      [System.IO.File]::WriteAllText($statePath, $json, $utf8NoBom)
    }
  }

  function Get-DocsNpmInstallPlan {
    param([Parameter(Mandatory)][string]$WebsiteRoot)

    $lockPath = Join-Path $WebsiteRoot "package-lock.json"
    if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
      return [pscustomobject]@{
        CommandName = "ci"
        Arguments = @("ci", "--no-audit", "--no-fund")
      }
    }

    return [pscustomobject]@{
      CommandName = "install"
      Arguments = @("install", "--no-audit", "--no-fund")
    }
  }

  function Test-DocsDependenciesSynchronized {
    param(
      [Parameter(Mandatory)][string]$WebsiteRoot,
      [switch]$IgnoreStateFile
    )

    $nodeModulesPath = Join-Path $WebsiteRoot "node_modules"
    if (-not (Test-Path -LiteralPath $nodeModulesPath -PathType Container)) {
      return [pscustomobject]@{
        IsSynchronized = $false
        Reason = "website/node_modules is missing."
        MissingDependencies = @()
        RequiredDependencies = @()
        DependencyHash = (Get-DocsDependencyFingerprint -WebsiteRoot $WebsiteRoot)
      }
    }

    $requiredDependencies = @(Get-DocsRequiredDependencyNames -WebsiteRoot $WebsiteRoot)
    $missingDependencies = New-Object System.Collections.Generic.List[string]
    foreach ($dependency in $requiredDependencies) {
      $dependencyPath = Join-Path $nodeModulesPath ($dependency -replace '/', '\')
      if (-not (Test-Path -LiteralPath $dependencyPath)) {
        [void]$missingDependencies.Add($dependency)
      }
    }
    if ($missingDependencies.Count -gt 0) {
      return [pscustomobject]@{
        IsSynchronized = $false
        Reason = "Required package(s) missing from website/node_modules: $($missingDependencies -join ', ')"
        MissingDependencies = @($missingDependencies.ToArray())
        RequiredDependencies = $requiredDependencies
        DependencyHash = (Get-DocsDependencyFingerprint -WebsiteRoot $WebsiteRoot)
      }
    }

    $fingerprint = Get-DocsDependencyFingerprint -WebsiteRoot $WebsiteRoot
    if (-not $IgnoreStateFile) {
      $state = Read-DocsDependencyState -WebsiteRoot $WebsiteRoot
      if ($null -eq $state) {
        return [pscustomobject]@{
          IsSynchronized = $false
          Reason = "Docs dependency state file is missing."
          MissingDependencies = @()
          RequiredDependencies = $requiredDependencies
          DependencyHash = $fingerprint
        }
      }

      $stateHash = ""
      if ($state.PSObject.Properties["dependencyHash"]) {
        $stateHash = [string]$state.dependencyHash
      }
      if ([string]::IsNullOrWhiteSpace($stateHash) -or $stateHash -ne $fingerprint) {
        return [pscustomobject]@{
          IsSynchronized = $false
          Reason = "Docs dependency fingerprint changed since last install."
          MissingDependencies = @()
          RequiredDependencies = $requiredDependencies
          DependencyHash = $fingerprint
        }
      }
    }

    return [pscustomobject]@{
      IsSynchronized = $true
      Reason = "Docs dependencies are synchronized."
      MissingDependencies = @()
      RequiredDependencies = $requiredDependencies
      DependencyHash = $fingerprint
    }
  }
  
  function Initialize-DocsTooling {
    param(
      [Parameter(Mandatory)][string]$ResolvedRepoRoot,
      [switch]$SkipAll,
      [switch]$SkipDocs,
      [switch]$SkipNpmInstall,
      [switch]$ForceNpmInstall,
      [switch]$SkipBridgeInstall
    )
  
    $ueToolsScript = Join-Path $ResolvedRepoRoot "Scripts\ue-tools.ps1"
    if (-not (Test-Path -LiteralPath $ueToolsScript)) {
      Add-ToolReadiness -Tool "ue-tools docs" -Status "SKIP" -Detail "Scripts\ue-tools.ps1 is not installed in this repo."
      return
    }
  
    $docsDomainScript = Join-Path $ResolvedRepoRoot "Scripts\UETools\UEToolSuite.Docs.psm1"
    if (-not (Test-Path -LiteralPath $docsDomainScript)) {
      Add-ToolReadiness -Tool "ue-tools docs" -Status "SKIP" -Detail "Docs domain is not installed in this repo."
      return
    }
  
    $websiteRoot = Join-Path $ResolvedRepoRoot "website"
    $websitePackagePath = Join-Path $websiteRoot "package.json"
    if (-not (Test-Path -LiteralPath $websitePackagePath)) {
      Add-ToolReadiness -Tool "ue-tools docs" -Status "SKIP" -Detail "No website/package.json found; docs site setup is not applicable."
      return
    }
  
    if ($SkipAll -or $SkipDocs) {
      Warn "Skipping docs tooling prerequisite setup."
      Add-ToolReadiness -Tool "ue-tools docs" -Status "SKIP" -Detail "Docs tooling prerequisite setup skipped by parameter."
      return
    }
  
    Info "Preparing docs tooling prerequisites..."
    $null = Assert-CommandAvailable -Name "node" -InstallHint "Install Node.js 20+ and rerun Init-Repo."
    $null = Assert-CommandAvailable -Name "npm" -InstallHint "Install npm and rerun Init-Repo."
    $nodeVersion = Assert-NodeVersion
    Add-ToolReadiness -Tool "node/npm" -Status "OK" -Detail "Node.js $nodeVersion and npm are available."
  
    $npmInstallPlan = Get-DocsNpmInstallPlan -WebsiteRoot $websiteRoot
    $dependencySync = Test-DocsDependenciesSynchronized -WebsiteRoot $websiteRoot
    if ($SkipNpmInstall) {
      Warn "Skipping docs npm install (SkipDocsNpmInstall set)."
      if (-not $dependencySync.IsSynchronized) {
        Warn "Docs dependency check detected drift: $($dependencySync.Reason)"
      }
      Add-ToolReadiness -Tool "docs dependencies" -Status "SKIP" -Detail "Docs dependency synchronization skipped by parameter."
    }
    elseif ($ForceNpmInstall -or -not $dependencySync.IsSynchronized) {
      $installReason = if ($ForceNpmInstall) { "forced by parameter" } else { $dependencySync.Reason }
      Info "Installing docs site dependencies with npm $($npmInstallPlan.CommandName)..."
      Info "Docs dependency install reason: $installReason"
      Invoke-CheckedTool `
        -Description "npm $($npmInstallPlan.CommandName) for docs site" `
        -FilePath "npm" `
        -Arguments $npmInstallPlan.Arguments `
        -WorkingDirectory $websiteRoot
      $postInstallSync = Test-DocsDependenciesSynchronized -WebsiteRoot $websiteRoot -IgnoreStateFile
      if (-not $postInstallSync.IsSynchronized) {
        throw "Docs dependency install completed but validation failed: $($postInstallSync.Reason)"
      }
      Write-DocsDependencyState `
        -WebsiteRoot $websiteRoot `
        -DependencyHash $postInstallSync.DependencyHash `
        -RequiredDependencies $postInstallSync.RequiredDependencies `
        -InstallCommand ("npm " + $npmInstallPlan.CommandName)
      Add-ToolReadiness -Tool "docs dependencies" -Status "OK" -Detail "npm $($npmInstallPlan.CommandName) completed in website/."
    }
    else {
      Add-ToolReadiness -Tool "docs dependencies" -Status "OK" -Detail "website/node_modules is synchronized with package manifests."
    }
  
    if ($SkipBridgeInstall) {
      Warn "Skipping docs VS Code bridge install (SkipDocsBridgeInstall set)."
      Add-ToolReadiness -Tool "docs VS Code bridge" -Status "SKIP" -Detail "Bridge install skipped by parameter."
    }
    elseif (Test-CommandAvailable -Name "code") {
      Info "Installing optional docs VS Code bridge..."
      Invoke-CheckedTool `
        -Description "ue-tools docs install-bridge" `
        -FilePath "pwsh" `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ueToolsScript, "-RepoRoot", $ResolvedRepoRoot, "docs", "install-bridge")
      Add-ToolReadiness -Tool "docs VS Code bridge" -Status "OK" -Detail "VS Code bridge installed. Reload VS Code windows to activate it."
    }
    else {
      Warn "Skipping docs VS Code bridge install because the 'code' CLI is not available."
      Add-ToolReadiness -Tool "docs VS Code bridge" -Status "WARN" -Detail "Install or expose the VS Code 'code' CLI, then run: ue-tools docs install-bridge"
    }
  
    Info "Running ue-tools docs doctor..."
    Invoke-CheckedTool `
      -Description "ue-tools docs doctor" `
      -FilePath "pwsh" `
      -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ueToolsScript, "-RepoRoot", $ResolvedRepoRoot, "docs", "doctor")
    Add-ToolReadiness -Tool "ue-tools docs" -Status "OK" -Detail "ue-tools docs doctor completed."
  }
  
  
  # --- Require PowerShell 7+ ---
  if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7+ is required. Current: $($PSVersionTable.PSVersion)"
  }
  
  # --- Optional: ensure ANSI is not downgraded in nested calls ---
  # This helps if a user has changed OutputRendering elsewhere.
  try { $PSStyle.OutputRendering = 'Host' } catch { }
  
  # --- Require git ---
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git not found. Install Git for Windows and try again."
  }
  
  # --- Find repo root and move there ---
  $repoRoot = Resolve-InitRepoRoot -ExplicitRepoRoot $RepoRoot -AllowNonGit
  
  Set-Location $repoRoot
  Info "Repo root: $repoRoot"

  $createdGitRepository = $false
  $isGitRepository = Test-UEToolSuiteInitGitRepository -RepoRoot $repoRoot
  if (-not $isGitRepository) {
    if ($NonInteractive) {
      Warn "Repo is not initialized with git. Non-interactive mode will run git init."
      Initialize-UEToolSuiteInitGitRepository -RepoRoot $repoRoot | Out-Null
      $createdGitRepository = $true
    }
    else {
      Warn "Repo root is not currently a git repository: $repoRoot"
      $shouldInitGit = Read-InitYesNo -Prompt "Initialize a git repository now?" -DefaultYes $true
      if (-not $shouldInitGit) {
        throw "Init-Repo requires a git repository. Initialize git manually or re-run with -NonInteractive."
      }

      Initialize-UEToolSuiteInitGitRepository -RepoRoot $repoRoot | Out-Null
      $createdGitRepository = $true
    }
  }

  if ($createdGitRepository) {
    Add-ToolReadiness -Tool "git repository" -Status "OK" -Detail "Initialized git repository at repo root."
  }
  else {
    Add-ToolReadiness -Tool "git repository" -Status "OK" -Detail "Git repository already initialized."
  }
  
  $projectContextHelpers = Join-Path $repoRoot "Scripts\Unreal\ProjectContext.ps1"
  if (-not (Test-Path -LiteralPath $projectContextHelpers)) {
    throw "Project context helpers not found: $projectContextHelpers"
  }
  . $projectContextHelpers
  
  $projectContext = Get-ProjectContext -RepoRoot $repoRoot -UProjectPath $UProjectPath -WorkspacePath $WorkspacePath
  Info "Project: $($projectContext.ProjectName)"
  Info "Primary module: $($projectContext.PrimaryModuleName)"
  
  $leaf = Split-Path $repoRoot -Leaf
  if ($leaf -ne $projectContext.ProjectName) {
    Warn "Repo folder name '$leaf' differs from project name '$($projectContext.ProjectName)'."
    Warn "This is allowed, but keep generated workspace/tooling paths aligned with the current repo root."
  }
  
  # --- Ensure Git LFS is available and initialized ---
  if (-not (Get-Command git-lfs -ErrorAction SilentlyContinue)) {
    throw "git-lfs not found. Install Git LFS and try again."
  }
  
  # IMPORTANT:
  # - We do NOT want git lfs to attempt to install hook files into the repo because we commit our own hooks.
  # - --skip-repo installs/configures LFS filters but skips repo hook installation.  (see git-lfs-install(1))
  Info "Initializing Git LFS filters for this repo (skipping repo hook install)..."
  & git lfs install --local --skip-repo
  if ($LASTEXITCODE -ne 0) { throw "git lfs install failed (exit $LASTEXITCODE)." }
  Add-ToolReadiness -Tool "git-lfs" -Status "OK" -Detail "LFS filters initialized for this repo."
  
  if (-not $SkipLfsPull) {
    Info "Pulling LFS content (this may take a while on first run)..."
    & git lfs pull
    if ($LASTEXITCODE -ne 0) { throw "git lfs pull failed (exit $LASTEXITCODE)." }
    Add-ToolReadiness -Tool "git-lfs content" -Status "OK" -Detail "git lfs pull completed."
  }
  else {
    Warn "Skipping 'git lfs pull' (SkipLfsPull set)."
    Add-ToolReadiness -Tool "git-lfs content" -Status "SKIP" -Detail "git lfs pull skipped by parameter."
  }
  
  # --- Configure recommended repo-local git settings ---
  Info "Applying recommended repo-local git config..."
  & git config --local core.hooksPath .githooks
  & git config --local fetch.prune true
  & git config --local pull.ff only
  & git config --local core.autocrlf input
  & git config --local core.eol lf
  & git config --local core.safecrlf warn
  & git config --local advice.mergeConflict false
  
  Ok "Git config applied:"
  & git config --local --get core.hooksPath | ForEach-Object { Write-Host "  core.hooksPath=$_" }
  & git config --local --get pull.ff        | ForEach-Object { Write-Host "  pull.ff=$_" }
  & git config --local --get fetch.prune    | ForEach-Object { Write-Host "  fetch.prune=$_" }
  & git config --local --get core.autocrlf  | ForEach-Object { Write-Host "  core.autocrlf=$_" }
  & git config --local --get core.eol       | ForEach-Object { Write-Host "  core.eol=$_" }
  & git config --local --get core.safecrlf  | ForEach-Object { Write-Host "  core.safecrlf=$_" }
  & git config --local --get advice.mergeConflict | ForEach-Object { Write-Host "  advice.mergeConflict=$_" }
  Add-ToolReadiness -Tool "git config" -Status "OK" -Detail "Hooks path, pull, LFS-safe line ending, and conflict advice settings applied."

  Ensure-IgnoredTrackedFilesUntracked `
    -ResolvedRepoRoot $repoRoot `
    -NonInteractiveMode:$NonInteractive `
    -SkipUntrack:$SkipIgnoredUntrack
  
  $originUrl = ((git remote get-url origin 2>$null) | Select-Object -First 1)
  $repoSlug = Get-GitHubRepoSlugFromRemoteUrl -RemoteUrl $originUrl
  
  if (Get-Command gh -ErrorAction SilentlyContinue) {
    if (-not [string]::IsNullOrWhiteSpace($repoSlug)) {
      Info "Configuring GitHub CLI (gh) defaults for this repo (best-effort)..."
      & gh repo set-default $repoSlug
      if ($LASTEXITCODE -eq 0) {
        Add-ToolReadiness -Tool "gh" -Status "OK" -Detail "Default GitHub repo set to $repoSlug."
      }
      else {
        Add-ToolReadiness -Tool "gh" -Status "WARN" -Detail "gh repo set-default failed for $repoSlug."
      }
    }
    else {
      Warn "Skipping GitHub CLI default repo setup because origin does not point to a GitHub repo."
      Add-ToolReadiness -Tool "gh" -Status "SKIP" -Detail "origin does not point to a GitHub repo."
    }
  }
  else {
    Add-ToolReadiness -Tool "gh" -Status "SKIP" -Detail "GitHub CLI is not installed."
  }
  
  Update-DocusaurusGitHubMetadata -ResolvedRepoRoot $repoRoot -RepoSlug $repoSlug
  
  # --- Ensure hook scripts exist ---
  $requiredHooks = @(
    ".githooks\pre-commit",
    ".githooks\pre-push",
    ".githooks\post-checkout",
    ".githooks\post-merge",
    ".githooks\post-commit",
    ".githooks\post-rewrite"
  )
  
  $requiredShared = @(
    "Scripts\git-hooks\colors.sh",
    "Scripts\git-hooks\hook-common.sh"
  )
  
  $requiredHelpers = @(
    "Scripts\UETools\UEToolSuite.Git.psm1",
    "Scripts\UETools\UEToolSuite.Art.psm1",
    "Scripts\UETools\UEToolSuite.AI.psm1",
    "Scripts\Unreal\ProjectContext.ps1",
    "Scripts\ue-tools.ps1"
  )
  
  $requiredTests = @(
    "Scripts\git-hooks\Test-Hooks.ps1"
  )
  
  $missing = @()
  foreach ($p in @($requiredHooks + $requiredShared + $requiredHelpers + $requiredTests)) {
    if (-not (Test-Path (Join-Path $repoRoot $p))) { $missing += $p }
  }
  
  if ($missing.Count -gt 0) {
    Err "Missing required file(s):"
    $missing | Sort-Object -Unique | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    throw "Required files are missing. Pull latest changes and re-run Init-Repo."
  }
  
  # --- Mark hook scripts and shared sh scripts executable in the index (best-effort) ---
  Info "Ensuring hooks + shared hook scripts are marked executable in git index..."
  $chmodPaths = @(
    ".githooks/pre-commit",
    ".githooks/pre-push",
    ".githooks/post-checkout",
    ".githooks/post-merge",
    ".githooks/post-commit",
    ".githooks/post-rewrite",
    "Scripts/git-hooks/colors.sh",
    "Scripts/git-hooks/hook-common.sh"
  )
  
  foreach ($p in $chmodPaths) {
    & git update-index --chmod=+x -- $p 2>$null | Out-Null
  }
  Ok "Exec bits updated (best-effort)."
  Add-ToolReadiness -Tool "hook scripts" -Status "OK" -Detail "Hook and shared shell scripts are marked executable in the git index where applicable."
  
  # --- Run hook enable script (idempotent) ---
  $enableHooks = Join-Path $repoRoot "Scripts\git-hooks\Enable-GitHooks.ps1"
  if (Test-Path $enableHooks) {
    Info "Running Enable-GitHooks.ps1..."
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $enableHooks
    if ($LASTEXITCODE -ne 0) { throw "Enable-GitHooks.ps1 failed (exit $LASTEXITCODE)." }
    Add-ToolReadiness -Tool "git hooks" -Status "OK" -Detail "Enable-GitHooks.ps1 completed."
  }
  else {
    Warn "Enable-GitHooks.ps1 not found at Scripts\git-hooks\Enable-GitHooks.ps1 (skipping)."
    Add-ToolReadiness -Tool "git hooks" -Status "WARN" -Detail "Enable-GitHooks.ps1 was not found."
  }
  
  # --- Configure git aliases for conflict helpers ---
  Info "Configuring git aliases: ours / theirs / conflicts ..."
  & git config --local alias.ours     '!pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/ue-tools.ps1 -RepoRoot . git ours'
  & git config --local alias.theirs   '!pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/ue-tools.ps1 -RepoRoot . git theirs'
  & git config --local alias.conflicts '!pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/ue-tools.ps1 -RepoRoot . git'
  
  if ($LASTEXITCODE -ne 0) { throw "Failed to configure conflict helper aliases." }
  
  Ok "Aliases configured:"
  & git config --local --get alias.ours      | ForEach-Object { Write-Host "  alias.ours=$_" -ForegroundColor Green }
  & git config --local --get alias.theirs    | ForEach-Object { Write-Host "  alias.theirs=$_" -ForegroundColor Green }
  & git config --local --get alias.conflicts | ForEach-Object { Write-Host "  alias.conflicts=$_" -ForegroundColor Green }
  Write-Host "  usage: git ours <patterns...>" -ForegroundColor Green
  Write-Host "  usage: git theirs <patterns...>" -ForegroundColor Green
  Write-Host "  usage: git conflicts <status|sync|continue|abort|restart|help>" -ForegroundColor Green
  Add-ToolReadiness -Tool "git conflict helpers" -Status "OK" -Detail "git ours/theirs/conflicts aliases configured."
  
  # --- Configure shell aliases for project scripts ---
  if ($SkipShellAliases) {
    Warn "Skipping shell alias install (SkipShellAliases set)."
    Add-ToolReadiness -Tool "PowerShell aliases" -Status "SKIP" -Detail "Shell alias install skipped by parameter."
  }
  else {
    Info "Configuring PowerShell aliases for the dispatcher ..."
    try {
      $aliasInstall = Install-ProjectShellAliases -ScriptsRoot (Join-Path $repoRoot "Scripts")
      Ok "PowerShell aliases installed."
      Write-Host "  profile: $($aliasInstall.ProfilePath)" -ForegroundColor Green
  
      foreach ($group in @($aliasInstall.AliasGroups)) {
        $aliasList = @($group.Aliases) -join ", "
        Write-Host "  function: $($group.FunctionName)  aliases: $aliasList" -ForegroundColor Green
      }
  
      Write-Host "  usage: ue-tools help" -ForegroundColor Green
      Write-Host "  usage: ue-tools build -DryRun" -ForegroundColor Green
      Write-Host "  usage: ue-tools build -NoBuild -NoRegen" -ForegroundColor Green
      Write-Host "  usage: ue help" -ForegroundColor Green
      Write-Host "  usage: ue-tools docs help" -ForegroundColor Green
      Write-Host "  usage: ue-tools art" -ForegroundColor Green
      Write-Host "  usage: ue-tools ai prompt -Task `"Fix UnrealSync tests`"" -ForegroundColor Green
      Warn "Open a new PowerShell session (or run: . `"$($aliasInstall.ProfilePath)`") to load aliases."
      Add-ToolReadiness -Tool "PowerShell aliases" -Status "OK" -Detail "Installed aliases: $(@($aliasInstall.Aliases) -join ', ')."
    }
    catch {
      Warn "Could not install PowerShell script aliases."
      Warn $_.Exception.Message
      Add-ToolReadiness -Tool "PowerShell aliases" -Status "WARN" -Detail $_.Exception.Message
    }
  }
  
  # --- Hook self-test ---
  $hookTest = Join-Path $repoRoot "Scripts\git-hooks\Test-Hooks.ps1"
  Info "Running hook self-test..."
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $hookTest
  if ($LASTEXITCODE -ne 0) { throw "Hook self-test failed (exit $LASTEXITCODE)." }
  Ok "Hook self-test completed."
  Add-ToolReadiness -Tool "hook self-test" -Status "OK" -Detail "Scripts\git-hooks\Test-Hooks.ps1 completed."
  
  Initialize-DocsTooling `
    -ResolvedRepoRoot $repoRoot `
    -SkipAll:$SkipOptionalToolSetup `
    -SkipDocs:$SkipDocsSetup `
    -SkipNpmInstall:$SkipDocsNpmInstall `
    -ForceNpmInstall:$ForceDocsNpmInstall `
    -SkipBridgeInstall:$SkipDocsBridgeInstall
  
  if ($SkipOptionalToolSetup) {
    Add-ToolReadiness -Tool "ue-tools art" -Status "SKIP" -Detail "Optional tool setup skipped by parameter."
  }
  else {
    Test-ArtSourceTemplateReady -ResolvedRepoRoot $repoRoot
  }

  if ($createdGitRepository) {
    Invoke-InitialRepositoryCommit -ResolvedRepoRoot $repoRoot -NonInteractiveMode:$NonInteractive
  }
  
  # --- Optional: run UE build/sync once for first-time setup ---
  $ueToolsScript = Join-Path $repoRoot "Scripts\ue-tools.ps1"
  if (-not $SkipUnrealSync -and (Test-Path $ueToolsScript -PathType Leaf)) {
    $isBlueprintOnlyProject = $false
    $declaredModules = @(
      @($projectContext.Modules) | Where-Object {
        $null -ne $_ -and
        $_.PSObject.Properties["Name"] -and
        -not [string]::IsNullOrWhiteSpace([string]$_.Name)
      }
    )
    if ($declaredModules.Count -eq 0) {
      $sourceRoot = Join-Path $projectContext.RepoRoot "Source"
      if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
        $isBlueprintOnlyProject = $true
      }
      else {
        $nativeBuildMarkers = @(
          Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Include "*.Target.cs", "*.Build.cs" -ErrorAction SilentlyContinue
        )
        $isBlueprintOnlyProject = ($nativeBuildMarkers.Count -eq 0)
      }
    }

    if ($isBlueprintOnlyProject) {
      Warn "Blueprint-only project detected (no C++ modules/targets). Skipping first-time ue-tools build."
      Warn "Add a C++ module first if you want init to run regeneration/build automatically."
      Add-ToolReadiness -Tool "ue-tools" -Status "SKIP" -Detail "First-time build skipped for blueprint-only project."
    }
    else {
      Info "Running ue-tools build for first-time setup..."
    
      $_args = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $ueToolsScript,
        "-RepoRoot", $repoRoot,
        "build",
        "-Config", $Config,
        "-Platform", $Platform
      )
      if ($NoBuild) { $_args += "-NoBuild" }
      if ($NoRegen) { $_args += "-NoRegen" }
      if (-not [string]::IsNullOrWhiteSpace($UProjectPath)) { $_args += @("-UProjectPath", $UProjectPath) }
      if (-not [string]::IsNullOrWhiteSpace($WorkspacePath)) { $_args += @("-WorkspacePath", $WorkspacePath) }
    
      & pwsh @_args
      if ($LASTEXITCODE -ne 0) { throw "ue-tools build failed (exit $LASTEXITCODE)." }
    
      Ok "ue-tools build completed."
      Add-ToolReadiness -Tool "ue-tools" -Status "OK" -Detail "ue-tools build completed for first-time setup."
    }
  }
  elseif ($SkipUnrealSync) {
    Warn "Skipping ue-tools build (SkipUnrealSync set)."
    Add-ToolReadiness -Tool "ue-tools" -Status "SKIP" -Detail "ue-tools build skipped by parameter."
  }
  else {
    Warn "ue-tools entrypoint not found at Scripts/ue-tools.ps1 (skipping)."
    Add-ToolReadiness -Tool "ue-tools" -Status "WARN" -Detail "Scripts\ue-tools.ps1 was not found."
  }
  
  Ok "Repo initialization complete."
  Show-ToolReadinessSummary
  Info "Next steps:"
  Write-Host "  - Open repo folder in VS Code" -ForegroundColor Cyan
  Write-Host "  - Verify hooks by attempting a small commit" -ForegroundColor Cyan
  Write-Host "  - During merge/rebase conflicts of binary files, use: git ours / git theirs" -ForegroundColor Cyan
  Write-Host "  - Run Unreal tools manually with: ue-tools help" -ForegroundColor Cyan
  if (Test-Path -LiteralPath (Join-Path $repoRoot "Scripts\UETools\UEToolSuite.Docs.psm1") -PathType Leaf) {
    Write-Host "  - Run docs tools manually with: ue-tools docs help" -ForegroundColor Cyan
  }
  if (Test-Path -LiteralPath (Join-Path $repoRoot "Scripts\UETools\UEToolSuite.Art.psm1") -PathType Leaf) {
    Write-Host "  - Run ArtSource tools manually with: ue-tools art" -ForegroundColor Cyan
  }
  if (Test-Path -LiteralPath (Join-Path $repoRoot "Scripts\UETools\UEToolSuite.AI.psm1") -PathType Leaf) {
    Write-Host "  - Build an AI startup prompt with: ue-tools ai prompt -IncludePrivate" -ForegroundColor Cyan
  }
  
}

Export-ModuleMember -Function Invoke-UEToolSuiteInitRuntime
