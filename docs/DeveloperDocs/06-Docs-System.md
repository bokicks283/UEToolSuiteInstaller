# Docs System

## Source-of-truth roots

Confirmed authored roots:

- docs content: `payload/Docs/**`
- website source: `payload/website/**`
- runtime lifecycle and checks: `payload/Scripts/UETools/UEToolSuite.Docs.psm1`
- route/sidebar/domain synthesis: `payload/website/domainCatalog.ts`, `payload/website/sidebars.ts`

The website does not use `website/docs`. `payload/website/AGENTS.md` explicitly states that docs content lives in `../Docs`.

## How content becomes a rendered doc

1. Markdown or MDX lives under `Docs/`.
2. Docusaurus reads `../Docs` via the classic preset in `payload/website/docusaurus.config.ts`.
3. `domainCatalog.ts` derives doc ids, labels, positions, domain ownership, and sidebar items from:
   - markdown front matter
   - `_category_.json`
   - `Docs/_domains.json`
   - directory names and README/index fallbacks
4. `sidebars.ts` calls `buildDocsSidebarsConfig()`.
5. `docusaurus.config.ts` builds navbar items from the same catalog.
6. On doc pages, `DocItem/Layout/index.tsx` decides whether authoring controls can appear for the current `source` token.

## Route generation

Confirmed route rules from `payload/website/domainCatalog.ts` and `payload/website/src/theme/authoring/api.ts`:

- doc ids use Docs-relative paths with normalized segment handling
- numbered prefixes are stripped by `normalizeDocsPathSegments()` when forming doc ids
- route slugs shown in the frontend are derived by `getDocsRouteFromToken()`
- section landing docs resolve from `_category_.json` links first, then README/index fallback (`getDirectoryLandingDocId()`)

## Docs metadata sources

| Source | Purpose |
|---|---|
| front matter in `.md/.mdx` | title, slug, sidebar position, visibility (`unlisted`) |
| `_category_.json` | section label, position, landing-doc link |
| `Docs/_domains.json` | domain keys, labels, sidebar ids, owned roots/docs, landing behavior |
| directory/file names | fallback labels and ids when metadata is missing |

## Hidden and visibility-managed documents

Confirmed behavior:

- sidebar visibility is derived from `unlisted` front matter for pages (`isDocHiddenFromSidebar()` in `domainCatalog.ts`)
- the Docs Editor API toggles page visibility via `/api/visibility` and `Set-DocsPageVisibility`
- the inline doc page UI exposes Hide/Show on pages that support it

## Local authoring versus static rendering

The docs website supports two modes at once:

- static/read-only rendering when the authoring runtime is absent
- local authoring when runtime discovery succeeds and the API identity matches the active project

This split is intentional. `runtimeDiscovery.ts` explicitly models checking, connected, and multiple failure categories rather than treating missing authoring as a site failure.

## Runtime descriptor and proxying

- frontend proxy base: `/__ue_docs_api__/`
- direct API default: `http://127.0.0.1:38473/`
- runtime descriptor candidates: `/ue-tools/editor-runtime.json`, `/.ue-tools/editor-runtime.json`

The runtime descriptor is discovery metadata, not final proof of a usable runtime. The frontend still validates `/health` before enabling authoring.

## Rebuild and reload behavior

Confirmed by current source and tests:

- `ue-tools docs check` runs Docusaurus build validation
- `ue-tools docs start` can run foreground or background
- background docs runtime writes tracked server/editor state and can be reused
- docs structure changes broadcast `ue-docs:structure-changed` from `api.ts`

## Example: file path to editable doc

Example source path:

`Docs/WorkflowStandards/DocsSite/Authoring.md`

Relevant transformations:

- Docusaurus doc id: `WorkflowStandards/DocsSite/Authoring`
- route from frontend token helper: `/docs/workflow-standards/docs-site/authoring`
- sidebar membership: derived by `buildDocsSidebarsConfig()` through domain ownership and section/category metadata
- editable page token: resolved from the Docusaurus `source` path by `resolveSourceToken()`
- visibility-managed page: the same token is used by `/api/content` and `/api/visibility`

## Source references

- `payload/website/docusaurus.config.ts`
- `payload/website/domainCatalog.ts`
- `payload/website/sidebars.ts`
- `payload/website/src/theme/authoring/api.ts`
- `payload/website/src/theme/DocItem/Layout/index.tsx`
