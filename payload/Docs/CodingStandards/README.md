---
title: Coding Standards
slug: /coding-standards
---

# Unreal C++ Coding Standards

This project follows Epic's Unreal C++ coding standard at all times.

Source of truth:

- https://dev.epicgames.com/documentation/en-us/unreal-engine/epic-cplusplus-coding-standard-for-unreal-engine

## Folder Purpose

`Docs/CodingStandards/` stores local snapshots and team-facing implementation notes for the official standard.

Use this folder so teammates can review the exact coding-standard source used at the time of a change.

The readable in-repo standard page lives at `Docs/CodingStandards/UnrealCppStandard.md`. Hidden capture metadata stays under `Docs/CodingStandards/Current/`.

## Required Layout

```text
Docs/CodingStandards/
|- README.md
|- UnrealCppStandard.md
|- Sync-UnrealCppStandard.ps1
|- Parse-UnrealCppStandard.ps1
|- Templates/
|  |- SOURCE.template.md
|- Current/
|  |- page.html
|  |- SOURCE.md
```

## Best Way To Bring The Full Web Page Into Repo

Use a raw HTML snapshot from the official Epic page, then keep metadata with it.

Why this is best:

- Captures the full source page, not partial summaries.
- Makes reviews deterministic when the web page changes later.
- Avoids manual copy/paste drift.

## Snapshot Workflow (Exact)

1. Run:
   - `pwsh -File Docs/CodingStandards/Sync-UnrealCppStandard.ps1`
2. This refreshes:
   - `Docs/CodingStandards/Current/page.html`
   - `Docs/CodingStandards/Current/SOURCE.md`
3. Fill all placeholders in `Docs/CodingStandards/Current/SOURCE.md`.
4. Parse the current snapshot into the readable docs page:
   - `pwsh -File Docs/CodingStandards/Parse-UnrealCppStandard.ps1`
5. This rewrites:
   - `Docs/CodingStandards/UnrealCppStandard.md`
6. Commit the refreshed current snapshot + docs page in a docs-only commit.

## Update Frequency

Refresh coding-standard snapshot:

- When upgrading Unreal engine version.
- When Epic updates the coding-standard page.
- At least once per quarter while active development is ongoing.
- At minimum, treat the snapshot as stale once it is older than six months and refresh it before relying on it as the current local reference.

## Codex Usage

- Agents should scrutinize `Docs/CodingStandards/` thoroughly before C++ or style-sensitive work.
- Start with this file, then inspect `Docs/CodingStandards/UnrealCppStandard.md`.
- Use `Docs/CodingStandards/Current/SOURCE.md` for hidden capture metadata and `Docs/CodingStandards/Current/page.html` for the exact raw source page.
- If the snapshot date in `Docs/CodingStandards/Current/SOURCE.md` is older than six months:
  1. Run `pwsh -File Docs/CodingStandards/Sync-UnrealCppStandard.ps1`
  2. Update `Docs/CodingStandards/Current/SOURCE.md`
  3. Run `pwsh -File Docs/CodingStandards/Parse-UnrealCppStandard.ps1`
  4. Commit the refreshed current snapshot and `Docs/CodingStandards/UnrealCppStandard.md` in docs scope

## Concrete Usage Example

Scenario: teammate introduces new class naming that is questioned in review.

1. Reviewer opens `Docs/CodingStandards/Current/`.
2. Reviewer checks official guidance in `page.html`.
3. Reviewer references snapshot date and source URL from `SOURCE.md`.
4. Reviewer and author use `Docs/CodingStandards/UnrealCppStandard.md` as the readable in-repo reference during discussion.
5. Team aligns code to standard and merges with traceable rationale.
