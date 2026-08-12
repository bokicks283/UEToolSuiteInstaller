$ErrorActionPreference = "Stop"

if (-not (Get-Command -Name "Write-UEToolSuiteUtf8NoBomFile" -ErrorAction SilentlyContinue)) {
  $coreModulePath = Join-Path $PSScriptRoot "UEToolSuite.Core.psm1"
  if (Test-Path -LiteralPath $coreModulePath -PathType Leaf) {
    Import-Module -Name $coreModulePath -Force
  }
}

function Get-ProjectAliasBootstrapMarkers {
  [CmdletBinding()]
  param()

  return [pscustomobject]@{
    Start = "#region ue project shell aliases"
    End = "#endregion"
    LegacyStart = "# >>> ue project shell aliases >>>"
    LegacyEnd = "# <<< ue project shell aliases <<<"
  }
}

function Resolve-ProfilePathForAliases {
  [CmdletBinding()]
  param([string]$ProfilePath)

  if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    $ProfilePath = $PROFILE.CurrentUserAllHosts
  }
  if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    $ProfilePath = [string]$PROFILE
  }
  if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    throw "Could not resolve a PowerShell profile path for alias installation."
  }

  return $ProfilePath
}

function Resolve-UEToolSuiteAliasScriptsRoot {
  [CmdletBinding()]
  param([string]$AliasScriptPath)

  if (-not [string]::IsNullOrWhiteSpace($AliasScriptPath)) {
    $candidatePath = $AliasScriptPath
    if (-not [System.IO.Path]::IsPathRooted($candidatePath)) {
      $candidatePath = [System.IO.Path]::GetFullPath($candidatePath)
    }

    if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
      return (Split-Path -Path $candidatePath -Parent)
    }

    if (Test-Path -LiteralPath $candidatePath -PathType Container) {
      return (Resolve-Path -LiteralPath $candidatePath).Path
    }
  }

  return (Split-Path -Parent $PSScriptRoot)
}

function Remove-ProfileSnippet {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [Parameter(Mandatory)][string]$StartMarker,
    [Parameter(Mandatory)][string]$EndMarker
  )

  if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
    return
  }

  $existing = Get-Content -LiteralPath $ProfilePath -Raw
  $pattern = "(?s)$([regex]::Escape($StartMarker)).*?$([regex]::Escape($EndMarker))"
  $updated = [regex]::Replace($existing, $pattern, "")
  if ($updated -ceq $existing) {
    return
  }

  Write-UEToolSuiteUtf8NoBomFile -Path $ProfilePath -Content $updated
}

function Set-ProfileSnippet {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [Parameter(Mandatory)][string]$StartMarker,
    [Parameter(Mandatory)][string]$EndMarker,
    [Parameter(Mandatory)][string]$SnippetBody
  )

  $profileDirectory = Split-Path -Parent $ProfilePath
  if ($profileDirectory -and -not (Test-Path -LiteralPath $profileDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
  }

  $existing = ""
  if (Test-Path -LiteralPath $ProfilePath -PathType Leaf) {
    $existing = Get-Content -LiteralPath $ProfilePath -Raw
  }

  $snippet = @(
    $StartMarker
    $SnippetBody.TrimEnd()
    $EndMarker
  ) -join "`r`n"

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
    $updated = $existing
    if ($updated -and -not $updated.EndsWith("`n")) {
      $updated += "`r`n"
    }
    if ($updated) {
      $updated += "`r`n"
    }
    $updated += $snippet + "`r`n"
  }

  Write-UEToolSuiteUtf8NoBomFile -Path $ProfilePath -Content $updated -EnsureParentDirectory
}

function Get-ProjectShellAliasBootstrapSnippet {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$BootstrapScriptPath)

  $escapedBootstrapPath = $BootstrapScriptPath.Replace("'", "''")
  return @"
