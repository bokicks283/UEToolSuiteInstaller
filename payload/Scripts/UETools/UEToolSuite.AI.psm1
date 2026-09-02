function Resolve-UEToolSuiteAIRepoRoot {
  [CmdletBinding()]
  param(
    [string]$ExplicitRepoRoot,
    [string]$InvocationName = "ue-tools ai prompt"
  )

  if (-not [string]::IsNullOrWhiteSpace($ExplicitRepoRoot)) {
    $candidate = [System.IO.Path]::GetFullPath($ExplicitRepoRoot)
    if (-not (Test-Path -LiteralPath $candidate)) {
      throw "RepoRoot does not exist: $candidate"
    }

    return (Resolve-Path -LiteralPath $candidate).Path
  }

  $repoRoot = ((git rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    throw "$InvocationName must be run from inside a git repository or passed -RepoRoot."
  }

  return $repoRoot.Trim()
}

function Test-UEToolSuiteAIExcludedMarkdownPath {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RelativePath)

  if ($RelativePath -match '^\.[^/]+-local/') {
    return $true
  }

  $excludedPrefixes = @(
    ".git/",
    ".ue-tools-installer-backups/",
    "Binaries/",
    "DerivedDataCache/",
    "Intermediate/",
    "Saved/",
    "website/.docusaurus/",
    "website/build/",
    "website/node_modules/"
  )

  foreach ($prefix in $excludedPrefixes) {
    if ($RelativePath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }

  return $false
}

function Get-UEToolSuiteAIRepoMarkdownPaths {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $markdownFiles = Get-ChildItem -LiteralPath $ResolvedRepoRoot -Recurse -File -Filter "*.md"
  $relativePaths = New-Object System.Collections.Generic.List[string]

  foreach ($file in $markdownFiles) {
    $relativePath = [System.IO.Path]::GetRelativePath($ResolvedRepoRoot, $file.FullName).Replace("\", "/")
    if ($relativePath -eq "AGENTS.md") {
      continue
    }
    if (Test-UEToolSuiteAIExcludedMarkdownPath -RelativePath $relativePath) {
      continue
    }

    $relativePaths.Add($relativePath) | Out-Null
  }

  $docsPaths = @($relativePaths | Where-Object { $_ -like "Docs/*" } | Sort-Object -Unique)
  $otherPaths = @($relativePaths | Where-Object { $_ -notlike "Docs/*" } | Sort-Object -Unique)
  return @($docsPaths + $otherPaths)
}

function Get-UEToolSuiteAICodingStandardsSnapshotInfo {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $snapshotCandidates = @(
    [pscustomobject]@{
      Root = Join-Path $ResolvedRepoRoot "Docs\WorkflowStandards\CodingStandards\Current"
      RelativePath = "Docs/WorkflowStandards/CodingStandards/Current"
    },
    [pscustomobject]@{
      Root = Join-Path $ResolvedRepoRoot "Docs\CodingStandards\Current"
      RelativePath = "Docs/CodingStandards/Current"
    }
  )
  $snapshotCandidate = @($snapshotCandidates | Where-Object { Test-Path -LiteralPath $_.Root -PathType Container } | Select-Object -First 1)

  if ($snapshotCandidate.Count -eq 0) {
    return [pscustomobject]@{
      Exists = $false
      Path = $null
      SnapshotDate = $null
      IsStale = $false
      HasValidDate = $false
    }
  }

  $currentSnapshotRoot = [string]$snapshotCandidate[0].Root
  $relativeSnapshotPath = [string]$snapshotCandidate[0].RelativePath
  $sourcePath = Join-Path $currentSnapshotRoot "SOURCE.md"

  $snapshotDate = $null
  $hasValidDate = $false
  if (Test-Path -LiteralPath $sourcePath) {
    $sourceText = Get-Content -LiteralPath $sourcePath -Raw
    if ($sourceText -match '(?m)^\s*-\s*Snapshot date:\s*(?<date>\d{4}-\d{2}-\d{2})\s*$') {
      $snapshotDate = [datetime]::ParseExact($Matches.date, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
      $hasValidDate = $true
    }
  }

  $isStale = $false
  if ($hasValidDate) {
    $isStale = $snapshotDate.Date.AddMonths(6) -lt (Get-Date).Date
  }

  return [pscustomobject]@{
    Exists = $true
    Path = $relativeSnapshotPath
    SnapshotDate = $snapshotDate
    IsStale = $isStale
    HasValidDate = $hasValidDate
  }
}

function New-UEToolSuiteAIStartupPrompt {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string]$Task,
    [switch]$IncludePrivate
  )

  $repoMarkdownPaths = @(Get-UEToolSuiteAIRepoMarkdownPaths -ResolvedRepoRoot $ResolvedRepoRoot)
  $snapshotInfo = Get-UEToolSuiteAICodingStandardsSnapshotInfo -ResolvedRepoRoot $ResolvedRepoRoot
  $privateContextPath = ".ai-local/Private-Context.md"
  $privateContextExists = Test-Path -LiteralPath (Join-Path $ResolvedRepoRoot $privateContextPath)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("Read AGENTS.md first.") | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("Then read these repo markdown docs before doing substantial work:") | Out-Null

  foreach ($relativePath in $repoMarkdownPaths) {
    $lines.Add("- $relativePath") | Out-Null
  }

  $lines.Add("") | Out-Null

  if ($snapshotInfo.Exists) {
    $codingStandardsRoot = $snapshotInfo.Path -replace '/Current$', ''
    $syncScriptPath = "$codingStandardsRoot/Sync-UnrealCppStandard.ps1"
    if ($snapshotInfo.HasValidDate) {
      $lines.Add(("Current Unreal C++ standard snapshot: {0} ({1:yyyy-MM-dd})." -f $snapshotInfo.Path, $snapshotInfo.SnapshotDate)) | Out-Null
    }
    else {
      $lines.Add(("Current Unreal C++ standard snapshot: {0} (snapshot date missing from SOURCE.md)." -f $snapshotInfo.Path)) | Out-Null
    }

    if ($snapshotInfo.HasValidDate -and $snapshotInfo.IsStale) {
      $lines.Add("It is older than six months. Refresh it with `pwsh -File $syncScriptPath` before treating the local standard reference as current.") | Out-Null
    }
    elseif ($snapshotInfo.HasValidDate) {
      $lines.Add("It is not older than six months.") | Out-Null
    }
    else {
      $lines.Add("Refresh SOURCE.md and re-run `pwsh -File $syncScriptPath` before treating the local standard reference as current.") | Out-Null
    }
  }
  else {
    $lines.Add("No local Unreal C++ standard snapshot was found under Docs/WorkflowStandards/CodingStandards/Current/ or the legacy Docs/CodingStandards/Current/ path.") | Out-Null
  }

  $lines.Add("If this task touches C++ or style-sensitive code, scrutinize Docs/WorkflowStandards/CodingStandards/README.md, Docs/WorkflowStandards/CodingStandards/UnrealCppStandard.md, and Docs/WorkflowStandards/CodingStandards/Current/SOURCE.md first.") | Out-Null

  if (-not [string]::IsNullOrWhiteSpace($Task)) {
    $lines.Add("") | Out-Null
    $lines.Add("Task:") | Out-Null
    $lines.Add("- $Task") | Out-Null
  }

  if ($IncludePrivate -and $privateContextExists) {
    $lines.Add("") | Out-Null
    $lines.Add("Also use .ai-local/Private-Context.md for my local preferences.") | Out-Null
  }

  return [pscustomobject]@{
    Prompt = ($lines -join "`r`n")
    PrivateContextPath = $privateContextPath
    PrivateContextExists = [bool]$privateContextExists
  }
}

function Invoke-UEToolSuiteAIPromptCommand {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [AllowNull()][string[]]$CommandArguments = @()
  )

  $normalizedArgs = New-Object System.Collections.Generic.List[string]
  foreach ($arg in @($CommandArguments)) {
    if ($null -eq $arg) { continue }
    $text = [string]$arg
    if ([string]::IsNullOrWhiteSpace($text)) { continue }
    $normalizedArgs.Add($text) | Out-Null
  }
  $argsList = @($normalizedArgs.ToArray())

  $task = $null
  $includePrivate = $false
  $copyToClipboard = $false
  $showHelp = $false
  $i = 0
  while ($i -lt $argsList.Count) {
    $token = [string]$argsList[$i]
    $normalized = $token.Trim().ToLowerInvariant()
    if ($normalized -eq "-task") {
      if (($i + 1) -ge $argsList.Count) {
        throw "Missing value for -Task."
      }
      $task = [string]$argsList[$i + 1]
      $i += 2
      continue
    }
    elseif ($normalized -eq "-includeprivate") {
      $includePrivate = $true
      $i += 1
      continue
    }
    elseif ($normalized -eq "-copytoclipboard") {
      $copyToClipboard = $true
      $i += 1
      continue
    }
    elseif ($normalized -in @("help", "--help", "-help", "-h", "/?", "-?")) {
      $showHelp = $true
      break
    }
    else {
      throw "Unknown ai prompt option '$token'. Supported options: -Task <text>, -IncludePrivate, -CopyToClipboard."
    }
  }

  if ($showHelp) {
    @(
      "Usage: ue-tools ai prompt [options]"
      "Options:"
      "  -Task <text>          Optional task context line."
      "  -IncludePrivate       Include .ai-local/Private-Context.md guidance when present."
      "  -CopyToClipboard      Copy the generated prompt to clipboard."
      "Examples:"
      "  ue-tools ai prompt -Task `"Investigate UnrealSync failures`""
      "  ue-tools ai prompt -IncludePrivate -CopyToClipboard"
    ) | Write-Output
    return
  }

  $resolvedRepoRoot = Resolve-UEToolSuiteAIRepoRoot -ExplicitRepoRoot $RepoRoot -InvocationName "ue-tools ai prompt"
  $promptResult = New-UEToolSuiteAIStartupPrompt -ResolvedRepoRoot $resolvedRepoRoot -Task $task -IncludePrivate:$includePrivate

  if ($includePrivate -and -not [bool]$promptResult.PrivateContextExists) {
    Write-Warning "Private context requested but not found: $($promptResult.PrivateContextPath)"
  }

  if ($copyToClipboard) {
    if (-not (Get-Command -Name "Set-Clipboard" -ErrorAction SilentlyContinue)) {
      throw "Set-Clipboard is not available in this PowerShell session."
    }

    Set-Clipboard -Value ([string]$promptResult.Prompt)
    Write-Host "[AI Prompt] Copied startup prompt to clipboard." -ForegroundColor Green
  }

  Write-Output ([string]$promptResult.Prompt)
}

Export-ModuleMember -Function `
  Resolve-UEToolSuiteAIRepoRoot, `
  Test-UEToolSuiteAIExcludedMarkdownPath, `
  Get-UEToolSuiteAIRepoMarkdownPaths, `
  Get-UEToolSuiteAICodingStandardsSnapshotInfo, `
  New-UEToolSuiteAIStartupPrompt, `
  Invoke-UEToolSuiteAIPromptCommand
