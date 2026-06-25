[CmdletBinding()]
param(
  [switch]$NoCleanup,
  [switch]$FailFast
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$gitRoot = ((git rev-parse --show-toplevel 2>$null) | Select-Object -First 1).Trim()
if (-not $gitRoot) { throw "Not inside a git repository." }

$repoRoot = $gitRoot
$testHarnessPath = Join-Path $repoRoot "Scripts\Tests\TestHarness.ps1"
if (-not (Test-Path -LiteralPath $testHarnessPath -PathType Leaf)) {
  $payloadRoot = Join-Path $gitRoot "payload"
  $payloadHarnessPath = Join-Path $payloadRoot "Scripts\Tests\TestHarness.ps1"
  if (Test-Path -LiteralPath $payloadHarnessPath -PathType Leaf) {
    $repoRoot = $payloadRoot
    $testHarnessPath = $payloadHarnessPath
  }
}

Set-Location $repoRoot

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$resultsDir = Join-Path $repoRoot "Scripts\Tests\Test-DocsToolsResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "DocsToolsTest-$stamp.log"
$tempRoot = Join-Path $resultsDir "scratch-$stamp"
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
if (-not (Test-Path -LiteralPath $testHarnessPath -PathType Leaf)) {
  throw "Test harness not found: $testHarnessPath"
}
. $testHarnessPath

$script:DocsToolsScriptPath = Join-Path $repoRoot "Scripts\UETools\UEToolSuite.Docs.psm1"
$script:PassCount = 0
$script:FailCount = 0
$script:WarnCount = 0
$script:SkipCount = 0
$script:CleanupRan = $false
Initialize-TestHarness -LogPath $logPath -FailFast:$FailFast

function New-ScratchPath([string]$Name) {
  return (Join-Path $tempRoot $Name)
}

function Get-FreeTcpPort {
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
  $listener.Start()
  try {
    return [int]([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
  }
  finally {
    $listener.Stop()
  }
}

function New-MinimalDocsRepo {
  param([Parameter(Mandatory)][string]$Name)

  $scratchRepo = New-ScratchPath $Name
  New-Item -ItemType Directory -Force -Path (Join-Path $scratchRepo "Docs") | Out-Null
  $scratchWebsiteRoot = Join-Path $scratchRepo "website"
  New-Item -ItemType Directory -Force -Path $scratchWebsiteRoot | Out-Null

  $readmeContent = @'
---
title: Overview
slug: /
sidebar_position: 1
---

# Overview

Minimal docs root for ue-tools docs testing.
'@
  Write-Utf8NoBomFile -Path (Join-Path $scratchRepo "Docs\README.md") -Content $readmeContent

  $packageSource = Join-Path $repoRoot "website\package.json"
  if (Test-Path -LiteralPath $packageSource) {
    Copy-Item -LiteralPath $packageSource -Destination (Join-Path $scratchWebsiteRoot "package.json") -Force
  }
  $configSource = Join-Path $repoRoot "website\docusaurus.config.ts"
  if (Test-Path -LiteralPath $configSource) {
    Copy-Item -LiteralPath $configSource -Destination (Join-Path $scratchWebsiteRoot "docusaurus.config.ts") -Force
  }
  foreach ($websiteSourceRelativePath in @(
      "website\sidebars.ts",
      "website\domainCatalog.ts"
    )) {
    $websiteSourcePath = Join-Path $repoRoot $websiteSourceRelativePath
    if (-not (Test-Path -LiteralPath $websiteSourcePath -PathType Leaf)) {
      continue
    }

    $websiteDestinationPath = Join-Path $scratchWebsiteRoot ($websiteSourceRelativePath.Substring("website\".Length))
    $websiteDestinationParent = Split-Path -Path $websiteDestinationPath -Parent
    if ($websiteDestinationParent) {
      New-Item -ItemType Directory -Force -Path $websiteDestinationParent | Out-Null
    }
    Copy-Item -LiteralPath $websiteSourcePath -Destination $websiteDestinationPath -Force
  }
  $themePresetsSource = Join-Path $repoRoot "website\theme-presets"
  if (Test-Path -LiteralPath $themePresetsSource -PathType Container) {
    Copy-Item -LiteralPath $themePresetsSource -Destination (Join-Path $scratchWebsiteRoot "theme-presets") -Recurse -Force
  }
  foreach ($relativeCssPath in @(
      "website\src\css\custom.css",
      "website\src\css\suite-shell.css",
      "website\src\css\project-overrides.css",
      "website\theme-presets\active-theme.css"
    )) {
    $cssSource = Join-Path $repoRoot $relativeCssPath
    if (-not (Test-Path -LiteralPath $cssSource -PathType Leaf)) {
      continue
    }

    $cssDestination = Join-Path $scratchWebsiteRoot ($relativeCssPath.Substring("website\".Length))
    $cssDestinationParent = Split-Path -Path $cssDestination -Parent
    if ($cssDestinationParent) {
      New-Item -ItemType Directory -Force -Path $cssDestinationParent | Out-Null
    }
    Copy-Item -LiteralPath $cssSource -Destination $cssDestination -Force
  }
  $themeAssetSource = Join-Path $repoRoot "website\static\img\themes"
  if (Test-Path -LiteralPath $themeAssetSource -PathType Container) {
    $themeAssetDestination = Join-Path $scratchWebsiteRoot "static\img\themes"
    New-Item -ItemType Directory -Force -Path $themeAssetDestination | Out-Null
    Copy-Item -Path (Join-Path $themeAssetSource "*") -Destination $themeAssetDestination -Recurse -Force
  }

  return $scratchRepo
}

function New-StubToolset {
  param(
    [Parameter(Mandatory)][string]$Name,
    [string[]]$CodeExtensions = @()
  )

  $stubRoot = New-ScratchPath $Name
  New-Item -ItemType Directory -Force -Path $stubRoot | Out-Null

  $commandLog = Join-Path $stubRoot "stub-commands.log"
  Write-Utf8NoBomFile -Path $commandLog -Content ""

  $codeLines = @(
    "@echo off"
    'if "%~1"=="--list-extensions" ('
  )
  foreach ($extensionId in @($CodeExtensions)) {
    $codeLines += "  echo $extensionId"
  }
  $codeLines += @(
    "  exit /b 0"
    ")"
    '>> "%STUB_LOG%" echo code %*'
    "exit /b 0"
  )
  Write-Utf8NoBomFile -Path (Join-Path $stubRoot "code.cmd") -Content ($codeLines -join "`r`n")

  $npmLines = @(
    "@echo off"
    '>> "%STUB_LOG%" echo npm %*'
    'if "%~1"=="run" if "%~2"=="start" if /i "%STUB_NPM_START_MODE%"=="sleep" ('
    '  ping -n 60 127.0.0.1 >nul'
    ')'
    "exit /b 0"
  )
  Write-Utf8NoBomFile -Path (Join-Path $stubRoot "npm.cmd") -Content ($npmLines -join "`r`n")

  return [pscustomobject]@{
    StubRoot = $stubRoot
    CommandLog = $commandLog
  }
}

function Invoke-DocsToolsCommand {
  param(
    [Parameter(Mandatory)][string]$ScratchRepoRoot,
    [Parameter(Mandatory)][string[]]$CliArgs,
    [Parameter(Mandatory)]$Toolset,
    [Parameter(Mandatory)][string]$SandboxRoot,
    [hashtable]$ExtraEnv = @{}
  )

  $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
  $sandboxLocalAppData = Join-Path $SandboxRoot "LocalAppData"
  $sandboxUserProfile = Join-Path $SandboxRoot "UserProfile"
  $sandboxTemp = Join-Path $SandboxRoot "Temp"
  foreach ($path in @($sandboxLocalAppData, $sandboxUserProfile, $sandboxTemp)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
  }

  $pathSegments = @(
    $Toolset.StubRoot,
    (Join-Path $env:SystemRoot "System32"),
    $env:SystemRoot
  ) | Where-Object { $_ -and $_.Trim() -ne "" }

  $previousEnv = @{
    Path = $env:Path
    LOCALAPPDATA = $env:LOCALAPPDATA
    USERPROFILE = $env:USERPROFILE
    TEMP = $env:TEMP
    TMP = $env:TMP
    STUB_LOG = $env:STUB_LOG
    STUB_NPM_START_MODE = $env:STUB_NPM_START_MODE
  }

  try {
    $env:Path = ($pathSegments -join ';')
    $env:LOCALAPPDATA = $sandboxLocalAppData
    $env:USERPROFILE = $sandboxUserProfile
    $env:TEMP = $sandboxTemp
    $env:TMP = $sandboxTemp
    $env:STUB_LOG = $Toolset.CommandLog
    foreach ($entry in $ExtraEnv.GetEnumerator()) {
      Set-Item -Path ("Env:{0}" -f $entry.Key) -Value ([string]$entry.Value)
    }

    $coreModulePath = Join-Path (Split-Path -Parent $script:DocsToolsScriptPath) "UEToolSuite.Core.psm1"
    $previousAutoRunFlag = $env:UE_TOOLS_DOCS_RUNTIME_NO_AUTORUN
    $env:UE_TOOLS_DOCS_RUNTIME_NO_AUTORUN = '1'
    try {
      Import-Module -Name $coreModulePath -Force -DisableNameChecking | Out-Null
      $scriptsRoot = Split-Path -Parent (Split-Path -Parent $script:DocsToolsScriptPath)
      if (Get-Command -Name 'Set-UEToolSuiteRuntimeContext' -CommandType Function -ErrorAction SilentlyContinue) {
        Set-UEToolSuiteRuntimeContext -ScriptsRoot $scriptsRoot -StateKey 'docs-tools-test' -LogPrefix '[Docs]'
      }

      $docsModule = Import-Module -Name $script:DocsToolsScriptPath -Force -DisableNameChecking -PassThru
      $repoResolver = Get-Command -Name 'Get-DocsToolsRepoRoot' -Module $docsModule.Name -CommandType Function -ErrorAction SilentlyContinue
      if (-not $repoResolver) { throw 'Get-DocsToolsRepoRoot was not exported by docs module.' }
      $entrypoint = Get-Command -Name 'Invoke-DocsToolsMain' -Module $docsModule.Name -CommandType Function -ErrorAction SilentlyContinue
      if (-not $entrypoint) { throw 'Invoke-DocsToolsMain was not exported by docs module.' }
      $resolvedRepoRoot = & $repoResolver.Name -ExplicitRepoRoot $ScratchRepoRoot
      $output = @(& $entrypoint.Name -ResolvedRepoRoot $resolvedRepoRoot -CommandArguments $CliArgs 2>&1)
      $exitCode = 0
    }
    catch {
      $output = @("Error: $($_.Exception.Message)")
      $exitCode = 1
    }
    finally {
      if ($null -eq $previousAutoRunFlag) {
        Remove-Item Env:UE_TOOLS_DOCS_RUNTIME_NO_AUTORUN -ErrorAction SilentlyContinue
      }
      else {
        $env:UE_TOOLS_DOCS_RUNTIME_NO_AUTORUN = $previousAutoRunFlag
      }
    }

    return [pscustomobject]@{
      ExitCode = $exitCode
      OutputLines = @($output | ForEach-Object { "$_" })
      OutputText = (($output | ForEach-Object { "$_" }) -join "`n")
      SandboxLocalAppData = $sandboxLocalAppData
      SandboxUserProfile = $sandboxUserProfile
      SandboxTemp = $sandboxTemp
    }
  }
  finally {
    $env:Path = $previousEnv.Path
    $env:LOCALAPPDATA = $previousEnv.LOCALAPPDATA
    $env:USERPROFILE = $previousEnv.USERPROFILE
    $env:TEMP = $previousEnv.TEMP
    $env:TMP = $previousEnv.TMP
    $env:STUB_LOG = $previousEnv.STUB_LOG
    $env:STUB_NPM_START_MODE = $previousEnv.STUB_NPM_START_MODE
  }
}

function Restore-State {
  if ($script:CleanupRan) { return }
  $script:CleanupRan = $true

  if ($NoCleanup) {
    Write-Log "[WARN] Cleanup - NoCleanup set; leaving scratch files in place." Yellow
    return
  }

  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

try {
  Step "Docs Tools Tests ($stamp)"
  Write-Log "Repo: $repoRoot" Cyan
  Write-Log "Log : $logPath" Cyan

  Assert-Condition "script exists" (Test-Path -LiteralPath $script:DocsToolsScriptPath) "DocsTools runtime found"

  Step "Case 1: Help output lists the supported commands"
  $helpRepo = New-MinimalDocsRepo -Name "repo-help"
  $helpToolset = New-StubToolset -Name "toolset-help"
  $helpResult = Invoke-DocsToolsCommand -ScratchRepoRoot $helpRepo -CliArgs @("help") -Toolset $helpToolset -SandboxRoot (New-ScratchPath "sandbox-help")
  Assert-Condition "case1 help exits cleanly" ($helpResult.ExitCode -eq 0) "exit code=0" "exit code=$($helpResult.ExitCode)"
  Assert-TextContains "case1 help shows header" $helpResult.OutputText "UE project docs automation."
  Assert-TextContains "case1 help shows section alias" $helpResult.OutputText "new-section, create-section"
  Assert-TextContains "case1 help shows page alias" $helpResult.OutputText "new-page, create-page"
  Assert-TextContains "case1 help shows reorder" $helpResult.OutputText "reorder"
  Assert-TextContains "case1 help shows start" $helpResult.OutputText "start"
  Assert-TextContains "case1 help mentions inline docs editing" $helpResult.OutputText "Inline page editing is available directly on docs pages"
  Assert-TextContains "case1 help shows docusaurus passthrough" $helpResult.OutputText "docusaurus <args...>"
  Assert-TextContains "case1 help shows help syntax" $helpResult.OutputText "help [command]"

  Step "Case 1b: detailed help shows Docusaurus metadata options"
  $helpSectionResult = Invoke-DocsToolsCommand -ScratchRepoRoot $helpRepo -CliArgs @("help", "new-section") -Toolset $helpToolset -SandboxRoot (New-ScratchPath "sandbox-help-new-section")
  Assert-Condition "case1b detailed help exits cleanly" ($helpSectionResult.ExitCode -eq 0) "exit code=0" "exit code=$($helpSectionResult.ExitCode)"
  Assert-TextContains "case1b help shows generated-index" $helpSectionResult.OutputText "-LinkType <doc|generated-index|none>"
  Assert-TextContains "case1b help shows generated index slug" $helpSectionResult.OutputText "-GeneratedIndexSlug <path>"
  Assert-TextContains "case1b help shows category json" $helpSectionResult.OutputText "-CategoryJson <key=json>"
  Assert-TextContains "case1b help shows detailed syntax" $helpSectionResult.OutputText "ue-tools docs new-section <SectionPath> [options]"

  Step "Case 1c: missing positional arguments return friendly command errors"
  $friendlyErrorRepo = New-MinimalDocsRepo -Name "repo-friendly-errors"
  $friendlyErrorToolset = New-StubToolset -Name "toolset-friendly-errors"
  $reorderMissingTargetResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $friendlyErrorRepo `
    -CliArgs @("reorder") `
    -Toolset $friendlyErrorToolset `
    -SandboxRoot (New-ScratchPath "sandbox-friendly-errors-reorder-target")
  Assert-Condition "case1c reorder without target exits nonzero" ($reorderMissingTargetResult.ExitCode -ne 0) "nonzero exit code returned" "exit code=$($reorderMissingTargetResult.ExitCode)"
  Assert-TextContains "case1c reorder without target names the missing parameter" $reorderMissingTargetResult.OutputText "Error: TargetPath is required."
  Assert-TextNotContains "case1c reorder without target avoids binder noise" $reorderMissingTargetResult.OutputText "Cannot bind argument to parameter 'Args'"

  $reorderMissingPositionResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $friendlyErrorRepo `
    -CliArgs @("reorder", "Art-Source") `
    -Toolset $friendlyErrorToolset `
    -SandboxRoot (New-ScratchPath "sandbox-friendly-errors-reorder-position")
  Assert-Condition "case1c reorder without position exits nonzero" ($reorderMissingPositionResult.ExitCode -ne 0) "nonzero exit code returned" "exit code=$($reorderMissingPositionResult.ExitCode)"
  Assert-TextContains "case1c reorder without position names the missing parameter" $reorderMissingPositionResult.OutputText "Error: Position is required."
  Assert-TextNotContains "case1c reorder without position avoids binder noise" $reorderMissingPositionResult.OutputText "Cannot bind argument to parameter 'Args'"

  Step "Case 1d: theme list shows available website themes"
  $themeListRepo = New-MinimalDocsRepo -Name "repo-theme-list"
  $themeListToolset = New-StubToolset -Name "toolset-theme-list"
  $themeListResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $themeListRepo `
    -CliArgs @("theme", "list") `
    -Toolset $themeListToolset `
    -SandboxRoot (New-ScratchPath "sandbox-theme-list")
  Assert-Condition "case1d theme list exits cleanly" ($themeListResult.ExitCode -eq 0) "exit code=0" "exit code=$($themeListResult.ExitCode)"
  Assert-TextContains "case1d theme list includes neutral" $themeListResult.OutputText "- neutral:"
  Assert-TextContains "case1d theme list includes ocean" $themeListResult.OutputText "- ocean:"
  Assert-TextContains "case1d theme list includes graphite" $themeListResult.OutputText "- graphite:"
  Assert-TextContains "case1d theme list includes forest" $themeListResult.OutputText "- forest:"
  Assert-TextContains "case1d theme list includes amber" $themeListResult.OutputText "- amber:"
  Assert-TextContains "case1d theme list includes violet" $themeListResult.OutputText "- violet:"
  Assert-TextContains "case1d theme list includes cobalt" $themeListResult.OutputText "- cobalt:"
  Assert-TextContains "case1d theme list includes teal" $themeListResult.OutputText "- teal:"
  Assert-TextContains "case1d theme list includes jade" $themeListResult.OutputText "- jade:"
  Assert-TextContains "case1d theme list includes indigo" $themeListResult.OutputText "- indigo:"
  Assert-TextContains "case1d theme list includes crimson" $themeListResult.OutputText "- crimson:"
  Assert-TextContains "case1d theme list includes rose" $themeListResult.OutputText "- rose:"
  Assert-TextContains "case1d theme list includes copper" $themeListResult.OutputText "- copper:"
  Assert-TextContains "case1d theme list includes slate" $themeListResult.OutputText "- slate:"
  $themeListMatches = [regex]::Matches($themeListResult.OutputText, '(?m)^-\s+[a-z0-9-]+:')
  Assert-Condition "case1d theme list reports 14 presets" ($themeListMatches.Count -eq 14) "theme count=14" "theme count=$($themeListMatches.Count)"

  Step "Case 1e: theme apply requires managed marker unless explicitly adopted"
  $themeGuardRepo = New-MinimalDocsRepo -Name "repo-theme-guard"
  $themeGuardToolset = New-StubToolset -Name "toolset-theme-guard"
  $themeGuardResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $themeGuardRepo `
    -CliArgs @("theme", "apply", "ocean") `
    -Toolset $themeGuardToolset `
    -SandboxRoot (New-ScratchPath "sandbox-theme-guard")
  Assert-Condition "case1e unmanaged theme apply exits nonzero" ($themeGuardResult.ExitCode -ne 0) "exit code=$($themeGuardResult.ExitCode)" "expected non-zero exit code"
  Assert-TextContains "case1e unmanaged theme apply guidance" $themeGuardResult.OutputText "Website is unmanaged."

  Step "Case 1f: theme apply can adopt existing website and update branding files"
  $themeAdoptRepo = New-MinimalDocsRepo -Name "repo-theme-adopt"
  $themeAdoptToolset = New-StubToolset -Name "toolset-theme-adopt"
  $themeLogoPath = Join-Path (New-ScratchPath "assets-theme-adopt") "project-logo.svg"
  New-Item -ItemType Directory -Force -Path (Split-Path -Path $themeLogoPath -Parent) | Out-Null
  Write-Utf8NoBomFile -Path $themeLogoPath -Content @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
  <rect width="16" height="16" fill="#0d7ea2"/>
</svg>
'@
  $themeAdoptResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $themeAdoptRepo `
    -CliArgs @("theme", "apply", "ocean", "-LogoPath", $themeLogoPath, "--adopt-existing") `
    -Toolset $themeAdoptToolset `
    -SandboxRoot (New-ScratchPath "sandbox-theme-adopt")
  Assert-Condition "case1f adopt theme apply exits cleanly" ($themeAdoptResult.ExitCode -eq 0) "exit code=0" "exit code=$($themeAdoptResult.ExitCode)"
  Assert-TextContains "case1f adopt message emitted" $themeAdoptResult.OutputText "Adopted existing website"
  Assert-TextContains "case1f apply message emitted" $themeAdoptResult.OutputText "Applied website theme 'ocean'."
  Assert-TextContains "case1f custom css keeps theme shell imports" (Get-Content -LiteralPath (Join-Path $themeAdoptRepo "website\src\css\custom.css") -Raw) "@import '../../theme-presets/active-theme.css';"
  Assert-TextContains "case1f active theme css updated to ocean palette" (Get-Content -LiteralPath (Join-Path $themeAdoptRepo "website\theme-presets\active-theme.css") -Raw) "--ifm-color-primary: #0d7ea2;"
  $themeAdoptConfig = Get-Content -LiteralPath (Join-Path $themeAdoptRepo "website\docusaurus.config.ts") -Raw
  Assert-TextContains "case1f config stores updated theme id" $themeAdoptConfig "suiteThemeId: 'ocean'"
  Assert-TextContains "case1f custom logo rewires navbar icon" $themeAdoptConfig "src: 'img/branding/project-logo.svg'"
  Assert-TextContains "case1f custom logo rewires favicon icon" $themeAdoptConfig "favicon: 'img/branding/project-logo.svg'"
  Assert-TextContains "case1f custom logo rewires social card image" $themeAdoptConfig "image: 'img/branding/project-logo.svg'"
  Assert-Condition "case1f ownership marker written" (Test-Path -LiteralPath (Join-Path $themeAdoptRepo "website\.ue-tools\ownership.json") -PathType Leaf) "ownership marker present"

  Step "Case 1g: editor API host serves tree/reorder/save endpoints without argument conversion failures"
  $apiHostRepo = New-MinimalDocsRepo -Name "repo-editor-api-host"
  $apiHostPort = Get-FreeTcpPort
  $apiHostScriptPath = Join-Path $repoRoot "Scripts\UETools\DocsEditorApiHost.ps1"
  if (-not (Test-Path -LiteralPath $apiHostScriptPath -PathType Leaf)) {
    $script:SkipCount += 1
    Write-Log "[SKIP] case1g editor API host script is not present in this payload build." Yellow
  }
  else {
  $apiHostOutPath = Join-Path (New-ScratchPath "api-host") "stdout.log"
  $apiHostErrPath = Join-Path (Split-Path -Parent $apiHostOutPath) "stderr.log"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $apiHostOutPath) | Out-Null
  $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
  $apiHostArgs = @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy Bypass",
    ("-File `"{0}`"" -f $apiHostScriptPath),
    ("-RepoRoot `"{0}`"" -f $apiHostRepo),
    ("-DocsModulePath `"{0}`"" -f $script:DocsToolsScriptPath),
    ("-Port {0}" -f $apiHostPort)
  ) -join ' '
  $apiHostProcess = Start-Process `
    -FilePath $pwshPath `
    -ArgumentList $apiHostArgs `
    -PassThru `
    -RedirectStandardOutput $apiHostOutPath `
    -RedirectStandardError $apiHostErrPath

  $apiHostReady = $false
  try {
    for ($i = 0; $i -lt 30; $i++) {
      try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/health" -Method Get -TimeoutSec 2
        if ($health.ok) {
          $apiHostReady = $true
          break
        }
      }
      catch {
      }
      Start-Sleep -Milliseconds 200
    }
    $apiHostHealthFailure = "health endpoint did not report ready"
    if (-not $apiHostReady) {
      $stderrSnippet = if (Test-Path -LiteralPath $apiHostErrPath -PathType Leaf) {
        (Get-Content -LiteralPath $apiHostErrPath -Raw)
      }
      else {
        "<stderr log not found>"
      }
      $stdoutSnippet = if (Test-Path -LiteralPath $apiHostOutPath -PathType Leaf) {
        (Get-Content -LiteralPath $apiHostOutPath -Raw)
      }
      else {
        "<stdout log not found>"
      }
      $apiHostHealthFailure = "health endpoint did not report ready. stderr=$stderrSnippet stdout=$stdoutSnippet"
    }
    Assert-Condition "case1g api host health endpoint ready" $apiHostReady "health ok" $apiHostHealthFailure
    Assert-Condition "case1g health reports application identity" ([string]$health.applicationId -eq "UEToolSuiteDocsEditorApi") "application id matches" "applicationId=$([string]$health.applicationId)"
    Assert-Condition "case1g health reports api version" ([int]$health.apiVersion -eq 2) "apiVersion=2" "apiVersion=$([string]$health.apiVersion)"
    Assert-Condition "case1g health reports process id" ([int]$health.processId -gt 0) "process id reported" "processId=$([string]$health.processId)"
    Assert-Condition "case1g health reports repo root" ([string]$health.repoRoot -eq $apiHostRepo) "repo root matches" "repoRoot=$([string]$health.repoRoot)"
    Assert-Condition "case1g health reports docs root" ([string]$health.docsRoot -eq (Join-Path $apiHostRepo 'Docs')) "docs root matches" "docsRoot=$([string]$health.docsRoot)"
    Assert-Condition "case1g health reports startup timestamp" (-not [string]::IsNullOrWhiteSpace([string]$health.startedAt)) "startedAt reported" "startedAt missing"

    if ($apiHostReady) {
      $tree = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/tree" -Method Get -TimeoutSec 5
      Assert-Condition "case1g api tree endpoint returns ok payload" ($tree.ok -eq $true) "tree ok=true" "tree response did not set ok=true"
      Assert-Condition "case1g api tree includes docs root entries" (@($tree.tree.children).Count -gt 0) "children count > 0" "children count=0"

      $content = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/content?path=README.md" -Method Get -TimeoutSec 5
      Assert-Condition "case1g api content returns ok payload" ($content.ok -eq $true) "content ok=true" "content response did not set ok=true"
      Assert-TextContains "case1g api content includes front matter title" ([string]$content.content.content) "title: Overview"

      $saveBody = @{
        path = "README.md"
        content = [string]$content.content.content
        expectedHash = [string]$content.content.hash
      } | ConvertTo-Json -Depth 8
      $save = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/content" -Method Post -ContentType "application/json" -Body $saveBody -TimeoutSec 5
      Assert-Condition "case1g api save endpoint returns ok payload" ($save.ok -eq $true) "save ok=true" "save response did not set ok=true"

      $createSectionBody = @{
        parentPath = ""
        sectionName = "Guides Space"
        title = "Guides Space"
      } | ConvertTo-Json -Depth 6
      $createSection = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/create/section" -Method Post -ContentType "application/json" -Body $createSectionBody -TimeoutSec 5
      Assert-Condition "case1g api create section endpoint returns ok payload" ($createSection.ok -eq $true) "create section ok=true" "create section response did not set ok=true"

      $createSetupPageBody = @{
        sectionPath = ""
        pageName = "Setup"
        title = "Setup"
      } | ConvertTo-Json -Depth 6
      $createSetupPage = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/create/page" -Method Post -ContentType "application/json" -Body $createSetupPageBody -TimeoutSec 5
      Assert-Condition "case1g api seed setup page endpoint returns ok payload" ($createSetupPage.ok -eq $true) "create setup page ok=true" "create setup page response did not set ok=true"

      $sidebarsPath = Join-Path $apiHostRepo "website\sidebars.ts"
      if (Test-Path -LiteralPath $sidebarsPath -PathType Leaf) {
        $sidebarsBeforeSeed = Get-Content -LiteralPath $sidebarsPath -Raw
        $sidebarsAfterSeed = if ($sidebarsBeforeSeed -notmatch "docId:\s*'Setup'") {
          $sidebarsBeforeSeed.TrimEnd() + "`r`n`r`nexport const testSidebarReference = [{type: 'doc', docId: 'Setup'}];`r`n"
        }
        else {
          $sidebarsBeforeSeed
        }
        if ($sidebarsAfterSeed -ne $sidebarsBeforeSeed) {
          Write-Utf8NoBomFile -Path $sidebarsPath -Content $sidebarsAfterSeed
        }
        Assert-TextContains "case1g seed setup sidebar docId reference" $sidebarsAfterSeed "docId: 'Setup'"
      }

      $moveReferencedPageBody = @{
        sourcePath = "Setup"
        destinationParentPath = "Guides Space"
        insertIndex = 0
      } | ConvertTo-Json -Depth 6
      $moveReferencedPage = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/move" -Method Post -ContentType "application/json" -Body $moveReferencedPageBody -TimeoutSec 5
      Assert-Condition "case1g api move handles navbar docId references" ($moveReferencedPage.ok -eq $true) "move referenced page ok=true" "move referenced page response did not set ok=true"
      $sidebarsAfterReferencedMove = Get-Content -LiteralPath (Join-Path $apiHostRepo "website\sidebars.ts") -Raw
      Assert-TextContains "case1g api move rewrites sidebar docId reference after path move" $sidebarsAfterReferencedMove "docId: 'Guides Space/Setup'"
      Assert-TextNotContains "case1g api move removes stale sidebar docId reference" $sidebarsAfterReferencedMove "docId: 'Setup'"
      $movedSetupContent = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/content?path=Guides%20Space%2FSetup.md" -Method Get -TimeoutSec 5
      Assert-TextContains "case1g api move keeps referenced page slug stable" ([string]$movedSetupContent.content.content) "slug: /setup"

      $createPageBody = @{
        sectionPath = ""
        pageName = "Notes"
        title = "Notes"
      } | ConvertTo-Json -Depth 6
      $createPage = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/create/page" -Method Post -ContentType "application/json" -Body $createPageBody -TimeoutSec 5
      Assert-Condition "case1g api create page endpoint returns ok payload" ($createPage.ok -eq $true) "create page ok=true" "create page response did not set ok=true"

      $sluglessNotesPath = Join-Path $apiHostRepo "Docs\Notes.md"
      $sluglessNotesContent = Get-Content -LiteralPath $sluglessNotesPath -Raw
      $sluglessNotesContent = [regex]::Replace($sluglessNotesContent, "(?m)^\s*slug\s*:\s*.*(?:\r?\n)?", "")
      Write-Utf8NoBomFile -Path $sluglessNotesPath -Content $sluglessNotesContent

      $rootContentBeforeMove = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/content?path=README.md" -Method Get -TimeoutSec 5
      $rootContentWithLink = ([string]$rootContentBeforeMove.content.content).TrimEnd() + "`n`n[Notes](./Notes.md)`n"
      $saveRootLinkBody = @{
        path = "README.md"
        content = $rootContentWithLink
        expectedHash = [string]$rootContentBeforeMove.content.hash
      } | ConvertTo-Json -Depth 8
      $saveRootLink = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/content" -Method Post -ContentType "application/json" -Body $saveRootLinkBody -TimeoutSec 5
      Assert-Condition "case1g api save endpoint preserves a markdown file reference" ($saveRootLink.ok -eq $true) "save link ok=true" "save link response did not set ok=true"

      $moveBody = @{
        sourcePath = "Notes"
        destinationParentPath = "Guides Space"
        insertIndex = 0
      } | ConvertTo-Json -Depth 6
      $move = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/move" -Method Post -ContentType "application/json" -Body $moveBody -TimeoutSec 5
      Assert-Condition "case1g api move endpoint returns ok payload" ($move.ok -eq $true) "move ok=true" "move response did not set ok=true"
      Assert-TextContains "case1g api move endpoint returns moved docs path" ([string]$move.result.path) "Guides Space/Notes"

      $movedPageContent = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/content?path=Guides%20Space%2FNotes.md" -Method Get -TimeoutSec 5
      Assert-TextContains "case1g api move preserves moved page slug" ([string]$movedPageContent.content.content) "slug: /notes"
      $rootContentAfterPageMove = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/content?path=README.md" -Method Get -TimeoutSec 5
      Assert-TextContains "case1g api move rewrites links to moved page using stable docs route" ([string]$rootContentAfterPageMove.content.content) "[Notes](/docs/notes)"
      $staleUnwrappedLinkContent = ([string]$rootContentAfterPageMove.content.content).Replace("[Notes](/docs/notes)", "[Notes](./Guides%20Space/Notes.md)")
      $saveStaleLinkBody = @{
        path = "README.md"
        content = $staleUnwrappedLinkContent
        expectedHash = [string]$rootContentAfterPageMove.content.hash
      } | ConvertTo-Json -Depth 8
      $saveStaleLink = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/content" -Method Post -ContentType "application/json" -Body $saveStaleLinkBody -TimeoutSec 5
      Assert-Condition "case1g api save endpoint accepts url-encoded moved-page link fixture" ($saveStaleLink.ok -eq $true) "save stale link ok=true" "save stale link response did not set ok=true"

      $createArchiveSectionBody = @{
        parentPath = ""
        sectionName = "Archive"
        title = "Archive"
      } | ConvertTo-Json -Depth 6
      $createArchiveSection = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/create/section" -Method Post -ContentType "application/json" -Body $createArchiveSectionBody -TimeoutSec 5
      Assert-Condition "case1g api create second section endpoint returns ok payload" ($createArchiveSection.ok -eq $true) "create section ok=true" "create second section response did not set ok=true"

      $moveSectionBody = @{
        sourcePath = "Guides Space"
        destinationParentPath = "Archive"
        insertIndex = 1
      } | ConvertTo-Json -Depth 6
      $moveSection = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/move" -Method Post -ContentType "application/json" -Body $moveSectionBody -TimeoutSec 5
      Assert-Condition "case1g api nested section move endpoint returns ok payload" ($moveSection.ok -eq $true) "move section ok=true" "move section response did not set ok=true"
      Assert-TextContains "case1g api nested section move returns moved docs path" ([string]$moveSection.result.path) "Archive/Guides Space"

      $nestedPageContent = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/content?path=Archive%2FGuides%20Space%2FNotes.md" -Method Get -TimeoutSec 5
      Assert-TextContains "case1g api nested section move preserves child page slug" ([string]$nestedPageContent.content.content) "slug: /notes"

      $nestedSectionReadme = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/content?path=Archive%2FGuides%20Space%2FREADME.md" -Method Get -TimeoutSec 5
      Assert-TextContains "case1g api nested section move preserves section readme slug" ([string]$nestedSectionReadme.content.content) "slug: /guides-space"
      $rootContentAfterSectionMove = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/content?path=README.md" -Method Get -TimeoutSec 5
      Assert-TextContains "case1g api nested section move preserves stable route links" ([string]$rootContentAfterSectionMove.content.content) "[Notes](/docs/notes)"
    }
  }
  finally {
    if ($apiHostProcess -and -not $apiHostProcess.HasExited) {
      Stop-Process -Id $apiHostProcess.Id -Force -ErrorAction SilentlyContinue
    }
  }
  }

  Step "Case 1h: cross-domain move rewrites known displayed_sidebar values and preserves destination landing docs"
  $crossDomainRepo = New-MinimalDocsRepo -Name "repo-editor-cross-domain"
  $crossDomainPort = Get-FreeTcpPort
  $crossDomainApiHostScriptPath = Join-Path $repoRoot "Scripts\UETools\DocsEditorApiHost.ps1"
  if (-not (Test-Path -LiteralPath $crossDomainApiHostScriptPath -PathType Leaf)) {
    $script:SkipCount += 1
    Write-Log "[SKIP] case1h editor API host script is not present in this payload build." Yellow
  }
  else {
    New-Item -ItemType Directory -Force -Path (Join-Path $crossDomainRepo "Docs\DomainA\PopulatedSection") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $crossDomainRepo "Docs\DomainB") | Out-Null
    Write-Utf8NoBomFile -Path (Join-Path $crossDomainRepo "Docs\_domains.json") -Content @'
{
  "schemaVersion": 1,
  "domains": [
    {
      "key": "DomainA",
      "dirName": "DomainA",
      "sidebarId": "domain-a-sidebar",
      "label": "Domain A",
      "position": 10,
      "landingDoc": "DomainA/README",
      "showLandingInSidebar": false,
      "ownedRoots": ["DomainA"],
      "ownedDocs": [],
      "catchAll": false
    },
    {
      "key": "DomainB",
      "dirName": "DomainB",
      "sidebarId": "domain-b-sidebar",
      "label": "Domain B",
      "position": 20,
      "landingDoc": "DomainB/README",
      "showLandingInSidebar": false,
      "ownedRoots": ["DomainB"],
      "ownedDocs": [],
      "catchAll": false
    }
  ]
}
'@
    Write-Utf8NoBomFile -Path (Join-Path $crossDomainRepo "Docs\DomainA\README.md") -Content @'
---
title: Domain A
slug: /domain-a
sidebar_position: 1
displayed_sidebar: domain-a-sidebar
---

# Domain A
'@
    Write-Utf8NoBomFile -Path (Join-Path $crossDomainRepo "Docs\DomainA\_category_.json") -Content @'
{
  "label": "Domain A",
  "position": 1,
  "link": {
    "type": "doc",
    "id": "DomainA/README"
  }
}
'@
    Write-Utf8NoBomFile -Path (Join-Path $crossDomainRepo "Docs\DomainB\README.md") -Content @'
---
title: Domain B
slug: /domain-b
sidebar_position: 1
displayed_sidebar: domain-b-sidebar
---

# Domain B
'@
    Write-Utf8NoBomFile -Path (Join-Path $crossDomainRepo "Docs\DomainB\_category_.json") -Content @'
{
  "label": "Domain B",
  "position": 1,
  "link": {
    "type": "doc",
    "id": "DomainB/README"
  }
}
'@
    Write-Utf8NoBomFile -Path (Join-Path $crossDomainRepo "Docs\DomainA\PopulatedSection\README.md") -Content @'
---
title: Populated Section
slug: /domain-a/populated-section
sidebar_position: 1
displayed_sidebar: domain-a-sidebar
description: Keep this description
---

# Populated Section

[Child](./Child.mdx)
'@
    Write-Utf8NoBomFile -Path (Join-Path $crossDomainRepo "Docs\DomainA\PopulatedSection\Child.mdx") -Content @'
---
title: Child
slug: /domain-a/populated-section/child
sidebar_position: 2
displayed_sidebar: domain-a-sidebar
unlisted: true
sidebar_label: Child Label
---

# Child

[Back](./README.md)
'@
    Write-Utf8NoBomFile -Path (Join-Path $crossDomainRepo "Docs\DomainA\PopulatedSection\NoSidebar.md") -Content @'
---
title: No Sidebar
slug: /domain-a/populated-section/no-sidebar
sidebar_position: 3
pagination_label: Keep pagination label
---

# No Sidebar
'@
    Write-Utf8NoBomFile -Path (Join-Path $crossDomainRepo "Docs\DomainA\PopulatedSection\CustomSidebar.md") -Content @'
---
title: Custom Sidebar
slug: /domain-a/populated-section/custom-sidebar
sidebar_position: 4
displayed_sidebar: custom-docs-sidebar
sidebar_class_name: custom-sidebar-class
---

# Custom Sidebar
'@
    Write-Utf8NoBomFile -Path (Join-Path $crossDomainRepo "Docs\DomainA\PopulatedSection\_category_.json") -Content @'
{
  "label": "Populated Section",
  "position": 2,
  "link": {
    "type": "doc",
    "id": "DomainA/PopulatedSection/README"
  }
}
'@

    $crossDomainOutPath = Join-Path (New-ScratchPath "api-host-cross-domain") "stdout.log"
    $crossDomainErrPath = Join-Path (Split-Path -Parent $crossDomainOutPath) "stderr.log"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $crossDomainOutPath) | Out-Null
    $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
    $crossDomainApiHostArgs = @(
      "-NoLogo",
      "-NoProfile",
      "-ExecutionPolicy Bypass",
      ("-File `"{0}`"" -f $crossDomainApiHostScriptPath),
      ("-RepoRoot `"{0}`"" -f $crossDomainRepo),
      ("-DocsModulePath `"{0}`"" -f $script:DocsToolsScriptPath),
      ("-Port {0}" -f $crossDomainPort)
    ) -join ' '
    $crossDomainApiHostProcess = Start-Process `
      -FilePath $pwshPath `
      -ArgumentList $crossDomainApiHostArgs `
      -PassThru `
      -RedirectStandardOutput $crossDomainOutPath `
      -RedirectStandardError $crossDomainErrPath

    $crossDomainApiHostReady = $false
    try {
      for ($i = 0; $i -lt 30; $i++) {
        try {
          $crossDomainHealth = Invoke-RestMethod -Uri "http://127.0.0.1:$crossDomainPort/health" -Method Get -TimeoutSec 2
          if ($crossDomainHealth.ok) {
            $crossDomainApiHostReady = $true
            break
          }
        }
        catch {
        }
        Start-Sleep -Milliseconds 200
      }
      $crossDomainHealthFailure = "health endpoint did not report ready"
      if (-not $crossDomainApiHostReady) {
        $crossDomainStderrSnippet = if (Test-Path -LiteralPath $crossDomainErrPath -PathType Leaf) {
          (Get-Content -LiteralPath $crossDomainErrPath -Raw)
        }
        else {
          "<stderr log not found>"
        }
        $crossDomainStdoutSnippet = if (Test-Path -LiteralPath $crossDomainOutPath -PathType Leaf) {
          (Get-Content -LiteralPath $crossDomainOutPath -Raw)
        }
        else {
          "<stdout log not found>"
        }
        $crossDomainHealthFailure = "health endpoint did not report ready. stderr=$crossDomainStderrSnippet stdout=$crossDomainStdoutSnippet"
      }
      Assert-Condition "case1h api host health endpoint ready" $crossDomainApiHostReady "health ok" $crossDomainHealthFailure

      if ($crossDomainApiHostReady) {
        $crossDomainMoveBody = @{
          sourcePath = "DomainA/PopulatedSection"
          destinationDomainPath = "DomainB"
          destinationParentPath = "DomainB"
          insertIndex = 0
        } | ConvertTo-Json -Depth 6
        $crossDomainMove = Invoke-RestMethod -Uri "http://127.0.0.1:$crossDomainPort/api/move" -Method Post -ContentType "application/json" -Body $crossDomainMoveBody -TimeoutSec 5
        Assert-Condition "case1h cross-domain move endpoint returns ok payload" ($crossDomainMove.ok -eq $true) "move ok=true" "cross-domain move response did not set ok=true"
        Assert-TextContains "case1h cross-domain move returns moved docs path" ([string]$crossDomainMove.result.path) "DomainB/PopulatedSection"

        Assert-Condition "case1h source section removed after cross-domain move" (-not (Test-Path -LiteralPath (Join-Path $crossDomainRepo "Docs\DomainA\PopulatedSection"))) "source section removed" "source section still exists after move"
        Assert-Condition "case1h destination section exists after cross-domain move" (Test-Path -LiteralPath (Join-Path $crossDomainRepo "Docs\DomainB\PopulatedSection")) "destination section created" "destination section missing after move"

        $domainsAfterMove = Get-Content -LiteralPath (Join-Path $crossDomainRepo "Docs\_domains.json") -Raw | ConvertFrom-Json
        $domainBAfterMove = @($domainsAfterMove.domains | Where-Object { ([string]$_.key).Equals("DomainB", [System.StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
        Assert-Condition "case1h destination domain remains defined" ($null -ne $domainBAfterMove) "DomainB present" "DomainB missing from _domains.json after move"
        if ($null -ne $domainBAfterMove) {
          Assert-Condition "case1h destination landingDoc remains unchanged" ([string]$domainBAfterMove.landingDoc -eq "DomainB/README") "landingDoc=DomainB/README" "landingDoc=$([string]$domainBAfterMove.landingDoc)"
        }
        Assert-Condition "case1h destination landing doc file remains present" (Test-Path -LiteralPath (Join-Path $crossDomainRepo "Docs\DomainB\README.md") -PathType Leaf) "DomainB README present" "DomainB README missing after move"

        $movedSectionReadmeText = Get-Content -LiteralPath (Join-Path $crossDomainRepo "Docs\DomainB\PopulatedSection\README.md") -Raw
        $movedChildText = Get-Content -LiteralPath (Join-Path $crossDomainRepo "Docs\DomainB\PopulatedSection\Child.mdx") -Raw
        $movedNoSidebarText = Get-Content -LiteralPath (Join-Path $crossDomainRepo "Docs\DomainB\PopulatedSection\NoSidebar.md") -Raw
        $movedCustomSidebarText = Get-Content -LiteralPath (Join-Path $crossDomainRepo "Docs\DomainB\PopulatedSection\CustomSidebar.md") -Raw
        $movedCategoryText = Get-Content -LiteralPath (Join-Path $crossDomainRepo "Docs\DomainB\PopulatedSection\_category_.json") -Raw

        Assert-TextContains "case1h moved section readme preserves slug" $movedSectionReadmeText "slug: /domain-a/populated-section"
        Assert-TextContains "case1h moved section readme rewrites displayed_sidebar to destination domain" $movedSectionReadmeText "displayed_sidebar: domain-b-sidebar"
        Assert-TextNotContains "case1h moved section readme removes source domain displayed_sidebar" $movedSectionReadmeText "displayed_sidebar: domain-a-sidebar"
        Assert-TextContains "case1h moved section readme preserves unrelated front matter" $movedSectionReadmeText "description: Keep this description"
        Assert-TextContains "case1h moved section readme preserves relative links" $movedSectionReadmeText "[Child](./Child.mdx)"

        Assert-TextContains "case1h moved child preserves slug" $movedChildText "slug: /domain-a/populated-section/child"
        Assert-TextContains "case1h moved child rewrites displayed_sidebar recursively for mdx" $movedChildText "displayed_sidebar: domain-b-sidebar"
        Assert-TextNotContains "case1h moved child removes source domain displayed_sidebar" $movedChildText "displayed_sidebar: domain-a-sidebar"
        Assert-TextContains "case1h moved child preserves unlisted front matter" $movedChildText "unlisted: true"
        Assert-TextContains "case1h moved child preserves unrelated front matter" $movedChildText "sidebar_label: Child Label"

        Assert-TextContains "case1h moved doc without displayed_sidebar keeps it absent" $movedNoSidebarText "pagination_label: Keep pagination label"
        Assert-TextNotContains "case1h moved doc without displayed_sidebar stays absent" $movedNoSidebarText "displayed_sidebar:"

        Assert-TextContains "case1h moved doc preserves custom displayed_sidebar" $movedCustomSidebarText "displayed_sidebar: custom-docs-sidebar"
        Assert-TextContains "case1h moved doc preserves unrelated custom front matter" $movedCustomSidebarText "sidebar_class_name: custom-sidebar-class"
        Assert-TextContains "case1h move reports preserved custom displayed_sidebar" ([string]$crossDomainMove.result.warning) "custom displayed_sidebar"
        Assert-TextContains "case1h move warning names preserved custom displayed_sidebar file" ([string]$crossDomainMove.result.warning) "DomainB/PopulatedSection/CustomSidebar.md"

        Assert-TextContains "case1h moved category link rewrites to destination docId" $movedCategoryText '"id": "DomainB/PopulatedSection/README"'
        Assert-TextNotContains "case1h moved category link removes source docId" $movedCategoryText '"id": "DomainA/PopulatedSection/README"'
      }
    }
    finally {
      if ($crossDomainApiHostProcess -and -not $crossDomainApiHostProcess.HasExited) {
        Stop-Process -Id $crossDomainApiHostProcess.Id -Force -ErrorAction SilentlyContinue
      }
    }
  }

  Step "Case 1i: cross-domain move normalizes legacy sections before persisting the move"
  $legacySectionRepo = New-MinimalDocsRepo -Name "repo-editor-legacy-section"
  $legacySectionPort = Get-FreeTcpPort
  $legacySectionApiHostScriptPath = Join-Path $repoRoot "Scripts\UETools\DocsEditorApiHost.ps1"
  if (-not (Test-Path -LiteralPath $legacySectionApiHostScriptPath -PathType Leaf)) {
    $script:SkipCount += 1
    Write-Log "[SKIP] case1i editor API host script is not present in this payload build." Yellow
  }
  else {
    New-Item -ItemType Directory -Force -Path (Join-Path $legacySectionRepo "Docs\WorkflowStandards\ProjectStructure") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $legacySectionRepo "Docs\WorkflowStandards\EmptyAssets") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $legacySectionRepo "Docs\TestDomain") | Out-Null
    Write-Utf8NoBomFile -Path (Join-Path $legacySectionRepo "Docs\_domains.json") -Content @'
{
  "schemaVersion": 1,
  "domains": [
    {
      "key": "workflow-standards",
      "dirName": "WorkflowStandards",
      "sidebarId": "workflow-standards-sidebar",
      "label": "Workflow & Standards",
      "position": 10,
      "landingDoc": "WorkflowStandards/README",
      "showLandingInSidebar": false,
      "ownedRoots": ["WorkflowStandards"],
      "ownedDocs": [],
      "catchAll": false
    },
    {
      "key": "test-domain",
      "dirName": "TestDomain",
      "sidebarId": "test-domain-sidebar",
      "label": "Test Domain",
      "position": 20,
      "landingDoc": "TestDomain/README",
      "showLandingInSidebar": false,
      "ownedRoots": ["TestDomain"],
      "ownedDocs": [],
      "catchAll": false
    }
  ]
}
'@
    Write-Utf8NoBomFile -Path (Join-Path $legacySectionRepo "Docs\WorkflowStandards\README.md") -Content @'
---
title: Workflow And Standards
slug: /workflow-standards
sidebar_position: 1
displayed_sidebar: workflow-standards-sidebar
---

# Workflow And Standards
'@
    Write-Utf8NoBomFile -Path (Join-Path $legacySectionRepo "Docs\WorkflowStandards\_category_.json") -Content @'
{
  "label": "Workflow & Standards",
  "position": 1,
  "link": {
    "type": "doc",
    "id": "WorkflowStandards/README"
  }
}
'@
    Write-Utf8NoBomFile -Path (Join-Path $legacySectionRepo "Docs\WorkflowStandards\ProjectStructure\Target-Structure.md") -Content @'
---
title: Target Structure
slug: /target-structure
sidebar_position: 1
---

# Target Structure
'@
    Write-Utf8NoBomFile -Path (Join-Path $legacySectionRepo "Docs\WorkflowStandards\ProjectStructure\UE-Editor-Migration.md") -Content @'
---
title: UE Editor Migration
slug: /ue-editor-migration
sidebar_position: 2
---

# UE Editor Migration
'@
    Write-Utf8NoBomFile -Path (Join-Path $legacySectionRepo "Docs\TestDomain\README.md") -Content @'
---
title: Test Domain
slug: /test-domain
sidebar_position: 1
displayed_sidebar: test-domain-sidebar
---

# Test Domain
'@
    Write-Utf8NoBomFile -Path (Join-Path $legacySectionRepo "Docs\TestDomain\_category_.json") -Content @'
{
  "label": "Test Domain",
  "position": 1,
  "link": {
    "type": "doc",
    "id": "TestDomain/README"
  }
}
'@

    $legacySectionOutPath = Join-Path (New-ScratchPath "api-host-legacy-section") "stdout.log"
    $legacySectionErrPath = Join-Path (Split-Path -Parent $legacySectionOutPath) "stderr.log"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $legacySectionOutPath) | Out-Null
    $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
    $legacySectionApiHostArgs = @(
      "-NoLogo",
      "-NoProfile",
      "-ExecutionPolicy Bypass",
      ("-File `"{0}`"" -f $legacySectionApiHostScriptPath),
      ("-RepoRoot `"{0}`"" -f $legacySectionRepo),
      ("-DocsModulePath `"{0}`"" -f $script:DocsToolsScriptPath),
      ("-Port {0}" -f $legacySectionPort)
    ) -join ' '
    $legacySectionApiHostProcess = Start-Process `
      -FilePath $pwshPath `
      -ArgumentList $legacySectionApiHostArgs `
      -PassThru `
      -RedirectStandardOutput $legacySectionOutPath `
      -RedirectStandardError $legacySectionErrPath

    $legacySectionApiHostReady = $false
    try {
      for ($i = 0; $i -lt 30; $i++) {
        try {
          $legacySectionHealth = Invoke-RestMethod -Uri "http://127.0.0.1:$legacySectionPort/health" -Method Get -TimeoutSec 2
          if ($legacySectionHealth.ok) {
            $legacySectionApiHostReady = $true
            break
          }
        }
        catch {
        }
        Start-Sleep -Milliseconds 200
      }

      $legacySectionHealthFailure = "health endpoint did not report ready"
      if (-not $legacySectionApiHostReady) {
        $legacySectionStderrSnippet = if (Test-Path -LiteralPath $legacySectionErrPath -PathType Leaf) {
          (Get-Content -LiteralPath $legacySectionErrPath -Raw)
        }
        else {
          "<stderr log not found>"
        }
        $legacySectionStdoutSnippet = if (Test-Path -LiteralPath $legacySectionOutPath -PathType Leaf) {
          (Get-Content -LiteralPath $legacySectionOutPath -Raw)
        }
        else {
          "<stdout log not found>"
        }
        $legacySectionHealthFailure = "health endpoint did not report ready. stderr=$legacySectionStderrSnippet stdout=$legacySectionStdoutSnippet"
      }
      Assert-Condition "case1i api host health endpoint ready" $legacySectionApiHostReady "health ok" $legacySectionHealthFailure

      if ($legacySectionApiHostReady) {
        $sourceLegacySectionPath = Join-Path $legacySectionRepo "Docs\WorkflowStandards\ProjectStructure"
        Assert-Condition "case1i legacy source directory exists" (Test-Path -LiteralPath $sourceLegacySectionPath -PathType Container) "source directory present" "source directory missing"
        Assert-Condition "case1i legacy source directory has no category metadata" (-not (Test-Path -LiteralPath (Join-Path $sourceLegacySectionPath "_category_.json") -PathType Leaf)) "_category_.json absent" "_category_.json unexpectedly present"
        Assert-Condition "case1i legacy source directory has no readme landing doc" (-not (Test-Path -LiteralPath (Join-Path $sourceLegacySectionPath "README.md") -PathType Leaf)) "README.md absent" "README.md unexpectedly present"

        $legacyTargetHashBefore = (Get-FileHash -LiteralPath (Join-Path $sourceLegacySectionPath "Target-Structure.md") -Algorithm SHA256).Hash
        $legacyMigrationHashBefore = (Get-FileHash -LiteralPath (Join-Path $sourceLegacySectionPath "UE-Editor-Migration.md") -Algorithm SHA256).Hash
        $legacyTreeBeforeMove = Invoke-RestMethod -Uri "http://127.0.0.1:$legacySectionPort/api/tree?sidebarId=workflow-standards-sidebar" -Method Get -TimeoutSec 5
        $legacyProjectStructureNode = @($legacyTreeBeforeMove.tree.children | Where-Object { ([string]$_.path) -eq "WorkflowStandards/ProjectStructure" }) | Select-Object -First 1
        Assert-Condition "case1i api tree exposes legacy section node" ($null -ne $legacyProjectStructureNode) "ProjectStructure node present" "ProjectStructure node missing from api tree"
        if ($null -ne $legacyProjectStructureNode) {
          Assert-Condition "case1i api tree classifies legacy directory as section" ([string]$legacyProjectStructureNode.type -eq "section") "type=section" "type=$([string]$legacyProjectStructureNode.type)"
          Assert-Condition "case1i api tree legacy section path is canonical" ([string]$legacyProjectStructureNode.path -eq "WorkflowStandards/ProjectStructure") "path=WorkflowStandards/ProjectStructure" "path=$([string]$legacyProjectStructureNode.path)"
          Assert-Condition "case1i api tree lists both legacy child pages" (@($legacyProjectStructureNode.children).Count -eq 2) "child count=2" "child count=$(@($legacyProjectStructureNode.children).Count)"
          Assert-Condition "case1i api tree includes Target-Structure child" (@($legacyProjectStructureNode.children | Where-Object { ([string]$_.path) -eq "WorkflowStandards/ProjectStructure/Target-Structure.md" }).Count -eq 1) "Target-Structure child present" "Target-Structure child missing"
          Assert-Condition "case1i api tree includes UE-Editor-Migration child" (@($legacyProjectStructureNode.children | Where-Object { ([string]$_.path) -eq "WorkflowStandards/ProjectStructure/UE-Editor-Migration.md" }).Count -eq 1) "UE-Editor-Migration child present" "UE-Editor-Migration child missing"
        }

        Assert-Condition "case1i empty directory fixture exists" (Test-Path -LiteralPath (Join-Path $legacySectionRepo "Docs\WorkflowStandards\EmptyAssets") -PathType Container) "empty dir present" "empty dir missing"
        Assert-Condition "case1i api tree does not expose arbitrary empty directory as section" (@($legacyTreeBeforeMove.tree.children | Where-Object { ([string]$_.path) -eq "WorkflowStandards/EmptyAssets" }).Count -eq 0) "EmptyAssets absent from tree" "EmptyAssets unexpectedly exposed in api tree"

        $legacyMoveBody = @{
          sourcePath = "WorkflowStandards/ProjectStructure"
          destinationDomainPath = "TestDomain"
          destinationParentPath = "TestDomain"
          insertIndex = 0
        } | ConvertTo-Json -Depth 6
        $legacyMove = Invoke-RestMethod -Uri "http://127.0.0.1:$legacySectionPort/api/move" -Method Post -ContentType "application/json" -Body $legacyMoveBody -TimeoutSec 5
        Assert-Condition "case1i legacy section move endpoint returns ok payload" ($legacyMove.ok -eq $true) "move ok=true" "legacy move response did not set ok=true"
        Assert-TextContains "case1i legacy section move returns moved docs path" ([string]$legacyMove.result.path) "TestDomain/ProjectStructure"
        Assert-Condition "case1i legacy source section removed after move" (-not (Test-Path -LiteralPath $sourceLegacySectionPath)) "source section removed" "source section still exists after move"
        Assert-Condition "case1i legacy destination section exists after move" (Test-Path -LiteralPath (Join-Path $legacySectionRepo "Docs\TestDomain\ProjectStructure")) "destination section created" "destination section missing after move"
        Assert-Condition "case1i legacy destination section creates normalized category metadata" (Test-Path -LiteralPath (Join-Path $legacySectionRepo "Docs\TestDomain\ProjectStructure\_category_.json") -PathType Leaf) "_category_.json present" "destination _category_.json missing after move"
        Assert-Condition "case1i legacy destination section preserves absent readme landing doc" (-not (Test-Path -LiteralPath (Join-Path $legacySectionRepo "Docs\TestDomain\ProjectStructure\README.md") -PathType Leaf)) "README.md absent" "destination README.md was created unexpectedly"
        Assert-Condition "case1i legacy moved Target-Structure page exists" (Test-Path -LiteralPath (Join-Path $legacySectionRepo "Docs\TestDomain\ProjectStructure\Target-Structure.md") -PathType Leaf) "Target-Structure moved" "Target-Structure missing after move"
        Assert-Condition "case1i legacy moved UE-Editor-Migration page exists" (Test-Path -LiteralPath (Join-Path $legacySectionRepo "Docs\TestDomain\ProjectStructure\UE-Editor-Migration.md") -PathType Leaf) "UE-Editor-Migration moved" "UE-Editor-Migration missing after move"
        $movedLegacyCategoryText = Get-Content -LiteralPath (Join-Path $legacySectionRepo "Docs\TestDomain\ProjectStructure\_category_.json") -Raw
        Assert-TextContains "case1i legacy move writes deterministic category label" $movedLegacyCategoryText '"label": "ProjectStructure"'
        Assert-TextContains "case1i legacy move writes category position" $movedLegacyCategoryText '"position":'
        Assert-TextNotContains "case1i legacy move does not invent doc link" $movedLegacyCategoryText '"link":'
        $movedLegacyTargetText = Get-Content -LiteralPath (Join-Path $legacySectionRepo "Docs\TestDomain\ProjectStructure\Target-Structure.md") -Raw
        Assert-TextContains "case1i legacy moved page preserves slug" $movedLegacyTargetText "slug: /target-structure"
        Assert-TextContains "case1i legacy moved page preserves sidebar position" $movedLegacyTargetText "sidebar_position: 1"
        Assert-Condition "case1i legacy moved target markdown hash unchanged" ((Get-FileHash -LiteralPath (Join-Path $legacySectionRepo "Docs\TestDomain\ProjectStructure\Target-Structure.md") -Algorithm SHA256).Hash -eq $legacyTargetHashBefore) "target hash preserved" "Target-Structure.md changed during normalization"
        Assert-Condition "case1i legacy moved migration markdown hash unchanged" ((Get-FileHash -LiteralPath (Join-Path $legacySectionRepo "Docs\TestDomain\ProjectStructure\UE-Editor-Migration.md") -Algorithm SHA256).Hash -eq $legacyMigrationHashBefore) "migration hash preserved" "UE-Editor-Migration.md changed during normalization"

        $legacyTreeAfterMove = Invoke-RestMethod -Uri "http://127.0.0.1:$legacySectionPort/api/tree?sidebarId=test-domain-sidebar" -Method Get -TimeoutSec 5
        $legacyMovedNode = @($legacyTreeAfterMove.tree.children | Where-Object { ([string]$_.path) -eq "TestDomain/ProjectStructure" }) | Select-Object -First 1
        Assert-Condition "case1i destination tree exposes moved legacy section" ($null -ne $legacyMovedNode) "TestDomain/ProjectStructure node present" "TestDomain/ProjectStructure node missing from destination tree"
        Assert-Condition "case1i source tree removes moved legacy section" (@($legacyTreeAfterMove.tree.children | Where-Object { ([string]$_.path) -eq "WorkflowStandards/ProjectStructure" }).Count -eq 0) "source path absent from destination tree" "unexpected source path appeared in destination tree"

        $legacyMoveBackBody = @{
          sourcePath = "TestDomain/ProjectStructure"
          destinationDomainPath = "WorkflowStandards"
          destinationParentPath = "WorkflowStandards"
          insertIndex = 0
        } | ConvertTo-Json -Depth 6
        $legacyMoveBack = Invoke-RestMethod -Uri "http://127.0.0.1:$legacySectionPort/api/move" -Method Post -ContentType "application/json" -Body $legacyMoveBackBody -TimeoutSec 5
        Assert-Condition "case1i legacy section round-trip move returns ok payload" ($legacyMoveBack.ok -eq $true) "move back ok=true" "legacy move back response did not set ok=true"
        Assert-TextContains "case1i legacy section round-trip returns source docs path" ([string]$legacyMoveBack.result.path) "WorkflowStandards/ProjectStructure"
        Assert-Condition "case1i legacy destination section removed after move back" (-not (Test-Path -LiteralPath (Join-Path $legacySectionRepo "Docs\TestDomain\ProjectStructure"))) "destination section removed" "destination section still exists after move back"
        Assert-Condition "case1i legacy source section restored after move back" (Test-Path -LiteralPath $sourceLegacySectionPath -PathType Container) "source section restored" "source section missing after move back"
        Assert-Condition "case1i legacy source section keeps normalized category metadata after move back" (Test-Path -LiteralPath (Join-Path $sourceLegacySectionPath "_category_.json") -PathType Leaf) "_category_.json restored" "_category_.json missing after move back"
        $legacyTreeAfterMoveBack = Invoke-RestMethod -Uri "http://127.0.0.1:$legacySectionPort/api/tree?sidebarId=workflow-standards-sidebar" -Method Get -TimeoutSec 5
        Assert-Condition "case1i workflow tree exposes legacy section after move back" (@($legacyTreeAfterMoveBack.tree.children | Where-Object { ([string]$_.path) -eq "WorkflowStandards/ProjectStructure" }).Count -eq 1) "WorkflowStandards/ProjectStructure restored" "WorkflowStandards/ProjectStructure missing after move back"

        $emptyMoveBody = @{
          sourcePath = "WorkflowStandards/EmptyAssets"
          destinationDomainPath = "TestDomain"
          destinationParentPath = "TestDomain"
          insertIndex = 0
        } | ConvertTo-Json -Depth 6
        $emptyMoveResponse = Invoke-WebRequest -Uri "http://127.0.0.1:$legacySectionPort/api/move" -Method Post -ContentType "application/json" -Body $emptyMoveBody -TimeoutSec 5 -SkipHttpErrorCheck
        Assert-Condition "case1i empty directory move returns client error" ([int]$emptyMoveResponse.StatusCode -ge 400) "status>=400" "status=$([int]$emptyMoveResponse.StatusCode)"
        Assert-TextContains "case1i arbitrary empty directory remains rejected" ([string]$emptyMoveResponse.Content) "Docs page or section not found: WorkflowStandards/EmptyAssets"

        $missingMoveBody = @{
          sourcePath = "WorkflowStandards/DoesNotExist"
          destinationDomainPath = "TestDomain"
          destinationParentPath = "TestDomain"
          insertIndex = 0
        } | ConvertTo-Json -Depth 6
        $missingMoveResponse = Invoke-WebRequest -Uri "http://127.0.0.1:$legacySectionPort/api/move" -Method Post -ContentType "application/json" -Body $missingMoveBody -TimeoutSec 5 -SkipHttpErrorCheck
        Assert-Condition "case1i missing source move returns client error" ([int]$missingMoveResponse.StatusCode -ge 400) "status>=400" "status=$([int]$missingMoveResponse.StatusCode)"
        Assert-TextContains "case1i nonexistent source returns clear not found error" ([string]$missingMoveResponse.Content) "Docs page or section not found: WorkflowStandards/DoesNotExist"
      }
    }
    finally {
      if ($legacySectionApiHostProcess -and -not $legacySectionApiHostProcess.HasExited) {
        Stop-Process -Id $legacySectionApiHostProcess.Id -Force -ErrorAction SilentlyContinue
      }
    }
  }

  Step "Case 1ii: domain-root same-parent moves persist exact long-distance order across tree, restart, and sidebar output"
  $domainRootApiHostScriptPath = Join-Path $repoRoot "Scripts\UETools\DocsEditorApiHost.ps1"
  if (-not (Test-Path -LiteralPath $domainRootApiHostScriptPath -PathType Leaf)) {
    $script:SkipCount += 1
    Write-Log "[SKIP] case1ii editor API host script is not present in this payload build." Yellow
  }
  else {
    function New-DomainRootReorderRepo {
      param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$ShowLandingInSidebar,
        [switch]$IncludeMixedPage
      )

      $repo = New-MinimalDocsRepo -Name $Name
      New-Item -ItemType Directory -Force -Path (Join-Path $repo "Docs\WorkflowStandards\Alpha") | Out-Null
      New-Item -ItemType Directory -Force -Path (Join-Path $repo "Docs\WorkflowStandards\DocsSite") | Out-Null
      New-Item -ItemType Directory -Force -Path (Join-Path $repo "Docs\Beta") | Out-Null
      New-Item -ItemType Directory -Force -Path (Join-Path $repo "Docs\Gamma") | Out-Null
      New-Item -ItemType Directory -Force -Path (Join-Path $repo "Docs\Delta") | Out-Null
      New-Item -ItemType Directory -Force -Path (Join-Path $repo "Docs\Epsilon") | Out-Null

      $ownedRoots = @("WorkflowStandards", "Beta", "Gamma", "Delta", "Epsilon")
      $ownedDocs = @()
      if ($IncludeMixedPage) {
        $ownedRoots = @("WorkflowStandards", "Beta", "Delta", "Epsilon")
        $ownedDocs = @("Gamma")
      }

      $domainsJson = [ordered]@{
        schemaVersion = 1
        domains = @(
          [ordered]@{
            key = "workflow-standards"
            dirName = "WorkflowStandards"
            sidebarId = "workflow-standards-sidebar"
            label = "Workflow & Standards"
            position = 10
            landingDoc = "WorkflowStandards/README"
            showLandingInSidebar = $ShowLandingInSidebar.IsPresent
            ownedRoots = @($ownedRoots)
            ownedDocs = @($ownedDocs)
            catchAll = $false
          }
        )
      }
      Write-Utf8NoBomFile -Path (Join-Path $repo "Docs\_domains.json") -Content (($domainsJson | ConvertTo-Json -Depth 10) + "`r`n")
      Write-Utf8NoBomFile -Path (Join-Path $repo "Docs\WorkflowStandards\README.md") -Content @'
---
title: Workflow & Standards
slug: /workflow-standards
sidebar_position: 1
displayed_sidebar: workflow-standards-sidebar
---

# Workflow & Standards
'@
      Write-Utf8NoBomFile -Path (Join-Path $repo "Docs\WorkflowStandards\_category_.json") -Content @'
{
  "label": "Workflow & Standards",
  "position": 1,
  "link": {
    "type": "doc",
    "id": "WorkflowStandards/README"
  }
}
'@
      Write-Utf8NoBomFile -Path (Join-Path $repo "Docs\WorkflowStandards\Alpha\_category_.json") -Content @'
{
  "label": "Alpha",
  "position": 1
}
'@
      Write-Utf8NoBomFile -Path (Join-Path $repo "Docs\WorkflowStandards\Alpha\Alpha.md") -Content @'
---
title: Alpha
sidebar_position: 1
---

# Alpha
'@
      Write-Utf8NoBomFile -Path (Join-Path $repo "Docs\WorkflowStandards\DocsSite\_category_.json") -Content @'
{
  "label": "Docs Site",
  "position": 2
}
'@
      Write-Utf8NoBomFile -Path (Join-Path $repo "Docs\WorkflowStandards\DocsSite\Authoring.md") -Content @'
---
title: Authoring
sidebar_position: 1
---

# Authoring
'@
      foreach ($entry in @(
          @{ Name = "Beta"; Position = 3 },
          @{ Name = "Gamma"; Position = 4 },
          @{ Name = "Delta"; Position = 5 },
          @{ Name = "Epsilon"; Position = 6 }
        )) {
        Write-Utf8NoBomFile -Path (Join-Path $repo ("Docs\{0}\_category_.json" -f $entry.Name)) -Content @"
{
  "label": "$($entry.Name)",
  "position": $($entry.Position)
}
"@
        Write-Utf8NoBomFile -Path (Join-Path $repo ("Docs\{0}\{0}.md" -f $entry.Name)) -Content @"
---
title: $($entry.Name)
sidebar_position: 1
---

# $($entry.Name)
"@
      }

      if ($IncludeMixedPage) {
        Remove-Item -LiteralPath (Join-Path $repo "Docs\Gamma") -Recurse -Force
        Write-Utf8NoBomFile -Path (Join-Path $repo "Docs\Gamma.md") -Content @'
---
title: Gamma
sidebar_position: 4
---

# Gamma
'@
      }

      return $repo
    }

    function Start-DomainRootApiHost {
      param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][int]$Port
      )

      $stdoutPath = Join-Path (New-ScratchPath ("api-host-domain-root-{0}" -f $Port)) "stdout.log"
      $stderrPath = Join-Path (Split-Path -Parent $stdoutPath) "stderr.log"
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stdoutPath) | Out-Null
      $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
      $apiHostArgs = @(
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy Bypass",
        ("-File `"{0}`"" -f $domainRootApiHostScriptPath),
        ("-RepoRoot `"{0}`"" -f $RepoPath),
        ("-DocsModulePath `"{0}`"" -f $script:DocsToolsScriptPath),
        ("-Port {0}" -f $Port)
      ) -join ' '
      $process = Start-Process `
        -FilePath $pwshPath `
        -ArgumentList $apiHostArgs `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

      $ready = $false
      for ($i = 0; $i -lt 30; $i++) {
        try {
          $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -Method Get -TimeoutSec 2
          if ($health.ok) {
            $ready = $true
            break
          }
        }
        catch {
        }
        Start-Sleep -Milliseconds 200
      }

      $failure = "health endpoint did not report ready"
      if (-not $ready) {
        $stderr = if (Test-Path -LiteralPath $stderrPath -PathType Leaf) { Get-Content -LiteralPath $stderrPath -Raw } else { "<stderr log not found>" }
        $stdout = if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) { Get-Content -LiteralPath $stdoutPath -Raw } else { "<stdout log not found>" }
        $failure = "health endpoint did not report ready. stderr=$stderr stdout=$stdout"
      }
      Assert-Condition "case1ii api host health endpoint ready" $ready "health ok" $failure

      return [pscustomobject]@{
        Process = $process
        Port = $Port
      }
    }

    function Stop-DomainRootApiHost {
      param($ApiHost)
      if ($ApiHost -and $ApiHost.Process -and -not $ApiHost.Process.HasExited) {
        Stop-Process -Id $ApiHost.Process.Id -Force -ErrorAction SilentlyContinue
      }
    }

    function Restart-DomainRootApiHost {
      param(
        [Parameter(Mandatory)]$ApiHost,
        [Parameter(Mandatory)][string]$RepoPath
      )

      Stop-DomainRootApiHost -ApiHost $ApiHost
      return (Start-DomainRootApiHost -RepoPath $RepoPath -Port ([int]$ApiHost.Port))
    }

    function Get-DomainRootTree {
      param(
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$SidebarId
      )

      return (Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/api/tree?sidebarId={1}" -f $Port, $SidebarId) -Method Get -TimeoutSec 5)
    }

    function Get-SidebarOrder {
      param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$SidebarId
      )

      $websiteRoot = Join-Path $RepoPath "website"
      $sourcePath = Join-Path $websiteRoot "domainCatalog.ts"
      $evalPath = Join-Path $websiteRoot "domainCatalog.eval.ts"
      $content = Get-Content -LiteralPath $sourcePath -Raw
      $shim = "import { fileURLToPath } from 'node:url';`nconst __dirname = path.dirname(fileURLToPath(import.meta.url));`n"
      $patched = $content -replace "import path from 'node:path';", ("import path from 'node:path';`n" + $shim)
      Write-Utf8NoBomFile -Path $evalPath -Content $patched
      try {
        $importPath = ('file:///{0}' -f ($evalPath -replace '\\', '/'))
        $json = node --input-type=module -e "import('$importPath').then(m=>{console.log(JSON.stringify(m.buildDocsSidebarsConfig()));}).catch(err=>{console.error(err);process.exit(1);})"
        if ($LASTEXITCODE -ne 0) {
          throw "Unable to evaluate sidebars config."
        }

        $config = $json | ConvertFrom-Json
        $items = @($config.$SidebarId)
        return @(
          foreach ($item in $items) {
            if ($item -is [string]) {
              $docId = [string]$item
              $docRelativePath = (($docId -replace '/', '\') + ".md")
              $docPath = Join-Path $RepoPath ("Docs\{0}" -f $docRelativePath)
              $titleLine = if (Test-Path -LiteralPath $docPath -PathType Leaf) {
                Select-String -Path $docPath -Pattern '^\s*title\s*:\s*(.+?)\s*$' | Select-Object -First 1
              }
              else {
                $null
              }

              if ($titleLine) {
                ([string]$titleLine.Matches[0].Groups[1].Value).Trim().Trim("'", '"')
              }
              else {
                [System.IO.Path]::GetFileNameWithoutExtension($docRelativePath)
              }
            }
            elseif ($null -ne $item.label) {
              [string]$item.label
            }
          }
        )
      }
      finally {
        Remove-Item -LiteralPath $evalPath -Force -ErrorAction SilentlyContinue
      }
    }

    function Get-MarkdownHashes {
      param([Parameter(Mandatory)][string]$RepoPath)

      $hashes = @{}
      foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $RepoPath "Docs") -Recurse -File | Where-Object { $_.Extension -in @(".md", ".mdx") })) {
        $hashes[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
      }
      return $hashes
    }

    function Get-SanitizedCategoryTexts {
      param([Parameter(Mandatory)][string]$RepoPath)

      $texts = @{}
      foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $RepoPath "Docs") -Recurse -File -Filter _category_.json)) {
        $jsonObject = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        $jsonObject.PSObject.Properties.Remove('position')
        $texts[$file.FullName] = ($jsonObject | ConvertTo-Json -Depth 20)
      }
      return $texts
    }

    function Assert-DomainRootState {
      param(
        [Parameter(Mandatory)][string]$CaseName,
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$SidebarId,
        [Parameter(Mandatory)][string[]]$ExpectedPaths,
        [Parameter(Mandatory)][string[]]$ExpectedSidebarLabels,
        [Parameter(Mandatory)][hashtable]$MarkdownHashes,
        [Parameter(Mandatory)][hashtable]$SanitizedCategoryTexts,
        [Parameter(Mandatory)][string]$ExpectedLandingDoc,
        [string[]]$IgnoredMarkdownPaths = @(),
        [switch]$SkipContiguousPositionCheck
      )

      $tree = Get-DomainRootTree -Port $Port -SidebarId $SidebarId
      $actualPaths = @($tree.tree.children | ForEach-Object { [string]$_.path })
      Assert-Condition "$CaseName tree child count matches" ($actualPaths.Count -eq $ExpectedPaths.Count) "count matches" "expected $($ExpectedPaths.Count) children, found $($actualPaths.Count): $($actualPaths -join ', ')"
      Assert-Condition "$CaseName tree order matches" ((@($actualPaths) -join '|') -eq (@($ExpectedPaths) -join '|')) "tree order preserved" "expected $($ExpectedPaths -join ', '), found $($actualPaths -join ', ')"
      if (-not $SkipContiguousPositionCheck) {
        $actualPositions = @($tree.tree.children | ForEach-Object { [int][double]$_.position })
        $expectedPositions = @(1..$ExpectedPaths.Count)
        Assert-Condition "$CaseName tree positions are deterministic" ((@($actualPositions) -join '|') -eq (@($expectedPositions) -join '|')) "positions are contiguous" "expected positions $($expectedPositions -join ', '), found $($actualPositions -join ', ')"
      }
      Assert-Condition "$CaseName tree paths are unique" ((@($actualPaths | Select-Object -Unique).Count) -eq $actualPaths.Count) "paths unique" "duplicate paths in $($actualPaths -join ', ')"

      foreach ($entry in $MarkdownHashes.GetEnumerator()) {
        if (@($IgnoredMarkdownPaths | Where-Object { ([string]$_).Equals([string]$entry.Key, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
          continue
        }
        $currentHash = (Get-FileHash -LiteralPath ([string]$entry.Key) -Algorithm SHA256).Hash
        Assert-Condition "$CaseName markdown hash unchanged for $([System.IO.Path]::GetFileName([string]$entry.Key))" ($currentHash -eq [string]$entry.Value) "markdown hash unchanged" "hash changed for $([string]$entry.Key)"
      }

      foreach ($entry in $SanitizedCategoryTexts.GetEnumerator()) {
        $currentObject = Get-Content -LiteralPath ([string]$entry.Key) -Raw | ConvertFrom-Json
        $currentObject.PSObject.Properties.Remove('position')
        $currentText = ($currentObject | ConvertTo-Json -Depth 20)
        Assert-Condition "$CaseName category metadata unchanged outside position for $([System.IO.Path]::GetFileName((Split-Path -Parent ([string]$entry.Key))))" ($currentText -eq [string]$entry.Value) "category metadata stable" "unexpected category metadata change in $([string]$entry.Key)"
      }

      $domains = Get-Content -LiteralPath (Join-Path $RepoPath "Docs\_domains.json") -Raw | ConvertFrom-Json
      $workflowDomain = @($domains.domains | Where-Object { ([string]$_.sidebarId) -eq $SidebarId }) | Select-Object -First 1
      Assert-Condition "$CaseName landingDoc unchanged" ([string]$workflowDomain.landingDoc -eq $ExpectedLandingDoc) "landingDoc unchanged" "landingDoc=$([string]$workflowDomain.landingDoc)"

      $sidebarOrder = @(Get-SidebarOrder -RepoPath $RepoPath -SidebarId $SidebarId)
      Assert-Condition "$CaseName sidebar item count matches" ($sidebarOrder.Count -eq $ExpectedSidebarLabels.Count) "sidebar count matches" "expected $($ExpectedSidebarLabels.Count) items, found $($sidebarOrder.Count): $($sidebarOrder -join ', ')"
      Assert-Condition "$CaseName sidebar order matches" ((@($sidebarOrder) -join '|') -eq (@($ExpectedSidebarLabels) -join '|')) "sidebar order preserved" "expected $($ExpectedSidebarLabels -join ', '), found $($sidebarOrder -join ', ')"
    }

    function Invoke-MoveScenario {
      param(
        [Parameter(Mandatory)][string]$CaseName,
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)]$ApiHost,
        [Parameter(Mandatory)][hashtable]$Payload,
        [Parameter(Mandatory)][string[]]$ExpectedPaths,
        [Parameter(Mandatory)][string[]]$ExpectedSidebarLabels,
        [Parameter(Mandatory)][hashtable]$MarkdownHashes,
        [Parameter(Mandatory)][hashtable]$SanitizedCategoryTexts,
        [Parameter(Mandatory)][string]$ExpectedLandingDoc,
        [string[]]$IgnoredMarkdownPaths = @(),
        [switch]$SkipContiguousPositionCheck,
        [switch]$RestartAndReassert
      )

      $response = Invoke-RestMethod `
        -Uri ("http://127.0.0.1:{0}/api/move" -f $ApiHost.Port) `
        -Method Post `
        -ContentType "application/json" `
        -Body ($Payload | ConvertTo-Json -Depth 6) `
        -TimeoutSec 5
      Assert-Condition "$CaseName move endpoint returns ok payload" ($response.ok -eq $true) "move ok=true" "move response did not set ok=true"
      Assert-DomainRootState `
        -CaseName $CaseName `
        -RepoPath $RepoPath `
        -Port $ApiHost.Port `
        -SidebarId "workflow-standards-sidebar" `
        -ExpectedPaths $ExpectedPaths `
        -ExpectedSidebarLabels $ExpectedSidebarLabels `
        -MarkdownHashes $MarkdownHashes `
        -SanitizedCategoryTexts $SanitizedCategoryTexts `
        -ExpectedLandingDoc $ExpectedLandingDoc `
        -IgnoredMarkdownPaths $IgnoredMarkdownPaths `
        -SkipContiguousPositionCheck:$SkipContiguousPositionCheck
      if ($RestartAndReassert) {
        $script:domainRootCurrentApiHost = Restart-DomainRootApiHost -ApiHost $ApiHost -RepoPath $RepoPath
        Assert-DomainRootState `
          -CaseName "$CaseName after restart" `
          -RepoPath $RepoPath `
          -Port $script:domainRootCurrentApiHost.Port `
          -SidebarId "workflow-standards-sidebar" `
          -ExpectedPaths $ExpectedPaths `
          -ExpectedSidebarLabels $ExpectedSidebarLabels `
          -MarkdownHashes $MarkdownHashes `
          -SanitizedCategoryTexts $SanitizedCategoryTexts `
          -ExpectedLandingDoc $ExpectedLandingDoc `
          -IgnoredMarkdownPaths $IgnoredMarkdownPaths `
          -SkipContiguousPositionCheck:$SkipContiguousPositionCheck
      }
    }

    function Invoke-ReorderScenario {
      param(
        [Parameter(Mandatory)][string]$CaseName,
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)]$ApiHost,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)]$Position,
        [Parameter(Mandatory)][string[]]$ExpectedPaths,
        [Parameter(Mandatory)][string[]]$ExpectedSidebarLabels,
        [Parameter(Mandatory)][hashtable]$MarkdownHashes,
        [Parameter(Mandatory)][hashtable]$SanitizedCategoryTexts,
        [Parameter(Mandatory)][string]$ExpectedLandingDoc,
        [string[]]$IgnoredMarkdownPaths = @()
      )

      $response = Invoke-RestMethod `
        -Uri ("http://127.0.0.1:{0}/api/reorder" -f $ApiHost.Port) `
        -Method Post `
        -ContentType "application/json" `
        -Body (@{ targetPath = $TargetPath; position = $Position } | ConvertTo-Json -Depth 4) `
        -TimeoutSec 5
      Assert-Condition "$CaseName reorder endpoint returns ok payload" ($response.ok -eq $true) "reorder ok=true" "reorder response did not set ok=true"
      Assert-DomainRootState `
        -CaseName $CaseName `
        -RepoPath $RepoPath `
        -Port $ApiHost.Port `
        -SidebarId "workflow-standards-sidebar" `
        -ExpectedPaths $ExpectedPaths `
        -ExpectedSidebarLabels $ExpectedSidebarLabels `
        -MarkdownHashes $MarkdownHashes `
        -SanitizedCategoryTexts $SanitizedCategoryTexts `
        -ExpectedLandingDoc $ExpectedLandingDoc `
        -IgnoredMarkdownPaths $IgnoredMarkdownPaths
    }

    $mainRepo = New-DomainRootReorderRepo -Name "repo-domain-root-reorder"
    $mainPort = Get-FreeTcpPort
    $script:domainRootCurrentApiHost = $null
    try {
      $script:domainRootCurrentApiHost = Start-DomainRootApiHost -RepoPath $mainRepo -Port $mainPort
      $mainMarkdownHashes = Get-MarkdownHashes -RepoPath $mainRepo
      $mainCategoryTexts = Get-SanitizedCategoryTexts -RepoPath $mainRepo
      $expectedLandingDoc = "WorkflowStandards/README"
      $initialPaths = @(
        "WorkflowStandards/Alpha",
        "WorkflowStandards/DocsSite",
        "Beta",
        "Gamma",
        "Delta",
        "Epsilon"
      )
      $initialSidebar = @("Alpha", "Docs Site", "Beta", "Gamma", "Delta", "Epsilon")
      Assert-DomainRootState -CaseName "case1ii initial" -RepoPath $mainRepo -Port $mainPort -SidebarId "workflow-standards-sidebar" -ExpectedPaths $initialPaths -ExpectedSidebarLabels $initialSidebar -MarkdownHashes $mainMarkdownHashes -SanitizedCategoryTexts $mainCategoryTexts -ExpectedLandingDoc $expectedLandingDoc

      Invoke-MoveScenario -CaseName "case1ii same-slot move is a no-op" -RepoPath $mainRepo -ApiHost $script:domainRootCurrentApiHost -Payload @{
        sourcePath = "WorkflowStandards/DocsSite"
        destinationDomainPath = "WorkflowStandards"
        destinationParentPath = "WorkflowStandards"
        insertIndex = 1
      } -ExpectedPaths $initialPaths -ExpectedSidebarLabels $initialSidebar -MarkdownHashes $mainMarkdownHashes -SanitizedCategoryTexts $mainCategoryTexts -ExpectedLandingDoc $expectedLandingDoc

      $docsSiteBottomPaths = @("WorkflowStandards/Alpha", "Beta", "Gamma", "Delta", "Epsilon", "WorkflowStandards/DocsSite")
      $docsSiteBottomSidebar = @("Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Docs Site")
      Invoke-MoveScenario -CaseName "case1ii docs site index 1 to final index 5" -RepoPath $mainRepo -ApiHost $script:domainRootCurrentApiHost -Payload @{
        sourcePath = "WorkflowStandards/DocsSite"
        destinationDomainPath = "WorkflowStandards"
        destinationParentPath = "WorkflowStandards"
        insertIndex = 6
      } -ExpectedPaths $docsSiteBottomPaths -ExpectedSidebarLabels $docsSiteBottomSidebar -MarkdownHashes $mainMarkdownHashes -SanitizedCategoryTexts $mainCategoryTexts -ExpectedLandingDoc $expectedLandingDoc -RestartAndReassert

      $docsSiteTopPaths = @("WorkflowStandards/DocsSite", "WorkflowStandards/Alpha", "Beta", "Gamma", "Delta", "Epsilon")
      $docsSiteTopSidebar = @("Docs Site", "Alpha", "Beta", "Gamma", "Delta", "Epsilon")
      Invoke-MoveScenario -CaseName "case1ii final index 5 to index 0" -RepoPath $mainRepo -ApiHost $script:domainRootCurrentApiHost -Payload @{
        sourcePath = "WorkflowStandards/DocsSite"
        destinationDomainPath = "WorkflowStandards"
        destinationParentPath = "WorkflowStandards"
        insertIndex = 0
      } -ExpectedPaths $docsSiteTopPaths -ExpectedSidebarLabels $docsSiteTopSidebar -MarkdownHashes $mainMarkdownHashes -SanitizedCategoryTexts $mainCategoryTexts -ExpectedLandingDoc $expectedLandingDoc

      Invoke-MoveScenario -CaseName "case1ii index 0 to final index 5" -RepoPath $mainRepo -ApiHost $script:domainRootCurrentApiHost -Payload @{
        sourcePath = "WorkflowStandards/DocsSite"
        destinationDomainPath = "WorkflowStandards"
        destinationParentPath = "WorkflowStandards"
        insertIndex = 6
      } -ExpectedPaths $docsSiteBottomPaths -ExpectedSidebarLabels $docsSiteBottomSidebar -MarkdownHashes $mainMarkdownHashes -SanitizedCategoryTexts $mainCategoryTexts -ExpectedLandingDoc $expectedLandingDoc

      $betaMiddlePaths = @("WorkflowStandards/Alpha", "Gamma", "Delta", "Epsilon", "Beta", "WorkflowStandards/DocsSite")
      $betaMiddleSidebar = @("Alpha", "Gamma", "Delta", "Epsilon", "Beta", "Docs Site")
      Invoke-MoveScenario -CaseName "case1ii later domain-root move preserves the full sibling list" -RepoPath $mainRepo -ApiHost $script:domainRootCurrentApiHost -Payload @{
        sourcePath = "Beta"
        destinationDomainPath = "WorkflowStandards"
        destinationParentPath = "WorkflowStandards"
        insertIndex = 4
      } -ExpectedPaths $betaMiddlePaths -ExpectedSidebarLabels $betaMiddleSidebar -MarkdownHashes $mainMarkdownHashes -SanitizedCategoryTexts $mainCategoryTexts -ExpectedLandingDoc $expectedLandingDoc

      $betaUpPaths = @("WorkflowStandards/Alpha", "Beta", "Gamma", "Delta", "Epsilon", "WorkflowStandards/DocsSite")
      $betaUpSidebar = @("Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Docs Site")
      Invoke-MoveScenario -CaseName "case1ii move back toward the top preserves exact sibling order" -RepoPath $mainRepo -ApiHost $script:domainRootCurrentApiHost -Payload @{
        sourcePath = "Beta"
        destinationDomainPath = "WorkflowStandards"
        destinationParentPath = "WorkflowStandards"
        insertIndex = 1
      } -ExpectedPaths $betaUpPaths -ExpectedSidebarLabels $betaUpSidebar -MarkdownHashes $mainMarkdownHashes -SanitizedCategoryTexts $mainCategoryTexts -ExpectedLandingDoc $expectedLandingDoc

      Invoke-ReorderScenario -CaseName "case1ii adjacent down uses the full domain-root sibling list" -RepoPath $mainRepo -ApiHost $script:domainRootCurrentApiHost -TargetPath "Beta" -Position 3 -ExpectedPaths @("WorkflowStandards/Alpha", "Gamma", "Beta", "Delta", "Epsilon", "WorkflowStandards/DocsSite") -ExpectedSidebarLabels @("Alpha", "Gamma", "Beta", "Delta", "Epsilon", "Docs Site") -MarkdownHashes $mainMarkdownHashes -SanitizedCategoryTexts $mainCategoryTexts -ExpectedLandingDoc $expectedLandingDoc
      Invoke-ReorderScenario -CaseName "case1ii adjacent up uses the full domain-root sibling list" -RepoPath $mainRepo -ApiHost $script:domainRootCurrentApiHost -TargetPath "Beta" -Position 2 -ExpectedPaths $betaUpPaths -ExpectedSidebarLabels $betaUpSidebar -MarkdownHashes $mainMarkdownHashes -SanitizedCategoryTexts $mainCategoryTexts -ExpectedLandingDoc $expectedLandingDoc

      Invoke-MoveScenario -CaseName "case1ii repeated downward move after long-distance reordering succeeds" -RepoPath $mainRepo -ApiHost $script:domainRootCurrentApiHost -Payload @{
        sourcePath = "Beta"
        destinationDomainPath = "WorkflowStandards"
        destinationParentPath = "WorkflowStandards"
        insertIndex = 6
      } -ExpectedPaths @("WorkflowStandards/Alpha", "Gamma", "Delta", "Epsilon", "WorkflowStandards/DocsSite", "Beta") -ExpectedSidebarLabels @("Alpha", "Gamma", "Delta", "Epsilon", "Docs Site", "Beta") -MarkdownHashes $mainMarkdownHashes -SanitizedCategoryTexts $mainCategoryTexts -ExpectedLandingDoc $expectedLandingDoc
      Invoke-MoveScenario -CaseName "case1ii repeated upward move after a long move succeeds" -RepoPath $mainRepo -ApiHost $script:domainRootCurrentApiHost -Payload @{
        sourcePath = "WorkflowStandards/DocsSite"
        destinationDomainPath = "WorkflowStandards"
        destinationParentPath = "WorkflowStandards"
        insertIndex = 2
      } -ExpectedPaths @("WorkflowStandards/Alpha", "Gamma", "WorkflowStandards/DocsSite", "Delta", "Epsilon", "Beta") -ExpectedSidebarLabels @("Alpha", "Gamma", "Docs Site", "Delta", "Epsilon", "Beta") -MarkdownHashes $mainMarkdownHashes -SanitizedCategoryTexts $mainCategoryTexts -ExpectedLandingDoc $expectedLandingDoc

      Invoke-MoveScenario -CaseName "case1ii negative insert index clamps to first" -RepoPath $mainRepo -ApiHost $script:domainRootCurrentApiHost -Payload @{
        sourcePath = "WorkflowStandards/DocsSite"
        destinationDomainPath = "WorkflowStandards"
        destinationParentPath = "WorkflowStandards"
        insertIndex = -5
      } -ExpectedPaths @("WorkflowStandards/DocsSite", "WorkflowStandards/Alpha", "Gamma", "Delta", "Epsilon", "Beta") -ExpectedSidebarLabels @("Docs Site", "Alpha", "Gamma", "Delta", "Epsilon", "Beta") -MarkdownHashes $mainMarkdownHashes -SanitizedCategoryTexts $mainCategoryTexts -ExpectedLandingDoc $expectedLandingDoc
      Invoke-MoveScenario -CaseName "case1ii above-maximum insert index clamps to last" -RepoPath $mainRepo -ApiHost $script:domainRootCurrentApiHost -Payload @{
        sourcePath = "WorkflowStandards/DocsSite"
        destinationDomainPath = "WorkflowStandards"
        destinationParentPath = "WorkflowStandards"
        insertIndex = 99
      } -ExpectedPaths @("WorkflowStandards/Alpha", "Gamma", "Delta", "Epsilon", "Beta", "WorkflowStandards/DocsSite") -ExpectedSidebarLabels @("Alpha", "Gamma", "Delta", "Epsilon", "Beta", "Docs Site") -MarkdownHashes $mainMarkdownHashes -SanitizedCategoryTexts $mainCategoryTexts -ExpectedLandingDoc $expectedLandingDoc

      $missingMoveResponse = Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/api/move" -f $script:domainRootCurrentApiHost.Port) -Method Post -ContentType "application/json" -Body (@{
          sourcePath = "WorkflowStandards/DoesNotExist"
          destinationDomainPath = "WorkflowStandards"
          destinationParentPath = "WorkflowStandards"
          insertIndex = 0
        } | ConvertTo-Json -Depth 4) -TimeoutSec 5 -SkipHttpErrorCheck
      Assert-Condition "case1ii missing source move returns client error" ([int]$missingMoveResponse.StatusCode -ge 400) "status>=400" "status=$([int]$missingMoveResponse.StatusCode)"
      Assert-TextContains "case1ii missing source keeps clear error text" ([string]$missingMoveResponse.Content) "Docs page or section not found: WorkflowStandards/DoesNotExist"

      $wrongParentResponse = Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/api/move" -f $script:domainRootCurrentApiHost.Port) -Method Post -ContentType "application/json" -Body (@{
          sourcePath = "WorkflowStandards/DocsSite"
          destinationDomainPath = "WorkflowStandards"
          destinationParentPath = "WorkflowStandards/DocsSite"
          insertIndex = 0
        } | ConvertTo-Json -Depth 4) -TimeoutSec 5 -SkipHttpErrorCheck
      Assert-Condition "case1ii wrong destination parent returns client error" ([int]$wrongParentResponse.StatusCode -ge 400) "status>=400" "status=$([int]$wrongParentResponse.StatusCode)"
      Assert-TextContains "case1ii wrong destination parent keeps clear error text" ([string]$wrongParentResponse.Content) "Cannot move a section into itself or one of its descendants."
    }
    finally {
      Stop-DomainRootApiHost -ApiHost $script:domainRootCurrentApiHost
    }

    $visibleLandingRepo = New-DomainRootReorderRepo -Name "repo-domain-root-visible-landing" -ShowLandingInSidebar
    $visibleLandingPort = Get-FreeTcpPort
    $visibleLandingApiHost = $null
    try {
      $visibleLandingApiHost = Start-DomainRootApiHost -RepoPath $visibleLandingRepo -Port $visibleLandingPort
      $visibleMarkdownHashes = Get-MarkdownHashes -RepoPath $visibleLandingRepo
      $visibleCategoryTexts = Get-SanitizedCategoryTexts -RepoPath $visibleLandingRepo
      Invoke-MoveScenario -CaseName "case1ii visible landing control keeps insert indices authoritative" -RepoPath $visibleLandingRepo -ApiHost $visibleLandingApiHost -Payload @{
        sourcePath = "WorkflowStandards/DocsSite"
        destinationDomainPath = "WorkflowStandards"
        destinationParentPath = "WorkflowStandards"
        insertIndex = 7
      } -ExpectedPaths @("WorkflowStandards/Alpha", "WorkflowStandards/README", "Beta", "Gamma", "Delta", "Epsilon", "WorkflowStandards/DocsSite") -ExpectedSidebarLabels @("Alpha", "Workflow & Standards", "Beta", "Gamma", "Delta", "Epsilon", "Docs Site") -MarkdownHashes $visibleMarkdownHashes -SanitizedCategoryTexts $visibleCategoryTexts -ExpectedLandingDoc "WorkflowStandards/README" -SkipContiguousPositionCheck -IgnoredMarkdownPaths @(Join-Path $visibleLandingRepo "Docs\WorkflowStandards\README.md")
    }
    finally {
      Stop-DomainRootApiHost -ApiHost $visibleLandingApiHost
    }

    $mixedRepo = New-DomainRootReorderRepo -Name "repo-domain-root-mixed" -IncludeMixedPage
    $mixedPort = Get-FreeTcpPort
    $mixedApiHost = $null
    try {
      $mixedApiHost = Start-DomainRootApiHost -RepoPath $mixedRepo -Port $mixedPort
      $mixedMarkdownHashes = Get-MarkdownHashes -RepoPath $mixedRepo
      $mixedCategoryTexts = Get-SanitizedCategoryTexts -RepoPath $mixedRepo
      Invoke-MoveScenario -CaseName "case1ii mixed child control keeps pages and sections in one reorderable list" -RepoPath $mixedRepo -ApiHost $mixedApiHost -Payload @{
        sourcePath = "WorkflowStandards/DocsSite"
        destinationDomainPath = "WorkflowStandards"
        destinationParentPath = "WorkflowStandards"
        insertIndex = 5
      } -ExpectedPaths @("WorkflowStandards/Alpha", "Beta", "Gamma.md", "Delta", "Epsilon", "WorkflowStandards/DocsSite") -ExpectedSidebarLabels @("Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Docs Site") -MarkdownHashes $mixedMarkdownHashes -SanitizedCategoryTexts $mixedCategoryTexts -ExpectedLandingDoc "WorkflowStandards/README" -IgnoredMarkdownPaths @(Join-Path $mixedRepo "Docs\Gamma.md")
      Invoke-MoveScenario -CaseName "case1ii mixed child control reorders a section across a page in the same list" -RepoPath $mixedRepo -ApiHost $mixedApiHost -Payload @{
        sourcePath = "Beta"
        destinationDomainPath = "WorkflowStandards"
        destinationParentPath = "WorkflowStandards"
        insertIndex = 2
      } -ExpectedPaths @("WorkflowStandards/Alpha", "Gamma.md", "Beta", "Delta", "Epsilon", "WorkflowStandards/DocsSite") -ExpectedSidebarLabels @("Alpha", "Gamma", "Beta", "Delta", "Epsilon", "Docs Site") -MarkdownHashes $mixedMarkdownHashes -SanitizedCategoryTexts $mixedCategoryTexts -ExpectedLandingDoc "WorkflowStandards/README" -IgnoredMarkdownPaths @(Join-Path $mixedRepo "Docs\Gamma.md")
    }
    finally {
      Stop-DomainRootApiHost -ApiHost $mixedApiHost
    }

    Remove-Item function:New-DomainRootReorderRepo -ErrorAction SilentlyContinue
    Remove-Item function:Start-DomainRootApiHost -ErrorAction SilentlyContinue
    Remove-Item function:Stop-DomainRootApiHost -ErrorAction SilentlyContinue
    Remove-Item function:Restart-DomainRootApiHost -ErrorAction SilentlyContinue
    Remove-Item function:Get-DomainRootTree -ErrorAction SilentlyContinue
    Remove-Item function:Get-SidebarOrder -ErrorAction SilentlyContinue
    Remove-Item function:Get-MarkdownHashes -ErrorAction SilentlyContinue
    Remove-Item function:Get-SanitizedCategoryTexts -ErrorAction SilentlyContinue
    Remove-Item function:Assert-DomainRootState -ErrorAction SilentlyContinue
    Remove-Item function:Invoke-MoveScenario -ErrorAction SilentlyContinue
    Remove-Item function:Invoke-ReorderScenario -ErrorAction SilentlyContinue
  }

  Step "Case 1j: migrate-sections and doctor classify legacy sections without overwriting content"
  $migrationRepo = New-MinimalDocsRepo -Name "repo-migrate-sections"
  New-Item -ItemType Directory -Force -Path (Join-Path $migrationRepo "Docs\WorkflowStandards\ProjectStructure") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $migrationRepo "Docs\WorkflowStandards\MdxOnly") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $migrationRepo "Docs\WorkflowStandards\LegacySibling") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $migrationRepo "Docs\WorkflowStandards\NestedParent\ChildLegacy") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $migrationRepo "Docs\WorkflowStandards\AssetOnly") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $migrationRepo "Docs\WorkflowStandards\EmptyDir") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $migrationRepo "Docs\.generated-cache\SkipMe") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $migrationRepo "Docs\LegacyDomainRoot") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $migrationRepo "Docs\WorkflowStandards\BrokenMarked") | Out-Null
  $migrationToolset = New-StubToolset -Name "toolset-migrate-sections"
  Write-Utf8NoBomFile -Path (Join-Path $migrationRepo "Docs\_domains.json") -Content @'
{
  "schemaVersion": 1,
  "domains": [
    {
      "key": "workflow-standards",
      "dirName": "WorkflowStandards",
      "sidebarId": "workflow-standards-sidebar",
      "label": "Workflow & Standards",
      "position": 10,
      "landingDoc": "WorkflowStandards/README",
      "showLandingInSidebar": false,
      "ownedRoots": ["WorkflowStandards"],
      "ownedDocs": [],
      "catchAll": false
    },
    {
      "key": "legacy-domain-root",
      "dirName": "LegacyDomainRoot",
      "sidebarId": "legacy-domain-root-sidebar",
      "label": "Legacy Domain Root",
      "position": 20,
      "landingDoc": "",
      "showLandingInSidebar": false,
      "ownedRoots": ["LegacyDomainRoot"],
      "ownedDocs": [],
      "catchAll": false
    }
  ]
}
'@
  Write-Utf8NoBomFile -Path (Join-Path $migrationRepo "Docs\WorkflowStandards\ProjectStructure\Target-Structure.md") -Content @'
