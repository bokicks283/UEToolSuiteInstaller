[CmdletBinding()]
param(
  [string]$RepoRoot,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$CommandArgs
)

$ErrorActionPreference = "Stop"

$scriptsRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$entrypoint = Join-Path $scriptsRoot "ue-tools.ps1"
if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {
  throw "ue-tools entrypoint not found: $entrypoint"
}

& $entrypoint -RepoRoot $RepoRoot @CommandArgs
exit $LASTEXITCODE
