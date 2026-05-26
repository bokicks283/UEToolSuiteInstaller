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

  return [pscustomobject]@{
    Code = $code
    Output = ($normalized -join "`n")
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

function Install-TestProfileAliases {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$ProfilePath
  )

  $aliasModulePath = Join-Path $TargetRoot "Scripts\UETools\UEToolSuite.Aliases.psm1"
  $bootstrapPath = Join-Path (Split-Path -Parent $ProfilePath) "UEToolsBootstrap.ps1"
  $escapedAliasModule = $aliasModulePath.Replace("'", "''")
  $escapedProfile = $ProfilePath.Replace("'", "''")
  $escapedBootstrap = $bootstrapPath.Replace("'", "''")
  $command = @"
Import-Module '$escapedAliasModule' -Force
Install-ProjectShellAliases -ProfilePath '$escapedProfile' -BootstrapScriptPath '$escapedBootstrap' -ScriptsRoot '$($TargetRoot.Replace("'", "''"))\\Scripts' | ConvertTo-Json -Depth 5
"@

  $result = Invoke-CapturedPwsh -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command) -WorkingDirectory $TargetRoot
  Assert-Condition -Name "profile alias install exits cleanly" -Condition ($result.Code -eq 0) -PassDetail "exit=0" -FailDetail "exit=$($result.Code)"
  Assert-TextContains -Name "profile alias metadata includes ue-tools" -Text $result.Output -Needle "ue-tools"
  Assert-TextContains -Name "profile alias metadata includes ue" -Text $result.Output -Needle "`"ue`""
  Assert-Condition -Name "profile alias bootstrap file created" -Condition (Test-Path -LiteralPath $bootstrapPath -PathType Leaf) -PassDetail "bootstrap present" -FailDetail "bootstrap missing: $bootstrapPath"
  $profileText = Get-Content -LiteralPath $ProfilePath -Raw
  Assert-TextContains -Name "profile snippet uses lazy bootstrap initializer" -Text $profileText -Needle "function Initialize-UEToolsShell"
  Assert-TextContains -Name "profile snippet uses lazy wrapper dispatch" -Text $profileText -Needle "function Invoke-UEToolsLazyShellCommand"
  Assert-TextContains -Name "profile snippet binds ue-tools to lazy wrapper" -Text $profileText -Needle "Set-Alias -Name `"ue-tools`" -Value `"Invoke-UEToolsLazyShellCommand`" -Scope Global"
  Assert-TextContains -Name "profile snippet binds ue to lazy wrapper" -Text $profileText -Needle "Set-Alias -Name `"ue`" -Value `"Invoke-UEToolsLazyShellCommand`" -Scope Global"
}

function Invoke-CompatibilityCommand {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$ExpectedText,
    [Parameter(Mandatory)][string]$TargetRoot
  )

  $result = Invoke-CapturedPwsh -Arguments $Arguments -WorkingDirectory $TargetRoot
  Assert-Condition -Name "$Name exits cleanly" -Condition ($result.Code -eq 0) -PassDetail "exit=0" -FailDetail "exit=$($result.Code)"
  Assert-TextContains -Name "$Name output" -Text $result.Output -Needle $ExpectedText
}

