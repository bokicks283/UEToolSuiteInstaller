## Priority issue — Fix populated-section moves across domains

Use the complete staged prompts in the roadmap package:

1. `prompts/01-cross-domain-info-dump.md`
2. `prompts/02-cross-domain-regression-test.md`
3. `prompts/03-fix-cross-domain-move.md`

This issue must be handled before broad refactoring because the Admin Panel tree and Docusaurus navigation currently disagree after a populated section is moved between domains.


# Ready-to-paste issue prompts — local authoring model

Use one prompt in a fresh Codex thread. Start Codex in the narrowest relevant directory so it loads the closest `AGENTS.md`.

Do not combine all issues into one implementation.


## Issue 01 — Make staged structure saves atomic or safely resumable

### Prompt

Goal:
Prevent partial and duplicate application of staged structure mutations from `SiteAdminPanel`.

Current behavior:
`saveStructureChanges` sends each queued mutation as a separate sequential POST. If a later operation fails, earlier operations may already be persisted while the browser still holds the original queue. Retrying can repeat completed changes.

Read:
- `payload/website/src/theme/authoring/AGENTS.md`
- `docs/agent/EDITOR_CONTRACTS.md`
- `docs/agent/TEST_MATRIX.md`

Relevant files:
- `payload/website/src/theme/authoring/SiteAdminPanel.tsx`
- `payload/Scripts/UETools/DocsEditorApiHost.ps1`
- docs mutation functions/modules
- `payload/Scripts/Tests/Test-DocsTools.ps1`

Preferred result:
Create a versioned endpoint such as `POST /api/structure/apply` that receives an ordered operation batch and a baseline revision.

The server should:
1. Validate the complete batch before writing.
2. Resolve dependencies and final paths deterministically.
3. Snapshot affected files/directories or create an equivalent transaction journal.
4. Apply operations in order.
5. Roll back all applied changes if any operation fails.
6. Return typed per-operation results and a new structure revision.
7. Reject stale baselines before mutation.

Frontend:
- Submit one batch.
- Clear pending changes only after complete success.
- Retain the draft after conflict/failure.
- Do not reload over unsaved draft state.

Tests:
- successful mixed batch
- validation failure before first write
- injected failure after at least one operation with full rollback
- stale baseline conflict
- safe retry
- move followed by metadata edit using the moved path
- delete combined with dependent queued operations

Constraints:
- Preserve existing individual endpoints temporarily if compatibility requires them.
- Do not claim atomicity if only partial best-effort cleanup exists.
- Use scratch repositories only.

Done when:
A failed structure save cannot persist only a prefix of the requested operations, and retry cannot duplicate completed work.


## Issue 02 — Add a narrow frontend verification harness

### Prompt

Goal:
Add fast deterministic tests for the local docs authoring frontend.

Package:
`payload/website`

Current state:
The package has start/build/typecheck scripts but no frontend unit, component, or browser test scripts.

Phase 1 — Unit:
- Add Vitest.
- Add tests for:
  - path normalization/building
  - tree remove/insert/path rewrite
  - descendant exclusion
  - mutation queue ordering/deduplication
  - runtime candidate selection
  - Markdown preparation/save fixtures

Phase 2 — Components:
- Add React Testing Library tests for:
  - pending changes survive API failure
  - conflict/error UI
  - invalid move/collision blocked
  - runtime unavailable state

Phase 3 — Browser:
- Add Playwright with one Chromium project.
- Start a scratch docs repo, API host, and Docusaurus on dynamic ports.
- Verify one inline edit/save/reload flow.
- Verify one structure move flow.
- Assert resulting files and navigation.
- Capture trace, screenshot, and logs on failure.

Scripts:
- `test:unit`
- `test:editor`
- `test:e2e`
- one CI-friendly aggregate command

Constraints:
- Use `npm ci`.
- Never test against the real repository `Docs/`.
- Do not use fixed ports.
- Keep the first patch focused on harness plus a small representative set.

