[CmdletBinding()]
param(
  [switch]$NoCleanup,
  [switch]$FailFast
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$installerRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$installerScript = Join-Path $installerRoot "Install-UEToolSuite.ps1"
$fixtureHelper = Join-Path $PSScriptRoot "TestSupport\UEProjectFixtures.ps1"
if (-not (Test-Path -LiteralPath $fixtureHelper -PathType Leaf)) {
  throw "UE project fixture helper not found: $fixtureHelper"
}
. $fixtureHelper
$testHarnessPath = Join-Path $installerRoot "payload\Scripts\Tests\TestHarness.ps1"
if (-not (Test-Path -LiteralPath $testHarnessPath -PathType Leaf)) {
  throw "Test harness not found: $testHarnessPath"
}
. $testHarnessPath

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$resultsDir = Join-Path $PSScriptRoot "Test-UpgradeCompatibilityResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "UpgradeCompatibility-$stamp.log"
$scratchRoot = New-TestScratchRoot -Prefix "ue tool suite upgrade compatibility"

$script:PassCount = 0
$script:FailCount = 0
Initialize-TestHarness -LogPath $logPath -FailFast:$FailFast

function Invoke-CapturedPwsh {
  param(
    [Parameter(Mandatory)][string[]]$Arguments,
    [string]$WorkingDirectory = $installerRoot
  )

  Write-Log ">> pwsh $($Arguments -join ' ')" DarkGray
  Push-Location $WorkingDirectory
  try {
    $output = @(& pwsh @Arguments 2>&1)
    $code = $LASTEXITCODE
  }
  finally {
    Pop-Location
  }

  $normalized = @()
  foreach ($line in $output) {
    $text = Remove-AnsiEscapeSequences -Text "$line"
    $normalized += $text
    if (-not [string]::IsNullOrWhiteSpace($text)) {
      Write-Log ("   " + $text.TrimEnd()) DarkGray
    }
  }

  [pscustomobject]@{
    Code = $code
    Output = ($normalized | ForEach-Object { "$_" }) -join "`n"
  }
}

function Invoke-InstallerForUpgradeTest {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [switch]$RunInit
  )

  $args = @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $installerScript,
    "-TargetRepoRoot", $TargetRoot
  )

  if ($RunInit) {
    $args += @(
      "-RunInit",
      "-SkipLfsPull",
      "-SkipShellAliases",
      "-SkipOptionalToolSetup",
      "-SkipDocsSetup",
      "-SkipUnrealSync"
    )
  }

  Invoke-CapturedPwsh -Arguments $args
}

function Invoke-CompatibilityCommand {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$ExpectedText,
    [Parameter(Mandatory)][string]$TargetRoot,
    [string[]]$UnexpectedText = @()
  )

  $result = Invoke-CapturedPwsh -Arguments $Arguments -WorkingDirectory $TargetRoot
  Assert-Condition -Name "$Name exits cleanly" -Condition ($result.Code -eq 0) -PassDetail "exit=0" -FailDetail "exit=$($result.Code)"
  Assert-TextContains -Name "$Name output" -Text $result.Output -Needle $ExpectedText
  foreach ($unexpected in $UnexpectedText) {
    Assert-TextNotContains -Name "$Name excludes $unexpected" -Text $result.Output -Needle $unexpected
  }
}

function Install-TestProfileAliases {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$ProfilePath
  )

  $aliasScript = Join-Path $TargetRoot "Scripts\Unreal\ProjectShellAliases.ps1"
  $bootstrapPath = Join-Path (Split-Path -Parent $ProfilePath) "UEToolsBootstrap.ps1"
  $escapedAliasScript = $aliasScript.Replace("'", "''")
  $escapedProfile = $ProfilePath.Replace("'", "''")
  $escapedBootstrapPath = $bootstrapPath.Replace("'", "''")
  $command = ". '$escapedAliasScript'; Install-ProjectShellAliases -ProfilePath '$escapedProfile' -BootstrapScriptPath '$escapedBootstrapPath' | ConvertTo-Json -Depth 5"

  $result = Invoke-CapturedPwsh -Arguments @("-NoLogo", "-NoProfile", "-Command", $command) -WorkingDirectory $TargetRoot
  Assert-Condition -Name "profile alias install exits cleanly" -Condition ($result.Code -eq 0) -PassDetail "exit=0" -FailDetail "exit=$($result.Code)"
  Assert-TextContains -Name "profile alias metadata includes ue-tools" -Text $result.Output -Needle "ue-tools"
  Assert-TextContains -Name "profile alias metadata includes codex-prompt" -Text $result.Output -Needle "codex-prompt"
  Assert-Condition -Name "profile alias bootstrap file created" -Condition (Test-Path -LiteralPath $bootstrapPath -PathType Leaf) -PassDetail "bootstrap present" -FailDetail "bootstrap missing: $bootstrapPath"
}

function Invoke-ProfileAliasSmoke {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$ProfilePath
  )

  $escapedProfile = $ProfilePath.Replace("'", "''")
  $escapedTarget = $TargetRoot.Replace("'", "''")
  $command = @"
