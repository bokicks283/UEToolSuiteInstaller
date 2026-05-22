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

Export-ModuleMember -Function `
  Write-UEToolSuiteUtf8NoBomFile, `
  Resolve-UEToolSuiteRepoRoot, `
  Resolve-UEToolSuiteRepoPath, `
  Get-UEToolSuiteCoreModuleEntryPath, `
  Get-UEToolSuitePowerShellHostPath, `
  Invoke-UEToolSuiteScriptProcess
