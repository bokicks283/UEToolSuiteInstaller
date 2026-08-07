# Inline document editor instructions

`index.tsx` currently contains Docusaurus layout integration, Tiptap extensions, node views, Markdown transforms, editor state, toolbar UI, dialogs, draft recovery, and API operations.

Do not make it larger without a compelling reason.

## Data preservation

- Loading and saving without a user edit must not change the document.
- Preserve front matter and all supported Markdown semantics.
- Do not use broad cleanup regexes without golden round-trip tests.
- Unsupported MDX remains source-edit-only.
- Keep optimistic concurrency through `expectedHash`.
- Conflict errors must preserve the local draft and offer a clear recovery path.
- Keep front matter outside Tiptap serialization.

## Refactoring order

1. Add golden fixtures and tests.
2. Extract pure Markdown transforms.
3. Extract Tiptap extensions/node views.
4. Extract editor state/API workflow.
5. Extract toolbar/dialog components.
6. Leave a thin Docusaurus wrapper.

Each extraction must be behavior-preserving and independently reviewable.

## Required checks

- unit-test the transform or command
- verify advanced MDX remains source-only
- verify local draft recovery
- verify save conflict behavior
- verify unchanged documents remain unchanged
- run typecheck, editor tests, and production build
