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
- **Deliverable dossier (HTML)** — produces the Intune metadata, return-code map, detection rule, and a
  ready-to-paste HTML app description for the Company Portal.
- **Guided testing & staged rollout** — DEV-VM cycles (silent, `.exe` launcher, SYSTEM context via
  PsExec), an Intune test-group assignment, then pilot → staged production.
- **Troubleshooting** — decodes Intune error/HRESULT codes (e.g. `0x80070001`), maps symptoms to root
  causes, and triages the right logs (AppWorkload.log, PSADT session log).
- **Start Menu only** — creates Start Menu entries and removes stray desktop icons; keeps the desktop clean.
- **Optional direct Intune upload** *(planned — future release)* — will upload the `.intunewin` via
  Microsoft Graph with an app registration (client secret stored DPAPI-encrypted), and stay fully
  optional with a fallback to the manual dossier flow. **Not in the current version yet** — today you
  upload the generated `.intunewin` manually in the Intune Admin Center.

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
| `intune.*` | Optional direct-upload settings (tenant id, client id, default assignment) |

`config.json`, `secret.dpapi`, and `tools/` are **machine-local** and are never committed.

### Secret handling (DPAPI)

If you enable direct upload, the client secret is **never typed into the chat**. The skill prints a
terminal one-liner that reads the secret via `Read-Host -AsSecureString` and encrypts it with Windows
**DPAPI** (scope `CurrentUser`) into `secret.dpapi`. It is bound to your user + machine, decrypted only
in-memory at upload time, and never written to `config.json` or any log.

## Project structure

```
psadt-deploy/
├─ SKILL.md                          the skill itself
├─ README.md  ·  LICENSE
├─ scripts/                          Get/Set-PsadtConfig, Get-PsadtModule, Get-IntuneWinAppUtil
│                                    (upload scripts arrive with the future upload feature)
├─ references/                       PSADTv4-Deployment-Guide.md
│                                    (app-registration.md arrives with the upload feature)
├─ docs/superpowers/specs/           design documents
├─ tools/        (gitignored)        auto-downloaded IntuneWinAppUtil.exe
├─ config.json   (gitignored)        machine-local settings
└─ secret.dpapi  (gitignored)        DPAPI-encrypted client secret
```

## Status

The core build/package/test/dossier workflow is in active use. **Shipped:** first-run setup + config,
self-healing prerequisites (PSADT module + content-prep tool), and HTML deliverables — verified via the
Pester suite in `tests/`. See the
[design spec](docs/superpowers/specs/2026-06-04-psadt-skill-setup-design.md) and
[implementation plan](docs/superpowers/plans/2026-06-04-psadt-skill-setup.md).

**Planned for a future release:** the optional direct Intune upload via Microsoft Graph (app
registration + DPAPI-encrypted secret). Until then, upload the generated `.intunewin` manually in the
Intune Admin Center.

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
