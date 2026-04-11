[CmdletBinding()]
param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [string]$OutputRoot = "",
    [int]$LookbackHours = 6,
    [bool]$UseLastUnexpectedShutdownWindow = $true,
    [int]$MaxFilesPerSource = 80,
    [bool]$IncludeMemoryDump = $false,
    [bool]$CreateZip = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($LookbackHours -lt 1) {
    throw "LookbackHours must be at least 1."
}

if ($MaxFilesPerSource -lt 1) {
    throw "MaxFilesPerSource must be at least 1."
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectRoot "Scripts\Tests\CrashEvidenceResults"
}

if (-not (Test-Path $ProjectRoot)) {
    throw "ProjectRoot does not exist: $ProjectRoot"
}

New-Item -Path $OutputRoot -ItemType Directory -Force | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$bundleRoot = Join-Path $OutputRoot "CrashEvidence-$timestamp"
New-Item -Path $bundleRoot -ItemType Directory -Force | Out-Null

$warnings = New-Object System.Collections.Generic.List[string]
$notes = New-Object System.Collections.Generic.List[string]
$copied = New-Object System.Collections.Generic.List[string]

function Add-WarningText {
    param([string]$Message)
    Write-Warning $Message
    $script:warnings.Add($Message)
}

function Add-Note {
    param([string]$Message)
    Write-Host $Message
    $script:notes.Add($Message)
}

function Ensure-Dir {
    param([string]$Path)
    New-Item -Path $Path -ItemType Directory -Force | Out-Null
}

function Copy-FileSafe {
    param(
        [string]$SourceFile,
        [string]$DestinationFile
    )

    try {
        $destinationDir = Split-Path -Path $DestinationFile -Parent
        if (-not [string]::IsNullOrWhiteSpace($destinationDir)) {
            Ensure-Dir -Path $destinationDir
        }
        Copy-Item -Path $SourceFile -Destination $DestinationFile -Force -ErrorAction Stop
        $script:copied.Add($DestinationFile)
    }
    catch {
        Add-WarningText "Failed to copy file '$SourceFile' -> '$DestinationFile': $($_.Exception.Message)"
    }
}

function Copy-RecentFiles {
    param(
        [string]$SourceDirectory,
        [string]$DestinationDirectory,
        [datetime]$StartTime,
        [int]$Limit,
        [switch]$Recurse,
        [string]$Filter = "*"
    )

    if (-not (Test-Path $SourceDirectory)) {
        Add-Note "Source not found, skipping: $SourceDirectory"
        return
    }

    try {
        $items = if ($Recurse) {
            Get-ChildItem -Path $SourceDirectory -File -Recurse -Filter $Filter -ErrorAction Stop
        }
        else {
            Get-ChildItem -Path $SourceDirectory -File -Filter $Filter -ErrorAction Stop
        }

        $selected = $items |
            Where-Object { $_.LastWriteTime -ge $StartTime } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First $Limit

        if (-not $selected) {
            $selected = $items | Sort-Object LastWriteTime -Descending | Select-Object -First ([Math]::Min($Limit, 5))
        }

        foreach ($item in $selected) {
            $relative = $item.FullName.Substring($SourceDirectory.Length).TrimStart('\')
            $destination = Join-Path $DestinationDirectory $relative
            Copy-FileSafe -SourceFile $item.FullName -DestinationFile $destination
        }
    }
    catch {
        if ($_.Exception.Message -like "*Access to the path*denied*") {
            Add-Note "Access denied for '$SourceDirectory' (run PowerShell as Administrator to include this source)."
        }
        else {
            Add-WarningText "Failed to scan '$SourceDirectory': $($_.Exception.Message)"
        }
    }
}

function Copy-RecentDirectories {
    param(
        [string]$SourceDirectory,
        [string]$DestinationDirectory,
        [datetime]$StartTime,
        [int]$Limit
    )

    if (-not (Test-Path $SourceDirectory)) {
        Add-Note "Source not found, skipping: $SourceDirectory"
        return
    }

    try {
        $dirs = Get-ChildItem -Path $SourceDirectory -Directory -ErrorAction Stop
        $selected = $dirs |
            Where-Object { $_.LastWriteTime -ge $StartTime } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First $Limit

        if (-not $selected) {
            $selected = $dirs | Sort-Object LastWriteTime -Descending | Select-Object -First ([Math]::Min($Limit, 3))
        }

        foreach ($dir in $selected) {
            $destination = Join-Path $DestinationDirectory $dir.Name
            try {
                Copy-Item -Path $dir.FullName -Destination $destination -Recurse -Force -ErrorAction Stop
                $script:copied.Add($destination)
            }
            catch {
                Add-WarningText "Failed to copy directory '$($dir.FullName)': $($_.Exception.Message)"
            }
        }
    }
    catch {
        Add-WarningText "Failed to scan directories under '$SourceDirectory': $($_.Exception.Message)"
    }
}

function Export-EventLogWindow {
    param(
        [string]$LogName,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [string]$DestinationBasePath
    )

    $events = $null
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = $LogName
            StartTime = $StartTime
            EndTime = $EndTime
        } -ErrorAction Stop
    }
    catch {
        if ($_.Exception.Message -like "*No events were found*") {
            Add-Note "No matching events for $LogName in the selected time window."
            return
        }

        Add-WarningText "Failed to export $LogName log window: $($_.Exception.Message)"
        return
    }

    $selected = @(
        $events |
            Where-Object { $_.LevelDisplayName -in @("Critical", "Error", "Warning") } |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message
    )

    if ($selected.Count -eq 0) {
        Add-Note "No Critical/Error/Warning events found in $LogName for the selected window."
        return
    }

    $csvPath = "$DestinationBasePath.csv"
    $txtPath = "$DestinationBasePath.txt"
    $selected | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    $selected | Format-Table -AutoSize | Out-String | Set-Content -Path $txtPath -Encoding UTF8
    $script:copied.Add($csvPath)
    $script:copied.Add($txtPath)
}

