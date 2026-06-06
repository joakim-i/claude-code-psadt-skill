<#
.SYNOPSIS
    One-time bootstrap of the Entra app registration used for direct Intune upload.

.DESCRIPTION
    Runs interactively (device-code sign-in, no third-party module) against Microsoft Graph and, in a
    single pass:
      1. signs the admin in via the well-known "Microsoft Graph Command Line Tools" public client,
      2. creates the app registration "PSADT Intune Upload" + its service principal,
      3. grants the application permission DeviceManagementApps.ReadWrite.All and admin-consents it
         (the appRoleAssignment IS the consent - no separate portal click),
      4. creates a client secret (returned once),
      5. writes intune.tenantId / clientId / uploadEnabled to config.json and DPAPI-stores the secret
         via Set-PsadtConfig.ps1 - the secret is never printed and never typed by hand.

    Requirement: the signed-in user must be able to create an app AND grant admin consent - i.e.
    Global Administrator or Privileged Role Administrator. Application Administrator alone cannot perform
    the consent step; the script detects that and points to the manual fallback (references/app-registration.md).

    Runs on Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER SkillRoot
    Skill root (folder containing scripts/ and config.json). Defaults to the parent of this script.

.PARAMETER TenantId
    Optional tenant id or domain to sign in against. Default 'organizations' - the real tenant id is then
    read from the issued token and stored. Pass this if your account can access several tenants.

.PARAMETER SecretValidMonths
    Lifetime of the generated client secret, in months. Default 12.

.PARAMETER Force
    If an app named "PSADT Intune Upload" already exists, reuse it without prompting (a fresh secret is
    still created).

.OUTPUTS
    PSCustomObject: TenantId, ClientId, AppObjectId, ConsentGranted(bool), SecretExpires(datetime), ConfigPath.

.EXAMPLE
    pwsh scripts/New-PsadtEntraApp.ps1
.EXAMPLE
    powershell -File scripts/New-PsadtEntraApp.ps1 -TenantId contoso.onmicrosoft.com -SecretValidMonths 24
#>
[CmdletBinding()]
param(
    [string]$SkillRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$TenantId = 'organizations',
    [ValidateRange(1, 24)][int]$SecretValidMonths = 12,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# --- Constants ---------------------------------------------------------------------------------------
$AppDisplayName = 'PSADT Intune Upload'                       # fixed by design
$DeviceCodeClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'  # "Microsoft Graph Command Line Tools" (public)
$GraphResourceAppId = '00000003-0000-0000-c000-000000000000'  # Microsoft Graph
$RequiredAppRole = 'DeviceManagementApps.ReadWrite.All'
$Scopes = 'Application.ReadWrite.All AppRoleAssignment.ReadWrite.All offline_access openid profile'
$GraphBase = 'https://graph.microsoft.com/v1.0'

# --- Console UX helpers ------------------------------------------------------------------------------
$script:step = 0
function Write-Step([string]$msg) { $script:step++; Write-Host "`n[$script:step] $msg" -ForegroundColor Cyan }
function Write-Ok  ([string]$msg) { Write-Host "    OK  $msg" -ForegroundColor Green }
function Write-Info([string]$msg) { Write-Host "    $msg" -ForegroundColor Gray }
function Write-Warn2([string]$msg){ Write-Host "    !   $msg" -ForegroundColor Yellow }
function Write-Fail([string]$msg) { Write-Host "    X   $msg" -ForegroundColor Red }

# --- Cross-version Graph error extraction ------------------------------------------------------------
function Get-GraphError($err) {
    # PS7 puts the response body in ErrorDetails.Message; PS5.1 needs the response stream.
    $body = $null
    if ($err.ErrorDetails -and $err.ErrorDetails.Message) {
        $body = $err.ErrorDetails.Message
    } elseif ($err.Exception.Response) {
        try {
            $s = $err.Exception.Response.GetResponseStream()
            $body = (New-Object System.IO.StreamReader($s)).ReadToEnd()
        } catch { }
    }
    if ($body) {
        try { return (ConvertFrom-Json $body).error } catch { return [pscustomobject]@{ code = 'Unknown'; message = $body } }
    }
    return [pscustomobject]@{ code = 'Unknown'; message = $err.Exception.Message }
}

function Invoke-Graph {
    param([string]$Method, [string]$Uri, $Body, [hashtable]$Headers)
    $p = @{ Method = $Method; Uri = $Uri; Headers = $Headers; ErrorAction = 'Stop' }
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $p.Body = ($Body | ConvertTo-Json -Depth 10)
        $p.ContentType = 'application/json'
    }
    return Invoke-RestMethod @p
}

function ConvertFrom-JwtPayload([string]$jwt) {
    $payload = $jwt.Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
}

