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
$testHarnessPath = Join-Path $repoRoot "Scripts\Tests\TestHarness.ps1"
if (-not (Test-Path -LiteralPath $testHarnessPath -PathType Leaf)) {
  throw "Test harness not found: $testHarnessPath"
}
. $testHarnessPath

$script:PassCount = 0
$script:FailCount = 0
$script:WarnCount = 0
$script:SkipCount = 0
$script:CleanupRan = $false
$script:ExternalTempDirs = New-Object System.Collections.Generic.List[string]
Initialize-TestHarness -LogPath $logPath -FailFast:$FailFast

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
  Remove-Item -LiteralPath Function:\Invoke-AITools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Function:\Invoke-AIPrompt -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Function:\Invoke-UESync -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Function:\Invoke-CozyUESync -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\ue-tools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\art-tools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\docs-tools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\ai-tools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\ai-prompt -ErrorAction SilentlyContinue
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
  $bootstrapPath = New-ScratchPath "UEToolsBootstrap.ps1"
  . $helperPath
  $artToolsAvailable = Test-ProjectAliasRepoScriptAvailable -RelativePath "New-ArtSourcePath.ps1"
  $docsToolsAvailable = Test-ProjectAliasRepoScriptAvailable -RelativePath "..\Docs\DocsTools.ps1"
  $aiToolsAvailable = Test-ProjectAliasRepoScriptAvailable -RelativePath "..\AI\Get-AIStartupPrompt.ps1"

  Step "Case 1: Alias definition table is present and complete"
  $definitions = @(Get-ProjectAliasDefinitions)
  $definitionIds = @($definitions | ForEach-Object { $_.Id })
  $expectedAliasCount = 1
  if ($artToolsAvailable) { $expectedAliasCount++ }
  if ($docsToolsAvailable) { $expectedAliasCount++ }
  if ($aiToolsAvailable) { $expectedAliasCount += 2 }
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
  if ($aiToolsAvailable) {
    Assert-Condition "case1 includes ai-tools" ($definitionIds -contains "ai-tools") "ai-tools definition found"
    Assert-Condition "case1 ai-tools function mapping" ((@($definitions | Where-Object { $_.Id -eq "ai-tools" })[0].FunctionName) -eq "Invoke-AITools") "ai-tools maps to Invoke-AITools"
    Assert-Condition "case1 includes ai-prompt" ($definitionIds -contains "ai-prompt") "ai-prompt definition found"
    Assert-Condition "case1 ai-prompt function mapping" ((@($definitions | Where-Object { $_.Id -eq "ai-prompt" })[0].FunctionName) -eq "Invoke-AIPrompt") "ai-prompt maps to Invoke-AIPrompt"
  }
  else {
    Assert-Condition "case1 omits ai tools without script" (-not ($definitionIds -contains "ai-tools")) "ai tools omitted"
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
  if ($aiToolsAvailable) {
    Assert-Condition "case2 ai-tools alias maps to function" (((Get-Alias -Name "ai-tools").Definition) -eq "Invoke-AITools") "ai-tools -> Invoke-AITools"
    Assert-Condition "case2 ai-prompt alias maps to function" (((Get-Alias -Name "ai-prompt").Definition) -eq "Invoke-AIPrompt") "ai-prompt -> Invoke-AIPrompt"
    Assert-Condition "case2 metadata includes ai-tools" ($registered.Aliases -contains "ai-tools") "metadata contains ai-tools"
    Assert-Condition "case2 metadata includes ai-prompt" ($registered.Aliases -contains "ai-prompt") "metadata contains ai-prompt"
  }
  else {
    Assert-Condition "case2 ai-tools alias not registered" (-not (Get-Alias -Name "ai-tools" -ErrorAction SilentlyContinue)) "ai-tools alias absent"
    Assert-Condition "case2 metadata omits ai-tools" (-not ($registered.Aliases -contains "ai-tools")) "metadata omits ai-tools"
  }

  Step "Case 3: Install writes bootstrap snippet (no giant function strings)"
  $profileNew = New-ScratchPath "profile-new.ps1"
  $installNew = Install-ProjectShellAliases -ProfilePath $profileNew -AliasScriptPath $helperPath -BootstrapScriptPath $bootstrapPath
  $markers = Get-ProjectAliasBootstrapMarkers
  $newContent = Get-Content -LiteralPath $profileNew -Raw
  $bootstrapContent = Get-Content -LiteralPath $bootstrapPath -Raw

  Assert-Condition "case3 profile created" (Test-Path -LiteralPath $profileNew) "profile file exists"
  Assert-Condition "case3 bootstrap created" (Test-Path -LiteralPath $bootstrapPath) "bootstrap file exists"
  Assert-TextContains "case3 start marker present" $newContent $markers.StartMarker
  Assert-TextContains "case3 end marker present" $newContent $markers.EndMarker
  Assert-Condition "case3 one start marker" ((Count-Matches $newContent ([regex]::Escape($markers.StartMarker))) -eq 1) "start marker count=1"
  Assert-Condition "case3 one end marker" ((Count-Matches $newContent ([regex]::Escape($markers.EndMarker))) -eq 1) "end marker count=1"
  Assert-TextContains "case3 snippet references bootstrap path" $newContent $bootstrapPath
  Assert-TextNotContains "case3 snippet does not pin helper path" $newContent $helperPath
  Assert-TextNotContains "case3 no inline ue function definition" $newContent "function Invoke-UETools"
  Assert-TextNotContains "case3 no inline art function definition" $newContent "function Invoke-ArtTools"
  Assert-TextNotContains "case3 no inline ai tools function definition" $newContent "function Invoke-AITools"
  Assert-TextNotContains "case3 no inline ai prompt function definition" $newContent "function Invoke-AIPrompt"
  Assert-TextContains "case3 bootstrap resolves repo at command time" $bootstrapContent "Resolve-UEToolSuiteCurrentRepoRoot"
  Assert-TextContains "case3 bootstrap loads repo helper script" $bootstrapContent "Scripts\Unreal\ProjectShellAliases.ps1"
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
  if ($aiToolsAvailable) {
    Assert-Condition "case3 metadata includes ai-tools" ($installNew.Aliases -contains "ai-tools") "metadata contains ai-tools"
    Assert-Condition "case3 metadata includes ai-prompt" ($installNew.Aliases -contains "ai-prompt") "metadata contains ai-prompt"
  }
  else {
    Assert-Condition "case3 metadata omits ai-tools" (-not ($installNew.Aliases -contains "ai-tools")) "metadata omits ai-tools"
  }

  Step "Case 4: Installer is idempotent"
  $beforeSecondInstall = Get-Content -LiteralPath $profileNew -Raw
  $beforeSecondBootstrapInstall = Get-Content -LiteralPath $bootstrapPath -Raw
  $null = Install-ProjectShellAliases -ProfilePath $profileNew -AliasScriptPath $helperPath -BootstrapScriptPath $bootstrapPath
  $afterSecondInstall = Get-Content -LiteralPath $profileNew -Raw
  $afterSecondBootstrapInstall = Get-Content -LiteralPath $bootstrapPath -Raw
  Assert-Condition "case4 profile unchanged on second install" ($beforeSecondInstall -ceq $afterSecondInstall) "profile content is unchanged"
  Assert-Condition "case4 bootstrap unchanged on second install" ($beforeSecondBootstrapInstall -ceq $afterSecondBootstrapInstall) "bootstrap content is unchanged"

  Step "Case 4b: Bootstrap aliases resolve to the active repo when multiple repos exist"
  Reset-LoadedAliases
  . $bootstrapPath

  $multiRepoA = New-ScratchPath "multi-repo-a"
  $multiRepoB = New-ScratchPath "multi-repo-b"
  New-Item -ItemType Directory -Force -Path (Join-Path $multiRepoA "Scripts\\Unreal") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $multiRepoB "Scripts\\Unreal") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $multiRepoA "Scripts") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $multiRepoB "Scripts") | Out-Null

  Copy-Item -LiteralPath $helperPath -Destination (Join-Path $multiRepoA "Scripts\\Unreal\\ProjectShellAliases.ps1") -Force
  Copy-Item -LiteralPath $helperPath -Destination (Join-Path $multiRepoB "Scripts\\Unreal\\ProjectShellAliases.ps1") -Force

  Write-TextFileLf -Path (Join-Path $multiRepoA "Scripts\\ue-tools.ps1") -Content @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CommandArgs)
