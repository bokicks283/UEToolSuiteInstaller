# Domains, Sidebars, and Navigation

## Domain representation

The primary authored domain model lives in `Docs/_domains.json` and is normalized by `getDocsDomainCatalog()` in `payload/website/domainCatalog.ts:598`.

Confirmed domain fields in the current source:

- `key`
- `dirName`
- `sidebarId`
- `label`
- `position`
- `landingDoc`
- `description`
- `showLandingInSidebar`
- `ownedRoots`
- `ownedDocs`
- `catchAll`

## Sidebar and navbar generation

- sidebars are built by `buildDocsSidebarsConfig()` in `domainCatalog.ts:812`
- `payload/website/sidebars.ts` is a thin shell that exports that generated config
- navbar items are synthesized in `payload/website/docusaurus.config.ts` from `docsDomainCatalog`

## Ordering and normalization rules

Confirmed behaviors:

- path normalization is slash-insensitive and trims leading/trailing separators
- directory positions come from `_category_.json`
- page positions come from front matter `sidebar_position`
- hidden docs (`unlisted`) are filtered from sidebar generation
- section landing docs are handled specially to avoid duplicate visible children

## Workflow traces

### 1. Create a domain

- frontend: Site Settings
- API route: `POST /api/create/domain`
- handler: `Create-DocsDomain`
- file effects: `Docs/_domains.json`, possible landing-doc files and metadata

### 2. Move a section into or between domains

- frontend drafts mutation in `SiteAdminPanel.tsx`
- API route: `POST /api/move`
- handler: `Move-DocsNode`
- side effects: filesystem move, doc id and link repair, landing/sidebar metadata updates, invalidation

### 3. Move a section to root

- same route as general move
- ownership changes are based on destination domain path and destination parent path

### 4. Rename a domain

- API route: `POST /api/domains/update`
- handler: `Update-DocsDomain`
- side effects: `_domains.json` update and possibly path/landing metadata changes

### 5. Delete a domain

- API route: `POST /api/domains/delete`
- handler: `Remove-DocsDomain`
- side effects: remove ownership entry and related state; exact file deletion policy is route-specific

### 6. Hide or show a document

- API route: `POST /api/visibility`
- handler: `Set-DocsPageVisibility`
- effect: toggle `unlisted` front matter on pages or landing docs

### 7. Rebuild navigation

- authored synthesis: `domainCatalog.ts`
- live docs checks: `ue-tools docs check`
- authoring UI refresh path: structure-change broadcast events and tree reloads

## Atomicity notes

| Workflow | Current status |
|---|---|
| page save with `expectedHash` | partially guarded, route-local |
| section/domain move | partially atomic with route-specific validation/rollback logic |
| sidebar/nav regeneration | derived, not a committed transaction |
| visibility toggle | direct mutation of target doc front matter |
| runtime frontend refresh | non-atomic, event/poll driven |

## Before/after file-state examples

Common authored files involved in navigation changes:

- `Docs/_domains.json`
- `Docs/<Section>/_category_.json`
- landing docs such as `README.md`
- page front matter with `slug`, `sidebar_position`, `unlisted`

## Source references

- `payload/website/domainCatalog.ts`
- `payload/website/docusaurus.config.ts`
- `payload/website/src/theme/authoring/SiteAdminPanel.tsx`
- `payload/Scripts/UETools/DocsEditorApiHost.ps1`
- `payload/Scripts/Tests/Test-DocsTools.ps1` Cases `1g` through `1ii`