function Export-ProviderEvents {
    param(
        [string]$LogName,
        [string[]]$Providers,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [string]$DestinationBasePath
    )

    $events = $null
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = $LogName
            StartTime = $StartTime
            EndTime = $EndTime
        } -ErrorAction Stop
    }
    catch {
        if ($_.Exception.Message -like "*No events were found*") {
            Add-Note "No matching events for $LogName in the selected time window."
            return
        }

        Add-WarningText "Failed to export provider-filtered events from ${LogName}: $($_.Exception.Message)"
        return
    }

    $selected = @(
        $events |
            Where-Object { $Providers -contains $_.ProviderName } |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message
    )

    if ($selected.Count -eq 0) {
        Add-Note "No provider-matching events found in $LogName for selected providers."
        return
    }

    $csvPath = "$DestinationBasePath.csv"
    $txtPath = "$DestinationBasePath.txt"
    $selected | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    $selected | Format-Table -AutoSize | Out-String | Set-Content -Path $txtPath -Encoding UTF8
    $script:copied.Add($csvPath)
    $script:copied.Add($txtPath)
}

function Find-LatestUnexpectedShutdownTime {
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = "System"
            Id = 41, 6008
            StartTime = (Get-Date).AddDays(-14)
        } -ErrorAction Stop | Sort-Object TimeCreated -Descending

        if ($events -and $events.Count -gt 0) {
            return [datetime]$events[0].TimeCreated
        }
    }
    catch {
        Add-WarningText "Failed to query unexpected shutdown events: $($_.Exception.Message)"
    }

    return $null
}

Add-Note "Writing crash evidence bundle to: $bundleRoot"

$windowStart = (Get-Date).AddHours(-1 * $LookbackHours)
$windowEnd = Get-Date
$detectedCrashTime = $null

if ($UseLastUnexpectedShutdownWindow) {
    $detectedCrashTime = Find-LatestUnexpectedShutdownTime
    if ($null -ne $detectedCrashTime) {
        $windowStart = $detectedCrashTime.AddHours(-1)
        $windowEnd = $detectedCrashTime.AddHours(2)
        if ($windowEnd -lt (Get-Date).AddMinutes(-5)) {
            $windowEnd = Get-Date
        }
    }
}

$metaDir = Join-Path $bundleRoot "Meta"
$unrealDir = Join-Path $bundleRoot "Unreal"
$windowsDir = Join-Path $bundleRoot "Windows"
$eventsDir = Join-Path $windowsDir "EventLogs"
$dumpsDir = Join-Path $windowsDir "Dumps"

Ensure-Dir -Path $metaDir
Ensure-Dir -Path $unrealDir
Ensure-Dir -Path $eventsDir
Ensure-Dir -Path $dumpsDir

$uprojectPath = $null
$projectContextHelper = Join-Path $ProjectRoot "Scripts\Unreal\ProjectContext.ps1"
if (Test-Path -LiteralPath $projectContextHelper) {
    try {
        . $projectContextHelper
        $uprojectPath = (Get-ProjectContext -RepoRoot $ProjectRoot).UProjectPath
    }
    catch {
        Add-WarningText "Could not resolve project context from '$projectContextHelper': $($_.Exception.Message)"
    }
}

if ([string]::IsNullOrWhiteSpace($uprojectPath)) {
    $uproject = Get-ChildItem -Path $ProjectRoot -Filter "*.uproject" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($uproject) {
        $uprojectPath = $uproject.FullName
    }
}

