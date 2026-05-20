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
  Get-UEToolSuiteGitContextLedgerTransition
