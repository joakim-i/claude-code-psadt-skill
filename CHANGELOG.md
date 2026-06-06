# Changelog

All notable changes to this skill. Newest first. This project follows a loose [SemVer](https://semver.org/).

## 0.3.0 — 2026-06-06 — Direct Intune upload (Microsoft Graph)

### Added
- **Direct Intune upload** — `scripts/Invoke-IntuneWin32Upload.ps1` (Phase 7.5): self-contained raw-Graph
  upload of a `.intunewin` as a `win32LobApp` (app + logo, **no group assignment**). 8-step flow: parse
  `.intunewin` → app-only token → read-only permission probe → idempotency check → build body →
  create/update → content version → register file → poll SAS → block-blob upload (HttpClient) → commit →
  activate → categories → optional supersedence. Read-only **dry-run by default**; `-Execute` performs the
  writes.
- **WAM Entra-app bootstrap** — `scripts/New-PsadtEntraApp.ps1` now signs the admin in via **WAM** (Windows
  Web Account Manager broker) using MSAL.NET (auto-located or downloaded to `%LOCALAPPDATA%\PsadtIntune\msal`),
  with automatic **device-code fallback**. Creates the `PSADT Intune Upload` app, grants + admin-consents
  `DeviceManagementApps.ReadWrite.All`, creates a client secret, and DPAPI-stores it.
- **App-only Graph token helper** — `scripts/Get-GraphToken.ps1` (client-credentials; DPAPI secret decrypted
  in-memory only).
- **Full App-information metadata** — the uploader fills `displayName, description, publisher, developer,
  owner, displayVersion, informationUrl, privacyInformationUrl, notes, largeIcon, msiInformation,
  returnCodes, rules, installExperience` instead of the bare minimum.
- **Coexistence-safe versioning** — `-OnExisting CreateNewCoexist` (default) uploads a new version as a
  **separate** app and never touches the existing one; `-UpdateAppId` for explicit in-place update;
  `-SupersedesAppId` wires "new replaces old". The script issues only POST/PATCH — **never DELETE**.
- **Logo guard** — refuses the PSADT default `Assets\AppIcon.png` (SHA256 blocklist) unless
  `-AllowDefaultLogo`; warns when no logo is supplied.
- **Reference guide Appendix H** — the hard-won Graph upload lessons (see below). README + SKILL.md updated;
  `references/app-registration.md` manual portal fallback.

### Fixed
- **Repair `-FilePath`→`-ProductCode`** — the `Repair-ADTDeployment` MSI example (and the 7-Zip package) used
  `-FilePath '{GUID}'`, which PSADT 4.1.x rejects with `InvalidFilePathParameterValue` (exit 60001). The
  Uninstall fix had been applied earlier but Repair was missed — now corrected in SKILL.md and the guide.

### Lessons baked in (do-not-repeat)
- Use the unified **`rules`** collection (`win32LobAppProductCodeRule`, `ruleType=detection`), **not** the
  legacy `detectionRules` — the current backend rejects the latter ("must have at least one detection rule").
- **`@odata.type` must serialise first** in polymorphic sub-objects (`[ordered]@{}`).
- Upload the encrypted blob with **HttpClient/ByteArrayContent**, not `Invoke-RestMethod -Body <byte[]>`
  (binary corruption → `commitFileFailed`).
- Write win32LobApp metadata on **`/beta`** — `/v1.0` silently drops `displayVersion` and others.
- **Never the default PSADT logo** as the app logo; `IsAlphaPixelFormat` is not proof of transparency.
- **Never auto-impose** category / branded notes / featured / group assignment; **never delete** an older
  version.

## 0.2.0 — Automated SYSTEM test loop

- **Automated SYSTEM test loop** (`scripts/Invoke-PsadtSystemTest.ps1`, Phase 5.5): install → uninstall →
  reinstall the package as the SYSTEM account via `Invoke-CommandAs`, with agent-driven auto-fix until green
  or a max-iteration cap. Opt-in; elevated session required.
- Phase 8 now prefers `Invoke-CommandAs -AsSystem` for SYSTEM-context testing (PsExec kept as a fallback).
- Self-re-exec to Windows PowerShell 5.1 when run under pwsh 7 (PSScheduledJob is 5.1-only). See guide
  Appendix G (2026-06-05).

## 0.1.0 — Initial release

- Guided PSADT v4 → Intune Win32 lifecycle: intake, autonomous research, scaffolding, all three deployment
  types (Install/Uninstall/Repair), pre-flight checks, packaging, dossier + logo, guided testing,
  troubleshooting.
- First-run setup writing a machine-local `config.json` (paths, language, author).
- Self-healing prerequisites: PSAppDeployToolkit module (PSGallery) and `IntuneWinAppUtil.exe` (auto-download
  + version check).
- HTML dossier document with a Markdown app-description block (the Intune description field is Markdown-only).
- English skill + reference guide; MIT licensed.
