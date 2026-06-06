<#
.SYNOPSIS
    Acquires an app-only (client-credentials) Microsoft Graph token for the configured tenant/client.

.DESCRIPTION
    Reads intune.tenantId / intune.clientId from config.json and decrypts the DPAPI-stored client secret
    (intune.secretRef, default secret.dpapi) IN-MEMORY ONLY - the plaintext is never written back, never
    logged, and is zeroed from unmanaged memory immediately after the token request. Returns
    { Token, ExpiresOn, TenantId, ClientId }.

    Shaped so a certificate thumbprint can be added later without changing call sites (secret-only for now).

.PARAMETER SkillRoot
    Skill root (folder with config.json). Defaults to the parent of this script.

.OUTPUTS
    PSCustomObject: Token(string), ExpiresOn(datetime), TenantId(string), ClientId(string)
#>
[CmdletBinding()]
param([string]$SkillRoot = (Split-Path $PSScriptRoot -Parent))

$ErrorActionPreference = 'Stop'

$cfg = (& (Join-Path $PSScriptRoot 'Get-PsadtConfig.ps1') -SkillRoot $SkillRoot).Config
if (-not $cfg.intune) { throw "config.json has no 'intune' block - run New-PsadtEntraApp.ps1 first." }
$tenantId = $cfg.intune.tenantId
$clientId = $cfg.intune.clientId
$secretRef = if ($cfg.intune.secretRef) { $cfg.intune.secretRef } else { 'secret.dpapi' }
if ([string]::IsNullOrWhiteSpace($tenantId) -or [string]::IsNullOrWhiteSpace($clientId)) {
    throw "intune.tenantId / intune.clientId missing in config.json."
}
$secretPath = Join-Path $SkillRoot $secretRef
if (-not (Test-Path $secretPath)) { throw "Encrypted secret not found: $secretPath (run New-PsadtEntraApp.ps1)." }

# DPAPI -> SecureString -> plaintext, in-memory only.
$secure = ConvertTo-SecureString (Get-Content $secretPath -Raw)
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    $resp = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body @{
        client_id     = $clientId
        scope         = 'https://graph.microsoft.com/.default'
        grant_type    = 'client_credentials'
        client_secret = $plain
    } -ErrorAction Stop
} finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    $plain = $null
}

[pscustomobject]@{
    Token     = $resp.access_token
    ExpiresOn = (Get-Date).AddSeconds([int]$resp.expires_in)
    TenantId  = $tenantId
    ClientId  = $clientId
}
