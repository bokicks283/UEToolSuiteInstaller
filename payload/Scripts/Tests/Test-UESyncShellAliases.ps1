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
$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ue-tool-suite-alias-test-{0}-{1}" -f $stamp, ([guid]::NewGuid().ToString("N")))
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
Initialize-TestHarness -LogPath $logPath -FailFast:$FailFast

function Reset-LoadedAliases {
  Remove-Item -LiteralPath Function:\Invoke-UEToolSuiteShellCommand -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\ue-tools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\ue -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\art-tools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\docs-tools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\ai-tools -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Alias:\ai-prompt -ErrorAction SilentlyContinue
}

function Invoke-PwshCapture {
  param(
    [Parameter(Mandatory)][string[]]$Arguments,
    [string]$WorkingDirectory = $repoRoot
  )

  Push-Location $WorkingDirectory
  try {
    $output = @(& pwsh @Arguments 2>&1)
    $normalized = @($output | ForEach-Object { Remove-AnsiEscapeSequences "$_" })
    return [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      OutputText = ($normalized -join "`n")
    }
  }
  finally {
    Pop-Location
  }
}

function New-TestRepo {
  param([Parameter(Mandatory)][string]$Name)

  $path = Join-Path $scratchRoot $Name
  New-Item -ItemType Directory -Force -Path $path | Out-Null
  & git -C $path init | Out-Null
  & git -C $path config user.email "ue-alias-test@example.invalid" | Out-Null
  & git -C $path config user.name "UE Alias Test" | Out-Null

  $scriptsSource = Join-Path $repoRoot "Scripts"
  Copy-Item -LiteralPath $scriptsSource -Destination (Join-Path $path "Scripts") -Recurse -Force

  Write-Utf8NoBomFile -Path (Join-Path $path "PortableSample.uproject") -Content @'
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

  return $path
}

