# PSADT v4.x Deployment Guide - Intune

Verbindliche End-to-End-Anleitung fuer Intune-Win32-Pakete mit PSADT 4.x. In dieser Reihenfolge abarbeiten. Keine Phasen ueberspringen.

- **Phase 0**: Recherche + Intake (VOR dem ersten Klick)
- **Phase 1**: Scaffold via `New-ADTTemplate`
- **Phase 2**: Script-Customizing
- **Phase 3**: Pre-Flight-Checks (Encoding, Parse, Launcher-Simulation)
- **Phase 4**: .intunewin bauen
- **Phase 5**: Intune-App-Konfiguration
- **Phase 6**: Test-Sequenz
- **Phase 7**: Rollout
- **Anhaenge**: A Error-Ref / B Anti-Patterns / C Stub-Tricks / D Ressourcen / E Final-Checklist / F Intune-Upload-Dossier / G Lessons Learned

---

## Phase 0: Recherche + Intake (NICHT ueberspringen)

### 0.1 Aktuelle PSADT-Version pruefen

Bevor irgendein Paket gebaut wird: ist das lokale PSADT-Modul noch aktuell? Breaking Changes zwischen Minor-Versionen kommen vor (4.0.x -> 4.1.x Param-Umbenennungen).

**Check-Befehle (online + lokal):**

```powershell
# Lokale Modulversion
Get-Module -ListAvailable -Name PSAppDeployToolkit | Select-Object Version,Path

# Neueste Release-Info von GitHub (API, ohne Auth)
$rel = Invoke-RestMethod 'https://api.github.com/repos/PSAppDeployToolkit/PSAppDeployToolkit/releases/latest'
"Neueste: $($rel.tag_name) vom $($rel.published_at)"
$rel.body -split "`n" | Select-Object -First 40   # Changelog-Auszug
```

**Docs-Stand pruefen:**
- Release-Notes: https://psappdeploytoolkit.com/docs/getting-started/release-notes
- Migrations-Guide (v3 -> v4): https://psappdeploytoolkit.com/docs/migration/migrate-from-v3
- Reference-Index (alle Cmdlets): https://psappdeploytoolkit.com/docs/reference
- Blog (Releases + Community Updates): https://psappdeploytoolkit.com/blog
- Discourse (Forum): https://discourse.psappdeploytoolkit.com/latest

**Entscheidung:**
- Lokal < Latest Minor: Modul aktualisieren (`Update-Module PSAppDeployToolkit -Force` oder aus GitHub-Release entpacken) BEVOR neues Paket gebaut wird
- Lokal == Latest: weiter
- Lokal > Latest (Beta): auf stable downgraden, keine Beta in Prod

Die Modul-Version muss im Paket `<pkg>\PSAppDeployToolkit\PSAppDeployToolkit.psd1` `ModuleVersion = '<VER>'` exakt zu dem passen, was im Script `$adtSession.DeployAppScriptVersion = '<VER>'` steht UND zur `Invoke-AppDeployToolkit.exe`-Build-Version (RightClick-Properties-Details).

### 0.2 Intake-Fragen zur App (bevor auch nur eine Zeile Code entsteht)

Ohne Antworten zu diesen Punkten wird das Paket Mist. Mit Stakeholder / User klaeren:

**App-Identitaet:**
- Exakter Produktname und Hersteller (wie im Company Portal stehen soll)
- Version (Marketing-Version + Dateiversion im MSI / Setup.exe)
- Sprache (EN, DE, Multi?)
- Architektur (x86 / x64 / ARM64 / Universal)
- Lizenzmodell (Freeware, Pro, Enterprise, Named User, Device, Subscription? Lizenzkey noetig? Activation-Server?)

**Installer:**
- Quell-Medium: MSI, EXE-Wrapper (um MSI), InstallShield, NSIS, AppX/MSIX, Squirrel, selbstgebautes?
- Download-URL des offiziellen Installers (fuer Reproduzierbarkeit) + Hash
- Silent-Install-Switches bekannt? (siehe 0.3)
- Uninstall-Methode: MSI-ProductCode, Uninstallstring in Registry, Custom-Uninstaller?
- Repair-Unterstuetzung?
- Reboot-Verhalten (erfordert, empfiehlt, nie)
- Abhaengigkeiten: .NET, VC++ Redist, Java, Edge-WebView2, PowerShell-Version?

**Ziel-Umgebung:**
- Intune-Zielgruppe (User- oder Device-based? AAD-Gruppe, Filter?)
- Install-Context: System (klassisch), User (selten), Available + Required?
- Min-OS-Version, Architecture-Filter
- Koexistenz mit Vorversionen: Upgrade-in-Place, Side-by-Side, Force-Uninstall-Altversionen?
- Conflicting-Apps: gibt's konkurrierende Produkte die raus muessen?
- Roaming-Profile / FSLogix / Nicht-persistente-VDI?

**Laufzeitverhalten:**
- Prozesse die geschlossen werden muessen (fuer `AppProcessesToClose` in `$adtSession`)
- Sichtbare UI waehrend Install (Silent vs. NonInteractive)? 
- User-Benachrichtigungen gewuenscht (Welcome-Dialog, Defer-Button, Countdown)?
- Erforderliche Umgebungsvariablen / Registry-Policies
- Firewall-Regeln / Service-Konten

**Konfiguration / Customizing:**
- Default-Settings die ueberschrieben werden sollen (Startup-Behavior, Telemetrie-Opt-Out, Updater-Abschaltung, Default-Ordner)
- Registry-Keys / ADMX / XML / JSON zum Injizieren
- Files-to-Copy in AppData / ProgramData
- Shortcuts (Desktop, StartMenu) platzieren oder entfernen?

**Detection:**
- Wie eindeutig nachweisen dass installiert? MSI-ProductCode ist meist genug; bei EXE-Installern oft File-Version + Registry.
- Zwingend funktionaler Test (z.B. "DB erreichbar", "Service laeuft") oder reicht Presence-Check?

**Uninstall / Cleanup:**
- Was MUSS weggeraeumt werden bei Uninstall (User-Daten behalten? Registry-Leichen entfernen?)
- Was DARF NICHT geloescht werden (Shared-Komponenten, User-Templates)?
- Soll Uninstall auch Vorversionen killen oder nur die selbst installierte?

**Sicherheit:**
- Credentials im Installer noetig (Service-Account, API-Key, Cert)? Wie werden die an den Install uebergeben ohne im Log/Filesystem zu landen?
- PII / GDPR-relevante Konfiguration?
- Signaturprufung erwartet?

Diese Liste als Intake-Formular nehmen; was offen bleibt = Risiko im Deploy.

### 0.3 Web-Recherche zum konkreten Installer

Pro App recherchieren - ohne diese Antworten kein erfolgreiches Silent-Install:

**Pflicht-Such-Queries (Beispiele):**
```
"<AppName>" "<Version>" silent install command line
"<AppName>" msi transform mst enterprise deployment
"<AppName>" uninstall silent /quiet /qn
"<AppName>" site:<hersteller-docs-domain> deployment guide
"<AppName>" known issues intune win32
```

**Offizielle Quellen immer zuerst:**
- Hersteller-Admin-Guide / Enterprise-Deployment-Guide (Adobe Admin Console, Autodesk Enterprise, Microsoft Docs, ...)
- Release-Notes fuer die spezifische Version
- Knowledge Base / Support Forum des Herstellers

**Community-Quellen (zur Validierung):**
- `silentinstallhq.com` - Silent-Switches fuer viele Apps
- `deploymentresearch.com` - Tim Mangans Archiv
- PSADT Discourse: https://discourse.psappdeploytoolkit.com/search
- `/r/SCCM`, `/r/Intune` auf Reddit
- GitHub: Suche nach `<appname> intune win32` oder `<appname> PSADT`

**Minimal-Ergebnis dokumentieren:**

| Frage | Antwort | Quelle |
|---|---|---|
| Silent-Install-CMD | `<...>` | |
| Silent-Uninstall-CMD | `<...>` | |
| Bekannte Exit-Codes (Erfolg, Reboot, Fehler) | `0, 3010, ...` | |
| Logfile-Pfad des Installers | `<...>` | |
| Dependency-Installer (wenn separat) | `<...>` | |
| Bekannte Intune-Stolpersteine | `<...>` | |
| Known-Post-Install-Config (Registry / XML) | `<...>` | |

Ohne diese Tabelle ausgefuellt: **nicht packen**.

**Beispiel (Adobe Acrobat Pro):**
- Admin-Guide: https://www.adobe.com/devnet-docs/acrobatetk/
- Customization Wizard (MST bauen): https://www.adobe.com/devnet-docs/acrobatetk/tools/Wizard/index.html
- Package via Adobe Admin Console (Creative Cloud): offizieller Weg fuer neuere Versionen

**Beispiel (Oracle Database XE):**
- Doku: https://docs.oracle.com/en/database/oracle/oracle-database/21/xeinw/
- Silent-Install: `setup.exe /s /f1"XEInstall.rsp"` + Response-File
- Bekannter Stolperstein: `svc_oracle` muss VOR Install existieren (deshalb im Script der Service-Account-Create)

---

## Phase 1: Scaffold via `New-ADTTemplate`

Nicht manuell Ordner anlegen. Der offizielle Cmdlet baut die korrekte Struktur.

### 1.1 Modul laden, Scaffold erzeugen

```powershell
# Einmalig - oder wenn Version veraltet
Install-Module PSAppDeployToolkit -Scope CurrentUser -Force
# Alternativ: vom GitHub-Release .zip runterladen und manuell nach $HOME\Documents\PowerShell\Modules\PSAppDeployToolkit\<ver>\ entpacken

