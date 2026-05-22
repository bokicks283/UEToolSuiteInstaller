function Get-UEToolSuiteDocsNormalizedArgumentList {
  [CmdletBinding()]
  param([AllowNull()][string[]]$Values)

  $normalized = New-Object System.Collections.Generic.List[string]
  foreach ($value in @($Values)) {
    if ($null -eq $value) {
      continue
    }

    $stringValue = [string]$value
    if ([string]::IsNullOrWhiteSpace($stringValue)) {
      continue
    }

    $normalized.Add($stringValue) | Out-Null
  }

  return $normalized.ToArray()
}

function Resolve-UEToolSuiteDocsCommandAlias {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$CommandName)

  $normalized = $CommandName.Trim().ToLowerInvariant()
  switch ($normalized) {
    "create-page" { return "new-page" }
    "create-section" { return "new-section" }
    default { return $normalized }
  }
}

function Test-UEToolSuiteDocsHelpToken {
  [CmdletBinding()]
  param([string]$Token)

  if ([string]::IsNullOrWhiteSpace($Token)) {
    return $false
  }

  $normalized = $Token.Trim().ToLowerInvariant()
  return ($normalized -in @("help", "--help", "-help", "-h", "/?", "-?"))
}

function Split-UEToolSuiteDocsStartArguments {
  [CmdletBinding()]
  param([string[]]$StartArgsInput = @())

  $background = $false
  $passThroughArgs = New-Object System.Collections.Generic.List[string]
  foreach ($token in @(Get-UEToolSuiteDocsNormalizedArgumentList -Values $StartArgsInput)) {
    $normalized = [string]$token
    if ($normalized -in @("--background", "-background")) {
      $background = $true
      continue
    }

    $passThroughArgs.Add($normalized) | Out-Null
  }

  return [pscustomobject]@{
    Background = $background
    StartArgs = $passThroughArgs.ToArray()
  }
}

function Resolve-UEToolSuiteDocsHelpTopicAlias {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$CommandName)

  $normalized = $CommandName.Trim().ToLowerInvariant()
  switch ($normalized) {
    "create-page" { return "new-page" }
    "create-section" { return "new-section" }
    default { return $normalized }
  }
}

function Get-UEToolSuiteDocsRootHelpText {
  [CmdletBinding()]
  param()

@"
UE project docs automation.

Usage:
  ue-tools docs <command> [options]

Create:
  new-section, create-section   Create a docs section
  new-page, create-page         Create a page at Docs root or inside a section
  reorder                       Reorder a page or section and shift sibling positions

Run:
  start                         Start Docusaurus in the current terminal
  stop                          Stop the tracked background Docusaurus server
  status                        Show tracked background server status
  check                         Validate docs and run the production build
  doctor                        Check local docs prerequisites

Pass-through:
  build, clear, deploy, serve, swizzle
  write-translations, write-heading-ids, typecheck
  docusaurus <args...>

Other:
  install-bridge                Install the optional VS Code TOC bridge
  help [command]

Examples:
  ue-tools docs help new-section
  ue-tools docs create-section DocsSite -LinkType generated-index -GeneratedIndexSlug /docs-site
  ue-tools docs create-page Setup -Title "Setup"
  ue-tools docs create-page Workflow Daily-Flow -Title "Daily Flow" -SidebarLabel "Daily Flow"
  ue-tools docs reorder Art-Source 4
  ue-tools docs start --port 3001
  ue-tools docs start --background --port 3001
  ue-tools docs docusaurus docs:version 1.0.0 --skip-feedback

Notes:
  - Docs are authored in Docs/ and rendered by website/.
  - TOC generation is optional and only runs when the bridge + Markdown All in One are installed.
  - Use ue-tools docs help <command> for detailed option help.
"@
}

function Test-UEToolSuiteDocsProcessRunning {
  [CmdletBinding()]
  param([int]$ProcessId)

  if ($ProcessId -le 0) {
    return $false
  }

  try {
    Get-Process -Id $ProcessId -ErrorAction Stop | Out-Null
    return $true
  }
  catch {
    return $false
  }
}

