$script:UEToolSuiteWorkspaceSettingsSchemaVersion = 1
$script:UEToolSuiteWorkspaceProjectContextHelper = Join-Path (Split-Path -Parent $PSScriptRoot) 'Unreal\ProjectContext.ps1'
if (-not (Test-Path -LiteralPath $script:UEToolSuiteWorkspaceProjectContextHelper -PathType Leaf)) {
  throw "Project context helper not found: $script:UEToolSuiteWorkspaceProjectContextHelper"
}
. $script:UEToolSuiteWorkspaceProjectContextHelper
$script:UEToolSuiteWorkspaceArrayIdentities = @{
  '/folders' = 'path'
  '/tasks/tasks' = 'label'
  '/launch/configurations' = 'name'
  '/launch/compounds' = 'name'
  '/inputs' = 'id'
}

function ConvertFrom-UEToolSuiteJsoncText {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
    [Parameter(Mandatory)][string]$SourceName
  )

  $builder = [System.Text.StringBuilder]::new()
  $inString = $false
  $escaped = $false
  $lineComment = $false
  $blockComment = $false
  for ($i = 0; $i -lt $Text.Length; $i++) {
    $ch = $Text[$i]
    $next = if (($i + 1) -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
    if ($lineComment) {
      if ($ch -eq "`n" -or $ch -eq "`r") { $lineComment = $false; [void]$builder.Append($ch) }
      continue
    }
    if ($blockComment) {
      if ($ch -eq '*' -and $next -eq '/') { $blockComment = $false; $i++ }
      elseif ($ch -eq "`n" -or $ch -eq "`r") { [void]$builder.Append($ch) }
      continue
    }
    if ($inString) {
      [void]$builder.Append($ch)
      if ($escaped) { $escaped = $false; continue }
      if ($ch -eq '\') { $escaped = $true; continue }
      if ($ch -eq '"') { $inString = $false }
      continue
    }
    if ($ch -eq '"') { $inString = $true; [void]$builder.Append($ch); continue }
    if ($ch -eq '/' -and $next -eq '/') { $lineComment = $true; $i++; continue }
    if ($ch -eq '/' -and $next -eq '*') { $blockComment = $true; $i++; continue }
    [void]$builder.Append($ch)
  }
  if ($inString -or $blockComment) { throw "Malformed JSONC in '$SourceName': unterminated string or comment." }
  try {
    return ($builder.ToString() | ConvertFrom-Json -AsHashtable -Depth 100)
  }
  catch { throw "Could not parse JSON/JSONC '$SourceName': $($_.Exception.Message)" }
}

function Read-UEToolSuiteWorkspaceJsonFile {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Workspace settings file was not found: $Path" }
  return (ConvertFrom-UEToolSuiteJsoncText -Text (Get-Content -LiteralPath $Path -Raw) -SourceName $Path)
}

function Copy-UEToolSuiteWorkspaceValue {
  [CmdletBinding()]
  param([AllowNull()]$Value)
  if ($null -eq $Value) { return $null }
  $copy = (($Value | ConvertTo-Json -Depth 100 -Compress) | ConvertFrom-Json -AsHashtable -Depth 100)
  if ($Value -is [System.Collections.IList]) { return ,@($copy) }
  return $copy
}

function ConvertTo-UEToolSuiteCanonicalJson {
  [CmdletBinding()]
  param([AllowNull()]$Value)
  if ($null -eq $Value) { return 'null' }
  return ($Value | ConvertTo-Json -Depth 100 -Compress)
}

function Test-UEToolSuiteWorkspaceValueEqual {
  [CmdletBinding()]
  param([AllowNull()]$Left, [AllowNull()]$Right)
  return ((ConvertTo-UEToolSuiteCanonicalJson $Left) -ceq (ConvertTo-UEToolSuiteCanonicalJson $Right))
}

function ConvertFrom-UEToolSuiteJsonPointer {
  [CmdletBinding()]
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Path)
  if ($Path -eq '') { return @() }
  if (-not $Path.StartsWith('/')) { throw "Invalid JSON Pointer '$Path'. Paths must be empty or start with '/'." }
  return @($Path.Substring(1).Split('/') | ForEach-Object {
    if ($_ -match '~(?![01])') { throw "Invalid JSON Pointer '$Path'. A '~' escape must be '~0' or '~1'." }
    ($_ -replace '~1', '/') -replace '~0', '~'
  })
}

function Get-UEToolSuiteWorkspacePointerResult {
  [CmdletBinding()]
  param([AllowNull()]$Root, [Parameter(Mandatory)][AllowEmptyString()][string]$Path)
  $current = $Root
  foreach ($segment in @(ConvertFrom-UEToolSuiteJsonPointer $Path)) {
    if ($current -is [System.Collections.IDictionary]) {
      if (-not $current.Contains($segment)) { return [pscustomobject]@{ Exists = $false; Value = $null } }
      $current = $current[$segment]
      continue
    }
    if ($current -is [System.Collections.IList]) {
      $index = 0
      if (-not [int]::TryParse($segment, [ref]$index) -or $index -lt 0 -or $index -ge $current.Count) {
        return [pscustomobject]@{ Exists = $false; Value = $null }
      }
      $current = $current[$index]
      continue
    }
    return [pscustomobject]@{ Exists = $false; Value = $null }
  }
  return [pscustomobject]@{ Exists = $true; Value = $current }
}

function Set-UEToolSuiteWorkspacePointerValue {
  [CmdletBinding()]
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Root, [Parameter(Mandatory)][AllowEmptyString()][string]$Path, [AllowNull()]$Value)
  $segments = @(ConvertFrom-UEToolSuiteJsonPointer $Path)
  if ($segments.Count -eq 0) { throw 'An operation cannot replace the workspace root.' }
  $current = $Root
  for ($i = 0; $i -lt ($segments.Count - 1); $i++) {
    $segment = $segments[$i]
    if (-not ($current -is [System.Collections.IDictionary])) { throw "Cannot traverse non-object at '$Path'." }
    if (-not $current.Contains($segment)) { $current[$segment] = [ordered]@{} }
    if (-not ($current[$segment] -is [System.Collections.IDictionary])) { throw "Cannot traverse non-object at '$Path'." }
    $current = $current[$segment]
  }
  $current[$segments[-1]] = Copy-UEToolSuiteWorkspaceValue $Value
}

function Remove-UEToolSuiteWorkspacePointerValue {
  [CmdletBinding()]
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Root, [Parameter(Mandatory)][AllowEmptyString()][string]$Path)
  $segments = @(ConvertFrom-UEToolSuiteJsonPointer $Path)
  if ($segments.Count -eq 0) { throw 'An operation cannot remove the workspace root.' }
  $current = $Root
  for ($i = 0; $i -lt ($segments.Count - 1); $i++) {
    if (-not ($current -is [System.Collections.IDictionary]) -or -not $current.Contains($segments[$i])) { return $false }
    $current = $current[$segments[$i]]
  }
  if ($current -is [System.Collections.IDictionary] -and $current.Contains($segments[-1])) {
    $current.Remove($segments[-1]); return $true
  }
  return $false
}

function Get-UEToolSuiteWorkspaceStoragePaths {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$WorkspacePath,
    [string]$ProfileId = 'default'
  )
  if ($ProfileId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw "Invalid workspace settings profile id '$ProfileId'." }
  $localAppData = [string]$env:LOCALAPPDATA
  if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData) }
  if ([string]::IsNullOrWhiteSpace($localAppData)) { throw 'LOCALAPPDATA could not be resolved.' }
  $workspaceIdentity = ([System.IO.Path]::GetFullPath($WorkspacePath)).ToLowerInvariant()
  $sha = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($workspaceIdentity))
  $workspaceId = ([Convert]::ToHexString($sha)).ToLowerInvariant().Substring(0, 24)
  return [pscustomobject]@{
    Team = Join-Path $RepoRoot '.ue-tools\workspace-settings\team.jsonc'
    User = Join-Path $localAppData "UEToolSuite\workspace-settings\profiles\$ProfileId.jsonc"
    Project = Join-Path $RepoRoot '.ue-tools\local\workspace-settings.jsonc'
    Selection = Join-Path $RepoRoot '.ue-tools\local\workspace-profile.json'
    State = Join-Path $RepoRoot ".ue-tools\state\workspace-sync\$workspaceId.json"
    WorkspaceId = $workspaceId
    ProfileId = $ProfileId
  }
}

