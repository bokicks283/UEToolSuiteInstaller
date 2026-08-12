[CmdletBinding()]
param(
  [string[]]$Name,
  [string[]]$Category,
  [switch]$List,
  [switch]$WriteJson,
  [switch]$NoCleanup,
  [switch]$FailFast,
  [switch]$IncludeExclusive,
  [switch]$PassThru
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$manifestScript = Join-Path $PSScriptRoot "ToolSuiteManifest.ps1"
if (-not (Test-Path -LiteralPath $manifestScript -PathType Leaf)) {
  throw "Tool suite test manifest not found: $manifestScript"
}
. $manifestScript

$fixtureHelper = Join-Path $PSScriptRoot "TestSupport\UEProjectFixtures.ps1"
if (-not (Test-Path -LiteralPath $fixtureHelper -PathType Leaf)) {
  throw "UE project fixture helper not found: $fixtureHelper"
}
. $fixtureHelper

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss") + "-" + $PID
$resultsDir = Join-Path $PSScriptRoot "UEToolSuiteResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "UEToolSuite-$stamp.log"
$jsonPath = if ($WriteJson) { Join-Path $resultsDir "UEToolSuite-$stamp.json" } else { $null }

function Write-SuiteLog {
  param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
    [ConsoleColor]$Color = [ConsoleColor]::Gray
  )

  Write-Host $Message -ForegroundColor $Color
  Add-Content -LiteralPath $logPath -Value $Message -Encoding UTF8
}

function Remove-AnsiEscapeSequences {
  param([AllowNull()][string]$Text)
  if ($null -eq $Text) { return "" }
  return ([regex]::Replace($Text, "`e\[[0-9;?]*[ -/]*[@-~]", ""))
}

function Write-ChildOutputLine {
  param([AllowNull()][string]$Text)

  $plainText = Remove-AnsiEscapeSequences -Text $Text
  $color = $null
  switch -Regex ($plainText) {
    '^\[PASS\]' { $color = [ConsoleColor]::Green; break }
    '^\[FAIL\]' { $color = [ConsoleColor]::Red; break }
    '^\[WARN\]' { $color = [ConsoleColor]::Yellow; break }
    '^\[SKIP\]' { $color = [ConsoleColor]::DarkYellow; break }
    '^\s*WARNING:' { $color = [ConsoleColor]::Yellow; break }
    '^\s*(Exception:|Write-Error:)' { $color = [ConsoleColor]::Red; break }
    '^\s*=+\s*$' { $color = [ConsoleColor]::DarkGray; break }
  }

  if ($null -ne $color) {
    Write-Host $plainText -ForegroundColor $color
  }
  else {
    Write-Host $plainText
  }

  Add-Content -LiteralPath $logPath -Value $plainText -Encoding UTF8
}

function Get-RepoState {
  param([string]$Root = $repoRoot)

  $head = ((git -C $Root rev-parse --verify HEAD 2>$null) | Select-Object -First 1)
  $branch = ((git -C $Root rev-parse --abbrev-ref HEAD 2>$null) | Select-Object -First 1)
  $dirtyLines = @((git -C $Root status --porcelain 2>$null) | Where-Object { $_ -and $_.Trim() -ne "" })

  [pscustomobject]@{
    HasCommits     = -not [string]::IsNullOrWhiteSpace($head)
    IsClean        = ($dirtyLines.Count -eq 0)
    Branch         = ([string]$branch).Trim()
    DirtyFileCount = $dirtyLines.Count
  }
}

