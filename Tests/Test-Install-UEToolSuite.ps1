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
$testHarnessPath = Join-Path $installerRoot "payload\Scripts\Tests\TestHarness.ps1"
if (-not (Test-Path -LiteralPath $testHarnessPath -PathType Leaf)) {
  throw "Test harness not found: $testHarnessPath"
}
. $testHarnessPath

$script:PassCount = 0
$script:FailCount = 0
Initialize-TestHarness -LogPath $logPath -FailFast:$FailFast

function Assert-PathExists([string]$Name, [string]$Path) {
  Assert-Condition $Name (Test-Path -LiteralPath $Path) "present" "missing: $Path"
}

function Assert-PathMissing([string]$Name, [string]$Path) {
  Assert-Condition $Name (-not (Test-Path -LiteralPath $Path)) "absent" "unexpected path: $Path"
}

function Assert-FileContains([string]$Name, [string]$Path, [string]$ExpectedText) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Fail $Name "missing: $Path"
    return
  }

  $content = Get-Content -LiteralPath $Path -Raw
  Assert-Condition $Name ($content.Contains($ExpectedText)) "found expected text" "expected text missing from $Path"
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
      ".gitattributes",
      ".gitignore",
      ".githooks\post-checkout",
      "Scripts\Init-Repo.ps1",
      "Scripts\ue-tools.ps1",
      "Scripts\UETools\UEToolSuite.Core.psm1",
      "Scripts\UETools\ue-tools.ps1",
      "Scripts\Unreal\UnrealSync.ps1",
      "Scripts\Docs\DocsTools.ps1",
      "Docs\Setup.md",
      "Docs\Pipeline\README.md",
      "Docs\DocsSite\Docusaurus-Setup.md",
      "website\package.json",
      "website\docusaurus.config.ts",
      "website\.gitignore",
      "website\static\.nojekyll"
    )) {
    Assert-PathExists "case1 installed $relativePath" (Join-Path $targetRepo $relativePath)
  }
  Assert-FileContains "case1 installed git attributes marker" (Join-Path $targetRepo ".gitattributes") "# >>> ue tool suite git attributes >>>"
  Assert-FileContains "case1 installed git ignore marker" (Join-Path $targetRepo ".gitignore") "# >>> ue tool suite git ignore >>>"
  Assert-FileContains "case1 installed binary guard uasset rule" (Join-Path $targetRepo ".gitattributes") "*.uasset filter=lfs diff=lfs merge=binary -text"

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
  $gitIgnorePath = Join-Path $targetRepo ".gitignore"
  $existingGitIgnore = Get-Content -LiteralPath $gitIgnorePath -Raw
  Write-Utf8NoBomFile -Path $gitIgnorePath -Content ("local-custom-ignore/`n`n" + $existingGitIgnore)
  Write-Utf8NoBomFile -Path (Join-Path $targetRepo "Docs\Pipeline\README.md") -Content "stale project pipeline readme`n"
  Remove-Item -LiteralPath (Join-Path $targetRepo "website\src\css") -Recurse -Force
  Write-Utf8NoBomFile -Path (Join-Path $targetRepo "website\src\css") -Content "stale file blocking managed directory`n"
  $projectSpecificFiles = @(
    [pscustomobject]@{ RelativePath = "Docs\Codex\Project-Context.md"; Content = "project-specific codex context should survive`n" },
    [pscustomobject]@{ RelativePath = "Docs\Pipeline\Project-Pipeline-Notes.md"; Content = "project-specific pipeline notes should survive`n" },
    [pscustomobject]@{ RelativePath = "Docs\DocsSite\Local-DocsSite-Notes.md"; Content = "project-specific docs site notes should survive`n" },
    [pscustomobject]@{ RelativePath = "website\src\pages\local-project-page.tsx"; Content = "project-specific docs page should survive`n" }
  )
  foreach ($projectSpecificFile in $projectSpecificFiles) {
    Write-Utf8NoBomFile -Path (Join-Path $targetRepo $projectSpecificFile.RelativePath) -Content $projectSpecificFile.Content
  }
  $updateResult = Invoke-Installer -TargetRoot $targetRepo -ExtraArgs @("-SkipTests")
  Assert-Condition "case2 update exits cleanly" ($updateResult.Code -eq 0) "exit=0" "exit=$($updateResult.Code)"
  Assert-PathMissing "case2 legacy installer removed" (Join-Path $targetRepo "Scripts\Install-UEProjectTools.ps1")
  $backupMatches = @(Get-ChildItem -LiteralPath (Join-Path $targetRepo ".ue-tools-installer-backups") -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "UnrealSync.ps1" })
  Assert-Condition "case2 backup created for replaced tool" ($backupMatches.Count -gt 0) "backup count=$($backupMatches.Count)" "backup missing"
  Assert-FileContains "case2 git ignore preserves local lines" $gitIgnorePath "local-custom-ignore/"
  $gitIgnoreBackupMatches = @(Get-ChildItem -LiteralPath (Join-Path $targetRepo ".ue-tools-installer-backups") -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq ".gitignore" })
  Assert-Condition "case2 backup created for managed git ignore" ($gitIgnoreBackupMatches.Count -gt 0) "backup count=$($gitIgnoreBackupMatches.Count)" "backup missing"
  foreach ($projectSpecificFile in $projectSpecificFiles) {
    Assert-FileContains "case2 preserved target-only $($projectSpecificFile.RelativePath)" (Join-Path $targetRepo $projectSpecificFile.RelativePath) $projectSpecificFile.Content.Trim()
  }
  Assert-Condition "case2 replaced file conflict with managed directory" (Test-Path -LiteralPath (Join-Path $targetRepo "website\src\css") -PathType Container) "directory restored" "directory not restored"
  Assert-PathExists "case2 restored payload file under conflict directory" (Join-Path $targetRepo "website\src\css\custom.css")
  Assert-FileContains "case2 refreshed managed docs file inside existing directory" (Join-Path $targetRepo "Docs\Pipeline\README.md") "# Daily Workflow"
  $pipelineReadmeBackupMatches = @(Get-ChildItem -LiteralPath (Join-Path $targetRepo ".ue-tools-installer-backups") -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like "*Docs*Pipeline*README.md" })
  Assert-Condition "case2 backup created for managed file inside existing directory" ($pipelineReadmeBackupMatches.Count -gt 0) "backup count=$($pipelineReadmeBackupMatches.Count)" "backup missing"

  Step "Case 2b: update merges managed test directory without removing target-only files"
  $managedDirectoryRepo = New-TargetRepo "managed directory merge target"
  $managedDirectoryInstallResult = Invoke-Installer -TargetRoot $managedDirectoryRepo -ExtraArgs @()
  Assert-Condition "case2b initial install exits cleanly" ($managedDirectoryInstallResult.Code -eq 0) "exit=0" "exit=$($managedDirectoryInstallResult.Code)"
  Write-Utf8NoBomFile -Path (Join-Path $managedDirectoryRepo "Scripts\Tests\ProjectSpecific-Test.ps1") -Content "project-specific test should survive`n"
  Write-Utf8NoBomFile -Path (Join-Path $managedDirectoryRepo "Scripts\Tests\TestManifest.ps1") -Content "stale test manifest`n"
  $managedDirectoryUpdateResult = Invoke-Installer -TargetRoot $managedDirectoryRepo -ExtraArgs @()
  Assert-Condition "case2b update exits cleanly" ($managedDirectoryUpdateResult.Code -eq 0) "exit=0" "exit=$($managedDirectoryUpdateResult.Code)"
  Assert-FileContains "case2b preserved target-only test file" (Join-Path $managedDirectoryRepo "Scripts\Tests\ProjectSpecific-Test.ps1") "project-specific test should survive"
  Assert-FileContains "case2b refreshed managed test file" (Join-Path $managedDirectoryRepo "Scripts\Tests\TestManifest.ps1") "function Get-ProjectTestManifest"
  $testManifestBackupMatches = @(Get-ChildItem -LiteralPath (Join-Path $managedDirectoryRepo ".ue-tools-installer-backups") -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like "*Scripts*Tests*TestManifest.ps1" })
  Assert-Condition "case2b backup created for managed test file" ($testManifestBackupMatches.Count -gt 0) "backup count=$($testManifestBackupMatches.Count)" "backup missing"

  Step "Case 3: installer can run target Init-Repo"
  $initRepo = New-TargetRepo "run init target"
  & git -C $initRepo remote add origin "git@github.com:AcmeTools/PortableSample.git" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "git remote add failed for target repo: $initRepo" }
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
  Assert-FileContains "case3 docusaurus organization metadata set" (Join-Path $initRepo "website\docusaurus.config.ts") "organizationName: 'AcmeTools'"
  Assert-FileContains "case3 docusaurus project metadata set" (Join-Path $initRepo "website\docusaurus.config.ts") "projectName: 'PortableSample'"

  Step "Case 4: SkipDocs omits Docs payload without omitting website payload"
  $skipDocsRepo = New-TargetRepo "skip docs target"
  $skipDocsResult = Invoke-Installer -TargetRoot $skipDocsRepo -ExtraArgs @("-SkipTests", "-SkipDocs")
  Assert-Condition "case4 skip docs exits cleanly" ($skipDocsResult.Code -eq 0) "exit=0" "exit=$($skipDocsResult.Code)"
  Assert-PathMissing "case4 Docs README skipped" (Join-Path $skipDocsRepo "Docs\README.md")
  Assert-PathExists "case4 website retained" (Join-Path $skipDocsRepo "website\package.json")

  Step "Case 5: SkipWebsite omits website payload while keeping docs tooling"
  $skipWebsiteRepo = New-TargetRepo "skip website target"
  $skipWebsiteResult = Invoke-Installer -TargetRoot $skipWebsiteRepo -ExtraArgs @("-SkipTests", "-SkipWebsite")
  Assert-Condition "case5 skip website exits cleanly" ($skipWebsiteResult.Code -eq 0) "exit=0" "exit=$($skipWebsiteResult.Code)"
  Assert-PathMissing "case5 website skipped" (Join-Path $skipWebsiteRepo "website\package.json")
  Assert-PathExists "case5 docs tooling retained" (Join-Path $skipWebsiteRepo "Scripts\Docs\DocsTools.ps1")
  Assert-PathExists "case5 docs retained" (Join-Path $skipWebsiteRepo "Docs\README.md")

  Step "Case 6: NoBackup replaces managed paths without writing backup output"
  $noBackupRepo = New-TargetRepo "no backup target"
  Write-Utf8NoBomFile -Path (Join-Path $noBackupRepo ".gitattributes") -Content "custom attributes`n"
  Write-Utf8NoBomFile -Path (Join-Path $noBackupRepo "Scripts\Unreal\UnrealSync.ps1") -Content "legacy sync`n"
  $noBackupResult = Invoke-Installer -TargetRoot $noBackupRepo -ExtraArgs @("-SkipTests", "-NoBackup")
  Assert-Condition "case6 no backup exits cleanly" ($noBackupResult.Code -eq 0) "exit=0" "exit=$($noBackupResult.Code)"
  Assert-PathMissing "case6 backup root not created" (Join-Path $noBackupRepo ".ue-tools-installer-backups")
  Assert-FileContains "case6 git attributes preserves local lines" (Join-Path $noBackupRepo ".gitattributes") "custom attributes"

  Step "Case 7: NoLegacyCleanup preserves old in-project installer path"
  $noLegacyCleanupRepo = New-TargetRepo "no legacy cleanup target"
  Write-Utf8NoBomFile -Path (Join-Path $noLegacyCleanupRepo "Scripts\Install-UEProjectTools.ps1") -Content "legacy installer`n"
  $noLegacyCleanupResult = Invoke-Installer -TargetRoot $noLegacyCleanupRepo -ExtraArgs @("-SkipTests", "-NoLegacyCleanup")
  Assert-Condition "case7 no legacy cleanup exits cleanly" ($noLegacyCleanupResult.Code -eq 0) "exit=0" "exit=$($noLegacyCleanupResult.Code)"
  Assert-PathExists "case7 legacy installer preserved" (Join-Path $noLegacyCleanupRepo "Scripts\Install-UEProjectTools.ps1")

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