Import-Module PSAppDeployToolkit
```

Werte kommen aus dem Intake aus Phase 0.2 - ersetze `<...>` durch die TATSAECHLICHEN Werte der App, die gerade paketiert wird.

**Basic-Scaffold (nur Destination + Name):**
```powershell
New-ADTTemplate -Destination '<Root-Ordner>' -Name '<AppName>'
# z.B. New-ADTTemplate -Destination 'C:\Temp\PSADTv4' -Name 'FooBar 10'
```

Erzeugt `<Root-Ordner>\<AppName>\` mit kompletter v4-Struktur. Standard ist `-Version 4` (aktueller v4-Stil). `-Version 3` gibt das v3-Kompatibilitaets-Template (braucht man 2026 nicht mehr).

**Extended-Scaffold (vorbefuellt mit App-Metadaten, Werte aus Phase 0.2):**
```powershell
New-ADTTemplate -Destination '<Root-Ordner>' `
    -Name '<AppName>' `
    -AppVendor '<Hersteller>' `
    -AppName '<ProduktKurzname>' `
    -AppVersion '<Major.Minor.Build.Rev>' `
    -AppArch '<x64|x86|ARM64>' `
    -AppLang '<EN|DE|Multi>' `
    -AppRevision '<01>' `
    -AppSuccessExitCodes @(<0>, <1707>) `
    -AppRebootExitCodes @(<1641>, <3010>) `
    -AppScriptAuthor '<Vorname Nachname>'
```

Die Werte landen direkt als `$adtSession = @{...}` im generierten `Invoke-AppDeployToolkit.ps1`. Weniger manuelles Editieren = weniger Tippfehler.

> Die `Adobe Acrobat Pro`- und `Oracle XE`-Referenzen weiter unten im Dokument sind ausschliesslich Illustration - bei jedem neuen Paket wird hier die ZU PAKETIERENDE App eingesetzt, nicht Adobe oder Oracle.

### 1.2 Was im Scaffold entsteht

```
<Destination>\<Name>\
  Invoke-AppDeployToolkit.exe          # 4.x Launcher
  Invoke-AppDeployToolkit.ps1          # Template mit Pre/Install/Post-Hooks
  PSAppDeployToolkit\                  # Komplettes Modul (psd1 + psm1 + lib\)
  PSAppDeployToolkit.Extensions\       # Leere Extension-Shell (eigenes Code-Home)
  Files\                               # Hier kommen Installer-Binaries rein
  SupportFiles\                        # MST, INI, XML, Scripts
  Assets\                              # Icon (AppIcon.png), Logos
  Config\                              # PSADT Config-Overrides (optional)
  Strings\                             # Lokalisierungs-Overrides (optional)
