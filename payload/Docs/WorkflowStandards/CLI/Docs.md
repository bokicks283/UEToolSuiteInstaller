---
title: "CLI: docs"
sidebar_position: 4
slug: /cli/docs
---

# `ue docs`

The `docs` domain creates and organizes Markdown content, controls the local Docusaurus/editor runtime, validates the documentation site, and exposes website administration commands.

## Usage and help

```powershell
ue docs <command> [options]
ue docs help
ue docs help <command>
```

Use detailed help before advanced scaffolding or metadata operations:

```powershell
ue docs help new-page
ue docs help new-section
ue docs help theme
ue docs help site
```

## Content and navigation commands

| Command | Purpose |
|---|---|
| `new-section` | Create a section, `_category_.json`, and optional landing document. |
| `create-section` | Alias for `new-section`. |
| `new-page` | Create a root or section Markdown page with Docusaurus front matter. |
| `create-page` | Alias for `new-page`. |
| `reorder` | Move a page/section and shift sibling positions deterministically. |
| `migrate-sections` | Add `_category_.json` to legacy sections without changing their Markdown content. |
| `visibility` | Show or hide a page from navigation using Docusaurus `unlisted` front matter. |

Examples:

```powershell
ue docs new-section CLI -Title "CLI" -Position 5
ue docs new-page CLI Release -Title "CLI: release" -Position 9
ue docs reorder CLI/Release 8
ue docs migrate-sections --what-if
ue docs visibility CLI/Release hide
```

## Local runtime commands

| Command | Purpose |
|---|---|
| `start` | Start Docusaurus plus the editor API attached to the current terminal. |
| `start --background` | Start detached tracked Docusaurus/editor processes. |
| `status` | Inspect tracked server/editor state, URLs, and logs. |
| `stop` | Stop tracked background process trees and remove runtime state. |
| `check` | Validate docs metadata and run the Docusaurus production build. |
| `doctor` | Check Node/npm, dependencies, VS Code/TOC bridge, runtime health, and legacy sections. |
| `preview` | Deprecated background-start alias; use `start` or `start --background`. |

```powershell
ue docs start --port 3001
ue docs start --background --port 3001
ue docs status
ue docs stop
ue docs check
ue docs doctor
```

## Site administration

### Theme

```powershell
ue docs theme list
ue docs theme apply <id> [-LogoPath <path>] [-FaviconPath <path>] `
  [-SocialCardPath <path>] [--adopt-existing]
```

`theme list` reads the preset catalog. `theme apply` updates the active preset and configured branding while preserving unmanaged websites unless adoption is explicit.

### Ownership and overrides

```powershell
ue docs site status
ue docs site override list
ue docs site override set -Path <relative-path> -Mode <suite|project>
ue docs site override clear -Path <relative-path>
```

These commands inspect website ownership/install mode and persist per-file suite/project override decisions.

### Optional TOC bridge

```powershell
ue docs install-bridge
```

This installs the optional VS Code bridge. Markdown All in One is still required before automatic TOC requests can run.

## Docusaurus and npm pass-through

The domain exposes supported website package scripts including:

```text
build
clear
deploy
serve
swizzle
write-translations
write-heading-ids
typecheck
```

It also accepts arbitrary Docusaurus CLI arguments through:

```powershell
ue docs docusaurus <args...>
ue docs docusaurus docs:version 1.0.0 --skip-feedback
```

## Storage and authoring boundaries

- Author content in `Docs/`; keep the `website/` shell focused on rendering/runtime behavior.
- Use `_category_.json` and `sidebar_position` for navigation.
- Foreground `start` owns the current terminal; `status` and `stop` manage tracked background mode.
- Site ownership overrides affect installer updates and should be reviewed before changing a managed file from suite to project ownership.
