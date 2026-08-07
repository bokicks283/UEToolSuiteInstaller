# Frontend Component Catalog

This catalog focuses on authoring-related React components in the current checkout.

| Component | Source file | Purpose | Props | Main state/hooks | API routes used | Null or gated rendering | Related tests | Risk |
|---|---|---|---|---|---|---|---|---|
| `SiteSettingsPage` | `payload/website/src/pages/site-settings.tsx` | Dedicated Site Settings route for theme, branding, domains, and overrides | none | `useDocsAuthoringApi` | indirect via `SiteAdminPanel` | renders `SiteAdminPanel` only when `runtimeAvailable`; renders status card on failure | runtime discovery behavior from docs/frontend suites | High |
| `AuthoringConnectionStatusCard` | `payload/website/src/theme/authoring/AuthoringConnectionStatusCard.tsx` | Structured UI for runtime discovery failures | `status`, `onRetry` | `getAuthoringConnectionPresentation` | none directly | returns details block only when technical details exist | runtime discovery behavior | Medium |
| `SiteAdminPanel` | `payload/website/src/theme/authoring/SiteAdminPanel.tsx` | Main tree/domain/site-settings administration surface | `requestJson` | many `useState` hooks, local storage, mutation queue | tree, domains, move, rename, metadata, reorder, delete, visibility, site routes | parent page prevents render unless runtime connected | docs authoring integration cases | High |
| default `DocItem/Layout` component | `payload/website/src/theme/DocItem/Layout/index.tsx` | Inline edit, save, hide/show, draft, shortcode, and rendered-doc controls on document pages | Docusaurus doc layout props | `useDocsAuthoringApi`, document-local state, local storage | `/api/content`, `/api/visibility`, structure refresh behavior | hides authoring UI when source token/runtime state disallow it | docs authoring/browser acceptance, route cases | High |
| `DocSidebarWrapper` | `payload/website/src/theme/DocSidebar/index.tsx` | Thin wrapper around the original Docusaurus sidebar | Docusaurus `Props` | none | none | no custom null branch | docs UI build coverage | Low |
| home page default component | `payload/website/src/pages/index.tsx` | Site landing page | none | page-local render only | none | no authoring behavior | docs build coverage | Low |

## Observations

- The authoring UI has two concentration points: `SiteAdminPanel.tsx` and `DocItem/Layout/index.tsx`.
- `site-settings.tsx` is intentionally thin and delegates runtime state to `useDocsAuthoringApi`.
- `AuthoringConnectionStatusCard.tsx` is the shared failure presenter worth reusing for new authoring entry surfaces.

Count note: this catalog covers 6 meaningful frontend components in the current authoring surface.
