[CmdletBinding()]
param(
  [switch]$NoCleanup,
  [switch]$FailFast
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = ((git rev-parse --show-toplevel 2>$null) | Select-Object -First 1).Trim()
if (-not $repoRoot) { throw "Not inside a git repository." }
Set-Location $repoRoot

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$resultsDir = Join-Path $repoRoot "Scripts\Tests\Test-DocsToolsResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "DocsToolsTest-$stamp.log"
$tempRoot = Join-Path $resultsDir "scratch-$stamp"
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$testHarnessPath = Join-Path $repoRoot "Scripts\Tests\TestHarness.ps1"
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
  $themePresetsSource = Join-Path $repoRoot "website\theme-presets"
  if (Test-Path -LiteralPath $themePresetsSource -PathType Container) {
    Copy-Item -LiteralPath $themePresetsSource -Destination (Join-Path $scratchWebsiteRoot "theme-presets") -Recurse -Force
  }
  $cssSource = Join-Path $repoRoot "website\src\css\custom.css"
  if (Test-Path -LiteralPath $cssSource -PathType Leaf) {
    $cssDestination = Join-Path $scratchWebsiteRoot "src\css\custom.css"
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
    $escapedCoreModulePath = $coreModulePath -replace "'", "''"
    $escapedScriptPath = $script:DocsToolsScriptPath -replace "'", "''"
    $escapedRepoRoot = $ScratchRepoRoot -replace "'", "''"
    $escapedCliArgs = @($CliArgs | ForEach-Object { "'" + (("$($_)") -replace "'", "''") + "'" })
    $commandText = @"
`$cliArgs = @($($escapedCliArgs -join ', '))
`$previousAutoRunFlag = `$env:UE_TOOLS_DOCS_RUNTIME_NO_AUTORUN
`$env:UE_TOOLS_DOCS_RUNTIME_NO_AUTORUN = '1'
try {
  Import-Module -Name '$escapedCoreModulePath' -Force -DisableNameChecking | Out-Null
  `$scriptsRoot = Split-Path -Parent (Split-Path -Parent '$escapedScriptPath')
  if (Get-Command -Name 'Set-UEToolSuiteRuntimeContext' -CommandType Function -ErrorAction SilentlyContinue) {
    Set-UEToolSuiteRuntimeContext -ScriptsRoot `$scriptsRoot -StateKey 'docs-tools-test' -LogPrefix '[Docs]'
  }
  `$docsModule = Import-Module -Name '$escapedScriptPath' -Force -DisableNameChecking -PassThru
  `$repoResolver = Get-Command -Name 'Get-DocsToolsRepoRoot' -Module `$docsModule.Name -CommandType Function -ErrorAction SilentlyContinue
  if (-not `$repoResolver) { throw 'Get-DocsToolsRepoRoot was not exported by docs module.' }
  `$entrypoint = Get-Command -Name 'Invoke-DocsToolsMain' -Module `$docsModule.Name -CommandType Function -ErrorAction SilentlyContinue
  if (-not `$entrypoint) { throw 'Invoke-DocsToolsMain was not exported by docs module.' }
  `$resolvedRepoRoot = & `$repoResolver.Name -ExplicitRepoRoot '$escapedRepoRoot'
  & `$entrypoint.Name -ResolvedRepoRoot `$resolvedRepoRoot -CommandArguments `$cliArgs
}
catch {
  Write-Host ('Error: ' + `$_.Exception.Message) -ForegroundColor Red
  exit 1
}
finally {
  if (`$null -eq `$previousAutoRunFlag) {
    Remove-Item Env:UE_TOOLS_DOCS_RUNTIME_NO_AUTORUN -ErrorAction SilentlyContinue
  }
  else {
    `$env:UE_TOOLS_DOCS_RUNTIME_NO_AUTORUN = `$previousAutoRunFlag
  }
}
"@

    $allArgs = @(
      "-NoLogo",
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-Command", $commandText
    )

    $output = @(& $pwshPath @allArgs 2>&1)
    $exitCode = $LASTEXITCODE

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
  Assert-TextContains "case1f custom css updated to ocean palette" (Get-Content -LiteralPath (Join-Path $themeAdoptRepo "website\src\css\custom.css") -Raw) "--ifm-color-primary: #0d7ea2;"
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

      $docsConfigPath = Join-Path $apiHostRepo "website\docusaurus.config.ts"
      if (Test-Path -LiteralPath $docsConfigPath -PathType Leaf) {
        $docsConfigBeforeSeed = Get-Content -LiteralPath $docsConfigPath -Raw
        $docsConfigAfterSeed = [regex]::Replace(
          $docsConfigBeforeSeed,
          "(?s)(type:\s*'doc'\s*,\s*docId:\s*')[^']+('\s*,\s*position:\s*'left'\s*,\s*label:\s*'Setup')",
          ('$1Setup$2')
        )
        if ($docsConfigAfterSeed -ne $docsConfigBeforeSeed) {
          Write-Utf8NoBomFile -Path $docsConfigPath -Content $docsConfigAfterSeed
        }
        Assert-TextContains "case1g seed setup navbar docId reference" $docsConfigAfterSeed "docId: 'Setup'"
      }

      $moveReferencedPageBody = @{
        sourcePath = "Setup"
        destinationParentPath = "Guides Space"
        insertIndex = 0
      } | ConvertTo-Json -Depth 6
      $moveReferencedPage = Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/move" -Method Post -ContentType "application/json" -Body $moveReferencedPageBody -TimeoutSec 5
      Assert-Condition "case1g api move handles navbar docId references" ($moveReferencedPage.ok -eq $true) "move referenced page ok=true" "move referenced page response did not set ok=true"
      $docsConfigAfterReferencedMove = Get-Content -LiteralPath (Join-Path $apiHostRepo "website\docusaurus.config.ts") -Raw
      Assert-TextContains "case1g api move rewrites navbar docId reference after path move" $docsConfigAfterReferencedMove "docId: 'Guides Space/Setup'"
      Assert-TextNotContains "case1g api move removes stale navbar docId reference" $docsConfigAfterReferencedMove "docId: 'Setup'"
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
      -ExtraEnv @{ UE_TOOLS_DOCS_START_CONTINUE = "yes" }
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

    Step "Case 5c: start --background tracks multiple servers and stop removes tracked state"
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
      -ExtraEnv @{ UE_TOOLS_DOCS_START_CONTINUE = "yes" }
    $secondStartResult = Invoke-DocsToolsCommand `
      -ScratchRepoRoot $multiServerRepo `
      -CliArgs @("start", "--background", "--port", "$secondMultiPort") `
      -Toolset $multiServerToolset `
      -SandboxRoot $multiServerSandbox `
      -ExtraEnv @{ UE_TOOLS_DOCS_START_CONTINUE = "yes" }
    $multiStateFiles = @(Get-ChildItem -Path (Join-Path $firstStartResult.SandboxTemp "ueproject-ue-tools-docs") -Recurse -Filter docs-server.json -ErrorAction SilentlyContinue)
    $multiStateRaw = Get-Content -LiteralPath $multiStateFiles[0].FullName -Raw | ConvertFrom-Json
    $multiEntries = if ($multiStateRaw.PSObject.Properties["servers"]) { @($multiStateRaw.servers) } else { @($multiStateRaw) }
    $multiPids = @($multiEntries | ForEach-Object { [int]$_.processId } | Select-Object -Unique)
    Assert-Condition "case5c first start exits cleanly" ($firstStartResult.ExitCode -eq 0) "exit code=0" "exit code=$($firstStartResult.ExitCode)"
    Assert-Condition "case5c second start exits cleanly" ($secondStartResult.ExitCode -eq 0) "exit code=0" "exit code=$($secondStartResult.ExitCode)"
    Assert-Condition "case5c state file remains valid after second start" ($multiEntries.Count -ge 1) "tracked servers=$($multiEntries.Count)" "expected at least one tracked server entry"
    Assert-Condition "case5c second start reports a handled path" (
      $secondStartResult.OutputText.Contains("Started docs dev server in the background") -or
      $secondStartResult.OutputText.Contains("Docs dev server start aborted")
    ) "second start returned a handled result"
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
      -ExtraEnv @{ UE_TOOLS_DOCS_START_CONTINUE = "yes" }
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
      Assert-TextContains "case5d runtime config stores api url" $editorRuntimeConfigText '"apiUrl": "http://127.0.0.1:'
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
  }
  else {
    Step "Case 5b/5c/5d: background runtime lifecycle (optional)"
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