$projectSavedDir = Join-Path $ProjectRoot "Saved"
$projectLogsDir = Join-Path $projectSavedDir "Logs"
$projectCrashesDir = Join-Path $projectSavedDir "Crashes"
$localAppData = [Environment]::GetFolderPath("LocalApplicationData")
$crashReportClientLogs = Join-Path $localAppData "CrashReportClient\Saved\Logs"
$ubtLogDir = Join-Path $localAppData "UnrealBuildTool"

Add-Note "Collecting Unreal project logs..."
Copy-RecentFiles -SourceDirectory $projectLogsDir -DestinationDirectory (Join-Path $unrealDir "Saved\Logs") -StartTime $windowStart -Limit $MaxFilesPerSource

Add-Note "Collecting Unreal crash folders..."
Copy-RecentDirectories -SourceDirectory $projectCrashesDir -DestinationDirectory (Join-Path $unrealDir "Saved\Crashes") -StartTime $windowStart -Limit 10

Add-Note "Collecting CrashReportClient logs..."
Copy-RecentFiles -SourceDirectory $crashReportClientLogs -DestinationDirectory (Join-Path $unrealDir "CrashReportClient\Saved\Logs") -StartTime $windowStart -Limit $MaxFilesPerSource

Add-Note "Collecting UnrealBuildTool logs..."
Copy-RecentFiles -SourceDirectory $ubtLogDir -DestinationDirectory (Join-Path $unrealDir "UnrealBuildTool") -StartTime $windowStart -Limit $MaxFilesPerSource -Recurse -Filter "Log*"

Add-Note "Collecting Windows event logs..."
Export-EventLogWindow -LogName "System" -StartTime $windowStart -EndTime $windowEnd -DestinationBasePath (Join-Path $eventsDir "System-CriticalErrorWarning")
Export-EventLogWindow -LogName "Application" -StartTime $windowStart -EndTime $windowEnd -DestinationBasePath (Join-Path $eventsDir "Application-CriticalErrorWarning")

$providerList = @(
    "Kernel-Power",
    "EventLog",
    "WHEA-Logger",
    "Display",
    "nvlddmkm",
    "amdkmdag",
    "amdwddmg",
    "dxgkrnl"
)
Export-ProviderEvents -LogName "System" -Providers $providerList -StartTime $windowStart -EndTime $windowEnd -DestinationBasePath (Join-Path $eventsDir "System-TargetProviders")

Add-Note "Collecting Reliability Monitor records..."
try {
    $reliabilityRecords = Get-CimInstance -ClassName Win32_ReliabilityRecords -Namespace root\cimv2 -ErrorAction Stop |
        Where-Object { $_.TimeGenerated -ge $windowStart } |
        Select-Object TimeGenerated, SourceName, EventIdentifier, ProductName, Message

    if ($reliabilityRecords.Count -gt 0) {
        $relCsv = Join-Path $windowsDir "ReliabilityRecords.csv"
        $reliabilityRecords | Export-Csv -Path $relCsv -NoTypeInformation -Encoding UTF8
        $copied.Add($relCsv)
    }
}
catch {
    if ($_.Exception.Message -like "*Access denied*") {
        Add-Note "Reliability records require elevated PowerShell on this machine. Re-run as Administrator if you want them included."
    }
    else {
        Add-WarningText "Failed to export reliability records: $($_.Exception.Message)"
    }
}

Add-Note "Collecting dump files..."
Copy-RecentFiles -SourceDirectory "C:\Windows\Minidump" -DestinationDirectory (Join-Path $dumpsDir "Minidump") -StartTime $windowStart -Limit $MaxFilesPerSource -Filter "*.dmp"
Copy-RecentFiles -SourceDirectory "C:\Windows\LiveKernelReports" -DestinationDirectory (Join-Path $dumpsDir "LiveKernelReports") -StartTime $windowStart -Limit $MaxFilesPerSource -Recurse -Filter "*.dmp"

if ($IncludeMemoryDump) {
    $memoryDumpPath = "C:\Windows\MEMORY.DMP"
    if (Test-Path $memoryDumpPath) {
        Copy-FileSafe -SourceFile $memoryDumpPath -DestinationFile (Join-Path $dumpsDir "MEMORY.DMP")
    }
    else {
        Add-Note "MEMORY.DMP not found (skipping)."
    }
}
else {
    Add-Note "Skipping MEMORY.DMP (set -IncludeMemoryDump `$true to include it)."
}

