---
name: psadt-deploy
description: Use this skill when the user wants to build, package, test, troubleshoot, or deploy a PowerShell App Deployment Toolkit (PSADT) v4.x Intune Win32 app package. Triggers include "PSADT paket bauen", "intune paket fuer <app>", "<app> via intune paketieren", "PSADT v4 deploy", "PSADT troubleshooting", "Invoke-AppDeployToolkit.ps1 debug", "IntuneWinAppUtil", or when working inside a folder that contains Invoke-AppDeployToolkit.ps1 / .exe or a PSAppDeployToolkit module. Also use it to self-update the skill: "update skill", "/update-skill", "psadt update", "check for skill updates".
---

# PSADT v4.x Deployment Skill

## Summary

This skill guides the complete lifecycle of a **PSADT v4.x Intune Win32 package** - from the first conversation to a tested, upload-ready `.intunewin`. It is intended for **build, packaging, test, troubleshooting, and deployment** (triggers include "PSADT paket bauen", "intune paket fuer <App>", "PSADT v4 deploy", or working in a folder that contains `Invoke-AppDeployToolkit.ps1`).

**Workflow (10 phases):** 1) Intake (8 kill questions, ALWAYS via click options) - 2) Web research (PSADT version + command changes, silent/uninstall/repair of the app, Intune pitfalls) - 3) Scaffold (`New-ADTTemplate`) - 4) Customizing all three deployment types (Install/Uninstall/Repair) - 5) Pre-flight (encoding/parse/acid test) - 5.5) optional SYSTEM test loop - 6) Packaging (IntuneWinAppUtil) - 7) **HTML package report (ALWAYS, via `New-PsadtReport.ps1`)** + REAL logo - 7.5) optional direct Intune upload via Graph (win32LobApp, coexistence-safe) - 8) Test - 9) Rollout.

