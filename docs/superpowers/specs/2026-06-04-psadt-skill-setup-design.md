# Design: Erst-Setup & optionaler Intune-Upload fuer den psadt-deploy Skill

- **Datum:** 2026-06-04
- **Autor:** Patrick Taubert, PHAT Consulting GmbH (mit Claude Code)
- **Status:** Design freigegeben, wartet auf User-Review der Spec
- **Betrifft:** `~/.claude/skills/psadt-deploy/`

> Hinweis zur Sprache dieses Dokuments: Diese Spec und die `SKILL.md` sind interne
> Skill-/Prozess-Artefakte und bleiben in Markdown. Die neue HTML-Konvention (siehe unten)
> gilt fuer die **Deliverables** (Intune-Dossier, Beschreibungs-Block), NICHT fuer Skill-
> oder Prozess-Dokumente.

## 1. Problem / Motivation

Der `psadt-deploy` Skill verdrahtet aktuell zentrale Konventionen direkt im Prosa-Text der
`SKILL.md`:

- Output-Pfad `c:\Temp\PSADTv4\Output\`
- IntuneWinAppUtil unter `C:\Tools\IntuneWinAppUtil.exe`
- Sprach-Split (Dossier DE / Scripts EN)
- Author `Patrick Taubert, PHAT Consulting GmbH`

Diese Werte muessen pro Maschine/Umgebung stimmen, sind aber nirgends zentral konfigurierbar.
Ausserdem fehlt dem Skill eine **Direkt-Upload-Faehigkeit nach Intune** komplett — inkl. der
dafuer noetigen Entra-App-Registrierung.

**Ziel:** Ein einmaliges **Setup (Phase 0)**, das diese Werte in eine persistente Config zieht,
plus eine **optionale** Intune-Direkt-Upload-Faehigkeit ueber Microsoft Graph.

## 2. Entscheidungen (vom User bestaetigt)

| Thema | Entscheidung |
|---|---|
| Config-Ablage | Im Skill-Ordner: `~/.claude/skills/psadt-deploy/config.json` |
| Secret-Ablage | DPAPI-verschluesselt (CurrentUser) in `secret.dpapi`, getrennt von der Config |
| Setup-Trigger | Beides: Auto bei fehlender/unvollstaendiger Config UND explizit re-triggerbar ("psadt setup") |
| Upload-Modus | Skill laedt selbst hoch (Graph), aber **optional** und pro Lauf ablehnbar |
| Auth-Methode | Client-Secret (Tenant-ID + Client-ID in config.json, Secret per DPAPI) |
| Architektur | Hybrid: Helfer-Skripte fuer Sicherheits-/Komplexitaetsteile, Wizard/Customizing bleibt modellgesteuert |
| Ausgabeformat | Neue Konvention: Deliverables in **HTML** statt Markdown (Dossier komplett). `SKILL.md` bleibt Markdown |
| Author | Strukturiert in der Config (`person` + `company`), im Setup getrennt abgefragt |

**Wichtige Randbedingung:** Der Upload bleibt **vollstaendig optional**. Nicht in jedem Tenant
besteht die Moeglichkeit, eine App zu registrieren (z.B. Kunden-Tenant). `uploadEnabled: false`
bzw. ein fehlender `intune`-Block ist ein vollwertiger Zustand — dann faellt der Skill auf den
bisherigen manuellen Flow (`.intunewin` + Dossier, Upload von Hand im Admin Center) zurueck.

**Kein Plugin:** Es bleibt ein Skill mit mitgelieferten Hilfsdateien (`scripts/`, `references/`),
keine Umwandlung in ein Claude-Code-Plugin.

## 3. Dateistruktur

```
~/.claude/skills/psadt-deploy/
├─ SKILL.md                          (Markdown; bekommt Phase 0 + Upload-Phase + HTML-Umstellung)
├─ config.json                       (nicht eingecheckt; entsteht beim Setup)
├─ secret.dpapi                      (DPAPI-Blob, nur das Secret; nie Klartext)
├─ references/
│  └─ app-registration.md            (Anleitung Entra-App-Registrierung)
└─ scripts/
   ├─ Get-PsadtConfig.ps1            (liest config.json -> Objekt; meldet fehlende Felder)
   ├─ Set-PsadtConfig.ps1           (schreibt/aktualisiert config.json; DPAPI-verschluesselt Secret)
   ├─ Invoke-IntuneWin32Upload.ps1  (Graph-Upload: Token -> App -> Content -> Blob -> Commit -> Assign)
   └─ Test-PsadtSetup.ps1           (Auth-Smoke-Test: Token holen + 1 Graph-GET)
