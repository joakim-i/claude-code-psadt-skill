<#
.SYNOPSIS
    One-time bootstrap of the Entra app registration used for direct Intune upload.

.DESCRIPTION
    Runs interactively against Microsoft Graph and, in a single pass:
      1. signs the admin in via the well-known "Microsoft Graph Command Line Tools" public client.
         By default it uses WAM (the Windows Web Account Manager broker) so the native Windows sign-in
         window appears and SSO / a Primary Refresh Token can be reused - no code to type on a phone.
         WAM needs the MSAL.NET broker assemblies; the script auto-locates them (global NuGet cache /
         downloaded once to %LOCALAPPDATA%\PsadtIntune\msal). If WAM cannot run (non-Windows, no broker,
         MSAL unavailable) it falls back to the device-code flow. Force device code with -UseDeviceCode.
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

.PARAMETER UseDeviceCode
    Skip WAM and sign in with the device-code flow instead. Useful on machines without the Windows broker
    (e.g. some Server Core / non-interactive hosts) or to avoid the one-time MSAL download.

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
    [switch]$Force,
    [switch]$UseDeviceCode,
    # Certificate-based auth (preferred over client secret): pass the thumbprint of a cert already in
    # Cert:\CurrentUser\My. The cert's public key is uploaded to the app; no client secret is created.
    [switch]$UseCertificate,
    [string]$CertThumbprint
)

$ErrorActionPreference = 'Stop'

# Validate cert early (fail before any network calls)
$certObj = $null
if ($UseCertificate) {
    if ([string]::IsNullOrWhiteSpace($CertThumbprint)) {
        throw "-CertThumbprint is required with -UseCertificate. List available certs: Get-ChildItem Cert:\CurrentUser\My | Select Subject,Thumbprint,NotAfter"
    }
    $certObj = Get-Item "Cert:\CurrentUser\My\$CertThumbprint" -ErrorAction SilentlyContinue
    if (-not $certObj) { throw "Certificate not found: Cert:\CurrentUser\My\$CertThumbprint" }
    if ($certObj.NotAfter -lt (Get-Date)) { throw "Certificate has expired ($($certObj.NotAfter.ToString('yyyy-MM-dd'))). Create a new cert." }
    if (-not $certObj.HasPrivateKey) { throw "Certificate Cert:\CurrentUser\My\$CertThumbprint has no private key - cannot sign client assertions." }
}

# --- Constants ---------------------------------------------------------------------------------------
$AppDisplayName = 'PSADT Intune Upload'                       # fixed by design
$DeviceCodeClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'  # "Microsoft Graph Command Line Tools" (public)
$GraphResourceAppId = '00000003-0000-0000-c000-000000000000'  # Microsoft Graph
$RequiredAppRole = 'DeviceManagementApps.ReadWrite.All'
$Scopes = 'Application.ReadWrite.All AppRoleAssignment.ReadWrite.All offline_access openid profile'
$GraphBase = 'https://graph.microsoft.com/v1.0'

# WAM (Windows broker) is the preferred interactive sign-in; device code is the fallback.
# offline_access must be included explicitly - MSAL does NOT add OIDC scopes automatically for WAM.
$WamScopes = @(
    'https://graph.microsoft.com/Application.ReadWrite.All'
    'https://graph.microsoft.com/AppRoleAssignment.ReadWrite.All'
    'offline_access'
)
# Pinned, known-good MSAL.NET broker package set (auto-located or downloaded once).
# Abstractions is a transitive dependency of the client and must be loaded alongside it.
$MsalVersions = @{ Client = '4.66.2'; Broker = '4.66.2'; Native = '0.16.2'; Abstractions = '6.35.0' }
$MsalCacheRoot = Join-Path $env:LOCALAPPDATA 'PsadtIntune\msal'

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
            # OAuth token endpoint errors return { "error": "<string>", "error_description": "..." }
            # so Get-GraphError returns the string directly (not a .code/.message object).
            $e = Get-GraphError $_
            $eCode = if ($e -is [string]) { $e } else { [string]$e.error }
            switch ($eCode) {
                'authorization_pending'  { continue }
                'slow_down'              { $interval += 5; continue }
                'authorization_declined' { throw "Sign-in was declined in the browser." }
                'expired_token'          { throw "The device code expired before sign-in completed. Re-run the script." }
                default                  { if ($eCode -match 'pending') { continue }; throw ($e | Out-String) }
            }
        }
    }
    throw "Timed out waiting for sign-in."
}

