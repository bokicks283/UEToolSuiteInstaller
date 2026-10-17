$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$module = Join-Path $repoRoot 'payload\Scripts\UETools\UEToolSuite.Multiplayer.psm1'
Import-Module $module -Force
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('ue-mp-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $scratch 'Config') -Force | Out-Null
try {
  if ((ConvertTo-UEToolSuiteMpMapArgument '/Game/Maps/Arena') -cne '/Game/Maps/Arena?listen') { throw 'Map URL regression.' }
  try { ConvertTo-UEToolSuiteMpMapArgument '../bad' | Out-Null; throw 'Invalid map was accepted.' }
  catch { if ($_.Exception.Message -eq 'Invalid map was accepted.') { throw } }
  if (Test-UEToolSuiteMpProcessOwned ([pscustomobject]@{ Pid = 2147483647; Executable = 'C:\missing.exe'; StartUtc = [datetime]::UtcNow.ToString('o') })) { throw 'Stale PID was treated as owned.' }
  '[OnlineSubsystem]`nDefaultPlatformService=Steam' -replace '`n', "`n" | Set-Content -LiteralPath (Join-Path $scratch 'Config\DefaultEngine.ini')
  try { Assert-UEToolSuiteMpLocalMode -RepoRoot $scratch; throw 'Steam configuration was accepted.' }
  catch { if ($_.Exception.Message -eq 'Steam configuration was accepted.') { throw } }
  '[OnlineSubsystem]`n+NetDriverDefinitions=(DriverClassName="/Script/OnlineSubsystemSteam.SteamNetDriver")' -replace '`n', "`n" | Set-Content -LiteralPath (Join-Path $scratch 'Config\DefaultEngine.ini')
  try { Assert-UEToolSuiteMpLocalMode -RepoRoot $scratch; throw 'Steam net driver was accepted.' }
  catch { if ($_.Exception.Message -eq 'Steam net driver was accepted.') { throw } }
  $helpText = @(Invoke-UEToolSuiteMpCommand -RepoRoot $scratch -CommandArguments @('help')) -join ' '
  if ($helpText -notlike '*ue mp play*') { throw 'Help regression.' }
  'PASS multiplayer launcher focused checks'
}
finally { Remove-Item -LiteralPath $scratch -Recurse -Force }
