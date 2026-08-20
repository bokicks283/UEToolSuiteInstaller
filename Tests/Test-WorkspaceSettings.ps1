[CmdletBinding()]
param([switch]$NoCleanup,[switch]$FailFast)

$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$modulePath=Join-Path $repoRoot 'payload\Scripts\UETools\UEToolSuite.Settings.psm1'
$resultRoot=Join-Path $PSScriptRoot 'Test-WorkspaceSettingsResults'
$scratch=Join-Path $resultRoot ('run-'+[guid]::NewGuid().ToString('N'))
$passed=0;$failed=0

function Assert-True([string]$Name,[bool]$Condition,[string]$Detail=''){
  if($Condition){$script:passed++;Write-Host "PASS: $Name" -ForegroundColor Green;return}
  $script:failed++;Write-Host "FAIL: $Name $Detail" -ForegroundColor Red;if($FailFast){throw "Assertion failed: $Name"}
}
function Write-JsonFile([string]$Path,$Value){$parent=Split-Path -Parent $Path;if(-not(Test-Path $parent)){New-Item -ItemType Directory -Force -Path $parent|Out-Null};[IO.File]::WriteAllText($Path,(($Value|ConvertTo-Json -Depth 100)+"`n"),[Text.UTF8Encoding]::new($false))}
function New-Fixture([string]$Name,[string]$Engine='D:\UE_5.8'){
  $root=Join-Path $scratch $Name;New-Item -ItemType Directory -Force -Path $root|Out-Null
  Write-JsonFile (Join-Path $root 'Game.uproject') ([ordered]@{FileVersion=3;EngineAssociation='5.8';Modules=@([ordered]@{Name='Game';Type='Runtime'})})
  $workspace=Join-Path $root 'Game.code-workspace';Write-JsonFile $workspace ([ordered]@{folders=@([ordered]@{path='.'},[ordered]@{path=$Engine});settings=[ordered]@{'ue.generated'='old'};tasks=[ordered]@{tasks=@([ordered]@{label='Generated';type='shell';command='old'})};launch=[ordered]@{configurations=@();compounds=@()};inputs=@()})
  return [pscustomobject]@{Root=$root;Workspace=$workspace}
}

