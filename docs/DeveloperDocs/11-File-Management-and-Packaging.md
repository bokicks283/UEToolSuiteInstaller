# File Management and Packaging

## Payload layout

The payload contract is declared by:

- `payload/ue-tool-suite.manifest.json`
- `payload/docs-managed-file-index.json`
- `payload/website-managed-file-index.json`

The manifest separates:

- `managedTextItems`
- `managedItems.base`
- `managedItems.tests`
- `managedItems.docs`
- `managedItems.docsTools`
- `managedItems.website`
- optional categories such as `aiTools`, `artTools`, `codingStandards`
- `legacyCleanupPaths`

## Managed-file ownership model

| Asset type | Tracking model | Notes |
|---|---|---|
| root text files | marker-managed blocks | preserves surrounding project content |
| docs defaults | docs managed-file index + docs ledger | smart-update and candidate model |
| website files | website managed-file index + website ledger | includes built site assets in the current checkout |
| retired payload files | legacy cleanup + obsolete-ledger cleanup | removed only when identified as managed/retired |

## Generated assets

There are two distinct generated-asset concerns:

1. repo-local generated output, such as `payload/website/build/**`, which is not the authored source but is part of the current website packaging contract
2. installed-project generated/runtime state such as `website/build/**` and `.ue-tools/state/**`

The current checkout treats built website assets as part of managed website installation, not just as an optional local build byproduct. This is enforced by packaging-contract tests and installer cases around stale build cleanup.

## Source-to-served bundle path

1. `payload/website/src/**` and static assets define the authored website.
2. Docusaurus build emits `payload/website/build/**`.
3. The installer copies managed website files into the target repo, including tracked build artifacts in the current contract.
4. `ue-tools docs start` serves the website from the target repo `website/` directory.

## Stale bundle prevention model

Confirmed prevention mechanisms in the current checkout:

- managed website ledger tracks installed managed website files
- website build assets are included in the managed website index
- obsolete managed build files can be removed on update
- installer tests explicitly cover stale build cleanup and build-directory refresh paths

This is the current source-backed answer to “why do stale frontend bundles not persist forever?”

## Files users may safely modify

This depends on ownership mode and install mode.

Safe or preserve-first examples:

- project-specific docs outside tracked defaults, depending on update path
- explicit website project-override paths
- unmanaged website content when the site is still preserved instead of adopted

Unsafe to assume project-owned:

- files listed in managed-file indexes
- files restored or replaced by installer-ledger rules
- marker-managed blocks in root `.gitattributes` and `.gitignore`

## Packaging and release files

- GUI project: `src/UEToolSuiteInstaller.Gui/UEToolSuiteInstaller.Gui.csproj`
- GUI source: `src/UEToolSuiteInstaller.Gui/Program.cs`
- publish script: `Scripts/Publish-InstallerExe.ps1`
- release workflow: `.github/workflows/release.yml`
- dependency validation workflow: `.github/workflows/dependency-pr-validation.yml`

## Source/install parity verification

Use [24-Deployment-Verification.md](24-Deployment-Verification.md) for exact procedures. The most important parity boundaries are:

- authored payload vs managed-file indexes
- authored payload vs installed source files
- authored build output vs installed build files
- installed build files vs currently served bundle
