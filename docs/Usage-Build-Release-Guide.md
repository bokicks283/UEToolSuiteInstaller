# UE Tool Suite Installer Guide

This repository is the source of truth for the portable Unreal Engine 5 tool suite installer.

Use this guide when you want to:

- Install the tool suite into a UE 5 project.
- Understand how this installer repo is structured.
- Build the public Windows installer executable.
- Publish a signed GitHub Release.
- Maintain the bundled payload over time.

## End-User Install Flow

The public release artifact is:

```text
UEToolSuiteInstaller-<version>-win-x64.exe
```

Users do not need to clone this repo.

1. Install prerequisites:
   - Git for Windows
   - Git LFS
   - PowerShell 7
   - Unreal Engine 5.x
2. Download the latest `UEToolSuiteInstaller-<version>-win-x64.exe` from GitHub Releases.
3. Run the exe.
4. Click `Browse...`.
5. Choose the target project's `.uproject` file.
6. Keep the default options for normal installs:
   - Run repo initialization after install.
   - Skip Git LFS pull during init.
   - Skip the first Unreal sync during init.
   - Install the managed PowerShell alias block.
   - Keep backups enabled.
7. Click `Install`.
8. Watch installer progress in the progress bar. Turn on `Show terminal output` only when you want detailed runtime logs.

The installer writes backups under:

```text
.ue-tools-installer-backups/<timestamp>/
```

Backups mirror original relative paths. For example, a backup of `Scripts/UETools/UEToolSuite.Unreal.psm1` is restored by copying it from the timestamp folder back to `Scripts/UETools/UEToolSuite.Unreal.psm1`.

## What Gets Installed

The installer copies managed paths from `payload/` into the selected UE project:

- `.githooks/`
- managed `.gitattributes` block
- managed `.gitignore` block
- `Scripts/UETools/UEToolSuite.Init.psm1`
- `Scripts/ue-tools.ps1`
- `Scripts/git-hooks/`
- `Scripts/git-tools/`
- `Scripts/UETools/`
- `Scripts/Unreal/ProjectContext.ps1`
- `Scripts/UETools/UEToolSuite.Unreal.psm1`
- optional `Scripts/Docs/`
- optional `Scripts/Tests/`
- generic `Docs/`
- `website/`

Root `.gitattributes` and `.gitignore` are not replaced wholesale. The installer updates the tool-suite marker blocks and preserves project-specific content outside those blocks.

Managed directories are merged in place when they already exist. The installer replaces payload-owned files under those directories and backs up the replaced files, but it does not delete target-only files that are not in `payload/`. This protects files such as `Docs/AI/Project-Context.md`, local docs pages, and project-specific tests in repos that already have a similar tool layout.

## How This Repo Works

Important paths:

```text
Install-UEToolSuite.ps1                    CLI installer/updater engine
payload/                                   files installed into target UE projects
payload/Scripts/UETools/UEToolSuite.Init.psm1      target repo bootstrap module
payload/Scripts/ue-tools.ps1               unified CLI dispatcher entrypoint
src/UEToolSuiteInstaller.Gui/              public Windows GUI launcher
Scripts/Publish-InstallerExe.ps1           local/CI publish script
Tests/Test-Install-UEToolSuite.ps1         installer regression suite
.github/workflows/release.yml              tag-based GitHub Release workflow
docs/                                      maintainer documentation for this repo
```

The GUI executable does not reimplement the installer. It bundles `Install-UEToolSuite.ps1` and `payload/`, opens a `.uproject` picker, then runs the existing PowerShell installer with the selected project path and options.

When `Run repo initialization after install` is enabled (default), the GUI passes `-RunInit -InitNonInteractive` so init runs without interactive prompts. This prevents hidden-prompt hangs in packaged exe runs and keeps behavior deterministic for clean installs.

This keeps the behavior auditable: the CLI installer and GUI installer use the same install engine.

## Local Development

Run the installer test suite after any payload or installer change:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File Tests/Test-Install-UEToolSuite.ps1
```

Run a parser check across PowerShell files:

```powershell
$failed = $false
$files = Get-ChildItem -Path . -Recurse -Filter *.ps1 -File |
  Where-Object { $_.FullName -notmatch '\\payload\\website\\node_modules\\|\\payload\\website\\build\\|\\payload\\website\\.docusaurus\\|\\src\\.*\\bin\\|\\src\\.*\\obj\\' }

