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

Export-ModuleMember -Function Get-UEToolSuiteCommandRegistry
