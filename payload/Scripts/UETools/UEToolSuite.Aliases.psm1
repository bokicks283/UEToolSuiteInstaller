$ErrorActionPreference = "Stop"

$script:UEToolSuiteAliasesModuleLoadContext = $true
try {
  $helperPath = Join-Path (Split-Path -Parent $PSScriptRoot) "Unreal\ProjectShellAliases.ps1"
  if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    throw "Project shell alias helper not found: $helperPath"
  }

  . $helperPath
}
finally {
  $script:UEToolSuiteAliasesModuleLoadContext = $false
}
