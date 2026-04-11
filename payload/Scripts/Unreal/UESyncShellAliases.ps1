$projectAliasHelpers = Join-Path $PSScriptRoot "ProjectShellAliases.ps1"
if (-not (Test-Path -LiteralPath $projectAliasHelpers)) {
  throw "Project shell alias helpers not found: $projectAliasHelpers"
}

. $projectAliasHelpers