function Invoke-DirectEntrypointSmoke {
  param([Parameter(Mandatory)][string]$TargetRoot)

  $entrypoint = Join-Path $TargetRoot "Scripts\ue-tools.ps1"

  Invoke-CompatibilityCommand `
    -Name "direct ue-tools help" `
    -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $entrypoint, "-RepoRoot", $TargetRoot, "help") `
    -ExpectedText "UE Tool Suite dispatcher." `
    -TargetRoot $TargetRoot

  Invoke-CompatibilityCommand `
    -Name "direct ue-tools build dry-run" `
    -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $entrypoint, "-RepoRoot", $TargetRoot, "build", "-NoBuild", "-NoRegen", "-DryRun") `
    -ExpectedText "DryRun enabled" `
    -TargetRoot $TargetRoot

  Invoke-CompatibilityCommand `
    -Name "direct ue-tools docs help" `
    -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $entrypoint, "-RepoRoot", $TargetRoot, "docs", "help") `
    -ExpectedText "UE project docs automation." `
    -TargetRoot $TargetRoot

  Invoke-CompatibilityCommand `
    -Name "direct ue-tools ai prompt" `
    -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $entrypoint, "-RepoRoot", $TargetRoot, "ai", "prompt", "-Task", "Validate dispatcher compatibility", "-IncludePrivate") `
    -ExpectedText "Validate dispatcher compatibility" `
    -TargetRoot $TargetRoot
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
ue help
ue-tools docs help
ue-tools ai prompt --help
docs-tools help
"@

  $result = Invoke-CapturedPwsh -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command) -WorkingDirectory $TargetRoot
  Assert-Condition -Name "profile aliases run" -Condition ($result.Code -ne 0) -PassDetail "legacy alias command fails as expected" -FailDetail "expected non-zero because docs-tools should not exist"
  Assert-TextContains -Name "profile alias ue-tools works" -Text $result.Output -Needle "UE Tool Suite dispatcher."
  Assert-TextContains -Name "profile alias ue works" -Text $result.Output -Needle "UE Tool Suite dispatcher."
  Assert-TextContains -Name "profile alias docs domain works" -Text $result.Output -Needle "UE project docs automation."
  Assert-TextContains -Name "profile alias ai domain help works" -Text $result.Output -Needle "AI startup prompt builder"
  Assert-TextContains -Name "legacy docs-tools command rejected" -Text $result.Output -Needle "docs-tools"
}

function Assert-InstalledPayloadContract {
  param([Parameter(Mandatory)][string]$TargetRoot)

  Assert-Condition -Name "payload contract ue-tools path present" -Condition (Test-Path -LiteralPath (Join-Path $TargetRoot "Scripts\ue-tools.ps1") -PathType Leaf) -PassDetail "Scripts\\ue-tools.ps1 present" -FailDetail "Scripts\\ue-tools.ps1 missing"
  Assert-Condition -Name "payload contract init runtime present" -Condition (Test-Path -LiteralPath (Join-Path $TargetRoot "Scripts\Init-Repo.Runtime.ps1") -PathType Leaf) -PassDetail "Init-Repo.Runtime present" -FailDetail "Init-Repo.Runtime missing"
  Assert-Condition -Name "payload contract unreal runtime present" -Condition (Test-Path -LiteralPath (Join-Path $TargetRoot "Scripts\Unreal\UnrealSync.Runtime.ps1") -PathType Leaf) -PassDetail "UnrealSync.Runtime present" -FailDetail "UnrealSync.Runtime missing"
  Assert-Condition -Name "payload contract docs runtime present" -Condition (Test-Path -LiteralPath (Join-Path $TargetRoot "Scripts\Docs\DocsTools.Runtime.ps1") -PathType Leaf) -PassDetail "DocsTools.Runtime present" -FailDetail "DocsTools.Runtime missing"
  Assert-Condition -Name "payload contract git runtime present" -Condition (Test-Path -LiteralPath (Join-Path $TargetRoot "Scripts\git-tools\GitConflictHelpers.Runtime.ps1") -PathType Leaf) -PassDetail "GitConflictHelpers.Runtime present" -FailDetail "GitConflictHelpers.Runtime missing"
  Assert-Condition -Name "payload contract legacy init script removed" -Condition (-not (Test-Path -LiteralPath (Join-Path $TargetRoot "Scripts\Init-Repo.ps1"))) -PassDetail "legacy Init-Repo absent" -FailDetail "legacy Init-Repo still present"
  Assert-Condition -Name "payload contract legacy unreal script removed" -Condition (-not (Test-Path -LiteralPath (Join-Path $TargetRoot "Scripts\Unreal\UnrealSync.ps1"))) -PassDetail "legacy UnrealSync absent" -FailDetail "legacy UnrealSync still present"
  Assert-Condition -Name "payload contract legacy docs script removed" -Condition (-not (Test-Path -LiteralPath (Join-Path $TargetRoot "Scripts\Docs\DocsTools.ps1"))) -PassDetail "legacy DocsTools absent" -FailDetail "legacy DocsTools still present"
  Assert-Condition -Name "payload contract legacy git helper removed" -Condition (-not (Test-Path -LiteralPath (Join-Path $TargetRoot "Scripts\git-tools\GitConflictHelpers.ps1"))) -PassDetail "legacy GitConflictHelpers absent" -FailDetail "legacy GitConflictHelpers still present"
  Assert-Condition -Name "payload contract legacy wrapper removed" -Condition (-not (Test-Path -LiteralPath (Join-Path $TargetRoot "Scripts\UETools\ue-tools.ps1"))) -PassDetail "legacy wrapper absent" -FailDetail "legacy Scripts\\UETools\\ue-tools.ps1 still present"
  Assert-Condition -Name "payload contract legacy shell helper removed" -Condition (-not (Test-Path -LiteralPath (Join-Path $TargetRoot "Scripts\Unreal\ProjectShellAliases.ps1"))) -PassDetail "legacy ProjectShellAliases absent" -FailDetail "legacy ProjectShellAliases still present"
  Assert-Condition -Name "payload contract legacy shim removed" -Condition (-not (Test-Path -LiteralPath (Join-Path $TargetRoot "Scripts\Unreal\UESyncShellAliases.ps1"))) -PassDetail "legacy UESyncShellAliases absent" -FailDetail "legacy UESyncShellAliases still present"
  Assert-Condition -Name "payload contract installer script not copied to target root" -Condition (-not (Test-Path -LiteralPath (Join-Path $TargetRoot "Install-UEToolSuite.ps1"))) -PassDetail "installer script absent in target root" -FailDetail "installer script should remain installer-only"
  Assert-Condition -Name "payload contract installer tests folder not copied to target root" -Condition (-not (Test-Path -LiteralPath (Join-Path $TargetRoot "Tests"))) -PassDetail "installer Tests folder absent in target root" -FailDetail "installer Tests folder should not be copied to payload target"
}

