function Get-UEToolSuiteGitConflictsHelpLines {
  [CmdletBinding()]
  param()

  return @(
    ""
    "Unreal Binary Conflict Helpers"
    "--------------------------------"
    "These commands enforce safe resolution for guarded binary assets (e.g. .uasset/.umap/.png) during merges/rebases."
    "Use git ours / git theirs to pick a side for guarded files. Use git conflicts status/sync to inspect approvals."
    ""
    "Usage:"
    "  git ours   <pattern> [pattern...] [--verbose|-v]"
    "  git theirs <pattern> [pattern...] [--verbose|-v]"
    "  git conflicts <command> [--verbose|-v] [--skip-editor|-se]"
    ""
    "Commands:"
    "  ours"
    "    Resolve guarded binary conflicts by choosing the OURS side."
    "    (In a rebase, ours/theirs are flipped to match human meaning.)"
    "  theirs"
    "    Resolve guarded binary conflicts by choosing the THEIRS side."
    "  conflicts status"
    "    Show current merge/rebase context and approval status."
    "  conflicts sync"
    "    Recompute required guarded set and refresh context-bound ledgers."
    "  conflicts continue"
    "    Continue rebase after resolving conflicts (enforces guard before continuing)."
    "  conflicts abort"
    "    Abort the current merge or rebase operation (no effect if none is active)."
    "  conflicts restart"
    "    Abort and attempt to re-run the current merge/rebase using detected args."
    "  conflicts help"
    "    Show this help."
    ""
    "Notes:"
    "  - Patterns are PowerShell -like wildcards (not bash globs). Quote patterns with * or **."
    "  - Example pattern: ""**/*.uasset"" or ""Content/Test/*.png"" or ""*"" for all conflicted files"
    "  - -v / --verbose prints detailed file lists and internal context info."
    "  - --skip-editor / -se skips commit message editing during rebase --continue (for automation)."
    ""
  )
}

function Write-UEToolSuiteGitConflictsHelp {
  [CmdletBinding()]
  param()

  $lines = @(Get-UEToolSuiteGitConflictsHelpLines)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -eq "Unreal Binary Conflict Helpers" -or $line -eq "--------------------------------" -or $line -eq "Usage:" -or $line -eq "Commands:" -or $line -eq "Notes:") {
      Write-Host $line -ForegroundColor Cyan
      continue
    }

    if ($line -match "^  ours$|^  theirs$|^  conflicts status$|^  conflicts sync$|^  conflicts continue$|^  conflicts abort$|^  conflicts restart$|^  conflicts help$") {
      Write-Host $line -ForegroundColor Green
      continue
    }

    if ($line -eq "") {
      Write-Host ""
      continue
    }

    Write-Host $line -ForegroundColor Gray
  }
}

function Split-UEToolSuiteGitConflictsArguments {
  [CmdletBinding()]
  param([string[]]$ArgsList)

  $skipEditor = $false
  $filteredArgs = New-Object System.Collections.Generic.List[string]

  foreach ($arg in @($ArgsList)) {
    if ($arg -eq "-SkipEditor" -or $arg -eq "--skip-editor" -or $arg -eq "-se") {
      $skipEditor = $true
      continue
    }

    $filteredArgs.Add($arg) | Out-Null
  }

  return [pscustomobject]@{
    SkipEditor = [bool]$skipEditor
    Args = @($filteredArgs.ToArray())
  }
}

function Enable-UEToolSuiteGitHooks {
  [CmdletBinding()]
  param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$HooksPath = ".githooks"
  )

  $resolvedRoot = [System.IO.Path]::GetFullPath($RepoRoot)
  if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
    throw "Repo root does not exist: $resolvedRoot"
  }

  & git -C $resolvedRoot config --local core.hooksPath $HooksPath
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to set git core.hooksPath to '$HooksPath'."
  }

  $hooksRootPath = Join-Path $resolvedRoot ($HooksPath -replace "/", "\")
  $postCheckoutPath = Join-Path $hooksRootPath "post-checkout"
  if (-not (Test-Path -LiteralPath $postCheckoutPath -PathType Leaf)) {
    Write-Warning "Missing $HooksPath/post-checkout. Did you pull the repo changes?"
  }
}

function Get-UEToolSuiteGitDir {
  [CmdletBinding()]
  param()

  $gitDir = (git rev-parse --git-dir 2>$null)
  if (-not $gitDir) {
    throw "Not inside a git repository."
  }

  return (Resolve-Path -LiteralPath $gitDir).Path
}

function Get-UEToolSuiteGitPath {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path)

  $resolved = (git rev-parse --git-path $Path 2>$null).Trim()
  if (-not $resolved) {
    return $null
  }

  return $resolved
}

function Test-UEToolSuiteGitPathExists {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path)

  $resolved = Get-UEToolSuiteGitPath -Path $Path
  if (-not $resolved) {
    return $false
  }

  return (Test-Path -LiteralPath $resolved)
}

function Read-UEToolSuiteGitFile {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  return (Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue).Trim()
}

function Get-UEToolSuiteGitContext {
  [CmdletBinding()]
  param()

  if (Test-UEToolSuiteGitPathExists -Path "MERGE_HEAD") { return "merge" }
  if (Test-UEToolSuiteGitPathExists -Path "CHERRY_PICK_HEAD") { return "merge" }
  if (Test-UEToolSuiteGitPathExists -Path "REVERT_HEAD") { return "merge" }
  if (Test-UEToolSuiteGitPathExists -Path "rebase-merge") { return "rebase" }
  if (Test-UEToolSuiteGitPathExists -Path "rebase-apply") { return "rebase" }
  return "none"
}

function Test-UEToolSuiteGitRebaseStateDirsPresent {
  [CmdletBinding()]
  param()

  $mergeDir = Get-UEToolSuiteGitPath -Path "rebase-merge"
  if ($mergeDir -and (Test-Path -LiteralPath $mergeDir -PathType Container)) {
    return $true
  }

  $applyDir = Get-UEToolSuiteGitPath -Path "rebase-apply"
  if ($applyDir -and (Test-Path -LiteralPath $applyDir -PathType Container)) {
    return $true
  }

  return $false
}

function Get-UEToolSuiteGitLedgerPaths {
  [CmdletBinding()]
  param()

  $gitDir = Get-UEToolSuiteGitDir
  return [pscustomobject]@{
    Context  = Join-Path $gitDir "ue_binary_conflicts.context"
    Resolved = Join-Path $gitDir "ue_binary_conflicts.resolved"
    Audit    = Join-Path $gitDir "ue_binary_conflicts.audit"
  }
}

function Get-UEToolSuiteGitMTimeEpoch {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path)

  try {
    if (-not (Test-Path -LiteralPath $Path)) {
      return $null
    }

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    return [DateTimeOffset]::new($item.LastWriteTimeUtc).ToUnixTimeSeconds()
  }
  catch {
    return $null
  }
}

function Get-UEToolSuiteGitOperationStamp {
  [CmdletBinding()]
  param([string]$Context)

  $ctx = $Context
  if ([string]::IsNullOrWhiteSpace($ctx)) {
    $ctx = Get-UEToolSuiteGitContext
  }

  $gitDir = Get-UEToolSuiteGitDir

  if ($ctx -eq "merge") {
    $mergeHeadPath = Join-Path $gitDir "MERGE_HEAD"
    $stamp = Get-UEToolSuiteGitMTimeEpoch -Path $mergeHeadPath
    return $(if ($stamp) { $stamp.ToString() } else { "nostamp" })
  }

  if ($ctx -eq "rebase") {
    $rebaseMergeRoot = Join-Path $gitDir "rebase-merge"
    $rebaseApplyRoot = Join-Path $gitDir "rebase-apply"
    $candidates = @(
      (Join-Path $rebaseMergeRoot "onto"),
      (Join-Path $rebaseMergeRoot "head-name"),
      (Join-Path $rebaseApplyRoot "orig-head")
    )

    foreach ($candidate in $candidates) {
      $stamp = Get-UEToolSuiteGitMTimeEpoch -Path $candidate
      if ($stamp) {
        return $stamp.ToString()
      }
    }

    return "nostamp"
  }

  return $null
}

function Get-UEToolSuiteGitMergeHeadSha {
  [CmdletBinding()]
  param()

  $mergeHeadPath = Get-UEToolSuiteGitPath -Path "MERGE_HEAD"
  if (-not $mergeHeadPath) {
    return $null
  }

  return (Read-UEToolSuiteGitFile -Path $mergeHeadPath)
}