function Get-UEToolSuiteDocsDescendantProcessId {
  [CmdletBinding()]
  param([int]$RootProcessId)

  if ($RootProcessId -le 0) {
    return $null
  }

  $queue = New-Object System.Collections.Generic.Queue[int]
  $queue.Enqueue($RootProcessId)

  while ($queue.Count -gt 0) {
    $parentId = $queue.Dequeue()

    try {
      $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $parentId" -ErrorAction Stop)
    }
    catch {
      $children = @()
    }

    foreach ($child in $children) {
      $childId = [int]$child.ProcessId
      if (Test-UEToolSuiteDocsProcessRunning -ProcessId $childId) {
        return $childId
      }

      $queue.Enqueue($childId)
    }
  }

  return $null
}

function Get-UEToolSuiteDocsStartUrl {
  [CmdletBinding()]
  param([string[]]$StartArgs = @())

  $normalizedStartArgs = @(Get-UEToolSuiteDocsNormalizedArgumentList -Values $StartArgs)
  $port = 3000
  for ($i = 0; $i -lt $normalizedStartArgs.Count; $i++) {
    $token = [string]$normalizedStartArgs[$i]
    if ($token -match '^--port=(?<port>\d+)$') {
      $parsedEqualsPort = 0
      if ([int]::TryParse($Matches.port, [ref]$parsedEqualsPort)) {
        $port = $parsedEqualsPort
      }
      break
    }

    if ($token -eq "--port" -or $token -eq "-p") {
      if (($i + 1) -lt $normalizedStartArgs.Count) {
        $parsedPort = 0
        if ([int]::TryParse([string]$normalizedStartArgs[$i + 1], [ref]$parsedPort)) {
          $port = $parsedPort
        }
      }
      break
    }
  }

  return "http://localhost:$port/docs/"
}

function Test-UEToolSuiteDocsCommandAvailable {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Name)

  return ($null -ne (Get-Command $Name -ErrorAction SilentlyContinue))
}

function ConvertTo-UEToolSuiteDocsCmdArgument {
  [CmdletBinding()]
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

  if ($Value.Length -eq 0) {
    return '""'
  }

  if ($Value -notmatch '[\s"&|<>^]') {
    return $Value
  }

  return '"' + ($Value -replace '"', '""') + '"'
}

function Get-UEToolSuiteDocsServerState {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$StatePath)

  if (-not (Test-Path -LiteralPath $StatePath)) {
    return $null
  }

  return (Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json)
}

function Remove-UEToolSuiteDocsServerState {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$StatePath)

  if (Test-Path -LiteralPath $StatePath) {
    Remove-Item -LiteralPath $StatePath -Force
  }
}

function Save-UEToolSuiteDocsServerState {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$StatePath,
    [Parameter(Mandatory)][object]$State
  )

  $stateDirectory = Split-Path -Parent $StatePath
  if (-not [string]::IsNullOrWhiteSpace($stateDirectory)) {
    New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
  }

  $stateJson = $State | ConvertTo-Json -Depth 6
  if (Get-Command -Name "Write-UEToolSuiteUtf8NoBomFile" -ErrorAction SilentlyContinue) {
    Write-UEToolSuiteUtf8NoBomFile -Path $StatePath -Content $stateJson
  }
  else {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($StatePath, $stateJson, $utf8NoBom)
  }
  return $StatePath
}

function Get-UEToolSuiteDocsWorkspaceRequestKey {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $normalized = [System.IO.Path]::GetFullPath($ResolvedRepoRoot).ToLowerInvariant()
  $sha1 = [System.Security.Cryptography.SHA1]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $hash = $sha1.ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
  }
  finally {
    $sha1.Dispose()
  }
}

