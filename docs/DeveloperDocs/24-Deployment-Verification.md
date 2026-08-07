# Deployment Verification

This file focuses on exact verification steps a maintainer can run against the current repository and the reference installed repo:

- source repo: `C:\Users\Rim28\Projects\UEToolSuiteInstaller`
- reference install: `C:\Users\Rim28\Projects\cppCozyRPG`

## Read-only verification first

### 1. Source to payload parity

Goal: confirm the authored installer and payload inputs are internally consistent.

```powershell
Set-Location C:\Users\Rim28\Projects\UEToolSuiteInstaller
Get-Content .\payload\ue-tool-suite.manifest.json -Raw
Get-ChildItem .\payload\Scripts\UETools
Get-ChildItem .\payload\website
```

Healthy result:

- manifest paths correspond to real payload folders/files
- key website files exist
- expected modules exist

### 2. Source to installed source parity

Use file hashes for high-value files:

```powershell
Get-FileHash `
  .\payload\Scripts\UETools\UEToolSuite.Docs.psm1, `
  C:\Users\Rim28\Projects\cppCozyRPG\Scripts\UETools\UEToolSuite.Docs.psm1

Get-FileHash `
  .\payload\Scripts\UETools\DocsEditorApiHost.ps1, `
  C:\Users\Rim28\Projects\cppCozyRPG\Scripts\UETools\DocsEditorApiHost.ps1

Get-FileHash `
  .\payload\website\src\theme\authoring\runtimeDiscovery.ts, `
  C:\Users\Rim28\Projects\cppCozyRPG\website\src\theme\authoring\runtimeDiscovery.ts
```

Healthy result:

- source hash equals installed hash for each compared file

### 3. Source build to installed build parity

This verifies the built website contract, not just source files.

```powershell
Get-ChildItem .\payload\website\build -Recurse -File | Sort-Object FullName | Select-Object FullName,Length
Get-ChildItem C:\Users\Rim28\Projects\cppCozyRPG\website\build -Recurse -File | Sort-Object FullName | Select-Object FullName,Length
```

For stronger parity:

```powershell
$source = Get-ChildItem .\payload\website\build -Recurse -File | ForEach-Object {
  [pscustomobject]@{ Path = $_.FullName.Substring((Resolve-Path .\payload\website\build).Path.Length); Hash = (Get-FileHash $_.FullName).Hash }
}
$installed = Get-ChildItem C:\Users\Rim28\Projects\cppCozyRPG\website\build -Recurse -File | ForEach-Object {
  [pscustomobject]@{ Path = $_.FullName.Substring((Resolve-Path C:\Users\Rim28\Projects\cppCozyRPG\website\build).Path.Length); Hash = (Get-FileHash $_.FullName).Hash }
}
Compare-Object $source $installed -Property Path,Hash
```

Healthy result:

- no differences for managed build assets

## Runtime verification

### 4. Runtime descriptor to live API parity

```powershell
Get-Content C:\Users\Rim28\Projects\cppCozyRPG\website\static\ue-tools\editor-runtime.json -Raw
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:38473/health | Select-Object -ExpandProperty Content
```

Healthy result:

- `applicationId`, `apiVersion`, `repoRoot`, `docsRoot`, and `processId` agree between descriptor and health

### 5. API process identity

```powershell
$health = Invoke-RestMethod http://127.0.0.1:38473/health
Get-Process -Id $health.processId | Select-Object Id,ProcessName,Path,StartTime
```

Healthy result:

- process exists
- process path is a PowerShell host
- process start time is compatible with the descriptor/health timestamps

### 6. Port ownership

```powershell
Get-NetTCPConnection -LocalPort 38473 -State Listen | Select-Object LocalAddress,LocalPort,OwningProcess
```

Healthy result:

- `OwningProcess` matches the process id from `/health`

### 7. Served-bundle parity

Use this only when the docs site is already running:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000 | Select-Object -ExpandProperty Content
```

Check that the HTML references the installed build assets you expect. If the installed source matches but the served bundle does not, the likely drift is between installed source and installed build output.

## Functional authoring verification

### 8. Correct authoring controls

State-changing command, not read-only:

```powershell
Set-Location C:\Users\Rim28\Projects\cppCozyRPG
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs status
```

Healthy result:

- docs server and editor API report running
- log paths exist
- site pages that have valid source tokens can show authoring UI

### 9. Domain/sidebar/navbar behavior

Read-only filesystem checks:

```powershell
Get-Content C:\Users\Rim28\Projects\cppCozyRPG\Docs\_domains.json -Raw
Get-Content C:\Users\Rim28\Projects\cppCozyRPG\website\domainCatalog.ts -TotalCount 40
```

Healthy result:

- domain definitions exist
- installed website still uses the same catalog logic as source

## Validation categories

| Procedure | Read-only | Notes |
|---|---|---|
| hash comparison | Yes | safest first step |
| descriptor/health comparison | Yes | requires running API |
| port/process ownership | Yes | requires running API |
| served HTML inspection | Yes | requires running docs site |
| `ue-tools docs status` | Mostly | may clean stale state internally |
| reinstall/update | No | use only after evidence capture |

## Evidence-preserving order

1. Capture `git status` in the source repo.
2. Capture installed hashes.
3. Capture runtime descriptor.
4. Capture `/health`.
5. Capture port/process ownership.
6. Capture stdout/stderr logs if runtime is unhealthy.
7. Restart or reinstall only after the above evidence exists.
