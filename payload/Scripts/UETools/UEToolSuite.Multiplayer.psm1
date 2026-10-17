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

function ConvertTo-UEToolSuiteMpIssueKey {
  param([Parameter(Mandatory)][string]$Message)
  $key = $Message.Trim()
  $key = [regex]::Replace($key, '(?i)\b[A-Za-z0-9_]+_UAID_[A-F0-9-]+', '<ACTOR>')
  $key = [regex]::Replace($key, '(?i)0x[0-9a-f]{6,}', '<ADDRESS>')
  $key = [regex]::Replace($key, '(?i)(?<=\bBP_[A-Za-z0-9_]+)_C_[A-F0-9]{8,}(?=\b|\s|\.)', '<ID>')
  return $key
}

function Get-UEToolSuiteMpLogFileSummary {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][ValidateSet('Host','Client')][string]$Role, [ValidateRange(1,100)][int]$Top = 10)
  $issues = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
  $lineCount = 0L; $warningCount = 0L; $errorCount = 0L; $ensureCount = 0L; $fatalCount = 0L
  $fileSize = 0L; $parseError = $null
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    $parseError = 'Log file is missing.'
  } else {
    try {
      $fileSize = (Get-Item -LiteralPath $Path -ErrorAction Stop).Length
      $reader = [IO.StreamReader]::new($Path, [Text.Encoding]::UTF8, $true)
      try {
        $active = $null
        while ($null -ne ($line = $reader.ReadLine())) {
          $lineCount++
          if ($active -and ($active.Group.Severity -eq 'Ensure' -or $active.Message -match 'ensure') -and $line -match '^\s+(?:at\s|/Game/|\w+\s+\(|WBP_[A-Za-z0-9_]+)') {
            $active.Message += "`n$line"
            $active.Group.Message = $active.Message
            $active.Group.Key = ConvertTo-UEToolSuiteMpIssueKey -Message $active.Message
            $newKey = $active.Group.Severity + '|' + $active.Group.Key
            if ($newKey -cne $active.Key) {
              if ($issues.ContainsKey($newKey)) {
                $existing = $issues[$newKey]
                if (-not [object]::ReferenceEquals($existing, $active.Group)) { $existing.Count += $active.Group.Count }
                if (-not $existing.First -or ($active.Group.First -and $active.Group.First -lt $existing.First)) { $existing.First = $active.Group.First }
                if (-not $existing.Last -or ($active.Group.Last -and $active.Group.Last -gt $existing.Last)) { $existing.Last = $active.Group.Last }
                $active.Group = $existing
              } else { $issues[$newKey] = $active.Group }
              $issues.Remove($active.Key)
              $active.Key = $newKey
            }
            continue
          }
          $active = $null
          $match = [regex]::Match($line, '^(?:\[(?<time>[^\]]+)\].*?)?\b(?<severity>Fatal error|Fatal|handled ensure|Ensure|Error|Warning)\s*:\s*(?<message>.*)$', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
          if (-not $match.Success) { continue }
          $severity = $match.Groups['severity'].Value
          if ($severity -match 'fatal') { $fatalCount++; $kind = 'Fatal' }
          elseif ($severity -match 'ensure' -or $match.Groups['message'].Value -match '^Handled ensure') { $ensureCount++; $kind = 'Ensure' }
          elseif ($severity -match 'error') { $errorCount++; $kind = 'Error' }
          else { $warningCount++; $kind = 'Warning' }
          $message = $match.Groups['message'].Value.Trim()
          if (-not $message) { $message = $line.Trim() }
          $key = $kind + '|' + (ConvertTo-UEToolSuiteMpIssueKey -Message $message)
          if (-not $issues.ContainsKey($key)) {
            $issues[$key] = [pscustomobject]@{ Severity = $kind; Key = (ConvertTo-UEToolSuiteMpIssueKey -Message $message); Count = 0L; First = $null; Last = $null; Message = $message; TimestampPattern = $match.Groups['time'].Value }
          }
          $group = $issues[$key]; $group.Count++
          $timestamp = $match.Groups['time'].Value
          if ($timestamp) { if (-not $group.First) { $group.First = $timestamp }; $group.Last = $timestamp }
          $active = [pscustomobject]@{ Message = $message; Group = $group; Key = $key }
        }
      } finally { $reader.Dispose() }
    } catch { $parseError = "Could not read log: $($_.Exception.Message)" }
  }
  $ordered = @($issues.Values | Sort-Object @{Expression='Count';Descending=$true}, @{Expression='Severity';Descending=$false}, @{Expression='Key';Descending=$false})
  [pscustomobject]@{ Role=$Role; Path=$Path; SizeBytes=$fileSize; LineCount=$lineCount; WarningCount=$warningCount; ErrorCount=$errorCount; EnsureCount=$ensureCount; FatalCount=$fatalCount; Issues=@($ordered | Select-Object -First $Top); ImportantOneOffs=@($ordered | Where-Object { $_.Severity -in @('Error','Ensure','Fatal') -and $_.Count -eq 1 }); Error=$parseError }
}

