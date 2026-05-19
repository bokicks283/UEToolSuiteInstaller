function Get-UEToolSuiteCoreModuleEntryPathFromScriptsRoot {
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

function Import-UEToolSuiteCoreModuleFromScriptsRoot {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ScriptsRoot,
    [Parameter(Mandatory)][string]$StateKey
  )

  $stateVarName = "UEToolSuiteCoreModuleImportState"
  $stateVar = Get-Variable -Scope Script -Name $stateVarName -ErrorAction SilentlyContinue
  if ($null -eq $stateVar) {
    Set-Variable -Scope Script -Name $stateVarName -Value (@{}) -Force
    $state = Get-Variable -Scope Script -Name $stateVarName -ErrorAction Stop
    $stateValue = $state.Value
  }
  else {
    $stateValue = $stateVar.Value
  }

  if ($stateValue.ContainsKey($StateKey)) {
    return [bool]$stateValue[$StateKey]
  }

  $modulePath = Get-UEToolSuiteCoreModuleEntryPathFromScriptsRoot -ScriptsRoot $ScriptsRoot
  if ([string]::IsNullOrWhiteSpace($modulePath)) {
    $stateValue[$StateKey] = $false
    return $false
  }

  Import-Module -Name $modulePath -Force
  $stateValue[$StateKey] = $true
  return $true
}

function Resolve-UEToolSuiteRuntimeRepoRoot {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ScriptsRoot,
    [string]$ExplicitRepoRoot,
    [string]$InvocationName = "Command",
    [switch]$AllowFilePath
  )

  $stateKey = "runtime-repo-root::{0}" -f $ScriptsRoot.ToLowerInvariant()
  if (Import-UEToolSuiteCoreModuleFromScriptsRoot -ScriptsRoot $ScriptsRoot -StateKey $stateKey) {
    $resolver = Get-Command -Name "Resolve-UEToolSuiteRepoRoot" -ErrorAction SilentlyContinue
    if ($resolver) {
      return (Resolve-UEToolSuiteRepoRoot -ExplicitRepoRoot $ExplicitRepoRoot -InvocationName $InvocationName)
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($ExplicitRepoRoot)) {
    $candidate = [System.IO.Path]::GetFullPath($ExplicitRepoRoot)
    $pathType = if ($AllowFilePath) { "Any" } else { "Container" }
    $exists = switch ($pathType) {
      "Container" { Test-Path -LiteralPath $candidate -PathType Container }
      default { Test-Path -LiteralPath $candidate }
    }
    if (-not $exists) {
      if ($AllowFilePath) {
        throw "RepoRoot does not exist: $candidate"
      }
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

function Resolve-UEToolSuiteRuntimeRepoPath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ScriptsRoot,
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$NotFoundMessagePrefix,
    [ValidateSet("Any", "Leaf", "Container")][string]$PathType = "Any"
  )

  $stateKey = "runtime-repo-path::{0}" -f $ScriptsRoot.ToLowerInvariant()
  if (Import-UEToolSuiteCoreModuleFromScriptsRoot -ScriptsRoot $ScriptsRoot -StateKey $stateKey) {
    $resolver = Get-Command -Name "Resolve-UEToolSuiteRepoPath" -ErrorAction SilentlyContinue
    if ($resolver) {
      return (Resolve-UEToolSuiteRepoPath -RepoRoot $RepoRoot -RelativePath $RelativePath -NotFoundMessagePrefix $NotFoundMessagePrefix -PathType $PathType)
    }
  }

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

function Write-UEToolSuiteRuntimeUtf8NoBomFile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ScriptsRoot,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
    [switch]$EnsureParentDirectory
  )

  $stateKey = "runtime-write-file::{0}" -f $ScriptsRoot.ToLowerInvariant()
  if (Import-UEToolSuiteCoreModuleFromScriptsRoot -ScriptsRoot $ScriptsRoot -StateKey $stateKey) {
    $writer = Get-Command -Name "Write-UEToolSuiteUtf8NoBomFile" -ErrorAction SilentlyContinue
    if ($writer) {
      Write-UEToolSuiteUtf8NoBomFile -Path $Path -Content $Content -EnsureParentDirectory:$EnsureParentDirectory
      return
    }
  }

  if ($EnsureParentDirectory) {
    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
      New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
  }

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}
