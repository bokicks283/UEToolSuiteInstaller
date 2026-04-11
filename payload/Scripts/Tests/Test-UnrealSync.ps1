[CmdletBinding()]
param(
  [switch]$NoCleanup,
  [switch]$FailFast,
  [string]$ReturnBranch = "feat/add-hooks"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = (git rev-parse --show-toplevel 2>$null).Trim()
if (-not $repoRoot) { throw "Not inside a git repository." }
Set-Location $repoRoot

$projectContextHelper = Join-Path $repoRoot "Scripts\Unreal\ProjectContext.ps1"
if (-not (Test-Path -LiteralPath $projectContextHelper)) {
  throw "Project context helper not found: $projectContextHelper"
}
. $projectContextHelper
$projectContext = Get-ProjectContext -RepoRoot $repoRoot

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$resultsDir = Join-Path $repoRoot "Scripts\Tests\Test-UnrealSyncResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "UnrealSyncTest-$stamp.log"

$script:PassCount = 0
$script:FailCount = 0
$script:WarnCount = 0
$script:SkipCount = 0
$script:TempBranches = New-Object System.Collections.Generic.List[string]
$script:TempDirs = New-Object System.Collections.Generic.List[string]
$script:CleanupRan = $false

$script:OriginalBranch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
$script:OriginalHead = (git rev-parse HEAD 2>$null).Trim()

function Write-Log {
  param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
    [ConsoleColor]$Color = [ConsoleColor]::Gray
  )
  Write-Host $Message -ForegroundColor $Color
  Add-Content -LiteralPath $logPath -Value $Message -Encoding UTF8
}

function Step([string]$Title) {
  Write-Log ""
  Write-Log "============================================================" DarkGray
  Write-Log $Title DarkGray
  Write-Log "============================================================" DarkGray
}

function Pass([string]$Name, [string]$Detail) {
  $script:PassCount++
  Write-Log "[PASS] $Name - $Detail" Green
}

function Fail([string]$Name, [string]$Detail) {
  $script:FailCount++
  Write-Log "[FAIL] $Name - $Detail" Red
  if ($FailFast) { throw "FAILFAST" }
}

function Warn([string]$Name, [string]$Detail) {
  $script:WarnCount++
  Write-Log "[WARN] $Name - $Detail" Yellow
}

function Skip([string]$Name, [string]$Detail) {
  $script:SkipCount++
  Write-Log "[SKIP] $Name - $Detail" DarkYellow
}

function Get-HeadSha {
  ((git rev-parse HEAD 2>$null) | Select-Object -First 1).Trim()
}

function Write-TextFileLf {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Content
  )

  $normalized = $Content -replace "`r`n", "`n" -replace "`r", "`n"
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

function Invoke-Git {
  param(
    [Parameter(Mandatory)][string[]]$Args,
    [switch]$AllowFail,
    [bool]$SuppressUESync = $true
  )

  $display = "git " + ($Args -join " ")
  Write-Log ">> $display" DarkGray

  $hadSuppress = Test-Path Env:UE_SYNC_SUPPRESS
  $prevSuppress = $null

  if ($SuppressUESync) {
    if ($hadSuppress) { $prevSuppress = $env:UE_SYNC_SUPPRESS }
    $env:UE_SYNC_SUPPRESS = "1"
  }

  try {
    $out = @(& git @Args 2>&1)
    $code = $LASTEXITCODE
  }
  finally {
    if ($SuppressUESync) {
      if ($hadSuppress) {
        $env:UE_SYNC_SUPPRESS = $prevSuppress
      }
      else {
        Remove-Item Env:UE_SYNC_SUPPRESS -ErrorAction SilentlyContinue
      }
    }
  }

  foreach ($line in $out) {
    $text = "$line"
    if (-not [string]::IsNullOrWhiteSpace($text)) {
      Write-Log ("   " + $text.TrimEnd()) DarkGray
    }
  }

  if (-not $AllowFail -and $code -ne 0) {
    throw "Command failed (exit=$code): $display"
  }

  [pscustomobject]@{
    Code = $code
    Output = ($out | ForEach-Object { "$_" }) -join "`n"
  }
}

