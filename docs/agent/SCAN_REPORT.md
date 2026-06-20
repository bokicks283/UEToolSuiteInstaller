## Immediate regression — Cross-domain moves of populated sections

A populated section can appear correctly moved in the Admin Panel while the rendered destination domain opens an unexpected moved page and omits the intended domain sidebar.

Treat this as the first repair:

1. produce an information dump without code changes
2. add a failing regression fixture
3. implement the smallest navigation/metadata fix

The likely boundary includes domain landing selection, `displayed_sidebar`, category `link.id`, ownership normalization, TypeScript sidebar generation, and navigation invalidation.


# Repository scan report — local authoring model

Scanned: **2026-06-19**  
Repository: `bokicks283/UEToolSuiteInstaller`  
Branch: `main`

The docs website and editor API are treated here as intentionally local development tools that write directly to repository files. Public deployment security is outside scope.

## Executive summary

The editor already has meaningful functionality and substantial PowerShell integration coverage. Its main risks are:

- partial multi-file changes
- retry behavior after failures
- Markdown/front-matter transformation
- oversized mixed-responsibility files
- duplicated TypeScript/PowerShell rules
- slow broad verification loops
- generated output polluting source search

## Findings

### P0 — Staged structure save is not atomic or retry-safe

`SiteAdminPanel` sends queued mutations as separate sequential requests. If a later request fails, earlier changes may already be on disk while the full queue remains in the browser. Retrying can repeat completed operations.

**Impact:** inconsistent repository state and difficult recovery.

**Prompt:** Issue 01.

### P1 — No frontend unit or browser test harness

The website package has build/typecheck scripts but no focused frontend test scripts.

**Impact:** tree, mutation, and Markdown changes require broad builds or manual testing, increasing Codex cost and regression risk.

**Prompt:** Issue 02.

### P1 — Markdown round trips can change unrelated content

Editor preparation and serialization normalize several patterns. Without golden fixtures, intended normalization and accidental content loss cannot be distinguished.

**Impact:** saving one edit can alter unrelated Markdown.

**Prompt:** Issue 03.

### P1 — Inline editor file is an oversized change surface

`DocItem/Layout/index.tsx` combines layout integration, Tiptap extensions, Markdown transforms, drafts, API operations, toolbar UI, dialogs, and rendering.

**Impact:** high context usage and large regression blast radius.

**Prompt:** Issue 04.

### P1 — Site administration mixes model, persistence, and UI

`SiteAdminPanel.tsx` contains tree algorithms, pending mutation logic, optimistic state, API persistence, dialogs, and rendering.

**Impact:** mutation behavior is hard to test independently.

**Prompt:** Issue 05.

### P1 — API host combines transport and all domain operations

`DocsEditorApiHost.ps1` owns listener transport, routing, content editing, paths, domains, moves, reference rewriting, invalidation, and site settings.

**Impact:** changes require understanding a very large trust-and-mutation surface even for small fixes.

**Prompt:** Issue 06.

### P1 — Canonical docs rules are duplicated across TypeScript and PowerShell

Path normalization, domain discovery, front matter, doc IDs, ownership, exclusions, and navigation rules exist in both languages.

**Impact:** browser preview and backend mutation can disagree.

**Prompt:** Issue 07.

### P2 — Runtime discovery scans many ports and retries frequently

The browser probes many loopback candidates and retries while unavailable.

**Impact:** noisy debugging, unnecessary requests, and stale-process confusion.

**Prompt:** Issue 08.

### P2 — Generated `build-debug` output is committed and not ignored

Generated Docusaurus bundles under `payload/website/build-debug/` appear in repository search but are not the source implementation.

**Impact:** wasted model context and false-positive code matches.

**Prompt:** Issue 09.

### P2 — API errors are weakly typed

Frontend behavior relies mainly on error strings, while the host infers conflict status from message text.

**Impact:** brittle recovery behavior and harder testing.

**Prompt:** Issue 10.

### P1 cost reduction — Docs suite needs narrow case selection

The docs PowerShell suite has good integration coverage but is broad.

**Impact:** slower repair loops and larger logs.

**Prompt:** Issue 11.

### P1 — Front matter parsing and mutation need one tested policy

Multiple regex/ad hoc readers and writers interpret front matter.

**Impact:** quoted values, comments, multiline values, ordering, and newline style may diverge.

**Prompt:** Issue 12.

### P2 — Local runtime lifecycle should be formalized

The browser, Docusaurus process, API process, runtime descriptor, tracked state, and ports form one local system but lifecycle behavior is spread across files.

**Impact:** stale state, wrong-port discovery, or orphaned processes can look like editor bugs.

**Prompt:** Issue 13.

## Recommended order

| Order | Work | Reason |
|---:|---|---|
| 1 | Generated output cleanup | Immediate context reduction |
| 2 | Targeted test selection | Speeds all later work |
| 3 | Frontend test harness | Establishes fast verification |
| 4 | Atomic structure save | Highest data-integrity risk |
| 5 | Markdown/front-matter fixtures | Protects authored content |
| 6 | Shared contracts and typed errors | Stabilizes language boundary |
| 7 | Incremental file extraction | Lower-risk after tests |
| 8 | Runtime discovery/lifecycle | Improves local reliability |