function Resolve-UEToolSuiteWorkspaceSettingsContext {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot, [string]$WorkspacePath)
  $project = Get-ProjectContext -RepoRoot $RepoRoot -WorkspacePath $WorkspacePath
  if ([string]::IsNullOrWhiteSpace([string]$project.WorkspacePath)) { throw "No .code-workspace file was found under '$RepoRoot'. Pass -WorkspacePath." }
  $profileId = 'default'
  $selectionPath = Join-Path $project.RepoRoot '.ue-tools\local\workspace-profile.json'
  if (Test-Path -LiteralPath $selectionPath -PathType Leaf) {
    $selection = Read-UEToolSuiteWorkspaceJsonFile -Path $selectionPath
    if (-not [string]::IsNullOrWhiteSpace([string]$selection.profileId)) { $profileId = [string]$selection.profileId }
  }
  return [pscustomobject]@{
    Project = $project
    RepoRoot = $project.RepoRoot
    WorkspacePath = $project.WorkspacePath
    Paths = Get-UEToolSuiteWorkspaceStoragePaths -RepoRoot $project.RepoRoot -WorkspacePath $project.WorkspacePath -ProfileId $profileId
  }
}

function New-UEToolSuiteWorkspaceOverlay {
  param([Parameter(Mandatory)][ValidateSet('Team','User','Project')][string]$Scope)
  return [ordered]@{ schemaVersion = 1; scope = $Scope; operations = @() }
}

function ConvertTo-UEToolSuiteMergeLeafOperations {
  param([Parameter(Mandatory)]$Operation)
  if ([string]$Operation.op -ne 'mergeObject') { return @($Operation) }
  if (-not ($Operation.value -is [System.Collections.IDictionary])) { throw "mergeObject at '$($Operation.path)' requires an object value." }
  $leaves=@()
  foreach($key in $Operation.value.Keys){
    $escaped=([string]$key -replace '~','~0') -replace '/','~1';$child=if([string]$Operation.path -eq ''){"/$escaped"}else{"$($Operation.path)/$escaped"};$value=$Operation.value[$key]
    if($value -is [System.Collections.IDictionary]){$leaves+=ConvertTo-UEToolSuiteMergeLeafOperations ([ordered]@{op='mergeObject';path=$child;value=$value})}else{$leaves += [ordered]@{op='set';path=$child;value=Copy-UEToolSuiteWorkspaceValue $value}}
  }
  return @($leaves)
}

function Test-UEToolSuitePortableTeamValue {
  param([AllowNull()]$Value, [string]$OperationPath)
  if ($null -eq $Value) { return }
  if ($Value -is [string]) {
    if ([System.IO.Path]::IsPathRooted($Value) -or $Value -match '^\\\\' -or $Value -match '(?i)https?://') {
      throw "Team operation '$OperationPath' contains a machine-specific absolute path or host: '$Value'. Use User/Project scope or a semantic selector."
    }
    return
  }
  if ($Value -is [System.Collections.IDictionary]) {
    foreach ($key in @($Value.Keys)) {
      if ([string]$key -match '(?i)(password|passwd|secret|token|credential|api[-_]?key|account)') {
        throw "Team operation '$OperationPath' contains sensitive field '$key'."
      }
      if ([string]$key -in @('op','path','selector','identityKey')) { continue }
      Test-UEToolSuitePortableTeamValue -Value $Value[$key] -OperationPath $OperationPath
    }
    return
  }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    foreach ($item in $Value) { Test-UEToolSuitePortableTeamValue -Value $item -OperationPath $OperationPath }
  }
}

function Get-UEToolSuiteWorkspaceLayers {
  [CmdletBinding()]
  param([Parameter(Mandatory)]$Context)
  $layers = @()
  foreach ($item in @(
    [pscustomobject]@{ Scope='Team'; Path=$Context.Paths.Team },
    [pscustomobject]@{ Scope='User'; Path=$Context.Paths.User },
    [pscustomobject]@{ Scope='Project'; Path=$Context.Paths.Project }
  )) {
    $overlay = if (Test-Path -LiteralPath $item.Path -PathType Leaf) { Read-UEToolSuiteWorkspaceJsonFile $item.Path } else { New-UEToolSuiteWorkspaceOverlay $item.Scope }
    if ([int]$overlay.schemaVersion -ne 1) { throw "Unsupported workspace overlay schema in '$($item.Path)': $($overlay.schemaVersion)." }
    if ([string]$overlay.scope -ne $item.Scope) { throw "Workspace overlay '$($item.Path)' declares scope '$($overlay.scope)' but expected '$($item.Scope)'." }
    $expanded=@();foreach($operation in @($overlay.operations)){$expanded+=ConvertTo-UEToolSuiteMergeLeafOperations $operation};$overlay.operations=@($expanded)
    $layers += [pscustomobject]@{ Scope=$item.Scope; Path=$item.Path; Overlay=$overlay }
  }
  return @($layers)
}

function Get-UEToolSuiteWorkspaceOperationIdentity {
  param([Parameter(Mandatory)]$Operation)
  $op = [string]$Operation.op; $path = [string]$Operation.path
  switch ($op) {
    'set' { return "property|$path" }
    'mergeObject' { return "property|$path" }
    'removeProperty' { return "property|$path" }
    'addStringItem' { return "string|$path|$($Operation.value)" }
    'removeStringItem' { return "string|$path|$($Operation.value)" }
    'upsertKeyedItem' { return "keyed|$path|$($Operation.identityKey)|$($Operation.identityValue)" }
    'removeKeyedItem' { return "keyed|$path|$($Operation.identityKey)|$($Operation.identityValue)" }
    'removeSemantic' { return "semantic|$path|$($Operation.selector)" }
    default { throw "Unknown workspace settings operation '$op' at '$path'." }
  }
}

function Assert-UEToolSuiteWorkspaceLayersValid {
  [CmdletBinding()]
  param([Parameter(Mandatory)][object[]]$Layers)
  $seen = @{}
  $propertyOwners = @()
  foreach ($layer in $Layers) {
    $localSeen = @{}
    foreach ($op in @($layer.Overlay.operations)) {
      $path = [string]$op.path; [void](ConvertFrom-UEToolSuiteJsonPointer $path)
      $identity = Get-UEToolSuiteWorkspaceOperationIdentity $op
      if ($identity.StartsWith('property|')) {
        foreach ($owner in $propertyOwners) {
          if ($owner.Path -ne $path -and ($path.StartsWith($owner.Path + '/') -or $owner.Path.StartsWith($path + '/'))) {
            throw "Overlapping incompatible property ownership between '$($owner.Path)' ($($owner.Scope)) and '$path' ($($layer.Scope)). Own object leaves separately."
          }
        }
        $propertyOwners += [pscustomobject]@{ Path = $path; Scope = $layer.Scope }
      }
      if ($localSeen.ContainsKey($identity)) { throw "Duplicate ownership in $($layer.Scope) overlay for '$identity'." }
      $localSeen[$identity] = [string]$op.op
      if ($seen.ContainsKey($identity)) {
        $prior = $seen[$identity]
        $removalKinds = @('removeProperty','removeStringItem','removeKeyedItem','removeSemantic')
        if (($prior.Op -in $removalKinds) -xor ([string]$op.op -in $removalKinds)) {
          throw "Contradictory ownership for '$identity' between $($prior.Scope) and $($layer.Scope). Remove or move one operation."
        }
      }
      $seen[$identity] = [pscustomobject]@{ Scope=$layer.Scope; Op=[string]$op.op }
      if ([string]$op.op -in @('upsertKeyedItem','removeKeyedItem')) {
        if ([string]::IsNullOrWhiteSpace([string]$op.identityKey) -or [string]::IsNullOrWhiteSpace([string]$op.identityValue)) {
          throw "Keyed array operation at '$path' requires identityKey and identityValue."
        }
        if ($script:UEToolSuiteWorkspaceArrayIdentities.ContainsKey($path) -and $script:UEToolSuiteWorkspaceArrayIdentities[$path] -ne [string]$op.identityKey) {
          throw "Array '$path' uses identity '$($script:UEToolSuiteWorkspaceArrayIdentities[$path])', not '$($op.identityKey)'."
        }
      }
      if ([string]$op.op -eq 'removeSemantic' -and ([string]$op.selector -ne 'activeUnrealEngineRoot')) {
        throw "Unknown semantic selector '$($op.selector)' at '$path'."
      }
      if ($layer.Scope -eq 'Team') { Test-UEToolSuitePortableTeamValue -Value $op -OperationPath $path }
    }
  }
}