# --- Device-code sign-in -----------------------------------------------------------------------------
function Get-DeviceCodeToken([string]$Tenant, [string]$Scope) {
    $authority = "https://login.microsoftonline.com/$Tenant/oauth2/v2.0"
    $dc = Invoke-RestMethod -Method Post -Uri "$authority/devicecode" -Body @{
        client_id = $DeviceCodeClientId; scope = $Scope
    } -ErrorAction Stop

    Write-Host ""
    Write-Host "    To sign in, open: " -NoNewline; Write-Host $dc.verification_uri -ForegroundColor White
    Write-Host "    Enter code:       " -NoNewline; Write-Host $dc.user_code -ForegroundColor White
    Write-Host "    (waiting for you to complete sign-in and consent in the browser ...)" -ForegroundColor Gray

    $interval = [int]$dc.interval; if ($interval -lt 1) { $interval = 5 }
    $deadline = (Get-Date).AddSeconds([int]$dc.expires_in)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $interval
        try {
            return Invoke-RestMethod -Method Post -Uri "$authority/token" -Body @{
                grant_type = 'urn:ietf:params:oauth:grant-type:device_code'
                client_id  = $DeviceCodeClientId
                device_code = $dc.device_code
            } -ErrorAction Stop
        } catch {
            $e = Get-GraphError $_
            switch ($e.error) {
                'authorization_pending' { continue }
                'slow_down'             { $interval += 5; continue }
                'authorization_declined' { throw "Sign-in was declined in the browser." }
                'expired_token'         { throw "The device code expired before sign-in completed. Re-run the script." }
                default                 { if ($e.code -eq 'Unknown' -and $e.message -match 'pending') { continue }; throw $e.message }
            }
        }
    }
    throw "Timed out waiting for sign-in."
}

# --- Retry wrapper for replication lag (new SP not yet visible) --------------------------------------
function Invoke-WithRetry([scriptblock]$Action, [int]$Tries = 6, [int]$DelaySec = 5) {
    for ($i = 1; $i -le $Tries; $i++) {
        try { return & $Action }
        catch {
            $e = Get-GraphError $_
            $transient = $e.code -in 'Request_ResourceNotFound', 'ResourceNotFound', 'Authorization_RequestDenied' -and $i -lt $Tries
            if (-not $transient) { throw }
            Write-Info "  ... not replicated yet ($($e.code)), retry $i/$Tries in ${DelaySec}s"
            Start-Sleep -Seconds $DelaySec
        }
    }
}

# =====================================================================================================
Write-Host "PSADT Intune upload - Entra app bootstrap" -ForegroundColor White
Write-Host "Creates the app registration '$AppDisplayName' and configures direct upload." -ForegroundColor Gray
Write-Host "You must sign in as Global Administrator or Privileged Role Administrator." -ForegroundColor Gray

# 1. Sign in -------------------------------------------------------------------------------------------
Write-Step "Sign in (device code)"
$tok = Get-DeviceCodeToken -Tenant $TenantId -Scope $Scopes
$claims = ConvertFrom-JwtPayload $tok.access_token
$realTenant = $claims.tid
$who = if ($claims.preferred_username) { $claims.preferred_username } elseif ($claims.upn) { $claims.upn } else { '(unknown)' }
$H = @{ Authorization = "Bearer $($tok.access_token)" }
Write-Ok "Signed in as $who"
Write-Info "Tenant: $realTenant"

# 2. Resolve the Microsoft Graph SP + the app-role id --------------------------------------------------
Write-Step "Resolve Graph permission '$RequiredAppRole'"
$graphSp = (Invoke-Graph GET "$GraphBase/servicePrincipals?`$filter=appId eq '$GraphResourceAppId'" -Headers $H).value | Select-Object -First 1
if (-not $graphSp) { throw "Could not find the Microsoft Graph service principal in this tenant." }
$role = $graphSp.appRoles | Where-Object { $_.value -eq $RequiredAppRole -and $_.allowedMemberTypes -contains 'Application' } | Select-Object -First 1
if (-not $role) { throw "App role '$RequiredAppRole' not found on the Graph service principal." }
Write-Ok "Found app role id $($role.id)"

# 3. Create (or reuse) the app registration ------------------------------------------------------------
Write-Step "Create app registration '$AppDisplayName'"
$existing = (Invoke-Graph GET "$GraphBase/applications?`$filter=displayName eq '$AppDisplayName'" -Headers $H).value | Select-Object -First 1
if ($existing) {
    if (-not $Force) {
        Write-Warn2 "An app named '$AppDisplayName' already exists (appId $($existing.appId))."
        $ans = Read-Host "    Reuse it and just create a new secret? [y/N]"
        if ($ans -notmatch '^(y|yes|j|ja)$') { Write-Fail "Aborted by user."; return }
    }
    $app = $existing
    Write-Ok "Reusing existing app (objectId $($app.id))"
} else {
    $appBody = @{
        displayName = $AppDisplayName
        signInAudience = 'AzureADMyOrg'
        requiredResourceAccess = @(@{
            resourceAppId  = $GraphResourceAppId
            resourceAccess = @(@{ id = $role.id; type = 'Role' })
        })
    }
    $app = Invoke-Graph POST "$GraphBase/applications" -Body $appBody -Headers $H
    Write-Ok "Created app (objectId $($app.id), appId $($app.appId))"
}

