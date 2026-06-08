<#
.SYNOPSIS
    Checks GitHub for a newer version of this skill and (optionally) updates the local copy in place.

.DESCRIPTION
    Compares the local skill version (top entry in CHANGELOG.md) against the same file on the GitHub default
    branch. With -Check (default) it only reports; with -Apply it updates the tracked skill files:
      - if the skill folder is a git clone (.git present) -> `git pull --ff-only`
      - otherwise -> downloads the branch zip and overwrites the tracked files
        (SKILL.md, README.md, CHANGELOG.md, LICENSE, references/, scripts/, tests/)
    Machine-local state is NEVER touched: config.json, secret.dpapi, tools/, docs/ are left exactly as-is.

    The agent flow: run -Check, show LocalVersion/RemoteVersion + WhatsNew, ask the user via AskUserQuestion,
    then run -Apply only on confirmation.

.PARAMETER SkillRoot  Skill root (folder with SKILL.md/CHANGELOG.md). Defaults to the parent of this script.
.PARAMETER Repo       GitHub owner/repo. Default 'pt1987/claude-code-psadt-skill'.
.PARAMETER Branch     Branch to track. Default 'main'.
.PARAMETER Apply      Perform the update. Without it the script only checks (read-only).

.OUTPUTS
    PSCustomObject: LocalVersion, RemoteVersion, UpdateAvailable(bool), Method('git'|'archive'),
                    Applied(bool), WhatsNew(string), Action, Error
#>
[CmdletBinding()]
param(
    [string]$SkillRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$Repo = 'pt1987/claude-code-psadt-skill',
    [string]$Branch = 'main',
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'

# Tracked content that an update may overwrite. Everything else (config.json, secret.dpapi, tools/, docs/,
# .git) is machine-local / gitignored and is deliberately preserved.
$TrackedItems = @('SKILL.md', 'README.md', 'CHANGELOG.md', 'LICENSE', 'references', 'scripts', 'tests')

function Get-TopChangelogVersion([string]$text) {
    foreach ($line in ($text -split "`n")) {
        if ($line -match '^\s*##\s+(\d+\.\d+\.\d+)') { return $Matches[1] }
    }
    return $null
}
function Get-TopChangelogSection([string]$text) {
    $lines = $text -split "`n"; $out = @(); $started = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*##\s+\d+\.\d+\.\d+') { if ($started) { break }; $started = $true }
        if ($started) { $out += $line }
    }
    return ($out -join "`n").Trim()
}

# --- Local version ---------------------------------------------------------------------------------
$localChangelog = Join-Path $SkillRoot 'CHANGELOG.md'
if (-not (Test-Path $localChangelog)) { throw "CHANGELOG.md not found under $SkillRoot - is this the skill folder?" }
$localVersion = Get-TopChangelogVersion (Get-Content $localChangelog -Raw)

# --- Remote version (raw CHANGELOG on the branch) --------------------------------------------------
$remoteVersion = $null; $whatsNew = $null; $checkError = $null
try {
    $rawUrl = "https://raw.githubusercontent.com/$Repo/$Branch/CHANGELOG.md"
    $remoteText = Invoke-RestMethod -Uri $rawUrl -Headers @{ 'Cache-Control' = 'no-cache' } -ErrorAction Stop
    $remoteVersion = Get-TopChangelogVersion $remoteText
    $whatsNew = Get-TopChangelogSection $remoteText
} catch { $checkError = "Could not reach GitHub: $($_.Exception.Message)" }

$updateAvailable = $false
if ($localVersion -and $remoteVersion) {
    try { $updateAvailable = [version]$remoteVersion -gt [version]$localVersion } catch { $updateAvailable = $remoteVersion -ne $localVersion }
}
$method = if (Test-Path (Join-Path $SkillRoot '.git')) { 'git' } else { 'archive' }

$result = [ordered]@{
    LocalVersion = $localVersion; RemoteVersion = $remoteVersion; UpdateAvailable = $updateAvailable
    Method = $method; Applied = $false; WhatsNew = $whatsNew; Action = 'Checked'; Error = $checkError
}

if (-not $Apply -or -not $updateAvailable) {
    if ($checkError) { $result.Action = 'CheckFailed' }
    elseif (-not $updateAvailable) { $result.Action = 'UpToDate' }
    return [pscustomobject]$result
}

# --- Apply -----------------------------------------------------------------------------------------
try {
    if ($method -eq 'git') {
        $git = (Get-Command git -ErrorAction SilentlyContinue)
        if (-not $git) { throw "git not found on PATH; cannot pull. Re-run without a .git folder for the archive method." }
        & git -C $SkillRoot fetch --quiet origin $Branch
        $pull = & git -C $SkillRoot pull --ff-only origin $Branch 2>&1
        $result.Action = "git pull --ff-only: $($pull -join ' ')"
    } else {
        $zipUrl = "https://github.com/$Repo/archive/refs/heads/$Branch.zip"
        $tmpZip = Join-Path ([IO.Path]::GetTempPath()) "psadt-skill-$Branch.zip"
        $tmpDir = Join-Path ([IO.Path]::GetTempPath()) "psadt-skill-extract"
        Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip -UseBasicParsing
        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
        Expand-Archive $tmpZip -DestinationPath $tmpDir -Force
        $extracted = Get-ChildItem $tmpDir -Directory | Select-Object -First 1   # <repo>-<branch>/
        if (-not $extracted) { throw "Downloaded archive had no content folder." }
        foreach ($item in $TrackedItems) {
            $src = Join-Path $extracted.FullName $item
            if (-not (Test-Path $src)) { continue }
            $dst = Join-Path $SkillRoot $item
            if ((Get-Item $src) -is [IO.DirectoryInfo]) {
                Copy-Item $src $SkillRoot -Recurse -Force          # overwrite into existing dir
            } else {
                Copy-Item $src $dst -Force
            }
        }
        Remove-Item $tmpZip, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        $result.Action = "archive: overwrote tracked files from $Branch.zip (config/secret/tools preserved)"
    }
    # Re-read local version after update
    $result.LocalVersion = Get-TopChangelogVersion (Get-Content $localChangelog -Raw)
    $result.Applied = $true
} catch {
    $result.Action = 'UpdateFailed'; $result.Error = "$_"
}
[pscustomobject]$result