```

### 1.3 Erste Verifizierung des Scaffolds

```powershell
$pkg = '<Scaffold-Pfad>'   # z.B. 'C:\Temp\PSADTv4\<AppName>'
# Modulversion im Scaffold muss der installierten Version entsprechen
(Import-PowerShellDataFile "$pkg\PSAppDeployToolkit\PSAppDeployToolkit.psd1").ModuleVersion
# Template-Version im Script
Select-String "$pkg\Invoke-AppDeployToolkit.ps1" -Pattern 'DeployAppScriptVersion' -List | Select-Object Line
```

Beides muss matchen (typisch `4.1.8`). Wenn divergent -> Modul neu installieren + neu scaffolden.

---

## Phase 2: Script-Customizing

### 2.1 Installer in `Files\` legen

Alles was `setup.exe`, `*.msi`, `*.mst`, Response-Files, Runtime-Assets ist, landet unter `<pkg>\Files\`.
Im Script dann `$adtSession.DirFiles` als Root.

### 2.2 `$adtSession`-Metadaten finalisieren

Im `Invoke-AppDeployToolkit.ps1` den Hashtable pruefen (siehe 0.2 Intake fuer die Werte):

```powershell
$adtSession = @{
    AppVendor                   = '<Hersteller>'
    AppName                     = '<Produkt-Kurzname>'
    AppVersion                  = '<Major.Minor.Build.Rev>'
    AppArch                     = '<x64|x86|ARM64>'
    AppLang                     = '<EN|DE|Multi>'
    AppRevision                 = '<01>'
    AppSuccessExitCodes         = @(0, 1707)                           # Installer-spezifisch ergaenzen
    AppRebootExitCodes          = @(1641, 3010)
    AppProcessesToClose         = @('<prozess1>', '<prozess2>')        # Namen ohne .exe; aus Phase 0.2
    AppScriptVersion            = '<1.0.0>'
    AppScriptDate               = '<YYYY-MM-DD>'
    AppScriptAuthor             = '<Vorname Nachname>'
    RequireAdmin                = $true
    InstallName                 = ''
    InstallTitle                = ''
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters   = $PSBoundParameters                    # oder sanitized Dictionary wenn Secrets
    DeployAppScriptVersion      = '<passend zur ModuleVersion im Scaffold>'
}
```

### 2.3 Install/Uninstall/Repair-Hooks fuellen

Das Scaffold hat drei leere Funktionen: `Install-ADTDeployment`, `Uninstall-ADTDeployment`, `Repair-ADTDeployment`. Jede hat Pre/Install/Post-MARK-Abschnitte.

**Minimal-Pattern fuer MSI:**
```powershell
function Install-ADTDeployment {
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"
    Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -CheckDiskSpace -RequiredDiskSpace 3000
    Show-ADTInstallationProgress

    $adtSession.InstallPhase = $adtSession.DeploymentType
    Start-ADTMsiProcess -FilePath "$($adtSession.DirFiles)\<installer>.msi" -Transforms "$($adtSession.DirSupportFiles)\<transform>.mst" -ArgumentList '/qn REBOOT=ReallySuppress'

    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"
    # Shortcuts aufraeumen, Registry-Keys setzen, Update-Service deaktivieren, etc.
}
```

**Pattern fuer EXE-Wrapper:**
```powershell
Start-ADTProcess -FilePath "$($adtSession.DirFiles)\setup.exe" -ArgumentList '/silent /allusers=1 /log="C:\Windows\Logs\Software\install.log"' -SuccessExitCodes @(0, 3010, 1641) -WaitForMsiExec
```

Immer `-SuccessExitCodes` mitgeben - sonst wirft Start-ADTProcess bei allem != 0.

### 2.4 Extensions-Modul fuer Helper-Funktionen

Custom-Helpers gehoeren in `<pkg>\PSAppDeployToolkit.Extensions\PSAppDeployToolkit.Extensions.psm1` - NICHT direkt ins Main-Script. Gruende: Wiederverwendung, saubere Namespaces, Main-Script bleibt lesbar.

```powershell
# PSAppDeployToolkit.Extensions.psm1
function Set-CompanyBranding { ... }
function Disable-AppUpdater    { ... }
Export-ModuleMember -Function Set-CompanyBranding, Disable-AppUpdater
```

Das Main-Script lädt die Extensions automatisch (der Block `Get-ChildItem ... -match 'PSAppDeployToolkit\..+$'` am Ende von `Invoke-AppDeployToolkit.ps1`).

---

## Phase 3: Pre-Flight-Checks

Alles aus dieser Phase ausfuehren. Jeder Fehlschlag = NICHT weiter.

### 3.1 Encoding-Check (UTF-8 mit BOM oder ASCII-only)

PowerShell 5.1 liest .ps1 ohne BOM als Windows-1252. UTF-8-Multibytes (Em-Dash `—`, Pfeil `→`, Umlaute, typografische Quotes, Ellipsis `…`) zerfallen. In Double-Quoted Strings **schliesst** ein falsch interpretierter Em-Dash den String vorzeitig (UTF-8 `E2 80 94` -> CP1252 `â€"`, letztes Byte = `"`). Parse-Error. Script laeuft NIE. Intune zeigt `0x80070001`, keine lokalen Logs.

```powershell
$s = '<pfad-zur-ps1>'
$bytes = [System.IO.File]::ReadAllBytes($s)
$hasBom = $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
$text = [System.IO.File]::ReadAllText($s, [System.Text.Encoding]::UTF8)
$nonAscii = [regex]::Matches($text, '[^\x00-\x7F]') | ForEach-Object { $_.Value } | Sort-Object -Unique
"HasBOM=$hasBom NonAscii=$($nonAscii -join ' ') Count=$(([regex]::Matches($text,'[^\x00-\x7F]')).Count)"
```

Akzeptanzkriterium: `HasBOM=True` ODER `Count=0`. Beides = Defense-in-Depth.

Fix, wenn nicht:
```powershell
$text = [System.IO.File]::ReadAllText($s, [System.Text.Encoding]::UTF8)
$text = $text -replace [char]0x2014, '-'      # em-dash
$text = $text -replace [char]0x2013, '-'      # en-dash
$text = $text -replace [char]0x2192, '->'     # right arrow
$text = $text -replace [char]0x2018, "'"      # left single quote
$text = $text -replace [char]0x2019, "'"      # right single quote
$text = $text -replace [char]0x201C, '"'      # left double quote
$text = $text -replace [char]0x201D, '"'      # right double quote
$text = $text -replace [char]0x2026, '...'    # ellipsis
[System.IO.File]::WriteAllText($s, $text, [System.Text.UTF8Encoding]::new($true))
```

### 3.2 Parse-Check

```powershell
$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($s, [ref]$null, [ref]$errs)
if ($errs) { $errs | Select Message,@{N='L';E={$_.Extent.StartLineNumber}} } else { 'PARSE_OK' }
```

WICHTIG: `Parser::ParseFile` detektiert UTF-8-ohne-BOM korrekt und meldet oft `PARSE_OK` obwohl powershell.exe via Launcher trotzdem knallt. Der 3.3-Test ist der ECHTE Gate.

### 3.3 Launcher-Simulation (Acid-Test)

Der `Invoke-AppDeployToolkit.exe`-Launcher ruft PS5.1 mit `-Command "try { & 'script.ps1' ... } catch { throw }; exit $Global:LASTEXITCODE"` auf. Genau das replizieren:

```powershell
Start-Process powershell.exe -ArgumentList `
    '-ExecutionPolicy','Bypass','-NonInteractive','-NoProfile','-NoLogo',`
    '-Command', "try { & '$s' -DeploymentType Install -DeployMode Silent } catch { throw }; exit `$Global:LASTEXITCODE" `
    -Wait -NoNewWindow -RedirectStandardError stderr.log
Get-Content stderr.log
```

Parse-Errors im stderr trotz gruenem 3.2 = Encoding-Bug, zurueck zu 3.1.

Bei Scripten die echte Installer anstossen: Install-ADTDeployment-Body stubben (siehe Anhang C).

### 3.4 Param-Block vs. v4-Template

Param-Block im Main-Script muss zu `<pkg>\PSAppDeployToolkit\Frontend\v4\Invoke-AppDeployToolkit.ps1` passen. Stand 4.1.8:

```powershell
[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)][ValidateSet('Install','Uninstall','Repair')][System.String]$DeploymentType,
    [Parameter(Mandatory=$false)][ValidateSet('Auto','Interactive','NonInteractive','Silent')][System.String]$DeployMode,
    [Parameter(Mandatory=$false)][System.Management.Automation.SwitchParameter]$SuppressRebootPassThru,
    [Parameter(Mandatory=$false)][System.Management.Automation.SwitchParameter]$TerminalServerMode,
    [Parameter(Mandatory=$false)][System.Management.Automation.SwitchParameter]$DisableLogging
)
```

NICHT: `$AllowRebootPassThru` (v3-Denken). Eigene Parameter (z.B. `$DbPassword`) hinten anhaengen, VOR `Open-ADTSession` aus `$iadtParams` entfernen.

### 3.5 v3-Cmdlet-Rueckstaende

Verboten im Code:

| v3 (weg) | v4 (richtig) |
|---|---|
| `Execute-Process` | `Start-ADTProcess` |
| `Execute-MSI` | `Start-ADTMsiProcess` |
| `Write-Log` | `Write-ADTLogEntry` |
| `Show-InstallationWelcome` | `Show-ADTInstallationWelcome` |
| `Show-InstallationProgress` | `Show-ADTInstallationProgress` |
| `Show-InstallationPrompt` | `Show-ADTInstallationPrompt` |
| `Show-InstallationRestartPrompt` | `Show-ADTInstallationRestartPrompt` |
| `Get-InstalledApplication` | `Get-ADTApplication` |
| `Remove-MSIApplications` | `Remove-ADTApplication` |
| `Test-PowerPoint` | `Test-ADTPowerPoint` |
| `Get-LoggedOnUser` | `Get-ADTLoggedOnUser` |
| `Block-AppExecution` | `Block-ADTAppExecution` |
| `Refresh-Desktop` | `Update-ADTDesktop` |
| `Update-GroupPolicy` | `Update-ADTGroupPolicy` |

