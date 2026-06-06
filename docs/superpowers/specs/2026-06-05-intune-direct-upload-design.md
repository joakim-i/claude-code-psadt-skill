# Direct Intune Upload (Microsoft Graph) — Design Spec

- **Date:** 2026-06-05
- **Branch:** `intune-dev-upload`
- **Status:** IMPLEMENTED (2026-06-06) and verified against a live tenant. See `CHANGELOG.md` 0.3.0 and
  reference guide **Appendix H** for the as-built behaviour and the Graph gotchas discovered during
  implementation. Deltas from this design (kept here for history):
  - **Auth (bootstrap):** uses **WAM** (Windows broker) with device-code fallback — not device-code-only.
  - **Detection:** the live backend requires the unified **`rules`** collection (`win32LobAppProductCodeRule`),
    not the legacy `detectionRules` named in §4.4/§4.5.
  - **API version:** metadata is written on **`/beta`** (v1.0 silently drops `displayVersion` et al.).
  - **Content upload:** **HttpClient/ByteArrayContent** (raw bytes) — `Invoke-RestMethod -Body <byte[]>`
    corrupts the blob and fails the commit.
  - **Script consolidation:** `Test-PsadtSetup.ps1` and `New-IntuneWin32AppBody.ps1` were folded **into**
    `Invoke-IntuneWin32Upload.ps1` (the read-only probe + body-builder run inline) rather than shipped as
    separate scripts. `Get-GraphToken.ps1` ships as designed.
  - **Coexistence:** new versions create a **separate** app by default (`-OnExisting CreateNewCoexist`); the
    script **never deletes**; optional `-SupersedesAppId` wiring added.
  - **Metadata completeness + boundaries:** fills the full App-information tab; never auto-assigns
    category/branded-notes/featured/groups. **Logo guard** added (refuses the PSADT default icon).
- **Skill:** `psadt-deploy` (PSADT v4.x → Intune Win32 lifecycle)

## 1. Goal

Add an **optional** capability to upload a finished `.intunewin` package straight to Intune via
Microsoft Graph, turning the already-generated dossier metadata into a single API push — instead of the
manual copy-paste into the Intune Admin Center. The manual dossier flow remains the documented fallback
for tenants where direct upload is not possible.

Scope of what is pushed: **the full Win32 LOB app object + logo, but NOT assignment.** The admin assigns
to Entra groups manually — a deliberate human step that keeps the blast radius bounded.

## 2. Decisions (locked during brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| Implementation | **Self-contained raw Graph** | No third-party runtime dependency; matches the skill's self-healing/minimal philosophy; auditable. |
| Upload scope | **Full app + logo, NO assignment** | One API push from the dossier; assignment stays a deliberate human action. |
| Idempotency | **Detect + ask** (default: update-in-place) | Preserves existing assignments/history; avoids silent updates to the wrong app. |
| Auth (uploads) | **Client secret only**, app-only | Simplest; DPAPI plumbing already exists. Token helper shaped so a cert can drop in later. |
| Safety gating | **Preflight + summary + confirm** | Fail fast before any write; no silent writes to a production tenant. |
| App-registration setup | **Ready-made bootstrap script** (`New-PsadtEntraApp.ps1`) | One run: admin login + consent + secret created and stored automatically. Portal guide kept as fallback. |
| Entra app display name | **Fixed: `PSADT Intune Upload`** | Predictable, no wizard prompt. |

## 3. Key technical insight

`IntuneWinAppUtil` **already AES-encrypts** the payload when it builds the `.intunewin`. The `.intunewin`
is a ZIP containing:

- `IntuneWinPackage/Contents/<name>.intunewin` — the **already-encrypted** content blob.
- `IntuneWinPackage/Metadata/Detection.xml` — holds the **`EncryptionInfo`** (AES key, IV, MAC, profile
  identifier), the **unencrypted content size**, and the **`SetupFile`**.

Therefore we **never implement AES ourselves**. We extract the encrypted blob and **relay** its
`EncryptionInfo` to Graph's `commit` call. This is what keeps a raw-Graph implementation small and
feasible.

## 4. Components

### 4.1 `scripts/New-PsadtEntraApp.ps1` — one-time bootstrap

Creates the Entra app registration (the upload identity) in a single interactive run. Dependency-free:
uses the **device-code flow** against the well-known first-party public client *"Microsoft Graph Command
Line Tools"* (`14d82eec-204b-4c2f-b7e8-296a70dab67e`), so no pre-existing app is needed to authenticate.

Flow:

1. **Interactive admin login** (device-code: show code → browser → sign in). Delegated scopes:
   `Application.ReadWrite.All`, `AppRoleAssignment.ReadWrite.All`. First run prompts the admin to consent
   to this setup action.
2. **Create the app registration** (`POST /applications`, displayName = `PSADT Intune Upload`) + its
   service principal (`POST /servicePrincipals`).