try {
  Step "UE dispatcher alias tests ($stamp)"
  Write-Log "Repo: $repoRoot" Cyan
  Write-Log "Log : $logPath" Cyan

  $aliasModulePath = Join-Path $repoRoot "Scripts\UETools\UEToolSuite.Aliases.psm1"
  Assert-Condition "case1 alias module path exists" (Test-Path -LiteralPath $aliasModulePath -PathType Leaf) "module found" "module missing: $aliasModulePath"
  Import-Module -Name $aliasModulePath -Force

  Step "Case 1: Register-ProjectShellAliases wires only ue-tools and ue"
  Reset-LoadedAliases
  $registered = Register-ProjectShellAliases -ScriptsRoot (Join-Path $repoRoot "Scripts")
  Assert-Condition "case1 ue-tools alias exists" ($null -ne (Get-Alias -Name "ue-tools" -ErrorAction SilentlyContinue)) "ue-tools alias registered" "ue-tools alias missing"
  Assert-Condition "case1 ue alias exists" ($null -ne (Get-Alias -Name "ue" -ErrorAction SilentlyContinue)) "ue alias registered" "ue alias missing"
  Assert-Condition "case1 ue-tools alias target" ((Get-Alias -Name "ue-tools").Definition -eq "Invoke-UEToolSuiteShellCommand") "ue-tools alias target correct" "ue-tools alias target incorrect"
  Assert-Condition "case1 ue alias target" ((Get-Alias -Name "ue").Definition -eq "Invoke-UEToolSuiteShellCommand") "ue alias target correct" "ue alias target incorrect"
  Assert-Condition "case1 no docs-tools alias" (-not (Get-Alias -Name "docs-tools" -ErrorAction SilentlyContinue)) "docs-tools absent" "docs-tools alias unexpectedly present"
  Assert-Condition "case1 no art-tools alias" (-not (Get-Alias -Name "art-tools" -ErrorAction SilentlyContinue)) "art-tools absent" "art-tools alias unexpectedly present"
  Assert-Condition "case1 no ai-tools alias" (-not (Get-Alias -Name "ai-tools" -ErrorAction SilentlyContinue)) "ai-tools absent" "ai-tools alias unexpectedly present"
  Assert-Condition "case1 no ai-prompt alias" (-not (Get-Alias -Name "ai-prompt" -ErrorAction SilentlyContinue)) "ai-prompt absent" "ai-prompt alias unexpectedly present"
  Assert-Condition "case1 metadata aliases" ((@($registered.Aliases) -join ",") -eq "ue-tools,ue") "metadata aliases are ue-tools,ue" ("metadata aliases: " + (@($registered.Aliases) -join ","))

  Step "Case 2: Install-ProjectShellAliases writes bootstrap markers and file"
  Reset-LoadedAliases
  $profilePath = Join-Path $scratchRoot "profile.ps1"
  $bootstrapPath = Join-Path $scratchRoot "bootstrap\UEToolsBootstrap.ps1"
  $installed = Install-ProjectShellAliases -ProfilePath $profilePath -BootstrapScriptPath $bootstrapPath -ScriptsRoot (Join-Path $repoRoot "Scripts")
  Assert-Condition "case2 profile created" (Test-Path -LiteralPath $profilePath -PathType Leaf) "profile created" "profile missing"
  Assert-Condition "case2 bootstrap created" (Test-Path -LiteralPath $bootstrapPath -PathType Leaf) "bootstrap created" "bootstrap missing"
  $profileText = Get-Content -LiteralPath $profilePath -Raw
  Assert-TextContains "case2 start marker present" $profileText "# >>> ue project shell aliases >>>"
  Assert-TextContains "case2 end marker present" $profileText "# <<< ue project shell aliases <<<"
  $bootstrapText = Get-Content -LiteralPath $bootstrapPath -Raw
  Assert-TextContains "case2 bootstrap defines dispatcher function" $bootstrapText "function Invoke-UEToolSuiteShellCommand"
  Assert-TextContains "case2 bootstrap registers ue-tools alias" $bootstrapText "Set-Alias -Name `"ue-tools`" -Value `"Invoke-UEToolSuiteShellCommand`" -Scope Global"
  Assert-TextContains "case2 bootstrap registers ue alias" $bootstrapText "Set-Alias -Name `"ue`" -Value `"Invoke-UEToolSuiteShellCommand`" -Scope Global"
  Assert-Condition "case2 metadata aliases" ((@($installed.Aliases) -join ",") -eq "ue-tools,ue") "metadata aliases are ue-tools,ue" ("metadata aliases: " + (@($installed.Aliases) -join ","))

  Step "Case 3: profile bootstrap resolves the active repo at command time"
  $repoA = New-TestRepo -Name "multi-repo-a"
  $repoB = New-TestRepo -Name "multi-repo-b"
  $multiProfilePath = Join-Path $scratchRoot "multi-profile.ps1"
  $multiBootstrapPath = Join-Path $scratchRoot "multi-bootstrap\UEToolsBootstrap.ps1"

  $null = Install-ProjectShellAliases -ProfilePath $multiProfilePath -BootstrapScriptPath $multiBootstrapPath -ScriptsRoot (Join-Path $repoA "Scripts")
  Assert-Condition "case3 profile exists" (Test-Path -LiteralPath $multiProfilePath -PathType Leaf) "profile exists" "profile missing"
  Assert-Condition "case3 bootstrap exists" (Test-Path -LiteralPath $multiBootstrapPath -PathType Leaf) "bootstrap exists" "bootstrap missing"

  $repoAScript = @(
    ". '$multiProfilePath'",
    "ue-tools help"
  ) -join "`n"
  $repoAResult = Invoke-PwshCapture -WorkingDirectory $repoA -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $repoAScript)
  Assert-Condition "case3 repoA alias help exits cleanly" ($repoAResult.ExitCode -eq 0) "exit=0" "exit=$($repoAResult.ExitCode)"
  Assert-TextContains "case3 repoA alias help output" $repoAResult.OutputText "UE Tool Suite dispatcher."

  $repoBScript = @(
    ". '$multiProfilePath'",
    "ue help"
  ) -join "`n"
  $repoBResult = Invoke-PwshCapture -WorkingDirectory $repoB -Arguments @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $repoBScript)
  Assert-Condition "case3 repoB alias help exits cleanly" ($repoBResult.ExitCode -eq 0) "exit=0" "exit=$($repoBResult.ExitCode)"
  Assert-TextContains "case3 repoB alias help output" $repoBResult.OutputText "UE Tool Suite dispatcher."

  Step "Summary"
  Write-Log ("PASS={0} FAIL={1} WARN={2} SKIP={3}" -f $script:PassCount, $script:FailCount, $script:WarnCount, $script:SkipCount) Cyan
  if ($script:FailCount -eq 0) {
    Write-Log "UE dispatcher alias tests passed." Green
  }
  else {
    Write-Log "UE dispatcher alias tests failed." Red
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
  Reset-LoadedAliases
  if (-not $NoCleanup -and (Test-Path -LiteralPath $scratchRoot)) {
    Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Log ""
  Write-Log "Log saved: $logPath" Cyan
}