function Get-UEToolSuiteNormalizedWindowsPath {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$BasePath)
  $resolved = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $BasePath $Path }
  return ([System.IO.Path]::GetFullPath($resolved).Replace('/','\').TrimEnd('\')).ToLowerInvariant()
}

function Get-UEToolSuiteSemanticMatches {
  param([Parameter(Mandatory)]$Workspace, [Parameter(Mandatory)]$Context, [Parameter(Mandatory)]$Operation)
  if ([string]$Operation.selector -ne 'activeUnrealEngineRoot' -or [string]$Operation.path -ne '/folders') {
    throw "Unsupported semantic selector '$($Operation.selector)' at '$($Operation.path)'."
  }
  $attempts = [System.Collections.Generic.List[string]]::new()
  $engineRoot = Resolve-UnrealEngineRoot -ProjectContext $Context.Project -WorkspacePath $Context.WorkspacePath -Attempts $attempts
  if ([string]::IsNullOrWhiteSpace($engineRoot)) { throw "Could not resolve the active Unreal Engine root for semantic workspace removal. $($attempts -join '; ')" }
  $engine = Get-UEToolSuiteNormalizedWindowsPath -Path $engineRoot -BasePath $Context.RepoRoot
  $matches = @()
  $foldersResult = Get-UEToolSuiteWorkspacePointerResult $Workspace '/folders'
  if ($foldersResult.Exists) {
    for ($i=0; $i -lt @($foldersResult.Value).Count; $i++) {
      $folder = @($foldersResult.Value)[$i]
      if (-not ($folder -is [System.Collections.IDictionary]) -or [string]::IsNullOrWhiteSpace([string]$folder.path)) { continue }
      $candidate = Get-UEToolSuiteNormalizedWindowsPath -Path ([string]$folder.path) -BasePath (Split-Path -Parent $Context.WorkspacePath)
      $engineSource = "$engine\engine"
      if ($candidate -eq $engine -or $candidate -eq $engineSource) { $matches += $i }
    }
  }
  if ($matches.Count -gt 1) { throw "Semantic selector 'activeUnrealEngineRoot' matched $($matches.Count) workspace folders. Remove the duplicate or use an explicit keyed operation." }
  return [pscustomobject]@{ Indices=@($matches); EngineRoot=$engineRoot }
}

function Get-UEToolSuiteArrayIndexByIdentity {
  param([object[]]$Items, [string]$IdentityKey, [string]$IdentityValue, [string]$Path, [Parameter(Mandatory)]$Context)
  $matches = @()
  for($i=0;$i -lt $Items.Count;$i++) {
    $item=$Items[$i]; if(-not ($item -is [System.Collections.IDictionary]) -or -not $item.Contains($IdentityKey)){continue}
    $actual=[string]$item[$IdentityKey]
    $equal = if ($Path -eq '/folders' -and $IdentityKey -eq 'path') {
      (Get-UEToolSuiteNormalizedWindowsPath $actual (Split-Path -Parent $Context.WorkspacePath)) -eq (Get-UEToolSuiteNormalizedWindowsPath $IdentityValue (Split-Path -Parent $Context.WorkspacePath))
    } else { $actual -ceq $IdentityValue }
    if($equal){$matches += $i}
  }
  if($matches.Count -gt 1){throw "Identity collision at '$Path': $IdentityKey == '$IdentityValue' matched $($matches.Count) items."}
  return $(if($matches.Count -eq 1){$matches[0]}else{-1})
}

function Invoke-UEToolSuiteWorkspaceOperation {
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Workspace, [Parameter(Mandatory)]$Operation, [Parameter(Mandatory)]$Context)
  $path=[string]$Operation.path
  switch ([string]$Operation.op) {
    'set' { Set-UEToolSuiteWorkspacePointerValue $Workspace $path $Operation.value; return }
    'mergeObject' {
      $current=Get-UEToolSuiteWorkspacePointerResult $Workspace $path
      if(-not $current.Exists){Set-UEToolSuiteWorkspacePointerValue $Workspace $path ([ordered]@{});$current=Get-UEToolSuiteWorkspacePointerResult $Workspace $path}
      if(-not ($current.Value -is [System.Collections.IDictionary]) -or -not ($Operation.value -is [System.Collections.IDictionary])){throw "mergeObject at '$path' requires objects."}
      foreach($key in $Operation.value.Keys){$current.Value[$key]=Copy-UEToolSuiteWorkspaceValue $Operation.value[$key]}; return
    }
    'removeProperty' { [void](Remove-UEToolSuiteWorkspacePointerValue $Workspace $path); return }
    'addStringItem' { $r=Get-UEToolSuiteWorkspacePointerResult $Workspace $path; $items=if($r.Exists){@($r.Value)}else{@()}; if(@($items|Where-Object{[string]$_ -ceq [string]$Operation.value}).Count -eq 0){$items+= [string]$Operation.value}; Set-UEToolSuiteWorkspacePointerValue $Workspace $path @($items); return }
    'removeStringItem' { $r=Get-UEToolSuiteWorkspacePointerResult $Workspace $path; if($r.Exists){$items=@($r.Value|Where-Object{[string]$_ -cne [string]$Operation.value});Set-UEToolSuiteWorkspacePointerValue $Workspace $path @($items)}; return }
    'upsertKeyedItem' { $r=Get-UEToolSuiteWorkspacePointerResult $Workspace $path;$items=if($r.Exists){@($r.Value)}else{@()};$idx=Get-UEToolSuiteArrayIndexByIdentity $items ([string]$Operation.identityKey) ([string]$Operation.identityValue) $path $Context;if($idx -ge 0){$items[$idx]=Copy-UEToolSuiteWorkspaceValue $Operation.value}else{$items+=Copy-UEToolSuiteWorkspaceValue $Operation.value};Set-UEToolSuiteWorkspacePointerValue $Workspace $path @($items);return }
    'removeKeyedItem' { $r=Get-UEToolSuiteWorkspacePointerResult $Workspace $path;if($r.Exists){$items=@($r.Value);$idx=Get-UEToolSuiteArrayIndexByIdentity $items ([string]$Operation.identityKey) ([string]$Operation.identityValue) $path $Context;if($idx -ge 0){$items=@($items|ForEach-Object -Begin{$j=0}-Process{if($j -ne $idx){$_};$j++});Set-UEToolSuiteWorkspacePointerValue $Workspace $path @($items)}};return }
    'removeSemantic' { $match=Get-UEToolSuiteSemanticMatches $Workspace $Context $Operation;if($match.Indices.Count -eq 1){$r=Get-UEToolSuiteWorkspacePointerResult $Workspace $path;$idx=$match.Indices[0];$items=@($r.Value|ForEach-Object -Begin{$j=0}-Process{if($j -ne $idx){$_};$j++});Set-UEToolSuiteWorkspacePointerValue $Workspace $path @($items)};return }
    default { throw "Unknown workspace operation '$($Operation.op)'." }
  }
}

