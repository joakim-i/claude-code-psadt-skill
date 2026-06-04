---
name: psadt-deploy
description: Use this skill when the user wants to build, package, test, troubleshoot, or deploy a PowerShell App Deployment Toolkit (PSADT) v4.x Intune Win32 app package. Triggers include "PSADT paket bauen", "intune paket fuer <app>", "<app> via intune paketieren", "PSADT v4 deploy", "PSADT troubleshooting", "Invoke-AppDeployToolkit.ps1 debug", "IntuneWinAppUtil", or when working inside a folder that contains Invoke-AppDeployToolkit.ps1 / .exe or a PSAppDeployToolkit module.
---

# PSADT v4.x Deployment Skill

## Kurzbeschreibung

Diese Skill begleitet den kompletten Lebenszyklus eines **PSADT-v4.x-Intune-Win32-Pakets** - vom ersten Gespraech bis zum getesteten, hochladefertigen `.intunewin`. Sie ist fuer **Build, Packaging, Test, Troubleshooting und Deployment** gedacht (Trigger u.a. "PSADT Paket bauen", "Intune Paket fuer <App>", "PSADT v4 deploy", oder Arbeit in einem Ordner mit `Invoke-AppDeployToolkit.ps1`).

**Ablauf (9 Phasen):** 1) Intake (8 Kill-Fragen, IMMER per Klick-Optionen) - 2) Web-Recherche (PSADT-Version + Command-Aenderungen, Silent/Uninstall/Repair der App, Intune-Stolpersteine) - 3) Scaffold (`New-ADTTemplate`) - 4) Customizing aller drei Deployment-Types (Install/Uninstall/Repair) - 5) Pre-Flight (Encoding/Parse/Acid-Test) - 6) Packen (IntuneWinAppUtil) - 7) Dossier + Logo - 8) Test - 9) Rollout.

