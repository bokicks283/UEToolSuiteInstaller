$script:ProjectShellAliasesScriptPath = if ($PSCommandPath) {
  [System.IO.Path]::GetFullPath($PSCommandPath)
}
else {
  $null
}

function Write-Utf8NoBomFile {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content
  )

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
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
    Write-Utf8NoBomFile -Path $ProfilePath -Content $updated
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

  Write-Utf8NoBomFile -Path $ProfilePath -Content $updated
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

function Get-ProjectAliasDefinitions {
  # Add new alias groups here by mapping alias name(s) to an existing function.
  $definitions = New-Object System.Collections.Generic.List[object]

  [void]$definitions.Add([pscustomobject]@{
      Id = "ue-tools"
      FunctionName = "Invoke-UETools"
      Aliases = @("ue-tools")
    })

  if (Test-ProjectAliasRepoScriptAvailable -RelativePath "New-ArtSourcePath.ps1") {
    [void]$definitions.Add([pscustomobject]@{
        Id = "art-tools"
        FunctionName = "Invoke-ArtTools"
        Aliases = @("art-tools")
      })
  }

  if (Test-ProjectAliasRepoScriptAvailable -RelativePath "..\Docs\DocsTools.ps1") {
    [void]$definitions.Add([pscustomobject]@{
        Id = "docs-tools"
        FunctionName = "Invoke-DocsTools"
        Aliases = @("docs-tools")
      })
  }

  if (Test-ProjectAliasRepoScriptAvailable -RelativePath "..\Codex\Get-CodexStartupPrompt.ps1") {
    [void]$definitions.Add([pscustomobject]@{
        Id = "codex-tools"
        FunctionName = "Invoke-CodexTools"
        Aliases = @("codex-tools")
      })

    [void]$definitions.Add([pscustomobject]@{
        Id = "codex-prompt"
        FunctionName = "Invoke-CodexPrompt"
        Aliases = @("codex-prompt")
      })
  }

  return @($definitions.ToArray())
}

function Get-RepoRootOrThrow {
  param([Parameter(Mandatory)][string]$InvokerName)

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

  $scriptPath = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "${NotFoundMessagePrefix}: $scriptPath"
  }

  return $scriptPath
}

