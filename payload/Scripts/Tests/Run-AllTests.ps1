[CmdletBinding()]
param(
  [string[]]$Name,
  [string[]]$Category,
  [switch]$List,
  [switch]$WriteJson,
  [switch]$NoCleanup,
  [switch]$FailFast,
  [switch]$PassThru
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = ((git rev-parse --show-toplevel 2>$null) | Select-Object -First 1).Trim()
if (-not $repoRoot) { throw "Not inside a git repository." }
Set-Location $repoRoot

$manifestScript = Join-Path $repoRoot "Scripts\Tests\TestManifest.ps1"
if (-not (Test-Path -LiteralPath $manifestScript)) {
  throw "Test manifest not found: $manifestScript"
}
. $manifestScript

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$resultsDir = Join-Path $repoRoot "Scripts\Tests\Run-AllTestsResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "Run-AllTests-$stamp.log"
$jsonPath = if ($WriteJson) {
  Join-Path $resultsDir "Run-AllTests-$stamp.json"
}
else {
  $null
}

function Write-SuiteLog {
  param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
    [ConsoleColor]$Color = [ConsoleColor]::Gray
  )

  Write-Host $Message -ForegroundColor $Color
  Add-Content -LiteralPath $logPath -Value $Message -Encoding UTF8
}

function Remove-AnsiEscapeSequences([string]$Text) {
  if ($null -eq $Text) { return "" }
  return ([regex]::Replace($Text, "`e\[[0-9;?]*[ -/]*[@-~]", ""))
}

function Test-TextHasAnsiEscape([string]$Text) {
  if ([string]::IsNullOrEmpty($Text)) { return $false }
  return ($Text -match "`e\[[0-9;?]*[ -/]*[@-~]")
}

