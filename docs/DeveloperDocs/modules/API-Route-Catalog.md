# API Route Catalog

All routes below are implemented in `payload/Scripts/UETools/DocsEditorApiHost.ps1` and dispatched by `Invoke-EditorApiRequest`.

## Health and read routes

| Method | Path | Purpose | Request fields | Response shape | Files read/written | Frontend callers | Tests |
|---|---|---|---|---|---|---|---|
| `GET` | `/health` | Runtime identity and capability probe | none | `ok`, `applicationId`, `apiVersion`, `processId`, `repoRoot`, `docsRoot`, `startedAt`, `modulePath`, `scriptPath`, `capabilities.*` | reads runtime state only | `probeApiBase` | background/runtime discovery cases |
| `GET` | `/api/tree` | Return visible docs tree for root, domain, or sidebar | query: `root`, `sidebarId`, `general` | `ok`, `tree` | reads Docs tree and metadata | `SiteAdminPanel` | Case `1g`, domain reorder/move cases |
| `GET` | `/api/domains` | Return domain definitions | none | `ok`, `domains` | reads `Docs/_domains.json` and related metadata | `SiteAdminPanel` | domain cases |
| `GET` | `/api/content` | Load editable document content | query: `path` | `ok`, `content` with `path`, `content`, `hash`, `modifiedUtc` | reads markdown file | `DocItem/Layout/index.tsx` | Case `1g` |
| `GET` | `/api/site/config` | Return current theme/branding/override config | none | `ok`, `config` | reads site config inputs | `SiteAdminPanel` | site settings coverage |
| `GET` | `/api/site/theme-catalog` | Return theme preset catalog | none | `ok`, `catalog` | reads `theme-catalog.json` | `SiteAdminPanel` | Case `1d` indirectly |

## Content and structure mutation routes

| Method | Path | Purpose | Request fields | Response shape | Files changed | Frontend callers | Tests |
|---|---|---|---|---|---|---|---|
| `POST` | `/api/content` | Save markdown content with optimistic concurrency | `path`, `content`, `expectedHash` | `ok`, `result` | target markdown file | `DocItem/Layout/index.tsx` | Case `1g` |
| `POST` | `/api/create/page` | Create a docs page | `domainPath`, `sectionPath`, `pageName`, `title` | `ok`, `result` | markdown file and possibly metadata | `SiteAdminPanel` | create-page/new-page cases |
| `POST` | `/api/create/section` | Create a section | `domainPath`, `parentPath`, `sectionName`, `title`, `linkType`, `generatedIndexTitle`, `generatedIndexSlug`, `generatedIndexDescription`, `displayedSidebar` | `ok`, `result` | directory, `_category_.json`, optional landing page | `SiteAdminPanel` | create-section/new-section cases |
| `POST` | `/api/create/domain` | Create a domain and optional landing content | `domainName`, `title`, `description`, `createLandingPage` | `ok`, `result` | `Docs/_domains.json`, Docs files | `SiteAdminPanel` | domain move/create coverage |
| `POST` | `/api/move` | Move page or section, including cross-domain cases | `sourcePath`, `destinationDomainPath`, `destinationParentPath`, `insertIndex`, `newName` | `ok`, `result` | Docs tree, domain metadata, front matter | `SiteAdminPanel` | Cases `1h`, `1i`, `1ii` |
| `POST` | `/api/rename` | Rename page or section | `sourcePath`, `newName` | `ok`, `result` | Docs tree and affected references | `SiteAdminPanel` | rename coverage in structure scenarios |
| `POST` | `/api/node/metadata` | Update title/label metadata | `path`, `title`, `label` | `ok`, `result` | front matter or `_category_.json` | `SiteAdminPanel` | metadata coverage |
| `POST` | `/api/reorder` | Reassign order/position | `targetPath`, `position` | `ok`, `result` | front matter or `_category_.json` positions | `SiteAdminPanel` | Case `1g`, `2d`, `2e`, `1ii` |
| `POST` | `/api/delete` | Delete page or section | `path` | `ok`, `result` | Docs files/directories | `SiteAdminPanel` | delete coverage |
| `POST` | `/api/visibility` | Hide or show page/section landing doc | `path`, `hidden` | `ok`, `result` | front matter `unlisted` state | `DocItem/Layout`, `SiteAdminPanel` | Case `3f` |

## Domain and site-setting routes

| Method | Path | Purpose | Request fields | Response shape | Files changed | Frontend callers | Tests |
|---|---|---|---|---|---|---|---|
| `POST` | `/api/domains/reorder` | Move domain order up/down | `domainPath`, `direction` | `ok`, `result` | `Docs/_domains.json` | `SiteAdminPanel` | domain reorder coverage |
| `POST` | `/api/domains/update` | Rename/update a domain | `domainPath`, `label`, `newPath`, `showLandingInSidebar` | `ok`, `result` | `Docs/_domains.json`, owned Docs paths | `SiteAdminPanel` | domain rename/update coverage |
| `POST` | `/api/domains/delete` | Remove a domain definition | `domainPath` | `ok`, `result` | `Docs/_domains.json`, possibly related metadata | `SiteAdminPanel` | domain delete coverage |
| `POST` | `/api/site/theme` | Apply theme preset from API | route-specific body accepted by `Apply-SiteThemeFromApiBody` | `ok`, `result` | website theme files | `SiteAdminPanel` | theme apply coverage |
| `POST` | `/api/site/branding` | Apply logo/branding changes | route-specific body accepted by `Apply-SiteBrandingFromApiBody` | `ok`, `result` | website branding files | `SiteAdminPanel` | branding coverage |
| `POST` | `/api/site/overrides` | Apply site override policy changes | route-specific body accepted by `Apply-SiteOverridesFromApiBody` | `ok`, `result` | site override files/config | `SiteAdminPanel` | override coverage |

## Notes

- Route examples above are examples, not a formal versioned schema.
- For `/api/site/theme`, `/api/site/branding`, and `/api/site/overrides`, this documentation pass confirmed the handler entrypoints but did not fully line-trace every accepted field. Those remain partially documented in [25-Open-Questions.md](../25-Open-Questions.md).
