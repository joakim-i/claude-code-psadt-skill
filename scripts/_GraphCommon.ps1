<#
.SYNOPSIS
    Shared Microsoft Graph helpers for the PSADT Intune skill (console UX, cross-version error/status
    extraction, and a resilient REST wrapper). Dot-source this; it defines functions only.

.DESCRIPTION
    Previously Invoke-Graph / Get-GraphErr / the Write-* console helpers were copy-pasted into
    Invoke-IntuneWin32Upload.ps1, Invoke-IntuneAppAssignment.ps1 and New-PsadtEntraApp.ps1. That drift let
    a retry-guard bug live in only one copy. Centralising them keeps the request/retry/error logic in ONE
    place. Windows PowerShell 5.1 and PowerShell 7 compatible.

    Dot-source from a script's directory:
        . (Join-Path $PSScriptRoot '_GraphCommon.ps1')

    The Write-Step counter uses $script:step in the DOT-SOURCING script's scope; that script should set
    `$script:step = 0` once before its first Write-Step.

.NOTES
    Part of the psadt-deploy skill. No side effects on import beyond defining functions.
#>

# --- Console UX -------------------------------------------------------------------------------------
function Write-Step([string]$m) { if ($null -eq $script:step) { $script:step = 0 }; $script:step++; Write-Host "`n[$script:step] $m" -ForegroundColor Cyan }
function Write-Ok   ([string]$m) { Write-Host "    OK  $m" -ForegroundColor Green }
function Write-Info ([string]$m) { Write-Host "    $m" -ForegroundColor Gray }
function Write-Warn2([string]$m) { Write-Host "    !   $m" -ForegroundColor Yellow }
function Write-Fail ([string]$m) { Write-Host "    X   $m" -ForegroundColor Red }

# --- Cross-version HTTP status extraction ----------------------------------------------------------
function Get-GraphStatusCode($err) {
    # Returns the integer HTTP status of a failed Invoke-RestMethod, or $null if unavailable.
    # PS5.1 throws WebException (.Response = HttpWebResponse); PS7 throws HttpResponseException
    # (.Response = HttpResponseMessage). On both, .StatusCode is a [System.Net.HttpStatusCode] enum,
    # so [int] on it is safe - but .Response can be $null (e.g. a raw HttpRequestException on PS7).
    try {
        $resp = $err.Exception.Response
        if ($null -eq $resp) { return $null }
        $sc = $resp.StatusCode
        if ($null -eq $sc) { return $null }
        return [int]$sc
    } catch { return $null }
}

# --- Cross-version Retry-After extraction (seconds) ------------------------------------------------
function Get-GraphRetryAfterSeconds($err) {
    # Returns the server's Retry-After hint in whole seconds, or 0 if absent/unparseable.
    # PS7: HttpResponseMessage.Headers.RetryAfter is a strongly-typed RetryConditionHeaderValue.
    # PS5.1: WebHeaderCollection indexer returns the raw string. Casting [int]$Headers['Retry-After']
    # (the old code) THROWS on PS7 because the indexer yields IEnumerable<string> - so throttling
    # silently fell back to backoff. Handle both shapes explicitly.
    try {
        $resp = $err.Exception.Response
        if ($null -eq $resp) { return 0 }
        # PS7 strongly-typed path
        $ra = $null
        try { $ra = $resp.Headers.RetryAfter } catch { $ra = $null }
        if ($ra) {
            if ($ra.Delta -and $ra.Delta.TotalSeconds -ge 1) { return [int]$ra.Delta.TotalSeconds }
            if ($ra.Date) {
                $d = ($ra.Date.UtcDateTime - [DateTime]::UtcNow).TotalSeconds
                if ($d -ge 1) { return [int]$d }
            }
        }
        # PS5.1 / string path
        $raw = $null
        try { $raw = [string]$resp.Headers['Retry-After'] } catch { $raw = $null }
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $n = 0
            if ([int]::TryParse($raw.Trim(), [ref]$n) -and $n -ge 1) { return $n }
        }
    } catch { }
    return 0
}

# --- Cross-version Graph error body extraction -----------------------------------------------------
function Get-GraphErr($err) {
    # PS7 puts the response body in ErrorDetails.Message; PS5.1 needs the response stream.
    $body = $null
    if ($err.ErrorDetails -and $err.ErrorDetails.Message) {
        $body = $err.ErrorDetails.Message
    }
    elseif ($err.Exception.Response) {
        try {
            $resp = $err.Exception.Response
            if ($resp -is [System.Net.HttpWebResponse]) {
                $s = $resp.GetResponseStream()
                $body = (New-Object System.IO.StreamReader($s)).ReadToEnd()
            }
        } catch { }
    }
    if ($body) {
        try { return (ConvertFrom-Json $body).error } catch { return [pscustomobject]@{ code = 'Unknown'; message = $body } }
    }
    return [pscustomobject]@{ code = 'Unknown'; message = $err.Exception.Message }
}

# --- Resilient Graph REST wrapper ------------------------------------------------------------------
function Invoke-Graph {
    # Sends one Graph request and returns the parsed object. Retries ONLY transient failures (HTTP 429 +
    # 5xx), honouring Retry-After, up to 4 attempts. The request (method/uri/body) is never mutated.
    param(
        [string]$Method,
        [string]$Uri,
        $Body,
        [hashtable]$Headers,
        [int]$Depth = 20
    )
    $p = @{ Method = $Method; Uri = $Uri; Headers = $Headers; ErrorAction = 'Stop' }
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $p.Body = ($Body | ConvertTo-Json -Depth $Depth)
        $p.ContentType = 'application/json'
    }
    for ($attempt = 1; ; $attempt++) {
        try { return Invoke-RestMethod @p }
        catch {
            $status = Get-GraphStatusCode $_
            if ($attempt -ge 4 -or -not (($status -eq 429) -or ($null -ne $status -and $status -ge 500 -and $status -le 599))) { throw }
            $retryAfter = Get-GraphRetryAfterSeconds $_
            $wait = if ($retryAfter -gt 0) { $retryAfter } else { [int][Math]::Min(30, [Math]::Pow(2, $attempt)) }
            Write-Info "Graph $status - transient, retrying in ${wait}s (attempt $attempt)..."
            Start-Sleep -Seconds $wait
        }
    }
}
