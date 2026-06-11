#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
    Tests for scripts/Invoke-IntuneWin32Upload.ps1 parameter guards. These validate at PARAM BINDING (before
    any Graph call), so no network / .intunewin fixture is needed: a bad value must fail fast, a good value
    must pass binding (the body then fails on the dummy path, which proves binding let it through).
#>

BeforeAll {
    $script:Upload = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\Invoke-IntuneWin32Upload.ps1')).Path
    $script:DummyWin = 'C:\__nonexistent__\nope.intunewin'
}

Describe '-MinWindowsRelease ValidateSet' {
    It 'rejects a server-unknown release label (21H2) at binding' {
        { & $script:Upload -IntuneWinPath $script:DummyWin -DisplayName 'X' -MinWindowsRelease '21H2' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*MinWindowsRelease*'
    }
    It 'accepts a backend-valid release (1809) - passes binding, then fails on the dummy path' {
        { & $script:Upload -IntuneWinPath $script:DummyWin -DisplayName 'X' -MinWindowsRelease '1809' -DetectionScriptPath $script:DummyWin -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*not found*'
    }
}

Describe '-MsiProductCode / -MsiUpgradeCode GUID ValidatePattern' {
    It 'rejects a non-GUID ProductCode at binding' {
        { & $script:Upload -IntuneWinPath $script:DummyWin -DisplayName 'X' -MsiProductCode 'not-a-guid' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*MsiProductCode*'
    }
    It 'accepts a brace-wrapped GUID ProductCode (passes binding)' {
        { & $script:Upload -IntuneWinPath $script:DummyWin -DisplayName 'X' -MsiProductCode '{12345678-1234-1234-1234-123456789abc}' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*not found*'
    }
    It 'accepts a bare GUID UpgradeCode (passes binding)' {
        { & $script:Upload -IntuneWinPath $script:DummyWin -DisplayName 'X' -MsiProductCode '12345678-1234-1234-1234-123456789abc' -MsiUpgradeCode '87654321-4321-4321-4321-cba987654321' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*not found*'
    }
}
