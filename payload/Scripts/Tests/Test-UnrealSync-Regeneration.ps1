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
$resultsDir = Join-Path $repoRoot "Scripts\Tests\Test-UnrealSync-RegenerationResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "UnrealSync-Regen-$stamp.log"
$testHarnessPath = Join-Path $repoRoot "Scripts\Tests\TestHarness.ps1"
if (-not (Test-Path -LiteralPath $testHarnessPath -PathType Leaf)) {
  throw "Test harness not found: $testHarnessPath"
}
. $testHarnessPath
$syncScript = Resolve-UEToolSuiteRuntimeFile -RepoRoot $repoRoot -RelativePath "Scripts\UETools\UEToolSuite.Unreal.psm1"

$script:PassCount = 0
$script:FailCount = 0
$script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ue sync regen tests " + [Guid]::NewGuid().ToString("N"))
$script:TestEngineAssociation = "5.4"
New-Item -ItemType Directory -Force -Path $script:TempRoot | Out-Null
Initialize-TestHarness -LogPath $logPath -FailFast:$FailFast

function New-CaseDir([string]$CaseName) {
  $dir = Join-Path $script:TempRoot $CaseName
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  return $dir
}

function New-UProjectFile([string]$CaseDir, [string]$EngineAssociation) {
  $uprojectPath = Join-Path $CaseDir "Space Project.uproject"
  $template = @'
{
  "FileVersion": 3,
  "EngineAssociation": "__ENGINE_ASSOC__",
  "Category": "",
  "Description": "",
  "Modules": []
}
'@
  $content = $template.Replace("__ENGINE_ASSOC__", $EngineAssociation)
  Write-TextFileLf -Path $uprojectPath -Content $content
  return $uprojectPath
}

function New-ActionPlanUProjectFile([string]$RepoDir) {
  $uprojectPath = Join-Path $RepoDir "ActionPlan.uproject"
  $content = @'
{
  "FileVersion": 3,
  "EngineAssociation": "5.4",
  "Category": "",
  "Description": "",
  "Modules": [
    {
      "Name": "ActionPlan",
      "Type": "Runtime",
      "LoadingPhase": "Default"
    }
  ]
}
'@
  Write-TextFileLf -Path $uprojectPath -Content $content
  return $uprojectPath
}