`$bootstrapPath = '$escapedBootstrapPath'
function Initialize-UEToolsShell {
  if (Get-Command -Name "Invoke-UEToolSuiteShellCommand" -CommandType Function -ErrorAction SilentlyContinue) {
    return
  }

  if (-not (Test-Path -LiteralPath `$bootstrapPath -PathType Leaf)) {
    throw "UE Tool Suite bootstrap script not found: `$bootstrapPath. Re-run 'ue-tools init' in this repository to reinstall shell aliases."
  }

  . `$bootstrapPath

  if (-not (Get-Command -Name "Invoke-UEToolSuiteShellCommand" -CommandType Function -ErrorAction SilentlyContinue)) {
    throw "UE Tool Suite bootstrap did not register Invoke-UEToolSuiteShellCommand. Re-run 'ue-tools init' to repair shell aliases."
  }
}

function Invoke-UEToolsLazyShellCommand {
  [CmdletBinding(PositionalBinding = `$false)]
  param(
    [string]`$RepoRoot,
    [Parameter(ValueFromRemainingArguments = `$true)]
    [string[]]`$CommandArgs
  )

  Initialize-UEToolsShell
  & Invoke-UEToolSuiteShellCommand -RepoRoot `$RepoRoot @CommandArgs
}

Set-Alias -Name "ue-tools" -Value "Invoke-UEToolsLazyShellCommand" -Scope Global
Set-Alias -Name "ue" -Value "Invoke-UEToolsLazyShellCommand" -Scope Global
"@
}

function Get-DefaultProjectAliasBootstrapScriptPath {
  [CmdletBinding()]
  param()

  $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
  if ([string]::IsNullOrWhiteSpace($localAppData)) {
    throw "Could not resolve LOCALAPPDATA for bootstrap script installation."
  }

  return (Join-Path $localAppData "UEToolSuite\Shell\UEToolsBootstrap.ps1")
}

function Resolve-ProjectAliasBootstrapScriptPath {
  [CmdletBinding()]
  param([string]$BootstrapScriptPath)

  if ([string]::IsNullOrWhiteSpace($BootstrapScriptPath)) {
    return (Get-DefaultProjectAliasBootstrapScriptPath)
  }

  return $BootstrapScriptPath
}

function ConvertTo-SingleQuotedPowerShellLiteral {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Value)

  return ("'{0}'" -f $Value.Replace("'", "''"))
}

function Get-ProjectShellAliasBootstrapScriptContent {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$ScriptsRoot)

  $escapedScriptsRoot = ConvertTo-SingleQuotedPowerShellLiteral -Value $ScriptsRoot
  return @"
# Auto-generated by UEToolSuite alias installer.
# Resolves the active git repo at command time and routes to that repo's dispatcher.

function global:Resolve-UEToolSuiteAliasRepoRoot {
  param([string]`$ExplicitRepoRoot)

  if (-not [string]::IsNullOrWhiteSpace(`$ExplicitRepoRoot)) {
    `$candidate = [System.IO.Path]::GetFullPath(`$ExplicitRepoRoot)
    if (-not (Test-Path -LiteralPath `$candidate -PathType Container)) {
      throw "RepoRoot does not exist or is not a directory: `$candidate"
    }
    return (Resolve-Path -LiteralPath `$candidate).Path
  }

  `$repoRoot = ((git rev-parse --show-toplevel 2>`$null) | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace(`$repoRoot)) {
    throw "Command must be run from inside a git repository or passed -RepoRoot."
  }

  return `$repoRoot.Trim()
}

function global:Invoke-UEToolSuiteShellCommand {
  [CmdletBinding(PositionalBinding = `$false)]
  param(
    [string]`$RepoRoot,
    [Parameter(ValueFromRemainingArguments = `$true)]
    [string[]]`$CommandArgs
  )

  `$resolvedRepoRoot = Resolve-UEToolSuiteAliasRepoRoot -ExplicitRepoRoot `$RepoRoot
  `$entrypoint = Join-Path `$resolvedRepoRoot "Scripts\ue-tools.ps1"
  if (-not (Test-Path -LiteralPath `$entrypoint -PathType Leaf)) {
    throw "UE Tool Suite entrypoint not found: `$entrypoint"
  }

  & `$entrypoint -RepoRoot `$resolvedRepoRoot @CommandArgs
}

if (Get-Command -Name "ue-tools" -ErrorAction SilentlyContinue) {
  Remove-Item -LiteralPath Alias:\ue-tools -ErrorAction SilentlyContinue
}
if (Get-Command -Name "ue" -ErrorAction SilentlyContinue) {
  Remove-Item -LiteralPath Alias:\ue -ErrorAction SilentlyContinue
}

Set-Alias -Name "ue-tools" -Value "Invoke-UEToolSuiteShellCommand" -Scope Global
Set-Alias -Name "ue" -Value "Invoke-UEToolSuiteShellCommand" -Scope Global

