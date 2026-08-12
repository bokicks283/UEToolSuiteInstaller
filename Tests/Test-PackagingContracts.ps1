[CmdletBinding()]
param(
  [switch]$FailFast
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$testHarnessPath = Join-Path $repoRoot "payload\Scripts\Tests\TestHarness.ps1"
if (-not (Test-Path -LiteralPath $testHarnessPath -PathType Leaf)) {
  throw "Test harness not found: $testHarnessPath"
}
. $testHarnessPath

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$resultsDir = Join-Path $PSScriptRoot "Test-PackagingContractsResults"
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logPath = Join-Path $resultsDir "PackagingContracts-$stamp.log"

$script:PassCount = 0
$script:FailCount = 0
Initialize-TestHarness -LogPath $logPath -FailFast:$FailFast

function Assert-HasLiteral {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Needle
  )
  Assert-Condition -Name $Name -Condition ($Text -like "*$Needle*") -PassDetail "found '$Needle'" -FailDetail "missing '$Needle'"
}

function Assert-LacksLiteral {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Needle
  )
  Assert-Condition -Name $Name -Condition ($Text -notlike "*$Needle*") -PassDetail "missing '$Needle'" -FailDetail "unexpected '$Needle'"
}

function Assert-ManagedFileIndexMatchesPayload {
  param(
    [Parameter(Mandatory)][string]$NamePrefix,
    [Parameter(Mandatory)][string]$PayloadRoot,
    [Parameter(Mandatory)][string]$IndexPath
  )

  Assert-Condition -Name "$NamePrefix index exists" -Condition (Test-Path -LiteralPath $IndexPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $IndexPath"
  if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
    return
  }

  $index = Get-Content -LiteralPath $IndexPath -Raw | ConvertFrom-Json
  foreach ($entry in @($index.files)) {
    $relativePath = [string]$entry.relativePath
    $expectedHash = ([string]$entry.sha256).ToLowerInvariant()
    $payloadPath = Join-Path $PayloadRoot ($relativePath -replace '/', '\')
    Assert-Condition -Name "$NamePrefix payload file exists: $relativePath" -Condition (Test-Path -LiteralPath $payloadPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $payloadPath"
    if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
      continue
    }

    $actualHash = (Get-FileHash -LiteralPath $payloadPath).Hash.ToLowerInvariant()
    Assert-Condition -Name "$NamePrefix hash matches payload: $relativePath" -Condition ($actualHash -eq $expectedHash) -PassDetail $actualHash -FailDetail "expected $expectedHash but found $actualHash"
  }
}

function Get-NpmLockRootDependencyNames {
  param(
    [Parameter(Mandatory)][string]$LockPath
  )

  $nodeScript = @'
const fs = require("fs");
const lockPath = process.argv[process.argv.length - 1];
const lock = JSON.parse(fs.readFileSync(lockPath, "utf8"));
const deps = Object.keys((((lock || {}).packages || {})[""] || {}).dependencies || {});
process.stdout.write(JSON.stringify(deps));
'@

  $dependencyJson = $nodeScript | & node - $LockPath
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to read npm lock root dependencies from $LockPath"
  }

  return @($dependencyJson | ConvertFrom-Json)
}

