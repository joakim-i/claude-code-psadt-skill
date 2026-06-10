---
name: psadt-deploy
description: Use when the user wants to build, package, test, troubleshoot, or deploy a PSADT v4.x Intune Win32 app. Triggers - "PSADT paket bauen", "intune paket fuer <app>", "<app> via intune paketieren", "PSADT v4 deploy", "PSADT troubleshooting", "Invoke-AppDeployToolkit.ps1 debug", "IntuneWinAppUtil", "update skill" / "psadt update", or when working in a folder with Invoke-AppDeployToolkit.ps1/.exe or a PSAppDeployToolkit module.
---

# PSADT v4.x Deployment Skill

Drive a PSADT v4.x Intune Win32 package end-to-end. Depth lives in
`references/PSADTv4-Deployment-Guide.md` (Phases 0-7 + Appendix A-J) and in each script's comment-based
help. Keep THIS file as the control plane; load guide sections on demand instead of inlining them.

## Operating mode (autonomy first)

1. **Research before you ask.** Anything researchable - latest version, installer type, silent/uninstall/
   repair switches, ProductCode, known Intune issues - is resolved by the Phase 2 research fan-out, never
   by a question.
2. **State founded assumptions, then proceed.** Emit one short `Assumptions:` status line (plain text is
   allowed for status / intermediate results) and keep working. Do not wait for confirmation on researched facts.
3. **Ask only at the 4 decision gates** (below), always via `AskUserQuestion` - clickable options,
   recommended option first with the suffix "(recommended)"; the tool adds "Other" automatically. Never ask
   as free text. Offer researched values as pre-selected options so the user just confirms or corrects.
4. **Blockade protocol.** On any error, API limit, or dead-end, never dump a raw error and never give up.
   Isolate the problem and emit exactly:
   `PROBLEM: <one line>. TRIED: <what>. OPTIONS: 1) <action> 2) <action>.`
   Then take option 1 if it is safe and reversible; otherwise hand the exact command back to the user.

Do not assume Adobe/Oracle (or any vendor) as a default - the app always comes from the user; guide examples
are illustration only.

## Sub-agent architecture (roles + handoffs)

You are the **Orchestrator**: you own config, the binding conventions, and the decision gates. Delegate
independent work; never let a gate be crossed without its handoff.

| Role | Run as | Owns | Handoff (gate) |
|---|---|---|---|
| **Researcher x3** | parallel agents (REQUIRED: superpowers:dispatching-parallel-agents) | (a) PSADT version + command-change check, (b) app silent/uninstall/repair switches, (c) Intune pitfalls | structured findings table, shown before scaffold |
| **Builder** | inline (you) | scaffold + fill all 3 hooks + Extensions module | a package that passes pre-flight |
| **Reviewer/QA** | agent (REQUIRED: superpowers:requesting-code-review for the script review) | pre-flight verdict, SYSTEM-test diagnosis, report + logo sanity | GREEN gate, or a blockade report |

**Hard handoff rules:** Builder may not package until Reviewer returns GREEN on pre-flight. Upload (7.5) may
not run until Reviewer returns GREEN on the SYSTEM test (Install + Uninstall). Researchers run concurrently
and return before scaffold.

## Decision gates (the ONLY AskUserQuestion moments)

Everything else is a researched assumption. Bundle questions (max 4 per call); pre-fill every option with
researched defaults; recommended option first.

1. **Scope confirm** - app + exact version, installer type, source strategy (local / bundle into package /
   download at runtime). WinGet is strictly opt-in here: default to the native installer, never recommend or
   auto-select WinGet even if a package exists. If WinGet is chosen, follow guide Appendix I.
2. **Deployment semantics** - target audience (Required / Available / both, + AAD groups), uninstall "what
   goes vs. what stays", repair strategy, reboot behaviour (never / 3010 / 1641). Pre-select defaults from
   the installer type. Group assignment is **opt-in**: only when the user wants it here do you create/assign
   Entra groups (Phase 7.6, config `intune.groups`, guide Appendix M); the default is upload-without-assignment.
3. **SYSTEM-test consent** - it installs the real software as SYSTEM; recommend a VM/snapshot before the
   first install.
4. **Upload confirm** - show the dry-run summary + the exact `On -Execute` action; confirm before `-Execute`.