function Get-UEToolSuiteWorkspacePlan {
  [CmdletBinding()]
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Pristine, [AllowNull()]$PreviousPristine, [Parameter(Mandatory)][object[]]$Layers, [Parameter(Mandatory)]$Context)
  Assert-UEToolSuiteWorkspaceLayersValid $Layers
  $effective=Copy-UEToolSuiteWorkspaceValue $Pristine;$conflicts=@();$changes=@();$seen=@{}
  foreach($layer in $Layers){foreach($op in @($layer.Overlay.operations)){
    $identity=Get-UEToolSuiteWorkspaceOperationIdentity $op
    $nonRemoval=[string]$op.op -in @('set','mergeObject','addStringItem','upsertKeyedItem')
    if($nonRemoval -and $null -ne $PreviousPristine){
      $old=Get-UEToolSuiteWorkspacePointerResult $PreviousPristine ([string]$op.path);$new=Get-UEToolSuiteWorkspacePointerResult $Pristine ([string]$op.path)
      if([string]$op.op -eq 'upsertKeyedItem'){
        $oldItems=if($old.Exists){@($old.Value)}else{@()};$newItems=if($new.Exists){@($new.Value)}else{@()}
        $oldIndex=Get-UEToolSuiteArrayIndexByIdentity $oldItems ([string]$op.identityKey) ([string]$op.identityValue) ([string]$op.path) $Context
        $newIndex=Get-UEToolSuiteArrayIndexByIdentity $newItems ([string]$op.identityKey) ([string]$op.identityValue) ([string]$op.path) $Context
        $old=[pscustomobject]@{Exists=($oldIndex-ge0);Value=$(if($oldIndex-ge0){$oldItems[$oldIndex]}else{$null})};$new=[pscustomobject]@{Exists=($newIndex-ge0);Value=$(if($newIndex-ge0){$newItems[$newIndex]}else{$null})}
      }
      elseif([string]$op.op -eq 'addStringItem'){
        $oldItems=if($old.Exists){@($old.Value)}else{@()};$newItems=if($new.Exists){@($new.Value)}else{@()};$oldPresent=@($oldItems|Where-Object{[string]$_ -ceq [string]$op.value}).Count-gt0;$newPresent=@($newItems|Where-Object{[string]$_ -ceq [string]$op.value}).Count-gt0;$old=[pscustomobject]@{Exists=$oldPresent;Value=$oldPresent};$new=[pscustomobject]@{Exists=$newPresent;Value=$newPresent}
      }
      $changed=($old.Exists -ne $new.Exists) -or ($old.Exists -and -not (Test-UEToolSuiteWorkspaceValueEqual $old.Value $new.Value))
      if($changed){$conflicts += [pscustomobject]@{Path=[string]$op.path;PreviousUE=$(if($old.Exists){$old.Value}else{$null});NewUE=$(if($new.Exists){$new.Value}else{$null});Layer=$layer.Scope;Operation=$op;Resolution="Review Unreal's new value, then run settings capture to update ownership or remove the operation."};continue}
    }
    Invoke-UEToolSuiteWorkspaceOperation $effective $op $Context
    $changes += [pscustomobject]@{Layer=$layer.Scope;Operation=[string]$op.op;Path=[string]$op.path;Identity=$identity}
    $seen[$identity]=$layer.Scope
  }}
  return [pscustomobject]@{WorkspacePath=$Context.WorkspacePath;Layers=@($Layers|ForEach-Object{$_.Path});Effective=$effective;Changes=@($changes);Conflicts=@($conflicts);HasConflicts=($conflicts.Count -gt 0)}
}

function ConvertTo-UEToolSuiteWorkspaceFileText { param($Value,[string]$NewLine="`r`n") return (($Value|ConvertTo-Json -Depth 100) -replace "`r?`n",$NewLine)+$NewLine }

function Invoke-UEToolSuiteAtomicTextTransaction {
  [CmdletBinding()]
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Writes)
  $staged=@();$original=@{}
  try{
    foreach($path in $Writes.Keys){$parent=Split-Path -Parent $path;if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Force -Path $parent|Out-Null};$original[$path]=if(Test-Path -LiteralPath $path -PathType Leaf){[System.IO.File]::ReadAllBytes($path)}else{$null};$tmp=Join-Path $parent ('.'+[IO.Path]::GetFileName($path)+'.uetools-'+[guid]::NewGuid().ToString('N')+'.tmp');[IO.File]::WriteAllText($tmp,[string]$Writes[$path],[Text.UTF8Encoding]::new($false));$staged+=@($path,$tmp)}
    for($i=0;$i -lt $staged.Count;$i+=2){[IO.File]::Move($staged[$i+1],$staged[$i],$true)}
  }catch{
    foreach($path in $original.Keys){if($null -eq $original[$path]){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}}else{[IO.File]::WriteAllBytes($path,$original[$path])}}
    throw
  }finally{for($i=1;$i -lt $staged.Count;$i+=2){if(Test-Path -LiteralPath $staged[$i]){Remove-Item -LiteralPath $staged[$i] -Force}}}
}

