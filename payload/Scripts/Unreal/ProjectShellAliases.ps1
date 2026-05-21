$ErrorActionPreference = "Stop"

$scriptsRoot = Split-Path -Parent $PSScriptRoot
$aliasesModulePath = Join-Path $scriptsRoot "UETools\UEToolSuite.Aliases.psm1"
$facadeManifestPath = Join-Path $scriptsRoot "UETools\UETools.psd1"

if (-not $script:UEToolSuiteAliasesModuleLoadContext) {
  if (Test-Path -LiteralPath $aliasesModulePath -PathType Leaf) {
    Import-Module -Name $aliasesModulePath -Force
    return
  }

  if (Test-Path -LiteralPath $facadeManifestPath -PathType Leaf) {
    Import-Module -Name $facadeManifestPath -Force
    if (Get-Command -Name "Get-ProjectAliasDefinitions" -ErrorAction SilentlyContinue) {
      return
    }
  }
}

# Runtime-backed fallback for copied helper scenarios where UETools modules are not present.
$script:ProjectShellAliasesScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) "Unreal\ProjectShellAliases.ps1"
if (-not (Test-Path -LiteralPath $script:ProjectShellAliasesScriptPath -PathType Leaf)) {
  $script:ProjectShellAliasesScriptPath = if ($PSCommandPath) {
    [System.IO.Path]::GetFullPath($PSCommandPath)
  }
  else {
    $null
  }
}
$runtimeHelperPath = Join-Path (Split-Path -Parent $PSScriptRoot) "UETools\UEToolSuite.Runtime.ps1"
if (Test-Path -LiteralPath $runtimeHelperPath -PathType Leaf) {
  . $runtimeHelperPath
}
else {
  throw "Runtime helper not found: $runtimeHelperPath"
}

function Remove-ProfileSnippet {
  param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [Parameter(Mandatory)][string]$StartMarker,
    [Parameter(Mandatory)][string]$EndMarker
  )

  if (-not (Test-Path -LiteralPath $ProfilePath)) {
    return
  }

  $existing = Get-Content -LiteralPath $ProfilePath -Raw
  $pattern = "(?s)$([regex]::Escape($StartMarker)).*?$([regex]::Escape($EndMarker))"
  $updated = [regex]::Replace($existing, $pattern, "")

  if ($updated -cne $existing) {
    Write-Utf8NoBomFile -ScriptsRoot (Get-ProjectAliasScriptsRoot) -Path $ProfilePath -Content $updated
  }
}

function Set-ProfileSnippet {
  param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [Parameter(Mandatory)][string]$StartMarker,
    [Parameter(Mandatory)][string]$EndMarker,
    [Parameter(Mandatory)][string]$SnippetBody
  )

  $profileDir = Split-Path -Parent $ProfilePath
  if ($profileDir -and -not (Test-Path -LiteralPath $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
  }

  $existing = ""
  if (Test-Path -LiteralPath $ProfilePath) {
    $existing = Get-Content -LiteralPath $ProfilePath -Raw
  }

  $snippet = @(
    $StartMarker
    $SnippetBody.TrimEnd()
    $EndMarker
  ) -join "`r`n"

  $updated = $existing
  $pattern = "(?s)$([regex]::Escape($StartMarker)).*?$([regex]::Escape($EndMarker))"
  $regex = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

  if ($regex.IsMatch($existing)) {
    $updated = $regex.Replace(
      $existing,
      [System.Text.RegularExpressions.MatchEvaluator] { param($m) $snippet },
      1
    )
  }
  else {
    if ($updated -and -not $updated.EndsWith("`n")) {
      $updated += "`r`n"
    }
    if ($updated) {
      $updated += "`r`n"
    }
    $updated += $snippet + "`r`n"
  }

  Write-Utf8NoBomFile -ScriptsRoot (Get-ProjectAliasScriptsRoot) -Path $ProfilePath -Content $updated
}

function Resolve-ProfilePathForAliases {
  param([string]$ProfilePath)

  if (-not $ProfilePath) {
    $ProfilePath = $PROFILE.CurrentUserAllHosts
  }
  if (-not $ProfilePath) {
    $ProfilePath = [string]$PROFILE
  }
  if (-not $ProfilePath) {
    throw "Could not resolve a PowerShell profile path for alias installation."
  }

  return $ProfilePath
}

function Resolve-ProjectAliasScriptPath {
  param([string]$AliasScriptPath)

  $candidate = $AliasScriptPath
  if ([string]::IsNullOrWhiteSpace($candidate)) {
    $candidate = $script:ProjectShellAliasesScriptPath
  }

  if ([string]::IsNullOrWhiteSpace($candidate)) {
    throw "Could not resolve ProjectShellAliases.ps1 path. Pass -AliasScriptPath explicitly."
  }

  if (-not [System.IO.Path]::IsPathRooted($candidate)) {
    $candidate = [System.IO.Path]::GetFullPath($candidate)
  }

  if (-not (Test-Path -LiteralPath $candidate)) {
    throw "Alias script path does not exist: $candidate"
  }

  return (Resolve-Path -LiteralPath $candidate).Path
}