Scan:
```powershell
$v3 = @('Execute-Process','Execute-MSI','Write-Log','Show-InstallationWelcome','Show-InstallationProgress','Show-InstallationPrompt','Get-InstalledApplication','Remove-MSIApplications','Refresh-Desktop','Update-GroupPolicy','Block-AppExecution')
$t = [System.IO.File]::ReadAllText($s)
foreach ($fn in $v3) { $m = [regex]::Matches($t, "\b$fn\b"); if ($m.Count) { "V3_FOUND: $fn ($($m.Count)x)" } }
```

### 3.6 Top-Level-Statements ausserhalb try/catch

Alles was NICHT in einem try/catch ist und wirft = exit 1 = kein Log. Top-Level erlaubt nur Attribute, Param-Block, simple `$var = @{...}`, Preference-Variablen, `Set-StrictMode`, `try/catch`.

```powershell
$ast = [System.Management.Automation.Language.Parser]::ParseFile($s, [ref]$null, [ref]$null)
$ast.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] } |
    ForEach-Object { "L$($_.Extent.StartLineNumber): $($_.GetType().Name)" }
```

Alles was kein `AssignmentStatementAst` / `PipelineAst` (fuer Set-StrictMode) / `TryStatementAst` ist = pruefen.

---

## Phase 4: .intunewin bauen

### 4.1 IntuneWinAppUtil holen

Microsoft's offizielles Packaging-Tool. Immer die aktuelle Version:
- GitHub: https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool
- Direct-Download (releases/latest): `https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/releases/latest`

```powershell
$tool = 'C:\Tools\IntuneWinAppUtil.exe'
if (-not (Test-Path $tool)) {
    New-Item 'C:\Tools' -ItemType Directory -Force | Out-Null
    $latest = Invoke-RestMethod 'https://api.github.com/repos/microsoft/Microsoft-Win32-Content-Prep-Tool/releases/latest'
    $asset = $latest.assets | Where-Object { $_.name -eq 'IntuneWinAppUtil.exe' } | Select-Object -First 1
    Invoke-WebRequest $asset.browser_download_url -OutFile $tool
}
& $tool -v
```

### 4.2 Packen

```powershell
$src = '<Paketordner aus Phase 1>'                  # z.B. 'C:\Temp\PSADTv4\<AppName>'
$setupFile = 'Invoke-AppDeployToolkit.exe'         # IMMER die .exe, NICHT die .ps1
$out = '<Ausgabeordner AUSSERHALB von $src>'       # z.B. 'C:\Temp\PSADTv4\_output\<AppName>' - NICHT im src!
New-Item $out -ItemType Directory -Force | Out-Null

& $tool -c $src -s $setupFile -o $out -q
```

Parameter:
- `-c <srcDir>` - der Paketordner mit .exe + .ps1 + PSAppDeployToolkit + Files
- `-s <setupFile>` - relativer Pfad (zu `-c`) zur Entry-.exe. IMMER `Invoke-AppDeployToolkit.exe`, **nicht** `.ps1` (Launcher braucht WDAC-Kompatibilitaet und 64-bit-PS-Bootstrap)
- `-o <outDir>` - Ausgabeordner fuer die .intunewin - **nicht** in `-c` rein, sonst packt ein Rebuild die alte .intunewin mit ein (nested, doppelter Speicher)
- `-q` - quiet, keine Eingabe-Prompts
- `-a <catalogFolder>` - optional, Katalogdateien fuer WDAC-signierte Umgebungen
- `-e` - verschluesselungs-Output-Info (interessant fuer Tooling, nicht fuer Intune)

Ergebnis-Plausibilitaet:
```powershell
$iw = Get-ChildItem "$out\*.intunewin" | Select-Object -First 1
"Size: $([Math]::Round($iw.Length / 1MB, 1)) MB"
"Approx Files/-Size: $([Math]::Round(((Get-ChildItem "$src\Files" -Recurse -File | Measure-Object -Property Length -Sum).Sum) / 1MB, 1)) MB"
```

Drastisch groesser als Files + 20-50 MB Toolkit = nested .intunewin, `-o` war im `-c`, neu packen mit externem Output.

### 4.3 Entpackbarkeit pruefen (offline)

Die .intunewin ist eine AES-verschluesselte ZIP. Ohne Intune nicht entpackbar, aber das Outer-ZIP hat eine Metadata-XML die unverschluesselt zugaenglich ist:

```powershell
Expand-Archive -Path $iw.FullName -DestinationPath "$env:TEMP\iw-inspect" -Force
Get-Content "$env:TEMP\iw-inspect\IntuneWinPackage\Metadata\Detection.xml"
```

Die XML muss `<SetupFile>Invoke-AppDeployToolkit.exe</SetupFile>` enthalten. Wenn da was anderes steht: falscher `-s` beim Packen.

---

## Phase 5: Intune-App-Konfiguration

### 5.1 App Information
- Name / Version / Publisher: matched zu `$adtSession.AppName / AppVersion / AppVendor`
- Description: Markdown-faehig, erster Absatz standalone lesbar (~200 Zeichen sind die Kurzvorschau im Company Portal)
- Category: semantisch korrekt waehlen (Development, Productivity, ...)
- Logo: `<pkg>\Assets\AppIcon.png`, 256x256 PNG transparent

### 5.2 Program
- **Install command**: `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent`
- **Uninstall command**: `Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent` (Case egal, ValidateSet ist case-insensitive)
- **Install behavior**: `System` (Default; SYSTEM-Context ist richtig fuer Win32-Apps)
- **Device restart behavior**: 
  - `App install may force a device restart` - wenn Installer 1641 liefern kann
  - `Determine behavior based on return codes` - default, greift auf Return-Codes-Mapping zurueck
- **Allow available uninstall**: Yes (erlaubt User Uninstall ueber Company Portal)

### 5.3 Return codes (kritisch, nie auslassen)

Pflicht-Mapping, sonst zeigt Intune unbekannte Exit-Codes als `0x80070000 + code`:

| Code | Type | Grund |
|---:|---|---|
| 0 | Success | OK |
| 1707 | Success | MSI-Success-Alternative |
| 3010 | Soft reboot | Reboot empfohlen |
| 1641 | Hard reboot | Reboot erzwungen |
| 1618 | Retry | Parallele MSI laeuft |
| 60001 | **Failed** | PSADT Unhandled Script Error |
| 60008 | **Failed** | PSADT Init fehlgeschlagen (Module Import / Open-ADTSession) |

Zusaetzlich die installer-spezifischen Codes aus 0.3 eintragen.

### 5.4 Requirements
- **OS architecture**: `x64` wenn Script `AppArch='x64'`, sonst entsprechend
- **Minimum OS**: realistisch (Win11 22H2, Win10 22H2) - nicht `1607`, das ist Legacy-Offenlassen
- **Disk space**: wenn Installer viel braucht - spart Zeit bei kleinen Platten
- **Physical memory**: nur bei echt speicherhungrigen Installern
- **Additional requirement rules**: Registry / File / Script - fuer alles was ueber Standardrequirements hinausgeht (z.B. Domain-Join-Pruefung, spezifische Build-Nummer)

### 5.5 Detection rules

Drei Optionen, Reihenfolge der Robustheit:

1. **Custom Detection Script** (bevorzugt fuer komplexe Installs):
   - Contract: `exit 0 + stdout non-empty` = installed; `exit 0 + stdout empty` = not installed; `exit != 0` = Detection-Error, Retry
   - Meist: `Enforce script signature check = No` (ausser in streng signierter Umgebung)
   - Meist: `Run as 32-bit on 64-bit = No` (sonst falscher Registry-View)

2. **MSI Product Code**: fuer reine MSI-Installer die ihren ProductCode stabil halten

3. **File / Registry / Version**: fuer einfache Faelle - EIN Kriterium, nicht mehrere gemischt

