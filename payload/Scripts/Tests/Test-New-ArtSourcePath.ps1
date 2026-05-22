[CmdletBinding()]
param(
  [switch]$NoCleanup
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = (git rev-parse --show-toplevel 2>$null | Select-Object -First 1).Trim()
if (-not $repoRoot) { throw "Not inside a git repository." }
Set-Location $repoRoot

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$resultsDir = Join-Path $repoRoot "Scripts\Tests\Test-New-ArtSourcePathResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "New-ArtSourcePathTest-$stamp.log"
$testHarnessPath = Join-Path $repoRoot "Scripts\Tests\TestHarness.ps1"
if (-not (Test-Path -LiteralPath $testHarnessPath -PathType Leaf)) {
  throw "Test harness not found: $testHarnessPath"
}
. $testHarnessPath

$script:PassCount = 0
$script:FailCount = 0
Initialize-TestHarness -LogPath $logPath

function New-TemplateSkeleton {
  param(
    [Parameter(Mandatory)][string]$TemplatePath
  )

  foreach ($name in @("Source", "Textures", "Exports")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $TemplatePath $name) | Out-Null
  }
}

$tempRoot = Join-Path $resultsDir ("Temp-" + [Guid]::NewGuid().ToString("N"))

try {
  Step "Setup Test Data"

  $artSourceRoot = Join-Path $tempRoot "ArtSource"
  New-Item -ItemType Directory -Force -Path $artSourceRoot | Out-Null

  foreach ($domain in @("Characters", "Props", "Shared")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $artSourceRoot $domain) | Out-Null
  }

  $charactersTemplate = Join-Path $artSourceRoot "Characters\_Template"
  $propsTemplate = Join-Path $artSourceRoot "Props\_Template"
  $sharedTemplate = Join-Path $artSourceRoot "Shared\_Template"

  New-TemplateSkeleton -TemplatePath $charactersTemplate
  New-TemplateSkeleton -TemplatePath $propsTemplate
  New-TemplateSkeleton -TemplatePath $sharedTemplate

  Set-Content -LiteralPath (Join-Path $charactersTemplate "Exports\CharacterTemplate.txt") -Value "character template marker" -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $sharedTemplate "Exports\SharedTemplate.txt") -Value "shared template marker" -Encoding UTF8

  $artModulePath = Join-Path $repoRoot "Scripts\UETools\UEToolSuite.Art.psm1"
  Assert-Condition -Name "art domain module exists" -Condition (Test-Path -LiteralPath $artModulePath -PathType Leaf) -FailDetail "missing: $artModulePath"
  Import-Module -Name $artModulePath -Force -DisableNameChecking

  Step "Canonical Template Consolidation"

  $canonicalTemplate = Ensure-UEToolSuiteArtCanonicalTemplate -ArtSourceRoot $artSourceRoot
  $canonicalTemplate = [System.IO.Path]::GetFullPath($canonicalTemplate)

  Assert-Condition -Name "Canonical template exists" -Condition (Test-Path -LiteralPath $canonicalTemplate) -FailDetail "ArtSource/_Template was not created"
  Assert-Condition -Name "Characters duplicate template removed" -Condition (-not (Test-Path -LiteralPath $charactersTemplate)) -FailDetail "Characters/_Template still exists"
  Assert-Condition -Name "Props duplicate template removed" -Condition (-not (Test-Path -LiteralPath $propsTemplate)) -FailDetail "Props/_Template still exists"
  Assert-Condition -Name "Shared duplicate template removed" -Condition (-not (Test-Path -LiteralPath $sharedTemplate)) -FailDetail "Shared/_Template still exists"

  foreach ($required in @("Source", "Textures", "Exports")) {
    $requiredPath = Join-Path $canonicalTemplate $required
    Assert-Condition -Name "Canonical includes $required" -Condition (Test-Path -LiteralPath $requiredPath) -FailDetail "Missing $required under ArtSource/_Template"
  }

  Assert-Condition -Name "Merged character template file present" -Condition (Test-Path -LiteralPath (Join-Path $canonicalTemplate "Exports\CharacterTemplate.txt")) -FailDetail "Character template marker missing from canonical template"
  Assert-Condition -Name "Merged shared template file present" -Condition (Test-Path -LiteralPath (Join-Path $canonicalTemplate "Exports\SharedTemplate.txt")) -FailDetail "Shared template marker missing from canonical template"

  Step "Create Art Item From Canonical Template"

  $toolsContainer = New-UEToolSuiteArtDirectoryChecked -ParentPath (Join-Path $artSourceRoot "Props") -Name "Tools"
  $newArtItemPath = Join-Path $toolsContainer "Hammer_A"
  [void](New-UEToolSuiteArtItemFromTemplate -TemplatePath $canonicalTemplate -DestinationPath $newArtItemPath)

  Assert-Condition -Name "Art item folder created" -Condition (Test-Path -LiteralPath $newArtItemPath) -FailDetail "Art item directory was not created"

  foreach ($required in @("Source", "Textures", "Exports")) {
    $requiredPath = Join-Path $newArtItemPath $required
    Assert-Condition -Name "Art item includes $required" -Condition (Test-Path -LiteralPath $requiredPath) -FailDetail "Missing $required in new art item"
  }

  Assert-Condition -Name "Art item copied merged file" -Condition (Test-Path -LiteralPath (Join-Path $newArtItemPath "Exports\SharedTemplate.txt")) -FailDetail "Merged template file did not copy into new art item"

  Step "Navigable Child Folder Filtering"

  $swordContainer = New-UEToolSuiteArtDirectoryChecked -ParentPath $toolsContainer -Name "Sword"
  New-Item -ItemType Directory -Force -Path (Join-Path $swordContainer "Source") | Out-Null
  $materialsContainer = New-UEToolSuiteArtDirectoryChecked -ParentPath $toolsContainer -Name "Materials"

  Assert-Condition -Name "Hammer_A detected as art item" -Condition (Test-UEToolSuiteArtItemDirectory -Path $newArtItemPath) -FailDetail "Hammer_A should be recognized as an art item"
  Assert-Condition -Name "Sword detected as container" -Condition (-not (Test-UEToolSuiteArtItemDirectory -Path $swordContainer)) -FailDetail "Sword should remain a container because it is missing required art-item folders"
  Assert-Condition -Name "Materials detected as container" -Condition (-not (Test-UEToolSuiteArtItemDirectory -Path $materialsContainer)) -FailDetail "Materials should be treated as a container"

  $navigableNames = @(
    Get-UEToolSuiteArtNavigableChildDirectories -ParentPath $toolsContainer |
    Select-Object -ExpandProperty Name
  )

  Assert-Condition -Name "Navigable list includes Sword" -Condition ($navigableNames -contains "Sword") -FailDetail "Sword should be listed as a navigable child folder"
  Assert-Condition -Name "Navigable list includes Materials" -Condition ($navigableNames -contains "Materials") -FailDetail "Materials should be listed as a navigable child folder"
  Assert-Condition -Name "Navigable list excludes Hammer_A art item" -Condition (-not ($navigableNames -contains "Hammer_A")) -FailDetail "Hammer_A art item should not be listed as a navigable child folder"

  Step "Summary"
  Write-Log ("PASS={0} FAIL={1}" -f $script:PassCount, $script:FailCount) Cyan
  if ($script:FailCount -eq 0) {
    Write-Log "New-ArtSourcePath tests passed." Green
  }
  else {
    Write-Log "New-ArtSourcePath tests failed." Red
    exit 1
  }
}
catch {
  Write-Log "[FATAL] $($_.Exception.Message)" Red
  if ($script:FailCount -eq 0) { $script:FailCount = 1 }
  Write-Log ("PASS={0} FAIL={1}" -f $script:PassCount, $script:FailCount) Cyan
  exit 1
}
finally {
  if (-not $NoCleanup -and (Test-Path -LiteralPath $tempRoot)) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }

  Write-Log ""
  Write-Log "Log saved: $logPath" Cyan
}