function Get-UEToolSuiteMpLogSummary {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$LogDir, [ValidateRange(1,100)][int]$Top = 10)
  $resolved = [IO.Path]::GetFullPath($LogDir)
  $hostSummary = Get-UEToolSuiteMpLogFileSummary -Path (Join-Path $resolved 'host.log') -Role Host -Top $Top
  $clientSummary = Get-UEToolSuiteMpLogFileSummary -Path (Join-Path $resolved 'client.log') -Role Client -Top $Top
  $processes = [System.Collections.ArrayList]::new()
  [void]$processes.Add($hostSummary)
  [void]$processes.Add($clientSummary)
  return [pscustomobject]@{ LogDir=$resolved; Processes=$processes.ToArray(); Top=$Top }
}

function Format-UEToolSuiteMpLogSummary {
  param([Parameter(Mandatory)]$Summary)
  $lines = [Collections.Generic.List[string]]::new()
  $lines.Add('UE Multiplayer Log Summary'); $lines.Add("Session: $($Summary.LogDir)")
  foreach ($process in $Summary.Processes) {
    $lines.Add(''); $lines.Add($process.Role.ToUpperInvariant())
    $lines.Add(('Log: {0} ({1:N1} MB)' -f $process.Path, ($process.SizeBytes / 1MB)))
    $lines.Add("Lines: $($process.LineCount)")
    $lines.Add("Warnings: $($process.WarningCount)  Errors: $($process.ErrorCount)  Ensures: $($process.EnsureCount)  Fatal: $($process.FatalCount)")
    if ($process.Error) { $lines.Add("Log status: $($process.Error)"); continue }
    $lines.Add('Top issues:')
    if (-not $process.Issues.Count) { $lines.Add('  (none)') }
    foreach ($issue in $process.Issues) {
      $timestamp = if ($issue.First) { " [$($issue.First) .. $($issue.Last)]" } else { '' }
      $lines.Add(('  {0}x {1}: {2}{3}' -f $issue.Count, $issue.Severity, $issue.Key, $timestamp))
      $lines.Add(('      {0}' -f ($issue.Message -replace "`n", ' | ')))
    }
    if ($process.ImportantOneOffs.Count) {
      $lines.Add('Important one-off errors:')
      foreach ($issue in $process.ImportantOneOffs) { $lines.Add(('  {0}: {1}' -f $issue.Severity, ($issue.Message -replace "`n", ' | '))) }
    }
  }
  return $lines -join "`n"
}

function ConvertTo-UEToolSuiteMpSummaryOptions {
  param([string[]]$Arguments = @())
  $options = @{ Top = 10; LogDir = $null }
  $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  for ($i=0; $i -lt $Arguments.Count; $i += 2) {
    if ($i + 1 -ge $Arguments.Count) { throw 'Usage: ue mp summary [-Top 10] [-LogDir path]' }
    $option = $Arguments[$i].ToLowerInvariant()
    if (-not $seen.Add($option)) { throw "Duplicate summary option '$($Arguments[$i])'." }
    switch ($option) {
      '-top' { $value=0; if (-not [int]::TryParse($Arguments[$i+1], [ref]$value) -or $value -lt 1 -or $value -gt 100) { throw '-Top must be an integer from 1 through 100.' }; $options.Top=$value; break }
      '-logdir' { if ([string]::IsNullOrWhiteSpace($Arguments[$i+1])) { throw '-LogDir requires a directory.' }; $options.LogDir=$Arguments[$i+1]; break }
      default { throw "Unsupported summary option '$($Arguments[$i])'. Usage: ue mp summary [-Top 10] [-LogDir path]" }
    }
  }
  [pscustomobject]$options
}

function ConvertTo-UEToolSuiteMpStartUtc {
  param([Parameter(Mandatory)]$Value)
  if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
  return [datetime]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
}