Done when:
A change to one path/tree/Markdown behavior receives a focused pass/fail signal without running the whole repository.


## Issue 03 — Protect Markdown with golden round-trip tests

### Prompt

Goal:
Prove which Markdown/MDX constructs the rich editor preserves and prevent unrelated rewrites.

Relevant file:
`payload/website/src/theme/DocItem/Layout/index.tsx`

First extract pure preparation/serialization functions into a testable module with no React dependency. Do not begin with a broad UI refactor.

Fixture corpus:
- LF and CRLF
- quoted/special front matter
- headings and intentional blank lines
- inline and fenced code containing Markdown-like text
- links with spaces, encoded paths, anchors, and queries
- images
- tables and alignment
- task/nested lists
- admonitions
- Mermaid
- icon/emoji shortcodes
- generated TOC and ignored headings
- supported HTML
- imports/exports and custom MDX that remain source-only

Define explicit policies:
1. byte-identical no-op where feasible
2. documented normalization where necessary
3. unsupported rich editing with a clear reason

Tests:
- load -> serialize with no edit
- load -> one localized edit -> serialize
- unsupported syntax detection
- TOC regeneration
- front matter remains outside Tiptap serialization

Do not update expected fixtures merely because current output differs. Classify every difference first.

Done when:
A test catches unintended Markdown changes outside the user's edit.


## Issue 04 — Split the inline editor in behavior-preserving slices

### Prompt

Goal:
Reduce `DocItem/Layout/index.tsx` to a thin Docusaurus integration component without changing behavior.

Prerequisites:
Frontend tests and Markdown fixtures must exist and pass.

Small steps:
1. Move pure Markdown/TOC/shortcode helpers.
2. Move Tiptap extensions and node views.
3. Move toolbar and insert dialogs.
4. Move load/save/draft/conflict workflow into `useDocAuthoring`.
5. Leave route metadata and Docusaurus composition in the wrapper.

Rules:
- No feature additions during extraction.
- No CSS redesign.
- Preserve localStorage keys, endpoint payloads, draft behavior, and visible behavior.
- Avoid circular barrel imports.
- Keep browser-only code out of pure modules.
- Do not add a global state library.

At every step:
- run focused tests
- run typecheck/build
- review moved code versus changed behavior

Done when:
The swizzled layout can be understood without reading serialization and Tiptap internals.


## Issue 05 — Extract the SiteAdmin structure model from React

### Prompt

Goal:
Make SiteAdmin tree and pending-mutation behavior deterministic and testable without React.

Relevant file:
`payload/website/src/theme/authoring/SiteAdminPanel.tsx`

Extract:
- `structure/model.ts`
- `structure/reducer.ts`
- `structure/planner.ts`
- `structure/api.ts`
- focused React components

Required properties:
- `draft = reduce(baseline, pendingOperations)`
- immutable baseline
- stable operation IDs
- no stale path capture after moves
- typed invalid-sequence errors
- exact discard behavior
- pending state retained after persistence failure
- server-confirmed state becomes the next baseline

Pure tests:
- create/move/reorder/delete
- cross-domain move
- consecutive moves
- move then metadata edit
- metadata edit then move
- delete parent with pending child edit
- deduplicated metadata/visibility updates
- collision/descendant rejection

Do not combine this with backend atomic batching unless explicitly scoped.

Done when:
Most SiteAdmin behavior is explainable through pure input/output tests.


## Issue 06 — Turn the PowerShell API host into a thin transport layer

### Prompt

Goal:
Extract testable docs-editor services from `DocsEditorApiHost.ps1` while preserving local endpoint and CLI behavior.

Suggested boundaries:
- contracts/errors
- paths
- content/front matter
- structure planning/application
- links/doc IDs/slugs
- domains/navigation
- site customization
- HTTP transport