---
title: Target Structure
slug: /target-structure
sidebar_position: 1
---

# Target Structure
'@
  Write-Utf8NoBomFile -Path (Join-Path $migrationRepo "Docs\WorkflowStandards\MdxOnly\Guide.mdx") -Content @'
---
title: Guide
slug: /guide
sidebar_position: 2
---

# Guide
'@
  Write-Utf8NoBomFile -Path (Join-Path $migrationRepo "Docs\WorkflowStandards\LegacySibling\Sibling.md") -Content @'
---
title: Sibling
slug: /sibling
sidebar_position: 3
---

# Sibling
'@
  Write-Utf8NoBomFile -Path (Join-Path $migrationRepo "Docs\WorkflowStandards\NestedParent\ChildLegacy\Nested.md") -Content @'
---
title: Nested
slug: /nested
sidebar_position: 1
---

# Nested
'@
  Write-Utf8NoBomFile -Path (Join-Path $migrationRepo "Docs\LegacyDomainRoot\DomainRoot.md") -Content @'
---
title: Domain Root
slug: /domain-root
sidebar_position: 1
---

# Domain Root
'@
  Write-Utf8NoBomFile -Path (Join-Path $migrationRepo "Docs\.generated-cache\SkipMe\Ignored.md") -Content @'
---
title: Ignored
slug: /ignored
sidebar_position: 1
---

