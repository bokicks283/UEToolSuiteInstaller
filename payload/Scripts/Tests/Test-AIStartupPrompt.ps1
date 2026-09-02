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
    param(
      [string]$CommandRepoRoot = $repoRoot,
      [string[]]$CommandArgs = @()
    )
    $args = @(
      "-NoLogo",
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-File", $entrypointPath,
      "-RepoRoot", $CommandRepoRoot,
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

  $promptRepoRoot = Join-Path $resultsDir "prompt-repo-$stamp"
  Write-Utf8NoBomFile -Path (Join-Path $promptRepoRoot "AGENTS.md") -Content "Read AGENTS.md first.`n"
  Write-Utf8NoBomFile -Path (Join-Path $promptRepoRoot "Docs\README.md") -Content "# Docs`n"
  Write-Utf8NoBomFile -Path (Join-Path $promptRepoRoot "Docs\WorkflowStandards\CodingStandards\README.md") -Content "# Coding Standards`n"
  Write-Utf8NoBomFile -Path (Join-Path $promptRepoRoot "Docs\WorkflowStandards\CodingStandards\UnrealCppStandard.md") -Content "# Unreal C++ Standard`n"
  Write-Utf8NoBomFile -Path (Join-Path $promptRepoRoot "Docs\WorkflowStandards\CodingStandards\Current\SOURCE.md") -Content ("# Source`n`n- Snapshot date: {0}`n" -f (Get-Date).ToString("yyyy-MM-dd"))
  Write-Utf8NoBomFile -Path (Join-Path $promptRepoRoot "Scripts\README.md") -Content "# Scripts`n"
  Write-Utf8NoBomFile -Path (Join-Path $promptRepoRoot ".ai-local\Private-Context.md") -Content "Local test-only private context.`n"

  Step "Case 1: Default prompt lists repo docs and coding-standard guidance"
  $defaultPrompt = (Invoke-AIPrompt -CommandRepoRoot $promptRepoRoot) -join "`n"
  Assert-TextContains "case1 reads AGENTS first" $defaultPrompt "Read AGENTS.md first."
  Assert-TextContains "case1 includes docs read line" $defaultPrompt "Then read these repo markdown docs before doing substantial work:"
  Assert-TextContains "case1 includes docs overview" $defaultPrompt "Docs/README.md"
  Assert-TextContains "case1 includes Coding Standards readme" $defaultPrompt "Docs/WorkflowStandards/CodingStandards/README.md"
  Assert-TextContains "case1 includes Scripts readme" $defaultPrompt "Scripts/README.md"
  Assert-TextContains "case1 includes snapshot line" $defaultPrompt "Current Unreal C++ standard snapshot:"
  Assert-TextContains "case1 reports canonical snapshot path" $defaultPrompt "Current Unreal C++ standard snapshot: Docs/WorkflowStandards/CodingStandards/Current"
  Assert-TextContains "case1 includes coding standards scrutiny note" $defaultPrompt "If this task touches C++ or style-sensitive code, scrutinize Docs/WorkflowStandards/CodingStandards/README.md"
  Assert-TextNotContains "case1 excludes private context by default" $defaultPrompt ".ai-local/Private-Context.md"

  Step "Case 2: Task and private context are included on request"
  $taskPrompt = (Invoke-AIPrompt -CommandRepoRoot $promptRepoRoot -CommandArgs @("-Task", "Fix UnrealSync regeneration messaging", "-IncludePrivate")) -join "`n"
  Assert-TextContains "case2 includes task header" $taskPrompt "Task:"
  Assert-TextContains "case2 includes task text" $taskPrompt "Fix UnrealSync regeneration messaging"
  Assert-TextContains "case2 includes private context line" $taskPrompt "Also use .ai-local/Private-Context.md for my local preferences."

  Step "Case 3: Fresh snapshot is reported as not stale"
  Assert-TextContains "case3 snapshot freshness line" $defaultPrompt "It is not older than six months."
  Assert-TextNotContains "case3 no stale refresh demand" $defaultPrompt 'Refresh it with `pwsh -File Docs/WorkflowStandards/CodingStandards/Sync-UnrealCppStandard.ps1`'

  Step "Case 4: Legacy coding-standard snapshot path remains supported"
  $legacyRepoRoot = Join-Path $resultsDir "legacy-prompt-repo-$stamp"
  Write-Utf8NoBomFile -Path (Join-Path $legacyRepoRoot "AGENTS.md") -Content "Read AGENTS.md first.`n"
  Write-Utf8NoBomFile -Path (Join-Path $legacyRepoRoot "Docs\CodingStandards\Current\SOURCE.md") -Content "# Source`n`n- Snapshot date: 2000-01-01`n"
  $legacyPrompt = (Invoke-AIPrompt -CommandRepoRoot $legacyRepoRoot) -join "`n"
  Assert-TextContains "case4 reports legacy snapshot path" $legacyPrompt "Current Unreal C++ standard snapshot: Docs/CodingStandards/Current"
  Assert-TextContains "case4 uses legacy refresh path" $legacyPrompt 'Docs/CodingStandards/Sync-UnrealCppStandard.ps1'

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
