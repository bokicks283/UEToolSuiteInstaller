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
  $publishScriptPath = Join-Path $repoRoot "Scripts\Publish-InstallerExe.ps1"
  $workflowPath = Join-Path $repoRoot ".github\workflows\release.yml"

  Assert-Condition -Name "GUI project file exists" -Condition (Test-Path -LiteralPath $csprojPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $csprojPath"
  Assert-Condition -Name "GUI runtime file exists" -Condition (Test-Path -LiteralPath $programPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $programPath"
  Assert-Condition -Name "Publish script exists" -Condition (Test-Path -LiteralPath $publishScriptPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $publishScriptPath"
  Assert-Condition -Name "Release workflow exists" -Condition (Test-Path -LiteralPath $workflowPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $workflowPath"

  Step "GUI publish content contract"
  [xml]$csprojXml = Get-Content -LiteralPath $csprojPath -Raw
  $projectNode = $csprojXml.Project
  Assert-Condition -Name "GUI targets net10 windows" -Condition ($projectNode.PropertyGroup.TargetFramework -contains "net10.0-windows") -PassDetail "net10.0-windows" -FailDetail "TargetFramework mismatch"
  Assert-Condition -Name "GUI single-file publish enabled" -Condition ($projectNode.PropertyGroup.PublishSingleFile -contains "true") -PassDetail "PublishSingleFile=true" -FailDetail "PublishSingleFile not true"
  Assert-Condition -Name "GUI self-contained publish enabled" -Condition ($projectNode.PropertyGroup.SelfContained -contains "true") -PassDetail "SelfContained=true" -FailDetail "SelfContained not true"

  $contentNodes = @($projectNode.ItemGroup.Content)
  $contentInclude = @($contentNodes | ForEach-Object { $_.Include })
  Assert-Condition -Name "GUI bundles installer script content" -Condition ($contentInclude -contains "..\..\Install-UEToolSuite.ps1") -PassDetail "installer script content present" -FailDetail "missing installer script content include"
  Assert-Condition -Name "GUI bundles payload content tree" -Condition ($contentInclude -contains "..\..\payload\**\*") -PassDetail "payload content include present" -FailDetail "missing payload content include"

  Step "GUI runtime contract"
  $programText = Get-Content -LiteralPath $programPath -Raw
  Assert-HasLiteral -Name "gui run-init requests non-interactive installer init" -Text $programText -Needle "-InitNonInteractive"
  Assert-HasLiteral -Name "gui exposes terminal output toggle" -Text $programText -Needle "Show terminal output"
  Assert-HasLiteral -Name "gui includes progress bar" -Text $programText -Needle "ProgressBar"
  Assert-HasLiteral -Name "gui enforces no-output timeout guard" -Text $programText -Needle "NoOutputTimeout"

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
