[CmdletBinding()]
param(
  [string]$RepoRoot,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CommandArgs
)

$ErrorActionPreference = "Stop"
$script:UEToolSuiteCoreModuleImported = $false
$script:UEToolSuiteCoreModuleImportAttempted = $false

function Write-UEToolsError {
  param([Parameter(Mandatory)][string]$Message)

  Write-Host "Error: $Message" -ForegroundColor Red
}

function Get-UEToolSuiteCoreModulePath {
  $manifestPath = Join-Path $PSScriptRoot "UETools\UETools.psd1"
  if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    return $manifestPath
  }

  $modulePath = Join-Path $PSScriptRoot "UETools\UEToolSuite.Core.psm1"
  if (Test-Path -LiteralPath $modulePath -PathType Leaf) {
    return $modulePath
  }

  return $null
}

function Import-UEToolSuiteCoreModule {
  if ($script:UEToolSuiteCoreModuleImported) {
    return $true
  }
  if ($script:UEToolSuiteCoreModuleImportAttempted) {
    return $false
  }

  $script:UEToolSuiteCoreModuleImportAttempted = $true
  $modulePath = Get-UEToolSuiteCoreModulePath
  if ([string]::IsNullOrWhiteSpace($modulePath)) {
    return $false
  }

  Import-Module -Name $modulePath -Force
  $script:UEToolSuiteCoreModuleImported = $true
  return $true
}

function Resolve-UEToolsRepoRoot {
  param([string]$ExplicitRepoRoot)

  if (Import-UEToolSuiteCoreModule) {
    $resolver = Get-Command -Name "Resolve-UEToolSuiteRepoRoot" -ErrorAction SilentlyContinue
    if ($resolver) {
      return (Resolve-UEToolSuiteRepoRoot -ExplicitRepoRoot $ExplicitRepoRoot -InvocationName "ue-tools")
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($ExplicitRepoRoot)) {
    $candidate = [System.IO.Path]::GetFullPath($ExplicitRepoRoot)
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
      throw "RepoRoot does not exist or is not a directory: $candidate"
    }

    return (Resolve-Path -LiteralPath $candidate).Path
  }

  $repoRoot = ((git rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    throw "ue-tools must be run from inside a git repository or passed -RepoRoot."
  }

  return $repoRoot.Trim()
}

if ($MyInvocation.InvocationName -ne '.') {
  try {
    $resolvedRepoRoot = Resolve-UEToolsRepoRoot -ExplicitRepoRoot $RepoRoot
    $helpersPath = Join-Path $resolvedRepoRoot "Scripts\Unreal\ProjectShellAliases.ps1"
    if (-not (Test-Path -LiteralPath $helpersPath -PathType Leaf)) {
      throw "Project shell alias helper not found: $helpersPath"
    }

    . $helpersPath
    Push-Location $resolvedRepoRoot
    try {
      Invoke-UETools @CommandArgs
    }
    finally {
      Pop-Location
    }
  }
  catch {
    Write-UEToolsError -Message $_.Exception.Message
    exit 1
  }
}
