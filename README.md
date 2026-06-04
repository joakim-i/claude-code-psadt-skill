# claude-code-psadt-skill

Ein **Claude-Code-Skill** (kein Plugin) fuer den kompletten Lebenszyklus eines
**PSADT-v4.x-Intune-Win32-Pakets** — vom ersten Gespraech bis zum getesteten,
hochladefertigen `.intunewin`, optional inklusive Direkt-Upload nach Intune via
Microsoft Graph.

## Inhalt

| Pfad | Zweck |
|---|---|
| `SKILL.md` | Der Skill selbst (Markdown). |
| `scripts/` | Helfer-Skripte (Config lesen/schreiben, DPAPI, Graph-Upload, Auth-Test). |
| `references/` | Nachschlag (z.B. Anleitung Entra-App-Registrierung). |
| `docs/superpowers/specs/` | Design-Dokumente / Specs. |

## Installation

Den Skill-Ordner nach `~/.claude/skills/psadt-deploy/` kopieren oder verlinken
(Repo-Root entspricht dem Skill-Ordner). Anschliessend laeuft beim ersten Aufruf
automatisch das Setup (Phase 0).

## Konfiguration (maschinenlokal, NICHT im Repo)

Das Setup erzeugt pro Maschine:

- `config.json` — Pfade, Sprache, Author, optionale Intune-Upload-Settings (Tenant-/Client-ID).
- `secret.dpapi` — das Client-Secret, **DPAPI-verschluesselt** (Scope CurrentUser), an
  User+Maschine gebunden.

Beide Dateien sind per `.gitignore` ausgeschlossen und werden nie eingecheckt.

## Hinweise

- **Kein Plugin:** bewusst als reiner Skill gehalten. Eine spaetere Plugin-Verpackung
  waere ein separater Schritt.
- **Intune-Upload ist optional:** ohne eingerichtete App-Registrierung faellt der Skill
  auf den manuellen Upload via Dossier zurueck (z.B. in Kunden-Tenants ohne Registrierungsrechte).