`$global:UEToolSuiteAliasBootstrapScriptsRoot = $escapedScriptsRoot
"@
}

function Register-ProjectShellAliases {
  [CmdletBinding()]
  param(
    [string]$AliasScriptPath,
    [string]$ScriptsRoot
  )

  $resolvedScriptsRoot = if (-not [string]::IsNullOrWhiteSpace($ScriptsRoot)) {
    [System.IO.Path]::GetFullPath($ScriptsRoot)
  }
  else {
    Resolve-UEToolSuiteAliasScriptsRoot -AliasScriptPath $AliasScriptPath
  }

  $bootstrapScript = [scriptblock]::Create((Get-ProjectShellAliasBootstrapScriptContent -ScriptsRoot $resolvedScriptsRoot))
  & $bootstrapScript

  $definitions = @(
    [pscustomobject]@{
      Id = "ue-tools"
      FunctionName = "Invoke-UEToolSuiteShellCommand"
      Aliases = @("ue-tools")
      RequiredRelativePath = "Scripts\ue-tools.ps1"
    },
    [pscustomobject]@{
      Id = "ue"
      FunctionName = "Invoke-UEToolSuiteShellCommand"
      Aliases = @("ue")
      RequiredRelativePath = "Scripts\ue-tools.ps1"
    }
  )

  return [pscustomobject]@{
    FunctionName = "Invoke-UEToolSuiteShellCommand"
    Aliases = @("ue-tools", "ue")
    AliasGroups = @(
      [pscustomobject]@{
        FunctionName = "Invoke-UEToolSuiteShellCommand"
        Aliases = @("ue-tools", "ue")
      }
    )
    Definitions = $definitions
    ScriptsRoot = $resolvedScriptsRoot
  }
}

function Install-ProjectShellAliases {
  [CmdletBinding()]
  param(
    [string]$ProfilePath,
    [string]$AliasScriptPath,
    [string]$BootstrapScriptPath,
    [string]$ScriptsRoot
  )

  $resolvedProfilePath = Resolve-ProfilePathForAliases -ProfilePath $ProfilePath
  $resolvedScriptsRoot = if (-not [string]::IsNullOrWhiteSpace($ScriptsRoot)) {
    [System.IO.Path]::GetFullPath($ScriptsRoot)
  }
  else {
    Resolve-UEToolSuiteAliasScriptsRoot -AliasScriptPath $AliasScriptPath
  }

  $resolvedBootstrapScriptPath = Resolve-ProjectAliasBootstrapScriptPath -BootstrapScriptPath $BootstrapScriptPath
  $bootstrapContent = Get-ProjectShellAliasBootstrapScriptContent -ScriptsRoot $resolvedScriptsRoot
  Write-UEToolSuiteUtf8NoBomFile -Path $resolvedBootstrapScriptPath -Content $bootstrapContent -EnsureParentDirectory

  $markers = Get-ProjectAliasBootstrapMarkers
  Remove-ProfileSnippet -ProfilePath $resolvedProfilePath -StartMarker $markers.LegacyStart -EndMarker $markers.LegacyEnd
  Remove-ProfileSnippet -ProfilePath $resolvedProfilePath -StartMarker $markers.Start -EndMarker $markers.End
  Set-ProfileSnippet `
    -ProfilePath $resolvedProfilePath `
    -StartMarker $markers.Start `
    -EndMarker $markers.End `
    -SnippetBody (Get-ProjectShellAliasBootstrapSnippet -BootstrapScriptPath $resolvedBootstrapScriptPath)

  $registered = Register-ProjectShellAliases -ScriptsRoot $resolvedScriptsRoot
  return [pscustomobject]@{
    ProfilePath = $resolvedProfilePath
    AliasScriptPath = $AliasScriptPath
    BootstrapScriptPath = $resolvedBootstrapScriptPath
    FunctionName = $registered.FunctionName
    Aliases = @($registered.Aliases)
    AliasGroups = @($registered.AliasGroups)
    Definitions = @($registered.Definitions)
    ScriptsRoot = $resolvedScriptsRoot
  }
}

Export-ModuleMember -Function `
  Get-ProjectAliasBootstrapMarkers, `
  Register-ProjectShellAliases, `
  Install-ProjectShellAliases, `
  Resolve-ProfilePathForAliases, `
  Get-DefaultProjectAliasBootstrapScriptPath, `
  Resolve-ProjectAliasBootstrapScriptPath, `
  Get-ProjectShellAliasBootstrapScriptContent