```

`config.json` und `secret.dpapi` sind maschinen-/benutzerlokaler Laufzeit-Zustand und werden
nicht mit dem Skill verteilt. Das Setup behandelt sie als "erzeuge-falls-fehlt".

## 4. Config-Schema (`config.json`)

```json
{
  "version": 1,
  "paths": {
    "packageRoot":      "c:\\Temp\\PSADTv4",
    "outputRoot":       "c:\\Temp\\PSADTv4\\Output",
    "intuneWinAppUtil": "C:\\Tools\\IntuneWinAppUtil.exe"
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

**Feld-Regeln:**

- Die vier vom User geforderten Werte sind abgedeckt: Ablage (`paths.packageRoot`/`outputRoot`),
  Sprache (`language.script`/`dossier`), Tool-Pfad (`paths.intuneWinAppUtil`), Upload + App-Reg
  (`intune.*`). Plus `author` (vorher hartverdrahtet).
- **Das Secret steht NIE in `config.json`** — nur `tenantId`/`clientId`. `secretRef` zeigt auf die
  DPAPI-Datei.
- `author` ist strukturiert; der Skill setzt `AppScriptAuthor = "<person>, <company>"` zusammen.
- `intune.defaultAssignment` ∈ `{ "available", "required", "none" }`.
- Wenn der `intune`-Block fehlt ODER `uploadEnabled: false`, ist der Upload deaktiviert.

## 5. Komponenten

### 5.1 `Get-PsadtConfig.ps1`
- Liest `config.json`, gibt ein PowerShell-Objekt zurueck.
- Validiert Vollstaendigkeit; gibt eine **Liste fehlender/ungueltiger Felder** zurueck, damit der
  Wizard gezielt nur diese nachfragt.
- Entschluesselt das Secret NICHT von sich aus (separater Pfad nur zur Upload-Zeit).

### 5.2 `Set-PsadtConfig.ps1`
- Schreibt/aktualisiert `config.json` (partielle Updates moeglich, Schema-validiert).
- Nimmt das Secret als Parameter entgegen, **DPAPI-verschluesselt** es (Scope CurrentUser) nach
  `secret.dpapi`. Secret wird nie nach `config.json` oder in Logs geschrieben, nie zurueckgegeben.

### 5.3 `Invoke-IntuneWin32Upload.ps1`
- Holt App-only-Token via Client-Secret (Tenant-/Client-ID aus Config, Secret per DPAPI entschluesselt,
  nur in-memory).
- Legt `win32LobApp` an, erstellt Content-Version, nutzt die Verschluesselungs-Metadaten aus der
  `.intunewin` (Detection.xml) fuer den **Block-Blob-Upload** nach Azure Storage, committed die Version.
- Laedt das App-Logo separat hoch (Graph kann das, kein Repack der `.intunewin` noetig).
- Setzt Assignment gemaess `defaultAssignment`.
- **Idempotent:** Existiert eine App gleichen DisplayName + Version bereits, wird vor
  Ueberschreiben/Supersedence gefragt.
- Gibt App-ID + Portal-Link zurueck.

### 5.4 `Test-PsadtSetup.ps1`
- Auth-Smoke-Test: Token holen + ein einfacher Graph-GET (z.B. `/deviceAppManagement/mobileApps?$top=1`).
- Liefert klare Diagnose bei Fehlern (Secret falsch / Permission fehlt / Admin-Consent fehlt).

### 5.5 `references/app-registration.md`
Kurz-Checkliste zur Entra-App-Registrierung:
1. Entra Admin Center → App registrations → New registration
2. API permissions → Microsoft Graph → **Application** → `DeviceManagementApps.ReadWrite.All`
3. **Grant admin consent**
4. Certificates & secrets → New client secret → Wert kopieren (nur einmal sichtbar)
5. Tenant-ID + Client-ID + Secret ins Setup eingeben

## 6. SKILL.md-Aenderungen

### 6.1 Phase 0 — Setup (neu, vor Intake)
- Skill ruft `Get-PsadtConfig.ps1`. Vollstaendig → direkt zu Intake. Fehlt/unvollstaendig → Wizard
  (fragt nur fehlende Felder).
- Wizard als AskUserQuestion-Batches (Klick-Optionen, empfohlene Option zuerst):
  1. **Pfade** (`packageRoot`, `outputRoot`, `intuneWinAppUtil`) — aktuelle Werte als Defaults
  2. **Sprachen** (`script`=EN, `dossier`=DE als Defaults)
  3. **Author** — Person + Firma getrennt (Defaults = bisherige Konvention)
  4. **Intune-Upload**: Ja / Nein / Spaeter
  5. Falls Ja: Tenant-ID, Client-ID (Freitext), Secret (Freitext → sofort DPAPI, nie zurueckgezeigt),
     `defaultAssignment`
- Bei Ja: `Test-PsadtSetup.ps1` ausfuehren; rot → klare Meldung, `uploadEnabled` wird erst nach
  gruenem Test `true`.
- Explizit re-triggerbar ("psadt setup") → einzelne Werte aendern.
- Verlinkt `references/app-registration.md`.

### 6.2 Config statt Hardcode
Ueberall im Skill die festen Werte durch Config-Lookups ersetzen: `outputRoot`, `intuneWinAppUtil`,
`author`, Sprachen. Die bisherigen VERBINDLICHEN Werte bleiben als **Defaults** erhalten — jetzt
config-getrieben statt im Text gemauert.

### 6.3 Neue Phase — Intune-Upload (optional, zwischen Packen und Test)
- Nur bei `uploadEnabled: true`. Sonst: bisheriger manueller Flow, explizit als Fallback dokumentiert.
- Auch bei `uploadEnabled: true` **pro Lauf ablehnbar** (z.B. Kunden-Tenant ohne Rechte) → manueller
  Fallback.
- `Invoke-IntuneWin32Upload.ps1` aufrufen, Ergebnis (App-ID + Portal-Link) anzeigen.

### 6.4 HTML-Umstellung (neue Konvention)
- Dossier → `Intune-Dossier.html`, komplett HTML; Beschreibungs-Block als sauberes HTML
  (Intune-Beschreibungsfeld hat HTML-Editor).
- Konventionen-Block, Phase 7 und Anti-Patterns von "Markdown" auf "HTML" umschreiben.
- `SKILL.md` selbst bleibt Markdown.
- Echte DE-Umlaute im Dossier bleiben; Scripts bleiben EN/ASCII (Encoding-Sauberkeit unveraendert).

### 6.5 DPAPI-Ablauf informativ im Skill verankern
Die `SKILL.md` bekommt einen kurzen, **informativen** Abschnitt, der den DPAPI-Ablauf erklaert —
damit der Skill einem User auf Rueckfrage ("wie wird mein Secret gespeichert?") sauber antworten kann:
- Verschluesselung erfolgt **automatisch** durch `Set-PsadtConfig.ps1` (Windows-DPAPI,
  `ConvertFrom-SecureString`, Scope CurrentUser) — der User macht die Krypto NICHT von Hand.
- Das Secret wird **im eigenen Terminal** per `Read-Host -AsSecureString` eingegeben, damit es nie ins
  Claude-Transkript gelangt (Tool-Aufrufe sind nicht-interaktiv → das Setup gibt dem User den
  Einzeiler aus, statt das Secret selbst abzufragen).
- Bindung an User+Maschine: ein kopiertes `secret.dpapi` ist auf einer anderen Maschine/unter anderem
  User wertlos.
- Entschluesselung nur in-memory zur Upload-Zeit; bei Secret-Rotation Setup erneut anstossen.

## 7. Sicherheit

- Secret ausschliesslich per **DPAPI (Scope CurrentUser)** → an User+Maschine gebunden, kein Klartext
  im Profil.
- **Secret-Eingabe NICHT ueber den Chat:** Das Setup laesst den User das Secret im eigenen Terminal per
  `Read-Host -AsSecureString` eingeben (Einzeiler vom Skill ausgegeben). So landet der Klartext nie im
  Konversations-Transkript. `AskUserQuestion`-Freitext fuer das Secret wird bewusst vermieden.
- Secret nie in `config.json`, nie in Logs, nie im Konversations-Output; Entschluesselung nur
  in-memory zur Upload-Zeit.
- Setup zeigt das eingegebene Secret nach Eingabe nicht erneut an.

## 8. Fehlerbehandlung

- `Get-PsadtConfig.ps1` liefert strukturierte "fehlende Felder" → Wizard fragt nur diese.
- `Test-PsadtSetup.ps1` / Upload: Token-Fehler → klare Ursache (Secret/Permission/Consent). Graph-4xx
  durchreichen statt verschlucken.
- Upload idempotent: bestehende App gleicher Version → vor Ueberschreiben/Supersedence fragen.
- Fehlender/abgelehnter Upload ist kein Fehler → sauberer Fallback auf manuellen Flow.

## 9. Tests

- Helfer-Skripte: parse-clean (AST), DPAPI-Round-Trip-Test (verschluesseln → entschluesseln → gleich).
- `Get`/`Set-PsadtConfig`: Schema-Validierung, partielle Updates, Erkennung fehlender Felder.
- `Test-PsadtSetup.ps1` als Live-Auth-Check (gegen einen Test-Tenant, wo verfuegbar).
- `Invoke-IntuneWin32Upload.ps1`: gegen Test-Tenant ein echtes Klein-Paket hochladen, App-ID
  pruefen, danach wieder aufraeumen.

## 10. Bewusst NICHT im Scope (YAGNI)

- Zertifikat- oder Delegated-Auth (Entscheidung: Client-Secret).
- Verteilung als Claude-Code-Plugin / Marketplace.
- Multi-Tenant-Profile in einer Config (eine Config pro Maschine; Tenant-Wechsel via Re-Setup).
- Automatische Secret-Rotation.