function Get-UEToolSuiteGitRebasePatchSha {
  [CmdletBinding()]
  param()

  $patchCandidates = @(
    (Get-UEToolSuiteGitPath -Path "rebase-merge/patch"),
    (Get-UEToolSuiteGitPath -Path "rebase-apply/patch")
  )

  foreach ($candidate in $patchCandidates) {
    if (-not $candidate -or -not (Test-Path -LiteralPath $candidate)) {
      continue
    }

    $line = Get-Content -LiteralPath $candidate -TotalCount 1 -ErrorAction SilentlyContinue
    if ($line -match '^From\s+([0-9a-f]{7,40})\b') {
      return $Matches[1]
    }
  }

  return $null
}

function Get-UEToolSuiteGitRebasePatchPaths {
  [CmdletBinding()]
  param()

  $patchCandidates = @(
    (Get-UEToolSuiteGitPath -Path "rebase-merge/patch"),
    (Get-UEToolSuiteGitPath -Path "rebase-apply/patch")
  )

  foreach ($candidate in $patchCandidates) {
    if (-not $candidate -or -not (Test-Path -LiteralPath $candidate)) {
      continue
    }

    try {
      if ((Get-Item -LiteralPath $candidate).Length -eq 0) {
        continue
      }
    }
    catch {
      continue
    }

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Get-Content -LiteralPath $candidate -ErrorAction SilentlyContinue)) {
      if ($line -match '^\+\+\+\s+(.+)$') {
        $pathValue = $Matches[1] -replace '^b/', ''
        if ($pathValue -and $pathValue -ne '/dev/null') {
          $paths.Add($pathValue) | Out-Null
        }
        continue
      }

      if ($line -match '^---\s+(.+)$') {
        $pathValue = $Matches[1] -replace '^a/', ''
        if ($pathValue -and $pathValue -ne '/dev/null') {
          $paths.Add($pathValue) | Out-Null
        }
      }
    }

    if ($paths.Count -gt 0) {
      return @($paths | Sort-Object -Unique)
    }
  }

  return @()
}

function Get-UEToolSuiteGitRebaseSeqCurrentSha {
  [CmdletBinding()]
  param()

  $donePath = Get-UEToolSuiteGitPath -Path "rebase-merge/done"
  $todoPath = Get-UEToolSuiteGitPath -Path "rebase-merge/git-rebase-todo"

  if ($donePath -and (Test-Path -LiteralPath $donePath)) {
    $doneLines = Get-Content -LiteralPath $donePath -ErrorAction SilentlyContinue |
      Where-Object { $_ -and ($_ -notmatch '^\s*#') }
    if ($doneLines) {
      $lastLine = $doneLines | Select-Object -Last 1
      if ($lastLine -match '^\s*\S+\s+([0-9a-fA-F]{7,40})\b') {
        return $Matches[1]
      }
    }
  }

  if ($todoPath -and (Test-Path -LiteralPath $todoPath)) {
    $todoLines = Get-Content -LiteralPath $todoPath -ErrorAction SilentlyContinue |
      Where-Object { $_ -and ($_ -notmatch '^\s*#') }
    if ($todoLines) {
      $firstLine = $todoLines | Select-Object -First 1
      if ($firstLine -match '^\s*\S+\s+([0-9a-fA-F]{7,40})\b') {
        return $Matches[1]
      }
    }
  }

  return $null
}

function Get-UEToolSuiteGitRebaseHeadSha {
  [CmdletBinding()]
  param()

  if (-not (Test-UEToolSuiteGitRebaseStateDirsPresent)) {
    return $null
  }

  try {
    $stoppedShaPath = Get-UEToolSuiteGitPath -Path "rebase-merge/stopped-sha"
    if ($stoppedShaPath -and (Test-Path -LiteralPath $stoppedShaPath -PathType Leaf)) {
      $stoppedSha = Get-Content -LiteralPath $stoppedShaPath -Raw -ErrorAction SilentlyContinue
      if ($stoppedSha) {
        $stoppedSha = $stoppedSha.Trim()
        if ($stoppedSha) {
          return $stoppedSha
        }
      }
    }
  }
  catch {
  }

  try {
    $rebaseHeadSha = (git rev-parse -q --verify REBASE_HEAD 2>$null)
    if ($rebaseHeadSha) {
      $rebaseHeadSha = $rebaseHeadSha.Trim()
      if ($rebaseHeadSha) {
        return $rebaseHeadSha
      }
    }
  }
  catch {
  }

  $cherryPickHeadPath = Get-UEToolSuiteGitPath -Path "CHERRY_PICK_HEAD"
  $cherryPickHeadSha = if ($cherryPickHeadPath) { Read-UEToolSuiteGitFile -Path $cherryPickHeadPath } else { $null }
  if ($cherryPickHeadSha) {
    return $cherryPickHeadSha
  }

  $patchSha = Get-UEToolSuiteGitRebasePatchSha
  if ($patchSha) {
    return $patchSha
  }

  $sequenceSha = Get-UEToolSuiteGitRebaseSeqCurrentSha
  if ($sequenceSha) {
    return $sequenceSha
  }

  $origMergePath = Get-UEToolSuiteGitPath -Path "rebase-merge/orig-head"
  $origMergeSha = if ($origMergePath) { Read-UEToolSuiteGitFile -Path $origMergePath } else { $null }
  if ($origMergeSha) {
    return $origMergeSha
  }

  return $null
}

function Get-UEToolSuiteGitRebaseOntoSha {
  [CmdletBinding()]
  param()

  if (-not (Test-UEToolSuiteGitRebaseStateDirsPresent)) {
    return $null
  }

  try {
    $ontoPath = Get-UEToolSuiteGitPath -Path "rebase-merge/onto"
    if ($ontoPath -and (Test-Path -LiteralPath $ontoPath -PathType Leaf)) {
      $ontoValue = Get-Content -LiteralPath $ontoPath -Raw -ErrorAction SilentlyContinue
      if ($ontoValue) {
        $ontoValue = $ontoValue.Trim()
        if ($ontoValue) {
          return $ontoValue
        }
      }
    }
  }
  catch {
  }

  try {
    $ontoPath = Get-UEToolSuiteGitPath -Path "rebase-apply/onto"
    if ($ontoPath -and (Test-Path -LiteralPath $ontoPath -PathType Leaf)) {
      $ontoValue = Get-Content -LiteralPath $ontoPath -Raw -ErrorAction SilentlyContinue
      if ($ontoValue) {
        $ontoValue = $ontoValue.Trim()
        if ($ontoValue) {
          return $ontoValue
        }
      }
    }
  }
  catch {
  }

  return $null
}

function Get-UEToolSuiteGitOtherSideSha {
  [CmdletBinding()]
  param([string]$Context)

  $ctx = $Context
  if ([string]::IsNullOrWhiteSpace($ctx)) {
    $ctx = Get-UEToolSuiteGitContext
  }

  if ($ctx -eq "merge") {
    return (Get-UEToolSuiteGitMergeHeadSha)
  }

  if ($ctx -eq "rebase") {
    return (Get-UEToolSuiteGitRebaseHeadSha)
  }

  return $null
}

function Get-UEToolSuiteGitNormalizedUniquePaths {
  [CmdletBinding()]
  param([AllowNull()][string[]]$Paths)

  return @(
    foreach ($path in @($Paths)) {
      if ($null -eq $path) { continue }
      $normalized = ([string]$path).Trim()
      if (-not $normalized) { continue }
      $normalized
    }
  ) | Sort-Object -Unique
}

function Get-UEToolSuiteGitPathIntersection {
  [CmdletBinding()]
  param(
    [AllowNull()][string[]]$Left,
    [AllowNull()][string[]]$Right
  )

  $leftPaths = @(Get-UEToolSuiteGitNormalizedUniquePaths -Paths $Left)
  $rightPaths = @(Get-UEToolSuiteGitNormalizedUniquePaths -Paths $Right)
  if ($leftPaths.Count -eq 0 -or $rightPaths.Count -eq 0) {
    return @()
  }

  $rightSet = @{}
  foreach ($path in $rightPaths) {
    $rightSet[$path] = $true
  }

  $intersection = New-Object System.Collections.Generic.List[string]
  foreach ($path in $leftPaths) {
    if ($rightSet.ContainsKey($path)) {
      $intersection.Add($path) | Out-Null
    }
  }

  return @($intersection | Sort-Object -Unique)
}