function New-InstalledToolSuiteFixture {
  param([Parameter(Mandatory)]$Entry)

  $scratchRoot = New-TestScratchRoot -Prefix "ue tool suite installed fixture"
  $fixtureRepo = New-TestUEProjectRepo -Root $scratchRoot -Name "PortableSample" -WithGit -WithDocsSite -WithArtSource -WithSourceModule
  Write-TestUtf8NoBomFile -Path (Join-Path $fixtureRepo "AGENTS.md") -Content "Read AGENTS.md first.`n"
  Write-TestUtf8NoBomFile -Path (Join-Path $fixtureRepo ".ai-local\Private-Context.md") -Content "Local test-only private context.`n"

  $installerScript = Join-Path $repoRoot "Install-UEToolSuite.ps1"
  $installArgs = @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $installerScript,
    "-TargetRepoRoot", $fixtureRepo,
    "-GlobalCliRoot", (Join-Path $scratchRoot "global cli root with spaces"),
    "-AdoptExistingWebsite",
    "-RunInit",
    "-InitNonInteractive",
    "-SkipLfsPull",
    "-SkipShellAliases",
    "-SkipOptionalToolSetup",
    "-SkipDocsSetup",
    "-SkipUnrealSync"
  )

  Write-SuiteLog "Preparing installed fixture for $($Entry.Name): $fixtureRepo" Cyan
  & pwsh @installArgs 2>&1 | ForEach-Object { Write-ChildOutputLine -Text "$_" }
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to prepare installed fixture for $($Entry.Name). Installer exit code: $LASTEXITCODE"
  }

  # Repository tests are intentionally excluded from real installs. Hydrate only
  # source test files into this disposable fixture so installed-runtime suites
  # can still exercise the public project layout.
  $sourceTestsRoot = Join-Path $repoRoot "payload\Scripts\Tests"
  $fixtureTestsRoot = Join-Path $fixtureRepo "Scripts\Tests"
  New-Item -ItemType Directory -Path $fixtureTestsRoot -Force | Out-Null
  foreach ($sourceFile in @(Get-ChildItem -LiteralPath $sourceTestsRoot -File -Recurse)) {
    $relativeTestPath = [System.IO.Path]::GetRelativePath($sourceTestsRoot, $sourceFile.FullName)
    $pathSegments = @($relativeTestPath -split '[\\/]')
    if (@($pathSegments | Where-Object { $_ -like "*Results" }).Count -gt 0) {
      continue
    }

    $fixtureTestPath = Join-Path $fixtureTestsRoot $relativeTestPath
    $fixtureTestParent = Split-Path -Path $fixtureTestPath -Parent
    New-Item -ItemType Directory -Path $fixtureTestParent -Force | Out-Null
    Copy-Item -LiteralPath $sourceFile.FullName -Destination $fixtureTestPath -Force
  }

  & git -C $fixtureRepo add -A | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Failed to stage installed fixture: $fixtureRepo" }
  & git -C $fixtureRepo commit -m "test: installed UE tool suite fixture" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Failed to commit installed fixture: $fixtureRepo" }

  [pscustomobject]@{
    RepoRoot = $fixtureRepo
    ScratchRoot = $scratchRoot
  }
}

function Test-NameMatch {
  param(
    [Parameter(Mandatory)]$Entry,
    [Parameter(Mandatory)][string[]]$Patterns
  )

  $leaf = Split-Path $Entry.Path -Leaf
  foreach ($pattern in $Patterns) {
    if ($Entry.Id -like $pattern) { return $true }
    if ($Entry.Name -like $pattern) { return $true }
    if ($leaf -like $pattern) { return $true }
  }

  return $false
}

function Test-CategoryMatch {
  param(
    [Parameter(Mandatory)]$Entry,
    [Parameter(Mandatory)][string[]]$Patterns
  )

  foreach ($pattern in $Patterns) {
    if ($Entry.Category -like $pattern) { return $true }
  }

  return $false
}

function Resolve-TestSelection {
  param([Parameter(Mandatory)][object[]]$Manifest)

  $explicitSelection = ((@($Name | Where-Object { $_ }).Count -gt 0) -or (@($Category | Where-Object { $_ }).Count -gt 0))
  $selected = @($Manifest)

  if (-not $explicitSelection) {
    $selected = @($selected | Where-Object { $_.DefaultEnabled })
  }

  if ($Name) {
    $selected = @($selected | Where-Object { Test-NameMatch -Entry $_ -Patterns $Name })
  }

  if ($Category) {
    $selected = @($selected | Where-Object { Test-CategoryMatch -Entry $_ -Patterns $Category })
  }

  if (-not $IncludeExclusive) {
    $selected = @($selected | Where-Object { -not $_.ExclusiveRepoAccess })
  }

  return @($selected)
}

function Get-ResultDirectorySnapshot {
  param([string]$ResultDirectory)

  if ([string]::IsNullOrWhiteSpace($ResultDirectory)) { return @() }
  if (-not (Test-Path -LiteralPath $ResultDirectory)) { return @() }

  return @(
    Get-ChildItem -Path $ResultDirectory -File -Recurse -ErrorAction SilentlyContinue |
      Select-Object -ExpandProperty FullName
  )
}

