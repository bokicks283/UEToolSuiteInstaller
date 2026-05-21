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

function Set-UEToolSuiteRuntimeContext {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ScriptsRoot,
    [Parameter(Mandatory)][string]$StateKey,
    [string]$LogPrefix = "[UETools]",
    [switch]$WriteFileEnsureParentDirectory,
    [string]$CommandAvailabilityFunctionName
  )

  $script:UEToolSuiteRuntimeContext = @{
    ScriptsRoot = $ScriptsRoot
    StateKey = $StateKey
    LogPrefix = $LogPrefix
    WriteFileEnsureParentDirectory = [bool]$WriteFileEnsureParentDirectory
    CommandAvailabilityFunctionName = $CommandAvailabilityFunctionName
  }
}

function Get-UEToolSuiteRuntimeContext {
  [CmdletBinding()]
  param(
    [string]$ScriptsRoot,
    [string]$StateKey
  )

  $context = @{}
  if ($script:UEToolSuiteRuntimeContext) {
    $context = $script:UEToolSuiteRuntimeContext
  }

  $resolvedScriptsRoot = $ScriptsRoot
  if ([string]::IsNullOrWhiteSpace($resolvedScriptsRoot)) {
    $resolvedScriptsRoot = [string]$context.ScriptsRoot
  }
  if ([string]::IsNullOrWhiteSpace($resolvedScriptsRoot)) {
    throw "UEToolSuite runtime context is missing ScriptsRoot. Call Set-UEToolSuiteRuntimeContext or pass -ScriptsRoot."
  }

  $resolvedStateKey = $StateKey
  if ([string]::IsNullOrWhiteSpace($resolvedStateKey)) {
    $resolvedStateKey = [string]$context.StateKey
  }
  if ([string]::IsNullOrWhiteSpace($resolvedStateKey)) {
    $resolvedStateKey = "runtime::{0}" -f $resolvedScriptsRoot.ToLowerInvariant()
  }

  $logPrefix = [string]$context.LogPrefix
  if ([string]::IsNullOrWhiteSpace($logPrefix)) {
    $logPrefix = "[UETools]"
  }

  return [pscustomobject]@{
    ScriptsRoot = $resolvedScriptsRoot
    StateKey = $resolvedStateKey
    LogPrefix = $logPrefix
    WriteFileEnsureParentDirectory = [bool]$context.WriteFileEnsureParentDirectory
    CommandAvailabilityFunctionName = [string]$context.CommandAvailabilityFunctionName
  }
}

function Import-UEToolSuiteCoreModule {
  [CmdletBinding()]
  param(
    [string]$ScriptsRoot,
    [string]$StateKey
  )

  $context = Get-UEToolSuiteRuntimeContext -ScriptsRoot $ScriptsRoot -StateKey $StateKey
  return (Import-UEToolSuiteCoreModuleFromScriptsRoot -ScriptsRoot $context.ScriptsRoot -StateKey $context.StateKey)
}

function Write-UEToolSuiteRuntimeLog {
  [CmdletBinding()]
  param(
    [AllowNull()][AllowEmptyString()][string]$Message,
    [ValidateSet("Info", "Warn", "Err", "Ok", "Success")][string]$Level = "Info",
    [string]$LogPrefix
  )

  $prefix = $LogPrefix
  if ([string]::IsNullOrWhiteSpace($prefix)) {
    if ($script:UEToolSuiteRuntimeContext -and -not [string]::IsNullOrWhiteSpace([string]$script:UEToolSuiteRuntimeContext.LogPrefix)) {
      $prefix = [string]$script:UEToolSuiteRuntimeContext.LogPrefix
    }
    else {
      $prefix = "[UETools]"
    }
  }

  $color = switch ($Level) {
    "Info" { "Cyan" }
    "Warn" { "Yellow" }
    "Err" { "Red" }
    "Ok" { "Green" }
    "Success" { "Green" }
    default { "Gray" }
  }

  Write-Host "$prefix $Message" -ForegroundColor $color
}

function Info {
  [CmdletBinding()]
  param([AllowNull()][AllowEmptyString()][string]$Message)
  Write-UEToolSuiteRuntimeLog -Message $Message -Level "Info"
}

function Warn {
  [CmdletBinding()]
  param([AllowNull()][AllowEmptyString()][string]$Message)
  Write-UEToolSuiteRuntimeLog -Message $Message -Level "Warn"
}

function Err {
  [CmdletBinding()]
  param([AllowNull()][AllowEmptyString()][string]$Message)
  Write-UEToolSuiteRuntimeLog -Message $Message -Level "Err"
}

function Ok {
  [CmdletBinding()]
  param([AllowNull()][AllowEmptyString()][string]$Message)
  Write-UEToolSuiteRuntimeLog -Message $Message -Level "Ok"
}

function Success {
  [CmdletBinding()]
  param([AllowNull()][AllowEmptyString()][string]$Message)
  Write-UEToolSuiteRuntimeLog -Message $Message -Level "Success"
}

function Write-Utf8NoBomFile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
    [switch]$EnsureParentDirectory,
    [string]$ScriptsRoot,
    [string]$StateKey
  )

  $context = Get-UEToolSuiteRuntimeContext -ScriptsRoot $ScriptsRoot -StateKey $StateKey
  $ensureParent = $EnsureParentDirectory
  if (-not $PSBoundParameters.ContainsKey("EnsureParentDirectory")) {
    $ensureParent = [bool]$context.WriteFileEnsureParentDirectory
  }

  Write-UEToolSuiteRuntimeUtf8NoBomFile -ScriptsRoot $context.ScriptsRoot -Path $Path -Content $Content -EnsureParentDirectory:$ensureParent
}

function Test-CommandAvailable {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Name,
    [string]$ModuleFunctionName,
    [string]$ScriptsRoot,
    [string]$StateKey
  )

  $context = Get-UEToolSuiteRuntimeContext -ScriptsRoot $ScriptsRoot -StateKey $StateKey

  $resolverName = $ModuleFunctionName
  if ([string]::IsNullOrWhiteSpace($resolverName)) {
    $resolverName = $context.CommandAvailabilityFunctionName
  }

  if (-not [string]::IsNullOrWhiteSpace($resolverName)) {
    [void](Import-UEToolSuiteCoreModuleFromScriptsRoot -ScriptsRoot $context.ScriptsRoot -StateKey $context.StateKey)
    $moduleFn = Get-Command -Name $resolverName -ErrorAction SilentlyContinue
    if ($moduleFn) {
      return (& $resolverName -Name $Name)
    }
  }

  return ($null -ne (Get-Command $Name -ErrorAction SilentlyContinue))
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
