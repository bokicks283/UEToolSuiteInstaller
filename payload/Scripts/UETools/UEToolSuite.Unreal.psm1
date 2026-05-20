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

function Test-UEToolSuiteUnrealEnvTrue {
  [CmdletBinding()]
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
  switch ($Value.Trim().ToLowerInvariant()) {
    "1" { return $true }
    "true" { return $true }
    "yes" { return $true }
    default { return $false }
  }
}

function Test-UEToolSuiteUnrealCanPrompt {
  [CmdletBinding()]
  param()

  try {
    if (-not [Environment]::UserInteractive) { return $false }
    if (-not $Host.UI -or -not $Host.UI.RawUI) { return $false }
    if ([Console]::IsInputRedirected) { return $false }
    if ([Console]::IsOutputRedirected) { return $false }
    return $true
  }
  catch { return $false }
}

function Add-UEToolSuiteUnrealDiagnosticAttempt {
  [CmdletBinding()]
  param(
    [System.Collections.Generic.List[string]]$Attempts,
    [string]$Message
  )

  if ($null -ne $Attempts) {
    [void]$Attempts.Add($Message)
  }
}

function Test-UEToolSuiteUnrealEngineRoot {
  [CmdletBinding()]
  param([string]$Root)

  if ([string]::IsNullOrWhiteSpace($Root)) { return $false }
  if (-not (Test-Path -LiteralPath $Root)) { return $false }
  return (Test-Path -LiteralPath (Join-Path $Root "Engine\Build\BatchFiles\Build.bat"))
}

function Resolve-UEToolSuiteUnrealPathRelativeTo {
  [CmdletBinding()]
  param(
    [string]$BaseDir,
    [string]$Path
  )

  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  if ([IO.Path]::IsPathRooted($Path)) { return $Path }
  return (Join-Path $BaseDir $Path)
}

function Get-UEToolSuiteUnrealRegistryPropertyString {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$KeyPath,
    [Parameter(Mandatory)][string]$PropertyName
  )

  if (-not (Test-Path -LiteralPath $KeyPath)) { return $null }
  $props = Get-ItemProperty -LiteralPath $KeyPath -ErrorAction SilentlyContinue
  if (-not $props) { return $null }

  $property = $props.PSObject.Properties[$PropertyName]
  if ($property) { return [string]$property.Value }
  return $null
}

function Test-UEToolSuiteJsonObjectProperty {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$Name
  )

  return ($null -ne $Object.PSObject.Properties[$Name])
}

function Get-UEToolSuiteJsonObjectPropertyValue {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$Name
  )

  $property = $Object.PSObject.Properties[$Name]
  if ($property) { return $property.Value }
  return $null
}

function Set-UEToolSuiteJsonObjectPropertyValue {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$Name,
    [AllowNull()]$Value
  )

  if (Test-UEToolSuiteJsonObjectProperty -Object $Object -Name $Name) {
    $Object.$Name = $Value
    return
  }

  $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
}

function Test-UEToolSuiteJsonObject {
  [CmdletBinding()]
  param([AllowNull()]$Value)

  return ($null -ne $Value -and $Value -is [pscustomobject])
}

function Merge-UEToolSuiteMissingJsonObjectProperties {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Target,
    [Parameter(Mandatory)]$Source
  )

  foreach ($sourceProperty in @($Source.PSObject.Properties)) {
    $targetValue = Get-UEToolSuiteJsonObjectPropertyValue -Object $Target -Name $sourceProperty.Name
    if (-not (Test-UEToolSuiteJsonObjectProperty -Object $Target -Name $sourceProperty.Name)) {
      Set-UEToolSuiteJsonObjectPropertyValue -Object $Target -Name $sourceProperty.Name -Value $sourceProperty.Value
      continue
    }

    if ((Test-UEToolSuiteJsonObject -Value $targetValue) -and (Test-UEToolSuiteJsonObject -Value $sourceProperty.Value)) {
      Merge-UEToolSuiteMissingJsonObjectProperties -Target $targetValue -Source $sourceProperty.Value
    }
  }
}

