# Security and Trust Boundaries

## Current security posture

Confirmed behavior:

- The Docs Editor API binds to `127.0.0.1`, not `0.0.0.0`.
- There is no authentication or authorization layer in `DocsEditorApiHost.ps1`.
- The frontend trusts local authoring only after runtime descriptor and `/health` identity checks succeed.
- The API writes directly into the active repository's `Docs/` and `website/`-related files.

This is a local developer tool security model, not a hardened service model.

## Trust boundaries

| Boundary | Current protection | Missing protection | Evidence |
|---|---|---|---|
| browser frontend -> runtime descriptor | JSON schema validation and expected field checks | no signature or origin proof beyond same served site path | `loadRuntimeDescriptor`, `validateRuntimeConfigPayload` |
| browser frontend -> API | application id, version, repo root, docs root, process id, capability checks | no auth token, no TLS, no origin-bound secret | `probeApiBase`, `compareRuntimeIdentity` |
| API -> filesystem | path-token normalization and route-specific validation | no separate sandbox beyond repo-root logic | `DocsEditorApiHost.ps1` |
| installer -> target repo | explicit target repo path, managed ledgers, marker-managed text blocks | no global rollback transaction | `Install-UEToolSuite.ps1` |
| lifecycle -> running process | PID tracking plus health validation | another local process could still compete for the same port | `Get-DocsEditorApiStatus`, `Start-DocsEditorApiBackground` |

## Path and traversal defenses

Confirmed behavior:

- frontend path helpers normalize slashes and strip repo-relative prefixes
- route handlers require known fields like `path`, `domainPath`, `sourcePath`, or `targetPath`
- docs/content routes operate in terms of Docs path tokens rather than arbitrary raw absolute paths

Unresolved:

- this documentation pass did not prove every route's full traversal-defense strategy line by line
- no separate allowlist language exists beyond current repo/docs-root validation and helper normalization

## Runtime descriptor trust model

`runtimeDiscovery.ts` treats `editor-runtime.json` as a hint, not final authority.

Confirmed checks after reading the descriptor:

- API URL is normalized
- `/health` must answer
- application id must be `UEToolSuiteDocsEditorApi`
- version must be `2`
- repo root and docs root must match
- process id must match
- capability booleans must match

This reduces stale-descriptor errors, but it is not equivalent to authentication.

## Port ownership and process identity

Confirmed behavior:

- startup refuses the default port if a different or unverified process already owns it
- status and stop logic use tracked PIDs plus health probes
- the frontend can reject a healthy-looking process if its project identity differs

Known risk:

- another local process could still present a compatible health payload if it intentionally mimicked the contract

## CORS and proxy behavior

Confirmed behavior:

- Docusaurus dev mode proxies `/__ue_docs_api__` to `http://127.0.0.1:38473`
- the frontend can also probe the direct local URL as a fallback candidate

Absent protections:

- no cross-user browser isolation model
- no bearer token or nonce between frontend and API

## Write boundaries

| Writer | Paths it can mutate | Evidence |
|---|---|---|
| installer | installed `Scripts/`, `Docs/`, `website/`, managed root text files | manifest + installer copy/remove logic |
| Docs Editor API | Docs pages, section metadata, domain metadata, site/theme/branding/override files | route handlers in `DocsEditorApiHost.ps1` |
| docs CLI | Docs files, runtime state, optional bridge files, website theme files | `UEToolSuite.Docs.psm1` |

## Risks if exposed beyond localhost

If the API were reachable beyond loopback, the current code would permit unauthenticated filesystem mutations in the active repository. The loopback bind is therefore a material boundary, not a convenience.

## Practical maintainer guidance

- Treat the local API as trusted only on the machine where it was started.
- Investigate port conflicts before forcing restarts.
- Preserve runtime descriptor, stdout, and stderr logs before cleanup when debugging.
- Do not claim the docs authoring stack is secure for remote or multi-user exposure. The current codebase does not support that claim.