3. **Grant the application permission + admin consent in one step**: first resolve the Microsoft Graph
   service principal in the tenant (`GET /servicePrincipals?$filter=appId eq
   '00000003-0000-0000-c000-000000000000'`) and find the `appRole` id whose value is
   `DeviceManagementApps.ReadWrite.All`. Then assign it to the new app's SP via
   `POST /servicePrincipals/{newSpId}/appRoleAssignments` with
   `{ principalId: <newSpId>, resourceId: <graphSpId>, appRoleId: <roleId> }`. This appRoleAssignment
   **is** the granted admin consent for an application permission — no separate portal click.
4. **Create a client secret** automatically (`POST /applications/{appObjectId}/addPassword`) — the value
   is returned exactly once.
5. **Persist**: write `intune.tenantId`, `intune.clientId`, `intune.uploadEnabled = true` via
   `Set-PsadtConfig.ps1`, and DPAPI-store the secret via the existing `Set-PsadtConfig.ps1 -Secret`. The
   secret is never echoed to the console and never typed by the user.

**Privilege requirement (stated up front, fails cleanly if missing):** the running user must be able to
create an app **and** grant admin consent — i.e. **Global Administrator** or **Privileged Role
Administrator**. (Application Administrator alone cannot perform the appRoleAssignment consent step.) The
script verifies/handles the `Authorization_RequestDenied` failure on step 3 with a clear message and a
pointer to the manual fallback.

Idempotency: if an app named `PSADT Intune Upload` already exists, report it and offer to reuse it
(create only a fresh secret) rather than creating a duplicate.

### 4.2 `scripts/Get-GraphToken.ps1` — app-only token (uploads)

Acquires an app-only **client-credentials** token for the configured tenant/client. Decrypts the DPAPI
secret **in-memory only** (never written back, never logged), returns `{ Token, ExpiresOn }`. Shaped so a
certificate thumbprint can be added later without changing call sites (secret-only for now).

### 4.3 `scripts/Test-PsadtSetup.ps1` — preflight

Read-only validation, run before any upload:

1. Config complete (`intune.tenantId`, `intune.clientId`, `secretRef` present; `secret.dpapi` exists).
2. Secret decryptable; token acquirable via `Get-GraphToken`.
3. Read-only Graph probe: `GET /deviceAppManagement/mobileApps?$top=1` → proves
   `DeviceManagementApps.ReadWrite.All` is effective (a 403 here means consent/permission is missing).

Returns a structured result: `{ Ok, TenantId, ClientId, TokenAcquired, GraphProbeOk, Problems[] }`.

### 4.4 `scripts/New-IntuneWin32AppBody.ps1` — dossier → win32LobApp mapper

Pure function, **no network**. Maps the dossier/intake metadata to the `win32LobApp` request body.
Property names below are **verified against the live Graph `win32LobApp` resource schema** (2026-06-06):

- `@odata.type` = `#microsoft.graph.win32LobApp`
- `displayName`, `description` (Markdown), `publisher`, `developer`/`owner`/`notes` (optional)
- `displayVersion` — the app version shown in the portal (e.g. `3.9.16`)
- `fileName` — the `.intunewin` file name; `setupFilePath` — the `SetupFile` from `Detection.xml`
  (e.g. `Invoke-AppDeployToolkit.exe`)
- `installCommandLine`, `uninstallCommandLine`
- `applicableArchitectures` (enum `windowsArchitecture`, e.g. `x64`); `minimumSupportedWindowsRelease`
  (string, e.g. `1607`) — or the richer `minimumSupportedOperatingSystem` object as an alternative
- `installExperience` (`win32LobAppInstallExperience`): `runAsAccount` = `system` (PSADT norm),
  `deviceRestartBehavior` mapped from intake's reboot decision
- `returnCodes` (`win32LobAppReturnCode` collection) — 0/1707 success, 3010/1641 reboot (soft/hard),
  1618 retry, 60001/60008 failed + researched codes
- `detectionRules` (`win32LobAppDetection` collection) — script or MSI/file rule from the package
- `largeIcon` (`mimeContent` = `{ type: 'image/png', value: <base64> }`) — set here or via the
  activation PATCH

Independently unit-testable.

### 4.5 `scripts/Invoke-IntuneWin32Upload.ps1` — orchestrator

The 8-step Graph Win32 LOB upload flow. **All endpoints below were verified against the live Microsoft
Graph catalog (msgraph skill, 2026-06-06).** Note: the content sub-paths require the
**type-cast segment** `microsoft.graph.win32LobApp` between `mobileApps/{id}` and `contentVersions`.

1. **Parse the `.intunewin`** — unzip; read `Detection.xml` → `EncryptionInfo`, unencrypted size,
   `SetupFile`; extract the inner encrypted blob.
2. **Idempotency check** — `GET /deviceAppManagement/mobileApps` filtered by `displayName`
   (`isof('microsoft.graph.win32LobApp')`). If a match exists, show id / version / lastModified and **ask**
   via click options: *update-in-place* (recommended) / *create new app* / *abort*.
3. **Create or locate the app** — `POST /deviceAppManagement/mobileApps`
   (`@odata.type: #microsoft.graph.win32LobApp`) from the body-builder, **or** reuse the matched app id.
