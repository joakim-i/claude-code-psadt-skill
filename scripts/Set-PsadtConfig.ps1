<#
.SYNOPSIS
    Creates/updates config.json (deep partial merge) and, optionally, DPAPI-encrypts the client secret.

.DESCRIPTION
    Merges -Updates into the existing config.json (creating it if absent), using dotted-path keys so a single
    leaf or a whole sub-tree can be set without rewriting the file. A -Secret is DPAPI-encrypted (CurrentUser
    scope) to the secret.dpapi file and is never logged or returned. Writes config.json as UTF-8.

.PARAMETER SkillRoot
    The skill root folder that holds config.json (and secret.dpapi). Defaults to the parent of this script.

.PARAMETER Updates
    Hashtable of dotted-path -> value, e.g. @{ 'paths.packageRoot' = 'c:\p'; 'intune.groups.naming' = @{...} }.
    Intermediate nodes are created as needed; existing siblings are preserved.

.PARAMETER Secret
    SecureString client secret; DPAPI-encrypted (CurrentUser) to secret.dpapi. Never logged or returned.

.EXAMPLE
    Set-PsadtConfig.ps1 -Updates @{ 'author.person' = 'Jane Doe'; 'author.company' = 'Contoso' }
#>
[CmdletBinding()]
param(
    [string]$SkillRoot = (Split-Path $PSScriptRoot -Parent),
    [hashtable]$Updates = @{},
    [System.Security.SecureString]$Secret
)

$configPath = Join-Path $SkillRoot 'config.json'
function ConvertTo-HashtableDeep($obj) {
    if ($obj -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-HashtableDeep $p.Value }
        return $h
    }
    return $obj
}
$config = if (Test-Path $configPath) {
    try { ConvertTo-HashtableDeep (Get-Content $configPath -Raw | ConvertFrom-Json) }
    catch { throw "config.json is malformed and cannot be safely updated: $($_.Exception.Message). Fix or delete it, then re-run." }
} else { @{ version = 1 } }
if (-not $config.ContainsKey('version')) { $config['version'] = 1 }

foreach ($key in $Updates.Keys) {
    $segs = $key -split '\.'
    $node = $config
    for ($i = 0; $i -lt $segs.Count - 1; $i++) {
        if (-not ($node[$segs[$i]] -is [hashtable])) { $node[$segs[$i]] = @{} }
        $node = $node[$segs[$i]]
    }
    $node[$segs[-1]] = $Updates[$key]
}

$config | ConvertTo-Json -Depth 8 | Set-Content -Path $configPath -Encoding UTF8

if ($Secret) {
    $enc = ConvertFrom-SecureString $Secret
    Set-Content -Path (Join-Path $SkillRoot 'secret.dpapi') -Value $enc -Encoding ASCII -NoNewline
}