function Resolve-TestArtifactPath {
  param(
    [string]$ResultDirectory,
    [string[]]$BeforeFiles
  )

  if ([string]::IsNullOrWhiteSpace($ResultDirectory)) { return $null }
  if (-not (Test-Path -LiteralPath $ResultDirectory)) { return $null }

  $afterFiles = @(Get-ChildItem -Path $ResultDirectory -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
  if ($afterFiles.Count -eq 0) { return $null }

  $newFiles = @($afterFiles | Where-Object { $_.FullName -notin $BeforeFiles })
  if ($newFiles.Count -gt 0) { return $newFiles[0].FullName }
  return $afterFiles[0].FullName
}

function Invoke-TestEntry {
  param([Parameter(Mandatory)]$Entry)

  $fixture = $null
  $executionRoot = $repoRoot

  if ($Entry.RequiresInstalledFixture) {
    $fixture = New-InstalledToolSuiteFixture -Entry $Entry
    $executionRoot = $fixture.RepoRoot
  }

  $repoState = Get-RepoState -Root $executionRoot
  $skipReason = $null

  if ($Entry.RequiresCommits -and -not $repoState.HasCommits) {
    $skipReason = "requires at least one commit"
  }
  elseif ($Entry.RequiresCleanRepo -and -not $repoState.IsClean) {
    $skipReason = "requires a clean repo"
  }

  if ($skipReason) {
    Write-SuiteLog "[SKIP] $($Entry.Name) - $skipReason" DarkYellow
    return [pscustomobject]@{
      Id = $Entry.Id; Name = $Entry.Name; Category = $Entry.Category; Status = "SKIP"
      ExitCode = $null; DurationSec = 0; Path = $Entry.Path; Artifact = $null; Detail = $skipReason
    }
  }

  $scriptRoot = if ($Entry.ScriptInInstallerRoot) { $repoRoot } else { $executionRoot }
  $scriptPath = Join-Path $scriptRoot $Entry.Path
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    Write-SuiteLog "[FAIL] $($Entry.Name) - script not found: $scriptPath" Red
    return [pscustomobject]@{
      Id = $Entry.Id; Name = $Entry.Name; Category = $Entry.Category; Status = "FAIL"
      ExitCode = -1; DurationSec = 0; Path = $Entry.Path; Artifact = $null; Detail = "script not found"
    }
  }

  $resultDirectory = if ([string]::IsNullOrWhiteSpace($Entry.ResultDirectory)) { $null } else { Join-Path $executionRoot $Entry.ResultDirectory }
  $beforeFiles = Get-ResultDirectorySnapshot -ResultDirectory $resultDirectory
  $args = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath)
  if ($NoCleanup -and $Entry.SupportsNoCleanup) { $args += "-NoCleanup" }
  if ($FailFast -and $Entry.SupportsFailFast) { $args += "-FailFast" }

  Write-SuiteLog ""
  Write-SuiteLog "============================================================" DarkGray
  Write-SuiteLog "Running: $($Entry.Name)" DarkGray
  Write-SuiteLog "============================================================" DarkGray
  Write-SuiteLog "Script : $($Entry.Path)" Cyan
  Write-SuiteLog "Root   : $executionRoot" Cyan
  Write-SuiteLog "Args   : pwsh $($args -join ' ')" Cyan
  Write-SuiteLog "Branch : $($repoState.Branch)" Cyan

  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  Push-Location $executionRoot
  try {
    & pwsh @args 2>&1 | ForEach-Object {
      Write-ChildOutputLine -Text "$_"
    }
    $exitCode = $LASTEXITCODE
  }
  finally {
    Pop-Location
    $stopwatch.Stop()
  }

  $artifact = Resolve-TestArtifactPath -ResultDirectory $resultDirectory -BeforeFiles $beforeFiles
  $status = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }
  $color = if ($status -eq "PASS") { [ConsoleColor]::Green } else { [ConsoleColor]::Red }
  $detail = "exit=$exitCode duration={0:N1}s" -f $stopwatch.Elapsed.TotalSeconds
  if ($artifact) { $detail = "$detail artifact=$artifact" }
  Write-SuiteLog "[$status] $($Entry.Name) - $detail" $color

  if ($fixture -and $status -eq "PASS" -and -not $NoCleanup -and (Test-Path -LiteralPath $fixture.ScratchRoot)) {
    Remove-Item -LiteralPath $fixture.ScratchRoot -Recurse -Force -ErrorAction SilentlyContinue
  }

  return [pscustomobject]@{
    Id = $Entry.Id; Name = $Entry.Name; Category = $Entry.Category; Status = $status
    ExitCode = $exitCode; DurationSec = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
    Path = $Entry.Path; Artifact = $artifact; Detail = $detail
  }
}

