<h1 align="center">PSADT v4 → Intune Deployment Skill</h1>

<p align="center">
  <em>A Claude Code skill that drives the full lifecycle of a PowerShell App Deployment Toolkit (PSADT) v4.x Intune Win32 package — from first conversation to a tested, upload-ready <code>.intunewin</code>.</em>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="License: MIT" /></a>
  <img src="https://img.shields.io/badge/PSADT-v4.x-0a7bbb?style=flat-square" alt="PSADT v4.x" />
  <img src="https://img.shields.io/badge/Platform-Windows-0078d6?style=flat-square&logo=windows&logoColor=white" alt="Windows" />
  <img src="https://img.shields.io/badge/Claude%20Code-Skill-d97757?style=flat-square" alt="Claude Code Skill" />
</p>

<p align="center"><sub><a href="#roadmap">Roadmap</a> · <a href="#changelog">Changelog</a></sub></p>

---

## What is this?

This is a **Claude Code skill** (not a plugin): a reusable instruction package that teaches the agent
how to build, package, test, troubleshoot, and deploy a **PSADT v4.x Intune Win32 app**. You describe
the application; the skill runs the whole workflow — intake, web research, scaffolding, customizing all
three deployment types (Install / Uninstall / Repair), pre-flight checks, packaging with
IntuneWinAppUtil, dossier generation, testing, and rollout.

A skill is a folder with a `SKILL.md` (YAML frontmatter + Markdown instructions), optionally bundled
with `scripts/`, `references/`, and `tools/`. It loads progressively: the agent sees only the name and
description until a task makes it relevant, then the full body loads on demand.

<img width="1024" height="254" alt="image" src="https://github.com/user-attachments/assets/7c7931ba-dcae-4476-a648-11115eceb3b5" />

## Features

- **First-run setup** — a one-time wizard persists machine config (paths, language, author) so
  conventions are configured once, in one place.
- **Self-healing prerequisites** — auto-installs the PSAppDeployToolkit module from the PowerShell
  Gallery if missing, and auto-downloads `IntuneWinAppUtil.exe`, keeping both current against their
  official sources. No manual provisioning, no roadblocks.
- **Guided intake** — asks the blocker questions up front as clickable options, pre-filled with
  researched defaults (app, latest version, installer type).
- **Autonomous research** — checks the installed PSADT version against the latest release *and* whether
  commands changed; researches silent install / uninstall / repair switches and known Intune pitfalls.
- **Scaffolding & customizing** — runs `New-ADTTemplate` and fills all three deployment types (Install,
  Uninstall, Repair) from the start — acid-tested — so Company-Portal uninstalls actually work.
- **Pre-flight checks** — encoding/BOM, AST parse, launcher acid-test per deployment type, and a v3
  cmdlet scan before anything is packaged.
- **Packaging to `.intunewin`** — packs with IntuneWinAppUtil to the central output folder and verifies
  the package (correct `SetupFile`, size).
- **App logo auto-fetch** — finds and downloads the **real** application logo (official vendor source or
  Wikimedia Commons) as a high-resolution PNG, verifies actual pixel transparency *and* visually confirms
  the brand. Never ships the PSADT default `AppIcon.png` (the upload script blocks it by hash).
- **Deliverable dossier** — produces the Intune metadata, return-code map, detection rule, and a
  ready-to-paste **Markdown** app description for the Company Portal field (the dossier document itself
  is HTML; the Intune description field supports only Markdown, not HTML).
- **Guided testing & staged rollout** — DEV-VM cycles (silent, `.exe` launcher, SYSTEM context via
  PsExec), an Intune test-group assignment, then pilot → staged production.
- **Troubleshooting** — decodes Intune error/HRESULT codes (e.g. `0x80070001`), maps symptoms to root
  causes, and triages the right logs (AppWorkload.log, PSADT session log).
- **Start Menu only** — creates Start Menu entries and removes stray desktop icons; keeps the desktop clean.
- **Automated SYSTEM test loop** *(opt-in)* — before packaging, installs/uninstalls/reinstalls the package
  as the **SYSTEM** account (via `Invoke-CommandAs`, mirroring the Intune Management Extension), evaluates
  logs + detection, and auto-fixes until green or a max-iteration cap. Runs locally and needs an elevated
  session; recommended on a VM/snapshot.
