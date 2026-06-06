<#
.SYNOPSIS  Reads the PSADT skill config and reports any missing required fields.
.OUTPUTS   PSCustomObject: Exists(bool), Config(object|null), Missing(string[]), Path(string)
#>
[CmdletBinding()]
param([string]$SkillRoot = (Split-Path $PSScriptRoot -Parent))

$configPath = Join-Path $SkillRoot 'config.json'
$required = @(
    'paths.packageRoot','paths.outputRoot','paths.intuneWinAppUtil',
    'language.script','language.dossier','author.person','author.company'
)
function Get-ByPath($obj, [string]$path) {
    $cur = $obj
    foreach ($seg in ($path -split '\.')) {
        if ($null -eq $cur) { return $null }
        $cur = $cur.$seg
    }
    return $cur
}

if (-not (Test-Path $configPath)) {
    return [pscustomobject]@{ Exists = $false; Config = $null; Missing = $required; Path = $configPath }
}

$cfg = Get-Content $configPath -Raw | ConvertFrom-Json
$missing = [System.Collections.Generic.List[string]]::new()
foreach ($key in $required) {
    if ([string]::IsNullOrWhiteSpace([string](Get-ByPath $cfg $key))) { $missing.Add($key) }
}
if ($cfg.intune -and $cfg.intune.uploadEnabled) {
    foreach ($f in 'tenantId','clientId') {
        if ([string]::IsNullOrWhiteSpace([string]$cfg.intune.$f)) { $missing.Add("intune.$f") }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$cfg.intune.certThumbprint)) {
        if (-not (Test-Path "Cert:\CurrentUser\My\$($cfg.intune.certThumbprint)")) {
            $missing.Add("intune.certThumbprint (cert not found in Cert:\CurrentUser\My)")
        }
    } else {
        $ref = if ($cfg.intune.secretRef) { $cfg.intune.secretRef } else { 'secret.dpapi' }
        if (-not (Test-Path (Join-Path $SkillRoot $ref))) { $missing.Add('intune.secret') }
    }
}
[pscustomobject]@{ Exists = $true; Config = $cfg; Missing = $missing.ToArray(); Path = $configPath }