**Binding conventions (details in the block below):**
- ALWAYS ask the user via `AskUserQuestion` (click options), never as free text
- Output `.intunewin` ALWAYS centrally to `paths.outputRoot`/<App>\ - the output root is configured by the user during setup (NO hard-coded default); read it from config via `Get-PsadtConfig`
- **HTML package report ALWAYS generated for every package — whether uploaded to Intune or not (BINDING, never skipped).** Produce it from the fixed template `references/Report-Template.html` via `scripts/New-PsadtReport.ps1`, output ALWAYS `Intune-Dossier.html` in `Output\<App>\`. It is ONE self-contained, bilingual (DE/EN toggle) document combining the **Intune dossier** + a **technical package report**; language from `language.dossier` (**default German with real umlauts**) - BUT the **app description block** for the Company Portal field is **Markdown** (that field supports only Markdown, not HTML); scripts on the other hand **English/ASCII**
- Author ALWAYS assembled from config (`author.person` + `author.company`, set during setup - no hard-coded default); first script version `0.1`; changelog in the `.NOTES` header is mandatory
- Obtain the **REAL** app logo (PNG, high resolution) -> `Assets\` + `Output\<App>\` — NEVER the PSADT default `AppIcon.png`
- Start Menu entries only, NO desktop icons
- Build all three deployment types (Install/Uninstall/Repair) from the start and verify them via acid test
- Direct Intune upload (Phase 7.5) is opt-in: **fill all objective app-info fields**, but NEVER auto-impose category / branded notes / featured / assignment, and NEVER delete an older version (new versions coexist for supersedence)
- **Test before upload (BINDING):** Install + Uninstall must pass the Phase 5.5 SYSTEM test before any `.intunewin` is uploaded — never upload an untested package

Per-topic depth in the reference guide `references/PSADTv4-Deployment-Guide.md` (appendices A-H).

---

You guide the user through the complete lifecycle of a PSADT v4.x Intune package: intake, research, scaffold, customizing, pre-flight, packaging, Intune upload, test, rollout. Behavior rules:

- **Actively drive the conversation** - do not dump a question list; ask targeted blocker questions, research what can be researched, show the user intermediate results
- **ALWAYS ask questions via `AskUserQuestion` (click options), never as plain free text** - every decision question to the user goes through the `AskUserQuestion` tool with pre-filled, clickable options. Always put the recommended option first and mark it with the suffix "(recommended)". Offer researched defaults as options. The tool automatically adds an "Other" free-text option - so there is no need to build a manual free-text alternative. Plain text is only allowed for intermediate results / status messages, not for questions.
- **Do not assume Adobe/Oracle as default** - the app to be packaged always comes from the user; examples from the guide are illustration
- **Reference**: The complete reference guide is at `references/PSADTv4-Deployment-Guide.md` - point to specific appendices (A-G) there when depth is needed, do NOT dump the whole guide into the conversation

## Conventions (BINDING)

- **Language - split by target:**
  - **HTML package report (`Intune-Dossier.html`, always generated via `New-PsadtReport.ps1` — see Phase 7) - but the app description block for the Company Portal field is Markdown** (that field supports only Markdown, not HTML). The report is a single self-contained, bilingual (DE/EN toggle) document; it carries both languages so the user can switch in the browser. **Default language from `language.dossier`, default GERMAN with real umlauts** (ä, ö, ü, ß) - this is end-user text for the Company Portal, where umlauts are correct and desired (do NOT spell out ae/oe/ue). The report's real umlauts come from the description metadata; the template stays ASCII via HTML entities and the file is written UTF-8. The dossier language is a config value, not a fixed rule.
  - **In the scripts themselves (Invoke-AppDeployToolkit.ps1, Extensions, Detection): EVERYTHING in ENGLISH** - especially all comments. Keep script strings in English too, so that no umlauts/non-ASCII end up in the PS1 (encoding cleanliness, see pre-flight). Umlauts belong ONLY in the dossier HTML, never in the script.
- **Author ALWAYS from config:** compose `AppScriptAuthor` (in `$adtSession`) from `author.person` + `author.company`, which the user sets during setup (`Get-PsadtConfig`). No hard-coded author.
- **Script versioning (`AppScriptVersion` in `$adtSession`):**
  - The first version of a script is ALWAYS **`0.1`** (not 1.0.0).
  - Every substantively justified change increases the version number (small fixes/clarifications -> patch/minor, larger functional changes -> bigger jump). Purely cosmetic edits without functional relevance do not necessarily need to bump.
- **Changelog is mandatory:** Every change to a script is documented in a **changelog in the script header (`.NOTES` block)** - one line per version: `Version (date, author): What was changed`. On every change, update the changelog entry AND `AppScriptVersion` together. Format:
  ```
  Changelog:
  - 0.1 (YYYY-MM-DD, <author.person>): Initial version.
  - 0.2 (YYYY-MM-DD, <author.person>): <what was changed>.
  ```

## Self-update (check for a newer skill version)

The skill can update itself from GitHub. **When the user asks** — "update skill", "/update-skill",
"psadt update", "check for skill updates" — OR **once at the start of Phase 0 setup** (a quiet, non-blocking
check), run:

```powershell
pwsh scripts/Update-PsadtSkill.ps1            # read-only check -> UpdateAvailable / Behind / WhatsNew / versions
```
The check is **commit-based** (authoritative, no CDN lag): a git clone compares `HEAD` vs `origin/<branch>`;
otherwise the GitHub commits API sha is compared against the recorded `tooling.skillCommit`. The CHANGELOG
version is shown only as context. If `UpdateAvailable` is true, show the user `LocalVersion -> RemoteVersion`
+ `Behind` and the `WhatsNew` (remote's top CHANGELOG section), then **ask via `AskUserQuestion`**. Only on confirmation:
```powershell
pwsh scripts/Update-PsadtSkill.ps1 -Apply     # git pull --ff-only (clone) OR overwrite tracked files from the branch zip
```
It updates only tracked content (SKILL.md, README.md, CHANGELOG.md, LICENSE, references/, scripts/, tests/);
`config.json`, `secret.dpapi`, `tools/` and `docs/` are never touched. Never auto-apply — always ask first.
If the check fails (offline), say so and continue; an update check must never block packaging.

## Workflow (execute in this order)

### 0. Setup (Phase 0 — run before intake)

Before anything else happens: make sure the skill is configured and the prerequisites are in place.

0. **Self-update check (optional, non-blocking):** run `pwsh scripts/Update-PsadtSkill.ps1`; if a newer
   version exists, show what's new and ask whether to update (see "Self-update" above). Skip silently on error.
1. Run `pwsh scripts/Get-PsadtConfig.ps1`. If `Exists` is true and `Missing` is empty, go straight to intake.
2. If the config is missing/incomplete, run the **setup wizard** — ask only for the missing values, ALWAYS via `AskUserQuestion` (click options), recommended option first:
   - **Paths**: `paths.packageRoot`, `paths.outputRoot`, `paths.intuneWinAppUtil` (offer the current values as defaults).
   - **Languages**: `language.script` (EN), `language.dossier` (DE as default — but a config value, not fixed).
   - **Author**: `author.person`, `author.company`.
   - **Intune direct upload** *(ACTIVE — see Phase 7.5)*: optional. To enable it, the admin runs `pwsh scripts/New-PsadtEntraApp.ps1` **once** — it signs in interactively via **WAM** (the Windows Web Account Manager broker; falls back to device code only if WAM is unavailable), creates the `PSADT Intune Upload` Entra app, grants + admin-consents `DeviceManagementApps.ReadWrite.All`, creates a client secret, and writes `intune.tenantId/clientId/uploadEnabled` + DPAPI-stores the secret. Requires Global Admin or Privileged Role Admin. Manual portal route: `references/app-registration.md`. If the user does NOT want direct upload, skip this — the manual dossier-in-Admin-Center flow still works.
3. Persist answers with `scripts/Set-PsadtConfig.ps1 -Updates @{ ... }` (in this version without `-Secret`).
4. Provision prerequisites (never block the user):
   - `pwsh scripts/Get-PsadtModule.ps1` — installs/updates PSAppDeployToolkit.
   - `pwsh scripts/Get-IntuneWinAppUtil.ps1` — downloads/updates the content-prep tool into `tools/`.
   - `pwsh scripts/Get-WinGetModule.ps1` — downloads/caches PSAppDeployToolkit.WinGet to `tools/`. Run at scaffold time for WinGet packages only; skip for MSI/EXE packages. Re-triggerable to update the module to the latest release.
5. Re-triggerable at any time via "psadt setup" to change individual values.

### 1. Intake (right at the start, before anything else)

Critical: A PSADT v4 package ALWAYS serves three deployment types — **Install, Uninstall, Repair**. All three must be planned from the start, not only at the end.

Ask the **8 kill questions exclusively via the `AskUserQuestion` tool** (clickable options), NOT as a free-text list. Since the tool allows max. 4 questions per call, bundle them into **two `AskUserQuestion` calls** (4 + 4). Wherever possible, lightly probe what is researchable beforehand (app, latest version, installer type) and offer the findings as pre-selected options - the user then only clicks confirm or correct. Each question gets sensible default options; the recommended one first with the suffix "(recommended)". The tool automatically appends an "Other" free-text option.

The 8 substantive questions that must be covered (spread across the two calls):
1. **App + exact version** - options: detected/latest version (recommended), known previous version(s), from context.
2. **Installer type** - options: MSI, EXE wrapper, MSIX, InstallShield, Squirrel/ZIP/portable, WinGet package, other.
   - **WinGet is strictly OPT-IN and NEVER the default.** Default to the app's native installer (MSI/EXE/...). Only go the WinGet route when the user *explicitly* picks "WinGet package" here — never assume, recommend, or auto-select it, even if a WinGet package exists. The whole WinGet path below (2b discovery, module provisioning, install/uninstall/repair patterns) applies ONLY after that explicit choice.
   - If **WinGet selected**: inject a follow-up `AskUserQuestion` before Q3 covering: Package ID (e.g. `Valve.Steam`, `Microsoft.PowerShell` — user provides or Phase 2b confirms), scope (`Machine` recommended — required for Intune SYSTEM context), version (`Latest` recommended vs pinned). Then **skip Q3** — WinGet packages have no local installer to source.
3. **Installer source** - options: available locally (path follows), download + bundle into the package (recommended), download at runtime. *(Skip for WinGet — Package ID is the source; see Q2 above.)*
4. **Target audience** - options: Required on devices, Available in Company Portal, both; pull in AAD groups as free text if needed.
5. **Special config** - options: none (recommended default if nothing is known), registry keys, XML/JSON/settings file, license key, service account, branding (multiSelect: true makes sense).
6. **Reboot behavior** - options: never (recommended), recommended (3010), forced (1641).
7. **Uninstall semantics** - options for "what must go": app files only, + registry leftovers, + scheduled tasks/services/firewall, + user data (multiSelect). Plus a separate question/option for what definitely must be KEPT (user data, shared components, neighboring products from the same vendor). Uninstall method (MSI ProductCode / registry UninstallString / custom uninstaller) as a separate question if unclear.
8. **Repair semantics** - options: no repair needed, MSI /fa, config reset to default, complete reinstall (recommended for ZIP/EXE), service restart.

Optionally follow up depending on context via a further `AskUserQuestion` call: co-existence with previous versions, processes-to-close list, language (EN/DE/Multi), architecture (x64/x86/ARM64). Not all 30 questions from guide Phase 0.2 at once - the rest comes situationally, also via click options.

### 2. Web research (parallel, autonomous)

After intake, without asking back, immediately run **three parallel research streams**:

**a) Check PSADT version sync AND command changes:**
```powershell
$local = (Get-Module -ListAvailable -Name PSAppDeployToolkit | Sort-Object Version -Descending | Select-Object -First 1).Version
$rel = Invoke-RestMethod 'https://api.github.com/repos/PSAppDeployToolkit/PSAppDeployToolkit/releases/latest'
"local=$local latest=$($rel.tag_name)"
```
If divergent: inform the user + recommend `Update-Module PSAppDeployToolkit -Force` BEFORE scaffold.

**Mandatory, do NOT just compare the version number:** On a divergent (newer) version ALWAYS check whether
**commands have changed** - new, renamed, deprecated, or with changed parameters. Otherwise you build a
package with outdated syntax that breaks at the launcher acid test or only later in Intune. Sources in this order:
- Release notes of the latest release: `$rel.body` (already loaded above) scanned for "Breaking", "renamed", "deprecated", "removed", "new function"
- Changelog/migration docs: https://psappdeploytoolkit.com/docs (v3->v4 function mapping and version changelogs)
- GitHub releases overview: https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/releases
- When in doubt, verify the actually used cmdlets against the installed module:
  `Get-Command -Module PSAppDeployToolkit -Name Start-ADTProcess,Start-ADTMsiProcess,Show-ADTInstallationWelcome,New-ADTShortcut,Remove-ADTFolder | Select Name,Version`
  and if needed `Get-Help <Cmdlet> -Parameter *` for changed parameters.
Show the finding to the user (which commands are new/changed/deprecated and what that means for the package) BEFORE building.

**b) Silent install / uninstall / repair research on the app** via WebSearch — ALL THREE, not just install:
- Query 1: `"<AppName>" "<Version>" silent install command line`
- Query 2: `"<AppName>" msi transform enterprise deployment`
- Query 3: `"<AppName>" uninstall silent /quiet /qn msiexec`
- Query 4: `"<AppName>" repair reinstall command line` (often `msiexec /fa <ProductCode>` for MSIs; for EXE wrappers: reinstall via the same installer)
- Query 5: `"<AppName>" "uninstall" "registry" "leftover"` — documented leftovers from the community
- Official vendor docs first, then silentinstallhq.com, then community (Reddit r/Intune, PSADT Discourse)

Record per deployment type: switch, expected exit codes, log path, known leftovers.

**b-WinGet) Package discovery (replaces stream b when installer type = WinGet):**

> **Module import required:** `Find-ADTWinGetPackage` comes from PSAppDeployToolkit.WinGet. Import it explicitly before calling:
> ```powershell
> Import-Module 'C:\Users\<user>\.claude\skills\psadt-deploy\tools\PSAppDeployToolkit.WinGet\PSAppDeployToolkit.WinGet.psd1' -ErrorAction SilentlyContinue
> ```
> (The skill's `tools/` path is in config under `paths.intuneWinAppUtil`'s parent — adjust if the skill root differs.)

> **Always search by name first** when the exact ID is not already known with certainty. WinGet IDs follow `Publisher.AppName` dot-notation where each word is its own segment — e.g. `Valve.Steam` or `Microsoft.PowerShell.Preview`, NOT `MicrosoftPowerShellPreview`. Guessing the concatenated form wastes a lookup.

```powershell
# Step 1: Search by display name to discover the exact ID
Find-ADTWinGetPackage -Name '<AppName>' | Select-Object Id, Name, Version, Source | Format-Table -AutoSize

