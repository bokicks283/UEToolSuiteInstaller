function New-UEToolSuiteCommandDefinition {
  param(
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][string]$Domain,
    [Parameter(Mandatory)][string]$FunctionName,
    [Parameter(Mandatory)][string[]]$Aliases,
    [Parameter(Mandatory)][string]$RequiredRelativePath,
    [string]$Description = ""
  )

  [pscustomobject]@{
    Id                   = $Id
    Domain               = $Domain
    FunctionName         = $FunctionName
    Aliases              = @($Aliases)
    RequiredRelativePath = $RequiredRelativePath
    Description          = $Description
  }
}

function Get-UEToolSuiteCommandRegistry {
  [CmdletBinding()]
  param(
    [string]$ScriptsRoot,
    [switch]$IncludeUnavailable
  )

  $commands = @(
    (New-UEToolSuiteCommandDefinition `
      -Id "ue-tools" `
      -Domain "unreal" `
      -FunctionName "Invoke-UETools" `
      -Aliases @("ue-tools") `
      -RequiredRelativePath "Unreal\UnrealSync.ps1" `
      -Description "Unreal project sync and build wrapper.")

    (New-UEToolSuiteCommandDefinition `
      -Id "art-tools" `
      -Domain "art" `
      -FunctionName "Invoke-ArtTools" `
      -Aliases @("art-tools") `
      -RequiredRelativePath "Unreal\New-ArtSourcePath.ps1" `
      -Description "ArtSource folder creation wrapper.")

    (New-UEToolSuiteCommandDefinition `
      -Id "docs-tools" `
      -Domain "docs" `
      -FunctionName "Invoke-DocsTools" `
      -Aliases @("docs-tools") `
      -RequiredRelativePath "Docs\DocsTools.ps1" `
      -Description "Project documentation automation wrapper.")

    (New-UEToolSuiteCommandDefinition `
      -Id "codex-tools" `
      -Domain "codex" `
      -FunctionName "Invoke-CodexTools" `
      -Aliases @("codex-tools") `
      -RequiredRelativePath "Codex\Get-CodexStartupPrompt.ps1" `
      -Description "Codex helper command wrapper.")

    (New-UEToolSuiteCommandDefinition `
      -Id "codex-prompt" `
      -Domain "codex" `
      -FunctionName "Invoke-CodexPrompt" `
      -Aliases @("codex-prompt") `
      -RequiredRelativePath "Codex\Get-CodexStartupPrompt.ps1" `
      -Description "Codex startup prompt wrapper.")
  )

  if ([string]::IsNullOrWhiteSpace($ScriptsRoot) -or $IncludeUnavailable) {
    return @($commands)
  }

  $resolvedScriptsRoot = [System.IO.Path]::GetFullPath($ScriptsRoot)
  return @(
    $commands | Where-Object {
      Test-Path -LiteralPath (Join-Path $resolvedScriptsRoot $_.RequiredRelativePath) -PathType Leaf
    }
  )
}

function Get-UEToolsCommandSpec {
  [CmdletBinding()]
  param()

  [pscustomobject]@{
    CommandName = "ue-tools"
    DefaultCommand = "help"
    OptionPrefixedDefaultCommand = "build"
    BuildScriptRelativePath = "Scripts\Unreal\UnrealSync.ps1"
    BuildScriptNotFoundPrefix = "UnrealSync script not found"
    HelpLines = @(
      "UE tools wrapper for repository Unreal helpers."
      "Usage:"
      "  ue-tools <command> [options]"
      "Commands:"
      "  help                 Show this help text."
      "  build [sync options] Run Scripts\Unreal\UnrealSync.ps1 with -Force."
      "Examples:"
      "  ue-tools help"
      "  ue-tools build -DryRun"
      "  ue-tools build -NoBuild -Config Debug"
      "Notes:"
      "  - If the first argument starts with '-' or '/', 'build' is assumed."
      "  - Additional commands can be added under this command group later."
    )
    BuildHelpLines = @(
      "Usage: ue-tools build [UnrealSync.ps1 options]"
      "Examples:"
      "  ue-tools build -DryRun"
      "  ue-tools build -NoBuild -NoRegen"
      "  ue-tools build -Config Debug -Platform Win64"
      "Notes:"
      "  - Wrapper always passes -Force to UnrealSync.ps1."
    )
  }
}

Export-ModuleMember -Function Get-UEToolSuiteCommandRegistry, Get-UEToolsCommandSpec
