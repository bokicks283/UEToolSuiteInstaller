# Cross-Domain Move Info Dump

## Executive summary

The current Site Admin move flow correctly rewrites the Admin draft tree and persists a filesystem move through `POST /api/move`, but the persisted move does not repair every Docusaurus navigation surface that can affect the rendered destination page.

The strongest static root-cause candidate is stale `displayed_sidebar` front matter on moved section landing docs and child docs. New domains can stamp landing docs with `displayed_sidebar: <domain-sidebar-id>`, but `Move-DocsNode` preserves moved Markdown front matter and does not rewrite `displayed_sidebar` to the destination domain. Docusaurus can then render the moved page with the old/source sidebar or no matching sidebar while Admin still shows the correct filesystem hierarchy.

The second strong candidate is destination domain navbar selection when `landingDoc` is missing or invalid. `getDocsDomainCatalog()` drops invalid landing docs, `docusaurus.config.ts` falls back from a `type: 'doc'` navbar item to `type: 'docSidebar'`, and a doc-sidebar navbar item can route to the first item in the destination sidebar. After moving a populated section into the destination domain, the first item can be the moved section's landing doc, which matches the "unexpected page from the moved section" symptom.

The earliest likely divergence is after `Move-DocsNode` has moved files and before Docusaurus renders: Admin reloads from `Get-DocsTree`, which is filesystem/tree oriented, while Docusaurus reloads from `_domains.json`, `_category_.json`, front matter, and `domainCatalog.ts`.

## Exact current move flow

Instruction and architecture contracts loaded:

- `AGENTS.md`
- `payload/AGENTS.md`
- `payload/website/AGENTS.md`
- `payload/Scripts/AGENTS.md`
- `payload/Scripts/UETools/AGENTS.md`
- `Tests/AGENTS.md`
- `payload/Scripts/Tests/AGENTS.md`
- `payload/website/src/theme/authoring/AGENTS.md`
- `payload/website/src/theme/DocItem/Layout/AGENTS.md`
- `docs/agent/EDITOR_ARCHITECTURE.md`
- `docs/agent/EDITOR_CONTRACTS.md`
- `docs/agent/TEST_MATRIX.md`

Frontend Admin flow:

- `payload/website/src/theme/authoring/SiteAdminPanel.tsx:62-80` defines `StructureMutation`, including `moveNode`, and `PendingMutation`.
- `payload/website/src/theme/authoring/SiteAdminPanel.tsx:355-389` builds move target parent options for a target domain. Cross-domain moves do not include shared root unless the active domain is the same as the target domain.
- `payload/website/src/theme/authoring/SiteAdminPanel.tsx:846-904` performs the optimistic Admin draft move. It removes the selected node from the source domain tree, rewrites in-memory node paths with `rewriteNodePaths`, inserts into the destination tree, and updates selection to the destination domain/path.
- `payload/website/src/theme/authoring/SiteAdminPanel.tsx:1167-1204` queues the user action from the Move panel. The pending operation is:

```json
{
  "kind": "moveNode",
  "sourcePath": "DomainA/PopulatedSection",
  "destinationDomainPath": "DomainB",
  "destinationParentPath": "DomainB",
  "insertIndex": 0
}
```

- `payload/website/src/theme/authoring/SiteAdminPanel.tsx:1300-1446` persists pending mutations sequentially. For `moveNode`, it sends `POST /api/move` with JSON body `{sourcePath,destinationDomainPath,destinationParentPath,insertIndex}` at `payload/website/src/theme/authoring/SiteAdminPanel.tsx:1412-1422`.
- `payload/website/src/theme/authoring/api.ts:303-312` sends the request to `${apiBaseUrl}${path}` and treats non-OK or `{ok:false}` as failure.
- `payload/website/src/theme/authoring/api.ts:53-68` defaults the API base to `/__ue_docs_api__/`, normalized with trailing slash.

PowerShell API flow:

- `payload/Scripts/UETools/DocsEditorApiHost.ps1:3554-3635` routes API requests and reads JSON bodies for POST requests.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:3668-3675` handles `/api/move`. It calls:

```powershell
Move-DocsNode `
  -SourcePath ([string]$body.sourcePath) `
  -OwnerDomainPath ([string]$body.destinationDomainPath) `
  -DestinationParentPath ([string]$body.destinationParentPath) `
  -InsertIndex $indexValue `
  -NewName ([string]$body.newName) `
  -PreferredSiteOrigin $siteOrigin