function Get-UEToolSuiteDocsBridgeRequestDirectory {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $workspaceKey = Get-UEToolSuiteDocsWorkspaceRequestKey -ResolvedRepoRoot $ResolvedRepoRoot
  return (Join-Path ([System.IO.Path]::GetTempPath()) "ueproject-ue-tools-docs\$workspaceKey")
}

function New-UEToolSuiteDocsBridgeStatus {
  [CmdletBinding()]
  param(
    [string]$CodeCliPath,
    [bool]$MarkdownAllInOneInstalled = $false,
    [bool]$BridgeInstalled = $false
  )

  return [pscustomobject]@{
    CodeCliPath = $CodeCliPath
    MarkdownAllInOneInstalled = [bool]$MarkdownAllInOneInstalled
    BridgeInstalled = [bool]$BridgeInstalled
    TocReady = ([bool]$CodeCliPath -and [bool]$MarkdownAllInOneInstalled -and [bool]$BridgeInstalled)
  }
}

function Invoke-UEToolSuiteDocsCommand {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [AllowNull()][string[]]$CommandArguments = @()
  )

  $resolvedRepoRoot = $RepoRoot
  $scriptPath = Join-Path $resolvedRepoRoot "Scripts\Docs\DocsTools.Runtime.ps1"
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "The 'docs' domain is not installed for this repo. Missing required path: $scriptPath. Re-run the installer with docs tooling included."
  }

  [string[]]$effectiveArgs = @()
  foreach ($argument in @($CommandArguments)) {
    if ($null -eq $argument) { continue }
    $effectiveArgs += [string]$argument
  }

  # Dot-source the docs runtime definitions without triggering standalone autorun.
  $previousAutoRunFlag = $env:UE_TOOLS_DOCS_RUNTIME_NO_AUTORUN
  $env:UE_TOOLS_DOCS_RUNTIME_NO_AUTORUN = "1"
  try {
    . $scriptPath
  }
  finally {
    if ($null -eq $previousAutoRunFlag) {
      Remove-Item Env:UE_TOOLS_DOCS_RUNTIME_NO_AUTORUN -ErrorAction SilentlyContinue
    }
    else {
      $env:UE_TOOLS_DOCS_RUNTIME_NO_AUTORUN = $previousAutoRunFlag
    }
  }

  $docsMainCommand = Get-Command -Name "Invoke-DocsToolsMain" -CommandType Function -ErrorAction SilentlyContinue
  if (-not $docsMainCommand) {
    throw "Docs command entrypoint function not found after loading $scriptPath."
  }

  $invokeParameters = @{
    ResolvedRepoRoot = $resolvedRepoRoot
  }
  if ($effectiveArgs.Count -gt 0) {
    $invokeParameters.CommandArguments = @($effectiveArgs)
  }

  Invoke-DocsToolsMain @invokeParameters
}

Export-ModuleMember -Function `
  Get-UEToolSuiteDocsNormalizedArgumentList, `
  Resolve-UEToolSuiteDocsCommandAlias, `
  Test-UEToolSuiteDocsHelpToken, `
  Split-UEToolSuiteDocsStartArguments, `
  Resolve-UEToolSuiteDocsHelpTopicAlias, `
  Get-UEToolSuiteDocsRootHelpText, `
  Test-UEToolSuiteDocsProcessRunning, `
  Get-UEToolSuiteDocsDescendantProcessId, `
  Get-UEToolSuiteDocsStartUrl, `
  Test-UEToolSuiteDocsCommandAvailable, `
  ConvertTo-UEToolSuiteDocsCmdArgument, `
  Get-UEToolSuiteDocsServerState, `
  Remove-UEToolSuiteDocsServerState, `
  Save-UEToolSuiteDocsServerState, `
  Get-UEToolSuiteDocsWorkspaceRequestKey, `
  Get-UEToolSuiteDocsBridgeRequestDirectory, `
  New-UEToolSuiteDocsBridgeStatus, `
  Invoke-UEToolSuiteDocsCommand
