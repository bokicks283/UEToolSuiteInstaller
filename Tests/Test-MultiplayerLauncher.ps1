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
  $fixtureDir = Join-Path $scratch 'historical-session'
  New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null
  $hostFixture = @(
    '[2026.10.17-15.00.00:000][  0] LogNet: Warning: No owning connection for actor BP_Vehicle_ClubLug_C_UAID_123 Function ServerUpdateState will not be processed.'
    '[2026.10.17-15.00.01:000][  0] LogNet: Warning: No owning connection for actor BP_Vehicle_ClubLug_C_UAID_999 Function ServerUpdateState will not be processed.'
    '[2026.10.17-15.00.02:000][  0] LogNet: Warning: No owning connection for actor BP_Vehicle_ClubLug_C_UAID_999 Function ServerSetColor will not be processed.'
    '[2026.10.17-15.00.03:000][  0] LogDataTable: Error: Row Item_Gun missing from table DT_Items'
    '[2026.10.17-15.00.04:000][  0] LogNet: Error: RPC dispatch failed for actor BP_Truck_C Function ServerSetColor'
    '[2026.10.17-15.00.05:000][  0] LogScript: Warning: Handled ensure: World is tearing down'
    '  WBP_World_InteractionPrompt_C'
    '  /Game/UI/WBP_World_InteractionPrompt.WBP_World_InteractionPrompt_C'
  ) -join "`n"
  $clientFixture = @(
    '[2026.10.17-15.00.06:000][  0] LogNet: Warning: No owning connection for actor BP_Vehicle_ClubLug_C_UAID_321 Function ServerUpdateState will not be processed.'
    'garbage without a log severity'
  ) -join "`n"
  $hostPath = Join-Path $fixtureDir 'host.log'
  $clientPath = Join-Path $fixtureDir 'client.log'
  Set-Content -LiteralPath $hostPath -Value $hostFixture -Encoding utf8NoBOM
  Set-Content -LiteralPath $clientPath -Value $clientFixture -Encoding utf8NoBOM
  $beforeHostHash = (Get-FileHash -LiteralPath $hostPath).Hash
  $summary = Get-UEToolSuiteMpLogSummary -LogDir $fixtureDir -Top 15
  if ($summary.Processes.Count -ne 2 -or $summary.Processes[0].Role -cne 'Host' -or $summary.Processes[1].Role -cne 'Client') { throw 'Historical host/client log separation failed.' }
  if ($summary.Processes[0].LineCount -ne 8 -or $summary.Processes[0].WarningCount -ne 3 -or $summary.Processes[0].ErrorCount -ne 2 -or $summary.Processes[0].EnsureCount -ne 1) { throw 'Summary severity or line counts failed.' }
  $summaryText = Format-UEToolSuiteMpLogSummary -Summary $summary
  if (-not $summaryText.Contains('2x Warning: No owning connection') -or -not $summaryText.Contains('ServerUpdateState') -or -not $summaryText.Contains('Item_Gun') -or -not $summaryText.Contains('ServerSetColor') -or -not (($summary.Processes[0].Issues | ForEach-Object { $_.Message }) -join ' ').Contains('WBP_World_InteractionPrompt_C')) { throw 'Summary grouping or representative details were lost.' }
  if ((Get-FileHash -LiteralPath $hostPath).Hash -cne $beforeHostHash) { throw 'Summary modified its original log.' }
  $manyPath = Join-Path $fixtureDir 'many.log'
  $writer = [IO.StreamWriter]::new($manyPath, $false, [Text.UTF8Encoding]::new($false))
  try { for ($i = 0; $i -lt 25000; $i++) { $writer.WriteLine("[2026.10.17-15.00.00:000][  0] LogNet: Warning: No owning connection for actor BP_Vehicle_C_UAID_$i Function ServerUpdateState will not be processed.") } }
  finally { $writer.Dispose() }
  $large = Get-UEToolSuiteMpLogFileSummary -Path $manyPath -Role 'Client' -Top 3
  if ($large.LineCount -ne 25000 -or $large.WarningCount -ne 25000 -or $large.Issues[0].Count -ne 25000) { throw 'Large repeated warning stream was not aggregated.' }
  $missing = Get-UEToolSuiteMpLogFileSummary -Path (Join-Path $fixtureDir 'missing.log') -Role 'Host' -Top 3
  if (-not $missing.Error -or $missing.LineCount -ne 0) { throw 'Missing log was not reported gracefully.' }
  $malformedPath = Join-Path $fixtureDir 'malformed.log'
  Set-Content -LiteralPath $malformedPath -Value "[2026.10.17-15.00.00:000] LogScript: Warning: Handled ensure: bad`n  WBP_First_C`n  WBP_Second_C" -Encoding utf8NoBOM
  $malformed = Get-UEToolSuiteMpLogFileSummary -Path $malformedPath -Role 'Host' -Top 10
  if ($malformed.LineCount -ne 3 -or $malformed.EnsureCount -ne 1 -or $malformed.Issues.Count -ne 1 -or -not $malformed.Issues[0].Message.Contains('WBP_First_C') -or -not $malformed.Issues[0].Message.Contains('WBP_Second_C')) { throw 'Multiline ensure records were not captured correctly.' }
  try { ConvertTo-UEToolSuiteMpSummaryOptions -Arguments @('-Top','3','-top','4') | Out-Null; throw 'Duplicate summary option was accepted.' }
  catch { if ($_.Exception.Message -eq 'Duplicate summary option was accepted.') { throw } }
  if ((ConvertTo-UEToolSuiteMpSummaryOptions -Arguments @('-top','3')).Top -ne 3) { throw 'Summary options are not case-insensitive.' }
  Set-Content -LiteralPath (Join-Path $fixtureDir 'host.log') -Value '[broken' -Encoding utf8NoBOM
  $historicalState = @{ Host = @{ Pid = 2147483647; Executable = 'C:\missing.exe'; StartUtc = [datetime]::UtcNow.ToString('o') }; Client = @{ Pid = 2147483646; Executable = 'C:\missing.exe'; StartUtc = [datetime]::UtcNow.ToString('o') }; HostLog = 'C:\Missing\host.log'; ClientLog = 'C:\Missing\client.log'; LogDir = $fixtureDir } | ConvertTo-Json -Depth 3
  Set-Content -LiteralPath $statePath -Value $historicalState
  $fallback = @(Invoke-UEToolSuiteMpCommand -RepoRoot $scratch -CommandArguments @('summary', '-Top', '5')) -join ' '
  if ($fallback -notlike '*HOST*' -or $fallback -notlike '*CLIENT*') { throw 'Recorded historical log directory fallback failed.' }
  $explicit = @(Invoke-UEToolSuiteMpCommand -RepoRoot $scratch -CommandArguments @('summary', '-LogDir', $fixtureDir, '-Top', '2')) -join ' '
  if ($explicit -notlike '*historical-session*') { throw 'Explicit historical summary directory was ignored.' }
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