function Invoke-GitAt {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string[]]$Args,
    [switch]$AllowFail,
    [hashtable]$Environment
  )

  $display = "git " + ($Args -join " ")
  Write-Log ">> [$Path] $display" DarkGray

  $envPrevious = @{}
  if ($Environment) {
    foreach ($key in $Environment.Keys) {
      $envPath = "Env:$key"
      if (Test-Path $envPath) {
        $envPrevious[$key] = (Get-Item -Path $envPath).Value
      }
      else {
        $envPrevious[$key] = $null
      }

      $newValue = $Environment[$key]
      if ($null -eq $newValue -or [string]::IsNullOrWhiteSpace([string]$newValue)) {
        Remove-Item -Path $envPath -ErrorAction SilentlyContinue
      }
      else {
        Set-Item -Path $envPath -Value ([string]$newValue)
      }
    }
  }

  Push-Location $Path
  try {
    $out = @(& git @Args 2>&1)
    $code = $LASTEXITCODE
  }
  finally {
    Pop-Location
    foreach ($key in $envPrevious.Keys) {
      $envPath = "Env:$key"
      if ($null -eq $envPrevious[$key]) {
        Remove-Item -Path $envPath -ErrorAction SilentlyContinue
      }
      else {
        Set-Item -Path $envPath -Value ([string]$envPrevious[$key])
      }
    }
  }

  foreach ($line in $out) {
    $text = "$line"
    if (-not [string]::IsNullOrWhiteSpace($text)) {
      Write-Log ("   " + $text.TrimEnd()) DarkGray
    }
  }

  if (-not $AllowFail -and $code -ne 0) {
    throw "Command failed (exit=$code): [$Path] $display"
  }

  [pscustomobject]@{
    Code = $code
    Output = ($out | ForEach-Object { "$_" }) -join "`n"
  }
}

function Invoke-UnrealSyncCapture {
  param(
    [Parameter(Mandatory)][string[]]$Args,
    [switch]$PowerShellNonInteractive,
    [hashtable]$Environment
  )

  $scriptPath = Join-Path $repoRoot "Scripts\Unreal\UnrealSync.ps1"
  $pwshArgs = @(
    "-NoLogo",
    "-NoProfile"
  )
  if ($PowerShellNonInteractive) {
    $pwshArgs += "-NonInteractive"
  }
  $pwshArgs += @(
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath
  )
  $pwshArgs += $Args

  Write-Log ">> pwsh $($pwshArgs -join ' ')" DarkGray

  $envPrevious = @{}
  if ($Environment) {
    foreach ($key in $Environment.Keys) {
      $envPath = "Env:$key"
      if (Test-Path $envPath) {
        $envPrevious[$key] = (Get-Item -Path $envPath).Value
      }
      else {
        $envPrevious[$key] = $null
      }

      $newValue = $Environment[$key]
      if ($null -eq $newValue -or [string]::IsNullOrWhiteSpace([string]$newValue)) {
        Remove-Item -Path $envPath -ErrorAction SilentlyContinue
      }
      else {
        Set-Item -Path $envPath -Value ([string]$newValue)
      }
    }
  }

  try {
    $out = @(& pwsh @pwshArgs 2>&1)
    $code = $LASTEXITCODE
  }
  finally {
    foreach ($key in $envPrevious.Keys) {
      $envPath = "Env:$key"
      if ($null -eq $envPrevious[$key]) {
        Remove-Item -Path $envPath -ErrorAction SilentlyContinue
      }
      else {
        Set-Item -Path $envPath -Value ([string]$envPrevious[$key])
      }
    }
  }

  foreach ($line in $out) {
    $text = "$line"
    if (-not [string]::IsNullOrWhiteSpace($text)) {
      Write-Log ("   " + $text.TrimEnd()) DarkGray
    }
  }

  [pscustomobject]@{
    Code = $code
    Output = ($out | ForEach-Object { "$_" }) -join "`n"
  }
}

function Assert-CodeZero {
  param([string]$Name, [int]$Code)
  if ($Code -eq 0) { Pass $Name "exit=0"; return }
  Fail $Name "expected exit=0, got exit=$Code"
}

function Assert-OutputEmpty {
  param([string]$Name, [string]$Output)
  if ([string]::IsNullOrWhiteSpace($Output)) { Pass $Name "no output"; return }
  Fail $Name "expected no output, got: $Output"
}

function Assert-OutputContains {
  param(
    [string]$Name,
    [string]$Output,
    [string]$Needle
  )
  if ($Output -like "*$Needle*") { Pass $Name "matched: $Needle"; return }
  Fail $Name "missing expected text: $Needle"
}

function Assert-OutputNotContains {
  param(
    [string]$Name,
    [string]$Output,
    [string]$Needle
  )
  if ($Output -notlike "*$Needle*") { Pass $Name "not present: $Needle"; return }
  Fail $Name "unexpected text present: $Needle"
}