function Write-ChildOutputLine([string]$Text) {
  $plainText = Remove-AnsiEscapeSequences $Text

  if (Test-TextHasAnsiEscape $Text) {
    Write-Host $Text
    Add-Content -LiteralPath $logPath -Value $plainText -Encoding UTF8
    return
  }

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
  $head = ((git rev-parse --verify HEAD 2>$null) | Select-Object -First 1).Trim()
  $branch = ((git rev-parse --abbrev-ref HEAD 2>$null) | Select-Object -First 1).Trim()
  $dirtyLines = @((git status --porcelain 2>$null) | Where-Object { $_ -and $_.Trim() -ne "" })

  [pscustomobject]@{
    HasCommits    = -not [string]::IsNullOrWhiteSpace($head)
    IsClean       = ($dirtyLines.Count -eq 0)
    Branch        = $branch
    DirtyFileCount = $dirtyLines.Count
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

  return @($selected)
}

function Resolve-TestArtifactPath {
  param(
    [string]$ResultDirectory,
    [string[]]$BeforeFiles
  )

  if ([string]::IsNullOrWhiteSpace($ResultDirectory)) {
    return $null
  }

  if (-not (Test-Path -LiteralPath $ResultDirectory)) {
    return $null
  }

  $afterFiles = @(Get-ChildItem -Path $ResultDirectory -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
  if ($afterFiles.Count -eq 0) {
    return $null
  }

  $newFiles = @($afterFiles | Where-Object { $_.FullName -notin $BeforeFiles })
  if ($newFiles.Count -gt 0) {
    return $newFiles[0].FullName
  }

  return $afterFiles[0].FullName
}

function Get-ResultDirectorySnapshot([string]$ResultDirectory) {
  if ([string]::IsNullOrWhiteSpace($ResultDirectory)) { return @() }
  if (-not (Test-Path -LiteralPath $ResultDirectory)) { return @() }

  @(Get-ChildItem -Path $ResultDirectory -File -Recurse -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName)
}

function Invoke-TestEntry {
  param([Parameter(Mandatory)]$Entry)

  $repoState = Get-RepoState
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
      Id          = $Entry.Id
      Name        = $Entry.Name
      Category    = $Entry.Category
      Status      = "SKIP"
      ExitCode    = $null
      DurationSec = 0
      Path        = $Entry.Path
      Artifact    = $null
      Detail      = $skipReason
    }
  }

  $scriptPath = Join-Path $repoRoot $Entry.Path
  if (-not (Test-Path -LiteralPath $scriptPath)) {
    Write-SuiteLog "[FAIL] $($Entry.Name) - script not found: $scriptPath" Red
    return [pscustomobject]@{
      Id          = $Entry.Id
      Name        = $Entry.Name
      Category    = $Entry.Category
      Status      = "FAIL"
      ExitCode    = -1
      DurationSec = 0
      Path        = $Entry.Path
      Artifact    = $null
      Detail      = "script not found"
    }
  }

  $resultDirectory = if ([string]::IsNullOrWhiteSpace($Entry.ResultDirectory)) {
    $null
  }
  else {
    Join-Path $repoRoot $Entry.ResultDirectory
  }
  $beforeFiles = Get-ResultDirectorySnapshot $resultDirectory

  $args = @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath
  )

  if ($NoCleanup -and $Entry.SupportsNoCleanup) {
    $args += "-NoCleanup"
  }
  if ($FailFast -and $Entry.SupportsFailFast) {
    $args += "-FailFast"
  }

  Write-SuiteLog ""
  Write-SuiteLog "============================================================" DarkGray
  Write-SuiteLog "Running: $($Entry.Name)" DarkGray
  Write-SuiteLog "============================================================" DarkGray
  Write-SuiteLog "Script : $($Entry.Path)" Cyan
  Write-SuiteLog "Args   : pwsh $($args -join ' ')" Cyan
  Write-SuiteLog "Branch : $($repoState.Branch)" Cyan

  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $capturedLines = New-Object System.Collections.Generic.List[string]
  Push-Location $repoRoot
  try {
    & pwsh @args 2>&1 | ForEach-Object {
      $text = "$_"
      $capturedLines.Add($text) | Out-Null
      Write-ChildOutputLine $text
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
  if ($artifact) {
    $detail = "$detail artifact=$artifact"
  }

  Write-SuiteLog "[$status] $($Entry.Name) - $detail" $color

  [pscustomobject]@{
    Id          = $Entry.Id
    Name        = $Entry.Name
    Category    = $Entry.Category
    Status      = $status
    ExitCode    = $exitCode
    DurationSec = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
    Path        = $Entry.Path
    Artifact    = $artifact
    Detail      = $detail
  }
}

$manifest = @(Get-ProjectTestManifest)
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
    Write-Host ("  script: {0}" -f (Split-Path $test.Path -Leaf))
    Write-Host ("  flags : {0}" -f ($(if ($flags.Count -gt 0) { $flags -join ", " } else { "none" })))
  }
  exit 0
}

if ($selectedTests.Count -lt 1) {
  throw "No tests matched the current selection."
}

$initialRepoState = Get-RepoState
Write-SuiteLog "============================================================" DarkGray
Write-SuiteLog "Project Test Runner ($stamp)" DarkGray
Write-SuiteLog "============================================================" DarkGray
Write-SuiteLog "Repo   : $repoRoot" Cyan
Write-SuiteLog "Log    : $logPath" Cyan
if ($WriteJson) {
  Write-SuiteLog "JSON   : $jsonPath" Cyan
}
Write-SuiteLog "Branch : $($initialRepoState.Branch)" Cyan
Write-SuiteLog "Clean  : $($initialRepoState.IsClean)" Cyan
Write-SuiteLog "Commits: $($initialRepoState.HasCommits)" Cyan
Write-SuiteLog "Count  : $($selectedTests.Count)" Cyan
Write-SuiteLog "Mode   : serial" Cyan

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

$summary = [pscustomobject]@{
  RepoRoot = $repoRoot
  Stamp    = $stamp
  Results  = $resultArray
}
if ($WriteJson) {
  $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
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
  if ($result.Artifact) {
    Write-SuiteLog ("       artifact: {0}" -f $result.Artifact) DarkGray
  }
  Write-SuiteLog ("       detail  : {0}" -f $result.Detail) DarkGray
}

Write-SuiteLog ""
Write-SuiteLog "Suite log saved: $logPath" Cyan
if ($WriteJson) {
  Write-SuiteLog "Suite JSON saved: $jsonPath" Cyan
}

if ($PassThru) {
  $results
}

if ($failCount -gt 0) {
  exit 1
}

exit 0
