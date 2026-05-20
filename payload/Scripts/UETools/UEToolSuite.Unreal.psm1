function Get-UEToolSuiteUnrealChangedFileRecords {
  [CmdletBinding()]
  param(
    [string]$OldRev,
    [string]$NewRev
  )

  if ([string]::IsNullOrWhiteSpace($OldRev) -or [string]::IsNullOrWhiteSpace($NewRev)) {
    return @()
  }

  $out = git diff --name-status $OldRev $NewRev 2>$null
  if ($LASTEXITCODE -ne 0) {
    return @()
  }

  $records = @()
  foreach ($line in @($out)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $parts = @($line -split "`t")
    if ($parts.Count -lt 2) { continue }

    $status = [string]$parts[0]
    if (($status.StartsWith("R") -or $status.StartsWith("C")) -and $parts.Count -ge 3) {
      $records += [pscustomobject]@{
        Status = $status
        Path = [string]$parts[2]
        OldPath = [string]$parts[1]
      }
      continue
    }

    $records += [pscustomobject]@{
      Status = $status
      Path = [string]$parts[1]
      OldPath = $null
    }
  }

  return @($records)
}

function Test-UEToolSuiteUnrealCppPath {
  [CmdletBinding()]
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  return (
    $Path -match '^Source/.*\.(h|hpp|cpp|inl)$' -or
    $Path -match '^Plugins/.*\.(h|hpp|cpp|inl)$'
  )
}

function Test-UEToolSuiteUnrealProjectStructurePath {
  [CmdletBinding()]
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  return (
    $Path -match '\.Build\.cs$' -or
    $Path -match '\.Target\.cs$' -or
    $Path -match '\.uproject$' -or
    $Path -match '^Plugins/.*\.uplugin$'
  )
}

function Test-UEToolSuiteUnrealAddDeleteOrRenameStatus {
  [CmdletBinding()]
  param([string]$Status)

  if ([string]::IsNullOrWhiteSpace($Status)) { return $false }
  return (
    $Status.StartsWith("A") -or
    $Status.StartsWith("D") -or
    $Status.StartsWith("R")
  )
}

function Get-UEToolSuiteUnrealSyncActionPlan {
  [CmdletBinding()]
  param([object[]]$ChangedFileRecords)

  if (-not $ChangedFileRecords -or $ChangedFileRecords.Count -eq 0) {
    return [pscustomobject]@{
      BuildTriggers = @()
      RegenTriggers = @()
      ShouldBuild = $false
      ShouldRegen = $false
    }
  }

  $buildTriggers = @()
  $regenTriggers = @()

  foreach ($record in @($ChangedFileRecords)) {
    $paths = @($record.Path, $record.OldPath) |
      Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
      Sort-Object -Unique

    foreach ($path in $paths) {
      if (Test-UEToolSuiteUnrealCppPath -Path $path) {
        $buildTriggers += $path
        if (Test-UEToolSuiteUnrealAddDeleteOrRenameStatus -Status $record.Status) {
          $regenTriggers += $path
        }
        continue
      }

      if (Test-UEToolSuiteUnrealProjectStructurePath -Path $path) {
        $buildTriggers += $path
        $regenTriggers += $path
      }
    }
  }

  $buildTriggers = @($buildTriggers | Sort-Object -Unique)
  $regenTriggers = @($regenTriggers | Sort-Object -Unique)

  return [pscustomobject]@{
    BuildTriggers = $buildTriggers
    RegenTriggers = $regenTriggers
    ShouldBuild = ($buildTriggers.Count -gt 0)
    ShouldRegen = ($regenTriggers.Count -gt 0)
  }
}

function Write-UEToolSuiteUnrealSyncActionPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$ActionPlan,
    [scriptblock]$WarnWriter
  )

  if (-not $ActionPlan -or (-not $ActionPlan.ShouldBuild -and -not $ActionPlan.ShouldRegen)) {
    return
  }

  if (-not $WarnWriter) {
    $WarnWriter = {
      param([string]$Message)
      Write-Warning $Message
    }
  }

  $actions = @()
  if ($ActionPlan.ShouldRegen) { $actions += "regenerate project files" }
  if ($ActionPlan.ShouldBuild) { $actions += "build the editor" }
  & $WarnWriter "UE Sync action plan: $($actions -join ' and ')."

  if ($ActionPlan.RegenTriggers.Count -gt 0) {
    & $WarnWriter "Project-file regeneration triggers:"
    foreach ($t in @($ActionPlan.RegenTriggers)) {
      & $WarnWriter " - $t"
    }
  }

  if ($ActionPlan.BuildTriggers.Count -gt 0) {
    & $WarnWriter "Build triggers:"
    foreach ($t in @($ActionPlan.BuildTriggers)) {
      & $WarnWriter " - $t"
    }
  }
}

Export-ModuleMember -Function `
  Get-UEToolSuiteUnrealChangedFileRecords, `
  Test-UEToolSuiteUnrealCppPath, `
  Test-UEToolSuiteUnrealProjectStructurePath, `
  Get-UEToolSuiteUnrealSyncActionPlan, `
  Write-UEToolSuiteUnrealSyncActionPlan
