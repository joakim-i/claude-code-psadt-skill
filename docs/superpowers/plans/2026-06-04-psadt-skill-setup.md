# PSADT Skill Setup & Optional Intune Upload — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a first-run Setup (Phase 0) with persistent config, self-healing prerequisites (PSADT module + content-prep tool), optional Microsoft Graph upload, the HTML deliverable switch, and an English translation to the `psadt-deploy` skill.

**Architecture:** Hybrid — security/complexity lives in committed PowerShell helper scripts under `scripts/` (tested with Pester); the wizard and per-app customizing stay model-driven in `SKILL.md`. Machine-local state (`config.json`, `secret.dpapi`, `tools/`) is gitignored. The client secret is DPAPI-encrypted (CurrentUser) and entered via the user's terminal, never the chat.

**Tech Stack:** Windows PowerShell 5.1 / PowerShell 7+, Pester v5 (tests), Microsoft Graph REST API (Intune Win32 upload), Windows DPAPI via `ConvertFrom-SecureString`/`ConvertTo-SecureString`.

**Repo / working dir:** `c:\Temp\claude.code\claude-code-psadt-skill` (== installed skill folder layout). Spec: `docs/superpowers/specs/2026-06-04-psadt-skill-setup-design.md`.

---

## Conventions for every task

- **Skill root resolution** inside any `scripts/*.ps1`: `$SkillRoot = Split-Path $PSScriptRoot -Parent`. All scripts accept an optional `-SkillRoot` param (default as above) so Pester can point them at a temp dir.
- **Config keys** (use these EXACT names everywhere): `paths.packageRoot`, `paths.outputRoot`, `paths.intuneWinAppUtil`; `tooling.intuneWinAppUtilVersion`, `tooling.intuneWinAppUtilSha`, `tooling.psadtModuleVersion`; `language.script`, `language.dossier`; `author.person`, `author.company`; `intune.uploadEnabled`, `intune.tenantId`, `intune.clientId`, `intune.secretRef`, `intune.defaultAssignment`.
- **Tests live in** `tests/` mirroring script names: `tests/<Name>.Tests.ps1`.
- **Run tests** with: `Invoke-Pester -Path tests/<Name>.Tests.ps1 -Output Detailed`
- **Commits** are per-task (after the task's tests pass). Push to `main` is done by the human/skill operator, not inside steps.
- Scripts emit **objects/strings**, never `Write-Host`. Errors via `throw`. No secret ever printed.

---

## Task 0: Test harness bootstrap

**Files:**
- Create: `tests/_helpers.ps1`
- Modify: `.gitignore`

- [ ] **Step 1: Ensure Pester v5 is available**

Run:
```powershell
$p = Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1
if (-not $p -or $p.Version.Major -lt 5) { Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck }
(Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1).Version
```
Expected: a version `>= 5.5.0` printed.

- [ ] **Step 2: Create a shared test helper that builds a throwaway skill root**

Create `tests/_helpers.ps1`:
```powershell
function New-TempSkillRoot {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("psadtskill_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'scripts')    -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'tools')      -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'references') -Force | Out-Null
    # copy the scripts under test into the temp root so -SkillRoot wiring is realistic
    $srcScripts = Join-Path $PSScriptRoot '..\scripts'
    if (Test-Path $srcScripts) { Copy-Item "$srcScripts\*" (Join-Path $root 'scripts') -Force }
    return $root
}
function Remove-TempSkillRoot([string]$Path) {
    if ($Path -and (Test-Path $Path)) { Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue }
}
```

- [ ] **Step 3: Add the tests output dir guard to .gitignore**

Add these lines to `.gitignore`:
```
# Pester / test artifacts
testResults*.xml
```

- [ ] **Step 4: Commit**

```bash
git add tests/_helpers.ps1 .gitignore
git commit -m "test: add Pester harness and temp-skill-root helper"
```

---

## Task 1: `Get-PsadtConfig.ps1` — read config + report missing fields

**Files:**
- Create: `scripts/Get-PsadtConfig.ps1`
- Test: `tests/Get-PsadtConfig.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Get-PsadtConfig.Tests.ps1`:
```powershell
. "$PSScriptRoot/_helpers.ps1"
Describe 'Get-PsadtConfig' {
    BeforeEach { $script:root = New-TempSkillRoot }
    AfterEach  { Remove-TempSkillRoot $script:root }
    $script = { & (Join-Path $script:root 'scripts/Get-PsadtConfig.ps1') -SkillRoot $script:root }

    It 'reports Exists=$false and all required fields missing when no config' {
        $r = & $script
        $r.Exists | Should -BeFalse
        $r.Missing | Should -Contain 'paths.packageRoot'
        $r.Missing | Should -Contain 'author.person'
    }

    It 'returns Exists=$true and empty Missing for a complete config' {
        @{
            version=1
            paths=@{ packageRoot='c:\p'; outputRoot='c:\o'; intuneWinAppUtil='c:\t\x.exe' }
            language=@{ script='EN'; dossier='DE' }
            author=@{ person='Pat'; company='PHAT' }
        } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $script:root 'config.json')
        $r = & $script
        $r.Exists | Should -BeTrue
        $r.Missing | Should -BeNullOrEmpty
    }

    It 'requires intune fields only when uploadEnabled is true' {
        @{
            version=1
            paths=@{ packageRoot='c:\p'; outputRoot='c:\o'; intuneWinAppUtil='c:\t\x.exe' }
            language=@{ script='EN'; dossier='DE' }
            author=@{ person='Pat'; company='PHAT' }
            intune=@{ uploadEnabled=$true; secretRef='secret.dpapi' }
        } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $script:root 'config.json')
        $r = & $script
        $r.Missing | Should -Contain 'intune.tenantId'
        $r.Missing | Should -Contain 'intune.secret'
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester -Path tests/Get-PsadtConfig.Tests.ps1 -Output Detailed`
Expected: FAIL — script file not found / cannot be invoked.

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/Get-PsadtConfig.ps1`:
```powershell
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
    $ref = if ($cfg.intune.secretRef) { $cfg.intune.secretRef } else { 'secret.dpapi' }
    if (-not (Test-Path (Join-Path $SkillRoot $ref))) { $missing.Add('intune.secret') }
}
[pscustomobject]@{ Exists = $true; Config = $cfg; Missing = $missing.ToArray(); Path = $configPath }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester -Path tests/Get-PsadtConfig.Tests.ps1 -Output Detailed`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/Get-PsadtConfig.ps1 tests/Get-PsadtConfig.Tests.ps1
git commit -m "feat: add Get-PsadtConfig with missing-field detection"
```