Requirements:
- Host initializes runtime, imports modules, routes requests, and serializes responses.
- Domain functions are callable without starting `HttpListener`.
- Importing a module must not start a listener.
- Preserve UTF-8 and endpoint payloads until separately versioned.
- Use typed errors.
- Reuse lower-level docs CLI behavior rather than duplicating it.

Process:
1. characterize current behavior
2. extract one cohesive group
3. keep compatibility wrappers
4. run targeted tests after each extraction
5. avoid reformatting the whole file

Done when:
Path/content/structure behavior can be tested by importing focused modules directly.


## Issue 07 — Establish one cross-language docs contract

### Prompt

Goal:
Prevent TypeScript and PowerShell from drifting on paths, domains, doc IDs, ownership, exclusions, and navigation.

Share fixtures and contracts rather than executing one language from the other.

Create:
- versioned JSON contract for API payloads and `_domains.json`
- canonical fixture cases
- TypeScript tests consuming fixtures
- PowerShell tests consuming the same fixtures
- contract version in runtime metadata

Cover:
- slash normalization
- case handling
- numbered prefixes
- `.md` and `.mdx`
- README/index landing docs
- root standalone docs
- ownership/catch-all
- excluded Current/Templates paths
- sidebar IDs/doc IDs
- hidden/unlisted behavior

For every current disagreement, document the canonical behavior and migration needs.

Done when:
Both language suites evaluate the same fixture expectations.


## Issue 08 — Make local API discovery deterministic and efficient

### Prompt

Goal:
Replace continuous broad port probing with a clear local runtime discovery sequence.

Relevant file:
`payload/website/src/theme/authoring/api.ts`

Desired order:
1. Docusaurus proxy.
2. Runtime descriptor written by `ue-tools docs start`.
3. Default direct loopback endpoint.
4. One bounded fallback scan only for stale/missing runtime metadata or explicit retry.

Requirements:
- one in-flight discovery attempt
- abort stale fetches
- exponential backoff with cap
- pause/slow while hidden
- immediate retry on user action/focus/runtime event
- distinguish discovering, unavailable, stale runtime, and ready
- static docs remain usable

Tests:
Use fake timers and mocked fetch for order, no overlap, backoff, pause/resume, and recovery.

Done when:
Unavailable authoring produces a small bounded request rate and non-default ports remain reliable.


## Issue 09 — Remove generated `build-debug` output from source control

### Prompt

Goal:
Remove generated Docusaurus `payload/website/build-debug/` artifacts from source control and prevent recurrence, unless repository evidence proves they are an intentional release input.

Process:
1. Search installer, packaging, release, and tests for references.
2. Confirm no shipped feature consumes it.
3. If unused:
   - remove tracked directory
   - add `/build-debug` to website `.gitignore`
   - add root ignore rule
   - ensure packaging/manifests exclude it
   - add/update packaging test rejecting generated website output
4. If intentionally consumed, stop and document the owner and generation process instead.

Do not delete source assets or regenerate/commit the directory.

Validation:
- website build
- packaging-contracts
- local build leaves no generated files in `git status`

Done when:
Generated bundles no longer pollute source search or release inputs.


## Issue 10 — Add typed local API contracts and errors

### Prompt

Goal:
Stop relying on error-message text for control flow and make editor recovery explicit.

Use a versioned envelope.

Success:
```json
{"ok":true,"result":{},"apiVersion":1}
```

Failure:
```json
{
  "ok":false,
  "error":{
    "code":"CONTENT_CONFLICT",
    "message":"File changed by another process.",
    "details":{}
  },
  "apiVersion":1
}
```

Define codes for:
- validation
- not found
- collision
- content conflict
- stale structure
- unsupported content
- runtime unavailable
- filesystem/application failure

Requirements:
- map PowerShell exception records to status/code without regex matching message text
- TypeScript discriminated unions and custom API error
- tolerate empty/non-JSON error responses
- branch conflict UI on code
- keep messages readable but not machine-significant
- optional debug details only in local debug mode