function Test-UEToolSuiteMpProcessOwned {
  param([Parameter(Mandatory)]$Record)
  try {
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$Record.Pid)" -ErrorAction Stop
    if (-not $process) { return $false }
    $expected = [IO.Path]::GetFullPath([string]$Record.Executable)
    if (-not [string]::Equals([IO.Path]::GetFullPath([string]$process.ExecutablePath), $expected, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    $actualStart = if ($process.CreationDate -is [datetime]) { $process.CreationDate.ToUniversalTime() } else { [Management.ManagementDateTimeConverter]::ToDateTime([string]$process.CreationDate).ToUniversalTime() }
    $expectedStart = ConvertTo-UEToolSuiteMpStartUtc -Value $Record.StartUtc
    return ([Math]::Abs(($actualStart - $expectedStart).TotalSeconds) -lt 2)
  }
  catch { return $false }
}

function Assert-UEToolSuiteMpLocalMode {
  param([Parameter(Mandatory)][string]$RepoRoot, [string]$Network)
  if ($Network -eq 'LAN') { return }
  $config = Join-Path $RepoRoot 'Config\DefaultEngine.ini'
  if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { return }
  $text = Get-Content -LiteralPath $config -Raw
  if ($text -match '(?im)^\s*DefaultPlatformService\s*=\s*Steam\s*$' -or
      $text -match '(?im)^\s*\+?NetDriverDefinitions\s*=.*SteamNetDriver') {
    throw 'This project configures Steam networking in DefaultEngine.ini. Two local game instances may require separate Steam accounts or project-specific session settings. The mp launcher does not override networking configuration; use your project-supported local mode and retry.'
  }
}

function ConvertTo-UEToolSuiteMpPlayOptions {
  param([string[]]$Arguments = @())
  $options = @{}
  for ($i = 0; $i -lt $Arguments.Count; $i += 2) {
    $key = [string]$Arguments[$i]
    if ($key -notin @('-Map','-UProjectPath','-WorkspacePath','-Network') -or $i + 1 -ge $Arguments.Count -or [string]::IsNullOrWhiteSpace([string]$Arguments[$i + 1])) {
      throw 'Usage: ue mp play [-Map /Game/Maps/YourMap] [-Network LAN] [-UProjectPath path] [-WorkspacePath path]'
    }
    if ($options.ContainsKey($key.ToLowerInvariant())) { throw "Duplicate mp option: $key" }
    $options[$key.ToLowerInvariant()] = [string]$Arguments[$i + 1]
  }
  $network = $options['-network']
  if ($network -and $network -ine 'LAN') { throw "Unsupported network mode '$network'. Supported mode: LAN. Omit -Network for the existing project configuration." }
  [pscustomobject]@{
    Map = $options['-map']
    UProjectPath = $options['-uprojectpath']
    WorkspacePath = $options['-workspacepath']
    Network = $(if ($network) { 'LAN' } else { $null })
  }
}

function Get-UEToolSuiteMpLaunchArguments {
  param(
    [Parameter(Mandatory)][string]$UProjectPath,
    [string]$HostMap,
    [Parameter(Mandatory)][string]$HostLog,
    [Parameter(Mandatory)][string]$ClientLog,
    [string]$Network,
    $WindowLayout
  )
  $project = '"' + $UProjectPath + '"'
  $common = '-game -windowed -UEToolSuiteMP -log -nosplash'
  $networkArguments = if ($Network -eq 'LAN') {
    ' -ini:Engine:[OnlineSubsystem]:DefaultPlatformService=Null -ini:Engine:[OnlineSubsystemSteam]:bEnabled=false -NetDriverOverrides=/Script/OnlineSubsystemUtils.IpNetDriver'
  } else { '' }
  $hostWindow = ''
  $clientWindow = ''
  if ($null -ne $WindowLayout) {
    $windowSettings = ',[/Script/EngineSettings.GeneralProjectSettings]:bUseBorderlessWindow=false'
    $hostWindow = ' -ini:Game:[/Script/EngineSettings.GeneralProjectSettings]:ProjectDisplayedTitle=MP_HOST' + $windowSettings + [string]$WindowLayout.Host
    $clientWindow = ' -ini:Game:[/Script/EngineSettings.GeneralProjectSettings]:ProjectDisplayedTitle=MP_CLIENT' + $windowSettings + [string]$WindowLayout.Client
  }
  [pscustomobject]@{
    Host = "$project $common " + $(if ($HostMap) { $HostMap } else { '?listen' }) + " -port=7777 -abslog=`"$HostLog`"$networkArguments$hostWindow"
    Client = "$project 127.0.0.1:7777 $common -abslog=`"$ClientLog`"$networkArguments$clientWindow"
  }
}

function Get-UEToolSuiteMpWindowLayout {
  param([object[]]$Screens = @())
  if ($Screens.Count -lt 2) { return [pscustomobject]@{ Host = ''; Client = '' } }
  $primary = @($Screens | Where-Object { $_.Primary } | Select-Object -First 1)
  $hostScreen = if ($primary.Count) { $primary[0] } else { $Screens[0] }
  $clientScreen = @($Screens | Where-Object { -not [object]::ReferenceEquals($_, $hostScreen) } | Select-Object -First 1)[0]
  if (-not $clientScreen -or [object]::ReferenceEquals($hostScreen, $clientScreen)) { $clientScreen = $Screens[1] }
  $positions = @()
  foreach ($screen in @($hostScreen, $clientScreen)) {
    $area = $screen.WorkingArea
    $width = [Math]::Min(1280, [Math]::Max(1, [int]$area.Width - 40))
    $height = [Math]::Min(720, [Math]::Max(1, [int]$area.Height - 40))
    $positions += " -WinX=$([int]$area.X + 20) -WinY=$([int]$area.Y + 20) -ResX=$width -ResY=$height"
  }
  [pscustomobject]@{ Host = $positions[0]; Client = $positions[1] }
}

function Get-UEToolSuiteMpScreens {
  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    return @([System.Windows.Forms.Screen]::AllScreens)
  }
  catch {
    Write-Warning "Could not read monitor layout; game windows will still start in windowed mode: $($_.Exception.Message)"
    return @()
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
    'Usage: ue mp play [-Map /Game/Maps/YourMap] [-Network LAN] [-UProjectPath path] [-WorkspacePath path] | summary [-Top N] [-LogDir path] | stop | logs'
    return
  }
  if ($verb -eq 'summary') {
    $options = ConvertTo-UEToolSuiteMpSummaryOptions -Arguments $tail
    $session = Get-UEToolSuiteMpSession -RepoRoot $RepoRoot
    $logDir = $options.LogDir
    if (-not $logDir -and $session) {
      if ($session.LogDir -and (Test-Path -LiteralPath ([string]$session.LogDir) -PathType Container)) { $logDir = [string]$session.LogDir }
      elseif ($session.HostLog) { $logDir = Split-Path -Parent ([string]$session.HostLog) }
      elseif ($session.ClientLog) { $logDir = Split-Path -Parent ([string]$session.ClientLog) }
    }
    if (-not $logDir) {
      $logsRoot = Join-Path $RepoRoot '.ue-tools\local\mp-logs'
      if (Test-Path -LiteralPath $logsRoot -PathType Container) {
        $recent = Get-ChildItem -LiteralPath $logsRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if ($recent) { $logDir = $recent.FullName }
      }
    }
    if (-not $logDir) { throw 'No multiplayer log directory is available. Run ue mp play first or pass -LogDir.' }
    $summary = Get-UEToolSuiteMpLogSummary -LogDir $logDir -Top $options.Top
    Format-UEToolSuiteMpLogSummary -Summary $summary
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
    foreach ($role in @('Client', 'Host')) {
      $record = $session.$role
      if (Test-UEToolSuiteMpProcessOwned -Record $record) {
        Stop-Process -Id ([int]$record.Pid) -ErrorAction Stop
        "Stopped owned $role process $($record.Pid)."
      }
      else { "$role process $($record.Pid) is absent or no longer matches this session; skipped." }
    }
    Remove-Item -LiteralPath $statePath -Force
    return
  }
  if ($verb -ne 'play') { throw "Unknown mp subcommand '$verb'. Run 'ue mp help'." }
  $options = ConvertTo-UEToolSuiteMpPlayOptions -Arguments $tail
  $map = $options.Map
  if ($map) { $hostMap = ConvertTo-UEToolSuiteMpMapArgument -Map $map }
  else { $hostMap = $null }
  $context = Get-ProjectContext -RepoRoot $RepoRoot -UProjectPath $options.UProjectPath -WorkspacePath $options.WorkspacePath
  Assert-UEToolSuiteMpLocalMode -RepoRoot $RepoRoot -Network $options.Network
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
  $windowLayout = Get-UEToolSuiteMpWindowLayout -Screens @(Get-UEToolSuiteMpScreens)
  $launch = Get-UEToolSuiteMpLaunchArguments -UProjectPath $context.UProjectPath -HostMap $hostMap -HostLog $hostLog -ClientLog $clientLog -Network $options.Network -WindowLayout $windowLayout
  $hostArgs = $launch.Host
  $clientArgs = $launch.Client
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

Export-ModuleMember -Function Invoke-UEToolSuiteMpCommand, Get-UEToolSuiteMpStatePath, Get-UEToolSuiteMpSession, Get-UEToolSuiteMpLogFileSummary, Get-UEToolSuiteMpLogSummary, Format-UEToolSuiteMpLogSummary, ConvertTo-UEToolSuiteMpSummaryOptions, Test-UEToolSuiteMpProcessOwned, Assert-UEToolSuiteMpLocalMode, ConvertTo-UEToolSuiteMpMapArgument, ConvertTo-UEToolSuiteMpPlayOptions, Get-UEToolSuiteMpLaunchArguments, Get-UEToolSuiteMpWindowLayout
