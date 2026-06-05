---
title: Git Workflow Standards
sidebar_position: 2
slug: /workflow/git-workflow-standards
---

# Git Workflow Standards

This page is the source of truth for repo git standards:

- branch naming
- start-of-day sync
- branch cleanup before review
- PR creation and merge policy
- guarded binary conflict handling

If a workflow rule is mainly about branches, commits, rebases, merges, PRs, or conflict resolution, it belongs here.

## Goals

This repo wants two things at the same time:

- one clean review commit per finished piece of work
- a real merge edge back into `main` so the git graph stays readable

The standard workflow is:

1. do normal work on a focused branch
2. when the work is finished, run one interactive rebase onto current `main`
3. squash the branch down to one polished commit during that rebase
4. open the PR from that cleaned-up branch
5. merge the PR with a normal merge commit

Do not use GitHub's `Squash and merge` or `Rebase and merge` options for final integration.

## Branch Naming

- Feature work: `feat/<scope>`
- Fix work: `fix/<scope>`
- Tooling and structure work: `chore/<scope>`

Examples:

- `feat/guest-panic-loop`
- `fix/ghost-possession-reset`
- `chore/docs-docusaurus-bootstrap`

## Start-Of-Day Sync

Run these in order:

```powershell
git pull --ff-only
git lfs pull
git status --short
```

Only start work when the output is clean or intentionally understood.

## Required Git Practices

- Keep branch scope focused.
- Keep docs updates in the same branch as workflow or policy changes.
- Use one interactive rebase onto current `main` before opening or finalizing a PR.
- Collapse the finished branch to one polished commit during that rebase.
- Use `git push --force-with-lease` when pushing a rebased branch.
- Use `git ours`, `git theirs`, and `git conflicts` for guarded binary conflict handling.
- Write validation steps clearly in the PR description.
- Delete stale work branches after merge when they are no longer useful.

## Do Not

- Mix large content migrations with unrelated gameplay work.
- Commit `Saved/`, `Intermediate/`, `DerivedDataCache/`, or `Binaries/`.
- Resolve Unreal binary conflicts by hand-editing files.
- Use GitHub `Squash and merge` for final integration.
- Use GitHub `Rebase and merge` for final integration.
- Force-push rebased work with plain `--force` when `--force-with-lease` is available.

## Required Branch Cleanup And PR Flow

This is the default repo workflow for finishing a branch.

Why this is the standard:

- the branch stays easy to review
- `main` still gets a real merge edge
- the final history is clean without relying on GitHub squash merge
- the work branch itself becomes the PR branch, so there is no second cleanup branch to maintain

### 1. Finish the work branch

Work normally on a focused branch such as:

- `feat/<scope>`
- `fix/<scope>`
- `chore/<scope>`

Example:

```powershell
git checkout -b fix/ue-tools docs
```

The branch can have as many commits as needed while the work is in progress.

### 2. Validate before cleanup

Run the checks that match the change before rewriting the branch history.

Example for docs or tooling work:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-DocsTools.ps1
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File Scripts/ue-tools.ps1 -RepoRoot . docs check
```

### 3. Run one interactive rebase onto current `main`

```powershell
git fetch origin
git checkout <work-branch>
git rebase -i origin/main
```

This does all three cleanup tasks in one operation:

- updates the branch against current `main`
- lets you squash the branch to one commit
- lets you rewrite the final commit message

In the rebase todo list:

- mark the first commit as `reword`
- mark every later commit as `fixup`

This keeps one final commit and folds the rest into it without keeping the intermediate messages.

If conflicts happen, resolve them, continue the rebase, and rerun the relevant validation if needed.

### 4. Write the final commit message

When the rebase prompts for the remaining commit message:

- first line: short summary
- body: key behavior changes, migration notes, and validation when useful

The goal is one polished commit that is ready to live on the branch and in the PR history.

### 5. Push the rewritten branch safely

```powershell
git push --force-with-lease
```

Use `--force-with-lease`, not plain `--force`.

### 6. Open or update the PR from the cleaned branch

```powershell
gh pr create --base main --assignee @me
```

If the PR already exists, just push the rebased branch and update the PR description if needed.

If you want to script the PR more explicitly:

```powershell
gh pr create --base main --title "<title>" --body-file <path-to-body.md> --assignee @me
```

### 7. Merge with a real merge commit

Use merge only:

```powershell
gh pr merge <pr-number> --merge --delete-branch
```

On GitHub.com, choose:

- `Create a merge commit`

Why:

- `Squash and merge` creates a single-parent commit, so the branch does not visibly merge back into `main` in the graph.
- `Rebase and merge` also removes the merge edge.
- `Create a merge commit` keeps the graph honest while the branch itself has already been cleaned to one commit.

### 8. Prune local leftovers

After the PR is merged:

```powershell
git checkout main
git pull --ff-only
git branch -D <work-branch>
git fetch --prune
```

## Conflict Rule During Rebase

If the branch hits conflicts while rebasing:

1. inspect the conflict state
2. resolve the intended side
3. confirm the conflict state again
4. continue the rebase

Example:

```powershell
git conflicts status
git ours "Content/**/*.uasset"
git theirs "Content/Maps/**/*.umap"
git conflicts status
git rebase --continue
```

## Decision Rule

Use this rule:

- branch still in progress: commit as needed, do not prematurely rewrite it
- branch finished and ready for PR: run one interactive rebase onto `origin/main` and collapse the branch to one commit there
- PR ready to merge: use `Create a merge commit` / `gh pr merge --merge`

## Worked Example

Goal: move Unreal assets under a new content folder and document the policy change.

1. Create `chore/guest-reaction-restructure`.
2. Move the assets in Unreal Editor.
3. Fix redirectors in the moved folder.
4. Update the project structure docs if the canonical layout changed.
5. Run the relevant smoke test in editor.
6. Commit only the moved assets and docs updates while the work is in progress.
7. When the work is finished, run one interactive rebase onto `origin/main`, squash the branch there, and open the PR from that cleaned branch.