function Get-UEToolSuiteGitMergeOverlapCandidates {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$OtherSideSha)

  $leftRef = "HEAD"
  $mergeBase = (git merge-base $leftRef $OtherSideSha 2>$null)
  if ($mergeBase) {
    $mergeBase = $mergeBase.Trim()
  }
  if (-not $mergeBase) {
    return @()
  }

  $leftPaths = @((git diff --name-only $mergeBase $leftRef 2>$null) -split "`r?`n")
  $rightPaths = @((git diff --name-only $mergeBase $OtherSideSha 2>$null) -split "`r?`n")
  return @(Get-UEToolSuiteGitPathIntersection -Left $leftPaths -Right $rightPaths)
}

function Get-UEToolSuiteGitRebaseOverlapCandidates {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$OtherSideSha,
    [string]$RebaseOntoSha
  )

  $parentSha = $null
  try {
    $parentSha = (git rev-parse -q --verify "${OtherSideSha}^" 2>$null)
    if ($parentSha) {
      $parentSha = $parentSha.Trim()
    }
  }
  catch {
  }

  if ($RebaseOntoSha -and $parentSha) {
    $basePaths = @((git diff --name-only $parentSha $OtherSideSha 2>$null) -split "`r?`n")
    $targetPaths = @((git diff --name-only $parentSha $RebaseOntoSha 2>$null) -split "`r?`n")
    return @(Get-UEToolSuiteGitPathIntersection -Left $basePaths -Right $targetPaths)
  }

  $fallbackBase = if ($parentSha) { $parentSha } else { (git merge-base HEAD $OtherSideSha 2>$null) }
  if ($fallbackBase) {
    $fallbackBase = $fallbackBase.Trim()
  }
  if (-not $fallbackBase) {
    return @()
  }

  $targetRef = if ($RebaseOntoSha) { $RebaseOntoSha } else { "HEAD" }
  $headPaths = @((git diff --name-only $fallbackBase $targetRef 2>$null) -split "`r?`n")
  $commitPaths = @((git diff --name-only $fallbackBase $OtherSideSha 2>$null) -split "`r?`n")
  return @(Get-UEToolSuiteGitPathIntersection -Left $headPaths -Right $commitPaths)
}

function Get-UEToolSuiteGitRequiredGuardedPaths {
  [CmdletBinding()]
  param(
    [AllowNull()][string[]]$UnmergedGuardedPaths,
    [AllowNull()][string[]]$OverlapGuardedPaths
  )

  $required = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($path in @(Get-UEToolSuiteGitNormalizedUniquePaths -Paths $UnmergedGuardedPaths)) {
    if ($path) {
      [void]$required.Add(($path -replace '\\', '/').Trim())
    }
  }
  foreach ($path in @(Get-UEToolSuiteGitNormalizedUniquePaths -Paths $OverlapGuardedPaths)) {
    if ($path) {
      [void]$required.Add(($path -replace '\\', '/').Trim())
    }
  }

  return @($required) | Sort-Object
}

function Get-UEToolSuiteGitApprovedPathsFromLedger {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$ResolvedLedgerPath)

  if (-not (Test-Path -LiteralPath $ResolvedLedgerPath)) {
    return @()
  }

  return @(
    Get-Content -LiteralPath $ResolvedLedgerPath -ErrorAction SilentlyContinue |
      ForEach-Object { ($_ -replace '\\', '/').Trim() } |
      Where-Object { $_ }
  ) | Sort-Object -Unique
}

function Get-UEToolSuiteGitRemainingRequiredPaths {
  [CmdletBinding()]
  param(
    [AllowNull()][string[]]$RequiredPaths,
    [AllowNull()][string[]]$ApprovedPaths
  )

  $required = @(Get-UEToolSuiteGitNormalizedUniquePaths -Paths $RequiredPaths)
  if ($required.Count -eq 0) {
    return @()
  }

  $approvedSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($path in @(Get-UEToolSuiteGitNormalizedUniquePaths -Paths $ApprovedPaths)) {
    if ($path) {
      [void]$approvedSet.Add(($path -replace '\\', '/').Trim())
    }
  }

  $remaining = New-Object System.Collections.Generic.List[string]
  foreach ($path in $required) {
    $normalized = ($path -replace '\\', '/').Trim()
    if (-not $approvedSet.Contains($normalized)) {
      $remaining.Add($normalized) | Out-Null
    }
  }

  return @($remaining | Sort-Object -Unique)
}

function Get-UEToolSuiteGitOperationContextId {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Context,
    [string]$Stamp,
    [string]$OtherSideSha,
    [string]$MergeBaseSha,
    [string]$RebaseOntoSha,
    [string]$RebaseHeadSha
  )

  if ($Context -eq "none") {
    return $null
  }

  $contextStamp = $Stamp
  if (-not $contextStamp) {
    $contextStamp = "nostamp"
  }

  if ($Context -eq "merge") {
    if (-not $OtherSideSha) {
      return "${Context}:unknown:unknown:${contextStamp}"
    }

    if (-not $MergeBaseSha) {
      return "${Context}:${OtherSideSha}:nobase:${contextStamp}"
    }

    return "${Context}:${OtherSideSha}:${MergeBaseSha}:${contextStamp}"
  }

  if ($Context -eq "rebase") {
    $onto = $(if ($RebaseOntoSha) { $RebaseOntoSha } else { "unknown" })
    $head = $(if ($RebaseHeadSha) { $RebaseHeadSha } else { "unknown" })
    return "${Context}:${onto}:${head}:${contextStamp}"
  }

  if (-not $OtherSideSha) {
    return "${Context}:unknown:unknown:${contextStamp}"
  }

  if (-not $MergeBaseSha) {
    return "${Context}:${OtherSideSha}:nobase:${contextStamp}"
  }

  return "${Context}:${OtherSideSha}:${MergeBaseSha}:${contextStamp}"
}

function Get-UEToolSuiteGitContextLedgerTransition {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Context,
    [string]$CurrentContextId,
    [string]$PreviousContextId
  )

  if ($Context -eq "none" -or -not $CurrentContextId) {
    return [pscustomobject]@{
      Action = "clear"
      ContextId = $CurrentContextId
      PreviousContextId = $PreviousContextId
      AuditMessage = $null
    }
  }

  if ($PreviousContextId -and $PreviousContextId -eq $CurrentContextId) {
    return [pscustomobject]@{
      Action = "noop"
      ContextId = $CurrentContextId
      PreviousContextId = $PreviousContextId
      AuditMessage = $null
    }
  }

  return [pscustomobject]@{
    Action = "reset"
    ContextId = $CurrentContextId
    PreviousContextId = $PreviousContextId
    AuditMessage = "context changed -> reset resolved to prevent stale approvals ($CurrentContextId)"
  }
}

function Import-UEToolSuiteGitConflictHelpers {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $domainPath = Join-Path $RepoRoot "Scripts\UETools\UEToolSuite.Git.psm1"
  if (-not (Test-Path -LiteralPath $domainPath -PathType Leaf)) {
    throw "The 'git' domain is not installed for this repo. Missing required path: $domainPath. Re-run the installer with git helper tooling included."
  }

  return (Resolve-Path -LiteralPath $domainPath).Path
}

function Invoke-UEToolSuiteGitCommand {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [AllowNull()][string[]]$CommandArguments = @()
  )

  [void](Import-UEToolSuiteGitConflictHelpers -RepoRoot $RepoRoot)

  [string[]]$effectiveArgs = if ($null -eq $CommandArguments -or @($CommandArguments).Count -eq 0) {
    @("help")
  }
  else {
    @($CommandArguments)
  }

  $command = ([string]$effectiveArgs[0]).Trim().ToLowerInvariant()
  $argsList = if ($effectiveArgs.Count -gt 1) { @($effectiveArgs[1..($effectiveArgs.Count - 1)]) } else { @() }

  $verboseMode = $PSBoundParameters.ContainsKey('Verbose') -or ($VerbosePreference -ne 'SilentlyContinue')
  $skipEditor = $false
  if (Get-Command -Name "Split-UEToolSuiteGitConflictsArguments" -ErrorAction SilentlyContinue) {
    $argumentSplit = Split-UEToolSuiteGitConflictsArguments -ArgsList $argsList
    $skipEditor = [bool]$argumentSplit.SkipEditor
    $argsList = @($argumentSplit.Args)
  }

  switch ($command) {
    "help" {
      Write-UEToolSuiteGitConflictsHelp
      return
    }
    "sync" {
      [void](Sync-BinaryConflictLock)
      if ($verboseMode) { Show-ConflictStatus -VerboseMode } else { Show-ConflictSummary }
      return
    }
    "status" {
      if ($verboseMode) { Show-ConflictStatus -VerboseMode } else { Show-ConflictStatus }
      return
    }
    "continue" {
      Continue-RebaseWithGuard -SkipEditor:$skipEditor
      return
    }
    "abort" {
      Abort-ConflictOperation
      return
    }
    "restart" {
      Restart-ConflictOperation
      return
    }
    "ours" {
      $patterns = @($argsList | Where-Object { $_ -and $_.Trim() -ne "" })
      if ($patterns.Count -lt 1) {
        Write-UEToolSuiteGitConflictsHelp
        return
      }

      Resolve-BinaryConflicts -Side "ours" -Patterns $patterns -VerboseMode:$verboseMode
      return
    }
    "theirs" {
      $patterns = @($argsList | Where-Object { $_ -and $_.Trim() -ne "" })
      if ($patterns.Count -lt 1) {
        Write-UEToolSuiteGitConflictsHelp
        return
      }

      Resolve-BinaryConflicts -Side "theirs" -Patterns $patterns -VerboseMode:$verboseMode
      return
    }
    default {
      throw "Unknown ue-tools git command '$command'. Run 'ue-tools help git'."
    }
  }
}

