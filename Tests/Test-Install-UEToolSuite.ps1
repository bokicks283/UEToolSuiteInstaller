[CmdletBinding()]
param(
  [switch]$NoCleanup,
  [switch]$FailFast
)

$ErrorActionPreference = "Stop"

$installerRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$installerScript = Join-Path $installerRoot "Install-UEToolSuite.ps1"
$payloadRoot = Join-Path $installerRoot "payload"

if (-not (Test-Path -LiteralPath $installerScript -PathType Leaf)) { throw "Installer script not found: $installerScript" }
if (-not (Test-Path -LiteralPath $payloadRoot -PathType Container)) { throw "Payload root not found: $payloadRoot" }

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$resultsDir = Join-Path $PSScriptRoot "Test-Install-UEToolSuiteResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "Install-UEToolSuite-$stamp.log"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ue tool suite installer tests " + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

$script:PassCount = 0
$script:FailCount = 0

function Write-Log {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray)
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
  param([string]$Name, [bool]$Condition, [string]$PassDetail = "ok", [string]$FailDetail = "failed")
  if ($Condition) { Pass $Name $PassDetail } else { Fail $Name $FailDetail }
}

function Assert-PathExists([string]$Name, [string]$Path) {
  Assert-Condition $Name (Test-Path -LiteralPath $Path) "present" "missing: $Path"
}

function Assert-PathMissing([string]$Name, [string]$Path) {
  Assert-Condition $Name (-not (Test-Path -LiteralPath $Path)) "absent" "unexpected path: $Path"
}

function Write-Utf8NoBomFile {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
  $parent = Split-Path -Path $Path -Parent
  if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Remove-AnsiEscapeSequences([string]$Text) {
  if ($null -eq $Text) { return "" }
  return ([regex]::Replace($Text, "`e\[[0-9;?]*[ -/]*[@-~]", ""))
}

function Invoke-Installer {
  param([Parameter(Mandatory)][string]$TargetRoot, [string[]]$ExtraArgs)

  $pwshArgs = @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $installerScript,
    "-TargetRepoRoot", $TargetRoot
  ) + @($ExtraArgs)

  Write-Log ">> pwsh $($pwshArgs -join ' ')" DarkGray
  $out = @(& pwsh @pwshArgs 2>&1)
  $code = $LASTEXITCODE
  $normalized = @()
  foreach ($line in $out) {
    $text = Remove-AnsiEscapeSequences "$line"
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

function New-TargetRepo([string]$Name) {
  $target = Join-Path $tempRoot $Name
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  & git -C $target init | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "git init failed for target repo: $target" }
  & git -C $target config user.email "ue-tool-suite-test@example.invalid" | Out-Null
  & git -C $target config user.name "UE Tool Suite Installer Test" | Out-Null

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

  return $target
}

try {
  Step "UE tool suite installer tests ($stamp)"
  Write-Log "Installer: $installerScript" Cyan
  Write-Log "Payload  : $payloadRoot" Cyan
  Write-Log "Temp     : $tempRoot" Cyan

  Step "Case 1: fresh install copies portable tools, docs, and website"
  $targetRepo = New-TargetRepo "fresh target"
  $result = Invoke-Installer -TargetRoot $targetRepo -ExtraArgs @("-SkipTests")
  Assert-Condition "case1 installer exits cleanly" ($result.Code -eq 0) "exit=0" "exit=$($result.Code)"
  foreach ($relativePath in @(
      ".githooks\post-checkout",
      "Scripts\Init-Repo.ps1",
      "Scripts\Unreal\UnrealSync.ps1",
      "Scripts\Docs\DocsTools.ps1",
      "Docs\Setup.md",
      "Docs\Pipeline\README.md",
      "Docs\DocsSite\Docusaurus-Setup.md",
      "website\package.json",
      "website\docusaurus.config.ts"
    )) {
    Assert-PathExists "case1 installed $relativePath" (Join-Path $targetRepo $relativePath)
  }

  foreach ($relativePath in @(
      "Scripts\Install-UEProjectTools.ps1",
      "Docs\GameDesign\README.md",
      "Docs\ProjectStructure\Target-Structure.md",
      "Docs\Codex\Project-Context.md"
    )) {
    Assert-PathMissing "case1 skipped $relativePath" (Join-Path $targetRepo $relativePath)
  }

  Step "Case 2: update removes legacy installer and writes backup"
  Write-Utf8NoBomFile -Path (Join-Path $targetRepo "Scripts\Install-UEProjectTools.ps1") -Content "legacy installer`n"
  Write-Utf8NoBomFile -Path (Join-Path $targetRepo "Scripts\Unreal\UnrealSync.ps1") -Content "legacy sync`n"
  $updateResult = Invoke-Installer -TargetRoot $targetRepo -ExtraArgs @("-SkipTests")
  Assert-Condition "case2 update exits cleanly" ($updateResult.Code -eq 0) "exit=0" "exit=$($updateResult.Code)"
  Assert-PathMissing "case2 legacy installer removed" (Join-Path $targetRepo "Scripts\Install-UEProjectTools.ps1")
  $backupMatches = @(Get-ChildItem -LiteralPath (Join-Path $targetRepo ".ue-tools-installer-backups") -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "UnrealSync.ps1" })
  Assert-Condition "case2 backup created for replaced tool" ($backupMatches.Count -gt 0) "backup count=$($backupMatches.Count)" "backup missing"

  Step "Case 3: installer can run target Init-Repo"
  $initRepo = New-TargetRepo "run init target"
  $initResult = Invoke-Installer -TargetRoot $initRepo -ExtraArgs @(
    "-SkipTests",
    "-RunInit",
    "-SkipLfsPull",
    "-SkipShellAliases",
    "-SkipOptionalToolSetup",
    "-SkipDocsSetup",
    "-SkipUnrealSync"
  )
  Assert-Condition "case3 init install exits cleanly" ($initResult.Code -eq 0) "exit=0" "exit=$($initResult.Code)"
  Assert-Condition "case3 init ran" ($initResult.Output -like "*Repo initialization complete.*") "init completed" "init output missing completion"
  $hooksPath = (& git -C $initRepo config --local --get core.hooksPath 2>$null | Select-Object -First 1)
  Assert-Condition "case3 hooks path configured" ($hooksPath -eq ".githooks") "hooksPath=.githooks" "hooksPath=$hooksPath"

  Step "Summary"
  Write-Log ("PASS={0} FAIL={1}" -f $script:PassCount, $script:FailCount) Cyan
  if ($script:FailCount -eq 0) {
    Write-Log "UE tool suite installer tests passed." Green
  }
  else {
    Write-Log "UE tool suite installer tests failed." Red
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
  if (-not $NoCleanup -and (Test-Path -LiteralPath $tempRoot)) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Log ""
  Write-Log "Log saved: $logPath" Cyan
}