function Merge-UEToolSuiteStringArrayProperty {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Target,
    [Parameter(Mandatory)]$Source,
    [Parameter(Mandatory)][string]$PropertyName
  )

  if (-not (Test-UEToolSuiteJsonObjectProperty -Object $Source -Name $PropertyName)) { return }

  $existing = @()
  if (Test-UEToolSuiteJsonObjectProperty -Object $Target -Name $PropertyName) {
    $existing = @(Get-UEToolSuiteJsonObjectPropertyValue -Object $Target -Name $PropertyName)
  }

  $merged = @($existing + @(Get-UEToolSuiteJsonObjectPropertyValue -Object $Source -Name $PropertyName)) |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
    Select-Object -Unique

  Set-UEToolSuiteJsonObjectPropertyValue -Object $Target -Name $PropertyName -Value @($merged)
}

function Merge-UEToolSuiteNamedObjectArrayProperty {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Target,
    [Parameter(Mandatory)]$Source,
    [Parameter(Mandatory)][string]$ArrayPropertyName,
    [Parameter(Mandatory)][string]$KeyPropertyName
  )

  if (-not (Test-UEToolSuiteJsonObjectProperty -Object $Source -Name $ArrayPropertyName)) { return }

  $targetItems = @()
  if (Test-UEToolSuiteJsonObjectProperty -Object $Target -Name $ArrayPropertyName) {
    $targetItems = @(Get-UEToolSuiteJsonObjectPropertyValue -Object $Target -Name $ArrayPropertyName)
  }

  $targetKeys = @{}
  foreach ($item in $targetItems) {
    $key = [string](Get-UEToolSuiteJsonObjectPropertyValue -Object $item -Name $KeyPropertyName)
    if (-not [string]::IsNullOrWhiteSpace($key)) {
      $targetKeys[$key] = $true
    }
  }

  $mergedItems = @($targetItems)
  foreach ($sourceItem in @(Get-UEToolSuiteJsonObjectPropertyValue -Object $Source -Name $ArrayPropertyName)) {
    $sourceKey = [string](Get-UEToolSuiteJsonObjectPropertyValue -Object $sourceItem -Name $KeyPropertyName)
    if ([string]::IsNullOrWhiteSpace($sourceKey) -or $targetKeys.ContainsKey($sourceKey)) {
      continue
    }

    $mergedItems += $sourceItem
    $targetKeys[$sourceKey] = $true
  }

  Set-UEToolSuiteJsonObjectPropertyValue -Object $Target -Name $ArrayPropertyName -Value @($mergedItems)
}

function Merge-UEToolSuiteVSCodeWorkspaceJson {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$GeneratedWorkspace,
    [Parameter(Mandatory)]$PreviousWorkspace
  )

  Merge-UEToolSuiteMissingJsonObjectProperties -Target $GeneratedWorkspace -Source $PreviousWorkspace
  Merge-UEToolSuiteNamedObjectArrayProperty -Target $GeneratedWorkspace -Source $PreviousWorkspace -ArrayPropertyName "folders" -KeyPropertyName "path"

  $generatedExtensions = Get-UEToolSuiteJsonObjectPropertyValue -Object $GeneratedWorkspace -Name "extensions"
  $previousExtensions = Get-UEToolSuiteJsonObjectPropertyValue -Object $PreviousWorkspace -Name "extensions"
  if ((Test-UEToolSuiteJsonObject -Value $generatedExtensions) -and (Test-UEToolSuiteJsonObject -Value $previousExtensions)) {
    Merge-UEToolSuiteStringArrayProperty -Target $generatedExtensions -Source $previousExtensions -PropertyName "recommendations"
    Merge-UEToolSuiteStringArrayProperty -Target $generatedExtensions -Source $previousExtensions -PropertyName "unwantedRecommendations"
  }

  $generatedTasks = Get-UEToolSuiteJsonObjectPropertyValue -Object $GeneratedWorkspace -Name "tasks"
  $previousTasks = Get-UEToolSuiteJsonObjectPropertyValue -Object $PreviousWorkspace -Name "tasks"
  if ((Test-UEToolSuiteJsonObject -Value $generatedTasks) -and (Test-UEToolSuiteJsonObject -Value $previousTasks)) {
    Merge-UEToolSuiteNamedObjectArrayProperty -Target $generatedTasks -Source $previousTasks -ArrayPropertyName "tasks" -KeyPropertyName "label"
  }

  $generatedLaunch = Get-UEToolSuiteJsonObjectPropertyValue -Object $GeneratedWorkspace -Name "launch"
  $previousLaunch = Get-UEToolSuiteJsonObjectPropertyValue -Object $PreviousWorkspace -Name "launch"
  if ((Test-UEToolSuiteJsonObject -Value $generatedLaunch) -and (Test-UEToolSuiteJsonObject -Value $previousLaunch)) {
    Merge-UEToolSuiteNamedObjectArrayProperty -Target $generatedLaunch -Source $previousLaunch -ArrayPropertyName "configurations" -KeyPropertyName "name"
  }

  return $GeneratedWorkspace
}

