BeforeAll {
    . "$PSScriptRoot/_helpers.ps1"
    Import-Module PowerShellGet -MinimumVersion 2.0 -ErrorAction Stop
}
Describe 'Get-PsadtModule' {
    BeforeEach {
        $script:root = New-TempSkillRoot
        $script:run  = { . (Join-Path $script:root 'scripts/Get-PsadtModule.ps1') -SkillRoot $script:root }
    }
    AfterEach { Remove-TempSkillRoot $script:root }

    It 'installs the module when none is present' {
        Mock -CommandName Get-Module     -MockWith { @() }
        Mock -CommandName Install-Module -MockWith { }
        Mock -CommandName Find-Module    -MockWith { [pscustomobject]@{ Version = [version]'4.1.0' } }
        $r = & $script:run
        Should -Invoke Install-Module -Times 1
        $r.Action | Should -Be 'Installed'
    }

    It 'does not install when a usable version exists' {
        Mock -CommandName Get-Module     -MockWith { [pscustomobject]@{ Version = [version]'4.1.0' } }
        Mock -CommandName Install-Module -MockWith { }
        Mock -CommandName Find-Module    -MockWith { [pscustomobject]@{ Version = [version]'4.1.0' } }
        $r = & $script:run
        Should -Invoke Install-Module -Times 0
        $r.Action | Should -Be 'AlreadyCurrent'
    }

    It 'reports UpdateAvailable when newer exists but does not auto-update' {
        Mock -CommandName Get-Module     -MockWith { [pscustomobject]@{ Version = [version]'4.0.0' } }
        Mock -CommandName Install-Module -MockWith { }
        Mock -CommandName Find-Module    -MockWith { [pscustomobject]@{ Version = [version]'4.1.0' } }
        $r = & $script:run
        Should -Invoke Install-Module -Times 0
        $r.Action | Should -Be 'UpdateAvailable'
        $r.Latest | Should -Be '4.1.0'
    }
}