function New-FakeUVSWithArtifactMutation([string]$Path, [string]$WorkspacePath, [string]$IgnorePath) {
  $scriptPath = [System.IO.Path]::ChangeExtension($Path, ".ps1")
  $escapedWorkspacePath = $WorkspacePath.Replace("'", "''")
  $escapedIgnorePath = $IgnorePath.Replace("'", "''")
  $scriptText = @"
`$workspacePath = '$escapedWorkspacePath'
`$ignorePath = '$escapedIgnorePath'
@'
{
  "folders": [
    {
      "name": "Generated Project",
      "path": "."
    }
  ],
  "settings": {
    "terminal.integrated.env.windows": {
      "PATH": "generated"
    }
  },
  "extensions": {
    "recommendations": [
      "generated.extension"
    ]
  },
  "tasks": {
    "version": "2.0.0",
    "tasks": [
      {
        "label": "Generated Task",
        "type": "shell",
        "command": "echo generated"
      }
    ]
  },
  "launch": {
    "version": "0.2.0",
    "configurations": [
      {
        "name": "Generated Launch",
        "type": "cppvsdbg",
        "request": "launch",
        "program": "generated.exe"
      }
    ]
  }
}
'@ | Set-Content -LiteralPath `$workspacePath -Encoding UTF8
'generated ignore' | Set-Content -LiteralPath `$ignorePath -Encoding UTF8
exit 0
"@
  Write-TextFileLf -Path $scriptPath -Content $scriptText

  $batchText = @"
@echo off
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$scriptPath"
exit /b %ERRORLEVEL%
"@
  Write-TextFileLf -Path $Path -Content $batchText
}

function New-FakeUVS([string]$Path, [int]$ExitCode) {
  $scriptText = @"
@echo off
setlocal
if not "%UE_SYNC_TEST_UVS_CAPTURE%"=="" (
  >>"%UE_SYNC_TEST_UVS_CAPTURE%" echo EXE=%~f0
  >>"%UE_SYNC_TEST_UVS_CAPTURE%" echo ARGS=%*
)
exit /b $ExitCode
"@
  Write-TextFileLf -Path $Path -Content $scriptText
}

function New-FakeUVSRetryOnce([string]$Path, [int]$FirstExitCode, [int]$SecondExitCode) {
  $scriptText = @"
@echo off
setlocal EnableDelayedExpansion
if not "%UE_SYNC_TEST_UVS_CAPTURE%"=="" (
  >>"%UE_SYNC_TEST_UVS_CAPTURE%" echo EXE=%~f0
  >>"%UE_SYNC_TEST_UVS_CAPTURE%" echo ARGS=%*
)
if "%UE_SYNC_TEST_UVS_STATE%"=="" (
  exit /b $FirstExitCode
)
if exist "%UE_SYNC_TEST_UVS_STATE%" (
  del "%UE_SYNC_TEST_UVS_STATE%" >nul 2>&1
  exit /b $SecondExitCode
)
echo first> "%UE_SYNC_TEST_UVS_STATE%"
exit /b $FirstExitCode
"@
  Write-TextFileLf -Path $Path -Content $scriptText
}

function New-FakeBuildBat([string]$EngineRoot, [int]$ExitCode) {
  $batchDir = Join-Path $EngineRoot "Engine\Build\BatchFiles"
  New-Item -ItemType Directory -Force -Path $batchDir | Out-Null

  $scriptText = @"
@echo off
setlocal
if not "%UE_SYNC_TEST_FALLBACK_CAPTURE%"=="" (
  >>"%UE_SYNC_TEST_FALLBACK_CAPTURE%" echo EXE=%~f0
  >>"%UE_SYNC_TEST_FALLBACK_CAPTURE%" echo ARGS=%*
)
exit /b $ExitCode
"@
  Write-TextFileLf -Path (Join-Path $batchDir "Build.bat") -Content $scriptText
}

function New-ActionPlanRepo([string]$Name) {
  $repoDir = New-CaseDir $Name
  & git -C $repoDir init | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "git init failed for action-plan repo: $repoDir" }
  & git -C $repoDir config user.email "ue-sync-test@example.invalid" | Out-Null
  & git -C $repoDir config user.name "UE Sync Test" | Out-Null

  [void](New-ActionPlanUProjectFile -RepoDir $repoDir)
  $sourceDir = Join-Path $repoDir "Source\ActionPlan"
  New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null
  Write-TextFileLf -Path (Join-Path $sourceDir "ActionPlan.Build.cs") -Content @'
using UnrealBuildTool;

public class ActionPlan : ModuleRules
{
  public ActionPlan(ReadOnlyTargetRules Target) : base(Target)
  {
    PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
  }
}
'@
  Write-TextFileLf -Path (Join-Path $sourceDir "ActionPlan.cpp") -Content @'
#include "ActionPlan.h"
'@
  Write-TextFileLf -Path (Join-Path $sourceDir "ActionPlan.h") -Content @'
#pragma once
'@

  & git -C $repoDir add . | Out-Null
  & git -C $repoDir commit -m "test: initial action plan repo" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "initial action-plan commit failed in: $repoDir" }
  $base = ((git -C $repoDir rev-parse HEAD 2>$null) | Select-Object -First 1).Trim()

  return [pscustomobject]@{
    RepoDir = $repoDir
    Base = $base
  }
}

function Invoke-UnrealSyncAt {
  param(
    [Parameter(Mandatory)][string]$WorkingDir,
    [Parameter(Mandatory)][string[]]$Args,
    [hashtable]$Environment,
    [Nullable[long]]$SeedLastExitCode = $null
  )

  Write-Log ">> [$WorkingDir] invoke UnrealSync module entrypoint" DarkGray
  if ($null -ne $SeedLastExitCode) {
    Write-Log "   seeded LASTEXITCODE=$SeedLastExitCode before UnrealSync invocation" DarkGray
  }

  $envBackup = @{}
  if ($Environment) {
    foreach ($key in $Environment.Keys) {
      $envPath = "Env:$key"
      if (Test-Path -Path $envPath) {
        $envBackup[$key] = (Get-Item -Path $envPath).Value
      }
      else {
        $envBackup[$key] = $null
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

  $runtimeModule = $null
  $entrypoint = $null
  $params = @{ RepoRoot = $WorkingDir }
  $i = 0
  while ($i -lt $Args.Count) {
    $token = [string]$Args[$i]
    $normalized = $token.Trim().ToLowerInvariant()
    switch ($normalized) {
      '-force' { $params.Force = $true; $i += 1; continue }
      '-cleangenerated' { $params.CleanGenerated = $true; $i += 1; continue }
      '-cleansaved' { $params.CleanSaved = $true; $i += 1; continue }
      '-cleancache' { $params.CleanCache = $true; $i += 1; continue }
      '-noregen' { $params.NoRegen = $true; $i += 1; continue }
      '-nobuild' { $params.NoBuild = $true; $i += 1; continue }
      '-noninteractive' { $params.NonInteractive = $true; $i += 1; continue }
      '-dryrun' { $params.DryRun = $true; $i += 1; continue }
      '-oldrev' { if (($i + 1) -ge $Args.Count) { throw 'Missing value for -OldRev' }; $params.OldRev = [string]$Args[$i + 1]; $i += 2; continue }
      '-newrev' { if (($i + 1) -ge $Args.Count) { throw 'Missing value for -NewRev' }; $params.NewRev = [string]$Args[$i + 1]; $i += 2; continue }
      '-flag' { if (($i + 1) -ge $Args.Count) { throw 'Missing value for -Flag' }; $params.Flag = [int]$Args[$i + 1]; $i += 2; continue }
      '-workspacepath' { if (($i + 1) -ge $Args.Count) { throw 'Missing value for -WorkspacePath' }; $params.WorkspacePath = [string]$Args[$i + 1]; $i += 2; continue }
      '-uprojectpath' { if (($i + 1) -ge $Args.Count) { throw 'Missing value for -UProjectPath' }; $params.UProjectPath = [string]$Args[$i + 1]; $i += 2; continue }
      '-config' { if (($i + 1) -ge $Args.Count) { throw 'Missing value for -Config' }; $params.Config = [string]$Args[$i + 1]; $i += 2; continue }
      '-platform' { if (($i + 1) -ge $Args.Count) { throw 'Missing value for -Platform' }; $params.Platform = [string]$Args[$i + 1]; $i += 2; continue }
      '-reporoot' { if (($i + 1) -ge $Args.Count) { throw 'Missing value for -RepoRoot' }; $params.RepoRoot = [string]$Args[$i + 1]; $i += 2; continue }
      default { throw "Unknown UnrealSync option '$token'." }
    }
  }

  $previousNoAutorun = $env:UE_TOOLS_UNREAL_RUNTIME_NO_AUTORUN
  $env:UE_TOOLS_UNREAL_RUNTIME_NO_AUTORUN = "1"
  $transcriptPath = Join-Path $WorkingDir (".ue-sync-test-transcript-" + [Guid]::NewGuid().ToString("N") + ".txt")
  $transcriptStarted = $false

  Push-Location $WorkingDir
  try {
    $runtimeModule = Import-Module -Name $syncScript -Force -DisableNameChecking -PassThru -ErrorAction Stop
    $entrypoint = Get-Command -Name 'Invoke-UEToolSuiteUnrealRuntime' -Module $runtimeModule.Name -CommandType Function -ErrorAction SilentlyContinue
    if (-not $entrypoint) {
      $entrypoint = Get-Command -Name 'Invoke-UEToolSuiteUnrealRuntime' -CommandType Function -ErrorAction Stop
    }

    if ($null -ne $SeedLastExitCode) {
      $global:LASTEXITCODE = $SeedLastExitCode
    }

    try {
      Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
      $transcriptStarted = $true
    }
    catch {
      $transcriptStarted = $false
    }

    $out = @(& $entrypoint.Name @params 2>&1)
    $code = 0
  }
  catch {
    $out = @(
      "Invoke-UEToolSuiteUnrealRuntime error: $($_.Exception.Message)"
      $_.ScriptStackTrace
      if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) { $_.InvocationInfo.PositionMessage }
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    $code = 128
  }
  finally {
    if ($transcriptStarted) {
      try { Stop-Transcript | Out-Null } catch { }
    }
    Pop-Location
    if ([string]::IsNullOrEmpty($previousNoAutorun)) {
      Remove-Item Env:UE_TOOLS_UNREAL_RUNTIME_NO_AUTORUN -ErrorAction SilentlyContinue
    }
    else {
      $env:UE_TOOLS_UNREAL_RUNTIME_NO_AUTORUN = $previousNoAutorun
    }
    foreach ($key in $envBackup.Keys) {
      $envPath = "Env:$key"
      if ($null -eq $envBackup[$key]) {
        Remove-Item -Path $envPath -ErrorAction SilentlyContinue
      }
      else {
        Set-Item -Path $envPath -Value ([string]$envBackup[$key])
      }
    }
  }

  if (Test-Path -LiteralPath $transcriptPath) {
    try {
      $transcriptLines = Get-Content -LiteralPath $transcriptPath -ErrorAction Stop |
        Where-Object { $_ -match '^\[UE Sync\]' -or $_ -match '^fatal:' }
      $out = @($out + $transcriptLines)
    }
    finally {
      Remove-Item -LiteralPath $transcriptPath -Force -ErrorAction SilentlyContinue
    }
  }

  $normalizedOutput = @()
  foreach ($line in $out) {
    $text = Remove-AnsiEscapeSequences "$line"
    $normalizedOutput += $text
    if (-not [string]::IsNullOrWhiteSpace($text)) {
      Write-Log ("   " + $text.TrimEnd()) DarkGray
    }
  }

  return [pscustomobject]@{
    Code   = $code
    Output = ($normalizedOutput | ForEach-Object { "$_" }) -join "`n"
  }
}

