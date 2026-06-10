# Changelog

All notable changes to this skill. Newest first. This project follows a loose [SemVer](https://semver.org/).

## 0.6.1 — 2026-06-10 — Report header: fix scrollbar-feedback flicker

### Fixed
- **`references/Report-Template.html` — wild header flicker at certain viewport widths.** The dossier did not
  reserve the vertical scrollbar gutter, so at widths where the content height landed at the viewport edge the
  scrollbar toggled on/off; each toggle changed the content width, and the header's `vw`-based `clamp()` padding
  and `h1` font-size reflowed on every toggle, producing a rapid flicker loop. Reserving the gutter
  (`html { overflow-y: scroll; scrollbar-gutter: stable; }`) holds the width constant and breaks the loop.

## 0.6.0 — 2026-06-10 — SKILL.md slimmed to a control plane (progressive disclosure)

### Changed
- **`SKILL.md` rewritten as a lean orchestrator: 733 → 244 lines (~16k → ~3.5k tokens, ~67% smaller).** It
  now holds the binding conventions, the workflow skeleton, the decision gates, and pointers - the long
  inline PowerShell blocks (encoding fix, pre-flight scans, packaging, logo fetch, MSI icon-table extraction,
  WinGet lifecycle, upload examples) moved into the reference guide and load on demand. No behaviour and no
  binding rule was dropped - all 11 conventions, the self-update flow, all phases, the troubleshooting table,
  and the anti-pattern list are preserved (verbatim where they are rules, relocated where they are code).
- **Autonomy:** intake is restructured from 8 mandatory questions into **4 decision gates**; everything
  researchable (version, installer type, silent/uninstall/repair switches, ProductCode, Intune issues) is now
  a researched, transparently-stated assumption instead of a question. `AskUserQuestion` is still the only way
  to ask, and the test/upload consents are unchanged.
- **Sub-agent architecture:** explicit Orchestrator / Researcher×3 / Builder / Reviewer roles with hard
  handoff gates (no packaging before a GREEN pre-flight; no upload before a GREEN SYSTEM test), wired to
  `superpowers:dispatching-parallel-agents` and `superpowers:requesting-code-review`.
- **Error handling:** a single **blockade protocol** (`PROBLEM / TRIED / OPTIONS 1,2`) replaces the scattered
  "stop and hand back" notes.
- **Frontmatter `description`** trimmed to triggering conditions only (no workflow summary), per Anthropic
  skill-authoring guidance.

### Added
- **`references/PSADTv4-Deployment-Guide.md` — Appendix I (WinGet packaging)** and **Appendix J (app-logo
  acquisition + verification)**: the WinGet discovery/provisioning/hook/detection code and the logo
  source-priority / Wikimedia / MSI icon-table / corner-pixel-verification code, lifted verbatim from the old
  SKILL.md so nothing is lost. The guide now spans Appendix A–J.

## 0.5.3 — 2026-06-09 — Guide: code inside code-fences is now English/ASCII

### Changed
- **`references/PSADTv4-Deployment-Guide.md`** — anglicized every German comment, string literal and
  placeholder that lived **inside PowerShell/text code fences** (and the inline-code placeholders in the
  Appendix F.1 table). Examples: `# Lokale Modulversion` → `# Local module version`,
  `"Neueste: … vom …"` → `"Latest: … from …"`, `<Hersteller>` → `<Vendor>`,
  `<Vorname Nachname>` → `<FirstName LastName>`, `<pfad-zur-ps1>` → `<path-to-ps1>`,
  `<prozess1>` → `<process1>`. Reason: snippets get copied verbatim into deployment scripts, where the
  binding rule is English + 7-bit ASCII — German comments/umlauts in a copied snippet are exactly the
  encoding/consistency failure class the pre-flight warns about.
- Deliberately **left unchanged**: the German explanatory **prose** of the guide and the **F.2 Company
  Portal description template** (legitimate end-user dossier text, `language.dossier` = German with real
  umlauts). No script/tooling code changed; `scripts/` and `Report-Template.html` were already compliant
  (German only as dossier output, ASCII-clean via HTML entities).

## 0.5.2 — 2026-06-08 — Always-on HTML package report (template + generator)

### Added
- **`scripts/New-PsadtReport.ps1`** (+ `tests/New-PsadtReport.Tests.ps1`, 9 cases): generates the package
  report as a single self-contained HTML file from the fixed template `references/Report-Template.html`.
  Data-driven via a `-Metadata` hashtable (or `-MetadataPath` JSON) with sane defaults for every field, so a
  minimal call still yields a complete report. Variable-length sections (return codes, cmdlets, deployment-hook
  bullets, pre-flight checks, SYSTEM-test rows, assignments) are built from arrays. The logo is embedded as a
  base64 data URI (fallback: a neutral initials tile), and free text is HTML-escaped (no injection).
- **`references/Report-Template.html`** — the fixed, tokenized report template. Fluent-2 styling, a **sticky
  header that shrinks on scroll** (with hysteresis to avoid flicker; disabled on mobile), the **real app logo
  in the header**, a **DE/EN language toggle** (decoupled, absolutely-positioned status block so switching
  never shifts the layout), and a client-side Markdown renderer so the description **preview is generated from
  its Markdown source**. The document stays browser-translatable.

### Changed
- **The HTML report is now BINDING — generated for EVERY package, whether or not it is uploaded to Intune.**
  It is one combined document: the **Intune dossier** (App Info, description, Program, Return Codes,
  Requirements, Detection, Dependencies, Supersedence, Assignments) **plus a technical package report**
  (deployment hooks, PSADT cmdlets used, pre-flight + SYSTEM-test results, logo/`.intunewin` verification).
  SKILL.md Phase 7 + conventions updated; Appendix F rewritten around the generator + the `-Metadata` key list;
  README Features/structure updated. New anti-patterns: never skip the report, never hand-assemble it.
- The report is bilingual and keeps **real umlauts** (the report is end-user output — the script-only ASCII
  rule does not apply; the template is ASCII via HTML entities, umlauts come from the description metadata,
  output is written UTF-8).

## 0.5.1 — 2026-06-06 — Robust commit-based self-update + README fix

### Changed
- **Self-update now decides by commit, not by the CHANGELOG version.** `Update-PsadtSkill.ps1` compares the
  local `HEAD` against `origin/<branch>` (git clone) or the GitHub commits-API sha against the recorded
  `tooling.skillCommit` (non-clone). This removes the `raw.githubusercontent.com` CDN cache lag and the
  circular "read the version from a file that can't know about a newer one." The CHANGELOG version is now
  shown only as context (`RemoteVersion` / `WhatsNew`); `Behind` reports how many commits behind a clone is.

### Fixed
- README project-structure tree compacted so it renders without horizontal scroll / truncated right-hand comments.

## 0.5.0 — 2026-06-06 — Skill self-update

### Added
- **`scripts/Update-PsadtSkill.ps1`** (+ Pester tests): checks GitHub for a newer skill version (compares the
  top `CHANGELOG.md` version), reports `LocalVersion` / `RemoteVersion` / `UpdateAvailable` / `WhatsNew`, and
  on confirmation updates **in place** — `git pull --ff-only` for a clone, otherwise overwrites only the
  tracked files (`SKILL.md`, `README.md`, `CHANGELOG.md`, `LICENSE`, `references/`, `scripts/`, `tests/`) from
  the branch zip. `config.json`, `secret.dpapi`, `tools/` and `docs/` are never touched.
- **SKILL.md**: a "Self-update" section + a non-blocking check at the start of Phase 0; triggers
  "update skill" / "/update-skill" / "psadt update" / "check for skill updates". The skill always **asks**
  before applying; an update check never blocks packaging.

## 0.4.0 — 2026-06-06 — WinGet support + certificate auth (PR #4)

Contributed by **@joakim-i** (PR #4), reviewed + hardened before merge.

### Added
- **WinGet packaging support** (strictly **opt-in**, never the default): `scripts/Get-WinGetModule.ps1`
  (self-heals the `PSAppDeployToolkit.WinGet` extension into `tools/` + the package), full SKILL.md lifecycle
  (intake Q2 option, Phase 2b discovery, install/uninstall/repair via `*-ADTWinGet*`, detection caveats,
  anti-patterns) and `tests/Get-WinGetModule.Tests.ps1`.
- **Certificate-based auth for Phase 7.5** — `New-PsadtEntraApp.ps1 -UseCertificate -CertThumbprint` uploads
  the cert's **public** key as an app `keyCredential`; `Get-GraphToken.ps1` signs an RFC 7523 JWT client
  assertion (RS256) with the private key (never exported). No secret at rest; config stores only the
  thumbprint. Client-secret path retained as fallback.
- **MSI Icon-table logo extraction** as a logo fallback (4-priority source list in Phase 7).

### Fixed
- Device-code polling `ScriptHalted` on the first poll (OAuth errors return a bare string, not a `.code`/`.message` object).

### Review hardening (applied on top of the PR before merge)
- Removed three junk `.gitignore` lines accidentally added by diff tooling.
- Dropped the unsubstantiated `offline_access` addition to `$WamScopes` (WAM is verified working without it; avoids
  MSAL reserved-scope risk; this one-shot bootstrap needs no refresh token).
- `Get-WinGetModule.ps1` now surfaces the **Authenticode trust state** of the third-party module (it executes on
  devices) and documents the supply-chain assumption.
- `Get-GraphToken.ps1` cert path: null-check `GetRSAPrivateKey` and dispose the RSA key.
- Made **WinGet's opt-in / never-default** rule explicit in SKILL.md (intake Q2 + anti-pattern).

## 0.3.2 — 2026-06-06 — Test-before-upload is now a binding gate

### Changed
- **Install + Uninstall must pass the Phase 5.5 SYSTEM test before any Phase 7.5 upload.** SKILL.md now makes
  this a binding prerequisite (Phase 7.5 callout, Phase 5.5 link, anti-pattern, conventions). If the test
  can't be run (no elevation / no VM), STOP before `-Execute` and hand the user the exact test command —
  never upload an untested package.

## 0.3.1 — 2026-06-06 — Script detection for non-MSI apps

### Added
- **PowerShell-script detection** in `Invoke-IntuneWin32Upload.ps1` via `-DetectionScriptPath` (+ optional
  `-DetectionRunAs32Bit`): builds a `win32LobAppPowerShellScriptRule` (ruleType=detection) for EXE / non-MSI
  installers (Vivaldi, Chrome-style, NSIS, Squirrel) that have no MSI ProductCode. Mutually exclusive with
  `-MsiProductCode`. Verified live by packaging + uploading Vivaldi 8.0.4033.44.

### Lessons baked in (do-not-repeat)
- A **detection** script rule accepts ONLY `ruleType, enforceSignatureCheck, runAs32Bit, scriptContent` —
  Graph rejects `displayName`/`runAsAccount`/`operationType`/`operator`/`comparisonValue` on detection rules
  ("The <X> property may not be set for Win32LobAppPowerShellScriptRule instances used for app detection").
- Reference guide **Appendix H.2** extended; SKILL.md Phase 7.5 + anti-patterns + troubleshooting updated.

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