---

## Task 2: `Set-PsadtConfig.ps1` — write/merge config + DPAPI-encrypt secret

**Files:**
- Create: `scripts/Set-PsadtConfig.ps1`
- Test: `tests/Set-PsadtConfig.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Set-PsadtConfig.Tests.ps1`:
```powershell
. "$PSScriptRoot/_helpers.ps1"
Describe 'Set-PsadtConfig' {
    BeforeEach { $script:root = New-TempSkillRoot }
    AfterEach  { Remove-TempSkillRoot $script:root }
    $set = { param($h) & (Join-Path $script:root 'scripts/Set-PsadtConfig.ps1') -SkillRoot $script:root @h }

    It 'creates config.json with nested values' {
        & $set @{ Updates = @{ 'paths.packageRoot'='c:\p'; 'author.person'='Pat' } }
        $cfg = Get-Content (Join-Path $script:root 'config.json') -Raw | ConvertFrom-Json
        $cfg.paths.packageRoot | Should -Be 'c:\p'
        $cfg.author.person     | Should -Be 'Pat'
        $cfg.version           | Should -Be 1
    }

    It 'merges into an existing config without dropping prior keys' {
        & $set @{ Updates = @{ 'paths.packageRoot'='c:\p' } }
        & $set @{ Updates = @{ 'author.company'='PHAT' } }
        $cfg = Get-Content (Join-Path $script:root 'config.json') -Raw | ConvertFrom-Json
        $cfg.paths.packageRoot | Should -Be 'c:\p'
        $cfg.author.company    | Should -Be 'PHAT'
    }

    It 'DPAPI-encrypts the secret to secret.dpapi and never to config.json' {
        $sec = ConvertTo-SecureString 'p@ss-w0rd!' -AsPlainText -Force
        & $set @{ Secret = $sec }
        $blob = Get-Content (Join-Path $script:root 'secret.dpapi') -Raw
        $blob | Should -Not -BeNullOrEmpty
        $blob | Should -Not -Match 'p@ss-w0rd'
        (Get-Content (Join-Path $script:root 'config.json') -Raw) | Should -Not -Match 'p@ss-w0rd'
        # round-trip
        $back = ConvertTo-SecureString $blob
        [System.Net.NetworkCredential]::new('', $back).Password | Should -Be 'p@ss-w0rd!'
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester -Path tests/Set-PsadtConfig.Tests.ps1 -Output Detailed`
Expected: FAIL — script not found.

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/Set-PsadtConfig.ps1`:
```powershell
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
# Load existing config as a nested hashtable, or start fresh
function ConvertTo-HashtableDeep($obj) {
    if ($obj -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-HashtableDeep $p.Value }
        return $h
    }
    return $obj
}
$config = if (Test-Path $configPath) {
    ConvertTo-HashtableDeep (Get-Content $configPath -Raw | ConvertFrom-Json)
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
    $enc = ConvertFrom-SecureString $Secret   # Windows DPAPI, CurrentUser scope
    Set-Content -Path (Join-Path $SkillRoot 'secret.dpapi') -Value $enc -Encoding ASCII -NoNewline
}
# Intentionally returns nothing (no secret echo).
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester -Path tests/Set-PsadtConfig.Tests.ps1 -Output Detailed`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/Set-PsadtConfig.ps1 tests/Set-PsadtConfig.Tests.ps1
git commit -m "feat: add Set-PsadtConfig with deep merge and DPAPI secret encryption"
```

---

## Task 3: `Get-PsadtModule.ps1` — self-heal the PSAppDeployToolkit module