function Get-ProjectAliasScriptDirectory {
  $resolvedScriptPath = Resolve-ProjectAliasScriptPath
  return (Split-Path -Path $resolvedScriptPath -Parent)
}

function Get-ProjectAliasScriptsRoot {
  $scriptDir = Get-ProjectAliasScriptDirectory
  return (Split-Path -Path $scriptDir -Parent)
}

function Get-ProjectAliasCoreImportContext {
  $scriptsRoot = Get-ProjectAliasScriptsRoot
  return [pscustomobject]@{
    ScriptsRoot = $scriptsRoot
    StateKey = ("project-shell-aliases::{0}" -f $scriptsRoot.ToLowerInvariant())
  }
}

function Get-ProjectAliasDefinitionsFromRegistry {
  $context = Get-ProjectAliasCoreImportContext
  if (-not (Import-UEToolSuiteCoreModule -ScriptsRoot $context.ScriptsRoot -StateKey $context.StateKey)) {
    return @()
  }

  return @(Get-UEToolSuiteCommandRegistry -ScriptsRoot $context.ScriptsRoot)
}

function Get-ProjectAliasCommandSpecFromRegistry {
  param([Parameter(Mandatory)][string]$SpecFunctionName)

  $context = Get-ProjectAliasCoreImportContext
  if (-not (Import-UEToolSuiteCoreModule -ScriptsRoot $context.ScriptsRoot -StateKey $context.StateKey)) {
    return $null
  }

  $specCommand = Get-Command -Name $SpecFunctionName -ErrorAction SilentlyContinue
  if (-not $specCommand) {
    return $null
  }

  return (& $SpecFunctionName)
}

function Get-UEToolsCommandSpecFromRegistry {
  return (Get-ProjectAliasCommandSpecFromRegistry -SpecFunctionName "Get-UEToolsCommandSpec")
}

function Get-ArtToolsCommandSpecFromRegistry {
  return (Get-ProjectAliasCommandSpecFromRegistry -SpecFunctionName "Get-ArtToolsCommandSpec")
}

function Get-DocsToolsCommandSpecFromRegistry {
  return (Get-ProjectAliasCommandSpecFromRegistry -SpecFunctionName "Get-DocsToolsCommandSpec")
}

function Get-AIPromptCommandSpecFromRegistry {
  $spec = Get-ProjectAliasCommandSpecFromRegistry -SpecFunctionName "Get-AIPromptCommandSpec"
  if ($null -ne $spec) { return $spec }
  return $null
}

function Get-AIToolsCommandSpecFromRegistry {
  $spec = Get-ProjectAliasCommandSpecFromRegistry -SpecFunctionName "Get-AIToolsCommandSpec"
  if ($null -ne $spec) { return $spec }
  return $null
}

