# Local docs editor triage checklist

## Capture

- source token
- browser route
- page/section/domain
- destination parent/domain
- spaces or no spaces
- root or nested
- pending mutation order
- selected API base
- runtime descriptor/state
- request/response
- filesystem before/after
- Docusaurus reload/build result

## Frequent root-cause classes

- stale path after queued move
- browser path normalization differs from PowerShell
- route/docId differs from filesystem path
- partial sequential structure save
- stale Docusaurus registry/cache after move
- unsupported Markdown transformed by Tiptap
- draft hash mismatch
- domain ownership differs between languages
- old runtime descriptor or wrong port
- orphaned or partially started process
- generated bundle mistaken for source
