[CmdletBinding()]
param(
  [string]$RepoRoot,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CommandArgs
)

$ErrorActionPreference = "Stop"

function Write-UEToolSuiteEntrypointError {
  param([Parameter(Mandatory)][string]$Message)
  Write-Host "Error: $Message" -ForegroundColor Red
}

if ($MyInvocation.InvocationName -ne '.') {
  try {
    $modulesToImport = @(
      "UEToolSuite.Core.psm1",
      "UEToolSuite.Settings.psm1",
      "UEToolSuite.Unreal.psm1",
      "UEToolSuite.Docs.psm1",
      "UEToolSuite.Art.psm1",
      "UEToolSuite.AI.psm1",
      "UEToolSuite.Init.psm1",
      "UEToolSuite.Git.psm1",
      "UEToolSuite.Dispatcher.psm1"
    ) | ForEach-Object { Join-Path (Join-Path $PSScriptRoot "UETools") $_ }

    foreach ($modulePath in $modulesToImport) {
      if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        throw "Required module not found: $modulePath"
      }

      Import-Module -Name $modulePath -Force -DisableNameChecking
    }

    Set-UEToolSuiteRuntimeContext -ScriptsRoot $PSScriptRoot -StateKey "ue-tools-dispatcher"

    $resolvedRepoRoot = Resolve-UEToolSuiteRepoRoot `
      -ExplicitRepoRoot $RepoRoot `
      -InvocationName "ue-tools"

    Push-Location $resolvedRepoRoot
    try {
      Invoke-UEToolSuiteDispatcher -RepoRoot $resolvedRepoRoot -CommandArguments $CommandArgs
    }
    finally {
      Pop-Location
    }
  }
  catch {
    Write-UEToolSuiteEntrypointError -Message $_.Exception.Message
    exit 1
  }
}