**Files:**
- Create: `scripts/Get-PsadtModule.ps1`
- Test: `tests/Get-PsadtModule.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Get-PsadtModule.Tests.ps1`:
```powershell
. "$PSScriptRoot/_helpers.ps1"
Describe 'Get-PsadtModule' {
    BeforeEach { $script:root = New-TempSkillRoot }
    AfterEach  { Remove-TempSkillRoot $script:root }
    $run = { & (Join-Path $script:root 'scripts/Get-PsadtModule.ps1') -SkillRoot $script:root }

    It 'installs the module when none is present' {
        Mock -CommandName Get-Module     -MockWith { @() }
        Mock -CommandName Install-Module -MockWith { }
        Mock -CommandName Find-Module    -MockWith { [pscustomobject]@{ Version = [version]'4.1.0' } }
        $r = & $run
        Should -Invoke Install-Module -Times 1
        $r.Action | Should -Be 'Installed'
    }

    It 'does not install when a usable version exists' {
        Mock -CommandName Get-Module     -MockWith { [pscustomobject]@{ Version = [version]'4.1.0' } }
        Mock -CommandName Install-Module -MockWith { }
        Mock -CommandName Find-Module    -MockWith { [pscustomobject]@{ Version = [version]'4.1.0' } }
        $r = & $run
        Should -Invoke Install-Module -Times 0
        $r.Action | Should -Be 'AlreadyCurrent'
    }

    It 'reports UpdateAvailable when newer exists but does not auto-update' {
        Mock -CommandName Get-Module     -MockWith { [pscustomobject]@{ Version = [version]'4.0.0' } }
        Mock -CommandName Install-Module -MockWith { }
        Mock -CommandName Find-Module    -MockWith { [pscustomobject]@{ Version = [version]'4.1.0' } }
        $r = & $run
        Should -Invoke Install-Module -Times 0
        $r.Action      | Should -Be 'UpdateAvailable'
        $r.Latest      | Should -Be '4.1.0'
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester -Path tests/Get-PsadtModule.Tests.ps1 -Output Detailed`
Expected: FAIL — script not found.

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/Get-PsadtModule.ps1`:
```powershell
<#
.SYNOPSIS  Ensures the PSAppDeployToolkit module is installed; never a manual hurdle.
.OUTPUTS   PSCustomObject: Action(Installed|AlreadyCurrent|UpdateAvailable|InstallFailed), Installed, Latest
#>
[CmdletBinding()]
param([string]$SkillRoot = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
$name = 'PSAppDeployToolkit'

$local = Get-Module -ListAvailable -Name $name | Sort-Object Version -Descending | Select-Object -First 1
$latest = $null
try { $latest = Find-Module -Name $name -ErrorAction Stop } catch { }

if (-not $local) {
    try {
        Install-Module -Name $name -Scope CurrentUser -Force -AllowClobber
        $local = Get-Module -ListAvailable -Name $name | Sort-Object Version -Descending | Select-Object -First 1
        return [pscustomobject]@{ Action='Installed'; Installed="$($local.Version)"; Latest="$($latest.Version)" }
    } catch {
        return [pscustomobject]@{ Action='InstallFailed'; Installed=$null; Latest="$($latest.Version)"; Error="$_" }
    }
}
if ($latest -and $latest.Version -gt $local.Version) {
    return [pscustomobject]@{ Action='UpdateAvailable'; Installed="$($local.Version)"; Latest="$($latest.Version)" }
}
[pscustomobject]@{ Action='AlreadyCurrent'; Installed="$($local.Version)"; Latest="$($latest.Version)" }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester -Path tests/Get-PsadtModule.Tests.ps1 -Output Detailed`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/Get-PsadtModule.ps1 tests/Get-PsadtModule.Tests.ps1
git commit -m "feat: add Get-PsadtModule to self-heal the PSADT prerequisite"
```

---

## Task 4: `Get-IntuneWinAppUtil.ps1` — provision + version-check the content-prep tool

**Files:**
- Create: `scripts/Get-IntuneWinAppUtil.ps1`
- Test: `tests/Get-IntuneWinAppUtil.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Get-IntuneWinAppUtil.Tests.ps1`:
```powershell
. "$PSScriptRoot/_helpers.ps1"
Describe 'Get-IntuneWinAppUtil' {
    BeforeEach { $script:root = New-TempSkillRoot }
    AfterEach  { Remove-TempSkillRoot $script:root }
    $run = { & (Join-Path $script:root 'scripts/Get-IntuneWinAppUtil.ps1') -SkillRoot $script:root }

    It 'downloads the exe when missing and records version + sha' {
        Mock -CommandName Invoke-RestMethod -MockWith { @{ tag_name = 'v1.8.7' } }
        Mock -CommandName Invoke-WebRequest -MockWith { Set-Content (Join-Path $script:root 'tools/IntuneWinAppUtil.exe') 'MZ' }
        $r = & $run
        Should -Invoke Invoke-WebRequest -Times 1
        $r.Action  | Should -Be 'Downloaded'
        $r.Version | Should -Be 'v1.8.7'
        (Test-Path (Join-Path $script:root 'tools/IntuneWinAppUtil.exe')) | Should -BeTrue
    }

    It 'is a no-op when present and version matches config' {
        Set-Content (Join-Path $script:root 'tools/IntuneWinAppUtil.exe') 'MZ'
        @{ version=1; tooling=@{ intuneWinAppUtilVersion='v1.8.7' } } |
            ConvertTo-Json -Depth 5 | Set-Content (Join-Path $script:root 'config.json')
        Mock -CommandName Invoke-RestMethod -MockWith { @{ tag_name = 'v1.8.7' } }
        Mock -CommandName Invoke-WebRequest -MockWith { }
        $r = & $run
        Should -Invoke Invoke-WebRequest -Times 0
        $r.Action | Should -Be 'AlreadyCurrent'
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester -Path tests/Get-IntuneWinAppUtil.Tests.ps1 -Output Detailed`
Expected: FAIL — script not found.

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/Get-IntuneWinAppUtil.ps1`:
```powershell
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

$tag = if ($latestTag) { $latestTag } else { 'v1.8.7' }   # offline fallback to a known-good tag
try {
    New-Item (Split-Path $exe -Parent) -ItemType Directory -Force | Out-Null
    Invoke-WebRequest "https://github.com/$repo/raw/$tag/IntuneWinAppUtil.exe" -OutFile $exe
    # record the version in config (create config if absent)
    & (Join-Path $PSScriptRoot 'Set-PsadtConfig.ps1') -SkillRoot $SkillRoot -Updates @{ 'tooling.intuneWinAppUtilVersion' = $tag }
    return [pscustomobject]@{ Action='Downloaded'; Version=$tag; Path=$exe }
} catch {
    if (Test-Path $exe) { return [pscustomobject]@{ Action='AlreadyCurrent'; Version=$installedVersion; Path=$exe } }
    return [pscustomobject]@{ Action='UpdateFailed'; Version=$null; Path=$exe; Error="$_" }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester -Path tests/Get-IntuneWinAppUtil.Tests.ps1 -Output Detailed`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/Get-IntuneWinAppUtil.ps1 tests/Get-IntuneWinAppUtil.Tests.ps1
git commit -m "feat: add Get-IntuneWinAppUtil with version check and offline fallback"
```

---

## Task 5: `Test-PsadtSetup.ps1` — Graph auth smoke test

**Files:**
- Create: `scripts/Test-PsadtSetup.ps1`
- Test: `tests/Test-PsadtSetup.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Test-PsadtSetup.Tests.ps1`:
```powershell
. "$PSScriptRoot/_helpers.ps1"
Describe 'Test-PsadtSetup' {
    BeforeEach {
        $script:root = New-TempSkillRoot
        @{ version=1; intune=@{ uploadEnabled=$true; tenantId='t'; clientId='c'; secretRef='secret.dpapi' } } |
            ConvertTo-Json -Depth 6 | Set-Content (Join-Path $script:root 'config.json')
        Set-Content (Join-Path $script:root 'secret.dpapi') (ConvertFrom-SecureString (ConvertTo-SecureString 's3cret' -AsPlainText -Force))
    }
    AfterEach { Remove-TempSkillRoot $script:root }
    $run = { & (Join-Path $script:root 'scripts/Test-PsadtSetup.ps1') -SkillRoot $script:root }

    It 'returns Ok when token + graph GET succeed' {
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Uri -match 'oauth2/v2.0/token' } -MockWith { @{ access_token = 'abc' } }
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Uri -match 'graph.microsoft.com' }   -MockWith { @{ value = @(@{ id = '1' }) } }
        (& $run).Ok | Should -BeTrue
    }

    It 'returns a clear reason when token acquisition fails' {
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Uri -match 'oauth2/v2.0/token' } -MockWith { throw 'AADSTS7000215 invalid client secret' }
        $r = & $run
        $r.Ok     | Should -BeFalse
        $r.Reason | Should -Match 'secret'
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester -Path tests/Test-PsadtSetup.Tests.ps1 -Output Detailed`
Expected: FAIL — script not found.

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/Test-PsadtSetup.ps1`:
```powershell
<#
.SYNOPSIS  Smoke-tests the Graph app-only auth: acquire token + one Graph GET.
.OUTPUTS   PSCustomObject: Ok(bool), Reason(string)
#>
[CmdletBinding()]
param([string]$SkillRoot = (Split-Path $PSScriptRoot -Parent))
$cfg = (Get-Content (Join-Path $SkillRoot 'config.json') -Raw | ConvertFrom-Json)
$in  = $cfg.intune
$secBlob = Get-Content (Join-Path $SkillRoot ($in.secretRef ?? 'secret.dpapi')) -Raw
$secret  = [System.Net.NetworkCredential]::new('', (ConvertTo-SecureString $secBlob)).Password

try {
    $tokenResp = Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$($in.tenantId)/oauth2/v2.0/token" `
        -Body @{ client_id=$in.clientId; scope='https://graph.microsoft.com/.default'; client_secret=$secret; grant_type='client_credentials' }
    $token = $tokenResp.access_token
} catch {
    $msg = "$_"
    $reason = if ($msg -match 'AADSTS7000215|invalid client secret|secret') { 'Invalid client secret — re-run setup to re-enter it.' }
              elseif ($msg -match 'AADSTS700016|application.*not found')      { 'Client/Tenant id wrong — app not found in this tenant.' }
              else { "Token request failed: $msg" }
    return [pscustomobject]@{ Ok=$false; Reason=$reason }
}
try {
    Invoke-RestMethod -Uri 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps?$top=1' `
        -Headers @{ Authorization = "Bearer $token" } | Out-Null
    return [pscustomobject]@{ Ok=$true; Reason='Auth + Graph read OK.' }
} catch {
    return [pscustomobject]@{ Ok=$false; Reason="Token OK but Graph call failed (missing DeviceManagementApps.ReadWrite.All / admin consent?): $_" }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester -Path tests/Test-PsadtSetup.Tests.ps1 -Output Detailed`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/Test-PsadtSetup.ps1 tests/Test-PsadtSetup.Tests.ps1
git commit -m "feat: add Test-PsadtSetup Graph auth smoke test"
```

---

## Task 6: `Invoke-IntuneWin32Upload.ps1` — Graph upload (unit-mocked) + manual integration

**Files:**
- Create: `scripts/Invoke-IntuneWin32Upload.ps1`
- Test: `tests/Invoke-IntuneWin32Upload.Tests.ps1`

> Note: the real block-blob upload needs a tenant; unit tests mock every network call. A live integration check is in Task 11.

- [ ] **Step 1: Write the failing test**

Create `tests/Invoke-IntuneWin32Upload.Tests.ps1`:
```powershell
. "$PSScriptRoot/_helpers.ps1"
Describe 'Invoke-IntuneWin32Upload (mocked)' {
    BeforeEach {
        $script:root = New-TempSkillRoot
        @{ version=1; intune=@{ uploadEnabled=$true; tenantId='t'; clientId='c'; secretRef='secret.dpapi'; defaultAssignment='available' } } |
            ConvertTo-Json -Depth 6 | Set-Content (Join-Path $script:root 'config.json')
        Set-Content (Join-Path $script:root 'secret.dpapi') (ConvertFrom-SecureString (ConvertTo-SecureString 's' -AsPlainText -Force))
        $script:iw = Join-Path $script:root 'App.intunewin'
        Set-Content $script:iw 'fake'
    }
    AfterEach { Remove-TempSkillRoot $script:root }

    It 'returns AppId and PortalUrl on a clean mocked run' {
        Mock -CommandName Invoke-RestMethod -ParameterFilter { $Uri -match 'oauth2/v2.0/token' } -MockWith { @{ access_token='tok' } }
        Mock -CommandName Invoke-RestMethod -MockWith { @{ id='app-123'; value=@() } }
        $r = & (Join-Path $script:root 'scripts/Invoke-IntuneWin32Upload.ps1') -SkillRoot $script:root `
                -IntuneWinPath $script:iw -DisplayName 'Demo' -Version '1.0' -InstallCommand 'x' -UninstallCommand 'y' -SkipContentUpload
        $r.AppId    | Should -Be 'app-123'
        $r.PortalUrl | Should -Match 'app-123'
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester -Path tests/Invoke-IntuneWin32Upload.Tests.ps1 -Output Detailed`
Expected: FAIL — script not found.

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/Invoke-IntuneWin32Upload.ps1`:
```powershell
<#
.SYNOPSIS  Uploads a .intunewin to Intune as a win32LobApp via Microsoft Graph.
.DESCRIPTION
  Acquires an app-only token (client secret, DPAPI-decrypted in-memory), creates the win32LobApp,
  then (unless -SkipContentUpload) creates a content version, block-blob uploads the encrypted payload
  using the .intunewin's own Detection.xml encryption metadata, and commits. Idempotent on
  DisplayName+Version. Sets assignment per config defaultAssignment.
.OUTPUTS  PSCustomObject: AppId, PortalUrl
#>
[CmdletBinding()]
param(
    [string]$SkillRoot = (Split-Path $PSScriptRoot -Parent),
    [Parameter(Mandatory)][string]$IntuneWinPath,
    [Parameter(Mandatory)][string]$DisplayName,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$InstallCommand,
    [Parameter(Mandatory)][string]$UninstallCommand,
    [string]$LogoPath,
    [switch]$SkipContentUpload    # used by unit tests to bypass the blob upload
)
$ErrorActionPreference = 'Stop'
$cfg = Get-Content (Join-Path $SkillRoot 'config.json') -Raw | ConvertFrom-Json
$in  = $cfg.intune
$secret = [System.Net.NetworkCredential]::new('', (ConvertTo-SecureString (Get-Content (Join-Path $SkillRoot ($in.secretRef ?? 'secret.dpapi')) -Raw))).Password

$token = (Invoke-RestMethod -Method Post `
    -Uri "https://login.microsoftonline.com/$($in.tenantId)/oauth2/v2.0/token" `
    -Body @{ client_id=$in.clientId; scope='https://graph.microsoft.com/.default'; client_secret=$secret; grant_type='client_credentials' }).access_token
$secret = $null
$H = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
$base = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'

# Idempotency: look for an existing app with same name + version
$existing = (Invoke-RestMethod -Headers $H -Uri "$base`?`$filter=isof('microsoft.graph.win32LobApp')").value |
    Where-Object { $_.displayName -eq $DisplayName -and $_.displayVersion -eq $Version } | Select-Object -First 1
if ($existing) {
    Write-Verbose "App '$DisplayName' $Version already exists ($($existing.id))."
    $app = $existing
} else {
    $body = @{
        '@odata.type'         = '#microsoft.graph.win32LobApp'
        displayName           = $DisplayName
        displayVersion        = $Version
        publisher             = $cfg.author.company
        installCommandLine    = $InstallCommand
        uninstallCommandLine  = $UninstallCommand
        setupFilePath         = 'Invoke-AppDeployToolkit.exe'
        fileName              = [System.IO.Path]::GetFileName($IntuneWinPath)
        installExperience     = @{ runAsAccount = 'system' }
        returnCodes           = @(
            @{ returnCode=0; type='success' }, @{ returnCode=1707; type='success' },
            @{ returnCode=3010; type='softReboot' }, @{ returnCode=1641; type='hardReboot' },
            @{ returnCode=1618; type='retry' }
        )
    } | ConvertTo-Json -Depth 8
    $app = Invoke-RestMethod -Method Post -Headers $H -Uri $base -Body $body
}

if (-not $SkipContentUpload) {
    # Detailed block-blob upload (content version -> encrypt info from Detection.xml -> Azure block blob -> commit)
    # is implemented here against the existing $app.id. See references and Task 11 for the live walk-through.
    & (Join-Path $PSScriptRoot 'Invoke-IntuneWin32Upload.Content.ps1') -Token $token -AppId $app.id -IntuneWinPath $IntuneWinPath
}

if ($LogoPath -and (Test-Path $LogoPath)) {
    $logo = @{ largeIcon = @{ '@odata.type'='#microsoft.graph.mimeContent'; type='image/png'; value=[Convert]::ToBase64String([IO.File]::ReadAllBytes($LogoPath)) } } | ConvertTo-Json -Depth 6
    Invoke-RestMethod -Method Patch -Headers $H -Uri "$base/$($app.id)" -Body $logo | Out-Null
}

[pscustomobject]@{
    AppId     = $app.id
    PortalUrl = "https://intune.microsoft.com/#view/Microsoft_Intune_Apps/SettingsMenu/~/0/appId/$($app.id)"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester -Path tests/Invoke-IntuneWin32Upload.Tests.ps1 -Output Detailed`
Expected: PASS (1 test).

- [ ] **Step 5: Create the content-upload helper (split out for focus)**

Create `scripts/Invoke-IntuneWin32Upload.Content.ps1`:
```powershell
<#
.SYNOPSIS  Block-blob uploads the .intunewin payload to the app's content version and commits it.
.NOTES     Extracts IntuneWinPackage/Contents/<file>.intunewin (encrypted payload) and
           IntuneWinPackage/Metadata/Detection.xml (EncryptionInfo) from the .intunewin (a zip),
           creates a mobileAppContentFile, uploads to the returned Azure Storage SAS URI in
           <=4 MiB blocks, then commits with the EncryptionInfo. Implement against Graph beta:
           /mobileApps/{id}/microsoft.graph.win32LobApp/contentVersions/{cv}/files/{fid}
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Token,
    [Parameter(Mandatory)][string]$AppId,
    [Parameter(Mandatory)][string]$IntuneWinPath
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$work = Join-Path ([IO.Path]::GetTempPath()) ("iw_" + [guid]::NewGuid().ToString('N'))
[System.IO.Compression.ZipFile]::ExtractToDirectory($IntuneWinPath, $work)
try {
    [xml]$meta = Get-Content (Join-Path $work 'IntuneWinPackage/Metadata/Detection.xml') -Raw
    $enc = $meta.ApplicationInfo.EncryptionInfo
    $payload = Join-Path $work ('IntuneWinPackage/Contents/' + $meta.ApplicationInfo.FileName)
    $H = @{ Authorization = "Bearer $Token"; 'Content-Type' = 'application/json' }
    $appBase = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$AppId/microsoft.graph.win32LobApp"

    $cv  = Invoke-RestMethod -Method Post -Headers $H -Uri "$appBase/contentVersions" -Body '{}'
    $fileBody = @{ '@odata.type'='#microsoft.graph.mobileAppContentFile'; name=([IO.Path]::GetFileName($payload)); size=[int64]$meta.ApplicationInfo.UnencryptedContentSize; sizeEncrypted=([IO.FileInfo]$payload).Length; isDependency=$false } | ConvertTo-Json
    $file = Invoke-RestMethod -Method Post -Headers $H -Uri "$appBase/contentVersions/$($cv.id)/files" -Body $fileBody

    # poll for azureStorageUri
    do { Start-Sleep -Milliseconds 800; $st = Invoke-RestMethod -Headers $H -Uri "$appBase/contentVersions/$($cv.id)/files/$($file.id)" } until ($st.azureStorageUri)

    # block upload (<=4 MiB)
    $blockIds = @(); $i = 0; $fs = [IO.File]::OpenRead($payload); $buf = New-Object byte[] (4MB)
    while (($read = $fs.Read($buf,0,$buf.Length)) -gt 0) {
        $id = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(('{0:d4}' -f $i)))
        Invoke-RestMethod -Method Put -Uri ("$($st.azureStorageUri)&comp=block&blockid=$id") -Headers @{ 'x-ms-blob-type'='BlockBlob' } -Body $buf[0..($read-1)] | Out-Null
        $blockIds += $id; $i++
    }
    $fs.Close()
    $xml = '<?xml version="1.0" encoding="utf-8"?><BlockList>' + (($blockIds | ForEach-Object { "<Latest>$_</Latest>" }) -join '') + '</BlockList>'
    Invoke-RestMethod -Method Put -Uri ("$($st.azureStorageUri)&comp=blocklist") -Body $xml | Out-Null

    $commit = @{ fileEncryptionInfo = @{
        encryptionKey=$enc.EncryptionKey; macKey=$enc.MacKey; initializationVector=$enc.InitializationVector
        mac=$enc.Mac; profileIdentifier='ProfileVersion1'; fileDigest=$enc.FileDigest; fileDigestAlgorithm=$enc.FileDigestAlgorithm } } | ConvertTo-Json -Depth 6
    Invoke-RestMethod -Method Post -Headers $H -Uri "$appBase/contentVersions/$($cv.id)/files/$($file.id)/commit" -Body $commit | Out-Null
    do { Start-Sleep -Milliseconds 800; $st = Invoke-RestMethod -Headers $H -Uri "$appBase/contentVersions/$($cv.id)/files/$($file.id)" } until ($st.uploadState -eq 'commitFileSuccess')
    Invoke-RestMethod -Method Patch -Headers $H -Uri $appBase -Body (@{ '@odata.type'='#microsoft.graph.win32LobApp'; committedContentVersion="$($cv.id)" } | ConvertTo-Json) | Out-Null
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
```

- [ ] **Step 6: Commit**

```bash
git add scripts/Invoke-IntuneWin32Upload.ps1 scripts/Invoke-IntuneWin32Upload.Content.ps1 tests/Invoke-IntuneWin32Upload.Tests.ps1
git commit -m "feat: add Graph win32LobApp upload (app create mocked-tested + content helper)"
```

---

## Task 7: `references/app-registration.md`

**Files:**
- Create: `references/app-registration.md`

- [ ] **Step 1: Write the reference doc**

Create `references/app-registration.md` with this content (English):
```markdown
# Entra App Registration for Direct Intune Upload

The optional direct upload uses an app-only Graph token. Create a registration **once** per tenant.
Skip this entirely in tenants where you cannot register apps — the skill falls back to manual upload.

## Steps

1. **Entra Admin Center** → *App registrations* → *New registration*. Name e.g. `psadt-intune-upload`.
   Single tenant is fine. No redirect URI needed.
2. **API permissions** → *Add a permission* → *Microsoft Graph* → **Application permissions** →
   add `DeviceManagementApps.ReadWrite.All`.
3. **Grant admin consent** for the tenant (the status column must read "Granted").
4. **Certificates & secrets** → *New client secret* → copy the **Value** immediately (shown once).
5. Note the **Directory (tenant) ID** and **Application (client) ID** from the Overview page.
6. Run the skill setup (or `psadt setup`), choose *Intune upload: Yes*, and enter tenant id + client id.
   The skill prints a terminal one-liner to enter the secret securely (it is DPAPI-encrypted locally).

## Least privilege

`DeviceManagementApps.ReadWrite.All` is the only permission required to create and content-upload a
Win32 LOB app and assign it. Do not grant broader scopes.
```

- [ ] **Step 2: Commit**

```bash
git add references/app-registration.md
git commit -m "docs: add Entra app-registration walkthrough"
```

---

## Task 8: SKILL.md — add Phase 0 (Setup) and the DPAPI info block

**Files:**
- Modify: `SKILL.md` (insert a new "Phase 0" before the existing "### 1. Intake"; add a security/DPAPI subsection)

> Implementation note: insert Phase 0 as the first numbered step of the "## Ablauf" section and renumber nothing else (existing Intake stays "1." conceptually; label the new section "### 0. Setup (Phase 0)").

- [ ] **Step 1: Add the Phase 0 section**

Insert immediately before the line `### 1. Intake (sofort am Anfang, bevor irgendwas anderes)`:
```markdown
### 0. Setup (Phase 0 — run before Intake)

Before anything else, ensure the skill is configured and prerequisites are present.

1. Run `pwsh scripts/Get-PsadtConfig.ps1`. If `Exists` is true and `Missing` is empty, skip to Intake.
2. If config is missing/incomplete, run the **setup wizard** — ask only the missing values, ALWAYS via
   `AskUserQuestion` (clickable), recommended option first:
   - **Paths**: `paths.packageRoot`, `paths.outputRoot`, `paths.intuneWinAppUtil` (offer current defaults).
   - **Languages**: `language.script` (EN), `language.dossier` (DE).
   - **Author**: `author.person`, `author.company`.
   - **Intune upload**: Yes / No / Later. If Yes: `intune.tenantId`, `intune.clientId`, `intune.defaultAssignment`.
3. Persist answers with `scripts/Set-PsadtConfig.ps1 -Updates @{ ... }`.
4. **Secret (only if upload = Yes): NEVER ask for it in chat.** Print this terminal one-liner for the user
   to run themselves (it reads the secret hidden and DPAPI-encrypts it):
   ```powershell
   $s = Read-Host 'Client secret' -AsSecureString; pwsh '<skill>/scripts/Set-PsadtConfig.ps1' -Secret $s
   ```
5. Provision prerequisites (never block the user):
   - `pwsh scripts/Get-PsadtModule.ps1` — installs/updates PSAppDeployToolkit.
   - `pwsh scripts/Get-IntuneWinAppUtil.ps1` — downloads/updates the content-prep tool into `tools/`.
6. If upload = Yes, run `pwsh scripts/Test-PsadtSetup.ps1`. Only set `intune.uploadEnabled = $true`
   after `Ok = $true`. On failure, show `Reason` and point to `references/app-registration.md`.
7. Re-trigger anytime the user says "psadt setup" to change individual values.
```

- [ ] **Step 2: Add the DPAPI info block**

Append this subsection at the end of the `## Konventionen (VERBINDLICH)` block:
```markdown
### How the client secret is stored (DPAPI)

If a user asks how their secret is handled: encryption is automatic in `Set-PsadtConfig.ps1` using
Windows **DPAPI** (`ConvertFrom-SecureString`, scope CurrentUser). The user enters the secret in their
own terminal via `Read-Host -AsSecureString` — it never enters the chat transcript. The blob in
`secret.dpapi` is bound to user + machine (worthless if copied elsewhere), decrypted only in-memory at
upload time, and never written to `config.json` or any log. On secret rotation, re-run setup.
```

- [ ] **Step 3: Verify SKILL.md still parses as a skill (frontmatter intact)**

Run:
```powershell
$t = Get-Content SKILL.md -Raw
if ($t -notmatch '(?s)^---\s*\nname:\s*psadt-deploy') { throw 'frontmatter broken' } else { 'OK' }
```
Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add SKILL.md
git commit -m "feat: add Phase 0 setup wizard and DPAPI secret docs to SKILL.md"
```

---

## Task 9: SKILL.md — config-instead-of-hardcode + Intune upload phase + HTML switch

**Files:**
- Modify: `SKILL.md`

- [ ] **Step 1: Replace hard-coded values with config references**

Make these edits in `SKILL.md` (search → replace the surrounding guidance):
- Where the output folder is stated as `c:\Temp\PSADTv4\Output\<App>\`, add: "(default; actual value
  comes from `paths.outputRoot` in config — read it via `Get-PsadtConfig`)".
- Where IntuneWinAppUtil is fetched to `C:\Tools\IntuneWinAppUtil.exe`, replace the acquisition block
  with: "use `paths.intuneWinAppUtil` from config; it is provisioned by `scripts/Get-IntuneWinAppUtil.ps1`".
- Where author is stated `Patrick Taubert, PHAT Consulting GmbH`, add: "(default; composed from
  `author.person` + `author.company` in config)".

- [ ] **Step 2: Add the optional Intune upload phase**

Insert a new section after "### 6. Packen mit IntuneWinAppUtil" titled "### 6.5 Intune upload (optional)":
```markdown
### 6.5 Intune upload (optional)

Only if `intune.uploadEnabled` is true (read via `Get-PsadtConfig`). Otherwise keep the existing manual
flow (hand the user the `.intunewin` + dossier to upload in the Admin Center) — this is the explicit
fallback for tenants without app-registration rights.

Even when enabled, offer a per-run opt-out via `AskUserQuestion` (e.g. customer tenant). To upload:
```powershell
pwsh scripts/Invoke-IntuneWin32Upload.ps1 -IntuneWinPath '<out>\<App>.intunewin' `
    -DisplayName '<App>' -Version '<ver>' -InstallCommand 'Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent' `
    -UninstallCommand 'Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent' -LogoPath '<out>\<App>-Logo.png'
```
Show the returned `AppId` + `PortalUrl` to the user.
```

- [ ] **Step 3: Switch the deliverable convention from Markdown to HTML**

In the conventions block and in "### 7. Intune-Dossier":
- Rename the dossier deliverable from `Intune-Dossier.md` to **`Intune-Dossier.html`** and state it is full HTML.
- Change "App-Beschreibung IMMER in Markdown formatieren" to "App-Beschreibung IMMER in **HTML** formatieren"
  and replace the Markdown example block with an HTML example (`<strong>`, `<ul><li>`, `<a href>`, `<p>`).
- Keep: German umlauts in the dossier output; scripts stay EN/ASCII.
- In "## Anti-Patterns", change any "Markdown" deliverable references to "HTML".

- [ ] **Step 4: Verify no leftover `.md` dossier references remain**

Run:
```powershell
$t = Get-Content SKILL.md -Raw
if ($t -match 'Intune-Dossier\.md') { throw 'stale .md dossier reference' } else { 'OK' }
```
Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
git add SKILL.md
git commit -m "feat: config-driven values, optional upload phase, HTML dossier convention"
```

---

## Task 10: English translation of SKILL.md and the reference guide

**Files:**
- Modify: `SKILL.md`
- Modify: `references/PSADTv4-Deployment-Guide.md`

> Translation rules (apply to BOTH files): translate all prose and comments to natural technical English.
> PRESERVE: the YAML frontmatter `name`/`description` keys (translate the description text to English),
> all PowerShell code blocks and cmdlet names verbatim, file paths, the `0.1` start-version and changelog
> convention. Keep exactly ONE deliberate German element: any **example** of dossier/Company-Portal
> output stays German with real umlauts (it is end-user text) — label such blocks "(German — end-user output)".

- [ ] **Step 1: Translate `SKILL.md` to English**

Translate section by section, top to bottom, preserving structure and all code blocks. Update the
frontmatter `description` to English while keeping the German/English trigger phrases that users actually
type (e.g. keep "PSADT paket bauen" as a trigger, since users say it in German). After translating, the
only German left should be: trigger phrases in the description, and any explicitly labelled German
end-user dossier example.

- [ ] **Step 2: Verify SKILL.md frontmatter + skill still loads**

Run:
```powershell
$t = Get-Content SKILL.md -Raw
if ($t -notmatch '(?s)^---\s*\nname:\s*psadt-deploy\s*\ndescription:\s*\S') { throw 'frontmatter broken' } else { 'OK' }
```
Expected: `OK`.

- [ ] **Step 3: Translate `references/PSADTv4-Deployment-Guide.md` to English**

Translate all prose (appendices A–G) to English; keep code, paths, error codes, and cmdlet names verbatim.
Keep any German dossier/Company-Portal example blocks German and label them.

- [ ] **Step 4: Spot-check there is no accidental German left in headings**

Run:
```powershell
$bad = Select-String -Path SKILL.md,references/PSADTv4-Deployment-Guide.md -Pattern '^\#.*(?:ä|ö|ü|ß|Anhang|Voraussetzung|Sprache)' -CaseSensitive
if ($bad) { $bad | ForEach-Object { $_.Line }; throw 'German left in headings' } else { 'OK' }
```
Expected: `OK` (review any hits; legitimate German-output example headings should be labelled, not raw).

- [ ] **Step 5: Commit**

```bash
git add SKILL.md references/PSADTv4-Deployment-Guide.md
git commit -m "i18n: translate SKILL.md and reference guide to English (dossier output stays German)"
```

---

## Task 11: Full-suite green + live integration checklist

**Files:**
- Create: `tests/Run-All.ps1`

- [ ] **Step 1: Add a runner**

Create `tests/Run-All.ps1`:
```powershell
Invoke-Pester -Path "$PSScriptRoot" -Output Detailed -CI
```

- [ ] **Step 2: Run the whole suite**

Run: `pwsh tests/Run-All.ps1`
Expected: all tests PASS, exit code 0.

- [ ] **Step 3: Manual live integration (requires a real test tenant + app registration)**

Document the run in the PR description; do NOT automate (needs real credentials):
1. `psadt setup` → enter test tenant id/client id, secret via the printed one-liner.
2. `pwsh scripts/Test-PsadtSetup.ps1` → expect `Ok = $true`.
3. Build a tiny test `.intunewin`, then run `Invoke-IntuneWin32Upload.ps1` WITHOUT `-SkipContentUpload`.
4. Confirm in Intune the app exists, content version shows `commitFileSuccess`, logo set.
5. Delete the test app from the tenant afterwards.

- [ ] **Step 4: Commit**

```bash
git add tests/Run-All.ps1
git commit -m "test: add full-suite runner and live integration checklist"
```

---

## Task 12: Sync into the installed skill + final README status

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Flip the Status section**

In `README.md`, change the "Status" section: move first-run setup, self-healing prerequisites, optional
Graph upload, and HTML deliverables from "(in progress)" to shipped; keep a short "Verified via Pester +
one live tenant run" note.

- [ ] **Step 2: Install into the live skill folder**

Run (PowerShell):
```powershell
$dst = "$env:USERPROFILE\.claude\skills\psadt-deploy"
Copy-Item .\SKILL.md $dst -Force
Copy-Item .\scripts -Destination $dst -Recurse -Force
Copy-Item .\references -Destination $dst -Recurse -Force
'installed'
```
Expected: `installed`; the skill folder now contains scripts/ + references/.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: mark setup/upload/tool/HTML features as shipped"
```

---

## Self-Review (completed by plan author)

- **Spec coverage:** §3 file structure → Tasks 1–7; §4 config schema → Tasks 1–2 (keys), 4 (tooling);
  §5.1–5.7 components → Tasks 1–7; §6.1 Phase 0 → Task 8; §6.2 config-instead-of-hardcode → Task 9.1;
  §6.3 upload phase → Task 9.2; §6.4 HTML → Task 9.3; §6.5 DPAPI info → Task 8.2; §6.6 translation →
  Task 10; §7 security → Tasks 2 (DPAPI), 8 (terminal entry), 0/Task-0 gitignore (already in repo);
  §8 error handling → Tasks 3,4,5 return shapes; §9 tests → Tasks 1–6, 11.
- **Placeholder scan:** none — every code step contains complete code; translation tasks are concrete
  actions with explicit preservation rules, not "TODO".
- **Type/name consistency:** config keys, script names, and `-SkillRoot`/`-Updates`/`-Secret` params are
  used identically across tasks; `Invoke-IntuneWin32Upload` returns `AppId`/`PortalUrl` in both impl and test.