**Verbindliche Konventionen (Details im Block unten):**
- Fragen an den User IMMER per `AskUserQuestion` (Klick-Optionen), nie als Fliesstext
- Output-`.intunewin` IMMER zentral nach `c:\Temp\PSADTv4\Output\<App>\`
- Intune-Dossier IMMER `Intune-Dossier.md`, **Deutsch mit echten Umlauten**; Scripts dagegen **Englisch/ASCII**
- Author IMMER `Patrick Taubert, PHAT Consulting GmbH`; erste Script-Version `0.1`; Changelog im `.NOTES`-Header Pflicht
- App-Logo (PNG, transparent, hochaufloesend) besorgen -> `Assets\` + `Output\<App>\`
- Nur Startmenue-Eintraege, KEINE Desktop-Icons
- Alle drei Deployment-Types (Install/Uninstall/Repair) von Anfang an mitbauen und per Acid-Test pruefen

Tiefe pro Thema im Referenz-Guide `c:\Temp\PSADTv4\OracleDB\PSADTv4-Deployment-Guide.md` (Anhaenge A-G).

---

Du fuehrst den User durch den kompletten Lifecycle eines PSADT-v4.x-Intune-Pakets: Intake, Recherche, Scaffold, Customizing, Pre-Flight, Packen, Intune-Upload, Test, Rollout. Verhaltensregeln:

- **Fahre die Konversation aktiv** - dump keine Frageliste sondern stell gezielt Blocker-Fragen, recherchiere was recherchierbar ist, zeig dem User Zwischenergebnisse
- **Fragen IMMER per `AskUserQuestion` (Klick-Optionen) stellen, nie als reinen Fliesstext** - jede Entscheidungsfrage an den User laeuft ueber das `AskUserQuestion`-Tool mit vorausgefuellten, anklickbaren Optionen. Empfohlene Option immer zuerst und mit Suffix "(empfohlen)". Recherchierte Defaults als Optionen anbieten. Das Tool ergaenzt automatisch eine "Other"-Freitext-Option - es muss also keine manuelle Freitext-Alternative gebaut werden. Reiner Text ist nur fuer Zwischenergebnisse/Statusmeldungen erlaubt, nicht fuer Fragen.
- **Nicht Adobe/Oracle als Default annehmen** - die zu paketierende App kommt immer vom User, Beispiele aus dem Guide sind Illustration
- **Nachschlag**: Vollstaendiger Referenz-Guide liegt unter `c:\Temp\PSADTv4\OracleDB\PSADTv4-Deployment-Guide.md` - dort auf konkrete Anhaenge (A-G) verweisen wenn Tiefe noetig, NICHT den ganzen Guide in die Konversation kippen

## Konventionen (VERBINDLICH)

- **Sprache - getrennt nach Ziel:**
  - **Intune-Beschreibung / Dossier (`Intune-Dossier.md`): DEUTSCH mit echten Umlauten** (ä, ö, ü, ß) - das ist Fliesstext fuer Endnutzer im Company Portal, dort sind Umlaute korrekt und erwuenscht (KEIN ae/oe/ue ausschreiben).
  - **In den Scripts selbst (Invoke-AppDeployToolkit.ps1, Extensions, Detection): ALLES auf ENGLISCH** - insb. alle Kommentare. Script-Strings ebenfalls Englisch halten, damit keine Umlaute/Non-ASCII ins PS1 geraten (Encoding-Sauberkeit, siehe Pre-Flight). Umlaute gehoeren NUR in die Dossier-Markdown, nie ins Script.
- **Author IMMER:** `Patrick Taubert, PHAT Consulting GmbH` (Feld `AppScriptAuthor` im `$adtSession`).
- **Versionierung des Scripts (`AppScriptVersion` im `$adtSession`):**
  - Erste Version eines Scripts ist IMMER **`0.1`** (nicht 1.0.0).
  - Jede inhaltlich gerechtfertigte Aenderung erhoeht die Versionsnummer (kleine Fixes/Klarstellungen -> Patch/Minor, groessere funktionale Aenderungen -> groesserer Sprung). Rein kosmetische Edits ohne Funktionsbezug muessen nicht zwingend hochzaehlen.
- **Changelog ist Pflicht:** Jede Aenderung an einem Script wird in einem **Changelog im Script-Header (`.NOTES`-Block)** dokumentiert - eine Zeile pro Version: `Version (Datum, Author): Was geaendert wurde`. Bei jeder Aenderung den Changelog-Eintrag UND `AppScriptVersion` zusammen aktualisieren. Format:
  ```
  Changelog:
  - 0.1 (YYYY-MM-DD, Patrick Taubert): Initial version.
  - 0.2 (YYYY-MM-DD, Patrick Taubert): <was geaendert wurde>.
  ```

## Ablauf (fuehre in dieser Reihenfolge durch)

### 1. Intake (sofort am Anfang, bevor irgendwas anderes)

Kritisch: Ein PSADT-v4-Paket bedient IMMER drei Deployment-Types — **Install, Uninstall, Repair**. Alle drei muessen von Anfang an mitgeplant werden, nicht erst am Ende.

Stelle die **8 Kill-Fragen ausschliesslich per `AskUserQuestion`-Tool** (anklickbare Optionen), NICHT als Fliesstext-Liste. Da das Tool max. 4 Fragen pro Aufruf erlaubt, in **zwei `AskUserQuestion`-Aufrufen** buendeln (4 + 4). Wo immer moeglich, vorher das Recherchierbare (App, neueste Version, Installer-Typ) leicht antesten und die Befunde als vorausgewaehlte Optionen anbieten - der User klickt dann nur noch bestaetigen oder korrigieren. Jede Frage bekommt sinnvolle Default-Optionen; die empfohlene zuerst mit Suffix "(empfohlen)". Das Tool haengt automatisch eine "Other"-Freitext-Option an.

Die 8 inhaltlichen Fragen, die abgedeckt sein muessen (auf die zwei Aufrufe verteilen):
1. **App + exakte Version** - Optionen: erkannte/neueste Version (empfohlen), bekannte Vorversion(en), aus Kontext.
2. **Installer-Typ** - Optionen: MSI, EXE-Wrapper, MSIX, InstallShield, Squirrel/ZIP/portable, anderes.
3. **Installer-Quelle** - Optionen: lokal vorhanden (Pfad folgt), runterladen + ins Paket buendeln (empfohlen), zur Laufzeit runterladen.
4. **Zielgruppe** - Optionen: Required auf Devices, Available im Company Portal, beides; AAD-Gruppen ggf. als Freitext nachziehen.
5. **Spezielle Config** - Optionen: keine (empfohlen-Default falls nichts bekannt), Registry-Keys, XML/JSON/settings-Datei, Lizenzkey, Service-Account, Branding (multiSelect: true sinnvoll).
6. **Reboot-Verhalten** - Optionen: nie (empfohlen), empfohlen (3010), erzwungen (1641).
7. **Uninstall-Semantik** - Optionen fuer "was muss weg": nur App-Dateien, + Registry-Reste, + Scheduled Tasks/Services/Firewall, + User-Daten (multiSelect). Plus separate Frage/Option, was definitiv ERHALTEN bleiben muss (User-Daten, Shared-Komponenten, Nachbar-Produkte gleicher Hersteller). Uninstall-Method (MSI-ProductCode / Registry-UninstallString / eigener Uninstaller) als eigene Frage falls unklar.
8. **Repair-Semantik** - Optionen: kein Repair noetig, MSI /fa, Config zurueck auf Default, kompletter Reinstall (empfohlen bei ZIP/EXE), Service-Restart.

Optional je nach Kontext per weiteren `AskUserQuestion`-Aufruf nachziehen: Co-Existenz mit Vorversionen, Prozesse-schliessen-Liste, Sprache (EN/DE/Multi), Architektur (x64/x86/ARM64). Nicht alle 30 Fragen aus Guide Phase 0.2 auf einmal - Rest kommt situativ, ebenfalls per Klick-Optionen.

### 2. Web-Recherche (parallel, autonom)

Nach Intake ohne Rueckfrage sofort **drei parallele Recherchen**:

**a) PSADT-Version sync UND Command-Aenderungen pruefen:**
```powershell
$local = (Get-Module -ListAvailable -Name PSAppDeployToolkit | Sort-Object Version -Descending | Select-Object -First 1).Version
$rel = Invoke-RestMethod 'https://api.github.com/repos/PSAppDeployToolkit/PSAppDeployToolkit/releases/latest'
"local=$local latest=$($rel.tag_name)"
```
Wenn divergent: User informieren + `Update-Module PSAppDeployToolkit -Force` empfehlen BEVOR Scaffold.

**Pflicht, NICHT nur die Versionsnummer vergleichen:** Bei abweichender (neuerer) Version IMMER pruefen, ob sich
**Commands geaendert haben** - neue, umbenannte, deprecated oder mit geaenderten Parametern. Sonst baut man ein
Paket mit veralteter Syntax, das beim Launcher-Acid-Test oder erst in Intune bricht. Quellen in dieser Reihenfolge:
- Release Notes des neuesten Releases: `$rel.body` (oben schon geladen) auf "Breaking", "renamed", "deprecated", "removed", "new function" scannen
- Changelog/Migration-Doku: https://psappdeploytoolkit.com/docs (v3->v4 Function-Mapping und Versions-Changelogs)
- GitHub Releases-Uebersicht: https://github.com/PSAppDeployToolkit/PSAppDeployToolkit/releases
- Im Zweifel die konkret genutzten Cmdlets gegen das installierte Modul verifizieren:
  `Get-Command -Module PSAppDeployToolkit -Name Start-ADTProcess,Start-ADTMsiProcess,Show-ADTInstallationWelcome,New-ADTShortcut,Remove-ADTFolder | Select Name,Version`
  und bei Bedarf `Get-Help <Cmdlet> -Parameter *` fuer geaenderte Parameter.
Befund dem User zeigen (welche Commands neu/geaendert/deprecated sind und was das fuers Paket bedeutet) BEVOR gebaut wird.

**b) Silent-Install / Uninstall / Repair-Recherche zur App** via WebSearch — ALLE DREI, nicht nur Install:
- Query 1: `"<AppName>" "<Version>" silent install command line`
- Query 2: `"<AppName>" msi transform enterprise deployment`
- Query 3: `"<AppName>" uninstall silent /quiet /qn msiexec`
- Query 4: `"<AppName>" repair reinstall command line` (oft `msiexec /fa <ProductCode>` bei MSIs; bei EXE-Wrappers: reinstall ueber den gleichen Installer)
- Query 5: `"<AppName>" "uninstall" "registry" "leftover"` — dokumentierte Leichen aus der Community
- Offizielle Hersteller-Docs zuerst, dann silentinstallhq.com, dann Community (Reddit r/Intune, PSADT Discourse)

Ergebnis pro Deployment-Type festhalten: Switch, erwartete Exit-Codes, Log-Pfad, bekannte Leichen.

**c) Bekannte Intune-Stolpersteine:**
- Query: `"<AppName>" intune win32 known issues`
- Query: `"<AppName>" PSADT package github` (falls jemand schon ein Paket gebaut hat)

Ergebnis in die Phase-0.3-Tabelle aus dem Guide packen und dem User zeigen BEVOR das Scaffold gebaut wird.

### 3. Scaffold (`New-ADTTemplate`)

Werte aus Intake + Recherche einsetzen. **NICHT hardcoden**, **nicht Adobe/Oracle nehmen**.

```powershell
Import-Module PSAppDeployToolkit
# WICHTIG: New-ADTTemplate akzeptiert in 4.1.x NUR -Destination/-Name/-Version (Modulversion)/-Force/-Show/-PassThru.
# Es nimmt KEINE App-Metadaten (-AppVendor/-AppName/-AppVersion/-AppScriptAuthor ...). Die kommen NACH dem Scaffold
# ins $adtSession-Hashtable im Invoke-AppDeployToolkit.ps1.
New-ADTTemplate -Destination '<Root-aus-User-Angabe>' -Name '<AppName aus Intake>'
```

Danach im erzeugten `Invoke-AppDeployToolkit.ps1` das `$adtSession`-Hashtable fuellen - inkl. der verbindlichen Konventionen:
```powershell
AppVendor = '<Hersteller>'
AppName = '<Produkt-Kurzname>'
AppVersion = '<Version>'
AppArch = '<x64|x86|ARM64>'
AppLang = 'EN'
AppRevision = '01'
AppSuccessExitCodes = @(0, 1707)
AppRebootExitCodes = @(1641, 3010)
AppScriptVersion = '0.1'                              # erste Version IMMER 0.1, siehe Konventionen
AppScriptAuthor = 'Patrick Taubert, PHAT Consulting GmbH'   # IMMER dieser Author
```
Und im Header-Kommentar (`.NOTES`) den Changelog anlegen: `- 0.1 (YYYY-MM-DD, Patrick Taubert): Initial version.`

Verify direkt nach Scaffold:
```powershell
$pkg = '<Scaffold-Pfad>'
(Import-PowerShellDataFile "$pkg\PSAppDeployToolkit\PSAppDeployToolkit.psd1").ModuleVersion
Select-String "$pkg\Invoke-AppDeployToolkit.ps1" -Pattern 'DeployAppScriptVersion' -List | Select-Object Line
```
Beides muss matchen.

### 4. Script-Customizing — alle drei Deployment-Types

Der User legt Installer in `<pkg>\Files\`. Dann in `Invoke-AppDeployToolkit.ps1` **alle drei Hooks** fuellen: `Install-ADTDeployment`, `Uninstall-ADTDeployment`, `Repair-ADTDeployment`. Auch wenn heute nur Install gebraucht ist: spaetere User-Uninstalls via Company Portal funktionieren nur mit gefuelltem Uninstall-Block.

**4a. `Install-ADTDeployment`** — Pattern je nach Installer-Typ aus der Recherche:

- MSI: `Start-ADTMsiProcess -FilePath "$($adtSession.DirFiles)\<installer>.msi" -Transforms "$($adtSession.DirSupportFiles)\<transform>.mst" -ArgumentList '/qn REBOOT=ReallySuppress'`
- EXE-Wrapper: `Start-ADTProcess -FilePath "$($adtSession.DirFiles)\<setup>.exe" -ArgumentList '<recherchierte-silent-switches>' -SuccessExitCodes @(0, 3010, 1641)`
- InstallShield mit `setup.exe /s /f1"<response>.iss"`: Response-File in `SupportFiles\`
- Squirrel (`<app>-<ver>-full.nupkg`-based .exe): oft `/silent /quiet`

Pflicht vor Install: `Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -CheckDiskSpace -RequiredDiskSpace <MB>` (no-op in Silent, aktiv in Interactive). Dann `Show-ADTInstallationProgress` fuer die Welcome-Ersatz-Anzeige.

**Verknuepfungen - NUR Startmenue, NIE Desktop:** Wenn die App eine Verknuepfung braucht, ausschliesslich einen
Startmenue-Eintrag fuer alle User anlegen (`$envCommonStartMenuPrograms`, z.B.
`New-ADTShortcut -Path "$envCommonStartMenuPrograms\<App>\<App>.lnk" -TargetPath ...`). **Keine Desktop-Icons**
(`$envCommonDesktop` / `$envUserDesktop`) erstellen - das verschmutzt den Desktop und ist im Enterprise unerwuenscht.
Falls der Installer von sich aus ein Desktop-Icon anlegt: im Post-Install gezielt wieder entfernen
(`Remove-Item "$envCommonDesktop\<App>.lnk"`). Im Uninstall den Startmenue-Eintrag wieder mit abraeumen.

**4b. `Uninstall-ADTDeployment`** — Werte aus Intake-Frage 7 (was weg, was bleibt):

- MSI bekannter ProductCode: `Start-ADTMsiProcess -Action Uninstall -FilePath '{<ProductCode>}' -ArgumentList '/qn'`
- MSI per DisplayName-Match (wenn ProductCode variiert): `Remove-ADTApplication -Name '<AppName>' -NameMatch Exact` (nicht `Contains` - das loescht versehentlich Nachbar-Produkte mit Namens-Prefix)
- EXE mit eigenem Uninstaller: `Start-ADTProcess -FilePath '<uninstallstring-aus-registry>' -ArgumentList '<silent-uninstall-switches>'`
- Squirrel: `Start-ADTProcess -FilePath "$env:LocalAppData\<app>\update.exe" -ArgumentList '--uninstall -s'`

Post-Uninstall-Cleanup (anhand Intake-Frage 7):
- `Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -CloseProcessesCountdown 60` (nicht `-Silent` - Uninstalls sollten Prozesse killen durfen)
- Scheduled Tasks: `Get-ScheduledTask -TaskName '<Prefix>_*' | Unregister-ScheduledTask -Confirm:$false`
- Services: `Stop-Service <Name>` + `sc.exe delete <Name>` fuer Services die der Installer nicht selbst wegraeumt
- Firewall-Rules: `Get-NetFirewallRule -DisplayName '<App>*' | Remove-NetFirewallRule`
- Registry-Leichen: gezielt nur unter dem APP-spezifischen Key loeschen, NIE unter `HKLM\SOFTWARE\<Hersteller>\` pauschal (andere Produkte gleicher Firma leiden)
- Install-Directory `Remove-Item -Recurse` wenn Installer nicht von selbst aufraeumt
- User-Daten (AppData, Dokumente, Templates): DEFAULT **behalten**, nur auf explizite Intake-7-Anweisung entfernen (und dann gezielt per `Invoke-ADTAllUsersRegistryAction` / `$envProfilesDirectory`-Iteration pro User)

Gegenbeispiel zum Warnen: NIE `Remove-Item 'HKLM:\SOFTWARE\<Hersteller>' -Recurse` machen. Immer APP-Sub-Key.

**4c. `Repair-ADTDeployment`** — Werte aus Intake-Frage 8:

- Wenn in Intake "nicht benoetigt": Hook leer lassen oder mit `Write-ADTLogEntry -Message 'Repair nicht unterstuetzt - bitte Uninstall + Install nutzen.'` + `throw` abbrechen
- MSI: `Start-ADTMsiProcess -Action Repair -FilePath '{<ProductCode>}' -ArgumentList '/fa /qn'` (`/fa` = alle Files neu, Shortcuts + Registry werden erneut gesetzt)
- EXE-Wrapper ohne dedizierten Repair-Modus: Uninstall gefolgt von Install im selben Hook; User-Config moeglichst erhalten (Backup-Wiederherstell-Logik wenn noetig)
- Config-Only-Repair: Service stoppen, Config-Files aus `SupportFiles\` zurueckkopieren, Service starten - ohne die App neu zu installieren (schneller, weniger invasiv)

**Custom-Helpers** IMMER in `<pkg>\PSAppDeployToolkit.Extensions\PSAppDeployToolkit.Extensions.psm1`, nie im Main-Script.

### 5. Pre-Flight-Checks (Pflicht vor Packen)

Dreimal gruen pro Deployment-Type, sonst nicht weiter:

```powershell
$s = '<pfad-zur-ps1>'