- **Direct Intune upload via Microsoft Graph** *(opt-in)* — pushes the `.intunewin` straight to Intune as a
  `win32LobApp` (app + logo, **no group assignment**), self-contained raw Graph, no third-party module. A
  one-time `New-PsadtEntraApp.ps1` bootstrap signs in via **WAM** (Windows broker), creates the Entra app,
  grants + admin-consents `DeviceManagementApps.ReadWrite.All`, and DPAPI-stores the secret. Read-only
  dry-run → confirm → upload. Fills the full App-information tab; **never deletes an older version** (new
  versions coexist, with optional supersedence wiring); never auto-assigns categories/notes/groups.

> Planned features (GitHub package sync) live in the [Roadmap](#roadmap).

## Requirements

- Windows with PowerShell 5.1+ / PowerShell 7+
- [PSAppDeployToolkit](https://psappdeploytoolkit.com/) v4.x *(the skill installs/updates this
  automatically from the PowerShell Gallery if missing)*
- [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)
  *(the skill provisions this automatically)*
- For the optional **automated SYSTEM test loop**: an **elevated** PowerShell session; the
  [`Invoke-CommandAs`](https://github.com/mkellerman/Invoke-CommandAs) module is installed automatically
  from the PowerShell Gallery
- For the optional **direct Intune upload**: an Entra app registration with the Graph **application**
  permission `DeviceManagementApps.ReadWrite.All` (admin consent granted) — created for you in one run by
  `scripts/New-PsadtEntraApp.ps1` (interactive WAM sign-in as Global Admin / Privileged Role Admin; device
  code fallback). Manual portal route: `references/app-registration.md`.

## Installation

Clone into your Claude Code skills directory (the repo root *is* the skill folder):

```bash
git clone https://github.com/pt1987/claude-code-psadt-skill.git ~/.claude/skills/psadt-deploy
```

On Windows (PowerShell):

```powershell
git clone https://github.com/pt1987/claude-code-psadt-skill.git "$env:USERPROFILE\.claude\skills\psadt-deploy"
```

The skill activates automatically when you ask Claude Code to build an Intune package, or when you work
in a folder containing `Invoke-AppDeployToolkit.ps1`.

## First-run setup

On the first run (or when you say *"psadt setup"*), the skill walks a short wizard and writes a local
`config.json`:

| Setting | Purpose |
|---|---|
| `paths.packageRoot` / `outputRoot` | Where packages live and where `.intunewin` files are written |
| `paths.intuneWinAppUtil` | Content-prep tool location (skill-managed by default) |
| `language.script` / `dossier` | Script language (EN) vs. dossier language (DE for the Company Portal) |
| `author.person` / `company` | Stamped into every package's `AppScriptAuthor` |

`config.json` and `tools/` are **machine-local** and are never committed.

## Project structure

Current (what ships today):

```
psadt-deploy/
├─ SKILL.md                          the skill itself
├─ README.md  ·  CHANGELOG.md  ·  LICENSE
├─ scripts/
│   ├─ Get/Set-PsadtConfig, Get-PsadtModule, Get-IntuneWinAppUtil   setup + self-healing prerequisites
│   ├─ Invoke-PsadtSystemTest.ps1                                   opt-in SYSTEM test loop (Phase 5.5)
│   ├─ New-PsadtEntraApp.ps1                                        one-time Entra app bootstrap (WAM)
│   ├─ Get-GraphToken.ps1                                           app-only Graph token (uploads)
│   └─ Invoke-IntuneWin32Upload.ps1                                 direct Intune upload (Phase 7.5)
├─ references/                       PSADTv4-Deployment-Guide.md (App. A–H) · app-registration.md
├─ tests/                            Pester suite for the helper scripts
├─ tools/        (gitignored)        auto-downloaded IntuneWinAppUtil.exe
├─ config.json   (gitignored)        machine-local settings (incl. the `intune.*` block)
└─ secret.dpapi  (gitignored)        DPAPI-encrypted client secret (CurrentUser scope)
```

## Status

The core build/package/test/dossier workflow is in active use, and the **direct Intune upload** (Phase 7.5)
is implemented and verified against a live tenant. **Shipped:** first-run setup + config, self-healing
prerequisites (PSADT module + content-prep tool), HTML deliverables, the opt-in SYSTEM test loop, the WAM
Entra-app bootstrap, and the Graph win32LobApp uploader (coexistence-safe) — helper scripts verified via
the Pester suite in `tests/`.

## Roadmap

Planned features, in rough priority order. These are designed/specced and waiting to be built:

- **Sync finished packages to a GitHub repo** — a setup option (`output.target` = `local` / `git` /
  `both`) to push the per-app artifacts (`.intunewin`, dossier, detection, logo) to a Git repo instead
  of (or in addition to) a local folder — versioned and shareable, optionally not kept locally. Will use
  **Git LFS** for large `.intunewin` files (GitHub's 100 MB per-file limit).

Have a request? Open an issue.

## Contributing

Issues and pull requests are welcome. Keep `SKILL.md`, references, and docs in **English**. The only
non-English content is the generated end-user output (Intune dossier and Company-Portal app
description), whose language follows the `language.dossier` config value — **default German**, but
configurable per machine.

## License

[MIT](LICENSE) © Patrick Taubert, PHAT Consulting GmbH

## Acknowledgements

- [PSAppDeployToolkit](https://github.com/PSAppDeployToolkit/PSAppDeployToolkit)
- [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)
- [`Invoke-CommandAs`](https://github.com/mkellerman/Invoke-CommandAs)
- README structure inspired by [ComposioHQ/awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills)

## Changelog

Notable changes to the skill, newest first. Append-only — entries are never removed. Also mirrored in
**[CHANGELOG.md](CHANGELOG.md)**.

### 0.3.0 — Direct Intune upload (Microsoft Graph)
- **Direct upload** (`scripts/Invoke-IntuneWin32Upload.ps1`, Phase 7.5): self-contained raw-Graph
  `win32LobApp` upload (parse `.intunewin` → token → probe → idempotency → create/update → content → SAS
  block-blob upload via HttpClient → commit → activate → categories → supersedence). Read-only dry-run by
  default; `-Execute` to write.
- **WAM Entra-app bootstrap** (`scripts/New-PsadtEntraApp.ps1`): interactive Windows-broker sign-in (device
  code fallback), creates the app + admin consent + secret, DPAPI-stored.
- **App-only token helper** (`scripts/Get-GraphToken.ps1`).
- **Coexistence-safe versioning:** never deletes an older version; new versions coexist; optional
  supersedence wiring. **Logo guard:** refuses the PSADT default `AppIcon.png`. Fills the full
  App-information tab; never auto-assigns category/notes/groups.
- Fixed the Repair `-FilePath`→`-ProductCode` example; reference guide gains **Appendix H**.

### 0.2.0
- **Automated SYSTEM test loop** (`scripts/Invoke-PsadtSystemTest.ps1`, Phase 5.5): install → uninstall →
  reinstall the package as the SYSTEM account via `Invoke-CommandAs`, with agent-driven auto-fix until
  green or a max-iteration cap. Opt-in; elevated session required.
- Phase 8 now prefers `Invoke-CommandAs -AsSystem` for SYSTEM-context testing (PsExec kept as a fallback).

### 0.1.0
- Initial release: guided PSADT v4 → Intune Win32 lifecycle (intake, autonomous research, scaffolding, all
  three deployment types, pre-flight checks, packaging, dossier + logo, guided testing, troubleshooting).
- First-run setup writing a machine-local `config.json` (paths, language, author).
- Self-healing prerequisites: PSAppDeployToolkit module (PSGallery) and `IntuneWinAppUtil.exe`
  (auto-download + version check).
- HTML dossier document with a Markdown app-description block (the Intune description field is
  Markdown-only).
- English skill + reference guide; MIT licensed.