try {
  Step "Packaging contract checks ($stamp)"
  Write-Log "Repo: $repoRoot" Cyan
  Write-Log "Log : $logPath" Cyan

  $csprojPath = Join-Path $repoRoot "src\UEToolSuiteInstaller.Gui\UEToolSuiteInstaller.Gui.csproj"
  $programPath = Join-Path $repoRoot "src\UEToolSuiteInstaller.Gui\Program.cs"
  $iconPath = Join-Path $repoRoot "src\UEToolSuiteInstaller.Gui\Assets\UEToolSuiteInstaller.ico"
  $publishScriptPath = Join-Path $repoRoot "Scripts\Publish-InstallerExe.ps1"
  $workflowPath = Join-Path $repoRoot ".github\workflows\release.yml"
  $themeCatalogPath = Join-Path $repoRoot "payload\website\theme-presets\theme-catalog.json"
  $docsEditorHostPath = Join-Path $repoRoot "payload\Scripts\UETools\DocsEditorApiHost.ps1"
  $docsSidebarSwizzlePath = Join-Path $repoRoot "payload\website\src\theme\DocSidebar\index.tsx"
  $docsDocItemLayoutPath = Join-Path $repoRoot "payload\website\src\theme\DocItem\Layout\index.tsx"
  $docsAuthoringPanelPath = Join-Path $repoRoot "payload\website\src\theme\authoring\SiteAdminPanel.tsx"
  $docsAuthoringApiPath = Join-Path $repoRoot "payload\website\src\theme\authoring\api.ts"
  $docsShortcodeModulePath = Join-Path $repoRoot "payload\website\src\clientModules\lucideShortcodes.ts"
  $docsModulePath = Join-Path $repoRoot "payload\Scripts\UETools\UEToolSuite.Docs.psm1"
  $docsConfigPath = Join-Path $repoRoot "payload\website\docusaurus.config.ts"
  $docsPackageJsonPath = Join-Path $repoRoot "payload\website\package.json"
  $docsPackageLockPath = Join-Path $repoRoot "payload\website\package-lock.json"
  $docsBrowserQaPath = Join-Path $repoRoot "Tests\DocsAuthoringBrowserQA.md"
  $docsStandaloneEditorPagePath = Join-Path $repoRoot "payload\website\src\pages\editor.tsx"
  $docsStandaloneEditorStylesPath = Join-Path $repoRoot "payload\website\src\pages\editor.module.css"
  $payloadManifestPath = Join-Path $repoRoot "payload\ue-tool-suite.manifest.json"
  $docsManagedIndexPath = Join-Path $repoRoot "payload\docs-managed-file-index.json"
  $websiteManagedIndexPath = Join-Path $repoRoot "payload\website-managed-file-index.json"

  Assert-Condition -Name "GUI project file exists" -Condition (Test-Path -LiteralPath $csprojPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $csprojPath"
  Assert-Condition -Name "GUI runtime file exists" -Condition (Test-Path -LiteralPath $programPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $programPath"
  Assert-Condition -Name "GUI icon exists" -Condition (Test-Path -LiteralPath $iconPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $iconPath"
  Assert-Condition -Name "Publish script exists" -Condition (Test-Path -LiteralPath $publishScriptPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $publishScriptPath"
  Assert-Condition -Name "Release workflow exists" -Condition (Test-Path -LiteralPath $workflowPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $workflowPath"
  Assert-Condition -Name "Website theme catalog exists" -Condition (Test-Path -LiteralPath $themeCatalogPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $themeCatalogPath"
  Assert-Condition -Name "Docs editor API host exists" -Condition (Test-Path -LiteralPath $docsEditorHostPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $docsEditorHostPath"
  Assert-Condition -Name "Docs sidebar swizzle exists" -Condition (Test-Path -LiteralPath $docsSidebarSwizzlePath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $docsSidebarSwizzlePath"
  Assert-Condition -Name "Docs doc item layout swizzle exists" -Condition (Test-Path -LiteralPath $docsDocItemLayoutPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $docsDocItemLayoutPath"
  Assert-Condition -Name "Docs site admin panel exists" -Condition (Test-Path -LiteralPath $docsAuthoringPanelPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $docsAuthoringPanelPath"
  Assert-Condition -Name "Docs authoring API helper exists" -Condition (Test-Path -LiteralPath $docsAuthoringApiPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $docsAuthoringApiPath"
  Assert-Condition -Name "Docs shortcode module exists" -Condition (Test-Path -LiteralPath $docsShortcodeModulePath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $docsShortcodeModulePath"
  Assert-Condition -Name "Docs module exists" -Condition (Test-Path -LiteralPath $docsModulePath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $docsModulePath"
  Assert-Condition -Name "Docs config exists" -Condition (Test-Path -LiteralPath $docsConfigPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $docsConfigPath"
  Assert-Condition -Name "Docs package.json exists" -Condition (Test-Path -LiteralPath $docsPackageJsonPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $docsPackageJsonPath"
  Assert-Condition -Name "Docs package-lock.json exists" -Condition (Test-Path -LiteralPath $docsPackageLockPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $docsPackageLockPath"
  Assert-Condition -Name "Docs browser QA checklist exists" -Condition (Test-Path -LiteralPath $docsBrowserQaPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $docsBrowserQaPath"
  Assert-Condition -Name "Payload manifest exists" -Condition (Test-Path -LiteralPath $payloadManifestPath -PathType Leaf) -PassDetail "present" -FailDetail "missing: $payloadManifestPath"

  Step "Managed payload index contract"
  Assert-ManagedFileIndexMatchesPayload -NamePrefix "docs managed index" -PayloadRoot (Join-Path $repoRoot "payload") -IndexPath $docsManagedIndexPath
  Assert-ManagedFileIndexMatchesPayload -NamePrefix "website managed index" -PayloadRoot (Join-Path $repoRoot "payload") -IndexPath $websiteManagedIndexPath
  $websiteManagedIndex = Get-Content -LiteralPath $websiteManagedIndexPath -Raw | ConvertFrom-Json
  $websiteManagedPaths = @($websiteManagedIndex.files | ForEach-Object { [string]$_.relativePath })
  Assert-Condition -Name "website managed index includes runtime discovery source" -Condition ($websiteManagedPaths -contains "website/src/theme/authoring/runtimeDiscovery.ts") -PassDetail "runtime discovery managed" -FailDetail "missing website/src/theme/authoring/runtimeDiscovery.ts"
  Assert-Condition -Name "website managed index includes connection status card source" -Condition ($websiteManagedPaths -contains "website/src/theme/authoring/AuthoringConnectionStatusCard.tsx") -PassDetail "status card managed" -FailDetail "missing website/src/theme/authoring/AuthoringConnectionStatusCard.tsx"
  Assert-Condition -Name "website managed index includes document page authoring helper source" -Condition ($websiteManagedPaths -contains "website/src/theme/authoring/docPageAuthoring.ts") -PassDetail "doc page authoring helper managed" -FailDetail "missing website/src/theme/authoring/docPageAuthoring.ts"
  Assert-Condition -Name "website managed index includes authoring runtime tests" -Condition ($websiteManagedPaths -contains "website/scripts/test-authoring-runtime.cjs") -PassDetail "runtime tests managed" -FailDetail "missing website/scripts/test-authoring-runtime.cjs"
  Assert-Condition -Name "website managed index excludes built index html" -Condition ($websiteManagedPaths -notcontains "website/build/index.html") -PassDetail "website/build/index.html not managed" -FailDetail "website/build/index.html should not be managed"
  Assert-Condition -Name "website managed index excludes generated build output" -Condition (@($websiteManagedPaths | Where-Object { $_ -like "website/build/*" }).Count -eq 0) -PassDetail "website/build output not managed" -FailDetail "website/build entries should not be managed"

  Step "GUI publish content contract"
  [xml]$csprojXml = Get-Content -LiteralPath $csprojPath -Raw
  $projectNode = $csprojXml.Project
  Assert-Condition -Name "GUI targets net10 windows" -Condition ($projectNode.PropertyGroup.TargetFramework -contains "net10.0-windows") -PassDetail "net10.0-windows" -FailDetail "TargetFramework mismatch"
  Assert-Condition -Name "GUI single-file publish enabled" -Condition ($projectNode.PropertyGroup.PublishSingleFile -contains "true") -PassDetail "PublishSingleFile=true" -FailDetail "PublishSingleFile not true"
  Assert-Condition -Name "GUI self-contained publish enabled" -Condition ($projectNode.PropertyGroup.SelfContained -contains "true") -PassDetail "SelfContained=true" -FailDetail "SelfContained not true"
  Assert-Condition -Name "GUI application icon configured" -Condition ($projectNode.PropertyGroup.ApplicationIcon -contains "Assets\UEToolSuiteInstaller.ico") -PassDetail "ApplicationIcon configured" -FailDetail "ApplicationIcon missing or incorrect"

  $contentNodes = @($projectNode.ItemGroup.Content)
  $contentInclude = @($contentNodes | ForEach-Object { $_.Include })
  Assert-Condition -Name "GUI bundles installer script content" -Condition ($contentInclude -contains "..\..\Install-UEToolSuite.ps1") -PassDetail "installer script content present" -FailDetail "missing installer script content include"
  Assert-Condition -Name "GUI bundles payload content tree" -Condition ($contentInclude -contains "..\..\payload\**\*") -PassDetail "payload content include present" -FailDetail "missing payload content include"
  $payloadContentNode = @($contentNodes | Where-Object { $_.Include -eq "..\..\payload\**\*" }) | Select-Object -First 1
  $payloadContentExcludes = @(([string]$payloadContentNode.Exclude) -split ";")
  Assert-Condition -Name "GUI excludes generated test result trees" -Condition ($payloadContentExcludes -contains "..\..\payload\**\*Results\**\*") -PassDetail "generated test result trees excluded" -FailDetail "payload content can bundle generated *Results directories and exceed Windows extraction path limits"

  Step "GUI runtime contract"
  $programText = Get-Content -LiteralPath $programPath -Raw
  Assert-HasLiteral -Name "gui run-init option exists" -Text $programText -Needle "Run repo initialization after install"
  Assert-HasLiteral -Name "gui run-init requests non-interactive installer init" -Text $programText -Needle "-InitNonInteractive"
  Assert-HasLiteral -Name "gui exposes terminal output toggle" -Text $programText -Needle "Show terminal output"
  Assert-HasLiteral -Name "gui terminal hidden by default" -Text $programText -Needle "Panel2Collapsed = true"
  Assert-HasLiteral -Name "gui defers splitter min constraints until form is sized" -Text $programText -Needle "ApplySplitterMinimums();"
  Assert-HasLiteral -Name "gui terminal is resizable split layout" -Text $programText -Needle "SplitContainer"
  Assert-HasLiteral -Name "gui startup failures show explicit error dialog" -Text $programText -Needle "Installer UI failed to start."
  Assert-HasLiteral -Name "gui includes progress bar" -Text $programText -Needle "ProgressBar"
  Assert-HasLiteral -Name "gui progress parser tracks docs npm dependency phase" -Text $programText -Needle "Installing docs site dependencies with npm"
  Assert-HasLiteral -Name "gui progress text reports docs npm install phase" -Text $programText -Needle "Installing docs dependencies (npm install)..."
  Assert-HasLiteral -Name "gui progress text reports docs npm ci phase" -Text $programText -Needle "Installing docs dependencies (npm ci)..."
  Assert-HasLiteral -Name "gui progress parser tracks docs doctor phase" -Text $programText -Needle "Running ue-tools docs doctor..."
  Assert-HasLiteral -Name "gui progress text reports docs doctor phase" -Text $programText -Needle "Running docs doctor (Docusaurus validation)..."
  Assert-HasLiteral -Name "gui progress text reports first-time ue build phase" -Text $programText -Needle "Running first-time Unreal build setup..."
  Assert-HasLiteral -Name "gui enforces no-output timeout guard" -Text $programText -Needle "NoOutputTimeout"
  Assert-HasLiteral -Name "gui includes cancel button" -Text $programText -Needle "Cancel"
  Assert-HasLiteral -Name "gui prompts for another project on success" -Text $programText -Needle "Install in another project?"
  Assert-HasLiteral -Name "gui includes advanced options panel" -Text $programText -Needle "Show advanced options"
  Assert-HasLiteral -Name "gui advanced options are disabled by default" -Text $programText -Needle 'ConfigureOptionCheckBox(showAdvancedOptionsCheckBox, "Show advanced options", false);'
  Assert-HasLiteral -Name "gui main form supports scrolling for overflow content" -Text $programText -Needle "mainContentScrollPanel.AutoScroll = true;"
  Assert-HasLiteral -Name "gui options container auto-sizes to avoid clipping" -Text $programText -Needle "optionsContainer.AutoSize = true;"
  Assert-HasLiteral -Name "gui advanced panel auto-sizes to avoid clipping" -Text $programText -Needle "advancedOptionsPanel.AutoSize = true;"
  Assert-HasLiteral -Name "gui exposes skip shell aliases option explicitly" -Text $programText -Needle "Skip PowerShell shell alias install during init (-SkipShellAliases)"
  Assert-HasLiteral -Name "gui supports skip docs payload option" -Text $programText -Needle "-SkipDocs"
  Assert-HasLiteral -Name "gui supports skip website payload option" -Text $programText -Needle "-SkipWebsite"
  Assert-HasLiteral -Name "gui supports skip tests payload option" -Text $programText -Needle "-SkipTests"
  Assert-LacksLiteral -Name "gui does not expose obsolete global cli opt-in" -Text $programText -Needle "-GlobalCli"
  Assert-HasLiteral -Name "gui supports skip ai tools payload option" -Text $programText -Needle "-SkipAITools"
  Assert-HasLiteral -Name "gui supports skip artsource tools payload option" -Text $programText -Needle "-SkipArtSourceTools"
  Assert-HasLiteral -Name "gui supports skip coding standards payload option" -Text $programText -Needle "-SkipCodingStandardsTools"
  Assert-HasLiteral -Name "gui includes docs branding controls" -Text $programText -Needle "Docs website branding"
  Assert-HasLiteral -Name "gui includes website theme selector" -Text $programText -Needle "Theme"
  Assert-HasLiteral -Name "gui includes global site icon control" -Text $programText -Needle "Global site icon (.svg/.png)"
  Assert-HasLiteral -Name "gui includes per-asset overrides toggle" -Text $programText -Needle "Use per-asset overrides"
  Assert-HasLiteral -Name "gui includes website install mode control" -Text $programText -Needle "Website install mode"
  Assert-HasLiteral -Name "gui includes bulk override selector" -Text $programText -Needle "Apply to all"
  Assert-HasLiteral -Name "gui forwards website theme flag" -Text $programText -Needle "-WebsiteTheme"
  Assert-HasLiteral -Name "gui forwards website install mode flag" -Text $programText -Needle "-WebsiteInstallMode"
  Assert-HasLiteral -Name "gui forwards website global icon flag" -Text $programText -Needle "-WebsiteGlobalIconPath"
  Assert-HasLiteral -Name "gui forwards website logo flag" -Text $programText -Needle "-WebsiteLogoPath"
  Assert-HasLiteral -Name "gui forwards website favicon flag" -Text $programText -Needle "-WebsiteFaviconPath"
  Assert-HasLiteral -Name "gui forwards website social card flag" -Text $programText -Needle "-WebsiteSocialCardPath"
  Assert-HasLiteral -Name "gui forwards website force suite paths as one array argument" -Text $programText -Needle 'string.Join(",", options.WebsiteForceSuitePaths)'
  Assert-HasLiteral -Name "gui forwards website force project paths as one array argument" -Text $programText -Needle 'string.Join(",", options.WebsiteForceProjectPaths)'
  Assert-HasLiteral -Name "gui supports skip optional setup option" -Text $programText -Needle "-SkipOptionalToolSetup"
  Assert-HasLiteral -Name "gui supports skip docs setup option" -Text $programText -Needle "-SkipDocsSetup"
  Assert-HasLiteral -Name "gui supports skip docs npm install option" -Text $programText -Needle "-SkipDocsNpmInstall"
  Assert-HasLiteral -Name "gui supports force docs npm install option" -Text $programText -Needle "-ForceDocsNpmInstall"
  Assert-HasLiteral -Name "gui supports skip docs bridge option" -Text $programText -Needle "-SkipDocsBridgeInstall"
  Assert-HasLiteral -Name "gui supports no build option" -Text $programText -Needle "-NoBuild"
  Assert-HasLiteral -Name "gui supports no regen option" -Text $programText -Needle "-NoRegen"

  Step "Docs editor contract"
  $docsModuleText = Get-Content -LiteralPath $docsModulePath -Raw
  $docsConfigText = Get-Content -LiteralPath $docsConfigPath -Raw
  $docsSidebarText = Get-Content -LiteralPath $docsSidebarSwizzlePath -Raw
  $docsDocItemLayoutText = Get-Content -LiteralPath $docsDocItemLayoutPath -Raw
  $docsAuthoringPanelText = Get-Content -LiteralPath $docsAuthoringPanelPath -Raw
  $docsBrowserQaText = Get-Content -LiteralPath $docsBrowserQaPath -Raw
  $payloadManifestText = Get-Content -LiteralPath $payloadManifestPath -Raw
  Assert-HasLiteral -Name "docs module starts editor api in foreground start" -Text $docsModuleText -Needle "Start-DocsEditorApiBackground -ResolvedRepoRoot $ResolvedRepoRoot"
  Assert-HasLiteral -Name "docs module writes editor runtime config" -Text $docsModuleText -Needle "editor-runtime.json"
  Assert-HasLiteral -Name "docs module exposes visibility command" -Text $docsModuleText -Needle "ue-tools docs visibility"
  Assert-HasLiteral -Name "docs module exposes migrate-sections command" -Text $docsModuleText -Needle "ue-tools docs migrate-sections"
  Assert-LacksLiteral -Name "docs module removed docs edit command" -Text $docsModuleText -Needle "ue-tools docs edit"
  Assert-LacksLiteral -Name "docs config removed editor navbar route" -Text $docsConfigText -Needle "to: '/editor'"
  Assert-Condition -Name "docs payload omits standalone editor route" -Condition (-not (Test-Path -LiteralPath $docsStandaloneEditorPagePath -PathType Leaf)) -PassDetail "standalone editor page absent" -FailDetail "unexpected file: $docsStandaloneEditorPagePath"
  Assert-Condition -Name "docs payload omits standalone editor styles" -Condition (-not (Test-Path -LiteralPath $docsStandaloneEditorStylesPath -PathType Leaf)) -PassDetail "standalone editor styles absent" -FailDetail "unexpected file: $docsStandaloneEditorStylesPath"
  Assert-HasLiteral -Name "payload cleanup removes retired standalone editor page" -Text $payloadManifestText -Needle "website/src/pages/editor.tsx"
  Assert-HasLiteral -Name "payload cleanup removes retired standalone editor styles" -Text $payloadManifestText -Needle "website/src/pages/editor.module.css"
  Assert-HasLiteral -Name "docs config declares client modules" -Text $docsConfigText -Needle "clientModules:"
  Assert-HasLiteral -Name "docs config wires shortcode client module" -Text $docsConfigText -Needle "lucideShortcodes.ts"
  Assert-HasLiteral -Name "docs config enables Docusaurus Mermaid markdown" -Text $docsConfigText -Needle "mermaid: true"
  Assert-HasLiteral -Name "docs config includes Docusaurus Mermaid theme" -Text $docsConfigText -Needle "@docusaurus/theme-mermaid"
  Assert-HasLiteral -Name "docs sidebar wraps Docusaurus original component" -Text $docsSidebarText -Needle "@theme-original/DocSidebar"
  Assert-LacksLiteral -Name "docs sidebar no longer fetches api tree at read time" -Text $docsSidebarText -Needle "/api/tree"
  Assert-LacksLiteral -Name "docs sidebar no longer fetches domains at read time" -Text $docsSidebarText -Needle "/api/domains"
  Assert-HasLiteral -Name "site admin panel exposes dedicated structure ordering surface" -Text $docsAuthoringPanelText -Needle 'Save Structure'
  Assert-HasLiteral -Name "site admin panel exposes hide from site action" -Text $docsAuthoringPanelText -Needle 'Hide From Site'
  Assert-HasLiteral -Name "site admin panel exposes show in site action" -Text $docsAuthoringPanelText -Needle 'Show In Site'
  Assert-HasLiteral -Name "site admin panel exposes landing visibility toggle" -Text $docsAuthoringPanelText -Needle 'Show landing page in sidebar'
  Assert-HasLiteral -Name "doc layout exposes single edit entrypoint" -Text $docsDocItemLayoutText -Needle "setEditMode(true)"
  Assert-HasLiteral -Name "doc layout exposes page visibility action" -Text $docsDocItemLayoutText -Needle "toggleCurrentPageVisibility"
  Assert-HasLiteral -Name "doc layout persists unlisted visibility state" -Text $docsDocItemLayoutText -Needle "'unlisted'"
  Assert-HasLiteral -Name "doc layout renders hidden page notice from current page state" -Text $docsDocItemLayoutText -Needle "This page is hidden from site navigation."
  Assert-HasLiteral -Name "doc layout uses tiptap editor content" -Text $docsDocItemLayoutText -Needle "EditorContent"
  Assert-HasLiteral -Name "doc layout exposes formatting toolbar" -Text $docsDocItemLayoutText -Needle "toggleBold"
  Assert-HasLiteral -Name "doc layout exposes alignment toolbar" -Text $docsDocItemLayoutText -Needle "applyTextAlignment(activeEditor, 'center')"
  Assert-HasLiteral -Name "doc layout exposes link insert UI" -Text $docsDocItemLayoutText -Needle "Insert link"
  Assert-HasLiteral -Name "doc layout exposes image insert UI" -Text $docsDocItemLayoutText -Needle "Insert image"
  Assert-HasLiteral -Name "doc layout exposes task list UI" -Text $docsDocItemLayoutText -Needle "Task list"
  Assert-HasLiteral -Name "doc layout exposes code block UI" -Text $docsDocItemLayoutText -Needle "Code block"
  Assert-HasLiteral -Name "doc layout exposes clear formatting UI" -Text $docsDocItemLayoutText -Needle "Clear formatting"
  Assert-HasLiteral -Name "doc layout exposes unlink UI" -Text $docsDocItemLayoutText -Needle "Remove link"
  Assert-HasLiteral -Name "doc layout applies rich editor links" -Text $docsDocItemLayoutText -Needle "setLink({href})"
  Assert-HasLiteral -Name "doc layout applies rich editor images" -Text $docsDocItemLayoutText -Needle "setImage({src, alt:"
  Assert-HasLiteral -Name "doc layout applies task list commands" -Text $docsDocItemLayoutText -Needle "toggleTaskList"
  Assert-HasLiteral -Name "doc layout applies code block commands" -Text $docsDocItemLayoutText -Needle "toggleCodeBlock"
  Assert-HasLiteral -Name "doc layout applies clear formatting commands" -Text $docsDocItemLayoutText -Needle "unsetAllMarks"
  Assert-HasLiteral -Name "doc layout supports deleting table columns" -Text $docsDocItemLayoutText -Needle "deleteColumn"
  Assert-HasLiteral -Name "doc layout supports deleting table rows" -Text $docsDocItemLayoutText -Needle "deleteRow"
  Assert-HasLiteral -Name "doc layout serializes TOC placeholder safely" -Text $docsDocItemLayoutText -Needle "[[docs-tools-toc]]"
  Assert-HasLiteral -Name "doc layout renders Docusaurus admonitions in rich editor" -Text $docsDocItemLayoutText -Needle "DocusaurusAdmonition"
  Assert-HasLiteral -Name "doc layout parses admonition markdown containers" -Text $docsDocItemLayoutText -Needle "markdownTokenizer"
  Assert-HasLiteral -Name "doc layout serializes admonitions back to Docusaurus markdown" -Text $docsDocItemLayoutText -Needle "renderMarkdown"
  Assert-HasLiteral -Name "doc layout renders Mermaid diagrams in edit mode" -Text $docsDocItemLayoutText -Needle "DocusaurusMermaid"
  Assert-HasLiteral -Name "doc layout uses Mermaid renderer for edit previews" -Text $docsDocItemLayoutText -Needle "import('mermaid')"
  Assert-HasLiteral -Name "doc layout blocks advanced mdx with source fallback" -Text $docsDocItemLayoutText -Needle "Source Mode Required"
  Assert-HasLiteral -Name "docs editor api host exposes visibility endpoint" -Text (Get-Content -LiteralPath $docsEditorHostPath -Raw) -Needle '"/api/visibility"'
  $docsEditorHostText = Get-Content -LiteralPath $docsEditorHostPath -Raw
  Assert-HasLiteral -Name "docs editor api host defines shared api version" -Text $docsEditorHostText -Needle '$script:ApiVersion = 2'
  Assert-HasLiteral -Name "docs editor api host advertises authoring api version" -Text $docsEditorHostText -Needle 'authoringApiVersion = $script:ApiVersion'
  Assert-HasLiteral -Name "docs browser QA covers toolbar readability" -Text $docsBrowserQaText -Needle "at least 28x28 px"
  Assert-HasLiteral -Name "docs browser QA covers dedicated structure ordering controls" -Text $docsBrowserQaText -Needle "Use the Site Settings structure ordering controls"
  Assert-HasLiteral -Name "docs browser QA covers hide from site visibility" -Text $docsBrowserQaText -Needle "Hide the temporary page from the site"
  Assert-HasLiteral -Name "docs browser QA covers rich insert saves" -Text $docsBrowserQaText -Needle "save and reload to confirm"

  Step "Docs dependency contract"
  $docsPackage = Get-Content -LiteralPath $docsPackageJsonPath -Raw | ConvertFrom-Json
  $packageDependencyNames = @($docsPackage.dependencies.PSObject.Properties.Name)
  $lockDependencyNames = Get-NpmLockRootDependencyNames -LockPath $docsPackageLockPath
  Assert-Condition -Name "docs package declares tiptap react dependency" -Condition ($packageDependencyNames -contains "@tiptap/react") -PassDetail "@tiptap/react declared" -FailDetail "@tiptap/react missing from package.json dependencies"
  Assert-Condition -Name "docs package declares tiptap markdown dependency" -Condition ($packageDependencyNames -contains "@tiptap/markdown") -PassDetail "@tiptap/markdown declared" -FailDetail "@tiptap/markdown missing from package.json dependencies"
  Assert-Condition -Name "docs package declares tiptap table dependency" -Condition ($packageDependencyNames -contains "@tiptap/extension-table") -PassDetail "@tiptap/extension-table declared" -FailDetail "@tiptap/extension-table missing from package.json dependencies"
  Assert-Condition -Name "docs package declares tiptap starter-kit dependency" -Condition ($packageDependencyNames -contains "@tiptap/starter-kit") -PassDetail "@tiptap/starter-kit declared" -FailDetail "@tiptap/starter-kit missing from package.json dependencies"
  Assert-Condition -Name "docs package declares tiptap underline dependency" -Condition ($packageDependencyNames -contains "@tiptap/extension-underline") -PassDetail "@tiptap/extension-underline declared" -FailDetail "@tiptap/extension-underline missing from package.json dependencies"
  Assert-Condition -Name "docs package declares tiptap text-align dependency" -Condition ($packageDependencyNames -contains "@tiptap/extension-text-align") -PassDetail "@tiptap/extension-text-align declared" -FailDetail "@tiptap/extension-text-align missing from package.json dependencies"
  Assert-Condition -Name "docs package declares tiptap link dependency" -Condition ($packageDependencyNames -contains "@tiptap/extension-link") -PassDetail "@tiptap/extension-link declared" -FailDetail "@tiptap/extension-link missing from package.json dependencies"
  Assert-Condition -Name "docs package declares tiptap image dependency" -Condition ($packageDependencyNames -contains "@tiptap/extension-image") -PassDetail "@tiptap/extension-image declared" -FailDetail "@tiptap/extension-image missing from package.json dependencies"
  Assert-Condition -Name "docs package declares lucide dependency" -Condition ($packageDependencyNames -contains "lucide") -PassDetail "lucide declared" -FailDetail "lucide missing from package.json dependencies"
  Assert-Condition -Name "docs package declares mermaid dependency" -Condition ($packageDependencyNames -contains "mermaid") -PassDetail "mermaid declared" -FailDetail "mermaid missing from package.json dependencies"
  Assert-Condition -Name "docs package declares Docusaurus mermaid theme" -Condition ($packageDependencyNames -contains "@docusaurus/theme-mermaid") -PassDetail "@docusaurus/theme-mermaid declared" -FailDetail "@docusaurus/theme-mermaid missing from package.json dependencies"
  Assert-Condition -Name "docs lockfile contains tiptap react dependency" -Condition ($lockDependencyNames -contains "@tiptap/react") -PassDetail "@tiptap/react locked" -FailDetail "@tiptap/react missing from lockfile root dependencies"
  Assert-Condition -Name "docs lockfile contains tiptap markdown dependency" -Condition ($lockDependencyNames -contains "@tiptap/markdown") -PassDetail "@tiptap/markdown locked" -FailDetail "@tiptap/markdown missing from lockfile root dependencies"
  Assert-Condition -Name "docs lockfile contains tiptap table dependency" -Condition ($lockDependencyNames -contains "@tiptap/extension-table") -PassDetail "@tiptap/extension-table locked" -FailDetail "@tiptap/extension-table missing from lockfile root dependencies"
  Assert-Condition -Name "docs lockfile contains tiptap starter-kit dependency" -Condition ($lockDependencyNames -contains "@tiptap/starter-kit") -PassDetail "@tiptap/starter-kit locked" -FailDetail "@tiptap/starter-kit missing from lockfile root dependencies"
  Assert-Condition -Name "docs lockfile contains tiptap underline dependency" -Condition ($lockDependencyNames -contains "@tiptap/extension-underline") -PassDetail "@tiptap/extension-underline locked" -FailDetail "@tiptap/extension-underline missing from lockfile root dependencies"
  Assert-Condition -Name "docs lockfile contains tiptap text-align dependency" -Condition ($lockDependencyNames -contains "@tiptap/extension-text-align") -PassDetail "@tiptap/extension-text-align locked" -FailDetail "@tiptap/extension-text-align missing from lockfile root dependencies"
  Assert-Condition -Name "docs lockfile contains tiptap link dependency" -Condition ($lockDependencyNames -contains "@tiptap/extension-link") -PassDetail "@tiptap/extension-link locked" -FailDetail "@tiptap/extension-link missing from lockfile root dependencies"
  Assert-Condition -Name "docs lockfile contains tiptap image dependency" -Condition ($lockDependencyNames -contains "@tiptap/extension-image") -PassDetail "@tiptap/extension-image locked" -FailDetail "@tiptap/extension-image missing from lockfile root dependencies"
  Assert-Condition -Name "docs lockfile contains lucide dependency" -Condition ($lockDependencyNames -contains "lucide") -PassDetail "lucide locked" -FailDetail "lucide missing from lockfile root dependencies"
  Assert-Condition -Name "docs lockfile contains mermaid dependency" -Condition ($lockDependencyNames -contains "mermaid") -PassDetail "mermaid locked" -FailDetail "mermaid missing from lockfile root dependencies"
  Assert-Condition -Name "docs lockfile contains Docusaurus mermaid theme" -Condition ($lockDependencyNames -contains "@docusaurus/theme-mermaid") -PassDetail "@docusaurus/theme-mermaid locked" -FailDetail "@docusaurus/theme-mermaid missing from lockfile root dependencies"

  Step "Website theme catalog contract"
  $themeCatalog = (Get-Content -LiteralPath $themeCatalogPath -Raw | ConvertFrom-Json)
  $themeIds = @($themeCatalog.themes | ForEach-Object { [string]$_.id })
  $expectedThemeIds = @(
    "neutral", "graphite", "ocean", "forest", "amber", "violet",
    "cobalt", "teal", "jade", "indigo", "crimson", "rose", "copper", "slate"
  )
  Assert-Condition -Name "theme catalog default remains neutral" -Condition ($themeCatalog.defaultTheme -eq "neutral") -PassDetail "default=neutral" -FailDetail "default theme is '$($themeCatalog.defaultTheme)'"
  Assert-Condition -Name "theme catalog exposes 14 presets" -Condition ($themeIds.Count -eq 14) -PassDetail "count=14" -FailDetail "count=$($themeIds.Count)"
  foreach ($expectedId in $expectedThemeIds) {
    Assert-Condition -Name "theme catalog includes $expectedId" -Condition ($themeIds -contains $expectedId) -PassDetail "present" -FailDetail "missing"
  }
  foreach ($theme in @($themeCatalog.themes)) {
    Assert-Condition -Name "theme $($theme.id) has logo path metadata" -Condition (-not [string]::IsNullOrWhiteSpace([string]$theme.logoPath)) -PassDetail "logoPath present" -FailDetail "logoPath missing"
    Assert-Condition -Name "theme $($theme.id) has favicon path metadata" -Condition (-not [string]::IsNullOrWhiteSpace([string]$theme.faviconPath)) -PassDetail "faviconPath present" -FailDetail "faviconPath missing"
    Assert-Condition -Name "theme $($theme.id) has social card path metadata" -Condition (-not [string]::IsNullOrWhiteSpace([string]$theme.socialCardPath)) -PassDetail "socialCardPath present" -FailDetail "socialCardPath missing"
    $cssPath = Join-Path $repoRoot ("payload\website\" + ((($theme.cssPath -as [string]) -replace '^website/', '') -replace "/", "\"))
    $logoPath = Join-Path $repoRoot ("payload\website\static\" + (($theme.logoPath -as [string]) -replace "/", "\"))
    $faviconPath = Join-Path $repoRoot ("payload\website\static\" + (($theme.faviconPath -as [string]) -replace "/", "\"))
    $socialCardPath = Join-Path $repoRoot ("payload\website\static\" + (($theme.socialCardPath -as [string]) -replace "/", "\"))
    Assert-Condition -Name "theme $($theme.id) css asset exists" -Condition (Test-Path -LiteralPath $cssPath -PathType Leaf) -PassDetail "css present" -FailDetail "missing: $cssPath"
    Assert-Condition -Name "theme $($theme.id) logo asset exists" -Condition (Test-Path -LiteralPath $logoPath -PathType Leaf) -PassDetail "logo present" -FailDetail "missing: $logoPath"
    Assert-Condition -Name "theme $($theme.id) favicon asset exists" -Condition (Test-Path -LiteralPath $faviconPath -PathType Leaf) -PassDetail "favicon present" -FailDetail "missing: $faviconPath"
    Assert-Condition -Name "theme $($theme.id) social card asset exists" -Condition (Test-Path -LiteralPath $socialCardPath -PathType Leaf) -PassDetail "social card present" -FailDetail "missing: $socialCardPath"
  }

  Step "Publish script contract"
  $publishScriptText = Get-Content -LiteralPath $publishScriptPath -Raw
  Assert-HasLiteral -Name "publish script validates .NET SDK list" -Text $publishScriptText -Needle "--list-sdks"
  Assert-HasLiteral -Name "publish script enforces .NET 10 SDK" -Text $publishScriptText -Needle "^10\."
  Assert-HasLiteral -Name "publish script artifact naming convention" -Text $publishScriptText -Needle "UEToolSuiteInstaller-{0}-{1}.exe"
  Assert-HasLiteral -Name "publish script timestamp signing support" -Text $publishScriptText -Needle "/tr $TimestampUrl"
  Assert-HasLiteral -Name "publish script supports thumbprint signing" -Text $publishScriptText -Needle "CertificateThumbprint"
  Assert-HasLiteral -Name "publish script supports PFX signing" -Text $publishScriptText -Needle "CertificatePath"

  Step "Release workflow gate contract"
  $workflowText = Get-Content -LiteralPath $workflowPath -Raw
  Assert-HasLiteral -Name "workflow runs non-mutating full suite" -Text $workflowText -Needle "Tests/Run-UEToolSuiteTests.ps1 -FailFast"
  Assert-HasLiteral -Name "workflow runs mutating ue-sync suite" -Text $workflowText -Needle "ue-sync-automated"
  Assert-HasLiteral -Name "workflow runs mutating binary-guard suite" -Text $workflowText -Needle "binary-guard-fixes"
  Assert-HasLiteral -Name "workflow publishes installer via publish script" -Text $workflowText -Needle "Scripts/Publish-InstallerExe.ps1"
  Assert-HasLiteral -Name "workflow uploads versioned artifact name" -Text $workflowText -Needle 'UEToolSuiteInstaller-${{ steps.version.outputs.value }}-win-x64.exe'

  Step "Summary"
  Write-Log ("PASS={0} FAIL={1}" -f $script:PassCount, $script:FailCount) Cyan
  if ($script:FailCount -eq 0) {
    Write-Log "Packaging contract tests passed." Green
  }
  else {
    Write-Log "Packaging contract tests failed." Red
    exit 1
  }
}
catch {
  if ($_.Exception.Message -ne "FAILFAST") {
    Write-Log "[FATAL] $($_.Exception.Message)" Red
  }
  Write-Log ("PASS={0} FAIL={1}" -f $script:PassCount, $script:FailCount) Cyan
  if ($script:FailCount -eq 0) { $script:FailCount = 1 }
  exit 1
}
finally {
  Write-Log ""
  Write-Log "Log saved: $logPath" Cyan
}
