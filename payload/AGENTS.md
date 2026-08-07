# Managed payload instructions

Everything under `payload/` is installed into user Unreal Engine repositories.

## Compatibility and ownership

- Treat managed paths and file names as installation contracts.
- Preserve upgrade behavior and project-owned overrides.
- Check `payload/website-managed-file-index.json`, installer manifests, and packaging tests when adding, removing, or moving managed files.
- Do not rename a managed file solely because internal imports were updated.
- Keep runtime/generated state outside managed source paths unless the current installation contract requires otherwise.
- Avoid machine-specific absolute paths.

## Scope discipline

- Website-only fixes should not alter installer behavior.
- Docs API fixes should not alter unrelated Unreal tools.
- Installer changes need clean-install and update-path validation when relevant.
- Identify the authoritative source before editing copied or transformed files.
