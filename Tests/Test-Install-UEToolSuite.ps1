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

function Get-LineMatchCount([string]$Text, [string]$Line) {
  return ([regex]::Matches($Text, "(?m)^" + [regex]::Escape($Line) + "$")).Count
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

function Write-TestPngFile {
  param([Parameter(Mandatory)][string]$Path)

  $pngBytes = [byte[]]@(
    0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,
    0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
    0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
    0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
    0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,
    0x54,0x78,0x9C,0x63,0xF8,0xCF,0xC0,0x00,
    0x00,0x03,0x01,0x01,0x00,0x18,0xDD,0x8D,
    0xB1,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,
    0x44,0xAE,0x42,0x60,0x82
  )

  $parent = Split-Path -Path $Path -Parent
  if ($parent) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }

  [System.IO.File]::WriteAllBytes($Path, $pngBytes)
}

function New-LegacyDocsSectionFixture {
  param([Parameter(Mandatory)][string]$TargetRoot)

  New-Item -ItemType Directory -Force -Path (Join-Path $TargetRoot "Docs\WorkflowStandards\ProjectStructure") | Out-Null
  Write-Utf8NoBomFile -Path (Join-Path $TargetRoot "Docs\_domains.json") -Content @'
{
  "schemaVersion": 1,
  "domains": [
    {
      "key": "workflow-standards",
      "dirName": "WorkflowStandards",
      "sidebarId": "workflow-standards-sidebar",
      "label": "Workflow & Standards",
      "position": 10,
      "landingDoc": "WorkflowStandards/README",
      "showLandingInSidebar": false,
      "ownedRoots": ["WorkflowStandards"],
      "ownedDocs": [],
      "catchAll": false
    }
  ]
}
'@
  Write-Utf8NoBomFile -Path (Join-Path $TargetRoot "Docs\WorkflowStandards\README.md") -Content @'
---
title: Workflow And Standards
slug: /workflow-standards
sidebar_position: 1
---

# Workflow And Standards
'@
  Write-Utf8NoBomFile -Path (Join-Path $TargetRoot "Docs\WorkflowStandards\_category_.json") -Content @'
{
  "label": "Workflow & Standards",
  "position": 1,
  "link": {
    "type": "doc",
    "id": "WorkflowStandards/README"
  }
}
'@
  Write-Utf8NoBomFile -Path (Join-Path $TargetRoot "Docs\WorkflowStandards\ProjectStructure\Target-Structure.md") -Content @'
---
title: Target Structure
slug: /target-structure
sidebar_position: 1
---

# Target Structure
'@
}

function Get-TestDocsRuntimeDirectory {
  param([Parameter(Mandatory)][string]$TargetRoot)

  $docsModulePath = Join-Path $payloadRoot "Scripts\UETools\UEToolSuite.Docs.psm1"
  $docsModule = Import-Module -Name $docsModulePath -Force -DisableNameChecking -PassThru
  return (& $docsModule { param($repoRoot) Get-DocsToolsRuntimeDirectory -ResolvedRepoRoot $repoRoot } $TargetRoot)
}

