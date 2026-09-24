[CmdletBinding()]
param([switch]$FailFast)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repoRoot "payload\Scripts\Tests\TestHarness.ps1")
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$resultsDir = Join-Path $PSScriptRoot "Test-UpdateCommandsResults"
$scratchRoot = Join-Path $resultsDir "scratch-$stamp"
$logPath = Join-Path $resultsDir "UpdateCommands-$stamp.log"
New-Item -ItemType Directory -Path $scratchRoot -Force | Out-Null
$script:PassCount = 0
$script:FailCount = 0
Initialize-TestHarness -LogPath $logPath -FailFast:$FailFast

try {
  $projectRoot = Join-Path $scratchRoot "project"
  $sourceRoot = Join-Path $scratchRoot "release"
  New-Item -ItemType Directory -Path (Join-Path $projectRoot ".ue-tools"), (Join-Path $sourceRoot "payload") -Force | Out-Null
  $marker = [ordered]@{ schemaVersion=2; mode='global'; version='1.0.1'; bootstrap=[ordered]@{repositoryUrl='https://example.invalid/UEToolSuiteInstaller.git';releaseTag='v1.0.1'} }
  [IO.File]::WriteAllText((Join-Path $projectRoot ".ue-tools\global-cli.json"), (($marker|ConvertTo-Json -Depth 4)+"`n"), [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $sourceRoot "payload\ue-tool-suite.manifest.json"), "{`"payloadVersion`":`"1.0.2`"}`n", [Text.UTF8Encoding]::new($false))
  $fakeInstaller = @'
param([string]$TargetRepoRoot,[switch]$SkipTests)
$path = Join-Path $TargetRepoRoot '.ue-tools\global-cli.json'
$marker = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
$marker.version = '1.0.2'
$marker.bootstrap.releaseTag = 'v1.0.2'
[IO.File]::WriteAllText($path, (($marker | ConvertTo-Json -Depth 4) + "`n"), [Text.UTF8Encoding]::new($false))
'@
  [IO.File]::WriteAllText((Join-Path $sourceRoot "Install-UEToolSuite.ps1"), $fakeInstaller, [Text.UTF8Encoding]::new($false))

  $env:UE_TOOLS_UPDATE_SOURCE_ROOT = $sourceRoot
  Import-Module (Join-Path $repoRoot "payload\Scripts\UETools\UEToolSuite.Update.psm1") -Force
  $status = Get-UEToolSuiteVersionStatus -RepoRoot $projectRoot
  Assert-Condition "version command discovers newer package" ($status.ProjectVersion -eq '1.0.1' -and $status.LatestVersion -eq '1.0.2' -and $status.UpdateAvailable) "1.0.1 -> 1.0.2" "unexpected status"
  $versionOutput = @(Invoke-UEToolSuiteVersionCommand -RepoRoot $projectRoot) -join "`n"
  Assert-TextContains "version output names latest release" $versionOutput "Latest published version: 1.0.2"
  Invoke-UEToolSuiteUpdateCommand -RepoRoot $projectRoot -CommandArguments @('--yes')
  $updated = Get-Content -LiteralPath (Join-Path $projectRoot ".ue-tools\global-cli.json") -Raw | ConvertFrom-Json
  Assert-Condition "explicit update invokes release installer" ([string]$updated.version -eq '1.0.2') "version=1.0.2" "version=$([string]$updated.version)"
  Write-Log ("PASS={0} FAIL={1}" -f $script:PassCount, $script:FailCount) Cyan
  if ($script:FailCount -gt 0) { exit 1 }
}
finally {
  Remove-Item Env:\UE_TOOLS_UPDATE_SOURCE_ROOT -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $scratchRoot) { Remove-Item -LiteralPath $scratchRoot -Recurse -Force }
}
