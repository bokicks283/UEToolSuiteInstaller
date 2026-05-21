[CmdletBinding()]
param(
  [string]$RepoRoot,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CommandArgs
)

$ErrorActionPreference = "Stop"

$runtimeHelperPath = Join-Path $PSScriptRoot "UETools\UEToolSuite.Runtime.ps1"
if (Test-Path -LiteralPath $runtimeHelperPath -PathType Leaf) {
  . $runtimeHelperPath
}
else {
  throw "Runtime helper not found: $runtimeHelperPath"
}
Set-UEToolSuiteRuntimeContext -ScriptsRoot $PSScriptRoot -StateKey "ue-tools"

function Write-UEToolsError {
  param([Parameter(Mandatory)][string]$Message)

  Write-Host "Error: $Message" -ForegroundColor Red
}

function Resolve-UEToolsRepoRoot {
  param([string]$ExplicitRepoRoot)

  $runtimeResolver = Get-Command -Name "Resolve-UEToolSuiteRuntimeRepoRoot" -ErrorAction SilentlyContinue
  if ($runtimeResolver) {
    return (Resolve-UEToolSuiteRuntimeRepoRoot -ScriptsRoot $PSScriptRoot -ExplicitRepoRoot $ExplicitRepoRoot -InvocationName "ue-tools")
  }

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
