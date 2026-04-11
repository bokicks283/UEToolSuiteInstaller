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

$initScript = Join-Path $repoRoot "Scripts\Init-Repo.ps1"
if (-not (Test-Path -LiteralPath $initScript)) {
  throw "Init script not found: $initScript"
}

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$resultsDir = Join-Path $repoRoot "Scripts\Tests\Test-InitRepoToolReadinessResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "InitRepoToolReadiness-$stamp.log"

$script:PassCount = 0
$script:FailCount = 0
$script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("init repo tool readiness tests " + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $script:TempRoot | Out-Null

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

function Assert-Condition {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][bool]$Condition,
    [string]$PassDetail = "condition is true",
    [string]$FailDetail = "condition is false"
  )

  if ($Condition) {
    Pass $Name $PassDetail
    return
  }

  Fail $Name $FailDetail
}

function Assert-TextContains {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
    [Parameter(Mandatory)][string]$Needle
  )

  if ([string]::Concat($Text).Contains($Needle)) {
    Pass $Name "matched: $Needle"
    return
  }

  Fail $Name "missing expected text: $Needle"
}

function Assert-TextNotContains {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
    [Parameter(Mandatory)][string]$Needle
  )

  if (-not [string]::Concat($Text).Contains($Needle)) {
    Pass $Name "did not match: $Needle"
    return
  }

  Fail $Name "unexpected text found: $Needle"
}

function Write-Utf8NoBomFile {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content
  )

  $directory = Split-Path -Parent $Path
  if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
  }

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Remove-AnsiEscapeSequences([string]$Text) {
  if ($null -eq $Text) { return "" }
  return ([regex]::Replace($Text, "`e\[[0-9;?]*[ -/]*[@-~]", ""))
}

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
    [switch]$IncludeArtSourceTool
  )

  $target = Join-Path $script:TempRoot $Name
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  & git -C $target init | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "git init failed for target repo: $target"
  }

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

  foreach ($hookName in @("pre-commit", "pre-push", "post-checkout", "post-merge", "post-commit", "post-rewrite")) {
    Write-Utf8NoBomFile -Path (Join-Path $target ".githooks\$hookName") -Content "#!/usr/bin/env bash`nexit 0`n"
  }

  Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\git-hooks\colors.sh") -Content "#!/usr/bin/env bash`n"
  Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\git-hooks\hook-common.sh") -Content "#!/usr/bin/env bash`n"
  Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\git-hooks\Enable-GitHooks.ps1") -Content "Write-Host 'Enable hooks stub'`n"
  Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\git-hooks\Test-Hooks.ps1") -Content "Write-Host 'Hook self-test stub'`n"

  Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\git-tools\conflicts.ps1") -Content "Write-Host 'conflicts stub'`n"
  Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\git-tools\GitConflictHelpers.ps1") -Content "function Test-GitConflictHelperStub { `$true }`n"

  New-Item -ItemType Directory -Force -Path (Join-Path $target "Scripts\Unreal") | Out-Null
  Copy-Item `
    -LiteralPath (Join-Path $repoRoot "Scripts\Unreal\ProjectContext.ps1") `
    -Destination (Join-Path $target "Scripts\Unreal\ProjectContext.ps1") `
    -Force

  Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\Unreal\ProjectShellAliases.ps1") -Content @'