Export-ModuleMember -Function `
  Get-UEToolSuiteGitConflictsHelpLines, `
  Write-UEToolSuiteGitConflictsHelp, `
  Split-UEToolSuiteGitConflictsArguments, `
  Enable-UEToolSuiteGitHooks, `
  Get-UEToolSuiteGitDir, `
  Get-UEToolSuiteGitPath, `
  Test-UEToolSuiteGitPathExists, `
  Read-UEToolSuiteGitFile, `
  Get-UEToolSuiteGitContext, `
  Test-UEToolSuiteGitRebaseStateDirsPresent, `
  Get-UEToolSuiteGitLedgerPaths, `
  Get-UEToolSuiteGitMTimeEpoch, `
  Get-UEToolSuiteGitOperationStamp, `
  Get-UEToolSuiteGitMergeHeadSha, `
  Get-UEToolSuiteGitRebasePatchSha, `
  Get-UEToolSuiteGitRebasePatchPaths, `
  Get-UEToolSuiteGitRebaseSeqCurrentSha, `
  Get-UEToolSuiteGitRebaseHeadSha, `
  Get-UEToolSuiteGitRebaseOntoSha, `
  Get-UEToolSuiteGitOtherSideSha, `
  Get-UEToolSuiteGitNormalizedUniquePaths, `
  Get-UEToolSuiteGitPathIntersection, `
  Get-UEToolSuiteGitMergeOverlapCandidates, `
  Get-UEToolSuiteGitRebaseOverlapCandidates, `
  Get-UEToolSuiteGitRequiredGuardedPaths, `
  Get-UEToolSuiteGitApprovedPathsFromLedger, `
  Get-UEToolSuiteGitRemainingRequiredPaths, `
  Get-UEToolSuiteGitOperationContextId, `
  Get-UEToolSuiteGitContextLedgerTransition, `
  Import-UEToolSuiteGitConflictHelpers, `
  Invoke-UEToolSuiteGitCommand

# -----------------------------------------------------------------------------
# Migrated runtime implementation (Git conflict helpers)
# Source previously lived in: payload/Scripts/UETools/UEToolSuite.Git.psm1
# -----------------------------------------------------------------------------
if (-not $script:RunMemo) {
  $script:RunMemo = @{}
}

function Test-GuardPerfEnabled {
  $v = "$($env:UE_GUARD_PROFILE)".Trim().ToLowerInvariant()
  return ($v -eq "1" -or $v -eq "true" -or $v -eq "yes" -or $v -eq "on")
}

function Write-GuardPerf {
  param([Parameter(Mandatory)][string]$Message)
  if (-not (Test-GuardPerfEnabled)) { return }
  Write-Host "[conflicts][perf] $Message" -ForegroundColor DarkGray
}

function Clear-GuardMemo {
  param([string[]]$Keys)

  if (-not $script:RunMemo) { return }
  if (-not $Keys -or $Keys.Count -eq 0) {
    $script:RunMemo.Clear()
    return
  }

  foreach ($k in $Keys) {
    if ($k) { [void]$script:RunMemo.Remove($k) }
  }
}

# -----------------------------
# Repo / context / ledgers
# -----------------------------
function Get-GitDir {
  if ($script:RunMemo.ContainsKey("gitDir")) {
    return $script:RunMemo["gitDir"]
  }

  $resolved = Get-UEToolSuiteGitDir
  $script:RunMemo["gitDir"] = $resolved
  return $resolved
}

function Get-GitPath {
  param([Parameter(Mandatory)][string]$Path)
  $memoKey = "gitPath:$Path"
  if ($script:RunMemo.ContainsKey($memoKey)) {
    return $script:RunMemo[$memoKey]
  }

  $resolved = Get-UEToolSuiteGitPath -Path $Path
  $script:RunMemo[$memoKey] = $resolved
  return $resolved
}

function Test-GitPathExists {
  param([Parameter(Mandatory)][string]$Path)
  return (Test-UEToolSuiteGitPathExists -Path $Path)
}

function Remove-StaleRebaseMarkers {
  # Aggressively clean REBASE_HEAD when rebase directories are gone
  # REBASE_HEAD is unreliable - Git leaves it behind after rebase completes

  # Only keep REBASE_HEAD if directories exist
  $rbm = Test-GitPathExists -Path "rebase-merge"
  $rba = Test-GitPathExists -Path "rebase-apply"

  if ($rbm -or $rba) {
    Write-Verbose "Rebase directories exist, keeping REBASE_HEAD"
    return
  }

  # No directories - aggressively clean REBASE_HEAD
  $rebaseHead = Get-GitPath -Path "REBASE_HEAD"
  if ($rebaseHead -and (Test-Path $rebaseHead)) {
    Write-Verbose "Cleaning stale REBASE_HEAD (no rebase directories)"
    Remove-Item -Force -LiteralPath $rebaseHead -ErrorAction SilentlyContinue
  }
}

function Get-GitContext {
  if ($script:RunMemo.ContainsKey("ctx")) {
    return $script:RunMemo["ctx"]
  }

  $resolved = Get-UEToolSuiteGitContext
  $script:RunMemo["ctx"] = $resolved
  return $resolved
}

function Test-RebaseStateDirsPresent {
  return (Test-UEToolSuiteGitRebaseStateDirsPresent)
}

# Back-compat (some of your functions referenced Get-Context)
function Get-Context { Get-GitContext }

function Get-LedgerPaths {
  return (Get-UEToolSuiteGitLedgerPaths)
}

function Read-GitFile {
  param([Parameter(Mandatory)][string]$Path)
  return (Read-UEToolSuiteGitFile -Path $Path)
}

function Write-Audit {
  param(
    [Parameter(Mandatory)][string]$Action,
    [Parameter(Mandatory)][string]$Message
  )
  $p = Get-LedgerPaths
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $user = $env:USERNAME
  $ctx = Get-GitContext
  try {
    Add-Content -LiteralPath $p.Audit -Value "[$ts] [$ctx] [$user] [$Action] $Message" -Encoding UTF8
  }
  catch {
    # Never break resolving due to audit issues
  }
}

# -----------------------------
# Guarded-binary detection
# -----------------------------
function Normalize-RepoPath {
  param([Parameter(Mandatory)][string]$Path)

  $p = "$Path"
  if ($null -eq $p) { return $null }
  $p = $p.Trim()
  if (-not $p) { return $null }
  $p = $p -replace '^[.][\\/]', ''
  $p = $p -replace '\\', '/'
  $p
}

if (-not $script:GuardedAttrCache) {
  $script:GuardedAttrCache = New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([System.StringComparer]::OrdinalIgnoreCase)
}

function Get-GuardedAttrMapForPaths {
  param(
    [AllowEmptyCollection()]
    [string[]]$Paths = @()
  )

  $result = @{}
  $normalized = @(
    $Paths |
    ForEach-Object { if ($_ -ne $null) { Normalize-RepoPath $_ } } |
    Where-Object { $_ } |
    Sort-Object -Unique
  )

  if (-not $normalized -or $normalized.Count -eq 0) { return $result }

  $toQuery = New-Object System.Collections.Generic.List[string]
  foreach ($p in $normalized) {
    if ($script:GuardedAttrCache.ContainsKey($p)) {
      $result[$p] = $script:GuardedAttrCache[$p]
    }
    else {
      $toQuery.Add($p) | Out-Null
    }
  }

  if ($toQuery.Count -gt 0) {
    $chunkSize = 200
    for ($i = 0; $i -lt $toQuery.Count; $i += $chunkSize) {
      $end = [Math]::Min($i + $chunkSize - 1, $toQuery.Count - 1)
      $chunk = @($toQuery[$i..$end])

      $raw = @(
        & git check-attr --cached merge text -- @chunk 2>$null |
        ForEach-Object { "$_".Trim() } |
        Where-Object { $_ }
      )

      $state = @{}
      foreach ($line in $raw) {
        if ($line -match '^(.*):\s+(merge|text):\s+(.*)$') {
          $path = Normalize-RepoPath $Matches[1]
          $attr = $Matches[2]
          $val = $Matches[3].Trim()
          if (-not $path) { continue }
          if (-not $state.ContainsKey($path)) {
            $state[$path] = @{ merge = $null; text = $null }
          }
          $state[$path][$attr] = $val
        }
      }

      foreach ($p in $chunk) {
        $isGuarded = $false
        if ($state.ContainsKey($p)) {
          $m = $state[$p]["merge"]
          $t = $state[$p]["text"]
          $isGuarded = ($m -eq "binary" -and $t -eq "unset")
        }
        $script:GuardedAttrCache[$p] = $isGuarded
        $result[$p] = $isGuarded
      }
    }
  }

  return $result
}

function Get-GuardedPathsFromList {
  param(
    [AllowEmptyCollection()]
    [string[]]$Paths = @()
  )

  $map = Get-GuardedAttrMapForPaths -Paths $Paths
  if (-not $map.Keys -or $map.Keys.Count -eq 0) { return @() }

  @(
    $map.Keys |
    Where-Object { $map[$_] } |
    Sort-Object -Unique
  )
}

function Test-IsGuardedLfsBinary {
  param([Parameter(Mandatory)][string]$Path)

  $p = Normalize-RepoPath $Path
  if (-not $p) { return $false }

  $map = Get-GuardedAttrMapForPaths -Paths @($p)
  if (-not $map.ContainsKey($p)) { return $false }
  [bool]$map[$p]
}

# -----------------------------
# Conflict discovery
# -----------------------------
function Get-ConflictedPaths {
  if ($script:RunMemo.ContainsKey("conflicted")) {
    return @($script:RunMemo["conflicted"])
  }

  $out = @(
    git diff --name-only --diff-filter=U 2>$null |
    Where-Object { $_ -and $_.Trim() -ne "" } |
    ForEach-Object { $_.Trim() }
  )

  $script:RunMemo["conflicted"] = @($out)
  return @($out)
}

function Get-UnmergedPaths {
  if ($script:RunMemo.ContainsKey("unmerged")) {
    return @($script:RunMemo["unmerged"])
  }

  # Robust parse of `git ls-files -u` (path is after tab)
  $raw = git ls-files -u 2>$null
  if (-not $raw) {
    $script:RunMemo["unmerged"] = @()
    return @()
  }

  $paths = New-Object System.Collections.Generic.List[string]
  foreach ($line in ($raw -split "`r?`n")) {
    if (-not $line) { continue }
    $tab = $line.IndexOf("`t")
    if ($tab -lt 0) { continue }
    $p = $line.Substring($tab + 1).Trim()
    if ($p) { $paths.Add($p) | Out-Null }
  }

  $out = @($paths | Sort-Object -Unique)
  $script:RunMemo["unmerged"] = @($out)
  return @($out)
}