function New-TrackedDocsRuntimeFixture {
  param([Parameter(Mandatory)][string]$TargetRoot)

  $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
  $sleepProcess = Start-Process `
    -FilePath $pwshPath `
    -ArgumentList @("-NoLogo", "-NoProfile", "-Command", "Start-Sleep -Seconds 120") `
    -WindowStyle Hidden `
    -PassThru

  $runtimeDir = Get-TestDocsRuntimeDirectory -TargetRoot $TargetRoot
  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
  $statePath = Join-Path $runtimeDir "docs-server.json"
  $runtimeState = [ordered]@{
    version = 3
    servers = @()
    editorApi = [ordered]@{
      version       = 1
      rootProcessId = $sleepProcess.Id
      processId     = $sleepProcess.Id
      startedAt     = (Get-Date).ToString("o")
      url           = "http://127.0.0.1:38473/"
      port          = 38473
      logPath       = ""
      errorLogPath  = ""
      scriptPath    = (Join-Path $TargetRoot "Scripts\UETools\DocsEditorApiHost.ps1")
      modulePath    = (Join-Path $TargetRoot "Scripts\UETools\UEToolSuite.Docs.psm1")
    }
  }
  Write-Utf8NoBomFile -Path $statePath -Content ($runtimeState | ConvertTo-Json -Depth 10)

  $runtimeConfigPath = Join-Path $TargetRoot "website\static\ue-tools\editor-runtime.json"
  Write-Utf8NoBomFile -Path $runtimeConfigPath -Content (@{
      apiUrl = "http://127.0.0.1:38473/"
    } | ConvertTo-Json -Depth 5)

  return [pscustomobject]@{
    ProcessId         = $sleepProcess.Id
    RuntimeDirectory  = $runtimeDir
    RuntimeStatePath  = $statePath
    RuntimeConfigPath = $runtimeConfigPath
  }
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
      "Scripts\UETools\UEToolSuite.Init.psm1",
      "Scripts\ue-tools.ps1",
      "Scripts\UETools\UEToolSuite.Core.psm1",
      "Scripts\UETools\UEToolSuite.Dispatcher.psm1",
      "Scripts\UETools\UEToolSuite.Aliases.psm1",
      "Scripts\UETools\UEToolSuite.Unreal.psm1",
      "Scripts\UETools\UEToolSuite.Docs.psm1",
      "Docs\WorkflowStandards\Setup.md",
      "Docs\WorkflowStandards\Pipeline\README.md",
      "Docs\WorkflowStandards\DocsSite\Docusaurus-Setup.md",
      "website\package.json",
      "website\docusaurus.config.ts",
      "website\.gitignore",
      "website\static\.nojekyll",
      "website\static\img\themes\neutral\logo.svg",
      "website\static\img\themes\neutral\favicon.svg",
      "website\static\img\themes\neutral\social-card.svg",
      "website\.ue-tools\ownership.json",
      ".ue-tools\state\docs-managed-ledger.json",
      ".ue-tools\state\website-managed-ledger.json",
      "website\build\index.html"
    )) {
    Assert-PathExists "case1 installed $relativePath" (Join-Path $targetRepo $relativePath)
  }
  $case1WebsiteBuildJsAssets = @(Get-ChildItem -LiteralPath (Join-Path $targetRepo "website\build\assets\js") -File -Filter *.js -ErrorAction SilentlyContinue)
  Assert-Condition "case1 installed website build javascript assets" ($case1WebsiteBuildJsAssets.Count -gt 0) "build js asset count=$($case1WebsiteBuildJsAssets.Count)" "missing website build javascript assets"
  Assert-FileContains "case1 installed git attributes marker" (Join-Path $targetRepo ".gitattributes") "# >>> ue tool suite git attributes >>>"
  Assert-FileContains "case1 installed git ignore marker" (Join-Path $targetRepo ".gitignore") "# >>> ue tool suite git ignore >>>"
  Assert-FileContains "case1 installed binary guard uasset rule" (Join-Path $targetRepo ".gitattributes") "*.uasset filter=lfs diff=lfs merge=binary -text"
  Assert-FileContains "case1 default website custom css imports active theme" (Join-Path $targetRepo "website\src\css\custom.css") "@import '../../theme-presets/active-theme.css';"
  Assert-FileContains "case1 default website theme is neutral" (Join-Path $targetRepo "website\theme-presets\active-theme.css") "--ifm-color-primary: #3a6ea5;"
  Assert-FileContains "case1 website title uses project name" (Join-Path $targetRepo "website\docusaurus.config.ts") "title: 'PortableSample Docs'"
  Assert-FileContains "case1 website custom field project name uses .uproject stem" (Join-Path $targetRepo "website\docusaurus.config.ts") "suiteProjectName: 'PortableSample'"
  Assert-FileContains "case1 website custom field theme id is neutral" (Join-Path $targetRepo "website\docusaurus.config.ts") "suiteThemeId: 'neutral'"
  Assert-FileContains "case1 website default navbar logo is neutral themed icon" (Join-Path $targetRepo "website\docusaurus.config.ts") "src: 'img/themes/neutral/logo.svg'"
  Assert-FileContains "case1 website default favicon is neutral themed icon" (Join-Path $targetRepo "website\docusaurus.config.ts") "favicon: 'img/themes/neutral/favicon.svg'"
  Assert-FileContains "case1 website default social card is neutral themed icon" (Join-Path $targetRepo "website\docusaurus.config.ts") "image: 'img/themes/neutral/social-card.svg'"

  foreach ($relativePath in @(
      "Scripts\Install-UEProjectTools.ps1",
      "Docs\GameDesign\README.md",
      "Docs\ProjectStructure\Target-Structure.md",
      "Docs\AI\Project-Context.md"
    )) {
    Assert-PathMissing "case1 skipped $relativePath" (Join-Path $targetRepo $relativePath)
  }

  Step "Case 2: update removes legacy installer and writes backup"
  Write-Utf8NoBomFile -Path (Join-Path $targetRepo "Scripts\Install-UEProjectTools.ps1") -Content "legacy installer`n"
  Write-Utf8NoBomFile -Path (Join-Path $targetRepo "Scripts\UETools\UEToolSuite.Unreal.psm1") -Content "legacy sync`n"
  $gitIgnorePath = Join-Path $targetRepo ".gitignore"
  $existingGitIgnore = Get-Content -LiteralPath $gitIgnorePath -Raw
  Write-Utf8NoBomFile -Path $gitIgnorePath -Content ("local-custom-ignore/`n`n" + $existingGitIgnore)
  $docsLedgerPath = Join-Path $targetRepo ".ue-tools\state\docs-managed-ledger.json"
  Assert-PathExists "case2 docs ledger exists before update" $docsLedgerPath
  $docsLedger = Get-Content -LiteralPath $docsLedgerPath -Raw | ConvertFrom-Json
  $autoUpdateRelativePath = "Docs/WorkflowStandards/Pipeline/README.md"
  $preservedRelativePath = "Docs/WorkflowStandards/DocsSite/Authoring.md"
  $missingRelativePath = "Docs/WorkflowStandards/AI/README.md"
  $autoUpdateTargetPath = Join-Path $targetRepo ($autoUpdateRelativePath -replace "/", "\")
  $preservedTargetPath = Join-Path $targetRepo ($preservedRelativePath -replace "/", "\")
  $missingTargetPath = Join-Path $targetRepo ($missingRelativePath -replace "/", "\")
  Write-Utf8NoBomFile -Path $autoUpdateTargetPath -Content "legacy managed docs version that should auto-update`n"
  $autoUpdateHash = (Get-FileHash -LiteralPath $autoUpdateTargetPath -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-Utf8NoBomFile -Path $preservedTargetPath -Content "project-customized docs content should be preserved`n"
  if (Test-Path -LiteralPath $missingTargetPath) {
    Remove-Item -LiteralPath $missingTargetPath -Force
  }
  foreach ($entry in @($docsLedger.files)) {
    if ($null -eq $entry) { continue }
    if (($entry.relativePath -as [string]) -eq $autoUpdateRelativePath) {
      $entry.installedHash = $autoUpdateHash
      $entry.installedPayloadVersion = "0.9.0"
      break
    }
  }
  Write-Utf8NoBomFile -Path $docsLedgerPath -Content ($docsLedger | ConvertTo-Json -Depth 10)
  Remove-Item -LiteralPath (Join-Path $targetRepo "website\src\css") -Recurse -Force
  Write-Utf8NoBomFile -Path (Join-Path $targetRepo "website\src\css") -Content "stale file blocking managed directory`n"
  $projectSpecificFiles = @(
    [pscustomobject]@{ RelativePath = "Docs\WorkflowStandards\AI\Project-Context.md"; Content = "project-specific ai context should survive`n" },
    [pscustomobject]@{ RelativePath = "Docs\WorkflowStandards\Pipeline\Project-Pipeline-Notes.md"; Content = "project-specific pipeline notes should survive`n" },
    [pscustomobject]@{ RelativePath = "Docs\WorkflowStandards\DocsSite\Local-DocsSite-Notes.md"; Content = "project-specific docs site notes should survive`n" },
    [pscustomobject]@{ RelativePath = "website\src\pages\local-project-page.tsx"; Content = "project-specific docs page should survive`n" }
  )
  foreach ($projectSpecificFile in $projectSpecificFiles) {
    Write-Utf8NoBomFile -Path (Join-Path $targetRepo $projectSpecificFile.RelativePath) -Content $projectSpecificFile.Content
  }
  $updateResult = Invoke-Installer -TargetRoot $targetRepo -ExtraArgs @("-SkipTests")
  Assert-Condition "case2 update exits cleanly" ($updateResult.Code -eq 0) "exit=0" "exit=$($updateResult.Code)"
  Assert-PathMissing "case2 legacy installer removed" (Join-Path $targetRepo "Scripts\Install-UEProjectTools.ps1")
  $backupMatches = @(Get-ChildItem -LiteralPath (Join-Path $targetRepo ".ue-tools-installer-backups") -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "UEToolSuite.Unreal.psm1" })
  Assert-Condition "case2 backup created for replaced tool" ($backupMatches.Count -gt 0) "backup count=$($backupMatches.Count)" "backup missing"
  Assert-FileContains "case2 git ignore preserves local lines" $gitIgnorePath "local-custom-ignore/"
  $gitIgnoreBackupMatches = @(Get-ChildItem -LiteralPath (Join-Path $targetRepo ".ue-tools-installer-backups") -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq ".gitignore" })
  Assert-Condition "case2 backup created for managed git ignore" ($gitIgnoreBackupMatches.Count -gt 0) "backup count=$($gitIgnoreBackupMatches.Count)" "backup missing"
  foreach ($projectSpecificFile in $projectSpecificFiles) {
    Assert-FileContains "case2 preserved target-only $($projectSpecificFile.RelativePath)" (Join-Path $targetRepo $projectSpecificFile.RelativePath) $projectSpecificFile.Content.Trim()
  }
  Assert-Condition "case2 replaced file conflict with managed directory" (Test-Path -LiteralPath (Join-Path $targetRepo "website\src\css") -PathType Container) "directory restored" "directory not restored"
  Assert-PathExists "case2 restored payload file under conflict directory" (Join-Path $targetRepo "website\src\css\custom.css")
  Assert-FileContains "case2 auto-updated managed docs file" $autoUpdateTargetPath "# Daily Workflow"
  Assert-FileContains "case2 preserved customized docs file content" $preservedTargetPath "project-customized docs content should be preserved"
  Assert-PathMissing "case2 missing managed docs file remains missing by default" $missingTargetPath
  $docsUpdateReportRoot = Join-Path $targetRepo ".ue-tools-installer-updates"
  $docsUpdateReport = @(Get-ChildItem -LiteralPath $docsUpdateReportRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Update-Report.md" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
  Assert-Condition "case2 docs smart update report emitted" ($docsUpdateReport.Count -eq 1) "report written" "docs update report missing"
  if ($docsUpdateReport.Count -eq 1) {
    $reportText = Get-Content -LiteralPath $docsUpdateReport[0].FullName -Raw
    Assert-Condition "case2 report lists preserved customized file" ($reportText -like "*$preservedRelativePath*") "preserved path listed" "preserved path missing from report"
    Assert-Condition "case2 report lists missing preserved file" ($reportText -like "*$missingRelativePath*") "missing path listed" "missing path missing from report"
    $candidateRoot = Join-Path $docsUpdateReport[0].Directory.FullName "candidates"
    Assert-PathExists "case2 candidate generated for preserved customized file" (Join-Path $candidateRoot ($preservedRelativePath -replace "/", "\"))
    Assert-PathExists "case2 candidate generated for missing managed file" (Join-Path $candidateRoot ($missingRelativePath -replace "/", "\"))
  }

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

  Step "Case 2c: legacy repo without docs ledger preserves customized defaults and emits candidates"
  $legacyDocsRepo = New-TargetRepo "legacy docs target"
  Write-Utf8NoBomFile -Path (Join-Path $legacyDocsRepo "Docs\README.md") -Content "legacy customized docs root should be preserved`n"
  $legacyDocsResult = Invoke-Installer -TargetRoot $legacyDocsRepo -ExtraArgs @("-SkipTests", "-SkipWebsite")
  Assert-Condition "case2c legacy docs install exits cleanly" ($legacyDocsResult.Code -eq 0) "exit=0" "exit=$($legacyDocsResult.Code)"
  Assert-FileContains "case2c legacy customized docs file preserved" (Join-Path $legacyDocsRepo "Docs\README.md") "legacy customized docs root should be preserved"
  $legacyReport = @(Get-ChildItem -LiteralPath (Join-Path $legacyDocsRepo ".ue-tools-installer-updates") -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Update-Report.md" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
  Assert-Condition "case2c docs update report emitted for legacy preserve path" ($legacyReport.Count -eq 1) "report written" "legacy report missing"
  if ($legacyReport.Count -eq 1) {
    $legacyReportText = Get-Content -LiteralPath $legacyReport[0].FullName -Raw
    Assert-Condition "case2c report includes docs readme preserve entry" ($legacyReportText -like "*Docs/README.md*") "docs readme listed" "docs readme missing from report"
    Assert-PathExists "case2c candidate generated for preserved legacy docs file" (Join-Path $legacyReport[0].Directory.FullName "candidates\Docs\README.md")
  }

  Step "Case 2d: install migrates legacy docs sections without RunInit"
  $migrationInstallRepo = New-TargetRepo "legacy migration target"
  New-LegacyDocsSectionFixture -TargetRoot $migrationInstallRepo
  $legacySectionHashBeforeInstall = (Get-FileHash -LiteralPath (Join-Path $migrationInstallRepo "Docs\WorkflowStandards\ProjectStructure\Target-Structure.md") -Algorithm SHA256).Hash
  $migrationInstallResult = Invoke-Installer -TargetRoot $migrationInstallRepo -ExtraArgs @("-SkipTests", "-SkipWebsite")
  Assert-Condition "case2d legacy migration install exits cleanly" ($migrationInstallResult.Code -eq 0) "exit=0" "exit=$($migrationInstallResult.Code)"
  Assert-PathExists "case2d legacy migration category created" (Join-Path $migrationInstallRepo "Docs\WorkflowStandards\ProjectStructure\_category_.json")
  Assert-PathMissing "case2d legacy migration does not create readme" (Join-Path $migrationInstallRepo "Docs\WorkflowStandards\ProjectStructure\README.md")
  Assert-Condition "case2d child markdown hash preserved" ((Get-FileHash -LiteralPath (Join-Path $migrationInstallRepo "Docs\WorkflowStandards\ProjectStructure\Target-Structure.md") -Algorithm SHA256).Hash -eq $legacySectionHashBeforeInstall) "hash preserved" "Target-Structure.md changed during install migration"
  $migrationInstallCategoryText = Get-Content -LiteralPath (Join-Path $migrationInstallRepo "Docs\WorkflowStandards\ProjectStructure\_category_.json") -Raw
  Assert-FileContains "case2d migration category label preserved" (Join-Path $migrationInstallRepo "Docs\WorkflowStandards\ProjectStructure\_category_.json") '"label": "ProjectStructure"'
  Assert-Condition "case2d migration category omits link" ($migrationInstallCategoryText -notlike '*"link":*') "link omitted" "unexpected link generated"
  $migrationReport = @(Get-ChildItem -LiteralPath (Join-Path $migrationInstallRepo ".ue-tools-installer-updates") -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Docs-Section-Migration.md" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
  Assert-Condition "case2d docs section migration report emitted" ($migrationReport.Count -eq 1) "report written" "migration report missing"
  if ($migrationReport.Count -eq 1) {
    $migrationReportText = Get-Content -LiteralPath $migrationReport[0].FullName -Raw
    Assert-Condition "case2d migration report lists normalized section" ($migrationReportText -like "*WorkflowStandards/ProjectStructure*") "legacy section listed" "legacy section missing from migration report"
  }
  $migrationLedgerText = Get-Content -LiteralPath (Join-Path $migrationInstallRepo ".ue-tools\state\docs-managed-ledger.json") -Raw
  Assert-Condition "case2d project migration category not added to managed ledger" ($migrationLedgerText -notlike "*WorkflowStandards/ProjectStructure/_category_.json*") "legacy category absent from ledger" "legacy category unexpectedly tracked as managed"

  Step "Case 2e: rerunning install after migration is idempotent"
  $migrationCategoryFirstRun = Get-Content -LiteralPath (Join-Path $migrationInstallRepo "Docs\WorkflowStandards\ProjectStructure\_category_.json") -Raw
  $migrationRerunResult = Invoke-Installer -TargetRoot $migrationInstallRepo -ExtraArgs @("-SkipTests", "-SkipWebsite")
  Assert-Condition "case2e legacy migration rerun exits cleanly" ($migrationRerunResult.Code -eq 0) "exit=0" "exit=$($migrationRerunResult.Code)"
  Assert-Condition "case2e legacy migration rerun is idempotent" ((Get-Content -LiteralPath (Join-Path $migrationInstallRepo "Docs\WorkflowStandards\ProjectStructure\_category_.json") -Raw) -eq $migrationCategoryFirstRun) "category unchanged" "category changed on rerun"

  Step "Case 2f: SkipDocsSectionMigration preserves legacy section state"
  $skipMigrationRepo = New-TargetRepo "skip docs section migration target"
  New-LegacyDocsSectionFixture -TargetRoot $skipMigrationRepo
  $skipMigrationResult = Invoke-Installer -TargetRoot $skipMigrationRepo -ExtraArgs @("-SkipTests", "-SkipWebsite", "-SkipDocsSectionMigration")
  Assert-Condition "case2f skip docs section migration exits cleanly" ($skipMigrationResult.Code -eq 0) "exit=0" "exit=$($skipMigrationResult.Code)"
  Assert-PathMissing "case2f skip migration leaves category absent" (Join-Path $skipMigrationRepo "Docs\WorkflowStandards\ProjectStructure\_category_.json")
  $skipMigrationReport = @(Get-ChildItem -LiteralPath (Join-Path $skipMigrationRepo ".ue-tools-installer-updates") -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Docs-Section-Migration.md" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
  Assert-Condition "case2f skip migration report emitted" ($skipMigrationReport.Count -eq 1) "report written" "skip migration report missing"
  if ($skipMigrationReport.Count -eq 1) {
    $skipMigrationReportText = Get-Content -LiteralPath $skipMigrationReport[0].FullName -Raw
    Assert-Condition "case2f skip migration report records skipped status" ($skipMigrationReportText -like "*Status: skipped-by-parameter*") "skip status recorded" "skip status missing from migration report"
  }

  Step "Case 2g: managed git metadata removes duplicate unmanaged payload entries and reruns idempotently"
  $managedGitMetadataRepo = New-TargetRepo "managed git metadata target"
  $payloadGitIgnore = Get-Content -LiteralPath (Join-Path $payloadRoot ".gitignore") -Raw
  $payloadGitAttributes = Get-Content -LiteralPath (Join-Path $payloadRoot ".gitattributes") -Raw
  $legacyGitIgnore = $payloadGitIgnore -replace "(?ms)^# >>> ue tool suite git ignore >>>\r?\n", "" -replace "\r?\n# <<< ue tool suite git ignore <<<\r?\n?$", "`n"
  $legacyGitAttributes = $payloadGitAttributes -replace "(?ms)^# >>> ue tool suite git attributes >>>\r?\n", "" -replace "\r?\n# <<< ue tool suite git attributes <<<\r?\n?$", "`n"
  Write-Utf8NoBomFile -Path (Join-Path $managedGitMetadataRepo ".gitignore") -Content ("project-local-ignore/`n`n" + $legacyGitIgnore + "`nwebsite/node_modules/`n")
  Write-Utf8NoBomFile -Path (Join-Path $managedGitMetadataRepo ".gitattributes") -Content ("*.generated text eol=crlf`n`n" + $legacyGitAttributes + "`n*.uasset filter=lfs diff=lfs merge=binary -text`n")
  $managedGitMetadataResult = Invoke-Installer -TargetRoot $managedGitMetadataRepo -ExtraArgs @("-SkipTests")
  Assert-Condition "case2d installer exits cleanly" ($managedGitMetadataResult.Code -eq 0) "exit=0" "exit=$($managedGitMetadataResult.Code)"
  $managedGitIgnoreText = Get-Content -LiteralPath (Join-Path $managedGitMetadataRepo ".gitignore") -Raw
  $managedGitAttributesText = Get-Content -LiteralPath (Join-Path $managedGitMetadataRepo ".gitattributes") -Raw
  Assert-Condition "case2d git ignore marker occurs once" ((Get-LineMatchCount -Text $managedGitIgnoreText -Line "# >>> ue tool suite git ignore >>>") -eq 1) "single managed block" "duplicate managed block markers remain"
  Assert-Condition "case2d git attributes marker occurs once" ((Get-LineMatchCount -Text $managedGitAttributesText -Line "# >>> ue tool suite git attributes >>>") -eq 1) "single managed block" "duplicate managed block markers remain"
  Assert-Condition "case2d git ignore duplicate entry removed" ((Get-LineMatchCount -Text $managedGitIgnoreText -Line "website/node_modules/") -eq 1) "single managed entry" "duplicate website/node_modules/ entry remains"
  Assert-Condition "case2d git attributes duplicate entry removed" ((Get-LineMatchCount -Text $managedGitAttributesText -Line "*.uasset filter=lfs diff=lfs merge=binary -text") -eq 1) "single managed entry" "duplicate *.uasset managed entry remains"
  Assert-FileContains "case2d git ignore preserves local rule" (Join-Path $managedGitMetadataRepo ".gitignore") "project-local-ignore/"
  Assert-FileContains "case2d git attributes preserves local rule" (Join-Path $managedGitMetadataRepo ".gitattributes") "*.generated text eol=crlf"
  $managedGitIgnoreFirstRun = $managedGitIgnoreText
  $managedGitAttributesFirstRun = $managedGitAttributesText
  $managedGitMetadataRerun = Invoke-Installer -TargetRoot $managedGitMetadataRepo -ExtraArgs @("-SkipTests")
  Assert-Condition "case2d rerun exits cleanly" ($managedGitMetadataRerun.Code -eq 0) "exit=0" "exit=$($managedGitMetadataRerun.Code)"
  Assert-Condition "case2d git ignore rerun is idempotent" ((Get-Content -LiteralPath (Join-Path $managedGitMetadataRepo ".gitignore") -Raw) -eq $managedGitIgnoreFirstRun) "content unchanged" "gitignore changed on rerun"
  Assert-Condition "case2d git attributes rerun is idempotent" ((Get-Content -LiteralPath (Join-Path $managedGitMetadataRepo ".gitattributes") -Raw) -eq $managedGitAttributesFirstRun) "content unchanged" "gitattributes changed on rerun"

  Step "Case 2e: installer stops tracked docs runtime before updating managed payload files"
  $runtimeStopRepo = New-TargetRepo "runtime stop target"
  $runtimeStopInstallResult = Invoke-Installer -TargetRoot $runtimeStopRepo -ExtraArgs @("-SkipTests")
  Assert-Condition "case2e initial install exits cleanly" ($runtimeStopInstallResult.Code -eq 0) "exit=0" "exit=$($runtimeStopInstallResult.Code)"
  $runtimeFixture = New-TrackedDocsRuntimeFixture -TargetRoot $runtimeStopRepo
  $runtimeStopUpdateResult = Invoke-Installer -TargetRoot $runtimeStopRepo -ExtraArgs @("-SkipTests")
  Assert-Condition "case2e update exits cleanly" ($runtimeStopUpdateResult.Code -eq 0) "exit=0" "exit=$($runtimeStopUpdateResult.Code)"
  Assert-Condition "case2e installer reports docs runtime shutdown" ($runtimeStopUpdateResult.Output -like "*Stopped existing docs runtime before updating managed docs payload files.*") "stop message emitted" "stop message missing"
  Assert-Condition "case2e tracked runtime process stopped" (-not (Get-Process -Id $runtimeFixture.ProcessId -ErrorAction SilentlyContinue)) "process stopped" "process $($runtimeFixture.ProcessId) still running"
  Assert-PathMissing "case2e runtime state file removed" $runtimeFixture.RuntimeStatePath

  Step "Case 2f: managed website update removes obsolete build assets tracked in the website ledger"
  $websiteCleanupRepo = New-TargetRepo "website cleanup target"
  $websiteCleanupInstallResult = Invoke-Installer -TargetRoot $websiteCleanupRepo -ExtraArgs @("-SkipTests")
  Assert-Condition "case2f initial install exits cleanly" ($websiteCleanupInstallResult.Code -eq 0) "exit=0" "exit=$($websiteCleanupInstallResult.Code)"
  $websiteCleanupLedgerPath = Join-Path $websiteCleanupRepo ".ue-tools\state\website-managed-ledger.json"
  Assert-PathExists "case2f website ledger exists before update" $websiteCleanupLedgerPath
  $staleBuildRelativePath = "website/build/assets/js/stale-runtime.bundle.js"
  $staleBuildPath = Join-Path $websiteCleanupRepo ($staleBuildRelativePath -replace "/", "\")
  Write-Utf8NoBomFile -Path $staleBuildPath -Content "stale managed asset`n"
  $websiteCleanupLedger = Get-Content -LiteralPath $websiteCleanupLedgerPath -Raw | ConvertFrom-Json
  $websiteCleanupFiles = New-Object System.Collections.Generic.List[object]
  foreach ($entry in @($websiteCleanupLedger.files)) {
    if ($null -ne $entry) {
      $websiteCleanupFiles.Add($entry) | Out-Null
    }
  }
  $websiteCleanupFiles.Add([pscustomobject]@{
      relativePath = $staleBuildRelativePath
      installedPayloadVersion = "0.9.0"
      installedHash = (Get-FileHash -LiteralPath $staleBuildPath -Algorithm SHA256).Hash.ToLowerInvariant()
      updatedUtc = "2026-01-01T00:00:00Z"
      category = "shell"
    }) | Out-Null
  $websiteCleanupLedger.files = @($websiteCleanupFiles.ToArray())
  Write-Utf8NoBomFile -Path $websiteCleanupLedgerPath -Content ($websiteCleanupLedger | ConvertTo-Json -Depth 10)
  $websiteCleanupUpdateResult = Invoke-Installer -TargetRoot $websiteCleanupRepo -ExtraArgs @("-SkipTests")
  Assert-Condition "case2f update exits cleanly" ($websiteCleanupUpdateResult.Code -eq 0) "exit=0" "exit=$($websiteCleanupUpdateResult.Code)"
  Assert-PathMissing "case2f stale managed build asset removed" $staleBuildPath
  $websiteCleanupReport = @(Get-ChildItem -LiteralPath (Join-Path $websiteCleanupRepo ".ue-tools-installer-updates") -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Website-Update-Report.md" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
  Assert-Condition "case2f website update report emitted" ($websiteCleanupReport.Count -eq 1) "report written" "website update report missing"
  if ($websiteCleanupReport.Count -eq 1) {
    Assert-FileContains "case2f website update report lists removed obsolete asset" $websiteCleanupReport[0].FullName $staleBuildRelativePath
  }

  Step "Case 2g: managed website update refreshes the build directory even when older ledgers did not track build assets"
  $websiteBuildRefreshRepo = New-TargetRepo "website build refresh target"
  $websiteBuildRefreshInstallResult = Invoke-Installer -TargetRoot $websiteBuildRefreshRepo -ExtraArgs @("-SkipTests")
  Assert-Condition "case2g initial install exits cleanly" ($websiteBuildRefreshInstallResult.Code -eq 0) "exit=0" "exit=$($websiteBuildRefreshInstallResult.Code)"
  $websiteBuildRefreshLedgerPath = Join-Path $websiteBuildRefreshRepo ".ue-tools\state\website-managed-ledger.json"
  Assert-PathExists "case2g website ledger exists before update" $websiteBuildRefreshLedgerPath
  $legacyBuildRelativePath = "website/build/assets/js/legacy-runtime.bundle.js"
  $legacyBuildPath = Join-Path $websiteBuildRefreshRepo ($legacyBuildRelativePath -replace "/", "\")
  Write-Utf8NoBomFile -Path $legacyBuildPath -Content "legacy build asset`n"
  $websiteBuildRefreshLedger = Get-Content -LiteralPath $websiteBuildRefreshLedgerPath -Raw | ConvertFrom-Json
  $websiteBuildRefreshLedger.files = @(
    foreach ($entry in @($websiteBuildRefreshLedger.files)) {
      if ($null -eq $entry) { continue }
      if (([string]$entry.relativePath) -like "website/build/*") {
        continue
      }
      $entry
    }
  )
  Write-Utf8NoBomFile -Path $websiteBuildRefreshLedgerPath -Content ($websiteBuildRefreshLedger | ConvertTo-Json -Depth 10)
  $websiteBuildRefreshUpdateResult = Invoke-Installer -TargetRoot $websiteBuildRefreshRepo -ExtraArgs @("-SkipTests")
  Assert-Condition "case2g update exits cleanly" ($websiteBuildRefreshUpdateResult.Code -eq 0) "exit=0" "exit=$($websiteBuildRefreshUpdateResult.Code)"
  Assert-PathMissing "case2g legacy build asset removed by build refresh" $legacyBuildPath
  $websiteBuildRefreshNewMain = @(Get-ChildItem -LiteralPath (Join-Path $websiteBuildRefreshRepo "website\build\assets\js") -File -Filter "main.*.js" -ErrorAction SilentlyContinue)
  Assert-Condition "case2g refreshed build directory still contains managed main bundle" ($websiteBuildRefreshNewMain.Count -gt 0) "main bundle count=$($websiteBuildRefreshNewMain.Count)" "managed main bundle missing after build refresh"

  Step "Case 3: installer can run target Init-Repo"
  $initRepo = New-TargetRepo "run init target"
  & git -C $initRepo remote add origin "git@github.com:AcmeTools/PortableSample.git" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "git remote add failed for target repo: $initRepo" }
  $ignoredTrackedRelativePath = "Scripts/Tests/CrashEvidenceResults/preexisting-output.txt"
  Write-Utf8NoBomFile -Path (Join-Path $initRepo $ignoredTrackedRelativePath) -Content "preexisting generated artifact`n"
  & git -C $initRepo add -- $ignoredTrackedRelativePath | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "git add failed for tracked ignored fixture file: $ignoredTrackedRelativePath" }
  & git -C $initRepo commit -m "test: add tracked file that should become ignored after install" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "git commit failed for tracked ignored fixture file: $ignoredTrackedRelativePath" }
  $initResult = Invoke-Installer -TargetRoot $initRepo -ExtraArgs @(
    "-SkipTests",
    "-RunInit",
    "-InitNonInteractive",
    "-SkipLfsPull",
    "-SkipShellAliases",
    "-SkipOptionalToolSetup",
    "-SkipDocsSetup",
    "-SkipUnrealSync"
  )
  Assert-Condition "case3 init install exits cleanly" ($initResult.Code -eq 0) "exit=0" "exit=$($initResult.Code)"
  Assert-Condition "case3 init bootstrap forced non-interactive" ($initResult.Output -like "*-NonInteractive*") "non-interactive switch present" "non-interactive switch missing"
  Assert-Condition "case3 init ran" ($initResult.Output -like "*Repo initialization complete.*") "init completed" "init output missing completion"
  $trackedIgnoredListing = @(& git -C $initRepo ls-files --error-unmatch -- $ignoredTrackedRelativePath 2>$null)
  Assert-Condition "case3 tracked ignored file removed from git index" ($LASTEXITCODE -ne 0) "untracked from index" "still tracked in git index"
  Assert-PathExists "case3 tracked ignored file remains on disk" (Join-Path $initRepo $ignoredTrackedRelativePath)
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
  Assert-PathExists "case5 docs tooling retained" (Join-Path $skipWebsiteRepo "Scripts\UETools\UEToolSuite.Docs.psm1")
  Assert-PathExists "case5 docs retained" (Join-Path $skipWebsiteRepo "Docs\README.md")

  Step "Case 5b: explicit website theme and SVG logo are applied"
  $themedRepo = New-TargetRepo "themed website target"
  $svgLogoPath = Join-Path $tempRoot "sample-project-logo.svg"
  Write-Utf8NoBomFile -Path $svgLogoPath -Content @'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" fill="#0d7ea2"/>
  <circle cx="32" cy="32" r="18" fill="#ffffff"/>
</svg>
'@
  $themedResult = Invoke-Installer -TargetRoot $themedRepo -ExtraArgs @("-SkipTests", "-WebsiteTheme", "ocean", "-WebsiteLogoPath", $svgLogoPath)
  Assert-Condition "case5b themed install exits cleanly" ($themedResult.Code -eq 0) "exit=0" "exit=$($themedResult.Code)"
  Assert-FileContains "case5b custom css imports active theme" (Join-Path $themedRepo "website\src\css\custom.css") "@import '../../theme-presets/active-theme.css';"
  Assert-FileContains "case5b ocean theme copied to active-theme.css" (Join-Path $themedRepo "website\theme-presets\active-theme.css") "--ifm-color-primary: #0d7ea2;"
  Assert-FileContains "case5b config stores ocean theme id" (Join-Path $themedRepo "website\docusaurus.config.ts") "suiteThemeId: 'ocean'"
  Assert-FileContains "case5b config points logo src to branding asset" (Join-Path $themedRepo "website\docusaurus.config.ts") "src: 'img/branding/project-logo.svg'"
  Assert-FileContains "case5b custom logo also rewires favicon" (Join-Path $themedRepo "website\docusaurus.config.ts") "favicon: 'img/branding/project-favicon.svg'"
  Assert-FileContains "case5b custom logo also rewires social card" (Join-Path $themedRepo "website\docusaurus.config.ts") "image: 'img/branding/project-social-card.svg'"
  Assert-PathExists "case5b svg logo copied into website branding assets" (Join-Path $themedRepo "website\static\img\branding\project-logo.svg")
  Assert-PathExists "case5b svg favicon copied into website branding assets" (Join-Path $themedRepo "website\static\img\branding\project-favicon.svg")
  Assert-PathExists "case5b svg social card copied into website branding assets" (Join-Path $themedRepo "website\static\img\branding\project-social-card.svg")

  Step "Case 5c: PNG logo is accepted and applied"
  $pngLogoRepo = New-TargetRepo "png logo target"
  $pngLogoPath = Join-Path $tempRoot "sample-project-logo.png"
  Write-TestPngFile -Path $pngLogoPath
  $pngLogoResult = Invoke-Installer -TargetRoot $pngLogoRepo -ExtraArgs @("-SkipTests", "-WebsiteTheme", "violet", "-WebsiteLogoPath", $pngLogoPath)
  Assert-Condition "case5c png logo install exits cleanly" ($pngLogoResult.Code -eq 0) "exit=0" "exit=$($pngLogoResult.Code)"
  Assert-FileContains "case5c custom css imports active theme" (Join-Path $pngLogoRepo "website\src\css\custom.css") "@import '../../theme-presets/active-theme.css';"
  Assert-FileContains "case5c violet theme copied to active-theme.css" (Join-Path $pngLogoRepo "website\theme-presets\active-theme.css") "--ifm-color-primary: #6a53c1;"
  Assert-FileContains "case5c config points to png branding asset" (Join-Path $pngLogoRepo "website\docusaurus.config.ts") "src: 'img/branding/project-logo.png'"
  Assert-FileContains "case5c custom png logo rewires favicon" (Join-Path $pngLogoRepo "website\docusaurus.config.ts") "favicon: 'img/branding/project-favicon.png'"
  Assert-FileContains "case5c custom png logo rewires social card" (Join-Path $pngLogoRepo "website\docusaurus.config.ts") "image: 'img/branding/project-social-card.png'"
  Assert-PathExists "case5c png logo copied into website branding assets" (Join-Path $pngLogoRepo "website\static\img\branding\project-logo.png")
  Assert-PathExists "case5c png favicon copied into website branding assets" (Join-Path $pngLogoRepo "website\static\img\branding\project-favicon.png")
  Assert-PathExists "case5c png social card copied into website branding assets" (Join-Path $pngLogoRepo "website\static\img\branding\project-social-card.png")

  Step "Case 5d: invalid website theme fails with clear allowed-values message"
  $invalidThemeRepo = New-TargetRepo "invalid theme target"
  $invalidThemeResult = Invoke-Installer -TargetRoot $invalidThemeRepo -ExtraArgs @("-SkipTests", "-WebsiteTheme", "not-a-real-theme")
  Assert-Condition "case5d invalid theme returns non-zero" ($invalidThemeResult.Code -ne 0) "exit=$($invalidThemeResult.Code)" "unexpected success"
  Assert-Condition "case5d invalid theme error includes allowed values" ($invalidThemeResult.Output -like "*Unknown website theme*Allowed themes:*") "clear invalid-theme message present" "invalid-theme message missing"

  Step "Case 5e: invalid logo path fails with clear error"
  $invalidLogoRepo = New-TargetRepo "invalid logo target"
  $invalidLogoPath = Join-Path $tempRoot "does-not-exist-logo.svg"
  $invalidLogoResult = Invoke-Installer -TargetRoot $invalidLogoRepo -ExtraArgs @("-SkipTests", "-WebsiteTheme", "neutral", "-WebsiteLogoPath", $invalidLogoPath)
  Assert-Condition "case5e invalid logo returns non-zero" ($invalidLogoResult.Code -ne 0) "exit=$($invalidLogoResult.Code)" "unexpected success"
  Assert-Condition "case5e invalid logo message is clear" ($invalidLogoResult.Output -like "*WebsiteLogoPath does not exist or is not a file*") "clear invalid-logo message present" "invalid-logo message missing"

  Step "Case 5f: SkipWebsite bypasses website theme and logo validation"
  $skipWebsiteBypassRepo = New-TargetRepo "skip website bypass target"
  $skipWebsiteBypassResult = Invoke-Installer -TargetRoot $skipWebsiteBypassRepo -ExtraArgs @("-SkipTests", "-SkipWebsite", "-WebsiteTheme", "not-a-real-theme", "-WebsiteLogoPath", $invalidLogoPath)
  Assert-Condition "case5f skip website with theme/logo flags exits cleanly" ($skipWebsiteBypassResult.Code -eq 0) "exit=0" "exit=$($skipWebsiteBypassResult.Code)"
  Assert-PathMissing "case5f website remains skipped" (Join-Path $skipWebsiteBypassRepo "website\package.json")

  Step "Case 5g: PreserveExisting keeps an unmanaged website untouched"
  $preserveWebsiteRepo = New-TargetRepo "preserve website target"
  $preserveWebsiteRoot = Join-Path $preserveWebsiteRepo "website"
  New-Item -ItemType Directory -Force -Path (Join-Path $preserveWebsiteRoot "src\css") | Out-Null
  Write-Utf8NoBomFile -Path (Join-Path $preserveWebsiteRoot "package.json") -Content '{"name":"custom-site"}'
  Write-Utf8NoBomFile -Path (Join-Path $preserveWebsiteRoot "docusaurus.config.ts") -Content "export default { title: 'Custom Site' }`n"
  Write-Utf8NoBomFile -Path (Join-Path $preserveWebsiteRoot "src\css\custom.css") -Content "/* preserved custom css */`n:root { --ifm-color-primary: #ff0000; }`n"
  $preserveWebsiteResult = Invoke-Installer -TargetRoot $preserveWebsiteRepo -ExtraArgs @("-SkipTests", "-SkipDocs", "-WebsiteInstallMode", "PreserveExisting", "-WebsiteTheme", "not-a-real-theme")
  Assert-Condition "case5g unmanaged website preserve exits cleanly" ($preserveWebsiteResult.Code -eq 0) "exit=0" "exit=$($preserveWebsiteResult.Code)"
  Assert-FileContains "case5g custom css preserved" (Join-Path $preserveWebsiteRoot "src\css\custom.css") "--ifm-color-primary: #ff0000;"
  Assert-Condition "case5g output notes unmanaged website preserve mode" ($preserveWebsiteResult.Output -like "*Preserving current Docusaurus site*") "preserve guidance emitted" "preserve guidance missing"
  Assert-PathMissing "case5g ownership marker not created for preserved website" (Join-Path $preserveWebsiteRoot ".ue-tools\ownership.json")

  Step "Case 5h: adopt existing website allows managed theme updates"
  $adoptWebsiteRepo = New-TargetRepo "adopt website target"
  $adoptWebsiteRoot = Join-Path $adoptWebsiteRepo "website"
  New-Item -ItemType Directory -Force -Path (Join-Path $adoptWebsiteRoot "src\css") | Out-Null
  Copy-Item -LiteralPath (Join-Path $payloadRoot "website\docusaurus.config.ts") -Destination (Join-Path $adoptWebsiteRoot "docusaurus.config.ts") -Force
  Write-Utf8NoBomFile -Path (Join-Path $adoptWebsiteRoot "package.json") -Content '{"name":"adopt-site"}'
  Write-Utf8NoBomFile -Path (Join-Path $adoptWebsiteRoot "src\css\custom.css") -Content "/* stale css */`n:root { --ifm-color-primary: #ff0000; }`n"
  $adoptWebsiteResult = Invoke-Installer -TargetRoot $adoptWebsiteRepo -ExtraArgs @("-SkipTests", "-SkipDocs", "-AdoptExistingWebsite", "-WebsiteTheme", "ocean")
  Assert-Condition "case5h adopt website exits cleanly" ($adoptWebsiteResult.Code -eq 0) "exit=0" "exit=$($adoptWebsiteResult.Code)"
  Assert-FileContains "case5h adopted website custom css imports active theme" (Join-Path $adoptWebsiteRoot "src\css\custom.css") "@import '../../theme-presets/active-theme.css';"
  Assert-FileContains "case5h adopted website receives managed theme css" (Join-Path $adoptWebsiteRoot "theme-presets\active-theme.css") "--ifm-color-primary: #0d7ea2;"
  Assert-PathExists "case5h ownership marker created during adoption" (Join-Path $adoptWebsiteRoot ".ue-tools\ownership.json")
  $adoptSnapshotMatches = @(Get-ChildItem -LiteralPath (Join-Path $adoptWebsiteRepo ".ue-tools-installer-backups") -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like "*website*" })
  Assert-Condition "case5h pre-adopt website snapshot backup created" ($adoptSnapshotMatches.Count -gt 0) "backup count=$($adoptSnapshotMatches.Count)" "adopt snapshot backup missing"

  Step "Case 6: NoBackup replaces managed paths without writing backup output"
  $noBackupRepo = New-TargetRepo "no backup target"
  Write-Utf8NoBomFile -Path (Join-Path $noBackupRepo ".gitattributes") -Content "custom attributes`n"
  Write-Utf8NoBomFile -Path (Join-Path $noBackupRepo "Scripts\UETools\UEToolSuite.Unreal.psm1") -Content "legacy sync`n"
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
