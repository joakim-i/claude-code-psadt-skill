# Entra app registration — manual portal fallback

The direct Intune upload (SKILL.md Phase 7.5) authenticates as an **app-only** Entra application with the
Microsoft Graph **application** permission `DeviceManagementApps.ReadWrite.All`.

**Preferred path:** run `pwsh scripts/New-PsadtEntraApp.ps1` once. It signs you in interactively via **WAM**
(the Windows Web Account Manager broker; device-code fallback), creates the app, grants + admin-consents the
permission, creates a client secret, and stores everything automatically. Use the manual steps below only
when you cannot run that script (locked-down host, policy, etc.).

You must sign in as **Global Administrator** or **Privileged Role Administrator** — granting admin consent
for an application permission requires it. Application Administrator alone cannot complete the consent step.

## 1. Create the app registration

1. [Entra admin center](https://entra.microsoft.com) → **Identity → Applications → App registrations → New registration**.
2. **Name:** `PSADT Intune Upload` (fixed by convention). **Supported account types:** *Accounts in this
   organizational directory only*. No redirect URI needed (app-only/client-credentials). **Register**.
3. From the **Overview** blade, copy the **Application (client) ID** and the **Directory (tenant) ID**.

## 2. Add the application permission + grant admin consent

1. App → **API permissions → Add a permission → Microsoft Graph → Application permissions**.
2. Search `DeviceManagementApps.ReadWrite.All`, tick it, **Add permissions**.
3. Click **Grant admin consent for &lt;tenant&gt;** and confirm. The permission row must show
   **Granted for &lt;tenant&gt;** (green check). Without this the upload's read-only probe returns `403`.

## 3. Create a client secret

1. App → **Certificates & secrets → Client secrets → New client secret**.
2. Description `PSADT upload secret`, pick an expiry (e.g. 12 months). **Add**.
3. Copy the secret **Value** immediately (shown once). Do **not** paste it into chat or any file.

## 4. Feed it into the skill config (secret DPAPI-encrypted)

Store tenant/client in `config.json` and the secret DPAPI-encrypted (`CurrentUser`) in `secret.dpapi` —
the secret is never written to `config.json` or any log, and is decrypted only in-memory at upload time:

```powershell
$secret = Read-Host -AsSecureString 'Paste the client secret value'   # typed in the terminal, never in chat
& scripts/Set-PsadtConfig.ps1 -Secret $secret -Updates @{
    'intune.tenantId'      = '<tenant-guid>'
    'intune.clientId'      = '<client-guid>'
    'intune.uploadEnabled' = $true
    'intune.secretRef'     = 'secret.dpapi'
}
```

## 5. Verify

```powershell
$tok = & scripts/Get-GraphToken.ps1
Invoke-RestMethod -Headers @{ Authorization = "Bearer $($tok.Token)" } `
  -Uri 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps?$top=1' | Out-Null
'OK - DeviceManagementApps.ReadWrite.All is effective.'
```

A `403` here means consent/permission is missing — revisit step 2. Then proceed with Phase 7.5
(`Invoke-IntuneWin32Upload.ps1`, dry-run first).

> Rotation: when the secret expires, create a new one (step 3) and re-run step 4. The app, its consent, and
> any supersedence/assignments are unaffected.
