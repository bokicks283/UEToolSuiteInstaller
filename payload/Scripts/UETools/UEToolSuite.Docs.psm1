function Get-UEToolSuiteDocsNormalizedArgumentList {
  [CmdletBinding()]
  param([AllowNull()][string[]]$Values)

  $normalized = New-Object System.Collections.Generic.List[string]
  foreach ($value in @($Values)) {
    if ($null -eq $value) {
      continue
    }

    $stringValue = [string]$value
    if ([string]::IsNullOrWhiteSpace($stringValue)) {
      continue
    }

    $normalized.Add($stringValue) | Out-Null
  }

  return $normalized.ToArray()
}

function Resolve-UEToolSuiteDocsCommandAlias {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$CommandName)

  $normalized = $CommandName.Trim().ToLowerInvariant()
  switch ($normalized) {
    "create-page" { return "new-page" }
    "create-section" { return "new-section" }
    default { return $normalized }
  }
}

function Test-UEToolSuiteDocsHelpToken {
  [CmdletBinding()]
  param([string]$Token)

  if ([string]::IsNullOrWhiteSpace($Token)) {
    return $false
  }

  $normalized = $Token.Trim().ToLowerInvariant()
  return ($normalized -in @("help", "--help", "-help", "-h", "/?", "-?"))
}

function Split-UEToolSuiteDocsStartArguments {
  [CmdletBinding()]
  param([string[]]$StartArgsInput = @())

  $background = $false
  $passThroughArgs = New-Object System.Collections.Generic.List[string]
  foreach ($token in @(Get-UEToolSuiteDocsNormalizedArgumentList -Values $StartArgsInput)) {
    $normalized = [string]$token
    if ($normalized -in @("--background", "-background")) {
      $background = $true
      continue
    }

    $passThroughArgs.Add($normalized) | Out-Null
  }

  return [pscustomobject]@{
    Background = $background
    StartArgs = $passThroughArgs.ToArray()
  }
}

Export-ModuleMember -Function `
  Get-UEToolSuiteDocsNormalizedArgumentList, `
  Resolve-UEToolSuiteDocsCommandAlias, `
  Test-UEToolSuiteDocsHelpToken, `
  Split-UEToolSuiteDocsStartArguments
