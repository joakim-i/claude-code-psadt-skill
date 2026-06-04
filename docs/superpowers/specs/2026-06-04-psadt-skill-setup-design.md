# Design: First-Run Setup & Optional Intune Upload for the psadt-deploy Skill

- **Date:** 2026-06-04
- **Author:** Patrick Taubert, PHAT Consulting GmbH (with Claude Code)
- **Status:** Design approved. **Delivery scope:** the optional Intune direct upload (§5.4–5.7, §6.3) is
  **deferred to a future release**; the first version ships setup + config, self-healing prerequisites,
  HTML deliverables, and the English translation. See the implementation plan for the exact task split.
- **Applies to:** `~/.claude/skills/psadt-deploy/` (repo: `pt1987/claude-code-psadt-skill`)

> Language note: Everything in this repository is written in **English** (README, `SKILL.md`,
> reference guide, this spec). The **only deliberate exception is generated deliverable content**:
> the Intune dossier and the Company-Portal app description are produced in the configured dossier
> language (`language.dossier`, **default German** with real umlauts) for the end user — this is a
> config value, not a hard rule, so a user may set it to EN. Deployment scripts stay English/ASCII.

## 1. Problem / Motivation

The `psadt-deploy` skill currently hard-codes core conventions directly in the prose of `SKILL.md`:

- Output path `c:\Temp\PSADTv4\Output\`
- IntuneWinAppUtil at `C:\Tools\IntuneWinAppUtil.exe`
- Language split (dossier DE / scripts EN)
- Author `Patrick Taubert, PHAT Consulting GmbH`

These values must match the local machine/environment but are not configurable in one place. The
skill is also missing a **direct upload capability to Intune** entirely — including the required
Entra app registration — and it expects the user to provision the content-prep tool by hand.

**Goal:** A one-time **Setup (Phase 0)** that lifts these values into a persistent config, a
skill-managed **content-prep tool** (auto-download + version check), and an **optional** Intune
direct-upload capability via Microsoft Graph.

## 2. Decisions (confirmed by the user)

| Topic | Decision |
|---|---|
| Config location | In the skill folder: `~/.claude/skills/psadt-deploy/config.json` |
| Secret storage | DPAPI-encrypted (CurrentUser) in `secret.dpapi`, separate from the config |
| Setup trigger | Both: auto on missing/incomplete config AND explicitly re-triggerable ("psadt setup") |
| Upload mode | Skill uploads itself (Graph), but **optional** and declinable per run |
| Auth method | Client secret (tenant id + client id in config.json, secret via DPAPI) |
| Architecture | Hybrid: helper scripts for security/complex parts, wizard/customizing stays model-driven |
| Content-prep tool | Skill-managed: auto-download into `tools/`, version-checked against the official MS repo |
| PSADT module | Skill-managed: auto-installed from PSGallery if missing, version-synced — never a manual prerequisite |
| Deliverable format | New convention: deliverables in **HTML** instead of Markdown (full dossier) |
| Repo language | Everything in the repo is **English**; only generated dossier/description output is German |
| License | MIT (`LICENSE`, author Patrick Taubert / PHAT Consulting GmbH) |
| Author field | Structured in config (`person` + `company`), asked separately in setup |

**Key constraint:** The upload stays **fully optional**. Not every tenant allows registering an app
(e.g. a customer tenant). `uploadEnabled: false` (or a missing `intune` block) is a first-class
state — the skill then falls back to the existing manual flow (`.intunewin` + dossier, uploaded by
hand in the Admin Center).

**Not a plugin:** It stays a skill with bundled helper files (`scripts/`, `references/`, `tools/`),
no conversion into a Claude Code plugin. Packaging as a plugin later would be a separate step.

## 3. File structure

```
~/.claude/skills/psadt-deploy/   (== repo root)
├─ SKILL.md                          (Markdown; gains Phase 0 + upload phase + HTML switch; English)
├─ README.md                         (English, modeled on awesome-claude-skills single-skill style)
├─ LICENSE                           (MIT)
├─ .gitignore                        (excludes config.json, secret.dpapi, tools/)
├─ config.json                       (NOT committed; created by setup)
├─ secret.dpapi                      (NOT committed; DPAPI blob, secret only)
├─ tools/
│  └─ IntuneWinAppUtil.exe           (NOT committed; auto-downloaded + version-checked)
├─ references/
│  ├─ PSADTv4-Deployment-Guide.md    (the reference guide, appendices A–G; English)
│  └─ app-registration.md            (Entra app-registration walkthrough; English)
└─ scripts/
   ├─ Get-PsadtConfig.ps1            (reads config.json -> object; reports missing fields)
   ├─ Set-PsadtConfig.ps1           (writes/updates config.json; DPAPI-encrypts secret)
   ├─ Get-PsadtModule.ps1           (ensures PSAppDeployToolkit module installed + version-synced)
   ├─ Get-IntuneWinAppUtil.ps1      (ensures tool present + current vs official MS repo)
   ├─ Invoke-IntuneWin32Upload.ps1  (Graph upload: token -> app -> content -> blob -> commit -> assign)
   └─ Test-PsadtSetup.ps1           (auth smoke test: acquire token + 1 Graph GET)
