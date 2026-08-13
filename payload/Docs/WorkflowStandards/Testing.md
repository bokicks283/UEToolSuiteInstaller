---
title: Testing
sidebar_position: 4
slug: /testing
---

# Tooling And Workflow Tests

The full UEToolSuite regression suites are maintained and run from the UEToolSuiteInstaller source repository. They are not included in the public installer or copied into Unreal projects.

## Installed Project Health Check

Installed projects retain one focused hook health check because `ue-tools init` uses it to verify Git hook plumbing:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/git-hooks/Test-Hooks.ps1
```

Use normal project build, editor, and docs checks for project-specific validation. Suite maintainers should run the relevant installer, upgrade, packaging, docs, and Unreal regression suites in the source repository before publishing a release.
