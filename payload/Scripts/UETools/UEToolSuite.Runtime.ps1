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