function Get-UEToolSuiteWorkspaceState {
  param([Parameter(Mandatory)]$Context)
  if (-not (Test-Path -LiteralPath $Context.Paths.State -PathType Leaf)) { return $null }
  $state = Read-UEToolSuiteWorkspaceJsonFile $Context.Paths.State
  if (-not ($state -is [System.Collections.IDictionary])) {
    throw "Malformed workspace provenance ledger '$($Context.Paths.State)': the root must be an object."
  }
  if ([int]$state.schemaVersion -ne 1) {
    throw "Unsupported workspace state schema in '$($Context.Paths.State)': $($state.schemaVersion)."
  }
  if ([string]$state.workspaceId -ne $Context.Paths.WorkspaceId) {
    throw "Stale workspace provenance ledger '$($Context.Paths.State)': workspaceId does not match '$($Context.WorkspacePath)'. Move the stale file aside, then run 'ue settings adopt'."
  }
  if ([string]::IsNullOrWhiteSpace([string]$state.workspacePath) -or
      -not [string]::Equals([string]$state.workspacePath, [string]$Context.WorkspacePath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Stale workspace provenance ledger '$($Context.Paths.State)': workspacePath does not match '$($Context.WorkspacePath)'. Move the stale file aside, then run 'ue settings adopt'."
  }
  foreach ($field in @('pristine','effective')) {
    if (-not $state.Contains($field) -or -not ($state[$field] -is [System.Collections.IDictionary])) {
      throw "Malformed workspace provenance ledger '$($Context.Paths.State)': '$field' must be a workspace object. Restore a valid ledger or move it aside and run 'ue settings adopt'."
    }
  }
  return $state
}
function New-UEToolSuiteWorkspaceState { param($Context,$Pristine,$Effective) return [ordered]@{schemaVersion=1;workspaceId=$Context.Paths.WorkspaceId;workspacePath=$Context.WorkspacePath;profileId=$Context.Paths.ProfileId;updatedUtc=[DateTime]::UtcNow.ToString('o');pristine=Copy-UEToolSuiteWorkspaceValue $Pristine;effective=Copy-UEToolSuiteWorkspaceValue $Effective} }

function Write-UEToolSuiteWorkspacePlanSummary {
  param([Parameter(Mandatory)]$Plan,[switch]$DryRun)
  Write-Output "Workspace: $($Plan.WorkspacePath)";Write-Output "Layers:";foreach($p in $Plan.Layers){Write-Output "  $p"}
  foreach($c in $Plan.Changes){Write-Output ("  {0}: {1} {2} ({3})" -f $c.Layer,$c.Operation,$c.Path,$c.Identity)}
  foreach($c in $Plan.Conflicts){Write-Output "CONFLICT $($c.Path) [$($c.Layer)]";Write-Output "  previous UE: $(ConvertTo-UEToolSuiteCanonicalJson $c.PreviousUE)";Write-Output "  new UE: $(ConvertTo-UEToolSuiteCanonicalJson $c.NewUE)";Write-Output "  custom: $(ConvertTo-UEToolSuiteCanonicalJson $c.Operation)";Write-Output "  resolve: $($c.Resolution)"}
  if($null-ne$Plan.PSObject.Properties['StateWouldChange']){Write-Output "Baseline/state update: $(if($Plan.StateWouldChange){'yes'}else{'no'})"}
  Write-Output $(if($DryRun){'Dry run: no workspace, overlay, state, selection, or backup file was changed.'}else{'Workspace settings synchronization completed.'})
}

function Invoke-UEToolSuiteWorkspaceSync {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[string]$WorkspacePath,[switch]$DryRun,[switch]$NonInteractive,[AllowNull()][System.Collections.IDictionary]$PristineOverride,[AllowNull()]$PreviousWorkspaceContent)
  $context=Resolve-UEToolSuiteWorkspaceSettingsContext $RepoRoot $WorkspacePath;$layers=Get-UEToolSuiteWorkspaceLayers $context;$state=Get-UEToolSuiteWorkspaceState $context
  $live=if($null -ne $PristineOverride){Copy-UEToolSuiteWorkspaceValue $PristineOverride}else{Read-UEToolSuiteWorkspaceJsonFile $context.WorkspacePath}
  if($null -eq $state){if($null -eq $PreviousWorkspaceContent){throw "No workspace provenance ledger exists. Run 'ue settings adopt', or run a normal regeneration-enabled build to initialize an unchanged workspace."};$previous=ConvertFrom-UEToolSuiteJsoncText $PreviousWorkspaceContent $context.WorkspacePath;if(-not(Test-UEToolSuiteWorkspaceValueEqual $previous $live)){throw "Workspace changed during first provenance-aware regeneration, but no ledger exists. The original workspace was restored. Run 'ue settings adopt' to review and classify existing customization."}}
  $candidatePristine=if($state -and (Test-UEToolSuiteWorkspaceValueEqual $live $state.effective)){$state.pristine}else{$live}
  $previousPristine=if($state){$state.pristine}else{$null};$plan=Get-UEToolSuiteWorkspacePlan $candidatePristine $previousPristine $layers $context
  if($plan.HasConflicts){Write-UEToolSuiteWorkspacePlanSummary $plan -DryRun:$DryRun;throw "Workspace settings synchronization has $($plan.Conflicts.Count) conflict(s); nothing was written."}
  $stateMatches = (
    $null -ne $state -and
    (Test-UEToolSuiteWorkspaceValueEqual $state.pristine $candidatePristine) -and
    (Test-UEToolSuiteWorkspaceValueEqual $state.effective $plan.Effective) -and
    ([string]$state.profileId -eq $context.Paths.ProfileId) -and
    ([string]$state.workspacePath -eq $context.WorkspacePath)
  )
  $plan | Add-Member -NotePropertyName StateWouldChange -NotePropertyValue (-not $stateMatches)
  $newState=New-UEToolSuiteWorkspaceState $context $candidatePristine $plan.Effective
  if(-not $DryRun){$newline=if((Get-Content -LiteralPath $context.WorkspacePath -Raw) -match "`r`n"){"`r`n"}else{"`n"};$writes=[ordered]@{};if(-not(Test-UEToolSuiteWorkspaceValueEqual (Read-UEToolSuiteWorkspaceJsonFile $context.WorkspacePath) $plan.Effective)){$writes[$context.WorkspacePath]=ConvertTo-UEToolSuiteWorkspaceFileText $plan.Effective $newline};if(-not$stateMatches){$writes[$context.Paths.State]=ConvertTo-UEToolSuiteWorkspaceFileText $newState "`n"};if($writes.Count-gt0){Invoke-UEToolSuiteAtomicTextTransaction $writes}}
  Write-UEToolSuiteWorkspacePlanSummary $plan -DryRun:$DryRun;return $plan
}

function Get-UEToolSuiteWorkspaceArrayChanges {
  param($Before,$After,[string]$Path,$Context)
  $beforeItems=[System.Collections.Generic.List[object]]::new();if($null-ne$Before){foreach($item in $Before){[void]$beforeItems.Add($item)}}
  $afterItems=[System.Collections.Generic.List[object]]::new();if($null-ne$After){foreach($item in $After){[void]$afterItems.Add($item)}}
  $allItems=[System.Collections.Generic.List[object]]::new();foreach($item in $beforeItems){[void]$allItems.Add($item)};foreach($item in $afterItems){[void]$allItems.Add($item)}
  if(@($allItems|Where-Object{$_ -isnot [string]}).Count-eq0){$ops=@();foreach($item in $beforeItems){if(@($afterItems|Where-Object{[string]$_ -ceq [string]$item}).Count-eq0){$ops += [ordered]@{op='removeStringItem';path=$Path;value=[string]$item}}};foreach($item in $afterItems){if(@($beforeItems|Where-Object{[string]$_ -ceq [string]$item}).Count-eq0){$ops += [ordered]@{op='addStringItem';path=$Path;value=[string]$item}}};return @($ops)}
  if(-not $script:UEToolSuiteWorkspaceArrayIdentities.ContainsKey($Path)){throw "Array change at '$Path' has no known identity strategy. Specify a supported keyed array or edit the overlay with an explicit identityKey."}
  $key=$script:UEToolSuiteWorkspaceArrayIdentities[$Path];$ops=@()
  foreach($item in $beforeItems){$id=[string]$item[$key];$idx=Get-UEToolSuiteArrayIndexByIdentity $afterItems $key $id $Path $Context;if($idx -lt 0){
    if($Path -eq '/folders'){$semantic=[ordered]@{op='removeSemantic';path='/folders';selector='activeUnrealEngineRoot'};try{$probe=Copy-UEToolSuiteWorkspaceValue ([ordered]@{folders=@($item)});if((Get-UEToolSuiteSemanticMatches $probe $Context $semantic).Indices.Count -eq 1){$ops+=$semantic;continue}}catch{}}
    $ops += [ordered]@{op='removeKeyedItem';path=$Path;identityKey=$key;identityValue=$id}
  }}
  foreach($item in $afterItems){$id=[string]$item[$key];$idx=Get-UEToolSuiteArrayIndexByIdentity $beforeItems $key $id $Path $Context;if($idx -lt 0 -or -not(Test-UEToolSuiteWorkspaceValueEqual $beforeItems[$idx] $item)){$ops += [ordered]@{op='upsertKeyedItem';path=$Path;identityKey=$key;identityValue=$id;value=Copy-UEToolSuiteWorkspaceValue $item}}}
  return @($ops)
}

function Get-UEToolSuiteWorkspaceDiffAtPath {
  param($Before,$After,[string]$Path,$Context)
  $a=Get-UEToolSuiteWorkspacePointerResult $Before $Path;$b=Get-UEToolSuiteWorkspacePointerResult $After $Path
  if(-not$a.Exists -and -not$b.Exists){return @()};if($a.Exists -and -not$b.Exists){return @([ordered]@{op='removeProperty';path=$Path})}
  if($b.Value -is [System.Collections.IList]){return @(Get-UEToolSuiteWorkspaceArrayChanges -Before $(if($a.Exists){$a.Value}else{@()}) -After $b.Value -Path $Path -Context $Context)}
  if($b.Value -is [System.Collections.IDictionary]){$ops=@();$keys=@();if($a.Exists -and $a.Value -is [System.Collections.IDictionary]){$keys+=@($a.Value.Keys)};$keys+=@($b.Value.Keys);foreach($key in @($keys|Sort-Object -Unique)){$escaped=([string]$key -replace '~','~0') -replace '/','~1';$child=if($Path-eq''){"/$escaped"}else{"$Path/$escaped"};$ops+=Get-UEToolSuiteWorkspaceDiffAtPath $Before $After $child $Context};return @($ops)}
  if(-not$a.Exists -or -not(Test-UEToolSuiteWorkspaceValueEqual $a.Value $b.Value)){return @([ordered]@{op='set';path=$Path;value=Copy-UEToolSuiteWorkspaceValue $b.Value})};return @()
}

