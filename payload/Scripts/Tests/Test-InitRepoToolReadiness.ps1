[CmdletBinding()]
param(
  [switch]$NoCleanup,
  [switch]$FailFast
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = ((git rev-parse --show-toplevel 2>$null) | Select-Object -First 1).Trim()
if (-not $repoRoot) { throw "Not inside a git repository." }
$payloadRoot = Join-Path $repoRoot "payload"
if (Test-Path -LiteralPath (Join-Path $payloadRoot "Scripts\UETools\UEToolSuite.Init.psm1") -PathType Leaf) {
  $repoRoot = $payloadRoot
}
Set-Location $repoRoot

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$resultsDir = Join-Path $repoRoot "Scripts\Tests\Test-InitRepoToolReadinessResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "InitRepoToolReadiness-$stamp.log"
$testHarnessPath = Join-Path $repoRoot "Scripts\Tests\TestHarness.ps1"
if (-not (Test-Path -LiteralPath $testHarnessPath -PathType Leaf)) {
  throw "Test harness not found: $testHarnessPath"
}
. $testHarnessPath
$initScript = Resolve-UEToolSuiteRuntimeFile -RepoRoot $repoRoot -RelativePath "Scripts\UETools\UEToolSuite.Init.psm1"

$script:PassCount = 0
$script:FailCount = 0
$script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("init repo tool readiness tests " + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $script:TempRoot | Out-Null
Initialize-TestHarness -LogPath $logPath -FailFast:$FailFast

function New-CommandStubToolset {
  param([Parameter(Mandatory)][string]$Name)

  $stubRoot = Join-Path $script:TempRoot $Name
  New-Item -ItemType Directory -Force -Path $stubRoot | Out-Null

  Write-Utf8NoBomFile -Path (Join-Path $stubRoot "git-lfs.cmd") -Content @'
@echo off
>> "%INIT_REPO_TOOL_READINESS_LOG%" echo git-lfs %*
exit /b 0
'@

  Write-Utf8NoBomFile -Path (Join-Path $stubRoot "node.cmd") -Content @'
@echo off
if "%~1"=="--version" (
  echo v20.11.1
  exit /b 0
)
>> "%INIT_REPO_TOOL_READINESS_LOG%" echo node %*
exit /b 0
'@

  Write-Utf8NoBomFile -Path (Join-Path $stubRoot "npm.cmd") -Content @'
@echo off
>> "%INIT_REPO_TOOL_READINESS_LOG%" echo npm cwd=%CD% args=%*
if "%~1"=="install" (
  if not exist node_modules mkdir node_modules
  if not exist node_modules\react mkdir node_modules\react
)
if "%~1"=="ci" (
  if not exist node_modules mkdir node_modules
  if not exist node_modules\react mkdir node_modules\react
)
exit /b 0
'@

  Write-Utf8NoBomFile -Path (Join-Path $stubRoot "code.cmd") -Content @'
@echo off
if "%~1"=="--list-extensions" (
  echo yzhang.markdown-all-in-one
  echo ueproject.docs-tools-bridge
  exit /b 0
)
>> "%INIT_REPO_TOOL_READINESS_LOG%" echo code %*
exit /b 0
'@

  return $stubRoot
}

function New-InitRepoFixture {
  param(
    [Parameter(Mandatory)][string]$Name,
    [switch]$IncludeDocsSite,
    [switch]$IncludeArtSourceTool,
    [switch]$BlueprintOnly,
    [switch]$SkipGitInit
  )

  $target = Join-Path $script:TempRoot $Name
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  if (-not $SkipGitInit) {
    & git -C $target init | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "git init failed for target repo: $target"
    }

    & git -C $target config user.email "init-repo-readiness@example.invalid" | Out-Null
    & git -C $target config user.name "Init Repo Readiness Test" | Out-Null
  }

  if ($BlueprintOnly) {
    Write-Utf8NoBomFile -Path (Join-Path $target "PortableSample.uproject") -Content @'
{
  "FileVersion": 3,
  "EngineAssociation": "5.4",
  "Category": "",
  "Description": ""
}
'@
  }
  else {
    Write-Utf8NoBomFile -Path (Join-Path $target "PortableSample.uproject") -Content @'
{
  "FileVersion": 3,
  "EngineAssociation": "5.4",
  "Category": "",
  "Description": "",
  "Modules": [
    {
      "Name": "PortableSample",
      "Type": "Runtime",
      "LoadingPhase": "Default"
    }
  ]
}
'@
  }

  foreach ($hookName in @("pre-commit", "pre-push", "post-checkout", "post-merge", "post-commit", "post-rewrite")) {
    Write-Utf8NoBomFile -Path (Join-Path $target ".githooks\$hookName") -Content "#!/usr/bin/env bash`nexit 0`n"
  }

  Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\git-hooks\colors.sh") -Content "#!/usr/bin/env bash`n"
  Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\git-hooks\hook-common.sh") -Content "#!/usr/bin/env bash`n"
  Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\git-hooks\Enable-GitHooks.ps1") -Content "Write-Host 'Enable hooks stub'`n"
  Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\git-hooks\Test-Hooks.ps1") -Content "Write-Host 'Hook self-test stub'`n"

  Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\UETools\UEToolSuite.Core.psm1") -Content "function Test-UEToolSuiteCoreStub { `$true }`n"
  Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\UETools\UEToolSuite.Git.psm1") -Content "function Test-GitConflictHelperStub { `$true }`n"
  if ($IncludeArtSourceTool) {
    Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\UETools\UEToolSuite.Art.psm1") -Content "function Test-UEToolSuiteArtStub { `$true }`n"
  }
  Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\UETools\UEToolSuite.AI.psm1") -Content "function Test-UEToolSuiteAIStub { `$true }`n"

  New-Item -ItemType Directory -Force -Path (Join-Path $target "Scripts\Unreal") | Out-Null
  $projectContextSource = Resolve-UEToolSuiteRuntimeFile -RepoRoot $repoRoot -RelativePath "Scripts\Unreal\ProjectContext.ps1"
  Copy-Item `
    -LiteralPath $projectContextSource `
    -Destination (Join-Path $target "Scripts\Unreal\ProjectContext.ps1") `
    -Force

  Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\ue-tools.ps1") -Content @'
[CmdletBinding()]
param(
  [string]$RepoRoot,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CommandArgs
)

$normalizedArgs = New-Object System.Collections.Generic.List[string]
foreach ($arg in @($CommandArgs)) {
  if ($null -eq $arg) { continue }
  $value = [string]$arg
  if ([string]::IsNullOrWhiteSpace($value)) { continue }
  $normalizedArgs.Add($value) | Out-Null
}
$effectiveCommandArgs = @($normalizedArgs.ToArray())
if (-not [string]::IsNullOrWhiteSpace($env:INIT_REPO_TOOL_READINESS_LOG)) {
  Add-Content -LiteralPath $env:INIT_REPO_TOOL_READINESS_LOG -Value ("ue-tools " + ($effectiveCommandArgs -join " ") + " repo=$RepoRoot")
}

if ($effectiveCommandArgs.Count -lt 1) {
  Write-Error "Missing ue-tools command."
  exit 1
}

$command = [string]$effectiveCommandArgs[0]
if ($command -eq "docs") {
  $docsArgs = if ($effectiveCommandArgs.Count -gt 1) { @($effectiveCommandArgs[1..($effectiveCommandArgs.Count - 1)]) } else { @() }
  $coreModulePath = Join-Path $RepoRoot "Scripts\UETools\UEToolSuite.Core.psm1"
  $docsModulePath = Join-Path $RepoRoot "Scripts\UETools\UEToolSuite.Docs.psm1"
  if (-not (Test-Path -LiteralPath $coreModulePath -PathType Leaf)) {
    Write-Error "Docs core module missing: $coreModulePath"
    exit 1
  }
  if (-not (Test-Path -LiteralPath $docsModulePath -PathType Leaf)) {
    Write-Error "Docs module missing: $docsModulePath"
    exit 1
  }

  try {
    Import-Module -Name $coreModulePath -Force -DisableNameChecking | Out-Null
    $docsModule = Import-Module -Name $docsModulePath -Force -DisableNameChecking -PassThru
    $repoResolver = Get-Command -Name "Get-DocsToolsRepoRoot" -Module $docsModule.Name -CommandType Function -ErrorAction SilentlyContinue
    $entrypoint = Get-Command -Name "Invoke-DocsToolsMain" -Module $docsModule.Name -CommandType Function -ErrorAction SilentlyContinue
    if (-not $repoResolver -or -not $entrypoint) {
      throw "Docs module entrypoint is unavailable."
    }

    $resolvedRepoRoot = & $repoResolver.Name -ExplicitRepoRoot $RepoRoot
    & $entrypoint.Name -ResolvedRepoRoot $resolvedRepoRoot -CommandArguments $docsArgs
    exit $LASTEXITCODE
  }
  catch {
    Write-Error $_.Exception.Message
    exit 1
  }
}

Write-Output "ue-tools stub command: $command"
exit 0
'@

  if ($IncludeDocsSite) {
    Write-Utf8NoBomFile -Path (Join-Path $target "website\package.json") -Content @'
{
  "name": "portable-sample-docs",
  "private": true,
  "scripts": {
    "build": "docusaurus build"
  },
  "dependencies": {
    "react": "19.1.1"
  }
}
'@

    Write-Utf8NoBomFile -Path (Join-Path $target "website\package-lock.json") -Content @'
{
  "name": "portable-sample-docs",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": {
      "name": "portable-sample-docs",
      "dependencies": {
        "react": "19.1.1"
      }
    }
  }
}
'@

    Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\UETools\UEToolSuite.Docs.psm1") -Content @'
function Get-DocsToolsRepoRoot {
  param([string]$ExplicitRepoRoot)

  return $ExplicitRepoRoot
}

function Invoke-DocsToolsMain {
  param(
    [string]$ResolvedRepoRoot,
    [string[]]$CommandArguments
  )

  $normalizedArgs = New-Object System.Collections.Generic.List[string]
  foreach ($arg in @($CommandArguments)) {
    if ($null -eq $arg) { continue }
    $value = [string]$arg
    if ([string]::IsNullOrWhiteSpace($value)) { continue }
    $normalizedArgs.Add($value) | Out-Null
  }

  $effectiveCommandArgs = @($normalizedArgs.ToArray())
  $command = if ($effectiveCommandArgs.Count -gt 0) { [string]$effectiveCommandArgs[0] } else { $null }

  if (-not [string]::IsNullOrWhiteSpace($env:INIT_REPO_TOOL_READINESS_LOG)) {
    Add-Content -LiteralPath $env:INIT_REPO_TOOL_READINESS_LOG -Value ("ue-tools docs " + ($effectiveCommandArgs -join " ") + " repo=$ResolvedRepoRoot")
  }

  switch ($command) {
    "migrate-sections" {
      if ([string]$env:INIT_REPO_DOCS_MIGRATE_FAIL -eq "1") {
        throw "Simulated docs migration failure"
      }
      Write-Output "No legacy docs sections require migration."
      return
    }
    "install-bridge" {
      Write-Output "Installed VS Code bridge to: stub"
      Write-Output "Markdown All in One is already installed."
      Write-Output "Reload VS Code windows to activate the bridge."
      return
    }
    "doctor" {
      Write-Output "Repo root: $ResolvedRepoRoot"
      Write-Output "Website root: $ResolvedRepoRoot\website"
      Write-Output "Node installed: True"
      Write-Output "npm installed: True"
      Write-Output "website/node_modules present: True"
      Write-Output "VS Code CLI found: True"
      Write-Output "TOC automation ready: True"
      return
    }
    default {
      throw "Unexpected ue-tools docs command: $($effectiveCommandArgs -join ' ')"
    }
  }
}

Export-ModuleMember -Function Get-DocsToolsRepoRoot, Invoke-DocsToolsMain
'@
  }

  return $target
}

function Invoke-InitRepo {
  param(
    [Parameter(Mandatory)][string]$TargetRepoRoot,
    [Parameter(Mandatory)][string]$StubRoot,
    [Parameter(Mandatory)][string]$CommandLog,
    [bool]$IncludeSkipUnrealSync = $true,
    [string[]]$ExtraArgs = @(),
    [hashtable]$ExtraEnv = @{}
  )

  $previousPath = $env:Path
  $previousCommandLog = $env:INIT_REPO_TOOL_READINESS_LOG
  $previousAuthorName = $env:GIT_AUTHOR_NAME
  $previousAuthorEmail = $env:GIT_AUTHOR_EMAIL
  $previousCommitterName = $env:GIT_COMMITTER_NAME
  $previousCommitterEmail = $env:GIT_COMMITTER_EMAIL
  $previousExtraEnv = @{}
  try {
    $env:Path = "$StubRoot;$env:Path"
    $env:INIT_REPO_TOOL_READINESS_LOG = $CommandLog
    $env:GIT_AUTHOR_NAME = "Init Repo Readiness Test"
    $env:GIT_AUTHOR_EMAIL = "init-repo-readiness@example.invalid"
    $env:GIT_COMMITTER_NAME = "Init Repo Readiness Test"
    $env:GIT_COMMITTER_EMAIL = "init-repo-readiness@example.invalid"
    foreach ($entry in $ExtraEnv.GetEnumerator()) {
      $previousExtraEnv[$entry.Key] = (Get-Item -Path ("Env:{0}" -f $entry.Key) -ErrorAction SilentlyContinue).Value
      Set-Item -Path ("Env:{0}" -f $entry.Key) -Value ([string]$entry.Value)
    }

    $runtimeArgs = @(
      "-RepoRoot", $TargetRepoRoot,
      "-SkipLfsPull",
      "-SkipShellAliases"
    )
    if ($IncludeSkipUnrealSync) {
      $runtimeArgs += "-SkipUnrealSync"
    }
    $runtimeArgs += @($ExtraArgs)
    $params = @{}
    $i = 0
    while ($i -lt $runtimeArgs.Count) {
      $token = [string]$runtimeArgs[$i]
      $normalized = $token.Trim().ToLowerInvariant()
      switch ($normalized) {
        '-skiplfspull' { $params.SkipLfsPull = $true; $i += 1; continue }
        '-skipunrealsync' { $params.SkipUnrealSync = $true; $i += 1; continue }
        '-skipshellaliases' { $params.SkipShellAliases = $true; $i += 1; continue }
        '-skipoptionaltoolsetup' { $params.SkipOptionalToolSetup = $true; $i += 1; continue }
        '-skipartsourcetools' { $params.SkipArtSourceTools = $true; $i += 1; continue }
        '-skipdocssetup' { $params.SkipDocsSetup = $true; $i += 1; continue }
        '-skipdocssectionmigration' { $params.SkipDocsSectionMigration = $true; $i += 1; continue }
        '-skipdocsnpminstall' { $params.SkipDocsNpmInstall = $true; $i += 1; continue }
        '-forcedocsnpminstall' { $params.ForceDocsNpmInstall = $true; $i += 1; continue }
        '-skipdocsbridgeinstall' { $params.SkipDocsBridgeInstall = $true; $i += 1; continue }
        '-noninteractive' { $params.NonInteractive = $true; $i += 1; continue }
        '-skipignoreduntrack' { $params.SkipIgnoredUntrack = $true; $i += 1; continue }
        '-nobuild' { $params.NoBuild = $true; $i += 1; continue }
        '-noregen' { $params.NoRegen = $true; $i += 1; continue }
        '-reporoot' { if (($i + 1) -ge $runtimeArgs.Count) { throw 'Missing value for -RepoRoot' }; $params.RepoRoot = [string]$runtimeArgs[$i + 1]; $i += 2; continue }
        '-uprojectpath' { if (($i + 1) -ge $runtimeArgs.Count) { throw 'Missing value for -UProjectPath' }; $params.UProjectPath = [string]$runtimeArgs[$i + 1]; $i += 2; continue }
        '-workspacepath' { if (($i + 1) -ge $runtimeArgs.Count) { throw 'Missing value for -WorkspacePath' }; $params.WorkspacePath = [string]$runtimeArgs[$i + 1]; $i += 2; continue }
        '-config' { if (($i + 1) -ge $runtimeArgs.Count) { throw 'Missing value for -Config' }; $params.Config = [string]$runtimeArgs[$i + 1]; $i += 2; continue }
        '-platform' { if (($i + 1) -ge $runtimeArgs.Count) { throw 'Missing value for -Platform' }; $params.Platform = [string]$runtimeArgs[$i + 1]; $i += 2; continue }
        default { throw "Unknown init option '$token'." }
      }
    }

    Write-Log ">> invoke init module entrypoint" DarkGray
    $previousNoAutorun = $env:UE_TOOLS_INIT_RUNTIME_NO_AUTORUN
    $env:UE_TOOLS_INIT_RUNTIME_NO_AUTORUN = "1"
    $transcriptPath = Join-Path $script:TempRoot ("init-runtime-transcript-" + [Guid]::NewGuid().ToString("N") + ".log")
    Push-Location $TargetRepoRoot
    try {
      Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
      $runtimeModule = Import-Module -Name $initScript -Force -DisableNameChecking -PassThru
      $entrypoint = Get-Command -Name 'Invoke-UEToolSuiteInitRuntime' -Module $runtimeModule.Name -CommandType Function -ErrorAction SilentlyContinue
      if (-not $entrypoint) {
        $entrypoint = Get-Command -Name 'Invoke-UEToolSuiteInitRuntime' -CommandType Function -ErrorAction Stop
      }

      $output = @(& $entrypoint.Name @params 2>&1)
      $exitCode = 0
    }
    catch {
      $output = @("Exception: $($_.Exception.Message)")
      $exitCode = 1
    }
    finally {
      try { Stop-Transcript | Out-Null } catch { }
      Pop-Location
      if ($null -eq $previousNoAutorun) {
        Remove-Item Env:UE_TOOLS_INIT_RUNTIME_NO_AUTORUN -ErrorAction SilentlyContinue
      }
      else {
        $env:UE_TOOLS_INIT_RUNTIME_NO_AUTORUN = $previousNoAutorun
      }
    }

    if (Test-Path -LiteralPath $transcriptPath) {
      try {
        $transcriptLines = Get-Content -LiteralPath $transcriptPath -ErrorAction Stop |
          Where-Object {
            $_ -match '^\[Init\]' -or
            $_ -match 'Tool readiness summary:' -or
            $_ -match '^\s+\[(OK|SKIP|WARN)\]' -or
            $_ -match '^fatal:'
          }
        $output = @($output + $transcriptLines)
      }
      finally {
        Remove-Item -LiteralPath $transcriptPath -Force -ErrorAction SilentlyContinue
      }
    }

    $normalizedOutput = @()
    foreach ($line in $output) {
      $text = Remove-AnsiEscapeSequences "$line"
      $normalizedOutput += $text
      if (-not [string]::IsNullOrWhiteSpace($text)) {
        Write-Log ("   " + $text.TrimEnd()) DarkGray
      }
    }

    return [pscustomobject]@{
      ExitCode = $exitCode
      OutputText = ($normalizedOutput | ForEach-Object { "$_" }) -join "`n"
    }
  }
  finally {
    $env:Path = $previousPath
    if ($null -eq $previousCommandLog) {
      Remove-Item Env:INIT_REPO_TOOL_READINESS_LOG -ErrorAction SilentlyContinue
    }
    else {
      $env:INIT_REPO_TOOL_READINESS_LOG = $previousCommandLog
    }

    if ($null -eq $previousAuthorName) { Remove-Item Env:GIT_AUTHOR_NAME -ErrorAction SilentlyContinue } else { $env:GIT_AUTHOR_NAME = $previousAuthorName }
    if ($null -eq $previousAuthorEmail) { Remove-Item Env:GIT_AUTHOR_EMAIL -ErrorAction SilentlyContinue } else { $env:GIT_AUTHOR_EMAIL = $previousAuthorEmail }
    if ($null -eq $previousCommitterName) { Remove-Item Env:GIT_COMMITTER_NAME -ErrorAction SilentlyContinue } else { $env:GIT_COMMITTER_NAME = $previousCommitterName }
    if ($null -eq $previousCommitterEmail) { Remove-Item Env:GIT_COMMITTER_EMAIL -ErrorAction SilentlyContinue } else { $env:GIT_COMMITTER_EMAIL = $previousCommitterEmail }
    foreach ($entry in $ExtraEnv.GetEnumerator()) {
      $key = [string]$entry.Key
      if ($previousExtraEnv.ContainsKey($key) -and $null -ne $previousExtraEnv[$key]) {
        Set-Item -Path ("Env:{0}" -f $key) -Value ([string]$previousExtraEnv[$key])
      }
      else {
        Remove-Item -Path ("Env:{0}" -f $key) -ErrorAction SilentlyContinue
      }
    }
  }
}

try {
  Step "Init repo tool readiness tests ($stamp)"
  Write-Log "Repo: $repoRoot" Cyan
  Write-Log "Log : $logPath" Cyan
  Write-Log "Temp: $script:TempRoot" Cyan

  $stubRoot = New-CommandStubToolset -Name "tool-stubs"

  Step "Case 1: init prepares installed docs and ArtSource tools"
  $commandLog = Join-Path $script:TempRoot "case1-commands.log"
  Write-Utf8NoBomFile -Path $commandLog -Content ""
  $targetRepo = New-InitRepoFixture -Name "target with docs" -IncludeDocsSite -IncludeArtSourceTool
  $result = Invoke-InitRepo -TargetRepoRoot $targetRepo -StubRoot $stubRoot -CommandLog $commandLog
  $commandLogText = Get-Content -LiteralPath $commandLog -Raw

  Assert-Condition "case1 init exits cleanly" ($result.ExitCode -eq 0) "exit=0" "exit=$($result.ExitCode)"
  Assert-TextContains "case1 docs migration invoked" $commandLogText "ue-tools docs migrate-sections"
  Assert-TextContains "case1 npm install invoked" $commandLogText "npm cwd="
  Assert-TextContains "case1 npm ci args" $commandLogText "args=ci"
  Assert-TextContains "case1 bridge install invoked" $commandLogText "ue-tools docs install-bridge"
  Assert-TextContains "case1 docs doctor invoked" $commandLogText "ue-tools docs doctor"
  Assert-Condition "case1 node_modules created" (Test-Path -LiteralPath (Join-Path $targetRepo "website\node_modules")) "website/node_modules created" "website/node_modules missing"
  Assert-TextContains "case1 summary shown" $result.OutputText "Tool readiness summary:"
  Assert-TextContains "case1 git-lfs ready" $result.OutputText "[OK] git-lfs"
  Assert-TextContains "case1 node ready" $result.OutputText "[OK] node/npm"
  Assert-TextContains "case1 docs migration ready" $result.OutputText "[OK] docs section migration"
  Assert-TextContains "case1 docs deps ready" $result.OutputText "[OK] docs dependencies"
  Assert-TextContains "case1 docs bridge ready" $result.OutputText "[OK] docs VS Code bridge"
  Assert-TextContains "case1 docs tools ready" $result.OutputText "[OK] ue-tools docs"
  Assert-TextContains "case1 art tools ready" $result.OutputText "[OK] ue-tools art"
  foreach ($relativePath in @("ArtSource\_Template\Source", "ArtSource\_Template\Textures", "ArtSource\_Template\Exports")) {
    Assert-Condition "case1 created $relativePath" (Test-Path -LiteralPath (Join-Path $targetRepo $relativePath) -PathType Container) "$relativePath present" "$relativePath missing"
  }
  Assert-TextContains "case1 aliases skipped" $result.OutputText "[SKIP] PowerShell aliases"
  Assert-TextContains "case1 ue-tools skipped" $result.OutputText "[SKIP] ue-tools"

  Step "Case 1b: init re-syncs docs dependencies when node_modules drifts"
  $case1bLog = Join-Path $script:TempRoot "case1b-commands.log"
  Write-Utf8NoBomFile -Path $case1bLog -Content ""
  $case1bNodeModulePath = Join-Path $targetRepo "website\node_modules\react"
  if (Test-Path -LiteralPath $case1bNodeModulePath) {
    Remove-Item -LiteralPath $case1bNodeModulePath -Recurse -Force
  }
  $case1bStatePath = Join-Path $targetRepo "website\node_modules\.ue-tools-docs-deps-state.json"
  Write-Utf8NoBomFile -Path $case1bStatePath -Content '{"dependencyHash":"stale-hash","requiredDependencies":["react"],"installCommand":"npm ci","packageLockPresent":true,"updatedUtc":"2000-01-01T00:00:00.0000000Z"}'
  $case1bResult = Invoke-InitRepo `
    -TargetRepoRoot $targetRepo `
    -StubRoot $stubRoot `
    -CommandLog $case1bLog `
    -ExtraArgs @("-NonInteractive")
  $case1bLogText = Get-Content -LiteralPath $case1bLog -Raw
  Assert-Condition "case1b init exits cleanly" ($case1bResult.ExitCode -eq 0) "exit=0" "exit=$($case1bResult.ExitCode)"
  Assert-TextContains "case1b npm re-sync invoked" $case1bLogText "args=ci"
  Assert-TextContains "case1b output explains dependency drift" $case1bResult.OutputText "Docs dependency install reason:"
  Assert-Condition "case1b state file rewritten" (Test-Path -LiteralPath $case1bStatePath -PathType Leaf) "state file present" "state file missing"
  $case1bState = Get-Content -LiteralPath $case1bStatePath -Raw | ConvertFrom-Json
  Assert-Condition "case1b state hash updated" ([string]$case1bState.dependencyHash -ne "stale-hash") "dependencyHash refreshed" "dependencyHash remained stale"

  Step "Case 2: init skips missing docs but creates the default ArtSource layout"
  $commandLog2 = Join-Path $script:TempRoot "case2-commands.log"
  Write-Utf8NoBomFile -Path $commandLog2 -Content ""
  $targetRepoWithoutOptionalTools = New-InitRepoFixture -Name "target without optional tools"
  $result2 = Invoke-InitRepo -TargetRepoRoot $targetRepoWithoutOptionalTools -StubRoot $stubRoot -CommandLog $commandLog2
  Assert-Condition "case2 init exits cleanly" ($result2.ExitCode -eq 0) "exit=0" "exit=$($result2.ExitCode)"
  Assert-TextContains "case2 docs tools skipped" $result2.OutputText "[SKIP] ue-tools docs"
  Assert-TextContains "case2 art tools ready" $result2.OutputText "[OK] ue-tools art"
  Assert-Condition "case2 ArtSource template created" (Test-Path -LiteralPath (Join-Path $targetRepoWithoutOptionalTools "ArtSource\_Template\Source") -PathType Container) "ArtSource template present" "ArtSource template missing"
  Assert-TextContains "case2 ue-tools skipped" $result2.OutputText "[SKIP] ue-tools"

  Step "Case 3: SkipOptionalToolSetup skips docs setup but still prepares ArtSource"
  $commandLog3 = Join-Path $script:TempRoot "case3-commands.log"
  Write-Utf8NoBomFile -Path $commandLog3 -Content ""
  $targetRepoWithSkippedOptionalSetup = New-InitRepoFixture -Name "target skip optional setup" -IncludeDocsSite -IncludeArtSourceTool
  $result3 = Invoke-InitRepo `
    -TargetRepoRoot $targetRepoWithSkippedOptionalSetup `
    -StubRoot $stubRoot `
    -CommandLog $commandLog3 `
    -ExtraArgs @("-SkipOptionalToolSetup")
  $commandLog3Text = Get-Content -LiteralPath $commandLog3 -Raw
  Assert-Condition "case3 init exits cleanly" ($result3.ExitCode -eq 0) "exit=0" "exit=$($result3.ExitCode)"
  Assert-TextContains "case3 docs tools skipped" $result3.OutputText "[SKIP] ue-tools docs"
  Assert-TextContains "case3 art tools ready" $result3.OutputText "[OK] ue-tools art"
  Assert-Condition "case3 ArtSource template created" (Test-Path -LiteralPath (Join-Path $targetRepoWithSkippedOptionalSetup "ArtSource\_Template\Source") -PathType Container) "ArtSource template present" "ArtSource template missing"
  Assert-TextNotContains "case3 npm install not invoked" $commandLog3Text "npm cwd="
  Assert-TextNotContains "case3 docs migration not invoked" $commandLog3Text "ue-tools docs migrate-sections"
  Assert-TextNotContains "case3 bridge install not invoked" $commandLog3Text "ue-tools docs install-bridge"
  Assert-TextNotContains "case3 doctor not invoked" $commandLog3Text "ue-tools docs doctor"

  Step "Case 3a: SkipArtSourceTools is the explicit ArtSource opt-out"
  $commandLog3a = Join-Path $script:TempRoot "case3a-commands.log"
  Write-Utf8NoBomFile -Path $commandLog3a -Content ""
  $targetRepoWithSkippedArtSource = New-InitRepoFixture -Name "target skip artsource" -IncludeArtSourceTool
  $result3a = Invoke-InitRepo `
    -TargetRepoRoot $targetRepoWithSkippedArtSource `
    -StubRoot $stubRoot `
    -CommandLog $commandLog3a `
    -ExtraArgs @("-SkipArtSourceTools", "-SkipDocsSetup")
  Assert-Condition "case3a init exits cleanly" ($result3a.ExitCode -eq 0) "exit=0" "exit=$($result3a.ExitCode)"
  Assert-TextContains "case3a art tools skipped" $result3a.OutputText "[SKIP] ue-tools art"
  Assert-Condition "case3a ArtSource layout remains absent" (-not (Test-Path -LiteralPath (Join-Path $targetRepoWithSkippedArtSource "ArtSource"))) "ArtSource absent" "ArtSource unexpectedly created"

  Step "Case 3b: SkipDocsSectionMigration suppresses init migration but still runs doctor"
  $commandLog3b = Join-Path $script:TempRoot "case3b-commands.log"
  Write-Utf8NoBomFile -Path $commandLog3b -Content ""
  $targetRepoSkipMigration = New-InitRepoFixture -Name "target skip docs migration" -IncludeDocsSite
  $result3b = Invoke-InitRepo `
    -TargetRepoRoot $targetRepoSkipMigration `
    -StubRoot $stubRoot `
    -CommandLog $commandLog3b `
    -ExtraArgs @("-SkipDocsSectionMigration")
  $commandLog3bText = Get-Content -LiteralPath $commandLog3b -Raw
  Assert-Condition "case3b init exits cleanly" ($result3b.ExitCode -eq 0) "exit=0" "exit=$($result3b.ExitCode)"
  Assert-TextNotContains "case3b docs migration not invoked" $commandLog3bText "ue-tools docs migrate-sections"
  Assert-TextContains "case3b doctor still invoked" $commandLog3bText "ue-tools docs doctor"
  Assert-TextContains "case3b readiness reports migration skip" $result3b.OutputText "[SKIP] docs section migration"

  Step "Case 3c: docs migration failure is surfaced"
  $commandLog3c = Join-Path $script:TempRoot "case3c-commands.log"
  Write-Utf8NoBomFile -Path $commandLog3c -Content ""
  $targetRepoMigrationFailure = New-InitRepoFixture -Name "target docs migration failure" -IncludeDocsSite
  $result3c = Invoke-InitRepo `
    -TargetRepoRoot $targetRepoMigrationFailure `
    -StubRoot $stubRoot `
    -CommandLog $commandLog3c `
    -ExtraEnv @{ INIT_REPO_DOCS_MIGRATE_FAIL = "1" }
  Assert-Condition "case3c init fails when docs migration fails" ($result3c.ExitCode -ne 0) "non-zero exit" "expected non-zero exit code"
  Assert-TextContains "case3c output surfaces docs migration failure" $result3c.OutputText "ue-tools docs migrate-sections"

  Step "Case 4: Non-interactive init untracks newly ignored tracked files by default"
  $commandLog4 = Join-Path $script:TempRoot "case4-commands.log"
  Write-Utf8NoBomFile -Path $commandLog4 -Content ""
  $targetRepoTrackedIgnored = New-InitRepoFixture -Name "target tracked ignored files"
  $trackedIgnoredPath = Join-Path $targetRepoTrackedIgnored "Binaries\Tracked-Ignored-By-Init.txt"
  New-Item -ItemType Directory -Force -Path (Split-Path -Path $trackedIgnoredPath -Parent) | Out-Null
  Write-Utf8NoBomFile -Path $trackedIgnoredPath -Content "tracked then ignored`n"
  & git -C $targetRepoTrackedIgnored add -- "Binaries/Tracked-Ignored-By-Init.txt" | Out-Null
  & git -C $targetRepoTrackedIgnored commit -m "Add tracked file before ignore rule" | Out-Null
  Write-Utf8NoBomFile -Path (Join-Path $targetRepoTrackedIgnored ".gitignore") -Content "Binaries/`n"
  $result4 = Invoke-InitRepo `
    -TargetRepoRoot $targetRepoTrackedIgnored `
    -StubRoot $stubRoot `
    -CommandLog $commandLog4 `
    -ExtraArgs @("-NonInteractive")
  Assert-Condition "case4 init exits cleanly" ($result4.ExitCode -eq 0) "exit=0" "exit=$($result4.ExitCode)"
  Assert-TextContains "case4 output indicates non-interactive untrack" $result4.OutputText "Non-interactive mode: untracking"
  Assert-TextContains "case4 output reports ignored tracked file batch progress" $result4.OutputText "Untracking ignored tracked files batch 1/1"
  Assert-Condition "case4 tracked ignored file still exists locally" (Test-Path -LiteralPath $trackedIgnoredPath -PathType Leaf) "local file preserved" "local file was unexpectedly removed"
  & git -C $targetRepoTrackedIgnored ls-files --error-unmatch -- "Binaries/Tracked-Ignored-By-Init.txt" 2>$null | Out-Null
  Assert-Condition "case4 tracked ignored file untracked from git" ($LASTEXITCODE -ne 0) "file is no longer tracked" "file is still tracked"

  Step "Case 5: Non-interactive init auto-initializes non-git repo and creates default initial commit"
  $commandLog5 = Join-Path $script:TempRoot "case5-commands.log"
  Write-Utf8NoBomFile -Path $commandLog5 -Content ""
  $targetRepoNoGit = New-InitRepoFixture -Name "target no git" -SkipGitInit
  $result5 = Invoke-InitRepo `
    -TargetRepoRoot $targetRepoNoGit `
    -StubRoot $stubRoot `
    -CommandLog $commandLog5 `
    -ExtraArgs @("-NonInteractive")
  Assert-Condition "case5 init exits cleanly" ($result5.ExitCode -eq 0) "exit=0" "exit=$($result5.ExitCode)"
  Assert-Condition "case5 git directory created" (Test-Path -LiteralPath (Join-Path $targetRepoNoGit ".git") -PathType Container) ".git created" ".git missing"
  & git -C $targetRepoNoGit rev-parse --verify HEAD 2>$null | Out-Null
  Assert-Condition "case5 initial commit created" ($LASTEXITCODE -eq 0) "HEAD exists" "HEAD missing"
  Assert-TextContains "case5 readiness reports initial commit" $result5.OutputText "[OK] initial commit"

  Step "Case 6: blueprint-only repo skips optional first-time ue-tools build"
  $commandLog6 = Join-Path $script:TempRoot "case6-commands.log"
  Write-Utf8NoBomFile -Path $commandLog6 -Content ""
  $targetRepoBlueprintOnly = New-InitRepoFixture -Name "target blueprint only" -BlueprintOnly
  $result6 = Invoke-InitRepo `
    -TargetRepoRoot $targetRepoBlueprintOnly `
    -StubRoot $stubRoot `
    -CommandLog $commandLog6 `
    -IncludeSkipUnrealSync:$false `
    -ExtraArgs @("-NonInteractive")
  $commandLog6Text = Get-Content -LiteralPath $commandLog6 -Raw
  Assert-Condition "case6 init exits cleanly" ($result6.ExitCode -eq 0) "exit=0" "exit=$($result6.ExitCode)"
  Assert-TextContains "case6 output indicates blueprint-only build skip" $result6.OutputText "Blueprint-only project detected (no C++ modules/targets). Skipping first-time ue-tools build."
  Assert-TextContains "case6 readiness reports ue-tools skip" $result6.OutputText "[SKIP] ue-tools: First-time build skipped for blueprint-only project."
  Assert-TextNotContains "case6 ue-tools build was not invoked" $commandLog6Text "ue-tools build"

  Step "Summary"
  Write-Log ("PASS={0} FAIL={1}" -f $script:PassCount, $script:FailCount) Cyan
  if ($script:FailCount -eq 0) {
    Write-Log "Init repo tool readiness tests passed." Green
  }
  else {
    Write-Log "Init repo tool readiness tests failed." Red
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
  if (-not $NoCleanup -and (Test-Path -LiteralPath $script:TempRoot)) {
    Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Log ""
  Write-Log "Log saved: $logPath" Cyan
}