```

`Move-DocsNode` related functions:

- `payload/Scripts/UETools/DocsEditorApiHost.ps1:235-260` resolves navigation targets and normalizes missing sidebar positions before retrying resolution.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:3170-3388` implements `Move-DocsNode`.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:3170-3237` resolves source/destination, rejects self/descendant moves, computes destination full path.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:3250-3258` builds the moved Markdown path map and moves the source filesystem item with `Move-Item`.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:3263-3274` repairs slug/category/docId/link state and asserts references.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:3276-3294` tries dev-server invalidation and checks for stale registry imports.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:3296-3342` normalizes sibling positions in old and destination parents, then applies requested insert order.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:3343-3344` calls `Set-DocsDomainOwnerForTopLevelItem` using the new relative path and `OwnerDomainPath`.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:3349-3353` returns `{path,devServerInvalidated,warning}`.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:3355-3388` rolls back docId/link rewrites and moved path on error.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:331-402` preserves stable slugs for moved Markdown by adding the old route slug when a moved file lacks `slug`.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:405-436` updates a moved section's `_category_.json` doc link to the new README doc ID.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:966-1075` rewrites Markdown links for moved files.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:1273-1361` rewrites docId/id references in `website/docusaurus.config.ts`, `website/sidebars.ts`, and all `_category_.json` files.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:1543-1554` normalizes moved section category links; pages are skipped.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:2577-2585` touches navigation files when called.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:2619-2744` can update `_domains.json` ownership for top-level items only.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:1095-1227` locates dev-server origins and calls `/webpack-dev-server/invalidate` or `/invalidate`.

Domain and Admin tree reads:

- `payload/Scripts/UETools/DocsEditorApiHost.ps1:1676-1678` stores domains in `Docs/_domains.json`.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:1765-1893` normalizes domain definitions. It filters `ownedRoots` to existing top-level directories and `ownedDocs` to existing top-level doc IDs.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:1895-2001` builds Admin trees. With `sidebarId`, it finds the domain, collects top-level roots/docs owned by that domain, and for the domain's own root inserts children directly.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:2003-2202` builds tree children, skipping a README if it is the category-linked landing doc.

Docusaurus navigation generation:

- `payload/website/domainCatalog.ts:184-193` reads `Docs/_domains.json`.
- `payload/website/domainCatalog.ts:501-590` normalizes configured domains, drops non-existing owned roots/docs, assigns unclaimed roots/docs to standard/catch-all domains, and converts `landingDoc` to `docId`.
- `payload/website/domainCatalog.ts:593-621` exports `getDocsDomainCatalog()`. It drops `domain.docId` if `findDocPathFromDocId(domain.docId)` does not resolve.
- `payload/website/domainCatalog.ts:301-328` selects a directory landing doc from `_category_.json` `link.id` or README/index fallback.
- `payload/website/domainCatalog.ts:339-397` builds category sidebar items and attaches `link: {type:'doc', id: landingDocId}` when the landing doc is visible.
- `payload/website/domainCatalog.ts:682-751` exports `buildDocsSidebarsConfig()`, which builds one sidebar per domain from `ownedRoots`/`ownedDocs`.
- `payload/website/sidebars.ts:1-5` is a thin shell around `buildDocsSidebarsConfig()`.
- `payload/website/docusaurus.config.ts:4-6` computes the domain catalog at config load.
- `payload/website/docusaurus.config.ts:40-54` generates navbar items. If `domain.docId` exists, the navbar item is `type: 'doc'`; otherwise it is `type: 'docSidebar'`.
- `payload/website/docusaurus.config.ts:92-97` points Docusaurus docs at `../Docs`, `routeBasePath: 'docs'`, and `sidebars.ts`.
- `payload/website/src/theme/DocSidebar/index.tsx:1-7` wraps the original Docusaurus sidebar without changing sidebar selection.

Front matter creation and preservation:

- `payload/Scripts/UETools/UEToolSuite.Docs.psm1:2634-2643` creates initial doc front matter with `title`, `slug`, and optional `sidebar_position`.
- `payload/Scripts/UETools/UEToolSuite.Docs.psm1:2646-2664` applies optional common doc front matter, including `displayed_sidebar`.
- `payload/Scripts/UETools/UEToolSuite.Docs.psm1:2803-2833` creates section README front matter and doc ID.
- `payload/Scripts/UETools/UEToolSuite.Docs.psm1:2836-2866` creates `_category_.json` with `link.id` defaulting to the README doc ID.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:2746-2761` creates a domain by creating a top-level section with `-DisplayedSidebar $sidebarId`.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1:2485-2575` creates pages/sections and assigns top-level ownership. Ordinary section creation accepts `DisplayedSidebar` but the current Site Admin create-section request does not pass it.
- `Move-DocsNode` does not rewrite `displayed_sidebar`, `unlisted`, or existing `slug` values. It only adds missing slugs to preserve old routes.

## State before and after the move

Concrete example:

```text
Docs/DomainA/
Docs/DomainB/
Docs/DomainA/PopulatedSection/
```

Move target:

```text
Docs/DomainB/PopulatedSection/
```

Representative before state:

```text
Docs/
  _domains.json
  DomainA/
    README.md
    _category_.json
    PopulatedSection/
      README.md
      _category_.json
      Child.md
  DomainB/
    README.md
    _category_.json
```

Representative `_domains.json` before:

```json
{
  "schemaVersion": 1,
  "domains": [
    {
      "key": "DomainA",
      "dirName": "DomainA",
      "sidebarId": "domain-a-sidebar",
      "label": "Domain A",
      "landingDoc": "DomainA/README",
      "showLandingInSidebar": false,
      "ownedRoots": ["DomainA"],
      "ownedDocs": [],
      "catchAll": false
    },
    {
      "key": "DomainB",
      "dirName": "DomainB",
      "sidebarId": "domain-b-sidebar",
      "label": "Domain B",
      "landingDoc": "DomainB/README",
      "showLandingInSidebar": false,
      "ownedRoots": ["DomainB"],
      "ownedDocs": [],
      "catchAll": false
    }
  ]
}
```

Representative moved section metadata before:

```json
{
  "label": "Populated Section",
  "position": 2,
  "link": {
    "type": "doc",
    "id": "DomainA/PopulatedSection/README"
  }
}
```

Representative moved front matter before:

```yaml
---
title: Populated Section
slug: /domain-a/populated-section
sidebar_position: 1
displayed_sidebar: domain-a-sidebar
---
```

Expected after state:

```text
Docs/
  _domains.json
  DomainA/
    README.md
    _category_.json
  DomainB/
    README.md
    _category_.json
    PopulatedSection/
      README.md
      _category_.json
      Child.md
```

Expected `_domains.json` after:

- `DomainA.ownedRoots` remains `["DomainA"]`.
- `DomainB.ownedRoots` remains `["DomainB"]`.
- `DomainB.landingDoc` remains `DomainB/README` if it was valid before.
- Source and destination domain ownership remain unique.

Actual `_domains.json` after for this nested example:

- `Move-DocsNode` calls `Set-DocsDomainOwnerForTopLevelItem -PathToken "DomainB/PopulatedSection"`.
- `Get-DocsTopLevelOwnershipBinding` returns `$null` because the path has two segments.
- `_domains.json` is therefore usually unchanged. This is acceptable if `DomainB` already owns root `DomainB`, but it means no domain metadata is repaired for nested cross-domain moves.

Expected moved category metadata after:

```json
{
  "label": "Populated Section",
  "position": 1,
  "link": {
    "type": "doc",
    "id": "DomainB/PopulatedSection/README"
  }
}
```

Actual moved category metadata after:

- `Normalize-SlugsForMovedItem` updates the moved root section link at `payload/Scripts/UETools/DocsEditorApiHost.ps1:1543-1554`.
- `Update-DocsEditorDocIdReferencesForMove` also rewrites all `_category_.json` doc/id references at `payload/Scripts/UETools/DocsEditorApiHost.ps1:1273-1361`.
- Static evidence indicates the `link.id` should become `DomainB/PopulatedSection/README` unless parsing or a nonstandard link shape prevents the rewrite.

Expected moved front matter after:

```yaml
---
title: Populated Section
slug: /domain-a/populated-section
sidebar_position: 1
displayed_sidebar: domain-b-sidebar
---
```

Alternative acceptable behavior would be removing `displayed_sidebar` if Docusaurus can infer the destination sidebar deterministically. The contract that must remain stable is that the moved page renders with the destination domain's page sidebar.

Actual moved front matter after:

- `slug` is preserved if present.
- If `slug` is missing, `Ensure-DocsEditorMovedPageSlugsRemainStable` adds the old path slug.
- `sidebar_position` is normalized/reordered in source and destination parent groups.
- `unlisted` is preserved.
- `displayed_sidebar` is preserved unchanged.