# Step 2: Confirm the chosen ID exists and show full details
Find-ADTWinGetPackage -Id '<ConfirmedPackageId>' | Format-List Id, Name, Version, Source
```

**Fallback if WinGet/module is not available on the build machine:** look up the package ID at https://winstall.app/ (web UI over the winget-pkgs repo). This is a last resort — `Find-ADTWinGetPackage` is always preferred because it confirms the ID resolves at runtime on this machine.

If package not found after both steps: stop and ask the user to correct the ID — do NOT scaffold with an invalid ID.

Research the WinGet manifest for detection hints (ProductCode, installer type, known exe names, install path):
`https://github.com/microsoft/winget-pkgs/tree/master/manifests/<first-letter>/<publisher>/<app>/<version>/`

For WinGet **portable** packages: the manifest's `InstallerType: portable` means WinGet places files under `%ProgramFiles%\WinGet\Packages\<Id>_<Arch>\` and creates shims in `%ProgramFiles%\WinGet\Links\`. The exact exe names inside the Links folder come from the manifest — check the `.yaml` before coding them into shortcut lists. Always guard shortcut creation with `if (Test-Path $exePath)` so a wrong name logs a warning rather than failing the deployment.

Add to stream c for WinGet packages: `"<AppName>" winget intune deployment known issues`.

**c) Known Intune pitfalls:**
- Query: `"<AppName>" intune win32 known issues`
- Query: `"<AppName>" PSADT package github` (in case someone already built a package)

Put the result into the Phase-0.3 table from the guide and show it to the user BEFORE the scaffold is built.

### 3. Scaffold (`New-ADTTemplate`)

Insert values from intake + research. **Do NOT hardcode**, **do not use Adobe/Oracle**.

```powershell
Import-Module PSAppDeployToolkit
# IMPORTANT: In 4.1.x, New-ADTTemplate ONLY accepts -Destination/-Name/-Version (module version)/-Force/-Show/-PassThru.
# It takes NO app metadata (-AppVendor/-AppName/-AppVersion/-AppScriptAuthor ...). Those go AFTER the scaffold
# into the $adtSession hashtable in Invoke-AppDeployToolkit.ps1.
New-ADTTemplate -Destination '<root-from-user-input>' -Name '<AppName from intake>'
```

Then fill the `$adtSession` hashtable in the generated `Invoke-AppDeployToolkit.ps1` - including the binding conventions:
```powershell
AppVendor = '<vendor>'
AppName = '<short product name>'
AppVersion = '<version>'
AppArch = '<x64|x86|ARM64>'
AppLang = 'EN'
AppRevision = '01'
AppSuccessExitCodes = @(0, 1707)
AppRebootExitCodes = @(1641, 3010)
AppScriptVersion = '0.1'                              # first version ALWAYS 0.1, see conventions
AppScriptAuthor = '<author.person>, <author.company>'   # from config (Get-PsadtConfig), set during setup
```
And in the header comment (`.NOTES`) create the changelog: `- 0.1 (YYYY-MM-DD, <author.person>): Initial version.`

Verify right after scaffold:
```powershell
$pkg = '<scaffold path>'
(Import-PowerShellDataFile "$pkg\PSAppDeployToolkit\PSAppDeployToolkit.psd1").ModuleVersion
Select-String "$pkg\Invoke-AppDeployToolkit.ps1" -Pattern 'DeployAppScriptVersion' -List | Select-Object Line
```
Both must match.

**For WinGet packages only** — provision the extension module into the package folder immediately after scaffold:
```powershell
# Download module to tools/ (if not current) and copy into this package
pwsh scripts/Get-WinGetModule.ps1 -SkillRoot '<skillRoot>' -PackagePath '<pkg>'
# Verify
(Import-PowerShellDataFile '<pkg>\PSAppDeployToolkit.WinGet\PSAppDeployToolkit.WinGet.psd1').ModuleVersion
```
PSADT's extension auto-loader discovers `PSAppDeployToolkit.WinGet\` by folder-name match and imports it automatically — no `Import-Module` in the deployment script. The `Files\` folder remains empty for WinGet packages (nothing to bundle). Set `AppVersion = 'Latest'` in `$adtSession` (or `'<pinned>'` if a fixed version was requested); read `AppArch` from the WinGet manifest installer type.

### 4. Script customizing — all three deployment types

The user places the installer in `<pkg>\Files\`. Then fill **all three hooks** in `Invoke-AppDeployToolkit.ps1`: `Install-ADTDeployment`, `Uninstall-ADTDeployment`, `Repair-ADTDeployment`. Even if only install is needed today: later user uninstalls via Company Portal only work with a filled uninstall block.

**4a. `Install-ADTDeployment`** — pattern depending on installer type from the research:

- MSI: `Start-ADTMsiProcess -FilePath "$($adtSession.DirFiles)\<installer>.msi" -Transforms "$($adtSession.DirSupportFiles)\<transform>.mst" -ArgumentList '/qn REBOOT=ReallySuppress'`
- EXE wrapper: `Start-ADTProcess -FilePath "$($adtSession.DirFiles)\<setup>.exe" -ArgumentList '<researched silent switches>' -SuccessExitCodes @(0, 3010, 1641)`
- InstallShield with `setup.exe /s /f1"<response>.iss"`: response file in `SupportFiles\`
- Squirrel (`<app>-<ver>-full.nupkg`-based .exe): often `/silent /quiet`
- WinGet:
  ```powershell
  Repair-ADTWinGetPackageManager                                        # self-heal WinGet before every operation
  Install-ADTWinGetPackage -Id '<WinGetId>' -Scope Machine -Mode Silent # add -Version '<ver>' if pinned
  ```

Mandatory before install: `Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -CheckDiskSpace -RequiredDiskSpace <MB>` (no-op in silent, active in interactive). Then `Show-ADTInstallationProgress` for the welcome-replacement display.

**Shortcuts - ONLY Start Menu, NEVER desktop:** If the app needs a shortcut, create exclusively a
Start Menu entry for all users (`$envCommonStartMenuPrograms`, e.g.
`New-ADTShortcut -Path "$envCommonStartMenuPrograms\<App>\<App>.lnk" -TargetPath ...`). **No desktop icons**
(`$envCommonDesktop` / `$envUserDesktop`) - that clutters the desktop and is unwanted in the enterprise.
If the installer creates a desktop icon on its own: remove it again specifically in post-install
(`Remove-Item "$envCommonDesktop\<App>.lnk"`). In uninstall, clean up the Start Menu entry as well.

**4b. `Uninstall-ADTDeployment`** — values from intake question 7 (what goes, what stays):

- MSI with known ProductCode: `Start-ADTMsiProcess -Action Uninstall -ProductCode '{<ProductCode>}' -ArgumentList '/qn'` (in PSADT 4.1.x a GUID MUST go to `-ProductCode`; `-FilePath` is validated as a real file path and throws `InvalidFilePathParameterValue` -> exit 60001)
- MSI via DisplayName match (when ProductCode varies): `Remove-ADTApplication -Name '<AppName>' -NameMatch Exact` (not `Contains` - that accidentally removes neighboring products with a name prefix)
- EXE with its own uninstaller: `Start-ADTProcess -FilePath '<uninstallstring-from-registry>' -ArgumentList '<silent uninstall switches>'`
- Squirrel: `Start-ADTProcess -FilePath "$env:LocalAppData\<app>\update.exe" -ArgumentList '--uninstall -s'`
- WinGet: `Uninstall-ADTWinGetPackage -Id '<WinGetId>' -Mode Silent`

Post-uninstall cleanup (based on intake question 7):
- `Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -CloseProcessesCountdown 60` (not `-Silent` - uninstalls should be allowed to kill processes)
- Scheduled tasks: `Get-ScheduledTask -TaskName '<Prefix>_*' | Unregister-ScheduledTask -Confirm:$false`
- Services: `Stop-Service <Name>` + `sc.exe delete <Name>` for services the installer does not clean up itself
- Firewall rules: `Get-NetFirewallRule -DisplayName '<App>*' | Remove-NetFirewallRule`
- Registry leftovers: delete specifically only under the APP-specific key, NEVER under `HKLM\SOFTWARE\<vendor>\` wholesale (other products of the same company suffer)
- Install directory `Remove-Item -Recurse` if the installer does not clean up on its own
- User data (AppData, documents, templates): DEFAULT **keep**, only remove on explicit intake-7 instruction (and then specifically via `Invoke-ADTAllUsersRegistryAction` / `$envProfilesDirectory` iteration per user)

Counter-example to warn about: NEVER do `Remove-Item 'HKLM:\SOFTWARE\<vendor>' -Recurse`. Always the APP sub-key.

**4c. `Repair-ADTDeployment`** — values from intake question 8:

- If intake says "not needed": leave the hook empty or abort with `Write-ADTLogEntry -Message 'Repair not supported - please use Uninstall + Install.'` + `throw`
- MSI: `Start-ADTMsiProcess -Action Repair -ProductCode '{<ProductCode>}' -ArgumentList '/fa /qn'` (`/fa` = all files reinstalled, shortcuts + registry are set again; a GUID goes to `-ProductCode`, NOT `-FilePath` - see Uninstall note above. The Repair block is a frequent miss: the Uninstall fix often gets applied but Repair still has `-FilePath`, which fails 60001 only when a repair is actually triggered.)
- EXE wrapper without a dedicated repair mode: uninstall followed by install in the same hook; preserve user config if possible (backup-restore logic if needed)
- Config-only repair: stop the service, copy the config files back from `SupportFiles\`, start the service - without reinstalling the app (faster, less invasive)
- WinGet:
  ```powershell
  try {
      Repair-ADTWinGetPackage -Id '<WinGetId>'
  } catch {
      Write-ADTLogEntry -Message "WinGet repair not supported; performing uninstall + reinstall."
      Uninstall-ADTWinGetPackage -Id '<WinGetId>' -Mode Silent
      Repair-ADTWinGetPackageManager
      Install-ADTWinGetPackage -Id '<WinGetId>' -Scope Machine -Mode Silent
  }
  ```

**Custom helpers** ALWAYS in `<pkg>\PSAppDeployToolkit.Extensions\PSAppDeployToolkit.Extensions.psm1`, never in the main script.

### 5. Pre-flight checks (mandatory before packaging)

Three green per deployment type, otherwise do not proceed:

```powershell
$s = '<path-to-ps1>'

