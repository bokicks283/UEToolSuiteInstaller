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

Export-ModuleMember -Function `
  Get-UEToolSuiteGitConflictsHelpLines, `
  Write-UEToolSuiteGitConflictsHelp, `
  Split-UEToolSuiteGitConflictsArguments, `
  Enable-UEToolSuiteGitHooks