function Get-UEToolSuiteWorkspaceCaptureOperations {
  param($Before,$After,[string[]]$Paths,$Context)
  $pathsToCompare=[System.Collections.Generic.List[string]]::new()
  foreach($selectedPath in @($Paths)){[void]$pathsToCompare.Add([string]$selectedPath)}
  if($pathsToCompare.Count -eq 0){[void]$pathsToCompare.Add('')}
  $ops=@();foreach($path in $pathsToCompare){[void](ConvertFrom-UEToolSuiteJsonPointer $path);$ops+=Get-UEToolSuiteWorkspaceDiffAtPath $Before $After $path $Context};return @($ops)
}

function Test-UEToolSuiteWorkspaceConfiguration {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[string]$WorkspacePath)
  $context=Resolve-UEToolSuiteWorkspaceSettingsContext $RepoRoot $WorkspacePath;$layers=Get-UEToolSuiteWorkspaceLayers $context;Assert-UEToolSuiteWorkspaceLayersValid $layers;[void](Get-UEToolSuiteWorkspaceState $context);return $context
}

function Set-UEToolSuiteWorkspaceCapturedOperations {
  param($Context,[ValidateSet('Team','User','Project')][string]$Scope,[object[]]$Operations,[switch]$DryRun)
  $layers=Get-UEToolSuiteWorkspaceLayers $Context;$layer=@($layers|Where-Object Scope -eq $Scope)[0];$overlay=$layer.Overlay;$identities=@{};foreach($op in @($Operations)){$identities[(Get-UEToolSuiteWorkspaceOperationIdentity $op)]=$op};$retained=@($overlay.operations|Where-Object{-not$identities.ContainsKey((Get-UEToolSuiteWorkspaceOperationIdentity $_))});$overlay.operations=@($retained+@($Operations));$updatedLayers=@($layers|ForEach-Object{if($_.Scope -eq $Scope){[pscustomobject]@{Scope=$_.Scope;Path=$_.Path;Overlay=$overlay}}else{$_}});Assert-UEToolSuiteWorkspaceLayersValid $updatedLayers;if(-not$DryRun){$writes=[ordered]@{};$writes[$layer.Path]=ConvertTo-UEToolSuiteWorkspaceFileText $overlay "`n";Invoke-UEToolSuiteAtomicTextTransaction $writes};return [pscustomobject]@{Operations=@($Operations);Overlay=$overlay;OverlayPath=$layer.Path;Layers=$updatedLayers}
}

function Invoke-UEToolSuiteWorkspaceCapture {
  param([string]$RepoRoot,[string]$WorkspacePath,[ValidateSet('Team','User','Project')][string]$Scope,[string[]]$Path,[switch]$DryRun,[switch]$NonInteractive)
  $hasExplicitPaths=$null-ne$Path-and$Path.Count-gt0
  if($NonInteractive -and -not$hasExplicitPaths){throw 'settings capture -NonInteractive requires at least one explicit -Path.'};$selectInteractively=-not$hasExplicitPaths
  $context=Resolve-UEToolSuiteWorkspaceSettingsContext $RepoRoot $WorkspacePath;$state=Get-UEToolSuiteWorkspaceState $context;if(-not$state){throw "No workspace provenance ledger exists. Run 'ue settings adopt' first."};$live=Read-UEToolSuiteWorkspaceJsonFile $context.WorkspacePath;$ops=@(Get-UEToolSuiteWorkspaceCaptureOperations -Before $state.effective -After $live -Paths $Path -Context $context);if($ops.Count -eq 0){$selection=if($selectInteractively){'the whole workspace'}else{($Path -join ', ')};Write-Output "No workspace changes were found relative to the last effective state for $selection.";Write-Output "Workspace: $($context.WorkspacePath)";Write-Output "State: $($context.Paths.State)";Write-Output "If a change was expected, save the workspace and run 'ue settings status' to verify drift.";return}
  if($selectInteractively){for($i=0;$i-lt$ops.Count;$i++){$kind=if([string]$ops[$i].op -like 'remove*'){'REMOVAL'}else{if((Get-UEToolSuiteWorkspacePointerResult $state.effective ([string]$ops[$i].path)).Exists){'MODIFICATION'}else{'ADDITION'}};Write-Output "[$($i+1)] $kind $($ops[$i].op) $($ops[$i].path)"};$answer=Read-Host "Select change numbers for $Scope (comma-separated, or 'all')";if($answer.Trim().ToLowerInvariant() -ne 'all'){$selected=@();foreach($token in @($answer-split ',')){$index=0;if([int]::TryParse($token.Trim(),[ref]$index)-and$index-ge1-and$index-le$ops.Count){$selected+=$ops[$index-1]}};$ops=@($selected);if($ops.Count-eq0){throw 'No workspace changes were selected; nothing was written.'}}}
  foreach($op in $ops){Write-Output "Capture [$Scope]: $($op.op) $($op.path)"};$captured=Set-UEToolSuiteWorkspaceCapturedOperations $context $Scope $ops -DryRun;if(-not$DryRun){$plan=Get-UEToolSuiteWorkspacePlan $state.pristine $state.pristine $captured.Layers $context;if($plan.HasConflicts){throw 'Captured workspace operations conflict with the stored pristine baseline; no files were written.'};$newState=New-UEToolSuiteWorkspaceState $context $state.pristine $plan.Effective;$writes=[ordered]@{};$writes[$captured.OverlayPath]=ConvertTo-UEToolSuiteWorkspaceFileText $captured.Overlay "`n";$writes[$context.WorkspacePath]=ConvertTo-UEToolSuiteWorkspaceFileText $plan.Effective;$writes[$context.Paths.State]=ConvertTo-UEToolSuiteWorkspaceFileText $newState "`n";Invoke-UEToolSuiteAtomicTextTransaction $writes}
}