# Check 1: Encoding
$bytes = [System.IO.File]::ReadAllBytes($s)
$hasBom = $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
$text = [System.IO.File]::ReadAllText($s, [System.Text.Encoding]::UTF8)
$nonAscii = ([regex]::Matches($text, '[^\x00-\x7F]')).Count
"HasBOM=$hasBom NonAscii=$nonAscii"   # Requirement: HasBOM=True OR NonAscii=0

# Check 2: Parse
$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($s, [ref]$null, [ref]$errs)
if ($errs) { $errs | Select Message,@{N='L';E={$_.Extent.StartLineNumber}} | Format-List } else { 'PARSE_OK' }

# Check 3: Launcher acid test per deployment type (once each)
foreach ($dt in 'Install','Uninstall','Repair') {
    "--- Acid-Test $dt ---"
    Start-Process powershell.exe -ArgumentList `
        '-ExecutionPolicy','Bypass','-NonInteractive','-NoProfile','-NoLogo',`
        '-Command', "try { & '$s' -DeploymentType $dt -DeployMode Silent } catch { throw }; exit `$Global:LASTEXITCODE" `
        -Wait -NoNewWindow -RedirectStandardError "stderr-$dt.log"
    Get-Content "stderr-$dt.log"   # Must show no parse errors
}
```

If one of the three types turns red: that is NOT ok even if install is green. Otherwise the Company Portal user gets 0x80070001 when clicking uninstall.

For WinGet packages, add:
```powershell
# Check 4: WinGet extension module present in package
$moduleManifest = '<pkg>\PSAppDeployToolkit.WinGet\PSAppDeployToolkit.WinGet.psd1'
if (Test-Path $moduleManifest) {
    "WinGet module: $((Import-PowerShellDataFile $moduleManifest).ModuleVersion) - OK"
} else {
    "WinGet module MISSING - run: pwsh scripts/Get-WinGetModule.ps1 -PackagePath '<pkg>'"
}
```

**For WinGet packages, Check 3 WILL trigger a real installation — always use the test stub instead of skipping.** Skipping silently leaves scope bugs and path errors undetected. The stub replaces the deployment functions with a controlled exit and verifies the launcher finds and loads the script correctly without installing anything. See appendix C for the full stub pattern. After the stub passes, defer the live install/uninstall/repair verification to Phase 8 on a DEV VM.

On an encoding bug (check 1 red or check 3 parse errors): replace em-dashes / smart quotes + UTF-8 BOM:
```powershell
$text = [System.IO.File]::ReadAllText($s, [System.Text.Encoding]::UTF8)
$text = $text -replace [char]0x2014, '-' -replace [char]0x2013, '-' -replace [char]0x2192, '->' `
              -replace [char]0x2018, "'" -replace [char]0x2019, "'" `
              -replace [char]0x201C, '"' -replace [char]0x201D, '"' -replace [char]0x2026, '...'
[System.IO.File]::WriteAllText($s, $text, [System.Text.UTF8Encoding]::new($true))
```

If check 3 is too dangerous because a real install would start: use the test stub from guide appendix C (replace the Install-ADTDeployment call with an `exit 77` stub, launcher test, expects exit 77).

Additionally scan:
```powershell
# v3 leftovers (+ WinGet wrong-prefix guard)
$v3 = 'Execute-Process','Execute-MSI','Write-Log','Show-InstallationWelcome','Show-InstallationProgress','Show-InstallationPrompt','Get-InstalledApplication','Remove-MSIApplications','Refresh-Desktop','Update-GroupPolicy','Block-AppExecution','Assert-WinGetPackageManager','Get-WinGetPackage','Install-WinGetPackage','Uninstall-WinGetPackage','Repair-WinGetPackage','Repair-WinGetPackageManager'
$t = [System.IO.File]::ReadAllText($s)
foreach ($fn in $v3) { $m = [regex]::Matches($t, "\b$fn\b"); if ($m.Count) { "V3_FOUND: $fn ($($m.Count)x)" } }

# Top-level statements that could throw
$ast = [System.Management.Automation.Language.Parser]::ParseFile($s, [ref]$null, [ref]$null)
$ast.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] } |
    ForEach-Object { "L$($_.Extent.StartLineNumber): $($_.GetType().Name)" }
```

### 5.5 Automated SYSTEM test loop (opt-in, BEFORE packaging)

Validate the package's Install/Uninstall scripts in a real **SYSTEM** context (mirroring the Intune
Management Extension) BEFORE packing, so bugs are caught early. Runs on the package **source folder** (no
`.intunewin` needed yet — fixes to the `.ps1` take effect on the next run, and you pack the validated
scripts afterward). Requires an **elevated** PowerShell session.

Only run when `test.systemTestEnabled` is true OR the user opts in for this package. **This test is a BINDING
prerequisite for the Phase 7.5 direct upload** — Install + Uninstall must pass here before any `.intunewin` is
uploaded. Needs an elevated session; if you cannot run it, stop before the upload and hand the command back to the user.

**Hands:** `scripts/Invoke-PsadtSystemTest.ps1` runs ONE action as SYSTEM (via the `Invoke-CommandAs`
module, self-healed from PSGallery) and returns
`{ DeploymentType, ExitCode, Success, DetectionState, LogPath, LogTail, ErrorLines, Elevated }`. It fixes
nothing — YOU (the agent) drive the loop and apply fixes between runs.

