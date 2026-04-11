---
title: Overview
sidebar_position: 1
slug: /
---

# Unreal Project Documentation

`Docs/` is the source of truth for team-facing project documentation.

This repo uses the portable UE tool suite for Git hooks, Unreal sync, docs automation, and local setup. Keep repo workflow, tooling, structure, and testing rules here with the code.

## Documentation Contract

- Update docs in the same branch as behavior changes.
- Use repository paths and real commands, not abstract placeholders.
- Keep Docusaurus content in `Docs/`; `website/` only renders it.
- Treat Confluence as retired for this project. New process and design docs belong in this repo.

## Read Order

1. [Setup](./Setup.md)
2. [Workflow](./Pipeline/README.md)
3. [Testing](./Testing.md)
4. [Coding Standards](./CodingStandards/README.md)
5. [Docusaurus Setup](./DocsSite/Docusaurus-Setup.md)
6. [Codex Context](./Codex/README.md)

## High-Level Ownership

- `Docs/`: source markdown and process docs
- `AGENTS.md`: short repo-wide Codex routing instructions
- `website/`: Docusaurus app used to preview and publish `Docs/`
- `Scripts/`: automation, hooks, Unreal helpers, and test harnesses
- `Plugins/`: project and third-party plugin roots
- `ArtSource/`: optional DCC source files and import staging