# --- WAM (Windows broker) sign-in via MSAL.NET -------------------------------------------------------
# Acquire the MSAL broker assemblies: prefer the global NuGet cache, otherwise download the pinned
# .nupkg once from nuget.org and extract it into the local cache. A .nupkg is just a zip.
function Save-NuGetPackage {
    param([string]$Id, [string]$Version, [string]$DestDir)
    $idl = $Id.ToLower(); $verl = $Version.ToLower()
    $url = "https://api.nuget.org/v3-flatcontainer/$idl/$verl/$idl.$verl.nupkg"
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "$idl.$verl.nupkg"
    Write-Info "downloading $Id $Version ..."
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $DestDir) { Remove-Item $DestDir -Recurse -Force }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($tmp, $DestDir)
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

function Get-PackageDir {
    param([string]$Id, [string]$Version, [string]$LocalRoot)
    $global = Join-Path $env:USERPROFILE ".nuget\packages\$Id\$Version"
    if (Test-Path $global) { return $global }
    $local = Join-Path $LocalRoot "$Id\$Version"
    if ((Test-Path $local) -and (Get-ChildItem $local -ErrorAction SilentlyContinue)) { return $local }
    Save-NuGetPackage -Id $Id -Version $Version -DestDir $local
    return $local
}

$script:MsalReady = $false
function Initialize-MsalBroker {
    param([hashtable]$Versions, [string]$CacheRoot)
    if ($script:MsalReady) { return $true }
    if (-not [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        throw "WAM is only available on Windows."
    }
    $isCore = $PSVersionTable.PSEdition -eq 'Core'
    $clientTfm = if ($isCore) { 'net6.0' }        else { 'net462' }
    $brokerTfm = if ($isCore) { 'netstandard2.0' } else { 'net462' }
    $nativeTfm = if ($isCore) { 'netstandard2.0' } else { 'net461' }
    $arch = switch ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture) {
        'Arm64' { 'win-arm64' } 'X86' { 'win-x86' } default { 'win-x64' }
    }

    # Reuse a 4.66.x client already in the global cache (avoids a download) before falling back to pinned.
    $clientVer = $Versions.Client
    $cb = Join-Path $env:USERPROFILE ".nuget\packages\microsoft.identity.client"
    if (-not (Test-Path (Join-Path $cb $clientVer)) -and (Test-Path $cb)) {
        $newer = Get-ChildItem $cb -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '4.66.*' -and (Test-Path (Join-Path $_.FullName "lib\$clientTfm\Microsoft.Identity.Client.dll")) } |
            Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
        if ($newer) { $clientVer = $newer.Name }
    }

    $abstrDll  = Join-Path (Get-PackageDir 'microsoft.identitymodel.abstractions'    $Versions.Abstractions $CacheRoot) "lib\$clientTfm\Microsoft.IdentityModel.Abstractions.dll"
    $clientDll = Join-Path (Get-PackageDir 'microsoft.identity.client'              $clientVer        $CacheRoot) "lib\$clientTfm\Microsoft.Identity.Client.dll"
    $brokerDll = Join-Path (Get-PackageDir 'microsoft.identity.client.broker'       $Versions.Broker  $CacheRoot) "lib\$brokerTfm\Microsoft.Identity.Client.Broker.dll"
    $nativePkg =           (Get-PackageDir 'microsoft.identity.client.nativeinterop' $Versions.Native  $CacheRoot)
    $nativeMgr = Join-Path $nativePkg "lib\$nativeTfm\Microsoft.Identity.Client.NativeInterop.dll"
    $nativeRun = Join-Path $nativePkg "runtimes\$arch\native"

    foreach ($f in @($abstrDll, $clientDll, $brokerDll, $nativeMgr)) {
        if (-not (Test-Path $f)) { throw "MSAL assembly not found: $f" }
    }
    if (-not (Test-Path $nativeRun)) { throw "MSAL native runtime folder not found: $nativeRun" }

    # Stage the native broker dll into a private folder on PATH (never mutate the shared NuGet cache).
    $runDir = Join-Path $CacheRoot "native\$arch"
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    Get-ChildItem $nativeRun -Filter 'msalruntime*.dll' | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $runDir $_.Name) -Force
    }
    if (-not (Test-Path (Join-Path $runDir 'msalruntime.dll'))) {
        $alt = Get-ChildItem $runDir -Filter 'msalruntime*.dll' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($alt) { Copy-Item $alt.FullName (Join-Path $runDir 'msalruntime.dll') -Force }
    }
    if ($env:PATH -notlike "*$runDir*") { $env:PATH = "$runDir;$env:PATH" }

    [System.Reflection.Assembly]::LoadFrom($abstrDll)  | Out-Null
    [System.Reflection.Assembly]::LoadFrom($clientDll) | Out-Null
    [System.Reflection.Assembly]::LoadFrom($nativeMgr) | Out-Null
    [System.Reflection.Assembly]::LoadFrom($brokerDll) | Out-Null

    if (-not ([System.Management.Automation.PSTypeName]'PsadtNative.Win').Type) {
        Add-Type -Namespace PsadtNative -Name Win -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")]   public static extern System.IntPtr GetForegroundWindow();
'@
    }

    $script:MsalReady = $true
    return $true
}