Write-Host "UE tools wrapper RepoA"
'@
  Write-TextFileLf -Path (Join-Path $multiRepoB "Scripts\\ue-tools.ps1") -Content @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CommandArgs)
Write-Host "UE tools wrapper RepoB"
'@

  & git -C $multiRepoA init | Out-Null
  & git -C $multiRepoA config user.name "UE Tool Suite Test" | Out-Null
  & git -C $multiRepoA config user.email "ue-tool-suite-test@example.invalid" | Out-Null
  & git -C $multiRepoB init | Out-Null
  & git -C $multiRepoB config user.name "UE Tool Suite Test" | Out-Null
  & git -C $multiRepoB config user.email "ue-tool-suite-test@example.invalid" | Out-Null

  $originalLocation = (Get-Location).Path
  try {
    Set-Location -LiteralPath $multiRepoA
    $resolvedRepoA = Resolve-UEToolSuiteCurrentRepoRoot
    Assert-Condition "case4b repoA root resolution" ([System.IO.Path]::GetFullPath($resolvedRepoA) -eq [System.IO.Path]::GetFullPath($multiRepoA)) "resolved repoA root"
    Assert-Condition "case4b repoA helper path exists" (Test-Path -LiteralPath (Join-Path $resolvedRepoA "Scripts\\Unreal\\ProjectShellAliases.ps1") -PathType Leaf) "repoA helper found"

    Set-Location -LiteralPath $multiRepoB
    $resolvedRepoB = Resolve-UEToolSuiteCurrentRepoRoot
    Assert-Condition "case4b repoB root resolution" ([System.IO.Path]::GetFullPath($resolvedRepoB) -eq [System.IO.Path]::GetFullPath($multiRepoB)) "resolved repoB root"
    Assert-Condition "case4b repoB helper path exists" (Test-Path -LiteralPath (Join-Path $resolvedRepoB "Scripts\\Unreal\\ProjectShellAliases.ps1") -PathType Leaf) "repoB helper found"
  }
  finally {
    Set-Location -LiteralPath $originalLocation
  }

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

  $null = Install-ProjectShellAliases -ProfilePath $profileLegacy -AliasScriptPath $helperPath -BootstrapScriptPath $bootstrapPath
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

  Step "Case 6: ue-tools alias help works after profile bootstrap"
  Reset-LoadedAliases
  . $profileNew
  Assert-Condition "case6 ue-tools alias registered" ($null -ne (Get-Alias -Name "ue-tools" -ErrorAction SilentlyContinue)) "ue-tools alias exists"
  $helpAlias = @(& { ue-tools help } 2>&1 6>&1)
  $helpAliasText = ($helpAlias | ForEach-Object { "$_" }) -join "`n"
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

  Step "Case 7c: ai-tools help works after profile bootstrap"
  if ($aiToolsAvailable) {
    $aiToolsHelp = @(& { ai-tools help } 2>&1 6>&1)
    $aiPromptHelp = @(& { ai-prompt --help } 2>&1 6>&1)
    $aiToolsHelpText = ($aiToolsHelp | ForEach-Object { "$_" }) -join "`n"
    $aiPromptHelpText = ($aiPromptHelp | ForEach-Object { "$_" }) -join "`n"
    Assert-TextContains "case7c ai-tools help line" $aiToolsHelpText "ai-tools <command> [options]"
    Assert-TextContains "case7c ai-prompt usage line" $aiPromptHelpText "ai-prompt [-Task <text>] [-IncludePrivate] [-CopyToClipboard]"
  }
  else {
    Skip "case7c ai tools help" "Get-AIStartupPrompt.ps1 is not present in this repo."
  }

  Step "Case 8: ue-tools unknown subcommand gives actionable error"
  $unknownThrew = $false
  $unknownMsg = ""
  try {
    ue-tools banana | Out-Null
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
      ue-tools build -NoBuild | Out-Null
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
  Copy-Item -LiteralPath $helperPath -Destination (Join-Path $forwardUnrealDir "ProjectShellAliases.ps1") -Force

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

    ue-tools build -CleanGenerated -NoBuild -NoRegen -DryRun -Config Debug -Platform Win64 | Out-Null
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
  $missingArtUnrealDir = Join-Path $missingArtRepo "Scripts\Unreal"
  New-Item -ItemType Directory -Force -Path $missingArtUnrealDir | Out-Null
  & git -C $missingArtRepo init | Out-Null
  Copy-Item -LiteralPath $helperPath -Destination (Join-Path $missingArtUnrealDir "ProjectShellAliases.ps1") -Force

  Push-Location $missingArtRepo
  try {
    Reset-LoadedAliases
    . $profileNew

    $threw = $false
    $msg = ""
    try {
      art-tools | Out-Null
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
  $legacyInstall = Install-UEToolsShellAliases -ProfilePath $profileCompat -AliasScriptPath $helperPath -BootstrapScriptPath $bootstrapPath
  Assert-Condition "case13 wrapper returns ue-tools alias" ($legacyInstall.Aliases -contains "ue-tools") "Install-UEToolsShellAliases returns ue-tools metadata"
  Assert-Condition "case13 wrapper preserves function name" ($legacyInstall.FunctionName -eq "Invoke-UETools") "FunctionName=Invoke-UETools"

  Step "Case 14: Docs alias install wrapper remains available"
  $profileDocs = New-ScratchPath "profile-docs.ps1"
  $docsInstall = Install-DocsToolsShellAliases -ProfilePath $profileDocs -AliasScriptPath $helperPath -BootstrapScriptPath $bootstrapPath
  if ($docsToolsAvailable) {
    Assert-Condition "case14 wrapper returns docs-tools alias" ($docsInstall.Aliases -contains "docs-tools") "Install-DocsToolsShellAliases returns docs-tools metadata"
    Assert-Condition "case14 wrapper preserves function name" ($docsInstall.FunctionName -eq "Invoke-DocsTools") "FunctionName=Invoke-DocsTools"
  }
  else {
    Assert-Condition "case14 wrapper omits docs-tools when unavailable" ($docsInstall.Aliases.Count -eq 0) "no docs-tools aliases returned"
  }

  Step "Case 15: AI alias install wrapper remains available"
  $profileAi = New-ScratchPath "profile-ai.ps1"
  $aiInstall = Install-AIToolsShellAliases -ProfilePath $profileAi -AliasScriptPath $helperPath -BootstrapScriptPath $bootstrapPath
  if ($aiToolsAvailable) {
    Assert-Condition "case15 wrapper returns ai-tools alias" ($aiInstall.Aliases -contains "ai-tools") "Install-AIToolsShellAliases returns ai-tools metadata"
    Assert-Condition "case15 wrapper preserves function name" ($aiInstall.FunctionName -eq "Invoke-AITools") "FunctionName=Invoke-AITools"
  }
  else {
    Assert-Condition "case15 wrapper omits ai-tools when unavailable" ($aiInstall.Aliases.Count -eq 0) "no ai-tools aliases returned"
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