**Pflicht**: Detection-Methode ist **eindeutig** - nicht Custom-Script PLUS File-Rule; das gibt widerspruechliche Antworten.

### 5.6 Install time required
- Default 60 min reicht fuer die meisten Installer
- Nur wenn dokumentiert >45 min, hochziehen
- Nicht reflexartig 120 min ("mehr ist besser" stimmt hier nicht - Intune behaelt den Prozess dann extrem lang am Leben)

### 5.7 Assignments
- `Required` fuer Pflicht-Rollout auf Device- oder User-Gruppe
- `Available for enrolled devices` fuer Self-Service via Company Portal
- `Uninstall` als Pseudo-Assignment um Apps gezielt wieder zu entfernen
- **Filter** verwenden fuer dynamische Einschraenkungen (OS-Version, Device-Name-Regex, AzureAD-Join-Type)
- **Delivery Optimization**: fuer grosse Pakete Peer-to-Peer aktivieren
- **Dependencies / Supersedence**: wenn die App andere PSADT-Pakete voraussetzt oder Vorversionen ersetzt
- **App availability / Deadline / Grace period**: fuer Required-Apps mit Reboot-Auswirkung

---

## Phase 6: Test-Sequenz

In dieser Reihenfolge auf DEV-VM (nicht Prod).

### 6.1 Direct-Invoke (Smoke-Test)
```powershell
.\Invoke-AppDeployToolkit.ps1 -DeploymentType Install -DeployMode Silent
```
Laeuft durch = Script-Logik OK.
Laeuft nicht durch = dein Code-Bug, nicht Intune-Problem.

### 6.2 Launcher-Invoke (Acid-Test)
```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent
```
Laeuft durch = Encoding / Param-Block-Sync OK.
Laeuft nicht durch aber 6.1 ja = siehe 3.1 (Encoding), 3.4 (Params), 3.6 (Top-Level-Throws).

### 6.3 SYSTEM-Context (IME-Realitaet)
```cmd
psexec -s -accepteula cmd /c "cd /d <pkg> && Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent"
```
PsExec: https://learn.microsoft.com/en-us/sysinternals/downloads/psexec
Laeuft durch = keine User-Session-Abhaengigkeit. Dieser Test muss gruen sein BEVOR Upload.

### 6.4 Testgruppen-Deploy
Dedizierte Intune-Testgruppe mit 1 VM. Deployment beobachten:
- `C:\Windows\Logs\Software\*PSAppDeployToolkit_Install.log` muss existieren + `Close-ADTSession` mit Exit 0 drin
- `AppWorkload.log` zeigt `Status: Installed`
- Detection-Script liefert `exit 0 + stdout non-empty`

Erst nach Erfolg: Production-Rollout.

---

## Phase 7: Rollout

### 7.1 Staged Rollout
- Pilot-Gruppe (10-50 Geraete) fuer 24-48h laufen lassen
- Monitoring: Intune Admin Center -> Apps -> Oracle (Bsp.) -> Device install status
- Bei >5% Fehlerrate: Rollout pausieren, Ursache klaeren

### 7.2 Production
- Erweitern der Zielgruppen nach Pilot-Success
- Company-Portal-Beschreibung + Support-Hinweise pruefen
- Known-Issues in interne Wissensbasis

### 7.3 Ongoing
- GitHub-Release-Feed abonnieren (Releases -> Watch -> Releases only) um PSADT-Updates nicht zu verschlafen
- Pruefen bei jedem neuen Paket: ist das Modul im Scaffold noch aktuell (Phase 0.1)

---

## Anhang A: Error-Referenz

### A.1 Intune-HRESULT-Mapping

Intune rechnet unbekannte positive Exit-Codes in HRESULT um: `0x80070000 + exitcode`.

| Intune zeigt | Tatsaechlicher Exit | Bedeutung |
|---|---:|---|
| `0x80070001` | 1 | **Script ist gar nicht gelaufen** (Parse-Error, Param-Binding, Top-Level-Throw) |
| `0x80070002` | 2 | FILE_NOT_FOUND, oft: Launcher findet .ps1 nicht |
| `0x8000EA61` | 60001 | PSADT Unhandled Script Error |
| `0x8000EA68` | 60008 | PSADT Init / Module-Load fehlgeschlagen |
| `0x8007064B` | 1611 | MSI Component qualifier not present |
| `0x80070642` | 1602 | User cancelled |
| `0x80070652` | 1618 | Another install in progress |
| `0x0` | 0 | Success |

### A.2 Typische Root-Causes nach Symptom

**0x80070001 + keine lokalen PSADT-Logs:**
1. Script-Encoding (Em-Dash in Double-Quote-String, UTF-8 ohne BOM) -> Parse-Error
2. Top-Level-Code ausserhalb try/catch throwt
3. Param-Block akzeptiert nicht was Launcher uebergibt
-> 3.1, 3.4, 3.6

**0x8000EA68 (60008) + PSADT-Log vorhanden, aber leer nach Init:**
1. Import-Module-Fehler (Version-Mismatch, Path kaputt)
2. Open-ADTSession wirft (Config ungueltig, Admin-Check failed)
3. Typdaten-Kollision (`System.Security.AccessControl`) - Symptom `"AuditToString" ist bereits vorhanden`. IME laeuft als SYSTEM mit Machine-Scope PSModulePath (sauber), daher selten in Intune-Deploy - eher in Interactive-Tests. Workaround: `$env:PSModulePath` um PS7-Pfade bereinigen.

**0x8000EA61 (60001) + PSADT-Log mit Stacktrace:**
1. Runtime-Fehler in Install-ADTDeployment
2. External-Command scheitert
-> Log selbst hat den Stack, direkt lesbar

**App haengt auf "Installing" in Company Portal:**
1. Script laeuft noch (Prozess-ID, Scheduled-Task-State checken)
2. Script abgestuerzt, IME-Callback nicht geschrieben
3. GRS-Cache im Weg

Aufraeum-Sequenz (Vorsicht, erst pruefen):
```powershell
Get-Process | Where-Object { $_.ProcessName -match 'Invoke-AppDeployToolkit|setup|msiexec|dbca|sqlplus' } | Select Id,ProcessName,StartTime
Get-ScheduledTask -TaskName 'PSADT_*' -ErrorAction SilentlyContinue | Select TaskName,State

# Nur wenn sicher nichts mehr laeuft:
Stop-Service IntuneManagementExtension -Force
Remove-Item 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\<UserSID>\<AppId>' -Recurse -Force -ErrorAction SilentlyContinue
Start-Service IntuneManagementExtension
```

### A.3 Log-Fundorte