**Safety (this installs the REAL software on THIS machine as SYSTEM):**
- Before the FIRST install, confirm via `AskUserQuestion` and recommend a VM/snapshot.
- Hard cap `test.maxIterations` (default 5) — never loop forever.
- After a green run, leave the machine in `test.endState` (default `uninstalled`, leftover-clean).
- Keep each iteration's PSADT log in the output folder for an audit trail.

**Loop (max `test.maxIterations`):**
1. **Install:** `pwsh scripts/Invoke-PsadtSystemTest.ps1 -PackagePath <pkg> -DeploymentType Install -DetectionScript <detect>` (elevated). If not `Success`: read `LogTail`/`ErrorLines`, map to a root cause via the Troubleshooting quick-reference + guide Appendix A, fix `Install-ADTDeployment` (or Extensions), re-run.
2. **Uninstall:** run with `-DeploymentType Uninstall`. Verify `DetectionState = not-installed` AND the leftover checks (services, scheduled tasks, app registry key, install dir, firewall rules; neighbour products of the same vendor still present). On failure: fix `Uninstall-ADTDeployment`, re-run.
3. **Reinstall:** run `Install` again; verify installed. On failure: fix, re-run.
4. **Converged** (all three green) → leave the machine per `test.endState`, then proceed to Packaging (Phase 6) with the validated scripts.
5. **Cap reached** without convergence → STOP, present the diagnosis (last error, log tail, what was tried) and hand back to the user. Never loop forever.

### 6. Packaging with IntuneWinAppUtil

**Tool path and version are config-driven** (`paths.intuneWinAppUtil`) and are provisioned and kept current by `scripts/Get-IntuneWinAppUtil.ps1` (the inline download below stays as a manual fallback).

**Output folder convention (BINDING, not somewhere different each time):** ALWAYS place the finished `.intunewin` into
`<paths.outputRoot>\<AppName[-Version]>\` - the output root comes from config (set by the user during setup, no hard-coded path),
with a sub-folder per app underneath (e.g. `<outputRoot>\EclipseJEE\`, `<outputRoot>\RSAT-1.0.0\`, `<outputRoot>\ApacheMaven-3.9.16\`).
NEVER create a separate `_IntuneOutput`/`<App>-IntuneOutput` folder next to the package. The app sub-folder holds,
besides the `.intunewin`, also the detection script and the Intune dossier (1 place per app, everything together).
Important: `-c` (source) is the PACKAGE folder, `-o` (output) is the central output sub-folder - the two are
different trees, so `-o` automatically lies OUTSIDE `-c`.

```powershell
# All paths come from config - nothing hard-coded.
$cfg  = & scripts/Get-PsadtConfig.ps1
$tool = $cfg.Config.paths.intuneWinAppUtil    # provisioned + kept current by Get-IntuneWinAppUtil.ps1 (skill-managed tools/ by default)
if (-not (Test-Path $tool)) {
    # manual fallback if the tool was not provisioned yet (the GitHub release has NO assets - exe lives in the repo tree)
    New-Item (Split-Path $tool -Parent) -ItemType Directory -Force | Out-Null
    $tag = (Invoke-RestMethod 'https://api.github.com/repos/microsoft/Microsoft-Win32-Content-Prep-Tool/releases/latest').tag_name
    Invoke-WebRequest "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/$tag/IntuneWinAppUtil.exe" -OutFile $tool
}

$src = '<pkgFolder>'                                            # package folder with Invoke-AppDeployToolkit.ps1/.exe
$out = Join-Path $cfg.Config.paths.outputRoot '<AppName[-Version]>'   # CENTRAL, per-app sub-folder (from config)
New-Item $out -ItemType Directory -Force | Out-Null
& $tool -c $src -s 'Invoke-AppDeployToolkit.exe' -o $out -q
# Place the detection script + dossier alongside (dossier ALWAYS as Intune-Dossier.html):
Copy-Item '<pkgFolder>\Detect-*.ps1' $out -Force -ErrorAction SilentlyContinue
Copy-Item '<pkgFolder>\Intune-Dossier.html' $out -Force -ErrorAction SilentlyContinue
```

**Critical**: NEVER choose `-o` INSIDE `-c` - otherwise the old .intunewin lands recursively in the package on rebuild.
The central `Output\` folder lies outside every package folder anyway, which is exactly the reason for the convention.

Verify the .intunewin:
```powershell
$iw = Get-ChildItem "$out\*.intunewin" | Select-Object -First 1
"Size: $([Math]::Round($iw.Length / 1MB, 1)) MB"
Expand-Archive $iw.FullName -DestinationPath "$env:TEMP\iw-check" -Force
Get-Content "$env:TEMP\iw-check\IntuneWinPackage\Metadata\Detection.xml" | Select-String 'SetupFile'
# Must show: <SetupFile>Invoke-AppDeployToolkit.exe</SetupFile>
```

### 7. Package report (Intune dossier + technical report) — ALWAYS generated

**BINDING — the HTML report is produced for EVERY finished package, whether or not it is uploaded to Intune.**
It is never optional and never skipped. Generate it from the fixed template with the generator script — do
NOT hand-assemble HTML per package:

```powershell
# Fill $meta from the intake/research/test results (full key list: reference guide Appendix F).
& scripts/New-PsadtReport.ps1 -Metadata $meta -LogoPath '<Output\<App>\<App>-Logo.png>' `
    -OutputPath '<Output\<App>\Intune-Dossier.html'
```