$manifest = @(Get-UEToolSuiteTestManifest)
$selectedTests = @(Resolve-TestSelection -Manifest $manifest)

if ($List) {
  foreach ($test in $selectedTests) {
    $flags = New-Object System.Collections.Generic.List[string]
    if ($test.DefaultEnabled) { $flags.Add("default") | Out-Null }
    if ($test.RequiresCleanRepo) { $flags.Add("clean-repo") | Out-Null }
    if ($test.RequiresCommits) { $flags.Add("commits") | Out-Null }
    if ($test.MutatesRepo) { $flags.Add("mutates-repo") | Out-Null }
    if ($test.ExclusiveRepoAccess) { $flags.Add("exclusive-repo") | Out-Null }

    Write-Host "- [$($test.Id)] $($test.Name) ($($test.Category))"
    Write-Host ("  script: {0}" -f $test.Path)
    Write-Host ("  flags : {0}" -f ($(if ($flags.Count -gt 0) { $flags -join ", " } else { "none" })))
  }
  exit 0
}

if ($selectedTests.Count -lt 1) {
  throw "No tests matched the current selection."
}

$initialRepoState = Get-RepoState
Write-SuiteLog "============================================================" DarkGray
Write-SuiteLog "UE Tool Suite Test Runner ($stamp)" DarkGray
Write-SuiteLog "============================================================" DarkGray
Write-SuiteLog "Repo   : $repoRoot" Cyan
Write-SuiteLog "Log    : $logPath" Cyan
if ($WriteJson) { Write-SuiteLog "JSON   : $jsonPath" Cyan }
Write-SuiteLog "Branch : $($initialRepoState.Branch)" Cyan
Write-SuiteLog "Clean  : $($initialRepoState.IsClean)" Cyan
Write-SuiteLog "Commits: $($initialRepoState.HasCommits)" Cyan
Write-SuiteLog "Count  : $($selectedTests.Count)" Cyan

$results = New-Object System.Collections.Generic.List[object]
foreach ($entry in $selectedTests) {
  $result = Invoke-TestEntry -Entry $entry
  $results.Add($result) | Out-Null

  if ($FailFast -and $result.Status -eq "FAIL") {
    Write-SuiteLog "Stopping after first failure because -FailFast was requested." Yellow
    break
  }
}

$resultArray = $results.ToArray()
if ($WriteJson) {
  [pscustomobject]@{
    RepoRoot = $repoRoot
    Stamp = $stamp
    Results = $resultArray
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
}

$passCount = (@($resultArray | Where-Object { $_.Status -eq "PASS" })).Count
$failCount = (@($resultArray | Where-Object { $_.Status -eq "FAIL" })).Count
$skipCount = (@($resultArray | Where-Object { $_.Status -eq "SKIP" })).Count

Write-SuiteLog ""
Write-SuiteLog "============================================================" DarkGray
Write-SuiteLog "Summary" DarkGray
Write-SuiteLog "============================================================" DarkGray
Write-SuiteLog ("PASS={0} FAIL={1} SKIP={2}" -f $passCount, $failCount, $skipCount) Cyan

foreach ($result in $resultArray) {
  $color = switch ($result.Status) {
    "PASS" { [ConsoleColor]::Green; break }
    "FAIL" { [ConsoleColor]::Red; break }
    default { [ConsoleColor]::DarkYellow }
  }
  Write-SuiteLog ("[{0}] {1} ({2})" -f $result.Status, $result.Name, $result.Category) $color
  Write-SuiteLog ("       detail: {0}" -f $result.Detail) DarkGray
}

Write-SuiteLog ""
Write-SuiteLog "Suite log saved: $logPath" Cyan
if ($WriteJson) { Write-SuiteLog "Suite JSON saved: $jsonPath" Cyan }
if ($PassThru) { $results }
if ($failCount -gt 0) { exit 1 }
exit 0
