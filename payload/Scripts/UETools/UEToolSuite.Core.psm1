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

function Get-UEToolSuitePowerShellHostPath {
  [CmdletBinding()]
  param()

  try {
    $currentProcessPath = (Get-Process -Id $PID -ErrorAction Stop).Path
    if (-not [string]::IsNullOrWhiteSpace($currentProcessPath) -and (Test-Path -LiteralPath $currentProcessPath -PathType Leaf)) {
      return $currentProcessPath
    }
  }
  catch {
    # Fall back to command lookup.
  }

  $pwshCommand = Get-Command -Name "pwsh" -ErrorAction SilentlyContinue
  if ($pwshCommand -and -not [string]::IsNullOrWhiteSpace($pwshCommand.Source)) {
    return $pwshCommand.Source
  }

  $powershellCommand = Get-Command -Name "powershell" -ErrorAction SilentlyContinue
  if ($powershellCommand -and -not [string]::IsNullOrWhiteSpace($powershellCommand.Source)) {
    return $powershellCommand.Source
  }

  throw "Unable to locate a PowerShell host executable."
}

function Invoke-UEToolSuiteScriptProcess {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ScriptPath,
    [AllowNull()][string[]]$ScriptArguments = @()
  )

  if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    throw "Script path was not found: $ScriptPath"
  }

  $hostPath = Get-UEToolSuitePowerShellHostPath
  $invokeArgs = New-Object System.Collections.Generic.List[string]
  $invokeArgs.Add("-NoLogo") | Out-Null
  $invokeArgs.Add("-NoProfile") | Out-Null
  $invokeArgs.Add("-ExecutionPolicy") | Out-Null
  $invokeArgs.Add("Bypass") | Out-Null
  $invokeArgs.Add("-File") | Out-Null
  $invokeArgs.Add($ScriptPath) | Out-Null
  foreach ($argument in @($ScriptArguments)) {
    if ($null -eq $argument) { continue }
    $invokeArgs.Add([string]$argument) | Out-Null
  }

  & $hostPath @($invokeArgs.ToArray())
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    throw "Script command failed (exit $exitCode): $ScriptPath"
  }
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

  if ($PSBoundParameters.ContainsKey("ScriptsRoot") -or $PSBoundParameters.ContainsKey("StateKey")) {
    [void](Get-UEToolSuiteRuntimeContext -ScriptsRoot $ScriptsRoot -StateKey $StateKey)
  }

  return $true
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

  Write-UEToolSuiteUtf8NoBomFile -Path $Path -Content $Content -EnsureParentDirectory:$ensureParent
}

function Test-CommandAvailable {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Name,
    [string]$ModuleFunctionName,
    [string]$ScriptsRoot,
    [string]$StateKey
  )

  $context = $null
  try {
    $context = Get-UEToolSuiteRuntimeContext -ScriptsRoot $ScriptsRoot -StateKey $StateKey
  }
  catch {
    $context = $null
  }

  $resolverName = $ModuleFunctionName
  if ([string]::IsNullOrWhiteSpace($resolverName) -and $context) {
    $resolverName = $context.CommandAvailabilityFunctionName
  }

  if (-not [string]::IsNullOrWhiteSpace($resolverName)) {
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

  if (-not [string]::IsNullOrWhiteSpace($ExplicitRepoRoot)) {
    $candidate = [System.IO.Path]::GetFullPath($ExplicitRepoRoot)
    $exists = if ($AllowFilePath) {
      Test-Path -LiteralPath $candidate
    }
    else {
      Test-Path -LiteralPath $candidate -PathType Container
    }

    if (-not $exists) {
      if ($AllowFilePath) {
        throw "RepoRoot does not exist: $candidate"
      }

      throw "RepoRoot does not exist or is not a directory: $candidate"
    }

    return (Resolve-Path -LiteralPath $candidate).Path
  }

  return (Resolve-UEToolSuiteRepoRoot -InvocationName $InvocationName)
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

  return (Resolve-UEToolSuiteRepoPath -RepoRoot $RepoRoot -RelativePath $RelativePath -NotFoundMessagePrefix $NotFoundMessagePrefix -PathType $PathType)
}

function Write-UEToolSuiteRuntimeUtf8NoBomFile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ScriptsRoot,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
    [switch]$EnsureParentDirectory
  )

  Write-UEToolSuiteUtf8NoBomFile -Path $Path -Content $Content -EnsureParentDirectory:$EnsureParentDirectory
}

Export-ModuleMember -Function `
  Write-UEToolSuiteUtf8NoBomFile, `
  Resolve-UEToolSuiteRepoRoot, `
  Resolve-UEToolSuiteRepoPath, `
  Get-UEToolSuiteCoreModuleEntryPath, `
  Get-UEToolSuitePowerShellHostPath, `
  Invoke-UEToolSuiteScriptProcess, `
  Set-UEToolSuiteRuntimeContext, `
  Get-UEToolSuiteRuntimeContext, `
  Import-UEToolSuiteCoreModule, `
  Write-UEToolSuiteRuntimeLog, `
  Info, `
  Warn, `
  Err, `
  Ok, `
  Success, `
  Write-Utf8NoBomFile, `
  Test-CommandAvailable, `
  Resolve-UEToolSuiteRuntimeRepoRoot, `
  Resolve-UEToolSuiteRuntimeRepoPath, `
  Write-UEToolSuiteRuntimeUtf8NoBomFile
