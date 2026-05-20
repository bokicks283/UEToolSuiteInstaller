@{
  RootModule = "UEToolSuite.Core.psm1"
  NestedModules = @(
    "UEToolSuite.Aliases.psm1",
    "UEToolSuite.Unreal.psm1",
    "UEToolSuite.Docs.psm1",
    "UEToolSuite.Art.psm1",
    "UEToolSuite.AI.psm1",
    "UEToolSuite.Init.psm1",
    "UEToolSuite.Git.psm1"
  )
  ModuleVersion = "1.0.0"
  GUID = "7dce18a5-cf40-40f8-8e94-b8fe6b86b4be"
  Author = "UEToolSuiteInstaller"
  CompanyName = "UEToolSuiteInstaller"
  Copyright = "(c) UEToolSuiteInstaller. All rights reserved."
  PowerShellVersion = "5.1"
  FunctionsToExport = @(
    "Get-UEToolSuiteCommandRegistry",
    "Get-UEToolsCommandSpec",
    "Get-ArtToolsCommandSpec",
    "Get-DocsToolsCommandSpec",
    "Get-AIPromptCommandSpec",
    "Get-AIToolsCommandSpec",
    "Get-ProjectAliasBootstrapMarkers",
    "Get-ProjectAliasLegacyMarkers",
    "Get-ProjectAliasDefinitions",
    "Test-ProjectAliasRepoScriptAvailable",
    "Invoke-UETools",
    "Invoke-ArtTools",
    "Invoke-DocsTools",
    "Invoke-AIPrompt",
    "Invoke-AITools",
    "Register-ProjectShellAliases",
    "Install-ProjectShellAliases",
    "Install-UEToolsShellAliases",
    "Install-ArtToolsShellAliases",
    "Install-DocsToolsShellAliases",
    "Install-AIToolsShellAliases",
    "Write-UEToolSuiteUtf8NoBomFile",
    "Resolve-UEToolSuiteRepoRoot",
    "Resolve-UEToolSuiteRepoPath",
    "Get-UEToolSuiteCoreModuleEntryPath"
  )
  CmdletsToExport = @()
  VariablesToExport = @()
  AliasesToExport = @()
}
