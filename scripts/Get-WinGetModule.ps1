<#
.SYNOPSIS  Ensures tools/PSAppDeployToolkit.WinGet is present and current vs the GitHub release.
.PARAMETER PackagePath  Optional. Copies the module into <PackagePath>\PSAppDeployToolkit.WinGet\ after download.
.OUTPUTS   PSCustomObject: Action(Downloaded|Updated|AlreadyCurrent|UpdateFailed), Version, Path
#>
[CmdletBinding()]
param(
    [string]$SkillRoot   = (Split-Path $PSScriptRoot -Parent),
    [string]$PackagePath
)
$ErrorActionPreference = 'Stop'
$repo         = 'mjr4077au/PSAppDeployToolkit.WinGet'
$assetName    = 'PSAppDeployToolkit.WinGet.zip'
$fallbackTag  = 'v1.0.5'
$fallbackUrl  = "https://github.com/$repo/releases/download/$fallbackTag/$assetName"
$moduleDest   = Join-Path $SkillRoot 'tools/PSAppDeployToolkit.WinGet'
$manifestPath = Join-Path $moduleDest 'PSAppDeployToolkit.WinGet.psd1'
$configPath   = Join-Path $SkillRoot 'config.json'

$installedTag = $null
if (Test-Path $configPath) {
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
    $installedTag = $cfg.tooling.winGetModuleVersion
}

$latestTag = $null
try { $latestTag = (Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest").tag_name } catch { }

$outPath = if ($PackagePath) { Join-Path $PackagePath 'PSAppDeployToolkit.WinGet' } else { $moduleDest }

function Copy-ToPackage {
    if (-not $PackagePath) { return }
    Remove-Item $outPath -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item $moduleDest $outPath -Recurse -Force
}

if ((Test-Path $manifestPath) -and $latestTag -and ($installedTag -eq $latestTag)) {
    Copy-ToPackage
    return [pscustomobject]@{ Action = 'AlreadyCurrent'; Version = $latestTag; Path = $outPath }
}

if (-not $latestTag -and (Test-Path $manifestPath)) {
    Copy-ToPackage
    return [pscustomobject]@{ Action = 'AlreadyCurrent'; Version = $installedTag; Path = $outPath }
}

$tag = if ($latestTag) { $latestTag } else { $fallbackTag }
try {
    $downloadUrl = if ($latestTag) {
        $rel   = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
        $asset = $rel.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
        if (-not $asset) { throw "Release asset '$assetName' not found in release $tag." }
        $asset.browser_download_url
    } else {
        $fallbackUrl
    }

    $tmpZip = Join-Path $env:TEMP "PSADTWinGet-$tag.zip"
    $tmpDir = Join-Path $env:TEMP 'PSADTWinGet-extract'
    Invoke-WebRequest $downloadUrl -OutFile $tmpZip -UseBasicParsing

    $zipBytes = [System.IO.File]::ReadAllBytes($tmpZip)
    if ($zipBytes[0] -ne 0x50 -or $zipBytes[1] -ne 0x4B) { throw "Downloaded file is not a valid ZIP (missing PK header)." }

    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive $tmpZip -DestinationPath $tmpDir -Force

    $src = Join-Path $tmpDir 'PSAppDeployToolkit.WinGet'
    if (-not (Test-Path $src)) { throw "Expected folder 'PSAppDeployToolkit.WinGet' not found inside $assetName." }

    # SUPPLY-CHAIN NOTE: this is a third-party community module (mjr4077au/PSAppDeployToolkit.WinGet) that gets
    # packed into the .intunewin and EXECUTES on managed devices. We surface its Authenticode trust state so a
    # tampered/unsigned drop is visible (non-fatal - the PSADT WinGet module is normally signed by its author).
    $sig = Get-AuthenticodeSignature (Join-Path $src 'PSAppDeployToolkit.WinGet.psm1') -ErrorAction SilentlyContinue
    if ($sig -and $sig.Status -eq 'Valid') {
        Write-Verbose "WinGet module Authenticode signature: Valid ($($sig.SignerCertificate.Subject))."
    } else {
        Write-Warning "PSAppDeployToolkit.WinGet is NOT Authenticode-Valid (Status: $($sig.Status)). It is a third-party module that runs on devices - verify the source/release before deploying."
    }

    Remove-Item $moduleDest -Recurse -Force -ErrorAction SilentlyContinue
    New-Item (Split-Path $moduleDest -Parent) -ItemType Directory -Force | Out-Null
    Copy-Item $src $moduleDest -Recurse -Force
    Remove-Item $tmpZip, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

    & (Join-Path $PSScriptRoot 'Set-PsadtConfig.ps1') -SkillRoot $SkillRoot -Updates @{ 'tooling.winGetModuleVersion' = $tag }

    Copy-ToPackage
    $action = if ($installedTag) { 'Updated' } else { 'Downloaded' }
    return [pscustomobject]@{ Action = $action; Version = $tag; Path = $outPath }
}
catch {
    Remove-Item (Join-Path $env:TEMP "PSADTWinGet-$tag.zip") -Force -ErrorAction SilentlyContinue
    if (Test-Path $manifestPath) {
        Copy-ToPackage
        return [pscustomobject]@{ Action = 'AlreadyCurrent'; Version = $installedTag; Path = $outPath }
    }
    return [pscustomobject]@{ Action = 'UpdateFailed'; Version = $null; Path = $moduleDest; Error = "$_" }
}