# -----------------------------
# Merge/Rebase operation refs
# -----------------------------
function Get-MergeHeadSha {
  return (Get-UEToolSuiteGitMergeHeadSha)
}

function Get-RebasePatchSha {
  return (Get-UEToolSuiteGitRebasePatchSha)
}

function Get-RebasePatchPaths {
  return @(Get-UEToolSuiteGitRebasePatchPaths)
}

function Get-RebaseSeqCurrentSha {
  return (Get-UEToolSuiteGitRebaseSeqCurrentSha)
}

function Get-RebaseHeadSha {
  if ($script:RunMemo.ContainsKey("rebaseHead")) {
    return $script:RunMemo["rebaseHead"]
  }

  $resolved = Get-UEToolSuiteGitRebaseHeadSha
  $script:RunMemo["rebaseHead"] = $resolved
  return $resolved
}

function Get-RebaseOntoSha {
  if ($script:RunMemo.ContainsKey("rebaseOnto")) {
    return $script:RunMemo["rebaseOnto"]
  }

  $resolved = Get-UEToolSuiteGitRebaseOntoSha
  $script:RunMemo["rebaseOnto"] = $resolved
  return $resolved
}

function Get-OtherSideSha {
  return (Get-UEToolSuiteGitOtherSideSha -Context (Get-GitContext))
}

function Get-MTimeEpoch {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-UEToolSuiteGitMTimeEpoch -Path $Path)
}

function Get-OperationStamp {
  return (Get-UEToolSuiteGitOperationStamp -Context (Get-GitContext))
}

# -----------------------------
# Context-bound ledger (prevents stale approvals)
# -----------------------------
function Get-OperationContextId {
  if ($script:RunMemo.ContainsKey("ctxId")) {
    return $script:RunMemo["ctxId"]
  }

  $ctx = Get-GitContext
  if ($ctx -eq "none") {
    $script:RunMemo["ctxId"] = $null
    return $null
  }

  $stamp = Get-OperationStamp
  if (-not $stamp) { $stamp = "nostamp" }
  $other = $null
  $base = $null
  $onto = $null
  $current = $null

  if ($ctx -eq "merge") {
    $other = Get-MergeHeadSha
    if ($other) {
      $base = (git merge-base HEAD $other 2>$null)
      if ($base) { $base = $base.Trim() }
    }
  }
  elseif ($ctx -eq "rebase") {
    $onto = Get-RebaseOntoSha
    $current = Get-RebaseHeadSha

    if (-not $current) {
      $origPath = Get-GitPath -Path "rebase-merge/orig-head"
      if (-not $origPath) {
        $origPath = Get-GitPath -Path "rebase-apply/orig-head"
      }
      if ($origPath -and (Test-Path -LiteralPath $origPath -PathType Leaf)) {
        $current = Get-Content -LiteralPath $origPath -Raw -ErrorAction SilentlyContinue
        if ($current) { $current = $current.Trim() }
      }
    }
  }
  else {
    $other = Get-OtherSideSha
    if ($other) {
      $base = (git merge-base HEAD $other 2>$null)
      if ($base) { $base = $base.Trim() }
    }
  }

  $id = Get-UEToolSuiteGitOperationContextId `
    -Context $ctx `
    -Stamp $stamp `
    -OtherSideSha $other `
    -MergeBaseSha $base `
    -RebaseOntoSha $onto `
    -RebaseHeadSha $current

  $script:RunMemo["ctxId"] = $id
  return $id
}

function Ensure-ContextBoundLedgers {
  $p = Get-LedgerPaths
  $ctx = Get-GitContext
  $id = Get-OperationContextId
  $prev = Read-GitFile $p.Context
  $transition = Get-UEToolSuiteGitContextLedgerTransition -Context $ctx -CurrentContextId $id -PreviousContextId $prev

  if ($transition.Action -eq "clear") {
    if (Test-Path -LiteralPath $p.Context) { Remove-Item -Force -LiteralPath $p.Context -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $p.Resolved) { Remove-Item -Force -LiteralPath $p.Resolved -ErrorAction SilentlyContinue }
    Clear-GuardMemo -Keys @("approved", "required", "remaining", "unmerged", "conflicted", "overlap", "guardedOverlap", "ctxId", "rebaseHead", "rebaseOnto")
    return
  }

  if ($transition.Action -eq "noop") {
    return
  }

  Set-Content -LiteralPath $p.Context -Value $transition.ContextId -Encoding UTF8
  if (Test-Path -LiteralPath $p.Resolved) { Remove-Item -Force -LiteralPath $p.Resolved -ErrorAction SilentlyContinue }
  Clear-GuardMemo -Keys @("approved", "required", "remaining", "unmerged", "conflicted", "overlap", "guardedOverlap", "ctxId", "rebaseHead", "rebaseOnto")
  if ($transition.AuditMessage) {
    Write-Audit -Action "CTXRESET" -Message $transition.AuditMessage
  }
}

# -----------------------------
# Overlap candidates (covers 'git add .' cases where conflicts disappear)
# -----------------------------

