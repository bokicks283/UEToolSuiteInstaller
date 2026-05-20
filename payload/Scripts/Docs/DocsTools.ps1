[CmdletBinding()]
param(
  [string]$RepoRoot,

  [string[]]$CommandArgs,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ExtraArgs
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$script:DocsToolsBridgeExtensionId = "ueproject.docs-tools-bridge"
$script:MarkdownAllInOneExtensionId = "yzhang.markdown-all-in-one"
$script:TocMarker = "<!-- docs-tools-toc -->"
$script:CodeExtensionList = $null
$script:CodeCliPath = $null
$script:WebsitePackageScriptNames = $null

$script:DocsToolsScriptsRoot = Split-Path -Parent $PSScriptRoot
$runtimeHelperPath = Join-Path $script:DocsToolsScriptsRoot "UETools\UEToolSuite.Runtime.ps1"
if (Test-Path -LiteralPath $runtimeHelperPath -PathType Leaf) {
  . $runtimeHelperPath
}
else {
  function Get-UEToolSuiteCoreModuleEntryPathFromScriptsRoot {
    param([Parameter(Mandatory)][string]$ScriptsRoot)

    $manifestPath = Join-Path $ScriptsRoot "UETools\UETools.psd1"
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
      return $manifestPath
    }

    $modulePath = Join-Path $ScriptsRoot "UETools\UEToolSuite.Core.psm1"
    if (Test-Path -LiteralPath $modulePath -PathType Leaf) {
      return $modulePath
    }

    return $null
  }

  function Import-UEToolSuiteCoreModuleFromScriptsRoot {
    param(
      [Parameter(Mandatory)][string]$ScriptsRoot,
      [Parameter(Mandatory)][string]$StateKey
    )

    $modulePath = Get-UEToolSuiteCoreModuleEntryPathFromScriptsRoot -ScriptsRoot $ScriptsRoot
    if ([string]::IsNullOrWhiteSpace($modulePath)) {
      return $false
    }

    Import-Module -Name $modulePath -Force
    return $true
  }
}

function Import-UEToolSuiteCoreModule {
  return (Import-UEToolSuiteCoreModuleFromScriptsRoot -ScriptsRoot $script:DocsToolsScriptsRoot -StateKey "docs-tools")
}

function Write-Utf8NoBomFile {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content
  )

  $runtimeWriter = Get-Command -Name "Write-UEToolSuiteRuntimeUtf8NoBomFile" -ErrorAction SilentlyContinue
  if ($runtimeWriter) {
    Write-UEToolSuiteRuntimeUtf8NoBomFile -ScriptsRoot $script:DocsToolsScriptsRoot -Path $Path -Content $Content -EnsureParentDirectory
    return
  }

  if (Import-UEToolSuiteCoreModule) {
    $writer = Get-Command -Name "Write-UEToolSuiteUtf8NoBomFile" -ErrorAction SilentlyContinue
    if ($writer) {
      Write-UEToolSuiteUtf8NoBomFile -Path $Path -Content $Content -EnsureParentDirectory
      return
    }
  }

  $directory = Split-Path -Parent $Path
  if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
  }

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Get-DocsToolsRepoRoot {
  param([string]$ExplicitRepoRoot)

  $runtimeResolver = Get-Command -Name "Resolve-UEToolSuiteRuntimeRepoRoot" -ErrorAction SilentlyContinue
  if ($runtimeResolver) {
    return (Resolve-UEToolSuiteRuntimeRepoRoot -ScriptsRoot $script:DocsToolsScriptsRoot -ExplicitRepoRoot $ExplicitRepoRoot -InvocationName "docs-tools")
  }

  if (Import-UEToolSuiteCoreModule) {
    $resolver = Get-Command -Name "Resolve-UEToolSuiteRepoRoot" -ErrorAction SilentlyContinue
    if ($resolver) {
      return (Resolve-UEToolSuiteRepoRoot -ExplicitRepoRoot $ExplicitRepoRoot -InvocationName "docs-tools")
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($ExplicitRepoRoot)) {
    return [System.IO.Path]::GetFullPath($ExplicitRepoRoot)
  }

  $gitRoot = ((git rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($gitRoot)) {
    throw "docs-tools must be run from inside a git repository or passed -RepoRoot."
  }

  return $gitRoot.Trim()
}

function Get-DocsRoot {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)
  return (Join-Path $ResolvedRepoRoot "Docs")
}

function Get-WebsiteRoot {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)
  return (Join-Path $ResolvedRepoRoot "website")
}

function Get-DocsToolsRuntimeDirectory {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)
  return (Join-Path (Get-BridgeRequestDirectory -ResolvedRepoRoot $ResolvedRepoRoot) "runtime")
}

function Get-DocsServerStatePath {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)
  return (Join-Path (Get-DocsToolsRuntimeDirectory -ResolvedRepoRoot $ResolvedRepoRoot) "docs-server.json")
}

function ConvertTo-CmdArgument {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "ConvertTo-UEToolSuiteDocsCmdArgument" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (ConvertTo-UEToolSuiteDocsCmdArgument -Value $Value)
  }

  if ($Value.Length -eq 0) {
    return '""'
  }

  if ($Value -notmatch '[\s"&|<>^]') {
    return $Value
  }

  return '"' + ($Value -replace '"', '""') + '"'
}

function Get-NormalizedArgumentList {
  param([AllowNull()][string[]]$Values)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteDocsNormalizedArgumentList" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return @(Get-UEToolSuiteDocsNormalizedArgumentList -Values $Values)
  }

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

function Resolve-DocsToolsCommandAlias {
  param([Parameter(Mandatory)][string]$CommandName)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Resolve-UEToolSuiteDocsCommandAlias" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Resolve-UEToolSuiteDocsCommandAlias -CommandName $CommandName)
  }

  $normalized = $CommandName.Trim().ToLowerInvariant()
  switch ($normalized) {
    "create-page" { return "new-page" }
    "create-section" { return "new-section" }
    default { return $normalized }
  }
}

function Test-DocsToolsHelpToken {
  param([string]$Token)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Test-UEToolSuiteDocsHelpToken" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Test-UEToolSuiteDocsHelpToken -Token $Token)
  }

  if ([string]::IsNullOrWhiteSpace($Token)) {
    return $false
  }

  $normalized = $Token.Trim().ToLowerInvariant()
  return ($normalized -in @("help", "--help", "-help", "-h", "/?", "-?"))
}

function Test-ProcessRunning {
  param([int]$ProcessId)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Test-UEToolSuiteDocsProcessRunning" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Test-UEToolSuiteDocsProcessRunning -ProcessId $ProcessId)
  }

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

function Get-DescendantProcessId {
  param([int]$RootProcessId)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteDocsDescendantProcessId" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Get-UEToolSuiteDocsDescendantProcessId -RootProcessId $RootProcessId)
  }

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
      if (Test-ProcessRunning -ProcessId $childId) {
        return $childId
      }

      $queue.Enqueue($childId)
    }
  }

  return $null
}

function Get-DocsServerState {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $statePath = Get-DocsServerStatePath -ResolvedRepoRoot $ResolvedRepoRoot
  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteDocsServerState" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Get-UEToolSuiteDocsServerState -StatePath $statePath)
  }

  if (-not (Test-Path -LiteralPath $statePath)) { return $null }
  return (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json)
}

function Remove-DocsServerState {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $statePath = Get-DocsServerStatePath -ResolvedRepoRoot $ResolvedRepoRoot
  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Remove-UEToolSuiteDocsServerState" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    Remove-UEToolSuiteDocsServerState -StatePath $statePath
    return
  }

  if (Test-Path -LiteralPath $statePath) {
    Remove-Item -LiteralPath $statePath -Force
  }
}

function Save-DocsServerState {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [Parameter(Mandatory)][object]$State
  )

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Save-UEToolSuiteDocsServerState" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Save-UEToolSuiteDocsServerState -StatePath (Get-DocsServerStatePath -ResolvedRepoRoot $ResolvedRepoRoot) -State $State)
  }

  $runtimeDir = Get-DocsToolsRuntimeDirectory -ResolvedRepoRoot $ResolvedRepoRoot
  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null

  $statePath = Get-DocsServerStatePath -ResolvedRepoRoot $ResolvedRepoRoot
  $json = $State | ConvertTo-Json -Depth 6
  Write-Utf8NoBomFile -Path $statePath -Content $json
  return $statePath
}

function Get-WebsitePackageScriptNames {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  if ($null -ne $script:WebsitePackageScriptNames) {
    return $script:WebsitePackageScriptNames
  }

  $packagePath = Join-Path (Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot) "package.json"
  if (-not (Test-Path -LiteralPath $packagePath)) {
    $script:WebsitePackageScriptNames = @()
    return $script:WebsitePackageScriptNames
  }

  $packageJson = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
  if (-not $packageJson.scripts) {
    $script:WebsitePackageScriptNames = @()
    return $script:WebsitePackageScriptNames
  }

  $script:WebsitePackageScriptNames = @($packageJson.scripts.PSObject.Properties.Name)
  return $script:WebsitePackageScriptNames
}

function Get-DocsToolsRootHelp {
  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteDocsRootHelpText" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Get-UEToolSuiteDocsRootHelpText)
  }

@"
UE project docs automation.

Usage:
  docs-tools <command> [options]

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
  docs-tools help new-section
  docs-tools create-section DocsSite -LinkType generated-index -GeneratedIndexSlug /docs-site
  docs-tools create-page Setup -Title "Setup"
  docs-tools create-page Workflow Daily-Flow -Title "Daily Flow" -SidebarLabel "Daily Flow"
  docs-tools reorder Art-Source 4
  docs-tools start --port 3001
  docs-tools start --background --port 3001
  docs-tools docusaurus docs:version 1.0.0 --skip-feedback

Notes:
  - Docs are authored in Docs/ and rendered by website/.
  - TOC generation is optional and only runs when the bridge + Markdown All in One are installed.
  - Use `docs-tools help <command>` for detailed option help.
"@
}