# Ignored
'@
  Write-Utf8NoBomFile -Path (Join-Path $migrationRepo "Docs\WorkflowStandards\BrokenMarked\_category_.json") -Content "{ not-json`n"
  [System.IO.File]::WriteAllBytes((Join-Path $migrationRepo "Docs\WorkflowStandards\AssetOnly\preview.png"), [byte[]](1,2,3,4))

  $migrationWhatIf = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $migrationRepo `
    -CliArgs @("migrate-sections", "--what-if") `
    -Toolset $migrationToolset `
    -SandboxRoot (New-ScratchPath "sandbox-migrate-sections-whatif")
  Assert-Condition "case1j migrate-sections what-if exits cleanly" ($migrationWhatIf.ExitCode -eq 0) "exit code=0" "exit code=$($migrationWhatIf.ExitCode)"
  Assert-TextContains "case1j what-if reports project structure" $migrationWhatIf.OutputText "Would normalize 'WorkflowStandards/ProjectStructure'"
  Assert-TextContains "case1j what-if reports mdx-only legacy section" $migrationWhatIf.OutputText "Would normalize 'WorkflowStandards/MdxOnly'"
  Assert-TextContains "case1j what-if reports nested legacy section" $migrationWhatIf.OutputText "Would normalize 'WorkflowStandards/NestedParent/ChildLegacy'"
  Assert-Condition "case1j what-if writes nothing for project structure" (-not (Test-Path -LiteralPath (Join-Path $migrationRepo "Docs\WorkflowStandards\ProjectStructure\_category_.json") -PathType Leaf)) "_category_.json absent" "_category_.json created during what-if"

  $doctorBeforeMigration = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $migrationRepo `
    -CliArgs @("doctor") `
    -Toolset $migrationToolset `
    -SandboxRoot (New-ScratchPath "sandbox-migrate-sections-doctor")
  Assert-Condition "case1j doctor exits cleanly" ($doctorBeforeMigration.ExitCode -eq 0) "exit code=0" "exit code=$($doctorBeforeMigration.ExitCode)"
  Assert-TextContains "case1j doctor reports legacy section count" $doctorBeforeMigration.OutputText "Legacy docs sections requiring migration: 4"
  Assert-TextContains "case1j doctor recommends remediation" $doctorBeforeMigration.OutputText "Remediation: ue-tools docs migrate-sections"
  Assert-TextContains "case1j doctor distinguishes asset-only directory" $doctorBeforeMigration.OutputText "INFO asset-only-directory: WorkflowStandards/AssetOnly"
  Assert-TextContains "case1j doctor distinguishes empty directory" $doctorBeforeMigration.OutputText "INFO empty-directory: WorkflowStandards/EmptyDir"
  Assert-TextContains "case1j doctor distinguishes malformed category" $doctorBeforeMigration.OutputText "INFO malformed-category: WorkflowStandards/BrokenMarked"
  Assert-TextContains "case1j doctor distinguishes domain root" $doctorBeforeMigration.OutputText "INFO domain-root: LegacyDomainRoot"

  $projectStructureHashBeforeApply = (Get-FileHash -LiteralPath (Join-Path $migrationRepo "Docs\WorkflowStandards\ProjectStructure\Target-Structure.md") -Algorithm SHA256).Hash
  $mdxHashBeforeApply = (Get-FileHash -LiteralPath (Join-Path $migrationRepo "Docs\WorkflowStandards\MdxOnly\Guide.mdx") -Algorithm SHA256).Hash
  $migrationApply = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $migrationRepo `
    -CliArgs @("migrate-sections") `
    -Toolset $migrationToolset `
    -SandboxRoot (New-ScratchPath "sandbox-migrate-sections-apply")
  Assert-Condition "case1j migrate-sections apply exits cleanly" ($migrationApply.ExitCode -eq 0) "exit code=0" "exit code=$($migrationApply.ExitCode)"
  Assert-TextContains "case1j apply reports normalized project structure" $migrationApply.OutputText "Normalized 'WorkflowStandards/ProjectStructure'"
  Assert-TextContains "case1j apply reports normalized mdx section" $migrationApply.OutputText "Normalized 'WorkflowStandards/MdxOnly'"
  Assert-Condition "case1j project structure category created" (Test-Path -LiteralPath (Join-Path $migrationRepo "Docs\WorkflowStandards\ProjectStructure\_category_.json") -PathType Leaf) "_category_.json present" "_category_.json missing for ProjectStructure"
  Assert-Condition "case1j mdx-only category created" (Test-Path -LiteralPath (Join-Path $migrationRepo "Docs\WorkflowStandards\MdxOnly\_category_.json") -PathType Leaf) "_category_.json present" "_category_.json missing for MdxOnly"
  Assert-Condition "case1j nested legacy category created" (Test-Path -LiteralPath (Join-Path $migrationRepo "Docs\WorkflowStandards\NestedParent\ChildLegacy\_category_.json") -PathType Leaf) "_category_.json present" "_category_.json missing for ChildLegacy"
  Assert-Condition "case1j multiple sibling legacy category created" (Test-Path -LiteralPath (Join-Path $migrationRepo "Docs\WorkflowStandards\LegacySibling\_category_.json") -PathType Leaf) "_category_.json present" "_category_.json missing for LegacySibling"
  Assert-Condition "case1j migration preserves absent readme" (-not (Test-Path -LiteralPath (Join-Path $migrationRepo "Docs\WorkflowStandards\ProjectStructure\README.md") -PathType Leaf)) "README absent" "README created unexpectedly"
  $projectStructureCategoryText = Get-Content -LiteralPath (Join-Path $migrationRepo "Docs\WorkflowStandards\ProjectStructure\_category_.json") -Raw
  Assert-TextContains "case1j migration writes stable label" $projectStructureCategoryText '"label": "ProjectStructure"'
  Assert-TextNotContains "case1j migration does not invent link" $projectStructureCategoryText '"link":'
  Assert-Condition "case1j migration preserves markdown bytes" ((Get-FileHash -LiteralPath (Join-Path $migrationRepo "Docs\WorkflowStandards\ProjectStructure\Target-Structure.md") -Algorithm SHA256).Hash -eq $projectStructureHashBeforeApply) "target hash preserved" "Target-Structure.md changed"
  Assert-Condition "case1j migration preserves mdx bytes" ((Get-FileHash -LiteralPath (Join-Path $migrationRepo "Docs\WorkflowStandards\MdxOnly\Guide.mdx") -Algorithm SHA256).Hash -eq $mdxHashBeforeApply) "mdx hash preserved" "Guide.mdx changed"

  $migrationApplyNoOp = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $migrationRepo `
    -CliArgs @("migrate-sections") `
    -Toolset $migrationToolset `
    -SandboxRoot (New-ScratchPath "sandbox-migrate-sections-noop")
  Assert-Condition "case1j migrate-sections rerun exits cleanly" ($migrationApplyNoOp.ExitCode -eq 0) "exit code=0" "exit code=$($migrationApplyNoOp.ExitCode)"
  Assert-TextContains "case1j migrate-sections rerun is no-op" $migrationApplyNoOp.OutputText "No legacy docs sections require migration."
  $doctorAfterMigration = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $migrationRepo `
    -CliArgs @("doctor") `
    -Toolset $migrationToolset `
    -SandboxRoot (New-ScratchPath "sandbox-migrate-sections-doctor-after")
  Assert-Condition "case1j doctor after migration exits cleanly" ($doctorAfterMigration.ExitCode -eq 0) "exit code=0" "exit code=$($doctorAfterMigration.ExitCode)"
  Assert-TextContains "case1j doctor after migration clears legacy warnings" $doctorAfterMigration.OutputText "Legacy docs sections requiring migration: 0"

  Step "Case 2: new-section scaffolds a section and skips TOC without the bridge"
  $noTocRepo = New-MinimalDocsRepo -Name "repo-no-toc"
  $noTocToolset = New-StubToolset -Name "toolset-no-toc"
  $newSectionResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $noTocRepo `
    -CliArgs @("new-section", "GameDesign", "-Title", "Game Design", "-Position", "9") `
    -Toolset $noTocToolset `
    -SandboxRoot (New-ScratchPath "sandbox-no-toc")
  if ($newSectionResult.ExitCode -ne 0) {
    Write-Log ("case2 failure output:`n" + $newSectionResult.OutputText) DarkGray
  }
  $sectionReadme = Join-Path $noTocRepo "Docs\GameDesign\README.md"
  $sectionCategory = Join-Path $noTocRepo "Docs\GameDesign\_category_.json"
  Assert-Condition "case2 new-section exits cleanly" ($newSectionResult.ExitCode -eq 0) "exit code=0" "exit code=$($newSectionResult.ExitCode)"
  Assert-Condition "case2 section readme created" (Test-Path -LiteralPath $sectionReadme) "README.md created"
  Assert-Condition "case2 category metadata created" (Test-Path -LiteralPath $sectionCategory) "_category_.json created"
  Assert-TextContains "case2 output confirms skipped toc" $newSectionResult.OutputText "TOC generation skipped."
  if (Test-Path -LiteralPath $sectionReadme -PathType Leaf) {
    $sectionReadmeText = Get-Content -LiteralPath $sectionReadme -Raw
    Assert-TextContains "case2 readme has section slug" $sectionReadmeText "slug: /game-design"
    Assert-TextContains "case2 readme has overview heading" $sectionReadmeText "## Overview"
    Assert-TextNotContains "case2 readme omits toc marker" $sectionReadmeText "<!-- docs-tools-toc -->"
  }
  if (Test-Path -LiteralPath $sectionCategory -PathType Leaf) {
    $sectionCategoryText = Get-Content -LiteralPath $sectionCategory -Raw
    Assert-TextContains "case2 category label" $sectionCategoryText '"label": "Game Design"'
    Assert-TextContains "case2 category position" $sectionCategoryText '"position": 9'
    Assert-TextContains "case2 category doc link" $sectionCategoryText '"id": "GameDesign/README"'
  }

  Step "Case 2b: new-section auto-assigns the next sidebar position"
  $autoSectionRepo = New-MinimalDocsRepo -Name "repo-auto-section-position"
  $autoSectionToolset = New-StubToolset -Name "toolset-auto-section-position"
  $autoSectionResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $autoSectionRepo `
    -CliArgs @("new-section", "Systems") `
    -Toolset $autoSectionToolset `
    -SandboxRoot (New-ScratchPath "sandbox-auto-section-position")
  $autoSectionCategoryText = Get-Content -LiteralPath (Join-Path $autoSectionRepo "Docs\Systems\_category_.json") -Raw
  Assert-Condition "case2b new-section exits cleanly" ($autoSectionResult.ExitCode -eq 0) "exit code=0" "exit code=$($autoSectionResult.ExitCode)"
  Assert-TextContains "case2b default section position increments" $autoSectionCategoryText '"position": 2'

  Step "Case 2c: create-section supports generated-index and category passthrough metadata"
  $generatedSectionRepo = New-MinimalDocsRepo -Name "repo-generated-section"
  $generatedSectionToolset = New-StubToolset -Name "toolset-generated-section"
  $generatedSectionResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $generatedSectionRepo `
    -CliArgs @(
      "create-section", "DocsSite",
      "-LinkType", "generated-index",
      "-GeneratedIndexTitle", "Docs Site",
      "-GeneratedIndexSlug", "/docs-site",
      "-GeneratedIndexDescription", "Docs guidance",
      "-CategoryJson", 'customProps={"badge":"internal"}'
    ) `
    -Toolset $generatedSectionToolset `
    -SandboxRoot (New-ScratchPath "sandbox-generated-section")
  $generatedSectionCategoryText = Get-Content -LiteralPath (Join-Path $generatedSectionRepo "Docs\DocsSite\_category_.json") -Raw
  Assert-Condition "case2c create-section exits cleanly" ($generatedSectionResult.ExitCode -eq 0) "exit code=0" "exit code=$($generatedSectionResult.ExitCode)"
  Assert-TextContains "case2c generated index type" $generatedSectionCategoryText '"type": "generated-index"'
  Assert-TextContains "case2c generated index slug" $generatedSectionCategoryText '"slug": "/docs-site"'
  Assert-TextContains "case2c generated index description" $generatedSectionCategoryText '"description": "Docs guidance"'
  Assert-TextContains "case2c category custom props" $generatedSectionCategoryText '"badge": "internal"'

  Step "Case 2d: reorder moves a top-level page and shifts sibling positions"
  $reorderRepo = New-MinimalDocsRepo -Name "repo-reorder"
  $reorderToolset = New-StubToolset -Name "toolset-reorder"
  Write-Utf8NoBomFile -Path (Join-Path $reorderRepo "Docs\Setup.md") -Content @'