function Get-WamToken {
    param([string]$Tenant, [string[]]$GraphScopes, [string]$ClientId)
    $authority = "https://login.microsoftonline.com/$Tenant"
    $builder = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($ClientId).WithAuthority($authority)
    $bo = New-Object 'Microsoft.Identity.Client.BrokerOptions' -ArgumentList ([Microsoft.Identity.Client.BrokerOptions+OperatingSystems]::Windows)
    $builder = [Microsoft.Identity.Client.Broker.BrokerExtension]::WithBroker($builder, $bo)
    $pca = $builder.Build()

    $hwnd = [PsadtNative.Win]::GetConsoleWindow()
    if ($hwnd -eq [System.IntPtr]::Zero) { $hwnd = [PsadtNative.Win]::GetForegroundWindow() }

    Write-Host "    A Windows sign-in window (Web Account Manager) will open ..." -ForegroundColor Gray
    $req = $pca.AcquireTokenInteractive([string[]]$GraphScopes)
    $req = $req.WithParentActivityOrWindow($hwnd)
    $req = $req.WithPrompt([Microsoft.Identity.Client.Prompt]::SelectAccount)
    $result = $req.ExecuteAsync().GetAwaiter().GetResult()

    # Shape the result like the device-code token so downstream code is unchanged.
    return [pscustomobject]@{ access_token = $result.AccessToken }
}

