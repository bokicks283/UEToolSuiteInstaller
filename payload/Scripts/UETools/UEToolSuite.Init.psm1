function Add-UEToolSuiteInitToolReadinessEntry {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][System.Collections.Generic.List[object]]$ReadinessList,
    [Parameter(Mandatory)][string]$Tool,
    [Parameter(Mandatory)][ValidateSet("OK", "WARN", "SKIP")][string]$Status,
    [Parameter(Mandatory)][string]$Detail
  )

  [void]$ReadinessList.Add([pscustomobject]@{
      Tool = $Tool
      Status = $Status
      Detail = $Detail
    })
}

function Test-UEToolSuiteInitCommandAvailable {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Name)
  return ($null -ne (Get-Command $Name -ErrorAction SilentlyContinue))
}

function Assert-UEToolSuiteInitCommandAvailable {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$InstallHint
  )

  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $command) {
    throw "$Name not found. $InstallHint"
  }

  return $command
}

function Assert-UEToolSuiteInitNodeVersion {
  [CmdletBinding()]
  param()

  $nodeVersion = ((& node --version 2>$null) | Select-Object -First 1)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($nodeVersion)) {
    throw "node --version failed. Install Node.js 20+ and try again."
  }

  $versionText = $nodeVersion.Trim()
  if ($versionText -notmatch '^v?(?<major>\d+)') {
    throw "Could not parse Node.js version '$versionText'. Install Node.js 20+ and try again."
  }

  $major = [int]$Matches.major
  if ($major -lt 20) {
    throw "Node.js 20+ is required for docs tooling. Current: $versionText"
  }

  return $versionText
}

function Invoke-UEToolSuiteInitCheckedTool {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Description,
    [Parameter(Mandatory)][string]$FilePath,
    [string[]]$Arguments = @(),
    [string]$WorkingDirectory
  )

  $oldLocation = (Get-Location).Path
  try {
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
      Set-Location -LiteralPath $WorkingDirectory
    }

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "$Description failed (exit $LASTEXITCODE)."
    }
  }
  finally {
    Set-Location -LiteralPath $oldLocation
  }
}

function Get-UEToolSuiteInitGitHubRepoSlugFromRemoteUrl {
  [CmdletBinding()]
  param([string]$RemoteUrl)

  if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
    return $null
  }

  $trimmed = $RemoteUrl.Trim()
  if ($trimmed -match 'github\.com[:/](?<slug>[^/\s]+/[^/\s]+?)(?:\.git)?$') {
    return $Matches.slug
  }

  return $null
}

function ConvertTo-UEToolSuiteInitTypeScriptSingleQuotedString {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Value)

  return "'" + (($Value -replace "\\", "\\") -replace "'", "\'") + "'"
}

function Set-UEToolSuiteInitTypeScriptStringProperty {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$PropertyName,
    [Parameter(Mandatory)][string]$Value
  )

  $quotedValue = ConvertTo-UEToolSuiteInitTypeScriptSingleQuotedString -Value $Value
  $pattern = "(?m)^(\s*" + [regex]::Escape($PropertyName) + "\s*:\s*)(['""]).*?\2(,?\s*)$"
  if (-not [regex]::IsMatch($Text, $pattern)) {
    return $Text
  }

  return [regex]::Replace(
    $Text,
    $pattern,
    [System.Text.RegularExpressions.MatchEvaluator] {
      param($match)
      return $match.Groups[1].Value + $quotedValue + $match.Groups[3].Value
    },
    1
  )
}

function Resolve-UEToolSuiteInitRepoRoot {
  [CmdletBinding()]
  param(
    [string]$ExplicitRepoRoot,
    [string]$InvocationName = "Init-Repo"
  )

  if ([string]::IsNullOrWhiteSpace($ExplicitRepoRoot)) {
    $gitRoot = ((git rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($gitRoot)) {
      throw "Not inside a git repository (git rev-parse failed). Pass -RepoRoot when running from outside the repo."
    }

    return $gitRoot.Trim()
  }

  $candidate = [System.IO.Path]::GetFullPath($ExplicitRepoRoot)
  if (-not (Test-Path -LiteralPath $candidate)) {
    throw "RepoRoot does not exist: $candidate"
  }

  $gitRootFromCandidate = ((git -C $candidate rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($gitRootFromCandidate)) {
    throw "RepoRoot is not inside a git repository: $candidate"
  }

  return $gitRootFromCandidate.Trim()
}

function Show-UEToolSuiteInitToolReadinessSummary {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][System.Collections.IEnumerable]$Entries,
    [string]$Prefix = "[Init]"
  )

  $entryArray = @($Entries)
  if ($entryArray.Count -eq 0) {
    return
  }

  Write-Host "$Prefix Tool readiness summary:" -ForegroundColor Cyan
  foreach ($entry in $entryArray) {
    $color = [ConsoleColor]::Gray
    if ($entry.Status -eq "OK") {
      $color = [ConsoleColor]::Green
    }
    elseif ($entry.Status -eq "WARN") {
      $color = [ConsoleColor]::Yellow
    }
    elseif ($entry.Status -eq "SKIP") {
      $color = [ConsoleColor]::DarkYellow
    }

    Write-Host ("  [{0}] {1}: {2}" -f $entry.Status, $entry.Tool, $entry.Detail) -ForegroundColor $color
  }
}

Export-ModuleMember -Function `
  Add-UEToolSuiteInitToolReadinessEntry, `
  Test-UEToolSuiteInitCommandAvailable, `
  Assert-UEToolSuiteInitCommandAvailable, `
  Assert-UEToolSuiteInitNodeVersion, `
  Invoke-UEToolSuiteInitCheckedTool, `
  Get-UEToolSuiteInitGitHubRepoSlugFromRemoteUrl, `
  ConvertTo-UEToolSuiteInitTypeScriptSingleQuotedString, `
  Set-UEToolSuiteInitTypeScriptStringProperty, `
  Resolve-UEToolSuiteInitRepoRoot, `
  Show-UEToolSuiteInitToolReadinessSummary