- **Template:** `references/Report-Template.html` (do not fork it per app — the generator fills the tokens).
- **Output file name ALWAYS `Intune-Dossier.html`** (fixed; the app name is already in the output sub-folder),
  placed in the central `Output\<App>\` folder next to the `.intunewin` + detection script.
- **One combined document, two parts:** (1) **Intune dossier** — App Info, description (Markdown block),
  Program, Return Codes incl. 60001/60008=Failed, Requirements, Detection, Dependencies, Supersedence,
  Assignments; (2) **technical package report** — the three deployment hooks, the PSADT cmdlets used,
  pre-flight results, the Phase 5.5 SYSTEM-test result, logo + `.intunewin` verification.
- **Self-contained + bilingual:** the logo is embedded as a base64 data URI; the document carries BOTH
  German and English (DE/EN toggle top-right, `data-de`/`data-en`) and stays browser-translatable; the
  description **preview is rendered client-side from its Markdown source** (so preview == the Markdown you paste
  into Intune). The Fluent-2 header is sticky and shrinks on scroll.
- **The user reviews the report**, then (manual route) transfers the dossier values 1:1 into the Intune Admin
  Center, or (Phase 7.5) the upload reuses the same metadata.

The report language defaults to `language.dossier` (default German) and its **umlauts stay real** (ä, ö, ü, ß) —
the report is end-user output, so the script-only ASCII rule does NOT apply to it (the template itself is
ASCII via HTML entities; real umlauts come from the description metadata, and the file is written UTF-8).

**Note: direct Graph upload is now AVAILABLE — see Phase 7.5.** The manual dossier-in-Admin-Center route remains the documented alternative.

**Obtain the app logo automatically (mandatory):** Search for and download a suitable logo of the app - **PNG, transparent background, high resolution** (guideline >= 512px, more is better; square is best for the Company Portal tile). Place it under `<pkg>\Assets\<App>-Logo.png` AND a copy into `Output\<App>\`. Reference the filename in the logo row of the dossier.

> **HARD RULE — never ship the PSADT default icon as the app logo.** The PSADT template ships `Assets\AppIcon.png` (a generic coloured ">" mark) and `Assets\Banner.Classic.png`. These are NOT the application's logo. Re-using `AppIcon.png` as the Company-Portal logo is a real mistake that has happened — it passes a naive "is it square + has alpha" check yet shows the wrong brand. ALWAYS download the REAL application logo (steps below). The direct-upload script (`Invoke-IntuneWin32Upload.ps1`) enforces this with a SHA256 blocklist of the known PSADT default asset(s) and refuses unless `-AllowDefaultLogo` is explicitly passed.
- **Choose a license-clear source in this priority order:**
  1. **Microsoft products:** try `https://learn.microsoft.com/en-us/<product>/media/index/<product>.png` (official Microsoft Learn assets, transparent PNG, direct download). Replace `<product>` with the lowercase product identifier (e.g. `powershell`, `sqlserver`, `azure`).
  2. **Other vendors:** official vendor/project source (e.g. `apache.org/logos/res/<project>/` for Apache projects).
  3. **Fallback:** Wikimedia Commons (stable URLs, SVG rendered server-side as a transparent PNG):
  ```powershell
  # Wikimedia: SVG -> transparent PNG at the desired width (here 1024)
  $api = "https://commons.wikimedia.org/w/api.php?action=query&titles=$([uri]::EscapeDataString('File:<Logo>.svg'))&prop=imageinfo&iiprop=url&iiurlwidth=1024&format=json"
  $thumb = ((Invoke-RestMethod $api -Headers @{'User-Agent'='PSADT-pkg/1.0'}).query.pages.PSObject.Properties.Value).imageinfo[0].thumburl
  Invoke-WebRequest $thumb -OutFile '<pkg>\Assets\<App>-Logo.png' -Headers @{'User-Agent'='PSADT-pkg/1.0'}
  ```
  Avoid third-party PNG portals (stickpng, toppng, nicepng ...) - hotlink protection/ads/questionable quality.
  4. **MSI Icon table fallback (when web download fails):** MSI installers embed .ico files in an `Icon` table. Export via COM, parse the raw ICO binary, and extract the largest frame directly (System.Drawing.Icon silently falls back to 48x48 when the 256x256 frame is PNG-compressed inside the .ico on .NET Framework 4.x — always parse the binary directly):
  ```powershell
  Add-Type -AssemblyName System.Drawing
  Add-Type -TypeDefinition @'
  using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
  public class IcoDibReader {
      public static Bitmap FromDib32(byte[] dib, int width, int height) {
          int pixelDataSize = width * height * 4;
          var pixels = new byte[pixelDataSize];
          Array.Copy(dib, 40, pixels, 0, pixelDataSize);
          var bmp = new Bitmap(width, height, PixelFormat.Format32bppArgb);
          var bd = bmp.LockBits(new Rectangle(0, 0, width, height), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
          int rb = width * 4;
          for (int r = 0; r < height; r++) Marshal.Copy(pixels, (height-1-r)*rb, IntPtr.Add(bd.Scan0, r*bd.Stride), rb);
          bmp.UnlockBits(bd); return bmp;
      }
  }
  '@ -ReferencedAssemblies 'System.Drawing'
  $tmpDir = "$env:TEMP\MsiIconExport"; New-Item $tmpDir -ItemType Directory -Force | Out-Null
  $db = [System.Activator]::CreateInstance([System.Type]::GetTypeFromProgID('WindowsInstaller.Installer')).OpenDatabase('<path-to.msi>', 0)
  $db.Export('Icon', $tmpDir, 'Icon.idt')
  # Streams export as <IconName>.ico.ibd in a subfolder named 'Icon'
  $icoPath = Get-ChildItem "$tmpDir\Icon" -Filter '*.ibd' | Sort-Object Length -Descending | Select-Object -ExpandProperty FullName -First 1
  $allBytes = [System.IO.File]::ReadAllBytes($icoPath)
  $count = [BitConverter]::ToUInt16($allBytes, 4); $bestW = 0; $bestOff = 0; $bestSize = 0
  for ($i = 0; $i -lt $count; $i++) {
      $base = 6 + $i * 16; $w = [int]$allBytes[$base]; if ($w -eq 0) { $w = 256 }
      if ($w -gt $bestW) { $bestW = $w; $bestOff = [BitConverter]::ToUInt32($allBytes, $base+12); $bestSize = [BitConverter]::ToUInt32($allBytes, $base+8) }
  }
  $frame = New-Object byte[] $bestSize; [Array]::Copy($allBytes, $bestOff, $frame, 0, $bestSize)
  if ($frame[0] -eq 0x89 -and $frame[1] -eq 0x50) {
      [System.IO.File]::WriteAllBytes('<output>.png', $frame)  # PNG-compressed frame: write directly
  } else {
      $biH = [Math]::Abs([BitConverter]::ToInt32($frame, 8)) / 2
      $bmp = [IcoDibReader]::FromDib32($frame, $bestW, [int]$biH)
      $bmp.Save('<output>.png', [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  }
  Remove-Item $tmpDir -Recurse -Force
  ```
- **Verify** (resolution + ACTUAL transparency) AND visually confirm it is the right brand. `IsAlphaPixelFormat` only says the pixel *format* supports alpha — it returns True even for a fully opaque image (this misled a real session: a 7-Zip SVG rendered with an opaque black background still reported `Alpha=True`). Sample real corner pixels:
  ```powershell
  Add-Type -AssemblyName System.Drawing
  $b=[System.Drawing.Bitmap]::FromFile('<png>')
  $c=$b.GetPixel(0,0); "{0}x{1}  cornerAlpha={2} (0=transparent,255=opaque) RGB=({3},{4},{5})" -f $b.Width,$b.Height,$c.A,$c.R,$c.G,$c.B; $b.Dispose()
  ```
  Then **actually look at the image** (open it / read it as an image) to confirm it is the app's brand, not the PSADT default. A transparent background (cornerAlpha=0) is preferred; an OPAQUE-but-correct logo is acceptable (square it on its own background colour for a clean tile). What is NOT acceptable is the wrong image. The logo is uploaded separately in Intune's **App information tab** (or by Phase 7.5), it is NOT part of the `.intunewin` (no repack needed).

**App description ALWAYS in the dossier language with real umlauts (ä, ö, ü, ß)** - this is end-user text in the Company Portal, do NOT spell out ae/oe/ue. (Applies to the dossier/description output; the scripts stay English/ASCII - see conventions.)

**App description ALWAYS formatted as Markdown** - the Intune app description field for the Company Portal supports **only Markdown, NOT HTML**, and renders the Markdown formatted in the Company Portal. NO plain free-text wall. Deliver the description block in the dossier as ready Markdown that the user can paste 1:1 into the description field. Supported feature set (safe to use):
- **bold** and *italic* for emphasis
- bulleted lists (`-`) and numbered lists (`1.`) - ideal for requirements, set variables, what-happens steps
- Links `[Text](https://...)` for vendor/docs pages
- Short paragraphs instead of a block
- Use sparingly: headings and tables (rendering in the Company Portal varies) - prefer a bold line + list

Recommended description structure (end-user output — language.dossier, default German; adapt per app):
```markdown
**<AppName> <Version>** - <one-sentence value>.

**What this deployment does:**
- <install target / path>
- <environment variables / registry / config set>
- <notable side effects>

**Requirements:**
- <e.g. JDK, .NET, prior version>

**On uninstall:**
- <what is removed> / <what is kept>

More info: [Vendor page](https://...)
```

Mandatory return codes that must always be included: `0 Success, 1707 Success, 3010 Soft reboot, 1641 Hard reboot, 1618 Retry, 60001 Failed, 60008 Failed` + installer-specific codes from the research.

**For WinGet packages — additional dossier requirements:**
- Requirements table: add `Windows Package Manager (WinGet) >= 1.7.10582` — note that `Repair-ADTWinGetPackageManager` in the install hook self-heals this automatically.
- Detection note: The PSAppDeployToolkit.WinGet module is bundled inside the `.intunewin` and extracted at install time only — it is **NOT** present on the device during Intune's detection phase. Detection must use registry or file checks only. Never use `Get-ADTWinGetPackage` in a detection script. Recommended template for WinGet-installed apps:
  ```powershell
  # Detect-<AppName>.ps1 - registry-based, works regardless of ProductCode stability
  $regBases = @(
      'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )
  foreach ($base in $regBases) {
      $match = Get-ChildItem $base -ErrorAction SilentlyContinue |
          Get-ItemProperty |
          Where-Object { $_.DisplayName -like '<AppName>*' } |
          Select-Object -First 1
      if ($match) { Write-Output "Detected: $($match.DisplayName) $($match.DisplayVersion)"; exit 0 }
  }
  exit 1
  ```
  For apps whose WinGet manifest includes a stable `ProductCode`, use the direct GUID key (`HKLM:\...\Uninstall\{<ProductCode>}`) — faster and more reliable than a DisplayName scan.

### 7.5 Direct Intune upload via Microsoft Graph (opt-in)

