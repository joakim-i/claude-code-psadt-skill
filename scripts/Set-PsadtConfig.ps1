<#
.SYNOPSIS  Creates/updates config.json (partial merge) and DPAPI-encrypts the client secret.
.PARAMETER Updates  Hashtable of dotted-path -> value (e.g. @{ 'paths.packageRoot'='c:\p' }).
.PARAMETER Secret   SecureString; DPAPI-encrypted (CurrentUser) to secret.dpapi. Never logged/returned.
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