| Log | Zweck |
|---|---|
| `C:\Windows\Logs\Software\<AppName>*PSAppDeployToolkit_Install.log` | PSADT-Session (nach erfolgreichem Init) |
| `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AppWorkload.log` | **Wahrheit** zu Exit-Codes + Install-Commands |
| `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` | IME-Service-State |
| `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AgentExecutor.log` | Detection-Script-Runs |
| `C:\Windows\IMECache\<AppId>_<Version>\` | Entpacktes Paket (nur waehrend Install) |
| `C:\Program Files (x86)\Microsoft Intune Management Extension\Content\Incoming\` | .intunewin-Download (vor Extract) |

AppWorkload.log-Sequenz:
- `Content cache miss for app (id = ..., name = ...)` - Download startet
- `Downloading app ... via DO, bytes N/M` - Progress
- `SetCurrentDirectory: C:\WINDOWS\IMECache\...` - Extract done
- `Calling CreateProcessAsUser: '...Invoke-AppDeployToolkit.exe...'` - Echter Start
- `lpExitCode N` - Exit-Code
- `Admin did NOT set mapping for lpExitCode: N` - Code war nicht in Return-Codes
- `EnforcementErrorCode: -<huge>` - HRESULT als signed int

---

## Anhang B: Anti-Pattern-Liste

1. **Em-Dash/Smart-Quote in Double-Quoted Strings**. `"Repair failed — DB status [$status]."` killt das ganze Script.
2. **UTF-8 ohne BOM + Sonderzeichen**. BOM schreiben oder reines ASCII.
3. **v3-Cmdlet-Namen** (siehe 3.5).
4. **Top-Level-Code ausserhalb try/catch**.
5. **Single-Check ohne Retry fuer async State** (Services nach msiexec brauchen 30-60s; Fallback-Loesch-Aktionen nicht bei erster negativer Antwort triggern).
6. **Intune Return Codes nur Default**. 60001 + 60008 als Failed eintragen.
7. **Install time reflexartig hochsetzen**. 60 min ist fast immer richtig.
8. **Denken "Laeuft lokal = laeuft in Intune"**. Acid-Test ist 6.2 + 6.3.
9. **Detection gemischt** (Custom-Script + File-Rule parallel).
10. **Extensions im Main-Script statt in `PSAppDeployToolkit.Extensions`**.
11. **-o ins -c beim IntuneWinAppUtil** - nested .intunewin.
12. **Kein Stakeholder-Intake (Phase 0.2)** - haeufigster Grund fuer "Installer macht nicht was ich will" nach 2 Wochen.

---

## Anhang C: Test-Stub-Muster

Vor Launcher-Test auf DEV-Box, wenn Install-Aktion zu gross/teuer:

```powershell
$orig = '<pfad-zur-ps1>'
$test = "$env:TEMP\test-Invoke-AppDeployToolkit.ps1"
$content = [System.IO.File]::ReadAllText($orig)
$stub = '"STUB_REACHED_INSTALL" | Out-File $env:TEMP\stub-reached.log -Encoding utf8; exit 77'
$modified = $content -replace '& "\$\(\$adtSession\.DeploymentType\)-ADTDeployment"', $stub
[System.IO.File]::WriteAllText($test, $modified, [System.Text.UTF8Encoding]::new($true))

Start-Process powershell.exe -ArgumentList `
    '-ExecutionPolicy','Bypass','-NonInteractive','-NoProfile','-NoLogo',`
    '-Command', "try { & '$test' -DeploymentType Install -DeployMode Silent } catch { throw }; exit `$Global:LASTEXITCODE" `
    -Wait -NoNewWindow
Get-Content "$env:TEMP\stub-reached.log" -ErrorAction SilentlyContinue
```

- Exit 77 + Stub-Log = Init + Session-Open OK, Bug sitzt in Install-ADTDeployment
- Exit 1 = Parse/Encoding-Bug, siehe 3.1
- Exit 60008 = Import-Module / Open-ADTSession Bug, siehe A.2

---

## Anhang D: Ressourcen

### Offizielles PSADT
- Hauptseite + Docs: https://psappdeploytoolkit.com/docs
- Latest Release: https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/releases/latest
- Release Notes: https://psappdeploytoolkit.com/docs/getting-started/release-notes
- Download: https://psappdeploytoolkit.com/docs/getting-started/download
- Creating a New Deployment: https://psappdeploytoolkit.com/docs/getting-started/creating-a-new-deployment
- Reference (alle Cmdlets): https://psappdeploytoolkit.com/docs/reference
- New-ADTTemplate: https://psappdeploytoolkit.com/docs/reference/functions/New-ADTTemplate
- Exit Codes: https://psappdeploytoolkit.com/docs/reference/exit-codes
- Migration v3 -> v4: https://psappdeploytoolkit.com/docs/migration/migrate-from-v3
- Blog: https://psappdeploytoolkit.com/blog
- Community Forum: https://discourse.psappdeploytoolkit.com
- GitHub: https://github.com/PSAppDeployToolkit/PSAppDeployToolkit
- Launcher-Source: https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/tree/main/src/PSADT.Invoke

### Microsoft
- Intune Win32 App Docs: https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management
- IntuneWinAppUtil: https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool
- IntuneWinAppUtil Releases: https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/releases/latest
- Intune Troubleshooting: https://learn.microsoft.com/en-us/mem/intune/apps/troubleshoot-app-install
- Company Portal Docs: https://learn.microsoft.com/en-us/mem/intune/apps/company-portal-app
- PowerShell 5.1 UTF-8-No-BOM-Bug: https://learn.microsoft.com/en-us/answers/questions/3850223/powershell-5-1-parser-bug-failure-to-parse-utf-8
- PowerShell File Encoding: https://learn.microsoft.com/en-us/powershell/scripting/dev-cross-plat/vscode/understanding-file-encoding
- about_Character_Encoding: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_character_encoding
- PsExec (SysInternals): https://learn.microsoft.com/en-us/sysinternals/downloads/psexec

### Silent-Install-Recherche
- silentinstallhq.com - Switch-Sammlung
- deploymentresearch.com - Tim Mangan Archiv
- PSADT Discourse Search: https://discourse.psappdeploytoolkit.com/search
- Reddit r/Intune: https://www.reddit.com/r/Intune/
- Reddit r/SCCM: https://www.reddit.com/r/SCCM/

### Drittdocs Error-Codes
- Scappman Error Reference: https://support.scappman.com/support/error-code-reference
- xoap PSADT Exit Codes: https://docs.xoap.io/application-management/psadt/exit-codes
- netECM PSADT Exit Codes: https://docs.netecm.ch/launcher/troubleshooting/ps-app-deploy-toolkit-setup-exit-codes.html
- Anoop C Nair Intune Troubleshooting: https://www.anoopcnair.com/intune-management-extension-deep-dive-level-300/
- getpackit PSADT + Intune Issues: https://www.getpackit.com/blog/psadt-intune-apps-deployment-issues/

---

## Anhang E: Finale Deploy-Checkliste

```
Phase 0 - Recherche + Intake
[ ] 0.1  PSADT-Version lokal == Latest (oder Update)
[ ] 0.2  Intake-Formular komplett (App, Installer, Environment, Sec)
[ ] 0.3  Silent-Install-Switches + Uninstall-Switches dokumentiert

Phase 1 - Scaffold
[ ] 1.1  New-ADTTemplate -Destination ... -Name ... ausgefuehrt
[ ] 1.2  Folder-Layout komplett
[ ] 1.3  Modul-Version im Scaffold gepinnt

Phase 2 - Script-Customizing
[ ] 2.1  Installer in Files\
[ ] 2.2  $adtSession mit allen Metadaten
[ ] 2.3  Install/Uninstall/Repair-Hooks gefuellt
[ ] 2.4  Custom-Helpers in PSAppDeployToolkit.Extensions, nicht im Main

Phase 3 - Pre-Flight
[ ] 3.1  Encoding: HasBOM=True ODER NonAscii=0
[ ] 3.2  ParseFile PARSE_OK
[ ] 3.3  Launcher-Simulation gruen
[ ] 3.4  Param-Block zu v4-Template synchron
[ ] 3.5  Keine v3-Cmdlet-Reste
[ ] 3.6  Keine Top-Level-Statements die werfen koennen

Phase 4 - Bauen
[ ] 4.1  IntuneWinAppUtil latest
[ ] 4.2  -c / -s / -o korrekt, -o NICHT im -c
[ ] 4.3  Inspektion: Detection.xml hat SetupFile=Invoke-AppDeployToolkit.exe

Phase 5 - Intune-Config
[ ] 5.1  App Info + Logo
[ ] 5.2  Install/Uninstall-Command + Install Behavior=System
[ ] 5.3  Return Codes komplett (inkl. 60001+60008=Failed)
[ ] 5.4  Requirements (OS, Arch, Disk, Memory)
[ ] 5.5  Detection-Methode EINDEUTIG
[ ] 5.6  Install time realitaetsnah
[ ] 5.7  Assignments + Filter + Delivery-Opt

Phase 6 - Test
[ ] 6.1  Direct-Invoke auf DEV
[ ] 6.2  Launcher-Invoke auf DEV
[ ] 6.3  Psexec -s auf DEV
[ ] 6.4  Testgruppen-Deploy -> PSADT-Log + Close-ADTSession Exit 0

Phase 7 - Rollout
[ ] 7.1  Pilot (24-48h)
[ ] 7.2  Production staged
[ ] 7.3  GitHub-Release-Watch abonniert
```

