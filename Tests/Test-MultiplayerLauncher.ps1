$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$module = Join-Path $repoRoot 'payload\Scripts\UETools\UEToolSuite.Multiplayer.psm1'
Import-Module $module -Force
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('ue-mp-test-' + [guid]::NewGuid().ToString('N'))
$worker = $null
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
  $lanOptions = ConvertTo-UEToolSuiteMpPlayOptions -Arguments @('-Map', '/Game/Map/YourGameplayMap', '-Network', 'lAn')
  if ($lanOptions.Network -cne 'LAN' -or $lanOptions.Map -cne '/Game/Map/YourGameplayMap') { throw 'LAN option parsing failed.' }
  $reversed = ConvertTo-UEToolSuiteMpPlayOptions -Arguments @('-Network', 'LAN', '-Map', '/Game/Map/YourGameplayMap')
  if ($reversed.Network -cne $lanOptions.Network -or $reversed.Map -cne $lanOptions.Map) { throw 'LAN option order changed parsing.' }
  try { ConvertTo-UEToolSuiteMpPlayOptions -Arguments @('-Network', 'Steam') | Out-Null; throw 'Unsupported network mode was accepted.' }
  catch { if ($_.Exception.Message -eq 'Unsupported network mode was accepted.') { throw } }
  $legacyOptions = ConvertTo-UEToolSuiteMpPlayOptions -Arguments @('-Map', '/Game/Maps/Arena')
  if ($legacyOptions.Network) { throw 'Default network mode changed.' }
  $beforeConfig = (Get-FileHash -LiteralPath (Join-Path $scratch 'Config\DefaultEngine.ini')).Hash
  Assert-UEToolSuiteMpLocalMode -RepoRoot $scratch -Network LAN
  $afterConfig = (Get-FileHash -LiteralPath (Join-Path $scratch 'Config\DefaultEngine.ini')).Hash
  if ($beforeConfig -cne $afterConfig) { throw 'LAN validation modified project configuration.' }
  $launch = Get-UEToolSuiteMpLaunchArguments -UProjectPath 'C:\Test Game\TestGame.uproject' -HostMap '/Game/Map/YourGameplayMap?listen' -HostLog 'C:\Logs\host.log' -ClientLog 'C:\Logs\client.log' -Network LAN
  foreach ($argument in @('-ini:Engine:[OnlineSubsystem]:DefaultPlatformService=Null', '-ini:Engine:[OnlineSubsystemSteam]:bEnabled=false', '-NetDriverOverrides=/Script/OnlineSubsystemUtils.IpNetDriver')) {
    if (-not $launch.Host.Contains($argument, [StringComparison]::Ordinal) -or -not $launch.Client.Contains($argument, [StringComparison]::Ordinal)) { throw "Missing LAN override: $argument" }
  }
  if ($launch.Host -cnotlike '*/Game/Map/YourGameplayMap?listen*' -or $launch.Client -cnotlike '*127.0.0.1:7777*') { throw 'Host/client launch URLs changed.' }
  $defaultLaunch = Get-UEToolSuiteMpLaunchArguments -UProjectPath 'C:\Test Game\TestGame.uproject' -HostMap '/Game/Maps/Arena?listen' -HostLog 'C:\Logs\host.log' -ClientLog 'C:\Logs\client.log'
  if ($defaultLaunch.Host -cne '"C:\Test Game\TestGame.uproject" -game -windowed -UEToolSuiteMP -log -nosplash /Game/Maps/Arena?listen -port=7777 -abslog="C:\Logs\host.log"' -or
      $defaultLaunch.Client -cne '"C:\Test Game\TestGame.uproject" 127.0.0.1:7777 -game -windowed -UEToolSuiteMP -log -nosplash -abslog="C:\Logs\client.log"') { throw 'Default launch arguments changed.' }
  $screens = @(
    [pscustomobject]@{ Primary = $true; WorkingArea = [pscustomobject]@{ X = 0; Y = 0; Width = 1920; Height = 1080 } },
    [pscustomobject]@{ Primary = $false; WorkingArea = [pscustomobject]@{ X = -1600; Y = 0; Width = 1600; Height = 900 } }
  )
  $layout = Get-UEToolSuiteMpWindowLayout -Screens $screens
  if ($layout.Host -notlike '*-WinX=*' -or $layout.Client -notlike '*-WinX=-*') { throw 'Multi-screen placement was not generated.' }
  $single = Get-UEToolSuiteMpWindowLayout -Screens @($screens[0])
  if ($single.Host -or $single.Client) { throw 'Single-screen placement changed.' }
  $roleLaunch = Get-UEToolSuiteMpLaunchArguments -UProjectPath 'C:\Test Game\TestGame.uproject' -HostMap '/Game/Maps/Arena?listen' -HostLog 'C:\Logs\host.log' -ClientLog 'C:\Logs\client.log' -WindowLayout $layout
  if (-not $roleLaunch.Host.Contains('-UEToolSuiteMP', [StringComparison]::Ordinal) -or
      -not $roleLaunch.Client.Contains('-UEToolSuiteMP', [StringComparison]::Ordinal)) { throw 'Multiplayer video override marker missing.' }
  foreach ($role in @(@{ Args = $roleLaunch.Host; Title = 'MP_HOST' }, @{ Args = $roleLaunch.Client; Title = 'MP_CLIENT' })) {
    $expectedWindowSettings = "-ini:Game:[/Script/EngineSettings.GeneralProjectSettings]:ProjectDisplayedTitle=$($role.Title),[/Script/EngineSettings.GeneralProjectSettings]:bUseBorderlessWindow=false"
    if (-not $role.Args.Contains($expectedWindowSettings, [StringComparison]::Ordinal)) { throw "Visible $($role.Title) title configuration missing." }
  }
  if ($roleLaunch.Host -notlike '*-windowed*' -or $roleLaunch.Client -notlike '*-windowed*') { throw 'Windowed mode missing.' }
  $statePath = Get-UEToolSuiteMpStatePath -RepoRoot $scratch
  New-Item -ItemType Directory -Path (Split-Path -Parent $statePath) -Force | Out-Null
  @{ Host = @{ Pid = 2147483647; Executable = 'C:\missing.exe'; StartUtc = [datetime]::UtcNow.ToString('o') }; Client = @{ Pid = 2147483646; Executable = 'C:\missing.exe'; StartUtc = [datetime]::UtcNow.ToString('o') }; HostLog = 'C:\Logs\host.log'; ClientLog = 'C:\Logs\client.log' } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $statePath
  $logs = @(Invoke-UEToolSuiteMpCommand -RepoRoot $scratch -CommandArguments @('logs')) -join ' '
  if ($logs -notlike '*C:\Logs\host.log*' -or $logs -notlike '*C:\Logs\client.log*') { throw 'Session logs output changed.' }
  $stopped = @(Invoke-UEToolSuiteMpCommand -RepoRoot $scratch -CommandArguments @('stop')) -join ' '
  if ($stopped -notlike '*skipped*' -or (Test-Path -LiteralPath $statePath)) { throw 'Stale session cleanup changed.' }
  $workerScript = Join-Path $scratch 'mp-worker.ps1'
  'param([string]$abslog) Start-Sleep -Seconds 60' | Set-Content -LiteralPath $workerScript
  $workerLog = Join-Path $scratch 'unique-worker.log'
  $workerStart = [datetime]::UtcNow.AddSeconds(-1).ToString('o')
  $worker = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList "-NoProfile -File `"$workerScript`" -abslog `"$workerLog`"" -WindowStyle Hidden -PassThru
  $directRecord = [pscustomobject]@{ Pid = $worker.Id; Executable = (Get-Process -Id $worker.Id).Path; StartUtc = $worker.StartTime.ToUniversalTime().ToString('o') }
  $directRoundTrip = ($directRecord | ConvertTo-Json | ConvertFrom-Json)
  if (-not (Test-UEToolSuiteMpProcessOwned -Record $directRoundTrip)) { throw 'UTC process start time changed across session JSON.' }
  @{ Host = @{ Pid = 2147483646; Executable = 'C:\missing.exe'; StartUtc = $workerStart }; Client = $directRecord; HostLog = 'C:\Logs\host.log'; ClientLog = $workerLog } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $statePath
  $roundTrip = Get-UEToolSuiteMpSession -RepoRoot $scratch
  if (-not (Test-UEToolSuiteMpProcessOwned -Record $roundTrip.Client)) { throw 'Saved session record did not match its live process.' }
  $stoppedWorker = @(Invoke-UEToolSuiteMpCommand -RepoRoot $scratch -CommandArguments @('stop')) -join ' '
  $worker.Refresh()
  if ($stoppedWorker -notlike "*client process $($worker.Id)*" -or -not $worker.HasExited -or (Test-Path -LiteralPath $statePath)) { throw "Session stop did not terminate the recorded process: output='$stoppedWorker' exited=$($worker.HasExited) stateExists=$(Test-Path -LiteralPath $statePath)." }
  'PASS multiplayer launcher focused checks'
}
finally {
  if ($worker) { $worker.Refresh(); if (-not $worker.HasExited) { Stop-Process -Id $worker.Id -Force -ErrorAction SilentlyContinue } }
  Remove-Item -LiteralPath $scratch -Recurse -Force
}