. '$escapedProfile'
Set-Location -LiteralPath '$escapedTarget'
ue-tools help
docs-tools help
art-tools --help
codex-prompt --help
"@

  $result = Invoke-CapturedPwsh -Arguments @("-NoLogo", "-NoProfile", "-Command", $command) -WorkingDirectory $TargetRoot
  Assert-Condition -Name "profile aliases exit cleanly" -Condition ($result.Code -eq 0) -PassDetail "exit=0" -FailDetail "exit=$($result.Code)"
  Assert-TextContains -Name "profile alias ue-tools works" -Text $result.Output -Needle "UE tools wrapper"
  Assert-TextContains -Name "profile alias docs-tools works" -Text $result.Output -Needle "UE project docs automation."
  Assert-TextContains -Name "profile alias art-tools works" -Text $result.Output -Needle "Art tools wrapper"
  Assert-TextContains -Name "profile alias codex-prompt works" -Text $result.Output -Needle "Codex startup prompt builder"
}

function Invoke-DirectEntrypointSmoke {
  param([Parameter(Mandatory)][string]$TargetRoot)

  Invoke-CompatibilityCommand `
    -Name "direct ue-tools help" `
    -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $TargetRoot "Scripts\ue-tools.ps1"), "-RepoRoot", $TargetRoot, "help") `
    -ExpectedText "UE tools wrapper for repository Unreal helpers." `
    -TargetRoot $TargetRoot

  Invoke-CompatibilityCommand `
    -Name "direct legacy ue-tools wrapper help" `
    -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $TargetRoot "Scripts\UETools\ue-tools.ps1"), "-RepoRoot", $TargetRoot, "help") `
    -ExpectedText "UE tools wrapper for repository Unreal helpers." `
    -TargetRoot $TargetRoot

  Invoke-CompatibilityCommand `
    -Name "direct UnrealSync dry-run" `
    -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $TargetRoot "Scripts\Unreal\UnrealSync.ps1"), "-RepoRoot", $TargetRoot, "-Force", "-NoBuild", "-NoRegen", "-DryRun") `
    -ExpectedText "DryRun enabled" `
    -TargetRoot $TargetRoot

  Invoke-CompatibilityCommand `
    -Name "direct docs-tools help" `
    -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $TargetRoot "Scripts\Docs\DocsTools.ps1"), "-RepoRoot", $TargetRoot, "help") `
    -ExpectedText "UE project docs automation." `
    -TargetRoot $TargetRoot

  Invoke-CompatibilityCommand `
    -Name "direct codex prompt" `
    -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $TargetRoot "Scripts\Codex\Get-CodexStartupPrompt.ps1"), "-RepoRoot", $TargetRoot, "-Task", "Validate compatibility") `
    -ExpectedText "Validate compatibility" `
    -TargetRoot $TargetRoot `
    -UnexpectedText @(".ue-tools-installer-backups/")
}

try {
  Step "Upgrade compatibility setup"
  Write-Log "Installer: $installerScript" Cyan
  Write-Log "Scratch  : $scratchRoot" Cyan

  $targetRepo = New-TestUEProjectRepo -Root $scratchRoot -Name "PortableSample" -WithGit -WithDocsSite -WithArtSource -WithSourceModule
  Write-TestUtf8NoBomFile -Path (Join-Path $targetRepo "AGENTS.md") -Content "Read AGENTS.md first.`n"
  Write-TestUtf8NoBomFile -Path (Join-Path $targetRepo ".codex-local\Private-Context.md") -Content "Local test-only private context.`n"

  $installResult = Invoke-InstallerForUpgradeTest -TargetRoot $targetRepo -RunInit
  Assert-Condition -Name "initial install exits cleanly" -Condition ($installResult.Code -eq 0) -PassDetail "exit=0" -FailDetail "exit=$($installResult.Code)"

  $profilePath = Join-Path $scratchRoot "profile.ps1"
  Install-TestProfileAliases -TargetRoot $targetRepo -ProfilePath $profilePath

  Step "Compatibility before update"
  Invoke-DirectEntrypointSmoke -TargetRoot $targetRepo
  Invoke-ProfileAliasSmoke -TargetRoot $targetRepo -ProfilePath $profilePath

  Step "Compatibility after update without reinstalling profile aliases"
  $updateResult = Invoke-InstallerForUpgradeTest -TargetRoot $targetRepo
  Assert-Condition -Name "update install exits cleanly" -Condition ($updateResult.Code -eq 0) -PassDetail "exit=0" -FailDetail "exit=$($updateResult.Code)"
  Invoke-DirectEntrypointSmoke -TargetRoot $targetRepo
  Invoke-ProfileAliasSmoke -TargetRoot $targetRepo -ProfilePath $profilePath

  Step "Summary"
  Write-Log ("PASS={0} FAIL={1}" -f $script:PassCount, $script:FailCount) Cyan
  if ($script:FailCount -eq 0) {
    Write-Log "Upgrade compatibility tests passed." Green
  }
  else {
    Write-Log "Upgrade compatibility tests failed." Red
    exit 1
  }
}
catch {
  if ($_.Exception.Message -ne "FAILFAST") {
    Write-Log "[FATAL] $($_.Exception.Message)" Red
  }
  Write-Log ("PASS={0} FAIL={1}" -f $script:PassCount, $script:FailCount) Cyan
  if ($script:FailCount -eq 0) { $script:FailCount = 1 }
  exit 1
}
finally {
  if ($NoCleanup) {
    Write-Log "[WARN] Cleanup - NoCleanup set; leaving scratch root: $scratchRoot" Yellow
  }
  elseif (Test-Path -LiteralPath $scratchRoot) {
    Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
  }

  Write-Log ""
  Write-Log "Log saved: $logPath" Cyan
}