Erst wenn ALLE Zeilen gruen: Production-Rollout.

---

## Anhang F: Intune-Deployment-Dossier (Upload-Template, pro App auszufuellen)

Dieses Template als Markdown-Datei pro App neben das `.intunewin` legen (z.B. `<AppName>-IntuneDossier.md`). Ohne ausgefuelltes Dossier: **kein Upload**. Werte kommen aus Phase 0.2/0.3.

### F.1 App information

| Intune-Feld | Wert | Hinweise |
|---|---|---|
| **Name** | `<AppName> <Version>` | exakt wie im Company Portal sichtbar; Version inkl. Build falls Updates |
| **Description** | siehe F.2 (Markdown-Block) | erste ~200 Zeichen sind Kurzvorschau im CP |
| **Publisher** | `<Hersteller>` | aus Phase 0.2 (Adobe Inc., Oracle Corporation, ...) |
| **App version** | `<Major.Minor.Build.Rev>` | exakt Dateiversion |
| **Category** | z.B. Business, Development, Productivity, Communication | fuer CP-Navigation |
| **Show this as a featured app in the Company Portal** | Yes/No | Yes nur fuer empfohlene Self-Service-Apps |
| **Information URL** | `<hersteller-produktseite>` | offizielle Produkt-Homepage |
| **Privacy URL** | `<hersteller-privacy-url>` | oft `/legal/privacy/` des Herstellers |
| **Developer** | `<Hersteller-Kurzname>` | meist == Publisher |
| **Owner** | `<internes-Team>` | interner Service-Owner (z.B. "Workplace-Services") |
| **Notes** | `PSADT 4.1.8 v<N> - pkg rev <NN> - YYYY-MM-DD` | Paket-Metadaten fuer spaetere Troubleshootings |
| **Logo** | `<pkg>\Assets\AppIcon.png` | 256x256 PNG transparent |
| **Role scope tags** | `<Default>` oder custom | nur bei delegierter Admin-Rollenstruktur |

### F.2 Description-Markdown-Template (Company Portal)

Intune rendert Markdown im Company Portal. Block 1:1 kopieren, `<...>` ersetzen.

```markdown
**<AppName>** ist <Ein-Satz-Zweck>.

<Zwei-bis-drei-Saetze-Nutzenbeschreibung fuer Endbenutzer. Was bekommen sie, wofuer brauchen sie das.>

### Was du bekommst

- <Feature 1>
- <Feature 2>
- <Feature 3>
- <ggf. Config / Branding>

### Was du brauchst

- Windows 11 (oder Windows 10 22H2+)
- ~<X> GB freier Speicherplatz auf `C:`
- Ca. **<N>-<M> Minuten** Installationsdauer
- *<ggf. Kein Neustart erforderlich / Neustart empfohlen>*

### Nach der Installation

<Was findet der User vor? Startmenu-Eintrag, Desktop-Shortcut, Config-Datei, Zugangsdaten?>

### Deinstallation

<Was passiert bei Deinstall? Bleiben User-Daten, werden sie entfernt, was soll der User vorher sichern?>

### Support

Bei Problemen bitte ein Ticket beim **IT-Service-Desk** eroeffnen und - wenn moeglich - die Logdateien unter `C:\Windows\Logs\Software\` anhaengen.
```

Pruefen: erster Absatz muss auch allein lesbar sein (200-Zeichen-Kurzvorschau).

### F.3 Program

| Intune-Feld | Wert |
|---|---|
| **Install command** | `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent` |
| **Install script** | - (nicht verwenden, Command reicht) |
| **Uninstall command** | `Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent` |
| **Uninstall script** | - |
| **Installation time required (mins)** | Default 60; nur wenn >45 min dokumentiert hochziehen |
| **Allow available uninstall** | Yes (User darf via CP deinstallieren) |
| **Install behavior** | **System** |
| **Device restart behavior** | `Determine behavior based on return codes` (Default) ODER `App install may force a device restart` wenn Installer 1641 liefern kann |

### F.4 Return codes (Pflicht-Tabelle, exakt uebernehmen)

| Code | Type |
|---:|---|
| 0 | Success |
| 1707 | Success |
| 3010 | Soft reboot |
| 1641 | Hard reboot |
| 1618 | Retry |
| 60001 | **Failed** |
| 60008 | **Failed** |
| `<installer-success-nicht-0>` | Success |
| `<installer-known-error>` | Failed |

Installer-spezifische Codes aus Phase 0.3 ergaenzen. Jeder unbekannte Exit-Code erzeugt `0x80070000+code` in der Fehleranzeige.

### F.5 Requirements

| Intune-Feld | Wert | Hinweise |
|---|---|---|
| **Operating system architecture** | x64 / x86 / Both | matched zu `$adtSession.AppArch` |
| **Minimum operating system** | Win11 22H2 / Win10 22H2 | realitaetsnah, nicht "Win10 1607" |
| **Disk space required (MB)** | `<MB>` | aus Installer-Anforderung, Netto + 20% Reserve |
| **Physical memory required (MB)** | `<MB>` oder leer | nur bei RAM-hungrigen Installern |
| **Minimum number of logical processors required** | 1 / 2 / 4 | selten relevant |
| **Minimum CPU speed required (MHz)** | leer | selten relevant |
| **Additional requirement rules** | optional | Registry/File/Script - z.B. "Domain-Joined", "hat Edge-WebView2 installiert" |

### F.6 Detection rules

**Rules format:** einen Weg waehlen, NICHT mischen:

**Option A - Custom script (bevorzugt fuer komplexe Installs):**
| Feld | Wert |
|---|---|
| **Rules format** | Use a custom detection script |
| **Script file** | `Detect-<AppName>.ps1` (mit Paket ausgeliefert) |
| **Run script as 32-bit process on 64-bit clients** | No (ausser das Script liest bewusst Wow6432Node) |
| **Enforce script signature check** | No (es sei denn in streng signierter Umgebung) |

Detection-Script-Contract:
- `exit 0 + stdout non-empty` -> INSTALLED
- `exit 0 + stdout empty` -> NOT INSTALLED
- `exit != 0` -> Detection-Error (Intune retriet)

**Option B - Manuell, MSI Product Code:**
| Feld | Wert |
|---|---|
| **Rule type** | MSI |
| **MSI product code** | `{GUID}` |
| **MSI product version check** | No ODER operator + version |

**Option C - Manuell, File/Registry:**
EINE Regel reicht wenn eindeutig. Mehrere Regeln mischen: mit Bedacht, alle muessen matchen.

| Feld | Wert |
|---|---|
| **Rule type** | File / Registry / App version |
| **Path / Key** | `<konkret>` |
| **File/value** | `<konkret>` |
| **Detection method** | exists / string / version / size / date modified |
| **Associated with a 32-bit app on 64-bit clients** | No (fast immer) |