Context follow-ups (coexistence, processes-to-close, architecture) come situationally, also via
`AskUserQuestion`. Full 30-question intake catalogue and per-question option sets: guide Phase 0.2.

## Conventions (BINDING - never skip, never reorder priorities)

- **Language split.** Scripts (`Invoke-AppDeployToolkit.ps1`, Extensions, Detection) = **English, 7-bit
  ASCII only** - comments AND strings included, so no umlaut/non-ASCII ever lands in a `.ps1` (encoding
  cleanliness; see Phase 5). Dossier/report = **`language.dossier`, default German with REAL umlauts**
  (ä ö ü ß - this is Company-Portal end-user text; do NOT spell out ae/oe/ue). Real umlauts come from the
  description metadata; the template stays ASCII via HTML entities and the file is written UTF-8. The
  Company-Portal app description block = **Markdown** (that field is Markdown-only, not HTML).
- **Output location.** `.intunewin` ALWAYS to `<paths.outputRoot>\<App[-Version]>\` (from `Get-PsadtConfig`,
  no hard-coded default), one sub-folder per app. Detection script + `Intune-Dossier.html` live in that same
  folder (everything together). Never a `_IntuneOutput` folder beside the package; never `-o` inside `-c`.
- **Author / version / changelog.** `AppScriptAuthor` in `$adtSession` = `author.person, author.company`
  (config, no hard-coded author). First script version ALWAYS `0.1` (not 1.0.0); substantive changes bump it,
  cosmetic edits need not. Mandatory changelog in the `.NOTES` header, one line per version:
  `- <ver> (YYYY-MM-DD, <author.person>): <change>`; bump `AppScriptVersion` + changelog together.
- **HTML report ALWAYS** (upload or not - never skipped, "no upload" is not a reason to skip it). Produce
  `Intune-Dossier.html` from the fixed template `references/Report-Template.html` via
  `scripts/New-PsadtReport.ps1` - never hand-assemble the HTML. One self-contained, bilingual (DE/EN toggle,
  browser-translatable) document = Intune dossier (App Info, Markdown description, Program, return codes incl.
  60001/60008=Failed, Requirements, Detection, Dependencies, Supersedence, Assignments) + technical package
  report (the 3 hooks, PSADT cmdlets used, pre-flight + SYSTEM-test results, logo + `.intunewin` verification).
- **Real logo only.** Download the REAL app logo (PNG, transparent, >=512px, square preferred) → `Assets\` +
  `Output\<App>\`. NEVER the PSADT default `AppIcon.png`/Banner (the upload script blocks them by SHA256).
  Verify real corner-pixel alpha AND look at the image. Sources + MSI-icon fallback + verification: guide
  Appendix J. (The logo is uploaded separately to Intune's App-information tab; it is NOT in the `.intunewin`.)
- **Shortcuts.** Start Menu only (`$envCommonStartMenuPrograms`). No desktop icons; remove any the installer
  creates, and clean up the Start Menu entry on uninstall.
- **All three deployment types from the start** (Install / Uninstall / Repair), each acid-tested - even if
  only install is needed today, Company-Portal uninstall needs a filled Uninstall hook.
- **Upload (opt-in).** Fill EVERY objective App-info field; NEVER auto-impose category / branded notes /
  featured; NEVER DELETE an older version (new versions coexist via `-OnExisting CreateNewCoexist`; the user
  wires supersedence). Group assignment is opt-in too: NEVER auto-assign a group unless the user chose it at
  Gate 2 AND `intune.groups.enabled` - then create/assign via the configured naming scheme (Phase 7.6 / App. M).
- **Test before upload (gate).** Install + Uninstall must pass the Phase 5.5 SYSTEM test before any upload.
  Can't run it (no elevation / VM)? STOP before `-Execute` and hand back the exact command. Never upload
  untested.

## Self-update

On user request ("update skill" / "psadt update" / "/update-skill") or once at Phase 0 (quiet, non-blocking):
`pwsh scripts/Update-PsadtSkill.ps1` (read-only, commit-based: `HEAD` vs `origin/<branch>`, or the GitHub
commits-API sha vs the recorded `tooling.skillCommit`; the CHANGELOG version is context only). If
`UpdateAvailable`, show `LocalVersion -> RemoteVersion` + `Behind` + `WhatsNew`, then ask via
`AskUserQuestion`. Only on confirm: `pwsh scripts/Update-PsadtSkill.ps1 -Apply` (git pull --ff-only for a
clone, else branch-zip overwrite of tracked files only - never config/secret/tools/docs). Never auto-apply.
Offline → say so and continue; an update check must never block packaging.

## Workflow

**Phase 0 - Setup.** `pwsh scripts/Get-PsadtConfig.ps1`; if `Exists` and nothing `Missing`, go to intake.
Else run the wizard (ask only missing values via `AskUserQuestion`): paths (`packageRoot` / `outputRoot` /
`intuneWinAppUtil`, offer current values as defaults), languages (`script`=EN, `dossier`=DE), author
(`person` / `company`). Persist with `Set-PsadtConfig.ps1 -Updates @{...}`. Provision (never block):
`Get-PsadtModule.ps1`, `Get-IntuneWinAppUtil.ps1`, and for WinGet only `Get-WinGetModule.ps1`. Optional
direct-upload bootstrap: `New-PsadtEntraApp.ps1` once (WAM sign-in, device-code fallback; creates the
`PSADT Intune Upload` Entra app + admin-consents `DeviceManagementApps.ReadWrite.All` + stores the credential;
needs Global Admin / Privileged Role Admin). Add `-IncludeGroupManagement` to also consent the least-privilege
group roles (`Group.Create` + `GroupMember.Read.All`) when the user wants opt-in group assignment (Phase 7.6 /
guide Appendix M) - off by default. Manual portal route: `references/app-registration.md`.
Re-triggerable via "psadt setup".

**Phase 1 - Intake.** A PSADT v4 package always serves all three deployment types - plan them now, not at the
end. Resolve scope via decision gates 1 + 2 only; pre-fill every option from research. Catalogue: guide Phase 0.2.

**Phase 2 - Research fan-out (parallel sub-agents, no asking back).** Dispatch the three Researcher roles
concurrently, collect into the Phase-0.3 findings table, and show it before scaffold. Record per deployment
type: switch, expected exit codes, log path, known leftovers. **Consult guide Appendix L (installer technologies
+ silent switches) BEFORE web-searching switches**; for a script-only fix/remediation/debloat package (no vendor
installer) follow guide Appendix K instead of the normal installer flow. On a newer PSADT release, ALWAYS diff the
release notes for renamed/deprecated/changed commands before building - never adopt a version by number alone;
verify the actually-used cmdlets with `Get-Command -Module PSAppDeployToolkit` (and `Get-Help <cmdlet>
-Parameter *` for changed params). If divergent, recommend `Update-Module PSAppDeployToolkit -Force` before
scaffold. Queries + version-sync check: guide Phase 0.1 + 0.3, Appendix D. WinGet package discovery (search
by name first; `Find-ADTWinGetPackage`): guide Appendix I.1.

**Phase 3 - Scaffold.** `New-ADTTemplate -Destination <root> -Name <App>` (4.1.x takes only
`-Destination/-Name/-Version/-Force/-Show/-PassThru` - NO app metadata; metadata goes into `$adtSession`
afterwards). Fill `$adtSession` (AppVendor/Name/Version/Arch/Lang/Revision, success + reboot exit codes,
`AppScriptVersion='0.1'`, `AppScriptAuthor` from config) and the `.NOTES` changelog. Verify the module
version == `DeployAppScriptVersion`. WinGet: provision the extension module into the package, `Files\` stays
empty, `AppVersion='Latest'` (or pinned) (guide Appendix I.2). Field details: guide Phase 1.

**Phase 4 - Customize all three hooks.** User drops the installer in `<pkg>\Files\`; fill
`Install/Uninstall/Repair-ADTDeployment` from the research. Per-installer patterns
(MSI/EXE/InstallShield/Squirrel), `Show-ADTInstallationWelcome -CloseProcesses ... -CheckDiskSpace` before
install, Start-Menu-only shortcuts, uninstall cleanup (tasks/services/firewall/registry - only the APP
sub-key, NEVER the vendor root; keep user data by default), and async-retry loops (services need 30-60s after
msiexec): guide Phase 2. WinGet hook patterns: guide Appendix I.3. The GUID-to-`-ProductCode` rule (a GUID to
`-FilePath` throws `InvalidFilePathParameterValue` → 60001) applies to Uninstall AND Repair - Repair is the
usual miss. Custom helpers ALWAYS in `PSAppDeployToolkit.Extensions.psm1`, never the main script.

**Phase 5 - Pre-flight (Reviewer gate).** Run `scripts/Invoke-PsadtPreflight.ps1 -PackagePath <pkg>` - it returns
`{ Overall='GREEN'|'RED'; Checks=@(...) }` and runs all gate checks deterministically: encoding (`HasBOM=True` OR
non-ASCII `Count=0`), AST parse, v3-cmdlet scan (launcher + Extensions only - bundled `Files\*.ps1` are
parse/encoding-only, so a private `Write-Log` there is NOT flagged), top-level-statement scan, the structural
acid-test (all three `*-ADTDeployment` hooks defined + Extensions helpers actually called), and the
GUID-to-`-FilePath` anti-pattern. **`Overall` must be GREEN to proceed** (any RED = STOP, even if Install looks
fine - else Company-Portal uninstall returns 0x80070001). Encoding fix (em-dash/smart-quote replace + UTF-8 BOM)
and per-check explanations: guide Phase 3 (3.1-3.6) + Appendix C. WinGet adds a module-present check and MUST use
the acid-test stub (a live acid test would install): guide Appendix I.4.

**Phase 5.5 - SYSTEM test loop (opt-in; BINDING gate for upload).** `Invoke-PsadtSystemTest.ps1` runs one
action as SYSTEM (via `Invoke-CommandAs`, self-healed from PSGallery; needs an elevated session) and returns
`{ DeploymentType, ExitCode, Success, DetectionState, LogPath, LogTail, ErrorLines, Elevated }`. It fixes
nothing - YOU drive the loop and fix between runs. Gate 3 consent + VM/snapshot first; hard cap
`test.maxIterations` (default 5). Loop: Install → verify detection → Uninstall → verify clean (services,
tasks, app reg key, install dir, firewall; neighbour products of the same vendor still present) → Reinstall.
Converged → leave the machine per `test.endState` (default uninstalled), keep each PSADT log for audit. Cap
reached → blockade protocol, hand back. If you cannot run it (no elevation), STOP before any upload.
Diagnosis mapping: Troubleshooting table + guide Appendix A / G.

**Phase 6 - Package.** Paths from config (`paths.intuneWinAppUtil`, provisioned by `Get-IntuneWinAppUtil.ps1`):
`& $tool -c <pkg> -s 'Invoke-AppDeployToolkit.exe' -o <outputRoot>\<App[-Version]> -q`. `-o` lies outside `-c`
(different trees - never nest, or the old `.intunewin` lands recursively in the package). Copy the detection
script + `Intune-Dossier.html` alongside. Verify the `.intunewin` (`SetupFile` = Invoke-AppDeployToolkit.exe,
size). Code + extractability check: guide Phase 4.

**Phase 7 - HTML report (ALWAYS) + real logo.** Fill `$meta` (key list: guide Appendix F.0), then
`New-PsadtReport.ps1 -Metadata $meta -LogoPath <logo> -OutputPath <Output\<App>\Intune-Dossier.html>`.
Mandatory return codes: `0, 1707 Success; 3010 soft / 1641 hard reboot; 1618 retry; 60001, 60008 Failed` +
researched installer codes. App description = Markdown, dossier language, real umlauts (structure/template:
guide F.2). Logo fetch + verify + MSI-icon fallback: guide Appendix J. WinGet dossier additions
(WinGet >= 1.7.10582 requirement, registry/file detection note): guide Appendix I.6.

**Phase 7.5 - Direct Graph upload (opt-in).** Gate 4. ALWAYS dry-run first (read-only) → show summary +
`On -Execute` action → confirm → `-Execute`. `Invoke-IntuneWin32Upload.ps1` (via `Get-GraphToken.ps1`): MSI →
`-MsiProductCode '{GUID}'`; EXE/non-MSI → `-DetectionScriptPath` (a detection rule accepts only
`ruleType, enforceSignatureCheck, runAs32Bit, scriptContent`; the detect script writes stdout + `exit 0` when
installed, nothing when not). Fill every objective field; impose no category/notes/featured (group assignment
is the separate opt-in Phase 7.6); never DELETE (`-OnExisting CreateNewCoexist`, `-UpdateAppId` only for explicit
in-place, optional `-SupersedesAppId`). Uses `/beta` (v1.0 drops `displayVersion`). `-MinWindowsRelease` is a
`ValidateSet` of backend-accepted release IDs (`1607..2004`); labels like `21H2`/`22H2` are server-rejected -
set a higher minimum in the portal (guide H.11). The script refuses the PSADT default logo (SHA256) unless
`-AllowDefaultLogo`. Graph gotchas: guide Appendix H.

**Phase 7.6 - Group assignment (opt-in).** Only when the user chose it at Gate 2 AND `intune.groups.enabled`.
ALWAYS dry-run first (read-only) → show the planned group names + actions → confirm → `-Execute`.
`Invoke-IntuneAppAssignment.ps1 -AppId <id> -AppName ... -AppVendor ... -AppVersion ... -Intents required,available`
creates/reuses Entra security groups by the config naming scheme (`intune.groups.naming`, version-INDEPENDENT by
default so a new version reuses the same groups; `%version%` is an opt-in that breaks that) and assigns the app
(intents required/available/uninstall). Idempotent; never deletes a group or another app's assignment;
ambiguous/duplicate names are skipped, not guessed. Needs `Group.Create` + `GroupMember.Read.All` on the upload
app (`New-PsadtEntraApp.ps1 -IncludeGroupManagement`). Feed the returned `Groups` into the dossier Assignments
table. Full schema + naming rules + permission model: guide Appendix M.

**Phase 8 - Test sequence (DEV VM, all three types).** Install (ps1 → exe → SYSTEM via
`Invoke-PsadtSystemTest.ps1`, PsExec fallback) → Uninstall on the SAME VM + post-uninstall verification
(detection empty, services/tasks/firewall gone, install dir gone, vendor neighbours intact) → Repair after a
reinstall. Then an Intune test group (1 device, Required; check the PSADT log + AppWorkload.log for `Installed`
/ `Uninstalled` and `Close-ADTSession` exit 0). Steps + checks: guide Phase 6 / Appendix E.

**Phase 9 - Rollout.** All three green → pilot 24-48h → staged production. Guide Phase 7.

## Troubleshooting quick reference

HRESULT: Intune shows positive exit codes as `0x80070000 + code` (`0x80070001` = exit 1 = script never ran;
ignore the "ERROR_INVALID_FUNCTION" text, recompute). Logs in order: AppWorkload.log → PSADT session log →
IntuneManagementExtension.log.

| Symptom | Primary suspect | Fix / verify |
|---|---|---|
| `0x80070001`, no PSADT logs | encoding (em-dash) or top-level throw | Phase 5 checks; guide A.2 |
| `0x8000EA68` (60008), empty PSADT log | Import-Module / Open-ADTSession throws | guide A.2 |
| `0x8000EA61` (60001) + stacktrace | runtime error in the Install hook | stack shows the line |
| `60001 InvalidFilePathParameterValue` on Uninstall/Repair | GUID passed to `-FilePath` | use `-ProductCode '{GUID}'`; guide G |
| App stuck on "Installing" in Company Portal | IME state cache / process hang | guide A.2 cleanup sequence |
| `0x80070002` | launcher cannot find the .ps1 | `-s` during packaging was wrong |
| `0x80070643` (1603) MSI fatal error | perms / disk / **pending reboot** / bad property / failed custom action | clear pending reboot, read the `/l*v` MSI log; guide A.4 |
| `0x80070666` (1638) "another version installed" | older ProductCode still present | uninstall old first, or ship a real upgrade; guide A.4 |
| exit 1605 on uninstall | product already gone | treat as success (map 1605); guide A.4 |
| detection failed after a successful install | detection-script bug (contract / 32-64-bit reg) | run `.\Detect-*.ps1; $LASTEXITCODE` on target |
| SYSTEM test: every step `ExitCode=0 Success=False` | ran under pwsh 7 (PSScheduledJob is WinPS-5.1-only) | re-run under powershell.exe 5.1; guide G |
| upload `must have at least one detection rule` (rule WAS sent) | needs the unified `rules`, `@odata.type` first | `[ordered]@{}`; guide H |
| upload `commitFileFailed` after blocks "OK" | `Invoke-RestMethod -Body <byte[]>` corrupts the blob | HttpClient/ByteArrayContent; guide H |
| `displayVersion` empty after upload | v1.0 backend drops it | write on `/beta`; guide H |
| upload `403` on probe/create | app consent missing/ineffective | re-run `New-PsadtEntraApp.ps1`; guide H |
| detection rule rejected (`property may not be set ... used for app detection`) | requirement-only props on a detection rule | keep only `ruleType,enforceSignatureCheck,runAs32Bit,scriptContent`; guide H.2 |
| upload `BadRequest: Unknown MinimumSupportedWindowsRelease` | `-MinWindowsRelease` value the backend rejects (e.g. `21H2`/`22H2`) | use a backend-accepted ID `1607..2004`; set a higher min in the portal; guide H.11 |
| assignment `Group assignment is not enabled` | `intune.groups` absent/`enabled=false` in the resolved config | configure `intune.groups` (App. M) / point `-SkillRoot` at the install holding the config |
| assignment denied on group lookup/create (`Authorization`) | upload app lacks `GroupMember.Read.All` / `Group.Create` | `New-PsadtEntraApp.ps1 -IncludeGroupManagement` (Global Admin); guide M.1 |

Full symptom/HRESULT catalogue: guide Appendix A.

## Anti-patterns (top offenders; full list: guide Appendix B + I.7)

- v3 cmdlet names (`Execute-Process`, `Write-Log`, `Show-InstallationWelcome`, ...).
- Em-dash/smart quote anywhere in a script file (comments too) - 7-bit ASCII only; the #1 encoding failure.
- UTF-8 without BOM when non-ASCII is present; top-level code outside try/catch.
- `-o` inside `-c`; not mapping 60001/60008 as Failed; "runs locally = runs in Intune" without the acid test.
- GUID to `Start-ADTMsiProcess -FilePath` (Uninstall AND Repair - Repair is the usual miss).
- Mixed detection (script + file rule in parallel); MSI ProductCode rule for a non-MSI app (use a script rule).
- Shipping the PSADT default `AppIcon.png`/Banner as the logo; trusting `IsAlphaPixelFormat` for transparency.
- Defaulting to / recommending / auto-selecting WinGet (strictly opt-in); `-Scope User`;
  `Get-ADTWinGetPackage` in detection; skipping `Repair-ADTWinGetPackageManager`; bare WinGet cmdlets without
  the `ADT` prefix.
- DELETING/overwriting the older version on upload; branding in `notes`; auto-assigning category/featured, or
  assigning groups when the user did NOT opt in at Gate 2; filling only the minimum App-info fields.
- Baking `%version%` into the group naming scheme by reflex (breaks version-independent group reuse for
  supersedence); putting a `%intent%` token in a name (no such token - the intent is the template key, App. M).
- Skipping the HTML report; hand-assembling the report HTML; HTML in the Markdown-only description field.
- Desktop icons; Extensions logic in the main script; reflexive 120-min install time (60 is usually right);
  fallback deletes on the first negative async response (build a retry loop).
- Uploading without the Phase 5.5 SYSTEM test passing Install + Uninstall.
- Hand-rolling the pre-flight gate instead of running `scripts/Invoke-PsadtPreflight.ps1` (the GREEN/RED verdict
  is the gate); for a script-only fix, treating it like a vendor installer instead of following Appendix K.
- A blanket `exit 0` in a fix/remediation script, or a detection tag written in a `finally` - both report GREEN
  on failure. The exit code must reflect "could it run" (couldn't-run -> non-zero), detection the real end-state;
  never block enrollment by lying about the exit code (guide K.7).

## Reference lookup

`references/PSADTv4-Deployment-Guide.md` - Phase 0.2 intake catalogue · 0.1/0.3 research · Phase 1 scaffold ·
2 customize · 3 pre-flight · 4 package · 5 Intune config fields · 6 test · 7 rollout · App. A errors ·
B anti-patterns · C test stubs · D URLs · E deploy checklist · F dossier template (all fields) · G lessons
learned · H direct Graph upload · **I WinGet packaging** · **J app-logo acquisition + verification** ·
**K script-only / remediation packages (ESP-safe)** · **L installer technologies + silent switches** ·
**M group assignment (opt-in: config, naming, permissions)**.