Expected generated domain catalog after:

```text
DomainA: docId=DomainA/README, ownedRoots=[DomainA], sidebarId=domain-a-sidebar
DomainB: docId=DomainB/README, ownedRoots=[DomainB], sidebarId=domain-b-sidebar
```

Actual generated domain catalog after:

- If `DomainB/README` exists and is listed in `_domains.json`, `getDocsDomainCatalog()` keeps `DomainB.docId`.
- If `DomainB.landingDoc` is empty, stale, unresolvable, or omitted, `getDocsDomainCatalog()` returns `DomainB.docId = undefined` at `payload/website/domainCatalog.ts:614`.

Expected generated sidebar after:

```ts
{
  "domain-b-sidebar": [
    {
      type: "category",
      label: "Populated Section",
      link: {type: "doc", id: "DomainB/PopulatedSection/README"},
      items: ["DomainB/PopulatedSection/Child"]
    }
  ]
}
```

Actual generated sidebar after:

- `buildDocsSidebarsConfig()` includes moved content because `DomainB` owns root `DomainB`.
- If `DomainB.showLandingInSidebar` is false, `DomainB/README` is not included as a normal sidebar item.
- If the moved section is first by `position`, it can be the first navigable item in `domain-b-sidebar`.

Expected navbar target after:

- If `DomainB.landingDoc` is valid, navbar item should be `type: 'doc', docId: 'DomainB/README'`.
- If no landing doc exists by design, navbar item may be `type: 'docSidebar', sidebarId: 'domain-b-sidebar'`, but the first sidebar route must render with that sidebar.

Actual navbar target after:

- `docusaurus.config.ts` uses `type: 'doc'` only when `domain.docId` is truthy.
- If `DomainB.docId` is undefined, navbar uses `type: 'docSidebar'`. Docusaurus then chooses a sidebar landing route from that sidebar. Static local code does not define that final route selection; it is Docusaurus internals.

## First divergence

The earliest likely divergence is inside `Move-DocsNode` after the filesystem move has succeeded:

- Admin representation is driven by `Get-DocsTree`, which reads the current filesystem and `_category_.json` enough to display hierarchy.
- Docusaurus representation is driven by `getDocsDomainCatalog()`, `buildDocsSidebarsConfig()`, navbar generation, `_category_.json` category links, and each page's front matter.
- `Move-DocsNode` repairs slugs, Markdown links, docId references, category links, and sibling order, but it does not repair `displayed_sidebar` and does not ensure the destination domain has a stable landing doc/navbar target.

The first concrete line-level gap is `payload/Scripts/UETools/DocsEditorApiHost.ps1:3263-3274`: the code runs slug/link/docId repairs, but there is no equivalent repair for `displayed_sidebar`.

## Ranked root-cause candidates

1. Stale `displayed_sidebar` on moved Markdown.

Confidence: High.

Evidence:

- Domain creation passes the domain sidebar ID into section creation at `payload/Scripts/UETools/DocsEditorApiHost.ps1:2746-2761`.
- `Apply-CommonDocOptionValues` writes `displayed_sidebar` at `payload/Scripts/UETools/UEToolSuite.Docs.psm1:2646-2664`.
- `Move-DocsNode` does not rewrite `displayed_sidebar`.
- The symptom includes "destination domain's page sidebar is missing", which is exactly what stale or invalid sidebar front matter can cause in rendered Docusaurus.

What would falsify it:

- The moved section README and child docs do not contain `displayed_sidebar`.
- The rendered wrong page does contain the correct destination sidebar ID in Docusaurus metadata.
- Removing or rewriting only `displayed_sidebar` does not change the rendered sidebar behavior.

Minimal test:

- Fixture with `DomainA` and `DomainB`, both with valid sidebars.
- `DomainA/PopulatedSection/README.md` and `Child.md` include `displayed_sidebar: domain-a-sidebar`.
- Move `DomainA/PopulatedSection` to `DomainB` through `POST /api/move`.
- Assert moved Markdown no longer has `displayed_sidebar: domain-a-sidebar` and renders/selects `domain-b-sidebar`.

2. Destination domain has no valid `landingDoc`, so navbar falls back to first destination sidebar item.

Confidence: High for the "unexpected page from moved section" symptom; dependent on actual `_domains.json`.