function Get-PathsChangedInCommit {
  param([Parameter(Mandatory)][string]$Commit)

  @(
    (git diff-tree --no-commit-id --name-only -r $Commit 2>$null) -split "`r?`n" |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ }
  ) | Sort-Object -Unique
}
function Get-OverlapCandidates {
  if ($script:RunMemo.ContainsKey("overlap")) {
    return @($script:RunMemo["overlap"])
  }

  $ctx = Get-GitContext
  if ($ctx -eq "none") {
    $script:RunMemo["overlap"] = @()
    return @()
  }

  $other = Get-OtherSideSha
  if (-not $other) {
    $script:RunMemo["overlap"] = @()
    return @()
  }

  if ($ctx -eq "merge") {
    $mergedOverlap = @(Get-UEToolSuiteGitMergeOverlapCandidates -OtherSideSha $other)
    $script:RunMemo["overlap"] = @($mergedOverlap)
    return @($mergedOverlap)
  }

  if ($ctx -eq "rebase") {
    $rebaseOverlap = @(Get-UEToolSuiteGitRebaseOverlapCandidates -OtherSideSha $other -RebaseOntoSha (Get-RebaseOntoSha))
    $script:RunMemo["overlap"] = @($rebaseOverlap)
    return @($rebaseOverlap)
  }

  $script:RunMemo["overlap"] = @()
  return @()
}



function Get-GuardedOverlapCandidates {
  if ($script:RunMemo.ContainsKey("guardedOverlap")) {
    return @($script:RunMemo["guardedOverlap"])
  }

  $overlap = @(Get-OverlapCandidates)
  if (-not $overlap -or $overlap.Count -eq 0) {
    $script:RunMemo["guardedOverlap"] = @()
    return @()
  }

  $out = @(Get-GuardedPathsFromList -Paths $overlap)
  $script:RunMemo["guardedOverlap"] = @($out)
  return @($out)
}

# -----------------------------
# REQUIRED guarded set (recomputed each run)
# -----------------------------
function Get-RequiredGuardedPaths {
  if ($script:RunMemo.ContainsKey("required")) {
    return @($script:RunMemo["required"])
  }

  $ctx = Get-GitContext
  if ($ctx -eq "none") {
    $script:RunMemo["required"] = @()
    return @()
  }

  Ensure-ContextBoundLedgers

  $out = @(Get-UEToolSuiteGitRequiredGuardedPaths `
    -UnmergedGuardedPaths @(Get-GuardedPathsFromList -Paths @(Get-UnmergedPaths)) `
    -OverlapGuardedPaths @(Get-GuardedOverlapCandidates))
  $script:RunMemo["required"] = @($out)
  return @($out)
}

function Get-ApprovedGuardedPaths {
  if ($script:RunMemo.ContainsKey("approved")) {
    return @($script:RunMemo["approved"])
  }

  $p = Get-LedgerPaths
  $out = @(Get-UEToolSuiteGitApprovedPathsFromLedger -ResolvedLedgerPath $p.Resolved)
  $script:RunMemo["approved"] = @($out)
  return @($out)
}

function Get-RemainingRequiredGuardedPaths {
  if ($script:RunMemo.ContainsKey("remaining")) {
    return @($script:RunMemo["remaining"])
  }

  $required = Get-RequiredGuardedPaths
  if (-not $required -or $required.Count -eq 0) {
    $script:RunMemo["remaining"] = @()
    return @()
  }

  $approved = Get-ApprovedGuardedPaths
  $out = @(Get-UEToolSuiteGitRemainingRequiredPaths -RequiredPaths $required -ApprovedPaths $approved)
  $script:RunMemo["remaining"] = @($out)
  return @($out)
}

# -----------------------------
# Wildcard resolution
# -----------------------------
function Resolve-WildcardsToTargets {
  param([Parameter(Mandatory)][string[]]$Patterns)

  # Always return an array, never $null
  if ($null -eq $Patterns) { return @() }

  $candidates = @(Get-ConflictedPaths)
  if (-not $candidates -or $candidates.Count -eq 0) {
    # After `git add .` conflicts can vanish; fall back to overlap candidates.
    $candidates = @(Get-GuardedOverlapCandidates)
  }
  if (-not $candidates -or $candidates.Count -eq 0) { return @() }

  # Normalize patterns: drop null/whitespace, normalize slashes, strip leading ./ or .\
  $normPatterns = @(
    foreach ($p in @($Patterns)) {
      if ($null -eq $p) { continue }
      $x = "$p"
      if ($null -eq $x) { continue }
      $x = $x.Trim()
      if (-not $x) { continue }
      $x = $x -replace '^[.][\\/]', ''
      $x = $x -replace '\\', '/'
      if ($x) { $x }
    }
  )
  if (-not $normPatterns -or $normPatterns.Count -eq 0) { return @() }

  $matched = New-Object System.Collections.Generic.List[string]

  foreach ($c in @($candidates)) {
    if ($null -eq $c) { continue }

    $cNorm = "$c"
    if ($null -eq $cNorm) { continue }
    $cNorm = ($cNorm -replace '\\', '/').Trim()
    if (-not $cNorm) { continue }

    foreach ($pat in @($normPatterns)) {
      if ($null -eq $pat) { continue }
      if ($cNorm -like $pat) { $matched.Add($cNorm) | Out-Null; break }
    }
  }

  return @($matched | Sort-Object -Unique)
}



# -----------------------------
# Safety checks
# -----------------------------
function Test-HasConflictMarkers {
  param([Parameter(Mandatory)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) { return $false }

  try {
    # Read a limited amount of bytes (fast, prevents "git froze" moments on big files)
    $max = 1024 * 1024   # 1 MB
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
      $len = [Math]::Min($fs.Length, $max)
      $buf = New-Object byte[] $len
      [void]$fs.Read($buf, 0, $len)
    }
    finally { $fs.Dispose() }

    # Convert to ASCII-ish text for scanning (conflict markers are ASCII)
    $text = [System.Text.Encoding]::ASCII.GetString($buf)

    return ($text -match '<<<<<<<|=======|>>>>>>>')
  }
  catch {
    # If we can't read it, assume safe (don't brick the workflow),
    # but you can flip this to $true if you want ultra-strict behavior.
    return $false
  }
}

function Test-IsLfsPointerFile {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  try {
    $first = Get-Content -LiteralPath $Path -TotalCount 1 -ErrorAction Stop
    return ($first -eq "version https://git-lfs.github.com/spec/v1")
  }
  catch { return $false }
}

# -----------------------------
# Unreal bundle (sidecars)
# -----------------------------
function Get-UnrealBundlePaths {
  param([Parameter(Mandatory)][string[]]$Paths)

  $bundle = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

  foreach ($p in $Paths) {
    if (-not $p) { continue }
    $n = Normalize-RepoPath $p
    if (-not $n) { continue }
    [void]$bundle.Add($n)

    if ($n -match '\.(uasset|umap)$') {
      # Keep behavior aligned with shell helper (${p%.*}) to avoid double-dot sidecars.
      $base = ($n -replace '\.[^./\\]+$', '')
      foreach ($ext in @("uexp", "ubulk", "uptnl")) {
        [void]$bundle.Add("$base.$ext")
      }
    }
  }

  return @($bundle) | Sort-Object
}

# -----------------------------
# Choosing "ours/theirs" + existence checks
# -----------------------------
function Get-CheckoutFlagForHumanSide {
  param([Parameter(Mandatory)][ValidateSet("ours", "theirs")]$Side)

  $ctx = Get-GitContext
  # merge:  ours=>--ours,   theirs=>--theirs
  # rebase: ours=>--theirs, theirs=>--ours  (flip)
  if ($ctx -eq "rebase") {
    return ($Side -eq "ours") ? "--theirs" : "--ours"
  }
  return ($Side -eq "ours") ? "--ours" : "--theirs"
}

function Get-IndexStageForCheckoutFlag {
  param([Parameter(Mandatory)][ValidateSet("--ours", "--theirs")]$Flag)
  return ($Flag -eq "--ours") ? 2 : 3
}

function Test-IndexStageExists {
  param([Parameter(Mandatory)][int]$Stage, [Parameter(Mandatory)][string]$Path)
  & git cat-file -e (":${Stage}:${Path}") 2>$null
  return ($LASTEXITCODE -eq 0)
}

function Get-IndexStagePathsSet {
  param([Parameter(Mandatory)][int]$Stage)

  $set = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  $raw = git ls-files -u 2>$null
  if (-not $raw) { return ,$set }

  foreach ($line in ($raw -split "`r?`n")) {
    if (-not $line) { continue }
    $tab = $line.IndexOf("`t")
    if ($tab -lt 0) { continue }

    $meta = $line.Substring(0, $tab).Trim()
    $path = Normalize-RepoPath ($line.Substring($tab + 1).Trim())
    if (-not $path) { continue }

    $parts = @($meta -split '\s+' | Where-Object { $_ })
    if ($parts.Count -lt 3) { continue }

    $lineStage = 0
    if (-not [int]::TryParse($parts[2], [ref]$lineStage)) { continue }
    if ($lineStage -eq $Stage) { [void]$set.Add($path) }
  }

  return ,$set
}