Done when:
Changing an error sentence cannot break frontend behavior.


## Issue 11 — Add targeted case/tag selection to the docs-tools suite

### Prompt

Goal:
Allow agents to run only relevant docs cases while preserving the existing full-suite command.

Relevant files:
- `payload/Scripts/Tests/Test-DocsTools.ps1`
- `Tests/Run-UEToolSuiteTests.ps1`
- shared harness

Add:
- `-Case <pattern[]>`
- `-Tag <tag[]>`
- `-ListCases`

Requirements:
- default still runs complete suite
- stable unique case IDs
- selection before expensive setup when possible
- unknown selectors fail clearly
- logs show selected/skipped cases
- cleanup always runs
- CI remains full-suite
- document examples for content, move, domains, startup, and theme subsets

Adapt to the repository's existing argument-forwarding pattern.

Done when:
A single move or save regression can be run without unrelated setup.


## Issue 12 — Centralize front matter parsing and mutation

### Prompt

Goal:
Use one tested policy for front matter across the TypeScript catalog, browser editor, and PowerShell backend.

First inventory every parser and writer.

Required behavior:
- preserve unrelated keys, comments, order, and newline style where feasible
- handle colons/hash characters in quoted values
- consistent booleans/numbers
- do not treat body `---` as front matter
- malformed front matter produces a typed error
- justify any YAML dependency

Strategy:
- define the supported subset
- create shared fixtures
- implement one TypeScript and one PowerShell reader/writer against those fixtures
- centralize title, slug, unlisted, and sidebar_position mutations
- keep front matter outside Tiptap serialization

Done when:
Both languages interpret the same fixtures equivalently and changing one key does not rewrite unrelated metadata.


## Issue 13 — Formalize local docs runtime lifecycle

### Prompt

Goal:
Make `ue-tools docs start|stop|status` and browser runtime discovery agree on one reliable lifecycle model.

Trace:
- Docusaurus process
- PowerShell API process
- runtime descriptor
- tracked process state
- selected ports
- startup readiness
- shutdown cleanup

Required behavior:
- dynamic/default ports are recorded consistently
- startup waits for both processes to become ready or fails clearly
- stale state files are detected and replaced
- `status` distinguishes running, partial, stale, and stopped
- `stop` handles already-dead processes and removes stale state
- restart does not discover an old API
- child processes do not remain orphaned after normal stop
- logs identify the active Docusaurus URL and API URL

Tests:
- default port
- non-default port
- occupied port
- stale descriptor
- one process dies
- repeated start
- stop after partial startup
- clean restart

Done when:
Local startup, discovery, status, stop, and restart behave as one coherent system.

## Template — Additional issue

### Prompt

Goal:
[One observable outcome.]

Observed behavior:
[Exact steps, path examples, commands, and actual result.]

Expected behavior:
[What should happen.]

Environment:
- branch/commit
- PowerShell/Node versions if relevant
- docs route/path token
- clean restart result

Evidence:
- exact error
- screenshot/video
- logs
- smallest affected fixture

Read:
- root and nearest `AGENTS.md`
- `docs/agent/EDITOR_ARCHITECTURE.md`
- `docs/agent/EDITOR_CONTRACTS.md`

Constraints:
- reproduce before production edits
- add the narrowest regression test
- trace browser state -> API payload -> PowerShell operation -> repository result
- keep the diff bounded
- do not edit generated output
- use a scratch Docs tree

Process:
1. State a falsifiable failure assertion.
2. Trace to the first divergence.
3. Identify root cause with file/function evidence.
4. Add the failing test.
5. Implement the smallest coherent fix.
6. Run focused validation, relevant suite, typecheck, and build.
7. Report commands, results, and remaining uncertainty.

Done when:
- the test fails before and passes after
- the exact reported scenario passes
- neighboring behavior remains valid
- no generated/unrelated files changed