function Install-ProjectShellAliases {
  [pscustomobject]@{
    ProfilePath = "stub-profile"
    AliasGroups = @()
    Aliases = @()
  }
}
'@

  if ($IncludeArtSourceTool) {
    Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\Unreal\New-ArtSourcePath.ps1") -Content "Write-Host 'art-tools stub'`n"
    foreach ($relativePath in @("ArtSource\_Template\Source", "ArtSource\_Template\Textures", "ArtSource\_Template\Exports")) {
      New-Item -ItemType Directory -Force -Path (Join-Path $target $relativePath) | Out-Null
    }
  }

  if ($IncludeDocsSite) {
    Write-Utf8NoBomFile -Path (Join-Path $target "website\package.json") -Content @'
{
  "scripts": {
    "build": "docusaurus build"
  },
  "dependencies": {}
}
'@

    Write-Utf8NoBomFile -Path (Join-Path $target "Scripts\Docs\DocsTools.ps1") -Content @'
[CmdletBinding()]
param(
  [string]$RepoRoot,
  [string[]]$CommandArgs,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ExtraArgs
)

$effectiveCommandArgs = @($CommandArgs) + @($ExtraArgs) + @($MyInvocation.UnboundArguments)
$command = ($effectiveCommandArgs | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1)

if (-not [string]::IsNullOrWhiteSpace($env:INIT_REPO_TOOL_READINESS_LOG)) {
  Add-Content -LiteralPath $env:INIT_REPO_TOOL_READINESS_LOG -Value ("docs-tools " + ($effectiveCommandArgs -join " ") + " repo=$RepoRoot")
}

switch ($command) {
  "install-bridge" {
    Write-Output "Installed VS Code bridge to: stub"
    Write-Output "Markdown All in One is already installed."
    Write-Output "Reload VS Code windows to activate the bridge."
    exit 0
  }
  "doctor" {
    Write-Output "Repo root: $RepoRoot"
    Write-Output "Website root: $RepoRoot\website"
    Write-Output "Node installed: True"
    Write-Output "npm installed: True"
    Write-Output "website/node_modules present: True"
    Write-Output "VS Code CLI found: True"
    Write-Output "TOC automation ready: True"
    exit 0
  }
  default {
    Write-Error "Unexpected docs-tools command: $($effectiveCommandArgs -join ' ')"
    exit 1
  }
}
'@
  }

  return $target
}

function Invoke-InitRepo {
  param(
    [Parameter(Mandatory)][string]$TargetRepoRoot,
    [Parameter(Mandatory)][string]$StubRoot,
    [Parameter(Mandatory)][string]$CommandLog,
    [string[]]$ExtraArgs = @()
  )

  $previousPath = $env:Path
  $previousCommandLog = $env:INIT_REPO_TOOL_READINESS_LOG
  try {
    $env:Path = "$StubRoot;$env:Path"
    $env:INIT_REPO_TOOL_READINESS_LOG = $CommandLog

    $pwshArgs = @(
      "-NoLogo",
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-File", $initScript,
      "-RepoRoot", $TargetRepoRoot,
      "-SkipLfsPull",
      "-SkipShellAliases",
      "-SkipUnrealSync"
    ) + @($ExtraArgs)

    Write-Log ">> pwsh $($pwshArgs -join ' ')" DarkGray
    $output = @(& pwsh @pwshArgs 2>&1)
    $exitCode = $LASTEXITCODE
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
  Assert-TextContains "case1 npm install invoked" $commandLogText "npm cwd="
  Assert-TextContains "case1 npm install args" $commandLogText "args=install"
  Assert-TextContains "case1 bridge install invoked" $commandLogText "docs-tools install-bridge"
  Assert-TextContains "case1 docs doctor invoked" $commandLogText "docs-tools doctor"
  Assert-Condition "case1 node_modules created" (Test-Path -LiteralPath (Join-Path $targetRepo "website\node_modules")) "website/node_modules created" "website/node_modules missing"
  Assert-TextContains "case1 summary shown" $result.OutputText "Tool readiness summary:"
  Assert-TextContains "case1 git-lfs ready" $result.OutputText "[OK] git-lfs"
  Assert-TextContains "case1 node ready" $result.OutputText "[OK] node/npm"
  Assert-TextContains "case1 docs deps ready" $result.OutputText "[OK] docs dependencies"
  Assert-TextContains "case1 docs bridge ready" $result.OutputText "[OK] docs VS Code bridge"
  Assert-TextContains "case1 docs tools ready" $result.OutputText "[OK] docs-tools"
  Assert-TextContains "case1 art tools ready" $result.OutputText "[OK] art-tools"
  Assert-TextContains "case1 aliases skipped" $result.OutputText "[SKIP] PowerShell aliases"
  Assert-TextContains "case1 ue-tools skipped" $result.OutputText "[SKIP] ue-tools"

  Step "Case 2: init succeeds when optional docs and ArtSource tools are not installed"
  $commandLog2 = Join-Path $script:TempRoot "case2-commands.log"
  Write-Utf8NoBomFile -Path $commandLog2 -Content ""
  $targetRepoWithoutOptionalTools = New-InitRepoFixture -Name "target without optional tools"
  $result2 = Invoke-InitRepo -TargetRepoRoot $targetRepoWithoutOptionalTools -StubRoot $stubRoot -CommandLog $commandLog2
  Assert-Condition "case2 init exits cleanly" ($result2.ExitCode -eq 0) "exit=0" "exit=$($result2.ExitCode)"
  Assert-TextContains "case2 docs tools skipped" $result2.OutputText "[SKIP] docs-tools"
  Assert-TextContains "case2 art tools skipped" $result2.OutputText "[SKIP] art-tools"
  Assert-TextContains "case2 ue-tools skipped" $result2.OutputText "[SKIP] ue-tools"

  Step "Case 3: SkipOptionalToolSetup leaves installed optional tools alone"
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
  Assert-TextContains "case3 docs tools skipped" $result3.OutputText "[SKIP] docs-tools"
  Assert-TextContains "case3 art tools skipped" $result3.OutputText "[SKIP] art-tools"
  Assert-TextNotContains "case3 npm install not invoked" $commandLog3Text "npm cwd="
  Assert-TextNotContains "case3 bridge install not invoked" $commandLog3Text "docs-tools install-bridge"
  Assert-TextNotContains "case3 doctor not invoked" $commandLog3Text "docs-tools doctor"

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
