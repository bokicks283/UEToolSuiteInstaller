[CmdletBinding()]
param(
  [switch]$FailFast
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
$resultsDir = Join-Path $PSScriptRoot "Test-PackagingContractsResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "PackagingContracts-$stamp.log"

$script:PassCount = 0
$script:FailCount = 0
Initialize-TestHarness -LogPath $logPath -FailFast:$FailFast

function Assert-HasLiteral {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Needle
  )
  Assert-Condition -Name $Name -Condition ($Text -like "*$Needle*") -PassDetail "found '$Needle'" -FailDetail "missing '$Needle'"
}

try {
  Step "Packaging contract checks ($stamp)"
  Write-Log "Repo: $repoRoot" Cyan
  Write-Log "Log : $logPath" Cyan

  $csprojPath = Join-Path $repoRoot "src\UEToolSuiteInstaller.Gui\UEToolSuiteInstaller.Gui.csproj"
  $programPath = Join-Path $repoRoot "src\UEToolSuiteInstaller.Gui\Program.cs"
  $iconPath = Join-Path $repoRoot "src\UEToolSuiteInstaller.Gui\Assets\UEToolSuiteInstaller.ico"
  $publishScriptPath = Join-Path $repoRoot "Scripts\Publish-InstallerExe.ps1"
  $workflowPath = Join-Path $repoRoot ".github\workflows\release.yml"

  Assert-Condition -Name "GUI project file exists" -Condition (Test-Path -LiteralPath $csprojPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $csprojPath"
  Assert-Condition -Name "GUI runtime file exists" -Condition (Test-Path -LiteralPath $programPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $programPath"
  Assert-Condition -Name "GUI icon exists" -Condition (Test-Path -LiteralPath $iconPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $iconPath"
  Assert-Condition -Name "Publish script exists" -Condition (Test-Path -LiteralPath $publishScriptPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $publishScriptPath"
  Assert-Condition -Name "Release workflow exists" -Condition (Test-Path -LiteralPath $workflowPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $workflowPath"

  Step "GUI publish content contract"
  [xml]$csprojXml = Get-Content -LiteralPath $csprojPath -Raw
  $projectNode = $csprojXml.Project
  Assert-Condition -Name "GUI targets net10 windows" -Condition ($projectNode.PropertyGroup.TargetFramework -contains "net10.0-windows") -PassDetail "net10.0-windows" -FailDetail "TargetFramework mismatch"
  Assert-Condition -Name "GUI single-file publish enabled" -Condition ($projectNode.PropertyGroup.PublishSingleFile -contains "true") -PassDetail "PublishSingleFile=true" -FailDetail "PublishSingleFile not true"
  Assert-Condition -Name "GUI self-contained publish enabled" -Condition ($projectNode.PropertyGroup.SelfContained -contains "true") -PassDetail "SelfContained=true" -FailDetail "SelfContained not true"
  Assert-Condition -Name "GUI application icon configured" -Condition ($projectNode.PropertyGroup.ApplicationIcon -contains "Assets\UEToolSuiteInstaller.ico") -PassDetail "ApplicationIcon configured" -FailDetail "ApplicationIcon missing or incorrect"

  $contentNodes = @($projectNode.ItemGroup.Content)
  $contentInclude = @($contentNodes | ForEach-Object { $_.Include })
  Assert-Condition -Name "GUI bundles installer script content" -Condition ($contentInclude -contains "..\..\Install-UEToolSuite.ps1") -PassDetail "installer script content present" -FailDetail "missing installer script content include"
  Assert-Condition -Name "GUI bundles payload content tree" -Condition ($contentInclude -contains "..\..\payload\**\*") -PassDetail "payload content include present" -FailDetail "missing payload content include"

  Step "GUI runtime contract"
  $programText = Get-Content -LiteralPath $programPath -Raw
  Assert-HasLiteral -Name "gui run-init option exists" -Text $programText -Needle "Run repo initialization after install"
  Assert-HasLiteral -Name "gui run-init requests non-interactive installer init" -Text $programText -Needle "-InitNonInteractive"
  Assert-HasLiteral -Name "gui exposes terminal output toggle" -Text $programText -Needle "Show terminal output"
  Assert-HasLiteral -Name "gui terminal hidden by default" -Text $programText -Needle "Panel2Collapsed = true"
  Assert-HasLiteral -Name "gui defers splitter min constraints until form is sized" -Text $programText -Needle "ApplySplitterMinimums();"
  Assert-HasLiteral -Name "gui terminal is resizable split layout" -Text $programText -Needle "SplitContainer"
  Assert-HasLiteral -Name "gui startup failures show explicit error dialog" -Text $programText -Needle "Installer UI failed to start."
  Assert-HasLiteral -Name "gui includes progress bar" -Text $programText -Needle "ProgressBar"
  Assert-HasLiteral -Name "gui enforces no-output timeout guard" -Text $programText -Needle "NoOutputTimeout"
  Assert-HasLiteral -Name "gui includes cancel button" -Text $programText -Needle "Cancel"
  Assert-HasLiteral -Name "gui prompts for another project on success" -Text $programText -Needle "Install in another project?"
  Assert-HasLiteral -Name "gui includes advanced options panel" -Text $programText -Needle "Show advanced options"
  Assert-HasLiteral -Name "gui advanced options are disabled by default" -Text $programText -Needle 'ConfigureOptionCheckBox(showAdvancedOptionsCheckBox, "Show advanced options", false);'
  Assert-HasLiteral -Name "gui main form supports scrolling for overflow content" -Text $programText -Needle "mainContentScrollPanel.AutoScroll = true;"
  Assert-HasLiteral -Name "gui options container auto-sizes to avoid clipping" -Text $programText -Needle "optionsContainer.AutoSize = true;"
  Assert-HasLiteral -Name "gui advanced panel auto-sizes to avoid clipping" -Text $programText -Needle "advancedOptionsPanel.AutoSize = true;"
  Assert-HasLiteral -Name "gui exposes skip shell aliases option explicitly" -Text $programText -Needle "Skip PowerShell shell alias install during init (-SkipShellAliases)"
  Assert-HasLiteral -Name "gui supports skip docs payload option" -Text $programText -Needle "-SkipDocs"
  Assert-HasLiteral -Name "gui supports skip website payload option" -Text $programText -Needle "-SkipWebsite"
  Assert-HasLiteral -Name "gui supports skip tests payload option" -Text $programText -Needle "-SkipTests"
  Assert-HasLiteral -Name "gui supports skip ai tools payload option" -Text $programText -Needle "-SkipAITools"
  Assert-HasLiteral -Name "gui supports skip artsource tools payload option" -Text $programText -Needle "-SkipArtSourceTools"
  Assert-HasLiteral -Name "gui supports skip coding standards payload option" -Text $programText -Needle "-SkipCodingStandardsTools"
  Assert-HasLiteral -Name "gui supports skip optional setup option" -Text $programText -Needle "-SkipOptionalToolSetup"
  Assert-HasLiteral -Name "gui supports skip docs setup option" -Text $programText -Needle "-SkipDocsSetup"
  Assert-HasLiteral -Name "gui supports skip docs npm install option" -Text $programText -Needle "-SkipDocsNpmInstall"
  Assert-HasLiteral -Name "gui supports force docs npm install option" -Text $programText -Needle "-ForceDocsNpmInstall"
  Assert-HasLiteral -Name "gui supports skip docs bridge option" -Text $programText -Needle "-SkipDocsBridgeInstall"
  Assert-HasLiteral -Name "gui supports no build option" -Text $programText -Needle "-NoBuild"
  Assert-HasLiteral -Name "gui supports no regen option" -Text $programText -Needle "-NoRegen"

  Step "Publish script contract"
  $publishScriptText = Get-Content -LiteralPath $publishScriptPath -Raw
  Assert-HasLiteral -Name "publish script validates .NET SDK list" -Text $publishScriptText -Needle "--list-sdks"
  Assert-HasLiteral -Name "publish script enforces .NET 10 SDK" -Text $publishScriptText -Needle "^10\."
  Assert-HasLiteral -Name "publish script artifact naming convention" -Text $publishScriptText -Needle "UEToolSuiteInstaller-{0}-{1}.exe"
  Assert-HasLiteral -Name "publish script timestamp signing support" -Text $publishScriptText -Needle "/tr $TimestampUrl"
  Assert-HasLiteral -Name "publish script supports thumbprint signing" -Text $publishScriptText -Needle "CertificateThumbprint"
  Assert-HasLiteral -Name "publish script supports PFX signing" -Text $publishScriptText -Needle "CertificatePath"

  Step "Release workflow gate contract"
  $workflowText = Get-Content -LiteralPath $workflowPath -Raw
  Assert-HasLiteral -Name "workflow runs non-mutating full suite" -Text $workflowText -Needle "Tests/Run-UEToolSuiteTests.ps1 -FailFast"
  Assert-HasLiteral -Name "workflow runs mutating ue-sync suite" -Text $workflowText -Needle "ue-sync-automated"
  Assert-HasLiteral -Name "workflow runs mutating binary-guard suite" -Text $workflowText -Needle "binary-guard-fixes"
  Assert-HasLiteral -Name "workflow publishes installer via publish script" -Text $workflowText -Needle "Scripts/Publish-InstallerExe.ps1"
  Assert-HasLiteral -Name "workflow uploads versioned artifact name" -Text $workflowText -Needle 'UEToolSuiteInstaller-${{ steps.version.outputs.value }}-win-x64.exe'

  Step "Summary"
  Write-Log ("PASS={0} FAIL={1}" -f $script:PassCount, $script:FailCount) Cyan
  if ($script:FailCount -eq 0) {
    Write-Log "Packaging contract tests passed." Green
  }
  else {
    Write-Log "Packaging contract tests failed." Red
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
  Write-Log ""
  Write-Log "Log saved: $logPath" Cyan
}
