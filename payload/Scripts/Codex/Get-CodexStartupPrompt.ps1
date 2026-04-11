[CmdletBinding()]
param(
  [string]$Task,
  [switch]$IncludePrivate,
  [switch]$CopyToClipboard,
  [string]$RepoRoot
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
  param([string]$ExplicitRepoRoot)

  if (-not [string]::IsNullOrWhiteSpace($ExplicitRepoRoot)) {
    $candidate = [System.IO.Path]::GetFullPath($ExplicitRepoRoot)
    if (-not (Test-Path -LiteralPath $candidate)) {
      throw "RepoRoot does not exist: $candidate"
    }

    return $candidate
  }

  $repoRoot = ((git rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    throw "Get-CodexStartupPrompt.ps1 must be run from inside a git repository or passed -RepoRoot."
  }

  return $repoRoot.Trim()
}

function Test-IsExcludedMarkdownPath {
  param([Parameter(Mandatory)][string]$RelativePath)

  $excludedPrefixes = @(
    ".git/",
    ".codex-local/",
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

function Get-RepoMarkdownPaths {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $markdownFiles = Get-ChildItem -LiteralPath $ResolvedRepoRoot -Recurse -File -Filter "*.md"
  $relativePaths = New-Object System.Collections.Generic.List[string]

  foreach ($file in $markdownFiles) {
    $relativePath = [System.IO.Path]::GetRelativePath($ResolvedRepoRoot, $file.FullName).Replace("\", "/")
    if ($relativePath -eq "AGENTS.md") {
      continue
    }
    if (Test-IsExcludedMarkdownPath -RelativePath $relativePath) {
      continue
    }

    $relativePaths.Add($relativePath) | Out-Null
  }

  $docsPaths = @($relativePaths | Where-Object { $_ -like "Docs/*" } | Sort-Object -Unique)
  $otherPaths = @($relativePaths | Where-Object { $_ -notlike "Docs/*" } | Sort-Object -Unique)

  return @($docsPaths + $otherPaths)
}

function Get-CodingStandardsSnapshotInfo {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $currentSnapshotRoot = Join-Path $ResolvedRepoRoot "Docs\CodingStandards\Current"
  $sourcePath = Join-Path $currentSnapshotRoot "SOURCE.md"

  if (-not (Test-Path -LiteralPath $currentSnapshotRoot)) {
    return [pscustomobject]@{
      Exists = $false
      Path = $null
      SnapshotDate = $null
      IsStale = $false
      HasValidDate = $false
    }
  }

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
    Path = "Docs/CodingStandards/Current"
    SnapshotDate = $snapshotDate
    IsStale = $isStale
    HasValidDate = $hasValidDate
  }
}

$resolvedRepoRoot = Resolve-RepoRoot -ExplicitRepoRoot $RepoRoot
$repoMarkdownPaths = @(Get-RepoMarkdownPaths -ResolvedRepoRoot $resolvedRepoRoot)
$snapshotInfo = Get-CodingStandardsSnapshotInfo -ResolvedRepoRoot $resolvedRepoRoot
$privateContextPath = ".codex-local/Private-Context.md"
$privateContextExists = Test-Path -LiteralPath (Join-Path $resolvedRepoRoot $privateContextPath)

if ($IncludePrivate -and -not $privateContextExists) {
  Write-Warning "Private context requested but not found: $privateContextPath"
}

if ($CopyToClipboard -and -not (Get-Command Set-Clipboard -ErrorAction SilentlyContinue)) {
  throw "Set-Clipboard is not available in this PowerShell session."
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Read AGENTS.md first.") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("Then read these repo markdown docs before doing substantial work:") | Out-Null

foreach ($relativePath in $repoMarkdownPaths) {
  $lines.Add("- $relativePath") | Out-Null
}

$lines.Add("") | Out-Null

if ($snapshotInfo.Exists) {
  if ($snapshotInfo.HasValidDate) {
    $lines.Add(("Current Unreal C++ standard snapshot: {0} ({1:yyyy-MM-dd})." -f $snapshotInfo.Path, $snapshotInfo.SnapshotDate)) | Out-Null
  }
  else {
    $lines.Add(("Current Unreal C++ standard snapshot: {0} (snapshot date missing from SOURCE.md)." -f $snapshotInfo.Path)) | Out-Null
  }

  if ($snapshotInfo.HasValidDate -and $snapshotInfo.IsStale) {
    $lines.Add("It is older than six months. Refresh it with `pwsh -File Docs/CodingStandards/Sync-UnrealCppStandard.ps1` before treating the local standard reference as current.") | Out-Null
  }
  elseif ($snapshotInfo.HasValidDate) {
    $lines.Add("It is not older than six months.") | Out-Null
  }
  else {
    $lines.Add("Refresh SOURCE.md and re-run `pwsh -File Docs/CodingStandards/Sync-UnrealCppStandard.ps1` before treating the local standard reference as current.") | Out-Null
  }
}
else {
  $lines.Add("No local Unreal C++ standard snapshot was found under Docs/CodingStandards/Current/.") | Out-Null
}

$lines.Add("If this task touches C++ or style-sensitive code, scrutinize Docs/CodingStandards/README.md, Docs/CodingStandards/UnrealCppStandard.md, and Docs/CodingStandards/Current/SOURCE.md first.") | Out-Null

if (-not [string]::IsNullOrWhiteSpace($Task)) {
  $lines.Add("") | Out-Null
  $lines.Add("Task:") | Out-Null
  $lines.Add("- $Task") | Out-Null
}

if ($IncludePrivate -and $privateContextExists) {
  $lines.Add("") | Out-Null
  $lines.Add("Also use .codex-local/Private-Context.md for my local preferences.") | Out-Null
}

$prompt = $lines -join "`r`n"

if ($CopyToClipboard) {
  Set-Clipboard -Value $prompt
  Write-Host "[Codex Prompt] Copied startup prompt to clipboard." -ForegroundColor Green
}

Write-Output $prompt