function Get-CommitRefForHumanSide {
  param([Parameter(Mandatory)][ValidateSet("ours", "theirs")]$Side)

  $ctx = Get-GitContext
  if ($ctx -eq "merge") {
    # Human: ours=HEAD, theirs=MERGE_HEAD
    return ($Side -eq "ours") ? "HEAD" : (Get-MergeHeadSha)
  }

  if ($ctx -eq "rebase") {
    # Human: ours=REBASE_HEAD (commit being applied), theirs=HEAD (onto branch)
    return ($Side -eq "ours") ? (Get-RebaseHeadSha) : "HEAD"
  }

  return $null
}

function Test-PathExistsInRef {
  param([Parameter(Mandatory)][string]$Ref, [Parameter(Mandatory)][string]$Path)
  if (-not $Ref) { return $false }
  & git cat-file -e ("$Ref`:$Path") 2>$null
  return ($LASTEXITCODE -eq 0)
}

function Get-RefExistingPathsSet {
  param(
    [Parameter(Mandatory)][string]$Ref,
    [AllowEmptyCollection()][string[]]$Paths = @()
  )

  $set = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  if (-not $Ref) { return ,$set }

  $normalized = @(
    $Paths |
    ForEach-Object { if ($_ -ne $null) { Normalize-RepoPath $_ } } |
    Where-Object { $_ } |
    Sort-Object -Unique
  )
  if (-not $normalized -or $normalized.Count -eq 0) { return ,$set }

  $raw = @(
    & git ls-tree -r --name-only $Ref -- @normalized 2>$null |
    ForEach-Object { Normalize-RepoPath $_ } |
    Where-Object { $_ }
  )
  foreach ($p in $raw) { [void]$set.Add($p) }
  return ,$set
}

# -----------------------------
# Ledger updates
# -----------------------------
function Update-LedgersAfterResolve {
  param([Parameter(Mandatory)][string[]]$ResolvedPaths)

  $p = Get-LedgerPaths

  $resolved = $ResolvedPaths |
  ForEach-Object { ($_ -replace '\\', '/').Trim() } |
  Where-Object { $_ } |
  Sort-Object -Unique

  if (-not (Test-Path -LiteralPath $p.Resolved)) {
    New-Item -ItemType File -Force -Path $p.Resolved | Out-Null
  }

  $existing = @()
  if (Test-Path -LiteralPath $p.Resolved) {
    $existing = @(
      Get-Content -LiteralPath $p.Resolved -ErrorAction SilentlyContinue |
      ForEach-Object { ($_ -replace '\\', '/').Trim() } |
      Where-Object { $_ }
    )
  }

  $merged = @($existing + $resolved) | Sort-Object -Unique
  Set-Content -LiteralPath $p.Resolved -Value ($merged -join "`n") -Encoding UTF8

  # Index/worktree changed; invalidate derived sets for this invocation.
  Clear-GuardMemo -Keys @("approved", "required", "remaining", "unmerged", "conflicted", "overlap", "guardedOverlap", "ctxId", "rebaseHead", "rebaseOnto")
}

# -----------------------------
# Main resolver
# -----------------------------
function Resolve-BinaryConflicts {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][ValidateSet("ours", "theirs")]$Side,
    [Parameter(Mandatory)][string[]]$Patterns,
    [switch]$VerboseMode
  )

  $ctx = Get-GitContext
  if ($ctx -eq "none") { throw "No merge/rebase in progress." }
  $perfTotal = [System.Diagnostics.Stopwatch]::StartNew()

  Ensure-ContextBoundLedgers
  $perfTargets = [System.Diagnostics.Stopwatch]::StartNew()

  $targets = Resolve-WildcardsToTargets -Patterns $Patterns
  $perfTargets.Stop()
  Write-GuardPerf ("resolve-targets={0}ms matched={1}" -f $perfTargets.ElapsedMilliseconds, @($targets).Count)
  if (-not $targets -or $targets.Count -eq 0) {
    Write-Host "[conflicts] No candidates matched your pattern(s)." -ForegroundColor Yellow
    Write-Host "  Patterns: $($Patterns -join ', ')" -ForegroundColor Yellow

    $cand = Get-GuardedOverlapCandidates
    if ($cand.Count -gt 0) {
      Write-Host "[conflicts] Guarded overlap candidates:" -ForegroundColor Cyan
      $cand | ForEach-Object { Write-Host "  - $_" }
    }
    return
  }

  $perfBundle = [System.Diagnostics.Stopwatch]::StartNew()
  $bundleTargets = Get-UnrealBundlePaths -Paths $targets
  $perfBundle.Stop()
  Write-GuardPerf ("bundle-expand={0}ms bundle={1}" -f $perfBundle.ElapsedMilliseconds, @($bundleTargets).Count)

  # Act only on guarded binaries that are either currently conflicted OR overlap candidates
  $conflictedSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($p in @(Get-ConflictedPaths)) {
    $n = Normalize-RepoPath $p
    if ($n) { [void]$conflictedSet.Add($n) }
  }

  $overlapSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  # Fast path: when true conflicts still exist, overlap computation is not needed.
  # Overlap is only required after conflict stages are gone (e.g. user ran git add .).
  if ($conflictedSet.Count -eq 0) {
    foreach ($p in @(Get-GuardedOverlapCandidates)) {
      $n = Normalize-RepoPath $p
      if ($n) { [void]$overlapSet.Add($n) }
    }
  }

  $guardedMap = Get-GuardedAttrMapForPaths -Paths $bundleTargets
  $filteredTargets = New-Object System.Collections.Generic.List[string]
  foreach ($f in @($bundleTargets)) {
    $n = Normalize-RepoPath $f
    if (-not $n) { continue }
    if (-not $guardedMap.ContainsKey($n) -or -not [bool]$guardedMap[$n]) { continue }
    if ($conflictedSet.Contains($n) -or $overlapSet.Contains($n)) {
      $filteredTargets.Add($n) | Out-Null
    }
  }
  $bundleTargets = @($filteredTargets | Sort-Object -Unique)

  if ($bundleTargets.Count -eq 0) {
    Write-Host "[conflicts] No guarded files to resolve after bundle expansion." -ForegroundColor Yellow
    $perfTotal.Stop()
    Write-GuardPerf ("resolve-total={0}ms (no guarded targets)" -f $perfTotal.ElapsedMilliseconds)
    return
  }

  $flag = Get-CheckoutFlagForHumanSide -Side $Side
  $stage = Get-IndexStageForCheckoutFlag -Flag $flag
  $chosenRef = Get-CommitRefForHumanSide -Side $Side
  if (-not $chosenRef) { throw "Could not determine chosen ref for $Side ($ctx)." }
  $stagePathSet = Get-IndexStagePathsSet -Stage $stage
  $refPathSet = Get-RefExistingPathsSet -Ref $chosenRef -Paths $bundleTargets

  if ($VerboseMode) {
    Write-Host "[conflicts] Context: $ctx  Side: $Side" -ForegroundColor Cyan
    Write-Host "[conflicts] Prefer: git checkout $flag  (fallback: git checkout $chosenRef)" -ForegroundColor DarkGray
    $bundleTargets | ForEach-Object { Write-Host "  - $_" }
  }


  $resolvedNow = New-Object System.Collections.Generic.List[string]

  foreach ($f in $bundleTargets) {
    $used = $false

    # Stage-based (only if stage blob exists)
    if ($stagePathSet.Contains($f)) {
      & git checkout $flag -- $f
      if ($LASTEXITCODE -ne 0) { throw "git checkout $flag failed for $f" }
      & git add -- $f
      if ($LASTEXITCODE -ne 0) { throw "git add failed for $f" }
      $used = $true
    }

    if (-not $used) {
      # Commit-ref fallback (works after 'git add .' when :2/:3 are gone)
      if ($refPathSet.Contains($f)) {
        & git checkout $chosenRef -- $f
        if ($LASTEXITCODE -ne 0) { throw "git checkout $chosenRef failed for $f" }
        & git add -- $f
        if ($LASTEXITCODE -ne 0) { throw "git add failed for $f" }
      }
      else {
        # Only remove if chosen side truly doesn't contain it.
        & git rm -f --ignore-unmatch -- $f | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "git rm failed for $f" }
      }
    }

    $resolvedNow.Add($f) | Out-Null
  }

  $perfTotal.Stop()
  Write-GuardPerf ("resolve-total={0}ms resolved={1}" -f $perfTotal.ElapsedMilliseconds, $resolvedNow.Count)

  # Safety checks (keep your behavior)
  foreach ($f in $resolvedNow) {
    if (Test-HasConflictMarkers $f) {
      throw "Unsafe: conflict markers detected in $f. Re-run helper and choose a side again."
    }
    if (Test-IsLfsPointerFile $f) {
      throw "Unsafe: $f is an LFS pointer file. Run: git lfs pull; git lfs checkout -- $f; then re-run helper."
    }
  }

  Update-LedgersAfterResolve -ResolvedPaths $resolvedNow.ToArray()
  Write-Audit -Action "RESOLVE" -Message ("{0} patterns=[{1}] files=[{2}]" -f $Side, ($Patterns -join ';'), ($resolvedNow -join ';'))

  $resolvedCount = $resolvedNow.Count
  Write-Host ("[conflicts] {0} {1}: resolved {2} file(s)" -f $ctx, $Side, $resolvedCount) -ForegroundColor Green
  $resolvedNow | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }

  $required = @(Get-RequiredGuardedPaths)
  $remaining = @(Get-RemainingRequiredGuardedPaths)

  if ($remaining.Count -gt 0) {
    Write-Host ("[conflicts] approvals: MISSING ({0}/{1})" -f ($required.Count - $remaining.Count), $required.Count) -ForegroundColor Yellow
    if ($VerboseMode) {
      $remaining | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
  }
  else {
    Write-Host ("[conflicts] approvals: OK ({0}/{1})" -f $required.Count, $required.Count) -ForegroundColor Green
  }

  if ($VerboseMode) {
    Show-ConflictStatus -VerboseMode
  }
}