$oldLocal=$env:LOCALAPPDATA;$oldEngine=$env:UE_ENGINE_ROOT
try{
  New-Item -ItemType Directory -Force -Path $scratch|Out-Null;$env:LOCALAPPDATA=Join-Path $scratch 'localappdata'
  $engine=Join-Path $scratch 'UE_5.8';New-Item -ItemType Directory -Force -Path (Join-Path $engine 'Engine\Build\BatchFiles')|Out-Null;New-Item -ItemType File -Force -Path (Join-Path $engine 'Engine\Build\BatchFiles\Build.bat')|Out-Null;$env:UE_ENGINE_ROOT=$engine
  Import-Module $modulePath -Force

  $jsonc=ConvertFrom-UEToolSuiteJsoncText -SourceName test -Text "{ // comment`n `"url`": `"https://example/a//b`", /* block */ `"value`": 2 }"
  Assert-True 'JSONC parser preserves comment markers inside strings' ($jsonc.url -eq 'https://example/a//b' -and $jsonc.value -eq 2)

  $f=New-Fixture 'precedence' $engine;$ctx=Resolve-UEToolSuiteWorkspaceSettingsContext $f.Root $f.Workspace
  Write-JsonFile $ctx.Paths.Team ([ordered]@{schemaVersion=1;scope='Team';operations=@([ordered]@{op='set';path='/settings/editor.formatOnSave';value=$true},[ordered]@{op='addStringItem';path='/extensions/recommendations';value='team.extension'},[ordered]@{op='upsertKeyedItem';path='/launch/compounds';identityKey='name';identityValue='Team Compound';value=[ordered]@{name='Team Compound';configurations=@('Team Launch')}},[ordered]@{op='upsertKeyedItem';path='/inputs';identityKey='id';identityValue='teamInput';value=[ordered]@{id='teamInput';type='promptString'}},[ordered]@{op='removeSemantic';path='/folders';selector='activeUnrealEngineRoot'},[ordered]@{op='removeKeyedItem';path='/tasks/tasks';identityKey='label';identityValue='Generated'})})
  Write-JsonFile $ctx.Paths.User ([ordered]@{schemaVersion=1;scope='User';operations=@([ordered]@{op='set';path='/settings/editor.fontSize';value=15})})
  Write-JsonFile $ctx.Paths.Project ([ordered]@{schemaVersion=1;scope='Project';operations=@([ordered]@{op='set';path='/settings/editor.fontSize';value=17})})
  $before=Get-Content $f.Workspace -Raw;[void](Invoke-UEToolSuiteWorkspaceSync -RepoRoot $f.Root -WorkspacePath $f.Workspace -PreviousWorkspaceContent $before -NonInteractive)
  $effective=Read-UEToolSuiteWorkspaceJsonFile $f.Workspace
  Assert-True 'team/user/project precedence applies' ($effective.settings.'editor.formatOnSave' -eq $true -and $effective.settings.'editor.fontSize' -eq 17)
  Assert-True 'semantic Engine removal removes only Engine folder' (@($effective.folders).Count -eq 1 -and $effective.folders[0].path -eq '.')
  Assert-True 'keyed removal tombstone applies' (@($effective.tasks.tasks).Count -eq 0)
  Assert-True 'string arrays, compounds, and inputs use identity-aware operations' (@($effective.extensions.recommendations) -contains 'team.extension' -and @($effective.launch.compounds|Where-Object name -eq 'Team Compound').Count -eq 1 -and @($effective.inputs|Where-Object id -eq 'teamInput').Count -eq 1)
  $state=Read-UEToolSuiteWorkspaceJsonFile $ctx.Paths.State;Assert-True 'ledger stores pristine and effective snapshots' ($state.pristine.folders.Count -eq 2 -and $state.effective.folders.Count -eq 1)

  $regenerated=Copy-UEToolSuiteWorkspaceValue $state.pristine;$regenerated['future']=[ordered]@{nested=42};$regenerated.settings.Remove('ue.generated');$regenerated.tasks.tasks=@([ordered]@{label='Generated';type='shell';command='new'},[ordered]@{label='Future';type='shell';command='future'})
  [void](Invoke-UEToolSuiteWorkspaceSync -RepoRoot $f.Root -WorkspacePath $f.Workspace -PristineOverride $regenerated -PreviousWorkspaceContent (Get-Content $f.Workspace -Raw) -NonInteractive)
  $afterRegen=Read-UEToolSuiteWorkspaceJsonFile $f.Workspace
  Assert-True 'new UE fields and array entries survive while obsolete unowned fields disappear' ($afterRegen.future.nested -eq 42 -and -not $afterRegen.settings.Contains('ue.generated') -and @($afterRegen.tasks.tasks|Where-Object label -eq Future).Count -eq 1)
  Assert-True 'removal tombstones reapply without conflict' (@($afterRegen.tasks.tasks|Where-Object label -eq Generated).Count -eq 0 -and @($afterRegen.folders).Count -eq 1)

  $sameBytes=[IO.File]::ReadAllBytes($f.Workspace);$sameStateBytes=[IO.File]::ReadAllBytes($ctx.Paths.State);[void](Invoke-UEToolSuiteWorkspaceSync -RepoRoot $f.Root -WorkspacePath $f.Workspace -NonInteractive);$sameBytes2=[IO.File]::ReadAllBytes($f.Workspace);$sameStateBytes2=[IO.File]::ReadAllBytes($ctx.Paths.State)
  Assert-True 'idempotent semantic no-op does not rewrite workspace or state' ([Convert]::ToBase64String($sameBytes) -eq [Convert]::ToBase64String($sameBytes2) -and [Convert]::ToBase64String($sameStateBytes) -eq [Convert]::ToBase64String($sameStateBytes2))

  $conflict=Copy-UEToolSuiteWorkspaceValue $regenerated;$conflict.settings['editor.formatOnSave']=$false;$threw=$false;try{[void](Invoke-UEToolSuiteWorkspaceSync -RepoRoot $f.Root -WorkspacePath $f.Workspace -PristineOverride $conflict -PreviousWorkspaceContent (Get-Content $f.Workspace -Raw) -NonInteractive)}catch{$threw=$_.Exception.Message -match 'conflict'}
  Assert-True 'UE change to owned value produces no-write conflict' $threw

  if(Test-Path -LiteralPath $ctx.Paths.User){Remove-Item -LiteralPath $ctx.Paths.User -Force}
  $capture=New-Fixture 'capture' $engine;$captureBefore=Get-Content $capture.Workspace -Raw;[void](Invoke-UEToolSuiteWorkspaceSync -RepoRoot $capture.Root -WorkspacePath $capture.Workspace -PreviousWorkspaceContent $captureBefore -NonInteractive);$live=Read-UEToolSuiteWorkspaceJsonFile $capture.Workspace;$live.folders=@($live.folders|Where-Object{$_.path -eq '.'});Write-JsonFile $capture.Workspace $live;Invoke-UEToolSuiteWorkspaceCapture -RepoRoot $capture.Root -WorkspacePath $capture.Workspace -Scope Team -Path /folders -NonInteractive;$captureCtx=Resolve-UEToolSuiteWorkspaceSettingsContext $capture.Root $capture.Workspace;$capturedOverlay=Read-UEToolSuiteWorkspaceJsonFile $captureCtx.Paths.Team
  Assert-True 'capture records portable Engine removal rather than absolute path' (@($capturedOverlay.operations|Where-Object{$_.op -eq 'removeSemantic' -and $_.selector -eq 'activeUnrealEngineRoot'}).Count -eq 1 -and (Get-Content $captureCtx.Paths.Team -Raw) -notmatch [regex]::Escape($engine))

  $private=New-Fixture 'privacy' $engine;$privateCtx=Resolve-UEToolSuiteWorkspaceSettingsContext $private.Root $private.Workspace;Write-JsonFile $privateCtx.Paths.Team ([ordered]@{schemaVersion=1;scope='Team';operations=@([ordered]@{op='set';path='/settings/tool.path';value='C:\Private\tool.exe'})});$rejected=$false;try{Assert-UEToolSuiteWorkspaceLayersValid (Get-UEToolSuiteWorkspaceLayers $privateCtx)}catch{$rejected=$true};Assert-True 'team layer rejects machine absolute path' $rejected
  Write-JsonFile $privateCtx.Paths.Team ([ordered]@{schemaVersion=1;scope='Team';operations=@()});Write-JsonFile $privateCtx.Paths.User ([ordered]@{schemaVersion=1;scope='User';operations=@([ordered]@{op='set';path='/settings/tool.path';value='C:\Private\tool.exe'})});$accepted=$true;try{Assert-UEToolSuiteWorkspaceLayersValid (Get-UEToolSuiteWorkspaceLayers $privateCtx)}catch{$accepted=$false};Assert-True 'user layer permits machine absolute path' $accepted

  $unknownRejected=$false;try{Get-UEToolSuiteWorkspaceCaptureOperations ([ordered]@{custom=@([ordered]@{x=1})}) ([ordered]@{custom=@([ordered]@{x=2})}) @('/custom') $privateCtx|Out-Null}catch{$unknownRejected=$true};Assert-True 'unknown object-array shape requires explicit strategy' $unknownRejected

  Write-JsonFile $privateCtx.Paths.Team ([ordered]@{schemaVersion=1;scope='Team';operations=@([ordered]@{op='set';path='/settings/editor';value='team'})});Write-JsonFile $privateCtx.Paths.User ([ordered]@{schemaVersion=1;scope='User';operations=@([ordered]@{op='set';path='/settings/editor/fontSize';value=14})});$overlapRejected=$false;try{Assert-UEToolSuiteWorkspaceLayersValid (Get-UEToolSuiteWorkspaceLayers $privateCtx)}catch{$overlapRejected=$true};Assert-True 'overlapping incompatible property ownership is rejected' $overlapRejected

  $adoptBefore=[ordered]@{folders=@([ordered]@{path='.'},[ordered]@{path=$engine});settings=[ordered]@{generated='old'};tasks=[ordered]@{tasks=@([ordered]@{label='Generated';command='old'})}}
  $adoptAfter=[ordered]@{folders=@([ordered]@{path='.'});settings=[ordered]@{generated='custom';added=$true};tasks=[ordered]@{tasks=@()}}
  $adoptOps=Get-UEToolSuiteWorkspaceCaptureOperations $adoptBefore $adoptAfter @('/folders','/settings','/tasks/tasks') $privateCtx
  Assert-True 'adoption diff detects additions, modifications, and keyed removals' (@($adoptOps|Where-Object op -eq 'removeSemantic').Count -eq 1 -and @($adoptOps|Where-Object{$_.op -eq 'set' -and $_.path -eq '/settings/generated'}).Count -eq 1 -and @($adoptOps|Where-Object{$_.op -eq 'set' -and $_.path -eq '/settings/added'}).Count -eq 1 -and @($adoptOps|Where-Object op -eq 'removeKeyedItem').Count -eq 1)

  $adoptDry=New-Fixture 'adopt-dry-run' $engine;$adoptDryCtx=Resolve-UEToolSuiteWorkspaceSettingsContext $adoptDry.Root $adoptDry.Workspace;$adoptDryBytes=[IO.File]::ReadAllBytes($adoptDry.Workspace);$adoptDryUserBytes=if(Test-Path $adoptDryCtx.Paths.User){[IO.File]::ReadAllBytes($adoptDryCtx.Paths.User)}else{$null};Invoke-UEToolSuiteWorkspaceAdopt -RepoRoot $adoptDry.Root -WorkspacePath $adoptDry.Workspace -Scope User -Path /settings -DryRun -NonInteractive|Out-Null
  $adoptDryUserUnchanged=if($null-eq$adoptDryUserBytes){-not(Test-Path $adoptDryCtx.Paths.User)}else{[Convert]::ToBase64String($adoptDryUserBytes)-eq[Convert]::ToBase64String([IO.File]::ReadAllBytes($adoptDryCtx.Paths.User))};Assert-True 'adoption dry run does not change workspace, overlay, or ledger' ([Convert]::ToBase64String($adoptDryBytes) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($adoptDry.Workspace)) -and $adoptDryUserUnchanged -and -not(Test-Path $adoptDryCtx.Paths.State))

  Write-JsonFile $privateCtx.Paths.Team ([ordered]@{schemaVersion=1;scope='Team';operations=@()});Write-JsonFile $privateCtx.Paths.User ([ordered]@{schemaVersion=1;scope='User';operations=@()})
  $relative=New-Fixture 'relative-case' '..\UE_5.8\ENGINE\';$relativeCtx=Resolve-UEToolSuiteWorkspaceSettingsContext $relative.Root $relative.Workspace;Write-JsonFile $relativeCtx.Paths.Team ([ordered]@{schemaVersion=1;scope='Team';operations=@([ordered]@{op='removeSemantic';path='/folders';selector='activeUnrealEngineRoot'})});$relativeBefore=Get-Content $relative.Workspace -Raw;[void](Invoke-UEToolSuiteWorkspaceSync -RepoRoot $relative.Root -WorkspacePath $relative.Workspace -PreviousWorkspaceContent $relativeBefore -NonInteractive);$relativeLive=Read-UEToolSuiteWorkspaceJsonFile $relative.Workspace
  Assert-True 'Engine selector normalizes relative paths, case, separators, and trailing separators' (@($relativeLive.folders).Count -eq 1)

  $ambiguous=New-Fixture 'ambiguous' $engine;$ambiguousLive=Read-UEToolSuiteWorkspaceJsonFile $ambiguous.Workspace;$ambiguousLive.folders+= [ordered]@{path=(Join-Path $engine 'Engine')};Write-JsonFile $ambiguous.Workspace $ambiguousLive;$ambiguousCtx=Resolve-UEToolSuiteWorkspaceSettingsContext $ambiguous.Root $ambiguous.Workspace;Write-JsonFile $ambiguousCtx.Paths.Team ([ordered]@{schemaVersion=1;scope='Team';operations=@([ordered]@{op='removeSemantic';path='/folders';selector='activeUnrealEngineRoot'})});$ambiguousThrew=$false;try{[void](Invoke-UEToolSuiteWorkspaceSync -RepoRoot $ambiguous.Root -WorkspacePath $ambiguous.Workspace -PreviousWorkspaceContent (Get-Content $ambiguous.Workspace -Raw) -NonInteractive)}catch{$ambiguousThrew=$_.Exception.Message -match 'matched 2'};Assert-True 'ambiguous Engine selector stops before write' $ambiguousThrew

  if(Test-Path $ctx.Paths.User){Remove-Item $ctx.Paths.User -Force};$externalState=Read-UEToolSuiteWorkspaceJsonFile $ctx.Paths.State;$externalWorkspace=Copy-UEToolSuiteWorkspaceValue $externalState.pristine;Write-JsonFile $f.Workspace $externalWorkspace
  $noRegenOutput=& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'payload\Scripts\ue-tools.ps1') -RepoRoot $f.Root build -NoRegen -NoBuild -NonInteractive -WorkspacePath $f.Workspace 2>&1|Out-String;$afterNoRegen=Read-UEToolSuiteWorkspaceJsonFile $f.Workspace
  Assert-True '-NoRegen still synchronizes workspace settings' ($LASTEXITCODE -eq 0 -and @($afterNoRegen.folders).Count -eq 1) $noRegenOutput
  Write-JsonFile $f.Workspace $externalWorkspace;$skipOutput=& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'payload\Scripts\ue-tools.ps1') -RepoRoot $f.Root build -NoRegen -NoBuild -NonInteractive -SkipSettingsSync -WorkspacePath $f.Workspace 2>&1|Out-String;$afterSkip=Read-UEToolSuiteWorkspaceJsonFile $f.Workspace
  Assert-True '-SkipSettingsSync is the explicit opt-out' ($LASTEXITCODE -eq 0 -and @($afterSkip.folders).Count -eq 2) $skipOutput

  $helpOutput=& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'payload\Scripts\ue-tools.ps1') -RepoRoot $f.Root settings sync help 2>&1 | Out-String
  Assert-True 'command-first settings help dispatches' ($LASTEXITCODE -eq 0 -and $helpOutput -match 'Usage: ue settings sync') $helpOutput
}
finally{$env:LOCALAPPDATA=$oldLocal;$env:UE_ENGINE_ROOT=$oldEngine;if(-not$NoCleanup -and (Test-Path $scratch)){Remove-Item -LiteralPath $scratch -Recurse -Force}}

Write-Host "PASS=$passed FAIL=$failed"
if($failed -gt 0){exit 1}