Add-Note "Collecting DXDIAG snapshot..."
try {
    $dxdiagOut = Join-Path $windowsDir "DxDiag.txt"
    $dxdiagProcess = Start-Process -FilePath "dxdiag.exe" -ArgumentList "/t `"$dxdiagOut`"" -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
    if ($dxdiagProcess.ExitCode -eq 0 -and (Test-Path $dxdiagOut)) {
        $copied.Add($dxdiagOut)
    }
    else {
        Add-WarningText "dxdiag exited with code $($dxdiagProcess.ExitCode)."
    }
}
catch {
    Add-WarningText "Failed to run dxdiag: $($_.Exception.Message)"
}

Add-Note "Writing metadata summary..."
try {
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $gpuInfo = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue |
        Select-Object Name, DriverVersion, DriverDate, AdapterRAM
    $lastBootUpIso = ""

    if ($osInfo -and $null -ne $osInfo.LastBootUpTime) {
        $rawLastBoot = $osInfo.LastBootUpTime

        if ($rawLastBoot -is [datetime]) {
            $lastBootUpIso = ([datetime]$rawLastBoot).ToString("o")
        }
        else {
            $rawLastBootString = [string]$rawLastBoot
            if (-not [string]::IsNullOrWhiteSpace($rawLastBootString)) {
                try {
                    $lastBootUpIso = ([Management.ManagementDateTimeConverter]::ToDateTime($rawLastBootString)).ToString("o")
                }
                catch {
                    Add-Note "Could not parse Win32_OperatingSystem.LastBootUpTime value '$rawLastBootString'. Leaving metadata field empty."
                }
            }
        }
    }

    $meta = [ordered]@{
        GeneratedAtLocal = (Get-Date).ToString("o")
        ComputerName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        ProjectRoot = $ProjectRoot
        UProjectPath = if ($uprojectPath) { $uprojectPath } else { "" }
        UProjectFound = (-not [string]::IsNullOrWhiteSpace($uprojectPath) -and (Test-Path -LiteralPath $uprojectPath))
        BundlePath = $bundleRoot
        WindowStart = $windowStart.ToString("o")
        WindowEnd = $windowEnd.ToString("o")
        DetectedUnexpectedShutdownTime = if ($null -ne $detectedCrashTime) { $detectedCrashTime.ToString("o") } else { "" }
        LookbackHours = $LookbackHours
        UseLastUnexpectedShutdownWindow = $UseLastUnexpectedShutdownWindow
        MaxFilesPerSource = $MaxFilesPerSource
        IncludeMemoryDump = $IncludeMemoryDump
        OsCaption = if ($osInfo) { $osInfo.Caption } else { "" }
        OsVersion = if ($osInfo) { $osInfo.Version } else { "" }
        OsBuild = if ($osInfo) { $osInfo.BuildNumber } else { "" }
        LastBootUpTime = $lastBootUpIso
        Gpu = $gpuInfo
        Notes = $notes
        Warnings = $warnings
        CopiedItemCount = $copied.Count
        CopiedItems = $copied
    }

    $metaJson = Join-Path $metaDir "CrashEvidence-Metadata.json"
    $metaTxt = Join-Path $metaDir "CrashEvidence-Metadata.txt"
    $meta | ConvertTo-Json -Depth 8 | Set-Content -Path $metaJson -Encoding UTF8

    @(
        "Crash Evidence Bundle"
        "Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")"
        "ProjectRoot: $ProjectRoot"
        "BundlePath: $bundleRoot"
        "WindowStart: $($windowStart.ToString("o"))"
        "WindowEnd: $($windowEnd.ToString("o"))"
        "DetectedUnexpectedShutdownTime: $(if ($null -ne $detectedCrashTime) { $detectedCrashTime.ToString("o") } else { "N/A" })"
        "CopiedItemCount: $($copied.Count)"
        "WarningCount: $($warnings.Count)"
    ) | Set-Content -Path $metaTxt -Encoding UTF8

    $copied.Add($metaJson)
    $copied.Add($metaTxt)
}
catch {
    Add-WarningText "Failed to write metadata summary: $($_.Exception.Message)"
}

$zipPath = ""
if ($CreateZip) {
    Add-Note "Compressing bundle..."
    try {
        $zipPath = "$bundleRoot.zip"
        if (Test-Path $zipPath) {
            Remove-Item -Path $zipPath -Force
        }
        Compress-Archive -Path "$bundleRoot\*" -DestinationPath $zipPath -CompressionLevel Optimal -Force
    }
    catch {
        Add-WarningText "Failed to create zip archive: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "Crash evidence collection complete."
Write-Host "Bundle folder: $bundleRoot"
if (-not [string]::IsNullOrWhiteSpace($zipPath) -and (Test-Path $zipPath)) {
    Write-Host "Bundle zip:    $zipPath"
}
Write-Host "Copied items:  $($copied.Count)"
Write-Host "Warnings:      $($warnings.Count)"

if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "Warnings:"
    foreach ($warningText in $warnings) {
        Write-Host "- $warningText"
    }
}