function Get-DocsToolsCommandHelp {
  param([Parameter(Mandatory)][string]$CommandName)

  [void](Import-UEToolSuiteCoreModule)
  $topicResolver = Get-Command -Name "Resolve-UEToolSuiteDocsHelpTopicAlias" -ErrorAction SilentlyContinue
  if ($topicResolver) {
    $normalized = Resolve-UEToolSuiteDocsHelpTopicAlias -CommandName $CommandName
  }
  else {
    $normalized = $CommandName.Trim().ToLowerInvariant()
    switch ($normalized) {
      "new-page" { break }
      "create-page" { $normalized = "new-page"; break }
      "new-section" { break }
      "create-section" { $normalized = "new-section"; break }
      default { }
    }
  }

  switch ($normalized) {
    "new-page" {
@"
docs-tools new-page
Alias: docs-tools create-page

Usage:
  docs-tools new-page <PageName> [options]
  docs-tools new-page <SectionPath> <PageName> [options]

Required:
  <PageName>                    File stem source, for example Setup or Fear-Loop
  <SectionPath>                 Optional existing Docs/ section path, for example Workflow

Scaffold:
  -Title <text>                 Front matter title
  -Slug <path>                  Doc slug, for example /workflow/daily-flow
  -Position <number>            sidebar_position
  -Force                        Overwrite an existing file
  -NoToc                        Skip optional VS Code TOC generation

Common doc front matter:
  -Description <text>           description
  -Image <path>                 image
  -Keywords <a,b,c>             keywords string list
  -Tags <a,b,c>                 tags string list
  -TagsJson <json>              tags as full JSON
  -SidebarLabel <text>          sidebar_label
  -SidebarClassName <text>      sidebar_class_name
  -SidebarKey <text>            sidebar_key
  -SidebarCustomPropsJson <json> sidebar_custom_props
  -DisplayedSidebar <id>        displayed_sidebar
  -PaginationLabel <text>       pagination_label
  -PaginationNext <id|null>     pagination_next
  -PaginationPrev <id|null>     pagination_previous
  -HideTitle <true|false>       hide_title
  -HideTableOfContents <true|false> hide_table_of_contents
  -TocMinHeadingLevel <int>     toc_min_heading_level
  -TocMaxHeadingLevel <int>     toc_max_heading_level
  -CustomEditUrl <url|null>     custom_edit_url
  -Draft <true|false>           draft
  -Unlisted <true|false>        unlisted
  -ParseNumberPrefixes <true|false> parse_number_prefixes
  -LastUpdateDate <YYYY-MM-DD>  last_update.date
  -LastUpdateAuthor <text>      last_update.author

Generic front matter passthrough:
  -Field <key=value>            Set any front matter key as a string
  -FieldJson <key=json>         Set any front matter key with JSON values
                                Arrays/objects/bools/numbers should use -FieldJson

Examples:
  docs-tools create-page Setup -Title "Setup"
  docs-tools create-page Workflow Daily-Flow -Title "Daily Flow" -Position 2
  docs-tools create-page DocsSite Cli-Guide -Slug /docs-site/cli-guide -Keywords docs,cli,docusaurus
  docs-tools create-page Workflow Release-Checklist -FieldJson last_update={\"date\":\"2026-04-08\",\"author\":\"Team\"}
"@
      return
    }
    "new-section" {
@"
docs-tools new-section
Alias: docs-tools create-section

Usage:
  docs-tools new-section <SectionPath> [options]

Required:
  <SectionPath>                   New Docs/ section path, for example DocsSite

Section README front matter:
  -Title <text>                   README title
  -Slug <path>                    README slug, for example /docs-site
  -DocSidebarPosition <number>    README sidebar_position, default: 1
  -Description <text>             README description
  -Image <path>                   README image
  -Keywords <a,b,c>               README keywords
  -Tags <a,b,c>                   README tags
  -TagsJson <json>                README tags as full JSON
  -SidebarLabel <text>            README sidebar_label
  -SidebarClassName <text>        README sidebar_class_name
  -SidebarKey <text>              README sidebar_key
  -SidebarCustomPropsJson <json>  README sidebar_custom_props
  -DisplayedSidebar <id>          README displayed_sidebar
  -PaginationLabel <text>         README pagination_label
  -PaginationNext <id|null>       README pagination_next
  -PaginationPrev <id|null>       README pagination_previous
  -HideTitle <true|false>         README hide_title
  -HideTableOfContents <true|false> README hide_table_of_contents
  -TocMinHeadingLevel <int>       README toc_min_heading_level
  -TocMaxHeadingLevel <int>       README toc_max_heading_level
  -CustomEditUrl <url|null>       README custom_edit_url
  -Draft <true|false>             README draft
  -Unlisted <true|false>          README unlisted
  -ParseNumberPrefixes <true|false> README parse_number_prefixes
  -LastUpdateDate <YYYY-MM-DD>    README last_update.date
  -LastUpdateAuthor <text>        README last_update.author
  -DocField <key=value>           Any additional README front matter key
  -DocFieldJson <key=json>        Any additional README front matter JSON value

Category metadata (_category_.json):
  -Label <text>                   label, default: title
  -Position <number>              position
  -Collapsible <true|false>       collapsible
  -Collapsed <true|false>         collapsed
  -ClassName <text>               className
  -Key <text>                     key
  -CustomPropsJson <json>         customProps

Category link types:
  -LinkType <doc|generated-index|none>
                                  doc: link to an existing doc ID
                                  generated-index: auto-generate an index page
                                  none: write `"link": null`
  -LinkId <docId>                 link.id when LinkType=doc
  -GeneratedIndexTitle <text>     link.title when LinkType=generated-index
  -GeneratedIndexSlug <path>      link.slug when LinkType=generated-index
  -GeneratedIndexDescription <text> link.description
  -GeneratedIndexImage <path>     link.image
  -GeneratedIndexKeywords <a,b,c> link.keywords
  -CategoryField <key=value>      Any additional _category_.json key
  -CategoryJson <key=json>        Any additional _category_.json JSON value
                                  Use link={...} for full manual link control when needed

Scaffold:
  -Force                          Overwrite an existing directory
  -NoToc                          Skip optional VS Code TOC generation

Examples:
  docs-tools create-section DocsSite -Title "Docs Site" -Position 8
  docs-tools create-section DocsSite -LinkType generated-index -GeneratedIndexTitle "Docs Site" -GeneratedIndexSlug /docs-site
  docs-tools create-section Guides/API -LinkType none -CategoryJson customProps={\"badge\":\"internal\"}
"@
      return
    }
    "start" {
@"
docs-tools start

Usage:
  docs-tools start [--background] [docusaurus start args]

Default behavior runs `npm run start -- <args...>` in website/ attached to the current terminal so stdout/stderr stream live.

Options:
  --background                  Run detached and track the server for `status` and `stop`

Examples:
  docs-tools start
  docs-tools start --port 3001
  docs-tools start --background --port 3001
"@
      return
    }
    "reorder" {
@"
docs-tools reorder

Usage:
  docs-tools reorder <TargetPath> <Position>

Required:
  <TargetPath>                  Docs-relative page or section path
                                Pages: Setup, Workflow/Daily-Flow
                                Sections: Workflow, DocsSite
                                `Docs\` prefixes and `.md` suffixes are accepted
  <Position>                    Target sidebar position number

Behavior:
  - Moves the target item to the requested position within its parent
  - Shifts sibling pages/sections in the same parent container to keep ordering stable
  - Updates `sidebar_position` for pages and `_category_.json` `position` for sections

Examples:
  docs-tools reorder Art-Source 4
  docs-tools reorder Workflow 3
  docs-tools reorder Workflow/Daily-Flow 2
"@
      return
    }
    "docusaurus" {
@"
docs-tools docusaurus

Usage:
  docs-tools docusaurus <args...>

Passes all args and flags through to `npm run docusaurus -- <args...>`.
Example:
  docs-tools docusaurus docs:version 1.0.0 --skip-feedback
"@
      return
    }
    "check" {
@"
docs-tools check

Validates docs metadata, catches common docs-site mistakes, and runs the Docusaurus production build.
"@
      return
    }
    "status" {
@"
docs-tools status

Shows whether the tracked background docs dev server is running and prints the URL/log paths when state exists.
"@
      return
    }
    "stop" {
@"
docs-tools stop

Stops the tracked background docs dev server process tree and removes its saved state.
"@
      return
    }
    "doctor" {
@"
docs-tools doctor

Checks common local docs prerequisites:
  - node / npm availability
  - website/node_modules presence
  - VS Code CLI availability
  - Markdown All in One installation
  - docs bridge installation
  - tracked docs dev server state
"@
      return
    }
    "install-bridge" {
@"
docs-tools install-bridge

Installs the optional UE project VS Code bridge used for TOC generation. Markdown All in One still needs to be installed separately.
"@
      return
    }
    default {
      throw "Unknown docs-tools help topic '$CommandName'."
    }
  }
}

function ConvertTo-KebabCase {
  param([Parameter(Mandatory)][string]$Text)

  $value = $Text.Trim()
  $value = $value -creplace '([a-z0-9])([A-Z])', '$1-$2'
  $value = $value -replace '[^A-Za-z0-9]+', '-'
  $value = $value.Trim('-')

  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "Could not convert '$Text' into a slug segment."
  }

  return $value.ToLowerInvariant()
}

function ConvertTo-TitleWords {
  param([Parameter(Mandatory)][string]$Text)

  $expanded = $Text.Trim()
  $expanded = $expanded -creplace '([a-z0-9])([A-Z])', '$1 $2'
  $expanded = $expanded -replace '[_\-]+', ' '
  $expanded = $expanded -replace '\s+', ' '
  $expanded = $expanded.Trim()

  if ([string]::IsNullOrWhiteSpace($expanded)) {
    throw "Could not convert '$Text' into a title."
  }

  $textInfo = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
  return $textInfo.ToTitleCase($expanded.ToLowerInvariant())
}

function ConvertTo-FileStem {
  param([Parameter(Mandatory)][string]$Text)

  $expanded = $Text.Trim()
  $expanded = $expanded -replace '\.md$', ''
  $expanded = $expanded -creplace '([a-z0-9])([A-Z])', '$1 $2'
  $expanded = $expanded -replace '[^A-Za-z0-9]+', ' '
  $expanded = $expanded -replace '\s+', ' '
  $expanded = $expanded.Trim()

  if ([string]::IsNullOrWhiteSpace($expanded)) {
    throw "Could not convert '$Text' into a file name."
  }

  $parts = @($expanded.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries))
  return ($parts | ForEach-Object {
      if ($_.Length -eq 1) { $_.ToUpperInvariant() }
      else { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }
    }) -join '-'
}

function Get-RelativeDocPath {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [Parameter(Mandatory)][string]$FullPath
  )

  $relative = [System.IO.Path]::GetRelativePath($DocsRoot, $FullPath)
  return ($relative -replace '\\', '/')
}

function Get-DocIdForPath {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [Parameter(Mandatory)][string]$FullPath
  )

  $relative = Get-RelativeDocPath -DocsRoot $DocsRoot -FullPath $FullPath
  return ($relative -replace '\.md$', '')
}

function Get-SlugForSectionPath {
  param([Parameter(Mandatory)][string]$SectionPath)

  $segments = @($SectionPath -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($segments.Count -eq 0) {
    throw "Section path must not be empty."
  }

  $slugSegments = @($segments | ForEach-Object { ConvertTo-KebabCase $_ })
  return "/" + ($slugSegments -join '/')
}

function Get-SlugForPage {
  param(
    [AllowEmptyString()][string]$SectionPath,
    [Parameter(Mandatory)][string]$PageName
  )

  $pageSlug = ConvertTo-KebabCase $PageName
  if ([string]::IsNullOrWhiteSpace($SectionPath)) {
    return "/$pageSlug"
  }

  $sectionSlug = Get-SlugForSectionPath -SectionPath $SectionPath
  return "$sectionSlug/$pageSlug"
}

function Parse-SubcommandArguments {
  param(
    [AllowNull()][string[]]$CommandArguments = @(),
    [string[]]$SwitchNames = @(),
    [string[]]$ValueNames = @(),
    [string[]]$MultiValueNames = @()
  )

  $argumentList = @($CommandArguments)
  $positionals = New-Object System.Collections.Generic.List[string]
  $values = @{}
  $multiValues = @{}
  $switches = @{}
  $switchSet = @($SwitchNames | ForEach-Object { $_.ToLowerInvariant() })
  $valueSet = @($ValueNames | ForEach-Object { $_.ToLowerInvariant() })
  $multiValueSet = @($MultiValueNames | ForEach-Object { $_.ToLowerInvariant() })

  for ($i = 0; $i -lt $argumentList.Count; $i++) {
    $token = [string]$argumentList[$i]
    if ($token.StartsWith('-')) {
      $name = $token.TrimStart('-').ToLowerInvariant()

      if ($switchSet -contains $name) {
        $switches[$name] = $true
        continue
      }

      if ($valueSet -contains $name) {
        if (($i + 1) -ge $argumentList.Count) {
          throw "Missing value for option '$token'."
        }

        $values[$name] = [string]$argumentList[$i + 1]
        $i++
        continue
      }

      if ($multiValueSet -contains $name) {
        if (($i + 1) -ge $argumentList.Count) {
          throw "Missing value for option '$token'."
        }

        if (-not $multiValues.ContainsKey($name)) {
          $multiValues[$name] = New-Object System.Collections.Generic.List[string]
        }

        $multiValues[$name].Add([string]$argumentList[$i + 1]) | Out-Null
        $i++
        continue
      }

      throw "Unknown option '$token'."
    }

    $positionals.Add($token) | Out-Null
  }

  return [pscustomobject]@{
    Positionals = $positionals.ToArray()
    Values = $values
    MultiValues = $multiValues
    Switches = $switches
  }
}

function Parse-KeyValueAssignment {
  param([Parameter(Mandatory)][string]$Assignment)

  $separatorIndex = $Assignment.IndexOf('=')
  if ($separatorIndex -lt 1) {
    throw "Expected key=value assignment but got '$Assignment'."
  }

  $key = $Assignment.Substring(0, $separatorIndex).Trim()
  $value = $Assignment.Substring($separatorIndex + 1)
  if ([string]::IsNullOrWhiteSpace($key)) {
    throw "Assignment key must not be empty: '$Assignment'."
  }

  return [pscustomobject]@{
    Key = $key
    Value = $value
  }
}

function ConvertTo-BooleanValue {
  param(
    [Parameter(Mandatory)][string]$Value,
    [Parameter(Mandatory)][string]$OptionName
  )

  $normalized = $Value.Trim().ToLowerInvariant()
  switch ($normalized) {
    "true" { return $true }
    "false" { return $false }
    default { throw "Option '$OptionName' expects true or false." }
  }
}

function ConvertTo-NullableStringValue {
  param([Parameter(Mandatory)][string]$Value)

  if ($Value.Trim().ToLowerInvariant() -eq "null") {
    return $null
  }

  return $Value
}

function ConvertTo-CompactNumericValue {
  param([Parameter(Mandatory)][double]$Value)

  if ([Math]::Abs($Value % 1) -lt 0.0000001) {
    return [int64][Math]::Round($Value)
  }

  return $Value
}

function ConvertTo-NumericValue {
  param(
    [Parameter(Mandatory)][string]$Value,
    [Parameter(Mandatory)][string]$OptionName
  )

  $parsed = 0.0
  if (-not [double]::TryParse($Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
    throw "Option '$OptionName' expects a number."
  }

  return (ConvertTo-CompactNumericValue -Value $parsed)
}

function ConvertTo-IntegerValue {
  param(
    [Parameter(Mandatory)][string]$Value,
    [Parameter(Mandatory)][string]$OptionName
  )

  $parsed = 0
  if (-not [int]::TryParse($Value, [ref]$parsed)) {
    throw "Option '$OptionName' expects an integer."
  }

  return $parsed
}

function ConvertTo-StringList {
  param([AllowNull()][string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return @()
  }

  return @(
    $Value.Split(',') |
      ForEach-Object { $_.Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )
}

function ConvertFrom-JsonArgument {
  param(
    [Parameter(Mandatory)][string]$Value,
    [Parameter(Mandatory)][string]$OptionName
  )

  try {
    return (ConvertFrom-Json -InputObject $Value -Depth 20)
  }
  catch {
    throw "Option '$OptionName' expects valid JSON."
  }
}

function Set-OrderedMapValue {
  param(
    [Parameter(Mandatory)][System.Collections.IDictionary]$Map,
    [Parameter(Mandatory)][string]$Key,
    $Value
  )

  if ($Map.Contains($Key)) {
    $Map[$Key] = $Value
  }
  else {
    $Map.Add($Key, $Value)
  }
}

function Apply-KeyValueAssignmentsToMap {
  param(
    [Parameter(Mandatory)][System.Collections.IDictionary]$Map,
    [string[]]$Assignments = @(),
    [string[]]$JsonAssignments = @()
  )

  foreach ($assignment in @(Get-NormalizedArgumentList -Values $Assignments)) {
    $entry = Parse-KeyValueAssignment -Assignment $assignment
    Set-OrderedMapValue -Map $Map -Key $entry.Key -Value $entry.Value
  }

  foreach ($assignment in @(Get-NormalizedArgumentList -Values $JsonAssignments)) {
    $entry = Parse-KeyValueAssignment -Assignment $assignment
    $jsonValue = ConvertFrom-JsonArgument -Value $entry.Value -OptionName $entry.Key
    Set-OrderedMapValue -Map $Map -Key $entry.Key -Value $jsonValue
  }
}

function Test-IsYamlScalar {
  param($Value)

  return (
    $null -eq $Value -or
    $Value -is [string] -or
    $Value -is [bool] -or
    $Value -is [byte] -or
    $Value -is [int16] -or
    $Value -is [int32] -or
    $Value -is [int64] -or
    $Value -is [single] -or
    $Value -is [double] -or
    $Value -is [decimal]
  )
}

function Format-YamlNumber {
  param([Parameter(Mandatory)]$Value)

  if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
    if ([Math]::Abs([double]$Value % 1) -lt 0.0000001) {
      return ([int64][Math]::Round([double]$Value)).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
  }

  return ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0}", $Value))
}

function Format-YamlScalar {
  param($Value)

  if ($null -eq $Value) {
    return "null"
  }

  if ($Value -is [bool]) {
    return $Value.ToString().ToLowerInvariant()
  }

  if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
    return (Format-YamlNumber -Value $Value)
  }

  $text = [string]$Value
  if ($text.Length -eq 0) {
    return "''"
  }

  $safePattern = '^[A-Za-z0-9_./:+@%-]+$'
  $reservedPattern = '^(true|false|null|yes|no|on|off|[-+]?\d+(\.\d+)?)$'
  if ($text -match $safePattern -and $text -notmatch $reservedPattern) {
    return $text
  }

  return "'" + ($text -replace "'", "''") + "'"
}

function Get-ObjectEntries {
  param($Value)

  if ($Value -is [System.Collections.IDictionary]) {
    return @($Value.GetEnumerator())
  }

  return @($Value.PSObject.Properties | ForEach-Object {
      [pscustomobject]@{
        Key = $_.Name
        Value = $_.Value
      }
    })
}

function ConvertTo-YamlLines {
  param(
    $Value,
    [int]$Indent = 0
  )

  $indentText = (' ' * $Indent)

  if (Test-IsYamlScalar -Value $Value) {
    return @("$indentText$(Format-YamlScalar -Value $Value)")
  }

  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string]) -and -not ($Value -is [System.Collections.IDictionary]) -and -not ($Value.PSObject.Properties.Count -gt 0 -and -not ($Value -is [array]))) {
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Value)) {
      if (Test-IsYamlScalar -Value $item) {
        $lines.Add("$indentText- $(Format-YamlScalar -Value $item)") | Out-Null
      }
      else {
        $lines.Add("$indentText-") | Out-Null
        foreach ($nested in @(ConvertTo-YamlLines -Value $item -Indent ($Indent + 2))) {
          $lines.Add($nested) | Out-Null
        }
      }
    }
    return @($lines)
  }

  $objectLines = New-Object System.Collections.Generic.List[string]
  foreach ($entry in @(Get-ObjectEntries -Value $Value)) {
    $key = [string]$entry.Key
    $entryValue = $entry.Value
    if (Test-IsYamlScalar -Value $entryValue) {
      $objectLines.Add("${indentText}${key}: $(Format-YamlScalar -Value $entryValue)") | Out-Null
    }
    else {
      $objectLines.Add("${indentText}${key}:") | Out-Null
      foreach ($nested in @(ConvertTo-YamlLines -Value $entryValue -Indent ($Indent + 2))) {
        $objectLines.Add($nested) | Out-Null
      }
    }
  }

  return @($objectLines)
}

function ConvertTo-FrontMatterBlock {
  param([Parameter(Mandatory)][System.Collections.IDictionary]$FrontMatter)

  $lines = @("---") + @(ConvertTo-YamlLines -Value $FrontMatter) + @("---")
  return ($lines -join "`r`n")
}

function Get-CodeCliPath {
  if ($script:CodeCliPath) {
    return $script:CodeCliPath
  }

  $command = Get-Command code.cmd -ErrorAction SilentlyContinue
  if ($command) {
    $script:CodeCliPath = $command.Source
    return $script:CodeCliPath
  }

  $defaultPath = Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\bin\code.cmd"
  if (Test-Path -LiteralPath $defaultPath) {
    $script:CodeCliPath = $defaultPath
    return $script:CodeCliPath
  }

  return $null
}

function Get-InstalledVSCodeExtensions {
  $codeCliPath = Get-CodeCliPath
  if (-not $codeCliPath) {
    return @()
  }

  if ($null -ne $script:CodeExtensionList) {
    return $script:CodeExtensionList
  }

  $lines = @(& $codeCliPath --list-extensions 2>$null)
  $script:CodeExtensionList = @($lines | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
  return $script:CodeExtensionList
}

function Test-VSCodeExtensionInstalled {
  param([Parameter(Mandatory)][string]$ExtensionId)
  return (Get-InstalledVSCodeExtensions) -contains $ExtensionId
}

function Get-BridgeStatus {
  [void](Import-UEToolSuiteCoreModule)
  $codeCliPath = Get-CodeCliPath
  $markdownInstalled = $false
  $bridgeInstalled = $false

  if ($codeCliPath) {
    $markdownInstalled = Test-VSCodeExtensionInstalled -ExtensionId $script:MarkdownAllInOneExtensionId
    $bridgeInstalled = Test-VSCodeExtensionInstalled -ExtensionId $script:DocsToolsBridgeExtensionId
  }

  $moduleFn = Get-Command -Name "New-UEToolSuiteDocsBridgeStatus" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (New-UEToolSuiteDocsBridgeStatus -CodeCliPath $codeCliPath -MarkdownAllInOneInstalled:$markdownInstalled -BridgeInstalled:$bridgeInstalled)
  }

  return [pscustomobject]@{ CodeCliPath = $codeCliPath; MarkdownAllInOneInstalled = $markdownInstalled; BridgeInstalled = $bridgeInstalled; TocReady = ($codeCliPath -and $markdownInstalled -and $bridgeInstalled) }
}

function Get-WorkspaceRequestKey {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteDocsWorkspaceRequestKey" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Get-UEToolSuiteDocsWorkspaceRequestKey -ResolvedRepoRoot $ResolvedRepoRoot)
  }

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

function Get-BridgeRequestDirectory {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteDocsBridgeRequestDirectory" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Get-UEToolSuiteDocsBridgeRequestDirectory -ResolvedRepoRoot $ResolvedRepoRoot)
  }

  $workspaceKey = Get-WorkspaceRequestKey -ResolvedRepoRoot $ResolvedRepoRoot
  return (Join-Path ([System.IO.Path]::GetTempPath()) "ueproject-docs-tools\$workspaceKey")
}

function Queue-TocRequest {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [Parameter(Mandatory)][string]$FilePath
  )

  $requestDir = Get-BridgeRequestDirectory -ResolvedRepoRoot $ResolvedRepoRoot
  New-Item -ItemType Directory -Force -Path $requestDir | Out-Null

  $requestObject = [ordered]@{
    version = 1
    action = "createToc"
    workspaceRoot = [System.IO.Path]::GetFullPath($ResolvedRepoRoot)
    filePath = [System.IO.Path]::GetFullPath($FilePath)
    marker = $script:TocMarker
    createdAt = (Get-Date).ToString("o")
  }

  $requestId = "{0}-{1}" -f (Get-Date).ToString("yyyyMMddHHmmss"), ([Guid]::NewGuid().ToString("N"))
  $json = $requestObject | ConvertTo-Json -Depth 5
  $tempPath = Join-Path $requestDir "$requestId.tmp"
  $finalPath = Join-Path $requestDir "$requestId.json"

  Write-Utf8NoBomFile -Path $tempPath -Content $json
  Move-Item -LiteralPath $tempPath -Destination $finalPath -Force

  return $finalPath
}

function Open-PathInVSCode {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [Parameter(Mandatory)][string]$FilePath
  )

  $codeCliPath = Get-CodeCliPath
  if (-not $codeCliPath) {
    return $false
  }

  & $codeCliPath --reuse-window -g "${FilePath}:1" | Out-Null
  return $true
}

function Build-ScaffoldDocContent {
  param(
    [Parameter(Mandatory)][System.Collections.IDictionary]$FrontMatter,
    [Parameter(Mandatory)][string]$HeadingTitle,
    [Parameter(Mandatory)][bool]$IncludeToc,
    [Parameter(Mandatory)][string]$OverviewNoun
  )

  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($line in @((ConvertTo-FrontMatterBlock -FrontMatter $FrontMatter) -split "`r?`n")) {
    $lines.Add($line) | Out-Null
  }

  $lines.Add("") | Out-Null
  $lines.Add("# $HeadingTitle <!-- omit from toc -->") | Out-Null
  $lines.Add("") | Out-Null

  if ($IncludeToc) {
    $lines.Add("## Table of Contents <!-- omit from toc -->") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add($script:TocMarker) | Out-Null
    $lines.Add("") | Out-Null
  }

  $lines.Add("## Overview") | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("Describe this $OverviewNoun.") | Out-Null
  $lines.Add("") | Out-Null

  return ($lines -join "`r`n")
}

function Build-CategoryMetadataContent {
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Metadata)
  return (($Metadata | ConvertTo-Json -Depth 10) + "`r`n")
}

function Assert-PathInsideRoot {
  param(
    [Parameter(Mandatory)][string]$RootPath,
    [Parameter(Mandatory)][string]$TargetPath
  )

  $rootFull = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\') + '\'
  $targetFull = [System.IO.Path]::GetFullPath($TargetPath)
  if (-not $targetFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Path '$TargetPath' resolves outside the intended root '$RootPath'."
  }
}

function Test-DocsSectionExists {
  param([Parameter(Mandatory)][string]$SectionDir)

  if (-not (Test-Path -LiteralPath $SectionDir -PathType Container)) {
    return $false
  }

  $categoryPath = Join-Path $SectionDir "_category_.json"
  return (Test-Path -LiteralPath $categoryPath -PathType Leaf)
}

function Get-CommonDocValueOptionNames {
  return @(
    "title",
    "slug",
    "position",
    "description",
    "image",
    "sidebarlabel",
    "sidebarclassname",
    "sidebarkey",
    "sidebarcustompropsjson",
    "displayedsidebar",
    "paginationlabel",
    "paginationnext",
    "paginationprev",
    "hidetitle",
    "hidetableofcontents",
    "tocminheadinglevel",
    "tocmaxheadinglevel",
    "customediturl",
    "draft",
    "unlisted",
    "parsenumberprefixes",
    "lastupdatedate",
    "lastupdateauthor",
    "tags",
    "tagsjson",
    "keywords"
  )
}

function New-DocFrontMatter {
  param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$Slug,
    [AllowNull()]$SidebarPosition
  )

  $frontMatter = [ordered]@{
    title = $Title
    slug = $Slug
  }

  if ($null -ne $SidebarPosition) {
    Set-OrderedMapValue -Map $frontMatter -Key "sidebar_position" -Value $SidebarPosition
  }

  return $frontMatter
}

function Apply-CommonDocOptionValues {
  param(
    [Parameter(Mandatory)][System.Collections.IDictionary]$FrontMatter,
    [Parameter(Mandatory)][hashtable]$Values
  )

  if ($Values.ContainsKey("description")) { Set-OrderedMapValue -Map $FrontMatter -Key "description" -Value $Values["description"] }
  if ($Values.ContainsKey("image")) { Set-OrderedMapValue -Map $FrontMatter -Key "image" -Value $Values["image"] }
  if ($Values.ContainsKey("keywords")) { Set-OrderedMapValue -Map $FrontMatter -Key "keywords" -Value @(ConvertTo-StringList -Value $Values["keywords"]) }
  if ($Values.ContainsKey("tags")) { Set-OrderedMapValue -Map $FrontMatter -Key "tags" -Value @(ConvertTo-StringList -Value $Values["tags"]) }
  if ($Values.ContainsKey("tagsjson")) { Set-OrderedMapValue -Map $FrontMatter -Key "tags" -Value (ConvertFrom-JsonArgument -Value $Values["tagsjson"] -OptionName "tagsjson") }
  if ($Values.ContainsKey("sidebarlabel")) { Set-OrderedMapValue -Map $FrontMatter -Key "sidebar_label" -Value $Values["sidebarlabel"] }
  if ($Values.ContainsKey("sidebarclassname")) { Set-OrderedMapValue -Map $FrontMatter -Key "sidebar_class_name" -Value $Values["sidebarclassname"] }
  if ($Values.ContainsKey("sidebarkey")) { Set-OrderedMapValue -Map $FrontMatter -Key "sidebar_key" -Value $Values["sidebarkey"] }
  if ($Values.ContainsKey("sidebarcustompropsjson")) { Set-OrderedMapValue -Map $FrontMatter -Key "sidebar_custom_props" -Value (ConvertFrom-JsonArgument -Value $Values["sidebarcustompropsjson"] -OptionName "sidebarcustompropsjson") }
  if ($Values.ContainsKey("displayedsidebar")) { Set-OrderedMapValue -Map $FrontMatter -Key "displayed_sidebar" -Value $Values["displayedsidebar"] }
  if ($Values.ContainsKey("paginationlabel")) { Set-OrderedMapValue -Map $FrontMatter -Key "pagination_label" -Value $Values["paginationlabel"] }
  if ($Values.ContainsKey("paginationnext")) { Set-OrderedMapValue -Map $FrontMatter -Key "pagination_next" -Value (ConvertTo-NullableStringValue -Value $Values["paginationnext"]) }
  if ($Values.ContainsKey("paginationprev")) { Set-OrderedMapValue -Map $FrontMatter -Key "pagination_prev" -Value (ConvertTo-NullableStringValue -Value $Values["paginationprev"]) }
  if ($Values.ContainsKey("hidetitle")) { Set-OrderedMapValue -Map $FrontMatter -Key "hide_title" -Value (ConvertTo-BooleanValue -Value $Values["hidetitle"] -OptionName "HideTitle") }
  if ($Values.ContainsKey("hidetableofcontents")) { Set-OrderedMapValue -Map $FrontMatter -Key "hide_table_of_contents" -Value (ConvertTo-BooleanValue -Value $Values["hidetableofcontents"] -OptionName "HideTableOfContents") }
  if ($Values.ContainsKey("tocminheadinglevel")) { Set-OrderedMapValue -Map $FrontMatter -Key "toc_min_heading_level" -Value (ConvertTo-IntegerValue -Value $Values["tocminheadinglevel"] -OptionName "TocMinHeadingLevel") }
  if ($Values.ContainsKey("tocmaxheadinglevel")) { Set-OrderedMapValue -Map $FrontMatter -Key "toc_max_heading_level" -Value (ConvertTo-IntegerValue -Value $Values["tocmaxheadinglevel"] -OptionName "TocMaxHeadingLevel") }
  if ($Values.ContainsKey("customediturl")) { Set-OrderedMapValue -Map $FrontMatter -Key "custom_edit_url" -Value (ConvertTo-NullableStringValue -Value $Values["customediturl"]) }
  if ($Values.ContainsKey("draft")) { Set-OrderedMapValue -Map $FrontMatter -Key "draft" -Value (ConvertTo-BooleanValue -Value $Values["draft"] -OptionName "Draft") }
  if ($Values.ContainsKey("unlisted")) { Set-OrderedMapValue -Map $FrontMatter -Key "unlisted" -Value (ConvertTo-BooleanValue -Value $Values["unlisted"] -OptionName "Unlisted") }
  if ($Values.ContainsKey("parsenumberprefixes")) { Set-OrderedMapValue -Map $FrontMatter -Key "parse_number_prefixes" -Value (ConvertTo-BooleanValue -Value $Values["parsenumberprefixes"] -OptionName "ParseNumberPrefixes") }

  $lastUpdate = [ordered]@{}
  if ($Values.ContainsKey("lastupdatedate")) { Set-OrderedMapValue -Map $lastUpdate -Key "date" -Value $Values["lastupdatedate"] }
  if ($Values.ContainsKey("lastupdateauthor")) { Set-OrderedMapValue -Map $lastUpdate -Key "author" -Value $Values["lastupdateauthor"] }
  if ($lastUpdate.Count -gt 0) {
    Set-OrderedMapValue -Map $FrontMatter -Key "last_update" -Value $lastUpdate
  }
}

function New-CategoryMetadata {
  param(
    [Parameter(Mandatory)][string]$Label,
    [AllowNull()]$Position,
    [AllowNull()][string]$LinkType,
    [string]$LinkDocId,
    [string]$GeneratedIndexTitle,
    [string]$GeneratedIndexSlug,
    [string]$GeneratedIndexDescription,
    [string]$GeneratedIndexImage,
    [string]$GeneratedIndexKeywords,
    [string]$ClassName,
    [string]$Key,
    [AllowNull()]$Collapsible,
    [AllowNull()]$Collapsed,
    [AllowNull()]$CustomProps,
    [string[]]$Assignments = @(),
    [string[]]$JsonAssignments = @()
  )

  $metadata = [ordered]@{
    label = $Label
  }

  if ($null -ne $Position) { Set-OrderedMapValue -Map $metadata -Key "position" -Value $Position }
  if (-not [string]::IsNullOrWhiteSpace($ClassName)) { Set-OrderedMapValue -Map $metadata -Key "className" -Value $ClassName }
  if (-not [string]::IsNullOrWhiteSpace($Key)) { Set-OrderedMapValue -Map $metadata -Key "key" -Value $Key }
  if ($null -ne $Collapsible) { Set-OrderedMapValue -Map $metadata -Key "collapsible" -Value $Collapsible }
  if ($null -ne $Collapsed) { Set-OrderedMapValue -Map $metadata -Key "collapsed" -Value $Collapsed }
  if ($null -ne $CustomProps) { Set-OrderedMapValue -Map $metadata -Key "customProps" -Value $CustomProps }

  $normalizedLinkType = if ([string]::IsNullOrWhiteSpace($LinkType)) { "doc" } else { $LinkType.Trim().ToLowerInvariant() }
  switch ($normalizedLinkType) {
    "doc" {
      $link = [ordered]@{
        type = "doc"
        id = $LinkDocId
      }
      Set-OrderedMapValue -Map $metadata -Key "link" -Value $link
    }
    "generated-index" {
      $link = [ordered]@{
        type = "generated-index"
      }

      if (-not [string]::IsNullOrWhiteSpace($GeneratedIndexTitle)) { Set-OrderedMapValue -Map $link -Key "title" -Value $GeneratedIndexTitle }
      if (-not [string]::IsNullOrWhiteSpace($GeneratedIndexSlug)) { Set-OrderedMapValue -Map $link -Key "slug" -Value $GeneratedIndexSlug }
      if (-not [string]::IsNullOrWhiteSpace($GeneratedIndexDescription)) { Set-OrderedMapValue -Map $link -Key "description" -Value $GeneratedIndexDescription }
      if (-not [string]::IsNullOrWhiteSpace($GeneratedIndexImage)) { Set-OrderedMapValue -Map $link -Key "image" -Value $GeneratedIndexImage }
      if (-not [string]::IsNullOrWhiteSpace($GeneratedIndexKeywords)) { Set-OrderedMapValue -Map $link -Key "keywords" -Value @(ConvertTo-StringList -Value $GeneratedIndexKeywords) }

      Set-OrderedMapValue -Map $metadata -Key "link" -Value $link
    }
    "none" {
      Set-OrderedMapValue -Map $metadata -Key "link" -Value $null
    }
    default {
      throw "LinkType expects one of: doc, generated-index, none."
    }
  }

  Apply-KeyValueAssignmentsToMap -Map $metadata -Assignments $Assignments -JsonAssignments $JsonAssignments
  return $metadata
}

function Invoke-NewSection {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string[]]$CommandArguments = @()
  )

  $parsed = Parse-SubcommandArguments `
    -CommandArguments $CommandArguments `
    -SwitchNames @("force", "notoc") `
    -ValueNames @(
      "title", "label", "slug", "position", "docsidebarposition",
      "description", "image", "keywords", "tags", "tagsjson",
      "sidebarlabel", "sidebarclassname", "sidebarkey", "sidebarcustompropsjson",
      "displayedsidebar", "paginationlabel", "paginationnext", "paginationprev",
      "hidetitle", "hidetableofcontents", "tocminheadinglevel", "tocmaxheadinglevel",
      "customediturl", "draft", "unlisted", "parsenumberprefixes",
      "lastupdatedate", "lastupdateauthor",
      "collapsible", "collapsed", "classname", "key", "custompropsjson",
      "linktype", "linkid", "generatedindextitle", "generatedindexslug",
      "generatedindexdescription", "generatedindeximage", "generatedindexkeywords"
    ) `
    -MultiValueNames @("docfield", "docfieldjson", "categoryfield", "categoryjson")
  if ($parsed.Positionals.Count -eq 0) {
    throw "SectionPath is required. Usage: docs-tools new-section <SectionPath> [options]. Run 'docs-tools help new-section'."
  }

  if ($parsed.Positionals.Count -gt 1) {
    throw "Too many positional arguments for new-section. Usage: docs-tools new-section <SectionPath> [options]. Run 'docs-tools help new-section'."
  }

  $sectionPath = $parsed.Positionals[0]
  $title = if ($parsed.Values.ContainsKey("title")) { $parsed.Values["title"] } else { ConvertTo-TitleWords ($sectionPath -split '[\\/]' | Select-Object -Last 1) }
  $label = if ($parsed.Values.ContainsKey("label")) { $parsed.Values["label"] } else { $title }
  $force = $parsed.Switches.ContainsKey("force")
  $noToc = $parsed.Switches.ContainsKey("notoc")

  $docsRoot = Get-DocsRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $sectionSegments = @($sectionPath -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($sectionSegments.Count -eq 0) {
    throw "Section path must not be empty."
  }

  if ($sectionSegments.Count -gt 1) {
    $parentSegments = @($sectionSegments[0..($sectionSegments.Count - 2)])
    $parentDir = Join-Path $docsRoot ([System.IO.Path]::Combine($parentSegments))
    Assert-PathInsideRoot -RootPath $docsRoot -TargetPath $parentDir

    if (-not (Test-DocsSectionExists -SectionDir $parentDir)) {
      throw "Parent section does not exist: $parentDir"
    }
  }

  $sectionDir = Join-Path $docsRoot ([System.IO.Path]::Combine($sectionSegments))
  Assert-PathInsideRoot -RootPath $docsRoot -TargetPath $sectionDir
  $position = if ($parsed.Values.ContainsKey("position")) { ConvertTo-NumericValue -Value $parsed.Values["position"] -OptionName "Position" } else { Get-NextSectionPosition -DocsRoot $docsRoot -SectionPath $sectionPath }

  $readmePath = Join-Path $sectionDir "README.md"
  $categoryPath = Join-Path $sectionDir "_category_.json"
  $docSlug = if ($parsed.Values.ContainsKey("slug")) { $parsed.Values["slug"] } else { Get-SlugForSectionPath -SectionPath $sectionPath }
  $bridgeStatus = Get-BridgeStatus
  $includeToc = (-not $noToc) -and $bridgeStatus.TocReady

  if ((Test-Path -LiteralPath $sectionDir) -and (-not $force)) {
    throw "Section directory already exists: $sectionDir"
  }

  New-Item -ItemType Directory -Force -Path $sectionDir | Out-Null

  $docSidebarPosition = if ($parsed.Values.ContainsKey("docsidebarposition")) { ConvertTo-NumericValue -Value $parsed.Values["docsidebarposition"] -OptionName "DocSidebarPosition" } else { 1 }
  $readmeFrontMatter = New-DocFrontMatter -Title $title -Slug $docSlug -SidebarPosition $docSidebarPosition
  Apply-CommonDocOptionValues -FrontMatter $readmeFrontMatter -Values $parsed.Values
  Apply-KeyValueAssignmentsToMap `
    -Map $readmeFrontMatter `
    -Assignments @($parsed.MultiValues["docfield"]) `
    -JsonAssignments @($parsed.MultiValues["docfieldjson"])

  $readmeContent = Build-ScaffoldDocContent -FrontMatter $readmeFrontMatter -HeadingTitle $title -IncludeToc:$includeToc -OverviewNoun "section"
  $docId = Get-DocIdForPath -DocsRoot $docsRoot -FullPath $readmePath
  $linkType = if ($parsed.Values.ContainsKey("linktype")) { $parsed.Values["linktype"] } else { "doc" }
  $linkDocId = if ($parsed.Values.ContainsKey("linkid")) { $parsed.Values["linkid"] } else { $docId }
  $generatedIndexTitle = if ($parsed.Values.ContainsKey("generatedindextitle")) { $parsed.Values["generatedindextitle"] } else { $label }
  $generatedIndexSlug = if ($parsed.Values.ContainsKey("generatedindexslug")) { $parsed.Values["generatedindexslug"] } else { $docSlug }
  $categoryCustomProps = if ($parsed.Values.ContainsKey("custompropsjson")) { ConvertFrom-JsonArgument -Value $parsed.Values["custompropsjson"] -OptionName "CustomPropsJson" } else { $null }
  $categoryCollapsible = if ($parsed.Values.ContainsKey("collapsible")) { ConvertTo-BooleanValue -Value $parsed.Values["collapsible"] -OptionName "Collapsible" } else { $null }
  $categoryCollapsed = if ($parsed.Values.ContainsKey("collapsed")) { ConvertTo-BooleanValue -Value $parsed.Values["collapsed"] -OptionName "Collapsed" } else { $null }

  $categoryMetadata = New-CategoryMetadata `
    -Label $label `
    -Position $position `
    -LinkType $linkType `
    -LinkDocId $linkDocId `
    -GeneratedIndexTitle $generatedIndexTitle `
    -GeneratedIndexSlug $generatedIndexSlug `
    -GeneratedIndexDescription $parsed.Values["generatedindexdescription"] `
    -GeneratedIndexImage $parsed.Values["generatedindeximage"] `
    -GeneratedIndexKeywords $parsed.Values["generatedindexkeywords"] `
    -ClassName $parsed.Values["classname"] `
    -Key $parsed.Values["key"] `
    -Collapsible $categoryCollapsible `
    -Collapsed $categoryCollapsed `
    -CustomProps $categoryCustomProps `
    -Assignments @($parsed.MultiValues["categoryfield"]) `
    -JsonAssignments @($parsed.MultiValues["categoryjson"])
  $categoryContent = Build-CategoryMetadataContent -Metadata $categoryMetadata

  Write-Utf8NoBomFile -Path $readmePath -Content $readmeContent
  Write-Utf8NoBomFile -Path $categoryPath -Content $categoryContent

  if ($includeToc) {
    $null = Queue-TocRequest -ResolvedRepoRoot $ResolvedRepoRoot -FilePath $readmePath
    [void](Open-PathInVSCode -ResolvedRepoRoot $ResolvedRepoRoot -FilePath $readmePath)
  }

  [pscustomobject]@{
    Command = "new-section"
    Path = $readmePath
    CategoryPath = $categoryPath
    TocQueued = $includeToc
    BridgeStatus = $bridgeStatus
  }
}

function Invoke-NewPage {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string[]]$CommandArguments = @()
  )

  $parsed = Parse-SubcommandArguments `
    -CommandArguments $CommandArguments `
    -SwitchNames @("force", "notoc") `
    -ValueNames (Get-CommonDocValueOptionNames) `
    -MultiValueNames @("field", "fieldjson")
  if ($parsed.Positionals.Count -eq 0) {
    throw "PageName is required. Usage: docs-tools new-page <PageName> [options] or docs-tools new-page <SectionPath> <PageName> [options]. Run 'docs-tools help new-page'."
  }

  if ($parsed.Positionals.Count -gt 2) {
    throw "Too many positional arguments for new-page. Usage: docs-tools new-page <PageName> [options] or docs-tools new-page <SectionPath> <PageName> [options]. Run 'docs-tools help new-page'."
  }

  $sectionPath = $null
  if ($parsed.Positionals.Count -eq 1) {
    $pageName = $parsed.Positionals[0]
  }
  else {
    $sectionPath = $parsed.Positionals[0]
    $pageName = $parsed.Positionals[1]
  }
  $title = if ($parsed.Values.ContainsKey("title")) { $parsed.Values["title"] } else { ConvertTo-TitleWords $pageName }
  $force = $parsed.Switches.ContainsKey("force")
  $noToc = $parsed.Switches.ContainsKey("notoc")

  $docsRoot = Get-DocsRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $sectionDir = $docsRoot
  if (-not [string]::IsNullOrWhiteSpace($sectionPath)) {
    $sectionSegments = @($sectionPath -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($sectionSegments.Count -eq 0) {
      throw "Section path must not be empty."
    }

    $sectionDir = Join-Path $docsRoot ([System.IO.Path]::Combine($sectionSegments))
    Assert-PathInsideRoot -RootPath $docsRoot -TargetPath $sectionDir

    if (-not (Test-DocsSectionExists -SectionDir $sectionDir)) {
      throw "Section does not exist: $sectionDir"
    }
  }

  $fileStem = ConvertTo-FileStem $pageName
  $pagePath = Join-Path $sectionDir "$fileStem.md"
  $position = if ($parsed.Values.ContainsKey("position")) { ConvertTo-NumericValue -Value $parsed.Values["position"] -OptionName "Position" } else { Get-NextPagePosition -SectionDir $sectionDir }
  $docSlug = if ($parsed.Values.ContainsKey("slug")) { $parsed.Values["slug"] } else { Get-SlugForPage -SectionPath $sectionPath -PageName $pageName }
  $bridgeStatus = Get-BridgeStatus
  $includeToc = (-not $noToc) -and $bridgeStatus.TocReady

  if ((Test-Path -LiteralPath $pagePath) -and (-not $force)) {
    throw "Page already exists: $pagePath"
  }

  $pageFrontMatter = New-DocFrontMatter -Title $title -Slug $docSlug -SidebarPosition $position
  Apply-CommonDocOptionValues -FrontMatter $pageFrontMatter -Values $parsed.Values
  Apply-KeyValueAssignmentsToMap `
    -Map $pageFrontMatter `
    -Assignments @($parsed.MultiValues["field"]) `
    -JsonAssignments @($parsed.MultiValues["fieldjson"])

  $pageContent = Build-ScaffoldDocContent -FrontMatter $pageFrontMatter -HeadingTitle $title -IncludeToc:$includeToc -OverviewNoun "page"
  Write-Utf8NoBomFile -Path $pagePath -Content $pageContent

  if ($includeToc) {
    $null = Queue-TocRequest -ResolvedRepoRoot $ResolvedRepoRoot -FilePath $pagePath
    [void](Open-PathInVSCode -ResolvedRepoRoot $ResolvedRepoRoot -FilePath $pagePath)
  }

  [pscustomobject]@{
    Command = "new-page"
    Path = $pagePath
    TocQueued = $includeToc
    BridgeStatus = $bridgeStatus
  }
}

function Get-MarkdownDocFiles {
  param([Parameter(Mandatory)][string]$DocsRoot)

  $files = Get-ChildItem -LiteralPath $DocsRoot -Recurse -File -Filter *.md
  return @($files | Where-Object {
      $fullName = $_.FullName
      $fullName -notmatch '\\CodingStandards\\Snapshots\\' -and
      $fullName -notmatch '\\CodingStandards\\Templates\\'
    })
}

function Get-FrontMatterBlock {
  param([Parameter(Mandatory)][string]$Content)

  if ($Content -notmatch '(?s)\A---\s*\r?\n(.*?)\r?\n---\s*(?:\r?\n|$)') {
    return $null
  }

  return $Matches[1]
}

function Get-FrontMatterValue {
  param(
    [AllowNull()][string]$FrontMatter,
    [Parameter(Mandatory)][string]$Key
  )

  if ([string]::IsNullOrWhiteSpace($FrontMatter)) {
    return $null
  }

  $pattern = "(?m)^\s*$([regex]::Escape($Key))\s*:\s*(.+?)\s*$"
  if ($FrontMatter -notmatch $pattern) {
    return $null
  }

  $value = $Matches[1].Trim()
  if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
    $value = $value.Substring(1, $value.Length - 2)
  }

  return $value
}

function Get-SidebarPositionForMarkdownFile {
  param([Parameter(Mandatory)][string]$FilePath)

  if (-not (Test-Path -LiteralPath $FilePath)) {
    return $null
  }

  $content = Get-Content -LiteralPath $FilePath -Raw
  $frontMatter = Get-FrontMatterBlock -Content $content
  $value = Get-FrontMatterValue -FrontMatter $frontMatter -Key "sidebar_position"
  if ([string]::IsNullOrWhiteSpace($value)) {
    return $null
  }

  $parsed = 0.0
  if ([double]::TryParse($value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
    return $parsed
  }

  return $null
}

function Get-CategoryPositionForDirectory {
  param([Parameter(Mandatory)][string]$DirectoryPath)

  $categoryPath = Join-Path $DirectoryPath "_category_.json"
  if (-not (Test-Path -LiteralPath $categoryPath)) {
    return $null
  }

  $categoryJson = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json
  if ($null -eq $categoryJson.position) {
    return $null
  }

  $parsed = 0.0
  if ([double]::TryParse("$($categoryJson.position)", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
    return $parsed
  }

  return $null
}

function Get-NextSectionPosition {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [Parameter(Mandatory)][string]$SectionPath
  )

  $sectionSegments = @($SectionPath -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($sectionSegments.Count -le 1) {
    $parentDir = $DocsRoot
  }
  else {
    $parentSegments = @($sectionSegments[0..($sectionSegments.Count - 2)])
    $parentDir = Join-Path $DocsRoot ([System.IO.Path]::Combine($parentSegments))
  }

  $positions = New-Object System.Collections.Generic.List[double]

  foreach ($markdownFile in @(Get-ChildItem -LiteralPath $parentDir -File -Filter *.md -ErrorAction SilentlyContinue)) {
    $position = Get-SidebarPositionForMarkdownFile -FilePath $markdownFile.FullName
    if ($null -ne $position) {
      $positions.Add($position) | Out-Null
    }
  }

  foreach ($childDir in @(Get-ChildItem -LiteralPath $parentDir -Directory -ErrorAction SilentlyContinue)) {
    $position = Get-CategoryPositionForDirectory -DirectoryPath $childDir.FullName
    if ($null -ne $position) {
      $positions.Add($position) | Out-Null
    }
  }

  if ($positions.Count -eq 0) {
    return 1.0
  }

  return (ConvertTo-CompactNumericValue -Value ((($positions.ToArray() | Measure-Object -Maximum).Maximum) + 1))
}

function Get-NextPagePosition {
  param([Parameter(Mandatory)][string]$SectionDir)

  $positions = New-Object System.Collections.Generic.List[double]

  foreach ($markdownFile in @(Get-ChildItem -LiteralPath $SectionDir -File -Filter *.md -ErrorAction SilentlyContinue)) {
    $position = Get-SidebarPositionForMarkdownFile -FilePath $markdownFile.FullName
    if ($null -ne $position) {
      $positions.Add($position) | Out-Null
    }
  }

  if ($positions.Count -eq 0) {
    return 1.0
  }

  return (ConvertTo-CompactNumericValue -Value ((($positions.ToArray() | Measure-Object -Maximum).Maximum) + 1))
}

function Normalize-DocsTargetPath {
  param([Parameter(Mandatory)][string]$TargetPath)

  $normalized = $TargetPath.Trim()
  $normalized = $normalized -replace '^[\\/]+', ''
  if ($normalized -match '^(?i:docs)[\\/](.+)$') {
    $normalized = $Matches[1]
  }

  $normalized = ($normalized -replace '/', '\').Trim('\')
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    throw "Target path must not be empty."
  }

  return $normalized
}

function Get-DocsItemRelativePath {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [Parameter(Mandatory)][string]$ItemPath,
    [Parameter(Mandatory)][string]$ItemType
  )

  if ($ItemType -eq "page") {
    return (Get-RelativeDocPath -DocsRoot $DocsRoot -FullPath $ItemPath)
  }

  return ([System.IO.Path]::GetRelativePath($DocsRoot, $ItemPath) -replace '\\', '/')
}

function Resolve-DocsNavigationTarget {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [Parameter(Mandatory)][string]$TargetPath
  )

  $normalized = Normalize-DocsTargetPath -TargetPath $TargetPath

  $directoryCandidate = Join-Path $DocsRoot $normalized
  Assert-PathInsideRoot -RootPath $DocsRoot -TargetPath $directoryCandidate
  if (Test-DocsSectionExists -SectionDir $directoryCandidate) {
    $position = Get-CategoryPositionForDirectory -DirectoryPath $directoryCandidate
    if ($null -eq $position) {
      throw "Target section does not have an explicit position: $(Get-DocsItemRelativePath -DocsRoot $DocsRoot -ItemPath $directoryCandidate -ItemType 'section')"
    }

    return [pscustomobject]@{
      ItemType = "section"
      FullPath = $directoryCandidate
      ParentDir = (Split-Path -Parent $directoryCandidate)
      RelativePath = (Get-DocsItemRelativePath -DocsRoot $DocsRoot -ItemPath $directoryCandidate -ItemType "section")
      Position = $position
    }
  }

  $fileRelativePath = $normalized
  if (-not $fileRelativePath.EndsWith(".md", [System.StringComparison]::OrdinalIgnoreCase)) {
    $fileRelativePath = "$fileRelativePath.md"
  }

  $fileCandidate = Join-Path $DocsRoot $fileRelativePath
  Assert-PathInsideRoot -RootPath $DocsRoot -TargetPath $fileCandidate
  if (-not (Test-Path -LiteralPath $fileCandidate -PathType Leaf)) {
    throw "Docs page or section not found: $TargetPath"
  }

  $pagePosition = Get-SidebarPositionForMarkdownFile -FilePath $fileCandidate
  if ($null -eq $pagePosition) {
    throw "Target page does not have an explicit sidebar_position: $(Get-DocsItemRelativePath -DocsRoot $DocsRoot -ItemPath $fileCandidate -ItemType 'page')"
  }

  return [pscustomobject]@{
    ItemType = "page"
    FullPath = $fileCandidate
    ParentDir = (Split-Path -Parent $fileCandidate)
    RelativePath = (Get-DocsItemRelativePath -DocsRoot $DocsRoot -ItemPath $fileCandidate -ItemType "page")
    Position = $pagePosition
  }
}

function Get-DocsNavigationSiblings {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [Parameter(Mandatory)][string]$ParentDir
  )

  $siblings = New-Object System.Collections.Generic.List[object]

  foreach ($markdownFile in @(Get-ChildItem -LiteralPath $ParentDir -File -Filter *.md -ErrorAction SilentlyContinue)) {
    $position = Get-SidebarPositionForMarkdownFile -FilePath $markdownFile.FullName
    if ($null -eq $position) {
      continue
    }

    $siblings.Add([pscustomobject]@{
        ItemType = "page"
        FullPath = $markdownFile.FullName
        ParentDir = $ParentDir
        RelativePath = (Get-DocsItemRelativePath -DocsRoot $DocsRoot -ItemPath $markdownFile.FullName -ItemType "page")
        Position = $position
      }) | Out-Null
  }

  foreach ($childDir in @(Get-ChildItem -LiteralPath $ParentDir -Directory -ErrorAction SilentlyContinue)) {
    if (-not (Test-DocsSectionExists -SectionDir $childDir.FullName)) {
      continue
    }

    $position = Get-CategoryPositionForDirectory -DirectoryPath $childDir.FullName
    if ($null -eq $position) {
      continue
    }

    $siblings.Add([pscustomobject]@{
        ItemType = "section"
        FullPath = $childDir.FullName
        ParentDir = $ParentDir
        RelativePath = (Get-DocsItemRelativePath -DocsRoot $DocsRoot -ItemPath $childDir.FullName -ItemType "section")
        Position = $position
      }) | Out-Null
  }

  return @($siblings | Sort-Object Position, RelativePath)
}

function Set-SidebarPositionForMarkdownFile {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)]$Position
  )

  $content = Get-Content -LiteralPath $FilePath -Raw
  $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
  $formattedPosition = Format-YamlNumber -Value (ConvertTo-CompactNumericValue -Value ([double]$Position))

  $match = [regex]::Match($content, '(?s)\A---\s*\r?\n(?<frontMatter>.*?)\r?\n---(?<rest>(?:\r?\n|$).*)\z')
  if (-not $match.Success) {
    $newContent = @(
      '---'
      "sidebar_position: $formattedPosition"
      '---'
      ''
      $content.TrimStart("`r", "`n")
    ) -join $newline
    Write-Utf8NoBomFile -Path $FilePath -Content $newContent
    return
  }

  $frontMatter = $match.Groups['frontMatter'].Value
  $rest = $match.Groups['rest'].Value

  if ($frontMatter -match '(?m)^\s*sidebar_position\s*:') {
    $updatedFrontMatter = [regex]::Replace($frontMatter, '(?m)^\s*sidebar_position\s*:\s*.+$', "sidebar_position: $formattedPosition", 1)
  }
  else {
    $updatedFrontMatter = $frontMatter.TrimEnd() + $newline + "sidebar_position: $formattedPosition"
  }

  $newContent = "---$newline$updatedFrontMatter$newline---$rest"
  Write-Utf8NoBomFile -Path $FilePath -Content $newContent
}

function Set-CategoryPositionForDirectory {
  param(
    [Parameter(Mandatory)][string]$DirectoryPath,
    [Parameter(Mandatory)]$Position
  )

  $categoryPath = Join-Path $DirectoryPath "_category_.json"
  if (-not (Test-Path -LiteralPath $categoryPath -PathType Leaf)) {
    throw "Section category metadata not found: $categoryPath"
  }

  $categoryJson = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json
  $categoryJson.position = (ConvertTo-CompactNumericValue -Value ([double]$Position))
  $content = ($categoryJson | ConvertTo-Json -Depth 20) + "`r`n"
  Write-Utf8NoBomFile -Path $categoryPath -Content $content
}

function Set-DocsNavigationItemPosition {
  param(
    [Parameter(Mandatory)][pscustomobject]$Item,
    [Parameter(Mandatory)]$Position
  )

  if ($Item.ItemType -eq "page") {
    Set-SidebarPositionForMarkdownFile -FilePath $Item.FullPath -Position $Position
    return
  }

  Set-CategoryPositionForDirectory -DirectoryPath $Item.FullPath -Position $Position
}

function Invoke-DocsReorder {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string[]]$CommandArguments = @()
  )

  $argumentList = @($CommandArguments)
  if ($argumentList.Count -eq 0) {
    throw "TargetPath is required. Usage: docs-tools reorder <TargetPath> <Position>. Run 'docs-tools help reorder'."
  }

  if ($argumentList.Count -eq 1) {
    throw "Position is required. Usage: docs-tools reorder <TargetPath> <Position>. Run 'docs-tools help reorder'."
  }

  if ($argumentList.Count -gt 2) {
    throw "Too many positional arguments for reorder. Usage: docs-tools reorder <TargetPath> <Position>. Run 'docs-tools help reorder'."
  }

  $docsRoot = Get-DocsRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $target = Resolve-DocsNavigationTarget -DocsRoot $docsRoot -TargetPath $argumentList[0]
  $desiredPosition = ConvertTo-NumericValue -Value $argumentList[1] -OptionName "Position"
  if ([double]$desiredPosition -lt 1) {
    throw "Position must be 1 or greater."
  }

  $siblings = @(Get-DocsNavigationSiblings -DocsRoot $docsRoot -ParentDir $target.ParentDir)
  if ($siblings.Count -eq 0) {
    throw "No positioned sibling items were found under '$($target.ParentDir)'."
  }

  $maxPosition = [double](($siblings | Measure-Object -Property Position -Maximum).Maximum)
  if ([double]$desiredPosition -gt $maxPosition) {
    $desiredPosition = (ConvertTo-CompactNumericValue -Value $maxPosition)
  }

  $currentPosition = [double]$target.Position
  $desiredPositionNumber = [double]$desiredPosition
  if ([Math]::Abs($currentPosition - $desiredPositionNumber) -lt 0.0000001) {
    return [pscustomobject]@{
      Command = "reorder"
      Target = $target.RelativePath
      OldPosition = $target.Position
      NewPosition = $desiredPosition
      UpdatedCount = 0
    }
  }

  $changedItems = New-Object System.Collections.Generic.List[object]
  foreach ($sibling in $siblings) {
    $siblingPath = [System.IO.Path]::GetFullPath($sibling.FullPath)
    $targetPath = [System.IO.Path]::GetFullPath($target.FullPath)
    if ($siblingPath.Equals($targetPath, [System.StringComparison]::OrdinalIgnoreCase)) {
      continue
    }

    $siblingPosition = [double]$sibling.Position
    $newSiblingPosition = $null
    if ($desiredPositionNumber -lt $currentPosition) {
      if ($siblingPosition -ge $desiredPositionNumber -and $siblingPosition -lt $currentPosition) {
        $newSiblingPosition = (ConvertTo-CompactNumericValue -Value ($siblingPosition + 1))
      }
    }
    else {
      if ($siblingPosition -le $desiredPositionNumber -and $siblingPosition -gt $currentPosition) {
        $newSiblingPosition = (ConvertTo-CompactNumericValue -Value ($siblingPosition - 1))
      }
    }

    if ($null -ne $newSiblingPosition) {
      Set-DocsNavigationItemPosition -Item $sibling -Position $newSiblingPosition
      $changedItems.Add([pscustomobject]@{
          RelativePath = $sibling.RelativePath
          Position = $newSiblingPosition
        }) | Out-Null
    }
  }

  Set-DocsNavigationItemPosition -Item $target -Position $desiredPosition
  $changedItems.Add([pscustomobject]@{
      RelativePath = $target.RelativePath
      Position = $desiredPosition
    }) | Out-Null

  return [pscustomobject]@{
    Command = "reorder"
    Target = $target.RelativePath
    OldPosition = $target.Position
    NewPosition = $desiredPosition
    UpdatedCount = $changedItems.Count
    UpdatedItems = @($changedItems | Sort-Object RelativePath)
  }
}

function Invoke-DocsCheck {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $docsRoot = Get-DocsRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $websiteRoot = Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $docFiles = @(Get-MarkdownDocFiles -DocsRoot $docsRoot)
  $slugToFiles = @{}
  $issues = New-Object System.Collections.Generic.List[string]

  foreach ($file in $docFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    $frontMatter = Get-FrontMatterBlock -Content $content
    $slug = Get-FrontMatterValue -FrontMatter $frontMatter -Key "slug"

    if (-not [string]::IsNullOrWhiteSpace($slug)) {
      if ($slug.StartsWith("/docs/", [System.StringComparison]::OrdinalIgnoreCase)) {
        $issues.Add("Slug should not start with /docs/: $($file.FullName) -> $slug") | Out-Null
      }

      if (-not $slugToFiles.ContainsKey($slug)) {
        $slugToFiles[$slug] = New-Object System.Collections.Generic.List[string]
      }

      $slugToFiles[$slug].Add($file.FullName) | Out-Null
    }

    if ($content.Contains($script:TocMarker)) {
      $issues.Add("Unprocessed TOC marker remains in: $($file.FullName)") | Out-Null
    }
  }

  foreach ($entry in $slugToFiles.GetEnumerator()) {
    if ($entry.Value.Count -gt 1) {
      $issues.Add("Duplicate slug '$($entry.Key)' used by: $($entry.Value -join ', ')") | Out-Null
    }
  }

  if (-not (Test-Path -LiteralPath $websiteRoot)) {
    throw "website/ directory not found: $websiteRoot"
  }

  if ($issues.Count -gt 0) {
    $message = @("Docs validation failed:") + @($issues | ForEach-Object { " - $_" })
    throw ($message -join [Environment]::NewLine)
  }

  Push-Location $websiteRoot
  try {
    & npm run build
    if ($LASTEXITCODE -ne 0) {
      throw "npm run build failed (exit $LASTEXITCODE)."
    }
  }
  finally {
    Pop-Location
  }

  return [pscustomobject]@{
    Command = "check"
    FilesChecked = $docFiles.Count
  }
}

function Invoke-WebsiteNpmScript {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [Parameter(Mandatory)][string]$ScriptName,
    [string[]]$ScriptArgs = @()
  )

  $normalizedScriptArgs = @(Get-NormalizedArgumentList -Values $ScriptArgs)
  $websiteRoot = Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot
  Push-Location $websiteRoot
  try {
    $npmArgs = @("run", $ScriptName)
    if ($normalizedScriptArgs.Count -gt 0) {
      $npmArgs += "--"
      $npmArgs += $normalizedScriptArgs
    }

    & npm @npmArgs
    if ($LASTEXITCODE -ne 0) {
      throw "npm run $ScriptName failed (exit $LASTEXITCODE)."
    }
  }
  finally {
    Pop-Location
  }
}

function Get-DocsStartUrl {
  param([string[]]$StartArgs = @())

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteDocsStartUrl" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Get-UEToolSuiteDocsStartUrl -StartArgs $StartArgs)
  }

  $normalizedStartArgs = @(Get-NormalizedArgumentList -Values $StartArgs)
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

function Split-DocsStartArguments {
  param([string[]]$StartArgsInput = @())

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Split-UEToolSuiteDocsStartArguments" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Split-UEToolSuiteDocsStartArguments -StartArgsInput $StartArgsInput)
  }

  $background = $false
  $passThroughArgs = New-Object System.Collections.Generic.List[string]
  foreach ($token in @(Get-NormalizedArgumentList -Values $StartArgsInput)) {
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

function Invoke-DocsStartForeground {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string[]]$StartArgs = @()
  )

  $normalizedStartArgs = @(Get-NormalizedArgumentList -Values $StartArgs)
  $url = Get-DocsStartUrl -StartArgs $normalizedStartArgs
  $websiteRoot = Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot

  Write-Output "Starting docs dev server in the current terminal."
  Write-Output "URL: $url"

  Push-Location $websiteRoot
  try {
    $npmArgs = @("run", "start")
    if ($normalizedStartArgs.Count -gt 0) {
      $npmArgs += "--"
      $npmArgs += $normalizedStartArgs
    }

    & npm @npmArgs
    if ($LASTEXITCODE -ne 0) {
      throw "npm run start failed (exit $LASTEXITCODE)."
    }
  }
  finally {
    Pop-Location
  }
}

function Invoke-DocsStartBackground {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string[]]$StartArgs = @()
  )

  $normalizedStartArgs = @(Get-NormalizedArgumentList -Values $StartArgs)
  $existingState = Get-DocsServerState -ResolvedRepoRoot $ResolvedRepoRoot
  if ($existingState) {
    if (Test-ProcessRunning -ProcessId ([int]$existingState.ProcessId)) {
      return [pscustomobject]@{
        Command = "start"
        AlreadyRunning = $true
        ProcessId = [int]$existingState.ProcessId
        LogPath = [string]$existingState.LogPath
        ErrorLogPath = [string]$existingState.ErrorLogPath
        Url = [string]$existingState.Url
      }
    }

    Remove-DocsServerState -ResolvedRepoRoot $ResolvedRepoRoot
  }

  $runtimeDir = Get-DocsToolsRuntimeDirectory -ResolvedRepoRoot $ResolvedRepoRoot
  $websiteRoot = Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot
  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null

  $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $stdoutPath = Join-Path $runtimeDir "docs-start-$stamp.stdout.log"
  $stderrPath = Join-Path $runtimeDir "docs-start-$stamp.stderr.log"

  $npmCommandParts = @("npm", "run", "start")
  if ($normalizedStartArgs.Count -gt 0) {
    $npmCommandParts += "--"
    $npmCommandParts += $normalizedStartArgs
  }

  $commandLine = (@($npmCommandParts) | ForEach-Object { ConvertTo-CmdArgument "$_" }) -join ' '
  $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
  $process = Start-Process `
    -FilePath $pwshPath `
    -ArgumentList @("-NoLogo", "-NoProfile", "-Command", $commandLine) `
    -WorkingDirectory $websiteRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -PassThru

  Start-Sleep -Seconds 2
  $trackedProcessId = if (Test-ProcessRunning -ProcessId $process.Id) { $process.Id } else { Get-DescendantProcessId -RootProcessId $process.Id }
  if ($null -eq $trackedProcessId) {
    $errorText = ""
    if (Test-Path -LiteralPath $stderrPath) {
      $errorText = (Get-Content -LiteralPath $stderrPath -Raw).Trim()
    }

    if ([string]::IsNullOrWhiteSpace($errorText) -and (Test-Path -LiteralPath $stdoutPath)) {
      $errorText = (Get-Content -LiteralPath $stdoutPath -Raw).Trim()
    }

    $details = if ([string]::IsNullOrWhiteSpace($errorText)) { "Check $stdoutPath and $stderrPath." } else { $errorText }
    throw "Docs dev server exited immediately. $details"
  }

  $url = Get-DocsStartUrl -StartArgs $normalizedStartArgs
  $state = [ordered]@{
    version = 1
    rootProcessId = $process.Id
    processId = $trackedProcessId
    startedAt = (Get-Date).ToString("o")
    websiteRoot = $websiteRoot
    logPath = $stdoutPath
    errorLogPath = $stderrPath
    url = $url
    args = $normalizedStartArgs
  }

  $statePath = Save-DocsServerState -ResolvedRepoRoot $ResolvedRepoRoot -State $state

  return [pscustomobject]@{
    Command = "start-background"
    AlreadyRunning = $false
    ProcessId = $trackedProcessId
    RootProcessId = $process.Id
    LogPath = $stdoutPath
    ErrorLogPath = $stderrPath
    StatePath = $statePath
    Url = $url
  }
}

function Invoke-DocsStop {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $state = Get-DocsServerState -ResolvedRepoRoot $ResolvedRepoRoot
  if (-not $state) {
    return [pscustomobject]@{
      Command = "stop"
      Status = "not_running"
    }
  }

  $processId = [int]$state.processId
  $rootProcessId = if ($null -ne $state.rootProcessId) { [int]$state.rootProcessId } else { $processId }
  if (-not (Test-ProcessRunning -ProcessId $processId) -and -not (Test-ProcessRunning -ProcessId $rootProcessId)) {
    Remove-DocsServerState -ResolvedRepoRoot $ResolvedRepoRoot
    return [pscustomobject]@{
      Command = "stop"
      Status = "stale_state_removed"
      ProcessId = $processId
    }
  }

  $targetPid = if (Test-ProcessRunning -ProcessId $rootProcessId) { $rootProcessId } else { $processId }
  $taskKillPath = Join-Path $env:SystemRoot "System32\taskkill.exe"
  if (Test-Path -LiteralPath $taskKillPath) {
    & $taskKillPath /PID $targetPid /T /F | Out-Null
  }
  else {
    Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
  }

  Start-Sleep -Milliseconds 750
  if (Test-ProcessRunning -ProcessId $processId) {
    Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
  }
  if (Test-ProcessRunning -ProcessId $rootProcessId) {
    Stop-Process -Id $rootProcessId -Force -ErrorAction SilentlyContinue
  }

  Remove-DocsServerState -ResolvedRepoRoot $ResolvedRepoRoot
  return [pscustomobject]@{
    Command = "stop"
    Status = "stopped"
    ProcessId = $processId
  }
}

function Invoke-DocsStatus {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $state = Get-DocsServerState -ResolvedRepoRoot $ResolvedRepoRoot
  if (-not $state) {
    return [pscustomobject]@{
      Command = "status"
      Status = "not_running"
    }
  }

  $processId = [int]$state.processId
  $rootProcessId = if ($null -ne $state.rootProcessId) { [int]$state.rootProcessId } else { $processId }
  $isRunning = (Test-ProcessRunning -ProcessId $processId) -or (Test-ProcessRunning -ProcessId $rootProcessId)
  if (-not $isRunning) {
    return [pscustomobject]@{
      Command = "status"
      Status = "stale_state"
      ProcessId = $processId
      RootProcessId = $rootProcessId
      LogPath = [string]$state.logPath
      ErrorLogPath = [string]$state.errorLogPath
      Url = [string]$state.url
    }
  }

  return [pscustomobject]@{
    Command = "status"
    Status = "running"
    ProcessId = $processId
    RootProcessId = $rootProcessId
    LogPath = [string]$state.logPath
    ErrorLogPath = [string]$state.errorLogPath
    Url = [string]$state.url
    StartedAt = [string]$state.startedAt
    Args = @($state.args)
  }
}

function Test-CommandAvailable {
  param([Parameter(Mandatory)][string]$Name)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Test-UEToolSuiteDocsCommandAvailable" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Test-UEToolSuiteDocsCommandAvailable -Name $Name)
  }

  return ($null -ne (Get-Command $Name -ErrorAction SilentlyContinue))
}

function Invoke-DocsDoctor {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $websiteRoot = Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $bridgeStatus = Get-BridgeStatus
  $status = Invoke-DocsStatus -ResolvedRepoRoot $ResolvedRepoRoot

  return [pscustomobject]@{
    Command = "doctor"
    RepoRoot = $ResolvedRepoRoot
    WebsiteRoot = $websiteRoot
    DocsRoot = (Get-DocsRoot -ResolvedRepoRoot $ResolvedRepoRoot)
    NodeInstalled = (Test-CommandAvailable -Name "node")
    NpmInstalled = (Test-CommandAvailable -Name "npm")
    NodeModulesPresent = (Test-Path -LiteralPath (Join-Path $websiteRoot "node_modules"))
    CodeCliFound = (-not [string]::IsNullOrWhiteSpace($bridgeStatus.CodeCliPath))
    CodeCliPath = $bridgeStatus.CodeCliPath
    MarkdownAllInOneInstalled = $bridgeStatus.MarkdownAllInOneInstalled
    BridgeInstalled = $bridgeStatus.BridgeInstalled
    TocReady = $bridgeStatus.TocReady
    ServerStatus = $status.Status
    ServerUrl = $status.Url
    ServerLogPath = $status.LogPath
    ServerErrorLogPath = $status.ErrorLogPath
  }
}

function Write-DocsToolsError {
  param([Parameter(Mandatory)][string]$Message)

  $formatted = "Error: $Message"
  Write-Host $formatted -ForegroundColor Red
}

function Invoke-InstallBridge {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $bridgeSource = Join-Path $PSScriptRoot "VSCodeBridge"
  $packagePath = Join-Path $bridgeSource "package.json"
  if (-not (Test-Path -LiteralPath $packagePath)) {
    throw "VS Code bridge package.json not found: $packagePath"
  }

  $packageJson = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
  $publisher = [string]$packageJson.publisher
  $name = [string]$packageJson.name
  $version = [string]$packageJson.version
  if ([string]::IsNullOrWhiteSpace($publisher) -or [string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($version)) {
    throw "Bridge package.json is missing publisher, name, or version."
  }

  $extensionsRoot = Join-Path $env:USERPROFILE ".vscode\extensions"
  New-Item -ItemType Directory -Force -Path $extensionsRoot | Out-Null

  $prefix = "$publisher.$name-"
  Get-ChildItem -LiteralPath $extensionsRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "$prefix*" } |
    ForEach-Object {
      $resolved = $_.FullName
      if ($resolved.StartsWith($extensionsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
      }
    }

  $destination = Join-Path $extensionsRoot "$publisher.$name-$version"
  Copy-Item -LiteralPath $bridgeSource -Destination $destination -Recurse -Force

  return [pscustomobject]@{
    Command = "install-bridge"
    Destination = $destination
    MarkdownAllInOneInstalled = (Test-VSCodeExtensionInstalled -ExtensionId $script:MarkdownAllInOneExtensionId)
  }
}

function Invoke-DocsToolsMain {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string[]]$CommandArguments
  )

  $allArgs = @(Get-NormalizedArgumentList -Values $CommandArguments)
  if ($allArgs.Count -eq 0) {
    Write-Output (Get-DocsToolsRootHelp)
    return
  }

  if (Test-DocsToolsHelpToken -Token ([string]$allArgs[0])) {
    if ($allArgs.Count -gt 1) {
      Write-Output (Get-DocsToolsCommandHelp -CommandName $allArgs[1])
    }
    else {
      Write-Output (Get-DocsToolsRootHelp)
    }
    return
  }

  $command = Resolve-DocsToolsCommandAlias -CommandName ([string]$allArgs[0])

  $remaining = if ($allArgs.Count -gt 1) { @($allArgs[1..($allArgs.Count - 1)]) } else { @() }
  if ($remaining.Count -gt 0 -and (Test-DocsToolsHelpToken -Token ([string]$remaining[0]))) {
    Write-Output (Get-DocsToolsCommandHelp -CommandName $command)
    return
  }

  switch ($command) {
    "new-section" {
      $newSectionParameters = @{ ResolvedRepoRoot = $ResolvedRepoRoot }
      if ($remaining.Count -gt 0) {
        $newSectionParameters.CommandArguments = @($remaining)
      }

      $result = Invoke-NewSection @newSectionParameters
      Write-Output "Created section: $($result.Path)"
      Write-Output "Category metadata: $($result.CategoryPath)"
      if ($result.TocQueued) { Write-Output "TOC request queued through the VS Code bridge." }
      else { Write-Output "TOC generation skipped." }
      return
    }
    "new-page" {
      $newPageParameters = @{ ResolvedRepoRoot = $ResolvedRepoRoot }
      if ($remaining.Count -gt 0) {
        $newPageParameters.CommandArguments = @($remaining)
      }

      $result = Invoke-NewPage @newPageParameters
      Write-Output "Created page: $($result.Path)"
      if ($result.TocQueued) { Write-Output "TOC request queued through the VS Code bridge." }
      else { Write-Output "TOC generation skipped." }
      return
    }
    "reorder" {
      $reorderParameters = @{ ResolvedRepoRoot = $ResolvedRepoRoot }
      if ($remaining.Count -gt 0) {
        $reorderParameters.CommandArguments = @($remaining)
      }

      $result = Invoke-DocsReorder @reorderParameters
      if ($result.UpdatedCount -eq 0) {
        Write-Output "No reorder needed. '$($result.Target)' is already at position $($result.NewPosition)."
      }
      else {
        Write-Output "Reordered '$($result.Target)' from $($result.OldPosition) to $($result.NewPosition)."
        Write-Output "Updated items: $($result.UpdatedCount)"
      }
      return
    }
    "preview" {
      Write-Output "preview is deprecated. Use 'docs-tools start' or 'docs-tools start --background'."
      if ($remaining.Count -gt 0) {
        $previewMode = Split-DocsStartArguments -StartArgsInput $remaining
      }
      else {
        $previewMode = Split-DocsStartArguments
      }
      $result = Invoke-DocsStartBackground -ResolvedRepoRoot $ResolvedRepoRoot -StartArgs $previewMode.StartArgs
      if ($result.AlreadyRunning) {
        Write-Output "Docs dev server is already running (PID $($result.ProcessId))."
      }
      else {
        Write-Output "Started docs dev server in the background (PID $($result.ProcessId))."
      }
      Write-Output "URL: $($result.Url)"
      Write-Output "Stdout log: $($result.LogPath)"
      Write-Output "Stderr log: $($result.ErrorLogPath)"
      return
    }
    "start" {
      if ($remaining.Count -gt 0) {
        $startMode = Split-DocsStartArguments -StartArgsInput $remaining
      }
      else {
        $startMode = Split-DocsStartArguments
      }
      if ($startMode.Background) {
        $result = Invoke-DocsStartBackground -ResolvedRepoRoot $ResolvedRepoRoot -StartArgs $startMode.StartArgs
        if ($result.AlreadyRunning) {
          Write-Output "Docs dev server is already running (PID $($result.ProcessId))."
        }
        else {
          Write-Output "Started docs dev server in the background (PID $($result.ProcessId))."
        }
        Write-Output "URL: $($result.Url)"
        Write-Output "Stdout log: $($result.LogPath)"
        Write-Output "Stderr log: $($result.ErrorLogPath)"
        return
      }

      Invoke-DocsStartForeground -ResolvedRepoRoot $ResolvedRepoRoot -StartArgs $startMode.StartArgs
      return
    }
    "stop" {
      $result = Invoke-DocsStop -ResolvedRepoRoot $ResolvedRepoRoot
      switch ($result.Status) {
        "not_running" { Write-Output "Tracked background docs dev server is not running." }
        "stale_state_removed" { Write-Output "Removed stale background docs dev server state for PID $($result.ProcessId)." }
        default { Write-Output "Stopped background docs dev server (PID $($result.ProcessId))." }
      }
      return
    }
    "status" {
      $result = Invoke-DocsStatus -ResolvedRepoRoot $ResolvedRepoRoot
      switch ($result.Status) {
        "not_running" { Write-Output "Tracked background docs dev server is not running." }
        "stale_state" {
          Write-Output "Background docs dev server is not running, but stale state still exists for PID $($result.ProcessId)."
          Write-Output "URL: $($result.Url)"
          Write-Output "Stdout log: $($result.LogPath)"
          Write-Output "Stderr log: $($result.ErrorLogPath)"
        }
        default {
          Write-Output "Background docs dev server is running (PID $($result.ProcessId))."
          Write-Output "URL: $($result.Url)"
          Write-Output "Started: $($result.StartedAt)"
          Write-Output "Stdout log: $($result.LogPath)"
          Write-Output "Stderr log: $($result.ErrorLogPath)"
        }
      }
      return
    }
    "check" {
      $result = Invoke-DocsCheck -ResolvedRepoRoot $ResolvedRepoRoot
      Write-Output "Docs check passed. Files checked: $($result.FilesChecked)"
      return
    }
    "doctor" {
      $result = Invoke-DocsDoctor -ResolvedRepoRoot $ResolvedRepoRoot
      Write-Output "Repo root: $($result.RepoRoot)"
      Write-Output "Website root: $($result.WebsiteRoot)"
      Write-Output "Node installed: $($result.NodeInstalled)"
      Write-Output "npm installed: $($result.NpmInstalled)"
      Write-Output "website/node_modules present: $($result.NodeModulesPresent)"
      Write-Output "VS Code CLI found: $($result.CodeCliFound)"
      if ($result.CodeCliFound) {
        Write-Output "VS Code CLI path: $($result.CodeCliPath)"
      }
      Write-Output "Markdown All in One installed: $($result.MarkdownAllInOneInstalled)"
      Write-Output "Docs bridge installed: $($result.BridgeInstalled)"
      Write-Output "TOC automation ready: $($result.TocReady)"
      Write-Output "Background docs dev server status: $($result.ServerStatus)"
      if ($result.ServerUrl) {
        Write-Output "Background docs dev server URL: $($result.ServerUrl)"
      }
      if ($result.ServerLogPath) {
        Write-Output "Background docs dev server stdout log: $($result.ServerLogPath)"
      }
      if ($result.ServerErrorLogPath) {
        Write-Output "Background docs dev server stderr log: $($result.ServerErrorLogPath)"
      }
      return
    }
    "install-bridge" {
      $result = Invoke-InstallBridge -ResolvedRepoRoot $ResolvedRepoRoot
      Write-Output "Installed VS Code bridge to: $($result.Destination)"
      if ($result.MarkdownAllInOneInstalled) {
        Write-Output "Markdown All in One is already installed."
      }
      else {
        Write-Output "Markdown All in One is not installed. TOC generation will still be skipped until it is present."
      }
      Write-Output "Reload VS Code windows to activate the bridge."
      return
    }
    default {
      $packageScripts = @(Get-WebsitePackageScriptNames -ResolvedRepoRoot $ResolvedRepoRoot)
      if ($packageScripts -contains $command) {
        if ($remaining.Count -gt 0) {
          Invoke-WebsiteNpmScript -ResolvedRepoRoot $ResolvedRepoRoot -ScriptName $command -ScriptArgs $remaining
        }
        else {
          Invoke-WebsiteNpmScript -ResolvedRepoRoot $ResolvedRepoRoot -ScriptName $command
        }
        return
      }

      throw "Unknown docs-tools command '$command'. Run 'docs-tools help'."
    }
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  try {
    $resolvedRepoRoot = Get-DocsToolsRepoRoot -ExplicitRepoRoot $RepoRoot
    $effectiveCommandArgs = New-Object System.Collections.Generic.List[string]
    foreach ($argument in @($CommandArgs)) {
      $effectiveCommandArgs.Add([string]$argument) | Out-Null
    }
    foreach ($argument in @($ExtraArgs)) {
      $effectiveCommandArgs.Add([string]$argument) | Out-Null
    }
    foreach ($argument in @($MyInvocation.UnboundArguments)) {
      $effectiveCommandArgs.Add([string]$argument) | Out-Null
    }

    Invoke-DocsToolsMain -ResolvedRepoRoot $resolvedRepoRoot -CommandArguments $effectiveCommandArgs.ToArray()
  }
  catch {
    Write-DocsToolsError -Message $_.Exception.Message
    exit 1
  }
}