function Invoke-UEToolSuiteWorkspaceAdopt {
  param([string]$RepoRoot,[string]$WorkspacePath,[ValidateSet('Team','User','Project')][string]$Scope,[string[]]$Path,[switch]$DryRun,[switch]$NonInteractive)
  $hasExplicitPaths=$null-ne$Path-and$Path.Count-gt0
  if($NonInteractive -and (-not$hasExplicitPaths -or [string]::IsNullOrWhiteSpace($Scope))){throw 'settings adopt -NonInteractive requires explicit -Scope and at least one -Path.'}
  if([string]::IsNullOrWhiteSpace($Scope)){$requestedScope=(Read-Host 'Adoption scope (Team, User, or Project)').Trim();if($requestedScope -notin @('Team','User','Project')){throw "Invalid adoption scope '$requestedScope'."};$Scope=$requestedScope}
  $selectInteractively=-not$hasExplicitPaths
  $context=Resolve-UEToolSuiteWorkspaceSettingsContext $RepoRoot $WorkspacePath;if(Get-UEToolSuiteWorkspaceState $context){throw 'A workspace provenance ledger already exists; use settings capture or remove the state file to rebuild it.'};$original=Get-Content -LiteralPath $context.WorkspacePath -Raw
  if($DryRun){Write-Output "Workspace: $($context.WorkspacePath)";Write-Output "Adoption scope: $Scope";Write-Output "Selected paths: $($Path -join ', ')";Write-Output 'Adoption would snapshot the current workspace, regenerate pristine Unreal project files, classify the selected paths, and atomically write overlay/workspace/state. Dry run did not regenerate or write any file.';return}
  try{Invoke-UEToolSuiteUnrealBuild -RepoRoot $context.RepoRoot -CommandArguments @('-NoBuild','-SkipSettingsSync','-NonInteractive','-WorkspacePath',$context.WorkspacePath);$pristine=Read-UEToolSuiteWorkspaceJsonFile $context.WorkspacePath;$old=ConvertFrom-UEToolSuiteJsoncText $original $context.WorkspacePath;$ops=@(Get-UEToolSuiteWorkspaceCaptureOperations -Before $pristine -After $old -Paths $Path -Context $context);if($selectInteractively){for($i=0;$i-lt$ops.Count;$i++){$kind=if([string]$ops[$i].op-like'remove*'){'REMOVAL'}else{if((Get-UEToolSuiteWorkspacePointerResult $pristine ([string]$ops[$i].path)).Exists){'MODIFICATION'}else{'ADDITION'}};Write-Output "[$($i+1)] $kind $($ops[$i].op) $($ops[$i].path)"};$answer=Read-Host "Select changes to adopt into $Scope (comma-separated, or 'all')";if($answer.Trim().ToLowerInvariant()-ne'all'){$selected=@();foreach($token in @($answer-split',')){$index=0;if([int]::TryParse($token.Trim(),[ref]$index)-and$index-ge1-and$index-le$ops.Count){$selected+=$ops[$index-1]}};$ops=@($selected);if($ops.Count-eq0){throw 'No adoption candidates were selected; the original workspace was restored.'}}};$captured=Set-UEToolSuiteWorkspaceCapturedOperations $context $Scope $ops -DryRun;$plan=Get-UEToolSuiteWorkspacePlan $pristine $null $captured.Layers $context;if($plan.HasConflicts){throw 'Adoption produced conflicts.'};$state=New-UEToolSuiteWorkspaceState $context $pristine $plan.Effective;$writes=[ordered]@{};$writes[$captured.OverlayPath]=ConvertTo-UEToolSuiteWorkspaceFileText $captured.Overlay "`n";$writes[$context.WorkspacePath]=ConvertTo-UEToolSuiteWorkspaceFileText $plan.Effective;$writes[$context.Paths.State]=ConvertTo-UEToolSuiteWorkspaceFileText $state "`n";Invoke-UEToolSuiteAtomicTextTransaction $writes;Write-Output "Adopted $($ops.Count) operation(s) into $Scope scope."}catch{[IO.File]::WriteAllText($context.WorkspacePath,$original,[Text.UTF8Encoding]::new($false));throw}
}

function Invoke-UEToolSuiteWorkspaceStatus {
  param([string]$RepoRoot,[string]$WorkspacePath)
  $context=Resolve-UEToolSuiteWorkspaceSettingsContext $RepoRoot $WorkspacePath;$layers=Get-UEToolSuiteWorkspaceLayers $context;$state=Get-UEToolSuiteWorkspaceState $context;Write-Output "Workspace: $($context.WorkspacePath)";Write-Output "Profile: $($context.Paths.ProfileId)";Write-Output "State: $(if($state){$context.Paths.State}else{'missing (run settings adopt or build)'})";foreach($layer in $layers){Write-Output "$($layer.Scope): $($layer.Path) [$(@($layer.Overlay.operations).Count) operations]";foreach($op in @($layer.Overlay.operations)){Write-Output "  $($op.op) $($op.path)"}};if($state){$live=Read-UEToolSuiteWorkspaceJsonFile $context.WorkspacePath;$drift=-not(Test-UEToolSuiteWorkspaceValueEqual $live $state.effective);Write-Output "Drift: $(if($drift){'live workspace differs from last effective state'}else{'none'})";$candidate=if($drift){$live}else{$state.pristine};$plan=Get-UEToolSuiteWorkspacePlan $candidate $state.pristine $layers $context;Write-Output "Conflicts: $($plan.Conflicts.Count)";foreach($conflict in $plan.Conflicts){Write-Output "  $($conflict.Path) [$($conflict.Layer)] - $($conflict.Resolution)"}}
}

function ConvertTo-UEToolSuiteSettingsCommandParameters {
  param(
    [string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('sync','capture','adopt','status')][string]$Subcommand,
    [string[]]$Arguments
  )

  $allowedOptions = @{
    sync = @('reporoot','workspacepath','dryrun','noninteractive')
    capture = @('reporoot','workspacepath','scope','path','dryrun','noninteractive')
    adopt = @('reporoot','workspacepath','scope','path','dryrun','noninteractive')
    status = @('reporoot','workspacepath')
  }
  $valueOptions = @('reporoot','workspacepath','scope','path')
  $switchOptions = @('dryrun','noninteractive')
  $parameters = @{ RepoRoot = $RepoRoot }

  for ($i = 0; $i -lt @($Arguments).Count;) {
    $token = [string]$Arguments[$i]
    $option = $token.TrimStart('-','/').ToLowerInvariant()
    if ($option -notin @($valueOptions + $switchOptions)) {
      throw "Unknown settings option '$token'. Run 'ue settings $Subcommand help'."
    }
    if ($option -notin $allowedOptions[$Subcommand]) {
      throw "Option '$token' is not valid for 'settings $Subcommand'. Run 'ue settings $Subcommand help'."
    }
    if ($option -in $switchOptions) {
      $parameters[$(if ($option -eq 'dryrun') { 'DryRun' } else { 'NonInteractive' })] = $true
      $i++
      continue
    }
    if (($i + 1) -ge $Arguments.Count) {
      throw "Missing value for settings option '$token'."
    }
    $value = [string]$Arguments[$i + 1]
    if ($value.StartsWith('-') -and $value.TrimStart('-','/').ToLowerInvariant() -in @($valueOptions + $switchOptions)) {
      throw "Missing value for settings option '$token'."
    }
    $key = switch ($option) {
      'reporoot' { 'RepoRoot' }
      'workspacepath' { 'WorkspacePath' }
      'scope' { 'Scope' }
      'path' { 'Path' }
    }
    if ($key -eq 'Path') {
      $existingPaths = if ($parameters.ContainsKey('Path')) { [string[]]@($parameters.Path) } else { [string[]]@() }
      $parameters.Path = [string[]]@(@($existingPaths) + @($value))
    }
    else {
      $parameters[$key] = $value
    }
    $i += 2
  }
  return $parameters
}