# -----------------------------
# Status
# -----------------------------
function Show-ConflictStatus {
  param([switch]$VerboseMode)
  Ensure-ContextBoundLedgers
  $ctx = Get-GitContext
  $cid = Get-OperationContextId

  Write-Host "[conflicts] Context: $ctx" -ForegroundColor Cyan
  if ($VerboseMode -and $cid) {
    Write-Host "[conflicts] ContextId: $cid" -ForegroundColor DarkGray
  }

  $unmerged = Get-UnmergedPaths
  Write-Host "[conflicts] Conflicted: $($unmerged.Count)" -ForegroundColor $( if ($unmerged.Count -gt 0) { "Red" } else { "Green" } )
  $unmerged | ForEach-Object { Write-Host "  - $_" }

  $approved = Get-ApprovedGuardedPaths
  Write-Host "[conflicts] Resolved: $($approved.Count)" -ForegroundColor Green
  $approved | ForEach-Object { Write-Host "  - $_" }

  if ($VerboseMode) {
    $required = Get-RequiredGuardedPaths
    if ($required.Count -gt 0) {
      Write-Host "[conflicts] Guarded: $($required.Count)" -ForegroundColor Cyan
      $required | ForEach-Object { Write-Host "  - $_" }
    }
  }

  $remaining = Get-RemainingRequiredGuardedPaths
  if ($remaining.Count -gt 0) {
    Write-Host "[conflicts] Remaining files that require resolution: $($remaining.Count)" -ForegroundColor Yellow
    $remaining | ForEach-Object { Write-Host "  - $_" }
  }
  else {
    Write-Host "[conflicts] All conflicts resolved." -ForegroundColor Green
  }
}


function Show-ConflictSummary {
  Ensure-ContextBoundLedgers

  $ctx = Get-GitContext
  $unmerged = Get-UnmergedPaths
  $required = Get-RequiredGuardedPaths
  $approved = Get-ApprovedGuardedPaths
  $remaining = Get-RemainingRequiredGuardedPaths

  $unmergedCount = @($unmerged).Count
  $requiredCount = @($required).Count
  $approvedCount = @($approved).Count
  $remainingCount = @($remaining).Count

  Write-Host ("[conflicts] Context: {0} | Conflicted: {1} | Guarded: {2} | Resolved: {3} | Remaining: {4}" -f `
      $ctx, $unmergedCount, $requiredCount, $approvedCount, $remainingCount) `
    -ForegroundColor $(if ($remainingCount -gt 0) { "Yellow" } else { "Green" })
}

# -----------------------------
# Abort / Restart
# -----------------------------
function Abort-ConflictOperation {
  $ctx = Get-GitContext
  if ($ctx -eq "merge") {
    Write-Host "[conflicts] Aborting merge..." -ForegroundColor Yellow
    git merge --abort | Out-Host
    Write-Audit -Action "ABORT" -Message "merge"
    return
  }

  if ($ctx -eq "rebase") {
    Write-Host "[conflicts] Aborting rebase..." -ForegroundColor Yellow
    git rebase --abort | Out-Host
    Write-Audit -Action "ABORT" -Message "rebase"
    return
  }

  Write-Host "[conflicts] No merge/rebase in progress." -ForegroundColor Green
}

function Restart-ConflictOperation {
  $gitDir = Get-GitDir
  $ctx = Get-GitContext

  if ($ctx -eq "merge") {
    $mergeHead = Read-GitFile (Join-Path $gitDir "MERGE_HEAD")
    Write-Host "[conflicts] Restarting merge..." -ForegroundColor Yellow
    git merge --abort | Out-Host

    if ($mergeHead) {
      Write-Host "[conflicts] Re-running: git merge $mergeHead" -ForegroundColor Cyan
      git merge $mergeHead | Out-Host
      Write-Audit -Action "RESTART" -Message "merge head=$mergeHead"
    }
    else {
      Write-Host "[conflicts] Could not read MERGE_HEAD; run your merge again manually." -ForegroundColor Red
      Write-Audit -Action "RESTART" -Message "merge failed (no MERGE_HEAD)"
    }
    return
  }

  if ($ctx -eq "rebase") {
    # ... existing rebase restart logic ...
    Write-Host "[conflicts] Restarting rebase..." -ForegroundColor Yellow
    git rebase --abort | Out-Host
    # ... rest stays same ...
  }

  Write-Host "[conflicts] No merge/rebase in progress." -ForegroundColor Green
}

function Continue-RebaseWithGuard {
  param(
    [switch]$SkipEditor
  )

  $ctx = Get-GitContext

  if ($ctx -ne "rebase") {
    Write-Host "[conflicts] No rebase in progress." -ForegroundColor Yellow
    exit 1
  }

  # Enforce guard BEFORE continuing
  $perfGuard = [System.Diagnostics.Stopwatch]::StartNew()
  Ensure-ContextBoundLedgers

  $remaining = @(Get-RemainingRequiredGuardedPaths)
  $perfGuard.Stop()
  Write-GuardPerf ("continue-guard-check={0}ms remaining={1}" -f $perfGuard.ElapsedMilliseconds, $remaining.Count)

  if ($remaining.Count -gt 0) {
    Write-Host "[conflicts] BLOCKED: Guarded binary file(s) require helper approval before continuing." -ForegroundColor Red
    $remaining | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "Resolve these files first using:" -ForegroundColor Cyan
    Write-Host '  git ours   "<pattern>"' -ForegroundColor Gray
    Write-Host '  git theirs "<pattern>"' -ForegroundColor Gray
    Write-Host ""
    Write-Host "Then run: git conflicts continue" -ForegroundColor Cyan
    Write-Audit -Action "CONTINUE_BLOCKED" -Message "rebase continue blocked: $($remaining.Count) files require approval"
    exit 1
  }

  # Guard passed - continue rebase
  Write-Host "[conflicts] Guard passed - continuing rebase..." -ForegroundColor Green
  Write-Audit -Action "CONTINUE" -Message "rebase continue allowed (all guarded files approved)"

  $perfContinue = [System.Diagnostics.Stopwatch]::StartNew()
  if ($SkipEditor) {
    # Non-interactive mode: skip commit message editor
    git -c core.editor=true -c sequence.editor=true rebase --continue | Out-Host
  }
  else {
    # Normal mode: allow commit message editing
    git rebase --continue | Out-Host
  }

  $exitCode = $LASTEXITCODE
  $perfContinue.Stop()
  Write-GuardPerf ("continue-rebase={0}ms exit={1}" -f $perfContinue.ElapsedMilliseconds, $exitCode)

  if ($exitCode -eq 0) {
    Write-Host "[conflicts] Rebase continued successfully." -ForegroundColor Green
  }
  else {
    Write-Host "[conflicts] Rebase continue failed (exit code: $exitCode)." -ForegroundColor Red
  }

  exit $exitCode
}

# -----------------------------
# Back-compat stub
# -----------------------------
function Sync-BinaryConflictLock {
  # Old behavior returned lock contents; now return the required set
  return @(Get-RequiredGuardedPaths)
}