try {
  Step "Upgrade compatibility setup"
  Write-Log "Installer: $installerScript" Cyan
  Write-Log "Scratch  : $scratchRoot" Cyan

  $targetRepo = New-TestUEProjectRepo -Root $scratchRoot -Name "PortableSample" -WithGit -WithDocsSite -WithArtSource -WithSourceModule
  Write-TestUtf8NoBomFile -Path (Join-Path $targetRepo "AGENTS.md") -Content "Read AGENTS.md first.`n"
  Write-TestUtf8NoBomFile -Path (Join-Path $targetRepo ".ai-local\Private-Context.md") -Content "Local test-only private context.`n"
  Write-TestUtf8NoBomFile -Path (Join-Path $targetRepo ".codex-local\Private-Context.md") -Content "Legacy codex private context should be ignored.`n"

  $installResult = Invoke-InstallerForUpgradeTest -TargetRoot $targetRepo -RunInit
  Assert-Condition -Name "initial install exits cleanly" -Condition ($installResult.Code -eq 0) -PassDetail "exit=0" -FailDetail "exit=$($installResult.Code)"
  Assert-InstalledPayloadContract -TargetRoot $targetRepo

  $profilePath = Join-Path $scratchRoot "profile.ps1"
  Install-TestProfileAliases -TargetRoot $targetRepo -ProfilePath $profilePath

  Step "Compatibility before update"
  Invoke-DirectEntrypointSmoke -TargetRoot $targetRepo
  Invoke-ProfileAliasSmoke -TargetRoot $targetRepo -ProfilePath $profilePath

  Step "Compatibility after update without reinstalling profile aliases"
  $updateResult = Invoke-InstallerForUpgradeTest -TargetRoot $targetRepo
  Assert-Condition -Name "update install exits cleanly" -Condition ($updateResult.Code -eq 0) -PassDetail "exit=0" -FailDetail "exit=$($updateResult.Code)"
  Assert-InstalledPayloadContract -TargetRoot $targetRepo
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
