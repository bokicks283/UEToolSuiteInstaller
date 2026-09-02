$script:TestHarnessLogPath = $null
$script:TestHarnessFailFast = $false

function Resolve-UEToolSuiteRuntimeFile {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RelativePath
  )

  $localPath = Join-Path $RepoRoot $RelativePath
  if (Test-Path -LiteralPath $localPath -PathType Leaf) { return (Resolve-Path -LiteralPath $localPath).Path }

  $markerPath = Join-Path $RepoRoot ".ue-tools\global-cli.json"
  if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
    $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
    $version = [string]$marker.version
    if ($version -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
      throw "The global CLI project marker declares an invalid version '$version'."
    }
    $globalRoot = [string]$env:UE_TOOLS_GLOBAL_CLI_ROOT
    if ([string]::IsNullOrWhiteSpace($globalRoot)) {
      $globalRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) "UEToolSuite"
    }
    $globalVersionRoot = Join-Path ([IO.Path]::GetFullPath($globalRoot)) "versions\$version"
    $globalPath = Join-Path $globalVersionRoot $RelativePath
    if (Test-Path -LiteralPath $globalPath -PathType Leaf) { return (Resolve-Path -LiteralPath $globalPath).Path }
  }

  throw "UE Tool Suite runtime file not found locally or through .ue-tools/global-cli.json: $RelativePath"
}

function Initialize-TestHarness {
  param(
    [Parameter(Mandatory)][string]$LogPath,
    [switch]$FailFast
  )

  $script:TestHarnessLogPath = $LogPath
  $script:TestHarnessFailFast = [bool]$FailFast
}

function Get-TestCounterValue {
  param([Parameter(Mandatory)][string]$Name)

  $variable = Get-Variable -Scope Script -Name $Name -ErrorAction SilentlyContinue
  if ($null -eq $variable) {
    return 0
  }

  return [int]$variable.Value
}

function Add-TestCounterValue {
  param([Parameter(Mandatory)][string]$Name)

  $current = Get-TestCounterValue -Name $Name
  Set-Variable -Scope Script -Name $Name -Value ($current + 1)
}

function Write-Log {
  param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
    [ConsoleColor]$Color = [ConsoleColor]::Gray
  )

  Write-Host $Message -ForegroundColor $Color
  if (-not [string]::IsNullOrWhiteSpace($script:TestHarnessLogPath)) {
    Add-Content -LiteralPath $script:TestHarnessLogPath -Value $Message -Encoding UTF8
  }
}

function Step {
  param([Parameter(Mandatory)][string]$Title)

  Write-Log ""
  Write-Log "============================================================" DarkGray
  Write-Log $Title DarkGray
  Write-Log "============================================================" DarkGray
}

function Pass {
  param(
    [Parameter(Mandatory)][string]$Name,
    [string]$Detail = "ok"
  )

  Add-TestCounterValue -Name "PassCount"
  Write-Log "[PASS] $Name - $Detail" Green
}

function Fail {
  param(
    [Parameter(Mandatory)][string]$Name,
    [string]$Detail = "failed"
  )

  Add-TestCounterValue -Name "FailCount"
  Write-Log "[FAIL] $Name - $Detail" Red
  if ($script:TestHarnessFailFast) { throw "FAILFAST" }
}

function Warn {
  param(
    [Parameter(Mandatory)][string]$Name,
    [string]$Detail = "warning"
  )

  Add-TestCounterValue -Name "WarnCount"
  Write-Log "[WARN] $Name - $Detail" Yellow
}

function Skip {
  param(
    [Parameter(Mandatory)][string]$Name,
    [string]$Detail = "skipped"
  )

  Add-TestCounterValue -Name "SkipCount"
  Write-Log "[SKIP] $Name - $Detail" DarkYellow
}

function Assert-Condition {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][bool]$Condition,
    [string]$PassDetail = "condition is true",
    [string]$FailDetail = "condition is false"
  )

  if ($Condition) {
    Pass -Name $Name -Detail $PassDetail
    return
  }

  Fail -Name $Name -Detail $FailDetail
}

function Assert-Code {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][int]$Code,
    [Parameter(Mandatory)][int]$Expected
  )

  Assert-Condition `
    -Name $Name `
    -Condition ($Code -eq $Expected) `
    -PassDetail "exit=$Code" `
    -FailDetail "expected exit=$Expected, got exit=$Code"
}

function Assert-TextContains {
  param(
    [Parameter(Mandatory)][string]$Name,
    [AllowNull()][AllowEmptyString()][string]$Text,
    [Parameter(Mandatory)][string]$Needle
  )

  Assert-Condition `
    -Name $Name `
    -Condition ([string]::Concat($Text).Contains($Needle)) `
    -PassDetail "matched: $Needle" `
    -FailDetail "missing expected text: $Needle"
}

function Assert-TextNotContains {
  param(
    [Parameter(Mandatory)][string]$Name,
    [AllowNull()][AllowEmptyString()][string]$Text,
    [Parameter(Mandatory)][string]$Needle
  )

  Assert-Condition `
    -Name $Name `
    -Condition (-not [string]::Concat($Text).Contains($Needle)) `
    -PassDetail "did not match: $Needle" `
    -FailDetail "unexpected text found: $Needle"
}

function Assert-OutputContains {
  param(
    [Parameter(Mandatory)][string]$Name,
    [AllowNull()][AllowEmptyString()][string]$Output,
    [Parameter(Mandatory)][string]$Needle
  )

  Assert-Condition `
    -Name $Name `
    -Condition ([string]::Concat($Output).Contains($Needle)) `
    -PassDetail "matched: $Needle" `
    -FailDetail "missing expected text: $Needle"
}

function Assert-OutputNotContains {
  param(
    [Parameter(Mandatory)][string]$Name,
    [AllowNull()][AllowEmptyString()][string]$Output,
    [Parameter(Mandatory)][string]$Needle
  )

  Assert-Condition `
    -Name $Name `
    -Condition (-not [string]::Concat($Output).Contains($Needle)) `
    -PassDetail "not present: $Needle" `
    -FailDetail "unexpected text present: $Needle"
}

function Remove-AnsiEscapeSequences {
  param([AllowNull()][string]$Text)
  if ($null -eq $Text) { return "" }
  return ([regex]::Replace($Text, "`e\[[0-9;?]*[ -/]*[@-~]", ""))
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

function Write-TextFileLf {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Content
  )

  $normalized = $Content -replace "`r`n", "`n" -replace "`r", "`n"
  Write-Utf8NoBomFile -Path $Path -Content $normalized
}
