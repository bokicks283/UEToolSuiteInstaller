# Local docs editor contracts

## Path tokens

- Browser/API path tokens are relative to `Docs/`.
- API tokens use `/`.
- Empty string represents Docs root only where explicitly allowed.
- Display labels are not filesystem identifiers.
- Windows comparison is case-insensitive.
- Path normalization must produce the same result in TypeScript and PowerShell.
- Paths containing spaces and paths without spaces behave identically.
- Mutations must not accidentally target outside the intended repository docs tree.

## Content editing

- Saves use optimistic concurrency.
- A stale `expectedHash` does not write.
- Failed saves preserve the browser draft.
- Unsupported MDX is never silently stripped or downgraded.
- A no-op editor session does not rewrite the document.
- Intentional normalization must be documented and fixture-tested.
- Front matter and body are distinct regions.
- Newline style and unrelated content should be preserved where feasible.

## Structure editing

- A section cannot move into itself or a descendant.
- Destination collisions are rejected before mutation.
- All affected references are known before disk mutation.
- Stable public routes/slugs are preserved unless explicitly changed.
- Domain ownership remains unique and consistent.
- Sidebar positions remain deterministic.
- A staged structure save is atomic or safely resumable.
- Failed structural changes leave the pre-operation state or a clearly documented recoverable state.
- Retrying a failed save must not duplicate already-applied operations.

## Domain and navigation

- TypeScript and PowerShell agree on normalization, ownership, exclusions, and doc IDs.
- `_category_.json` links resolve after moves.
- Navbar/sidebar `docId` references resolve after moves.
- Markdown links to moved content remain valid.
- Landing documents are not duplicated as ordinary children.
- excluded directories/templates stay excluded.

## Runtime lifecycle

- Only one discovery sweep is active.
- Known proxy/runtime descriptor is tried before broad fallback.
- Discovery backs off after failure.
- Static docs rendering remains usable without the editor API.
- Runtime state is cleaned on normal shutdown.
- Stale state is detected and repaired.
- Non-default ports work reliably.

## Installation

- Added managed files are represented in the appropriate manifest/index.
- Upgrades respect project-owned override policy.
- Generated website output is not a managed source file unless explicitly documented.
