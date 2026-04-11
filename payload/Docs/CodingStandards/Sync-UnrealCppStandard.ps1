[CmdletBinding()]
param(
  [string]$SourceUrl = "https://dev.epicgames.com/documentation/en-us/unreal-engine/epic-cplusplus-coding-standard-for-unreal-engine"
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$currentRoot = Join-Path $scriptRoot "Current"
$pagePath = Join-Path $currentRoot "page.html"
$sourceTemplatePath = Join-Path $scriptRoot "Templates/SOURCE.template.md"
$sourceOutPath = Join-Path $currentRoot "SOURCE.md"

New-Item -ItemType Directory -Path $currentRoot -Force | Out-Null

Write-Host "[CodingStandards] Downloading: $SourceUrl"
Invoke-WebRequest -Uri $SourceUrl -OutFile $pagePath

if (Test-Path $sourceTemplatePath) {
  Copy-Item -Path $sourceTemplatePath -Destination $sourceOutPath -Force
}

Write-Host "[CodingStandards] Current snapshot refreshed:"
Write-Host "  $currentRoot"
Write-Host "[CodingStandards] This replaces the previous local snapshot in place."
Write-Host "[CodingStandards] Next:"
Write-Host "  1) Fill SOURCE.md"
Write-Host "  2) Run Parse-UnrealCppStandard.ps1"
Write-Host "  3) Review Docs/CodingStandards/UnrealCppStandard.md"
Write-Host "  4) Commit the refreshed current snapshot and docs page in docs-only scope"
