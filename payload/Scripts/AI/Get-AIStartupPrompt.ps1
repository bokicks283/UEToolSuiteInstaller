[CmdletBinding()]
param(
  [string]$Task,
  [switch]$IncludePrivate,
  [switch]$CopyToClipboard,
  [string]$RepoRoot
)

$ErrorActionPreference = "Stop"

$script:AIToolsScriptsRoot = Split-Path -Parent $PSScriptRoot
$runtimeHelperPath = Join-Path $script:AIToolsScriptsRoot "UETools\UEToolSuite.Runtime.ps1"
if (Test-Path -LiteralPath $runtimeHelperPath -PathType Leaf) {
  . $runtimeHelperPath
}
else {
  throw "Runtime helper not found: $runtimeHelperPath"
}
Set-UEToolSuiteRuntimeContext -ScriptsRoot $script:AIToolsScriptsRoot -StateKey "ai-startup-prompt"

if (-not (Import-UEToolSuiteCoreModule)) {
  throw "UETools module entry not found under $script:AIToolsScriptsRoot\UETools."
}

$aiDomainModulePath = Join-Path $script:AIToolsScriptsRoot "UETools\UEToolSuite.AI.psm1"
if (-not (Test-Path -LiteralPath $aiDomainModulePath -PathType Leaf)) {
  throw "AI domain module not found: $aiDomainModulePath"
}
Import-Module -Name $aiDomainModulePath -Force

function Resolve-RepoRoot {
  param([string]$ExplicitRepoRoot)
  return (Resolve-UEToolSuiteAIRepoRoot -ExplicitRepoRoot $ExplicitRepoRoot -InvocationName "Get-AIStartupPrompt.ps1")
}

function Test-IsExcludedMarkdownPath {
  param([Parameter(Mandatory)][string]$RelativePath)
  return (Test-UEToolSuiteAIExcludedMarkdownPath -RelativePath $RelativePath)
}

function Get-RepoMarkdownPaths {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)
  return @(Get-UEToolSuiteAIRepoMarkdownPaths -ResolvedRepoRoot $ResolvedRepoRoot)
}

function Get-CodingStandardsSnapshotInfo {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)
  return (Get-UEToolSuiteAICodingStandardsSnapshotInfo -ResolvedRepoRoot $ResolvedRepoRoot)
}

$resolvedRepoRoot = Resolve-RepoRoot -ExplicitRepoRoot $RepoRoot
$promptResult = New-UEToolSuiteAIStartupPrompt -ResolvedRepoRoot $resolvedRepoRoot -Task $Task -IncludePrivate:$IncludePrivate
$privateContextPath = $promptResult.PrivateContextPath
$privateContextExists = [bool]$promptResult.PrivateContextExists

if ($IncludePrivate -and -not $privateContextExists) {
  Write-Warning "Private context requested but not found: $privateContextPath"
}

if ($CopyToClipboard -and -not (Get-Command Set-Clipboard -ErrorAction SilentlyContinue)) {
  throw "Set-Clipboard is not available in this PowerShell session."
}

$prompt = [string]$promptResult.Prompt

if ($CopyToClipboard) {
  Set-Clipboard -Value $prompt
  Write-Host "[AI Prompt] Copied startup prompt to clipboard." -ForegroundColor Green
}

Write-Output $prompt
