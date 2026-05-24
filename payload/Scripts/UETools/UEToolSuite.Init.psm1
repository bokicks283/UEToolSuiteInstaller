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
  $runtimePath = Join-Path $resolvedRepoRoot "Scripts\Init-Repo.Runtime.ps1"
  if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
    throw "The 'init' domain is not installed for this repo. Missing required path: $runtimePath. Re-run the installer with base tooling."
  }

  $previousNoAutorun = $env:UE_TOOLS_INIT_RUNTIME_NO_AUTORUN
  $env:UE_TOOLS_INIT_RUNTIME_NO_AUTORUN = "1"
  try {
    . $runtimePath
  }
  finally {
    if ([string]::IsNullOrEmpty($previousNoAutorun)) {
      Remove-Item Env:UE_TOOLS_INIT_RUNTIME_NO_AUTORUN -ErrorAction SilentlyContinue
    }
    else {
      $env:UE_TOOLS_INIT_RUNTIME_NO_AUTORUN = $previousNoAutorun
    }
  }
  if (-not (Get-Command -Name "Invoke-UEToolSuiteInitRuntime" -CommandType Function -ErrorAction SilentlyContinue)) {
    throw "Init runtime entrypoint not found after loading $runtimePath."
  }

  $parameters = ConvertTo-UEToolSuiteInitParameters -RepoRoot $resolvedRepoRoot -CommandArguments $CommandArguments
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
  Invoke-UEToolSuiteInitCommand