function Assert-Condition {
  param(
    [string]$Name,
    [bool]$Condition,
    [string]$PassDetail = "condition is true",
    [string]$FailDetail = "condition is false"
  )
  if ($Condition) { Pass $Name $PassDetail; return }
  Fail $Name $FailDetail
}

function Restore-RepoState {
  if ($script:CleanupRan) { return }
  $script:CleanupRan = $true

  if ($NoCleanup) {
    Warn "Cleanup" "NoCleanup set; leaving temp branch/data in place."
    return
  }

  Step "Cleanup"

  try {
    if ($script:OriginalBranch -and $script:OriginalBranch -ne "HEAD") {
      Invoke-Git -Args @("checkout", $script:OriginalBranch) -AllowFail | Out-Null
    }
    elseif ($script:OriginalHead) {
      Invoke-Git -Args @("checkout", "--detach", $script:OriginalHead) -AllowFail | Out-Null
    }
  }
  catch {
    Warn "Cleanup checkout" "$($_.Exception.Message)"
  }

  foreach ($b in ($script:TempBranches | Sort-Object -Unique)) {
    try {
      Invoke-Git -Args @("branch", "-D", "--", $b) -AllowFail | Out-Null
    }
    catch {
      Warn "Cleanup branch delete" "$b -> $($_.Exception.Message)"
    }
  }

  foreach ($dir in ($script:TempDirs | Sort-Object -Unique)) {
    try {
      if (Test-Path -LiteralPath $dir) {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
    catch {
      Warn "Cleanup temp dir" "$dir -> $($_.Exception.Message)"
    }
  }

  foreach ($p in @(
      (Join-Path $repoRoot "Intermediate\UE_Sync_LockTest"),
      (Join-Path $repoRoot "Content\Test\UE_Sync_Test")
    )) {
    try {
      if (Test-Path -LiteralPath $p) {
        Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
    catch { }
  }
}

try {
  Step "Unreal Sync Automated Tests ($stamp)"
  Write-Log "Repo: $repoRoot" Cyan
  Write-Log "Log : $logPath" Cyan

  $dirty = @((git status --porcelain 2>$null) | Where-Object { $_ -and $_.Trim() -ne "" })
  if ($dirty.Count -gt 0) {
    throw "Working tree is not clean. Commit/stash changes before running Test-UnrealSync.ps1."
  }

  Step "Prepare isolated test branch"
  $baseSha = Get-HeadSha
  $testBranch = "test/ue-sync-auto-$((Get-Date).ToString('HHmmss'))"
  Invoke-Git -Args @("checkout", "-B", $testBranch, $baseSha) | Out-Null
  $script:TempBranches.Add($testBranch) | Out-Null

  Step "Case 1: Hook non-branch checkout flag skips silently"
  $head0 = Get-HeadSha
  $res = Invoke-UnrealSyncCapture -Args @("-OldRev", $head0, "-NewRev", $head0, "-Flag", "0")
  Assert-CodeZero "UE Sync case 1 exit code" $res.Code
  Assert-OutputEmpty "UE Sync case 1 output" $res.Output

  Step "Case 2: No structural trigger changes are silent"
  $nonStructRel = "Content/Test/UE_Sync_Test/NonStructural.txt"
  $nonStructAbs = Join-Path $repoRoot $nonStructRel
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $nonStructAbs) | Out-Null
  Write-TextFileLf -Path $nonStructAbs -Content "UE sync non-structural $(Get-Date -Format o)`n"
  Invoke-Git -Args @("add", "--", $nonStructRel) | Out-Null
  Invoke-Git -Args @("commit", "-m", "test: ue sync non-structural change") | Out-Null

  $head1 = Get-HeadSha
  $res = Invoke-UnrealSyncCapture -Args @("-OldRev", $head0, "-NewRev", $head1, "-Flag", "1")
  Assert-CodeZero "UE Sync case 2 exit code" $res.Code
  Assert-OutputEmpty "UE Sync case 2 output" $res.Output

  Step "Case 3: Rebase marker causes silent skip"
  $gitDir = (git rev-parse --git-dir 2>$null).Trim()
  if (-not [System.IO.Path]::IsPathRooted($gitDir)) {
    $gitDir = Join-Path $repoRoot $gitDir
  }
  $rebaseMergeDir = Join-Path $gitDir "rebase-merge"

  if (Test-Path -LiteralPath $rebaseMergeDir) {
    Skip "UE Sync case 3 setup" "rebase-merge already exists (operation in progress)."
  }
  else {
    New-Item -ItemType Directory -Force -Path $rebaseMergeDir | Out-Null
    try {
      $res = Invoke-UnrealSyncCapture -Args @("-OldRev", $head0, "-NewRev", $head1, "-Flag", "1")
      Assert-CodeZero "UE Sync case 3 exit code" $res.Code
      Assert-OutputEmpty "UE Sync case 3 output" $res.Output
    }
    finally {
      Remove-Item -LiteralPath $rebaseMergeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  Step "Case 4: Rebase reflog action causes silent skip"
  $previousReflogAction = $env:GIT_REFLOG_ACTION
  try {
    $env:GIT_REFLOG_ACTION = "rebase (pick)"
    $res = Invoke-UnrealSyncCapture -Args @("-OldRev", $head0, "-NewRev", $head1, "-Flag", "1")
    Assert-CodeZero "UE Sync case 4 exit code" $res.Code
    Assert-OutputEmpty "UE Sync case 4 output" $res.Output
  }
  finally {
    if ($null -eq $previousReflogAction) {
      Remove-Item Env:GIT_REFLOG_ACTION -ErrorAction SilentlyContinue
    }
    else {
      $env:GIT_REFLOG_ACTION = $previousReflogAction
    }
  }

  Step "Case 5: Hook suppression contract avoids duplicate UE Sync runs"
  $postCheckoutPath = Join-Path $repoRoot ".githooks\post-checkout"
  $postMergePath = Join-Path $repoRoot ".githooks\post-merge"
  $postCommitPath = Join-Path $repoRoot ".githooks\post-commit"
  $postRewritePath = Join-Path $repoRoot ".githooks\post-rewrite"
  $hookCommonPath = Join-Path $repoRoot "Scripts\git-hooks\hook-common.sh"
  $unrealSyncPath = Join-Path $repoRoot "Scripts\Unreal\UnrealSync.ps1"

  $postCheckoutText = Get-Content -LiteralPath $postCheckoutPath -Raw
  $postMergeText = Get-Content -LiteralPath $postMergePath -Raw
  $postCommitText = Get-Content -LiteralPath $postCommitPath -Raw
  $postRewriteText = Get-Content -LiteralPath $postRewritePath -Raw
  $hookCommonText = Get-Content -LiteralPath $hookCommonPath -Raw
  $unrealSyncText = Get-Content -LiteralPath $unrealSyncPath -Raw

  Assert-Condition `
    -Name "UE Sync case 5 hook-common has UE_SYNC_SUPPRESS gate" `
    -Condition (
      $hookCommonText -match 'case "\$\{UE_SYNC_SUPPRESS:-0\}"' -and
      $hookCommonText -match 'skip UnrealSync: suppressed by UE_SYNC_SUPPRESS'
    ) `
    -FailDetail "hook-common.sh missing UE_SYNC_SUPPRESS guard in hook_run_unrealsync"

  Assert-Condition `
    -Name "UE Sync case 5 hook-common seeds and uses root interactivity context" `
    -Condition (
      $hookCommonText -match 'hook_seed_root_interactivity\(\)' -and
      $hookCommonText -match 'UE_SYNC_ROOT_INTERACTIVE' -and
      $hookCommonText -match 'UE_SYNC_HOOK_HAS_TTY' -and
      $hookCommonText -match 'GIT_TERMINAL_PROMPT' -and
      $hookCommonText -match 'hook_seed_root_interactivity'
    ) `
    -FailDetail "hook-common.sh missing root interactivity seed/usage contract"

  Assert-Condition `
    -Name "UE Sync case 5 post-checkout suppresses nested fetch/pull/stash commands" `
    -Condition (
      $postCheckoutText -match 'UE_SYNC_SUPPRESS=1 git fetch --all --prune --quiet' -and
      $postCheckoutText -match 'UE_SYNC_SUPPRESS=1 git pull --ff-only' -and
      $postCheckoutText -match 'UE_SYNC_SUPPRESS=1 git stash push -u' -and
      $postCheckoutText -match 'UE_SYNC_SUPPRESS=1 git stash pop "\$STASH_REF"'
    ) `
    -FailDetail "post-checkout missing one or more UE_SYNC_SUPPRESS-prefixed nested git commands"

  $runCount = [regex]::Matches($postCheckoutText, 'hook_run_unrealsync\s+"').Count
  Assert-Condition `
    -Name "UE Sync case 5 post-checkout calls hook_run_unrealsync once" `
    -Condition ($runCount -eq 1) `
    -PassDetail "hook_run_unrealsync calls=$runCount" `
    -FailDetail "expected 1 hook_run_unrealsync call in post-checkout, found $runCount"

  Assert-Condition `
    -Name "UE Sync case 5 hook-common uses guarded tty redirection for interactive prompts" `
    -Condition (
      $hookCommonText -match 'UE_SYNC_HOOK_HAS_TTY' -and
      $hookCommonText -match 'hook_can_bind_tty\(\)' -and
      $hookCommonText -match '\[ "\$HAS_HOOK_TTY" -eq 1 \] && hook_can_bind_tty' -and
      $hookCommonText -match '</dev/tty >/dev/tty'
    ) `
    -FailDetail "hook-common missing guarded tty redirection path for interactive UnrealSync prompts"

  Assert-Condition `
    -Name "UE Sync case 5 hooks seed root interactivity before nested git work" `
    -Condition (
      $postCheckoutText -match 'hook_seed_root_interactivity' -and
      $postMergeText -match 'hook_seed_root_interactivity' -and
      $postCommitText -match 'hook_seed_root_interactivity' -and
      $postRewriteText -match 'hook_seed_root_interactivity'
    ) `
    -FailDetail "one or more hooks are missing hook_seed_root_interactivity initialization"

  $seedIndex = $postCheckoutText.IndexOf("hook_seed_root_interactivity")
  $fetchIndex = $postCheckoutText.IndexOf("UE_SYNC_SUPPRESS=1 git fetch --all --prune --quiet")
  Assert-Condition `
    -Name "UE Sync case 5 post-checkout seeds root interactivity before auto-pull" `
    -Condition ($seedIndex -ge 0 -and $fetchIndex -gt $seedIndex) `
    -PassDetail "hook_seed_root_interactivity index=$seedIndex fetch index=$fetchIndex" `
    -FailDetail "post-checkout must seed root interactivity before nested fetch/pull"

  Assert-Condition `
    -Name "UE Sync case 5 post-rewrite only allows rebase" `
    -Condition (
      $postRewriteText -match 'REWRITE_OP="\$\{1:-\}"' -and
      $postRewriteText -match '\[ "\$REWRITE_OP" != "rebase" \]' -and
      $postRewriteText -match 'skip UnrealSync: post-rewrite op=\$REWRITE_OP'
    ) `
    -FailDetail "post-rewrite missing rebase-only guard before UnrealSync invocation"

  Assert-Condition `
    -Name "UE Sync case 5 UnrealSync honors root interactive hook context" `
    -Condition (
      $unrealSyncText -match 'UE_SYNC_ROOT_INTERACTIVE' -and
      $unrealSyncText -match 'UE_SYNC_HOOK_HAS_TTY' -and
      $unrealSyncText -match 'Interactive root command detected but this hook has no terminal access' -and
      $unrealSyncText -match 'Interactive root command detected but no input was received'
    ) `
    -FailDetail "UnrealSync.ps1 missing root-interactive prompt handling contract"

  Step "Case 6: Structural change detection with DryRun"
  $structRel = "Source/$($projectContext.PrimaryModuleName)/UE_Sync_TestTmp_$((Get-Date).ToString('HHmmss')).cpp"
  $structAbs = Join-Path $repoRoot $structRel
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $structAbs) | Out-Null
  $structContent = @(
    '#include "CoreMinimal.h"'
    '// UE sync structural trigger file for automated test'
    ''
  ) -join "`n"
  Write-TextFileLf -Path $structAbs -Content $structContent

  Invoke-Git -Args @("add", "--", $structRel) | Out-Null
  Invoke-Git -Args @("commit", "-m", "test: ue sync structural change") | Out-Null

  $head2 = Get-HeadSha
  $res = Invoke-UnrealSyncCapture -Args @(
    "-OldRev", $head1,
    "-NewRev", $head2,
    "-Flag", "1",
    "-NonInteractive",
    "-DryRun"
  )

  Assert-CodeZero "UE Sync case 6 exit code" $res.Code
  Assert-OutputContains "UE Sync case 6 detects UE sync action plan" $res.Output "UE Sync action plan:"
  Assert-OutputContains "UE Sync case 6 non-interactive path" $res.Output "Non-interactive execution detected; proceeding without confirmation."
  Assert-OutputContains "UE Sync case 6 dry-run path" $res.Output "DryRun enabled. Skipping cleanup/regeneration/build."

  Step "Case 7: Root interactive context with no hook tty skips safely before prompt"
  $res = Invoke-UnrealSyncCapture -PowerShellNonInteractive -Environment @{ UE_SYNC_ROOT_INTERACTIVE = "1"; UE_SYNC_HOOK_HAS_TTY = "0" } -Args @(
    "-OldRev", $head1,
    "-NewRev", $head2,
    "-Flag", "1",
    "-DryRun"
  )

  Assert-CodeZero "UE Sync case 7 exit code" $res.Code
  Assert-OutputContains "UE Sync case 7 detects UE sync action plan" $res.Output "UE Sync action plan:"
  Assert-OutputContains "UE Sync case 7 no-tty safe skip path" $res.Output "Interactive root command detected but this hook has no terminal access. Skipping UE Sync to avoid an unconfirmed rebuild."
  Assert-OutputNotContains "UE Sync case 7 does not emit explicit user-decline message" $res.Output "User chose not to proceed. Exiting."
  Assert-OutputNotContains "UE Sync case 7 does not force non-interactive path" $res.Output "Non-interactive execution detected; proceeding without confirmation."
  Assert-OutputNotContains "UE Sync case 7 does not run dry-run rebuild path" $res.Output "DryRun enabled. Skipping cleanup/regeneration/build."

  Step "Case 8: Root interactive with hook tty in detached host never auto-declines"
  $res = Invoke-UnrealSyncCapture -PowerShellNonInteractive -Environment @{ UE_SYNC_ROOT_INTERACTIVE = "1"; UE_SYNC_HOOK_HAS_TTY = "1" } -Args @(
    "-OldRev", $head1,
    "-NewRev", $head2,
    "-Flag", "1",
    "-DryRun"
  )

  Assert-CodeZero "UE Sync case 8 exit code" $res.Code
  Assert-OutputContains "UE Sync case 8 detects UE sync action plan" $res.Output "UE Sync action plan:"
  Assert-OutputNotContains "UE Sync case 8 does not emit explicit user-decline message" $res.Output "User chose not to proceed. Exiting."
  Assert-OutputNotContains "UE Sync case 8 does not force non-interactive path" $res.Output "Non-interactive execution detected; proceeding without confirmation."
  Assert-Condition `
    -Name "UE Sync case 8 safe skip reason is explicit" `
    -Condition (
      $res.Output -like "*Interactive root command detected but prompt could not be shown*" -or
      $res.Output -like "*Interactive root command detected but no input was received*"
    ) `
    -FailDetail "case 8 expected a safe-skip prompt warning when interactive input is unavailable"
  Assert-OutputNotContains "UE Sync case 8 does not run dry-run rebuild path" $res.Output "DryRun enabled. Skipping cleanup/regeneration/build."

  Step "Case 9: Root non-interactive context keeps detached host non-interactive"
  $res = Invoke-UnrealSyncCapture -PowerShellNonInteractive -Environment @{ UE_SYNC_ROOT_INTERACTIVE = "0"; UE_SYNC_HOOK_HAS_TTY = "0" } -Args @(
    "-OldRev", $head1,
    "-NewRev", $head2,
    "-Flag", "1",
    "-DryRun"
  )

  Assert-CodeZero "UE Sync case 9 exit code" $res.Code
  Assert-OutputContains "UE Sync case 9 non-interactive path" $res.Output "Non-interactive execution detected; proceeding without confirmation."
  Assert-OutputContains "UE Sync case 9 dry-run path" $res.Output "DryRun enabled. Skipping cleanup/regeneration/build."

  Step "Case 10: Explicit -NonInteractive override wins over root interactive context"
  $res = Invoke-UnrealSyncCapture -PowerShellNonInteractive -Environment @{ UE_SYNC_ROOT_INTERACTIVE = "1"; UE_SYNC_HOOK_HAS_TTY = "1" } -Args @(
    "-OldRev", $head1,
    "-NewRev", $head2,
    "-Flag", "1",
    "-NonInteractive",
    "-DryRun"
  )

  Assert-CodeZero "UE Sync case 10 exit code" $res.Code
  Assert-OutputContains "UE Sync case 10 non-interactive path" $res.Output "Non-interactive execution detected; proceeding without confirmation."
  Assert-OutputContains "UE Sync case 10 dry-run path" $res.Output "DryRun enabled. Skipping cleanup/regeneration/build."

  Step "Case 11: Locked file in cleanup is handled gracefully (non-interactive)"
  $lockDir = Join-Path $repoRoot "Intermediate\UE_Sync_LockTest"
  $lockPath = Join-Path $lockDir "Locked.txt"
  New-Item -ItemType Directory -Force -Path $lockDir | Out-Null
  Set-Content -LiteralPath $lockPath -Encoding UTF8 -Value "locked $(Get-Date -Format o)"

  $fs = $null
  try {
    $fs = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    $res = Invoke-UnrealSyncCapture -Args @(
      "-Force",
      "-CleanGenerated",
      "-NoRegen",
      "-NoBuild",
      "-NonInteractive"
    )
    Assert-CodeZero "UE Sync case 11 exit code" $res.Code
    Assert-OutputContains "UE Sync case 11 lock warning" $res.Output "Could not clean 'Intermediate' because a file is in use."
  }
  finally {
    if ($fs) { $fs.Dispose() }
    if (Test-Path -LiteralPath $lockDir) {
      Remove-Item -LiteralPath $lockDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  Step "Case 12: post-checkout auto-pull on main preserves interactive UE Sync mode"
  $autoPullRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ue-sync-autopull-" + [Guid]::NewGuid().ToString("N"))
  $script:TempDirs.Add($autoPullRoot) | Out-Null

  $remoteRepo = Join-Path $autoPullRoot "remote.git"
  $workRepo = Join-Path $autoPullRoot "work"
  $updaterRepo = Join-Path $autoPullRoot "updater"
  $shimBin = Join-Path $autoPullRoot "bin"

  New-Item -ItemType Directory -Force -Path $autoPullRoot | Out-Null
  New-Item -ItemType Directory -Force -Path $shimBin | Out-Null

  # Git LFS shim to keep hook execution deterministic in temp repos.
  Write-TextFileLf -Path (Join-Path $shimBin "git-lfs") -Content @'
#!/bin/sh
exit 0
'@
  Write-TextFileLf -Path (Join-Path $shimBin "git-lfs.cmd") -Content @'
@echo off
exit /b 0
'@

  $hookEnv = @{
    PATH = "$shimBin;$env:PATH"
    UE_SYNC_ROOT_INTERACTIVE = "1"
    UE_SYNC_FORCE_INTERACTIVE = "1"
  }

  Invoke-GitAt -Path $autoPullRoot -Args @("init", "--bare", $remoteRepo) | Out-Null
  Invoke-GitAt -Path $autoPullRoot -Args @("clone", $remoteRepo, $workRepo) | Out-Null

  Invoke-GitAt -Path $workRepo -Args @("config", "user.name", "UE Sync Test") | Out-Null
  Invoke-GitAt -Path $workRepo -Args @("config", "user.email", "ue-sync-test@example.com") | Out-Null
  Invoke-GitAt -Path $workRepo -Args @("checkout", "-B", "main") | Out-Null

  $seedFile = Join-Path $workRepo "README.md"
  Write-TextFileLf -Path $seedFile -Content "seed`n"
  Invoke-GitAt -Path $workRepo -Args @("add", "--", "README.md") | Out-Null
  Invoke-GitAt -Path $workRepo -Args @("commit", "-m", "seed main") | Out-Null
  Invoke-GitAt -Path $workRepo -Args @("push", "-u", "origin", "main") | Out-Null
  Invoke-GitAt -Path $workRepo -Args @("checkout", "-B", "feature/local-work") | Out-Null

  # Install just enough hook assets for post-checkout + hook-common execution.
  New-Item -ItemType Directory -Force -Path (Join-Path $workRepo ".githooks") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $workRepo "Scripts\git-hooks") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $workRepo "Scripts\Unreal") | Out-Null
  Copy-Item -LiteralPath (Join-Path $repoRoot ".githooks\post-checkout") -Destination (Join-Path $workRepo ".githooks\post-checkout") -Force
  Copy-Item -LiteralPath (Join-Path $repoRoot "Scripts\git-hooks\hook-common.sh") -Destination (Join-Path $workRepo "Scripts\git-hooks\hook-common.sh") -Force
  Copy-Item -LiteralPath (Join-Path $repoRoot "Scripts\git-hooks\colors.sh") -Destination (Join-Path $workRepo "Scripts\git-hooks\colors.sh") -Force

  # Lightweight UnrealSync shim: capture invocation mode instead of rebuilding UE.
  Write-TextFileLf -Path (Join-Path $workRepo "Scripts\Unreal\UnrealSync.ps1") -Content @'
[CmdletBinding()]
param(
  [string]$OldRev,
  [string]$NewRev,
  [int]$Flag = 1,
  [switch]$NonInteractive
)

$logPath = Join-Path (Get-Location).Path "ue-sync-hook-log.txt"
$line = "OldRev=$OldRev;NewRev=$NewRev;Flag=$Flag;NonInteractive=$($NonInteractive.IsPresent);Root=$env:UE_SYNC_ROOT_INTERACTIVE;HookTTY=$env:UE_SYNC_HOOK_HAS_TTY"
Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
exit 0
'@

  Invoke-GitAt -Path $workRepo -Args @("config", "core.hooksPath", ".githooks") | Out-Null

  Invoke-GitAt -Path $autoPullRoot -Args @("clone", $remoteRepo, $updaterRepo) | Out-Null
  Invoke-GitAt -Path $updaterRepo -Args @("config", "user.name", "UE Sync Updater") | Out-Null
  Invoke-GitAt -Path $updaterRepo -Args @("config", "user.email", "ue-sync-updater@example.com") | Out-Null
  Invoke-GitAt -Path $updaterRepo -Args @("checkout", "main") | Out-Null
  $updateFile = Join-Path $updaterRepo "README.md"
  Write-TextFileLf -Path $updateFile -Content "seed`nupstream-change`n"
  Invoke-GitAt -Path $updaterRepo -Args @("add", "--", "README.md") | Out-Null
  Invoke-GitAt -Path $updaterRepo -Args @("commit", "-m", "upstream update") | Out-Null
  Invoke-GitAt -Path $updaterRepo -Args @("push", "origin", "main") | Out-Null

  $checkoutResult = Invoke-GitAt -Path $workRepo -Environment $hookEnv -Args @("checkout", "main")
  Assert-CodeZero "UE Sync case 12 checkout to main exit code" $checkoutResult.Code
  Assert-OutputContains "UE Sync case 12 auto-pull ran" $checkoutResult.Output "Pulled latest changes into main."

  $hookLog = Join-Path $workRepo "ue-sync-hook-log.txt"
  Assert-Condition `
    -Name "UE Sync case 12 hook log created" `
    -Condition (Test-Path -LiteralPath $hookLog) `
    -FailDetail "post-checkout did not invoke UnrealSync shim"

  $hookLines = @()
  if (Test-Path -LiteralPath $hookLog) {
    $hookLines = @(Get-Content -LiteralPath $hookLog | Where-Object { $_ -and $_.Trim() -ne "" })
  }
  Assert-Condition `
    -Name "UE Sync case 12 UnrealSync called once after auto-pull" `
    -Condition ($hookLines.Count -eq 1) `
    -PassDetail "log lines=$($hookLines.Count)" `
    -FailDetail "expected 1 UnrealSync invocation, got $($hookLines.Count)"

  if ($hookLines.Count -gt 0) {
    $line = $hookLines[0]
    Assert-OutputContains "UE Sync case 12 preserves interactive mode" $line "NonInteractive=False"
    Assert-OutputContains "UE Sync case 12 root interactivity propagated" $line "Root=1"
  }

  $workHead = (Invoke-GitAt -Path $workRepo -Args @("rev-parse", "HEAD")).Output.Trim()
  $updaterHead = (Invoke-GitAt -Path $updaterRepo -Args @("rev-parse", "HEAD")).Output.Trim()
  Assert-Condition `
    -Name "UE Sync case 12 local main pulled upstream commit" `
    -Condition ($workHead -eq $updaterHead) `
    -PassDetail "work main head matches upstream head" `
    -FailDetail "work main head does not match upstream head after auto-pull"

  Step "Summary"
  Write-Log ("PASS={0} FAIL={1} WARN={2} SKIP={3}" -f $script:PassCount, $script:FailCount, $script:WarnCount, $script:SkipCount) Cyan
  if ($script:FailCount -eq 0) {
    Write-Log "Unreal Sync automated tests passed." Green
  }
  else {
    Write-Log "Unreal Sync automated tests failed." Red
    exit 1
  }
}
catch {
  if ($_.Exception.Message -ne "FAILFAST") {
    Write-Log "[FATAL] $($_.Exception.Message)" Red
  }
  Write-Log ("PASS={0} FAIL={1} WARN={2} SKIP={3}" -f $script:PassCount, $script:FailCount, $script:WarnCount, $script:SkipCount) Cyan
  if ($script:FailCount -eq 0) { $script:FailCount = 1 }
  exit 1
}
finally {
  Restore-RepoState
  Write-Log ""
  Write-Log "Log saved: $logPath" Cyan
}