# 4. Ensure a service principal for the app ------------------------------------------------------------
Write-Step "Ensure service principal"
$sp = (Invoke-Graph GET "$GraphBase/servicePrincipals?`$filter=appId eq '$($app.appId)'" -Headers $H).value | Select-Object -First 1
if (-not $sp) {
    $sp = Invoke-WithRetry { Invoke-Graph POST "$GraphBase/servicePrincipals" -Body @{ appId = $app.appId } -Headers $H }
    Write-Ok "Created service principal ($($sp.id))"
} else {
    Write-Ok "Service principal exists ($($sp.id))"
}

# 5. Grant the application permission + admin consent --------------------------------------------------
Write-Step "Grant '$RequiredAppRole' + admin consent"
$consentGranted = $false
$already = (Invoke-Graph GET "$GraphBase/servicePrincipals/$($sp.id)/appRoleAssignments" -Headers $H).value |
    Where-Object { $_.appRoleId -eq $role.id -and $_.resourceId -eq $graphSp.id }
if ($already) {
    $consentGranted = $true
    Write-Ok "Permission already granted."
} else {
    try {
        # Short retry: tolerate brief replication lag on the just-created SP, but surface a real
        # permission denial quickly instead of looping for half a minute.
        Invoke-WithRetry -Tries 3 -DelaySec 4 -Action {
            Invoke-Graph POST "$GraphBase/servicePrincipals/$($sp.id)/appRoleAssignments" -Headers $H -Body @{
                principalId = $sp.id; resourceId = $graphSp.id; appRoleId = $role.id
            }
        } | Out-Null
        $consentGranted = $true
        Write-Ok "Permission granted and admin-consented."
    } catch {
        $e = Get-GraphError $_
        if ($e.code -eq 'Authorization_RequestDenied') {
            Write-Fail "Your account may not grant admin consent (need Global Admin or Privileged Role Admin)."
            Write-Warn2 "The app and secret will still be created. Grant consent later in the portal:"
            Write-Info  "Entra admin center > App registrations > '$AppDisplayName' > API permissions > Grant admin consent,"
            Write-Info  "or follow references/app-registration.md."
        } else {
            throw $e.message
        }
    }
}

# 6. Create a client secret ----------------------------------------------------------------------------
Write-Step "Create client secret (valid $SecretValidMonths month(s))"
$expires = (Get-Date).AddMonths($SecretValidMonths)
$pwdResult = Invoke-Graph POST "$GraphBase/applications/$($app.id)/addPassword" -Headers $H -Body @{
    passwordCredential = @{ displayName = 'PSADT upload secret'; endDateTime = $expires.ToString('o') }
}
$secret = ConvertTo-SecureString $pwdResult.secretText -AsPlainText -Force
Write-Ok "Secret created (expires $($expires.ToString('yyyy-MM-dd'))). It is never displayed - stored encrypted."

# 7. Persist to config (DPAPI for the secret) ----------------------------------------------------------
Write-Step "Write config (config.json + DPAPI secret.dpapi)"
$setCfg = Join-Path $PSScriptRoot 'Set-PsadtConfig.ps1'
& $setCfg -SkillRoot $SkillRoot -Secret $secret -Updates @{
    'intune.tenantId'      = $realTenant
    'intune.clientId'      = $app.appId
    'intune.uploadEnabled' = $true
    'intune.secretRef'     = 'secret.dpapi'
}
Write-Ok "Saved to $(Join-Path $SkillRoot 'config.json')"

# --- Summary -----------------------------------------------------------------------------------------
Write-Host "`n----------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "Done. Direct Intune upload is configured." -ForegroundColor Green
Write-Host "  Tenant   : $realTenant"
Write-Host "  Client   : $($app.appId)   ('$AppDisplayName')"
Write-Host "  Permission: $RequiredAppRole  (consent: $(if($consentGranted){'granted'}else{'PENDING - grant in portal'}))"
Write-Host "  Secret   : stored DPAPI-encrypted, expires $($expires.ToString('yyyy-MM-dd'))"
if (-not $consentGranted) {
    Write-Host "  ACTION   : grant admin consent in the portal before the first upload." -ForegroundColor Yellow
}
Write-Host "Next: build a package; the upload step (Phase 7.5) will use this app." -ForegroundColor Gray
Write-Host "----------------------------------------------------------------`n" -ForegroundColor DarkGray

[pscustomobject]@{
    TenantId       = $realTenant
    ClientId       = $app.appId
    AppObjectId    = $app.id
    ConsentGranted = $consentGranted
    SecretExpires  = $expires
    ConfigPath     = (Join-Path $SkillRoot 'config.json')
}