---
title: Setup
slug: /setup
sidebar_position: 2
---

# Setup
'@
  New-Item -ItemType Directory -Force -Path (Join-Path $reorderRepo "Docs\GameDesign") | Out-Null
  Write-Utf8NoBomFile -Path (Join-Path $reorderRepo "Docs\GameDesign\README.md") -Content @'
---
title: Game Design
slug: /game-design
sidebar_position: 1
---

# Game Design
'@
  Write-Utf8NoBomFile -Path (Join-Path $reorderRepo "Docs\GameDesign\_category_.json") -Content @'
{
  "label": "Game Design",
  "position": 3,
  "link": {
    "type": "doc",
    "id": "GameDesign/README"
  }
}
'@
  Write-Utf8NoBomFile -Path (Join-Path $reorderRepo "Docs\Workflow.md") -Content @'
---
title: Workflow
slug: /workflow
sidebar_position: 4
---

# Workflow
'@
  Write-Utf8NoBomFile -Path (Join-Path $reorderRepo "Docs\Art-Source.md") -Content @'
---
title: Art Source
slug: /art-source
sidebar_position: 5
---

# Art Source
'@
  $reorderResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $reorderRepo `
    -CliArgs @("reorder", "Art-Source", "3") `
    -Toolset $reorderToolset `
    -SandboxRoot (New-ScratchPath "sandbox-reorder")
  $reorderedArtSource = Get-Content -LiteralPath (Join-Path $reorderRepo "Docs\Art-Source.md") -Raw
  $reorderedSection = Get-Content -LiteralPath (Join-Path $reorderRepo "Docs\GameDesign\_category_.json") -Raw
  $reorderedWorkflow = Get-Content -LiteralPath (Join-Path $reorderRepo "Docs\Workflow.md") -Raw
  Assert-Condition "case2d reorder exits cleanly" ($reorderResult.ExitCode -eq 0) "exit code=0" "exit code=$($reorderResult.ExitCode)"
  Assert-TextContains "case2d output confirms reorder" $reorderResult.OutputText "Reordered 'Art-Source.md' from 5 to 3."
  Assert-TextContains "case2d art source moved to new position" $reorderedArtSource "sidebar_position: 3"
  Assert-TextContains "case2d section shifted down" $reorderedSection '"position": 4'
  Assert-TextContains "case2d workflow shifted down" $reorderedWorkflow "sidebar_position: 5"

  Step "Case 2e: reorder supports generated-index sections without a README"
  $generatedIndexReorderRepo = New-MinimalDocsRepo -Name "repo-generated-index-reorder"
  $generatedIndexReorderToolset = New-StubToolset -Name "toolset-generated-index-reorder"
  New-Item -ItemType Directory -Force -Path (Join-Path $generatedIndexReorderRepo "Docs\ProjectStructure") | Out-Null
  Write-Utf8NoBomFile -Path (Join-Path $generatedIndexReorderRepo "Docs\ProjectStructure\_category_.json") -Content @'
{
  "label": "Project Structure",
  "position": 3,
  "link": {
    "type": "generated-index",
    "title": "Project Structure",
    "slug": "/project-structure"
  }
}
'@
  Write-Utf8NoBomFile -Path (Join-Path $generatedIndexReorderRepo "Docs\ProjectStructure\Target-Structure.md") -Content @'
---
title: Target Structure
slug: /project-structure/target-structure
sidebar_position: 1
---

# Target Structure
'@
  Write-Utf8NoBomFile -Path (Join-Path $generatedIndexReorderRepo "Docs\Setup.md") -Content @'
---
title: Setup
slug: /setup
sidebar_position: 2
---

# Setup
'@
  $generatedIndexReorderResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $generatedIndexReorderRepo `
    -CliArgs @("reorder", "ProjectStructure", "2") `
    -Toolset $generatedIndexReorderToolset `
    -SandboxRoot (New-ScratchPath "sandbox-generated-index-reorder")
  $generatedIndexCategory = Get-Content -LiteralPath (Join-Path $generatedIndexReorderRepo "Docs\ProjectStructure\_category_.json") -Raw
  $generatedIndexSetup = Get-Content -LiteralPath (Join-Path $generatedIndexReorderRepo "Docs\Setup.md") -Raw
  Assert-Condition "case2e reorder exits cleanly" ($generatedIndexReorderResult.ExitCode -eq 0) "exit code=0" "exit code=$($generatedIndexReorderResult.ExitCode)"
  Assert-TextContains "case2e output confirms generated-index section reorder" $generatedIndexReorderResult.OutputText "Reordered 'ProjectStructure' from 3 to 2."
  Assert-TextContains "case2e generated-index section moved to new position" $generatedIndexCategory '"position": 2'
  Assert-TextContains "case2e setup shifted down" $generatedIndexSetup "sidebar_position: 3"

  Step "Case 3: new-page scaffolds a page and skips TOC without the bridge"
  $newPageResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $noTocRepo `
    -CliArgs @("new-page", "GameDesign", "Fear-Loop", "-Title", "Fear Loop", "-Position", "2") `
    -Toolset $noTocToolset `
    -SandboxRoot (New-ScratchPath "sandbox-new-page-no-toc")
  $pagePath = Join-Path $noTocRepo "Docs\GameDesign\Fear-Loop.md"
  $pageText = Get-Content -LiteralPath $pagePath -Raw
  Assert-Condition "case3 new-page exits cleanly" ($newPageResult.ExitCode -eq 0) "exit code=0" "exit code=$($newPageResult.ExitCode)"
  Assert-Condition "case3 page created" (Test-Path -LiteralPath $pagePath) "Fear-Loop.md created"
  Assert-TextContains "case3 output confirms skipped toc" $newPageResult.OutputText "TOC generation skipped."
  Assert-TextContains "case3 page slug" $pageText "slug: /game-design/fear-loop"
  Assert-TextContains "case3 page position" $pageText "sidebar_position: 2"
  Assert-TextNotContains "case3 page omits toc marker" $pageText "<!-- docs-tools-toc -->"

  Step "Case 3b: new-page auto-assigns the next sidebar position"
  $autoPageResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $noTocRepo `
    -CliArgs @("new-page", "GameDesign", "Escalation-Loop") `
    -Toolset $noTocToolset `
    -SandboxRoot (New-ScratchPath "sandbox-auto-page-position")
  $autoPageText = Get-Content -LiteralPath (Join-Path $noTocRepo "Docs\GameDesign\Escalation-Loop.md") -Raw
  Assert-Condition "case3b new-page exits cleanly" ($autoPageResult.ExitCode -eq 0) "exit code=0" "exit code=$($autoPageResult.ExitCode)"
  Assert-TextContains "case3b default page position increments" $autoPageText "sidebar_position: 3"

  Step "Case 3c: new-page can scaffold a top-level docs page without a section"
  $topLevelPageRepo = New-MinimalDocsRepo -Name "repo-top-level-page"
  $topLevelPageToolset = New-StubToolset -Name "toolset-top-level-page"
  $topLevelPageResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $topLevelPageRepo `
    -CliArgs @("new-page", "Setup", "-Title", "Setup") `
    -Toolset $topLevelPageToolset `
    -SandboxRoot (New-ScratchPath "sandbox-top-level-page")
  $topLevelPagePath = Join-Path $topLevelPageRepo "Docs\Setup.md"
  $topLevelPageText = Get-Content -LiteralPath $topLevelPagePath -Raw
  Assert-Condition "case3c top-level new-page exits cleanly" ($topLevelPageResult.ExitCode -eq 0) "exit code=0" "exit code=$($topLevelPageResult.ExitCode)"
  Assert-Condition "case3c top-level page created" (Test-Path -LiteralPath $topLevelPagePath) "Setup.md created"
  Assert-TextContains "case3c top-level page slug" $topLevelPageText "slug: /setup"
  Assert-TextContains "case3c top-level page position" $topLevelPageText "sidebar_position: 2"
  Assert-TextContains "case3c top-level output confirms skipped toc" $topLevelPageResult.OutputText "TOC generation skipped."

  Step "Case 3d: create-page supports generic front matter passthrough"
  $pageMetadataRepo = New-MinimalDocsRepo -Name "repo-page-metadata"
  New-Item -ItemType Directory -Force -Path (Join-Path $pageMetadataRepo "Docs\GameDesign") | Out-Null
  $pageMetadataSectionReadme = @'
---
title: Game Design
slug: /game-design
sidebar_position: 1
---

# Game Design
'@
  Write-Utf8NoBomFile -Path (Join-Path $pageMetadataRepo "Docs\GameDesign\README.md") -Content $pageMetadataSectionReadme
  Write-Utf8NoBomFile -Path (Join-Path $pageMetadataRepo "Docs\GameDesign\_category_.json") -Content '{"label":"Game Design","position":2,"link":{"type":"doc","id":"GameDesign/README"}}'
  $pageMetadataToolset = New-StubToolset -Name "toolset-page-metadata"
  $pageMetadataResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $pageMetadataRepo `
    -CliArgs @(
      "create-page", "GameDesign", "Panic-Curve",
      "-Description", "Curve notes",
      "-Field", "foo=bar",
      "-FieldJson", 'custom_edit_url=null'
    ) `
    -Toolset $pageMetadataToolset `
    -SandboxRoot (New-ScratchPath "sandbox-page-metadata")
  $pageMetadataText = Get-Content -LiteralPath (Join-Path $pageMetadataRepo "Docs\GameDesign\Panic-Curve.md") -Raw
  Assert-Condition "case3d create-page exits cleanly" ($pageMetadataResult.ExitCode -eq 0) "exit code=0" "exit code=$($pageMetadataResult.ExitCode)"
  Assert-TextContains "case3d front matter description" $pageMetadataText "description: 'Curve notes'"
  Assert-TextContains "case3d front matter custom string field" $pageMetadataText "foo: bar"
  Assert-TextContains "case3d front matter json field" $pageMetadataText "custom_edit_url: null"

  Step "Case 3e: new-page fails cleanly when the target section does not exist"
  $missingSectionResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $noTocRepo `
    -CliArgs @("new-page", "MissingSection", "Ghost-Notes") `
    -Toolset $noTocToolset `
    -SandboxRoot (New-ScratchPath "sandbox-missing-section")
  Assert-Condition "case3e new-page fails for missing section" ($missingSectionResult.ExitCode -ne 0) "exit code=$($missingSectionResult.ExitCode)" "expected non-zero exit code"
  Assert-TextContains "case3e output is user-friendly" $missingSectionResult.OutputText "Error: Section does not exist:"
  Assert-TextNotContains "case3e output hides stack traces" $missingSectionResult.OutputText "UEToolSuite.Docs.psm1:"

  Step "Case 3f: visibility toggles page and section landing docs through Docusaurus unlisted front matter"
  $visibilityPagePath = Join-Path $noTocRepo "Docs\GameDesign\Fear-Loop.md"
  $hidePageResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $noTocRepo `
    -CliArgs @("visibility", "GameDesign/Fear-Loop", "hide") `
    -Toolset $noTocToolset `
    -SandboxRoot (New-ScratchPath "sandbox-visibility-hide-page")
  $hiddenPageText = Get-Content -LiteralPath $visibilityPagePath -Raw
  Assert-Condition "case3f hide page exits cleanly" ($hidePageResult.ExitCode -eq 0) "exit code=0" "exit code=$($hidePageResult.ExitCode)"
  Assert-TextContains "case3f hide page confirms action" $hidePageResult.OutputText "Hidden 'GameDesign/Fear-Loop.md' from site navigation."
  Assert-TextContains "case3f hide page writes unlisted front matter" $hiddenPageText "unlisted: true"

  $showPageResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $noTocRepo `
    -CliArgs @("visibility", "GameDesign/Fear-Loop", "show") `
    -Toolset $noTocToolset `
    -SandboxRoot (New-ScratchPath "sandbox-visibility-show-page")
  $shownPageText = Get-Content -LiteralPath $visibilityPagePath -Raw
  Assert-Condition "case3f show page exits cleanly" ($showPageResult.ExitCode -eq 0) "exit code=0" "exit code=$($showPageResult.ExitCode)"
  Assert-TextContains "case3f show page confirms action" $showPageResult.OutputText "Showed 'GameDesign/Fear-Loop.md' in site navigation."
  Assert-TextNotContains "case3f show page removes unlisted front matter" $shownPageText "unlisted: true"

  $visibilitySectionPath = Join-Path $noTocRepo "Docs\GameDesign\README.md"
  $hideSectionResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $noTocRepo `
    -CliArgs @("visibility", "GameDesign", "hide") `
    -Toolset $noTocToolset `
    -SandboxRoot (New-ScratchPath "sandbox-visibility-hide-section")
  $hiddenSectionText = Get-Content -LiteralPath $visibilitySectionPath -Raw
  Assert-Condition "case3f hide section exits cleanly" ($hideSectionResult.ExitCode -eq 0) "exit code=0" "exit code=$($hideSectionResult.ExitCode)"
  Assert-TextContains "case3f hide section confirms landing target" $hideSectionResult.OutputText "Hidden 'GameDesign/README.md' from site navigation."
  Assert-TextContains "case3f hide section writes unlisted front matter" $hiddenSectionText "unlisted: true"

  $showSectionResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $noTocRepo `
    -CliArgs @("visibility", "GameDesign", "show") `
    -Toolset $noTocToolset `
    -SandboxRoot (New-ScratchPath "sandbox-visibility-show-section")
  $shownSectionText = Get-Content -LiteralPath $visibilitySectionPath -Raw
  Assert-Condition "case3f show section exits cleanly" ($showSectionResult.ExitCode -eq 0) "exit code=0" "exit code=$($showSectionResult.ExitCode)"
  Assert-TextContains "case3f show section confirms landing target" $showSectionResult.OutputText "Showed 'GameDesign/README.md' in site navigation."
  Assert-TextNotContains "case3f show section removes unlisted front matter" $shownSectionText "unlisted: true"

  Step "Case 4: install-bridge copies the optional VS Code bridge"
  $bridgeToolset = New-StubToolset -Name "toolset-install-bridge" -CodeExtensions @("yzhang.markdown-all-in-one")
  $bridgeRepo = New-MinimalDocsRepo -Name "repo-install-bridge"
  $installBridgeResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $bridgeRepo `
    -CliArgs @("install-bridge") `
    -Toolset $bridgeToolset `
    -SandboxRoot (New-ScratchPath "sandbox-install-bridge")
  $bridgeInstallPath = Join-Path $installBridgeResult.SandboxUserProfile ".vscode\extensions\ueproject.docs-tools-bridge-0.0.1"
  Assert-Condition "case4 install-bridge exits cleanly" ($installBridgeResult.ExitCode -eq 0) "exit code=0" "exit code=$($installBridgeResult.ExitCode)"
  Assert-Condition "case4 bridge folder created" (Test-Path -LiteralPath $bridgeInstallPath) "bridge extension copied"
  Assert-Condition "case4 bridge package copied" (Test-Path -LiteralPath (Join-Path $bridgeInstallPath "package.json")) "package.json copied"
  Assert-Condition "case4 bridge code copied" (Test-Path -LiteralPath (Join-Path $bridgeInstallPath "extension.js")) "extension.js copied"
  Assert-TextContains "case4 output mentions markdown extension" $installBridgeResult.OutputText "Markdown All in One is already installed."

  Step "Case 5: start streams the dev server in the current terminal by default"
  $foregroundStartRepo = New-MinimalDocsRepo -Name "repo-start-foreground"
  $foregroundStartToolset = New-StubToolset -Name "toolset-start-foreground"
  $foregroundStartResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $foregroundStartRepo `
    -CliArgs @("start", "--port", "3001") `
    -Toolset $foregroundStartToolset `
    -SandboxRoot (New-ScratchPath "sandbox-start-foreground")
  $foregroundStartStubLog = Get-Content -LiteralPath $foregroundStartToolset.CommandLog -Raw
  $foregroundStateFiles = @(Get-ChildItem -Path (Join-Path $foregroundStartResult.SandboxTemp "ueproject-ue-tools-docs") -Recurse -Filter docs-server.json -ErrorAction SilentlyContinue)
  Assert-Condition "case5 start exits cleanly" ($foregroundStartResult.ExitCode -eq 0) "exit code=0" "exit code=$($foregroundStartResult.ExitCode)"
  Assert-TextContains "case5 output confirms foreground start" $foregroundStartResult.OutputText "Starting docs dev server in the current terminal."
  Assert-TextContains "case5 output includes requested port url" $foregroundStartResult.OutputText "http://localhost:3001/docs/"
  Assert-TextContains "case5 npm start was invoked" $foregroundStartStubLog "npm run start -- --port 3001"
  Assert-Condition "case5 no background state file created" ($foregroundStateFiles.Count -eq 0) "no docs-server.json created"

  $runBackgroundRuntimeCases = ([string]$env:UE_TOOLS_ENABLE_BACKGROUND_DOCS_TESTS).Trim().ToLowerInvariant() -in @("1", "true", "yes")
  if ($runBackgroundRuntimeCases) {
    Step "Case 5b: start --background launches a tracked server, status reports it, and stop cleans state"
    $startStopRepo = New-MinimalDocsRepo -Name "repo-start-stop"
    $startStopToolset = New-StubToolset -Name "toolset-start-stop"
    $startStopSandbox = New-ScratchPath "sandbox-start-stop"
    $startStopPort = Get-FreeTcpPort
    $startResult = Invoke-DocsToolsCommand `
      -ScratchRepoRoot $startStopRepo `
      -CliArgs @("start", "--background", "--port", "$startStopPort") `
      -Toolset $startStopToolset `
      -SandboxRoot $startStopSandbox `
      -ExtraEnv @{ UE_TOOLS_DOCS_START_CONTINUE = "yes"; STUB_NPM_START_MODE = "sleep" }
    $serverStateFiles = @(Get-ChildItem -Path (Join-Path $startResult.SandboxTemp "ueproject-ue-tools-docs") -Recurse -Filter docs-server.json -ErrorAction SilentlyContinue)
    $serverState = Get-Content -LiteralPath $serverStateFiles[0].FullName -Raw | ConvertFrom-Json
    $primaryServerState = if ($serverState.PSObject.Properties["servers"]) { @($serverState.servers)[0] } else { $serverState }
    $primaryServerPid = [int]$primaryServerState.processId
    $startStubLog = Get-Content -LiteralPath $startStopToolset.CommandLog -Raw
    Assert-Condition "case5b start exits cleanly" ($startResult.ExitCode -eq 0) "exit code=0" "exit code=$($startResult.ExitCode)"
    Assert-TextContains "case5b output confirms background start" $startResult.OutputText "Started docs dev server in the background"
    Assert-TextContains "case5b output includes requested port url" $startResult.OutputText "http://localhost:$startStopPort/docs/"
    Assert-Condition "case5b server state file created" ($serverStateFiles.Count -eq 1) "docs-server.json created"
    Assert-TextContains "case5b npm start was invoked" $startStubLog "npm run start"
    $statusResult = Invoke-DocsToolsCommand `
      -ScratchRepoRoot $startStopRepo `
      -CliArgs @("status") `
      -Toolset $startStopToolset `
      -SandboxRoot $startStopSandbox
    Assert-Condition "case5b status exits cleanly" ($statusResult.ExitCode -eq 0) "exit code=0" "exit code=$($statusResult.ExitCode)"
    Assert-Condition "case5b status reports a handled server state" (
      $statusResult.OutputText.Contains("Background docs dev server is running") -or
      $statusResult.OutputText.Contains("stale state still exists") -or
      $statusResult.OutputText.Contains("Tracked background docs dev server is not running")
    ) "status command reported a handled server state"
    $stopResult = Invoke-DocsToolsCommand `
      -ScratchRepoRoot $startStopRepo `
      -CliArgs @("stop") `
      -Toolset $startStopToolset `
      -SandboxRoot $startStopSandbox
    Assert-Condition "case5b stop exits cleanly" ($stopResult.ExitCode -eq 0) "exit code=0" "exit code=$($stopResult.ExitCode)"
    Assert-Condition "case5b output confirms stop handling" (
      $stopResult.OutputText.Contains("Stopped background docs dev server") -or
      $stopResult.OutputText.Contains("Removed stale background docs dev server state") -or
      $stopResult.OutputText.Contains("Tracked background docs dev server is not running")
    ) "stop command reported a handled shutdown path"
    Assert-Condition "case5b state file removed after stop" (-not (Test-Path -LiteralPath $serverStateFiles[0].FullName)) "docs-server.json removed"
    Assert-Condition "case5b server pid cleaned up or exited" (
      -not (Get-Process -Id $primaryServerPid -ErrorAction SilentlyContinue)
    ) "process $primaryServerPid stopped"

    Step "Case 5c: start --background reuses the tracked docs server instead of creating duplicates"
    $multiServerRepo = New-MinimalDocsRepo -Name "repo-start-stop-multiple"
    $multiServerToolset = New-StubToolset -Name "toolset-start-stop-multiple"
    $multiServerSandbox = New-ScratchPath "sandbox-start-stop-multiple"
    $firstMultiPort = Get-FreeTcpPort
    $secondMultiPort = Get-FreeTcpPort
    while ($secondMultiPort -eq $firstMultiPort) {
      $secondMultiPort = Get-FreeTcpPort
    }
    $firstStartResult = Invoke-DocsToolsCommand `
      -ScratchRepoRoot $multiServerRepo `
      -CliArgs @("start", "--background", "--port", "$firstMultiPort") `
      -Toolset $multiServerToolset `
      -SandboxRoot $multiServerSandbox `
      -ExtraEnv @{ UE_TOOLS_DOCS_START_CONTINUE = "yes"; STUB_NPM_START_MODE = "sleep" }
    $secondStartResult = Invoke-DocsToolsCommand `
      -ScratchRepoRoot $multiServerRepo `
      -CliArgs @("start", "--background", "--port", "$secondMultiPort") `
      -Toolset $multiServerToolset `
      -SandboxRoot $multiServerSandbox `
      -ExtraEnv @{ UE_TOOLS_DOCS_START_CONTINUE = "yes"; STUB_NPM_START_MODE = "sleep" }
    $multiStateFiles = @(Get-ChildItem -Path (Join-Path $firstStartResult.SandboxTemp "ueproject-ue-tools-docs") -Recurse -Filter docs-server.json -ErrorAction SilentlyContinue)
    $multiStateRaw = Get-Content -LiteralPath $multiStateFiles[0].FullName -Raw | ConvertFrom-Json
    $multiEntries = if ($multiStateRaw.PSObject.Properties["servers"]) { @($multiStateRaw.servers) } else { @($multiStateRaw) }
    $multiPids = @($multiEntries | ForEach-Object { [int]$_.processId } | Select-Object -Unique)
    Assert-Condition "case5c first start exits cleanly" ($firstStartResult.ExitCode -eq 0) "exit code=0" "exit code=$($firstStartResult.ExitCode)"
    Assert-Condition "case5c second start exits cleanly" ($secondStartResult.ExitCode -eq 0) "exit code=0" "exit code=$($secondStartResult.ExitCode)"
    Assert-Condition "case5c state file keeps a single tracked server after second start" ($multiEntries.Count -eq 1) "tracked servers=1" "tracked servers=$($multiEntries.Count)"
    Assert-TextContains "case5c second start reports reuse" $secondStartResult.OutputText "Docs dev server is already running"
    $multiStopResult = Invoke-DocsToolsCommand `
      -ScratchRepoRoot $multiServerRepo `
      -CliArgs @("stop") `
      -Toolset $multiServerToolset `
      -SandboxRoot $multiServerSandbox
    Assert-Condition "case5c stop exits cleanly" ($multiStopResult.ExitCode -eq 0) "exit code=0" "exit code=$($multiStopResult.ExitCode)"
    Assert-Condition "case5c stop output confirms tracked shutdown" (
      $multiStopResult.OutputText.Contains("Stopped background docs dev servers") -or
      $multiStopResult.OutputText.Contains("Stopped background docs dev server") -or
      $multiStopResult.OutputText.Contains("Removed stale background docs dev server state") -or
      $multiStopResult.OutputText.Contains("Tracked background docs dev server is not running")
    ) "multi stop reported server shutdown"
    Assert-Condition "case5c state file removed after stop" (-not (Test-Path -LiteralPath $multiStateFiles[0].FullName)) "docs-server.json removed"
    foreach ($serverProcessId in $multiPids) {
      Assert-Condition "case5c server pid $serverProcessId stopped" (-not (Get-Process -Id $serverProcessId -ErrorAction SilentlyContinue)) "process $serverProcessId stopped"
    }

    Step "Case 5d: start --background also starts editor API and writes runtime config for inline editing"
    $editorRuntimeRepo = New-MinimalDocsRepo -Name "repo-editor-runtime"
    $editorRuntimeToolset = New-StubToolset -Name "toolset-editor-runtime"
    $editorRuntimeSandbox = New-ScratchPath "sandbox-editor-runtime"
    $editorRuntimePort = Get-FreeTcpPort
    $editorStartResult = Invoke-DocsToolsCommand `
      -ScratchRepoRoot $editorRuntimeRepo `
      -CliArgs @("start", "--background", "--port", "$editorRuntimePort") `
      -Toolset $editorRuntimeToolset `
      -SandboxRoot $editorRuntimeSandbox `
      -ExtraEnv @{ UE_TOOLS_DOCS_START_CONTINUE = "yes"; STUB_NPM_START_MODE = "sleep" }
    Assert-Condition "case5d start exits cleanly" ($editorStartResult.ExitCode -eq 0) "exit code=0" "exit code=$($editorStartResult.ExitCode)"
    Assert-TextContains "case5d start output includes editor api" $editorStartResult.OutputText "Editor API: http://127.0.0.1:"
    Assert-TextContains "case5d start output mentions inline editing" $editorStartResult.OutputText "Inline editing is available directly on docs pages."

    $editorStatusResult = Invoke-DocsToolsCommand `
      -ScratchRepoRoot $editorRuntimeRepo `
      -CliArgs @("status") `
      -Toolset $editorRuntimeToolset `
      -SandboxRoot $editorRuntimeSandbox
    Assert-Condition "case5d status exits cleanly" ($editorStatusResult.ExitCode -eq 0) "exit code=0" "exit code=$($editorStatusResult.ExitCode)"
    Assert-TextContains "case5d status reports editor api state" $editorStatusResult.OutputText "Editor API status:"

    $editorRuntimeConfigPath = Join-Path $editorRuntimeRepo "website\static\ue-tools\editor-runtime.json"
    Assert-Condition "case5d editor runtime config created" (Test-Path -LiteralPath $editorRuntimeConfigPath -PathType Leaf) "editor-runtime.json created"
    if (Test-Path -LiteralPath $editorRuntimeConfigPath -PathType Leaf) {
      $editorRuntimeConfigText = Get-Content -LiteralPath $editorRuntimeConfigPath -Raw
      $editorRuntimeConfig = $editorRuntimeConfigText | ConvertFrom-Json
      Assert-TextContains "case5d runtime config stores api url" $editorRuntimeConfigText '"apiUrl": "http://127.0.0.1:'
      Assert-Condition "case5d runtime config stores application id" ([string]$editorRuntimeConfig.applicationId -eq "UEToolSuiteDocsEditorApi") "application id matches" "applicationId=$([string]$editorRuntimeConfig.applicationId)"
      Assert-Condition "case5d runtime config stores repo root" ([string]$editorRuntimeConfig.repoRoot -eq $editorRuntimeRepo) "repo root matches" "repoRoot=$([string]$editorRuntimeConfig.repoRoot)"
      Assert-Condition "case5d runtime config stores docs root" ([string]$editorRuntimeConfig.docsRoot -eq (Join-Path $editorRuntimeRepo 'Docs')) "docs root matches" "docsRoot=$([string]$editorRuntimeConfig.docsRoot)"
      $editorHealth = Invoke-RestMethod -Uri ([string]$editorRuntimeConfig.apiUrl + "health") -Method Get -TimeoutSec 2
      Assert-Condition "case5d live health matches runtime config process id" ([int]$editorHealth.processId -eq [int]$editorRuntimeConfig.processId) "process ids match" "health processId=$([string]$editorHealth.processId) runtime processId=$([string]$editorRuntimeConfig.processId)"
      Assert-Condition "case5d live health reports startup timestamp" (-not [string]::IsNullOrWhiteSpace([string]$editorHealth.startedAt)) "startedAt reported" "health startedAt missing"
    }

    $editorStopResult = Invoke-DocsToolsCommand `
      -ScratchRepoRoot $editorRuntimeRepo `
      -CliArgs @("stop") `
      -Toolset $editorRuntimeToolset `
      -SandboxRoot $editorRuntimeSandbox
    Assert-Condition "case5d stop exits cleanly" ($editorStopResult.ExitCode -eq 0) "exit code=0" "exit code=$($editorStopResult.ExitCode)"
    Assert-Condition "case5d stop reports editor runtime status" (
      $editorStopResult.OutputText.Contains("Editor API status: stopped") -or
      $editorStopResult.OutputText.Contains("Editor API status: stale_state_removed") -or
      $editorStopResult.OutputText.Contains("Editor API status: not_running")
    ) "stop command reported editor runtime shutdown"

    Step "Case 5e: start --background fails clearly when the editor API port is occupied by another process"
    $occupiedApiRepo = New-MinimalDocsRepo -Name "repo-editor-port-conflict"
    $occupiedApiToolset = New-StubToolset -Name "toolset-editor-port-conflict"
    $occupiedApiSandbox = New-ScratchPath "sandbox-editor-port-conflict"
    $occupiedApiListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 38473)
    $occupiedApiListener.Start()
    try {
      $occupiedApiStartResult = Invoke-DocsToolsCommand `
        -ScratchRepoRoot $occupiedApiRepo `
        -CliArgs @("start", "--background", "--port", "$(Get-FreeTcpPort)") `
        -Toolset $occupiedApiToolset `
        -SandboxRoot $occupiedApiSandbox
      Assert-Condition "case5e start returns non-zero when api port is occupied" ($occupiedApiStartResult.ExitCode -ne 0) "non-zero exit" "exit code=$($occupiedApiStartResult.ExitCode)"
      Assert-TextContains "case5e start reports occupied api port clearly" $occupiedApiStartResult.OutputText "Docs editor API port 38473 is already in use by a different or unverified process."
    }
    finally {
      $occupiedApiListener.Stop()
    }
  }
  else {
    Step "Case 5b/5c/5d/5e: background runtime lifecycle (optional)"
    $script:SkipCount += 1
    Write-Log "[SKIP] Set UE_TOOLS_ENABLE_BACKGROUND_DOCS_TESTS=1 to run background docs runtime lifecycle cases." Yellow
  }

  Step "Case 6: ue-tools docs can invoke other website package scripts with passthrough flags"
  $scriptRepo = New-MinimalDocsRepo -Name "repo-script-passthrough"
  $scriptToolset = New-StubToolset -Name "toolset-script-passthrough"
  $scriptResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $scriptRepo `
    -CliArgs @("write-heading-ids", "--dry-run") `
    -Toolset $scriptToolset `
    -SandboxRoot (New-ScratchPath "sandbox-script-passthrough")
  $scriptStubLog = Get-Content -LiteralPath $scriptToolset.CommandLog -Raw
  Assert-Condition "case6 passthrough command exits cleanly" ($scriptResult.ExitCode -eq 0) "exit code=0" "exit code=$($scriptResult.ExitCode)"
  Assert-TextContains "case6 npm script was invoked" $scriptStubLog "npm run write-heading-ids -- --dry-run"

  Step "Case 6b: ue-tools docs docusaurus passes raw args and flags through"
  $docusaurusRepo = New-MinimalDocsRepo -Name "repo-docusaurus-passthrough"
  $docusaurusToolset = New-StubToolset -Name "toolset-docusaurus-passthrough"
  $docusaurusResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $docusaurusRepo `
    -CliArgs @("docusaurus", "docs:version", "1.0.0", "--skip-feedback") `
    -Toolset $docusaurusToolset `
    -SandboxRoot (New-ScratchPath "sandbox-docusaurus-passthrough")
  $docusaurusStubLog = Get-Content -LiteralPath $docusaurusToolset.CommandLog -Raw
  Assert-Condition "case6b docusaurus passthrough exits cleanly" ($docusaurusResult.ExitCode -eq 0) "exit code=0" "exit code=$($docusaurusResult.ExitCode)"
  Assert-TextContains "case6b npm docusaurus script was invoked" $docusaurusStubLog "npm run docusaurus -- docs:version 1.0.0 --skip-feedback"

  Step "Case 7: new-page queues a TOC request when the optional bridge is available"
  $tocRepo = New-MinimalDocsRepo -Name "repo-toc"
  New-Item -ItemType Directory -Force -Path (Join-Path $tocRepo "Docs\GameDesign") | Out-Null
  $tocSectionReadme = @'
---
title: Game Design
slug: /game-design
sidebar_position: 1
---

# Game Design
'@
  Write-Utf8NoBomFile -Path (Join-Path $tocRepo "Docs\GameDesign\README.md") -Content $tocSectionReadme
  Write-Utf8NoBomFile -Path (Join-Path $tocRepo "Docs\GameDesign\_category_.json") -Content @'
{
  "label": "Game Design",
  "position": 2,
  "link": {
    "type": "doc",
    "id": "GameDesign/README"
  }
}
'@
  $tocToolset = New-StubToolset -Name "toolset-toc" -CodeExtensions @(
    "yzhang.markdown-all-in-one",
    "ueproject.docs-tools-bridge"
  )
  $tocResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $tocRepo `
    -CliArgs @("new-page", "GameDesign", "Scare-Curve", "-Title", "Scare Curve", "-Position", "3") `
    -Toolset $tocToolset `
    -SandboxRoot (New-ScratchPath "sandbox-toc")
  $tocPagePath = Join-Path $tocRepo "Docs\GameDesign\Scare-Curve.md"
  $tocPageText = Get-Content -LiteralPath $tocPagePath -Raw
  $tocRequestFiles = @(Get-ChildItem -Path (Join-Path $tocResult.SandboxTemp "ueproject-ue-tools-docs") -Recurse -Filter *.json -ErrorAction SilentlyContinue)
  $stubLogText = Get-Content -LiteralPath $tocToolset.CommandLog -Raw
  Assert-Condition "case7 toc-ready new-page exits cleanly" ($tocResult.ExitCode -eq 0) "exit code=0" "exit code=$($tocResult.ExitCode)"
  Assert-TextContains "case7 output confirms queued toc" $tocResult.OutputText "TOC request queued through the VS Code bridge."
  Assert-TextContains "case7 page contains toc marker" $tocPageText "<!-- docs-tools-toc -->"
  Assert-Condition "case7 request json created" ($tocRequestFiles.Count -ge 1) "request file count=$($tocRequestFiles.Count)" "expected a queued request file"
  Assert-TextContains "case7 code cli was asked to open file" $stubLogText "code --reuse-window -g"
  Assert-TextNotContains "case7 code cli was not asked to open the repo root" $stubLogText ("code --reuse-window {0}" -f $tocRepo)

  Step "Case 8: check validates docs and runs the Docusaurus build"
  $checkRepo = New-MinimalDocsRepo -Name "repo-check-pass"
  $checkToolset = New-StubToolset -Name "toolset-check-pass"
  $checkResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $checkRepo `
    -CliArgs @("check") `
    -Toolset $checkToolset `
    -SandboxRoot (New-ScratchPath "sandbox-check-pass")
  $checkStubLog = Get-Content -LiteralPath $checkToolset.CommandLog -Raw
  Assert-Condition "case8 check exits cleanly" ($checkResult.ExitCode -eq 0) "exit code=0" "exit code=$($checkResult.ExitCode)"
  Assert-TextContains "case8 output confirms pass" $checkResult.OutputText "Docs check passed."
  Assert-TextContains "case8 npm build was invoked" $checkStubLog "npm run build"

  Step "Case 9: check rejects invalid slugs before attempting a build"
  $badSlugRepo = New-MinimalDocsRepo -Name "repo-check-bad-slug"
  $badSlugToolset = New-StubToolset -Name "toolset-check-bad-slug"
  $badDocPath = Join-Path $badSlugRepo "Docs\Bad-Slug.md"
  $badDocContent = @'
---
title: Bad Slug
slug: /docs/bad-slug
---

# Bad Slug
'@
  Write-Utf8NoBomFile -Path $badDocPath -Content $badDocContent
  $badSlugResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $badSlugRepo `
    -CliArgs @("check") `
    -Toolset $badSlugToolset `
    -SandboxRoot (New-ScratchPath "sandbox-check-bad-slug")
  $badSlugStubLog = Get-Content -LiteralPath $badSlugToolset.CommandLog -Raw
  Assert-Condition "case9 check fails for /docs/ slug" ($badSlugResult.ExitCode -ne 0) "exit code=$($badSlugResult.ExitCode)" "expected non-zero exit code"
  Assert-TextContains "case9 output explains bad slug" $badSlugResult.OutputText "Slug should not start with /docs/:"
  Assert-TextNotContains "case9 npm build not invoked on validation failure" $badSlugStubLog "npm run build"

  Step "Case 10: check rejects unprocessed TOC markers"
  $markerRepo = New-MinimalDocsRepo -Name "repo-check-toc-marker"
  $markerToolset = New-StubToolset -Name "toolset-check-toc-marker"
  $markerDocPath = Join-Path $markerRepo "Docs\Marker.md"
  $markerDocContent = @'
---
title: Marker
slug: /marker
---

# Marker

<!-- docs-tools-toc -->
'@
  Write-Utf8NoBomFile -Path $markerDocPath -Content $markerDocContent
  $markerResult = Invoke-DocsToolsCommand `
    -ScratchRepoRoot $markerRepo `
    -CliArgs @("check") `
    -Toolset $markerToolset `
    -SandboxRoot (New-ScratchPath "sandbox-check-toc-marker")
  Assert-Condition "case10 check fails for unprocessed toc marker" ($markerResult.ExitCode -ne 0) "exit code=$($markerResult.ExitCode)" "expected non-zero exit code"
  Assert-TextContains "case10 output explains toc marker" $markerResult.OutputText "Unprocessed TOC marker remains in:"

  Step "Summary"
  Write-Log ("PASS={0} FAIL={1} WARN={2} SKIP={3}" -f $script:PassCount, $script:FailCount, $script:WarnCount, $script:SkipCount) Cyan
  if ($script:FailCount -eq 0) {
    Write-Log "Docs tools tests passed." Green
  }
  else {
    Write-Log "Docs tools tests failed." Red
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
