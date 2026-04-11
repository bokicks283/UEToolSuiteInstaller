[CmdletBinding()]
param(
  [switch]$FailFast
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = (git rev-parse --show-toplevel 2>$null).Trim()
if (-not $repoRoot) { throw "Not inside a git repository." }
Set-Location $repoRoot

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$resultsDir = Join-Path $repoRoot "Scripts\Tests\Test-CodexStartupPromptResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "CodexStartupPromptTest-$stamp.log"

$script:PassCount = 0
$script:FailCount = 0
$script:WarnCount = 0
$script:SkipCount = 0

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

function Assert-Condition {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][bool]$Condition,
    [string]$PassDetail = "condition is true",
    [string]$FailDetail = "condition is false"
  )

  if ($Condition) {
    Pass $Name $PassDetail
    return
  }

  Fail $Name $FailDetail
}

function Assert-TextContains {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Needle
  )

  if ([string]::Concat($Text).Contains($Needle)) {
    Pass $Name "matched: $Needle"
    return
  }

  Fail $Name "missing expected text: $Needle"
}

function Assert-TextNotContains {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Needle
  )

  if (-not [string]::Concat($Text).Contains($Needle)) {
    Pass $Name "did not match: $Needle"
    return
  }

  Fail $Name "unexpected text found: $Needle"
}

try {
  Step "Codex Startup Prompt Tests ($stamp)"
  Write-Log "Repo: $repoRoot" Cyan
  Write-Log "Log : $logPath" Cyan

  $scriptPath = Join-Path $repoRoot "Scripts\Codex\Get-CodexStartupPrompt.ps1"
  Assert-Condition "script exists" (Test-Path -LiteralPath $scriptPath) "Get-CodexStartupPrompt.ps1 found"

  Step "Case 1: Default prompt lists repo docs and coding-standard guidance"
  $defaultPrompt = (& $scriptPath -RepoRoot $repoRoot) -join "`n"
  Assert-TextContains "case1 reads AGENTS first" $defaultPrompt "Read AGENTS.md first."
  Assert-TextContains "case1 includes docs read line" $defaultPrompt "Then read these repo markdown docs before doing substantial work:"
  Assert-TextContains "case1 includes docs overview" $defaultPrompt "Docs/README.md"
  Assert-TextContains "case1 includes Coding Standards readme" $defaultPrompt "Docs/CodingStandards/README.md"
  Assert-TextContains "case1 includes Scripts readme" $defaultPrompt "Scripts/README.md"
  Assert-TextContains "case1 includes snapshot line" $defaultPrompt "Current Unreal C++ standard snapshot:"
  Assert-TextContains "case1 includes coding standards scrutiny note" $defaultPrompt "If this task touches C++ or style-sensitive code, scrutinize Docs/CodingStandards/README.md"
  Assert-TextNotContains "case1 excludes private context by default" $defaultPrompt ".codex-local/Private-Context.md"

  Step "Case 2: Task and private context are included on request"
  $taskPrompt = (& $scriptPath -RepoRoot $repoRoot -Task "Fix UnrealSync regeneration messaging" -IncludePrivate) -join "`n"
  Assert-TextContains "case2 includes task header" $taskPrompt "Task:"
  Assert-TextContains "case2 includes task text" $taskPrompt "Fix UnrealSync regeneration messaging"
  Assert-TextContains "case2 includes private context line" $taskPrompt "Also use .codex-local/Private-Context.md for my local preferences."

  Step "Case 3: Fresh snapshot is reported as not stale"
  Assert-TextContains "case3 snapshot freshness line" $defaultPrompt "It is not older than six months."
  Assert-TextNotContains "case3 no stale refresh demand" $defaultPrompt 'Refresh it with `pwsh -File Docs/CodingStandards/Sync-UnrealCppStandard.ps1`'

  Step "Summary"
  Write-Log ("PASS={0} FAIL={1} WARN={2} SKIP={3}" -f $script:PassCount, $script:FailCount, $script:WarnCount, $script:SkipCount) Cyan
  if ($script:FailCount -eq 0) {
    Write-Log "Codex startup prompt tests passed." Green
  }
  else {
    Write-Log "Codex startup prompt tests failed." Red
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
  Write-Log ""
  Write-Log "Log saved: $logPath" Cyan
}
