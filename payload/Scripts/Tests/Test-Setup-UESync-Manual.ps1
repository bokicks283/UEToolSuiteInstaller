[CmdletBinding()]
param(
  [switch]$Cleanup,
  [string]$BranchName = "test/ue-sync-manual",
  [string]$CommitMessage = "test: prepare UE Sync manual structural change",
  [string]$ReturnBranch = "",
  [string]$RelativeTestFile = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = ((git rev-parse --show-toplevel 2>$null) | Select-Object -First 1).Trim()
if (-not $repoRoot) {
  throw "Not inside a git repository."
}

Set-Location $repoRoot

$projectContextHelper = Join-Path $repoRoot "Scripts\Unreal\ProjectContext.ps1"
if (-not (Test-Path -LiteralPath $projectContextHelper)) {
  throw "Project context helper not found: $projectContextHelper"
}

. $projectContextHelper
$projectContext = Get-ProjectContext -RepoRoot $repoRoot

$currentBranch = ((git rev-parse --abbrev-ref HEAD 2>$null) | Select-Object -First 1).Trim()
$head = ((git rev-parse HEAD 2>$null) | Select-Object -First 1).Trim()

if (-not $head) {
  throw "Repository has no commits yet. Create an initial commit before using this manual helper."
}

if ([string]::IsNullOrWhiteSpace($ReturnBranch) -and $currentBranch -and $currentBranch -ne "HEAD") {
  $ReturnBranch = $currentBranch
}

if ($Cleanup) {
  if ($currentBranch -eq $BranchName) {
    if ([string]::IsNullOrWhiteSpace($ReturnBranch)) {
      throw "Cleanup requires -ReturnBranch when the active branch is '$BranchName'."
    }

    & git checkout -- $ReturnBranch
    if ($LASTEXITCODE -ne 0) {
      throw "Could not switch back to '$ReturnBranch' before cleanup."
    }
  }

  & git show-ref --verify --quiet "refs/heads/$BranchName"
  if ($LASTEXITCODE -eq 0) {
    & git branch -D -- $BranchName
    if ($LASTEXITCODE -ne 0) {
      throw "Could not delete branch '$BranchName'."
    }
    Write-Host "Removed manual UE Sync branch: $BranchName"
  }
  else {
    Write-Host "Manual UE Sync branch not present: $BranchName"
  }

  exit 0
}

$dirty = @((git status --porcelain 2>$null) | Where-Object { $_ -and $_.Trim() -ne "" })
if ($dirty.Count -gt 0) {
  throw "Working tree is not clean. Commit or stash changes before preparing a manual UE Sync test branch."
}

$targetRelativePath = if ([string]::IsNullOrWhiteSpace($RelativeTestFile)) {
  "Source/$($projectContext.PrimaryModuleName)/UE_Sync_ManualTest.h"
}
else {
  $RelativeTestFile
}
$targetAbsolutePath = Join-Path $repoRoot $targetRelativePath

& git checkout -B -- $BranchName
if ($LASTEXITCODE -ne 0) {
  throw "Could not create or switch to branch '$BranchName'."
}

$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$fileBody = @(
  "#pragma once"
  ""
  '#include "CoreMinimal.h"'
  ""
  "// Temporary structural change used to manually validate UE Sync behavior."
  "namespace UESyncManualTest_$timestamp"
  "{"
  "  constexpr int32 Value = 1;"
  "}"
) -join "`n"

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetAbsolutePath) | Out-Null
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($targetAbsolutePath, $fileBody, $utf8NoBom)

& git add -- $targetRelativePath
if ($LASTEXITCODE -ne 0) {
  throw "Could not stage manual test file '$targetRelativePath'."
}

& git commit -m $CommitMessage
if ($LASTEXITCODE -ne 0) {
  throw "Could not commit the manual UE Sync test change."
}

Write-Host "Prepared manual UE Sync validation branch."
Write-Host "Project:      $($projectContext.ProjectName)"
Write-Host "Branch:       $BranchName"
Write-Host "Test file:    $targetRelativePath"
if (-not [string]::IsNullOrWhiteSpace($ReturnBranch)) {
  Write-Host "Return branch: $ReturnBranch"
}
Write-Host "Next steps:"
Write-Host "  1. Check out another branch to trigger the post-checkout hook."
Write-Host "  2. Confirm UE Sync detects the structural change."
Write-Host "  3. Run this script again with -Cleanup to remove the manual branch."