```

`config.json`, `secret.dpapi` and `tools/` are machine/user-local runtime state and are NOT
distributed with the skill. Setup treats them as "create-if-missing".

## 4. Config schema (`config.json`)

```json
{
  "version": 1,
  "paths": {
    "packageRoot":      "c:\\Temp\\PSADTv4",
    "outputRoot":       "c:\\Temp\\PSADTv4\\Output",
    "intuneWinAppUtil": "<skillDir>\\tools\\IntuneWinAppUtil.exe"
  },
  "tooling": {
    "intuneWinAppUtilVersion": "v1.8.7",
    "intuneWinAppUtilSha":     "<git-blob-sha>"
  },
  "language": { "script": "EN", "dossier": "DE" },
  "author":   { "person": "Patrick Taubert", "company": "PHAT Consulting GmbH" },
  "intune": {
    "uploadEnabled":     true,
    "tenantId":          "<guid>",
    "clientId":          "<guid>",
    "secretRef":         "secret.dpapi",
    "defaultAssignment": "available"
  }
}
```

**Field rules:**

- Covers the four user-requested values: storage (`paths.packageRoot`/`outputRoot`), language
  (`language.script`/`dossier`), tool path (`paths.intuneWinAppUtil`), upload + app-reg (`intune.*`).
  Plus `author` (previously hard-coded) and `tooling` (tool version tracking).
- **The secret is NEVER in `config.json`** — only `tenantId`/`clientId`. `secretRef` points to the
  DPAPI file.
- `author` is structured; the skill composes `AppScriptAuthor = "<person>, <company>"`.
- `paths.intuneWinAppUtil` defaults to the skill-managed `tools/IntuneWinAppUtil.exe`.
- `tooling.intuneWinAppUtilVersion`/`Sha` record the installed tool tag + blob sha to detect updates.
- `intune.defaultAssignment` ∈ `{ "available", "required", "none" }`.
- If the `intune` block is absent OR `uploadEnabled: false`, upload is disabled.

## 5. Components

### 5.1 `Get-PsadtConfig.ps1`
- Reads `config.json`, returns a PowerShell object.
- Validates completeness; returns a **list of missing/invalid fields** so the wizard asks only those.
- Does not decrypt the secret itself (separate path only at upload time).

### 5.2 `Set-PsadtConfig.ps1`
- Writes/updates `config.json` (partial updates, schema-validated).
- Takes the secret as a parameter and **DPAPI-encrypts** it (scope CurrentUser) to `secret.dpapi`.
  The secret is never written to `config.json` or logs and never returned.

### 5.3 `Get-PsadtModule.ps1`
- Ensures the **PSAppDeployToolkit** module is available; installing it must never be a manual hurdle.
- If missing: `Install-Module PSAppDeployToolkit -Scope CurrentUser -Force -AllowClobber` from the
  PowerShell Gallery (ensures NuGet provider / trusts PSGallery non-interactively as needed).
- If present: compares installed vs latest (the existing research step) and offers `Update-Module`
  before scaffolding when they diverge.
- Reports the resolved module version; clear message on install failure (offline / policy), without
  blocking the rest of setup when a usable version already exists.

### 5.4 `Get-IntuneWinAppUtil.ps1`
- Ensures `tools/IntuneWinAppUtil.exe` is present and current.
- Queries the official repo `microsoft/Microsoft-Win32-Content-Prep-Tool` for the latest release tag
  (currently `v1.8.7`); releases carry **no assets**, so the exe is fetched from the repo tree at the
  tag via raw URL.
- Downloads if missing or outdated (compares stored `tooling.*` against latest), then records the new
  tag + blob sha. Reports "already current" otherwise.

### 5.5 `Invoke-IntuneWin32Upload.ps1`
- Acquires an app-only token via client secret (tenant/client id from config, secret DPAPI-decrypted,
  in-memory only).
- Creates the `win32LobApp`, creates a content version, uses the encryption metadata from the
  `.intunewin` (Detection.xml) for the **block-blob upload** to Azure Storage, commits the version.
- Uploads the app logo separately (Graph supports this; no `.intunewin` repack needed).
- Sets assignment per `defaultAssignment`.
- **Idempotent:** if an app with the same display name + version already exists, it asks before
  overwrite/supersedence.
- Returns app id + portal link.

### 5.6 `Test-PsadtSetup.ps1`
- Auth smoke test: acquire token + a simple Graph GET (e.g. `/deviceAppManagement/mobileApps?$top=1`).
- Clear diagnostics on failure (wrong secret / missing permission / missing admin consent).

### 5.7 `references/app-registration.md`
Short Entra app-registration checklist:
1. Entra Admin Center → App registrations → New registration
2. API permissions → Microsoft Graph → **Application** → `DeviceManagementApps.ReadWrite.All`
3. **Grant admin consent**
4. Certificates & secrets → New client secret → copy the value (shown once)
5. Enter tenant id + client id + secret into setup

## 6. SKILL.md changes

### 6.1 Phase 0 — Setup (new, before Intake)
- Skill calls `Get-PsadtConfig.ps1`. Complete → straight to Intake. Missing/incomplete → wizard
  (asks only missing fields).
- Wizard as AskUserQuestion batches (clickable options, recommended option first):
  1. **Paths** (`packageRoot`, `outputRoot`, `intuneWinAppUtil`) — current values as defaults
  2. **Languages** (`script`=EN, `dossier`=DE as defaults)
  3. **Author** — person + company separately (defaults = existing convention)
  4. **Intune upload**: Yes / No / Later
  5. If Yes: tenant id, client id (free text), `defaultAssignment`. The **secret NOT via chat** — the
     skill prints a terminal one-liner (`Read-Host -AsSecureString` → `Set-PsadtConfig.ps1`) that
     DPAPI-encrypts it immediately (see 6.5 / section 7).
- On Yes: run `Test-PsadtSetup.ps1`; red → clear message, `uploadEnabled` becomes `true` only after a
  green test.
- Provision prerequisites during setup so neither is a manual hurdle: the **PSAppDeployToolkit module**
  via `Get-PsadtModule.ps1` (install from PSGallery if missing) and the **content-prep tool** via
  `Get-IntuneWinAppUtil.ps1`.
- Explicitly re-triggerable ("psadt setup") → change individual values.
- Links `references/app-registration.md`.

### 6.2 Config instead of hard-code
Replace fixed values throughout the skill with config lookups: `outputRoot`, `intuneWinAppUtil`,
`author`, languages. The previous mandatory values remain as **defaults** — now config-driven instead
of baked into the prose.

### 6.3 New phase — Intune upload (optional, between pack and test)
- Only when `uploadEnabled: true`. Otherwise the existing manual flow, explicitly documented as the
  fallback.
- Even when `uploadEnabled: true`, **declinable per run** (e.g. customer tenant without rights) →
  manual fallback.
- Call `Invoke-IntuneWin32Upload.ps1`, show the result (app id + portal link).

### 6.4 HTML switch (new convention)
- Dossier document → `Intune-Dossier.html`, full HTML. **Exception:** the app **description block** stays
  **Markdown**, because the Intune app description field for the Company Portal supports only Markdown
  (no HTML). So the dossier is HTML, but the description text pasted into Intune is Markdown.
- Rewrite the conventions block, Phase 7 and anti-patterns from "Markdown" to "HTML".
- German umlauts remain in the dossier; scripts stay EN/ASCII (encoding hygiene unchanged).

### 6.5 Document the DPAPI flow informatively in the skill
`SKILL.md` gains a short, **informative** section explaining the DPAPI flow so the skill can answer a
user asking "how is my secret stored?":
- Encryption happens **automatically** in `Set-PsadtConfig.ps1` (Windows DPAPI,
  `ConvertFrom-SecureString`, scope CurrentUser) — the user does not do crypto by hand.
- The secret is entered **in the user's own terminal** via `Read-Host -AsSecureString` so it never
  reaches the Claude transcript (tool calls are non-interactive → setup prints the one-liner instead
  of asking for the secret itself).
- Bound to user + machine: a copied `secret.dpapi` is worthless on another machine/under another user.
- Decryption only in-memory at upload time; on secret rotation, re-run setup.

### 6.6 English translation
Translate `SKILL.md` and `references/PSADTv4-Deployment-Guide.md` to English. The skill keeps
producing **German** dossier/description output per convention; only the skill-internal text becomes
English. Author and version conventions (`0.1` start, mandatory changelog in `.NOTES`) are preserved.

## 7. Security

- Secret only via **DPAPI (scope CurrentUser)** → bound to user + machine, no plaintext in the profile.
- **Secret entry NOT via chat:** setup has the user enter the secret in their own terminal via
  `Read-Host -AsSecureString` (one-liner printed by the skill). The plaintext never lands in the
  conversation transcript. `AskUserQuestion` free text for the secret is deliberately avoided.
- Secret never in `config.json`, never in logs, never in conversation output; decryption only
  in-memory at upload time.
- Setup does not re-display the entered secret.
- `.gitignore` excludes `config.json`, `secret.dpapi` and `tools/` (plus a `*.dpapi`/key safety net).

## 8. Error handling

- `Get-PsadtConfig.ps1` returns structured "missing fields" → wizard asks only those.
- `Test-PsadtSetup.ps1` / upload: token failure → clear cause (secret/permission/consent). Pass Graph
  4xx through instead of swallowing.
- Upload idempotent: existing app of same version → ask before overwrite/supersedence.
- `Get-IntuneWinAppUtil.ps1`: download/network failure → clear message; keep any existing working copy.
- A missing/declined upload is not an error → clean fallback to the manual flow.

## 9. Tests

- Helper scripts: parse-clean (AST), DPAPI round-trip test (encrypt → decrypt → equal).
- `Get`/`Set-PsadtConfig`: schema validation, partial updates, missing-field detection.
- `Get-PsadtModule.ps1`: missing → installs from PSGallery; present → version compare/no-op; install
  failure with an existing usable version does not block setup.
- `Get-IntuneWinAppUtil.ps1`: fresh download, up-to-date no-op, forced-update path; verify recorded
  version/sha.
- `Test-PsadtSetup.ps1` as a live auth check (against a test tenant where available).
- `Invoke-IntuneWin32Upload.ps1`: upload a real small package to a test tenant, verify app id, then
  clean up.

## 10. Out of scope (YAGNI)

- Certificate or delegated auth (decision: client secret).
- Distribution as a Claude Code plugin / marketplace.
- Multi-tenant profiles in one config (one config per machine; tenant switch via re-setup).
- Automatic secret rotation.
- Committing the content-prep tool binary into the repo (it is auto-downloaded and gitignored).
