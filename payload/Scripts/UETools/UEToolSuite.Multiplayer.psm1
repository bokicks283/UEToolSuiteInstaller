$projectContextPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Unreal\ProjectContext.ps1'
. $projectContextPath

function Get-UEToolSuiteMpStatePath {
  param([Parameter(Mandatory)][string]$RepoRoot)
  Join-Path $RepoRoot '.ue-tools\local\mp-session.json'
}

function Get-UEToolSuiteMpSession {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $path = Get-UEToolSuiteMpStatePath -RepoRoot $RepoRoot
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  try { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop) }
  catch { throw "Invalid multiplayer session record '$path': $($_.Exception.Message)" }
}

function Test-UEToolSuiteMpProcessOwned {
  param([Parameter(Mandatory)]$Record)
  try {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$Record.Pid)" -ErrorAction Stop
    if (-not $process) { return $false }
    $expected = [IO.Path]::GetFullPath([string]$Record.Executable)
    if (-not [string]::Equals([IO.Path]::GetFullPath([string]$process.ExecutablePath), $expected, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    $actualStart = if ($process.CreationDate -is [datetime]) { $process.CreationDate.ToUniversalTime() } else { [Management.ManagementDateTimeConverter]::ToDateTime([string]$process.CreationDate).ToUniversalTime() }
    $expectedStart = [datetime]::Parse([string]$Record.StartUtc, [Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
    return ([Math]::Abs(($actualStart - $expectedStart).TotalSeconds) -lt 2)
  }
  catch { return $false }
}

function Assert-UEToolSuiteMpLocalMode {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $config = Join-Path $RepoRoot 'Config\DefaultEngine.ini'
  if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { return }
  $text = Get-Content -LiteralPath $config -Raw
  if ($text -match '(?im)^\s*DefaultPlatformService\s*=\s*Steam\s*$' -or
      $text -match '(?im)^\s*\+?NetDriverDefinitions\s*=.*SteamNetDriver') {
    throw 'This project configures Steam networking in DefaultEngine.ini. Two local game instances may require separate Steam accounts or project-specific session settings. The mp launcher does not override networking configuration; use your project-supported local mode and retry.'
  }
}

function ConvertTo-UEToolSuiteMpMapArgument {
  param([string]$Map)
  if ([string]::IsNullOrWhiteSpace($Map)) { return '/Game/Maps/Entry?listen' }
  $value = $Map.Trim()
  if ($value -notmatch '^/Game/[A-Za-z0-9_/-]+$' -or $value.Contains('..')) {
    throw "Invalid map '$Map'. Pass a package path such as /Game/Maps/Arena."
  }
  return "$value`?listen"
}

function New-UEToolSuiteMpProcessRecord {
  param([Parameter(Mandatory)]$Process, [Parameter(Mandatory)][string]$Executable)
  [pscustomobject]@{ Pid = [int]$Process.Id; Executable = $Executable; StartUtc = $Process.StartTime.ToUniversalTime().ToString('o') }
}

function Invoke-UEToolSuiteMpCommand {
  param([Parameter(Mandatory)][string]$RepoRoot, [string[]]$CommandArguments = @())
  $verb = if ($CommandArguments.Count) { $CommandArguments[0].ToLowerInvariant() } else { 'help' }
  $tail = @($CommandArguments | Select-Object -Skip 1)
  $statePath = Get-UEToolSuiteMpStatePath -RepoRoot $RepoRoot
  if ($verb -in @('help','--help','-help','-h')) {
    'Usage: ue mp play [-Map /Game/Maps/YourMap] [-UProjectPath path] [-WorkspacePath path] | stop | logs'
    return
  }
  if ($verb -in @('stop','logs')) {
    if ($tail.Count) { throw "ue mp $verb does not accept options." }
    $session = Get-UEToolSuiteMpSession -RepoRoot $RepoRoot
    if (-not $session) { throw 'No multiplayer test session is recorded for this project.' }
    if ($verb -eq 'logs') {
      "Host log: $($session.HostLog)"
      "Client log: $($session.ClientLog)"
      return
    }
    foreach ($record in @($session.Client, $session.Host)) {
      if (Test-UEToolSuiteMpProcessOwned -Record $record) {
        Stop-Process -Id ([int]$record.Pid) -ErrorAction Stop
        "Stopped owned process $($record.Pid)."
      }
      else { "Process $($record.Pid) is absent or no longer matches this session; skipped." }
    }
    Remove-Item -LiteralPath $statePath -Force
    return
  }
  if ($verb -ne 'play') { throw "Unknown mp subcommand '$verb'. Run 'ue mp help'." }
  $options = @{}
  for ($i = 0; $i -lt $tail.Count; $i += 2) {
    $key = [string]$tail[$i]
    if ($key -notin @('-Map','-UProjectPath','-WorkspacePath') -or $i + 1 -ge $tail.Count -or [string]::IsNullOrWhiteSpace([string]$tail[$i + 1])) {
      throw 'Usage: ue mp play [-Map /Game/Maps/YourMap] [-UProjectPath path] [-WorkspacePath path]'
    }
    if ($options.ContainsKey($key.ToLowerInvariant())) { throw "Duplicate mp option: $key" }
    $options[$key.ToLowerInvariant()] = [string]$tail[$i + 1]
  }
  $map = $options['-map']
  if ($map) { $hostMap = ConvertTo-UEToolSuiteMpMapArgument -Map $map }
  else { $hostMap = $null }
  $context = Get-ProjectContext -RepoRoot $RepoRoot -UProjectPath $options['-uprojectpath'] -WorkspacePath $options['-workspacepath']
  Assert-UEToolSuiteMpLocalMode -RepoRoot $RepoRoot
  $existing = Get-UEToolSuiteMpSession -RepoRoot $RepoRoot
  if ($existing) { throw "A multiplayer session record already exists at '$statePath'. Run 'ue mp stop' before playing again." }
  $attempts = [Collections.Generic.List[string]]::new()
  $editor = Resolve-UnrealEditorPath -ProjectContext $context -WorkspacePath $context.WorkspacePath -Attempts $attempts
  if (-not $editor) { throw "UnrealEditor.exe could not be resolved for '$($context.UProjectPath)'. $($attempts -join '; ')" }
  if (@(Get-NetUDPEndpoint -LocalPort 7777 -ErrorAction SilentlyContinue).Count) {
    throw 'UDP port 7777 is already in use. Close the existing listener before running ue mp play.'
  }
  $sessionDir = Join-Path $RepoRoot ('.ue-tools\local\mp-logs\' + [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff'))
  New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
  $hostLog = Join-Path $sessionDir 'host.log'
  $clientLog = Join-Path $sessionDir 'client.log'
  $project = '"' + $context.UProjectPath + '"'
  $common = '-game -windowed -log -nosplash'
  $hostArgs = "$project $common " + $(if ($hostMap) { $hostMap } else { '?listen' }) + " -port=7777 -abslog=`"$hostLog`""
  $clientArgs = "$project 127.0.0.1:7777 $common -abslog=`"$clientLog`""
  $hostProcess = $null
  $clientProcess = $null
  try {
    $hostProcess = Start-Process -FilePath $editor -ArgumentList $hostArgs -WorkingDirectory $RepoRoot -PassThru
    if ($hostProcess.HasExited) { throw 'Host process exited immediately. Check the host log and project networking configuration.' }
    $deadline = [datetime]::UtcNow.AddSeconds(90)
    $hostReady = $false
    while ([datetime]::UtcNow -lt $deadline) {
      $hostProcess.Refresh()
      if ($hostProcess.HasExited) { throw "Host exited before opening UDP port 7777. Inspect '$hostLog'." }
      $hostReady = @((Get-NetUDPEndpoint -LocalPort 7777 -ErrorAction SilentlyContinue) | Where-Object { $_.OwningProcess -eq $hostProcess.Id }).Count -gt 0
      if ($hostReady) { break }
      Start-Sleep -Milliseconds 500
    }
    if (-not $hostReady) { throw "Host did not open UDP port 7777 within 90 seconds. Inspect '$hostLog' and the project's session configuration." }
    $clientProcess = Start-Process -FilePath $editor -ArgumentList $clientArgs -WorkingDirectory $RepoRoot -PassThru
    if ($clientProcess.HasExited) { throw 'Client process exited immediately. Check the client log and project networking configuration.' }
    $session = [pscustomobject]@{
      Host = New-UEToolSuiteMpProcessRecord -Process $hostProcess -Executable $editor
      Client = New-UEToolSuiteMpProcessRecord -Process $clientProcess -Executable $editor
      HostLog = $hostLog; ClientLog = $clientLog; Project = $context.UProjectPath
    }
    $session | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
    "Host PID $($hostProcess.Id); client PID $($clientProcess.Id)."
    "Host log: $hostLog"
    "Client log: $clientLog"
  }
  catch {
    if ($clientProcess -and -not $clientProcess.HasExited) { Stop-Process -Id $clientProcess.Id -ErrorAction SilentlyContinue }
    if ($hostProcess -and -not $hostProcess.HasExited) { Stop-Process -Id $hostProcess.Id -ErrorAction SilentlyContinue }
    throw
  }
}

Export-ModuleMember -Function Invoke-UEToolSuiteMpCommand, Get-UEToolSuiteMpStatePath, Get-UEToolSuiteMpSession, Test-UEToolSuiteMpProcessOwned, Assert-UEToolSuiteMpLocalMode, ConvertTo-UEToolSuiteMpMapArgument
