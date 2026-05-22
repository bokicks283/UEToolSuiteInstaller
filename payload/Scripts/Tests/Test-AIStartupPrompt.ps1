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
$resultsDir = Join-Path $repoRoot "Scripts\Tests\Test-AIStartupPromptResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "AIStartupPromptTest-$stamp.log"
$testHarnessPath = Join-Path $repoRoot "Scripts\Tests\TestHarness.ps1"
if (-not (Test-Path -LiteralPath $testHarnessPath -PathType Leaf)) {
  throw "Test harness not found: $testHarnessPath"
}
. $testHarnessPath

$script:PassCount = 0
$script:FailCount = 0
$script:WarnCount = 0
$script:SkipCount = 0
Initialize-TestHarness -LogPath $logPath -FailFast:$FailFast

try {
  Step "AI Startup Prompt Tests ($stamp)"
  Write-Log "Repo: $repoRoot" Cyan
  Write-Log "Log : $logPath" Cyan

  $entrypointPath = Join-Path $repoRoot "Scripts\ue-tools.ps1"
  Assert-Condition "dispatcher entrypoint exists" (Test-Path -LiteralPath $entrypointPath) "Scripts\\ue-tools.ps1 found"

  function Invoke-AIPrompt {
    param([string[]]$CommandArgs = @())
    $args = @(
      "-NoLogo",
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-File", $entrypointPath,
      "-RepoRoot", $repoRoot,
      "ai",
      "prompt"
    )
    $args += @($CommandArgs)
    $output = @(& pwsh @args 2>&1)
    if ($LASTEXITCODE -ne 0) {
      throw "ue-tools ai prompt failed with exit code ${LASTEXITCODE}: $($output -join "`n")"
    }
    return @($output | ForEach-Object { "$_" })
  }

  Step "Case 1: Default prompt lists repo docs and coding-standard guidance"
  $defaultPrompt = (Invoke-AIPrompt) -join "`n"
  Assert-TextContains "case1 reads AGENTS first" $defaultPrompt "Read AGENTS.md first."
  Assert-TextContains "case1 includes docs read line" $defaultPrompt "Then read these repo markdown docs before doing substantial work:"
  Assert-TextContains "case1 includes docs overview" $defaultPrompt "Docs/README.md"
  Assert-TextContains "case1 includes Coding Standards readme" $defaultPrompt "Docs/CodingStandards/README.md"
  Assert-TextContains "case1 includes Scripts readme" $defaultPrompt "Scripts/README.md"
  Assert-TextContains "case1 includes snapshot line" $defaultPrompt "Current Unreal C++ standard snapshot:"
  Assert-TextContains "case1 includes coding standards scrutiny note" $defaultPrompt "If this task touches C++ or style-sensitive code, scrutinize Docs/CodingStandards/README.md"
  Assert-TextNotContains "case1 excludes private context by default" $defaultPrompt ".ai-local/Private-Context.md"

  Step "Case 2: Task and private context are included on request"
  $taskPrompt = (Invoke-AIPrompt -CommandArgs @("-Task", "Fix UnrealSync regeneration messaging", "-IncludePrivate")) -join "`n"
  Assert-TextContains "case2 includes task header" $taskPrompt "Task:"
  Assert-TextContains "case2 includes task text" $taskPrompt "Fix UnrealSync regeneration messaging"
  Assert-TextContains "case2 includes private context line" $taskPrompt "Also use .ai-local/Private-Context.md for my local preferences."

  Step "Case 3: Fresh snapshot is reported as not stale"
  Assert-TextContains "case3 snapshot freshness line" $defaultPrompt "It is not older than six months."
  Assert-TextNotContains "case3 no stale refresh demand" $defaultPrompt 'Refresh it with `pwsh -File Docs/CodingStandards/Sync-UnrealCppStandard.ps1`'

  Step "Summary"
  Write-Log ("PASS={0} FAIL={1} WARN={2} SKIP={3}" -f $script:PassCount, $script:FailCount, $script:WarnCount, $script:SkipCount) Cyan
  if ($script:FailCount -eq 0) {
    Write-Log "AI startup prompt tests passed." Green
  }
  else {
    Write-Log "AI startup prompt tests failed." Red
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
