[CmdletBinding()]
param(
  [switch]$NoCleanup,
  [switch]$FailFast
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = (git rev-parse --show-toplevel 2>$null).Trim()
if (-not $repoRoot) { throw "Not inside a git repository." }
Set-Location $repoRoot

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$resultsDir = Join-Path $repoRoot "Scripts\Tests\Test-UESyncShellAliasesResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "UESyncShellAliasesTest-$stamp.log"
$scratchRoot = Join-Path $resultsDir "scratch-$stamp"
New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null

$script:PassCount = 0
$script:FailCount = 0
$script:WarnCount = 0
$script:SkipCount = 0
$script:CleanupRan = $false
$script:ExternalTempDirs = New-Object System.Collections.Generic.List[string]

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

function Assert-Condition {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][bool]$Condition,
    [string]$PassDetail = "condition is true",
    [string]$FailDetail = "condition is false"
  )
  if ($Condition) { Pass $Name $PassDetail; return }
  Fail $Name $FailDetail
}

function Assert-TextContains {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Needle
  )
  if ([string]::Concat($Text).Contains($Needle)) { Pass $Name "matched: $Needle"; return }
  Fail $Name "missing expected text: $Needle"
}

function Assert-TextNotContains {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Needle
  )
  if (-not [string]::Concat($Text).Contains($Needle)) { Pass $Name "did not match: $Needle"; return }
  Fail $Name "unexpected text found: $Needle"
}

function Normalize-Newlines([string]$Text) {
  if ($null -eq $Text) { return "" }
  return ($Text -replace "`r`n", "`n" -replace "`r", "`n")
}

function Count-Matches {
  param(
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Pattern
  )
  return [regex]::Matches($Text, $Pattern).Count
}

function Remove-ManagedBlock {
  param(
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$StartMarker,
    [Parameter(Mandatory)][string]$EndMarker
  )
  $pattern = "(?s)$([regex]::Escape($StartMarker)).*?$([regex]::Escape($EndMarker))"
  return [regex]::Replace($Text, $pattern, "")
}

function Write-TextFileLf {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Content
  )

  $normalized = Normalize-Newlines $Content
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

function New-ScratchPath([string]$Name) {
  return (Join-Path $scratchRoot $Name)
}

function Reset-LoadedAliases {
  Remove-Item -LiteralPath Function:\Invoke-UETools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Function:\Invoke-ArtTools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Function:\Invoke-DocsTools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Function:\Invoke-CodexTools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Function:\Invoke-CodexPrompt -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Function:\Invoke-UESync -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Function:\Invoke-CozyUESync -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\ue-tools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\art-tools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\docs-tools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\codex-tools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\codex-prompt -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\uesync -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\ue-sync -ErrorAction SilentlyContinue
}