Push the finished `.intunewin` straight to Intune as a **win32LobApp** (app + logo, **NO group assignment**) instead of copy-pasting the dossier. Self-contained raw Graph - no third-party module. Enabled by Phase 0's `New-PsadtEntraApp.ps1` bootstrap (`intune.uploadEnabled = true`). Manual dossier upload stays the alternative.

> **BINDING PREREQUISITE — test before you upload.** NEVER upload a package whose **Install AND Uninstall**
> have not been validated. Run the **Phase 5.5 SYSTEM test** (`Invoke-PsadtSystemTest.ps1`: Install -> verify
> detection -> Uninstall -> verify clean -> Reinstall) and get it GREEN first; fix the package and re-test on
> any failure. The SYSTEM test needs an **elevated** session (and installs the real software — use a VM/snapshot).
> If you cannot run it (no elevation, no VM), **STOP before `-Execute` and hand back to the user** with the exact
> test command — do not upload an untested package.

**Scripts:** `scripts/Get-GraphToken.ps1` (app-only client-credentials token; DPAPI secret decrypted in-memory only) and `scripts/Invoke-IntuneWin32Upload.ps1` (the orchestrator: parse `.intunewin` -> token -> permission probe -> idempotency -> build body -> create/update -> content version -> file -> SAS -> block-blob upload -> commit -> activate -> categories -> supersedence).

**Flow:** ALWAYS dry-run first (read-only) -> show the user the summary + the `On -Execute` action -> confirm via `AskUserQuestion` -> run with `-Execute`. Example:
```powershell
& scripts/Invoke-IntuneWin32Upload.ps1 -IntuneWinPath '<out>\<App>\Invoke-AppDeployToolkit.intunewin' `
  -DisplayName '<App>' -Description $markdownDesc -Publisher '<vendor>' -Developer '<vendor>' `
  -AppVersion '<ver>' -MsiProductCode '{<GUID>}' -Architecture x64 -MinWindowsRelease 1607 `
  -LogoPath '<out>\<App>\<App>-Logo.png'            # add -Execute to actually upload