try {
  Step "UnrealSync Regeneration Tests ($stamp)"
  Write-Log "Repo: $repoRoot" Cyan
  Write-Log "Log : $logPath" Cyan
  Write-Log "Temp: $script:TempRoot" Cyan

  Step "Case 1: UVS success path"
  $case1 = New-CaseDir "case 1 uvs success path"
  $uproject1 = New-UProjectFile $case1 $script:TestEngineAssociation
  $tools1 = Join-Path $case1 "Fake Tools"
  New-Item -ItemType Directory -Force -Path $tools1 | Out-Null
  $uvs1 = Join-Path $tools1 "UnrealVersionSelector.cmd"
  New-FakeUVS -Path $uvs1 -ExitCode 0
  $uvsCapture1 = Join-Path $case1 "uvs-capture.txt"
  $fallbackCapture1 = Join-Path $case1 "fallback-capture.txt"

  $res = Invoke-UnrealSyncAt -WorkingDir $case1 -Args @("-Force", "-NoBuild", "-NonInteractive") -Environment @{
    UE_SYNC_UVS_PATH             = $uvs1
    UE_SYNC_TEST_UVS_CAPTURE     = $uvsCapture1
    UE_SYNC_TEST_FALLBACK_CAPTURE = $fallbackCapture1
    UE_ENGINE_DIR                = $null
    UE_ENGINE_ROOT               = $null
    UNREAL_ENGINE_DIR            = $null
    UE_ENGINE_DISABLE_COMMON_INSTALL_SCAN = $null
  }

  Assert-Code "case 1 exit code" $res.Code 0
  Assert-OutputContains "case 1 UVS success message" $res.Output "UVS project-file regeneration succeeded."
  Assert-OutputNotContains "case 1 no fallback invocation" $res.Output "Regenerating project files (fallback via"
  Assert-Condition "case 1 UVS capture exists" (Test-Path -LiteralPath $uvsCapture1) "uvs capture created" "uvs capture missing"
  if (Test-Path -LiteralPath $uvsCapture1) {
    $capture = Get-Content -LiteralPath $uvsCapture1 -Raw
    Assert-OutputContains "case 1 UVS args include /projectfiles" $capture "/projectfiles"
    Assert-OutputContains "case 1 UVS args include spaced uproject path" $capture $uproject1
  }

  Step "Case 2: UVS failure falls back successfully via Build.bat"
  $case2 = New-CaseDir "case 2 uvs fail fallback build bat"
  $uproject2 = New-UProjectFile $case2 $script:TestEngineAssociation
  $tools2 = Join-Path $case2 "Fake Tools"
  New-Item -ItemType Directory -Force -Path $tools2 | Out-Null
  $uvs2 = Join-Path $tools2 "UnrealVersionSelector.cmd"
  New-FakeUVS -Path $uvs2 -ExitCode 17
  $engine2 = Join-Path $case2 "Fake Engine Root"
  New-FakeBuildBat -EngineRoot $engine2 -ExitCode 0
  $uvsCapture2 = Join-Path $case2 "uvs-capture.txt"
  $fallbackCapture2 = Join-Path $case2 "fallback-capture.txt"

  $res = Invoke-UnrealSyncAt -WorkingDir $case2 -Args @("-Force", "-NoBuild", "-NonInteractive") -Environment @{
    UE_SYNC_UVS_PATH              = $uvs2
    UE_SYNC_TEST_UVS_CAPTURE      = $uvsCapture2
    UE_SYNC_TEST_FALLBACK_CAPTURE = $fallbackCapture2
    UE_ENGINE_DIR                 = $engine2
    UE_ENGINE_ROOT                = $null
    UNREAL_ENGINE_DIR             = $null
    UE_ENGINE_DISABLE_COMMON_INSTALL_SCAN = $null
  }

  Assert-Code "case 2 exit code" $res.Code 0
  Assert-OutputContains "case 2 UVS failure logged" $res.Output "UVS failed (exit 17) after 2 attempt(s). Falling back to batch-file project generation..."
  Assert-OutputContains "case 2 fallback tool logged" $res.Output "Regenerating project files (fallback via Build.bat)..."
  Assert-OutputContains "case 2 engine root source logged" $res.Output "Engine root resolved from UE_ENGINE_DIR"
  Assert-Condition "case 2 fallback capture exists" (Test-Path -LiteralPath $fallbackCapture2) "fallback capture created" "fallback capture missing"
  if (Test-Path -LiteralPath $fallbackCapture2) {
    $capture = Get-Content -LiteralPath $fallbackCapture2 -Raw
    Assert-OutputContains "case 2 fallback args include projectfiles" $capture "-projectfiles"
    Assert-OutputContains "case 2 fallback args include vscode" $capture "-vscode"
    Assert-OutputContains "case 2 fallback args include spaced project path" $capture "-project=$uproject2"
  }

  Step "Case 3: Expected unresolved engine-root failure is actionable"
  $case3 = New-CaseDir "case 3 unresolved engine root"
  [void](New-UProjectFile $case3 "9.9-test-missing")
  $tools3 = Join-Path $case3 "Fake Tools"
  New-Item -ItemType Directory -Force -Path $tools3 | Out-Null
  $uvs3 = Join-Path $tools3 "UnrealVersionSelector.cmd"
  New-FakeUVS -Path $uvs3 -ExitCode 21
  $uvsCapture3 = Join-Path $case3 "uvs-capture.txt"

  $res = Invoke-UnrealSyncAt -WorkingDir $case3 -Args @("-Force", "-NoBuild", "-NonInteractive") -Environment @{
    UE_SYNC_UVS_PATH              = $uvs3
    UE_SYNC_TEST_UVS_CAPTURE      = $uvsCapture3
    UE_SYNC_TEST_FALLBACK_CAPTURE = $null
    UE_ENGINE_DIR                 = $null
    UE_ENGINE_ROOT                = $null
    UNREAL_ENGINE_DIR             = $null
    UE_ENGINE_DISABLE_COMMON_INSTALL_SCAN = "1"
  }

  Write-Log "   note: the non-zero exception output above is expected for this negative test case." DarkGray
  Assert-Condition "case 3 exit is non-zero" ($res.Code -ne 0) "exit=$($res.Code)" "expected non-zero exit, got $($res.Code)"
  Assert-OutputContains "case 3 actionable error header" $res.Output "Could not resolve Unreal Engine install path for project-file fallback."
  Assert-OutputContains "case 3 attempted sources heading" $res.Output "Attempted sources (in order):"
  Assert-OutputContains "case 3 env source listed" $res.Output "UE_ENGINE_DIR is unset"
  Assert-OutputContains "case 3 association listed" $res.Output ".uproject EngineAssociation='9.9-test-missing'"

  Step "Case 4: Spaced workspace path resolves engine root for fallback"
  $case4 = New-CaseDir "case 4 workspace path with spaces"
  $uproject4 = New-UProjectFile $case4 $script:TestEngineAssociation
  $tools4 = Join-Path $case4 "Fake Tools"
  New-Item -ItemType Directory -Force -Path $tools4 | Out-Null
  $uvs4 = Join-Path $tools4 "UnrealVersionSelector.cmd"
  New-FakeUVS -Path $uvs4 -ExitCode 8
  $engine4 = Join-Path $case4 "Engine Install With Spaces"
  New-FakeBuildBat -EngineRoot $engine4 -ExitCode 0
  $workspace4 = Join-Path $case4 "My Workspace.code-workspace"
  $workspaceContent = @'
{
  "folders": [
    { "name": "Project", "path": "." },
    { "name": "UE5", "path": "Engine Install With Spaces" }
  ]
}
'@
  Write-TextFileLf -Path $workspace4 -Content $workspaceContent
  $fallbackCapture4 = Join-Path $case4 "fallback-capture.txt"

  $res = Invoke-UnrealSyncAt -WorkingDir $case4 -Args @(
    "-Force",
    "-NoBuild",
    "-NonInteractive",
    "-WorkspacePath", $workspace4
  ) -Environment @{
    UE_SYNC_UVS_PATH              = $uvs4
    UE_SYNC_TEST_UVS_CAPTURE      = $null
    UE_SYNC_TEST_FALLBACK_CAPTURE = $fallbackCapture4
    UE_ENGINE_DIR                 = $null
    UE_ENGINE_ROOT                = $null
    UNREAL_ENGINE_DIR             = $null
    UE_ENGINE_DISABLE_COMMON_INSTALL_SCAN = $null
  }

  Assert-Code "case 4 exit code" $res.Code 0
  Assert-OutputContains "case 4 workspace resolution log" $res.Output "Engine root resolved from workspace: $engine4"
  Assert-OutputContains "case 4 fallback tool log" $res.Output "Regenerating project files (fallback via Build.bat)..."
  Assert-Condition "case 4 fallback capture exists" (Test-Path -LiteralPath $fallbackCapture4) "fallback capture created" "fallback capture missing"
  if (Test-Path -LiteralPath $fallbackCapture4) {
    $capture = Get-Content -LiteralPath $fallbackCapture4 -Raw
    Assert-OutputContains "case 4 fallback preserves spaced project path" $capture "-project=$uproject4"
  }

  Step "Case 5: UVS retry succeeds on second attempt and skips fallback"
  $case5 = New-CaseDir "case 5 uvs retry once then success"
  [void](New-UProjectFile $case5 $script:TestEngineAssociation)
  $tools5 = Join-Path $case5 "Fake Tools"
  New-Item -ItemType Directory -Force -Path $tools5 | Out-Null
  $uvs5 = Join-Path $tools5 "UnrealVersionSelector.cmd"
  New-FakeUVSRetryOnce -Path $uvs5 -FirstExitCode 42 -SecondExitCode 0
  $uvsCapture5 = Join-Path $case5 "uvs-capture.txt"
  $fallbackCapture5 = Join-Path $case5 "fallback-capture.txt"
  $uvsState5 = Join-Path $case5 "uvs-state.txt"

  $res = Invoke-UnrealSyncAt -WorkingDir $case5 -Args @("-Force", "-NoBuild", "-NonInteractive") -Environment @{
    UE_SYNC_UVS_PATH              = $uvs5
    UE_SYNC_TEST_UVS_CAPTURE      = $uvsCapture5
    UE_SYNC_TEST_UVS_STATE        = $uvsState5
    UE_SYNC_TEST_FALLBACK_CAPTURE = $fallbackCapture5
    UE_ENGINE_DIR                 = $null
    UE_ENGINE_ROOT                = $null
    UNREAL_ENGINE_DIR             = $null
    UE_ENGINE_DISABLE_COMMON_INSTALL_SCAN = $null
    UE_SYNC_UVS_MAX_ATTEMPTS      = "2"
  }

  Assert-Code "case 5 exit code" $res.Code 0
  Assert-OutputContains "case 5 retry warning" $res.Output "UVS returned non-zero exit (42) on attempt 1/2. Retrying..."
  Assert-OutputContains "case 5 strict success message" $res.Output "UVS project-file regeneration succeeded."
  Assert-OutputNotContains "case 5 no fallback invocation" $res.Output "Regenerating project files (fallback via"
  Assert-Condition "case 5 fallback capture absent" (-not (Test-Path -LiteralPath $fallbackCapture5)) "fallback not called" "fallback should not have been invoked"
  if (Test-Path -LiteralPath $uvsCapture5) {
    $capture = Get-Content -LiteralPath $uvsCapture5
    Assert-Condition "case 5 UVS invoked twice" ($capture.Count -ge 2) "uvs invocation count >=2" "expected at least two UVS invocations"
  }

  Step "Case 6: Seeded stale LASTEXITCODE does not leak into UVS failure reporting"
  $case6 = New-CaseDir "case 6 seeded stale last exit code"
  [void](New-UProjectFile $case6 $script:TestEngineAssociation)
  $tools6 = Join-Path $case6 "Fake Tools"
  New-Item -ItemType Directory -Force -Path $tools6 | Out-Null
  $uvs6 = Join-Path $tools6 "UnrealVersionSelector.cmd"
  New-FakeUVS -Path $uvs6 -ExitCode 29
  $engine6 = Join-Path $case6 "Fake Engine Root"
  New-FakeBuildBat -EngineRoot $engine6 -ExitCode 0
  $fallbackCapture6 = Join-Path $case6 "fallback-capture.txt"
  $staleSeedCode = 2147942402L

  $res = Invoke-UnrealSyncAt -WorkingDir $case6 -Args @("-Force", "-NoBuild", "-NonInteractive") -Environment @{
    UE_SYNC_UVS_PATH              = $uvs6
    UE_SYNC_TEST_FALLBACK_CAPTURE = $fallbackCapture6
    UE_ENGINE_DIR                 = $engine6
    UE_ENGINE_ROOT                = $null
    UNREAL_ENGINE_DIR             = $null
    UE_ENGINE_DISABLE_COMMON_INSTALL_SCAN = $null
  } -SeedLastExitCode $staleSeedCode

  Assert-Code "case 6 exit code" $res.Code 0
  Assert-OutputContains "case 6 UVS failure uses UVS exit code" $res.Output "UVS failed (exit 29) after 2 attempt(s). Falling back to batch-file project generation..."
  Assert-OutputNotContains "case 6 stale seeded code not reported as UVS exit" $res.Output "UVS failed (exit $staleSeedCode)"
  Assert-OutputContains "case 6 fallback still invoked" $res.Output "Regenerating project files (fallback via Build.bat)..."
  Assert-Condition "case 6 fallback capture exists" (Test-Path -LiteralPath $fallbackCapture6) "fallback capture created" "fallback capture missing"

  Step "Case 7: First regeneration with unknown customization restores workspace and requires adoption"
  $case7 = New-CaseDir "case 7 preserve workspace artifacts"
  [void](New-UProjectFile $case7 $script:TestEngineAssociation)
  $workspace7 = Join-Path $case7 "Space Project.code-workspace"
  $ignore7 = Join-Path $case7 ".ignore"
  $initialWorkspace7 = @'
{
  "folders": [
    {
      "name": "User Project",
      "path": "."
    },
    {
      "name": "User Extra Folder",
      "path": "../UserExtra"
    }
  ],
  "settings": {
    "editor.formatOnSave": true,
    "terminal.integrated.env.windows": {
      "USER_ONLY": "1"
    }
  },
  "extensions": {
    "recommendations": [
      "user.extension"
    ]
  },
  "tasks": {
    "version": "2.0.0",
    "tasks": [
      {
        "label": "User Task",
        "type": "shell",
        "command": "echo user"
      }
    ]
  },
  "launch": {
    "version": "0.2.0",
    "configurations": [
      {
        "name": "User Launch",
        "type": "node",
        "request": "launch",
        "program": "user.js"
      }
    ]
  }
}
'@
  Write-TextFileLf -Path $workspace7 -Content $initialWorkspace7
  Write-TextFileLf -Path $ignore7 -Content "original ignore`n"
  $uvs7 = Join-Path $case7 "UnrealVersionSelector.cmd"
  New-FakeUVSWithArtifactMutation -Path $uvs7 -WorkspacePath $workspace7 -IgnorePath $ignore7

  $res = Invoke-UnrealSyncAt -WorkingDir $case7 -Args @("-Force", "-NoBuild", "-NonInteractive") -Environment @{
    UE_SYNC_UVS_PATH              = $uvs7
    UE_SYNC_TEST_FALLBACK_CAPTURE = $null
    UE_ENGINE_DIR                 = $null
    UE_ENGINE_ROOT                = $null
    UNREAL_ENGINE_DIR             = $null
    UE_ENGINE_DISABLE_COMMON_INSTALL_SCAN = $null
  }

  Assert-Condition "case 7 exit is non-zero" ($res.Code -ne 0) "exit=$($res.Code)" "expected non-zero exit"
  Assert-OutputContains "case 7 adoption requirement logged" $res.Output "Run 'ue settings adopt'"
  Assert-OutputContains "case 7 workspace rollback logged" $res.Output "Restoring the pre-regen workspace file and stopping before build"
  $workspace7Text = Get-Content -LiteralPath $workspace7 -Raw
  $ignore7Text = Get-Content -LiteralPath $ignore7 -Raw
  Assert-Condition "case 7 original workspace restored byte-for-byte" ($workspace7Text -eq $initialWorkspace7) "original workspace restored" "workspace content changed"
  Assert-Condition "case 7 ignore restored" ($ignore7Text -eq "original ignore`n") "ignore restored" "ignore content=$ignore7Text"

  Step "Case 8: Modified C++ source triggers build only"
  $case8Repo = New-ActionPlanRepo -Name "case 8 modified cpp build only"
  $cpp8 = Join-Path $case8Repo.RepoDir "Source\ActionPlan\ActionPlan.cpp"
  Add-Content -LiteralPath $cpp8 -Value "// build-only change" -Encoding UTF8
  & git -C $case8Repo.RepoDir add . | Out-Null
  & git -C $case8Repo.RepoDir commit -m "test: modify cpp" | Out-Null
  $head8 = ((git -C $case8Repo.RepoDir rev-parse HEAD 2>$null) | Select-Object -First 1).Trim()
  $res = Invoke-UnrealSyncAt -WorkingDir $case8Repo.RepoDir -Args @(
    "-RepoRoot", $case8Repo.RepoDir,
    "-OldRev", $case8Repo.Base,
    "-NewRev", $head8,
    "-Flag", "1",
    "-NonInteractive",
    "-DryRun"
  ) -Environment @{}

  Assert-Code "case 8 exit code" $res.Code 0
  Assert-OutputContains "case 8 build-only action plan" $res.Output "UE Sync action plan: build the editor."
  Assert-OutputContains "case 8 build trigger listed" $res.Output "Build triggers:"
  Assert-OutputNotContains "case 8 no regen trigger heading" $res.Output "Project-file regeneration triggers:"

  Step "Case 9: Added C++ source triggers project-file regen and build"
  $case9Repo = New-ActionPlanRepo -Name "case 9 added cpp regen and build"
  $newCpp9 = Join-Path $case9Repo.RepoDir "Source\ActionPlan\NewFile.cpp"
  Write-TextFileLf -Path $newCpp9 -Content '#include "ActionPlan.h"'
  & git -C $case9Repo.RepoDir add . | Out-Null
  & git -C $case9Repo.RepoDir commit -m "test: add cpp" | Out-Null
  $head9 = ((git -C $case9Repo.RepoDir rev-parse HEAD 2>$null) | Select-Object -First 1).Trim()
  $res = Invoke-UnrealSyncAt -WorkingDir $case9Repo.RepoDir -Args @(
    "-RepoRoot", $case9Repo.RepoDir,
    "-OldRev", $case9Repo.Base,
    "-NewRev", $head9,
    "-Flag", "1",
    "-NonInteractive",
    "-DryRun"
  ) -Environment @{}

  Assert-Code "case 9 exit code" $res.Code 0
  Assert-OutputContains "case 9 regen and build action plan" $res.Output "UE Sync action plan: regenerate project files and build the editor."
  Assert-OutputContains "case 9 regen trigger listed" $res.Output "Project-file regeneration triggers:"
  Assert-OutputContains "case 9 build trigger listed" $res.Output "Build triggers:"

  Step "Case 10: Build.cs changes trigger project-file regen and build"
  $case10Repo = New-ActionPlanRepo -Name "case 10 build cs regen and build"
  $buildCs10 = Join-Path $case10Repo.RepoDir "Source\ActionPlan\ActionPlan.Build.cs"
  Add-Content -LiteralPath $buildCs10 -Value "// module rules changed" -Encoding UTF8
  & git -C $case10Repo.RepoDir add . | Out-Null
  & git -C $case10Repo.RepoDir commit -m "test: modify module rules" | Out-Null
  $head10 = ((git -C $case10Repo.RepoDir rev-parse HEAD 2>$null) | Select-Object -First 1).Trim()
  $res = Invoke-UnrealSyncAt -WorkingDir $case10Repo.RepoDir -Args @(
    "-RepoRoot", $case10Repo.RepoDir,
    "-OldRev", $case10Repo.Base,
    "-NewRev", $head10,
    "-Flag", "1",
    "-NonInteractive",
    "-DryRun"
  ) -Environment @{}

  Assert-Code "case 10 exit code" $res.Code 0
  Assert-OutputContains "case 10 regen and build action plan" $res.Output "UE Sync action plan: regenerate project files and build the editor."
  Assert-OutputContains "case 10 regen trigger listed" $res.Output "Project-file regeneration triggers:"
  Assert-OutputContains "case 10 build trigger listed" $res.Output "Build triggers:"

  Step "Case 11: Blueprint-only project skips build gracefully"
  $case11 = New-CaseDir "case 11 blueprint-only skip build"
  [void](New-UProjectFile $case11 $script:TestEngineAssociation)
  $engine11 = Join-Path $case11 "Blueprint Fake Engine"
  New-FakeBuildBat -EngineRoot $engine11 -ExitCode 0
  $buildCapture11 = Join-Path $case11 "build-capture.txt"

  $res = Invoke-UnrealSyncAt -WorkingDir $case11 -Args @(
    "-Force",
    "-NoRegen",
    "-NonInteractive"
  ) -Environment @{
    UE_SYNC_TEST_FALLBACK_CAPTURE = $buildCapture11
    UE_ENGINE_DIR                 = $engine11
    UE_ENGINE_ROOT                = $null
    UNREAL_ENGINE_DIR             = $null
    UE_ENGINE_DISABLE_COMMON_INSTALL_SCAN = $null
  }

  Assert-Code "case 11 exit code" $res.Code 0
  Assert-OutputContains "case 11 blueprint warning" $res.Output "Blueprint-only project detected"
  Assert-OutputContains "case 11 build skipped" $res.Output "Skipping build..."
  Assert-Condition "case 11 build tool not invoked" (-not (Test-Path -LiteralPath $buildCapture11)) "Build.bat not called" "Build.bat should not run for blueprint-only project"

  Step "Summary"
  Write-Log ("PASS={0} FAIL={1}" -f $script:PassCount, $script:FailCount) Cyan
  if ($script:FailCount -eq 0) {
    Write-Log "UnrealSync regeneration tests passed." Green
  }
  else {
    Write-Log "UnrealSync regeneration tests failed." Red
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