Evidence:

- `getDocsDomainCatalog()` drops invalid `docId` at `payload/website/domainCatalog.ts:614`.
- `docusaurus.config.ts:40-54` uses a `docSidebar` navbar item when `domain.docId` is absent.
- `buildDocsSidebarsConfig()` can place the moved populated section as the first item in `domain-b-sidebar` at `payload/website/domainCatalog.ts:682-739`.

What would falsify it:

- Destination domain has a valid `landingDoc` that resolves before and after move.
- Navbar generated after move still uses `type: 'doc'` for the destination domain.
- Clicking destination navbar still opens the moved section even when `DomainB.docId` is valid and points to `DomainB/README`.

Minimal test:

- Fixture where `DomainB.landingDoc` is intentionally missing or invalid.
- Move populated section into `DomainB`.
- Assert `getDocsDomainCatalog().domains.find(DomainB).docId` is undefined and navbar would use `docSidebar`.
- Add the same fixture with valid `DomainB/README`; assert navbar target remains `DomainB/README`.

3. Cross-domain ownership repair is top-level only.

Confidence: Medium for edge cases; low for the exact nested example when `DomainB` owns `DomainB`.

Evidence:

- `Set-DocsDomainOwnerForTopLevelItem` only repairs one-segment path tokens at `payload/Scripts/UETools/DocsEditorApiHost.ps1:2619-2662`.
- `Move-DocsNode` passes the moved path after the move at `payload/Scripts/UETools/DocsEditorApiHost.ps1:3343-3344`.
- Moving to `DomainB/PopulatedSection` produces a two-segment path, so ownership metadata is usually not written.

What would falsify it:

- `_domains.json` ownership is correct and unique before/after in a failing repro.
- The failure occurs even when the moved item is nested under an already owned destination root and no stale top-level ownership exists.

Minimal test:

- Move a top-level section owned by `DomainA` into `DomainB`.
- Assert `_domains.json` removes the stale top-level `ownedRoots` entry from `DomainA` and does not leave ownership duplicates.

4. `_category_.json` `link.id` is stale or resolves to the wrong landing doc.

Confidence: Medium-low.

Evidence:

- Docusaurus category links are built from `_category_.json` at `payload/website/domainCatalog.ts:301-328` and `payload/website/domainCatalog.ts:371-376`.
- `Move-DocsNode` appears to repair these via `Normalize-SlugsForMovedItem` and `Update-DocsEditorDocIdReferencesForMove`.
- Existing tests cover nested section slug preservation but not cross-domain generated sidebar output.

What would falsify it:

- The moved section `_category_.json` has `link.id: DomainB/PopulatedSection/README` after the move.
- `findDocPathFromDocId("DomainB/PopulatedSection/README")` resolves and the category item link is correct.

Minimal test:

- Move a populated section with category `link.type: doc`.
- Assert moved `_category_.json` `link.id` is the new README doc ID and no old doc ID remains anywhere under `Docs/`.

5. Stale Docusaurus navigation or registry state after move.

Confidence: Medium.

Evidence:

- `Move-DocsNode` calls dev-server invalidation only when a path moved and Markdown path map exists.
- `Touch-DocsWebsiteNavigationFiles` is called by ownership writes, but nested moves may not call it because top-level ownership binding returns null.
- `Move-DocsNode` waits for stale registry imports and can return a warning, but Site Admin currently ignores detailed result handling beyond success/failure.

What would falsify it:

- Restarting Docusaurus after the move leaves the same wrong page/sidebar behavior.
- The generated sidebars/navbar are wrong in a production build, not just in dev-server hot state.

Minimal test:

- Execute the move in a scratch repo, run a fresh `npm run build`, and inspect that generated navigation behavior is wrong even without hot-reload state.

6. Slug preservation causes old route to stay associated with moved docs.

Confidence: Low as a root cause; high as required behavior.

Evidence:

- `Ensure-DocsEditorMovedPageSlugsRemainStable` intentionally preserves old public routes at `payload/Scripts/UETools/DocsEditorApiHost.ps1:379-402`.
- Existing tests assert slug preservation for moved pages and nested section README at `payload/Scripts/Tests/Test-DocsTools.ps1:573-607`.
- A preserved slug can make the moved page reachable at its old route, but it should not by itself remove the destination sidebar if the correct sidebar is selected.

What would falsify it:

- Removing slug preservation alone fixes the destination sidebar.
- The failing moved page has no explicit slug and receives a newly added slug that conflicts with destination domain landing.

Minimal test:

- Cross-domain move with explicit old slug and destination sidebar assertion.
- Assert route stability and destination sidebar selection simultaneously.

7. `unlisted` preservation hides the destination sidebar landing.

Confidence: Low.

Evidence:

- `domainCatalog.ts:219-227` treats `unlisted: true` as hidden from sidebars.
- `Move-DocsNode` preserves `unlisted`.
- The reported moved section is populated and visible in Admin, but Admin can display unlisted nodes while Docusaurus hides them from sidebar.

What would falsify it:

- Moved README and child docs do not have `unlisted: true`.
- Docusaurus sidebar items include the moved section but still render the wrong/no sidebar.

Minimal test:

- Cross-domain move with both listed and unlisted moved README variants; assert listed content appears and unlisted content remains hidden by design.

## Existing behavior contracts

The following must remain stable:

- Browser/API paths are Docs-relative `/` tokens.
- Windows path comparisons remain case-insensitive.
- Moves reject self, descendant, collision, invalid names, and unsupported types before mutation.
- Stable public routes/slugs are preserved unless route semantics are explicitly changed.
- Markdown links, `_category_.json` doc links, navbar/sidebar docId references, and moved doc IDs remain resolvable.
- Domain ownership remains unique and consistent.
- Landing documents are not duplicated as ordinary children.
- `unlisted` continues to hide content from Docusaurus sidebars.
- Generated and build output remain untouched.
- Failed structural mutations do not leave unexplained partial state.
- Site Admin draft state must not mutate baseline objects and failed saves must remain retryable.

## Recommended test-only patch

Add one focused failing regression test to `payload/Scripts/Tests/Test-DocsTools.ps1`, preferably inside the existing API-host move case or as a new narrowly named case after Case 1g.

Fixture:

- Build a scratch repo with `Docs/DomainA` and `Docs/DomainB`.
- Create `Docs/_domains.json` with:
  - `DomainA`: `sidebarId: domain-a-sidebar`, `landingDoc: DomainA/README`, `ownedRoots: ["DomainA"]`.
  - `DomainB`: `sidebarId: domain-b-sidebar`, `landingDoc: DomainB/README`, `ownedRoots: ["DomainB"]`.
- Create `Docs/DomainA/PopulatedSection/README.md`:
  - `title: Populated Section`
  - `slug: /domain-a/populated-section`
  - `sidebar_position: 1`
  - `displayed_sidebar: domain-a-sidebar`
- Create `Docs/DomainA/PopulatedSection/Child.md`:
  - `title: Child`
  - `slug: /domain-a/populated-section/child`
  - `sidebar_position: 2`
  - `displayed_sidebar: domain-a-sidebar`
- Create `Docs/DomainA/PopulatedSection/_category_.json` with `link.id: DomainA/PopulatedSection/README`.

Action:

```powershell
$moveBody = @{
  sourcePath = "DomainA/PopulatedSection"
  destinationDomainPath = "DomainB"
  destinationParentPath = "DomainB"
  insertIndex = 0
} | ConvertTo-Json -Depth 6

Invoke-RestMethod -Uri "http://127.0.0.1:$apiHostPort/api/move" -Method Post -ContentType "application/json" -Body $moveBody
```

Assertions:

- `Docs/DomainA/PopulatedSection` does not exist.
- `Docs/DomainB/PopulatedSection/README.md`, `Child.md`, and `_category_.json` exist.
- `Docs/_domains.json` still has `DomainB.landingDoc: DomainB/README`, `DomainB.ownedRoots` contains `DomainB`, and no domain owns the same top-level root/doc twice.
- `Docs/DomainB/PopulatedSection/_category_.json` contains `"id": "DomainB/PopulatedSection/README"` and does not contain `DomainA/PopulatedSection/README`.
- Moved README and child preserve `slug`.
- Moved README and child preserve `sidebar_position` deterministically.
- Moved README and child preserve `unlisted` when present.
- Moved README and child do not keep `displayed_sidebar: domain-a-sidebar`; expected destination behavior should be either `displayed_sidebar: domain-b-sidebar` or no `displayed_sidebar` if the implementation chooses inference.
- `getDocsDomainCatalog()` would keep `DomainB.docId = DomainB/README`.
- `buildDocsSidebarsConfig()` would include `DomainB/PopulatedSection` under `domain-b-sidebar` with a category link to `DomainB/PopulatedSection/README`.