foreach ($file in $files) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) {
    $failed = $true
    Write-Host "PARSER ERRORS: $($file.FullName)"
    $errors | ForEach-Object { Write-Host $_.Message }
  }
}

if ($failed) { exit 1 }
```

Run the whitespace diff check:

```powershell
git add -N .
git diff --check
```

## Build The Public Installer Locally

Install the .NET 10 SDK:

```powershell
winget install Microsoft.DotNet.SDK.10
```

Publish the unsigned exe:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\Publish-InstallerExe.ps1 -Version 0.1.0
```

Output:

```text
dist/UEToolSuiteInstaller-0.1.0-win-x64.exe
```

The exe is self-contained and includes the .NET runtime, `Install-UEToolSuite.ps1`, and `payload/`. Users still need PowerShell 7 installed because the installed UE tools run on `pwsh`.

## Publish A New Version

Recommended release flow:

1. Update `payload/`, installer code, GUI code, and docs as needed.
2. Run:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File Tests/Run-UEToolSuiteTests.ps1 -FailFast
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& './Tests/Run-UEToolSuiteTests.ps1' -IncludeExclusive -Name @('ue-sync-automated','binary-guard-fixes') -FailFast"
git add -N .
git diff --check
```

3. Commit the changes.
4. Create a version tag:

```powershell
git tag v0.1.0
git push origin v0.1.0
```

5. The GitHub Actions workflow builds the exe and creates a GitHub Release for `v*` tags.
6. Download the release artifact on a clean Windows machine and run a smoke install into a scratch UE 5 project.

## GitHub Release Signing

For certificate procurement and operations end-to-end, see:
- [EXE Code-Signing Certificate Guide](./EXE-Code-Signing-Certificate-Guide.md)

The workflow supports PFX-based signing with these repository secrets:

```text
WINDOWS_CODESIGN_PFX_BASE64
WINDOWS_CODESIGN_PFX_PASSWORD
```

Add them in GitHub:

```text
Repository -> Settings -> Secrets and variables -> Actions -> New repository secret
```

Create `WINDOWS_CODESIGN_PFX_BASE64` from a PFX file:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\secure\codesign.pfx")) |
  Set-Content -LiteralPath C:\secure\codesign.pfx.base64 -NoNewline
```

Then paste the contents of `codesign.pfx.base64` into the GitHub secret.

Base64 is only a transport encoding. Treat the encoded value like the certificate itself.

## Local Signing

Sign with a certificate in your current user's certificate store:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\Publish-InstallerExe.ps1 `
  -Version 0.1.0 `
  -CertificateThumbprint <thumbprint>
```

Sign with a PFX file:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\Publish-InstallerExe.ps1 `
  -Version 0.1.0 `
  -CertificatePath C:\secure\codesign.pfx `
  -CertificatePassword "<password>"
```

The publish script uses SHA-256 and timestamps signatures with:

```text
http://timestamp.digicert.com
```

## Public Code-Signing Guidance

For public releases, use one of these:

- Microsoft Artifact Signing / Trusted Signing, if you are eligible in your region and account type.
- A standard OV code-signing certificate from a public CA.
- An EV code-signing certificate if you want the strongest Windows trust/reputation posture.

A self-signed certificate is useful for local signing tests only. It will not make downloads trusted by other people's Windows machines, and it will not establish SmartScreen reputation.

Expect SmartScreen behavior to be reputation-based. Signing improves publisher identity and tamper detection; it does not guarantee that a brand-new public download will avoid every warning immediately.

## Maintaining The Payload

Edit `payload/` directly. Do not copy from another project repo.

Keep these boundaries:

- Installer and updater logic stays in this repo.
- Installed UE projects receive only the usable payload files.
- Project-specific game docs, private context, generated output, `node_modules`, Docusaurus build output, and local test logs do not belong in payload.

After payload changes, run the installer tests and verify that a scratch UE project receives only the intended managed paths.

