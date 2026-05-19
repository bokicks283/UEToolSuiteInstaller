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

function Get-ArtToolsCommandSpec {
  [CmdletBinding()]
  param()

  [pscustomobject]@{
    CommandName = "art-tools"
    ScriptRelativePath = "Scripts\Unreal\New-ArtSourcePath.ps1"
    ScriptNotFoundPrefix = "ArtSource path script not found"
    HelpLines = @(
      "Art tools wrapper for ArtSource helpers."
      "Usage:"
      "  art-tools [New-ArtSourcePath.ps1 options]"
      "Examples:"
      "  art-tools"
      "  art-tools -RepoRoot C:\Path\To\Repo"
      "Notes:"
      "  - Runs Scripts\Unreal\New-ArtSourcePath.ps1."
    )
  }
}

function Get-DocsToolsCommandSpec {
  [CmdletBinding()]
  param()

  [pscustomobject]@{
    CommandName = "docs-tools"
    ScriptRelativePath = "Scripts\Docs\DocsTools.ps1"
    ScriptNotFoundPrefix = "Docs tools script not found"
  }
}

function Get-CodexPromptCommandSpec {
  [CmdletBinding()]
  param()

  [pscustomobject]@{
    CommandName = "codex-prompt"
    ScriptRelativePath = "Scripts\Codex\Get-CodexStartupPrompt.ps1"
    ScriptNotFoundPrefix = "Codex startup prompt script not found"
    HelpLines = @(
      "Codex startup prompt builder for this repository."
      "Usage:"
      "  codex-prompt [-Task <text>] [-IncludePrivate] [-CopyToClipboard]"
      "Examples:"
      "  codex-prompt"
      "  codex-prompt -Task `"Fix UnrealSync regeneration tests`""
      "  codex-prompt -Task `"Review Coding Standards docs`" -IncludePrivate -CopyToClipboard"
      "Notes:"
      "  - Runs Scripts\Codex\Get-CodexStartupPrompt.ps1."
    )
  }
}

function Get-CodexToolsCommandSpec {
  [CmdletBinding()]
  param()

  [pscustomobject]@{
    CommandName = "codex-tools"
    DefaultCommand = "help"
    OptionPrefixedDefaultCommand = "prompt"
    PromptSubcommandName = "prompt"
    HelpLines = @(
      "Codex tools wrapper for repository Codex helpers."
      "Usage:"
      "  codex-tools <command> [options]"
      "Commands:"
      "  help                   Show this help text."
      "  prompt [prompt args]   Run Scripts\Codex\Get-CodexStartupPrompt.ps1."
      "Examples:"
      "  codex-tools help"
      "  codex-tools prompt -Task `"Fix hook docs`""
      "  codex-tools prompt -IncludePrivate -CopyToClipboard"
      "Notes:"
      "  - If the first argument starts with '-' or '/', 'prompt' is assumed."
    )
  }
}

function Write-UEToolSuiteUtf8NoBomFile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
    [switch]$EnsureParentDirectory
  )

  if ($EnsureParentDirectory) {
    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
      New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
  }

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Resolve-UEToolSuiteRepoRoot {
  [CmdletBinding()]
  param(
    [string]$ExplicitRepoRoot,
    [string]$InvocationName = "Command"
  )

  if (-not [string]::IsNullOrWhiteSpace($ExplicitRepoRoot)) {
    $candidate = [System.IO.Path]::GetFullPath($ExplicitRepoRoot)
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
      throw "RepoRoot does not exist or is not a directory: $candidate"
    }

    return (Resolve-Path -LiteralPath $candidate).Path
  }

  $repoRoot = ((git rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    throw "$InvocationName must be run from inside a git repository or passed -RepoRoot."
  }

  return $repoRoot.Trim()
}

function Resolve-UEToolSuiteRepoPath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$NotFoundMessagePrefix,
    [ValidateSet("Any", "Leaf", "Container")][string]$PathType = "Any"
  )

  $path = Join-Path $RepoRoot $RelativePath
  $exists = switch ($PathType) {
    "Leaf" { Test-Path -LiteralPath $path -PathType Leaf }
    "Container" { Test-Path -LiteralPath $path -PathType Container }
    default { Test-Path -LiteralPath $path }
  }

  if (-not $exists) {
    throw "${NotFoundMessagePrefix}: $path"
  }

  return $path
}

function Get-UEToolSuiteCoreModuleEntryPath {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$ScriptsRoot)

  $manifestPath = Join-Path $ScriptsRoot "UETools\UETools.psd1"
  if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    return $manifestPath
  }

  $modulePath = Join-Path $ScriptsRoot "UETools\UEToolSuite.Core.psm1"
  if (Test-Path -LiteralPath $modulePath -PathType Leaf) {
    return $modulePath
  }

  return $null
}

Export-ModuleMember -Function `
  Get-UEToolSuiteCommandRegistry, `
  Get-UEToolsCommandSpec, `
  Get-ArtToolsCommandSpec, `
  Get-DocsToolsCommandSpec, `
  Get-CodexPromptCommandSpec, `
  Get-CodexToolsCommandSpec, `
  Write-UEToolSuiteUtf8NoBomFile, `
  Resolve-UEToolSuiteRepoRoot, `
  Resolve-UEToolSuiteRepoPath, `
  Get-UEToolSuiteCoreModuleEntryPath