function Get-UEToolSuiteSettingsHelpText {
  param([string]$Subcommand)
  if ([string]::IsNullOrWhiteSpace($Subcommand)) {
    return @(
      'VS Code workspace settings synchronization.'
      'Usage: ue settings <sync|capture|adopt|status|help> [options]'
      ''
      'Commands:'
      '  sync      Validate and apply operations that are already owned.'
      '  capture   Convert selected live workspace changes into owned operations.'
      '  adopt     Establish provenance for a workspace that may already be customized.'
      '  status    Inspect workspace selection, layers, state, drift, and conflicts.'
      ''
      'Getting started:'
      '  1. Run: ue settings status -WorkspacePath ".\Game.code-workspace"'
      '  2. If state is missing and the workspace is customized, use settings adopt.'
      '  3. If state exists, use settings capture for new edits and settings sync to apply ownership.'
      ''
      'Help:'
      '  ue help settings <command>'
      '  ue settings help <command>'
      '  ue settings <command> help'
      ''
      'Both ue and ue-tools use the same installed runtime and command surface.'
    )
  }

  switch ($Subcommand.Trim().ToLowerInvariant()) {
    'sync' {
      return @(
        'Apply owned VS Code workspace settings.'
        'Usage: ue settings sync [-RepoRoot <path>] [-WorkspacePath <path>] [-DryRun] [-NonInteractive]'
        ''
        'What it does:'
        '  - Requires an existing provenance ledger.'
        '  - Validates Team, User, and Project overlays before writing.'
        '  - Applies owned operations in Team -> User -> Project precedence order.'
        '  - Detects owned-value conflicts and writes nothing when any conflict exists.'
        '  - Never captures unknown live differences or creates ownership.'
        ''
        'Options:'
        '  -RepoRoot <path>       Select the Unreal repository explicitly.'
        '  -WorkspacePath <path> Select the .code-workspace file; relative paths use RepoRoot.'
        '  -DryRun               Run the full planner and validation without writing files.'
        '  -NonInteractive       Disable prompts for automation and hook-safe execution.'
        ''
        'Examples:'
        '  ue settings sync -WorkspacePath ".\Game.code-workspace" -DryRun'
        '  ue settings sync -RepoRoot "C:\Projects\Game" -WorkspacePath ".\Game.code-workspace" -NonInteractive'
        ''
        'Use settings capture for a saved edit made after the ledger exists. Use settings adopt only when establishing or intentionally rebuilding provenance.'
      )
    }
    'capture' {
      return @(
        'Capture selected live workspace changes as owned operations.'
        'Usage: ue settings capture -Scope <Team|User|Project> [-RepoRoot <path>] [-WorkspacePath <path>] [-Path <json-pointer>]... [-DryRun] [-NonInteractive]'
        ''
        'What it does:'
        '  - Requires an existing provenance ledger.'
        '  - Compares the saved live workspace with the last effective snapshot.'
        '  - Classifies selected additions, modifications, and removals as explicit operations.'
        '  - Applies all layers and atomically updates the overlay, workspace, and ledger.'
        '  - Scans the whole workspace and prompts for changes when -Path is omitted.'
        ''
        'Options:'
        '  -RepoRoot <path>       Select the Unreal repository explicitly.'
        '  -WorkspacePath <path> Select the .code-workspace file; relative paths use RepoRoot.'
        '  -Scope <scope>        Required ownership layer: Team, User, or Project.'
        '  -Path <json-pointer>  Select one structural path; repeat for multiple paths.'
        '  -DryRun               Preview selected operations without writing files.'
        '  -NonInteractive       Disable prompts; requires at least one explicit -Path.'
        ''
        'Examples:'
        '  ue settings capture -Scope Project -Path /settings/editor.fontSize -DryRun -NonInteractive'
        '  ue settings capture -Scope Team -Path /folders -WorkspacePath ".\Game.code-workspace" -NonInteractive'
        '  ue settings capture -Scope User'
        ''
        'Team is tracked and portable. User is machine-local and reusable. Project is private to this repository and user.'
      )
    }
    'adopt' {
      return @(
        'Establish provenance for an existing customized workspace.'
        'Usage: ue settings adopt [-RepoRoot <path>] [-WorkspacePath <path>] [-Scope <Team|User|Project>] [-Path <json-pointer>]... [-DryRun] [-NonInteractive]'
        ''
        'What it does:'
        '  - Refuses to run when a provenance ledger already exists.'
        '  - Preserves the original workspace, regenerates a pristine Unreal workspace, and compares them.'
        '  - Lets interactive users select candidate additions, modifications, and removals.'
        '  - Atomically writes the selected overlay, effective workspace, and first ledger.'
        '  - Restores the original workspace if regeneration, validation, or writing fails.'
        ''
        'Options:'
        '  -RepoRoot <path>       Select the Unreal repository explicitly.'
        '  -WorkspacePath <path> Select the .code-workspace file; relative paths use RepoRoot.'
        '  -Scope <scope>        Ownership layer: Team, User, or Project; prompted when omitted.'
        '  -Path <json-pointer>  Select one structural path; repeat for multiple paths.'
        '  -DryRun               Describe the adoption without regenerating or writing files.'
        '  -NonInteractive       Disable prompts; requires explicit -Scope and at least one -Path.'
        ''
        'Examples:'
        '  ue settings adopt -WorkspacePath ".\Game.code-workspace"'
        '  ue settings adopt -Scope User -Path /settings -Path /extensions/recommendations -NonInteractive'
        '  ue settings adopt -Scope Project -Path /tasks/tasks -DryRun -NonInteractive'
        ''
        'If a ledger already exists, use settings capture for new live edits or move a backed-up stale ledger aside before an intentional rebuild.'
      )
    }
    'status' {
      return @(
        'Inspect workspace settings provenance and health.'
        'Usage: ue settings status [-RepoRoot <path>] [-WorkspacePath <path>]'
        ''
        'What it does:'
        '  - Shows the resolved workspace, active user profile, and provenance state path.'
        '  - Lists Team, User, and Project overlay locations and owned operations.'
        '  - Reports live workspace drift from the last effective snapshot.'
        '  - Evaluates and lists current ownership conflicts when state exists.'
        '  - Never writes files.'
        ''
        'Options:'
        '  -RepoRoot <path>       Select the Unreal repository explicitly.'
        '  -WorkspacePath <path> Select the .code-workspace file; relative paths use RepoRoot.'
        ''
        'Examples:'
        '  ue settings status'
        '  ue settings status -WorkspacePath ".\Game.code-workspace"'
        '  ue settings status -RepoRoot "C:\Projects\Game" -WorkspacePath ".\Game.code-workspace"'
        ''
        'Status does not accept -DryRun, -NonInteractive, -Scope, or -Path because it is already read-only.'
      )
    }
    default {
      return @(
        "Unknown settings help topic '$Subcommand'."
        'Available topics: sync, capture, adopt, status.'
        'Run: ue settings help'
      )
    }
  }
}

function Invoke-UEToolSuiteSettingsCommand {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[string[]]$CommandArguments=@())
  if(@($CommandArguments).Count-eq0 -or [string]$CommandArguments[0] -in @('help','--help','-help','-h','/?','-?')){$topic=if($CommandArguments.Count-gt1){[string]$CommandArguments[1]}else{''};Get-UEToolSuiteSettingsHelpText $topic|Write-Output;return}
  $sub=[string]$CommandArguments[0];$tail=@($CommandArguments|Select-Object -Skip 1);if(@($tail|Where-Object{$_ -in @('help','--help','-help','-h','/?','-?')}).Count-gt0){Get-UEToolSuiteSettingsHelpText $sub|Write-Output;return};$normalizedSubcommand=$sub.Trim().ToLowerInvariant();if($normalizedSubcommand -notin @('sync','capture','adopt','status')){throw "Unknown settings subcommand '$sub'. Run 'ue settings help'."};$p=ConvertTo-UEToolSuiteSettingsCommandParameters -RepoRoot $RepoRoot -Subcommand $normalizedSubcommand -Arguments $tail
  switch($normalizedSubcommand){'sync'{[void](Invoke-UEToolSuiteWorkspaceSync @p)}'capture'{if(-not$p.Scope){throw 'settings capture requires -Scope Team, User, or Project.'};Invoke-UEToolSuiteWorkspaceCapture @p}'adopt'{Invoke-UEToolSuiteWorkspaceAdopt @p}'status'{Invoke-UEToolSuiteWorkspaceStatus @p}}
}

Export-ModuleMember -Function ConvertFrom-UEToolSuiteJsoncText,Read-UEToolSuiteWorkspaceJsonFile,Copy-UEToolSuiteWorkspaceValue,Get-UEToolSuiteWorkspaceStoragePaths,Resolve-UEToolSuiteWorkspaceSettingsContext,Get-UEToolSuiteWorkspaceLayers,Assert-UEToolSuiteWorkspaceLayersValid,Get-UEToolSuiteWorkspacePlan,Invoke-UEToolSuiteWorkspaceSync,Get-UEToolSuiteWorkspaceCaptureOperations,Test-UEToolSuiteWorkspaceConfiguration,Invoke-UEToolSuiteWorkspaceCapture,Invoke-UEToolSuiteWorkspaceAdopt,Invoke-UEToolSuiteWorkspaceStatus,Get-UEToolSuiteSettingsHelpText,Invoke-UEToolSuiteSettingsCommand
