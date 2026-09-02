# Repository Map

## Authored tree

```text
UEToolSuiteInstaller/
├── .github/
│   ├── dependabot.yml
│   └── workflows/
├── docs/
│   ├── agent/
│   └── *.md
├── payload/
│   ├── Docs/
│   ├── Scripts/
│   │   ├── Docs/
│   │   ├── Tests/
│   │   ├── UETools/
│   │   ├── Unreal/
│   │   └── git-hooks/
│   ├── website/
│   │   ├── src/
│   │   ├── static/
│   │   └── theme-presets/
│   ├── ue-tool-suite.manifest.json
│   ├── docs-managed-file-index.json
│   └── website-managed-file-index.json
├── Scripts/
│   ├── New-TestCodeSigningCertificate.ps1
│   └── Publish-InstallerExe.ps1
├── src/
│   └── UEToolSuiteInstaller.Gui/
├── Tests/
├── Install-UEToolSuite.ps1
├── MAINTAINER_GUIDE.md
├── README.md
└── PLANS.md
```

## Top-level directories

| Path | Purpose | Contains | Read by | Written by | Installed into target repo | Safe to edit directly |
|---|---|---|---|---|---|---|
| `.github/` | dependency automation | workflow YAML and Dependabot configuration | GitHub | maintainers | No | Yes |
| `docs/` | repo-maintainer and agent guidance | authored markdown | maintainers, agents | maintainers | No | Yes |
| `payload/` | installable suite source | PowerShell, docs, site, manifests | installer, tests, publish | maintainers | Yes | Yes |
| `Scripts/` | root build/sign/publish helpers | PowerShell | maintainers | maintainers | No | Yes |
| `src/` | GUI executable source | C# / csproj | publish script, dotnet | maintainers | Built artifact only | Yes |
| `Tests/` | installer-level suites and runner | PowerShell | maintainers, CI | test runs emit `*Results/` | No | Yes |
| `dist/` | publish output | generated artifacts | local release publisher, maintainers | publish script | No | No |
| `codex-findings/` | prior analysis notes | markdown | maintainers, agents | maintainers | No | Yes |

## Nested payload directories

| Path | Purpose | Installed | Direct editing safe | Notes |
|---|---|---|---|---|
| `payload/Docs/` | default docs content and metadata | Yes | Yes | Installer treats docs smart-update differently from raw overwrite |
| `payload/Scripts/UETools/` | nested PowerShell modules | Yes | Yes | Main command and docs runtime logic live here |
| `payload/Scripts/Tests/` | source-repository validation suites | No | Yes | Used by maintainers and CI; excluded from published installers |
| `payload/Scripts/Docs/VSCodeBridge/` | optional docs bridge | Yes | Yes | Installed by docs/init flows when requested |
| `payload/Scripts/git-hooks/` | hook setup and validation | Yes | Yes | Works with `.githooks/` payload path |
| `payload/Scripts/Unreal/` | Unreal project context helper | Yes | Yes | Used by Unreal/build flows |
| `payload/website/src/` | Docusaurus/React source | Yes | Yes | Source, not generated output |
| `payload/website/static/` | static assets and runtime descriptor location | Yes | Yes | Runtime descriptor is generated into `static/ue-tools/editor-runtime.json` in installed repos |
| `payload/website/theme-presets/` | theme catalog and preset CSS | Yes | Yes | GUI and installer both consume this catalog |

## Files that define install contracts

- `payload/ue-tool-suite.manifest.json`
- `payload/docs-managed-file-index.json`
- `payload/website-managed-file-index.json`
- `src/UEToolSuiteInstaller.Gui/UEToolSuiteInstaller.Gui.csproj`
- `Tests/Test-PackagingContracts.ps1`

## Do not inventory as authored source

The repository instructions explicitly exclude broad inspection or documentation of generated content such as:

- `payload/website/node_modules/**`
- `payload/website/.docusaurus/**`
- `payload/website/build/**`
- `payload/website/build-debug/**`
- `dist/**`
- test result directories

Those paths matter as outputs or install artifacts, but not as authored source-of-truth.
