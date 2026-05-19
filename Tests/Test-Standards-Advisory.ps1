[CmdletBinding()]
param(
  [switch]$FailFast,
  [switch]$Enforce
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$testHarnessPath = Join-Path $repoRoot "payload\Scripts\Tests\TestHarness.ps1"
if (-not (Test-Path -LiteralPath $testHarnessPath -PathType Leaf)) {
  throw "Test harness not found: $testHarnessPath"
}
. $testHarnessPath

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$resultsDir = Join-Path $PSScriptRoot "Test-Standards-AdvisoryResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "Standards-Advisory-$stamp.log"

$script:PassCount = 0
$script:FailCount = 0
$script:WarnCount = 0
$script:SkipCount = 0
Initialize-TestHarness -LogPath $logPath -FailFast:$FailFast

function Get-PowerShellPaths {
  $paths = New-Object System.Collections.Generic.List[string]
  $roots = @(
    "Install-UEToolSuite.ps1",
    "Scripts",
    "Tests",
    "payload\Scripts"
  )

  foreach ($root in $roots) {
    $full = Join-Path $repoRoot $root
    if (-not (Test-Path -LiteralPath $full)) { continue }
    if (Test-Path -LiteralPath $full -PathType Leaf) {
      $paths.Add((Resolve-Path -LiteralPath $full).Path) | Out-Null
      continue
    }

    $files = Get-ChildItem -LiteralPath $full -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object {
        $_.Extension -in @(".ps1", ".psm1", ".psd1") -and
        $_.FullName -notmatch "\\(bin|obj|dist)\\"
      }
    foreach ($file in $files) {
      $paths.Add($file.FullName) | Out-Null
    }
  }

  return @($paths | Sort-Object -Unique)
}

function Get-ShellScriptPaths {
  $paths = New-Object System.Collections.Generic.List[string]
  $shellRoots = @(
    (Join-Path $repoRoot "payload\.githooks"),
    (Join-Path $repoRoot "payload\Scripts\git-hooks")
  )

  foreach ($root in $shellRoots) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    $files = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object {
        $_.Extension -eq ".sh" -or
        $_.Name -in @("post-checkout", "post-merge", "post-commit", "post-rewrite", "pre-commit", "pre-push")
      }
    foreach ($file in $files) {
      $paths.Add($file.FullName) | Out-Null
    }
  }

  return @($paths | Sort-Object -Unique)
}

try {
  Step "Standards advisory checks ($stamp)"
  Write-Log "Repo: $repoRoot" Cyan
  Write-Log "Log : $logPath" Cyan
  Write-Log "Mode: $(if ($Enforce) { 'enforced' } else { 'advisory' })" Cyan

  Step "PowerShell Script Analyzer"
  $psAnalyzerCommand = Get-Command -Name "Invoke-ScriptAnalyzer" -ErrorAction SilentlyContinue
  if (-not $psAnalyzerCommand) {
    Warn "PSScriptAnalyzer" "Invoke-ScriptAnalyzer not found; skipping advisory check."
  }
  else {
    $psFiles = @(Get-PowerShellPaths)
    if ($psFiles.Count -lt 1) {
      Skip "PSScriptAnalyzer" "No PowerShell files matched scan roots."
    }
    else {
      Write-Log "Scanning $($psFiles.Count) PowerShell files..." DarkGray
      $findings = @(Invoke-ScriptAnalyzer -Path $psFiles -ErrorAction Stop)
      if ($findings.Count -eq 0) {
        Pass "PSScriptAnalyzer" "No findings."
      }
      else {
        $severityOrder = @{ Error = 0; Warning = 1; Information = 2; ParseError = 3 }
        $sorted = @(
          $findings | Sort-Object `
            @{ Expression = { if ($severityOrder.ContainsKey($_.Severity)) { $severityOrder[$_.Severity] } else { 99 } } }, `
            ScriptName, Line, RuleName
        )
        foreach ($finding in $sorted) {
          $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $finding.ScriptPath)
          Write-Log ("   [{0}] {1} {2}:{3} {4}" -f $finding.Severity, $finding.RuleName, $relativePath, $finding.Line, $finding.Message) Yellow
        }

        if ($Enforce) {
          Fail "PSScriptAnalyzer" "Findings=$($findings.Count)"
        }
        else {
          Warn "PSScriptAnalyzer" "Advisory findings=$($findings.Count)"
        }
      }
    }
  }

  Step "shellcheck"
  $shellcheckCommand = Get-Command -Name "shellcheck" -ErrorAction SilentlyContinue
  if (-not $shellcheckCommand) {
    Warn "shellcheck" "shellcheck not found; skipping advisory check."
  }
  else {
    $shellFiles = @(Get-ShellScriptPaths)
    if ($shellFiles.Count -lt 1) {
      Skip "shellcheck" "No shell scripts matched scan roots."
    }
    else {
      Write-Log "Scanning $($shellFiles.Count) shell scripts..." DarkGray
      $allOutput = New-Object System.Collections.Generic.List[string]
      $hasFindings = $false
      foreach ($path in $shellFiles) {
        $output = @(& $shellcheckCommand.Source -f gcc -S warning -- "$path" 2>&1)
        if ($LASTEXITCODE -gt 0) {
          $hasFindings = $true
        }
        foreach ($line in $output) {
          $text = Remove-AnsiEscapeSequences "$line"
          if (-not [string]::IsNullOrWhiteSpace($text)) {
            $allOutput.Add($text) | Out-Null
          }
        }
      }

      if (-not $hasFindings -and $allOutput.Count -eq 0) {
        Pass "shellcheck" "No findings."
      }
      else {
        foreach ($line in $allOutput) {
          Write-Log ("   $line") Yellow
        }
        if ($Enforce) {
          Fail "shellcheck" "Findings present."
        }
        else {
          Warn "shellcheck" "Advisory findings present."
        }
      }
    }
  }

  Step "Summary"
  Write-Log ("PASS={0} FAIL={1} WARN={2} SKIP={3}" -f $script:PassCount, $script:FailCount, $script:WarnCount, $script:SkipCount) Cyan
  if ($script:FailCount -eq 0) {
    Write-Log "Standards advisory checks completed." Green
  }
  else {
    Write-Log "Standards checks failed in enforced mode." Red
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
  Write-Log ""
  Write-Log "Log saved: $logPath" Cyan
}