### F.7 Dependencies

Andere Win32-Apps die ZUERST installiert sein muessen.

| Feld | Wert |
|---|---|
| **Dependency app** | z.B. "VC++ 2015-2022 x64" |
| **Automatically install** | Yes (Intune installiert automatisch nach) |

Zirkulaere Abhaengigkeiten und >3 Ebenen vermeiden.

### F.8 Supersedence

Ersetzt diese App eine Vorversion oder ein anderes Produkt?

| Feld | Wert |
|---|---|
| **Superseded app** | vorherige Version (separater Intune-Eintrag) |
| **Uninstall previous version** | Yes/No (Yes wenn echter Replace, No wenn parallel moeglich) |

Maximal **10 Apps** als superseded; **maximal 2 Ebenen** tief (Intune-Limit).

### F.9 Assignments

Pro Zielgruppe eine Zeile. Mindestens eine Required- ODER Available-Assignment, sonst nie installiert.

| Group (AzureAD / Entra) | Assignment type | Filter (include/exclude) | Install-Availability | Deadline | Restart grace period | Delivery Optimization |
|---|---|---|---|---|---|---|
| `<Grp-Devices-Required>` | Required | optional Filter | As soon as possible / Datum | optional Datum | 1440 min + 15 min vor Reboot | Foreground / Background |
| `<Grp-Users-OptIn>` | Available | optional Filter | - | - | - | Background |
| `<Grp-Cleanup>` | Uninstall | - | - | - | - | - |

**Hints:**
- Required fuer Pflicht-Rollouts (Security, Compliance, Standard-Tools)
- Available fuer Self-Service
- Uninstall fuer gezieltes Entfernen aus Gruppe
- Filter: Plattform/Version/DeviceName-Regex; bei Edge-Cases prueft IME sauber ob Filter-Property existiert
- Delivery Optimization Foreground bei Pakete die sofort kommen muessen; Background schont Netz bei grossen Paketen

**End user notifications** (pro Assignment):
- `Show all toast notifications` - Default, User sieht Download/Install/Reboot
- `Show toast notifications for computer restarts` - nur Reboot-Prompt
- `Hide all toast notifications` - nur fuer silent-only-Apps

### F.10 Review + Create

Vor dem `Create` alle Tabs durchgehen. Nach `Create`: Intune synct nicht sofort — 30-60 min Wartezeit bis Client das Paket sieht. Manuell triggern via Company Portal -> Einstellungen -> Sync.

### F.11 Beispielhafte Ausfuellung (Oracle Database 21c XE aus diesem Projekt)

| Feld | Wert |
|---|---|
| Name | Oracle Database 21c Express Edition |
| Publisher | Oracle Corporation |
| App version | 21.0.0.0 |
| Category | Development, Database |
| Featured | Yes (fuer Developer-Zielgruppe) |
| Information URL | https://docs.oracle.com/en/database/oracle/oracle-database/21/xeinw/ |
| Privacy URL | https://www.oracle.com/legal/privacy/ |
| Developer | Oracle |
| Owner | Workplace-Services |
| Notes | PSADT v4.1.8 Wrapper v2 - Paketversion 02 - 2026-04-22 |
| Logo | `Assets/AppIcon.png` |
| Install command | `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent` |
| Uninstall command | `Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent` |
| Install behavior | System |
| Device restart | App install may force a device restart |
| Installation time | 60 min |
| Return codes | 0/1707 Success; 3010/1641 reboot; 1618 retry; 60001/60008 Failed |
| OS architecture | x64 |
| Minimum OS | Windows 10 22H2 |
| Disk space required | 12288 MB |
| Physical memory | 4096 MB |
| Detection | Custom script `Detect-OracleXE.ps1`, Run as 32-bit=No, Signature=No |
| Dependencies | - (VCRedist ist im PSADT-Pre-Install-Hook integriert) |
| Supersedence | - (erste Version) |
| Required group | Devices-OracleXE-Dev |
| Available group | Users-OracleXE-OptIn |
| Install availability | As soon as possible |
| Restart grace period | 1440 min (24h), 15 min countdown, snooze 240 min |

Das ist ein vollstaendiges Dossier. Jede neue App genauso durchgehen.

---

## Anhang G: Lessons Learned (aus Praxis-Vorfaellen)

Diese Lessons stammen aus konkreten Paketierungs-Projekten und gelten fuer PSADT-v4-Intune-Deployments allgemein - nicht app-spezifisch. Jeder neue Vorfall wird hier als neuer Eintrag ergaenzt (Format: Datum, Symptom, Ursache, Fix, allgemeine Lehre).

### 2026-04-21/22 - Datenbank-Paket (grosser Installer, ~2 GB, mit Post-Install-DB-Verify)

1. **Em-Dash-Encoding-Bug**: Script hatte 74 Em-Dashes (`—`) als UTF-8 ohne BOM. In Double-Quoted Strings brach PowerShell 5.1 beim Parsen. Exit 1, Intune zeigte `0x80070001`, keine lokalen Logs. Fix: alle Em-Dashes zu `-`, Pfeile `→` zu `->`, UTF-8 BOM gesetzt.

2. **Transiente Post-Install-Check-False-Positive**: Funktionaler Check direkt nach `msiexec`-Ende lief ins Leere - die durch den Installer registrierten Services waren noch in `Starting`, Listener/API noch nicht erreichbar. Der Single-Check gab `NO_OUTPUT` / leeres Resultat zurueck, das als "nicht installiert" interpretierte Script triggerte eine 30-minuetige Drop+Recreate-Fallback-Aktion - obwohl die Installation eigentlich erfolgreich war. Fix: erst auf Service=Running warten (max 3 min), dann Check-Funktion mit Retry-Loop (6x, 30s Abstand), erst danach Fallback. **Generelle Lesson**: fuer jeden Post-Install-Check der auf asynchron gestarteten State angewiesen ist (Services, Listener, Registry-Keys die ein Dienst schreibt) IMMER Retry-Loop + Service-Ready-Wait, nie Single-Shot. Gilt fuer alle Installer mit Dienst-Registrierung (DBs, Message-Queues, Search-Indexer, Lizenz-Daemons, ...).

3. **IME-HRESULT-Mapping-Falle**: `0x80070001` sieht aus wie "ERROR_INVALID_FUNCTION" (Win32-API), ist aber `0x80070000 + 1`, also Exit 1 aus dem Script. Immer gegenrechnen.

4. **IntuneManagementExtension.log vs AppWorkload.log**: IntuneManagementExtension.log zeigt Service-State und State-Machine-Definitionen ("Adding new state transition..." sind nur Tabelleneintraege, KEINE echten Transitions). Fuer Install-Diagnose ist **AppWorkload.log** der Treffer.

5. **Acid-Test ist `Invoke-AppDeployToolkit.exe`, nicht `.ps1` direkt**. Die Launcher-Exe nutzt `powershell.exe -Command "try { & 'script.ps1' ... } catch { throw }; exit $Global:LASTEXITCODE"` - ein anderer Encoding-Pfad als `.\script.ps1`. Encoding-Bugs fallen nur hier auf.

6. **Falsche Param-Block-Diagnose vermeiden**: Ich habe zwischenzeitlich `$SuppressRebootPassThru` zu `$AllowRebootPassThru` geaendert - v3-Denken angewandt auf ein v4-Script. Der Launcher uebergibt NICHT automatisch Reboot-Switches; der Parametername ist in v4.x `$SuppressRebootPassThru`. Referenz ist IMMER das Template unter `<pkg>\PSAppDeployToolkit\Frontend\v4\Invoke-AppDeployToolkit.ps1`.