```

**Detection — pick the right rule for the installer type:**
- **MSI-backed app** (has a ProductCode): `-MsiProductCode '{<GUID>}'` (builds a `win32LobAppProductCodeRule`).
- **EXE / non-MSI app** (Vivaldi, Chrome-style, NSIS, Squirrel, ...): `-DetectionScriptPath '<out>\<App>\Detect-<App>.ps1'`
  (builds a `win32LobAppPowerShellScriptRule`, ruleType=detection). The detect script follows the classic
  contract: write to stdout + `exit 0` when installed, no stdout when not. Add `-DetectionRunAs32Bit` only if needed.
  A **detection** script rule accepts ONLY `enforceSignatureCheck`, `runAs32Bit`, `scriptContent` — Graph
  rejects `displayName`/`runAsAccount`/`operationType`/`operator`/`comparisonValue` on detection rules (guide Appendix H.2).

**Fill as many fields as possible — not the minimum.** The user expects a complete *App information* tab, not three fields. Map the dossier metadata onto: `displayName, description (Markdown), publisher, developer, owner, displayVersion, informationUrl, privacyInformationUrl, notes, largeIcon, msiInformation (productCode+productVersion for MSI), returnCodes, rules (detection), installExperience`. Empty fields are a defect to fix, not the norm.

**But NEVER auto-impose user/organisation choices:**
- **No company branding in `notes` by default** (e.g. "Managed by <company>"). Leave it empty, or let it come from config `intune.notes` - never hard-coded. The user/org decides.
- **No category by default.** `-Categories` defaults to empty; users assign categories themselves. Only pass `-Categories` if the user explicitly asks.
- **No featured flag, no group assignment** - deliberate human actions.

**Versioning / coexistence (CRITICAL — never delete an older version):** Uploading a new version must NOT remove the existing one. The script issues only POST/PATCH, **never DELETE**. Default `-OnExisting CreateNewCoexist` creates a NEW, separate app and leaves the existing version(s) fully intact, so you can configure **supersedence** and keep a rollback target. Use `-UpdateAppId <id>` only when the user explicitly wants in-place content replacement of one app (keeps its id/assignments). Wire supersedence with `-SupersedesAppId <oldId>` (new *replaces* old; old retained, not deleted) or in the portal. The dry-run prints the exact `On -Execute` action - show it before confirming.

**Beta endpoint:** the orchestrator uses `graph.microsoft.com/beta` - the v1.0 Intune app-metadata backend silently DROPS several win32LobApp write properties (most visibly `displayVersion`). See guide Appendix H.

**Logo guard:** the script refuses the PSADT default `AppIcon.png` (SHA256 blocklist) unless `-AllowDefaultLogo`. Always pass the REAL downloaded logo (Phase 7).

Per-detail depth + the hard-won Graph gotchas: **guide Appendix H**. Then feed into the Phase 8 test-group step (assign to 1 test device).

### 8. Test sequence (BEFORE production rollout) — all three deployment types

On a DEV VM in this order. After each successful install comes the uninstall test on **the same VM** (not a new VM) - so that uninstall actually has something to clean up.

**Install cycle:**
1. `.\Invoke-AppDeployToolkit.ps1 -DeploymentType Install -DeployMode Silent` (smoke test)
2. `.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent` (launcher acid test)
3. SYSTEM context: preferred is `scripts/Invoke-PsadtSystemTest.ps1` (uses the `Invoke-CommandAs` module, returns a structured result; see Phase 5.5 for the automated loop). Fallback: `psexec -s cmd /c "cd /d <pkg> && Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent"` (PsExec: https://learn.microsoft.com/en-us/sysinternals/downloads/psexec)

**Uninstall cycle (on the same VM, app must be installed):**
4. `.\Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent`
5. Verification checks after uninstall:
   - Detection script (see Phase 5 guide) must return `exit 0 + stdout empty` (app = not installed)
   - `Get-Service '<App-Service>' -ErrorAction SilentlyContinue` - empty
   - `Get-ScheduledTask '<App-Prefix>*' -ErrorAction SilentlyContinue` - empty
   - Install directory: gone (or only user-config leftovers if intake-7 wanted it so)
   - Registry under `HKLM:\SOFTWARE\<vendor>\<App>` - gone
   - Firewall rules `Get-NetFirewallRule -DisplayName '<App>*'` - empty
   - IMPORTANT: neighboring products of the same vendor still present (not accidentally deleted too)

**Repair cycle (reinstall the VM again, then repair):**
6. Repeat install (step 1)
7. `.\Invoke-AppDeployToolkit.exe -DeploymentType Repair -DeployMode Silent`
8. Detection must still show = installed afterwards; smoke-test app functionality manually

**Intune test group (after all three cycles are green):**
9. Assign the package as Required → 1 test device → check the PSADT install log + AppWorkload.log
10. Uninstall from the device: assign as "Uninstall" in the Admin Center OR have the user uninstall via Company Portal → check the PSADT uninstall log

Check in every Intune test:
- `C:\Windows\Logs\Software\<AppName>*PSAppDeployToolkit_Install.log` / `*_Uninstall.log` exists
- `Close-ADTSession` with exit 0 in it
- AppWorkload.log shows the matching status (`Installed` / `Uninstalled`)

After a successful test of all three types: pilot group 24-48h, then production staged.

## Troubleshooting quick reference

On user reports, check in this order:

| Symptom | Primary suspect | Verification |
|---|---|---|
| `0x80070001` + no local PSADT logs | Encoding (em-dash in "-string") or top-level throw | Phase 5 checks + appendix A.2 |
| `0x8000EA68` (60008) + PSADT log present but empty after init | Import-Module / Open-ADTSession throws | PSADT log directly readable, stack in appendix A.2 |
| `0x8000EA61` (60001) + stacktrace in the PSADT log | Runtime error in Install-ADTDeployment | Stack shows the line directly |
| App stuck on "Installing" in Company Portal | IME state cache or process hangs | Appendix A.2 cleanup sequence |
| `0x80070002` | Launcher does not find the .ps1 | `-s` during packaging was wrong |
| Detection failed after successful install | Detection script bug (contract violation, 32/64-bit registry) | Manually on target: `.\Detect-*.ps1; $LASTEXITCODE` |
| SYSTEM test: `New-ScheduledJobOption`/`PSScheduledJob` could not be loaded; every step `ExitCode=0 Success=False not-installed` | Running `Invoke-PsadtSystemTest.ps1` under pwsh 7 - PSScheduledJob (used by Invoke-CommandAs) is WinPS-5.1-only, blocked in Core | Re-run under `powershell.exe` 5.1; the harness now self-re-execs to 5.1 (guide Appendix G 2026-06-05 #1) |
| `60001` (`InvalidFilePathParameterValue,Start-ADTMsiProcess`) on Uninstall/Repair | ProductCode GUID passed to `-FilePath` instead of `-ProductCode` (PSADT 4.1.x) | Use `-ProductCode '{<GUID>}'`; verify `(Get-Command Start-ADTMsiProcess).Parameters.Keys` (guide Appendix G 2026-06-05 #2) |
| Upload create fails `BadRequest: must have at least one detection rule specified` (rule WAS sent) | New Intune backend wants the unified `rules` collection (`win32LobAppProductCodeRule`, `ruleType=detection`), NOT legacy `detectionRules` | Use `rules`; put `@odata.type` first (ordered) (guide Appendix H) |
| Upload `uploadState=commitFileFailed` after blocks uploaded "OK" | Binary corruption: `Invoke-RestMethod -Body <byte[]>` re-encodes the blob | Upload via `HttpClient`/`ByteArrayContent` (raw bytes) (guide Appendix H) |
| `displayVersion` (App Version) empty after upload despite being sent | v1.0 app-metadata backend drops it | Use `graph.microsoft.com/beta` for the write (guide Appendix H) |
| Upload `403` on the read-only probe / create | App consent missing/ineffective | Re-run `New-PsadtEntraApp.ps1`; verify `DeviceManagementApps.ReadWrite.All` admin-consented |
| Upload create fails `The <X> property may not be set for Win32LobAppPowerShellScriptRule ... used for app detection` | A detection script rule carries requirement-only props | Keep only `ruleType,enforceSignatureCheck,runAs32Bit,scriptContent` (guide Appendix H.2) |

HRESULT conversion: Intune shows unknown positive exit codes as `0x80070000 + code`. So `0x80070001` = exit 1 = script did not run at all. Always recompute, don't be misled by the "ERROR_INVALID_FUNCTION" text.

Check logs in this order:
1. `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AppWorkload.log` (what IME actually did + exit code)
2. `C:\Windows\Logs\Software\<AppName>*PSAppDeployToolkit_Install.log` (PSADT session, if init was OK)
3. `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` (IME service state)

## Anti-patterns (never do)

- v3 cmdlet names (`Execute-Process`, `Write-Log`, `Show-InstallationWelcome`, ...)
- Em-dash/smart quote **anywhere in the script file** — this means in comments too, not just in double-quoted strings. All generated script text must be 7-bit ASCII only. Use `-` (hyphen) never U+2014 (em-dash) or U+2013 (en-dash). This is the single most common encoding failure and always requires at least two extra pre-flight runs to find and fix.
- Saving UTF-8 without BOM when non-ASCII is present
- Top-level code outside try/catch
- `-o` inside `-c` for IntuneWinAppUtil
- Not mapping return codes 60001/60008 as Failed
- Assuming "runs locally = runs in Intune" - the launcher acid test is mandatory
- Mixed detection (custom script + file rule in parallel)
- Putting Extensions functions into the main script instead of the Extensions module
- Formatting the Intune app description field with HTML - that field supports ONLY Markdown (the dossier document is HTML, but the description block pasted into the Intune field must be Markdown)
- Reflexively setting install time to 120 min - 60 min is almost always right
- Triggering fallback delete actions on the first negative async response (services need 30-60s after msiexec, build a retry loop)
- Creating desktop icons (or leaving ones created by the installer) - Start Menu entries only, keep the desktop clean
- Recognizing a newer PSADT version only by its number and adopting it blindly - always check the release notes/changelog for changed/deprecated commands
- **Defaulting to / auto-selecting / recommending WinGet** — it is strictly opt-in (intake Q2); use the app's native installer (MSI/EXE/...) unless the user *explicitly* chose WinGet. Never assume WinGet just because a package exists
- Using `Get-ADTWinGetPackage` in a detection script — the WinGet module lives inside `.intunewin` and is not present on the device at detection time; use registry or file detection only
- `-Scope User` in WinGet Intune deployments — Intune SYSTEM context has no mounted user hive; always use `-Scope Machine`
- Skipping `Repair-ADTWinGetPackageManager` before `Install-ADTWinGetPackage` — WinGet may be absent or outdated on managed devices; always self-heal first
- Mixing `Install-ADTWinGetPackage` with `Start-ADTProcess`/`Start-ADTMsiProcess` in the same deployment type hook — use one installation paradigm per hook
- Using bare WinGet cmdlet names without the `ADT` prefix (`Install-WinGetPackage`, `Repair-WinGetPackageManager`, `Assert-WinGetPackageManager`, ...) — those are the non-PSADT cmdlets and bypass logging, error handling, and the PSADT session; always use the `*-ADTWinGet*` versions from the extension module
- Passing a ProductCode GUID to `Start-ADTMsiProcess -FilePath` (Uninstall AND Repair) - it must be `-ProductCode`; the Repair block is the one most often left wrong
- **Uploading the PSADT default `Assets\AppIcon.png` (or Banner) as the app logo** - always the REAL downloaded application logo; the upload script blocks the default by hash
- Trusting `IsAlphaPixelFormat` alone for "transparent" - it is True for opaque images too; sample a real corner pixel AND look at the image
- Using the legacy `detectionRules`/`requirementRules` for a new win32LobApp on the current backend - use the unified `rules` collection; never both at once
- For a non-MSI app, forcing an MSI ProductCode rule (there is none) - use a PowerShell-script detection rule (`-DetectionScriptPath`)
- Setting `displayName`/`runAsAccount`/`operationType`/`operator`/`comparisonValue` on a *detection* script rule - Graph rejects them (valid only on *requirement* script rules)
- Serialising a polymorphic Graph object with `@odata.type` NOT first - use `[ordered]@{}` so the subtype binds (else "no detection rule")
- Uploading the encrypted blob with `Invoke-RestMethod -Body <byte[]>` - it corrupts binary; use `HttpClient`/`ByteArrayContent`
- Writing win32LobApp metadata on `/v1.0` and wondering why `displayVersion` is empty - use `/beta`
- **Deleting / overwriting the older version when uploading a new one** - new versions COEXIST (separate app, `-OnExisting CreateNewCoexist`); never DELETE; let the user wire supersedence
- Putting company branding in `notes`, or auto-assigning a category/featured/group - those are user/org decisions (config-driven at most), never script defaults
- Filling only the minimum app-info fields - populate every objective field (publisher, developer, owner, version, info/privacy URL, description, logo)
- **Skipping the HTML package report** - it is generated for EVERY package, upload or not (Phase 7, `New-PsadtReport.ps1`); "no upload" is not a reason to skip it
- **Hand-assembling the report HTML per package** instead of filling `references/Report-Template.html` via `New-PsadtReport.ps1` - the template is fixed; only the metadata changes
- **Uploading a package whose Install + Uninstall were not tested** - the Phase 5.5 SYSTEM test (install -> uninstall -> reinstall, green) is a BINDING prerequisite for Phase 7.5; if you can't run it, STOP and hand back to the user, never upload untested

## Reference lookup

For depth on every topic: `references/PSADTv4-Deployment-Guide.md`
- Phase 0.2: Complete intake question list
- Phase 0.3: Web research pattern
- Phase 3.1: Encoding fix details
- Phase 5: Intune config fields
- Appendix A: Error codes + root causes
- Appendix B: Anti-pattern list
- Appendix C: Test stub patterns
- Appendix D: All resource URLs
- Appendix E: Final deploy checklist
- Appendix F: Complete Intune upload dossier template (all fields, all tabs)
- Appendix G: Lessons from the Oracle XE project
- Appendix H: Direct Intune upload via Graph - win32LobApp create, the `rules` collection, beta vs v1.0, HttpClient block-blob upload, EncryptionInfo relay, coexistence/supersedence, metadata completeness, logo guard, WAM bootstrap
