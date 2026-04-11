[CmdletBinding()]
param(
    [switch]$PostCrashCollect,
    [switch]$CancelPendingCollect,
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [string]$UProjectPath = "",
    [string]$UnrealEditorExe = "",
    [string]$ExtraEditorArgs = "-log -gpucrashdebugging",
    [int]$LookbackHours = 6,
    [int]$MaxFilesPerSource = 80,
    [bool]$UseLastUnexpectedShutdownWindow = $true,
    [bool]$IncludeMemoryDump = $false,
    [bool]$CreateZip = $true,
    [bool]$WaitForEditorExit = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runOnceRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
$runOnceValueName = "UECrashAutoCollect_{0}" -f (((Split-Path -Path (Resolve-Path $ProjectRoot).Path -Leaf) -replace '[^A-Za-z0-9_-]', '_'))
$stateDir = Join-Path $PSScriptRoot "CrashCaptureState"
$stateFile = Join-Path $stateDir "PendingCrashCapture.json"
$collectorScript = Join-Path $PSScriptRoot "Collect-CrashEvidence.ps1"
$selfScriptPath = $MyInvocation.MyCommand.Path

function Ensure-Dir {
    param([string]$Path)
    New-Item -Path $Path -ItemType Directory -Force | Out-Null
}

function Remove-RunOnceState {
    try {
        if (Test-Path $runOnceRegPath) {
            Remove-ItemProperty -Path $runOnceRegPath -Name $runOnceValueName -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "Failed to remove RunOnce value '$runOnceValueName': $($_.Exception.Message)"
    }
}

function Remove-SessionStateFile {
    try {
        if (Test-Path $stateFile) {
            Remove-Item -Path $stateFile -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "Failed to remove state file '$stateFile': $($_.Exception.Message)"
    }
}

function Get-CrashCaptureProjectContext {
    param(
        [string]$InProjectRoot,
        [string]$InUProjectPath
    )

    $projectContextHelper = Join-Path $InProjectRoot "Scripts\Unreal\ProjectContext.ps1"
    if (-not (Test-Path -LiteralPath $projectContextHelper)) {
        throw "Project context helper not found: $projectContextHelper"
    }

    . $projectContextHelper
    return (Get-ProjectContext -RepoRoot $InProjectRoot -UProjectPath $InUProjectPath)
}

function Resolve-CrashCaptureUnrealEditorExe {
    param(
        [Parameter(Mandatory)]$ProjectContext,
        [string]$InUnrealEditorExe
    )

    $attempts = [System.Collections.Generic.List[string]]::new()
    $resolvedEditorExe = Resolve-UnrealEditorPath `
        -ProjectContext $ProjectContext `
        -UnrealEditorPath $InUnrealEditorExe `
        -Attempts $attempts

    if (-not [string]::IsNullOrWhiteSpace($resolvedEditorExe)) {
        return $resolvedEditorExe
    }

    $attemptText = if ($attempts.Count -gt 0) {
        ($attempts | ForEach-Object { "- $_" }) -join "`n"
    }
    else {
        "- no discovery attempts were recorded"
    }

    throw @"
Unable to resolve UnrealEditor.exe automatically for '$($ProjectContext.ProjectName)'.

Attempted sources (in order):
$attemptText

Action:
- Re-generate the VS Code workspace in Unreal so it contains the UE install folder under folders[].
- Or set UE_ENGINE_DIR / UE_ENGINE_ROOT / UNREAL_ENGINE_DIR on this machine.
- Or pass -UnrealEditorExe explicitly.
"@
}

function Register-RunOnceCollector {
    if (-not (Test-Path $runOnceRegPath)) {
        New-Item -Path $runOnceRegPath -Force | Out-Null
    }

    $pwshCommand = Get-Command "pwsh" -ErrorAction SilentlyContinue
    $pwshExe = if ($null -ne $pwshCommand) { $pwshCommand.Source } else { "pwsh" }

    $runOnceCommand = "`"$pwshExe`" -NoProfile -ExecutionPolicy Bypass -File `"$selfScriptPath`" -PostCrashCollect"
    Set-ItemProperty -Path $runOnceRegPath -Name $runOnceValueName -Value $runOnceCommand
}

function Save-SessionState {
    param(
        [hashtable]$State
    )

    Ensure-Dir -Path $stateDir
    $State | ConvertTo-Json -Depth 6 | Set-Content -Path $stateFile -Encoding UTF8
}

function Invoke-CollectorFromState {
    if (-not (Test-Path $collectorScript)) {
        throw "Collector script not found: $collectorScript"
    }

    if (-not (Test-Path $stateFile)) {
        Write-Warning "No pending state file found. Running collector with current parameters."
        & $collectorScript `
            -ProjectRoot $ProjectRoot `
            -LookbackHours $LookbackHours `
            -UseLastUnexpectedShutdownWindow:$UseLastUnexpectedShutdownWindow `
            -MaxFilesPerSource $MaxFilesPerSource `
            -IncludeMemoryDump:$IncludeMemoryDump `
            -CreateZip:$CreateZip
        return
    }

    $state = Get-Content -Path $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json

    $collectorParams = @{
        ProjectRoot = [string]$state.ProjectRoot
        LookbackHours = [int]$state.LookbackHours
        UseLastUnexpectedShutdownWindow = [bool]$state.UseLastUnexpectedShutdownWindow
        MaxFilesPerSource = [int]$state.MaxFilesPerSource
        IncludeMemoryDump = [bool]$state.IncludeMemoryDump
        CreateZip = [bool]$state.CreateZip
    }

    & $collectorScript @collectorParams
}

if ($CancelPendingCollect) {
    Remove-RunOnceState
    Remove-SessionStateFile
    Write-Host "Canceled pending crash auto-collection state."
    exit 0
}

if ($PostCrashCollect) {
    try {
        Write-Host "Running post-crash auto-collection..."
        Invoke-CollectorFromState
        Write-Host "Post-crash auto-collection complete."
    }
    catch {
        Write-Error "Post-crash auto-collection failed: $($_.Exception.Message)"
        exit 1
    }
    finally {
        Remove-RunOnceState
        Remove-SessionStateFile
    }

    exit 0
}

if (-not (Test-Path $collectorScript)) {
    throw "Collector script not found: $collectorScript"
}

if (-not (Test-Path $ProjectRoot)) {
    throw "Project root not found: $ProjectRoot"
}

if ($LookbackHours -lt 1) {
    throw "LookbackHours must be at least 1."
}

if ($MaxFilesPerSource -lt 1) {
    throw "MaxFilesPerSource must be at least 1."
}

$projectContext = Get-CrashCaptureProjectContext -InProjectRoot $ProjectRoot -InUProjectPath $UProjectPath
$resolvedUProjectPath = $projectContext.UProjectPath
$resolvedEditorExe = Resolve-CrashCaptureUnrealEditorExe -ProjectContext $projectContext -InUnrealEditorExe $UnrealEditorExe

$sessionState = @{
    ProjectRoot = $projectContext.RepoRoot
    UProjectPath = $resolvedUProjectPath
    UnrealEditorExe = $resolvedEditorExe
    ExtraEditorArgs = $ExtraEditorArgs
    LookbackHours = $LookbackHours
    MaxFilesPerSource = $MaxFilesPerSource
    UseLastUnexpectedShutdownWindow = $UseLastUnexpectedShutdownWindow
    IncludeMemoryDump = $IncludeMemoryDump
    CreateZip = $CreateZip
    ArmedAt = (Get-Date).ToString("o")
}

Save-SessionState -State $sessionState
Register-RunOnceCollector

Write-Host "Crash capture auto-collector is armed for next login."
Write-Host "Launching Unreal Editor..."
Write-Host "Editor:   $resolvedEditorExe"
Write-Host "Project:  $resolvedUProjectPath"
Write-Host "Args:     $ExtraEditorArgs"

$editorArgString = "`"$resolvedUProjectPath`" $ExtraEditorArgs".Trim()
$editorProcess = Start-Process -FilePath $resolvedEditorExe -ArgumentList $editorArgString -PassThru

if (-not $WaitForEditorExit) {
    Write-Host "Editor launched (PID $($editorProcess.Id)). Leaving auto-collection armed."
    exit 0
}

Write-Host "Waiting for Unreal Editor process to exit..."
Wait-Process -Id $editorProcess.Id

Write-Host "Editor exited. Running collector now..."
try {
    Invoke-CollectorFromState
    Write-Host "Collection complete."
}
finally {
    Remove-RunOnceState
    Remove-SessionStateFile
}
