# Runs the whole skill test suite. REQUIRES Pester v5 (the tests use v5-only syntax: Should -Invoke,
# -ExpectedMessage, $TestDrive, BeforeAll/BeforeEach). On a stock Windows PowerShell 5.1 box the built-in
# Pester is 3.4 and would fail with a wall of confusing errors - so fail fast with a clear message instead.
$pester = Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester -or $pester.Version.Major -lt 5) {
    throw "Pester v5+ is required (found: $(if ($pester) { $pester.Version } else { 'none' })). Install with: Install-Module Pester -MinimumVersion 5.0 -Force -Scope CurrentUser"
}
Import-Module $pester.Path -Force
Invoke-Pester -Path "$PSScriptRoot" -Output Detailed -CI
