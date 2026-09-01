---
title: "CLI: git"
sidebar_position: 8
slug: /cli/git
---

# `ue git`

The `git` domain provides guarded binary conflict helpers for Unreal assets and other configured binary paths during merges and rebases.

## Usage

```powershell
ue git ours <pattern> [pattern...]
ue git theirs <pattern> [pattern...]
ue git <status|sync|continue|abort|restart|help> [options]
```

Installed repositories also configure convenience aliases such as `git ours`, `git theirs`, and `git conflicts`.

## Commands

| Command | Purpose |
|---|---|
| `ours` | Resolve matching guarded conflicts by choosing the human-meaning OURS side. |
| `theirs` | Resolve matching guarded conflicts by choosing the human-meaning THEIRS side. |
| `status` | Show merge/rebase context, required guarded files, and approval state. |
| `sync` | Recompute the required guarded set and refresh context-bound ledgers. |
| `continue` | Continue a rebase only after the binary guard requirements are satisfied. |
| `abort` | Abort the active merge or rebase; no-op when neither is active. |
| `restart` | Abort and attempt to rerun the detected merge/rebase operation. |
| `help` | Show the guarded conflict workflow help. |

During rebases, the implementation flips Git's low-level ours/theirs meaning so the command names continue to match human intent.

## Options

| Option | Meaning |
|---|---|
| `-v`, `--verbose` | Print detailed file lists and internal context information. |
| `-se`, `--skip-editor`, `-SkipEditor` | Skip commit-message editing during guarded rebase continuation. |

## Patterns

Patterns use PowerShell `-like` wildcard semantics, not Bash glob semantics. Quote any value containing `*` or `**`.

```powershell
ue git ours "**/*.uasset"
ue git theirs "Content/Test/*.png"
ue git status --verbose
ue git continue --skip-editor
```

## Safe workflow

1. Run `ue git status` to identify the active context and required guarded files.
2. Resolve each binary intentionally with `ours` or `theirs`.
3. Run `ue git sync` if the Git context or required set changed.
4. Re-run status and confirm approvals.
5. Use `continue` only when the guard reports the context is ready.

`restart` and `abort` alter active Git operations. Inspect status and preserve unrelated working-tree changes before using them.

## Help

```powershell
ue help git
ue git help
git conflicts help
```