4. **Content version** — `POST .../microsoft.graph.win32LobApp/contentVersions` → `{contentVersionId}`.
5. **Register file** — `POST .../contentVersions/{cvId}/files` with name, `size`, `sizeEncrypted` →
   `{fileId}`; then **poll** `GET .../files/{fileId}` until `uploadState = azureStorageUriRequestSuccess`
   → `azureStorageUri` (SAS).
6. **Block-blob upload** — chunk the encrypted blob to the SAS URI (~6 MB blocks: `PUT block` +
   `PUT block list`, header `x-ms-blob-type: BlockBlob`), with per-block retry and **SAS renewal**
   (`POST .../files/{fileId}/renewUpload`) if the SAS nears expiry on large files.
7. **Commit** — `POST .../files/{fileId}/commit` with the `fileEncryptionInfo` from step 1; **poll** until
   `uploadState = commitFileSuccess`.
8. **Activate + logo** — `PATCH /deviceAppManagement/mobileApps/{id}` setting
   `committedContentVersion = {cvId}` and `largeIcon` (`{ type: 'image/png', value: <base64> }` from the
   dossier logo). Print the **Intune portal deep-link** to the created/updated app.

**Assignment is intentionally NOT performed.**

All poll loops have **timeout caps** and surface the last `uploadState` on failure. Async states never
loop forever.

### 4.6 `references/app-registration.md` — manual fallback

Step-by-step Entra portal guide (create app → add `DeviceManagementApps.ReadWrite.All` **application**
permission → grant admin consent → create client secret → feed tenantId/clientId/secret into the wizard).
For tenants/policies where `New-PsadtEntraApp.ps1` cannot be run.

## 5. Configuration

No schema change — the `intune.*` block is already validated by `Get-PsadtConfig.ps1:31-37`:

- `intune.uploadEnabled` (bool)
- `intune.tenantId`
- `intune.clientId`
- `intune.secretRef` (default `secret.dpapi`)

Secret stays DPAPI-encrypted (`CurrentUser` scope) via the existing `Set-PsadtConfig.ps1 -Secret`
(`Set-PsadtConfig.ps1:39-42`), bound to the user + machine, decrypted only in-memory at upload time, never
in `config.json` or any log.

## 6. SKILL.md wiring

- **Phase 0 (setup):** replace the "planned — not active" note with an opt-in: enable upload → point the
  user to run `pwsh scripts/New-PsadtEntraApp.ps1` once (login + consent + secret captured automatically).
  Manual route via `references/app-registration.md` mentioned as fallback.
- **New Phase 7.5 "Direct Intune upload (opt-in)":** sits after the dossier (Phase 7) and feeds the
  existing Intune test-group step (Phase 8 step 9). Sequence: `Test-PsadtSetup` → human-readable summary
  (app name, version, **target tenant**, install/uninstall commands, detection) → `AskUserQuestion`
  confirm → `Invoke-IntuneWin32Upload` → print portal link. Manual dossier upload remains the documented
  alternative.

## 7. Safety model

`Test-PsadtSetup` preflight (fail fast before any write) → summary of exactly what will be created →
click-option confirm → upload → portal link. No silent writes. Idempotency "detect + ask" prevents
accidental duplicate apps or updating the wrong app.

## 8. Testing

Pester suite matching the existing `tests/` style; **all Graph/network calls mocked**:

- `New-IntuneWin32AppBody` — dossier → win32LobApp mapping (return codes, detection, Markdown description).
- `.intunewin` / `Detection.xml` parser — EncryptionInfo + sizes + SetupFile extraction.
- Idempotency branch logic — match found vs. not found → correct action.
- `Get-GraphToken` — token request shape + in-memory secret handling (mocked HTTP).
- `Test-PsadtSetup` — problem aggregation (missing config, 403 probe, token failure).

The live multi-step upload and the interactive bootstrap (`New-PsadtEntraApp.ps1`) are exercised manually
against a real tenant — documented in the test notes, not automated.

## 9. Out of scope (this feature)

- Assignment to Entra groups (deliberate human step).
- Certificate-based auth (token helper is shaped for it, not implemented now).
- Interactive/delegated auth for uploads (only the one-time bootstrap is interactive).
- Supersedence / dependency relationships between apps.
- The separate "GitHub package sync" roadmap item.

## 10. New/changed files summary

```
scripts/New-PsadtEntraApp.ps1          (new)  one-time Entra app bootstrap (device-code)
scripts/Get-GraphToken.ps1             (new)  app-only client-credentials token
scripts/Test-PsadtSetup.ps1            (new)  read-only preflight validation
scripts/New-IntuneWin32AppBody.ps1     (new)  dossier -> win32LobApp body mapper (no network)
scripts/Invoke-IntuneWin32Upload.ps1   (new)  8-step Graph upload orchestrator
references/app-registration.md         (new)  manual portal fallback guide
tests/*.Tests.ps1                      (new)  Pester for the above (Graph mocked)
SKILL.md                               (edit) Phase 0 opt-in + new Phase 7.5
README.md                              (edit) move direct upload from Roadmap to Features
config.json schema                     (none) intune.* already supported
```