# Check 1: Encoding
$bytes = [System.IO.File]::ReadAllBytes($s)
$hasBom = $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
$text = [System.IO.File]::ReadAllText($s, [System.Text.Encoding]::UTF8)
$nonAscii = ([regex]::Matches($text, '[^\x00-\x7F]')).Count
"HasBOM=$hasBom NonAscii=$nonAscii"   # Anforderung: HasBOM=True ODER NonAscii=0

# Check 2: Parse
$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($s, [ref]$null, [ref]$errs)
if ($errs) { $errs | Select Message,@{N='L';E={$_.Extent.StartLineNumber}} | Format-List } else { 'PARSE_OK' }

# Check 3: Launcher-Acid-Test pro Deployment-Type (je einmal)
foreach ($dt in 'Install','Uninstall','Repair') {
    "--- Acid-Test $dt ---"
    Start-Process powershell.exe -ArgumentList `
        '-ExecutionPolicy','Bypass','-NonInteractive','-NoProfile','-NoLogo',`
        '-Command', "try { & '$s' -DeploymentType $dt -DeployMode Silent } catch { throw }; exit `$Global:LASTEXITCODE" `
        -Wait -NoNewWindow -RedirectStandardError "stderr-$dt.log"
    Get-Content "stderr-$dt.log"   # Darf keine Parse-Errors zeigen
}
```

Wenn einer der drei Types rot wird: das ist NICHT ok auch wenn Install gruen ist. Company-Portal-User kriegt sonst beim Uninstall-Klick 0x80070001.

Bei Encoding-Bug (Check 1 rot oder Check 3 Parse-Errors): Em-Dashes / Smart-Quotes ersetzen + UTF-8 BOM:
```powershell
$text = [System.IO.File]::ReadAllText($s, [System.Text.Encoding]::UTF8)
$text = $text -replace [char]0x2014, '-' -replace [char]0x2013, '-' -replace [char]0x2192, '->' `
              -replace [char]0x2018, "'" -replace [char]0x2019, "'" `
              -replace [char]0x201C, '"' -replace [char]0x201D, '"' -replace [char]0x2026, '...'
[System.IO.File]::WriteAllText($s, $text, [System.Text.UTF8Encoding]::new($true))
```

Bei Check 3 zu gefaehrlich weil echter Install starten wuerde: Test-Stub aus Guide Anhang C verwenden (Install-ADTDeployment-Call ersetzen durch `exit 77`-Stub, Launcher-Test, erwartet Exit 77).

Zusaetzlich scannen:
```powershell
# v3-Reste
$v3 = 'Execute-Process','Execute-MSI','Write-Log','Show-InstallationWelcome','Show-InstallationProgress','Show-InstallationPrompt','Get-InstalledApplication','Remove-MSIApplications','Refresh-Desktop','Update-GroupPolicy','Block-AppExecution'
$t = [System.IO.File]::ReadAllText($s)
foreach ($fn in $v3) { $m = [regex]::Matches($t, "\b$fn\b"); if ($m.Count) { "V3_FOUND: $fn ($($m.Count)x)" } }

# Top-Level-Statements die werfen koennten
$ast = [System.Management.Automation.Language.Parser]::ParseFile($s, [ref]$null, [ref]$null)
$ast.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] } |
    ForEach-Object { "L$($_.Extent.StartLineNumber): $($_.GetType().Name)" }
```

### 6. Packen mit IntuneWinAppUtil

**Output-Ordner-Konvention (VERBINDLICH, nicht jedes Mal woanders):** Das fertige `.intunewin` IMMER nach
`c:\Temp\PSADTv4\Output\<AppName[-Version]>\` legen - ein zentraler `Output`-Ordner im PSADTv4-Hauptverzeichnis,
darunter ein Unterordner pro App (z.B. `Output\EclipseJEE\`, `Output\RSAT-1.0.0\`, `Output\ApacheMaven-3.9.16\`).
NIE einen eigenen `_IntuneOutput`/`<App>-IntuneOutput`-Ordner neben dem Paket anlegen. In den App-Unterordner gehoeren
neben der `.intunewin` auch das Detection-Script und das Intune-Dossier (1 Ort pro App, alles beisammen).
Wichtig: `-c` (Source) ist der PAKET-Ordner, `-o` (Output) ist der zentrale Output-Unterordner - die beiden sind
verschiedene Baeume, also liegt `-o` automatisch AUSSERHALB von `-c`.

```powershell
# IntuneWinAppUtil holen (das GitHub-Release hat KEINE Assets - exe liegt im Repo-Tree, daher raw-Download)
$tool = 'C:\Tools\IntuneWinAppUtil.exe'
if (-not (Test-Path $tool)) {
    New-Item 'C:\Tools' -ItemType Directory -Force | Out-Null
    $tag = (Invoke-RestMethod 'https://api.github.com/repos/microsoft/Microsoft-Win32-Content-Prep-Tool/releases/latest').tag_name
    Invoke-WebRequest "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/$tag/IntuneWinAppUtil.exe" -OutFile $tool
}

$src = '<pkgFolder>'                                            # Paket-Ordner mit Invoke-AppDeployToolkit.ps1/.exe
$out = 'c:\Temp\PSADTv4\Output\<AppName[-Version]>'             # ZENTRAL, pro-App-Unterordner
New-Item $out -ItemType Directory -Force | Out-Null
& $tool -c $src -s 'Invoke-AppDeployToolkit.exe' -o $out -q
# Detection-Script + Dossier daneben legen (Dossier IMMER als Intune-Dossier.md):
Copy-Item '<pkgFolder>\Detect-*.ps1' $out -Force -ErrorAction SilentlyContinue
Copy-Item '<pkgFolder>\Intune-Dossier.md' $out -Force -ErrorAction SilentlyContinue
```

**Kritisch**: `-o` NIE INNERHALB von `-c` waehlen - sonst landet beim Rebuild die alte .intunewin rekursiv im Paket.
Der zentrale `Output\`-Ordner liegt ohnehin ausserhalb jedes Paket-Ordners, das ist genau der Grund fuer die Konvention.

Verify der .intunewin:
```powershell
$iw = Get-ChildItem "$out\*.intunewin" | Select-Object -First 1
"Size: $([Math]::Round($iw.Length / 1MB, 1)) MB"
Expand-Archive $iw.FullName -DestinationPath "$env:TEMP\iw-check" -Force
Get-Content "$env:TEMP\iw-check\IntuneWinPackage\Metadata\Detection.xml" | Select-String 'SetupFile'
# Muss zeigen: <SetupFile>Invoke-AppDeployToolkit.exe</SetupFile>
```

### 7. Intune-Dossier

Anhang F aus dem Referenz-Guide als Template: die Datei IMMER **`Intune-Dossier.md`** nennen (fixer Name, NICHT `<App>-IntuneDossier.md` oder `Intune-App-Metadata.md` - der App-Name steckt schon im Output-Unterordner) und im zentralen `Output\<App>\`-Ordner ablegen. Alle Tabellen fuellen (App Info, Description-Markdown, Program, Return Codes inkl. 60001/60008=Failed, Requirements, Detection, Dependencies, Supersedence, Assignments). User pruefen lassen, dann er/sie uebertraegt die Werte 1:1 ins Intune Admin Center.

**App-Logo automatisch besorgen (Pflicht):** Ein passendes Logo der App suchen und herunterladen - **PNG, transparenter Hintergrund, hohe Aufloesung** (Richtwert >= 512px, lieber mehr; quadratisch ist fuer die Company-Portal-Kachel am besten). Ablegen unter `<pkg>\Assets\<App>-Logo.png` UND eine Kopie nach `Output\<App>\`. Im Dossier in der Logo-Zeile den Dateinamen referenzieren.
- **Quelle lizenzklar waehlen:** zuerst offizielle Hersteller-/Projekt-Quelle (z.B. `apache.org/logos/res/<projekt>/` fuer Apache-Projekte), sonst **Wikimedia Commons** (stabile URLs, SVG wird serverseitig als transparentes PNG gerendert):
  ```powershell
  # Wikimedia: SVG -> transparentes PNG in Wunschbreite (hier 1024)
  $api = "https://commons.wikimedia.org/w/api.php?action=query&titles=$([uri]::EscapeDataString('File:<Logo>.svg'))&prop=imageinfo&iiprop=url&iiurlwidth=1024&format=json"
  $thumb = ((Invoke-RestMethod $api -Headers @{'User-Agent'='PSADT-pkg/1.0'}).query.pages.PSObject.Properties.Value).imageinfo[0].thumburl
  Invoke-WebRequest $thumb -OutFile '<pkg>\Assets\<App>-Logo.png' -Headers @{'User-Agent'='PSADT-pkg/1.0'}
  ```
  Drittanbieter-PNG-Portale (stickpng, toppng, nicepng ...) meiden - Hotlink-Schutz/Werbung/fragliche Qualitaet.
- **Verifizieren** (Transparenz + Aufloesung) und dem User zeigen, dass es das richtige Logo ist:
  ```powershell
  Add-Type -AssemblyName System.Drawing
  $i=[System.Drawing.Image]::FromFile('<png>'); "{0}x{1} Alpha={2}" -f $i.Width,$i.Height,[System.Drawing.Image]::IsAlphaPixelFormat($i.PixelFormat); $i.Dispose()
  ```
  Alpha MUSS True sein (sonst kein transparenter Hintergrund -> anderes File suchen). Das Logo wird in Intune separat im **App-Information-Tab** hochgeladen, ist NICHT Teil des `.intunewin` (kein Repack noetig).

**App-Beschreibung IMMER auf DEUTSCH mit echten Umlauten (ä, ö, ü, ß)** - das ist Endnutzer-Text im Company Portal, KEIN ae/oe/ue ausschreiben. (Gilt nur fuer die Dossier-Markdown; die Scripts bleiben Englisch/ASCII - siehe Konventionen.)

**App-Beschreibung IMMER in Markdown formatieren** - das Intune-Beschreibungsfeld rendert Markdown (Toolbar-Editor) und stellt es im Company Portal formatiert dar. KEINE reine Fliesstext-Wand. Den Description-Block im Dossier als fertiges Markdown liefern, das der User 1:1 ins Beschreibungsfeld einfuegen kann. Unterstuetzter Funktionsumfang (sicher nutzbar):
- **Fett** und *kursiv* fuer Hervorhebungen
- Aufzaehlungslisten (`-`) und nummerierte Listen (`1.`) - ideal fuer Voraussetzungen, gesetzte Variablen, Was-passiert-Schritte
- Links `[Text](https://...)` fuer Hersteller-/Doku-Seiten
- Kurze Absaetze statt Block
- Vorsichtig/sparsam: Ueberschriften und Tabellen (Rendering im Company Portal variiert) - lieber Fett-Zeile + Liste

Empfohlene Struktur der Beschreibung (anpassen pro App):
```markdown
**<AppName> <Version>** - <Ein-Satz-Nutzen>.

**Was diese Bereitstellung macht:**
- <Installationsziel / Pfad>
- <gesetzte Umgebungsvariablen / Registry / Config>
- <besondere Nebenwirkungen>

**Voraussetzungen:**
- <z.B. JDK, .NET, Vorgängerversion>

**Bei Deinstallation:**
- <was entfernt wird> / <was erhalten bleibt>

Mehr Infos: [Herstellerseite](https://...)
```

Pflicht-Return-Codes die immer rein muessen: `0 Success, 1707 Success, 3010 Soft reboot, 1641 Hard reboot, 1618 Retry, 60001 Failed, 60008 Failed` + installer-spezifische Codes aus der Recherche.

### 8. Test-Sequenz (VOR Production-Rollout) — alle drei Deployment-Types

Auf DEV-VM in dieser Reihenfolge. Nach jedem erfolgreichen Install kommt der Uninstall-Test auf **der gleichen VM** (nicht neue VM) - damit Uninstall auch wirklich was zum Abraeumen hat.

**Install-Zyklus:**
1. `.\Invoke-AppDeployToolkit.ps1 -DeploymentType Install -DeployMode Silent` (Smoke-Test)
2. `.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent` (Launcher-Acid-Test)
3. `psexec -s cmd /c "cd /d <pkg> && Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent"` (SYSTEM-Context; PsExec: https://learn.microsoft.com/en-us/sysinternals/downloads/psexec)

**Uninstall-Zyklus (auf gleicher VM, App muss installiert sein):**
4. `.\Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent`
5. Verifikations-Checks nach Uninstall:
   - Detection-Script (siehe Phase 5 Guide) muss `exit 0 + stdout empty` geben (App = nicht installiert)
   - `Get-Service '<App-Service>' -ErrorAction SilentlyContinue` - leer
   - `Get-ScheduledTask '<App-Prefix>*' -ErrorAction SilentlyContinue` - leer
   - Install-Directory: weg (oder nur User-Config-Reste falls Intake-7 so gewuenscht)
   - Registry unter `HKLM:\SOFTWARE\<Hersteller>\<App>` - weg
   - Firewall-Rules `Get-NetFirewallRule -DisplayName '<App>*'` - leer
   - WICHTIG: Nachbarprodukte gleicher Hersteller noch da (nicht versehentlich mitgeloescht)

**Repair-Zyklus (VM wieder neu installieren, dann Repair):**
6. Install wiederholen (Step 1)
7. `.\Invoke-AppDeployToolkit.exe -DeploymentType Repair -DeployMode Silent`
8. Detection muss danach weiter = installed zeigen; App-Funktionalitaet manuell smoke-testen

**Intune-Testgruppe (nach allen drei Zyklen gruen):**
9. Paket zuweisen als Required → 1 Test-Device → PSADT-Install-Log + AppWorkload.log pruefen
10. Von Device uninstallen: in Admin Center als "Uninstall" zuweisen ODER User ueber Company Portal deinstallieren → PSADT-Uninstall-Log pruefen

Pruefen in jedem Intune-Test:
- `C:\Windows\Logs\Software\<AppName>*PSAppDeployToolkit_Install.log` / `*_Uninstall.log` existiert
- `Close-ADTSession` mit Exit 0 drin
- AppWorkload.log zeigt passenden Status (`Installed` / `Uninstalled`)

Nach erfolgreichem Test aller drei Types: Pilot-Gruppe 24-48h, dann Production staged.

## Troubleshooting-Quick-Reference

Bei User-Reports in dieser Reihenfolge abklopfen:

| Symptom | Primaerverdacht | Verifikation |
|---|---|---|
| `0x80070001` + keine lokalen PSADT-Logs | Encoding (Em-Dash in "-String") oder Top-Level-Throw | Phase 5 Checks + Anhang A.2 |
| `0x8000EA68` (60008) + PSADT-Log vorhanden aber leer nach Init | Import-Module / Open-ADTSession wirft | PSADT-Log direkt lesbar, Stack in Anhang A.2 |
| `0x8000EA61` (60001) + Stacktrace im PSADT-Log | Runtime-Error in Install-ADTDeployment | Stack zeigt Zeile direkt |
| App haengt "Installing" in Company Portal | IME-State-Cache oder Prozess haengt | Anhang A.2 Aufraeum-Sequenz |
| `0x80070002` | Launcher findet .ps1 nicht | `-s` beim Packen war falsch |
| Detection failed after successful install | Detection-Script-Bug (Contract-Verletzung, 32/64-bit-Registry) | Manuell auf Target: `.\Detect-*.ps1; $LASTEXITCODE` |

HRESULT-Umrechnung: Intune zeigt unbekannte positive Exit-Codes als `0x80070000 + code`. Also `0x80070001` = Exit 1 = Script lief gar nicht. Immer gegenrechnen, nicht von "ERROR_INVALID_FUNCTION"-Text blenden lassen.

Logs in dieser Reihenfolge pruefen:
1. `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AppWorkload.log` (was IME tatsaechlich gemacht hat + Exit-Code)
2. `C:\Windows\Logs\Software\<AppName>*PSAppDeployToolkit_Install.log` (PSADT-Session, wenn Init OK war)
3. `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` (IME-Service-State)

## Anti-Patterns (niemals tun)

- v3-Cmdlet-Namen (`Execute-Process`, `Write-Log`, `Show-InstallationWelcome`, ...)
- Em-Dash/Smart-Quote in Double-Quoted Strings
- UTF-8-Speichern ohne BOM wenn Non-ASCII drin ist
- Top-Level-Code ausserhalb try/catch
- `-o` im `-c` beim IntuneWinAppUtil
- Return Codes 60001/60008 nicht als Failed mappen
- Annehmen "laeuft lokal = laeuft in Intune" - Launcher-Acid-Test ist Pflicht
- Detection gemischt (Custom-Script + File-Rule parallel)
- Extensions-Funktionen ins Main-Script packen statt in Extensions-Modul
- Install-Zeit reflexartig auf 120 min - 60 min ist fast immer richtig
- Fallback-Loesch-Aktionen bei erster negativer Async-Antwort triggern (Services brauchen 30-60s nach msiexec, Retry-Loop bauen)
- Desktop-Icons anlegen (oder vom Installer angelegte stehen lassen) - nur Startmenue-Eintraege, Desktop bleibt sauber
- Neuere PSADT-Version nur an der Nummer erkennen und blind uebernehmen - immer Release Notes/Changelog auf geaenderte/deprecated Commands pruefen

## Referenz-Nachschlag

Fuer Tiefe zu jedem Thema: `c:\Temp\PSADTv4\OracleDB\PSADTv4-Deployment-Guide.md`
- Phase 0.2: Komplette Intake-Fragen-Liste
- Phase 0.3: Web-Recherche-Pattern
- Phase 3.1: Encoding-Fix-Details
- Phase 5: Intune-Config-Felder
- Anhang A: Error-Codes + Root-Causes
- Anhang B: Anti-Pattern-Liste
- Anhang C: Test-Stub-Muster
- Anhang D: Alle Ressourcen-URLs
- Anhang E: Finale Deploy-Checkliste
- Anhang F: Vollstaendiges Intune-Upload-Dossier-Template (alle Felder, alle Tabs)
- Anhang G: Lessons aus dem Oracle-XE-Projekt