function Test-UEToolSuiteUnrealGitTrackedPath {
  [CmdletBinding()]
  param([string]$RelativePath)

  if ([string]::IsNullOrWhiteSpace($RelativePath)) {
    return $false
  }

  & git ls-files --error-unmatch -- $RelativePath 2>$null | Out-Null
  return ($LASTEXITCODE -eq 0)
}

function Get-UEToolSuiteUnrealWorkspaceProtectionPaths {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$ProjectContext,
    [string]$WorkspacePathOverride
  )

  $paths = New-Object System.Collections.Generic.List[string]
  if (-not [string]::IsNullOrWhiteSpace($WorkspacePathOverride)) {
    [void]$paths.Add((Resolve-UEToolSuiteUnrealPathRelativeTo -BaseDir $ProjectContext.RepoRoot -Path $WorkspacePathOverride))
  }

  if (-not [string]::IsNullOrWhiteSpace($ProjectContext.WorkspacePath)) {
    [void]$paths.Add($ProjectContext.WorkspacePath)
  }

  [void]$paths.Add((Join-Path $ProjectContext.RepoRoot "$($ProjectContext.ProjectName).code-workspace"))

  return @(
    $paths.ToArray() |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      ForEach-Object { [System.IO.Path]::GetFullPath($_) } |
      Sort-Object -Unique
  )
}

function New-UEToolSuiteUnrealProjectFileArtifactSnapshot {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$ProjectContext,
    [string]$WorkspacePathOverride
  )

  $workspaceSnapshots = @()
  foreach ($workspacePath in @(Get-UEToolSuiteUnrealWorkspaceProtectionPaths -ProjectContext $ProjectContext -WorkspacePathOverride $WorkspacePathOverride)) {
    if (-not (Test-Path -LiteralPath $workspacePath -PathType Leaf)) {
      continue
    }

    $workspaceSnapshots += [pscustomobject]@{
      Path = $workspacePath
      Content = Get-Content -LiteralPath $workspacePath -Raw
    }
  }

  $ignorePath = Join-Path $ProjectContext.RepoRoot ".ignore"
  $ignoreExists = Test-Path -LiteralPath $ignorePath -PathType Leaf
  $ignoreTracked = Test-UEToolSuiteUnrealGitTrackedPath -RelativePath ".ignore"

  return [pscustomobject]@{
    WorkspaceSnapshots = @($workspaceSnapshots)
    IgnorePath = $ignorePath
    IgnoreExists = $ignoreExists
    IgnoreTracked = $ignoreTracked
    IgnoreContent = if ($ignoreExists) { Get-Content -LiteralPath $ignorePath -Raw } else { $null }
  }
}

Export-ModuleMember -Function `
  Get-UEToolSuiteUnrealChangedFileRecords, `
  Test-UEToolSuiteUnrealCppPath, `
  Test-UEToolSuiteUnrealProjectStructurePath, `
  Get-UEToolSuiteUnrealSyncActionPlan, `
  Write-UEToolSuiteUnrealSyncActionPlan, `
  Test-UEToolSuiteUnrealEnvTrue, `
  Test-UEToolSuiteUnrealCanPrompt, `
  Add-UEToolSuiteUnrealDiagnosticAttempt, `
  Test-UEToolSuiteUnrealEngineRoot, `
  Resolve-UEToolSuiteUnrealPathRelativeTo, `
  Get-UEToolSuiteUnrealRegistryPropertyString, `
  Test-UEToolSuiteJsonObjectProperty, `
  Get-UEToolSuiteJsonObjectPropertyValue, `
  Set-UEToolSuiteJsonObjectPropertyValue, `
  Test-UEToolSuiteJsonObject, `
  Merge-UEToolSuiteMissingJsonObjectProperties, `
  Merge-UEToolSuiteStringArrayProperty, `
  Merge-UEToolSuiteNamedObjectArrayProperty, `
  Merge-UEToolSuiteVSCodeWorkspaceJson, `
  Test-UEToolSuiteUnrealGitTrackedPath, `
  Get-UEToolSuiteUnrealWorkspaceProtectionPaths, `
  New-UEToolSuiteUnrealProjectFileArtifactSnapshot
