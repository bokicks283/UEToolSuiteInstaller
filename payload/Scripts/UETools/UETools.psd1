@{
  RootModule = "UEToolSuite.Core.psm1"
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
    "Get-CodexPromptCommandSpec",
    "Get-CodexToolsCommandSpec",
    "Write-UEToolSuiteUtf8NoBomFile",
    "Resolve-UEToolSuiteRepoRoot",
    "Resolve-UEToolSuiteRepoPath",
    "Get-UEToolSuiteCoreModuleEntryPath"
  )
  CmdletsToExport = @()
  VariablesToExport = @()
  AliasesToExport = @()
}
