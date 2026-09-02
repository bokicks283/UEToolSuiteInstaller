# EXE Code-Signing Certificate Guide

This guide covers how to obtain, configure, and operate a certificate/signing service for `UEToolSuiteInstaller-<version>-win-x64.exe`.

Use this for public releases where users download the installer from GitHub Releases.

## 1) Choose A Signing Path

Use one of these three production options:

1. **OV code-signing certificate (PFX)**
   - Best default for small teams and straightforward CI integration.
   - Lower identity friction than EV, but SmartScreen reputation still builds over time.
2. **EV code-signing certificate**
   - Strongest identity posture and best trust signal.
   - Usually higher cost and stricter issuance/operational requirements.
3. **Microsoft Trusted Signing (service-based)**
   - No private key file in your repo/CI.
   - Good long-term option if your organization qualifies and wants cloud-backed signing.

For this repository's local release publisher, OV or EV with either a certificate-store thumbprint or a password-protected PFX is the direct fit.

## 2) Prepare Organization Identity

Before purchasing OV/EV, prepare:

- Legal organization name exactly as registered.
- Public business website and matching contact email domain.
- Business registration details (entity number, jurisdiction, address).
- A phone number reachable by verifier (often required for callback verification).

If you are an individual publisher, confirm the CA offers individual code-signing for your region before purchase.

## 3) Purchase The Certificate

1. Select a CA/reseller that offers Windows code-signing certificates.
2. Choose certificate class (OV or EV).
3. Complete identity verification with CA instructions.
4. For EV, follow token/HSM or cloud-signing delivery instructions from the CA.

Important: keep publisher name consistent across renewals. Frequent publisher name changes reduce trust continuity for users.

## 4) Receive And Install Certificate

### OV/EV PFX path (file-based)

After issuance, install/import the certificate on the secure machine used for releases and export a password-protected PFX if needed.

PowerShell import example:

```powershell
Import-PfxCertificate -FilePath C:\secure\codesign.pfx -CertStoreLocation Cert:\CurrentUser\My
```

Validate it exists:

```powershell
Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -match "Your Publisher Name" } |
  Select-Object Subject, Thumbprint, NotAfter
```

Export for local release use (if required):

```powershell
$password = Read-Host "PFX password" -AsSecureString
Export-PfxCertificate -Cert Cert:\CurrentUser\My\<thumbprint> -FilePath C:\secure\codesign-ci.pfx -Password $password
```

### Trusted Signing path (service-based)

Follow Microsoft onboarding to create the signing identity/profile and grant the release operator access. Keep this flow separate from PFX files.

## 5) Wire Into This Repo

### Local release signing and publishing

Using cert store thumbprint:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\Publish-GitHubRelease.ps1 `
  -Version 1.0.1 `
  -CertificateThumbprint <thumbprint>
```

Using PFX directly:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\Publish-GitHubRelease.ps1 `
  -Version 1.0.1 `
  -CertificatePath C:\secure\codesign-ci.pfx `
  -CertificatePassword "<password>"
```

## 6) Verify Signatures Before Release

Run on produced exe:

```powershell
Get-AuthenticodeSignature .\dist\UEToolSuiteInstaller-1.0.0-win-x64.exe | Format-List *
```

Expected:

- `Status` should be `Valid`.
- `SignerCertificate.Subject` should match your intended publisher identity.
- Timestamp should be present so signatures remain valid after cert expiry.

## 7) Operational Security Rules

- Never commit `.pfx` files, plaintext passwords, or exported secret files.
- Store original PFX in a controlled vault location, not in normal project folders.
- Restrict who can read/update signing secrets in GitHub.
- Rotate PFX passwords on staff changes.
- Keep signing machine/workflow access limited to release maintainers.

## 8) Renewal And Rotation Plan

Track these dates:

- Certificate expiration (`NotAfter`)
- Renewal start window (usually 30-60 days before expiry)
- Any CA revalidation deadlines

Recommended cadence:

1. Start renewal at least 45 days before expiry.
2. Import renewed cert in parallel with old cert.
3. Test local signing and CI signing on a pre-release tag.
4. Cutover secrets and keep old cert artifacts only as long as needed for rollback.

## 9) Expected User-Facing Behavior

- Signing improves trust and publisher identity.
- SmartScreen reputation is still reputation-based and may take time to improve for new binaries/publisher identities.
- Keep binary names, publisher identity, and release process consistent to build trust over repeated releases.

## 10) Quick Decision Matrix

- Use **OV + PFX** now if you want the fastest production-ready path using existing repo wiring.
- Use **EV** if you want stronger publisher identity posture and are ready for stricter operational requirements.
- Evaluate **Trusted Signing** if you want to avoid long-lived private key files in CI and can invest in service onboarding.