function Restore-State {
  if ($script:CleanupRan) { return }
  $script:CleanupRan = $true

  Reset-LoadedAliases

  if ($NoCleanup) {
    Warn "Cleanup" "NoCleanup set; leaving scratch files in place."
    return
  }

  try {
    if (Test-Path -LiteralPath $scratchRoot) {
      Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    foreach ($p in ($script:ExternalTempDirs | Sort-Object -Unique)) {
      if ($p -and (Test-Path -LiteralPath $p)) {
        Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
  }
  catch {
    Warn "Cleanup" "Could not fully delete scratch data."
  }
}

try {
  Step "Project Shell Alias Automated Tests ($stamp)"
  Write-Log "Repo: $repoRoot" Cyan
  Write-Log "Log : $logPath" Cyan

  $helperPath = Join-Path $repoRoot "Scripts\Unreal\ProjectShellAliases.ps1"
  if (-not (Test-Path -LiteralPath $helperPath)) {
    throw "Helper script not found: $helperPath"
  }
  . $helperPath
  $artToolsAvailable = Test-ProjectAliasRepoScriptAvailable -RelativePath "New-ArtSourcePath.ps1"
  $docsToolsAvailable = Test-ProjectAliasRepoScriptAvailable -RelativePath "..\Docs\DocsTools.ps1"
  $codexToolsAvailable = Test-ProjectAliasRepoScriptAvailable -RelativePath "..\Codex\Get-CodexStartupPrompt.ps1"

  Step "Case 1: Alias definition table is present and complete"
  $definitions = @(Get-ProjectAliasDefinitions)
  $definitionIds = @($definitions | ForEach-Object { $_.Id })
  $expectedAliasCount = 1
  if ($artToolsAvailable) { $expectedAliasCount++ }
  if ($docsToolsAvailable) { $expectedAliasCount++ }
  if ($codexToolsAvailable) { $expectedAliasCount += 2 }
  Assert-Condition "case1 expected aliases defined" ($definitions.Count -eq $expectedAliasCount) "definition count=$expectedAliasCount"
  Assert-Condition "case1 includes ue-tools" ($definitionIds -contains "ue-tools") "ue-tools definition found"
  Assert-Condition "case1 ue-tools function mapping" ((@($definitions | Where-Object { $_.Id -eq "ue-tools" })[0].FunctionName) -eq "Invoke-UETools") "ue-tools maps to Invoke-UETools"
  if ($artToolsAvailable) {
    Assert-Condition "case1 includes art-tools" ($definitionIds -contains "art-tools") "art-tools definition found"
    Assert-Condition "case1 art-tools function mapping" ((@($definitions | Where-Object { $_.Id -eq "art-tools" })[0].FunctionName) -eq "Invoke-ArtTools") "art-tools maps to Invoke-ArtTools"
  }
  else {
    Assert-Condition "case1 omits art-tools without script" (-not ($definitionIds -contains "art-tools")) "art-tools definition omitted"
  }
  if ($docsToolsAvailable) {
    Assert-Condition "case1 includes docs-tools" ($definitionIds -contains "docs-tools") "docs-tools definition found"
    Assert-Condition "case1 docs-tools function mapping" ((@($definitions | Where-Object { $_.Id -eq "docs-tools" })[0].FunctionName) -eq "Invoke-DocsTools") "docs-tools maps to Invoke-DocsTools"
  }
  else {
    Assert-Condition "case1 omits docs-tools without script" (-not ($definitionIds -contains "docs-tools")) "docs-tools definition omitted"
  }
  if ($codexToolsAvailable) {
    Assert-Condition "case1 includes codex-tools" ($definitionIds -contains "codex-tools") "codex-tools definition found"
    Assert-Condition "case1 codex-tools function mapping" ((@($definitions | Where-Object { $_.Id -eq "codex-tools" })[0].FunctionName) -eq "Invoke-CodexTools") "codex-tools maps to Invoke-CodexTools"
    Assert-Condition "case1 includes codex-prompt" ($definitionIds -contains "codex-prompt") "codex-prompt definition found"
    Assert-Condition "case1 codex-prompt function mapping" ((@($definitions | Where-Object { $_.Id -eq "codex-prompt" })[0].FunctionName) -eq "Invoke-CodexPrompt") "codex-prompt maps to Invoke-CodexPrompt"
  }
  else {
    Assert-Condition "case1 omits codex tools without script" (-not ($definitionIds -contains "codex-tools")) "codex tools omitted"
  }

  Step "Case 2: Register-ProjectShellAliases wires aliases in current session"
  Reset-LoadedAliases
  . $helperPath
  $registered = Register-ProjectShellAliases
  Assert-Condition "case2 ue-tools alias maps to function" (((Get-Alias -Name "ue-tools").Definition) -eq "Invoke-UETools") "ue-tools -> Invoke-UETools"
  Assert-Condition "case2 metadata includes ue-tools" ($registered.Aliases -contains "ue-tools") "metadata contains ue-tools"
  if ($artToolsAvailable) {
    Assert-Condition "case2 art-tools alias maps to function" (((Get-Alias -Name "art-tools").Definition) -eq "Invoke-ArtTools") "art-tools -> Invoke-ArtTools"
    Assert-Condition "case2 metadata includes art-tools" ($registered.Aliases -contains "art-tools") "metadata contains art-tools"
  }
  else {
    Assert-Condition "case2 art-tools alias not registered" (-not (Get-Alias -Name "art-tools" -ErrorAction SilentlyContinue)) "art-tools alias absent"
    Assert-Condition "case2 metadata omits art-tools" (-not ($registered.Aliases -contains "art-tools")) "metadata omits art-tools"
  }
  if ($docsToolsAvailable) {
    Assert-Condition "case2 docs-tools alias maps to function" (((Get-Alias -Name "docs-tools").Definition) -eq "Invoke-DocsTools") "docs-tools -> Invoke-DocsTools"
    Assert-Condition "case2 metadata includes docs-tools" ($registered.Aliases -contains "docs-tools") "metadata contains docs-tools"
  }
  else {
    Assert-Condition "case2 docs-tools alias not registered" (-not (Get-Alias -Name "docs-tools" -ErrorAction SilentlyContinue)) "docs-tools alias absent"
    Assert-Condition "case2 metadata omits docs-tools" (-not ($registered.Aliases -contains "docs-tools")) "metadata omits docs-tools"
  }
  if ($codexToolsAvailable) {
    Assert-Condition "case2 codex-tools alias maps to function" (((Get-Alias -Name "codex-tools").Definition) -eq "Invoke-CodexTools") "codex-tools -> Invoke-CodexTools"
    Assert-Condition "case2 codex-prompt alias maps to function" (((Get-Alias -Name "codex-prompt").Definition) -eq "Invoke-CodexPrompt") "codex-prompt -> Invoke-CodexPrompt"
    Assert-Condition "case2 metadata includes codex-tools" ($registered.Aliases -contains "codex-tools") "metadata contains codex-tools"
    Assert-Condition "case2 metadata includes codex-prompt" ($registered.Aliases -contains "codex-prompt") "metadata contains codex-prompt"
  }
  else {
    Assert-Condition "case2 codex-tools alias not registered" (-not (Get-Alias -Name "codex-tools" -ErrorAction SilentlyContinue)) "codex-tools alias absent"
    Assert-Condition "case2 metadata omits codex-tools" (-not ($registered.Aliases -contains "codex-tools")) "metadata omits codex-tools"
  }

  Step "Case 3: Install writes bootstrap snippet (no giant function strings)"
  $profileNew = New-ScratchPath "profile-new.ps1"
  $installNew = Install-ProjectShellAliases -ProfilePath $profileNew -AliasScriptPath $helperPath
  $markers = Get-ProjectAliasBootstrapMarkers
  $newContent = Get-Content -LiteralPath $profileNew -Raw

  Assert-Condition "case3 profile created" (Test-Path -LiteralPath $profileNew) "profile file exists"
  Assert-TextContains "case3 start marker present" $newContent $markers.StartMarker
  Assert-TextContains "case3 end marker present" $newContent $markers.EndMarker
  Assert-Condition "case3 one start marker" ((Count-Matches $newContent ([regex]::Escape($markers.StartMarker))) -eq 1) "start marker count=1"
  Assert-Condition "case3 one end marker" ((Count-Matches $newContent ([regex]::Escape($markers.EndMarker))) -eq 1) "end marker count=1"
  Assert-TextContains "case3 snippet registers aliases" $newContent "Register-ProjectShellAliases"
  Assert-TextContains "case3 snippet references helper path" $newContent $helperPath
  Assert-TextNotContains "case3 no inline ue function definition" $newContent "function Invoke-UETools"
  Assert-TextNotContains "case3 no inline art function definition" $newContent "function Invoke-ArtTools"
  Assert-TextNotContains "case3 no inline codex tools function definition" $newContent "function Invoke-CodexTools"
  Assert-TextNotContains "case3 no inline codex prompt function definition" $newContent "function Invoke-CodexPrompt"
  Assert-Condition "case3 metadata includes ue-tools" ($installNew.Aliases -contains "ue-tools") "metadata contains ue-tools"
  if ($artToolsAvailable) {
    Assert-Condition "case3 metadata includes art-tools" ($installNew.Aliases -contains "art-tools") "metadata contains art-tools"
  }
  else {
    Assert-Condition "case3 metadata omits art-tools" (-not ($installNew.Aliases -contains "art-tools")) "metadata omits art-tools"
  }
  if ($docsToolsAvailable) {
    Assert-Condition "case3 metadata includes docs-tools" ($installNew.Aliases -contains "docs-tools") "metadata contains docs-tools"
  }
  else {
    Assert-Condition "case3 metadata omits docs-tools" (-not ($installNew.Aliases -contains "docs-tools")) "metadata omits docs-tools"
  }
  if ($codexToolsAvailable) {
    Assert-Condition "case3 metadata includes codex-tools" ($installNew.Aliases -contains "codex-tools") "metadata contains codex-tools"
    Assert-Condition "case3 metadata includes codex-prompt" ($installNew.Aliases -contains "codex-prompt") "metadata contains codex-prompt"
  }
  else {
    Assert-Condition "case3 metadata omits codex-tools" (-not ($installNew.Aliases -contains "codex-tools")) "metadata omits codex-tools"
  }

  Step "Case 4: Installer is idempotent"
  $beforeSecondInstall = Get-Content -LiteralPath $profileNew -Raw
  $null = Install-ProjectShellAliases -ProfilePath $profileNew -AliasScriptPath $helperPath
  $afterSecondInstall = Get-Content -LiteralPath $profileNew -Raw
  Assert-Condition "case4 profile unchanged on second install" ($beforeSecondInstall -ceq $afterSecondInstall) "profile content is unchanged"

  Step "Case 5: Legacy marker migration preserves non-managed profile content"
  $profileLegacy = New-ScratchPath "profile-legacy.ps1"
  $legacyBlocks = New-Object System.Collections.Generic.List[string]
  $legacyBlockNames = New-Object System.Collections.Generic.List[string]
  $legacyCounter = 0
  foreach ($legacyMarker in @(Get-ProjectAliasLegacyMarkers)) {
    $legacyCounter++
    $legacyBody = "legacy-managed-block-$legacyCounter"
    $legacyBlocks.Add($legacyMarker.StartMarker) | Out-Null
    $legacyBlocks.Add("function TestLegacyBlock$legacyCounter { throw '$legacyBody' }") | Out-Null
    $legacyBlocks.Add($legacyMarker.EndMarker) | Out-Null
    $legacyBlockNames.Add($legacyBody) | Out-Null
  }

  $legacyContent = @(
    "KEEP_TOP = '1'"
    "function KeepTop { return 'top-ok' }"
  ) + @($legacyBlocks) + @(
    "KEEP_BOTTOM = '1'"
    "function KeepBottom { return 'bottom-ok' }"
  ) -join "`r`n"
  Write-TextFileLf -Path $profileLegacy -Content $legacyContent

  $null = Install-ProjectShellAliases -ProfilePath $profileLegacy -AliasScriptPath $helperPath
  $migratedContent = Get-Content -LiteralPath $profileLegacy -Raw
  $outsideAfter = Remove-ManagedBlock -Text $migratedContent -StartMarker $markers.StartMarker -EndMarker $markers.EndMarker

  foreach ($legacyMarker in @(Get-ProjectAliasLegacyMarkers)) {
    Assert-TextNotContains "case5 removes legacy marker $($legacyMarker.StartMarker)" $migratedContent $legacyMarker.StartMarker
    Assert-TextNotContains "case5 removes legacy marker $($legacyMarker.EndMarker)" $migratedContent $legacyMarker.EndMarker
  }
  foreach ($legacyBody in @($legacyBlockNames)) {
    Assert-TextNotContains "case5 removes legacy body $legacyBody" $migratedContent $legacyBody
  }
  Assert-TextContains "case5 top preserved" $outsideAfter "KEEP_TOP = '1'"
  Assert-TextContains "case5 bottom preserved" $outsideAfter "KEEP_BOTTOM = '1'"

  Step "Case 6: ue-tools help works after profile bootstrap"
  Reset-LoadedAliases
  . $profileNew
  $helpDirect = @(& { Invoke-UETools help } 2>&1 6>&1)
  $helpAlias = @(& { ue-tools help } 2>&1 6>&1)
  $helpDirectText = ($helpDirect | ForEach-Object { "$_" }) -join "`n"
  $helpAliasText = ($helpAlias | ForEach-Object { "$_" }) -join "`n"
  Assert-TextContains "case6 direct help output" $helpDirectText "ue-tools <command> [options]"
  Assert-TextContains "case6 alias help output" $helpAliasText "Commands:"

  Step "Case 7: art-tools help works after profile bootstrap"
  if ($artToolsAvailable) {
    $artHelp = @(& { art-tools --help } 2>&1 6>&1)
    $artHelpText = ($artHelp | ForEach-Object { "$_" }) -join "`n"
    Assert-TextContains "case7 help line" $artHelpText "Art tools wrapper for ArtSource helpers."
    Assert-TextContains "case7 usage line" $artHelpText "art-tools [New-ArtSourcePath.ps1 options]"
  }
  else {
    Skip "case7 art-tools help" "New-ArtSourcePath.ps1 is not present in this repo."
  }

  Step "Case 7b: docs-tools help works after profile bootstrap"
  if ($docsToolsAvailable) {
    $docsToolsHelp = @(& { docs-tools help } 2>&1 6>&1)
    $docsToolsHelpText = ($docsToolsHelp | ForEach-Object { "$_" }) -join "`n"
    Assert-TextContains "case7b docs-tools help line" $docsToolsHelpText "new-page, create-page"
    Assert-TextContains "case7b docs-tools install bridge line" $docsToolsHelpText "install-bridge"
  }
  else {
    Skip "case7b docs-tools help" "DocsTools.ps1 is not present in this repo."
  }

  Step "Case 7c: codex-tools help works after profile bootstrap"
  if ($codexToolsAvailable) {
    $codexToolsHelp = @(& { codex-tools help } 2>&1 6>&1)
    $codexPromptHelp = @(& { codex-prompt --help } 2>&1 6>&1)
    $codexToolsHelpText = ($codexToolsHelp | ForEach-Object { "$_" }) -join "`n"
    $codexPromptHelpText = ($codexPromptHelp | ForEach-Object { "$_" }) -join "`n"
    Assert-TextContains "case7c codex-tools help line" $codexToolsHelpText "codex-tools <command> [options]"
    Assert-TextContains "case7c codex-prompt usage line" $codexPromptHelpText "codex-prompt [-Task <text>] [-IncludePrivate] [-CopyToClipboard]"
  }
  else {
    Skip "case7c codex tools help" "Get-CodexStartupPrompt.ps1 is not present in this repo."
  }

  Step "Case 8: ue-tools unknown subcommand gives actionable error"
  $unknownThrew = $false
  $unknownMsg = ""
  try {
    Invoke-UETools banana | Out-Null
  }
  catch {
    $unknownThrew = $true
    $unknownMsg = $_.Exception.Message
  }
  Assert-Condition "case8 unknown command throws" $unknownThrew "unknown command threw as expected"
  Assert-TextContains "case8 unknown message" $unknownMsg "Unknown ue-tools command 'banana'"

  Step "Case 9: ue-tools build errors clearly outside a git repo"
  $nonRepoDir = Join-Path ([System.IO.Path]::GetTempPath()) ("uetools-nongit-{0}" -f $stamp)
  New-Item -ItemType Directory -Force -Path $nonRepoDir | Out-Null
  $script:ExternalTempDirs.Add($nonRepoDir) | Out-Null

  Push-Location $nonRepoDir
  try {
    Reset-LoadedAliases
    . $profileNew
    $threw = $false
    $msg = ""
    try {
      Invoke-UETools build -NoBuild | Out-Null
    }
    catch {
      $threw = $true
      $msg = $_.Exception.Message
    }
    Assert-Condition "case9 throws outside git repo" $threw "build threw as expected"
    Assert-TextContains "case9 error message" $msg "inside a git repository"
  }
  finally {
    Pop-Location
  }

  Step "Case 10: ue-tools build forwards -Force and passthrough arguments"
  $forwardRepo = New-ScratchPath "forwarding-repo"
  $forwardUnrealDir = Join-Path $forwardRepo "Scripts\Unreal"
  New-Item -ItemType Directory -Force -Path $forwardUnrealDir | Out-Null
  & git -C $forwardRepo init | Out-Null

  $forwardScript = Join-Path $forwardUnrealDir "UnrealSync.ps1"
  $forwardResult = Join-Path $forwardUnrealDir "last-run.json"
  $forwardScriptBody = @'
[CmdletBinding()]
param(
  [switch]$Force,
  [switch]$NoBuild,
  [switch]$NoRegen,
  [switch]$CleanGenerated,
  [switch]$DryRun,
  [string]$RepoRoot,
  [string]$Config = "Development",
  [string]$Platform = "Win64"
)

$outPath = Join-Path (Split-Path -Parent $PSCommandPath) "last-run.json"
[pscustomobject]@{
  Force = [bool]$Force
  NoBuild = [bool]$NoBuild
  NoRegen = [bool]$NoRegen
  CleanGenerated = [bool]$CleanGenerated
  DryRun = [bool]$DryRun
  RepoRoot = $RepoRoot
  Config = $Config
  Platform = $Platform
} | ConvertTo-Json -Compress | Set-Content -LiteralPath $outPath -Encoding UTF8
'@
  Write-TextFileLf -Path $forwardScript -Content $forwardScriptBody

  Push-Location $forwardRepo
  try {
    Reset-LoadedAliases
    . $profileNew

    Invoke-UETools build -CleanGenerated -NoBuild -NoRegen -DryRun -Config Debug -Platform Win64 | Out-Null
    Assert-Condition "case10 build wrote result file" (Test-Path -LiteralPath $forwardResult) "last-run.json written"
    $payload = Get-Content -LiteralPath $forwardResult -Raw | ConvertFrom-Json
    Assert-Condition "case10 Force forwarded" ([bool]$payload.Force) "Force=true"
    Assert-Condition "case10 NoBuild forwarded" ([bool]$payload.NoBuild) "NoBuild=true"
    Assert-Condition "case10 NoRegen forwarded" ([bool]$payload.NoRegen) "NoRegen=true"
    Assert-Condition "case10 CleanGenerated forwarded" ([bool]$payload.CleanGenerated) "CleanGenerated=true"
    Assert-Condition "case10 DryRun forwarded" ([bool]$payload.DryRun) "DryRun=true"
    $expectedForwardRepo = [System.IO.Path]::GetFullPath($forwardRepo)
    $actualForwardRepo = [System.IO.Path]::GetFullPath([string]$payload.RepoRoot)
    Assert-Condition "case10 RepoRoot forwarded" ($actualForwardRepo -eq $expectedForwardRepo) "RepoRoot=$expectedForwardRepo" "RepoRoot=$actualForwardRepo"
    Assert-Condition "case10 Config forwarded" ($payload.Config -eq "Debug") "Config=Debug"
    Assert-Condition "case10 Platform forwarded" ($payload.Platform -eq "Win64") "Platform=Win64"
  }
  finally {
    Pop-Location
  }

  Step "Case 11: art-tools errors clearly when target script is missing"
  $missingArtRepo = New-ScratchPath "missing-art-repo"
  New-Item -ItemType Directory -Force -Path $missingArtRepo | Out-Null
  & git -C $missingArtRepo init | Out-Null

  Push-Location $missingArtRepo
  try {
    Reset-LoadedAliases
    . $profileNew

    $threw = $false
    $msg = ""
    try {
      Invoke-ArtTools | Out-Null
    }
    catch {
      $threw = $true
      $msg = $_.Exception.Message
    }

    Assert-Condition "case11 missing script throws" $threw "art-tools threw as expected"
    Assert-TextContains "case11 missing script message" $msg "ArtSource path script not found"
  }
  finally {
    Pop-Location
  }

  Step "Case 12: Compatibility shim still loads main helpers"
  $compatPath = Join-Path $repoRoot "Scripts\Unreal\UESyncShellAliases.ps1"
  Assert-Condition "case12 shim file exists" (Test-Path -LiteralPath $compatPath) "compat shim present"
  Reset-LoadedAliases
  . $compatPath
  $registeredCompat = Register-ProjectShellAliases
  Assert-Condition "case12 shim registration includes ue-tools" ($registeredCompat.Aliases -contains "ue-tools") "shim exposes Register-ProjectShellAliases"
  if ($artToolsAvailable) {
    Assert-Condition "case12 shim registration includes art-tools" ($registeredCompat.Aliases -contains "art-tools") "shim exposes Register-ProjectShellAliases"
  }
  else {
    Assert-Condition "case12 shim omits art-tools when unavailable" (-not ($registeredCompat.Aliases -contains "art-tools")) "compat shim omits art-tools"
  }
  if ($docsToolsAvailable) {
    Assert-Condition "case12 shim registration includes docs-tools" ($registeredCompat.Aliases -contains "docs-tools") "shim exposes docs-tools"
  }
  else {
    Assert-Condition "case12 shim omits docs-tools when unavailable" (-not ($registeredCompat.Aliases -contains "docs-tools")) "compat shim omits docs-tools"
  }

  Step "Case 13: Legacy install wrapper remains available"
  $profileCompat = New-ScratchPath "profile-compat.ps1"
  $legacyInstall = Install-UEToolsShellAliases -ProfilePath $profileCompat -AliasScriptPath $helperPath
  Assert-Condition "case13 wrapper returns ue-tools alias" ($legacyInstall.Aliases -contains "ue-tools") "Install-UEToolsShellAliases returns ue-tools metadata"
  Assert-Condition "case13 wrapper preserves function name" ($legacyInstall.FunctionName -eq "Invoke-UETools") "FunctionName=Invoke-UETools"

  Step "Case 14: Docs alias install wrapper remains available"
  $profileDocs = New-ScratchPath "profile-docs.ps1"
  $docsInstall = Install-DocsToolsShellAliases -ProfilePath $profileDocs -AliasScriptPath $helperPath
  if ($docsToolsAvailable) {
    Assert-Condition "case14 wrapper returns docs-tools alias" ($docsInstall.Aliases -contains "docs-tools") "Install-DocsToolsShellAliases returns docs-tools metadata"
    Assert-Condition "case14 wrapper preserves function name" ($docsInstall.FunctionName -eq "Invoke-DocsTools") "FunctionName=Invoke-DocsTools"
  }
  else {
    Assert-Condition "case14 wrapper omits docs-tools when unavailable" ($docsInstall.Aliases.Count -eq 0) "no docs-tools aliases returned"
  }

  Step "Case 15: Codex alias install wrapper remains available"
  $profileCodex = New-ScratchPath "profile-codex.ps1"
  $codexInstall = Install-CodexToolsShellAliases -ProfilePath $profileCodex -AliasScriptPath $helperPath
  if ($codexToolsAvailable) {
    Assert-Condition "case15 wrapper returns codex-tools alias" ($codexInstall.Aliases -contains "codex-tools") "Install-CodexToolsShellAliases returns codex-tools metadata"
    Assert-Condition "case15 wrapper preserves function name" ($codexInstall.FunctionName -eq "Invoke-CodexTools") "FunctionName=Invoke-CodexTools"
  }
  else {
    Assert-Condition "case15 wrapper omits codex-tools when unavailable" ($codexInstall.Aliases.Count -eq 0) "no codex-tools aliases returned"
  }

  Step "Summary"
  Write-Log ("PASS={0} FAIL={1} WARN={2} SKIP={3}" -f $script:PassCount, $script:FailCount, $script:WarnCount, $script:SkipCount) Cyan
  if ($script:FailCount -eq 0) {
    Write-Log "Project shell alias tests passed." Green
  }
  else {
    Write-Log "Project shell alias tests failed." Red
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
  Restore-State
  Write-Log ""
  Write-Log "Log saved: $logPath" Cyan
}