function New-FallbackUEToolsCommandSpec {
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

function New-FallbackArtToolsCommandSpec {
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

function New-FallbackDocsToolsCommandSpec {
  [pscustomobject]@{
    CommandName = "docs-tools"
    ScriptRelativePath = "Scripts\Docs\DocsTools.ps1"
    ScriptNotFoundPrefix = "Docs tools script not found"
  }
}

function New-FallbackAIPromptCommandSpec {
  [pscustomobject]@{
    CommandName = "ai-prompt"
    ScriptRelativePath = "Scripts\AI\Get-AIStartupPrompt.ps1"
    ScriptNotFoundPrefix = "AI startup prompt script not found"
    HelpLines = @(
      "AI startup prompt builder for this repository."
      "Usage:"
      "  ai-prompt [-Task <text>] [-IncludePrivate] [-CopyToClipboard]"
      "Examples:"
      "  ai-prompt"
      "  ai-prompt -Task `"Fix UnrealSync regeneration tests`""
      "  ai-prompt -Task `"Review Coding Standards docs`" -IncludePrivate -CopyToClipboard"
      "Notes:"
      "  - Runs Scripts\AI\Get-AIStartupPrompt.ps1."
    )
  }
}

function New-FallbackAIToolsCommandSpec {
  [pscustomobject]@{
    CommandName = "ai-tools"
    DefaultCommand = "help"
    OptionPrefixedDefaultCommand = "prompt"
    PromptSubcommandName = "prompt"
    HelpLines = @(
      "AI tools wrapper for repository AI helpers."
      "Usage:"
      "  ai-tools <command> [options]"
      "Commands:"
      "  help                   Show this help text."
      "  prompt [prompt args]   Run Scripts\AI\Get-AIStartupPrompt.ps1."
      "Examples:"
      "  ai-tools help"
      "  ai-tools prompt -Task `"Fix hook docs`""
      "  ai-tools prompt -IncludePrivate -CopyToClipboard"
      "Notes:"
      "  - If the first argument starts with '-' or '/', 'prompt' is assumed."
    )
  }
}

function Get-ResolvedUEToolsCommandSpec {
  $spec = Get-UEToolsCommandSpecFromRegistry
  if ($null -ne $spec) { return $spec }
  return (New-FallbackUEToolsCommandSpec)
}

function Get-ResolvedArtToolsCommandSpec {
  $spec = Get-ArtToolsCommandSpecFromRegistry
  if ($null -ne $spec) { return $spec }
  return (New-FallbackArtToolsCommandSpec)
}

function Get-ResolvedDocsToolsCommandSpec {
  $spec = Get-DocsToolsCommandSpecFromRegistry
  if ($null -ne $spec) { return $spec }
  return (New-FallbackDocsToolsCommandSpec)
}

function Get-ResolvedAIPromptCommandSpec {
  $spec = Get-AIPromptCommandSpecFromRegistry
  if ($null -ne $spec) { return $spec }
  return (New-FallbackAIPromptCommandSpec)
}

function Get-ResolvedAIToolsCommandSpec {
  $spec = Get-AIToolsCommandSpecFromRegistry
  if ($null -ne $spec) { return $spec }
  return (New-FallbackAIToolsCommandSpec)
}

function Test-ProjectAliasRepoScriptAvailable {
  param([Parameter(Mandatory)][string]$RelativePath)

  $scriptDir = Get-ProjectAliasScriptDirectory
  $candidate = Join-Path $scriptDir $RelativePath
  return (Test-Path -LiteralPath $candidate)
}

function Get-ProjectAliasBootstrapMarkers {
  [pscustomobject]@{
    StartMarker = "# >>> ue project shell aliases >>>"
    EndMarker = "# <<< ue project shell aliases <<<"
  }
}

function Get-ProjectAliasLegacyMarkers {
  @(
    [pscustomobject]@{
      StartMarker = "# >>> ue-sync aliases >>>"
      EndMarker = "# <<< ue-sync aliases <<<"
    },
    [pscustomobject]@{
      StartMarker = "# >>> ue-tools aliases >>>"
      EndMarker = "# <<< ue-tools aliases <<<"
    },
    [pscustomobject]@{
      StartMarker = "# >>> art-tools aliases >>>"
      EndMarker = "# <<< art-tools aliases <<<"
    },
    [pscustomobject]@{
      StartMarker = "# >>> docs-tools aliases >>>"
      EndMarker = "# <<< docs-tools aliases <<<"
    }
  )
}

function Get-ProjectAliasFallbackRegistry {
  return @(
    [pscustomobject]@{
      Id = "ue-tools"
      FunctionName = "Invoke-UETools"
      Aliases = @("ue-tools")
      RequiredRelativePath = "Unreal\UnrealSync.ps1"
    },
    [pscustomobject]@{
      Id = "art-tools"
      FunctionName = "Invoke-ArtTools"
      Aliases = @("art-tools")
      RequiredRelativePath = "Unreal\New-ArtSourcePath.ps1"
    },
    [pscustomobject]@{
      Id = "docs-tools"
      FunctionName = "Invoke-DocsTools"
      Aliases = @("docs-tools")
      RequiredRelativePath = "Docs\DocsTools.ps1"
    },
    [pscustomobject]@{
      Id = "ai-tools"
      FunctionName = "Invoke-AITools"
      Aliases = @("ai-tools")
      RequiredRelativePath = "AI\Get-AIStartupPrompt.ps1"
    },
    [pscustomobject]@{
      Id = "ai-prompt"
      FunctionName = "Invoke-AIPrompt"
      Aliases = @("ai-prompt")
      RequiredRelativePath = "AI\Get-AIStartupPrompt.ps1"
    }
  )
}

function Test-ProjectAliasFallbackDefinitionAvailable {
  param([Parameter(Mandatory)]$Definition)

  $scriptsRoot = Get-ProjectAliasScriptsRoot
  $candidate = Join-Path $scriptsRoot $Definition.RequiredRelativePath
  return (Test-Path -LiteralPath $candidate -PathType Leaf)
}

function Get-ProjectAliasDefinitions {
  $registryDefinitions = @(Get-ProjectAliasDefinitionsFromRegistry)
  if ($registryDefinitions.Count -gt 0) {
    return @(
      $registryDefinitions | ForEach-Object {
        [pscustomobject]@{
          Id = $_.Id
          FunctionName = $_.FunctionName
          Aliases = @($_.Aliases)
        }
      }
    )
  }

  # Fallback for older installed suites that do not have the shared registry module.
  $definitions = New-Object System.Collections.Generic.List[object]

  foreach ($definition in @(Get-ProjectAliasFallbackRegistry)) {
    if (-not (Test-ProjectAliasFallbackDefinitionAvailable -Definition $definition)) {
      continue
    }

    [void]$definitions.Add([pscustomobject]@{
        Id = $definition.Id
        FunctionName = $definition.FunctionName
        Aliases = @($definition.Aliases)
      })
  }

  return @($definitions.ToArray())
}

function Get-RepoRootOrThrow {
  param([Parameter(Mandatory)][string]$InvokerName)

  $context = Get-ProjectAliasCoreImportContext
  $runtimeResolver = Get-Command -Name "Resolve-UEToolSuiteRuntimeRepoRoot" -ErrorAction SilentlyContinue
  if ($runtimeResolver) {
    return (Resolve-UEToolSuiteRuntimeRepoRoot -ScriptsRoot $context.ScriptsRoot -InvocationName $InvokerName)
  }

  if (Import-UEToolSuiteCoreModule -ScriptsRoot $context.ScriptsRoot -StateKey $context.StateKey) {
    $resolver = Get-Command -Name "Resolve-UEToolSuiteRepoRoot" -ErrorAction SilentlyContinue
    if ($resolver) {
      return (Resolve-UEToolSuiteRepoRoot -InvocationName $InvokerName)
    }
  }

  $repoRoot = ((git rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    throw "$InvokerName must be run from inside a git repository."
  }

  return $repoRoot.Trim()
}

function Resolve-RepoScriptOrThrow {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$NotFoundMessagePrefix
  )

  $context = Get-ProjectAliasCoreImportContext
  if (Import-UEToolSuiteCoreModule -ScriptsRoot $context.ScriptsRoot -StateKey $context.StateKey) {
    $resolver = Get-Command -Name "Resolve-UEToolSuiteRepoPath" -ErrorAction SilentlyContinue
    if ($resolver) {
      return (Resolve-UEToolSuiteRepoPath -RepoRoot $RepoRoot -RelativePath $RelativePath -NotFoundMessagePrefix $NotFoundMessagePrefix -PathType Leaf)
    }
  }

  $runtimeResolver = Get-Command -Name "Resolve-UEToolSuiteRuntimeRepoPath" -ErrorAction SilentlyContinue
  if ($runtimeResolver) {
    return (Resolve-UEToolSuiteRuntimeRepoPath -ScriptsRoot $context.ScriptsRoot -RepoRoot $RepoRoot -RelativePath $RelativePath -NotFoundMessagePrefix $NotFoundMessagePrefix -PathType Leaf)
  }

  $scriptPath = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "${NotFoundMessagePrefix}: $scriptPath"
  }

  return $scriptPath
}

function Test-ProjectAliasHelpToken {
  param([object]$Value)

  if ($null -eq $Value) { return $false }
  $token = ([string]$Value).ToLowerInvariant()
  return @("help", "--help", "-help", "-h", "/?", "-?") -contains $token
}

function Resolve-ProjectCommandScriptContext {
  param(
    [Parameter(Mandatory)][string]$InvokerName,
    [Parameter(Mandatory)][string]$ScriptRelativePath,
    [Parameter(Mandatory)][string]$ScriptNotFoundPrefix
  )

  $repoRoot = Get-RepoRootOrThrow -InvokerName $InvokerName
  $scriptPath = Resolve-RepoScriptOrThrow `
    -RepoRoot $repoRoot `
    -RelativePath $ScriptRelativePath `
    -NotFoundMessagePrefix $ScriptNotFoundPrefix

  return [pscustomobject]@{
    RepoRoot = $repoRoot
    ScriptPath = $scriptPath
  }
}

function Invoke-ProjectCommandScript {
  param(
    [Parameter(Mandatory)][string]$InvokerName,
    [Parameter(Mandatory)][string]$ScriptRelativePath,
    [Parameter(Mandatory)][string]$ScriptNotFoundPrefix,
    [object[]]$ScriptArguments = @()
  )

  $context = Resolve-ProjectCommandScriptContext `
    -InvokerName $InvokerName `
    -ScriptRelativePath $ScriptRelativePath `
    -ScriptNotFoundPrefix $ScriptNotFoundPrefix

  & $context.ScriptPath @ScriptArguments
}

function Invoke-UETools {
  $argsList = @($args)
  $spec = Get-ResolvedUEToolsCommandSpec

  function Show-UEToolsHelp {
    @($spec.HelpLines) | Write-Output
  }

  function Show-UEToolsBuildHelp {
    @($spec.BuildHelpLines) | Write-Output
  }

  $command = [string]$spec.DefaultCommand
  $commandArgs = @()

  if ($argsList.Count -gt 0) {
    $first = [string]$argsList[0]
    if (Test-ProjectAliasHelpToken $first) {
      $command = [string]$spec.DefaultCommand
      if ($argsList.Count -gt 1) {
        $commandArgs = @($argsList[1..($argsList.Count - 1)])
      }
    }
    elseif ($first.StartsWith("-") -or $first.StartsWith("/")) {
      $command = [string]$spec.OptionPrefixedDefaultCommand
      $commandArgs = $argsList
    }
    else {
      $command = $first.ToLowerInvariant()
      if ($argsList.Count -gt 1) {
        $commandArgs = @($argsList[1..($argsList.Count - 1)])
      }
    }
  }

  switch ($command) {
    "help" {
      Show-UEToolsHelp
      return
    }
    "build" {
      foreach ($arg in $commandArgs) {
        if (Test-ProjectAliasHelpToken $arg) {
          Show-UEToolsBuildHelp
          return
        }
      }

      $context = Resolve-ProjectCommandScriptContext `
        -InvokerName "Invoke-UETools" `
        -ScriptRelativePath $spec.BuildScriptRelativePath `
        -ScriptNotFoundPrefix $spec.BuildScriptNotFoundPrefix

      & $context.ScriptPath -RepoRoot $context.RepoRoot -Force @commandArgs
      return
    }
    default {
      throw "Unknown ue-tools command '$command'. Run 'ue-tools help'."
    }
  }
}

function Invoke-ArtTools {
  $argsList = @($args)
  $spec = Get-ResolvedArtToolsCommandSpec

  foreach ($arg in $argsList) {
    if (Test-ProjectAliasHelpToken $arg) {
      @($spec.HelpLines) | Write-Output
      return
    }
  }

  Invoke-ProjectCommandScript `
    -InvokerName "Invoke-ArtTools" `
    -ScriptRelativePath $spec.ScriptRelativePath `
    -ScriptNotFoundPrefix $spec.ScriptNotFoundPrefix `
    -ScriptArguments $argsList
}

function Invoke-DocsTools {
  $argsList = @($args)
  $spec = Get-ResolvedDocsToolsCommandSpec
  $context = Resolve-ProjectCommandScriptContext `
    -InvokerName "Invoke-DocsTools" `
    -ScriptRelativePath $spec.ScriptRelativePath `
    -ScriptNotFoundPrefix $spec.ScriptNotFoundPrefix

  & {
    . $context.ScriptPath
    try {
      $resolvedRepoRoot = Get-DocsToolsRepoRoot -ExplicitRepoRoot $context.RepoRoot
      $normalizedDocsArgs = Get-NormalizedArgumentList -Values $argsList
      Invoke-DocsToolsMain -ResolvedRepoRoot $resolvedRepoRoot -CommandArguments $normalizedDocsArgs
    }
    catch {
      Write-DocsToolsError -Message $_.Exception.Message
    }
  }
}

function Show-AIPromptHelp {
  $spec = Get-ResolvedAIPromptCommandSpec

  @($spec.HelpLines) | Write-Output
}

function Invoke-AIPrompt {
  $argsList = @($args)
  $spec = Get-ResolvedAIPromptCommandSpec

  foreach ($arg in $argsList) {
    if (Test-ProjectAliasHelpToken $arg) {
      Show-AIPromptHelp
      return
    }
  }

  Invoke-ProjectCommandScript `
    -InvokerName "Invoke-AIPrompt" `
    -ScriptRelativePath $spec.ScriptRelativePath `
    -ScriptNotFoundPrefix $spec.ScriptNotFoundPrefix `
    -ScriptArguments $argsList
}

function Invoke-AITools {
  $argsList = @($args)
  $spec = Get-ResolvedAIToolsCommandSpec

  function Show-AIToolsHelp {
    @($spec.HelpLines) | Write-Output
  }

  $command = [string]$spec.DefaultCommand
  $commandArgs = @()

  if ($argsList.Count -gt 0) {
    $first = [string]$argsList[0]
    if (Test-ProjectAliasHelpToken $first) {
      $command = [string]$spec.DefaultCommand
      if ($argsList.Count -gt 1) {
        $commandArgs = @($argsList[1..($argsList.Count - 1)])
      }
    }
    elseif ($first.StartsWith("-") -or $first.StartsWith("/")) {
      $command = [string]$spec.OptionPrefixedDefaultCommand
      $commandArgs = $argsList
    }
    else {
      $command = $first.ToLowerInvariant()
      if ($argsList.Count -gt 1) {
        $commandArgs = @($argsList[1..($argsList.Count - 1)])
      }
    }
  }

  switch ($command) {
    "help" {
      Show-AIToolsHelp
      return
    }
    ([string]$spec.PromptSubcommandName) {
      foreach ($arg in $commandArgs) {
        if (Test-ProjectAliasHelpToken $arg) {
          Show-AIPromptHelp
          return
        }
      }

      Invoke-AIPrompt @commandArgs
      return
    }
    default {
      throw "Unknown ai-tools command '$command'. Run 'ai-tools help'."
    }
  }
}

function Register-ProjectShellAliases {
  $definitions = Get-ProjectAliasDefinitions
  $groups = @()

  foreach ($definition in $definitions) {
    if (-not (Get-Command $definition.FunctionName -ErrorAction SilentlyContinue)) {
      throw "Alias target function not found: $($definition.FunctionName)"
    }

    foreach ($aliasName in @($definition.Aliases)) {
      Set-Alias -Name $aliasName -Value $definition.FunctionName -Scope Global -Force
    }

    $groups += [pscustomobject]@{
      Id = $definition.Id
      FunctionName = $definition.FunctionName
      Aliases = @($definition.Aliases)
    }
  }

  $allAliases = @()
  foreach ($group in $groups) {
    $allAliases += @($group.Aliases)
  }

  [pscustomobject]@{
    AliasGroups = $groups
    Aliases = @($allAliases | Sort-Object -Unique)
  }
}

function ConvertTo-SingleQuotedPowerShellLiteral {
  param([Parameter(Mandatory)][string]$Value)

  return "'" + $Value.Replace("'", "''") + "'"
}

function Get-DefaultProjectAliasBootstrapScriptPath {
  $localAppData = $env:LOCALAPPDATA
  if ([string]::IsNullOrWhiteSpace($localAppData)) {
    $localAppData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
  }
  if ([string]::IsNullOrWhiteSpace($localAppData)) {
    throw "Could not resolve LOCALAPPDATA for UE tool suite shell bootstrap."
  }

  return (Join-Path $localAppData "UEToolSuite\Shell\UEToolsBootstrap.ps1")
}

function Resolve-ProjectAliasBootstrapScriptPath {
  param([string]$BootstrapScriptPath)

  $candidate = $BootstrapScriptPath
  if ([string]::IsNullOrWhiteSpace($candidate)) {
    $candidate = Get-DefaultProjectAliasBootstrapScriptPath
  }

  if (-not [System.IO.Path]::IsPathRooted($candidate)) {
    $candidate = [System.IO.Path]::GetFullPath($candidate)
  }

  return $candidate
}

function Get-ProjectShellAliasBootstrapScriptContent {
  param([Parameter(Mandatory)][object[]]$AliasGroups)

  $aliasMappings = New-Object System.Collections.Generic.List[object]
  foreach ($group in @($AliasGroups)) {
    foreach ($aliasName in @($group.Aliases)) {
      [void]$aliasMappings.Add([pscustomobject]@{
          AliasName = [string]$aliasName
          FunctionName = [string]$group.FunctionName
        })
    }
  }

  $dedupedMappings = @($aliasMappings | Group-Object AliasName | ForEach-Object { $_.Group[0] } | Sort-Object AliasName)
  $lines = New-Object System.Collections.Generic.List[string]
  [void]$lines.Add('$ErrorActionPreference = "Stop"')
  [void]$lines.Add("")
  [void]$lines.Add("function Resolve-UEToolSuiteCurrentRepoRoot {")
  [void]$lines.Add('  $repoRoot = ((git rev-parse --show-toplevel 2>$null) | Select-Object -First 1)')
  [void]$lines.Add('  if ([string]::IsNullOrWhiteSpace($repoRoot)) {')
  [void]$lines.Add('    throw "UE tool aliases must be run from inside a git repository."')
  [void]$lines.Add('  }')
  [void]$lines.Add("")
  [void]$lines.Add('  return $repoRoot.Trim()')
  [void]$lines.Add("}")
  [void]$lines.Add("")
  [void]$lines.Add("function Invoke-UEToolSuiteRepoAliasCommand {")
  [void]$lines.Add("  param(")
  [void]$lines.Add("    [Parameter(Mandatory)][string]`$FunctionName,")
  [void]$lines.Add("    [string[]]`$CommandArgs = @()")
  [void]$lines.Add("  )")
  [void]$lines.Add("")
  [void]$lines.Add("  `$repoRoot = Resolve-UEToolSuiteCurrentRepoRoot")
  [void]$lines.Add("  `$helperPath = Join-Path `$repoRoot 'Scripts\Unreal\ProjectShellAliases.ps1'")
  [void]$lines.Add("  if (-not (Test-Path -LiteralPath `$helperPath -PathType Leaf)) {")
  [void]$lines.Add('    throw "UE project alias helper not found: `$helperPath"')
  [void]$lines.Add("  }")
  [void]$lines.Add("")
  [void]$lines.Add("  . `$helperPath")
  [void]$lines.Add("  if (-not (Get-Command -Name `$FunctionName -ErrorAction SilentlyContinue)) {")
  [void]$lines.Add('    throw "Alias target function not found in `$helperPath: `$FunctionName"')
  [void]$lines.Add("  }")
  [void]$lines.Add("")
  [void]$lines.Add("  function Convert-UEToolSuiteCommandToken {")
  [void]$lines.Add("    param([AllowNull()][AllowEmptyString()][string]`$Value)")
  [void]$lines.Add("")
  [void]$lines.Add("    if (`$null -eq `$Value) { return ""''"" }")
  [void]$lines.Add("    if (`$Value.Length -eq 0) { return ""''"" }")
  [void]$lines.Add("    if (`$Value -match '^-{1,2}[A-Za-z0-9][A-Za-z0-9-]*$') { return `$Value }")
  [void]$lines.Add("    if (`$Value -match '^/[A-Za-z0-9][A-Za-z0-9-]*$') { return `$Value }")
  [void]$lines.Add("    if (`$Value -match '^[A-Za-z0-9_./:\\-]+$') { return `$Value }")
  [void]$lines.Add("")
  [void]$lines.Add('    return "''" + $Value.Replace("''", "''''") + "''"')
  [void]$lines.Add("  }")
  [void]$lines.Add("")
  [void]$lines.Add("  `$quotedArgs = @()")
  [void]$lines.Add("  foreach (`$commandArg in @(`$CommandArgs)) {")
  [void]$lines.Add("    `$quotedArgs += Convert-UEToolSuiteCommandToken -Value ([string]`$commandArg)")
  [void]$lines.Add("  }")
  [void]$lines.Add("")
  [void]$lines.Add("  `$commandText = `$FunctionName")
  [void]$lines.Add("  if (`$quotedArgs.Count -gt 0) {")
  [void]$lines.Add("    `$commandText += ' ' + (`$quotedArgs -join ' ')")
  [void]$lines.Add("  }")
  [void]$lines.Add("")
  [void]$lines.Add("  Invoke-Expression `$commandText")
  [void]$lines.Add("}")
  [void]$lines.Add("")

  foreach ($mapping in $dedupedMappings) {
    $wrapperName = "Invoke-UEToolSuiteAlias_" + ([string]$mapping.AliasName -replace "[^A-Za-z0-9_]", "_")
    $functionNameLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value ([string]$mapping.FunctionName)
    $aliasNameLiteral = ConvertTo-SingleQuotedPowerShellLiteral -Value ([string]$mapping.AliasName)

    [void]$lines.Add("function $wrapperName {")
    [void]$lines.Add("  param(")
    [void]$lines.Add("    [Parameter(ValueFromRemainingArguments = `$true)]")
    [void]$lines.Add("    [string[]]`$CommandArgs")
    [void]$lines.Add("  )")
    [void]$lines.Add("  Invoke-UEToolSuiteRepoAliasCommand -FunctionName $functionNameLiteral -CommandArgs `$CommandArgs")
    [void]$lines.Add("}")
    [void]$lines.Add("Set-Alias -Name $aliasNameLiteral -Value $wrapperName -Scope Global -Force")
    [void]$lines.Add("")
  }

  return ($lines -join "`r`n")
}

function Get-ProjectShellAliasBootstrapSnippet {
  param([Parameter(Mandatory)][string]$BootstrapScriptPath)

  $escapedPath = $BootstrapScriptPath.Replace("'", "''")
@"
`$ueToolSuiteBootstrapPath = '$escapedPath'
if (Test-Path -LiteralPath `$ueToolSuiteBootstrapPath) {
  . `$ueToolSuiteBootstrapPath
}
else {
  Write-Warning "UE tool suite bootstrap script not found: `$ueToolSuiteBootstrapPath"
}
"@
}

function Install-ProjectShellAliases {
  param(
    [string]$ProfilePath,
    [string]$AliasScriptPath,
    [string]$BootstrapScriptPath
  )

  $resolvedProfilePath = Resolve-ProfilePathForAliases -ProfilePath $ProfilePath
  $resolvedAliasScriptPath = Resolve-ProjectAliasScriptPath -AliasScriptPath $AliasScriptPath
  $resolvedBootstrapScriptPath = Resolve-ProjectAliasBootstrapScriptPath -BootstrapScriptPath $BootstrapScriptPath
  $registered = Register-ProjectShellAliases
  $bootstrapContent = Get-ProjectShellAliasBootstrapScriptContent -AliasGroups $registered.AliasGroups
  $bootstrapParent = Split-Path -Path $resolvedBootstrapScriptPath -Parent
  if ($bootstrapParent -and -not (Test-Path -LiteralPath $bootstrapParent)) {
    New-Item -ItemType Directory -Path $bootstrapParent -Force | Out-Null
  }

  $existingBootstrap = ""
  if (Test-Path -LiteralPath $resolvedBootstrapScriptPath -PathType Leaf) {
    $existingBootstrap = Get-Content -LiteralPath $resolvedBootstrapScriptPath -Raw
  }
  if ($existingBootstrap -cne $bootstrapContent) {
    Write-Utf8NoBomFile -ScriptsRoot (Get-ProjectAliasScriptsRoot) -Path $resolvedBootstrapScriptPath -Content $bootstrapContent
  }

  $markers = Get-ProjectAliasBootstrapMarkers
  $snippet = Get-ProjectShellAliasBootstrapSnippet -BootstrapScriptPath $resolvedBootstrapScriptPath

  foreach ($legacy in @(Get-ProjectAliasLegacyMarkers)) {
    Remove-ProfileSnippet `
      -ProfilePath $resolvedProfilePath `
      -StartMarker $legacy.StartMarker `
      -EndMarker $legacy.EndMarker
  }

  Set-ProfileSnippet `
    -ProfilePath $resolvedProfilePath `
    -StartMarker $markers.StartMarker `
    -EndMarker $markers.EndMarker `
    -SnippetBody $snippet

  [pscustomobject]@{
    ProfilePath = $resolvedProfilePath
    AliasScriptPath = $resolvedAliasScriptPath
    BootstrapScriptPath = $resolvedBootstrapScriptPath
    StartMarker = $markers.StartMarker
    EndMarker = $markers.EndMarker
    AliasGroups = $registered.AliasGroups
    Aliases = $registered.Aliases
  }
}

function Install-UEToolsShellAliases {
  param(
    [string]$ProfilePath,
    [string]$AliasScriptPath,
    [string]$BootstrapScriptPath
  )

  $result = Install-ProjectShellAliases -ProfilePath $ProfilePath -AliasScriptPath $AliasScriptPath -BootstrapScriptPath $BootstrapScriptPath
  $group = @($result.AliasGroups | Where-Object { $_.Id -eq "ue-tools" } | Select-Object -First 1)

  [pscustomobject]@{
    ProfilePath = $result.ProfilePath
    AliasScriptPath = $result.AliasScriptPath
    BootstrapScriptPath = $result.BootstrapScriptPath
    FunctionName = if ($group.Count -gt 0) { $group[0].FunctionName } else { "Invoke-UETools" }
    Aliases = if ($group.Count -gt 0) { @($group[0].Aliases) } else { @("ue-tools") }
    StartMarker = $result.StartMarker
    EndMarker = $result.EndMarker
  }
}

function Install-ArtToolsShellAliases {
  param(
    [string]$ProfilePath,
    [string]$AliasScriptPath,
    [string]$BootstrapScriptPath
  )

  $result = Install-ProjectShellAliases -ProfilePath $ProfilePath -AliasScriptPath $AliasScriptPath -BootstrapScriptPath $BootstrapScriptPath
  $group = @($result.AliasGroups | Where-Object { $_.Id -eq "art-tools" } | Select-Object -First 1)

  [pscustomobject]@{
    ProfilePath = $result.ProfilePath
    AliasScriptPath = $result.AliasScriptPath
    BootstrapScriptPath = $result.BootstrapScriptPath
    FunctionName = if ($group.Count -gt 0) { $group[0].FunctionName } else { $null }
    Aliases = if ($group.Count -gt 0) { @($group[0].Aliases) } else { @() }
    StartMarker = $result.StartMarker
    EndMarker = $result.EndMarker
  }
}

function Install-DocsToolsShellAliases {
  param(
    [string]$ProfilePath,
    [string]$AliasScriptPath,
    [string]$BootstrapScriptPath
  )

  $result = Install-ProjectShellAliases -ProfilePath $ProfilePath -AliasScriptPath $AliasScriptPath -BootstrapScriptPath $BootstrapScriptPath
  $group = @($result.AliasGroups | Where-Object { $_.Id -eq "docs-tools" } | Select-Object -First 1)

  [pscustomobject]@{
    ProfilePath = $result.ProfilePath
    AliasScriptPath = $result.AliasScriptPath
    BootstrapScriptPath = $result.BootstrapScriptPath
    FunctionName = if ($group.Count -gt 0) { $group[0].FunctionName } else { $null }
    Aliases = if ($group.Count -gt 0) { @($group[0].Aliases) } else { @() }
    StartMarker = $result.StartMarker
    EndMarker = $result.EndMarker
  }
}

function Install-AIToolsShellAliases {
  param(
    [string]$ProfilePath,
    [string]$AliasScriptPath,
    [string]$BootstrapScriptPath
  )

  $result = Install-ProjectShellAliases -ProfilePath $ProfilePath -AliasScriptPath $AliasScriptPath -BootstrapScriptPath $BootstrapScriptPath
  $group = @($result.AliasGroups | Where-Object { $_.Id -eq "ai-tools" } | Select-Object -First 1)

  [pscustomobject]@{
    ProfilePath = $result.ProfilePath
    AliasScriptPath = $result.AliasScriptPath
    BootstrapScriptPath = $result.BootstrapScriptPath
    FunctionName = if ($group.Count -gt 0) { $group[0].FunctionName } else { $null }
    Aliases = if ($group.Count -gt 0) { @($group[0].Aliases) } else { @() }
    StartMarker = $result.StartMarker
    EndMarker = $result.EndMarker
  }
}