Smallest browser-facing follow-up test:

- Add a Playwright/browser integration case only if the PowerShell/API regression cannot prove Docusaurus sidebar selection.
- Navigate to the destination domain navbar item after move.
- Assert the route is the expected destination landing route and `.theme-doc-sidebar-container` is visible with destination sidebar content.

## Recommended focused implementation patch

Do not implement in this investigation.

Smallest likely production change:

- Add a focused metadata repair step inside `Move-DocsNode` after `$movedMarkdownPathMap` is known and before reference assertions.
- When `OwnerDomainPath` resolves to a known domain, compute the destination sidebar ID from the domain definition.
- For every moved Markdown file:
  - If `displayed_sidebar` is absent, leave it absent unless the repo chooses explicit sidebar pinning.
  - If `displayed_sidebar` equals a known source domain sidebar ID or any known domain sidebar ID different from the destination, rewrite it to the destination sidebar ID.
  - Preserve custom/non-domain `displayed_sidebar` only if there is a documented reason; otherwise fail loudly or normalize deterministically.
- Keep existing slug preservation unchanged.
- Do not change `slug`, `sidebar_position`, or `unlisted` except through existing position normalization.
- Extend the move result or warning if dev-server invalidation fails after metadata repair.

Second focused patch if repro proves navbar fallback:

- Ensure destination domains keep a valid `landingDoc` when one existed before the move.
- If a domain has no landing doc, make that explicit in Admin and tests: clicking a `docSidebar` navbar item may route to the first sidebar doc by Docusaurus design.
- Do not silently promote a moved section landing doc to the destination domain landing doc unless that becomes an explicit feature.

Files most likely to change:

- `payload/Scripts/UETools/DocsEditorApiHost.ps1`
- `payload/Scripts/Tests/Test-DocsTools.ps1`
- Possibly `payload/website/domainCatalog.ts` only if navbar/landing selection, not front matter repair, proves to be the root cause.
- Possibly a future browser test file if Docusaurus sidebar selection needs end-to-end coverage.

## Commands and validation

Commands run for this investigation:

```powershell
git status --short --branch
rg -n "SiteAdminPanel|pending|Pending|move|Move|moveNode|moveSection|drag|drop|dragEnd|onDrag|Save|persist|api" payload\website\src -g !node_modules -g !.docusaurus -g !build -g !build-debug
rg -n "Move-DocsNode|Update-Docs|domain|_domains|category|displayed_sidebar|landingDoc|sidebar|Invalidate|Docusaurus|slug|link.id|docId|Resolve-|Normalize-" payload\Scripts\UETools payload\Scripts\Tests Tests -g !*Results*
rg -n "getDocsDomainCatalog|buildDocsSidebarsConfig|navbar|sidebars|displayed_sidebar|landingDoc|docId|route|slug" payload\website -g !node_modules -g !.docusaurus -g !build -g !build-debug
```

No validation tests were run because this task was explicitly information-gathering only and no fix was implemented.

Commands to run after the eventual fix:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File Tests/Run-UEToolSuiteTests.ps1 `
  -Name docs-tools `
  -FailFast
```

```powershell
Push-Location payload/website
try {
  npm run typecheck
  npm run build
}
finally {
  Pop-Location
}
```

If the fix changes managed payload paths or packaging-visible files:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File Tests/Run-UEToolSuiteTests.ps1 `
  -Name packaging-contracts `
  -FailFast
```

If browser behavior is patched or a browser regression test is added:

```powershell
Push-Location payload/website
try {
  npm run test:e2e -- --project=chromium
}
finally {
  Pop-Location
}
```

## Unknowns

- The exact failing repository state was not provided, so this report cannot prove whether the destination domain had a valid `landingDoc` before the move.
- The exact moved files' front matter was not provided, so stale `displayed_sidebar` is a high-confidence candidate, not a proven root cause.
- Docusaurus final route/sidebar selection for `type: 'docSidebar'` navbar items is not implemented in this repo's source; generated output and dependency internals were intentionally not inspected.
- Dev-server hot-reload behavior cannot be proven statically. A fresh build versus live dev-server comparison is needed to separate stale cache from incorrect generated navigation.
- Existing tests cover move slug/link/docId behavior, but not a full cross-domain populated-section move with domain landing, generated sidebars, navbar target, and `displayed_sidebar` assertions.
