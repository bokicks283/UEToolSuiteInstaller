---
title: "CLI: art"
sidebar_position: 6
slug: /cli/art
---

# `ue art`

The `art` command is an interactive ArtSource directory creator. It ensures the canonical template exists, lets the user navigate an ArtSource domain, and creates new item directories from that template.

## Usage

```powershell
ue art [options]
ue art [ArtSourcePath]
```

## Options and arguments

| Input | Meaning |
|---|---|
| `-ArtSourceRelativePath <path>` | Select the ArtSource root. Relative values use the repository root; absolute values are allowed. |
| Positional path | Shorthand for the ArtSource root when no explicit path option was supplied. |
| `-RepoRoot <path>` | Select the repository through the shared launcher. |

The default ArtSource root is `ArtSource` under the repository.

## Examples

```powershell
ue art
ue art -ArtSourceRelativePath ArtSource
ue art "D:\Shared\ProjectArtSource"
```

## Interactive workflow

1. Validate the repository and selected ArtSource root.
2. Offer to create a missing ArtSource root.
3. Ensure `_Template/Source`, `_Template/Textures`, and `_Template/Exports` exist.
4. Let the user navigate available domain folders.
5. Validate the requested item name and reserved-name rules.
6. Create the new item from the canonical template.
7. Offer to create another item or exit.

## Help and automation boundary

```powershell
ue help art
ue art help
```

This is intentionally an interactive creator. For unattended scripts, create a separate reviewed automation flow rather than attempting to feed prompts implicitly.
