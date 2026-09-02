# Configuration and State

## Important configuration and state files

| File | Producer | Consumer | Generated | Stale risk |
|---|---|---|---|---|
| `payload/ue-tool-suite.manifest.json` | maintainers | installer, packaging tests | No | low |
| `payload/docs-managed-file-index.json` | maintainers | installer, packaging tests | No | medium if payload changes without regen |
| `payload/website-managed-file-index.json` | maintainers | installer, packaging tests | No | medium if payload changes without regen |
| `payload/website/package.json` | maintainers | npm, init, dependency CI | No | medium |
| `payload/website/package-lock.json` | maintainers / npm | init, dependency CI | No | medium |
| `payload/website/docusaurus.config.ts` | maintainers | Docusaurus, packaging tests | No | medium |
| `payload/website/sidebars.ts` | maintainers | Docusaurus | No | low |
| `payload/Docs/_domains.json` | maintainers or authoring API | `domainCatalog.ts`, API, tests | No in source, mutable in installed repo | medium |
| `Docs/**/_category_.json` | maintainers or authoring API | `domainCatalog.ts`, API | No in source, mutable in installed repo | medium |
| page front matter | maintainers or authoring API | Docusaurus, API, frontend | No in source, mutable in installed repo | medium |
| `.ue-tools/state/docs-managed-ledger.json` | installer | installer | Yes | medium |
| `.ue-tools/state/website-managed-ledger.json` | installer | installer | Yes | medium |
| `.ue-tools/state/docs-server.json` | docs runtime | docs status/stop | Yes | high |
| `website/static/ue-tools/editor-runtime.json` | docs runtime | frontend discovery | Yes | high |
| `website/.ue-tools/ownership.json` | installer / docs theme helpers | theme/site adoption logic | Yes | medium |

## Environment variables observed in source or tests

Confirmed notable variables:

- `UE_TOOLS_DOCS_EDITOR_DEBUG`
- `UE_TOOLS_ENABLE_BACKGROUND_DOCS_TESTS`
- `UE_TOOLS_DOCS_RUNTIME_NO_AUTORUN`
- `UE_TOOLS_INIT_RUNTIME_NO_AUTORUN`
- `UE_TOOLS_DOCS_START_CONTINUE`
- `INIT_REPO_TOOL_READINESS_*` test variables
- local release signing inputs: certificate-store thumbprint or external PFX path/password passed to `Scripts/Publish-GitHubRelease.ps1`

## Lifecycle notes

- runtime descriptors and server state are disposable and may become stale
- managed ledgers are durable across installer reruns
- package metadata is source-controlled
- build artifacts are generated but are part of the current website packaging contract

## Security relevance

- runtime descriptor files influence which local API the frontend probes
- ledgers influence what the installer may overwrite or remove
- website ownership markers affect whether theme/site commands are permitted without explicit adoption

## See also

- [modules/Configuration-Catalog.md](modules/Configuration-Catalog.md)
- [10-Process-Lifecycle.md](10-Process-Lifecycle.md)
- [23-Security-and-Trust-Boundaries.md](23-Security-and-Trust-Boundaries.md)
