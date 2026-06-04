<#
.SYNOPSIS  Ensures tools/IntuneWinAppUtil.exe is present and current vs the official MS repo.
.OUTPUTS   PSCustomObject: Action(Downloaded|AlreadyCurrent|UpdateFailed), Version, Path
#>
[CmdletBinding()]
param([string]$SkillRoot = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
$repo = 'microsoft/Microsoft-Win32-Content-Prep-Tool'
$exe  = Join-Path $SkillRoot 'tools/IntuneWinAppUtil.exe'
$configPath = Join-Path $SkillRoot 'config.json'

$installedVersion = $null
if (Test-Path $configPath) {
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
    $installedVersion = $cfg.tooling.intuneWinAppUtilVersion
}

$latestTag = $null
try { $latestTag = (Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest").tag_name } catch { }

if ((Test-Path $exe) -and $latestTag -and $installedVersion -eq $latestTag) {
    return [pscustomobject]@{ Action='AlreadyCurrent'; Version=$latestTag; Path=$exe }
}

$tag = if ($latestTag) { $latestTag } else { 'v1.8.7' }
try {
    New-Item (Split-Path $exe -Parent) -ItemType Directory -Force | Out-Null
    Invoke-WebRequest "https://github.com/$repo/raw/$tag/IntuneWinAppUtil.exe" -OutFile $exe
    & (Join-Path $PSScriptRoot 'Set-PsadtConfig.ps1') -SkillRoot $SkillRoot -Updates @{ 'tooling.intuneWinAppUtilVersion' = $tag }
    return [pscustomobject]@{ Action='Downloaded'; Version=$tag; Path=$exe }
} catch {
    if (Test-Path $exe) { return [pscustomobject]@{ Action='AlreadyCurrent'; Version=$installedVersion; Path=$exe } }
    return [pscustomobject]@{ Action='UpdateFailed'; Version=$null; Path=$exe; Error="$_" }
}
