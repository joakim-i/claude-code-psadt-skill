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
- **App logo auto-fetch** — finds and downloads a license-clear logo (official vendor source or Wikimedia
  Commons), as a transparent high-resolution PNG, and verifies the alpha channel before use.
- **Deliverable dossier** — produces the Intune metadata, return-code map, detection rule, and a
  ready-to-paste **Markdown** app description for the Company Portal field (the dossier document itself
  is HTML; the Intune description field supports only Markdown, not HTML).
- **Guided testing & staged rollout** — DEV-VM cycles (silent, `.exe` launcher, SYSTEM context via
  PsExec), an Intune test-group assignment, then pilot → staged production.
- **Troubleshooting** — decodes Intune error/HRESULT codes (e.g. `0x80070001`), maps symptoms to root
  causes, and triages the right logs (AppWorkload.log, PSADT session log).
- **Start Menu only** — creates Start Menu entries and removes stray desktop icons; keeps the desktop clean.

> Planned features (direct Intune upload, GitHub package sync) live in the [Roadmap](#roadmap).

## Requirements

- Windows with PowerShell 5.1+ / PowerShell 7+
- [PSAppDeployToolkit](https://psappdeploytoolkit.com/) v4.x *(the skill installs/updates this
  automatically from the PowerShell Gallery if missing)*
- [Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)
  *(the skill provisions this automatically)*
- *(Future release only)* For the optional direct upload: an Entra app registration with the Graph
  **application** permission `DeviceManagementApps.ReadWrite.All` (admin consent granted)

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
├─ README.md  ·  LICENSE
├─ scripts/                          Get/Set-PsadtConfig, Get-PsadtModule, Get-IntuneWinAppUtil
├─ references/                       PSADTv4-Deployment-Guide.md
├─ tests/                            Pester suite for the helper scripts
├─ tools/        (gitignored)        auto-downloaded IntuneWinAppUtil.exe
└─ config.json   (gitignored)        machine-local settings
```

Arrives later with the [direct-upload feature](#roadmap): `scripts/Invoke-IntuneWin32Upload.ps1`,
`scripts/Test-PsadtSetup.ps1`, `references/app-registration.md`, the `intune.*` config block, and
`secret.dpapi` (the DPAPI-encrypted client secret).

## Status

The core build/package/test/dossier workflow is in active use. **Shipped:** first-run setup + config,
self-healing prerequisites (PSADT module + content-prep tool), and HTML deliverables — verified via the
Pester suite in `tests/`. (Design spec and implementation plan are kept in the maintainer's local
planning folder, not in this repo.)

## Roadmap

Planned features, in rough priority order. These are designed/specced and waiting to be built:

- **Optional direct Intune upload (Microsoft Graph)** — upload the `.intunewin` straight to Intune via
  an Entra app registration (`DeviceManagementApps.ReadWrite.All`). Stays optional, with a fallback to
  the manual dossier flow for tenants where you cannot register an app. *Until then: upload the generated
  `.intunewin` manually in the Intune Admin Center.*
  - *Secret handling (planned):* the client secret will be entered via a terminal one-liner
    (`Read-Host -AsSecureString`), never typed into the chat, and stored **DPAPI-encrypted** (scope
    `CurrentUser`) in `secret.dpapi` — bound to your user + machine, decrypted only in-memory at upload
    time, never written to `config.json` or any log.
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
- README structure inspired by [ComposioHQ/awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills)