# Pick WAM, fall back to device code. Returns an object exposing .access_token (a Graph JWT).
function Get-AdminToken {
    if (-not $UseDeviceCode) {
        try {
            Initialize-MsalBroker -Versions $MsalVersions -CacheRoot $MsalCacheRoot | Out-Null
            Write-Info "Sign-in method: WAM (Windows Web Account Manager)."
            return Get-WamToken -Tenant $TenantId -GraphScopes $WamScopes -ClientId $DeviceCodeClientId
        } catch {
            Write-Warn2 "WAM sign-in unavailable: $($_.Exception.Message)"
            Write-Info  "Falling back to device-code sign-in."
        }
    }
    Write-Info "Sign-in method: device code."
    return Get-DeviceCodeToken -Tenant $TenantId -Scope $Scopes
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
Write-Step "Sign in"
$tok = Get-AdminToken
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

# 3b. Upload certificate public key (if -UseCertificate) -----------------------------------------------
if ($UseCertificate) {
    Write-Info "Uploading certificate credential (thumbprint $CertThumbprint)..."
    Invoke-WithRetry { Invoke-Graph PATCH "$GraphBase/applications/$($app.id)" -Headers $H -Body @{
        keyCredentials = @(@{
            type        = 'AsymmetricX509Cert'
            usage       = 'Verify'
            key         = [Convert]::ToBase64String($certObj.GetRawCertData())
            displayName = 'PSADT Intune Automation'
        })
    } } | Out-Null
    Write-Ok "Certificate uploaded (expires $($certObj.NotAfter.ToString('yyyy-MM-dd')))."
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

# 6. Credential: certificate (preferred) or client secret ----------------------------------------------
$secret = $null
$credExpires = $null
if ($UseCertificate) {
    Write-Step "Credential: certificate (uploaded in step 3b - no client secret created)"
    $credExpires = $certObj.NotAfter
    Write-Ok "Auth will use certificate $CertThumbprint (expires $($credExpires.ToString('yyyy-MM-dd')))."
} else {
    Write-Step "Create client secret (valid $SecretValidMonths month(s))"
    $credExpires = (Get-Date).AddMonths($SecretValidMonths)
    $pwdResult = Invoke-Graph POST "$GraphBase/applications/$($app.id)/addPassword" -Headers $H -Body @{
        passwordCredential = @{ displayName = 'PSADT upload secret'; endDateTime = $credExpires.ToString('o') }
    }
    $secret = ConvertTo-SecureString $pwdResult.secretText -AsPlainText -Force
    Write-Ok "Secret created (expires $($credExpires.ToString('yyyy-MM-dd'))). It is never displayed - stored encrypted."
}

# 7. Persist to config ---------------------------------------------------------------------------------
$setCfg = Join-Path $PSScriptRoot 'Set-PsadtConfig.ps1'
$cfgUpdates = @{
    'intune.tenantId'      = $realTenant
    'intune.clientId'      = $app.appId
    'intune.uploadEnabled' = $true
}
if ($UseCertificate) {
    Write-Step "Write config (config.json - thumbprint stored, no secret file)"
    $cfgUpdates['intune.certThumbprint'] = $CertThumbprint
    & $setCfg -SkillRoot $SkillRoot -Updates $cfgUpdates
} else {
    Write-Step "Write config (config.json + DPAPI secret.dpapi)"
    $cfgUpdates['intune.secretRef'] = 'secret.dpapi'
    & $setCfg -SkillRoot $SkillRoot -Secret $secret -Updates $cfgUpdates
}
Write-Ok "Saved to $(Join-Path $SkillRoot 'config.json')"

# --- Summary -----------------------------------------------------------------------------------------
Write-Host "`n----------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "Done. Direct Intune upload is configured." -ForegroundColor Green
Write-Host "  Tenant    : $realTenant"
Write-Host "  Client    : $($app.appId)   ('$AppDisplayName')"
Write-Host "  Permission: $RequiredAppRole  (consent: $(if($consentGranted){'granted'}else{'PENDING - grant in portal'}))"
if ($UseCertificate) {
    Write-Host "  Auth      : certificate ($CertThumbprint), expires $($credExpires.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
} else {
    Write-Host "  Auth      : client secret, DPAPI-encrypted, expires $($credExpires.ToString('yyyy-MM-dd'))"
}
if (-not $consentGranted) {
    Write-Host "  ACTION    : grant admin consent in the portal before the first upload." -ForegroundColor Yellow
}
Write-Host "Next: build a package; the upload step (Phase 7.5) will use this app." -ForegroundColor Gray
Write-Host "----------------------------------------------------------------`n" -ForegroundColor DarkGray

[pscustomobject]@{
    TenantId       = $realTenant
    ClientId       = $app.appId
    AppObjectId    = $app.id
    ConsentGranted = $consentGranted
    AuthMethod     = if ($UseCertificate) { 'Certificate' } else { 'ClientSecret' }
    CredExpires    = $credExpires
    ConfigPath     = (Join-Path $SkillRoot 'config.json')
}
