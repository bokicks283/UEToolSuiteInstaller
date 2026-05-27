@{
  RootModule = "UEToolSuite.Core.psm1"
  NestedModules = @(
    "UEToolSuite.Aliases.psm1",
    "UEToolSuite.Dispatcher.psm1",
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
  FunctionsToExport = "*"
  CmdletsToExport = @()
  VariablesToExport = @()
  AliasesToExport = @()
}