function Invoke-UETools {
  $helpTokens = @("help", "--help", "-help", "-h", "/?", "-?")
  $argsList = @($args)

  function Test-HelpToken([object]$Value) {
    if ($null -eq $Value) { return $false }
    $token = ([string]$Value).ToLowerInvariant()
    return ($helpTokens -contains $token)
  }

  function Show-UEToolsHelp {
    @(
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
    ) | Write-Output
  }

  function Show-UEToolsBuildHelp {
    @(
      "Usage: ue-tools build [UnrealSync.ps1 options]"
      "Examples:"
      "  ue-tools build -DryRun"
      "  ue-tools build -NoBuild -NoRegen"
      "  ue-tools build -Config Debug -Platform Win64"
      "Notes:"
      "  - Wrapper always passes -Force to UnrealSync.ps1."
    ) | Write-Output
  }

  $command = "help"
  $commandArgs = @()

  if ($argsList.Count -gt 0) {
    $first = [string]$argsList[0]
    if (Test-HelpToken $first) {
      $command = "help"
      if ($argsList.Count -gt 1) {
        $commandArgs = @($argsList[1..($argsList.Count - 1)])
      }
    }
    elseif ($first.StartsWith("-") -or $first.StartsWith("/")) {
      $command = "build"
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
        if (Test-HelpToken $arg) {
          Show-UEToolsBuildHelp
          return
        }
      }

      $repoRoot = Get-RepoRootOrThrow -InvokerName "Invoke-UETools"
      $syncScript = Resolve-RepoScriptOrThrow `
        -RepoRoot $repoRoot `
        -RelativePath "Scripts\Unreal\UnrealSync.ps1" `
        -NotFoundMessagePrefix "UnrealSync script not found"

      & $syncScript -RepoRoot $repoRoot -Force @commandArgs
      return
    }
    default {
      throw "Unknown ue-tools command '$command'. Run 'ue-tools help'."
    }
  }
}

function Invoke-ArtTools {
  $helpTokens = @("help", "--help", "-help", "-h", "/?", "-?")
  $argsList = @($args)

  foreach ($arg in $argsList) {
    if ($helpTokens -contains ([string]$arg).ToLowerInvariant()) {
      @(
        "Art tools wrapper for ArtSource helpers."
        "Usage:"
        "  art-tools [New-ArtSourcePath.ps1 options]"
        "Examples:"
        "  art-tools"
        "  art-tools -RepoRoot C:\Path\To\Repo"
        "Notes:"
        "  - Runs Scripts\Unreal\New-ArtSourcePath.ps1."
      ) | Write-Output
      return
    }
  }

  $repoRoot = Get-RepoRootOrThrow -InvokerName "Invoke-ArtTools"
  $artScript = Resolve-RepoScriptOrThrow `
    -RepoRoot $repoRoot `
    -RelativePath "Scripts\Unreal\New-ArtSourcePath.ps1" `
    -NotFoundMessagePrefix "ArtSource path script not found"

  & $artScript @argsList
}

function Invoke-DocsTools {
  $argsList = @($args)

  $repoRoot = Get-RepoRootOrThrow -InvokerName "Invoke-DocsTools"
  $docsScript = Resolve-RepoScriptOrThrow `
    -RepoRoot $repoRoot `
    -RelativePath "Scripts\Docs\DocsTools.ps1" `
    -NotFoundMessagePrefix "Docs tools script not found"

  & {
    . $docsScript
    try {
      $resolvedRepoRoot = Get-DocsToolsRepoRoot -ExplicitRepoRoot $repoRoot
      $normalizedDocsArgs = Get-NormalizedArgumentList -Values $argsList
      Invoke-DocsToolsMain -ResolvedRepoRoot $resolvedRepoRoot -CommandArguments $normalizedDocsArgs
    }
    catch {
      Write-DocsToolsError -Message $_.Exception.Message
    }
  }
}

function Show-CodexPromptHelp {
  @(
    "Codex startup prompt builder for this repository."
    "Usage:"
    "  codex-prompt [-Task <text>] [-IncludePrivate] [-CopyToClipboard]"
    "Examples:"
    "  codex-prompt"
    "  codex-prompt -Task `"Fix UnrealSync regeneration tests`""
    "  codex-prompt -Task `"Review Coding Standards docs`" -IncludePrivate -CopyToClipboard"
    "Notes:"
    "  - Runs Scripts\Codex\Get-CodexStartupPrompt.ps1."
  ) | Write-Output
}

function Invoke-CodexPrompt {
  $helpTokens = @("help", "--help", "-help", "-h", "/?", "-?")
  $argsList = @($args)

  foreach ($arg in $argsList) {
    if ($helpTokens -contains ([string]$arg).ToLowerInvariant()) {
      Show-CodexPromptHelp
      return
    }
  }

  $repoRoot = Get-RepoRootOrThrow -InvokerName "Invoke-CodexPrompt"
  $promptScript = Resolve-RepoScriptOrThrow `
    -RepoRoot $repoRoot `
    -RelativePath "Scripts\Codex\Get-CodexStartupPrompt.ps1" `
    -NotFoundMessagePrefix "Codex startup prompt script not found"

  & $promptScript @argsList
}

function Invoke-CodexTools {
  $helpTokens = @("help", "--help", "-help", "-h", "/?", "-?")
  $argsList = @($args)

  function Test-HelpToken([object]$Value) {
    if ($null -eq $Value) { return $false }
    $token = ([string]$Value).ToLowerInvariant()
    return ($helpTokens -contains $token)
  }

  function Show-CodexToolsHelp {
    @(
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
    ) | Write-Output
  }

  $command = "help"
  $commandArgs = @()

  if ($argsList.Count -gt 0) {
    $first = [string]$argsList[0]
    if (Test-HelpToken $first) {
      $command = "help"
      if ($argsList.Count -gt 1) {
        $commandArgs = @($argsList[1..($argsList.Count - 1)])
      }
    }
    elseif ($first.StartsWith("-") -or $first.StartsWith("/")) {
      $command = "prompt"
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
      Show-CodexToolsHelp
      return
    }
    "prompt" {
      foreach ($arg in $commandArgs) {
        if (Test-HelpToken $arg) {
          Show-CodexPromptHelp
          return
        }
      }

      Invoke-CodexPrompt @commandArgs
      return
    }
    default {
      throw "Unknown codex-tools command '$command'. Run 'codex-tools help'."
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

function Get-ProjectShellAliasBootstrapSnippet {
  param([Parameter(Mandatory)][string]$AliasScriptPath)

  $escapedPath = $AliasScriptPath.Replace("'", "''")
@"
`$projectAliasScriptPath = '$escapedPath'
if (Test-Path -LiteralPath `$projectAliasScriptPath) {
  . `$projectAliasScriptPath
  Register-ProjectShellAliases | Out-Null
}
else {
  Write-Warning "UE project alias script not found: `$projectAliasScriptPath"
}
"@
}

function Install-ProjectShellAliases {
  param(
    [string]$ProfilePath,
    [string]$AliasScriptPath
  )

  $resolvedProfilePath = Resolve-ProfilePathForAliases -ProfilePath $ProfilePath
  $resolvedAliasScriptPath = Resolve-ProjectAliasScriptPath -AliasScriptPath $AliasScriptPath
  $markers = Get-ProjectAliasBootstrapMarkers
  $snippet = Get-ProjectShellAliasBootstrapSnippet -AliasScriptPath $resolvedAliasScriptPath

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

  $registered = Register-ProjectShellAliases

  [pscustomobject]@{
    ProfilePath = $resolvedProfilePath
    AliasScriptPath = $resolvedAliasScriptPath
    StartMarker = $markers.StartMarker
    EndMarker = $markers.EndMarker
    AliasGroups = $registered.AliasGroups
    Aliases = $registered.Aliases
  }
}

function Install-UEToolsShellAliases {
  param(
    [string]$ProfilePath,
    [string]$AliasScriptPath
  )

  $result = Install-ProjectShellAliases -ProfilePath $ProfilePath -AliasScriptPath $AliasScriptPath
  $group = @($result.AliasGroups | Where-Object { $_.Id -eq "ue-tools" } | Select-Object -First 1)

  [pscustomobject]@{
    ProfilePath = $result.ProfilePath
    AliasScriptPath = $result.AliasScriptPath
    FunctionName = if ($group.Count -gt 0) { $group[0].FunctionName } else { "Invoke-UETools" }
    Aliases = if ($group.Count -gt 0) { @($group[0].Aliases) } else { @("ue-tools") }
    StartMarker = $result.StartMarker
    EndMarker = $result.EndMarker
  }
}

function Install-ArtToolsShellAliases {
  param(
    [string]$ProfilePath,
    [string]$AliasScriptPath
  )

  $result = Install-ProjectShellAliases -ProfilePath $ProfilePath -AliasScriptPath $AliasScriptPath
  $group = @($result.AliasGroups | Where-Object { $_.Id -eq "art-tools" } | Select-Object -First 1)

  [pscustomobject]@{
    ProfilePath = $result.ProfilePath
    AliasScriptPath = $result.AliasScriptPath
    FunctionName = if ($group.Count -gt 0) { $group[0].FunctionName } else { $null }
    Aliases = if ($group.Count -gt 0) { @($group[0].Aliases) } else { @() }
    StartMarker = $result.StartMarker
    EndMarker = $result.EndMarker
  }
}

function Install-DocsToolsShellAliases {
  param(
    [string]$ProfilePath,
    [string]$AliasScriptPath
  )

  $result = Install-ProjectShellAliases -ProfilePath $ProfilePath -AliasScriptPath $AliasScriptPath
  $group = @($result.AliasGroups | Where-Object { $_.Id -eq "docs-tools" } | Select-Object -First 1)

  [pscustomobject]@{
    ProfilePath = $result.ProfilePath
    AliasScriptPath = $result.AliasScriptPath
    FunctionName = if ($group.Count -gt 0) { $group[0].FunctionName } else { $null }
    Aliases = if ($group.Count -gt 0) { @($group[0].Aliases) } else { @() }
    StartMarker = $result.StartMarker
    EndMarker = $result.EndMarker
  }
}

function Install-CodexToolsShellAliases {
  param(
    [string]$ProfilePath,
    [string]$AliasScriptPath
  )

  $result = Install-ProjectShellAliases -ProfilePath $ProfilePath -AliasScriptPath $AliasScriptPath
  $group = @($result.AliasGroups | Where-Object { $_.Id -eq "codex-tools" } | Select-Object -First 1)

  [pscustomobject]@{
    ProfilePath = $result.ProfilePath
    AliasScriptPath = $result.AliasScriptPath
    FunctionName = if ($group.Count -gt 0) { $group[0].FunctionName } else { $null }
    Aliases = if ($group.Count -gt 0) { @($group[0].Aliases) } else { @() }
    StartMarker = $result.StartMarker
    EndMarker = $result.EndMarker
  }
}
